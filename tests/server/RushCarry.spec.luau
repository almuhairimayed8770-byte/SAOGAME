--!strict
--[[
	A stopped rush never carries a player (D-190), end to end: the real EnemyService, Charger,
	EntityService, CombatService, RigBuilder boar and CollisionGroups over a fake engine whose bodies
	have a velocity (they speed up and slow down at a Humanoid-like rate, so a stop is not instant),
	walls that can hold a body, and an overlap query over the real parts of every enemy and player.

	Every client draws a server body up to CLIENT_LAG late, while the body's collision group reaches
	it sooner. A rush that turns solid the tick its time runs out (still moving, or just past a
	player) is solid on a client that still draws it inside the player, and the engine pushes the
	player out at the rush's speed: up onto the boar's back. So:
	- a jammed rush stops its body where it jammed, and its line ends at its snout (D-195);
	- a stopped rush turns solid only once its root has stayed clear of every player and enemy for
	  ai.collision.rejoinClearSeconds, longer than CLIENT_LAG: no client still draws it inside anyone.
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
local RushWorld = Harness.load("src/shared/choreo/RushWorld")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Playground = Harness.load("src/shared/data/playground")
local CollectionService = Harness.game():GetService("CollectionService")

local TICK = AI.tickSeconds()
local FRAME = 1 / 60
local SUBSTEP = 1 / 240
local CLIENT_LAG = 0.3 -- engine fact: every client draws a server-owned body 0.2-0.3 s late
local ACCEL = 560 -- studs/s^2 a Humanoid-like body speeds up or slows down by
local GROUPS = AI.collision

type Body = {
	position: Vector3,
	velocity: Vector3,
	goal: Vector3?,
	walkSpeed: number,
	offsets: { [BasePart]: CFrame },
	moveTos: { { time: number, position: Vector3 } },
	stops: { number },
	history: { { t: number, position: Vector3 } },
}

-- Holds the model's root centre at most `at` studs along `along` from `origin`. With `face`, it is a
-- wall the world casts see (engine.worldAhead): its face stands `face` studs along, where the root's
-- front meets it; without, it is something only the body feels.
type Wall = { model: Model, origin: Vector3, along: Vector3, at: number, face: number? }

local clock = { t = 4000 }
local sent: { any } = {}
local bodies: { [Model]: Body } = {}
local walls: { Wall } = {}
local playerModels: { Model } = {}
local groupLog: { { time: number, model: Model, group: string } } = {}
local spans: { { time: number, from: number, to: number } } = {} -- every stretch the rush resolved

-- CombatService as the enemies see it, noting each stretch of a rush's line as it resolves.
local combat = setmetatable({
	enemyStrike = function(enemyId: number, attack: any, origin: Vector3, facing: Vector3, options: any?)
		if options ~= nil and options.span ~= nil then
			table.insert(spans, { time = clock.t, from = options.span.from, to = options.span.to })
		end
		return CombatService.enemyStrike(enemyId, attack, origin, facing, options)
	end,
}, { __index = CombatService })

local function record(remote: string, payload: any)
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

local function yawOf(model: Model): Vector3
	local align = EnemyService.alignOf(model)
	local look = if align ~= nil then align.CFrame.LookVector else (model.PrimaryPart :: BasePart).CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

-- Every part follows the root as built.
local function placeParts(model: Model, body: Body)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.lookAt(body.position, body.position + yawOf(model))
	for part, offset in body.offsets do
		part.CFrame = root.CFrame * offset
	end
end

-- A part's horizontal footprint (the bodies stand upright).
local function bounds(part: BasePart): (number, number, number, number)
	local half = part.Size / 2
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, 0, half.Z * z))
			minX, maxX = math.min(minX, corner.X), math.max(maxX, corner.X)
			minZ, maxZ = math.min(minZ, corner.Z), math.max(maxZ, corner.Z)
		end
	end
	return minX, maxX, minZ, maxZ
end

local function overlaps(a: BasePart, b: BasePart): boolean
	local ax0, ax1, az0, az1 = bounds(a)
	local bx0, bx1, bz0, bz1 = bounds(b)
	return ax0 < bx1 and bx0 < ax1 and az0 < bz1 and bz0 < az1
end

-- workspace:GetPartsInPart over every enemy and player part.
local function overlap(root: BasePart, exclude: Instance): { BasePart }
	local found = {}
	local function scan(model: Model)
		if model == exclude then
			return
		end
		for _, other in model:GetDescendants() do
			if other:IsA("BasePart") and overlaps(root, other) then
				table.insert(found, other)
			end
		end
	end
	for model in bodies do
		scan(model)
	end
	for _, model in playerModels do
		scan(model)
	end
	return found
end

local engine = {
	place = function(model: Model, cframe: CFrame)
		local root = model.PrimaryPart :: BasePart
		root.CFrame = CFrame.new()
		local offsets = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= root then
				offsets[part] = root.CFrame:ToObjectSpace(part.CFrame)
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
			moveTos = {},
			stops = {},
			history = {},
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
		local body = bodies[model]
		body.goal = position
		table.insert(body.moveTos, { time = clock.t, position = position })
	end,
	-- The real engine: Humanoid:MoveTo(root.Position). The body keeps its momentum and slows to rest.
	stop = function(model: Model)
		local body = bodies[model]
		body.goal = nil
		table.insert(body.stops, clock.t)
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
		table.insert(groupLog, { time = clock.t, model = model, group = group })
	end,
	bodyClear = function(model: Model): boolean
		return CollisionGroups.clear(model, overlap)
	end,
	-- The real engine casts the root's box from its centre along `direction` in its own group: here,
	-- how far ahead of the root's centre the face of a wall it runs into stands (nil: none within).
	worldAhead = function(model: Model, direction: Vector3, distance: number): number?
		local root = model.PrimaryPart :: BasePart
		local nearest: number? = nil
		for _, wall in walls do
			local face = wall.face
			local toward = direction:Dot(wall.along)
			if wall.model == model and face ~= nil and toward > 1e-6 then
				local gap = (face - (root.CFrame.Position - wall.origin):Dot(wall.along)) / toward
				if gap >= 0 and gap <= distance and (nearest == nil or gap < nearest) then
					nearest = gap
				end
			end
		end
		return nearest
	end,
}

local function physics(dt: number)
	local steps = math.max(1, math.floor(dt / SUBSTEP + 0.5))
	local h = dt / steps
	for _ = 1, steps do
		for model, body in bodies do
			local desired = Vector3.zero
			local goal = body.goal
			if goal ~= nil then
				local delta = goal - body.position
				delta = Vector3.new(delta.X, 0, delta.Z)
				if delta.Magnitude > 0.05 then
					desired = delta.Unit * math.min(body.walkSpeed, delta.Magnitude / h)
				end
			end
			local change = desired - body.velocity
			if change.Magnitude > ACCEL * h then
				change = change.Unit * ACCEL * h
			end
			body.velocity += change
			local nextPosition = body.position + body.velocity * h
			for _, wall in walls do
				if wall.model == model then
					local along = (nextPosition - wall.origin):Dot(wall.along)
					if along > wall.at then
						nextPosition -= wall.along * (along - wall.at)
						local into = body.velocity:Dot(wall.along)
						if into > 0 then
							body.velocity -= wall.along * into
						end
					end
				end
			end
			body.position = nextPosition
		end
	end
	for model, body in bodies do
		placeParts(model, body)
		table.insert(body.history, { t = clock.t, position = body.position })
	end
end

-- One server frame: physics first, then Heartbeat (the AI ticks and the frame pass).
local function frame()
	clock.t += FRAME
	physics(FRAME)
	EnemyService.step(FRAME)
	EntityService.tick(FRAME)
	CombatService.tick()
end

local function fresh()
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	clock.t = 4000
	sent = {}
	bodies = {}
	walls = {}
	playerModels = {}
	groupLog = {}
	spans = {}
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
		combat = combat,
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
end

local playerCount = 0
local function spawnPlayer(position: Vector3): (number, Model)
	playerCount += 1
	local model = Instance.new("Model")
	model.Name = "Trialist" .. playerCount
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CanCollide = true
	root.CFrame = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	CollisionGroups.assign(model, GROUPS.players)
	table.insert(playerModels, model)
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 950 + playerCount }
	return EntityService.registerPlayer(player :: any, model, Playground.loadout), model
end

local function movePlayer(model: Model, position: Vector3)
	(model.PrimaryPart :: BasePart).CFrame = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

local function phaseOf(id: number): string?
	local brain = EnemyService.brainOf(id)
	return if brain ~= nil then brain:getPhase() else nil
end

type Launch = { at: number, origin: Vector3, direction: Vector3, duration: number }

-- A boar at the origin looking down -Z and a player `distance` studs down its line; frames until
-- the rush launches.
local function launched(distance: number): (number, Model, Model, Launch)
	fresh()
	local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
	local boar = EnemyService.modelOf(boarId) :: Model
	local _, player = spawnPlayer(Vector3.new(0, 3, -distance))
	local guard = 0
	while #sentOf("RushStarted") == 0 and guard < 600 do
		frame()
		guard += 1
	end
	local started = sentOf("RushStarted")
	expect(#started).toBe(1)
	local payload = started[1].payload
	local launch: Launch = {
		at = payload.serverTime,
		origin = Vector3.new(payload.origin[1], payload.origin[2], payload.origin[3]),
		direction = Vector3.new(payload.direction[1], payload.direction[2], payload.direction[3]),
		duration = payload.duration,
	}
	return boarId, boar, player, launch
end

-- When the boar turned solid again after its rush (nil while it has not).
local function solidAt(boar: Model): number?
	for index = #groupLog, 1, -1 do
		local entry = groupLog[index]
		if entry.model == boar then
			return if entry.group == GROUPS.enemies then entry.time else nil
		end
	end
	return nil
end

-- Whether any client (drawing the body up to CLIENT_LAG late) still drew the boar's root inside the
-- player's at the moment it turned solid: its root at every server frame in the lag window.
local function drawnInside(boar: Model, player: Model, at: number, direction: Vector3): boolean
	local root = boar.PrimaryPart :: BasePart
	local probe = Instance.new("Part")
	probe.Size = root.Size
	for _, sample in bodies[boar].history do
		if sample.t >= at - CLIENT_LAG - 1e-9 and sample.t <= at + 1e-9 then
			probe.CFrame = CFrame.lookAt(sample.position, sample.position + direction)
			if overlaps(probe, player.PrimaryPart :: BasePart) then
				return true
			end
		end
	end
	return false
end

describe("A stopped rush never carries a player (D-190)", function()
	it(
		"the setting: only the boar's root and its blocker collide, and a client draws it up to CLIENT_LAG late",
		function()
			expect(GROUPS.rejoinClearSeconds).toBeGreaterThan(CLIENT_LAG)
			fresh()
			local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
			local boar = EnemyService.modelOf(boarId) :: Model
			local blockers = 0
			for _, part in boar:GetDescendants() do
				if part:IsA("BasePart") then
					if part.CollisionGroup == GROUPS.blockers then
						blockers += 1 -- the root's footprint, what players bump into (D-198)
						expect(part.CanCollide).toBe(true)
					else
						expect(part.CanCollide).toBe(part == boar.PrimaryPart)
					end
				end
			end
			expect(blockers).toBe(1)
		end
	)

	it("a jammed rush stops its body where it jammed; its line ends at its snout (D-195)", function()
		local boarId, boar, _, launch = launched(12)
		local body = bodies[boar]
		-- Something holds the body 2 studs down its line until the jam is told, then lets go.
		table.insert(walls, { model = boar, origin = launch.origin, along = launch.direction, at = 2 })
		local jammedAt: number? = nil
		while jammedAt == nil and phaseOf(boarId) == "Strike" do
			frame()
			for _, entry in sentOf("RushEnded") do
				if entry.payload.reason == "Jammed" then
					jammedAt = entry.time
				end
			end
		end
		expect(jammedAt).never.toBeNil()
		walls = {}
		local stoppedAt = body.position
		local movesBefore = #body.moveTos
		while phaseOf(boarId) == "Strike" do
			frame()
		end
		for _ = 1, 20 do
			frame()
		end
		expect(phaseOf(boarId)).toBe("Recover")
		-- Stopped on the jam's own frame, never sent down the line again, and it came to rest there.
		expect(table.find(body.stops, jammedAt :: number)).never.toBeNil()
		expect(#body.moveTos).toBe(movesBefore)
		expect((body.position - stoppedAt):Dot(launch.direction)).toBeLessThan(1)
		-- The player down the line, beyond the snout held 2 + front studs down it, was never hit.
		local hits = 0
		for _, entry in sentOf("HitConfirmed") do
			if entry.payload.attackerId == boarId then
				hits += 1
			end
		end
		expect(hits).toBe(0)
	end)

	it("a jam ends the rush's line at the body: walls 6, 8 and 10 studs down it, players at 5, 9 and 14", function()
		local speed = AI.rushSpeed(Enemies.byId("FrenzyBoar").attacks[1])
		local keepUp = AI.archetypes.Charger.keepUpStuds
		-- The rush with its snout held `wall` studs down the line (nil: no wall): which players it hit,
		-- and what it resolved and reported.
		local function run(wall: number?): ({ [number]: boolean }, { any }, number)
			fresh()
			local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
			local boar = EnemyService.modelOf(boarId) :: Model
			local front = EnemyService.bodyExtents(boar)
			local targetId, target = spawnPlayer(Vector3.new(0, 3, -14))
			local guard = 0
			while #sentOf("Telegraph") == 0 and guard < 600 do
				frame()
				guard += 1
			end
			local telegraph = sentOf("Telegraph")[1].payload
			local origin = Vector3.new(telegraph.origin[1], telegraph.origin[2], telegraph.origin[3])
			local direction = Vector3.new(telegraph.facing[1], 0, telegraph.facing[3]).Unit
			-- During the crouch: the target exactly 14 studs down the line, two more at 5 and 9.
			movePlayer(target, origin + direction * 14)
			local ids: { [number]: number } = { [14] = targetId }
			for _, along in { 5, 9 } do
				ids[along] = spawnPlayer(origin + direction * along)
			end
			if wall ~= nil then
				table.insert(walls, { model = boar, origin = origin, along = direction, at = wall - front })
			end
			while phaseOf(boarId) ~= "Recover" and guard < 2000 do
				frame()
				guard += 1
			end
			local hit: { [number]: boolean } = {}
			for along, id in ids do
				local count = 0
				for _, entry in sentOf("HitConfirmed") do
					if entry.payload.attackerId == boarId and entry.payload.targetId == id then
						count += 1
					end
				end
				expect(count <= 1).toBe(true)
				hit[along] = count == 1
			end
			return hit, sentOf("RushEnded"), front
		end
		local hit, ended, front = run(nil)
		expect(hit).toEqual({ [5] = true, [9] = true, [14] = true })
		expect(#ended).toBe(0)
		expect(spans[#spans].to).toBeCloseTo(speed * Enemies.byId("FrenzyBoar").attacks[1].strike + front, 1e-6)
		-- The player at 9 reaches back to 8 (its body's radius): a snout held at 8 touches it.
		for wall, expected in
			{
				[6] = { [5] = true, [9] = false, [14] = false },
				[8] = { [5] = true, [9] = true, [14] = false },
				[10] = { [5] = true, [9] = true, [14] = false },
			}
		do
			hit, ended, front = run(wall)
			expect(hit).toEqual(expected)
			-- Jammed once with its snout at the wall; no stretch past the snout by more than the frame
			-- it started late and keepUpStuds, and none after the report.
			expect(#ended).toBe(1)
			expect(ended[1].payload.reason).toBe("Jammed")
			expect(ended[1].payload.distance + front).toBeCloseTo(wall, 0.05)
			for _, span in spans do
				expect(span.to).toBeLessThanOrEqual(wall + speed * FRAME + keepUp)
				expect(span.time).toBeLessThanOrEqual(ended[1].time + 1e-9)
			end
		end
	end)

	it(
		"a wall the root runs into ends the line at its face (D-197): wall 8 studs down it, players at 5, 6.5, 9.5, 12",
		function()
			-- Only the root collides (the setting above), so the snout runs on through the wall face by
			-- front - the root's half length while the root is held at it: the line must stop at the face.
			local speed = AI.rushSpeed(Enemies.byId("FrenzyBoar").attacks[1])
			local function run(face: number): ({ [number]: boolean }, { any }, number)
				fresh()
				local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
				local boar = EnemyService.modelOf(boarId) :: Model
				local front = EnemyService.bodyExtents(boar)
				local rootHalf = (boar.PrimaryPart :: BasePart).Size.Z / 2
				local targetId, target = spawnPlayer(Vector3.new(0, 3, -12))
				local guard = 0
				while #sentOf("Telegraph") == 0 and guard < 600 do
					frame()
					guard += 1
				end
				local telegraph = sentOf("Telegraph")[1].payload
				local origin = Vector3.new(telegraph.origin[1], telegraph.origin[2], telegraph.origin[3])
				local direction = Vector3.new(telegraph.facing[1], 0, telegraph.facing[3]).Unit
				movePlayer(target, origin + direction * 12)
				local ids: { [number]: number } = { [12] = targetId }
				for _, along in { 5, 6.5, 9.5 } do
					ids[along] = spawnPlayer(origin + direction * along)
				end
				table.insert(
					walls,
					{ model = boar, origin = origin, along = direction, at = face - rootHalf, face = face }
				)
				-- Up to the recovery, or the slam's daze (D-208).
				while phaseOf(boarId) ~= "Recover" and phaseOf(boarId) ~= "Interrupted" and guard < 2000 do
					frame()
					guard += 1
				end
				local hit: { [number]: boolean } = {}
				for along, id in ids do
					local count = 0
					for _, entry in sentOf("HitConfirmed") do
						if entry.payload.attackerId == boarId and entry.payload.targetId == id then
							count += 1
						end
					end
					hit[along] = count == 1
				end
				expect(front - rootHalf).toBeGreaterThan(2) -- the snout reaches well past the root's front
				return hit, sentOf("RushEnded"), front
			end
			for _, face in { 8, 7.5 } do
				local hit, ended = run(face)
				expect(hit).toEqual({ [5] = true, [6.5] = true, [9.5] = false, [12] = false })
				-- A slam with the snout on the face (D-205), then the daze's stop at that same spot (D-210);
				-- no stretch past the face.
				expect(#ended).toBe(2)
				expect(ended[1].payload.reason).toBe("Wall")
				-- The snout a slam rests on the face: the farthest the body reaches in any pose its rush draws
				-- it in (D-437).
				local slamFront = RushWorld.front((RushWorld.bodyOf(RigBuilder.build("Boar")) :: any).poses)
				expect(ended[1].payload.distance + slamFront).toBeCloseTo(face, 0.05)
				expect(ended[2].payload.reason).toBe("Interrupted")
				expect(ended[2].payload.distance).toBeCloseTo(ended[1].payload.distance, 1e-6)
				for _, span in spans do
					expect(span.to).toBeLessThanOrEqual(face + 1e-3)
				end
			end
			-- A wall beyond the run's reach changes nothing: the free line, to its clock's end.
			local hit = run(40)
			expect(hit).toEqual({ [5] = true, [6.5] = true, [9.5] = true, [12] = true })
			expect(spans[#spans].to).toBeGreaterThan(speed * Enemies.byId("FrenzyBoar").attacks[1].strike)
		end
	)

	it(
		"a wall the cast sees ends the rush at once (D-202): faces 6, 8 and 10, told before the root gets there",
		function()
			for face, expected in
				{
					[6] = { [5] = true, [6.5] = true, [9.5] = false, [12] = false },
					[8] = { [5] = true, [6.5] = true, [9.5] = false, [12] = false },
					[10] = { [5] = true, [6.5] = true, [9.5] = true, [12] = false },
				}
			do
				fresh()
				local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
				local boar = EnemyService.modelOf(boarId) :: Model
				local rootHalf = (boar.PrimaryPart :: BasePart).Size.Z / 2
				local targetId, target = spawnPlayer(Vector3.new(0, 3, -12))
				local guard = 0
				while #sentOf("Telegraph") == 0 and guard < 600 do
					frame()
					guard += 1
				end
				local telegraph = sentOf("Telegraph")[1].payload
				local origin = Vector3.new(telegraph.origin[1], telegraph.origin[2], telegraph.origin[3])
				local direction = Vector3.new(telegraph.facing[1], 0, telegraph.facing[3]).Unit
				movePlayer(target, origin + direction * 12)
				local ids: { [number]: number } = { [12] = targetId }
				for _, along in { 5, 6.5, 9.5 } do
					ids[along] = spawnPlayer(origin + direction * along)
				end
				table.insert(
					walls,
					{ model = boar, origin = origin, along = direction, at = face - rootHalf, face = face }
				)
				local body = bodies[boar]
				local movesAtReport: number? = nil
				local maxSnout = -math.huge
				local front = EnemyService.bodyExtents(boar)
				-- Up to the slam's daze (D-208), which interrupts the strike once the timeline brings the
				-- snout to the face.
				while phaseOf(boarId) ~= "Recover" and phaseOf(boarId) ~= "Interrupted" and guard < 2000 do
					frame()
					guard += 1
					if movesAtReport == nil and #sentOf("RushEnded") > 0 then
						movesAtReport = #body.moveTos
					end
					maxSnout = math.max(maxSnout, (body.position - origin):Dot(direction) + front)
				end
				expect(phaseOf(boarId)).toBe("Interrupted")
				-- What the rush did with the body, up to its daze. Still in the rushing group: it stopped
				-- with players under it, who now step off to the side.
				local movesAtRecover = #body.moveTos
				expect(solidAt(boar)).toBeNil()
				for _, model in playerModels do
					movePlayer(model, (model.PrimaryPart :: BasePart).CFrame.Position + Vector3.new(12, 0, 0))
				end
				local clearFrom = clock.t
				local limit = clock.t + 2
				while solidAt(boar) == nil and clock.t < limit do
					frame()
				end
				-- Which players it hit: exactly D-197's line, which still ends at the face.
				for along, id in ids do
					local count = 0
					for _, entry in sentOf("HitConfirmed") do
						if entry.payload.attackerId == boarId and entry.payload.targetId == id then
							count += 1
						end
					end
					expect(count == 1).toBe(expected[along])
				end
				-- A slam told once, on the frame the first stretch met the face, with the body's stop: its
				-- snout on the face (D-205), then the daze's stop at that same spot (D-210). Nothing resolved
				-- after it, and nothing past the face.
				local ended = sentOf("RushEnded")
				expect(#ended).toBe(2)
				expect(ended[1].payload.reason).toBe("Wall")
				-- The snout a slam rests on the face: the farthest the body reaches in any pose its rush draws
				-- it in (D-437).
				local slamFront = RushWorld.front((RushWorld.bodyOf(boar) :: any).poses)
				expect(ended[1].payload.distance + slamFront).toBeCloseTo(face, 1e-3)
				expect(ended[2].payload.reason).toBe("Interrupted")
				expect(ended[2].payload.distance).toBeCloseTo(ended[1].payload.distance, 1e-6)
				-- The line resolves on the clock up to the face, where every client draws the snout, and no
				-- further: the slam is told no later than that, and dazes the body once it is there.
				local cappedAt: number? = nil
				for _, span in spans do
					expect(span.to).toBeLessThanOrEqual(face + 1e-3)
					if cappedAt == nil and span.to >= face - 1e-3 then
						cappedAt = span.time
					end
				end
				expect(cappedAt).never.toBeNil()
				expect(ended[1].time).toBeLessThanOrEqual((cappedAt :: number) + 1e-9)
				for _, span in spans do
					expect(span.time).toBeLessThanOrEqual(ended[2].time + 1e-9)
				end
				-- The world never had to stop it: its root's front stays front - rootHalf short of the face
				-- (the snout is on it), but for the mover's own overshoot of a goal (STUDIO_TASKS item 199).
				for _, sample in body.history do
					expect((sample.position - origin):Dot(direction) + rootHalf).toBeLessThan(face - 2)
				end
				expect(maxSnout).toBeLessThan(face + 0.7)
				-- Sent to that stop and never further; it rests there.
				local stop = origin + direction * ended[1].payload.distance
				for index = (movesAtReport :: number) + 1, movesAtRecover do
					local goal = body.moveTos[index].position
					expect((goal - origin):Dot(direction)).toBeLessThanOrEqual(ended[1].payload.distance + 1e-6)
				end
				expect(((body.position - stop) * Vector3.new(1, 0, 1)).Magnitude).toBeLessThan(0.05)
				-- And turned solid only after the rejoin wait once clear (D-190).
				local at = solidAt(boar)
				expect(at).never.toBeNil()
				expect((at :: number) - clearFrom).toBeGreaterThan(GROUPS.rejoinClearSeconds - TICK - FRAME)
				expect((at :: number) - clearFrom).toBeLessThan(GROUPS.rejoinClearSeconds + TICK + FRAME)
			end
		end
	)

	it("a rush that ran its time turns solid only when no client still draws its root in a player", function()
		for _, distance in { 12, 14, 16, 18 } do
			local boarId, boar, player, launch = launched(distance)
			local limit = clock.t + 3
			while solidAt(boar) == nil and clock.t < limit do
				frame()
			end
			local at = solidAt(boar)
			expect(at).never.toBeNil()
			expect(phaseOf(boarId)).toBe("Recover") -- solid again before it moves off
			expect(drawnInside(boar, player, at :: number, launch.direction)).toBe(false)
			-- Turned solid within a tick of the clear window after the body stopped, not later.
			local ended = launch.at + launch.duration
			expect((at :: number) - ended).toBeLessThan(GROUPS.rejoinClearSeconds + 2 * TICK + FRAME)
		end
	end)

	it("a jammed rush that let go turns solid only when no client still draws its root in a player", function()
		for _, distance in { 10, 12, 14 } do
			local boarId, boar, player, launch = launched(distance)
			table.insert(walls, { model = boar, origin = launch.origin, along = launch.direction, at = 3 })
			local releaseAt = clock.t + 0.25
			local limit = clock.t + 3
			while solidAt(boar) == nil and clock.t < limit do
				frame()
				if clock.t >= releaseAt then
					walls = {}
				end
			end
			local at = solidAt(boar)
			expect(at).never.toBeNil()
			-- Solid again before it moves off: still in its attack, standing where it jammed. A jam told
			-- by a blocked step (D-280) starts the rejoin wait soon enough that it may still be in Strike.
			local phase = phaseOf(boarId)
			expect(phase == "Strike" or phase == "Recover").toBe(true)
			local jam: number? = nil
			for _, entry in sentOf("RushEnded") do
				if entry.payload.reason == "Jammed" then
					jam = entry.time
				end
			end
			expect(jam).never.toBeNil()
			local first: Vector3? = nil
			for _, sample in bodies[boar].history do
				if sample.t >= (jam :: number) + FRAME - 1e-9 and sample.t <= (at :: number) + 1e-9 then
					first = first or sample.position
					expect((sample.position - (first :: Vector3)).Magnitude).toBeLessThan(0.05)
				end
			end
			expect(first).never.toBeNil()
			expect(drawnInside(boar, player, at :: number, launch.direction)).toBe(false)
		end
	end)

	it(
		"a body resting on a player stays in the rushing group, and turns solid only once clear for the window",
		function()
			-- The run's end (reach + overshoot = 22 studs) is the player's spot: the body rests over them.
			local boarId, boar, player, launch = launched(22)
			local ended = launch.at + launch.duration
			while clock.t < ended + 0.5 do
				frame()
				expect(solidAt(boar)).toBeNil()
			end
			expect(phaseOf(boarId)).toBe("Recover")
			-- The player steps off to the side: the body is clear from this frame on.
			movePlayer(player, launch.origin + launch.direction * 22 + Vector3.new(8, 0, 0))
			local clearFrom = clock.t
			while solidAt(boar) == nil and clock.t < clearFrom + 2 do
				frame()
			end
			local at = solidAt(boar)
			expect(at).never.toBeNil()
			expect((at :: number) - clearFrom).toBeGreaterThan(GROUPS.rejoinClearSeconds - TICK - FRAME)
			expect((at :: number) - clearFrom).toBeLessThan(GROUPS.rejoinClearSeconds + TICK + FRAME)
		end
	)

	it(
		"a body that stops over a packmate's footprint turns solid only once the two blockers stand apart (D-281)",
		function()
			-- A held boar stands down the line, facing the same way, just past where the run ends (reach
			-- + overshoot = 22 studs): the roots never meet, but the rusher's snout stands over the held
			-- boar's haunches. Solid there, the two blockers would meet inside each other and the engine
			-- would push them apart. The player steps on, far down the line, so the rusher keeps facing
			-- it (and the packmate) through its recovery.
			local boarId, boar, player, launch = launched(14)
			movePlayer(player, launch.origin + launch.direction * 60)
			local ahead = 6.5
			local restAt = launch.origin + launch.direction * (22 + ahead)
			local heldId = EnemyService.spawn("FrenzyBoar", CFrame.lookAt(restAt, restAt + launch.direction))
			expect(EnemyService.setHeld(heldId, true)).toBe(true)
			local held = EnemyService.modelOf(heldId) :: Model
			local function blockerOf(model: Model): BasePart
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and part.CollisionGroup == GROUPS.blockers then
						return part
					end
				end
				error("no blocker")
			end
			local own, theirs = blockerOf(boar), blockerOf(held)
			expect(theirs.CanCollide).toBe(true)
			local ended = launch.at + launch.duration
			while clock.t < ended + GROUPS.rejoinClearSeconds + 0.5 do
				frame()
			end
			expect(phaseOf(boarId)).toBe("Recover")
			-- At rest where the run ended: roots apart, footprints over each other.
			expect(overlaps(boar.PrimaryPart :: BasePart, held.PrimaryPart :: BasePart)).toBe(false)
			expect(overlaps(own, theirs)).toBe(true)
			expect(solidAt(boar)).toBeNil()
			expect(own.CanCollide).toBe(false)
			-- The packmate steps aside: the rusher turns solid one clear window later.
			EnemyService.setHeld(heldId, false)
			EnemyService.setHeld(heldId, true)
			local aside = restAt + Vector3.new(12, 0, 0)
			bodies[held].position = aside
			placeParts(held, bodies[held])
			expect(overlaps(own, theirs)).toBe(false)
			local clearFrom = clock.t
			while solidAt(boar) == nil and clock.t < clearFrom + 2 do
				frame()
			end
			local at = solidAt(boar)
			expect(at).never.toBeNil()
			expect((at :: number) - clearFrom).toBeGreaterThan(GROUPS.rejoinClearSeconds - TICK - FRAME)
			expect((at :: number) - clearFrom).toBeLessThan(GROUPS.rejoinClearSeconds + TICK + FRAME)
			expect(drawnInside(boar, player, at :: number, launch.direction)).toBe(false)
		end
	)

	it("blockerClear judges the blockers' own boxes: turned, side by side, stacked, or switched off (D-281)", function()
		fresh()
		local aId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
		local bId = EnemyService.spawn("FrenzyBoar", CFrame.new(40, 3, 0))
		EnemyService.setHeld(aId, true)
		EnemyService.setHeld(bId, true)
		local a, b = EnemyService.modelOf(aId) :: Model, EnemyService.modelOf(bId) :: Model
		local function blockerOf(model: Model): BasePart
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.CollisionGroup == GROUPS.blockers then
					return part
				end
			end
			error("no blocker")
		end
		local blockerA, blockerB = blockerOf(a), blockerOf(b)
		local function pose(model: Model, position: Vector3, degrees: number)
			local yaw = math.rad(degrees)
			EnemyService.applyFacing(model, Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)))
			bodies[model].position = position
			placeParts(model, bodies[model])
		end
		-- The oracle: two footprints (convex quads) overlap when an edge of one crosses an edge of the
		-- other or one holds a corner of the other, and the two spans overlap in height.
		local function corners(part: BasePart): { Vector2 }
			local half = part.Size / 2
			local list = {}
			for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
				local p = part.CFrame:PointToWorldSpace(Vector3.new(half.X * c[1], 0, half.Z * c[2]))
				table.insert(list, Vector2.new(p.X, p.Z))
			end
			return list
		end
		local function cross(o: Vector2, p: Vector2, q: Vector2): number
			return (p.X - o.X) * (q.Y - o.Y) - (p.Y - o.Y) * (q.X - o.X)
		end
		local function inside(point: Vector2, quad: { Vector2 }): boolean
			for i = 1, 4 do
				if cross(quad[i], quad[i % 4 + 1], point) <= 0 then
					return false
				end
			end
			return true
		end
		local function crosses(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2): boolean
			local d1, d2 = cross(q1, q2, p1), cross(q1, q2, p2)
			local d3, d4 = cross(p1, p2, q1), cross(p1, p2, q2)
			return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))
		end
		local function oracle(): boolean
			local ya, yb = blockerA.CFrame.Position.Y, blockerB.CFrame.Position.Y
			if math.abs(ya - yb) >= (blockerA.Size.Y + blockerB.Size.Y) / 2 then
				return false
			end
			local qa, qb = corners(blockerA), corners(blockerB)
			-- Wind both counter-clockwise for `inside`.
			for _, quad in { qa, qb } do
				if cross(quad[1], quad[2], quad[3]) < 0 then
					quad[2], quad[4] = quad[4], quad[2]
				end
			end
			for i = 1, 4 do
				-- Corners, and points along each edge (an edge lying along the other's edge holds none of
				-- the other's corners strictly inside, and crosses none of its edges).
				for _, t in { 0, 0.25, 0.5, 0.75 } do
					if inside(qa[i]:Lerp(qa[i % 4 + 1], t), qb) or inside(qb[i]:Lerp(qb[i % 4 + 1], t), qa) then
						return true
					end
				end
				for j = 1, 4 do
					if crosses(qa[i], qa[i % 4 + 1], qb[j], qb[j % 4 + 1]) then
						return true
					end
				end
			end
			return false
		end
		pose(a, Vector3.new(0, 3, 0), 0)
		local width = blockerA.Size.X
		-- Side by side: a hair apart is clear, a hair over is not.
		pose(b, Vector3.new(width + 0.2, 3, 0), 0)
		expect(EnemyService.blockerClear(a)).toBe(true)
		pose(b, Vector3.new(width - 0.2, 3, 0), 0)
		expect(EnemyService.blockerClear(a)).toBe(false)
		expect(EnemyService.blockerClear(b)).toBe(false)
		-- Stacked out of reach in height, or switched off (rushing), it is clear.
		pose(b, Vector3.new(width - 0.2, 3 + blockerA.Size.Y + 0.1, 0), 0)
		expect(EnemyService.blockerClear(a)).toBe(true)
		pose(b, Vector3.new(width - 0.2, 3, 0), 0)
		blockerB.CanCollide = false
		expect(EnemyService.blockerClear(a)).toBe(true)
		blockerB.CanCollide = true
		-- Turned: the boxes themselves, not their bounding boxes, against the oracle.
		local apart, met = 0, 0
		for _, degrees in { 0, 30, 45, 60, 90, 135 } do
			for x = -10, 10, 1.25 do
				for z = -14, 14, 1.25 do
					pose(b, Vector3.new(x, 3, z), degrees)
					local expected = not oracle()
					expect(EnemyService.blockerClear(a)).toBe(expected)
					if expected then
						apart += 1
					else
						met += 1
					end
				end
			end
		end
		expect(apart).toBeGreaterThan(100)
		expect(met).toBeGreaterThan(100)
	end)

	it("blockerClear meets every face: a kobold's axe face counts as its body's does (D-281, D-315)", function()
		fresh()
		local koboldId = EnemyService.spawn("KoboldAxeman", CFrame.new(0, 3, 0))
		local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(40, 3, 0))
		EnemyService.setHeld(koboldId, true)
		EnemyService.setHeld(boarId, true)
		local kobold, boar = EnemyService.modelOf(koboldId) :: Model, EnemyService.modelOf(boarId) :: Model
		local body, axe = kobold:FindFirstChild("Blocker") :: BasePart, kobold:FindFirstChild("HeldBlocker") :: BasePart
		expect(body).never.toBeNil()
		expect(axe).never.toBeNil()
		expect(axe.CanCollide).toBe(true)
		local boarFace = boar:FindFirstChild("Blocker") :: BasePart
		-- The boar side-on beside the kobold's axe face, clear of its body face: its blocker over the
		-- axe's alone, then a stud past it.
		local function place(position: Vector3)
			EnemyService.applyFacing(boar, Vector3.new(1, 0, 0))
			bodies[boar].position = position
			placeParts(boar, bodies[boar])
		end
		local function partsOverlap(a: BasePart, b: BasePart): boolean
			local offset = b.CFrame:PointToObjectSpace(a.CFrame.Position)
			local reach = a.Size / 2
			local half = b.Size / 2
			return math.abs(offset.X) < half.X + reach.Z and math.abs(offset.Z) < half.Z + reach.X
		end
		local axeAt = axe.CFrame.Position
		local bodyAt = body.CFrame.Position
		local away = Vector3.new(axeAt.X - bodyAt.X, 0, axeAt.Z - bodyAt.Z).Unit
		local found = false
		for step = 0, 40 do
			place(Vector3.new(axeAt.X, 3, axeAt.Z) + away * (step * 0.25))
			if partsOverlap(boarFace, axe) and not partsOverlap(boarFace, body) then
				found = true
				break
			end
		end
		expect(found).toBe(true)
		expect(EnemyService.blockerClear(boar)).toBe(false)
		-- Moved off the axe's face too, it is clear.
		place(Vector3.new(axeAt.X, 3, axeAt.Z) + away * 20)
		expect(EnemyService.blockerClear(boar)).toBe(true)
	end)

	it(
		"a slam's body waits to rejoin from the stop that ends its rush, never from the slam's report (D-210)",
		function()
			-- Nobody under it: the wait is the window alone. The slam is told while the body is still on its
			-- way to the face (passing through whoever stands there, D-167); its daze ends the rush there.
			local boarId, boar, _, launch = launched(20)
			local rootHalf = (boar.PrimaryPart :: BasePart).Size.Z / 2
			local face = 10
			table.insert(
				walls,
				{ model = boar, origin = launch.origin, along = launch.direction, at = face - rootHalf, face = face }
			)
			local limit = clock.t + 3
			while phaseOf(boarId) ~= "Interrupted" and clock.t < limit do
				frame()
			end
			local ended = sentOf("RushEnded")
			expect(#ended).toBe(2)
			expect(ended[1].payload.reason).toBe("Wall")
			expect(ended[2].payload.reason).toBe("Interrupted")
			expect(ended[2].time).toBeGreaterThan(ended[1].time)
			expect(solidAt(boar)).toBeNil()
			while solidAt(boar) == nil and clock.t < limit do
				frame()
			end
			local at = solidAt(boar)
			expect(at).never.toBeNil()
			expect((at :: number) - ended[2].time).toBeGreaterThan(GROUPS.rejoinClearSeconds - 1e-6)
			expect((at :: number) - ended[2].time).toBeLessThan(GROUPS.rejoinClearSeconds + TICK + FRAME)
		end
	)
end)
