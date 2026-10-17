--!strict
-- The pure anti-cheat arithmetic: allowances per state, verdicts, the sliding window and the kick policy.
local Rules = Harness.load("src/server/anticheat/Rules")
local Combat = Harness.load("src/shared/data/combat")
local World = Harness.load("src/shared/data/world")
local Arts = Harness.load("src/shared/data/arts")
local Playground = Harness.load("src/shared/data/playground")

local interval = Combat.anticheatSampleInterval
-- The sprint allowance of one sample: the cap over the interval plus the section 17 lag budget.
local function allowance(seconds: number): number
	return Combat.maxSpeedStudsPerSecond * (seconds + Combat.lagAllowance)
end
local sprint = allowance(interval)

local function flag(at: number, weight: number?)
	return { at = at, weight = weight or 1, reason = "test" }
end

local function flags(count: number, at: number, weight: number?)
	local list = {}
	for _ = 1, count do
		table.insert(list, flag(at, weight))
	end
	return list
end

describe("Rules.allowedDistance", function()
	it("outside any action the allowance is the sprint cap over the interval", function()
		expect(Rules.allowedDistance(interval, { state = "Idle" }, Combat)).toBeCloseTo(sprint, 1e-9)
		expect(Rules.allowedDistance(interval, { state = "Moving" }, Combat)).toBeCloseTo(sprint, 1e-9)
		expect(Rules.allowedDistance(interval, { state = "Guard" }, Combat)).toBeCloseTo(sprint, 1e-9)
		expect(Rules.allowedDistance(interval, { state = "Stagger" }, Combat)).toBeCloseTo(sprint, 1e-9)
		expect(Rules.allowedDistance(1, { state = "Idle" }, Combat)).toBeCloseTo(allowance(1), 1e-9)
		-- The lag budget is real: the client sprints at exactly the cap and replication jitters.
		expect(sprint).toBeGreaterThan(Combat.maxSpeedStudsPerSecond * interval)
		expect(Combat.lagAllowance).toBeGreaterThan(0)
	end)

	it("mid-Art adds the known Art's rootMotion plus the slack", function()
		local leap = Arts.byId("OneHandedSword.SonicLeap")
		expect(leap).toBeTruthy()
		local allowed = Rules.allowedDistance(interval, { state = "Art" }, Combat, leap.rootMotion)
		expect(allowed).toBeCloseTo(sprint + leap.rootMotion + Combat.rootMotionSlack, 1e-9)
		-- A basic swing is an Art with no root motion of its own: only the slack.
		expect(Rules.allowedDistance(interval, { state = "Art" }, Combat, 0)).toBeCloseTo(
			sprint + Combat.rootMotionSlack,
			1e-9
		)
		-- The lock after the last hit still covers the carried motion.
		expect(Rules.allowedDistance(interval, { state = "PostMotion" }, Combat, leap.rootMotion)).toBeCloseTo(
			sprint + leap.rootMotion + Combat.rootMotionSlack,
			1e-9
		)
	end)

	it("without CombatService the weapon category's largest Art is assumed", function()
		local record = { state = "Art", weaponId = Playground.loadout.weapon }
		local largest = 0
		for _, art in Arts.list("OneHandedSword") do
			largest = math.max(largest, art.rootMotion)
		end
		expect(largest).toBeGreaterThan(0)
		expect(Rules.maxRootMotion("OneHandedSword")).toBe(largest)
		expect(Rules.categoryOf(record)).toBe("OneHandedSword")
		expect(Rules.allowedDistance(interval, record, Combat)).toBeCloseTo(
			sprint + largest + Combat.rootMotionSlack,
			1e-9
		)
		-- No weapon at all: the largest Art of every category.
		local overall = Rules.maxRootMotion(nil)
		expect(overall).toBeGreaterThanOrEqual(largest)
		expect(Rules.allowedDistance(interval, { state = "Art" }, Combat)).toBeCloseTo(
			sprint + overall + Combat.rootMotionSlack,
			1e-9
		)
		expect(Rules.categoryOf({ state = "Idle" })).toBe(nil)
		expect(Rules.categoryOf({ state = "Idle", weaponId = "NoSuchWeapon" })).toBe(nil)
	end)

	it("mid-Dodge adds the dodge distance and a negative interval never goes below the lag budget", function()
		expect(Rules.allowedDistance(interval, { state = "Dodge" }, Combat)).toBeCloseTo(
			sprint + Combat.dodgeDistance,
			1e-9
		)
		expect(Rules.allowedDistance(-1, { state = "Idle" }, Combat)).toBeCloseTo(allowance(0), 1e-9)
		expect(Rules.allowedDistance(0, { state = "Idle" }, Combat)).toBeCloseTo(allowance(0), 1e-9)
	end)

	it("no Art plus the slack ever reaches the teleport distance in one sample", function()
		local most = Rules.allowedDistance(interval, { state = "Art" }, Combat)
		expect(most).toBeLessThan(Combat.teleportFlagDistance)
	end)
end)

describe("Rules.evaluate", function()
	it("inside the allowance nothing happens", function()
		local verdict = Rules.evaluate(sprint, sprint, Combat)
		expect(verdict.kind).toBe("ok")
		expect(verdict.weight).toBe(0)
		expect(Rules.evaluate(0, 0, Combat).kind).toBe("ok")
	end)

	it("over the allowance but under the teleport distance is an over-speed anomaly of speedWeight", function()
		local verdict = Rules.evaluate(sprint + 1, sprint, Combat)
		expect(verdict.kind).toBe("speed")
		expect(verdict.weight).toBe(World.anticheat.speedWeight)
		expect(verdict.reason:find(World.anticheat.reasons.speed, 1, true)).toBe(1)
		expect(verdict.delta).toBeCloseTo(sprint + 1, 1e-9)
		expect(verdict.allowed).toBeCloseTo(sprint, 1e-9)
	end)

	it("a jump past the teleport distance is a teleport weighted by the unexplained distances spanned", function()
		local verdict = Rules.evaluate(Combat.teleportFlagDistance + 1, sprint, Combat)
		expect(verdict.kind).toBe("teleport")
		expect(verdict.weight).toBe(1) -- 41 studs, 6 of them legitimate: one teleport distance
		expect(verdict.reason:find(World.anticheat.reasons.teleport, 1, true)).toBe(1)
		local far = Rules.evaluate(200, sprint, Combat)
		expect(far.weight).toBe(math.ceil((200 - sprint) / Combat.teleportFlagDistance))
		expect(far.weight).toBe(5)
		-- Mid-Art the allowance explains more of the jump.
		local midArt = Rules.evaluate(200, sprint + 20 + Combat.rootMotionSlack, Combat)
		expect(midArt.weight).toBe(math.ceil((200 - 30) / Combat.teleportFlagDistance))
	end)

	it("a long lag spike makes the allowance generous: a legitimate run is not a teleport", function()
		local lagged = Rules.allowedDistance(2, { state = "Idle" }, Combat)
		expect(lagged).toBeGreaterThan(Combat.teleportFlagDistance)
		expect(Rules.evaluate(Combat.teleportFlagDistance + 1, lagged, Combat).kind).toBe("ok")
		-- A hair over it after a long spike carries the smallest weight.
		expect(Rules.evaluate(lagged + 0.5, lagged, Combat).weight).toBe(1)
	end)

	it("teleport weight is capped at half the kick threshold so one anomaly can never kick", function()
		local cap = math.floor(Combat.anomalyKickThreshold / 2)
		expect(Rules.teleportWeight(1e6, Combat)).toBe(cap)
		expect(Rules.teleportWeight(1e6, Combat, sprint)).toBe(cap)
		expect(Rules.teleportWeight(Combat.teleportFlagDistance, Combat)).toBe(1)
		expect(Rules.teleportWeight(Combat.teleportFlagDistance + 1, Combat, sprint)).toBe(1)
		expect(Rules.teleportWeight(0, Combat, 100)).toBe(1)
		expect(Rules.evaluate(1e6, sprint, Combat).weight).toBeLessThan(Combat.anomalyKickThreshold)
	end)

	it("horizontal distance ignores the vertical axis", function()
		expect(Rules.horizontalDistance(Vector3.new(0, 0, 0), Vector3.new(3, 100, 4))).toBeCloseTo(5, 1e-5)
		expect(Rules.horizontalDistance(Vector3.new(1, 2, 3), Vector3.new(1, -50, 3))).toBe(0)
	end)
end)

describe("Rules window, shadow and kick", function()
	local threshold = Combat.anomalyKickThreshold
	local window = Combat.anomalyWindow

	it("prune drops flags older than the window in place and weight sums what is left", function()
		local list = { flag(0), flag(10), flag(20, 3), flag(29) }
		Rules.prune(list, window, Combat)
		expect(#list).toBe(3)
		expect(list[1].at).toBe(10)
		expect(Rules.weight(list, window, Combat)).toBe(5)
		expect(Rules.count(list, window, Combat)).toBe(3)
		-- weight and count respect the window without pruning.
		expect(Rules.weight(list, window + 10, Combat)).toBe(4)
		expect(Rules.count(list, window + 10, Combat)).toBe(2)
		expect(Rules.weight({}, 0, Combat)).toBe(0)
	end)

	it("the combat table defaults to combat.luau", function()
		local list = { flag(0), flag(window + 1) }
		expect(Rules.weight(list, window + 1)).toBe(1)
		expect(Rules.weight(list, window + 1, Combat)).toBe(1)
	end)

	it("never kicks on a single anomaly, however heavy", function()
		expect(Rules.shouldKick({ flag(0, threshold * 2) }, 0, Combat)).toBe(false)
		expect(Rules.shouldKick({ flag(0, threshold) }, 0, Combat)).toBe(false)
		expect(Rules.shouldKick({}, 0, Combat)).toBe(false)
	end)

	it("kicks at the threshold inside the window, not below it", function()
		expect(Rules.shouldKick(flags(threshold, 5), 5, Combat)).toBe(true)
		expect(Rules.shouldKick(flags(threshold - 1, 5), 5, Combat)).toBe(false)
		-- Weight counts, not just events: two heavy anomalies reach the threshold.
		local two = { flag(0, threshold / 2), flag(1, threshold / 2) }
		expect(Rules.shouldKick(two, 1, Combat)).toBe(true)
	end)

	it("flags slide out of the window and the kick with them", function()
		local list = flags(threshold, 0)
		expect(Rules.shouldKick(list, window - 1, Combat)).toBe(true)
		expect(Rules.shouldKick(list, window, Combat)).toBe(false)
		expect(Rules.shouldKick(list, window + 1, Combat)).toBe(false)
	end)

	it("shadows at half the threshold, before any kick", function()
		local half = math.ceil(threshold / 2)
		expect(Rules.shouldShadow(flags(half, 0), 0, Combat)).toBe(true)
		expect(Rules.shouldShadow(flags(half - 1, 0), 0, Combat)).toBe(false)
		expect(Rules.shouldKick(flags(half, 0), 0, Combat)).toBe(false)
		-- A single heavy teleport can shadow but never kick.
		local one = { flag(0, Rules.teleportWeight(200, Combat)) }
		expect(Rules.shouldShadow(one, 0, Combat)).toBe(Rules.teleportWeight(200, Combat) >= threshold / 2)
		expect(Rules.shouldKick(one, 0, Combat)).toBe(false)
	end)

	it("five 200-stud teleports inside a second are a kick; three honest over-speed samples are not", function()
		local list = {}
		for index = 1, 5 do
			local verdict = Rules.evaluate(200, sprint, Combat)
			table.insert(list, { at = index * 0.2, weight = verdict.weight, reason = verdict.reason })
		end
		expect(Rules.shouldKick(list, 1, Combat)).toBe(true)
		local honest = {}
		for index = 1, 3 do
			local verdict = Rules.evaluate(sprint + 2, sprint, Combat)
			table.insert(honest, { at = index, weight = verdict.weight, reason = verdict.reason })
		end
		expect(Rules.shouldKick(honest, 3, Combat)).toBe(false)
		expect(Rules.shouldShadow(honest, 3, Combat)).toBe(false)
	end)
end)
