--!strict
-- The harness's Sound engine model holds the playback facts measured in Studio on 2026-10-23
-- (rbxassetid://9119749145, whoosh.Small, 0.965 s): (a) Ended at the region end, (b) a start at
-- or past the region end does not play, (c) a looped first pass starts where Play found it, then
-- wraps inside LoopRegion, (d) PlaybackLoudness is 0 for two frames after Play.
local SoundEngine = Harness.SoundEngine

local DT = 1 / 60

local function newSound(): any
	local sound = Instance.new("Sound")
	sound.Name = "whoosh.Small"
	return sound
end

local function frames(engine: any, count: number)
	for _ = 1, count do
		engine.step(DT)
	end
end

describe("SoundEngine (Studio facts of 2026-10-23)", function()
	it("(a) fires Ended at PlaybackRegion.Max and reports IsPlaying false from then", function()
		local engine = SoundEngine.new()
		engine.lengths["whoosh.Small"] = 0.965
		local sound = newSound()
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(0, 0.32)
		sound.TimePosition = 0
		local endedAt: number? = nil
		engine.onEnded(sound, function()
			endedAt = engine.now
		end)
		engine.play(sound)
		local lastPlaying = 0
		for _ = 1, 30 do
			engine.step(DT)
			if engine.isPlaying(sound) then
				lastPlaying = sound.TimePosition
			end
		end
		expect(endedAt).never.toBeNil()
		-- Studio: Ended at 0.316 s, the last TimePosition read while playing 0.299.
		expect(endedAt :: number).toBeCloseTo(0.32, DT + 1e-9)
		expect(lastPlaying).toBeCloseTo(0.3, DT + 1e-9)
		expect(engine.isPlaying(sound)).toBe(false)
		expect(#engine.violations).toBe(0)
	end)

	it("(b) does not play a start at or past PlaybackRegion.Max: TimePosition reads 0, IsPlaying false", function()
		local engine = SoundEngine.new()
		local sound = newSound()
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(0, 0.32)
		sound.TimePosition = 0.6
		engine.play(sound)
		for _ = 1, 6 do
			engine.step(DT)
			expect(engine.isPlaying(sound)).toBe(false)
			expect(sound.TimePosition).toBe(0)
		end
		expect(#engine.violations).toBe(1)
		expect(engine.violations[1].kind).toBe("pastEnd")
	end)

	it("(b) holds the region end as float32: a double start between it and stopAt is refused", function()
		local engine = SoundEngine.new()
		local sound = newSound()
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(0, 0.22)
		local held = sound.PlaybackRegion.Max
		expect(held < 0.22).toBe(true) -- 0.2199999988 in float32
		sound.TimePosition = (held + 0.22) / 2
		engine.play(sound)
		expect(engine.isPlaying(sound)).toBe(false)
		expect(engine.violations[1].kind).toBe("pastEnd")
	end)

	it("(c) starts a loop's first pass where Play found it, then wraps inside LoopRegion", function()
		local engine = SoundEngine.new()
		local sound = newSound()
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(0, 0.32)
		sound.Looped = true
		sound.LoopRegion = NumberRange.new(0.05, 0.25)
		sound.TimePosition = 0
		engine.play(sound)
		engine.step(DT)
		-- The first pass is under LoopRegion.Min.
		expect(sound.TimePosition).toBeLessThan(0.05)
		frames(engine, 60)
		local state = engine.stateOf(sound)
		expect(state.firstPass).toBe(false)
		expect(#state.wraps).toBeGreaterThan(2)
		-- Later passes stay inside the loop region, 0.2 s a pass.
		for _ = 1, 30 do
			engine.step(DT)
			expect(sound.TimePosition).toBeGreaterThanOrEqual(0.05 - 1e-6)
			expect(sound.TimePosition).toBeLessThan(0.25)
		end
		expect(state.wraps[3] - state.wraps[2]).toBeCloseTo(0.2, DT + 1e-9)
	end)

	it("(d) reads PlaybackLoudness 0 on the first two frames after Play, live on the third", function()
		local engine = SoundEngine.new()
		local sound = newSound()
		engine.play(sound)
		engine.step(DT)
		expect(engine.loudness(sound)).toBe(0)
		engine.step(DT)
		expect(engine.loudness(sound)).toBe(0)
		engine.step(DT)
		expect(engine.loudness(sound)).toBeGreaterThan(0)
	end)

	it("records a start more than a float32 rounding under PlaybackRegion.Min (not measured)", function()
		local engine = SoundEngine.new()
		local sound = newSound()
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(0.18, 1.12)
		sound.TimePosition = 0.18 -- 7e-9 under the float32 Min: plays (the heartbeat in Studio)
		engine.play(sound)
		expect(#engine.violations).toBe(0)
		engine.stop(sound)
		sound.TimePosition = 0
		engine.play(sound)
		expect(#engine.violations).toBe(1)
		expect(engine.violations[1].kind).toBe("beforeStart (not measured)")
	end)
end)
