--!strict
--[[
	SpeedLines: screen-edge speed lines on the local screen for a dodge or a dash.

	One ScreenGui (under the HUD) holds a pool of thin Frames on rays from the screen center.
	Each line runs from just outside the middle third of the screen (accents.speedLines
	clearFraction: the fighter in the middle stays readable) to past the screen edge, its inner
	end faded by a UIGradient. The ray layout is worked out in pixels from the viewport at each
	play, so the middle third holds at any aspect ratio. On play the inner ends rush in from the
	edges (inEasing), hold, then pull back out to the edges as the lines fade (outEasing), all
	inside the kind's seconds (a Dodge is the dodge's 0.25 s). Each line is a white core inside a
	thin ink edge (accents.speedLines.edge, a UIStroke with its own copy of the inner-end fade), so
	it reads on a bright sky as well as a dark floor. The count is the kind's count times
	the quality tier's speedLineScale. The lines are thin and change no screen-wide brightness, so
	they are never a flash and never ask the flash budget. A line whose whole pixels did not move
	since the last frame is not written again, so the hold builds nothing. A Heartbeat watchdog
	(AccentStep onWatch) hides them at the kind's length while no frame renders.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Accents = require(Shared.data.accents)
local Palette = require(Shared.data.palette)
local Easing = require(Shared.util.Easing)
local Engine = require(script.Parent.Engine)
local Quality = require(script.Parent.Quality)
local AccentStep = require(script.Parent.AccentStep)

export type Pose = {
	reachIn: number, -- 0 at the start reach .. 1 at each line's own reach
	reachOut: number, -- 0 at the line's reach .. 1 pulled back to the screen edge
	fade: number, -- 0 at full strength .. 1 gone
	done: boolean,
}

export type LineView = {
	frame: Frame,
	angle: number, -- degrees, clockwise from screen right (y down)
	reach: number, -- the inner end's reach while held
}

export type View = {
	gui: ScreenGui,
	lines: { LineView }, -- the lines this play shows
	kind: string,
	active: boolean,
	viewport: Vector2,
}

type Line = {
	frame: Frame,
	edge: UIStroke,
	angle: number,
	reach: number,
	-- The whole pixels last laid (x, y off the center, length); math.huge before the first.
	laidX: number,
	laidY: number,
	laidLength: number,
}

local SpeedLines = {}

local deps: AccentStep.Deps = AccentStep.deps()
local stopLoop: (() -> ())? = nil
local random = Random.new()
local gui: ScreenGui? = nil
local pool: { Line } = {}
local shown = 0
local kindName = Accents.speedLines.defaultKind
local started = 0
local active = false
local viewport = Vector2.new(Accents.speedLines.referenceScreen.width, Accents.speedLines.referenceScreen.height)
local laidTransparency = -1 -- the transparency last written to the shown lines
-- The pose the step loop works in, reused frame to frame.
local poseScratch: Pose = { reachIn = 0, reachOut = 0, fade = 1, done = false }

local function kindOf(name: string): (string, Accents.SpeedLineKind)
	local config = Accents.speedLines
	local found = config.kinds[name]
	if found ~= nil then
		return name, found
	end
	return config.defaultKind, config.kinds[config.defaultKind]
end

-- The most lines any kind shows at any tier: the pool's size.
local function poolSize(): number
	local most = 0
	for _, kind in Accents.speedLines.kinds do
		for _, tier in Accents.quality do
			most = math.max(most, math.floor(kind.count * tier.speedLineScale + 0.5))
		end
	end
	return most
end

local function gradient(): NumberSequence
	local points = {}
	for _, key in Accents.speedLines.gradient do
		table.insert(points, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	return NumberSequence.new(points)
end

local function ensureGui(): ScreenGui
	local config = Accents.speedLines
	if gui == nil then
		local screen = Instance.new("ScreenGui")
		screen.Name = config.screenGuiName
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.DisplayOrder = config.displayOrder
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screen.Enabled = false
		local container = Instance.new("Frame")
		container.Name = "Lines"
		container.Size = UDim2.fromScale(1, 1)
		container.BackgroundTransparency = 1
		container.BorderSizePixel = 0
		container.Parent = screen
		local fade = gradient()
		local color = Palette.color3(config.token :: any)
		local ink = Palette.color3(config.edge.token :: any)
		for _ = 1, poolSize() do
			local frame = Instance.new("Frame")
			frame.Name = "Line"
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.BorderSizePixel = 0
			frame.BackgroundColor3 = color
			frame.BackgroundTransparency = 1
			frame.Visible = false
			local ramp = Instance.new("UIGradient")
			ramp.Transparency = fade
			ramp.Parent = frame
			-- The ink edge round the core; a stroke takes its own gradient, not the frame's.
			local edge = Instance.new("UIStroke")
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.Color = ink
			edge.Thickness = config.edge.pixels
			edge.Transparency = 1
			local edgeRamp = Instance.new("UIGradient")
			edgeRamp.Transparency = fade
			edgeRamp.Parent = edge
			edge.Parent = frame
			frame.Parent = container
			table.insert(pool, {
				frame = frame,
				edge = edge,
				angle = 0,
				reach = 0,
				laidX = math.huge,
				laidY = math.huge,
				laidLength = math.huge,
			})
		end
		gui = screen
	end
	local screen = gui :: ScreenGui
	if screen.Parent == nil then
		local parent = Engine.playerGui()
		if parent ~= nil then
			pcall(function()
				screen.Parent = parent
			end)
		end
	end
	return screen
end

-- Pixels from the screen center to the edge of a centered half-width x half-height box along a ray.
local function toBox(dx: number, dy: number, halfWidth: number, halfHeight: number): number
	local alongX = if math.abs(dx) > 1e-6 then halfWidth / math.abs(dx) else math.huge
	local alongY = if math.abs(dy) > 1e-6 then halfHeight / math.abs(dy) else math.huge
	return math.min(alongX, alongY)
end

--- The pixel span (inner, outer) from the screen center of a line on a ray at `angle` degrees
--- whose inner end is `reach` of the way from the middle third's edge to the screen edge (pure).
function SpeedLines.span(angle: number, reach: number, screen: Vector2, overshoot: number): (number, number)
	local radians = math.rad(angle)
	local dx, dy = math.cos(radians), math.sin(radians)
	local clear = Accents.speedLines.clearFraction * 0.5
	local inside = toBox(dx, dy, screen.X * clear, screen.Y * clear)
	local edge = toBox(dx, dy, screen.X * 0.5, screen.Y * 0.5)
	return inside + (edge - inside) * reach, edge * overshoot
end

-- SpeedLines.pose written into `into` (the step loop reuses one table).
local function poseInto(kind: string, elapsed: number, into: Pose): Pose
	local config = Accents.speedLines
	local _, found = kindOf(kind)
	local total = found.seconds
	-- 1e-6: a clock summed frame by frame lands a hair short of the frame count it reached.
	if elapsed + 1e-6 >= total then
		into.reachIn, into.reachOut, into.fade, into.done = 1, 1, 1, true
		return into
	end
	local rushIn = Accents.seconds(found.inFrames)
	local pullOut = Accents.seconds(found.outFrames)
	local outStart = total - pullOut
	if rushIn > 0 and elapsed < rushIn then
		local eased = Easing.evaluate(config.inEasing, math.max(elapsed, 0) / rushIn)
		into.reachIn, into.reachOut, into.fade, into.done = eased, 0, 1 - eased, false
		return into
	end
	if elapsed >= outStart and pullOut > 0 then
		local eased = Easing.evaluate(config.outEasing, (elapsed - outStart) / pullOut)
		into.reachIn, into.reachOut, into.fade, into.done = 1, eased, eased, false
		return into
	end
	into.reachIn, into.reachOut, into.fade, into.done = 1, 0, 0, false
	return into
end

--- The look `elapsed` seconds into a play of `kind` (pure).
function SpeedLines.pose(kind: string, elapsed: number): Pose
	return poseInto(kind, elapsed, { reachIn = 0, reachOut = 0, fade = 1, done = false })
end

--- Seconds a play of `kind` lasts.
function SpeedLines.seconds(kind: string): number
	local _, found = kindOf(kind)
	return found.seconds
end

--- Lines a play of `kind` shows at a quality tier.
function SpeedLines.count(kind: string, tier: string): number
	local _, found = kindOf(kind)
	return math.max(0, math.floor(found.count * Accents.tier(tier).speedLineScale + 0.5))
end

-- Lays the shown lines for a pose. UDim offsets are whole pixels, so a line whose rounded place
-- and length did not move is not written (no UDim2 built), nor is an unchanged transparency.
local function lay(pose: Pose)
	local _, config = kindOf(kindName)
	local edge = Accents.speedLines.edge
	local transparency = config.transparency + (1 - config.transparency) * pose.fade
	local fadeChanged = transparency ~= laidTransparency
	laidTransparency = transparency
	local edgeTransparency = edge.transparency + (1 - edge.transparency) * pose.fade
	-- The core is the line's whole width less the edge drawn outside it on both sides.
	local core = math.max(config.thicknessPixels - 2 * edge.pixels, 1)
	for index = 1, shown do
		local line = pool[index]
		local reach = config.startReach + (line.reach - config.startReach) * pose.reachIn
		reach += (1 - reach) * pose.reachOut
		local inner, outer = SpeedLines.span(line.angle, reach, viewport, config.overshoot)
		local radians = math.rad(line.angle)
		local middle = (inner + outer) * 0.5
		local frame = line.frame
		local x = math.floor(math.cos(radians) * middle + 0.5)
		local y = math.floor(math.sin(radians) * middle + 0.5)
		if x ~= line.laidX or y ~= line.laidY then
			line.laidX, line.laidY = x, y
			frame.Position = UDim2.new(0.5, x, 0.5, y)
		end
		local length = math.floor(math.max(outer - inner, 0) + 0.5)
		if length ~= line.laidLength then
			line.laidLength = length
			frame.Size = UDim2.fromOffset(length, core)
		end
		if fadeChanged then
			frame.BackgroundTransparency = transparency
			line.edge.Transparency = edgeTransparency
		end
	end
end

local function stop()
	active = false
	for _, line in pool do
		line.frame.Visible = false
	end
	shown = 0
	if gui ~= nil then
		(gui :: ScreenGui).Enabled = false
	end
	if stopLoop ~= nil then
		local disconnect = stopLoop :: () -> ()
		stopLoop = nil
		disconnect()
	end
end

-- `rendering`: the render step lays the lines; the watchdog (no frame drawn) only hides them once
-- the kind's length is over.
local function step(rendering: boolean)
	if not active then
		stop()
		return
	end
	local pose = poseInto(kindName, deps.now() - started, poseScratch)
	if pose.done then
		stop()
		return
	end
	if rendering then
		lay(pose)
	end
end

--- Plays screen-edge speed lines on the local screen; `kind` is a key of accents.speedLines.kinds.
function SpeedLines.play(kind: string)
	local name, config = kindOf(kind)
	local screen = ensureGui()
	local count = math.min(SpeedLines.count(name, Quality.get()), #pool)
	if count <= 0 then
		return
	end
	local size = deps.viewport()
	viewport = size or Vector2.new(Accents.speedLines.referenceScreen.width, Accents.speedLines.referenceScreen.height)
	kindName = name
	shown = count
	started = deps.now()
	active = true
	local spacing = 360 / count
	for index, line in pool do
		if index > count then
			line.frame.Visible = false
			continue
		end
		line.angle = spacing * (index - 1) + random:NextNumber(-1, 1) * config.angleJitter * spacing
		line.reach = random:NextNumber(config.innerReach.min, config.innerReach.max)
		line.laidX, line.laidY, line.laidLength = math.huge, math.huge, math.huge
		line.frame.Rotation = line.angle
		line.frame.Visible = true
	end
	laidTransparency = -1
	lay(poseInto(name, 0, poseScratch))
	screen.Enabled = true
	if stopLoop == nil then
		stopLoop = AccentStep.connect(deps, function()
			step(true)
		end, function()
			step(false)
		end)
	end
end

--- True while lines are on screen.
function SpeedLines.isShowing(): boolean
	return active
end

--- The ScreenGui and the lines the current (or last) play shows (specs).
function SpeedLines.view(): View
	local screen = ensureGui()
	local lines: { LineView } = {}
	for index = 1, shown do
		local line = pool[index]
		table.insert(lines, { frame = line.frame, angle = line.angle, reach = line.reach })
	end
	return { gui = screen, lines = lines, kind = kindName, active = active, viewport = viewport }
end

--- Advances the lines to the clock's now (the step loop calls it; specs may too).
function SpeedLines.step()
	step(true)
end

--- Replaces the clock, the frame step or the viewport (specs); stops the running loop.
function SpeedLines.bind(overrides: AccentStep.Overrides?)
	if stopLoop ~= nil then
		local disconnect = stopLoop :: () -> ()
		stopLoop = nil
		disconnect()
	end
	deps = AccentStep.deps(overrides)
end

--- Hides the lines and stops the loop (specs, a respawn).
function SpeedLines.reset()
	stop()
end

--- Builds the ScreenGui and its pool so the first dodge never allocates.
function SpeedLines.start()
	ensureGui()
end

return SpeedLines
