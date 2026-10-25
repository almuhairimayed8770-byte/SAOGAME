--!strict
--[[
	A rush that slams a wall rests where its RushEnded says (D-208, D-210), and the body never
	walks its snout into that wall afterwards (D-278, D-279), end to end: the real EnemyService,
	Charger, EntityService and CombatService over a RigBuilder boar, at 30 and 60 server frames a
	second. The fake engine moves velocity bodies (a body accelerates toward its MoveTo goal, as a
	Humanoid does, and skids past a goal it reaches at speed) on a 240 Hz physics step; a wall is a
	plane that pushes the root's box out of it, and the server's Blockcast sees it.
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
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local AI = Harness.load("src/shared/data/ai")
local Playground = Harness.load("src/shared/data/playground")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

-- The fake engine's physics: a Humanoid-like body reaches its walk speed in a twentieth of a
-- second (or slower, `acceleration`; at `speedScale` of it) and pushes out of walls on every 240 Hz
-- step.
local PHYSICS_STEP = 1 / 240
local FLOOR_GAP = 1e-9
local physicsTuning = { acceleration = 560, speedScale = 1 }

-- A wall: free space where (x - point):Dot(out) >= 0. `seen`: the server's Blockcast meets it (a
-- wall it misses still stops the root: a part moved into the path, a slope too steep to climb).
type Plane = { point: Vector3, out: Vector3, seen: boolean }

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

-- The engine's Blockcast against the walls: how far the box moves along `vector` before it meets
-- one, or nil. A wall the box starts in is never seen (the engine's rule).
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
		if wall.seen and gap >= -FLOOR_GAP and rate > FLOOR_GAP then
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

-- A body as it stands, as part corners in its root's space (never its blocker, which the world
-- passes through: D-198).
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

-- The boar's body at rest (the rig as built).
local CORNERS = cornersOf(RigBuilder.build("Boar"))

-- How deep any corner of the body at `frame` stands inside a wall (0: none); the boar's body unless
-- `corners` is given.
local function depthInWalls(frame: CFrame, corners: { Vector3 }?): number
	local deepest = 0
	local list: { Vector3 } = corners or CORNERS
	for _, wall in walls do
		for _, corner in list do
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
		-- A Humanoid's MoveTo(root.Position): it brakes toward where it stood when told.
		local body = bodies[model]
		body.goal = body.position
	end,
	-- Stops the body dead where it stands, or on `position` (the server's stop point).
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
	worldAhead = function(model: Model, direction: Vector3, distance: number, offset: Vector3?, walk: boolean?)
		return EnemyService.worldAhead(model, direction, distance, function(start, size, vector)
			return blockcast(start, size, vector)
		end, offset, walk)
	end,
}

-- Moves every body to `untilT` in 240 Hz steps: toward its goal at its walk speed, out of walls.
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
					local speed = body.walkSpeed * physicsTuning.speedScale
					desired = delta.Unit * math.min(speed, delta.Magnitude / PHYSICS_STEP)
				end
			end
			local change = desired - body.velocity
			local most = physicsTuning.acceleration * PHYSICS_STEP
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

-- One server frame; `throttled`: a hitch of that many seconds in which physics ran only one frame's
-- time (the rest is lost: the body stands still for it while the clock runs on).
local function serverFrame(fps: number, throttled: number?)
	local dt = throttled or 1 / fps
	if throttled ~= nil then
		physics(clock.t + 1 / fps)
		for _, body in bodies do
			body.physT += throttled - 1 / fps
		end
	end
	clock.t += dt
	physics(clock.t)
	EnemyService.step(dt)
	EntityService.tick(dt)
	CombatService.tick()
end

local function fresh()
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	clock.t = 1000
	sent = {}
	bodies = {}
	walls = {}
	physicsTuning.acceleration = 560
	physicsTuning.speedScale = 1
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
end

local playerCount = 0
local function spawnPlayer(position: Vector3): Model
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
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 2100 + playerCount }
	EntityService.registerPlayer(player :: any, model, Playground.loadout)
	return model
end

type Run = {
	launch: number, -- server time of RushStarted
	ends: { { time: number, reason: string, distance: number } },
	stoppedAt: () -> number, -- seconds after the launch the root first stood at its farthest
	along: (since: number) -> number, -- the root's distance down the line at `since` after launch
	farthest: (fromSince: number, toSince: number) -> number,
	deepest: (fromSince: number, toSince: number) -> number, -- the body's deepest into the wall
}

type Options = {
	staggerAt: number?, -- seconds after the launch a hit staggers the rushing boar
	unseen: boolean?, -- the server's cast misses the wall
	meetDegrees: number?, -- the wall meets the line at this angle (90 unless given)
	speedScale: number?, -- the body runs at this share of its walk speed
	acceleration: number?, -- studs per second squared (560 unless given)
	throttledHitchAt: number?, -- seconds after the launch a 0.1 s frame runs one frame of physics
}

-- A boar charges a player down a line with a wall `wall` studs down it (its face half a stud
-- nearer; none for nil); the player stands `playerAlong` studs down the line. Runs `seconds` past
-- the launch at `fps`.
local function charge(fps: number, wall: number?, playerAlong: number, seconds: number, options: Options?): Run
	local given: Options = options or {}
	fresh()
	local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 2.8, 0))
	local boar = EnemyService.modelOf(boarId) :: Model
	local target = spawnPlayer(Vector3.new(0, 3, -12))
	local guard = 0
	while #sentOf("Telegraph", boarId) == 0 and guard < 600 do
		serverFrame(fps)
		guard += 1
	end
	local telegraph = sentOf("Telegraph", boarId)[1].payload
	local origin = Vector3.new(telegraph.origin[1], telegraph.origin[2], telegraph.origin[3])
	local direction = Vector3.new(telegraph.facing[1], 0, telegraph.facing[3]).Unit;
	(target.PrimaryPart :: BasePart).CFrame = CFrame.new(origin + direction * playerAlong)
	if wall ~= nil then
		local turn = math.rad(90 - (given.meetDegrees or 90))
		table.insert(walls, {
			point = origin + direction * (wall - 0.5),
			out = (CFrame.Angles(0, turn, 0) * -direction).Unit,
			seen = given.unseen ~= true,
		})
	end
	physicsTuning.acceleration = given.acceleration or 560
	physicsTuning.speedScale = given.speedScale or 1
	local body = bodies[boar]
	local launch: number? = nil
	local samples: { { since: number, along: number, depth: number } } = {}
	local staggered, hitched = false, false
	while guard < 6000 do
		local hitchAt = given.throttledHitchAt
		if hitchAt ~= nil and launch ~= nil and not hitched and clock.t + 1 / fps - launch >= hitchAt then
			hitched = true
			serverFrame(fps, 0.1)
		else
			serverFrame(fps)
		end
		guard += 1
		local started = sentOf("RushStarted", boarId)
		if launch == nil and #started > 0 then
			launch = started[1].payload.serverTime
		end
		if launch ~= nil then
			local since = clock.t - launch
			if given.staggerAt ~= nil and not staggered and since >= given.staggerAt then
				staggered = true
				EntityService.setState(boarId, "Stagger", 1.0, "Front")
			end
			table.insert(samples, {
				since = since,
				along = (body.position - origin):Dot(direction),
				depth = depthInWalls(CFrame.lookAt(body.position, body.position + yawOf(boar))),
			})
			if since >= seconds then
				break
			end
		end
	end
	assert(launch ~= nil, "the boar never launched")
	local ends = {}
	for _, entry in sentOf("RushEnded", boarId) do
		table.insert(
			ends,
			{ time = entry.time - launch, reason = entry.payload.reason, distance = entry.payload.distance }
		)
	end
	return {
		launch = launch,
		ends = ends,
		stoppedAt = function(): number
			local most = -math.huge
			for _, sample in samples do
				most = math.max(most, sample.along)
			end
			for _, sample in samples do
				if sample.along >= most - 0.01 then
					return sample.since
				end
			end
			return math.huge
		end,
		along = function(since: number): number
			local found = samples[1].along
			for _, sample in samples do
				if sample.since <= since then
					found = sample.along
				end
			end
			return found
		end,
		farthest = function(fromSince: number, toSince: number): number
			local most = -math.huge
			for _, sample in samples do
				if sample.since >= fromSince and sample.since <= toSince then
					most = math.max(most, sample.along)
				end
			end
			return most
		end,
		deepest = function(fromSince: number, toSince: number): number
			local most = 0
			for _, sample in samples do
				if sample.since >= fromSince and sample.since <= toSince then
					most = math.max(most, sample.depth)
				end
			end
			return most
		end,
	}
end

-- An enemy `defId` hunts a player who stands at `off` studs from a wall (the plane z = 0, free
-- space z >= 0), starting a dozen studs away at `bearing` degrees from the wall's normal (no nearer
-- the wall than `nearest`) and facing along the wall, for `seconds` at 60 server frames a second.
-- Returns the attacks it started and its body's deepest into the wall.
local function hunt(defId: string, off: number, bearing: number, nearest: number, seconds: number): (number, number)
	fresh()
	table.insert(walls, { point = Vector3.zero, out = Vector3.zAxis, seen = true })
	local playerAt = Vector3.new(0, 3, off)
	local angle = math.rad(bearing)
	local start = playerAt + Vector3.new(math.sin(angle), 0, math.cos(angle)) * 12
	start = Vector3.new(start.X, 3, math.max(start.Z, nearest))
	local id = EnemyService.spawn(defId, CFrame.lookAt(start, start + Vector3.xAxis))
	local model = EnemyService.modelOf(id) :: Model
	local corners = cornersOf(model)
	spawnPlayer(playerAt)
	local body = bodies[model]
	local t0 = clock.t
	local deepest = 0
	while clock.t - t0 < seconds do
		serverFrame(60)
		deepest = math.max(deepest, depthInWalls(CFrame.lookAt(body.position, body.position + yawOf(model)), corners))
	end
	return #sentOf("Telegraph", id), deepest
end

local function firstEnd(run: Run, reason: string): { time: number, reason: string, distance: number }?
	for _, ended in run.ends do
		if ended.reason == reason then
			return ended
		end
	end
	return nil
end

-- A rest is where the body's root stands: within a hundredth of a stud of the report.
local REST_SLACK = 0.01
-- The wall face never ends deeper in the body than the boar's launch put it (a crouch point
-- a stud or two off a wall stands the snout a tenth of a stud into it) plus a hair; a hunting body's
-- turns and walks keep it as shallow (D-278, D-295).
local DEPTH_SLACK = 0.15

describe("WallStop", function()
	it("a wall slam's body rests where RushEnded Wall says, at 30 and 60 frames a second", function()
		local wrong = {}
		for _, fps in { 30, 60 } do
			for _, wall in { 8, 10, 13 } do
				local run = charge(fps, wall, 12, 1.0)
				local slam = firstEnd(run, "Wall")
				local label = ("%d fps, wall %d"):format(fps, wall)
				if slam == nil then
					table.insert(wrong, label .. ": no Wall end")
					continue
				end
				-- Never past the report on the way in (no skid), at rest on it through the daze,
				-- and never into the wall.
				local farthest, rest, deepest = run.farthest(0, 1.0), run.along(1.0), run.deepest(0, 1.0)
				if
					farthest > slam.distance + REST_SLACK
					or math.abs(rest - slam.distance) > REST_SLACK
					or deepest > DEPTH_SLACK
				then
					table.insert(
						wrong,
						("%s: reported %.2f, farthest %.2f, rest %.2f, %.2f deep"):format(
							label,
							slam.distance,
							farthest,
							rest,
							deepest
						)
					)
				end
			end
		end
		expect(wrong).toEqual({})
	end)

	it("an early stagger rests where RushEnded Interrupted says", function()
		local wrong = {}
		for _, fps in { 30, 60 } do
			local run = charge(fps, 8, 12, 0.6, { staggerAt = 0.05 })
			local cut = firstEnd(run, "Interrupted")
			if cut == nil then
				table.insert(wrong, ("%d fps: no Interrupted end"):format(fps))
			elseif math.abs(run.along(0.6) - cut.distance) > REST_SLACK then
				table.insert(wrong, ("%d fps: reported %.2f, rest %.2f"):format(fps, cut.distance, run.along(0.6)))
			end
		end
		expect(wrong).toEqual({})
	end)

	it("the walk after the daze never sets the snout in the wall", function()
		local wrong = {}
		for _, fps in { 30, 60 } do
			for _, wall in { 6, 8, 10, 13 } do
				for _, playerAlong in { 12, 6 } do
					local deepest = charge(fps, wall, playerAlong, 4.0).deepest(0, 4.0)
					if deepest > DEPTH_SLACK then
						table.insert(
							wrong,
							("%d fps, wall %d, player %d: %.2f deep"):format(fps, wall, playerAlong, deepest)
						)
					end
				end
			end
		end
		expect(wrong).toEqual({})
	end)

	it("a wall the cast misses is told Jammed within blockedSeconds and two frames of the stop (D-280)", function()
		local wrong = {}
		local blockedSeconds = AI.archetypes.Charger.blockedSeconds
		for _, fps in { 30, 60 } do
			for _, wall in { 8, 10, 13 } do
				local run = charge(fps, wall, 16, 0.8, { unseen = true })
				local jam = firstEnd(run, "Jammed")
				local stopped = run.stoppedAt()
				local label = ("%d fps, wall %d"):format(fps, wall)
				if jam == nil then
					table.insert(wrong, label .. ": no Jammed end")
				elseif jam.time - stopped > blockedSeconds + 2 / fps + 1e-6 then
					table.insert(wrong, ("%s: stopped at +%.3f, Jammed at +%.3f"):format(label, stopped, jam.time))
				end
			end
		end
		expect(wrong).toEqual({})
	end)

	it("a boar hunting a player by a wall turns away from it and still charges (D-295)", function()
		-- The short turn onto the target would swing the snout through the wall: the body turns the
		-- long way round instead of standing stock still facing the wall.
		local wrong = {}
		for _, off in { 2, 4, 8 } do
			for _, bearing in { 0, 45, 80 } do
				local attacks, deepest = hunt("FrenzyBoar", off, bearing, 2.6, 10)
				if attacks == 0 or deepest > DEPTH_SLACK then
					table.insert(
						wrong,
						("player %d off, from %d degrees: %d attacks, %.2f deep"):format(off, bearing, attacks, deepest)
					)
				end
			end
		end
		expect(wrong).toEqual({})
	end)

	it("a kobold walking up a wall slides along it to a player beside it and swings (D-295)", function()
		-- A walk with a little of it into the wall moves along the wall instead of not at all.
		local wrong = {}
		for _, off in { 0.5, 2 } do
			for _, bearing in { 45, 80, 120 } do
				local attacks, deepest = hunt("KoboldAxeman", off, bearing, 2.6, 6)
				if attacks == 0 or deepest > DEPTH_SLACK then
					table.insert(
						wrong,
						("player %.1f off, from %d degrees: %d attacks, %.2f deep"):format(
							off,
							bearing,
							attacks,
							deepest
						)
					)
				end
			end
		end
		expect(wrong).toEqual({})
	end)

	it("a free run, a slowed body, a slow start, a glance and a throttled hitch are never jammed (D-280)", function()
		local wrong = {}
		local cases: { { name: string, wall: number?, options: Options } } = {
			{ name = "free", wall = nil, options = {} },
			{ name = "0.85 of the speed", wall = nil, options = { speedScale = 0.85 } },
			{ name = "a quarter of the acceleration", wall = nil, options = { acceleration = 140 } },
			{ name = "a wall met at 30 degrees", wall = 8, options = { meetDegrees = 30 } },
			{ name = "a throttled 0.1 s hitch", wall = nil, options = { throttledHitchAt = 0.2 } },
		}
		for _, fps in { 30, 60 } do
			for _, case in cases do
				local run = charge(fps, case.wall, 16, 1.2, case.options)
				local jam = firstEnd(run, "Jammed")
				if jam ~= nil then
					table.insert(wrong, ("%d fps, %s: Jammed at +%.3f"):format(fps, case.name, jam.time))
				end
			end
		end
		expect(wrong).toEqual({})
	end)
end)
