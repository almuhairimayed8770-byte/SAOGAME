--!strict
--[[
	Validates src/shared/data/weaponModels.luau: every weapon category has stand-in geometry with
	positive dimensions, the blade is the long part (its length beats its width and thickness), the
	placeholder colors are palette tokens, and the names the rest of the game relies on (the Weapon
	part, the Weapon Motor6D, the TrailStart / TrailEnd / WeaponGrip attachments) are unchanged.

	Sheaths: every row is keyed by a weapon category and has the right shape (a pos and rot vec3, a
	wall above 0, a clearance of 0 or more, a palette color); its part is a PlayerR15 body part; the
	Playground loadout's weapon has a row; and the Sheath model, Scabbard part and ScabbardWeld
	names differ from each other and from every weapon name, since FX and the hit sweep find those
	by name anywhere under the character.
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
	local Rigs = ctx.load("src/shared/data/rigs")
	local Weapons = ctx.load("src/shared/data/weapons")
	local Playground = ctx.load("src/shared/data/playground")

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

	-- Sheaths: the back mount and the scabbard per category.
	local sheathSchema = Check.strictInterface({
		part = Check.string(64),
		mount = Check.strictInterface({ pos = Check.vec3(10), rot = Check.vec3(360) }),
		scabbard = Check.strictInterface({
			wall = Check.number(0, 1),
			clearance = Check.number(0, 2),
			color = Check.string(64),
		}),
	})
	-- The body parts a sheath may ride on: every part a PlayerR15 joint links, but the weapon's own.
	local bodyParts: { [string]: boolean } = {}
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name ~= WeaponModels.motorName then
			bodyParts[joint.part0] = true
			bodyParts[joint.part1] = true
		end
	end
	local sheaths = WeaponModels.sheaths
	if typeof(sheaths) ~= "table" then
		problem("sheaths must be a table of back mounts by weapon category")
		sheaths = {}
	end
	for category, row in sheaths do
		local label = ("sheaths.%s"):format(tostring(category))
		if table.find(CATEGORIES, category) == nil then
			problem(("%s: '%s' is not a weapon category"):format(label, tostring(category)))
		end
		local ok, message = sheathSchema(row)
		if not ok then
			problem(("%s: %s"):format(label, tostring(message)))
			continue
		end
		if not bodyParts[row.part] then
			problem(("%s: part '%s' is not a PlayerR15 body part"):format(label, row.part))
		end
		if row.scabbard.wall <= 0 then
			problem(("%s: scabbard.wall must be above 0 (the scabbard must be wider than the blade)"):format(label))
		end
		if Palette.tokens[row.scabbard.color] == nil then
			problem(("%s: scabbard.color '%s' is not a palette token"):format(label, row.scabbard.color))
		end
	end
	local loadoutWeapon = Weapons.byId(Playground.loadout.weapon)
	if loadoutWeapon == nil then
		problem(
			("the Playground loadout weapon '%s' is not in weapons.luau"):format(tostring(Playground.loadout.weapon))
		)
	elseif sheaths[loadoutWeapon.category] == nil then
		problem(
			("the Playground loadout's category %s has no sheaths row, so its sword never rides on the back"):format(
				loadoutWeapon.category
			)
		)
	end

	-- The sheath names must not collide with each other or with any name found by search.
	local searched: { { string } } = {
		{ "modelName", WeaponModels.modelName },
		{ "bladePart", WeaponModels.bladePart },
		{ "motorName", WeaponModels.motorName },
		{ "guardPart", WeaponModels.guardPart },
		{ "gripPart", WeaponModels.gripPart },
		{ "lightName", WeaponModels.lightName },
		{ "trailName", WeaponModels.trailName },
		{ "attachments.grip", attachments.grip },
		{ "attachments.trailStart", attachments.trailStart },
		{ "attachments.trailEnd", attachments.trailEnd },
	}
	local taken: { [string]: string } = {}
	for _, entry in searched do
		local label, name = entry[1], entry[2]
		taken[name] = if taken[name] ~= nil then taken[name] .. " and " .. label else label
	end
	for _, field in { "sheathModelName", "scabbardPart", "scabbardWeld" } do
		local name = WeaponModels[field]
		if typeof(name) ~= "string" or name == "" then
			problem(("%s must be a name"):format(field))
			continue
		end
		local other = taken[name]
		if other ~= nil then
			problem(("%s '%s' is also %s"):format(field, name, other))
			continue
		end
		taken[name] = field
	end

	return problems
end

return validate
