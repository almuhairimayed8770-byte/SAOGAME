--!strict
--[[
	The Frenzy Boar's rests, holds and walls under DevCombat's Studio test hooks (D-333), after the
	1cf87aa PC run (M9/306(c), G4, 311(a), the FB hand-back). The DevCombat Script is loaded the way
	Studio runs it over DevEnemyHooks.spec's fake engine (velocity bodies on a 240 Hz physics step,
	walls as planes the root's box is pushed out of and the server's Blockcast sees, Model:PivotTo),
	plus `land`: a body carried onto a point by its own velocity over a given time and stopped dead
	there, the way a server-owned body moves without a CFrame write (which every client would show as
	a teleport of its replicated root).
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
local sent: { { time: number, remote: string, payload: any } } = {}
-- Every AntiCheatService call the hooks make (the enemy hooks move no player: none, D-143).
local antiCheatCalls: { string } = {}
local bodies: { [Model]: Body } = {}
local walls: { Plane } = {}
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
