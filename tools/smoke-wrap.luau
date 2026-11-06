--!strict
--[[
	Writes the run-in-roblox runner for one smoke script (see tools/smoke/SmokeRunner.luau).

		lune run tools/smoke-wrap.luau <smoke script> <runner output>

	tools/smoke.sh calls this for every tests/smoke/*.smoke.luau before handing the runner to
	run-in-roblox; there is no reason to run it by hand.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local SmokeRunner = require("./smoke/SmokeRunner")

local input = process.args[1]
local output = process.args[2]
if input == nil or output == nil then
	print("usage: lune run tools/smoke-wrap.luau <smoke script> <runner output>")
	process.exit(2)
end
assert(input ~= nil and output ~= nil, "unreachable: both arguments were checked above")

if not fs.isFile(input) then
	print(("smoke-wrap: no such file: %s"):format(input))
	process.exit(2)
end

local source = fs.readFile(input)
local runner = SmokeRunner.build({ path = (input:gsub("\\", "/")), source = source })
local directory = output:match("^(.*)[/\\][^/\\]+$")
if directory ~= nil and directory ~= "" and not fs.isDir(directory) then
	fs.writeDir(directory)
end
fs.writeFile(output, runner)
print(("smoke-wrap: %s -> %s"):format(input, output))
