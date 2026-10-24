--!strict
--[[
	FrameClock: frame-counted callbacks for the two- and three-frame flashes (section 10 beat 4,
	section 11). "N frames" means N rendered frames, counted from the first frame that shows the
	change, so a flash reads the same at any frame rate the player actually gets.

	Which frame first shows a change depends on when in the frame it was made (issue 3). A frame's
	render steps (BindToRenderStep, First to Last priority) run before it draws, so a change made
	there (the local rig's contact, a near rig's clip event) shows on this frame; a change made
	after them (a remote event, Heartbeat, a task.delay resumption) shows on the next one. Counting
	Heartbeats instead cut a flash a remote event put up to one drawn frame: the restore ran at the
	second Heartbeat, before the second frame drew. So two render steps mark the frame: one at the
	First priority counts the frame and runs the callbacks due on it (before anything of it
	draws), one at the Last priority closes it. `after(n, fn)` runs `fn` at the start of the n-th
	frame after the first one that shows the change, so exactly n frames draw it.

	Render stalls (D-142, D-125): RenderStepped stops while the display sleeps and Heartbeat goes
	on, and a frame can be presented after a stall before the first render step runs. So a
	Heartbeat watchdog runs every pending callback once no render step has run for longer than
	choreo.luau stall.jumpSeconds: a flash put up before the display slept is gone before the
	frame that comes back.

	Under Lune (no render step) `after` falls back to the 60 fps frame length from combat.luau
	through task.delay, so the same code runs in tests; `bind` hands in a fake render step,
	Heartbeat and clock so specs count frames by hand. The two render steps bind when the module
	loads and stay bound, so the first flash already knows its frame; they do nothing but count
	while nothing is pending.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage.Shared

local Combat = require(Shared.data.combat)
local ChoreoData = require(Shared.data.choreo)
local ImpactData = require(Shared.data.impact)

export type Cancel = () -> ()

export type StepFn = (dt: number) -> ()

-- The engine seam. Each connector returns its disconnect, or nil when the engine has none.
export type Deps = {
	now: () -> number,
	onFrameStart: (fn: StepFn) -> (() -> ())?, -- the frame's first render step (priority First)
	onFrameEnd: (fn: StepFn) -> (() -> ())?, -- the frame's last render step (priority Last)
	onHeartbeat: (fn: StepFn) -> (() -> ())?, -- the stall watchdog (runs while nothing renders)
}

export type Overrides = {
	now: (() -> number)?,
	onFrameStart: ((fn: StepFn) -> (() -> ())?)?,
	onFrameEnd: ((fn: StepFn) -> (() -> ())?)?,
	onHeartbeat: ((fn: StepFn) -> (() -> ())?)?,
}

type Pending = { due: number, fn: () -> (), cancelled: boolean }

local FrameClock = {}

local START_NAME = "FrameClockFrameStart"
local END_NAME = "FrameClockFrameEnd"

local function engineNow(): number
	return os.clock()
end

-- BindToRenderStep at `priority` ("First" | "Last"); nil under Lune (no render step).
local function bindRenderStep(name: string, priority: string, fn: StepFn): (() -> ())?
	local ok = pcall(function()
		RunService:BindToRenderStep(name, (Enum.RenderPriority :: any)[priority].Value, fn)
	end)
	if not ok then
		return nil
	end
	return function()
		pcall(function()
			RunService:UnbindFromRenderStep(name)
		end)
	end
end

local function engineFrameStart(fn: StepFn): (() -> ())?
	return bindRenderStep(START_NAME, "First", fn)
end

local function engineFrameEnd(fn: StepFn): (() -> ())?
	return bindRenderStep(END_NAME, "Last", fn)
end

local function engineHeartbeat(fn: StepFn): (() -> ())?
	local ok, signal = pcall(function()
		return (RunService :: any).Heartbeat
	end)
	if not ok or typeof(signal) ~= "RBXScriptSignal" then
		return nil
	end
	local connection = (signal :: RBXScriptSignal):Connect(fn)
	return function()
		connection:Disconnect()
	end
end

local function defaults(overrides: Overrides?): Deps
	local deps: Deps = {
		now = engineNow,
		onFrameStart = engineFrameStart,
		onFrameEnd = engineFrameEnd,
		onHeartbeat = engineHeartbeat,
	}
	if overrides ~= nil then
		deps.now = overrides.now or deps.now
		deps.onFrameStart = overrides.onFrameStart or deps.onFrameStart
		deps.onFrameEnd = overrides.onFrameEnd or deps.onFrameEnd
		deps.onHeartbeat = overrides.onHeartbeat or deps.onHeartbeat
	end
	return deps
end

local deps: Deps = defaults(nil)
local pending: { Pending } = {}
-- Render steps begun so far, and whether this frame's render steps are running (a change made
-- now shows on frame `frame`; otherwise on the next one).
local frame = 0
local inRender = false
-- When the last render step began (deps.now); nil before the first.
local renderedAt: number? = nil
-- The last render-step frame lengths (impact.timing.paceSamples, newest last; hitches left out).
local paceSamples: { number } = {}
-- nil: not tried yet; true: the render steps are bound; false: the engine has none (Lune).
local bound: boolean? = nil
local unbinds: { () -> () } = {}

local function run(entry: Pending)
	local ok, err = pcall(entry.fn)
	if not ok then
		warn("[FrameClock] callback failed: " .. tostring(err))
	end
end

-- Runs the callbacks `ready` picks, oldest first; a callback may add new ones.
local function runWhere(ready: (entry: Pending) -> boolean)
	local due: { Pending } = {}
	for index = #pending, 1, -1 do
		local entry = pending[index]
		if entry.cancelled then
			table.remove(pending, index)
		elseif ready(entry) then
			table.remove(pending, index)
			table.insert(due, 1, entry)
		end
	end
	for _, entry in due do
		if not entry.cancelled then
			run(entry)
		end
	end
end

-- The first render step of a frame: counts it, then runs what is due on it before it draws.
local function frameStart(dt: number)
	frame += 1
	inRender = true
	renderedAt = deps.now()
	if dt > 0 and dt <= ImpactData.timing.maxPaceSeconds then
		table.insert(paceSamples, dt)
		if #paceSamples > ImpactData.timing.paceSamples then
			table.remove(paceSamples, 1)
		end
	end
	if #pending == 0 then
		return
	end
	local current = frame
	runWhere(function(entry: Pending): boolean
		return entry.due <= current
	end)
end

-- The last render step of a frame: anything changed from here on shows on the next one.
local function frameEnd(_dt: number)
	inRender = false
end

-- Heartbeat: once no frame has rendered for longer than a jump, every flash is long over (D-142).
local function watch(_dt: number)
	if #pending == 0 then
		return
	end
	local at = renderedAt
	if at == nil or deps.now() - at <= ChoreoData.stall.jumpSeconds then
		return
	end
	-- The frame that comes back is a new start: nothing the stall held carries a count into it.
	inRender = false
	runWhere(function(): boolean
		return true
	end)
end

local function unbindAll()
	for _, unbind in unbinds do
		unbind()
	end
	table.clear(unbinds)
	bound = nil
end

-- Binds the render steps and the watchdog the first time a callback needs them.
local function ensureBound(): boolean
	if bound ~= nil then
		return bound :: boolean
	end
	local stopStart = deps.onFrameStart(frameStart)
	if stopStart == nil then
		bound = false
		return false
	end
	table.insert(unbinds, stopStart)
	local stopEnd = deps.onFrameEnd(frameEnd)
	if stopEnd ~= nil then
		table.insert(unbinds, stopEnd)
	end
	local stopWatch = deps.onHeartbeat(watch)
	if stopWatch ~= nil then
		table.insert(unbinds, stopWatch)
	end
	bound = true
	return true
end

--- Runs `fn` once `frames` rendered frames (at least one) have shown what the caller changed just
--- now: at the start of the frame after them, before it draws. Returns a cancel function.
function FrameClock.after(frames: number, fn: () -> ()): Cancel
	local count = math.max(1, math.floor(frames + 0.5))
	if not ensureBound() then
		local thread = task.delay(count * Combat.hitStopFrameSeconds, fn)
		return function()
			pcall(task.cancel, thread)
		end
	end
	local shownFrom = if inRender then frame else frame + 1
	local entry: Pending = { due = shownFrom + count, fn = fn, cancelled = false }
	table.insert(pending, entry)
	return function()
		entry.cancelled = true
	end
end

--- The rendered frame a change made now first shows on (render steps counted since start).
function FrameClock.shownFrom(): number
	return if inRender then frame else frame + 1
end

--- Seconds a rendered frame takes on this screen: the median of the last few render-step frame
--- lengths (impact.timing; a hitch or a stall is left out), or nil before any frame rendered.
function FrameClock.pace(): number?
	local count = #paceSamples
	if count == 0 then
		return nil
	end
	local sorted = table.clone(paceSamples)
	table.sort(sorted)
	local middle = (count + 1) // 2
	if count % 2 == 1 then
		return sorted[middle]
	end
	return (sorted[middle] + sorted[middle + 1]) * 0.5
end

--- Seconds that `frames` frames take at the reference frame rate (for durations, never for flashes).
function FrameClock.seconds(frames: number): number
	return frames * Combat.hitStopFrameSeconds
end

--- Replaces the render steps, Heartbeat and the clock (specs); nil restores the engine. Pending
--- callbacks are dropped and the frame count starts over.
function FrameClock.bind(overrides: Overrides?)
	unbindAll()
	table.clear(pending)
	frame = 0
	inRender = false
	renderedAt = nil
	table.clear(paceSamples)
	deps = defaults(overrides)
	ensureBound()
end

-- Bound from the start: the first flash must already know which frame it shows on.
ensureBound()

return FrameClock
