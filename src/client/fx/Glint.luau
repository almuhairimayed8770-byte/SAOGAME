--!strict
--[[
	Glint: the reel's four-point star at the contact point, its edges split into color.

	A pooled BillboardGui (AlwaysOnTop, LightInfluence 0) on an anchored invisible part holds the
	star: a long cross and a shorter diagonal cross (thin Frames, each with a UIGradient that tapers
	its transparency from the middle to both tips) in a SystemWhite core, with two copies behind it
	in the split-edge tokens (TrailRose and SystemCyan) a pixel or two out, so the edges read as
	chromatic. It punches out to full size with an overshoot (accents.glint.punchEasing, never
	linear), turns a few degrees, and shrinks and fades. Sizes are accents.glint.sizes: Small
	(basic hits), Medium (crits, Art hits), Large (Art final hits, kills), Parry (the biggest and
	longest). An optional token tints the core toward that color.

	The BillboardGui is sized in studs, so a far glint is small, and its star is capped in pixels
	(UISizeConstraint, maxPixels times the current scale), so one by the camera never fills the
	view: never a full-screen flash. Quality: the tier's glintEdgeScale scales the split-edge offset
	and 0 skips the copies; at most the tier's `glints` play at once and past that the oldest is
	reused. Every instance is pooled; nothing is created after the pool is full. A frame that
	leaves the star's size where it was (the hold) writes no size, so it builds nothing.

	Render stalls: the pose runs on the render step, and a Heartbeat watchdog (AccentStep onWatch)
	ends each glint at its own length while no frame renders, so one asked for while the display
	sleeps is never left enabled for the frame that comes back.
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
	scale: number, -- of the size's full span
	rotation: number, -- degrees turned since the start
	transparency: number, -- 0 solid .. 1 gone (on top of each layer's own)
	done: boolean,
}

export type SlotView = {
	gui: BillboardGui,
	anchor: BasePart,
	star: Frame,
	core: Frame,
	edges: { Frame },
	size: string,
	active: boolean,
	started: number,
}

type Layer = {
	frame: Frame,
	arms: { Frame },
	base: number, -- the layer's transparency at full strength
}

type Slot = {
	anchor: BasePart,
	gui: BillboardGui,
	star: Frame,
	cap: UISizeConstraint,
	core: Layer,
	edges: { Layer },
	config: Accents.GlintSize,
	size: string,
	started: number,
	serial: number,
	rotation: number,
	active: boolean,
	lastTransparency: number,
	lastScale: number, -- the scale last sized; -1 before the first
}

local Glint = {}

local slots: { Slot } = {}
local deps: AccentStep.Deps = AccentStep.deps()
local stopLoop: (() -> ())? = nil
local serial = 0
local random = Random.new()
local folder: Instance? = nil
local taperSequence: NumberSequence? = nil
-- The pose the step loop works in, reused frame to frame.
local poseScratch: Pose = { scale = 1, rotation = 0, transparency = 0, done = false }

local function config(): typeof(Accents.glint)
	return Accents.glint
end

local function sizeOf(name: string): (string, Accents.GlintSize)
	local sizes = config().sizes
	local found = sizes[name]
	if found ~= nil then
		return name, found
	end
	local fallback = config().defaultSize
	return fallback, sizes[fallback]
end

local function sequence(keys: { { number } }): NumberSequence
	local points = {}
	for _, key in keys do
		table.insert(points, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	return NumberSequence.new(points)
end

local function taper(): NumberSequence
	if taperSequence == nil then
		taperSequence = sequence(config().taper)
	end
	return taperSequence :: NumberSequence
end

local function ensureFolder(): Instance
	if folder == nil then
		folder = Engine.folder(workspace, config().folderName)
	end
	return folder :: Instance
end

local function newLayer(parent: Frame, name: string, token: string, base: number, zIndex: number): Layer
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	local color = Palette.color3(token :: any)
	local arms: { Frame } = {}
	for _, arm in config().arms do
		local bar = Instance.new("Frame")
		bar.Name = "Arm"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(arm.length, 0)
		bar.Rotation = arm.rotation
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = 1
		bar.ZIndex = zIndex
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = taper()
		gradient.Parent = bar
		bar.Parent = frame
		table.insert(arms, bar)
	end
	frame.Parent = parent
	return { frame = frame, arms = arms, base = base }
end

local function newSlot(): Slot
	local glint = config()
	local anchor = Instance.new("Part")
	anchor.Name = "GlintAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * glint.anchorSize

	local gui = Instance.new("BillboardGui")
	gui.Name = "Glint"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = glint.maxDistance
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Adornee = anchor
	gui.Enabled = false

	local star = Instance.new("Frame")
	star.Name = "Star"
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.fromScale(0.5, 0.5)
	star.Size = UDim2.fromScale(1, 1)
	star.BackgroundTransparency = 1
	star.BorderSizePixel = 0
	local cap = Instance.new("UISizeConstraint")
	cap.Parent = star

	-- The split-edge copies go behind the core: lower ZIndex, built first.
	local edges: { Layer } = {}
	for index, token in glint.edgeTokens do
		table.insert(edges, newLayer(star, "Edge" .. token, token, glint.edgeTransparency, index))
	end
	local core = newLayer(star, "Core", glint.coreToken, 0, #glint.edgeTokens + 1)
	star.Parent = gui
	gui.Parent = anchor
	anchor.Parent = ensureFolder()

	local name, size = sizeOf(glint.defaultSize)
	return {
		anchor = anchor,
		gui = gui,
		star = star,
		cap = cap,
		core = core,
		edges = edges,
		config = size,
		size = name,
		started = 0,
		serial = 0,
		rotation = 0,
		active = false,
		lastTransparency = -1,
		lastScale = -1,
	}
end

-- A free slot while fewer than `cap` play; past the cap the oldest playing one is reused.
local function acquire(cap: number): Slot
	local active = 0
	local oldest: Slot? = nil
	local free: Slot? = nil
	for _, slot in slots do
		if slot.active then
			active += 1
			if oldest == nil or slot.serial < (oldest :: Slot).serial then
				oldest = slot
			end
		elseif free == nil then
			free = slot
		end
	end
	if active >= cap and oldest ~= nil then
		return oldest :: Slot
	end
	if free ~= nil then
		return free :: Slot
	end
	local slot = newSlot()
	table.insert(slots, slot)
	return slot
end

-- The pose `elapsed` seconds into a glint of `size`, written into `into`.
local function poseOf(size: Accents.GlintSize, elapsed: number, into: Pose): Pose
	local glint = config()
	local punch = Accents.seconds(size.punchFrames)
	local hold = Accents.seconds(size.holdFrames)
	local fade = Accents.seconds(size.fadeFrames)
	local total = Accents.seconds(size.punchFrames + size.holdFrames + size.fadeFrames)
	-- 1e-6: a clock summed frame by frame lands a hair short of the frame count it reached.
	if elapsed + 1e-6 >= total then
		into.scale, into.rotation, into.transparency, into.done = size.endScale, size.turnDegrees, 1, true
		return into
	end
	local scale = 1
	local transparency = 0
	if punch > 0 and elapsed < punch then
		local t = math.max(elapsed, 0) / punch
		scale = size.startScale + (1 - size.startScale) * Easing.evaluate(glint.punchEasing, t)
	elseif elapsed >= punch + hold then
		local eased = Easing.evaluate(glint.fadeEasing, (elapsed - punch - hold) / fade)
		scale = 1 + (size.endScale - 1) * eased
		transparency = eased
	end
	local turn = size.turnDegrees * Easing.evaluate(glint.turnEasing, math.clamp(elapsed / total, 0, 1))
	into.scale, into.rotation, into.transparency, into.done = scale, turn, transparency, false
	return into
end

local function setLayerTransparency(layer: Layer, transparency: number)
	local value = layer.base + (1 - layer.base) * transparency
	for _, arm in layer.arms do
		arm.BackgroundTransparency = value
	end
end

local function applyPose(slot: Slot, pose: Pose)
	if pose.scale ~= slot.lastScale then
		slot.lastScale = pose.scale
		local fraction = pose.scale / config().canvasScale
		slot.star.Size = UDim2.fromScale(fraction, fraction)
		local pixels = slot.config.maxPixels * pose.scale
		slot.cap.MaxSize = Vector2.new(pixels, pixels)
	end
	slot.star.Rotation = slot.rotation + pose.rotation
	if pose.transparency ~= slot.lastTransparency then
		slot.lastTransparency = pose.transparency
		setLayerTransparency(slot.core, pose.transparency)
		for _, edge in slot.edges do
			setLayerTransparency(edge, pose.transparency)
		end
	end
end

local function hide(slot: Slot)
	slot.active = false
	slot.gui.Enabled = false
	slot.lastTransparency = -1
	setLayerTransparency(slot.core, 1)
	for _, edge in slot.edges do
		setLayerTransparency(edge, 1)
	end
end

-- `rendering`: the render step poses every glint; the watchdog (no frame drawn) only ends those
-- past their length.
local function step(rendering: boolean)
	local now = deps.now()
	local any = false
	for _, slot in slots do
		if not slot.active then
			continue
		end
		local pose = poseOf(slot.config, now - slot.started, poseScratch)
		if pose.done then
			hide(slot)
			continue
		end
		any = true
		if rendering then
			applyPose(slot, pose)
		end
	end
	if not any and stopLoop ~= nil then
		local stop = stopLoop :: () -> ()
		stopLoop = nil
		stop()
	end
end

local function ensureLoop()
	if stopLoop == nil then
		stopLoop = AccentStep.connect(deps, function()
			step(true)
		end, function()
			step(false)
		end)
	end
end

-- Lays the split-edge copies out for the tier: offset times the tier's scale, hidden at 0.
local function layEdges(slot: Slot, edgeScale: number)
	local glint = config()
	local show = edgeScale > 0
	local offset = if show then math.max(1, math.floor(slot.config.edgeOffsetPixels * edgeScale + 0.5)) else 0
	for index, edge in slot.edges do
		edge.frame.Visible = show
		local direction = glint.edgeDirections[index] or glint.edgeDirections[1]
		-- UDim offsets are whole pixels.
		local x = math.floor(direction[1] * offset + 0.5)
		local y = math.floor(direction[2] * offset + 0.5)
		edge.frame.Position = UDim2.new(0.5, x, 0.5, y)
	end
end

local function layArms(slot: Slot, coreColor: Color3)
	local thickness = slot.config.thickness
	local arms = config().arms
	local layers = { slot.core }
	for _, edge in slot.edges do
		table.insert(layers, edge)
	end
	for _, layer in layers do
		for index, bar in layer.arms do
			bar.Size = UDim2.new(arms[index].length, 0, thickness.scale, thickness.pixels)
		end
	end
	for _, bar in slot.core.arms do
		bar.BackgroundColor3 = coreColor
	end
end

--- The glint's look `elapsed` seconds after it starts at a size (pure; the specs and the director read it).
function Glint.pose(size: string, elapsed: number): Pose
	local _, found = sizeOf(size)
	return poseOf(found, elapsed, { scale = 1, rotation = 0, transparency = 0, done = false })
end

--- Seconds a glint of `size` lasts, punch to gone.
function Glint.seconds(size: string): number
	local _, found = sizeOf(size)
	return Accents.seconds(found.punchFrames + found.holdFrames + found.fadeFrames)
end

--- The core color for an optional tint token: SystemWhite pulled toward the token by tintBlend.
function Glint.coreColor(token: string?): Color3
	local glint = config()
	local white = Palette.color3(glint.coreToken :: any)
	if token == nil or Palette.tokens[token :: any] == nil then
		return white
	end
	return white:Lerp(Palette.color3(token :: any), glint.tintBlend)
end

--- Plays a four-point star at a world point; `size` is a key of accents.glint.sizes, `token` tints the core.
function Glint.play(position: Vector3, size: string, token: string?)
	local name, found = sizeOf(size)
	local tier = Accents.tier(Quality.get())
	local slot = acquire(math.max(1, tier.glints))
	serial += 1
	slot.serial = serial
	slot.size = name
	slot.config = found
	slot.started = deps.now()
	slot.rotation = random:NextNumber(-1, 1) * config().jitterDegrees
	slot.active = true
	slot.lastTransparency = -1
	slot.lastScale = -1
	slot.anchor.CFrame = CFrame.new(position)
	local span = found.studs * config().canvasScale
	slot.gui.Size = UDim2.fromScale(span, span)
	layEdges(slot, tier.glintEdgeScale)
	layArms(slot, Glint.coreColor(token))
	applyPose(slot, poseOf(found, 0, poseScratch))
	slot.gui.Enabled = true
	ensureLoop()
end

--- Glints showing right now.
function Glint.activeCount(): number
	local count = 0
	for _, slot in slots do
		if slot.active then
			count += 1
		end
	end
	return count
end

--- A read-only view of every pooled glint, in pool order (specs).
function Glint.slots(): { SlotView }
	local views: { SlotView } = {}
	for _, slot in slots do
		local edges: { Frame } = {}
		for _, edge in slot.edges do
			table.insert(edges, edge.frame)
		end
		table.insert(views, {
			gui = slot.gui,
			anchor = slot.anchor,
			star = slot.star,
			core = slot.core.frame,
			edges = edges,
			size = slot.size,
			active = slot.active,
			started = slot.started,
		})
	end
	return views
end

--- Advances every glint to the clock's now (the step loop calls it; specs may too).
function Glint.step()
	step(true)
end

--- Replaces the clock, the frame step or the viewport (specs); stops the running loop.
function Glint.bind(overrides: AccentStep.Overrides?)
	if stopLoop ~= nil then
		local stop = stopLoop :: () -> ()
		stopLoop = nil
		stop()
	end
	deps = AccentStep.deps(overrides)
end

--- Hides every glint and stops the loop; the pool stays (specs, a place change).
function Glint.reset()
	for _, slot in slots do
		hide(slot)
	end
	if stopLoop ~= nil then
		local stop = stopLoop :: () -> ()
		stopLoop = nil
		stop()
	end
end

--- Pre-builds the pool to the largest tier's cap so the first hit never allocates.
function Glint.start()
	local most = 0
	for _, tier in Accents.quality do
		most = math.max(most, tier.glints)
	end
	while #slots < most do
		table.insert(slots, newSlot())
	end
end

return Glint
