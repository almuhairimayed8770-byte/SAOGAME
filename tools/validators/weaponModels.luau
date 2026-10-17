--!strict
--[[
	Validates src/shared/data/weaponModels.luau: every weapon category has stand-in geometry with
	positive dimensions, the blade is the long part (its length beats its width and thickness), the
	placeholder colors are palette tokens, and the names the rest of the game relies on (the Weapon
	part, the Weapon Motor6D, the TrailStart / TrailEnd / WeaponGrip attachments) are unchanged.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local CATEGORIES = {
	"OneHandedSword",
	"Rapier",
	"TwoHandedSword",
	"Katana",
	"Dagger",
	"Spear",
	"Axe",
	"Mace",
	"Shield",
	"MartialArts",
	"TwinFang",
	"AegisBlade",
}

local SHAPES = { "Block", "Ball", "Cylinder" }

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Check = ctx.load("src/shared/util/Check")
	local Palette = ctx.load("src/shared/data/palette")
	local WeaponModels = ctx.load("src/shared/data/weaponModels")

	local function problem(message: string)
		table.insert(problems, "weaponModels: " .. message)
	end

	local positive = Check.number(0.01, 40)
	local schema = Check.strictInterface({
		blade = Check.strictInterface({ length = positive, width = positive, thickness = positive }),
		guard = Check.strictInterface({ width = positive, height = positive, depth = positive }),
		grip = Check.strictInterface({ length = positive, width = positive }),
		shape = Check.optional(Check.literal(table.unpack(SHAPES))),
		note = Check.string(200),
	})

	for _, category in CATEGORIES do
		local model = WeaponModels.categories[category]
		if model == nil then
			problem(("category %s has no placeholder geometry"):format(category))
			continue
		end
		local ok, message = schema(model)
		if not ok then
			problem(("%s: %s"):format(category, tostring(message)))
			continue
		end
		if model.blade.length < model.blade.width or model.blade.length < model.blade.thickness then
			problem(("%s: the blade's length must be its long axis (+Y, tip forward)"):format(category))
		end
		if WeaponModels.holdOffset(category) <= model.blade.length / 2 then
			problem(("%s: the hold point must sit below the blade"):format(category))
		end
	end
	for category in WeaponModels.categories do
		if table.find(CATEGORIES, category) == nil then
			problem(("unknown weapon category '%s'"):format(tostring(category)))
		end
	end

	for role, token in WeaponModels.colors do
		if Palette.tokens[token] == nil then
			problem(("colors.%s '%s' is not a palette token"):format(tostring(role), tostring(token)))
		end
	end

	-- Names the client FX, HitSweep and the clips depend on.
	if WeaponModels.bladePart ~= "Weapon" or WeaponModels.modelName ~= "Weapon" then
		problem("the blade part and the weapon Model must both be named Weapon (ARCHITECTURE)")
	end
	if WeaponModels.motorName ~= "Weapon" then
		problem("the weapon Motor6D must be named Weapon (the rigs.luau PlayerR15 joint)")
	end
	local attachments = WeaponModels.attachments
	if
		attachments.trailStart ~= "TrailStart"
		or attachments.trailEnd ~= "TrailEnd"
		or attachments.grip ~= "WeaponGrip"
	then
		problem("attachment names must be WeaponGrip / TrailStart / TrailEnd (section 10)")
	end
	if WeaponModels.tag ~= "Placeholder" then
		problem("stand-in weapons must carry the Placeholder tag (section 19)")
	end
	if WeaponModels.partsPerWeapon ~= 3 then
		problem("partsPerWeapon must count the blade, guard and grip")
	end

	return problems
end

return validate
