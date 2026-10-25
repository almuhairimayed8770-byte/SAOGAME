--!strict
-- SheathState: where the sword is and which sheath clip plays, one rule per case.
local SheathState = Harness.load("src/client/choreo/SheathState")
local ChoreoData = Harness.load("src/shared/data/choreo")

local FRAME = 1 / 60
local DELAY = ChoreoData.sheath.sheatheDelay

local function input(overrides: { [string]: boolean }?)
	local base = { target = false, cut = false, covered = false, drawing = false, sheathing = false, hold = false }
	for key, value in overrides or {} do
		(base :: any)[key] = value
	end
	return base
end

-- Steps `seconds` worth of frames with one input; returns every output.
local function run(state, seconds: number, given)
	local outputs = {}
	for _ = 1, math.ceil(seconds / FRAME - 1e-9) do
		table.insert(outputs, state:step(FRAME, given))
	end
	return outputs
end

-- Steps one frame at a time until the clip plays; returns the frames it took (nil past `limit`).
local function framesUntil(state, clip: string, given, limit: number): number?
	for frame = 1, limit do
		if state:step(FRAME, given).play == clip then
			return frame
		end
	end
	return nil
end

local function plays(outputs, clip: string): number
	local total = 0
	for _, out in outputs do
		if out.play == clip then
			total += 1
		end
	end
	return total
end

describe("SheathState.step", function()
	it("a draw-cut from the back puts the sword in the hand at once and plays no Draw", function()
		local state = SheathState.new("Back")
		local out = state:step(FRAME, input({ cut = true, target = true }))
		expect(out.place).toBe("Hand")
		expect(out.play).toBeNil()
		expect(state.place).toBe("Hand")
		-- With no target yet (a remote attack ahead of the attribute) it is the same.
		local remote = SheathState.new("Back")
		expect(remote:step(FRAME, input({ cut = true })).place).toBe("Hand")
	end)

	it("a draw-cut stops a Draw or a Sheathe that is playing", function()
		local drawing = SheathState.new("Back")
		local out = drawing:step(FRAME, input({ cut = true, target = true, drawing = true }))
		expect(out.place).toBe("Hand")
		expect(out.stop).toBe("Draw")
		local sheathed = SheathState.new("Back")
		out = sheathed:step(FRAME, input({ cut = true, sheathing = true }))
		expect(out.place).toBe("Hand")
		expect(out.stop).toBe("Sheathe")
	end)

	it("a cut stops a Sheathe while the sword is still in the hand", function()
		local state = SheathState.new("Hand")
		local out = state:step(FRAME, input({ cut = true, sheathing = true }))
		expect(out.stop).toBe("Sheathe")
		expect(out.place).toBeNil()
		expect(state.place).toBe("Hand")
	end)

	it("a true target on the back plays Draw once; the sword waits on the back for the event", function()
		local state = SheathState.new("Back")
		local out = state:step(FRAME, input({ target = true }))
		expect(out.play).toBe("Draw")
		expect(out.place).toBeNil()
		expect(state.place).toBe("Back")
		expect(plays(run(state, 0.2, input({ target = true, drawing = true })), "Draw")).toBe(0)
		expect(state:onEvent("WeaponDraw", input({ target = true, drawing = true }))).toBe("Hand")
		expect(state.place).toBe("Hand")
		-- In the hand with a true target nothing more plays.
		expect(plays(run(state, 1, input({ target = true })), "Draw")).toBe(0)
	end)

	it("a false target plays Sheathe only after sheatheDelay, and only once", function()
		local state = SheathState.new("Hand")
		local frames = framesUntil(state, "Sheathe", input(), 120) :: number
		expect(frames).toBeTruthy()
		expect(frames * FRAME).toBeGreaterThan(DELAY - FRAME / 2)
		expect(frames * FRAME).toBeLessThan(DELAY + FRAME * 1.5)
		expect(plays(run(state, 0.3, input({ sheathing = true })), "Sheathe")).toBe(0)
		expect(state:onEvent("WeaponSheathe", input({ sheathing = true }))).toBe("Back")
		expect(state.place).toBe("Back")
		expect(plays(run(state, 1, input()), "Sheathe")).toBe(0)
	end)

	it("a target that flickers true resets the delay", function()
		local state = SheathState.new("Hand")
		expect(plays(run(state, DELAY - 2 * FRAME, input()), "Sheathe")).toBe(0)
		state:step(FRAME, input({ target = true }))
		local frames = framesUntil(state, "Sheathe", input(), 120) :: number
		expect(frames * FRAME).toBeGreaterThan(DELAY - FRAME / 2)
	end)

	it("a reversal while drawing, before the event: Draw stops and the sword stays on the back", function()
		local state = SheathState.new("Back")
		state:step(FRAME, input({ target = true }))
		local out = state:step(FRAME, input({ drawing = true }))
		expect(out.stop).toBe("Draw")
		-- A cut back: nothing else moves the arm, so it turns back at the clips' pace.
		expect(out.blend).toBe(ChoreoData.sheath.cutBackBlend)
		-- The stopped Draw's late event changes nothing.
		expect(state:onEvent("WeaponDraw", input())).toBeNil()
		local after = run(state, 2, input())
		expect(state.place).toBe("Back")
		expect(plays(after, "Sheathe")).toBe(0)
		expect(plays(after, "Draw")).toBe(0)
	end)

	it("a reversal while drawing, after the event: Draw stops and Sheathe follows the delay", function()
		local state = SheathState.new("Back")
		state:step(FRAME, input({ target = true }))
		state:onEvent("WeaponDraw", input({ target = true, drawing = true }))
		expect(state.place).toBe("Hand")
		local out = state:step(FRAME, input({ drawing = true }))
		expect(out.stop).toBe("Draw")
		expect(out.blend).toBe(ChoreoData.sheath.cutBackBlend)
		expect(state.place).toBe("Hand")
		local frames = framesUntil(state, "Sheathe", input(), 120) :: number
		expect(frames).toBeTruthy()
		expect(frames * FRAME).toBeLessThan(DELAY + FRAME)
	end)

	it("a reversal while sheathing, before the event: Sheathe stops and the sword stays in the hand", function()
		local state = SheathState.new("Hand")
		expect(framesUntil(state, "Sheathe", input(), 120)).toBeTruthy()
		local out = state:step(FRAME, input({ target = true, sheathing = true }))
		expect(out.stop).toBe("Sheathe")
		-- The lock-on mid-Sheathe: the drawn pose comes back over cutBackBlend, not stopBlend.
		expect(out.blend).toBe(ChoreoData.sheath.cutBackBlend)
		expect(ChoreoData.sheath.cutBackBlend).toBeGreaterThan(ChoreoData.sheath.stopBlend)
		expect(state:onEvent("WeaponSheathe", input({ target = true }))).toBeNil()
		local after = run(state, 1, input({ target = true }))
		expect(state.place).toBe("Hand")
		expect(plays(after, "Draw")).toBe(0)
	end)

	it("a reversal while sheathing, after the event: Sheathe stops, then Draw plays the next step", function()
		local state = SheathState.new("Hand")
		expect(framesUntil(state, "Sheathe", input(), 120)).toBeTruthy()
		expect(state:onEvent("WeaponSheathe", input({ sheathing = true }))).toBe("Back")
		local out = state:step(FRAME, input({ target = true, sheathing = true }))
		expect(out.stop).toBe("Sheathe")
		-- The Draw takes the arm over next step: the Sheathe goes at the plain stopBlend.
		expect(out.blend).toBeNil()
		expect(out.play).toBeNil()
		out = state:step(FRAME, input({ target = true }))
		expect(out.play).toBe("Draw")
	end)

	it("a Draw that ends before its event still puts the sword in the hand, and does not replay", function()
		local state = SheathState.new("Back")
		state:step(FRAME, input({ target = true }))
		state:step(FRAME, input({ target = true, drawing = true }))
		local out = state:step(FRAME, input({ target = true }))
		expect(out.place).toBe("Hand")
		expect(out.play).toBeNil()
	end)

	it("a Sheathe that ends before its event still puts the sword on the back, but not under a cut", function()
		local state = SheathState.new("Hand")
		state:step(FRAME, input({ sheathing = true }))
		local out = state:step(FRAME, input())
		expect(out.place).toBe("Back")
		expect(out.play).toBeNil()

		local guarded = SheathState.new("Hand")
		guarded:step(FRAME, input({ sheathing = true }))
		out = guarded:step(FRAME, input({ cut = true }))
		expect(out.place).toBeNil()
		expect(guarded.place).toBe("Hand")
	end)

	it("a clip it stopped itself is not a clip that ended: a flicker replays Draw instead of popping", function()
		local state = SheathState.new("Back")
		state:step(FRAME, input({ target = true }))
		expect(state:step(FRAME, input({ drawing = true })).stop).toBe("Draw")
		local out = state:step(FRAME, input({ target = true }))
		expect(out.place).toBeNil()
		expect(out.play).toBe("Draw")
	end)

	it("hold freezes everything: no clip starts and the sword stays", function()
		local back = SheathState.new("Back")
		local outputs = run(back, 1, input({ target = true, hold = true }))
		expect(plays(outputs, "Draw")).toBe(0)
		expect(back.place).toBe("Back")
		local hand = SheathState.new("Hand")
		outputs = run(hand, 1, input({ hold = true, cut = false }))
		expect(plays(outputs, "Sheathe")).toBe(0)
		expect(hand:step(FRAME, input({ hold = true, cut = true })).place).toBeNil()
		expect(hand.place).toBe("Hand")
	end)
end)

describe("SheathState: a clip that hides the arm", function()
	it("holds the Draw back while the arm is covered, and plays it once the arm is free", function()
		local state = SheathState.new("Back")
		local outputs = run(state, 0.5, input({ target = true, covered = true }))
		expect(plays(outputs, "Draw")).toBe(0)
		expect(state.place).toBe("Back")
		expect(state:step(FRAME, input({ target = true })).play).toBe("Draw")
	end)

	it("stops a Draw that has not taken the sword yet, and plays it again after the cover", function()
		local state = SheathState.new("Back")
		expect(state:step(FRAME, input({ target = true })).play).toBe("Draw")
		local out = state:step(FRAME, input({ target = true, drawing = true, covered = true }))
		expect(out.stop).toBe("Draw")
		expect(out.place).toBeNil()
		-- The stopped Draw fades past its grab under the cover: the sword stays on the back.
		expect(state:onEvent("WeaponDraw", input({ target = true, covered = true }))).toBeNil()
		expect(plays(run(state, 0.3, input({ target = true, covered = true })), "Draw")).toBe(0)
		expect(state.place).toBe("Back")
		out = state:step(FRAME, input({ target = true }))
		expect(out.play).toBe("Draw")
		expect(out.place).toBeNil()
	end)

	it("leaves a Draw that already took the sword alone", function()
		local state = SheathState.new("Back")
		state:step(FRAME, input({ target = true }))
		state:onEvent("WeaponDraw", input({ target = true, drawing = true }))
		local out = state:step(FRAME, input({ target = true, drawing = true, covered = true }))
		expect(out.stop).toBeNil()
		expect(state.place).toBe("Hand")
	end)

	it("holds the Sheathe back, and stops one that has not put the sword away", function()
		local state = SheathState.new("Hand")
		expect(plays(run(state, DELAY + 0.5, input({ covered = true })), "Sheathe")).toBe(0)
		expect(state:step(FRAME, input()).play).toBe("Sheathe")
		local out = state:step(FRAME, input({ sheathing = true, covered = true }))
		expect(out.stop).toBe("Sheathe")
		expect(state:onEvent("WeaponSheathe", input({ covered = true }))).toBeNil()
		expect(state.place).toBe("Hand")
		expect(state:step(FRAME, input()).play).toBe("Sheathe")
	end)

	it("a Draw that ends under a cover leaves the sword on the back", function()
		local state = SheathState.new("Back")
		state:step(FRAME, input({ target = true }))
		state:step(FRAME, input({ target = true, drawing = true }))
		local out = state:step(FRAME, input({ target = true, covered = true }))
		expect(out.place).toBeNil()
		expect(state.place).toBe("Back")
	end)

	it("a draw-cut under a cover still takes the sword at once", function()
		local state = SheathState.new("Back")
		local out = state:step(FRAME, input({ cut = true, covered = true }))
		expect(out.place).toBe("Hand")
	end)
end)

describe("SheathState.onEvent", function()
	it("takes an event only when it fits the target or a cut", function()
		local state = SheathState.new("Back")
		expect(state:onEvent("WeaponDraw", input())).toBeNil()
		expect(state:onEvent("WeaponDraw", input({ cut = true }))).toBe("Hand")
		expect(state:onEvent("WeaponSheathe", input({ cut = true }))).toBeNil()
		expect(state:onEvent("WeaponSheathe", input({ target = true }))).toBeNil()
		expect(state:onEvent("WeaponSheathe", input())).toBe("Back")
		-- Already there, or another kind: nothing new.
		expect(state:onEvent("WeaponSheathe", input())).toBeNil()
		expect(state:onEvent("Footstep", input({ target = true }))).toBeNil()
		expect(state.place).toBe("Back")
	end)
end)

describe("SheathState.riseFilter", function()
	local REMOTE = ChoreoData.sheath.remoteDrawDelay

	it("a rise counts once it has held the delay; the step that first sees it counts", function()
		local filter = SheathState.riseFilter(REMOTE, false)
		expect(filter.value).toBe(false)
		local steps = 0
		repeat
			steps += 1
		until filter:step(FRAME, true) or steps > 60
		expect(steps).toBe(math.ceil(REMOTE / FRAME - 1e-6))
		expect(filter.value).toBe(true)
		-- It stays true while the raw value does.
		expect(filter:step(FRAME, true)).toBe(true)
	end)

	it("covers an attack three 60 Hz frames behind its Drawn, not four", function()
		local filter = SheathState.riseFilter(REMOTE, false)
		for _ = 1, 3 do
			expect(filter:step(FRAME, true)).toBe(false)
		end
		expect(filter:step(FRAME, true)).toBe(true)
	end)

	it("a fall counts at once, and a new rise waits the whole delay again", function()
		local filter = SheathState.riseFilter(REMOTE, false)
		run(filter :: any, 0.5, true)
		expect(filter.value).toBe(true)
		expect(filter:step(FRAME, false)).toBe(false)
		expect(filter:step(FRAME, true)).toBe(false)
		expect(filter:step(REMOTE, true)).toBe(true)
		-- A flicker shorter than the delay never shows.
		filter:step(FRAME, false)
		expect(filter:step(REMOTE / 2, true)).toBe(false)
		expect(filter:step(FRAME, false)).toBe(false)
		expect(filter:step(REMOTE / 2, true)).toBe(false)
	end)

	it("starting true counts as already held; a slow step passes the delay in one go", function()
		local filter = SheathState.riseFilter(REMOTE, true)
		expect(filter.value).toBe(true)
		expect(filter:step(FRAME, true)).toBe(true)
		local slow = SheathState.riseFilter(REMOTE, false)
		expect(slow:step(1 / 10, true)).toBe(true)
	end)
end)
