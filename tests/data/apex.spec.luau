local Apex = Harness.load("src/shared/data/apex")
local Weapons = Harness.load("src/shared/data/weapons")
local Armor = Harness.load("src/shared/data/armor")
local Loot = Harness.load("src/shared/data/loot")
local Bosses = Harness.load("src/shared/data/bosses")

describe("apex data", function()
	it("floor 1 has a weapon, four armor pieces and an accessory from the four sources", function()
		local set = Apex.get(1)
		expect(set.id).toBe("Floor1Apex")
		expect(set.weapon).toBe("DaybreakEdge")
		expect(#set.armor).toBe(4)
		expect(set.accessory).toBe("FirstlightSignet")
		expect(#set.pieces).toBe(6)
		expect(#Apex.pieceIds(1)).toBe(6)

		local sources = {}
		for _, piece in set.pieces do
			sources[piece.source] = (sources[piece.source] or 0) + 1
		end
		expect(sources.LAB).toBe(1)
		expect(sources.FieldBoss).toBe(2)
		expect(sources.MiniDungeon).toBe(2)
		expect(sources.Smith).toBe(1)
	end)

	it("every piece exists at rarity Apex on floor 1 and the armor carries the set id", function()
		local set = Apex.get(1)
		local weapon = Weapons.byId(set.weapon)
		expect(weapon.rarity).toBe("Apex")
		expect(weapon.floor).toBe(1)
		expect(weapon.source).toBe("Smith")
		for _, id in set.armor do
			local piece = Armor.byId(id)
			expect(piece.rarity).toBe("Apex")
			expect(piece.set).toBe("Floor1Apex")
		end
		expect(Armor.byId(set.accessory).slot).toBe("Accessory")
		expect(Armor.byId("MantleOfLastLight").set).toBe("Floor1Apex")
	end)

	it("the LAB piece is the Mantle and agrees with loot.luau and the floor boss", function()
		local labPiece = nil
		for _, piece in Apex.get(1).pieces do
			if piece.source == "LAB" then
				labPiece = piece.id
			end
		end
		expect(labPiece).toBe("MantleOfLastLight")
		expect(Loot.lastAttackBonus[1]).toBe(labPiece)
		expect(Bosses.forFloor(1).lab).toBe(labPiece)
	end)

	it("the smith recipe forges the set weapon from a Labyrinth ingot", function()
		local recipe = Apex.get(1).recipe
		expect(recipe.result).toBe("DaybreakEdge")
		expect(recipe.ingot).toBe("DeepstoneIngot")
		expect(Loot.items[recipe.ingot]).toBeTruthy()
		expect(Loot.items[recipe.ingot].rarity).toBe("Apex")
		for _, entry in recipe.materials do
			expect(Loot.items[entry.item]).toBeTruthy()
		end
	end)

	it("isComplete needs all six pieces, accepts lists or sets, ignores extras and unknown floors", function()
		local ids = Apex.pieceIds(1)
		expect(Apex.isComplete(ids, 1)).toBe(true)

		local missingOne = table.clone(ids)
		table.remove(missingOne, 1)
		expect(Apex.isComplete(missingOne, 1)).toBe(false)
		expect(Apex.missing(missingOne, 1)).toEqual({ ids[1] })

		local withExtras = table.clone(ids)
		table.insert(withExtras, "TrialistSword")
		table.insert(withExtras, "TrialistHood")
		expect(Apex.isComplete(withExtras, 1)).toBe(true)

		local asSet = {}
		for _, id in ids do
			asSet[id] = true
		end
		expect(Apex.isComplete(asSet, 1)).toBe(true)
		asSet.DaybreakEdge = false
		expect(Apex.isComplete(asSet, 1)).toBe(false)

		expect(Apex.isComplete(ids, 2)).toBe(false)
		expect(Apex.isComplete({}, 1)).toBe(false)
		expect(#Apex.missing({}, 1)).toBe(6)
		expect(Apex.pieceIds(2)).toEqual({})
		expect(Apex.get(2)).toBeNil()
		expect(Apex.floors()).toEqual({ 1 })
	end)

	it("rules: the field boss drops a piece at 15% and the edge-light is the ApexEdge token", function()
		expect(Apex.rules.fieldBossDropChance).toBe(0.15)
		expect(Apex.rules.edgeLightToken).toBe("ApexEdge")
		expect(Apex.rules.piecesPerSet).toBe(6)
	end)
end)
