--!strict
-- AimLogic (D-112): when the body faces a held lock, how far it turns a frame, how far a swing may
-- turn it at once (the snap, kept inside what the server accepts), and which enemy the soft assist
-- aims at with no lock.
local AimLogic = Harness.load("src/client/controllers/AimLogic")
local combat = Harness.load("src/shared/data/combat")

local aim = combat.aim
local ACCEPTANCE = math.deg(math.acos(1 - combat.facingTolerance)) -- 49.46

describe("AimLogic.facesLock", function()
	it("faces the lock in Idle, Guard and the held Art stance", function()
		for _, state in { "Idle", "Guard", "Holding" } do
			expect(AimLogic.facesLock(state, true, false, aim)).toBe(true)
		end
	end)

	it("never while the clip owns the body, and never without a lock", function()
		for _, state in { "Art", "Basic", "PostMotion", "Dodge", "Stagger", "GuardBroken", "Dead" } do
			expect(AimLogic.facesLock(state, true, false, aim)).toBe(false)
		end
		for _, state in { "Idle", "Guard", "Holding" } do
			expect(AimLogic.facesLock(state, false, false, aim)).toBe(false)
		end
	end)

	it("sprinting hands the facing back to the stick unless lockFaceWhileSprinting", function()
		expect(aim.lockFaceWhileSprinting).toBe(false)
		expect(AimLogic.facesLock("Idle", true, true, aim)).toBe(false)
		local always = table.clone(aim)
		always.lockFaceWhileSprinting = true
		expect(AimLogic.facesLock("Idle", true, true, always)).toBe(true)
	end)
end)

describe("AimLogic angles", function()
	it("bearing is signed degrees from the look, positive to the left (CFrame.Angles yaw)", function()
		-- Facing -Z: -X is the body's left.
		expect(AimLogic.bearing(0, -1, 0, -5)).toBeCloseTo(0, 1e-9)
		expect(AimLogic.bearing(0, -1, -5, 0)).toBeCloseTo(90, 1e-9)
		expect(AimLogic.bearing(0, -1, 5, 0)).toBeCloseTo(-90, 1e-9)
		expect(math.abs(AimLogic.bearing(0, -1, 0, 5))).toBeCloseTo(180, 1e-9)
		-- A yaw of +30 (CFrame.Angles(0, rad(30), 0)) turns the look toward the target at +30.
		local r = math.rad(30)
		local look = CFrame.Angles(0, r, 0).LookVector
		expect(AimLogic.bearing(0, -1, look.X, look.Z)).toBeCloseTo(30, 1e-6)
		expect(AimLogic.yawOf(look.X, look.Z)).toBeCloseTo(30, 1e-6)
		expect(AimLogic.yawOf(0, -1)).toBeCloseTo(0, 1e-9)
	end)

	it("bearingTo gives no direction for a target closer than minFaceDistance", function()
		expect(AimLogic.bearingTo(0, -1, 10, 10, 10, 5, aim.minFaceDistance)).toBeCloseTo(0, 1e-9)
		expect(AimLogic.bearingTo(0, -1, 10, 10, 5, 10, aim.minFaceDistance)).toBeCloseTo(90, 1e-9)
		expect(AimLogic.bearingTo(0, -1, 10, 10, 10.3, 10.3, aim.minFaceDistance)).toBeNil()
	end)

	it("turnStep turns at most the rate times the frame, never past the target", function()
		local frame = 1 / 60
		expect(AimLogic.turnStep(120, aim.lockTurnRate, frame)).toBeCloseTo(12, 1e-9)
		expect(AimLogic.turnStep(-120, aim.lockTurnRate, frame)).toBeCloseTo(-12, 1e-9)
		expect(AimLogic.turnStep(5, aim.lockTurnRate, frame)).toBe(5)
		expect(AimLogic.turnStep(0, aim.lockTurnRate, frame)).toBe(0)
		-- 180 degrees takes a quarter second.
		local left, frames = 180, 0
		while left > 1e-9 do
			left -= AimLogic.turnStep(left, aim.lockTurnRate, frame)
			frames += 1
		end
		expect(frames).toBe(15)
	end)

	it("snap clamps to the most a swing may turn at once", function()
		expect(AimLogic.snap(30, aim.snapDegrees)).toBe(30)
		expect(AimLogic.snap(120, aim.snapDegrees)).toBe(aim.snapDegrees)
		expect(AimLogic.snap(-165, aim.snapDegrees)).toBe(-aim.snapDegrees)
	end)
end)

describe("AimLogic.requestTurn", function()
	it("a body that held still turns the whole way, up to the snap", function()
		expect(AimLogic.requestTurn(30, 0, 0, aim)).toBe(30)
		expect(AimLogic.requestTurn(-25, 0, 0, aim)).toBe(-25)
		expect(AimLogic.requestTurn(120, 0, 0, aim)).toBe(aim.snapDegrees)
		expect(AimLogic.requestTurn(-165, 0, 0, aim)).toBe(-aim.snapDegrees)
		expect(AimLogic.requestTurn(0, 0, 0, aim)).toBe(0)
	end)

	it("never leaves the facing farther than snap + margin from any yaw the server may still hold", function()
		-- The body turned left 20 degrees in the lag window (the window's yaws sit at -20..0 from now):
		-- a further left turn may only take the facing 49 from -20, so 29.
		expect(AimLogic.requestTurn(60, -20, 0, aim)).toBe(aim.snapDegrees + aim.replicationMarginDegrees - 20)
		-- Turning back the other way is limited by the snap only.
		expect(AimLogic.requestTurn(-60, -20, 0, aim)).toBe(-aim.snapDegrees)
		-- Mid acquisition: it already turned 72 in the window. No snap, and never a turn away from the
		-- target to win the server back.
		expect(AimLogic.requestTurn(90, -72, 0, aim)).toBe(0)
		expect(AimLogic.requestTurn(-90, 0, 72, aim)).toBe(0)
		-- Every answer: inside the snap, toward the target, and never taking the facing out of the
		-- server's acceptance of a window yaw on the side it turns away from (a turn toward a yaw only
		-- brings the facing closer to it).
		for _, delta in { -170, -90, -45, -10, 0, 10, 45, 90, 170 } do
			for _, lo in { -60, -30, -9, 0 } do
				for _, hi in { 0, 9, 30, 60 } do
					local turn = AimLogic.requestTurn(delta, lo, hi, aim)
					expect(math.abs(turn) <= aim.snapDegrees).toBe(true)
					expect(turn * delta >= 0).toBe(true)
					expect(math.abs(turn) <= math.abs(delta)).toBe(true)
					if turn > 0 then
						expect(turn - lo <= ACCEPTANCE + 1e-9).toBe(true)
					elseif turn < 0 then
						expect(hi - turn <= ACCEPTANCE + 1e-9).toBe(true)
					end
					-- The most it could turn toward the target without leaving that acceptance, it does.
					local room = if delta > 0
						then math.min(aim.snapDegrees, lo + aim.snapDegrees + aim.replicationMarginDegrees)
						else math.min(aim.snapDegrees, aim.snapDegrees + aim.replicationMarginDegrees - hi)
					expect(math.abs(turn)).toBeCloseTo(math.max(0, math.min(math.abs(delta), room)), 1e-9)
				end
			end
		end
	end)
end)

describe("AimLogic.sendOffset", function()
	local budget = aim.snapDegrees + aim.replicationMarginDegrees

	it("sends the body's own look while it sits inside the server's acceptance of the lag window", function()
		expect(AimLogic.sendOffset(0, 0, aim)).toBe(0)
		expect(AimLogic.sendOffset(-budget, 0, aim)).toBe(0)
		expect(AimLogic.sendOffset(0, budget, aim)).toBe(0)
		expect(AimLogic.sendOffset(-30, 15, aim)).toBe(0)
	end)

	it("mid-turn, faces back toward where the body was by just enough for the server to accept it", function()
		-- The lock turned the body 84 left in the window: the request faces 35 back right, 49 from
		-- where the window began.
		expect(AimLogic.sendOffset(-84, 0, aim)).toBeCloseTo(-(84 - budget), 1e-9)
		expect(AimLogic.sendOffset(0, 84, aim)).toBeCloseTo(84 - budget, 1e-9)
		-- Every answer inside the bound of every window yaw when the window allows one, its middle
		-- when it does not.
		for _, lo in { -120, -90, -60, -49, -20, 0 } do
			for _, hi in { 0, 20, 49, 60, 90, 120 } do
				local offset = AimLogic.sendOffset(lo, hi, aim)
				if hi - lo <= 2 * budget then
					expect(offset - lo <= budget + 1e-9).toBe(true)
					expect(hi - offset <= budget + 1e-9).toBe(true)
				else
					expect(offset).toBeCloseTo((lo + hi) / 2, 1e-9)
				end
			end
		end
	end)
end)

describe("AimLogic yaw history", function()
	local window = combat.lagAllowance

	it("keeps the yaws of the lag window and the one in effect when it began", function()
		local history = AimLogic.newHistory()
		local lo, hi = AimLogic.range(history)
		expect(lo).toBe(0)
		expect(hi).toBe(0)
		AimLogic.record(history, 0, 0, window)
		AimLogic.record(history, 0.05, 10, window)
		AimLogic.record(history, 0.1, 30, window)
		lo, hi = AimLogic.range(history)
		expect(lo).toBeCloseTo(-30, 1e-9)
		expect(hi).toBeCloseTo(0, 1e-9)
		-- At 0.2 the window starts at 0.05: the yaw then (10) still counts, the one at 0 does not.
		AimLogic.record(history, 0.2, 30, window)
		lo, hi = AimLogic.range(history)
		expect(lo).toBeCloseTo(-20, 1e-9)
		expect(hi).toBeCloseTo(0, 1e-9)
		-- Long still: only the current yaw.
		AimLogic.record(history, 1, 30, window)
		lo, hi = AimLogic.range(history)
		expect(lo).toBeCloseTo(0, 1e-9)
		expect(hi).toBeCloseTo(0, 1e-9)
	end)

	it("unwraps across +-180 so a turn through the back is measured as the short way", function()
		local history = AimLogic.newHistory()
		AimLogic.record(history, 0, 170, window)
		AimLogic.record(history, 0.05, -170, window) -- 20 further left, through 180
		local lo, hi = AimLogic.range(history)
		expect(lo).toBeCloseTo(-20, 1e-9)
		expect(hi).toBeCloseTo(0, 1e-9)
	end)

	it("holds a bounded number of samples however long it runs", function()
		local history = AimLogic.newHistory()
		for frame = 1, 600 do
			AimLogic.record(history, frame / 240, frame % 7, window)
		end
		expect(#history.times <= math.ceil(window * 240) + 1).toBe(true)
		expect(#history.times).toBe(#history.yaws)
	end)
end)

describe("AimLogic.assistPick", function()
	it("picks the best enemy inside the assist range and cone, nearest with the angle priced in", function()
		local pick = AimLogic.assistPick({
			{ id = 1, distance = 6, bearing = 30 },
			{ id = 2, distance = 5, bearing = -40 },
			{ id = 3, distance = 3, bearing = 120 }, -- behind the cone: never an unanimated 120
			{ id = 4, distance = 11, bearing = 0 }, -- past assistRange
		}, aim)
		expect(pick).never.toBeNil()
		-- 6 + rad(30) x 6 = 9.14 against 5 + rad(40) x 6 = 9.19.
		expect((pick :: any).id).toBe(1)
		expect((pick :: any).bearing).toBe(30)
	end)

	it("takes the cone as a whole (45 each side) and the range flat, root to root", function()
		local half = aim.assistConeDegrees / 2
		expect(AimLogic.assistPick({ { id = 1, distance = 5, bearing = half } }, aim)).never.toBeNil()
		expect(AimLogic.assistPick({ { id = 1, distance = 5, bearing = -half - 1 } }, aim)).toBeNil()
		expect(AimLogic.assistPick({ { id = 1, distance = aim.assistRange, bearing = 0 } }, aim)).never.toBeNil()
		expect(AimLogic.assistPick({ { id = 1, distance = aim.assistRange + 0.01, bearing = 0 } }, aim)).toBeNil()
		-- An enemy standing on the body gives no direction to face.
		expect(AimLogic.assistPick({ { id = 1, distance = aim.minFaceDistance / 2, bearing = 0 } }, aim)).toBeNil()
		expect(AimLogic.assistPick({}, aim)).toBeNil()
	end)
end)

describe("AimLogic.moveSpeed", function()
	it("a body facing its lock strafes at walk speed; otherwise the speed stands", function()
		expect(AimLogic.moveSpeed(16, true, 8)).toBe(8)
		expect(AimLogic.moveSpeed(16, false, 8)).toBe(16)
		expect(AimLogic.moveSpeed(0, true, 8)).toBe(0) -- a locked state stays still
	end)
end)

describe("AimLogic: the snap's whip (item 102)", function()
	local Easing = Harness.load("src/shared/util/Easing")
	local FRAME = combat.hitStopFrameSeconds

	it("shows a snap on the curve over its seconds and the whole turn from then on", function()
		local seconds = aim.snapTurnSeconds
		local easing = aim.snapTurnEasing
		expect(AimLogic.snapShown(35, 0, seconds, easing)).toBe(0)
		expect(AimLogic.snapShown(35, seconds / 2, seconds, easing)).toBeCloseTo(
			35 * Easing.evaluate(easing, 0.5),
			1e-9
		)
		expect(AimLogic.snapShown(-35, seconds / 2, seconds, easing)).toBeCloseTo(
			-35 * Easing.evaluate(easing, 0.5),
			1e-9
		)
		expect(AimLogic.snapShown(35, seconds, seconds, easing)).toBe(35)
		expect(AimLogic.snapShown(35, 5, seconds, easing)).toBe(35)
		-- No time to show it in: the whole turn at once.
		expect(AimLogic.snapShown(35, 0, 0, easing)).toBe(35)
		expect(AimLogic.snapShown(0, seconds / 2, seconds, easing)).toBe(0)
	end)

	it("hands the turn out frame by frame; the steps add up to the turn and none is most of it", function()
		local snap = AimLogic.newSnap(35, 10, aim.snapTurnSeconds)
		expect(AimLogic.snapLeft(snap)).toBe(35)
		local total, biggest, frames = 0, 0, 0
		local t = 10
		while AimLogic.snapLeft(snap) ~= 0 and frames < 100 do
			t += FRAME
			local step = AimLogic.snapStep(snap, t, aim.snapTurnEasing)
			expect(step > 0).toBe(true)
			total += step
			biggest = math.max(biggest, step)
			frames += 1
		end
		expect(total).toBeCloseTo(35, 1e-9)
		expect(frames).toBe(math.ceil(aim.snapTurnSeconds / FRAME - 1e-9))
		expect(biggest < 35 / 2).toBe(true)
		-- Over: nothing more to hand out.
		expect(AimLogic.snapStep(snap, t + 1, aim.snapTurnEasing)).toBe(0)
		-- A step taken twice at the same moment hands out nothing the second time.
		local again = AimLogic.newSnap(-20, 0, aim.snapTurnSeconds)
		local once = AimLogic.snapStep(again, FRAME, aim.snapTurnEasing)
		expect(once < 0).toBe(true)
		expect(AimLogic.snapStep(again, FRAME, aim.snapTurnEasing)).toBe(0)
		expect(AimLogic.snapLeft(again)).toBeCloseTo(-20 - once, 1e-12)
	end)

	it("stretches the whip with a slowed capture, the way the clips stretch", function()
		expect(AimLogic.snapSeconds(aim, 1)).toBe(aim.snapTurnSeconds)
		expect(AimLogic.snapSeconds(aim, 0.25)).toBeCloseTo(aim.snapTurnSeconds * 4, 1e-12)
		-- A scale that would stop or reverse time changes nothing.
		expect(AimLogic.snapSeconds(aim, 0)).toBe(aim.snapTurnSeconds)
		expect(AimLogic.snapSeconds(aim, -1)).toBe(aim.snapTurnSeconds)
	end)
end)

describe("AimLogic.assistPick: the two-boar case behind item 102's 12 degrees", function()
	-- Unlocked, one boar 35 degrees off at 4 studs: 4 + rad(35) x 6 = 7.67. A second boar 23
	-- degrees off scores d + rad(23) x 6 = d + 2.41, so it wins inside 5.26 studs and the snap
	-- faces it, which leaves the body 12 degrees off the first. That is the ranking at work.
	it("a second boar 23 degrees off and nearer than 5.26 studs is the pick", function()
		local first = { id = 1, distance = 4, bearing = 35 }
		local near = AimLogic.assistPick({ first, { id = 2, distance = 5.2, bearing = 23 } }, aim)
		expect((near :: any).id).toBe(2)
		expect(35 - (near :: any).bearing).toBe(12)
		local far = AimLogic.assistPick({ first, { id = 2, distance = 5.3, bearing = 23 } }, aim)
		expect((far :: any).id).toBe(1)
	end)
end)
