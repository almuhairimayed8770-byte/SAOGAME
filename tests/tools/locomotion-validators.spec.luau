--!strict
--[[
	The stride validator (tools/validators/stride.luau): run against the real data/choreo.luau,
	which must be clean, and against copies with one number broken.
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

-- Loads a tools/ module under Lune, its relative requires resolved from its own directory.
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
		print = function() end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value do
		out[key] = deepCopy(inner)
	end
	return out
end

-- Runs the validator with data/choreo.luau as the real one changed by `mutate`.
local function run(mutate: ((choreo: any) -> ())?): { string }
	local validator = loadTool("tools/validators/stride")
	local context = {
		load = function(path: string): any
			local loaded = Harness.load(path)
			if path == "src/shared/data/choreo" and mutate ~= nil then
				local copy = deepCopy(loaded)
				mutate(copy)
				return copy
			end
			return loaded
		end,
		listFiles = Harness.listFiles,
		readFile = Harness.readFile,
		repoRoot = root,
	}
	return validator(context)
end

local function hasProblem(problems: { string }, needle: string): boolean
	for _, problem in problems do
		if problem:find(needle, 1, true) then
			return true
		end
	end
	return false
end

describe("stride validator", function()
	it("passes the real data/choreo.luau", function()
		expect(table.concat(run(), "; ")).toBe("")
	end)

	it("flags a walk whose planted foot cannot keep up with a walk-speed strafe at rateCeiling", function()
		for _, name in { "WalkLeft", "WalkRightDrawn", "WalkBack", "WalkForwardDrawn" } do
			local problems = run(function(choreo: any)
				local stride = choreo.locomotion.stride
				-- Just short of walkSpeed at the ceiling.
				stride.groundSpeed[name] = choreo.locomotion.walkSpeed / stride.rateCeiling * 0.99
			end)
			expect(hasProblem(problems, name)).toBe(true)
		end
	end)

	it("flags a gait clip with no ground speed or touchdown, and a rate range that leaves out 1", function()
		expect(hasProblem(
			run(function(choreo: any)
				choreo.locomotion.stride.groundSpeed.WalkLeftDrawn = nil
			end),
			"WalkLeftDrawn"
		)).toBe(true)
		expect(hasProblem(
			run(function(choreo: any)
				choreo.locomotion.stride.touchdown.RunDrawn = nil
			end),
			"RunDrawn"
		)).toBe(true)
		expect(hasProblem(
			run(function(choreo: any)
				choreo.locomotion.stride.rateCeiling = 0.9
			end),
			"rateCeiling"
		)).toBe(true)
		expect(hasProblem(
			run(function(choreo: any)
				choreo.locomotion.stride.rateFloor = 1.1
			end),
			"rateFloor"
		)).toBe(true)
	end)
end)
