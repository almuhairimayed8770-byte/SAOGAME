--!strict
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

	it("a key that re-authors a joint with only one component resets the other to rest", function()
		local c = clip({
			{ time = 0, easing = "Hold", joints = { Neck = { pos = { 1, 0, 0 }, rot = { 0, 30, 0 } } } },
			{ time = 1, easing = "Linear", joints = { Neck = { rot = { 0, 30, 0 } } } },
		})
		expect(ClipSampler.sample(c, 0).Neck.pos[1]).toBe(1)
		expect(ClipSampler.sample(c, 1).Neck.pos[1]).toBe(0)
		expect(ClipSampler.sample(c, 0.5).Neck.pos[1]).toBeCloseTo(0.5)
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

	it("rootMotionAt agrees with the root sample in every region of the clip", function()
		local c = clip({
			{ time = 0.2, easing = "Hold", joints = { Neck = { rot = { 0, 5, 0 } } }, root = { pos = { 0, 0, -1 } } },
			{ time = 0.5, easing = "Linear", joints = { Neck = { rot = { 0, 10, 0 } } } },
			{ time = 0.8, easing = "QuadOut", joints = {}, root = { pos = { 2, 0, -4 } } },
		}, {}, true)
		for _, time in { 0, 0.1, 0.35, 0.65, 0.8, 0.9, 1.3 } do
			expect(ClipSampler.rootMotionAt(c, time)).toEqual(ClipSampler.sample(c, time)[ClipSampler.ROOT_KEY].pos)
		end
		local still = clip({ { time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 5, 0 } } } } })
		expect(ClipSampler.rootMotionAt(still, 0.5)).toEqual({ 0, 0, 0 })
		expect(ClipSampler.sample(still, 0.5)[ClipSampler.ROOT_KEY]).toBeNil()
		expect(ClipSampler.rootMotionAt(clip({}), 0.5)).toEqual({ 0, 0, 0 })
	end)

	it("repeated sample() calls return equal results in fresh tables", function()
		local c = clip({
			{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 0, 0 } }, Waist = { pos = { 0, 1, 0 } } } },
			{ time = 1, easing = "Linear", joints = { Neck = { rot = { 0, 90, 0 } } }, root = { pos = { 0, 0, -2 } } },
		})
		for _, time in { 0, 0.5, 1, 2 } do
			local first = ClipSampler.sample(c, time)
			local second = ClipSampler.sample(c, time)
			expect(second).toEqual(first)
			expect(second).never.toBe(first)
			expect(second.Neck).never.toBe(first.Neck)
			-- Callers blend and mutate their result; the next sample must not see it.
			first.Neck = nil
			first.Waist.pos = { 9, 9, 9 }
			expect(ClipSampler.sample(c, time)).toEqual(second)
		end
	end)

	it("jointNames serves one cached, frozen list per clip", function()
		local c = clip({
			{ time = 0, easing = "Hold", joints = { Waist = { rot = { 0, 0, 0 } } } },
			{ time = 1, easing = "Linear", joints = { Neck = { rot = { 0, 90, 0 } } }, root = { pos = { 0, 0, -2 } } },
		})
		local names = ClipSampler.jointNames(c)
		expect(names).toEqual({ "Neck", "Waist", ClipSampler.ROOT_KEY })
		expect(table.isfrozen(names)).toBe(true)
		expect(ClipSampler.jointNames(c)).toBe(names)
		ClipSampler.sample(c, 0.5)
		expect(ClipSampler.jointNames(c)).toBe(names)
		-- A different clip table with the same content has its own entry.
		local twin = clip(c.keys)
		expect(ClipSampler.jointNames(twin)).toEqual(names)
		expect(ClipSampler.jointNames(twin)).never.toBe(names)
	end)

	it("edits to a clip's keys are served stale until invalidate; then the new joint appears", function()
		local c = clip({
			{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 10, 0 } } } },
			{ time = 1, easing = "Linear", joints = { Neck = { rot = { 0, 20, 0 } } } },
		})
		local names = ClipSampler.jointNames(c)
		expect(names).toEqual({ "Neck" })
		-- Clip tables are immutable after load: the sampler caches the joint set and which key
		-- authors each held value, so a key edit without invalidate is not seen.
		c.keys[2].joints.Waist = { rot = { 5, 0, 0 } }
		table.insert(c.keys, { time = 0.5, easing = "Linear", joints = { Neck = { rot = { 0, 90, 0 } } } })
		table.sort(c.keys, function(a, b)
			return a.time < b.time
		end)
		expect(ClipSampler.jointNames(c)).toBe(names)
		expect(ClipSampler.sample(c, 1).Waist).toBeNil()
		-- The stale structure never errors: key 2 is read live (now the inserted key, 90) while
		-- key 3, which the cache never saw, degrades to rest, so the midpoint reads 45 instead of 55.
		expect(ClipSampler.sample(c, 0.75).Neck.rot[2]).toBeCloseTo(45)
		expect(ClipSampler.sample(c, 2).Neck.rot[2]).toBe(0)
		ClipSampler.invalidate(c)
		expect(ClipSampler.jointNames(c)).toEqual({ "Neck", "Waist" })
		expect(ClipSampler.jointNames(c)).never.toBe(names)
		expect(ClipSampler.sample(c, 1).Waist.rot[1]).toBe(5)
		expect(ClipSampler.sample(c, 0.5).Neck.rot[2]).toBe(90)
		expect(ClipSampler.sample(c, 0.75).Neck.rot[2]).toBeCloseTo(55)
		expect(ClipSampler.sample(c, 2).Neck.rot[2]).toBe(20)
		expect(ClipSampler.sample(c, 0.25).Waist.rot[1]).toBe(0)
		-- Replacing a joint's offset table in place is read live; no invalidate needed for values.
		c.keys[1].joints.Neck = { rot = { 0, 40, 0 } }
		expect(ClipSampler.sample(c, 0).Neck.rot[2]).toBe(40)
		-- Invalidating a clip the sampler never saw is harmless.
		ClipSampler.invalidate(clip({}))
	end)

	it("blend and add combine offset sets", function()
		local a = { Neck = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } } }
		local b =
			{ Neck = { pos = { 0, 0, 0 }, rot = { 0, 40, 0 } }, Waist = { pos = { 0, 0, 0 }, rot = { 10, 0, 0 } } }
		local blended = ClipSampler.blend(a, b, 0.5)
		expect(blended.Neck.rot[2]).toBeCloseTo(20)
		expect(blended.Waist.rot[1]).toBeCloseTo(5)
		local added = ClipSampler.add(a, b, 0.5)
		expect(added.Neck.rot[2]).toBeCloseTo(20)
		expect(added.Waist.rot[1]).toBeCloseTo(5)
	end)

	it("blend and add leave their inputs untouched and return fresh tables", function()
		local a = { Neck = { pos = { 1, 2, 3 }, rot = { 0, 10, 0 } }, Waist = { pos = { 0, 0, 0 }, rot = { 5, 0, 0 } } }
		local b =
			{ Neck = { pos = { 0, 0, 0 }, rot = { 0, 30, 0 } }, LeftHip = { pos = { 0, 1, 0 }, rot = { 0, 0, 8 } } }
		local aCopy =
			{ Neck = { pos = { 1, 2, 3 }, rot = { 0, 10, 0 } }, Waist = { pos = { 0, 0, 0 }, rot = { 5, 0, 0 } } }
		local bCopy =
			{ Neck = { pos = { 0, 0, 0 }, rot = { 0, 30, 0 } }, LeftHip = { pos = { 0, 1, 0 }, rot = { 0, 0, 8 } } }
		local added = ClipSampler.add(a, b, 0.5)
		expect(added).toEqual({
			Neck = { pos = { 1, 2, 3 }, rot = { 0, 25, 0 } },
			Waist = { pos = { 0, 0, 0 }, rot = { 5, 0, 0 } },
			LeftHip = { pos = { 0, 0.5, 0 }, rot = { 0, 0, 4 } },
		})
		expect(added.Waist).never.toBe(a.Waist)
		expect(added.Waist.pos).never.toBe(a.Waist.pos)
		expect(added.LeftHip).never.toBe(b.LeftHip)
		local blended = ClipSampler.blend(a, b, 0.25)
		expect(blended).toEqual({
			Neck = { pos = { 0.75, 1.5, 2.25 }, rot = { 0, 15, 0 } },
			Waist = { pos = { 0, 0, 0 }, rot = { 3.75, 0, 0 } },
			LeftHip = { pos = { 0, 0.25, 0 }, rot = { 0, 0, 2 } },
		})
		expect(blended.Neck).never.toBe(a.Neck)
		expect(a).toEqual(aCopy)
		expect(b).toEqual(bCopy)
	end)

	it("toCFrame builds a CFrame from studs and degrees", function()
		local cf = ClipSampler.toCFrame({ pos = { 1, 2, 3 }, rot = { 0, 90, 0 } })
		expect(cf.Position.X).toBeCloseTo(1)
		expect(cf.LookVector.X).toBeCloseTo(-1, 1e-5)
	end)
end)
