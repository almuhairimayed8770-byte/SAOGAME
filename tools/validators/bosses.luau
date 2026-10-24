--!strict
--[[
	Validates src/shared/data/bosses.luau: BossDef fields and types, ids match keys, 4 to 6 bars,
	phases that start on bar 1 and ascend within the bar count, every phase attack inside the
	telegraph bounds, phase Art ids and summon ids that exist, phase weapons that are weapons.luau
	rows of the phase Arts' category, a Lockstep per boss, a boss loot table, a Last Attack Bonus
	that is a real item (or a declared pending one) and matches loot.lastAttackBonus, a Mirror
	Shield, and exactly one boss per floor 1..10.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local ARCHETYPES =
	{ "Charger", "Brute", "Skirmisher", "Lancer", "Swarm", "Guard", "CasterBeast", "Stalker", "WardenConstruct" }
local MECHANICS = { "Lockstep", "Summon", "Hazard", "WeaponSwap", "Shield", "Terrain", "Illusion" }
local TELEGRAPHS = { "Normal", "Unblockable", "GuardBreak" }
local STATUSES = { "Bleed", "Poison", "Paralysis", "Stun", "Burn", "Freeze" }
local SHAPES = { "Line", "Cone", "Circle" }

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Check = ctx.load("src/shared/util/Check")
	local Combat = ctx.load("src/shared/data/combat")
	local Arts = ctx.load("src/shared/data/arts")
	local Enemies = ctx.load("src/shared/data/enemies")
	local Loot = ctx.load("src/shared/data/loot")
	local Weapons = ctx.load("src/shared/data/weapons")
	local Armor = ctx.load("src/shared/data/armor")
	local Bosses = ctx.load("src/shared/data/bosses")

	local function problem(id: string, message: string)
		table.insert(problems, ("bosses.%s: %s"):format(id, message))
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

	local mechanicSchema = Check.interface({
		id = Check.string(48),
		name = Check.string(64),
		kind = Check.literal(table.unpack(MECHANICS)),
		description = Check.string(240),
		window = Check.optional(Check.number(0, 10)),
		targets = Check.optional(Check.integer(1, 8)),
		interval = Check.optional(Check.number(0, 600)),
		failure = Check.optional(Check.string(120)),
	})

	local summonSchema = Check.interface({ enemyId = Check.string(48), count = Check.integer(1, 12) })

	local phaseSchema = Check.interface({
		bar = Check.integer(1, 6),
		name = Check.string(64),
		summary = Check.string(400),
		archetype = Check.optional(Check.literal(table.unpack(ARCHETYPES))),
		attacks = Check.array(attackSchema, 8),
		arts = Check.optional(Check.array(Check.string(64), 16)),
		mechanics = Check.array(mechanicSchema, 8),
		summons = Check.optional(Check.array(summonSchema, 4)),
		weapon = Check.optional(Check.string(48)),
		attackSpeed = Check.optional(Check.number(0.5, 3)),
	})

	local schema = Check.interface({
		id = Check.string(48),
		name = Check.string(64),
		floor = Check.integer(1, 100),
		tier = Check.integer(1, 100),
		skin = Check.string(48),
		bars = Check.integer(Bosses.rules.minBars, Bosses.rules.maxBars),
		hpPerBar = Check.number(1),
		attack = Check.number(0),
		defense = Check.number(0),
		guardGauge = Check.number(1),
		guardRegenPerSecond = Check.number(0, 1),
		moveSpeed = Check.number(0, 100),
		phases = Check.array(phaseSchema, 6),
		guardPack = Check.array(summonSchema, 4),
		lockstep = mechanicSchema,
		enrage = Check.interface({ startSeconds = Check.number(1), damagePerMinute = Check.number(0.01, 1) }),
		mirrorShield = Check.boolean,
		lootTable = Check.string(48),
		lab = Check.string(64),
		shatter = Check.literal("Beast", "Construct", "Plant", "Humanoid", "Boss"),
		xp = Check.number(1),
		chamber = Check.optional(Check.string(240)),
	})

	local pendingLab: { [string]: boolean } = {}
	for _, id in Bosses.pendingLab do
		pendingLab[id] = true
		if Weapons.rows[id] ~= nil or Armor.rows[id] ~= nil then
			problem("pendingLab", ("'%s' exists now; remove it from pendingLab"):format(id))
		end
	end

	local perFloor: { [number]: number } = {}

	local function checkAttacks(label: string, attacks: { any })
		for _, attack in attacks do
			local attackLabel = label .. "." .. attack.id
			if attack.windUp < Combat.telegraphMinWindUp then
				problem(
					attackLabel,
					("windUp %s is under the %s floor (hard rule)"):format(attack.windUp, Combat.telegraphMinWindUp)
				)
			end
			if attack.windUp > Combat.telegraphMaxWindUp then
				problem(
					attackLabel,
					("windUp %s is over the %s ceiling"):format(attack.windUp, Combat.telegraphMaxWindUp)
				)
			end
			if not attack.clip:match("^%u[%w]*$") then
				problem(attackLabel, "clip must be a PascalCase clip name")
			end
		end
	end

	for key, def in Bosses.rows do
		local ok, message = schema(def)
		if not ok then
			problem(tostring(key), message or "invalid row")
			continue
		end
		if def.id ~= key then
			problem(key, ("id '%s' does not match its key"):format(def.id))
		end
		perFloor[def.floor] = (perFloor[def.floor] or 0) + 1
		if def.tier ~= def.floor then
			problem(key, ("tier %d differs from floor %d"):format(def.tier, def.floor))
		end
		if not def.mirrorShield then
			problem(key, "every boss carries a Mirror Shield (section 7)")
		end
		if def.shatter ~= "Boss" then
			problem(key, "bosses shatter with the Boss effect")
		end
		if def.lockstep.kind ~= "Lockstep" then
			problem(key, "lockstep mechanic must be of kind Lockstep")
		end
		if def.lockstep.targets == nil or def.lockstep.targets < 2 then
			problem(key, "a Lockstep needs at least two targets")
		end
		if
			def.enrage.startSeconds ~= Bosses.rules.enrageStartSeconds
			or def.enrage.damagePerMinute ~= Bosses.rules.enrageDamagePerMinute
		then
			problem(key, "enrage differs from the floor-boss template (8 minutes, +10% per minute)")
		end

		-- Phases
		if #def.phases == 0 then
			problem(key, "needs at least one phase")
		else
			if def.phases[1].bar ~= 1 then
				problem(key, "the first phase starts on bar 1")
			end
			local previousBar = 0
			for index, phase in def.phases do
				local label = key .. ".phase" .. index
				if phase.bar <= previousBar then
					problem(label, "phase bars must ascend")
				end
				previousBar = phase.bar
				if phase.bar > def.bars then
					problem(label, ("bar %d is past the boss's %d bars"):format(phase.bar, def.bars))
				end
				if #phase.attacks == 0 and (phase.arts == nil or #phase.arts == 0) then
					problem(label, "a phase needs attacks or Arts")
				end
				checkAttacks(label, phase.attacks)
				if phase.arts ~= nil then
					for _, artId in phase.arts do
						if Arts.byId(artId) == nil then
							problem(label, ("art '%s' is not in arts.luau"):format(artId))
						end
					end
				end
				if phase.weapon ~= nil then
					local weapon = Weapons.rows[phase.weapon]
					if weapon == nil then
						problem(label, ("weapon '%s' is not in weapons.luau"):format(phase.weapon))
					else
						for _, artId in phase.arts or {} do
							local art = Arts.byId(artId)
							if art ~= nil and art.weapon ~= weapon.category then
								problem(
									label,
									("art '%s' is a %s Art but the phase weapon '%s' is a %s"):format(
										artId,
										art.weapon,
										phase.weapon,
										weapon.category
									)
								)
							end
						end
					end
				end
				if phase.summons ~= nil then
					for _, summon in phase.summons do
						if Enemies.rows[summon.enemyId] == nil then
							problem(label, ("summon '%s' is not in enemies.luau"):format(summon.enemyId))
						end
					end
				end
				for _, mechanic in phase.mechanics do
					if mechanic.kind == "Lockstep" and (mechanic.window == nil or mechanic.targets == nil) then
						problem(label .. "." .. mechanic.id, "a Lockstep mechanic needs a window and targets")
					end
				end
			end
		end

		for _, summon in def.guardPack do
			if Enemies.rows[summon.enemyId] == nil then
				problem(key, ("guard pack '%s' is not in enemies.luau"):format(summon.enemyId))
			end
		end

		-- Loot and the Last Attack Bonus
		local lootTable = Loot.tables[def.lootTable]
		if lootTable == nil then
			problem(key, ("lootTable '%s' is not in loot.luau"):format(def.lootTable))
		elseif not lootTable.boss then
			problem(key, ("lootTable '%s' must be flagged boss"):format(def.lootTable))
		end
		local labExists = Weapons.rows[def.lab] ~= nil or Armor.rows[def.lab] ~= nil
		if not labExists and not pendingLab[def.lab] then
			problem(key, ("lab '%s' is not a weapon, an armor piece, or a declared pending item"):format(def.lab))
		end
		if labExists then
			local item = Weapons.rows[def.lab] or Armor.rows[def.lab]
			if item.rarity ~= "Apex" and item.rarity ~= "Legendary" then
				problem(key, "the Last Attack Bonus is always an Apex piece or a Legendary")
			end
			if Loot.lastAttackBonus[def.floor] ~= def.lab then
				problem(key, ("loot.lastAttackBonus[%d] should be '%s'"):format(def.floor, def.lab))
			end
		end
	end

	for floor = 1, 10 do
		if (perFloor[floor] or 0) ~= 1 then
			problem(("floor%d"):format(floor), ("%d bosses; every floor has exactly one"):format(perFloor[floor] or 0))
		end
	end

	-- Grolak, the Phase 0 boss, in full.
	local grolak = Bosses.rows.Grolak
	if grolak == nil then
		problem("Grolak", "missing")
	else
		if grolak.bars ~= 4 or #grolak.phases ~= 4 then
			problem("Grolak", "has 4 bars with a phase per bar")
		end
		local last = grolak.phases[#grolak.phases]
		if last ~= nil then
			local swaps = false
			for _, mechanic in last.mechanics do
				if mechanic.kind == "WeaponSwap" then
					swaps = true
				end
			end
			if not swaps or last.arts == nil or #last.arts == 0 then
				problem("Grolak", "the final bar swaps to a curved blade with Katana-style Arts")
			end
			for _, artId in last.arts or {} do
				if not artId:match("^Katana%.") then
					problem("Grolak", ("final-bar art '%s' is not a Katana Art"):format(artId))
				end
			end
		end
		if grolak.lab ~= "MantleOfLastLight" then
			problem("Grolak", "the floor 1 Last Attack Bonus is the Mantle of Last Light")
		end
	end

	return problems
end

return validate
