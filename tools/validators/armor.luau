--!strict
--[[
	Validates src/shared/data/armor.luau: ArmorDef fields and types, ids match keys, slots and
	rarities are known, weight classes are consistent (agiPenalty from the class, weight under its
	cap), the Trialist cloth set covers its five slots, and the Mantle of Last Light is the floor 1
	Apex over-layer.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local SLOTS = { "Chest", "Legs", "Hands", "Boots", "Head", "OverLayer", "Accessory" }
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Apex" }
local CLASSES = { "Light", "Medium", "Heavy" }
local SOURCES = { "LAB", "FieldBoss", "MiniDungeon", "Smith", "Drop", "Vendor" }

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Check = ctx.load("src/shared/util/Check")
	local Armor = ctx.load("src/shared/data/armor")

	local function problem(id: string, message: string)
		table.insert(problems, ("armor.%s: %s"):format(id, message))
	end

	local schema = Check.interface({
		id = Check.string(64),
		name = Check.string(64),
		slot = Check.literal(table.unpack(SLOTS)),
		rarity = Check.literal(table.unpack(RARITIES)),
		defense = Check.number(0, 10000),
		weight = Check.number(0, 50),
		agiPenalty = Check.number(0, 50),
		durability = Check.number(1),
		floor = Check.integer(1, 100),
		set = Check.optional(Check.string(32)),
		weightClass = Check.literal(table.unpack(CLASSES)),
		source = Check.optional(Check.literal(table.unpack(SOURCES))),
		description = Check.optional(Check.string(200)),
		bonus = Check.optional(Check.map(Check.string(32), Check.number(-1, 1))),
	})

	for _, class in CLASSES do
		if Armor.weightClasses[class] == nil then
			problem("weightClasses", ("missing class '%s'"):format(class))
		end
	end

	for key, piece in Armor.rows do
		local ok, message = schema(piece)
		if not ok then
			problem(tostring(key), message or "invalid row")
			continue
		end
		if piece.id ~= key then
			problem(key, ("id '%s' does not match its key"):format(piece.id))
		end
		local class = Armor.weightClasses[piece.weightClass]
		if class ~= nil then
			if piece.agiPenalty ~= class.agiPenalty then
				problem(
					key,
					("%s pieces cost %d AGI, not %s"):format(
						piece.weightClass,
						class.agiPenalty,
						tostring(piece.agiPenalty)
					)
				)
			end
			if piece.weight > class.maxWeight then
				problem(
					key,
					("weight %s exceeds the %s cap %s"):format(piece.weight, piece.weightClass, class.maxWeight)
				)
			end
		end
		if piece.slot == "Accessory" and piece.defense ~= 0 then
			problem(key, "accessories carry bonuses, not defense")
		end
		if piece.rarity == "Apex" and piece.set == nil then
			problem(key, "Apex pieces belong to a set")
		end
		if piece.rarity == "Apex" and (piece.source == "Drop" or piece.source == "Vendor") then
			problem(key, "Apex pieces never drop or sell")
		end
	end

	-- Trialist cloth set
	for _, slot in { "Chest", "Legs", "Hands", "Boots", "Head" } do
		local id = Armor.trialistSet[slot]
		local piece = if id then Armor.rows[id] else nil
		if piece == nil then
			problem("trialistSet", ("no piece for slot %s"):format(slot))
		else
			if piece.slot ~= slot then
				problem(id, ("trialist piece for %s is a %s"):format(slot, piece.slot))
			end
			if piece.rarity ~= "Common" or piece.floor ~= 1 or piece.weightClass ~= "Light" then
				problem(id, "the Trialist cloth set is Common, floor 1, Light")
			end
		end
	end

	local mantle = Armor.rows.MantleOfLastLight
	if mantle == nil then
		problem("MantleOfLastLight", "missing (the floor 1 Last Attack Bonus coat)")
	else
		if mantle.slot ~= "OverLayer" or mantle.rarity ~= "Apex" or mantle.floor ~= 1 or mantle.set ~= "Floor1Apex" then
			problem("MantleOfLastLight", "must be an Apex OverLayer on floor 1 in set Floor1Apex")
		end
		if mantle.source ~= "LAB" then
			problem("MantleOfLastLight", "source must be LAB")
		end
	end

	return problems
end

return validate
