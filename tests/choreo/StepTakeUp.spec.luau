--!strict
--[[
	StepTakeUp (D-651): the physics steps a rendered frame is about to make, guessed from the
	steps the frames before it made. Each frame the take-up is told the steps the frame before took
	and asked for this one's, as Locomotion does in the render step.

	The clocks are drawn to item 530's counts on the owner's PC (97cea9d): the engine plans whole
	1/240 s steps on its own frame clock (0.3 ms of frame jitter) and takes one step more for every
	64 it plans (4.063 a frame at 60 fps, 1.693 at 144), while the render dt also carries up to
	6 ms of work jitter (4 ms at 240) that cancels from frame to frame; the same clocks with no
	drift step, and with the steps in pairs. Item 282's 2-6 pattern (pc-282-feetcheck.csv) and a
	60 Hz clock whose steps are caught up on a jittered dt with no plan of their own (F2d's model)
	are clocks it must leave to D-334: no guess on the first, and on the second no more misses in
	any gateRows frames than the gate lets by before it shuts.

	The owner's PC rows of item 555 (d310ca7, tests/fixtures/PcSteps555.luau) hold flips too, a
	step the engine's frame jitter moved across a frame boundary (5 then 3 about every 45th frame
	at 60 fps, the 2, 2, 1 cycle's 1 swapped with a 2 on a fifth of the frames at 144). Each misses
	twice, so 59 of 60 right never held there and no guess was given; the lead gate (D-661)
	gives the guesses once they clearly miss fewer frames than the last frame's steps.
]]

local luau = require("@lune/luau")

local StepTakeUp = Harness.load("src/client/choreo/StepTakeUp")
local ChoreoData = Harness.load("src/shared/data/choreo")

local TakeUp = ChoreoData.locomotion.stride.takeUp

type Clock = { dt: { number }, steps: { number } }

-- The owner's PC rows of item 555 at `fps`: each render step's dt with the steps of the physics
-- that ran after it, which the PC logged on the next row.
local function pc555(fps: number): Clock
	local fixture = luau.load(Harness.readFile("tests/fixtures/PcSteps555.luau"), { debugName = "PcSteps555" })()
	local dts, steps = {}, {}
	for dt, count in (fixture[fps].rows :: string):gmatch("([%d%.]+) (%d+)") do
		table.insert(dts, (tonumber(dt) :: number) / 1000)
		table.insert(steps, tonumber(count) :: number)
	end
	local clock: Clock = { dt = {}, steps = {} }
	for k = 1, #dts - 1 do
		clock.dt[k] = dts[k]
		clock.steps[k] = steps[k + 1]
	end
	return clock
end

-- Item 530's engine: `fps` frames whose length jitters by up to frameJitMs (telescoping), whole
-- steps planned on that frame clock in `pair`s, one more every `extraEvery` planned (0: none),
-- and a render dt that also carries up to workMs of work jitter (telescoping).
local function engine530(
	rows: number,
	fps: number,
	frameJitMs: number,
	workMs: number,
	seed: number,
	extraEvery: number,
	pair: number
): Clock
	local random = Random.new(seed)
	local acc = (0.3 + 0.4 * random:NextNumber()) / 240 * pair
	local count = math.floor(random:NextNumber() * math.max(1, extraEvery))
	local vPrev = random:NextNumber() * frameJitMs / 1000
	local wPrev = random:NextNumber() * workMs / 1000
	local dts, steps = {}, {}
	for i = 1, rows do
		local v = random:NextNumber() * frameJitMs / 1000
		local f = 1 / fps + v - vPrev
		vPrev = v
		acc += f
		local planned = 0
		while acc >= pair / 240 - 1e-12 do
			acc -= pair / 240
			planned += pair
		end
		local extra = 0
		if extraEvery > 0 then
			count += planned
			while count >= extraEvery do
				count -= extraEvery
				extra += 1
			end
		end
		local w = random:NextNumber() * workMs / 1000
		dts[i] = f + w - wPrev
		wPrev = w
		steps[i] = planned + extra
	end
	return { dt = dts, steps = steps }
end

-- Item 282's frames and steps (Stride.spec's PC clock), looped.
local PC_STEPS = {
	4,
	4,
	4,
	4,
	4,
	4,
	4,
	4,
	4,
	2,
	4,
	4,
	4,
	4,
	4,
	4,
	6,
	4,
	2,
	6,
	4,
	4,
	2,
	6,
	4,
	2,
	6,
	2,
	4,
	6,
	4,
	2,
	4,
	4,
	4,
	6,
	4,
	2,
	4,
	4,
	4,
	6,
	4,
	4,
	4,
	4,
	4,
	4,
	4,
	2,
	6,
	2,
	6,
	4,
	2,
	6,
	4,
	2,
	4,
	4,
	4,
	4,
	4,
	4,
	6,
	4,
	2,
	6,
	4,
	2,
	4,
	4,
}
local PC_MS = {
	15.6,
	17.7,
	16.5,
	17.2,
	16.2,
	16.5,
	16.9,
	16.7,
	16.6,
	16.4,
	16.1,
	17.3,
	15.7,
	16.8,
	17.1,
	17.0,
	16.9,
	16.0,
	17.7,
	16.1,
	16.5,
	16.7,
	17.1,
	16.5,
	16.0,
	17.0,
	16.4,
	17.0,
	16.8,
	16.6,
	16.0,
	17.7,
	15.4,
	17.7,
	17.2,
	15.9,
	16.1,
	17.4,
	15.9,
	17.2,
	17.2,
	16.6,
	17.0,
	15.9,
	16.7,
	17.4,
	15.9,
	16.8,
	16.2,
	17.3,
	15.9,
	16.9,
	17.1,
	15.9,
	16.7,
	17.5,
	15.9,
	16.7,
	17.4,
	15.7,
}
local function pc282(rows: number): Clock
	local dts, steps = {}, {}
	for i = 1, rows do
		dts[i] = PC_MS[(i - 1) % #PC_MS + 1] / 1000
		steps[i] = PC_STEPS[(i - 1) % #PC_STEPS + 1]
	end
	return { dt = dts, steps = steps }
end

-- F2d's 60 Hz model: the steps caught up on a jittered dt, the render dt read without the
-- catch-up's own jitter.
local function caughtUp(rows: number, seed: number): Clock
	local random = Random.new(seed)
	local acc = random:NextNumber() / 240
	local before = 0
	local dts, steps = {}, {}
	for i = 1, rows do
		local dt = (16.91 + (random:NextNumber() * 2 - 1) * 0.4) / 1000
		local jitter = (random:NextNumber() * 2 - 1) * 0.35 / 1000
		acc += dt + jitter - before
		before = jitter
		local count = 0
		while acc >= 1 / 240 - 1e-12 do
			acc -= 1 / 240
			count += 1
		end
		dts[i] = dt
		steps[i] = count
	end
	return { dt = dts, steps = steps }
end

type Read = {
	first: number?,
	late: number,
	guessed: number,
	right: number,
	wrong: number,
	given: number,
	worstWindow: number,
	means: { number },
}

-- Runs a take-up over a clock: the first frame it guesses, every guess it gave and the wrong
-- ones, the most wrong guesses in any gateRows frames, and over the frames after spanRows how
-- many it guessed and how many of those were right; every frame's mean a frame.
local function read(clock: Clock): Read
	local takeUp = StepTakeUp.new(TakeUp)
	local out: Read =
		{ first = nil, late = 0, guessed = 0, right = 0, wrong = 0, given = 0, worstWindow = 0, means = {} }
	local missed: { boolean } = {}
	local inWindow = 0
	for i = 1, #clock.dt do
		if i > 1 then
			takeUp:observe(clock.steps[i - 1])
		end
		local guess, mean = takeUp:guess(clock.dt[i])
		out.means[i] = mean
		if guess ~= nil and out.first == nil then
			out.first = i
		end
		if guess ~= nil then
			out.given += 1
		end
		missed[i] = guess ~= nil and guess ~= clock.steps[i]
		if missed[i] then
			out.wrong += 1
			inWindow += 1
		end
		if i > TakeUp.gateRows and missed[i - TakeUp.gateRows] then
			inWindow -= 1
		end
		out.worstWindow = math.max(out.worstWindow, inWindow)
		if i > TakeUp.spanRows then
			out.late += 1
			if guess ~= nil then
				out.guessed += 1
				if guess == clock.steps[i] then
					out.right += 1
				end
			end
		end
	end
	return out
end

local RATES = {
	{ fps = 60, rows = 1200, workMs = 6 },
	{ fps = 144, rows = 2880, workMs = 6 },
	{ fps = 240, rows = 4800, workMs = 4 },
}

describe("StepTakeUp on the PC's step clocks (item 530, D-651)", function()
	it(
		"at 60, 144 and 240 fps, with and without the drift step: guesses by spanRows, then on gateShare of the frames, right on gateShare of its guesses",
		function()
			local problems = {}
			for _, rate in RATES do
				for _, extraEvery in { 64, 0 } do
					for seed = 1, 5 do
						local clock = engine530(rate.rows, rate.fps, 0.3, rate.workMs, seed, extraEvery, 1)
						local result = read(clock)
						local label = ("%d fps%s seed %d"):format(
							rate.fps,
							if extraEvery > 0 then "" else " no drift",
							seed
						)
						if result.first == nil or (result.first :: number) > TakeUp.spanRows then
							table.insert(
								problems,
								("%s: first guess at frame %s"):format(label, tostring(result.first))
							)
						end
						if result.guessed < TakeUp.gateShare * result.late then
							table.insert(
								problems,
								("%s: guessed %d of %d frames"):format(label, result.guessed, result.late)
							)
						end
						if result.right < TakeUp.gateShare * result.guessed then
							table.insert(
								problems,
								("%s: right on %d of %d guesses"):format(label, result.right, result.guessed)
							)
						end
					end
				end
			end
			expect(table.concat(problems, "; ")).toBe("")
		end
	)

	it("the steps in pairs at 144 fps: the same", function()
		local problems = {}
		for seed = 1, 5 do
			local result = read(engine530(2880, 144, 0.3, 6, seed, 0, 2))
			if result.guessed < TakeUp.gateShare * result.late or result.right < TakeUp.gateShare * result.guessed then
				table.insert(
					problems,
					("seed %d: %d of %d guessed, %d right"):format(seed, result.guessed, result.late, result.right)
				)
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it(
		"item 282's 2-6 pattern: no guess; steps caught up on a jittered dt: no more misses in any gateRows frames than the gate lets by",
		function()
			local problems = {}
			local pattern = read(pc282(1200))
			if pattern.given > 0 then
				table.insert(problems, ("item 282: %d guesses, %d wrong"):format(pattern.given, pattern.wrong))
			end
			-- The gate opens on (1 - gateShare) x gateRows misses at most and shuts on the next one.
			local letBy = math.floor((1 - TakeUp.gateShare) * TakeUp.gateRows) + 1
			for seed = 1, 5 do
				local result = read(caughtUp(1200, seed))
				if result.worstWindow > letBy then
					table.insert(
						problems,
						("caught up, seed %d: %d wrong guesses in %d frames, %d let by"):format(
							seed,
							result.worstWindow,
							TakeUp.gateRows,
							letBy
						)
					)
				end
			end
			expect(table.concat(problems, "; ")).toBe("")
		end
	)

	it(
		"on the owner's PC rows of item 555 (d310ca7): from 2 s, a guess on most frames, and misses on at most half (60 fps) or three quarters (144) of the frames the last frame's steps miss",
		function()
			local problems = {}
			for _, case in { { fps = 60, given = 0.9, share = 0.5 }, { fps = 144, given = 0.5, share = 0.75 } } do
				local clock = pc555(case.fps)
				local takeUp = StepTakeUp.new(TakeUp)
				local t, judged, given, lastMisses, misses = 0, 0, 0, 0, 0
				for i = 1, #clock.dt do
					if i > 1 then
						takeUp:observe(clock.steps[i - 1])
					end
					local guess = takeUp:guess(clock.dt[i])
					t += clock.dt[i]
					if t >= 2 then
						judged += 1
						-- D-334 alone moves the foot on screen by every change of steps; with a guess, by
						-- its miss.
						local lastMiss = clock.steps[i] ~= clock.steps[i - 1]
						if lastMiss then
							lastMisses += 1
						end
						if guess ~= nil then
							given += 1
						end
						if (guess ~= nil and guess ~= clock.steps[i]) or (guess == nil and lastMiss) then
							misses += 1
						end
					end
				end
				if given < case.given * judged or misses > case.share * lastMisses then
					table.insert(
						problems,
						("%d fps: guessed %d of %d frames, %d missed against D-334's %d"):format(
							case.fps,
							given,
							judged,
							misses,
							lastMisses
						)
					)
				end
			end
			expect(table.concat(problems, "; ")).toBe("")
		end
	)

	it("the mean a frame is the last spanRows frames' steps; a reset forgets every frame", function()
		local clock = engine530(TakeUp.spanRows + 200, 60, 0.3, 6, 3, 64, 1)
		local takeUp = StepTakeUp.new(TakeUp)
		local guess, mean = takeUp:guess(clock.dt[1])
		expect(guess).toBe(nil)
		expect(mean).toBe(0)
		for i = 2, #clock.dt do
			takeUp:observe(clock.steps[i - 1])
			guess, mean = takeUp:guess(clock.dt[i])
		end
		local sum = 0
		for i = #clock.dt - TakeUp.spanRows, #clock.dt - 1 do
			sum += clock.steps[i]
		end
		expect(math.abs(mean - sum / TakeUp.spanRows) < 1e-9).toBe(true)
		expect(guess).toBe(clock.steps[#clock.dt])

		takeUp:reset()
		guess, mean = takeUp:guess(clock.dt[1])
		expect(guess).toBe(nil)
		expect(mean).toBe(0)
		local firstGuess: number? = nil
		for i = 2, #clock.dt do
			takeUp:observe(clock.steps[i - 1])
			guess = takeUp:guess(clock.dt[i])
			if guess ~= nil and firstGuess == nil then
				firstGuess = i
			end
		end
		-- No guess before minRows frames and the gate's own gateRows have been read again.
		expect(firstGuess ~= nil and (firstGuess :: number) > math.max(TakeUp.minRows, TakeUp.gateRows)).toBe(true)
	end)
end)
