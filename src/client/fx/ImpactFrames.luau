--!strict
--[[
	ImpactFrames (the reel style on top of section 10 beat 4): on the biggest hits the picture
	turns for a few frames into flat silhouettes of the fighters on a solid field (white figures on
	black, ink on white, ink brush strokes along the slash, the parry's inverted frame).

	Built from engine pieces that need no shaders. One pooled ScreenGui under the local PlayerGui
	(IgnoreGuiInset, ResetOnSpawn off, disabled while idle, impact.overlay.displayOrder above the
	HUD) holds, back to front:
	  - Background: a full-screen Frame in the look's background token.
	  - Figures: a full-screen ViewportFrame with its own Camera, copied from the CurrentCamera
	    (CFrame and FieldOfView) every frame the overlay shows. Each rig's visible BaseParts
	    (MeshParts and accessory Handles and the sword too; not the root, the sheath or FX parts,
	    as impact.silhouette.excludeNames says, nor layered clothing) are cloned once per play, or
	    taken back from the pool, and stripped to their bare mesh: no texture, decal,
	    SurfaceAppearance, Highlight, script, sound, joint or attachment, SmoothPlastic, flat white.
	    The viewport's white Ambient and black LightColor render every clone flat, and ImageColor3
	    tints the whole picture to the look's figure token. Each clone copies its source part's
	    CFrame every overlay frame; the rigs are frozen by hit-stop, so the silhouettes hold the
	    pose. Each clone takes its source's rest size: the sword's smear stretch (Smear.restSize)
	    can still be on in a hit-stop that froze the snap, and the figure draws the blade at rest.
	    Every quality tier draws them; lower tiers draw fewer parts per rig (impact.quality).
	  - Strokes: a layer of OutlineInk Frames (UICorner round ends, UIGradient transparency
	    taper) rotated to the slash angle across the hit; no image assets.

	Timing: the sequence's clock starts on the first frame drawn after `play` (a HitConfirmed
	lands between frames), and every look gets at least one drawn frame: a look ends on the first
	drawn frame at or past its finish (to the nearest frame), so a slow device shows each look
	once instead of skipping the parry's single frame. Nothing shows past the hit-stop the
	sequence rides on (ImpactSequence.capSeconds). At the end everything hides, the render step
	unbinds and the clones go back to the pool (the oldest past impact.silhouette.poolCap are
	destroyed).

	Hits that land together (one sweep through several targets confirms them all in one frame):
	a play while a sequence shows never cuts it for a dim and is never charged again. A sequence
	of the same or a lower rank joins the one showing (its rigs are drawn too); a higher rank
	takes over when the budget allows what the whole path really shows (every look drawn under
	the claim, through earlier takeovers too), else it joins.

	Flash safety: `play` asks FlashBudget itself with the sequence's flash cost and holds that
	claim until the overlay's last change. When the budget says no, or the Reduce flashing setting
	is on, it shows impact.reduced instead: a soft OutlineInk dim eased in and out, charged
	impact.reduced.flashCost (on a bright scene its dip is a flash too); nothing shows when that
	is refused as well. A dim asked for while a dim rises or holds keeps it at the peak, uncharged;
	one asked for while it fades is a new flash and is charged. With the setting on, at most
	impact.reduced.maxPerWindow dims start in any flash window, so Reduce flashing really flashes
	less than the budget allows.

	Engine-only pieces (the render step, PlayerGui, the camera, projection) sit behind `bind`, so
	specs drive the clock and the render step by hand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage.Shared

local Impact = require(Shared.data.impact)
local Palette = require(Shared.data.palette)
local Engine = require(script.Parent.Engine)
local Quality = require(script.Parent.Quality)
local FlashBudget = require(script.Parent.FlashBudget)
local ImpactSequence = require(script.Parent.ImpactSequence)
local Smear = require(script.Parent.Smear)

export type Options = {
	slashDirection: Vector2?, -- screen space, x right and y down; nil uses impact.strokes.defaultAngle
	now: number?, -- the flash budget's clock (Engine.now() when nil); the picture runs on its own clock
	position: Vector3?, -- the hit point the strokes cross; the rigs' centre when nil
}

-- The engine surface; `bind` replaces any of these (specs).
export type Deps = {
	now: (() -> number)?,
	onRender: ((step: (dt: number) -> ()) -> (() -> ())?)?, -- binds a per-frame step; returns its unbind
	playerGui: (() -> Instance?)?,
	camera: (() -> Camera?)?,
	project: ((position: Vector3) -> Vector2?)?, -- world point -> screen fractions (0..1), nil off screen
	aspect: (() -> number)?, -- screen width / height
	quality: (() -> string)?,
	random: Random?,
}

type CloneEntry = { source: BasePart, clone: BasePart }

type Showing = {
	kind: "Sequence" | "Dim",
	name: string,
	rank: number, -- a sequence's rank (impact.sequences); 0 for the dim
	startedAt: number?, -- a sequence's first drawn frame (nil until then); when a dim began
	frames: { ImpactSequence.Frame },
	index: number, -- the look on screen
	seconds: number, -- the sequence's length
	cap: number, -- a sequence never shows longer than this after its first drawn frame
	from: number, -- the dim's starting opacity
	hold: number, -- seconds the dim's peak holds (a dim that merges into it extends this)
	look: string?,
	unbind: (() -> ())?,
	claim: FlashBudget.Claim?, -- the flash budget's record of what this picture costs
	shownBefore: { string }, -- looks the sequences this one took over drew under the same claim
	rigs: { Model }, -- the rigs drawn as silhouettes
	wantsFigures: boolean, -- a look of the sequence draws figures
}

local ImpactFrames = {}

local overrides: Deps = {}
local random = Random.new()

local gui: ScreenGui? = nil
local background: Frame? = nil
local viewport: ViewportFrame? = nil
local overlayCamera: Camera? = nil
local strokeLayer: Frame? = nil
local strokes: { Frame } = {}
local rigFolders: { Model } = {}

local active: { CloneEntry } = {}
local pooled: { [BasePart]: BasePart } = {}
local pooledOrder: { BasePart } = {}

local showing: Showing? = nil
local reducedDims: { FlashBudget.Claim } = {} -- the dims Reduce flashing let start, newest last
local finish: () -> () -- ends what is showing; defined with the show / hide helpers below
local figuresOn = true
local strokesOn = true
local partsPerRig = 0
local started = false

local excludeSet: { [string]: boolean } = {}
for _, name in Impact.silhouette.excludeNames do
	excludeSet[name] = true
end

-- ---------------------------------------------------------------------------------------------
-- Engine seam
-- ---------------------------------------------------------------------------------------------

local function now(): number
	local fn = overrides.now
	return if fn ~= nil then fn() else Engine.now()
end

local function sourceCamera(): Camera?
	local fn = overrides.camera
	return if fn ~= nil then fn() else Engine.camera()
end

local function playerGui(): Instance?
	local fn = overrides.playerGui
	return if fn ~= nil then fn() else Engine.playerGui()
end

local function qualityRow(): Impact.QualityRow
	local fn = overrides.quality
	local tier = if fn ~= nil then fn() else Quality.get()
	return Impact.quality[tier] or Impact.quality.High
end

local function rng(): Random
	return overrides.random or random
end

-- The size a silhouette draws a part at: the smear's stored rest size for a stretched sword
-- (Smear.restSize), else the part's own.
local function restSizeOf(part: BasePart): Vector3
	return Smear.restSize(part) or part.Size
end

-- Binds the step after the camera's own (CameraController binds at Camera priority), so the
-- overlay camera copies this frame's view. Returns nil when there is no engine (Lune).
local function defaultOnRender(step: (dt: number) -> ()): (() -> ())?
	local name = Impact.overlay.renderStepName
	local ok = pcall(function()
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, step)
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

local function onRender(step: (dt: number) -> ()): (() -> ())?
	local fn = overrides.onRender
	return if fn ~= nil then fn(step) else defaultOnRender(step)
end

local function viewportSize(): Vector2?
	local camera = sourceCamera()
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

local function aspect(): number
	local fn = overrides.aspect
	if fn ~= nil then
		return fn()
	end
	local size = viewportSize()
	return if size ~= nil then size.X / size.Y else Impact.strokes.fallbackAspect
end

local function project(position: Vector3): Vector2?
	local fn = overrides.project
	if fn ~= nil then
		return fn(position)
	end
	local camera = sourceCamera()
	local size = viewportSize()
	if camera == nil or size == nil then
		return nil
	end
	local ok, point = pcall(function()
		return (camera :: any):WorldToViewportPoint(position)
	end)
	if not ok or typeof(point) ~= "Vector3" or point.Z <= 0 then
		return nil
	end
	return Vector2.new(point.X / size.X, point.Y / size.Y)
end

-- ---------------------------------------------------------------------------------------------
-- The overlay tree
-- ---------------------------------------------------------------------------------------------

local function color(token: string): Color3
	return Palette.color3(token :: any)
end

-- True while an Instance is still in a tree (a destroyed one has no parent, and some hosts
-- refuse to read it at all).
local function alive(instance: Instance?): boolean
	if instance == nil then
		return false
	end
	local ok, parent = pcall(function(): Instance?
		return (instance :: Instance).Parent
	end)
	return ok and parent ~= nil
end

local function newStroke(parent: Instance): Frame
	local config = Impact.strokes
	local frame = Instance.new("Frame")
	frame.Name = "Stroke"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.SizeConstraint = Enum.SizeConstraint.RelativeYY -- both sides measured in screen heights
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = color(config.token)
	frame.ZIndex = Impact.overlay.zIndex.strokes
	frame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(config.cornerRadius, 0)
	corner.Parent = frame
	local keypoints = {}
	for _, key in config.taper do
		table.insert(keypoints, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new(keypoints)
	gradient.Rotation = 0 -- along the stroke: the slash runs along the Frame's own X
	gradient.Parent = frame
	frame.Parent = parent
	return frame
end

local function destroyGui()
	if gui ~= nil then
		pcall(function()
			(gui :: ScreenGui):Destroy()
		end)
	end
	gui = nil
	background = nil
	viewport = nil
	overlayCamera = nil
	strokeLayer = nil
	table.clear(strokes)
	table.clear(rigFolders)
end

local function build(parent: Instance): ScreenGui
	local overlay = Impact.overlay
	local screen = Instance.new("ScreenGui")
	screen.Name = overlay.screenGuiName
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = overlay.displayOrder
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local field = Instance.new("Frame")
	field.Name = "Background"
	field.Size = UDim2.fromScale(1, 1)
	field.BorderSizePixel = 0
	field.BackgroundTransparency = 1
	field.BackgroundColor3 = color(Impact.reduced.token)
	field.ZIndex = overlay.zIndex.background
	field.Parent = screen

	local view = Instance.new("ViewportFrame")
	view.Name = "Figures"
	view.Size = UDim2.fromScale(1, 1)
	view.BorderSizePixel = 0
	view.BackgroundTransparency = 1
	view.ImageTransparency = 0
	view.Ambient = color(Impact.viewport.ambientToken)
	view.LightColor = color(Impact.viewport.lightToken)
	view.ImageColor3 = color(Impact.viewport.ambientToken)
	view.ZIndex = overlay.zIndex.figures
	view.Visible = false
	view.Parent = screen

	local camera = Instance.new("Camera")
	camera.Name = Impact.viewport.cameraName
	camera.Parent = view
	pcall(function()
		view.CurrentCamera = camera
	end)

	local layer = Instance.new("Frame")
	layer.Name = "Strokes"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.ZIndex = overlay.zIndex.strokes
	layer.Visible = false
	layer.Parent = screen
	table.clear(strokes)
	for _ = 1, Impact.strokes.count.max do
		table.insert(strokes, newStroke(layer))
	end

	screen.Parent = parent
	gui = screen
	background = field
	viewport = view
	overlayCamera = camera
	strokeLayer = layer
	table.clear(rigFolders)
	return screen
end

-- The overlay, built once under the local PlayerGui (again if the PlayerGui lost it).
local function ensureGui(): ScreenGui?
	if alive(gui) then
		return gui
	end
	local parent = playerGui()
	if parent == nil then
		return nil
	end
	-- The PlayerGui lost the overlay (and the clones on screen with it): drop it, end what was
	-- showing, then build a new one.
	destroyGui()
	finish()
	return build(parent)
end

local function rigFolder(index: number): Model
	local existing: Model? = rigFolders[index]
	if existing ~= nil then
		return existing
	end
	local folder = Instance.new("Model")
	folder.Name = "Rig" .. tostring(index)
	folder.Parent = viewport
	rigFolders[index] = folder
	return folder
end

-- ---------------------------------------------------------------------------------------------
-- Silhouettes
-- ---------------------------------------------------------------------------------------------

local function excluded(part: Instance, model: Instance): boolean
	local node: Instance? = part
	while node ~= nil and node ~= model do
		if excludeSet[(node :: Instance).Name] then
			return true
		end
		node = (node :: Instance).Parent
	end
	return false
end

local function volume(part: BasePart): number
	local size = part.Size
	return size.X * size.Y * size.Z
end

-- The rig's visible BaseParts the silhouette draws, the largest first past the per-rig cap.
local function eligibleParts(model: Instance, cap: number): { BasePart }
	local config = Impact.silhouette
	local list: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		local part = descendant :: BasePart
		if part.Transparency >= config.hiddenTransparency or excluded(part, model) then
			continue
		end
		if config.skipWrapLayers and part:FindFirstChildOfClass("WrapLayer") ~= nil then
			continue
		end
		table.insert(list, part)
	end
	if #list > cap then
		table.sort(list, function(a, b)
			return volume(a) > volume(b)
		end)
		for index = #list, cap + 1, -1 do
			list[index] = nil
		end
	end
	return list
end

-- Flat, inert and untextured: the viewport's lighting does the rest.
local function flatten(clone: BasePart)
	local config = Impact.silhouette
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanQuery = false
	clone.CanTouch = false
	clone.CastShadow = false
	clone.Material = (Enum.Material :: any)[config.material]
	clone.Color = color(config.flatToken)
	clone.Transparency = 0
	clone.Reflectance = 0
	if clone:IsA("MeshPart") then
		pcall(function()
			(clone :: any).TextureID = ""
		end)
	end
	if clone:IsA("UnionOperation") then
		pcall(function()
			(clone :: any).UsePartColor = true
		end)
	end
end

-- Keeps only the mesh that gives a part its shape (a SpecialMesh on an accessory Handle, say),
-- with its texture and tint taken off; every other child goes.
local function strip(clone: BasePart)
	for _, child in clone:GetChildren() do
		if child:IsA("DataModelMesh") then
			pcall(function()
				(child :: any).TextureId = ""
			end)
			pcall(function()
				(child :: any).VertexColor = Vector3.one
			end)
		else
			child:Destroy()
		end
	end
	flatten(clone)
end

local function cloneOf(source: BasePart): BasePart?
	local ok, result = pcall(function(): Instance?
		return source:Clone()
	end)
	local copy: Instance? = if ok then result else nil
	if copy == nil then
		-- A part with Archivable off clones to nil: clone it with the flag on, then put it back.
		local okArchivable, made = pcall(function(): Instance?
			local was = source.Archivable
			source.Archivable = true
			local cloned = source:Clone()
			source.Archivable = was
			return cloned
		end)
		copy = if okArchivable then made else nil
	end
	if copy == nil or not copy:IsA("BasePart") then
		return nil
	end
	local clone = copy :: BasePart
	strip(clone)
	return clone
end

local function takePooled(source: BasePart): BasePart?
	local clone: BasePart? = pooled[source]
	if clone == nil then
		return nil
	end
	pooled[source] = nil
	local index = table.find(pooledOrder, source)
	if index ~= nil then
		table.remove(pooledOrder, index)
	end
	return clone
end

local function centreOf(models: { Model }): Vector3?
	local sum = Vector3.zero
	local count = 0
	for _, model in models do
		local position = Engine.modelPosition(model)
		if position ~= nil then
			sum += position
			count += 1
		end
	end
	return if count > 0 then sum / count else nil
end

-- `models` without repeats or non-Instances, after the rigs in `already`, up to the rig cap.
local function uniqueRigs(models: { Model }, already: { Model }?): { Model }
	local list: { Model } = {}
	local seen: { [Instance]: boolean } = {}
	local room = Impact.silhouette.maxRigs
	local prior: { Model } = already or {}
	for _, model in prior do
		seen[model] = true
		room -= 1
	end
	for _, model in models do
		if room <= 0 then
			break
		end
		if typeof(model) ~= "Instance" or seen[model] then
			continue
		end
		seen[model] = true
		table.insert(list, model)
		room -= 1
	end
	return list
end

-- Clones `rigs` into the viewport, the first into rig folder `firstIndex`.
local function buildSilhouettes(rigs: { Model }, firstIndex: number)
	for offset, model in rigs do
		local folder = rigFolder(firstIndex + offset - 1)
		for _, source in eligibleParts(model, partsPerRig) do
			local clone = takePooled(source) or cloneOf(source)
			if clone == nil then
				continue
			end
			clone.Size = restSizeOf(source)
			clone.CFrame = source.CFrame
			clone.Parent = folder
			table.insert(active, { source = source, clone = clone })
		end
	end
end

-- Back to the pool: unparented, kept for the source's next play, the oldest destroyed past the
-- cap. A clone whose source has left the world is destroyed at once.
local function releaseClones()
	for _, entry in active do
		-- A clone destroyed with a lost overlay refuses a new parent: it is simply dropped.
		local released = pcall(function()
			entry.clone.Parent = nil
		end)
		local taken: BasePart? = pooled[entry.source]
		if released and alive(entry.source) and taken == nil then
			pooled[entry.source] = entry.clone
			table.insert(pooledOrder, entry.source)
		else
			pcall(function()
				entry.clone:Destroy()
			end)
		end
	end
	table.clear(active)
	for index = #pooledOrder, 1, -1 do
		local source = pooledOrder[index]
		if not alive(source) then
			local clone: BasePart? = pooled[source]
			pooled[source] = nil
			table.remove(pooledOrder, index)
			if clone ~= nil then
				clone:Destroy()
			end
		end
	end
	while #pooledOrder > Impact.silhouette.poolCap do
		local oldest = table.remove(pooledOrder, 1) :: BasePart
		local clone: BasePart? = pooled[oldest]
		pooled[oldest] = nil
		if clone ~= nil then
			clone:Destroy()
		end
	end
end

local function syncFigures()
	local camera = sourceCamera()
	local own = overlayCamera
	if camera ~= nil and own ~= nil then
		own.CFrame = camera.CFrame
		own.FieldOfView = camera.FieldOfView
	end
	for _, entry in active do
		entry.clone.CFrame = entry.source.CFrame
	end
end

-- ---------------------------------------------------------------------------------------------
-- Strokes
-- ---------------------------------------------------------------------------------------------

local function slashAngle(direction: Vector2?): number
	local config = Impact.strokes
	if direction ~= nil and direction.Magnitude > config.directionEpsilon then
		return math.deg(math.atan2(direction.Y, direction.X))
	end
	return config.defaultAngle
end

-- Lays the strokes along the slash, fanned in even lanes across the hit with a little jitter.
local function layoutStrokes(centre: Vector2, angle: number)
	local config = Impact.strokes
	local generator = rng()
	local count = generator:NextInteger(config.count.min, config.count.max)
	local radians = math.rad(angle)
	local alongX, alongY = math.cos(radians), math.sin(radians)
	local acrossX, acrossY = -alongY, alongX
	local widthOverHeight = aspect()
	for index, frame in strokes do
		if index > count then
			frame.Visible = false
			continue
		end
		local lane = (2 * (index - 0.5) / count - 1) * config.spread
			+ generator:NextNumber(-config.laneJitter, config.laneJitter)
		local slide = generator:NextNumber(-config.slide, config.slide)
		-- Offsets are in screen heights; the X scale divides by width / height.
		local dx = (acrossX * lane + alongX * slide) / widthOverHeight
		local dy = acrossY * lane + alongY * slide
		frame.Position = UDim2.fromScale(centre.X + dx, centre.Y + dy)
		frame.Size = UDim2.fromScale(
			generator:NextNumber(config.length.min, config.length.max),
			generator:NextNumber(config.width.min, config.width.max)
		)
		frame.Rotation = angle + generator:NextNumber(-config.jitterDegrees, config.jitterDegrees)
		frame.Visible = true
	end
end

local function hideStrokes()
	for _, frame in strokes do
		frame.Visible = false
	end
end

-- ---------------------------------------------------------------------------------------------
-- Showing and hiding
-- ---------------------------------------------------------------------------------------------

local function applyLook(name: string)
	local look = Impact.looks[name]
	local field = background :: Frame
	local view = viewport :: ViewportFrame
	field.BackgroundColor3 = color(look.background)
	field.BackgroundTransparency = 0
	local figures = look.figures
	view.Visible = figuresOn and figures ~= nil
	if figures ~= nil then
		view.ImageColor3 = color(figures)
	end
	if strokeLayer ~= nil then
		(strokeLayer :: Frame).Visible = strokesOn and look.strokes
	end
end

local function hide()
	-- Guarded: the overlay may have gone down with the PlayerGui mid-sequence.
	pcall(function()
		if gui ~= nil then
			(gui :: ScreenGui).Enabled = false
		end
		if background ~= nil then
			(background :: Frame).BackgroundTransparency = 1
		end
		if viewport ~= nil then
			(viewport :: ViewportFrame).Visible = false
		end
		if strokeLayer ~= nil then
			(strokeLayer :: Frame).Visible = false
		end
		hideStrokes()
	end)
end

-- The picture still changes at `at`: the flash budget keeps its cost until a window after.
local function holdClaim(current: Showing, at: number)
	local claim = current.claim
	if claim ~= nil then
		FlashBudget.hold(claim, at)
	end
end

finish = function()
	local current = showing
	if current == nil then
		return
	end
	showing = nil
	if current.unbind ~= nil then
		current.unbind()
	end
	hide()
	releaseClones()
	-- The frame the overlay hides is its last change: the scene comes back.
	holdClaim(current, now())
end

local function dimOpacityOf(current: Showing, at: number): number
	return ImpactSequence.dimOpacity(at - (current.startedAt or at), current.from, current.hold)
end

-- Seconds left of what shows; a sequence not drawn yet has all of it left.
local function remainingOf(current: Showing, at: number): number
	local began = current.startedAt
	if began == nil then
		return current.seconds
	end
	local total = if current.kind == "Dim" then ImpactSequence.dimSeconds(current.hold) else current.seconds
	return math.max(0, began + total - at)
end

-- The looks put on screen so far under the claim: those of the sequences this one took over,
-- then its own (none of its own before its first drawn frame).
local function drawnLooks(current: Showing): { string }
	local names: { string } = table.clone(current.shownBefore)
	if current.startedAt == nil then
		return names
	end
	for index = 1, current.index do
		table.insert(names, current.frames[index].look)
	end
	return names
end

local function stepDim(current: Showing, at: number)
	local began = current.startedAt or at
	if at - began >= ImpactSequence.dimSeconds(current.hold) then
		finish()
		return
	end
	(background :: Frame).BackgroundTransparency = 1 - dimOpacityOf(current, at)
	holdClaim(current, at)
end

local function stepSequence(current: Showing, at: number)
	local began = current.startedAt
	if began == nil then
		-- The first frame drawn since play: the clock starts here, on the first look.
		current.startedAt = at
		syncFigures()
		holdClaim(current, at)
		return
	end
	local elapsed = at - began
	local frame = current.frames[current.index]
	-- A look ends on the first drawn frame at or past its finish, to the nearest frame, so each
	-- look is drawn at least once and a 60 fps frame clock that runs a hair fast never adds one.
	local due = elapsed >= frame.finish - Impact.frameSeconds * 0.5
	if elapsed >= current.cap or (due and current.index >= #current.frames) then
		finish()
		return
	end
	if due then
		current.index += 1
		local look = current.frames[current.index].look
		current.look = look
		applyLook(look)
	end
	syncFigures()
	holdClaim(current, at)
end

local function step()
	local current = showing
	if current == nil then
		return
	end
	if current.kind == "Dim" then
		stepDim(current, now())
	else
		stepSequence(current, now())
	end
end

-- Starts the per-frame step for what is showing; with no render step (no engine) the overlay
-- still ends on time through task.delay.
local function run(current: Showing)
	local unbind = onRender(function()
		step()
	end)
	if unbind ~= nil then
		current.unbind = unbind
		return
	end
	task.delay(current.seconds, function()
		if showing == current then
			finish()
		end
	end)
end

-- Draws `rigs` into the sequence showing too (another target of the same sweep), up to the rig cap.
local function join(current: Showing, models: { Model })
	local added = uniqueRigs(models, current.rigs)
	if #added == 0 then
		return
	end
	local firstIndex = #current.rigs + 1
	for _, model in added do
		table.insert(current.rigs, model)
	end
	if figuresOn and current.wantsFigures then
		buildSilhouettes(added, firstIndex)
		syncFigures()
	end
end

-- True when Reduce flashing still allows a new dim at `at`: fewer than impact.reduced.maxPerWindow
-- dims it let start are still counted (each until a window after its end, like the budget).
local function reducedAllows(at: number): boolean
	for index = #reducedDims, 1, -1 do
		if at - reducedDims[index].finish >= Impact.flash.windowSeconds then
			table.remove(reducedDims, index)
		end
	end
	return #reducedDims < Impact.reduced.maxPerWindow
end

-- The soft dim, or more of the one showing. Returns the seconds it lasts (0 when refused).
-- `reduced`: asked for by the Reduce flashing setting, which allows fewer dims than the budget.
local function playDim(name: string, budgetNow: number, reduced: boolean): number
	local at = now()
	local current = showing
	if current ~= nil and current.kind == "Sequence" then
		-- Reduce flashing came on while a sequence showed: it goes at once.
		ImpactFrames.cancel()
		current = nil
	end
	local fadeIn = Impact.reduced.fadeInFrames * Impact.frameSeconds
	if current ~= nil then
		local elapsed = at - (current.startedAt or at)
		if elapsed < fadeIn + current.hold then
			-- Rising or at its peak: it stays at the peak at least as long as a dim of its own
			-- would, with no fade out and in again between (no new flash, nothing charged).
			current.hold = math.max(current.hold, elapsed + ImpactSequence.dimHoldSeconds())
			holdClaim(current, (current.startedAt or at) + ImpactSequence.dimSeconds(current.hold))
			return remainingOf(current, at)
		end
	end
	-- A new dim, or one rising again out of a fade: a new flash.
	if reduced and not reducedAllows(budgetNow) then
		return if current ~= nil then remainingOf(current, at) else 0
	end
	local claim = FlashBudget.claim(budgetNow, Impact.reduced.flashCost, ImpactSequence.dimSeconds())
	if claim == nil then
		return if current ~= nil then remainingOf(current, at) else 0
	end
	if reduced then
		table.insert(reducedDims, claim)
	end
	local from = if current ~= nil then dimOpacityOf(current, at) else 0
	ImpactFrames.cancel()
	local field = background :: Frame
	field.BackgroundColor3 = color(Impact.reduced.token)
	field.BackgroundTransparency = 1 - from
	local dim: Showing = {
		kind = "Dim",
		name = name,
		rank = 0,
		startedAt = at,
		frames = {},
		index = 0,
		seconds = ImpactSequence.dimSeconds(),
		cap = math.huge,
		from = from,
		hold = ImpactSequence.dimHoldSeconds(),
		look = nil,
		unbind = nil,
		claim = claim,
		shownBefore = {},
		rigs = {},
		wantsFigures = false,
	}
	showing = dim;
	(gui :: ScreenGui).Enabled = true
	run(dim)
	return dim.seconds
end

-- Puts a sequence on screen with its claim (whatever showed before goes); `shownBefore` holds the
-- looks a sequence it takes over already drew under that claim.
local function showSequence(
	sequence: string,
	frames: { ImpactSequence.Frame },
	rigs: { Model },
	options: Options,
	claim: FlashBudget.Claim,
	shownBefore: { string }?
): number
	local screen = gui :: ScreenGui
	ImpactFrames.cancel()
	local row = qualityRow()
	figuresOn = row.silhouettes
	strokesOn = row.strokes
	partsPerRig = row.maxPartsPerRig
	local wantsFigures, wantsStrokes = false, false
	for _, frame in frames do
		local look = Impact.looks[frame.look]
		wantsFigures = wantsFigures or look.figures ~= nil
		wantsStrokes = wantsStrokes or look.strokes
	end
	if figuresOn and wantsFigures then
		buildSilhouettes(rigs, 1)
	end
	if strokesOn and wantsStrokes then
		local hit = options.position or centreOf(rigs)
		local centre = if hit ~= nil then project(hit) else nil
		local point = centre or Vector2.new(0.5, 0.5)
		layoutStrokes(
			Vector2.new(math.clamp(point.X, 0, 1), math.clamp(point.Y, 0, 1)),
			slashAngle(options.slashDirection)
		)
	end

	local current: Showing = {
		kind = "Sequence",
		name = sequence,
		rank = ImpactSequence.rank(sequence),
		startedAt = nil,
		frames = frames,
		index = 1,
		seconds = ImpactSequence.seconds(sequence),
		cap = ImpactSequence.capSeconds(sequence),
		from = 0,
		hold = 0,
		look = frames[1].look,
		unbind = nil,
		claim = claim,
		shownBefore = shownBefore or {},
		rigs = table.clone(rigs),
		wantsFigures = wantsFigures,
	}
	showing = current
	applyLook(current.look :: string)
	syncFigures()
	screen.Enabled = true
	run(current)
	return current.seconds
end

-- ---------------------------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------------------------

--- Plays impact.sequences[sequence] full screen with `models` as flat silhouettes. Asks
--- FlashBudget itself and shows the soft dim instead when the budget says no or Reduce flashing
--- is on. Returns the seconds the overlay lasts (0 if nothing showed).
function ImpactFrames.play(sequence: string, models: { Model }, opts: Options?): number
	if not ImpactSequence.has(sequence) then
		warn(("[ImpactFrames] unknown sequence '%s'"):format(tostring(sequence)))
		return 0
	end
	local screen = ensureGui()
	if screen == nil then
		return 0
	end
	local frames = ImpactSequence.frames(sequence)
	if #frames == 0 then
		return 0
	end
	local options: Options = opts or {}
	local budgetNow = if options.now ~= nil then options.now else now()
	local rigs = uniqueRigs(models or {})
	if FlashBudget.reduced() then
		return playDim(sequence, budgetNow, true)
	end

	local current = showing
	if current ~= nil and current.kind == "Sequence" then
		-- Another hit of the same frame or the same burst: never a second charge for one picture.
		if ImpactSequence.rank(sequence) > current.rank then
			-- Every look drawn under the claim, through any takeover earlier in this frame.
			local shown = drawnLooks(current)
			local path = table.clone(shown)
			for _, frame in frames do
				table.insert(path, frame.look)
			end
			local claim = current.claim
			if claim ~= nil and FlashBudget.raise(claim, budgetNow, ImpactSequence.costOfLooks(path, Impact.looks)) then
				-- The bigger sequence takes the screen, keeping every rig drawn so far.
				local all = table.clone(current.rigs)
				for _, model in uniqueRigs(models or {}, current.rigs) do
					table.insert(all, model)
				end
				return showSequence(sequence, frames, all, options, claim, shown)
			end
		end
		join(current, rigs)
		return remainingOf(current, now())
	end

	local claim = FlashBudget.claim(budgetNow, ImpactSequence.flashCost(sequence), ImpactSequence.seconds(sequence))
	if claim == nil then
		return playDim(sequence, budgetNow, false)
	end
	return showSequence(sequence, frames, rigs, options, claim)
end

--- True while an impact sequence or the soft dim is on screen.
function ImpactFrames.isShowing(): boolean
	return showing ~= nil
end

--- The look on screen ("Dark", "Ink"...), "Reduced" for the soft dim, or nil when idle.
function ImpactFrames.look(): string?
	local current = showing
	if current == nil then
		return nil
	end
	return if current.kind == "Dim" then "Reduced" else current.look
end

--- Seconds left of what is on screen (impact frames or the dim); 0 when idle.
function ImpactFrames.remaining(): number
	local current = showing
	return if current ~= nil then remainingOf(current, now()) else 0
end

--- Seconds the opaque impact frames still hide the 3D world (0 while idle or dimming); the
--- director starts its world-space accents after them so they are not drawn under the overlay.
function ImpactFrames.hiddenSeconds(): number
	local current = showing
	if current == nil or current.kind ~= "Sequence" then
		return 0
	end
	return remainingOf(current, now())
end

--- Hides whatever is showing at once and returns its clones to the pool.
function ImpactFrames.cancel()
	finish()
end

--- Advances the overlay to the clock's time (the render step calls this; specs may too).
function ImpactFrames.step()
	step()
end

--- Builds the overlay under the PlayerGui ahead of the first hit and watches the Reduce flashing
--- setting; a sequence showing when the setting turns on is cut at once (idempotent).
function ImpactFrames.start()
	ensureGui()
	FlashBudget.start()
	if started then
		return
	end
	started = true
	FlashBudget.changed:Connect(function(reduced: boolean)
		local current = showing
		if reduced and current ~= nil and current.kind == "Sequence" then
			ImpactFrames.cancel()
		end
	end)
end

--- Replaces the engine surface (specs: a fake clock, render step, PlayerGui, camera); nil
--- restores the engine. Drops the overlay and the pool so the next play builds fresh.
function ImpactFrames.bind(deps: Deps?)
	ImpactFrames.cancel()
	table.clear(reducedDims)
	for source, clone in pooled do
		pooled[source] = nil
		clone:Destroy()
	end
	table.clear(pooledOrder)
	destroyGui()
	overrides = deps or {}
end

--- A screen direction (x right, y down) for a world swing direction at a world point, from the
--- current camera (the director turns Trails.swingDirection into a slashDirection with it).
function ImpactFrames.screenDirection(position: Vector3, direction: Vector3): Vector2?
	local from = project(position)
	local to = project(position + direction)
	if from == nil or to == nil then
		return nil
	end
	local delta = Vector2.new((to.X - from.X) * aspect(), to.Y - from.Y)
	if delta.Magnitude <= Impact.strokes.directionEpsilon then
		return nil
	end
	return delta.Unit
end

--- The overlay ScreenGui, or nil before the first build (specs).
function ImpactFrames.gui(): ScreenGui?
	return gui
end

--- The silhouette clones on screen now (specs).
function ImpactFrames.clones(): { BasePart }
	local list = {}
	for _, entry in active do
		table.insert(list, entry.clone)
	end
	return list
end

--- Idle clones kept in the pool (specs).
function ImpactFrames.pooledCount(): number
	return #pooledOrder
end

--- The overlay's own camera (specs read its CFrame and FieldOfView).
function ImpactFrames.camera(): Camera?
	return overlayCamera
end

return ImpactFrames
