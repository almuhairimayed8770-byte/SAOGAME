--!strict
--[[
	Validates src/shared/data/apex.luau: every set has six pieces (a weapon, four armor pieces, an
	accessory) that exist in weapons.luau / armor.luau at rarity Apex on the set's floor, armor
	rows carry the set id (and no stray row does), each of the four sources is used, the LAB piece
	matches loot.lastAttackBonus and the floor boss, and the recipe's ingot and materials exist.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local SOURCES = { "LAB", "FieldBoss", "MiniDungeon", "Smith" }
local SLOTS = { "Weapon", "OffHand", "Chest", "Legs", "Hands", "Boots", "Head", "OverLayer", "Accessory" }

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Check = ctx.load("src/shared/util/Check")
	local Apex = ctx.load("src/shared/data/apex")
	local Weapons = ctx.load("src/shared/data/weapons")
	local Armor = ctx.load("src/shared/data/armor")
	local Loot = ctx.load("src/shared/data/loot")
	local Bosses = ctx.load("src/shared/data/bosses")

	local function problem(id: string, message: string)
		table.insert(problems, ("apex.%s: %s"):format(id, message))
	end

	local pieceSchema = Check.interface({
		id = Check.string(64),
		slot = Check.literal(table.unpack(SLOTS)),
		source = Check.literal(table.unpack(SOURCES)),
		sourceDetail = Check.string(200),
	})
	local setSchema = Check.interface({
		id = Check.string(32),
		floor = Check.integer(1, 100),
		name = Check.string(64),
		weapon = Check.string(64),
		armor = Check.array(Check.string(64), 4),
		accessory = Check.string(64),
		pieces = Check.array(pieceSchema, 6),
		recipe = Check.interface({
			result = Check.string(64),
			ingot = Check.string(48),
			ingotSource = Check.string(200),
			crowns = Check.integer(0),
			materials = Check.array(Check.interface({ item = Check.string(48), count = Check.integer(1, 99) }), 8),
		}),
	})

	if Apex.sets[1] == nil then
		problem("sets", "floor 1 has no Apex set")
	end

	for floor, set in Apex.sets do
		local ok, message = setSchema(set)
		if not ok then
			problem(tostring(floor), message or "invalid set")
			continue
		end
		local label = set.id
		if set.floor ~= floor then
			problem(label, ("set floor %d differs from its key %s"):format(set.floor, tostring(floor)))
		end
		if #set.armor ~= 4 then
			problem(label, ("a set has four armor pieces, found %d"):format(#set.armor))
		end
		if #set.pieces ~= Apex.rules.piecesPerSet then
			problem(label, ("a set has %d pieces, found %d"):format(Apex.rules.piecesPerSet, #set.pieces))
		end

		-- Weapon
		local weapon = Weapons.rows[set.weapon]
		if weapon == nil then
			problem(label, ("weapon '%s' is not in weapons.luau"):format(set.weapon))
		else
			if weapon.rarity ~= "Apex" then
				problem(label, ("weapon '%s' is %s, not Apex"):format(set.weapon, weapon.rarity))
			end
			if weapon.floor ~= set.floor then
				problem(label, ("weapon '%s' is a floor %d item"):format(set.weapon, weapon.floor))
			end
		end

		-- Armor and accessory
		local armorIds = table.clone(set.armor)
		table.insert(armorIds, set.accessory)
		for _, id in armorIds do
			local piece = Armor.rows[id]
			if piece == nil then
				problem(label, ("armor piece '%s' is not in armor.luau"):format(id))
				continue
			end
			if piece.rarity ~= "Apex" then
				problem(label, ("'%s' is %s, not Apex"):format(id, piece.rarity))
			end
			if piece.set ~= set.id then
				problem(label, ("'%s' does not carry set '%s'"):format(id, set.id))
			end
			if piece.floor ~= set.floor then
				problem(label, ("'%s' is a floor %d item"):format(id, piece.floor))
			end
		end
		local accessory = Armor.rows[set.accessory]
		if accessory ~= nil and accessory.slot ~= "Accessory" then
			problem(label, ("accessory '%s' is a %s"):format(set.accessory, accessory.slot))
		end
		for id, piece in Armor.rows do
			if piece.set == set.id and table.find(armorIds, id) == nil then
				problem(label, ("armor '%s' claims the set but is not one of its pieces"):format(id))
			end
		end

		-- Pieces list: matches the six ids, every source used, LAB consistent
		local pieceIds: { [string]: any } = {}
		local sourcesUsed: { [string]: boolean } = {}
		for _, piece in set.pieces do
			pieceIds[piece.id] = piece
			sourcesUsed[piece.source] = true
			local item = Weapons.rows[piece.id] or Armor.rows[piece.id]
			if item == nil then
				problem(label, ("piece '%s' does not exist"):format(piece.id))
			elseif item.slot ~= nil and item.slot ~= piece.slot then
				problem(label, ("piece '%s' is a %s, listed as %s"):format(piece.id, item.slot, piece.slot))
			elseif item.slot == nil and piece.slot ~= "Weapon" then
				problem(label, ("weapon piece '%s' must have slot Weapon"):format(piece.id))
			end
			if item ~= nil and item.source ~= nil and item.source ~= piece.source then
				problem(
					label,
					("piece '%s' source %s differs from its row's %s"):format(piece.id, piece.source, item.source)
				)
			end
		end
		for _, id in { set.weapon, set.accessory } do
			if pieceIds[id] == nil then
				problem(label, ("'%s' is missing from pieces"):format(id))
			end
		end
		for _, id in set.armor do
			if pieceIds[id] == nil then
				problem(label, ("'%s' is missing from pieces"):format(id))
			end
		end
		for _, source in SOURCES do
			if not sourcesUsed[source] then
				problem(label, ("no piece comes from %s (section 7 lists all four sources)"):format(source))
			end
		end
		local labPiece: string? = nil
		for _, piece in set.pieces do
			if piece.source == "LAB" then
				labPiece = piece.id
			end
		end
		if labPiece ~= nil then
			if Loot.lastAttackBonus[set.floor] ~= labPiece then
				problem(
					label,
					("loot.lastAttackBonus[%d] is '%s', the set's LAB piece is '%s'"):format(
						set.floor,
						tostring(Loot.lastAttackBonus[set.floor]),
						labPiece
					)
				)
			end
			local boss = Bosses.forFloor(set.floor)
			if boss ~= nil and boss.lab ~= labPiece then
				problem(
					label,
					("floor boss %s gives '%s', the set's LAB piece is '%s'"):format(boss.id, boss.lab, labPiece)
				)
			end
		end

		-- Recipe
		if set.recipe.result ~= set.weapon then
			problem(label, "the smith recipe forges the set weapon")
		end
		if Loot.items[set.recipe.ingot] == nil then
			problem(label, ("recipe ingot '%s' is not in loot items"):format(set.recipe.ingot))
		end
		local ingotListed = false
		for _, entry in set.recipe.materials do
			if Loot.items[entry.item] == nil then
				problem(label, ("recipe material '%s' is not in loot items"):format(entry.item))
			end
			if entry.item == set.recipe.ingot then
				ingotListed = true
			end
		end
		if not ingotListed then
			problem(label, "the recipe materials must include the ingot")
		end

		-- Helpers agree with the data
		if not Apex.isComplete(Apex.pieceIds(set.floor), set.floor) then
			problem(label, "Apex.isComplete rejects the set's own pieces")
		end
	end

	return problems
end

return validate
