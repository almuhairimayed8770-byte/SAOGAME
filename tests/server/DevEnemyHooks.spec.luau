--!strict
--[[
	DevCombat's Studio test hooks (D-333) over the real game: the DevCombat Script loaded the way
	Studio runs it (its requires go to the same EnemyService, Charger, EntityService and
	CombatService modules this spec drives; only AntiCheatService is a recorder, and nothing may
	call it), over the WallStop.spec fake engine (velocity bodies on a 240 Hz physics step, walls as
	planes that push the root's box out and that the server's Blockcast sees) plus Model:PivotTo.
	Every task.wait in a command is one 60 Hz server frame, and the dev parts "part" makes stand in
	the fake engine as walls (the plane of the part's thin face toward the body).

	The point: a body the hooks place, walk or charge follows the server's own rules exactly as an
	undisturbed one does: a charge runs the same line and lands the same hit on the same player and
	no other, slams a wall at the same distance and rests out of it, and placed or walked bodies keep
	the same room to each other on every face (D-332).
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
local GAP = AI.spacing.gapStuds
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

type Plane = { point: Vector3, out: Vector3 }

type Body = {
	position: Vector3,
	velocity: Vector3,
	goal: Vector3?,
	walkSpeed: number,
	offsets: { [BasePart]: CFrame },
	physT: number,
}

local clock = { t = 1000 }
local sent: { { time: number, remote: string, payload: any } } = {}
local bodies: { [Model]: Body } = {}
local walls: { Plane } = {}
local delayed: { { at: number, fn: () -> () } } = {}
local devWorkspace: any = nil
local antiCheatCalls: { string } = {}
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

-- The hits the server confirmed on `targetId` (HitConfirmed: what every client is told).
local function hitsOn(targetId: number): { any }
	local list = {}
	for _, entry in sent do
		if entry.remote == "HitConfirmed" and entry.payload.targetId == targetId then
			table.insert(list, entry.payload)
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
		placeParts(model, body)
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

local function physics(untilT: number)
	for model, body in bodies do
		local root = model.PrimaryPart :: BasePart
		while body.physT + PHYSICS_STEP <= untilT + FLOOR_GAP do
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

-- One 60 Hz server frame: the parts due land, then physics, the AI, the entities, the combat tick.
local FRAME = 1 / 60
local function serverFrame()
	clock.t += FRAME
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
	EnemyService.step(FRAME)
	EntityService.tick(FRAME)
	CombatService.tick()
end

local function frames(seconds: number)
	for _ = 1, math.round(seconds / FRAME) do
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
			serverFrame()
			return FRAME
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

local function movePlayer(model: Model, position: Vector3)
	(model.PrimaryPart :: BasePart).CFrame = CFrame.new(position)
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- ------------------------------------------------------------------------------------------
-- The faces judge (PackFaces.spec's): the flat boxes of the blockers a model really has
-- ------------------------------------------------------------------------------------------

local function facesOf(model: Model): { { Vector3 } }
	local faces: { { Vector3 } } = {}
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.CollisionGroup == AI.collision.blockers then
			local half = part.Size / 2
			local corners: { Vector3 } = {}
			for _, sign in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
				local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * sign[1], 0, half.Z * sign[2]))
				table.insert(corners, Vector3.new(corner.X, 0, corner.Z))
			end
			table.insert(faces, corners)
		end
	end
	return faces
end

local function separation(a: { Vector3 }, b: { Vector3 }): number
	local best = -math.huge
	for _, polygon in { a, b } do
		for index = 1, #polygon do
			local edge = polygon[index % #polygon + 1] - polygon[index]
			local axis = Vector3.new(-edge.Z, 0, edge.X).Unit
			local aMin, aMax, bMin, bMax = math.huge, -math.huge, math.huge, -math.huge
			for _, point in a do
				local d = point:Dot(axis)
				aMin, aMax = math.min(aMin, d), math.max(aMax, d)
			end
			for _, point in b do
				local d = point:Dot(axis)
				bMin, bMax = math.min(bMin, d), math.max(bMax, d)
			end
			best = math.max(best, bMin - aMax, aMin - bMax)
		end
	end
	return best
end

local function facesApart(a: Model, b: Model): number
	local least = math.huge
	for _, first in facesOf(a) do
		for _, second in facesOf(b) do
			least = math.min(least, separation(first, second))
		end
	end
	return least
end

-- ------------------------------------------------------------------------------------------
-- A rush, left to the boar or started by "charge"
-- ------------------------------------------------------------------------------------------

type Rush = {
	origin: Vector3,
	direction: Vector3,
	hits: { any }, -- HitConfirmed on the player down the line
	besideHits: number, -- HitConfirmed on the player beside the line
	ends: { { reason: string, distance: number } },
	rest: number, -- how far down the line the root stands at the end
	deepest: number, -- the body's deepest into a wall over the whole run
	reply: any?, -- the "charge" reply (dev runs)
}

-- The line is the -Z axis from the floor point (0, 0, 0): the player stands `playerAlong` studs
-- down it, another 6 studs beside it at 8 down; a dev wall (a "part") faces the boar `wall` studs
-- down it, if given. `dev`: the boar is held facing +X (off the line) by "enemy" and "charge" aims it
-- at the player; otherwise it is spawned facing down the line and left to start its own rush.
local function rush(dev: boolean, playerAlong: number, wall: number?, seconds: number): Rush
	fresh()
	local direction = Vector3.new(0, 0, -1)
	local boarId: number
	local target, targetId = spawnPlayer(Vector3.new(0, 3, -12))
	local beside, besideId = spawnPlayer(Vector3.new(30, 3, -30))
	if wall ~= nil then
		local reply = invokeDev("part", { size = { 16, 8, 1 }, position = { 0, 4, -(wall + 0.5) }, name = "Wall" })
		assert(reply.ok, reply.error)
	end
	local reply: any = nil
	if dev then
		boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(40, BOAR_HEIGHT, 40))
		local placed = invokeDev("enemy", { entityId = boarId, position = { 0, 0, 0 }, facing = -90, hold = true })
		assert(placed.ok, placed.error)
		frames(0.5) -- held: it never sees the players
		assert(#sentOf("Telegraph", boarId) == 0, "a held boar telegraphed")
		movePlayer(target, Vector3.new(0, 3, -playerAlong))
		movePlayer(beside, Vector3.new(6, 3, -8))
		reply = invokeDev("charge", { entityId = boarId, toward = { 0, 0, -playerAlong } })
		assert(reply.ok, reply.error)
	else
		boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, BOAR_HEIGHT, 0))
		local guard = 0
		while #sentOf("Telegraph", boarId) == 0 and guard < 600 do
			serverFrame()
			guard += 1
		end
		assert(#sentOf("Telegraph", boarId) > 0, "the boar never telegraphed")
		movePlayer(target, Vector3.new(0, 3, -playerAlong))
		movePlayer(beside, Vector3.new(6, 3, -8))
	end
	local model = EnemyService.modelOf(boarId) :: Model
	local deepest = 0
	local guard = 0
	while #sentOf("RushStarted", boarId) == 0 and guard < 600 do
		serverFrame()
		guard += 1
	end
	local started = sentOf("RushStarted", boarId)[1]
	assert(started ~= nil, "no RushStarted")
	local launch = started.time
	while clock.t - launch < seconds do
		serverFrame()
		deepest = math.max(deepest, depthInWalls(model))
	end
	local origin = Vector3.new(started.payload.origin[1], started.payload.origin[2], started.payload.origin[3])
	local ends = {}
	for _, entry in sentOf("RushEnded", boarId) do
		table.insert(ends, { reason = entry.payload.reason, distance = entry.payload.distance })
	end
	return {
		origin = origin,
		direction = Vector3.new(
			started.payload.direction[1],
			started.payload.direction[2],
			started.payload.direction[3]
		),
		hits = hitsOn(targetId),
		besideHits = #hitsOn(besideId),
		ends = ends,
		rest = (bodies[model].position - origin):Dot(direction),
		deepest = deepest,
		reply = reply,
	}
end

describe("DevCombat Studio test hooks over the real EnemyService (D-333)", function()
	it("enemy stands a boar on the floor point at its root height and facing, Idle, held if asked", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, 200)) -- awake, never aggroed
		local id = EnemyService.spawn("FrenzyBoar", CFrame.new(20, BOAR_HEIGHT, 20))
		local model = EnemyService.modelOf(id) :: Model
		frames(0.5)
		local reply = invokeDev("enemy", { entityId = id, position = { -6, 0, 10 }, facing = 135, hold = true })
		expect(reply.ok).toBe(true)
		expect(reply.name).toBe(BOAR.name)
		expect(reply.held).toBe(true)
		local at = Vector3.new(-6, BOAR_HEIGHT, 10)
		expect((bodies[model].position - at).Magnitude).toBeLessThan(1e-4)
		local look = yawOf(model)
		expect(look:Dot(Vector3.new(-math.sin(math.rad(135)), 0, -math.cos(math.rad(135))))).toBeCloseTo(1, 1e-4)
		expect((EnemyService.brainOf(id) :: any):getPhase()).toBe("Idle")
		expect(EnemyService.isHeld(id)).toBe(true)
		-- Held, it stands there, whoever comes close.
		spawnPlayer(Vector3.new(-6, 3, 0))
		frames(3)
		expect((bodies[model].position - at).Magnitude).toBeLessThan(1e-3)
		expect(#sentOf("Telegraph", id)).toBe(0)
		-- Let go (no hold), its brain takes the player as any boar does: it lines up and charges.
		local free = invokeDev("enemy", { entityId = id, position = { -6, 0, 16 }, facing = 0 })
		expect(free.ok).toBe(true)
		expect(free.held).toBe(false)
		frames(4)
		expect(#sentOf("Telegraph", id)).toBeGreaterThan(0)
		-- No player was moved and the anti-cheat was never asked.
		expect(antiCheatCalls).toEqual({})
	end)

	it("enemy on a boar mid-rush ends the rush once (Stopped) and stands it at the point", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, -12))
		local id = EnemyService.spawn("FrenzyBoar", CFrame.new(0, BOAR_HEIGHT, 0))
		local model = EnemyService.modelOf(id) :: Model
		local guard = 0
		while #sentOf("RushStarted", id) == 0 and guard < 600 do
			serverFrame()
			guard += 1
		end
		frames(0.1)
		local reply = invokeDev("enemy", { entityId = id, position = { 20, 0, 20 }, facing = 0, hold = true })
		expect(reply.ok).toBe(true)
		local ends = sentOf("RushEnded", id)
		expect(#ends).toBe(1)
		expect(ends[1].payload.reason).toBe("Stopped")
		frames(1)
		expect((bodies[model].position - Vector3.new(20, BOAR_HEIGHT, 20)).Magnitude).toBeLessThan(1e-3)
		expect(#sentOf("RushEnded", id)).toBe(1)
		expect((model.PrimaryPart :: BasePart).CollisionGroup).toBe(AI.collision.enemies)
	end)

	it("a charge runs the same line and lands the same hit as the boar's own rush, on nobody beside it", function()
		local natural = rush(false, 10, nil, 1.6)
		local charged = rush(true, 10, nil, 1.6)
		for _, run in { natural, charged } do
			expect(run.direction:Dot(Vector3.new(0, 0, -1))).toBeCloseTo(1, 1e-4)
			expect(#run.hits).toBe(1)
			expect(run.besideHits).toBe(0)
		end
		expect((flat(charged.origin) - flat(natural.origin)).Magnitude).toBeLessThan(0.05)
		expect(charged.hits[1].damage).toBe(natural.hits[1].damage)
		expect(charged.hits[1].crit).toBe(natural.hits[1].crit)
		expect(charged.hits[1].attackerId).never.toBeNil()
		expect(charged.rest).toBeCloseTo(natural.rest, 0.05)
		-- The reply tells the launch and the run's end as the clients were told it.
		local reply = charged.reply
		expect(reply.complete).toBe(true)
		expect(reply.attackId).toBe(BOAR.attacks[1].id)
		expect(reply.launched.direction).toEqual({ 0, 0, -1 })
		expect(reply.phase).never.toBe("Strike")
		expect(reply.seconds).toBeLessThan(HOOKS.chargeTimeoutSeconds)
		expect(antiCheatCalls).toEqual({})
	end)

	it("a charge into a dev wall slams it where the boar's own rush does, and rests out of it", function()
		local natural = rush(false, 12, 8, 1.2)
		local charged = rush(true, 12, 8, 1.2)
		local function slamOf(run: Rush): { reason: string, distance: number }?
			for _, ended in run.ends do
				if ended.reason == "Wall" then
					return ended
				end
			end
			return nil
		end
		local naturalSlam, chargedSlam = slamOf(natural), slamOf(charged)
		expect(naturalSlam).never.toBeNil()
		expect(chargedSlam).never.toBeNil()
		local wallAt = (chargedSlam :: any).distance
		expect(wallAt).toBeCloseTo((naturalSlam :: any).distance, 0.02)
		expect(charged.rest).toBeCloseTo(wallAt, 0.01)
		expect(charged.deepest).toBeLessThanOrEqual(0.15)
		expect(natural.deepest).toBeLessThanOrEqual(0.15)
		-- Nobody behind the wall is hit.
		expect(#charged.hits).toBe(0)
		-- The reply's stops are the RushEnded ones, in order, with the slam first.
		local stops = charged.reply.stops
		expect(stops[1].reason).toBe("Wall")
		expect(stops[1].distance).toBeCloseTo(wallAt, 0.006)
		expect(antiCheatCalls).toEqual({})
	end)

	it("a part that lands mid-rush stops the run at its face, never through it", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, -30))
		local id = EnemyService.spawn("FrenzyBoar", CFrame.new(40, BOAR_HEIGHT, 40))
		local model = EnemyService.modelOf(id) :: Model
		expect(invokeDev("enemy", { entityId = id, position = { 0, 0, 0 }, facing = 0, hold = true }).ok).toBe(true)
		local windUp = BOAR.attacks[1].windUp
		local late = invokeDev("part", { size = { 16, 8, 1 }, position = { 0, 4, -14.5 }, after = windUp + 0.15 })
		expect(late.ok).toBe(true)
		local reply = invokeDev("charge", { entityId = id, toward = { 0, 0, -30 } })
		expect(reply.ok).toBe(true)
		expect(#reply.stops).toBeGreaterThan(0)
		local first = reply.stops[1]
		expect(first.reason == "Wall" or first.reason == "Jammed").toBe(true)
		expect(first.after).toBeGreaterThan(0.15)
		frames(1)
		expect(depthInWalls(model)).toBeLessThanOrEqual(0.15)
		expect(-bodies[model].position.Z).toBeLessThan(14)
	end)

	it("a body placed inside another steps out face to face as an overlapping spawn does (D-332)", function()
		local function settle(dev: boolean): number
			fresh()
			spawnPlayer(Vector3.new(0, 3, 200)) -- awake, never aggroed
			local a = EnemyService.spawn("FrenzyBoar", CFrame.new(0, BOAR_HEIGHT, 0))
			local b: number
			if dev then
				b = EnemyService.spawn("FrenzyBoar", CFrame.new(30, BOAR_HEIGHT, 0))
				frames(0.2)
				local reply = invokeDev("enemy", { entityId = b, position = { 0.4, 0, 0.3 }, facing = 70 })
				assert(reply.ok, reply.error)
			else
				b = EnemyService.spawn(
					"FrenzyBoar",
					CFrame.new(0.4, BOAR_HEIGHT, 0.3) * CFrame.Angles(0, math.rad(70), 0)
				)
			end
			local first, second = EnemyService.modelOf(a) :: Model, EnemyService.modelOf(b) :: Model
			assert(facesApart(first, second) < 0, "the two did not start inside each other")
			frames(5)
			return facesApart(first, second)
		end
		local natural, placed = settle(false), settle(true)
		expect(natural).toBeGreaterThanOrEqual(GAP - 1e-3)
		expect(placed).toBeGreaterThanOrEqual(GAP - 1e-3)
	end)

	it("walk takes a boar to the point at its own pace, keeps its room to another, and holds it there", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, 200)) -- awake, never aggroed
		local a = EnemyService.spawn("FrenzyBoar", CFrame.new(0, BOAR_HEIGHT, 0))
		local b = EnemyService.spawn("FrenzyBoar", CFrame.new(0, BOAR_HEIGHT, -24))
		local walker, other = EnemyService.modelOf(a) :: Model, EnemyService.modelOf(b) :: Model
		frames(0.5)
		expect(invokeDev("enemy", { entityId = b, position = { 0, 0, -24 }, hold = true }).ok).toBe(true)
		-- A plain walk first: there and held.
		local reply = invokeDev("walk", { entityId = a, toward = { 12, 0, 0 }, hold = true, wait = true })
		expect(reply.ok).toBe(true)
		expect(reply.over).toBe(true)
		expect(reply.arrived).toBe(true)
		expect(reply.held).toBe(true)
		expect(reply.took).toBeGreaterThanOrEqual((12 - HOOKS.arriveStuds) / BOAR.moveSpeed)
		expect(reply.took).toBeLessThan(12 / BOAR.moveSpeed + 2)
		expect(flat(bodies[walker].position - Vector3.new(12, 0, 0)).Magnitude).toBeLessThanOrEqual(HOOKS.arriveStuds)
		expect(EnemyService.isHeld(a)).toBe(true)
		frames(0.2) -- held where it arrived: the brake of a body stopped at walking speed
		local stood = bodies[walker].position
		frames(2)
		expect((bodies[walker].position - stood).Magnitude).toBeLessThan(1e-3)
		-- Then straight into the other boar: it stops at the room the AI keeps, never inside it.
		local least = math.huge
		local into = invokeDev("walk", { entityId = a, toward = { 0, 0, -24 }, wait = false })
		expect(into.ok).toBe(true)
		for _ = 1, 60 * 6 do
			serverFrame()
			least = math.min(least, facesApart(walker, other))
		end
		local tickWalk = BOAR.moveSpeed * AI.tickSeconds()
		expect(least).toBeGreaterThan(-tickWalk)
		expect(facesApart(walker, other)).toBeGreaterThanOrEqual(GAP - 1e-3)
		-- Its point is inside the other's room, so it stands at the room's edge until the walk's
		-- time is up, and the brain has it from there.
		expect(EnemyService.walking(a)).toBe(true)
		frames(HOOKS.walkTimeoutSeconds - 6 + 0.5)
		expect(EnemyService.walking(a)).toBe(false)
		expect(facesApart(walker, other)).toBeGreaterThanOrEqual(GAP - 1e-3)
		expect(antiCheatCalls).toEqual({})
	end)

	it("charge refuses a non-Charger and a staggered boar; walk refuses a staggered one", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, 200))
		local kobold = EnemyService.spawn("KoboldAxeman", CFrame.new(10, 3.25, 0))
		local boar = EnemyService.spawn("FrenzyBoar", CFrame.new(-10, BOAR_HEIGHT, 0))
		frames(0.5)
		local refused = invokeDev("charge", { entityId = kobold, toward = { 10, 0, -20 } })
		expect(refused.ok).toBe(false)
		expect(refused.error:find("Charger", 1, true)).never.toBeNil()
		EntityService.setState(boar, "Stagger", 1.0, "Front")
		frames(0.1)
		local dazed = invokeDev("charge", { entityId = boar, toward = { -10, 0, -20 } })
		expect(dazed.ok).toBe(false)
		expect(dazed.error:find("Interrupted", 1, true)).never.toBeNil()
		expect(invokeDev("walk", { entityId = boar, toward = { -10, 0, -20 } }).ok).toBe(false)
		expect(#sentOf("Telegraph", boar)).toBe(0)
		expect(#sentOf("Telegraph", kobold)).toBe(0)
		-- Once it recovers, the charge goes.
		frames(1.5)
		expect(invokeDev("charge", { entityId = boar, toward = { -10, 0, -20 } }).ok).toBe(true)
	end)
end)
