--!strict
--[[
	Assets validator: every registry entry has a non-negative integer id, a known kind, a boolean
	placeholder flag and a note; an entry with id 0 must be flagged placeholder, and every Phase 0
	reference exists. Missing ids are printed (section 19: "tools/assets.luau reports missing
	ones") but do not fail the build while they are flagged as placeholders.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local KINDS = { Mesh = true, Texture = true, Sound = true, Font = true, Animation = true }

local PHASE_0 = {
	"PlayerAnimeRig",
	"BoarRig",
	"KoboldRig",
	"TrialistSword",
	"TrailGradient",
	"Shard",
	"TelegraphLine",
	"TelegraphCone",
	"TelegraphCircle",
	"HexTile",
	"SystemFont",
	"SerifFont",
}

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end

	local Assets = ctx.load("src/shared/data/assets")

	for _, name in PHASE_0 do
		if typeof(Assets.registry[name]) ~= "table" then
			problem("assets.registry is missing the Phase 0 entry '%s'", name)
		end
	end

	for name, def in Assets.registry do
		local label = ("assets.registry.%s"):format(tostring(name))
		if typeof(name) ~= "string" or not name:match("^%u[%w]*$") then
			problem("%s: asset names are PascalCase", label)
		end
		if typeof(def.id) ~= "number" or def.id < 0 or def.id % 1 ~= 0 then
			problem("%s: id must be a non-negative integer", label)
		end
		if not KINDS[def.kind] then
			problem("%s: unknown kind '%s'", label, tostring(def.kind))
		end
		if typeof(def.placeholder) ~= "boolean" then
			problem("%s: placeholder must be a boolean", label)
		elseif def.id == 0 and not def.placeholder then
			problem("%s: id 0 must be marked placeholder = true", label)
		end
		if typeof(def.note) ~= "string" or def.note == "" then
			problem("%s: needs a note for the modeler / uploader", label)
		end
	end

	-- Rigs that point at an asset must point at a registered mesh.
	local Rigs = ctx.load("src/shared/data/rigs")
	for rigId, rig in Rigs do
		if rig.assetKey ~= nil then
			local def = Assets.registry[rig.assetKey]
			if def == nil then
				problem("rigs.%s.assetKey '%s' is not in assets.luau", rigId, tostring(rig.assetKey))
			elseif def.kind ~= "Mesh" then
				problem("rigs.%s.assetKey '%s' is not a Mesh", rigId, tostring(rig.assetKey))
			end
		end
	end

	local missing = Assets.missing()
	if #missing > 0 then
		print(("  ~ assets: %d placeholder ids still 0: %s"):format(#missing, table.concat(missing, ", ")))
	end

	return problems
end
