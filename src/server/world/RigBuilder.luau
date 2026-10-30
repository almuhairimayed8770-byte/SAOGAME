--!strict
--[[
	RigBuilder: part-built placeholder rigs from rigs.luau (section 10 "Rigs", section 19 asset
	pipeline, D-009). A rig definition lists its parts (size, color, shape) and its joints (Motor6D
	name, Part0, Part1, rest pose); this module turns one into a Model the Choreo animator, the
	Humanoid mover and the server hit sweep can all use:

	- one SmoothPlastic Part per `rig.parts` entry, flat palette color, unanchored, CanCollide only
	  on the root; every limb is Massless while the root keeps its mass and the highest RootPriority,
	  so the engine's assembly root is always the HumanoidRootPart (a Humanoid only moves the
	  assembly root; with every part massless the engine would pick the biggest part instead, the
	  Kobold's Torso); the root is the PrimaryPart;
	- a Humanoid for MoveTo (D-012: its health is pinned by EntityService), HipHeight from the rig,
	  no neck requirement, no auto-rotate (the AI owns the yaw), no name or health display: the
	  engine's own label is off for every viewer (DisplayDistanceType None; under the default
	  Viewer the viewer's distances apply, so a rig showed the engine's name over the nameplate);
	- a Motor6D per joint, parented to its Part1 like R15: C0 = the rest pose (studs and degrees),
	  C1 = the joint's position relative to Part1's center when the rig gives one, else identity
	  so Part1's center sits at the joint (the rigs.luau convention);
	- every part placed at its rest pose through Pose.solve, so the model is coherent before the
	  engine's physics takes over and PivotTo / GetBoundingBox work on the frame it is built;
	- a WeaponGrip attachment on `rig.weaponGrip` (at the Weapon joint's position on that part) and
	  TrailStart / TrailEnd attachments on each `rig.trailParts` part along its long axis, at the
	  fx.luau placeholder fractions (guard near the grip, tip at the far end);
	- the CollectionService tag Placeholder and the attribute Rig = rig id.

	addBlocker (D-198) gives an enemy its blocker: what a player bumps into instead of the root,
	upright, invisible boxes from the floor (HipHeight below the root's bottom) to
	ai.collision.blockerHeight, welded to the root, massless, in the blockers group and switched off
	until CollisionGroups.assign puts the enemy in the enemies group. One face over the body's
	footprint (footprint: the flat box over every part but the ones it holds), and one over each
	part it holds (D-315), each over the part as it stands at rest and in every pose of the loops it
	stands in (rigs.luau `blocker`: its idle). Over the whole body, not the root alone, and over
	what it shows standing, so a walk-in stops where the player touches it on every side: at the
	boar's snout and tail as at its flank, never inside its head, a kobold's hunched head and arms
	or the axe it holds; the axe's own face leaves a player who walks in head-on at the chest.

	Everything here runs under Lune's Instance implementation, so the shape of every rig is tested.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local Rigs = require(Shared.data.rigs)
local Palette = require(Shared.data.palette)
local Fx = require(Shared.data.fx)
local WeaponModels = require(Shared.data.weaponModels)
local Pose = require(Shared.choreo.Pose)
local BodyShell = require(Shared.choreo.BodyShell)
local ClipSampler = require(Shared.choreo.ClipSampler)
local AI = require(Shared.data.ai)

export type Frame = { pos: Types.Vec3, rot: Types.Vec3 }

local RigBuilder = {}

RigBuilder.TAG = WeaponModels.tag
RigBuilder.RIG_ATTRIBUTE = "Rig"

local PART_SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

-- The root part's RootPriority: one above every limb's default, so it is the assembly root.
local ROOT_PRIORITY = 1

-- The name of an enemy's blocker part over its body (addBlocker, D-198).
local BLOCKER_NAME = "Blocker"
RigBuilder.BLOCKER_NAME = BLOCKER_NAME
-- The name of the blocker part over each part an enemy holds (addBlocker, D-315).
local HELD_BLOCKER_NAME = "HeldBlocker"
RigBuilder.HELD_BLOCKER_NAME = HELD_BLOCKER_NAME

--- One blocker face in its root's space: the part's name (BLOCKER_NAME or HELD_BLOCKER_NAME), the
--- flat box's centre and size (Y 0), and the rig parts it stands over.
export type Footprint = { name: string, centre: Vector3, size: Vector3, parts: { string } }

local function toVector3(v: Types.Vec3): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

--- The CFrame a rigs.luau rest-pose entry describes: position in studs, XYZ Euler rotation in degrees.
function RigBuilder.frameOf(frame: Frame): CFrame
	local rot = frame.rot
	return CFrame.new(toVector3(frame.pos))
		* CFrame.fromEulerAnglesXYZ(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
end

--- The unit axis of a size's longest dimension and the extent along it (Y wins ties: blades point +Y).
function RigBuilder.longAxis(size: Vector3): (Vector3, number)
	if size.Y >= size.X and size.Y >= size.Z then
		return Vector3.yAxis, size.Y
	elseif size.Z >= size.X then
		return Vector3.zAxis, size.Z
	end
	return Vector3.xAxis, size.X
end

local function sortedPartNames(parts: { [string]: any }): { string }
	local names = {}
	for name in parts do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function makePart(name: string, spec: { size: Types.Vec3, color: string, shape: string? }, isRoot: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = toVector3(spec.size)
	part.Shape = PART_SHAPES[spec.shape or "Block"] or Enum.PartType.Block
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Palette.color3(spec.color :: Palette.Token)
	part.Anchored = false
	part.CanCollide = isRoot
	part.Massless = not isRoot
	if isRoot then
		part.RootPriority = ROOT_PRIORITY
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function makeHumanoid(rig: Rigs.Rig): Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = rig.hipHeight
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.BreakJointsOnDeath = false
	if rig.walkSpeed ~= nil then
		humanoid.WalkSpeed = rig.walkSpeed
	end
	return humanoid
end

local function addAttachment(part: BasePart, name: string, cframe: CFrame): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = cframe
	attachment.Parent = part
	return attachment
end

-- The joint that hangs a weapon from the grip part (Part0 is the grip part and Part1 is a trail part
-- or is named Weapon), or nil for rigs that carry none.
local function weaponJointOf(rig: Rigs.Rig): Rigs.PlaceholderJoint?
	local gripPart = rig.weaponGrip
	if gripPart == nil then
		return nil
	end
	local trailParts = rig.trailParts or {}
	for _, joint in rig.joints do
		if
			joint.part0 == gripPart and (joint.part1 == WeaponModels.bladePart or table.find(trailParts, joint.part1))
		then
			return joint
		end
	end
	return nil
end

--- The rig definition a part-built model is made from; errors for unknown or engine-built rigs.
function RigBuilder.definition(rigId: string): Rigs.Rig
	local rig = Rigs[rigId]
	if rig == nil then
		error(("RigBuilder: rigs.luau has no rig '%s'"):format(tostring(rigId)))
	end
	if rig.parts == nil then
		error(
			("RigBuilder: rig '%s' is engine-built (no parts table); only placeholder rigs are assembled here"):format(
				rigId
			)
		)
	end
	return rig
end

--- Builds the placeholder Model for a rig id; `name` becomes the Model's name (the rig id when nil).
function RigBuilder.build(rigId: string, name: string?): Model
	local rig = RigBuilder.definition(rigId)
	local specs = rig.parts :: { [string]: { size: Types.Vec3, color: string, shape: string? } }

	local model = Instance.new("Model")
	model.Name = name or rig.id

	-- Parts, in a stable order so two builds of one rig are identical.
	local parts: { [string]: BasePart } = {}
	for _, partName in sortedPartNames(specs) do
		local part = makePart(partName, specs[partName], partName == rig.rootPart)
		part.Parent = model
		parts[partName] = part
	end
	local root = parts[rig.rootPart]
	if root == nil then
		error(("RigBuilder: rig '%s' names root part '%s' but has no such part"):format(rig.id, rig.rootPart))
	end
	model.PrimaryPart = root

	makeHumanoid(rig).Parent = model

	-- Joints: a Motor6D per rigs.luau joint, parented to Part1 (the R15 convention).
	for _, joint in rig.joints do
		local part0 = parts[joint.part0]
		local part1 = parts[joint.part1]
		if part0 == nil or part1 == nil then
			error(
				("RigBuilder: joint %s of rig '%s' links %s -> %s, which the parts table does not define"):format(
					joint.name,
					rig.id,
					joint.part0,
					joint.part1
				)
			)
		end
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = RigBuilder.frameOf(joint.c0)
		motor.C1 = if joint.c1 ~= nil then RigBuilder.frameOf(joint.c1 :: Frame) else CFrame.identity
		motor.Parent = part1
	end

	-- Rest pose: every part where its chain of joints puts it, with the root at the origin.
	local solved = Pose.solve(model, CFrame.identity, {})
	for partName, cframe in solved do
		local part = parts[partName]
		if part ~= nil then
			part.CFrame = cframe
		end
	end

	-- Attachments: the grip and the trail ends.
	local weaponJoint = weaponJointOf(rig)
	local gripPartName = rig.weaponGrip
	if gripPartName ~= nil then
		local gripPart = parts[gripPartName]
		if gripPart == nil then
			error(("RigBuilder: rig '%s' names weaponGrip '%s' but has no such part"):format(rig.id, gripPartName))
		end
		local gripFrame = if weaponJoint ~= nil then RigBuilder.frameOf(weaponJoint.c0) else CFrame.identity
		addAttachment(gripPart, WeaponModels.attachments.grip, gripFrame)
	end
	for _, trailPartName in rig.trailParts or {} do
		local trailPart = parts[trailPartName]
		if trailPart == nil then
			error(("RigBuilder: rig '%s' lists trail part '%s' but has no such part"):format(rig.id, trailPartName))
		end
		local axis, extent = RigBuilder.longAxis(trailPart.Size)
		addAttachment(
			trailPart,
			WeaponModels.attachments.trailStart,
			CFrame.new(axis * extent * Fx.trail.placeholderStart)
		)
		addAttachment(trailPart, WeaponModels.attachments.trailEnd, CFrame.new(axis * extent * Fx.trail.placeholderEnd))
	end

	model:SetAttribute(RigBuilder.RIG_ATTRIBUTE, rig.id)
	model:AddTag(RigBuilder.TAG)
	return model
end

-- A clip by id ("enemy/Kobold/Idle") under Shared.clips, or nil.
local function clipById(id: string): Types.ClipDef?
	local node: Instance? = Shared:FindFirstChild("clips")
	for segment in id:gmatch("[^/]+") do
		if node == nil then
			return nil
		end
		node = (node :: Instance):FindFirstChild(segment)
	end
	if node == nil or not (node :: Instance):IsA("ModuleScript") then
		return nil
	end
	local ok, clip = pcall(require, node :: ModuleScript)
	if not ok or typeof(clip) ~= "table" then
		return nil
	end
	return clip :: Types.ClipDef
end

-- The poses a built model stands in, every part's frame in its root's space: the rest pose, then
-- every pose of the rig's blocker clips (rigs.luau `blocker`) at its sampleSeconds, each clip's end
-- included. A clip that does not load is left out, with a warning.
local function standingPoses(model: Model, rig: Rigs.Rig): { { [string]: CFrame } }
	local poses = { Pose.solve(model, CFrame.identity, {}) }
	local blocker = rig.blocker
	if blocker == nil then
		return poses
	end
	local step = blocker.sampleSeconds
	for _, id in blocker.clips do
		local clip = clipById(id)
		if clip == nil or step <= 0 then
			warn(("RigBuilder: rig '%s' stands in clip '%s', which does not load"):format(rig.id, id))
			continue
		end
		local count = math.max(1, math.ceil(clip.duration / step - 1e-6))
		for k = 0, count do
			local time = math.min(k * step, clip.duration)
			table.insert(poses, Pose.solve(model, CFrame.identity, ClipSampler.sample(clip, time)))
		end
	end
	return poses
end

-- The flat box over `names` in every pose (root space), corners and all: centre and size, Y 0.
local function flatHull(model: Model, names: { string }, poses: { { [string]: CFrame } }): (Vector3, Vector3)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, partName in names do
		local part = model:FindFirstChild(partName)
		if part == nil or not part:IsA("BasePart") then
			continue
		end
		local half = (part :: BasePart).Size / 2
		for _, solved in poses do
			local frame: CFrame? = solved[partName]
			if frame == nil then
				continue
			end
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local corner = frame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						minX, maxX = math.min(minX, corner.X), math.max(maxX, corner.X)
						minZ, maxZ = math.min(minZ, corner.Z), math.max(maxZ, corner.Z)
					end
				end
			end
		end
	end
	return Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2), Vector3.new(maxX - minX, 0, maxZ - minZ)
end

-- A rig's blocker faces, measured once per rig (the geometry is the rig's, wherever and however a
-- model of it stands).
local measured: { [string]: { Footprint } } = {}

-- The faces of a built model's rig: the body (every rigs.luau part but its trailParts) first, then
-- one per part it holds that the model has, each over the poses it stands in. The root is one of
-- the body's parts, so the body's face always covers the root's own footprint.
local function footprintsOf(model: Model, rig: Rigs.Rig): { Footprint }
	local known = measured[rig.id]
	if known ~= nil then
		return known
	end
	local held: { string } = rig.trailParts or {}
	local body: { string } = {}
	for partName in rig.parts :: { [string]: any } do
		if table.find(held, partName) == nil then
			table.insert(body, partName)
		end
	end
	table.sort(body)
	local poses = standingPoses(model, rig)
	local centre, size = flatHull(model, body, poses)
	local faces: { Footprint } = { { name = BLOCKER_NAME, centre = centre, size = size, parts = body } }
	for _, partName in held do
		local part = model:FindFirstChild(partName)
		if part ~= nil and part:IsA("BasePart") then
			local heldCentre, heldSize = flatHull(model, { partName }, poses)
			table.insert(
				faces,
				{ name = HELD_BLOCKER_NAME, centre = heldCentre, size = heldSize, parts = { partName } }
			)
		end
	end
	measured[rig.id] = faces
	return faces
end

--- A rig's blocker faces in its root's space (addBlocker): the body's first (RigBuilder.footprint),
--- then one per part it holds, each the flat box over its parts at rest and in every pose of the
--- rig's blocker clips. Builds the rig to measure it the first time (specs, tools).
function RigBuilder.footprints(rigId: string): { Footprint }
	local model = RigBuilder.build(rigId)
	local faces = footprintsOf(model, RigBuilder.definition(rigId))
	model:Destroy()
	return faces
end

--- The footprint of a rig's body in its root's space (the body's blocker face, addBlocker): the
--- centre and size, Y 0, of the flat box over every part but its trailParts, at rest and in every
--- pose of its blocker clips.
function RigBuilder.footprint(rigId: string): (Vector3, Vector3)
	local body = RigBuilder.footprints(rigId)[1]
	return body.centre, body.size
end

--- Gives an enemy model its blocker (D-198) and returns the body's face, or nil when the model has
--- no root or no rig rigs.luau knows (the Rig attribute). One face over the body's footprint
--- (RigBuilder.footprint) and one over each part it holds (HELD_BLOCKER_NAME, D-315), along the
--- root's own axes, each from the floor the Humanoid holds the root's bottom HipHeight above, up to
--- ai.collision.blockerHeight; welded to the root and massless, so the body and its Humanoid move
--- as before. Invisible, casts no shadow and touches nothing; it collides with nothing until
--- CollisionGroups.assign puts the enemy in the enemies group, and with players only then.
function RigBuilder.addBlocker(model: Model): Part?
	local root = model.PrimaryPart
	local rigId = model:GetAttribute(RigBuilder.RIG_ATTRIBUTE)
	local rig = if typeof(rigId) == "string" then Rigs[rigId] else nil
	if root == nil or rig == nil or rig.parts == nil then
		return nil
	end
	local height = AI.collision.blockerHeight
	local floorBelowCenter = rig.hipHeight + root.Size.Y / 2
	local bodyFace: Part? = nil
	for _, footprint in footprintsOf(model, rig) do
		local centre, size = footprint.centre, footprint.size
		local blocker = Instance.new("Part")
		blocker.Name = footprint.name
		blocker.Size = Vector3.new(size.X, height, size.Z)
		blocker.CFrame = root.CFrame * CFrame.new(centre.X, height / 2 - floorBelowCenter, centre.Z)
		blocker.Transparency = 1
		blocker.CastShadow = false
		blocker.CanCollide = false
		blocker.CanQuery = false
		blocker.CanTouch = false
		blocker.Massless = true
		blocker.Anchored = false
		blocker.CollisionGroup = AI.collision.blockers
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = blocker
		weld.Parent = blocker
		blocker.Parent = model
		if bodyFace == nil then
			bodyFace = blocker
		end
	end
	return bodyFace
end

--- The body shell a character carries (item 236, BodyShell.boxes): one box per part of rigs.luau
--- PlayerR15.shell `parts` the model has, in its root's own space, over that part (corners and all)
--- in every pose of the stance's clips (`drawn` or `sheathed`), posed every sampleSeconds, each
--- clip's end included, and padded padStuds. Empty for a rig with no shell or a model without a root.
function RigBuilder.playerShell(model: Model, drawn: boolean): { BodyShell.Box }
	return BodyShell.boxes(model, drawn)
end

--- Number of parts and Motor6Ds a rig builds to (budgeting and tests).
function RigBuilder.counts(rigId: string): (number, number)
	local rig = RigBuilder.definition(rigId)
	local partCount = 0
	for _ in rig.parts :: { [string]: any } do
		partCount += 1
	end
	return partCount, #rig.joints
end

--- Every placeholder rig id rigs.luau defines, sorted.
function RigBuilder.placeholderRigIds(): { string }
	local ids = {}
	for id, rig in Rigs do
		if rig.parts ~= nil then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

return RigBuilder
