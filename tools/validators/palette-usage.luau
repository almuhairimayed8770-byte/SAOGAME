--!strict
--[[
	Palette usage validator (section 11): the palette is the only source of color for UI and FX.
	Scans src/client/fx and src/client/ui for Palette.rgb("X") / Palette.color3("X") and checks
	that X is a token; also checks the trail colors in weapons.luau (when it exists) and the
	placeholder part colors in rigs.luau name real tokens.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local DIRECTORIES = { "src/client/fx", "src/client/ui" }

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end

	local Palette = ctx.load("src/shared/data/palette")
	local tokens = Palette.tokens

	for _, directory in DIRECTORIES do
		local ok, files = pcall(ctx.listFiles, directory, "%.luau$")
		if not ok then
			continue -- the package has not landed yet
		end
		for _, path in files :: { string } do
			local content = ctx.readFile(path)
			local lineNumber = 0
			for line in (content .. "\n"):gmatch("(.-)\n") do
				lineNumber += 1
				for token in line:gmatch('Palette%.rgb%(%s*"([^"]*)"') do
					if tokens[token] == nil then
						problem('%s:%d: Palette.rgb("%s") is not a palette token', path, lineNumber, token)
					end
				end
				for token in line:gmatch('Palette%.color3%(%s*"([^"]*)"') do
					if tokens[token] == nil then
						problem('%s:%d: Palette.color3("%s") is not a palette token', path, lineNumber, token)
					end
				end
			end
		end
	end

	local Rigs = ctx.load("src/shared/data/rigs")
	for rigId, rig in Rigs do
		if typeof(rig.parts) == "table" then
			for partName, part in rig.parts do
				if typeof(part.color) == "string" and tokens[part.color] == nil then
					problem("rigs.%s part %s color '%s' is not a palette token", rigId, partName, part.color)
				end
			end
		end
	end

	local okWeapons, Weapons = pcall(ctx.load, "src/shared/data/weapons")
	if okWeapons and typeof(Weapons) == "table" then
		local rows = if typeof(Weapons.rows) == "table" then Weapons.rows else Weapons
		for key, weapon in rows do
			if typeof(weapon) == "table" and weapon.trailColor ~= nil and tokens[weapon.trailColor] == nil then
				problem(
					"weapons.luau %s trailColor '%s' is not a palette token",
					tostring(key),
					tostring(weapon.trailColor)
				)
			end
		end
	end

	return problems
end
