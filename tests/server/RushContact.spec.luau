--!strict
--[[
	The boar's rush hits on contact (D-166), end to end: the real EnemyService, CombatService and
	EntityService over a RigBuilder boar, a fake engine whose bodies walk toward their MoveTo goals,
	and players that are real EntityService records. A player is hit on the tick the rush's snout
	reaches them on the server's clock (speed * elapsed + the snout's reach past the root), from
	the crouch point along exactly the telegraphed line; nobody past the line's end, beside it or
	stepping in behind the passing body is hit; a jammed body hits only what its snout reaches (D-195).
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

local EntityService = Harness.load("src/server/services/EntityService")
local CombatService = Harness.load("src/server/services/CombatService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local HitSweep = Harness.load("src/server/combat/HitSweep")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Playground = Harness.load("src/shared/data/playground")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

local TICK = AI.tickSeconds()
local CHARGE = Enemies.byId("FrenzyBoar").attacks[1]
local SPEED = AI.rushSpeed(CHARGE)

local clock = { t = 3000 }
local sent: { any } = {}
local bodies: { [any]: any } = {}
local jammed = false
local groups: { [any]: string } = {} -- each model's collision group, as the engine was told
local groupLog: { any } = {}
local bodyIsClear = true

local function record(remote: string, payload: any)
	local ok, message = Net.validate(remote, payload)
	if not ok then
		error(("invalid %s payload: %s"):format(remote, tostring(message)))
	end
	table.insert(sent, { time = clock.t, remote = remote, payload = payload })
end

local function sentOf(remote: string): { any }
	local list = {}
	for _, entry in sent do
		if entry.remote == remote then
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
	end,
	setCollisionGroup = function(model, group)
		groups[model] = group
		table.insert(groupLog, { time = clock.t, group = group })
	end,
	bodyClear = function(_model)
		return bodyIsClear
	end,
}

local function physics(dt: number)
	if jammed then
		return
	end
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
	jammed = false
	groups = {}
	groupLog = {}
	bodyIsClear = true
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

local playerCount = 0
local function spawnPlayer(position: Vector3): (number, any)
	playerCount += 1
	local model = Instance.new("Model")
	model.Name = "Trialist" .. playerCount
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.lookAt(position, position + Vector3.new(0, 0, 1)) -- facing the boar
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 900 + playerCount }
	return EntityService.registerPlayer(player :: any, model, Playground.loadout), model
end

local function tick()
	EnemyService.step(TICK)
	physics(TICK)
	EntityService.tick(TICK)
	CombatService.tick()
	clock.t += TICK
end

local function phaseOf(id: number): string?
	local brain = EnemyService.brainOf(id)
	return if brain ~= nil then brain:getPhase() else nil
end

-- Ticks until the boar launches; returns the launch time and the crouch point.
local function untilLaunch(boarId: number): (number, Vector3)
	local guard = 0
	while phaseOf(boarId) ~= "Strike" and guard < 200 do
		tick()
		guard += 1
	end
	expect(phaseOf(boarId)).toBe("Strike")
	local brain = EnemyService.brainOf(boarId)
	local launchAt = clock.t - TICK -- the tick that entered Strike ran before the clock advanced
	expect(brain:phaseElapsed()).toBeCloseTo(TICK, 1e-6)
	local telegraphs = sentOf("Telegraph")
	local origin = telegraphs[#telegraphs].payload.origin -- the crouch point the line was drawn from
	return launchAt, Vector3.new(origin[1], origin[2], origin[3])
end

local function hitsOn(targetId: number): { any }
	local list = {}
	for _, entry in sentOf("HitConfirmed") do
		if entry.payload.targetId == targetId then
			table.insert(list, entry)
		end
	end
	return list
end

-- The first tick (seconds after the launch) on which the snout reaches a target `along` studs down
-- the line with body radius `radius`.
local function contactTick(along: number, radius: number, front: number): number
	local seconds = math.max(0, (along - radius - front) / SPEED)
	return math.ceil(seconds / TICK - 1e-6) * TICK
end

describe("A boar's rush hits on contact (D-166)", function()
	it("a player is hit the tick the snout reaches them, long before the strike beat", function()
		fresh()
		local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
		local front = EnemyService.bodyExtents(EnemyService.modelOf(boarId))
		expect(front).toBeGreaterThan(5) -- the snout, well past the root's own half-length
		local playerId, model = spawnPlayer(Vector3.new(0, 3, -12))
		local launchAt, crouch = untilLaunch(boarId)
		local along = (EntityService.positionOf(playerId) - crouch):Dot(Vector3.new(0, 0, -1))
		local radius = HitSweep.bodyRadius(model)
		local expected = contactTick(along, radius, front)
		expect(expected).toBeLessThan(CHARGE.strike - TICK) -- what the old resolve-at-the-beat missed
		for _ = 1, 30 do
			tick()
		end
		local hits = hitsOn(playerId)
		expect(#hits).toBe(1)
		expect(hits[1].time - launchAt).toBeCloseTo(expected, 1e-6)
		expect(hits[1].payload.attackerId).toBe(boarId)
		expect(hits[1].payload.damage).toBeGreaterThan(0)
	end)

	it("past the line's end nobody is hit, though the overshoot carries the body over them", function()
		fresh()
		local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
		local targetId = spawnPlayer(Vector3.new(0, 3, -12))
		local pastId = spawnPlayer(Vector3.new(0, 3, -(CHARGE.reach + 4)))
		untilLaunch(boarId)
		while phaseOf(boarId) == "Strike" do
			tick()
		end
		expect(#hitsOn(targetId)).toBe(1)
		expect(#hitsOn(pastId)).toBe(0)
		expect(EntityService.get(pastId).hp).toBe(EntityService.get(pastId).maxHp)
	end)

	it("a player stepping into the line behind the passing body is not hit", function()
		fresh()
		local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
		spawnPlayer(Vector3.new(0, 3, -12))
		local launchAt = untilLaunch(boarId)
		-- Beside the line as the rush starts (joined late, so the boar never lined up on it).
		local sideId, side = spawnPlayer(Vector3.new(6, 3, -4))
		local _, back = EnemyService.bodyExtents(EnemyService.modelOf(boarId))
		-- Once the body's back has passed 4 studs down the line (plus the player's radius), step in.
		while SPEED * (clock.t - launchAt) - back <= 4 + 1 + SPEED * TICK do
			tick()
		end
		side.PrimaryPart.CFrame = CFrame.new(0, 3, -4)
		while phaseOf(boarId) == "Strike" do
			tick()
		end
		expect(#hitsOn(sideId)).toBe(0)
	end)

	it("a body jammed at the crouch point hits only what its snout reaches, on the same clock (D-195)", function()
		-- A player under the snout as the rush starts, and the target 12 studs down the line.
		local function run(jam: boolean): (number?, { any }, { any })
			fresh()
			local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
			local farId = spawnPlayer(Vector3.new(0, 3, -12))
			jammed = jam
			local launchAt, crouch = untilLaunch(boarId)
			local nearId = spawnPlayer(crouch + Vector3.new(0, 0, -6))
			while phaseOf(boarId) == "Strike" do
				tick()
			end
			local near = hitsOn(nearId)
			return if #near == 1 then near[1].time - launchAt else nil, hitsOn(farId), sentOf("RushEnded")
		end
		local free, freeFar = run(false)
		expect(free).never.toBeNil()
		expect(#freeFar).toBe(1)
		local near, far, ended = run(true)
		expect(near).toBeCloseTo(free :: number, 1e-9)
		expect(#far).toBe(0)
		expect(#ended).toBe(1)
		expect(ended[1].payload.reason).toBe("Jammed")
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The launch and an early stop go to every client (D-169)
-- ------------------------------------------------------------------------------------------

local function payloadsOf(remote: string): { any }
	local list = {}
	for _, entry in sentOf(remote) do
		table.insert(list, entry.payload)
	end
	return list
end

-- Spawns the boar and a player 12 studs down its line and ticks to the launch.
local function launched(): (number, number, Vector3)
	fresh()
	local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
	spawnPlayer(Vector3.new(0, 3, -12))
	local launchAt, crouch = untilLaunch(boarId)
	return boarId, launchAt, crouch
end

describe("Rush messages (D-169)", function()
	it(
		"the launch sends RushStarted with the server's line and clock; a rush that runs its time sends no end",
		function()
			local boarId, launchAt, crouch = launched()
			local started = payloadsOf("RushStarted")
			expect(#started).toBe(1)
			local rush = started[1]
			expect(rush.entityId).toBe(boarId)
			expect(rush.attackId).toBe(CHARGE.id)
			expect(rush.serverTime).toBeCloseTo(launchAt, 1e-9)
			expect((Vector3.new(rush.origin[1], rush.origin[2], rush.origin[3]) - crouch).Magnitude).toBeLessThan(1e-6)
			local telegraphs = payloadsOf("Telegraph")
			expect(rush.direction).toEqual(telegraphs[#telegraphs].facing) -- the line the telegraph drew
			expect(rush.speed).toBeCloseTo(SPEED, 1e-9)
			expect(rush.duration).toBeCloseTo((CHARGE.reach + AI.archetypes.Charger.overshoot) / SPEED, 1e-9)
			while phaseOf(boarId) == "Strike" do
				tick()
			end
			expect(phaseOf(boarId)).toBe("Recover")
			expect(#payloadsOf("RushEnded")).toBe(0)
			expect(#payloadsOf("RushStarted")).toBe(1)
		end
	)

	it(
		"a body that falls behind the clock is reported Jammed once, and the strike runs its time to the skid",
		function()
			local boarId, launchAt = launched()
			jammed = true
			while phaseOf(boarId) == "Strike" do
				tick()
			end
			local ended = payloadsOf("RushEnded")
			expect(#ended).toBe(1)
			expect(ended[1].reason).toBe("Jammed")
			expect(ended[1].entityId).toBe(boarId)
			expect(ended[1].launchedAt).toBeCloseTo(launchAt, 1e-9)
			-- Reported once the clock ran jamLagStuds ahead of the body, not before.
			local lag = AI.archetypes.Charger.jamLagStuds
			local after = ended[1].serverTime - launchAt
			expect(SPEED * after).toBeGreaterThan(lag + ended[1].distance)
			expect(SPEED * (after - TICK)).toBeLessThanOrEqual(lag + ended[1].distance + 1e-6)
			expect(phaseOf(boarId)).toBe("Recover")
		end
	)

	it("a stagger mid-rush ends it Interrupted where the body stands", function()
		local boarId, launchAt, crouch = launched()
		tick()
		tick()
		local model = EnemyService.modelOf(boarId)
		local progress = (engine.position(model) - crouch):Dot(Vector3.new(0, 0, -1))
		EntityService.setState(boarId, "Stagger", 0.5)
		local ended = payloadsOf("RushEnded")
		expect(#ended).toBe(1)
		expect(ended[1].reason).toBe("Interrupted")
		expect(ended[1].launchedAt).toBeCloseTo(launchAt, 1e-9)
		expect(ended[1].serverTime).toBeCloseTo(clock.t, 1e-9)
		expect(ended[1].distance).toBeCloseTo(progress, 1e-6)
		expect(phaseOf(boarId)).toBe("Interrupted")
		for _ = 1, 30 do
			tick()
		end
		expect(#payloadsOf("RushEnded")).toBe(1)
	end)

	it("a death mid-rush ends it Died, and a hold mid-rush ends it Stopped", function()
		local boarId = launched()
		tick()
		EntityService.die(boarId)
		local ended = payloadsOf("RushEnded")
		expect(#ended).toBe(1)
		expect(ended[1].reason).toBe("Died")

		local heldId = launched()
		tick()
		EnemyService.setHeld(heldId, true)
		ended = payloadsOf("RushEnded")
		expect(#ended).toBe(1)
		expect(ended[1].reason).toBe("Stopped")
		expect(ended[1].entityId).toBe(heldId)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- A rush runs through players and packmates (D-167)
-- ------------------------------------------------------------------------------------------

describe("Rush collision groups (D-167)", function()
	local GROUPS = AI.collision
	-- Ticks a stopped rush waits once its body is clear (D-190): it rejoins on the tick that has
	-- seen it clear for rejoinClearSeconds, counted from the first clear tick.
	local WAIT_TICKS = math.ceil(GROUPS.rejoinClearSeconds / TICK - 1e-6)

	-- Ticks until the model leaves the rushing group (at most `limit` ticks); returns the ticks run.
	local function ticksUntilSolid(model: any, limit: number): number
		local count = 0
		while groups[model] == GROUPS.rushing and count < limit do
			tick()
			count += 1
		end
		return count
	end

	it("an enemy joins the enemies group at spawn; its rush runs in the rushing group and rejoins after it", function()
		local boarId = launched()
		local model = EnemyService.modelOf(boarId)
		expect(groupLog[1].group).toBe(GROUPS.enemies)
		expect(groups[model]).toBe(GROUPS.rushing)
		while phaseOf(boarId) == "Strike" do
			tick()
			if phaseOf(boarId) == "Strike" then
				expect(groups[model]).toBe(GROUPS.rushing)
			end
		end
		-- The first clear tick starts the wait; the body rejoins rejoinClearSeconds after it.
		expect(ticksUntilSolid(model, 40)).toBe(WAIT_TICKS + 1)
		expect(groups[model]).toBe(GROUPS.enemies)
	end)

	it("a stopped rush waits in the rushing group while its body overlaps someone, then rejoins", function()
		local boarId = launched()
		local model = EnemyService.modelOf(boarId)
		bodyIsClear = false
		while phaseOf(boarId) == "Strike" do
			tick()
		end
		for _ = 1, 10 do
			tick()
			expect(groups[model]).toBe(GROUPS.rushing)
		end
		bodyIsClear = true
		expect(ticksUntilSolid(model, 40)).toBe(WAIT_TICKS + 1)
		expect(groups[model]).toBe(GROUPS.enemies)
	end)

	it("an overlap during the wait starts it over", function()
		local boarId = launched()
		local model = EnemyService.modelOf(boarId)
		while phaseOf(boarId) == "Strike" do
			tick()
		end
		for _ = 1, WAIT_TICKS - 1 do
			tick()
		end
		expect(groups[model]).toBe(GROUPS.rushing)
		bodyIsClear = false
		tick()
		bodyIsClear = true
		expect(ticksUntilSolid(model, 40)).toBe(WAIT_TICKS + 1)
	end)

	it("a jammed rush stops and rejoins once clear for the wait; an interrupted one likewise", function()
		local boarId = launched()
		local model = EnemyService.modelOf(boarId)
		jammed = true
		bodyIsClear = true
		local jammedAt: number? = nil
		while groups[model] == GROUPS.rushing and phaseOf(boarId) == "Strike" do
			tick()
			if jammedAt == nil and #payloadsOf("RushEnded") == 1 then
				jammedAt = clock.t
				expect(bodies[model].goal).toBeNil() -- the jam stopped the body (D-190)
			end
		end
		expect(jammedAt).never.toBeNil()
		expect(#payloadsOf("RushEnded")).toBe(1) -- the jam was told once
		if groups[model] == GROUPS.rushing then
			ticksUntilSolid(model, 40)
		end
		expect(groups[model]).toBe(GROUPS.enemies)
		expect(clock.t - (jammedAt :: number)).toBeGreaterThan(GROUPS.rejoinClearSeconds - 1e-6)

		local staggeredId = launched()
		local staggered = EnemyService.modelOf(staggeredId)
		tick()
		EntityService.setState(staggeredId, "Stagger", 0.5)
		expect(groups[staggered]).toBe(GROUPS.rushing)
		expect(ticksUntilSolid(staggered, 40)).toBe(WAIT_TICKS + 1)
		expect(groups[staggered]).toBe(GROUPS.enemies)
	end)
end)
