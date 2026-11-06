--!strict
-- PlaygroundBuilder under Lune's Instance: builds into a container Folder instead of workspace.
local PlaygroundBuilder = Harness.load("src/server/world/PlaygroundBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local Playground = Harness.load("src/shared/data/playground")
local World = Harness.load("src/shared/data/world")
local Fx = Harness.load("src/shared/data/fx")

local rim = Playground.rim

local function countClass(root: any, className: string): number
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA(className) then
			count += 1
		end
	end
	return count
end

-- The place's static Playground: a Model with the Field, the Ceiling (a cylinder on its side) and the Spawn.
local function placeContainer(): (any, any)
	local container = Instance.new("Folder")
	container.Name = "Workspace"
	local playground = Instance.new("Model")
	playground.Name = "Playground"
	playground.Parent = container
	local field = Instance.new("Part")
	field.Name = "Field"
	field.Shape = Enum.PartType.Cylinder
	field.Size = Vector3.new(4, 400, 400)
	field.CFrame = CFrame.new(0, -2, 0) * CFrame.Angles(0, 0, math.rad(90))
	field.Anchored = true
	field.Parent = playground
	local ceiling = Instance.new("Part")
	ceiling.Name = "Ceiling"
	ceiling.Shape = Enum.PartType.Cylinder
	ceiling.Size = Vector3.new(6, 900, 900)
	ceiling.CFrame = CFrame.new(0, Playground.ceilingHeight, 0) * CFrame.Angles(0, 0, math.rad(90))
	ceiling.Anchored = true
	ceiling.Parent = playground
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Parent = playground
	return container, playground
end

describe("PlaygroundBuilder.build", function()
	local container, playground = placeContainer()
	local result = PlaygroundBuilder.build(container, Random.new(5))

	it("builds the Railing, Pillars and Clouds folders and the KillVolume under the place's Playground", function()
		expect(result.model).toBe(playground)
		expect(playground:FindFirstChild("Railing")).toBeTruthy()
		expect(playground:FindFirstChild("Pillars")).toBeTruthy()
		expect(playground:FindFirstChild("Clouds")).toBeTruthy()
		expect(playground:FindFirstChild("KillVolume")).toBeTruthy()
		expect(playground:FindFirstChild("Field")).toBeTruthy() -- the place's own parts are untouched
		expect(playground:FindFirstChild("Ceiling")).toBeTruthy()
	end)

	it("puts the Enemies and Entities folders directly under the container (where EnemyService spawns)", function()
		expect(result.enemies.Parent).toBe(container)
		expect(result.entities.Parent).toBe(container)
		expect(result.enemies.Name).toBe("Enemies")
		expect(result.entities.Name).toBe("Entities")
		expect(result.enemies:IsA("Folder")).toBe(true)
	end)

	it("counts the railing from the layout: 125 posts and two rails per post, all anchored", function()
		local railing = playground:FindFirstChild("Railing")
		expect(result.posts).toBe(125)
		expect(result.rails).toBe(125 * World.railing.railCount)
		expect(countClass(railing, "BasePart")).toBe(result.posts + result.rails)
		for _, part in railing:GetChildren() do
			expect(part.Anchored).toBe(true)
			expect(part.Material).toBe(Enum.Material.SmoothPlastic)
		end
		local post = railing:FindFirstChild("Post001")
		expect(post).toBeTruthy()
		expect(PlaygroundLayout.distance(0, 0, post.CFrame.Position.X, post.CFrame.Position.Z)).toBeCloseTo(
			Playground.fieldRadius - rim.postSize[1] / 2,
			1e-2
		)
		local rail = railing:FindFirstChild("Rail001")
		expect(rail.Size.Z).toBeGreaterThan(rim.postSpacing * 0.9)
		expect(rail.Size.X).toBeCloseTo(rim.railThickness, 1e-4)
		expect(rail.CFrame.Position.Y).toBeCloseTo(rim.railingHeight - rim.railThickness / 2, 1e-3)
	end)

	it("stands the pillars at pillarDistance as Slate cylinders topped by a SurfaceLight under the ceiling", function()
		local pillars = playground:FindFirstChild("Pillars")
		expect(result.pillars).toBe(rim.pillarCount)
		expect(countClass(pillars, "BasePart")).toBe(rim.pillarCount)
		expect(countClass(pillars, "SurfaceLight")).toBe(rim.pillarCount)
		local underside = Playground.ceilingHeight - 3 -- the Ceiling part is 6 thick
		expect(PlaygroundBuilder.ceilingUnderside(playground)).toBeCloseTo(underside, 1e-3)
		for _, pillar in pillars:GetChildren() do
			expect(pillar.Shape).toBe(Enum.PartType.Cylinder)
			expect(pillar.Material).toBe(Enum.Material.Slate)
			expect(pillar.Anchored).toBe(true)
			expect(pillar.Size.X).toBeCloseTo(rim.pillarHeight, 1e-3)
			expect(pillar.Size.Y).toBeCloseTo(rim.pillarRadius * 2, 1e-3)
			local position = pillar.CFrame.Position
			expect(PlaygroundLayout.distance(0, 0, position.X, position.Z)).toBeCloseTo(rim.pillarDistance, 1e-2)
			-- Rolled upright: the part's +X points up, so the Right face is the top.
			expect(pillar.CFrame.RightVector.Y).toBeCloseTo(1, 1e-5)
			local top = position.Y + rim.pillarHeight / 2
			expect(top).toBeCloseTo(underside - World.pillars.ceilingGap, 1e-2)
			expect(position.Y - rim.pillarHeight / 2).toBeLessThan(-rim.cloudRingDrop)
			local light = pillar:FindFirstChildOfClass("SurfaceLight")
			expect(light.Face).toBe(Enum.NormalId.Right)
			expect(light.Range).toBeCloseTo(rim.pillarLightRange, 1e-5)
			expect(light.Brightness).toBeCloseTo(rim.pillarLightBrightness, 1e-5)
			expect(light.Angle).toBeCloseTo(World.pillars.light.angle, 1e-5)
		end
	end)

	it("hangs the cloud ring cloudRingDrop below the field: invisible hosts with slow, large, soft emitters", function()
		local clouds = playground:FindFirstChild("Clouds")
		expect(result.clouds).toBe(Fx.quality.High.cloudBillboards)
		expect(PlaygroundBuilder.cloudCount()).toBe(Fx.quality.High.cloudBillboards)
		expect(countClass(clouds, "ParticleEmitter")).toBe(result.clouds)
		for index, host in clouds:GetChildren() do
			expect(host.Transparency).toBe(1)
			expect(host.CanCollide).toBe(false)
			expect(host.Anchored).toBe(true)
			expect(host:GetAttribute("CloudIndex")).toBeTruthy()
			local position = host.CFrame.Position
			expect(math.abs(position.Y + rim.cloudRingDrop)).toBeLessThanOrEqual(World.clouds.heightJitter + 1e-3)
			local radial = PlaygroundLayout.distance(0, 0, position.X, position.Z)
			expect(radial).toBeGreaterThan(Playground.fieldRadius)
			expect(math.abs(radial - rim.cloudRingRadius)).toBeLessThanOrEqual(World.clouds.radialJitter + 1e-2)
			local emitter = host:FindFirstChildOfClass("ParticleEmitter")
			expect(emitter.Enabled).toBe(true)
			expect(emitter.Speed.Min).toBeCloseTo(rim.cloudDriftStudsPerSecond, 1e-5)
			expect(emitter.Lifetime.Min).toBeCloseTo(World.clouds.lifetime.min, 1e-5)
			expect(emitter.Lifetime.Max).toBeCloseTo(World.clouds.lifetime.max, 1e-5)
			expect(emitter.Rate * emitter.Lifetime.Max).toBeLessThan(World.clouds.particlesPerEmitter * 1.5)
			expect(emitter.Size.Keypoints[1].Value).toBeGreaterThan(rim.cloudSize * 0.5)
			expect(index).toBeGreaterThan(0)
		end
	end)

	it("the kill volume is an invisible, non-colliding slab whose top is the kill plane", function()
		local volume = playground:FindFirstChild("KillVolume")
		expect(volume.Anchored).toBe(true)
		expect(volume.CanCollide).toBe(false)
		expect(volume.Transparency).toBe(1)
		expect(volume.CFrame.Position.Y + volume.Size.Y / 2).toBeCloseTo(Playground.killVolume.y, 1e-3)
		expect(volume.Size.X).toBeCloseTo(Playground.killVolume.halfExtent * 2, 1e-2)
		expect(volume:GetAttribute("KillY")).toBe(Playground.killVolume.y)
	end)

	it("writes PartCount under the budget, counting the place's own parts too", function()
		local count = result.partCount
		expect(playground:GetAttribute("PartCount")).toBe(count)
		expect(playground:GetAttribute("PartBudget")).toBe(World.playground.partBudget)
		expect(count).toBe(result.posts + result.rails + result.pillars + result.clouds + 1 + 3)
		expect(count).toBeLessThan(World.playground.partBudget)
		expect(PlaygroundBuilder.countParts(playground)).toBe(count)
	end)

	it("building again rebuilds its own folders without doubling anything", function()
		local again = PlaygroundBuilder.build(container, Random.new(5))
		expect(again.model).toBe(playground)
		expect(again.partCount).toBe(result.partCount)
		expect(playground:GetAttribute("PartCount")).toBe(result.partCount)
		expect(#container:GetChildren()).toBe(3) -- Playground, Enemies, Entities
	end)
end)

describe("PlaygroundBuilder without the place", function()
	it("creates the Playground model and falls back to the data's ceiling height", function()
		local container = Instance.new("Folder")
		local result = PlaygroundBuilder.build(container)
		expect(result.model.Name).toBe("Playground")
		expect(result.model.Parent).toBe(container)
		expect(PlaygroundBuilder.ceilingUnderside(result.model)).toBe(Playground.ceilingHeight)
		local pillar = result.model:FindFirstChild("Pillars"):FindFirstChild("Pillar01")
		expect(pillar.CFrame.Position.Y + rim.pillarHeight / 2).toBeCloseTo(
			Playground.ceilingHeight - World.pillars.ceilingGap,
			1e-2
		)
		expect(result.partCount).toBe(result.posts + result.rails + result.pillars + result.clouds + 1)
	end)
end)
