local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")

local function clip(keys, events, loop)
	return {
		id = "test/clip",
		rig = "PlayerR15",
		duration = 1,
		loop = loop or false,
		layer = "FullBody",
		keys = keys,
		events = events or {},
	}
end

describe("ClipSampler", function()
	it("holds the first key before it and the last key after it", function()
		local c = clip({
			{ time = 0.2, easing = "Hold", joints = { RightShoulder = { rot = { 10, 0, 0 } } } },
			{ time = 0.8, easing = "Linear", joints = { RightShoulder = { rot = { 50, 0, 0 } } } },
		})
		expect(ClipSampler.sample(c, 0).RightShoulder.rot[1]).toBe(10)
		expect(ClipSampler.sample(c, 0.95).RightShoulder.rot[1]).toBe(50)
		expect(ClipSampler.sample(c, 5).RightShoulder.rot[1]).toBe(50)
	end)

	it("interpolates with the easing of the key being approached", function()
		local c = clip({
			{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 0, 0 } } } },
			{ time = 1, easing = "Linear", joints = { Neck = { rot = { 0, 90, 0 } } } },
		})
		expect(ClipSampler.sample(c, 0.5).Neck.rot[2]).toBeCloseTo(45)
		c.keys[2].easing = "ExpoOut"
		expect(ClipSampler.sample(c, 0.5).Neck.rot[2]).toBeGreaterThan(80)
	end)

	it("a joint missing from a key holds its last value", function()
		local c = clip({
			{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 30, 0 } }, Waist = { rot = { 5, 0, 0 } } } },
			{ time = 0.5, easing = "Linear", joints = { Neck = { rot = { 0, 60, 0 } } } },
			{ time = 1, easing = "Linear", joints = { Waist = { rot = { 25, 0, 0 } } } },
		})
		local mid = ClipSampler.sample(c, 0.25)
		expect(mid.Waist.rot[1]).toBe(5)
		local late = ClipSampler.sample(c, 0.75)
		expect(late.Neck.rot[2]).toBe(60)
		expect(late.Waist.rot[1]).toBeCloseTo(15)
	end)

	it("looping clips wrap from the last key back to the first (first key's easing governs the wrap)", function()
		local c = clip({
			{ time = 0, easing = "Linear", joints = { Neck = { rot = { 0, 0, 0 } } } },
			{ time = 0.5, easing = "Linear", joints = { Neck = { rot = { 0, 10, 0 } } } },
		}, {}, true)
		expect(ClipSampler.sample(c, 0.75).Neck.rot[2]).toBeCloseTo(5)
		expect(ClipSampler.sample(c, 1.25).Neck.rot[2]).toBeCloseTo(5)
	end)

	it("root motion and hit windows come from the clip", function()
		local c = clip({
			{ time = 0, easing = "Hold", joints = {}, root = { pos = { 0, 0, 0 } } },
			{ time = 1, easing = "Linear", joints = {}, root = { pos = { 0, 0, -6 } } },
		}, {
			{ time = 0.3, kind = "HitWindowOpen" },
			{ time = 0.5, kind = "HitWindowClose" },
			{ time = 0.6, kind = "HitWindowOpen" },
			{ time = 0.7, kind = "HitWindowClose" },
		})
		expect(ClipSampler.rootMotionAt(c, 0.5)[3]).toBeCloseTo(-3)
		expect(ClipSampler.hitWindows(c)).toEqual({ { open = 0.3, close = 0.5 }, { open = 0.6, close = 0.7 } })
		expect(#ClipSampler.events(c, 0.25, 0.55)).toBe(2)
		expect(#ClipSampler.events(c, 0.5, 0.55)).toBe(0)
	end)

	it("blend and add combine offset sets", function()
		local a = { Neck = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } } }
		local b = { Neck = { pos = { 0, 0, 0 }, rot = { 0, 40, 0 } }, Waist = { pos = { 0, 0, 0 }, rot = { 10, 0, 0 } } }
		local blended = ClipSampler.blend(a, b, 0.5)
		expect(blended.Neck.rot[2]).toBeCloseTo(20)
		expect(blended.Waist.rot[1]).toBeCloseTo(5)
		local added = ClipSampler.add(a, b, 0.5)
		expect(added.Neck.rot[2]).toBeCloseTo(20)
		expect(added.Waist.rot[1]).toBeCloseTo(5)
	end)

	it("toCFrame builds a CFrame from studs and degrees", function()
		local cf = ClipSampler.toCFrame({ pos = { 1, 2, 3 }, rot = { 0, 90, 0 } })
		expect(cf.Position.X).toBeCloseTo(1)
		expect(cf.LookVector.X).toBeCloseTo(-1, 1e-5)
	end)
end)
