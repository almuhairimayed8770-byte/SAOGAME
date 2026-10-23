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

-- A choreo.luau stand-in that names no locomotion or sheath clips (the synthetic trees hold none).
local function emptyChoreo(): any
	return {
		priority = { Sheath = 8 },
		locomotion = { clipPrefix = "player/OneHandedSword/", clips = {} },
		sheath = { clips = {}, drawCutClips = {} },
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
	local function runImpact(mutate: (impact: any) -> ()): { string }
		local impact = deepCopy(Harness.load("src/shared/data/impact"))
		mutate(impact)
		local validate = loadTool("tools/validators/impact")
		return validate({
			load = function(path: string)
				if path == "src/shared/data/impact" then
					return impact
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
