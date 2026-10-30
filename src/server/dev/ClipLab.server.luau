--!strict
--[[
	Dev server script (Playground and ClipLab places only). Returns at once unless the workspace
	carries one of the dev attributes from data/dev.luau.

	With `DevCapture`: creates the DevTimeScale RemoteEvent and mirrors a client's slow-motion
	choice onto the workspace attribute of the same name, so server systems that run in dev
	places can honour it (they read the attribute; nothing here touches them).

	With `ClipLab`: builds the review stage from data: a pedestal per rig, a key, a fill and a rim
	light on the camera's side and behind the rigs, the backdrop's color, the lighting preset from
	lighting.luau with the lab's brighter ambient over it (dev.luau clipLab.lighting: a dark outfit
	has to read), one Boar and one Kobold rig (through RigBuilder when it
	is in the build, otherwise a part-built fallback from rigs.luau), and puts every joining
	player's own character on the PlayerR15 pedestal with the starter weapon in its right hand.
	The enemy rigs pose through Motor6Ds; the player's character through AnimationConstraints
	under the Avatar Joint Upgrade (Motor6Ds in older places). Choreo drives either kind
	(shared/choreo/Joints.luau), and nothing here writes a joint the engine built.
	Nothing here is gameplay: no entities, no HP, no services.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingService = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dev = require(Shared.data.dev)

local isClipLab = workspace:GetAttribute(Dev.attributes.clipLab) == true
local isCapture = workspace:GetAttribute(Dev.attributes.capture) == true
if not (isClipLab or isCapture) then
	return
end

local Palette = require(Shared.data.palette)
local Rigs = require(Shared.data.rigs)
local LightingData = require(Shared.data.lighting)
local Weapons = require(Shared.data.weapons)
local Playground = require(Shared.data.playground)
local Joints = require(Shared.choreo.Joints)

local Lab = Dev.clipLab

-- ---------------------------------------------------------------------------------------------
-- Slow-motion remote (dev places only)
-- ---------------------------------------------------------------------------------------------

local remote = Instance.new("RemoteEvent")
remote.Name = Dev.timeScale.remoteName
remote.Parent = ReplicatedStorage

local lastRequest: { [Player]: number } = {}
remote.OnServerEvent:Connect(function(player: Player, scale: unknown)
	if typeof(scale) ~= "number" then
		return
	end
	local now = os.clock()
	local last = lastRequest[player]
	if last ~= nil and now - last < 1 / Dev.timeScale.remotePerSecond then
		return
	end
	lastRequest[player] = now
	if table.find(Dev.timeScale.steps, scale) == nil then
		return
	end
	workspace:SetAttribute(Dev.attributes.timeScale, scale)
end)
Players.PlayerRemoving:Connect(function(player: Player)
	lastRequest[player] = nil
end)

if not isClipLab then
	return
end

-- ---------------------------------------------------------------------------------------------
-- Stage
-- ---------------------------------------------------------------------------------------------

local function vec(list: { number }): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

local function color(token: string): Color3
	return Palette.color3(token :: any)
end

local stage = Instance.new("Folder")
stage.Name = Lab.stageFolderName

local function anchoredPart(name: string, size: Vector3, cframe: CFrame, token: string, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color(token)
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = transparency
	part.Parent = stage
	return part
end

local function pointLight(name: string, def: { position: { number }, range: number, brightness: number, color: string })
	local holder = anchoredPart(name, Vector3.one, CFrame.new(vec(def.position)), def.color, 1)
	holder.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = def.range
	light.Brightness = def.brightness
	light.Color = color(def.color)
	light.Shadows = true
	light.Parent = holder
end

-- Pedestal tops sit at the rig's listed y; the rig stands on them.
local pedestalTops: { [string]: Vector3 } = {}
for _, entry in Lab.rigs do
	local size = vec(Lab.pedestal.size)
	local position = vec(entry.position)
	local center = position - Vector3.new(0, size.Y / 2, 0)
	anchoredPart("Pedestal_" .. entry.rig, size, CFrame.new(center), Lab.pedestal.color, Lab.pedestal.transparency)
	pedestalTops[entry.rig] = position
end

pointLight("KeyLight", Lab.keyLight)
pointLight("FillLight", Lab.fillLight)
pointLight("RimLight", Lab.rimLight)
stage.Parent = workspace

-- The place's backdrop wall (places/ClipLab.project.json) takes its color from the data.
local placeModel = workspace:FindFirstChild("ClipLab")
local backdrop = if placeModel ~= nil then placeModel:FindFirstChild(Lab.backdrop.part) else nil
if backdrop ~= nil and backdrop:IsA("BasePart") then
	backdrop.Color = color(Lab.backdrop.color)
end

-- Lighting from lighting.luau (Technology is set in the place file; the rest is data).
local function applyLighting()
	local preset = LightingData.preset(Lab.lightingPreset)
	local base = LightingData.base
	LightingService.Brightness = base.brightness
	LightingService.ShadowSoftness = base.shadowSoftness
	LightingService.EnvironmentDiffuseScale = base.environmentDiffuseScale
	LightingService.EnvironmentSpecularScale = base.environmentSpecularScale
	LightingService.ClockTime = base.dayClockTime
	LightingService.GeographicLatitude = base.geographicLatitude
	LightingService.GlobalShadows = base.globalShadows
	LightingService.Ambient = Color3.new(preset.ambient[1], preset.ambient[2], preset.ambient[3])
	LightingService.OutdoorAmbient =
		Color3.new(preset.outdoorAmbient[1], preset.outdoorAmbient[2], preset.outdoorAmbient[3])
	local correction = LightingService:FindFirstChildOfClass("ColorCorrectionEffect")
	if correction then
		correction.Saturation = LightingData.colorCorrection.saturation
		correction.Contrast = LightingData.colorCorrection.contrast
		correction.TintColor = Color3.new(preset.tint[1], preset.tint[2], preset.tint[3])
	end
	local bloom = LightingService:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = LightingData.bloom.intensity
		bloom.Size = LightingData.bloom.size
		bloom.Threshold = LightingData.bloom.threshold
	end
	local atmosphere = LightingService:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = LightingData.atmosphere.density
		atmosphere.Haze = LightingData.atmosphere.haze
		atmosphere.Glare = LightingData.atmosphere.glare
		atmosphere.Color = Color3.new(preset.atmosphere[1], preset.atmosphere[2], preset.atmosphere[3])
		atmosphere.Decay = Color3.new(preset.decay[1], preset.decay[2], preset.decay[3])
	end
	-- The lab's own light over the preset: a review stage, not a floor of the game.
	local lab = Lab.lighting
	LightingService.Ambient = Color3.new(lab.ambient[1], lab.ambient[2], lab.ambient[3])
	LightingService.OutdoorAmbient = Color3.new(lab.outdoorAmbient[1], lab.outdoorAmbient[2], lab.outdoorAmbient[3])
	LightingService.EnvironmentDiffuseScale = lab.environmentDiffuseScale
	LightingService.ExposureCompensation = lab.exposureCompensation
end
applyLighting()

-- ---------------------------------------------------------------------------------------------
-- Rigs
-- ---------------------------------------------------------------------------------------------

local function cframeOf(offset: { pos: { number }, rot: { number } }): CFrame
	local pos = offset.pos
	local rot = offset.rot
	return CFrame.new(pos[1], pos[2], pos[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
end

-- Loads an optional server module (world/RigBuilder, world/WeaponBuilder) without crashing when
-- the package has not landed in this build.
local function optionalServerModule(folderName: string, moduleName: string): any
	local server = ServerScriptService:FindFirstChild("Server")
	local folder = if server then server:FindFirstChild(folderName) else nil
	local module = if folder then folder:FindFirstChild(moduleName) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(("[ClipLab] %s.%s failed to load: %s"):format(folderName, moduleName, tostring(result)))
		return nil
	end
	return result
end

-- Fallback rig: one Part per rigs.luau part and one Motor6D per joint, rest pose from the data.
local function buildFallbackRig(rigId: string): Model
	local rig = Rigs[rigId]
	assert(rig ~= nil and rig.parts ~= nil, ("[ClipLab] rig %s has no part table"):format(rigId))
	local model = Instance.new("Model")
	model.Name = rigId
	local parts: { [string]: Part } = {}
	for partName, def in rig.parts :: any do
		local part = Instance.new("Part")
		part.Name = partName
		part.Size = vec(def.size)
		part.Color = color(def.color)
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CanCollide = false
		part.Massless = partName ~= rig.rootPart
		if def.shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif def.shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		end
		part.Parent = model
		parts[partName] = part
	end
	local root = parts[rig.rootPart]
	assert(root ~= nil, ("[ClipLab] rig %s has no root part"):format(rigId))
	root.Transparency = 1
	model.PrimaryPart = root
	for _, joint in rig.joints do
		local part0 = parts[joint.part0]
		local part1 = parts[joint.part1]
		if part0 == nil or part1 == nil then
			continue
		end
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = cframeOf(joint.c0)
		motor.C1 = if joint.c1 then cframeOf(joint.c1) else CFrame.identity
		motor.Parent = part0
		-- Place the child so the joint solver starts from the rest pose.
		part1.CFrame = part0.CFrame * motor.C0 * motor.C1:Inverse()
	end
	model:SetAttribute("Placeholder", true)
	return model
end

local function buildEnemyRig(rigId: string): Model
	local RigBuilder = optionalServerModule("world", "RigBuilder")
	if RigBuilder ~= nil and typeof(RigBuilder.build) == "function" then
		local ok, model = pcall(RigBuilder.build, rigId, rigId)
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			return model
		end
		warn(("[ClipLab] RigBuilder.build(%s) failed: %s"):format(rigId, tostring(model)))
	end
	return buildFallbackRig(rigId)
end

local function placeOnPedestal(model: Model, rigId: string)
	local top = pedestalTops[rigId]
	local rig = Rigs[rigId]
	if top == nil or rig == nil then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChild(rig.rootPart)
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local height = top.Y + rig.hipHeight + root.Size.Y / 2
	model:PivotTo(CFrame.new(top.X, height, top.Z))
	root.Anchored = true
end

for _, entry in Lab.rigs do
	if entry.rig == "PlayerR15" then
		continue
	end
	local ok, result = pcall(buildEnemyRig, entry.rig)
	if not ok then
		warn(("[ClipLab] could not build rig %s: %s"):format(entry.rig, tostring(result)))
		continue
	end
	local model = result :: Model
	model.Name = entry.rig
	model:SetAttribute(Lab.rigAttribute, entry.rig)
	model:SetAttribute("DisplayName", entry.rig)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
	end
	model.Parent = stage
	placeOnPedestal(model, entry.rig)
end

-- ---------------------------------------------------------------------------------------------
-- The player's own character on the PlayerR15 pedestal, starter weapon in hand
-- ---------------------------------------------------------------------------------------------

local function buildFallbackWeapon(): Model
	local def = Lab.fallbackWeapon
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local blade = Instance.new("Part")
	blade.Name = "Weapon"
	blade.Size = vec(def.size)
	blade.Color = color(def.color)
	blade.Material = Enum.Material.SmoothPlastic
	blade.CanCollide = false
	blade.Massless = true
	blade.Parent = model
	local start = Instance.new("Attachment")
	start.Name = "TrailStart"
	start.Position = Vector3.new(0, -blade.Size.Y / 2 + def.gripOffset[2] * -1 / 2, 0)
	start.Parent = blade
	local finish = Instance.new("Attachment")
	finish.Name = "TrailEnd"
	finish.Position = Vector3.new(0, blade.Size.Y / 2, 0)
	finish.Parent = blade
	model.PrimaryPart = blade
	model:SetAttribute("Placeholder", true)
	return model
end

local function weaponJoint(): { pos: { number }, rot: { number } }?
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name == "Weapon" then
			return joint.c0
		end
	end
	return nil
end

-- The game's own equip (WeaponBuilder.equip: C0 from rigs.luau, C1 at the grip, the WeaponGrip
-- attachment, the WeaponId attribute) so the ClipLab shows the blade exactly where the Playground
-- holds it. Returns false when WeaponBuilder is not in the build or refused.
local function equipThroughBuilder(character: Model): boolean
	local weaponId = Playground.loadout.weapon
	local def = Weapons.rows[weaponId]
	local WeaponBuilder = optionalServerModule("world", "WeaponBuilder")
	if def == nil or WeaponBuilder == nil or typeof(WeaponBuilder.equip) ~= "function" then
		return false
	end
	local ok, result = pcall(WeaponBuilder.equip, character, def)
	if ok and typeof(result) == "Instance" and result:IsA("Model") then
		return true
	end
	warn(("[ClipLab] WeaponBuilder.equip(%s) failed: %s"):format(weaponId, tostring(result)))
	return false
end

local function attachWeapon(character: Model)
	local hand = character:FindFirstChild(Rigs.PlayerR15.weaponGrip or "RightHand")
	if hand == nil or not hand:IsA("BasePart") then
		return
	end
	if character:FindFirstChild("Weapon") then
		return
	end
	if equipThroughBuilder(character) then
		return
	end
	-- Fallback (WeaponBuilder absent): a blade-shaped part on the rigs.luau Weapon joint.
	local weapon = buildFallbackWeapon()
	local blade = weapon:FindFirstChild("Weapon")
	if blade == nil or not blade:IsA("BasePart") then
		warn("[ClipLab] weapon model has no part named Weapon")
		return
	end
	weapon.Parent = character
	local motor = Instance.new("Motor6D")
	motor.Name = "Weapon"
	motor.Part0 = hand
	motor.Part1 = blade
	local c0 = weaponJoint()
	motor.C0 = if c0 then cframeOf(c0) else CFrame.identity
	motor.Parent = hand
	character:SetAttribute("WeaponId", Playground.loadout.weapon)
end

local function applyPlayerScale(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local scale = Rigs.PlayerR15.scale
	if humanoid == nil or scale == nil then
		return
	end
	local values = {
		BodyHeightScale = scale.bodyHeight,
		BodyWidthScale = scale.bodyWidth,
		BodyDepthScale = scale.bodyDepth,
		HeadScale = scale.head,
	}
	for name, value in values do
		local holder = humanoid:FindFirstChild(name)
		if holder and holder:IsA("NumberValue") then
			holder.Value = value
		end
	end
end

local function stageCharacter(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", Lab.stageWaitSeconds)
	if root == nil or not root:IsA("BasePart") then
		return
	end
	-- CharacterAdded fires before the engine parents and dresses the character; scaling or arming
	-- it before that is undone (D-046).
	local CharacterReady = optionalServerModule("world", "CharacterReady")
	if CharacterReady ~= nil and not CharacterReady.wait(player, character, Lab.stageWaitSeconds) then
		return
	end
	character.PrimaryPart = root
	character:SetAttribute(Lab.rigAttribute, "PlayerR15")
	applyPlayerScale(character)
	attachWeapon(character)
	placeOnPedestal(character, "PlayerR15")
	-- Every PlayerR15 joint by name, of either kind: the engine's 15 and the Weapon one above.
	local missing: { string } = {}
	local byName = Joints.byName(character)
	for _, joint in Rigs.PlayerR15.joints do
		if byName[joint.name] == nil then
			table.insert(missing, joint.name)
		end
	end
	if #missing > 0 then
		warn(
			("[ClipLab] %s has no Motor6D or AnimationConstraint named %s; Choreo cannot pose those joints"):format(
				character.Name,
				table.concat(missing, ", ")
			)
		)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		task.defer(stageCharacter, player, character)
	end)
	if player.Character then
		task.defer(stageCharacter, player, player.Character :: Model)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
