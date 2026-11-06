--!strict
-- Mixer.seek (D-138): one handle's clock moved forward at once, whatever the pause or the time
-- scale, as if it had played there. The Art hold a render stall kept from its hold pose uses it.
local Mixer = Harness.load("src/client/choreo/Mixer")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")

local FRAME = 1 / 60

-- A one-second clip that turns the neck, walks the root 3 studs forward and carries events at
-- 0, 0.1, 0.2 and 0.5.
local function clip(id: string, overrides: { [string]: any }?): any
	local def: { [string]: any } = {
		id = id,
		rig = "PlayerR15",
		duration = 1,
		loop = false,
		layer = "FullBody",
		keys = {
			{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 0, 0 } } }, root = { pos = { 0, 0, 0 } } },
			{ time = 1, easing = "Linear", joints = { Neck = { rot = { 0, 100, 0 } } }, root = { pos = { 0, 0, -3 } } },
		},
		events = {
			{ time = 0, kind = "Sfx", data = { id = "start" } },
			{ time = 0.1, kind = "ActivationHold" } :: any,
			{ time = 0.2, kind = "Sfx", data = { id = "middle" } },
			{ time = 0.5, kind = "HitWindowOpen" } :: any,
		},
		blendIn = 0,
		blendOut = 0,
	}
	local extra: { [string]: any } = overrides or {}
	for key, value in extra do
		def[key] = value
	end
	return def
end

local function kinds(events: { any }): { string }
	local list = {}
	for _, fired in events do
		table.insert(list, fired.event.kind)
	end
	return list
end

local function rootZ(def: any, clipTime: number): number
	return ClipSampler.rootMotionAt(def, clipTime)[3]
end

describe("Mixer.seek", function()
	it("moves the clock on at once and returns the events it crosses, unmarked, each once", function()
		local mixer = Mixer.new()
		local def = clip("a")
		local handle = mixer:play(def)
		local first = mixer:step(0.05)
		expect(kinds(first.events)).toEqual({ "Sfx" })
		local crossed = mixer:seek(handle, 0.3)
		expect(handle.time).toBe(0.3)
		expect(kinds(crossed)).toEqual({ "ActivationHold", "Sfx" })
		for _, fired in crossed do
			expect(fired.jumped).toBe(false)
			expect(fired.handle).toBe(handle)
			expect(fired.clipId).toBe("a")
		end
		-- The next step goes on from there: nothing it crossed fires again.
		local after = mixer:step(0.25)
		expect(kinds(after.events)).toEqual({ "HitWindowOpen" })
	end)

	it("a handle never stepped yet fires the event at its start too", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a"))
		expect(kinds(mixer:seek(handle, 0.15))).toEqual({ "Sfx", "ActivationHold" })
		expect(kinds(mixer:step(FRAME).events)).toEqual({})
	end)

	it("moves no root: the next step's root delta starts where the seek left the clip", function()
		local mixer = Mixer.new()
		local def = clip("a")
		local handle = mixer:play(def)
		mixer:step(0.05)
		mixer:seek(handle, 0.4)
		local result = mixer:step(0.1)
		expect(result.rootDelta[3]).toBeCloseTo(rootZ(def, 0.5) - rootZ(def, 0.4), 1e-9)
		-- Not the 0.05 -> 0.5 a step would have moved the body.
		expect(math.abs(result.rootDelta[3] - (rootZ(def, 0.5) - rootZ(def, 0.05))) > 0.5).toBe(true)
	end)

	it("moves the clock through a hit-stop and at time scale zero; the clip then holds there", function()
		local mixer = Mixer.new()
		local def = clip("a")
		local handle = mixer:play(def)
		mixer:step(FRAME)
		mixer:setTimeScale(0)
		mixer:hitStop(10)
		expect(kinds(mixer:seek(handle, 0.25))).toEqual({ "ActivationHold", "Sfx" })
		expect(handle.time).toBe(0.25)
		-- The pose shows the seek's time at the next step (the neck is keyed linearly 0 -> 100).
		local result = mixer:step(FRAME)
		expect(handle.time).toBe(0.25)
		expect(result.offsets.Neck.rot[2]).toBeCloseTo(25, 1e-6)
		expect(result.rootDelta[3]).toBe(0)
		expect(#result.events).toBe(0)
	end)

	it("never moves a clock back, nor a finished handle, nor a looping clip to or past its end", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a"))
		mixer:step(0.3)
		expect(#mixer:seek(handle, 0.2)).toBe(0)
		expect(#mixer:seek(handle, 0.3)).toBe(0)
		expect(handle.time).toBeCloseTo(0.3, 1e-12)

		local looping = mixer:play(clip("loop", { loop = true, layer = "Additive" }))
		mixer:step(0.1)
		local before = looping.time
		expect(#mixer:seek(looping, 1)).toBe(0)
		expect(#mixer:seek(looping, 1.4)).toBe(0)
		expect(looping.time).toBe(before)

		local stopped = mixer:play(clip("b", { layer = "UpperBody" }))
		mixer:step(FRAME)
		mixer:stop(stopped, 0)
		mixer:step(FRAME)
		expect(stopped.done).toBe(true)
		local at = stopped.time
		expect(#mixer:seek(stopped, 0.6)).toBe(0)
		expect(stopped.time).toBe(at)
	end)

	it("stops a one-shot clip at its end; the end is the next step's to report", function()
		local mixer = Mixer.new()
		local def = clip("a")
		local handle = mixer:play(def)
		mixer:step(FRAME)
		local crossed = mixer:seek(handle, 5)
		expect(handle.time).toBe(def.duration)
		expect(kinds(crossed)).toEqual({ "ActivationHold", "Sfx", "HitWindowOpen" })
		expect(handle.ended).toBe(false)
		local result = mixer:step(FRAME)
		expect(handle.ended).toBe(true)
		expect(#result.finished).toBe(1)
		expect(result.finished[1]).toBe(handle)
		expect(result.rootDelta[3]).toBe(0)
	end)
end)
