--!strict
--[[
	Apex sets (section 7). Every floor defines one best-in-slot set: a weapon, four armor pieces
	and an accessory. Wearing all six grants Apex status (the white edge-light) and, with Twin
	Fang, turns off the solo gate on that floor. Pieces come from that floor's Last Attack Bonus,
	its field boss, its mini-dungeon first-clear chests, and a smith recipe needing an ingot from
	the Labyrinth's deepest level. Apex pieces are never random drops.

	Phase 0 ships floor 1; later floors add rows in the same shape. Piece ids are weapon ids from
	weapons.luau and armor ids from armor.luau; the apex validator checks every one exists.
]]

local Types = require(script.Parent.Parent.types)

export type ApexSource = "LAB" | "FieldBoss" | "MiniDungeon" | "Smith"

export type ApexPiece = {
	id: string, -- weapon or armor id
	slot: Types.EquipSlot,
	source: ApexSource,
	sourceDetail: string, -- which boss, which dungeon, which recipe
}

export type ApexRecipe = {
	result: string, -- weapon id the smith forges
	ingot: string, -- loot item id from the Labyrinth's deepest level
	ingotSource: string,
	crowns: number,
	materials: { { item: string, count: number } },
}

export type ApexSet = {
	id: string, -- "Floor1Apex"; armor rows carry it in `set`
	floor: number,
	name: string,
	weapon: string,
	armor: { string }, -- four armor ids
	accessory: string,
	pieces: { ApexPiece }, -- all six with their sources
	recipe: ApexRecipe,
}

local Apex = {}

Apex.rules = {
	piecesPerSet = 6,
	fieldBossDropChance = 0.15, -- section 9: the field boss drops an Apex piece at 15%
	edgeLightToken = "ApexEdge", -- palette token for the Apex edge-light
	edgeLightUnderSkins = true, -- section 12: the edge-light survives transmog
	perFloor = true, -- floor 6's set is ordinary gear on floor 9
}

Apex.sets = {
	[1] = {
		id = "Floor1Apex",
		floor = 1,
		name = "Last Light",
		weapon = "DaybreakEdge",
		armor = { "MantleOfLastLight", "WarboarHideJerkin", "WarboarHideGreaves", "SentinelGrips" },
		accessory = "FirstlightSignet",
		pieces = {
			{
				id = "DaybreakEdge",
				slot = "Weapon",
				source = "Smith",
				sourceDetail = "Forged at any smith from a Deepstone Ingot mined on the Labyrinth's deepest level",
			},
			{
				id = "MantleOfLastLight",
				slot = "OverLayer",
				source = "LAB",
				sourceDetail = "Last Attack Bonus from Grolak, Kobold Warlord",
			},
			{
				id = "WarboarHideJerkin",
				slot = "Chest",
				source = "FieldBoss",
				sourceDetail = "Tusk, Warboar King (15% per kill)",
			},
			{
				id = "WarboarHideGreaves",
				slot = "Legs",
				source = "FieldBoss",
				sourceDetail = "Tusk, Warboar King (15% per kill)",
			},
			{
				id = "SentinelGrips",
				slot = "Hands",
				source = "MiniDungeon",
				sourceDetail = "First-clear chest of the Sentinel Crypt under the oak stands",
			},
			{
				id = "FirstlightSignet",
				slot = "Accessory",
				source = "MiniDungeon",
				sourceDetail = "First-clear chest of the Plains Ruin on the Reach road",
			},
		},
		recipe = {
			result = "DaybreakEdge",
			ingot = "DeepstoneIngot",
			ingotSource = "Ingot node on the Labyrinth's deepest level, guarded by a mini-boss",
			crowns = 2500,
			materials = {
				{ item = "DeepstoneIngot", count = 1 },
				{ item = "IngotOre", count = 6 },
				{ item = "BoarTusk", count = 4 },
			},
		},
	},
} :: { [number]: ApexSet }

local function toSet(equippedIds: { string } | { [string]: boolean }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for key, value in equippedIds :: { [any]: any } do
		if typeof(key) == "string" then
			if value then
				set[key] = true
			end
		elseif typeof(value) == "string" then
			set[value] = true
		end
	end
	return set
end

--- The Apex set of a floor, or nil when that floor has none authored yet.
function Apex.get(floor: number): ApexSet?
	return Apex.sets[floor]
end

--- The six piece ids of a floor's set (empty when none is authored).
function Apex.pieceIds(floor: number): { string }
	local set = Apex.sets[floor]
	if set == nil then
		return {}
	end
	local ids = {}
	for _, piece in set.pieces do
		table.insert(ids, piece.id)
	end
	return ids
end

--- Piece ids of the floor's set that are not in the equipped list (or set) of ids.
function Apex.missing(equippedIds: { string } | { [string]: boolean }, floor: number): { string }
	local equipped = toSet(equippedIds)
	local missing = {}
	for _, id in Apex.pieceIds(floor) do
		if not equipped[id] then
			table.insert(missing, id)
		end
	end
	return missing
end

--- True when every piece of the floor's Apex set is equipped. A floor with no set is never complete.
function Apex.isComplete(equippedIds: { string } | { [string]: boolean }, floor: number): boolean
	if Apex.sets[floor] == nil then
		return false
	end
	return #Apex.missing(equippedIds, floor) == 0
end

--- Floors that have an authored Apex set, ascending.
function Apex.floors(): { number }
	local floors = {}
	for floor in Apex.sets do
		table.insert(floors, floor)
	end
	table.sort(floors)
	return floors
end

return Apex
