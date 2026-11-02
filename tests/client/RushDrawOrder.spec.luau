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

	Every frame is judged on the screen, as the PC's render check found it (AI R1 to R5 on 4b18b5c):
	the pose written before physics, solved at physics on the root part where physics leaves it
	(the BasePart.CFrame the frame shows). A write after physics never shows.
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
local DrawnBody = Harness.load("src/client/choreo/DrawnBody")

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

-- What the frame draws, as the PC's render check found it on 4b18b5c (AI R1 to R5): the pose the
-- rig's step writes before physics, solved at physics on the root part where physics leaves it,
-- so the BasePart.CFrame the screen shows (the screen at row N is frame N-1's pre-physics pose on
-- the root physics left). A Transform or CFrame written after physics (PostSimulation) is gone
-- before the next physics and never shows (R1, R4). `shoot` takes the pose right after the step;
-- `screenOf` solves it on the root part as it then stands. A joint the step turned off whose Part1
-- it anchored draws that part where the step put it, and the parts hanging from it on it.
-- A billboard following the rig (DrawnBody.follow, as Nameplates' plate does) is drawn by the same
-- frame at its Adornee's place as the frame draws it, before that frame's physics (the root part
-- where the last physics left it; a part the step drew itself where the step put it), plus its
-- StudsOffsetWorldSpace as the step left it: `plate`.
type Shot = { transforms: { [string]: CFrame }, held: { [string]: CFrame }, offset: CFrame?, plate: Vector3? }

local function shoot(model: Model, animator: any, plate: BillboardGui?): Shot
	local transforms: { [string]: CFrame } = {}
	local held: { [string]: CFrame } = {}
	for name, joint in Joints.map(model) do
		local motor: any = joint
		transforms[name] = motor.Transform
		local part1 = motor.Part1
		if motor.Enabled == false and part1 ~= nil and part1.Anchored then
			held[name] = part1.CFrame
		end
	end
	local adornee: any = if plate ~= nil then plate.Adornee else nil
	return {
		transforms = transforms,
		held = held,
		offset = animator.bodyOffset,
		plate = if plate ~= nil
				and adornee ~= nil
				and adornee:IsA("BasePart")
			then (adornee.CFrame :: CFrame).Position + plate.StudsOffsetWorldSpace
			else nil,
	}
end

local function screenOf(model: Model, rootFrame: CFrame, shot: Shot): { [string]: CFrame }
	local chain = Pose.chain(model)
	local solved: { [string]: CFrame } = { [chain.rootName] = rootFrame }
	for _, link in chain.links do
		local held = shot.held[link.name]
		solved[link.part1] = if held ~= nil
			then held
			else solved[link.part0] * link.c0 * (shot.transforms[link.name] or CFrame.identity) * link.c1Inverse
	end
	return solved
end

-- The root part the screen hangs the body from: the drawn Part1 of the root joint back through its
-- C1, the Transform the step wrote and its C0. While the joint draws the body that is the root
-- part where physics left it; while the step draws the Torso itself, the root it drew it from.
local function hungFrom(model: Model, solved: { [string]: CFrame }, shot: Shot): CFrame
	local chain = Pose.chain(model)
	for _, link in chain.links do
		if link.part0 == chain.rootName then
			local transform = shot.transforms[link.name] or CFrame.identity
			return solved[link.part1] * link.c1Inverse:Inverse() * transform:Inverse() * link.c0:Inverse()
		end
	end
	return solved[chain.rootName]
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
	-- The Torso on the screen (screenOf: the BasePart.CFrame the frame shows), the Charge clip's
	-- time on the frame (-1 when it does not play) and the frame's length.
	torso: Vector3,
	clipTime: number,
	dt: number,
	-- Where the rig's following billboard is drawn (Shot.plate; nil with no adornee), and whether
	-- the step drew the Torso itself, off the root joint (D-531).
	plate: Vector3?,
	detached: boolean,
}

-- The following billboard's own offset above the root part (a plate's lift).
local PLATE_LIFT = Vector3.new(0, 3.5, 0)

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
	-- Studio's frame order: the rig's step writes the pose against the root as it stands before
	-- physics; physics then moves the replicated root, and the frame shows that pose solved on the
	-- moved root (screenOf).
	studioOrder: boolean?,
	-- Where the replicated root stands at client time `t` (default: the server's body `lag` late).
	rootAt: ((t: number) -> CFrame)?,
	fps: number?, -- the loop's frame rate (default 60)
	-- The share of the server body's velocity the replicated root reports on the loop's frame n
	-- (default all of it). Studio's under-reads the move physics gives the root: (velocity x dt)
	-- minus the PostSimulation-PreSimulation move read -0.12 to -0.43 a row at 60 fps (AH 401(c)).
	velocityScale: ((frame: number) -> number)?,
	-- The length of the loop's frame n (default 1 / fps): a frame time that varies as Studio's does.
	frameTime: ((frame: number) -> number)?,
	-- A replicated root the PC logged, row by row (replaces `lag`, rootAt and velocityScale; see
	-- Replay).
	replay: Replay?,
}

-- The PC's log of a wall run (AI 423 on 4b18b5c, x423): per row its number, its frame length in
-- milliseconds, where physics left the replicated root down the line (PostSimulation) and the
-- velocity it carried down the line at PreSimulation. The loop's frame that hears RushStarted plays
-- row `started` and each later frame the next row; before it the root rests on the crouch point
-- (as every logged row before RushStarted does), and after the last row it stays where that left
-- it. `events` are the server's words, each on the frame that plays its row.
type Replay = {
	started: number,
	rows: { { number } },
	events: { { row: number, name: string, payload: any } },
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
	local frameLength = if options.fps ~= nil then 1 / options.fps else FRAME
	clock = WIND_UP_START - 0.2 + (options.phase or 0) * frameLength
	local model = RigBuilder.build("Boar")
	local front = EnemyService.bodyExtents(model)
	local root = model.PrimaryPart :: BasePart
	root.LocalTransparencyModifier = 0
	local replay = options.replay
	-- The replay's row the loop's frame plays (0 before RushStarted is heard).
	-- The rig's plate: adorned to the root part and following the drawn body, as Nameplates.adorn does.
	local plate = Instance.new("BillboardGui")
	plate.Adornee = root
	DrawnBody.follow(plate, model, PLATE_LIFT)
	local replayRow = 0
	local replayFirst = 0
	if replay ~= nil then
		for index, row in replay.rows do
			if row[1] == replay.started then
				replayFirst = index
			end
		end
	end
	local function place(frame: CFrame)
		if options.rootAt ~= nil then
			frame = options.rootAt(clock)
		end
		if replay ~= nil then
			local rows = replay.rows
			local row = rows[math.min(replayRow, #rows)]
			local along = if replayRow > 0 then row[3] else 0
			local position = ORIGIN + DIRECTION * along
			root.CFrame = CFrame.lookAt(position, position + DIRECTION)
			root.Position = position
			-- The velocity the next row's step reads (its PreSimulation's).
			local next = if replayRow > 0 then rows[replayRow + 1] else rows[replayFirst]
			root.AssemblyLinearVelocity = DIRECTION * (if next ~= nil then next[4] else 0)
			return
		end
		local yaw = options.rootYaw
		local turned = if yaw ~= nil
			then frame * CFrame.Angles(0, math.rad(yaw(clock - options.lag - LAUNCH)), 0)
			else frame
		root.CFrame = turned
		root.Position = frame.Position -- Lune keeps the two apart; the engine does not
		local scale = options.velocityScale
		root.AssemblyLinearVelocity = velocityAt(clock - options.lag, options.stopAt)
			* (if scale ~= nil then scale(frameNow) else 1)
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
	animator:step(frameLength)

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
		if options.frameTime ~= nil then
			frameLength = options.frameTime(frameNow)
		end
		if replay ~= nil and replayRow > 0 then
			replayRow += 1
			local row = replay.rows[replayRow]
			if row ~= nil then
				frameLength = row[2] / 1000
			end
		end
		clock += frameLength
		for _, message in messages do
			if not message.sent and clock >= message.at - 1e-9 then
				message.sent = true
				Replication.dispatch(message.name, message.payload)
				if replay ~= nil and message.name == "RushStarted" then
					replayRow = replayFirst
				end
			end
		end
		if replay ~= nil and replayRow > 0 then
			local number = replay.rows[math.min(replayRow, #replay.rows)][1]
			for _, event in replay.events do
				if event.row == number and replayRow <= #replay.rows then
					Replication.dispatch(event.name, event.payload)
				end
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
			clockStart(frameLength)
		end
		animator:step(frameLength)
		if clockPosed ~= nil then
			clockPosed(frameLength)
		end
		if clockEnd ~= nil then
			clockEnd(frameLength)
		end
		-- The pose the frame draws: what the step wrote, before physics.
		local shot = shoot(model, animator, plate)
		if options.studioOrder then
			place(bodyAt(clock - options.lag, options.stopAt))
		end
		local offset = shot.offset
		local solved = screenOf(model, root.CFrame, shot)
		local drawn = hungFrom(model, solved, shot) * (offset or CFrame.identity)
		local walkTarget, gait = 0, 0
		local charge = false
		local clipTime = -1
		for _, handle in (animator :: any).mixer:handles() do
			if handle.clipId == ChoreoData.rigs.Boar.walk and not handle.stopping then
				walkTarget = handle.targetWeight
				gait = if walkTarget > 0 then handle.speed * Rigs.Boar.walkSpeed else 0
			end
			if handle.clipId == CHARGE_CLIP and not handle.stopping and not handle.done then
				charge = true
				clipTime = handle.time
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
			torso = solved.Torso.Position,
			clipTime = clipTime,
			dt = frameLength,
			plate = shot.plate,
			detached = next(shot.held) ~= nil,
		})
	end
	if options.gait then
		Replication.unwatch(record)
	end
	if options.frameClock then
		FrameClock.bind(nil)
	end
	DrawnBody.unfollow(plate, PLATE_LIFT)
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

-- The first step the drawn rush takes: the drawn body's move on the first frame from the client's
-- launch (the telegraph's predicted launch, else RushStarted heard `latency` late) that moves it;
-- the largest step before it (the body on its root, which moves at most at the server's own speed);
-- and the root's own move on that frame when it is the root's first from rest (what Studio's order
-- adds then, D-438; 0 when the root stood still or was already moving).
local function launchStep(run: Run, launchAt: number): (number, number, number)
	local frames = run.frames
	local before, launch, rootStart = 0, 0, 0
	for index = 2, #frames do
		local frame = frames[index]
		local step = (frame.drawn - frames[index - 1].drawn).Magnitude
		if frame.t < launchAt - 1e-9 then
			before = math.max(before, step)
		elseif step > 1e-6 then
			launch = step
			local rootMove = (frame.root - frames[index - 1].root).Magnitude
			local moving = index > 2 and (frames[index - 1].root - frames[index - 2].root).Magnitude > 1e-6
			rootStart = if moving then 0 else rootMove
			break
		end
	end
	return before, launch, rootStart
end

describe("a rush's first drawn step (D-480)", function()
	-- The launch starts the drawn body where it was last drawn: never from where the root has moved
	-- to since (a root with no lag, or already on its way when RushStarted is heard), which added the
	-- root's own move of the frame to the run's first step (48a846f: 1.87 studs at 30 fps, 0.84 at
	-- 60, 0.35 at 144 with the telegraph; 1.77, 0.89 and 0.37 with RushStarted alone).
	for _, fps in { 30, 60, 144 } do
		local steady = SPEED / fps
		for _, lag in { 0, 0.05, 0.25 } do
			for _, telegraph in { true, false } do
				it(
					("moves no more than a frame of the run's travel at %d fps, root %.2f s late, %s"):format(
						fps,
						lag,
						if telegraph then "telegraphed" else "RushStarted alone"
					),
					function()
						local latency = 0.05
						local launchAt = if telegraph then 0 else latency
						for _, phase in { 0, 0.3, 0.6, 0.9 } do
							local run = rush({
								latency = latency,
								lag = lag,
								telegraph = telegraph,
								fps = fps,
								phase = phase,
								frames = math.ceil((0.4 + CHARGE.windUp) * fps),
								frameClock = true,
							})
							local before, launch = launchStep(run, launchAt)
							expect(before).toBeLessThanOrEqual(steady + 1e-3)
							expect(launch).toBeLessThanOrEqual(steady + 1e-3)
							expect(launch).toBeGreaterThan(0)
						end
					end
				)
			end
		end
	end

	-- In Studio's order the launch adds nothing but the late root's own first move from rest on that
	-- frame, which nothing the client holds before physics moves it foretells (it carries no velocity
	-- yet, D-438; STUDIO_TASKS 347(c) measures it).
	for _, fps in { 30, 60, 144 } do
		local steady = SPEED / fps
		for _, lag in { 0, 0.05, 0.25 } do
			it(
				("adds only the root's first move in Studio's order at %d fps, root %.2f s late"):format(fps, lag),
				function()
					for _, telegraph in { true, false } do
						local latency = 0.05
						for _, phase in { 0, 0.3, 0.6, 0.9 } do
							local run = rush({
								latency = latency,
								lag = lag,
								telegraph = telegraph,
								fps = fps,
								phase = phase,
								frames = math.ceil((0.4 + CHARGE.windUp) * fps),
								frameClock = true,
								studioOrder = true,
							})
							local before, launch, rootStart = launchStep(run, if telegraph then 0 else latency)
							expect(before).toBeLessThanOrEqual(steady + 1e-3)
							expect(rootStart).toBeLessThanOrEqual(steady + 1e-3)
							expect(launch).toBeLessThanOrEqual(steady + rootStart + 1e-3)
						end
					end
				end
			)
		end
	end
end)

-- The largest backward step of the drawn body down the line over the `rows` frames after the
-- replicated root comes to rest (its last move), the slam's settle.
local function backAfterStop(run: Run, rows: number): number
	local frames = run.frames
	local stopped: number? = nil
	for index = #frames, 2, -1 do
		if (frames[index].root - frames[index - 1].root).Magnitude > 1e-4 then
			stopped = index
			break
		end
	end
	local worst = 0
	if stopped ~= nil then
		for index = stopped + 1, math.min(#frames, stopped + rows) do
			worst = math.max(worst, frames[index - 1].along - frames[index].along)
		end
	end
	return worst
end

-- The share of its velocity a late root reports on the loop's frame n, as Studio's under-reads the
-- move physics gives it (AH 401(c): (velocity x dt) minus the PostSimulation-PreSimulation move
-- read -0.12 to -0.43 a row at 60 fps and -0.01 to -0.05 at 144 once the root ran).
local function underRead(fps: number): (frame: number) -> number
	local low, high = if fps < 100 then 0.08 else 0.74, if fps < 100 then 0.74 else 0.95
	return function(frame: number): number
		return low + (high - low) * ((frame * 7) % 10) / 9
	end
end

describe("a drawn rush whose replicated velocity under-reads the root's move (AH 401(c), D-531)", function()
	-- The PC's log on 0582a04: (velocity x dt) minus the PostSimulation-PreSimulation move read
	-- -0.12 to -0.43 a row at 60 fps and -0.01 to -0.05 at 144 once the root ran. Here the root
	-- reports that share of the server body's velocity, row by row, while physics moves it at the
	-- server's pace. The step's offset, written against the root that velocity foretold, carried the
	-- body on the screen by the error (4b18b5c, 60 fps: the snout 0.308 to 0.338 past the face at
	-- lags 0 to 0.25 s, drawn steps of 0.622 to 0.862; D-514's redraw after physics never showed).
	-- The step now draws the Torso itself off the root's move (D-531).
	-- The run's drawn steps, the deepest snout past `face` (nil: none), and whether the body was
	-- back on its root by the end.
	local function measure(run: Run, face: number?): (number, number, boolean)
		local worst = 0
		local frames = run.frames
		for index = 2, #frames do
			worst = math.max(worst, (frames[index].drawn - frames[index - 1].drawn).Magnitude)
		end
		return worst, if face ~= nil then pastFace(run, face) else 0, not frames[#frames].offset
	end

	for _, lag in { 0, 0.1, 0.25 } do
		it(
			("keeps the snout off the wall's face on every row and slides back without a step, root %.2f s late"):format(
				lag
			),
			function()
				for _, fps in { 60, 144 } do
					local face = 12
					local stop = stopFor(face)
					local run = rush({
						latency = 0,
						lag = lag,
						events = slam(face),
						stopAt = stop,
						wall = face,
						frames = 3 * fps,
						fps = fps,
						studioOrder = true,
						velocityScale = underRead(fps),
					})
					local worst, past, home = measure(run, face)
					expect(home).toBe(true)
					expect(past).toBeLessThanOrEqual(0.05)
					expect(backAfterStop(run, 10)).toBeLessThanOrEqual(0.02)
					expect(worst).toBeLessThanOrEqual(SPEED / fps + 0.05)
				end
			end
		)

		it(
			("moves the drawn body no more than a frame of the run's travel on every row, root %.2f s late"):format(lag),
			function()
				for _, fps in { 60, 144 } do
					local run = rush({
						latency = 0,
						lag = lag,
						frames = 3 * fps,
						fps = fps,
						studioOrder = true,
						velocityScale = underRead(fps),
					})
					local worst, _, home = measure(run, nil)
					expect(home).toBe(true)
					-- The root's first move from rest included: nothing the root does carries the body.
					expect(worst).toBeLessThanOrEqual(SPEED / fps + 0.05)
				end
			end
		)
	end

	-- AI 423(b) on 4b18b5c, lag 0.25 s: one row read the snout 1.607 past the face. A row that far
	-- needs the late root to move about 1.6 studs more in one frame than its velocity foretold (the
	-- PC's log: 0 to 1.697 in one row, its velocity read 0). The step's offset, written against the
	-- foretold root, carried the body on the screen by all of it (4b18b5c: 1.938 past at 60 fps,
	-- 1.532 at 144); the Torso drawn off the root's move carries nothing of it (D-531).
	it("keeps the snout off the face when the late root catches up 1.6 studs in one row (AI 423(b))", function()
		local lag, catchUp, face = 0.25, 1.6, 12
		local stop = stopFor(face)
		for _, fps in { 60, 144 } do
			local run = rush({
				latency = 0,
				lag = lag,
				events = slam(face),
				stopAt = stop,
				wall = face,
				frames = 3 * fps,
				fps = fps,
				studioOrder = true,
				velocityScale = underRead(fps),
				-- The server's body `lag` late, caught up by `catchUp` in one frame once it has run
				-- 0.12 s, short of its stop and capped there.
				rootAt = function(t: number): CFrame
					local ran = t - lag - LAUNCH
					local d = math.clamp(SPEED * ran, 0, stop)
					if ran > 0.12 then
						d = math.min(stop, d + catchUp)
					end
					local position = ORIGIN + DIRECTION * d
					return CFrame.lookAt(position, position + DIRECTION)
				end,
			})
			local jump = 0
			for index = 2, #run.frames do
				jump = math.max(jump, (run.frames[index].root - run.frames[index - 1].root).Magnitude)
			end
			expect(jump).toBeGreaterThan(catchUp)
			local worst, past, home = measure(run, face)
			expect(home).toBe(true)
			expect(past).toBeLessThanOrEqual(0.05)
			expect(backAfterStop(run, 10)).toBeLessThanOrEqual(0.02)
			expect(worst).toBeLessThanOrEqual(SPEED / fps + 0.05)
		end
	end)
end)

-- AI 423 on 4b18b5c: the PC's replicated root on four runs into a wall whose face stands 12 down
-- the line (x423: two at 60 fps, root 0 and 0.05 s late; the 0.25 s run with the 1.607 row; one at
-- 144 fps). Each row's PreSimulation root was the last row's PostSimulation one, so only that is
-- kept. The velocity it carried read 0 on many moving rows; the root crept 0.02 to 0.19 a row for
-- about ten rows before it ran at 0.5 to 0.7 a row; at 0.25 s late it went 0 to 1.697 in one row;
-- and it came to rest 0.126 past the told stop at 60 fps (6.295, the server's own rest).
type PcRun = {
	name: string,
	fps: number,
	lag: number,
	started: number,
	wall: number,
	interrupted: number,
	rest: number,
	rows: { { number } },
}
local PC_WALL_RUNS: { PcRun } = {
	{
		name = "W423_60_0",
		fps = 60,
		lag = 0,
		started = 47418,
		wall = 47426,
		interrupted = 47432,
		rest = 6.295,
		rows = {
			{ 47413, 15.707, 0.0, 0 },
			{ 47414, 17.309, 0.0, 0 },
			{ 47415, 16.733, 0.0, 0 },
			{ 47416, 15.944, 0.0, 0 },
			{ 47417, 17.05, 0.0, 0 },
			{ 47418, 17.718, 0.0, 0 },
			{ 47419, 15.805, 0.017, 0 },
			{ 47420, 16.37, 0.04, 0 },
			{ 47421, 17.42, 0.082, 0 },
			{ 47422, 15.755, 0.124, 0 },
			{ 47423, 17.386, 0.197, 0 },
			{ 47424, 16.697, 0.267, 0 },
			{ 47425, 16.146, 0.351, 0 },
			{ 47426, 16.635, 0.431, 0 },
			{ 47427, 17.099, 0.517, 0 },
			{ 47428, 15.96, 0.589, 0 },
			{ 47429, 16.842, 0.65, 0 },
			{ 47430, 17.554, 0.688, 0 },
			{ 47431, 15.961, 0.724, 0 },
			{ 47432, 16.796, 1.049, 0.649 },
			{ 47433, 17.268, 1.634, 0 },
			{ 47434, 15.556, 2.234, 18.066 },
			{ 47435, 16.97, 2.754, 26.162 },
			{ 47436, 17.545, 3.261, 28 },
			{ 47437, 15.464, 3.696, 28 },
			{ 47438, 17.358, 4.213, 28 },
			{ 47439, 17.294, 4.701, 28 },
			{ 47440, 15.468, 5.134, 28 },
			{ 47441, 16.844, 5.622, 26.823 },
			{ 47442, 17.062, 6.017, 19.034 },
			{ 47443, 16.279, 6.253, 8.922 },
			{ 47444, 17.533, 6.295, 1.476 },
			{ 47445, 16.339, 6.295, 0 },
			{ 47446, 16.292, 6.295, 0 },
			{ 47447, 17.054, 6.295, 0 },
			{ 47448, 16.699, 6.295, 0 },
			{ 47449, 17.036, 6.295, 0 },
			{ 47450, 16.196, 6.295, 0 },
			{ 47451, 16.55, 6.295, 0 },
			{ 47452, 16.014, 6.295, 0 },
			{ 47453, 17.272, 6.295, 0 },
			{ 47454, 16.637, 6.295, 0 },
		},
	},
	{
		name = "W423_60_05",
		fps = 60,
		lag = 0.05,
		started = 47953,
		wall = 47960,
		interrupted = 47966,
		rest = 6.169,
		rows = {
			{ 47948, 15.873, 0.0, 0 },
			{ 47949, 16.649, 0.0, 0 },
			{ 47950, 17.137, 0.0, 0 },
			{ 47951, 17.039, 0.0, 0 },
			{ 47952, 15.886, 0.0, 0 },
			{ 47953, 17.372, 0.0, 0 },
			{ 47954, 16.597, 0.0, 0 },
			{ 47955, 16.092, 0.0, 0 },
			{ 47956, 16.962, 0.025, 0 },
			{ 47957, 17, 0.055, 0 },
			{ 47958, 17.306, 0.104, 0 },
			{ 47959, 15.971, 0.162, 0 },
			{ 47960, 16.663, 0.252, 0 },
			{ 47961, 17.005, 0.37, 0 },
			{ 47962, 16.161, 0.495, 0 },
			{ 47963, 16.142, 0.644, 0 },
			{ 47964, 16.89, 0.797, 0 },
			{ 47965, 17.143, 0.983, 0 },
			{ 47966, 16.664, 1.143, 0 },
			{ 47967, 16.822, 1.291, 0 },
			{ 47968, 16.164, 1.427, 0 },
			{ 47969, 17.277, 1.542, 0 },
			{ 47970, 15.804, 1.607, 0 },
			{ 47971, 17.007, 1.638, 0 },
			{ 47972, 17.657, 1.911, 0.231 },
			{ 47973, 15.2, 2.481, 6.038 },
			{ 47974, 17.397, 3.192, 16.743 },
			{ 47975, 16.485, 3.715, 26.448 },
			{ 47976, 16.203, 4.215, 28 },
			{ 47977, 17.389, 4.76, 28 },
			{ 47978, 16.089, 5.244, 28 },
			{ 47979, 17.221, 5.749, 28 },
			{ 47980, 15.835, 6.125, 28 },
			{ 47981, 16.637, 6.289, 24.88 },
			{ 47982, 16.787, 6.312, 15.238 },
			{ 47983, 16.79, 6.295, 5.821 },
			{ 47984, 17.028, 6.295, 0.099 },
			{ 47985, 16.238, 6.295, 0 },
			{ 47986, 16.928, 6.295, 0 },
			{ 47987, 16.929, 6.295, 0 },
			{ 47988, 17.07, 6.295, 0 },
			{ 47989, 16.759, 6.295, 0 },
			{ 47990, 16.097, 6.295, 0 },
			{ 47991, 16.443, 6.295, 0 },
			{ 47992, 16.838, 6.295, 0 },
			{ 47993, 17.038, 6.295, 0 },
		},
	},
	{
		name = "W423_60_25",
		fps = 60,
		lag = 0.25,
		started = 49033,
		wall = 49041,
		interrupted = 49047,
		rest = 6.295,
		rows = {
			{ 49028, 16.775, 0.0, 0 },
			{ 49029, 16.901, 0.0, 0 },
			{ 49030, 16.381, 0.0, 0 },
			{ 49031, 16.432, 0.0, 0 },
			{ 49032, 17.212, 0.0, 0 },
			{ 49033, 15.992, 0.0, 0 },
			{ 49034, 17.143, 0.0, 0 },
			{ 49035, 16.757, 0.0, 0 },
			{ 49036, 16.051, 1.697, 0 },
			{ 49037, 17.383, 2.277, 28 },
			{ 49038, 16.525, 2.935, 28 },
			{ 49039, 16.157, 3.425, 28 },
			{ 49040, 17.276, 3.603, 28 },
			{ 49041, 16.67, 4.178, 28 },
			{ 49042, 15.914, 4.731, 28 },
			{ 49043, 17.367, 5.227, 28 },
			{ 49044, 16.941, 5.69, 28 },
			{ 49045, 16.238, 5.98, 26.046 },
			{ 49046, 16.366, 6.17, 19.704 },
			{ 49047, 17.387, 6.267, 11.039 },
			{ 49048, 16.662, 6.295, 0 },
			{ 49049, 16.512, 6.295, 0.009 },
			{ 49050, 16.526, 6.295, 0 },
			{ 49051, 15.853, 6.295, 0 },
			{ 49052, 17.31, 6.295, 0 },
			{ 49053, 16.955, 6.295, 0 },
			{ 49054, 15.649, 6.295, 0 },
			{ 49055, 18.734, 6.295, 0 },
			{ 49056, 15.697, 6.295, 0 },
			{ 49057, 16.158, 6.295, 0 },
			{ 49058, 17.8, 6.295, 0 },
		},
	},
	{
		name = "W423_144_0",
		fps = 144,
		lag = 0,
		started = 56507,
		wall = 56522,
		interrupted = 56539,
		rest = 6.169,
		rows = {
			{ 56502, 7.738, 0.0, 0 },
			{ 56503, 6.931, 0.0, 0 },
			{ 56504, 7.252, 0.0, 0 },
			{ 56505, 6.366, 0.0, 0 },
			{ 56506, 6.515, 0.0, 0 },
			{ 56507, 8.004, 0.0, 0 },
			{ 56508, 6.262, 0.0, 0 },
			{ 56509, 7.181, 0.0, 0 },
			{ 56510, 6.971, 0.0, 0 },
			{ 56511, 6.371, 0.0, 0 },
			{ 56512, 7.548, 0.0, 0 },
			{ 56513, 6.59, 0.017, 0 },
			{ 56514, 7.228, 0.017, 0 },
			{ 56515, 6.359, 0.028, 0 },
			{ 56516, 7.601, 0.028, 0 },
			{ 56517, 7.171, 0.04, 0 },
			{ 56518, 6.522, 0.041, 0 },
			{ 56519, 6.525, 0.041, 0 },
			{ 56520, 7.733, 0.067, 0 },
			{ 56521, 6.306, 0.069, 0 },
			{ 56522, 7.068, 0.078, 0 },
			{ 56523, 7.682, 0.1, 0 },
			{ 56524, 6.002, 0.115, 0 },
			{ 56525, 7.205, 0.138, 0 },
			{ 56526, 6.939, 0.163, 0 },
			{ 56527, 7.141, 0.191, 0 },
			{ 56528, 6.515, 0.221, 0 },
			{ 56529, 7.086, 0.253, 0 },
			{ 56530, 7.345, 0.296, 0 },
			{ 56531, 6.547, 0.332, 0 },
			{ 56532, 7.59, 0.368, 0 },
			{ 56533, 6.716, 0.411, 0 },
			{ 56534, 6.844, 0.453, 0 },
			{ 56535, 7.164, 0.493, 0 },
			{ 56536, 8.291, 0.531, 0 },
			{ 56537, 5.566, 0.566, 0 },
			{ 56538, 6.295, 0.594, 0 },
			{ 56539, 6.636, 0.622, 0 },
			{ 56540, 7.253, 0.647, 28 },
			{ 56541, 7.363, 0.67, 0 },
			{ 56542, 6.605, 0.684, 0 },
			{ 56543, 7.692, 0.694, 0 },
			{ 56544, 6.056, 0.701, 0 },
			{ 56545, 7.146, 0.767, 0.136 },
			{ 56546, 6.993, 0.912, 1.593 },
			{ 56547, 7.244, 1.113, 4.659 },
			{ 56548, 6.631, 1.353, 8.726 },
			{ 56549, 7.14, 1.617, 13.292 },
			{ 56550, 7.219, 1.889, 17.888 },
			{ 56551, 6.455, 2.155, 22.068 },
			{ 56552, 7.339, 2.429, 25.408 },
			{ 56553, 7.102, 2.662, 27.648 },
			{ 56554, 6.891, 2.882, 28 },
			{ 56555, 6.263, 3.071, 28 },
			{ 56556, 6.881, 3.285, 28 },
			{ 56557, 7.62, 3.525, 28 },
			{ 56558, 6.534, 3.706, 28 },
			{ 56559, 7.72, 3.931, 28 },
			{ 56560, 6.131, 4.108, 28 },
			{ 56561, 7.184, 4.312, 28 },
			{ 56562, 6.898, 4.515, 28 },
			{ 56563, 7.026, 4.727, 28 },
			{ 56564, 7.598, 4.987, 27.34 },
			{ 56565, 6.156, 5.189, 24.74 },
			{ 56566, 6.98, 5.42, 21.813 },
			{ 56567, 6.552, 5.638, 17.757 },
			{ 56568, 7.546, 5.833, 13.376 },
			{ 56569, 7.276, 5.995, 9.062 },
			{ 56570, 6.135, 6.102, 5.201 },
			{ 56571, 7.72, 6.185, 2.535 },
			{ 56572, 7.279, 6.199, 0.355 },
			{ 56573, 5.66, 6.199, 0 },
			{ 56574, 7.092, 6.199, 0 },
			{ 56575, 7.085, 6.199, 0 },
			{ 56576, 6.874, 6.199, 0 },
			{ 56577, 6.553, 6.199, 0 },
			{ 56578, 7.08, 6.199, 0 },
			{ 56579, 7.075, 6.199, 0 },
			{ 56580, 7.655, 6.199, 0 },
			{ 56581, 6.43, 6.199, 0 },
			{ 56582, 7.116, 6.199, 0 },
		},
	},
}

-- The server's words on a PC run, each on its logged row: the wall it told on its first RushEnded
-- (stop 6.169, the slam stop of a face 12 down the line), the daze and the rush's end where it
-- rested.
local function replayOf(take: PcRun, face: number): Replay
	local function at(row: number): number
		return LAUNCH + (row - take.started) / take.fps
	end
	return {
		started = take.started,
		rows = take.rows,
		events = {
			{
				row = take.wall,
				name = "RushEnded",
				payload = {
					entityId = 5,
					launchedAt = LAUNCH,
					serverTime = at(take.wall),
					distance = stopFor(face),
					reason = "Wall",
					contact = vec(ORIGIN + DIRECTION * face),
					normal = vec(-DIRECTION),
				},
			},
			{
				row = take.interrupted,
				name = "StateChanged",
				payload = { entityId = 5, state = "Stagger", duration = WORLD.slamDazeSeconds, direction = "Front" },
			},
			{
				row = take.interrupted,
				name = "RushEnded",
				payload = {
					entityId = 5,
					launchedAt = LAUNCH,
					serverTime = at(take.interrupted),
					distance = take.rest,
					reason = "Interrupted",
				},
			},
		},
	}
end

-- A PC run through the real path: the crouch, then the rows from RushStarted to rest, then 0.8 s
-- on the resting root.
local function runPc(take: PcRun, face: number): Run
	local after = 0
	for _, row in take.rows do
		if row[1] > take.started then
			after += 1
		end
	end
	return rush({
		latency = take.lag,
		lag = take.lag,
		wall = face,
		stopAt = stopFor(face),
		fps = take.fps,
		frames = math.ceil((0.2 + CHARGE.windUp + take.lag) * take.fps) + 2 + after + math.ceil(0.8 * take.fps),
		studioOrder = true,
		replay = replayOf(take, face),
	})
end

describe("the PC's wall runs drawn on the screen (AI 423, x423 on 4b18b5c)", function()
	it("are runs into the face the slam stop 6.169 is told for", function()
		expect(stopFor(12)).toBeCloseTo(6.169, 3)
	end)

	for _, take in PC_WALL_RUNS do
		it(
			("keeps the snout off the face on every row and steps no more than the run's travel, %s"):format(take.name),
			function()
				local face = 12
				local run = runPc(take, face)
				local frames = run.frames
				-- The deepest snout past the face beyond what the root's own place puts there (the
				-- root rests 0.126 past the told stop at 60 fps, 0.030 at 144: the server's rest,
				-- where the body goes back on its root), and the largest drawn step over the run's
				-- travel in the row. 4b18b5c: 0.381, 0.406, 1.628 and 0.036 past (the PC's BasePart
				-- read 0.372, 0.367, 1.607 and 0.027), on 3, 5, 2 and 0 rows over 0.05 (the PC's 3,
				-- 7, 2 and 0), and a step 1.248 over the run's travel at 0.25 s late.
				local stop = stopFor(face)
				local past, worst = -math.huge, -math.huge
				for index, frame in frames do
					local rootPast = math.max(0, (frame.root - ORIGIN):Dot(DIRECTION) - stop)
					past = math.max(past, frame.reach - face - rootPast)
					if index > 1 then
						local step = (frame.drawn - frames[index - 1].drawn).Magnitude
						worst = math.max(worst, step - SPEED * frame.dt)
					end
				end
				expect(not frames[#frames].offset).toBe(true)
				expect(past).toBeLessThanOrEqual(0.05)
				expect(worst).toBeLessThanOrEqual(0.05)
			end
		)

		it(
			("draws the plate over the drawn body on every row the Torso is drawn off its root, %s (D-533)"):format(
				take.name
			),
			function()
				local run = runPc(take, 12)
				local rows, off = 0, 0
				for _, frame in run.frames do
					if frame.detached then
						rows += 1
						expect(frame.plate).never.toBeNil()
						off = math.max(off, ((frame.plate :: Vector3) - (frame.drawn + PLATE_LIFT)).Magnitude)
					end
				end
				-- 4b18b5c-on-E2b: the plate rode the root part, drawn where the last physics left it with
				-- the way to the body taken from the root the step drew from, so it trailed the body by
				-- the root's foretold move (its velocity x dt): 0.491, 0.487, 0.487 and 0.216 off.
				expect(rows).toBeGreaterThan(20)
				expect(off).toBeLessThanOrEqual(1e-3)
			end
		)
	end
end)

-- The Charge clip's launch: the strike snap ClipAudit judges no pop in (ReviewMarkers.strikeSnaps,
-- section 10 beat 2: "the fastest motion in the game"), and the Torso's place in its root part's
-- frame at a clip time from the clip alone (the Root joint's C0 * key * C1^-1 on a built rig).
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers")
local CHARGE_DEF = ClipLibrary.get(CHARGE_CLIP)
local LAUNCH_SNAP = ReviewMarkers.strikeSnaps(CHARGE_DEF)[1]
local ROOT_JOINT_C0, ROOT_JOINT_C1 = Joints.frames(Joints.map(RigBuilder.build("Boar")).Root)

local function torsoInRoot(clipTime: number): Vector3
	local key = ClipSampler.sample(CHARGE_DEF, clipTime).Root
	local keyed = if key ~= nil then ClipSampler.toCFrame(key) else CFrame.identity
	return (ROOT_JOINT_C0 * keyed * ROOT_JOINT_C1:Inverse()).Position
end

-- True for a frame whose Charge clip time crosses the launch snap (its step draws part of it).
local function inLaunchSnap(before: Frame, frame: Frame): boolean
	return before.clipTime >= 0
		and before.clipTime < LAUNCH_SNAP.finish - 1e-6
		and frame.clipTime > LAUNCH_SNAP.start + 1e-6
end

describe("the boar's Torso over a drawn rush (AI 422(a), D-530)", function()
	-- The PC on 4b18b5c: the Torso stepped 0.74 to 0.85 on 2 rows a rush at 60 fps, the drawn root
	-- 0.44 to 0.50 on them. The Torso is drawn at the drawn root times the Charge clip's Root key, so
	-- on the launch's rows it moves by the run's travel and by the clip's own spring off the
	-- haunches, which a bar of 0.6 a row did not count. On the screen (4b18b5c in Lune, 60 fps):
	-- the launch row 1.067 at lag 0 (drawn 0.689: the root's error on it) and other rows 0.585 to
	-- 0.862 (each the root's error); with the Torso drawn off the root's move (D-531) the launch
	-- rows 0.737 to 0.853 (drawn 0.466, the clip 0.308 to 0.431) and every other row at most 0.484.
	it(
		"springs off its haunches inside the launch snap: 0.771 studs in 0.05 s, about half of it in the first frame",
		function()
			expect(LAUNCH_SNAP.start).toBeCloseTo(CHARGE.windUp, 4)
			expect(LAUNCH_SNAP.finish - LAUNCH_SNAP.start).toBeCloseTo(0.05, 4)
			local from, to = torsoInRoot(LAUNCH_SNAP.start), torsoInRoot(LAUNCH_SNAP.finish)
			-- Forward (-Z) 0.62 and up 0.458: out of the coil rocked back over the haunches.
			expect((to - from).Magnitude).toBeCloseTo(0.771, 3)
			expect(to.Z - from.Z).toBeLessThan(-0.6)
			-- D-153's snap ease: 57, 29 and 14 % of it a 60 fps frame.
			local first = (torsoInRoot(LAUNCH_SNAP.start + 1 / 60) - from).Magnitude
			expect(first).toBeGreaterThan(0.43)
			expect(first).toBeLessThan(0.45)
			-- Through the run, the clip moves the Torso at most 0.12 a 60 fps frame in its root's frame.
			local gallop = 0
			local t = LAUNCH_SNAP.finish
			while t < 1.67 do
				gallop = math.max(gallop, (torsoInRoot(t + 1 / 60) - torsoInRoot(t)).Magnitude)
				t += 1 / 60
			end
			expect(gallop).toBeLessThanOrEqual(0.12)
		end
	)

	-- Studio's frame lengths at 60 fps (15.5 to 17.5 ms rows), a 144 Hz frame steadier.
	local swing = { -1.2, 0.8, -0.4, 1.0, -0.9, 0.6, 0, -0.7, 0.9 }
	for _, fps in { 60, 144 } do
		for _, lag in { 0, 0.05, 0.1, 0.25 } do
			it(
				("steps no more than the drawn root plus the clip's spring on the snap's rows, %d fps, root %.2f s late"):format(
					fps,
					lag
				),
				function()
					local face = 12
					local stop = stopFor(face)
					for _, phase in { 0, 0.5 } do
						for _, wall in { false, true } do
							local run = rush({
								latency = 0,
								lag = lag,
								phase = phase,
								events = if wall then slam(face) else nil,
								stopAt = if wall then stop else nil,
								wall = if wall then face else nil,
								frames = math.ceil(2.6 * fps),
								fps = fps,
								studioOrder = true,
								velocityScale = underRead(fps),
								frameTime = function(frame: number): number
									return (1 / fps) * (1 + swing[frame % #swing + 1] * fps / 60000)
								end,
							})
							local snapRows = 0
							local frames = run.frames
							for index = 2, #frames do
								local frame, before = frames[index], frames[index - 1]
								local torso = (frame.torso - before.torso).Magnitude
								local drawn = (frame.drawn - before.drawn).Magnitude
								if inLaunchSnap(before, frame) then
									snapRows += 1
									-- The run's travel plus the clip's spring (Lune: up to 0.386 over the
									-- drawn root at 60 fps, 0.179 at 144).
									expect(torso).toBeLessThanOrEqual(drawn + 0.42)
								elseif before.clipTime >= LAUNCH_SNAP.finish - 1e-6 then
									-- The run, the skid and the slam: its travel plus the clip's own gallop
									-- (Lune 0.030 in the open, 0.109 at the slam's daze; 0.046 at 144).
									expect(torso).toBeLessThanOrEqual(drawn + 0.12)
								else
									-- The crouch: the clip's own stamp and coil on a body standing still
									-- (Lune up to 0.173 at 60 fps, 0.108 at 144).
									expect(torso).toBeLessThanOrEqual(drawn + 0.2)
								end
								if fps < 100 and not inLaunchSnap(before, frame) then
									-- 399(a)'s bar holds on every row but the snap's (Lune 0.510).
									expect(torso).toBeLessThanOrEqual(0.6)
								end
							end
							-- The snap is 0.05 s of rows: 3 or 4 at 60 fps, 7 to 9 at 144.
							expect(snapRows).toBeGreaterThanOrEqual(math.floor(0.05 * fps))
							expect(snapRows).toBeLessThanOrEqual(math.ceil(0.05 * fps) + 1)
						end
					end
				end
			)
		end
	end
end)
