--!strict
local Bosses = Harness.load("src/shared/data/bosses")
local Tiers = Harness.load("src/shared/data/tiers")
local Combat = Harness.load("src/shared/data/combat")
local Enemies = Harness.load("src/shared/data/enemies")
local Arts = Harness.load("src/shared/data/arts")
local Weapons = Harness.load("src/shared/data/weapons")
local Loot = Harness.load("src/shared/data/loot")

local LAUNCH_BOSSES = {
	[1] = { "Grolak", 4 },
	[2] = { "MirefangMatriarch", 4 },
	[3] = { "AshbarkTreant", 5 },
	[4] = { "TidecallerSerpent", 5 },
	[5] = { "IronBulwarkGolem", 6 },
	[6] = { "PaleCrawler", 5 },
	[7] = { "KhaganOfHooves", 5 },
	[8] = { "RimeclawBehemoth", 6 },
	[9] = { "HexenStag", 5 },
	[10] = { "WardensKnight", 6 },
}

describe("bosses data", function()
	it("Grolak, Kobold Warlord has four bars, a Sentinel guard pack, the totem Lockstep and the Mantle", function()
		local grolak = Bosses.byId("Grolak")
		expect(grolak.name).toBe("Grolak, Kobold Warlord")
		expect(grolak.floor).toBe(1)
		expect(grolak.bars).toBe(4)
		expect(grolak.hpPerBar).toBe(5000)
		expect(Bosses.totalHp(grolak)).toBe(20000)
		expect(grolak.guardPack).toEqual({ { enemyId = "KoboldSentinel", count = 3 } })
		expect(grolak.lockstep.kind).toBe("Lockstep")
		expect(grolak.lockstep.targets).toBe(2)
		expect(grolak.lockstep.window).toBe(1.0)
		expect(grolak.enrage).toEqual({ startSeconds = 480, damagePerMinute = 0.1 })
		expect(grolak.mirrorShield).toBe(true)
		expect(grolak.lab).toBe("MantleOfLastLight")
		expect(grolak.lootTable).toBe("Boss.F1")
		expect(grolak.shatter).toBe("Boss")
		expect(#grolak.phases).toBe(4)
		for index, phase in grolak.phases do
			expect(phase.bar).toBe(index)
		end
	end)

	it(
		"Grolak's bars: buckler throw calls four more Sentinels, the last bar draws a curved blade with Katana Arts",
		function()
			local grolak = Bosses.byId("Grolak")
			local third = Bosses.phaseForBar(grolak, 3)
			expect(third.name).toBe("Buckler Throw")
			expect(third.summons).toEqual({ { enemyId = "KoboldSentinel", count = 4 } })
			local throwFound = false
			for _, attack in third.attacks do
				if attack.id == "BucklerThrow" then
					throwFound = true
					expect(attack.telegraph).toBe("Unblockable")
					expect(attack.groundShape).toBe("Line")
				end
			end
			expect(throwFound).toBe(true)

			local last = Bosses.phaseForBar(grolak, 4)
			expect(last.name).toBe("Curved Blade")
			expect(last.archetype).toBe("Skirmisher")
			expect(last.attackSpeed).toBeGreaterThan(1)
			local swap = false
			for _, mechanic in last.mechanics do
				if mechanic.kind == "WeaponSwap" then
					swap = true
				end
			end
			expect(swap).toBe(true)
			expect(#last.arts).toBeGreaterThanOrEqual(3)
			for _, artId in last.arts do
				expect(Arts.byId(artId).weapon).toBe("Katana")
			end
			-- The jump cut one-shots a yellow-HP (half or less) level-1 player.
			local skyfall = nil
			for _, attack in last.attacks do
				if attack.id == "SkyfallCut" then
					skyfall = attack
				end
			end
			expect(skyfall).toBeTruthy()
			expect(skyfall.telegraph).toBe("Unblockable")
			expect(grolak.attack * skyfall.multiplier).toBeGreaterThan(Tiers.maxHp(1) * Combat.hpYellowFraction)
		end
	)

	it("every launch floor has exactly its boss with the section 9 bar count", function()
		for floor, row in LAUNCH_BOSSES do
			local boss = Bosses.forFloor(floor)
			expect(boss).toBeTruthy()
			expect(boss.id).toBe(row[1])
			expect(boss.bars).toBe(row[2])
			expect(boss.tier).toBe(floor)
			expect(boss.mirrorShield).toBe(true)
			expect(boss.phases[1].bar).toBe(1)
			expect(boss.phases[#boss.phases].bar).toBeLessThanOrEqual(boss.bars)
			expect(boss.lockstep.kind).toBe("Lockstep")
		end
		expect(#Bosses.list()).toBe(10)
		expect(Bosses.forFloor(11)).toBeNil()
		expect(Bosses.byId("Nobody")).toBeNil()
	end)

	it("gives the raid a level's worth of XP", function()
		for _, boss in Bosses.list() do
			expect(boss.xp).toBe(Tiers.xpToNext(boss.floor))
		end
	end)

	it("every phase attack, guard pack, summon and Art is valid", function()
		for _, boss in Bosses.list() do
			for _, summon in boss.guardPack do
				expect(Enemies.byId(summon.enemyId)).toBeTruthy()
			end
			for _, phase in boss.phases do
				for _, attack in phase.attacks do
					expect(attack.windUp).toBeGreaterThanOrEqual(Combat.telegraphMinWindUp)
					expect(attack.windUp).toBeLessThanOrEqual(Combat.telegraphMaxWindUp)
				end
				for _, summon in phase.summons or {} do
					expect(Enemies.byId(summon.enemyId)).toBeTruthy()
				end
				for _, artId in phase.arts or {} do
					expect(Arts.byId(artId)).toBeTruthy()
				end
			end
		end
	end)

	it("every phase weapon is a weapons.luau row of its Arts' category; the Khagan's axe is the floor 7 LAB", function()
		local swaps = 0
		for _, boss in Bosses.list() do
			for _, phase in boss.phases do
				if phase.weapon ~= nil then
					swaps += 1
					local weapon = Weapons.byId(phase.weapon)
					expect(weapon).toBeTruthy()
					for _, artId in phase.arts or {} do
						expect(Arts.byId(artId).weapon).toBe(weapon.category)
					end
				end
			end
		end
		expect(swaps).toBe(3)
		expect(Weapons.byId("WarlordCurvedBlade").category).toBe("Katana")
		expect(Weapons.byId("WardensTwinSabres").category).toBe("TwinFang")
		local khagan = Bosses.byId("KhaganOfHooves")
		expect(khagan.lab).toBe("KhagansGreataxe")
		expect(Bosses.phaseForBar(khagan, 5).weapon).toBe("KhagansGreataxe")
		expect(Weapons.byId("KhagansGreataxe").rarity).toBe("Legendary")
		expect(table.find(Bosses.pendingLab, "KhagansGreataxe")).toBeNil()
		expect(Loot.lastAttackBonus[7]).toBe("KhagansGreataxe")
		-- Every other pending LAB id is still pending: no row and no loot entry.
		for _, id in Bosses.pendingLab do
			expect(Weapons.byId(id)).toBeNil()
		end
	end)

	it("phase lookup picks the last phase at or below a bar", function()
		local matriarch = Bosses.byId("MirefangMatriarch")
		expect(Bosses.phaseForBar(matriarch, 1).name).toBe("Three Platforms")
		expect(Bosses.phaseForBar(matriarch, 2).name).toBe("Eggs")
		expect(Bosses.phaseForBar(matriarch, 3).name).toBe("Eggs")
		expect(Bosses.phaseForBar(matriarch, 4).name).toBe("Poison Fog")
		local knight = Bosses.byId("WardensKnight")
		expect(Bosses.phaseForBar(knight, 6).name).toBe("Forced Duelist Protocol")
		expect(Bosses.phaseForBar(knight, 4).weapon).toBe("WardensTwinSabres")
	end)

	it("enrage starts at 8 minutes and adds 10% per minute", function()
		local grolak = Bosses.byId("Grolak")
		expect(Bosses.enrageMultiplier(grolak, 0)).toBe(1)
		expect(Bosses.enrageMultiplier(grolak, 480)).toBe(1)
		expect(Bosses.enrageMultiplier(grolak, 481)).toBeCloseTo(1.1, 1e-9)
		expect(Bosses.enrageMultiplier(grolak, 540)).toBeCloseTo(1.2, 1e-9)
		expect(Bosses.enrageMultiplier(grolak, 600)).toBeCloseTo(1.3, 1e-9)
		expect(Bosses.rules.enrageStartSeconds).toBe(480)
		expect(Bosses.rules.enrageDamagePerMinute).toBe(0.1)
	end)

	it("section 7 raid rules are data: Overwhelm under three players, 60 s wipe reset, 3 s entrance", function()
		expect(Bosses.overwhelms(1)).toBe(true)
		expect(Bosses.overwhelms(2)).toBe(true)
		expect(Bosses.overwhelms(3)).toBe(false)
		expect(Bosses.rules.overwhelmAttackSpeed).toBe(1.4)
		expect(Bosses.rules.overwhelmPackIntervalSeconds).toBe(20)
		expect(Bosses.rules.wipeResetSeconds).toBe(60)
		expect(Bosses.rules.entranceSeconds).toBe(3)
		expect(Bosses.rules.lockstepWindow).toBe(1.0)
		expect(Bosses.rules.successTargets.soloDualWielderApex).toBe(0.25)
	end)

	it("scales by floor tier without touching the row", function()
		local knight = Bosses.byId("WardensKnight")
		local scaled = Bosses.scaled(knight)
		expect(scaled.hpPerBar).toBe(math.floor(6000 * Tiers.get(10).hp + 0.5))
		expect(scaled.attack).toBeCloseTo(50 * Tiers.get(10).attack, 1e-9)
		expect(knight.hpPerBar).toBe(6000)
		expect(Bosses.scaled(Bosses.byId("Grolak")).hpPerBar).toBe(5000)
	end)

	it("the Iron Bulwark Golem never drops its shield and the Warden's Knight ends in Duelist Protocol", function()
		local golem = Bosses.byId("IronBulwarkGolem")
		expect(golem.phases[1].mechanics[1].kind).toBe("Shield")
		local knight = Bosses.byId("WardensKnight")
		local lastPhase = knight.phases[#knight.phases]
		expect(lastPhase.summons).toBeNil()
		expect(lastPhase.arts).toContain("TwinFang.MeteorCascade")
	end)
end)
