--!strict
--[[
	Walking into an enemy (D-198): what a player's character collides with on a standing boar and a
	standing kobold, spawned through the real EnemyService over RigBuilder rigs and grouped by the
	real CollisionGroups (the pairs register sets), against an R15 player's colliding column.

	Studio: a player walking (W) into a held boar or a kobold bobbed for about 1 s (root Y 3.8 to
	4.4, up to 4.83, about 11 studs/s up and down), slid off sideways and never stood on it. The only
	part a player collided with was the enemy's root: a box floating at HipHeight (the boar's 1.6 to
	4.0 studs above the floor, the kobold's 2.2 to 4.2) whose top edge sits level with the player's
	root top, at its chest, while the player's colliding parts run from its root's bottom (HipHeight,
	2.0) to the top of its head. The engine meets that edge, not a face. A walk-in has to meet one
	flat, upright face from below the player's lowest colliding part to above its highest, and
	nothing else of the enemy; a rush still passes through players (D-167), and nothing else about
	the body changes: it runs on the world as before, and no query sees the new part.

	The face stands over the whole body, not the root alone: over the root's footprint a player
	walked into a boar head-on stopped inside its head (the root ends 2.5 studs ahead of its centre,
	the snout 5.6), from behind inside its tail, and on the flank 0.1 into its side. A walk-in now
	stops where the player touches the body, on every side.
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
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local HitSweep = Harness.load("src/server/combat/HitSweep")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Rigs = Harness.load("src/shared/data/rigs")
local CollectionService = Harness.game():GetService("CollectionService")

local GROUPS = AI.collision

-- Engine facts about a player's R15 character at the place's scale (rigs.luau PlayerR15 scale
-- bodyHeight 1.08): the Humanoid never lets the legs collide, so the lowest colliding part is the
-- root, whose bottom the Humanoid holds HipHeight above the floor (2.0, 2.16 scaled); the highest is
-- the head, whose top stands about 5.6 studs up.
local PLAYER_LOWEST = Rigs.PlayerR15.hipHeight
local PLAYER_HIGHEST = 5.6

-- The pairs register makes (PhysicsService stand-in): every pair collides unless set apart.
local apart: { [string]: boolean } = {}
local physics = {
	IsCollisionGroupRegistered = function(_self, _name: string): boolean
		return true
	end,
	RegisterCollisionGroup = function(_self, _name: string) end,
	CollisionGroupSetCollidable = function(_self, a: string, b: string, collidable: boolean)
		apart[a .. "|" .. b] = not collidable
		apart[b .. "|" .. a] = not collidable
	end,
}
CollisionGroups.register(physics :: any)

local function collides(a: string, b: string): boolean
	return apart[a .. "|" .. b] ~= true
end

-- Every part follows the root as built (the engine's place: PivotTo).
local engine = {
	place = function(model: Model, cframe: CFrame)
		local root = model.PrimaryPart :: BasePart
		local offsets = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= root then
				offsets[part] = root.CFrame:ToObjectSpace(part.CFrame)
			end
		end
		root.CFrame = cframe
		for part, offset in offsets do
			part.CFrame = cframe * offset
		end
	end,
	position = function(model: Model): Vector3
		return (model.PrimaryPart :: BasePart).CFrame.Position
	end,
	facing = function(model: Model): Vector3
		return (model.PrimaryPart :: BasePart).CFrame.LookVector
	end,
	setFacing = function() end,
	moveTo = function() end,
	stop = function() end,
	setWalkSpeed = function() end,
	computePath = function()
		return nil
	end,
	destroy = function(model: Model)
		model.Parent = nil
	end,
	setCollisionGroup = function(model: Model, group: string)
		CollisionGroups.assign(model, group)
	end,
}

local function fresh()
	EnemyService.reset()
	EntityService.reset()
	local now = function()
		return 100
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
		combat = nil,
		rigBuilder = RigBuilder,
		fireAll = function() end,
		engine = engine,
		players = function()
			return {}
		end,
		heartbeat = nil,
		serverTime = now,
		folder = Instance.new("Folder"),
		random = Random.new(1),
		spawnTask = nil,
	} :: any)
end

-- A standing enemy on a floor at y = 0: its root's centre HipHeight + half its height up.
local function standing(defId: string): Model
	local def = Enemies.byId(defId)
	local rig = Rigs[def.skin]
	local rootSize = rig.parts[rig.rootPart].size
	local id = EnemyService.spawn(defId, CFrame.new(0, rig.hipHeight + rootSize[2] / 2, 0))
	return EnemyService.modelOf(id) :: Model
end

-- A part's lowest and highest point (its corners as it stands).
local function heights(part: BasePart): (number, number)
	local half = part.Size / 2
	local low, high = math.huge, -math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
				low, high = math.min(low, corner.Y), math.max(high, corner.Y)
			end
		end
	end
	return low, high
end

-- The enemy's parts that collide with `group` as the enemy stands now.
local function collidersWith(model: Model, group: string): { BasePart }
	local found = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide and collides(part.CollisionGroup, group) then
			table.insert(found, part)
		end
	end
	return found
end

describe("Walking into an enemy meets one upright face (D-198)", function()
	it("a standing boar and kobold: one part meets a player, over the whole of its colliding column", function()
		for _, defId in { "FrenzyBoar", "KoboldAxeman" } do
			fresh()
			local model = standing(defId)
			local root = model.PrimaryPart :: BasePart
			local colliders = collidersWith(model, GROUPS.players)
			expect(#colliders).toBe(1)
			local face = colliders[1]
			local low, high = heights(face)
			-- From below the player's lowest colliding part to above its highest: no edge to climb.
			expect(low).toBeLessThanOrEqual(PLAYER_LOWEST)
			expect(high).toBeGreaterThanOrEqual(PLAYER_HIGHEST)
			-- Upright over the body's footprint (which covers the root's: a body still blocks where
			-- it blocked), and unseen.
			local _, size = RigBuilder.footprint(Enemies.byId(defId).skin)
			expect(face.Size.X).toBeCloseTo(size.X, 1e-4)
			expect(face.Size.Z).toBeCloseTo(size.Z, 1e-4)
			expect(face.Size.X).toBeGreaterThanOrEqual(root.Size.X)
			expect(face.Size.Z).toBeGreaterThanOrEqual(root.Size.Z)
			expect(face.CFrame.UpVector:Dot(Vector3.yAxis)).toBeCloseTo(1, 1e-6)
			expect(face.Transparency).toBe(1)
			-- It meets nothing but players: not the world, not an enemy, not a rush.
			expect(collides(face.CollisionGroup, "Default")).toBe(false)
			expect(collides(face.CollisionGroup, GROUPS.enemies)).toBe(false)
			expect(collides(face.CollisionGroup, GROUPS.rushing)).toBe(false)
		end
	end)

	-- A walk-in seen from above, in the enemy root's space: a player's colliding column (a circle of
	-- PLAYER_RADIUS) comes in along a bearing (degrees from the enemy's front, + = its right) until
	-- it meets the face. Returns how far the player then is from the nearest part of the body at
	-- rest (what it holds aside): 0 touching, under 0 inside it.
	local PLAYER_RADIUS = 0.6
	local function gapAt(model: Model, rig: any, bearing: number): number
		local root = model.PrimaryPart :: BasePart
		local function flat(part: BasePart): (number, number, number, number)
			local half = part.Size / 2
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local corner = root.CFrame:PointToObjectSpace(
							part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						)
						minX, maxX = math.min(minX, corner.X), math.max(maxX, corner.X)
						minZ, maxZ = math.min(minZ, corner.Z), math.max(maxZ, corner.Z)
					end
				end
			end
			return minX, maxX, minZ, maxZ
		end
		-- Signed distance from a point to a flat box (under 0 inside).
		local function distance(x: number, z: number, box: { number }): number
			local dx = math.max(box[1] - x, x - box[2])
			local dz = math.max(box[3] - z, z - box[4])
			if dx <= 0 and dz <= 0 then
				return math.max(dx, dz)
			end
			return math.sqrt(math.max(dx, 0) ^ 2 + math.max(dz, 0) ^ 2)
		end
		local face = collidersWith(model, GROUPS.players)[1]
		local faceBox = { flat(face) }
		local body = {}
		for name in rig.parts do
			if table.find(rig.trailParts or {}, name) == nil then
				table.insert(body, { flat(model:FindFirstChild(name) :: BasePart) })
			end
		end
		local ux, uz = math.sin(math.rad(bearing)), -math.cos(math.rad(bearing))
		-- Bisect the stop: the column meets the face at PLAYER_RADIUS from it.
		local near, far = 0, 40
		for _ = 1, 60 do
			local mid = (near + far) / 2
			if distance(ux * mid, uz * mid, faceBox) < PLAYER_RADIUS then
				near = mid
			else
				far = mid
			end
		end
		local nearest = math.huge
		for _, box in body do
			nearest = math.min(nearest, distance(ux * far, uz * far, box))
		end
		return nearest - PLAYER_RADIUS
	end

	it("a walk-in stops touching the body on every side: snout, flank, tail; never inside it", function()
		for _, defId in { "FrenzyBoar", "KoboldAxeman" } do
			fresh()
			local model = standing(defId)
			local rig = Rigs[Enemies.byId(defId).skin]
			-- Head-on, both flanks and from behind: touching.
			for _, bearing in { 0, 90, 180, 270 } do
				local gap = gapAt(model, rig, bearing)
				expect(math.abs(gap)).toBeLessThan(0.05)
			end
			-- Every bearing: never inside the body, and off it only where one flat box's corner
			-- stands out past a tapering head (the boar's, up to 0.58 studs at 20 degrees off its
			-- snout) or beside a thin tail (0.8 at 160, a tail's length past the rump).
			for bearing = 0, 355, 5 do
				local gap = gapAt(model, rig, bearing)
				expect(gap).toBeGreaterThan(-1e-4) -- float32 sizes
				expect(gap).toBeLessThan(0.85)
			end
		end
	end)

	it("the root still runs on the world and meets its packmates, never a player", function()
		for _, defId in { "FrenzyBoar", "KoboldAxeman" } do
			fresh()
			local model = standing(defId)
			local root = model.PrimaryPart :: BasePart
			expect(root.CanCollide).toBe(true)
			expect(collides(root.CollisionGroup, "Default")).toBe(true)
			expect(collides(root.CollisionGroup, GROUPS.enemies)).toBe(true)
			expect(collides(root.CollisionGroup, GROUPS.players)).toBe(false)
			-- The world meets the root and nothing else of the enemy, as before.
			local world = collidersWith(model, "Default")
			expect(#world).toBe(1)
			expect(world[1]).toBe(root)
		end
	end)

	it("a rush still passes through players (D-167); solid again, the face is back", function()
		fresh()
		local model = standing("FrenzyBoar")
		CollisionGroups.assign(model, GROUPS.rushing)
		expect(#collidersWith(model, GROUPS.players)).toBe(0)
		expect(#collidersWith(model, GROUPS.enemies)).toBe(0)
		CollisionGroups.assign(model, GROUPS.enemies)
		expect(#collidersWith(model, GROUPS.players)).toBe(1)
	end)

	it("nothing else changes: the body's reach, and no blade or query ever meets the face", function()
		local built = RigBuilder.build("Boar")
		local front, back = EnemyService.bodyExtents(built)
		fresh()
		local model = standing("FrenzyBoar")
		local after, afterBack = EnemyService.bodyExtents(model)
		-- The face covers exactly the body's footprint, so the reach is the body's (to float32 sizes).
		expect(after).toBeCloseTo(front, 1e-4)
		expect(afterBack).toBeCloseTo(back, 1e-4)
		local root = model.PrimaryPart :: BasePart
		local face = collidersWith(model, GROUPS.players)[1]
		expect(BladeContact.queryable(face)).toBe(false)
		expect(BladeContact.queryable(root)).toBe(true)
		-- A blade swept across the space over the boar's back, inside the face's box: no hit; the
		-- same blade through the body: a hit.
		local function sweep(y: number): number
			local samples = {
				{
					time = 0,
					start = Vector3.new(-4, y, -0.5),
					finish = Vector3.new(-2, y, -0.5),
					mid = Vector3.new(-3, y, -0.5),
				},
				{
					time = 0.05,
					start = Vector3.new(2, y, -0.5),
					finish = Vector3.new(4, y, -0.5),
					mid = Vector3.new(3, y, -0.5),
				},
			}
			local hits = HitSweep.castBladePath(samples :: any, {
				exclude = {},
				resolve = function(instance: Instance): (number?, Model?)
					if instance:IsDescendantOf(model) then
						return 1, model
					end
					return nil, nil
				end,
				cast = function()
					return nil
				end,
				overlap = function(): { BasePart }
					local parts = {}
					for _, part in model:GetDescendants() do
						if part:IsA("BasePart") then
							table.insert(parts, part)
						end
					end
					return parts
				end,
			})
			return #hits
		end
		local _, top = heights(face)
		expect(sweep(top - 0.5)).toBe(0)
		expect(sweep(root.CFrame.Position.Y)).toBe(1)
	end)
end)
