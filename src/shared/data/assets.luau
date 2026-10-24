--!strict
--[[
	Asset registry (section 19): every uploaded id by name. Until the user uploads an asset its
	id is 0 and `placeholder` is true; the game then uses a part-built stand-in with the right
	size and Highlight (D-009) and docs/PLACEHOLDERS.md lists it. The assets validator prints the
	missing ones and fails only on an entry whose id is 0 while placeholder is false.

	Studio handoff: upload through Studio or the Open Cloud assets API, paste the id here, flip
	placeholder to false (docs/STUDIO_TASKS.md has the steps).
]]

export type Kind = "Mesh" | "Texture" | "Sound" | "Font" | "Animation"

export type AssetDef = {
	id: number,
	kind: Kind,
	placeholder: boolean,
	note: string,
}

local function asset(kind: Kind, note: string): AssetDef
	return { id = 0, kind = kind, placeholder = true, note = note }
end

local Assets = {
	kinds = { "Mesh", "Texture", "Sound", "Font", "Animation" } :: { Kind },

	registry = {
		-- Rigs (section 10). Until uploaded: R15 with anime scale values / part-built enemy rigs.
		PlayerAnimeRig = asset("Mesh", "R15-compatible player rig with anime proportions; keep the 15 Motor6D names"),
		BoarRig = asset("Mesh", "Frenzy Boar: four legs and a spine, blue hide, tusks; joints as rigs.luau"),
		KoboldRig = asset("Mesh", "Kobold Axeman: humanoid, round shoulders, big hands; joints as rigs.luau"),

		-- Weapons
		TrialistSword = asset("Mesh", "the starter one-handed sword; blade length sets reach in weapons.luau"),

		-- FX textures
		TrailGradient = asset("Texture", "soft gradient for weapon Trails; white, alpha fades to the tail"),
		Shard = asset("Mesh", "wedge shard for the shatter pool; Neon, ShardBlue"),
		TelegraphLine = asset("Texture", "flat ground decal: a line with a soft edge"),
		TelegraphCone = asset("Texture", "flat ground decal: a cone / arc"),
		TelegraphCircle = asset("Texture", "flat ground decal: a filled circle with a soft edge"),
		HexTile = asset("Texture", "hexagonal system panel tile for the red sky and Mirror Shields"),
		CloudBillboard = asset("Texture", "soft cloud for the ring of billboards below the rim"),

		-- Fonts (section 14): two, never more.
		SystemFont = asset("Font", "rounded geometric sans for system text; Gotham is the fallback"),
		SerifFont = asset("Font", "narrow serif for item and lore text"),
	} :: { [string]: AssetDef },

	fallbackFonts = {
		SystemFont = "Gotham",
		SerifFont = "Garamond",
	},
}

--- An asset by name; errors on an unknown name.
function Assets.get(name: string): AssetDef
	local def = Assets.registry[name]
	if def == nil then
		error(("assets: unknown asset '%s'"):format(tostring(name)))
	end
	return def
end

--- The rbxassetid url for an asset (rbxassetid://0 while it is a placeholder).
function Assets.url(name: string): string
	return "rbxassetid://" .. tostring(Assets.get(name).id)
end

--- True when the asset has been uploaded (a real id and placeholder cleared).
function Assets.isReady(name: string): boolean
	local def = Assets.get(name)
	return def.id > 0 and not def.placeholder
end

--- Sorted names of every asset that still has no id.
function Assets.missing(): { string }
	local names = {}
	for name, def in Assets.registry do
		if def.id == 0 then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

return Assets
