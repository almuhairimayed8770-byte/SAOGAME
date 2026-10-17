--!strict
--[[
	Clip validator (section 10, ARCHITECTURE "Clips"). For every module under src/shared/clips:

	- the table has the Types.ClipDef shape: id matches its path, rig exists in rigs.luau, every
	  joint name exists in that rig, keys sorted by time inside [0, duration], easing names valid,
	  no "Linear" on a key that moves a joint (root-only keys may be Linear), events sorted,
	  HitWindowOpen / HitWindowClose pairs balanced, every Sfx / Voice event names its sound as a
	  sfx.luau "family.Name" that Sfx.get resolves (the client plays it through SfxPool.play);
	- attack clips (attack = true) define all six beats in order
	  (Anticipation < Snap <= Smear < Hold <= Settle < Recovery), Snap 2..4 frames, Anticipation
	  4..10 frames (a warning, not an error, on enemy clips: enemies hold longer), hitStop set, at
	  least one hit window (unless the Art it belongs to has 0 hits), TrailOn/TrailOff and
	  SmearOn/SmearOff present, and for player Arts ActivationHold and PostMotionStart present;
	- cross-checks: every Art in arts.luau has a clip file whose hit-window count equals the Art's
	  hits and whose duration covers the Art's total; every enemy attack clip in enemies.luau and
	  every boss attack clip in bosses.luau exists, is an attack clip, and its Anticipation beat
	  covers the attack's windUp - 0.05.

	Phase scope (D-015, src/shared/data/scope.luau): a missing clip for an Art, enemy or boss in
	the current phase's scope is a problem; missing clips for later-phase rows are collected into
	ONE summary warning and are not counted. A clip file that exists is always validated in full.
	A missing sibling table (arts, enemies, bosses, scope) is a problem; without scope.luau every
	row counts as in scope, so nothing is hidden. Warnings are printed and not counted.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local FPS = 60
local FRAME = 1 / FPS
local EPSILON = 1e-6
local ENEMY_WINDUP_SLACK = 0.05

local ANTICIPATION_FRAMES = { min = 4, max = 10 }
local SNAP_FRAMES = { min = 2, max = 4 }

local CLIPS_DIRECTORY = "src/shared/clips"

local EVENT_KINDS = {
	HitWindowOpen = true,
	HitWindowClose = true,
	TrailOn = true,
	TrailOff = true,
	SmearOn = true,
	SmearOff = true,
	Footstep = true,
	Voice = true,
	Sfx = true,
	ActivationHold = true,
	PostMotionStart = true,
	WeaponSwap = true,
	CameraNudge = true,
}

-- Event kinds whose data.name is a sound in src/shared/data/sfx.luau.
local SOUND_KINDS = { Sfx = true, Voice = true }

local LAYERS = { Base = true, UpperBody = true, Additive = true, FullBody = true }
local HIT_STOPS = { Normal = true, Final = true, Kill = true }
local BEATS = { "Anticipation", "Snap", "Smear", "Hold", "Settle", "Recovery" }
local BACKLOG_KINDS = { "Arts", "enemy attacks", "boss attacks" }

local function isVec3(value: any): boolean
	if typeof(value) ~= "table" or #value ~= 3 then
		return false
	end
	for index = 1, 3 do
		if typeof(value[index]) ~= "number" then
			return false
		end
	end
	return true
end

local function shortError(err: any): string
	local text = tostring(err)
	local last = text:match("([^\n]+)$") or text
	return last:sub(1, 160)
end

local function clipName(id: string): string
	return id:match("([^/]+)$") or id
end

local function isPlayerArtClip(id: string): boolean
	return id:sub(1, 7) == "player/" and clipName(id):match("^Basic%d") == nil
end

local function isEnemyClip(id: string): boolean
	return id:sub(1, 6) == "enemy/"
end

return function(ctx: Context): { string }
	local problems: { string } = {}
	local warnings: { string } = {}

	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end
	local function warning(format: string, ...: any)
		table.insert(warnings, string.format(format, ...))
	end

	local function tryLoad(path: string): (any, string?)
		local ok, result = pcall(ctx.load, path)
		if ok then
			return result, nil
		end
		return nil, shortError(result)
	end

	local Easing = ctx.load("src/shared/util/Easing")
	local ClipSampler = ctx.load("src/shared/choreo/ClipSampler")
	local rigs = ctx.load("src/shared/data/rigs")

	local rigJoints: { [string]: { [string]: boolean } } = {}
	for rigId, rig in rigs do
		local joints = {}
		for _, joint in rig.joints do
			joints[joint.name] = true
		end
		rigJoints[rigId] = joints
	end

	-- Sibling tables: optional until their packages land, reported when missing.
	local arts, artsError = tryLoad("src/shared/data/arts")
	if arts == nil then
		problem("src/shared/data/arts.luau is missing or failed to load (%s)", artsError or "?")
	end
	local enemies, enemiesError = tryLoad("src/shared/data/enemies")
	if enemies == nil then
		problem("src/shared/data/enemies.luau is missing or failed to load (%s)", enemiesError or "?")
	end
	local bosses, bossesError = tryLoad("src/shared/data/bosses")
	if bosses == nil then
		problem("src/shared/data/bosses.luau is missing or failed to load (%s)", bossesError or "?")
	end
	-- The sound registry clip Sfx / Voice events name; without it every sound event is unresolved.
	local sfx, sfxError = tryLoad("src/shared/data/sfx")
	if sfx == nil or typeof(sfx.get) ~= "function" then
		problem("src/shared/data/sfx.luau is missing or failed to load (%s)", sfxError or "no Sfx.get")
		sfx = nil
	end

	-- Phase scope (D-015). Without it every row is in scope, so a missing scope hides nothing.
	local scope, scopeError = tryLoad("src/shared/data/scope")
	if scope == nil then
		problem(
			"src/shared/data/scope.luau is missing or failed to load (%s); every row is treated as in scope",
			scopeError or "?"
		)
	end
	local function inScope(helper: string, id: string): boolean
		if scope == nil or typeof(scope[helper]) ~= "function" then
			return true
		end
		return scope[helper](id) == true
	end

	-- Missing clips of later-phase rows: a set of clip ids per kind, summarized as one warning.
	local backlog: { [string]: { [string]: boolean } } = {}
	for _, kind in BACKLOG_KINDS do
		backlog[kind] = {}
	end
	local function missingClip(kind: string, clipId: string, isInScope: boolean, format: string, ...: any)
		if isInScope then
			problem(format, ...)
		else
			backlog[kind][clipId] = true
		end
	end

	-- Sibling tables keep their rows under `rows` (keyed by id); fall back to the module itself.
	local function rowsOf(module: any): { [any]: any }
		if typeof(module) == "table" and typeof(module.rows) == "table" then
			return module.rows
		end
		return module
	end
	local artRows = rowsOf(arts)
	local enemyRows = rowsOf(enemies)
	local bossRows = rowsOf(bosses)

	local artByClip: { [string]: any } = {}
	if arts then
		for key, art in artRows do
			if typeof(art) == "table" and typeof(art.clip) == "string" then
				artByClip[art.clip] = art
			else
				problem("arts.luau entry %s has no clip id", tostring(key))
			end
		end
	end

	-- Discover clip files.
	local okList, files = pcall(ctx.listFiles, CLIPS_DIRECTORY, "%.luau$")
	if not okList then
		files = {}
	end
	local present: { [string]: boolean } = {}
	local loaded: { [string]: any } = {}
	for _, file in files :: { string } do
		local id = file:match("^" .. CLIPS_DIRECTORY .. "/(.-)%.luau$")
		if id == nil then
			continue
		end
		present[id] = true
	end

	local function validateKeys(id: string, clip: any, joints: { [string]: boolean })
		if typeof(clip.keys) ~= "table" then
			problem("%s: keys must be an array", id)
			return
		end
		local lastTime = -math.huge
		for index, key in ipairs(clip.keys) do
			local label = ("%s key %d"):format(id, index)
			if typeof(key) ~= "table" then
				problem("%s is not a table", label)
				continue
			end
			if typeof(key.time) ~= "number" then
				problem("%s has no time", label)
			else
				if key.time < -EPSILON or key.time > clip.duration + EPSILON then
					problem("%s time %s is outside [0, %s]", label, tostring(key.time), tostring(clip.duration))
				end
				if key.time < lastTime - EPSILON then
					problem(
						"%s time %s is earlier than the previous key (keys must be sorted)",
						label,
						tostring(key.time)
					)
				end
				lastTime = key.time
			end
			local okEasing = pcall(Easing.get, key.easing)
			if not okEasing then
				problem("%s has unknown easing '%s'", label, tostring(key.easing))
			end
			if typeof(key.joints) ~= "table" then
				problem("%s has no joints table", label)
				continue
			end
			local movesJoint = false
			for jointName, jointKey in key.joints do
				movesJoint = true
				if not joints[jointName] then
					problem(
						"%s moves joint '%s' which is not in rig '%s'",
						label,
						tostring(jointName),
						tostring(clip.rig)
					)
				end
				if typeof(jointKey) ~= "table" then
					problem("%s joint '%s' is not a table", label, tostring(jointName))
					continue
				end
				if jointKey.pos ~= nil and not isVec3(jointKey.pos) then
					problem("%s joint '%s' pos is not {x, y, z}", label, tostring(jointName))
				end
				if jointKey.rot ~= nil and not isVec3(jointKey.rot) then
					problem("%s joint '%s' rot is not {x, y, z}", label, tostring(jointName))
				end
			end
			if key.easing == "Linear" and movesJoint then
				problem("%s uses Linear easing on a limb (Linear is allowed on root-only keys)", label)
			end
			if key.root ~= nil then
				if typeof(key.root) ~= "table" then
					problem("%s root is not a table", label)
				else
					if key.root.pos ~= nil and not isVec3(key.root.pos) then
						problem("%s root pos is not {x, y, z}", label)
					end
					if key.root.rot ~= nil and not isVec3(key.root.rot) then
						problem("%s root rot is not {x, y, z}", label)
					end
				end
			end
		end
	end

	-- A Sfx / Voice event's data.name must resolve the way SfxPool.play resolves it: split at the
	-- first dot into family and entry, then Sfx.get(family, entry).
	local function validateSound(label: string, event: any)
		local data = event.data
		local name = if typeof(data) == "table" then data.name else nil
		if typeof(name) ~= "string" then
			problem("%s (%s) has no data.name naming a sfx.luau sound", label, tostring(event.kind))
			return
		end
		local family, entry = name:match("^([^%.]+)%.(.+)$")
		if family == nil or entry == nil then
			problem("%s (%s) sound '%s' is not a sfx.luau 'family.Name'", label, tostring(event.kind), name)
			return
		end
		if sfx == nil then
			return -- the missing registry is already reported
		end
		if not pcall(sfx.get, family, entry) then
			problem("%s (%s) sound '%s' is not in sfx.luau", label, tostring(event.kind), name)
		end
	end

	local function validateEvents(id: string, clip: any): { [string]: number }
		local counts: { [string]: number } = {}
		if typeof(clip.events) ~= "table" then
			problem("%s: events must be an array", id)
			return counts
		end
		local lastTime = -math.huge
		local openWindow = false
		for index, event in ipairs(clip.events) do
			local label = ("%s event %d"):format(id, index)
			if typeof(event) ~= "table" then
				problem("%s is not a table", label)
				continue
			end
			if not EVENT_KINDS[event.kind] then
				problem("%s has unknown kind '%s'", label, tostring(event.kind))
			else
				counts[event.kind] = (counts[event.kind] or 0) + 1
			end
			if SOUND_KINDS[event.kind] then
				validateSound(label, event)
			end
			if typeof(event.time) ~= "number" then
				problem("%s has no time", label)
				continue
			end
			if event.time < -EPSILON or event.time > clip.duration + EPSILON then
				problem("%s time %s is outside [0, %s]", label, tostring(event.time), tostring(clip.duration))
			end
			if event.time < lastTime - EPSILON then
				problem(
					"%s time %s is earlier than the previous event (events must be sorted)",
					label,
					tostring(event.time)
				)
			end
			lastTime = event.time
			if event.kind == "HitWindowOpen" then
				if openWindow then
					problem("%s opens a hit window while one is already open", label)
				end
				openWindow = true
			elseif event.kind == "HitWindowClose" then
				if not openWindow then
					problem("%s closes a hit window that was never opened", label)
				end
				openWindow = false
			end
		end
		if openWindow then
			problem("%s: the last hit window is never closed", id)
		end
		return counts
	end

	local function validateBeats(id: string, clip: any)
		local beats = clip.beats
		if typeof(beats) ~= "table" then
			problem("%s: attack clip has no beats table", id)
			return
		end
		local spans: { [string]: { start: number, finish: number } } = {}
		for _, beat in BEATS do
			local span = beats[beat]
			if typeof(span) ~= "table" or typeof(span.start) ~= "number" or typeof(span.finish) ~= "number" then
				problem("%s: beat '%s' is missing or has no {start, finish}", id, beat)
				continue
			end
			if span.start < -EPSILON or span.finish > clip.duration + EPSILON then
				problem("%s: beat '%s' lies outside [0, %s]", id, beat, tostring(clip.duration))
			end
			if span.finish < span.start - EPSILON then
				problem("%s: beat '%s' ends before it starts", id, beat)
			end
			spans[beat] = span
		end
		local function before(a: string, b: string, strict: boolean)
			local first, second = spans[a], spans[b]
			if first == nil or second == nil then
				return
			end
			if strict then
				if first.start >= second.start - EPSILON then
					problem("%s: beat '%s' must start before '%s'", id, a, b)
				end
			elseif first.start > second.start + EPSILON then
				problem("%s: beat '%s' must not start after '%s'", id, a, b)
			end
		end
		before("Anticipation", "Snap", true)
		before("Snap", "Smear", false)
		before("Smear", "Hold", true)
		before("Hold", "Settle", false)
		before("Settle", "Recovery", true)

		local anticipation = spans.Anticipation
		if anticipation then
			local frames = (anticipation.finish - anticipation.start) / FRAME
			if frames < ANTICIPATION_FRAMES.min - EPSILON or frames > ANTICIPATION_FRAMES.max + EPSILON then
				local message = ("%s: Anticipation is %.1f frames at %d fps (expected %d..%d)"):format(
					id,
					frames,
					FPS,
					ANTICIPATION_FRAMES.min,
					ANTICIPATION_FRAMES.max
				)
				if isEnemyClip(id) then
					warning("%s; enemy wind-ups are checked against enemies.luau instead", message)
				else
					problem("%s", message)
				end
			end
		end
		local snap = spans.Snap
		if snap then
			local frames = (snap.finish - snap.start) / FRAME
			if frames < SNAP_FRAMES.min - EPSILON or frames > SNAP_FRAMES.max + EPSILON then
				problem(
					"%s: Snap is %.1f frames at %d fps (expected %d..%d)",
					id,
					frames,
					FPS,
					SNAP_FRAMES.min,
					SNAP_FRAMES.max
				)
			end
		end
	end

	-- The clip's hit-window count through the runtime sampler, or nil when the events array is
	-- malformed (already reported by validateEvents) so the sampler is never handed bad data.
	local function hitWindowCount(clip: any): number?
		if typeof(clip.events) ~= "table" then
			return nil
		end
		for _, event in ipairs(clip.events) do
			if typeof(event) ~= "table" or typeof(event.time) ~= "number" then
				return nil
			end
		end
		return #ClipSampler.hitWindows(clip)
	end

	local function validateAttack(id: string, clip: any, counts: { [string]: number })
		validateBeats(id, clip)
		if not HIT_STOPS[clip.hitStop] then
			problem("%s: attack clip needs hitStop Normal | Final | Kill (got %s)", id, tostring(clip.hitStop))
		end
		local art = artByClip[id]
		local windows = hitWindowCount(clip)
		if windows == 0 and not (art and art.hits == 0) then
			problem("%s: attack clip has no HitWindowOpen/HitWindowClose pair", id)
		end
		for _, kind in { "TrailOn", "TrailOff", "SmearOn", "SmearOff" } do
			if (counts[kind] or 0) == 0 then
				problem("%s: attack clip has no %s event", id, kind)
			end
		end
		if isPlayerArtClip(id) then
			for _, kind in { "ActivationHold", "PostMotionStart" } do
				if (counts[kind] or 0) == 0 then
					problem("%s: player Art clip has no %s event", id, kind)
				end
			end
		end
	end

	local function validateClip(id: string, clip: any)
		if typeof(clip) ~= "table" then
			problem("%s: module did not return a table", id)
			return
		end
		if clip.id ~= id then
			problem("%s: id '%s' does not match its path", id, tostring(clip.id))
		end
		if typeof(clip.duration) ~= "number" or clip.duration <= 0 then
			problem("%s: duration must be a positive number", id)
			return
		end
		if typeof(clip.loop) ~= "boolean" then
			problem("%s: loop must be a boolean", id)
		end
		if not LAYERS[clip.layer] then
			problem("%s: unknown layer '%s'", id, tostring(clip.layer))
		end
		for _, field in { "priority", "blendIn", "blendOut" } do
			if clip[field] ~= nil and typeof(clip[field]) ~= "number" then
				problem("%s: %s must be a number", id, field)
			end
		end
		local joints = rigJoints[clip.rig]
		if joints == nil then
			problem("%s: rig '%s' is not in rigs.luau", id, tostring(clip.rig))
			joints = {}
		end
		validateKeys(id, clip, joints)
		local counts = validateEvents(id, clip)
		if clip.attack == true then
			validateAttack(id, clip, counts)
		elseif clip.attack ~= nil and clip.attack ~= false then
			problem("%s: attack must be a boolean", id)
		end
	end

	local ids = {}
	for id in present do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local clip, err = tryLoad(CLIPS_DIRECTORY .. "/" .. id)
		if clip == nil then
			problem("%s/%s.luau failed to load (%s)", CLIPS_DIRECTORY, id, err or "?")
			continue
		end
		loaded[id] = clip
		validateClip(id, clip)
	end

	local function sortedRows(rows: { [any]: any }): { { key: string, def: any } }
		local list = {}
		for key, def in rows do
			table.insert(list, { key = tostring(key), def = def })
		end
		table.sort(list, function(a, b)
			return a.key < b.key
		end)
		return list
	end

	-- Cross-check: Arts.
	if arts then
		for _, row in sortedRows(artRows) do
			local art = row.def
			if typeof(art) ~= "table" or typeof(art.clip) ~= "string" then
				continue
			end
			local clip = loaded[art.clip]
			if not present[art.clip] then
				missingClip(
					"Arts",
					art.clip,
					inScope("hasArt", row.key),
					"Art %s: clip file %s/%s.luau is missing",
					row.key,
					CLIPS_DIRECTORY,
					art.clip
				)
				continue
			end
			if clip == nil then
				continue -- load failure already reported
			end
			local windows = hitWindowCount(clip)
			if windows ~= nil and windows ~= art.hits then
				problem(
					"Art %s: clip %s has %d hit windows but the Art has %s hits",
					row.key,
					art.clip,
					windows,
					tostring(art.hits)
				)
			end
			if typeof(art.total) == "number" and clip.duration < art.total - EPSILON then
				problem(
					"Art %s: clip %s duration %s is shorter than the Art's total %s",
					row.key,
					art.clip,
					tostring(clip.duration),
					tostring(art.total)
				)
			end
			if clip.attack ~= true then
				problem("Art %s: clip %s is not marked attack = true", row.key, art.clip)
			end
		end
	end

	-- Cross-check: one enemy or boss attack. The clip id is enemy/<skin>/<clip> unless the row
	-- spells a full id. A present clip must be an attack clip whose Anticipation beat holds for the
	-- attack's windUp; a missing one is a problem in scope and a backlog entry outside it.
	local function crossCheckAttack(label: string, attack: any, skin: any, kind: string, isInScope: boolean)
		local clipId = attack.clip
		if not clipId:find("/", 1, true) then
			clipId = ("enemy/%s/%s"):format(tostring(skin), clipId)
		end
		if not present[clipId] then
			missingClip(kind, clipId, isInScope, "%s: clip file %s/%s.luau is missing", label, CLIPS_DIRECTORY, clipId)
			return
		end
		local clip = loaded[clipId]
		if clip == nil then
			return -- load failure already reported
		end
		if clip.attack ~= true then
			problem("%s: clip %s is not marked attack = true", label, clipId)
		end
		local anticipation = typeof(clip.beats) == "table" and clip.beats.Anticipation or nil
		if typeof(attack.windUp) == "number" and typeof(anticipation) == "table" then
			local held = (anticipation.finish or 0) - (anticipation.start or 0)
			if held < attack.windUp - ENEMY_WINDUP_SLACK - EPSILON then
				problem(
					"%s: clip %s holds Anticipation for %.2f s but the attack's windUp is %.2f s",
					label,
					clipId,
					held,
					attack.windUp
				)
			end
		end
	end

	-- Cross-check: enemy attacks.
	if enemies then
		for _, row in sortedRows(enemyRows) do
			local def = row.def
			if typeof(def) ~= "table" or typeof(def.attacks) ~= "table" then
				continue
			end
			local isInScope = inScope("hasEnemy", row.key)
			for _, attack in ipairs(def.attacks) do
				if typeof(attack) ~= "table" or typeof(attack.clip) ~= "string" then
					problem("enemy %s has an attack without a clip id", row.key)
					continue
				end
				local label = ("enemy %s attack %s"):format(row.key, tostring(attack.id or attack.name or "?"))
				crossCheckAttack(label, attack, def.skin, "enemy attacks", isInScope)
			end
		end
	end

	-- Cross-check: boss attacks, phase by phase.
	if bosses then
		for _, row in sortedRows(bossRows) do
			local def = row.def
			if typeof(def) ~= "table" or typeof(def.phases) ~= "table" then
				continue
			end
			local isInScope = inScope("hasBoss", row.key)
			for phaseIndex, phase in ipairs(def.phases) do
				if typeof(phase) ~= "table" or typeof(phase.attacks) ~= "table" then
					continue
				end
				for _, attack in ipairs(phase.attacks) do
					if typeof(attack) ~= "table" or typeof(attack.clip) ~= "string" then
						problem("boss %s phase %d has an attack without a clip id", row.key, phaseIndex)
						continue
					end
					local label = ("boss %s phase %d attack %s"):format(
						row.key,
						phaseIndex,
						tostring(attack.id or attack.name or "?")
					)
					crossCheckAttack(label, attack, def.skin, "boss attacks", isInScope)
				end
			end
		end
	end

	-- The later-phase backlog, as one line.
	local backlogTotal = 0
	local breakdown = {}
	for _, kind in BACKLOG_KINDS do
		local count = 0
		for _ in backlog[kind] do
			count += 1
		end
		backlogTotal += count
		table.insert(breakdown, ("%d %s"):format(count, kind))
	end
	if backlogTotal > 0 then
		warning(
			"%d clips for later phases are not authored yet (outside the phase %s scope): %s",
			backlogTotal,
			tostring(if scope ~= nil then scope.phase else "?"),
			table.concat(breakdown, ", ")
		)
	end

	for _, line in warnings do
		print("  ~ clips warning: " .. line)
	end
	return problems
end
