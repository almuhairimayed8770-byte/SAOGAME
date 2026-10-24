--!strict
--[[
	Validates src/shared/data/scope.luau (D-015): `phase` is a non-negative integer; every id in
	`arts`, `enemies`, `bosses` and `rigs` is a row of arts.luau, enemies.luau, bosses.luau or
	rigs.luau; no list holds an id twice; every in-scope enemy's and boss's skin rig is in scope
	too (their attack clips are enemy/<rig>/<clip>); and the has* helpers answer from the lists.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local LISTS = {
	{ field = "arts", table = "src/shared/data/arts", helper = "hasArt" },
	{ field = "enemies", table = "src/shared/data/enemies", helper = "hasEnemy" },
	{ field = "bosses", table = "src/shared/data/bosses", helper = "hasBoss" },
	{ field = "rigs", table = "src/shared/data/rigs", helper = "hasRig" },
}

-- Sibling tables keep their rows under `rows` (D-017); rigs.luau is keyed by id directly.
local function rowsOf(module: any): { [any]: any }
	if typeof(module) == "table" and typeof(module.rows) == "table" then
		return module.rows
	end
	return module
end

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local Scope = ctx.load("src/shared/data/scope")

	local function problem(label: string, message: string)
		table.insert(problems, ("scope.%s: %s"):format(label, message))
	end

	local phase = Scope.phase
	if typeof(phase) ~= "number" or phase < 0 or phase % 1 ~= 0 then
		problem("phase", ("must be a non-negative integer (got %s)"):format(tostring(phase)))
	end

	local inScope: { [string]: { [string]: boolean } } = {}
	for _, spec in LISTS do
		local set: { [string]: boolean } = {}
		inScope[spec.field] = set
		local list = Scope[spec.field]
		if typeof(list) ~= "table" then
			problem(spec.field, "must be an array of ids")
			continue
		end
		local rows = rowsOf(ctx.load(spec.table))
		local tableName = spec.table:match("[^/]+$") .. ".luau"
		for index, id in ipairs(list) do
			local label = ("%s[%d]"):format(spec.field, index)
			if typeof(id) ~= "string" then
				problem(label, "ids are strings")
				continue
			end
			if set[id] then
				problem(label, ("'%s' is listed twice"):format(id))
			end
			set[id] = true
			if rows[id] == nil then
				problem(label, ("'%s' is not a row of %s"):format(id, tableName))
			end
		end

		local helper = Scope[spec.helper]
		if typeof(helper) ~= "function" then
			problem(spec.helper, "must be a function")
			continue
		end
		for id in set do
			if helper(id) ~= true then
				problem(spec.helper, ("returns false for the listed id '%s'"):format(id))
			end
		end
		if helper("") ~= false then
			problem(spec.helper, "returns true for an id that is not listed")
		end
	end

	-- An in-scope enemy or boss needs its rig in scope: its attack clips animate that rig.
	for _, spec in
		{
			{ field = "enemies", table = "src/shared/data/enemies" },
			{ field = "bosses", table = "src/shared/data/bosses" },
		}
	do
		local rows = rowsOf(ctx.load(spec.table))
		local ids = {}
		for id in inScope[spec.field] do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			local def = rows[id]
			if typeof(def) == "table" and not inScope.rigs[def.skin] then
				problem(spec.field, ("'%s' is in scope but its rig '%s' is not"):format(id, tostring(def.skin)))
			end
		end
	end

	return problems
end

return validate
