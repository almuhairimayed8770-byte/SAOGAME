--!strict
--[[
	Weapons (sections 8, 12, 13). One starter per category, the named weapons of section 8, and the
	rarity table that sets base attack scale, enhancement slots and drop weight.

	Numbers: attack is the tier-1 value for a row's floor and rarity (base attack per category times
	the rarity scale times the floor's attack tier, rounded); gaugeDamage is a scale applied to an
	Art's gaugeDamage (axes and maces crush guards, rapiers and daggers barely touch them); reach is
	the capsule sweep length; trailWidth is studs; trailColor is the section 8 category color as a
	palette token. Twin Fang weapons carry a second color (`twinColor`) because both blades trail.

	Apex weapons are never random drops (section 8); they come from the sources in apex.luau.
]]

local Types = require(script.Parent.Parent.types)
local Tiers = require(script.Parent.tiers)

export type WeaponSource = "LAB" | "FieldBoss" | "MiniDungeon" | "Smith" | "Drop" | "Vendor"

export type Weapon = Types.WeaponDef & {
	twinColor: string?, -- second trail color (Twin Fang only)
	description: string?, -- one line for the item card
	bossOnly: boolean?, -- a weapon a boss draws on a phase (bosses.luau); never a player item, never a drop
}

export type RarityRow = {
	attackScale: number, -- multiplier on the category's base attack
	slots: number, -- enhancement slots
	dropWeight: number, -- section 13: 60 / 25 / 10 / 4 / 1; Apex never drops
	durabilityScale: number,
}

local Weapons = {}

-- Section 8 / 13 rarity table.
Weapons.rarity = {
	Common = { attackScale = 1.0, slots = 0, dropWeight = 60, durabilityScale = 1.0 },
	Uncommon = { attackScale = 1.15, slots = 1, dropWeight = 25, durabilityScale = 1.2 },
	Rare = { attackScale = 1.3, slots = 2, dropWeight = 10, durabilityScale = 1.4 },
	Epic = { attackScale = 1.5, slots = 3, dropWeight = 4, durabilityScale = 1.7 },
	Legendary = { attackScale = 1.8, slots = 4, dropWeight = 1, durabilityScale = 2.0 },
	Apex = { attackScale = 2.2, slots = 5, dropWeight = 0, durabilityScale = 2.5 },
} :: { [Types.Rarity]: RarityRow }

Weapons.rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Apex" } :: { Types.Rarity }

-- Tier-1 Common attack per category (the starter's attack). Two-handers hit hard and slow;
-- daggers and fists make it up in hit count.
Weapons.baseAttack = {
	OneHandedSword = 18,
	Rapier = 15,
	TwoHandedSword = 26,
	Katana = 20,
	Dagger = 12,
	Spear = 20,
	Axe = 24,
	Mace = 22,
	Shield = 6,
	MartialArts = 10,
	TwinFang = 16,
	AegisBlade = 18,
} :: { [Types.WeaponCategory]: number }

-- Section 8 trail colors per category as palette tokens.
Weapons.trailColor = {
	OneHandedSword = "TrailCyanWhite",
	Rapier = "TrailPaleGold",
	TwoHandedSword = "TrailCrimson",
	Katana = "TrailSilverBlue",
	Dagger = "TrailViolet",
	Spear = "TrailJade",
	Axe = "TrailOrange",
	Mace = "TrailAmber",
	Shield = "TrailWhite",
	MartialArts = "TrailRose",
	TwinFang = "TrailCyanWhite",
	AegisBlade = "TrailIvory",
} :: { [Types.WeaponCategory]: string }

Weapons.twinFangSecondColor = "TrailViolet"

-- Enhancement (section 8)
Weapons.enhancement = {
	maxLevel = 15,
	successStart = 0.95,
	successFallPerLevel = 0.04,
	breakRiskFromLevel = 10, -- from +10 up, a failure may break the weapon in Lucid
	breakChanceOnFailure = 0.25,
	attributes = { "Sharpness", "Quickness", "Accuracy", "Heaviness", "Durability" },
	legacyResetLevel = 0, -- a willed weapon arrives at +0
}

local rows: { [string]: Weapon } = {
	-- ------------------------------------------------------------------ starters (Trialist issue)
	TrialistSword = {
		id = "TrialistSword",
		name = "Trialist Sword",
		category = "OneHandedSword",
		rarity = "Common",
		attack = 18,
		gaugeDamage = 1.0,
		durability = 120,
		weight = 3,
		trailWidth = 0.9,
		trailColor = "TrailCyanWhite",
		reach = 4.5,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "Plain steel issued at the Firstlight gate. Every climb starts here.",
	},
	TrialistFoil = {
		id = "TrialistFoil",
		name = "Trialist Foil",
		category = "Rapier",
		rarity = "Common",
		attack = 15,
		gaugeDamage = 0.7,
		durability = 110,
		weight = 2,
		trailWidth = 0.5,
		trailColor = "TrailPaleGold",
		reach = 5,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "A thin blade with a cup guard; it asks for precision and gives nothing else.",
	},
	TrialistGreatsword = {
		id = "TrialistGreatsword",
		name = "Trialist Greatsword",
		category = "TwoHandedSword",
		rarity = "Common",
		attack = 26,
		gaugeDamage = 1.5,
		durability = 140,
		weight = 8,
		trailWidth = 1.4,
		trailColor = "TrailCrimson",
		reach = 6,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "Too much blade for a beginner, which is exactly why beginners want it.",
	},
	TrialistKatana = {
		id = "TrialistKatana",
		name = "Trialist Katana",
		category = "Katana",
		rarity = "Common",
		attack = 20,
		gaugeDamage = 0.9,
		durability = 110,
		weight = 3,
		trailWidth = 0.8,
		trailColor = "TrailSilverBlue",
		reach = 5.5,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "A curved blade in a plain lacquer sheath; it is drawn, never carried bare.",
	},
	TrialistKnife = {
		id = "TrialistKnife",
		name = "Trialist Knife",
		category = "Dagger",
		rarity = "Common",
		attack = 12,
		gaugeDamage = 0.5,
		durability = 100,
		weight = 1,
		trailWidth = 0.4,
		trailColor = "TrailViolet",
		reach = 3,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "Short, quick and close. The Spire rewards the ones who get behind things.",
	},
	TrialistSpear = {
		id = "TrialistSpear",
		name = "Trialist Spear",
		category = "Spear",
		rarity = "Common",
		attack = 20,
		gaugeDamage = 1.0,
		durability = 120,
		weight = 5,
		trailWidth = 0.7,
		trailColor = "TrailJade",
		reach = 10,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "Ash shaft, leaf blade. Reach is a kind of armor.",
	},
	TrialistHatchet = {
		id = "TrialistHatchet",
		name = "Trialist Hatchet",
		category = "Axe",
		rarity = "Common",
		attack = 24,
		gaugeDamage = 1.6,
		durability = 130,
		weight = 6,
		trailWidth = 1.2,
		trailColor = "TrailOrange",
		reach = 4.5,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "A woodcutter's axe with the handle shortened for a fighter's grip.",
	},
	TrialistCudgel = {
		id = "TrialistCudgel",
		name = "Trialist Cudgel",
		category = "Mace",
		rarity = "Common",
		attack = 22,
		gaugeDamage = 1.5,
		durability = 150,
		weight = 6,
		trailWidth = 1.1,
		trailColor = "TrailAmber",
		reach = 4,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "Iron-shod oak. Guards do not like it.",
	},
	TrialistBuckler = {
		id = "TrialistBuckler",
		name = "Trialist Buckler",
		category = "Shield",
		rarity = "Common",
		attack = 6,
		gaugeDamage = 1.8,
		durability = 160,
		weight = 4,
		trailWidth = 1.0,
		trailColor = "TrailWhite",
		reach = 3,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "A round shield with a steel boss; it widens the guard and bashes when asked.",
	},
	TrialistWraps = {
		id = "TrialistWraps",
		name = "Trialist Wraps",
		category = "MartialArts",
		rarity = "Common",
		attack = 10,
		gaugeDamage = 0.8,
		durability = 200,
		weight = 0,
		trailWidth = 0.6,
		trailColor = "TrailRose",
		reach = 3,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "Linen hand wraps. The unarmed line trades reach for mobility.",
	},
	TrialistTwinBlades = {
		id = "TrialistTwinBlades",
		name = "Trialist Twin Blades",
		category = "TwinFang",
		rarity = "Common",
		attack = 16,
		gaugeDamage = 1.0,
		durability = 120,
		weight = 4,
		trailWidth = 0.8,
		trailColor = "TrailCyanWhite",
		twinColor = "TrailViolet",
		reach = 4.5,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "A matched pair the gate smith hands only to a Dual Wielder. They draw a crowd.",
	},
	TrialistVowBlade = {
		id = "TrialistVowBlade",
		name = "Trialist Vow Blade",
		category = "AegisBlade",
		rarity = "Common",
		attack = 18,
		gaugeDamage = 1.2,
		durability = 160,
		weight = 4,
		trailWidth = 1.0,
		trailColor = "TrailIvory",
		reach = 4.5,
		floor = 1,
		slots = 0,
		source = "Vendor",
		description = "A broad blade paired with a tower shield mount; it only strikes after it has held.",
	},

	-- ------------------------------------------------------------------ named weapons, floor 1
	TemperedEdge = {
		id = "TemperedEdge",
		name = "Tempered Edge",
		category = "OneHandedSword",
		rarity = "Rare",
		attack = 24,
		gaugeDamage = 1.0,
		durability = 170,
		weight = 3,
		trailWidth = 0.9,
		trailColor = "TrailCyanWhite",
		reach = 4.5,
		floor = 1,
		slots = 2,
		named = true,
		source = "Drop",
		description = "The first blade worth enhancing; its edge holds a line of blue heat after a swing.",
	},
	KoboldCleaver = {
		id = "KoboldCleaver",
		name = "Kobold Cleaver",
		category = "Axe",
		rarity = "Uncommon",
		attack = 28,
		gaugeDamage = 1.6,
		durability = 150,
		weight = 6,
		trailWidth = 1.2,
		trailColor = "TrailOrange",
		reach = 4.5,
		floor = 1,
		slots = 1,
		named = true,
		source = "Drop",
		description = "Taken from a Kobold Axeman. Crude, heavy, and it opens guards like doors.",
	},
	WarboarTuskSpear = {
		id = "WarboarTuskSpear",
		name = "Warboar Tusk Spear",
		category = "Spear",
		rarity = "Rare",
		attack = 26,
		gaugeDamage = 1.1,
		durability = 170,
		weight = 5,
		trailWidth = 0.7,
		trailColor = "TrailJade",
		reach = 10,
		floor = 1,
		slots = 2,
		named = true,
		source = "FieldBoss",
		description = "A tusk of the Warboar King lashed to an oak shaft. It charges back.",
	},
	DaybreakEdge = {
		id = "DaybreakEdge",
		name = "Daybreak Edge",
		category = "OneHandedSword",
		rarity = "Apex",
		attack = 40,
		gaugeDamage = 1.1,
		durability = 300,
		weight = 3,
		trailWidth = 1.0,
		trailColor = "TrailCyanWhite",
		reach = 4.5,
		floor = 1,
		slots = 5,
		named = true,
		source = "Smith",
		description = "Forged from a Deepstone Ingot carried up from the Labyrinth. The floor 1 Apex blade.",
	},

	-- ------------------------------------------------------------------ named weapons, later floors
	LucentNeedle = {
		id = "LucentNeedle",
		name = "Lucent Needle",
		category = "Rapier",
		rarity = "Epic",
		attack = 32,
		gaugeDamage = 0.7,
		durability = 190,
		weight = 2,
		trailWidth = 0.5,
		trailColor = "TrailPaleGold",
		reach = 5,
		floor = 4,
		slots = 3,
		named = true,
		source = "Drop",
		description = "Sera Valdane's line of rapiers begins here: pale gold, almost weightless.",
	},
	SovereignsOath = {
		id = "SovereignsOath",
		name = "Sovereign's Oath",
		category = "TwoHandedSword",
		rarity = "Apex",
		attack = 420,
		gaugeDamage = 1.6,
		durability = 400,
		weight = 8,
		trailWidth = 1.5,
		trailColor = "TrailCrimson",
		reach = 6,
		floor = 25,
		slots = 5,
		named = true,
		source = "LAB",
		description = "The Silver Sovereign's own blade, given to whoever lands the last hit on it.",
	},
	Nightfall = {
		id = "Nightfall",
		name = "Nightfall",
		category = "OneHandedSword",
		rarity = "Legendary",
		attack = 715,
		gaugeDamage = 1.1,
		durability = 360,
		weight = 3,
		trailWidth = 1.0,
		trailColor = "TrailCyanWhite",
		reach = 4.5,
		floor = 50,
		slots = 4,
		named = true,
		source = "LAB",
		description = "A black blade from the floor 50 Last Attack Bonus. It drinks the light around it.",
	},
	GlacierEdge = {
		id = "GlacierEdge",
		name = "Glacier Edge",
		category = "OneHandedSword",
		rarity = "Legendary",
		attack = 891,
		gaugeDamage = 1.1,
		durability = 360,
		weight = 3,
		trailWidth = 1.0,
		trailColor = "TrailCyanWhite",
		reach = 4.5,
		floor = 55,
		slots = 4,
		named = true,
		source = "Smith",
		description = "Smith-forged from a white wyrm's ingot on floor 55; pale as the thing it came from.",
	},

	-- ------------------------------------------------------------------ boss-held weapons (bosses.luau phases)
	-- Drawn by a boss on a WeaponSwap bar; the boss executes player Arts of this category with it. The
	-- rows give the hit sweep its reach and the trail its color. bossOnly rows are never player items.
	WarlordCurvedBlade = {
		id = "WarlordCurvedBlade",
		name = "Warlord's Curved Blade",
		category = "Katana",
		rarity = "Rare",
		attack = 26,
		gaugeDamage = 0.9,
		durability = 170,
		weight = 3,
		trailWidth = 0.8,
		trailColor = "TrailSilverBlue",
		reach = 5.5,
		floor = 1,
		slots = 2,
		bossOnly = true,
		description = "The curved blade Grolak draws on his last bar. It never leaves the chamber.",
	},
	WardensTwinSabres = {
		id = "WardensTwinSabres",
		name = "Warden's Twin Sabres",
		category = "TwinFang",
		rarity = "Rare",
		attack = 53,
		gaugeDamage = 1.0,
		durability = 300,
		weight = 4,
		trailWidth = 0.8,
		trailColor = "TrailCyanWhite",
		twinColor = "TrailViolet",
		reach = 4.5,
		floor = 10,
		slots = 2,
		bossOnly = true,
		description = "The paired sabres the Warden's Knight takes up when it sheds the shield. A foreshadowing.",
	},
	-- The Khagan's weapon is also the floor 7 Last Attack Bonus, so it is a real Legendary item.
	KhagansGreataxe = {
		id = "KhagansGreataxe",
		name = "Khagan's Greataxe",
		category = "TwoHandedSword",
		rarity = "Legendary",
		attack = 91,
		gaugeDamage = 1.7,
		durability = 360,
		weight = 8,
		trailWidth = 1.5,
		trailColor = "TrailCrimson",
		reach = 6.5,
		floor = 7,
		slots = 4,
		named = true,
		source = "LAB",
		description = "The Khagan of Hooves' great axe, swung like a two-hander; the floor 7 Last Attack Bonus.",
	},
}

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

Weapons.rows = rows

-- The weapon a new character of each category starts with.
Weapons.starters = {
	OneHandedSword = "TrialistSword",
	Rapier = "TrialistFoil",
	TwoHandedSword = "TrialistGreatsword",
	Katana = "TrialistKatana",
	Dagger = "TrialistKnife",
	Spear = "TrialistSpear",
	Axe = "TrialistHatchet",
	Mace = "TrialistCudgel",
	Shield = "TrialistBuckler",
	MartialArts = "TrialistWraps",
	TwinFang = "TrialistTwinBlades",
	AegisBlade = "TrialistVowBlade",
} :: { [Types.WeaponCategory]: string }

--- The weapon with this id, or nil when unknown.
function Weapons.byId(id: string): Weapon?
	return rows[id]
end

--- The category of a weapon id, or nil when unknown (CombatService checks the Art's weapon against it).
function Weapons.category(id: string): Types.WeaponCategory?
	local weapon = rows[id]
	if weapon == nil then
		return nil
	end
	return weapon.category
end

--- Every weapon, or every weapon of one category, sorted by floor then rarity then name.
function Weapons.list(category: Types.WeaponCategory?): { Weapon }
	local rarityIndex: { [string]: number } = {}
	for index, rarity in Weapons.rarityOrder do
		rarityIndex[rarity] = index
	end
	local list = {}
	for _, weapon in rows do
		if category == nil or weapon.category == category then
			table.insert(list, weapon)
		end
	end
	table.sort(list, function(a, b)
		if a.floor ~= b.floor then
			return a.floor < b.floor
		end
		if rarityIndex[a.rarity] ~= rarityIndex[b.rarity] then
			return rarityIndex[a.rarity] < rarityIndex[b.rarity]
		end
		return a.name < b.name
	end)
	return list
end

--- The named weapons (section 8), sorted by floor.
function Weapons.named(): { Weapon }
	local list = {}
	for _, weapon in Weapons.list() do
		if weapon.named then
			table.insert(list, weapon)
		end
	end
	return list
end

--- The starter weapon def of a category.
function Weapons.starter(category: Types.WeaponCategory): Weapon
	return rows[Weapons.starters[category]]
end

--- Attack a weapon of this category, rarity and floor is worth: base * rarity scale * floor tier.
function Weapons.attackFor(category: Types.WeaponCategory, rarity: Types.Rarity, floor: number): number
	local base = Weapons.baseAttack[category]
	local scale = Weapons.rarity[rarity].attackScale
	return math.floor(base * scale * Tiers.get(floor).attack + 0.5)
end

--- Whether a weapon can be used with an Art of the given category (Twin Fang needs the pair).
function Weapons.matchesArt(weaponId: string, artWeapon: Types.WeaponCategory): boolean
	return Weapons.category(weaponId) == artWeapon
end

return Weapons
