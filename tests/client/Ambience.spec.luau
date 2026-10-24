--!strict
-- Ambience: the Playground's bed while the local character is on the island, the rim wind rising
-- toward the island's edge across the data band, both ramped through the loop call and stopped
-- off the island or with no character. Every engine call runs through the module's seams: a
-- per-frame step the spec fires by hand, a fake character position and a recording loop; the
-- last case runs the real SfxPool.loop on the pool's own recording seams.
local Ambience = Harness.load("src/client/audio/Ambience")
local SfxPool = Harness.load("src/client/audio/SfxPool")
local fx = Harness.load("src/shared/data/fx")
local playground = Harness.load("src/shared/data/playground")
local Easing = Harness.load("src/shared/util/Easing")

local config = fx.audio.ambience
local FRAME = 1 / 60
local EPSILON = 1e-9

type Call = { name: string, gain: number }

-- A point `edge` studs inside the island's edge (negative: past it), on the +X side of the field.
local function atEdge(edge: number): Vector3
	return Vector3.new(playground.fieldRadius - edge, 3, 0)
end

-- A hand-driven world bound into the module: `frames(n)` fires the step n times at 60 fps,
-- `standAt(position)` moves the character (nil: no character), `calls` records every loop call.
local function world()
	local w = {
		calls = {} :: { Call },
		position = nil :: Vector3?,
		reads = 0,
		connections = 0,
	}
	local stepFn: ((number) -> ())? = nil

	function w.frames(count: number, dt: number?)
		for _ = 1, count do
			if stepFn ~= nil then
				(stepFn :: (number) -> ())(dt or FRAME)
			end
		end
	end

	function w.seconds(seconds: number)
		w.frames(math.ceil(seconds / FRAME - EPSILON))
	end

	function w.standAt(position: Vector3?)
		w.position = position
	end

	-- The gain of the last loop call for a bed, nil when none was made.
	function w.last(name: string): number?
		for index = #w.calls, 1, -1 do
			if w.calls[index].name == name then
				return w.calls[index].gain
			end
		end
		return nil
	end

	function w.count(name: string): number
		local count = 0
		for _, call in w.calls do
			if call.name == name then
				count += 1
			end
		end
		return count
	end

	Ambience.bind({
		onStep = function(fn: (number) -> ()): () -> ()
			stepFn = fn
			w.connections += 1
			return function()
				stepFn = nil
				w.connections -= 1
			end
		end,
		position = function(): Vector3?
			w.reads += 1
			return w.position
		end,
		loop = function(name: string, gain: number)
			table.insert(w.calls, { name = name, gain = gain })
		end,
	})
	return w
end

-- Runs `body` with a fresh world and puts the module back on the engine seams after, pass or fail.
local function scenario(body: (any) -> ())
	local w = world()
	local ok, err = pcall(body, w)
	Ambience.bind(nil)
	if not ok then
		error(err, 0)
	end
end

describe("Ambience data", function()
	it("names two real loop beds, a positive ramp and rate, and a band inside the island", function()
		local sfx = Harness.load("src/shared/data/sfx")
		for _, name in { config.bed, config.rimWind } do
			local family, entryName = name:match("^([^%.]+)%.(.+)$")
			local entry = sfx.get(family :: string, entryName :: string)
			expect(entry.loop).toBe(true)
			expect(sfx.isReal(entry)).toBe(true)
			expect(sfx.groupOf(family :: string)).toBe("SFX")
		end
		expect(config.rampSeconds).toBeGreaterThan(0)
		expect(config.sampleHz).toBeGreaterThan(0)
		expect(config.rimBand.near).toBeGreaterThanOrEqual(0)
		expect(config.rimBand.far).toBeGreaterThan(config.rimBand.near)
		expect(config.rimBand.far).toBeLessThanOrEqual(playground.fieldRadius)
		expect(config.rimFloor).toBeGreaterThan(fx.audio.stemFadeFloor)
		expect(config.rimFloor).toBeLessThan(1)
	end)
end)

describe("Ambience on the island", function()
	it("measures the edge distance inward from the field's radius, negative past it", function()
		expect(Ambience.edgeDistance(Vector3.new(0, 3, 0))).toBeCloseTo(playground.fieldRadius, EPSILON)
		expect(Ambience.edgeDistance(Vector3.new(0, -20, playground.fieldRadius - 12))).toBeCloseTo(12, EPSILON)
		expect(Ambience.edgeDistance(Vector3.new(-(playground.fieldRadius + 5), 0, 0))).toBeCloseTo(-5, EPSILON)
	end)

	it("raises the rim wind from its floor across the band, eased, to full level at the edge", function()
		local band = config.rimBand
		expect(Ambience.rimGainAt(playground.fieldRadius)).toBeCloseTo(config.rimFloor, EPSILON)
		expect(Ambience.rimGainAt(band.far)).toBeCloseTo(config.rimFloor, EPSILON)
		expect(Ambience.rimGainAt(band.near)).toBeCloseTo(1, EPSILON)
		expect(Ambience.rimGainAt(0)).toBeCloseTo(1, EPSILON)
		local middle = (band.near + band.far) / 2
		local eased = Easing.evaluate(config.rimEasing, 0.5)
		expect(Ambience.rimGainAt(middle)).toBeCloseTo(config.rimFloor + (1 - config.rimFloor) * eased, EPSILON)
		local previous = 0
		for edge = band.far + 10, band.near - 10, -5 do
			local gain = Ambience.rimGainAt(edge)
			expect(gain).toBeGreaterThanOrEqual(previous)
			previous = gain
		end
	end)

	it("ramps the bed in to full level and the rim wind to its floor at the island's middle", function()
		scenario(function(w)
			w.standAt(Vector3.new(0, 3, 0))
			Ambience.start()
			w.frames(1)
			-- One frame of the ramp: a bed never jumps.
			expect(w.last(config.bed)).toBeCloseTo(FRAME / config.rampSeconds, EPSILON)
			expect(w.last(config.rimWind)).toBeCloseTo(FRAME / config.rampSeconds, EPSILON)
			w.seconds(config.rampSeconds)
			local state = Ambience.state()
			expect(state.onIsland).toBe(true)
			expect(state.edgeDistance).toBeCloseTo(playground.fieldRadius, EPSILON)
			expect(w.last(config.bed)).toBe(1)
			expect(w.last(config.rimWind)).toBeCloseTo(config.rimFloor, EPSILON)
		end)
	end)

	it("follows the character to the rim: full wind there, the bed unchanged", function()
		scenario(function(w)
			w.standAt(atEdge(config.rimBand.far + 20))
			Ambience.start()
			w.seconds(config.rampSeconds)
			expect(w.last(config.rimWind)).toBeCloseTo(config.rimFloor, EPSILON)
			w.standAt(atEdge(config.rimBand.near / 2))
			w.seconds(config.rampSeconds)
			expect(Ambience.state().rimTarget).toBeCloseTo(1, EPSILON)
			expect(w.last(config.rimWind)).toBeCloseTo(1, EPSILON)
			expect(w.last(config.bed)).toBe(1)
		end)
	end)

	it("moves each gain by at most one frame of the ramp, and calls the loop only when it moves", function()
		scenario(function(w)
			w.standAt(atEdge(1))
			Ambience.start()
			w.seconds(config.rampSeconds * 2)
			local previous: { [string]: number } = {}
			for _, call in w.calls do
				local before = previous[call.name] or 0
				expect(math.abs(call.gain - before)).toBeLessThanOrEqual(FRAME / config.rampSeconds + EPSILON)
				expect(call.gain).never.toBe(before)
				previous[call.name] = call.gain
			end
			-- Settled: more frames make no call.
			local settled = #w.calls
			w.seconds(1)
			expect(#w.calls).toBe(settled)
		end)
	end)

	it("reads the character at sampleHz, not every frame", function()
		scenario(function(w)
			w.standAt(Vector3.new(0, 3, 0))
			Ambience.start()
			w.frames(1)
			expect(w.reads).toBe(1)
			w.seconds(2)
			-- Two seconds at sampleHz, give or take the frame each read lands on.
			expect(w.reads).toBeGreaterThanOrEqual(1 + 2 * config.sampleHz - 1)
			expect(w.reads).toBeLessThanOrEqual(1 + 2 * config.sampleHz + 1)
		end)
	end)
end)

describe("Ambience off the island", function()
	it("ramps both beds out and stops them once the character is past the edge", function()
		scenario(function(w)
			w.standAt(atEdge(5))
			Ambience.start()
			w.seconds(config.rampSeconds)
			expect(w.last(config.bed)).toBeCloseTo(1, EPSILON)
			w.standAt(atEdge(-3))
			w.frames(1)
			w.seconds(1 / config.sampleHz)
			local state = Ambience.state()
			expect(state.onIsland).toBe(false)
			expect(state.bedTarget).toBe(0)
			expect(state.rimTarget).toBe(0)
			-- Still ramping out, never cut.
			expect(w.last(config.bed)).toBeGreaterThan(0)
			w.seconds(config.rampSeconds)
			expect(w.last(config.bed)).toBe(0)
			expect(w.last(config.rimWind)).toBe(0)
			local settled = #w.calls
			w.seconds(1)
			expect(#w.calls).toBe(settled)
		end)
	end)

	it("ramps both out when the character is gone, and back in when one stands on the island again", function()
		scenario(function(w)
			w.standAt(Vector3.new(10, 3, 10))
			Ambience.start()
			w.seconds(config.rampSeconds)
			w.standAt(nil)
			w.seconds(config.rampSeconds + 1 / config.sampleHz)
			expect(Ambience.state().edgeDistance).toBeNil()
			expect(w.last(config.bed)).toBe(0)
			expect(w.last(config.rimWind)).toBe(0)
			w.standAt(Vector3.new(0, 3, 0))
			w.seconds(config.rampSeconds + 1 / config.sampleHz)
			expect(w.last(config.bed)).toBe(1)
		end)
	end)

	it("silences both at once on stop() and connects one step however often start() runs", function()
		scenario(function(w)
			w.standAt(Vector3.new(0, 3, 0))
			Ambience.start()
			Ambience.start()
			expect(w.connections).toBe(1)
			expect(Ambience.state().running).toBe(true)
			w.seconds(1)
			Ambience.stop()
			expect(w.connections).toBe(0)
			expect(w.last(config.bed)).toBe(0)
			expect(w.last(config.rimWind)).toBe(0)
			local state = Ambience.state()
			expect(state.running).toBe(false)
			expect(state.bed).toBe(0)
			expect(state.rim).toBe(0)
		end)
	end)
end)

describe("Ambience through SfxPool.loop", function()
	it("loops both beds in the pool on the island and stops them off it", function()
		local plays: { string } = {}
		local stops: { string } = {}
		SfxPool.reset()
		SfxPool.bind({
			play = function(sound: Sound): boolean
				table.insert(plays, sound.Name)
				return true
			end,
			stop = function(sound: Sound)
				table.insert(stops, sound.Name)
			end,
			preload = function(_sounds: { Instance }) end,
			onStep = function(_fn: (number) -> ()): () -> ()
				return function() end
			end,
		})
		local position: Vector3? = Vector3.new(0, 3, 0)
		local stepFn: ((number) -> ())? = nil
		local ok, err = pcall(function()
			Ambience.bind({
				onStep = function(fn: (number) -> ()): () -> ()
					stepFn = fn
					return function()
						stepFn = nil
					end
				end,
				position = function(): Vector3?
					return position
				end,
			})
			Ambience.start()
			local function run(seconds: number)
				for _ = 1, math.ceil(seconds / FRAME) do
					(stepFn :: (number) -> ())(FRAME)
				end
			end
			run(config.rampSeconds)
			expect(plays).toEqual({ config.bed, config.rimWind })
			position = atEdge(-10)
			run(config.rampSeconds + 1 / config.sampleHz)
			table.sort(stops)
			local expected = { config.bed, config.rimWind }
			table.sort(expected)
			expect(stops).toEqual(expected)
		end)
		Ambience.bind(nil)
		SfxPool.reset()
		SfxPool.bind(nil)
		if not ok then
			error(err, 0)
		end
	end)
end)
