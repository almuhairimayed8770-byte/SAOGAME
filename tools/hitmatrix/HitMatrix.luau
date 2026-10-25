--!strict
--[[
	HitMatrix: does the server register every hit of every Phase 0 player attack? (section 20, the
	Phase 0 gate: "the server registered every hit"; section 6 "Authority and feel").

	For every attack the Playground loadout carries (its slotted Arts, then the basic chain) and every
	hit window of it, an enemy stands in front of the player at each placement in dev.luau
	hitMatrix.setups (the boar facing, the boar side-on, the kobold) and the swing runs through the
	server's own path: CombatService.beginArt / beginBasic, then EntityService.tick and
	CombatService.tick at 60 Hz with the player's root carried by the clip's root motion (the client
	moves the root, the server reads it), starting at each of hitMatrix.framePhases. CombatService
	sweeps the blade through HitSweep exactly as on a live server; only the two engine queries are
	fakes, and they follow the engine's rules:
	- the spherecast returns the first part the sphere meets along its path and never a part the
	  sphere already overlaps where the cast starts; a fighter part is a hit, any other part (the
	  Playground Field, read from places/Playground.project.json) stops the blade;
	- the bounds query returns every queryable part (CanQuery or CanCollide on) whose bounding box
	  comes within the radius; HitSweep measures the real box itself.

	The player is the engine-style R15 from hitMatrix.avatar, scaled by rigs.luau PlayerR15.scale,
	jointed with AnimationConstraints and armed by WeaponBuilder, its feet on the field. Enemies are
	RigBuilder rigs in their rest pose (the server never animates them) at the height
	PlaygroundService spawns them.

	A cell records, per frame phase, whether the window registered the enemy and which blade sample
	did it (frames after the window opened; "s" when it was an arc sub-sample), and, for a window
	that missed, how close the true blade came to the enemy (traced at
	hitMatrix.clearanceSampleHz): a blade that passes clear of the enemy is choreography to fix; one
	whose hit sphere only grazes it, less deep than the sweep promises (the hit radius less half of
	combat.luau sweepMaxTipStep), is the sweep's stated tolerance; one that passes deeper than that
	is a server fault.

	A registered hit must also land on the strike, not after it: by the first server frame at or
	after its strike's snap ends (ReviewMarkers.strikeSnaps, the n-th snap for the n-th window). The
	snap's end is the contact pose section 10's Hold freezes on; a blade that first meets the enemy
	later, in the settle or the recovery, lands a hit the clip never shows as a strike. Such a cell
	is "late" (choreography to fix, like a miss).

	The client must agree (fix F2, section 6: the client predicts the hit-stop at once, the server
	decides the hit). Every swing is also drawn the way the local client draws it, at each of
	hitMatrix.clientFps and each frame phase: a Mixer poses the same body every rendered frame as
	Choreo does and ContactPredictor sweeps the blade those frames show. A hit the client draws
	that the server does not count is a flash with no number (the review's Horizontal hit 2); a
	hit the server counts that the client does not draw flashes a round trip after the cut (issue
	13). Neither may happen at any placement, the point-blank ones at either shoulder (`bearing`,
	`pointBlank`: inside the blade's start pose, never required to register) included. Both sides
	see the enemy in its rest pose where the server holds it; what a live client adds (an animated
	enemy, its drawn lag, the replicated root's lag) is outside this check.

	An Art swung at an enemy the aim assist would pick (inside its cone and range: every setup but
	the point-blank shoulders) runs with the stand-off the client plans at the release (fix F1,
	ContactPredictor.standOff): when its first cut would start in the body, the root steps back
	over the anticipation on the clip's clock, and the server reads that root as it reads the
	clip's root motion. Every requirement above holds with it.

	Used by tools/hit-matrix.luau (prints the matrix) and tests/server/HitMatrix.spec.luau (fails on
	a real-fight miss). It needs the test harness (`Harness`) to load game modules, and leaves
	CombatService and EntityService reset and HitSweep unwrapped when it returns.
]]

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Instance = roblox.Instance

export type Attack = {
	id: string, -- "OneHandedSword.Horizontal" or "Basic2"
	label: string,
	artId: string?,
	chainIndex: number?, -- basic chain position (1..basicChainLength)
	clipId: string,
	clip: any,
	windows: { { open: number, close: number } },
	-- The strike snap of each window, in order (ReviewMarkers.strikeSnaps; the clips validator keeps
	-- one per window).
	snaps: { { start: number, finish: number } },
}

export type Setup = {
	id: string,
	enemy: string,
	yaw: number,
	-- Degrees to the right of the player's look the enemy's root stands at (0 or nil: straight ahead).
	bearing: number?,
	-- A placement no swing is aimed at (fix F2): the enemy stands at the shoulder, outside the aim
	-- assist's cone, so nothing turns the body to it and its hits are reported, never required. The
	-- client and the server must still agree on every one of them.
	pointBlank: boolean?,
	realFight: { min: number, max: number },
	distances: { number },
}

export type Derived = {
	surface: number, -- how far in front of the enemy's root its body reaches toward the player
	contact: number, -- root distance at which the bodies touch
	reachDistance: number, -- root distance at which the enemy's nearest body point is at weapon reach
	min: number, -- contact rounded up to rangeStep
	max: number, -- reachDistance rounded down to rangeStep
}

export type PhaseResult = {
	phase: number,
	hit: boolean,
	frames: number?, -- the registering sample, in frames after the window opened
	sub: boolean?, -- it was an arc sub-sample, not a frame sample
	landed: number?, -- the server frame that landed the hit, in frames after the window opened
}

export type Cell = {
	attack: string,
	window: number,
	setup: string,
	distance: number,
	real: boolean, -- inside the setup's realFight range
	phases: { PhaseResult },
	hit: boolean, -- registered at every phase
	-- The last server frame a hit may land on and still land on the strike: the first one at or
	-- after the window's snap ends, in frames after the window opened.
	landBy: number,
	late: boolean, -- some phase registered, but only after landBy
	-- Not required to register: outside the setup's realFight range, or a pointBlank setup.
	required: boolean,
	-- The Art stand-off (fix F1) the client stepped back before the swing, in studs; nil for none.
	standOff: number?,
	-- Whether the local client drew this hit at each of its frame rates (dev.luau hitMatrix.clientFps)
	-- and frame phases: ContactPredictor touched the enemy in this window while the client's own
	-- frames posed the swing (fix F2). Nil when the run skipped the client.
	drawn: { Drawn }?,
	-- When some phase missed: the closest the true blade came to the enemy over the window, minus
	-- the hit radius (<= 0: it touches), and the enemy part it came closest to.
	clearance: number?,
	nearestPart: string?,
}

export type Drawn = { fps: number, phase: number, hit: boolean }

export type Report = {
	attacks: { Attack },
	setups: { Setup },
	derived: { [string]: Derived },
	cells: { Cell },
	rootHeight: number,
	weaponReach: number,
	radius: number,
	-- How deep the true blade must reach into a target for the sweep to promise the hit: the hit
	-- radius less half of combat.luau sweepMaxTipStep (every point the blade passes lies within half
	-- a step of a sample). A miss shallower than this is a graze; a deeper one is a server fault.
	promise: number,
}

type Context = {
	Harness: any,
	HitSweep: any,
	CombatService: any,
	EntityService: any,
	ClipSampler: any,
	Pose: any,
	Rigs: any,
	Weapons: any,
	Arts: any,
	Enemies: any,
	Playground: any,
	Combat: any,
	World: any,
	Dev: any,
	RigBuilder: any,
	WeaponBuilder: any,
	PlaygroundLayout: any,
	ReviewMarkers: any,
	Mixer: any,
	Joints: any,
	ContactPredictor: any,
	ActionLogic: any,
	AimLogic: any,
}

export type Avatar = { model: any, root: any, rootHeight: number, base: any, top: number }

export type World = {
	parts: { any },
	cast: (origin: any, radius: number, direction: any, exclude: { any }) -> any,
	overlap: (center: any, radius: number, exclude: { any }) -> { any },
}

local HitMatrix = {}

local FORWARD = Vector3.new(0, 0, -1)
local BISECTIONS = 48 -- halvings of the contact search: far below a micro-stud

local function vec(t: { number }): any
	return Vector3.new(t[1], t[2], t[3])
end

local function load(Harness: any): Context
	local function stub()
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
	end
	stub()
	return {
		Harness = Harness,
		HitSweep = Harness.load("src/server/combat/HitSweep"),
		CombatService = Harness.load("src/server/services/CombatService"),
		EntityService = Harness.load("src/server/services/EntityService"),
		ClipSampler = Harness.load("src/shared/choreo/ClipSampler"),
		Pose = Harness.load("src/shared/choreo/Pose"),
		Rigs = Harness.load("src/shared/data/rigs"),
		Weapons = Harness.load("src/shared/data/weapons"),
		Arts = Harness.load("src/shared/data/arts"),
		Enemies = Harness.load("src/shared/data/enemies"),
		Playground = Harness.load("src/shared/data/playground"),
		Combat = Harness.load("src/shared/data/combat"),
		World = Harness.load("src/shared/data/world"),
		Dev = Harness.load("src/shared/data/dev"),
		RigBuilder = Harness.load("src/server/world/RigBuilder"),
		WeaponBuilder = Harness.load("src/server/world/WeaponBuilder"),
		PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout"),
		ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers"),
		Mixer = Harness.load("src/client/choreo/Mixer"),
		Joints = Harness.load("src/shared/choreo/Joints"),
		ContactPredictor = Harness.load("src/client/controllers/ContactPredictor"),
		ActionLogic = Harness.load("src/client/controllers/ActionLogic"),
		AimLogic = Harness.load("src/client/controllers/AimLogic"),
	}
end

-- ------------------------------------------------------------------------------------------
-- Geometry
-- ------------------------------------------------------------------------------------------

-- The nearest point of a box to a point.
local function closestOnBox(point: any, cframe: any, size: any): any
	local localPoint = cframe:PointToObjectSpace(point)
	local half = size * 0.5
	return cframe:PointToWorldSpace(
		Vector3.new(
			math.clamp(localPoint.X, -half.X, half.X),
			math.clamp(localPoint.Y, -half.Y, half.Y),
			math.clamp(localPoint.Z, -half.Z, half.Z)
		)
	)
end

-- Half extents of a box's world-axis bounds.
local function boundsHalf(cframe: any, size: any): any
	local half = size * 0.5
	local right, up, back = cframe.RightVector, cframe.UpVector, cframe.LookVector
	return Vector3.new(
		math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(back.X) * half.Z,
		math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(back.Y) * half.Z,
		math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(back.Z) * half.Z
	)
end

-- True when two boxes overlap (separating axis test); boxes that only touch do not.
local function boxesOverlap(aFrame: any, aSize: any, bFrame: any, bSize: any): boolean
	local axesA = { aFrame.RightVector, aFrame.UpVector, aFrame.LookVector }
	local axesB = { bFrame.RightVector, bFrame.UpVector, bFrame.LookVector }
	local halfA = { aSize.X * 0.5, aSize.Y * 0.5, aSize.Z * 0.5 }
	local halfB = { bSize.X * 0.5, bSize.Y * 0.5, bSize.Z * 0.5 }
	local offset = bFrame.Position - aFrame.Position
	local function separates(axis: any): boolean
		if axis.Magnitude < 1e-9 then
			return false
		end
		local unit = axis.Unit
		local reachA, reachB = 0, 0
		for index = 1, 3 do
			reachA += math.abs(axesA[index]:Dot(unit)) * halfA[index]
			reachB += math.abs(axesB[index]:Dot(unit)) * halfB[index]
		end
		return math.abs(offset:Dot(unit)) >= reachA + reachB
	end
	for index = 1, 3 do
		if separates(axesA[index]) or separates(axesB[index]) then
			return false
		end
	end
	for i = 1, 3 do
		for j = 1, 3 do
			if separates(axesA[i]:Cross(axesB[j])) then
				return false
			end
		end
	end
	return true
end

local function lowestPoint(cframe: any, size: any): number
	return cframe.Position.Y - boundsHalf(cframe, size).Y
end

local function highestPoint(cframe: any, size: any): number
	return cframe.Position.Y + boundsHalf(cframe, size).Y
end

-- ------------------------------------------------------------------------------------------
-- The fighters
-- ------------------------------------------------------------------------------------------

-- The engine-style player: hitMatrix.avatar scaled by rigs.luau PlayerR15.scale, AnimationConstraint
-- joints between rig attachments, the loadout weapon on WeaponBuilder's Motor6D, feet on the ground.
local function buildAvatar(ctx: Context): Avatar
	local spec = ctx.Dev.hitMatrix.avatar
	local scale = ctx.Rigs.PlayerR15.scale
	local body = Vector3.new(scale.bodyWidth, scale.bodyHeight, scale.bodyDepth)
	local head = Vector3.new(scale.head, scale.head, scale.head)
	local function scaleOf(partName: string): any
		return if partName == "Head" then head else body
	end
	local model = Instance.new("Model")
	model.Name = "MatrixTrialist"
	local parts: { [string]: any } = {}
	for name, size in spec.parts do
		local part = Instance.new("Part")
		part.Name = name
		part.Size = vec(size) * scaleOf(name)
		part.Parent = model
		parts[name] = part
	end
	local rootPart = parts[ctx.Rigs.PlayerR15.rootPart]
	model.PrimaryPart = rootPart
	for _, joint in ctx.Rigs.PlayerR15.joints do
		local pair = spec.attachments[joint.name]
		if pair == nil then
			continue -- the Weapon joint: WeaponBuilder hangs it from the hand
		end
		local part0, part1 = parts[joint.part0], parts[joint.part1]
		assert(part0 ~= nil and part1 ~= nil, "hitMatrix.avatar lacks a part of joint " .. joint.name)
		local attachment0 = Instance.new("Attachment")
		attachment0.Name = joint.name .. "RigAttachment"
		attachment0.CFrame = CFrame.new(vec(pair[1]) * scaleOf(joint.part0))
		attachment0.Parent = part0
		local attachment1 = Instance.new("Attachment")
		attachment1.Name = joint.name .. "RigAttachment"
		attachment1.CFrame = CFrame.new(vec(pair[2]) * scaleOf(joint.part1))
		attachment1.Parent = part1
		local constraint = Instance.new("AnimationConstraint")
		constraint.Name = joint.name
		constraint.Attachment0 = attachment0
		constraint.Attachment1 = attachment1
		constraint.Parent = part1
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	ctx.WeaponBuilder.equip(model, ctx.Weapons.byId(ctx.Playground.loadout.weapon))

	-- The Humanoid holds the root where the feet touch the floor: solve the rest pose from a root
	-- at the origin and lift it by the depth of the lowest body point.
	local solved = ctx.Pose.solve(model, CFrame.new(), {})
	local lowest, highest = math.huge, -math.huge
	for name, part in parts do
		local frame = solved[name]
		if frame ~= nil then
			lowest = math.min(lowest, lowestPoint(frame, part.Size))
			highest = math.max(highest, highestPoint(frame, part.Size))
		end
	end
	local rootHeight = -lowest
	local base = CFrame.new(0, rootHeight, 0) -- at the field center, facing -Z
	rootPart.CFrame = base
	for name, frame in ctx.Pose.solve(model, base, {}) do
		local part = model:FindFirstChild(name, true)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = frame
		end
	end
	return { model = model, root = rootPart, rootHeight = rootHeight, base = base, top = highest + rootHeight }
end

-- Every BasePart of the avatar's own body (not the weapon), at its current CFrame.
local function avatarBodyParts(ctx: Context, avatar: Avatar): { any }
	local list = {}
	for name in ctx.Dev.hitMatrix.avatar.parts do
		local part = avatar.model:FindFirstChild(name)
		if part ~= nil then
			table.insert(list, part)
		end
	end
	return list
end

-- An enemy's rig in its rest pose at a root distance from the player, at the setup's bearing (to
-- the right of the player's look; straight ahead without one), at the height PlaygroundService
-- spawns it, turned by the setup's yaw from facing the player.
local function placeEnemy(ctx: Context, setup: Setup, distance: number): (any, any)
	local def = ctx.Enemies.byId(setup.enemy)
	assert(def ~= nil, "hitMatrix setup names an unknown enemy: " .. setup.enemy)
	local rig = ctx.Rigs[def.skin]
	local model = ctx.RigBuilder.build(def.skin)
	local height =
		ctx.PlaygroundLayout.rootHeight(rig.hipHeight, model.PrimaryPart.Size.Y, ctx.World.spawn.groundEpsilon)
	local bearing = math.rad(setup.bearing or 0)
	local frame = CFrame.new(math.sin(bearing) * distance, height, -math.cos(bearing) * distance)
		* CFrame.Angles(0, math.pi - bearing + math.rad(setup.yaw), 0)
	for name, solved in ctx.Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	return model, def
end

-- The enemy's body: every part but the weapon it holds (rigs.luau trailParts).
local function enemyBodyParts(ctx: Context, model: any, setup: Setup): { any }
	local def = ctx.Enemies.byId(setup.enemy)
	local rig = ctx.Rigs[def.skin]
	local held = rig.trailParts or {}
	local list = {}
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and table.find(held, part.Name) == nil then
			table.insert(list, part)
		end
	end
	return list
end

local function enemyParts(model: any): { any }
	local list = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(list, part)
		end
	end
	return list
end

-- The Playground's Field part as places/Playground.project.json builds it (its box: the cylinder
-- is 400 across, so near the center its box and its shape agree).
local function fieldPart(ctx: Context): any
	local project = serde.decode("json", ctx.Harness.readFile("places/Playground.project.json"))
	local function find(node: any): any
		if typeof(node) ~= "table" then
			return nil
		end
		if node.Field ~= nil and typeof(node.Field) == "table" and node.Field["$className"] == "Part" then
			return node.Field
		end
		for key, child in node do
			if typeof(key) == "string" and key:sub(1, 1) ~= "$" then
				local found = find(child)
				if found ~= nil then
					return found
				end
			end
		end
		return nil
	end
	local node = find(project.tree)
	assert(node ~= nil, "places/Playground.project.json has no Field part")
	local properties = node["$properties"]
	local frame = properties.CFrame.CFrame
	local p, o = frame.position, frame.orientation
	local part = Instance.new("Part")
	part.Name = "Field"
	part.Anchored = true
	part.Size = vec(properties.Size)
	part.CFrame =
		CFrame.new(p[1], p[2], p[3], o[1][1], o[1][2], o[1][3], o[2][1], o[2][2], o[2][3], o[3][1], o[3][2], o[3][3])
	return part
end

--- The matrix's player standing on the Playground field, and the Field part, for checks that pose
--- the same body the matrix swings (tests/choreo/GroundClearance.spec.luau): the avatar's root
--- stands at `base`, its feet on the field's top face.
function HitMatrix.standing(Harness: any): (Avatar, any)
	local ctx = load(Harness)
	return buildAvatar(ctx), fieldPart(ctx)
end

-- ------------------------------------------------------------------------------------------
-- The engine queries
-- ------------------------------------------------------------------------------------------

local function queryable(part: any): boolean
	return part.CanQuery or part.CanCollide
end

-- Where along origin -> origin + direction (0..1) a sphere of `radius` first touches the box, or
-- nil when it never does or already touches it at the origin (the engine never reports that part).
-- In the box's space the squared distance from the moving center to the box is piecewise quadratic
-- in t, with a new piece wherever the path crosses a slab face; it is convex, so the first piece
-- whose quadratic reaches radius squared holds the touch, at that quadratic's smaller root.
local function entryAlong(origin: any, direction: any, radius: number, cframe: any, size: any): number?
	local start = cframe:PointToObjectSpace(origin)
	local slope = cframe:VectorToObjectSpace(direction)
	local o = { start.X, start.Y, start.Z }
	local d = { slope.X, slope.Y, slope.Z }
	local h = { size.X * 0.5, size.Y * 0.5, size.Z * 0.5 }
	local limit = radius * radius
	local function squaredAt(t: number): number
		local total = 0
		for axis = 1, 3 do
			local outside = math.abs(o[axis] + d[axis] * t) - h[axis]
			if outside > 0 then
				total += outside * outside
			end
		end
		return total
	end
	if squaredAt(0) <= limit then
		return nil
	end
	local cuts = { 0, 1 }
	for axis = 1, 3 do
		if d[axis] ~= 0 then
			for _, face in { -h[axis], h[axis] } do
				local t = (face - o[axis]) / d[axis]
				if t > 0 and t < 1 then
					table.insert(cuts, t)
				end
			end
		end
	end
	table.sort(cuts)
	for index = 1, #cuts - 1 do
		local from, to = cuts[index], cuts[index + 1]
		local middle = (from + to) * 0.5
		-- On this piece each axis is below, inside or above its slab throughout.
		local a, b, c = 0, 0, -limit
		for axis = 1, 3 do
			local value = o[axis] + d[axis] * middle
			local offset = if value > h[axis]
				then o[axis] - h[axis]
				elseif value < -h[axis] then o[axis] + h[axis]
				else nil
			if offset ~= nil then
				a += d[axis] * d[axis]
				b += 2 * d[axis] * offset
				c += offset * offset
			end
		end
		if a == 0 then
			if c <= 0 then -- the center runs inside the box on this piece
				return from
			end
		else
			local discriminant = b * b - 4 * a * c
			if discriminant >= 0 then
				-- Within radius between the roots: the touch is where that span first meets the piece.
				local root = math.sqrt(discriminant)
				local enter, leave = (-b - root) / (2 * a), (-b + root) / (2 * a)
				if enter <= to and leave >= from then
					return math.max(enter, from)
				end
			end
		end
	end
	return nil
end

-- One part as the queries see it. Nothing in the world moves while a swing runs (the enemy stands
-- in its rest pose, the field is anchored, the attacker's own parts are always excluded), so each
-- part's frame, size, bounds and ancestry are read once.
type Entry = {
	part: any,
	cframe: any,
	size: any,
	center: any,
	bounds: any, -- half extents of its world-axis bounds
	sphere: number, -- radius of its bounding sphere
	ancestors: { [any]: boolean }, -- itself and everything above it
}

local function entryOf(part: any): Entry
	local ancestors: { [any]: boolean } = {}
	local node = part
	while node ~= nil do
		ancestors[node] = true
		node = node.Parent
	end
	local cframe, size = part.CFrame, part.Size
	return {
		part = part,
		cframe = cframe,
		size = size,
		center = cframe.Position,
		bounds = boundsHalf(cframe, size),
		sphere = size.Magnitude * 0.5,
		ancestors = ancestors,
	}
end

local function excluded(entry: Entry, exclude: { any }): boolean
	for _, instance in exclude do
		if entry.ancestors[instance] then
			return true
		end
	end
	return false
end

local function fakeWorld(parts: { any }): World
	local entries: { Entry } = {}
	for _, part in parts do
		if queryable(part) then -- the engine's query rule: CanQuery or CanCollide
			table.insert(entries, entryOf(part))
		end
	end
	local world = { parts = parts } :: any
	function world.cast(origin: any, radius: number, direction: any, exclude: { any }): any
		local best, bestAlong = nil, math.huge
		local length = direction.Magnitude
		local middle = origin + direction * 0.5
		for _, entry in entries do
			-- Cheap reject: the swept sphere's bounding sphere never meets the part's.
			if (entry.center - middle).Magnitude > length * 0.5 + radius + entry.sphere then
				continue
			end
			if excluded(entry, exclude) then
				continue
			end
			local along = entryAlong(origin, direction, radius, entry.cframe, entry.size)
			if along ~= nil and along < bestAlong then
				best, bestAlong = entry, along
			end
		end
		if best == nil then
			return nil
		end
		local center = origin + direction * bestAlong
		local position = closestOnBox(center, best.cframe, best.size)
		return { Instance = best.part, Position = position, Distance = length * bestAlong }
	end
	function world.overlap(center: any, radius: number, exclude: { any }): { any }
		local found = {}
		for _, entry in entries do
			local half = entry.bounds
			local offset = center - entry.center
			local outside = Vector3.new(
				math.max(math.abs(offset.X) - half.X, 0),
				math.max(math.abs(offset.Y) - half.Y, 0),
				math.max(math.abs(offset.Z) - half.Z, 0)
			)
			if outside.Magnitude <= radius and not excluded(entry, exclude) then
				table.insert(found, entry.part)
			end
		end
		return found
	end
	return world
end

--- The fake engine queries over `parts`, as the matrix uses them (the spec holds them to the
--- engine's rules).
function HitMatrix.world(parts: { any }): World
	return fakeWorld(parts)
end

-- ------------------------------------------------------------------------------------------
-- Attacks
-- ------------------------------------------------------------------------------------------

local function clipOf(ctx: Context, clipId: string): any
	return ctx.Harness.load("src/shared/clips/" .. clipId)
end

--- Every Phase 0 player attack: the loadout's slotted Arts in quick-slot order, then the basic chain.
function HitMatrix.attacks(ctx: Context): { Attack }
	local list: { Attack } = {}
	for _, artId in ctx.Playground.loadout.artSlots do
		local art = ctx.Arts.byId(artId)
		assert(art ~= nil, "playground.luau slots an unknown Art: " .. artId)
		local clip = clipOf(ctx, art.clip)
		table.insert(list, {
			id = artId,
			label = art.name,
			artId = artId,
			clipId = art.clip,
			clip = clip,
			windows = ctx.ClipSampler.hitWindows(clip),
			snaps = ctx.ReviewMarkers.strikeSnaps(clip),
		})
	end
	local weapon = ctx.Weapons.byId(ctx.Playground.loadout.weapon)
	for index = 1, ctx.Combat.basicChainLength do
		local clipId = ("player/%s/Basic%d"):format(weapon.category, index)
		local clip = clipOf(ctx, clipId)
		table.insert(list, {
			id = "Basic" .. index,
			label = "Basic " .. index,
			chainIndex = index,
			clipId = clipId,
			clip = clip,
			windows = ctx.ClipSampler.hitWindows(clip),
			snaps = ctx.ReviewMarkers.strikeSnaps(clip),
		})
	end
	return list
end

-- Where the client has carried the root at a clip time: the start frame plus the clip's root
-- motion, plus the Art stand-off's step (fix F1) when the swing has one.
local function rootAt(ctx: Context, avatar: Avatar, clip: any, time: number, standOff: any?): any
	local start = ctx.ClipSampler.rootMotionAt(clip, 0)
	local now = ctx.ClipSampler.rootMotionAt(clip, time)
	local frame = avatar.base * CFrame.new(now[1] - start[1], now[2] - start[2], now[3] - start[3])
	if standOff ~= nil then
		local easing = ctx.Combat.contact.standOff.easing
		frame += standOff.away * ctx.AimLogic.standOffAt(standOff.distance, standOff.from, standOff.to, time, easing)
	end
	return frame
end

-- The Art stand-off (fix F1) the local client plans at the release against this placement, as
-- CharacterController does: only for an Art, only when the aim assist would pick the enemy (inside
-- its cone and range; a lock turns the body square to it the same way), from the hold pose with
-- the root where the clip has carried it, facing ahead. Nil for a basic swing, the point-blank
-- shoulders (outside the assist) and a start pose already clear of the body.
local function standOffOf(
	ctx: Context,
	avatar: Avatar,
	attack: Attack,
	setup: Setup,
	distance: number,
	enemyModel: any
): any?
	local aim = ctx.Combat.aim
	if
		attack.artId == nil
		or math.abs(setup.bearing or 0) > aim.assistConeDegrees / 2
		or distance > aim.assistRange
		or distance < aim.minFaceDistance
	then
		return nil
	end
	local hold = ctx.ActionLogic.holdClipTime(attack.clip, ctx.Combat.startPoseTime + ctx.Combat.activationHold)
	return ctx.ContactPredictor.standOff(
		avatar.model,
		attack.clip,
		hold,
		rootAt(ctx, avatar, attack.clip, hold),
		enemyModel
	)
end

-- ------------------------------------------------------------------------------------------
-- Real-fight ranges
-- ------------------------------------------------------------------------------------------

local function roundUp(value: number, step: number): number
	return math.ceil(value / step - 1e-9) * step
end

local function roundDown(value: number, step: number): number
	return math.floor(value / step + 1e-9) * step
end

--- Derives a setup's real-fight range from the rigs: where the bodies touch and where the enemy's
--- nearest body point sits at the loadout weapon's reach from the player's root.
function HitMatrix.derive(ctx: Context, avatar: Avatar, setup: Setup): Derived
	local config = ctx.Dev.hitMatrix
	local reach = ctx.Weapons.byId(ctx.Playground.loadout.weapon).reach
	local column = config.bodyColumnHeight
	local bottom, top = Vector3.new(0, 0, 0), Vector3.new(0, column, 0)
	local mine = avatarBodyParts(ctx, avatar)
	local function nearestAt(distance: number): number
		local model = placeEnemy(ctx, setup, distance)
		local nearest = math.huge
		for _, part in enemyBodyParts(ctx, model, setup) do
			local gap = ctx.HitSweep.segmentBoxDistance(bottom, top, part.CFrame, part.Size)
			nearest = math.min(nearest, gap)
		end
		return nearest
	end
	local function touches(distance: number): boolean
		local model = placeEnemy(ctx, setup, distance)
		for _, theirs in enemyBodyParts(ctx, model, setup) do
			for _, part in mine do
				if boxesOverlap(theirs.CFrame, theirs.Size, part.CFrame, part.Size) then
					return true
				end
			end
		end
		return false
	end
	-- Far enough that the whole enemy is in front of the player.
	local far = column * 4
	local surface = far - nearestAt(far)
	local apart, together = far, 0
	assert(touches(together) and not touches(apart), "hitMatrix: the bodies do not separate along the line")
	for _ = 1, BISECTIONS do
		local middle = (apart + together) * 0.5
		if touches(middle) then
			together = middle
		else
			apart = middle
		end
	end
	local step = config.rangeStep
	local reachDistance = surface + reach
	return {
		surface = surface,
		contact = apart,
		reachDistance = reachDistance,
		min = roundUp(apart, step),
		max = roundDown(reachDistance, step),
	}
end

-- ------------------------------------------------------------------------------------------
-- One swing through the server
-- ------------------------------------------------------------------------------------------

type Probe = {
	frameTimes: { [number]: boolean },
	registered: { [number]: { time: number, sub: boolean } }, -- by target id, the latest attribution
}

-- Wraps HitSweep so every hit the sweep finds is attributed to the blade sample that found it: the
-- shortest prefix of the swept path that finds the same target (the real castBladePath, run again
-- on a copy of the window's hit set). bladePath marks the frame samples; the rest are arc sub-samples.
local function instrument(ctx: Context, probe: Probe, attribute: boolean): () -> ()
	local HitSweep = ctx.HitSweep
	if not attribute then
		return function() end
	end
	local originalCast = HitSweep.castBladePath
	local originalPath = HitSweep.bladePath
	HitSweep.bladePath = function(model, rootCFrame, clip, times, ...)
		for _, time in times do
			probe.frameTimes[time] = true
		end
		return originalPath(model, rootCFrame, clip, times, ...) -- pass the ends, `from` and the chain through
	end
	HitSweep.castBladePath = function(samples, options)
		local before = table.clone(options.alreadyHit or {})
		local hits = originalCast(samples, options)
		for _, hit in hits do
			for count = 1, #samples do
				local prefix = table.move(samples, 1, count, 1, {})
				local again = table.clone(options)
				again.alreadyHit = table.clone(before)
				local found = false
				for _, other in originalCast(prefix, again) do
					if other.targetId == hit.targetId then
						found = true
					end
				end
				if found then
					local time = samples[count].time
					probe.registered[hit.targetId] = { time = time, sub = probe.frameTimes[time] ~= true }
					break
				end
			end
		end
		return hits
	end
	return function()
		HitSweep.castBladePath = originalCast
		HitSweep.bladePath = originalPath
	end
end

local noCrit = {
	NextNumber = function()
		return 0.999
	end,
	NextInteger = function(_self, low: number)
		return low
	end,
}

local function resetServices(ctx: Context)
	ctx.CombatService.reset()
	ctx.EntityService.reset()
end

-- Runs one attack at one frame phase against one placed enemy; returns, per hit window, the
-- registering sample (nil: unattributed or never registered) and the clip time of the server frame
-- that landed the hit (nil: that window never registered the enemy).
local function swing(
	ctx: Context,
	avatar: Avatar,
	attack: Attack,
	enemyModel: any,
	enemyDef: any,
	world: World,
	phase: number,
	attribute: boolean,
	standOff: any?
): ({ [number]: { time: number, sub: boolean }? }, { [number]: number })
	local clock = { t = 0 }
	local function now(): number
		return clock.t
	end
	resetServices(ctx)
	ctx.EntityService.bind({
		now = now,
		fireAll = nil,
		heartbeat = nil,
		addTag = function() end,
		removeTag = function() end,
		respawn = function() end,
		playerRemoving = nil,
	})
	ctx.CombatService.bind({
		now = now,
		net = nil,
		heartbeat = nil,
		cast = world.cast,
		overlap = world.overlap,
		random = noCrit,
	})
	ctx.CombatService.start()
	avatar.root.CFrame = avatar.base
	local player = { Name = "MatrixTrialist", DisplayName = "Trialist", UserId = 1 }
	local playerId = ctx.EntityService.registerPlayer(player, avatar.model, ctx.Playground.loadout)
	local enemyId = ctx.EntityService.registerEnemy(enemyModel, enemyDef)

	local probe: Probe = { frameTimes = {}, registered = {} }
	local results: { [number]: { time: number, sub: boolean }? } = {}
	-- hit index -> the clip time of the server frame that landed it (the run starts at clock 0)
	local landed: { [number]: number } = {}
	local restore = instrument(ctx, probe, attribute)
	local connection = ctx.CombatService.HitLanded:Connect(function(applied)
		if applied.targetId == enemyId and landed[applied.hitIndex] == nil then
			landed[applied.hitIndex] = clock.t
			results[applied.hitIndex] = probe.registered[enemyId]
		end
	end)
	local ok, err = pcall(function()
		if attack.artId ~= nil then
			local started, reason = ctx.CombatService.beginArt(playerId, attack.artId, FORWARD)
			assert(started, ("%s did not start: %s"):format(attack.id, tostring(reason)))
		else
			-- The chain advances on every swing inside basicChainWindow; each new swing cancels the last.
			for _ = 1, attack.chainIndex or 1 do
				local started, reason = ctx.CombatService.beginBasic(playerId, FORWARD)
				assert(started, ("%s did not start: %s"):format(attack.id, tostring(reason)))
			end
		end
		local frame = 1 / ctx.Combat.hitSampleHz
		local last = attack.windows[#attack.windows].close + frame * 2
		local previous = 0
		local tick = 0
		while true do
			local time = (phase + tick) * frame
			if time > last then
				break
			end
			clock.t = time
			avatar.root.CFrame = rootAt(ctx, avatar, attack.clip, time, standOff)
			ctx.EntityService.tick(time - previous)
			ctx.CombatService.tick()
			previous = time
			tick += 1
		end
	end)
	connection:Disconnect()
	restore()
	resetServices(ctx)
	avatar.root.CFrame = avatar.base
	if not ok then
		error(err, 0)
	end
	return results, landed
end

-- Runs one attack the way the local client draws it, at one frame rate and phase (fix F2): a Mixer
-- poses the body every rendered frame as Choreo does (joint Transforms, the root carried by the
-- clip's root motion) and ContactPredictor sweeps the blade that frame shows against the placed
-- enemy, as CharacterController's render step does. Returns the windows it drew a touch of the
-- enemy in. The hit-stop a touch starts only delays the frames after it, so the run does not hold.
-- An Art's stand-off moves the root on the clip's clock, as CharacterController.stepStandOff does.
local function drawSwing(
	ctx: Context,
	avatar: Avatar,
	attack: Attack,
	enemyModel: any,
	enemyDef: any,
	fps: number,
	phase: number,
	standOff: any?
): { [number]: boolean }
	local weapon = ctx.Weapons.byId(ctx.Playground.loadout.weapon)
	local art = if attack.artId ~= nil then ctx.Arts.byId(attack.artId) else nil
	local scaled = ctx.Enemies.scaled(enemyDef)
	local me = { id = 1, model = avatar.model, kind = "Player", state = if art ~= nil then "Art" else "Basic" }
	local enemy = {
		id = 2,
		model = enemyModel,
		kind = "Enemy",
		state = "Idle",
		defId = enemyDef.id,
		hp = scaled.hp,
		maxHp = scaled.hp,
		elite = false,
	}
	local targets = { me, enemy }
	local predictor = ctx.ContactPredictor.new({
		targets = function(): { any }
			return targets
		end,
	})
	local joints = ctx.Joints.list(avatar.model)
	local function pose(offsets: { [string]: any }?)
		for _, joint in joints do
			local offset = if offsets ~= nil then offsets[joint.Name] else nil
			joint.Transform = if offset ~= nil then ctx.ClipSampler.toCFrame(offset) else CFrame.identity
		end
	end
	avatar.root.CFrame = avatar.base
	local mixer = ctx.Mixer.new()
	local handle = mixer:play(attack.clip)
	local began = predictor:begin({
		model = avatar.model,
		clip = attack.clip,
		artId = attack.artId,
		finalHit = art ~= nil or (attack.chainIndex or 1) >= ctx.Combat.basicChainLength,
		multiplier = if art ~= nil then art.multiplier else ctx.Combat.basicAttackMultiplier,
		weaponAttack = weapon.attack,
	})
	assert(began, attack.id .. ": the client has no window to sweep")
	local drawn: { [number]: boolean } = {}
	local frame = 1 / fps
	local last = attack.windows[#attack.windows].close + frame * 2
	local previous, tick = 0, 0
	local stepped = 0
	while true do
		local time = (phase + tick) * frame
		if time > last then
			break
		end
		if time > previous then
			local result = mixer:step(time - previous)
			pose(result.offsets)
			local delta = result.rootDelta
			avatar.root.CFrame = avatar.root.CFrame + Vector3.new(delta[1], delta[2], delta[3])
			if standOff ~= nil then
				local shown = ctx.AimLogic.standOffAt(
					standOff.distance,
					standOff.from,
					standOff.to,
					handle.time,
					ctx.Combat.contact.standOff.easing
				)
				avatar.root.CFrame = avatar.root.CFrame + standOff.away * (shown - stepped)
				stepped = shown
			end
			for _, contact in predictor:step(handle.time) do
				if contact.targetId == enemy.id then
					drawn[contact.windowIndex] = true
				end
			end
		end
		previous = time
		tick += 1
	end
	predictor:stop()
	pose(nil)
	avatar.root.CFrame = avatar.base
	return drawn
end

-- The true blade over one window, traced finely, with the root carried by root motion.
local function bladeTrack(
	ctx: Context,
	avatar: Avatar,
	attack: Attack,
	window: { open: number, close: number },
	standOff: any?
): { any }
	local trailStart, trailEnd = ctx.HitSweep.trailAttachments(avatar.model)
	local step = 1 / ctx.Dev.hitMatrix.clearanceSampleHz
	local track = {}
	local count = math.max(math.ceil((window.close - window.open) / step), 1)
	for index = 0, count do
		local time = window.open + (window.close - window.open) * index / count
		local sample = ctx.HitSweep.bladeAt(
			avatar.model,
			rootAt(ctx, avatar, attack.clip, time, standOff),
			attack.clip,
			time,
			trailStart,
			trailEnd
		)
		assert(sample ~= nil, "the matrix avatar cannot place its blade")
		table.insert(track, sample)
	end
	return track
end

local function clearanceOf(ctx: Context, track: { any }, parts: { any }, radius: number): (number, string)
	local best, bestPart = math.huge, ""
	for _, sample in track do
		for _, part in parts do
			local gap = ctx.HitSweep.segmentBoxDistance(sample.start, sample.finish, part.CFrame, part.Size)
			if gap < best then
				best, bestPart = gap, part.Name
			end
		end
	end
	return best - radius, bestPart
end

-- ------------------------------------------------------------------------------------------
-- The matrix
-- ------------------------------------------------------------------------------------------

export type Options = {
	setups: { string }?, -- only these setup ids
	attacks: { string }?, -- only these attack ids
	realOnly: boolean?, -- only the placements inside realFight
	phases: { number }?, -- override hitMatrix.framePhases
	-- Skip naming the blade sample that registered each hit (the spec only needs hit or miss); a
	-- hit then reports frames = nil.
	skipAttribution: boolean?,
	-- Skip drawing each swing on the client (cells then carry no `drawn`).
	skipClient: boolean?,
}

-- A Pose.solve made without a Pose.chain walks the rig for its joints (the live sweep reads one
-- chain per fighter per frame). Nothing here changes a rig's joints while the matrix runs, so the
-- walk is done once per model: the same joints, read once (a speedup only; every solve still runs
-- Pose's own forward kinematics). Returns the undo.
local function rememberJoints(ctx: Context): () -> ()
	local Joints = ctx.Harness.load("src/shared/choreo/Joints")
	local original = Joints.collect
	local cache: { [any]: any } = {}
	Joints.collect = function(root)
		local known = cache[root]
		if known == nil then
			known = original(root)
			cache[root] = known
		end
		return known
	end
	return function()
		Joints.collect = original
	end
end

--- Runs the whole matrix. Leaves CombatService and EntityService reset.
function HitMatrix.run(Harness: any, options: Options?): Report
	local opts: Options = options or {}
	local ctx = load(Harness)
	local forgetJoints = rememberJoints(ctx)
	local config = ctx.Dev.hitMatrix
	local radius = ctx.Combat.hitSphereRadius
	local avatar = buildAvatar(ctx)
	local field = fieldPart(ctx)
	local attacks = HitMatrix.attacks(ctx)
	local phases = opts.phases or config.framePhases
	local report: Report = {
		attacks = attacks,
		setups = config.setups,
		derived = {},
		cells = {},
		rootHeight = avatar.rootHeight,
		weaponReach = ctx.Weapons.byId(ctx.Playground.loadout.weapon).reach,
		radius = radius,
		promise = radius - ctx.Combat.sweepMaxTipStep / 2,
	}
	local ok, err = pcall(function()
		for _, setup in config.setups do
			report.derived[setup.id] = HitMatrix.derive(ctx, avatar, setup)
		end
		-- The true blade of a window, traced the first time a miss needs it.
		local tracks: { [string]: { any } } = {}
		local function trackOf(attack: Attack, index: number, standOff: any?): { any }
			local key = attack.id .. "#" .. index
			if standOff ~= nil then
				local step = standOff.away * standOff.distance
				key ..= ("@%.3f,%.3f,%.3f"):format(step.X, step.Y, step.Z)
			end
			local track = tracks[key]
			if track == nil then
				track = bladeTrack(ctx, avatar, attack, attack.windows[index], standOff)
				tracks[key] = track
			end
			return track
		end
		for _, setup in config.setups do
			if opts.setups ~= nil and table.find(opts.setups, setup.id) == nil then
				continue
			end
			for _, distance in setup.distances do
				local real = distance >= setup.realFight.min - 1e-9 and distance <= setup.realFight.max + 1e-9
				if opts.realOnly and not real then
					continue
				end
				local enemyModel, enemyDef = placeEnemy(ctx, setup, distance)
				local parts = enemyParts(enemyModel)
				local worldParts = table.clone(parts)
				table.insert(worldParts, field)
				for _, part in avatar.model:GetDescendants() do
					if part:IsA("BasePart") then
						table.insert(worldParts, part)
					end
				end
				local world = fakeWorld(worldParts)
				for _, attack in attacks do
					if opts.attacks ~= nil and table.find(opts.attacks, attack.id) == nil then
						continue
					end
					local standOff = standOffOf(ctx, avatar, attack, setup, distance, enemyModel)
					local byPhase, landedByPhase, drawnByPhase = {}, {}, {}
					for _, phase in phases do
						byPhase[phase], landedByPhase[phase] = swing(
							ctx,
							avatar,
							attack,
							enemyModel,
							enemyDef,
							world,
							phase,
							not opts.skipAttribution,
							standOff
						)
						if not opts.skipClient then
							local byFps = {}
							for _, fps in config.clientFps do
								byFps[fps] = drawSwing(ctx, avatar, attack, enemyModel, enemyDef, fps, phase, standOff)
							end
							drawnByPhase[phase] = byFps
						end
					end
					for index, window in attack.windows do
						local hz = ctx.Combat.hitSampleHz
						-- The first server frame at or after the strike's snap ends (without a snap,
						-- which the clips validator rejects, the window's own close).
						local snap = attack.snaps[index]
						local landBy = ((if snap ~= nil then snap.finish else window.close) - window.open) * hz + 1
						local results: { PhaseResult } = {}
						local all, late = true, false
						for _, phase in phases do
							local found = byPhase[phase][index]
							local landedAt = landedByPhase[phase][index]
							if landedAt == nil then
								all = false
								table.insert(results, { phase = phase, hit = false })
							else
								local landed = (landedAt - window.open) * hz
								if landed > landBy + 1e-6 then
									late = true
								end
								table.insert(results, {
									phase = phase,
									hit = true,
									frames = if found ~= nil then (found.time - window.open) * hz else nil,
									sub = if found ~= nil then found.sub else nil,
									landed = landed,
								})
							end
						end
						local drawn: { Drawn }? = nil
						if not opts.skipClient then
							local list: { Drawn } = {}
							for _, fps in config.clientFps do
								for _, phase in phases do
									table.insert(
										list,
										{ fps = fps, phase = phase, hit = drawnByPhase[phase][fps][index] == true }
									)
								end
							end
							drawn = list
						end
						local clearance, nearest = nil, nil
						if not all then
							clearance, nearest = clearanceOf(ctx, trackOf(attack, index, standOff), parts, radius)
						end
						table.insert(report.cells, {
							attack = attack.id,
							window = index,
							setup = setup.id,
							distance = distance,
							real = real,
							phases = results,
							hit = all,
							landBy = landBy,
							late = late,
							required = real and not setup.pointBlank,
							standOff = if standOff ~= nil then standOff.distance else nil,
							drawn = drawn,
							clearance = clearance,
							nearestPart = nearest,
						})
					end
				end
			end
		end
	end)
	resetServices(ctx)
	forgetJoints()
	if not ok then
		error(err, 0)
	end
	return report
end

-- ------------------------------------------------------------------------------------------
-- Reporting
-- ------------------------------------------------------------------------------------------

local function labelOf(report: Report, attackId: string, window: number): string
	for _, attack in report.attacks do
		if attack.id == attackId then
			if #attack.windows > 1 then
				return ("%s hit %d"):format(attack.label, window)
			end
			return attack.label
		end
	end
	return attackId
end

local function distanceLabel(distance: number): string
	local text = ("%.2f"):format(distance)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return text
end

--- One line per required cell (real fight, not point-blank) that did not register at every frame phase.
function HitMatrix.misses(report: Report): { string }
	local lines = {}
	for _, cell in report.cells do
		if cell.required and not cell.hit then
			local missed = {}
			for _, result in cell.phases do
				if not result.hit then
					table.insert(missed, distanceLabel(result.phase))
				end
			end
			local clearance = cell.clearance or math.huge
			local why = if clearance <= -report.promise
				then ("the blade passes %.2f deep into %s, past the sweep's promise: a server miss"):format(
					-clearance,
					tostring(cell.nearestPart)
				)
				elseif clearance <= 0 then ("the blade's rim grazes %s (%.2f deep, the sweep promises %.2f)"):format(
					tostring(cell.nearestPart),
					-clearance,
					report.promise
				)
				else ("the blade passes %.2f studs clear (nearest %s)"):format(
					clearance,
					tostring(cell.nearestPart)
				)
			table.insert(
				lines,
				("%s vs %s at %s studs: no hit at frame phase %s; %s"):format(
					labelOf(report, cell.attack, cell.window),
					cell.setup,
					distanceLabel(cell.distance),
					table.concat(missed, ", "),
					why
				)
			)
		end
	end
	return lines
end

--- One line per real-fight cell that registered but landed after its strike at some frame phase:
--- the blade first meets the enemy in the settle or the recovery, past the contact pose.
function HitMatrix.lateHits(report: Report): { string }
	local lines = {}
	for _, cell in report.cells do
		if cell.required and cell.late then
			local worst, phases = -math.huge, {}
			for _, result in cell.phases do
				if result.landed ~= nil and result.landed > cell.landBy + 1e-6 then
					worst = math.max(worst, result.landed)
					table.insert(phases, distanceLabel(result.phase))
				end
			end
			table.insert(
				lines,
				("%s vs %s at %s studs: lands %.2f frames after its window opens at frame phase %s, after its strike (by %.2f): the blade meets the enemy only in the settle or the recovery"):format(
					labelOf(report, cell.attack, cell.window),
					cell.setup,
					distanceLabel(cell.distance),
					worst,
					table.concat(phases, ", "),
					cell.landBy
				)
			)
		end
	end
	return lines
end

local function phaseList(cell: Cell, pick: (result: PhaseResult) -> boolean): string
	local list = {}
	for _, result in cell.phases do
		if pick(result) then
			table.insert(list, distanceLabel(result.phase))
		end
	end
	return table.concat(list, ", ")
end

-- The client frame rates and phases at which a cell's hit was drawn (`hit` true) or not.
local function drawnList(drawn: { Drawn }, hit: boolean): string
	local list = {}
	for _, entry in drawn do
		if entry.hit == hit then
			table.insert(list, ("%d fps phase %s"):format(entry.fps, distanceLabel(entry.phase)))
		end
	end
	return table.concat(list, ", ")
end

local function anyDrawn(drawn: { Drawn }, hit: boolean): boolean
	for _, entry in drawn do
		if entry.hit == hit then
			return true
		end
	end
	return false
end

--- One line per cell, at every placement, where the local client draws a hit the server does not
--- count (fix F2, section 6: the client predicts the hit-stop, the server decides the hit): some
--- client frame rate and phase drew the touch while some server frame phase did not register it.
--- The client's frames and the server's are not in step, so a hit drawn at any of them must
--- register at every server phase.
function HitMatrix.drawnNotCounted(report: Report): { string }
	local lines = {}
	for _, cell in report.cells do
		local drawn = cell.drawn
		if drawn == nil or cell.hit or not anyDrawn(drawn, true) then
			continue
		end
		table.insert(
			lines,
			("%s vs %s at %s studs: the client draws the hit (%s), the server misses it at frame phase %s"):format(
				labelOf(report, cell.attack, cell.window),
				cell.setup,
				distanceLabel(cell.distance),
				drawnList(drawn, true),
				phaseList(cell, function(result: PhaseResult): boolean
					return not result.hit
				end)
			)
		)
	end
	return lines
end

--- One line per cell where the server counts a hit the local client does not draw at some frame
--- rate and phase: the flash then waits for HitConfirmed, a round trip after the cut (issue 13).
function HitMatrix.countedNotDrawn(report: Report): { string }
	local lines = {}
	for _, cell in report.cells do
		local drawn = cell.drawn
		if drawn == nil or not anyDrawn(drawn, false) then
			continue
		end
		local counted = false
		for _, result in cell.phases do
			counted = counted or result.hit
		end
		if not counted then
			continue
		end
		table.insert(
			lines,
			("%s vs %s at %s studs: the server counts the hit, the client does not draw it (%s)"):format(
				labelOf(report, cell.attack, cell.window),
				cell.setup,
				distanceLabel(cell.distance),
				drawnList(drawn, false)
			)
		)
	end
	return lines
end

--- Every setup whose data range differs from the one the rigs derive.
function HitMatrix.rangeProblems(report: Report): { string }
	local lines = {}
	for _, setup in report.setups do
		local derived = report.derived[setup.id]
		if derived == nil then
			continue
		end
		if math.abs(setup.realFight.min - derived.min) > 1e-6 or math.abs(setup.realFight.max - derived.max) > 1e-6 then
			table.insert(
				lines,
				("%s: realFight is %s..%s, the rigs derive %s..%s"):format(
					setup.id,
					distanceLabel(setup.realFight.min),
					distanceLabel(setup.realFight.max),
					distanceLabel(derived.min),
					distanceLabel(derived.max)
				)
			)
		end
	end
	return lines
end

--- The matrix as Markdown-ish text: one table per setup, a row per hit, a column per distance.
function HitMatrix.render(report: Report): { string }
	local lines = {}
	table.insert(lines, "Server hit matrix (section 20 Phase 0 gate: the server registered every hit)")
	table.insert(
		lines,
		("Player: engine-style R15 scaled by rigs.luau PlayerR15.scale, root %.2f above the field; hit radius %.2f; weapon reach %.2f."):format(
			report.rootHeight,
			report.radius,
			report.weaponReach
		)
	)
	table.insert(lines, "Cell: the blade sample that first registered the enemy, in frames after the window opened")
	table.insert(lines, "(worst frame phase; 's' = an arc sub-sample). 'miss c' = never registered and the true blade")
	table.insert(lines, "passes c studs clear of the enemy; 'graze d' = never registered and the blade's rim touches")
	table.insert(
		lines,
		("it d deep, less than the %.2f the sweep promises; 'MISS! d' = never registered though the blade"):format(
			report.promise
		)
	)
	table.insert(lines, "passes d deep (a server fault); 'miss@p d' = registered except at frame phase p, the blade's")
	table.insert(
		lines,
		"deepest pass d (MISS!@p when d is past the promise); 'LATE' = registered, but some phase landed"
	)
	table.insert(lines, "after the first server frame past its strike's snap (in the settle or recovery). Distances in")
	table.insert(lines, "parentheses are outside the setup's real-fight range and are not required; a point-blank")
	table.insert(lines, "setup stands at the shoulder, outside the aim assist, and is never required. ' !drawn' marks")
	table.insert(lines, "a cell the client and the server disagree on (some client frame rate or phase drew a hit")
	table.insert(lines, "the server missed, or missed one it counted). ' <s' marks an Art swung after a stand-off of s")
	table.insert(lines, "studs (fix F1: its first cut would have started in the body).")
	for _, setup in report.setups do
		local derived = report.derived[setup.id]
		table.insert(lines, "")
		table.insert(
			lines,
			("### %s (%s, yaw %d, bearing %d): %s %s..%s studs"):format(
				setup.id,
				setup.enemy,
				setup.yaw,
				setup.bearing or 0,
				if setup.pointBlank then "point-blank, reported and never required," else "real fight",
				distanceLabel(setup.realFight.min),
				distanceLabel(setup.realFight.max)
			)
		)
		if derived ~= nil then
			table.insert(
				lines,
				("derived: bodies touch at %.3f, the body reaches %.3f in front of its root, at weapon reach from %.3f"):format(
					derived.contact,
					derived.surface,
					derived.reachDistance
				)
			)
		end
		local header = "| hit |"
		local rule = "|---|"
		for _, distance in setup.distances do
			local real = distance >= setup.realFight.min - 1e-9 and distance <= setup.realFight.max + 1e-9
			header ..= (if real then " %s |" else " (%s) |"):format(distanceLabel(distance))
			rule ..= "---|"
		end
		table.insert(lines, header)
		table.insert(lines, rule)
		for _, attack in report.attacks do
			for index in attack.windows do
				local row = ("| %s |"):format(labelOf(report, attack.id, index))
				local any = false
				for _, distance in setup.distances do
					local found
					for _, cell in report.cells do
						if
							cell.setup == setup.id
							and cell.attack == attack.id
							and cell.window == index
							and cell.distance == distance
						then
							found = cell
						end
					end
					if found == nil then
						row ..= " |"
						continue
					end
					any = true
					local text
					if found.hit then
						local worst, sub = -math.huge, false
						for _, result in found.phases do
							if (result.frames or 0) > worst then
								worst, sub = result.frames or 0, result.sub == true
							end
						end
						text = ("%s+%.2f%s"):format(if found.late then "LATE " else "", worst, if sub then "s" else "")
					else
						local missed, hitSome = {}, false
						for _, result in found.phases do
							if result.hit then
								hitSome = true
							else
								table.insert(missed, distanceLabel(result.phase))
							end
						end
						local clearance = found.clearance or math.huge
						if hitSome then
							text = ("%s@%s %.2f"):format(
								if clearance <= -report.promise then "MISS!" else "miss",
								table.concat(missed, ","),
								-clearance
							)
						elseif clearance <= -report.promise then
							text = ("MISS! %.2f"):format(-clearance)
						elseif clearance <= 0 then
							text = ("graze %.2f"):format(-clearance)
						else
							text = ("miss %.2f"):format(clearance)
						end
					end
					local drawn = found.drawn
					if drawn ~= nil then
						local counted = false
						for _, result in found.phases do
							counted = counted or result.hit
						end
						if (anyDrawn(drawn, true) and not found.hit) or (counted and anyDrawn(drawn, false)) then
							text ..= " !drawn"
						end
					end
					if found.standOff ~= nil then
						text ..= (" <%s"):format(distanceLabel(found.standOff))
					end
					row ..= " " .. text .. " |"
				end
				if any then
					table.insert(lines, row)
				end
			end
		end
	end
	return lines
end

return HitMatrix
