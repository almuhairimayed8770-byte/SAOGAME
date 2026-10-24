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
