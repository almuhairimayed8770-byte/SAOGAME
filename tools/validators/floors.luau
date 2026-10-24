--!strict
--[[
	Floors validator: floors.luau holds floors 1 to 25 in order with unique names, towns and
	PascalCase boss ids, Haven flags on every fifth floor, the settlement flag on Mirrorlake,
	a biome from the twelve kits, and sane anatomy ranges. When bosses.luau exists, every
	launch-floor boss id (floors 1 to 10) must be a key in it; when apex.luau exists, floor 1
	must have an Apex set.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local HAND_AUTHORED = 25
local LAUNCH_FLOORS = 10
local MIRRORLAKE = 22

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end

	local Floors = ctx.load("src/shared/data/floors")
	local anatomy = Floors.anatomy

	if #Floors.biomeKits ~= 12 then
		problem("floors.biomeKits must list the twelve generator kits (got %d)", #Floors.biomeKits)
	end
	local kitSet: { [string]: boolean } = {}
	for _, kit in Floors.biomeKits do
		if kitSet[kit] then
			problem("floors.biomeKits lists '%s' twice", kit)
		end
		kitSet[kit] = true
	end

	if #Floors.list ~= HAND_AUTHORED then
		problem("floors.list must hold %d floors (got %d)", HAND_AUTHORED, #Floors.list)
	end
	local names: { [string]: boolean } = {}
	local towns: { [string]: boolean } = {}
	local bosses: { [string]: boolean } = {}
	for index, def in ipairs(Floors.list) do
		local label = ("floor %s"):format(tostring(def.number))
		if def.number ~= index then
			problem("floors.list[%d] has number %s (rows must be in order)", index, tostring(def.number))
		end
		for _, field in { "name", "feel", "town", "boss", "bossName" } do
			if typeof(def[field]) ~= "string" or def[field] == "" then
				problem("%s: %s must be a non-empty string", label, field)
			end
		end
		if names[def.name] then
			problem("%s: duplicate name '%s'", label, def.name)
		end
		names[def.name] = true
		if towns[def.town] then
			problem("%s: duplicate town '%s'", label, def.town)
		end
		towns[def.town] = true
		if bosses[def.boss] then
			problem("%s: duplicate boss id '%s'", label, def.boss)
		end
		bosses[def.boss] = true
		if typeof(def.boss) == "string" and not def.boss:match("^%u[%w]*$") then
			problem("%s: boss id '%s' must be PascalCase with no spaces", label, def.boss)
		end
		if not kitSet[def.biome] then
			problem("%s: biome '%s' is not one of the twelve kits", label, tostring(def.biome))
		end
		local expectHaven = def.number % anatomy.havenEvery == 0
		if def.haven ~= expectHaven then
			problem("%s: haven must be %s", label, tostring(expectHaven))
		end
		if def.number == MIRRORLAKE and def.settlement ~= true then
			problem("%s: Mirrorlake must be a settlement floor", label)
		end
		if def.settlement ~= (expectHaven or def.number == MIRRORLAKE) then
			problem("%s: settlement flag is wrong", label)
		end
		if Floors.get(def.number) ~= def then
			problem("%s: Floors.get does not return the row", label)
		end
	end

	-- Anatomy
	if
		not (
			anatomy.discDiameterMin <= anatomy.floor1DiscDiameter
			and anatomy.floor1DiscDiameter <= anatomy.discDiameterMax
		)
	then
		problem("floors.anatomy: Floor 1 disc must sit inside the disc range")
	end
	if anatomy.ceilingHeight <= 0 then
		problem("floors.anatomy.ceilingHeight must be positive")
	end
	if anatomy.dayLengthMinutes <= 0 then
		problem("floors.anatomy.dayLengthMinutes must be positive")
	end
	if anatomy.nightSpawnMultiplier < 1 then
		problem("floors.anatomy.nightSpawnMultiplier must be at least 1")
	end
	if anatomy.bloodMoonChancePerNight <= 0 or anatomy.bloodMoonChancePerNight >= 1 then
		problem("floors.anatomy.bloodMoonChancePerNight must be a fraction in (0, 1)")
	end
	if anatomy.labyrinthLevelsMin > anatomy.labyrinthLevelsMax or anatomy.labyrinthLevelsMin < 1 then
		problem("floors.anatomy: Labyrinth level range is inverted")
	end
	if anatomy.fieldBossRespawnMinutes <= anatomy.packRespawnMinutes then
		problem("floors.anatomy: the field boss must respawn slower than packs")
	end
	if anatomy.homesMin > anatomy.homesMax or anatomy.villagesMin > anatomy.villagesMax then
		problem("floors.anatomy: an inverted min/max range")
	end
	if
		anatomy.miniDungeonsMin > anatomy.miniDungeonsMax
		or anatomy.miniDungeonMinutesMin > anatomy.miniDungeonMinutesMax
	then
		problem("floors.anatomy: an inverted mini-dungeon range")
	end
	if #anatomy.threatBands ~= 3 then
		problem("floors.anatomy.threatBands must hold Verge, Reach and Blight")
	end

	-- Cross-check bosses.luau for the launch floors.
	local okBosses, Bosses = pcall(ctx.load, "src/shared/data/bosses")
	if okBosses and typeof(Bosses) == "table" then
		local bossIds: { [string]: boolean } = {}
		local rows = if typeof(Bosses.rows) == "table" then Bosses.rows else Bosses
		for key, row in rows do
			if typeof(row) == "table" and typeof(row.id) == "string" then
				bossIds[row.id] = true
			elseif typeof(key) == "string" then
				bossIds[key] = true
			end
		end
		for _, def in ipairs(Floors.list) do
			if def.number <= LAUNCH_FLOORS and not bossIds[def.boss] then
				problem("floor %d: boss id '%s' is not in bosses.luau", def.number, def.boss)
			end
		end
	end

	-- Cross-check apex.luau for floor 1.
	local okApex, Apex = pcall(ctx.load, "src/shared/data/apex")
	if okApex and typeof(Apex) == "table" then
		local sets = if typeof(Apex.sets) == "table"
			then Apex.sets
			elseif typeof(Apex.rows) == "table" then Apex.rows
			else Apex
		local found = false
		for key, row in sets do
			if key == 1 or (typeof(row) == "table" and row.floor == 1) then
				found = true
			end
		end
		if not found then
			problem("apex.luau has no Apex set for floor 1")
		end
	end

	return problems
end
