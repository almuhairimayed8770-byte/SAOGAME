--!strict
--[[
	FrameOrder: the client's render steps, in one order on every machine (D-211).

	A frame's render steps run before it draws, by priority (BindToRenderStep, First to Last), and
	the engine pins no order between a plain RenderStepped connection and a bound step (D-201). So
	everything that reads a rig's pose on a frame is a bound step after the steps that pose it:

	  First            FrameClock: the frame starts (counted, its due callbacks run)
	  Camera - 1       SkyspireRigs: Choreo steps every full-rate rig, publishes its drawn body
	  Character + 1    the controller: the local rig (stepLocal), its root motion, the contact
	  Character + 2    SkyspireCamera: frames the local root and the drawn bodies as this frame draws them
	  Character + 3    the impact picture: copies the camera and the frozen bodies into its figures
	  Character + 4    SkyspirePoseReaders: Trails samples every blade tip where it is drawn
	  Last             SkyspireCameraLate (D-180) and FrameClock's end, tied (the engine pins no order)

	Distant and Far rigs step on Choreo's Heartbeat, after the draw, and are drawn as posed on the
	next frame, so a reader here sees them as drawn too. Each priority is a data row, an
	Enum.RenderPriority name and an offset from its value: choreo.luau renderOrder (rigs,
	character), camera.luau renderOrder (main, late), fx.luau renderOrder (impactFrames,
	poseReaders). Effects that read no pose (the glint, the slash line, the speed lines: driven by
	time and the camera's own projection) stay on RenderStepped.

	`join(name, row, fn)` runs `fn` in the named step every frame until the `leave` it returns is
	called. The step is bound once, at its first join or at `prepare`, and stays bound: an empty one
	costs one call a frame. A step bound inside a frame after its priority has passed waits for the
	next frame, and whether one bound inside a frame before its priority runs on that frame is the
	engine's choice, so a reader that will join at the contact (Character + 1) prepares its step at
	start (ImpactFrames) and then runs on the contact frame itself. Callbacks run in join order,
	each in its own pcall (one that throws is warned about, the rest run); one joined while the
	step runs runs in that same pass; one that leaves runs no more from that moment. Nothing is
	allocated per frame. Where there is no render step (Lune) `join` returns nil and `prepare`
	false. `bind` hands in a fake BindToRenderStep (specs).
]]

local RunService = game:GetService("RunService")

-- A place in the frame: an Enum.RenderPriority name and an offset from its value.
export type Row = { base: string, offset: number }

export type StepFn = (dt: number) -> ()

export type Leave = () -> ()

-- The engine seam: binds `fn` as the render step `name` at `priority`; false when there is none.
export type BindRenderStep = (name: string, priority: number, fn: StepFn) -> boolean

export type Overrides = {
	bindRenderStep: BindRenderStep?,
}

type Entry = { fn: StepFn, live: boolean }

type Step = {
	name: string,
	priority: number,
	entries: { Entry },
	running: boolean, -- its callbacks are running now
	dirty: boolean, -- an entry left while it ran: the list is compacted once the pass is over
}

local FrameOrder = {}

local function engineBind(name: string, priority: number, fn: StepFn): boolean
	local ok = pcall(function()
		RunService:BindToRenderStep(name, priority, fn)
	end)
	return ok
end

local bindRenderStep: BindRenderStep = engineBind
local steps: { [string]: Step } = {}

--- The step every reader of a drawn pose joins (fx.luau renderOrder.poseReaders): Trails' blade
--- samples.
FrameOrder.POSE_READERS = "SkyspirePoseReaders"

--- The render priority a row names: its Enum.RenderPriority value plus its offset.
function FrameOrder.priority(row: Row): number
	return (Enum.RenderPriority :: any)[row.base].Value + row.offset
end

-- Drops the entries that left, keeping the order of the rest (in place: nothing allocated).
local function compact(step: Step)
	local entries = step.entries
	local count = #entries
	local kept = 0
	for index = 1, count do
		local entry = entries[index]
		if entry.live then
			kept += 1
			entries[kept] = entry
		end
	end
	for index = count, kept + 1, -1 do
		entries[index] = nil
	end
	step.dirty = false
end

local function run(step: Step, dt: number)
	step.running = true
	local entries = step.entries
	-- `#entries` read every turn: a callback joined during the pass runs in it too.
	local index = 1
	while index <= #entries do
		local entry = entries[index]
		if entry.live then
			-- Typed to return a value so the failure's message has a slot (the step returns none).
			local ok, err = pcall(entry.fn :: (number) -> any, dt)
			if not ok then
				warn(("[FrameOrder] %s: a callback failed: %s"):format(step.name, tostring(err)))
			end
		end
		index += 1
	end
	step.running = false
	if step.dirty then
		compact(step)
	end
end

-- The named step, bound at the row's priority on first use; nil when there is no render step.
local function ensure(name: string, row: Row): Step?
	local existing = steps[name]
	if existing ~= nil then
		return existing
	end
	local step: Step = {
		name = name,
		priority = FrameOrder.priority(row),
		entries = {},
		running = false,
		dirty = false,
	}
	if not bindRenderStep(name, step.priority, function(dt: number)
		run(step, dt)
	end) then
		return nil
	end
	steps[name] = step
	return step
end

--- Binds the named step now, ahead of its first reader, so one that joins inside a frame runs on
--- that frame. False when there is no render step (Lune).
function FrameOrder.prepare(name: string, row: Row): boolean
	return ensure(name, row) ~= nil
end

--- Runs `fn` in the named render step (at the row's priority) every frame until the returned
--- `leave` is called; nil when there is no render step (Lune).
function FrameOrder.join(name: string, row: Row, fn: StepFn): Leave?
	local step = ensure(name, row)
	if step == nil then
		return nil
	end
	local entry: Entry = { fn = fn, live = true }
	table.insert(step.entries, entry)
	local joined = step
	return function()
		if not entry.live then
			return
		end
		entry.live = false
		joined.dirty = true
		if not joined.running then
			compact(joined)
		end
	end
end

--- Replaces BindToRenderStep (specs); nil restores the engine. Every step bound so far is
--- forgotten and its readers stop.
function FrameOrder.bind(overrides: Overrides?)
	for _, step in steps do
		for _, entry in step.entries do
			entry.live = false
		end
	end
	table.clear(steps)
	bindRenderStep = if overrides ~= nil and overrides.bindRenderStep ~= nil
		then overrides.bindRenderStep
		else engineBind
end

return FrameOrder
