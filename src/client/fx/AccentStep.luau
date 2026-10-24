--!strict
--[[
	AccentStep: the engine seam Glint, SlashArc and SpeedLines share. Each module reads time
	through `now` and runs its per-frame update through `onStep` (RenderStepped in the engine:
	the accents are screen-facing visuals and update once per rendered frame). Specs hand in a fake
	clock and a fake step through each module's `bind`, then drive frames by hand; under Lune the
	defaults are the package clock and a step that never fires.

	`onWatch` is the accents' watchdog (Heartbeat in the engine). RenderStepped stops while the
	display sleeps or the window is minimised and Heartbeat goes on (measured in Studio: 0/s and
	60/s), and a frame can be presented or captured after a stall before the first render step
	runs. So an accent never waits for a render step to end: while any shows, the watchdog ends
	each one at its own length (no pose is written there), and `connect` hands back one disconnect
	for both loops.
]]

local RunService = game:GetService("RunService")

local Engine = require(script.Parent.Engine)

export type StepFn = (dt: number) -> ()

export type Deps = {
	now: () -> number, -- monotonic seconds
	onStep: (fn: StepFn) -> () -> (), -- connects a per-frame callback; returns its disconnect
	onWatch: (fn: StepFn) -> () -> (), -- connects the watchdog (runs while nothing renders); returns its disconnect
	viewport: () -> Vector2?, -- the screen size in pixels, nil when unknown
}

export type Overrides = {
	now: (() -> number)?,
	onStep: ((fn: StepFn) -> () -> ())?,
	onWatch: ((fn: StepFn) -> () -> ())?,
	viewport: (() -> Vector2?)?,
}

local AccentStep = {}

--- Connects `fn(dt)` to RenderStepped when the engine runs; a no-op disconnect under Lune.
function AccentStep.renderStepped(fn: StepFn): () -> ()
	local ok, signal = pcall(function()
		return (RunService :: any).RenderStepped
	end)
	if not ok or typeof(signal) ~= "RBXScriptSignal" then
		return function() end
	end
	local connection = (signal :: RBXScriptSignal):Connect(fn)
	return function()
		connection:Disconnect()
	end
end

--- Connects `fn(dt)` to Heartbeat when the engine runs (it goes on while nothing renders); a no-op disconnect under Lune.
function AccentStep.heartbeat(fn: StepFn): () -> ()
	return Engine.onHeartbeat(fn)
end

--- Connects `render` to the deps' per-frame step and `watch` to their watchdog; returns one disconnect for both.
function AccentStep.connect(deps: Deps, render: StepFn, watch: StepFn): () -> ()
	local stopRender = deps.onStep(render)
	local stopWatch = deps.onWatch(watch)
	return function()
		stopRender()
		stopWatch()
	end
end

--- The current camera's ViewportSize in pixels, or nil (no camera, or Lune).
function AccentStep.viewport(): Vector2?
	local camera = Engine.camera()
	if camera == nil then
		return nil
	end
	local ok, size = pcall(function()
		return (camera :: any).ViewportSize
	end)
	if ok and typeof(size) == "Vector2" and size.X > 0 and size.Y > 0 then
		return size
	end
	return nil
end

--- The engine defaults with any overrides applied on top.
function AccentStep.deps(overrides: Overrides?): Deps
	local deps: Deps = {
		now = Engine.now,
		onStep = AccentStep.renderStepped,
		onWatch = AccentStep.heartbeat,
		viewport = AccentStep.viewport,
	}
	if overrides ~= nil then
		deps.now = overrides.now or deps.now
		deps.onStep = overrides.onStep or deps.onStep
		deps.onWatch = overrides.onWatch or deps.onWatch
		deps.viewport = overrides.viewport or deps.viewport
	end
	return deps
end

return AccentStep
