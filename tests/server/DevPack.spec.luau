--!strict
--[[
	Item 315 (D-332): a kobold pack never shoves. The Playground spawns its kobolds one to a spawn
	point (playground.luau packSize 1..1), so Studio never sees a natural kobold pack (the PC had 2
	kobolds, which walked home). DevCombat's "pack" hook (Studio only, D-333) spawns one the way the
	world does: `count` members of `enemy` through PlaygroundService.spawnCFrame (scattered around
	the floor point by playground.spawnScatterRadius, each clear of every living fighter by
	playground.spawnSpacing, at the rig's root height, facing `facing` with the spawn jitter) and
	EnemyService.spawn, at most dev.hooks.maxPackSize of them.

	The DevCombat Script is loaded the way Studio runs it over DevEnemyHooks.spec's fake engine.
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
local PlaygroundService = Harness.load("src/server/services/PlaygroundService")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local World = Harness.load("src/shared/data/world")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local AI = Harness.load("src/shared/data/ai")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Rigs = Harness.load("src/shared/data/rigs")
local Playground = Harness.load("src/shared/data/playground")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

local FILE = "src/server/dev/DevCombat.server.luau"
local HOOKS = Dev.hooks

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
	landing: { to: Vector3, untilT: number }?,
}

local clock = { t = 1000 }
local bodies: { [Model]: Body } = {}
local walls: { Plane } = {}
local delayed: { { at: number, fn: () -> () } } = {}
local devWorkspace: any = nil
local invokeDev: (command: string, args: any) -> any = nil :: any

-- Every AntiCheatService call the hooks make (the pack hook moves no player: none, D-143).
local antiCheatCalls: { string } = {}

-- Every payload the server sends meets its remote's schema.
local function record(remote: string, payload: any)
	local ok, problem = Net.validate(remote, payload)
	assert(ok, ("%s payload fails the schema: %s"):format(remote, tostring(problem)))
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
	-- Carries the body onto `position` (its height kept) by its velocity over `seconds`, then stops it
	-- dead there: no CFrame write.
	land = function(model: Model, position: Vector3, seconds: number)
		local body = bodies[model]
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

local function physics(untilT: number)
	for model, body in bodies do
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
	PlaygroundService.bind({
		now = now,
		entities = EntityService,
		enemies = EnemyService,
		waitForChild = function(): Instance?
			return nil
		end,
		random = Random.new(9),
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

describe("DevCombat's pack hook spawns a pack the way the world does (item 315, D-332, D-333)", function()
	it("spawns count kobolds round the point, each clear of every fighter by the world's spawn spacing", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, 200))
		local reply = invokeDev("pack", { enemy = "KoboldAxeman", position = { 0, 0, -30 }, count = 3, facing = 0 })
		expect(reply.error).toBeNil()
		expect(reply.ok).toBe(true)
		expect(#reply.ids).toBe(3)
		local def = Enemies.byId("KoboldAxeman")
		local rig = Rigs[def.skin]
		local rootSize = (rig.parts :: any)[rig.rootPart].size[2]
		local height = PlaygroundLayout.rootHeight(rig.hipHeight, rootSize, World.spawn.groundEpsilon)
		local spots: { Vector3 } = {}
		for _, id in reply.ids do
			local record = EntityService.get(id) :: any
			expect(record ~= nil and record.kind == "Enemy" and record.state ~= "Dead").toBe(true)
			local model = EnemyService.modelOf(id) :: Model
			-- (the CFrame: the engine stand-in sets a root by its CFrame)
			local position = (model.PrimaryPart :: BasePart).CFrame.Position
			expect(math.abs(position.Y - height)).toBeLessThanOrEqual(1e-3)
			local flatAway = Vector3.new(position.X, 0, position.Z + 30).Magnitude
			expect(
				flatAway
					<= Playground.spawnScatterRadius
						+ Playground.spawnSpacing.widenStuds * Playground.spawnSpacing.widenings
						+ 1e-3
			).toBe(true)
			table.insert(spots, Vector3.new(position.X, 0, position.Z))
		end
		expect(antiCheatCalls).toEqual({})
		for i = 1, #spots do
			for j = i + 1, #spots do
				expect((spots[i] - spots[j]).Magnitude >= Playground.spawnSpacing.minStuds - 1e-3).toBe(true)
			end
		end
	end)

	it("refuses more than dev.hooks.maxPackSize members, an unknown enemy and a point off the map", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, 200))
		local max: number = Dev.hooks.maxPackSize
		expect(typeof(max) == "number" and max >= 3).toBe(true)
		expect(invokeDev("pack", { enemy = "KoboldAxeman", position = { 0, 0, -30 }, count = max + 1 }).ok).never.toBe(
			true
		)
		expect(invokeDev("pack", { enemy = "NoSuchEnemy", position = { 0, 0, -30 }, count = 2 }).ok).never.toBe(true)
		local far = Dev.place.maxCoordinate + 1
		expect(invokeDev("pack", { enemy = "KoboldAxeman", position = { far, 0, 0 }, count = 2 }).ok).never.toBe(true)
		expect(#EnemyService.ids()).toBe(0)
	end)
end)
