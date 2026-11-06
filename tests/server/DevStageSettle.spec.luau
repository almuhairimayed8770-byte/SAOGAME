--!strict
--[[
	A staged shot puts its enemies where the player comes to rest, not where the server last saw
	them on the way in (item 321, step 19 on cebade4: the boar's Charge telegraph came at +4.12 s,
	not about 0.3 s, and its hit fell on the take's end).

	The capture panel's walk runs its last approachStuds along the shot's facing at the sprint and
	asks for the staging the frame the body is at rest on the client. The server reads the player's
	root as Studio replicates a client-owned character: a copy `lag` seconds behind. Read at once,
	that copy still stands a sprint's lag short of the spot, so the boar (12 studs ahead along the
	facing) stood under 10 studs from where the player rests: the Charger's circle-out (ai.luau
	minChargeDistance) ran first and its only charge landed on the take's last frame.

	Here: the real DevStage, EnemyService, CombatService and EntityService, the boar on a 240 Hz
	velocity body under 60 Hz server frames, and the player's root on the server as a delayed copy of
	the client's body. Every lag Studio can show (none to a quarter second) stages the boar at the
	shot's distance from where the player rests, and its first charge crouches on the take's first
	beats and meets the player inside the take.
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
local SHOT_ID = "enemy-boar-charge"

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
local sent: { { time: number, remote: string, payload: any } } = {}
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
	table.insert(sent, { time = clock.t, remote = remote, payload = payload })
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
	worldAhead = function(model: Model, direction: Vector3, distance: number, offset: Vector3?, walk: Vector3?)
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
	sent = {}
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

type Take = {
	staged: boolean,
	distance: number, -- flat, from the boar as staged to where the player's body rests
	crouchAt: number?, -- the boar's first WindUp, seconds after the "go"
	hitAt: number?, -- its first hit on the player, seconds after the "go"
}

local function runTake(speed: number, lag: number): Take
	fresh()
	local remote = loadStage()
	local playerId = spawnPlayer(speed, lag)
	local who = EntityService.get(playerId).player
	local state = client :: Client
	-- The panel asks the frame the client's body is at rest (capture.walk.restSpeed).
	local guard = 0
	while state.speed > CAPTURE.walk.restSpeed and guard < 10 * FPS do
		serverFrame()
		guard += 1
	end
	serverFrame() -- the request reaches the server a frame later
	local staged = remote.OnServerInvoke(who, "stage", SHOT_ID)
	if staged.ok ~= true then
		return { staged = false, distance = 0, crouchAt = nil, hitAt = nil }
	end
	local boarId = staged.ids[1]
	local boarModel = EnemyService.modelOf(boarId) :: Model
	local boarAt = bodies[boarModel].position
	local rest = state.position
	local distance = ((boarAt - rest) * Vector3.new(1, 0, 1)).Magnitude
	for _ = 1, math.ceil(CAPTURE.countdownSeconds * FPS) do
		serverFrame()
	end
	clock.t += 1 / STAGE.requestsPerSecond -- the server's own request rate never refuses the "go"
	local go = remote.OnServerInvoke(who, "go")
	assert(go.ok == true, "go refused: " .. tostring(go.error))
	local t0 = clock.t
	local crouchAt: number? = nil
	while clock.t - t0 < 5 do
		serverFrame()
		local brain = EnemyService.brainOf(boarId)
		if crouchAt == nil and brain ~= nil and brain:getPhase() == "WindUp" then
			crouchAt = brain.phaseStart - t0
		end
		local playerRecord = EntityService.get(playerId)
		if playerRecord.hp < playerRecord.maxHp / 2 then
			EntityService.setHp(playerId, playerRecord.maxHp)
		end
	end
	local hitAt: number? = nil
	for _, entry in sent do
		if entry.remote == "HitConfirmed" and entry.time >= t0 and entry.payload.targetId == playerId then
			hitAt = entry.time - t0
			break
		end
	end
	return { staged = true, distance = distance, crouchAt = crouchAt, hitAt = hitAt }
end

local function shotDistance(): number
	for _, shot in CAPTURE.shots do
		if shot.id == SHOT_ID then
			return shot.stage.enemies[1].distance
		end
	end
	error("no shot " .. SHOT_ID)
end

describe("A staged shot stands its enemies off where the player rests (item 321)", function()
	-- { the walk's speed on its last leg, the replication's lag }: none; the sprint read a little
	-- late (staged short); a run read so the boar stands under minChargeDistance; the sprint read
	-- outside the ring (a new walk, the ping-pong between the approach point and the spot).
	for _, case in { { SPRINT, 0 }, { SPRINT, 0.1 }, { 16, 0.2 }, { SPRINT, 0.3 } } do
		local speed, lag = case[1], case[2]
		local name = "at %g studs/s with %g s of replication: the boar at the shot's distance, crouching at once"
		it(name:format(speed, lag), function()
			local take = runTake(speed, lag)
			expect(take.staged).toBe(true)
			-- 12 studs from where the player rests, not from where the server last saw them
			expect(math.abs(take.distance - shotDistance()) <= 0.25).toBe(true)
			-- the crouch on the take's first beats (the alert and one tick), not after a circle-out
			expect(take.crouchAt).toBeTruthy()
			expect(take.crouchAt :: number).toBeLessThan(0.5)
			-- Meets: the hit lands well inside the 5 s take, at about 1.1 s
			expect(take.hitAt).toBeTruthy()
			expect(take.hitAt :: number).toBeLessThan(1.5)
		end)
	end
end)
