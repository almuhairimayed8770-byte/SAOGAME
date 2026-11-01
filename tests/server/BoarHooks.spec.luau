--!strict
--[[
	The Frenzy Boar's rests, holds and walls under DevCombat's Studio test hooks (D-333), after the
	1cf87aa PC run (M9/306(c), G4, 311(a), the FB hand-back). The DevCombat Script is loaded the way
	Studio runs it over DevEnemyHooks.spec's fake engine (velocity bodies on a 240 Hz physics step,
	walls as planes the root's box is pushed out of and the server's Blockcast sees, Model:PivotTo),
	plus `land`: a body carried onto a point by its own velocity over a given time and stopped dead
	there, the way a server-owned body moves without a CFrame write (which every client would show as
	a teleport of its replicated root). The last cases (AI 423(c), 422(d)) swap in the Humanoid the
	PC's server log shows (`humanoid`, "studio") and Studio's 60 and 144 Hz server frames, jittered.
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
-- never brakes short (it only ever runs on past its goal). `fps` and `jitter` set the server frames:
-- each lasts 1/fps × (1 + u), u uniform in [-jitter, jitter].
local humanoid = {
	mode = "ideal",
	arriveFrames = 1.7,
	brake = 0.672,
	acceleration = 1320,
	fps = 60,
	jitter = 0,
	random = Random.new(11),
}

type Plane = { point: Vector3, out: Vector3 }

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
	end,
	stop = function(model: Model)
		local body = bodies[model]
		body.goal = body.position
	end,
	halt = function(model: Model, position: Vector3?)
		local body = bodies[model]
		if position ~= nil then
			body.position = Vector3.new(position.X, body.position.Y, position.Z)
		end
		body.velocity = Vector3.zero
		body.goal = body.position
		body.written = true
		placeParts(model, body)
	end,
	-- Carries the body onto `position` (its height kept) by its velocity over `seconds`, then stops it
	-- dead there: no CFrame write. The studio Humanoid gets what the real engine.land does: the flat
	-- velocity that covers the way in `seconds`, that pace as its WalkSpeed, and MoveTo(position).
	land = function(model: Model, position: Vector3, seconds: number)
		local body = bodies[model]
		if humanoid.mode == "studio" then
			local offset = Vector3.new(position.X - body.position.X, 0, position.Z - body.position.Z)
			local pace = if seconds > 0 then offset / seconds else Vector3.zero
			body.velocity = pace
			body.walkSpeed = pace.Magnitude
			body.goal = Vector3.new(position.X, body.position.Y, position.Z)
			body.written = true
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

local function physics(untilT: number)
	for model, body in bodies do
		if humanoid.mode == "studio" then
			studioFrame(model, body, untilT)
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

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
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
local lands: { { model: Model, time: number, seconds: number } } = {}
local engineLand = engine.land
engine.land = function(model: Model, position: Vector3, seconds: number)
	table.insert(lands, { model = model, time = clock.t, seconds = seconds })
	engineLand(model, position, seconds)
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
