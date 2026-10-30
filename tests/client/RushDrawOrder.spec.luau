--!strict
--[[
	A Charger's rush drawn in Studio's frame order (PC 1cf87aa M9/306(c) and 307(b)).

	Choreo writes the rig's pose, the rush's body offset in the root joint among it, on
	PreSimulation; physics then moves the replicated root, and the frame is drawn from the moved root
	with the offset written before it moved. Replication.stepRush writes the offset against the root
	as it stood before physics (`rootFrame:Inverse() * drawn`), so the drawn body is carried by the
	root's own move of that frame: one frame of its travel ahead while it runs, a step of up to twice
	the run's travel the frame the late root starts or stops, and the root's whole jump when the
	engine snaps it (a server CFrame write). The PC drew steps of 0.8-1.17 studs a frame (307(b)) and
	a snout 6 studs through a wall for one frame (306(c)).

	The real path, as RushDraw.spec runs it (a RigBuilder Boar posed by a real Choreo animator, the
	remotes through the real Replication), with the replicated root moved after the rig's step
	instead of before it. Without a snap, the order must add nothing to what the drawn body does.
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
local Replication = Harness.load("src/client/controllers/Replication")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local EnemyService = Harness.load("src/server/services/EnemyService")
local Enemies = Harness.load("src/shared/data/enemies")
local AI = Harness.load("src/shared/data/ai")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local Rigs = Harness.load("src/shared/data/rigs")
local FrameClock = Harness.load("src/client/fx/FrameClock")

local FRAME = 1 / 60
local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]
local SPEED: number = AI.rushSpeed(CHARGE)
local LENGTH: number = CHARGE.reach + AI.archetypes.Charger.overshoot
-- One frame of the run's own travel: the most the drawn body may move when its offset starts or ends.
local FRAME_TRAVEL = SPEED * FRAME

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
	-- Studio's frame order: the rig's step (PreSimulation) writes the body offset against the root
	-- as it stands before physics; physics then moves the replicated root, and the frame is drawn
	-- from the moved root with that offset.
	studioOrder: boolean?,
	-- Where the replicated root stands at client time `t` (default: the server's body `lag` late).
	rootAt: ((t: number) -> CFrame)?,
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
		if options.rootAt ~= nil then
			frame = options.rootAt(clock)
		end
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
		-- Studio's order: the root the frame draws is the one physics moved after the step, as
		-- start() binds it (D-438).
		rootAhead = if options.studioOrder then Replication.rootAhead else nil,
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
		if not options.studioOrder then
			place(bodyAt(clock - options.lag, options.stopAt))
		end
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
		if options.studioOrder then
			place(bodyAt(clock - options.lag, options.stopAt))
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

-- Targets down the line, near edge this far from the crouch point (the line's reach is 14).

local WORLD = AI.rushWorld
local RushWorld = Harness.load("src/shared/choreo/RushWorld")
-- The body EnemyService.spawn gives the Charger, the one its slam stop is judged on (D-437).
local BODY = RushWorld.bodyOf(RigBuilder.build("Boar")) :: any

-- Where the server's slam stops the root for a wall square across the line `face` studs down it:
-- RushWorld.contact on that body, its root's box meeting the face.
local function stopFor(face: number): number
	local legs = { { at = 0, from = Vector3.new(ORIGIN.X, 0, ORIGIN.Z), heading = DIRECTION, facing = DIRECTION } }
	local contact = RushWorld.contact(legs, 0, face - BODY.size.Z / 2, -DIRECTION, BODY, ORIGIN.Y, nil)
	return contact.at
end

-- What the server says of a slam into a wall `face` studs down the line (RushDraw.spec's slam).
local function slam(face: number): { any }
	local stop = stopFor(face)
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

-- The farthest the drawn snout reaches past `face` over the run.
local function pastFace(run: Run, face: number): number
	local deepest = -math.huge
	for _, frame in run.frames do
		deepest = math.max(deepest, frame.reach - face)
	end
	return deepest
end

-- The frame the replicated root first moves from rest (its index in run.frames, nil if it never
-- does) and how far it moved on it. Nothing the client holds says when that frame comes: the root
-- carries no velocity before it (D-438).
local function rootStart(run: Run): (number?, number)
	local frames = run.frames
	for index = 2, #frames do
		local move = (frames[index].root - frames[index - 1].root).Magnitude
		if move > 1e-4 then
			return index, move
		end
	end
	return nil, 0
end

-- pastFace over every frame but the one the replicated root first moves on, and on that one.
local function pastFaceAround(run: Run, face: number): (number, number)
	local start = rootStart(run)
	local deepest, onStart = -math.huge, -math.huge
	for index, frame in run.frames do
		if index == start then
			onStart = frame.reach - face
		else
			deepest = math.max(deepest, frame.reach - face)
		end
	end
	return deepest, onStart
end

-- The largest frame-to-frame move of the drawn body over the run but on the frame the replicated
-- root first moves from rest, the move on that frame, and the root's own move on it.
local function studioSteps(run: Run): (number, number, number)
	local first, rootMove = rootStart(run)
	local worst, start = 0, 0
	local frames = run.frames
	for index = 2, #frames do
		local step = (frames[index].drawn - frames[index - 1].drawn).Magnitude
		if index == first then
			start = step
		else
			worst = math.max(worst, step)
		end
	end
	return worst, start, rootMove
end

describe("a drawn rush in Studio's frame order (offset on PreSimulation, root moved by physics)", function()
	for _, lag in { 0.21, 0.5 } do
		for _, phase in { 0, 0.5 } do
			it(
				("moves the drawn body no more than a frame of the run's travel, root %.2f s late, launch %.1f into its frame"):format(
					lag,
					phase
				),
				function()
					local worst, start, rootMove =
						studioSteps(rush({ latency = 0, lag = lag, studioOrder = true, frames = 150, phase = phase }))
					expect(worst).toBeLessThanOrEqual(FRAME_TRAVEL + 0.05)
					-- The frame the late root first moves adds that move alone, once.
					expect(rootMove).toBeLessThanOrEqual(FRAME_TRAVEL + 1e-3)
					expect(start).toBeLessThanOrEqual(FRAME_TRAVEL + rootMove + 0.05)
				end
			)
		end

		it(("draws the snout no deeper into a wall than the plain order does, root %.2f s late"):format(lag), function()
			local face = 12
			local stop = stopFor(face)
			local plain =
				rush({ latency = 0, lag = lag, events = slam(face), stopAt = stop, wall = face, frames = 120 })
			local studio = rush({
				latency = 0,
				lag = lag,
				events = slam(face),
				stopAt = stop,
				wall = face,
				frames = 120,
				studioOrder = true,
			})
			local deepest, onStart = pastFaceAround(studio, face)
			local _, rootMove = rootStart(studio)
			expect(deepest).toBeLessThanOrEqual(pastFace(plain, face) + 0.05)
			-- The frame the late root first moves carries the body by that move alone, once.
			expect(onStart).toBeLessThanOrEqual(pastFace(plain, face) + rootMove + 0.05)
		end)

		it(
			("draws no pose of the run into the wall at the server's slam stop, root %.2f s late (D-437)"):format(lag),
			function()
				for _, face in { 9, 12, 16 } do
					local stop = stopFor(face)
					local plain =
						rush({ latency = 0, lag = lag, events = slam(face), stopAt = stop, wall = face, frames = 150 })
					expect(pastFace(plain, face)).toBeLessThanOrEqual(0.05)
					local studio = rush({
						latency = 0,
						lag = lag,
						events = slam(face),
						stopAt = stop,
						wall = face,
						frames = 150,
						studioOrder = true,
					})
					local deepest, onStart = pastFaceAround(studio, face)
					local _, rootMove = rootStart(studio)
					expect(deepest).toBeLessThanOrEqual(0.05)
					expect(onStart).toBeLessThanOrEqual(0.05 + rootMove)
				end
			end
		)
	end
end)
