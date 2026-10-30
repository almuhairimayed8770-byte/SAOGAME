--!strict
--[[
	A hold counts the rendered frames nearest its length at any refresh rate (D-228 amended). The
	rig ends a pause once what is left of it is under half of the step: 3, 6 and 10 frames at 60 Hz
	(also under frame-time jitter), and at 120, 144 and 240 Hz the frames nearest 50, 100 and 166.7
	ms. Before, every hold asked for half a 60 Hz frame less and ran until nothing was left, so at
	120 Hz and above a Normal held 41.7 ms against 50, a Final 91.7 to 97.2 against 100 and a Kill
	158 to 160 against 166.7. Holds are asked for as Replication.heldFrames asks (the tier's frames
	less combat.hitStopShaveFrames).
]]

local Combat = Harness.load("src/shared/data/combat")
local Mixer = Harness.load("src/client/choreo/Mixer")
local clip = Harness.load("src/shared/clips/player/OneHandedSword/Horizontal")

local TIERS = { "Normal", "Final", "Kill" }

-- Plays the clip, steps a few frames, puts the tier's hold on, then steps until the clock moves:
-- the frames it held, their length in seconds, and what pauseRemaining said after the last one.
local function hold(tier: string, nextDt: () -> number): (number, number, number)
	local mixer = Mixer.new()
	local handle = mixer:play(clip)
	for _ = 1, 3 do
		mixer:step(nextDt())
	end
	mixer:hitStop(math.max(0, Combat.hitStopFrames[tier] - Combat.hitStopShaveFrames))
	local still, seconds = 0, 0
	local left = mixer:pauseRemaining()
	for _ = 1, 200 do
		local before = handle.time
		local dt = nextDt()
		mixer:step(dt)
		if handle.time > before + 1e-12 then
			break
		end
		still += 1
		seconds += dt
		left = mixer:pauseRemaining()
	end
	return still, seconds, left
end

local function steady(hz: number): () -> number
	return function(): number
		return 1 / hz
	end
end

-- Frame times whose present times wobble by up to `jitter` of a frame around the refresh grid (a
-- display's clock never drifts), or, with `drift`, frame times that each wobble on their own.
local function jittered(hz: number, jitter: number, rng: any, drift: boolean): () -> number
	local last = 0
	return function(): number
		local wobble = (rng:NextNumber() * 2 - 1) * jitter
		if drift then
			return (1 / hz) * (1 + wobble)
		end
		local step = (1 / hz) * (1 + wobble - last)
		last = wobble
		return step
	end
end

describe("a hold counts the frames nearest its length (D-228 amended)", function()
	it("holds the nearest whole number of frames at 30, 60, 120, 144 and 240 Hz", function()
		for _, hz in { 30, 60, 120, 144, 240 } do
			for _, tier in TIERS do
				local exact = Combat.hitStopFrames[tier] * hz / 60
				-- Half a frame left over holds the frame: 1.5 frames at 30 Hz hold 2.
				local want = math.floor(exact + 0.5)
				local still = hold(tier, steady(hz))
				if still ~= want then
					error(
						("%s at %d Hz held %d frames, the nearest to %.2f is %d"):format(tier, hz, still, exact, want)
					)
				end
			end
		end
	end)

	it("at 120, 144 and 240 Hz holds within half a frame of 50, 100 and 166.7 ms", function()
		for _, hz in { 120, 144, 240 } do
			for _, tier in TIERS do
				local target = Combat.hitStopFrames[tier] * Combat.hitStopFrameSeconds
				local _, seconds = hold(tier, steady(hz))
				if math.abs(seconds - target) > 0.5 / hz + 1e-9 then
					error(("%s at %d Hz held %.1f ms against %.1f"):format(tier, hz, seconds * 1000, target * 1000))
				end
			end
		end
	end)

	it("keeps 60 Hz exact: 3, 6 and 10 frames at 0, 5 and 10% jitter", function()
		local rng = Random.new(20261025)
		for _, case in { { 0, false }, { 0.05, true }, { 0.05, false }, { 0.1, false } } :: { { any } } do
			local jitter, drift = case[1] :: number, case[2] :: boolean
			for _ = 1, 100 do
				for _, tier in TIERS do
					local still = hold(tier, jittered(60, jitter, rng, drift))
					if still ~= Combat.hitStopFrames[tier] then
						error(
							("%s at 60 Hz, %d%% jitter%s, held %d frames"):format(
								tier,
								jitter * 100,
								if drift then " (drifting)" else "",
								still
							)
						)
					end
				end
			end
		end
	end)

	it("leaves nothing of the pause once its last frame is held", function()
		for _, hz in { 30, 60, 144, 240 } do
			for _, tier in TIERS do
				local _, _, left = hold(tier, steady(hz))
				expect(left).toBe(0)
			end
		end
	end)

	it("freezes no frame for a sliver under half a step", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip)
		mixer:step(1 / 60)
		mixer:hitStop(0.4)
		local before = handle.time
		mixer:step(1 / 60)
		expect(handle.time > before).toBe(true)
		expect(mixer:pauseRemaining()).toBe(0)
	end)
end)

-- A rig in a running fight: `warm` frames from `nextDt` before the hold goes on, so the Mixer has
-- the pace of its last impact.luau hold.paceFrames steps (D-327).
-- A 12 s loop: no warm-up runs it out, and nothing in it ends or jumps the clock.
local longClip = Harness.load("src/shared/clips/player/OneHandedSword/IdleDrawn")
local function holdAfter(tier: string, nextDt: () -> number, warm: number): number
	local mixer = Mixer.new()
	local handle = mixer:play(longClip)
	for _ = 1, warm do
		mixer:step(nextDt())
	end
	-- The clip is long enough that the warm-up never ends it.
	assert(not handle.done and handle.time < 6, "the warm-up ran the clip out")
	mixer:hitStop(math.max(0, Combat.hitStopFrames[tier] - Combat.hitStopShaveFrames))
	local still = 0
	for _ = 1, 200 do
		local before = handle.time
		mixer:step(nextDt())
		if handle.time > before + 1e-12 then
			break
		end
		still += 1
	end
	return still
end

describe("a hold's frames are counted once, at its start, from the rig's pace (D-327)", function()
	local ImpactData = Harness.load("src/shared/data/impact")
	local WARM = ImpactData.hold.paceFrames + 4

	it("holds a Normal 2 frames at 30 Hz under 5 and 10% jitter, a Final 3 and a Kill 5", function()
		local rng = Random.new(30301)
		local want = { Normal = 2, Final = 3, Kill = 5 }
		for _, case in { { 0.05, false }, { 0.1, false }, { 0.05, true }, { 0.1, true } } :: { { any } } do
			local jitter, drift = case[1] :: number, case[2] :: boolean
			for run = 1, 300 do
				for _, tier in TIERS do
					local still = holdAfter(tier, jittered(30, jitter, rng, drift), WARM + run % 7)
					if still ~= want[tier] then
						error(
							("%s at 30 Hz, %d%% jitter%s, run %d, held %d frames, want %d"):format(
								tier,
								jitter * 100,
								if drift then " (drifting)" else "",
								run,
								still,
								want[tier]
							)
						)
					end
				end
			end
		end
	end)

	it("keeps 60 Hz exact (3, 6 and 10) and 120 and 240 Hz at the nearest frames under jitter", function()
		local rng = Random.new(60601)
		for _, hz in { 60, 120, 240 } do
			-- Frame times that drift on their own (no display grid) only at 60 Hz: at 240 Hz a Kill
			-- is 40 frames and their mean wanders by a frame's fraction either way (as at HEAD).
			local cases: { { any } } = if hz == 60
				then { { 0, false }, { 0.05, false }, { 0.1, false }, { 0.05, true } } :: { { any } }
				else { { 0, false }, { 0.05, false }, { 0.1, false } } :: { { any } }
			for _, case in cases do
				local jitter, drift = case[1] :: number, case[2] :: boolean
				for run = 1, 100 do
					for _, tier in TIERS do
						local want = math.floor(Combat.hitStopFrames[tier] * hz / 60 + 0.5)
						local still = holdAfter(tier, jittered(hz, jitter, rng, drift), WARM + run % 5)
						if still ~= want then
							error(
								("%s at %d Hz, %d%% jitter%s, held %d frames, want %d"):format(
									tier,
									hz,
									jitter * 100,
									if drift then " (drifting)" else "",
									still,
									want
								)
							)
						end
					end
				end
			end
		end
	end)

	it("at 144 Hz holds the nearest frames steadily, and at most one more under jitter", function()
		local rng = Random.new(14401)
		for _, case in { { 0, false }, { 0.05, false }, { 0.1, false }, { 0.05, true } } :: { { any } } do
			local jitter, drift = case[1] :: number, case[2] :: boolean
			for run = 1, if jitter == 0 then 1 else 100 do
				for _, tier in TIERS do
					local want = math.floor(Combat.hitStopFrames[tier] * 144 / 60 + 0.5)
					local still = holdAfter(tier, jittered(144, jitter, rng, drift), WARM + run % 5)
					local slack = if jitter == 0 then 0 else 1
					if still < want or still > want + slack then
						error(
							("%s at 144 Hz, %d%% jitter, held %d frames, want %d"):format(
								tier,
								jitter * 100,
								still,
								want
							)
						)
					end
				end
			end
		end
	end)

	it("is not shortened by a hitch just before it", function()
		for _, hz in { 30, 60 } do
			for _, tier in TIERS do
				local count = 0
				local still = holdAfter(tier, function(): number
					count += 1
					-- One 0.2 s hitch two frames before the hold.
					return if count == WARM - 1 then 0.2 else 1 / hz
				end, WARM)
				expect(still).toBe(math.floor(Combat.hitStopFrames[tier] * hz / 60 + 0.5))
			end
		end
	end)

	it("takes a display's own cadence as the pace, never as hitches (D-341)", function()
		-- A rig that cannot keep up with a vsync display shows each frame for one or two refreshes:
		-- 45 fps on 60 Hz is 1, 1, 2 refreshes again and again. The two-refresh frames are a third of
		-- them, the pace, not hitches: left out, a Final held 6 frames (133 ms) and a Kill 10 (217 to
		-- 233 ms) at 45 fps. The hold is the frames nearest its length at the mean pace (a half frame
		-- going to the longer count): 45 fps holds 2, 5 and 8 (2.25, 4.5 and 7.5 frames).
		-- At 120 and 144 Hz the 32 frames' mean moves with the cadence's phase (32 is no multiple of
		-- 3), so a length near a half frame may hold one more, as under jitter at 144 Hz above.
		local cases: { { any } } = {
			{ 60, { 1, 1, 2 }, { Normal = 2, Final = 5, Kill = 8 }, 0 }, -- 45 fps
			{ 60, { 1, 2 }, { Normal = 2, Final = 4, Kill = 7 }, 0 }, -- 40 fps
			{ 144, { 1, 1, 2 }, { Normal = 5, Final = 11, Kill = 18 }, 1 }, -- 108 fps
			{ 120, { 1, 1, 2 }, { Normal = 5, Final = 9, Kill = 15 }, 1 }, -- 90 fps
		}
		for _, case in cases do
			local hz, pattern, want = case[1] :: number, case[2] :: { number }, case[3] :: { [string]: number }
			local slack = case[4] :: number
			for phase = 0, #pattern - 1 do
				for _, tier in TIERS do
					local count = phase
					local still = holdAfter(tier, function(): number
						count += 1
						return pattern[(count - 1) % #pattern + 1] / hz
					end, WARM)
					if still < want[tier] or still > want[tier] + slack then
						error(
							("%s at %d Hz showing frames for %s refreshes (phase %d) held %d frames, want %d"):format(
								tier,
								hz,
								table.concat(pattern, ", "),
								phase,
								still,
								want[tier]
							)
						)
					end
				end
			end
		end
	end)

	it("follows a change of frame rate within its pace's frames", function()
		local count = 0
		-- 60 Hz, then 30 Hz from the frame the pace starts over.
		local still = holdAfter("Normal", function(): number
			count += 1
			return if count <= WARM then 1 / 60 else 1 / 30
		end, WARM + ImpactData.hold.paceFrames)
		expect(still).toBe(2)
	end)

	it("keeps a running count when a shorter hold comes, and counts on from now for a longer one", function()
		local mixer = Mixer.new()
		local handle = mixer:play(longClip)
		for _ = 1, WARM do
			mixer:step(1 / 30)
		end
		mixer:hitStop(Combat.hitStopFrames.Final) -- 3 frames at 30 Hz
		mixer:step(1 / 30)
		mixer:hitStop(Combat.hitStopFrames.Normal) -- 2 frames: the 2 left are kept
		local still = 1
		for _ = 1, 20 do
			local before = handle.time
			mixer:step(1 / 30)
			if handle.time > before + 1e-12 then
				break
			end
			still += 1
		end
		expect(still).toBe(3)
		-- A Kill asked for on the Normal's first frame runs its 5 frames from there.
		mixer:hitStop(Combat.hitStopFrames.Normal)
		mixer:step(1 / 30)
		mixer:hitStop(Combat.hitStopFrames.Kill)
		still = 1
		for _ = 1, 20 do
			local before = handle.time
			mixer:step(1 / 30)
			if handle.time > before + 1e-12 then
				break
			end
			still += 1
		end
		expect(still).toBe(6)
	end)

	it("says what is left of the hold in its own seconds, none once its last frame is held", function()
		local mixer = Mixer.new()
		mixer:play(longClip)
		for _ = 1, WARM do
			mixer:step(1 / 30)
		end
		local asked = Combat.hitStopFrames.Normal * Combat.hitStopFrameSeconds
		mixer:hitStop(Combat.hitStopFrames.Normal)
		expect(mixer:pauseRemaining()).toBeCloseTo(asked, 1e-9)
		mixer:step(1 / 30)
		-- Half the hold's seconds for the one frame of its two still to come: still owed a frame
		-- by Replication's rule (at least half a step).
		expect(mixer:pauseRemaining()).toBeCloseTo(asked / 2, 1e-9)
		mixer:step(1 / 30)
		expect(mixer:pauseRemaining()).toBe(0)
	end)
end)

-- Steps a mixer playing the long loop `warm` times at `nextDt`, returning it and the loop's handle.
local function warmed(nextDt: () -> number, warm: number): (any, any)
	local mixer = Mixer.new()
	local handle = mixer:play(longClip)
	for _ = 1, warm do
		mixer:step(nextDt())
	end
	assert(not handle.done and handle.time < 6, "the warm-up ran the clip out")
	return mixer, handle
end

-- The steps the clip's clock stands still from now on (at most 200).
local function stillSteps(mixer: any, handle: any, nextDt: () -> number): number
	local still = 0
	for _ = 1, 200 do
		local before = handle.time
		mixer:step(nextDt())
		if handle.time > before + 1e-12 then
			break
		end
		still += 1
	end
	return still
end

describe("a hold counted in steps, and the steps a rig's holds froze (D-354)", function()
	it("holdSteps freezes exactly that many steps, whatever their length", function()
		for _, warm in { 0, 3, 40 } do
			for _, pacing in { "even", "alt45", "hitchy" } do
				local f = 0
				local function nextDt(): number
					f += 1
					if pacing == "alt45" then
						return if f % 2 == 0 then 1 / 60 else 2 / 60
					elseif pacing == "hitchy" then
						local k = f % 5
						return if k == 0 then 3 / 60 elseif k == 3 then 2 / 60 else 1 / 60
					end
					return 1 / 60
				end
				for _, steps in { 1, 4, 9 } do
					local mixer, handle = warmed(nextDt, warm)
					mixer:holdSteps(steps)
					local still = stillSteps(mixer, handle, nextDt)
					if still ~= steps then
						error(("%s, %d steps in: holdSteps(%d) froze %d steps"):format(pacing, warm, steps, still), 0)
					end
				end
			end
		end
	end)

	it("keeps a longer hold already running, counted or not", function()
		-- 144 Hz: a Kill's seconds are 24 steps; a picture's 14 steps must not cut it short, with or
		-- without the rig's pace (D-327) to count it by.
		for _, warm in { 3, 40 } do
			local mixer, handle = warmed(steady(144), warm)
			mixer:hitStop(Combat.hitStopFrames.Kill - Combat.hitStopShaveFrames)
			mixer:holdSteps(14)
			expect(stillSteps(mixer, handle, steady(144))).toBe(24)
		end
	end)

	it("heldCount counts every step a hold froze, and holdPace the length they are counted at", function()
		local mixer = Mixer.new()
		expect(mixer:holdPace()).toBe(nil)
		local handle = mixer:play(longClip)
		for _ = 1, 3 do
			mixer:step(1 / 30)
		end
		local mark = mixer:heldCount()
		expect(math.abs((mixer:holdPace() :: number) - 1 / 30) < 1e-9).toBe(true)
		-- A Normal at 30 fps freezes 2 steps (D-271): 0.067 s shown against the 0.05 s asked.
		mixer:hitStop(Combat.hitStopFrames.Normal - Combat.hitStopShaveFrames)
		local still = stillSteps(mixer, handle, function(): number
			return 1 / 30
		end)
		expect(still).toBe(2)
		expect(mixer:heldCount() - mark).toBe(2)
		expect(math.abs((mixer:heldCount() - mark) * (mixer:holdPace() :: number) - 2 / 30) < 1e-9).toBe(true)
	end)
end)
