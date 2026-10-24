--!strict
--[[
	The Playground place (section 20, Phase 0; D-013): a 400-stud field, a rim, a ceiling and a
	kill volume, with a few boars and kobolds and a level-1 Trialist loadout whose proficiency
	unlocks Horizontal, Vertical, Rising Arc and Sharp Nail.

	The place JSON holds the static disc and ceiling; PlaygroundBuilder adds the rim, pillars,
	clouds and kill volume from this table; PlaygroundService spawns from the tables below.
	Distances are studs, positions are {x, y, z} with the field center at the origin and the
	field surface at y = 0.
]]

export type Spawn = {
	enemy: string, -- enemy def id in enemies.luau
	position: { number },
	facing: number, -- degrees, 0 faces -Z
	packSize: { min: number, max: number },
}

export type SpawnSpacing = {
	minStuds: number, -- root to root, studs
	tries: number, -- spots drawn per disc
	widenStuds: number, -- how much each widening adds to the disc radius
	widenings: number, -- how many times the disc may widen
}

local Playground = {
	fieldRadius = 200,
	ceilingHeight = 350,
	lightingPreset = "Floor1",

	rim = {
		railingHeight = 3.5,
		railThickness = 0.6,
		postSpacing = 10, -- studs between railing posts along the rim
		postSize = { 0.8, 3.5, 0.8 },
		cloudRingDrop = 200, -- studs below the field surface
		cloudCount = 24,
		cloudRingRadius = 260,
		cloudSize = 120,
		cloudDriftStudsPerSecond = 1.5,
		pillarCount = 8,
		pillarDistance = 520, -- studs from the center to each outer pillar
		pillarHeight = 800, -- the pillars span from below the clouds to the ceiling
		pillarRadius = 18,
		pillarLightRange = 60, -- SurfaceLight at the ceiling end of each pillar
		pillarLightBrightness = 2,
	},

	killVolume = {
		y = -50, -- a player below this is dead (falling off the rim)
		halfExtent = 1200,
		thickness = 10,
	},

	--- Spawn points: three Frenzy Boar packs 40..120 studs out, two Kobold Axemen 60..100 out.
	spawns = {
		{ enemy = "FrenzyBoar", position = { 60, 0, -40 }, facing = 180, packSize = { min = 1, max = 2 } },
		{ enemy = "FrenzyBoar", position = { -90, 0, 30 }, facing = 90, packSize = { min = 1, max = 2 } },
		{ enemy = "FrenzyBoar", position = { 20, 0, 110 }, facing = 0, packSize = { min = 1, max = 2 } },
		{ enemy = "KoboldAxeman", position = { -70, 0, -50 }, facing = 135, packSize = { min = 1, max = 1 } },
		{ enemy = "KoboldAxeman", position = { 85, 0, 45 }, facing = 270, packSize = { min = 1, max = 1 } },
	} :: { Spawn },

	spawnRings = {
		FrenzyBoar = { min = 40, max = 120 },
		KoboldAxeman = { min = 60, max = 100 },
	},

	respawnSeconds = 20, -- Playground only; fields use floors.anatomy.packRespawnMinutes
	spawnScatterRadius = 6, -- pack members scatter this far from the spawn point
	spawnFacingJitterDegrees = 20,
	-- No fighter spawns on another (D-170). A spawning enemy's root stands at least minStuds from
	-- the root of every living fighter, players included: a boar reaches 5.6 studs from its root
	-- (snout), so two boars this far apart clear each other at any facing. It tries `tries` spots in
	-- the scatter disc, then widens the disc by widenStuds, up to `widenings` times; with no clear
	-- spot left it takes the roomiest spot it tried.
	spawnSpacing = {
		minStuds = 12,
		tries = 12,
		widenStuds = 6,
		widenings = 4,
	} :: SpawnSpacing,
	playerSpawn = { position = { 0, 0, 0 }, facing = 0 },

	loadout = {
		weapon = "TrialistSword",
		armor = {
			Chest = "TrialistTunic",
			Legs = "TrialistTrousers",
			Hands = "TrialistGloves",
			Boots = "TrialistBoots",
		},
		level = 1,
		str = 10,
		agi = 10,
		proficiency = { OneHandedSword = 150 },
		-- The Arts the proficiency above unlocks, in quick-slot order (checked against arts.luau).
		artSlots = {
			"OneHandedSword.Horizontal",
			"OneHandedSword.Vertical",
			"OneHandedSword.RisingArc",
			"OneHandedSword.SharpNail",
		},
	},

	--- Capture / ClipLab helpers (section 20 gate clip): where the review camera starts.
	capture = {
		cameraDistance = 14,
		cameraHeight = 5,
		clipSeconds = 20,
	},
}

--- Horizontal distance of a position from the field center.
function Playground.distanceFromCenter(position: { number }): number
	return math.sqrt(position[1] * position[1] + position[3] * position[3])
end

--- The spawn ring an enemy id must sit in, or nil when the Playground has no rule for it.
function Playground.ringFor(enemyId: string): { min: number, max: number }?
	return Playground.spawnRings[enemyId]
end

return Playground
