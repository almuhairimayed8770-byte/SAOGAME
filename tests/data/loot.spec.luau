--!strict
local Loot = Harness.load("src/shared/data/loot")
local Enemies = Harness.load("src/shared/data/enemies")
local Bosses = Harness.load("src/shared/data/bosses")
local Weapons = Harness.load("src/shared/data/weapons")
local Armor = Harness.load("src/shared/data/armor")
local Apex = Harness.load("src/shared/data/apex")

local SAMPLES = 20000
local TOLERANCE = 0.015

local function countRarities(seed, allowLegendary)
	local random = Random.new(seed)
	local counts = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0 }
	for _ = 1, SAMPLES do
		local rarity = Loot.rollRarity(random, allowLegendary)
		counts[rarity] += 1
	end
	return counts
end

local function itemExists(id)
	return Loot.items[id] ~= nil or Weapons.rows[id] ~= nil or Armor.rows[id] ~= nil
end

describe("loot data", function()
	it("uses the section 13 rarity weights", function()
		expect(Loot.rarityWeights).toEqual({ Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1 })
		expect(Loot.rules.mendShardChanceElite).toBe(0.005)
		expect(Loot.rules.bloodMoonRateMultiplier).toBe(3)
		expect(Loot.rules.lastAttackBonus.deterministic).toBe(true)
		expect(Loot.lastAttackBonus[1]).toBe("MantleOfLastLight")
	end)

	it("20,000 Elite rarity rolls land within 1.5% of 60/25/10/4/1", function()
		local counts = countRarities(20260, true)
		expect(counts.Common / SAMPLES).toBeCloseTo(0.60, TOLERANCE)
		expect(counts.Uncommon / SAMPLES).toBeCloseTo(0.25, TOLERANCE)
		expect(counts.Rare / SAMPLES).toBeCloseTo(0.10, TOLERANCE)
		expect(counts.Epic / SAMPLES).toBeCloseTo(0.04, TOLERANCE)
		expect(counts.Legendary / SAMPLES).toBeCloseTo(0.01, TOLERANCE)
		expect(counts.Legendary).toBeGreaterThan(0)
	end)

	it("ordinary mobs never roll Legendary and keep the other weights in proportion", function()
		local counts = countRarities(777, false)
		expect(counts.Legendary).toBe(0)
		expect(counts.Common / SAMPLES).toBeCloseTo(60 / 99, TOLERANCE)
		expect(counts.Uncommon / SAMPLES).toBeCloseTo(25 / 99, TOLERANCE)
		expect(counts.Rare / SAMPLES).toBeCloseTo(10 / 99, TOLERANCE)
		expect(counts.Epic / SAMPLES).toBeCloseTo(4 / 99, TOLERANCE)
	end)

	it("Loot.roll is pure: the same seed gives the same result", function()
		local first = Loot.roll(Random.new(99), "F1.Kobold", { elite = true })
		local second = Loot.roll(Random.new(99), "F1.Kobold", { elite = true })
		expect(first).toEqual(second)
		expect(function()
			Loot.roll(Random.new(1), "F1.Nothing")
		end).toThrow("unknown loot table")
	end)

	it("boar kills pay 4 to 9 Crowns and drop hide about 60% of the time", function()
		local random = Random.new(4242)
		local hides = 0
		local rolls = 10000
		for _ = 1, rolls do
			local result = Loot.roll(random, "F1.Boar")
			expect(result.crowns).toBeGreaterThanOrEqual(4)
			expect(result.crowns).toBeLessThanOrEqual(9)
			for _, drop in result.drops do
				expect(itemExists(drop.item)).toBe(true)
				expect(drop.count).toBeGreaterThanOrEqual(1)
				if drop.item == "BoarHide" then
					hides += 1
					expect(drop.count).toBeLessThanOrEqual(2)
				end
				expect(drop.item).never.toBe("MendShard")
			end
		end
		expect(hides / rolls).toBeCloseTo(0.60, 0.03)
	end)

	it("Mend Shards drop at 0.5% from Elites only", function()
		local random = Random.new(31337)
		local rolls = 40000
		local shards = 0
		for _ = 1, rolls do
			for _, drop in Loot.roll(random, "F1.Kobold", { elite = true }).drops do
				if drop.item == "MendShard" then
					shards += 1
				end
			end
		end
		expect(shards / rolls).toBeCloseTo(0.005, 0.0025)
		expect(shards).toBeGreaterThan(0)
	end)

	it("the Last Attack Bonus is deterministic on boss tables", function()
		for seed = 1, 50 do
			local result = Loot.roll(Random.new(seed), "Boss.F1", { lastAttack = true, floor = 1 })
			local found = false
			for _, drop in result.drops do
				if drop.item == "MantleOfLastLight" then
					found = true
					expect(drop.kind).toBe("LAB")
				end
			end
			expect(found).toBe(true)
		end
		local withoutHit = Loot.roll(Random.new(7), "Boss.F1", { floor = 1 })
		for _, drop in withoutHit.drops do
			expect(drop.item).never.toBe("MantleOfLastLight")
		end
		local notABoss = Loot.roll(Random.new(7), "F1.Boar", { lastAttack = true, floor = 1 })
		for _, drop in notABoss.drops do
			expect(drop.kind).never.toBe("LAB")
		end
	end)

	it("Gilded kills always drop gear at Rare or better; a Blood Moon triples the rates", function()
		local random = Random.new(2024)
		for _ = 1, 300 do
			local result = Loot.roll(random, "F1.Boar", { gilded = true })
			local gear = nil
			for _, drop in result.drops do
				if drop.kind == "Gear" then
					gear = drop
				end
			end
			expect(gear).toBeTruthy()
			expect(gear.rarity).never.toBe("Common")
			expect(gear.rarity).never.toBe("Uncommon")
		end

		local function gearRate(context)
			local rolls = 6000
			local gearDrops = 0
			local source = Random.new(555)
			for _ = 1, rolls do
				for _, drop in Loot.roll(source, "F1.Wolf", context).drops do
					if drop.kind == "Gear" then
						gearDrops += 1
					end
				end
			end
			return gearDrops / rolls
		end
		local normal = gearRate({})
		local bloodMoon = gearRate({ bloodMoon = true })
		expect(normal).toBeCloseTo(Loot.tables["F1.Wolf"].gearChance, 0.02)
		expect(bloodMoon).toBeCloseTo(Loot.tables["F1.Wolf"].gearChance * 3, 0.03)
	end)

	it("steps gear down to the richest non-empty pool", function()
		local gearId, rarity = Loot.pickGear(Random.new(1), Loot.tables["F1.Boar"], "Legendary")
		expect(gearId).toBeTruthy()
		expect(rarity).toBe("Rare")
		local empty = {
			id = "x",
			crowns = { min = 0, max = 0 },
			materials = {},
			materialRolls = 0,
			consumableChance = 0,
			consumables = {},
			gearChance = 0,
			gear = {},
		}
		local none = Loot.pickGear(Random.new(1), empty, "Epic")
		expect(none).toBeNil()
	end)

	it("every enemy and boss loot table exists and every referenced item is real", function()
		for _, def in Enemies.list() do
			expect(Loot.tables[def.lootTable]).toBeTruthy()
		end
		for _, boss in Bosses.list() do
			expect(Loot.tables[boss.lootTable]).toBeTruthy()
			expect(Loot.tables[boss.lootTable].boss).toBe(true)
		end
		for id, lootTable in Loot.tables do
			expect(lootTable.id).toBe(id)
			for _, drop in lootTable.materials do
				expect(drop.item == Loot.NOTHING or Loot.items[drop.item] ~= nil).toBe(true)
			end
			for _, pool in lootTable.gear do
				for _, gearId in pool do
					expect(Weapons.rows[gearId] ~= nil or Armor.rows[gearId] ~= nil).toBe(true)
				end
			end
		end
		expect(#Loot.tableIds()).toBeGreaterThanOrEqual(60)
	end)

	it("the Last Attack Bonus comes from floor bosses only, at the item's own rarity", function()
		for seed = 1, 50 do
			local fieldBoss = Loot.roll(Random.new(seed), "FieldBoss.F1", { lastAttack = true, floor = 1 })
			for _, drop in fieldBoss.drops do
				expect(drop.kind).never.toBe("LAB")
				expect(drop.item).never.toBe("MantleOfLastLight")
			end
		end
		local khagan = Loot.roll(Random.new(3), "Boss.F7", { lastAttack = true, floor = 7 })
		local lab = nil
		for _, drop in khagan.drops do
			if drop.kind == "LAB" then
				lab = drop
			end
		end
		expect(lab).toBeTruthy()
		expect(lab.item).toBe("KhagansGreataxe")
		expect(lab.rarity).toBe("Legendary")
		local mantle = Loot.roll(Random.new(3), "Boss.F1", { lastAttack = true, floor = 1 })
		for _, drop in mantle.drops do
			if drop.kind == "LAB" then
				expect(drop.rarity).toBe("Apex")
			end
		end
		for id, lootTable in Loot.tables do
			if id:match("^Boss%.") then
				expect(lootTable.lab).toBe(true)
			else
				expect(lootTable.lab).toBeNil()
			end
		end
	end)

	it("Tusk, Warboar King gives a floor 1 Apex piece at 15% and no other table does", function()
		local random = Random.new(1515)
		local rolls = 20000
		local apexDrops = 0
		local seen = {}
		for _ = 1, rolls do
			for _, drop in Loot.roll(random, "FieldBoss.F1").drops do
				if drop.rarity == "Apex" then
					apexDrops += 1
					seen[drop.item] = true
					expect(drop.kind).toBe("Gear")
					expect(Armor.rows[drop.item].source).toBe("FieldBoss")
				end
			end
		end
		expect(Apex.rules.fieldBossDropChance).toBe(0.15)
		expect(apexDrops / rolls).toBeCloseTo(Apex.rules.fieldBossDropChance, 0.01)
		expect(seen.WarboarHideJerkin).toBe(true)
		expect(seen.WarboarHideGreaves).toBe(true)
		expect(Loot.tables["FieldBoss.F1"].apexPieces).toEqual({ "WarboarHideJerkin", "WarboarHideGreaves" })

		local other = Random.new(99)
		for _ = 1, 2000 do
			for _, drop in Loot.roll(other, "F1.Boar", { gilded = true }).drops do
				expect(drop.rarity).never.toBe("Apex")
			end
			for _, drop in Loot.roll(other, "Boss.F1", { floor = 1 }).drops do
				expect(drop.rarity).never.toBe("Apex")
			end
		end
		-- The spear made from his tusk is in his table and nowhere else.
		expect(Loot.tables["FieldBoss.F1"].gear.Rare).toContain("WarboarTuskSpear")
		for id, lootTable in Loot.tables do
			if id ~= "FieldBoss.F1" then
				for _, pool in lootTable.gear do
					expect(table.find(pool, "WarboarTuskSpear")).toBeNil()
				end
			end
		end
	end)
end)
