--!strict
--[[
	TrailRibbon: the weapon trail drawn from sub-frame blade samples (D-261, review issue 8).

	The engine Trail takes one sample a rendered frame, so a cut that sweeps most of its arc
	between two frames drew a straight chord or a slab. Trails solves the blade at sub-steps
	between the frames it renders (BladeContact.blade) and pushes each one here: a sample is the
	guard and the tip in world space and the ribbon-clock time it stands for. A ribbon draws the
	samples younger than fx.luau trail.lifetime as one chain of camera-facing Beams per layer
	(fx.luau trail.ribbon.layers: the colored body through the blade's middle, a narrow glowing core
	near the tip), each Beam joining two neighbouring samples, its widths keyed by each end's age
	(trail.widthKeys, head to tail) and its transparency by the pair's mean age (the layer's keys,
	snapped to trail.ribbon.transparencySteps prebuilt sequences, so a frame builds none).

	Samples sit in a ring of trail.ribbon.maxSamples slots; Beam k always joins slot k to the next
	slot, so nothing is re-wired: a Beam shows only while both its slots hold live samples and the
	later one is joined to it. `push(..., joined = false)` starts a new stroke (a new swing): the
	last swing's tail fades where it is, never joined to the new one (issue 11's streak).

	Every Instance is made once per ribbon and reused; Trails keeps a pool of ribbons. Attachments
	are laid by Position on an anchored host with no turn (moved only while the ribbon is empty), so
	a frame builds no CFrame. Pure apart from the Instances it owns: the clock is the caller's.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Palette = require(Shared.data.palette)

export type Layer = typeof(Fx.trail.ribbon.layers[1])

export type Style = {
	color: Color3, -- the trail color before the ribbon saturates it
	whiteBlend: number, -- how far the saturated color then moves toward TrailWhite (a Basic swing)
	width: number, -- studs: the body's width at the head (weapon trailWidth x kind width x thickness)
	lifetime: number, -- seconds a sample lives
}

--- What a spec reads of a ribbon: the live samples' layer points (oldest first) and the Beams on.
export type View = {
	count: number,
	points: { { Vector3 } }, -- per layer, the live samples' points in world space, oldest first
	beams: { { Beam } }, -- per layer, the Beams showing, oldest first
	host: BasePart,
}

export type Ribbon = {
	host: BasePart,
	attachments: { { Attachment } }, -- [layer][slot]
	beams: { { Beam } }, -- [layer][slot]: slot -> next slot
	guard: { Vector3 },
	tip: { Vector3 },
	born: { number },
	joined: { boolean }, -- the slot's sample continues the stroke of the slot before it
	shown: { boolean }, -- the slot's Beams are on
	fade: { { number } }, -- [layer][slot]: the transparency step the Beam wears (-1 before any)
	head: number, -- the newest slot (0 before the first sample)
	count: number, -- live samples
	last: Vector3?, -- the newest tip pushed (minLength skip)
	color: Color3?, -- the style color the Beams wear now
	whiteBlend: number, -- and the style's white blend
}

local RIBBON = Fx.trail.ribbon
local SLOTS = math.max(2, RIBBON.maxSamples)
local STEPS = math.max(1, RIBBON.transparencySteps)

local TrailRibbon = {}

local folder: Instance? = nil
-- [step + 1]: a constant Transparency sequence, built once.
local fades: { NumberSequence } = {}

-- The step a transparency snaps to (0..STEPS).
local function fadeStep(value: number): number
	return math.clamp(math.floor(value * STEPS + 0.5), 0, STEPS)
end

local function fadeAt(step: number): NumberSequence
	local cached: NumberSequence? = fades[step + 1]
	if cached ~= nil then
		return cached
	end
	local made = NumberSequence.new(step / STEPS)
	fades[step + 1] = made
	return made
end

--- A piecewise-linear key table ({ {time, value} }, times 0..1 ascending) at `t`.
function TrailRibbon.evaluate(keys: { { number } }, t: number): number
	local count = #keys
	if count == 0 then
		return 0
	end
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for index = 2, count do
		local key = keys[index]
		if t <= key[1] then
			local before = keys[index - 1]
			local span = key[1] - before[1]
			local alpha = if span > 0 then (t - before[1]) / span else 1
			return before[2] + (key[2] - before[2]) * alpha
		end
	end
	return keys[count][2]
end

--- The ribbon's color for a trail color: its HSV saturation times trail.ribbon.saturation (at
--- most 1), hue and value kept.
function TrailRibbon.saturate(color: Color3): Color3
	local hue, saturation, value = color:ToHSV()
	return Color3.fromHSV(hue, math.min(1, saturation * RIBBON.saturation), value)
end

--- A layer's color for a trail color: saturated, lerped toward TrailWhite by `whiteBlend` (a Basic
--- swing's whiter look, 0 when nil), then toward SystemWhite by the layer's whiteBlend.
function TrailRibbon.layerColor(color: Color3, layer: Layer, whiteBlend: number?): Color3
	local swing = TrailRibbon.saturate(color):Lerp(Palette.color3("TrailWhite"), whiteBlend or 0)
	return swing:Lerp(Palette.color3("SystemWhite"), layer.whiteBlend)
end

local function ensureFolder(): Instance
	local current = folder
	if current == nil or current.Parent == nil then
		local made = Instance.new("Folder")
		made.Name = RIBBON.folderName
		pcall(function()
			made.Parent = workspace
		end)
		folder = made
		current = made
	end
	return current :: Instance
end

--- A ribbon with every Instance it will use, all off.
function TrailRibbon.new(): Ribbon
	local host = Instance.new("Part")
	host.Name = "TrailRibbon"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Transparency = 1
	host.Size = Vector3.one * RIBBON.hostSize
	host.Parent = ensureFolder()
	local attachments: { { Attachment } } = {}
	local beams: { { Beam } } = {}
	local fade: { { number } } = {}
	for layerIndex, layer in RIBBON.layers do
		fade[layerIndex] = table.create(SLOTS, -1)
		local points: { Attachment } = {}
		for slot = 1, SLOTS do
			local attachment = Instance.new("Attachment")
			attachment.Name = layer.name .. slot
			attachment.Parent = host
			points[slot] = attachment
		end
		local chain: { Beam } = {}
		for slot = 1, SLOTS do
			local beam = Instance.new("Beam")
			beam.Name = layer.name .. slot
			beam.Attachment0 = points[slot]
			beam.Attachment1 = points[slot % SLOTS + 1]
			beam.FaceCamera = true
			beam.Segments = 1
			beam.CurveSize0 = 0
			beam.CurveSize1 = 0
			beam.Texture = ""
			beam.LightInfluence = 0
			beam.LightEmission = layer.lightEmission
			beam.ZOffset = layer.zOffset
			beam.Enabled = false
			beam.Parent = host
			chain[slot] = beam
		end
		attachments[layerIndex] = points
		beams[layerIndex] = chain
	end
	return {
		host = host,
		attachments = attachments,
		beams = beams,
		guard = table.create(SLOTS, Vector3.zero),
		tip = table.create(SLOTS, Vector3.zero),
		born = table.create(SLOTS, 0),
		joined = table.create(SLOTS, false),
		shown = table.create(SLOTS, false),
		fade = fade,
		head = 0,
		count = 0,
		last = nil,
		color = nil,
		whiteBlend = 0,
	}
end

local function hide(ribbon: Ribbon, slot: number)
	if not ribbon.shown[slot] then
		return
	end
	ribbon.shown[slot] = false
	for _, chain in ribbon.beams do
		chain[slot].Enabled = false
	end
end

--- Drops every sample and turns every Beam off.
function TrailRibbon.clear(ribbon: Ribbon)
	for slot = 1, SLOTS do
		hide(ribbon, slot)
	end
	ribbon.head = 0
	ribbon.count = 0
	ribbon.last = nil
end

--- True while the ribbon still has samples to draw.
function TrailRibbon.live(ribbon: Ribbon): boolean
	return ribbon.count > 0
end

--- Adds a sample: the blade's guard and tip in world space and the ribbon-clock time it stands
--- for. `joined` false starts a new stroke. A tip that moved less than trail.minLength since the
--- last sample of the same stroke adds nothing (a held blade fills no slots). Returns true when
--- the sample was kept.
function TrailRibbon.push(ribbon: Ribbon, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
	local last = ribbon.last
	if joined and last ~= nil and ribbon.count > 0 and (tip - last).Magnitude < Fx.trail.minLength then
		return false
	end
	local slot = ribbon.head % SLOTS + 1
	-- The slot it reuses was the oldest: its Beam (to the slot after) goes with it.
	hide(ribbon, slot)
	if ribbon.count == 0 then
		-- Nothing live is laid from the old place: the host moves to where the ribbon draws now.
		ribbon.host.Position = guard
	end
	local origin = ribbon.host.Position
	ribbon.head = slot
	ribbon.count = math.min(ribbon.count + 1, SLOTS)
	ribbon.guard[slot] = guard
	ribbon.tip[slot] = tip
	ribbon.born[slot] = born
	ribbon.joined[slot] = joined and ribbon.count > 1
	ribbon.last = tip
	for layerIndex, layer in RIBBON.layers do
		ribbon.attachments[layerIndex][slot].Position = guard:Lerp(tip, layer.fraction) - origin
	end
	return true
end

local function recolor(ribbon: Ribbon, color: Color3, whiteBlend: number)
	if ribbon.color == color and ribbon.whiteBlend == whiteBlend then
		return
	end
	ribbon.color = color
	ribbon.whiteBlend = whiteBlend
	for layerIndex, layer in RIBBON.layers do
		local sequence = ColorSequence.new(TrailRibbon.layerColor(color, layer, whiteBlend))
		for _, beam in ribbon.beams[layerIndex] do
			beam.Color = sequence
		end
	end
end

--- Lays the Beams for ribbon-clock time `clock`: samples older than the style's lifetime go, and
--- every Beam between two live, joined samples shows with its widths and transparency by age.
function TrailRibbon.draw(ribbon: Ribbon, clock: number, style: Style)
	local lifetime = math.max(1e-6, style.lifetime)
	-- The oldest live samples that have aged out go first.
	while ribbon.count > 0 do
		local oldest = (ribbon.head - ribbon.count) % SLOTS + 1
		if clock - ribbon.born[oldest] < lifetime then
			break
		end
		hide(ribbon, oldest)
		ribbon.count -= 1
	end
	if ribbon.count == 0 then
		ribbon.last = nil
		return
	end
	recolor(ribbon, style.color, style.whiteBlend)
	local widthKeys = Fx.trail.widthKeys
	for back = ribbon.count - 1, 1, -1 do
		local slot = (ribbon.head - 1 - back) % SLOTS + 1 -- the older end
		local nextSlot = slot % SLOTS + 1
		if not ribbon.joined[nextSlot] then
			hide(ribbon, slot)
			continue
		end
		local ageA = math.clamp((clock - ribbon.born[slot]) / lifetime, 0, 1)
		local ageB = math.clamp((clock - ribbon.born[nextSlot]) / lifetime, 0, 1)
		local widthA = style.width * TrailRibbon.evaluate(widthKeys, ageA)
		local widthB = style.width * TrailRibbon.evaluate(widthKeys, ageB)
		local mean = (ageA + ageB) * 0.5
		for layerIndex, layer in RIBBON.layers do
			local beam = ribbon.beams[layerIndex][slot]
			beam.Width0 = widthA * layer.width
			beam.Width1 = widthB * layer.width
			-- Written only when the snapped step or the shown state changes: a frame writes the
			-- two widths of each Beam and little else.
			local step = fadeStep(TrailRibbon.evaluate(layer.transparencyKeys, mean))
			local layerFade = ribbon.fade[layerIndex]
			if layerFade[slot] ~= step then
				layerFade[slot] = step
				beam.Transparency = fadeAt(step)
			end
			if not ribbon.shown[slot] then
				beam.Enabled = true
			end
		end
		ribbon.shown[slot] = true
	end
	-- The newest slot's Beam would join it to the oldest: never shown.
	hide(ribbon, ribbon.head)
end

--- The live samples and the Beams showing (specs).
function TrailRibbon.view(ribbon: Ribbon): View
	local points: { { Vector3 } } = {}
	local beams: { { Beam } } = {}
	local origin = ribbon.host.Position
	for layerIndex in RIBBON.layers do
		local layerPoints: { Vector3 } = {}
		local layerBeams: { Beam } = {}
		for back = ribbon.count - 1, 0, -1 do
			local slot = (ribbon.head - 1 - back) % SLOTS + 1
			table.insert(layerPoints, origin + ribbon.attachments[layerIndex][slot].Position)
			local beam = ribbon.beams[layerIndex][slot]
			if beam.Enabled then
				table.insert(layerBeams, beam)
			end
		end
		points[layerIndex] = layerPoints
		beams[layerIndex] = layerBeams
	end
	return { count = ribbon.count, points = points, beams = beams, host = ribbon.host }
end

--- Destroys a ribbon's Instances (a place change).
function TrailRibbon.destroy(ribbon: Ribbon)
	ribbon.host:Destroy()
end

return TrailRibbon
