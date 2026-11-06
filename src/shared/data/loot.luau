--!strict
--[[
	Loot (section 13). Drop tables keyed by the `lootTable` ids in enemies.luau and bosses.luau,
	the item registry for materials and consumables, the rarity weights (Common 60, Uncommon 25,
	Rare 10, Epic 4, Legendary 1 on Elites and bosses only), the Mend Shard rule (0.5% on Elites),
	the field-boss Apex piece (section 9: 15% per kill, the chance lives in apex.luau) and the Last
	Attack Bonus as data (deterministic: the floor's LAB item to whoever lands the killing hit on a
	floor boss; field bosses never give it).

	`Loot.roll` is pure: it takes a `Random` and returns what dropped, so LootService can seed it
	per request (section 7) and the Lune spec can check the distribution. Nothing here touches
	inventory; the server owns that.
]]

local Types = require(script.Parent.Parent.types)
local Rng = require(script.Parent.Parent.util.Rng)
local Apex = require(script.Parent.apex)
local Armor = require(script.Parent.armor)
local Weapons = require(script.Parent.weapons)

export type ItemKind = "Material" | "Consumable" | "Gear" | "LAB"

export type ItemDef = {
	id: string,
	name: string,
	kind: ItemKind,
	rarity: Types.Rarity,
	value: number, -- vendor price in Crowns
	stackMax: number,
	description: string?,
}

export type WeightedDrop = {
	item: string, -- item id, or NOTHING for an empty hand
	weight: number,
	min: number?, -- stack range (default 1)
	max: number?,
}

export type LootTable = {
	id: string,
	crowns: { min: number, max: number },
	materials: { WeightedDrop }, -- one weighted roll per materialRolls
	materialRolls: number,
	consumableChance: number, -- 0..1 chance of one consumable roll
	consumables: { WeightedDrop },
	gearChance: number, -- 0..1 chance of one gear roll
	gear: { [Types.Rarity]: { string } }, -- weapon or armor ids by rarity; an empty pool steps down
	boss: boolean?, -- bosses and field bosses: Legendary allowed
	lab: boolean?, -- floor bosses only: the Last Attack Bonus goes to the killing hit
	apexPieces: { string }?, -- field bosses only: the floor's Apex pieces this kill can give at Apex.rules.fieldBossDropChance
}

export type RollContext = {
	elite: boolean?,
	gilded: boolean?,
	bloodMoon: boolean?,
	lastAttack: boolean?, -- the roller landed the killing hit (bosses only)
	floor: number?, -- needed for the Last Attack Bonus lookup
}

export type Drop = { item: string, count: number, kind: ItemKind, rarity: Types.Rarity? }

export type RollResult = { crowns: number, drops: { Drop } }

local NOTHING = "Nothing"

local Loot = {}

Loot.NOTHING = NOTHING

-- Section 13 rarity weights for gear drops.
Loot.rarityWeights = {
	Common = 60,
	Uncommon = 25,
	Rare = 10,
	Epic = 4,
	Legendary = 1,
} :: { [Types.Rarity]: number }

Loot.rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" } :: { Types.Rarity }

Loot.rules = {
	legendaryOnlyOnElites = true, -- section 13: Legendary 1% on Elites and bosses only
	mendShardChanceElite = 0.005, -- Mend Shards drop at 0.5% from Elites
	mendShardPerMiniDungeonFirstClear = 1,
	gildedGuaranteedRare = true, -- a Gilded kill always rolls gear at Rare or better
	gildedMinimumRarity = "Rare" :: Types.Rarity,
	bloodMoonRateMultiplier = 3, -- drop chances triple under a Blood Moon
	lastAttackBonus = {
		deterministic = true, -- no roll: the killing hit always receives the floor's item
		rollOfHonorGold = true, -- the name goes in gold on the Roll of Honor
	},
	unclaimedShatterSeconds = 60, -- a Lucid drop nobody takes in 60 s shatters
	partySplit = "RoundRobin", -- the leader can set NeedGreed or FreeForAll
	shardCarryMax = 5, -- carrying more than five of any Shard is not allowed
	gateShardPriceFloor1 = 500,
	gateShardPricePerFloor = 300,
	vendorInflationPerClearedFloor = 0.02,
	marketListingFee = 0.1,
}

-- The Last Attack Bonus item per floor (always an Apex piece or a Legendary). Floors whose item has
-- no row yet are listed in Bosses.pendingLab instead.
Loot.lastAttackBonus = {
	[1] = "MantleOfLastLight",
	[7] = "KhagansGreataxe",
	[25] = "SovereignsOath",
	[50] = "Nightfall",
} :: { [number]: string }

-- ---------------------------------------------------------------------------------------------
-- Items: materials and consumables. Gear ids live in weapons.luau and armor.luau.
-- ---------------------------------------------------------------------------------------------

local function material(id: string, name: string, rarity: Types.Rarity, value: number, description: string?): ItemDef
	return {
		id = id,
		name = name,
		kind = "Material",
		rarity = rarity,
		value = value,
		stackMax = 99,
		description = description,
	}
end

local function consumable(
	id: string,
	name: string,
	rarity: Types.Rarity,
	value: number,
	stackMax: number,
	description: string?
): ItemDef
	return {
		id = id,
		name = name,
		kind = "Consumable",
		rarity = rarity,
		value = value,
		stackMax = stackMax,
		description = description,
	}
end

Loot.items = {
	-- consumables (section 6 quick-slot ring)
	Potion = consumable("Potion", "Potion", "Common", 40, 20, "Heals 30% over 10 s. Useless in a burst."),
	MendShard = consumable("MendShard", "Mend Shard", "Epic", 0, 5, "Instant full heal. Never sold."),
	GateShard = consumable(
		"GateShard",
		"Gate Shard",
		"Rare",
		500,
		5,
		"Teleport to any cleared town; blocked in boss chambers and Warded zones."
	),
	CorridorShard = consumable(
		"CorridorShard",
		"Corridor Shard",
		"Rare",
		0,
		5,
		"Opens a party portal to a town for 20 s."
	),
	CleanseShard = consumable("CleanseShard", "Cleanse Shard", "Uncommon", 120, 5, "Clears every status."),
	Antidote = consumable("Antidote", "Haven Antidote", "Uncommon", 60, 10, "Clears poison; the Haven recipe."),

	-- floor 1 materials
	BoarHide = material("BoarHide", "Boar Hide", "Common", 3),
	BoarTusk = material("BoarTusk", "Boar Tusk", "Uncommon", 8),
	WolfFang = material("WolfFang", "Wolf Fang", "Common", 4),
	WolfPelt = material("WolfPelt", "Wolf Pelt", "Uncommon", 9),
	KoboldScale = material("KoboldScale", "Kobold Scale", "Common", 3),
	KoboldTooth = material("KoboldTooth", "Kobold Tooth", "Common", 2),
	IngotOre = material("IngotOre", "Ingot Ore", "Uncommon", 12, "Smelts to a plain ingot at any smith."),
	NepentheResin = material("NepentheResin", "Nepenthe Resin", "Uncommon", 10, "Acid sap; the antidote base."),
	DeepstoneIngot = material(
		"DeepstoneIngot",
		"Deepstone Ingot",
		"Apex",
		0,
		"Mined on the Labyrinth's deepest level. The Apex recipe ingot."
	),
	WarboarCrown = material(
		"WarboarCrown",
		"Warboar Crown",
		"Epic",
		400,
		"Tusk's crown of bone; a trophy and a tailoring core."
	),

	-- floors 2 to 10 materials
	WaspStinger = material("WaspStinger", "Wasp Stinger", "Common", 4),
	LeechGland = material("LeechGland", "Leech Gland", "Uncommon", 11, "Paralytic. Handle with gloves."),
	TrollHide = material("TrollHide", "Troll Hide", "Uncommon", 14),
	ReedBundle = material("ReedBundle", "Reed Bundle", "Common", 2),
	EmberFur = material("EmberFur", "Ember Fur", "Common", 5),
	AshBark = material("AshBark", "Ash Bark", "Common", 4),
	BeetleShell = material("BeetleShell", "Beetle Shell", "Uncommon", 9),
	MothDust = material("MothDust", "Moth Dust", "Uncommon", 10),
	HarpyFeather = material("HarpyFeather", "Harpy Feather", "Common", 5),
	CrabShell = material("CrabShell", "Crab Shell", "Uncommon", 10),
	LizardmanScale = material("LizardmanScale", "Lizardman Scale", "Common", 6),
	BrineGland = material("BrineGland", "Brine Gland", "Uncommon", 13),
	RamHorn = material("RamHorn", "Ram Horn", "Common", 7),
	WardCore = material("WardCore", "Ward Core", "Rare", 30, "The light inside a scarecrow construct."),
	BanditBadge = material("BanditBadge", "Bandit Badge", "Uncommon", 15),
	HawkFeather = material("HawkFeather", "Hawk Feather", "Common", 6),
	SpiderSilk = material("SpiderSilk", "Spider Silk", "Uncommon", 12),
	OgreTooth = material("OgreTooth", "Ogre Tooth", "Uncommon", 16),
	FungalCap = material("FungalCap", "Fungal Cap", "Common", 5),
	BatWing = material("BatWing", "Bat Wing", "Common", 3),
	LionMane = material("LionMane", "Lion Mane", "Uncommon", 18),
	MinotaurHorn = material("MinotaurHorn", "Minotaur Horn", "Rare", 35),
	VultureFeather = material("VultureFeather", "Vulture Feather", "Common", 6),
	BeetleCarapace = material("BeetleCarapace", "Beetle Carapace", "Rare", 32),
	FrostFur = material("FrostFur", "Frost Fur", "Common", 8),
	IceHeart = material("IceHeart", "Ice Heart", "Rare", 40, "A golem's core; cold to hold."),
	YetiHide = material("YetiHide", "Yeti Hide", "Uncommon", 20),
	RimeEssence = material("RimeEssence", "Rime Essence", "Uncommon", 22),
	ShadeEssence = material("ShadeEssence", "Shade Essence", "Uncommon", 24),
	DryadBark = material("DryadBark", "Dryad Bark", "Uncommon", 22),
	OwlbearClaw = material("OwlbearClaw", "Owlbear Claw", "Uncommon", 25),
	MantisBlade = material("MantisBlade", "Mantis Blade", "Uncommon", 23),
	KnightPlate = material("KnightPlate", "Citadel Plate", "Rare", 50),
	WardenCog = material("WardenCog", "Warden Cog", "Rare", 45),
	ClockworkSpring = material("ClockworkSpring", "Clockwork Spring", "Uncommon", 28),
	CaptainsSeal = material("CaptainsSeal", "Captain's Seal", "Epic", 120),
	BossCore = material(
		"BossCore",
		"Warlord Core",
		"Legendary",
		600,
		"What is left of a floor boss. One per raid member."
	),
} :: { [string]: ItemDef }

-- ---------------------------------------------------------------------------------------------
-- Drop tables
-- ---------------------------------------------------------------------------------------------

local floor1Gear = {
	Common = { "TrialistSword", "TrialistHatchet", "TrialistSpear", "TrialistTunic", "TrialistBoots" },
	Uncommon = { "KoboldCleaver", "BoarhideVest", "BoarhideBoots", "WandererCloak" },
	Rare = { "TemperedEdge", "KoboldScaleCuirass", "KoboldScaleGreaves", "SentinelHelm" },
	Epic = {},
	Legendary = {},
}

-- Tusk, Warboar King: the floor 1 pools plus the spear made from his tusk (source FieldBoss).
local fieldBoss1Gear = {
	Common = floor1Gear.Common,
	Uncommon = floor1Gear.Uncommon,
	Rare = { "TemperedEdge", "KoboldScaleCuirass", "KoboldScaleGreaves", "SentinelHelm", "WarboarTuskSpear" },
	Epic = {},
	Legendary = {},
}

-- Later floors drop their vendor-grade gear until their named rows are authored (Phase 5+).
local laterGear = {
	Common = {
		"TrialistSword",
		"TrialistFoil",
		"TrialistGreatsword",
		"TrialistKatana",
		"TrialistKnife",
		"TrialistSpear",
	},
	Uncommon = { "KoboldCleaver", "WandererCloak" },
	Rare = { "TemperedEdge", "KoboldScaleCuirass" },
	Epic = {},
	Legendary = {},
}

local floor4Gear = {
	Common = laterGear.Common,
	Uncommon = laterGear.Uncommon,
	Rare = laterGear.Rare,
	Epic = { "LucentNeedle" },
	Legendary = {},
}

local potionOnly = { { item = "Potion", weight = 100 } }
local potionAndCleanse = { { item = "Potion", weight = 85 }, { item = "CleanseShard", weight = 15 } }
local potionAndAntidote =
	{ { item = "Potion", weight = 70 }, { item = "Antidote", weight = 20 }, { item = "CleanseShard", weight = 10 } }

local function mobTable(
	id: string,
	crowns: { min: number, max: number },
	materials: { WeightedDrop },
	consumables: { WeightedDrop },
	gear: { [Types.Rarity]: { string } },
	gearChance: number
): LootTable
	return {
		id = id,
		crowns = crowns,
		materials = materials,
		materialRolls = 1,
		consumableChance = 0.08,
		consumables = consumables,
		gearChance = gearChance,
		gear = gear,
	}
end

local function bossTable(
	id: string,
	crowns: { min: number, max: number },
	materials: { WeightedDrop },
	gear: { [Types.Rarity]: { string } },
	lab: boolean,
	apexPieces: { string }?
): LootTable
	return {
		id = id,
		crowns = crowns,
		materials = materials,
		materialRolls = 2,
		consumableChance = 1,
		consumables = {
			{ item = "Potion", weight = 60, min = 2, max = 3 },
			{ item = "CleanseShard", weight = 30 },
			{ item = "CorridorShard", weight = 10 },
		},
		gearChance = 1,
		gear = gear,
		boss = true,
		lab = if lab then true else nil,
		apexPieces = apexPieces,
	}
end

-- A field boss (section 9): boss-grade rolls, an Apex piece of its floor at 15%, no Last Attack Bonus.
local function fieldBossTable(
	id: string,
	crowns: { min: number, max: number },
	materials: { WeightedDrop },
	gear: { [Types.Rarity]: { string } },
	apexPieces: { string }?
): LootTable
	return bossTable(id, crowns, materials, gear, false, apexPieces)
end

-- A floor boss: boss-grade rolls and the floor's Last Attack Bonus to the killing hit.
local function floorBossTable(
	id: string,
	crowns: { min: number, max: number },
	materials: { WeightedDrop },
	gear: { [Types.Rarity]: { string } }
): LootTable
	return bossTable(id, crowns, materials, gear, true, nil)
end

Loot.tables = {
	-- ------------------------------------------------------------------ floor 1
	["F1.Boar"] = mobTable("F1.Boar", { min = 4, max = 9 }, {
		{ item = "BoarHide", weight = 60, min = 1, max = 2 },
		{ item = "BoarTusk", weight = 15 },
		{ item = NOTHING, weight = 25 },
	}, potionOnly, floor1Gear, 0.06),
	["F1.Wolf"] = mobTable("F1.Wolf", { min = 5, max = 11 }, {
		{ item = "WolfFang", weight = 55, min = 1, max = 2 },
		{ item = "WolfPelt", weight = 20 },
		{ item = NOTHING, weight = 25 },
	}, potionOnly, floor1Gear, 0.08),
	["F1.Kobold"] = mobTable("F1.Kobold", { min = 6, max = 14 }, {
		{ item = "KoboldScale", weight = 45, min = 1, max = 3 },
		{ item = "KoboldTooth", weight = 25 },
		{ item = "IngotOre", weight = 10 },
		{ item = NOTHING, weight = 20 },
	}, potionAndCleanse, floor1Gear, 0.1),
	["F1.Bloom"] = mobTable("F1.Bloom", { min = 5, max = 12 }, {
		{ item = "NepentheResin", weight = 50, min = 1, max = 2 },
		{ item = NOTHING, weight = 50 },
	}, potionAndAntidote, floor1Gear, 0.08),

	-- ------------------------------------------------------------------ floor 2
	["F2.Wasp"] = mobTable(
		"F2.Wasp",
		{ min = 4, max = 8 },
		{ { item = "WaspStinger", weight = 60 }, { item = NOTHING, weight = 40 } },
		potionOnly,
		laterGear,
		0.04
	),
	["F2.Leech"] = mobTable(
		"F2.Leech",
		{ min = 6, max = 12 },
		{ { item = "LeechGland", weight = 45 }, { item = NOTHING, weight = 55 } },
		potionAndCleanse,
		laterGear,
		0.07
	),
	["F2.Troll"] = mobTable("F2.Troll", { min = 12, max = 24 }, {
		{ item = "TrollHide", weight = 55, min = 1, max = 2 },
		{ item = "IngotOre", weight = 15 },
		{ item = NOTHING, weight = 30 },
	}, potionAndCleanse, laterGear, 0.12),
	["F2.Lurker"] = mobTable("F2.Lurker", { min = 8, max = 16 }, {
		{ item = "ReedBundle", weight = 50, min = 1, max = 3 },
		{ item = "IngotOre", weight = 10 },
		{ item = NOTHING, weight = 40 },
	}, potionAndCleanse, laterGear, 0.09),

	-- ------------------------------------------------------------------ floor 3
	["F3.Fox"] = mobTable(
		"F3.Fox",
		{ min = 8, max = 15 },
		{ { item = "EmberFur", weight = 60, min = 1, max = 2 }, { item = NOTHING, weight = 40 } },
		potionOnly,
		laterGear,
		0.08
	),
	["F3.Sapling"] = mobTable(
		"F3.Sapling",
		{ min = 10, max = 18 },
		{ { item = "AshBark", weight = 65, min = 1, max = 3 }, { item = NOTHING, weight = 35 } },
		potionAndAntidote,
		laterGear,
		0.08
	),
	["F3.Beetle"] = mobTable(
		"F3.Beetle",
		{ min = 9, max = 17 },
		{ { item = "BeetleShell", weight = 50 }, { item = "IngotOre", weight = 10 }, { item = NOTHING, weight = 40 } },
		potionOnly,
		laterGear,
		0.08
	),
	["F3.Moth"] = mobTable(
		"F3.Moth",
		{ min = 5, max = 10 },
		{ { item = "MothDust", weight = 55 }, { item = NOTHING, weight = 45 } },
		potionAndCleanse,
		laterGear,
		0.04
	),

	-- ------------------------------------------------------------------ floor 4
	["F4.Harpy"] = mobTable(
		"F4.Harpy",
		{ min = 12, max = 22 },
		{ { item = "HarpyFeather", weight = 60, min = 1, max = 2 }, { item = NOTHING, weight = 40 } },
		potionOnly,
		floor4Gear,
		0.08
	),
	["F4.Crab"] = mobTable(
		"F4.Crab",
		{ min = 14, max = 24 },
		{ { item = "CrabShell", weight = 55 }, { item = "IngotOre", weight = 15 }, { item = NOTHING, weight = 30 } },
		potionOnly,
		floor4Gear,
		0.09
	),
	["F4.Lizardman"] = mobTable(
		"F4.Lizardman",
		{ min = 15, max = 26 },
		{ { item = "LizardmanScale", weight = 55, min = 1, max = 2 }, { item = NOTHING, weight = 45 } },
		potionAndCleanse,
		floor4Gear,
		0.1
	),
	["F4.Serpent"] = mobTable(
		"F4.Serpent",
		{ min = 16, max = 28 },
		{ { item = "BrineGland", weight = 45 }, { item = NOTHING, weight = 55 } },
		potionAndAntidote,
		floor4Gear,
		0.1
	),

	-- ------------------------------------------------------------------ floor 5
	["F5.Ram"] = mobTable(
		"F5.Ram",
		{ min = 18, max = 30 },
		{ { item = "RamHorn", weight = 55 }, { item = NOTHING, weight = 45 } },
		potionOnly,
		laterGear,
		0.08
	),
	["F5.Scarecrow"] = mobTable(
		"F5.Scarecrow",
		{ min = 24, max = 40 },
		{ { item = "WardCore", weight = 30 }, { item = "IngotOre", weight = 20 }, { item = NOTHING, weight = 50 } },
		potionAndCleanse,
		laterGear,
		0.12
	),
	["F5.Bandit"] = mobTable(
		"F5.Bandit",
		{ min = 30, max = 55 },
		{ { item = "BanditBadge", weight = 40 }, { item = "IngotOre", weight = 15 }, { item = NOTHING, weight = 45 } },
		potionAndCleanse,
		laterGear,
		0.15
	),
	["F5.Hawk"] = mobTable(
		"F5.Hawk",
		{ min = 10, max = 18 },
		{ { item = "HawkFeather", weight = 60 }, { item = NOTHING, weight = 40 } },
		potionOnly,
		laterGear,
		0.05
	),

	-- ------------------------------------------------------------------ floor 6
	["F6.Spider"] = mobTable(
		"F6.Spider",
		{ min = 22, max = 36 },
		{ { item = "SpiderSilk", weight = 55, min = 1, max = 2 }, { item = NOTHING, weight = 45 } },
		potionAndCleanse,
		laterGear,
		0.09
	),
	["F6.Ogre"] = mobTable(
		"F6.Ogre",
		{ min = 34, max = 58 },
		{ { item = "OgreTooth", weight = 50 }, { item = "IngotOre", weight = 15 }, { item = NOTHING, weight = 35 } },
		potionAndCleanse,
		laterGear,
		0.13
	),
	["F6.Shambler"] = mobTable(
		"F6.Shambler",
		{ min = 24, max = 40 },
		{ { item = "FungalCap", weight = 60, min = 1, max = 3 }, { item = NOTHING, weight = 40 } },
		potionAndAntidote,
		laterGear,
		0.09
	),
	["F6.Bat"] = mobTable(
		"F6.Bat",
		{ min = 12, max = 20 },
		{ { item = "BatWing", weight = 60 }, { item = NOTHING, weight = 40 } },
		potionOnly,
		laterGear,
		0.04
	),

	-- ------------------------------------------------------------------ floor 7
	["F7.Lion"] = mobTable(
		"F7.Lion",
		{ min = 36, max = 60 },
		{ { item = "LionMane", weight = 45 }, { item = NOTHING, weight = 55 } },
		potionOnly,
		laterGear,
		0.1
	),
	["F7.Minotaur"] = mobTable(
		"F7.Minotaur",
		{ min = 50, max = 80 },
		{ { item = "MinotaurHorn", weight = 30 }, { item = "IngotOre", weight = 20 }, { item = NOTHING, weight = 50 } },
		potionAndCleanse,
		laterGear,
		0.14
	),
	["F7.Vulture"] = mobTable(
		"F7.Vulture",
		{ min = 16, max = 26 },
		{ { item = "VultureFeather", weight = 60 }, { item = NOTHING, weight = 40 } },
		potionOnly,
		laterGear,
		0.05
	),
	["F7.Beetle"] = mobTable(
		"F7.Beetle",
		{ min = 44, max = 70 },
		{ { item = "BeetleCarapace", weight = 40 }, { item = NOTHING, weight = 60 } },
		potionOnly,
		laterGear,
		0.12
	),

	-- ------------------------------------------------------------------ floor 8
	["F8.Wolf"] = mobTable(
		"F8.Wolf",
		{ min = 40, max = 66 },
		{ { item = "FrostFur", weight = 60, min = 1, max = 2 }, { item = NOTHING, weight = 40 } },
		potionOnly,
		laterGear,
		0.09
	),
	["F8.Golem"] = mobTable(
		"F8.Golem",
		{ min = 60, max = 95 },
		{ { item = "IceHeart", weight = 30 }, { item = "IngotOre", weight = 25 }, { item = NOTHING, weight = 45 } },
		potionAndCleanse,
		laterGear,
		0.13
	),
	["F8.Yeti"] = mobTable(
		"F8.Yeti",
		{ min = 64, max = 100 },
		{ { item = "YetiHide", weight = 50 }, { item = NOTHING, weight = 50 } },
		potionAndCleanse,
		laterGear,
		0.13
	),
	["F8.Wisp"] = mobTable(
		"F8.Wisp",
		{ min = 44, max = 70 },
		{ { item = "RimeEssence", weight = 45 }, { item = NOTHING, weight = 55 } },
		potionAndCleanse,
		laterGear,
		0.1
	),

	-- ------------------------------------------------------------------ floor 9
	["F9.Hound"] = mobTable(
		"F9.Hound",
		{ min = 60, max = 95 },
		{ { item = "ShadeEssence", weight = 45 }, { item = NOTHING, weight = 55 } },
		potionAndCleanse,
		laterGear,
		0.1
	),
	["F9.Dryad"] = mobTable(
		"F9.Dryad",
		{ min = 80, max = 130 },
		{ { item = "DryadBark", weight = 50 }, { item = "IngotOre", weight = 15 }, { item = NOTHING, weight = 35 } },
		potionAndCleanse,
		laterGear,
		0.15
	),
	["F9.Owlbear"] = mobTable(
		"F9.Owlbear",
		{ min = 84, max = 135 },
		{ { item = "OwlbearClaw", weight = 50 }, { item = NOTHING, weight = 50 } },
		potionOnly,
		laterGear,
		0.13
	),
	["F9.Mantis"] = mobTable(
		"F9.Mantis",
		{ min = 64, max = 100 },
		{ { item = "MantisBlade", weight = 45 }, { item = NOTHING, weight = 55 } },
		potionAndCleanse,
		laterGear,
		0.1
	),

	-- ------------------------------------------------------------------ floor 10
	["F10.Knight"] = mobTable(
		"F10.Knight",
		{ min = 110, max = 180 },
		{ { item = "KnightPlate", weight = 35 }, { item = "IngotOre", weight = 25 }, { item = NOTHING, weight = 40 } },
		potionAndCleanse,
		laterGear,
		0.16
	),
	["F10.Hound"] = mobTable(
		"F10.Hound",
		{ min = 70, max = 110 },
		{ { item = "WardenCog", weight = 35 }, { item = NOTHING, weight = 65 } },
		potionOnly,
		laterGear,
		0.1
	),
	["F10.Archer"] = mobTable(
		"F10.Archer",
		{ min = 80, max = 130 },
		{ { item = "ClockworkSpring", weight = 50 }, { item = NOTHING, weight = 50 } },
		potionAndCleanse,
		laterGear,
		0.12
	),
	["F10.Captain"] = mobTable("F10.Captain", { min = 160, max = 260 }, {
		{ item = "CaptainsSeal", weight = 40 },
		{ item = "KnightPlate", weight = 20 },
		{ item = NOTHING, weight = 40 },
	}, potionAndCleanse, laterGear, 0.2),

	-- ------------------------------------------------------------------ field bosses (section 9)
	["FieldBoss.F1"] = fieldBossTable(
		"FieldBoss.F1",
		{ min = 120, max = 200 },
		{ { item = "WarboarCrown", weight = 40 }, { item = "BoarTusk", weight = 60, min = 2, max = 4 } },
		fieldBoss1Gear,
		{ "WarboarHideJerkin", "WarboarHideGreaves" }
	),
	["FieldBoss.F2"] = fieldBossTable("FieldBoss.F2", { min = 220, max = 360 }, {
		{ item = "WaspStinger", weight = 70, min = 3, max = 6 },
		{ item = "IngotOre", weight = 30, min = 1, max = 2 },
	}, laterGear),
	["FieldBoss.F3"] = fieldBossTable(
		"FieldBoss.F3",
		{ min = 320, max = 500 },
		{ { item = "AshBark", weight = 70, min = 3, max = 6 }, { item = "IngotOre", weight = 30, min = 1, max = 2 } },
		laterGear
	),
	["FieldBoss.F4"] = fieldBossTable(
		"FieldBoss.F4",
		{ min = 420, max = 650 },
		{ { item = "BrineGland", weight = 70, min = 2, max = 4 }, { item = "IngotOre", weight = 30, min = 1, max = 2 } },
		floor4Gear
	),
	["FieldBoss.F5"] = fieldBossTable(
		"FieldBoss.F5",
		{ min = 550, max = 850 },
		{ { item = "RamHorn", weight = 60, min = 2, max = 4 }, { item = "IngotOre", weight = 40, min = 2, max = 3 } },
		laterGear
	),
	["FieldBoss.F6"] = fieldBossTable(
		"FieldBoss.F6",
		{ min = 700, max = 1100 },
		{ { item = "SpiderSilk", weight = 70, min = 3, max = 6 }, { item = "IngotOre", weight = 30, min = 1, max = 3 } },
		laterGear
	),
	["FieldBoss.F7"] = fieldBossTable(
		"FieldBoss.F7",
		{ min = 900, max = 1400 },
		{ { item = "LionMane", weight = 70, min = 2, max = 3 }, { item = "IngotOre", weight = 30, min = 1, max = 3 } },
		laterGear
	),
	["FieldBoss.F8"] = fieldBossTable(
		"FieldBoss.F8",
		{ min = 1100, max = 1700 },
		{ { item = "IceHeart", weight = 50, min = 1, max = 2 }, { item = "YetiHide", weight = 50, min = 2, max = 4 } },
		laterGear
	),
	["FieldBoss.F9"] = fieldBossTable("FieldBoss.F9", { min = 1300, max = 2000 }, {
		{ item = "ShadeEssence", weight = 60, min = 2, max = 4 },
		{ item = "DryadBark", weight = 40, min = 2, max = 4 },
	}, laterGear),
	["FieldBoss.F10"] = fieldBossTable(
		"FieldBoss.F10",
		{ min = 1600, max = 2500 },
		{ { item = "CaptainsSeal", weight = 50 }, { item = "KnightPlate", weight = 50, min = 2, max = 3 } },
		laterGear
	),

	-- ------------------------------------------------------------------ floor bosses (section 9)
	["Boss.F1"] = floorBossTable(
		"Boss.F1",
		{ min = 400, max = 600 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 3, max = 5 } },
		floor1Gear
	),
	["Boss.F2"] = floorBossTable(
		"Boss.F2",
		{ min = 700, max = 1000 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 3, max = 5 } },
		laterGear
	),
	["Boss.F3"] = floorBossTable(
		"Boss.F3",
		{ min = 1000, max = 1500 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 3, max = 6 } },
		laterGear
	),
	["Boss.F4"] = floorBossTable(
		"Boss.F4",
		{ min = 1400, max = 2000 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 3, max = 6 } },
		floor4Gear
	),
	["Boss.F5"] = floorBossTable(
		"Boss.F5",
		{ min = 1800, max = 2600 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 4, max = 6 } },
		laterGear
	),
	["Boss.F6"] = floorBossTable(
		"Boss.F6",
		{ min = 2300, max = 3300 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 4, max = 7 } },
		laterGear
	),
	["Boss.F7"] = floorBossTable(
		"Boss.F7",
		{ min = 2900, max = 4000 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 4, max = 7 } },
		laterGear
	),
	["Boss.F8"] = floorBossTable(
		"Boss.F8",
		{ min = 3500, max = 4800 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 4, max = 8 } },
		laterGear
	),
	["Boss.F9"] = floorBossTable(
		"Boss.F9",
		{ min = 4200, max = 5700 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 5, max = 8 } },
		laterGear
	),
	["Boss.F10"] = floorBossTable(
		"Boss.F10",
		{ min = 5000, max = 7000 },
		{ { item = "BossCore", weight = 50 }, { item = "IngotOre", weight = 50, min = 5, max = 9 } },
		laterGear
	),
} :: { [string]: LootTable }

-- ---------------------------------------------------------------------------------------------
-- Rolling (pure)
-- ---------------------------------------------------------------------------------------------

local function rarityIndex(rarity: Types.Rarity): number
	return table.find(Loot.rarityOrder, rarity) or 1
end

local function rateMultiplier(context: RollContext?): number
	if context ~= nil and context.bloodMoon then
		return Loot.rules.bloodMoonRateMultiplier
	end
	return 1
end

local function pickWeighted(random: Random, entries: { WeightedDrop }): WeightedDrop?
	if #entries == 0 then
		return nil
	end
	local weighted: { Rng.Weighted<WeightedDrop> } = {}
	local total = 0
	for _, entry in entries do
		if entry.weight > 0 then
			table.insert(weighted, { value = entry, weight = entry.weight })
			total += entry.weight
		end
	end
	if total <= 0 then
		return nil
	end
	return Rng.weighted(random, weighted)
end

-- The rarity of a weapon or armor id (the Last Attack Bonus is an Apex piece or a Legendary), or nil.
local function gearRarity(id: string): Types.Rarity?
	local weapon = Weapons.byId(id)
	if weapon ~= nil then
		return weapon.rarity
	end
	local armor = Armor.byId(id)
	if armor ~= nil then
		return armor.rarity
	end
	return nil
end

local function stackCount(random: Random, entry: WeightedDrop): number
	local min = entry.min or 1
	local max = entry.max or min
	if max <= min then
		return min
	end
	return random:NextInteger(min, max)
end

--- The drop table with this id, or nil when unknown.
function Loot.table(id: string): LootTable?
	return Loot.tables[id]
end

--- The item with this id (materials and consumables only), or nil.
function Loot.item(id: string): ItemDef?
	return Loot.items[id]
end

--- Rolls a gear rarity by the section 13 weights; Legendary is only in the pool when `allowLegendary`.
function Loot.rollRarity(random: Random, allowLegendary: boolean): Types.Rarity
	local entries: { Rng.Weighted<Types.Rarity> } = {}
	for _, rarity in Loot.rarityOrder do
		local weight = Loot.rarityWeights[rarity]
		if rarity == "Legendary" and not allowLegendary and Loot.rules.legendaryOnlyOnElites then
			weight = 0
		end
		table.insert(entries, { value = rarity, weight = weight })
	end
	return Rng.weighted(random, entries)
end

--- Picks a gear id from the table's pool at `rarity`, stepping down to lower rarities when a pool is empty.
function Loot.pickGear(random: Random, lootTable: LootTable, rarity: Types.Rarity): (string?, Types.Rarity?)
	for index = rarityIndex(rarity), 1, -1 do
		local candidate = Loot.rarityOrder[index]
		local pool = lootTable.gear[candidate]
		if pool ~= nil and #pool > 0 then
			return pool[random:NextInteger(1, #pool)], candidate
		end
	end
	return nil, nil
end

--- Rolls one kill's drops from a table. Pure: the same Random and context give the same result.
function Loot.roll(random: Random, tableId: string, context: RollContext?): RollResult
	local lootTable = Loot.tables[tableId]
	if lootTable == nil then
		error(("Loot.roll: unknown loot table '%s'"):format(tostring(tableId)))
	end
	local ctx: RollContext = context or {}
	local multiplier = rateMultiplier(ctx)
	local result: RollResult = { crowns = 0, drops = {} }

	-- Crowns
	local crowns = lootTable.crowns
	result.crowns = if crowns.max > crowns.min then random:NextInteger(crowns.min, crowns.max) else crowns.min

	-- Materials
	for _ = 1, lootTable.materialRolls do
		local entry = pickWeighted(random, lootTable.materials)
		if entry ~= nil and entry.item ~= NOTHING then
			table.insert(result.drops, { item = entry.item, count = stackCount(random, entry), kind = "Material" })
		end
	end

	-- Consumables
	if Rng.chance(random, math.min(1, lootTable.consumableChance * multiplier)) then
		local entry = pickWeighted(random, lootTable.consumables)
		if entry ~= nil and entry.item ~= NOTHING then
			table.insert(result.drops, { item = entry.item, count = stackCount(random, entry), kind = "Consumable" })
		end
	end

	-- Gear
	local elite = ctx.elite == true or lootTable.boss == true
	local gearChance = if ctx.gilded and Loot.rules.gildedGuaranteedRare then 1 else lootTable.gearChance * multiplier
	if Rng.chance(random, math.min(1, gearChance)) then
		local rarity = Loot.rollRarity(random, elite)
		if ctx.gilded and rarityIndex(rarity) < rarityIndex(Loot.rules.gildedMinimumRarity) then
			rarity = Loot.rules.gildedMinimumRarity
		end
		local gearId, actualRarity = Loot.pickGear(random, lootTable, rarity)
		if gearId ~= nil then
			table.insert(result.drops, { item = gearId, count = 1, kind = "Gear", rarity = actualRarity })
		end
	end

	-- Mend Shards: Elites only, 0.5%
	if ctx.elite and Rng.chance(random, math.min(1, Loot.rules.mendShardChanceElite * multiplier)) then
		table.insert(result.drops, { item = "MendShard", count = 1, kind = "Consumable", rarity = "Epic" })
	end

	-- Field boss Apex piece (section 9: one of the floor's set pieces at 15% per kill)
	local apexPieces = lootTable.apexPieces
	if apexPieces ~= nil and #apexPieces > 0 then
		if Rng.chance(random, math.min(1, Apex.rules.fieldBossDropChance * multiplier)) then
			local pieceId = apexPieces[random:NextInteger(1, #apexPieces)]
			table.insert(result.drops, { item = pieceId, count = 1, kind = "Gear", rarity = "Apex" })
		end
	end

	-- Last Attack Bonus: deterministic, floor bosses only
	if lootTable.lab and ctx.lastAttack and ctx.floor ~= nil then
		local lab = Loot.lastAttackBonus[ctx.floor]
		if lab ~= nil then
			table.insert(result.drops, { item = lab, count = 1, kind = "LAB", rarity = gearRarity(lab) })
		end
	end

	return result
end

--- Every table id, sorted.
function Loot.tableIds(): { string }
	local ids = {}
	for id in Loot.tables do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return Loot
