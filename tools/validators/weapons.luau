--!strict
--[[
	Validates src/shared/data/weapons.luau: WeaponDef fields and types, ids match keys, categories
	and rarities are known, every trailColor (and Twin Fang twinColor) is a palette token matching
	the section 8 category color, slots match the rarity table, a Common floor-1 starter exists per
	category, the drop weights sum to 100, and floor 1 has at least three named weapons.
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
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Apex" }
local SOURCES = { "LAB", "FieldBoss", "MiniDungeon", "Smith", "Drop", "Vendor" }

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Check = ctx.load("src/shared/util/Check")
	local Palette = ctx.load("src/shared/data/palette")
	local Weapons = ctx.load("src/shared/data/weapons")

	local function problem(id: string, message: string)
		table.insert(problems, ("weapons.%s: %s"):format(id, message))
	end

	local schema = Check.interface({
		id = Check.string(64),
		name = Check.string(64),
		category = Check.literal(table.unpack(CATEGORIES)),
		rarity = Check.literal(table.unpack(RARITIES)),
		attack = Check.number(0),
		gaugeDamage = Check.number(0, 10),
		durability = Check.number(1),
		weight = Check.number(0, 50),
		trailWidth = Check.number(0.1, 5),
		trailColor = Check.string(32),
		reach = Check.number(0.5, 40),
		floor = Check.integer(1, 100),
		slots = Check.integer(0, 5),
		named = Check.optional(Check.boolean),
		source = Check.optional(Check.literal(table.unpack(SOURCES))),
		twinColor = Check.optional(Check.string(32)),
		description = Check.optional(Check.string(200)),
		bossOnly = Check.optional(Check.boolean),
	})

	-- Rarity table
	local weightSum = 0
	for _, rarity in RARITIES do
		local row = Weapons.rarity[rarity]
		if row == nil then
			problem("rarity", ("missing rarity row '%s'"):format(rarity))
			continue
		end
		weightSum += row.dropWeight
		if row.slots ~= table.find(RARITIES, rarity) - 1 then
			problem("rarity", ("%s should have %d slots"):format(rarity, table.find(RARITIES, rarity) - 1))
		end
	end
	if weightSum ~= 100 then
		problem("rarity", ("drop weights sum to %d, not 100"):format(weightSum))
	end
	if Weapons.rarity.Apex and Weapons.rarity.Apex.dropWeight ~= 0 then
		problem("rarity", "Apex pieces are never random drops; dropWeight must be 0")
	end

	local namedOnFloor1 = 0
	local startersSeen: { [string]: boolean } = {}

	for key, weapon in Weapons.rows do
		local ok, message = schema(weapon)
		if not ok then
			problem(tostring(key), message or "invalid row")
			continue
		end
		if weapon.id ~= key then
			problem(key, ("id '%s' does not match its key"):format(weapon.id))
		end
		if Palette.tokens[weapon.trailColor] == nil then
			problem(key, ("trailColor '%s' is not a palette token"):format(weapon.trailColor))
		end
		local expectedColor = Weapons.trailColor[weapon.category]
		if weapon.trailColor ~= expectedColor then
			problem(
				key,
				("trailColor '%s' is not the %s color %s"):format(
					weapon.trailColor,
					weapon.category,
					tostring(expectedColor)
				)
			)
		end
		if weapon.category == "TwinFang" then
			if weapon.twinColor == nil then
				problem(key, "Twin Fang weapons need a twinColor")
			elseif Palette.tokens[weapon.twinColor] == nil then
				problem(key, ("twinColor '%s' is not a palette token"):format(weapon.twinColor))
			elseif weapon.twinColor ~= Weapons.twinFangSecondColor then
				problem(key, ("twinColor should be %s"):format(Weapons.twinFangSecondColor))
			end
		elseif weapon.twinColor ~= nil then
			problem(key, "only Twin Fang weapons carry a twinColor")
		end
		local rarityRow = Weapons.rarity[weapon.rarity]
		if rarityRow and weapon.slots ~= rarityRow.slots then
			problem(key, ("%s weapons have %d slots, not %d"):format(weapon.rarity, rarityRow.slots, weapon.slots))
		end
		if weapon.named then
			if weapon.source == nil then
				problem(key, "named weapons need a source")
			end
			if weapon.floor == 1 then
				namedOnFloor1 += 1
			end
		end
		if weapon.rarity == "Apex" and (weapon.source == "Drop" or weapon.source == "Vendor") then
			problem(key, "Apex weapons never drop or sell")
		end
		if weapon.bossOnly and (weapon.source ~= nil or weapon.named) then
			problem(key, "boss-held weapons have no player source and are not named weapons")
		end
		if weapon.attack <= 0 and weapon.category ~= "Shield" then
			problem(key, "attack must be > 0")
		end
	end

	-- Starters: one Common floor-1 weapon per category
	for _, category in CATEGORIES do
		local starterId = Weapons.starters[category]
		if starterId == nil then
			problem(category, "no starter weapon")
			continue
		end
		local starter = Weapons.rows[starterId]
		if starter == nil then
			problem(category, ("starter '%s' is not a row"):format(starterId))
			continue
		end
		if starter.category ~= category then
			problem(starterId, ("starter for %s is a %s"):format(category, starter.category))
		end
		if starter.rarity ~= "Common" or starter.floor ~= 1 then
			problem(starterId, "starters are Common and floor 1")
		end
		if starter.attack ~= Weapons.baseAttack[category] then
			problem(
				starterId,
				("starter attack %s should equal baseAttack %s"):format(
					starter.attack,
					tostring(Weapons.baseAttack[category])
				)
			)
		end
		startersSeen[starterId] = true
	end

	local trialist = Weapons.rows.TrialistSword
	if trialist == nil then
		problem("TrialistSword", "missing (the Phase 0 loadout weapon)")
	elseif
		trialist.attack ~= 18
		or trialist.reach ~= 4.5
		or trialist.trailWidth ~= 0.9
		or trialist.trailColor ~= "TrailCyanWhite"
	then
		problem("TrialistSword", "Phase 0 numbers drifted (attack 18, reach 4.5, trailWidth 0.9, TrailCyanWhite)")
	end

	for _, id in { "TemperedEdge", "LucentNeedle", "KoboldCleaver", "GlacierEdge", "Nightfall", "SovereignsOath" } do
		if Weapons.rows[id] == nil then
			problem(id, "section 8 named weapon is missing")
		elseif not Weapons.rows[id].named then
			problem(id, "section 8 weapon must be named = true")
		end
	end

	if namedOnFloor1 < 3 then
		problem("floor1", ("only %d named weapons on floor 1; need at least 3"):format(namedOnFloor1))
	end

	return problems
end

return validate
