--!strict
--[[
	The gait clips are the gait generator's output (tools/gaitgen.luau; D-054, D-128, D-134, D-135).
	Every clip it checks regenerates byte for byte from tools/gaitgen/ (the plans in Gaits.luau,
	the pinned upper-body sources in sources/), the same check `lune run tools/gaitgen.luau --check`
	runs, so a hand edit to one of those clips fails here: change the generator's input and
	regenerate instead. Every gait clip is in the byte check, Run and Sprint too (D-291: their
	hand-keyed upper bodies are pinned sources, so GaitGen.DRIFTED is empty). Should a clip ever be
	listed there again, it is left out of the byte check, but its key times, root, legs and
	Footsteps must still be the generator's, and it must still differ (else it belongs back in the
	check).
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

-- Loads a tools/ module under Lune, resolving its relative requires the same way (once each).
local loaded: { [string]: any } = {}
local loadTool
function loadTool(path: string): any
	local cached = loaded[path]
	if cached ~= nil then
		return cached
	end
	local directory = path:match("^(.*)/[^/]+$") or ""
	local env = {
		require = function(target: string): any
			if target:sub(1, 6) == "@lune/" then
				return require(target)
			end
			return loadTool(normalize(directory .. "/" .. target))
		end,
	}
	local module =
		luau.load(fs.readFile(root .. "/" .. path .. ".luau"), { debugName = path, environment = env :: any })()
	loaded[path] = module
	return module
end

local GaitGen = loadTool("tools/gaitgen/GaitGen")

-- The lines the generator owns outright: key times, the root, the legs, the Footsteps.
local function rootAndLegs(source: string): { string }
	local lines = {}
	for _, line in source:split("\n") do
		local joint = line:match("^%s+(%a+) = ")
		if
			joint == "time"
			or joint == "Root"
			or (joint ~= nil and (joint:find("Hip") or joint:find("Knee") or joint:find("Ankle")))
			or line:find('kind = "Footstep"', 1, true)
		then
			table.insert(lines, line)
		end
	end
	return lines
end

describe("gaitgen", function()
	it("regenerates every gait clip it checks byte for byte", function()
		local lines = {}
		for _, drift in GaitGen.check(Harness) do
			table.insert(lines, GaitGen.describe(drift))
		end
		expect(lines).toEqual({})
	end)

	it("owns every gait clip, sheathed and drawn, and checks all but the drifted ones", function()
		local checked = GaitGen.checked()
		for _, name in GaitGen.NAMES do
			expect(fs.isFile(root .. "/" .. GaitGen.path(name))).toBe(true)
			expect(table.find(checked, name) ~= nil).toBe(GaitGen.DRIFTED[name] == nil)
		end
		for name in GaitGen.DRIFTED do
			expect(table.find(GaitGen.NAMES, name) ~= nil).toBe(true)
		end
		-- every drawn twin is checked: the sheathed legs under it are the generator's (D-134)
		for _, name in GaitGen.NAMES do
			if name:find("Drawn$") then
				expect(table.find(checked, name) ~= nil).toBe(true)
			end
		end
	end)

	it("reports a hand edit to a generated clip", function()
		local result = GaitGen.generate(Harness, "WalkBack")
		expect(GaitGen.compare(result, result.source)).toBeNil()
		-- nudge the first left knee angle by a tenth of a degree, the smallest edit a clip can hold
		local lines = result.source:split("\n")
		local edited: number? = nil
		for index, line in lines do
			local before, angle, after = line:match("^(%s+LeftKnee = rot%()([%-%d%.]+)(,.*)$")
			if before and angle and after then
				lines[index] = before .. tostring(math.floor((tonumber(angle) :: number) * 10 + 1.5) / 10) .. after
				edited = index
				break
			end
		end
		expect(edited).never.toBeNil()
		local drift = GaitGen.compare(result, table.concat(lines, "\n"))
		expect(drift).never.toBeNil()
		if drift then
			expect(drift.line).toBe(edited)
			expect(drift.lines).toBe(1)
			expect(GaitGen.describe(drift):find("WalkBack", 1, true)).never.toBeNil()
		end
		expect(GaitGen.compare(result, nil)).never.toBeNil()
	end)

	for _, name in GaitGen.NAMES do
		if GaitGen.DRIFTED[name] then
			it(
				("%s still differs above the hips, and its key times, root, legs and Footsteps are the generator's"):format(
					name
				),
				function()
					local result = GaitGen.generate(Harness, name)
					local committed = Harness.readFile(result.path)
					expect(committed == result.source).toBe(false)
					expect(rootAndLegs(committed)).toEqual(rootAndLegs(result.source))
					expect(#rootAndLegs(committed)).toBeGreaterThan(0)
				end
			)
		end
	end
end)
