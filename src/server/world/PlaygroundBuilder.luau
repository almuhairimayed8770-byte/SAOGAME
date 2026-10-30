--!strict
--[[
	PlaygroundBuilder: the parts of the Playground that come from data at server start (sections 5,
	11, 16, 20; D-005, D-013). places/Playground.project.json holds the static disc, ceiling and
	lighting; this module adds, under workspace.Playground:

	- Railing: posts every playground.rim.postSpacing studs along the rim with rails between them
	  (world.railing.railCount: the top rail at the post height, one at half of it);
	- Pillars: the distant outer pillars, Slate cylinders from below the clouds to just under the
	  ceiling, each with a SurfaceLight on its top face lighting the ceiling underside (section 11);
	- Clouds: a ring of invisible hosts cloudRingDrop studs below the field carrying ParticleEmitters
	  (large, soft, white, drifting slowly along the ring); the emitter count comes from fx.luau's
	  High quality tier so a client of any tier can trim by the CloudIndex attribute;
	- KillVolume: an invisible slab whose top face is the kill plane (PlaygroundService does the
	  actual Heartbeat check; the part marks the plane and never traps anything);

	and, directly under workspace, the Enemies and Entities folders (EnemyService parents rigs into
	workspace.Enemies), and the sky's Clouds (section 11) under workspace.Terrain with
	lighting.luau's cover and density. The engine takes a Clouds only as a child of Terrain (one
	under Lighting logs "Cloud instance must exist under Terrain node" and draws nothing), and a
	place file cannot hold it there reliably, so the server makes it at start; it replicates. A
	Clouds an older place build left under Lighting is removed. Every part is anchored. The build
	is idempotent: calling it again rebuilds the folders it owns and leaves the place's own parts
	alone. workspace.Playground gets the attribute PartCount (every BasePart under it) and the
	builder warns past world.partBudget.

	Layout math lives in PlaygroundLayout (Lune-tested); this file only makes Instances.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Playground = require(Shared.data.playground)
local World = require(Shared.data.world)
local Fx = require(Shared.data.fx)
local Assets = require(Shared.data.assets)
local LightingData = require(Shared.data.lighting)
local PlaygroundLayout = require(script.Parent.PlaygroundLayout)

export type BuildResult = {
	model: Instance, -- workspace.Playground
	enemies: Instance, -- workspace.Enemies
	entities: Instance, -- workspace.Entities
	partCount: number,
	posts: number,
	rails: number,
	pillars: number,
	clouds: number,
	skyClouds: Instance?, -- workspace.Terrain's Clouds; nil when the container has no Terrain
}

local PlaygroundBuilder = {}

local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Slate = Enum.Material.Slate,
	Concrete = Enum.Material.Concrete,
	Marble = Enum.Material.Marble,
	Wood = Enum.Material.Wood,
	Metal = Enum.Material.Metal,
}

local CLOUD_INDEX_ATTRIBUTE = "CloudIndex"
local SKY_CLOUDS_CLASS = "Clouds"

local function color3(rgb: { number }): Color3
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

local function materialOf(name: string): Enum.Material
	return MATERIALS[name] or Enum.Material.SmoothPlastic
end

local function findOrCreate(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing ~= nil and existing:IsA(className) then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

-- A folder this builder owns: emptied on every build so a rebuild never doubles the parts.
local function ownedFolder(parent: Instance, name: string): Folder
	local folder = findOrCreate(parent, name, "Folder") :: Folder
	for _, child in folder:GetChildren() do
		child:Destroy()
	end
	return folder
end

local function staticPart(name: string, size: Vector3, cframe: CFrame, material: string, rgb: { number }): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Material = materialOf(material)
	part.Color = color3(rgb)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

--- The Playground model (workspace.Playground, or a Model of that name under `container`), created when missing.
function PlaygroundBuilder.playgroundModel(container: Instance): Instance
	return findOrCreate(container, World.playground.modelName, "Model")
end

--- Height of the ceiling underside: read from the place's Ceiling part (a cylinder whose axis is X,
--- so its thickness is Size.X) when it exists, else the data's ceiling height.
function PlaygroundBuilder.ceilingUnderside(playground: Instance): number
	local ceiling = playground:FindFirstChild("Ceiling")
	if ceiling ~= nil and ceiling:IsA("BasePart") then
		return ceiling.CFrame.Position.Y - ceiling.Size.X / 2
	end
	return Playground.ceilingHeight
end

--- How many cloud hosts to build: fx.luau's High tier when it knows, else playground.luau's count.
function PlaygroundBuilder.cloudCount(): number
	local tier = Fx.quality.High
	if tier ~= nil and typeof(tier.cloudBillboards) == "number" then
		return tier.cloudBillboards
	end
	return (Playground.rim :: any)[World.clouds.fallbackCountKey]
end

--- Builds the rim railing under `parent`; returns (posts, rails).
function PlaygroundBuilder.buildRailing(parent: Instance): (number, number)
	local rim = Playground.rim
	local railing = World.railing
	local folder = ownedFolder(parent, World.playground.folders.railing)
	local posts = PlaygroundLayout.posts(Playground.fieldRadius, rim.postSpacing, rim.postSize)
	local postSize = Vector3.new(rim.postSize[1], rim.postSize[2], rim.postSize[3])
	for index, post in posts do
		local part = staticPart(
			("Post%03d"):format(index),
			postSize,
			CFrame.new(post.x, post.y, post.z) * CFrame.Angles(0, -math.rad(post.angle), 0),
			railing.material,
			railing.postColor
		)
		part.Parent = folder
	end
	local heights = PlaygroundLayout.railHeights(rim.railingHeight, rim.railThickness, railing.railCount)
	local rails = PlaygroundLayout.rails(posts, heights, rim.postSize[1] * railing.railOverlap)
	for index, rail in rails do
		local center = Vector3.new(rail.x, rail.y, rail.z)
		local part = staticPart(
			("Rail%03d"):format(index),
			Vector3.new(rim.railThickness, rim.railThickness, rail.length),
			CFrame.lookAt(center, center + Vector3.new(rail.dirX, 0, rail.dirZ)),
			railing.material,
			railing.railColor
		)
		part.Parent = folder
	end
	return #posts, #rails
end

--- Builds the outer pillars with their ceiling lights under `parent`; returns the pillar count.
function PlaygroundBuilder.buildPillars(parent: Instance, ceilingUnderside: number): number
	local rim = Playground.rim
	local pillarData = World.pillars
	local folder = ownedFolder(parent, World.playground.folders.pillars)
	local centerY = PlaygroundLayout.pillarCenterY(ceilingUnderside, pillarData.ceilingGap, rim.pillarHeight)
	local pillars = PlaygroundLayout.pillars(rim.pillarCount, rim.pillarDistance, centerY)
	local diameter = rim.pillarRadius * 2
	for index, point in pillars do
		-- A cylinder's axis is X; rolling it 90 degrees about Z stands it up with +X as the top face.
		local part = staticPart(
			("Pillar%02d"):format(index),
			Vector3.new(rim.pillarHeight, diameter, diameter),
			CFrame.new(point.x, point.y, point.z) * CFrame.Angles(0, 0, math.rad(90)),
			pillarData.material,
			pillarData.color
		)
		part.Shape = Enum.PartType.Cylinder
		local light = Instance.new("SurfaceLight")
		light.Name = "CeilingLight"
		light.Face = Enum.NormalId.Right
		light.Range = rim.pillarLightRange
		light.Brightness = rim.pillarLightBrightness
		light.Angle = pillarData.light.angle
		light.Color = color3(pillarData.light.color)
		light.Shadows = pillarData.light.shadows
		light.Parent = part
		part.Parent = folder
	end
	return #pillars
end

--- Builds the cloud ring under `parent` with `count` emitters; returns the count built.
function PlaygroundBuilder.buildClouds(parent: Instance, count: number, random: Random?): number
	local rim = Playground.rim
	local cloudData = World.clouds
	local folder = ownedFolder(parent, World.playground.folders.clouds)
	local clouds = PlaygroundLayout.clouds(
		count,
		rim.cloudRingRadius,
		rim.cloudRingDrop,
		{ radial = cloudData.radialJitter, height = cloudData.heightJitter },
		random
	)
	local drift = rim.cloudDriftStudsPerSecond
	local meanLifetime = (cloudData.lifetime.min + cloudData.lifetime.max) / 2
	local hostSize = Vector3.new(cloudData.emitterPartSize, cloudData.emitterPartSize, cloudData.emitterPartSize)
	for index, cloud in clouds do
		local center = Vector3.new(cloud.x, cloud.y, cloud.z)
		local host = Instance.new("Part")
		host.Name = ("Cloud%02d"):format(index)
		host.Size = hostSize
		-- The host looks along the ring's tangent; the emitter pushes particles out of its Front face.
		host.CFrame = CFrame.lookAt(center, center + Vector3.new(cloud.dirX, 0, cloud.dirZ))
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.Transparency = 1
		host.CastShadow = false
		host:SetAttribute(CLOUD_INDEX_ATTRIBUTE, index)

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Billboard"
		emitter.Enabled = true
		emitter.Rate = cloudData.particlesPerEmitter / meanLifetime
		emitter.Lifetime = NumberRange.new(cloudData.lifetime.min, cloudData.lifetime.max)
		emitter.Speed = NumberRange.new(drift)
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.SpreadAngle = Vector2.new(cloudData.spreadDegrees, cloudData.spreadDegrees)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, rim.cloudSize * (1 - Fx.clouds.sizeJitter)),
			NumberSequenceKeypoint.new(1, rim.cloudSize * (1 + Fx.clouds.sizeJitter)),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, Fx.clouds.transparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Color = ColorSequence.new(color3(cloudData.color))
		emitter.LightEmission = cloudData.lightEmission
		emitter.LightInfluence = 1
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-cloudData.rotationDegreesPerSecond, cloudData.rotationDegreesPerSecond)
		emitter.Orientation = Enum.ParticleOrientation.FacingCamera
		emitter.LockedToPart = false
		emitter.Acceleration = Vector3.zero
		emitter.Drag = 0
		if Assets.isReady(cloudData.textureAsset) then
			emitter.Texture = Assets.url(cloudData.textureAsset)
		end
		emitter.Parent = host
		host.Parent = folder
	end
	return #clouds
end

--- Builds the sky's Clouds under `root`'s Terrain from lighting.luau (the engine takes a Clouds
--- only there) and removes any Clouds left under `lighting`; returns it, or nil with no Terrain.
function PlaygroundBuilder.buildSkyClouds(root: Instance, lighting: Instance?): Instance?
	if lighting ~= nil then
		for _, child in lighting:GetChildren() do
			if child:IsA(SKY_CLOUDS_CLASS) then
				child:Destroy()
			end
		end
	end
	local terrain = root:FindFirstChildOfClass("Terrain")
	if terrain == nil then
		return nil
	end
	local clouds = terrain:FindFirstChildOfClass(SKY_CLOUDS_CLASS) :: Clouds?
	if clouds == nil then
		local made = Instance.new(SKY_CLOUDS_CLASS) :: Clouds
		made.Parent = terrain
		clouds = made
	end
	local sky = clouds :: Clouds
	sky.Cover = LightingData.clouds.cover
	sky.Density = LightingData.clouds.density
	return sky
end

--- Builds the kill volume slab under `parent` (invisible, non-colliding; the plane PlaygroundService checks).
function PlaygroundBuilder.buildKillVolume(parent: Instance): BasePart
	local existing = parent:FindFirstChild(World.playground.killVolumeName)
	if existing ~= nil then
		existing:Destroy()
	end
	local box = PlaygroundLayout.killVolume(Playground.killVolume)
	local part = Instance.new("Part")
	part.Name = World.playground.killVolumeName
	part.Size = Vector3.new(box.size[1], box.size[2], box.size[3])
	part.CFrame = CFrame.new(box.x, box.y, box.z)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = World.killVolume.transparency
	part.CastShadow = false
	part:SetAttribute("KillY", Playground.killVolume.y)
	part.Parent = parent
	return part
end

--- Counts every BasePart under an Instance.
function PlaygroundBuilder.countParts(root: Instance): number
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

--- Builds everything under `container` (workspace when nil) and returns what it made.
function PlaygroundBuilder.build(container: Instance?, random: Random?): BuildResult
	local root: Instance = container or workspace
	local model = PlaygroundBuilder.playgroundModel(root)
	local posts, rails = PlaygroundBuilder.buildRailing(model)
	local pillars = PlaygroundBuilder.buildPillars(model, PlaygroundBuilder.ceilingUnderside(model))
	local clouds = PlaygroundBuilder.buildClouds(model, PlaygroundBuilder.cloudCount(), random)
	PlaygroundBuilder.buildKillVolume(model)
	local enemies = findOrCreate(root, World.playground.folders.enemies, "Folder")
	local entities = findOrCreate(root, World.playground.folders.entities, "Folder")
	-- Only the real workspace's Lighting is cleaned; a test container brings its own Terrain or none.
	local skyClouds =
		PlaygroundBuilder.buildSkyClouds(root, if container == nil then game:GetService("Lighting") else nil)

	local partCount = PlaygroundBuilder.countParts(model)
	model:SetAttribute(World.playground.partCountAttribute, partCount)
	model:SetAttribute("PartBudget", World.playground.partBudget)
	if partCount > World.playground.partBudget then
		warn(
			("[PlaygroundBuilder] %d parts in the Playground, over the %d budget"):format(
				partCount,
				World.playground.partBudget
			)
		)
	end
	return {
		model = model,
		enemies = enemies,
		entities = entities,
		partCount = partCount,
		posts = posts,
		rails = rails,
		pillars = pillars,
		clouds = clouds,
		skyClouds = skyClouds,
	}
end

return PlaygroundBuilder
