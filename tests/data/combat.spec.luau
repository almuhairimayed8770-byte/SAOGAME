--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local combat = Harness.load("src/shared/data/combat")

-- tools/validators/combat.luau reads combat.luau through ctx.load and requires nothing, so it loads
-- as a plain chunk; `override` replaces fields of a copy of the real table.
local function runValidator(override: { [string]: any }?): { string }
	local path = "tools/validators/combat.luau"
	local chunk = luau.load(
		fs.readFile(Harness.repoRoot() .. "/" .. path),
		{ debugName = path, environment = Harness.environment() :: any }
	)
	local validate = chunk()
	local copy = table.clone(combat)
	for key, value in override or {} do
		copy[key] = value
	end
	return validate({
		load = function(modulePath: string): any
			if modulePath == "src/shared/data/combat" then
				return copy
			end
			return Harness.load(modulePath)
		end,
		listFiles = Harness.listFiles,
		readFile = Harness.readFile,
		repoRoot = Harness.repoRoot(),
	})
end

local function mentions(problems: { string }, needle: string): boolean
	for _, problem in problems do
		if problem:find(needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

describe("combat data", function()
	it("matches the section 6 starting values", function()
		expect(combat.startPoseTime).toBe(0.15)
		expect(combat.activationHold).toBe(0.1)
		expect(combat.activationCancelTime).toBe(1.0)
		expect(combat.hitStopFrames).toEqual({ Normal = 3, Final = 6, Kill = 10 })
		expect(combat.strDamageScale).toBe(0.012)
		expect(combat.critMultiplier).toBe(1.5)
		expect(combat.guardRegenPerSecond).toBe(0.1)
		expect(combat.breakDuration).toBe(3)
		expect(combat.breakDamageMultiplier).toBe(2)
		expect(combat.switchWindow).toBe(0.8)
		expect(combat.guardConeDegrees).toBe(120)
		expect(combat.guardReduction).toBe(0.7)
		expect(combat.parryWindow).toBe(0.15)
		expect(combat.parryStagger).toBe(1.0)
		expect(combat.dodgeDuration).toBe(0.25)
		expect(combat.dodgeInvulnerability).toBe(0.1)
		expect(combat.dodgeCooldown).toBe(0.6)
		expect(combat.deathFreeze).toBe(0.5)
		expect(combat.lagAllowance).toBe(0.15)
	end)

	it("telegraph wind-ups respect the hard-rule floor", function()
		expect(combat.telegraphMinWindUp).toBeGreaterThanOrEqual(0.3)
		expect(combat.telegraphDefaultWindUp).toBeGreaterThanOrEqual(combat.telegraphMinWindUp)
		expect(combat.telegraphMaxWindUp).toBeLessThanOrEqual(1.2)
	end)

	it("the death freeze ducks every sound group deep enough to read as silence", function()
		expect(combat.deathDuckDb).toBe(40)
		-- 30 dB leaves about 3% of the amplitude; anything shallower still reads as sound under the freeze.
		expect(combat.deathDuckDb).toBeGreaterThanOrEqual(30)
		expect(combat.deathDuckDb).toBeGreaterThan(combat.lowHpMusicDuck)
	end)

	it("section 10 camera numbers", function()
		expect(combat.cameraNudgeStuds).toBe(0.4)
		expect(combat.cameraShakeStuds).toEqual({ Normal = 0.15, Final = 0.3, Kill = 0.6 })
	end)
end)

describe("combat data: the server hit sweep", function()
	it("steps the arc one hit radius at a time, at most 4 sub-samples a frame", function()
		expect(combat.hitSampleHz).toBe(60)
		expect(combat.hitSphereRadius).toBe(1.2)
		expect(combat.maxTargetsPerWindow).toBe(6)
		-- Tied to the radius: a blade passing through a target touches it at a sample with half the
		-- radius to spare.
		expect(combat.sweepMaxTipStep).toBe(combat.hitSphereRadius)
		expect(combat.sweepMaxSubdivisions).toBe(4)
	end)

	it("the validator passes the real table", function()
		expect(runValidator()).toEqual({})
	end)

	it("the validator wants the step at most two radii and the cap a positive whole number", function()
		local wide = runValidator({ sweepMaxTipStep = combat.hitSphereRadius * 2 + 0.01 })
		expect(#wide).toBe(1)
		expect(mentions(wide, "sweepMaxTipStep")).toBe(true)
		expect(runValidator({ sweepMaxTipStep = combat.hitSphereRadius * 2 })).toEqual({})
		for _, bad in { 0, -1, 0.5, 2.5, 0 / 0, math.huge, "6" } do
			local problems = runValidator({ sweepMaxSubdivisions = bad })
			expect(#problems).toBe(1)
			expect(mentions(problems, "sweepMaxSubdivisions")).toBe(true)
		end
		for _, bad in { 0, -1.2, 0 / 0 } do
			expect(mentions(runValidator({ sweepMaxTipStep = bad }), "sweepMaxTipStep")).toBe(true)
			expect(mentions(runValidator({ hitSphereRadius = bad }), "hitSphereRadius")).toBe(true)
		end
	end)

	it("the validator wants a positive rate, a whole target cap and a lag allowance of 0 or more", function()
		expect(mentions(runValidator({ hitSampleHz = 0 }), "hitSampleHz")).toBe(true)
		expect(mentions(runValidator({ maxTargetsPerWindow = 2.5 }), "maxTargetsPerWindow")).toBe(true)
		expect(mentions(runValidator({ lagAllowance = -0.1 }), "lagAllowance")).toBe(true)
		expect(runValidator({ lagAllowance = 0 })).toEqual({})
	end)
end)
