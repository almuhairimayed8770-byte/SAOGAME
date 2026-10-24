--!strict
--[[
	Validates src/shared/data/arts.luau: every row has the ArtDef fields with the right types, ids
	match keys and the "<Weapon>.<NameNoSpaces>" rule, clips follow "player/<Weapon>/<Name>",
	startup <= total, post-motion > 0 except guard Arts (hits = 0), unlocks within 0..1000 with no
	duplicates above 0, every weapon starts at 0 and has an ultimate.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local WEAPONS = {
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

local PRECONDITIONS = { "Standing", "Moving", "Airborne", "AfterParry" }
local STATUSES = { "Bleed", "Poison", "Paralysis", "Stun", "Burn", "Freeze" }
local EFFECTS = { "Launch", "Knockdown", "Knockback", "Pull", "Trip", "Teleport", "Area", "Pierce", "Guard" }

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Check = ctx.load("src/shared/util/Check")
	local Arts = ctx.load("src/shared/data/arts")

	local function problem(id: string, message: string)
		table.insert(problems, ("arts.%s: %s"):format(id, message))
	end

	local schema = Check.interface({
		id = Check.string(64),
		name = Check.string(48),
		weapon = Check.literal(table.unpack(WEAPONS)),
		unlock = Check.integer(0, Arts.rules.proficiencyMax),
		hits = Check.integer(0, 64),
		startup = Check.number(0, 5),
		total = Check.number(0, 20),
		postMotion = Check.number(0, 5),
		multiplier = Check.number(0, 20),
		gaugeDamage = Check.number(0, 500),
		rootMotion = Check.number(0, 40),
		clip = Check.string(96),
		preconditions = Check.optional(Check.array(Check.literal(table.unpack(PRECONDITIONS)), 4)),
		ultimate = Check.optional(Check.boolean),
		note = Check.optional(Check.string(160)),
		status = Check.optional(Check.literal(table.unpack(STATUSES))),
		effect = Check.optional(Check.literal(table.unpack(EFFECTS))),
	})

	local byWeapon: { [string]: { any } } = {}

	for key, art in Arts.rows do
		local ok, message = schema(art)
		if not ok then
			problem(tostring(key), message or "invalid row")
			continue
		end
		if art.id ~= key then
			problem(key, ("id '%s' does not match its key"):format(art.id))
		end
		local expectedId = art.weapon .. "." .. art.name:gsub(" ", "")
		if art.id ~= expectedId then
			problem(key, ("id should be '%s' (weapon + name without spaces)"):format(expectedId))
		end
		local expectedClip = ("player/%s/%s"):format(art.weapon, art.name:gsub(" ", ""))
		if art.clip ~= expectedClip then
			problem(key, ("clip should be '%s'"):format(expectedClip))
		end
		if art.startup > art.total then
			problem(key, ("startup %s exceeds total %s"):format(art.startup, art.total))
		end
		if art.hits > 0 then
			if art.postMotion <= 0 then
				problem(key, "post-motion must be > 0 for an Art that hits")
			end
			if art.multiplier <= 0 then
				problem(key, "multiplier must be > 0 for an Art that hits")
			end
		else
			if art.effect ~= "Guard" then
				problem(key, "an Art with zero hits must be a guard Art (effect = 'Guard')")
			end
		end
		if art.ultimate and art.unlock < 500 then
			problem(key, "an ultimate unlocks at 500 or later")
		end
		byWeapon[art.weapon] = byWeapon[art.weapon] or {}
		table.insert(byWeapon[art.weapon], art)
	end

	for _, weapon in WEAPONS do
		local list = byWeapon[weapon]
		if list == nil then
			problem(weapon, "weapon category has no Arts")
			continue
		end
		local sorted = Arts.list(weapon)
		local seen: { [number]: string } = {}
		local lowest = math.huge
		local hasUltimate = false
		local previous = -1
		for _, art in sorted do
			if art.unlock < previous then
				problem(art.id, "Arts.list is not sorted by unlock")
			end
			previous = art.unlock
			lowest = math.min(lowest, art.unlock)
			if art.unlock > 0 and seen[art.unlock] ~= nil then
				problem(art.id, ("shares unlock %d with %s"):format(art.unlock, seen[art.unlock]))
			end
			seen[art.unlock] = art.id
			if art.ultimate then
				hasUltimate = true
			end
		end
		if lowest ~= 0 then
			problem(weapon, "no Art unlocks at proficiency 0")
		end
		if not hasUltimate then
			problem(weapon, "no ultimate Art")
		end
		if #sorted < 5 then
			problem(weapon, ("only %d Arts; every category has at least 5"):format(#sorted))
		end
	end

	-- Axe and Mace share the section 8 rows.
	for _, axeArt in Arts.list("Axe") do
		local maceArt = Arts.byId("Mace." .. axeArt.name:gsub(" ", ""))
		if maceArt == nil then
			problem(axeArt.id, "has no Mace twin")
		else
			for _, field in { "unlock", "hits", "startup", "total", "postMotion", "multiplier", "gaugeDamage" } do
				if axeArt[field] ~= maceArt[field] then
					problem(axeArt.id, ("%s differs from %s"):format(field, maceArt.id))
				end
			end
		end
	end

	return problems
end

return validate
