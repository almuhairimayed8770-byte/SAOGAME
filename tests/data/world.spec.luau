--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local World = Harness.load("src/shared/data/world")
local Playground = Harness.load("src/shared/data/playground")
local Fx = Harness.load("src/shared/data/fx")

-- tools/validators/world.luau reads every table through ctx.load and requires nothing, so it
-- loads as a plain chunk; `overrides` swaps whole data tables (deep copies the test mutates).
local function runValidator(overrides: { [string]: any }?): { string }
	local path = "tools/validators/world.luau"
	local chunk = luau.load(
		fs.readFile(Harness.repoRoot() .. "/" .. path),
		{ debugName = path, environment = Harness.environment() :: any }
	)
	local validate = chunk()
	return validate({
		load = function(modulePath: string): any
			if overrides ~= nil and overrides[modulePath] ~= nil then
				return overrides[modulePath]
			end
			return Harness.load(modulePath)
		end,
		listFiles = Harness.listFiles,
		readFile = Harness.readFile,
		repoRoot = Harness.repoRoot(),
	})
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

local function mentions(problems: { string }, needle: string): boolean
	for _, problem in problems do
		if problem:find(needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

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

	it("anti-cheat fractions shadow before the kick and keep a single teleport under it", function()
		local Combat = Harness.load("src/shared/data/combat")
		local policy = World.anticheat
		expect(policy.shadowFraction).toBeGreaterThan(0)
		expect(policy.shadowFraction).toBeLessThan(1)
		expect(policy.teleportWeightCapFraction).toBeGreaterThanOrEqual(0)
		expect(policy.teleportWeightCapFraction).toBeLessThanOrEqual(1)
		local heaviest = math.floor(Combat.anomalyKickThreshold * policy.teleportWeightCapFraction)
		expect(heaviest).toBeLessThan(Combat.anomalyKickThreshold)
	end)

	it("rate-limits exactly the client-to-server remotes", function()
		local Remotes = Harness.load("src/shared/net/Remotes")
		local rates = World.anticheat.remoteRates
		for name, definition in Remotes do
			if definition.direction == "ClientToServer" then
				expect(rates[name]).toBeTruthy()
			end
		end
		for name, rate in rates do
			expect(Remotes[name]).toBeTruthy()
			expect(Remotes[name].direction).toBe("ClientToServer")
			expect(rate.perSecond).toBeGreaterThan(0)
			expect(rate.burst).toBeGreaterThanOrEqual(1)
			expect(rate.burst).toBe(math.floor(rate.burst))
		end
	end)

	it("holds the section 16 performance targets and the load they are measured under", function()
		local performance = World.performance
		expect(performance.maxServerHeartbeatMs).toBe(12)
		expect(performance.maxMemoryMbPc).toBe(1200)
		expect(performance.maxMemoryMbMobile).toBe(600)
		expect(performance.testPlayers).toBe(8)
		expect(performance.testEnemies).toBe(60)
		expect(performance.heartbeatPercentile).toBeGreaterThan(0.5)
		expect(performance.heartbeatPercentile).toBeLessThanOrEqual(1)
		expect(performance.sampleSeconds).toBeGreaterThan(0)
		expect(performance.settleSeconds).toBeGreaterThanOrEqual(0)
		-- Parts and draw calls are the section 11 scene budgets; the perf smoke reads them from fx.luau.
		expect(Fx.budgets.parts).toBe(60000)
		expect(Fx.budgets.drawCalls).toBe(1500)
		expect(performance.maxParts).toBeNil()
		expect(performance.maxDrawCalls).toBeNil()
	end)

	it("the world validator accepts the real table", function()
		expect(#runValidator()).toBe(0)
	end)

	it("the world validator flags broken performance targets", function()
		-- True when the validator, run on a copy of world.luau whose performance block `mutate`
		-- changed, reports a problem naming `field`.
		local function flagged(field: string, mutate: (performance: any) -> ()): boolean
			local world = deepCopy(World)
			mutate(world.performance)
			return mentions(runValidator({ ["src/shared/data/world"] = world }), field)
		end
		-- A heartbeat target past one 60 Hz server step.
		expect(flagged("maxServerHeartbeatMs", function(performance)
			performance.maxServerHeartbeatMs = 20
		end)).toBe(true)
		-- Mobile memory not under PC memory.
		expect(flagged("maxMemoryMbMobile", function(performance)
			performance.maxMemoryMbMobile = performance.maxMemoryMbPc
		end)).toBe(true)
		-- More stand-ins than a server holds.
		expect(flagged("testPlayers", function(performance)
			performance.testPlayers = 9
		end)).toBe(true)
		-- A stand-in without an enemy.
		expect(flagged("testEnemies", function(performance)
			performance.testEnemies = performance.testPlayers - 1
		end)).toBe(true)
		-- A sample of no length.
		expect(flagged("sampleSeconds", function(performance)
			performance.sampleSeconds = 0
		end)).toBe(true)
		-- A second copy of the part budget (it lives in fx.budgets only).
		expect(flagged("maxParts", function(performance)
			performance.maxParts = 60000
		end)).toBe(true)
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
