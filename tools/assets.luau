--!strict
--[[
	Asset report (section 19: "every uploaded id goes in assets.luau with a name, and
	tools/assets.luau reports missing ones").

		lune run tools/assets.luau [--markdown]

	Lists every entry of data/assets.luau (grouped by kind) and data/sfx.luau (grouped by family):
	its id, whether it is still a placeholder, the note, and which modules under src/ reference the
	name (a grep for the quoted name, so a reference through a variable is not found). Exits 1 when
	an entry has no id (0 / rbxassetid://0) but is not flagged as a placeholder: that is an asset
	the game would try to load and fail on. Placeholders are reported, not failed (the gate rule is
	that each one is listed in docs/PLACEHOLDERS.md).

	--markdown prints the same report as two markdown tables (pasted into docs/ASSETS.md).
]]

local process = require("@lune/process")
local stdio = require("@lune/stdio")

local Harness = require("../tests/_harness/Harness")

local Assets = Harness.load("src/shared/data/assets")
local Sfx = Harness.load("src/shared/data/sfx")

local markdown = table.find(process.args, "--markdown") ~= nil

local PLACEHOLDER_SOUND = "rbxassetid://0"

-- Every src/ module except the registries themselves, with its source, for reference lookups.
local sources: { { path: string, text: string } } = {}
for _, file in Harness.listFiles("src", "%.luau$") do
	if file ~= "src/shared/data/assets.luau" and file ~= "src/shared/data/sfx.luau" then
		table.insert(sources, { path = file, text = Harness.readFile(file) })
	end
end

local function referencesOf(name: string): { string }
	local needle = ('"%s"'):format(name)
	local found = {}
	for _, source in sources do
		if source.text:find(needle, 1, true) then
			table.insert(found, (source.path:gsub("^src/", ""):gsub("%.luau$", "")))
		end
	end
	return found
end

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

type AssetRow = {
	kind: string,
	name: string,
	id: string,
	placeholder: boolean,
	missing: boolean,
	note: string,
	references: { string },
}

local rows: { AssetRow } = {}
local failures = 0

for _, name in sortedKeys(Assets.registry) do
	local def = Assets.registry[name]
	local missing = def.id == 0
	if missing and not def.placeholder then
		failures += 1
	end
	table.insert(rows, {
		kind = def.kind,
		name = name,
		id = tostring(def.id),
		placeholder = def.placeholder,
		missing = missing,
		note = def.note,
		references = referencesOf(name),
	})
end

for _, item in Sfx.all() do
	local entry = item.entry
	local missing = entry.id == PLACEHOLDER_SOUND or entry.id == "" or entry.id == nil
	if missing and not entry.placeholder then
		failures += 1
	end
	table.insert(rows, {
		kind = "Sound/" .. item.family,
		name = item.name,
		id = tostring(entry.id),
		placeholder = entry.placeholder,
		missing = missing,
		note = entry.note or "",
		references = referencesOf(item.name),
	})
end

table.sort(rows, function(a, b)
	if a.kind == b.kind then
		return a.name < b.name
	end
	return a.kind < b.kind
end)

local placeholders = 0
local ready = 0
for _, row in rows do
	if row.missing then
		placeholders += 1
	else
		ready += 1
	end
end

if markdown then
	stdio.write("| Kind | Name | Id | State | Referenced by | Note |\n")
	stdio.write("| --- | --- | --- | --- | --- | --- |\n")
	for _, row in rows do
		local state = if not row.missing then "uploaded" elseif row.placeholder then "placeholder" else "MISSING"
		stdio.write(
			("| %s | `%s` | %s | %s | %s | %s |\n"):format(
				row.kind,
				row.name,
				row.id,
				state,
				if #row.references == 0 then "-" else table.concat(row.references, ", "),
				(row.note:gsub("|", "/"))
			)
		)
	end
else
	local lastKind = nil
	for _, row in rows do
		if row.kind ~= lastKind then
			lastKind = row.kind
			stdio.write(("\n%s%s%s\n"):format(stdio.style("bold"), row.kind, stdio.style("reset")))
		end
		local state: string
		if not row.missing then
			state = stdio.color("green") .. "uploaded   " .. stdio.color("reset")
		elseif row.placeholder then
			state = stdio.color("yellow") .. "placeholder" .. stdio.color("reset")
		else
			state = stdio.color("red") .. "MISSING    " .. stdio.color("reset")
		end
		stdio.write(
			("  %s  %-24s id %-14s used by %s\n"):format(
				state,
				row.name,
				row.id,
				if #row.references == 0 then "-" else table.concat(row.references, ", ")
			)
		)
		stdio.write(("               %s\n"):format(row.note))
	end
end

stdio.write(
	("\n%d entries: %d uploaded, %d placeholders, %d missing without a placeholder flag\n"):format(
		#rows,
		ready,
		placeholders,
		failures
	)
)
if failures > 0 then
	process.exit(1)
end
