--!strict
-- The pure anti-cheat arithmetic: allowances per state, the lag credit, verdicts, the sliding window and the kick policy.
local Rules = Harness.load("src/server/anticheat/Rules")
local Combat = Harness.load("src/shared/data/combat")
local World = Harness.load("src/shared/data/world")
local Arts = Harness.load("src/shared/data/arts")
local Playground = Harness.load("src/shared/data/playground")

local interval = Combat.anticheatSampleInterval
local cap = Combat.maxSpeedStudsPerSecond
-- The speed check's tolerance on the cap (D-052): a sample may travel the cap times this.
local margin = Combat.speedMargin
-- The full lag credit: the sprint cap over the section 17 lag budget, spent once rather than per sample.
local credit = cap * Combat.lagAllowance
-- The sprint allowance over `seconds` with a full credit: the cap and its margin over the time plus the credit.
local function allowance(seconds: number): number
	return cap * margin * seconds + credit
end
-- One sample's allowance without credit, and with a full one.
local base = cap * margin * interval
local sprint = allowance(interval)
-- What an honest sprint at exactly the cap travels in one sample.
local honest = cap * interval

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
	it(
		"outside any action the allowance is the sprint cap and its margin over the interval, plus the credit passed",
		function()
			expect(Rules.allowedDistance(interval, { state = "Idle" }, Combat)).toBeCloseTo(base, 1e-9)
			expect(Rules.allowedDistance(interval, { state = "Moving" }, Combat)).toBeCloseTo(base, 1e-9)
			expect(Rules.allowedDistance(interval, { state = "Guard" }, Combat)).toBeCloseTo(base, 1e-9)
			expect(Rules.allowedDistance(interval, { state = "Stagger" }, Combat)).toBeCloseTo(base, 1e-9)
			expect(Rules.allowedDistance(1, { state = "Idle" }, Combat)).toBeCloseTo(cap * margin, 1e-9)
			-- The margin is a tolerance for jitter, not a second sprint: a tenth over the cap at most.
			expect(margin).toBeGreaterThan(1)
			expect(margin).toBeLessThanOrEqual(1.1)
			-- The lag credit is added once, whatever the interval: it is not a per-second bonus.
			expect(Rules.allowedDistance(interval, { state = "Idle" }, Combat, nil, credit)).toBeCloseTo(sprint, 1e-9)
			expect(Rules.allowedDistance(1, { state = "Idle" }, Combat, nil, credit)).toBeCloseTo(allowance(1), 1e-9)
			expect(Rules.allowedDistance(interval, { state = "Idle" }, Combat, nil, 1)).toBeCloseTo(base + 1, 1e-9)
			-- The lag budget is real: the client sprints at exactly the cap and replication jitters.
			expect(Combat.lagAllowance).toBeGreaterThan(0)
			expect(Rules.maxCredit(Combat)).toBeCloseTo(credit, 1e-9)
			expect(Rules.maxCredit(Combat)).toBeGreaterThan(0)
		end
	)

	it("mid-Art adds the known Art's rootMotion plus the slack", function()
		local leap = Arts.byId("OneHandedSword.SonicLeap")
		expect(leap).toBeTruthy()
		local allowed = Rules.allowedDistance(interval, { state = "Art" }, Combat, leap.rootMotion)
		expect(allowed).toBeCloseTo(base + leap.rootMotion + Combat.rootMotionSlack, 1e-9)
		expect(Rules.allowedDistance(interval, { state = "Art" }, Combat, leap.rootMotion, credit)).toBeCloseTo(
			sprint + leap.rootMotion + Combat.rootMotionSlack,
			1e-9
		)
		-- A basic swing is an Art with no root motion of its own: only the slack.
		expect(Rules.allowedDistance(interval, { state = "Art" }, Combat, 0)).toBeCloseTo(
			base + Combat.rootMotionSlack,
			1e-9
		)
		-- The lock after the last hit still covers the carried motion.
		expect(Rules.allowedDistance(interval, { state = "PostMotion" }, Combat, leap.rootMotion)).toBeCloseTo(
			base + leap.rootMotion + Combat.rootMotionSlack,
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
			base + largest + Combat.rootMotionSlack,
			1e-9
		)
		-- No weapon at all: the largest Art of every category.
		local overall = Rules.maxRootMotion(nil)
		expect(overall).toBeGreaterThanOrEqual(largest)
		expect(Rules.allowedDistance(interval, { state = "Art" }, Combat)).toBeCloseTo(
			base + overall + Combat.rootMotionSlack,
			1e-9
		)
		expect(Rules.categoryOf({ state = "Idle" })).toBe(nil)
		expect(Rules.categoryOf({ state = "Idle", weaponId = "NoSuchWeapon" })).toBe(nil)
	end)

	it("mid-Dodge adds the dodge distance and a negative interval never goes below the credit", function()
		expect(Rules.allowedDistance(interval, { state = "Dodge" }, Combat)).toBeCloseTo(
			base + Combat.dodgeDistance,
			1e-9
		)
		expect(Rules.allowedDistance(-1, { state = "Idle" }, Combat)).toBe(0)
		expect(Rules.allowedDistance(0, { state = "Idle" }, Combat)).toBe(0)
		expect(Rules.allowedDistance(-1, { state = "Idle" }, Combat, nil, credit)).toBeCloseTo(allowance(0), 1e-9)
		expect(Rules.allowedDistance(0, { state = "Idle" }, Combat, nil, credit)).toBeCloseTo(allowance(0), 1e-9)
	end)

	it("no Art plus the slack and a full credit ever reaches the teleport distance in one sample", function()
		local most = Rules.allowedDistance(interval, { state = "Art" }, Combat, nil, credit)
		expect(most).toBeLessThan(Combat.teleportFlagDistance)
	end)
end)

describe("Rules lag credit", function()
	-- Plays `deltas` (studs per sample, Idle) through the credit bucket from full; returns how many
	-- samples were flagged and the index of the first one (nil when none).
	local function play(deltas: { number }, grants: { number }?): (number, number?)
		local left = Rules.maxCredit(Combat)
		local flagged = 0
		local first: number? = nil
		for index, delta in deltas do
			local allowed = base + (if grants ~= nil then grants[index] or 0 else 0)
			if Rules.evaluate(delta, allowed + left, Combat).kind ~= "ok" then
				flagged += 1
				first = first or index
			end
			left = Rules.nextCredit(left, allowed, delta, Combat)
		end
		return flagged, first
	end

	it("is spent by travel past the allowance and refilled by travel under it, within 0..maxCredit", function()
		expect(Rules.nextCredit(credit, base, base, Combat)).toBeCloseTo(credit, 1e-9)
		expect(Rules.nextCredit(credit, base, base + 1, Combat)).toBeCloseTo(credit - 1, 1e-9)
		expect(Rules.nextCredit(1, base, base - 0.5, Combat)).toBeCloseTo(1.5, 1e-9)
		-- Never above the full credit, never below zero.
		expect(Rules.nextCredit(credit, base, 0, Combat)).toBeCloseTo(credit, 1e-9)
		expect(Rules.nextCredit(0, base, base * 10, Combat)).toBe(0)
		expect(Rules.nextCredit(credit, base, base + credit * 2, Combat)).toBe(0)
	end)

	it("an honest sprint at the cap with replication jitter of nearly the whole lag is never flagged", function()
		local jitter = credit - 0.1
		local deltas = {}
		for index = 1, 400 do
			-- A reading that lags behind, then one that catches up: the root moved base studs each time.
			table.insert(deltas, if index % 2 == 1 then base - jitter else base + jitter)
		end
		expect((play(deltas))).toBe(0)
		-- The same at exactly the cap, where the margin refills the credit on every sample.
		deltas = {}
		for index = 1, 400 do
			table.insert(deltas, if index % 2 == 1 then honest - jitter else honest + jitter)
		end
		expect((play(deltas))).toBe(0)
		-- The credit starts full, so a first reading that catches up on a lag from before is fine too.
		expect((play({ base + jitter, base, base, base - jitter, base + jitter }))).toBe(0)
	end)

	it("a sustained walk at 1.5x the cap drains the credit and is flagged on every sample after", function()
		local deltas = {}
		for _ = 1, 400 do
			table.insert(deltas, base * 1.5)
		end
		local flagged, first = play(deltas)
		expect(first).toBeTruthy()
		expect(first).toBeLessThanOrEqual(3)
		expect(flagged).toBe(#deltas - (first :: number) + 1)
		-- The old per-sample lag grant let this run forever: 1.5x the cap fits base plus the full credit.
		expect(base * 1.5).toBeLessThanOrEqual(sprint)
	end)

	it("an Art's unused grant refills the credit instead of emptying it", function()
		local grant = 20 + Combat.rootMotionSlack
		local jitter = credit - 0.1
		-- The Art carries the body its whole rootMotion, the reading lags, then the lag catches up.
		local flagged = play({ base + 20, base, base + jitter }, { grant, 0, 0 })
		expect(flagged).toBe(0)
		-- Refilling against the bare sprint term would have emptied the credit after the Art.
		expect(Rules.nextCredit(credit, base + grant, base + 20, Combat)).toBeCloseTo(credit, 1e-9)
	end)

	it("an honest sprint read a little past the cap on every sample is never flagged (D-052)", function()
		-- The Studio play-test kick: a 15 s sprint at the cap, read 6.5 studs over 16 frames (allowed
		-- 6.4 with no margin), 1.6 % past the cap on every sample.
		local frames = 16 / 60
		local over = 6.5 / (cap * frames)
		expect(over).toBeLessThan(margin)
		local deltas = {}
		for _ = 1, 240 do
			table.insert(deltas, honest * over)
		end
		expect((play(deltas))).toBe(0)
		-- With no margin the credit drains and every reading after it is flagged: the old kick.
		local noMargin = table.clone(Combat)
		noMargin.speedMargin = 1
		local left = Rules.maxCredit(noMargin)
		local flagged = 0
		local bare = cap * interval
		for _, delta in deltas do
			if Rules.evaluate(delta, bare + left, noMargin).kind ~= "ok" then
				flagged += 1
			end
			left = Rules.nextCredit(left, bare, delta, noMargin)
		end
		expect(flagged).toBeGreaterThanOrEqual(Combat.anomalyKickThreshold)
	end)

	-- Ten minutes of an honest sprint at exactly the cap, sampled on 15 to 17 frame boundaries. The
	-- server's reading of the root lags it by `lagAt(index)` seconds; every `stallEvery` samples the
	-- reading freezes for one sample, then catches up. Returns the heaviest window weight, how many
	-- samples were flagged, and whether the player was ever kicked.
	local function sprintRun(lagAt: (index: number) -> number, stallEvery: number): (number, number, boolean)
		local list = {}
		local left = Rules.maxCredit(Combat)
		local truth, lastReading, now = 0, 0, 0
		local kicked, worst, flagged = false, 0, 0
		local frames = { 16, 15, 17, 16, 17, 15 } -- a fixed shuffle of the sampler's step
		for index = 1, 2400 do
			local dt = frames[index % #frames + 1] / 60
			now += dt
			truth += cap * dt
			local reading = if index % stallEvery == 0 then lastReading else truth - cap * lagAt(index)
			local delta = reading - lastReading
			lastReading = reading
			local allowed = cap * margin * dt
			local verdict = Rules.evaluate(delta, allowed + left, Combat)
			left = Rules.nextCredit(left, allowed, delta, Combat)
			if verdict.kind ~= "ok" then
				flagged += 1
				table.insert(list, { at = now, weight = verdict.weight, reason = verdict.reason })
			end
			Rules.prune(list, now, Combat)
			worst = math.max(worst, Rules.weight(list, now, Combat))
			kicked = kicked or Rules.shouldKick(list, now, Combat)
		end
		return worst, flagged, kicked
	end

	-- A fixed-seed generator, so every run is the same.
	local function generator(seed: number): () -> number
		local state = seed
		return function(): number
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
	end

	it("an honest sprint with a typical connection is never flagged, a stall at most once", function()
		-- The lag drifts between 30 and 120 ms; a 0.25 s stall every 30 s.
		local random = generator(12345)
		local lag = 0.075
		local worst, flagged, kicked = sprintRun(function()
			lag = math.clamp(lag + (random() - 0.5) * 0.02, 0.03, 0.12)
			return lag
		end, 120)
		expect(kicked).toBe(false)
		expect(flagged).toBeLessThanOrEqual(2400 // 120)
		expect(worst).toBeLessThanOrEqual(1)
	end)

	it("an honest sprint with the worst connection the lag budget allows is never kicked", function()
		-- Every reading lags by anything from 0 to the whole lag budget, independently, and a 0.25 s
		-- stall comes every 10 s: harsher than any connection that can play.
		local random = generator(777)
		local worst, _, kicked = sprintRun(function()
			return random() * Combat.lagAllowance
		end, 40)
		expect(kicked).toBe(false)
		expect(worst).toBeLessThan(Combat.anomalyKickThreshold)
	end)

	it("a body over the cap times the margin is flagged on every sample once the credit drains", function()
		local deltas = {}
		for _ = 1, 120 do
			table.insert(deltas, honest * (margin + 0.1))
		end
		local flagged, first = play(deltas)
		expect(first).toBeTruthy()
		expect(flagged).toBe(#deltas - (first :: number) + 1)
		-- At 1.2x the cap it takes a few seconds at most to start flagging every sample.
		expect((first :: number) * interval).toBeLessThan(5)
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
		expect(verdict.weight).toBe(1) -- 41 studs, a sample's allowance of them legitimate: one teleport distance
		expect(verdict.reason:find(World.anticheat.reasons.teleport, 1, true)).toBe(1)
		local far = Rules.evaluate(200, sprint, Combat)
		expect(far.weight).toBe(math.ceil((200 - sprint) / Combat.teleportFlagDistance))
		expect(far.weight).toBe(5)
		-- Mid-Art the allowance explains more of the jump.
		local midArt = Rules.evaluate(200, sprint + 20 + Combat.rootMotionSlack, Combat)
		expect(midArt.weight).toBe(math.ceil((200 - 30) / Combat.teleportFlagDistance))
	end)

	it("a long lag spike makes the allowance generous: a legitimate run is not a teleport", function()
		local lagged = Rules.allowedDistance(2, { state = "Idle" }, Combat, nil, credit)
		expect(lagged).toBeCloseTo(allowance(2), 1e-9)
		-- The interval scales the cap term; the credit is still added once.
		expect(Rules.allowedDistance(2, { state = "Idle" }, Combat)).toBeGreaterThan(Combat.teleportFlagDistance)
		expect(Rules.evaluate(Combat.teleportFlagDistance + 1, lagged, Combat).kind).toBe("ok")
		-- A hair over it after a long spike carries the smallest weight.
		expect(Rules.evaluate(lagged + 0.5, lagged, Combat).weight).toBe(1)
	end)

	it(
		"teleport weight is capped at teleportWeightCapFraction of the kick threshold so one anomaly can never kick",
		function()
			local most = math.floor(Combat.anomalyKickThreshold * World.anticheat.teleportWeightCapFraction)
			expect(Rules.teleportWeight(1e6, Combat)).toBe(most)
			expect(Rules.teleportWeight(1e6, Combat, sprint)).toBe(most)
			expect(Rules.teleportWeight(Combat.teleportFlagDistance, Combat)).toBe(1)
			expect(Rules.teleportWeight(Combat.teleportFlagDistance + 1, Combat, sprint)).toBe(1)
			expect(Rules.teleportWeight(0, Combat, 100)).toBe(1)
			expect(Rules.evaluate(1e6, sprint, Combat).weight).toBeLessThan(Combat.anomalyKickThreshold)
		end
	)

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
		-- Weight counts, not just events: two anomalies whose weights sum to the threshold reach it.
		local two = { flag(0, threshold - 1), flag(1, 1) }
		expect(Rules.shouldKick(two, 1, Combat)).toBe(true)
		expect(Rules.shouldKick({ flag(0, threshold - 2), flag(1, 1) }, 1, Combat)).toBe(false)
	end)

	it("flags slide out of the window and the kick with them", function()
		local list = flags(threshold, 0)
		expect(Rules.shouldKick(list, window - 1, Combat)).toBe(true)
		expect(Rules.shouldKick(list, window, Combat)).toBe(false)
		expect(Rules.shouldKick(list, window + 1, Combat)).toBe(false)
	end)

	it("shadows at shadowFraction of the threshold, before any kick", function()
		local shadowAt = threshold * World.anticheat.shadowFraction
		local half = math.ceil(shadowAt)
		expect(Rules.shouldShadow(flags(half, 0), 0, Combat)).toBe(true)
		expect(Rules.shouldShadow(flags(half - 1, 0), 0, Combat)).toBe(false)
		expect(Rules.shouldKick(flags(half, 0), 0, Combat)).toBe(false)
		-- A single heavy teleport can shadow but never kick.
		local one = { flag(0, Rules.teleportWeight(200, Combat)) }
		expect(Rules.shouldShadow(one, 0, Combat)).toBe(Rules.teleportWeight(200, Combat) >= shadowAt)
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
