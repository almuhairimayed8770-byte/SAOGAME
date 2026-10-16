--!strict
--[[
	Data validators. `lune run tools/validate.luau` loads every validator in tools/validators/,
	runs it, prints every problem, and exits 1 if any validator reported one.

	A validator is a module returning `function(ctx): { string }` where each string is one
	problem. `ctx.load(path)` loads a game module through the test harness, `ctx.listFiles`
	and `ctx.readFile` read the repository.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local Harness = require("../tests/_harness/Harness")

export type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local context: Context = {
	load = Harness.load,
	listFiles = Harness.listFiles,
	readFile = Harness.readFile,
	repoRoot = Harness.repoRoot(),
}

local validatorsDirectory = Harness.repoRoot() .. "/tools/validators"
local names = {}
for _, entry in fs.readDir(validatorsDirectory) do
	local name = entry:match("^(.-)%.luau$")
	if name then
		table.insert(names, name)
	end
end
table.sort(names)

local totalProblems = 0
for _, name in names do
	local validator = require("./validators/" .. name) :: (Context) -> { string }
	local ok, problems = pcall(validator, context)
	if not ok then
		totalProblems += 1
		stdio.write(
			stdio.color("red") .. "ERROR " .. stdio.color("reset") .. name .. ": " .. tostring(problems) .. "\n"
		)
		continue
	end
	if #problems == 0 then
		stdio.write(stdio.color("green") .. "ok    " .. stdio.color("reset") .. name .. "\n")
	else
		totalProblems += #problems
		stdio.write(
			stdio.color("red") .. "FAIL  " .. stdio.color("reset") .. name .. (" (%d)"):format(#problems) .. "\n"
		)
		for _, problem in problems do
			stdio.write("  - " .. problem .. "\n")
		end
	end
end

stdio.write(("\n%d validators, %d problems\n"):format(#names, totalProblems))
if totalProblems > 0 then
	process.exit(1)
end
