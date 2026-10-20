--!strict
--[[
	SfxPool (section 15): pooled Sounds for every entry in sfx.luau, by "family.Name".

	`start()` creates the SoundGroups (Master with Music / SFX / UI / Voice under it) with the
	mix rules from sfx.luau and fx.luau. `play(name, position?)` takes a pooled Sound for the
	entry, pitches it inside its range, and plays it either in 3D (parented to a pooled anchored
	part at the position, roll-off from the data) or in 2D under SoundService. The same sound at
	the same spot inside the dedupe window plays once, so a hit heard through two reactions does
	not double (a 2D sound is heard everywhere, so it dedupes by name alone). Placeholder entries
	(rbxassetid://0) go through the whole path but never call Play, so the console is not filled
	with load failures until the real ids arrive.

	Trims (sfx.luau Entry startAt / stopAt / fadeOut / loop / length, seconds of the asset before
	PlaybackSpeed). A trimmed entry plays with PlaybackRegionsEnabled and PlaybackRegion =
	startAt .. (stopAt, else the library length, else sfx.playback.openEndSeconds); an untrimmed
	one with no region, as before. Every play sets TimePosition itself (startAt, or a riser's
	computed point), because Play starts from the last TimePosition a script set. A fadeOut ramps
	the Sound's Volume linearly from the play's volume to 0, ending at stopAt in real time: it
	starts (stopAt - fadeOut - TimePosition) / PlaybackSpeed seconds after Play and lasts
	fadeOut / PlaybackSpeed, on the pool's per-frame step. A trimmed play's real-time length is
	(stopAt - TimePosition) / PlaybackSpeed: its voice is free once that has passed, whether or not
	the engine fired Ended or still reports IsPlaying there, and it never listens to Ended (an
	Ended that arrives late for an earlier play must not free a newer one). Only an untrimmed play,
	or a play whose asset has not loaded yet (Play then starts whenever the asset arrives, so no
	clock is known: no Lua fade, a hard stop at the region end), waits on Ended through the seam,
	one connection per voice, dropped when the voice plays again. Every play of a pooled voice
	resets its Volume, PlaybackSpeed, regions, Looped and any fade still running from an earlier
	play. No play ends above sfx.limits.maxPlayVolume, the heartbeat's lift included.

	The reel's sound on top (sfx.luau `cues`, `contours`, `effects`):
	- `cue(name, position?)` plays a layered recipe: every layer goes through the same play path
	  (dedupe, placeholders, trims, 3D or 2D per entry) at its delay, at entry.volume x
	  10^(gainDb / 20) for that play (the entry's base volume never changes; a fade starts from it),
	  and at the layer's pitch when it names one (else the entry's random pick); every PlaybackSpeed
	  stays inside sfx.engine.playbackSpeed. A layer whose delay is under
	  sfx.playback.sameFrameSeconds plays on the cue's own call: task.delay resumes a thread once
	  per frame, so a few-ms wait would land a whole frame (17 to 33 ms) after the crack.
	- `contour(name)` runs mix automation: eased ramps of the EQ bands and the reverb wet level on
	  the SoundGroups in `effects.groups`. `start()` gives each of those groups one
	  EqualizerSoundEffect and one ReverbSoundEffect, flat, dry and disabled while no contour
	  runs. Each run owns the keys (low / mid / high / wet) its steps name on each group; a new
	  contour takes over only the keys it names there, and the older run keeps the rest (a
	  bystander's reverb bloom never ends the local player's bass cut). A run whose keys are all
	  taken stops; a run that has fired its last step eases the keys it still owns back to the
	  defaults.
	- `playEndingAt(name, seconds, position?)` lands the end of the audible region (stopAt, else
	  the loaded TimeLength) `seconds` from now: a riser that ends on the hit. It starts at
	  TimePosition = end - seconds x PlaybackSpeed when that is at or after startAt, else at
	  startAt after a wait of seconds - (end - startAt) / PlaybackSpeed. A sound whose asset has
	  not loaded yet is skipped, never played out of time, and asked to load for the next one. A
	  riser whose hit is now or already past (seconds <= 0) is skipped too.
	- `preload()` (run by `start()`) creates the voices of every combat sound and asks the engine
	  to load them, so the first hit of a session is not silent: sfx.preload, every cue's layers,
	  and the families the hit, tick and parry helpers play from (`preloadNames()`). Loop beds
	  (ambience, the heartbeat) are not pooled and never preloaded here.

	Helpers: `hit(tier, position, surface)` (impact plus the metallic ring), `hitStopTick(tier)`,
	`parry(position)`, `shatter(position, boss)` (the Shatter / BossShatter cue; the reverb bloom
	is the impact director's), `footstep(model, surface?, weight?)` (surface from the Humanoid's
	FloorMaterial when the clip event carries none), `loop(name, gain)` for the heartbeat and the
	ambience beds (Looped over startAt .. stopAt; the caller's gain ramp is the fade, and stopping
	resets Looped and the regions), `duck(db, seconds)` for the system voice.

	Engine seams (`bind`): the clock, the scheduler behind every delay, the per-frame step the
	contours and fades ramp on, Sound:Play, Sound:Stop, IsPlaying, Sound.Ended, the loaded-length
	read and the asset preload. Specs hand in fakes and drive time by hand; the defaults are the
	package clock, task.delay, Heartbeat and the engine calls (ContentProvider:PreloadAsync on its
	own thread).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Sfx = require(Shared.data.sfx)
local Easing = require(Shared.util.Easing)
local Engine = require(script.Parent.Parent.fx.Engine)
local MusicState = require(script.Parent.MusicState)

export type StepFn = (dt: number) -> ()

export type Deps = {
	now: () -> number, -- monotonic seconds (dedupe, voices, contours, fades)
	delay: (seconds: number, fn: () -> ()) -> (), -- every delayed layer, start, voice release and restore
	onStep: (fn: StepFn) -> () -> (), -- the per-frame step contours and fades ramp on; returns its disconnect
	play: (sound: Sound) -> boolean, -- Sound:Play; false when the engine refused it
	stop: (sound: Sound) -> (), -- Sound:Stop (a stolen voice, a loop let go)
	isPlaying: (sound: Sound) -> boolean, -- Sound.IsPlaying (only an untimed play waits on it)
	-- Sound.Ended:Once(fn) for an untimed play; returns its disconnect, nil when the Sound has none
	onEnded: (sound: Sound, fn: () -> ()) -> (() -> ())?,
	timeLength: (sound: Sound) -> number, -- the loaded length in seconds, 0 while not loaded
	preload: (sounds: { Instance }) -> (), -- asks the engine to load these sounds' assets
}

export type Overrides = {
	now: (() -> number)?,
	delay: ((seconds: number, fn: () -> ()) -> ())?,
	onStep: ((fn: StepFn) -> () -> ())?,
	play: ((sound: Sound) -> boolean)?,
	stop: ((sound: Sound) -> ())?,
	isPlaying: ((sound: Sound) -> boolean)?,
	onEnded: ((sound: Sound, fn: () -> ()) -> (() -> ())?)?,
	timeLength: ((sound: Sound) -> number)?,
	preload: ((sounds: { Instance }) -> ())?,
}

export type MixState = {
	low: number,
	mid: number,
	high: number,
	wet: number,
	enabled: boolean,
	running: string?, -- the newest contour running on the group, nil when none
	owners: { [string]: string }, -- key -> the contour that owns it there
}

type Voice = {
	sound: Sound,
	busyUntil: number, -- held until this time (and until its emitter is back)
	emitter: BasePart?,
	serial: number, -- bumped on every play and steal, so a late callback or fade from an earlier play does nothing
	startedAt: number, -- when its current play starts: the stealing order (longest playing first)
	timed: boolean, -- the current play ends at a known time (a stopAt), so IsPlaying is never asked
	ended: (() -> ())?, -- disconnects the Ended handler of the current untimed play
	defaultRegion: NumberRange, -- the Sound's own PlaybackRegion when made: the untrimmed reset
	defaultLoopRegion: NumberRange,
}

type Loop = {
	voice: Voice,
	entry: Sfx.Entry,
	playing: boolean,
}

-- A fade to silence on one play: linear from `from` at `startsAt` to 0 at `endsAt` (real seconds).
type Fade = {
	voice: Voice,
	serial: number,
	from: number,
	startsAt: number,
	endsAt: number,
}

type Tween = { from: number, to: number, start: number, duration: number, ease: (number) -> number }

-- One contour running on one group: its steps there and the keys it still owns.
type Run = {
	name: string,
	started: number,
	steps: { Sfx.ContourStep },
	nextIndex: number,
	keys: { [string]: boolean },
}

type Mix = {
	equalizer: EqualizerSoundEffect,
	reverb: ReverbSoundEffect,
	values: { [string]: number }, -- "low" / "mid" / "high" / "wet" as last written
	tweens: { [string]: Tween },
	runs: { Run }, -- oldest first
	enabled: boolean,
}

-- The contour keys: the three EQ bands and the reverb wet level.
local MIX_KEYS = { "low", "mid", "high", "wet" }

-- The families the hit, hitStopTick and parry helpers play from (a hit's surface names any impact
-- entry); preload() loads them with sfx.preload and every cue's layers.
local HELPER_FAMILIES = { "impact", "hitStopTick", "guard" }

local SfxPool = {}

local groups: { [string]: SoundGroup } = {}
local voices: { [string]: { Voice } } = {}
local loops: { [string]: Loop } = {}
local mixes: { [string]: Mix } = {}
local fades: { Fade } = {}
local emitterPool: { BasePart } = {}
local emitterFolder: Instance? = nil
local recent: { { name: string, position: Vector3?, time: number } } = {}
-- Plays asked for, played, deduped, placeholders that never play, risers skipped unloaded, and
-- plays whose asset had not loaded yet (they start when it arrives, untimed and unfaded).
export type Stats = {
	requested: number,
	played: number,
	deduped: number,
	placeholders: number,
	unloaded: number,
	lateStarts: number,
}

local function freshStats(): Stats
	return { requested = 0, played = 0, deduped = 0, placeholders = 0, unloaded = 0, lateStarts = 0 }
end

local stats: Stats = freshStats()
local duckGeneration = 0
local started = false
local pitch = Random.new()
local stepDisconnect: (() -> ())? = nil

--- The loaded length of a Sound in seconds: its TimeLength once the asset has loaded, else 0.
function SfxPool.timeLength(sound: Sound): number
	local ok, length = pcall(function()
		return (sound :: any).TimeLength
	end)
	if ok and typeof(length) == "number" and length > 0 then
		return length
	end
	return 0
end

local function engineIsPlaying(sound: Sound): boolean
	local ok, playing = pcall(function()
		return (sound :: any).IsPlaying
	end)
	return ok and playing == true
end

local function defaultDeps(): Deps
	return {
		now = Engine.now,
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		onStep = Engine.onHeartbeat,
		play = function(sound: Sound): boolean
			return (pcall(function()
				sound:Play()
			end))
		end,
		stop = function(sound: Sound)
			pcall(function()
				sound:Stop()
			end)
		end,
		isPlaying = engineIsPlaying,
		onEnded = function(sound: Sound, fn: () -> ()): (() -> ())?
			local ok, connection = pcall(function(): RBXScriptConnection
				return sound.Ended:Once(function(_soundId: string)
					fn()
				end)
			end)
			if not ok then
				return nil -- a Sound without Ended (the caller falls back to maxSoundLength)
			end
			return function()
				connection:Disconnect()
			end
		end,
		timeLength = SfxPool.timeLength,
		preload = function(sounds: { Instance })
			task.spawn(function()
				pcall(function()
					(game:GetService("ContentProvider") :: any):PreloadAsync(sounds)
				end)
			end)
		end,
	}
end

local deps: Deps = defaultDeps()

local function splitName(name: string): (string, string)
	local family, entryName = name:match("^([^%.]+)%.(.+)$")
	if family == nil or entryName == nil then
		error(("SfxPool: sound name '%s' is not 'family.Name'"):format(tostring(name)))
	end
	return family :: string, entryName :: string
end

local function groupFor(family: string): SoundGroup?
	return groups[Sfx.groupOf(family)]
end

local function ensureEmitterFolder(): Instance
	if emitterFolder == nil then
		emitterFolder = Engine.folder(workspace, Fx.audio.emitterFolderName)
	end
	return emitterFolder :: Instance
end

local function newEmitter(): BasePart
	local part = Instance.new("Part")
	part.Name = "SfxEmitter"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Parent = ensureEmitterFolder()
	return part
end

local function acquireEmitter(): BasePart
	local part = table.remove(emitterPool)
	if part == nil then
		part = newEmitter()
	end
	return part :: BasePart
end

local function releaseEmitter(part: BasePart)
	table.insert(emitterPool, part)
end

local function newSound(entry: Sfx.Entry, family: string, entryName: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = family .. "." .. entryName
	sound.SoundId = entry.id
	sound.Volume = entry.volume
	sound.RollOffMinDistance = Sfx.mix.rolloffMinDistance
	sound.RollOffMaxDistance = Sfx.mix.rolloffMaxDistance
	sound.PlayOnRemove = false
	local group = groupFor(family)
	if group ~= nil then
		sound.SoundGroup = group
	end
	return sound
end

-- A voice for the entry, remembering the Sound's own regions so an untrimmed play can put them back.
local function newVoice(entry: Sfx.Entry, family: string, entryName: string): Voice
	local sound = newSound(entry, family, entryName)
	return {
		sound = sound,
		busyUntil = 0,
		emitter = nil,
		serial = 0,
		startedAt = 0,
		timed = false,
		ended = nil,
		defaultRegion = sound.PlaybackRegion,
		defaultLoopRegion = sound.LoopRegion,
	}
end

local function parentToSoundService(sound: Sound)
	pcall(function()
		sound.Parent = SoundService
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Trims: where an entry's audible part starts and ends, and how a Sound is set up to play it
-- ---------------------------------------------------------------------------------------------

-- True when the entry plays only part of its asset (a PlaybackRegion).
local function isTrimmed(entry: Sfx.Entry): boolean
	return entry.startAt ~= nil or entry.stopAt ~= nil
end

local function startOf(entry: Sfx.Entry): number
	local first = Sfx.region(entry)
	return first
end

-- Where a trimmed entry's PlaybackRegion ends: stopAt, else the library length, else the data's
-- open end (past any asset, so it plays to its own end).
local function regionEndOf(entry: Sfx.Entry): number
	local _, last = Sfx.region(entry)
	return last
end

-- Where the audible part ends, for a fade and a riser: stopAt, else the loaded length, else the
-- library length; nil when none is known.
local function audibleEnd(entry: Sfx.Entry, loaded: number): number?
	if entry.stopAt ~= nil then
		return entry.stopAt
	end
	if loaded > 0 then
		return loaded
	end
	return entry.length
end

-- A NumberRange over two ends in either order (the engine refuses min > max).
local function rangeOf(first: number, last: number): NumberRange
	return NumberRange.new(math.min(first, last), math.max(first, last))
end

-- Every Sound.Volume the pool writes: never above limits.maxPlayVolume (the picks' volumes sit on
-- the 0 dB reference, and a gain or a lift only moves a play inside that scale).
local function clampVolume(volume: number): number
	local range = Sfx.engine.soundVolume
	return math.clamp(volume, range.min, math.min(range.max, Sfx.limits.maxPlayVolume))
end

local function volumeOf(entry: Sfx.Entry, gainDb: number): number
	return clampVolume(entry.volume * Sfx.gainOf(gainDb))
end

-- The PlaybackSpeed of one play: the cue layer's own pitch when it sets one, else a random pick in
-- the entry's range, else 1; held inside the speeds the data may ask for (never 0, which no
-- region length could be divided by).
local function pitchOf(entry: Sfx.Entry, override: number?): number
	local speed = 1
	if override ~= nil then
		speed = override
	elseif entry.pitchRange ~= nil then
		local range = entry.pitchRange :: { number }
		speed = pitch:NextNumber(range[1], range[2])
	end
	local bounds = Sfx.engine.playbackSpeed
	return math.clamp(speed, bounds.min, bounds.max)
end

-- Sets every per-play property a reused voice could carry from an earlier play: the volume, the
-- speed, Looped, and the regions (the entry's trim, or the Sound's defaults when untrimmed).
local function applyPlayback(voice: Voice, entry: Sfx.Entry, volume: number, speed: number, looped: boolean)
	local sound = voice.sound
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.Looped = looped
	if isTrimmed(entry) then
		local region = rangeOf(startOf(entry), regionEndOf(entry))
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = region
		sound.LoopRegion = if looped then region else voice.defaultLoopRegion
	else
		sound.PlaybackRegionsEnabled = false
		sound.PlaybackRegion = voice.defaultRegion
		sound.LoopRegion = voice.defaultLoopRegion
	end
end

-- Back to an untouched Sound: not looped, no regions, from the top.
local function clearPlayback(voice: Voice)
	local sound = voice.sound
	sound.Looped = false
	sound.PlaybackRegionsEnabled = false
	sound.PlaybackRegion = voice.defaultRegion
	sound.LoopRegion = voice.defaultLoopRegion
	sound.TimePosition = 0
end

-- ---------------------------------------------------------------------------------------------
-- Voices
-- ---------------------------------------------------------------------------------------------

-- Lets go of the Ended handler an earlier untimed play left on the voice (one per voice at most).
local function dropEnded(voice: Voice)
	local disconnect = voice.ended
	if disconnect ~= nil then
		voice.ended = nil
		disconnect()
	end
end

-- Free once its play is over and its emitter is back. A trimmed play is over at its region end in
-- real time, whatever the engine says; an untrimmed one also waits for IsPlaying to drop.
local function isFree(voice: Voice, now: number): boolean
	if voice.emitter ~= nil or now < voice.busyUntil then
		return false
	end
	return voice.timed or not deps.isPlaying(voice.sound)
end

local function acquireVoice(name: string, entry: Sfx.Entry, family: string, entryName: string, now: number): Voice
	local list = voices[name]
	if list == nil then
		list = {}
		voices[name] = list
	end
	local oldest: Voice? = nil
	for _, voice in list do
		if isFree(voice, now) then
			return voice
		end
		if oldest == nil or voice.startedAt < (oldest :: Voice).startedAt then
			oldest = voice
		end
	end
	if #list < Sfx.mix.pooledVoicesPerEntry then
		local voice = newVoice(entry, family, entryName)
		table.insert(list, voice)
		return voice
	end
	-- Every voice is busy: steal the one that has been playing longest. Its callbacks and fade die
	-- with the serial.
	local victim = oldest :: Voice
	victim.serial += 1
	dropEnded(victim)
	deps.stop(victim.sound)
	if victim.emitter ~= nil then
		releaseEmitter(victim.emitter :: BasePart)
		victim.emitter = nil
	end
	return victim
end

local function isDuplicate(name: string, position: Vector3?, now: number): boolean
	local window = Fx.audio.dedupeSeconds
	for index = #recent, 1, -1 do
		local item = recent[index]
		if now - item.time > window then
			table.remove(recent, index)
			continue
		end
		if item.name ~= name then
			continue
		end
		if position == nil or item.position == nil then
			if position == nil and item.position == nil then
				return true
			end
		elseif (position - (item.position :: Vector3)).Magnitude <= Fx.audio.dedupeDistance then
			return true
		end
	end
	return false
end

local function applyGroupVolume(name: string, volume: number)
	local group: SoundGroup? = groups[name]
	if group ~= nil then
		group.Volume = volume
	end
end

local function baseGroupVolume(name: string): number
	local base = (Fx.audio.groupVolumes :: { [string]: number })[name] or 1
	if name == "Music" and Engine.isTouch() then
		base *= MusicState.dbToGain(-Sfx.mix.mobileMusicOffsetDb)
	end
	return base
end

-- ---------------------------------------------------------------------------------------------
-- Contours: the EQ and reverb on each contour group, ramped on the pool's own step
-- ---------------------------------------------------------------------------------------------

local function defaultOf(key: string): number
	if key == "wet" then
		return Sfx.effects.reverb.wet
	end
	return (Sfx.effects.equalizer :: any)[key]
end

local function writeValue(mix: Mix, key: string, value: number)
	local range = if key == "wet" then Sfx.engine.reverbLevelDb else Sfx.engine.eqGainDb
	local clamped = math.clamp(value, range.min, range.max)
	mix.values[key] = clamped
	if key == "low" then
		mix.equalizer.LowGain = clamped
	elseif key == "mid" then
		mix.equalizer.MidGain = clamped
	elseif key == "high" then
		mix.equalizer.HighGain = clamped
	else
		mix.reverb.WetLevel = clamped
	end
end

local function setEnabled(mix: Mix, enabled: boolean)
	if mix.enabled == enabled then
		return
	end
	mix.enabled = enabled
	mix.equalizer.Enabled = enabled
	mix.reverb.Enabled = enabled
end

local function newMix(group: SoundGroup): Mix
	local eqData = Sfx.effects.equalizer
	local reverbData = Sfx.effects.reverb
	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.Name = eqData.name
	equalizer.Priority = eqData.priority
	local reverb = Instance.new("ReverbSoundEffect")
	reverb.Name = reverbData.name
	reverb.Priority = reverbData.priority
	reverb.DryLevel = reverbData.dry
	reverb.DecayTime = reverbData.decayTime
	reverb.Density = reverbData.density
	reverb.Diffusion = reverbData.diffusion
	local mix: Mix = { equalizer = equalizer, reverb = reverb, values = {}, tweens = {}, runs = {}, enabled = true }
	for _, key in MIX_KEYS do
		writeValue(mix, key, defaultOf(key))
	end
	setEnabled(mix, false)
	equalizer.Parent = group
	reverb.Parent = group
	return mix
end

-- Where `key` is at `time`: on its running ramp, else its last written value.
local function valueAt(mix: Mix, key: string, time: number): number
	local tween = mix.tweens[key]
	if tween == nil then
		return mix.values[key]
	end
	local t = (time - tween.start) / tween.duration
	if t >= 1 then
		return tween.to
	end
	return tween.from + (tween.to - tween.from) * tween.ease(math.max(t, 0))
end

-- Starts easing `key` to `target` over `ramp` seconds from `startTime`, from wherever it is then
-- (a long frame that fires two steps on one key chains them instead of starting from stale).
local function rampTo(mix: Mix, key: string, target: number, ramp: number, ease: (number) -> number, startTime: number)
	if ramp <= 0 then
		mix.tweens[key] = nil
		writeValue(mix, key, target)
		return
	end
	local from = valueAt(mix, key, startTime)
	mix.tweens[key] = { from = from, to = target, start = startTime, duration = ramp, ease = ease }
end

-- Eases each of `keys` that is off its default (or still moving) back to it.
local function restore(mix: Mix, now: number, keys: { [string]: boolean })
	local ease = Easing.get(Sfx.effects.easing)
	for _, key in MIX_KEYS do
		if not keys[key] then
			continue
		end
		local target = defaultOf(key)
		if mix.values[key] ~= target or mix.tweens[key] ~= nil then
			rampTo(mix, key, target, Sfx.effects.restoreSeconds, ease, now)
		end
	end
end

local function isBusy(mix: Mix): boolean
	return #mix.runs > 0 or next(mix.tweens) ~= nil
end

-- The keys a run's steps name.
local function keysOf(steps: { Sfx.ContourStep }): { [string]: boolean }
	local keys: { [string]: boolean } = {}
	for _, contourStep in steps do
		for _, key in MIX_KEYS do
			if typeof((contourStep :: any)[key]) == "number" then
				keys[key] = true
			end
		end
	end
	return keys
end

-- True while one of the run's keys is still on a ramp.
local function moving(mix: Mix, run: Run): boolean
	for key in run.keys do
		if mix.tweens[key] ~= nil then
			return true
		end
	end
	return false
end

-- Brings one group's mix to `now`: fires each run's due steps on the keys it owns (each ramp
-- starts at its step's own time, so a late frame does not stretch it), moves every ramp, and
-- eases a run's keys back to the defaults once it has nothing left to do.
local function advance(mix: Mix, now: number)
	for _, run in mix.runs do
		while run.nextIndex <= #run.steps do
			local step = run.steps[run.nextIndex]
			local stepTime = run.started + step.at
			if now < stepTime then
				break
			end
			run.nextIndex += 1
			local ease = Easing.get(step.easing or Sfx.effects.easing)
			for _, key in MIX_KEYS do
				local target = (step :: any)[key]
				if typeof(target) == "number" and run.keys[key] then
					rampTo(mix, key, target, step.ramp, ease, stepTime)
				end
			end
		end
	end
	for key, tween in mix.tweens do
		if (now - tween.start) / tween.duration >= 1 then
			mix.tweens[key] = nil
			writeValue(mix, key, tween.to)
		else
			writeValue(mix, key, valueAt(mix, key, now))
		end
	end
	for index = #mix.runs, 1, -1 do
		local run = mix.runs[index]
		if next(run.keys) == nil then
			table.remove(mix.runs, index) -- every key it named was taken over
		elseif run.nextIndex > #run.steps and not moving(mix, run) then
			table.remove(mix.runs, index)
			restore(mix, now, run.keys)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Fades: a play's Volume ramped linearly to silence at its stopAt, on the same step
-- ---------------------------------------------------------------------------------------------

-- The fade's level at `time`: the play's volume until it starts, 0 from its end.
local function fadeLevel(fade: Fade, time: number): number
	local duration = fade.endsAt - fade.startsAt
	if duration <= 0 then
		return if time >= fade.endsAt then 0 else fade.from
	end
	return fade.from * math.clamp((fade.endsAt - time) / duration, 0, 1)
end

-- Moves every running fade to `now`; drops the finished ones and those whose voice was taken for
-- another play. True while one still runs.
local function advanceFades(now: number): boolean
	for index = #fades, 1, -1 do
		local fade = fades[index]
		if fade.voice.serial ~= fade.serial then
			table.remove(fades, index)
			continue
		end
		if now >= fade.startsAt then
			fade.voice.sound.Volume = fadeLevel(fade, now)
		end
		if now >= fade.endsAt then
			table.remove(fades, index)
		end
	end
	return #fades > 0
end

local function step()
	local now = deps.now()
	local busy = advanceFades(now)
	for _, mix in mixes do
		advance(mix, now)
		if isBusy(mix) then
			busy = true
		else
			setEnabled(mix, false)
		end
	end
	if not busy and stepDisconnect ~= nil then
		local disconnect = stepDisconnect :: () -> ()
		stepDisconnect = nil
		disconnect()
	end
end

local function ensureStepper()
	if stepDisconnect == nil then
		stepDisconnect = deps.onStep(function(_dt: number)
			step()
		end)
	end
end

local function stopStepper()
	if stepDisconnect ~= nil then
		local disconnect = stepDisconnect :: () -> ()
		stepDisconnect = nil
		disconnect()
	end
end

-- The steps for one group in time order (ties keep the data order).
local function stepsFor(steps: { Sfx.ContourStep }, group: string): { Sfx.ContourStep }
	local list: { Sfx.ContourStep } = {}
	for _, contourStep in steps do
		if contourStep.group == group then
			local index = #list + 1
			while index > 1 and list[index - 1].at > contourStep.at do
				index -= 1
			end
			table.insert(list, index, contourStep)
		end
	end
	return list
end

-- ---------------------------------------------------------------------------------------------
-- The play path every sound, cue layer and riser goes through
-- ---------------------------------------------------------------------------------------------

-- Plays an entry at entry.volume x 10^(gainDb / 20) for this play, at the cue layer's `speed` when
-- it sets one. With `endIn`, the start is placed so the audible end (stopAt, else the loaded
-- length) lands `endIn` seconds from now: from a later TimePosition when the region is longer than
-- the lead, after a wait when it is shorter.
local function startSound(
	name: string,
	position: Vector3?,
	gainDb: number,
	endIn: number?,
	speedOverride: number?
): Sound?
	SfxPool.start()
	stats.requested += 1
	local family, entryName = splitName(name)
	local entry = Sfx.get(family, entryName)
	local now = deps.now()
	-- A 2D sound is heard everywhere: its position does not make it another sound.
	local heardAt = if entry.spatial then position else nil
	if isDuplicate(name, heardAt, now) then
		stats.deduped += 1
		return nil
	end
	table.insert(recent, { name = name, position = heardAt, time = now })
	if entry.placeholder then
		stats.placeholders += 1
		return nil
	end
	local voice = acquireVoice(name, entry, family, entryName, now)
	local loaded = deps.timeLength(voice.sound)
	if endIn ~= nil and loaded <= 0 then
		-- Not loaded: Play would start whenever the asset arrives, so its end would not land on
		-- the hit. Skip it and load it for the next one.
		stats.unloaded += 1
		local waiting = voice.sound
		if waiting.Parent == nil then
			parentToSoundService(waiting)
		end
		deps.preload({ waiting })
		return nil
	end
	-- An asset still loading starts whenever it arrives, so no clock knows where its region ends:
	-- the play is untimed (Ended or IsPlaying frees it) and gets no Lua fade (the region still
	-- stops it).
	local late = endIn == nil and loaded <= 0
	if late then
		stats.lateStarts += 1
	end
	dropEnded(voice)
	voice.serial += 1
	local serial = voice.serial
	local sound = voice.sound
	local volume = volumeOf(entry, gainDb)
	local speed = pitchOf(entry, speedOverride)
	applyPlayback(voice, entry, volume, speed, false)
	if entry.spatial and position ~= nil then
		local emitter = acquireEmitter()
		emitter.CFrame = CFrame.new(position)
		voice.emitter = emitter
		sound.Parent = emitter
	else
		voice.emitter = nil
		parentToSoundService(sound)
	end

	-- Where the play starts in the asset, and how long it waits first (a riser shorter than its lead).
	local first = startOf(entry)
	local timePosition = first
	local wait = 0
	if endIn ~= nil then
		-- endIn > 0 here (playEndingAt skips a hit that is now or past), so from < last.
		local last = audibleEnd(entry, loaded) :: number -- loaded > 0 here
		local from = last - endIn * speed
		if from >= first then
			timePosition = from
		else
			wait = endIn - (last - first) / speed
		end
	end

	-- A trimmed play ends at its stopAt in real time; an untrimmed or late one holds the voice up
	-- to the data's longest one-shot, or until Ended frees it.
	local stopAt = entry.stopAt
	local playLength = if stopAt ~= nil and not late then math.max(stopAt - timePosition, 0) / speed else nil
	voice.timed = playLength ~= nil
	voice.startedAt = now + wait
	voice.busyUntil = if playLength ~= nil then now + wait + playLength else now + Fx.audio.maxSoundLength

	local function finish()
		if voice.serial ~= serial then
			return
		end
		dropEnded(voice)
		if voice.emitter ~= nil then
			deps.delay(Fx.audio.emitterReleaseDelay, function()
				if voice.serial ~= serial then
					return
				end
				local emitter: BasePart? = voice.emitter
				if emitter ~= nil then
					releaseEmitter(emitter)
					voice.emitter = nil
				end
				voice.busyUntil = 0
			end)
		else
			voice.busyUntil = 0
		end
	end

	local fadeOut = if late then 0 else entry.fadeOut or 0
	local fadeEnd = audibleEnd(entry, loaded)
	local function begin()
		if voice.serial ~= serial then
			return -- the voice was taken for another play while this one waited
		end
		local playedAt = deps.now()
		-- Play starts from the last TimePosition a script set: every play sets it.
		sound.TimePosition = timePosition
		if fadeOut > 0 and fadeEnd ~= nil then
			local fade: Fade = {
				voice = voice,
				serial = serial,
				from = volume,
				startsAt = playedAt + ((fadeEnd :: number) - fadeOut - timePosition) / speed,
				endsAt = playedAt + ((fadeEnd :: number) - timePosition) / speed,
			}
			sound.Volume = fadeLevel(fade, playedAt)
			table.insert(fades, fade)
			ensureStepper()
		end
		if playLength ~= nil then
			-- Ended may or may not fire at a region end: the voice frees itself when the region is over.
			voice.startedAt = playedAt
			voice.busyUntil = playedAt + playLength
			deps.delay(playLength, finish)
		end
		if deps.play(sound) then
			stats.played += 1
		end
	end
	-- Only an untimed play listens to Ended (one handler per voice, dropped when the voice plays
	-- again), else it is freed after the data's longest one-shot. A timed play never listens: an
	-- Ended that arrives late for an earlier play on this voice must not free this one.
	if playLength == nil then
		voice.ended = deps.onEnded(sound, finish)
		if voice.ended == nil then
			deps.delay(Fx.audio.maxSoundLength, finish)
		end
	end
	if wait > 0 then
		deps.delay(wait, begin)
	else
		begin()
	end
	return sound
end

-- ---------------------------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------------------------

--- Replaces the engine seams (clock, scheduler, per-frame step, Play, Stop, IsPlaying, Ended, length read, preload); nil restores the engine.
function SfxPool.bind(overrides: Overrides?)
	stopStepper()
	local base = defaultDeps()
	if overrides ~= nil then
		base.now = overrides.now or base.now
		base.delay = overrides.delay or base.delay
		base.onStep = overrides.onStep or base.onStep
		base.play = overrides.play or base.play
		base.stop = overrides.stop or base.stop
		base.isPlaying = overrides.isPlaying or base.isPlaying
		base.onEnded = overrides.onEnded or base.onEnded
		base.timeLength = overrides.timeLength or base.timeLength
		base.preload = overrides.preload or base.preload
	end
	deps = base
	local busy = #fades > 0
	for _, mix in mixes do
		if isBusy(mix) then
			busy = true
			break
		end
	end
	if busy then
		ensureStepper()
	end
end

--- Back to a fresh pool for specs: no recent plays, zero counters, no voices, loops or fades, every contour stopped.
function SfxPool.reset()
	stopStepper()
	table.clear(recent)
	stats = freshStats()
	for _, list in voices do
		for _, voice in list do
			voice.serial += 1
			dropEnded(voice)
			pcall(function()
				voice.sound:Destroy()
			end)
		end
	end
	table.clear(voices)
	for _, loop in loops do
		loop.voice.serial += 1
		pcall(function()
			loop.voice.sound:Destroy()
		end)
	end
	table.clear(loops)
	table.clear(fades)
	for _, mix in mixes do
		table.clear(mix.runs)
		table.clear(mix.tweens)
		for _, key in MIX_KEYS do
			writeValue(mix, key, defaultOf(key))
		end
		setEnabled(mix, false)
	end
	duckGeneration += 1
end

--- Creates the SoundGroups under SoundService with the section 15 mix levels and the contour effects.
function SfxPool.start()
	if started then
		return
	end
	started = true
	local master: SoundGroup? = nil
	for _, name in Sfx.groups do
		local group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = baseGroupVolume(name)
		groups[name] = group
		if name == "Master" then
			master = group
			pcall(function()
				group.Parent = SoundService
			end)
		end
	end
	for name, group in groups do
		if name ~= "Master" and master ~= nil then
			group.Parent = master
		end
	end
	for _, name in Sfx.effects.groups do
		local group: SoundGroup? = groups[name]
		if group ~= nil then
			mixes[name] = newMix(group)
		end
	end
	SfxPool.preload()
end

--- The combat sounds preload() loads, sorted: sfx.preload, every cue's layers and the families the hit, tick and parry helpers play; never a loop bed.
function SfxPool.preloadNames(): { string }
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	local function add(name: string)
		if seen[name] then
			return
		end
		seen[name] = true
		local family, entryName = splitName(name)
		if Sfx.get(family, entryName).loop ~= true then
			table.insert(names, name)
		end
	end
	for _, name in Sfx.preload do
		add(name)
	end
	for _, cueName in Sfx.cueNames() do
		for _, layer in Sfx.cue(cueName) do
			add(layer.name)
		end
	end
	for _, family in HELPER_FAMILIES do
		local group = Sfx.families[family]
		if group ~= nil then
			for entryName in group.entries do
				add(family .. "." .. entryName)
			end
		end
	end
	table.sort(names)
	return names
end

--- Creates every voice of the preloadNames() entries and asks the engine to load them, so the first
--- hit of a session is heard and the first riser knows its length. Placeholders are skipped.
function SfxPool.preload()
	local sounds: { Instance } = {}
	for _, name in SfxPool.preloadNames() do
		local family, entryName = splitName(name)
		local entry = Sfx.get(family, entryName)
		if entry.placeholder then
			continue
		end
		local list = voices[name]
		if list == nil then
			list = {}
			voices[name] = list
		end
		while #list < Sfx.mix.pooledVoicesPerEntry do
			local voice = newVoice(entry, family, entryName)
			parentToSoundService(voice.sound)
			table.insert(list, voice)
		end
		for _, voice in list do
			table.insert(sounds, voice.sound)
		end
	end
	if #sounds > 0 then
		deps.preload(sounds)
	end
end

--- Plays "family.Name" at a world position (3D) or everywhere (2D). Returns the Sound, or nil
--- when the sound was deduped or is a placeholder.
function SfxPool.play(name: string, position: Vector3?): Sound?
	return startSound(name, position, 0, nil)
end

--- Plays sfx.cues[name]: each layer through the play path at its delay (under a frame: with the call), at entry.volume x 10^(gainDb / 20) and its own pitch when it sets one.
function SfxPool.cue(name: string, position: Vector3?)
	local layers = Sfx.cue(name)
	for _, layer in layers do
		-- Resolve every layer now, so a bad name fails at the call and not inside the scheduler.
		local family, entryName = splitName(layer.name)
		Sfx.get(family, entryName)
	end
	for _, layer in layers do
		local layerName, gainDb, layerPitch = layer.name, layer.gainDb, layer.pitch
		-- Under a frame, a scheduled thread would resume on the next frame: play it with the call.
		if layer.delay < Sfx.playback.sameFrameSeconds then
			startSound(layerName, position, gainDb, nil, layerPitch)
		else
			deps.delay(layer.delay, function()
				startSound(layerName, position, gainDb, nil, layerPitch)
			end)
		end
	end
end

--- Runs sfx.contours[name] on its groups' EQ and reverb. On each group it takes over the keys
--- its steps name from whatever runs there (those ease from where they are); the other keys stay
--- with the contour that owns them.
function SfxPool.contour(name: string)
	SfxPool.start()
	local steps = Sfx.contour(name)
	local now = deps.now()
	local order: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, contourStep in steps do
		if not seen[contourStep.group] then
			seen[contourStep.group] = true
			table.insert(order, contourStep.group)
		end
	end
	for _, groupName in order do
		local mix = mixes[groupName]
		if mix == nil then
			error(("SfxPool: contour '%s' names group '%s', which has no effects"):format(name, groupName))
		end
		local resolved = mix :: Mix
		advance(resolved, now)
		local own = stepsFor(steps, groupName)
		local keys = keysOf(own)
		for _, older in resolved.runs do
			for key in keys do
				older.keys[key] = nil
			end
		end
		table.insert(resolved.runs, { name = name, started = now, steps = own, nextIndex = 1, keys = keys })
		restore(resolved, now, keys)
		setEnabled(resolved, true)
		advance(resolved, now)
	end
	ensureStepper()
end

--- Starts "family.Name" so its audible end (stopAt, else TimeLength) lands `seconds` from now (a riser into a hit); nil when deduped, a placeholder, not loaded yet, or the hit is now or past.
function SfxPool.playEndingAt(name: string, seconds: number, position: Vector3?): Sound?
	if not (seconds > 0) then
		return nil -- only its last sample (or nothing) would land on a hit that is now or past
	end
	return startSound(name, position, 0, seconds)
end

--- Every cue name in sfx.luau, sorted.
function SfxPool.cueNames(): { string }
	return Sfx.cueNames()
end

--- Every contour name in sfx.luau, sorted.
function SfxPool.contourNames(): { string }
	return Sfx.contourNames()
end

--- A contour group's EQ and reverb values as last written, whether its effects are on, and the contour running there.
function SfxPool.mixState(group: string): MixState?
	local mix = mixes[group]
	if mix == nil then
		return nil
	end
	local newest = mix.runs[#mix.runs]
	local owners: { [string]: string } = {}
	for _, run in mix.runs do
		for key in run.keys do
			owners[key] = run.name
		end
	end
	return {
		low = mix.values.low,
		mid = mix.values.mid,
		high = mix.values.high,
		wet = mix.values.wet,
		enabled = mix.enabled,
		running = if newest ~= nil then newest.name else nil,
		owners = owners,
	}
end

--- A looped bed (the heartbeat, an ambience) at `gain` 0..1 of its data volume, looping startAt .. stopAt; 0 stops it.
function SfxPool.loop(name: string, gain: number)
	SfxPool.start()
	local loop = loops[name]
	if loop == nil then
		local family, entryName = splitName(name)
		local entry = Sfx.get(family, entryName)
		local voice = newVoice(entry, family, entryName)
		parentToSoundService(voice.sound)
		loop = { voice = voice, entry = entry, playing = false }
		loops[name] = loop
	end
	local resolved = loop :: Loop
	local sound = resolved.voice.sound
	-- Only the HP heartbeat sits above the mix (section 15); an ambience bed plays at its data level.
	local above = if name == Fx.audio.heartbeatLoop then MusicState.dbToGain(-Sfx.mix.heartbeatOverAllDb) else 1
	local volume = clampVolume(volumeOf(resolved.entry, 0) * math.clamp(gain, 0, 1) * above)
	sound.Volume = volume
	local shouldPlay = gain > Fx.audio.stemFadeFloor and not resolved.entry.placeholder
	if shouldPlay and not resolved.playing then
		applyPlayback(resolved.voice, resolved.entry, volume, pitchOf(resolved.entry, nil), true)
		sound.TimePosition = startOf(resolved.entry)
		resolved.playing = deps.play(sound)
	elseif not shouldPlay and resolved.playing then
		resolved.playing = false
		deps.stop(sound)
		clearPlayback(resolved.voice)
	end
end

--- The impact for a hit-stop tier plus the short metallic ring (section 15).
function SfxPool.hit(tier: string, position: Vector3?, surface: string?)
	local impact = "impact." .. (surface or "Flesh")
	if tier == "Kill" then
		impact = "impact.Kill"
	elseif tier == "Final" then
		impact = "impact.FinalHit"
	end
	SfxPool.play(impact, position)
	SfxPool.play("impact.Ring", position)
end

--- The hit-stop tick for a tier (2D; it is the player's own frame freezing).
function SfxPool.hitStopTick(tier: string)
	local entry = Sfx.families.hitStopTick.entries[tier]
	SfxPool.play("hitStopTick." .. (if entry ~= nil then tier else "Normal"))
end

--- The parry: a bright steel clash with its ring.
function SfxPool.parry(position: Vector3?)
	SfxPool.play("guard.Parry", position)
end

--- The shatter: the Shatter cue (slam, sub, glass crack, chime, bass dive); bosses get BossShatter.
function SfxPool.shatter(position: Vector3?, boss: boolean?)
	-- The mix stays alone: the reverb bloom is the impact director's, for deaths near the camera.
	SfxPool.cue(if boss then Sfx.shatterCues.boss else Sfx.shatterCues.normal, position)
end

--- The footstep surface for a character: the event's surface, else the Humanoid's floor material.
function SfxPool.surfaceOf(model: Instance?, surface: string?): string
	if surface ~= nil and Sfx.families.footsteps.entries[surface .. "Light"] ~= nil then
		return surface
	end
	if model ~= nil then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			local ok, material = pcall(function()
				return (humanoid :: any).FloorMaterial
			end)
			if ok and material ~= nil then
				local mapped = (Fx.audio.materialSurface :: { [string]: string })[(material :: any).Name]
				if mapped ~= nil then
					return mapped
				end
			end
		end
	end
	return Fx.audio.defaultSurface
end

--- A footstep for a character by surface and weight (Light / Armored from the Armored attribute).
function SfxPool.footstep(model: Instance?, surface: string?, weight: string?)
	local resolvedSurface = SfxPool.surfaceOf(model, surface)
	local armored = if model ~= nil then model:GetAttribute(Fx.audio.armoredAttribute) else nil
	local resolvedWeight: string = if weight ~= nil then weight elseif armored == true then "Armored" else "Light"
	SfxPool.play("footsteps." .. resolvedSurface .. resolvedWeight, Engine.modelPosition(model))
end

--- Sets a group's slider (0..1 of its data level): "Master" | "Music" | "SFX" | "UI" | "Voice".
function SfxPool.setGroupVolume(name: string, fraction: number)
	applyGroupVolume(name, baseGroupVolume(name) * math.clamp(fraction, 0, 1))
end

--- Ducks Music, SFX and UI by `db` for `seconds` (the system voice ducks everything by 8 dB).
function SfxPool.duck(db: number, seconds: number)
	duckGeneration += 1
	local generation = duckGeneration
	local gain = MusicState.dbToGain(db)
	for _, name in { "Music", "SFX", "UI" } do
		applyGroupVolume(name, baseGroupVolume(name) * gain)
	end
	deps.delay(seconds, function()
		if generation ~= duckGeneration then
			return
		end
		for _, name in { "Music", "SFX", "UI" } do
			applyGroupVolume(name, baseGroupVolume(name))
		end
	end)
end

--- The SoundGroup by name once started (MusicDirector routes its stems through "Music").
function SfxPool.group(name: string): SoundGroup?
	return groups[name]
end

--- Counters for the smoke test and the profiler.
function SfxPool.stats(): Stats
	return table.clone(stats)
end

return SfxPool
