--!strict
-- FrameClock counts rendered frames from the first frame that shows a change (issue 3): a flash
-- put up inside a frame's render steps (the local rig's contact) shows on that frame, one put up
-- after them (a HitConfirmed, Heartbeat) on the next, and either way exactly N frames draw it. The
-- engine's render steps, Heartbeat and clock are hand-driven through FrameClock.bind; a frame is
-- its first render step, the render steps between, its last render step, the draw (sampled
-- here), then what runs after the draw (remote events) and Heartbeat.
local FrameClock = Harness.load("src/client/fx/FrameClock")
local OutlineManager = Harness.load("src/client/fx/OutlineManager")
local fx = Harness.load("src/shared/data/fx")
local choreo = Harness.load("src/shared/data/choreo")
local combat = Harness.load("src/shared/data/combat")

type Driver = {
	-- One frame: `during` runs inside its render steps, `after` once it drew; returns what the
	-- frame drew (`sample` read at the draw).
	frame: (during: (() -> ())?, after: (() -> ())?) -> any,
	heartbeat: () -> (),
	sleep: (seconds: number) -> (),
	sample: (fn: () -> any) -> (),
	finish: () -> (),
}

local function drive(): Driver
	local clock = 0
	local startFn: ((dt: number) -> ())? = nil
	local endFn: ((dt: number) -> ())? = nil
	local watchFn: ((dt: number) -> ())? = nil
	local sampler: () -> any = function(): any
		return nil
	end
	FrameClock.bind({
		now = function(): number
			return clock
		end,
		onFrameStart = function(fn)
			startFn = fn
			return function()
				startFn = nil
			end
		end,
		onFrameEnd = function(fn)
			endFn = fn
			return function()
				endFn = nil
			end
		end,
		onHeartbeat = function(fn)
			watchFn = fn
			return function()
				watchFn = nil
			end
		end,
	})
	local function heartbeat()
		if watchFn ~= nil then
			(watchFn :: (number) -> ())(1 / 60)
		end
	end
	return {
		frame = function(during: (() -> ())?, after: (() -> ())?): any
			clock += 1 / 60
			if startFn ~= nil then
				(startFn :: (number) -> ())(1 / 60)
			end
			if during ~= nil then
				during()
			end
			if endFn ~= nil then
				(endFn :: (number) -> ())(1 / 60)
			end
			local drew = sampler()
			if after ~= nil then
				after()
			end
			heartbeat()
			return drew
		end,
		heartbeat = heartbeat,
		sleep = function(seconds: number)
			local until_ = clock + seconds
			while clock < until_ do
				clock += 1 / 60
				heartbeat()
			end
		end,
		sample = function(fn: () -> any)
			sampler = fn
		end,
		finish = function()
			FrameClock.bind(nil)
		end,
	}
end

-- Frames (up to `limit`) whose draw shows `on` true, starting with the frame `first` drives.
local function countLit(d: Driver, first: (Driver) -> any, limit: number): { boolean }
	local drawn: { boolean } = { first(d) == true }
	for _ = 2, limit do
		table.insert(drawn, d.frame() == true)
	end
	return drawn
end

describe("FrameClock counts rendered frames", function()
	it("a change made inside the render steps shows on that frame and lasts exactly N frames", function()
		for _, n in { 1, 2, 3 } do
			local d = drive()
			local on = false
			d.sample(function(): any
				return on
			end)
			d.frame()
			local drawn = countLit(d, function(driver: Driver): any
				return driver.frame(function()
					on = true
					FrameClock.after(n, function()
						on = false
					end)
				end)
			end, 6)
			local expected: { boolean } = {}
			for index = 1, 6 do
				expected[index] = index <= n
			end
			expect(drawn).toEqual(expected)
			d.finish()
		end
	end)

	it("a change made after the draw (a remote event) shows from the next frame for exactly N frames", function()
		for _, n in { 2, 3 } do
			local d = drive()
			local on = false
			d.sample(function(): any
				return on
			end)
			d.frame()
			local drawn = countLit(d, function(driver: Driver): any
				return driver.frame(nil, function()
					on = true
					FrameClock.after(n, function()
						on = false
					end)
				end)
			end, 7)
			local expected: { boolean } = { false }
			for index = 2, 7 do
				expected[index] = index <= n + 1
			end
			expect(drawn).toEqual(expected)
			d.finish()
		end
	end)

	it("a change made on Heartbeat counts the same as one made after the draw", function()
		local d = drive()
		local on = false
		d.sample(function(): any
			return on
		end)
		d.frame()
		on = true
		FrameClock.after(2, function()
			on = false
		end)
		d.heartbeat()
		expect({ d.frame() == true, d.frame() == true, d.frame() == true }).toEqual({ true, true, false })
		d.finish()
	end)

	it("cancels a callback, and runs a callback a callback schedules on its own count", function()
		local d = drive()
		d.frame()
		local ran = 0
		local cancel = FrameClock.after(1, function()
			ran += 1
		end)
		cancel()
		for _ = 1, 4 do
			d.frame()
		end
		expect(ran).toBe(0)
		local order: { string } = {}
		d.frame(function()
			FrameClock.after(1, function()
				table.insert(order, "first")
				FrameClock.after(1, function()
					table.insert(order, "second")
				end)
			end)
		end)
		d.frame()
		expect(order).toEqual({ "first" })
		d.frame()
		expect(order).toEqual({ "first", "second" })
		d.finish()
	end)

	it("a flash up when the display goes to sleep is gone before the frame that comes back", function()
		local d = drive()
		local on = false
		d.sample(function(): any
			return on
		end)
		d.frame()
		d.frame(function()
			on = true
			FrameClock.after(2, function()
				on = false
			end)
		end)
		-- Asleep: no render step, Heartbeat on; within a jump nothing ends yet (a long frame).
		d.sleep(choreo.stall.jumpSeconds * 0.5)
		expect(on).toBe(true)
		d.sleep(choreo.stall.jumpSeconds)
		expect(on).toBe(false)
		expect(d.frame()).toBe(false)
		d.finish()
	end)

	it("with no render step (Lune, a server) it falls back to the 60 fps frame length", function()
		FrameClock.bind({
			onFrameStart = function()
				return nil
			end,
		})
		local ran = false
		FrameClock.after(2, function()
			ran = true
		end)
		task.wait(3 * combat.hitStopFrameSeconds + 0.05)
		expect(ran).toBe(true)
		FrameClock.bind(nil)
	end)
end)

describe("OutlineManager flashes for exactly highlightFlashFrames drawn frames (issue 3)", function()
	local function flashed(model: Model): boolean
		local highlight = model:FindFirstChild("Outline") :: Highlight
		return highlight ~= nil and math.abs(highlight.FillTransparency - fx.outline.flashFillTransparency) < 1e-3
	end

	it("a HitConfirmed flash (after the draw) draws white on 2 frames, not 1", function()
		local d = drive()
		local model = Instance.new("Model")
		d.sample(function(): any
			return flashed(model)
		end)
		d.frame()
		local drawn = countLit(d, function(driver: Driver): any
			return driver.frame(nil, function()
				OutlineManager.flash(model, "SystemWhite", combat.highlightFlashFrames)
			end)
		end, 5)
		expect(drawn).toEqual({ false, true, true, false, false })
		OutlineManager.unregister(model)
		d.finish()
	end)

	it("a predicted contact flash (the local render step) draws white on the contact frame and the next", function()
		local d = drive()
		local model = Instance.new("Model")
		d.sample(function(): any
			return flashed(model)
		end)
		d.frame()
		local drawn = countLit(d, function(driver: Driver): any
			return driver.frame(function()
				OutlineManager.flash(model, "SystemWhite", combat.highlightFlashFrames)
			end)
		end, 4)
		expect(drawn).toEqual({ true, true, false, false })
		OutlineManager.unregister(model)
		d.finish()
	end)
end)

describe("FrameClock.pace", function()
	it("is the median of the last render-step frame lengths: one late frame never moves it", function()
		local impact = Harness.load("src/shared/data/impact")
		local startFn: ((number) -> ())? = nil
		FrameClock.bind({
			now = function(): number
				return 0
			end,
			onFrameStart = function(fn)
				startFn = fn
				return function() end
			end,
			onFrameEnd = function()
				return function() end
			end,
			onHeartbeat = function()
				return function() end
			end,
		})
		expect(FrameClock.pace()).toBeNil()
		local F = 1 / 60
		for _, dt in { F, F, 2.5 * F, F, F } do
			(startFn :: (number) -> ())(dt)
		end
		expect(FrameClock.pace()).toBeCloseTo(F, 1e-9); -- A stall's frame is no pace at all; a steady 30 fps takes over.
		(startFn :: (number) -> ())(impact.timing.maxPaceSeconds * 5)
		expect(FrameClock.pace()).toBeCloseTo(F, 1e-9)
		for _ = 1, impact.timing.paceSamples do
			(startFn :: (number) -> ())(2 * F)
		end
		expect(FrameClock.pace()).toBeCloseTo(2 * F, 1e-9)
		FrameClock.bind(nil)
		expect(FrameClock.pace()).toBeNil()
	end)
end)
