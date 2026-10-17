local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local combat = Harness.load("src/shared/data/combat")
local choreo = Harness.load("src/shared/data/choreo")

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

	it("keeps the weapon drawn for the combat tag duration", function()
		expect(ActionLogic.drawn(nil, 10, combat.combatTagDuration)).toBe(false)
		expect(ActionLogic.drawn(10, 12, combat.combatTagDuration)).toBe(true)
		expect(ActionLogic.drawn(10, 10 + combat.combatTagDuration + 0.1, combat.combatTagDuration)).toBe(false)
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

	it("keeps the held clip frozen for the clip time it reached so it resumes in step with the server", function()
		local plan = ActionLogic.syncPlan(10, 0.15, 10.8)
		expect(plan.freezeClipTime).toBeCloseTo(0.15)
		expect(plan.resumeAt).toBeCloseTo(10.95)
		-- Released before the freeze landed: the clip time reached is the time since the press.
		local early = ActionLogic.syncPlan(10, nil, 10.1)
		expect(early.freezeClipTime).toBeCloseTo(0.1)
		expect(early.resumeAt).toBeCloseTo(10.2)
	end)

	it("maps actions to local states", function()
		expect(ActionLogic.stateForAction("Art")).toBe("Art")
		expect(ActionLogic.stateForAction("Basic")).toBe("Basic")
		expect(ActionLogic.stateForAction("Guard")).toBe("Guard")
		expect(ActionLogic.stateForAction("Dodge")).toBe("Dodge")
	end)
end)
