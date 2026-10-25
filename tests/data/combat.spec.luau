--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local combat = Harness.load("src/shared/data/combat")

-- tools/validators/combat.luau reads combat.luau through ctx.load and requires nothing, so it loads
-- as a plain chunk; `override` replaces fields of a copy of the real table.
-- `modules` stands in for other modules by path (a clip, say).
local function runValidator(override: { [string]: any }?, modules: { [string]: any }?): { string }
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
			local standIn = if modules ~= nil then modules[modulePath] else nil
			if standIn ~= nil then
				return standIn
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
	it("steps the arc one hit radius at a time, at most 12 sub-samples a frame", function()
		expect(combat.hitSampleHz).toBe(60)
		expect(combat.hitSphereRadius).toBe(1.2)
		expect(combat.maxTargetsPerWindow).toBe(6)
		-- Tied to the radius: a blade passing through a target touches it at a sample with half the
		-- radius to spare.
		expect(combat.sweepMaxTipStep).toBe(combat.hitSphereRadius)
		expect(combat.sweepMaxSubdivisions).toBe(12)
	end)

	it("a fighter beside the swing is cut by the blade itself: its edge in the body (D-275)", function()
		expect(combat.besideHitRadius).toBe(0.15)
		local blade = Harness.load("src/shared/data/weaponModels").categories.OneHandedSword.blade
		-- No wider than half the blade: the drawn edge reaches the body before it counts.
		expect(combat.besideHitRadius <= blade.width / 2).toBe(true)
		expect(combat.besideHitRadius > 0).toBe(true)
		-- The test follows the drawn arc closely: a chord of the follow step strays from an arc
		-- around the shoulder (3 studs or more) by far less than the radius.
		expect(combat.besideFollowStep).toBe(0.3)
		expect(combat.besideFollowStep ^ 2 / (8 * 3)).toBeLessThan(combat.besideHitRadius / 10)
		expect(combat.besideMaxSubdivisions).toBe(16)
	end)

	it("a root has jumped past 90 studs a second over the time and the lag, 1.25 x honest travel", function()
		expect(combat.sweepMaxRootSpeed).toBe(90)
		expect(combat.sweepRootSpeedMargin).toBe(1.25)
		-- One server frame and the full lag credit allow 15 studs: a sprint and a whole dodge reaching
		-- the server at once (12) stay under it.
		local frame = combat.sweepMaxRootSpeed * (1 / combat.hitSampleHz + combat.lagAllowance)
		expect(frame).toBeCloseTo(15, 1e-9)
		local burst = combat.maxSpeedStudsPerSecond * (1 / combat.hitSampleHz + combat.lagAllowance)
			+ combat.dodgeDistance
		expect(burst).toBeLessThan(frame)
		-- The credit is spent once, so over one anti-cheat sample the sweep follows at most 36 studs:
		-- under what the anti-cheat calls a teleport (40).
		local sample = combat.sweepMaxRootSpeed * (combat.anticheatSampleInterval + combat.lagAllowance)
		expect(sample).toBeCloseTo(36, 1e-9)
		expect(sample).toBeLessThan(combat.teleportFlagDistance)
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
		-- No lag allowance is legal on its own; the root speed bound must then cover the fastest
		-- single reading of a clip's root motion, which 90 does not.
		local noLag = runValidator({ lagAllowance = 0 })
		expect(#noLag).toBe(1)
		expect(mentions(noLag, "lagAllowance must")).toBe(false)
		expect(mentions(noLag, "sweepMaxRootSpeed 90 is under")).toBe(true)
	end)

	it("the validator wants the root speed bound over every honest travel by the margin", function()
		-- The fastest is the back dodge's root motion with a sprint, 70.75 studs a second: the bound
		-- needs 88.44.
		local slow = runValidator({ sweepMaxRootSpeed = 88 })
		expect(#slow).toBe(1)
		expect(mentions(slow, "sweepMaxRootSpeed 88 is under 1.25 x the fastest honest travel (70.75")).toBe(true)
		expect(mentions(slow, "player/OneHandedSword/DodgeBack")).toBe(true)
		expect(runValidator({ sweepMaxRootSpeed = 88.5 })).toEqual({})
		expect(mentions(runValidator({ sweepRootSpeedMargin = 1.3 }), "sweepMaxRootSpeed 90 is under 1.3 x")).toBe(true)
		-- A faster sprint, a longer dodge or a bigger anti-cheat allowance raises the floor.
		expect(mentions(runValidator({ maxSpeedStudsPerSecond = 40 }), "root motion")).toBe(true)
		expect(mentions(runValidator({ dodgeDistance = 20 }), "(104.00 studs a second, the dodge)")).toBe(true)
		expect(mentions(runValidator({ rootMotionSlack = 20 }), "the anti-cheat allowance")).toBe(true)
		-- The speed check's margin on the cap (D-052) stays between 1 and 1.25.
		expect(mentions(runValidator({ speedMargin = 0.95 }), "speedMargin must be a number from 1 to 1.25")).toBe(true)
		expect(mentions(runValidator({ speedMargin = 1.5 }), "speedMargin must be a number from 1 to 1.25")).toBe(true)
		expect(mentions(runValidator({ speedMargin = "1.1" }), "speedMargin must be a number")).toBe(true)
		expect(runValidator({ speedMargin = 1.25 })).toEqual({})
		-- Every player clip counts: a back dodge played twice as fast is faster travel.
		local DodgeBack = Harness.load("src/shared/clips/player/OneHandedSword/DodgeBack")
		local quick = table.clone(DodgeBack)
		quick.duration = DodgeBack.duration / 2
		quick.keys = {}
		for _, key in DodgeBack.keys do
			local copy = table.clone(key)
			copy.time = key.time / 2
			table.insert(quick.keys, copy)
		end
		local quicker = runValidator(nil, { ["src/shared/clips/player/OneHandedSword/DodgeBack"] = quick })
		expect(#quicker).toBe(1)
		expect(mentions(quicker, "player/OneHandedSword/DodgeBack")).toBe(true)
	end)

	it("the validator counts root motion by the path it travels, not the line across it", function()
		-- A swing whose root shakes 2 studs back and forth every 0.025 s: it ends where it starts and
		-- never strays 2 studs, yet every frame step spends the sweep's lag credit (80 studs a second
		-- of path, 104 with the sprint).
		local Basic1 = Harness.load("src/shared/clips/player/OneHandedSword/Basic1")
		local shaking = table.clone(Basic1)
		shaking.duration = 0.3
		shaking.keys = {}
		for index = 0, 12 do
			table.insert(shaking.keys, {
				time = index * 0.025,
				easing = "Linear",
				joints = {},
				root = { pos = { 0, 0, if index % 2 == 0 then 0 else 2 } },
			})
		end
		local problems = runValidator(nil, { ["src/shared/clips/player/OneHandedSword/Basic1"] = shaking })
		expect(#problems).toBe(1)
		expect(mentions(problems, "(104.00 studs a second, root motion (player/OneHandedSword/Basic1))")).toBe(true)
	end)

	it("the validator keeps what the sweep follows in one anti-cheat sample under a teleport", function()
		-- 90 studs a second over the 0.25 s sample plus the 13.5-stud credit: 36 studs.
		local near = runValidator({ teleportFlagDistance = 36 })
		expect(#near).toBe(1)
		expect(mentions(near, "follow the root 36.0 studs in 0.25 s")).toBe(true)
		expect(mentions(near, "not under teleportFlagDistance (36)")).toBe(true)
		expect(runValidator({ teleportFlagDistance = 36.01 })).toEqual({})
		-- At 30 one frame (15 studs) would pass, but the sweep may follow 36 over the sample.
		expect(mentions(runValidator({ teleportFlagDistance = 30 }), "follow the root")).toBe(true)
		-- A sample shorter than a frame falls back to the frame.
		local frameOnly = runValidator({ anticheatSampleInterval = 0.001, teleportFlagDistance = 15 })
		expect(mentions(frameOnly, "follow the root 15.0 studs in 0.02 s")).toBe(true)
	end)

	it("the validator wants a sound margin and a positive root speed", function()
		for _, bad in { 0.9, 0, -1, 0 / 0, "1.25" } do
			local problems = runValidator({ sweepRootSpeedMargin = bad })
			expect(#problems).toBe(1)
			expect(mentions(problems, "sweepRootSpeedMargin must be a number, 1 or more")).toBe(true)
		end
		for _, bad in { 0, -90, 0 / 0, math.huge, "90" } do
			local problems = runValidator({ sweepMaxRootSpeed = bad })
			expect(mentions(problems, "sweepMaxRootSpeed must be a positive number")).toBe(true)
		end
	end)
end)

describe("combat data: aim (D-112)", function()
	-- A copy of the real aim table with `fields` replaced, for runValidator.
	local function aimWith(fields: { [string]: any }): { [string]: any }
		local copy = table.clone(combat.aim)
		for key, value in fields do
			copy[key] = value
		end
		return copy
	end

	it("starts at the lock-facing and snap values D-112 chose", function()
		expect(combat.aim.lockTurnRate).toBe(720)
		expect(combat.aim.lockFaceWhileSprinting).toBe(false)
		expect(combat.aim.snapDegrees).toBe(40)
		expect(combat.aim.replicationMarginDegrees).toBe(9)
		expect(combat.aim.assistRange).toBe(10.5)
		expect(combat.aim.assistConeDegrees).toBe(80) -- D-275: was 90
		expect(combat.aim.assistAngleWeightStuds).toBe(6)
		expect(combat.aim.minFaceDistance).toBe(0.5)
	end)

	it("an enemy the assist picks is one the snap turns the body all the way onto (D-275)", function()
		-- The Play-test: a boar 45 degrees off was picked (cone 90) but the snap turned 40, and the
		-- cut stopped 5 short of it. Half the cone is no wider than the snap.
		expect(combat.aim.assistConeDegrees / 2).toBeLessThanOrEqual(combat.aim.snapDegrees)
	end)

	it("the snap and the replication margin stay inside the server's facing acceptance", function()
		-- facingTolerance 0.35: the server accepts a request facing within acos(0.65) = 49.46 degrees
		-- of its root. A snap the server has not seen yet plus the turn it may still be catching up on
		-- must fit inside that, or the swing is rejected and its clip cancelled.
		local acceptance = math.deg(math.acos(1 - combat.facingTolerance))
		expect(acceptance).toBeCloseTo(49.46, 0.01)
		expect(combat.aim.snapDegrees + combat.aim.replicationMarginDegrees).toBeLessThanOrEqual(acceptance)
		local over = runValidator({ aim = aimWith({ snapDegrees = 41 }) })
		expect(#over).toBe(1)
		expect(mentions(over, "aim.snapDegrees 41 + aim.replicationMarginDegrees 9")).toBe(true)
		expect(mentions(over, "49.46")).toBe(true)
		expect(mentions(runValidator({ aim = aimWith({ replicationMarginDegrees = 10 }) }), "49.46")).toBe(true)
		-- A looser facing tolerance makes room for a bigger snap.
		expect(runValidator({ aim = aimWith({ snapDegrees = 41 }), facingTolerance = 0.4 })).toEqual({})
		expect(runValidator({ aim = aimWith({ snapDegrees = 40.4 }) })).toEqual({})
	end)

	it("the validator wants every aim number sound", function()
		for _, field in { "lockTurnRate", "snapDegrees", "assistRange", "assistConeDegrees" } do
			for _, bad in { 0, -1, 0 / 0, math.huge, "5" } do
				local problems = runValidator({ aim = aimWith({ [field] = bad }) })
				expect(mentions(problems, "aim." .. field .. " must be a positive number")).toBe(true)
			end
		end
		for _, field in { "replicationMarginDegrees", "assistAngleWeightStuds", "minFaceDistance" } do
			for _, bad in { -1, 0 / 0, math.huge, "5" } do
				local problems = runValidator({ aim = aimWith({ [field] = bad }) })
				expect(mentions(problems, "aim." .. field .. " must be a number, 0 or more")).toBe(true)
			end
			expect(runValidator({ aim = aimWith({ [field] = 0 }) })).toEqual({})
		end
		-- The assist cone is a cone in front of the body: wider than a full turn means nothing.
		expect(mentions(runValidator({ aim = aimWith({ assistConeDegrees = 361 }) }), "assistConeDegrees")).toBe(true)
		expect(mentions(runValidator({ aim = aimWith({ lockFaceWhileSprinting = "no" }) }), "lockFaceWhileSprinting")).toBe(
			true
		)
		expect(mentions(runValidator({ aim = "fast" }), "aim must be a table")).toBe(true)
	end)
end)
