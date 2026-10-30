--!strict
--[[
	A Charger's rush drawn on the server's timeline (D-171, item 1).

	The pure half drives choreo/RushDraw alone. The measured half runs the real path: a RigBuilder
	Boar posed every 60 fps frame by a real Choreo animator, the remotes going through the real
	Replication, and the root part played as the engine replicates it: the server's body (crouched
	at the line's origin through the wind-up, then down the line at the rush speed for reach +
	overshoot) shown `lag` seconds late (0.25 s, and 0.5 s for a first move after a long stand).
	The Telegraph and ActionStarted reach the client `latency` seconds after the server sent them,
	RushStarted that long after the launch. Each frame the rig's parts are solved from the root
	part and the joints' Transforms (what the engine draws), and the snout's reach down the line
	is compared with the moment the server's own sweep reaches a target there: its snout is
	speed * elapsed + front (EnemyService.bodyExtents) on the server's clock (Charger.luau).
]]

local function frameSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
Harness.stubService("RunService", {
	RenderStepped = frameSignal(),
	Heartbeat = frameSignal(),
	PreSimulation = frameSignal(),
	-- Choreo's rig step (bound just before the camera's): the spec steps the rigs itself.
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
local RushDraw = Harness.load("src/client/choreo/RushDraw")
local Replication = Harness.load("src/client/controllers/Replication")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local EnemyService = Harness.load("src/server/services/EnemyService")
local Enemies = Harness.load("src/shared/data/enemies")
local AI = Harness.load("src/shared/data/ai")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local Rigs = Harness.load("src/shared/data/rigs")
local Fx = Harness.load("src/shared/data/fx")
local CameraMath = Harness.load("src/client/camera/CameraMath")
local FrameClock = Harness.load("src/client/fx/FrameClock")

local FRAME = 1 / 60
local TUNING = ChoreoData.enemy.rush
local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]
local SPEED: number = AI.rushSpeed(CHARGE)
local LENGTH: number = CHARGE.reach + AI.archetypes.Charger.overshoot
-- One frame of the run's own travel: the most the drawn body may move when its offset starts or ends.
local FRAME_TRAVEL = SPEED * FRAME
-- Vector3 is single precision: positions some tens of studs out agree to about this.
local EPSILON = 1e-4

local clock = 0
-- The rendered frame the measured half's loop is on (its recorders note it with each call).
local frameNow = 0
Choreo.configure({
	now = function()
		return clock
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})

local function line(startedAt: number): any
	return {
		origin = Vector3.zero,
		direction = Vector3.new(0, 0, -1),
		speed = SPEED,
		length = LENGTH,
		strike = CHARGE.strike,
		startedAt = startedAt,
	}
end

local function at(along: number): CFrame
	local position = Vector3.new(0, 3, -along)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

describe("RushDraw's timeline (D-171)", function()
	it("runs at the rush speed to the strike, then sheds it evenly to rest at the run's end", function()
		local run = line(0)
		expect(RushDraw.distanceAt(run, -0.1)).toBe(0)
		expect(RushDraw.distanceAt(run, CHARGE.strike)).toBeCloseTo(SPEED * CHARGE.strike, 1e-9)
		local finish = RushDraw.finishSeconds(run)
		local rest = LENGTH - SPEED * CHARGE.strike
		expect(finish).toBeCloseTo(CHARGE.strike + 2 * rest / SPEED, 1e-9)
		expect(RushDraw.distanceAt(run, finish)).toBeCloseTo(LENGTH, 1e-9)
		expect(RushDraw.distanceAt(run, finish + 1)).toBeCloseTo(LENGTH, 1e-9)
		-- Never backward, and no step in speed at the strike.
		local last = 0
		for step = 1, 200 do
			local d = RushDraw.distanceAt(run, step * finish / 200)
			expect(d >= last - 1e-12).toBe(true)
			last = d
		end
		local before = (RushDraw.distanceAt(run, CHARGE.strike) - RushDraw.distanceAt(run, CHARGE.strike - 1e-4)) / 1e-4
		local after = (RushDraw.distanceAt(run, CHARGE.strike + 1e-4) - RushDraw.distanceAt(run, CHARGE.strike)) / 1e-4
		expect(before).toBeCloseTo(SPEED, 1e-3)
		expect(after).toBeCloseTo(SPEED, 1e-2)
	end)

	it("a telegraph predicts the line RushStarted brings", function()
		local predicted = RushDraw.predict(CHARGE, 50, Vector3.new(4, 3, 2), Vector3.new(3, 0, 4))
		expect(predicted.startedAt).toBeCloseTo(50 + CHARGE.windUp, 1e-9)
		expect(predicted.speed).toBe(SPEED)
		expect(predicted.length).toBeCloseTo(LENGTH, 1e-9)
		expect(predicted.direction.X).toBeCloseTo(0.6, EPSILON)
		expect(predicted.direction.Z).toBeCloseTo(0.8, EPSILON)
		expect(RushDraw.isRush("Charger", CHARGE)).toBe(true)
		expect(RushDraw.isRush("Brute", Enemies.byId("KoboldAxeman").attacks[1])).toBe(false)
		expect(RushDraw.isRush("Charger", Enemies.eliteAttacks.Charger)).toBe(false)
	end)

	-- D-255 (item 6): the server's body holds its line through the crouch, while its late root may
	-- still show the turn onto it. Drawn on that root it turned 60 degrees in 5 frames at the launch.
	it("before the launch the body stands on its root, turned onto its line; the launch turns nothing", function()
		local state = RushDraw.new(line(1))
		-- The late root still faces 60 degrees off the line.
		local off = at(0) * CFrame.Angles(0, math.rad(60), 0)
		local first = RushDraw.step(state, 0.5, FRAME, off) :: CFrame
		expect(state.phase).toBe("Armed")
		expect((first.Position - off.Position).Magnitude < EPSILON).toBe(true)
		-- From the root's own look: nothing jumps on the frame the drawing starts.
		expect(first.LookVector:Dot(off.LookVector)).toBeCloseTo(1, 1e-6)
		expect(RushDraw.drawing(state)).toBe(false)
		expect(RushDraw.running(state)).toBe(false)
		local now, previous, worst = 0.5, first, 0
		while now < 1 - FRAME / 2 do
			now += FRAME
			local drawn = RushDraw.step(state, now, FRAME, off) :: CFrame
			expect((drawn.Position - off.Position).Magnitude < EPSILON).toBe(true)
			worst = math.max(worst, math.acos(math.clamp(drawn.LookVector:Dot(previous.LookVector), -1, 1)))
			previous = drawn
		end
		-- On its line by the launch, turned evenly over the time left (60 degrees in 0.5 s).
		expect(previous.LookVector.Z).toBeCloseTo(-1, 1e-3)
		expect(math.deg(worst)).toBeLessThan(60 / 0.5 * FRAME * 1.05)
		local launch = RushDraw.step(state, 1 + FRAME, FRAME, off) :: CFrame
		expect(state.phase).toBe("Run")
		expect((launch.Position - at(FRAME_TRAVEL).Position).Magnitude < EPSILON).toBe(true)
		expect(launch.LookVector.Z).toBeCloseTo(-1, 1e-6)
		expect(RushDraw.drawing(state)).toBe(true)
		expect(RushDraw.running(state)).toBe(true)
	end)

	it("a long crouch turns at the chase's own rate; a launch heard late still turns at the run's", function()
		local chase = AI.archetypes.Charger.turnRate
		local state = RushDraw.new(line(2))
		local off = at(0) * CFrame.Angles(0, math.rad(60), 0)
		RushDraw.step(state, 0, FRAME, off)
		local drawn = RushDraw.step(state, FRAME, FRAME, off) :: CFrame
		local turned = math.deg(math.acos(math.clamp(drawn.LookVector:Dot(off.LookVector), -1, 1)))
		expect(turned).toBeCloseTo(chase * FRAME, 1e-3)
		-- No crouch drawn (the telegraph lost or late): the launch starts on the root's look.
		local late = RushDraw.new(line(0))
		local launched = RushDraw.step(late, 0.1, FRAME, off) :: CFrame
		local launchTurn = math.deg(math.acos(math.clamp(launched.LookVector:Dot(off.LookVector), -1, 1)))
		expect(launchTurn).toBeCloseTo(TUNING.turnRate * FRAME, 1e-3)
	end)

	it("a crouch that will not launch keeps its turn until the late root has come round, then is on it", function()
		local state = RushDraw.new(line(1))
		local off = at(0) * CFrame.Angles(0, math.rad(40), 0)
		local now = 0.5
		RushDraw.step(state, now, FRAME, off)
		for _ = 1, 6 do
			now += FRAME
			RushDraw.step(state, now, FRAME, off)
		end
		local chase = AI.archetypes.Charger.turnRate * FRAME
		local before = state.facing
		local lineAngle = math.acos(math.clamp(before:Dot(Vector3.new(0, 0, -1)), -1, 1))
		expect(RushDraw.release(state, now, off)).toBe(true)
		-- The late root still faces off: the body never turns back to it; it keeps onto its line, as
		-- the server's body holds it.
		now += FRAME
		local held = RushDraw.step(state, now, FRAME, off) :: CFrame
		expect(held ~= nil).toBe(true)
		expect(math.deg(math.acos(math.clamp(held.LookVector:Dot(before), -1, 1)))).toBeCloseTo(chase, 1e-3)
		expect(math.acos(math.clamp(held.LookVector:Dot(Vector3.new(0, 0, -1)), -1, 1)) < lineAngle).toBe(true)
		-- Past the launch it was due at, it never launches.
		while now < 1.05 do
			now += FRAME
			RushDraw.step(state, now, FRAME, off)
		end
		expect(state.along).toBe(0)
		expect(state.phase).toBe("Armed")
		-- The root comes round onto the line: the body, turning onto it at the chase's rate, is on
		-- its root once they meet, with no jump and no slide.
		local previous = (state.drawn :: CFrame).LookVector
		local worst = 0
		local frames = 0
		while state.phase == "Armed" and frames < 60 do
			now += FRAME
			frames += 1
			local drawn = RushDraw.step(state, now, FRAME, at(0))
			local look = if drawn ~= nil then drawn.LookVector else at(0).LookVector
			worst = math.max(worst, math.deg(math.acos(math.clamp(previous:Dot(look), -1, 1))))
			previous = look
		end
		expect(state.phase).toBe("Done")
		expect(worst <= chase + 1e-3).toBe(true)
	end)

	it("a crouch that will not launch slides back onto a root that never comes round", function()
		local state = RushDraw.new(line(1))
		local off = at(0) * CFrame.Angles(0, math.rad(40), 0)
		local now = 0.5
		RushDraw.step(state, now, FRAME, off)
		for _ = 1, 10 do
			now += FRAME
			RushDraw.step(state, now, FRAME, off)
		end
		RushDraw.release(state, now, off)
		local released = now
		while state.phase ~= "Done" and now < released + 2 do
			now += FRAME
			RushDraw.step(state, now, FRAME, off)
		end
		expect(state.phase).toBe("Done")
		expect(now - released <= TUNING.settleSeconds + TUNING.handBackSeconds + 2 * FRAME).toBe(true)
		-- Nothing drawn yet: released at once.
		local fresh = RushDraw.new(line(1))
		expect(RushDraw.release(fresh, 0.2, off)).toBe(false)
		expect(fresh.phase).toBe("Done")
	end)

	it("a predicted launch the server never made slides back onto the root from where it was drawn", function()
		local state = RushDraw.new(line(0))
		local now = 0
		for _ = 1, 9 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(0))
		end
		local drawnAt = state.along
		expect(drawnAt > 1).toBe(true)
		expect(RushDraw.release(state, now, at(0))).toBe(true)
		expect(state.phase).toBe("HandBack")
		now += FRAME
		local last: CFrame? = RushDraw.step(state, now, FRAME, at(0))
		expect(((last :: CFrame).Position - at(drawnAt).Position).Magnitude <= FRAME_TRAVEL + EPSILON).toBe(true)
		local worst = 0
		while last ~= nil do
			now += FRAME
			local step = RushDraw.step(state, now, FRAME, at(0))
			if step ~= nil then
				worst = math.max(worst, (step.Position - (last :: CFrame).Position).Magnitude)
			end
			last = step
		end
		-- At the hand-back's pace (the catch-up's), never a jump.
		expect(worst <= FRAME_TRAVEL + EPSILON).toBe(true)
		expect(state.phase).toBe("Done")
	end)

	it("a death in the crouch leaves the body turned where it was drawn", function()
		local state = RushDraw.new(line(1))
		local off = at(0) * CFrame.Angles(0, math.rad(40), 0)
		RushDraw.step(state, 0.5, FRAME, off)
		local drawn = RushDraw.step(state, 0.5 + FRAME, FRAME, off) :: CFrame
		expect(RushDraw.freeze(state)).toBe(true)
		expect(state.phase).toBe("Frozen")
		expect(RushDraw.step(state, 0.6, FRAME, at(0))).toBe(drawn)
	end)

	it("a launch heard late moves one frame of travel, then closes at most catchUpFraction faster", function()
		local state = RushDraw.new(line(0))
		local now = 0.1
		local previous = at(0)
		local drawn = RushDraw.step(state, now, FRAME, at(0)) :: CFrame
		expect((drawn.Position - previous.Position).Magnitude <= FRAME_TRAVEL + EPSILON).toBe(true)
		local worst = 0
		while now < 0.45 do
			previous = drawn
			now += FRAME
			drawn = RushDraw.step(state, now, FRAME, at(0)) :: CFrame
			worst = math.max(worst, (drawn.Position - previous.Position).Magnitude)
		end
		expect(worst <= (1 + TUNING.catchUpFraction) * FRAME_TRAVEL + EPSILON).toBe(true)
		-- Caught up: on the timeline again.
		expect(state.along).toBeCloseTo(RushDraw.distanceAt(state.line, now), 1e-6)
	end)

	it("a long frame moves the body the timeline's own travel over it: a hitch's step is speed x dt", function()
		-- 01.14.00 at ef698e5: the torso stepped 2.5 to 3.4 studs on the frames a rush was drawn
		-- across a 0.09 to 0.12 s frame. On the timeline that is the run itself (the server's body
		-- moved as far), not a jump: no catch-up is added on top and nothing is held back.
		local state = RushDraw.new(line(0))
		local now = 0
		for _ = 1, 6 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(0))
		end
		for _, dt in { 0.09, 0.12, FRAME } do
			local before = state.along
			now += dt
			RushDraw.step(state, now, dt, at(0))
			expect(state.along - before).toBeCloseTo(SPEED * dt, 1e-6)
			expect(state.along).toBeCloseTo(RushDraw.distanceAt(state.line, now), 1e-6)
		end
	end)

	it("never draws the body backward: a later launch from the server slows it instead", function()
		local state = RushDraw.new(line(0))
		local now = 0
		for _ = 1, 12 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(0))
		end
		local before = state.along
		RushDraw.retime(state, line(0.1))
		expect(state.along).toBeCloseTo(before, EPSILON) -- the same place in the world
		now += FRAME
		RushDraw.step(state, now, FRAME, at(0))
		expect(state.along - before).toBeCloseTo((1 - TUNING.catchUpFraction) * FRAME_TRAVEL, 1e-6)
	end)

	it("moves only a launch still to come when the server pauses the wind-up", function()
		local state = RushDraw.new(line(1))
		RushDraw.delay(state, 0.05)
		expect(state.line.startedAt).toBeCloseTo(1.05, 1e-9)
		RushDraw.step(state, 1.1, FRAME, at(0))
		RushDraw.delay(state, 0.05)
		expect(state.line.startedAt).toBeCloseTo(1.05, 1e-9)
	end)

	it("a jam caps the run; the hand-back waits for the root to reach where the server's body stopped", function()
		local state = RushDraw.new(line(0))
		local now = 0
		while now < 0.4 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(0))
		end
		RushDraw.jam(state, 6)
		now += FRAME
		RushDraw.step(state, now, FRAME, at(3))
		expect(state.phase).toBe("Settle")
		local stoodAt = state.along
		-- The root still on its way: the body stands where it got to.
		now += FRAME
		RushDraw.step(state, now, FRAME, at(5))
		expect(state.phase).toBe("Settle")
		expect(state.along).toBe(stoodAt)
		-- The root arrives where the server's body is stuck: the body slides back onto it.
		now += FRAME
		local from = RushDraw.step(state, now, FRAME, at(6)) :: CFrame
		expect(state.phase).toBe("HandBack")
		local worst = 0
		local previous = from
		while state.phase == "HandBack" do
			now += FRAME
			local drawn = RushDraw.step(state, now, FRAME, at(6)) or at(6)
			worst = math.max(worst, (drawn.Position - previous.Position).Magnitude)
			previous = drawn
		end
		expect(state.phase).toBe("Done")
		expect(worst <= FRAME_TRAVEL + EPSILON).toBe(true)
		expect(RushDraw.drawing(state)).toBe(false)
	end)

	it("a death keeps the body where it was drawn; nothing drawn yet has nothing to keep", function()
		local state = RushDraw.new(line(0))
		local now = 0
		for _ = 1, 10 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(0))
		end
		local drawn = state.drawn :: CFrame
		expect(RushDraw.freeze(state)).toBe(true)
		now += FRAME
		expect(RushDraw.step(state, now, FRAME, at(9))).toBe(drawn)
		expect(RushDraw.drawing(state)).toBe(true)
		local armed = RushDraw.new(line(5))
		expect(RushDraw.freeze(armed)).toBe(false)
		expect(armed.phase).toBe("Done")
	end)

	it("a stop heard while running holds the body where it is drawn (a Stagger before its RushEnded)", function()
		local state = RushDraw.new(line(0))
		local now = 0
		for _ = 1, 10 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(0))
		end
		RushDraw.halt(state, now)
		local held = state.along
		for _ = 1, 5 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(1))
		end
		expect(state.along).toBe(held)
		expect(state.phase).toBe("Settle")
	end)
end)

-- A wall across the pure line (down -Z from the origin) whose face stands `face` studs down it, for
-- a root that reaches `reach` studs ahead of its centre: how much farther its centre may go from
-- `from`, or nil while the wall is beyond `distance` (what RushDraw.room answers). `asked` collects
-- the distances it was asked about.
local function wallRoom(face: number, reach: number, asked: { number }?)
	return function(from: CFrame, _direction: Vector3, distance: number): number?
		if asked ~= nil then
			table.insert(asked, distance)
		end
		local free = face - reach + from.Position.Z -- the root's centre is -Z studs down the line
		if free < distance then
			return math.max(0, free)
		end
		return nil
	end
end

describe("the world stops a drawn rush where it stops the root (D-199)", function()
	local REACH = 2.5 -- the Boar root's half length

	-- Steps a rush on line(0) with `room`, its root `lag` seconds behind and stopped at `stopAt`.
	local function run(room: any, lag: number, stopAt: number, seconds: number?): (any, { CFrame }, number)
		local state = RushDraw.new(line(0))
		local drawn: { CFrame } = {}
		local now = 0
		while now < (seconds or 3) and state.phase ~= "Done" do
			now += FRAME
			local rootAt = at(math.clamp(SPEED * (now - lag), 0, stopAt))
			table.insert(drawn, RushDraw.step(state, now, FRAME, rootAt, room) or rootAt)
		end
		return state, drawn, now
	end

	local function worstStep(drawn: { CFrame }): number
		local worst = 0
		for index = 2, #drawn do
			worst = math.max(worst, (drawn[index].Position - drawn[index - 1].Position).Magnitude)
		end
		return worst
	end

	it("holds the body where the world stops its root, then hands it back as for a jam", function()
		for _, face in { 6, 8, 10 } do
			local stop = face - REACH
			local state, drawn = run(wallRoom(face, REACH), 0.25, stop)
			local farthest = 0
			for _, frame in drawn do
				farthest = math.max(farthest, -frame.Position.Z)
			end
			expect(farthest <= stop + EPSILON).toBe(true)
			expect(farthest).toBeCloseTo(stop, EPSILON)
			expect(state.limit).toBeCloseTo(stop, EPSILON)
			expect(state.phase).toBe("Done")
			expect(worstStep(drawn) <= FRAME_TRAVEL + EPSILON).toBe(true)
			-- It waits at the wall for the late root, as for a jam.
			local held = run(wallRoom(face, REACH), 0.25, stop, stop / SPEED + 0.1)
			expect(held.phase).toBe("Settle")
			expect(held.along).toBeCloseTo(stop, EPSILON)
		end
	end)

	-- Item 7: a RushEnded that comes late (the server's word on a stop its cast never saw) left the
	-- body drawn down the whole run, then slid back over all of it: a jam at 6 studs drawn 16 on.
	-- The late root has stopped well short of the drawn body: that is the server's body stuck there.
	for _, lag in { 0.25, 0.5 } do
		it(
			("a root come to rest well short of the drawn body is a jam before its word (root %.2f s late)"):format(lag),
			function()
				local state = RushDraw.new(line(0))
				local now = 0
				local farthest = 0
				while now < 3 and state.phase ~= "Done" do
					now += FRAME
					RushDraw.step(state, now, FRAME, at(math.clamp(SPEED * (now - lag), 0, 6)))
					farthest = math.max(farthest, state.along)
				end
				-- The root reached 6 studs at 6 / speed + lag and has rested restSeconds since: the body
				-- goes no farther than the timeline had it then.
				local known = 6 / SPEED + lag + AI.rushWorld.restSeconds
				expect(farthest <= RushDraw.distanceAt(line(0), known + 2 * FRAME) + EPSILON).toBe(true)
				expect(farthest < LENGTH - 1).toBe(true)
				-- Then back onto the stuck root.
				expect(state.phase).toBe("Done")
			end
		)
	end

	it("a root still in its crouch, or one at rest at the run's end, is no jam", function()
		-- A first move after a long stand: the root leaves its crouch 0.65 s late.
		local state = RushDraw.new(line(0))
		local now = 0
		local farthest = 0
		while now < 3 and state.phase ~= "Done" do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(RushDraw.distanceAt(line(0), now - 0.65)))
			farthest = math.max(farthest, state.along)
		end
		expect(farthest).toBeCloseTo(LENGTH, EPSILON)
		-- A root that runs the timeline 0.3 s late comes to rest at the run's end.
		local free = RushDraw.new(line(0))
		now = 0
		farthest = 0
		while now < 3 and free.phase ~= "Done" do
			now += FRAME
			RushDraw.step(free, now, FRAME, at(RushDraw.distanceAt(line(0), now - 0.3)))
			farthest = math.max(farthest, free.along)
		end
		expect(farthest).toBeCloseTo(LENGTH, EPSILON)
	end)

	it("a jam heard after the world stopped it draws the body neither back nor on", function()
		for _, jammed in { 3, 3.2, 5 } do
			local state = RushDraw.new(line(0))
			local room = wallRoom(6, REACH)
			local now = 0
			while now < 0.3 do
				now += FRAME
				RushDraw.step(state, now, FRAME, at(0), room)
			end
			expect(state.along).toBeCloseTo(3.5, EPSILON)
			RushDraw.jam(state, jammed)
			local drawn: { CFrame } = {}
			while state.phase ~= "Done" and now < 3 do
				now += FRAME
				local rootAt = at(math.min(jammed, 3.5))
				local frame = RushDraw.step(state, now, FRAME, rootAt, room) or rootAt
				table.insert(drawn, frame)
				expect(-frame.Position.Z <= 3.5 + EPSILON).toBe(true)
			end
			expect(state.phase).toBe("Done")
			expect(worstStep(drawn) <= FRAME_TRAVEL + EPSILON).toBe(true)
		end
	end)

	it("a free rush is drawn exactly as before: the world is asked, and finds nothing", function()
		for _, lag in { 0, 0.25, 0.5 } do
			local asked: { number } = {}
			local open = function(_from: CFrame, _direction: Vector3, distance: number): number?
				table.insert(asked, distance)
				return nil
			end
			local _, free = run(open, lag, LENGTH)
			local _, plain = run(nil, lag, LENGTH)
			expect(#free).toBe(#plain)
			for index, frame in free do
				expect(frame == plain[index]).toBe(true)
			end
			expect(#asked > 0).toBe(true)
			for _, distance in asked do
				expect(distance > 0).toBe(true)
			end
		end
	end)

	it("the server's line keeps a world stop where it stands in the world", function()
		local state = RushDraw.new(line(0))
		local room = wallRoom(6, REACH)
		local now = 0
		while now < 0.3 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(0), room)
		end
		local before = (state.drawn :: CFrame).Position
		-- The server's line starts a stud further back than the telegraph predicted.
		local server = line(0)
		server.origin = Vector3.new(0, 0, 1)
		RushDraw.retime(state, server)
		expect(state.along).toBeCloseTo(4.5, EPSILON)
		expect(state.limit).toBeCloseTo(4.5, EPSILON)
		now += FRAME
		local after = (RushDraw.step(state, now, FRAME, at(0), room) :: CFrame).Position
		expect((after - before).Magnitude <= EPSILON).toBe(true)
	end)

	it("RushDraw.room casts the root's own box as the server's worldAhead does, in the rushing group", function()
		local model = RigBuilder.build("Boar")
		local root = model.PrimaryPart :: BasePart
		root.CFrame = CFrame.new(4, 3, -2) * CFrame.Angles(0, math.rad(30), 0)
		root.CollisionGroup = AI.collision.rushing
		local direction = Vector3.new(1, 0.4, -1) -- flattened by both
		local flatDirection = Vector3.new(direction.X, 0, direction.Z).Unit
		local half = root.Size / 2
		local reach = math.abs(root.CFrame.RightVector:Dot(flatDirection)) * half.X
			+ math.abs(root.CFrame.UpVector:Dot(flatDirection)) * half.Y
			+ math.abs(root.CFrame.LookVector:Dot(flatDirection)) * half.Z
		local function recording(into: { any }, travelled: number?)
			return function(start: CFrame, size: Vector3, vector: Vector3, group: string, exclude: Instance): number?
				table.insert(into, { start = start, size = size, vector = vector, group = group, exclude = exclude })
				return travelled
			end
		end
		local server: { any } = {}
		local client: { any } = {}
		expect(EnemyService.worldAhead(model, direction, 3 + reach, recording(server, 5))).toBe(5)
		expect(RushDraw.room(root.CFrame, root.Size, direction, 3, recording(client, 5), model)).toBeCloseTo(
			5 - reach,
			EPSILON
		)
		local s, c = server[1], client[1]
		expect((s.start.Position - c.start.Position).Magnitude <= EPSILON).toBe(true)
		expect(s.start.LookVector:Dot(c.start.LookVector) >= 1 - EPSILON).toBe(true)
		expect(s.size).toBe(c.size)
		expect((s.vector - c.vector).Magnitude <= EPSILON).toBe(true)
		expect(c.group).toBe(AI.collision.rushing)
		expect(s.group).toBe(c.group)
		expect(c.exclude).toBe(model)
		-- A face nearer than the root's own reach leaves no room; nothing in the way is no stop.
		expect(RushDraw.room(root.CFrame, root.Size, direction, 3, recording({}, 1), model)).toBe(0)
		expect(RushDraw.room(root.CFrame, root.Size, direction, 3, recording({}, nil), model)).toBe(nil)
		local broken = function(): number?
			error("no world")
		end
		expect(RushDraw.room(root.CFrame, root.Size, direction, 3, broken, model)).toBe(nil)
		expect(RushDraw.room(root.CFrame, root.Size, Vector3.yAxis, 3, recording({}, 1), model)).toBe(nil)
	end)

	it(
		"RushDraw.room calls ground what the server's worldAhead does: a face within groundSlopeDegrees of up (D-204)",
		function()
			local model = RigBuilder.build("Boar")
			local root = model.PrimaryPart :: BasePart
			root.CFrame = CFrame.new(4, 3, -2) * CFrame.Angles(0, math.rad(30), 0)
			root.CollisionGroup = AI.collision.rushing
			local direction = root.CFrame.LookVector
			local slope = AI.collision.groundSlopeDegrees
			local function hitting(normal: Vector3?)
				return function(): (number?, Vector3?)
					return 5, normal
				end
			end
			-- A rise down the look: its face leans back toward the root by its slope.
			local function rise(degrees: number): Vector3
				local up = math.rad(degrees)
				return (Vector3.yAxis * math.cos(up) - direction * math.sin(up)).Unit
			end
			local reach = root.Size.Z / 2
			for _, case in
				{
					{ normal = rise(10) :: Vector3?, ground = true },
					{ normal = rise(slope - 1), ground = true },
					{ normal = rise(slope + 1), ground = false },
					{ normal = -direction, ground = false },
					{ normal = rise(150), ground = false },
					{ normal = nil, ground = false },
				}
			do
				local client = RushDraw.room(root.CFrame, root.Size, direction, 3, hitting(case.normal), model)
				local server, ground = EnemyService.worldAhead(model, direction, 3 + reach, hitting(case.normal))
				-- The server still caps its line at ground (its root stops only at a wall, D-204); the
				-- drawn body is stopped only by a wall.
				expect(server).toBe(5)
				expect(ground).toBe(case.ground)
				expect(RushDraw.isGround(case.normal)).toBe(case.ground)
				if case.ground then
					expect(client).toBe(nil)
				else
					expect(client).toBeCloseTo(5 - reach, EPSILON)
				end
			end
		end
	)
end)

describe("the drawn body meets the world as the server's does (D-205 to D-210)", function()
	local RushWorld = Harness.load("src/shared/choreo/RushWorld")
	local boar = RigBuilder.build("Boar")
	local BODY = { profile = RushWorld.profileOf(boar), size = (boar.PrimaryPart :: BasePart).Size }
	local FRONT = RushWorld.front(BODY.profile)
	local HOVER = 2.8 -- the Boar's HipHeight (1.6) plus half its root's height
	local REACH = BODY.size.Z / 2

	-- A wall across the pure line `face` studs down it, its face toward the body (the room
	-- RushDraw.room answers: the root centre's room, and the face's normal).
	local function faceRoom(face: number)
		return function(from: CFrame, _direction: Vector3, distance: number): (number?, Vector3?)
			local free = face - REACH + from.Position.Z
			if free < distance then
				return math.max(0, free), Vector3.zAxis
			end
			return nil, nil
		end
	end

	local function body(state: any)
		RushDraw.setBody(state, BODY, HOVER)
	end

	it("its own cast stops the snout on the face; the slam's cue plays once, on the frame it gets there", function()
		for _, face in { 8, 10, 14 } do
			local stop = face - FRONT
			local state = RushDraw.new(line(0))
			body(state)
			local room = faceRoom(face)
			local now = 0
			local played: { { t: number, kind: string } } = {}
			while now < 1.5 do
				now += FRAME
				RushDraw.step(state, now, FRAME, at(0), room)
				for _, cue in RushDraw.takeCues(state) do
					table.insert(played, { t = now, kind = cue.kind })
					expect(state.along).toBeCloseTo(stop, 1e-6)
				end
				expect(state.along).toBeLessThanOrEqual(stop + 1e-5) -- single-precision positions
			end
			expect(state.along).toBeCloseTo(stop, 1e-6)
			expect(state.guess).toBeCloseTo(stop, 1e-6)
			expect(#played).toBe(1)
			expect(played[1].kind).toBe("Slam")
			expect(math.abs(played[1].t - stop / SPEED)).toBeLessThanOrEqual(FRAME + 1e-9)
		end
	end)

	it("a stop only its own cast guessed is no place to hand back before the server's word", function()
		local face = 10
		local stop = face - FRONT
		local state = RushDraw.new(line(0))
		body(state)
		local room = faceRoom(face)
		local now = 0
		-- The late root passes the guessed stop at full speed (a world this client sees, the server
		-- not): the body waits for the word, never sliding after a root that runs on.
		while now < stop / SPEED + 0.3 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(math.min(SPEED * now, LENGTH)), room)
			expect(state.phase == "HandBack").toBe(false)
		end
		-- The server's slam says the same stop: once its root is there, the body slides onto it.
		RushDraw.wall(state, stop, Vector3.new(0, 3, -face), Vector3.zAxis)
		RushDraw.rest(state, stop)
		now += FRAME
		RushDraw.step(state, now, FRAME, at(stop), room)
		expect(state.phase).toBe("HandBack")
	end)

	it("the server's bend redraws the path from where the body is: no jump, its cue once at the bend", function()
		local state = RushDraw.new(line(0))
		body(state)
		local now = 0
		while now < 0.15 do
			now += FRAME
			RushDraw.step(state, now, FRAME, at(0))
		end
		-- A glance 6 studs down the line: on along a heading 30 degrees off it.
		local bend = 6
		local heading = Vector3.new(math.sin(math.rad(30)), 0, -math.cos(math.rad(30)))
		local legs = RushWorld.line(Vector3.zero, Vector3.new(0, 0, -1))
		table.insert(legs, { at = bend, from = Vector3.new(0, 0, -bend), heading = heading, facing = heading })
		local before = state.drawn :: CFrame
		RushDraw.turn(state, legs, "Glance", bend, Vector3.new(1, 3, -bend - 2), Vector3.new(-1, 0, 0))
		local previous = before
		local worst, cues = 0, 0
		while now < 0.6 do
			now += FRAME
			local drawn = RushDraw.step(state, now, FRAME, at(0)) :: CFrame
			worst = math.max(worst, (drawn.Position - previous.Position).Magnitude)
			previous = drawn
			for _, cue in RushDraw.takeCues(state) do
				cues += 1
				expect(cue.kind).toBe("Glance")
				expect(state.along).toBeGreaterThanOrEqual(bend - RushWorld.SAME_STUDS)
			end
		end
		expect(cues).toBe(1)
		expect(worst).toBeLessThanOrEqual((1 + TUNING.catchUpFraction) * FRAME_TRAVEL + EPSILON)
		-- On the bent path, facing its way.
		local spot = RushWorld.pointAt(legs, state.along)
		expect(((previous.Position - spot) * Vector3.new(1, 0, 1)).Magnitude).toBeLessThan(1e-3)
		expect(previous.LookVector:Dot(heading)).toBeCloseTo(1, 1e-3)
	end)

	it("the server's bend drops a slam this client guessed at the same wall", function()
		local state = RushDraw.new(line(0))
		body(state)
		RushDraw.wall(state, 4, Vector3.new(0, 3, -9.6), Vector3.zAxis, true)
		expect(state.limit).toBe(4)
		local legs = RushWorld.line(Vector3.zero, Vector3.new(0, 0, -1))
		table.insert(legs, { at = 4, from = Vector3.new(0, 0, -4), heading = Vector3.xAxis, facing = Vector3.xAxis })
		RushDraw.turn(state, legs, "Glance", 4, Vector3.new(0, 3, -9.6), Vector3.zAxis)
		expect(state.limit).toBeNil()
		expect(state.walled).toBe(false)
		for _, cue in state.cues do
			expect(cue.kind).toBe("Glance")
		end
		-- A slam the server told stands whatever bend follows.
		local told = RushDraw.new(line(0))
		RushDraw.wall(told, 4, nil, nil)
		RushDraw.turn(told, legs, "Glance", 4, Vector3.new(0, 3, -9.6), Vector3.zAxis)
		expect(told.limit).toBeCloseTo(4, 1e-6)
	end)

	-- The ground: a ramp rising `degrees` from 4 studs down the line, or a step `rise` high 6 down it.
	local function rampGround(degrees: number): (along: number) -> number
		return function(along: number): number
			return math.max(0, along - 4) * math.tan(math.rad(degrees))
		end
	end
	local function stepGround(rise: number): (along: number) -> number
		return function(along: number): number
			return if along >= 6 then rise else 0
		end
	end

	for _, case in
		{
			{ name = "an 8 degree ramp", ground = rampGround(8) },
			{ name = "a 15 degree ramp", ground = rampGround(15) },
			{ name = "a 1 stud step", ground = stepGround(1) },
			{ name = "a 1 stud drop", ground = stepGround(-1) },
		}
	do
		for _, lag in { 0, 0.25, 0.5 } do
			it(
				("%s, the root %.2f s late: drawn standing on the ground under it, never in it"):format(case.name, lag),
				function()
					local heightAt = case.ground
					local state = RushDraw.new(line(0))
					body(state)
					local probe = function(spot: Vector3): number?
						return heightAt(-spot.Z)
					end
					local now = 0
					local deepest, highest = 0, 0
					local landed = false
					while now < 1.4 and state.phase ~= "Done" do
						now += FRAME
						local rootAlong = math.clamp(SPEED * (now - lag), 0, LENGTH)
						local root = CFrame.lookAt(
							Vector3.new(0, heightAt(rootAlong) + HOVER, -rootAlong),
							Vector3.new(0, heightAt(rootAlong) + HOVER, -rootAlong - 1)
						)
						local drawn = RushDraw.step(state, now, FRAME, root, nil, probe)
						if drawn ~= nil and state.phase ~= "HandBack" then
							local floor = heightAt(-drawn.Position.Z) + HOVER
							deepest = math.max(deepest, floor - drawn.Position.Y)
							highest = math.max(highest, drawn.Position.Y - floor)
							landed = landed or drawn.Position.Y - floor < 1e-6
						end
					end
					-- Never sunk into it; up a rise at once; down a drop under gravity, so above it only
					-- while it falls (a stud takes sqrt(2 / fallGravity) seconds).
					expect(deepest).toBeLessThan(1e-6)
					if heightAt(10) >= 0 then
						expect(highest).toBeLessThan(1e-6)
					else
						expect(highest).toBeLessThanOrEqual(1 + 1e-6)
						expect(landed).toBe(true)
					end
				end
			)
		end
	end
end)

-- ---------------------------------------------------------------------------------------------
-- The real path
-- ---------------------------------------------------------------------------------------------

local function recorder(calls: { any }, name: string): any
	return setmetatable({}, {
		__index = function(_self: any, key: string): any
			return function(...: any): any
				table.insert(calls, { module = name, fn = key, args = { ... }, at = clock, frame = frameNow })
				return nil
			end
		end,
	})
end

-- Every part's world CFrame from the root part's CFrame and the joints' Transforms, as the engine
-- draws the rig.
local function solve(model: Model, rootFrame: CFrame): { [string]: CFrame }
	local chain = Pose.chain(model)
	local motors = Joints.map(model)
	local solved: { [string]: CFrame } = { [chain.rootName] = rootFrame }
	for _, link in chain.links do
		local motor: any = motors[link.name]
		local transform = if motor ~= nil then motor.Transform else CFrame.identity
		solved[link.part1] = solved[link.part0] * link.c0 * transform * link.c1Inverse
	end
	return solved
end

-- How far down the line (from `origin` along `direction`) the drawn body reaches: the farthest
-- corner of any part but the root part (hidden while the body is drawn away from it).
local function reachOf(model: Model, solved: { [string]: CFrame }, origin: Vector3, direction: Vector3): number
	local best = -math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= model.PrimaryPart then
			local frame = solved[part.Name]
			if frame ~= nil then
				local half = part.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local corner = frame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
							best = math.max(best, (corner - origin):Dot(direction))
						end
					end
				end
			end
		end
	end
	return best
end

type Frame = {
	t: number, -- server seconds since the launch
	offset: boolean, -- the body is drawn away from its root part
	drawn: Vector3, -- where the body is drawn from (the root part moved by the offset)
	along: number, -- that, down the line
	reach: number, -- the snout's reach down the line
	hidden: number, -- the root part's LocalTransparencyModifier
	pause: number, -- the rig's hit-stop left
	head: Vector3, -- the drawn head
	pose: Vector3, -- the head in the drawn body's own space: the clip's pose alone
	-- With `gait`: the weight the locomotion driver gave the walk this frame, and the ground speed
	-- it paced the walk to (its clip speed times the rig's walkSpeed; 0 with no walk).
	walkTarget: number,
	gait: number,
	root: Vector3, -- the root part's place
	look: Vector3, -- the drawn body's look
	charge: boolean, -- the Charge clip plays (a live handle, not fading out)
}

type Options = {
	latency: number,
	lag: number,
	telegraph: boolean?, -- default true
	telegraphLatency: number?, -- the Telegraph (and its wind-up clip) comes this late (default latency)
	started: boolean?, -- RushStarted arrives (default true)
	stopAt: number?, -- the server's body stops this far down the line
	events: { { at: number, name: string, payload: any } }?, -- seconds after the launch (server)
	hitAt: number?, -- the local blade touches the boar this many seconds after the launch
	frames: number?,
	phase: number?, -- where the launch falls in its frame (0 to 1, default 0)
	wall: number?, -- a wall's face this far down the line, which the client's world cast sees
	wallNormal: Vector3?, -- the face's normal the cast reports (default: none named)
	gait: boolean?, -- the real locomotion driver walks the rig (Replication.watch)
	wallSlam: any?, -- the slam's dust (Replication's wallSlam dependency; none when nil)
	me: Vector3?, -- where the local player's body stands (default: the world's origin)
	-- Degrees the server's body faced off the line at server time `t` (since the launch), which the
	-- replicated root shows `lag` late (default: on the line throughout).
	rootYaw: ((t: number) -> number)?,
	-- The real FrameClock on the loop's render steps (its start, then the rigs' step, its posed
	-- mark and its end), given to Replication as the client's start() does (D-342, D-343).
	frameClock: boolean?,
}

local WIND_UP_START = 10
local LAUNCH = WIND_UP_START + CHARGE.windUp
local CHARGE_CLIP = "enemy/" .. BOAR.skin .. "/" .. CHARGE.clip
local ORIGIN = Vector3.new(10, 3, 20)
local DIRECTION = Vector3.new(1, 0, -1).Unit

local function bodyAt(t: number, stopAt: number?): CFrame
	local d = math.clamp(SPEED * (t - LAUNCH), 0, stopAt or LENGTH)
	local position = ORIGIN + DIRECTION * d
	return CFrame.lookAt(position, position + DIRECTION)
end

-- The server body's velocity at `t` (what the replicated root carries with it).
local function velocityAt(t: number, stopAt: number?): Vector3
	local d = SPEED * (t - LAUNCH)
	return if d > 0 and d < (stopAt or LENGTH) then DIRECTION * SPEED else Vector3.zero
end

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

type Cast = { group: string, exclude: Instance }

-- The engine's Blockcast against a wall across the line whose face stands `face` studs down it
-- (nil: no wall): how far the box at `start` moves along `vector` before it meets the face, or nil.
-- Like the engine's, it never sees a face its box starts in or past. `casts` collects the calls.
local function wallCast(face: number?, casts: { Cast }, normal: Vector3?)
	return function(
		start: CFrame,
		size: Vector3,
		vector: Vector3,
		group: string,
		exclude: Instance
	): (number?, Vector3?)
		table.insert(casts, { group = group, exclude = exclude })
		local length = vector.Magnitude
		local along = if length > 1e-9 then (vector / length):Dot(DIRECTION) else 0
		if face == nil or along <= 1e-9 then
			return nil
		end
		local half = size / 2
		local front = (start.Position - ORIGIN):Dot(DIRECTION)
			+ math.abs(start.RightVector:Dot(DIRECTION)) * half.X
			+ math.abs(start.UpVector:Dot(DIRECTION)) * half.Y
			+ math.abs(start.LookVector:Dot(DIRECTION)) * half.Z
		if front > face then
			return nil
		end
		local travel = (face - front) / along
		if travel > length then
			return nil
		end
		return travel, normal
	end
end

type Run = { frames: { Frame }, front: number, model: Model, root: BasePart, calls: { any }, casts: { Cast } }

local function rush(options: Options): Run
	clock = WIND_UP_START - 0.2 + (options.phase or 0) * FRAME
	local model = RigBuilder.build("Boar")
	local front = EnemyService.bodyExtents(model)
	local root = model.PrimaryPart :: BasePart
	root.LocalTransparencyModifier = 0
	local function place(frame: CFrame)
		local yaw = options.rootYaw
		local turned = if yaw ~= nil
			then frame * CFrame.Angles(0, math.rad(yaw(clock - options.lag - LAUNCH)), 0)
			else frame
		root.CFrame = turned
		root.Position = frame.Position -- Lune keeps the two apart; the engine does not
		root.AssemblyLinearVelocity = velocityAt(clock - options.lag, options.stopAt)
	end
	if options.gait then
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: any
		humanoid.MoveDirection = Vector3.zero
		humanoid.FloorMaterial = Enum.Material.Grass
	end
	place(bodyAt(clock - options.lag, options.stopAt))
	local folder = Instance.new("Folder")
	model.Parent = folder
	local record = {
		id = 5,
		model = model,
		kind = "Enemy",
		defId = BOAR.id,
		rig = BOAR.skin,
		state = "Idle",
		hp = 100,
		maxHp = 120,
	}
	local me = Instance.new("Model")
	local mine = { id = 1, model = me, kind = "Player", state = "Art", weaponId = "TrialistSword" }
	local myAnimator = {
		hitStop = function() end,
		pauseRemaining = function(): number
			return 0
		end,
	}
	local calls: { any } = {}
	local casts: { Cast } = {}
	local clockStart: ((dt: number) -> ())? = nil
	local clockPosed: ((dt: number) -> ())? = nil
	local clockEnd: ((dt: number) -> ())? = nil
	if options.frameClock then
		FrameClock.bind({
			now = function(): number
				return clock
			end,
			onFrameStart = function(fn: any): () -> ()
				clockStart = fn
				return function()
					clockStart = nil
				end
			end,
			onPosed = function(fn: any): () -> ()
				clockPosed = fn
				return function()
					clockPosed = nil
				end
			end,
			onFrameEnd = function(fn: any): () -> ()
				clockEnd = fn
				return function()
					clockEnd = nil
				end
			end,
			onHeartbeat = function(): () -> ()
				return function() end
			end,
		} :: any)
	end
	local frameClock: any = if options.frameClock then FrameClock else {}
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == 5 then record elseif id == 1 then mine else nil
			end,
		},
		localId = function(): number?
			return 1
		end,
		locomotion = if options.gait then Locomotion else recorder(calls, "locomotion"),
		choreo = {
			get = function(target: any): any
				return if target == me then myAnimator else Choreo.get(target)
			end,
		},
		clipLibrary = ClipLibrary,
		trails = recorder(calls, "trails"),
		smear = recorder(calls, "smear"),
		shatter = recorder(calls, "shatter"),
		sparks = recorder(calls, "sparks"),
		telegraphs = recorder(calls, "telegraphs"),
		outline = recorder(calls, "outline"),
		switchRing = recorder(calls, "switchRing"),
		digits = recorder(calls, "digits"),
		hud = recorder(calls, "hud"),
		systemLine = recorder(calls, "systemLine"),
		sfx = recorder(calls, "sfx"),
		impact = recorder(calls, "impact"),
		camera = recorder(calls, "camera"),
		weaponCategory = function(): string
			return "OneHandedSword"
		end,
		trailToken = function(): string
			return "TrailCyanWhite"
		end,
		positionOf = function(target: Instance): Vector3
			return if target == me and options.me ~= nil then options.me else Vector3.zero
		end,
		schedule = function() end,
		now = function(): number
			return clock
		end,
		serverNow = function(): number
			return clock
		end,
		worldCast = if options.wall ~= nil then wallCast(options.wall, casts, options.wallNormal) else nil,
		wallSlam = options.wallSlam,
		atPose = frameClock.atPose,
		atStepPose = frameClock.atStepPose,
	} :: any)
	if options.gait then
		Replication.watch(record)
	end
	local animator = Choreo.get(model)
	animator:step(FRAME)

	local messages: { { at: number, name: string, payload: any, sent: boolean? } } = {}
	local telegraphAt = WIND_UP_START + (options.telegraphLatency or options.latency)
	if options.telegraph ~= false then
		table.insert(messages, {
			at = telegraphAt,
			name = "Telegraph",
			payload = {
				entityId = 5,
				attackId = CHARGE.id,
				kind = CHARGE.telegraph,
				windUp = CHARGE.windUp,
				serverTime = WIND_UP_START,
				origin = vec(ORIGIN),
				facing = vec(DIRECTION),
			},
		})
		table.insert(messages, {
			at = telegraphAt,
			name = "ActionStarted",
			payload = {
				entityId = 5,
				clipId = "enemy/" .. BOAR.skin .. "/" .. CHARGE.clip,
				serverTime = WIND_UP_START,
				facing = vec(DIRECTION),
			},
		})
	end
	if options.started ~= false then
		table.insert(messages, {
			at = LAUNCH + options.latency,
			name = "RushStarted",
			payload = {
				entityId = 5,
				attackId = CHARGE.id,
				serverTime = LAUNCH,
				origin = vec(ORIGIN),
				direction = vec(DIRECTION),
				speed = SPEED,
				duration = LENGTH / SPEED,
			},
		})
	end
	for _, event in options.events or {} do
		table.insert(messages, { at = LAUNCH + event.at + options.latency, name = event.name, payload = event.payload })
	end

	local frames: { Frame } = {}
	local hit = false
	frameNow = 0
	for _ = 1, options.frames or 170 do
		frameNow += 1
		clock += FRAME
		for _, message in messages do
			if not message.sent and clock >= message.at - 1e-9 then
				message.sent = true
				Replication.dispatch(message.name, message.payload)
			end
		end
		place(bodyAt(clock - options.lag, options.stopAt))
		local hitAt = options.hitAt
		if hitAt ~= nil and not hit and clock >= LAUNCH + hitAt then
			hit = true
			Replication.contact({
				targetId = 5,
				windowIndex = 1,
				artId = nil,
				tier = "Normal",
				position = root.Position,
			})
		end
		-- The frame's render steps: FrameClock's start, the rigs' (this animator), its posed mark.
		if clockStart ~= nil then
			clockStart(FRAME)
		end
		animator:step(FRAME)
		if clockPosed ~= nil then
			clockPosed(FRAME)
		end
		if clockEnd ~= nil then
			clockEnd(FRAME)
		end
		local offset: CFrame? = (animator :: any).bodyOffset
		local drawn = root.CFrame * (offset or CFrame.identity)
		local solved = solve(model, root.CFrame)
		local walkTarget, gait = 0, 0
		local charge = false
		for _, handle in (animator :: any).mixer:handles() do
			if handle.clipId == ChoreoData.rigs.Boar.walk and not handle.stopping then
				walkTarget = handle.targetWeight
				gait = if walkTarget > 0 then handle.speed * Rigs.Boar.walkSpeed else 0
			end
			if handle.clipId == CHARGE_CLIP and not handle.stopping and not handle.done then
				charge = true
			end
		end
		table.insert(frames, {
			t = clock - LAUNCH,
			offset = offset ~= nil,
			drawn = drawn.Position,
			along = (drawn.Position - ORIGIN):Dot(DIRECTION),
			reach = reachOf(model, solved, ORIGIN, DIRECTION),
			hidden = root.LocalTransparencyModifier,
			pause = animator:pauseRemaining(),
			head = solved.Head.Position,
			pose = drawn:PointToObjectSpace(solved.Head.Position),
			walkTarget = walkTarget,
			gait = gait,
			root = root.Position,
			look = drawn.LookVector,
			charge = charge,
		})
	end
	if options.gait then
		Replication.unwatch(record)
	end
	if options.frameClock then
		FrameClock.bind(nil)
	end
	return { frames = frames, front = front, model = model, root = root, calls = calls, casts = casts }
end

-- The server time (since the launch) the drawn snout first reaches `distance` down the line.
local function reachedAt(run: Run, distance: number): number?
	for _, frame in run.frames do
		if frame.reach >= distance then
			return frame.t
		end
	end
	return nil
end

-- The largest frame-to-frame move of the drawn body on the frames its offset starts or ends, and
-- over the whole run.
local function steps(run: Run): (number, number, number)
	local starts, ends, worst = 0, 0, 0
	local frames = run.frames
	for index = 2, #frames do
		local step = (frames[index].drawn - frames[index - 1].drawn).Magnitude
		worst = math.max(worst, step)
		if frames[index].offset and not frames[index - 1].offset then
			starts = math.max(starts, step)
		elseif frames[index - 1].offset and not frames[index].offset then
			ends = math.max(ends, step)
		end
	end
	return starts, ends, worst
end

-- Targets down the line, near edge this far from the crouch point (the line's reach is 14).
local TARGETS = { 7, 8, 10, 12, CHARGE.reach }

describe("a Boar's rush through Replication and Choreo (D-171, item 1)", function()
	for _, case in
		{
			{ latency = 0, lag = 0.25 },
			{ latency = 0.2, lag = 0.25 },
			{ latency = 0.5, lag = 0.5 },
			{ latency = FRAME, lag = 0.5 },
		}
	do
		it(
			("the snout reaches each target within a frame of the server's contact (latency %.2f s, root %.2f s late)"):format(
				case.latency,
				case.lag
			),
			function()
				local run = rush({ latency = case.latency, lag = case.lag })
				expect(run.front).toBeCloseTo(5.6, 0.01) -- the snout ahead of the root (the server's front)
				for _, distance in TARGETS do
					local contact = math.max(0, (distance - run.front) / SPEED)
					local drawn = reachedAt(run, distance)
					expect(drawn ~= nil).toBe(true)
					expect(math.abs((drawn :: number) - contact) <= FRAME + EPSILON).toBe(true)
				end
				-- Nothing jumps: the offset starts and ends within a frame of the run's own travel,
				-- and the body is never drawn faster than the run.
				local starts, ends, worst = steps(run)
				expect(starts <= FRAME_TRAVEL + EPSILON).toBe(true)
				expect(ends <= FRAME_TRAVEL + EPSILON).toBe(true)
				expect(worst <= FRAME_TRAVEL + EPSILON).toBe(true)
				-- Drawn away from the root while the run lasts; back on it, shown, once the root came.
				local last = run.frames[#run.frames]
				expect(last.offset).toBe(false)
				expect(last.hidden).toBe(0)
				for _, frame in run.frames do
					if frame.t > 0 and frame.t < CHARGE.strike then
						expect(frame.offset).toBe(true)
						expect(frame.hidden).toBe(TUNING.hiddenRootTransparency)
					end
					if frame.t < 0 then
						-- Before the launch the body stands on its root (turned onto its line, D-255).
						expect((frame.drawn - frame.root).Magnitude < EPSILON).toBe(true)
					end
				end
				-- The body comes to rest where the server's body stopped.
				expect(last.along).toBeCloseTo(LENGTH, EPSILON)
			end
		)
	end

	it("without the telegraph (lost on the way), RushStarted alone draws it, catching up with no jump", function()
		local run = rush({ latency = 0.1, lag = 0.25, telegraph = false })
		local starts, ends, worst = steps(run)
		expect(starts <= FRAME_TRAVEL + EPSILON).toBe(true)
		expect(ends <= FRAME_TRAVEL + EPSILON).toBe(true)
		expect(worst <= (1 + TUNING.catchUpFraction) * FRAME_TRAVEL + EPSILON).toBe(true)
		-- Caught up by the line's far end.
		local contact = (CHARGE.reach - run.front) / SPEED
		expect(math.abs((reachedAt(run, CHARGE.reach) :: number) - contact) <= FRAME + EPSILON).toBe(true)
	end)

	it("without RushStarted (lost on the way), the telegraph's prediction draws it on time", function()
		local run = rush({ latency = 0.1, lag = 0.5, started = false })
		for _, distance in TARGETS do
			local contact = math.max(0, (distance - run.front) / SPEED)
			expect(math.abs((reachedAt(run, distance) :: number) - contact) <= FRAME + EPSILON).toBe(true)
		end
	end)

	it("a telegraph heard after its own RushStarted never draws the body back to the crouch", function()
		-- Out of order: the unreliable Telegraph came after the reliable RushStarted it led to. Re-armed
		-- as a fresh prediction it stepped the running body back 1.40 studs (latency 0.25 and 0.5).
		for _, latency in { 0, 0.25, 0.5 } do
			local run = rush({
				latency = latency,
				lag = latency + 0.15,
				telegraphLatency = CHARGE.windUp + latency + 0.05,
				frames = 200,
			})
			local frames = run.frames
			for index = 2, #frames do
				expect(frames[index].along - frames[index - 1].along >= -EPSILON).toBe(true)
			end
			-- A wind-up the client has seen launch shows no telegraph either, nor plays its Charge
			-- clip from the middle of its run (item 8: its ActionStarted is as late).
			for _, call in run.calls do
				expect(call.module == "telegraphs" and call.fn == "show").toBe(false)
			end
			for _, frame in frames do
				expect(frame.charge).toBe(false)
			end
			expect(frames[#frames].along).toBeCloseTo(LENGTH, EPSILON)
		end
	end)

	-- Item 6 (D-255): recording A 10.25 to 10.30 s, the boar turned 60 degrees in a few frames at its
	-- launch: its late root still showed the turn onto the line the server's body already held.
	for _, latency in { 0.1, 0.25 } do
		it(
			("the crouch turns the body onto its line before the launch: no snap (latency %.2f s)"):format(latency),
			function()
				local run = rush({
					latency = latency,
					lag = latency + 0.15,
					-- The server's body still turning onto its line at the wind-up's start, at the chase's
					-- rate: its late root shows it 60 degrees off at the launch.
					rootYaw = function(t: number): number
						return math.clamp(60 - AI.archetypes.Charger.turnRate * (t - 0.05), 0, 60)
					end,
				})
				local worst = 0
				for index = 2, #run.frames do
					local a, b = run.frames[index - 1].look, run.frames[index].look
					worst = math.max(worst, math.deg(math.acos(math.clamp(a:Dot(b), -1, 1))))
				end
				-- Before: 12 degrees a frame (the run's 720 a second) over the launch's first 5 frames.
				-- Now at most the turn the crouch's time left needs, about 2 degrees a frame.
				expect(worst <= 60 / (CHARGE.windUp - latency) * FRAME + 0.2).toBe(true)
				for _, frame in run.frames do
					if frame.t >= 0 and frame.t < CHARGE.strike then
						expect(frame.look:Dot(DIRECTION)).toBeCloseTo(1, 1e-3)
					end
				end
				expect(run.frames[#run.frames].offset).toBe(false)
			end
		)
	end

	it("a Stagger in the crouch keeps the body's turn until its late root has come round: no snap back", function()
		local chase = AI.archetypes.Charger.turnRate
		local run = rush({
			latency = 0.1,
			lag = 0.25,
			started = false,
			stopAt = 0,
			-- The server's body coming round onto its line late in the crouch, slower than the chase
			-- turns: its late root still 21 degrees off when the Stagger is heard.
			rootYaw = function(t: number): number
				return math.clamp(60 * (-0.1 - t), 0, 60)
			end,
			events = {
				{ at = -0.3, name = "StateChanged", payload = { entityId = 5, state = "Stagger", duration = 1 } },
			},
		})
		local worst = 0
		for index = 2, #run.frames do
			local a, b = run.frames[index - 1].look, run.frames[index].look
			worst = math.max(worst, math.deg(math.acos(math.clamp(a:Dot(b), -1, 1))))
			expect((run.frames[index].drawn - run.frames[index].root).Magnitude < EPSILON).toBe(true)
		end
		expect(worst <= chase * FRAME + 0.05).toBe(true)
		expect(run.frames[#run.frames].offset).toBe(false)
	end)

	-- Item 7 (D-256): a jam the server's cast never saw, told late: before, the body ran the whole
	-- line (22 studs) past the stuck root at 6, then slid back over all of it.
	for _, lag in { 0.25, 0.5 } do
		it(
			("a jam told after the run is over: the late root at rest stops the drawn body (root %.2f s late)"):format(
				lag
			),
			function()
				local run = rush({
					latency = lag,
					lag = lag,
					stopAt = 6,
					frames = 220,
					events = {
						{
							at = 1.1,
							name = "RushEnded",
							payload = {
								entityId = 5,
								launchedAt = LAUNCH,
								serverTime = LAUNCH + 1.1,
								distance = 6,
								reason = "Jammed",
							},
						},
					},
				})
				local farthest = 0
				for _, frame in run.frames do
					farthest = math.max(farthest, frame.along)
				end
				local known = 6 / SPEED + lag + AI.rushWorld.restSeconds
				expect(farthest <= RushDraw.distanceAt(line(0), known + 2 * FRAME) + EPSILON).toBe(true)
				local _, ends, worst = steps(run)
				expect(ends <= FRAME_TRAVEL + EPSILON).toBe(true)
				expect(worst <= FRAME_TRAVEL + EPSILON).toBe(true)
				local last = run.frames[#run.frames]
				expect(last.offset).toBe(false)
				expect(last.along).toBeCloseTo(6, EPSILON)
			end
		)
	end

	-- Item 5 (D-254): a hold or a sleep in the wind-up dropped the attack without a word, and the
	-- client drew the launch its telegraph predicted: a phantom 22-stud rush, the tell still lit.
	it("a wind-up the server dropped draws no rush, takes its tell down and stops its clip", function()
		local run = rush({
			latency = 0.1,
			lag = 0.25,
			started = false,
			stopAt = 0,
			events = {
				{
					at = -0.3,
					name = "RushEnded",
					payload = {
						entityId = 5,
						launchedAt = LAUNCH,
						serverTime = LAUNCH - 0.3,
						distance = 0,
						reason = "Dropped",
					},
				},
			},
		})
		local farthest = 0
		for _, frame in run.frames do
			farthest = math.max(farthest, math.abs(frame.along))
			expect((frame.drawn - frame.root).Magnitude < EPSILON).toBe(true)
			if frame.t > -0.2 + FRAME then
				expect(frame.charge).toBe(false)
			end
		end
		expect(farthest < EPSILON).toBe(true)
		local hidden = false
		for _, call in run.calls do
			if call.module == "telegraphs" and call.fn == "hide" then
				hidden = true
			end
		end
		expect(hidden).toBe(true)
		expect(run.frames[#run.frames].offset).toBe(false)
	end)

	it("a jam: the body stops being drawn ahead, then slides back onto the stuck root without a jump", function()
		-- A wall 9 studs down the line; the server's body falls jamLagStuds behind its clock at
		-- the 0.5 s tick and says so.
		local run = rush({
			latency = 0.1,
			lag = 0.25,
			stopAt = 9,
			events = {
				{
					at = 0.5,
					name = "RushEnded",
					payload = {
						entityId = 5,
						launchedAt = LAUNCH,
						serverTime = LAUNCH + 0.5,
						distance = 9,
						reason = "Jammed",
					},
				},
			},
		})
		local farthest = 0
		for _, frame in run.frames do
			farthest = math.max(farthest, frame.along)
		end
		-- Drawn on its clock until the word came (0.6 s): no farther than the timeline then.
		expect(farthest <= RushDraw.distanceAt(line(0), 0.6 + FRAME) + EPSILON).toBe(true)
		local starts, ends, worst = steps(run)
		expect(starts <= FRAME_TRAVEL + EPSILON).toBe(true)
		expect(ends <= FRAME_TRAVEL + EPSILON).toBe(true)
		expect(worst <= FRAME_TRAVEL + EPSILON).toBe(true)
		local last = run.frames[#run.frames]
		expect(last.offset).toBe(false)
		expect(last.along).toBeCloseTo(9, EPSILON)
	end)

	it("a Stagger holds the body where it is drawn; it goes back to the root once that arrives", function()
		for _, lag in { 0.25, 0.5 } do
			local run = rush({
				latency = 0.1,
				lag = lag,
				stopAt = 8.4,
				events = {
					{ at = 0.3, name = "StateChanged", payload = { entityId = 5, state = "Stagger", duration = 0.6 } },
					{
						at = 0.3,
						name = "RushEnded",
						payload = {
							entityId = 5,
							launchedAt = LAUNCH,
							serverTime = LAUNCH + 0.3,
							distance = 8.4,
							reason = "Interrupted",
						},
					},
				},
			})
			local heldAt: number? = nil
			for _, frame in run.frames do
				if frame.t >= 0.4 + FRAME and frame.offset then
					heldAt = heldAt or frame.along
				end
			end
			-- Held where the word found it: the timeline when the Stagger came, never farther.
			expect(heldAt ~= nil).toBe(true)
			expect((heldAt :: number) <= RushDraw.distanceAt(line(0), 0.4) + EPSILON).toBe(true)
			-- The hand-back starts once the root (lag late) has come to where the body stopped.
			local handedAt: number? = nil
			for index = 2, #run.frames do
				local frame = run.frames[index]
				if frame.offset and frame.along < run.frames[index - 1].along - EPSILON then
					handedAt = handedAt or frame.t
				end
			end
			local arrives = 8.4 / SPEED + lag - TUNING.settleStuds / SPEED
			expect(handedAt ~= nil).toBe(true)
			expect(math.abs((handedAt :: number) - arrives) <= 2 * FRAME).toBe(true)
			local _, ends, worst = steps(run)
			expect(ends <= FRAME_TRAVEL + EPSILON).toBe(true)
			expect(worst <= FRAME_TRAVEL + EPSILON).toBe(true)
			expect(run.frames[#run.frames].along).toBeCloseTo(8.4, EPSILON)
		end
	end)

	it("a death leaves the body where it was drawn, its root hidden, while the root comes to a stop", function()
		local run = rush({
			latency = 0.1,
			lag = 0.25,
			stopAt = 8.4,
			events = {
				{
					at = 0.3,
					name = "EntityDied",
					payload = { entityId = 5, position = vec(ORIGIN), shatter = BOAR.shatter, name = BOAR.name },
				},
				{
					at = 0.3,
					name = "RushEnded",
					payload = {
						entityId = 5,
						launchedAt = LAUNCH,
						serverTime = LAUNCH + 0.3,
						distance = 8.4,
						reason = "Died",
					},
				},
			},
		})
		local diedAt: number? = nil
		for _, frame in run.frames do
			if frame.t >= 0.4 then
				diedAt = diedAt or frame.along
				expect(frame.along).toBeCloseTo(diedAt :: number, EPSILON)
				expect(frame.offset).toBe(true)
				expect(frame.hidden).toBe(TUNING.hiddenRootTransparency)
			end
		end
		expect(Replication.drawnAway(run.root)).toBe(true)
	end)

	it("the local blade skips a root the body is drawn away from, and tests it again once it is back", function()
		local run = rush({ latency = 0.05, lag = 0.25, frames = 60 })
		expect(run.frames[#run.frames].offset).toBe(true)
		expect(Replication.drawnAway(run.root)).toBe(true)
		local done = rush({ latency = 0.05, lag = 0.25 })
		expect(Replication.drawnAway(done.root)).toBe(false)
		expect(Replication.drawnAway(Instance.new("Part"))).toBe(false)
	end)

	it("a hit on a launched rush holds nothing of it (the server pauses nothing of it either)", function()
		local launched = rush({ latency = 0.05, lag = 0.25, hitAt = 0.2, frames = 75 })
		local played = 0
		for _, call in launched.calls do
			if call.module == "impact" and call.fn == "hit" then
				played += 1
			end
		end
		expect(played).toBe(1) -- the contact played its moment
		for _, frame in launched.frames do
			expect(frame.pause).toBe(0)
		end
		-- A hit in the crouch still holds the rig.
		local crouched = rush({ latency = 0.05, lag = 0.25, hitAt = -0.3, frames = 40 })
		local held = 0
		for _, frame in crouched.frames do
			held = math.max(held, frame.pause)
		end
		expect(held > 0).toBe(true)
	end)

	it("the rush's own hit on a player does not stop its legs while its body runs on (D-176)", function()
		local function strike(at: number, tier: string): any
			return {
				at = at,
				name = "HitConfirmed",
				payload = {
					attackerId = 5,
					targetId = 1,
					damage = 20,
					crit = false,
					gaugeDamage = 0,
					killed = tier == "Kill",
					broke = false,
					hitStop = tier,
					position = vec(ORIGIN + DIRECTION * 9),
					parried = false,
					guarded = false,
					reflected = false,
					hitIndex = 1,
				},
			}
		end
		-- Even a kill's long hit-stop: the launch's own hold is long behind it.
		for _, tier in { "Normal", "Kill" } do
			local run = rush({ latency = 0.05, lag = 0.25, events = { strike(0.2, tier) }, frames = 80 })
			for _, frame in run.frames do
				expect(frame.pause).toBe(0)
			end
		end
	end)
end)

describe("a Boar's rush into a wall through Replication and Choreo (D-199)", function()
	-- The root's half length: a server body only its root's box stopped (a wall its own cast missed,
	-- told late as Jammed) stands this far short of the wall's face (D-197). This client's cast still
	-- stops the drawn snout on the face (D-205) and never draws it past the server's stop; the hand-back
	-- waits for the server's word, not the root running past this client's own stop.
	local REACH = 2.5
	for _, face in { 6, 8, 10 } do
		for _, lag in { 0, 0.25, 0.5 } do
			it(
				("the body is drawn no farther than the wall stops its root (wall %d studs, %.2f s late)"):format(
					face,
					lag
				),
				function()
					local stop = face - REACH
					-- The server says Jammed once its clock is jamLagStuds past the stuck body (the
					-- latest word it sends; the body has stood at the wall a while by then).
					local jammedAt = (stop + AI.archetypes.Charger.jamLagStuds) / SPEED + AI.tickSeconds()
					local run = rush({
						latency = lag,
						lag = lag,
						stopAt = stop,
						wall = face,
						events = {
							{
								at = jammedAt,
								name = "RushEnded",
								payload = {
									entityId = 5,
									launchedAt = LAUNCH,
									serverTime = LAUNCH + jammedAt,
									distance = stop,
									reason = "Jammed",
								},
							},
						},
					})
					local farthest = -math.huge
					for _, frame in run.frames do
						farthest = math.max(farthest, frame.along)
					end
					expect(farthest <= stop + EPSILON).toBe(true)
					-- Nothing jumps, the RushEnded included; it ends on its root, shown.
					local starts, ends, worst = steps(run)
					expect(starts <= FRAME_TRAVEL + EPSILON).toBe(true)
					expect(ends <= FRAME_TRAVEL + EPSILON).toBe(true)
					expect(worst <= FRAME_TRAVEL + EPSILON).toBe(true)
					local last = run.frames[#run.frames]
					expect(last.offset).toBe(false)
					expect(last.hidden).toBe(0)
					expect(last.along).toBeCloseTo(stop, EPSILON)
					-- The cast is the rushing root's: the world only, never its own model.
					expect(#run.casts > 0).toBe(true)
					for _, cast in run.casts do
						expect(cast.group).toBe(AI.collision.rushing)
						expect(cast.exclude).toBe(run.model)
					end
				end
			)
		end
	end

	it("a rise the root climbs is ground, not a wall: the rush is drawn as with nothing ahead", function()
		local up = math.rad(AI.collision.groundSlopeDegrees - 1)
		local rise = (Vector3.yAxis * math.cos(up) - DIRECTION * math.sin(up)).Unit
		for _, lag in { 0.25, 0.5 } do
			local ramp = rush({ latency = lag, lag = lag, wall = 8, wallNormal = rise })
			local plain = rush({ latency = lag, lag = lag })
			expect(#ramp.casts > 0).toBe(true)
			for index, frame in ramp.frames do
				expect(frame.along).toBe(plain.frames[index].along)
			end
			-- A face as steep as a wall still stops it.
			local wall = rush({ latency = lag, lag = lag, stopAt = 8 - REACH, wall = 8, wallNormal = -DIRECTION })
			local farthest = -math.huge
			for _, frame in wall.frames do
				farthest = math.max(farthest, frame.along)
			end
			expect(farthest <= 8 - REACH + EPSILON).toBe(true)
		end
	end)

	it("a rush with no wall ahead is drawn as before (the cast finds nothing)", function()
		for _, lag in { 0.25, 0.5 } do
			local open = rush({ latency = lag, lag = lag, wall = 1000 })
			local plain = rush({ latency = lag, lag = lag })
			expect(#open.casts > 0).toBe(true)
			for index, frame in open.frames do
				expect(frame.along).toBe(plain.frames[index].along)
			end
		end
	end)
end)

describe("a Boar's slam drawn through Replication and Choreo (D-205, D-208, D-210)", function()
	local WORLD = AI.rushWorld
	-- The snout a slam rests on the face: the farthest ahead the body reaches in any pose its rush
	-- draws it in (RushWorld.bodyOf, the body the server's Charger and every client judge a wall on,
	-- D-437).
	local RushWorld = Harness.load("src/shared/choreo/RushWorld")
	local FRONT: number = RushWorld.front((RushWorld.bodyOf(RigBuilder.build("Boar")) :: any).poses)
	-- What the server says of a slam into a wall `face` studs down the line: "Wall" as soon as its cast
	-- sees the face (lookAheadStuds past the clock's snout), with the body's stop (its snout on the
	-- face) and where it meets the face; then, once the timeline brings the snout there, the daze's
	-- Stagger from the front and the stop that ends the rush, at that same distance.
	local function slam(face: number): { any }
		local stop = face - FRONT
		local seen = math.max(0, (stop - WORLD.lookAheadStuds) / SPEED)
		local dazed = stop / SPEED
		return {
			{
				at = seen,
				name = "RushEnded",
				payload = {
					entityId = 5,
					launchedAt = LAUNCH,
					serverTime = LAUNCH + seen,
					distance = stop,
					reason = "Wall",
					contact = vec(ORIGIN + DIRECTION * face),
					normal = vec(-DIRECTION),
				},
			},
			{
				at = dazed,
				name = "StateChanged",
				payload = { entityId = 5, state = "Stagger", duration = WORLD.slamDazeSeconds, direction = "Front" },
			},
			{
				at = dazed,
				name = "RushEnded",
				payload = {
					entityId = 5,
					launchedAt = LAUNCH,
					serverTime = LAUNCH + dazed,
					distance = stop,
					reason = "Interrupted",
				},
			},
		}
	end

	-- The rush with the rushContact cues it fired: the frame (server time since the launch) and what.
	type Cue = { t: number, kind: string, point: Vector3, normal: Vector3 }
	local function watched(options: Options): (Run, { Cue })
		local cues: { Cue } = {}
		local connection = Replication.rushContact:Connect(
			function(_record, kind: string, point: Vector3, normal: Vector3)
				table.insert(cues, { t = clock - LAUNCH, kind = kind, point = point, normal = normal })
			end
		)
		local run = rush(options)
		connection:Disconnect()
		return run, cues
	end

	-- Every wall this client's world has too, at every lag; one only the server's world has, when its
	-- word comes before the drawn snout gets there (it is sent lookAheadStuds ahead of the clock).
	local cases: { { face: number, lag: number, seen: boolean } } = {}
	for _, face in { 6, 8, 10 } do
		for _, lag in { 0, 0.25, 0.5 } do
			table.insert(cases, { face = face, lag = lag, seen = true })
		end
		table.insert(cases, { face = face, lag = 0, seen = false })
	end
	table.insert(cases, { face = 14, lag = 0.1, seen = false })
	for _, case in cases do
		local face, lag, seen = case.face, case.lag, case.seen
		it(
			("the snout is drawn onto the face and no further, its cue on that frame (wall %d studs, %.2f s late, %s)"):format(
				face,
				lag,
				if seen then "this client sees it too" else "the server's word alone"
			),
			function()
				local stop = face - FRONT
				local run, cues = watched({
					latency = lag,
					lag = lag,
					stopAt = stop,
					wall = if seen then face else nil,
					events = slam(face),
				})
				-- Flush: drawn to the stop (the snout on the face), never past it.
				local farthest, reachedAt = -math.huge, nil
				for _, frame in run.frames do
					farthest = math.max(farthest, frame.along)
					if reachedAt == nil and frame.along >= stop - EPSILON then
						reachedAt = frame.t
					end
				end
				expect(farthest).toBeLessThanOrEqual(stop + EPSILON)
				expect(farthest).toBeGreaterThan(stop - EPSILON)
				-- On the timeline: there no later than a frame after the server's body.
				expect(reachedAt).never.toBeNil()
				expect((reachedAt :: number) - stop / SPEED).toBeLessThanOrEqual(FRAME + EPSILON)
				-- One slam cue, on the frame the snout reaches the face, where the face is.
				expect(#cues).toBe(1)
				expect(cues[1].kind).toBe("Slam")
				expect(cues[1].t).toBeCloseTo(reachedAt :: number, EPSILON)
				local at = (cues[1].point - ORIGIN):Dot(DIRECTION)
				expect(at).toBeCloseTo(face, 1e-2)
				expect(cues[1].normal:Dot(-DIRECTION)).toBeCloseTo(1, 1e-3)
				-- Nothing jumps, the daze and the RushEnded included; it ends on its root, shown.
				local starts, ends, worst = steps(run)
				expect(starts).toBeLessThanOrEqual(FRAME_TRAVEL + EPSILON)
				expect(ends).toBeLessThanOrEqual(FRAME_TRAVEL + EPSILON)
				expect(worst).toBeLessThanOrEqual(FRAME_TRAVEL + EPSILON)
				local last = run.frames[#run.frames]
				expect(last.offset).toBe(false)
				expect(last.hidden).toBe(0)
				expect(last.along).toBeCloseTo(stop, EPSILON)
			end
		)
	end

	-- The slam's cue (D-217): the dust and the stone thud where the snout meets the face, on the
	-- frame it gets there and once; the camera shakes only when that is near the local player.
	local slamCases: { { lag: number, seen: boolean } } = {
		{ lag = 0, seen = true },
		{ lag = 0.25, seen = true },
		{ lag = 0.5, seen = true },
		{ lag = 0, seen = false },
	}
	for _, case in slamCases do
		for _, near in { true, false } do
			it(
				("plays the slam's dust and thud once at the contact on the stop frame, %s (%.2f s late, %s)"):format(
					if near then "shaking the camera near the local player" else "no shake far from the local player",
					case.lag,
					if case.seen then "this client sees the wall" else "the server's word alone"
				),
				function()
					local SLAM = Fx.wallSlam
					local face = 8
					local stop = face - FRONT
					local contact = ORIGIN + DIRECTION * face
					local dust: { { at: number, point: Vector3, normal: Vector3 } } = {}
					local run, cues = watched({
						latency = case.lag,
						lag = case.lag,
						stopAt = stop,
						wall = if case.seen then face else nil,
						events = slam(face),
						wallSlam = {
							slam = function(point: Vector3, normal: Vector3): number
								table.insert(dust, { at = clock, point = point, normal = normal })
								return 0
							end,
						},
						me = contact - DIRECTION * (if near then SLAM.shakeRadius - 1 else SLAM.shakeRadius + 1),
					})
					expect(#cues).toBe(1)
					local cue = cues[1]
					expect(cue.kind).toBe("Slam")
					-- The dust: once, on the cue's frame, at the cue's point, thrown off the face.
					expect(#dust).toBe(1)
					expect(dust[1].at - LAUNCH).toBeCloseTo(cue.t, EPSILON)
					expect((dust[1].point - cue.point).Magnitude).toBeLessThan(EPSILON)
					expect(dust[1].normal:Dot(cue.normal)).toBeCloseTo(1, 1e-6)
					-- The thud: the slam's cue, once, on that frame, at that point.
					local thuds, shakes = {}, {}
					for _, call in run.calls do
						if call.module == "sfx" and call.fn == "cue" and call.args[1] == SLAM.cue then
							table.insert(thuds, call)
						elseif call.module == "camera" and call.fn == "shake" then
							table.insert(shakes, call)
						end
					end
					expect(#thuds).toBe(1)
					expect(thuds[1].at - LAUNCH).toBeCloseTo(cue.t, EPSILON)
					expect((thuds[1].args[2] - cue.point).Magnitude).toBeLessThan(EPSILON)
					if near then
						expect(#shakes).toBe(1)
						expect(shakes[1].args[1]).toBe(SLAM.shakeTier)
						expect(shakes[1].at - LAUNCH).toBeCloseTo(cue.t, EPSILON)
					else
						expect(#shakes).toBe(0)
					end
				end
			)
		end
	end

	-- The engine draws a step's pose on the next frame (D-342: Choreo writes it again on
	-- PreSimulation, after the draw), so the frame whose rig step puts the snout on the face still
	-- draws it short. The slam's dust, thud and shake wait for the next frame, the first that draws
	-- the snout on the face, never one ahead of it (D-343).
	local ENGINE_LAG = 1
	for _, case in slamCases do
		it(
			("shows the slam's dust, thud and shake on the first frame that draws the snout on the face (%.2f s late, %s)"):format(
				case.lag,
				if case.seen then "this client sees the wall" else "the server's word alone"
			),
			function()
				local SLAM = Fx.wallSlam
				local face = 8
				local stop = face - FRONT
				local contact = ORIGIN + DIRECTION * face
				local dust: { number } = {}
				local run = rush({
					latency = case.lag,
					lag = case.lag,
					stopAt = stop,
					wall = if case.seen then face else nil,
					events = slam(face),
					wallSlam = {
						slam = function(_point: Vector3, _normal: Vector3): number
							table.insert(dust, frameNow)
							return 0
						end,
					},
					me = contact - DIRECTION * (SLAM.shakeRadius - 1),
					frameClock = true,
				})
				-- The step that writes the snout on the face, and the first frame that draws it.
				local wrote: number? = nil
				for index, frame in run.frames do
					if wrote == nil and frame.along >= stop - EPSILON then
						wrote = index
					end
				end
				expect(wrote).never.toBeNil()
				local drawn = (wrote :: number) + ENGINE_LAG
				expect(#dust).toBe(1)
				if dust[1] ~= drawn then
					error(
						("the slam's dust showed on frame %d, the snout first drawn on the face on %d"):format(
							dust[1],
							drawn
						)
					)
				end
				local thuds, shakes = {}, {}
				for _, call in run.calls do
					if call.module == "sfx" and call.fn == "cue" and call.args[1] == SLAM.cue then
						table.insert(thuds, call.frame)
					elseif call.module == "camera" and call.fn == "shake" then
						table.insert(shakes, call.frame)
					end
				end
				expect(#thuds).toBe(1)
				expect(thuds[1]).toBe(drawn)
				expect(#shakes).toBe(1)
				expect(shakes[1]).toBe(drawn)
			end
		)
	end

	-- The slam's shake fades with distance (D-288): the whole Kill tier up to shakeFullRadius from
	-- the contact, CameraMath.falloff beyond it, so a slam just inside shakeRadius no longer shakes
	-- as hard as one at the player's feet.
	for _, distance in { Fx.wallSlam.shakeFullRadius - 2, Fx.wallSlam.shakeFullRadius + 3, Fx.wallSlam.shakeRadius - 1 } do
		it(("scales the slam's shake by its falloff %.0f studs from the contact"):format(distance), function()
			local SLAM = Fx.wallSlam
			local face = 8
			local contact = ORIGIN + DIRECTION * face
			local run = watched({
				latency = 0,
				lag = 0,
				stopAt = face - FRONT,
				wall = face,
				events = slam(face),
				wallSlam = {
					slam = function(_point: Vector3, _normal: Vector3): number
						return 0
					end,
				},
				me = contact - DIRECTION * distance,
			})
			local shakes = {}
			for _, call in run.calls do
				if call.module == "camera" and call.fn == "shake" then
					table.insert(shakes, call)
				end
			end
			expect(#shakes).toBe(1)
			expect(shakes[1].args[1]).toBe(SLAM.shakeTier)
			local scale: number = if shakes[1].args[2] ~= nil then shakes[1].args[2] else 1
			local want = CameraMath.falloff(distance, SLAM.shakeFullRadius, SLAM.shakeRadius)
			expect(scale).toBeCloseTo(want, 1e-3)
			expect(scale).toBeGreaterThan(0)
		end)
	end

	-- The slam's "Wall" is unreliable (D-210): lost, or heard after the daze's Stagger (StateChanged is
	-- reliable), on a link quick enough that the daze comes on the frame the drawn snout gets to the
	-- face. This client's own cast found that face, so the daze is its slam's (D-218): the snout is
	-- still drawn onto it and the slam plays there, once, wherever the launch falls in its frame.
	for _, word in { "lost", "late" } do
		for _, case in { { latency = 0, phase = 0 }, { latency = 0, phase = 0.5 }, { latency = 1 / 120, phase = 0.25 } } do
			it(
				("the daze heard before the slam's word (%s, %.3f s late, launch %.2f into its frame) still draws the snout onto the face and plays the slam once"):format(
					word,
					case.latency,
					case.phase
				),
				function()
					local face = 8
					local stop = face - FRONT
					local events = slam(face)
					local wallWord: any = table.remove(events, 1) :: any
					if word == "late" then
						wallWord.at = events[1].at + 0.2
						table.insert(events, wallWord)
					end
					local run, cues = watched({
						latency = case.latency,
						lag = case.latency,
						stopAt = stop,
						wall = face,
						events = events,
						phase = case.phase,
					})
					local farthest, reachedAt = -math.huge, nil
					for _, frame in run.frames do
						farthest = math.max(farthest, frame.along)
						if reachedAt == nil and frame.along >= stop - EPSILON then
							reachedAt = frame.t
						end
					end
					expect(farthest).toBeLessThanOrEqual(stop + EPSILON)
					expect(reachedAt).never.toBeNil()
					expect((reachedAt :: number) - stop / SPEED).toBeLessThanOrEqual(FRAME + EPSILON)
					expect(#cues).toBe(1)
					expect(cues[1].kind).toBe("Slam")
					expect(cues[1].t).toBeCloseTo(reachedAt :: number, EPSILON)
					expect(((cues[1].point - ORIGIN):Dot(DIRECTION))).toBeCloseTo(face, 1e-2)
					local _starts, _ends, worst = steps(run)
					expect(worst).toBeLessThanOrEqual(FRAME_TRAVEL + EPSILON)
				end
			)
		end
	end

	-- A Stagger mid-rush, short of a face this client's cast found, still holds the body where it is
	-- drawn: only a daze the timeline had brought the snout to the face by is the slam's.
	it("a Stagger heard short of a face this client's cast found holds the body where it is drawn", function()
		local face = 10
		local stop = face - FRONT
		local hold = stop / SPEED - 4 * FRAME
		local run, cues = watched({
			latency = 0,
			lag = 0,
			stopAt = SPEED * hold,
			wall = face,
			events = {
				{
					at = hold,
					name = "StateChanged",
					payload = { entityId = 5, state = "Stagger", duration = 1, direction = "Front" },
				},
			},
		})
		-- On the Stagger's frame it stands where it was drawn on the frame before (not a frame on
		-- toward the face), then slides back onto its root, never near the face.
		local farthest, held, onHalt = -math.huge, nil, nil
		for _, frame in run.frames do
			farthest = math.max(farthest, frame.along)
			if frame.t < hold - EPSILON then
				held = frame.along
			elseif onHalt == nil then
				onHalt = frame.along
			end
		end
		expect(held).never.toBeNil()
		expect(onHalt).never.toBeNil()
		expect(onHalt :: number).toBeLessThanOrEqual((held :: number) + EPSILON)
		expect(farthest).toBeLessThan(stop - 2 * FRAME_TRAVEL)
		expect(#cues).toBe(0)
	end)

	it("the server's sidestep (RushTurned) draws the body on its path, its cue once at the sidestep's end", function()
		local right = Vector3.new(-DIRECTION.Z, 0, DIRECTION.X)
		local flatOrigin = ORIGIN * Vector3.new(1, 0, 1)
		local side = DIRECTION * 3 + right * 0.75
		local back = 3 + side.Magnitude
		local function leg(at: number, from: Vector3, heading: Vector3): any
			return { at = at, from = vec(from), heading = vec(heading), facing = vec(DIRECTION) }
		end
		local legs = {
			leg(0, flatOrigin, DIRECTION),
			leg(3, flatOrigin + DIRECTION * 3, side.Unit),
			leg(back, flatOrigin + DIRECTION * 3 + side, DIRECTION),
		}
		local dust = 0
		local run, cues = watched({
			latency = 0.05,
			lag = 0.25,
			wallSlam = {
				slam = function(): number
					dust += 1
					return 0
				end,
			},
			events = {
				{
					at = 0.02,
					name = "RushTurned",
					payload = {
						entityId = 5,
						launchedAt = LAUNCH,
						serverTime = LAUNCH + 0.02,
						kind = "Clip",
						at = back,
						legs = legs,
						contact = vec(ORIGIN + DIRECTION * 12 + right * 1),
						normal = vec(-DIRECTION),
					},
				},
			},
		})
		-- Beside the line by the sidestep once past it, while the run lasts; no jump on the way.
		local beside = false
		for _, frame in run.frames do
			if frame.t > (back + 2) / SPEED and frame.t < CHARGE.strike and frame.offset then
				local lateral = ((frame.drawn - ORIGIN) * Vector3.new(1, 0, 1)):Dot(right)
				expect(lateral).toBeCloseTo(0.75, 1e-3)
				beside = true
			end
		end
		expect(beside).toBe(true)
		local _, _, worst = steps(run)
		expect(worst).toBeLessThanOrEqual((1 + TUNING.catchUpFraction) * FRAME_TRAVEL + EPSILON)
		expect(#cues).toBe(1)
		expect(cues[1].kind).toBe("Clip")
		-- A corner shouldered past is no slam: no dust, no thud, no shake (D-217).
		expect(dust).toBe(0)
		for _, call in run.calls do
			expect(call.module == "sfx" and call.fn == "cue" and call.args[1] == Fx.wallSlam.cue).toBe(false)
			expect(call.module == "camera" and call.fn == "shake").toBe(false)
		end
	end)

	it("this client's own cast stops the snout on the face before the server's word comes", function()
		-- The server's Wall lost on the way: the drawn body still stops flush, and its cue still plays.
		for _, face in { 8, 10 } do
			local stop = face - FRONT
			local events = slam(face)
			table.remove(events, 1)
			local run, cues = watched({ latency = 0.25, lag = 0.25, stopAt = stop, wall = face, events = events })
			local farthest = -math.huge
			for _, frame in run.frames do
				farthest = math.max(farthest, frame.along)
			end
			expect(farthest).toBeLessThanOrEqual(stop + EPSILON)
			expect(farthest).toBeGreaterThan(stop - EPSILON)
			expect(#cues).toBe(1)
			expect(cues[1].kind).toBe("Slam")
		end
	end)
end)

describe("the legs follow the drawn body while it is drawn away from its root (D-200)", function()
	local THRESHOLD = ChoreoData.locomotion.idleSpeedThreshold
	local WALK = Rigs.Boar.walkSpeed
	local function jam(stop: number): any
		local at = (stop + AI.archetypes.Charger.jamLagStuds) / SPEED + AI.tickSeconds()
		return {
			at = at,
			name = "RushEnded",
			payload = {
				entityId = 5,
				launchedAt = LAUNCH,
				serverTime = LAUNCH + at,
				distance = stop,
				reason = "Jammed",
			},
		}
	end
	local cases: { { name: string, lag: number, options: any } } = {}
	for _, lag in { 0, 0.25, 0.5 } do
		table.insert(cases, { name = "a free rush", lag = lag, options = {} })
		table.insert(
			cases,
			{ name = "a rush into a wall", lag = lag, options = { wall = 8, stopAt = 5.5, events = { jam(5.5) } } }
		)
	end
	table.insert(cases, {
		name = "a Staggered rush",
		lag = 0.25,
		options = {
			stopAt = 8.4,
			events = {
				{ at = 0.3, name = "StateChanged", payload = { entityId = 5, state = "Stagger", duration = 0.6 } } :: any,
				{
					at = 0.3,
					name = "RushEnded",
					payload = {
						entityId = 5,
						launchedAt = LAUNCH,
						serverTime = LAUNCH + 0.3,
						distance = 8.4,
						reason = "Interrupted",
					},
				},
			},
		},
	})
	for _, case in cases do
		it(
			("%s, the root %.2f s late: the walk runs at the drawn body's own speed, still when it is"):format(
				case.name,
				case.lag
			),
			function()
				local options = table.clone(case.options)
				options.latency = case.lag
				options.lag = case.lag
				options.gait = true
				options.frames = 240
				local run = rush(options)
				local drawnFrames, still, moving = 0, 0, 0
				for index = 2, #run.frames do
					local frame, previous = run.frames[index], run.frames[index - 1]
					if frame.offset then
						drawnFrames += 1
						local moved = Vector3.new(frame.drawn.X - previous.drawn.X, 0, frame.drawn.Z - previous.drawn.Z)
						local speed = moved.Magnitude / FRAME
						if speed > THRESHOLD then
							moving += 1
							local paced = math.clamp(speed, ChoreoData.minSpeed * WALK, ChoreoData.maxSpeed * WALK)
							expect(math.abs(frame.gait - paced) <= 1e-2).toBe(true)
							expect(frame.walkTarget).toBeCloseTo(math.min(1, speed / WALK), 1e-3)
						else
							still += 1
							expect(frame.walkTarget).toBe(0)
						end
					end
				end
				expect(drawnFrames > 0).toBe(true)
				expect(moving > 0).toBe(true)
			end
		)
	end
end)

describe("an enemy that does not rush is drawn on its root", function()
	it("the Kobold's Overhead never draws its body away, and no enemy clip carries root motion", function()
		clock = 200
		local kobold = Enemies.byId("KoboldAxeman")
		local model = RigBuilder.build(kobold.skin)
		local root = model.PrimaryPart :: BasePart
		root.CFrame = CFrame.new(0, 3, 0)
		root.Position = root.CFrame.Position
		root.LocalTransparencyModifier = 0
		local record = { id = 7, model = model, kind = "Enemy", defId = kobold.id, rig = kobold.skin, state = "Idle" }
		local calls: { any } = {}
		Replication.bind({
			net = { on = function() end },
			entities = {
				get = function(id: number): any
					return if id == 7 then record else nil
				end,
			},
			localId = function(): number?
				return 1
			end,
			choreo = Choreo,
			clipLibrary = ClipLibrary,
			telegraphs = recorder(calls, "telegraphs"),
			trails = recorder(calls, "trails"),
			smear = recorder(calls, "smear"),
			impact = recorder(calls, "impact"),
			locomotion = recorder(calls, "locomotion"),
			now = function(): number
				return clock
			end,
			serverNow = function(): number
				return clock
			end,
		} :: any)
		local animator = Choreo.get(model)
		local attack = kobold.attacks[1]
		Replication.dispatch("Telegraph", {
			entityId = 7,
			attackId = attack.id,
			kind = attack.telegraph,
			windUp = attack.windUp,
			serverTime = clock,
			origin = { 0, 3, 0 },
			facing = { 0, 0, -1 },
		})
		Replication.dispatch("ActionStarted", {
			entityId = 7,
			clipId = "enemy/" .. kobold.skin .. "/" .. attack.clip,
			serverTime = clock,
			facing = { 0, 0, -1 },
		})
		local clip = ClipLibrary.get("enemy/" .. kobold.skin .. "/" .. attack.clip)
		local rootJoint: any = Joints.map(model).Root
		for _ = 1, 150 do
			clock += FRAME
			animator:step(FRAME)
			expect((animator :: any).bodyOffset).toBe(nil)
			expect(root.LocalTransparencyModifier).toBe(0)
			expect(animator:currentRootMotionDelta().Magnitude).toBe(0)
		end
		expect(Replication.drawnAway(root)).toBe(false)
		-- The Root joint shows the clip's own key, nothing composed onto it.
		local handle = animator.mixer:handles()[1]
		local keyed = ClipSampler.toCFrame(ClipSampler.sample(clip, handle.time).Root)
		expect((rootJoint.Transform.Position - keyed.Position).Magnitude < 1e-4).toBe(true)
		for _, id in ClipLibrary.all() do
			if string.sub(id, 1, 6) == "enemy/" then
				expect(table.find(ClipSampler.jointNames(ClipLibrary.get(id)), ClipSampler.ROOT_KEY)).toBe(nil)
			end
		end
	end)
end)

describe("the launch: the head's burst is the Charge clip's strike snap on the body's frame (D-188, D-189)", function()
	-- Studio at c73cfa8: the drawn head stepped about 1 stud on the first frame after the launch, the
	-- run's own travel 0.47. The head's move is the drawn body's travel plus its pose in the body's
	-- own space (the clip alone). The crouch only creeps; the launch key (0.60 to 0.65 s, ExpoOut,
	-- the strike snap of D-153) lifts the head out of the crouch onto the run, about 2.5 studs of
	-- path. At c73cfa8 a telegraph heard 0.1 to 0.2 s late left the clip a frame ahead of the server
	-- from its mark on (the Mixer's last kept step ran at maxRate while the clip was ahead, D-188):
	-- the snap began a frame before the body moved.
	local CREEP = 0.15 -- the most the crouch's pose moves the head in a frame (measured 0.07)
	local SNAP_SHARE = 0.6 -- D-153 shows 57% of a 3-frame snap in its first frame; the head's path curves
	local SNAP_SECONDS = 0.05 -- the Charge clip's launch key, 0.60 to 0.65
	local HOLD_END = 0.1 -- its hold on the launch pose, to 0.70
	for _, latency in { 0, 0.2 } do
		for _, phase in { 0, 0.25, 0.5, 0.75, 0.9 } do
			it(
				("starts on the frame the body starts running, spread over its frames, then the head runs with the body (latency %.1f s, launch %.2f into its frame)"):format(
					latency,
					phase
				),
				function()
					local run = rush({ latency = latency, lag = 0.25, phase = phase, frames = 70 })
					local frames = run.frames
					local launch: number? = nil
					for index, frame in frames do
						if frame.t > 1e-9 then
							launch = index
							break
						end
					end
					expect(launch).never.toBeNil()
					local first = launch :: number
					local function travel(index: number): number
						return (frames[index].drawn - frames[index - 1].drawn).Magnitude
					end
					local function pose(index: number): number
						return (frames[index].pose - frames[index - 1].pose).Magnitude
					end
					-- The crouch: the body stands, the pose only creeps.
					for index = 2, first - 1 do
						if frames[index].t > -CHARGE.windUp / 2 then
							expect(travel(index) <= EPSILON).toBe(true)
							expect(pose(index) < CREEP).toBe(true)
						end
					end
					-- The launch frame: the body starts down the line and the snap starts with it.
					expect(travel(first) > EPSILON).toBe(true)
					expect(travel(first) <= FRAME_TRAVEL + EPSILON).toBe(true)
					expect(pose(first) > CREEP).toBe(true)
					-- The snap: over the frames its key spans, no frame shows much more than D-153's share.
					local path, most = 0, 0
					local index = first
					while index <= #frames and frames[index - 1].t < SNAP_SECONDS do
						path += pose(index)
						most = math.max(most, pose(index))
						index += 1
					end
					expect(path > 2).toBe(true)
					expect(most <= SNAP_SHARE * path).toBe(true)
					-- The hold: the head runs with the body, one frame of travel a frame.
					for later = index, #frames do
						if frames[later].t > HOLD_END + 1e-9 then
							break
						end
						local head = (frames[later].head - frames[later - 1].head).Magnitude
						expect(math.abs(head - FRAME_TRAVEL) <= 0.02).toBe(true)
					end
				end
			)
		end
	end
end)
