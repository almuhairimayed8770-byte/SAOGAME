--!strict
--[[
	EnemyService under Lune: the real EntityService (fake clock, fake net, fake tags), a fake
	RigBuilder, a fake engine (positions, facings, MoveTo goals, path requests) with a one-line
	physics stand-in, and a fake CombatService that records enemy strikes. Spawning, the tick,
	telegraph and action payloads against the remote schemas, sleep, death, interrupts, despawn,
	the MoveTo / pathfinding mover and the step accumulator.
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
local EnemyService = Harness.load("src/server/services/EnemyService")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Combat = Harness.load("src/shared/data/combat")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

local TICK = AI.tickSeconds()
local FORWARD = Vector3.new(0, 0, -1)
local BOAR = Enemies.byId("FrenzyBoar")
local KOBOLD = Enemies.byId("KoboldAxeman")
local CHARGE = BOAR.attacks[1]
local OVERHEAD = KOBOLD.attacks[1]

-- ------------------------------------------------------------------------------------------
-- Fixtures
-- ------------------------------------------------------------------------------------------

local clock = { t = 1000 }
local sent: { any } = {}
local strikes: { any } = {}
local spawned: { any } = {}
local despawned: { any } = {}
local builds: { any } = {}
local pathCalls: { any } = {}
local pathResult: ((from: Vector3, to: Vector3) -> { Vector3 }?)? = nil
local deferredPaths: { () -> () }? = nil -- when set, path computations queue here instead of running inline
local physicsEnabled = true
local players: { any } = {}
local bodies: { [any]: any } = {}
local folder: any = nil
local connections: { any } = {}

local function near(a: Vector3, b: Vector3, epsilon: number?): boolean
	return (a - b).Magnitude <= (epsilon or 1e-3)
end

local function bodyOf(model: any)
	local body = bodies[model]
	if body == nil then
		body = {
			position = Vector3.zero,
			facing = FORWARD,
			goal = nil,
			walkSpeed = nil,
			moveTos = {},
			stops = 0,
			destroyed = false,
		}
		bodies[model] = body
	end
	return body
end

local function writeRoot(model: any, body: any)
	local root = model.PrimaryPart
	if root ~= nil then
		root.CFrame = CFrame.new(body.position)
	end
end

local engine = {
	place = function(model, cframe)
		local body = bodyOf(model)
		body.position = cframe.Position
		body.facing = cframe.LookVector
		body.parentAtPlace = model.Parent -- the real engine claims network ownership here: it needs Workspace
		writeRoot(model, body)
	end,
	position = function(model)
		return bodyOf(model).position
	end,
	facing = function(model)
		return bodyOf(model).facing
	end,
	setFacing = function(model, facing)
		bodyOf(model).facing = facing.Unit
	end,
	moveTo = function(model, position)
		local body = bodyOf(model)
		body.goal = position
		table.insert(body.moveTos, { time = clock.t, position = position, from = body.position })
	end,
	stop = function(model)
		local body = bodyOf(model)
		body.goal = nil
		body.stops += 1
	end,
	setWalkSpeed = function(model, speed)
		bodyOf(model).walkSpeed = speed
	end,
	computePath = function(from, to)
		table.insert(pathCalls, { time = clock.t, from = from, to = to })
		return if pathResult ~= nil then pathResult(from, to) else nil
	end,
	destroy = function(model)
		bodyOf(model).destroyed = true
		model.Parent = nil
	end,
}

local rigBuilder = {
	build = function(rigId, name)
		table.insert(builds, { rigId = rigId, name = name })
		local model = Instance.new("Model")
		model.Name = name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 4)
		root.CFrame = CFrame.new(0, 0, 0)
		root.Parent = model
		model.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
		return model
	end,
}

local hitStopHooks: { any } = {} -- every hook EnemyService handed CombatService.setEnemyHitStop
local combat = {
	setEnemyHitStop = function(hook)
		table.insert(hitStopHooks, hook or false)
	end,
	enemyStrike = function(enemyId, attack, origin, facing, options)
		table.insert(
			strikes,
			{ time = clock.t, enemyId = enemyId, attack = attack, origin = origin, facing = facing, options = options }
		)
		return {}
	end,
}

local function fresh()
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	EnemyService.reset()
	EntityService.reset()
	clock.t = 1000
	sent = {}
	strikes = {}
	spawned = {}
	despawned = {}
	builds = {}
	pathCalls = {}
	pathResult = nil
	deferredPaths = nil
	physicsEnabled = true
	players = {}
	bodies = {}
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	EntityService.bind({
		now = function()
			return clock.t
		end,
		fireAll = function(remote, payload)
			local ok, message = Net.validate(remote, payload)
			if not ok then
				error(("invalid %s payload: %s"):format(remote, tostring(message)))
			end
			table.insert(sent, { remote = remote, payload = payload })
		end,
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
	EnemyService.bind({
		entities = EntityService,
		combat = combat,
		rigBuilder = rigBuilder,
		fireAll = function(remote, payload)
			local ok, message = Net.validate(remote, payload)
			if not ok then
				error(("invalid %s payload: %s"):format(remote, tostring(message)))
			end
			table.insert(sent, { remote = remote, payload = payload })
		end,
		engine = engine,
		players = function()
			return players
		end,
		heartbeat = nil,
		serverTime = function()
			return clock.t
		end,
		folder = folder,
		random = Random.new(1),
		spawnTask = function(fn)
			local queue = deferredPaths
			if queue ~= nil then
				table.insert(queue, fn)
			else
				fn()
			end
		end,
	})
	table.insert(
		connections,
		EnemyService.Spawned:Connect(function(id, defId, model)
			table.insert(spawned, { id = id, defId = defId, model = model })
		end)
	)
	table.insert(
		connections,
		EnemyService.Despawned:Connect(function(id, defId, reason)
			table.insert(despawned, { id = id, defId = defId, reason = reason })
		end)
	)
end

local function sentOf(remote: string)
	local list = {}
	for _, entry in sent do
		if entry.remote == remote then
			table.insert(list, entry.payload)
		end
	end
	return list
end

local function putPlayer(id: number, position: Vector3)
	for _, snapshot in players do
		if snapshot.id == id then
			snapshot.position = position
			return
		end
	end
	table.insert(players, { id = id, position = position })
end

-- One AI tick of the world: the service steps, bodies walk toward their MoveTo goals at their
-- walk speed, EntityService expires timed states, the clock advances.
local function physics(dt: number)
	if not physicsEnabled then
		return
	end
	for model, body in bodies do
		if body.goal ~= nil and not body.destroyed then
			local delta = body.goal - body.position
			local distance = delta.Magnitude
			local reach = (body.walkSpeed or 1) * dt
			if distance <= reach then
				body.position = body.goal
			elseif distance > 0 then
				body.position = body.position + delta.Unit * reach
			end
			writeRoot(model, body)
		end
	end
end

local function advance(seconds: number)
	local remaining = seconds
	while remaining > 1e-9 do
		EnemyService.step(TICK)
		physics(TICK)
		EntityService.tick(TICK)
		clock.t += TICK
		remaining -= TICK
	end
end

local function advanceUntil(predicate: () -> boolean, maxSeconds: number): boolean
	local elapsed = 0
	while elapsed < maxSeconds do
		if predicate() then
			return true
		end
		advance(TICK)
		elapsed += TICK
	end
	return predicate()
end

-- A fake PathfindingService: the route starts under the body (as real paths do), passes the corners
-- the body has not reached yet along the route's Z direction, and ends at the goal.
local function routeThrough(corners: { Vector3 }, towardNegativeZ: boolean)
	return function(from: Vector3, to: Vector3): { Vector3 }
		local waypoints = { from }
		for _, corner in corners do
			local ahead = if towardNegativeZ then corner.Z < from.Z - 1 else corner.Z > from.Z + 1
			if ahead then
				table.insert(waypoints, corner)
			end
		end
		table.insert(waypoints, to)
		return waypoints
	end
end

local function phaseOf(id: number): string?
	local brain = EnemyService.brainOf(id)
	return if brain ~= nil then brain:getPhase() else nil
end

local function spawnAt(defId: string, position: Vector3, options: any?): (number, any)
	local id = EnemyService.spawn(defId, CFrame.new(position), options)
	return id, EnemyService.modelOf(id)
end

-- ------------------------------------------------------------------------------------------
-- Spawning
-- ------------------------------------------------------------------------------------------

describe("EnemyService spawn", function()
	it("builds the rig, registers the entity, parents it under the folder and fires Spawned", function()
		fresh()
		local id, model = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		local def = Enemies.scaled(BOAR)
		expect(builds).toHaveLength(1)
		expect(builds[1].rigId).toBe(BOAR.skin)
		expect(builds[1].name).toBe(BOAR.name)
		expect(model.Parent).toBe(folder)
		expect(bodyOf(model).parentAtPlace).toBe(folder) -- placed (and network-owned) only once under the folder
		local record = EntityService.get(id)
		expect(record).toBeTruthy()
		expect(record.kind).toBe("Enemy")
		expect(record.defId).toBe("FrenzyBoar")
		expect(record.hp).toBe(def.hp)
		expect(record.state).toBe("Idle")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		expect(humanoid.WalkSpeed).toBe(def.moveSpeed)
		expect(humanoid.AutoRotate).toBe(false)
		expect(near(engine.position(model), Vector3.new(0, 3, 0))).toBe(true)
		expect(spawned).toHaveLength(1)
		expect(spawned[1].id).toBe(id)
		expect(spawned[1].defId).toBe("FrenzyBoar")
		expect(spawned[1].model).toBe(model)
		expect(phaseOf(id)).toBe("Idle")
		expect(EnemyService.isAwake(id)).toBe(true)
		expect(EnemyService.count()).toBe(1)
		expect(EnemyService.ids()).toEqual({ id })
		expect(EnemyService.defOf(id).id).toBe("FrenzyBoar")
	end)

	it("resolveDef applies the Elite and Night variants and a band override", function()
		fresh()
		local plain = EnemyService.resolveDef("FrenzyBoar")
		expect(plain.attacks).toHaveLength(#BOAR.attacks)
		expect(plain.band).toBe(BOAR.band)
		local elite = EnemyService.resolveDef("FrenzyBoar", { elite = true, band = "Blight" })
		expect(#elite.attacks).toBeGreaterThan(#BOAR.attacks)
		expect(elite.hp).toBeGreaterThan(plain.hp)
		expect(elite.band).toBe("Blight")
		local night = EnemyService.resolveDef("KoboldAxeman", { night = true })
		expect(night.attack).toBeGreaterThan(Enemies.scaled(KOBOLD).attack)
		local id = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0), { elite = true, name = "Tusked One" })
		expect(EntityService.get(id).name).toBe("Tusked One")
		expect(#EnemyService.defOf(id).attacks).toBe(#elite.attacks)
	end)

	it("refuses an unknown def", function()
		fresh()
		expect(function()
			EnemyService.spawn("NotAnEnemy", CFrame.new())
		end).toThrow("unknown enemy def")
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The tick: telegraphs, strikes, payloads
-- ------------------------------------------------------------------------------------------

describe("EnemyService tick", function()
	it("a boar telegraphs its Charge within a few seconds of a player appearing, with valid payloads", function()
		fresh()
		local id, model = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -20))
		local appeared = clock.t
		expect(advanceUntil(function()
			return #sentOf("Telegraph") > 0
		end, 5)).toBe(true)
		expect(clock.t - appeared).toBeLessThan(5)

		local telegraph = sentOf("Telegraph")[1]
		expect(telegraph.entityId).toBe(id)
		expect(telegraph.attackId).toBe(CHARGE.id)
		expect(telegraph.kind).toBe(CHARGE.telegraph)
		expect(telegraph.windUp).toBe(CHARGE.windUp)
		expect(telegraph.shape.kind).toBe("Line")
		expect(telegraph.shape.length).toBe(CHARGE.reach)
		expect(telegraph.shape.width).toBe(Combat.strikeLineWidth)
		local position = engine.position(model)
		expect(near(Vector3.new(telegraph.origin[1], telegraph.origin[2], telegraph.origin[3]), position, 1e-3)).toBe(
			true
		)
		expect(telegraph.facing[2]).toBe(0)
		expect(telegraph.facing[3]).toBeLessThan(0)
		expect(telegraph.serverTime).toBeCloseTo(clock.t - TICK, 1e-9)

		local action = sentOf("ActionStarted")[1]
		expect(action).toBeTruthy()
		expect(action.entityId).toBe(id)
		expect(action.clipId).toBe(("enemy/%s/%s"):format(BOAR.skin, CHARGE.clip))
		expect(phaseOf(id)).toBe("WindUp")
		expect(EntityService.get(id).state).toBe("Art")
	end)

	it(
		"the rush reaches CombatService.enemyStrike stretch by stretch from the launch to the strike beat, from the crouch point along the line (D-166)",
		function()
			fresh()
			local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
			putPlayer(1, Vector3.new(0, 3, -20))
			expect(advanceUntil(function()
				return #sentOf("Telegraph") > 0
			end, 5)).toBe(true)
			local telegraph = sentOf("Telegraph")[1]
			local telegraphAt = clock.t
			expect(advanceUntil(function()
				return #strikes > 0
			end, 3)).toBe(true)
			-- The launch resolves the body where it crouched (the fake rig's 4-stud root, 2 each way),
			-- its snout carried on by the time since the launch beat (the wind-up's end) the tick that
			-- launches it came after.
			local first = strikes[1]
			expect(first.enemyId).toBe(id)
			expect(first.attack.id).toBe(CHARGE.id)
			expect(first.time - telegraphAt).toBeCloseTo(CHARGE.windUp, TICK + 1e-6)
			local beat = telegraph.serverTime + CHARGE.windUp
			expect(first.time - beat).toBeGreaterThanOrEqual(-1e-9)
			expect(first.time - beat).toBeLessThan(TICK + 1e-6)
			expect(first.options.span.from).toBeCloseTo(-2, 1e-6)
			expect(first.options.span.to).toBeCloseTo(2 + AI.rushSpeed(CHARGE) * (first.time - beat), 1e-6)
			expect(phaseOf(id)).toBe("Strike")
			expect(advanceUntil(function()
				return phaseOf(id) == "Recover"
			end, 2)).toBe(true)
			local origin = Vector3.new(telegraph.origin[1], telegraph.origin[2], telegraph.origin[3])
			local facing = Vector3.new(telegraph.facing[1], telegraph.facing[2], telegraph.facing[3])
			for _, strike in strikes do
				expect(near(strike.origin, origin, 1e-3)).toBe(true)
				expect(near(strike.facing, facing, 1e-3)).toBe(true)
				expect(strike.options.resolved).toBe(first.options.resolved)
			end
			local last = strikes[#strikes]
			expect(last.time - telegraphAt).toBeCloseTo(CHARGE.windUp + CHARGE.strike, TICK + 1e-6)
			expect(last.options.span.to).toBeGreaterThanOrEqual(CHARGE.reach)
			expect(EntityService.get(id).state).toBe("PostMotion")
		end
	)

	it("a kobold walks up at its move speed and telegraphs its Overhead cone", function()
		fresh()
		local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		local def = Enemies.scaled(KOBOLD)
		putPlayer(1, Vector3.new(0, 3, -12))
		expect(advanceUntil(function()
			return #sentOf("Telegraph") > 0
		end, 5)).toBe(true)
		local body = bodyOf(model)
		expect(body.walkSpeed).toBe(def.moveSpeed)
		expect(#body.moveTos).toBeGreaterThan(0)
		expect(body.position.Z).toBeLessThan(-1)
		local telegraph = sentOf("Telegraph")[1]
		expect(telegraph.entityId).toBe(id)
		expect(telegraph.attackId).toBe(OVERHEAD.id)
		expect(telegraph.kind).toBe("GuardBreak")
		expect(telegraph.windUp).toBe(OVERHEAD.windUp)
		expect(telegraph.shape.kind).toBe("Cone")
		expect(telegraph.shape.width).toBe(OVERHEAD.arc)
		expect(sentOf("ActionStarted")[1].clipId).toBe(("enemy/%s/%s"):format(KOBOLD.skin, OVERHEAD.clip))
		expect(phaseOf(id)).toBe("WindUp")
		local windUpAt = clock.t
		expect(advanceUntil(function()
			return #strikes > 0
		end, 3)).toBe(true)
		expect(strikes[1].time - windUpAt).toBeGreaterThanOrEqual(OVERHEAD.windUp)
	end)

	it("every payload the tick sends passes its remote schema", function()
		fresh()
		spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		spawnAt("KoboldAxeman", Vector3.new(10, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -15))
		advance(6)
		expect(#sentOf("Telegraph")).toBeGreaterThan(0)
		expect(#sentOf("ActionStarted")).toBeGreaterThan(0)
		for _, entry in sent do
			local ok = Net.validate(entry.remote, entry.payload)
			expect(ok).toBe(true)
		end
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Sleep
-- ------------------------------------------------------------------------------------------

describe("EnemyService sleep", function()
	it("a brain farther than the sleep radius from every player sleeps and does not tick", function()
		fresh()
		local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		local brain = EnemyService.brainOf(id)
		local ticks = 0
		local original = brain.tick
		brain.tick = function(self, dt)
			ticks += 1
			return original(self, dt)
		end
		putPlayer(1, Vector3.new(0, 3, -(AI.sleepRadius + 50)))
		advance(AI.sleepCheckInterval + TICK * 2)
		expect(EnemyService.isAwake(id)).toBe(false)
		expect(brain:isAwake()).toBe(false)
		local asleepTicks = ticks
		advance(1)
		expect(ticks).toBe(asleepTicks)
		expect(sentOf("Telegraph")).toHaveLength(0)

		-- The player walks in: the brain wakes and the boar attacks a few seconds later.
		putPlayer(1, Vector3.new(0, 3, -20))
		advance(AI.sleepCheckInterval + TICK * 2)
		expect(EnemyService.isAwake(id)).toBe(true)
		expect(ticks).toBeGreaterThan(asleepTicks)
		expect(advanceUntil(function()
			return #sentOf("Telegraph") > 0
		end, 5)).toBe(true)
	end)

	it("with no players at all every brain sleeps", function()
		fresh()
		local boar = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		local kobold = spawnAt("KoboldAxeman", Vector3.new(20, 3, 0))
		advance(AI.sleepCheckInterval + TICK * 2)
		expect(EnemyService.isAwake(boar)).toBe(false)
		expect(EnemyService.isAwake(kobold)).toBe(false)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Death, interrupts, despawn
-- ------------------------------------------------------------------------------------------

describe("EnemyService lifecycle", function()
	it("death stops the brain and fires Despawned once with reason Died; EntityService keeps the corpse", function()
		fresh()
		local id, model = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -20))
		expect(advanceUntil(function()
			return phaseOf(id) == "WindUp"
		end, 5)).toBe(true)
		EntityService.die(id)
		expect(despawned).toHaveLength(1)
		expect(despawned[1].id).toBe(id)
		expect(despawned[1].defId).toBe("FrenzyBoar")
		expect(despawned[1].reason).toBe("Died")
		expect(EnemyService.brainOf(id)).toBeNil()
		expect(EnemyService.count()).toBe(0)
		expect(bodyOf(model).destroyed).toBe(false)
		advance(2)
		expect(strikes).toHaveLength(0)
		expect(despawned).toHaveLength(1)
		expect(EntityService.get(id)).toBeTruthy()
		expect(EntityService.get(id).state).toBe("Dead")
	end)

	it("a Stagger during the kobold's wind-up (a parry) cancels the strike; it attacks again later", function()
		fresh()
		local id = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -6))
		expect(advanceUntil(function()
			return phaseOf(id) == "WindUp"
		end, 5)).toBe(true)
		advance(0.3)
		expect(phaseOf(id)).toBe("WindUp")
		expect(strikes).toHaveLength(0)
		EntityService.setState(id, "Stagger", Combat.parryStagger)
		expect(phaseOf(id)).toBe("Interrupted")
		advance(2)
		expect(strikes).toHaveLength(0)
		expect(advanceUntil(function()
			return #strikes > 0
		end, 6)).toBe(true)
		expect(sentOf("Telegraph")).toHaveLength(2)
	end)

	it("a Break from the record interrupts a chase and the brain resumes afterwards", function()
		fresh()
		local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -34))
		expect(advanceUntil(function()
			return phaseOf(id) == "Chase"
		end, 2)).toBe(true)
		EntityService.setState(id, "Break", Combat.breakDuration)
		expect(phaseOf(id)).toBe("Interrupted")
		advance(Combat.breakDuration / 2)
		expect(phaseOf(id)).toBe("Interrupted")
		expect(advanceUntil(function()
			return phaseOf(id) ~= "Interrupted"
		end, Combat.breakDuration)).toBe(true)
	end)

	it("despawn destroys the model, unregisters the entity and fires Despawned", function()
		fresh()
		local id, model = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		EnemyService.despawn(id)
		expect(bodyOf(model).destroyed).toBe(true)
		expect(model.Parent).toBeNil()
		expect(EntityService.get(id)).toBeNil()
		expect(EnemyService.brainOf(id)).toBeNil()
		expect(EnemyService.count()).toBe(0)
		expect(despawned).toHaveLength(1)
		expect(despawned[1].reason).toBe("Despawned")
		EnemyService.despawn(id) -- a second call is a no-op
		expect(despawned).toHaveLength(1)
	end)

	it("EntityService dropping the record fires Despawned with reason Unregistered", function()
		fresh()
		local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		EntityService.unregister(id)
		expect(despawned).toHaveLength(1)
		expect(despawned[1].reason).toBe("Unregistered")
		expect(EnemyService.count()).toBe(0)
	end)

	it("despawnAll clears the field", function()
		fresh()
		spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		spawnAt("KoboldAxeman", Vector3.new(10, 3, 0))
		spawnAt("FrenzyBoar", Vector3.new(20, 3, 0))
		expect(EnemyService.count()).toBe(3)
		EnemyService.despawnAll()
		expect(EnemyService.count()).toBe(0)
		expect(despawned).toHaveLength(3)
		expect(#EntityService.enemies()).toBe(0)
	end)

	it("the leash return forgets who hit it through EntityService.clearThreat", function()
		fresh()
		local id, model = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		putPlayer(5, Vector3.new(0, 3, -34))
		EntityService.addThreat(id, 5, 10)
		expect(advanceUntil(function()
			return phaseOf(id) == "Chase"
		end, 2)).toBe(true)
		expect(EntityService.threatOf(id)[5]).toBe(10)
		local body = bodyOf(model)
		body.position = Vector3.new(0, 3, -(BOAR.leashRange + 5))
		writeRoot(model, body)
		advance(TICK)
		expect(phaseOf(id)).toBe("Return")
		expect(EntityService.threatOf(id)[5]).toBeNil()
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The mover: MoveTo, re-issue, pathfinding
-- ------------------------------------------------------------------------------------------

describe("EnemyService mover", function()
	it("re-issues MoveTo only when the goal moved or the re-issue interval passed", function()
		fresh()
		local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		physicsEnabled = false
		putPlayer(1, Vector3.new(0, 3, -20))
		expect(advanceUntil(function()
			return phaseOf(id) == "Chase"
		end, 2)).toBe(true)
		local body = bodyOf(model)
		expect(advanceUntil(function()
			return #body.moveTos > 0
		end, 1)).toBe(true)
		local issued = #body.moveTos
		expect(issued).toBe(1)
		advance(AI.movement.reissueInterval - TICK * 2)
		expect(#body.moveTos).toBe(issued)
		advance(TICK * 4)
		expect(#body.moveTos).toBe(issued + 1)
		putPlayer(1, Vector3.new(0, 3, -24))
		advance(TICK)
		expect(#body.moveTos).toBe(issued + 2)
		expect(near(body.moveTos[#body.moveTos].position, Vector3.new(0, 3, -24))).toBe(true)
	end)

	it("a stuck body asks for a path and walks its waypoints to the end", function()
		fresh()
		local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		physicsEnabled = false
		local goal = Vector3.new(0, 3, -20)
		putPlayer(1, goal)
		pathResult = routeThrough({ Vector3.new(6, 3, -6), Vector3.new(6, 3, -14) }, true)
		expect(advanceUntil(function()
			return phaseOf(id) == "Chase"
		end, 2)).toBe(true)
		expect(pathCalls).toHaveLength(0)
		advance(AI.movement.stuckSeconds + TICK * 2)
		expect(#pathCalls).toBeGreaterThan(0)
		expect(near(pathCalls[1].from, Vector3.new(0, 3, 0))).toBe(true)
		expect(near(pathCalls[1].to, goal)).toBe(true)
		local body = bodyOf(model)
		-- The first waypoint is under the body and is passed; the second is the one issued.
		expect(near(body.moveTos[#body.moveTos].position, Vector3.new(6, 3, -6))).toBe(true)

		physicsEnabled = true
		expect(advanceUntil(function()
			return near(body.moveTos[#body.moveTos].position, Vector3.new(6, 3, -14))
		end, 3)).toBe(true)
		-- Progress alone does not drop the path: the body heads for the third waypoint, then the goal.
		expect(advanceUntil(function()
			return body.goal ~= nil and near(body.goal, goal)
		end, 4)).toBe(true)
		expect(advanceUntil(function()
			return phaseOf(id) == "WindUp"
		end, 6)).toBe(true)
	end)

	it("a goal beyond pathfindPastStuds asks for a path straight away and retries after a failure", function()
		fresh()
		local id, model = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -34))
		expect(advanceUntil(function()
			return phaseOf(id) == "Chase"
		end, 2)).toBe(true)
		local body = bodyOf(model)
		body.position = Vector3.new(0, 3, -(AI.pathfindPastStuds + BOAR.leashRange))
		writeRoot(model, body)
		pathResult = nil
		advance(TICK)
		expect(phaseOf(id)).toBe("Return")
		advance(TICK)
		expect(#pathCalls).toBe(1)
		expect(near(pathCalls[1].to, Vector3.new(0, 3, 0))).toBe(true)
		-- No path: it walks straight at home and asks again after pathFailRetry.
		expect(near(body.moveTos[#body.moveTos].position, Vector3.new(0, 3, 0))).toBe(true)
		expect(body.walkSpeed).toBeCloseTo(BOAR.moveSpeed * AI.leash.returnSpeedMultiplier, 1e-9)
		advance(AI.movement.pathFailRetry - TICK * 2)
		expect(#pathCalls).toBe(1)
		pathResult = routeThrough({ Vector3.new(0, 3, -60), Vector3.new(0, 3, -30) }, false)
		advance(TICK * 4)
		expect(#pathCalls).toBe(2)
		expect(near(body.moveTos[#body.moveTos].position, Vector3.new(0, 3, -60))).toBe(true)
	end)

	it("a path that finishes computing after the goal was dropped is discarded", function()
		fresh()
		local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		physicsEnabled = false
		local queue: { () -> () } = {}
		deferredPaths = queue
		putPlayer(1, Vector3.new(0, 3, -20))
		pathResult = routeThrough({ Vector3.new(6, 3, -6), Vector3.new(6, 3, -14) }, true)
		expect(advanceUntil(function()
			return phaseOf(id) == "Chase"
		end, 2)).toBe(true)
		advance(AI.movement.stuckSeconds + TICK * 2)
		expect(#queue).toBe(1) -- PathfindingService is still computing
		expect(#pathCalls).toBe(0)
		-- The player leaves: the brain idles and the mover stops before the path arrives.
		players = {}
		advance(TICK * 3)
		expect(phaseOf(id)).toBe("Idle")
		local body = bodyOf(model)
		expect(body.goal).toBeNil()
		local issued = #body.moveTos
		table.remove(queue, 1)()
		expect(#pathCalls).toBe(1)
		advance(TICK)
		expect(body.goal).toBeNil()
		expect(#body.moveTos).toBe(issued)
		-- The player is back: the first MoveTo goes straight at them, not along the stale waypoints.
		deferredPaths = nil
		pathResult = nil
		putPlayer(1, Vector3.new(0, 3, -20))
		expect(advanceUntil(function()
			return #body.moveTos > issued
		end, 2)).toBe(true)
		expect(near(body.moveTos[#body.moveTos].position, Vector3.new(0, 3, -20))).toBe(true)
	end)

	it("the sleeping brain's mover stops the body", function()
		fresh()
		local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		physicsEnabled = false
		putPlayer(1, Vector3.new(0, 3, -20))
		expect(advanceUntil(function()
			return phaseOf(id) == "Chase"
		end, 2)).toBe(true)
		local body = bodyOf(model)
		expect(advanceUntil(function()
			return body.goal ~= nil
		end, 1)).toBe(true)
		putPlayer(1, Vector3.new(0, 3, -(AI.sleepRadius + 50)))
		advance(AI.sleepCheckInterval + TICK * 2)
		expect(EnemyService.isAwake(id)).toBe(false)
		expect(body.goal).toBeNil()
		expect(body.stops).toBeGreaterThan(0)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The step accumulator
-- ------------------------------------------------------------------------------------------

describe("EnemyService step", function()
	it("runs whole ticks at tickHz and drops the backlog after a hitch", function()
		fresh()
		local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -20))
		local brain = EnemyService.brainOf(id)
		local ticks = 0
		local original = brain.tick
		brain.tick = function(self, dt)
			ticks += 1
			expect(dt).toBeCloseTo(TICK, 1e-9)
			return original(self, dt)
		end
		EnemyService.step(TICK * 0.5)
		expect(ticks).toBe(0)
		EnemyService.step(TICK * 0.5)
		expect(ticks).toBe(1)
		EnemyService.step(1.0)
		expect(ticks).toBe(1 + AI.maxTicksPerFrame)
		EnemyService.step(TICK)
		expect(ticks).toBe(2 + AI.maxTicksPerFrame)
	end)

	it("a brain that errors is reported and the others keep ticking", function()
		fresh()
		local broken = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		local healthy = spawnAt("KoboldAxeman", Vector3.new(10, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -20))
		EnemyService.brainOf(broken).tick = function()
			error("boom")
		end
		advance(1)
		expect(phaseOf(healthy)).never.toBe("Idle")
		local reported = false
		for _, line in Harness.warnings() do
			if line:find("brain of entity", 1, true) and line:find("boom", 1, true) then
				reported = true
			end
		end
		expect(reported).toBe(true)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Hold: the cinematic freeze (story beats, cutscenes) and the Studio dev hooks (D-120)
-- ------------------------------------------------------------------------------------------

local function lethalHit(attackerId: number, damage: number): any
	return {
		attackerId = attackerId,
		rawDamage = damage,
		gaugeDamage = 0,
		crit = false,
		parried = false,
		guarded = false,
		artId = "OneHandedSword.Horizontal",
		hitIndex = 1,
		hitStop = "Normal",
		position = { 0, 3, -2 },
	}
end

local function telegraphsOf(id: number): number
	local count = 0
	for _, payload in sentOf("Telegraph") do
		if payload.entityId == id then
			count += 1
		end
	end
	return count
end

describe("EnemyService hold", function()
	it("a held enemy sleeps at once, its mover stops, and a player next to it never wakes it", function()
		fresh()
		local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		physicsEnabled = false
		putPlayer(1, Vector3.new(0, 3, -20))
		expect(advanceUntil(function()
			return phaseOf(id) == "Chase" and bodyOf(model).goal ~= nil
		end, 3)).toBe(true)
		local body = bodyOf(model)
		local stops = body.stops
		expect(EnemyService.setHeld(id, true)).toBe(true)
		expect(EnemyService.isHeld(id)).toBe(true)
		expect(EnemyService.isAwake(id)).toBe(false)
		expect(EnemyService.brainOf(id):isAwake()).toBe(false)
		expect(body.goal).toBeNil()
		expect(body.stops).toBe(stops + 1)
		expect(EnemyService.heldIds()).toEqual({ id })
		-- The player walks right up to it: the sleep check runs many times and never wakes it.
		putPlayer(1, Vector3.new(0, 3, -3))
		local sentBefore = telegraphsOf(id)
		local issued = #body.moveTos
		advance(AI.sleepCheckInterval * 10)
		expect(EnemyService.isAwake(id)).toBe(false)
		expect(telegraphsOf(id)).toBe(sentBefore)
		expect(#body.moveTos).toBe(issued)
		expect(strikes).toHaveLength(0)
		expect(phaseOf(id)).toBe("Idle")
		-- Holding twice changes nothing.
		expect(EnemyService.setHeld(id, true)).toBe(true)
		expect(EnemyService.heldIds()).toEqual({ id })
	end)

	it("held in the middle of a wind-up, the strike never lands", function()
		fresh()
		local id = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -6))
		expect(advanceUntil(function()
			return phaseOf(id) == "WindUp"
		end, 5)).toBe(true)
		EnemyService.setHeld(id, true)
		advance(OVERHEAD.windUp + OVERHEAD.strike + OVERHEAD.recovery + 2)
		expect(strikes).toHaveLength(0)
		expect(EnemyService.isAwake(id)).toBe(false)
		-- The wind-up's timed Art state runs out on EntityService's clock as it would asleep.
		expect(EntityService.get(id).state).toBe("Idle")
	end)

	it("hits still land on a held enemy: HP, the stagger, and the kill path with reason Died", function()
		fresh()
		local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		putPlayer(1, Vector3.new(0, 3, -4))
		EnemyService.setHeld(id, true)
		local record = EntityService.get(id)
		local maxHp = record.maxHp
		local applied = EntityService.applyHit(id, lethalHit(77, 30))
		expect(applied.damage).toBeGreaterThan(0)
		expect(record.hp).toBeLessThan(maxHp)
		EntityService.setState(id, "Stagger", Combat.parryStagger)
		expect(phaseOf(id)).toBe("Interrupted")
		expect(EnemyService.isAwake(id)).toBe(false)
		advance(Combat.parryStagger + AI.sleepCheckInterval * 4)
		expect(record.state).toBe("Idle")
		expect(EnemyService.isAwake(id)).toBe(false)
		expect(telegraphsOf(id)).toBe(0)
		local killing = EntityService.applyHit(id, lethalHit(77, maxHp * 10))
		expect(killing.killed).toBe(true)
		expect(killing.hitStop).toBe("Kill")
		expect(despawned).toHaveLength(1)
		expect(despawned[1].id).toBe(id)
		expect(despawned[1].reason).toBe("Died")
		expect(EnemyService.isHeld(id)).toBe(false)
		expect(EnemyService.heldIds()).toEqual({})
		local died = sentOf("EntityDied")
		expect(died).toHaveLength(1)
		expect(died[1].entityId).toBe(id)
	end)

	it("a held enemy's HP never regenerates, so a low HP set up for a hit waits for it; release resumes", function()
		fresh()
		local held = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		local free = spawnAt("FrenzyBoar", Vector3.new(0, 3, 40))
		EnemyService.setHeld(held, true)
		expect(EntityService.setHp(held, 1)).toBe(1)
		expect(EntityService.setHp(free, 1)).toBe(1)
		advance(Combat.outOfCombatRegenDelay + 5)
		expect(EntityService.get(held).hp).toBe(1)
		expect(EntityService.get(free).hp).toBeGreaterThan(1) -- the regen rule itself still runs
		expect(EnemyService.setHeld(held, false)).toBe(true)
		advance(1)
		expect(EntityService.get(held).hp).toBeGreaterThan(1)
	end)

	it("an enemy that starts held under hold-new never regenerates either", function()
		fresh()
		EnemyService.setHoldNew(true)
		local id = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		expect(EntityService.setHp(id, 1)).toBe(1)
		advance(Combat.outOfCombatRegenDelay + 5)
		expect(EntityService.get(id).hp).toBe(1)
	end)

	it("a held enemy EnemyService lets go of while its record lives on (reset) regenerates again", function()
		fresh()
		local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		EnemyService.setHeld(id, true)
		expect(EntityService.setHp(id, 1)).toBe(1)
		EnemyService.reset()
		expect(EntityService.get(id)).toBeTruthy()
		advance(Combat.outOfCombatRegenDelay + 5)
		expect(EntityService.get(id).hp).toBeGreaterThan(1)
	end)

	it("release returns it to the sleep rules: near a player it wakes on the next tick and attacks", function()
		fresh()
		local near = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		local far = spawnAt("FrenzyBoar", Vector3.new(0, 3, AI.sleepRadius + 200))
		putPlayer(1, Vector3.new(0, 3, -20))
		EnemyService.setHeld(near, true)
		EnemyService.setHeld(far, true)
		advance(2)
		expect(EnemyService.setHeld(near, false)).toBe(true)
		expect(EnemyService.setHeld(far, false)).toBe(true)
		expect(EnemyService.isHeld(near)).toBe(false)
		expect(EnemyService.heldIds()).toEqual({})
		advance(TICK)
		expect(EnemyService.isAwake(near)).toBe(true)
		expect(EnemyService.isAwake(far)).toBe(false)
		expect(advanceUntil(function()
			return telegraphsOf(near) > 0
		end, 5)).toBe(true)
		expect(telegraphsOf(far)).toBe(0)
	end)

	it("setHeld on an id that is not a living enemy returns false and holds nothing", function()
		fresh()
		expect(EnemyService.setHeld(999, true)).toBe(false)
		local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		EntityService.die(id)
		expect(EnemyService.setHeld(id, true)).toBe(false)
		expect(EnemyService.heldIds()).toEqual({})
	end)

	it("hold-new makes every later spawn start held; earlier ones keep their own setting", function()
		fresh()
		putPlayer(1, Vector3.new(0, 3, -10))
		local before = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		expect(EnemyService.holdsNew()).toBe(false)
		EnemyService.setHoldNew(true)
		expect(EnemyService.holdsNew()).toBe(true)
		local after = spawnAt("KoboldAxeman", Vector3.new(4, 3, 0))
		expect(EnemyService.isHeld(before)).toBe(false)
		expect(EnemyService.isHeld(after)).toBe(true)
		expect(EnemyService.isAwake(after)).toBe(false)
		expect(phaseOf(after)).toBe("Idle")
		expect(advanceUntil(function()
			return telegraphsOf(before) > 0
		end, 5)).toBe(true)
		advance(3)
		expect(telegraphsOf(after)).toBe(0)
		EnemyService.setHoldNew(false)
		local later = spawnAt("FrenzyBoar", Vector3.new(-4, 3, 0))
		expect(EnemyService.isHeld(later)).toBe(false)
		expect(EnemyService.isHeld(after)).toBe(true) -- turning hold-new off releases nobody
	end)

	it("a PlaygroundService respawn comes back held under hold-new", function()
		fresh()
		local Playground = Harness.load("src/shared/data/playground")
		local PlaygroundService = Harness.load("src/server/services/PlaygroundService")
		PlaygroundService.bind({
			now = function()
				return clock.t
			end,
			entities = EntityService,
			enemies = EnemyService,
			weaponBuilder = nil,
			build = nil,
			players = nil,
			heartbeat = nil,
			waitForChild = function(parent, name)
				return parent:FindFirstChild(name)
			end,
			random = Random.new(5),
		} :: any)
		local first = PlaygroundService.spawnMember(1)
		expect(EnemyService.isHeld(first)).toBe(false)
		EnemyService.setHoldNew(true)
		EntityService.die(first)
		expect(PlaygroundService.pendingRespawns()).toBe(1)
		clock.t += Playground.respawnSeconds + 1
		PlaygroundService.tick(TICK)
		local alive = PlaygroundService.enemyIds()
		expect(alive).toHaveLength(1)
		expect(alive[1]).never.toBe(first)
		expect(EnemyService.isHeld(alive[1])).toBe(true)
		expect(EnemyService.isAwake(alive[1])).toBe(false)
		PlaygroundService.reset()
	end)

	it("reset forgets hold-new", function()
		fresh()
		EnemyService.setHoldNew(true)
		fresh()
		expect(EnemyService.holdsNew()).toBe(false)
		local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		expect(EnemyService.isHeld(id)).toBe(false)
	end)
end)

describe("EnemyService hit-stop (D-168)", function()
	it("bind hands CombatService the pause; reset takes it back", function()
		hitStopHooks = {}
		fresh()
		expect(hitStopHooks[#hitStopHooks]).toBe(EnemyService.pauseForHit)
		EnemyService.reset()
		expect(hitStopHooks[#hitStopHooks]).toBe(false)
	end)

	it("a hit during the kobold's wind-up pushes its strike and its Art state back by the hit-stop", function()
		local function strikeDelay(pause: number?): (number, number?, number)
			fresh()
			local id = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
			putPlayer(1, Vector3.new(0, 3, -4))
			advanceUntil(function()
				return phaseOf(id) == "WindUp"
			end, 5)
			local telegraphAt = clock.t - TICK
			advance(TICK * 2)
			local artUntil = EntityService.get(id).stateUntil
			local added = if pause ~= nil then EnemyService.pauseForHit(id, pause) else nil
			local shift = EntityService.get(id).stateUntil - artUntil
			advanceUntil(function()
				return #strikes > 0
			end, 3)
			return strikes[1].time - telegraphAt, added, shift
		end
		local plain = strikeDelay(nil)
		local paused, added, shift = strikeDelay(TICK * 2)
		expect(added).toBeCloseTo(TICK * 2, 1e-9)
		expect(paused - plain).toBeCloseTo(TICK * 2, 1e-6)
		expect(shift).toBeCloseTo(TICK * 2, 1e-9)
		expect(#sentOf("Telegraph")).toBe(1) -- the clients hear it on HitConfirmed, not a new telegraph
	end)

	it("nothing to pause: an unknown id, an enemy between attacks, a rush on its way", function()
		fresh()
		expect(EnemyService.pauseForHit(999, 0.05)).toBeNil()
		local id = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		expect(EnemyService.pauseForHit(id, 0.05)).toBeNil()
		putPlayer(1, Vector3.new(0, 3, -20))
		advanceUntil(function()
			return phaseOf(id) == "Strike"
		end, 5)
		expect(EnemyService.pauseForHit(id, 0.05)).toBe(0)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The stuck clock starts with each movement; a strike's own movement goes straight (D-183)
-- ------------------------------------------------------------------------------------------

-- A route over open ground the way PathfindingService returns it: it starts where the body stood
-- when it asked, with a waypoint every 4 studs to the goal.
local function straightRoute(from: Vector3, to: Vector3): { Vector3 }
	local waypoints = { from }
	local delta = to - from
	for index = 1, math.floor(delta.Magnitude / 4) do
		table.insert(waypoints, from + delta.Unit * (index * 4))
	end
	table.insert(waypoints, to)
	return waypoints
end

-- The engine's own order, one AI tick per frame: physics moves the bodies, then the Heartbeat
-- runs the service on where they stand (the shared `advance` runs physics after the step, which
-- leaves a step of motion the mover never saw). Path computations land `delay` seconds after they
-- were asked for (PathfindingService computes off the tick: in Studio a path took about 0.15 s).
local lateQueue: { any } = {}
local lateDelay = 0
local function deferPaths(delay: number)
	lateQueue = {}
	lateDelay = delay
	deferredPaths = {}
end

local function engineTick()
	clock.t += TICK
	physics(TICK)
	local due = {}
	for index = #lateQueue, 1, -1 do
		if lateQueue[index].at <= clock.t + 1e-9 then
			table.insert(due, 1, table.remove(lateQueue, index))
		end
	end
	for _, job in due do
		job.fn()
	end
	EnemyService.step(TICK)
	EntityService.tick(TICK)
	local queue = deferredPaths
	if queue ~= nil then
		for _, fn in queue do
			table.insert(lateQueue, { at = clock.t + lateDelay, fn = fn })
		end
		table.clear(queue)
	end
end

local function advanceLate(seconds: number)
	for _ = 1, math.max(1, math.floor(seconds / TICK + 0.5)) do
		engineTick()
	end
end

local function untilLate(predicate: () -> boolean, maxSeconds: number): boolean
	for _ = 1, math.ceil(maxSeconds / TICK) do
		if predicate() then
			return true
		end
		engineTick()
	end
	return predicate()
end

describe("EnemyService mover: each movement starts its own stuck clock (D-183)", function()
	it("a boar held, then released lined up, rushes straight down its line: no path, no step back", function()
		-- Studio a2: the body stood still longer than stuckSeconds, so the rush's first update read
		-- it as stuck, asked for a path, and walked back to the path's start once the path landed.
		for _, delay in { TICK, TICK * 3 } do
			fresh()
			pathResult = straightRoute
			deferPaths(delay)
			local id, model = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
			local body = bodyOf(model)
			local brain = EnemyService.brainOf(id)
			-- It wheels toward a player behind it first, so its mover has moved before the hold.
			putPlayer(1, Vector3.new(0, 3, 25))
			advanceLate(1.5)
			expect(phaseOf(id)).toBe("Chase")
			EnemyService.setHeld(id, true)
			advanceLate(AI.movement.stuckSeconds + 0.5)
			-- Released with the player straight down its line: it crouches at once.
			putPlayer(1, body.position + brain:getFacing() * 20)
			EnemyService.setHeld(id, false)
			local guard = 0
			while phaseOf(id) ~= "WindUp" and guard < 40 do
				advanceLate(TICK)
				guard += 1
			end
			expect(phaseOf(id)).toBe("WindUp")
			local moves = #body.moveTos
			local calls = #pathCalls
			while phaseOf(id) == "WindUp" do
				advanceLate(TICK)
			end
			expect(phaseOf(id)).toBe("Strike")
			local rush = brain.memory.rush
			local last = (body.position - rush.origin):Dot(rush.direction)
			while phaseOf(id) == "Strike" do
				advanceLate(TICK)
				local progress = (body.position - rush.origin):Dot(rush.direction)
				expect(progress).toBeGreaterThanOrEqual(last - 1e-6) -- never a step back down the line
				last = progress
			end
			advanceLate(TICK * 6) -- anything still computing lands
			expect(#pathCalls).toBe(calls) -- the rush never asked for a path
			expect(#body.moveTos).toBeGreaterThan(moves)
			for index = moves + 1, #body.moveTos do
				local move = body.moveTos[index]
				if move.time > clock.t - TICK * 7 then
					break -- the skid and after
				end
				-- Every MoveTo of the rush is the run's end, reach + overshoot down the line.
				expect((move.position - (rush.origin + rush.direction * rush.length)).Magnitude).toBeLessThan(1e-6)
			end
			expect(#sentOf("RushEnded")).toBe(0) -- it ran its line: no jam
		end
	end)

	it("every walk after a stand starts its own stuck clock: the chase, the wheel and a body really blocked", function()
		-- Each one moves first (so its mover has a progress clock), is held (the dev hold) for longer
		-- than stuckSeconds, and is released with its player where it will walk on, not attack: the
		-- Brute walks up, the Charger runs at a player beyond its charge band (straight ahead, or behind
		-- it so it wheels round first).
		local beyondBand = AI.archetypes.Charger.maxChargeDistance + 6
		local cases = {
			{
				defId = "KoboldAxeman",
				away = Vector3.new(0, 3, -24),
				release = function(_body: any, _brain: any): Vector3
					return Vector3.new(0, 0, -24)
				end,
			},
			{
				defId = "FrenzyBoar",
				away = Vector3.new(0, 3, 25),
				release = function(_body: any, brain: any): Vector3
					return brain:getFacing() * beyondBand
				end,
			},
			{
				defId = "FrenzyBoar",
				away = Vector3.new(0, 3, 25),
				release = function(_body: any, brain: any): Vector3
					return -brain:getFacing() * beyondBand
				end,
			},
		}
		for _, case in cases do
			for _, blocked in { false, true } do
				fresh()
				pathResult = straightRoute
				local id, model = spawnAt(case.defId, Vector3.new(0, 3, 0))
				local body = bodyOf(model)
				putPlayer(1, case.away)
				advanceLate(1.2)
				expect(phaseOf(id)).toBe("Chase")
				EnemyService.setHeld(id, true)
				advanceLate(AI.movement.stuckSeconds + 0.5)
				putPlayer(1, body.position + case.release(body, EnemyService.brainOf(id)))
				physicsEnabled = not blocked -- blocked: a wall stops every step from here on
				local moves = #body.moveTos
				local calls = #pathCalls
				EnemyService.setHeld(id, false)
				expect(untilLate(function()
					return #body.moveTos > moves
				end, 2)).toBe(true)
				local triedFrom = body.moveTos[moves + 1].time
				expect(untilLate(function()
					return #pathCalls > calls
				end, AI.movement.stuckSeconds + 0.5)).toBe(blocked)
				if blocked then
					-- Real stuck detection still works: the path comes after stuckSeconds of trying, not
					-- at the first step of the new walk.
					local askedAfter = pathCalls[calls + 1].time - triedFrom
					expect(askedAfter).toBeGreaterThanOrEqual(AI.movement.stuckSeconds - 1e-6)
					expect(askedAfter).toBeLessThanOrEqual(AI.movement.stuckSeconds + TICK * 2 + 1e-6)
				end
			end
		end
	end)

	it("a path that lands after the body moved on never walks it back to where it asked from", function()
		fresh()
		pathResult = straightRoute
		deferPaths(TICK * 8)
		local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		local body = bodyOf(model)
		putPlayer(1, Vector3.new(0, 3, -24))
		physicsEnabled = false
		expect(untilLate(function()
			return phaseOf(id) == "Chase" and body.goal ~= nil
		end, 2)).toBe(true)
		-- Stuck against something for stuckSeconds: it asks for a path, then slides free while the
		-- path computes and walks on toward the player.
		expect(untilLate(function()
			return #lateQueue > 0
		end, AI.movement.stuckSeconds + 1)).toBe(true)
		physicsEnabled = true
		local moves = #body.moveTos
		advanceLate(TICK * 12)
		expect(#pathCalls).toBe(1)
		local start = pathCalls[1].from
		for index = moves + 1, #body.moveTos do
			expect((body.moveTos[index].position - start).Magnitude).toBeGreaterThan(1e-3)
		end
		expect(body.position.Z).toBeLessThan(start.Z - AI.movement.waypointReach)
	end)

	it("a strike's own move goes straight however far or blocked; the walk after starts afresh", function()
		-- An idle kobold (its player beyond aggro, inside the sleep radius) keeps whatever goal it is
		-- handed, so the mover is driven through the brain's own calls.
		fresh()
		pathResult = straightRoute
		deferPaths(TICK * 4)
		local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		local body = bodyOf(model)
		local brain = EnemyService.brainOf(id)
		putPlayer(1, Vector3.new(0, 3, 120))
		advanceLate(0.5)
		expect(phaseOf(id)).toBe("Idle")
		physicsEnabled = false -- a wall in front from here on

		-- A walk to a point close by: stuck after stuckSeconds, it asks for a path (still computing).
		local near = body.position + Vector3.new(0, 0, -20)
		brain:moveToward(near, 10)
		expect(untilLate(function()
			return #pathCalls > 0
		end, AI.movement.stuckSeconds + 0.5)).toBe(true)
		-- A lunge before the path lands: straight at a point past the pathfinding range, never a path,
		-- however long the body stays blocked.
		local far = body.position + Vector3.new(0, 0, -(AI.pathfindPastStuds + 10))
		local calls = #pathCalls
		local moves = #body.moveTos
		brain:moveDirect(far, 20)
		EnemyService.step(0) -- the frame pass hands it to the mover in this frame
		expect(#body.moveTos).toBe(moves + 1)
		expect((body.moveTos[#body.moveTos].position - far).Magnitude).toBeLessThan(1e-6)
		advanceLate(AI.movement.stuckSeconds + 0.5) -- the walk's path lands meanwhile
		expect(#pathCalls).toBe(calls)
		for index = moves + 1, #body.moveTos do
			expect((body.moveTos[index].position - far).Magnitude).toBeLessThan(1e-6)
		end

		-- The walk again, still blocked: its own clock (no path for stuckSeconds) and nothing from the
		-- path the old walk asked for.
		moves = #body.moveTos
		brain:moveToward(near, 10)
		EnemyService.step(0)
		local walkedAt = clock.t
		expect((body.moveTos[moves + 1].position - near).Magnitude).toBeLessThan(1e-6)
		expect(untilLate(function()
			return #pathCalls > calls
		end, AI.movement.stuckSeconds + 0.5)).toBe(true)
		-- The path computes off the tick: it was asked for lateDelay before it ran.
		local landed = pathCalls[calls + 1].time
		expect(landed - lateDelay - walkedAt).toBeGreaterThanOrEqual(AI.movement.stuckSeconds - 1e-6)
		-- Until its own path lands, the walk heads straight for its goal: no waypoint of the old one.
		for index = moves + 1, #body.moveTos do
			if body.moveTos[index].time < landed then
				expect((body.moveTos[index].position - near).Magnitude).toBeLessThan(1e-6)
			end
		end
	end)
end)

-- ------------------------------------------------------------------------------------------
-- A path that lands late skips the waypoints the body already walked past (D-196)
-- ------------------------------------------------------------------------------------------

-- How far behind the body a MoveTo sent it, along `way` (0 when it was ahead).
local function behind(move: any, way: Vector3): number
	local flat = Vector3.new(way.X, 0, way.Z).Unit
	local ahead = Vector3.new(move.position.X - move.from.X, 0, move.position.Z - move.from.Z):Dot(flat)
	return math.max(0, -ahead)
end

describe("EnemyService mover: a late path skips the waypoints the body already passed (D-196)", function()
	it("a path that lands 0.05, 0.3, 0.5 or 1.0 s late never sends a walking body back", function()
		for _, delay in { 0.05, 0.3, 0.5, 1.0 } do
			fresh()
			pathResult = straightRoute
			deferPaths(delay)
			local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
			local body = bodyOf(model)
			local brain = EnemyService.brainOf(id)
			putPlayer(1, Vector3.new(0, 3, 120)) -- inside the sleep radius, beyond aggro: it idles
			advanceLate(0.5)
			expect(phaseOf(id)).toBe("Idle")
			-- A walk past the pathfinding range: it walks straight while each path computes, follows
			-- the path once it lands, and asks again every repathInterval.
			local goal = body.position + Vector3.new(0, 0, -(AI.pathfindPastStuds + 6))
			local moves = #body.moveTos
			local start = body.position
			for _ = 1, math.floor(4 / TICK) do
				brain:moveToward(goal, 14)
				engineTick()
			end
			expect(#pathCalls).toBeGreaterThanOrEqual(2) -- a path landed, and another while it followed it
			local worst = 0
			for index = moves + 1, #body.moveTos do
				local move = body.moveTos[index]
				worst = math.max(worst, behind(move, goal - move.from))
				if move.time >= pathCalls[1].time - 1e-9 then
					-- On a path, the next waypoint ahead: never one beyond it (the route has one every 4).
					expect((move.position - move.from).Magnitude).toBeLessThanOrEqual(4 + AI.movement.waypointReach)
				end
			end
			expect(worst).toBeLessThan(1)
			expect(body.position.Z).toBeLessThan(start.Z - 14 * (4 - TICK * 2)) -- it walked on all the while
		end
	end)

	it("a detour that goes back round an obstacle is walked as it came: a stuck body, and a walking one", function()
		-- A stuck body (it asked because the way ahead is blocked, and has walked nowhere since): the
		-- route backs off, then runs along the leg that passes beside it. Cutting to that leg would
		-- walk it into what blocked it.
		fresh()
		deferPaths(0.5)
		local id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		local body = bodyOf(model)
		local brain = EnemyService.brainOf(id)
		putPlayer(1, Vector3.new(0, 3, 120))
		advanceLate(0.5)
		local start = body.position
		local back = start + Vector3.new(0, 0, 3.5)
		pathResult = function(from: Vector3, to: Vector3): { Vector3 }
			return { from, back, start + Vector3.new(4, 0, -0.5), start + Vector3.new(4, 0, -8), to }
		end
		physicsEnabled = false
		local goal = start + Vector3.new(0, 0, -20)
		expect(untilLate(function()
			brain:moveToward(goal, 10)
			return #pathCalls > 0
		end, AI.movement.stuckSeconds + 1.5)).toBe(true)
		local landed = pathCalls[1].time
		local first: any = nil
		for _, move in body.moveTos do
			if move.time >= landed - 1e-9 then
				first = move
				break
			end
		end
		expect(first).never.toBeNil()
		expect(near(first.position, back)).toBe(true)

		-- A walking body whose route turns back round a wall it has not reached yet: the legs that go
		-- back are not legs it is on, so it walks back to their start.
		fresh()
		deferPaths(0.5)
		id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		body = bodyOf(model)
		brain = EnemyService.brainOf(id)
		putPlayer(1, Vector3.new(0, 3, 120))
		advanceLate(0.5)
		start = body.position
		goal = start + Vector3.new(0, 0, -(AI.pathfindPastStuds + 6))
		local turn = start + Vector3.new(0, 0, 6)
		pathResult = function(from: Vector3, to: Vector3): { Vector3 }
			return {
				from,
				from + Vector3.new(0, 0, 6),
				from + Vector3.new(10, 0, 6),
				from + Vector3.new(10, 0, -20),
				to,
			}
		end
		local moves = #body.moveTos
		expect(untilLate(function()
			brain:moveToward(goal, 14)
			return #pathCalls > 0
		end, 2)).toBe(true)
		expect(pathCalls[1].from.Z).toBeCloseTo(start.Z, 1e-6) -- it asked from where it stood
		first = nil
		for index = moves + 1, #body.moveTos do
			local move = body.moveTos[index]
			if move.time >= pathCalls[1].time - 1e-9 then
				first = move
				break
			end
		end
		expect(first).never.toBeNil()
		expect(first.from.Z).toBeLessThan(start.Z - 5) -- it had walked on 7 studs meanwhile
		expect(near(first.position, turn)).toBe(true)

		-- A walking body whose route steps sideways to a corridor before it runs on: the body is past
		-- the corridor's start along it and walked that way, but not on it, so it goes to its start.
		fresh()
		deferPaths(0.5)
		id, model = spawnAt("KoboldAxeman", Vector3.new(0, 3, 0))
		body = bodyOf(model)
		brain = EnemyService.brainOf(id)
		putPlayer(1, Vector3.new(0, 3, 120))
		advanceLate(0.5)
		start = body.position
		goal = start + Vector3.new(0, 0, -(AI.pathfindPastStuds + 6))
		local side = start + Vector3.new(8, 0, 0)
		pathResult = function(from: Vector3, to: Vector3): { Vector3 }
			return { from, from + Vector3.new(8, 0, 0), from + Vector3.new(8, 0, -20), to }
		end
		moves = #body.moveTos
		expect(untilLate(function()
			brain:moveToward(goal, 14)
			return #pathCalls > 0
		end, 2)).toBe(true)
		first = nil
		for index = moves + 1, #body.moveTos do
			local move = body.moveTos[index]
			if move.time >= pathCalls[1].time - 1e-9 then
				first = move
				break
			end
		end
		expect(first).never.toBeNil()
		expect(first.from.Z).toBeLessThan(start.Z - 5)
		expect(near(first.position, side)).toBe(true)
	end)
end)

describe("EnemyService.worldAhead: where the world stops a root (D-197)", function()
	-- A boar-sized root looking down -Z in the rushing group.
	local function rootModel(): (Model, BasePart)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2.4, 2.4, 5)
		root.CFrame = CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(0, 3, -1))
		root.CollisionGroup = AI.collision.rushing
		root.Parent = model
		model.PrimaryPart = root
		return model, root
	end

	it("casts the root's own box in its own group from where its front face is at the root's centre", function()
		local model, root = rootModel()
		local calls = {}
		local function cast(start: CFrame, size: Vector3, vector: Vector3, group: string, exclude: Instance): number?
			table.insert(calls, { start = start, size = size, vector = vector, group = group, exclude = exclude })
			return 4.5
		end
		-- Down its look (a tilted direction is flattened): half its length back.
		expect(EnemyService.worldAhead(model, Vector3.new(0, 0.5, -2), 10, cast)).toBe(4.5)
		local call = calls[1]
		expect(near(call.start.Position, Vector3.new(0, 3, 2.5))).toBe(true)
		expect(near(call.start.LookVector, root.CFrame.LookVector)).toBe(true)
		expect(call.size).toBe(root.Size)
		expect(near(call.vector, Vector3.new(0, 0, -10))).toBe(true)
		expect(call.group).toBe(AI.collision.rushing)
		expect(call.exclude).toBe(model)
		-- Across it: half its width back.
		EnemyService.worldAhead(model, Vector3.new(1, 0, 0), 3, cast)
		expect(near(calls[2].start.Position, Vector3.new(-1.2, 3, 0))).toBe(true)
		expect(near(calls[2].vector, Vector3.new(3, 0, 0))).toBe(true)
	end)

	it("nothing in the way, a failed cast, no root, no distance or no direction: nil", function()
		local model = rootModel()
		local cast = function(): number?
			return nil
		end
		expect(EnemyService.worldAhead(model, FORWARD, 10, cast)).toBeNil()
		expect(EnemyService.worldAhead(model, FORWARD, 10, function(): number?
			error("engine refused")
		end)).toBeNil()
		local called = false
		local counting = function(): number?
			called = true
			return 1
		end
		expect(EnemyService.worldAhead(model, FORWARD, 0, counting)).toBeNil()
		expect(EnemyService.worldAhead(model, Vector3.new(0, 1, 0), 10, counting)).toBeNil()
		expect(EnemyService.worldAhead(Instance.new("Model"), FORWARD, 10, counting)).toBeNil()
		expect(called).toBe(false)
	end)

	it("names a face the root climbs ground, not a wall: one within groundSlopeDegrees of up (D-204)", function()
		local model = rootModel()
		local slope = AI.collision.groundSlopeDegrees
		local function hitting(normal: Vector3?)
			return function(): (number?, Vector3?)
				return 4.5, normal
			end
		end
		-- A rise down the root's look (-Z): its face leans back toward the root (+Z) by its slope.
		local function rise(degrees: number): Vector3
			local up = math.rad(degrees)
			return Vector3.new(0, math.cos(up), math.sin(up))
		end
		local function ahead(normal: Vector3?): (number?, boolean?)
			return EnemyService.worldAhead(model, FORWARD, 10, hitting(normal))
		end
		-- Ground still says where the face is (a rush's line never resolves past it).
		for _, normal in { rise(14), rise(slope - 1) } do
			local face, ground = ahead(normal)
			expect(face).toBe(4.5)
			expect(ground).toBe(true)
		end
		-- A steeper rise, a wall, an overhang and a face named no way are walls.
		for _, normal in { rise(slope + 1), Vector3.new(0, 0, 1), rise(150) } do
			local face, ground = ahead(normal)
			expect(face).toBe(4.5)
			expect(ground).toBe(false)
		end
		local face, ground = ahead(nil)
		expect(face).toBe(4.5)
		expect(ground).toBe(false)
		expect(EnemyService.isGround(rise(slope - 1))).toBe(true)
		expect(EnemyService.isGround(rise(slope + 1))).toBe(false)
		expect(EnemyService.isGround(Vector3.zero)).toBe(false)
		expect(EnemyService.isGround(nil)).toBe(false)
	end)

	it("a brain asks through the engine with its own model; no engine cast is no world", function()
		fresh()
		local id, model = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		local brain = EnemyService.brainOf(id)
		local asked = {}
		(engine :: any).worldAhead = function(target: any, direction: Vector3, distance: number): number?
			table.insert(asked, { model = target, direction = direction, distance = distance })
			return 2
		end
		local result: number? = brain:worldAhead(FORWARD, 6);
		(engine :: any).worldAhead = nil
		expect(result).toBe(2)
		expect(#asked).toBe(1)
		expect(asked[1].model).toBe(model)
		expect(asked[1].distance).toBe(6)
		expect(brain:worldAhead(FORWARD, 6)).toBeNil()
	end)

	it("rootReach: how far the root's box reaches from its centre along a flattened direction (D-202)", function()
		local model, root = rootModel()
		-- (Part sizes are single precision.)
		expect(EnemyService.rootReach(model, FORWARD)).toBeCloseTo(2.5, 1e-4) -- half its length
		expect(EnemyService.rootReach(model, Vector3.new(0, 0.5, -2))).toBeCloseTo(2.5, 1e-4) -- flattened
		expect(EnemyService.rootReach(model, Vector3.new(-1, 0, 0))).toBeCloseTo(1.2, 1e-4) -- half its width
		-- Turned 30 degrees: its box's corner reach along the line.
		root.CFrame = CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(30), 0)
		local expected = 1.2 * math.sin(math.rad(30)) + 2.5 * math.cos(math.rad(30))
		expect(EnemyService.rootReach(model, FORWARD)).toBeCloseTo(expected, 1e-4)
		expect(EnemyService.rootReach(model, Vector3.new(0, 1, 0))).toBe(0) -- no direction
		expect(EnemyService.rootReach(Instance.new("Model"), FORWARD)).toBe(0) -- no root
	end)

	it("a brain's rootReach is its own root's, so a face it found stops its centre that far short", function()
		fresh()
		local id, model = spawnAt("FrenzyBoar", Vector3.new(0, 3, 0))
		local brain = EnemyService.brainOf(id)
		local root = model.PrimaryPart :: BasePart
		expect(brain:rootReach(root.CFrame.LookVector)).toBeCloseTo(root.Size.Z / 2, 1e-4)
		expect(brain:rootReach(root.CFrame.RightVector)).toBeCloseTo(root.Size.X / 2, 1e-4)
	end)
end)
