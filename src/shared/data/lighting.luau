--!strict
--[[
	Lighting (section 11): the values every floor place applies, the town and night overrides,
	and a tint/atmosphere preset per generator biome plus "Floor1" (the warmest floor in the
	game). Colors are {r, g, b} in 0..1 so the table loads in Lune; the place builder converts.

	A floor's preset name comes from Lighting.presetName(floorNumber, biome).
]]

export type ColorRGB = { number }

export type BiomePreset = {
	tint: ColorRGB, -- ColorCorrectionEffect.TintColor
	atmosphere: ColorRGB, -- Atmosphere.Color
	decay: ColorRGB, -- Atmosphere.Decay
	ambient: ColorRGB, -- Lighting.Ambient
	outdoorAmbient: ColorRGB, -- Lighting.OutdoorAmbient
	note: string,
}

local Lighting = {
	base = {
		technology = "Future",
		shadowSoftness = 0.2,
		environmentDiffuseScale = 0.6,
		environmentSpecularScale = 0.3,
		brightness = 2,
		globalShadows = true,
		dayClockTime = 10,
		geographicLatitude = 30,
		exposureCompensation = 0,
	},

	colorCorrection = {
		saturation = 0.15,
		contrast = 0.1,
	},

	bloom = {
		intensity = 0.4,
		size = 24,
		threshold = 0.9,
	},

	sunRays = {
		intensity = 0.1,
		spread = 0.6,
	},

	atmosphere = {
		density = 0.3,
		haze = 1.5,
		glare = 0.4,
		offset = 0,
	},

	--- The sky's Clouds. The engine takes a Clouds only under Workspace.Terrain, so the server
	--- builds it there at start (PlaygroundBuilder.buildSkyClouds); no place file holds one.
	clouds = {
		cover = 0.55,
		density = 0.3,
	},

	sky = {
		sunAngularSize = 14,
		moonAngularSize = 8,
		starCount = 1500,
	},

	--- Towns add a light DepthOfField (far distance 180, intensity 0.3).
	town = {
		depthOfField = {
			focusDistance = 180,
			farIntensity = 0.3,
			nearIntensity = 0,
			inFocusRadius = 60,
		},
	},

	--- Night lowers Brightness and raises Bloom; the server clock drives ClockTime.
	night = {
		brightness = 0.8,
		bloomIntensity = 0.6,
		clockTime = 0,
	},

	--- The in-game day (floors.anatomy.dayLengthMinutes real minutes) maps to ClockTime 0..24;
	--- these are the hours when night starts and ends.
	dayCycle = {
		nightStartHour = 19,
		nightEndHour = 5,
	},

	--- Per-biome tint and atmosphere. "Floor1" is the warmest-lit floor in the game (section 2).
	biomes = {
		Floor1 = {
			tint = { 1, 0.94, 0.78 },
			atmosphere = { 0.82, 0.88, 0.95 },
			decay = { 0.6, 0.68, 0.82 },
			ambient = { 0.38, 0.39, 0.42 },
			outdoorAmbient = { 0.5, 0.54, 0.6 },
			note = "cheap sunlight, warm cobbles, deep green",
		},
		plains = {
			tint = { 1, 0.98, 0.93 },
			atmosphere = { 0.78, 0.86, 0.95 },
			decay = { 0.55, 0.65, 0.8 },
			ambient = { 0.35, 0.37, 0.42 },
			outdoorAmbient = { 0.45, 0.5, 0.58 },
			note = "bright and open",
		},
		marsh = {
			tint = { 0.9, 0.95, 0.9 },
			atmosphere = { 0.62, 0.7, 0.66 },
			decay = { 0.4, 0.48, 0.44 },
			ambient = { 0.3, 0.34, 0.32 },
			outdoorAmbient = { 0.38, 0.44, 0.42 },
			note = "dusk fog, green-grey",
		},
		forest = {
			tint = { 1, 0.93, 0.86 },
			atmosphere = { 0.9, 0.72, 0.52 },
			decay = { 0.6, 0.42, 0.3 },
			ambient = { 0.36, 0.3, 0.26 },
			outdoorAmbient = { 0.5, 0.42, 0.36 },
			note = "autumn, red leaves, low sun",
		},
		coast = {
			tint = { 0.95, 0.98, 1 },
			atmosphere = { 0.75, 0.86, 0.98 },
			decay = { 0.5, 0.62, 0.82 },
			ambient = { 0.34, 0.38, 0.44 },
			outdoorAmbient = { 0.46, 0.52, 0.62 },
			note = "sea light, cool and clean",
		},
		cave = {
			tint = { 0.8, 0.9, 1 },
			atmosphere = { 0.25, 0.35, 0.45 },
			decay = { 0.1, 0.18, 0.28 },
			ambient = { 0.12, 0.16, 0.22 },
			outdoorAmbient = { 0.14, 0.2, 0.28 },
			note = "no sky; fungus glow carries the scene",
		},
		savanna = {
			tint = { 1, 0.95, 0.84 },
			atmosphere = { 0.95, 0.85, 0.65 },
			decay = { 0.72, 0.6, 0.42 },
			ambient = { 0.4, 0.36, 0.3 },
			outdoorAmbient = { 0.56, 0.5, 0.4 },
			note = "heat shimmer, dry gold",
		},
		snow = {
			tint = { 0.93, 0.97, 1 },
			atmosphere = { 0.88, 0.93, 1 },
			decay = { 0.68, 0.76, 0.9 },
			ambient = { 0.42, 0.45, 0.5 },
			outdoorAmbient = { 0.58, 0.62, 0.7 },
			note = "white, blue shadows",
		},
		twilight = {
			tint = { 0.88, 0.85, 1 },
			atmosphere = { 0.5, 0.45, 0.72 },
			decay = { 0.3, 0.25, 0.5 },
			ambient = { 0.24, 0.22, 0.34 },
			outdoorAmbient = { 0.3, 0.28, 0.44 },
			note = "violet dusk, fireflies read against it",
		},
		volcanic = {
			tint = { 1, 0.88, 0.82 },
			atmosphere = { 0.55, 0.4, 0.35 },
			decay = { 0.35, 0.22, 0.18 },
			ambient = { 0.3, 0.22, 0.2 },
			outdoorAmbient = { 0.4, 0.3, 0.26 },
			note = "ash haze, lava is the only neon",
		},
		canyon = {
			tint = { 1, 0.92, 0.86 },
			atmosphere = { 0.9, 0.75, 0.6 },
			decay = { 0.65, 0.48, 0.36 },
			ambient = { 0.38, 0.32, 0.28 },
			outdoorAmbient = { 0.52, 0.44, 0.38 },
			note = "red rock, hard shadows",
		},
		jungle = {
			tint = { 0.9, 1, 0.9 },
			atmosphere = { 0.6, 0.8, 0.62 },
			decay = { 0.35, 0.52, 0.38 },
			ambient = { 0.26, 0.34, 0.26 },
			outdoorAmbient = { 0.36, 0.48, 0.36 },
			note = "green canopy light, wet stone",
		},
		ruin = {
			tint = { 0.95, 0.95, 1 },
			atmosphere = { 0.75, 0.78, 0.88 },
			decay = { 0.5, 0.55, 0.68 },
			ambient = { 0.34, 0.35, 0.4 },
			outdoorAmbient = { 0.46, 0.48, 0.56 },
			note = "silver stone, cool neutral",
		},
	} :: { [string]: BiomePreset },
}

--- The preset name a floor uses: "Floor1" for floor 1, otherwise its biome kit.
function Lighting.presetName(floorNumber: number, biome: string): string
	if floorNumber == 1 then
		return "Floor1"
	end
	return biome
end

--- A biome preset by name; errors on an unknown name so a bad floor row fails at build time.
function Lighting.preset(name: string): BiomePreset
	local preset = Lighting.biomes[name]
	if preset == nil then
		error(("lighting: unknown preset '%s'"):format(tostring(name)))
	end
	return preset
end

--- Whether an in-game hour (ClockTime 0..24) counts as night for spawns and lighting.
function Lighting.isNightHour(hour: number): boolean
	local cycle = Lighting.dayCycle
	return hour >= cycle.nightStartHour or hour < cycle.nightEndHour
end

return Lighting
