--!strict
local LocomotionState = Harness.load("src/client/choreo/LocomotionState")
local ChoreoData = Harness.load("src/shared/data/choreo")

local Config = ChoreoData.locomotion
local Stride = Config.stride
local FRAME = 1 / 60
local WALKS = { "WalkForward", "WalkRight", "WalkBack", "WalkLeft" }

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

describe("LocomotionState.walkWeights", function()
	it("maps the four axis directions to one walk each, in both sets", function()
		for _, drawn in { false, true } do
			expect(LocomotionState.walkWeights(1, 0, drawn).WalkForward).toBeCloseTo(1, 1e-9)
			expect(LocomotionState.walkWeights(0, 1, drawn).WalkRight).toBeCloseTo(1, 1e-9)
			expect(LocomotionState.walkWeights(-1, 0, drawn).WalkBack).toBeCloseTo(1, 1e-9)
			expect(LocomotionState.walkWeights(0, -1, drawn).WalkLeft).toBeCloseTo(1, 1e-9)
		end
	end)

	it("splits a diagonal so the planted foot travels straight back along the move", function()
		local gaits = LocomotionState.gaits()
		for _, drawn in { false, true } do
			for angle = 0, 355, 5 do
				local radians = math.rad(angle)
				local forward, right = math.cos(radians), math.sin(radians)
				local weights = LocomotionState.walkWeights(forward, right, drawn)
				expect(sum(weights)).toBeCloseTo(1, 1e-9)
				-- The blend's foot travel per cycle: each walk's stride along its own axis.
				local travelForward, travelRight = 0, 0
				for _, name in WALKS do
					local gait = gaits[LocomotionState.clipFor(name, drawn)]
					travelForward += weights[name] * gait.stride * gait.forward
					travelRight += weights[name] * gait.stride * gait.right
				end
				local across = travelForward * right - travelRight * forward
				local along = travelForward * forward + travelRight * right
				expect(math.abs(across)).toBeLessThan(1e-9)
				expect(along).toBeGreaterThan(0)
				local _, duration = LocomotionState.walkGait(weights, forward, right, drawn)
				expect(LocomotionState.walkGait(weights, forward, right, drawn) * duration).toBeCloseTo(along, 1e-9)
			end
		end
	end)
end)

describe("LocomotionState.gaitWeights", function()
	local gaits = LocomotionState.gaits()
	local function sets()
		local out = {}
		for _, drawn in { false, true } do
			local walkSpeed, walkDuration =
				LocomotionState.walkGait(LocomotionState.walkWeights(1, 0, drawn), 1, 0, drawn)
			table.insert(out, {
				walkSpeed = walkSpeed,
				walkDuration = walkDuration,
				run = gaits[LocomotionState.clipFor("Run", drawn)],
				sprint = gaits[LocomotionState.clipFor("Sprint", drawn)],
			})
		end
		return out
	end

	it("shows each gait alone at its own ground speed", function()
		for _, set in sets() do
			local walk, run, sprint, idle =
				LocomotionState.gaitWeights(set.walkSpeed, set.walkSpeed, set.walkDuration, set.run, set.sprint)
			expect(walk).toBeCloseTo(1, 1e-9)
			expect(run + sprint + idle).toBeCloseTo(0, 1e-9)
			walk, run, sprint, idle =
				LocomotionState.gaitWeights(set.run.groundSpeed, set.walkSpeed, set.walkDuration, set.run, set.sprint)
			expect(run).toBeCloseTo(1, 1e-9)
			walk, run, sprint, idle = LocomotionState.gaitWeights(
				set.sprint.groundSpeed,
				set.walkSpeed,
				set.walkDuration,
				set.run,
				set.sprint
			)
			expect(sprint).toBeCloseTo(1, 1e-9)
		end
	end)

	it("between two gaits picks the shares at which the blend steps at its natural cadence", function()
		for _, set in sets() do
			local speed = set.walkSpeed
			while speed < set.sprint.groundSpeed do
				local walk, run, sprint, idle =
					LocomotionState.gaitWeights(speed, set.walkSpeed, set.walkDuration, set.run, set.sprint)
				expect(walk + run + sprint + idle).toBeCloseTo(1, 1e-9)
				expect(idle).toBe(0)
				local duration = walk * set.walkDuration + run * set.run.duration + sprint * set.sprint.duration
				local stride = walk * set.walkSpeed * set.walkDuration
					+ run * set.run.stride
					+ sprint * set.sprint.stride
				-- rate 1: the blend covers its stride in its own cycle at this speed
				expect(speed * duration).toBeCloseTo(stride, 1e-9)
				speed += 0.25
			end
		end
	end)

	it("at walkSpeed blends the walk with Run: walkSpeed is a movement speed, not a gait's", function()
		local set = sets()[1]
		local walk, run =
			LocomotionState.gaitWeights(Config.walkSpeed, set.walkSpeed, set.walkDuration, set.run, set.sprint)
		expect(walk).toBeLessThan(0.9)
		expect(run).toBeGreaterThan(0.1)
		expect(walk + run).toBeCloseTo(1, 1e-9)
	end)

	it("with no Sprint, Run carries every speed past its own ground speed", function()
		for _, set in sets() do
			for _, speed in { set.run.groundSpeed + 0.5, Config.runSpeed, set.sprint.groundSpeed } do
				local walk, run, sprint, idle =
					LocomotionState.gaitWeights(speed, set.walkSpeed, set.walkDuration, set.run, nil)
				expect(run).toBeCloseTo(1, 1e-9)
				expect(walk + sprint + idle).toBe(0)
			end
		end
	end)

	it("below the walk's ground speed slows the walk to rateFloor, then hands weight to Idle", function()
		for _, set in sets() do
			local floor = Stride.rateFloor * set.walkSpeed
			for step = 1, 20 do
				local speed = set.walkSpeed * step / 20
				local walk, run, sprint, idle =
					LocomotionState.gaitWeights(speed, set.walkSpeed, set.walkDuration, set.run, set.sprint)
				expect(run + sprint).toBe(0)
				if speed >= floor then
					expect(walk).toBeCloseTo(1, 1e-9)
				else
					expect(walk).toBeCloseTo(speed / floor, 1e-9)
					expect(idle).toBeCloseTo(1 - walk, 1e-9)
				end
			end
		end
	end)

	it("wholeWalkSpeed: from it the walk of a direction shows alone (D-144)", function()
		for _, drawn in { false, true } do
			for degrees = 0, 315, 45 do
				local f, r = math.cos(math.rad(degrees)), math.sin(math.rad(degrees))
				local walkSpeed, walkDuration =
					LocomotionState.walkGait(LocomotionState.walkWeights(f, r, drawn), f, r, drawn)
				local whole = LocomotionState.wholeWalkSpeed(f, r, drawn)
				expect(whole).toBeCloseTo(Stride.rateFloor * walkSpeed, 1e-9)
				local at = LocomotionState.gaitWeights(whole, walkSpeed, walkDuration, nil, nil)
				local below = LocomotionState.gaitWeights(whole * 0.99, walkSpeed, walkDuration, nil, nil)
				expect(at).toBeCloseTo(1, 1e-9)
				expect(below).toBeLessThan(1)
			end
		end
	end)
end)

describe("LocomotionState.plantedAlong and settlePoints", function()
	local gaits = LocomotionState.gaits()
	it("puts each foot at its touchdown at its Footstep and moves it back by the stride per cycle", function()
		for name, gait in gaits do
			-- left foot: shared phase 0 is its Footstep
			local left = gait.leftFoot
			local at0 = LocomotionState.plantedAlong(name, 0, gait.forward, gait.right)
			expect(at0).toBeCloseTo(left.forward * gait.forward + left.right * gait.right, 1e-9)
			local later = LocomotionState.plantedAlong(name, 0.2, gait.forward, gait.right)
			expect(at0 - later).toBeCloseTo(gait.stride * 0.2, 1e-9)
		end
		local idle = LocomotionState.idleFeet("IdleDrawn")
		expect(LocomotionState.plantedAlong("IdleDrawn", 0.7, 1, 0)).toBeCloseTo(idle.rightFoot.forward, 1e-9)
	end)

	it("settles where the walk's planted foot is over its Idle spot, for every direction and set", function()
		-- A foot that gets over its Idle spot only within stopHandOverCycles of the other foot's
		-- Footstep goes on to the other foot's settle point half a cycle on (that foot would come
		-- down mid hand-over and skate to its own spot); the other foot's own point is not late.
		local late = 0
		for _, drawn in { false, true } do
			local rest = LocomotionState.idleFeet(LocomotionState.clipFor("Idle", drawn))
			for degrees = 0, 315, 45 do
				local radians = math.rad(degrees)
				local forward, right = math.cos(radians), math.sin(radians)
				local leftStep, leftAfter, rightStep, rightAfter = LocomotionState.settlePoints(forward, right, drawn)
				expect(leftStep).toBe(0)
				expect(math.abs(rightStep - 0.5)).toBeLessThan(0.01)
				local weights = LocomotionState.walkWeights(forward, right, drawn)
				local feet = {
					{ step = leftStep, after = leftAfter, rest = rest.leftFoot, toOther = rightStep - leftStep },
					{ step = rightStep, after = rightAfter, rest = rest.rightFoot, toOther = 1 - rightStep },
				}
				for index, foot in feet do
					local other = feet[3 - index]
					if foot.after > foot.toOther - Config.stopHandOverCycles + 1e-9 then
						late += 1
						expect(foot.after).toBeCloseTo(foot.toOther + other.after, 1e-9)
						expect(other.after <= other.toOther - Config.stopHandOverCycles + 1e-9).toBe(true)
						continue
					end
					local planted = 0
					for walk, share in weights do
						planted += share * LocomotionState.plantedAlong(
							LocomotionState.clipFor(walk, drawn),
							foot.step + foot.after,
							forward,
							right
						)
					end
					local spot = foot.rest.forward * forward + foot.rest.right * right
					-- Within half a cycle of its Footstep the walk reaches it, or the point is held at
					-- an end of that half (the spot is behind the touchdown, or a side walk's stride
					-- is too short to reach it).
					if math.abs(planted - spot) > 1e-6 then
						expect(foot.after == 0 or foot.after == 0.5).toBe(true)
					end
				end
			end
		end
		-- The drawn forward walk's right foot reaches the fighting stance's back spot only as the
		-- left heel lands: that stop goes on to the left foot's point.
		local _, leftAfter, rightStep, rightAfter = LocomotionState.settlePoints(1, 0, true)
		expect(rightAfter).toBeCloseTo(1 - rightStep + leftAfter, 1e-9)
		expect(late > 0).toBe(true)
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

	it("walks with the stride-aligned direction blend at the walk's ground speed and runs at Run's", function()
		local state = LocomotionState.new()
		local out = state:update(FRAME, input({ forward = 1, speed = Stride.groundSpeed.WalkForward }))
		expect(out.weights.WalkForward).toBeCloseTo(1, 1e-9)
		expect(out.phase).toBe("Move")
		local diagonal = LocomotionState.walkWeights(1, 1, false)
		local along = LocomotionState.walkGait(diagonal, 1, 1, false)
		out = state:update(FRAME, input({ forward = 1, right = 1, speed = along }))
		expect(out.weights.WalkForward).toBeCloseTo(diagonal.WalkForward, 1e-9)
		expect(out.weights.WalkRight).toBeCloseTo(diagonal.WalkRight, 1e-9)
		out = state:update(FRAME, input({ forward = 1, speed = Stride.groundSpeed.Run }))
		expect(out.weights.Run).toBeCloseTo(1, 1e-9)
		expect(sum(out.weights)).toBeCloseTo(1, 1e-6)
	end)

	it("sprinting with a drawn weapon reports the drawn-sprint additive weight", function()
		local state = LocomotionState.new()
		local out =
			state:update(FRAME, input({ forward = 1, speed = Config.sprintSpeed, sprinting = true, drawn = true }))
		expect(out.weights.SprintDrawn).toBeCloseTo(1)
		expect(out.drawnSprint).toBeCloseTo(out.weights.SprintDrawn, 1e-9)
		out = state:update(FRAME, input({ forward = 1, speed = Config.sprintSpeed, sprinting = true, drawn = false }))
		expect(out.drawnSprint).toBe(0)
	end)

	it("drawn moves the walks, Run and Sprint to the ...Drawn clips; sheathed keeps the plain ones", function()
		-- Each case moves at its clip's own ground speed in each set.
		local cases = {
			{ input = { forward = 1 }, name = "WalkForward" },
			{ input = { forward = -1 }, name = "WalkBack" },
			{ input = { right = -1 }, name = "WalkLeft" },
			{ input = { right = 1 }, name = "WalkRight" },
			{ input = { forward = 1 }, name = "Run" },
			{ input = { forward = 1, sprinting = true }, name = "Sprint" },
			{ input = { forward = 1, grounded = false, verticalVelocity = -1 }, name = "Run" },
		}
		for _, case in cases do
			local sheathedInput = input(case.input)
			sheathedInput.speed = Stride.groundSpeed[case.name]
			local sheathed = LocomotionState.new():update(FRAME, sheathedInput)
			expect(sheathed.weights[case.name]).toBeCloseTo(1, 1e-6)
			expect(sheathed.weights[case.name .. "Drawn"]).toBe(0)
			local drawnInput = input(case.input)
			drawnInput.drawn = true
			drawnInput.speed = Stride.groundSpeed[case.name .. "Drawn"]
			local drawn = LocomotionState.new():update(FRAME, drawnInput)
			expect(drawn.weights[case.name .. "Drawn"]).toBeCloseTo(1, 1e-6)
			expect(drawn.weights[case.name]).toBe(0)
		end
		expect(LocomotionState.clipFor("Run", true)).toBe("RunDrawn")
		expect(LocomotionState.clipFor("Idle", true)).toBe("IdleDrawn")
		expect(LocomotionState.clipFor("Run", false)).toBe("Run")
	end)

	it("weighs all fourteen clips and the weights sum to one, drawn or sheathed", function()
		expect(#LocomotionState.WEIGHT_NAMES).toBe(14)
		for _, name in LocomotionState.WEIGHT_NAMES do
			expect(Config.clips[name]).toBeTruthy()
		end
		for _, drawn in { false, true } do
			local state = LocomotionState.new()
			for speed = 0, Config.sprintSpeed + 2, 0.5 do
				for _, direction in { { 1, 0 }, { 1, 1 }, { 0, -1 }, { -1, 0.3 } } do
					local out = state:update(
						FRAME,
						input({
							forward = direction[1],
							right = direction[2],
							speed = speed,
							sprinting = speed > Config.runSpeed,
							drawn = drawn,
						})
					)
					local count = 0
					for _ in out.weights do
						count += 1
					end
					expect(count).toBe(14)
					expect(sum(out.weights)).toBeCloseTo(1, 1e-6)
				end
			end
		end
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

	it("plays no turn in place while the stick is pushed (the first steps take the turn)", function()
		local state = LocomotionState.new()
		-- The frame the stick goes behind, before the root has any speed.
		expect(state:update(FRAME, input({ forward = -1, turning = 180, yawRate = 1200 })).oneShot).toBeNil()
		expect(state:update(FRAME, input({ right = 1, turning = 90, yawRate = 1200 })).oneShot).toBeNil()
		-- The yaw turned while pushed (40 degrees) is not kept for the next stand.
		expect(state:update(FRAME, input({ yawRate = 600 })).oneShot).toBeNil()
		expect(state:update(FRAME, input({ turning = Config.turnInPlaceDegrees + 1 })).oneShot).toBe("TurnLeft")
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

	it("a stop below the skid threshold leaves the gait to the root's speed: no walk on a still root", function()
		-- The two-step stop is the root's (CharacterController carries it): a walk weight with the
		-- root standing still would slide the planted foot.
		local state = LocomotionState.new()
		state:update(FRAME, input({ forward = 1, speed = Config.runSpeed }))
		local out = state:update(FRAME, input({ speed = 0 }))
		expect(out.phase).toBe("Idle")
		expect(out.oneShot).toBeNil()
		for _ = 1, math.ceil(Config.stopStepsSeconds / FRAME) do
			out = state:update(FRAME, input({ speed = 0 }))
			expect(out.weights.Idle).toBe(1)
		end
		-- A root that slows down over the stop walks down with it, at every speed.
		local slowing = LocomotionState.new()
		slowing:update(FRAME, input({ forward = 1, speed = Config.runSpeed }))
		local frames = math.ceil(Config.stopStepsSeconds / FRAME)
		for frame = 1, frames do
			local speed = Config.runSpeed * (1 - frame / frames)
			out = slowing:update(FRAME, input({ forward = 1, speed = speed }))
			expect(out.oneShot).toBeNil()
			expect(out.phase).toBe(if speed > Config.idleSpeedThreshold then "Move" else "Idle")
		end
	end)

	it("moving again during a skid's stop does not skid a second time", function()
		local state = LocomotionState.new()
		state:update(FRAME, input({ forward = 1, speed = Config.sprintSpeed, sprinting = true }))
		expect(state:update(FRAME, input({ speed = 0 })).oneShot).toBe("Skid")
		local out = state:update(FRAME, input({ forward = 1, speed = Config.runSpeed }))
		expect(out.oneShot).toBeNil()
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

	it("a landing on the move has no squash: the gait carries it", function()
		local state = LocomotionState.new()
		state:update(FRAME, input({ forward = 1, speed = Config.walkSpeed, grounded = false, verticalVelocity = -5 }))
		local out = state:update(
			FRAME,
			input({
				forward = 1,
				speed = Config.walkSpeed,
				grounded = true,
				fallHeight = Config.landing.fullSquashHeight,
			})
		)
		expect(out.oneShot).toBe("Land")
		expect(out.oneShotWeight).toBe(0)
		expect(out.phase).toBe("Move")
	end)

	it("shows Sprint only while sprinting: a run past Run's ground speed stays Run", function()
		for _, drawn in { false, true } do
			local run = LocomotionState.clipFor("Run", drawn)
			local sprint = LocomotionState.clipFor("Sprint", drawn)
			for _, speed in { Config.runSpeed, Config.runSpeed + 2 } do
				local state = LocomotionState.new()
				local out
				for _ = 1, 60 do
					out = state:update(FRAME, input({ forward = 1, speed = speed, drawn = drawn }))
				end
				expect(out.weights[sprint]).toBe(0)
				expect(out.weights[run]).toBeCloseTo(1, 1e-9)
				expect(out.drawnSprint).toBe(0)
				-- Sprinting at the same speed: past Run's ground speed it is all Sprint.
				local sprinter = LocomotionState.new()
				for _ = 1, 60 do
					out = sprinter:update(
						FRAME,
						input({ forward = 1, speed = speed + 2, drawn = drawn, sprinting = true })
					)
				end
				expect(out.weights[sprint]).toBeCloseTo(1, 1e-9)
				expect(out.weights[run]).toBe(0)
			end
		end
	end)

	it("a move behind the facing keeps Run and Sprint only while the body turns to it", function()
		local behind = { forward = -1, speed = Config.runSpeed }
		-- Held behind (lock-on backpedal): the walks carry it.
		local held = LocomotionState.new():update(FRAME, input(behind))
		expect(held.weights.Run).toBe(0)
		expect(held.weights.WalkBack).toBeGreaterThan(0.99)
		-- Turning to it: the controller's angle past turnInPlaceDegrees, or a fast yaw.
		for _, turn in { { turning = Config.turnInPlaceDegrees + 1 }, { yawRate = Stride.turnYawRate + 1 } } do
			local fields = table.clone(behind)
			for key, value in turn do
				fields[key] = value
			end
			local out = LocomotionState.new():update(FRAME, input(fields))
			expect(out.weights.Run).toBeGreaterThan(0.5)
		end
		-- A slow lock-on circle is not a turn.
		local circling =
			LocomotionState.new()
				:update(FRAME, input({ forward = -1, speed = Config.runSpeed, yawRate = Stride.turnYawRate - 1 }))
		expect(circling.weights.Run).toBe(0)
	end)

	it("a move the body is held off (lock-on strafe): Run's feet carry only its part along the facing", function()
		local gaits = LocomotionState.gaits()
		-- Studs a cycle the blend's planted foot travels across the move (forward, right): each
		-- gait clip's foot goes along its own axis by its stride.
		local function across(weights: { [string]: number }, forward: number, right: number): number
			local total = 0
			for name, gait in gaits do
				total += (weights[name] or 0) * gait.stride * (gait.right * forward - gait.forward * right)
			end
			return total
		end
		for _, drawn in { false, true } do
			local run = LocomotionState.clipFor("Run", drawn)
			-- A strafe a little off square (the lock turn lags the target): the side walk carries it.
			for _, degrees in { 88, 92, 268, 272 } do
				local radians = math.rad(degrees)
				local out = LocomotionState.new():update(
					FRAME,
					input({
						forward = math.cos(radians),
						right = math.sin(radians),
						speed = Config.walkSpeed,
						drawn = drawn,
					})
				)
				expect(out.weights[run]).toBeLessThan(0.05)
				expect(sum(out.weights)).toBeCloseTo(1, 1e-6)
			end
			-- Every way into the forward half at walkSpeed: the planted foot goes straight back.
			for degrees = 5, 85, 10 do
				for _, side in { 1, -1 } do
					local radians = math.rad(degrees)
					local forward, right = math.cos(radians), side * math.sin(radians)
					local out = LocomotionState.new():update(
						FRAME,
						input({ forward = forward, right = right, speed = Config.walkSpeed, drawn = drawn })
					)
					expect(math.abs(across(out.weights, forward, right))).toBeLessThan(1e-6)
					expect(sum(out.weights)).toBeCloseTo(1, 1e-6)
				end
			end
		end
		-- A body turning to its move (the controller gives the angle) runs into it as before.
		local radians = math.rad(30)
		local turning = LocomotionState.new():update(
			FRAME,
			input({ forward = math.cos(radians), right = math.sin(radians), speed = Config.runSpeed, turning = -30 })
		)
		expect(turning.weights.Run).toBeGreaterThan(0.9)
		-- By run speed a body held a few degrees off its move (a remote rig's facing lagging its
		-- velocity) runs too: the side walks only take the sideways part at walking speeds.
		radians = math.rad(5)
		local drifting = LocomotionState.new():update(
			FRAME,
			input({ forward = math.cos(radians), right = math.sin(radians), speed = Config.runSpeed })
		)
		expect(drifting.weights.Run).toBeGreaterThan(0.9)
	end)

	it("a held move at walkSpeed (a lock or Guard, the body not turning): the walks alone (D-292)", function()
		for _, drawn in { false, true } do
			-- Straight ahead: the forward walk alone, paced past its ground speed, no Run.
			local walk = LocomotionState.clipFor("WalkForward", drawn)
			local out = LocomotionState.new()
				:update(FRAME, input({ forward = 1, speed = Config.walkSpeed, drawn = drawn }))
			expect(out.weights[walk]).toBeCloseTo(1, 1e-9)
			expect(out.weights[LocomotionState.clipFor("Run", drawn)]).toBe(0)
			-- A few degrees off: the walks by direction, nothing else.
			for _, degrees in { 3, 8, 30, 352 } do
				local radians = math.rad(degrees)
				local forward, right = math.cos(radians), math.sin(radians)
				local direction = LocomotionState.walkWeights(forward, right, drawn)
				out = LocomotionState.new():update(
					FRAME,
					input({ forward = forward, right = right, speed = Config.walkSpeed, drawn = drawn })
				)
				for name, weight in out.weights do
					local share = direction[name:gsub("Drawn$", "")] or 0
					local expected = if LocomotionState.clipFor(name:gsub("Drawn$", ""), drawn) == name
						then share
						else 0
					expect(weight).toBeCloseTo(expected, 1e-9)
				end
			end
		end
		-- heldShare: all of it up to walkSpeed, none by the speed at which the walks alone reach
		-- rateCeiling, and none for a body turning to its move.
		local ahead = input({ forward = 1 })
		local walkSpeed = Stride.groundSpeed.WalkForward
		local ceiling = walkSpeed * Stride.rateCeiling
		expect(LocomotionState.heldShare(Config.walkSpeed, ahead, walkSpeed)).toBe(1)
		expect(LocomotionState.heldShare((Config.walkSpeed + ceiling) * 0.5, ahead, walkSpeed)).toBeCloseTo(0.5, 1e-9)
		expect(LocomotionState.heldShare(ceiling, ahead, walkSpeed)).toBe(0)
		expect(LocomotionState.heldShare(Config.runSpeed, ahead, walkSpeed)).toBe(0)
		expect(LocomotionState.heldShare(Config.walkSpeed, input({ forward = 1, turning = -30 }), walkSpeed)).toBe(0)
		expect(
			LocomotionState.heldShare(
				Config.walkSpeed,
				input({ forward = 1, yawRate = 2 * Stride.turnYawRate }),
				walkSpeed
			)
		).toBe(0)
	end)

	it(
		"a run slowing to walkSpeed keeps its cadence shares and hands over to the walk within heldRiseSeconds",
		function()
			local gaits = LocomotionState.gaits()
			local direction = LocomotionState.walkWeights(1, 0, false)
			local walkSpeed, walkDuration = LocomotionState.walkGait(direction, 1, 0, false)
			local cadenceWalk, cadenceRun =
				LocomotionState.gaitWeights(Config.walkSpeed, walkSpeed, walkDuration, gaits.Run, nil)
			expect(cadenceRun).toBeGreaterThan(0.3)
			local state = LocomotionState.new()
			state:update(FRAME, input({ forward = 1, speed = Config.runSpeed }))
			-- The frame the run comes down to walkSpeed (a two-step stop passes it in a few frames).
			local held = FRAME / Stride.heldRiseSeconds
			local out = state:update(FRAME, input({ forward = 1, speed = Config.walkSpeed }))
			expect(out.weights.Run).toBeCloseTo(cadenceRun * (1 - held), 1e-9)
			expect(out.weights.WalkForward).toBeCloseTo(cadenceWalk * (1 - held) + held, 1e-9)
			-- Held there (a lock or Guard): the walk alone once heldRiseSeconds have passed.
			for _ = 1, math.ceil(Stride.heldRiseSeconds / FRAME) do
				out = state:update(FRAME, input({ forward = 1, speed = Config.walkSpeed }))
			end
			expect(out.weights.WalkForward).toBeCloseTo(1, 1e-9)
			expect(out.weights.Run).toBe(0)
			-- Speeding up again (the lock lets go): the run is back at once.
			out = state:update(FRAME, input({ forward = 1, speed = Config.runSpeed }))
			expect(out.weights.Run).toBeCloseTo(1, 1e-9)
			-- Standing, then a start at walkSpeed: no gait to hand over from, the walk alone at once.
			state:update(FRAME, input({}))
			out = state:update(FRAME, input({ forward = 1, speed = Config.walkSpeed }))
			expect(out.weights.WalkForward).toBeCloseTo(1, 1e-9)
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

	it("lean offsets roll the waist into the turn and the head back by the data fraction", function()
		local offsets = LocomotionState.leanOffsets(8)
		expect(offsets.Waist.rot[3]).toBe(8)
		expect(offsets.Neck.rot[3]).toBeCloseTo(-8 * Config.lean.neckCounterFraction, 1e-9)
		expect(Config.lean.neckCounterFraction).toBeGreaterThan(0)
		expect(Config.lean.neckCounterFraction).toBeLessThan(1)
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
