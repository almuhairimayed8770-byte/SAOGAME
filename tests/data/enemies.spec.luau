--!strict
local Enemies = Harness.load("src/shared/data/enemies")
local Combat = Harness.load("src/shared/data/combat")
local Tiers = Harness.load("src/shared/data/tiers")
local Rigs = Harness.load("src/shared/data/rigs")
local Arts = Harness.load("src/shared/data/arts")
local Weapons = Harness.load("src/shared/data/weapons")
local Loot = Harness.load("src/shared/data/loot")

-- Section 6 damage formula for a level-1 player with the starter sword and a tier-1 Art, no crit.
local function hitsToKill(def)
	local attack = Weapons.byId("TrialistSword").attack
	local multiplier = Arts.byId("OneHandedSword.Horizontal").multiplier
	local str = 10
	local damage = attack * multiplier * (1 + str * Combat.strDamageScale) - def.defense
	return math.ceil(def.hp / damage)
end

local BESTIARY = {
	[1] = { "FrenzyBoar", "DireWolf", "KoboldSentinel", "KoboldAxeman", "NepentheBloom" },
	[2] = { "MarshWasp", "MireLeech", "BogTroll", "ReedLurker" },
	[3] = { "EmberFox", "TreantSapling", "AshBeetle", "WillWispMoth" },
	[4] = { "GullHarpy", "TideCrab", "SeaLizardman", "BrineSerpent" },
	[5] = { "HighlandRam", "ScarecrowConstruct", "BanditTrialist", "StormHawk" },
	[6] = { "GlowSpider", "CaveOgre", "FungalShambler", "LanternBat" },
	[7] = { "SavannaLion", "MinotaurGuard", "DustVulture", "ElephantBeetle" },
	[8] = { "FrostWolf", "IceGolem", "Yeti", "RimeWisp" },
	[9] = { "ShadeHound", "DryadKnight", "Owlbear", "GlowMantis" },
	[10] = { "CitadelKnight", "WardenHound", "ClockworkArcher", "HonorGuardCaptain" },
}

describe("enemies data", function()
	it("Frenzy Boar is the Phase 0 Charger on the Boar rig with one Charge", function()
		local boar = Enemies.byId("FrenzyBoar")
		expect(boar.archetype).toBe("Charger")
		expect(boar.skin).toBe("Boar")
		expect(Rigs[boar.skin]).toBeTruthy()
		expect(boar.shatter).toBe("Beast")
		expect(boar.floor).toBe(1)
		expect(boar.band).toBe("Verge")
		expect(#boar.attacks).toBe(1)
		local charge = boar.attacks[1]
		expect(charge.id).toBe("Charge")
		expect(charge.telegraph).toBe("Normal")
		expect(charge.windUp).toBe(0.6)
		expect(charge.strike).toBe(0.5)
		expect(charge.recovery).toBe(1.2)
		expect(charge.groundShape).toBe("Line")
		expect(charge.reach).toBe(14)
		expect(charge.arc).toBe(0)
		expect(charge.clip).toBe("Charge")
		expect(boar.moveSpeed).toBe(Rigs.Boar.walkSpeed)
	end)

	it("Kobold Axeman is the Phase 0 Brute on the Kobold rig with one Overhead", function()
		local kobold = Enemies.byId("KoboldAxeman")
		expect(kobold.archetype).toBe("Brute")
		expect(kobold.skin).toBe("Kobold")
		expect(Rigs[kobold.skin]).toBeTruthy()
		expect(kobold.shatter).toBe("Humanoid")
		expect(#kobold.attacks).toBe(1)
		local overhead = kobold.attacks[1]
		expect(overhead.id).toBe("Overhead")
		expect(overhead.telegraph).toBe("GuardBreak")
		expect(overhead.windUp).toBe(1.0)
		expect(overhead.strike).toBe(0.35)
		expect(overhead.recovery).toBe(1.4)
		expect(overhead.groundShape).toBe("Cone")
		expect(overhead.reach).toBe(6)
		expect(overhead.arc).toBe(60)
		expect(overhead.clip).toBe("Overhead")
		expect(overhead.gaugeDamage).toBeGreaterThanOrEqual(40)
		expect(kobold.moveSpeed).toBe(Rigs.Kobold.walkSpeed)
	end)

	it("a level-1 player with the Trialist Sword kills a boar in 6 to 8 Art hits and a kobold in 10 to 14", function()
		local boarHits = hitsToKill(Enemies.byId("FrenzyBoar"))
		expect(boarHits).toBeGreaterThanOrEqual(6)
		expect(boarHits).toBeLessThanOrEqual(8)
		local koboldHits = hitsToKill(Enemies.byId("KoboldAxeman"))
		expect(koboldHits).toBeGreaterThanOrEqual(10)
		expect(koboldHits).toBeLessThanOrEqual(14)
		-- Floor 1 rows are tier 1, so scaling is the identity for the Phase 0 slice.
		local scaled = Enemies.scaled(Enemies.byId("FrenzyBoar"))
		expect(scaled.hp).toBe(Enemies.byId("FrenzyBoar").hp)
		expect(scaled.attack).toBe(Enemies.byId("FrenzyBoar").attack)
	end)

	it("a kobold overhead hurts but does not kill a fresh level-1 player", function()
		local kobold = Enemies.byId("KoboldAxeman")
		local damage = kobold.attack * kobold.attacks[1].multiplier
		expect(damage).toBeGreaterThan(Tiers.maxHp(1) * 0.1)
		expect(damage).toBeLessThan(Tiers.maxHp(1) * 0.25)
	end)

	it("every attack respects the telegraph bounds (hard rule: wind-up >= 0.3)", function()
		for _, def in Enemies.list() do
			expect(#def.attacks).toBeGreaterThanOrEqual(1)
			for _, attack in def.attacks do
				expect(attack.windUp).toBeGreaterThanOrEqual(Combat.telegraphMinWindUp)
				expect(attack.windUp).toBeLessThanOrEqual(Combat.telegraphMaxWindUp)
			end
		end
		for _, attack in Enemies.eliteAttacks do
			expect(attack.windUp).toBeGreaterThanOrEqual(Combat.telegraphMinWindUp)
		end
	end)

	it("covers the whole floors 1 to 10 bestiary with one field boss per floor", function()
		for floor, ids in BESTIARY do
			for _, id in ids do
				local def = Enemies.byId(id)
				expect(def).toBeTruthy()
				expect(def.floor).toBe(floor)
				expect(def.tier).toBe(floor)
			end
			expect(#Enemies.forFloor(floor)).toBeGreaterThanOrEqual(3)
			local boss = Enemies.fieldBoss(floor)
			expect(boss).toBeTruthy()
			expect(boss.fieldBoss).toBe(true)
			expect(boss.mirrorShield).toBe(true)
		end
		expect(Enemies.fieldBoss(1).id).toBe("TuskWarboarKing")
		expect(Enemies.count()).toBe(51)
	end)

	it("uses the archetype telegraphs from the section 9 table", function()
		local expected = {
			Charger = { "Normal", 0.6 },
			Brute = { "GuardBreak", 1.0 },
			Skirmisher = { "Normal", 0.4 },
			Lancer = { "Unblockable", 0.7 },
			Swarm = { "Normal", 0.3 },
			CasterBeast = { "Unblockable", 1.2 },
			Stalker = { "Normal", 0.3 },
			WardenConstruct = { "Unblockable", 1.0 },
		}
		for _, def in Enemies.forFloor(2) do
			local row = expected[def.archetype]
			if row then
				expect(def.attacks[1].telegraph).toBe(row[1])
				expect(def.attacks[1].windUp).toBe(row[2])
			end
		end
		expect(Enemies.byId("NepentheBloom").attacks[1].windUp).toBe(1.2)
		expect(Enemies.byId("NepentheBloom").attacks[1].status).toBe("Poison")
		expect(Enemies.byId("MireLeech").attacks[1].status).toBe("Paralysis")
		expect(Enemies.byId("ScarecrowConstruct").attacks[1].groundShape).toBe("Circle")
	end)

	it("Elite variant: 1.5x stats, a Mirror Shield and a second attack, without touching the row", function()
		local boar = Enemies.byId("FrenzyBoar")
		local elite = Enemies.variant(boar, "Elite")
		expect(elite.hp).toBe(180)
		expect(elite.attack).toBeCloseTo(21, 1e-9)
		expect(elite.defense).toBe(3)
		expect(elite.guardGauge).toBe(90)
		expect(elite.elite).toBe(true)
		expect(elite.mirrorShield).toBe(true)
		expect(elite.variant).toBe("Elite")
		expect(elite.name).toBe("Elite Frenzy Boar")
		expect(#elite.attacks).toBe(2)
		expect(elite.attacks[2].id).toBe("Trample")
		-- The source row is untouched.
		expect(boar.hp).toBe(120)
		expect(#boar.attacks).toBe(1)
		expect(boar.elite).toBeNil()
		-- An Elite that already carries the archetype's second attack does not get a duplicate.
		local king = Enemies.variant(Enemies.byId("TuskWarboarKing"), "Elite")
		expect(#king.attacks).toBe(2)
	end)

	it("Night variant adds 25% damage; Gilded has 5x HP and a guaranteed Rare; variants stack", function()
		local kobold = Enemies.byId("KoboldAxeman")
		local night = Enemies.variant(kobold, "Night")
		expect(night.attack).toBeCloseTo(kobold.attack * 1.25, 1e-9)
		expect(night.hp).toBe(kobold.hp)
		expect(night.night).toBe(true)
		expect(night.name).toBe("Night Kobold Axeman")

		local gilded = Enemies.variant(kobold, "Gilded")
		expect(gilded.hp).toBe(kobold.hp * 5)
		expect(gilded.attack).toBe(kobold.attack)
		expect(gilded.gilded).toBe(true)
		expect(gilded.guaranteedRare).toBe(true)

		local bloodMoonNight = Enemies.variant(Enemies.variant(kobold, "Elite"), "Night")
		expect(bloodMoonNight.hp).toBe(285)
		expect(bloodMoonNight.attack).toBeCloseTo(kobold.attack * 1.5 * 1.25, 1e-9)
		expect(bloodMoonNight.mirrorShield).toBe(true)

		expect(function()
			Enemies.variant(kobold, "Golden")
		end).toThrow("unknown variant")
	end)

	it("scales rows by their floor tier and field bosses by 4x Elite stats", function()
		local ram = Enemies.byId("HighlandRam")
		local scaled = Enemies.scaled(ram)
		local tier = Tiers.get(5)
		expect(scaled.hp).toBe(math.floor(ram.hp * tier.hp + 0.5))
		expect(scaled.attack).toBeCloseTo(ram.attack * tier.attack, 1e-9)
		expect(scaled.guardGauge).toBe(math.floor(ram.guardGauge * tier.gauge + 0.5))
		expect(scaled.xp).toBe(Tiers.scaleXp(ram.xp, 5))
		expect(ram.hp).toBe(130)

		local king = Enemies.scaled(Enemies.byId("TuskWarboarKing"))
		local rules = Enemies.rules
		expect(king.hp).toBe(300 * rules.eliteStatMultiplier * rules.fieldBossEliteMultiplier)
		expect(king.attack).toBeCloseTo(20 * 6, 1e-9)
	end)

	it("declares every rig that rigs.luau lacks as a placeholder, and nothing else", function()
		local declared = {}
		for _, rigId in Enemies.placeholderRigs do
			declared[rigId] = true
			expect(Rigs[rigId]).toBeNil()
		end
		for _, rigId in Enemies.rigIds() do
			if Rigs[rigId] == nil then
				expect(declared[rigId]).toBe(true)
			end
		end
		expect(declared.Boar).toBeNil()
		expect(declared.Kobold).toBeNil()
	end)

	it("every loot table and Art an enemy references exists", function()
		for _, def in Enemies.list() do
			expect(Loot.tables[def.lootTable]).toBeTruthy()
			for _, artId in def.arts or {} do
				expect(Arts.byId(artId)).toBeTruthy()
			end
			expect(def.guardRegenPerSecond).toBe(Combat.guardRegenPerSecond)
		end
		expect(Enemies.byId("BanditTrialist").arts).toContain("OneHandedSword.SharpNail")
		-- Section 9: the Elephant Beetle's gauge is 3x a Brute of its floor (Cave Ogre 170, Yeti 180).
		expect(Enemies.byId("ElephantBeetle").guardGauge).toBe(520)
		expect(Enemies.byId("ElephantBeetle").guardGauge).toBeGreaterThanOrEqual(
			Enemies.byId("CaveOgre").guardGauge * 3
		)
	end)

	it("lists floors by band order and returns nil for unknown ids", function()
		local floor1 = Enemies.list(1)
		expect(floor1[1].band).toBe("Verge")
		expect(floor1[#floor1].band).toBe("Blight")
		expect(Enemies.byId("Dragon")).toBeNil()
		expect(Enemies.fieldBoss(99)).toBeNil()
		expect(Enemies.count(1)).toBe(6)
	end)
end)
