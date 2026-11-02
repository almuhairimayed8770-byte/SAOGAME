--!strict
--[[
	The Frenzy Boar's rests, holds and walls under DevCombat's Studio test hooks (D-333), after the
	1cf87aa PC run (M9/306(c), G4, 311(a), the FB hand-back). The DevCombat Script is loaded the way
	Studio runs it over DevEnemyHooks.spec's fake engine (velocity bodies on a 240 Hz physics step,
	walls as planes the root's box is pushed out of and the server's Blockcast sees, Model:PivotTo),
	plus `land`: a body carried onto a point by its own velocity over a given time and stopped dead
	there, the way a server-owned body moves without a CFrame write (which every client would show as
	a teleport of its replicated root). The last cases (AI 423(c), 422(d), 440, 441) swap in the
	Humanoid the PC's server logs show (`humanoid`: "studio", fitted to the 4b18b5c log, and
	"tolerant", fitted to the PC's P2 probe of a real server Humanoid on 4e60f11) and Studio's 60 and
	144 Hz server frames, jittered.
]]
Harness.stubService("CollectionService", {
	AddTag = function(_self, instance, tag)
		instance:AddTag(tag)
	end,
	RemoveTag = function(_self, instance, tag)
		instance:RemoveTag(tag)
	end,
	HasTag = function(_self, instance, tag)
		return instance:HasTag(tag)
	end,
})
Harness.stubService("RunService", {
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
})

local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local EntityService = Harness.load("src/server/services/EntityService")
local CombatService = Harness.load("src/server/services/CombatService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local AI = Harness.load("src/shared/data/ai")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Rigs = Harness.load("src/shared/data/rigs")
local WorldData = Harness.load("src/shared/data/world")
local Playground = Harness.load("src/shared/data/playground")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

local FILE = "src/server/dev/DevCombat.server.luau"
local HOOKS = Dev.hooks
local BOAR = Enemies.byId("FrenzyBoar")
local BOAR_HEIGHT = (function(): number
	local rig = Rigs.Boar
	return rig.hipHeight + rig.parts[rig.rootPart].size[2] / 2 + WorldData.spawn.groundEpsilon
end)()

-- ------------------------------------------------------------------------------------------
-- The fake engine (WallStop.spec's, plus pivot)
-- ------------------------------------------------------------------------------------------

local PHYSICS_STEP = 1 / 240
local FLOOR_GAP = 1e-9
local ACCELERATION = 560

-- The Humanoid the fake engine plays and the server's frames (AI 423(c), 422(d)). "ideal" is this
-- file's own: it walks onto its MoveTo goal and stops on it, and a landing ends exactly on its point.
-- "studio" is the one the PC's server log on 4b18b5c shows (item 420 column 4; Studio, 60 fps):
--   - it settles its walk once a frame, at the frame's start: it walks the whole frame at WalkSpeed
--     toward its MoveTo goal, past the goal when that is nearer than a frame's walk (the slam ran
--     0.467 a row through a goal 0.341 away: 5.828 → 6.295 against the told 6.169);
--   - it holds a goal nearer than `arriveFrames` frames of its walk as reached and brakes, also at
--     rest (the open run braked 0.772 short of the line end, 28 → 4.93 → 0.10 studs/s, rested at
--     21.467 and stayed there with MoveTo re-sent; the slam ran on 0.808 short: 1.65–1.73 frames);
--     `brake` per 1/240 s step brakes 28 studs/s to rest in 0.239, as the PC's rows did;
--   - a velocity written on its root (engine.land, engine.halt) carries the body through the frame it
--     is written on (the slam's land at 0.341 short ran the frame at 28.00);
--   - it reaches its walk speed at `acceleration` (1320: the PC's rows sit 0.239 behind a body at
--     full speed from the launch row, 3.028 at +0.116 s, 21.228 at +0.766 s).
-- What lies behind the arrival rule is not visible from the log; `arriveFrames` 0 is a Humanoid that
-- never brakes short (it only ever runs on past its goal).
-- "tolerant" is the one the PC's P2 probe measured (a real server FrenzyBoar on open floor, AI held
-- off, 4e60f11; rc/g4/PC-P2-humanoid-near-goal.md), which also plays the 4b18b5c rows above and the
-- 9063a60 landing's rows (AJ 440, 441):
--   - each 1/240 s step its velocity closes `gain` of the way to its target, by at most `cap` × step
--     (the ramp from rest: 0.240, 0.455, 0.466 at WalkSpeed 28, 0.179, 0.232 at 14, 0.114, 0.133 at
--     8; the partial rows after its walk stops: 0.226 + 0.012 at 28, 0.054 at 14, 0.020 at 8, 0.005
--     at 2; the open run's 28 → 4.93 → 0.10); a velocity written on its root is where it starts from;
--   - it settles its walk at the frame's start: WalkSpeed toward its MoveTo goal, the way fixed for
--     the frame, or nothing (target 0);
--   - a MoveTo given to it while it stands (or has arrived) never starts it toward a goal within
--     `startStuds` (no move at all for 30 rows at any WalkSpeed), and a walk it starts so stops
--     once one more frame and its brake would bring it within `startStuds` of the goal (0.933 to
--     1.4 short);
--   - a MoveTo given to it while it walks (a re-issue, the slam's stop, a landing) keeps it walking:
--     it walks that frame and arrives at a frame's end within `runFrames` frames of its walk (the
--     4b18b5c rows: 0.772 braked, 0.808 ran on; the slam's land 0.341 short ran the frame through
--     its goal, 0.126 past).
-- So a landing paced onto a goal inside `startStuds` (D-525) walks one frame and then only drifts on
-- the velocity written on it each frame, braked within the frame: the PC's 9063a60 landings rested
-- 0.06 to 0.14 short at 60 fps once landMaxSeconds ran out, and passed at 144 fps.
-- `fps` and `jitter` set the server frames: each lasts 1/fps × (1 + u), u uniform in [-jitter, jitter].
local humanoid = {
	mode = "ideal",
	arriveFrames = 1.7,
	brake = 0.672,
	acceleration = 1320,
	gain = 0.623,
	cap = 1384,
	startStuds = 0.9335,
	runFrames = 1.7,
	fps = 60,
	jitter = 0,
	random = Random.new(11),
}

type Plane = { point: Vector3, out: Vector3 }

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

type Body = {
	position: Vector3,
	velocity: Vector3,
	goal: Vector3?,
	walkSpeed: number,
	offsets: { [BasePart]: CFrame },
	physT: number,
	landing: { to: Vector3, untilT: number }?,
	-- A velocity written on the root since the last frame's physics (land, halt): the studio
	-- Humanoid keeps it through the next frame.
	written: boolean?,
	-- The tolerant Humanoid: a MoveTo given since its last frame, whether it walks toward its goal,
	-- and how that walk arrives ("start": begun standing, "run": given while walking).
	called: boolean?,
	walking: boolean?,
	band: string?,
}

local clock = { t = 1000 }
local sent: { { time: number, remote: string, payload: any } } = {}
-- Every AntiCheatService call the hooks make (the enemy hooks move no player: none, D-143).
local antiCheatCalls: { string } = {}
local bodies: { [Model]: Body } = {}
local walls: { Plane } = {}
-- Walls the studio Humanoid's body meets and the server's cast never sees (an obstacle it misses).
local hiddenWalls: { Plane } = {}
local delayed: { { at: number, fn: () -> () } } = {}
local devWorkspace: any = nil
local invokeDev: (command: string, args: any) -> any = nil :: any

local function record(remote: string, payload: any)
	local ok, problem = Net.validate(remote, payload)
	assert(ok, ("%s payload fails the schema: %s"):format(remote, tostring(problem)))
	table.insert(sent, { time = clock.t, remote = remote, payload = payload })
end

local function sentOf(remote: string, entityId: number): { { time: number, remote: string, payload: any } }
	local list = {}
	for _, entry in sent do
		if entry.remote == remote and entry.payload.entityId == entityId then
			table.insert(list, entry)
		end
	end
	return list
end

local function support(frame: CFrame, half: Vector3, axis: Vector3): number
	return math.abs(frame.RightVector:Dot(axis)) * half.X
		+ math.abs(frame.UpVector:Dot(axis)) * half.Y
		+ math.abs(frame.LookVector:Dot(axis)) * half.Z
end

local function blockcast(start: CFrame, size: Vector3, vector: Vector3): (number?, Vector3?)
	local length = vector.Magnitude
	if length < FLOOR_GAP then
		return nil, nil
	end
	local direction = vector / length
	local best: number?, normal: Vector3? = nil, nil
	for _, wall in walls do
		local gap = (start.Position - wall.point):Dot(wall.out) - support(start, size / 2, wall.out)
		local rate = -direction:Dot(wall.out)
		if gap >= -FLOOR_GAP and rate > FLOOR_GAP then
			local at = math.max(0, gap) / rate
			if at <= length and (best == nil or at < best) then
				best, normal = at, wall.out
			end
		end
	end
	return best, normal
end

local function yawOf(model: Model): Vector3
	local align = EnemyService.alignOf(model)
	local look = if align ~= nil then align.CFrame.LookVector else (model.PrimaryPart :: BasePart).CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function placeParts(model: Model, body: Body)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.lookAt(body.position, body.position + yawOf(model))
	for part, offset in body.offsets do
		part.CFrame = root.CFrame * offset
	end
end

-- The boar's body as part corners in its root's space (never its blockers: D-198).
local function cornersOf(rig: Model): { Vector3 }
	local corners: { Vector3 } = {}
	local root = rig.PrimaryPart :: BasePart
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") and not CollisionGroups.isBlocker(part) then
			local half = part.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						table.insert(corners, root.CFrame:PointToObjectSpace(corner))
					end
				end
			end
		end
	end
	return corners
end

local CORNERS = cornersOf(RigBuilder.build("Boar"))

local function depthInWalls(model: Model): number
	local body = bodies[model]
	local frame = CFrame.lookAt(body.position, body.position + yawOf(model))
	local deepest = 0
	for _, wall in walls do
		for _, corner in CORNERS do
			deepest = math.max(deepest, -(frame:PointToWorldSpace(corner) - wall.point):Dot(wall.out))
		end
	end
	return deepest
end

local engine = {
	place = function(model: Model, cframe: CFrame)
		local root = model.PrimaryPart :: BasePart
		root.CFrame = CFrame.new()
		local offsets = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= root then
				offsets[part] = part.CFrame
			end
		end
		root.CFrame = cframe
		EnemyService.addYawAlign(root, cframe.LookVector)
		local body: Body = {
			position = cframe.Position,
			velocity = Vector3.zero,
			goal = nil,
			walkSpeed = 16,
			offsets = offsets,
			physT = clock.t,
		}
		bodies[model] = body
		placeParts(model, body)
	end,
	-- Model:PivotTo (EnemyService.place, D-333): the whole model moves there and keeps its
	-- velocity and its Humanoid's MoveTo goal, as the engine's does.
	pivot = function(model: Model, cframe: CFrame)
		local body = bodies[model]
		body.position = cframe.Position
		placeParts(model, body)
	end,
	position = function(model: Model): Vector3
		return bodies[model].position
	end,
	facing = function(model: Model): Vector3
		return yawOf(model)
	end,
	setFacing = function(model: Model, facing: Vector3)
		EnemyService.applyFacing(model, facing)
	end,
	moveTo = function(model: Model, position: Vector3)
		bodies[model].goal = position
		bodies[model].called = true
	end,
	stop = function(model: Model)
		local body = bodies[model]
		body.goal = body.position
		body.called = true
	end,
	halt = function(model: Model, position: Vector3?)
		local body = bodies[model]
		if position ~= nil then
			body.position = Vector3.new(position.X, body.position.Y, position.Z)
		end
		body.velocity = Vector3.zero
		body.goal = body.position
		body.written = true
		body.called = true
		placeParts(model, body)
	end,
	-- Carries the body onto `position` (its height kept) by its velocity over `seconds`, then stops it
	-- dead there: no CFrame write. The studio and tolerant Humanoids get what the real engine.land
	-- does: the flat velocity that covers the way in `seconds`, that pace as its WalkSpeed, and
	-- MoveTo `past` studs beyond `position` the way it goes.
	land = function(model: Model, position: Vector3, seconds: number, past: number?)
		local body = bodies[model]
		if humanoid.mode == "studio" or humanoid.mode == "tolerant" then
			local offset = Vector3.new(position.X - body.position.X, 0, position.Z - body.position.Z)
			local pace = if seconds > 0 then offset / seconds else Vector3.zero
			local way = if offset.Magnitude > 1e-9 then offset.Unit else Vector3.zero
			local aim = position + way * (past or 0)
			body.velocity = pace
			body.walkSpeed = pace.Magnitude
			body.goal = Vector3.new(aim.X, body.position.Y, aim.Z)
			body.written = true
			body.called = true
			return
		end
		body.landing = {
			to = Vector3.new(position.X, body.position.Y, position.Z),
			untilT = body.physT + math.max(seconds, PHYSICS_STEP),
		}
		body.goal = body.landing.to
	end,
	setWalkSpeed = function(model: Model, speed: number)
		bodies[model].walkSpeed = speed
	end,
	computePath = function()
		return nil
	end,
	destroy = function(model: Model)
		model.Parent = nil
		bodies[model] = nil
	end,
	setCollisionGroup = function(model: Model, group: string)
		CollisionGroups.assign(model, group)
	end,
	bodyClear = function(): boolean
		return true
	end,
	worldAhead = function(model: Model, direction: Vector3, distance: number, offset: Vector3?, walk: Vector3?)
		return EnemyService.worldAhead(model, direction, distance, function(start, size, vector)
			return blockcast(start, size, vector)
		end, offset, walk)
	end,
}

-- The dev folder's parts as walls: each part's thin face toward `from` (the line's crouch point).
local wallFrom = Vector3.zero
local function syncWalls()
	table.clear(walls)
	local folder = if devWorkspace ~= nil then devWorkspace:FindFirstChild(HOOKS.folderName) else nil
	if folder == nil then
		return
	end
	for _, part in folder:GetChildren() do
		local size, frame = part.Size, part.CFrame
		local axis, half = frame.LookVector, size.Z / 2
		if size.X <= size.Y and size.X <= size.Z then
			axis, half = frame.RightVector, size.X / 2
		elseif size.Y <= size.Z then
			axis, half = frame.UpVector, size.Y / 2
		end
		local out = if (wallFrom - frame.Position):Dot(axis) >= 0 then axis else -axis
		table.insert(walls, { point = frame.Position + out * half, out = out })
	end
end

-- The root's box at `nextPosition` pushed out of every wall (its velocity into a wall dropped).
local function outOfWalls(model: Model, body: Body, nextPosition: Vector3): Vector3
	local root = model.PrimaryPart :: BasePart
	local frame = CFrame.lookAt(nextPosition, nextPosition + yawOf(model))
	local at = nextPosition
	local all = table.clone(walls)
	table.move(hiddenWalls, 1, #hiddenWalls, #all + 1, all)
	for _, wall in all do
		local depth = support(frame, root.Size / 2, wall.out) - (at - wall.point):Dot(wall.out)
		if depth > 0 then
			at += wall.out * depth
			local into = body.velocity:Dot(wall.out)
			if into < 0 then
				body.velocity -= wall.out * into
			end
		end
	end
	return at
end

-- One frame of the studio Humanoid (see `humanoid`): its walk settled at the frame's start, then
-- 240 Hz steps up to `untilT`.
local function studioFrame(model: Model, body: Body, untilT: number)
	local seconds = untilT - body.physT
	local desired: Vector3? = nil
	local goal = body.goal
	if goal ~= nil then
		local delta = Vector3.new(goal.X - body.position.X, 0, goal.Z - body.position.Z)
		local reached = humanoid.arriveFrames * body.walkSpeed * math.max(seconds, 0)
		if delta.Magnitude > math.max(reached, 1e-3) then
			desired = delta.Unit * body.walkSpeed
		end
	end
	local kept = body.written == true
	body.written = false
	while body.physT + PHYSICS_STEP <= untilT + FLOOR_GAP do
		body.physT += PHYSICS_STEP
		if desired ~= nil then
			local change = desired - body.velocity
			local most = humanoid.acceleration * PHYSICS_STEP
			if change.Magnitude > most then
				change = change.Unit * most
			end
			body.velocity += change
		elseif not kept then
			body.velocity *= humanoid.brake
			if body.velocity.Magnitude < 0.01 then
				body.velocity = Vector3.zero
			end
		end
		body.position = outOfWalls(model, body, body.position + body.velocity * PHYSICS_STEP)
	end
	placeParts(model, body)
end

-- The studs the tolerant Humanoid runs on from `speed` once its target is nothing.
local function tolerantBrake(speed: number): number
	local v, run = speed, 0
	for _ = 1, 240 do
		v -= math.min(humanoid.cap * PHYSICS_STEP, humanoid.gain * v)
		if v < 1e-4 then
			break
		end
		run += v * PHYSICS_STEP
	end
	return run
end

-- One frame of the tolerant Humanoid (see `humanoid`): its walk settled at the frame's start, then
-- 240 Hz steps up to `untilT`, then a walk given on the way arrives.
local function tolerantFrame(model: Model, body: Body, untilT: number)
	local seconds = math.max(untilT - body.physT, 0)
	local function left(): Vector3
		local goal = body.goal
		if goal == nil then
			return Vector3.zero
		end
		return Vector3.new(goal.X - body.position.X, 0, goal.Z - body.position.Z)
	end
	if body.called then
		body.called = false
		if body.walking then
			body.band = "run"
		else
			body.walking = left().Magnitude > humanoid.startStuds
			body.band = "start"
		end
	end
	local speed = flat(body.velocity).Magnitude
	if
		body.walking
		and body.band == "start"
		and left().Magnitude - speed * seconds - tolerantBrake(speed) <= humanoid.startStuds
	then
		body.walking = false
	end
	local target = Vector3.zero
	local walkSpeed = body.walkSpeed
	local way = left()
	if body.walking and way.Magnitude > 1e-3 then
		target = way.Unit * walkSpeed
	end
	body.written = false
	while body.physT + PHYSICS_STEP <= untilT + FLOOR_GAP do
		body.physT += PHYSICS_STEP
		local change = (target - flat(body.velocity)) * humanoid.gain
		local most = humanoid.cap * PHYSICS_STEP
		if change.Magnitude > most then
			change = change.Unit * most
		end
		body.velocity = flat(body.velocity) + change
		body.position = outOfWalls(model, body, body.position + body.velocity * PHYSICS_STEP)
	end
	if body.walking and body.band == "run" and left().Magnitude <= humanoid.runFrames * walkSpeed * seconds then
		body.walking = false
	end
	placeParts(model, body)
end

local function physics(untilT: number)
	for model, body in bodies do
		if humanoid.mode == "studio" then
			studioFrame(model, body, untilT)
			continue
		end
		if humanoid.mode == "tolerant" then
			tolerantFrame(model, body, untilT)
			continue
		end
		local root = model.PrimaryPart :: BasePart
		while body.physT + PHYSICS_STEP <= untilT + FLOOR_GAP do
			local landing = body.landing
			if landing ~= nil then
				local left = landing.untilT - body.physT
				body.physT += PHYSICS_STEP
				if left <= PHYSICS_STEP + FLOOR_GAP then
					body.position = landing.to
					body.velocity = Vector3.zero
					body.goal = landing.to
					body.landing = nil
				else
					body.velocity = (landing.to - body.position) / left
					body.position += body.velocity * PHYSICS_STEP
				end
				continue
			end
			body.physT += PHYSICS_STEP
			local desired = Vector3.zero
			local goal = body.goal
			if goal ~= nil then
				local delta = Vector3.new(goal.X - body.position.X, 0, goal.Z - body.position.Z)
				if delta.Magnitude > 0.05 then
					desired = delta.Unit * math.min(body.walkSpeed, delta.Magnitude / PHYSICS_STEP)
				end
			end
			local change = desired - body.velocity
			local most = ACCELERATION * PHYSICS_STEP
			if change.Magnitude > most then
				change = change.Unit * most
			end
			body.velocity += change
			local nextPosition = body.position + body.velocity * PHYSICS_STEP
			local frame = CFrame.lookAt(nextPosition, nextPosition + yawOf(model))
			for _, wall in walls do
				local depth = support(frame, root.Size / 2, wall.out) - (nextPosition - wall.point):Dot(wall.out)
				if depth > 0 then
					nextPosition += wall.out * depth
					local into = body.velocity:Dot(wall.out)
					if into < 0 then
						body.velocity -= wall.out * into
					end
				end
			end
			body.position = nextPosition
		end
		placeParts(model, body)
	end
end

-- One server frame (60 Hz unless `humanoid` says otherwise): the parts due land, then physics, the
-- AI, the entities, the combat tick. Returns the frame's seconds.
local FRAME = 1 / 60
-- Called at the end of every server frame while set (a case's per-frame log).
local frameHook: (() -> ())? = nil
local function serverFrame(): number
	local dt = FRAME
	if humanoid.fps ~= 60 or humanoid.jitter > 0 then
		dt = (1 + humanoid.jitter * (2 * humanoid.random:NextNumber() - 1)) / humanoid.fps
	end
	clock.t += dt
	local due = {}
	for index = #delayed, 1, -1 do
		if delayed[index].at <= clock.t + FLOOR_GAP then
			table.insert(due, 1, table.remove(delayed, index))
		end
	end
	for _, item in due do
		item.fn()
	end
	syncWalls()
	physics(clock.t)
	EnemyService.step(dt)
	EntityService.tick(dt)
	CombatService.tick()
	local hook = frameHook
	if hook ~= nil then
		hook()
	end
	return dt
end

local function frames(seconds: number)
	local stop = clock.t + seconds - FRAME / 2
	while clock.t < stop do
		serverFrame()
	end
end

-- The DevCombat Script as Studio runs it, with this spec's services and clock.
local function loadDevCombat()
	local bindable: any = nil
	local services: { [string]: any } = {
		Players = {
			GetPlayers = function(): { any }
				return {}
			end,
		},
		RunService = {
			IsStudio = function(): boolean
				return true
			end,
		},
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
		ServerScriptService = { Name = "ServerScriptService" },
	}
	local antiCheat = setmetatable({}, {
		__index = function(_self: any, key: string): any
			return function(): any
				table.insert(antiCheatCalls, key)
				return true
			end
		end,
	})
	devWorkspace = roblox.Instance.new("Folder")
	devWorkspace.Name = "Workspace"
	devWorkspace:SetAttribute(Dev.attributes.capture, true)
	local env = Harness.environment()
	env.script = Harness.node("src/server/dev/DevCombat")
	env.require = function(node: any): any
		if node.Name == "AntiCheatService" then
			return antiCheat
		end
		return Harness.loadModule(node)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name] or error("no service " .. name)
		end,
	}
	env.workspace = devWorkspace
	env.Instance = {
		new = function(className: string): any
			if className == "BindableFunction" then
				bindable = { ClassName = className }
				return bindable
			end
			return roblox.Instance.new(className :: any)
		end,
	}
	env.print = function() end
	env.task = {
		wait = function(_seconds: number?): number
			return serverFrame()
		end,
		delay = function(seconds: number, fn: () -> ())
			table.insert(delayed, { at = clock.t + seconds, fn = fn })
		end,
	}
	env.os = {
		clock = function(): number
			return clock.t
		end,
	}
	luau.load(Harness.readFile(FILE), { debugName = FILE, environment = env :: any })()
	invokeDev = function(command: string, args: any): any
		return bindable.OnInvoke(command, args)
	end
end

local function fresh()
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	clock.t = 1000
	sent = {}
	bodies = {}
	walls = {}
	delayed = {}
	antiCheatCalls = {}
	wallFrom = Vector3.zero
	table.clear(hiddenWalls)
	local now = function()
		return clock.t
	end
	EntityService.bind({
		now = now,
		fireAll = record,
		heartbeat = nil,
		addTag = function(instance, tag)
			CollectionService:AddTag(instance, tag)
		end,
		removeTag = function(instance, tag)
			CollectionService:RemoveTag(instance, tag)
		end,
		respawn = function() end,
		playerRemoving = nil,
	})
	CombatService.bind({
		now = now,
		net = {
			on = function() end,
			fire = function(remote, _player, payload)
				record(remote, payload)
			end,
			fireAll = record,
		},
		heartbeat = nil,
		cast = function()
			return nil
		end,
		overlap = function()
			return {}
		end,
		random = Random.new(1),
	})
	EnemyService.bind({
		entities = EntityService,
		combat = CombatService,
		rigBuilder = RigBuilder,
		fireAll = record,
		engine = engine,
		players = function()
			local list = {}
			for _, player in EntityService.players() do
				if player.state ~= "Dead" then
					table.insert(list, { id = player.id, position = EntityService.positionOf(player.id) })
				end
			end
			return list
		end,
		heartbeat = nil,
		serverTime = now,
		folder = Instance.new("Folder"),
		random = Random.new(3),
		spawnTask = function(fn)
			fn()
		end,
	} :: any)
	loadDevCombat()
end

local playerCount = 0
local function spawnPlayer(position: Vector3): (Model, number)
	playerCount += 1
	local model = Instance.new("Model")
	model.Name = "Trialist" .. playerCount
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position)
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	CollisionGroups.assign(model, AI.collision.players)
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 3100 + playerCount }
	return model, EntityService.registerPlayer(player :: any, model, Playground.loadout)
end

-- ------------------------------------------------------------------------------------------
-- What the cases measure
-- ------------------------------------------------------------------------------------------

-- Every CFrame write the server makes on `model` (a halt onto a position, a pivot), with its time.
local writes: { { model: Model, time: number, kind: string } } = {}
local engineHalt = engine.halt
engine.halt = function(model: Model, position: Vector3?)
	if position ~= nil then
		table.insert(writes, { model = model, time = clock.t, kind = "halt" })
	end
	engineHalt(model, position)
end
-- Every land the server asks of the engine, with its time and seconds (D-525).
local lands: { { model: Model, time: number, seconds: number, past: number? } } = {}
local engineLand = engine.land
engine.land = function(model: Model, position: Vector3, seconds: number, past: number?)
	table.insert(lands, { model = model, time = clock.t, seconds = seconds, past = past })
	engineLand(model, position, seconds, past)
end
local enginePivot = engine.pivot
engine.pivot = function(model: Model, cframe: CFrame)
	table.insert(writes, { model = model, time = clock.t, kind = "pivot" })
	enginePivot(model, cframe)
end

-- Whether the server last anchored each body (284: a held enemy must not move when a player walks
-- into it; the engine seam `anchor` sets the root's Anchored, and on false hands the body back to
-- the server's physics, network owner nil).
local anchoredOf: { [Model]: boolean } = {}
engine.anchor = function(model: Model, anchored: boolean)
	anchoredOf[model] = anchored
end

local function writesOn(model: Model, from: number): number
	local count = 0
	for _, entry in writes do
		if entry.model == model and entry.time >= from - FLOOR_GAP then
			count += 1
		end
	end
	return count
end

local WALL_Z = -12.5 -- a 16 x 8 x 1 wall whose near face stands 12 studs ahead of the crouch

-- A boar held at the origin facing -Z, a player far behind it, and a wall ahead when asked.
local function boarAtOrigin(wallZ: number?): (number, Model)
	fresh()
	spawnPlayer(Vector3.new(0, 3, 60))
	local id = EnemyService.spawn("FrenzyBoar", CFrame.new(40, BOAR_HEIGHT, 40))
	local model = EnemyService.modelOf(id) :: Model
	frames(0.3)
	if wallZ ~= nil then
		assert(
			invokeDev("part", { size = { 16, 8, 1 }, position = { 0, 4, wallZ }, name = "Wall" }).ok,
			"the Studio hook refused it"
		)
	end
	assert(
		invokeDev("enemy", { entityId = id, position = { 0, 0, 0 }, facing = 0, hold = true }).ok,
		"the Studio hook refused it"
	)
	frames(0.3)
	table.clear(writes)
	return id, model
end

describe("Boar hooks: rests, holds and walls after the 1cf87aa PC run", function()
	it("a slam brings the body onto its stop by its own motion, never a CFrame write mid-rush", function()
		-- PC 1cf87aa M9/306(c): the server's halt onto the stop is a PivotTo, which every client shows
		-- as a teleport of the replicated root past its interpolation (5.2-5.9 studs in one frame), so
		-- the drawn body jumps that far through the wall for a frame.
		local id, model = boarAtOrigin(WALL_Z)
		local from = clock.t
		local reply = invokeDev("charge", { entityId = id, toward = { 0, 0, -20 } })
		expect(reply.ok).toBe(true)
		frames(2.5)
		local ended = sentOf("RushEnded", id)
		expect(#ended >= 1).toBe(true)
		expect(ended[1].payload.reason).toBe("Wall")
		expect(writesOn(model, from)).toBe(0)
		-- It still rests on the stop every client was told.
		expect(math.abs(-bodies[model].position.Z - ended[1].payload.distance)).toBeLessThanOrEqual(0.05)
		expect(depthInWalls(model)).toBeLessThanOrEqual(0.05)
	end)

	it("a free rush rests on its line's end, where every client draws the skid", function()
		-- FB hand-back (critic item 7): the run ends Done one frame short and the recovery's stop
		-- leaves the body 0.4-0.5 studs short of the line every client drew, so the drawn body slides
		-- back that far as it is handed back to the root.
		local id, model = boarAtOrigin(nil)
		local from = clock.t
		expect(invokeDev("charge", { entityId = id, toward = { 0, 0, -20 } }).ok).toBe(true)
		frames(2.5)
		local started = sentOf("RushStarted", id)[1].payload
		local length = started.speed * started.duration
		local origin = Vector3.new(started.origin[1], 0, started.origin[3])
		local along = (flat(bodies[model].position) - origin).Magnitude
		expect(math.abs(along - length)).toBeLessThanOrEqual(0.05)
		expect(writesOn(model, from)).toBe(0)
	end)

	it("a boar held right after a slam charges again once its daze is over", function()
		-- PC 1cf87aa G4: enemy{hold=true} after a slam left the sleeping brain Interrupted for good
		-- (a held brain never ticks, so its interrupt never ends): charge was refused for minutes while
		-- the record showed Idle.
		local id = boarAtOrigin(WALL_Z)
		expect(invokeDev("charge", { entityId = id, toward = { 0, 0, -20 } }).ok).toBe(true)
		expect(invokeDev("enemy", { entityId = id, position = { 0, 0, 0 }, facing = 0, hold = true }).ok).toBe(true)
		frames(AI.rushWorld.slamDazeSeconds + AI.interrupt.resumeDelay)
		frames(0.5)
		expect((EntityService.get(id) :: any).state).toBe("Idle")
		local again = invokeDev("charge", { entityId = id, toward = { 0, 0, -20 } })
		expect(again.error).toBeNil()
		expect(again.ok).toBe(true)
	end)

	it("walks along a wall and round its end without any part of the boar entering either wall", function()
		-- PC 1cf87aa 311(a): the walk to the end-wall corner carried the snout into the end wall
		-- (Lune: 2.40 deep). The walk's snout room casts the root box turned to the walk direction,
		-- not the body as it faces while it walks.
		fresh()
		spawnPlayer(Vector3.new(0, 3, 200))
		local id = EnemyService.spawn("FrenzyBoar", CFrame.new(-20, BOAR_HEIGHT, 20))
		local model = EnemyService.modelOf(id) :: Model
		frames(0.3)
		wallFrom = Vector3.new(0, 4, -20)
		assert(
			invokeDev("part", { size = { 1, 8, 40 }, position = { 4, 4, -20 }, name = "Long" }).ok,
			"the Studio hook refused it"
		)
		assert(
			invokeDev("part", { size = { 16, 8, 1 }, position = { -3.5, 4, -40.5 }, name = "End" }).ok,
			"the Studio hook refused it"
		)
		assert(
			invokeDev("enemy", { entityId = id, position = { 2.2, 0, 0 }, facing = 0, hold = true }).ok,
			"the Studio hook refused it"
		)
		frames(0.5)
		local deepest = 0
		for _, toward in { { 2.2, 0, -36 }, { -8, 0, -37 } } do
			expect(invokeDev("walk", { entityId = id, toward = toward, hold = true, wait = false }).ok).toBe(true)
			local began = clock.t
			while EnemyService.walking(id) and clock.t - began < HOOKS.walkTimeoutSeconds + 1 do
				serverFrame()
				deepest = math.max(deepest, depthInWalls(model))
			end
		end
		local tickWalk = BOAR.moveSpeed * AI.tickSeconds()
		expect(deepest).toBeLessThanOrEqual(math.min(0.05, tickWalk))
	end)

	it("a walk the end wall cuts short is over once the body stands at the cut, not at the timeout", function()
		-- PC 1cf87aa 311(a): the walk along the wall stood 2.4 studs short (Lune: 1.51, the snout at the
		-- face) and only ended after walkTimeoutSeconds (30 s).
		fresh()
		spawnPlayer(Vector3.new(0, 3, 200))
		local id = EnemyService.spawn("FrenzyBoar", CFrame.new(-20, BOAR_HEIGHT, 20))
		frames(0.3)
		wallFrom = Vector3.new(0, 4, -20)
		assert(
			invokeDev("part", { size = { 1, 8, 40 }, position = { 4, 4, -20 }, name = "Long" }).ok,
			"the Studio hook refused it"
		)
		assert(
			invokeDev("part", { size = { 16, 8, 1 }, position = { -3.5, 4, -40.5 }, name = "End" }).ok,
			"the Studio hook refused it"
		)
		assert(
			invokeDev("enemy", { entityId = id, position = { 2.2, 0, 0 }, facing = 0, hold = true }).ok,
			"the Studio hook refused it"
		)
		frames(0.5)
		local reply = invokeDev("walk", { entityId = id, toward = { 2.2, 0, -36 }, hold = true, wait = true })
		expect(reply.ok).toBe(true)
		expect(reply.arrived).toBe(false)
		expect(reply.took).toBeLessThan(36 / BOAR.moveSpeed + 2)
	end)
	it("a held enemy stands anchored while it is held and goes back to the server's physics when released", function()
		-- PC 1cf87aa 284 (extra.md B1): a held kobold is unanchored and server-owned, and the
		-- client-simulated player walking into it shoves it in bursts (2.0-4.6 studs for a kobold,
		-- 0.45-1.14 for a boar). A held enemy must not move.
		for _, defId in { "KoboldAxeman", "FrenzyBoar" } do
			fresh()
			table.clear(anchoredOf)
			spawnPlayer(Vector3.new(0, 3, 200))
			local id = EnemyService.spawn(defId, CFrame.new(40, BOAR_HEIGHT, 40))
			local model = EnemyService.modelOf(id) :: Model
			frames(0.3)
			expect(anchoredOf[model] == true).toBe(false)
			assert(
				invokeDev("enemy", { entityId = id, position = { 30, 0, 30 }, facing = 0, hold = true }).ok,
				"the Studio hook refused it"
			)
			frames(0.1)
			expect(anchoredOf[model]).toBe(true)
			assert(invokeDev("hold", { ids = id, on = false }).ok, "the Studio hook refused it")
			frames(0.5)
			expect(anchoredOf[model]).toBe(false)
			-- Held again through the hold command, then a walk that ends held.
			assert(invokeDev("hold", { ids = id }).ok, "the Studio hook refused it")
			frames(0.1)
			expect(anchoredOf[model]).toBe(true)
			expect(antiCheatCalls).toEqual({})
		end
	end)
end)

-- ------------------------------------------------------------------------------------------
-- AI 423(c) and 422(d): where the server body rests against the stop it was told
-- ------------------------------------------------------------------------------------------

type HumanoidSettings = {
	mode: string?,
	fps: number?,
	jitter: number?,
	seed: number?,
	arriveFrames: number?,
}

type Rest = {
	told: number, -- the told stop: RushEnded Wall's distance, or the line end (speed × duration)
	finalTold: number?, -- the distance the stop that ended the rush told (a slam's Interrupted)
	rest: number, -- the root's distance down the line 1 s after the stop that ended the rush
	farthest: number, -- the farthest the root got down the line, launch to then
	backStep: number, -- the largest step the root took back up the line between two frames
	doneAt: number?, -- seconds from the launch to the run's Done, if it ran its time
	duration: number, -- the run's time (RushStarted)
	writes: number, -- CFrame writes on the body from the charge on
	rows: { { t: number, along: number, speed: number, walkSpeed: number } },
	launch: number, -- the server time of the launch (RushStarted's serverTime)
}

local PROBE = false

-- A held boar at the origin charges -Z (a wall's face 12 studs ahead of its root when `wallZ` is
-- given; the open field otherwise), with the fake engine's Humanoid and frames as `settings` asks.
-- The server root is logged every frame from the launch to 1 s after the stop that ends the rush
-- (item 420 column 4).
local function restRun(wallZ: number?, settings: HumanoidSettings, hiddenAt: number?): Rest
	humanoid.mode = settings.mode or "studio"
	humanoid.fps = settings.fps or 60
	humanoid.jitter = settings.jitter or 0
	humanoid.random = Random.new(settings.seed or 11)
	humanoid.arriveFrames = settings.arriveFrames or 1.7
	local id, model = boarAtOrigin(wallZ)
	if hiddenAt ~= nil then
		table.insert(hiddenWalls, { point = Vector3.new(0, 0, -(hiddenAt + 2.5)), out = Vector3.zAxis })
	end
	local from = clock.t
	local body = bodies[model]
	local launch: number? = nil
	local origin, direction = Vector3.zero, -Vector3.zAxis
	local result: Rest = {
		told = 0,
		finalTold = nil,
		rest = 0,
		farthest = -math.huge,
		backStep = 0,
		doneAt = nil,
		duration = 0,
		writes = 0,
		rows = {},
		launch = 0,
	}
	local endedAt: number? = nil
	local finished = false
	local last: number? = nil
	frameHook = function()
		if finished then
			return
		end
		local started = sentOf("RushStarted", id)
		if launch == nil and #started > 0 then
			local payload = started[1].payload
			launch = payload.serverTime
			origin = Vector3.new(payload.origin[1], 0, payload.origin[3])
			direction = Vector3.new(payload.direction[1], 0, payload.direction[3]).Unit
			result.told = payload.speed * payload.duration
			result.duration = payload.duration
			result.launch = payload.serverTime
		end
		local launchedAt = launch
		if launchedAt == nil then
			return
		end
		local along = (flat(body.position) - origin):Dot(direction)
		table.insert(result.rows, {
			t = clock.t - launchedAt,
			along = along,
			speed = flat(body.velocity).Magnitude,
			walkSpeed = body.walkSpeed,
		})
		result.farthest = math.max(result.farthest, along)
		if last ~= nil then
			result.backStep = math.max(result.backStep, last - along)
		end
		last = along
		local log = EnemyService.devRushOf(id)
		if endedAt == nil and log ~= nil then
			for _, stop in log.stops do
				if stop.reason == "Wall" then
					result.told = stop.distance
				elseif stop.reason == "Done" then
					result.doneAt = stop.at - launchedAt
					endedAt = clock.t
				else
					result.finalTold = stop.distance
					endedAt = clock.t
				end
			end
		end
		local ended = endedAt
		if ended ~= nil and clock.t - ended >= 1 - FLOOR_GAP then
			result.rest = along
			finished = true
		end
	end
	expect(invokeDev("charge", { entityId = id, toward = { 0, 0, -20 } }).ok).toBe(true)
	local guard = 0
	while not finished and guard < 2000 do
		guard += 1
		serverFrame()
	end
	frameHook = nil
	assert(finished, "the rush never ended")
	result.writes = writesOn(model, from)
	humanoid.mode = "ideal"
	humanoid.fps = 60
	humanoid.jitter = 0
	humanoid.arriveFrames = 1.7
	if PROBE then
		print(
			("told %.3f rest %.3f (%+.3f) farthest %+.3f backStep %.3f final %s done %s"):format(
				result.told,
				result.rest,
				result.rest - result.told,
				result.farthest - result.told,
				result.backStep,
				tostring(result.finalTold),
				tostring(result.doneAt)
			)
		)
		for _, row in result.rows do
			if (row.t < 0.3 and result.told < 10) or (row.t > 0.7 and row.t < 0.9) then
				print(("  +%.3f along %.3f speed %.2f walk %.2f"):format(row.t, row.along, row.speed, row.walkSpeed))
			end
		end
	end
	return result
end

describe("A rush's server body rests on its told stop (AI 423(c), 422(d), D-525)", function()
	it("a slam and an open run rest on their stops at 60 Hz, where the PC's log on 4b18b5c rested off them", function()
		-- The PC's server log (Studio, 60 fps, lag 0; this file's studio Humanoid plays it: rows 3.027,
		-- 5.822 → 6.294 and 21.227 → 21.417 → 21.456 against its 3.028, 5.828 → 6.295 and 21.228 →
		-- 21.454 → 21.466). The slam was landed 0.341 short of its told 6.169 on a landing timed to end
		-- inside the frame, ran the whole frame at 28 and was halted a frame later: 0.126 past (Lune
		-- 0.125 on 4b18b5c). The open run's Humanoid braked 0.772 short of the line end on its own, and
		-- a body 0.534 short is no landing for a frame's lead, so it stood there: 0.533 short (Lune
		-- 0.534).
		for _, kind in { "slam", "open" } do
			local wall = if kind == "slam" then WALL_Z else nil
			local run = restRun(wall, {})
			expect(math.abs(run.rest - run.told)).toBeLessThanOrEqual(0.05)
			expect(run.farthest - run.told).toBeLessThanOrEqual(0.05)
			expect(run.backStep).toBeLessThanOrEqual(1e-6)
			expect(run.writes).toBe(0)
			if wall ~= nil then
				-- The stop that ends the slam (its daze) tells the rest too.
				expect(math.abs((run.finalTold :: number) - run.told)).toBeLessThanOrEqual(0.05)
			end
		end
	end)

	it("rests within 0.05 of its stop at 60 and 144 Hz server frames, jittered, never past it nor back", function()
		local worst = { rest = 0, past = -math.huge, back = 0 }
		for _, fps in { 60, 144 } do
			for _, jitter in { 0, 0.25 } do
				for seed = 1, if jitter > 0 then 3 else 1 do
					for _, kind in { "slam", "open" } do
						local wall = if kind == "slam" then WALL_Z else nil
						local run = restRun(wall, { fps = fps, jitter = jitter, seed = seed })
						worst.rest = math.max(worst.rest, math.abs(run.rest - run.told))
						worst.past = math.max(worst.past, run.farthest - run.told)
						worst.back = math.max(worst.back, run.backStep)
						expect(run.writes).toBe(0)
					end
				end
			end
		end
		print(
			("[423(c)] studio Humanoid, 60/144 Hz, jitter 0/0.25: rest off its stop %.3f, farthest past %+.3f, back %.4f"):format(
				worst.rest,
				worst.past,
				worst.back
			)
		)
		expect(worst.rest).toBeLessThanOrEqual(0.05)
		expect(worst.past).toBeLessThanOrEqual(0.05)
		expect(worst.back).toBeLessThanOrEqual(1e-6)
	end)

	it("rests on its stop whether the Humanoid never brakes short or brakes as far as its lead", function()
		-- What makes Studio's Humanoid brake short is not in the log (0.772 braked, 0.808 ran on, at
		-- 60 fps): a Humanoid that only ever runs on past its goal, and one that holds a goal 1.95
		-- frames out reached (0.91 at 60 Hz, inside the 0.933 lead), both land on the stop. On
		-- 4b18b5c the first ran 0.579 past the slam's stop at 60 Hz and walked 0.552 back: once
		-- halted there, MoveTo was sent to the stop again and it ran a whole frame through it.
		local worst = { rest = 0, past = -math.huge, back = 0 }
		for _, arrive in { 0, 1.95 } do
			for _, fps in { 60, 144 } do
				for _, kind in { "slam", "open" } do
					local wall = if kind == "slam" then WALL_Z else nil
					local run = restRun(wall, { fps = fps, arriveFrames = arrive, jitter = 0.1, seed = 5 })
					worst.rest = math.max(worst.rest, math.abs(run.rest - run.told))
					worst.past = math.max(worst.past, run.farthest - run.told)
					worst.back = math.max(worst.back, run.backStep)
				end
			end
		end
		print(
			("[423(c)] Humanoids braking at 0 and 1.95 frames: rest off its stop %.3f, farthest past %+.3f, back %.4f"):format(
				worst.rest,
				worst.past,
				worst.back
			)
		)
		expect(worst.rest).toBeLessThanOrEqual(0.05)
		expect(worst.past).toBeLessThanOrEqual(0.05)
		expect(worst.back).toBeLessThanOrEqual(1e-6)
	end)

	it("keeps the run's end on its time, and a landing the world holds short ends in landMaxSeconds", function()
		-- Done still comes when the run's time is over (the clients' timeline): 22 / 28 = 0.786 s
		-- after the body started, on the first frame after it. A body something unseen holds short of
		-- its line end (here 21.6) is landed for at most landMaxSeconds and then stopped dead there.
		local open = restRun(nil, {})
		local duration = open.duration
		expect(open.doneAt).toBeGreaterThanOrEqual(duration)
		expect(open.doneAt).toBeLessThanOrEqual(duration + 2 / 60 + 1e-6)
		table.clear(lands)
		local held = restRun(nil, {}, 21.6)
		expect(held.doneAt).toBeGreaterThanOrEqual(duration)
		expect(held.doneAt).toBeLessThanOrEqual(duration + 2 / 60 + 1e-6)
		expect(math.abs(held.rest - 21.6)).toBeLessThanOrEqual(0.01)
		expect(#lands >= 2).toBe(true)
		local first, last = lands[1].time, lands[#lands].time
		expect(last - first).toBeLessThanOrEqual(AI.movement.landMaxSeconds + 1e-6)
		-- Stopped dead after it: still on the next rows.
		local row = held.rows[#held.rows]
		expect(row.speed).toBe(0)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- AI 440 and 441: the landing against Studio's MoveTo tolerance (the PC's P2 probe, D-548)
-- ------------------------------------------------------------------------------------------

-- The land and landed rows of a run (item 439): the first land, and the first row after it whose
-- flat velocity reads 0, in seconds from the launch; nil when there was none.
local function landRows(run: Rest, model: Model?): (number?, number?)
	local landAt: number? = nil
	for _, entry in lands do
		if (model == nil or entry.model == model) and entry.time >= run.launch then
			landAt = entry.time - run.launch
			break
		end
	end
	if landAt == nil then
		return nil, nil
	end
	for _, row in run.rows do
		if row.t > (landAt :: number) + 1e-9 and row.speed < 1e-6 then
			return landAt, row.t
		end
	end
	return landAt, nil
end

-- The PC's P2 probe on the fake engine's tolerant Humanoid: a body standing still is given
-- WalkSpeed `walkSpeed` and MoveTo `ahead` studs down -Z on a Heartbeat, then `rows` frames at
-- `fps` are stepped (physics only: no AI moves it). `stopAfter`: MoveTo where it stands (the
-- Humanoid's own stop, as Move(Vector3.zero) is) after that many rows. Returns each row's step and
-- what is left to the goal at the end.
local function probeWalk(
	model: Model,
	walkSpeed: number,
	ahead: number,
	fps: number,
	rows: number,
	stopAfter: number?
): ({ number }, number)
	local body = bodies[model]
	local start = Vector3.new(0, body.position.Y, 0)
	body.position = start
	body.velocity = Vector3.zero
	body.goal = start
	body.walking = false
	body.called = false
	body.physT = clock.t
	engine.setWalkSpeed(model, walkSpeed)
	local goal = start - Vector3.zAxis * ahead
	engine.moveTo(model, goal)
	local steps = {}
	local last = start
	for row = 1, rows do
		clock.t += 1 / fps
		physics(clock.t)
		table.insert(steps, (flat(body.position) - flat(last)).Magnitude)
		last = body.position
		if stopAfter ~= nil and row == stopAfter then
			engine.stop(model)
		end
	end
	return steps, (flat(goal) - flat(body.position)).Magnitude
end

describe("A rush's landing against Studio's MoveTo tolerance (AI 440, 441, D-548)", function()
	it("the fake engine's tolerant Humanoid plays the PC's P2 probe rows (4e60f11)", function()
		humanoid.mode = "tolerant"
		local _, model = boarAtOrigin(nil)
		-- §1: a goal within the tolerance never starts it, at any WalkSpeed (30 rows, no move).
		for _, case in { { 28, 1 }, { 28, 1.5 }, { 28, 2 }, { 14, 3 }, { 8, 5 }, { 4, 10 }, { 2, 10 } } do
			local steps = probeWalk(model, case[1], case[2] * case[1] / 60, 60, 30)
			for _, step in steps do
				expect(step).toBeLessThanOrEqual(1e-9)
			end
		end
		-- §1: a longer goal is walked to about 0.93 short (more at 28): the PC's steps and what is left.
		-- The probe's goals (k frames of walk) put the last frame of W 28 k 10, W 14 k 10 and W 8 k 10
		-- exactly on a predicted rest of 14/15 = 0.9333 stud, where the PC braked the first and walked
		-- the other two one frame more: this Humanoid brakes all three there, so those two stop a
		-- frame's walk short of the PC's (`tie`).
		for _, case in
			{
				{ walk = 28, k = 3, steps = { 0.240, 0.153, 0.005 }, left = 1.001 },
				{ walk = 28, k = 10, steps = { 0.240, 0.455, 0.466, 0.467 }, left = 1.400 },
				{ walk = 14, k = 5, steps = { 0.179, 0.051 }, left = 0.935 },
				{ walk = 14, k = 10, steps = { 0.179, 0.232, 0.233 }, left = 0.933, tie = true },
				{ walk = 8, k = 10, steps = { 0.114, 0.133 }, left = 0.933, tie = true },
			}
		do
			local steps, left = probeWalk(model, case.walk, case.k * case.walk / 60, 60, 30)
			if PROBE then
				local text = {}
				for index = 1, 10 do
					table.insert(text, ("%.3f"):format(steps[index]))
				end
				print(("P2 W %d k %d: %s left %.3f"):format(case.walk, case.k, table.concat(text, " "), left))
			end
			for index, step in case.steps do
				expect(math.abs(steps[index] - step)).toBeLessThanOrEqual(0.003)
			end
			local over = if case.tie then case.walk / 60 else 0
			expect(left - case.left).toBeGreaterThanOrEqual(-0.003)
			expect(left - case.left).toBeLessThanOrEqual(over + 0.003)
		end
		-- At 144 fps: W 8 k 10 still stops about 0.933 short; W 8 k 5 and W 2 k 10 never start.
		local _, left144 = probeWalk(model, 8, 10 * 8 / 60, 144, 60)
		expect(left144 - 0.933).toBeGreaterThanOrEqual(-0.003)
		expect(left144 - 0.933).toBeLessThanOrEqual(8 / 144 + 0.003)
		for _, case in { { 8, 5 }, { 2, 10 } } do
			local steps = probeWalk(model, case[1], case[2] * case[1] / 60, 144, 60)
			for _, step in steps do
				expect(step).toBeLessThanOrEqual(1e-9)
			end
		end
		-- §2: walked 10 rows toward a far goal and then stopped where it stands (as Move(Vector3.zero)
		-- stops it): one partial row (0.226 then 0.012 at 28; 0.054 at 14; 0.020 at 8; 0.005 at 2).
		for _, case in { { 28, 0.226, 0.012 }, { 14, 0.054, 0 }, { 8, 0.020, 0 }, { 2, 0.005, 0 } } do
			local steps = probeWalk(model, case[1], 100, 60, 14, 10)
			expect(math.abs(steps[10] - case[1] / 60)).toBeLessThanOrEqual(0.001)
			expect(math.abs(steps[11] - case[2])).toBeLessThanOrEqual(0.002)
			expect(math.abs(steps[12] - case[3])).toBeLessThanOrEqual(0.002)
			expect(steps[14]).toBeLessThanOrEqual(1e-3)
		end
		-- §3: a goal 5 studs past a mark 3 studs ahead is walked at full pace through the mark: it is
		-- crossed on row 7 at 28, 14 at 14, 23 at 8 and 91 at 2 (the PC's W 4 started 11 rows late in
		-- §2 and §3 both; this Humanoid does not play that).
		for _, case in { { 28, 7 }, { 14, 14 }, { 8, 23 }, { 2, 91 } } do
			local steps = probeWalk(model, case[1], 8, 60, 100)
			local along, crossed = 0, nil
			for row, step in steps do
				along += step
				if crossed == nil and along >= 3 then
					crossed = row
				end
			end
			expect(crossed).toBe(case[2])
		end
		humanoid.mode = "ideal"
	end)

	it("aimed at its stop (9063a60), stalls at 60 Hz as the PC's rows did and passes at 144", function()
		-- The PC on 9063a60 at 60 fps: the slam's landing WalkSpeed went 28, 25.22, 8.21, 8.26, 7.63
		-- and then slowly down to about 2.3; landed came 0.267 to 0.285 s after land, when
		-- landMaxSeconds ran out; the slam rested 0.060 to 0.090 short and the open run 0.114 to 0.144.
		-- At 144 fps both rested 0.017 to 0.020 short. movement.landAimStuds 0 aims the landing's
		-- MoveTo at its stop, as 9063a60's did: within the Humanoid's tolerance, so after its first
		-- frame the body only drifts on the velocity written on it, braked within the frame. (The PC's
		-- second row, 8.21 where this Humanoid reads 12.11, stepped 0.567 at 25.22 studs a second: a
		-- longer frame than 1/60 s; with frames jittered by a quarter, seed 5 reads 25.39, 7.56, 6.64,
		-- 8.58, 7.80 ... 2.43 and rests 0.086 short.) The open run's own Humanoid braked short of the
		-- line end before Done, as on 4b18b5c, so its landing starts 0.533 short (the PC's 0.533).
		local saved = AI.movement.landAimStuds
		AI.movement.landAimStuds = 0
		local runs = {}
		for _, fps in { 60, 144 } do
			for _, jitter in { 0, 0.25 } do
				for seed = 1, if jitter > 0 then 3 else 1 do
					for _, kind in { "slam", "open" } do
						table.clear(lands)
						local run = restRun(
							if kind == "slam" then WALL_Z else nil,
							{ mode = "tolerant", fps = fps, jitter = jitter, seed = seed }
						)
						local landAt, landedAt = landRows(run)
						local paces = {}
						local landLeft: number? = nil
						for _, row in run.rows do
							if landAt ~= nil and landLeft == nil and row.t >= landAt - 1e-9 then
								landLeft = run.told - row.along
							end
							if
								landAt ~= nil
								and row.t >= landAt - 1e-9
								and (landedAt == nil or row.t < landedAt - 1e-9)
							then
								table.insert(paces, row.walkSpeed)
							end
						end
						table.insert(runs, {
							name = ("%s %d Hz jitter %.2f seed %d"):format(kind, fps, jitter, seed),
							kind = kind,
							fps = fps,
							jitter = jitter,
							rest = run.rest - run.told,
							landing = if landAt ~= nil and landedAt ~= nil then landedAt - landAt else nil,
							paces = paces,
							landLeft = landLeft,
						})
					end
				end
			end
		end
		AI.movement.landAimStuds = saved
		for _, run in runs do
			if PROBE then
				local text = {}
				for _, pace in run.paces do
					table.insert(text, ("%.2f"):format(pace))
				end
				print(
					("%s: rest %+.3f, land to landed %s, WalkSpeed %s"):format(
						run.name,
						run.rest,
						tostring(run.landing),
						table.concat(text, ", ")
					)
				)
			end
			expect(run.landing ~= nil).toBe(true)
			if run.fps == 60 then
				-- Short of its stop by more than 440(e)'s and 441(b)'s 0.05 when landMaxSeconds runs out.
				expect(run.rest).toBeLessThan(-0.05)
				expect(run.rest).toBeGreaterThan(-0.2)
				expect(run.landing :: number).toBeGreaterThanOrEqual(AI.movement.landMaxSeconds)
				if run.jitter == 0 then
					-- One paced row (the slam's) and then no row ever halves: each is at least 0.85 of the
					-- last (the PC's 8.21, 8.26, 7.63), and the last is still above 2 (the PC's about 2.3).
					local from = if run.kind == "slam" then 3 else 2
					if run.kind == "open" then
						expect(math.abs((run.landLeft :: number) - 0.533)).toBeLessThanOrEqual(0.01)
					end
					if run.kind == "slam" then
						expect(run.paces[1]).toBeGreaterThan(20)
						expect(run.paces[2]).toBeLessThanOrEqual(run.paces[1] * 0.55)
					end
					for index = from, #run.paces do
						expect(run.paces[index]).toBeGreaterThanOrEqual(run.paces[index - 1] * 0.85)
					end
					expect(run.paces[#run.paces]).toBeGreaterThan(2)
				end
			else
				-- A pass at 144: within 0.025 short (the PC's 0.017 to 0.020), landed before the bound.
				expect(run.rest).toBeLessThanOrEqual(0)
				expect(run.rest).toBeGreaterThanOrEqual(-0.025)
				expect(run.landing :: number).toBeLessThan(AI.movement.landMaxSeconds)
			end
		end
	end)

	it("rests within 0.05 of its stop at 60 and 144 Hz, jittered, landed before landMaxSeconds is out", function()
		-- On 9063a60 the PC's server rows at 60 fps: the landing's WalkSpeed went 28, 25.22, 8.21,
		-- 8.26, 7.63 and then slowly down to about 2.3; landed came 0.267 to 0.285 s after land, when
		-- landMaxSeconds ran out, and the slam rested 0.060 to 0.090 short, the open run 0.114 to
		-- 0.144; at 144 fps both rested 0.017 to 0.020 short and passed. The pace left/(2 dt) aims the
		-- Humanoid's MoveTo at the stop, within its tolerance, so after its first frame it only drifts
		-- on the velocity written on it, braked within the frame: 7% of what is left a frame at 60
		-- fps, 13% at 144 with 2.4 times the frames.
		local worst = { rest = 0, past = -math.huge, back = 0, landing = 0 }
		for _, fps in { 60, 144 } do
			for _, jitter in { 0, 0.25 } do
				for seed = 1, if jitter > 0 then 3 else 1 do
					for _, kind in { "slam", "open" } do
						local wall = if kind == "slam" then WALL_Z else nil
						table.clear(lands)
						local run = restRun(wall, { mode = "tolerant", fps = fps, jitter = jitter, seed = seed })
						local landAt, landedAt = landRows(run)
						if PROBE then
							print(
								("%s %d Hz jitter %.2f seed %d: rest %+.3f, land %s landed %s"):format(
									kind,
									fps,
									jitter,
									seed,
									run.rest - run.told,
									tostring(landAt),
									tostring(landedAt)
								)
							)
						end
						worst.rest = math.max(worst.rest, math.abs(run.rest - run.told))
						worst.past = math.max(worst.past, run.farthest - run.told)
						worst.back = math.max(worst.back, run.backStep)
						expect(landAt ~= nil and landedAt ~= nil).toBe(true)
						worst.landing = math.max(worst.landing, (landedAt :: number) - (landAt :: number))
						expect(run.writes).toBe(0)
						expect(antiCheatCalls).toEqual({})
					end
				end
			end
		end
		print(
			("[440/441] tolerant Humanoid, 60/144 Hz, jitter 0/0.25: rest off its stop %.3f, farthest past %+.3f, back %.4f, land to landed %.3f s"):format(
				worst.rest,
				worst.past,
				worst.back,
				worst.landing
			)
		)
		expect(worst.rest).toBeLessThanOrEqual(0.05)
		expect(worst.past).toBeLessThanOrEqual(0.05)
		expect(worst.back).toBeLessThanOrEqual(1e-3)
		-- Landed because it stands on its stop, not because landMaxSeconds ran out.
		expect(worst.landing).toBeLessThan(AI.movement.landMaxSeconds - 1e-6)
	end)

	it("at 60 Hz the landing's WalkSpeed halves each row and it lands in under 0.15 s", function()
		-- Item 439 line 2: from land on, WalkSpeed reads about what is left / (2 × the row's dt) and
		-- shrinks each row. The 9063a60 PC rows held at about 8 for rows on end (8.21, 8.26, 7.63).
		for _, kind in { "slam", "open" } do
			local wall = if kind == "slam" then WALL_Z else nil
			table.clear(lands)
			local run = restRun(wall, { mode = "tolerant" })
			local landAt, landedAt = landRows(run)
			expect(landAt ~= nil and landedAt ~= nil).toBe(true)
			local paces = {}
			for _, row in run.rows do
				if row.t >= (landAt :: number) - 1e-9 and row.t < (landedAt :: number) - 1e-9 then
					table.insert(paces, row.walkSpeed)
				end
			end
			if PROBE then
				local text = {}
				for _, pace in paces do
					table.insert(text, ("%.2f"):format(pace))
				end
				print(
					("%s: land +%.3f landed +%.3f WalkSpeed %s"):format(
						kind,
						landAt :: number,
						landedAt :: number,
						table.concat(text, ", ")
					)
				)
			end
			expect(#paces >= 2).toBe(true)
			for index = 2, #paces do
				expect(paces[index]).toBeLessThanOrEqual(paces[index - 1] * 0.6)
			end
			expect((landedAt :: number) - (landAt :: number)).toBeLessThan(0.15)
		end
	end)

	it("a landing the world holds short still ends in landMaxSeconds, stopped dead, its run's end on time", function()
		-- Done still comes when the run's time is over; a body something unseen holds 0.4 short of its
		-- line end pushes on it for at most landMaxSeconds and is then stopped dead where it stands,
		-- and stays there: the MoveTo past the stop is replaced by the halt's own.
		table.clear(lands)
		local held = restRun(nil, { mode = "tolerant" }, 21.6)
		local duration = held.duration
		expect(held.doneAt).toBeGreaterThanOrEqual(duration)
		expect(held.doneAt).toBeLessThanOrEqual(duration + 2 / 60 + 1e-6)
		expect(math.abs(held.rest - 21.6)).toBeLessThanOrEqual(0.01)
		expect(#lands >= 2).toBe(true)
		local first, last = lands[1].time, lands[#lands].time
		expect(last - first).toBeLessThanOrEqual(AI.movement.landMaxSeconds + 1e-6)
		local row = held.rows[#held.rows]
		expect(row.speed).toBe(0)
		expect(held.farthest - 21.6).toBeLessThanOrEqual(0.01)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- AO 479(b) and 480(a) at 144 fps: the landing's WalkSpeed column (the PC on 209875b)
-- ------------------------------------------------------------------------------------------

describe("A rush's landing paced on every server frame at 60 and 144 Hz (AO 479(b), 480(a))", function()
	it(
		"lands every Heartbeat row at min(speed, left / (landFrames x dt)); a log read before the service reads the row before's",
		function()
			-- The PC on 209875b: at 144 fps the slam's WalkSpeed read 28 on the land row and the 3 rows
			-- after it, then 0.57, 0.35, 0.65 … of the row before; at 60 the land row read 28 and the next
			-- 20.3 to 27.2 (0.72 to 0.97 of 28) for 0.691 to 0.924 left, = left / (2 x 0.017 s): the land
			-- row's own write, a row late. The service lands the body on every Heartbeat (frameAll, not
			-- the 20 Hz tick) with that Heartbeat's dt, at the pace left / max(left / speed, landFrames x
			-- dt): never faster than the rush, so at 144 Hz it runs at 28 until it is within landFrames
			-- frames of travel of its stop (28 x 2 / 144 = 0.389) and the land row and the 2 or 3 after
			-- it write 28. A log whose Heartbeat runs before the service's reads each row's write on the
			-- next row. Frames here are Studio's at 60 and 144 fps (dt within 6 %, physics in 1/240 s
			-- steps: 3 to 5 a 60 Hz frame, 1 or 2 a 144 Hz frame).
			local speed = AI.rushSpeed(BOAR.attacks[1])
			local frameCount = AI.movement.landFrames
			local report = {}
			for _, fps in { 60, 144 } do
				for _, kind in { "slam", "open" } do
					local worstRatio, worstPace, under = 0, 0, {}
					for seed = 0, 4 do
						table.clear(lands)
						local run = restRun(
							if kind == "slam" then WALL_Z else nil,
							{ mode = "tolerant", fps = fps, jitter = if seed == 0 then 0 else 0.06, seed = seed }
						)
						local landAt, landedAt = landRows(run)
						expect(landAt ~= nil and landedAt ~= nil).toBe(true)
						local first: number? = nil
						for index, row in run.rows do
							if first == nil and math.abs(row.t - (landAt :: number)) < 1e-9 then
								first = index
							end
						end
						local landRow = first :: number
						local loggedUnder: number? = nil
						for index = landRow, #run.rows do
							local row, before = run.rows[index], run.rows[index - 1]
							if row.t > (landedAt :: number) + 1e-9 then
								break
							end
							if row.t < (landedAt :: number) - 1e-9 then
								-- One land on this Heartbeat row, at the pace of this row's left and dt.
								local count = 0
								for _, entry in lands do
									if math.abs(entry.time - run.launch - row.t) < 1e-9 then
										count += 1
									end
								end
								expect(count).toBe(1)
								local dt = row.t - before.t
								local pace = math.min(speed, (run.told - row.along) / (frameCount * dt))
								worstPace = math.max(worstPace, math.abs(row.walkSpeed - pace))
							end
							-- The PC's column: this row's log reads the write of the row before.
							local logged, loggedBefore = before.walkSpeed, run.rows[index - 2].walkSpeed
							if loggedUnder == nil and logged < speed - 1e-6 then
								loggedUnder = index - landRow
							elseif loggedUnder ~= nil then
								worstRatio = math.max(worstRatio, logged / loggedBefore)
							end
						end
						expect(loggedUnder).never.toBeNil()
						table.insert(under, loggedUnder :: number)
						if kind == "slam" and seed == 0 then
							-- The land row and the next rows the PC read at 28: 0 at 60 Hz, 3 at 144 Hz.
							expect(loggedUnder).toBe(if fps == 60 then 1 else 4)
						end
						expect((landedAt :: number) - (landAt :: number)).toBeLessThanOrEqual(
							if fps == 60 then 0.15 else 0.08
						)
						expect(math.abs(run.rest - run.told)).toBeLessThanOrEqual(0.02)
						expect(run.farthest - run.told).toBeLessThanOrEqual(0)
					end
					expect(worstPace).toBeLessThanOrEqual(1e-4)
					if fps == 60 then
						expect(worstRatio).toBeLessThanOrEqual(0.75)
					end
					local text = {}
					for _, rows in under do
						table.insert(text, tostring(rows))
					end
					table.insert(
						report,
						("%s %d Hz: logged under %d first at land+%s, then each <= %.3f of the row before"):format(
							kind,
							fps,
							speed,
							table.concat(text, "/"),
							worstRatio
						)
					)
				end
			end
			print("[479(b)/480(a)] " .. table.concat(report, "; "))
		end
	)
end)

-- ------------------------------------------------------------------------------------------
-- AR 501(a)(b) and 502(b): the row before the log's landed mark (the PC on c78acd1)
-- ------------------------------------------------------------------------------------------

-- A Heartbeat row of item 439's server log as the PC reads it on c78acd1 (items 501 and 502): the
-- root's flat velocity read by a Heartbeat handler that runs before EnemyService's, and paced, the
-- WalkSpeed at the next PreSimulation (after every Heartbeat handler: what the next physics walks
-- with), beside what the service did on that Heartbeat.
type LogRow = {
	t: number, -- seconds from the launch
	dt: number, -- the Heartbeat's own dt
	along: number,
	left: number, -- the told stop less along
	velocity: number, -- the flat velocity the log reads, before the service's write
	paced: number, -- WalkSpeed after the service (the next PreSimulation)
	written: number, -- the flat velocity after the service (0 once halted)
	lands: number, -- Engine.land calls on this Heartbeat
	halts: number, -- Engine.halt calls on this Heartbeat
	reset: boolean, -- the mover's own speed written on this Heartbeat (moverUpdate, the AI tick)
}

-- The entry of `list` logged on the server frame at `time`.
local function loggedAt<T>(list: { { time: number, value: T } }, time: number): T?
	for _, entry in list do
		if math.abs(entry.time - time) < 1e-7 then
			return entry.value
		end
	end
	return nil
end

-- restRun with the PC's columns. Returns the rows from the launch's second row on, the land row's
-- index and the landed row's (the first row after land whose logged velocity reads 0), and the run.
local function logRun(wallZ: number?, settings: HumanoidSettings, speed: number): ({ LogRow }, number, number, Rest)
	local velocities: { { time: number, value: number } } = {}
	local halts: { { time: number, value: boolean } } = {}
	local resets: { { time: number, value: boolean } } = {}
	local realStep, realHalt, realSetWalkSpeed = EnemyService.step, engine.halt, engine.setWalkSpeed
	EnemyService.step = function(dt: number)
		for _, body in bodies do
			table.insert(velocities, { time = clock.t, value = flat(body.velocity).Magnitude })
		end
		realStep(dt)
	end
	engine.halt = function(model: Model, position: Vector3?)
		table.insert(halts, { time = clock.t, value = true })
		realHalt(model, position)
	end
	engine.setWalkSpeed = function(model: Model, walkSpeed: number)
		if walkSpeed == speed then
			table.insert(resets, { time = clock.t, value = true })
		end
		realSetWalkSpeed(model, walkSpeed)
	end
	table.clear(lands)
	local ok, result = pcall(restRun, wallZ, settings)
	EnemyService.step, engine.halt, engine.setWalkSpeed = realStep, realHalt, realSetWalkSpeed
	assert(ok, tostring(result))
	local run = result :: Rest
	local rows: { LogRow } = {}
	for index = 2, #run.rows do
		local row, before = run.rows[index], run.rows[index - 1]
		local time = run.launch + row.t
		local landCount, haltCount = 0, 0
		for _, entry in lands do
			if math.abs(entry.time - time) < 1e-7 then
				landCount += 1
			end
		end
		for _, entry in halts do
			if math.abs(entry.time - time) < 1e-7 then
				haltCount += 1
			end
		end
		table.insert(rows, {
			t = row.t,
			dt = row.t - before.t,
			along = row.along,
			left = run.told - row.along,
			velocity = loggedAt(velocities, time) :: number,
			paced = row.walkSpeed,
			written = row.speed,
			lands = landCount,
			halts = haltCount,
			reset = loggedAt(resets, time) == true,
		})
	end
	local landAt = landRows(run)
	assert(landAt ~= nil, "no landing")
	local landIndex: number? = nil
	local landedIndex: number? = nil
	for index, row in rows do
		if landIndex == nil and math.abs(row.t - landAt) < 1e-9 then
			landIndex = index
		elseif landIndex ~= nil and landedIndex == nil and row.velocity < 1e-6 then
			landedIndex = index
		end
	end
	assert(landIndex ~= nil and landedIndex ~= nil, "no land or landed row")
	return rows, landIndex, landedIndex, run
end

describe("A rush's landing ends on a halt row, a row before the log's landed mark (AR 501(a)(b), 502(b))", function()
	it(
		"lands every row with more than landSlackStuds left; the row before landed halts it and it stands from there",
		function()
			-- The PC on c78acd1, 9 slams and 12 open runs: every judged row matched min(28, left / (2 dt))
			-- within 2 % but the last, landed - 1, with 0.007 to 0.014 left. There paced read 28 (60 fps
			-- takes 1 and 2, lag 0.25) or the row before's value unchanged (0.721 / 0.766 / 0.670 at 60,
			-- 1.77 / 2.64 / 1.89 at 144; the open runs 0.97 to 4.46). That row is the service's halt: with
			-- landSlackStuds (0.02) or less left, landStep stops the body dead (Engine.halt: flat
			-- velocity 0, MoveTo where it stands) and writes no pace (D-525). The log reads the velocity
			-- before the service's Heartbeat handler, so it reads the halt's 0 a row later and marks
			-- landed there. WalkSpeed on the halt row is the last landing pace, or 28 when the 20 Hz AI
			-- tick ran on that Heartbeat: its moverUpdate, before the frame pass, sets the mover's own
			-- speed back, and on a landing row the land overwrites it within the same Heartbeat. A halted
			-- body walks to where it stands at either WalkSpeed, so it stands: the rest is the halt row's.
			-- The tolerant Humanoid (the PC's P2 probe), Studio's frames at 60 and 144 fps (dt within 6 %,
			-- physics in 1/240 s steps).
			local speed = AI.rushSpeed(BOAR.attacks[1])
			local slack = AI.movement.landSlackStuds
			local report = {}
			for _, fps in { 60, 144 } do
				local worstPace, worstRatio, worstHold = 0, 0, 0
				local leastLeft, mostLeft = math.huge, 0
				local reads28, readsKept = 0, 0
				for _, kind in { "slam", "open" } do
					for seed = 0, 7 do
						local rows, landIndex, landedIndex, run = logRun(
							if kind == "slam" then WALL_Z else nil,
							{ mode = "tolerant", fps = fps, jitter = if seed == 0 then 0 else 0.06, seed = seed },
							speed
						)
						-- Land to landed - 2: one land each, at that row's own left and dt, never a halt.
						local under: number? = nil
						for index = landIndex, landedIndex - 2 do
							local row = rows[index]
							expect(row.lands).toBe(1)
							expect(row.halts).toBe(0)
							expect(row.left > slack).toBe(true)
							local pace = math.min(speed, row.left / (AI.movement.landFrames * row.dt))
							worstPace = math.max(worstPace, math.abs(row.paced - pace))
							if under == nil and row.paced < speed - 1e-6 then
								under = index
							elseif under ~= nil then
								worstRatio = math.max(worstRatio, row.paced / rows[index - 1].paced)
							end
						end
						-- landed - 1: the halt row. No land, one halt, velocity 0, and no pace of its own.
						local halt, last = rows[landedIndex - 1], rows[landedIndex - 2]
						expect(halt.left <= slack).toBe(true)
						expect(halt.left > 0).toBe(true)
						expect(halt.lands).toBe(0)
						expect(halt.halts).toBe(1)
						expect(halt.written).toBe(0)
						expect(halt.velocity > 0).toBe(true)
						expect(halt.paced).toBe(if halt.reset then speed else last.paced)
						if halt.reset then
							reads28 += 1
						else
							readsKept += 1
						end
						leastLeft = math.min(leastLeft, halt.left)
						mostLeft = math.max(mostLeft, halt.left)
						-- The body stands from the halt row to 1 s after the stop: its rest is that row's.
						for index = landedIndex - 1, #rows do
							worstHold = math.max(worstHold, math.abs(rows[index].along - halt.along))
						end
						expect(math.abs(run.rest - halt.along)).toBeLessThanOrEqual(1e-6)
						expect(run.farthest - run.told).toBeLessThanOrEqual(0)
					end
				end
				expect(worstPace).toBeLessThanOrEqual(1e-4)
				expect(worstHold).toBeLessThanOrEqual(1e-6)
				if fps == 60 then
					expect(worstRatio).toBeLessThanOrEqual(0.75)
				end
				-- Both of the PC's readings come up: 28 after an AI tick, the last pace otherwise.
				expect(reads28 >= 1 and readsKept >= 1).toBe(true)
				table.insert(
					report,
					("%d Hz: land rows at the pace within %.1e, then each <= %.3f of the row before; halt row left %.4f-%.4f, paced 28 on %d takes and the last pace on %d; stands within %.1e"):format(
						fps,
						worstPace,
						worstRatio,
						leastLeft,
						mostLeft,
						reads28,
						readsKept,
						worstHold
					)
				)
			end
			print("[501(a)(b)/502(b)] " .. table.concat(report, "; "))
		end
	)
end)

-- ------------------------------------------------------------------------------------------
-- AS 525(g) and 526(g): the halt row in either order of the log's Heartbeat and the service's
-- ------------------------------------------------------------------------------------------

describe(
	"A rush's halt row is the first row with landSlackStuds or less left, whichever order the log's Heartbeat and the service's run in (AS 525(g), 526(g))",
	function()
		it("halts on that row; a log after the service reads landed there, a log before it a row later", function()
			-- The PC on 97cea9d (items 525 and 526): landed − 1 read left 0.025 to 0.049 as an ordinary
			-- paced row (0.74 to 1.42 at 60, 2.24 to 2.82 at 144), and the first row with 0.02 or less
			-- left already read velocity 0 (left 0.016 to 0.020), so the halt and landed fell on the same
			-- row; one 526 take had the halt on landed − 1. EnemyService connects its step to the server's
			-- Heartbeat (its heartbeat dependency); the PC's runtime log script connects its own, and the
			-- engine, not the code, sets which of the two runs first. The service halts on the first row
			-- from land with landSlackStuds or less left, and writes velocity 0 there: a log read after
			-- the service (`written`) marks landed on the halt row, a log read before it (`velocity`) a
			-- row later. Either way the halt row is the first row with left <= 0.02, the rows before it
			-- are paced landing rows, and the body stands from it. Tolerant Humanoid, Studio-like frames.
			local speed = AI.rushSpeed(BOAR.attacks[1])
			local slack = AI.movement.landSlackStuds
			local report = {}
			for _, fps in { 60, 144 } do
				for _, kind in { "slam", "open" } do
					local stat = {
						beforeLeft = { math.huge, -math.huge },
						beforePaced = { math.huge, -math.huge },
						haltLeft = { math.huge, -math.huge },
						landedA = { math.huge, -math.huge },
						landedB = { math.huge, -math.huge },
					}
					local function note(key: string, value: number)
						local span = (stat :: any)[key]
						span[1] = math.min(span[1], value)
						span[2] = math.max(span[2], value)
					end
					for seed = 0, 7 do
						local rows, landIndex, landedBefore = logRun(
							if kind == "slam" then WALL_Z else nil,
							{ mode = "tolerant", fps = fps, jitter = if seed == 0 then 0 else 0.06, seed = seed },
							speed
						)
						local halt: number? = nil
						for index = landIndex, #rows do
							if rows[index].left <= slack then
								halt = index
								break
							end
						end
						expect(halt).never.toBeNil()
						local h = halt :: number
						local landedAfter: number? = nil
						for index = landIndex, #rows do
							if rows[index].written < 1e-6 then
								landedAfter = index
								break
							end
						end
						expect(rows[h].halts).toBe(1)
						expect(rows[h].lands).toBe(0)
						expect(landedBefore).toBe(h + 1)
						expect(landedAfter).toBe(h)
						for index = landIndex, h - 1 do
							local row = rows[index]
							expect(row.lands).toBe(1)
							expect(row.left > slack).toBe(true)
							local pace = math.min(speed, row.left / (AI.movement.landFrames * row.dt))
							expect(math.abs(row.paced - pace)).toBeLessThanOrEqual(1e-4)
						end
						for index = h, #rows do
							expect(math.abs(rows[index].along - rows[h].along)).toBeLessThanOrEqual(1e-6)
						end
						local landT = rows[landIndex].t
						note("beforeLeft", rows[h - 1].left)
						note("beforePaced", rows[h - 1].paced)
						note("haltLeft", rows[h].left)
						note("landedA", rows[h + 1].t - landT)
						note("landedB", rows[h].t - landT)
					end
					table.insert(
						report,
						("%s %d Hz: halt row left %.4f-%.4f; the row before it left %.4f-%.4f paced %.3f-%.3f; land to landed %.3f-%.3f s read after the service (landed = halt row), %.3f-%.3f s read before it (halt row + 1)"):format(
							kind,
							fps,
							stat.haltLeft[1],
							stat.haltLeft[2],
							stat.beforeLeft[1],
							stat.beforeLeft[2],
							stat.beforePaced[1],
							stat.beforePaced[2],
							stat.landedB[1],
							stat.landedB[2],
							stat.landedA[1],
							stat.landedA[2]
						)
					)
				end
			end
			print("[525(g)/526(g)] " .. table.concat(report, "\n  "))
		end)
	end
)
