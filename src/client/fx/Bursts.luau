--!strict
--[[
	Bursts: the one-shot ParticleEmitter bursts (the parry's sparks, the shatter's white flash)
	across a render stall.

	The engine moves and draws particles only on rendered frames. RenderStepped stops while the
	display sleeps or the window is minimised and Heartbeat goes on (measured in Studio: 0/s and
	60/s), so a burst emitted then would wait and fly when rendering comes back, long after the
	hit or the death it belonged to. `emit` records when the burst's longest particle is gone by
	the clock (Engine.now); a Heartbeat watchdog clears the emitter then, so the frame that comes
	back shows nothing of it. While the display runs the clear removes nothing anyone sees: every
	particle has faded out by the end of its lifetime. Back-to-back bursts on one emitter clear at
	the latest one's end. The watchdog runs only while a burst is pending.

	Engine-only pieces (Heartbeat, Emit, Clear) sit behind `bind`, so specs drive them by hand.
]]

local Engine = require(script.Parent.Engine)

export type Deps = {
	now: () -> number,
	onHeartbeat: (fn: (dt: number) -> ()) -> () -> (), -- connects the watchdog; returns its disconnect
	emit: (emitter: ParticleEmitter, count: number) -> (),
	clear: (emitter: ParticleEmitter) -> (),
}

export type Overrides = {
	now: (() -> number)?,
	onHeartbeat: ((fn: (dt: number) -> ()) -> () -> ())?,
	emit: ((emitter: ParticleEmitter, count: number) -> ())?,
	clear: ((emitter: ParticleEmitter) -> ())?,
}

local Bursts = {}

-- Emit and Clear are engine-only; under Lune the calls fail quietly.
local function engineEmit(emitter: ParticleEmitter, count: number)
	pcall(function()
		emitter:Emit(count)
	end)
end

local function engineClear(emitter: ParticleEmitter)
	pcall(function()
		emitter:Clear()
	end)
end

local function defaults(overrides: Overrides?): Deps
	local deps: Deps = {
		now = Engine.now,
		onHeartbeat = Engine.onHeartbeat,
		emit = engineEmit,
		clear = engineClear,
	}
	if overrides ~= nil then
		deps.now = overrides.now or deps.now
		deps.onHeartbeat = overrides.onHeartbeat or deps.onHeartbeat
		deps.emit = overrides.emit or deps.emit
		deps.clear = overrides.clear or deps.clear
	end
	return deps
end

local deps: Deps = defaults(nil)
-- Each emitter with a burst still flying, and when the clock says its last particle is gone.
local pending: { [ParticleEmitter]: number } = {}
local stopWatch: (() -> ())? = nil

local function letGo()
	local stop = stopWatch
	stopWatch = nil
	if stop ~= nil then
		stop()
	end
end

-- The watchdog: clears every emitter whose bursts are over by the clock.
local function watch()
	local at = deps.now()
	local any = false
	for emitter, endsAt in pending do
		if at >= endsAt then
			pending[emitter] = nil
			deps.clear(emitter)
		else
			any = true
		end
	end
	if not any then
		letGo()
	end
end

--- Emits `count` particles from `emitter` now; the emitter is cleared on Heartbeat once `lifetime` (its longest particle's, seconds) has passed by the clock. Returns the count emitted.
function Bursts.emit(emitter: ParticleEmitter, count: number, lifetime: number): number
	if count <= 0 then
		return 0
	end
	deps.emit(emitter, count)
	local endsAt = deps.now() + math.max(lifetime, 0)
	local current = pending[emitter]
	pending[emitter] = if current ~= nil then math.max(current, endsAt) else endsAt
	if stopWatch == nil then
		stopWatch = deps.onHeartbeat(function()
			watch()
		end)
	end
	return count
end

--- Emitters with a burst still flying (specs).
function Bursts.pending(): number
	local count = 0
	for _ in pending do
		count += 1
	end
	return count
end

--- Runs the watchdog by hand (specs).
function Bursts.step()
	watch()
end

--- Forgets every pending burst and stops the watchdog (specs, a place change).
function Bursts.reset()
	table.clear(pending)
	letGo()
end

--- Replaces the clock, Heartbeat, Emit or Clear (specs); nil restores the engine. Forgets what was
--- pending (its times were on the old clock) and stops the watchdog.
function Bursts.bind(overrides: Overrides?)
	Bursts.reset()
	deps = defaults(overrides)
end

return Bursts
