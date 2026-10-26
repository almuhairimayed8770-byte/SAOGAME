--!strict
--[[
	Staged takes on the real services (F12, CS): DevStage.server.luau loaded the way Studio runs
	it, over the real EnemyService, CombatService and EntityService (a RigBuilder enemy, a fake
	engine whose bodies walk toward their MoveTo goals, the AI's 20 Hz tick on a fake clock) and a
	player standing still on the stand spot. Each take is staged, held through the countdown, let go
	with "go", run for the shot's length, then ended with "hold" the way the capture panel ends it.

	- A released Charger's first charge does what its shot says (dev.luau StagedEnemy.charge): it
	  "Meets" the player standing on the spot (the telegraphed line reaches them, one hit) or
	  "Passes" (the line ends short of them; the overshoot carries the body on, no hit).
	- The charge shot shows the whole charge inside the take: the 0.6 s crouch with its line from
	  the start, the launch, the hit and the skid past the player, once.
	- The take's end holds every staged enemy (D-297): nothing of the take hits, telegraphs or starts
	  an action between takes.
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
local AI = Harness.load("src/shared/data/ai")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Playground = Harness.load("src/shared/data/playground")
local World = Harness.load("src/shared/data/world")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

local TICK = AI.tickSeconds()
local CAPTURE = Dev.capture
local STAGE = CAPTURE.stage
local HIP = 2 -- the player's Humanoid.HipHeight in this world
local COUNTDOWN_TICKS = math.ceil(CAPTURE.countdownSeconds / TICK)
local BETWEEN_TAKES_SECONDS = 10

local clock = { t = 3000 }
-- DevStage's task.delay functions (a late release, CF), each run on the first tick past its moment.
local timers: { { at: number, fn: () -> () } } = {}
local sent: { any } = {}
local bodies: { [any]: any } = {}

local function record(remote: string, payload: any)
	local ok, message = Net.validate(remote, payload)
	if not ok then
		error(("invalid %s payload: %s"):format(remote, tostring(message)))
	end
	table.insert(sent, { time = clock.t, remote = remote, payload = payload })
end

local function sentOf(remote: string, from: number?): { any }
	local list = {}
	for _, entry in sent do
		if entry.remote == remote and entry.time >= (from or -math.huge) then
			table.insert(list, entry)
		end
	end
	return list
end

local engine = {
	place = function(model, cframe)
		model.PrimaryPart.CFrame = cframe
		EnemyService.addYawAlign(model.PrimaryPart, cframe.LookVector)
		bodies[model] = { position = cframe.Position, goal = nil, walkSpeed = nil }
	end,
	position = function(model)
		return bodies[model].position
	end,
	facing = function(model)
		local align = EnemyService.alignOf(model)
		return if align ~= nil then align.CFrame.LookVector else model.PrimaryPart.CFrame.LookVector
	end,
	setFacing = function(model, facing)
		EnemyService.applyFacing(model, facing)
	end,
	moveTo = function(model, position)
		bodies[model].goal = position
	end,
	stop = function(model)
		bodies[model].goal = nil
	end,
	setWalkSpeed = function(model, speed)
		bodies[model].walkSpeed = speed
	end,
	computePath = function()
		return nil
	end,
	destroy = function(model)
		model.Parent = nil
		bodies[model] = nil
	end,
	setCollisionGroup = function() end,
	bodyClear = function(_model)
		return true
	end,
}

local function physics(dt: number)
	for model, body in bodies do
		if body.goal ~= nil then
			local delta = body.goal - body.position
			local reach = (body.walkSpeed or 1) * dt
			if delta.Magnitude <= reach then
				body.position = body.goal
			elseif delta.Magnitude > 0 then
				body.position += delta.Unit * reach
			end
		end
		model.PrimaryPart.CFrame = CFrame.new(body.position)
	end
end

local function fresh()
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	clock.t = 3000
	sent = {}
	bodies = {}
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

local function tick()
	EnemyService.step(TICK)
	physics(TICK)
	EntityService.tick(TICK)
	CombatService.tick()
	clock.t += TICK
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

-- DevStage.server.luau as Studio runs it, over the real services bound above.
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
			local dt = seconds or TICK
			clock.t += dt
			return dt
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

-- The player on the stand spot, facing the shot's way, feet on the floor.
local function spawnPlayer(): (number, any)
	local area = STAGE.area
	local y = area.position[2] + HIP + 1 + World.spawn.groundEpsilon
	local model = Instance.new("Model")
	model.Name = "Trialist"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(area.position[1], y, area.position[3]) * CFrame.Angles(0, math.rad(area.facing), 0)
	root.Position = root.CFrame.Position
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = HIP
	humanoid.Parent = model
	model.Parent = Instance.new("Folder")
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 901 }
	return EntityService.registerPlayer(player :: any, model, Playground.loadout), model
end

local function shotById(id: string): any
	for _, shot in CAPTURE.shots do
		if shot.id == id then
			return shot
		end
	end
	error("no shot " .. id)
end

type Phase = { phase: string, at: number, position: Vector3 }
type Take = {
	shot: any,
	playerId: number,
	playerAt: Vector3,
	ids: { number },
	phases: { [number]: { Phase } }, -- each staged enemy's phase changes, `at` from the "go"
	hits: { any }, -- HitConfirmed on the player inside the take, `at` from the "go"
	held: any, -- the "hold" reply
	after: { hits: number, telegraphs: number, actions: number },
}

-- One take of a shot, the player standing still on the spot (kept above half HP so the take runs
-- its length), ended with "hold" and followed by BETWEEN_TAKES_SECONDS of standing.
local function runTake(shotId: string): Take
	fresh()
	local shot = shotById(shotId)
	local remote = loadStage()
	local playerId = spawnPlayer()
	local who = EntityService.get(playerId).player
	local function invoke(action: string, id: string?): any
		clock.t += 1 / STAGE.requestsPerSecond
		return remote.OnServerInvoke(who, action, id)
	end
	local staged = invoke("stage", shot.id)
	assert(staged.ok == true, "the staging refused: " .. tostring(staged.error))
	for _ = 1, COUNTDOWN_TICKS do
		tick()
	end
	local go = invoke("go")
	assert(go.ok == true, "go refused: " .. tostring(go.error))
	local t0 = clock.t
	local phases: { [number]: { Phase } } = {}
	local last: { [number]: string } = {}
	for _, id in staged.ids do
		phases[id] = {}
	end
	while clock.t - t0 < shot.seconds do
		tick()
		for _, id in staged.ids do
			local brain = EnemyService.brainOf(id)
			local phase = if brain ~= nil then brain:getPhase() else "Gone"
			if phase ~= last[id] then
				local model = EnemyService.modelOf(id)
				local body = if model ~= nil then bodies[model] else nil
				table.insert(phases[id], {
					phase = phase,
					at = (if brain ~= nil then brain.phaseStart else clock.t) - t0,
					position = if body ~= nil then body.position else Vector3.zero,
				})
				last[id] = phase
			end
		end
		local record = EntityService.get(playerId)
		if record.hp < record.maxHp / 2 then
			EntityService.setHp(playerId, record.maxHp)
		end
	end
	local hits = {}
	for _, entry in sentOf("HitConfirmed", t0) do
		if entry.payload.targetId == playerId then
			table.insert(hits, { at = entry.time - t0, payload = entry.payload })
		end
	end
	local held = invoke("hold")
	local holdAt = clock.t
	EntityService.setHp(playerId, EntityService.get(playerId).maxHp)
	while clock.t - holdAt < BETWEEN_TAKES_SECONDS do
		tick()
	end
	local after = 0
	for _, entry in sentOf("HitConfirmed", holdAt) do
		if entry.payload.targetId == playerId then
			after += 1
		end
	end
	return {
		shot = shot,
		playerId = playerId,
		playerAt = EntityService.positionOf(playerId),
		ids = staged.ids,
		phases = phases,
		hits = hits,
		held = held,
		after = {
			hits = after,
			telegraphs = #sentOf("Telegraph", holdAt),
			actions = #sentOf("ActionStarted", holdAt),
		},
	}
end

local function firstOf(list: { Phase }, phase: string, from: number?): Phase?
	for _, entry in list do
		if entry.phase == phase and entry.at >= (from or -math.huge) then
			return entry
		end
	end
	return nil
end

local function countOf(list: { Phase }, phase: string): number
	local count = 0
	for _, entry in list do
		if entry.phase == phase then
			count += 1
		end
	end
	return count
end

local function rushOf(enemy: string): any
	local def = Enemies.byId(enemy)
	return if def ~= nil and def.archetype == "Charger" then def.attacks[1] else nil
end

describe("Staged takes on the real services (F12, CS)", function()
	it("the charge shot: the 0.6 s crouch from the start, the launch, one hit, the skid past the player", function()
		local take = runTake("enemy-boar-charge")
		local boarId = take.ids[1]
		local charge = rushOf("FrenzyBoar")
		local log = take.phases[boarId]
		local crouch = firstOf(log, "WindUp")
		expect(crouch).toBeTruthy()
		local crouchAt = (crouch :: Phase).at
		-- the crouch starts on the take's first beats, never before the "go" (held through the countdown)
		expect(crouchAt >= 0).toBe(true)
		expect(crouchAt).toBeLessThan(0.5)
		local launch = firstOf(log, "Strike", crouchAt) :: Phase
		expect(launch).toBeTruthy()
		expect(launch.at - crouchAt).toBeCloseTo(charge.windUp, 1e-6)
		local telegraph = nil
		for _, entry in sentOf("Telegraph") do
			if entry.payload.entityId == boarId then
				telegraph = entry.payload
				break
			end
		end
		expect(telegraph).toBeTruthy()
		expect(telegraph.windUp).toBe(charge.windUp)
		expect(telegraph.shape.kind).toBe("Line")
		expect(telegraph.shape.length).toBe(charge.reach)
		-- one hit, from the boar, during its run
		local skid = firstOf(log, "Recover", launch.at) :: Phase
		expect(skid).toBeTruthy()
		expect(#take.hits).toBe(1)
		expect(take.hits[1].payload.attackerId).toBe(boarId)
		expect(take.hits[1].at >= launch.at).toBe(true)
		expect(take.hits[1].at <= skid.at).toBe(true)
		-- the run carries the body past the player, and the skid plays inside the take
		local line = (take.playerAt - (crouch :: Phase).position) * Vector3.new(1, 0, 1)
		local past = (skid.position - take.playerAt):Dot(line.Unit)
		expect(past).toBeGreaterThan(0)
		expect(skid.at + 1).toBeLessThan(take.shot.seconds)
		-- one charge per take: the prompts describe exactly one
		expect(countOf(log, "WindUp")).toBe(1)
	end)

	it("every released Charger's first charge meets or passes the player as its shot says", function()
		local checked = 0
		for _, shot in CAPTURE.shots do
			for index, entry in shot.stage.enemies do
				local rush = rushOf(entry.enemy)
				if rush == nil or entry.held then
					continue
				end
				expect(entry.charge == "Meets" or entry.charge == "Passes").toBe(true)
				local take = runTake(shot.id)
				local id = take.ids[index]
				local log = take.phases[id]
				local launch = firstOf(log, "Strike")
				expect(launch).toBeTruthy()
				local skid = firstOf(log, "Recover", (launch :: Phase).at) :: Phase
				expect(skid).toBeTruthy()
				local fromIt = 0
				for _, hit in take.hits do
					if hit.payload.attackerId == id and hit.at >= (launch :: Phase).at and hit.at <= skid.at then
						fromIt += 1
					end
				end
				expect(fromIt).toBe(if entry.charge == "Meets" then 1 else 0)
				checked += 1
			end
		end
		expect(checked >= 2).toBe(true) -- the charge shot and the fight
	end)

	it("a take's end holds every staged enemy: nothing hits, telegraphs or acts between takes (D-297)", function()
		local checked = 0
		for _, shot in CAPTURE.shots do
			local released = false
			for _, entry in shot.stage.enemies do
				released = released or not entry.held
			end
			if not released then
				continue
			end
			local take = runTake(shot.id)
			expect(take.held.ok).toBe(true)
			expect(#take.held.held).toBe(#take.ids)
			expect(take.after.hits).toBe(0)
			expect(take.after.telegraphs).toBe(0)
			expect(take.after.actions).toBe(0)
			checked += 1
		end
		expect(checked >= 4).toBe(true) -- the fight, the charge, the overhead and the parry
	end)
end)
