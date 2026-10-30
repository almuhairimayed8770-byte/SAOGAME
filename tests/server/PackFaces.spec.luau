--!strict
--[[
	Room between enemies on every blocker face (D-259, D-281, D-315, D-332).

	Since D-281 an enemy's blocker faces (RigBuilder.addBlocker: the body's, and one over each part
	it holds) are solid against every other enemy's faces. The room the AI keeps (Spacing) was a
	capsule over the rest pose, and the faces reach past it: a kobold's axe face 1.84 studs, 3.85
	ahead at its right. Two kobolds a capsule gap apart could stand with their faces inside each
	other, and the engine shoved them apart. Now a footprint carries the faces and the clear ground
	between two enemies is face to face. The judge here is independent of the rule: the flat boxes
	of the faces the model really has (the blockers group), compared edge by edge.

	First the pure rules over the real rigs' faces, then the whole loop (the real EnemyService,
	brains, EntityService and RigBuilder rigs over a fake engine whose bodies walk to their MoveTo
	goals and pass through each other: nothing but the AI keeps them apart), then the spawner
	(PlaygroundService's scatter): no pack it makes starts with a face inside another's.
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
local PlaygroundService = Harness.load("src/server/services/PlaygroundService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Spacing = Harness.load("src/server/ai/Spacing")
local RushWorld = Harness.load("src/shared/choreo/RushWorld")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Playground = Harness.load("src/shared/data/playground")
local CollectionService = Harness.game():GetService("CollectionService")

local FRAME = 1 / 60
local GAP = AI.spacing.gapStuds
local FORWARD = Vector3.new(0, 0, -1)

-- ------------------------------------------------------------------------------------------
-- The judge: the faces a model really has, flat, edge against edge
-- ------------------------------------------------------------------------------------------

local function facesOf(model: Model): { { Vector3 } }
	local faces: { { Vector3 } } = {}
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.CollisionGroup == AI.collision.blockers then
			local half = part.Size / 2
			local corners: { Vector3 } = {}
			for _, sign in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
				local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * sign[1], 0, half.Z * sign[2]))
				table.insert(corners, Vector3.new(corner.X, 0, corner.Z))
			end
			table.insert(faces, corners)
		end
	end
	return faces
end

-- How far two flat convex boxes are apart along their best separating edge normal (negative: the
-- depth they overlap by).
local function separation(a: { Vector3 }, b: { Vector3 }): number
	local best = -math.huge
	for _, polygon in { a, b } do
		for index = 1, #polygon do
			local edge = polygon[index % #polygon + 1] - polygon[index]
			local axis = Vector3.new(-edge.Z, 0, edge.X).Unit
			local aMin, aMax, bMin, bMax = math.huge, -math.huge, math.huge, -math.huge
			for _, point in a do
				local d = point:Dot(axis)
				aMin, aMax = math.min(aMin, d), math.max(aMax, d)
			end
			for _, point in b do
				local d = point:Dot(axis)
				bMin, bMax = math.min(bMin, d), math.max(bMax, d)
			end
			best = math.max(best, bMin - aMax, aMin - bMax)
		end
	end
	return best
end

local function facesApart(a: Model, b: Model): number
	local least = math.huge
	for _, first in facesOf(a) do
		for _, second in facesOf(b) do
			least = math.min(least, separation(first, second))
		end
	end
	return least
end

local function packApart(models: { Model }): number
	local least = math.huge
	for i = 1, #models do
		for j = i + 1, #models do
			least = math.min(least, facesApart(models[i], models[j]))
		end
	end
	return least
end

-- ------------------------------------------------------------------------------------------
-- The pure rules over the real rigs' faces
-- ------------------------------------------------------------------------------------------

-- A rig's footprint as EnemyService measures it: its rest corners and the faces addBlocker builds.
local function footprintOf(rigId: string): any
	local model = RigBuilder.build(rigId)
	local faces = {}
	for _, face in RigBuilder.footprints(rigId) do
		table.insert(faces, { centre = face.centre, half = face.size / 2 })
	end
	return Spacing.footprintOf(RushWorld.profileOf(model), faces)
end

local function body(position: Vector3, facing: Vector3, footprint: any): any
	return { position = position, facing = facing, footprint = footprint }
end

-- Where a footprint's faces stand on a body, as flat boxes (the judge's shape).
local function bodyFaces(subject: any): { { Vector3 } }
	local list: { { Vector3 } } = {}
	for _, face in subject.footprint.faces do
		table.insert(list, Spacing.faceCorners(subject, face))
	end
	return list
end

local function bodiesApart(a: any, b: any): number
	local least = math.huge
	for _, first in bodyFaces(a) do
		for _, second in bodyFaces(b) do
			least = math.min(least, separation(first, second))
		end
	end
	return least
end

describe("Spacing on every blocker face (D-332)", function()
	local KOBOLD = footprintOf("Kobold")
	local BOAR = footprintOf("Boar")

	it("a footprint carries every face RigBuilder builds and spans them", function()
		expect(#KOBOLD.faces).toBe(#RigBuilder.footprints("Kobold"))
		expect(#KOBOLD.faces).toBe(2) -- the body's and the axe's (D-315)
		expect(#BOAR.faces).toBe(1)
		for _, face in KOBOLD.faces do
			expect(KOBOLD.radius).toBeGreaterThanOrEqual(math.abs(face.centre.X) + face.half.X - 1e-6)
			expect(KOBOLD.front).toBeGreaterThanOrEqual(-face.centre.Z + face.half.Z - 1e-6)
		end
	end)

	it("measures face to face: two kobolds a capsule gap apart, axes toward each other, overlap", function()
		-- One kobold facing -Z, the other ahead at its right (310 degrees round) turned back toward
		-- it (170 degrees): the worst of 36 x 36 placements. The capsules alone (the faces left out)
		-- stand a gap apart, and the faces reach into each other.
		local capsule = Spacing.footprintOf(RushWorld.profileOf(RigBuilder.build("Kobold")))
		local round, turned = math.rad(310), math.rad(170)
		local away = Vector3.new(math.cos(round), 0, math.sin(round))
		local a = body(Vector3.new(0, 3, 0), FORWARD, capsule)
		local b = body(Vector3.new(0, 3, 0) + away * 10, Vector3.new(math.sin(turned), 0, -math.cos(turned)), capsule)
		for _ = 1, 20 do
			b.position -= away * (Spacing.clearance(a, b, Vector3.xAxis) - GAP)
		end
		expect(Spacing.clearance(a, b, Vector3.xAxis)).toBeCloseTo(GAP, 1e-4)
		local withFaces = body(a.position, a.facing, KOBOLD)
		local other = body(b.position, b.facing, KOBOLD)
		local judged = bodiesApart(withFaces, other)
		expect(judged).toBeLessThan(-1) -- the faces are 1.33 studs inside each other at the capsules' gap
		local clear, out = Spacing.clearance(withFaces, other, Vector3.xAxis)
		-- Face to face it overlaps, by at least as much as the judge's deepest pair (one push must
		-- part every pair at once).
		expect(clear).toBeLessThan(0)
		expect(clear).toBeLessThanOrEqual(judged + 1e-6)
		-- Out of the other, away from it.
		expect(out:Dot(-away)).toBeGreaterThan(0)
		-- The two directions of one pair are opposite: the two step apart.
		local clearBack, back = Spacing.clearance(other, withFaces, -Vector3.xAxis)
		expect(clearBack).toBeCloseTo(clear, 1e-6)
		expect((out + back).Magnitude).toBeLessThan(1e-6)
		-- Pushed that far along it, every face stands the gap clear.
		local moved = body(withFaces.position + out * (GAP - clear), withFaces.facing, KOBOLD)
		expect(bodiesApart(moved, other)).toBeGreaterThanOrEqual(GAP - 1e-3)
	end)

	it("a body standing in another's faces steps out past the gap on every face", function()
		for _, case in
			{
				{ at = Vector3.new(1.5, 3, 0), facing = FORWARD },
				{ at = Vector3.new(0.4, 3, 0.2), facing = Vector3.new(1, 0, 0) },
				{ at = Vector3.new(0, 3, 0), facing = FORWARD }, -- one spot: the fallback picks the side
			}
		do
			local boar = body(Vector3.new(0, 3, 0), FORWARD, BOAR)
			local me = body(case.at, case.facing, KOBOLD)
			expect(bodiesApart(me, boar)).toBeLessThan(0)
			local step = Spacing.steer(me, nil, { { body = boar, share = 1, side = 1 } }) :: Vector3
			expect(step).never.toBe(nil)
			local after = bodiesApart(body(step, case.facing, KOBOLD), boar)
			expect(after).toBeGreaterThanOrEqual(GAP - 1e-3)
		end
	end)

	it("a goal inside another body's faces moves out to the gap", function()
		local boar = body(Vector3.new(0, 3, 0), Vector3.new(1, 0, 0), BOAR)
		local me = body(Vector3.new(30, 3, 30), FORWARD, KOBOLD)
		local spot = Spacing.standOff(me, Vector3.new(0.5, 3, 0.5), { boar }, GAP, Vector3.xAxis)
		local clear = bodiesApart(body(spot, FORWARD, KOBOLD), boar)
		expect(clear).toBeGreaterThanOrEqual(GAP - 1e-3)
		expect(clear).toBeLessThan(GAP + 0.05)
	end)

	it("a walk into a long flat face with its goal behind the middle goes round one end", function()
		-- A boar side on (its face 8.9 long across the walk), the goal straight through it. Along a
		-- flat face the turn points at the goal's foot on it; it must not walk to the middle and stay.
		local boar = body(Vector3.new(0, 3, 0), Vector3.new(1, 0, 0), BOAR)
		local goal = Vector3.new(0.3, 3, -20)
		local at = Vector3.new(0.3, 3, 8)
		local least = math.huge
		local passed = false
		for _ = 1, 60 do
			local me = body(at, goal - at, KOBOLD)
			local target = Spacing.steer(me, goal, { { body = boar, share = 1, side = 1 } })
			local walk = (if target ~= nil then target else goal) - at
			-- One AI tick of walking at the kobold's pace.
			local reach = Enemies.byId("KoboldAxeman").moveSpeed * AI.tickSeconds()
			at += if walk.Magnitude > reach then walk.Unit * reach else walk
			least = math.min(least, bodiesApart(body(at, goal - at, KOBOLD), boar))
			if at.Z < -2 then
				passed = true
				break
			end
		end
		expect(passed).toBe(true)
		-- Never inside it on the way round (a tick's walk may close a little past the gap).
		expect(least).toBeGreaterThan(0)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The whole loop over the real rigs
-- ------------------------------------------------------------------------------------------

type Walker = {
	position: Vector3,
	goal: Vector3?,
	walkSpeed: number,
	offsets: { [BasePart]: CFrame },
}

local clock = { t = 8000 }
local walkers: { [Model]: Walker } = {}

local function yawOf(model: Model): Vector3
	local align = EnemyService.alignOf(model)
	local look = if align ~= nil then align.CFrame.LookVector else (model.PrimaryPart :: BasePart).CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function placeParts(model: Model, state: Walker)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.lookAt(state.position, state.position + yawOf(model))
	for part, offset in state.offsets do
		part.CFrame = root.CFrame * offset
	end
end

local engine = {
	place = function(model: Model, cframe: CFrame)
		local root = model.PrimaryPart :: BasePart
		root.CFrame = CFrame.new()
		local offsets: { [BasePart]: CFrame } = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= root then
				offsets[part] = root.CFrame:ToObjectSpace(part.CFrame)
			end
		end
		root.CFrame = cframe
		EnemyService.addYawAlign(root, cframe.LookVector)
		local state: Walker = { position = cframe.Position, goal = nil, walkSpeed = 16, offsets = offsets }
		walkers[model] = state
		placeParts(model, state)
	end,
	position = function(model: Model): Vector3
		return walkers[model].position
	end,
	facing = function(model: Model): Vector3
		return yawOf(model)
	end,
	setFacing = function(model: Model, facing: Vector3)
		EnemyService.applyFacing(model, facing)
	end,
	moveTo = function(model: Model, position: Vector3)
		walkers[model].goal = position
	end,
	stop = function(model: Model)
		walkers[model].goal = nil
	end,
	setWalkSpeed = function(model: Model, speed: number)
		walkers[model].walkSpeed = speed
	end,
	computePath = function()
		return nil
	end,
	destroy = function(model: Model)
		model.Parent = nil
		walkers[model] = nil
	end,
}

-- Bodies walk straight at their goals at their walk speed and pass through each other.
local function physics(dt: number)
	for model, state in walkers do
		local goal = state.goal
		if goal ~= nil then
			local delta = Vector3.new(goal.X - state.position.X, 0, goal.Z - state.position.Z)
			local reach = state.walkSpeed * dt
			if delta.Magnitude <= reach then
				state.position = Vector3.new(goal.X, state.position.Y, goal.Z)
			else
				state.position += delta.Unit * reach
			end
		end
		placeParts(model, state)
	end
end

local function frame()
	clock.t += FRAME
	physics(FRAME)
	EnemyService.step(FRAME)
	EntityService.tick(FRAME)
end

local function fresh(seed: number?)
	EnemyService.reset()
	EntityService.reset()
	clock.t = 8000
	walkers = {}
	local now = function()
		return clock.t
	end
	EntityService.bind({
		now = now,
		fireAll = function() end,
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
		combat = {
			setEnemyHitStop = function() end,
			enemyStrike = function()
				return {}
			end,
		},
		rigBuilder = RigBuilder,
		fireAll = function() end,
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
		random = Random.new(seed or 5),
		spawnTask = function(fn)
			fn()
		end,
	} :: any)
end

local playerCount = 0
local function spawnPlayer(position: Vector3): number
	playerCount += 1
	local model = Instance.new("Model")
	model.Name = "PackTarget" .. playerCount
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position)
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	local player = { Name = model.Name, DisplayName = "PackTarget", UserId = 990 + playerCount }
	return EntityService.registerPlayer(player :: any, model, Playground.loadout)
end

describe("EnemyService keeps a pack's faces apart (D-332)", function()
	it("three kobolds spawned in one heap step apart until no face is within the gap of another", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, 200)) -- far off: awake, never aggroed
		local models: { Model } = {}
		for index, spot in { Vector3.new(0, 3, 0), Vector3.new(0.4, 3, 0.2), Vector3.new(-0.3, 3, 0.5) } do
			local facing = Vector3.new(math.sin(index * 2.1), 0, math.cos(index * 2.1))
			local id = EnemyService.spawn("KoboldAxeman", CFrame.lookAt(spot, spot + facing))
			table.insert(models, EnemyService.modelOf(id) :: Model)
		end
		expect(packApart(models)).toBeLessThan(0)
		for _ = 1, 60 * 4 do
			frame()
		end
		-- Every face the gap clear of every other (it was 0.33 studs inside on the capsule rule).
		expect(packApart(models)).toBeGreaterThanOrEqual(GAP - 1e-3)
	end)

	it("four kobolds closing on one player never stand a face deep in each other", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, 0))
		local models: { Model } = {}
		for index = 1, 4 do
			local angle = index * math.pi / 2
			local spot = Vector3.new(math.cos(angle) * 16, 3, math.sin(angle) * 16)
			local id = EnemyService.spawn("KoboldAxeman", CFrame.lookAt(spot, Vector3.new(0, 3, 0)))
			table.insert(models, EnemyService.modelOf(id) :: Model)
		end
		local least = math.huge
		for _ = 1, 60 * 8 do
			frame()
			least = math.min(least, packApart(models))
		end
		-- The room is kept every AI tick, so a body can close at most one tick's walk past it before
		-- the next; on the capsule rule two axes stood 1.82 studs inside each other.
		local tickWalk = Enemies.byId("KoboldAxeman").moveSpeed * AI.tickSeconds()
		expect(least).toBeGreaterThan(-tickWalk)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The spawner
-- ------------------------------------------------------------------------------------------

describe("the spawner never makes a pack inside itself (D-170, D-332)", function()
	it("every pack PlaygroundService scatters stands with every face the gap clear of the others", function()
		local least = math.huge
		for _, case in
			{
				{ enemy = "KoboldAxeman", size = 3 },
				{ enemy = "KoboldAxeman", size = 6 },
				{ enemy = "FrenzyBoar", size = 3 },
			}
		do
			for seed = 1, 40 do
				fresh(seed)
				PlaygroundService.bind({
					now = function()
						return clock.t
					end,
					entities = EntityService,
					enemies = EnemyService,
					waitForChild = function()
						return nil
					end,
					random = Random.new(seed),
				} :: any)
				local spawn = {
					enemy = case.enemy,
					position = { 0, 0, 0 },
					facing = 0,
					packSize = { min = case.size, max = case.size },
				}
				local models: { Model } = {}
				for _ = 1, case.size do
					local id = EnemyService.spawn(case.enemy, PlaygroundService.spawnCFrame(spawn :: any), {})
					table.insert(models, EnemyService.modelOf(id) :: Model)
				end
				least = math.min(least, packApart(models))
			end
		end
		expect(least).toBeGreaterThanOrEqual(GAP)
	end)
end)
