--!strict
--[[
	SlashArc: the reel's flat-color slash crescent, and the thin chromatic slash line.

	The crescent bows through the hit point in the swing plane. `tangent` is the swing direction
	(the blade's motion at the hit) and `normal` the swing's rotation axis (right-hand rule), so
	the crescent bulges away from the swing's center, along tangent x normal. The curve is one
	cubic Bezier from the trailing point to the leading point with its apex on the hit; it is
	split at the apex into two halves, and each half is a Beam pair between pooled Attachments on
	an anchored invisible part, curved with CurveSize0 / CurveSize1: an outer Beam in the token's
	color and a narrower SystemWhite core. Widths taper from the apex to nothing at both points,
	Texture is empty, FaceCamera is off and LightInfluence 0, so it reads as one flat shape. It
	snaps on in one frame, holds, and wipes out from the trailing point to the leading one
	(Transparency keyed along each beam over time); the core finishes its wipe first. The wipe
	front snaps to accents.slashArc.wipeSteps steps whose sequences are built once, so a frame
	of the wipe assigns a prebuilt sequence (and only when the step moved) and builds nothing.

	`line(position, tangent, size)` is the thin line along the blade's path across the hit for
	Art final hits and kills: three straight camera-facing Beams through the hit point along the
	tangent, a SystemWhite core and TrailRose and SystemCyan copies offset across the screen. It
	grows out in a frame or two, holds, then thins to nothing. Its attachments are laid by
	Position on a host with no turn, so a frame of it builds no CFrame either.

	Neither is a full-screen flash. At most the tier's `arcs` crescents and `lines` lines play at
	once; past that the oldest is reused. Every instance is pooled.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Accents = require(Shared.data.accents)
local Palette = require(Shared.data.palette)
local Easing = require(Shared.util.Easing)
local Engine = require(script.Parent.Engine)
local Quality = require(script.Parent.Quality)
local AccentStep = require(script.Parent.AccentStep)

export type Geometry = {
	a: Vector3, -- the trailing point
	aControl: Vector3, -- first half's control points
	mIn: Vector3,
	m: Vector3, -- the apex: the hit point
	mOut: Vector3, -- second half's control points
	bControl: Vector3,
	b: Vector3, -- the leading point
	tangent: Vector3, -- unit, along the swing
	normal: Vector3, -- unit, the swing plane's normal
	outward: Vector3, -- unit, where the crescent bulges (tangent x normal)
}

export type LinePose = {
	length: number, -- fraction of the size's length
	width: number, -- fraction of the size's width
	done: boolean,
}

export type ArcView = {
	host: BasePart,
	attachments: { Attachment }, -- trailing point, apex, leading point
	outer: { Beam }, -- first half, second half
	inner: { Beam },
	size: string,
	active: boolean,
}

export type LineView = {
	host: BasePart,
	beams: { Beam }, -- core, then the edge copies in accents.slashLine.edgeTokens order
	starts: { Attachment },
	ends: { Attachment },
	size: string,
	active: boolean,
}

type Arc = {
	host: BasePart,
	a: Attachment,
	m: Attachment,
	b: Attachment,
	outer: { Beam },
	inner: { Beam },
	size: string,
	config: Accents.ArcSize,
	started: number,
	serial: number,
	active: boolean,
	outerStep: number, -- the wipe step the outer beams show; -1 before the first
	innerStep: number,
}

type Line = {
	host: BasePart,
	beams: { Beam },
	starts: { Attachment },
	ends: { Attachment },
	offsets: { Vector3 }, -- each beam's offset off the hit point, across the screen
	tangent: Vector3,
	size: string,
	config: Accents.LineSize,
	started: number,
	serial: number,
	active: boolean,
	laidLength: number, -- the pose last laid; -1 before the first
	laidWidth: number,
}

local SlashArc = {}

local arcs: { Arc } = {}
local lines: { Line } = {}
local deps: AccentStep.Deps = AccentStep.deps()
local stopLoop: (() -> ())? = nil
local serial = 0
local arcFolder: Instance? = nil
local lineFolder: Instance? = nil
-- Transparency sequences per wipe step, built once: [layer][half][step + 1], layer 1 the outer
-- (color) beams and 2 the inner (white) ones, half 1 the trailing half and 2 the leading one.
local wipeCache: { { { NumberSequence } } }? = nil
-- The slash line's Transparency: [1] the core, [2] the split-edge copies; built once.
local lineFades: { NumberSequence }? = nil
-- The pose each line is laid from, reused frame to frame.
local linePoseScratch: LinePose = { length = 1, width = 1, done = false }

local function unit(v: Vector3): Vector3?
	local length = v.Magnitude
	if length < 1e-6 then
		return nil
	end
	return v / length
end

-- `candidate` with its part along `t` removed, as a unit vector; nil when nothing is left.
local function perpendicular(candidate: Vector3, t: Vector3): Vector3?
	return unit(candidate - t * candidate:Dot(t))
end

local function midpoint(p: Vector3, q: Vector3): Vector3
	return (p + q) * 0.5
end

local function arcSize(name: string): (string, Accents.ArcSize)
	local config = Accents.slashArc
	local found = config.sizes[name]
	if found ~= nil then
		return name, found
	end
	return config.defaultSize, config.sizes[config.defaultSize]
end

local function lineSize(name: string): (string, Accents.LineSize)
	local config = Accents.slashLine
	local found = config.sizes[name]
	if found ~= nil then
		return name, found
	end
	return config.defaultSize, config.sizes[config.defaultSize]
end

local function newHost(name: string, size: number, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * size
	part.Parent = parent
	return part
end

local function newAttachment(host: BasePart, name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = host
	return attachment
end

local function newBeam(host: BasePart, name: string, a0: Attachment, a1: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Texture = ""
	beam.Enabled = false
	beam.Parent = host
	return beam
end

local function ensureArcFolder(): Instance
	if arcFolder == nil then
		arcFolder = Engine.folder(workspace, Accents.slashArc.folderName)
	end
	return arcFolder :: Instance
end

local function ensureLineFolder(): Instance
	if lineFolder == nil then
		lineFolder = Engine.folder(workspace, Accents.slashLine.folderName)
	end
	return lineFolder :: Instance
end

local function newArc(): Arc
	local config = Accents.slashArc
	local host = newHost("SlashArc", config.hostSize, ensureArcFolder())
	local a = newAttachment(host, "Trailing")
	local m = newAttachment(host, "Apex")
	local b = newAttachment(host, "Leading")
	local outer = { newBeam(host, "OuterTrailing", a, m), newBeam(host, "OuterLeading", m, b) }
	local inner = { newBeam(host, "InnerTrailing", a, m), newBeam(host, "InnerLeading", m, b) }
	for _, beam in outer do
		beam.FaceCamera = false
		beam.LightEmission = config.outerLightEmission
		beam.LightInfluence = config.lightInfluence
		beam.ZOffset = 0
	end
	local white = ColorSequence.new(Palette.color3(config.innerToken :: any))
	for _, beam in inner do
		beam.FaceCamera = false
		beam.LightEmission = config.innerLightEmission
		beam.LightInfluence = config.lightInfluence
		beam.ZOffset = config.innerZOffset
		beam.Color = white
	end
	local name, size = arcSize(config.defaultSize)
	return {
		host = host,
		a = a,
		m = m,
		b = b,
		outer = outer,
		inner = inner,
		size = name,
		config = size,
		started = 0,
		serial = 0,
		active = false,
		outerStep = -1,
		innerStep = -1,
	}
end

local function newLine(): Line
	local config = Accents.slashLine
	local host = newHost("SlashLine", config.hostSize, ensureLineFolder())
	local beams: { Beam } = {}
	local starts: { Attachment } = {}
	local ends: { Attachment } = {}
	local tokens = { config.coreToken }
	for _, token in config.edgeTokens do
		table.insert(tokens, token)
	end
	for index, token in tokens do
		local first = newAttachment(host, "Start" .. token)
		local last = newAttachment(host, "End" .. token)
		local beam = newBeam(host, if index == 1 then "Core" else "Edge" .. token, first, last)
		beam.FaceCamera = config.faceCamera
		beam.LightEmission = config.lightEmission
		beam.LightInfluence = config.lightInfluence
		beam.Segments = 1
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.Color = ColorSequence.new(Palette.color3(token :: any))
		-- The core draws over the edge copies.
		beam.ZOffset = if index == 1 then config.coreZOffset else 0
		table.insert(beams, beam)
		table.insert(starts, first)
		table.insert(ends, last)
	end
	local name, size = lineSize(config.defaultSize)
	return {
		host = host,
		beams = beams,
		starts = starts,
		ends = ends,
		offsets = {},
		tangent = Vector3.xAxis,
		size = name,
		config = size,
		started = 0,
		serial = 0,
		active = false,
		laidLength = -1,
		laidWidth = -1,
	}
end

-- A free item while fewer than `cap` play; past the cap the oldest playing one is reused.
local function acquire(pool: { any }, cap: number, build: () -> any): any
	local active = 0
	local oldest: any = nil
	local free: any = nil
	for _, item in pool do
		if item.active then
			active += 1
			if oldest == nil or item.serial < oldest.serial then
				oldest = item
			end
		elseif free == nil then
			free = item
		end
	end
	if active >= cap and oldest ~= nil then
		return oldest
	end
	if free ~= nil then
		return free
	end
	local item = build()
	table.insert(pool, item)
	return item
end

-- The attachment frame at `position` whose X axis is `axis` and whose face axis (Y or Z, from
-- accents.slashArc.faceAxis) is the swing plane's normal.
local function attachmentFrame(position: Vector3, axis: Vector3, normal: Vector3): CFrame
	if Accents.slashArc.faceAxis == "Z" then
		return CFrame.fromMatrix(position, axis, normal:Cross(axis))
	end
	return CFrame.fromMatrix(position, axis, normal)
end

local function sequence(keys: { { number } }): NumberSequence
	local points = {}
	for _, key in keys do
		table.insert(points, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	return NumberSequence.new(points)
end

-- Transparency along one crescent half: `from`..`to` is the half's share of the whole crescent
-- (0 at the trailing point, 1 at the leading point); everything behind the front is gone.
local function halfSequence(from: number, to: number, front: number, base: number): NumberSequence
	local count = math.max(2, Accents.slashArc.wipeKeys)
	local keys: { { number } } = {}
	for index = 1, count do
		local x = (index - 1) / (count - 1)
		table.insert(keys, { x, SlashArc.transparencyAt(from + (to - from) * x, front, base) })
	end
	return sequence(keys)
end

-- The wipe front at `step` of accents.slashArc.wipeSteps (0 whole .. wipeSteps gone).
local function stepFront(step: number): number
	local config = Accents.slashArc
	return -config.wipeSoftness + (1 + config.wipeSoftness) * step / math.max(1, config.wipeSteps)
end

local function ensureWipeCache(): { { { NumberSequence } } }
	local cache = wipeCache
	if cache == nil then
		local config = Accents.slashArc
		local built: { { { NumberSequence } } } = {}
		for layer, base in { config.outerTransparency, config.innerTransparency } do
			local halves: { { NumberSequence } } = {}
			for half, range in { { 0, 0.5 }, { 0.5, 1 } } do
				local list: { NumberSequence } = {}
				for step = 0, math.max(1, config.wipeSteps) do
					list[step + 1] = halfSequence(range[1], range[2], stepFront(step), base)
				end
				halves[half] = list
			end
			built[layer] = halves
		end
		wipeCache = built
		cache = built
	end
	return cache :: { { { NumberSequence } } }
end

local function ensureLineFades(): { NumberSequence }
	local fades = lineFades
	if fades == nil then
		local config = Accents.slashLine
		local fade = config.endFade
		local built: { NumberSequence } = {}
		for index, base in { config.coreTransparency, config.edgeTransparency } do
			built[index] = sequence({ { 0, 1 }, { fade, base }, { 1 - fade, base }, { 1, 1 } })
		end
		lineFades = built
		fades = built
	end
	return fades :: { NumberSequence }
end

-- Shows each layer's prebuilt sequences for the steps its front snaps to; a layer whose step has
-- not moved is left as it is (no write).
local function setArcTransparency(arc: Arc, outerFront: number, innerFront: number)
	local cache = ensureWipeCache()
	local outerStep = SlashArc.wipeStep(outerFront)
	local innerStep = SlashArc.wipeStep(innerFront)
	if outerStep ~= arc.outerStep then
		arc.outerStep = outerStep
		arc.outer[1].Transparency = cache[1][1][outerStep + 1]
		arc.outer[2].Transparency = cache[1][2][outerStep + 1]
	end
	if innerStep ~= arc.innerStep then
		arc.innerStep = innerStep
		arc.inner[1].Transparency = cache[2][1][innerStep + 1]
		arc.inner[2].Transparency = cache[2][2][innerStep + 1]
	end
end

local function hideArc(arc: Arc)
	arc.active = false
	for _, beam in arc.outer do
		beam.Enabled = false
	end
	for _, beam in arc.inner do
		beam.Enabled = false
	end
end

local function hideLine(line: Line)
	line.active = false
	for _, beam in line.beams do
		beam.Enabled = false
	end
end

-- Lays the line's beams for a pose. The host sits on the hit with no turn, so each end's place on
-- it is its beam's offset off the hit plus or minus half the length along the tangent (Position:
-- no CFrame built). A pose already laid is not written again.
local function layLine(line: Line, pose: LinePose)
	if pose.length == line.laidLength and pose.width == line.laidWidth then
		return
	end
	line.laidLength = pose.length
	line.laidWidth = pose.width
	local along = line.tangent * (line.config.length * pose.length * 0.5)
	local width = line.config.width * pose.width
	for index, beam in line.beams do
		local offset = line.offsets[index] or Vector3.zero
		line.starts[index].Position = offset - along
		line.ends[index].Position = offset + along
		beam.Width0 = width
		beam.Width1 = width
	end
end

-- SlashArc.linePose written into `into` (the step loop reuses one table).
local function linePoseInto(size: string, elapsed: number, into: LinePose): LinePose
	local config = Accents.slashLine
	local _, found = lineSize(size)
	local grow = Accents.seconds(found.growFrames)
	local hold = Accents.seconds(found.holdFrames)
	local thin = Accents.seconds(found.thinFrames)
	if elapsed + 1e-6 >= Accents.seconds(found.growFrames + found.holdFrames + found.thinFrames) then
		into.length, into.width, into.done = 1, 0, true
		return into
	end
	local length = 1
	if grow > 0 and elapsed < grow then
		local eased = Easing.evaluate(config.growEasing, math.max(elapsed, 0) / grow)
		length = found.startLength + (1 - found.startLength) * eased
	end
	local width = 1
	if elapsed >= grow + hold then
		width = 1 - Easing.evaluate(config.thinEasing, (elapsed - grow - hold) / thin)
	end
	into.length, into.width, into.done = length, width, false
	return into
end

local function step()
	local now = deps.now()
	local any = false
	for _, arc in arcs do
		if not arc.active then
			continue
		end
		local outerFront, innerFront = SlashArc.wipeFront(arc.size, now - arc.started)
		if outerFront == nil or innerFront == nil then
			hideArc(arc)
			continue
		end
		any = true
		setArcTransparency(arc, outerFront, innerFront)
	end
	for _, line in lines do
		if not line.active then
			continue
		end
		local pose = linePoseInto(line.size, now - line.started, linePoseScratch)
		if pose.done then
			hideLine(line)
			continue
		end
		any = true
		layLine(line, pose)
	end
	if not any and stopLoop ~= nil then
		local stop = stopLoop :: () -> ()
		stopLoop = nil
		stop()
	end
end

local function ensureLoop()
	if stopLoop == nil then
		stopLoop = deps.onStep(function()
			step()
		end)
	end
end

--- The crescent's curve for a hit (pure): its apex on `position`, bulging along tangent x normal.
--- A normal along the tangent falls back to the plane holding the tangent and world up; nil when
--- the tangent is zero.
function SlashArc.geometry(position: Vector3, tangent: Vector3, normal: Vector3, size: string): Geometry?
	local t = unit(tangent)
	if t == nil then
		return nil
	end
	local tUnit = t :: Vector3
	local n = perpendicular(normal, tUnit) or perpendicular(Vector3.yAxis, tUnit) or perpendicular(Vector3.xAxis, tUnit)
	if n == nil then
		return nil
	end
	local nUnit = n :: Vector3
	local outward = tUnit:Cross(nUnit)
	local _, config = arcSize(size)
	local half = config.length * 0.5
	local lean = config.length * Accents.slashArc.endSpread
	local p0 = -tUnit * half
	local p3 = tUnit * half
	local p1 = p0 + tUnit * lean + outward * config.bow
	local p2 = p3 - tUnit * lean + outward * config.bow
	-- Split the cubic at its middle (de Casteljau): the apex and each half's control points.
	local l1 = midpoint(p0, p1)
	local q = midpoint(p1, p2)
	local r2 = midpoint(p2, p3)
	local l2 = midpoint(l1, q)
	local r1 = midpoint(q, r2)
	local apex = midpoint(l2, r1)
	local shift = position - apex
	return {
		a = p0 + shift,
		aControl = l1 + shift,
		mIn = l2 + shift,
		m = position,
		mOut = r1 + shift,
		bControl = r2 + shift,
		b = p3 + shift,
		tangent = tUnit,
		normal = nUnit,
		outward = outward,
	}
end

--- Transparency at `s` along the crescent (0 trailing .. 1 leading) for a wipe front (pure).
function SlashArc.transparencyAt(s: number, front: number, base: number): number
	local softness = math.max(Accents.slashArc.wipeSoftness, 1e-6)
	if s < front then
		return 1
	elseif s < front + softness then
		return 1 - (1 - base) * ((s - front) / softness)
	end
	return base
end

--- The wipe step a front snaps to (0 whole .. accents.slashArc.wipeSteps gone) and that step's
--- front (pure): the crescent shows the snapped front, never more than half a step off.
function SlashArc.wipeStep(front: number): (number, number)
	local config = Accents.slashArc
	local steps = math.max(1, config.wipeSteps)
	local raw = (front + config.wipeSoftness) / (1 + config.wipeSoftness) * steps
	local step = math.clamp(math.floor(raw + 0.5), 0, steps)
	return step, stepFront(step)
end

--- The wipe fronts (outer, inner) `elapsed` seconds into a crescent of `size`; nil once it is gone.
function SlashArc.wipeFront(size: string, elapsed: number): (number?, number?)
	local config = Accents.slashArc
	local _, found = arcSize(size)
	local hold = Accents.seconds(found.holdFrames)
	local wipe = Accents.seconds(found.wipeFrames)
	local softness = config.wipeSoftness
	-- 1e-6: a clock summed frame by frame lands a hair short of the frame count it reached.
	if elapsed + 1e-6 >= Accents.seconds(found.holdFrames + found.wipeFrames) then
		return nil, nil
	end
	if elapsed < hold then
		return -softness, -softness
	end
	local t = (elapsed - hold) / wipe
	local innerT = math.min(1, t / math.max(1 - config.innerLead, 1e-6))
	local outer = -softness + (1 + softness) * Easing.evaluate(config.wipeEasing, t)
	local inner = -softness + (1 + softness) * Easing.evaluate(config.wipeEasing, innerT)
	return outer, inner
end

--- Seconds a crescent of `size` lasts, snap to gone.
function SlashArc.seconds(size: string): number
	local _, found = arcSize(size)
	return Accents.seconds(found.holdFrames + found.wipeFrames)
end

--- The slash line's length and width fractions `elapsed` seconds into a line of `size` (pure).
function SlashArc.linePose(size: string, elapsed: number): LinePose
	return linePoseInto(size, elapsed, { length = 1, width = 1, done = false })
end

--- Seconds a slash line of `size` lasts.
function SlashArc.lineSeconds(size: string): number
	local _, found = lineSize(size)
	return Accents.seconds(found.growFrames + found.holdFrames + found.thinFrames)
end

--- Plays the crescent through `position` in the swing plane; `size` is a key of accents.slashArc.sizes.
function SlashArc.play(position: Vector3, tangent: Vector3, normal: Vector3, token: string, size: string)
	local config = Accents.slashArc
	local name, found = arcSize(size)
	local geometry = SlashArc.geometry(position, tangent, normal, name)
	if geometry == nil then
		return
	end
	local shape = geometry :: Geometry
	local tier = Accents.tier(Quality.get())
	local arc: Arc = acquire(arcs, math.max(1, tier.arcs), newArc)
	serial += 1
	arc.serial = serial
	arc.size = name
	arc.config = found
	arc.started = deps.now()
	arc.active = true

	arc.host.CFrame = CFrame.new(position)
	local origin = arc.host.CFrame
	local n = shape.normal
	local aArm = shape.aControl - shape.a
	local mArmIn = shape.m - shape.mIn
	local mArmOut = shape.mOut - shape.m
	local bArm = shape.b - shape.bControl
	local apexAxis = unit(mArmOut) or shape.tangent
	arc.a.CFrame = origin:ToObjectSpace(attachmentFrame(shape.a, unit(aArm) or shape.outward, n))
	arc.m.CFrame = origin:ToObjectSpace(attachmentFrame(shape.m, apexAxis, n))
	arc.b.CFrame = origin:ToObjectSpace(attachmentFrame(shape.b, unit(bArm) or shape.outward, n))

	local colorToken = if Palette.tokens[token :: any] ~= nil then token else config.defaultToken
	local color = ColorSequence.new(Palette.color3(colorToken :: any))
	local segments = math.max(1, tier.arcSegments)
	local function layHalves(beams: { Beam }, width: number)
		local first, second = beams[1], beams[2]
		-- Trailing half: a point at the trailing end, widest at the apex.
		first.CurveSize0 = aArm.Magnitude
		first.CurveSize1 = mArmIn.Magnitude
		first.Width0 = 0
		first.Width1 = width
		-- Leading half: widest at the apex, a point at the leading end.
		second.CurveSize0 = mArmOut.Magnitude
		second.CurveSize1 = bArm.Magnitude
		second.Width0 = width
		second.Width1 = 0
		for _, beam in beams do
			beam.Segments = segments
			beam.Enabled = true
		end
	end
	layHalves(arc.outer, found.width)
	layHalves(arc.inner, found.width * config.innerWidthFraction)
	for _, beam in arc.outer do
		beam.Color = color
	end
	local front = -config.wipeSoftness
	arc.outerStep = -1
	arc.innerStep = -1
	setArcTransparency(arc, front, front)
	ensureLoop()
end

--- Plays the thin chromatic line along `tangent` through `position`; `size` is a key of accents.slashLine.sizes.
function SlashArc.line(position: Vector3, tangent: Vector3, size: string)
	local config = Accents.slashLine
	local t = unit(tangent)
	if t == nil then
		return
	end
	local tUnit = t :: Vector3
	local name, found = lineSize(size)
	local tier = Accents.tier(Quality.get())
	local line: Line = acquire(lines, math.max(1, tier.lines), newLine)
	serial += 1
	line.serial = serial
	line.size = name
	line.config = found
	line.started = deps.now()
	line.active = true
	line.tangent = tUnit
	line.laidLength = -1
	line.laidWidth = -1
	line.host.CFrame = CFrame.new(position)

	-- Across the screen: perpendicular to the line and to the view, so the copies split sideways.
	local viewer = Engine.viewerPosition()
	local across = if viewer ~= nil then perpendicular(position - viewer, tUnit) else nil
	local side = if across ~= nil then tUnit:Cross(across :: Vector3) else nil
	local sideUnit = (if side ~= nil then unit(side :: Vector3) else nil)
		or perpendicular(Vector3.yAxis, tUnit)
		or perpendicular(Vector3.xAxis, tUnit)
		or Vector3.zero
	table.clear(line.offsets)
	table.insert(line.offsets, Vector3.zero)
	for index in config.edgeTokens do
		local sign = config.edgeSides[index] or 1
		table.insert(line.offsets, sideUnit * (found.edgeOffset * sign))
	end

	local fades = ensureLineFades()
	for index, beam in line.beams do
		beam.Transparency = if index == 1 then fades[1] else fades[2]
		beam.Enabled = index == 1 or tier.lineEdges
	end
	layLine(line, linePoseInto(name, 0, linePoseScratch))
	ensureLoop()
end

--- Crescents showing right now.
function SlashArc.activeCount(): number
	local count = 0
	for _, arc in arcs do
		if arc.active then
			count += 1
		end
	end
	return count
end

--- Slash lines showing right now.
function SlashArc.activeLines(): number
	local count = 0
	for _, line in lines do
		if line.active then
			count += 1
		end
	end
	return count
end

--- A read-only view of every pooled crescent, in pool order (specs).
function SlashArc.arcs(): { ArcView }
	local views: { ArcView } = {}
	for _, arc in arcs do
		table.insert(views, {
			host = arc.host,
			attachments = { arc.a, arc.m, arc.b },
			outer = table.clone(arc.outer),
			inner = table.clone(arc.inner),
			size = arc.size,
			active = arc.active,
		})
	end
	return views
end

--- A read-only view of every pooled slash line, in pool order (specs).
function SlashArc.lines(): { LineView }
	local views: { LineView } = {}
	for _, line in lines do
		table.insert(views, {
			host = line.host,
			beams = table.clone(line.beams),
			starts = table.clone(line.starts),
			ends = table.clone(line.ends),
			size = line.size,
			active = line.active,
		})
	end
	return views
end

--- Advances every crescent and line to the clock's now (the step loop calls it; specs may too).
function SlashArc.step()
	step()
end

--- Replaces the clock or the frame step (specs); stops the running loop.
function SlashArc.bind(overrides: AccentStep.Overrides?)
	if stopLoop ~= nil then
		local stop = stopLoop :: () -> ()
		stopLoop = nil
		stop()
	end
	deps = AccentStep.deps(overrides)
end

--- Hides every crescent and line and stops the loop; the pools stay (specs, a place change).
function SlashArc.reset()
	for _, arc in arcs do
		hideArc(arc)
	end
	for _, line in lines do
		hideLine(line)
	end
	if stopLoop ~= nil then
		local stop = stopLoop :: () -> ()
		stopLoop = nil
		stop()
	end
end

--- Pre-builds both pools to the largest tier's caps so the first hit never allocates.
function SlashArc.start()
	local mostArcs, mostLines = 0, 0
	for _, tier in Accents.quality do
		mostArcs = math.max(mostArcs, tier.arcs)
		mostLines = math.max(mostLines, tier.lines)
	end
	while #arcs < mostArcs do
		table.insert(arcs, newArc())
	end
	while #lines < mostLines do
		table.insert(lines, newLine())
	end
	ensureWipeCache()
	ensureLineFades()
end

return SlashArc
