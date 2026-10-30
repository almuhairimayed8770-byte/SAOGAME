--!strict
--[[
	The staged kobold stands off where the player rests (316(a), round D on the owner's PC, shot 2
	from 8 bearings): the server placed the shot's Kobold Axeman about 0.1 s before the player's
	body reached the spot, from where Studio's server last saw the root, so its Blocker stood on
	the body as it came to rest (bearing 0: the kobold at z -10.94 against the root at -10.37, the
	Blocker reaching to -9.71), and physics threw the client-owned body 0.6 to 4.4 studs and turned
	it 70 to 81 degrees in the first 0.2 s; frame 0 started 0.98 to 3.65 studs off the spot.

	Here: tests/server/DevStageSettle.spec.luau's harness (the real DevStage, EnemyService,
	CombatService and EntityService; the player's root on the server as a delayed copy of the
	client's body), staging art-horizontal (the kobold 3.5 studs ahead, held). At every lag Studio
	can show, the kobold stands its distance off where the body rests, and no blocker face it
	carries (RigBuilder.addBlocker: the Blocker and the HeldBlocker over its axe) reaches the
	player's root box there.
]]

local luau = require("@lune/luau")

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

local EntityService = Harness.load("src/server/services/EntityService")
local CombatService = Harness.load("src/server/services/CombatService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local DevStageLogic = Harness.load("src/server/dev/DevStageLogic")
local AI = Harness.load("src/shared/data/ai")
local Dev = Harness.load("src/shared/data/dev")
local Playground = Harness.load("src/shared/data/playground")
local World = Harness.load("src/shared/data/world")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

local CAPTURE = Dev.capture
local STAGE = CAPTURE.stage
local HIP = 2 -- the player's Humanoid.HipHeight in this world
local FPS = 60
local PHYSICS_STEP = 1 / 240
local SPRINT = 24 -- the walk's sprint (studs per second), as Studio measured it (step 16)
local SKID_STUDS = 0.36 -- the sprint stop's slide, over SKID_FRAMES frames (step 16)
local SKID_FRAMES = 3
-- The kobold shots: Horizontal (3.5 studs ahead, held) and the overhead (4.5 studs, let go; PC M8:
-- 2.96 studs on every frame, the kobold still turning to the player at r0).
local SHOTS = { "art-horizontal", "enemy-kobold-overhead" }

type Body = {
	position: Vector3,
	velocity: Vector3,
	goal: Vector3?,
	walkSpeed: number,
	offsets: { [BasePart]: CFrame },
	physT: number,
}

local clock = { t = 3000 }
local timers: { { at: number, fn: () -> () } } = {}
local bodies: { [Model]: Body } = {}

-- The player's client body and the server's copy of it (`lag` seconds behind).
type Client = {
	root: BasePart,
	position: Vector3,
	speed: number,
	direction: Vector3,
	stopAt: Vector3,
	skidLeft: number,
	history: { { t: number, position: Vector3 } },
	lag: number,
}
local client: Client? = nil

local function record(remote: string, payload: any)
	local ok, problem = Net.validate(remote, payload)
	assert(ok, ("%s payload fails the schema: %s"):format(remote, tostring(problem)))
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
	-- A flat, open field: nothing ahead of any walk or rush.
	worldAhead = function(model: Model, direction: Vector3, distance: number, offset: Vector3?, walk: boolean?)
		return EnemyService.worldAhead(model, direction, distance, function()
			return nil, nil
		end, offset, walk)
	end,
}

-- Enemy bodies: toward their goals at their walk speed, a Humanoid's quick acceleration.
local function physics(untilT: number)
	for model, body in bodies do
		while body.physT + PHYSICS_STEP <= untilT + 1e-9 do
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
			local most = 560 * PHYSICS_STEP
			if change.Magnitude > most then
				change = change.Unit * most
			end
			body.velocity += change
			body.position += body.velocity * PHYSICS_STEP
		end
		placeParts(model, body)
	end
end

-- Where the client's body stood at `t` (its history, linearly between samples).
local function clientAt(state: Client, t: number): Vector3
	local history = state.history
	if t <= history[1].t then
		return history[1].position
	end
	for index = #history, 1, -1 do
		local sample = history[index]
		if sample.t <= t then
			local after = history[index + 1]
			if after == nil then
				return sample.position
			end
			local u = (t - sample.t) / (after.t - sample.t)
			return sample.position:Lerp(after.position, u)
		end
	end
	return history[#history].position
end

-- The player's client body sprints along the facing to the spot and skids to rest on it; the
-- server's root is the body `lag` seconds ago.
local function stepClient(dt: number)
	local state = client
	if state == nil then
		return
	end
	if state.speed > 0 then
		local left = (state.stopAt - state.position):Dot(state.direction)
		if state.skidLeft <= 0 and left <= SKID_STUDS then
			state.skidLeft = SKID_FRAMES
		end
		if state.skidLeft > 0 then
			local step = math.max(0, left) / state.skidLeft
			state.position += state.direction * step
			state.skidLeft -= 1
			state.speed = if state.skidLeft <= 0 then 0 else step / dt
		else
			state.position += state.direction * math.min(state.speed * dt, left - SKID_STUDS)
		end
	end
	table.insert(state.history, { t = clock.t, position = state.position })
	local seen = clientAt(state, clock.t - state.lag)
	local root = state.root
	root.CFrame = CFrame.lookAt(seen, seen + state.direction)
	root.Position = seen
end

local function runTimers()
	local index = 1
	while index <= #timers do
		local timer = timers[index]
		if timer.at <= clock.t + 1e-9 then
			table.remove(timers, index)
			timer.fn()
		else
			index += 1
		end
	end
end

local function serverFrame()
	local dt = 1 / FPS
	clock.t += dt
	stepClient(dt)
	physics(clock.t)
	EnemyService.step(dt)
	EntityService.tick(dt)
	CombatService.tick()
	runTimers()
end

local function fresh()
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	clock.t = 3000
	bodies = {}
	client = nil
	table.clear(timers)
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
		random = Random.new(2),
		spawnTask = function(fn)
			fn()
		end,
	} :: any)
end

-- DevStage.server.luau as Studio runs it: a task.wait yields while the server's frames run.
local function loadStage(): any
	local created: { any } = {}
	local env = Harness.environment()
	env.script = Harness.node("src/server/dev/DevStage")
	env.require = function(node: any): any
		if node.Name == "EnemyService" then
			return EnemyService
		elseif node.Name == "EntityService" then
			return EntityService
		end
		return Harness.loadModule(node)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			if name == "RunService" then
				return {
					IsStudio = function(): boolean
						return true
					end,
				}
			elseif name == "Players" then
				return { PlayerRemoving = { Connect = function() end } }
			end
			return Harness.game():GetService(name)
		end,
	}
	env.workspace = {
		GetAttribute = function(_self: any, name: string): any
			return name == Dev.attributes.capture
		end,
		-- Every reply carries the server's clock as the ask arrived (EF).
		GetServerTimeNow = function(_self: any): number
			return clock.t
		end,
	}
	env.Instance = {
		new = function(className: string): any
			local instance: any = { ClassName = className }
			table.insert(created, instance)
			return instance
		end,
	}
	env.task = {
		wait = function(seconds: number?): number
			local from = clock.t
			repeat
				serverFrame()
			until clock.t - from >= (seconds or 0) - 1e-9
			return clock.t - from
		end,
		delay = function(seconds: number, fn: () -> ())
			table.insert(timers, { at = clock.t + seconds, fn = fn })
		end,
	}
	env.os = {
		clock = function(): number
			return clock.t
		end,
	}
	luau.load(
		Harness.readFile("src/server/dev/DevStage.server.luau"),
		{ debugName = "DevStage", environment = env :: any }
	)()
	for _, instance in created do
		if instance.ClassName == "RemoteFunction" then
			return instance
		end
	end
	error("DevStage made no RemoteFunction")
end

-- The player sprinting in along the last leg of the walk's route (the approach along the spot's
-- facing), `lag` seconds of replication between its body and the server's root.
local function spawnPlayer(speed: number, lag: number): number
	local area = STAGE.area
	local y = area.position[2] + HIP + 1 + World.spawn.groundEpsilon
	local lx, lz = DevStageLogic.look(area.facing)
	local direction = Vector3.new(lx, 0, lz)
	local spot = Vector3.new(area.position[1], y, area.position[3])
	local start = spot - direction * (STAGE.approachStuds + 4)
	local model = Instance.new("Model")
	model.Name = "Trialist"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.lookAt(start, start + direction)
	root.Position = start
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = HIP
	humanoid.Parent = model
	model.Parent = Instance.new("Folder")
	CollisionGroups.assign(model, AI.collision.players)
	client = {
		root = root,
		position = start,
		speed = speed,
		direction = direction,
		stopAt = spot,
		skidLeft = 0,
		history = { { t = clock.t, position = start } },
		lag = lag,
	}
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 902 }
	return EntityService.registerPlayer(player :: any, model, Playground.loadout)
end

-- The flat corners of a part's box (or of a box of `size` at `cframe`).
local function corners(cframe: CFrame, size: Vector3): { Vector3 }
	local list = {}
	for _, s in { { -1, -1 }, { -1, 1 }, { 1, 1 }, { 1, -1 } } do
		local at = cframe:PointToWorldSpace(Vector3.new(s[1] * size.X / 2, 0, s[2] * size.Z / 2))
		table.insert(list, Vector3.new(at.X, 0, at.Z))
	end
	return list
end

-- The flat gap between two convex quads (separating axes): negative is how deep they overlap.
local function gap(a: { Vector3 }, b: { Vector3 }): number
	local best = -math.huge
	for _, polygon in { a, b } do
		for index = 1, 4 do
			local p, q = polygon[index], polygon[index % 4 + 1]
			local normal = Vector3.new(-(q.Z - p.Z), 0, q.X - p.X).Unit
			local aMin, aMax, bMin, bMax = math.huge, -math.huge, math.huge, -math.huge
			for _, v in a do
				aMin, aMax = math.min(aMin, v:Dot(normal)), math.max(aMax, v:Dot(normal))
			end
			for _, v in b do
				bMin, bMax = math.min(bMin, v:Dot(normal)), math.max(bMax, v:Dot(normal))
			end
			best = math.max(best, math.max(bMin - aMax, aMin - bMax))
		end
	end
	return best
end

type Staging = { staged: boolean, distance: number, nearest: number, face: string, turn: number }

-- Stages the shot the frame the client's body is at rest, as the panel asks: how far (flat) the
-- kobold stands from where the body rests, and the nearest of its blocker faces to the root box.
local function stage(shotId: string, speed: number, lag: number): Staging
	fresh()
	local remote = loadStage()
	local playerId = spawnPlayer(speed, lag)
	local who = EntityService.get(playerId).player
	local state = client :: Client
	local guard = 0
	while state.speed > CAPTURE.walk.restSpeed and guard < 10 * FPS do
		serverFrame()
		guard += 1
	end
	serverFrame() -- the request reaches the server a frame later
	local staged = remote.OnServerInvoke(who, "stage", shotId)
	if staged.ok ~= true then
		return { staged = false, distance = 0, nearest = math.huge, face = "", turn = 180 }
	end
	local model = EnemyService.modelOf(staged.ids[1]) :: Model
	local rest = state.position
	local distance = ((bodies[model].position - rest) * Vector3.new(1, 0, 1)).Magnitude
	local body = corners(CFrame.lookAt(rest, rest + state.direction), state.root.Size)
	local nearest, face = math.huge, ""
	for _, part in model:GetChildren() do
		if
			part:IsA("BasePart") and (part.Name == RigBuilder.BLOCKER_NAME or part.Name == RigBuilder.HELD_BLOCKER_NAME)
		then
			local between = gap(body, corners(part.CFrame, part.Size))
			if between < nearest then
				nearest, face = between, part.Name
			end
		end
	end
	-- How far the kobold's facing is off the line to where the body rests (it turns to it if not).
	local toRest = ((rest - bodies[model].position) * Vector3.new(1, 0, 1)).Unit
	local turn = math.deg(math.acos(math.clamp(yawOf(model):Dot(toRest), -1, 1)))
	return { staged = true, distance = distance, nearest = nearest, face = face, turn = turn }
end

local function shotDistance(shotId: string): number
	for _, shot in CAPTURE.shots do
		if shot.id == shotId then
			return shot.stage.enemies[1].distance
		end
	end
	error("no shot " .. shotId)
end

describe("A staged kobold stands off where the player rests, clear of the body (316(a), M8)", function()
	-- { the walk's speed on its last leg, the replication's lag }, as tests/server/DevStageSettle.
	for _, shotId in SHOTS do
		for _, case in { { SPRINT, 0 }, { SPRINT, 0.1 }, { 16, 0.2 }, { SPRINT, 0.3 } } do
			local speed, lag = case[1], case[2]
			local name =
				"%s at %g studs/s with %g s of replication: the kobold %g studs off the rest, facing it, no blocker on the body"
			it(name:format(shotId, speed, lag, shotDistance(shotId)), function()
				local result = stage(shotId, speed, lag)
				print(
					("[316(a) kobold] %s %g studs/s, %g s: staged %s, %.2f studs from the rest, %.1f deg off facing it, nearest face %s %.2f studs off the root box"):format(
						shotId,
						speed,
						lag,
						tostring(result.staged),
						result.distance,
						result.turn,
						result.face,
						result.nearest
					)
				)
				expect(result.staged).toBe(true)
				expect(math.abs(result.distance - shotDistance(shotId)) <= 0.25).toBe(true)
				expect(result.turn).toBeLessThan(2)
				expect(result.nearest).toBeGreaterThan(0)
			end)
		end
	end
end)
