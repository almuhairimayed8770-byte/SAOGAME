--!strict
--[[
	The clip, scope and magic-number validators, driven through a fake ctx with synthetic inputs,
	and the data-table validators run against the real tables (which must be clean: every clip the
	Phase 0 scope demands is authored, so the clips validator reports nothing on the real tree).
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

-- Loads a tools/ module under Lune. Validators print their warnings instead of returning them:
-- they are swallowed to keep the test output quiet unless a test hands in a `prints` sink.
local loadTool
function loadTool(path: string, prints: { string }?): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local directory = path:match("^(.*)/[^/]+$") or ""
	local env = {
		require = function(target: string): any
			if target:sub(1, 6) == "@lune/" then
				return require(target)
			end
			return loadTool(normalize(directory .. "/" .. target))
		end,
		print = function(...: any)
			if prints == nil then
				return
			end
			local parts = {}
			for _, value in { ... } do
				table.insert(parts, tostring(value))
			end
			table.insert(prints, table.concat(parts, " "))
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local realContext = {
	load = Harness.load,
	listFiles = Harness.listFiles,
	readFile = Harness.readFile,
	repoRoot = root,
}

local function hasProblem(problems: { string }, needle: string): boolean
	for _, problem in problems do
		if problem:find(needle, 1, true) then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------------------------------
-- Synthetic clips
-- ------------------------------------------------------------------------------------------

local F = 1 / 60

local function playerArtClip(id: string): any
	return {
		id = id,
		rig = "PlayerR15",
		duration = 0.7,
		loop = false,
		layer = "UpperBody",
		attack = true,
		hitStop = "Normal",
		beats = {
			Anticipation = { start = 0, finish = 6 * F },
			Snap = { start = 6 * F, finish = 9 * F },
			Smear = { start = 6 * F, finish = 9 * F },
			Hold = { start = 9 * F, finish = 12 * F },
			Settle = { start = 12 * F, finish = 20 * F },
			Recovery = { start = 20 * F, finish = 0.7 },
		},
		keys = {
			{ time = 0, easing = "Hold", joints = { RightShoulder = { rot = { 0, 0, 0 } } } },
			{
				time = 6 * F,
				easing = "ExpoIn",
				joints = { RightShoulder = { rot = { -80, 0, 0 } }, Waist = { rot = { 0, -20, 0 } } },
			},
			{
				time = 9 * F,
				easing = "ExpoOut",
				joints = { RightShoulder = { rot = { 60, 0, 0 } }, Waist = { rot = { 0, 25, 0 } } },
			},
			{ time = 20 * F, easing = "Spring", joints = { RightShoulder = { rot = { 50, 0, 0 } } } },
			{
				time = 0.7,
				easing = "SineInOut",
				joints = { RightShoulder = { rot = { 0, 0, 0 } } },
				root = { pos = { 0, 0, -2 } },
			},
		},
		events = {
			{ time = 0, kind = "ActivationHold" },
			{ time = 5 * F, kind = "TrailOn" },
			{ time = 6 * F, kind = "SmearOn" },
			{ time = 6 * F, kind = "HitWindowOpen" },
			{ time = 9 * F, kind = "SmearOff" },
			{ time = 10 * F, kind = "HitWindowClose" },
			{ time = 12 * F, kind = "TrailOff" },
			{ time = 20 * F, kind = "PostMotionStart" },
		},
	}
end

local function enemyChargeClip(id: string, anticipationSeconds: number): any
	local snapStart = anticipationSeconds
	return {
		id = id,
		rig = "Boar",
		duration = anticipationSeconds + 0.6,
		loop = false,
		layer = "FullBody",
		attack = true,
		hitStop = "Normal",
		beats = {
			Anticipation = { start = 0, finish = anticipationSeconds },
			Snap = { start = snapStart, finish = snapStart + 3 * F },
			Smear = { start = snapStart, finish = snapStart + 3 * F },
			Hold = { start = snapStart + 3 * F, finish = snapStart + 6 * F },
			Settle = { start = snapStart + 6 * F, finish = snapStart + 0.3 },
			Recovery = { start = snapStart + 0.3, finish = anticipationSeconds + 0.6 },
		},
		keys = {
			{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 0, 0 } } } },
			{ time = anticipationSeconds, easing = "QuadIn", joints = { Neck = { rot = { -30, 0, 0 } } } },
			{ time = snapStart + 3 * F, easing = "ExpoOut", joints = { Neck = { rot = { 25, 0, 0 } } } },
			{ time = anticipationSeconds + 0.6, easing = "BackOut", joints = { Neck = { rot = { 0, 0, 0 } } } },
		},
		events = {
			{ time = snapStart - F, kind = "TrailOn" },
			{ time = snapStart, kind = "SmearOn" },
			{ time = snapStart, kind = "HitWindowOpen" },
			{ time = snapStart + 3 * F, kind = "SmearOff" },
			{ time = snapStart + 4 * F, kind = "HitWindowClose" },
			{ time = snapStart + 6 * F, kind = "TrailOff" },
		},
	}
end

local function idleClip(id: string, rig: string): any
	return {
		id = id,
		rig = rig,
		duration = 2,
		loop = true,
		layer = "Base",
		keys = {
			{ time = 0, easing = "SineInOut", joints = { Neck = { rot = { 0, 0, 0 } } } },
			{ time = 1, easing = "SineInOut", joints = { Neck = { rot = { 2, 0, 0 } } } },
		},
		events = { { time = 0.5, kind = "Footstep" } },
	}
end

local function art(id: string, clip: string, hits: number): any
	return {
		id = id,
		name = id,
		weapon = "OneHandedSword",
		unlock = 0,
		hits = hits,
		startup = 0.25,
		total = 0.6,
		postMotion = 0.4,
		multiplier = 1,
		gaugeDamage = 10,
		rootMotion = 2,
		clip = clip,
	}
end

-- A scope that puts every row in the current phase (the default for the synthetic tests).
local function everythingInScope(): any
	local function yes(_id: string): boolean
		return true
	end
	return { phase = 0, hasArt = yes, hasEnemy = yes, hasBoss = yes, hasRig = yes }
end

-- A scope built from id lists, the way scope.luau answers.
local function scopeOf(lists: { arts: { string }?, enemies: { string }?, bosses: { string }? }): any
	local function has(list: { string }?): (string) -> boolean
		return function(id: string): boolean
			return list ~= nil and table.find(list, id) ~= nil
		end
	end
	return { phase = 0, hasArt = has(lists.arts), hasEnemy = has(lists.enemies), hasBoss = has(lists.bosses) }
end

type ClipsExtra = { scope: any?, bosses: any?, sfx: any?, prints: { string }? }

-- `extra.scope` / `extra.bosses` / `extra.sfx`: nil for the defaults (everything in scope, no
-- bosses, the real sfx.luau), false for a table that fails to load, or a fake module.
-- `extra.prints` collects the printed warnings.
local function runClips(clips: { [string]: any }, arts: any, enemies: any, extra: ClipsExtra?): { string }
	local options: ClipsExtra = extra or {}
	local validate = loadTool("tools/validators/clips", options.prints)
	local scope = if options.scope == nil then everythingInScope() else options.scope
	local bosses = if options.bosses == nil then { rows = {} } else options.bosses
	local files = {}
	for id in clips do
		table.insert(files, "src/shared/clips/" .. id .. ".luau")
	end
	table.sort(files)
	return validate({
		load = function(path: string)
			local id = path:match("^src/shared/clips/(.+)$")
			if id then
				return clips[id]
			end
			if path == "src/shared/data/arts" then
				return arts or error("no arts")
			end
			if path == "src/shared/data/enemies" then
				return enemies or error("no enemies")
			end
			if path == "src/shared/data/bosses" then
				return bosses or error("no bosses")
			end
			if path == "src/shared/data/scope" then
				return scope or error("no scope")
			end
			if path == "src/shared/data/sfx" and options.sfx ~= nil then
				return options.sfx or error("no sfx")
			end
			return Harness.load(path)
		end,
		listFiles = function(directory: string, _pattern: string?)
			if directory == "src/shared/clips" then
				return files
			end
			error("no such directory " .. directory)
		end,
		readFile = Harness.readFile,
		repoRoot = root,
	})
end

local GOOD_ART = "player/OneHandedSword/TestArt"
local GOOD_CHARGE = "enemy/Boar/TestCharge"

local function goodArts(): any
	return { rows = { ["OneHandedSword.TestArt"] = art("OneHandedSword.TestArt", GOOD_ART, 1) } }
end

local function goodEnemies(): any
	return {
		rows = {
			TestBoar = {
				id = "TestBoar",
				skin = "Boar",
				attacks = { { id = "TestCharge", name = "Charge", windUp = 0.6, clip = "TestCharge" } },
			},
		},
	}
end

describe("clips validator", function()
	it("accepts a well-formed player Art clip, enemy attack clip and idle", function()
		local problems = runClips({
			[GOOD_ART] = playerArtClip(GOOD_ART),
			[GOOD_CHARGE] = enemyChargeClip(GOOD_CHARGE, 0.6),
			["player/OneHandedSword/Idle"] = idleClip("player/OneHandedSword/Idle", "PlayerR15"),
		}, goodArts(), goodEnemies())
		expect(problems).toEqual({})
	end)

	it("reports missing sibling tables and missing clip files", function()
		local problems = runClips({}, nil, nil)
		expect(hasProblem(problems, "arts.luau is missing")).toBe(true)
		expect(hasProblem(problems, "enemies.luau is missing")).toBe(true)
		local arts = goodArts()
		arts.rows["OneHandedSword.Ghost"] = art("OneHandedSword.Ghost", "player/OneHandedSword/Ghost", 1)
		problems = runClips({ [GOOD_ART] = playerArtClip(GOOD_ART) }, arts, { rows = {} })
		expect(#problems).toBe(1)
		expect(problems[1]).toContain("src/shared/clips/player/OneHandedSword/Ghost.luau is missing")
	end)

	it("rejects Linear easing on a limb but allows it on a root-only key", function()
		local clip = playerArtClip(GOOD_ART)
		clip.keys[3].easing = "Linear"
		local problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "Linear easing on a limb")).toBe(true)

		clip = playerArtClip(GOOD_ART)
		table.insert(clip.keys, 4, { time = 15 * F, easing = "Linear", joints = {}, root = { pos = { 0, 0, -1 } } })
		problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(problems).toEqual({})
	end)

	it("checks the id, the rig, the joints, key order and easing names", function()
		local clip = playerArtClip(GOOD_ART)
		clip.id = "player/OneHandedSword/Other"
		clip.keys[2].joints.Tail = { rot = { 1, 0, 0 } }
		clip.keys[2].easing = "Tween"
		clip.keys[3].time = 0.01
		local problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "does not match its path")).toBe(true)
		expect(hasProblem(problems, "joint 'Tail' which is not in rig 'PlayerR15'")).toBe(true)
		expect(hasProblem(problems, "unknown easing 'Tween'")).toBe(true)
		expect(hasProblem(problems, "keys must be sorted")).toBe(true)

		clip = playerArtClip(GOOD_ART)
		clip.rig = "Dragon"
		problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "rig 'Dragon' is not in rigs.luau")).toBe(true)
	end)

	it("requires balanced hit windows and sorted events", function()
		local clip = playerArtClip(GOOD_ART)
		table.remove(clip.events, 6) -- HitWindowClose
		local problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "never closed")).toBe(true)

		clip = playerArtClip(GOOD_ART)
		clip.events[2].time = 0.6
		problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "events must be sorted")).toBe(true)
	end)

	it("enforces the six beats, their order, Snap length and the attack events", function()
		local clip = playerArtClip(GOOD_ART)
		clip.beats.Snap = { start = 6 * F, finish = 12 * F } -- 6 frames
		clip.beats.Hold = nil
		local problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "Snap is 6.0 frames")).toBe(true)
		expect(hasProblem(problems, "beat 'Hold' is missing")).toBe(true)

		clip = playerArtClip(GOOD_ART)
		clip.beats.Recovery.start = clip.beats.Settle.start - F
		clip.hitStop = nil
		for index = #clip.events, 1, -1 do
			local kind = clip.events[index].kind
			if kind == "TrailOff" or kind == "PostMotionStart" or kind == "SmearOn" then
				table.remove(clip.events, index)
			end
		end
		problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "beat 'Settle' must start before 'Recovery'")).toBe(true)
		expect(hasProblem(problems, "needs hitStop")).toBe(true)
		expect(hasProblem(problems, "no TrailOff event")).toBe(true)
		expect(hasProblem(problems, "no SmearOn event")).toBe(true)
		expect(hasProblem(problems, "no PostMotionStart event")).toBe(true)
	end)

	it("a player Anticipation outside 4..10 frames is an error; an enemy's is only a warning", function()
		local clip = playerArtClip(GOOD_ART)
		clip.beats.Anticipation = { start = 0, finish = 2 * F }
		local problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "Anticipation is 2.0 frames")).toBe(true)

		local charge = enemyChargeClip(GOOD_CHARGE, 0.6) -- 36 frames of wind-up
		problems = runClips({ [GOOD_CHARGE] = charge }, { rows = {} }, goodEnemies())
		expect(problems).toEqual({})
	end)

	it("reports a malformed events field instead of crashing", function()
		local clip = playerArtClip(GOOD_ART)
		clip.events = "none"
		local problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "events must be an array")).toBe(true)

		clip = playerArtClip(GOOD_ART)
		clip.events[4] = "HitWindowOpen"
		problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(hasProblem(problems, "event 4 is not a table")).toBe(true)
	end)

	it("resolves every Sfx and Voice event name through sfx.luau", function()
		local clip = playerArtClip(GOOD_ART)
		table.insert(clip.events, { time = 0.5, kind = "Sfx", data = { name = "whoosh.Medium" } })
		table.insert(clip.events, { time = 0.6, kind = "Voice", data = { name = "enemy.ChargerWindUp" } })
		expect(runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })).toEqual({})

		clip = playerArtClip(GOOD_ART)
		table.insert(clip.events, { time = 0.5, kind = "Sfx", data = { name = "ArtSwingLight" } })
		table.insert(clip.events, { time = 0.55, kind = "Sfx", data = { name = "whoosh.Enormous" } })
		table.insert(clip.events, { time = 0.6, kind = "Voice", data = { name = "beast.Roar" } })
		table.insert(clip.events, { time = 0.65, kind = "Voice" })
		local problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} })
		expect(problems).toEqual({
			"player/OneHandedSword/TestArt event 9 (Sfx) sound 'ArtSwingLight' is not a sfx.luau 'family.Name'",
			"player/OneHandedSword/TestArt event 10 (Sfx) sound 'whoosh.Enormous' is not in sfx.luau",
			"player/OneHandedSword/TestArt event 11 (Voice) sound 'beast.Roar' is not in sfx.luau",
			"player/OneHandedSword/TestArt event 12 (Voice) has no data.name naming a sfx.luau sound",
		})

		-- Without the registry nothing resolves: the load failure is the one report for the names
		-- that would need it, and the malformed or missing names are still reported.
		problems = runClips({ [GOOD_ART] = clip }, goodArts(), { rows = {} }, { sfx = false })
		expect(#problems).toBe(3)
		expect(problems[1]).toContain("src/shared/data/sfx.luau is missing or failed to load")
		expect(problems[2]).toContain("sound 'ArtSwingLight' is not a sfx.luau 'family.Name'")
		expect(problems[3]).toContain("event 12 (Voice) has no data.name")
	end)

	it("cross-checks Art hits and duration against the clip", function()
		local arts = goodArts()
		arts.rows["OneHandedSword.TestArt"].hits = 3
		arts.rows["OneHandedSword.TestArt"].total = 0.9
		local problems = runClips({ [GOOD_ART] = playerArtClip(GOOD_ART) }, arts, { rows = {} })
		expect(hasProblem(problems, "has 1 hit windows but the Art has 3 hits")).toBe(true)
		expect(hasProblem(problems, "duration 0.7 is shorter than the Art's total 0.9")).toBe(true)
	end)

	it("a guard Art with 0 hits may have a clip without hit windows", function()
		local clip = playerArtClip(GOOD_ART)
		for index = #clip.events, 1, -1 do
			local kind = clip.events[index].kind
			if kind == "HitWindowOpen" or kind == "HitWindowClose" then
				table.remove(clip.events, index)
			end
		end
		local arts = goodArts()
		arts.rows["OneHandedSword.TestArt"].hits = 0
		local problems = runClips({ [GOOD_ART] = clip }, arts, { rows = {} })
		expect(problems).toEqual({})
		problems = runClips({ [GOOD_ART] = clip }, { rows = {} }, { rows = {} })
		expect(hasProblem(problems, "no HitWindowOpen/HitWindowClose pair")).toBe(true)
	end)

	it("cross-checks enemy wind-ups against the Anticipation beat", function()
		local problems = runClips({ [GOOD_CHARGE] = enemyChargeClip(GOOD_CHARGE, 0.3) }, { rows = {} }, goodEnemies())
		expect(hasProblem(problems, "holds Anticipation for 0.30 s but the attack's windUp is 0.60 s")).toBe(true)

		problems = runClips({ [GOOD_CHARGE] = enemyChargeClip(GOOD_CHARGE, 0.56) }, { rows = {} }, goodEnemies())
		expect(problems).toEqual({})

		problems = runClips({}, { rows = {} }, goodEnemies())
		expect(hasProblem(problems, "enemy/Boar/TestCharge.luau is missing")).toBe(true)
	end)

	it("a missing clip outside the phase scope is summarized, not reported; inside it stays a problem", function()
		local arts = goodArts()
		arts.rows["OneHandedSword.Ghost"] = art("OneHandedSword.Ghost", "player/OneHandedSword/Ghost", 1)
		local enemies = goodEnemies()
		enemies.rows.LaterWolf = {
			id = "LaterWolf",
			skin = "DireWolf",
			attacks = { { id = "Lunge", name = "Lunge", windUp = 0.4, clip = "Lunge" } },
		}
		local scope = scopeOf({ arts = { "OneHandedSword.TestArt" }, enemies = { "TestBoar" } })
		local problems = runClips({
			[GOOD_ART] = playerArtClip(GOOD_ART),
			[GOOD_CHARGE] = enemyChargeClip(GOOD_CHARGE, 0.6),
		}, arts, enemies, { scope = scope })
		expect(problems).toEqual({})

		problems = runClips({}, arts, enemies, { scope = scope })
		expect(problems).toEqual({
			"Art OneHandedSword.TestArt: clip file src/shared/clips/player/OneHandedSword/TestArt.luau is missing",
			"enemy TestBoar attack TestCharge: clip file src/shared/clips/enemy/Boar/TestCharge.luau is missing",
		})
	end)

	it("a present clip is validated in full whatever the scope says", function()
		local clip = playerArtClip(GOOD_ART)
		clip.keys[3].easing = "Linear"
		local arts = goodArts()
		arts.rows["OneHandedSword.TestArt"].hits = 3
		local problems = runClips({ [GOOD_ART] = clip }, arts, { rows = {} }, { scope = scopeOf({}) })
		expect(hasProblem(problems, "Linear easing on a limb")).toBe(true)
		expect(hasProblem(problems, "has 1 hit windows but the Art has 3 hits")).toBe(true)
	end)

	it("boss attack clips are cross-checked like enemy attacks, phase by phase", function()
		local function bosses(): any
			return {
				rows = {
					TestBoss = {
						id = "TestBoss",
						skin = "Boar",
						phases = {
							{
								bar = 1,
								attacks = { { id = "TestCharge", name = "Charge", windUp = 0.6, clip = "TestCharge" } },
							},
							{ bar = 3, attacks = { { id = "Rush", name = "Rush", windUp = 0.8, clip = "Rush" } } },
						},
					},
				},
			}
		end
		local inScope = { scope = scopeOf({ bosses = { "TestBoss" } }), bosses = bosses() }
		local problems = runClips(
			{ [GOOD_CHARGE] = enemyChargeClip(GOOD_CHARGE, 0.6) },
			{ rows = {} },
			{ rows = {} },
			inScope
		)
		expect(problems).toEqual({
			"boss TestBoss phase 2 attack Rush: clip file src/shared/clips/enemy/Boar/Rush.luau is missing",
		})

		problems = runClips(
			{ [GOOD_CHARGE] = enemyChargeClip(GOOD_CHARGE, 0.3) },
			{ rows = {} },
			{ rows = {} },
			inScope
		)
		expect(
			hasProblem(
				problems,
				"boss TestBoss phase 1 attack TestCharge: clip enemy/Boar/TestCharge holds Anticipation for 0.30 s"
			)
		).toBe(true)

		local outOfScope = { scope = scopeOf({}), bosses = bosses() }
		problems = runClips({}, { rows = {} }, { rows = {} }, outOfScope)
		expect(problems).toEqual({})
	end)

	it("the backlog is printed as ONE warning naming the phase, counted once per clip id", function()
		local arts = goodArts()
		arts.rows["OneHandedSword.Ghost"] = art("OneHandedSword.Ghost", "player/OneHandedSword/Ghost", 1)
		arts.rows["OneHandedSword.Wraith"] = art("OneHandedSword.Wraith", "player/OneHandedSword/Wraith", 1)
		local enemies = {
			rows = {
				LaterWolf = {
					id = "LaterWolf",
					skin = "DireWolf",
					attacks = { { id = "Lunge", name = "Lunge", windUp = 0.4, clip = "Lunge" } },
				},
			},
		}
		local rush = { id = "Rush", name = "Rush", windUp = 0.8, clip = "Rush" }
		local bosses = {
			rows = {
				TestBoss = {
					id = "TestBoss",
					skin = "Boar",
					-- the same clip in two phases counts once
					phases = { { bar = 1, attacks = { rush } }, { bar = 3, attacks = { rush } } },
				},
			},
		}
		local scope = scopeOf({ arts = { "OneHandedSword.TestArt" } })
		scope.phase = 2
		local prints = {}
		local problems = runClips(
			{ [GOOD_ART] = playerArtClip(GOOD_ART) },
			arts,
			enemies,
			{ scope = scope, bosses = bosses, prints = prints }
		)
		expect(problems).toEqual({})
		expect(prints).toEqual({
			"  ~ clips warning: 4 clips for later phases are not authored yet (outside the phase 2 scope): "
				.. "2 Arts, 1 enemy attacks, 1 boss attacks",
		})

		-- Nothing outside the scope is missing: no backlog line at all.
		prints = {}
		problems = runClips({ [GOOD_ART] = playerArtClip(GOOD_ART) }, goodArts(), { rows = {} }, { prints = prints })
		expect(problems).toEqual({})
		expect(prints).toEqual({})
	end)

	it("without scope.luau the missing table is reported and every missing clip stays a problem", function()
		local arts = goodArts()
		arts.rows["OneHandedSword.Ghost"] = art("OneHandedSword.Ghost", "player/OneHandedSword/Ghost", 1)
		local problems = runClips({ [GOOD_ART] = playerArtClip(GOOD_ART) }, arts, { rows = {} }, { scope = false })
		expect(hasProblem(problems, "scope.luau is missing or failed to load")).toBe(true)
		expect(hasProblem(problems, "player/OneHandedSword/Ghost.luau is missing")).toBe(true)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Scope
-- ------------------------------------------------------------------------------------------

-- A scope.luau stand-in whose has* helpers answer from its lists unless a field overrides them.
local function fakeScope(fields: { [string]: any }): any
	local scope = {
		phase = if fields.phase == nil then 0 else fields.phase,
		arts = fields.arts or {},
		enemies = fields.enemies or {},
		bosses = fields.bosses or {},
		rigs = fields.rigs or {},
	}
	local function has(list: { string }): (string) -> boolean
		return function(id: string): boolean
			return table.find(list, id) ~= nil
		end
	end
	scope.hasArt = fields.hasArt or has(scope.arts)
	scope.hasEnemy = fields.hasEnemy or has(scope.enemies)
	scope.hasBoss = fields.hasBoss or has(scope.bosses)
	scope.hasRig = fields.hasRig or has(scope.rigs)
	return scope
end

local function runScope(scope: any): { string }
	local validate = loadTool("tools/validators/scope")
	return validate({
		load = function(path: string)
			if path == "src/shared/data/scope" then
				return scope
			end
			return Harness.load(path)
		end,
		listFiles = Harness.listFiles,
		readFile = Harness.readFile,
		repoRoot = root,
	})
end

describe("scope validator", function()
	it("accepts a scope whose ids resolve and whose rigs cover its enemies", function()
		local problems = runScope(fakeScope({
			arts = { "OneHandedSword.Horizontal", "Rapier.Linear" },
			enemies = { "FrenzyBoar" },
			rigs = { "PlayerR15", "Boar" },
		}))
		expect(problems).toEqual({})
	end)

	it("rejects a fractional phase, unknown ids, duplicates and a rig the in-scope rows need", function()
		local problems = runScope(fakeScope({
			phase = 1.5,
			arts = { "OneHandedSword.Horizontal", "OneHandedSword.Horizontal", "OneHandedSword.Nope" },
			enemies = { "KoboldAxeman" },
			bosses = { "Grolak", "NotABoss" },
			rigs = { "Boar", "Dragon" },
		}))
		expect(hasProblem(problems, "scope.phase: must be a non-negative integer (got 1.5)")).toBe(true)
		expect(hasProblem(problems, "scope.arts[2]: 'OneHandedSword.Horizontal' is listed twice")).toBe(true)
		expect(hasProblem(problems, "scope.arts[3]: 'OneHandedSword.Nope' is not a row of arts.luau")).toBe(true)
		expect(hasProblem(problems, "scope.bosses[2]: 'NotABoss' is not a row of bosses.luau")).toBe(true)
		expect(hasProblem(problems, "scope.rigs[2]: 'Dragon' is not a row of rigs.luau")).toBe(true)
		expect(hasProblem(problems, "scope.enemies: 'KoboldAxeman' is in scope but its rig 'Kobold' is not")).toBe(true)
		expect(hasProblem(problems, "scope.bosses: 'Grolak' is in scope but its rig 'KoboldWarlord' is not")).toBe(true)
		expect(#problems).toBe(7)

		problems = runScope(fakeScope({ phase = -1 }))
		expect(problems).toEqual({ "scope.phase: must be a non-negative integer (got -1)" })
	end)

	it("reports helpers that are missing or disagree with their lists", function()
		local problems = runScope(fakeScope({
			arts = { "OneHandedSword.Horizontal" },
			rigs = { "PlayerR15" },
			hasArt = function(_id: string): boolean
				return false
			end,
			hasRig = function(_id: string): boolean
				return true
			end,
			hasBoss = "no",
		}))
		expect(hasProblem(problems, "scope.hasArt: returns false for the listed id 'OneHandedSword.Horizontal'")).toBe(
			true
		)
		expect(hasProblem(problems, "scope.hasRig: returns true for an id that is not listed")).toBe(true)
		expect(hasProblem(problems, "scope.hasBoss: must be a function")).toBe(true)
		expect(#problems).toBe(3)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Magic numbers
-- ------------------------------------------------------------------------------------------

local function runNumbers(source: string): { string }
	local validate = loadTool("tools/validators/numbers")
	local path = "src/server/services/FakeService.luau"
	return validate({
		load = Harness.load,
		listFiles = function(directory: string, _pattern: string?)
			if directory == "src/server/services" then
				return { path }
			end
			error("no such directory " .. directory)
		end,
		readFile = function(_path: string)
			return source
		end,
		repoRoot = root,
	})
end

describe("numbers validator", function()
	it("flags literals outside the allowlist and reports the line", function()
		local problems = runNumbers(table.concat({
			"--!strict",
			"local a = 0.35",
			"local b = 60 + 100 - 180 + 360 + 255 + 90 + 45 + 30 + 20 + 10 + 2 - 1 + 0",
			"local c = 1e-6 + 1e6 + 0.5 - 0.5",
			"local d = 1.5",
			"local e = 7",
		}, "\n"))
		expect(#problems).toBe(3)
		expect(problems[1]).toContain(":2: magic number 0.35")
		expect(problems[2]).toContain(":5: magic number 1.5")
		expect(problems[3]).toContain(":6: magic number 7")
	end)

	it("honours unit: and index: comments", function()
		local problems = runNumbers(table.concat({
			"local a = 1000 -- unit: milliseconds per second",
			"local b = list[4] -- index: the fourth joint",
			"local c = 3 -- not a unit",
		}, "\n"))
		expect(#problems).toBe(1)
		expect(problems[1]).toContain(":3: magic number 3")
	end)

	it("skips comments, strings, require lines and identifiers with digits", function()
		local problems = runNumbers(table.concat({
			"-- a comment with 42 in it",
			"--[[ a block",
			"with 99 inside",
			"]]",
			"local s = \"a string with 42 inside\" .. 'and 17 here'",
			"local r = require(script.Parent.Parent.data.combat)",
			"local v = Vector3.new(1, 2, 0) + UDim2.fromScale(0.5, 0.5)",
			"local long = [[ 55 ]]",
			"local x = 5 --[[ trailing 66 ]]",
		}, "\n"))
		expect(#problems).toBe(1)
		expect(problems[1]).toContain(":9: magic number 5")
	end)

	it("allows Vec3 component indices and loops but not a bare 3", function()
		local problems = runNumbers(table.concat({
			"local z = pos[3] + rot[ 3 ]",
			"for axis = 1, 3 do end",
			"local frames = 3",
			"local w = t[4]",
		}, "\n"))
		expect(#problems).toBe(2)
		expect(problems[1]).toContain(":3: magic number 3")
		expect(problems[2]).toContain(":4: magic number 4")
	end)

	it("reads hex, exponents and signs correctly", function()
		local problems = runNumbers(table.concat({
			"local a = 0xFF",
			"local b = 0x10",
			"local c = -0.5 + -60",
			"local d = 3-5",
			"local e = 2e3",
		}, "\n"))
		expect(#problems).toBe(4)
		expect(problems[1]).toContain(":2: magic number 0x10")
		expect(problems[2]).toContain(":4: magic number 3")
		expect(problems[3]).toContain(":4: magic number 5")
		expect(problems[4]).toContain(":5: magic number 2e3")
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Data-table validators on the real tables
-- ------------------------------------------------------------------------------------------

describe("data validators on the real tables", function()
	for _, name in
		{
			"floors",
			"origins",
			"paths",
			"lighting",
			"sfx",
			"assets",
			"playground",
			"palette-usage",
			"numbers",
			"scope",
			"clips",
		}
	do
		it(name .. " is clean", function()
			local validate = loadTool("tools/validators/" .. name)
			expect(validate(realContext)).toEqual({})
		end)
	end

	it("clips demands every clip the real scope.luau lists: hiding an in-scope file is a problem", function()
		local hidden = {
			["src/shared/clips/player/OneHandedSword/SharpNail.luau"] = true,
			["src/shared/clips/enemy/Boar/Charge.luau"] = true,
		}
		local context = table.clone(realContext)
		context.listFiles = function(directory: string, pattern: string?): { string }
			local files = {}
			for _, file in Harness.listFiles(directory, pattern) do
				if not hidden[file] then
					table.insert(files, file)
				end
			end
			return files
		end
		local validate = loadTool("tools/validators/clips")
		expect(validate(context)).toEqual({
			"Art OneHandedSword.SharpNail: clip file src/shared/clips/player/OneHandedSword/SharpNail.luau is missing",
			"enemy FrenzyBoar attack Charge: clip file src/shared/clips/enemy/Boar/Charge.luau is missing",
		})
	end)
end)
