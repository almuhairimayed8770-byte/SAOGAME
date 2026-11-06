--!strict
--[[
	Floors (section 5): floors 1 to 25 as rows, the anatomy every floor shares, and the twelve
	Floor Generator biome kits. Floors 26 to 100 are assembled from a kit at server start
	(phase 6) and have no row here; story floors and every fifth floor override the generator.

	Boss ids are the PascalCase first proper name of the section 5 boss ("Grolak, Kobold
	Warlord" -> "Grolak") and must match the keys of bosses.luau; `bossName` is the display name.
	Every number is a tunable: distances are studs, times are stated per key.
]]

export type BiomeKit =
	"plains"
	| "marsh"
	| "forest"
	| "coast"
	| "cave"
	| "savanna"
	| "snow"
	| "twilight"
	| "volcanic"
	| "canyon"
	| "jungle"
	| "ruin"

export type FloorDef = {
	number: number,
	name: string,
	biome: BiomeKit, -- the generator kit whose lighting and creature roster the floor uses
	feel: string, -- the section 5 "biome and feel" text, for the level designer
	town: string, -- main town (safe zone) name
	boss: string, -- boss id in bosses.luau
	bossName: string, -- boss display name for the name card
	haven: boolean, -- every fifth floor: bigger town, sparse fields, quarter-mark raid
	settlement: boolean, -- a living floor (every Haven, plus Mirrorlake)
	bossNote: string?,
}

local function floor(
	number: number,
	name: string,
	biome: BiomeKit,
	feel: string,
	town: string,
	boss: string,
	bossName: string,
	bossNote: string?
): FloorDef
	local haven = number % 5 == 0
	return {
		number = number,
		name = name,
		biome = biome,
		feel = feel,
		town = town,
		boss = boss,
		bossName = bossName,
		haven = haven,
		settlement = haven or number == 22,
		bossNote = bossNote,
	}
end

local Floors = {
	--- The twelve generator kits (section 5). Each holds a town prefab, three village prefabs,
	--- eight field chunks, two mini-dungeon layouts, a Labyrinth layout and a creature roster.
	biomeKits = {
		"plains",
		"marsh",
		"forest",
		"coast",
		"cave",
		"savanna",
		"snow",
		"twilight",
		"volcanic",
		"canyon",
		"jungle",
		"ruin",
	} :: { BiomeKit },

	kitContents = {
		townPrefabs = 1,
		villagePrefabs = 3,
		fieldChunks = 8,
		miniDungeonLayouts = 2,
		labyrinthLayouts = 1,
	},

	--- Anatomy of a floor (section 5), shared by hand-built and generated floors.
	anatomy = {
		discDiameterMin = 2000,
		discDiameterMax = 4000,
		floor1DiscDiameter = 3000,
		ceilingHeight = 350, -- the lit stone underside of the floor above
		dayLengthMinutes = 48, -- one in-game day in real minutes
		nightSpawnMultiplier = 1.5,
		bloodMoonChancePerNight = 0.005,
		fieldBossRespawnMinutes = 90,
		packRespawnMinutes = 6,
		labyrinthLevelsMin = 8,
		labyrinthLevelsMax = 12,
		labyrinthGateShardBlockedTopLevels = 3, -- no Gate Shards on the top three Labyrinth levels (section 9)
		homesMin = 10,
		homesMax = 40,
		villagesMin = 2,
		villagesMax = 4,
		miniDungeonsMin = 2,
		miniDungeonsMax = 3,
		miniDungeonMinutesMin = 10, -- for a party of four
		miniDungeonMinutesMax = 20,
		threatBands = { "Verge", "Reach", "Blight" },
		generatorBudgetSeconds = 8, -- a generated floor must build in under this on the server
		clearAnnounceSeconds = 5, -- a floor clear reaches every server within this
		firstFloor = 1,
		topFloor = 100,
		handAuthoredThrough = 25,
		havenEvery = 5,
		storyFloors = { 55, 74, 75, 100 },
	},

	list = {
		floor(
			1,
			"Firstlight Plains",
			"plains",
			"Bright green plains, oak stands, cobbled roads",
			"Firstlight",
			"Grolak",
			"Grolak, Kobold Warlord"
		),
		floor(
			2,
			"Thornmere",
			"marsh",
			"Reed marsh, boardwalks, dusk fog",
			"Marrow",
			"MirefangMatriarch",
			"Mirefang Matriarch",
			"giant wasp"
		),
		floor(
			3,
			"Emberwood",
			"forest",
			"Autumn forest, red leaves, fallen logs",
			"Duskwatch",
			"AshbarkTreant",
			"Ashbark Treant"
		),
		floor(
			4,
			"Saltwind Coast",
			"coast",
			"Sea cliffs, gull rocks, a lighthouse",
			"Gullhaven",
			"TidecallerSerpent",
			"Tidecaller Serpent"
		),
		floor(
			5,
			"Vaelric Highlands",
			"plains",
			"Hills, terraced farms, wind",
			"Vaelric",
			"IronBulwarkGolem",
			"Iron Bulwark Golem"
		),
		floor(
			6,
			"Hollowdeep",
			"cave",
			"Cave floor, bioluminescent fungus, no sky",
			"Lanternfall",
			"PaleCrawler",
			"Pale Crawler"
		),
		floor(
			7,
			"Sunbreak Savanna",
			"savanna",
			"Dry grass, acacia, heat shimmer",
			"Dunmoor",
			"KhaganOfHooves",
			"Khagan of Hooves",
			"minotaur"
		),
		floor(
			8,
			"Frostvein",
			"snow",
			"Snowfield, frozen river, pine",
			"Greymantle",
			"RimeclawBehemoth",
			"Rimeclaw Behemoth"
		),
		floor(
			9,
			"Gloamwood",
			"twilight",
			"Twilight forest, fireflies, mist",
			"Nightshade Crossing",
			"HexenStag",
			"Hexen Stag"
		),
		floor(
			10,
			"Castellan's Reach",
			"plains",
			"Citadel floor, white walls, banners",
			"Highwall",
			"WardensKnight",
			"The Warden's Knight"
		),
		floor(11, "Fenmoor Reaches", "marsh", "Peat bog, will-o-wisps", "Sedge", "Bogmother", "Bogmother"),
		floor(
			12,
			"Cinderspire Foothills",
			"volcanic",
			"Volcanic rock, ash, lava seams",
			"Kilnrest",
			"Magmaw",
			"Magmaw"
		),
		floor(
			13,
			"Thundertop Mesas",
			"canyon",
			"Red mesas, canyons, storms",
			"Rookery",
			"StormhornRoc",
			"Stormhorn Roc"
		),
		floor(
			14,
			"Lantern Lake",
			"coast",
			"Lakeside town, lantern festivals",
			"Lantern",
			"DrownedChoir",
			"Drowned Choir"
		),
		floor(
			15,
			"Aurelian Terraces",
			"plains",
			"Vineyards, gold evening light",
			"Aurelia",
			"VintnersColossus",
			"Vintner's Colossus"
		),
		floor(
			16,
			"Ironhollow Quarry",
			"canyon",
			"Open-pit mine, scaffolds, rust",
			"Strake",
			"Overseer",
			"The Overseer",
			"clockwork"
		),
		floor(
			17,
			"Mistral Steppe",
			"savanna",
			"Windswept grass, nomad camps",
			"Khoran",
			"WindriderWarlord",
			"Windrider Warlord"
		),
		floor(
			18,
			"Verdigris Ruins",
			"jungle",
			"Jungle over a drowned city",
			"Tendril",
			"StoneIdolOfVerdigris",
			"Stone Idol of Verdigris"
		),
		floor(19, "Hallowed Pines", "snow", "Snowy cathedral forest, bells", "Vespers", "BellWarden", "Bell Warden"),
		floor(
			20,
			"Kingsmoor",
			"plains",
			"Royal moors, castles, tournament grounds",
			"Kingsmoor",
			"PaleKing",
			"The Pale King"
		),
		floor(
			21,
			"Blackreach Marsh",
			"marsh",
			"Dead trees, black water, Hollow Grin territory",
			"Gallows Fen",
			"CarrionHydra",
			"Carrion Hydra"
		),
		floor(
			22,
			"Mirrorlake",
			"forest",
			"Forest, lake, cabins, the quiet floor",
			"Mirrorlake",
			"Lakewarden",
			"Lakewarden",
			"optional, peaceful unless provoked"
		),
		floor(
			23,
			"Shalewind Gorge",
			"canyon",
			"Slot canyons, rope bridges, wind",
			"Cleft",
			"GorgefangWyrm",
			"Gorgefang Wyrm"
		),
		floor(
			24,
			"Oathfire Plateau",
			"volcanic",
			"High plateau, braziers, ancient arena",
			"Pyrehold",
			"OathbreakerKnight",
			"Oathbreaker Knight"
		),
		floor(
			25,
			"Argent Crown",
			"ruin",
			"Silver spires, the first quarter-mark",
			"Argentis",
			"SilverSovereign",
			"The Silver Sovereign",
			"the raid where the Legion breaks"
		),
	} :: { FloorDef },
}

local byNumber: { [number]: FloorDef } = {}
for _, def in Floors.list do
	byNumber[def.number] = def
end

--- The floor row for a hand-authored floor number; errors on a floor that has no row.
function Floors.get(number: number): FloorDef
	local def = byNumber[number]
	if def == nil then
		error(("floors: no row for floor %s"):format(tostring(number)))
	end
	return def
end

--- The floor row if one exists (generated floors have none).
function Floors.find(number: number): FloorDef?
	return byNumber[number]
end

--- True on every fifth floor (5, 10, 15...), hand-authored or generated.
function Floors.isHaven(number: number): boolean
	return number % Floors.anatomy.havenEvery == 0
end

--- True on Havens and on Mirrorlake: floors built for living, not fighting.
function Floors.isSettlement(number: number): boolean
	local def = byNumber[number]
	if def then
		return def.settlement
	end
	return Floors.isHaven(number)
end

--- True when a floor is hand-authored rather than generated: 1 to 25, Havens and story floors.
function Floors.isHandAuthored(number: number): boolean
	if number <= Floors.anatomy.handAuthoredThrough then
		return true
	end
	if Floors.isHaven(number) then
		return true
	end
	return table.find(Floors.anatomy.storyFloors, number) ~= nil
end

--- True when the kit name is one of the twelve generator kits.
function Floors.isBiomeKit(name: string): boolean
	return table.find(Floors.biomeKits, name :: any) ~= nil
end

return Floors
