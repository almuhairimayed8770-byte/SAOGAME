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
	local still, seconds, left = 0, 0, mixer:pauseRemaining()
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
		for _, case in { { 0, false }, { 0.05, true }, { 0.05, false }, { 0.1, false } } do
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
