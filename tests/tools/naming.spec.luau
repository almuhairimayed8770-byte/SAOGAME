--!strict
--[[
	The naming validator must catch a planted blocklist hit and honour whole-word entries.
	Terms are taken from the blocklist at runtime so this file never spells one itself.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local root = Harness.repoRoot()

local function normalize(path: string): string
	local parts = {}
	for segment in path:gmatch("[^/]+") do
		if segment == ".." then
			table.remove(parts)
		elseif segment ~= "." then
			table.insert(parts, segment)
		end
	end
	return table.concat(parts, "/")
end

-- Loads a Lune module by repo-relative path, resolving its relative requires.
local loadTool
function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local directory = path:match("^(.*)/[^/]+$") or ""
	local env = {
		require = function(target: string): any
			if target:sub(1, 6) == "@lune/" then
				return require(target)
			end
			return loadTool(normalize(directory .. "/" .. target))
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local blocklist = loadTool("tools/naming/blocklist")
local validate = loadTool("tools/validators/naming")

local function pick(whole: boolean, minLength: number): string
	for _, entry in blocklist do
		if entry.whole == whole and not entry.term:find(" ", 1, true) and #entry.term >= minLength then
			return entry.term
		end
	end
	error("blocklist has no suitable entry")
end

local function scan(files: { [string]: string }): { string }
	local paths = {}
	for path in files do
		table.insert(paths, path)
	end
	table.sort(paths)
	return validate({
		load = Harness.load,
		listFiles = function(_directory: string, _pattern: string?)
			return paths
		end,
		readFile = function(path: string)
			return files[path]
		end,
		repoRoot = "/nonexistent",
	})
end

describe("naming validator", function()
	it("loads a non-empty lowercase blocklist", function()
		expect(#blocklist).toBeGreaterThan(40)
		for _, entry in blocklist do
			expect(entry.term).toBe(entry.term:lower())
			expect(typeof(entry.whole)).toBe("boolean")
		end
	end)

	it("catches a planted hit and reports file:line", function()
		local term = pick(false, 5)
		local planted = '--!strict\nlocal x = 1\nlocal name = "' .. term:upper() .. '"\nreturn x\n'
		local problems = scan({ ["src/shared/data/planted.luau"] = planted })
		expect(#problems).toBe(1)
		expect(problems[1]).toContain("src/shared/data/planted.luau:3")
		expect(problems[1]).toContain(term)
	end)

	it("substring entries match inside longer words", function()
		local term = pick(false, 5)
		local problems = scan({ ["docs/notes.md"] = "the " .. term .. "s were here" })
		expect(#problems).toBe(1)
	end)

	it("whole-word entries match only as a whole word", function()
		local term = pick(true, 3)
		local embedded = scan({ ["src/a.luau"] = "local x" .. term .. "y = 1\nlocal " .. term .. "ish = 2" })
		expect(#embedded).toBe(0)
		local standalone = scan({ ["src/a.luau"] = "local " .. term .. " = 1" })
		expect(#standalone).toBe(1)
		expect(standalone[1]).toContain("(whole word)")
		local punctuated = scan({ ["src/a.luau"] = "-- (" .. term:upper() .. ")" })
		expect(#punctuated).toBe(1)
	end)

	it("skips the spec, the blocklist, build output and binary files", function()
		local term = pick(false, 5)
		local problems = scan({
			["docs/GAME_SPEC.md"] = term,
			["tools/naming/blocklist.luau"] = term,
			["build/Skyspire.luau"] = term,
			["Packages/x.luau"] = term,
			[".git/config"] = term,
			["places/Playground.rbxl"] = term,
			["docs/clips/a.png"] = term,
			["docs/notes.txt"] = "binary\0" .. term,
		})
		expect(problems).toEqual({})
	end)

	it("reports every hit line in a file", function()
		local term = pick(false, 5)
		local problems = scan({ ["README.md"] = term .. "\nclean\n" .. term })
		expect(#problems).toBe(2)
		expect(problems[1]).toContain("README.md:1")
		expect(problems[2]).toContain("README.md:3")
	end)

	it("a clean file reports nothing", function()
		local problems =
			scan({ ["src/clean.luau"] = "local Spire = { Firstlight = true, Crowns = 0 }\nreturn Spire\n" })
		expect(problems).toEqual({})
	end)
end)
