--!strict
--[[
	Validates src/shared/data/world.luau: the Playground part budget is under the section 11 scene
	budget and above what the rim, pillars and clouds need from playground.luau; every count,
	distance and time is positive; colors are {r, g, b} in 0..1; the folder EnemyService spawns
	into is still called Enemies; the Humanoid scale value names are the engine's.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local SCALE_VALUES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }

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
