--!strict
--[[
	Playground validator (section 20, D-013): the field, rim, ceiling and kill volume numbers are
	sane; every spawn sits on the field inside its ring (boars 40..120, kobolds 60..100); the
	loadout is level 1 with proficiency that unlocks the four Phase 0 Arts; the lighting preset
	exists. Cross-checks when the sibling tables exist: spawn ids in enemies.luau, the weapon in
	weapons.luau, the armor pieces in armor.luau, the Art slots in arts.luau.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local FIELD_RADIUS = 200
local CEILING = 350
local BOAR = "FrenzyBoar"
local KOBOLD = "KoboldAxeman"
local BOAR_PACKS = 3
local KOBOLD_SPAWNS = 2

local function tryLoad(ctx: Context, path: string): any
	local ok, result = pcall(ctx.load, path)
	if ok and typeof(result) == "table" then
		return result
	end
	return nil
end

-- Sibling tables keep their rows under `rows` (keyed by id); fall back to the module itself.
local function rowsOf(module: any): any
	if typeof(module) == "table" and typeof(module.rows) == "table" then
		return module.rows
	end
	return module
end

local function hasKey(module: any, id: string): boolean
	local collection = rowsOf(module)
	if typeof(collection) ~= "table" then
		return false
	end
	if collection[id] ~= nil then
		return true
	end
	for _, row in collection do
		if typeof(row) == "table" and row.id == id then
			return true
		end
	end
	return false
end

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end

	local Playground = ctx.load("src/shared/data/playground")
	local Lighting = ctx.load("src/shared/data/lighting")

	if Playground.fieldRadius ~= FIELD_RADIUS then
		problem("playground.fieldRadius must be %d (the 400-stud field)", FIELD_RADIUS)
	end
	if Playground.ceilingHeight ~= CEILING then
		problem("playground.ceilingHeight must be %d", CEILING)
	end
	if typeof(Playground.killVolume) ~= "table" or Playground.killVolume.y >= 0 then
		problem("playground.killVolume.y must be below the field")
	end
	if typeof(Lighting.biomes[Playground.lightingPreset]) ~= "table" then
		problem("playground.lightingPreset '%s' is not in lighting.luau", tostring(Playground.lightingPreset))
	end

	local rim = Playground.rim
	if typeof(rim) ~= "table" then
		problem("playground.rim is missing")
	else
		for _, field in
			{
				"railingHeight",
				"postSpacing",
				"cloudRingDrop",
				"cloudCount",
				"pillarCount",
				"pillarDistance",
				"pillarHeight",
			}
		do
			if typeof(rim[field]) ~= "number" or rim[field] <= 0 then
				problem("playground.rim.%s must be a positive number", field)
			end
		end
		if rim.cloudRingDrop ~= 200 then
			problem("playground.rim.cloudRingDrop must be 200 studs below the field (section 11)")
		end
		if typeof(rim.pillarDistance) == "number" and rim.pillarDistance <= Playground.fieldRadius then
			problem("playground.rim.pillarDistance must be outside the field")
		end
		if typeof(rim.pillarHeight) == "number" and rim.pillarHeight < Playground.ceilingHeight then
			problem("playground.rim.pillarHeight must reach the ceiling")
		end
	end

	if typeof(Playground.respawnSeconds) ~= "number" or Playground.respawnSeconds <= 0 then
		problem("playground.respawnSeconds must be positive")
	end

	-- Spawns
	local counts: { [string]: number } = {}
	for index, spawn in ipairs(Playground.spawns) do
		local label = ("playground.spawns[%d]"):format(index)
		if typeof(spawn.enemy) ~= "string" then
			problem("%s: enemy must be an enemy id", label)
			continue
		end
		counts[spawn.enemy] = (counts[spawn.enemy] or 0) + 1
		local position = spawn.position
		if typeof(position) ~= "table" or #position ~= 3 then
			problem("%s: position must be {x, y, z}", label)
			continue
		end
		if position[2] ~= 0 then
			problem("%s: spawns sit on the field surface (y = 0)", label)
		end
		local distance = Playground.distanceFromCenter(position)
		if distance >= Playground.fieldRadius then
			problem("%s: position is off the field (%.0f studs out)", label, distance)
		end
		local ring = Playground.ringFor(spawn.enemy)
		if ring == nil then
			problem("%s: no spawn ring for '%s'", label, spawn.enemy)
		elseif distance < ring.min or distance > ring.max then
			problem("%s: %s at %.0f studs is outside its ring %d..%d", label, spawn.enemy, distance, ring.min, ring.max)
		end
		if typeof(spawn.packSize) ~= "table" or spawn.packSize.min < 1 or spawn.packSize.max < spawn.packSize.min then
			problem("%s: packSize must be {min >= 1, max >= min}", label)
		end
		if typeof(spawn.facing) ~= "number" then
			problem("%s: facing must be a number of degrees", label)
		end
	end
	if (counts[BOAR] or 0) ~= BOAR_PACKS then
		problem("playground needs %d %s packs (got %d)", BOAR_PACKS, BOAR, counts[BOAR] or 0)
	end
	if (counts[KOBOLD] or 0) ~= KOBOLD_SPAWNS then
		problem("playground needs %d %s spawns (got %d)", KOBOLD_SPAWNS, KOBOLD, counts[KOBOLD] or 0)
	end
	local rings = Playground.spawnRings
	if rings[BOAR] == nil or rings[BOAR].min ~= 40 or rings[BOAR].max ~= 120 then
		problem("playground.spawnRings.%s must be 40..120", BOAR)
	end
	if rings[KOBOLD] == nil or rings[KOBOLD].min ~= 60 or rings[KOBOLD].max ~= 100 then
		problem("playground.spawnRings.%s must be 60..100", KOBOLD)
	end

	-- Loadout
	local loadout = Playground.loadout
	if loadout.level ~= 1 or loadout.str ~= 10 or loadout.agi ~= 10 then
		problem("playground.loadout must be level 1 with STR 10 and AGI 10")
	end
	if typeof(loadout.proficiency) ~= "table" or loadout.proficiency.OneHandedSword ~= 150 then
		problem("playground.loadout.proficiency.OneHandedSword must be 150 (unlocks Sharp Nail)")
	end
	if loadout.weapon ~= "TrialistSword" then
		problem("playground.loadout.weapon must be TrialistSword")
	end
	if typeof(loadout.armor) ~= "table" or next(loadout.armor) == nil then
		problem("playground.loadout.armor must hold the Trialist set")
	end
	if typeof(loadout.artSlots) ~= "table" or #loadout.artSlots ~= 4 then
		problem("playground.loadout.artSlots must list the four Phase 0 Arts")
	end

	-- Cross-checks against sibling tables when they exist.
	local Enemies = tryLoad(ctx, "src/shared/data/enemies")
	if Enemies then
		for enemyId in counts do
			if not hasKey(Enemies, enemyId) then
				problem("playground spawn enemy '%s' is not in enemies.luau", enemyId)
			end
		end
	end
	local Weapons = tryLoad(ctx, "src/shared/data/weapons")
	if Weapons and not hasKey(Weapons, loadout.weapon) then
		problem("playground loadout weapon '%s' is not in weapons.luau", tostring(loadout.weapon))
	end
	local Armor = tryLoad(ctx, "src/shared/data/armor")
	if Armor and typeof(loadout.armor) == "table" then
		for slot, armorId in loadout.armor do
			if not hasKey(Armor, armorId) then
				problem("playground loadout armor %s '%s' is not in armor.luau", tostring(slot), tostring(armorId))
			end
		end
	end
	local Arts = tryLoad(ctx, "src/shared/data/arts")
	if Arts and typeof(loadout.artSlots) == "table" then
		local artRows = rowsOf(Arts)
		for _, artId in loadout.artSlots do
			local art = artRows[artId]
			if typeof(art) ~= "table" then
				for _, row in artRows do
					if typeof(row) == "table" and row.id == artId then
						art = row
					end
				end
			end
			if typeof(art) ~= "table" then
				problem("playground loadout Art '%s' is not in arts.luau", tostring(artId))
			else
				local proficiency = loadout.proficiency[art.weapon] or 0
				if typeof(art.unlock) == "number" and art.unlock > proficiency then
					problem(
						"playground loadout Art '%s' needs proficiency %s but the loadout has %s",
						tostring(artId),
						tostring(art.unlock),
						tostring(proficiency)
					)
				end
			end
		end
	end

	return problems
end
