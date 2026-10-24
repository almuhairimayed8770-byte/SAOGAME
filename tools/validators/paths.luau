--!strict
--[[
	Paths validator: the six section 7 Paths exist with known weapon categories, an armor class,
	a signature table carrying the spec's numbers, the respec rule and the choose level.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local WEAPON_CATEGORIES = {
	OneHandedSword = true,
	Rapier = true,
	TwoHandedSword = true,
	Katana = true,
	Dagger = true,
	Spear = true,
	Axe = true,
	Mace = true,
	Shield = true,
	MartialArts = true,
	TwinFang = true,
	AegisBlade = true,
}

local ARMOR_CLASSES = { Light = true, Medium = true, Heavy = true }

local EXPECTED_PATHS = { "Vanguard", "Striker", "Duelist", "Breaker", "Shade", "Herald" }

-- Signature numbers from section 7 as (path, key path, value).
local SIGNATURE_NUMBERS = {
	{ "Vanguard", { "taunt", "threatMultiplier" }, 3 },
	{ "Vanguard", { "taunt", "duration" }, 8 },
	{ "Vanguard", { "bulwarkStance", "guardConeDegrees" }, 360 },
	{ "Striker", { "momentum", "startPoseCutPerStack" }, 0.5 },
	{ "Striker", { "momentum", "maxStacks" }, 3 },
	{ "Duelist", { "riposte", "activationHold" }, 0 },
	{ "Breaker", { "shatter", "gaugeDamageBonus" }, 0.6 },
	{ "Shade", { "firstStrike", "fromBehindMultiplier" }, 2.5 },
	{ "Herald", { "rally", "tempoCapBonus" }, 2 },
	{ "Herald", { "rally", "artSpeedBonus" }, 0.1 },
	{ "Herald", { "rally", "duration" }, 10 },
	{ "Herald", { "extraShards" }, 2 },
}

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end

	local Paths = ctx.load("src/shared/data/paths")

	if Paths.chooseLevel ~= 10 then
		problem("paths.chooseLevel must be 10")
	end
	if typeof(Paths.respec) ~= "table" or Paths.respec.perFloors ~= 10 or Paths.respec.crownFraction ~= 0.2 then
		problem("paths.respec must be one per ten floors for 20%% of carried Crowns")
	end

	local count = 0
	for id, def in Paths.list do
		count += 1
		if def.id ~= id then
			problem("paths.list.%s has id '%s'", tostring(id), tostring(def.id))
		end
		if typeof(def.name) ~= "string" or typeof(def.summary) ~= "string" then
			problem("paths.list.%s needs a name and a summary", tostring(id))
		end
		if typeof(def.weapons) ~= "table" or #def.weapons == 0 then
			problem("paths.list.%s needs at least one weapon category", tostring(id))
		else
			for _, weapon in def.weapons do
				if not WEAPON_CATEGORIES[weapon] then
					problem("paths.list.%s weapon '%s' is not a Types.WeaponCategory", tostring(id), tostring(weapon))
				end
			end
		end
		if not ARMOR_CLASSES[def.armor] then
			problem("paths.list.%s armor class '%s' is unknown", tostring(id), tostring(def.armor))
		end
		if typeof(def.signature) ~= "table" or next(def.signature) == nil then
			problem("paths.list.%s needs a signature table", tostring(id))
		end
	end
	if count ~= #EXPECTED_PATHS then
		problem("paths.list must hold exactly %d Paths (got %d)", #EXPECTED_PATHS, count)
	end
	for _, id in EXPECTED_PATHS do
		if Paths.list[id] == nil then
			problem("paths.list is missing '%s'", id)
		end
		if table.find(Paths.order, id) == nil then
			problem("paths.order is missing '%s'", id)
		end
	end

	for _, row in SIGNATURE_NUMBERS do
		local pathId, keyPath, want = row[1], row[2], row[3]
		local def = Paths.list[pathId]
		local value: any = if def then def.signature else nil
		for _, key in keyPath :: { string } do
			value = if typeof(value) == "table" then value[key] else nil
		end
		if value ~= want then
			problem(
				"paths.list.%s signature.%s should be %s (got %s)",
				pathId,
				table.concat(keyPath, "."),
				tostring(want),
				tostring(value)
			)
		end
	end

	if typeof(Paths.get) ~= "function" or typeof(Paths.canWield) ~= "function" then
		problem("paths.luau must export get() and canWield()")
	end

	return problems
end
