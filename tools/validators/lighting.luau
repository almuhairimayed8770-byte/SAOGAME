--!strict
--[[
	Lighting validator: the section 11 values are present and exact, and every generator biome
	plus "Floor1" has a preset of {r, g, b} colors in 0..1.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local EXPECTED = {
	{ { "base", "technology" }, "Future" },
	{ { "base", "shadowSoftness" }, 0.2 },
	{ { "base", "environmentDiffuseScale" }, 0.6 },
	{ { "base", "environmentSpecularScale" }, 0.3 },
	{ { "colorCorrection", "saturation" }, 0.15 },
	{ { "colorCorrection", "contrast" }, 0.1 },
	{ { "bloom", "intensity" }, 0.4 },
	{ { "bloom", "size" }, 24 },
	{ { "bloom", "threshold" }, 0.9 },
	{ { "sunRays", "intensity" }, 0.1 },
	{ { "atmosphere", "density" }, 0.3 },
	{ { "atmosphere", "haze" }, 1.5 },
	{ { "atmosphere", "glare" }, 0.4 },
	{ { "town", "depthOfField", "focusDistance" }, 180 },
	{ { "town", "depthOfField", "farIntensity" }, 0.3 },
	{ { "night", "brightness" }, 0.8 },
	{ { "night", "bloomIntensity" }, 0.6 },
}

local COLOR_FIELDS = { "tint", "atmosphere", "decay", "ambient", "outdoorAmbient" }

local function isColor(value: any): boolean
	if typeof(value) ~= "table" or #value ~= 3 then
		return false
	end
	for index = 1, 3 do
		local channel = value[index]
		if typeof(channel) ~= "number" or channel < 0 or channel > 1 then
			return false
		end
	end
	return true
end

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end

	local Lighting = ctx.load("src/shared/data/lighting")
	local Floors = ctx.load("src/shared/data/floors")

	for _, row in EXPECTED do
		local keyPath, want = row[1], row[2]
		local value: any = Lighting
		for _, key in keyPath :: { string } do
			value = if typeof(value) == "table" then value[key] else nil
		end
		if value ~= want then
			problem("lighting.%s should be %s (got %s)", table.concat(keyPath, "."), tostring(want), tostring(value))
		end
	end

	local required = { "Floor1" }
	for _, kit in Floors.biomeKits do
		table.insert(required, kit)
	end
	for _, name in required do
		local preset = Lighting.biomes[name]
		if typeof(preset) ~= "table" then
			problem("lighting.biomes is missing the '%s' preset", name)
			continue
		end
		for _, field in COLOR_FIELDS do
			if not isColor(preset[field]) then
				problem("lighting.biomes.%s.%s must be {r, g, b} in 0..1", name, field)
			end
		end
		if typeof(preset.note) ~= "string" then
			problem("lighting.biomes.%s needs a note", name)
		end
	end
	for name in Lighting.biomes do
		if table.find(required, name) == nil then
			problem("lighting.biomes.%s is not a generator kit or Floor1", name)
		end
	end

	-- Floor 1 is the warmest-lit floor in the game (section 2): its tint leans furthest from
	-- blue toward red (warmth = r - b).
	local function warmth(color: { number }): number
		return color[1] - color[3]
	end
	local floor1 = Lighting.biomes.Floor1
	if typeof(floor1) == "table" and isColor(floor1.tint) then
		for name, preset in Lighting.biomes do
			if name ~= "Floor1" and isColor(preset.tint) and warmth(preset.tint) >= warmth(floor1.tint) then
				problem("lighting.biomes.%s is as warm as Floor1; Floor1 must be the warmest floor", name)
			end
		end
	end

	if Lighting.presetName(1, "plains") ~= "Floor1" or Lighting.presetName(2, "marsh") ~= "marsh" then
		problem("lighting.presetName must map floor 1 to Floor1 and every other floor to its biome")
	end

	return problems
end
