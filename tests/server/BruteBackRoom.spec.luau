--!strict
--[[
	A Brute that walks a fighter back to the world leaves the fighter's swing its room (D-627; F1e
	openIssue 1 and ownerCall 2, F1d ownerCall 1). The owner's call: the monster looms close, but
	the hero always has room to swing, and nobody is shoved by physics.

	Played the way the game plays it: the real EnemyService (the Brute's brain at the AI's tick, the
	frame pass, the yaw align, the mover), EntityService and CombatService, over EnemyWalkStart's
	"studio" Humanoid (BoarHooks.spec's: its walk settled once a frame, reaching its WalkSpeed at
	1320 studs/s^2, braking 0.672 a 1/240 s step) at 60 server frames a second. The kobold is
	RigBuilder's, its blocker faces carried with its root. The fighter is a player's root box (2 x 2
	x 1) looking at the kobold, backed to the face of item 519's wall (10 x 8 x 1) or pillar (2 x 8 x
	2) at z 25.7: its deepest corner rests 0.05 in it (the engine's contact, F1e), its root 0.45 off
	square on. The world is boxes that the server's Blockcast meets (a box it starts in is never
	met, the engine's rule).

	The kobold is let loose 9 studs off along a line `angle` degrees off the face's normal (0, 10, 20
	and 30: F1e's takes turned the line 7 to 10 off once the body had slid along the face), facing
	the fighter. It walks in, swings its Overhead from where it engages, recovers, walks in to its
	stop and swings again. Read when that second wind-up begins: the flat root-to-root distance (the
	stop) and the gap from the world to the kobold's Blocker along the line, over the fighter's root
	width (rays from the fighter's root, one to each box). On efa907c it stopped 3.06-3.41 root to
	root and left 2.52-2.74, where the swings lean 2.0-2.8 deep on the matrix's Head. With the
	owner's Head colliding (D-630) they lean up to 3.688 (Vertical, D-642): the bar is the
	deepest lean plus the stand-off's gap off each face, 3.788. On c4f0e1c it stopped 3.93-4.30 and
	left 3.42-3.66; it now lands on its stop (D-643), 4.52-4.70, and leaves 3.87-3.91. Both of its
	blows must still land on the fighter.
]]

local function fakeSignal()
	local signal = {}
	function signal:Connect()
		return { Disconnect = function() end }
	end
	return signal
end
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
	RenderStepped = fakeSignal(),
	Heartbeat = fakeSignal(),
	PreSimulation = fakeSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local EntityService = Harness.load("src/server/services/EntityService")
local CombatService = Harness.load("src/server/services/CombatService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local Playground = Harness.load("src/shared/data/playground")
local CollectionService = Harness.game():GetService("CollectionService")

-- The room every player swing needs (D-627), read from the clips' own extents on the parts the
-- engine collides (HitMatrix.leanColumns, D-642: Vertical's 3.688 on the owner's Head the
-- deepest), with the stand-off's gap off each face: a stop that leaves less than this between the
-- world and the Blocker squeezes a swing.
local function swingRoom(): (number, string)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local source = fs.readFile(Harness.repoRoot() .. "/tools/hitmatrix/HitMatrix.luau")
	local HitMatrix = luau.load(source, {
		debugName = "tools/hitmatrix/HitMatrix",
		environment = { require = require } :: any,
	})()
	local deepest, which = 0, ""
	for _, column in HitMatrix.leanColumns(Harness) do
		if column.depth > deepest then
			deepest, which = column.depth, column.id
		end
	end
	return deepest + 2 * Harness.load("src/shared/data/combat").contact.standOff.wallGapStuds, which
end
local ROOM, DEEPEST = swingRoom()

local FRAME = 1 / 60
local PHYSICS_STEP = 1 / 240
local GAP = 1e-9
local FACE_Z = 25.7
local CONTACT = 0.05 -- the engine rests a pressed root box this deep in the face (F1e: the PC's 0.050-0.056)
local ROOT_SIZE = Vector3.new(2, 2, 1) -- an R15's root box
local START = 9 -- studs from the fighter the kobold is let loose
local KOBOLD = Enemies.byId("KoboldAxeman")

-- BoarHooks.spec's "studio" Humanoid (the PC's server log on 4b18b5c).
local humanoid = { arriveFrames = 1.7, brake = 0.672, acceleration = 1320 }
local clock = { t = 1000 }
local bodies: { [Model]: any } = {}
local world: { BasePart } = {}
local sent: { { time: number, remote: string, payload: any } } = {}

-- ------------------------------------------------------------------------------------------
-- The world: upright boxes, met by a box cast as workspace:Blockcast meets them
-- ------------------------------------------------------------------------------------------

local function reachAlong(frame: CFrame, size: Vector3, axis: Vector3): number
	local half = size / 2
	return math.abs(frame.RightVector:Dot(axis)) * half.X
		+ math.abs(frame.UpVector:Dot(axis)) * half.Y
		+ math.abs(frame.LookVector:Dot(axis)) * half.Z
end

-- A box of `size` at `start` moved along `vector` against every world box (all of them turned
-- about the vertical only, so their face normals and the vertical separate them): how far it
-- moves before it first touches one, and that face's normal (out of the box it meets). A box it
-- starts in is never met.
local function blockcast(start: CFrame, size: Vector3, vector: Vector3): (number?, Vector3?)
	local length = vector.Magnitude
	if length < GAP then
		return nil, nil
	end
	local best: number?, normal: Vector3? = nil, nil
	for _, part in world do
		local frame = part.CFrame
		local axes = { Vector3.yAxis, frame.RightVector, frame.LookVector, start.RightVector, start.LookVector }
		local enter, leave = -math.huge, math.huge
		local enterAxis = Vector3.yAxis
		local missed = false
		for _, axis in axes do
			local reach = reachAlong(start, size, axis) + reachAlong(frame, part.Size, axis)
			local apart = (start.Position - frame.Position):Dot(axis) -- the box less the part, along axis
			local rate = vector:Dot(axis)
			if math.abs(rate) < GAP then
				if math.abs(apart) >= reach then
					missed = true
					break
				end
			else
				-- When the box's centre is `reach` from the part's along this axis.
				local a = (-reach - apart) / rate
				local b = (reach - apart) / rate
				local low, high = math.min(a, b), math.max(a, b)
				if low > enter then
					enter = low
					enterAxis = if apart >= 0 then axis else -axis
				end
				leave = math.min(leave, high)
			end
		end
		if not missed and enter >= 0 and enter <= leave and enter <= 1 then
			local travelled = enter * length
			if best == nil or travelled < best then
				best, normal = travelled, enterAxis
			end
		end
	end
	return best, normal
end

-- Where a ray from `origin` along `direction` (unit) first enters `part`'s box, or nil.
local function rayInto(origin: Vector3, direction: Vector3, cframe: CFrame, size: Vector3): number?
	local from = cframe:PointToObjectSpace(origin)
	local along = cframe:VectorToObjectSpace(direction)
	local half = size / 2
	local enter, leave = -math.huge, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local o: number = (from :: any)[axis]
		local d: number = (along :: any)[axis]
		local h: number = (half :: any)[axis]
		if math.abs(d) < GAP then
			if math.abs(o) > h then
				return nil
			end
		else
			local a, b = (-h - o) / d, (h - o) / d
			enter = math.max(enter, math.min(a, b))
			leave = math.min(leave, math.max(a, b))
		end
	end
	if enter > leave or leave < 0 then
		return nil
	end
	return math.max(enter, 0)
end

local function addBox(shape: string)
	if shape ~= "wall" and shape ~= "pillar" then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	if shape == "wall" then
		part.Size = Vector3.new(10, 8, 1)
		part.CFrame = CFrame.new(30, 4, FACE_Z - 0.5)
	else
		part.Size = Vector3.new(2, 8, 2)
		part.CFrame = CFrame.new(30, 4, FACE_Z - 1)
	end
	table.insert(world, part)
end

-- ------------------------------------------------------------------------------------------
-- The fake engine (EnemyWalkStart's, its rig's parts carried with the root as WallStop's are)
-- ------------------------------------------------------------------------------------------

local function yawOf(model: Model): Vector3
	local align = EnemyService.alignOf(model)
	local look = if align ~= nil then align.CFrame.LookVector else (model.PrimaryPart :: BasePart).CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function placeParts(model: Model, body: any)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.lookAt(body.position, body.position + yawOf(model))
	for part, offset in body.offsets do
		part.CFrame = root.CFrame * offset
	end
end

local function worldCast(start: CFrame, size: Vector3, vector: Vector3): (number?, Vector3?)
	return blockcast(start, size, vector)
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
		bodies[model] = {
			position = cframe.Position,
			velocity = Vector3.zero,
			walkSpeed = 16,
			physT = clock.t,
			offsets = offsets,
		}
		placeParts(model, bodies[model])
	end,
	pivot = function(model: Model, cframe: CFrame)
		bodies[model].position = cframe.Position
		placeParts(model, bodies[model])
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
		bodies[model].goal = bodies[model].position
	end,
	halt = function(model: Model, position: Vector3?)
		local body = bodies[model]
		if position ~= nil then
			body.position = Vector3.new(position.X, body.position.Y, position.Z)
		end
		body.velocity = Vector3.zero
		body.goal = body.position
		body.written = true
		placeParts(model, body)
	end,
	land = function(model: Model, position: Vector3, seconds: number)
		local body = bodies[model]
		local offset = Vector3.new(position.X - body.position.X, 0, position.Z - body.position.Z)
		local pace = if seconds > 0 then offset / seconds else Vector3.zero
		body.velocity = pace
		body.walkSpeed = pace.Magnitude
		body.goal = Vector3.new(position.X, body.position.Y, position.Z)
		body.written = true
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
		return EnemyService.worldAhead(model, direction, distance, worldCast, offset, walk)
	end,
	worldBehind = function(root: BasePart, direction: Vector3, distance: number)
		return EnemyService.worldBehind(root, direction, distance, worldCast)
	end,
	anchor = function(model: Model, anchored: boolean)
		bodies[model].anchored = anchored
	end,
}

-- One server frame of the "studio" Humanoid: the walk settled at the frame's start, then 240 Hz
-- physics steps toward it at `acceleration`, braking when it holds its goal as reached.
local function studioFrame(model: Model, body: any, untilT: number)
	local seconds = untilT - body.physT
	local desired: Vector3? = nil
	local goal = body.goal
	if goal ~= nil and not body.anchored then
		local delta = Vector3.new(goal.X - body.position.X, 0, goal.Z - body.position.Z)
		local reached = humanoid.arriveFrames * body.walkSpeed * math.max(seconds, 0)
		if delta.Magnitude > math.max(reached, 1e-3) then
			desired = delta.Unit * body.walkSpeed
		end
	end
	local kept = body.written == true
	body.written = false
	while body.physT + PHYSICS_STEP <= untilT + GAP do
		body.physT += PHYSICS_STEP
		if body.anchored then
			body.velocity = Vector3.zero
			continue
		end
		if desired ~= nil then
			local change = desired - body.velocity
			local most = humanoid.acceleration * PHYSICS_STEP
			if change.Magnitude > most then
				change = change.Unit * most
			end
			body.velocity += change
		elseif not kept then
			body.velocity *= humanoid.brake
			if body.velocity.Magnitude < 0.01 then
				body.velocity = Vector3.zero
			end
		end
		body.position += body.velocity * PHYSICS_STEP
	end
	placeParts(model, body)
end

local function serverFrame()
	clock.t += FRAME
	for model, body in bodies do
		studioFrame(model, body, clock.t)
	end
	EnemyService.step(FRAME)
	EntityService.tick(FRAME)
	CombatService.tick()
end

local function record(remote: string, payload: any)
	table.insert(sent, { time = clock.t, remote = remote, payload = payload })
end

local function fresh()
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	clock.t = 1000
	bodies = {}
	world = {}
	sent = {}
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

-- The fighter: a player's root box (an R15's 2 x 2 x 1) at `position`, looking at `toward`.
local function spawnPlayer(position: Vector3, toward: Vector3): (number, BasePart)
	local model = Instance.new("Model")
	model.Name = "Trialist1"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT_SIZE
	root.CFrame = CFrame.lookAt(position, Vector3.new(toward.X, position.Y, toward.Z))
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	CollisionGroups.assign(model, AI.collision.players)
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 3101 }
	local id = EntityService.registerPlayer(player :: any, model, Playground.loadout)
	-- Two Overheads must land and be counted, so the fighter outlives them.
	local fighter = EntityService.get(id) :: any
	fighter.maxHp = 1e6
	fighter.hp = 1e6
	return id, root
end

type Take = {
	stand: number, -- root to root, flat, as the second wind-up begins (the stop)
	first: number, -- the same as the first wind-up begins (where it engaged)
	gap: number, -- the world to the Blocker along the line, the least over the fighter's root width
	centre: number, -- the same on the line through the fighter's root centre
	blows: number, -- Overheads that landed on the fighter
	telegraphs: number,
	behind: number?, -- the world behind the fighter's root along the line, as a Blockcast reads it
	angle: number, -- the line's angle off the face's normal at the stop (degrees)
}

local function take(shape: string, angle: number): Take
	fresh()
	addBox(shape)
	local def = KOBOLD
	-- The fighter looks along the line it is attacked from, its root box resting CONTACT in the face
	-- at its deepest corner (0.45 off it square on, as F1e's).
	local along = Vector3.new(math.sin(math.rad(angle)), 0, math.cos(math.rad(angle)))
	local look = CFrame.lookAt(Vector3.zero, along)
	local off = reachAlong(look, ROOT_SIZE, Vector3.zAxis) - CONTACT
	local playerAt = Vector3.new(30, 3, FACE_Z + off)
	local spot = playerAt + along * START
	local playerId, playerRoot = spawnPlayer(playerAt, spot)
	local rig = Rigs[def.skin]
	local height = PlaygroundLayout.rootHeight(rig.hipHeight, 2, World.spawn.groundEpsilon)
	local koboldAt = Vector3.new(spot.X, height, spot.Z)
	local id = EnemyService.spawn(def.id, CFrame.lookAt(koboldAt, Vector3.new(playerAt.X, height, playerAt.Z)))
	local model = EnemyService.modelOf(id) :: Model
	assert(model ~= nil, "no kobold model")
	local blocker = model:FindFirstChild(RigBuilder.BLOCKER_NAME) :: BasePart
	assert(blocker ~= nil, "the kobold has no Blocker")
	local hpBefore = (EntityService.get(playerId) :: any).hp
	local result: Take = {
		stand = 0,
		first = 0,
		gap = 0,
		centre = 0,
		blows = 0,
		telegraphs = 0,
		behind = nil,
		angle = 0,
	}
	local seen = 0
	local hp = hpBefore
	for _ = 1, math.floor(9 / FRAME) do
		serverFrame()
		local now = (EntityService.get(playerId) :: any).hp
		if now < hp then
			result.blows += 1
		end
		hp = now
		local telegraphs = 0
		for _, entry2 in sent do
			if entry2.remote == "Telegraph" and entry2.payload.entityId == id then
				telegraphs += 1
			end
		end
		if telegraphs > seen then
			seen = telegraphs
			local at = engine.position(model)
			local flat = Vector3.new(playerAt.X - at.X, 0, playerAt.Z - at.Z)
			if telegraphs == 1 then
				result.first = flat.Magnitude
			elseif telegraphs == 2 then
				result.stand = flat.Magnitude
				-- The gap along the line, over the fighter's root width: rays from the fighter's root,
				-- one on past it to the world, one back to the kobold's Blocker.
				local u = flat.Unit
				local across = u:Cross(Vector3.yAxis)
				local least, centre = math.huge, math.huge
				for step = -10, 10 do
					local origin = playerAt + across * (step / 10)
					local toWorld = math.huge
					for _, part in world do
						toWorld = math.min(toWorld, rayInto(origin, u, part.CFrame, part.Size) or math.huge)
					end
					local toFace = rayInto(origin, -u, blocker.CFrame, blocker.Size) or math.huge
					least = math.min(least, toWorld + toFace)
					if step == 0 then
						centre = toWorld + toFace
					end
				end
				result.gap, result.centre = least, centre
				result.angle = math.deg(math.acos(math.clamp(-u.Z, -1, 1)))
				local reach = reachAlong(playerRoot.CFrame, playerRoot.Size, u)
				result.behind = select(1, worldCast(playerRoot.CFrame - u * reach, playerRoot.Size, u * 10))
			end
		end
	end
	result.telegraphs = seen
	return result
end

describe("a Brute at a fighter backed to a wall or a pillar (D-627)", function()
	it("stops far enough off to leave every swing's lean its room, and both its blows land", function()
		local engage = math.huge
		for _, attack in KOBOLD.attacks do
			engage = math.min(engage, attack.reach * AI.archetypes.Brute.engageFraction)
		end
		for _, shape in { "wall", "pillar" } do
			for _, angle in { 0, 10, 20, 30 } do
				local result = take(shape, angle)
				print(
					("[G6b] %s at %d deg: engaged at %.3f, stopped at %.3f root to root (the line %.1f deg off the face's normal); gap to the Blocker %.3f (on the root's line %.3f) against the swings' %.3f (%s); the world %.3f behind the root; %d blows of %d"):format(
						shape,
						angle,
						result.first,
						result.stand,
						result.angle,
						result.gap,
						result.centre,
						ROOM,
						DEEPEST,
						result.behind or -1,
						result.blows,
						result.telegraphs
					)
				)
				expect(result.telegraphs >= 2).toBe(true)
				-- Every swing's lean fits between the world and the Blocker, wherever the walk's last
				-- tick and the brake left the body, across the fighter's width.
				expect(result.gap >= ROOM - 1e-3).toBe(true)
				-- It still looms: inside the Overhead's engage range, and no farther than the stop's cap.
				expect(result.stand <= engage).toBe(true)
				expect(result.stand <= AI.archetypes.Brute.backRoom.maxStopDistance + 1e-6).toBe(true)
				-- And its blows land: the engage one and the one from its stop.
				expect(result.blows >= 2).toBe(true)
			end
		end
	end)

	it("keeps its stopDistance with no world behind the fighter", function()
		-- The open field: the stop is stopDistance's 3.0-3.5 band, as before.
		local open = take("none", 0)
		print(("[G6b] open field: engaged at %.3f, stopped at %.3f"):format(open.first, open.stand))
		local tuning = AI.archetypes.Brute
		local walk = KOBOLD.moveSpeed * tuning.chaseSpeedMultiplier * AI.tickSeconds()
		expect(open.stand <= tuning.stopDistance + 1e-6).toBe(true)
		expect(open.stand > tuning.stopDistance - walk - 0.15).toBe(true)
		expect(open.blows >= 2).toBe(true)
	end)
end)
