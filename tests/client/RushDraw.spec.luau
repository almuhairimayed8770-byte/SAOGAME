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
Harness.stubService(
	"RunService",
	{ RenderStepped = frameSignal(), Heartbeat = frameSignal(), PreSimulation = frameSignal() }
)

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

	it("draws nothing before the launch, then starts on the root and runs the timeline", function()
		local state = RushDraw.new(line(1))
		expect(RushDraw.step(state, 0.99, FRAME, at(0))).toBe(nil)
		expect(state.phase).toBe("Armed")
		local first = RushDraw.step(state, 1 + FRAME, FRAME, at(0)) :: CFrame
		expect(state.phase).toBe("Run")
		expect((first.Position - at(FRAME_TRAVEL).Position).Magnitude < EPSILON).toBe(true)
		expect(first.LookVector.Z).toBeCloseTo(-1, 1e-9)
		expect(RushDraw.drawing(state)).toBe(true)
		expect(RushDraw.running(state)).toBe(true)
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

-- ---------------------------------------------------------------------------------------------
-- The real path
-- ---------------------------------------------------------------------------------------------

local function recorder(calls: { any }, name: string): any
	return setmetatable({}, {
		__index = function(_self: any, key: string): any
			return function(...: any): any
				table.insert(calls, { module = name, fn = key, args = { ... } })
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
}

type Options = {
	latency: number,
	lag: number,
	telegraph: boolean?, -- default true
	started: boolean?, -- RushStarted arrives (default true)
	stopAt: number?, -- the server's body stops this far down the line
	events: { { at: number, name: string, payload: any } }?, -- seconds after the launch (server)
	hitAt: number?, -- the local blade touches the boar this many seconds after the launch
	frames: number?,
	phase: number?, -- where the launch falls in its frame (0 to 1, default 0)
}

local WIND_UP_START = 10
local LAUNCH = WIND_UP_START + CHARGE.windUp
local ORIGIN = Vector3.new(10, 3, 20)
local DIRECTION = Vector3.new(1, 0, -1).Unit

local function bodyAt(t: number, stopAt: number?): CFrame
	local d = math.clamp(SPEED * (t - LAUNCH), 0, stopAt or LENGTH)
	local position = ORIGIN + DIRECTION * d
	return CFrame.lookAt(position, position + DIRECTION)
end

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

type Run = { frames: { Frame }, front: number, model: Model, root: BasePart, calls: { any } }

local function rush(options: Options): Run
	clock = WIND_UP_START - 0.2 + (options.phase or 0) * FRAME
	local model = RigBuilder.build("Boar")
	local front = EnemyService.bodyExtents(model)
	local root = model.PrimaryPart :: BasePart
	root.LocalTransparencyModifier = 0
	local function place(frame: CFrame)
		root.CFrame = frame
		root.Position = frame.Position -- Lune keeps the two apart; the engine does not
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
		locomotion = recorder(calls, "locomotion"),
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
		positionOf = function(): Vector3
			return Vector3.zero
		end,
		schedule = function() end,
		now = function(): number
			return clock
		end,
		serverNow = function(): number
			return clock
		end,
	} :: any)
	local animator = Choreo.get(model)
	animator:step(FRAME)

	local messages: { { at: number, name: string, payload: any, sent: boolean? } } = {}
	if options.telegraph ~= false then
		table.insert(messages, {
			at = WIND_UP_START + options.latency,
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
			at = WIND_UP_START + options.latency,
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
	for _ = 1, options.frames or 170 do
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
		animator:step(FRAME)
		local offset: CFrame? = (animator :: any).bodyOffset
		local drawn = root.CFrame * (offset or CFrame.identity)
		local solved = solve(model, root.CFrame)
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
		})
	end
	return { frames = frames, front = front, model = model, root = root, calls = calls }
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
						expect(frame.offset).toBe(false)
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
