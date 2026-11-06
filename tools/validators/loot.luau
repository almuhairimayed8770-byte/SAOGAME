--!strict
--[[
	Validates src/shared/data/loot.luau: rarity weights sum to 100 with Legendary at 1, every
	table's fields and ranges, every material and consumable id in the item registry, every gear
	id in weapons.luau or armor.luau (never an Apex piece, never a boss-held weapon, never an item
	whose source is the LAB, a mini-dungeon or a smith; field-boss pieces only in FieldBoss tables),
	boss tables flagged, the Last Attack Bonus only on floor-boss tables, Apex pieces only on the
	field-boss table of a floor with an Apex set (and exactly that set's FieldBoss pieces), and every
	Last Attack Bonus a real Apex or Legendary item of its floor.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Apex" }
local KINDS = { "Material", "Consumable", "Gear", "LAB" }

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Check = ctx.load("src/shared/util/Check")
	local Loot = ctx.load("src/shared/data/loot")
	local Weapons = ctx.load("src/shared/data/weapons")
	local Armor = ctx.load("src/shared/data/armor")
	local Apex = ctx.load("src/shared/data/apex")

	local function problem(id: string, message: string)
		table.insert(problems, ("loot.%s: %s"):format(id, message))
	end

	-- Rarity weights
	local sum = 0
	for _, rarity in Loot.rarityOrder do
		sum += Loot.rarityWeights[rarity] or 0
	end
	if sum ~= 100 then
		problem("rarityWeights", ("sum to %d, not 100"):format(sum))
	end
	local expectedWeights = { Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1 }
	for rarity, weight in expectedWeights do
		if Loot.rarityWeights[rarity] ~= weight then
			problem("rarityWeights", ("%s should weigh %d (section 13)"):format(rarity, weight))
		end
	end
	if Loot.rules.mendShardChanceElite ~= 0.005 then
		problem("rules", "Mend Shards drop at 0.5% from Elites (section 13)")
	end

	-- Items
	local itemSchema = Check.interface({
		id = Check.string(48),
		name = Check.string(64),
		kind = Check.literal(table.unpack(KINDS)),
		rarity = Check.literal(table.unpack(RARITIES)),
		value = Check.number(0),
		stackMax = Check.integer(1, 999),
		description = Check.optional(Check.string(200)),
	})
	for key, item in Loot.items do
		local ok, message = itemSchema(item)
		if not ok then
			problem("items." .. tostring(key), message or "invalid item")
			continue
		end
		if item.id ~= key then
			problem("items." .. key, ("id '%s' does not match its key"):format(item.id))
		end
	end
	for _, required in { "Potion", "MendShard", "GateShard", "CorridorShard", "CleanseShard" } do
		if Loot.items[required] == nil then
			problem("items", ("section 6 consumable '%s' is missing"):format(required))
		end
	end

	-- Tables
	local dropSchema = Check.interface({
		item = Check.string(48),
		weight = Check.number(0),
		min = Check.optional(Check.integer(1, 99)),
		max = Check.optional(Check.integer(1, 99)),
	})
	local tableSchema = Check.interface({
		id = Check.string(48),
		crowns = Check.interface({ min = Check.integer(0), max = Check.integer(0) }),
		materials = Check.array(dropSchema, 16),
		materialRolls = Check.integer(0, 8),
		consumableChance = Check.number(0, 1),
		consumables = Check.array(dropSchema, 16),
		gearChance = Check.number(0, 1),
		gear = Check.map(
			Check.literal("Common", "Uncommon", "Rare", "Epic", "Legendary"),
			Check.array(Check.string(64), 64)
		),
		boss = Check.optional(Check.boolean),
		lab = Check.optional(Check.boolean),
		apexPieces = Check.optional(Check.array(Check.string(64), 6)),
	})

	-- Sources that are never random drops (section 7 / 8): those items come from one place.
	local NEVER_RANDOM = { LAB = true, MiniDungeon = true, Smith = true }

	local function checkDrops(label: string, drops: { any }, requireWeight: boolean)
		local total = 0
		for _, drop in drops do
			total += drop.weight
			if drop.item ~= Loot.NOTHING and Loot.items[drop.item] == nil then
				problem(label, ("item '%s' is not in Loot.items"):format(drop.item))
			end
			if drop.min ~= nil and drop.max ~= nil and drop.max < drop.min then
				problem(label, ("stack range %d..%d is inverted for %s"):format(drop.min, drop.max, drop.item))
			end
		end
		if requireWeight and total <= 0 then
			problem(label, "needs at least one weighted entry")
		end
	end

	for key, lootTable in Loot.tables do
		local ok, message = tableSchema(lootTable)
		if not ok then
			problem(tostring(key), message or "invalid table")
			continue
		end
		if lootTable.id ~= key then
			problem(key, ("id '%s' does not match its key"):format(lootTable.id))
		end
		if lootTable.crowns.max < lootTable.crowns.min then
			problem(key, "crowns max is under min")
		end
		checkDrops(key .. ".materials", lootTable.materials, lootTable.materialRolls > 0)
		checkDrops(key .. ".consumables", lootTable.consumables, lootTable.consumableChance > 0)
		local fieldBossFloor = tonumber(key:match("^FieldBoss%.F(%d+)$"))
		local floorBossFloor = tonumber(key:match("^Boss%.F(%d+)$"))
		for rarity, pool in lootTable.gear do
			local label = key .. ".gear." .. rarity
			for _, gearId in pool do
				local weapon = Weapons.rows[gearId]
				local armor = Armor.rows[gearId]
				local item = weapon or armor
				if item == nil then
					problem(label, ("'%s' is neither a weapon nor an armor piece"):format(gearId))
				else
					if item.rarity == "Apex" then
						problem(label, ("Apex piece '%s' is never a random drop"):format(gearId))
					elseif item.rarity ~= rarity then
						problem(label, ("'%s' is %s, not %s"):format(gearId, item.rarity, rarity))
					end
					if item.bossOnly then
						problem(label, ("'%s' is a boss-held weapon, never a drop"):format(gearId))
					end
					if item.source ~= nil and NEVER_RANDOM[item.source] then
						problem(
							label,
							("'%s' comes from its %s source, never a random drop"):format(gearId, item.source)
						)
					end
					if item.source == "FieldBoss" and fieldBossFloor == nil then
						problem(label, ("'%s' is a field boss piece; only FieldBoss tables drop it"):format(gearId))
					end
					if item.source == "FieldBoss" and fieldBossFloor ~= nil and item.floor ~= fieldBossFloor then
						problem(label, ("'%s' is a floor %d field boss piece"):format(gearId, item.floor))
					end
				end
			end
		end
		if (fieldBossFloor ~= nil or floorBossFloor ~= nil) and not lootTable.boss then
			problem(key, "boss tables must set boss = true")
		end
		if floorBossFloor ~= nil and lootTable.lab ~= true then
			problem(key, "floor boss tables carry the Last Attack Bonus (lab = true)")
		end
		if floorBossFloor == nil and lootTable.lab ~= nil then
			problem(key, "only floor boss tables carry the Last Attack Bonus")
		end
		if fieldBossFloor == nil and lootTable.apexPieces ~= nil then
			problem(key, "only field boss tables give Apex pieces")
		end
		if fieldBossFloor ~= nil then
			-- Section 9: the field boss drops an Apex piece at 15%; the pieces are the set's FieldBoss ones.
			local set = Apex.sets[fieldBossFloor]
			local expected: { string } = {}
			if set ~= nil then
				for _, piece in set.pieces do
					if piece.source == "FieldBoss" then
						table.insert(expected, piece.id)
					end
				end
			end
			local listed: { string } = lootTable.apexPieces or {}
			if set == nil and #listed > 0 then
				problem(key, ("lists Apex pieces but floor %d has no Apex set"):format(fieldBossFloor))
			end
			for _, id in listed do
				if table.find(expected, id) == nil then
					problem(
						key,
						("Apex piece '%s' is not a FieldBoss piece of the floor %d set"):format(id, fieldBossFloor)
					)
				end
			end
			for _, id in expected do
				if table.find(listed, id) == nil then
					problem(key, ("missing the floor %d set's field boss piece '%s'"):format(fieldBossFloor, id))
				end
			end
		end
	end

	-- Last Attack Bonus
	for floor, id in Loot.lastAttackBonus do
		local item = Weapons.rows[id] or Armor.rows[id]
		if item == nil then
			problem("lastAttackBonus." .. tostring(floor), ("'%s' is not a weapon or armor id"):format(id))
		elseif item.rarity ~= "Apex" and item.rarity ~= "Legendary" then
			problem("lastAttackBonus." .. tostring(floor), ("'%s' must be Apex or Legendary"):format(id))
		elseif item.floor ~= floor then
			problem("lastAttackBonus." .. tostring(floor), ("'%s' is a floor %d item"):format(id, item.floor))
		end
	end

	return problems
end

return validate
