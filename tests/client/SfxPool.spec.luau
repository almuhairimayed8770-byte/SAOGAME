--!strict
-- SfxPool: the play path with trims (PlaybackRegion, TimePosition, fades), voices that free
-- themselves at their region end in real time, Ended only for untimed plays, late starts, loops
-- over their region, risers that land their stopAt on the hit, the combat preload, layered cues
-- (a layer under a frame plays with the call), the volume ceiling, contours on the groups' EQ and
-- reverb, and the shatter cue. Every engine call runs through the pool's seams: a hand-driven
-- clock and scheduler, a per-frame step the spec fires, Play / Stop recorders, a fake IsPlaying
-- and a fake loaded length; the pool's own default Ended seam runs against Sounds that carry a
-- fake Ended signal, and every NumberRange it builds refuses min > max as the engine does.
-- The behaviour cases run on a spec-only family of fake entries (`spec.*`) so the real sfx.luau
-- rows can change without changing a case; the real-data cases only hold the data to the contract.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

-- The engine refuses NumberRange.new(min, max) with min > max ("invalid range"); Lune swaps the
-- ends without a word. The pool under test gets a NumberRange that refuses it too, so a reversed
-- region fails here as it would in the game.
local StrictNumberRange = {
	new = function(first: number, last: number?): NumberRange
		if last == nil then
			return NumberRange.new(first)
		end
		if first > last then
			error(("NumberRange.new(%s, %s): invalid range"):format(tostring(first), tostring(last)), 2)
		end
		return NumberRange.new(first, last)
	end,
}

-- Lune's Sounds have no Ended event. The pool under test makes its Sounds through this shim: each
-- is the real Sound behind a stand-in that adds an Ended signal the spec fires by hand, so the
-- pool's own default Ended seam (Sound.Ended:Once) runs here. `soundsHaveEnded = false` makes the
-- member missing, like a Sound the engine cannot connect to.
type EndedSignal = { handlers: { () -> () } }
local endedOf: { [any]: EndedSignal } = setmetatable({}, { __mode = "k" }) :: any
local realOf: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local soundsHaveEnded = true

local function newSignal(): any
	local signal = { handlers = {} :: { () -> () } }
	function signal.Once(self: any, fn: () -> ()): any
		table.insert(self.handlers, fn)
		return {
			Disconnect = function(_connection: any)
				local index = table.find(self.handlers, fn)
				if index ~= nil then
					table.remove(self.handlers, index)
				end
			end,
		}
	end
	return signal
end

local function soundStandIn(real: any): any
	local signal = newSignal()
	local standIn = {}
	endedOf[standIn] = signal
	realOf[standIn] = real
	setmetatable(standIn, {
		__index = function(_self: any, key: string): any
			if key == "Ended" then
				if not soundsHaveEnded then
					error("Ended is not a valid member of Sound")
				end
				return signal
			end
			local value = real[key]
			if typeof(value) == "function" then
				return function(_standIn: any, ...: any): any
					return value(real, ...)
				end
			end
			return value
		end,
		__newindex = function(_self: any, key: string, value: any)
			real[key] = if realOf[value] ~= nil then realOf[value] else value
		end,
	})
	return standIn
end

local InstanceShim = {
	new = function(className: string): any
		local real = Instance.new(className)
		if className == "Sound" then
			return soundStandIn(real)
		end
		return real
	end,
}

-- A private SfxPool on the harness's module cache (it shares sfx, fx and Engine with this spec),
-- run with the strict NumberRange and the Sound shim.
local function loadPool(): any
	local node = Harness.node("src/client/audio/SfxPool")
	local path = Harness.repoRoot() .. "/src/client/audio/SfxPool.luau"
	local env = Harness.environment()
	env.NumberRange = StrictNumberRange
	env.Instance = InstanceShim
	env.script = node
	env.require = Harness.loadModule
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env :: any })
	return chunk()
end

local SfxPool = loadPool()
local sfx = Harness.load("src/shared/data/sfx")
local fx = Harness.load("src/shared/data/fx")
local combat = Harness.load("src/shared/data/combat")
local moments = Harness.load("src/shared/data/moments")
local Easing = Harness.load("src/shared/util/Easing")

local HIT = Vector3.new(4, 3, -6)
local FAR = HIT + Vector3.new(fx.audio.dedupeDistance * 2, 0, 0)
local EPSILON = 1e-4
-- Sound.Volume, PlaybackSpeed and the NumberRange ends are 32-bit floats in the engine.
local FLOAT = 1e-6
-- A Sound's own regions before any script touches them (the untrimmed reset).
local DEFAULT_REGION = Instance.new("Sound").PlaybackRegion
local DEFAULT_LOOP_REGION = Instance.new("Sound").LoopRegion

type Range = { min: number, max: number }

type Play = {
	name: string,
	sound: any,
	volume: number,
	speed: number,
	time: number,
	timePosition: number,
	regionsEnabled: boolean,
	region: Range,
	loopRegion: Range,
	looped: boolean,
	parent: any,
	group: any, -- the Sound's SoundGroup when it played
}

-- A hand-driven world bound into the pool. `run(t)` moves the clock to t and runs every delayed
-- callback that falls due on the way, in time order; `frame(t)` does that and then fires the
-- per-frame step once. Every Sound has loaded (`loadedLength`) unless `lengths` says otherwise
-- (0: still loading). `fireEnded(sound)` fires that Sound's Ended once, as the engine would.
local function world()
	local w = {
		now = 0,
		pending = {} :: { { at: number, order: number, fn: () -> () } },
		plays = {} :: { Play },
		stops = {} :: { any },
		lengths = {} :: { [string]: number },
		loadedLength = 30, -- an asset that has loaded (longer than any spec trim)
		preloaded = {} :: { string },
		preloadedSounds = {} :: { any },
		steppers = 0,
		engineSaysPlaying = false, -- what the fake IsPlaying answers
		overrides = {} :: { [string]: any }, -- what the world binds into the pool
	}
	local stepFns: { [number]: (number) -> () } = {}
	local orderCounter = 0
	local connectionId = 0

	function w.run(t: number)
		while true do
			local best: number? = nil
			for index, item in w.pending do
				local current = if best ~= nil then w.pending[best] else nil
				if
					item.at <= t + 1e-9
					and (
						current == nil
						or item.at < current.at
						or (item.at == current.at and item.order < current.order)
					)
				then
					best = index
				end
			end
			if best == nil then
				break
			end
			local item = table.remove(w.pending, best :: number) :: any
			w.now = math.max(w.now, item.at)
			item.fn()
		end
		w.now = t
	end

	function w.frame(t: number)
		w.run(t)
		local fns = {}
		for _, fn in stepFns do
			table.insert(fns, fn)
		end
		for _, fn in fns do
			fn(1 / 60)
		end
	end

	function w.names(): { string }
		local names = {}
		for _, play in w.plays do
			table.insert(names, play.name)
		end
		return names
	end

	-- The Ended handlers waiting on a Sound the pool made.
	function w.endedCount(sound: any): number
		local signal = endedOf[sound]
		return if signal ~= nil then #signal.handlers else 0
	end

	-- The engine fires the Sound's Ended: every Once handler waiting on it runs, once.
	function w.fireEnded(sound: any)
		local signal = endedOf[sound]
		if signal == nil then
			return
		end
		local handlers = signal.handlers
		signal.handlers = {}
		for _, fn in handlers do
			fn()
		end
	end

	-- Binds the world again with `extra` seams on top (nil fields keep the world's).
	function w.rebind(extra: { [string]: any })
		local merged = table.clone(w.overrides)
		for key, value in extra do
			merged[key] = value
		end
		SfxPool.bind(merged :: any)
	end

	SfxPool.reset()
	w.overrides = {
		now = function()
			return w.now
		end,
		delay = function(seconds: number, fn: () -> ())
			orderCounter += 1
			table.insert(w.pending, { at = w.now + seconds, order = orderCounter, fn = fn })
		end,
		onStep = function(fn: (number) -> ()): () -> ()
			connectionId += 1
			local id = connectionId
			stepFns[id] = fn
			w.steppers += 1
			return function()
				if stepFns[id] ~= nil then
					stepFns[id] = nil
					w.steppers -= 1
				end
			end
		end,
		play = function(sound: Sound): boolean
			local region = sound.PlaybackRegion
			local loopRegion = sound.LoopRegion
			table.insert(w.plays, {
				name = sound.Name,
				sound = sound,
				volume = sound.Volume,
				speed = sound.PlaybackSpeed,
				time = w.now,
				timePosition = sound.TimePosition,
				regionsEnabled = sound.PlaybackRegionsEnabled,
				region = { min = region.Min, max = region.Max },
				loopRegion = { min = loopRegion.Min, max = loopRegion.Max },
				looped = sound.Looped,
				parent = sound.Parent,
				group = sound.SoundGroup,
			})
			return true
		end,
		stop = function(sound: Sound)
			table.insert(w.stops, sound)
		end,
		isPlaying = function(_sound: Sound): boolean
			return w.engineSaysPlaying
		end,
		timeLength = function(sound: Sound): number
			return w.lengths[sound.Name] or w.loadedLength
		end,
		preload = function(sounds: { Instance })
			for _, sound in sounds do
				table.insert(w.preloaded, sound.Name)
				table.insert(w.preloadedSounds, sound)
			end
		end,
	}
	SfxPool.bind(w.overrides :: any)
	return w
end

-- Runs `body` with a fresh world and puts the pool back on the engine seams after, pass or fail.
local function scenario(body: (any) -> ())
	local w = world()
	local ok, err = pcall(body, w)
	soundsHaveEnded = true
	SfxPool.reset()
	SfxPool.bind(nil)
	if not ok then
		error(err, 0)
	end
end

-- The spec-only entries. Their trims are the picks' own shapes: Swish is whoosh.Medium's
-- (0.34 .. 0.55, a 0.06 s fade), Riser is whoosh.Riser's (0.15 .. 0.46, no fade), Tick a 2D
-- one-shot, Bed an ambience loop region.
local function specEntries(): { [string]: any }
	local function real(fields: { [string]: any }): { [string]: any }
		local entry: { [string]: any } = { id = "rbxassetid://1", placeholder = false, volume = 0.5, spatial = true }
		for key, value in fields do
			entry[key] = value
		end
		return entry
	end
	return {
		Plain = real({ volume = 0.6 }),
		Flat = real({ volume = 0.45, spatial = false }),
		Swish = real({ volume = 0.32, startAt = 0.34, stopAt = 0.55, fadeOut = 0.06, length = 0.9 }),
		SwishFast = real({
			volume = 0.32,
			pitchRange = { 1.25, 1.25 },
			startAt = 0.34,
			stopAt = 0.55,
			fadeOut = 0.06,
			length = 0.9,
		}),
		Riser = real({ volume = 0.7, startAt = 0.15, stopAt = 0.46, fadeOut = 0, length = 1.5 }),
		RiserFast = real({ volume = 0.7, pitchRange = { 1.1, 1.1 }, startAt = 0.15, stopAt = 0.46, length = 1.5 }),
		RiserFade = real({ volume = 0.7, startAt = 0.15, stopAt = 0.46, fadeOut = 0.1, length = 1.5 }),
		Tick = real({ volume = 0.2, spatial = false, startAt = 0, stopAt = 0.08, fadeOut = 0.02, length = 0.4 }),
		-- 2D, 0.4 s of asset at a fixed speed: 0.32 s of real time at 1.25x, 0.533 s at 0.75x.
		FlatFast = real({ volume = 0.3, spatial = false, pitchRange = { 1.25, 1.25 }, startAt = 0, stopAt = 0.4 }),
		FlatSlow = real({ volume = 0.3, spatial = false, pitchRange = { 0.75, 0.75 }, startAt = 0, stopAt = 0.4 }),
		-- Pitch ranges past the speeds the data may ask for (the validator refuses them in sfx.luau).
		TooFast = real({ volume = 0.3, spatial = false, pitchRange = { 3, 3 }, startAt = 0, stopAt = 0.4 }),
		TooSlow = real({ volume = 0.3, spatial = false, pitchRange = { 0.2, 0.2 }, startAt = 0, stopAt = 0.4 }),
		Tail = real({ volume = 0.4, startAt = 0.25, length = 18.4 }),
		TailUnknown = real({ volume = 0.4, startAt = 0.25 }),
		Bed = real({ volume = 0.36, spatial = false, loop = true, startAt = 2, stopAt = 125, length = 128 }),
		PlainBed = real({ volume = 0.3, spatial = false }),
		Silent = { id = sfx.placeholderId, placeholder = true, volume = 0.5, spatial = true },
	}
end

local SPEC_CUES = {
	SpecStack = {
		{ name = "spec.Swish", delay = 0, gainDb = 2 },
		{ name = "spec.Plain", delay = 0.004, gainDb = -3 },
		{ name = "spec.Tick", delay = 0.02, gainDb = 0 },
	},
	SpecPitched = {
		{ name = "spec.Swish", delay = 0, gainDb = 0, pitch = 1.25 },
		{ name = "spec.Riser", delay = 0, gainDb = 0 },
	},
	SpecSilent = {
		{ name = "spec.Silent", delay = 0, gainDb = 0 },
		{ name = "spec.Silent", delay = 0.05, gainDb = -2 },
	},
	-- Under a frame, half a frame, and exactly one frame.
	-- The Dodge cue's shape: a whoosh with the call and a landing at the end of the step.
	SpecLanding = {
		{ name = "spec.Swish", delay = 0, gainDb = 0 },
		{ name = "spec.Plain", delay = 0.25, gainDb = 0 },
	},
	SpecFrames = {
		{ name = "spec.Swish", delay = 0, gainDb = 0 },
		{ name = "spec.Plain", delay = sfx.playback.sameFrameSeconds / 2, gainDb = 0 },
		{ name = "spec.Tick", delay = sfx.playback.sameFrameSeconds, gainDb = 0 },
	},
	SpecTooFast = {
		{ name = "spec.Flat", delay = 0, gainDb = 0, pitch = 3 },
	},
	-- 0.6 x 10^(6 / 20) = 1.2: past the ceiling (the validator refuses this in sfx.luau).
	SpecLoud = {
		{ name = "spec.Plain", delay = 0, gainDb = 6 },
	},
}

-- Runs `body` in a fresh world with the spec family and the spec cues installed.
local function spec(body: (any) -> ())
	scenario(function(w)
		sfx.families.spec = { group = "SFX", entries = specEntries() }
		for name, layers in SPEC_CUES do
			sfx.cues[name] = layers
		end
		local ok, err = pcall(body, w)
		sfx.families.spec = nil
		for name in SPEC_CUES do
			sfx.cues[name] = nil
		end
		if not ok then
			error(err, 0)
		end
	end)
end

local function entryOf(name: string): any
	local family, entryName = name:match("^([^%.]+)%.(.+)$")
	return sfx.get(family :: string, entryName :: string)
end

-- Marks the named real entries playable (a non-zero id, placeholder = false) while `body` runs.
local function withReal(names: { string }, body: () -> ())
	local saved = {}
	for _, name in names do
		local entry = entryOf(name)
		if saved[entry] == nil then
			saved[entry] = { id = entry.id, placeholder = entry.placeholder }
			entry.id = "rbxassetid://1"
			entry.placeholder = false
		end
	end
	local ok, err = pcall(body)
	for entry, values in saved do
		entry.id = values.id
		entry.placeholder = values.placeholder
	end
	SfxPool.reset()
	if not ok then
		error(err, 0)
	end
end

-- Sets fields on real entries while `body` runs and puts every entry back exactly as it was.
local function withFields(changes: { [string]: { [string]: any } }, body: () -> ())
	local saved = {}
	for name, fields in changes do
		local entry = entryOf(name)
		saved[entry] = table.clone(entry)
		for key, value in fields do
			entry[key] = value
		end
	end
	local ok, err = pcall(body)
	for entry, copy in saved do
		table.clear(entry)
		for key, value in copy do
			entry[key] = value
		end
	end
	SfxPool.reset()
	if not ok then
		error(err, 0)
	end
end

local function layerNames(cueName: string): { string }
	local names = {}
	for _, layer in sfx.cue(cueName) do
		table.insert(names, layer.name)
	end
	return names
end

-- When a layer with this delay sounds: with the cue under a frame (a scheduled thread would
-- resume a whole frame late), else at its delay.
local function dueAt(delay: number): number
	return if delay < sfx.playback.sameFrameSeconds then 0 else delay
end

-- A cue's layers in the order they sound (by when they are due; ties keep the data order).
local function byDelay(cueName: string): { any }
	local list = {}
	for index, layer in sfx.cue(cueName) do
		table.insert(list, { layer = layer, index = index })
	end
	table.sort(list, function(a, b)
		local first, second = dueAt(a.layer.delay), dueAt(b.layer.delay)
		if first == second then
			return a.index < b.index
		end
		return first < second
	end)
	local layers = {}
	for _, item in list do
		table.insert(layers, item.layer)
	end
	return layers
end

local function playsOf(w: any, name: string): { Play }
	local list = {}
	for _, play in w.plays do
		if play.name == name then
			table.insert(list, play)
		end
	end
	return list
end

local function expectRegion(play: Play, first: number, last: number)
	expect(play.regionsEnabled).toBe(true)
	expect(play.region.min).toBeCloseTo(first, FLOAT)
	expect(play.region.max).toBeCloseTo(last, FLOAT)
end

local function expectUntrimmed(play: Play)
	expect(play.regionsEnabled).toBe(false)
	expect(play.region.min).toBe(DEFAULT_REGION.Min)
	expect(play.region.max).toBe(DEFAULT_REGION.Max)
	expect(play.loopRegion.min).toBe(DEFAULT_LOOP_REGION.Min)
	expect(play.loopRegion.max).toBe(DEFAULT_LOOP_REGION.Max)
	expect(play.looped).toBe(false)
	expect(play.timePosition).toBe(0)
end

-- Adds spec-only contours to sfx.contours while `body` runs.
local function withContours(extra: { [string]: any }, body: () -> ())
	for name, steps in extra do
		sfx.contours[name] = steps
	end
	local ok, err = pcall(body)
	for name in extra do
		sfx.contours[name] = nil
	end
	if not ok then
		error(err, 0)
	end
end

local function effectsOf(group: string): (any, any)
	local soundGroup = SfxPool.group(group) :: any
	return soundGroup:FindFirstChildOfClass("EqualizerSoundEffect"),
		soundGroup:FindFirstChildOfClass("ReverbSoundEffect")
end

-- The idle value of a contour key: the flat EQ band or the dry reverb.
local function idle(key: string): number
	return if key == "wet" then sfx.effects.reverb.wet else sfx.effects.equalizer[key]
end

-- The first step of a contour on `group` that sets `key` below 0 (the cut) and the later one
-- that sets it back to 0 (the return).
local function cutAndBack(contourName: string, group: string, key: string): (any, any)
	local cut, back
	for _, step in sfx.contour(contourName) do
		if step.group == group and step[key] ~= nil then
			if step[key] < 0 and cut == nil then
				cut = step
			elseif step[key] == 0 and cut ~= nil and back == nil then
				back = step
			end
		end
	end
	return cut, back
end

describe("SfxPool trims: PlaybackRegion and TimePosition on every play", function()
	it("plays a trimmed entry inside its region from startAt", function()
		spec(function(w)
			local sound = SfxPool.play("spec.Swish", HIT)
			expect(sound).never.toBeNil()
			expect(#w.plays).toBe(1)
			local play = w.plays[1]
			expectRegion(play, 0.34, 0.55)
			expect(play.timePosition).toBeCloseTo(0.34, 1e-9)
			expect(play.looped).toBe(false)
			expect(play.loopRegion.min).toBe(DEFAULT_LOOP_REGION.Min)
			expect(play.loopRegion.max).toBe(DEFAULT_LOOP_REGION.Max)
			expect(play.volume).toBeCloseTo(0.32, FLOAT)
			expect(play.speed).toBe(1)
		end)
	end)

	it("runs against a NumberRange that refuses min > max, as the engine does", function()
		expect(function()
			StrictNumberRange.new(0.55, 0.34)
		end).toThrow("invalid range")
		expect(StrictNumberRange.new(0.34, 0.55).Max).toBeCloseTo(0.55, FLOAT)
	end)

	it("plays an entry without startAt or stopAt as before: no region, from the top", function()
		spec(function(w)
			SfxPool.play("spec.Plain", HIT)
			SfxPool.play("spec.Flat")
			expect(#w.plays).toBe(2)
			for _, play in w.plays do
				expectUntrimmed(play)
			end
			expect(w.plays[1].volume).toBeCloseTo(0.6, FLOAT)
		end)
	end)

	it("runs a startAt with no stopAt to the library length, else to the data's open end", function()
		spec(function(w)
			SfxPool.play("spec.Tail", HIT)
			SfxPool.play("spec.TailUnknown", HIT)
			expectRegion(playsOf(w, "spec.Tail")[1], 0.25, 18.4)
			expectRegion(playsOf(w, "spec.TailUnknown")[1], 0.25, sfx.playback.openEndSeconds)
			for _, play in w.plays do
				expect(play.timePosition).toBeCloseTo(0.25, 1e-9)
			end
		end)
	end)

	it("sends the hit, tick and parry helpers through the same trimmed path", function()
		scenario(function(w)
			local trims = {
				["impact.Flesh"] = { startAt = 0.27, stopAt = 0.72, fadeOut = 0.15 },
				["impact.Ring"] = { startAt = 0, stopAt = 0.27, fadeOut = 0.05 },
				["impact.FinalHit"] = { startAt = 0.17, stopAt = 0.36, fadeOut = 0.05 },
				["hitStopTick.Normal"] = { startAt = 0, stopAt = 0.08, fadeOut = 0.02 },
				["guard.Parry"] = { startAt = 0.39, stopAt = 0.82, fadeOut = 0.12 },
			}
			local changes = {}
			for name, trim in trims do
				local fields = table.clone(trim) :: { [string]: any }
				fields.id = "rbxassetid://1"
				fields.placeholder = false
				changes[name] = fields
			end
			withFields(changes, function()
				SfxPool.hit("Normal", HIT, "Flesh")
				SfxPool.hit("Final", FAR, nil)
				SfxPool.hitStopTick("Normal")
				SfxPool.parry(HIT)
				expect(#w.plays).toBe(6)
				for _, play in w.plays do
					local trim = trims[play.name]
					expect(trim).never.toBeNil()
					expectRegion(play, trim.startAt, trim.stopAt)
					expect(play.timePosition).toBeCloseTo(trim.startAt, 1e-9)
				end
			end)
		end)
	end)
end)

describe("SfxPool fades", function()
	it("fades a trimmed play linearly to silence, ending at stopAt (PlaybackSpeed 1)", function()
		spec(function(w)
			local sound = SfxPool.play("spec.Swish", HIT) :: any
			-- The fade starts (stopAt - fadeOut - startAt) / speed = 0.15 s in and ends at 0.21 s.
			expect(w.steppers).toBe(1)
			w.frame(0.149)
			expect(sound.Volume).toBeCloseTo(0.32, FLOAT)
			w.frame(0.165)
			expect(sound.Volume).toBeCloseTo(0.32 * 0.75, FLOAT)
			w.frame(0.18)
			expect(sound.Volume).toBeCloseTo(0.32 * 0.5, FLOAT)
			w.frame(0.21)
			expect(sound.Volume).toBeCloseTo(0, FLOAT)
			w.frame(0.21 + EPSILON)
			expect(sound.Volume).toBe(0)
			-- Done: the step lets go.
			w.frame(0.25)
			expect(w.steppers).toBe(0)
		end)
	end)

	it("at PlaybackSpeed 1.25 starts and ends the fade 1.25 times sooner", function()
		spec(function(w)
			local sound = SfxPool.play("spec.SwishFast", HIT) :: any
			expect(w.plays[1].speed).toBeCloseTo(1.25, FLOAT)
			local starts = (0.55 - 0.06 - 0.34) / 1.25
			local ends = (0.55 - 0.34) / 1.25
			w.frame(starts - EPSILON)
			expect(sound.Volume).toBeCloseTo(0.32, FLOAT)
			w.frame((starts + ends) / 2)
			expect(sound.Volume).toBeCloseTo(0.16, FLOAT)
			w.frame(ends)
			expect(sound.Volume).toBe(0)
			w.frame(ends + EPSILON)
			expect(w.steppers).toBe(0)
		end)
	end)

	it("starts the fade from the cue layer's gained volume", function()
		spec(function(w)
			SfxPool.cue("SpecStack", HIT)
			local play = playsOf(w, "spec.Swish")[1]
			local gained = 0.32 * 10 ^ (2 / 20)
			expect(play.volume).toBeCloseTo(gained, FLOAT)
			w.frame(0.18)
			expect(play.sound.Volume).toBeCloseTo(gained * 0.5, FLOAT)
			-- The base volume never moved.
			expect(entryOf("spec.Swish").volume).toBe(0.32)
		end)
	end)

	it("starts a riser that begins inside its fade part-way down", function()
		spec(function(w)
			w.lengths["spec.RiserFade"] = 1.5
			-- 0.05 s before the hit: TimePosition 0.41, inside the 0.36 .. 0.46 fade.
			SfxPool.playEndingAt("spec.RiserFade", 0.05, HIT)
			local play = w.plays[1]
			expect(play.timePosition).toBeCloseTo(0.41, 1e-9)
			expect(play.volume).toBeCloseTo(0.7 * 0.5, FLOAT)
			w.frame(0.025)
			expect(play.sound.Volume).toBeCloseTo(0.7 * 0.25, FLOAT)
			w.frame(0.05)
			expect(play.sound.Volume).toBe(0)
		end)
	end)

	it("drops a running fade when its voice is stolen: the new play keeps its own volume", function()
		spec(function(w)
			local sounds = {}
			for index = 1, sfx.mix.pooledVoicesPerEntry do
				w.run((index - 1) * 0.04)
				table.insert(sounds, SfxPool.play("spec.Swish", HIT))
			end
			-- 0.17 s: the first play is a third into its 0.15 .. 0.21 fade and every voice is busy.
			w.frame(0.17)
			local first = sounds[1] :: any
			expect(first.Volume).toBeLessThan(0.32)
			local again = SfxPool.play("spec.Swish", HIT)
			expect(again).toBe(first)
			expect(table.find(w.stops, first)).never.toBeNil()
			expect(first.Volume).toBeCloseTo(0.32, FLOAT)
			-- The old fade would have reached 0 at 0.21; the new play's own fade starts at 0.32.
			w.frame(0.2)
			expect(first.Volume).toBeCloseTo(0.32, FLOAT)
			w.frame(0.25)
			expect(first.Volume).toBeCloseTo(0.32, FLOAT)
			w.frame(0.17 + 0.18)
			expect(first.Volume).toBeCloseTo(0.32 * 0.5, FLOAT)
		end)
	end)

	it("leaves no fade running after reset", function()
		spec(function(w)
			SfxPool.play("spec.Swish", HIT)
			expect(w.steppers).toBe(1)
			SfxPool.reset()
			expect(w.steppers).toBe(0)
		end)
	end)
end)

describe("SfxPool voices", function()
	it(
		"frees a trimmed voice at its region end even if the engine still says it plays and Ended never fires",
		function()
			spec(function(w)
				w.engineSaysPlaying = true
				local first = SfxPool.play("spec.Tick")
				-- 0.07 s: still inside its 0.08 s region, so another voice takes the next play.
				w.run(0.07)
				local second = SfxPool.play("spec.Tick")
				expect(second).never.toBe(first)
				-- 0.081 s: the first region is over in real time; its voice plays again.
				w.run(0.081 + fx.audio.dedupeSeconds)
				local third = SfxPool.play("spec.Tick")
				expect(third).toBe(first)
			end)
		end
	)

	it("frees a 3D trimmed voice once its emitter is back after the region end", function()
		spec(function(w)
			local first = SfxPool.play("spec.Swish", HIT)
			w.run(0.21 + fx.audio.emitterReleaseDelay - EPSILON)
			expect(SfxPool.play("spec.Swish", FAR)).never.toBe(first)
			w.run(0.21 + fx.audio.emitterReleaseDelay + EPSILON)
			expect(SfxPool.play("spec.Swish", HIT)).toBe(first)
		end)
	end)

	it("keeps an untrimmed voice until the engine says it stopped", function()
		spec(function(w)
			w.engineSaysPlaying = true
			local first = SfxPool.play("spec.Flat")
			w.run(fx.audio.maxSoundLength + 1)
			local second = SfxPool.play("spec.Flat")
			expect(second).never.toBe(first)
			w.engineSaysPlaying = false
			w.run(fx.audio.maxSoundLength * 2 + 2)
			expect(SfxPool.play("spec.Flat")).toBe(first)
		end)
	end)

	it("steals the voice that has been playing longest when every voice is busy", function()
		spec(function(w)
			local sounds = {}
			for index = 1, sfx.mix.pooledVoicesPerEntry do
				w.run((index - 1) * 0.04)
				table.insert(sounds, SfxPool.play("spec.Swish"))
			end
			w.run(0.16)
			expect(SfxPool.play("spec.Swish")).toBe(sounds[1])
			-- The restarted first voice is now the newest: the next steal takes the second.
			w.run(0.2)
			expect(SfxPool.play("spec.Swish")).toBe(sounds[2])
			expect(#w.stops).toBe(2)
		end)
	end)

	it("never plays a waiting riser whose voice was stolen", function()
		spec(function(w)
			w.lengths["spec.Riser"] = 1.5
			-- Each riser 0.5 s out waits 0.19 s before its Play.
			for index = 1, sfx.mix.pooledVoicesPerEntry do
				w.run((index - 1) * 0.04)
				SfxPool.playEndingAt("spec.Riser", 0.5, HIT)
			end
			expect(#w.plays).toBe(0)
			-- The next one (0.16 s, before the first Play at 0.19) steals the oldest waiting voice,
			-- then finds it unloaded and skips.
			w.run(0.16)
			w.lengths["spec.Riser"] = 0
			expect(SfxPool.playEndingAt("spec.Riser", 0.5, HIT)).toBeNil()
			expect(#w.stops).toBe(1)
			w.run(1)
			expect(#w.plays).toBe(sfx.mix.pooledVoicesPerEntry - 1)
		end)
	end)

	it("resets a reused voice fully: volume, speed, regions, Looped and TimePosition", function()
		spec(function(w)
			w.lengths["spec.Riser"] = 1.5
			local sound = SfxPool.playEndingAt("spec.Riser", 0.2) :: any
			expect(w.plays[1].timePosition).toBeCloseTo(0.26, 1e-9)
			-- Leftovers a script or an earlier play could leave on the Sound.
			sound.Looped = true
			sound.LoopRegion = NumberRange.new(1, 2)
			sound.PlaybackRegionsEnabled = false
			sound.PlaybackRegion = NumberRange.new(0.9, 1)
			sound.Volume = 0.01
			sound.PlaybackSpeed = 3
			sound.TimePosition = 0.9
			w.run(0.2 + EPSILON)
			expect(SfxPool.play("spec.Riser")).toBe(sound)
			local play = w.plays[2]
			expectRegion(play, 0.15, 0.46)
			expect(play.timePosition).toBeCloseTo(0.15, 1e-9)
			expect(play.looped).toBe(false)
			expect(play.loopRegion.min).toBe(DEFAULT_LOOP_REGION.Min)
			expect(play.loopRegion.max).toBe(DEFAULT_LOOP_REGION.Max)
			expect(play.volume).toBeCloseTo(0.7, FLOAT)
			expect(play.speed).toBe(1)

			-- An untrimmed voice goes back to no region at all.
			local flat = SfxPool.play("spec.Flat") :: any
			flat.Looped = true
			flat.LoopRegion = NumberRange.new(1, 2)
			flat.PlaybackRegionsEnabled = true
			flat.PlaybackRegion = NumberRange.new(0.5, 0.6)
			flat.Volume = 0.01
			flat.PlaybackSpeed = 3
			flat.TimePosition = 0.4
			w.engineSaysPlaying = false
			w.run(fx.audio.maxSoundLength + 1)
			expect(SfxPool.play("spec.Flat")).toBe(flat)
			local plain = w.plays[#w.plays]
			expectUntrimmed(plain)
			expect(plain.volume).toBeCloseTo(0.45, FLOAT)
			expect(plain.speed).toBe(1)
		end)
	end)
end)

describe("SfxPool timed voices at speed", function()
	for _, case in { { name = "spec.FlatFast", speed = 1.25 }, { name = "spec.FlatSlow", speed = 0.75 } } do
		-- 0.4 s of asset: its real-time length is 0.4 / speed.
		local length = 0.4 / case.speed
		it(
			("holds a timed voice for (stopAt - startAt) / PlaybackSpeed of real time at %.2fx"):format(case.speed),
			function()
				-- Just before its real-time end the voice is still busy: the next play takes another.
				spec(function(w)
					local first = SfxPool.play(case.name)
					expect(w.plays[1].speed).toBeCloseTo(case.speed, FLOAT)
					w.run(length - 0.005)
					expect(SfxPool.play(case.name)).never.toBe(first)
				end)
				-- Just after it, the same voice plays again.
				spec(function(w)
					local first = SfxPool.play(case.name)
					w.run(length + 0.005)
					expect(SfxPool.play(case.name)).toBe(first)
				end)
			end
		)
	end

	it("times a waiting riser's fade and its voice from the delayed Play, not from the call", function()
		spec(function(w)
			w.lengths["spec.RiserFade"] = 1.5
			-- 0.5 s out with 0.31 s of region: it waits 0.19 s, then plays 0.15 .. 0.46 with a 0.1 s fade.
			local sound = SfxPool.playEndingAt("spec.RiserFade", 0.5) :: any
			w.frame(0.19 + EPSILON)
			expect(#w.plays).toBe(1)
			expect(w.plays[1].time).toBeCloseTo(0.19, 1e-9)
			-- The fade starts 0.21 s after the Play (0.40) and ends on the hit (0.50).
			w.frame(0.4 - EPSILON)
			expect(sound.Volume).toBeCloseTo(0.7, FLOAT)
			w.frame(0.45)
			expect(sound.Volume).toBeCloseTo(0.35, FLOAT)
			-- Its voice is busy until the hit: a play just before takes another.
			w.run(0.5 - 0.005)
			expect(SfxPool.play("spec.RiserFade")).never.toBe(sound)
			w.frame(0.5 + EPSILON)
			expect(sound.Volume).toBeCloseTo(0, FLOAT)
		end)
		spec(function(w)
			w.lengths["spec.RiserFade"] = 1.5
			local sound = SfxPool.playEndingAt("spec.RiserFade", 0.5)
			w.run(0.5 + 0.005)
			expect(SfxPool.play("spec.RiserFade")).toBe(sound)
		end)
	end)

	it("holds every PlaybackSpeed inside sfx.engine.playbackSpeed: a range, a cue layer's pitch", function()
		spec(function(w)
			local bounds = sfx.engine.playbackSpeed
			SfxPool.play("spec.TooFast")
			SfxPool.play("spec.TooSlow")
			SfxPool.cue("SpecTooFast")
			expect(playsOf(w, "spec.TooFast")[1].speed).toBe(bounds.max)
			expect(playsOf(w, "spec.TooSlow")[1].speed).toBe(bounds.min)
			expect(playsOf(w, "spec.Flat")[1].speed).toBe(bounds.max)
			-- Its voice is timed at the clamped speed: 0.4 s of asset at 2x.
			w.run(0.4 / bounds.max + 0.005)
			expect(SfxPool.play("spec.TooFast")).toBe(playsOf(w, "spec.TooFast")[1].sound)
		end)
	end)
end)

describe("SfxPool Ended: only an untimed play listens", function()
	it("connects no Ended for a timed play, so a late Ended cannot free a newer play's voice", function()
		spec(function(w)
			local first = SfxPool.play("spec.Tick") -- 2D, 0 .. 0.08
			expect(w.endedCount(first)).toBe(0)
			-- Free at its region end: the next play takes the same voice and sounds until 0.161.
			w.run(0.081)
			local second = SfxPool.play("spec.Tick")
			expect(second).toBe(first)
			-- The first play's Ended arrives after the pool's clock freed its voice (the engine
			-- fires it on its own frame schedule, so it can land after the next play started).
			w.run(0.09)
			w.fireEnded(first)
			w.run(0.115)
			expect(SfxPool.play("spec.Tick")).never.toBe(first)
		end)
	end)

	it("never hands a newer play's emitter to another sound through a late Ended", function()
		spec(function(w)
			local first = SfxPool.play("spec.Swish", HIT) -- 0.34 .. 0.55: 0.21 s
			w.run(0.21 + fx.audio.emitterReleaseDelay + EPSILON)
			local second = SfxPool.play("spec.Swish", HIT)
			expect(second).toBe(first)
			local emitter = w.plays[2].parent
			expect(emitter:IsA("BasePart")).toBe(true)
			w.run(0.35)
			w.fireEnded(first)
			-- The second play sounds until about 0.52: its emitter stays its own.
			w.run(0.35 + fx.audio.emitterReleaseDelay + EPSILON)
			SfxPool.play("spec.Plain", FAR)
			expect(w.plays[3].parent).never.toBe(emitter)
			expect(SfxPool.play("spec.Swish", FAR)).never.toBe(second)
		end)
	end)

	it("frees an untimed play on its Ended, with one handler per voice dropped on the next play", function()
		spec(function(w)
			w.engineSaysPlaying = false
			local first = SfxPool.play("spec.Plain", HIT) -- untrimmed: no known end
			expect(w.endedCount(first)).toBe(1)
			w.run(1)
			expect(SfxPool.play("spec.Plain", FAR)).never.toBe(first)
			w.fireEnded(first)
			expect(w.endedCount(first)).toBe(0)
			w.run(1 + fx.audio.emitterReleaseDelay + EPSILON)
			expect(SfxPool.play("spec.Plain", HIT)).toBe(first)
			expect(w.endedCount(first)).toBe(1)
		end)
	end)

	it("keeps at most one Ended handler per voice when Ended never fires (200 plays)", function()
		spec(function(w)
			w.engineSaysPlaying = false
			local seen: { [any]: boolean } = {}
			for index = 1, 200 do
				w.run(index * 0.1)
				seen[SfxPool.play("spec.Flat") :: any] = true
				seen[SfxPool.play("spec.Tick") :: any] = true
			end
			local voices = 0
			for sound in seen do
				voices += 1
				expect(w.endedCount(sound)).toBeLessThanOrEqual(if entryOf(sound.Name).stopAt ~= nil then 0 else 1)
			end
			expect(voices).toBeGreaterThan(1)
		end)
	end)

	it("lets go of a stolen voice's Ended handler even when the play that stole it is skipped", function()
		spec(function(w)
			w.engineSaysPlaying = true
			local sounds = {}
			for index = 1, sfx.mix.pooledVoicesPerEntry do
				w.run(index * 0.1)
				table.insert(sounds, SfxPool.play("spec.Flat"))
			end
			expect(w.endedCount(sounds[1])).toBe(1)
			-- A riser on the same entry steals the oldest voice, then finds the asset unloaded.
			w.run(1)
			w.lengths["spec.Flat"] = 0
			expect(SfxPool.playEndingAt("spec.Flat", 0.5)).toBeNil()
			expect(table.find(w.stops, sounds[1])).never.toBeNil()
			expect(w.endedCount(sounds[1])).toBe(0)
		end)
	end)

	it("falls back to fx.audio.maxSoundLength when a Sound has no Ended to connect to", function()
		spec(function(w)
			soundsHaveEnded = false
			w.engineSaysPlaying = false
			local first = SfxPool.play("spec.Plain", HIT)
			w.run(fx.audio.maxSoundLength - EPSILON)
			expect(SfxPool.play("spec.Plain", FAR)).never.toBe(first)
			w.run(fx.audio.maxSoundLength + fx.audio.emitterReleaseDelay + EPSILON)
			expect(SfxPool.play("spec.Plain", HIT)).toBe(first)
		end)
	end)

	it("runs an onEnded seam handed to bind, and lets its disconnect go on the next play", function()
		spec(function(w)
			local connected, disconnected = 0, 0
			w.rebind({
				onEnded = function(_sound: Sound, _fn: () -> ()): (() -> ())?
					connected += 1
					return function()
						disconnected += 1
					end
				end,
			})
			w.engineSaysPlaying = false
			SfxPool.play("spec.Flat")
			SfxPool.play("spec.Tick")
			expect(connected).toBe(1)
			w.run(fx.audio.maxSoundLength + 1)
			SfxPool.play("spec.Flat")
			expect(connected).toBe(2)
			expect(disconnected).toBe(1)
		end)
	end)
end)

describe("SfxPool late starts", function()
	it("plays an asset still loading untimed and unfaded (it starts when it arrives), and counts it", function()
		spec(function(w)
			w.lengths["spec.Swish"] = 0
			w.engineSaysPlaying = true
			local first = SfxPool.play("spec.Swish", HIT) :: any
			expect(first).never.toBeNil()
			expect(SfxPool.stats().lateStarts).toBe(1)
			-- Its trim still holds; no Lua fade runs on a clock the audio does not keep.
			expectRegion(w.plays[1], 0.34, 0.55)
			expect(w.steppers).toBe(0)
			w.frame(0.2)
			expect(first.Volume).toBeCloseTo(0.32, FLOAT)
			-- Past its region end in asset time, but nobody knows when it started: still held (the
			-- play that takes another voice is still loading too).
			w.run(0.4)
			expect(SfxPool.play("spec.Swish", FAR)).never.toBe(first)
			expect(SfxPool.stats().lateStarts).toBe(2)
			-- Its Ended frees it (and its emitter).
			w.engineSaysPlaying = false
			w.fireEnded(first)
			w.run(0.4 + fx.audio.emitterReleaseDelay + EPSILON)
			w.lengths["spec.Swish"] = nil
			expect(SfxPool.play("spec.Swish", HIT)).toBe(first)
			-- Loaded now: a timed play with its fade, and no Ended handler.
			expect(w.steppers).toBe(1)
			expect(w.endedCount(first)).toBe(0)
			expect(SfxPool.stats().lateStarts).toBe(2)
			expect(SfxPool.stats().played).toBe(3)
		end)
	end)
end)

describe("SfxPool.playEndingAt", function()
	-- The riser pick: 0.15 .. 0.46 s of the asset, a 0.31 s plateau whose end lands on the hit.
	local cases = {
		{ entry = "spec.Riser", speed = 1, gap = 0.2, timePosition = 0.26, wait = 0 },
		{ entry = "spec.RiserFast", speed = 1.1, gap = 0.2, timePosition = 0.46 - 0.2 * 1.1, wait = 0 },
		{ entry = "spec.Riser", speed = 1, gap = 0.5, timePosition = 0.15, wait = 0.5 - 0.31 },
		{ entry = "spec.RiserFast", speed = 1.1, gap = 0.5, timePosition = 0.15, wait = 0.5 - 0.31 / 1.1 },
	}
	for _, case in cases do
		local branch = if case.wait > 0 then "waits, then starts at startAt" else "starts now, part-way in"
		it(("lands stopAt %.1f s out at speed %.1f: %s"):format(case.gap, case.speed, branch), function()
			spec(function(w)
				w.lengths[case.entry] = 1.5
				local sound = SfxPool.playEndingAt(case.entry, case.gap, HIT)
				expect(sound).never.toBeNil()
				if case.wait > 0 then
					expect(#w.plays).toBe(0)
					w.run(case.wait - EPSILON)
					expect(#w.plays).toBe(0)
				end
				w.run(case.wait + EPSILON)
				expect(#w.plays).toBe(1)
				local play = w.plays[1]
				expect(play.time).toBeCloseTo(case.wait, 1e-9)
				expect(play.speed).toBeCloseTo(case.speed, FLOAT)
				expect(play.timePosition).toBeCloseTo(case.timePosition, 1e-9)
				expectRegion(play, 0.15, 0.46)
				-- Its end (stopAt, not the 1.5 s TimeLength) lands on the hit.
				expect(play.time + (0.46 - play.timePosition) / case.speed).toBeCloseTo(case.gap, 1e-9)
			end)
		end)
	end

	it("still lands on the hit when the engine resumes the wait on a later frame (30 fps)", function()
		-- task.delay resumes on the first frame boundary after the wait: on a 30 fps phone that is
		-- up to 33 ms late. The riser starts that much further into its region, so its stopAt and
		-- its fade still land where they were aimed.
		for _, case in
			{
				{ entry = "spec.Riser", speed = 1 },
				{ entry = "spec.RiserFade", speed = 1 },
				{ entry = "spec.RiserFast", speed = 1.1 },
			}
		do
			spec(function(w)
				local frame = 1 / 30
				local order = 1000
				w.rebind({
					delay = function(seconds: number, fn: () -> ())
						order += 1
						local at = math.ceil((w.now + seconds) / frame - 1e-9) * frame
						table.insert(w.pending, { at = at, order = order, fn = fn })
					end,
				})
				w.lengths[case.entry] = 1.5
				-- 0.31 s of region against a 0.5 s lead: it waits 0.19 s (at 1x), resumed at 0.2.
				local lead = 0.5
				expect(SfxPool.playEndingAt(case.entry, lead, HIT)).never.toBeNil()
				w.run(1)
				expect(#w.plays).toBe(1)
				local play = w.plays[1]
				local ideal = lead - (0.46 - 0.15) / case.speed
				expect(play.time).toBeCloseTo(math.ceil(ideal / frame - 1e-9) * frame, 1e-9)
				expect(play.time > ideal + 1e-6).toBe(true)
				expect(play.timePosition).toBeCloseTo(0.15 + (play.time - ideal) * case.speed, 1e-9)
				expect(play.time + (0.46 - play.timePosition) / case.speed).toBeCloseTo(lead, 1e-9)
			end)
		end
	end)

	it("aims the fade from where the slipped start really is", function()
		spec(function(w)
			local frame = 1 / 30
			local order = 1000
			w.rebind({
				delay = function(seconds: number, fn: () -> ())
					order += 1
					local at = math.ceil((w.now + seconds) / frame - 1e-9) * frame
					table.insert(w.pending, { at = at, order = order, fn = fn })
				end,
			})
			w.lengths["spec.RiserFade"] = 1.5
			SfxPool.playEndingAt("spec.RiserFade", 0.5, HIT)
			w.run(0.2)
			local sound = w.plays[1].sound
			-- The 0.1 s fade ends on stopAt, which lands at 0.5: half way at 0.45, silent at 0.5.
			w.frame(0.45)
			expect(sound.Volume).toBeCloseTo(0.7 * 0.5, 1e-4)
			w.frame(0.5)
			expect(sound.Volume).toBeCloseTo(0, FLOAT)
		end)
	end)

	it("lands the loaded TimeLength for an entry without a stopAt, as before", function()
		spec(function(w)
			w.lengths["spec.Flat"] = 2
			SfxPool.playEndingAt("spec.Flat", 0.5)
			expect(w.plays[1].time).toBe(0)
			expect(w.plays[1].timePosition).toBeCloseTo(1.5, 1e-9)
			expect(w.plays[1].regionsEnabled).toBe(false)
			expect(w.plays[1].region.max).toBe(DEFAULT_REGION.Max)
			expect(w.plays[1].looped).toBe(false)
		end)
		spec(function(w)
			w.lengths["spec.Flat"] = 0.3
			SfxPool.playEndingAt("spec.Flat", 0.5)
			expect(#w.plays).toBe(0)
			w.run(0.19)
			expect(#w.plays).toBe(0)
			w.run(0.25)
			expect(#w.plays).toBe(1)
			expect(w.plays[1].time).toBeCloseTo(0.2, 1e-9)
			expect(w.plays[1].timePosition).toBe(0)
		end)
	end)

	it("skips a riser that has not loaded (never out of time) and loads it for the next one", function()
		spec(function(w)
			w.lengths["spec.Riser"] = 0
			expect(SfxPool.playEndingAt("spec.Riser", 0.2, HIT)).toBeNil()
			expect(#w.plays).toBe(0)
			expect(SfxPool.stats().unloaded).toBe(1)
			expect(w.preloaded).toContain("spec.Riser")
			-- Loaded now: the next one lands on its hit.
			w.lengths["spec.Riser"] = 1.5
			w.run(1)
			expect(SfxPool.playEndingAt("spec.Riser", 0.2, HIT)).never.toBeNil()
			expect(w.plays[1].timePosition).toBeCloseTo(0.26, 1e-9)
		end)
	end)

	it("never carries a riser's offset into the voice's next plain play", function()
		spec(function(w)
			w.lengths["spec.Riser"] = 1.5
			local first = SfxPool.playEndingAt("spec.Riser", 0.2, nil)
			expect(w.plays[1].timePosition).toBeCloseTo(0.26, 1e-9)
			w.run(1)
			local second = SfxPool.play("spec.Riser", nil)
			expect(second).toBe(first)
			expect(w.plays[2].timePosition).toBeCloseTo(0.15, 1e-9)
		end)
	end)

	it("skips a riser whose hit is now or already past: nothing of it would land on the hit", function()
		spec(function(w)
			w.lengths["spec.Riser"] = 1.5
			expect(SfxPool.playEndingAt("spec.Riser", 0, HIT)).toBeNil()
			expect(SfxPool.playEndingAt("spec.Riser", -0.1, HIT)).toBeNil()
			w.run(1)
			expect(#w.plays).toBe(0)
			-- A hit still ahead plays, from before stopAt.
			expect(SfxPool.playEndingAt("spec.Riser", 0.01, HIT)).never.toBeNil()
			expect(w.plays[1].timePosition).toBeCloseTo(0.45, 1e-9)
		end)
	end)

	it("sends a placeholder riser down the path without Play", function()
		spec(function(w)
			expect(SfxPool.playEndingAt("spec.Silent", 0.5, HIT)).toBeNil()
			expect(#w.plays).toBe(0)
			expect(SfxPool.stats().placeholders).toBe(1)
		end)
	end)

	it("reads a Sound's loaded length, 0 while it has not loaded", function()
		local sound: any = Instance.new("Sound")
		expect(SfxPool.timeLength(sound)).toBe(0)
		sound.TimeLength = 1.25
		expect(SfxPool.timeLength(sound)).toBeCloseTo(1.25, 1e-9)
	end)
end)

describe("SfxPool.loop", function()
	it("loops a loop entry over startAt .. stopAt from startAt, and resets it on stop", function()
		spec(function(w)
			SfxPool.loop("spec.Bed", 1)
			expect(#w.plays).toBe(1)
			local play = w.plays[1]
			expect(play.looped).toBe(true)
			expectRegion(play, 2, 125)
			expect(play.loopRegion.min).toBeCloseTo(2, FLOAT)
			expect(play.loopRegion.max).toBeCloseTo(125, FLOAT)
			expect(play.timePosition).toBe(2)
			-- An ambience bed plays at its data level: only the heartbeat sits above the mix.
			expect(play.volume).toBeCloseTo(0.36, FLOAT)
			local sound = play.sound

			-- A gain change while it runs moves the volume and does not restart it.
			SfxPool.loop("spec.Bed", 0.5)
			expect(#w.plays).toBe(1)
			expect(sound.Volume).toBeCloseTo(0.18, FLOAT)

			-- Stopped: Stop, then not looped, no regions, from the top.
			SfxPool.loop("spec.Bed", 0)
			expect(w.stops).toHaveLength(1)
			expect(w.stops[1]).toBe(sound)
			expect(sound.Looped).toBe(false)
			expect(sound.PlaybackRegionsEnabled).toBe(false)
			expect(sound.PlaybackRegion.Min).toBe(DEFAULT_REGION.Min)
			expect(sound.PlaybackRegion.Max).toBe(DEFAULT_REGION.Max)
			expect(sound.LoopRegion.Min).toBe(DEFAULT_LOOP_REGION.Min)
			expect(sound.LoopRegion.Max).toBe(DEFAULT_LOOP_REGION.Max)
			expect(sound.TimePosition).toBe(0)
			SfxPool.loop("spec.Bed", 0)
			expect(w.stops).toHaveLength(1)

			-- Back on: the same Sound loops its region again from startAt.
			SfxPool.loop("spec.Bed", 1)
			expect(#w.plays).toBe(2)
			expect(w.plays[2].sound).toBe(sound)
			expect(w.plays[2].looped).toBe(true)
			expectRegion(w.plays[2], 2, 125)
			expect(w.plays[2].timePosition).toBe(2)
		end)
	end)

	it("loops an untrimmed bed over the whole asset", function()
		spec(function(w)
			SfxPool.loop("spec.PlainBed", 1)
			local play = w.plays[1]
			expect(play.looped).toBe(true)
			expect(play.regionsEnabled).toBe(false)
			expect(play.loopRegion.max).toBe(DEFAULT_LOOP_REGION.Max)
			expect(play.timePosition).toBe(0)
		end)
	end)

	it("lifts the HP heartbeat above the mix by heartbeatOverAllDb", function()
		scenario(function(w)
			local name = fx.audio.heartbeatLoop
			withReal({ name }, function()
				SfxPool.loop(name, 1)
				local entry = entryOf(name)
				local lifted = entry.volume * 10 ^ (sfx.mix.heartbeatOverAllDb / 20)
				expect(w.plays[1].volume).toBeCloseTo(math.min(lifted, sfx.limits.maxPlayVolume), FLOAT)
				expect(w.plays[1].looped).toBe(true)
				expect(w.plays[1].timePosition).toBeCloseTo(entry.startAt or 0, 1e-9)
			end)
		end)
	end)

	it("never plays the heartbeat above limits.maxPlayVolume, its lift included", function()
		scenario(function(w)
			local name = fx.audio.heartbeatLoop
			withFields({ [name] = { id = "rbxassetid://1", placeholder = false, volume = 0.8 } }, function()
				SfxPool.loop(name, 1)
				expect(w.plays[1].volume).toBeCloseTo(sfx.limits.maxPlayVolume, FLOAT)
				-- Under the ceiling the lift still applies in full.
				SfxPool.loop(name, 0.5)
				local lifted = 0.8 * 0.5 * 10 ^ (sfx.mix.heartbeatOverAllDb / 20)
				expect(w.plays[1].sound.Volume).toBeCloseTo(lifted, FLOAT)
			end)
		end)
	end)

	it("never plays a placeholder bed", function()
		spec(function(w)
			SfxPool.loop("spec.Silent", 1)
			expect(#w.plays).toBe(0)
		end)
	end)
end)

describe("SfxPool.preload", function()
	it("names every combat sound: sfx.preload, every cue's layers and the helpers' families, no beds", function()
		local names = SfxPool.preloadNames()
		local set: { [string]: boolean } = {}
		for index, name in names do
			expect(set[name]).toBeNil()
			set[name] = true
			if index > 1 then
				expect(names[index - 1] < name).toBe(true)
			end
			-- Never an ambience bed (another floor's, or this one's) and never a loop.
			expect(name:sub(1, #"ambience.")).never.toBe("ambience.")
			expect(entryOf(name).loop).never.toBe(true)
		end
		for _, cueName in sfx.cueNames() do
			for _, layer in sfx.cue(cueName) do
				expect(set[layer.name]).toBe(true)
			end
		end
		for _, name in sfx.preload do
			expect(set[name] or entryOf(name).loop == true).toBe(true)
		end
		for _, family in { "impact", "hitStopTick", "guard" } do
			for entryName in sfx.families[family].entries do
				expect(set[family .. "." .. entryName]).toBe(true)
			end
		end
		expect(set["whoosh.Riser"]).toBe(true)
		expect(set["guard.Parry"]).toBe(true)
		expect(set["hitStopTick.Kill"]).toBe(true)
	end)

	it("creates and loads every voice of a real combat sound, and skips placeholders and beds", function()
		spec(function(w)
			local saved = table.clone(sfx.preload)
			table.insert(sfx.preload, "spec.Bed")
			table.insert(sfx.preload, "spec.Riser")
			local ok, err = pcall(function()
				SfxPool.preload()
				local counts: { [string]: number } = {}
				for _, name in w.preloaded do
					counts[name] = (counts[name] or 0) + 1
				end
				-- The cue layers and the listed riser: every voice, so each one knows its length.
				for _, name in { "spec.Swish", "spec.Plain", "spec.Tick", "spec.Riser" } do
					expect(counts[name]).toBe(sfx.mix.pooledVoicesPerEntry)
				end
				expect(counts["spec.Silent"]).toBeNil()
				expect(counts["spec.Bed"]).toBeNil()
				-- Every real entry the pool names is loaded; nothing else is.
				for name, count in counts do
					expect(table.find(SfxPool.preloadNames(), name)).never.toBeNil()
					expect(entryOf(name).placeholder).toBe(false)
					expect(count).toBe(sfx.mix.pooledVoicesPerEntry)
				end
				-- A play uses a preloaded voice; it does not make a new Sound.
				local sound = SfxPool.play("spec.Swish", HIT)
				expect(table.find(w.preloadedSounds, sound)).never.toBeNil()
				-- Preloading again makes no more voices.
				local before = #w.preloaded
				SfxPool.preload()
				expect(#w.preloaded - before).toBe(before)
			end)
			table.clear(sfx.preload)
			for _, name in saved do
				table.insert(sfx.preload, name)
			end
			if not ok then
				error(err, 0)
			end
		end)
	end)

	it("loads the riser's every voice so the first riser of a session already knows its length", function()
		scenario(function(w)
			withReal({ "whoosh.Riser" }, function()
				SfxPool.preload()
				local count = 0
				for _, name in w.preloaded do
					if name == "whoosh.Riser" then
						count += 1
					end
				end
				expect(count).toBe(sfx.mix.pooledVoicesPerEntry)
			end)
		end)
	end)
end)

describe("SfxPool start: the contour effects", function()
	it("gives each contour group one flat EQ, always in, and one dry reverb, off while idle", function()
		scenario(function()
			SfxPool.start()
			SfxPool.start()
			for _, group in sfx.effects.groups do
				local soundGroup = SfxPool.group(group) :: any
				local eqs, reverbs = 0, 0
				for _, child in soundGroup:GetChildren() do
					if child:IsA("EqualizerSoundEffect") then
						eqs += 1
					elseif child:IsA("ReverbSoundEffect") then
						reverbs += 1
					end
				end
				expect(eqs).toBe(1)
				expect(reverbs).toBe(1)
				local eq, reverb = effectsOf(group)
				expect(eq.Name).toBe(sfx.effects.equalizer.name)
				expect(reverb.Name).toBe(sfx.effects.reverb.name)
				-- The engine's EQ defaults are -20 / -10 / 0: the pool must flatten them.
				expect(eq.LowGain).toBeCloseTo(0, EPSILON)
				expect(eq.MidGain).toBeCloseTo(0, EPSILON)
				expect(eq.HighGain).toBeCloseTo(0, EPSILON)
				-- The engine's reverb defaults are wet 0 / dry -6: the pool must dry them.
				expect(reverb.WetLevel).toBeCloseTo(sfx.engine.reverbLevelDb.min, EPSILON)
				expect(reverb.DryLevel).toBeCloseTo(sfx.effects.reverb.dry, EPSILON)
				expect(reverb.DecayTime).toBeCloseTo(sfx.effects.reverb.decayTime, EPSILON)
				expect(reverb.Density).toBeCloseTo(sfx.effects.reverb.density, EPSILON)
				expect(reverb.Diffusion).toBeCloseTo(sfx.effects.reverb.diffusion, EPSILON)
				-- The EQ runs first, so a bass cut also leaves the reverb's tail.
				expect(eq.Priority).toBeGreaterThan(reverb.Priority)
				-- The flat EQ stays in the chain (F15): a cut lands on the hit's own call with
				-- nothing switched in on that frame. The reverb is switched in only while it runs.
				expect(eq.Enabled).toBe(true)
				expect(reverb.Enabled).toBe(false)
				local state = SfxPool.mixState(group) :: any
				expect(state.running).toBeNil()
				expect(state.enabled).toBe(false)
			end
			for _, group in { "UI", "Voice" } do
				local soundGroup = SfxPool.group(group) :: any
				expect(soundGroup:FindFirstChildOfClass("EqualizerSoundEffect")).toBeNil()
				expect(soundGroup:FindFirstChildOfClass("ReverbSoundEffect")).toBeNil()
				expect(SfxPool.mixState(group)).toBeNil()
			end
		end)
	end)
end)

describe("SfxPool.cue", function()
	it("plays each layer at its delay, in time order, at entry.volume x 10^(gainDb / 20)", function()
		spec(function(w)
			SfxPool.cue("SpecStack", HIT)
			-- The first layer, and the one due a few ms later, land on the call itself.
			expect(w.names()).toEqual({ "spec.Swish", "spec.Plain" })
			w.run(1)
			local layers = byDelay("SpecStack")
			expect(#w.plays).toBe(#layers)
			for index, layer in layers do
				local play = w.plays[index]
				expect(play.name).toBe(layer.name)
				expect(play.time).toBeCloseTo(dueAt(layer.delay), 1e-9)
				expect(play.volume).toBeCloseTo(entryOf(layer.name).volume * 10 ^ (layer.gainDb / 20), FLOAT)
			end
			-- Each layer keeps its own trim.
			expectRegion(playsOf(w, "spec.Swish")[1], 0.34, 0.55)
			expectUntrimmed(playsOf(w, "spec.Plain")[1])
			expectRegion(playsOf(w, "spec.Tick")[1], 0, 0.08)
			expect(SfxPool.stats().played).toBe(#layers)
		end)
	end)

	it("plays a layer due under a frame with the cue: a scheduled thread would land a frame late", function()
		spec(function(w)
			SfxPool.cue("SpecFrames", HIT)
			expect(w.names()).toEqual({ "spec.Swish", "spec.Plain" })
			for _, play in w.plays do
				expect(play.time).toBe(0)
			end
			-- A layer a whole frame out keeps its delay.
			w.run(sfx.playback.sameFrameSeconds - EPSILON)
			expect(#w.plays).toBe(2)
			w.run(sfx.playback.sameFrameSeconds)
			expect(w.names()).toEqual({ "spec.Swish", "spec.Plain", "spec.Tick" })
		end)
	end)

	it("a late cue keeps every layer on the cue's own clock, as if it had started lateBy ago", function()
		spec(function(w)
			-- A remote dodge the catch-up started 0.1 s late: the whoosh is 0.1 s into its region
			-- already (0.34 + 0.1), and the landing comes 0.25 - 0.1 from now, not 0.25.
			SfxPool.cue("SpecLanding", HIT, 0.1)
			expect(w.names()).toEqual({ "spec.Swish" })
			expect(w.plays[1].time).toBe(0)
			expect(w.plays[1].timePosition).toBeCloseTo(0.44, 1e-9)
			w.run(0.15 - EPSILON)
			expect(#w.plays).toBe(1)
			w.run(0.15)
			expect(w.names()).toEqual({ "spec.Swish", "spec.Plain" })
			expect(w.plays[2].time).toBeCloseTo(0.15, 1e-9)
			expect(w.plays[2].timePosition).toBe(0)
		end)
	end)

	it("a late cue drops a layer already over, and plays one now that is due under a frame or past", function()
		spec(function(w)
			-- 0.3 s late: the whoosh (0.34 + 0.3 is past its 0.55 stop) has nothing left; the landing
			-- was due 0.05 s ago and starts 0.05 s in.
			SfxPool.cue("SpecLanding", HIT, 0.3)
			expect(w.names()).toEqual({ "spec.Plain" })
			expect(w.plays[1].time).toBe(0)
			expect(w.plays[1].timePosition).toBeCloseTo(0.05, 1e-9)
			w.run(1)
			expect(#w.plays).toBe(1)
		end)
		spec(function(w)
			-- Half a frame short of the landing: it is due in under a frame, so it plays with the
			-- call from its start (the whoosh is long over).
			SfxPool.cue("SpecLanding", HIT, 0.25 - sfx.playback.sameFrameSeconds / 2)
			expect(w.names()).toEqual({ "spec.Plain" })
			expect(w.plays[1].time).toBe(0)
			expect(w.plays[1].timePosition).toBe(0)
		end)
		spec(function(w)
			-- No lateness (nil or 0) is the plain cue.
			SfxPool.cue("SpecLanding", HIT, 0)
			SfxPool.cue("SpecLanding", FAR)
			expect(w.names()).toEqual({ "spec.Swish", "spec.Swish" })
			expect(w.plays[1].timePosition).toBeCloseTo(0.34, 1e-9)
			w.run(0.25)
			expect(w.names()).toEqual({ "spec.Swish", "spec.Swish", "spec.Plain", "spec.Plain" })
		end)
	end)

	it("never plays a layer above limits.maxPlayVolume, whatever its gain", function()
		spec(function(w)
			SfxPool.cue("SpecLoud", HIT)
			expect(w.plays[1].volume).toBeCloseTo(sfx.limits.maxPlayVolume, FLOAT)
		end)
	end)

	it("plays a layer at its own pitch when it sets one, and times its fade by it", function()
		spec(function(w)
			SfxPool.cue("SpecPitched", HIT)
			local swish = playsOf(w, "spec.Swish")[1]
			expect(swish.speed).toBeCloseTo(1.25, FLOAT)
			-- The fade runs on the layer's pitch: (0.55 - 0.06 - 0.34) / 1.25 = 0.12 .. 0.168 s.
			w.frame(0.144)
			expect(swish.sound.Volume).toBeCloseTo(0.16, FLOAT)
			-- A layer without one keeps the entry's own (Riser has no range: 1).
			expect(playsOf(w, "spec.Riser")[1].speed).toBe(1)
		end)
	end)

	it("plays every real cue's layers at their delays and trims, none above volume 1", function()
		for _, cueName in sfx.cueNames() do
			scenario(function(w)
				withReal(layerNames(cueName), function()
					SfxPool.cue(cueName, HIT)
					w.run(sfx.limits.cueDelaySeconds + 1)
					local stats = SfxPool.stats()
					expect(stats.played + stats.deduped).toBe(#sfx.cue(cueName))
					local index = 0
					for _, layer in byDelay(cueName) do
						local entry = entryOf(layer.name)
						local level = entry.volume * 10 ^ (layer.gainDb / 20)
						-- The contract: no layer ends above volume 1.
						expect(level).toBeLessThanOrEqual(sfx.limits.maxPlayVolume + FLOAT)
						index += 1
						local play = w.plays[index]
						if play == nil or play.name ~= layer.name then
							index -= 1 -- deduped against an earlier layer of the same sound
							continue
						end
						expect(play.time).toBeCloseTo(dueAt(layer.delay), 1e-9)
						expect(play.volume).toBeCloseTo(level, FLOAT)
						expect(play.timePosition).toBeCloseTo(entry.startAt or 0, 1e-9)
						expect(play.regionsEnabled).toBe(entry.startAt ~= nil or entry.stopAt ~= nil)
						if layer.pitch ~= nil then
							expect(play.speed).toBeCloseTo(layer.pitch, FLOAT)
						end
					end
				end)
			end)
		end
	end)

	it("dedupes inside a cue: the same cue at the same spot plays once, another spot plays again", function()
		spec(function(w)
			local names = layerNames("SpecStack")
			SfxPool.cue("SpecStack", HIT)
			SfxPool.cue("SpecStack", HIT)
			w.run(1)
			expect(w.names()).toEqual(names)
			expect(SfxPool.stats().deduped).toBe(#names)

			-- Past the window and at a spot outside the dedupe distance, every layer plays again.
			SfxPool.cue("SpecStack", FAR)
			w.run(2)
			expect(#w.plays).toBe(#names * 2)

			-- A layer already heard through another reaction at the same moment is not doubled.
			w.run(3)
			SfxPool.play("spec.Swish", HIT)
			SfxPool.cue("SpecStack", HIT)
			w.run(4)
			expect(#playsOf(w, "spec.Swish")).toBe(3)
			expect(#w.plays).toBe(#names * 3)
		end)
	end)

	it("hears a 2D layer once inside the window wherever it was asked for", function()
		spec(function(w)
			SfxPool.play("spec.Tick", HIT)
			SfxPool.play("spec.Tick", FAR)
			SfxPool.play("spec.Tick")
			expect(#playsOf(w, "spec.Tick")).toBe(1)
			-- A 3D sound at two spots is two sounds.
			SfxPool.play("spec.Swish", HIT)
			SfxPool.play("spec.Swish", FAR)
			expect(#playsOf(w, "spec.Swish")).toBe(2)
		end)
	end)

	it("sends placeholder layers down the whole path without ever calling Play", function()
		spec(function(w)
			SfxPool.cue("SpecSilent", HIT)
			w.run(1)
			expect(#w.plays).toBe(0)
			local stats = SfxPool.stats()
			expect(stats.requested).toBe(2)
			expect(stats.placeholders).toBe(2)
			expect(stats.played).toBe(0)
		end)
	end)

	it("puts 3D layers on an emitter at the hit and 2D layers nowhere in the world", function()
		spec(function(w)
			SfxPool.cue("SpecStack", HIT)
			w.run(1)
			expect(#w.plays).toBe(3)
			for _, play in w.plays do
				if entryOf(play.name).spatial then
					expect(play.parent).never.toBeNil()
					expect(play.parent:IsA("BasePart")).toBe(true)
					expect((play.parent.CFrame.Position - HIT).Magnitude).toBeCloseTo(0, EPSILON)
				else
					expect(play.parent == nil or not play.parent:IsA("BasePart")).toBe(true)
				end
			end
			expect(entryOf("spec.Tick").spatial).toBe(false)
		end)
	end)

	it("fails at the call on an unknown cue", function()
		scenario(function()
			expect(function()
				SfxPool.cue("HitEnormous", HIT)
			end).toThrow("unknown cue")
		end)
	end)

	it("lists the cue and contour names", function()
		expect(SfxPool.cueNames()).toEqual(sfx.cueNames())
		expect(SfxPool.contourNames()).toEqual(sfx.contourNames())
		expect(table.find(SfxPool.cueNames(), "HitKill")).never.toBeNil()
		expect(table.find(SfxPool.contourNames(), "KillCut")).never.toBeNil()
	end)
end)

describe("SfxPool.shatter", function()
	-- The caller's weight picks the cue; the old boolean still means boss (true) or normal.
	local cases: { { weight: any, label: string, cue: string } } = {
		{ weight = false, label = "false", cue = sfx.shatterCues.normal },
		{ weight = true, label = "true", cue = sfx.shatterCues.boss },
		{ weight = nil, label = "nil", cue = sfx.shatterCues.normal },
		{ weight = "normal", label = "normal", cue = sfx.shatterCues.normal },
		{ weight = "heavy", label = "heavy", cue = sfx.shatterCues.heavy },
		{ weight = "boss", label = "boss", cue = sfx.shatterCues.boss },
		-- The moments.luau death rows hand over the cue name itself: each shatter cue plays as named.
		{ weight = sfx.shatterCues.normal, label = "cue " .. sfx.shatterCues.normal, cue = sfx.shatterCues.normal },
		{ weight = sfx.shatterCues.heavy, label = "cue " .. sfx.shatterCues.heavy, cue = sfx.shatterCues.heavy },
		{ weight = sfx.shatterCues.boss, label = "cue " .. sfx.shatterCues.boss, cue = sfx.shatterCues.boss },
		-- A weight the data does not know never silences a death: the normal shatter plays. Nor does
		-- a cue that is not a shatter turn a death into something else.
		{ weight = "enormous", label = "enormous", cue = sfx.shatterCues.normal },
		{ weight = "HitBasic", label = "cue HitBasic", cue = sfx.shatterCues.normal },
	}
	for _, case in cases do
		it(("plays %s for the weight %s, by delay, and leaves the mix alone"):format(case.cue, case.label), function()
			scenario(function(w)
				withReal(layerNames(case.cue), function()
					SfxPool.shatter(HIT, case.weight)
					w.frame(0)
					-- The bloom is the impact director's (deaths near the camera): the shatter starts no contour.
					local state = SfxPool.mixState("SFX") :: any
					expect(state.running).toBeNil()
					expect(state.wet).toBe(sfx.effects.reverb.wet)
					w.run(sfx.limits.cueDelaySeconds + 1)
					local expected = {}
					for _, layer in byDelay(case.cue) do
						table.insert(expected, layer.name)
					end
					expect(w.names()).toEqual(expected)
					for index, layer in byDelay(case.cue) do
						expect(w.plays[index].time).toBeCloseTo(dueAt(layer.delay), 1e-9)
					end
				end)
			end)
		end)
	end

	it("lands a heavy shatter's bass dive 3 dB over a normal one's, the rest alike", function()
		local volumes: { [string]: number } = {}
		for _, weight in { "normal", "heavy" } do
			scenario(function(w)
				withReal(layerNames(sfx.shatterCues[weight]), function()
					SfxPool.shatter(HIT, weight)
					for _, play in w.plays do
						if play.name == "impact.SubDrop" then
							volumes[weight] = play.volume
						end
					end
				end)
			end)
		end
		local dive = entryOf("impact.SubDrop").volume
		expect(volumes.heavy).toBeCloseTo(dive, FLOAT)
		expect(volumes.normal).toBeCloseTo(dive * 10 ^ (-3 / 20), FLOAT)
	end)

	it("plays shatters that crack together once inside a sound's reach; another cue or a later one plays", function()
		scenario(function(w)
			local normal = sfx.shatterCues.normal
			local heavy = sfx.shatterCues.heavy
			local names = layerNames(normal)
			for _, name in layerNames(heavy) do
				table.insert(names, name)
			end
			withReal(names, function()
				-- One sweep's two kills, farther apart than the same-spot dedupe reaches, and a
				-- player's death in the same frame.
				local elsewhere = HIT - Vector3.new(fx.audio.dedupeDistance * 2, 0, 0)
				SfxPool.shatter(HIT, "normal")
				SfxPool.shatter(FAR, "normal")
				SfxPool.shatter(elsewhere, "heavy")
				w.run(sfx.limits.cueDelaySeconds + 1)
				expect(#w.plays).toBe(#sfx.cue(normal) + #sfx.cue(heavy))
				-- Past the window a shatter is another death's.
				SfxPool.shatter(FAR, "normal")
				w.run(2 * (sfx.limits.cueDelaySeconds + 1))
				expect(#w.plays).toBe(2 * #sfx.cue(normal) + #sfx.cue(heavy))
				-- reset forgets the last shatter.
				SfxPool.reset()
				SfxPool.shatter(FAR, "normal")
				w.run(3 * (sfx.limits.cueDelaySeconds + 1))
				expect(#w.plays).toBe(3 * #sfx.cue(normal) + #sfx.cue(heavy))
			end)
		end)
	end)

	it("plays a shatter beyond the last one's reach: a kill across the map does not mute the one here", function()
		scenario(function(w)
			local normal = sfx.shatterCues.normal
			withReal(layerNames(normal), function()
				local across = HIT + Vector3.new(sfx.mix.rolloffMaxDistance * 2, 0, 0)
				SfxPool.shatter(across, "normal")
				SfxPool.shatter(HIT, "normal")
				-- One with no position folds into the last one, as before.
				SfxPool.shatter(nil, "normal")
				w.run(sfx.limits.cueDelaySeconds + 1)
				expect(#w.plays).toBe(2 * #sfx.cue(normal))
			end)
		end)
	end)
end)

describe("SfxPool.playLate", function()
	it("starts a sound a late clip start jumped over where it would be by now, at its speed", function()
		spec(function(w)
			-- Swish plays 0.34 .. 0.55 of its asset; 0.05 s late it starts at 0.39.
			expect(SfxPool.playLate("spec.Swish", 0.05, HIT)).never.toBeNil()
			expect(#w.plays).toBe(1)
			expect(w.plays[1].time).toBe(0)
			expect(w.plays[1].timePosition).toBeCloseTo(0.39, 1e-9)
			expectRegion(w.plays[1], 0.34, 0.55)
			-- At 1.25x the asset moved 1.25 times as far.
			SfxPool.playLate("spec.SwishFast", 0.05, FAR)
			expect(w.plays[2].speed).toBeCloseTo(1.25, FLOAT)
			expect(w.plays[2].timePosition).toBeCloseTo(0.34 + 0.05 * 1.25, 1e-9)
			-- Its fade still ends on stopAt: (0.55 - 0.06 - 0.39) = 0.10 s in it starts, 0.16 s it ends.
			local sound = w.plays[1].sound
			w.frame(0.099)
			expect(sound.Volume).toBeCloseTo(0.32, FLOAT)
			w.frame(0.13)
			expect(sound.Volume).toBeCloseTo(0.32 * 0.5, FLOAT)
			w.frame(0.16)
			expect(sound.Volume).toBeCloseTo(0, FLOAT)
			-- Nothing late is a plain play.
			SfxPool.playLate("spec.Plain", 0, Vector3.new(90, 0, 0))
			expect(w.plays[3].timePosition).toBe(0)
		end)
	end)

	it("skips a sound already over by now, a placeholder, and a duplicate like any play", function()
		spec(function(w)
			-- 0.34 + 0.25 is past Swish's stopAt.
			expect(SfxPool.playLate("spec.Swish", 0.25, HIT)).toBeNil()
			expect(SfxPool.playLate("spec.Silent", 0.01, HIT)).toBeNil()
			expect(#w.plays).toBe(0)
			SfxPool.playLate("spec.Swish", 0.01, HIT)
			expect(SfxPool.playLate("spec.Swish", 0.02, HIT)).toBeNil()
			expect(SfxPool.play("spec.Swish", HIT)).toBeNil()
			expect(#w.plays).toBe(1)
		end)
	end)
end)

describe("the harness NumberRange", function()
	it("refuses min > max as the engine does, so a reversed region fails in every spec", function()
		local env = Harness.environment()
		expect(function()
			env.NumberRange.new(2, 1)
		end).toThrow("invalid range")
		local range = env.NumberRange.new(1, 2)
		expect(range.Min).toBe(1)
		expect(range.Max).toBe(2)
		local single = env.NumberRange.new(0.5)
		expect(single.Min).toBe(0.5)
		expect(single.Max).toBe(0.5)
		expect(env.NumberRange.new(1, 1).Max).toBe(1)
	end)
end)

describe("SfxPool.contour", function()
	it("eases FinalHit's bass cut in and out (never linear) and goes idle on the dry defaults", function()
		scenario(function(w)
			local cut, back = cutAndBack("FinalHit", "SFX", "low")
			expect(cut).never.toBeNil()
			expect(back).never.toBeNil()
			expect(back.at).toBeGreaterThan(cut.at + cut.ramp)
			local ease = Easing.get(cut.easing or sfx.effects.easing)
			local eq = effectsOf("SFX")

			SfxPool.contour("FinalHit")
			local state = SfxPool.mixState("SFX") :: any
			expect(state.running).toBe("FinalHit")
			expect(state.enabled).toBe(true)
			expect(eq.Enabled).toBe(true)
			expect(w.steppers).toBe(1)

			-- The cut's ramp is under a frame, which no step can draw: it is in place on the call.
			expect(cut.ramp).toBeLessThan(sfx.playback.sameFrameSeconds)
			expect((SfxPool.mixState("SFX") :: any).low).toBeCloseTo(cut.low, 1e-6)
			w.frame(cut.at + cut.ramp / 4)
			expect((SfxPool.mixState("SFX") :: any).low).toBeCloseTo(cut.low, 1e-6)
			-- A ramp of a frame or more still eases: on the curve, not on the straight line.
			expect(back.ramp).toBeGreaterThanOrEqual(sfx.playback.sameFrameSeconds)
			expect(ease(0.25)).never.toBeCloseTo(0.25, EPSILON)

			-- The cut holds through the freeze.
			w.frame(back.at - EPSILON)
			expect((SfxPool.mixState("SFX") :: any).low).toBeCloseTo(cut.low, 1e-6)
			expect(eq.LowGain).toBeCloseTo(cut.low, 1e-6)
			-- And the bass slams back on the release, eased.
			local backEase = Easing.get(back.easing or sfx.effects.easing)
			w.frame(back.at + back.ramp / 4)
			local returning = (SfxPool.mixState("SFX") :: any).low
			expect(returning).toBeCloseTo(cut.low + (0 - cut.low) * backEase(0.25), 1e-6)
			w.frame(back.at + back.ramp + EPSILON)
			expect((SfxPool.mixState("SFX") :: any).low).toBe(0)
			expect(eq.LowGain).toBe(0)

			-- Every group done: the effects switch off and the step disconnects.
			local last = 0
			for _, step in sfx.contour("FinalHit") do
				last = math.max(last, step.at + step.ramp)
			end
			w.frame(last + EPSILON)
			w.frame(last + sfx.effects.restoreSeconds + EPSILON)
			for _, group in sfx.effects.groups do
				local after = SfxPool.mixState(group) :: any
				expect(after.running).toBeNil()
				expect(after.enabled).toBe(false)
				expect(after.low).toBe(0)
			end
			-- Idle: the reverb is switched out, the flat EQ stays in for the next hit.
			local _, reverb = effectsOf("SFX")
			expect(reverb.Enabled).toBe(false)
			expect(eq.Enabled).toBe(true)
			expect(w.steppers).toBe(0)
		end)
	end)

	it("reaches every step's value in every contour and restores the defaults after", function()
		for _, name in sfx.contourNames() do
			scenario(function(w)
				local steps = sfx.contour(name)
				local checks = {}
				local last = 0
				for index, step in steps do
					local done = step.at + step.ramp
					last = math.max(last, done)
					for _, key in { "low", "mid", "high", "wet" } do
						local target = (step :: any)[key]
						if target == nil then
							continue
						end
						-- Skip a value a later step on the same key overrides before this one lands.
						local overridden = false
						for other, later in steps do
							if
								other ~= index
								and later.group == step.group
								and (later :: any)[key] ~= nil
								and later.at > step.at
								and later.at <= done
							then
								overridden = true
							end
						end
						if not overridden then
							table.insert(checks, { time = done, group = step.group, key = key, target = target })
						end
					end
				end
				table.sort(checks, function(a, b)
					return a.time < b.time
				end)
				expect(#checks).toBeGreaterThan(0)
				SfxPool.contour(name)
				for _, check in checks do
					w.frame(check.time + EPSILON)
					expect((SfxPool.mixState(check.group) :: any)[check.key]).toBeCloseTo(check.target, 1e-6)
				end
				w.frame(last + EPSILON)
				w.frame(last + sfx.effects.restoreSeconds + EPSILON * 2)
				for _, group in sfx.effects.groups do
					local state = SfxPool.mixState(group) :: any
					for _, key in { "low", "mid", "high", "wet" } do
						expect(state[key]).toBe(idle(key))
					end
					expect(state.enabled).toBe(false)
				end
				local _eq, reverb = effectsOf("SFX")
				expect(reverb.WetLevel).toBe(sfx.effects.reverb.wet)
				expect(w.steppers).toBe(0)
			end)
		end
	end)

	it("pulses the reverb wet on the shatter and dries it frame after frame", function()
		scenario(function(w)
			local wets = {}
			for _, step in sfx.contour("ShatterBloom") do
				if step.group == "SFX" and step.wet ~= nil then
					table.insert(wets, step)
				end
			end
			table.sort(wets, function(a, b)
				return a.at < b.at
			end)
			expect(#wets).toBeGreaterThanOrEqual(2)
			local peakStep, dryStep = wets[1], wets[2]
			expect(dryStep.wet).toBeLessThan(peakStep.wet)
			local _eq, reverb = effectsOf("SFX")
			expect(reverb.WetLevel).toBe(sfx.effects.reverb.wet)
			SfxPool.contour("ShatterBloom")
			w.frame(peakStep.at + peakStep.ramp + EPSILON)
			local peak = reverb.WetLevel
			expect(peak).toBeCloseTo(peakStep.wet, 1e-6)
			expect(peak).toBeGreaterThan(sfx.effects.reverb.wet)
			-- Drying: strictly between the peak and the floor, falling frame after frame.
			local previous = peak
			for quarter = 1, 3 do
				w.frame(dryStep.at + dryStep.ramp * quarter / 4)
				expect(reverb.WetLevel).toBeLessThan(previous)
				expect(reverb.WetLevel).toBeGreaterThan(sfx.effects.reverb.wet)
				previous = reverb.WetLevel
			end
			local last = 0
			for _, step in sfx.contour("ShatterBloom") do
				last = math.max(last, step.at + step.ramp)
			end
			w.frame(last + EPSILON)
			w.frame(last + sfx.effects.restoreSeconds + EPSILON * 2)
			expect(reverb.WetLevel).toBe(sfx.effects.reverb.wet)
			expect(reverb.DryLevel).toBe(sfx.effects.reverb.dry)
		end)
	end)

	it("a new contour takes over only the keys it names; the older one keeps the rest", function()
		withContours({
			SpecA = {
				{ at = 0, group = "SFX", wet = -10, ramp = 0 },
				{ at = 0, group = "SFX", low = -12, ramp = 0 },
				{ at = 0.5, group = "SFX", wet = -20, ramp = 0 },
				{ at = 0, group = "Music", mid = -6, ramp = 0 },
				{ at = 0.5, group = "Music", mid = -9, ramp = 0 },
			},
			SpecB = {
				{ at = 0, group = "SFX", high = -6, ramp = 0 },
				{ at = 1, group = "SFX", high = 0, ramp = 0 },
			},
			SpecC = {
				{ at = 0, group = "SFX", low = -3, ramp = 0.1 },
			},
		}, function()
			scenario(function(w)
				SfxPool.contour("SpecA")
				local sfxState = SfxPool.mixState("SFX") :: any
				expect(sfxState.wet).toBe(-10)
				expect(sfxState.low).toBe(-12)
				w.frame(0.2)
				SfxPool.contour("SpecB")
				local shared = SfxPool.mixState("SFX") :: any
				expect(shared.running).toBe("SpecB")
				expect(shared.high).toBe(-6)
				-- B names only the highs: A keeps its bass cut and its reverb.
				expect(shared.low).toBe(-12)
				expect(shared.wet).toBe(-10)
				expect(shared.owners).toEqual({ low = "SpecA", wet = "SpecA", high = "SpecB" })
				expect((SfxPool.mixState("Music") :: any).running).toBe("SpecA")

				-- C takes the bass from A; its ramp starts where A left it, never from the default.
				w.frame(0.25)
				SfxPool.contour("SpecC")
				expect((SfxPool.mixState("SFX") :: any).owners.low).toBe("SpecC")
				w.frame(0.3)
				local ease = Easing.get(sfx.effects.easing)
				expect((SfxPool.mixState("SFX") :: any).low).toBeCloseTo(-12 + 9 * ease(0.5), 1e-6)
				-- A's late step still fires on the keys it kept.
				w.frame(0.5 + EPSILON)
				expect((SfxPool.mixState("SFX") :: any).wet).toBe(-20)
				expect((SfxPool.mixState("SFX") :: any).low).toBe(-3)
				expect((SfxPool.mixState("Music") :: any).mid).toBe(-9)

				-- A is done: it eases the key it still owns (the reverb) back; C keeps the bass.
				w.frame(0.5 + sfx.effects.restoreSeconds + EPSILON)
				local afterA = SfxPool.mixState("SFX") :: any
				expect(afterA.wet).toBe(sfx.effects.reverb.wet)
				expect(afterA.owners.wet).toBeNil()

				-- B's own steps run from B's start.
				w.frame(0.2 + 1 - EPSILON)
				expect((SfxPool.mixState("SFX") :: any).high).toBe(-6)
				w.frame(0.2 + 1 + EPSILON)
				expect((SfxPool.mixState("SFX") :: any).high).toBe(0)
				w.frame(1.4)
				w.frame(1.6)
				local idleState = SfxPool.mixState("SFX") :: any
				expect(idleState.running).toBeNil()
				expect(idleState.enabled).toBe(false)
				expect(idleState.low).toBe(0)
				expect((SfxPool.mixState("Music") :: any).mid).toBe(0)
				expect(w.steppers).toBe(0)
			end)
		end)
	end)

	it("keeps an Art's bass cut when a nearby death's shatter blooms the reverb", function()
		scenario(function(w)
			local cut, back = cutAndBack("FinalHit", "SFX", "low")
			SfxPool.contour("FinalHit")
			w.frame(cut.at + cut.ramp + EPSILON)
			SfxPool.contour("ShatterBloom")
			w.frame(back.at - EPSILON)
			expect((SfxPool.mixState("SFX") :: any).low).toBeCloseTo(cut.low, 1e-6)
			expect((SfxPool.mixState("SFX") :: any).wet).toBeGreaterThan(sfx.effects.reverb.wet)
			w.frame(back.at + back.ramp + EPSILON)
			expect((SfxPool.mixState("SFX") :: any).low).toBe(0)
		end)
	end)

	it("has the bass back when every moment's sub-bass layer plays under its contour", function()
		local subs: { [string]: boolean } = {}
		for _, name in sfx.limits.subLayers do
			subs[name] = true
		end
		local pairs = 0
		for _, momentName in moments.list() do
			local row = moments.byId(momentName)
			if row.cue == nil or row.contour == nil then
				continue
			end
			for _, layer in sfx.cue(row.cue) do
				if not subs[layer.name] then
					continue
				end
				pairs += 1
				scenario(function(w)
					local family = layer.name:match("^([^%.]+)%.") :: string
					local group = sfx.groupOf(family)
					SfxPool.contour(row.contour)
					w.frame(dueAt(layer.delay) + 1e-9)
					local state = SfxPool.mixState(group)
					if state ~= nil then
						expect(state.low).toBeGreaterThanOrEqual(sfx.limits.bassBackDb)
					end
				end)
			end
		end
		expect(pairs).toBeGreaterThan(0)
	end)

	it("brings the music's highs back on WindUpRelease, under a bass cut that keeps running", function()
		scenario(function(w)
			local cut = cutAndBack("WindUp", "Music", "high")
			expect(cut).never.toBeNil()
			SfxPool.contour("WindUp")
			w.frame(cut.at + cut.ramp + EPSILON)
			expect((SfxPool.mixState("Music") :: any).high).toBeCloseTo(cut.high, 1e-6)
			SfxPool.contour("FinalHit")
			-- FinalHit names only the bass: the wind-up's highs stay out until the release.
			w.frame(cut.at + cut.ramp + 2 * EPSILON)
			expect((SfxPool.mixState("Music") :: any).high).toBeCloseTo(cut.high, 1e-6)
			SfxPool.contour("WindUpRelease")
			expect((SfxPool.mixState("Music") :: any).owners.high).toBe("WindUpRelease")
			local release = 0
			for _, step in sfx.contour("WindUpRelease") do
				release = math.max(release, step.at + step.ramp)
			end
			w.frame(cut.at + cut.ramp + 2 * EPSILON + release + EPSILON)
			local music = SfxPool.mixState("Music") :: any
			expect(music.high).toBe(0)
			expect(music.owners.low).toBe("FinalHit")
			-- The wind-up lost its only key: its safety step never fires.
			local safety = 0
			for _, step in sfx.contour("WindUp") do
				safety = math.max(safety, step.at + step.ramp)
			end
			w.frame(safety + 0.5)
			expect((SfxPool.mixState("Music") :: any).high).toBe(0)
			expect((SfxPool.mixState("Music") :: any).running).toBeNil()
		end)
	end)

	it("eases a contour that ends off the defaults back to them", function()
		withContours({ SpecLeave = { { at = 0, group = "Master", mid = -6, high = -3, ramp = 0 } } }, function()
			scenario(function(w)
				SfxPool.contour("SpecLeave")
				local eq = effectsOf("Master")
				expect(eq.MidGain).toBe(-6)
				w.frame(0)
				w.frame(sfx.effects.restoreSeconds / 4)
				expect(eq.MidGain).toBeGreaterThan(-6)
				expect(eq.MidGain).toBeLessThan(0)
				w.frame(sfx.effects.restoreSeconds + EPSILON)
				expect(eq.MidGain).toBe(0)
				expect(eq.HighGain).toBe(0)
				w.frame(sfx.effects.restoreSeconds * 2)
				expect((SfxPool.mixState("Master") :: any).enabled).toBe(false)
				expect(eq.Enabled).toBe(true)
			end)
		end)
	end)

	it("chains two steps on one key that a long frame fires together", function()
		withContours({
			SpecChain = {
				{ at = 0, group = "SFX", low = -40, ramp = 0.1 },
				{ at = 0.2, group = "SFX", low = 0, ramp = 0.1 },
			},
		}, function()
			scenario(function(w)
				SfxPool.contour("SpecChain")
				-- One 250 ms hitch: the second ramp starts from -40 (where the first had landed).
				w.frame(0.25)
				local ease = Easing.get(sfx.effects.easing)
				expect((SfxPool.mixState("SFX") :: any).low).toBeCloseTo(-40 + 40 * ease(0.5), 1e-6)
			end)
		end)
	end)

	it("lands the kill's bass back at the end of the kill's hit-stop", function()
		scenario(function(w)
			local hold = combat.hitStopFrames.Kill * combat.hitStopFrameSeconds
			local cut, back = cutAndBack("KillCut", "SFX", "low")
			local musicCut = cutAndBack("KillCut", "Music", "low")
			expect(cut).never.toBeNil()
			expect(back).never.toBeNil()
			expect(back.at).toBeCloseTo(hold, 1e-9)
			SfxPool.contour("KillCut")
			w.frame(cut.at + cut.ramp + EPSILON)
			expect((SfxPool.mixState("SFX") :: any).low).toBeCloseTo(cut.low, 1e-6)
			if musicCut ~= nil then
				expect((SfxPool.mixState("Music") :: any).low).toBeCloseTo(musicCut.low, 1e-6)
			end
			w.frame(hold - EPSILON)
			expect((SfxPool.mixState("SFX") :: any).low).toBeCloseTo(cut.low, 1e-6)
			w.frame(hold + back.ramp + EPSILON)
			expect((SfxPool.mixState("SFX") :: any).low).toBe(0)
		end)
	end)
end)

describe("SfxPool: an Art's final hit cuts the bass on its own call (F15)", function()
	-- The reel review heard the FinalHit's bass for the first 3 frames of the freeze: the effects
	-- were switched in on the hit's call and the 8 ms cut only landed on the next step.
	it("has the flat EQ in before the hit and the cut in place when the hit's call returns", function()
		scenario(function(w)
			SfxPool.start()
			local cuts: { [string]: number } = {}
			for _, step in sfx.contour("FinalHit") do
				if step.at == 0 and step.low ~= nil then
					cuts[step.group] = step.low
				end
			end
			expect(cuts.SFX).never.toBeNil()
			for group in cuts do
				local eq = effectsOf(group)
				expect(eq.Enabled).toBe(true)
				expect(eq.LowGain).toBe(0)
			end
			-- The impact director's order: the cue, then the contour, on one call.
			SfxPool.asOwn(function()
				SfxPool.cue("HitFinal", HIT)
				SfxPool.contour("FinalHit")
			end)
			local playedAt = #w.plays
			expect(playedAt).toBeGreaterThan(0)
			for group, low in cuts do
				local eq = effectsOf(group)
				expect(eq.Enabled).toBe(true)
				expect(eq.LowGain).toBeCloseTo(low, 1e-6)
			end
			-- And it holds through the first frames of the freeze.
			for frame = 1, 3 do
				w.frame(frame * sfx.playback.sameFrameSeconds)
				expect(effectsOf("SFX").LowGain).toBeCloseTo(cuts.SFX, 1e-6)
			end
		end)
	end)

	it("still eases a cut whose ramp spans frames, from the call on", function()
		withContours({ SpecSlowCut = { { at = 0, group = "SFX", low = -30, ramp = 0.1 } } }, function()
			scenario(function(w)
				SfxPool.contour("SpecSlowCut")
				expect((SfxPool.mixState("SFX") :: any).low).toBe(0)
				w.frame(0.025)
				local ease = Easing.get(sfx.effects.easing)
				expect((SfxPool.mixState("SFX") :: any).low).toBeCloseTo(-30 * ease(0.25), 1e-6)
			end)
		end)
	end)
end)

describe("SfxPool: the low-HP heartbeat ducks under the local player's own hits (F15)", function()
	local duck = sfx.mix.heartbeatDuck
	local function ducked(full: number, db: number): number
		return full * 10 ^ (-db / 20)
	end

	it("ducks on the hit's own call, holds, and comes back over the release", function()
		scenario(function(w)
			local name = fx.audio.heartbeatLoop
			withReal({ name }, function()
				SfxPool.loop(name, 1)
				local sound = w.plays[1].sound
				local full = sound.Volume
				expect(full).toBeGreaterThan(0)
				-- A hit the local player is not in leaves the heartbeat alone.
				SfxPool.cue("HitNormal", HIT)
				expect(sound.Volume).toBeCloseTo(full, FLOAT)
				-- An enemy's hit on the player (the impact director marks it own): down at once.
				SfxPool.asOwn(function()
					SfxPool.cue("HitNormal", FAR)
				end)
				expect(sound.Volume).toBeCloseTo(ducked(full, duck.db), FLOAT)
				-- The music director's per-frame loop call keeps the duck.
				SfxPool.loop(name, 1)
				expect(sound.Volume).toBeCloseTo(ducked(full, duck.db), FLOAT)
				w.frame(duck.holdSeconds - EPSILON)
				expect(sound.Volume).toBeCloseTo(ducked(full, duck.db), FLOAT)
				-- Coming back: between the duck and full, rising frame after frame.
				local previous = sound.Volume
				for quarter = 1, 3 do
					w.frame(duck.holdSeconds + duck.releaseSeconds * quarter / 4)
					expect(sound.Volume).toBeGreaterThan(previous)
					expect(sound.Volume).toBeLessThan(full)
					previous = sound.Volume
				end
				w.frame(duck.holdSeconds + duck.releaseSeconds + EPSILON)
				expect(sound.Volume).toBeCloseTo(full, FLOAT)
				SfxPool.loop(name, 1)
				expect(sound.Volume).toBeCloseTo(full, FLOAT)
			end)
		end)
	end)

	it("ducks only for the listed cues, and only the heartbeat", function()
		spec(function(w)
			local name = fx.audio.heartbeatLoop
			withReal({ name }, function()
				for _, cueName in duck.cues do
					expect(sfx.cues[cueName]).never.toBeNil()
				end
				SfxPool.loop(name, 1)
				SfxPool.loop("spec.Bed", 1)
				local heart, bed = w.plays[1].sound, w.plays[2].sound
				local fullHeart, fullBed = heart.Volume, bed.Volume
				-- Not a hit: the player's own dodge leaves it alone.
				SfxPool.asOwn(function()
					SfxPool.cue("Dodge", HIT)
				end)
				expect(heart.Volume).toBeCloseTo(fullHeart, FLOAT)
				SfxPool.asOwn(function()
					SfxPool.cue(duck.cues[1], HIT)
				end)
				expect(heart.Volume).toBeCloseTo(ducked(fullHeart, duck.db), FLOAT)
				expect(bed.Volume).toBeCloseTo(fullBed, FLOAT)
			end)
		end)
	end)

	it("restarts the hold on the next hit and starts a heartbeat that rises inside a duck ducked", function()
		scenario(function(w)
			local name = fx.audio.heartbeatLoop
			withReal({ name }, function()
				SfxPool.asOwn(function()
					SfxPool.cue("HitNormal", HIT)
				end)
				SfxPool.loop(name, 1)
				local heart = w.plays[#w.plays].sound
				local entry = entryOf(name)
				local full = math.min(entry.volume * 10 ^ (sfx.mix.heartbeatOverAllDb / 20), sfx.limits.maxPlayVolume)
				expect(heart.Volume).toBeCloseTo(ducked(full, duck.db), FLOAT)
				local second = duck.holdSeconds * 0.75
				w.frame(second)
				SfxPool.asOwn(function()
					SfxPool.cue("HitBasic", FAR)
				end)
				w.frame(second + duck.holdSeconds - EPSILON)
				expect(heart.Volume).toBeCloseTo(ducked(full, duck.db), FLOAT)
				w.frame(second + duck.holdSeconds + duck.releaseSeconds + EPSILON)
				expect(heart.Volume).toBeCloseTo(full, FLOAT)
			end)
		end)
	end)
end)

describe("SfxPool death silence: the local player's own sounds play through it (issue 9)", function()
	local function groups(): (any, any, any)
		SfxPool.start()
		return SfxPool.group("SFX"), SfxPool.group(fx.audio.ownGroupName), SfxPool.group("UI")
	end

	it("inside a death's silence a play marked own starts in the carve-out at full; the rest stay ducked", function()
		spec(function(w)
			local sfxGroup, own, ui = groups()
			expect(own).never.toBeNil()
			local base = fx.audio.groupVolumes.SFX
			expect(own.Volume).toBeCloseTo(base, FLOAT)
			SfxPool.duck(combat.deathDuckDb, combat.deathFreeze, true)
			expect(sfxGroup.Volume).toBeLessThan(base * 0.1)
			expect(ui.Volume).toBeLessThan(fx.audio.groupVolumes.UI * 0.1)
			-- No duck lowers the carve-out.
			expect(own.Volume).toBeCloseTo(base, FLOAT)
			SfxPool.asOwn(function()
				SfxPool.play("spec.Plain", HIT)
			end)
			SfxPool.play("spec.Flat")
			expect(w.names()).toEqual({ "spec.Plain", "spec.Flat" })
			expect(w.plays[1].group).toBe(own)
			expect(w.plays[2].group).toBe(sfxGroup)
		end)
	end)

	it("a cue marked own keeps every layer in the carve-out, the delayed ones too", function()
		spec(function(w)
			local _, own = groups()
			SfxPool.duck(combat.deathDuckDb, combat.deathFreeze, true)
			SfxPool.asOwn(function()
				SfxPool.cue("SpecLanding", HIT)
			end)
			w.run(0.3)
			expect(w.names()).toEqual({ "spec.Swish", "spec.Plain" })
			for _, play in w.plays do
				expect(play.group).toBe(own)
			end
		end)
	end)

	it("only a sound started inside the silence: before it, and once it ends, own plays stay in SFX", function()
		spec(function(w)
			local sfxGroup, own = groups()
			-- The kill's own crack, before the silence: the silence chops its tail.
			SfxPool.asOwn(function()
				SfxPool.play("spec.Plain", HIT)
			end)
			SfxPool.duck(combat.deathDuckDb, combat.deathFreeze, true)
			SfxPool.asOwn(function()
				SfxPool.play("spec.Plain", FAR)
			end)
			w.run(combat.deathFreeze + EPSILON)
			expect(sfxGroup.Volume).toBeCloseTo(fx.audio.groupVolumes.SFX, FLOAT)
			SfxPool.asOwn(function()
				SfxPool.play("spec.Flat")
			end)
			expect(w.names()).toEqual({ "spec.Plain", "spec.Plain", "spec.Flat" })
			expect(w.plays[1].group).toBe(sfxGroup)
			expect(w.plays[2].group).toBe(own)
			expect(w.plays[3].group).toBe(sfxGroup)
			-- A pooled voice an own play used goes back to its family's group on its next play.
			SfxPool.play("spec.Plain", FAR + FAR)
			for _, play in playsOf(w, "spec.Plain") do
				if play.time > combat.deathFreeze then
					expect(play.group).toBe(sfxGroup)
				end
			end
		end)
	end)

	it("a new duck takes the silence over: a restore (0 dB) ends the carve-out at once", function()
		spec(function(w)
			local sfxGroup, own = groups()
			SfxPool.duck(combat.deathDuckDb, combat.deathFreeze, true)
			SfxPool.duck(0, 0)
			SfxPool.asOwn(function()
				SfxPool.play("spec.Flat")
			end)
			expect(w.plays[1].group).toBe(sfxGroup)
			-- The next kill's silence carves out again.
			SfxPool.duck(combat.deathDuckDb, combat.deathFreeze, true)
			SfxPool.asOwn(function()
				SfxPool.play("spec.Plain", HIT)
			end)
			expect(w.plays[2].group).toBe(own)
		end)
	end)

	it("a duck that spares nothing (the system voice) and a UI sound marked own stay ducked", function()
		spec(function(w)
			local sfxGroup, _, ui = groups()
			SfxPool.duck(sfx.mix.systemVoiceDuckDb, 1)
			SfxPool.asOwn(function()
				SfxPool.play("spec.Flat")
			end)
			expect(w.plays[1].group).toBe(sfxGroup)
			SfxPool.duck(0, 0)
			sfx.families.specUi = { group = "UI", entries = { Click = specEntries().Flat } }
			local ok, err = pcall(function()
				SfxPool.duck(combat.deathDuckDb, combat.deathFreeze, true)
				SfxPool.asOwn(function()
					SfxPool.play("specUi.Click")
				end)
				expect(w.plays[2].group).toBe(ui)
			end)
			sfx.families.specUi = nil
			if not ok then
				error(err, 0)
			end
		end)
	end)

	it("the SFX slider moves the carve-out with it; an error inside asOwn leaves nothing marked", function()
		spec(function(w)
			local sfxGroup, own = groups()
			SfxPool.setGroupVolume("SFX", 0.5)
			expect(own.Volume).toBeCloseTo(sfxGroup.Volume, FLOAT)
			SfxPool.setGroupVolume("SFX", 1)
			SfxPool.duck(combat.deathDuckDb, combat.deathFreeze, true)
			local ok = pcall(SfxPool.asOwn, function()
				error("boom")
			end)
			expect(ok).toBe(false)
			SfxPool.play("spec.Flat")
			expect(w.plays[1].group).toBe(sfxGroup)
		end)
	end)
end)
