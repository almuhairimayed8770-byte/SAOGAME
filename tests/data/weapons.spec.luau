local Weapons = Harness.load("src/shared/data/weapons")
local Armor = Harness.load("src/shared/data/armor")
local Palette = Harness.load("src/shared/data/palette")

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

describe("weapons data", function()
	it("ships the Phase 0 Trialist Sword with its brief numbers", function()
		local sword = Weapons.byId("TrialistSword")
		expect(sword.category).toBe("OneHandedSword")
		expect(sword.rarity).toBe("Common")
		expect(sword.floor).toBe(1)
		expect(sword.attack).toBe(18)
		expect(sword.reach).toBe(4.5)
		expect(sword.trailWidth).toBe(0.9)
		expect(sword.trailColor).toBe("TrailCyanWhite")
		expect(sword.slots).toBe(0)
		expect(Weapons.starters.OneHandedSword).toBe("TrialistSword")
	end)

	it("has a Common floor-1 starter per category", function()
		for _, category in CATEGORIES do
			local starter = Weapons.starter(category)
			expect(starter).toBeTruthy()
			expect(starter.category).toBe(category)
			expect(starter.rarity).toBe("Common")
			expect(starter.floor).toBe(1)
			expect(starter.attack).toBe(Weapons.baseAttack[category])
		end
	end)

	it("resolves categories and returns nil for unknown ids", function()
		expect(Weapons.category("TrialistSword")).toBe("OneHandedSword")
		expect(Weapons.category("KoboldCleaver")).toBe("Axe")
		expect(Weapons.category("NotAWeapon")).toBeNil()
		expect(Weapons.byId("NotAWeapon")).toBeNil()
		expect(Weapons.matchesArt("TrialistSword", "OneHandedSword")).toBe(true)
		expect(Weapons.matchesArt("TrialistSword", "Rapier")).toBe(false)
	end)

	it("holds the section 8 named weapons with their rarity, floor and source", function()
		local expected = {
			TemperedEdge = { "OneHandedSword", "Rare", 1 },
			KoboldCleaver = { "Axe", "Uncommon", 1 },
			LucentNeedle = { "Rapier", "Epic", 4 },
			SovereignsOath = { "TwoHandedSword", "Apex", 25, "LAB" },
			Nightfall = { "OneHandedSword", "Legendary", 50, "LAB" },
			GlacierEdge = { "OneHandedSword", "Legendary", 55, "Smith" },
		}
		for id, row in expected do
			local weapon = Weapons.byId(id)
			expect(weapon).toBeTruthy()
			expect(weapon.named).toBe(true)
			expect(weapon.category).toBe(row[1])
			expect(weapon.rarity).toBe(row[2])
			expect(weapon.floor).toBe(row[3])
			if row[4] then
				expect(weapon.source).toBe(row[4])
			end
		end
		-- The Mantle is a coat: armor, not a weapon.
		expect(Weapons.byId("MantleOfLastLight")).toBeNil()
		expect(Armor.byId("MantleOfLastLight").slot).toBe("OverLayer")
	end)

	it("has at least three named weapons on floor 1", function()
		local count = 0
		for _, weapon in Weapons.named() do
			if weapon.floor == 1 then
				count += 1
			end
		end
		expect(count).toBeGreaterThanOrEqual(3)
	end)

	it("rarity table: slots 0..5, drop weights 60/25/10/4/1 and no Apex drops", function()
		local order = Weapons.rarityOrder
		expect(order).toEqual({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Apex" })
		local weights = {}
		local previousScale = 0
		for index, rarity in order do
			local row = Weapons.rarity[rarity]
			expect(row.slots).toBe(index - 1)
			expect(row.attackScale).toBeGreaterThan(previousScale)
			previousScale = row.attackScale
			table.insert(weights, row.dropWeight)
		end
		expect(weights).toEqual({ 60, 25, 10, 4, 1, 0 })
	end)

	it("trail colors are palette tokens matching the section 8 category colors", function()
		local sectionEight = {
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
		}
		for category, token in sectionEight do
			expect(Weapons.trailColor[category]).toBe(token)
		end
		for _, weapon in Weapons.list() do
			expect(Palette.tokens[weapon.trailColor]).toBeTruthy()
			expect(weapon.trailColor).toBe(sectionEight[weapon.category])
			if weapon.category == "TwinFang" then
				expect(weapon.twinColor).toBe("TrailViolet")
			else
				expect(weapon.twinColor).toBeNil()
			end
		end
	end)

	it("computes attack for a category, rarity and floor", function()
		expect(Weapons.attackFor("OneHandedSword", "Common", 1)).toBe(18)
		expect(Weapons.attackFor("OneHandedSword", "Rare", 1)).toBe(23)
		expect(Weapons.attackFor("OneHandedSword", "Apex", 1)).toBe(40)
		expect(Weapons.attackFor("TwoHandedSword", "Common", 10)).toBe(67)
	end)

	it("boss-held weapons are rows for the sweep and the trail but never player items", function()
		local bossOnly = 0
		for _, weapon in Weapons.list() do
			if weapon.bossOnly then
				bossOnly += 1
				expect(weapon.source).toBeNil()
				expect(weapon.named).toBeNil()
			end
		end
		expect(bossOnly).toBe(2)
		expect(Weapons.byId("WarlordCurvedBlade").bossOnly).toBe(true)
		expect(Weapons.byId("WarlordCurvedBlade").category).toBe("Katana")
		expect(Weapons.byId("WardensTwinSabres").bossOnly).toBe(true)
		expect(Weapons.byId("WardensTwinSabres").twinColor).toBe("TrailViolet")
		-- The Khagan's axe is a real Legendary (the floor 7 LAB), not a boss-only row.
		local axe = Weapons.byId("KhagansGreataxe")
		expect(axe.bossOnly).toBeNil()
		expect(axe.rarity).toBe("Legendary")
		expect(axe.source).toBe("LAB")
		expect(axe.attack).toBe(Weapons.attackFor("TwoHandedSword", "Legendary", 7))
	end)

	it("sorts lists by floor then rarity", function()
		local list = Weapons.list("OneHandedSword")
		expect(list[1].id).toBe("TrialistSword")
		for index = 2, #list do
			expect(list[index].floor).toBeGreaterThanOrEqual(list[index - 1].floor)
		end
		expect(list[#list].id).toBe("GlacierEdge")
	end)
end)

describe("armor data", function()
	it("has the Trialist cloth set across five slots, Common, floor 1, light", function()
		local ids = {}
		for _, slot in { "Chest", "Legs", "Hands", "Boots", "Head" } do
			local id = Armor.trialistSet[slot]
			local piece = Armor.byId(id)
			expect(piece).toBeTruthy()
			expect(piece.slot).toBe(slot)
			expect(piece.rarity).toBe("Common")
			expect(piece.floor).toBe(1)
			expect(piece.weightClass).toBe("Light")
			expect(piece.agiPenalty).toBe(0)
			table.insert(ids, id)
		end
		local totals = Armor.totals(ids)
		expect(totals.defense).toBe(7)
		expect(totals.weight).toBe(3.5)
		expect(totals.agiPenalty).toBe(0)
	end)

	it("the Mantle of Last Light is the floor 1 Apex over-layer from the Last Attack Bonus", function()
		local mantle = Armor.byId("MantleOfLastLight")
		expect(mantle.slot).toBe("OverLayer")
		expect(mantle.rarity).toBe("Apex")
		expect(mantle.floor).toBe(1)
		expect(mantle.set).toBe("Floor1Apex")
		expect(mantle.source).toBe("LAB")
	end)

	it("weight classes fix the AGI cost per piece", function()
		expect(Armor.weightClasses.Light.agiPenalty).toBe(0)
		expect(Armor.weightClasses.Medium.agiPenalty).toBeGreaterThan(0)
		expect(Armor.weightClasses.Heavy.agiPenalty).toBeGreaterThan(Armor.weightClasses.Medium.agiPenalty)
		for _, piece in Armor.list() do
			local class = Armor.weightClasses[piece.weightClass]
			expect(piece.agiPenalty).toBe(class.agiPenalty)
			expect(piece.weight).toBeLessThanOrEqual(class.maxWeight)
		end
	end)

	it("groups the floor 1 Apex set and skips unknown ids in totals", function()
		local set = Armor.set("Floor1Apex")
		expect(#set).toBe(5)
		expect(Armor.totals({ "TrialistTunic", "Nope" }).defense).toBe(2)
		expect(Armor.byId("Nope")).toBeNil()
	end)
end)
