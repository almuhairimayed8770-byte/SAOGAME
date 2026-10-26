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

-- A three-hit Art shaped like Sharp Nail: the first strike is the beats table's Snap (6f..9f);
-- the second and third re-wind (QuadIn) and snap (ExpoOut, 3 frames) at 26f..29f and 44f..47f.
-- Each hit window opens on its snap's first frame and closes in the settle.
local function threeHitArtClip(id: string): any
	local function arm(x: number): any
		return { RightShoulder = { rot = { x, 0, 0 } } }
	end
	local clip = playerArtClip(id)
	clip.duration = 1.2
	clip.beats.Recovery = { start = 60 * F, finish = 1.2 }
	clip.keys = {
		{ time = 0, easing = "Hold", joints = arm(0) },
		{ time = 6 * F, easing = "ExpoIn", joints = arm(-80) },
		{ time = 9 * F, easing = "ExpoOut", joints = arm(60) },
		{ time = 20 * F, easing = "Spring", joints = arm(54) },
		{ time = 26 * F, easing = "QuadIn", joints = arm(70) },
		{ time = 29 * F, easing = "ExpoOut", joints = arm(-40) },
		{ time = 38 * F, easing = "Spring", joints = arm(-34) },
		{ time = 44 * F, easing = "QuadIn", joints = arm(-60) },
		{ time = 47 * F, easing = "ExpoOut", joints = arm(85) },
		{ time = 60 * F, easing = "Spring", joints = arm(80) },
		{ time = 1.2, easing = "SineInOut", joints = arm(78), root = { pos = { 0, 0, -2 } } },
	}
	clip.events = {
		{ time = 0, kind = "ActivationHold" },
		{ time = 6 * F, kind = "TrailOn" },
		{ time = 6 * F, kind = "SmearOn" },
		{ time = 6 * F, kind = "HitWindowOpen" },
		{ time = 8 * F, kind = "SmearOff" },
		{ time = 14 * F, kind = "HitWindowClose" },
		{ time = 26 * F, kind = "SmearOn" },
		{ time = 26 * F, kind = "HitWindowOpen" },
		{ time = 28 * F, kind = "SmearOff" },
		{ time = 34 * F, kind = "HitWindowClose" },
		{ time = 44 * F, kind = "SmearOn" },
		{ time = 44 * F, kind = "HitWindowOpen" },
		{ time = 46 * F, kind = "SmearOff" },
		{ time = 54 * F, kind = "HitWindowClose" },
		{ time = 56 * F, kind = "TrailOff" },
		{ time = 60 * F, kind = "PostMotionStart" },
	}
	return clip
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

type ClipsExtra = { scope: any?, bosses: any?, sfx: any?, choreo: any?, prints: { string }? }

-- The real idle phase step (D-123): every choreo stand-in carries it.
local IDLE_PHASE_STEP = Harness.load("src/shared/data/choreo").enemyIdlePhaseStep

-- A choreo.luau stand-in that names no locomotion or sheath clips (the synthetic trees hold none).
local function emptyChoreo(): any
	return {
		priority = { Sheath = 8 },
		locomotion = { clipPrefix = "player/OneHandedSword/", clips = {} },
		sheath = { clips = {}, drawCutClips = {} },
		enemyIdlePhaseStep = IDLE_PHASE_STEP,
	}
end

-- `extra.scope` / `extra.bosses` / `extra.sfx` / `extra.choreo`: nil for the defaults (everything
-- in scope, no bosses, the real sfx.luau, a choreo naming no clips), false for a table that fails
-- to load, or a fake module. `extra.prints` collects the printed warnings.
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
			if path == "src/shared/data/choreo" then
				if options.choreo == nil then
					return emptyChoreo()
				end
				return options.choreo or error("no choreo")
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

	it("every hit window covers its strike's snap: on or before the snap start, through the snap end", function()
		-- Passing: windows on their snaps (one hit and three), and a window that opens a little early.
		expect(runClips({ [GOOD_ART] = playerArtClip(GOOD_ART) }, goodArts(), { rows = {} })).toEqual({})
		local threeHits = goodArts()
		threeHits.rows["OneHandedSword.TestArt"].hits = 3
		expect(runClips({ [GOOD_ART] = threeHitArtClip(GOOD_ART) }, threeHits, { rows = {} })).toEqual({})
		local early = playerArtClip(GOOD_ART)
		local open = table.remove(early.events, 4) -- HitWindowOpen at 6f
		open.time = 4 * F
		table.insert(early.events, 2, open)
		expect(runClips({ [GOOD_ART] = early }, goodArts(), { rows = {} })).toEqual({})

		-- Failing: the window opens 0.6 frames into the 3-frame ExpoOut snap (the cut is mostly done
		-- before the server sweeps), and one closes before its snap has landed.
		local late = playerArtClip(GOOD_ART)
		late.events[4].time = 6.6 * F
		expect(runClips({ [GOOD_ART] = late }, goodArts(), { rows = {} })).toEqual({
			"player/OneHandedSword/TestArt: hit window 1 opens 0.60 frames after its snap starts (f 6.00)",
		})
		local short = playerArtClip(GOOD_ART)
		local close = table.remove(short.events, 6) -- HitWindowClose, moved inside the 6f..9f snap
		close.time = 8.5 * F
		table.insert(short.events, 5, close)
		expect(runClips({ [GOOD_ART] = short }, goodArts(), { rows = {} })).toEqual({
			"player/OneHandedSword/TestArt: hit window 1 closes 0.50 frames before its snap ends (f 9.00)",
		})

		-- A later hit of a combo is paired with its own strike: hit 2 regressed, hit 3 cut short.
		local regressed = threeHitArtClip(GOOD_ART)
		regressed.events[8].time = 27 * F -- the second HitWindowOpen, a frame into its snap
		regressed.events[14].time = 46 * F -- the third HitWindowClose, before its snap lands at 47f
		expect(runClips({ [GOOD_ART] = regressed }, threeHits, { rows = {} })).toEqual({
			"player/OneHandedSword/TestArt: hit window 2 opens 1.00 frames after its snap starts (f 26.00)",
			"player/OneHandedSword/TestArt: hit window 3 closes 1.00 frames before its snap ends (f 47.00)",
		})

		-- A strike with no snap in the budget leaves a window unpaired.
		local unpaired = threeHitArtClip(GOOD_ART)
		unpaired.keys[9].easing = "QuadOut" -- the third strike no longer snaps
		expect(runClips({ [GOOD_ART] = unpaired }, threeHits, { rows = {} })).toEqual({
			"player/OneHandedSword/TestArt: 3 hit windows but 2 strike snaps (ExpoOut keys 2..4 frames after the key before)",
		})

		-- Enemy clips are held to the same rule: a Charger whose window waits for the end of the rush.
		local rush = enemyChargeClip(GOOD_CHARGE, 0.6)
		rush.events[3].time = 0.6 + 10 * F -- HitWindowOpen
		local closeAt = table.remove(rush.events, 5) -- HitWindowClose
		closeAt.time = 0.6 + 14 * F
		table.insert(rush.events, closeAt)
		table.sort(rush.events, function(a, b)
			return a.time < b.time
		end)
		expect(runClips({ [GOOD_CHARGE] = rush }, { rows = {} }, goodEnemies())).toEqual({
			"enemy/Boar/TestCharge: hit window 1 opens 10.00 frames after its snap starts (f 36.00)",
		})

		-- Malformed keys are reported once and never reach the snap derivation.
		local broken = playerArtClip(GOOD_ART)
		broken.keys = "none"
		local problems = runClips({ [GOOD_ART] = broken }, goodArts(), { rows = {} })
		expect(problems).toEqual({ "player/OneHandedSword/TestArt: keys must be an array" })
	end)

	it("lists the TrailOn that names the trail kind before the first HitWindowOpen on the same frame", function()
		-- The trail ignites with the window on the snap's first frame; the kind it names must come first.
		local named = enemyChargeClip(GOOD_CHARGE, 0.6)
		named.events[1].time = 0.6
		named.events[1].data = { kind = "Basic" }
		expect(runClips({ [GOOD_CHARGE] = named }, { rows = {} }, goodEnemies())).toEqual({})

		-- The same events with the window listed first: the client would light the Art trail.
		local swapped = enemyChargeClip(GOOD_CHARGE, 0.6)
		local trailOn = table.remove(swapped.events, 1)
		trailOn.time = 0.6
		trailOn.data = { kind = "Basic" }
		table.insert(swapped.events, 3, trailOn) -- after SmearOn and HitWindowOpen at 0.6
		expect(runClips({ [GOOD_CHARGE] = swapped }, { rows = {} }, goodEnemies())).toEqual({
			"enemy/Boar/TestCharge: HitWindowOpen (event 2) is listed before the TrailOn that names the trail kind (event 3)",
		})
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

	-- The sheathed weapon (D-050): a sheathed Run with its RunDrawn, and the Draw and Sheathe clips.
	local function sheathTree(): { [string]: any }
		local function loco(id: string, sheathed: boolean?): any
			return {
				id = id,
				rig = "PlayerR15",
				duration = 0.6,
				loop = true,
				sheathed = sheathed,
				layer = "Base",
				keys = {
					{ time = 0, easing = "SineInOut", joints = { LeftHip = { rot = { 30, 0, 0 } } } },
					{ time = 0.3, easing = "SineInOut", joints = { LeftHip = { rot = { -30, 0, 0 } } } },
				},
				events = {
					{ time = 0.02, kind = "Footstep", data = { foot = "Left" } },
					{ time = 0.32, kind = "Footstep", data = { foot = "Right" } },
				},
			}
		end
		local runDrawn = loco("player/OneHandedSword/RunDrawn", nil)
		runDrawn.keys[1].joints.Weapon = { rot = { -50, 0, 0 } }
		return {
			["player/OneHandedSword/Run"] = loco("player/OneHandedSword/Run", true),
			["player/OneHandedSword/RunDrawn"] = runDrawn,
			["player/OneHandedSword/Draw"] = {
				id = "player/OneHandedSword/Draw",
				rig = "PlayerR15",
				duration = 0.6,
				loop = false,
				sheathed = true,
				layer = "UpperBody",
				priority = 8,
				keys = {
					{ time = 0, easing = "SineInOut", joints = { RightShoulder = { rot = { 30, 0, 10 } } } },
					{
						time = 0.22,
						easing = "QuadOut",
						joints = { RightShoulder = { rot = { 170, 30, 0 } }, Weapon = { rot = { -6, -77, -3 } } },
					},
				},
				events = { { time = 0.22, kind = "WeaponDraw" } },
			},
			["player/OneHandedSword/Sheathe"] = {
				id = "player/OneHandedSword/Sheathe",
				rig = "PlayerR15",
				duration = 0.7,
				loop = false,
				layer = "UpperBody",
				priority = 8,
				keys = {
					{
						time = 0,
						easing = "SineInOut",
						joints = { RightShoulder = { rot = { 3, 0, 4 } }, Weapon = { rot = { 0, 0, 0 } } },
					},
					{ time = 0.42, easing = "QuadOut", joints = { RightShoulder = { rot = { 170, 30, 0 } } } },
				},
				events = { { time = 0.42, kind = "WeaponSheathe" } },
			},
			["player/OneHandedSword/Guard"] = idleClip("player/OneHandedSword/Guard", "PlayerR15"),
		}
	end

	local function sheathChoreo(): any
		return {
			priority = { Sheath = 8 },
			locomotion = { clipPrefix = "player/OneHandedSword/", clips = { Run = "Run", RunDrawn = "RunDrawn" } },
			sheath = { clips = { draw = "Draw", sheathe = "Sheathe" }, drawCutClips = { "Guard" } },
			enemyIdlePhaseStep = IDLE_PHASE_STEP,
		}
	end

	-- The choreo stand-in names only the Run pair; the validator skips the names it does not list.
	it("accepts WeaponDraw and WeaponSheathe events, the sheathed field and a matching pair", function()
		local problems = runClips(sheathTree(), { rows = {} }, { rows = {} }, { choreo = sheathChoreo() })
		expect(problems).toEqual({})
		local choreo = sheathChoreo()
		choreo.locomotion.clips.RunDrawn = nil
		problems = runClips(sheathTree(), { rows = {} }, { rows = {} }, { choreo = choreo })
		expect(problems).toEqual({ "locomotion.clips needs both Run and RunDrawn" })
	end)

	it("names a missing RunDrawn file by its key and path", function()
		local clips = sheathTree()
		clips["player/OneHandedSword/RunDrawn"] = nil
		local problems = runClips(clips, { rows = {} }, { rows = {} }, { choreo = sheathChoreo() })
		expect(problems).toEqual({
			"locomotion.clips RunDrawn: clip file src/shared/clips/player/OneHandedSword/RunDrawn.luau is missing",
		})
	end)

	it("flags a sheathed Run whose duration, loop or footsteps differ from RunDrawn", function()
		local clips = sheathTree()
		clips["player/OneHandedSword/Run"].duration = 0.65
		local problems = runClips(clips, { rows = {} }, { rows = {} }, { choreo = sheathChoreo() })
		expect(problems).toEqual({
			"player/OneHandedSword/Run: duration 0.65 differs from player/OneHandedSword/RunDrawn's 0.6 (the sets crossfade in step)",
		})

		clips = sheathTree()
		clips["player/OneHandedSword/Run"].events[2].time = 0.35
		clips["player/OneHandedSword/Run"].events[1].data.foot = "Right"
		problems = runClips(clips, { rows = {} }, { rows = {} }, { choreo = sheathChoreo() })
		expect(hasProblem(problems, "Footstep 2 at 0.35 s is more than a frame from")).toBe(true)
		expect(hasProblem(problems, "Footstep 1 plants the Right foot but player/OneHandedSword/RunDrawn")).toBe(true)
	end)

	it("flags a sheathed clip that keys Weapon and a drawn clip marked sheathed", function()
		local clips = sheathTree()
		clips["player/OneHandedSword/Run"].keys[1].joints.Weapon = { rot = { -50, 0, 0 } }
		clips["player/OneHandedSword/RunDrawn"].sheathed = true
		clips["player/OneHandedSword/RunDrawn"].keys[1].joints.Weapon = nil
		local problems = runClips(clips, { rows = {} }, { rows = {} }, { choreo = sheathChoreo() })
		expect(problems).toEqual({
			"player/OneHandedSword/Run: key 1 moves Weapon while the sword is on the back",
			"player/OneHandedSword/RunDrawn: the drawn set's RunDrawn must not be sheathed",
		})
	end)

	it("holds Draw and Sheathe to one event each, UpperBody, the Sheath priority, and a sheathed Draw", function()
		local clips = sheathTree()
		local draw = clips["player/OneHandedSword/Draw"]
		draw.sheathed = nil
		draw.keys[2].joints.Weapon = nil
		draw.events = {}
		clips["player/OneHandedSword/Sheathe"].layer = "FullBody"
		clips["player/OneHandedSword/Sheathe"].priority = 5
		local problems = runClips(clips, { rows = {} }, { rows = {} }, { choreo = sheathChoreo() })
		expect(problems).toEqual({
			"player/OneHandedSword/Draw: the draw clip must be sheathed (the sword starts on the back)",
			"player/OneHandedSword/Draw: needs exactly one WeaponDraw event (has 0)",
			"player/OneHandedSword/Sheathe: must be on the UpperBody layer (got FullBody)",
			"player/OneHandedSword/Sheathe: priority 5 must equal choreo priority.Sheath (8)",
		})
	end)

	it("names a missing draw-cut clip, an unknown sheath event and a missing choreo.luau", function()
		local clips = sheathTree()
		clips["player/OneHandedSword/Guard"] = nil
		local problems = runClips(clips, { rows = {} }, { rows = {} }, { choreo = sheathChoreo() })
		expect(problems).toEqual({
			"sheath.drawCutClips Guard: clip file src/shared/clips/player/OneHandedSword/Guard.luau is missing",
		})
		problems = runClips(sheathTree(), { rows = {} }, { rows = {} }, { choreo = false })
		expect(hasProblem(problems, "src/shared/data/choreo.luau is missing or failed to load")).toBe(true)
	end)

	it("keeps the enemy idle phase step spread over a run of ids and every enemy rig's idle and walk a loop", function()
		local tree = {
			["enemy/Boar/Idle"] = idleClip("enemy/Boar/Idle", "Boar"),
			["enemy/Boar/Walk"] = idleClip("enemy/Boar/Walk", "Boar"),
		}
		local function run(step: any, walkLoops: boolean): { string }
			local choreo = emptyChoreo()
			choreo.enemyIdlePhaseStep = step
			choreo.rigs = { Boar = { idle = "enemy/Boar/Idle", walk = "enemy/Boar/Walk" } }
			tree["enemy/Boar/Walk"].loop = walkLoops
			return runClips(tree, { rows = {} }, { rows = {} }, { choreo = choreo })
		end
		expect(run(IDLE_PHASE_STEP, true)).toEqual({})
		expect(run(IDLE_PHASE_STEP, false)).toEqual({
			"choreo rigs.Boar walk enemy/Boar/Walk must loop: it starts at the rig's idle phase (D-123)",
		})
		local outside = "choreo enemyIdlePhaseStep must be a number above 0 and below 1"
		for _, step in { 0, 1, -0.2, 1.4, "half" } :: { any } do
			expect(run(step, true)).toEqual({ outside })
		end
		expect(run(nil, true)).toEqual({ outside })
		-- Two ids in a row share a phase at a half step; a quarter step brings back the first of
		-- five; a tenth keeps two ids a tenth apart, under a sixth; 0.38 spreads like the golden step.
		expect(run(0.5, true)).toEqual({
			"choreo enemyIdlePhaseStep 0.5 puts two of 3 ids in a row closer than 1/9 of the loop",
		})
		expect(run(0.25, true)).toEqual({
			"choreo enemyIdlePhaseStep 0.25 puts two of 5 ids in a row closer than 1/15 of the loop",
		})
		expect(run(0.1, true)).toEqual({
			"choreo enemyIdlePhaseStep 0.1 puts two of 2 ids in a row closer than 1/6 of the loop",
		})
		expect(run(0.38, true)).toEqual({})
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
			"content",
			"world",
			"camera",
			"dev",
			"contact",
			"telegraph",
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

	it("clips demands every locomotion and sheath clip the real choreo.luau names", function()
		local hidden = {
			["src/shared/clips/player/OneHandedSword/RunDrawn.luau"] = true,
			["src/shared/clips/player/OneHandedSword/Draw.luau"] = true,
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
			"locomotion.clips RunDrawn: clip file src/shared/clips/player/OneHandedSword/RunDrawn.luau is missing",
			"sheath.clips draw: clip file src/shared/clips/player/OneHandedSword/Draw.luau is missing",
		})
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Impact frames: the flash safety limits and the sequences that ride on hit-stop
-- ------------------------------------------------------------------------------------------

describe("impact validator", function()
	local function deepCopy(value: any): any
		if typeof(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, element in value do
			copy[key] = deepCopy(element)
		end
		return copy
	end

	-- Runs the impact validator on a copy of the real impact.luau that `mutate` breaks.
	local function runImpact(mutate: (impact: any) -> (), mutateCombat: ((combat: any) -> ())?): { string }
		local impact = deepCopy(Harness.load("src/shared/data/impact"))
		mutate(impact)
		local combat = deepCopy(Harness.load("src/shared/data/combat"))
		if mutateCombat ~= nil then
			mutateCombat(combat)
		end
		local validate = loadTool("tools/validators/impact")
		return validate({
			load = function(path: string)
				if path == "src/shared/data/impact" then
					return impact
				end
				if path == "src/shared/data/combat" then
					return combat
				end
				return Harness.load(path)
			end,
			listFiles = Harness.listFiles,
			readFile = Harness.readFile,
			repoRoot = root,
		})
	end

	it("is clean on the real table", function()
		expect(runImpact(function() end)).toEqual({})
		expect(loadTool("tools/validators/impact")(realContext)).toEqual({})
	end)

	it("catches look tokens that are not in the palette and a bright look with nothing drawn on it", function()
		local problems = runImpact(function(impact)
			impact.looks.Dark.figures = "Magenta"
			impact.looks.Ink.background = "#FFFFFF"
			-- A plain white frame: a bare flash with no fighter in it.
			impact.looks.Blank = { background = "SystemWhite", figures = nil, strokes = false }
		end)
		expect(problems).toEqual({
			"impact: looks.Blank draws nothing on a bright field (relative luminance 0.95, at most 0.20): a bare flash",
			"impact: looks.Dark.figures 'Magenta' is not a palette token",
			"impact: looks.Ink.background '#FFFFFF' is not a palette token",
		})
	end)

	it("catches a missing or shared rank: which sequence replaces which must be clear", function()
		local problems = runImpact(function(impact)
			impact.sequences.Final.rank = impact.sequences.Kill.rank
			impact.sequences.Parry.rank = 0.5
		end)
		expect(problems).toEqual({
			"impact: sequences.Kill.rank 3 is also sequences.Final's: which one replaces the other?",
			"impact: sequences.Parry.rank 0.5 must be a whole number of at least 1",
		})
	end)

	it("catches a sequence that outlasts the hit-stop it rides on", function()
		local problems = runImpact(function(impact)
			impact.sequences.Final.steps = { { look = "Dark", frames = 7 } }
			impact.sequences.Parry.tier = "Normal"
			impact.sequences.Parry.steps = { { look = "Inverted", frames = 4 } }
		end)
		expect(problems).toEqual({
			"impact: sequences.Final holds 7 frames, more than the Final hit-stop's 6",
			"impact: sequences.Parry holds 4 frames, more than the Normal hit-stop's 3",
		})
	end)

	it("catches a step with an unknown look, a fractional frame count and an unknown tier", function()
		local problems = runImpact(function(impact)
			impact.sequences.Kill.steps[2] = { look = "Nope", frames = 1.5 }
			impact.sequences.Final.tier = "Huge"
		end)
		expect(hasProblem(problems, "sequences.Kill.steps[2] look 'Nope' is not a look")).toBe(true)
		expect(hasProblem(problems, "sequences.Kill.steps[2] frames 1.5 must be a whole number of at least 1")).toBe(
			true
		)
		expect(hasProblem(problems, "sequences.Final.tier 'Huge' is not a combat.hitStopFrames tier")).toBe(true)
		expect(#problems).toBe(3)
	end)

	it("catches a sequence that flashes more than the window allows", function()
		local problems = runImpact(function(impact)
			-- Eight one-frame flips fit the Kill's 10 frames but cost 5 flashes.
			local steps = {}
			for index = 1, 8 do
				table.insert(steps, { look = if index % 2 == 1 then "Dark" else "Light", frames = 1 })
			end
			impact.sequences.Kill.steps = steps
		end)
		expect(problems).toEqual({
			"impact: sequences.Kill costs 5 flashes, more than flash.maxPerWindow allows (3)",
		})
	end)

	it("counts a strobe in any region, not just the field", function()
		local problems = runImpact(function(impact)
			-- Six frames of a dark field whose figures blink white and gone: the field never
			-- changes, the figures flash 4 times.
			local steps = {}
			for index = 1, 6 do
				table.insert(steps, { look = if index % 2 == 1 then "Dark" else "Black", frames = 1 })
			end
			impact.sequences.Kill.steps = steps
			-- Ink strokes blinking on white paper: the field and figures hold, the strokes flash 3.
			impact.sequences.Final.steps = {
				{ look = "Ink", frames = 1 },
				{ look = "Light", frames = 1 },
				{ look = "Ink", frames = 1 },
				{ look = "Light", frames = 1 },
			}
		end)
		expect(problems).toEqual({
			"impact: sequences.Kill costs 4 flashes, more than flash.maxPerWindow allows (3)",
		})
	end)

	it("holds the hard limit: never more than 3 flashes in a window of at least 1 second", function()
		local problems = runImpact(function(impact)
			impact.flash.maxPerWindow = 13
			impact.flash.windowSeconds = 0.5
			impact.flash.transitionDelta = 0.3
			local steps = {}
			for index = 1, 8 do
				table.insert(steps, { look = if index % 2 == 1 then "Dark" else "Light", frames = 1 })
			end
			impact.sequences.Kill.steps = steps
		end)
		expect(problems).toEqual({
			"impact: flash.maxPerWindow 13 must be a whole number from 1 to 3",
			"impact: flash.windowSeconds 0.5 must be at least 1",
			"impact: flash.transitionDelta 0.3 must be above 0 and at most 0.1 (a smaller change still counts)",
			-- A looser budget never lets a 5-flash sequence through: the cost check uses the limit.
			"impact: sequences.Kill costs 5 flashes, more than flash.maxPerWindow allows (3)",
		})
		expect(runImpact(function(impact)
			impact.flash.maxPerWindow = 4
		end)).toEqual({ "impact: flash.maxPerWindow 4 must be a whole number from 1 to 3" })
	end)

	it("keeps the dim soft: a low opacity, at least 2 frames in and at least as many out", function()
		local problems = runImpact(function(impact)
			impact.reduced.opacity = 0.9
			impact.reduced.fadeInFrames = 1
			impact.reduced.fadeOutFrames = 0
			impact.reduced.fadeOutEasing = "Bounce"
		end)
		expect(problems).toEqual({
			"impact: reduced.opacity 0.9 must be above 0 and at most 0.4 (a soft dim, not a flash)",
			"impact: reduced.fadeInFrames 1 must be at least 2 (never an instant change)",
			"impact: reduced.fadeOutFrames must be at least reduced.fadeInFrames (out over more)",
			"impact: reduced.fadeOutEasing 'Bounce' is not an easing",
		})
	end)

	it("charges the dim when its dip over the brightest scene is a flash", function()
		local problems = runImpact(function(impact)
			impact.reduced.flashCost = 0
		end)
		expect(problems).toEqual({
			"impact: reduced dips the TrailWhite scene by 0.53 relative luminance, a flash: its flashCost must be at least 1",
		})
		-- A dim too faint to be a flash may be free.
		expect(runImpact(function(impact)
			impact.reduced.flashCost = 0
			impact.reduced.opacity = 0.04
		end)).toEqual({})
		expect(runImpact(function(impact)
			impact.reduced.flashCost = 4
			impact.reduced.referenceScene = "Chalk"
		end)).toEqual({
			"impact: reduced.referenceScene 'Chalk' is not a palette token",
			"impact: reduced.flashCost 4 must be a whole number from 0 to 3",
		})
	end)

	it("caps Reduce flashing at a whole number of dims a window, costing less than the flash budget", function()
		-- ImpactFrames counts dims against it: a fraction or zero is a broken setting.
		expect(runImpact(function(impact)
			impact.reduced.maxPerWindow = 0
		end)).toEqual({ "impact: reduced.maxPerWindow 0 must be a whole number of at least 1" })
		expect(runImpact(function(impact)
			impact.reduced.maxPerWindow = 1.5
		end)).toEqual({ "impact: reduced.maxPerWindow 1.5 must be a whole number of at least 1" })
		expect(runImpact(function(impact)
			impact.reduced.maxPerWindow = nil
		end)).toEqual({ "impact: reduced.maxPerWindow nil must be a whole number of at least 1" })
		-- Three dims of cost 1 are the whole budget: the setting would flash as much as without it.
		expect(runImpact(function(impact)
			impact.reduced.maxPerWindow = 3
		end)).toEqual({
			"impact: reduced.maxPerWindow 3 dims cost 3 flashes, not fewer than flash.maxPerWindow (3): Reduce flashing must flash less",
		})
		-- Passing: two dims of cost 1 under a budget of 3, and free dims (too faint to be a flash).
		expect(runImpact(function(impact)
			impact.reduced.maxPerWindow = 2
		end)).toEqual({})
		expect(runImpact(function(impact)
			impact.reduced.flashCost = 0
			impact.reduced.opacity = 0.04
			impact.reduced.maxPerWindow = 5
		end)).toEqual({})
	end)

	it("keeps the overlay above the HUD and every quality tier covered, each drawing the figures", function()
		local problems = runImpact(function(impact)
			impact.overlay.displayOrder = 5
			impact.quality.Low = nil
			impact.quality.Medium.silhouettes = false
			impact.quality.High.maxPartsPerRig = 0
		end)
		expect(problems).toEqual({
			"impact: overlay.displayOrder must sit above the HUD's (ui.hud.displayOrder)",
			"impact: quality.High.maxPartsPerRig must be a whole number of at least 1",
			"impact: quality.Low needs silhouettes and strokes booleans",
			"impact: quality.Medium must draw the silhouettes: an impact frame without its figures is a bare blink",
		})
	end)

	it(
		"lets each picture wait as long as its own hit-stop: no global staleFrames, no hit-stop under 2 frames",
		function()
			-- The single limit is gone (D-122): a leftover key would read as if it still bound something.
			expect(runImpact(function(impact)
				impact.overlay.staleFrames = 3
			end)).toEqual({
				"impact: overlay.staleFrames is gone (D-122): each picture waits for its first drawn frame as long as its own hit-stop (a dim: its own length)",
			})
			-- A sequence on a hit-stop shorter than 2 frames would drop every 30 fps first frame.
			expect(runImpact(function(impact)
				impact.sequences.Parry.tier = "Blink"
			end, function(combat)
				combat.hitStopFrames.Blink = 1
			end)).toEqual({
				"impact: sequences.Parry rides a 1-frame Blink hit-stop: under 2 frames, a 30 fps first frame (2 frames after the hit) would never draw it",
			})
		end
	)
end)

describe("accents validator: the swing memory and the crescent's tilt", function()
	local function deepCopy(value: any): any
		if typeof(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, element in value do
			copy[key] = deepCopy(element)
		end
		return copy
	end

	-- Runs the accents validator on a copy of the real accents.luau that `mutate` breaks.
	local function runAccents(mutate: (accents: any) -> ()): { string }
		local accents = deepCopy(Harness.load("src/shared/data/accents"))
		mutate(accents)
		local validate = loadTool("tools/validators/accents")
		return validate({
			load = function(path: string)
				if path == "src/shared/data/accents" then
					return accents
				end
				return Harness.load(path)
			end,
			listFiles = Harness.listFiles,
			readFile = Harness.readFile,
			repoRoot = root,
		})
	end

	it("is clean on the real table", function()
		expect(runAccents(function() end)).toEqual({})
		expect(loadTool("tools/validators/accents")(realContext)).toEqual({})
	end)

	it("keeps the swing memory past the sample ring and under a second", function()
		local samples = Harness.load("src/shared/data/accents").swing.samples
		local function memoryProblem(value: any): string
			return ("accents: swing.memorySeconds %s must be longer than the %d-sample ring and below 1 second"):format(
				tostring(value),
				samples
			)
		end
		for _, value in { 1, 1.5, samples / 60 } do
			expect(runAccents(function(accents)
				accents.swing.memorySeconds = value
				accents.swing.snapFrames = 1
			end)).toEqual({ memoryProblem(value) })
		end
		-- No memory at all also leaves no room for the snap.
		for _, value in { 0, -0.2 } do
			expect(runAccents(function(accents)
				accents.swing.memorySeconds = value
				accents.swing.snapFrames = 1
			end)).toEqual({
				memoryProblem(value),
				"accents: swing.snapFrames 1 must be a whole number of frames, at least 1, read well inside swing.memorySeconds",
			})
		end
		expect(runAccents(function(accents)
			accents.swing.memorySeconds = nil
		end)).toEqual({
			memoryProblem(nil),
			"accents: swing.snapFrames 2 must be a whole number of frames, at least 1, read well inside swing.memorySeconds",
		})
		-- Passing: a shorter memory that still outlasts the ring and the snap.
		expect(runAccents(function(accents)
			accents.swing.memorySeconds = 0.2
		end)).toEqual({})
	end)

	it("reads the snap over whole frames, at least one, well inside the memory", function()
		local function snapProblem(value: any): string
			return ("accents: swing.snapFrames %s must be a whole number of frames, at least 1, read well inside swing.memorySeconds"):format(
				tostring(value)
			)
		end
		for _, value in { 0, 1.5, 24, 30 } do
			expect(runAccents(function(accents)
				accents.swing.snapFrames = value
			end)).toEqual({ snapProblem(value) })
		end
		-- Passing: one frame, and 23 frames (0.383 s) inside the 0.4 s memory.
		for _, value in { 1, 23 } do
			expect(runAccents(function(accents)
				accents.swing.snapFrames = value
			end)).toEqual({})
		end
	end)

	it("bounds the crescent's turn toward the camera", function()
		expect(runAccents(function(accents)
			accents.slashArc.tilt.maxDegrees = 0
		end)).toEqual({ "accents: slashArc.tilt.maxDegrees must be above 0" })
		expect(runAccents(function(accents)
			accents.slashArc.tilt.faceDegrees = 90
			accents.slashArc.tilt.maxDegrees = -5
		end)).toEqual({
			"accents: slashArc.tilt.maxDegrees must be above 0",
			"accents: slashArc.tilt.faceDegrees must be above 0 and below 90",
		})
		-- A 45-degree turn brings an edge-on crescent 45 off the camera, nearer than faceDegrees 50.
		expect(runAccents(function(accents)
			accents.slashArc.tilt.maxDegrees = 45
		end)).toEqual({
			"accents: slashArc.tilt.maxDegrees 45 turns an edge-on crescent nearer the camera than faceDegrees 50",
		})
		for _, value in { 0, 1, nil :: any } do
			expect(runAccents(function(accents)
				accents.slashArc.tilt.minPlaneSine = value
			end)).toEqual({
				"accents: slashArc.tilt.minPlaneSine must be above 0 and below 1 (the sine of a swing's least angle to its radius)",
			})
		end
		expect(runAccents(function(accents)
			accents.slashArc.tilt = nil
		end)).toEqual({ "accents: slashArc.tilt must be {faceDegrees, maxDegrees, minPlaneSine}" })
		-- Passing: a full 40-degree turn from edge-on stops exactly at faceDegrees 50.
		expect(runAccents(function(accents)
			accents.slashArc.tilt.maxDegrees = 40
		end)).toEqual({})
	end)

	it("snaps the crescent's wipe to at least 4 whole steps a frame of the longest wipe", function()
		local longest = 0
		for _, size in Harness.load("src/shared/data/accents").slashArc.sizes do
			longest = math.max(longest, size.wipeFrames)
		end
		local function stepsProblem(value: any): string
			return ("accents: slashArc.wipeSteps %s must be a whole number, at least 4 per frame of the longest wipe (%d)"):format(
				tostring(value),
				4 * longest
			)
		end
		for _, value in { 4 * longest - 1, 0, 32.5, nil :: any } do
			expect(runAccents(function(accents)
				accents.slashArc.wipeSteps = value
			end)).toEqual({ stepsProblem(value) })
		end
		-- A longer wipe needs more steps.
		expect(runAccents(function(accents)
			accents.slashArc.wipeSteps = 4 * longest
			accents.slashArc.sizes.Large.wipeFrames = longest + 1
		end)).toEqual({
			("accents: slashArc.wipeSteps %d must be a whole number, at least 4 per frame of the longest wipe (%d)"):format(
				4 * longest,
				4 * (longest + 1)
			),
		})
		-- Passing: exactly 4 a frame.
		expect(runAccents(function(accents)
			accents.slashArc.wipeSteps = 4 * longest
		end)).toEqual({})
	end)

	it("samples an idle blade as far as every moment's accents show", function()
		local moments = Harness.load("src/shared/data/moments")
		expect(runAccents(function(accents)
			accents.swing.sampleDistance = 0
		end)).toEqual({ "accents: swing.sampleDistance must be above 0" })
		expect(runAccents(function(accents)
			accents.swing.sampleDistance = nil
		end)).toEqual({ "accents: swing.sampleDistance must be above 0" })
		-- Short of a row's range (the Kill row reads across the fight) but past accentRange.
		local farthest = moments.accentRange
		for _, row in moments.rows do
			farthest = math.max(farthest, row.range or 0)
		end
		local problems = runAccents(function(accents)
			accents.swing.sampleDistance = farthest - 1
		end)
		expect(#problems > 0).toBe(true)
		for _, problem in problems do
			expect(
				problem:find(
					("^accents: swing%%.sampleDistance %d must reach moments%%.rows%%.%%w+%%.range %d$"):format(
						farthest - 1,
						farthest
					)
				) ~= nil
			).toBe(true)
		end
		-- Short of accentRange too.
		local short = runAccents(function(accents)
			accents.swing.sampleDistance = moments.accentRange - 1
		end)
		expect(
			table.find(
				short,
				("accents: swing.sampleDistance %d must reach moments.accentRange %d"):format(
					moments.accentRange - 1,
					moments.accentRange
				)
			) ~= nil
		).toBe(true)
		-- Passing: exactly the farthest range.
		expect(runAccents(function(accents)
			accents.swing.sampleDistance = farthest
		end)).toEqual({})
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Combat validator: the aim snap rule (D-112)
-- ------------------------------------------------------------------------------------------

describe("combat validator: the aim snap fits the server's facing acceptance", function()
	-- The real combat table with `aim` fields and top-level fields replaced.
	local function runCombat(aimFields: { [string]: any }, fields: { [string]: any }?): { string }
		local real = Harness.load("src/shared/data/combat")
		local copy = table.clone(real)
		copy.aim = table.clone(real.aim)
		for key, value in aimFields do
			copy.aim[key] = value
		end
		for key, value in fields or {} do
			copy[key] = value
		end
		local context = table.clone(realContext)
		context.load = function(path: string): any
			if path == "src/shared/data/combat" then
				return copy
			end
			return Harness.load(path)
		end
		return loadTool("tools/validators/combat")(context)
	end

	it("passes the real table: 40 + 9 is inside 49.46 degrees", function()
		expect(runCombat({})).toEqual({})
	end)

	it("a snap plus margin past deg(acos(1 - facingTolerance)) is a problem", function()
		local problems = runCombat({ snapDegrees = 45, replicationMarginDegrees = 5 })
		expect(#problems).toBe(1)
		expect(hasProblem(problems, "aim.snapDegrees 45 + aim.replicationMarginDegrees 5")).toBe(true)
		expect(hasProblem(problems, "deg(acos(1 - facingTolerance)) = 49.46")).toBe(true)
		-- The same sum is fine once the server accepts a wider facing; a tighter one rejects 40 + 9.
		expect(runCombat({ snapDegrees = 45, replicationMarginDegrees = 5 }, { facingTolerance = 0.4 })).toEqual({})
		expect(hasProblem(runCombat({}, { facingTolerance = 0.3 }), "aim.snapDegrees 40")).toBe(true)
	end)
end)

describe("combat validator: the snap's visible turn (item 102)", function()
	local function runCombat(aimFields: { [string]: any }): { string }
		local real = Harness.load("src/shared/data/combat")
		local copy = table.clone(real)
		copy.aim = table.clone(real.aim)
		for key, value in aimFields do
			copy.aim[key] = value
		end
		local context = table.clone(realContext)
		context.load = function(path: string): any
			if path == "src/shared/data/combat" then
				return copy
			end
			return Harness.load(path)
		end
		return loadTool("tools/validators/combat")(context)
	end

	it("passes the real whip: a few frames, done before the first swing's blade can land", function()
		local real = Harness.load("src/shared/data/combat")
		expect(typeof(real.aim.snapTurnSeconds)).toBe("number")
		expect(typeof(real.aim.snapTurnEasing)).toBe("string")
		expect(runCombat({})).toEqual({})
	end)

	it("wants a positive number of seconds", function()
		for _, bad in { 0, -0.05, 0 / 0, math.huge, "0.08" } :: { any } do
			local problems = runCombat({ snapTurnSeconds = bad })
			expect(hasProblem(problems, "aim.snapTurnSeconds must be a positive number")).toBe(true)
		end
	end)

	it("a turn still going when a player swing's first hit window opens is a problem", function()
		-- The basic swings open at 0.1 s; the Arts at 0.333 and 0.35, 0.18 s past their activation hold,
		-- where the release (and its snap) comes.
		local slow = runCombat({ snapTurnSeconds = 0.12 })
		expect(#slow).toBe(1)
		expect(hasProblem(slow, "aim.snapTurnSeconds 0.12 is still turning")).toBe(true)
		expect(hasProblem(slow, "Basic1")).toBe(true)
		expect(hasProblem(slow, "0.100 s")).toBe(true)
		local slower = runCombat({ snapTurnSeconds = 0.19 })
		expect(#slower).toBe(1)
		expect(hasProblem(slower, "aim.snapTurnSeconds 0.19 is still turning")).toBe(true)
		-- At the earliest window itself the body faces the target as the blade comes: fine.
		expect(runCombat({ snapTurnSeconds = 0.1 })).toEqual({})
	end)

	it("wants an easing that exists, runs 0 to 1 without overshooting, and spreads the turn", function()
		expect(hasProblem(runCombat({ snapTurnEasing = "Wobble" }), "aim.snapTurnEasing 'Wobble' is not an easing")).toBe(
			true
		)
		expect(hasProblem(runCombat({ snapTurnEasing = 5 }), "aim.snapTurnEasing")).toBe(true)
		-- An overshoot swings the body past the target and back: a wobble, not a whip.
		for _, name in { "BackOut", "Spring" } do
			local problems = runCombat({ snapTurnEasing = name })
			expect(hasProblem(problems, ("aim.snapTurnEasing '%s' leaves 0..1"):format(name))).toBe(true)
		end
		-- Hold shows the whole turn on its last frame: the pop item 102 measured.
		local hold = runCombat({ snapTurnEasing = "Hold" })
		expect(#hold).toBe(1)
		expect(
			hasProblem(
				hold,
				"aim.snapTurnEasing 'Hold' over aim.snapTurnSeconds 0.08 shows 100% of the turn in one frame"
			)
		).toBe(true)
		-- ExpoOut over 0.08 s puts three quarters of the turn in the first frame.
		expect(hasProblem(runCombat({ snapTurnEasing = "ExpoOut" }), "shows 76% of the turn in one frame")).toBe(true)
		-- A turn shorter than a frame is the pop again, whatever the curve.
		expect(hasProblem(runCombat({ snapTurnSeconds = 0.01 }), "shows 100% of the turn in one frame")).toBe(true)
		for _, name in { "QuadOut", "Linear", "SineInOut", "QuadIn" } do
			expect(runCombat({ snapTurnEasing = name })).toEqual({})
		end
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Content: no placeholder id reaches an engine property; Clouds sits under Workspace.Terrain
-- ------------------------------------------------------------------------------------------

describe("content validator", function()
	local Lighting = Harness.load("src/shared/data/lighting")
	local World = Harness.load("src/shared/data/world")
	local Fx = Harness.load("src/shared/data/fx")

	-- A repository of synthetic files: `files` stands in for src/ and places/ (default.project.json
	-- and src/shared/data are the real ones unless `files` replaces them); `loads` swaps data tables.
	local function runContent(files: { [string]: string }, loads: { [string]: any }?): { string }
		local validate = loadTool("tools/validators/content")
		return validate({
			load = function(path: string): any
				if loads ~= nil and loads[path] ~= nil then
					return loads[path]
				end
				return Harness.load(path)
			end,
			listFiles = function(directory: string, pattern: string?): { string }
				if directory == "src/shared/data" then
					return Harness.listFiles(directory, pattern)
				end
				local list = {}
				for path in files do
					if path:sub(1, #directory + 1) == directory .. "/" and (pattern == nil or path:match(pattern)) then
						table.insert(list, path)
					end
				end
				table.sort(list)
				return list
			end,
			readFile = function(path: string): string
				return files[path] or Harness.readFile(path)
			end,
			repoRoot = root,
		})
	end

	local function source(lines: { string }): { [string]: string }
		return { ["src/client/audio/Fake.luau"] = table.concat(lines, "\n") }
	end

	local function project(lighting: string, workspace: string?): { [string]: string }
		return {
			["places/Fake.project.json"] = ([[{ "name": "Fake", "tree": { "$className": "DataModel",
				"Lighting": { %s }, "Workspace": { %s } } }]]):format(lighting, workspace or ""),
		}
	end

	it("flags a placeholder id written anywhere, and lets a comparison through", function()
		local problems = runContent(source({
			"sound.SoundId = Sfx.placeholderId",
			"local stem = { id = Sfx.placeholderId }",
			'if id == Sfx.placeholderId or id ~= "" then end',
			"local placeholder = Sfx.placeholderId == id",
			"-- sound.SoundId = Sfx.placeholderId (a comment)",
		}))
		expect(hasProblem(problems, "Fake.luau:1: a placeholder id is only ever compared")).toBe(true)
		expect(hasProblem(problems, "Fake.luau:1: SoundId gets a value nothing checked")).toBe(true)
		expect(hasProblem(problems, "Fake.luau:2: a placeholder id is only ever compared")).toBe(true)
		expect(#problems).toBe(3)
	end)

	it("keeps asset id literals in src/shared/data", function()
		local problems = runContent({
			["src/client/fx/Fake.luau"] = 'local ID = "rbxassetid://9119749145"',
			["src/shared/data/Fake.luau"] = 'local ID = "rbxassetid://9119749145"',
		})
		expect(problems).toEqual({ "src/client/fx/Fake.luau:1: an asset id literal belongs in src/shared/data" })
		expect(
			hasProblem(
				runContent(source({ 'local zero = "rbxassetid://0"' })),
				"a placeholder id is only ever compared"
			)
		).toBe(true)
	end)

	it("wants an Assets.isReady check within three lines before Assets.url", function()
		expect(runContent(source({
			"if Assets.isReady(name) then",
			"\tdecal.Texture = Assets.url(name)",
			"end",
		}))).toEqual({})
		local far = runContent(source({
			"if Assets.isReady(name) then",
			"\tlocal a = 1",
			"\tlocal b = 2",
			"\tlocal c = 3",
			"\tdecal.Texture = Assets.url(name)",
			"end",
		}))
		expect(hasProblem(far, "Fake.luau:5: Assets.url without an Assets.isReady check")).toBe(true)
	end)

	it("wants every content write to be empty or checked against placeholders", function()
		local problems = runContent(source({
			"sound.SoundId = entry.id",
			'sound.SoundId = if Sfx.isReal(entry) then entry.id else ""',
			'beam.Texture = ""',
			"if not isPlaceholder(id) then",
			"\tstem.SoundId = id",
			"end",
			"if sound.SoundId == id then end",
			"(clone :: any).TextureID = mesh",
			'part.MeshId = if entry.placeholder then "" else entry.mesh',
		}))
		expect(problems).toEqual({
			'src/client/audio/Fake.luau:1: SoundId gets a value nothing checked against placeholders (write "" for a placeholder)',
			'src/client/audio/Fake.luau:8: TextureID gets a value nothing checked against placeholders (write "" for a placeholder)',
		})
	end)

	it("puts a Clouds only under Workspace.Terrain, with lighting.luau's cover and density", function()
		local cover, density = Lighting.clouds.cover, Lighting.clouds.density
		local clouds = ('"Clouds": { "$className": "Clouds", "$properties": { "Cover": %s, "Density": %s } }'):format(
			tostring(cover),
			tostring(density)
		)
		expect(runContent(project("", '"Terrain": { "$className": "Terrain", ' .. clouds .. " }"))).toEqual({})
		expect(runContent(project(clouds))).toEqual({
			"places/Fake.project.json: game.Lighting.Clouds (Clouds) must be a direct child of Workspace.Terrain",
		})
		local thin = ('"Clouds": { "$className": "Clouds", "$properties": { "Cover": 0.1, "Density": %s } }'):format(
			tostring(density)
		)
		expect(runContent(project("", '"Terrain": { "$className": "Terrain", ' .. thin .. " }"))).toEqual({
			("places/Fake.project.json: game.Workspace.Terrain.Clouds.Cover is 0.1, lighting.luau clouds.cover is %s"):format(
				tostring(cover)
			),
		})
	end)

	it("keeps the sky and the post effects directly under Lighting, and asset ids out of project files", function()
		local problems = runContent(
			project(
				'"Sky": { "$className": "Sky", "$properties": { "SkyboxUp": "rbxassetid://1" } }',
				'"Bloom": { "$className": "BloomEffect" }'
			)
		)
		expect(problems).toEqual({
			"places/Fake.project.json: game.Lighting.Sky sets SkyboxUp; asset ids live in src/shared/data",
			"places/Fake.project.json: game.Workspace.Bloom (BloomEffect) must be a direct child of Lighting",
		})
	end)

	it("wants every *TextureAsset field to name an assets.luau Texture", function()
		local world = table.clone(World)
		world.clouds = table.clone(World.clouds)
		world.clouds.textureAsset = "TrialistSword"
		local fx = table.clone(Fx)
		fx.telegraph = table.clone(Fx.telegraph)
		fx.telegraph.decal = table.clone(Fx.telegraph.decal)
		fx.telegraph.decal.textureAssets = table.clone(Fx.telegraph.decal.textureAssets)
		fx.telegraph.decal.textureAssets.Line = "NoSuchAsset"
		local problems = runContent({}, { ["src/shared/data/world"] = world, ["src/shared/data/fx"] = fx })
		expect(problems).toEqual({
			"fx.telegraph.decal.textureAssets.Line: 'NoSuchAsset' is not in assets.luau",
			"world.clouds.textureAsset: 'TrialistSword' is a Mesh; this field feeds a Texture property",
		})
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Choreo's render-stall jump (D-132): data/choreo.luau stall.jumpSeconds
-- ------------------------------------------------------------------------------------------

describe("choreo validator: the render-stall jump", function()
	-- The real choreo (and camera) tables with `stall` and quality rows replaced.
	local function runChoreo(stall: any, quality: { [string]: any }?, cameraStall: any?): { string }
		local real = Harness.load("src/shared/data/choreo")
		local copy = table.clone(real)
		copy.stall = stall
		if quality ~= nil then
			copy.quality = table.clone(real.quality)
			for tier, row in quality do
				copy.quality[tier] = row
			end
		end
		local camera = Harness.load("src/shared/data/camera")
		if cameraStall ~= nil then
			camera = table.clone(camera)
			camera.stall = cameraStall
		end
		local context = table.clone(realContext)
		context.load = function(path: string): any
			if path == "src/shared/data/choreo" then
				return copy
			elseif path == "src/shared/data/camera" then
				return camera
			end
			return Harness.load(path)
		end
		return loadTool("tools/validators/choreo")(context)
	end

	it("passes the real table", function()
		local real = Harness.load("src/shared/data/choreo")
		expect(typeof(real.stall)).toBe("table")
		expect(runChoreo(real.stall)).toEqual({})
	end)

	it("wants a stall block with a positive, finite jumpSeconds", function()
		expect(hasProblem(runChoreo(nil), "stall is missing")).toBe(true)
		for _, bad in { 0, -0.5, 0 / 0, math.huge, "0.5" } :: { any } do
			local problems = runChoreo({ jumpSeconds = bad })
			expect(hasProblem(problems, "stall.jumpSeconds must be a positive number")).toBe(true)
		end
	end)

	it("keeps a far rig's Heartbeat step (and a hitch as long) under the jump", function()
		-- A far rig steps every 1/farHz on Heartbeat, which never stalls with the display: only a
		-- Heartbeat hitch of a whole step on top may be a jump. Low's 4 Hz wants 0.5 s.
		local problems = runChoreo(
			{ jumpSeconds = 0.4 },
			{ Low = { nearRadius = 30, maxFullRateRigs = 6, distantHz = 12, farHz = 4 } }
		)
		expect(hasProblem(problems, "stall.jumpSeconds 0.40 is under 2 / quality.Low.farHz (0.50)")).toBe(true)
		expect(
			runChoreo(
				{ jumpSeconds = 0.4 },
				{ Low = { nearRadius = 30, maxFullRateRigs = 6, distantHz = 12, farHz = 5 } }
			)
		).toEqual({})
		-- A distant rate slower than the far one is held to the same rule.
		expect(
			hasProblem(
				runChoreo(
					{ jumpSeconds = 0.5 },
					{ Medium = { nearRadius = 50, maxFullRateRigs = 12, distantHz = 3, farHz = 6 } }
				),
				"quality.Medium.distantHz"
			)
		).toBe(true)
	end)

	it("is a stall wherever the camera snaps one: at most camera.stall.settleSeconds", function()
		local problems = runChoreo({ jumpSeconds = 2.5 })
		expect(hasProblem(problems, "stall.jumpSeconds 2.50 is over camera.stall.settleSeconds (2.00)")).toBe(true)
		expect(runChoreo({ jumpSeconds = 2.5 }, nil, { maxStepSeconds = 1 / 30, settleSeconds = 3 })).toEqual({})
	end)
end)

-- ------------------------------------------------------------------------------------------
-- AI: the rush's jam lag, the hit-stop pause cap and the fighter collision groups (D-167..D-169, D-190)
-- ------------------------------------------------------------------------------------------

describe("ai validator: rush jam lag, hit-stop pause cap, collision groups", function()
	-- The real ai table with Charger fields, hitStop and collision replaced.
	local function runAi(change: (copy: any) -> ()): { string }
		local real = Harness.load("src/shared/data/ai")
		local copy = table.clone(real)
		copy.archetypes = table.clone(real.archetypes)
		copy.archetypes.Charger = table.clone(real.archetypes.Charger)
		copy.hitStop = table.clone(real.hitStop)
		copy.collision = table.clone(real.collision)
		copy.collision.apart = table.clone(real.collision.apart)
		change(copy)
		local context = table.clone(realContext)
		context.load = function(path: string): any
			if path == "src/shared/data/ai" then
				return copy
			end
			return Harness.load(path)
		end
		return loadTool("tools/validators/ai")(context)
	end

	it("passes the real table", function()
		expect(runAi(function() end)).toEqual({})
	end)

	it("a rush's dead stop leads by at most a tick, and a walk's snout slack stays a hair (D-278, D-279)", function()
		local function withMovement(field: string, value: any): { string }
			return runAi(function(copy)
				copy.movement = table.clone(copy.movement)
				copy.movement[field] = value
			end)
		end
		expect(hasProblem(withMovement("haltLeadSeconds", 0), "movement.haltLeadSeconds must be positive")).toBe(true)
		expect(hasProblem(withMovement("haltLeadSeconds", nil), "movement.haltLeadSeconds must be a number")).toBe(true)
		expect(
			hasProblem(
				withMovement("haltLeadSeconds", 0.06),
				"movement.haltLeadSeconds 0.06 must be at most one AI tick (0.05 s)"
			)
		).toBe(true)
		expect(hasProblem(withMovement("snoutSlackStuds", -0.1), "movement.snoutSlackStuds must be zero or positive")).toBe(
			true
		)
		expect(
			hasProblem(
				withMovement("snoutSlackStuds", 0.15),
				"movement.snoutSlackStuds 0.15 must be below rushWorld.clipMarginStuds (0.15)"
			)
		).toBe(true)
		expect(withMovement("snoutSlackStuds", 0)).toEqual({})
	end)

	it("a blocked step is told sooner than the jam lag, by fractions that tell running from blocked (D-280)", function()
		local function withCharger(field: string, value: any): { string }
			return runAi(function(copy)
				copy.archetypes.Charger[field] = value
			end)
		end
		expect(hasProblem(withCharger("blockedSeconds", 0), "archetypes.Charger.blockedSeconds must be positive")).toBe(
			true
		)
		expect(
			hasProblem(
				withCharger("blockedSeconds", 0.2),
				"archetypes.Charger.blockedSeconds 0.2 must be shorter than jamLagStuds / chargeSpeed"
			)
		).toBe(true)
		expect(
			hasProblem(
				withCharger("blockedFraction", 0.5),
				"archetypes.Charger.blockedFraction must be below runningFraction"
			)
		).toBe(true)
		expect(hasProblem(withCharger("runningFraction", 1.2), "archetypes.Charger.runningFraction must be at most 1")).toBe(
			true
		)
		expect(hasProblem(withCharger("runningFraction", nil), "archetypes.Charger.runningFraction must be a number")).toBe(
			true
		)
	end)

	it("a Charger needs a positive jamLagStuds", function()
		expect(hasProblem(
			runAi(function(copy)
				copy.archetypes.Charger.jamLagStuds = 0
			end),
			"archetypes.Charger.jamLagStuds must be positive"
		)).toBe(true)
	end)

	it("the hit-stop pause cap holds at least one Final hit-stop", function()
		local problems = runAi(function(copy)
			copy.hitStop.maxPausePerAttack = 0.05
		end)
		expect(hasProblem(problems, "hitStop.maxPausePerAttack 0.05 is shorter than one Final hit-stop")).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.hitStop.maxPausePerAttack = -1
			end),
			"hitStop.maxPausePerAttack must be positive"
		)).toBe(true)
	end)

	it("the collision groups are four distinct names, and a rush passes players", function()
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.rushing = copy.collision.enemies
			end),
			"collision groups must be four distinct names"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.blockers = copy.collision.players
			end),
			"collision groups must be four distinct names"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.players = "Default"
			end),
			"collision.players must not be the engine's Default group"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.apart = { { copy.collision.rushing, copy.collision.enemies } }
			end),
			"collision.apart must let the rushing group pass the players group"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				table.insert(copy.collision.apart, { copy.collision.rushing, "Walls" })
			end),
			"collision.apart names Walls, which is neither a fighter group nor Default"
		)).toBe(true)
	end)

	-- Drops every apart pair matching `a` and `b` (either order).
	local function without(copy: any, a: string, b: string)
		local kept = {}
		for _, pair in copy.collision.apart do
			if not ((pair[1] == a and pair[2] == b) or (pair[1] == b and pair[2] == a)) then
				table.insert(kept, pair)
			end
		end
		copy.collision.apart = kept
	end

	it(
		"an enemy's blocker meets players, enemies and other blockers, never the world or a rush (D-198, D-281)",
		function()
			local groups = Harness.load("src/shared/data/ai").collision
			for _, other in { "Default", groups.rushing } do
				expect(hasProblem(
					runAi(function(copy)
						without(copy, groups.blockers, other)
					end),
					("collision.apart must keep the blockers group from %s"):format(other)
				)).toBe(true)
			end
			-- Enemies never stand inside each other: a solid enemy's whole footprint meets another's.
			for _, key in { "enemies", "blockers" } do
				expect(hasProblem(
					runAi(function(copy)
						table.insert(copy.collision.apart, { groups.blockers, groups[key] })
					end),
					("collision.apart must not keep the blockers group from the %s group"):format(key)
				)).toBe(true)
			end
			expect(hasProblem(
				runAi(function(copy)
					table.insert(copy.collision.apart, { groups.players, groups.blockers })
				end),
				"collision.apart must not keep the blockers group from the players group"
			)).toBe(true)
			expect(hasProblem(
				runAi(function(copy)
					without(copy, groups.enemies, groups.players)
				end),
				"collision.apart must keep the enemies group from the players group"
			)).toBe(true)
		end
	)

	it("the blocker reaches above every enemy rig's root (D-198)", function()
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.blockerHeight = 4
			end),
			"collision.blockerHeight 4 must reach above rig Boar's root top (4)"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.blockerHeight = 4.1
			end),
			"must reach above rig Kobold's root top (4.2)"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.blockerHeight = nil
			end),
			"collision.blockerHeight must be a number"
		)).toBe(true)
	end)

	it("every slope a rushing root climbs is ground to the world casts, and a wall never is", function()
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.groundSlopeDegrees = 30
			end),
			"collision.groundSlopeDegrees 30 must be at least rig Boar's climb (32.6)"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.groundSlopeDegrees = 90
			end),
			"collision.groundSlopeDegrees must be below 90"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.groundSlopeDegrees = nil
			end),
			"collision.groundSlopeDegrees must be a number"
		)).toBe(true)
	end)

	it("a rush's line keeps up with its body by less than the jam lag (D-195)", function()
		expect(hasProblem(
			runAi(function(copy)
				copy.archetypes.Charger.keepUpStuds = copy.archetypes.Charger.jamLagStuds
			end),
			"archetypes.Charger.keepUpStuds must be below jamLagStuds"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.archetypes.Charger.keepUpStuds = 0
			end),
			"archetypes.Charger.keepUpStuds must be positive"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.archetypes.Charger.keepUpStuds = nil
			end),
			"archetypes.Charger.keepUpStuds must be a number"
		)).toBe(true)
	end)

	it("a stopped rush waits longer than the clients' draw lag and less than its recovery (D-190)", function()
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.rejoinClearSeconds = copy.collision.clientDrawLagSeconds
			end),
			"must exceed clientDrawLagSeconds"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.rejoinClearSeconds = 5
			end),
			"FrenzyBoar.Charge: recovery 1.2 must exceed collision.rejoinClearSeconds 5"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.rejoinClearSeconds = nil
			end),
			"collision.rejoinClearSeconds must be a number"
		)).toBe(true)
		expect(hasProblem(
			runAi(function(copy)
				copy.collision.clientDrawLagSeconds = 0
			end),
			"collision.clientDrawLagSeconds must be positive"
		)).toBe(true)
	end)
end)

describe("playground validator: spawn spacing (D-170)", function()
	-- The real playground table with spawnSpacing (and the scatter radius) replaced.
	local function runPlayground(change: (copy: any) -> ()): { string }
		local real = Harness.load("src/shared/data/playground")
		local copy = table.clone(real)
		copy.spawnSpacing = table.clone(real.spawnSpacing)
		change(copy)
		local context = table.clone(realContext)
		context.load = function(path: string): any
			if path == "src/shared/data/playground" then
				return copy
			end
			return Harness.load(path)
		end
		return loadTool("tools/validators/playground")(context)
	end

	it("passes the real table", function()
		expect(runPlayground(function() end)).toEqual({})
	end)

	it("spacing numbers are positive, and tries and widenings are whole counts", function()
		expect(hasProblem(
			runPlayground(function(copy)
				copy.spawnSpacing.minStuds = 0
			end),
			"playground.spawnSpacing.minStuds must be a positive number"
		)).toBe(true)
		expect(hasProblem(
			runPlayground(function(copy)
				copy.spawnSpacing.tries = 2.5
			end),
			"playground.spawnSpacing.tries must be a whole number of at least 1"
		)).toBe(true)
		expect(hasProblem(
			runPlayground(function(copy)
				copy.spawnSpacing.widenings = -1
			end),
			"playground.spawnSpacing.widenings must be a whole number of at least 0"
		)).toBe(true)
		expect(hasProblem(
			runPlayground(function(copy)
				copy.spawnSpacing = nil
			end),
			"playground.spawnSpacing is missing"
		)).toBe(true)
	end)

	it("the widest disc leaves room for the largest pack at the spacing", function()
		local problems = runPlayground(function(copy)
			copy.spawnSpacing.widenings = 0
		end)
		expect(hasProblem(problems, "playground.spawnSpacing: the widest disc (6 studs) leaves no room")).toBe(true)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The camera lock's close-fight keys, the dev capture's shots and the shatter balance: the rules
-- tests/client/CameraFraming, tests/data/devCapture and tests/data/sfx check, in the validators
-- ------------------------------------------------------------------------------------------

describe("camera, dev capture and sfx shatter rules", function()
	local function deepCopy(value: any): any
		if typeof(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, element in value do
			copy[key] = deepCopy(element)
		end
		return setmetatable(copy, getmetatable(value))
	end

	-- Runs a validator with one data module replaced by a mutated copy of the real one: a deep copy,
	-- or with `only`, a shallow one with just that row deep copied (a validator that checks a row
	-- by identity against another module's).
	local function runWith(validator: string, dataPath: string, mutate: ((any) -> ())?, only: string?): { string }
		local real = Harness.load(dataPath)
		local copy
		if only ~= nil then
			copy = table.clone(real)
			copy[only] = deepCopy(real[only])
		else
			copy = deepCopy(real)
		end
		if mutate ~= nil then
			mutate(copy)
		end
		return loadTool("tools/validators/" .. validator)({
			load = function(path: string): any
				if path == dataPath then
					return copy
				end
				return Harness.load(path)
			end,
			listFiles = Harness.listFiles,
			readFile = Harness.readFile,
			repoRoot = root,
		})
	end

	local function camera(mutate: ((any) -> ())?): { string }
		return runWith("camera", "src/shared/data/camera", mutate, "lock")
	end
	local function dev(mutate: ((any) -> ())?): { string }
		return runWith("dev", "src/shared/data/dev", mutate)
	end
	local function sfx(mutate: ((any) -> ())?): { string }
		return runWith("sfx", "src/shared/data/sfx", mutate)
	end
	local function contact(dataPath: string, mutate: ((any) -> ())?): { string }
		return runWith("contact", dataPath, mutate)
	end
	local function telegraph(dataPath: string, mutate: ((any) -> ())?): { string }
		return runWith("telegraph", dataPath, mutate)
	end

	it("each is clean on a copy of the real table", function()
		expect(camera()).toEqual({})
		expect(dev()).toEqual({})
		expect(sfx()).toEqual({})
		expect(contact("src/shared/data/combat")).toEqual({})
		expect(telegraph("src/shared/data/fx")).toEqual({})
	end)

	it("camera: the close shot opens from closeGap to openGap, both positive", function()
		expect(hasProblem(
			camera(function(copy)
				copy.lock.closeGap = copy.lock.openGap
			end),
			"lock.closeGap"
		)).toBe(true)
		expect(hasProblem(
			camera(function(copy)
				copy.lock.closeGap = 0
			end),
			"lock.closeGap"
		)).toBe(true)
	end)

	it("camera: the close swing is inside a quarter turn, the height and the turn cap positive", function()
		for _, bad in { 0, 95 } do
			expect(hasProblem(
				camera(function(copy)
					copy.lock.closeSwingDegrees = bad
				end),
				"lock.closeSwingDegrees"
			)).toBe(true)
		end
		expect(hasProblem(
			camera(function(copy)
				copy.lock.closeHeight = 0
			end),
			"lock.closeHeight"
		)).toBe(true)
		expect(hasProblem(
			camera(function(copy)
				copy.lock.maxTurnDegreesPerSecond = 0
			end),
			"lock.maxTurnDegreesPerSecond"
		)).toBe(true)
	end)

	it("camera: the aim depth is a fraction in (0, 1], and the footprint is RigBuilder's blocker", function()
		for _, bad in { 0, 1.2 } do
			expect(hasProblem(
				camera(function(copy)
					copy.lock.aimDepthFraction = bad
				end),
				"lock.aimDepthFraction"
			)).toBe(true)
		end
		expect(hasProblem(
			camera(function(copy)
				copy.lock.footprintPart = "HumanoidRootPart"
			end),
			"lock.footprintPart"
		)).toBe(true)
	end)

	it("dev: a shot names its staging, a camera side, prompts and a perform list", function()
		expect(hasProblem(
			dev(function(copy)
				copy.capture.shots[1].cameraSide = 0
			end),
			"cameraSide"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.shots[1].prompts = {}
			end),
			".prompts must list at least one beat"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.shots[1].stage.enemies = {}
			end),
			"must stage at least one enemy"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.shots[1].camera = "Nowhere"
			end),
			"'Nowhere' must be Lock or a capture.cameras view"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.shots[1].stage.enemies[1].enemy = "NoSuchEnemy"
			end),
			"'NoSuchEnemy', which is not an enemy the game has"
		)).toBe(true)
	end)

	it("dev: the lock camera only on a shot that locks on", function()
		expect(hasProblem(
			dev(function(copy)
				for _, shot in copy.capture.shots do
					if shot.camera == "Lock" then
						shot.stage.lock = false
					end
				end
			end),
			"takes the Lock camera on a shot that does not lock on"
		)).toBe(true)
	end)

	it("dev: prompt beats start at 0, run in order and show inside the take", function()
		expect(hasProblem(
			dev(function(copy)
				copy.capture.shots[1].prompts[1].at = 1
			end),
			"must be 0: the first prompt shows as the take starts"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				local prompts = copy.capture.shots[1].prompts
				prompts[#prompts].at = copy.capture.shots[1].seconds
			end),
			"must show inside the take"
		)).toBe(true)
	end)

	it("dev: a perform press is a real action, timed by one of a moment and a clip, inside the take", function()
		local function firstPress(copy: any): any
			for _, shot in copy.capture.shots do
				if #shot.perform > 0 then
					return shot.perform[1]
				end
			end
			error("no perform press in dev.luau")
		end
		expect(hasProblem(
			dev(function(copy)
				firstPress(copy).action = "Fly"
			end),
			"'Fly' is not an input.luau action"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				local press = firstPress(copy)
				press.onClip = "enemy/Kobold/Overhead"
				press.lead = 0
				press.at = press.at or 1
			end),
			"must be timed by exactly one of `at` and `onClip`"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				firstPress(copy).hold = 0
			end),
			".hold must be a positive number of seconds"
		)).toBe(true)
	end)

	it("dev: an Art press is held past the start pose and activation, short of the cancel time", function()
		local function artPress(copy: any): any
			for _, shot in copy.capture.shots do
				for _, press in shot.perform do
					if press.action == "Art" or press.action:match("^ArtSlot") ~= nil then
						return press
					end
				end
			end
			error("no Art press in dev.luau")
		end
		local combatData = Harness.load("src/shared/data/combat")
		expect(hasProblem(
			dev(function(copy)
				artPress(copy).hold = combatData.startPoseTime + combatData.activationHold
			end),
			"an Art press is held past the start pose and activation"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				artPress(copy).hold = combatData.activationCancelTime
			end),
			"an Art press is held past the start pose and activation"
		)).toBe(true)
	end)

	it(
		"dev: a released Charger says whether its first charge meets or passes the player on the spot (D-300)",
		function()
			-- A released Charger that does `charge`; with none in dev.luau (every take's charge Meets
			-- since CF), a released one made to say it (the rule is checked on the copy).
			local function charger(copy: any, charge: string): any
				local released = nil
				for _, shot in copy.capture.shots do
					for _, entry in shot.stage.enemies do
						if entry.charge == charge then
							return entry
						end
						released = released or (if entry.charge ~= nil then entry else nil)
					end
				end
				if released == nil then
					error("no released Charger in dev.luau")
				end
				released.charge = charge
				return released
			end
			local reach = Harness.load("src/shared/data/enemies").byId("FrenzyBoar").attacks[1].reach
			expect(hasProblem(
				dev(function(copy)
					charger(copy, "Meets").charge = nil
				end),
				".charge must say what the first charge does to the player on the spot"
			)).toBe(true)
			-- the line ends short of the player: the boar runs over them unhurt (the 18-stud take)
			expect(hasProblem(
				dev(function(copy)
					charger(copy, "Meets").distance = reach + 4
				end),
				"a charge that Meets needs the line"
			)).toBe(true)
			-- the line's end grazes the body: neither a clean hit nor a clean pass
			expect(hasProblem(
				dev(function(copy)
					charger(copy, "Passes").distance = reach + 0.5
				end),
				"a charge that Passes needs the line"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					charger(copy, "Meets").distance = 6
				end),
				"must be inside the charge band"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					charger(copy, "Meets").held = true
				end),
				".charge is only for a released Charger"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					copy.capture.shots[2].stage.enemies[1].charge = "Meets"
				end),
				".charge is only for a released Charger"
			)).toBe(true)
		end
	)

	it(
		"dev: a timed attack has a prompt beat at its press, an Art one at its release, and the glow reads (D-298)",
		function()
			local function shotOf(copy: any, action: string): (any, any)
				for _, shot in copy.capture.shots do
					for _, press in shot.perform do
						if press.action == action and press.at ~= nil then
							return shot, press
						end
					end
				end
				error("no timed " .. action .. " press in dev.luau")
			end
			local function dropBeat(shot: any, at: number)
				for index, beat in shot.prompts do
					if math.abs(beat.at - at) < 1e-6 then
						table.remove(shot.prompts, index)
						return
					end
				end
				error("no beat at " .. at)
			end
			expect(hasProblem(dev(function() end), "needs a prompt beat")).toBe(false)
			-- The snapshot's take: "Q now" at 1.0 s, the key held 0.35 s, so it launched at 1.35 s
			-- under that same line.
			expect(hasProblem(
				dev(function(copy)
					local shot, press = shotOf(copy, "Art")
					dropBeat(shot, press.at + press.hold)
				end),
				"a timed Art needs a prompt beat at its release"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					local _, press = shotOf(copy, "Art")
					press.at += 0.1
				end),
				"a timed Art needs a prompt beat at its press"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					local shot, press = shotOf(copy, "BasicAttack")
					dropBeat(shot, press.at)
				end),
				"a basic needs a prompt beat at its press"
			)).toBe(true)
			-- Past the start pose and activation, yet lit too briefly to read on camera.
			expect(hasProblem(
				dev(function(copy)
					local shot, press = shotOf(copy, "ArtSlot2")
					dropBeat(shot, press.at + press.hold)
					press.hold = 0.3
					table.insert(shot.prompts, { at = press.at + press.hold, text = "Let go" })
					table.sort(shot.prompts, function(a: any, b: any): boolean
						return a.at < b.at
					end)
				end),
				"holds its glow at least capture.artGlowSeconds"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					copy.capture.artGlowSeconds = 0
				end),
				"capture.artGlowSeconds must be a positive number"
			)).toBe(true)
		end
	)

	it("dev: a clip-timed press names a clip with a hit window and leads it inside the parry window", function()
		local function clipPress(copy: any): any
			for _, shot in copy.capture.shots do
				for _, press in shot.perform do
					if press.onClip ~= nil then
						return press
					end
				end
			end
			error("no clip-timed press in dev.luau")
		end
		local combatData = Harness.load("src/shared/data/combat")
		expect(hasProblem(
			dev(function(copy)
				clipPress(copy).lead = combatData.parryWindow
			end),
			"must be 0 or more and under combat.parryWindow"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				clipPress(copy).lead = nil
			end),
			".lead must say how far ahead of the hit window"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				clipPress(copy).onClip = "player/OneHandedSword/Idle"
			end),
			"'player/OneHandedSword/Idle' must name a clip with a HitWindowOpen event"
		)).toBe(true)
	end)

	-- The reactive auto-perform (CF): a Move press holds the stick, reactions to an enemy's clip,
	-- chains after them, standing rules, and an enemy let go partway through the take.
	local function shotNamed(copy: any, id: string): any
		for _, shot in copy.capture.shots do
			if shot.id == id then
				return shot
			end
		end
		error("no shot " .. id .. " in dev.luau")
	end
	local function entryWith(shot: any, check: (any) -> boolean): any
		for _, entry in shot.perform do
			if check(entry) then
				return entry
			end
		end
		error("no such perform entry in " .. shot.id)
	end
	local function moveEntry(copy: any): any
		return entryWith(shotNamed(copy, "locomotion"), function(entry: any): boolean
			return entry.action == "Move"
		end)
	end
	local function timedLock(copy: any): any
		return entryWith(shotNamed(copy, "locomotion"), function(entry: any): boolean
			return entry.action == "LockOn" and entry.at ~= nil
		end)
	end
	local function guardReaction(copy: any): any
		return entryWith(shotNamed(copy, "fight-boar-kobold"), function(entry: any): boolean
			return entry.action == "Guard" and entry.onClip ~= nil
		end)
	end
	local function dodgeReaction(copy: any): any
		return entryWith(shotNamed(copy, "fight-boar-kobold"), function(entry: any): boolean
			return entry.action == "Dodge" and entry.onClip ~= nil
		end)
	end
	local function standingBasic(copy: any): any
		return entryWith(shotNamed(copy, "fight-boar-kobold"), function(entry: any): boolean
			return entry.action == "BasicAttack" and entry.every ~= nil
		end)
	end
	local function lateRelease(copy: any): any
		for _, entry in shotNamed(copy, "fight-boar-kobold").stage.enemies do
			if entry.releaseAfter ~= nil then
				return entry
			end
		end
		error("no enemy let go partway through the fight")
	end

	it("dev: a Move press holds a stick of length (0, 1]; only it has a stick or a sprint (CF)", function()
		for _, bad in { {}, { 0, 0 }, { 1, 1 }, { "1", 0 } :: { any } } :: { any } do
			expect(hasProblem(
				dev(function(copy)
					moveEntry(copy).stick = bad
				end),
				".stick must be {right, forward} with a length above 0 and at most 1"
			)).toBe(true)
		end
		expect(hasProblem(
			dev(function(copy)
				moveEntry(copy).stick = nil
			end),
			".stick must be {right, forward} with a length above 0 and at most 1"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				timedLock(copy).stick = { 1, 0 }
			end),
			".stick is only for a capture.perform.moveAction press"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				moveEntry(copy).sprint = "yes"
			end),
			".sprint must be true or false"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				timedLock(copy).sprint = true
			end),
			".sprint is only for a capture.perform.moveAction press"
		)).toBe(true)
		for _, bad in { "LockOn", 3 } :: { any } do
			expect(hasProblem(
				dev(function(copy)
					copy.capture.perform.moveAction = bad
				end),
				"capture.perform.moveAction must be a name that is not an input.luau action"
			)).toBe(true)
		end
		-- Move is the stick, not a key: never an input action itself.
		expect(hasProblem(dev(), "'Move' is not an input.luau action")).toBe(false)
	end)

	it("dev: timed Move presses never overlap: one stick at a time (CF)", function()
		expect(hasProblem(
			dev(function(copy)
				local shot = shotNamed(copy, "locomotion")
				local moves = {}
				for _, entry in shot.perform do
					if entry.action == "Move" then
						table.insert(moves, entry)
					end
				end
				moves[2].at = moves[1].at + moves[1].hold - 0.1
			end),
			"overlaps the Move before it"
		)).toBe(true)
	end)

	it("dev: an entry is timed by exactly one of a moment, a clip and a standing rule (CF)", function()
		expect(hasProblem(
			dev(function(copy)
				standingBasic(copy).at = 1
			end),
			"must be timed by exactly one of `at` and `onClip`, or by `every`"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				standingBasic(copy).every = nil
			end),
			"must be timed by exactly one of `at` and `onClip`, or by `every`"
		)).toBe(true)
	end)

	it("dev: a reaction names a staged enemy that is let go, and one of its attack clips (CF)", function()
		for _, bad in { 3, 0, 1.5 } do
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).enemy = bad
				end),
				".enemy must name one of the shot's staged enemies (1 to 2)"
			)).toBe(true)
		end
		expect(hasProblem(
			dev(function(copy)
				guardReaction(copy).enemy = 2
			end),
			"must be an attack clip of the enemy it reacts to"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				dodgeReaction(copy).onClip = "enemy/Kobold/Overhead"
			end),
			"must be an attack clip of the enemy it reacts to"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				shotNamed(copy, "fight-boar-kobold").stage.enemies[1].held = true
			end),
			"reacts to an enemy the shot holds"
		)).toBe(true)
		-- the single-clip parry shot reacts to its only enemy, the kobold, unnamed
		expect(hasProblem(dev(), "parry-spark")).toBe(false)
	end)

	it("dev: a reaction's lead: a guard's under the parry window, another's inside the wind-up heard (CF)", function()
		-- The Charge's first event (its voice) comes 0.5 s before its hit window.
		for _, bad in { 0.55, -0.1 } do
			expect(hasProblem(
				dev(function(copy)
					dodgeReaction(copy).lead = bad
				end),
				"must be 0 or more and at most the clip's wind-up after its first event"
			)).toBe(true)
		end
		expect(hasProblem(
			dev(function(copy)
				dodgeReaction(copy).lead = 0.45
			end),
			"lead"
		)).toBe(false)
		expect(hasProblem(
			dev(function(copy)
				guardReaction(copy).lead = 0.2
			end),
			"must be 0 or more and under combat.parryWindow"
		)).toBe(true)
	end)

	it("dev: repeats and lock are true or false, and only on a reaction (CF)", function()
		expect(hasProblem(
			dev(function(copy)
				guardReaction(copy).repeats = "yes"
			end),
			".repeats must be true or false"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				guardReaction(copy).lock = 1
			end),
			".lock must be true or false"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				timedLock(copy).lock = true
			end),
			".lock is only for a clip-timed press"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				standingBasic(copy).repeats = true
			end),
			".repeats is only for a clip-timed press"
		)).toBe(true)
	end)

	it(
		"dev: a chain step comes a delay after the step before it, presses a real action and cycles Arts (CF)",
		function()
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).chain[1].delay = -1
				end),
				".delay must be 0 or more seconds"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).chain[1].at = 1
				end),
				"a chain step is timed by its delay alone"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).chain[1].action = "Fly"
				end),
				"chain[1].action 'Fly' is not an input.luau action"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).chain[1].hold = 0
				end),
				"chain[1].hold must be a positive number of seconds"
			)).toBe(true)
			local combatData = Harness.load("src/shared/data/combat")
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).chain[1].hold = combatData.startPoseTime
				end),
				"an Art press is held past the start pose and activation"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).chain[1].cycle = { "ArtSlot2", "Art" }
				end),
				".cycle must start with the step's own action"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).chain[1].cycle = { "Art", "Dodge" }
				end),
				".cycle must list Art actions"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					local step = dodgeReaction(copy).chain[2]
					step.within = 0
				end),
				".within must be a positive number of studs"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					dodgeReaction(copy).chain[2].stick = nil
				end),
				".stick must be {right, forward} with a length above 0 and at most 1"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					dodgeReaction(copy).chain[1].enemy = 5
				end),
				".enemy must name one of the shot's staged enemies"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					standingBasic(copy).chain = { { action = "Dodge", delay = 0, hold = 0.05 } }
				end),
				".chain is only for a clip-timed press"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).chain = {}
				end),
				".chain must list at least one step"
			)).toBe(true)
		end
	)

	it("dev: a standing rule presses a basic in reach or the lock, every so often inside the take (CF)", function()
		expect(hasProblem(
			dev(function(copy)
				standingBasic(copy).every = 0
			end),
			".every must be a positive number of seconds"
		)).toBe(true)
		for _, window in { { 0, 25 }, { 10, 5 }, { -1, 5 } } do
			expect(hasProblem(
				dev(function(copy)
					local rule = standingBasic(copy)
					rule.from = window[1]
					rule.to = window[2]
				end),
				"must run 0 <= from < to <= the take"
			)).toBe(true)
		end
		expect(hasProblem(
			dev(function(copy)
				standingBasic(copy).within = nil
			end),
			"a standing BasicAttack presses only in reach: `within`"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				standingBasic(copy).action = "Guard"
			end),
			"a standing rule (`every`) presses only BasicAttack or LockOn"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				timedLock(copy).from = 1
			end),
			".from and .to are only for a standing rule"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				timedLock(copy).within = 4
			end),
			".within is only for a standing BasicAttack or a Move chain step"
		)).toBe(true)
	end)

	it("dev: a reaction may end at a `to` inside the take, and has no `from` (D-320)", function()
		local function aboutTo(problems: any): boolean
			return hasProblem(problems, ".from and .to are only for a standing rule")
				or hasProblem(problems, "nothing of the reaction goes down past it")
		end
		expect(aboutTo(dev(function(copy)
			guardReaction(copy).to = 19
		end))).toBe(false)
		for _, bad in { 25, 0, -1, "19" } :: { any } do
			expect(hasProblem(
				dev(function(copy)
					guardReaction(copy).to = bad
				end),
				"nothing of the reaction goes down past it"
			)).toBe(true)
		end
		expect(hasProblem(
			dev(function(copy)
				guardReaction(copy).from = 1
			end),
			".from and .to are only for a standing rule"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				timedLock(copy).to = 6
			end),
			".from and .to are only for a standing rule"
		)).toBe(true)
	end)

	it("dev: an enemy let go partway through says when, inside the take, under a prompt beat (CF)", function()
		for _, bad in { 20, -1 } do
			expect(hasProblem(
				dev(function(copy)
					lateRelease(copy).releaseAfter = bad
				end),
				"must be 0 or more and inside the take"
			)).toBe(true)
		end
		expect(hasProblem(
			dev(function(copy)
				lateRelease(copy).held = true
			end),
			".releaseAfter is only for an enemy the shot lets go (held = false)"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				lateRelease(copy).releaseAfter += 0.2
			end),
			"needs a prompt beat at that moment"
		)).toBe(true)
	end)

	it("dev: the hotkeys are distinct, off the game's bindings and never a function key", function()
		expect(hasProblem(
			dev(function(copy)
				copy.capture.hotkeys.markDone = copy.capture.hotkeys.startCountdown
			end),
			"are both"
		)).toBe(true)
		local input = Harness.load("src/shared/data/input")
		local boundKey: string? = nil
		for _, keys in input.keyboard do
			boundKey = boundKey or keys[1]
		end
		expect(hasProblem(
			dev(function(copy)
				copy.capture.hotkeys.markDone = boundKey
			end),
			"is one of the game's own keyboard bindings"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.hotkeys.markDone = "F7"
			end),
			"must not be a function key"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.hotkeys.autoPerform = nil
			end),
			"capture.hotkeys.autoPerform is missing"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.perform.defaultOn = true
			end),
			"perform.defaultOn"
		)).toBe(true)
	end)

	it("dev: field enemies move past the lock's range, and the stage's numbers are sane", function()
		local cameraData = Harness.load("src/shared/data/camera")
		expect(hasProblem(
			dev(function(copy)
				copy.capture.stage.awayStuds = cameraData.lock.range
			end),
			"must be past camera.luau lock.range"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.stage.requestsPerSecond = 0
			end),
			"capture.stage.requestsPerSecond must be a positive number"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.stage.holdWaitSeconds = copy.capture.stageTimeoutSeconds
			end),
			"capture.stage.holdWaitSeconds must be under capture.stageTimeoutSeconds"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.stage.ledge.standInset = copy.capture.stage.ledge.size[3]
			end),
			"capture.stage.ledge.standInset must be inside the ledge's top"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.walk.ring.thickness = copy.capture.stage.standHeightTolerance
			end),
			"capture.walk.ring.thickness must be positive and under"
		)).toBe(true)
	end)

	it("dev: the render-frame tick is a small square in two palette colors that never flash (D-336)", function()
		expect(hasProblem(
			dev(function(copy)
				copy.capture.frameTick.size = 0
			end),
			"capture.frameTick.size must be a whole number of pixels"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.frameTick.margin = -1
			end),
			"capture.frameTick.margin must be a whole number of pixels"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.frameTick.tokens = { "SystemCyan", "SystemCyan" }
			end),
			"capture.frameTick.tokens must be two different palette tokens"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.frameTick.tokens = { "SystemCyan", "NoSuchToken" }
			end),
			"capture.frameTick.tokens must be two different palette tokens"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.frameTick.tokens = { "SystemCyan", "OutlineInk" }
			end),
			"capture.frameTick.tokens differ in brightness"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.frameTick.maxLuminanceStep = 0.5
			end),
			"capture.frameTick.maxLuminanceStep must be above 0 and at most"
		)).toBe(true)
	end)

	it(
		"dev: the walk rests inside the ring, sprints to a stop with no carry and follows the last leg (D-302)",
		function()
			expect(hasProblem(
				dev(function(copy)
					copy.capture.walk.restStuds = copy.capture.stage.standRadius
				end),
				"capture.walk.restStuds (3) must be under capture.stage.standRadius"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					copy.capture.walk.restDegrees = 90
				end),
				"capture.walk.restDegrees (90) must be under 90"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					copy.capture.walk.restStuds = 0
				end),
				"capture.walk.restStuds must be a positive number"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					copy.capture.walk.secondWalks = 1.5
				end),
				"capture.walk.secondWalks must be a whole number"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					copy.capture.walk.sprintAction = "Run"
				end),
				"capture.walk.sprintAction (Run) must be an input.luau action"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					copy.capture.walk.lookaheadStuds = copy.capture.stage.approachStuds
				end),
				"capture.walk.lookaheadStuds (6) must be under capture.stage.approachStuds"
			)).toBe(true)
			local locomotion = Harness.load("src/shared/data/choreo").locomotion
			expect(hasProblem(
				dev(function(copy)
					copy.capture.walk.carrySeconds = locomotion.stopStepsSeconds
				end),
				"must be under choreo locomotion.stopStepsSeconds"
			)).toBe(true)
			expect(hasProblem(
				dev(function(copy)
					copy.capture.walk.carrySeconds = copy.capture.stage.approachStuds / locomotion.runSpeed
				end),
				"off the last leg"
			)).toBe(true)
		end
	)

	it("dev: the stage's spots stand on the field, its enemies off the ledge, the ledge off the spawns", function()
		local playground = Harness.load("src/shared/data/playground")
		expect(hasProblem(
			dev(function(copy)
				copy.capture.stage.area.position = { playground.fieldRadius, 0, 0 }
			end),
			"capture.stage.area spot must stand"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				copy.capture.stage.ledge.position = table.clone(playground.spawns[1].position)
			end),
			"stands on playground spawn"
		)).toBe(true)
		expect(hasProblem(
			dev(function(copy)
				-- The open shot's enemy straight ahead, on the ledge's own top.
				for _, shot in copy.capture.shots do
					if shot.stage.open then
						shot.stage.enemies[1].side = 0
						shot.stage.enemies[1].distance = 1
					end
				end
			end),
			"stands on the ledge"
		)).toBe(true)
	end)

	it("sfx: the shatter balance names glass and bass that resolve, apart, and a positive gap", function()
		expect(hasProblem(
			sfx(function(copy)
				copy.shatterBalance.glassGapDb = 0
			end),
			"shatterBalance.glassGapDb"
		)).toBe(true)
		expect(hasProblem(
			sfx(function(copy)
				table.insert(copy.shatterBalance.glass, "shatter.NoSuchTake")
			end),
			"'shatter.NoSuchTake' is not a sfx.luau 'family.Name'"
		)).toBe(true)
		expect(hasProblem(
			sfx(function(copy)
				table.insert(copy.shatterBalance.bass, copy.shatterBalance.glass[1])
			end),
			"both glass and bass"
		)).toBe(true)
	end)

	it("sfx: every shatter cue doubles its glass, and its glass leads its bass by the gap", function()
		expect(hasProblem(
			sfx(function(copy)
				local cue = copy.cues[copy.shatterCues.normal]
				for index = #cue, 1, -1 do
					if cue[index].name == copy.shatterBalance.glass[2] then
						table.remove(cue, index)
					end
				end
			end),
			"two glass layers"
		)).toBe(true)
		expect(hasProblem(
			sfx(function(copy)
				copy.shatterBalance.glassGapDb = 40
			end),
			"over its loudest bass layer, under shatterBalance.glassGapDb"
		)).toBe(true)
	end)

	it("contact: the word's hold covers the Kill hold; the keep-out fits the slack (D-312, D-314)", function()
		expect(hasProblem(
			contact("src/shared/data/combat", function(copy)
				copy.contact.wordHoldSeconds = 0.1
			end),
			"wordHoldSeconds (0.1) must be at least the Kill hold"
		)).toBe(true)
		expect(hasProblem(
			contact("src/shared/data/combat", function(copy)
				copy.contact.standOff.keepOut.maxStuds = copy.rootMotionSlack + 0.5
			end),
			"must be within rootMotionSlack"
		)).toBe(true)
		expect(hasProblem(
			contact("src/shared/data/combat", function(copy)
				copy.contact.standOff.keepOut.maxStuds = copy.contact.standOff.maxStuds - 0.5
			end),
			"must be at least standOff.maxStuds"
		)).toBe(true)
	end)

	it("contact: the keep-out stays out of the faces RigBuilder builds, with the body's own parts (D-315)", function()
		expect(hasProblem(
			contact("src/shared/data/combat", function(copy)
				copy.contact.standOff.keepOut.bodyFace = "Body"
			end),
			"bodyFace 'Body' must be RigBuilder's BLOCKER_NAME"
		)).toBe(true)
		expect(hasProblem(
			contact("src/shared/data/combat", function(copy)
				copy.contact.standOff.keepOut.heldFace = "Blocker"
			end),
			"heldFace 'Blocker' must be RigBuilder's HELD_BLOCKER_NAME"
		)).toBe(true)
		expect(hasProblem(
			contact("src/shared/data/combat", function(copy)
				table.insert(copy.contact.standOff.keepOut.parts, "Sword")
			end),
			"'Sword' is not a PlayerR15 part"
		)).toBe(true)
		local plan = contact("src/shared/data/combat", function(copy)
			local keepOut = copy.contact.standOff.keepOut
			keepOut.sampleSeconds = 0
			keepOut.maxTurnDegrees = 0
			keepOut.rounds = 1.5
			keepOut.maxPieces = 0
		end)
		expect(hasProblem(plan, "keepOut.sampleSeconds must be above 0")).toBe(true)
		expect(hasProblem(plan, "keepOut.maxTurnDegrees must be above 0")).toBe(true)
		expect(hasProblem(plan, "keepOut.rounds must be a whole number")).toBe(true)
		expect(hasProblem(plan, "keepOut.maxPieces must be a whole number")).toBe(true)
	end)

	it("contact: a rig's blocker poses its own rig's clips, every one there (D-315)", function()
		expect(hasProblem(
			contact("src/shared/data/rigs", function(copy)
				copy.Kobold.blocker.clips = { "enemy/Boar/Idle" }
			end),
			"rigs.Kobold.blocker.clips[1] 'enemy/Boar/Idle' must be one of the rig's own clips"
		)).toBe(true)
		expect(hasProblem(
			contact("src/shared/data/rigs", function(copy)
				copy.Boar.blocker.clips = { "enemy/Boar/NoSuchIdle" }
			end),
			"'enemy/Boar/NoSuchIdle' is not a clip file"
		)).toBe(true)
		expect(hasProblem(
			contact("src/shared/data/rigs", function(copy)
				copy.Boar.blocker.sampleSeconds = 0
			end),
			"rigs.Boar.blocker.sampleSeconds must be above 0"
		)).toBe(true)
	end)

	it("telegraph: the glint's own numbers, and never on an Unblockable blow (D-316, D-317, D-289)", function()
		local shape = telegraph("src/shared/data/fx", function(copy)
			copy.telegraph.glintFrames = 2.5
			copy.telegraph.glintAimFrames = -1
			copy.telegraph.glintToken = "NoSuchToken"
			copy.telegraph.glintLeadMax = -0.1
			copy.telegraph.glintLeadSamples = 0
		end)
		expect(hasProblem(shape, "glintFrames must be a whole number of at least 1")).toBe(true)
		expect(hasProblem(shape, "glintAimFrames must be 0 or more")).toBe(true)
		expect(hasProblem(shape, "glintToken 'NoSuchToken' is not a palette token")).toBe(true)
		expect(hasProblem(shape, "glintLeadMax must be 0 or more")).toBe(true)
		expect(hasProblem(shape, "glintLeadSamples must be a whole number of at least 1")).toBe(true)
		expect(hasProblem(
			telegraph("src/shared/data/fx", function(copy)
				copy.telegraph.glintKinds.Unblockable = true
			end),
			"glintKinds must not hold Unblockable"
		)).toBe(true)
		expect(hasProblem(
			telegraph("src/shared/data/fx", function(copy)
				copy.telegraph.glintKinds.Heavy = true
			end),
			"glintKinds.Heavy is not a telegraph kind"
		)).toBe(true)
		expect(hasProblem(
			telegraph("src/shared/data/fx", function(copy)
				copy.telegraph.glintDecalAlpha = copy.telegraph.decal.alpha
			end),
			"must be above decal.alpha"
		)).toBe(true)
		expect(hasProblem(
			telegraph("src/shared/data/fx", function(copy)
				copy.telegraph.glintDecalAlpha = 1.2
			end),
			"must be above decal.alpha (0.55) and at most 1"
		)).toBe(true)
	end)

	it(
		"telegraph: every blow that glints glints wholly on its parry window, before its tell goes out (D-316)",
		function()
			-- Longer than the window, earlier than its open, past the tell's end: each puts a blow's
			-- glint frames where a press on them cannot parry.
			expect(hasProblem(
				telegraph("src/shared/data/fx", function(copy)
					copy.telegraph.glintFrames = 10
				end),
				"KoboldAxeman.Overhead: its glint"
			)).toBe(true)
			expect(hasProblem(
				telegraph("src/shared/data/fx", function(copy)
					copy.telegraph.glintAimFrames = 6
				end),
				"(the parry window, to the tell's end)"
			)).toBe(true)
			expect(hasProblem(
				telegraph("src/shared/data/ai", function(copy)
					copy.telegraph.snapLeadSeconds = 0.12
				end),
				"KoboldAxeman.Overhead: its glint"
			)).toBe(true)
			-- An Unblockable blow and a rush never glint, so the rule leaves them be.
			for _, problem in
				telegraph("src/shared/data/fx", function(copy)
					copy.telegraph.glintFrames = 10
				end)
			do
				expect(problem:find("FrenzyBoar.Charge", 1, true)).toBeNil()
				expect(problem:find("elite Charger.Trample", 1, true)).toBeNil()
			end
		end
	)

	it("combat: the assist's cone within the snap, the blade's edge beside the swing, the wall gap", function()
		local function combat(mutate: (any) -> ()): { string }
			return runWith("combat", "src/shared/data/combat", mutate)
		end
		-- One call holds three independent problems; each names its own numbers.
		local wide = combat(function(copy)
			copy.aim.assistConeDegrees = 82
			copy.besideHitRadius = 0.17
			copy.contact.standOff.wallGapStuds = 0.06
		end)
		expect(hasProblem(wide, "combat: aim.assistConeDegrees 82 is more than twice aim.snapDegrees (40)")).toBe(true)
		expect(
			hasProblem(
				wide,
				"combat: besideHitRadius 0.17 is over half the narrowest in-scope blade (OneHandedSword, 0.32 wide)"
			)
		).toBe(true)
		expect(hasProblem(wide, "combat: contact.standOff.wallGapStuds 0.06 is over contact.standOff.stepStuds (0.05)")).toBe(
			true
		)
		-- The follow step splits the arc only down to the straight steps of the radius.
		expect(hasProblem(
			combat(function(copy)
				copy.besideFollowStep = copy.besideHitRadius
			end),
			"combat: besideFollowStep 0.15 must be above besideHitRadius (0.15)"
		)).toBe(true)
		expect(hasProblem(
			combat(function(copy)
				copy.contact.standOff.wallGapStuds = -0.01
			end),
			"combat: contact.standOff.wallGapStuds must be a number, 0 or more (got -0.01)"
		)).toBe(true)
		-- At the edges each rule still passes: half the cone at the snap, the gap one step, and only
		-- in-scope blades count (the Rapier's 0.16 is no Phase 0 weapon).
		expect(combat(function(copy)
			copy.aim.assistConeDegrees = 80
			copy.besideHitRadius = 0.16
			copy.contact.standOff.wallGapStuds = copy.contact.standOff.stepStuds
		end)).toEqual({})
	end)

	it("combat: a struck stance falls inside the stagger and slower than a plain end (D-340)", function()
		local function combat(mutate: (any) -> ()): { string }
			return runWith("combat", "src/shared/data/combat", mutate)
		end
		local choreo = Harness.load("src/shared/data/choreo")
		local long = combat(function(copy)
			copy.struckStanceBlendOut = copy.staggerDuration + 0.1
			copy.struckStanceTipSpeed = choreo.sheath.drawTipSpeed
		end)
		expect(hasProblem(long, "combat: struckStanceBlendOut 0.6 is over staggerDuration (0.5)")).toBe(true)
		expect(hasProblem(long, "combat: struckStanceTipSpeed 84 must be under choreo.sheath.drawTipSpeed (84)")).toBe(
			true
		)
		expect(hasProblem(
			combat(function(copy)
				copy.struckStanceBlendOut = 0.15
			end),
			"combat: struckStanceBlendOut 0.15 is under locomotionBlendOut (0.2)"
		)).toBe(true)
		expect(hasProblem(
			combat(function(copy)
				copy.struckStanceTipSpeed = 0
			end),
			"combat: struckStanceTipSpeed must be a positive number (got 0)"
		)).toBe(true)
		-- At the edges each rule still passes.
		expect(combat(function(copy)
			copy.struckStanceBlendOut = copy.staggerDuration
		end)).toEqual({})
		expect(combat(function(copy)
			copy.struckStanceBlendOut = copy.locomotionBlendOut
		end)).toEqual({})
	end)

	it("camera: the catch-up lifts the cap and eases; the still shot and the wall side are fractions", function()
		local bad = camera(function(copy)
			copy.lock.catchUpDegreesPerSecond = copy.lock.maxTurnDegreesPerSecond - 1
			copy.lock.catchUpMostDegrees = 0
			copy.lock.catchUpMargin = -0.1
			copy.lock.catchUpEase = 0
			copy.lock.riseHoldSeconds = -1
			copy.lock.wallBlockedFraction = 0
			copy.lock.wallGainFraction = 1.2
		end)
		for _, needle in
			{
				"camera: lock.catchUpDegreesPerSecond must be at least lock.maxTurnDegreesPerSecond",
				"camera: lock.catchUpMostDegrees must be a positive number of degrees",
				"camera: lock.catchUpMargin must be 0 or more",
				"camera: lock.catchUpEase must be a positive number of seconds",
				"camera: lock.riseHoldSeconds must be 0 or more seconds",
				"camera: lock.wallBlockedFraction must be in (0, 1]",
				"camera: lock.wallGainFraction must be in [0, 1]",
			}
		do
			expect(hasProblem(bad, needle)).toBe(true)
		end
		expect(#bad).toBe(7)
		-- The edges: a catch-up at the cap, no margin, no hold, a wall at the whole reach, no gain.
		expect(camera(function(copy)
			copy.lock.catchUpDegreesPerSecond = copy.lock.maxTurnDegreesPerSecond
			copy.lock.catchUpMargin = 0
			copy.lock.riseHoldSeconds = 0
			copy.lock.wallBlockedFraction = 1
			copy.lock.wallGainFraction = 0
		end)).toEqual({})
		expect(hasProblem(
			camera(function(copy)
				copy.lock.wallBlockedFraction = 1.5
			end),
			"camera: lock.wallBlockedFraction must be in (0, 1]"
		)).toBe(true)
	end)

	it("choreo and stride: the sheath's moving share and the held walks' rise", function()
		local function choreo(mutate: (any) -> ()): { string }
			return runWith("choreo", "src/shared/data/choreo", mutate)
		end
		local function stride(mutate: (any) -> ()): { string }
			return runWith("stride", "src/shared/data/choreo", mutate)
		end
		expect(choreo(function() end)).toEqual({})
		expect(stride(function() end)).toEqual({})
		expect(hasProblem(
			choreo(function(copy)
				copy.sheath.movingTipShare = 0
			end),
			"choreo: sheath.movingTipShare (0) must be in (0, 1]"
		)).toBe(true)
		expect(hasProblem(
			choreo(function(copy)
				copy.sheath.movingTipShare = 1.1
			end),
			"choreo: sheath.movingTipShare (1.1) must be in (0, 1]"
		)).toBe(true)
		expect(choreo(function(copy)
			copy.sheath.movingTipShare = 1
		end)).toEqual({})
		for _, bad in { 0, -0.4, 0 / 0, math.huge } :: { any } do
			expect(hasProblem(
				stride(function(copy)
					copy.locomotion.stride.heldRiseSeconds = bad
				end),
				("stride: heldRiseSeconds (%s) must be a positive number of seconds"):format(tostring(bad))
			)).toBe(true)
		end
	end)

	it("dev: the Studio test hooks' numbers fit the game they wait on (D-333)", function()
		local cases: { { needle: string, mutate: (any) -> () } } = {
			{
				needle = "hooks table is missing",
				mutate = function(copy)
					copy.hooks = nil
				end,
			},
			{
				-- Arrived 3 studs off is no longer at home: the leash would walk it back.
				needle = "hooks.arriveStuds (3) must be positive and under ai.luau leash.homeRadius (3)",
				mutate = function(copy)
					copy.hooks.arriveStuds = 3
				end,
			},
			{
				needle = "hooks.arriveStuds (0) must be positive",
				mutate = function(copy)
					copy.hooks.arriveStuds = 0
				end,
			},
			{
				needle = "hooks.maxWalkStuds must be a positive number of studs",
				mutate = function(copy)
					copy.hooks.maxWalkStuds = 0 / 0
				end,
			},
			{
				-- The slowest walking enemy (5 studs a second) needs 24 s for twice a 60-stud walk.
				needle = "hooks.walkTimeoutSeconds (20) must give the slowest walking enemy (5 studs a second) twice its longest walk (24 s)",
				mutate = function(copy)
					copy.hooks.walkTimeoutSeconds = 20
				end,
			},
			{
				-- A wind-up of 0.6 s, a pause cap of 0.25 s and a 0.786 s run.
				needle = "hooks.chargeTimeoutSeconds (1.5) must outlast every Charger rush's wind-up, pauses and run (1.636 s)",
				mutate = function(copy)
					copy.hooks.chargeTimeoutSeconds = 1.5
					copy.hooks.maxAfterSeconds = 1
				end,
			},
			{
				needle = "hooks.folderName must be a plain instance name",
				mutate = function(copy)
					copy.hooks.folderName = "Dev Parts"
				end,
			},
			{
				needle = "hooks.folderName 'Playground' is already a name in the place",
				mutate = function(copy)
					copy.hooks.folderName = "Playground"
				end,
			},
			{
				needle = "hooks.maxParts must be a whole number from 1 to 256",
				mutate = function(copy)
					copy.hooks.maxParts = 1000
				end,
			},
			{
				needle = "hooks.maxParts must be a whole number from 1 to 256",
				mutate = function(copy)
					copy.hooks.maxParts = 2.5
				end,
			},
			{
				needle = "hooks.minPartStuds and maxPartStuds must satisfy 0 < min < max <= 2048",
				mutate = function(copy)
					copy.hooks.minPartStuds = copy.hooks.maxPartStuds
				end,
			},
			{
				needle = "hooks.minPartStuds and maxPartStuds must satisfy 0 < min < max <= 2048",
				mutate = function(copy)
					copy.hooks.maxPartStuds = 4096
				end,
			},
			{
				needle = "hooks.maxAfterSeconds (4) must be positive and at most hooks.chargeTimeoutSeconds (3)",
				mutate = function(copy)
					copy.hooks.maxAfterSeconds = 4
				end,
			},
			{
				needle = "hooks.maxNameLength must be a whole number from 1 to 100",
				mutate = function(copy)
					copy.hooks.maxNameLength = 0
				end,
			},
			{
				needle = "hooks.partColorToken 'Beige' is not a palette token",
				mutate = function(copy)
					copy.hooks.partColorToken = "Beige"
				end,
			},
			{
				needle = "hooks.partMaterial 'Cheese' is not an Enum.Material",
				mutate = function(copy)
					copy.hooks.partMaterial = "Cheese"
				end,
			},
		}
		for _, case in cases do
			local problems = dev(case.mutate)
			if not hasProblem(problems, case.needle) then
				error(("expected '%s' in { %s }"):format(case.needle, table.concat(problems, " | ")))
			end
		end
		-- At the edges: an arrival just under the home radius and a timeout of exactly the slowest
		-- walk twice over are fine.
		expect(dev(function(copy)
			copy.hooks.arriveStuds = 2.99
			copy.hooks.walkTimeoutSeconds = 24
		end)).toEqual({})
	end)

	it("wallSlam: the shake fades from shakeFullRadius to nothing at shakeRadius (D-296)", function()
		local function wallSlam(dataPath: string, mutate: (any) -> ()): { string }
			return runWith("wallSlam", dataPath, mutate)
		end
		expect(wallSlam("src/shared/data/fx", function() end)).toEqual({})
		expect(hasProblem(
			wallSlam("src/shared/data/fx", function(copy)
				copy.wallSlam.shakeFullRadius = copy.wallSlam.shakeRadius
			end),
			"wallSlam: shakeFullRadius (32) must be in [0, shakeRadius 32)"
		)).toBe(true)
		expect(hasProblem(
			wallSlam("src/shared/data/fx", function(copy)
				copy.wallSlam.shakeFullRadius = -1
			end),
			"wallSlam: shakeFullRadius (-1) must be in [0, shakeRadius 32)"
		)).toBe(true)
		expect(hasProblem(
			wallSlam("src/shared/data/fx", function(copy)
				copy.wallSlam.shakeRadius = 0
			end),
			"wallSlam: shakeRadius (0) must be a positive number of studs"
		)).toBe(true)
		expect(hasProblem(
			wallSlam("src/shared/data/fx", function(copy)
				copy.wallSlam.shakeTier = "Huge"
			end),
			"wallSlam: shakeTier 'Huge' must be a tier of combat.cameraShakeStuds"
		)).toBe(true)
		-- A full radius of 0 is a shake that fades from the contact itself: fine.
		expect(wallSlam("src/shared/data/fx", function(copy)
			copy.wallSlam.shakeFullRadius = 0
		end)).toEqual({})
	end)
end)
