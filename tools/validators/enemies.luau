--!strict
--[[
	Validates src/shared/data/enemies.luau: EnemyDef fields and types, PascalCase ids matching
	keys, a known archetype, a rig id (in rigs.luau or declared in Enemies.placeholderRigs), at
	least one attack, every wind-up within combat's telegraph bounds, valid shatter kinds, a loot
	table that exists, Art ids that exist, at least three regular enemies and one field boss per
	floor 1..10, and the Phase 0 pair (Frenzy Boar, Kobold Axeman) on real rigs with their clips.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local ARCHETYPES =
	{ "Charger", "Brute", "Skirmisher", "Lancer", "Swarm", "Guard", "CasterBeast", "Stalker", "WardenConstruct" }
local BANDS = { "Verge", "Reach", "Blight" }
local SHATTERS = { "Beast", "Construct", "Plant", "Humanoid", "Boss" }
local TELEGRAPHS = { "Normal", "Unblockable", "GuardBreak" }
local STATUSES = { "Bleed", "Poison", "Paralysis", "Stun", "Burn", "Freeze" }
local SHAPES = { "Line", "Cone", "Circle" }
local VARIANTS = { "Elite", "Night", "Gilded" }

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Check = ctx.load("src/shared/util/Check")
	local Combat = ctx.load("src/shared/data/combat")
	local Rigs = ctx.load("src/shared/data/rigs")
	local Arts = ctx.load("src/shared/data/arts")
	local Loot = ctx.load("src/shared/data/loot")
	local Enemies = ctx.load("src/shared/data/enemies")

	local function problem(id: string, message: string)
		table.insert(problems, ("enemies.%s: %s"):format(id, message))
	end

	local attackSchema = Check.interface({
		id = Check.string(48),
		name = Check.string(48),
		telegraph = Check.literal(table.unpack(TELEGRAPHS)),
		windUp = Check.number(0, 10),
		strike = Check.number(0, 10),
		recovery = Check.number(0, 10),
		multiplier = Check.number(0, 20),
		gaugeDamage = Check.number(0, 1000),
		reach = Check.number(0, 200),
		arc = Check.number(0, 360),
		clip = Check.string(48),
		groundShape = Check.optional(Check.literal(table.unpack(SHAPES))),
		status = Check.optional(Check.literal(table.unpack(STATUSES))),
	})

	local schema = Check.interface({
		id = Check.string(48),
		name = Check.string(64),
		archetype = Check.literal(table.unpack(ARCHETYPES)),
		skin = Check.string(48),
		floor = Check.integer(1, 100),
		tier = Check.integer(1, 100),
		band = Check.literal(table.unpack(BANDS)),
		hp = Check.number(1),
		attack = Check.number(0),
		defense = Check.number(0),
		guardGauge = Check.number(1),
		guardRegenPerSecond = Check.number(0, 1),
		moveSpeed = Check.number(0, 100),
		aggroRange = Check.number(0, 500),
		leashRange = Check.number(0, 1000),
		attacks = Check.array(attackSchema, 8),
		shatter = Check.literal(table.unpack(SHATTERS)),
		xp = Check.number(1),
		lootTable = Check.string(48),
		elite = Check.optional(Check.boolean),
		night = Check.optional(Check.boolean),
		packSize = Check.optional(Check.integer(1, 12)),
		arts = Check.optional(Check.array(Check.string(64), 16)),
		mirrorShield = Check.optional(Check.boolean),
		fieldBoss = Check.optional(Check.boolean),
		gilded = Check.optional(Check.boolean),
		guaranteedRare = Check.optional(Check.boolean),
		variant = Check.optional(Check.literal(table.unpack(VARIANTS))),
		description = Check.optional(Check.string(240)),
	})

	local placeholderSet: { [string]: boolean } = {}
	for _, rigId in Enemies.placeholderRigs do
		placeholderSet[rigId] = true
		if Rigs[rigId] ~= nil then
			problem("placeholderRigs", ("'%s' is in rigs.luau now; remove it from placeholderRigs"):format(rigId))
		end
	end
	local placeholderUsed: { [string]: boolean } = {}

	local regularPerFloor: { [number]: number } = {}
	local fieldBossPerFloor: { [number]: number } = {}

	for key, def in Enemies.rows do
		local ok, message = schema(def)
		if not ok then
			problem(tostring(key), message or "invalid row")
			continue
		end
		if def.id ~= key then
			problem(key, ("id '%s' does not match its key"):format(def.id))
		end
		if not key:match("^%u[%w]*$") then
			problem(key, "id must be PascalCase")
		end
		if Rigs[def.skin] == nil then
			if placeholderSet[def.skin] then
				placeholderUsed[def.skin] = true
			else
				problem(key, ("rig '%s' is neither in rigs.luau nor in Enemies.placeholderRigs"):format(def.skin))
			end
		end
		if #def.attacks == 0 then
			problem(key, "needs at least one attack")
		end
		local attackIds: { [string]: boolean } = {}
		for _, attack in def.attacks do
			local label = key .. "." .. attack.id
			if attackIds[attack.id] then
				problem(label, "duplicate attack id")
			end
			attackIds[attack.id] = true
			if attack.windUp < Combat.telegraphMinWindUp then
				problem(
					label,
					("windUp %s is under the %s floor (hard rule)"):format(attack.windUp, Combat.telegraphMinWindUp)
				)
			end
			if attack.windUp > Combat.telegraphMaxWindUp then
				problem(label, ("windUp %s is over the %s ceiling"):format(attack.windUp, Combat.telegraphMaxWindUp))
			end
			if not attack.clip:match("^%u[%w]*$") then
				problem(label, "clip must be a PascalCase clip name (enemy/<rig>/<clip>)")
			end
			if attack.arc == 0 and attack.groundShape ~= nil and attack.groundShape ~= "Line" and attack.reach > 0 then
				problem(label, "an attack with arc 0 is a line")
			end
			if attack.multiplier > 0 and attack.reach <= 0 then
				problem(label, "a damaging attack needs reach")
			end
		end
		if Loot.tables[def.lootTable] == nil then
			problem(key, ("lootTable '%s' is not in loot.luau"):format(def.lootTable))
		elseif def.fieldBoss and not Loot.tables[def.lootTable].boss then
			problem(key, ("field boss loot table '%s' must be flagged boss"):format(def.lootTable))
		end
		if def.arts ~= nil then
			for _, artId in def.arts do
				if Arts.byId(artId) == nil then
					problem(key, ("art '%s' is not in arts.luau"):format(artId))
				end
			end
		end
		if def.tier ~= def.floor then
			problem(key, ("tier %d differs from floor %d"):format(def.tier, def.floor))
		end
		if def.guardRegenPerSecond ~= Combat.guardRegenPerSecond then
			problem(
				key,
				("guardRegenPerSecond %s is not the section 6 value %s"):format(
					def.guardRegenPerSecond,
					Combat.guardRegenPerSecond
				)
			)
		end
		if def.fieldBoss then
			fieldBossPerFloor[def.floor] = (fieldBossPerFloor[def.floor] or 0) + 1
			if not def.mirrorShield then
				problem(key, "field bosses carry a Mirror Shield")
			end
		else
			regularPerFloor[def.floor] = (regularPerFloor[def.floor] or 0) + 1
		end
		if def.elite and not def.mirrorShield then
			problem(key, "an always-Elite row carries a Mirror Shield")
		end
	end

	for rigId in placeholderSet do
		if not placeholderUsed[rigId] then
			problem("placeholderRigs", ("'%s' is listed but no row uses it"):format(rigId))
		end
	end

	for floor = 1, 10 do
		if (regularPerFloor[floor] or 0) < 3 then
			problem(
				("floor%d"):format(floor),
				("only %d regular enemies; the bestiary needs at least 3"):format(regularPerFloor[floor] or 0)
			)
		end
		if (fieldBossPerFloor[floor] or 0) ~= 1 then
			problem(
				("floor%d"):format(floor),
				("%d field bosses; section 9 has exactly one"):format(fieldBossPerFloor[floor] or 0)
			)
		end
	end

	-- Phase 0 pair: real rigs and the clips ARCHITECTURE.md requires.
	local phase0 = {
		FrenzyBoar = { rig = "Boar", archetype = "Charger", clip = "Charge", telegraph = "Normal", shape = "Line" },
		KoboldAxeman = {
			rig = "Kobold",
			archetype = "Brute",
			clip = "Overhead",
			telegraph = "GuardBreak",
			shape = "Cone",
		},
	}
	for id, expected in phase0 do
		local def = Enemies.rows[id]
		if def == nil then
			problem(id, "Phase 0 enemy is missing")
			continue
		end
		if def.skin ~= expected.rig or Rigs[expected.rig] == nil then
			problem(id, ("must use the %s rig from rigs.luau"):format(expected.rig))
		end
		if def.archetype ~= expected.archetype then
			problem(id, ("must be a %s"):format(expected.archetype))
		end
		if #def.attacks ~= 1 then
			problem(id, "Phase 0 enemies have exactly one attack (one clip each)")
		end
		local attack = def.attacks[1]
		if attack ~= nil then
			if attack.clip ~= expected.clip then
				problem(id, ("attack clip must be '%s'"):format(expected.clip))
			end
			if attack.telegraph ~= expected.telegraph or attack.groundShape ~= expected.shape then
				problem(id, ("attack must telegraph %s on a %s"):format(expected.telegraph, expected.shape))
			end
		end
	end

	return problems
end

return validate
