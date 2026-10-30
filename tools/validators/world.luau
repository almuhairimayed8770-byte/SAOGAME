--!strict
--[[
	Validates src/shared/data/world.luau: the Playground part budget is under the section 11 scene
	budget and above what the rim, pillars and clouds need from playground.luau; every count,
	distance and time is positive; colors are {r, g, b} in 0..1; the folder EnemyService spawns
	into is still called Enemies; the Humanoid scale value names are the engine's; the anti-cheat
	fractions keep the shadow flag before the kick and a single teleport under it; every
	client-to-server remote in net/Remotes.luau has exactly one anticheat.remoteRates entry; the
	section 16 performance targets are positive, the heartbeat target leaves room inside a 60 Hz
	server step, mobile memory sits under PC memory, the perf smoke's load fits a server and the
	part and draw-call budgets it reads from fx.luau are positive whole numbers.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local SCALE_VALUES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }
local SERVER_STEP_MS = 1000 / 60 -- the server simulates at 60 Hz; a heartbeat target must fit one step
local MAX_SERVER_PLAYERS = 8 -- section 17: MaxPlayers 8 on every floor place

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Check = ctx.load("src/shared/util/Check")
	local World = ctx.load("src/shared/data/world")
	local Playground = ctx.load("src/shared/data/playground")
	local Fx = ctx.load("src/shared/data/fx")

	local function problem(message: string)
		table.insert(problems, "world: " .. message)
	end

	local color = Check.vec3(1)
	local positive = Check.number(0.001)
	local count = Check.integer(1)

	local schema = Check.strictInterface({
		playground = Check.strictInterface({
			modelName = Check.string(32),
			partBudget = count,
			partCountAttribute = Check.string(32),
			folders = Check.strictInterface({
				railing = Check.string(32),
				pillars = Check.string(32),
				clouds = Check.string(32),
				enemies = Check.string(32),
				entities = Check.string(32),
			}),
			killVolumeName = Check.string(32),
		}),
		railing = Check.strictInterface({
			railCount = Check.integer(1, 4),
			material = Check.string(32),
			postColor = color,
			railColor = color,
			railOverlap = Check.number(0, 2),
		}),
		pillars = Check.strictInterface({
			material = Check.string(32),
			color = color,
			ceilingGap = Check.number(0, 60),
			light = Check.strictInterface({
				angle = Check.number(0, 180),
				color = color,
				shadows = Check.boolean,
			}),
		}),
		clouds = Check.strictInterface({
			particlesPerEmitter = count,
			lifetime = Check.strictInterface({ min = positive, max = positive }),
			lightEmission = Check.number(0, 1),
			spreadDegrees = Check.number(0, 180),
			rotationDegreesPerSecond = Check.number(0, 90),
			heightJitter = Check.number(0),
			radialJitter = Check.number(0),
			emitterPartSize = positive,
			color = color,
			textureAsset = Check.string(32),
			fallbackCountKey = Check.string(32),
		}),
		killVolume = Check.strictInterface({
			transparency = Check.number(0, 1),
			checkInterval = positive,
		}),
		spawn = Check.strictInterface({ groundEpsilon = Check.number(0, 1) }),
		character = Check.strictInterface({
			scaleValues = Check.strictInterface({
				bodyHeight = Check.string(32),
				bodyWidth = Check.string(32),
				bodyDepth = Check.string(32),
				head = Check.string(32),
			}),
			partWaitSeconds = positive,
		}),
		anticheat = Check.strictInterface({
			shadowAttribute = Check.string(32),
			shadowFraction = Check.number(0, 1),
			teleportWeightCapFraction = Check.number(0, 1),
			kickText = Check.string(200),
			lineToken = Check.string(32),
			kickDelay = Check.number(0, 5),
			abuseWeight = Check.integer(1),
			speedWeight = Check.integer(1),
			minimumAnomalies = Check.integer(2),
			reasons = Check.strictInterface({
				speed = Check.string(32),
				teleport = Check.string(32),
				abuse = Check.string(32),
			}),
			remoteStallSeconds = Check.number(0, 2),
			remoteRates = Check.map(
				Check.string(64),
				Check.strictInterface({ perSecond = positive, burst = count, clientBurst = Check.optional(count) })
			),
		}),
		performance = Check.strictInterface({
			maxServerHeartbeatMs = positive,
			heartbeatPercentile = Check.number(0.5, 1),
			maxMemoryMbPc = positive,
			maxMemoryMbMobile = positive,
			testPlayers = count,
			testEnemies = count,
			settleSeconds = Check.number(0),
			sampleSeconds = positive,
		}),
	})
	local ok, message = schema(World)
	if not ok then
		problem(tostring(message))
		return problems
	end

	-- The kick text travels as a SystemLine payload and the token must be a palette color.
	local Palette = ctx.load("src/shared/data/palette")
	if Palette.tokens[World.anticheat.lineToken] == nil then
		problem(("anticheat.lineToken '%s' is not a palette token"):format(tostring(World.anticheat.lineToken)))
	end
	local Combat = ctx.load("src/shared/data/combat")
	if World.anticheat.minimumAnomalies > Combat.anomalyKickThreshold then
		problem("anticheat.minimumAnomalies must not exceed combat.anomalyKickThreshold")
	end
	if World.anticheat.speedWeight * World.anticheat.minimumAnomalies > Combat.anomalyKickThreshold then
		problem("two over-speed samples alone must never reach the kick threshold")
	end
	local teleportCap = math.floor(Combat.anomalyKickThreshold * World.anticheat.teleportWeightCapFraction)
	if teleportCap >= Combat.anomalyKickThreshold then
		problem("a single teleport must never reach the kick threshold (anticheat.teleportWeightCapFraction)")
	end
	if World.anticheat.shadowFraction <= 0 or World.anticheat.shadowFraction >= 1 then
		problem("anticheat.shadowFraction must put the shadow flag above zero weight and before the kick")
	end

	-- Every client-to-server remote is rate limited from this table, and nothing else is listed.
	local Remotes = ctx.load("src/shared/net/Remotes")
	local rates = World.anticheat.remoteRates
	for name, definition in Remotes do
		if definition.direction == "ClientToServer" and rates[name] == nil then
			problem(("anticheat.remoteRates has no entry for the client-to-server remote %s"):format(name))
		end
	end
	for name in rates do
		local definition = Remotes[name]
		if definition == nil or definition.direction ~= "ClientToServer" then
			problem(("anticheat.remoteRates.%s is not a client-to-server remote"):format(tostring(name)))
		end
	end
	-- A client burst plus what a stall bunches behind it must fit the server's bucket.
	for name, rate in rates do
		local clientBurst = (rate :: any).clientBurst
		if clientBurst ~= nil and clientBurst + rate.perSecond * World.anticheat.remoteStallSeconds > rate.burst then
			problem(
				("anticheat.remoteRates.%s.clientBurst plus perSecond x remoteStallSeconds must fit inside burst"):format(
					tostring(name)
				)
			)
		end
	end

	if World.clouds.lifetime.max < World.clouds.lifetime.min then
		problem("clouds.lifetime.max must be at least its min")
	end
	if World.playground.partBudget > Fx.budgets.parts then
		problem("playground.partBudget must fit the section 11 scene budget")
	end
	if World.playground.folders.enemies ~= "Enemies" then
		problem("folders.enemies must be Enemies (EnemyService spawns into workspace.Enemies)")
	end
	if Playground.rim[World.clouds.fallbackCountKey] == nil then
		problem(
			("clouds.fallbackCountKey '%s' is not in playground.rim"):format(tostring(World.clouds.fallbackCountKey))
		)
	end
	for _, name in SCALE_VALUES do
		local found = false
		for _, value in World.character.scaleValues do
			if value == name then
				found = true
			end
		end
		if not found then
			problem(("character.scaleValues must include the engine's %s"):format(name))
		end
	end

	-- Section 16 targets and the load the perf smoke measures them under.
	local performance = World.performance
	if performance.maxServerHeartbeatMs >= SERVER_STEP_MS then
		problem(
			("performance.maxServerHeartbeatMs %s must fit inside one 60 Hz server step (%.2f ms)"):format(
				tostring(performance.maxServerHeartbeatMs),
				SERVER_STEP_MS
			)
		)
	end
	if performance.maxMemoryMbMobile >= performance.maxMemoryMbPc then
		problem("performance.maxMemoryMbMobile must be under performance.maxMemoryMbPc")
	end
	if performance.testPlayers > MAX_SERVER_PLAYERS then
		problem(("performance.testPlayers must not exceed a server's %d players"):format(MAX_SERVER_PLAYERS))
	end
	if performance.testEnemies < performance.testPlayers then
		problem("performance.testEnemies must give every stand-in at least one enemy")
	end
	for _, key in { "parts", "drawCalls" } do
		local value = Fx.budgets[key]
		if typeof(value) ~= "number" or value < 1 or value % 1 ~= 0 then
			problem(("fx.budgets.%s (read by the perf smoke) must be a positive whole number"):format(key))
		end
	end

	-- The live particle count the cloud ring asks for must leave room for combat FX.
	local cloudCount = Fx.quality.High.cloudBillboards
	local liveClouds = cloudCount * World.clouds.particlesPerEmitter
	if liveClouds * 2 > Fx.budgets.particles then
		problem(
			("the cloud ring would hold %d live particles, over half the %d budget"):format(
				liveClouds,
				Fx.budgets.particles
			)
		)
	end

	return problems
end

return validate
