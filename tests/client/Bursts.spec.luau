--!strict
-- One-shot ParticleEmitter bursts (the parry sparks, the shatter's white flash) across a render
-- stall. The engine draws particles only on rendered frames, so a burst emitted while the display
-- sleeps (RenderStepped 0/s, Heartbeat 60/s, measured in Studio) would wait and fly when rendering
-- comes back. Bursts clears the emitter on Heartbeat once the burst's longest particle is gone by
-- the clock. Emit and Clear are engine-only, so a fake seam records them.
local Bursts = Harness.load("src/client/fx/Bursts")
local accents = Harness.load("src/shared/data/accents")

local F = accents.frameSeconds

type Log = { kind: string, emitter: any, count: number?, at: number }

local clock = 0
local watchFn: ((number) -> ())? = nil
local watchConnects = 0
local log: { Log } = {}

local function fresh()
	Bursts.bind({
		now = function(): number
			return clock
		end,
		onHeartbeat = function(fn: (number) -> ()): () -> ()
			watchConnects += 1
			watchFn = fn
			return function()
				if watchFn == fn then
					watchFn = nil
				end
			end
		end,
		emit = function(emitter: any, count: number)
			table.insert(log, { kind = "emit", emitter = emitter, count = count, at = clock })
		end,
		clear = function(emitter: any)
			table.insert(log, { kind = "clear", emitter = emitter, at = clock })
		end,
	})
	Bursts.reset()
	clock = 0
	watchFn = nil
	watchConnects = 0
	table.clear(log)
end

-- `count` engine frames with nothing rendered: the clock, then Heartbeat.
local function beats(count: number)
	for _ = 1, count do
		clock += F
		local fn = watchFn
		if fn ~= nil then
			fn(F)
		end
	end
end

local function clears(emitter: any): { Log }
	local found = {}
	for _, entry in log do
		if entry.kind == "clear" and entry.emitter == emitter then
			table.insert(found, entry)
		end
	end
	return found
end

describe("Bursts", function()
	it("emits through the seam and clears the emitter on Heartbeat once its longest particle is gone", function()
		fresh()
		local emitter = { name = "sparks" }
		local lifetime = 0.3
		expect(Bursts.emit(emitter :: any, 12, lifetime)).toBe(12)
		expect(log[1].kind).toBe("emit")
		expect(log[1].count).toBe(12)
		expect(Bursts.pending()).toBe(1)
		expect(watchConnects).toBe(1)
		while Bursts.pending() > 0 and clock < 5 do
			beats(1)
			if Bursts.pending() > 0 then
				expect(#clears(emitter)).toBe(0)
			end
		end
		local cleared = clears(emitter)
		expect(#cleared).toBe(1)
		expect(cleared[1].at).toBeGreaterThanOrEqual(lifetime - 1e-9)
		expect(cleared[1].at).toBeLessThanOrEqual(lifetime + F + 1e-9)
		-- Nothing pending: the watchdog let go.
		expect(watchFn).toBeNil()
	end)

	it("a second burst on the same emitter moves its clear to the later end; emitters clear apart", function()
		fresh()
		local sparks = { name = "sparks" }
		local flash = { name = "flash" }
		Bursts.emit(sparks :: any, 10, 0.3)
		beats(6) -- 0.1 s
		Bursts.emit(sparks :: any, 10, 0.3) -- ends at 0.4
		Bursts.emit(flash :: any, 28, 0.2) -- ends at 0.3
		expect(watchConnects).toBe(1)
		beats(15) -- 0.35 s
		expect(#clears(flash)).toBe(1)
		expect(#clears(sparks)).toBe(0)
		beats(4) -- 0.416 s
		expect(#clears(sparks)).toBe(1)
		expect(clears(sparks)[1].at).toBeGreaterThanOrEqual(0.4 - 1e-9)
		expect(Bursts.pending()).toBe(0)
		expect(watchFn).toBeNil()
	end)

	it("emits nothing and starts no watch for an empty burst", function()
		fresh()
		expect(Bursts.emit({} :: any, 0, 0.3)).toBe(0)
		expect(#log).toBe(0)
		expect(Bursts.pending()).toBe(0)
		expect(watchConnects).toBe(0)
	end)

	it("a rebind forgets bursts timed on the old clock", function()
		fresh()
		local emitter = { name = "sparks" }
		clock = 1000
		Bursts.emit(emitter :: any, 5, 0.3)
		fresh() -- a new clock at 0
		Bursts.emit(emitter :: any, 5, 0.3)
		beats(19)
		expect(#clears(emitter)).toBe(1)
		expect(Bursts.pending()).toBe(0)
	end)

	-- The display asleep for 54 s: bursts every second (a parry storm, a herd's deaths). None is
	-- left for the frame that comes back.
	it("leaves nothing of a stall's bursts for the frame that comes back", function()
		fresh()
		local emitter = { name = "flash" }
		for _ = 1, 54 do
			Bursts.emit(emitter :: any, 28, 0.28)
			beats(60)
			expect(Bursts.pending()).toBe(0)
		end
		expect(#clears(emitter)).toBe(54)
		expect(watchFn).toBeNil()
	end)
end)
