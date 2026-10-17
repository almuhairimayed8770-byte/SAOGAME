--!strict
local World = Harness.load("src/shared/data/world")
local Playground = Harness.load("src/shared/data/playground")
local Fx = Harness.load("src/shared/data/fx")

describe("world data", function()
	it("keeps the Playground part budget inside the scene budget", function()
		expect(World.playground.partBudget).toBe(2000)
		expect(World.playground.partBudget).toBeLessThanOrEqual(Fx.budgets.parts)
	end)

	it("names the folders the services agree on", function()
		expect(World.playground.modelName).toBe("Playground")
		expect(World.playground.folders.enemies).toBe("Enemies")
		expect(World.playground.folders.entities).toBe("Entities")
		expect(World.playground.folders.railing).toBe("Railing")
		expect(World.playground.folders.pillars).toBe("Pillars")
		expect(World.playground.folders.clouds).toBe("Clouds")
		expect(World.playground.partCountAttribute).toBe("PartCount")
	end)

	it("keeps the cloud ring well inside the particle budget", function()
		local live = Fx.quality.High.cloudBillboards * World.clouds.particlesPerEmitter
		expect(live * 2).toBeLessThanOrEqual(Fx.budgets.particles)
		expect(World.clouds.lifetime.max).toBeGreaterThanOrEqual(World.clouds.lifetime.min)
		expect(Playground.rim[World.clouds.fallbackCountKey]).toBe(Playground.rim.cloudCount)
	end)

	it("lists the engine's Humanoid scale values", function()
		local values = World.character.scaleValues
		expect(values.bodyHeight).toBe("BodyHeightScale")
		expect(values.bodyWidth).toBe("BodyWidthScale")
		expect(values.bodyDepth).toBe("BodyDepthScale")
		expect(values.head).toBe("HeadScale")
	end)

	it("anti-cheat policy strings and weights agree with combat.luau's section 17 block", function()
		local Combat = Harness.load("src/shared/data/combat")
		local Palette = Harness.load("src/shared/data/palette")
		local policy = World.anticheat
		expect(policy.shadowAttribute).toBe("Shadowed")
		expect(Palette.tokens[policy.lineToken]).toBeTruthy()
		expect(#policy.kickText).toBeLessThanOrEqual(200) -- the SystemLine schema's text limit
		expect(policy.minimumAnomalies).toBeGreaterThanOrEqual(2)
		expect(policy.speedWeight * policy.minimumAnomalies).toBeLessThan(Combat.anomalyKickThreshold)
		expect(Combat.anticheatSampleInterval).toBe(0.25)
		expect(Combat.anticheatSampleInterval).toBeLessThan(Combat.anomalyWindow)
	end)

	it("colors are {r, g, b} in 0..1", function()
		for _, color in
			{ World.railing.postColor, World.railing.railColor, World.pillars.color, World.pillars.light.color }
		do
			expect(#color).toBe(3)
			for _, channel in color do
				expect(channel).toBeGreaterThanOrEqual(0)
				expect(channel).toBeLessThanOrEqual(1)
			end
		end
	end)
end)
