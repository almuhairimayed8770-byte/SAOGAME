--!strict
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local combat = Harness.load("src/shared/data/combat")
local choreo = Harness.load("src/shared/data/choreo")
local world = Harness.load("src/shared/data/world")

local function art(id, preconditions)
	return {
		id = id,
		name = id,
		weapon = "OneHandedSword",
		unlock = 0,
		hits = 1,
		startup = 0.25,
		total = 0.6,
		postMotion = 0.4,
		multiplier = 1,
		gaugeDamage = 20,
		rootMotion = 1,
		clip = "player/OneHandedSword/" .. id,
		preconditions = preconditions,
	}
end

local standing = { moving = false, airborne = false, afterParry = false }
local moving = { moving = true, airborne = false, afterParry = false }
local airborne = { moving = true, airborne = true, afterParry = false }

describe("ActionLogic", function()
	it("launches inside the cancel time and cancels past it", function()
		expect(ActionLogic.holdOutcome(0.3, combat.activationCancelTime)).toBe("Launch")
		expect(ActionLogic.holdOutcome(combat.activationCancelTime, combat.activationCancelTime)).toBe("Launch")
		expect(ActionLogic.holdOutcome(1.2, combat.activationCancelTime)).toBe("Cancel")
	end)

	it("only starts actions from states that allow them", function()
		expect((ActionLogic.canStart("Idle", "Art", 0, 0))).toBe(true)
		expect((ActionLogic.canStart("Art", "Art", 0, 0))).toBe(false)
		expect((ActionLogic.canStart("PostMotion", "Dodge", 0, 0))).toBe(false)
		expect((ActionLogic.canStart("Holding", "Dodge", 0, 0))).toBe(true)
		expect((ActionLogic.canStart("Guard", "Basic", 0, 0))).toBe(false)
		expect((ActionLogic.canStart("Basic", "Art", 0, 0))).toBe(true)
	end)

	it("dodge respects its cooldown", function()
		local ok, reason = ActionLogic.canStart("Idle", "Dodge", 10, 10.5)
		expect(ok).toBe(false)
		expect(reason).toBe("cooldown")
		expect((ActionLogic.canStart("Idle", "Dodge", 10.5, 10.5))).toBe(true)
	end)

	it("derives the stance preconditions", function()
		expect(ActionLogic.stances(standing)).toEqual({ "Standing" })
		expect(ActionLogic.stances(moving)).toEqual({ "Moving" })
		expect(ActionLogic.stances(airborne)).toEqual({ "Airborne" })
		expect(ActionLogic.stances({ moving = false, airborne = false, afterParry = true })).toEqual({
			"Standing",
			"AfterParry",
		})
	end)

	it("picks the slot's Art when its preconditions fit, else another equipped Art that fits", function()
		local slots =
			{ [1] = art("Horizontal"), [2] = art("SonicLeap", { "Moving" }), [4] = art("Riposte", { "AfterParry" }) }
		expect(ActionLogic.pickArt(slots, 1, 4, standing).id).toBe("Horizontal")
		expect(ActionLogic.pickArt(slots, 2, 4, moving).id).toBe("SonicLeap")
		expect(ActionLogic.pickArt(slots, 2, 4, standing).id).toBe("Horizontal")
		expect(ActionLogic.pickArt(slots, 3, 4, standing).id).toBe("Horizontal")
		expect(ActionLogic.pickArt(slots, 4, 4, standing).id).toBe("Horizontal")
		local onlyMoving = { [1] = art("SonicLeap", { "Moving" }) }
		expect(ActionLogic.pickArt(onlyMoving, 1, 4, standing)).toBeNil()
	end)

	it("maps quick-slot ids to Arts that have a clip", function()
		local byId = {
			["OneHandedSword.Horizontal"] = art("Horizontal"),
			["OneHandedSword.Vertical"] = art("Vertical"),
			["OneHandedSword.RisingArc"] = art("RisingArc"),
		}
		local slots = ActionLogic.slotArts({
			"OneHandedSword.Horizontal",
			"OneHandedSword.Unknown",
			"OneHandedSword.RisingArc",
			"OneHandedSword.Vertical",
			"Extra",
		}, function(id)
			return byId[id]
		end, function(clip)
			return clip ~= "player/OneHandedSword/RisingArc"
		end, 4)
		expect(slots[1].id).toBe("Horizontal")
		expect(slots[2]).toBeNil()
		expect(slots[3]).toBeNil()
		expect(slots[4].id).toBe("Vertical")
		expect(slots[5]).toBeNil()
	end)

	it("reads the dodge direction from the local move input, back when there is none", function()
		local deadzone = 0.2
		expect(ActionLogic.dodgeDirection(0, 0, deadzone)).toBe("Back")
		expect(ActionLogic.dodgeDirection(0.1, 0.1, deadzone)).toBe("Back")
		expect(ActionLogic.dodgeDirection(0, -1, deadzone)).toBe("Forward")
		expect(ActionLogic.dodgeDirection(0, 1, deadzone)).toBe("Back")
		expect(ActionLogic.dodgeDirection(1, 0, deadzone)).toBe("Right")
		expect(ActionLogic.dodgeDirection(-1, 0.3, deadzone)).toBe("Left")
	end)

	it("chains basic attacks inside the window and restarts outside it", function()
		local window, length = combat.basicChainWindow, combat.basicChainLength
		expect(ActionLogic.nextBasic(0, 0, 5, window, length)).toBe(1)
		expect(ActionLogic.nextBasic(1, 5, 5.3, window, length)).toBe(2)
		expect(ActionLogic.nextBasic(2, 5.3, 5.6, window, length)).toBe(3)
		expect(ActionLogic.nextBasic(3, 5.6, 5.9, window, length)).toBe(1)
		expect(ActionLogic.nextBasic(1, 5, 5 + window + 0.1, window, length)).toBe(1)
	end)

	it("paces basic attacks at the server's BasicAttackRequest refill so mashing never trips the limit", function()
		local rate = world.anticheat.remoteRates.BasicAttackRequest
		local interval = 1 / rate.perSecond
		-- The first click of a session (nothing sent yet) always goes out.
		expect(ActionLogic.basicReady(0, 5, interval)).toBe(true)
		-- A click inside the refill interval is dropped; one at or past it goes out.
		expect(ActionLogic.basicReady(5, 5 + interval * 0.5, interval)).toBe(false)
		expect(ActionLogic.basicReady(5, 5 + interval - 1e-3, interval)).toBe(false)
		expect(ActionLogic.basicReady(5, 5 + interval, interval)).toBe(true)
		expect(ActionLogic.basicReady(5, 5 + interval * 2, interval)).toBe(true)

		-- A 12 clicks/s masher for 30 s, each request reaching the server with up to 80 ms of
		-- network jitter (late and on-time packets alternate: the worst bunching it allows), run
		-- through the same token bucket Net keeps per player and remote.
		local function rejectedRequests(gate: number): (number, number)
			local clicksPerSecond, jitter = 12, 0.08
			local lastSent = 0
			local arrivals = {}
			for index = 1, clicksPerSecond * 30 do
				local clickAt = 10 + index / clicksPerSecond
				if ActionLogic.basicReady(lastSent, clickAt, gate) then
					lastSent = clickAt
					table.insert(arrivals, clickAt + (if #arrivals % 2 == 0 then jitter else 0))
				end
			end
			table.sort(arrivals)
			local tokens, last, rejected = rate.burst, arrivals[1], 0
			for _, at in arrivals do
				tokens = math.min(rate.burst, tokens + (at - last) * rate.perSecond)
				last = at
				if tokens < 1 then
					rejected += 1
				else
					tokens -= 1
				end
			end
			return rejected, #arrivals
		end
		local rejected, sent = rejectedRequests(interval)
		expect(sent).toBeGreaterThan(0)
		expect(rejected).toBe(0)
		-- Ungated, the same masher overruns the bucket, and each rejection is an abuse report of
		-- abuseWeight: far more than the kick threshold inside the 30 s.
		local ungated = rejectedRequests(0)
		expect(ungated * world.anticheat.abuseWeight).toBeGreaterThan(combat.anomalyKickThreshold)
	end)

	it("builds clip ids from the rig kind", function()
		expect(ActionLogic.clipId("Player", "PlayerR15", "OneHandedSword", "Guard")).toBe("player/OneHandedSword/Guard")
		expect(ActionLogic.clipId("Enemy", "Boar", "OneHandedSword", "Stagger")).toBe("enemy/Boar/Stagger")
	end)

	it("reconciles the local state with the server's", function()
		expect(ActionLogic.reconcile("Art", "Idle")).toBe("EndAction")
		expect(ActionLogic.reconcile("PostMotion", "Moving")).toBe("EndAction")
		expect(ActionLogic.reconcile("Idle", "Idle")).toBe("None")
		expect(ActionLogic.reconcile("Holding", "Moving")).toBe("None")
		expect(ActionLogic.reconcile("Art", "PostMotion")).toBe("None")
		expect(ActionLogic.reconcile("Idle", "Stagger")).toBe("Stagger")
		expect(ActionLogic.reconcile("Guard", "GuardBroken")).toBe("GuardBroken")
		expect(ActionLogic.reconcile("Art", "Break")).toBe("Break")
		expect(ActionLogic.reconcile("Dodge", "Dead")).toBe("Die")
		expect(ActionLogic.reconcile("Basic", "Idle")).toBe("None")
	end)

	it("locks movement and applies root motion in the right states", function()
		for _, state in { "Holding", "Art", "PostMotion", "Basic", "Dodge", "Stagger", "GuardBroken", "Dead" } do
			expect(ActionLogic.movementLocked(state)).toBe(true)
		end
		expect(ActionLogic.movementLocked("Idle")).toBe(false)
		expect(ActionLogic.movementLocked("Guard")).toBe(false)
		expect(ActionLogic.rootMotionActive("Art")).toBe(true)
		expect(ActionLogic.rootMotionActive("Dodge")).toBe(true)
		expect(ActionLogic.rootMotionActive("Basic")).toBe(true)
		expect(ActionLogic.rootMotionActive("Holding")).toBe(false)
		expect(ActionLogic.rootMotionActive("Idle")).toBe(false)
	end)

	it("resolves locomotion speeds from choreo.luau and falls back per field", function()
		local fallback = { walk = 1, run = 2, sprint = 3 }
		local speeds = ActionLogic.resolveSpeeds(choreo, fallback)
		expect(speeds).toEqual({
			walk = choreo.locomotion.walkSpeed,
			run = choreo.locomotion.runSpeed,
			sprint = choreo.locomotion.sprintSpeed,
		})
		expect(ActionLogic.resolveSpeeds(nil, fallback)).toEqual(fallback)
		expect(ActionLogic.resolveSpeeds({ speeds = { sprint = 30 } }, fallback)).toEqual({
			walk = 1,
			run = 2,
			sprint = 30,
		})
		expect(ActionLogic.speedFor("Art", true, speeds)).toBe(0)
		expect(ActionLogic.speedFor("Idle", true, speeds)).toBe(speeds.sprint)
		expect(ActionLogic.speedFor("Idle", false, speeds)).toBe(speeds.run)
		expect(ActionLogic.speedFor("Guard", true, speeds)).toBe(speeds.walk)
	end)

	it("wants the sword drawn while the server says so or a request went out inside the prediction", function()
		local predict = choreo.sheath.predictSeconds
		-- attribute, last prediction, now -> drawn
		local cases: { { any } } = {
			{ false, nil, 10, false },
			{ true, nil, 10, true },
			{ false, 10, 10, true },
			{ false, 10, 10 + predict, true },
			{ false, 10, 10 + predict + 0.01, false },
			{ true, 10, 10 + predict + 0.01, true },
			{ true, 10, 10, true },
		}
		for _, case in cases do
			expect(ActionLogic.drawnTarget(case[1], case[2], case[3], predict)).toBe(case[4])
		end
		expect(ActionLogic.drawn).toBeNil()
	end)

	it("measures the signed degrees from the facing to the move direction (positive = left)", function()
		-- Facing -Z; the stick asks for -X, which is to the left: a quarter turn.
		expect(ActionLogic.turnAngle(0, -1, -1, 0)).toBeCloseTo(90, 1e-6)
		expect(ActionLogic.turnAngle(0, -1, 1, 0)).toBeCloseTo(-90, 1e-6)
		expect(math.abs(ActionLogic.turnAngle(0, -1, 0, 1))).toBeCloseTo(180, 1e-6)
		expect(ActionLogic.turnAngle(0, -1, 0, -1)).toBeCloseTo(0, 1e-6)
		-- The move vector's length does not matter, only its direction.
		expect(ActionLogic.turnAngle(0, -1, -0.2, -0.2)).toBeCloseTo(45, 1e-6)
		-- No move input: nothing to turn toward.
		expect(ActionLogic.turnAngle(0, -1, 0, 0)).toBe(0)
		-- Past choreo's turn-in-place threshold on one side, inside it on the other.
		expect(math.abs(ActionLogic.turnAngle(0, -1, -1, -1))).toBeLessThanOrEqual(choreo.locomotion.turnInPlaceDegrees)
		expect(math.abs(ActionLogic.turnAngle(0, -1, -1, 0))).toBeGreaterThan(choreo.locomotion.turnInPlaceDegrees)
	end)

	it("gives a predicted Art a fallback end after its clip, post-motion and the lag slack", function()
		local horizontal = art("Horizontal")
		local finish = ActionLogic.artFallbackEnd(10, 0.15, horizontal, combat.lagAllowance)
		expect(finish).toBeCloseTo(10 + 0.15 + horizontal.total + horizontal.postMotion + combat.lagAllowance, 1e-9)
		expect(ActionLogic.artFallbackEnd(10, 0, horizontal, 0)).toBeCloseTo(
			10 + horizontal.total + horizontal.postMotion,
			1e-9
		)
	end)

	it("reports the fall height on the landing frame only", function()
		local tracker = { airborneSince = nil, peakY = 0 }
		expect(ActionLogic.fallStep(tracker, true, 5, 0)).toBeNil()
		expect(ActionLogic.fallStep(tracker, false, 6, 0.1)).toBeNil()
		expect(ActionLogic.fallStep(tracker, false, 8, 0.2)).toBeNil()
		expect(ActionLogic.fallStep(tracker, false, 3, 0.3)).toBeNil()
		expect(ActionLogic.fallStep(tracker, true, 1, 0.4)).toBe(7)
		expect(ActionLogic.fallStep(tracker, true, 1, 0.5)).toBeNil()
	end)

	it("calls the rig asleep once a whole frame went by with no render step (D-141)", function()
		-- The render step, then that frame's Heartbeat: a press in the light has seen one.
		expect(ActionLogic.rigAsleep(0)).toBe(false)
		expect(ActionLogic.rigAsleep(1)).toBe(false)
		expect(ActionLogic.rigAsleep(2)).toBe(true)
		expect(ActionLogic.rigAsleep(600)).toBe(true)
	end)

	it("shows a dodge pressed in the dark whole from the wake, unless the stall skipped it (D-141)", function()
		local jump = choreo.stall.jumpSeconds
		expect(ActionLogic.wokenDodge(10, 10, jump)).toBe("Show")
		expect(ActionLogic.wokenDodge(10, 10.2, jump)).toBe("Show")
		expect(ActionLogic.wokenDodge(10, 10 + jump, jump)).toBe("Show")
		expect(ActionLogic.wokenDodge(10, 10 + jump + 1 / 60, jump)).toBe("Drop")
		expect(ActionLogic.wokenDodge(10, 20, jump)).toBe("Drop")
	end)

	it("keeps the held clip frozen for the clip time it reached so it resumes in step with the server", function()
		local plan = ActionLogic.syncPlan(10, 0.15, 10.8)
		expect(plan.freezeClipTime).toBeCloseTo(0.15)
		expect(plan.resumeAt).toBeCloseTo(10.95)
		-- Released before the freeze landed: the clip time reached is the time since the press.
		local early = ActionLogic.syncPlan(10, nil, 10.1)
		expect(early.freezeClipTime).toBeCloseTo(0.1)
		expect(early.resumeAt).toBeCloseTo(10.2)
	end)

	describe("the two-step stop's carry", function()
		local Locomotion = choreo.locomotion
		local config = {
			seconds = Locomotion.stopStepsSeconds,
			minCycles = Locomotion.stopMinCycles,
			endSpeed = Locomotion.stopEndSpeed,
			minSpeed = Locomotion.idleSpeedThreshold,
			maxSpeed = Locomotion.skidSpeedThreshold,
		}
		local FRAME = 1 / 60

		-- Moves along +X at `speed`, lets go at `phase`, and walks the gait on at `pace` cycles a
		-- second; `after` is each foot's settle point, in cycles after its Footstep (left at phase 0,
		-- right at 0.5). Returns the carry speeds and the phase each frame was at.
		local function stopWithGait(speed: number, walkSpeed: number, phase: number, pace: number, after: { number })
			local carry = ActionLogic.newStopCarry()
			local gait = { phase = phase, leftStep = 0, leftAfter = after[1], rightStep = 0.5, rightAfter = after[2] }
			for _ = 1, 3 do
				ActionLogic.stopCarryStep(carry, 1, 0, speed, walkSpeed, true, "Idle", FRAME, config, gait)
			end
			local speeds, phases = {}, {}
			local current = speed
			for _ = 1, math.ceil(config.seconds / FRAME) + 5 do
				current = ActionLogic.stopCarryStep(carry, 0, 0, current, walkSpeed, true, "Idle", FRAME, config, gait)
				table.insert(speeds, current)
				table.insert(phases, gait.phase)
				gait.phase = (gait.phase + pace * FRAME) % 1
			end
			return speeds, phases
		end

		it(
			"walks through the next Footstep stopMinCycles away and stops where that foot settles, slowing down",
			function()
				local after = { 0.12, 0.4 }
				for _, phase in { 0, 0.05, 0.25, 0.31, 0.45, 0.6, 0.79, 0.95 } do
					local pace = 2
					local speeds, phases = stopWithGait(Locomotion.runSpeed, Locomotion.runSpeed, phase, pace, after)
					local frames = 0
					local last = math.huge
					for index, value in speeds do
						if value == 0 then
							break
						end
						frames = index
						expect(value).toBeLessThan(last + 1e-12)
						expect(value).toBeGreaterThan(Locomotion.stopEndSpeed - 1e-9)
						last = value
					end
					-- The first Footstep at least stopMinCycles on, then that foot's settle point.
					local best = math.huge
					for index, step in { 0, 0.5 } do
						local toStep = (step - phase) % 1
						if toStep < Locomotion.stopMinCycles then
							toStep += 1
						end
						best = math.min(best, toStep + after[index])
					end
					local walked = frames * FRAME * pace
					expect(math.abs(walked - best)).toBeLessThan(pace * FRAME * 1.01)
					expect(phases[frames + 1]).toBeCloseTo((phase + walked) % 1, 1e-9)
				end
			end
		)

		it("ends at stopStepsSeconds when the gait does not walk on", function()
			local speeds = stopWithGait(Locomotion.walkSpeed, Locomotion.walkSpeed, 0, 0, { 0.12, 0.4 })
			local moving = 0
			for _, value in speeds do
				if value > 0 then
					moving += 1
				end
			end
			expect(moving * FRAME).toBeCloseTo(config.seconds, FRAME * 1.01)
		end)

		it("a Guard raised mid-carry slows the carry to the Guard speed at once", function()
			local carry = ActionLogic.newStopCarry()
			local gait = { phase = 0, leftStep = 0, leftAfter = 0.12, rightStep = 0.5, rightAfter = 0.4 }
			ActionLogic.stopCarryStep(
				carry,
				1,
				0,
				Locomotion.runSpeed,
				Locomotion.runSpeed,
				true,
				"Idle",
				FRAME,
				config,
				gait
			)
			local first = ActionLogic.stopCarryStep(
				carry,
				0,
				0,
				Locomotion.runSpeed,
				Locomotion.runSpeed,
				true,
				"Idle",
				FRAME,
				config,
				gait
			)
			expect(first).toBeGreaterThan(Locomotion.walkSpeed)
			gait.phase = 0.01
			local guarded =
				ActionLogic.stopCarryStep(carry, 0, 0, first, Locomotion.walkSpeed, true, "Guard", FRAME, config, gait)
			expect(guarded).toBeGreaterThan(0)
			expect(guarded).toBeLessThan(Locomotion.walkSpeed + 1e-9)
		end)

		-- Moves for a few frames at `speed` along +X, then lets go; returns the carry speeds.
		local function release(speed: number, walkSpeed: number, state: any, grounded: boolean?)
			local carry = ActionLogic.newStopCarry()
			for _ = 1, 5 do
				expect(ActionLogic.stopCarryStep(carry, 1, 0, speed, walkSpeed, true, state, FRAME, config)).toBe(0)
			end
			local speeds = {}
			local current = speed
			for _ = 1, math.ceil(config.seconds / FRAME) + 5 do
				current = ActionLogic.stopCarryStep(
					carry,
					0,
					0,
					current,
					walkSpeed,
					if grounded == nil then true else grounded,
					state,
					FRAME,
					config
				)
				table.insert(speeds, current)
			end
			return speeds, carry
		end

		it("with no gait, carries the root along the last move and slows it to a stop over stopStepsSeconds", function()
			local cases = {
				{ speed = Locomotion.walkSpeed, state = "Guard" },
				{ speed = Locomotion.runSpeed, state = "Idle" },
			}
			for _, case in cases do
				local speeds, carry = release(case.speed, case.speed, case.state)
				expect(carry.x).toBe(1)
				expect(carry.z).toBe(0)
				expect(speeds[1]).toBeCloseTo(case.speed * (1 - FRAME / config.seconds), 1e-9)
				local last = math.huge
				local moving = 0
				for _, value in speeds do
					expect(value).toBeLessThan(last + 1e-12)
					expect(value).toBeLessThan(case.speed + 1e-12)
					last = value
					if value > 0 then
						moving += 1
					end
				end
				expect(moving * FRAME).toBeCloseTo(config.seconds, FRAME * 1.01)
				expect(speeds[#speeds]).toBe(0)
			end
		end)

		it("never starts faster than the Humanoid's speed, and not at all above the skid threshold", function()
			local speeds = release(Locomotion.runSpeed, Locomotion.walkSpeed, "Guard")
			expect(speeds[1]).toBeLessThan(Locomotion.walkSpeed + 1e-9)
			local skid = release(Locomotion.skidSpeedThreshold + 1, Locomotion.sprintSpeed, "Idle")
			expect(skid[1]).toBe(0)
			local still = release(Locomotion.idleSpeedThreshold, Locomotion.runSpeed, "Idle")
			expect(still[1]).toBe(0)
		end)

		it("ends on new input, a locked state or leaving the ground", function()
			local carry = ActionLogic.newStopCarry()
			ActionLogic.stopCarryStep(carry, 0, -1, 16, 16, true, "Idle", FRAME, config)
			expect(ActionLogic.stopCarryStep(carry, 0, 0, 16, 16, true, "Idle", FRAME, config)).toBeGreaterThan(0)
			expect(carry.active).toBe(true)
			expect(ActionLogic.stopCarryStep(carry, 1, 0, 15, 16, true, "Idle", FRAME, config)).toBe(0)
			expect(carry.active).toBe(false)
			for _, ending in { { state = "Dodge", grounded = true }, { state = "Idle", grounded = false } } do
				local other = ActionLogic.newStopCarry()
				ActionLogic.stopCarryStep(other, 0, -1, 16, 16, true, "Idle", FRAME, config)
				expect(ActionLogic.stopCarryStep(other, 0, 0, 16, 16, true, "Idle", FRAME, config)).toBeGreaterThan(0)
				expect(ActionLogic.stopCarryStep(other, 0, 0, 15, 16, ending.grounded, ending.state, FRAME, config)).toBe(
					0
				)
				-- and it does not come back on its own
				expect(ActionLogic.stopCarryStep(other, 0, 0, 0, 16, true, "Idle", FRAME, config)).toBe(0)
			end
			-- Standing still is not a stop.
			local idle = ActionLogic.newStopCarry()
			expect(ActionLogic.stopCarryStep(idle, 0, 0, 5, 16, true, "Idle", FRAME, config)).toBe(0)
		end)
	end)

	it("maps actions to local states", function()
		expect(ActionLogic.stateForAction("Art")).toBe("Art")
		expect(ActionLogic.stateForAction("Basic")).toBe("Basic")
		expect(ActionLogic.stateForAction("Guard")).toBe("Guard")
		expect(ActionLogic.stateForAction("Dodge")).toBe("Dodge")
	end)
end)
