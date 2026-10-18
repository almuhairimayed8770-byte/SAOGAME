--!strict
--[[
	WeaponBuilder: placeholder weapons and the hand joint (ARCHITECTURE "Rigs, weapons and joints",
	sections 10 and 11, D-009).

	build(weaponDef) returns a Model named Weapon holding three parts from weaponModels.luau: the
	blade part (also named Weapon: the part Smear scales, Trails attaches to and HitSweep sweeps
	between its TrailStart and TrailEnd attachments), a guard and a grip welded to it. The blade
	carries a disabled Trail (lifetime, light emission and keypoints from fx.luau, the weapon's trail
	color from the palette) and a disabled PointLight (the Art activation light) so the client only
	ever flips Enabled; it never creates FX instances on a rig. The model is tagged Placeholder.

	equip(character, weaponDef) parents the model into the character and hangs it from the right
	hand on a Motor6D named Weapon: C0 is the rigs.luau PlayerR15 "Weapon" joint, C1 puts the grip's
	center at the hand so the blade points out of the fist. The character gets the WeaponId attribute
	and a WeaponGrip attachment on the hand. The blade's long axis is +Y with the tip at +Y.

	When the weapon's category has a weaponModels.luau `sheaths` row and the character has that
	row's part, equip also builds the sheath: a Model named Sheath next to the Weapon model, holding
	one Scabbard part welded to the body part by a Weld named ScabbardWeld at the row's back mount.
	The scabbard never collides, touches or answers a spatial query, and it carries no attachment.
	The server's Weapon motor never leaves the right hand: each client moves the sword to the back
	mount on its own, from the Drawn attribute, so hits and the hit matrix see the same rig as before.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local Rigs = require(Shared.data.rigs)
local Palette = require(Shared.data.palette)
local Fx = require(Shared.data.fx)
local Assets = require(Shared.data.assets)
local WeaponModels = require(Shared.data.weaponModels)
local RigBuilder = require(script.Parent.RigBuilder)

local WeaponBuilder = {}

local PART_SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

local function keypoints(keys: { { number } }): NumberSequence
	local points = {}
	for _, key in keys do
		table.insert(points, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	return NumberSequence.new(points)
end

local function makePart(name: string, size: Vector3, token: Palette.Token, shape: string?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Shape = PART_SHAPES[shape or "Block"] or Enum.PartType.Block
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Palette.color3(token)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function weld(blade: BasePart, other: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Name = other.Name .. "Weld"
	constraint.Part0 = blade
	constraint.Part1 = other
	constraint.Parent = other
end

local function addAttachment(part: BasePart, name: string, cframe: CFrame): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = cframe
	attachment.Parent = part
	return attachment
end

local function addTrail(blade: BasePart, start: Attachment, finish: Attachment, token: Palette.Token): Trail
	local trail = Instance.new("Trail")
	trail.Name = WeaponModels.trailName
	trail.Attachment0 = start
	trail.Attachment1 = finish
	trail.Enabled = false
	trail.Lifetime = Fx.trail.lifetime
	trail.LightEmission = Fx.trail.lightEmission
	trail.MinLength = Fx.trail.minLength
	trail.Color = ColorSequence.new(Palette.color3(token))
	trail.WidthScale = keypoints(Fx.trail.widthKeys)
	trail.Transparency = keypoints(Fx.trail.transparencyKeys)
	trail.FaceCamera = true
	if Assets.isReady(Fx.trail.textureAsset) then
		trail.Texture = Assets.url(Fx.trail.textureAsset)
	end
	trail.Parent = blade
	return trail
end

local function addLight(blade: BasePart, token: Palette.Token): PointLight
	local light = Instance.new("PointLight")
	light.Name = WeaponModels.lightName
	light.Enabled = false
	light.Range = Fx.activationLight.range
	light.Brightness = Fx.activationLight.brightness
	light.Color = Palette.color3(token)
	light.Parent = blade
	return light
end

--- The rigs.luau PlayerR15 joint the weapon hangs from (RightHand -> Weapon).
function WeaponBuilder.gripJoint(): Rigs.PlaceholderJoint
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name == WeaponModels.motorName then
			return joint
		end
	end
	error("WeaponBuilder: rigs.luau PlayerR15 has no Weapon joint")
end

--- C1 of the Weapon Motor6D: the hand's hold point relative to the blade's center (the grip's center, below the guard).
function WeaponBuilder.holdC1(category: Types.WeaponCategory): CFrame
	return CFrame.new(0, -WeaponModels.holdOffset(category), 0)
end

--- Builds the placeholder Model for a weapon def: blade (named Weapon), guard, grip, trail attachments, a
--- disabled Trail and a disabled activation PointLight, tagged Placeholder.
function WeaponBuilder.build(weaponDef: Types.WeaponDef): Model
	local geometry = WeaponModels.get(weaponDef.category)
	local colors = WeaponModels.colors
	local blade = geometry.blade
	local guard = geometry.guard
	local grip = geometry.grip
	local trailToken = weaponDef.trailColor :: Palette.Token

	local model = Instance.new("Model")
	model.Name = WeaponModels.modelName

	local bladePart = makePart(
		WeaponModels.bladePart,
		Vector3.new(blade.width, blade.length, blade.thickness),
		colors.blade :: Palette.Token,
		geometry.shape
	)
	bladePart.Parent = model
	model.PrimaryPart = bladePart

	-- The guard sits on the blade's -Y end, the grip below it; both ride the blade through welds.
	local guardPart = makePart(
		WeaponModels.guardPart,
		Vector3.new(guard.width, guard.height, guard.depth),
		colors.guard :: Palette.Token,
		nil
	)
	guardPart.CFrame = bladePart.CFrame * CFrame.new(0, -(blade.length / 2 + guard.height / 2), 0)
	guardPart.Parent = model
	weld(bladePart, guardPart)

	local gripPart = makePart(
		WeaponModels.gripPart,
		Vector3.new(grip.width, grip.length, grip.width),
		colors.grip :: Palette.Token,
		nil
	)
	gripPart.CFrame = bladePart.CFrame * CFrame.new(0, -(blade.length / 2 + guard.height + grip.length / 2), 0)
	gripPart.Parent = model
	weld(bladePart, gripPart)

	-- Trail ends: the guard end and the tip of the blade.
	local start = addAttachment(bladePart, WeaponModels.attachments.trailStart, CFrame.new(0, -blade.length / 2, 0))
	local finish = addAttachment(bladePart, WeaponModels.attachments.trailEnd, CFrame.new(0, blade.length / 2, 0))
	addTrail(bladePart, start, finish, trailToken)
	addLight(bladePart, trailToken)

	-- What the client FX read without a data lookup (fx.luau names the attributes).
	bladePart:SetAttribute(Fx.trail.widthAttribute, weaponDef.trailWidth)
	bladePart:SetAttribute(Fx.trail.colorAttribute, weaponDef.trailColor)
	model:SetAttribute(WeaponModels.attributes.weaponId, weaponDef.id)
	model:SetAttribute(WeaponModels.attributes.category, weaponDef.category)
	model:AddTag(WeaponModels.tag)
	return model
end

--- The weapon Model a character carries, or nil.
function WeaponBuilder.equipped(character: Model): Model?
	local existing = character:FindFirstChild(WeaponModels.modelName)
	if existing ~= nil and existing:IsA("Model") then
		return existing
	end
	return nil
end

--- The sheath Model a character carries (the scabbard on its back mount), or nil.
function WeaponBuilder.sheathOf(character: Model): Model?
	local existing = character:FindFirstChild(WeaponModels.sheathModelName)
	if existing ~= nil and existing:IsA("Model") then
		return existing
	end
	return nil
end

--- Removes a character's weapon model, its Motor6D and its sheath; clears the WeaponId attribute.
function WeaponBuilder.unequip(character: Model)
	local joint = WeaponBuilder.gripJoint()
	local hand = character:FindFirstChild(joint.part0)
	if hand ~= nil then
		local motor = hand:FindFirstChild(WeaponModels.motorName)
		if motor ~= nil and motor:IsA("Motor6D") then
			motor:Destroy()
		end
	end
	local existing = WeaponBuilder.equipped(character)
	if existing ~= nil then
		existing:Destroy()
	end
	for _, child in character:GetChildren() do
		if child.Name == WeaponModels.sheathModelName and child:IsA("Model") then
			child:Destroy()
		end
	end
	character:SetAttribute(WeaponModels.attributes.weaponId, nil)
end

--- The ScabbardWeld's C0 on the sheath part: the back mount, moved along the blade to the scabbard's center.
function WeaponBuilder.scabbardC0(category: Types.WeaponCategory): CFrame?
	local row = WeaponModels.sheath(category)
	if row == nil then
		return nil
	end
	local along = WeaponModels.holdOffset(category) + row.scabbard.clearance / 2
	return RigBuilder.frameOf(row.mount) * CFrame.new(0, along, 0)
end

-- The scabbard on the category's back mount, or nil when the category has no sheath row or the
-- character lacks the row's part (the Lune stand-ins have only a root and a hand).
local function buildSheath(character: Model, category: Types.WeaponCategory): Model?
	local row = WeaponModels.sheath(category)
	local c0 = WeaponBuilder.scabbardC0(category)
	if row == nil or c0 == nil then
		return nil
	end
	local body = character:FindFirstChild(row.part)
	if body == nil or not body:IsA("BasePart") then
		return nil
	end
	local blade = WeaponModels.get(category).blade
	local scabbard = row.scabbard
	local model = Instance.new("Model")
	model.Name = WeaponModels.sheathModelName
	local part = makePart(
		WeaponModels.scabbardPart,
		Vector3.new(
			blade.width + 2 * scabbard.wall,
			blade.length + scabbard.clearance,
			blade.thickness + 2 * scabbard.wall
		),
		scabbard.color :: Palette.Token,
		nil
	)
	-- Spatial queries skip it (D-042): no sweep or cast ever stops on the scabbard.
	part.CanQuery = false
	-- Start it where the weld holds it, so nothing flashes at the origin for a frame.
	part.CFrame = body.CFrame * c0
	part.Parent = model
	model.PrimaryPart = part
	local joint = Instance.new("Weld")
	joint.Name = WeaponModels.scabbardWeld
	joint.Part0 = body
	joint.Part1 = part
	joint.C0 = c0
	joint.C1 = CFrame.identity
	joint.Parent = part
	model:AddTag(WeaponModels.tag)
	model.Parent = character
	return model
end

--- Builds the weapon, parents it into the character and hangs it from the right hand on a Motor6D named
--- Weapon (C0 from rigs.luau, C1 at the grip); welds the category's scabbard to its back mount when the
--- category has one. Replaces any weapon and sheath already carried. Returns the weapon Model.
function WeaponBuilder.equip(character: Model, weaponDef: Types.WeaponDef): Model
	local joint = WeaponBuilder.gripJoint()
	local hand = character:FindFirstChild(joint.part0)
	if hand == nil or not hand:IsA("BasePart") then
		error(("WeaponBuilder: %s has no %s to hold a weapon"):format(character:GetFullName(), joint.part0))
	end
	WeaponBuilder.unequip(character)

	local model = WeaponBuilder.build(weaponDef)
	local bladePart = model.PrimaryPart :: BasePart
	local c0 = RigBuilder.frameOf(joint.c0)
	local c1 = WeaponBuilder.holdC1(weaponDef.category)

	-- Start the parts where the joint will hold them, so nothing flashes at the origin for a frame.
	local bladeCFrame = hand.CFrame * c0 * c1:Inverse()
	local offset = bladeCFrame * bladePart.CFrame:Inverse()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = offset * descendant.CFrame
		end
	end

	if hand:FindFirstChild(WeaponModels.attachments.grip) == nil then
		addAttachment(hand, WeaponModels.attachments.grip, c0)
	end

	model.Parent = character
	local motor = Instance.new("Motor6D")
	motor.Name = WeaponModels.motorName
	motor.Part0 = hand
	motor.Part1 = bladePart
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = bladePart

	buildSheath(character, weaponDef.category)

	character:SetAttribute(WeaponModels.attributes.weaponId, weaponDef.id)
	return model
end

return WeaponBuilder
