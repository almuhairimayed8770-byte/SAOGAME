--!strict
--[[
	The PoseEditor's Serialize module: parses every hand-written clip without executing it and
	gets the same table `require` would; serializes a clip and parses it back unchanged (no
	luau.load involved); the emitted source is also valid Luau that evaluates to the same table.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local root = Harness.repoRoot()

local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path)
	local env = {
		require = function(_target: any)
			error("Serialize must not require anything")
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local Serialize = loadTool("tools/PoseEditor/src/Serialize.luau")
local Dev = Harness.load("src/shared/data/dev")

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- Evaluates emitted source as Luau with a stub `script` / `require` (the Types require is a no-op).
local function evaluate(source: string): any
	local env = Harness.environment()
	env.script = { Parent = { Parent = { Parent = { Parent = { types = "types" } } } } }
	env.require = function(_target: any)
		return {}
	end
	return luau.load(source, { debugName = "emitted", environment = env :: any })()
end

local HORIZONTAL = "src/shared/clips/player/OneHandedSword/Horizontal"

describe("Serialize.parse on the hand-written clips", function()
	it("parses every clip under src/shared/clips to the table require produces", function()
		local files = Harness.listFiles("src/shared/clips", "%.luau$")
		expect(#files).toBeGreaterThan(0)
		for _, file in files do
			local loaded = Harness.load(file)
			local parsed = Serialize.parse(Harness.readFile(file))
			if not deepEqual(parsed, loaded) then
				error(("parse(%s) differs from require"):format(file))
			end
		end
	end)

	it("keeps the header comment, the key notes and the joint order", function()
		local _, meta = Serialize.parse(Harness.readFile(HORIZONTAL .. ".luau"))
		expect(meta.header).toContain("player/OneHandedSword/Horizontal: the first Art")
		expect(meta.keyNotes[1]).toBe("ready stance")
		expect(meta.keyNotes[2]).toBe("start pose")
		expect(meta.jointOrder[1][1]).toBe("Root")
		expect(meta.jointOrder[1][2]).toBe("Waist")
		expect(#meta.jointOrder[1]).toBe(16)
	end)

	it("names the line of a malformed clip and rejects code it cannot read", function()
		expect(function()
			Serialize.parse(
				'--!strict\nlocal clip = {\n\tid = "x",\n\tkeys = { { time = 0, easing = "Hold", joints = { Neck = rot(0, 0) } } },\n}\nreturn clip\n'
			)
		end).toThrow("line 4")
		expect(function()
			Serialize.parse("local clip = { id = math.huge }\nreturn clip")
		end).toThrow("unsupported identifier 'math'")
		expect(function()
			Serialize.parse("local clip = { id = 'a' }\nreturn other")
		end).toThrow("expected 'return clip'")
		expect(function()
			Serialize.parse("print('hi')")
		end).toThrow("unsupported statement")
		expect(function()
			Serialize.parse("local a = 1")
		end).toThrow("unsupported local value")
	end)

	it("reads negative numbers, exponents, hex, strings with escapes and nil-free tables", function()
		local clip = Serialize.parse(
			'local clip = {\n\tid = "a/b",\n\tn = -0.5,\n\te = 1e-6,\n\th = 0x10,\n\ts = "q\\"t\\n",\n\tlist = { 1, 2, 3 },\n\tflag = false,\n\t["odd key"] = 2,\n}\nreturn clip\n'
		)
		expect(clip.n).toBe(-0.5)
		expect(clip.e).toBe(1e-6)
		expect(clip.h).toBe(16)
		expect(clip.s).toBe('q"t\n')
		expect(clip.list).toEqual({ 1, 2, 3 })
		expect(clip.flag).toBe(false)
		expect(clip["odd key"]).toBe(2)
	end)
end)

describe("Serialize.toSource round trip", function()
	it("serialize -> parse gives the same table (no code execution)", function()
		for _, file in Harness.listFiles("src/shared/clips", "%.luau$") do
			local loaded = Harness.load(file)
			local source = Serialize.toSource(loaded)
			local parsed = Serialize.parse(source)
			if not deepEqual(parsed, loaded) then
				error(("round trip of %s differs"):format(file))
			end
		end
	end)

	it("the emitted source is valid Luau that evaluates to the same table", function()
		local loaded = Harness.load(HORIZONTAL)
		local source = Serialize.toSource(loaded)
		local evaluated = evaluate(source)
		expect(deepEqual(evaluated, loaded)).toBe(true)
	end)

	it("writes the hand-written style: strict header, helpers, ordered fields, return", function()
		local loaded, meta = Serialize.parse(Harness.readFile(HORIZONTAL .. ".luau"))
		local source = Serialize.toSource(loaded, { meta = meta })
		expect(source:sub(1, 9)).toBe("--!strict")
		expect(source).toContain("--[[\n\tplayer/OneHandedSword/Horizontal: the first Art")
		expect(source).toContain("local Types = require(script.Parent.Parent.Parent.Parent.types)")
		expect(source).toContain("local function rot(x: number, y: number, z: number): Types.JointKey")
		expect(source).toContain(
			'local clip: Types.ClipDef = {\n\tid = "player/OneHandedSword/Horizontal",\n\trig = "PlayerR15",\n\tduration = 1,'
		)
		expect(source).toContain(
			'\t\t{\n\t\t\t-- ready stance\n\t\t\ttime = 0,\n\t\t\teasing = "QuadOut",\n\t\t\tjoints = {\n\t\t\t\tRoot = posRot(0, -0.12, 0, 0, 0, 0),\n\t\t\t\tWaist = rot(-8, -12, 0),'
		)
		expect(source).toContain("\t\t\troot = { pos = { 0, 0, 0 } },")
		expect(source).toContain('\t\t{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },')
		expect(source).toContain(
			"\t\tAnticipation = { start = 0.25, finish = 0.35 },\n\t\tSnap = { start = 0.35, finish = 0.4 },"
		)
		expect(source:sub(-13)).toBe("\nreturn clip\n")
		-- A second pass is byte-identical: the format is a fixed point.
		local again, meta2 = Serialize.parse(source)
		expect(Serialize.toSource(again, { meta = meta2 })).toBe(source)
	end)

	it("uses the rig joint order for keys without a recorded order, then alphabetical", function()
		local clip = {
			id = "enemy/Boar/Test",
			rig = "Boar",
			duration = 1,
			loop = false,
			layer = "FullBody",
			keys = {
				{
					time = 0,
					easing = "Hold",
					joints = {
						TailJoint = { rot = { 1, 0, 0 } },
						Neck = { rot = { 2, 0, 0 } },
						Zed = { pos = { 0, 1, 0 } },
					},
				},
			},
			events = {},
		}
		local source = Serialize.toSource(clip, { jointOrder = { "Root", "Neck", "TailJoint" } })
		local neck = source:find("Neck = rot(2, 0, 0)", 1, true) :: number
		local tail = source:find("TailJoint = rot(1, 0, 0)", 1, true) :: number
		local zed = source:find("Zed = { pos = { 0, 1, 0 } }", 1, true) :: number
		expect(neck).toBeLessThan(tail)
		expect(tail).toBeLessThan(zed)
		expect(source).toContain("local Types = require(script.Parent.Parent.Parent.Parent.types)")
		expect(source).toContain("enemy/Boar/Test: written by the PoseEditor.")
	end)

	it("formats numbers without noise and keeps unknown fields", function()
		local clip = {
			id = "x/y",
			rig = "Boar",
			duration = 2.5,
			loop = true,
			layer = "Base",
			keys = {
				{ time = 0, easing = "SineInOut", joints = {}, root = { pos = { 0, 0, -6 }, rot = { 0, 90, 0 } } },
			},
			events = { { time = 0.3833, kind = "Footstep", data = { foot = "Left", weight = 1 } } },
			future = { nested = true },
		}
		local source = Serialize.toSource(clip)
		expect(source).toContain("duration = 2.5,")
		expect(source).toContain("joints = {},")
		expect(source).toContain("root = { pos = { 0, 0, -6 }, rot = { 0, 90, 0 } },")
		expect(source).toContain('{ time = 0.3833, kind = "Footstep", data = { foot = "Left", weight = 1 } },')
		expect(source).toContain("future = { nested = true },")
		expect(source).toContain("require(script.Parent.Parent.Parent.types)")
		expect(deepEqual(Serialize.parse(source), clip)).toBe(true)
	end)
end)

describe("Serialize.shapeProblems and clone", function()
	it("accepts a real clip and lists what a junk payload lacks", function()
		expect(Serialize.shapeProblems(Harness.load(HORIZONTAL))).toEqual({})
		local problems = Serialize.shapeProblems({ id = 3, keys = {}, events = "no" })
		expect(problems).toContain("id must be a string")
		expect(problems).toContain("keys must be a non-empty array")
		expect(problems).toContain("events must be an array")
		expect(Serialize.shapeProblems("text")).toEqual({ "clip is not a table" })
	end)

	it("clone is deep", function()
		local original = { a = { b = { 1, 2 } } }
		local copy = Serialize.clone(original)
		copy.a.b[1] = 9
		expect(original.a.b[1]).toBe(1)
	end)

	it("Dev.isClipId guards the pose server path", function()
		expect(Dev.isClipId("player/OneHandedSword/Horizontal")).toBe(true)
		expect(Dev.isClipId("enemy/Boar/Charge")).toBe(true)
		expect(Dev.isClipId("Horizontal")).toBe(false)
		expect(Dev.isClipId("player/../x/y")).toBe(false)
		expect(Dev.isClipId("player//Boar/Charge")).toBe(false)
		expect(Dev.isClipId("a/b/c/d/e")).toBe(false)
		expect(Dev.clipUrl("enemy/Boar/Charge")).toBe(
			("http://127.0.0.1:%d/clips/enemy/Boar/Charge"):format(Dev.poseServer.port)
		)
		expect(Dev.clipPath("art-horizontal")).toBe("docs/clips/phase-0/art-horizontal.mp4")
	end)
end)
