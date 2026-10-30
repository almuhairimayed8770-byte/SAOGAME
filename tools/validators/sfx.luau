--!strict
--[[
	SFX validator: every entry has an asset id string, a volume in 0..1, a boolean `spatial`, an
	optional ordered pitchRange inside engine.playbackSpeed, and routes to a declared SoundGroup;
	the section 15 families are present.

	Real sounds and placeholders: an id is rbxassetid://<digits>; placeholder = false exactly when
	the digits are not 0 (a real asset), so a placeholder never claims to be real and a real id is
	never skipped as a placeholder. A real entry names its library title, its creator (one of the
	licensed library's: ProSoundEffects, APMOfficial, Roblox) and the asset's length. The trim, in
	seconds of the asset: startAt is 0 or more, stopAt is after startAt and inside the length,
	fadeOut fits inside startAt..stopAt, a measured peakAt (when set) lies inside the audible part
	(startAt to stopAt, else the length), and a loop has a stopAt, a loop region longer than
	limits.loopMinSeconds and no per-cycle fade. Slots that share one real asset (the reuses) keep
	their pitch ranges at least limits.sharedAssetSemitones apart (no range means the asset's own
	speed, 1), so each reads as its own sound.

	Cues (the reel's layered hits): every required cue is there; each has limits.cueLayers layers
	(1 to 6), a Hit* cue at least limits.hitCueMinLayers; every layer names an entry that resolves,
	starts at 0 or more and under limits.cueDelaySeconds, at 0 or at least
	playback.sameFrameSeconds (a shorter wait would land a whole frame late, so it is not a
	delay the pool can keep), has a gain in limits.layerGainDb that keeps the played volume at
	or under limits.maxPlayVolume, and a pitch (when set) inside engine.playbackSpeed. HitKill carries no sub-bass layer (the bass is cut during the kill's
	impact frames; the slam comes after the freeze).

	Contours (mix automation): every required contour is there; each step names a group in
	effects.groups, starts at 0 or more, ramps 0 or more, ends inside limits.contourSeconds, sets
	at least one of low / mid / high (EqualizerSoundEffect gains, in the engine's range) or wet
	(the ReverbSoundEffect WetLevel, in the engine's range), and eases with a known curve that is
	not Linear or Hold. The effects' idle values are flat and dry, and in the engine's ranges.
	sfx.preload lists entries that resolve (SfxPool loads their voices at start).
	limits.subLayers lists the sub-bass entries (each resolves) and limits.bassBackDb is the low
	band, in dB at or under 0, a sub layer may start over (the moments validator pairs each
	moment's cue with its contour and checks every sub layer starts with the bass back).
	The HP heartbeat (fx.audio.heartbeatLoop) plays mix.heartbeatOverAllDb above its entry's
	volume, and that lifted volume is at or under limits.maxPlayVolume too.
	music.stemIds holds one rbxassetid:// id per music.stems name and nothing else (MusicDirector
	makes a stem's Sound only for a real id).
	The shatter's balance (F15, sfx.shatterBalance): glassGapDb is positive, the glass and bass
	lists name entries that resolve and share none, and every shatter cue (sfx.shatterCues) plays
	at least two glass layers and a bass layer, its glass (the glass layers' summed power) standing
	at least glassGapDb over its loudest bass layer. tests/data/sfx.spec.luau also holds the lift
	against the mix the reel review heard.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local REQUIRED_FAMILIES = {
	"artChime",
	"whoosh",
	"impact",
	"hitStopTick",
	"guard",
	"shatter",
	"footsteps",
	"telegraph",
	"enemy",
	"ui",
	"voice",
	"world",
	"ambience",
}

local REQUIRED_ENTRIES = {
	{ "guard", "Parry" },
	{ "guard", "Block" },
	{ "guard", "GuardBreak" },
	{ "shatter", "Crack" },
	{ "shatter", "BossCrack" },
	{ "telegraph", "Tick" },
	{ "hitStopTick", "Normal" },
	{ "impact", "Flesh" },
	{ "impact", "Armor" },
	{ "impact", "Construct" },
	{ "whoosh", "Small" },
	{ "whoosh", "Medium" },
	{ "whoosh", "Large" },
	{ "ui", "MenuOpen" },
	{ "ui", "MenuClose" },
	{ "voice", "Countdown" },
}

local REQUIRED_CUES = {
	"HitNormal",
	"HitBasic",
	"HitCrit",
	"HitFinal",
	"HitKill",
	"Shatter",
	"BossShatter",
	"Parry",
	"Block",
	"GuardBreak",
	"Dodge",
}

-- The creators of Roblox's licensed sound library: the only sources a real entry may name.
local LICENSED_CREATORS = { ProSoundEffects = true, APMOfficial = true, Roblox = true }

local REQUIRED_CONTOURS = { "FinalHit", "KillCut", "ShatterBloom", "ParryRing", "WindUp", "WindUpRelease" }

-- New layers the reel's stacks need (sfx.luau notes say what each one is).
local REQUIRED_LAYERS = {
	{ "impact", "Crack" },
	{ "impact", "Body" },
	{ "impact", "Sub" },
	{ "impact", "RingTail" },
	{ "impact", "SubDrop" },
	{ "whoosh", "Riser" },
	{ "whoosh", "Dodge" },
	{ "guard", "ParryRing" },
	{ "shatter", "Slam" },
}

-- Sub-bass layers: none may sound in HitKill, whose bass is cut through the impact frames.
local SUB_BASS = { ["impact.Sub"] = true, ["impact.SubDrop"] = true, ["shatter.BossBoom"] = true }
local BASS_CUT_CUES = { "HitKill" }

-- Contour step keys and the engine range each is held to.
local EQ_KEYS = { "low", "mid", "high" }

local ARCHETYPES = {
	"Charger",
	"Brute",
	"Skirmisher",
	"Lancer",
	"Swarm",
	"Guard",
	"CasterBeast",
	"Stalker",
	"WardenConstruct",
}

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end

	local Sfx = ctx.load("src/shared/data/sfx")
	local Palette = ctx.load("src/shared/data/palette")

	local groups: { [string]: boolean } = {}
	for _, name in Sfx.groups do
		groups[name] = true
	end
	for _, name in { "Master", "Music", "SFX", "UI", "Voice" } do
		if not groups[name] then
			problem("sfx.groups is missing the '%s' SoundGroup", name)
		end
	end

	for _, family in REQUIRED_FAMILIES do
		if typeof(Sfx.families[family]) ~= "table" then
			problem("sfx.families is missing '%s'", family)
		end
	end
	for _, pair in REQUIRED_ENTRIES do
		local family = Sfx.families[pair[1]]
		if typeof(family) == "table" and typeof(family.entries[pair[2]]) ~= "table" then
			problem("sfx.families.%s is missing the '%s' entry", pair[1], pair[2])
		end
	end

	-- One chime per trail color and one vocalization set per archetype.
	local chimes = if typeof(Sfx.families.artChime) == "table" then Sfx.families.artChime.entries else {}
	for token in Palette.tokens do
		if token:sub(1, 5) == "Trail" and typeof(chimes[token]) ~= "table" then
			problem("sfx.families.artChime has no chime for trail color '%s'", token)
		end
	end
	local enemy = if typeof(Sfx.families.enemy) == "table" then Sfx.families.enemy.entries else {}
	for _, archetype in ARCHETYPES do
		for _, moment in { "WindUp", "Strike", "Stagger", "Death" } do
			if typeof(enemy[archetype .. moment]) ~= "table" then
				problem("sfx.families.enemy is missing '%s%s'", archetype, moment)
			end
		end
	end

	local function isRange(value: any): boolean
		return typeof(value) == "table" and typeof(value.min) == "number" and typeof(value.max) == "number"
	end
	local function inRange(value: any, range: any): boolean
		return typeof(value) == "number" and value >= range.min and value <= range.max
	end
	local function isPositive(value: any): boolean
		return typeof(value) == "number" and value > 0
	end

	local engine = if typeof(Sfx.engine) == "table" then Sfx.engine else {}
	local limits = if typeof(Sfx.limits) == "table" then Sfx.limits else {}
	for _, key in { "eqGainDb", "reverbLevelDb", "reverbDecaySeconds", "unit", "soundVolume", "playbackSpeed" } do
		if not isRange(engine[key]) then
			problem("sfx.engine.%s must be a {min, max} range", key)
		end
	end
	-- A usable PlaybackSpeed range is positive and holds 1 (the asset's own speed); the pitch
	-- checks below measure against it only then, so one bad range is one problem.
	local speedOk = isRange(engine.playbackSpeed)
		and engine.playbackSpeed.min > 0
		and engine.playbackSpeed.min <= 1
		and engine.playbackSpeed.max >= 1
	if isRange(engine.playbackSpeed) and not speedOk then
		problem("sfx.engine.playbackSpeed must be positive and hold 1 (the asset's own speed)")
	end
	for _, key in { "cueLayers", "layerGainDb" } do
		if not isRange(limits[key]) then
			problem("sfx.limits.%s must be a {min, max} range", key)
		end
	end
	for _, key in { "hitCueMinLayers", "cueDelaySeconds", "contourSeconds" } do
		if typeof(limits[key]) ~= "number" then
			problem("sfx.limits.%s must be a number", key)
		end
	end
	if not isPositive(limits.maxPlayVolume) then
		problem("sfx.limits.maxPlayVolume must be a positive volume")
	elseif isRange(engine.soundVolume) and limits.maxPlayVolume > engine.soundVolume.max then
		problem("sfx.limits.maxPlayVolume must be inside the engine's Sound.Volume range")
	end
	if not isPositive(limits.loopMinSeconds) then
		problem("sfx.limits.loopMinSeconds must be a positive number of seconds")
	end
	local playback = if typeof(Sfx.playback) == "table" then Sfx.playback else {}
	if not isPositive(playback.openEndSeconds) then
		problem("sfx.playback.openEndSeconds must be a positive number of seconds")
	end
	if not isPositive(playback.sameFrameSeconds) then
		problem("sfx.playback.sameFrameSeconds must be a positive number of seconds (one frame)")
	end
	local sameFrame: number? = if isPositive(playback.sameFrameSeconds) then playback.sameFrameSeconds else nil
	if not isPositive(limits.sharedAssetSemitones) then
		problem("sfx.limits.sharedAssetSemitones must be a positive number of semitones")
	end
	local rangesOk = isRange(engine.eqGainDb)
		and isRange(engine.reverbLevelDb)
		and isRange(engine.reverbDecaySeconds)
		and isRange(engine.unit)
		and isRange(engine.soundVolume)
		and speedOk
		and isRange(limits.cueLayers)
		and isRange(limits.layerGainDb)
		and typeof(limits.hitCueMinLayers) == "number"
		and typeof(limits.cueDelaySeconds) == "number"
		and typeof(limits.contourSeconds) == "number"
		and isPositive(limits.maxPlayVolume)
	local speedRange = if speedOk then engine.playbackSpeed else nil

	-- The asset id's digits are not 0: a sound from the library.
	local function isRealId(id: any): boolean
		if typeof(id) ~= "string" then
			return false
		end
		local digits = string.match(id :: string, "^rbxassetid://(%d+)$")
		return digits ~= nil and tonumber(digits) ~= 0
	end

	-- The trim (seconds of the asset): startAt, stopAt, fadeOut, loop against the listed length.
	local function checkTrim(label: string, entry: any)
		local start = 0
		if entry.startAt ~= nil then
			if typeof(entry.startAt) ~= "number" or entry.startAt < 0 then
				problem("%s: startAt must be 0 or more seconds", label)
				return
			end
			start = entry.startAt
		end
		local length = entry.length
		if length ~= nil and not isPositive(length) then
			problem("%s: length must be a positive number of seconds", label)
			length = nil
		end
		local stop = entry.stopAt
		if stop ~= nil then
			if typeof(stop) ~= "number" or stop <= start then
				problem("%s: stopAt %s must be after startAt %s", label, tostring(stop), tostring(start))
				return
			end
			if length ~= nil and stop > length then
				problem("%s: stopAt %s is past the asset's length %s", label, tostring(stop), tostring(length))
			end
		elseif length ~= nil and length <= start then
			problem("%s: startAt %s is past the asset's length %s", label, tostring(start), tostring(length))
			return
		end
		local finish = stop or length
		if entry.fadeOut ~= nil then
			if typeof(entry.fadeOut) ~= "number" or entry.fadeOut < 0 then
				problem("%s: fadeOut must be 0 or more seconds", label)
			elseif entry.fadeOut > 0 and finish == nil then
				problem("%s: fadeOut needs a stopAt or a length to end at", label)
			elseif finish ~= nil and entry.fadeOut > finish - start then
				problem(
					"%s: fadeOut %s is longer than the audible part (%s to %s)",
					label,
					tostring(entry.fadeOut),
					tostring(start),
					tostring(finish)
				)
			end
		end
		if entry.peakAt ~= nil then
			if typeof(entry.peakAt) ~= "number" then
				problem("%s: peakAt must be seconds of the asset", label)
			elseif entry.peakAt < start or (finish ~= nil and entry.peakAt > finish) then
				problem(
					"%s: peakAt %s must lie in the audible part (%s to %s)",
					label,
					tostring(entry.peakAt),
					tostring(start),
					tostring(finish or "the end")
				)
			end
		end
		if entry.loop ~= nil and typeof(entry.loop) ~= "boolean" then
			problem("%s: loop must be a boolean", label)
		elseif entry.loop == true then
			if stop == nil then
				problem("%s: a loop needs a stopAt (its LoopRegion is startAt..stopAt)", label)
			elseif isPositive(limits.loopMinSeconds) and stop - start <= limits.loopMinSeconds then
				problem(
					"%s: the loop region %s..%s must be longer than %s s",
					label,
					tostring(start),
					tostring(stop),
					tostring(limits.loopMinSeconds)
				)
			end
			if typeof(entry.fadeOut) == "number" and entry.fadeOut > 0 then
				problem("%s: a loop has no fadeOut (it would dip every cycle); its stop fade is the caller's", label)
			end
		end
	end

	for family, group in Sfx.families do
		if typeof(group.group) ~= "string" or not groups[group.group] then
			problem("sfx.families.%s routes to unknown SoundGroup '%s'", family, tostring(group.group))
		end
		if typeof(group.entries) ~= "table" or next(group.entries) == nil then
			problem("sfx.families.%s has no entries", family)
			continue
		end
		for name, entry in group.entries do
			local label = ("sfx.families.%s.%s"):format(family, name)
			local wellFormed = typeof(entry.id) == "string" and entry.id:match("^rbxassetid://%d+$") ~= nil
			if not wellFormed then
				problem("%s: id must be an rbxassetid:// string", label)
			end
			if typeof(entry.volume) ~= "number" or entry.volume < 0 or entry.volume > 1 then
				problem("%s: volume must be a number in 0..1", label)
			end
			if typeof(entry.spatial) ~= "boolean" then
				problem("%s: spatial must be a boolean", label)
			end
			local real = isRealId(entry.id)
			if typeof(entry.placeholder) ~= "boolean" then
				problem("%s: placeholder must be a boolean", label)
			elseif wellFormed and not real and not entry.placeholder then
				problem("%s: a 0 asset id must be marked placeholder = true", label)
			elseif real and entry.placeholder then
				problem("%s: a real asset id must be marked placeholder = false", label)
			end
			if real then
				if typeof(entry.title) ~= "string" or entry.title == "" then
					problem("%s: a real sound needs its library title", label)
				end
				if typeof(entry.creator) ~= "string" or not LICENSED_CREATORS[entry.creator] then
					problem(
						"%s: creator '%s' must be ProSoundEffects, APMOfficial or Roblox (the licensed library)",
						label,
						tostring(entry.creator)
					)
				end
				if entry.length == nil then
					problem("%s: a real sound needs the asset's length as the library lists it", label)
				end
			end
			if entry.pitchRange ~= nil then
				local range = entry.pitchRange
				if typeof(range) ~= "table" or typeof(range[1]) ~= "number" or typeof(range[2]) ~= "number" then
					problem("%s: pitchRange must be {min, max}", label)
				elseif range[1] <= 0 or range[1] > range[2] then
					problem("%s: pitchRange must be positive and ordered", label)
				elseif speedRange ~= nil and (range[1] < speedRange.min or range[2] > speedRange.max) then
					problem(
						"%s: pitchRange %s..%s is outside the PlaybackSpeed range %s..%s",
						label,
						tostring(range[1]),
						tostring(range[2]),
						tostring(speedRange.min),
						tostring(speedRange.max)
					)
				end
			end
			checkTrim(label, entry)
		end
	end

	-- Slots on one real asset: each pair's pitch ranges at least limits.sharedAssetSemitones apart.
	if speedOk and isPositive(limits.sharedAssetSemitones) then
		type Slot = { label: string, low: number, high: number }
		local byId: { [string]: { Slot } } = {}
		for family, group in Sfx.families do
			if typeof(group.entries) ~= "table" then
				continue
			end
			for name, entry in group.entries do
				if not isRealId(entry.id) then
					continue
				end
				local range = entry.pitchRange
				local low, high = 1, 1
				if typeof(range) == "table" and typeof(range[1]) == "number" and typeof(range[2]) == "number" then
					low, high = range[1], range[2]
				end
				local list = byId[entry.id] or {}
				byId[entry.id] = list
				table.insert(list, { label = ("%s.%s"):format(family, name), low = low, high = high })
			end
		end
		local apart = 2 ^ (limits.sharedAssetSemitones / 12)
		local ids: { string } = {}
		for id in byId do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			local list = byId[id]
			table.sort(list, function(a: Slot, b: Slot): boolean
				return a.label < b.label
			end)
			for first = 1, #list do
				for second = first + 1, #list do
					local a, b = list[first], list[second]
					local ratio = math.max(a.low / b.high, b.low / a.high)
					if ratio < apart then
						problem(
							"sfx.families.%s and %s share %s: their pitch ranges %s..%s and %s..%s must be %s semitone(s) apart",
							a.label,
							b.label,
							id,
							tostring(a.low),
							tostring(a.high),
							tostring(b.low),
							tostring(b.high),
							tostring(limits.sharedAssetSemitones)
						)
					end
				end
			end
		end
	end

	for _, pair in REQUIRED_LAYERS do
		local family = Sfx.families[pair[1]]
		if typeof(family) == "table" and typeof(family.entries) == "table" then
			local entry = family.entries[pair[2]]
			if typeof(entry) ~= "table" then
				problem("sfx.families.%s is missing the '%s' layer", pair[1], pair[2])
			elseif typeof(entry.note) ~= "string" or entry.note == "" then
				problem("sfx.families.%s.%s needs a note saying what the layer is", pair[1], pair[2])
			end
		end
	end

	-- Resolves "family.Name" the way SfxPool does; returns the entry or nil.
	local function resolve(name: any): any
		if typeof(name) ~= "string" then
			return nil
		end
		local family, entryName = string.match(name :: string, "^([^%.]+)%.(.+)$")
		if family == nil then
			return nil
		end
		local group = Sfx.families[family]
		if typeof(group) ~= "table" or typeof(group.entries) ~= "table" then
			return nil
		end
		return group.entries[entryName]
	end

	-- The entries SfxPool preloads (the risers): a list of real names.
	if typeof(Sfx.preload) ~= "table" then
		problem("sfx.preload must list the entries SfxPool preloads ('family.Name')")
	else
		for index, name in Sfx.preload do
			if resolve(name) == nil then
				problem("sfx.preload[%d] '%s' is not a sfx.luau 'family.Name'", index, tostring(name))
			end
		end
	end

	-- The sub-bass layers and how far back the bass must be when one starts.
	if typeof(limits.subLayers) ~= "table" or #limits.subLayers == 0 then
		problem("sfx.limits.subLayers must list the sub-bass entries ('family.Name')")
	else
		for index, name in limits.subLayers do
			if resolve(name) == nil then
				problem("sfx.limits.subLayers[%d] '%s' is not a sfx.luau 'family.Name'", index, tostring(name))
			end
		end
	end
	if
		typeof(limits.bassBackDb) ~= "number"
		or limits.bassBackDb > 0
		or (isRange(engine.eqGainDb) and limits.bassBackDb < engine.eqGainDb.min)
	then
		problem("sfx.limits.bassBackDb must be a gain in dB at or under 0, in the EQ's range")
	end

	-- Cues
	local cues = Sfx.cues
	if typeof(cues) ~= "table" then
		problem("sfx.cues must be a table of layered cues")
		cues = {}
	end
	for _, name in REQUIRED_CUES do
		if typeof(cues[name]) ~= "table" then
			problem("sfx.cues is missing '%s'", name)
		end
	end
	if rangesOk then
		local cueNames = {}
		for name in cues do
			table.insert(cueNames, name)
		end
		table.sort(cueNames)
		for _, cueName in cueNames do
			local layers = cues[cueName]
			local label = ("sfx.cues.%s"):format(tostring(cueName))
			if typeof(layers) ~= "table" then
				problem("%s must be a list of layers", label)
				continue
			end
			local count = #layers
			if count < limits.cueLayers.min or count > limits.cueLayers.max then
				problem(
					"%s has %d layers (a cue has %d to %d)",
					label,
					count,
					limits.cueLayers.min,
					limits.cueLayers.max
				)
			end
			if tostring(cueName):sub(1, 3) == "Hit" and count < limits.hitCueMinLayers then
				problem(
					"%s has %d layers; a hit is a stack of at least %d (crack, body, ring)",
					label,
					count,
					limits.hitCueMinLayers
				)
			end
			for index, layer in layers do
				local layerLabel = ("%s layer %s"):format(label, tostring(index))
				if typeof(layer) ~= "table" then
					problem("%s must be {name, delay, gainDb}", layerLabel)
					continue
				end
				local entry = resolve(layer.name)
				if entry == nil then
					problem("%s sound '%s' is not a sfx.luau 'family.Name'", layerLabel, tostring(layer.name))
				end
				if typeof(layer.delay) ~= "number" or layer.delay < 0 or layer.delay >= limits.cueDelaySeconds then
					problem(
						"%s delay %s must be 0 or more and under %s s",
						layerLabel,
						tostring(layer.delay),
						tostring(limits.cueDelaySeconds)
					)
				elseif sameFrame ~= nil and layer.delay > 0 and layer.delay < sameFrame then
					problem(
						"%s delay %s is under one frame (%s s): it plays with the cue, so make it 0 or at least a frame",
						layerLabel,
						tostring(layer.delay),
						tostring(sameFrame)
					)
				end
				if not inRange(layer.gainDb, limits.layerGainDb) then
					problem(
						"%s gainDb %s must be in %s..%s dB",
						layerLabel,
						tostring(layer.gainDb),
						tostring(limits.layerGainDb.min),
						tostring(limits.layerGainDb.max)
					)
				elseif typeof(entry) == "table" and typeof(entry.volume) == "number" then
					-- The pool's one rule: a play's volume is the entry's volume x 10^(gainDb / 20).
					local volume = entry.volume * 10 ^ (layer.gainDb / 20)
					if volume > limits.maxPlayVolume then
						problem(
							"%s plays at volume %.2f, over limits.maxPlayVolume %s",
							layerLabel,
							volume,
							tostring(limits.maxPlayVolume)
						)
					end
				end
				if layer.pitch ~= nil and not inRange(layer.pitch, engine.playbackSpeed) then
					problem(
						"%s pitch %s must be a PlaybackSpeed in %s..%s",
						layerLabel,
						tostring(layer.pitch),
						tostring(engine.playbackSpeed.min),
						tostring(engine.playbackSpeed.max)
					)
				end
			end
		end
		for _, cueName in BASS_CUT_CUES do
			local layers = cues[cueName]
			if typeof(layers) == "table" then
				for _, layer in layers do
					if typeof(layer) == "table" and SUB_BASS[layer.name] then
						problem(
							"sfx.cues.%s carries the sub-bass layer '%s'; the bass is cut during the kill's impact frames",
							cueName,
							tostring(layer.name)
						)
					end
				end
			end
		end
	end

	-- Effects and contours
	local effects = if typeof(Sfx.effects) == "table" then Sfx.effects else {}
	local contourGroups: { [string]: boolean } = {}
	if typeof(effects.groups) ~= "table" then
		problem("sfx.effects.groups must list the SoundGroups a contour may name")
	else
		for _, name in effects.groups do
			if not groups[name] then
				problem("sfx.effects.groups names '%s', which is not in sfx.groups", tostring(name))
			end
			contourGroups[name] = true
		end
	end
	local Easing = ctx.load("src/shared/util/Easing")
	local function easingProblem(label: string, name: any)
		if typeof(name) ~= "string" or not pcall(Easing.get, name) then
			problem("%s easing '%s' is not a known curve", label, tostring(name))
		elseif name == "Linear" or name == "Hold" then
			problem("%s easing '%s' must ease (never linear or a jump)", label, name)
		end
	end
	easingProblem("sfx.effects", effects.easing)
	if typeof(effects.restoreSeconds) ~= "number" or effects.restoreSeconds <= 0 then
		problem("sfx.effects.restoreSeconds must be a positive number")
	end
	local eq = if typeof(effects.equalizer) == "table" then effects.equalizer else nil
	local reverb = if typeof(effects.reverb) == "table" then effects.reverb else nil
	if eq == nil or reverb == nil then
		problem("sfx.effects needs an equalizer and a reverb")
	elseif rangesOk then
		for _, key in EQ_KEYS do
			if eq[key] ~= 0 then
				problem("sfx.effects.equalizer.%s must be 0 (flat while no contour runs)", key)
			end
		end
		if reverb.wet ~= engine.reverbLevelDb.min then
			problem(
				"sfx.effects.reverb.wet must be %s dB (dry while no contour runs)",
				tostring(engine.reverbLevelDb.min)
			)
		end
		if not inRange(reverb.dry, engine.reverbLevelDb) then
			problem("sfx.effects.reverb.dry must be in the engine's DryLevel range")
		end
		if not inRange(reverb.decayTime, engine.reverbDecaySeconds) then
			problem("sfx.effects.reverb.decayTime must be in the engine's DecayTime range")
		end
		for _, key in { "density", "diffusion" } do
			if not inRange(reverb[key], engine.unit) then
				problem("sfx.effects.reverb.%s must be in 0..1", key)
			end
		end
	end

	local contours = Sfx.contours
	if typeof(contours) ~= "table" then
		problem("sfx.contours must be a table of mix automation")
		contours = {}
	end
	for _, name in REQUIRED_CONTOURS do
		if typeof(contours[name]) ~= "table" then
			problem("sfx.contours is missing '%s'", name)
		end
	end
	if rangesOk then
		local contourNames = {}
		for name in contours do
			table.insert(contourNames, name)
		end
		table.sort(contourNames)
		for _, contourName in contourNames do
			local steps = contours[contourName]
			local label = ("sfx.contours.%s"):format(tostring(contourName))
			if typeof(steps) ~= "table" or #steps == 0 then
				problem("%s must be a non-empty list of steps", label)
				continue
			end
			for index, step in steps do
				local stepLabel = ("%s step %s"):format(label, tostring(index))
				if typeof(step) ~= "table" then
					problem("%s must be {at, group, ramp, low / mid / high / wet}", stepLabel)
					continue
				end
				if not contourGroups[step.group] then
					problem("%s group '%s' is not in sfx.effects.groups", stepLabel, tostring(step.group))
				end
				local timed = true
				if typeof(step.at) ~= "number" or step.at < 0 then
					problem("%s at must be 0 or more seconds", stepLabel)
					timed = false
				end
				if typeof(step.ramp) ~= "number" or step.ramp < 0 then
					problem("%s ramp must be 0 or more seconds", stepLabel)
					timed = false
				end
				if timed and step.at + step.ramp > limits.contourSeconds then
					problem(
						"%s ends at %.2f s, past the %s s a contour may run",
						stepLabel,
						step.at + step.ramp,
						tostring(limits.contourSeconds)
					)
				end
				local sets = 0
				for _, key in EQ_KEYS do
					if step[key] ~= nil then
						sets += 1
						if not inRange(step[key], engine.eqGainDb) then
							problem(
								"%s %s %s dB is outside the EQ gain range %s..%s",
								stepLabel,
								key,
								tostring(step[key]),
								tostring(engine.eqGainDb.min),
								tostring(engine.eqGainDb.max)
							)
						end
					end
				end
				if step.wet ~= nil then
					sets += 1
					if not inRange(step.wet, engine.reverbLevelDb) then
						problem(
							"%s wet %s dB is outside the reverb WetLevel range %s..%s",
							stepLabel,
							tostring(step.wet),
							tostring(engine.reverbLevelDb.min),
							tostring(engine.reverbLevelDb.max)
						)
					end
				end
				if sets == 0 then
					problem("%s sets nothing (low, mid, high or wet)", stepLabel)
				end
				if step.easing ~= nil then
					easingProblem(stepLabel, step.easing)
				end
			end
		end
	end

	-- What SfxPool.shatter plays, by the caller's weight.
	local shatterCues = if typeof(Sfx.shatterCues) == "table" then Sfx.shatterCues else {}
	for _, kind in { "normal", "heavy", "boss" } do
		local cueName = shatterCues[kind]
		if typeof(cueName) ~= "string" then
			problem("sfx.shatterCues.%s must name the cue SfxPool.shatter plays", kind)
		elseif typeof(cues[cueName]) ~= "table" then
			problem("sfx.shatterCues.%s '%s' is not in sfx.cues", kind, cueName)
		end
	end

	-- The shatter's balance (F15): glass and bass layers that resolve and never overlap, a positive
	-- gap, and every shatter cue with its glass doubled and leading its loudest bass layer by the gap
	-- (each layer's played amplitude: entry volume x 10^(gainDb / 20); the glass summed in power).
	local balance = Sfx.shatterBalance
	if typeof(balance) ~= "table" then
		problem("sfx.shatterBalance must hold glassGapDb and the glass and bass layer lists")
	else
		local gapOk = typeof(balance.glassGapDb) == "number" and balance.glassGapDb > 0
		if not gapOk then
			problem("sfx.shatterBalance.glassGapDb must be a positive number of dB")
		end
		local listsOk = true
		for _, key in { "glass", "bass" } do
			local list = balance[key]
			if typeof(list) ~= "table" or #list == 0 then
				problem("sfx.shatterBalance.%s must list at least one 'family.Name'", key)
				listsOk = false
				continue
			end
			for index, name in list do
				if typeof(resolve(name)) ~= "table" then
					problem(
						"sfx.shatterBalance.%s[%d] '%s' is not a sfx.luau 'family.Name'",
						key,
						index,
						tostring(name)
					)
					listsOk = false
				end
			end
		end
		if listsOk then
			for _, name in balance.glass do
				if table.find(balance.bass, name) ~= nil then
					problem("sfx.shatterBalance names '%s' both glass and bass", tostring(name))
					listsOk = false
				end
			end
		end
		if listsOk then
			for _, kind in { "normal", "heavy", "boss" } do
				local cueName = shatterCues[kind]
				local layers = if typeof(cueName) == "string" then cues[cueName] else nil
				if typeof(layers) ~= "table" then
					continue -- reported above
				end
				local glassCount, glassPower, bassPeak = 0, 0, 0
				for _, layer in layers do
					local entry = if typeof(layer) == "table" then resolve(layer.name) else nil
					if
						typeof(entry) ~= "table"
						or typeof(entry.volume) ~= "number"
						or typeof(layer.gainDb) ~= "number"
					then
						continue -- the cue checks report it
					end
					local amplitude = entry.volume * 10 ^ (layer.gainDb / 20)
					if table.find(balance.glass, layer.name) ~= nil then
						glassCount += 1
						glassPower += amplitude * amplitude
					elseif table.find(balance.bass, layer.name) ~= nil then
						bassPeak = math.max(bassPeak, amplitude)
					end
				end
				if glassCount < 2 then
					problem(
						"sfx.cues.%s (shatterCues.%s) must play at least two glass layers (sfx.shatterBalance.glass); it plays %d",
						cueName,
						kind,
						glassCount
					)
				end
				if bassPeak <= 0 then
					problem(
						"sfx.cues.%s (shatterCues.%s) must play a bass layer (sfx.shatterBalance.bass)",
						cueName,
						kind
					)
				elseif gapOk and glassPower > 0 then
					local over = 10 * math.log10(glassPower) - 20 * math.log10(bassPeak)
					if over < balance.glassGapDb then
						problem(
							"sfx.cues.%s (shatterCues.%s): its glass stands %.2f dB over its loudest bass layer, under shatterBalance.glassGapDb (%s dB)",
							cueName,
							kind,
							over,
							tostring(balance.glassGapDb)
						)
					end
				end
			end
		end
	end

	-- The floor's music stems: one id per stem, each an rbxassetid:// string (0 while a placeholder).
	local music = if typeof(Sfx.music) == "table" then Sfx.music else {}
	local stemNames = if typeof(music.stems) == "table" then music.stems else {}
	local stemIds = music.stemIds
	if typeof(stemIds) ~= "table" then
		problem("sfx.music.stemIds must hold one asset id per stem")
	else
		local isStem: { [string]: boolean } = {}
		for _, name in stemNames do
			isStem[name] = true
			if stemIds[name] == nil then
				problem("sfx.music.stemIds is missing the '%s' stem", tostring(name))
			end
		end
		local named = {}
		for name in stemIds do
			table.insert(named, tostring(name))
		end
		table.sort(named)
		for _, name in named do
			local id = stemIds[name]
			if not isStem[name] then
				problem("sfx.music.stemIds.%s is not a stem in music.stems", name)
			elseif typeof(id) ~= "string" or id:match("^rbxassetid://%d+$") == nil then
				problem("sfx.music.stemIds.%s must be an rbxassetid:// string", name)
			end
		end
	end

	if typeof(Sfx.mix) ~= "table" or typeof(Sfx.mix.systemVoiceDuckDb) ~= "number" then
		problem("sfx.mix must hold the section 15 mix rules")
	elseif Sfx.mix.systemVoiceDuckDb ~= 8 or Sfx.mix.mobileMusicOffsetDb ~= -2 then
		problem("sfx.mix: the system voice ducks by 8 dB and mobile music sits 2 dB lower")
	end

	-- The HP heartbeat plays above the mix: its lifted volume still stays at or under the ceiling.
	local Fx = ctx.load("src/shared/data/fx")
	local audio = if typeof(Fx) == "table" and typeof(Fx.audio) == "table" then Fx.audio else {}
	local heartbeat = resolve(audio.heartbeatLoop)
	local lift = if typeof(Sfx.mix) == "table" then Sfx.mix.heartbeatOverAllDb else nil
	if typeof(heartbeat) ~= "table" then
		problem("fx.audio.heartbeatLoop '%s' is not a sfx.luau 'family.Name'", tostring(audio.heartbeatLoop))
	elseif typeof(lift) ~= "number" then
		problem("sfx.mix.heartbeatOverAllDb must be a number of dB")
	elseif typeof(heartbeat.volume) == "number" and isPositive(limits.maxPlayVolume) then
		local lifted = heartbeat.volume * 10 ^ (lift / 20)
		if lifted > limits.maxPlayVolume then
			problem(
				"%s plays at volume %.2f with the heartbeat's +%s dB, over limits.maxPlayVolume %s",
				tostring(audio.heartbeatLoop),
				lifted,
				tostring(lift),
				tostring(limits.maxPlayVolume)
			)
		end
	end

	return problems
end
