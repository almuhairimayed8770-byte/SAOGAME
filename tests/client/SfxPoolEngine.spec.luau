--!strict
-- SfxPool against the measured Sound engine model (Harness.SoundEngine, Studio 2026-10-23): every
-- play of every real sfx.luau entry starts inside its PlaybackRegion as the engine holds it
-- (fact b, float32 ends), the engine's Ended for a timed one-shot comes when the pool's own clock
-- frees it (fact a), a late start is freed by that Ended, a loop's first pass starts at startAt
-- (fact c), and the low-HP heartbeat keeps its rhythm through hits (MusicDirector -> SfxPool.loop,
-- frame by frame).
local SoundEngine = Harness.SoundEngine

local sfx = Harness.load("src/shared/data/sfx")
local fx = Harness.load("src/shared/data/fx")
local Engine = Harness.load("src/client/fx/Engine")
local SfxPool = Harness.load("src/client/audio/SfxPool")
local MusicDirector = Harness.load("src/client/audio/MusicDirector")

local DT = 1 / 60
local HIT = Vector3.new(4, 3, -6)

type Pending = { at: number, order: number, fn: () -> () }

type World = {
	now: number,
	engine: any,
	pending: { Pending },
	steps: { [number]: (number) -> () },
	frame: () -> (),
	runTo: (t: number) -> (),
}

-- A world on 60 fps frames: each frame runs the delays due by its end, steps the engine, then the
-- pool's per-frame step (fades), the order Heartbeat gives them in the game. Every real entry's
-- library length is the engine's TimeLength for it, so a long bed is not cut at the default.
local function world(onPlay: ((sound: any) -> ())?): World
	local order = 0
	local stepId = 0
	local w: World = {
		now = 0,
		engine = SoundEngine.new(),
		pending = {},
		steps = {},
		frame = nil :: any,
		runTo = nil :: any,
	}
	local function runDue(t: number)
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
				return
			end
			local item = table.remove(w.pending, best :: number) :: Pending
			w.now = math.max(w.now, item.at)
			item.fn()
		end
	end
	function w.frame()
		local t = w.now + DT
		runDue(t)
		w.now = t
		w.engine.step(DT)
		local fns = {}
		for _, fn in w.steps do
			table.insert(fns, fn)
		end
		for _, fn in fns do
			fn(DT)
		end
	end
	function w.runTo(t: number)
		while w.now + DT <= t + 1e-9 do
			w.frame()
		end
	end
	for familyName, family in sfx.families do
		for entryName, entry in family.entries do
			if entry.length ~= nil then
				w.engine.lengths[familyName .. "." .. entryName] = entry.length
			end
		end
	end
	SfxPool.reset()
	SfxPool.bind({
		now = function()
			return w.now
		end,
		delay = function(seconds: number, fn: () -> ())
			order += 1
			table.insert(w.pending, { at = w.now + seconds, order = order, fn = fn })
		end,
		onStep = function(fn: (number) -> ()): () -> ()
			stepId += 1
			local id = stepId
			w.steps[id] = fn
			return function()
				w.steps[id] = nil
			end
		end,
		play = function(sound: any): boolean
			if onPlay ~= nil then
				onPlay(sound)
			end
			return w.engine.play(sound)
		end,
		stop = w.engine.stop,
		isPlaying = w.engine.isPlaying,
		onEnded = w.engine.onEnded,
		timeLength = w.engine.timeLength,
		preload = function(_sounds: { Instance }) end,
	} :: any)
	Engine.setClock(function()
		return w.now
	end)
	return w
end

local function done()
	SfxPool.reset()
	SfxPool.bind(nil)
	Engine.setClock(nil)
end

local function realNames(): { string }
	local names = {}
	for familyName, family in sfx.families do
		for entryName, entry in family.entries do
			if sfx.isReal(entry) then
				table.insert(names, familyName .. "." .. entryName)
			end
		end
	end
	table.sort(names)
	return names
end

local function entryOf(name: string): any
	local family, entryName = name:match("^([^%.]+)%.(.+)$")
	return sfx.get(family :: string, entryName :: string)
end

local function describeViolations(engine: any): string
	local lines = {}
	for _, v in engine.violations do
		table.insert(
			lines,
			("%s %s at TimePosition %.9f, region %.9f..%.9f, t=%.3f"):format(
				v.sound.Name,
				v.kind,
				v.timePosition,
				v.min,
				v.max,
				v.at
			)
		)
	end
	return table.concat(lines, "\n")
end

describe("SfxPool on the measured engine: every start inside the region (fact b)", function()
	it("starts every real one-shot inside its PlaybackRegion, and it is playing a frame later", function()
		local w = world()
		local silent = {}
		for index, name in realNames() do
			if entryOf(name).loop then
				continue
			end
			w.runTo(index * 3)
			local sound = SfxPool.play(name, HIT)
			w.frame()
			if sound ~= nil and not w.engine.isPlaying(sound) then
				table.insert(silent, name)
			end
		end
		local report = describeViolations(w.engine)
		done()
		expect(report).toBe("")
		expect(table.concat(silent, ", ")).toBe("")
	end)

	it("starts every playLate inside the region for any lateBy up to the region's end", function()
		local w = world()
		local t = 0
		for _, name in realNames() do
			local entry = entryOf(name)
			if entry.loop then
				continue
			end
			local first, last = sfx.region(entry)
			local span = last - first
			-- 1 - 1e-16 lands a double start between the float32 region end and stopAt.
			for _, fraction in { 0.001, 0.25, 0.5, 0.9, 0.999, 1 - 1e-8, 1 - 1e-16, 1 } do
				t += 3
				w.runTo(t)
				-- The slowest speed in the range stretches lateBy the most.
				SfxPool.playLate(name, span * fraction / 0.5, HIT)
				SfxPool.playLate(name, span * fraction, HIT)
			end
		end
		local report = describeViolations(w.engine)
		done()
		expect(report).toBe("")
	end)

	it("starts every riser inside the region, on time and when its delay resumes late", function()
		local w = world()
		local t = 0
		for _, name in realNames() do
			local entry = entryOf(name)
			if entry.loop then
				continue
			end
			local first, last = sfx.region(entry)
			local span = last - first
			for _, seconds in { 0.001, span * 0.5, span, span + 0.01, span + 0.2, 2 } do
				t += 5
				w.runTo(t)
				SfxPool.playEndingAt(name, seconds, HIT)
			end
		end
		w.runTo(t + 5)
		local report = describeViolations(w.engine)
		done()
		expect(report).toBe("")
	end)

	it("plays nothing, and frees the voice, when a riser's wait resumes past its whole region", function()
		local w = world()
		local held = {}
		for _, name in realNames() do
			local entry = entryOf(name)
			if entry.loop then
				continue
			end
			local first, last = sfx.region(entry)
			local span = last - first
			local t = w.now + 1
			w.runTo(t)
			local before = #w.pending
			local sound = SfxPool.playEndingAt(name, span * 2 + 0.2, HIT)
			if sound == nil then
				continue
			end
			-- The engine resumes the start's wait a whole region late (a long hitch).
			for index = before + 1, #w.pending do
				w.pending[index].at += span * 2
			end
			-- Past the slipped start, the release delay and a frame.
			w.runTo(t + 4 * span + 0.5 + fx.audio.emitterReleaseDelay)
			-- Its voice and emitter are free again: the next play takes the same Sound.
			if SfxPool.play(name, HIT) ~= sound then
				table.insert(held, name)
			end
		end
		local report = describeViolations(w.engine)
		done()
		expect(report).toBe("")
		expect(table.concat(held, ", ")).toBe("")
	end)

	it("starts every cue layer inside its region for any catch-up lateness", function()
		local w = world()
		local t = 0
		for _, cueName in sfx.cueNames() do
			for _, lateBy in { 0, 0.01, 0.1, 0.3, 1, 3 } do
				t += 5
				w.runTo(t)
				SfxPool.cue(cueName, HIT, lateBy)
			end
		end
		w.runTo(t + 5)
		local report = describeViolations(w.engine)
		done()
		expect(report).toBe("")
	end)
end)

describe("SfxPool on the measured engine: region ends (fact a)", function()
	it("hears the engine's Ended for a timed one-shot within a frame of the pool's own clock", function()
		local w = world()
		local worst = 0
		local worstName = ""
		for index, name in realNames() do
			local entry = entryOf(name)
			if entry.loop then
				continue
			end
			w.runTo(index * 5)
			local sound = SfxPool.play(name)
			if sound == nil then
				continue
			end
			local state = w.engine.stateOf(sound)
			local before = #state.endedAt
			local started = w.now
			w.runTo(started + 4)
			local endedAt = state.endedAt[before + 1]
			expect(endedAt).never.toBeNil()
			-- The pool frees the voice (stopAt - startAt) / PlaybackSpeed after Play.
			local first, last = sfx.region(entry)
			local gap = math.abs((endedAt - started) - (last - first) / sound.PlaybackSpeed)
			if gap > worst then
				worst = gap
				worstName = name
			end
		end
		done()
		expect(if worst <= DT + 1e-9 then "" else worstName .. " " .. tostring(worst)).toBe("")
	end)

	it("frees a late start (asset still loading) through the Ended it gets at the region end", function()
		local w = world()
		local name = "whoosh.Small"
		w.engine.lengths[name] = 0 -- loading: the pool plays it untimed
		local first = SfxPool.play(name, HIT) :: any
		expect(first).never.toBeNil()
		expect(SfxPool.stats().lateStarts).toBe(1)
		w.engine.lengths[name] = 0.965 -- it arrives; the engine plays the region
		-- Its region in real time at this play's speed (the pick is random in the pitch range).
		local over = 0.32 / first.PlaybackSpeed + DT
		w.runTo(over)
		expect(w.engine.isPlaying(first)).toBe(false)
		w.runTo(over + fx.audio.emitterReleaseDelay + DT)
		-- Ended freed it and its emitter: the next play takes the same voice.
		expect(SfxPool.play(name, HIT)).toBe(first)
		done()
	end)
end)

describe("SfxPool on the measured engine: loops (fact c)", function()
	it("starts every loop's first pass at startAt and wraps it inside startAt .. stopAt", function()
		local loops = 0
		for _, name in realNames() do
			local entry = entryOf(name)
			if not entry.loop then
				continue
			end
			loops += 1
			local recorded: any = nil
			local w = world(function(sound: any)
				recorded = { sound = sound, timePosition = sound.TimePosition }
			end)
			SfxPool.loop(name, 1)
			expect(recorded).never.toBeNil()
			local first, last = sfx.region(entry)
			expect(recorded.timePosition).toBeCloseTo(first, 1e-6)
			local period = (last - first) / recorded.sound.PlaybackSpeed
			w.runTo(period * 3 + 0.5)
			local state = w.engine.stateOf(recorded.sound)
			local report = describeViolations(w.engine)
			SfxPool.loop(name, 0)
			done()
			expect(report).toBe("")
			expect(#state.wraps).toBeGreaterThanOrEqual(3)
			for index = 2, #state.wraps do
				expect(state.wraps[index] - state.wraps[index - 1]).toBeCloseTo(period, DT + 1e-9)
			end
		end
		expect(loops).toBeGreaterThan(0)
	end)
end)

describe("the low-HP heartbeat keeps its rhythm through hits", function()
	it("plays once and wraps every (stopAt - startAt) / speed while hits land below a quarter HP", function()
		local name = fx.audio.heartbeatLoop
		local heartbeat: any = nil
		local plays = 0
		local w = world(function(sound: any)
			if sound.Name == name then
				heartbeat = sound
				plays += 1
			end
		end)
		local first, last = sfx.region(entryOf(name))
		MusicDirector.start() -- idempotent; Lune has no Heartbeat, so this spec calls update itself
		MusicDirector.setLowHp(true)
		-- 12 s at 60 fps; a "hit" every 0.7 s (the Hud calls setLowHp on every HP change), a heal
		-- above a quarter at 6 s and a hit back under it 0.5 s later.
		local nextHit = 0.7
		local jumps = {}
		local lastPosition: number? = nil
		while w.now < 12 do
			w.frame()
			if w.now >= nextHit then
				nextHit += 0.7
				MusicDirector.setLowHp(true)
			end
			if w.now >= 6 and w.now < 6 + DT then
				MusicDirector.setLowHp(false)
			end
			if w.now >= 6.5 and w.now < 6.5 + DT then
				MusicDirector.setLowHp(true)
			end
			MusicDirector.update()
			if heartbeat ~= nil then
				local position = heartbeat.TimePosition
				if lastPosition ~= nil and position < (lastPosition :: number) then
					table.insert(jumps, { at = w.now, from = lastPosition, to = position })
				end
				lastPosition = position
			end
		end
		MusicDirector.setLowHp(false)
		MusicDirector.stop()
		local violations = describeViolations(w.engine)
		local period = (last - first) / (if heartbeat ~= nil then heartbeat.PlaybackSpeed else 1)
		done()
		expect(plays).toBe(1)
		expect(violations).toBe("")
		expect(#jumps).toBeGreaterThan(8)
		for index = 2, #jumps do
			-- Every backward jump is a wrap from just under stopAt to just over startAt, a period apart.
			expect(jumps[index].at - jumps[index - 1].at).toBeCloseTo(period, DT + 1e-9)
			expect(jumps[index].from).toBeGreaterThan(last - DT - 1e-9)
			expect(jumps[index].to).toBeLessThan(first + DT + 1e-9)
		end
	end)
end)
