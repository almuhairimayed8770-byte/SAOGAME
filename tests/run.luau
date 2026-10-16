--!strict
--[[
	Test runner. `lune run tests/run.luau [filter]` runs every tests/**/*.spec.luau whose path
	contains the optional filter. Each spec runs with `describe`, `it`, `expect`, `Harness` and
	`Test` as globals. Exits 1 on any failure.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local Harness = require("./_harness/Harness")
local Test = require("./_harness/Test")

local filter = process.args[1]
local testsDirectory = Harness.repoRoot() .. "/tests"

local specFiles = {}
local function walk(directory: string)
	for _, entry in fs.readDir(directory) do
		local full = directory .. "/" .. entry
		if fs.isDir(full) then
			if entry ~= "_harness" then
				walk(full)
			end
		elseif entry:match("%.spec%.luau$") then
			if filter == nil or full:find(filter, 1, true) then
				table.insert(specFiles, full)
			end
		end
	end
end
walk(testsDirectory)
table.sort(specFiles)

local failures = 0
local passes = 0
local started = os.clock()

for _, specPath in specFiles do
	Test.reset()
	local source = fs.readFile(specPath)
	local env = Harness.environment()
	env.describe = Test.describe
	env.it = Test.it
	env.expect = Test.expect
	env.Harness = Harness
	env.Test = Test
	env.require = require
	local chunk = luau.load(source, { debugName = specPath, environment = env :: any })
	local ok, err = pcall(chunk)
	if not ok then
		failures += 1
		stdio.write(
			stdio.color("red") .. "FAIL " .. stdio.color("reset") .. specPath .. "\n  " .. tostring(err) .. "\n"
		)
		continue
	end
	local fileFailures = 0
	for _, result in Test.results() do
		if result.ok then
			passes += 1
		else
			failures += 1
			fileFailures += 1
			stdio.write(
				stdio.color("red")
					.. "FAIL "
					.. stdio.color("reset")
					.. specPath
					.. " :: "
					.. result.suite
					.. " > "
					.. result.name
					.. "\n  "
					.. tostring(result.message)
					.. "\n"
			)
		end
	end
	if fileFailures == 0 then
		stdio.write(stdio.color("green") .. "ok   " .. stdio.color("reset") .. specPath .. "\n")
	end
end

local elapsed = os.clock() - started
stdio.write(("\n%d passed, %d failed, %d spec files, %.2fs\n"):format(passes, failures, #specFiles, elapsed))
if failures > 0 then
	process.exit(1)
end
