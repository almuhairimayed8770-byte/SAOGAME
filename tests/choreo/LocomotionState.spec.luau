--!strict
local LocomotionState = Harness.load("src/client/choreo/LocomotionState")
local ChoreoData = Harness.load("src/shared/data/choreo")

local Config = ChoreoData.locomotion
local FRAME = 1 / 60

local function input(overrides)
	local base = {
		forward = 0,
		right = 0,
		speed = 0,
		sprinting = false,
		grounded = true,
		drawn = false,
		turning = 0,
		yawRate = 0,
		verticalVelocity = 0,
		fallHeight = nil,
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

local function sum(weights)
	local total = 0
	for _, value in weights do
		total += value
	end
	return total
end

describe("LocomotionState.directionWeights", function()
	it("maps the four axis directions to one clip each", function()
		expect(LocomotionState.directionWeights(1, 0).WalkForward).toBeCloseTo(1)
		expect(LocomotionState.directionWeights(0, 1).WalkRight).toBeCloseTo(1)
		expect(LocomotionState.directionWeights(-1, 0).WalkBack).toBeCloseTo(1)
		expect(LocomotionState.directionWeights(0, -1).WalkLeft).toBeCloseTo(1)
	end)

	it("splits a diagonal between its two neighbours and always sums to one", function()
		local diagonal = LocomotionState.directionWeights(1, 1)
		expect(diagonal.WalkForward).toBeCloseTo(0.5)
		expect(diagonal.WalkRight).toBeCloseTo(0.5)
		local backLeft = LocomotionState.directionWeights(-1, -1)
		expect(backLeft.WalkBack).toBeCloseTo(0.5)
		expect(backLeft.WalkLeft).toBeCloseTo(0.5)
		for angle = 0, 350, 10 do
			local radians = math.rad(angle)
			local weights = LocomotionState.directionWeights(math.cos(radians), math.sin(radians))
			expect(sum(weights)).toBeCloseTo(1, 1e-6)
		end
	end)
end)

describe("LocomotionState.gaitWeights", function()
	it("walks at walk speed, runs at run speed, sprints at sprint speed and blends between", function()
		local walk, run, sprint = LocomotionState.gaitWeights(Config.walkSpeed)
		expect(walk).toBe(1)
		expect(run + sprint).toBe(0)
		walk, run, sprint = LocomotionState.gaitWeights(Config.runSpeed)
		expect(run).toBeCloseTo(1)
		walk, run, sprint = LocomotionState.gaitWeights(Config.sprintSpeed)
		expect(sprint).toBeCloseTo(1)
		walk, run, sprint = LocomotionState.gaitWeights((Config.walkSpeed + Config.runSpeed) / 2)
		expect(walk).toBeCloseTo(0.5)
		expect(run).toBeCloseTo(0.5)
	end)
end)

describe("LocomotionState.update", function()
	it("stands in Idle or IdleDrawn when still", function()
		local state = LocomotionState.new()
		local out = state:update(FRAME, input())
		expect(out.weights.Idle).toBe(1)
		expect(out.phase).toBe("Idle")
		out = state:update(FRAME, input({ drawn = true }))
		expect(out.weights.IdleDrawn).toBe(1)
		expect(out.weights.Idle).toBe(0)
	end)

	it("walks forward with the direction blend and runs at run speed", function()
		local state = LocomotionState.new()
		local out = state:update(FRAME, input({ forward = 1, speed = Config.walkSpeed }))
		expect(out.weights.WalkForward).toBeCloseTo(1)
		expect(out.phase).toBe("Move")
		out = state:update(FRAME, input({ forward = 1, right = 1, speed = Config.walkSpeed }))
		expect(out.weights.WalkForward).toBeCloseTo(0.5)
		expect(out.weights.WalkRight).toBeCloseTo(0.5)
		out = state:update(FRAME, input({ forward = 1, speed = Config.runSpeed }))
		expect(out.weights.Run).toBeCloseTo(1)
		expect(sum(out.weights)).toBeCloseTo(1, 1e-6)
	end)

	it("sprinting with a drawn weapon reports the drawn-sprint additive weight", function()
		local state = LocomotionState.new()
		local out =
			state:update(FRAME, input({ forward = 1, speed = Config.sprintSpeed, sprinting = true, drawn = true }))
		expect(out.weights.Sprint).toBeCloseTo(1)
		expect(out.drawnSprint).toBeCloseTo(1)
		out = state:update(FRAME, input({ forward = 1, speed = Config.sprintSpeed, sprinting = true, drawn = false }))
		expect(out.drawnSprint).toBe(0)
	end)

	it("turns in place past the threshold, once per turn clip", function()
		local state = LocomotionState.new()
		local out = state:update(FRAME, input({ turning = Config.turnInPlaceDegrees + 1 }))
		expect(out.oneShot).toBe("TurnLeft")
		out = state:update(FRAME, input({ turning = Config.turnInPlaceDegrees + 1 }))
		expect(out.oneShot).toBeNil()
		local other = LocomotionState.new()
		expect(other:update(FRAME, input({ turning = -(Config.turnInPlaceDegrees + 1) })).oneShot).toBe("TurnRight")
		expect(other:update(Config.turnClipDuration, input({ turning = Config.turnInPlaceDegrees - 1 })).oneShot).toBeNil()
	end)

	it(
		"turns in place once the body has yawed past the threshold on the spot, and forgets the yaw when it moves",
		function()
			local state = LocomotionState.new()
			local rate = 30 -- degrees per second: the threshold takes 1.5 s
			local fired = nil
			local frames = 0
			while fired == nil and frames < 200 do
				frames += 1
				fired = state:update(FRAME, input({ yawRate = rate })).oneShot
			end
			expect(fired).toBe("TurnLeft")
			expect(frames * FRAME).toBeCloseTo(Config.turnInPlaceDegrees / rate, FRAME * 2)
			-- The accumulator restarted: the next turn needs the whole threshold again.
			for _ = 1, math.ceil(Config.turnClipDuration / FRAME) + 1 do
				expect(state:update(FRAME, input({ yawRate = rate })).oneShot).toBeNil()
			end
			-- Walking clears it: half a threshold, a step, then half a threshold again fires nothing.
			local walker = LocomotionState.new()
			for _ = 1, 40 do
				walker:update(FRAME, input({ yawRate = -rate }))
			end
			walker:update(FRAME, input({ forward = 1, speed = Config.walkSpeed }))
			walker:update(FRAME, input({ speed = 0 }))
			for _ = 1, 40 do
				expect(walker:update(FRAME, input({ yawRate = -rate })).oneShot).toBeNil()
			end
		end
	)

	it("stopping from a run is a two-step stop through the walk gait", function()
		local state = LocomotionState.new()
		state:update(FRAME, input({ forward = 1, speed = Config.runSpeed }))
		local out = state:update(FRAME, input({ speed = 0 }))
		expect(out.phase).toBe("Stopping")
		expect(out.oneShot).toBeNil()
		local sawWalk = false
		for _ = 1, math.ceil(Config.stopStepsSeconds / FRAME) do
			out = state:update(FRAME, input({ speed = 0 }))
			if out.weights.WalkForward > 0.5 then
				sawWalk = true
			end
		end
		expect(sawWalk).toBe(true)
		out = state:update(FRAME, input({ speed = 0 }))
		expect(out.phase).toBe("Idle")
		expect(out.weights.Idle).toBe(1)
	end)

	it("stopping from above the skid threshold plays Skid", function()
		local state = LocomotionState.new()
		state:update(FRAME, input({ forward = 1, speed = Config.sprintSpeed, sprinting = true }))
		local out = state:update(FRAME, input({ speed = 0 }))
		expect(out.oneShot).toBe("Skid")
		expect(out.phase).toBe("Stopping")
	end)

	it(
		"leaving the ground plays Jump when rising and Fall when dropping, landing plays Land scaled by fall height",
		function()
			local state = LocomotionState.new()
			local out = state:update(FRAME, input({ grounded = false, verticalVelocity = Config.jumpVelocity * 10 }))
			expect(out.oneShot).toBe("Jump")
			expect(out.airborne).toBe(true)
			out = state:update(FRAME, input({ grounded = false, verticalVelocity = -1 }))
			expect(out.oneShot).toBeNil()
			out = state:update(FRAME, input({ grounded = true, fallHeight = Config.landing.fullSquashHeight * 2 }))
			expect(out.oneShot).toBe("Land")
			expect(out.oneShotWeight).toBe(1)

			local other = LocomotionState.new()
			expect(other:update(FRAME, input({ grounded = false, verticalVelocity = -5 })).oneShot).toBe("Fall")
			local land = other:update(FRAME, input({ grounded = true, fallHeight = 0 }))
			expect(land.oneShot).toBe("Land")
			expect(land.oneShotWeight).toBe(Config.landing.minSquash)
		end
	)

	it("leans into turns while moving and never past the data maximum", function()
		local state = LocomotionState.new()
		local out
		for _ = 1, 120 do
			out = state:update(FRAME, input({ forward = 1, speed = Config.runSpeed, yawRate = 1e6 }))
		end
		expect(out.lean).toBeCloseTo(Config.lean.max, 1e-3)
		for _ = 1, 120 do
			out = state:update(FRAME, input({ speed = 0, yawRate = 1e6 }))
		end
		expect(out.lean).toBeCloseTo(0, 1e-3)
	end)
end)

describe("LocomotionState.footIK", function()
	it("is identity on flat ground", function()
		local offsets = LocomotionState.footIK(0, 0, 1)
		expect(offsets.Root.pos[2]).toBeCloseTo(0, 1e-6)
		expect(offsets.LeftKnee.rot[1]).toBeCloseTo(0, 1e-3)
		expect(offsets.RightHip.rot[1]).toBeCloseTo(0, 1e-3)
	end)

	it("bends the leg whose ground is higher and keeps the foot level", function()
		local offsets = LocomotionState.footIK(0.5, 0, 1)
		expect(offsets.LeftKnee.rot[1]).toBeLessThan(0)
		expect(offsets.LeftHip.rot[1]).toBeGreaterThan(0)
		expect(offsets.LeftAnkle.rot[1]).toBeCloseTo(-(offsets.LeftHip.rot[1] + offsets.LeftKnee.rot[1]), 1e-6)
		expect(offsets.RightKnee.rot[1]).toBeCloseTo(0, 1e-3)
		expect(offsets.Root.pos[2]).toBeCloseTo(0, 1e-6)
	end)

	it("drops the pelvis by the lower foot's deficit, within the data limit", function()
		local offsets = LocomotionState.footIK(0, -0.4, 1)
		expect(offsets.Root.pos[2]).toBeCloseTo(-0.4, 1e-6)
		expect(offsets.LeftKnee.rot[1]).toBeLessThan(0)
		expect(offsets.RightKnee.rot[1]).toBeCloseTo(0, 1e-3)
		local far = LocomotionState.footIK(0, -10, 1)
		expect(far.Root.pos[2]).toBeCloseTo(-Config.footIK.maxAdjust, 1e-6)
	end)

	it("scales with the weight and fades out with speed", function()
		local half = LocomotionState.footIK(0.5, 0, 0.5)
		local full = LocomotionState.footIK(0.5, 0, 1)
		expect(half.LeftKnee.rot[1]).toBeCloseTo(full.LeftKnee.rot[1] * 0.5, 1e-6)
		expect(LocomotionState.footIKWeight(0, true)).toBe(1)
		expect(LocomotionState.footIKWeight(Config.footIK.fadeSpeed, true)).toBe(0)
		expect(LocomotionState.footIKWeight(0, false)).toBe(0)
		expect(next(LocomotionState.footIK(0.5, 0, 0))).toBeNil()
	end)
end)
