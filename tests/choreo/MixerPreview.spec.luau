--!strict
--[[
	Mixer.preview: what a handle's limbs show once the next step of `dt` has moved its envelope and
	its external weight, read before that step runs. A caller that must agree with this step's pose
	(Locomotion's drawn sprint pose giving way to Draw and Sheathe) reads it instead of copying the
	mixer's blend rule. Every case previews each live handle, steps, and compares with what the step
	left: the eased envelope times the weight (0 once a handle is done).
]]

local Mixer = Harness.load("src/client/choreo/Mixer")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Easing = Harness.load("src/shared/util/Easing")

local FRAME = 1 / 60

local function clip(id: string, overrides: { [string]: any }?): any
	local def: { [string]: any } = {
		id = id,
		rig = "PlayerR15",
		duration = 2,
		loop = false,
		layer = "FullBody",
		keys = {
			{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 0, 0 } } } },
			{ time = 2, easing = "Linear", joints = { Neck = { rot = { 0, 100, 0 } } } },
		},
		events = {},
		blendIn = 0.2,
		blendOut = 0.3,
	}
	for key, value in overrides or {} do
		def[key] = value
	end
	return def
end

local function shown(handle: any): number
	if handle.done then
		return 0
	end
	return Easing.evaluate(ChoreoData.blendEasing, handle.fade) * handle.weight
end

-- Previews every handle, steps `dt`, and checks each preview against the step's result. Returns the
-- largest preview seen (so a case can tell it measured a moving envelope).
local function stepAndCompare(mixer: any, dt: number): number
	local before: { [any]: number } = {}
	local largest = 0
	for _, handle in mixer:handles() do
		local value = mixer:preview(handle, dt)
		before[handle] = value
		largest = math.max(largest, value)
	end
	mixer:step(dt)
	for handle, value in before do
		expect(value).toBeCloseTo(shown(handle), 1e-9)
	end
	return largest
end

describe("Mixer.preview foresees the next step's blend", function()
	it("is part of the mixer's interface", function()
		expect(type(Mixer.preview)).toBe("function")
	end)

	it("a blend in and a stop's blend out, frame by frame and across an uneven step", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a"))
		local seen = 0
		for _ = 1, 8 do
			seen = math.max(seen, stepAndCompare(mixer, FRAME))
		end
		expect(seen).toBeGreaterThan(0)
		mixer:stop(handle, 0.25)
		stepAndCompare(mixer, 0.037)
		for _ = 1, 20 do
			stepAndCompare(mixer, FRAME)
		end
		expect(handle.done).toBe(true)
		expect(mixer:preview(handle, FRAME)).toBe(0)
	end)

	it("a stop with no blend-out shows nothing after the step", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a", { blendIn = 0 }))
		stepAndCompare(mixer, FRAME)
		mixer:stop(handle, 0)
		expect(mixer:preview(handle, FRAME)).toBe(0)
		stepAndCompare(mixer, FRAME)
	end)

	it("a hit-stop holds the envelope; an immediate stop still lands; a death tremor keeps moving", function()
		local mixer = Mixer.new()
		local held = mixer:play(clip("held", { layer = "Base" }))
		local cut = mixer:play(clip("cut", { layer = "UpperBody" }))
		local tremor = mixer:play(clip("tremor", { layer = "Additive" }), { ignorePause = true })
		stepAndCompare(mixer, FRAME)
		mixer:hitStop(4)
		local frozenAt = shown(held)
		expect(mixer:preview(held, FRAME)).toBeCloseTo(frozenAt, 1e-9)
		local tremorBefore = shown(tremor)
		expect(mixer:preview(tremor, FRAME)).toBeGreaterThan(tremorBefore)
		stepAndCompare(mixer, FRAME)
		mixer:stop(cut, 0)
		stepAndCompare(mixer, FRAME)
		expect(cut.done).toBe(true)
		for _ = 1, 6 do
			stepAndCompare(mixer, FRAME)
		end
	end)

	it("a render stall: a pause that ends inside the gap moves by the rest; a clip played in it by its age", function()
		local mixer = Mixer.new()
		local early = mixer:play(clip("early", { layer = "Base", blendIn = 0.5 }))
		stepAndCompare(mixer, FRAME)
		mixer:hitStop(6)
		local gap = ChoreoData.stall.jumpSeconds + 0.3
		-- Played 0.25 s before the wake: the hit-stop's rest still holds the first part of that.
		local late = mixer:play(clip("late", { layer = "UpperBody", blendIn = 0.4 }), { sinceStep = gap - 0.25 })
		local value = mixer:preview(early, gap)
		expect(value).toBeGreaterThan(shown(early))
		local age = 0.25 - mixer:pauseRemaining()
		expect(age).toBeGreaterThan(0)
		expect(mixer:preview(late, gap)).toBeCloseTo(Easing.evaluate(ChoreoData.blendEasing, age / 0.4), 1e-9)
		stepAndCompare(mixer, gap)
		stepAndCompare(mixer, FRAME)
	end)

	it("a long pause holds through a stall shorter than it", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a", { blendIn = 0.5 }))
		stepAndCompare(mixer, FRAME)
		mixer:hitStop(30)
		expect(mixer:preview(handle, 0.2)).toBeCloseTo(shown(handle), 1e-9)
		stepAndCompare(mixer, 0.2)
	end)

	it("retargeted blend-space weights and the fallback idle", function()
		local mixer = Mixer.new()
		local idle = mixer:play(clip("idle", { layer = "Base", loop = true }), { fallback = true })
		for _ = 1, 3 do
			stepAndCompare(mixer, FRAME)
		end
		local walk = mixer:play(clip("walk", { layer = "Base", loop = true }), { coexist = true, weight = 0 })
		local run = mixer:play(clip("run", { layer = "Base", loop = true }), { coexist = true, weight = 0.6 })
		mixer:setWeight(walk, 1)
		mixer:setWeight(run, 0)
		for _ = 1, 30 do
			stepAndCompare(mixer, FRAME)
		end
		expect(walk.weight).toBe(1)
		expect(idle.weight).toBeLessThan(1)
		mixer:stop(walk, 0.1)
		mixer:stop(run, 0)
		for _ = 1, 30 do
			stepAndCompare(mixer, FRAME)
		end
		expect(idle.weight).toBe(1)
	end)
end)

describe("Mixer.hold", function()
	it("stops the clock where it is: no events, no root; the envelope still fades it out", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a", {
			blendIn = 0,
			keys = {
				{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 0, 0 } } }, root = { pos = { 0, 0, 0 } } },
				{
					time = 2,
					easing = "Linear",
					joints = { Neck = { rot = { 0, 100, 0 } } },
					root = { pos = { 0, 0, -4 } },
				},
			},
			events = { { time = 0.5, kind = "Sfx", data = { name = "whoosh.Medium" } } },
		}))
		for _ = 1, 12 do
			mixer:step(FRAME)
		end
		local at = handle.time
		mixer:stop(handle, 0.3)
		mixer:hold(handle)
		local fired, root = 0, 0
		for _ = 1, 30 do
			local result = mixer:step(FRAME)
			fired += #result.events
			root += result.rootDelta[3]
			expect(handle.time).toBe(at)
		end
		expect(fired).toBe(0)
		expect(root).toBe(0)
		expect(handle.done).toBe(true)
	end)
end)
