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

	it("flags blocked-body numbers that are missing or out of range (D-144)", function()
		expect(hasProblem(
			run(function(choreo: any)
				choreo.locomotion.stride.blocked = nil
			end),
			"blocked"
		)).toBe(true)
		-- idleSpeedThreshold at the slowest capture step: the loosest match allowed is under it.
		local slowest = 1
		for _, step in Harness.load("src/shared/data/dev").timeScale.steps do
			slowest = math.min(slowest, step)
		end
		local limit = Harness.load("src/shared/data/choreo").locomotion.idleSpeedThreshold * slowest
		local cases: { { field: string, value: any } } = {
			{ field = "degrees", value = 0 },
			{ field = "degrees", value = 90 },
			{ field = "degrees", value = "3" },
			{ field = "settleSeconds", value = -0.1 },
			{ field = "settleSeconds", value = 1 },
			{ field = "followSeconds", value = 0 },
			{ field = "followSeconds", value = 0 / 0 },
			{ field = "matchSpeed", value = -0.01 },
			{ field = "matchSpeed", value = limit },
			{ field = "matchSpeed", value = nil },
		}
		for _, case in cases do
			local problems = run(function(choreo: any)
				choreo.locomotion.stride.blocked[case.field] = case.value
			end)
			expect(hasProblem(problems, "blocked." .. case.field)).toBe(true)
		end
		-- A settle of no wait at all, and a tight match, are fine.
		expect(table.concat(
			run(function(choreo: any)
				choreo.locomotion.stride.blocked.settleSeconds = 0
				choreo.locomotion.stride.blocked.matchSpeed = 0
			end),
			"; "
		)).toBe("")
	end)

	it("flags step take-up numbers that are missing or out of range (D-651)", function()
		expect(hasProblem(
			run(function(choreo: any)
				choreo.locomotion.stride.takeUp = nil
			end),
			"takeUp"
		)).toBe(true)
		local walkSpeed = Harness.load("src/shared/data/choreo").locomotion.walkSpeed
		local cases: { { field: string, value: any, needle: string? } } = {
			{ field = "planRows", value = 2 },
			{ field = "planRows", value = 30.5 },
			{ field = "refitRows", value = 0 },
			{ field = "refitRows", value = 31 },
			{ field = "refitRows", value = 1.5 },
			{ field = "gateRows", value = 0 },
			{ field = "minRows", value = 29, needle = "takeUp.minRows" },
			{ field = "spanRows", value = 59 },
			{ field = "phases", value = 1 },
			{ field = "stepHz", value = 0 },
			{ field = "extraSeconds", value = 0.5 },
			{ field = "extraSeconds", value = 10.1 },
			{ field = "gateShare", value = 0.49 },
			{ field = "gateShare", value = 1.01 },
			{ field = "wholeSteps", value = 0 },
			{ field = "wholeSteps", value = 0.5 },
			{ field = "p90Bar", value = 0 },
			{ field = "p90Bar", value = walkSpeed / 240 },
			{ field = "p90Bar", value = nil },
		}
		for _, case in cases do
			local problems = run(function(choreo: any)
				choreo.locomotion.stride.takeUp[case.field] = case.value
			end)
			expect(hasProblem(problems, case.needle or ("takeUp." .. case.field))).toBe(true)
		end
		-- A gate that takes only right guesses, and a bar just under a step, are fine.
		expect(table.concat(
			run(function(choreo: any)
				choreo.locomotion.stride.takeUp.gateShare = 1
				choreo.locomotion.stride.takeUp.p90Bar = walkSpeed / 240 * 0.99
			end),
			"; "
		)).toBe("")
	end)

	it("flags lead-gate numbers that are missing or out of range (D-661)", function()
		local cases: { { field: string, value: any } } = {
			{ field = "leadRows", value = nil },
			{ field = "leadRows", value = 59 },
			{ field = "leadRows", value = 601 },
			{ field = "leadRows", value = 240.5 },
			{ field = "gateLead", value = nil },
			{ field = "gateLead", value = 0 },
			{ field = "gateLead", value = 241 },
			{ field = "gateLead", value = 10.5 },
			{ field = "leadShare", value = nil },
			{ field = "leadShare", value = 0 },
			{ field = "leadShare", value = 1 },
		}
		for _, case in cases do
			local problems = run(function(choreo: any)
				choreo.locomotion.stride.takeUp[case.field] = case.value
			end)
			expect(hasProblem(problems, "takeUp." .. case.field)).toBe(true)
		end
		-- The window at the share gate's own and at the whole span, a lead of one frame and a
		-- share just under all are fine.
		for _, change in
			{ { leadRows = 60, gateLead = 1 }, { leadRows = 600, gateLead = 600, leadShare = 0.99 } } :: { { [string]: number } }
		do
			expect(table.concat(
				run(function(choreo: any)
					for field, value in change do
						choreo.locomotion.stride.takeUp[field] = value
					end
				end),
				"; "
			)).toBe("")
		end
	end)

	it("flags the local fighter's even-root numbers that are missing or out of range (D-675)", function()
		expect(hasProblem(
			run(function(choreo: any)
				choreo.locomotion.stride.evenRoot = nil
			end),
			"evenRoot"
		)).toBe(true)
		local cases: { { field: string, value: any } } = {
			{ field = "drawBody", value = "yes" },
			{ field = "rateSeconds", value = 0 },
			{ field = "rateSeconds", value = 0.26 },
			{ field = "followSeconds", value = 0 },
			{ field = "followSeconds", value = 0.2 },
			{ field = "lagSeconds", value = -0.01 },
			{ field = "lagSeconds", value = 0.2 },
			{ field = "maxDrawnStuds", value = 0 },
			{ field = "maxDrawnStuds", value = 4 },
			{ field = "maxLagStuds", value = 0 },
			{ field = "maxLagStuds", value = 0.2 },
			{ field = "maxLagDegrees", value = -1 },
			{ field = "maxLagDegrees", value = 91 },
			{ field = "settleStuds", value = -0.001 },
			{ field = "settleStuds", value = 0.03 },
			{ field = "settleDegrees", value = -1 },
		}
		for _, case in cases do
			local problems = run(function(choreo: any)
				choreo.locomotion.stride.evenRoot[case.field] = case.value
			end)
			expect(hasProblem(problems, "evenRoot." .. case.field)).toBe(true)
		end
		-- An evened yaw, no lag at the whole drawn bound, and the body on its root are fine.
		for _, change in
			{
				{ maxLagDegrees = 10, settleDegrees = 0.05 },
				{ lagSeconds = 0, maxLagStuds = 0.15 },
				{ drawBody = false },
			} :: { { [string]: any } }
		do
			expect(table.concat(
				run(function(choreo: any)
					for field, value in change do
						choreo.locomotion.stride.evenRoot[field] = value
					end
				end),
				"; "
			)).toBe("")
		end
	end)

	it("flags a stop hand-over margin that is missing or leaves no settle point in a half cycle", function()
		for _, value in { nil :: number?, 0, 0.5, -0.1 } do
			local problems = run(function(choreo: any)
				choreo.locomotion.stopHandOverCycles = value
			end)
			expect(hasProblem(problems, "stopHandOverCycles")).toBe(true)
		end
	end)
end)
