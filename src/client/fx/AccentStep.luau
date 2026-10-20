--!strict
--[[
	AccentStep: the engine seam Glint, SlashArc and SpeedLines share. Each module reads time
	through `now` and runs its per-frame update through `onStep` (RenderStepped in the engine:
	the accents are screen-facing visuals and update once per rendered frame). Specs hand in a fake
	clock and a fake step through each module's `bind`, then drive frames by hand; under Lune the
	defaults are the package clock and a step that never fires.
]]

local RunService = game:GetService("RunService")

local Engine = require(script.Parent.Engine)

export type StepFn = (dt: number) -> ()

export type Deps = {
	now: () -> number, -- monotonic seconds
	onStep: (fn: StepFn) -> () -> (), -- connects a per-frame callback; returns its disconnect
	viewport: () -> Vector2?, -- the screen size in pixels, nil when unknown
}

export type Overrides = {
	now: (() -> number)?,
	onStep: ((fn: StepFn) -> () -> ())?,
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
		viewport = AccentStep.viewport,
	}
	if overrides ~= nil then
		deps.now = overrides.now or deps.now
		deps.onStep = overrides.onStep or deps.onStep
		deps.viewport = overrides.viewport or deps.viewport
	end
	return deps
end

return AccentStep
