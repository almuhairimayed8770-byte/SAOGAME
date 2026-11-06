--!strict
--[[
	SoundEngine: the engine's Sound playback as measured in Studio Play on 2026-10-23 (build
	f7b0722; rbxassetid://9119749145 = whoosh.Small, TimeLength 0.965 s), for specs that bind
	SfxPool's seams (play, stop, isPlaying, onEnded, timeLength) to it and step it frame by frame.
	Lune's Instance has properties only, so without this model nothing advances TimePosition,
	wraps a loop or fires Ended.

	Measured, and modelled:
	(a) PlaybackRegionsEnabled, PlaybackRegion 0 .. 0.32, not Looped: Ended fires when the
	    playhead reaches PlaybackRegion.Max (0.316 s after Play at 60 fps; the last TimePosition
	    read while playing was 0.299) and IsPlaying is false from then. The playhead runs from
	    Play itself.
	(b) Play with TimePosition at or past PlaybackRegion.Max (0.6 against 0 .. 0.32): nothing
	    plays. TimePosition reads 0 and IsPlaying stays false (6 Heartbeats). Recorded as a
	    "pastEnd" violation.
	(c) Looped with LoopRegion 0.05 .. 0.25: the first pass runs from the TimePosition Play found
	    (0, under LoopRegion.Min); every later pass wraps from LoopRegion.Max to LoopRegion.Min.
	(d) PlaybackLoudness reads 0 for the first two frames after Play and is live from the third.

	Region ends are float32: the engine holds a NumberRange in float32 (Lune too: 0.22 reads
	back as 0.2199999988), while TimePosition is a double. The model compares against the
	NumberRange it reads, so a start between the float32 Max and a double stopAt is refused, as
	in the engine.

	Not measured. The model records these as `violations` instead of guessing, so a spec that
	leans on them fails rather than passing on a guess:
	- Play with TimePosition under PlaybackRegion.Min by more than a float32 rounding, recorded
	  as "beforeStart (not measured)". (Within a rounding it plays: ui.LowHpHeartbeat starts
	  7e-9 under its float32 Min and was seen looping in Studio.)
	Assumed from the API reference, not measured: Stop sets IsPlaying false and TimePosition 0
	and fires no Ended; TimePosition reads 0 after Ended (no spec should read it there).
]]

export type Violation = {
	sound: any,
	kind: string, -- "pastEnd" | "beforeStart (not measured)"
	timePosition: number,
	min: number,
	max: number,
	at: number,
}

export type State = {
	playing: boolean,
	frames: number, -- frames stepped since Play (PlaybackLoudness is live from the third)
	firstPass: boolean,
	plays: number,
	wraps: { number }, -- engine times of every loop wrap
	ended: { () -> () },
	endedAt: { number }, -- engine times of every Ended
}

export type SoundEngine = {
	now: number,
	violations: { Violation },
	lengths: { [any]: number }, -- TimeLength by Sound name or by Sound; defaultLength otherwise
	defaultLength: number,
	play: (sound: any) -> boolean,
	stop: (sound: any) -> (),
	isPlaying: (sound: any) -> boolean,
	onEnded: (sound: any, fn: () -> ()) -> (() -> ())?,
	timeLength: (sound: any) -> number,
	loudness: (sound: any) -> number,
	step: (dt: number) -> (),
	stateOf: (sound: any) -> State,
}

-- One float32 ulp at 1 s is 1.2e-7: a TimePosition this close under the region's Min is the same
-- point once the engine rounds the NumberRange to float32.
local FLOAT32_SLACK = 1e-6
-- Frames after Play that PlaybackLoudness still reads 0 (fact d).
local SILENT_FRAMES = 2
local DEFAULT_LENGTH = 30

local SoundEngine = {}

--- A fresh engine at time 0 with no Sounds playing.
function SoundEngine.new(): SoundEngine
	local states: { [any]: State } = setmetatable({}, { __mode = "k" }) :: any
	local engine: SoundEngine = nil :: any

	local function stateOf(sound: any): State
		local state = states[sound]
		if state == nil then
			local fresh: State =
				{ playing = false, frames = 0, firstPass = true, plays = 0, wraps = {}, ended = {}, endedAt = {} }
			states[sound] = fresh
			return fresh
		end
		return state
	end

	local function lengthOf(sound: any): number
		return engine.lengths[sound.Name] or engine.lengths[sound] or engine.defaultLength
	end

	-- Where the playhead stops (or wraps) this pass.
	local function endOf(sound: any): number
		local length = lengthOf(sound)
		if not sound.PlaybackRegionsEnabled then
			return length
		end
		if sound.Looped then
			return math.min(sound.LoopRegion.Max, sound.PlaybackRegion.Max, length)
		end
		return math.min(sound.PlaybackRegion.Max, length)
	end

	local function violation(sound: any, kind: string, region: NumberRange)
		table.insert(engine.violations, {
			sound = sound,
			kind = kind,
			timePosition = sound.TimePosition,
			min = region.Min,
			max = region.Max,
			at = engine.now,
		})
	end

	local function fireEnded(state: State)
		table.insert(state.endedAt, engine.now)
		local handlers = state.ended
		state.ended = {}
		for _, fn in handlers do
			fn()
		end
	end

	engine = {
		now = 0,
		violations = {},
		lengths = {},
		defaultLength = DEFAULT_LENGTH,
		play = function(sound: any): boolean
			local state = stateOf(sound)
			if sound.PlaybackRegionsEnabled then
				local region: NumberRange = sound.PlaybackRegion
				local position = sound.TimePosition
				if position >= region.Max then
					-- (b): refused; TimePosition reads 0 and IsPlaying stays false.
					violation(sound, "pastEnd", region)
					state.playing = false
					sound.TimePosition = 0
					return true -- Play itself does not throw
				end
				if position < region.Min - FLOAT32_SLACK then
					violation(sound, "beforeStart (not measured)", region)
				end
			end
			state.playing = true
			state.frames = 0
			state.firstPass = true
			state.plays += 1
			return true
		end,
		stop = function(sound: any)
			stateOf(sound).playing = false
			sound.TimePosition = 0
		end,
		isPlaying = function(sound: any): boolean
			return stateOf(sound).playing
		end,
		onEnded = function(sound: any, fn: () -> ()): (() -> ())?
			local state = stateOf(sound)
			table.insert(state.ended, fn)
			return function()
				local index = table.find(state.ended, fn)
				if index ~= nil then
					table.remove(state.ended, index)
				end
			end
		end,
		timeLength = function(sound: any): number
			return lengthOf(sound)
		end,
		loudness = function(sound: any): number
			local state = stateOf(sound)
			-- (d): 0 on the first two frames after Play, live from the third.
			return if state.playing and state.frames > SILENT_FRAMES then 1 else 0
		end,
		step = function(dt: number)
			engine.now += dt
			-- A snapshot: an Ended handler may play another Sound (a new state) mid-step.
			local playing: { any } = {}
			for sound, state in states do
				if state.playing then
					table.insert(playing, sound)
				end
			end
			for _, sound in playing do
				local state = states[sound]
				if not state.playing then
					continue
				end
				state.frames += 1
				local position = sound.TimePosition + dt * sound.PlaybackSpeed
				local last = endOf(sound)
				if position >= last then
					if sound.Looped then
						-- (c): wrap to LoopRegion.Min (regions on), else to the top.
						local first = if sound.PlaybackRegionsEnabled then sound.LoopRegion.Min else 0
						local span = last - first
						position = first + if span > 0 then (position - last) % span else 0
						state.firstPass = false
						table.insert(state.wraps, engine.now)
					else
						-- (a): Ended at the region end; IsPlaying false from then.
						state.playing = false
						sound.TimePosition = 0
						fireEnded(state)
						continue
					end
				end
				sound.TimePosition = position
			end
		end,
		stateOf = stateOf,
	}
	return engine
end

return SoundEngine
