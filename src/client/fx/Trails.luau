--!strict
--[[
	Trails: the weapon light trail and the activation light (section 10, section 11).

	`attach(model)` finds the Weapon part (the server's WeaponBuilder names it `Weapon` with
	`TrailStart` at the guard and `TrailEnd` at the tip; placeholder enemy weapons get the
	attachments created here), finds or creates its Trail (width from the weapon data, lifetime
	0.18 s, LightEmission 1, color the weapon's trail token) and a PointLight on the blade.

	`setActive(model, on, kind)`: Art trails are full width in the Art's color; Basic trails are
	thinner and whiter; Smear is full width for the smear frames. Several kinds may be on at once
	(a Smear inside a hit window); the trail stays enabled while any is. The width follows the
	kind that is on, the color follows the swing (Art over Basic): a Basic swing's smear frames
	go full width but stay whiter, and once every kind is off the fading tail keeps the look of
	the swing that drew it (Trail.Color and WidthScale recolor the whole trail).

	A trail that lights anew is cleared first (Trail:Clear()), so it starts where its blade is: the
	engine would otherwise join where it went out to where it lights again (issue 11).

	`activationLight` turns the blade light on in the trail color and flashes the weapon white for
	three rendered frames: a Highlight of the weapon part alone (fx.activationLight.flashName),
	never the rig's outline, which would turn the whole body white like a hit (issue 5); it holds a
	slot of the Highlight budget while it shows. A cancelled Art's light fades out over
	fx.activationLight.cancelFadeSeconds (issue 13; the Heartbeat step eases it down).
	`flashWhite` is the two-frame white flash on a Switch landing or a parry.

	Budget: at most fx.quality[tier].maxTrails trails are enabled at once; when more rigs are
	swinging, the farthest from the viewer are disabled first. Trails past the tier's distance
	stay off. Every instance is reused; nothing is created per frame.

	`swingDirection(model)`: every Heartbeat the module records each tracked blade tip's
	(TrailEnd's) WorldPosition in a short ring (accents.swing.samples long; only a swinging rig,
	or an idle one within accents.swing.sampleDistance, and never a weapon that left the world; a
	rig skipped for a frame starts its ring over) and answers with
	the unit motion from the oldest of those samples to the newest, or nil when the tip moved
	less than accents.swing.minTravel (or jumped more than maxTravel: a respawn, a teleport).
	The snap: when a strike begins (an Art or Basic kind turns on: TrailOn, or a HitWindowOpen,
	which opens with the snap), the tip's chord over its first accents.swing.snapFrames (the
	smear's two snap frames, section 10 beat 3) is kept with its time: the chord from the tip's
	last sample before the strike to its first sample past those frames, so a low frame rate
	still reads the strike, not the settle. It answers for
	accents.swing.memorySeconds after it was sampled, while the trail is still on in the
	overshoot and settle and once the swing is over, so a HitConfirmed that arrives a round trip
	late still gets the swing that hit, never the settle. The last good direction sampled while a
	trail kind was on backs it up, then the tip's motion now. The slash crescent and the slash
	line read it for their tangent.

	Render stalls (D-142): RenderStepped stops while the display sleeps or the window is minimised
	and Heartbeat goes on, and a frame can be presented or captured after a stall before the first
	render step runs (D-125). A trail lit when the display went dark has nothing to put it out in
	the dark (its TrailOff is a clip event, and the local and near rigs step on the render step),
	and its blade can move meanwhile (the body or a remote's replicated root), so that frame would
	draw one streak from where the blade was to where it is. So a Heartbeat watchdog puts out every
	trail and clears it once no render step has run for longer than choreo.luau
	stall.jumpSeconds (a jump, D-132); nothing lights one until a frame renders again, and that
	render step clears each trail again before it lights what is still on, so a swing that goes
	on past the wake starts where its blade is. On a frame that does run the render step, the
	jump's TrailOff (Replication closes it) puts the trail out inside the step, before the frame
	draws. A stall shorter than a jump is a long frame and changes nothing. The render step, the
	watchdog, the clock and Trail:Clear() sit behind `bind`, so specs drive them by hand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Accents = require(Shared.data.accents)
local ChoreoData = require(Shared.data.choreo)
local Palette = require(Shared.data.palette)
local Weapons = require(Shared.data.weapons)
local Easing = require(Shared.util.Easing)
local Assets = require(Shared.data.assets)
local Engine = require(script.Parent.Engine)
local AccentStep = require(script.Parent.AccentStep)
local FrameClock = require(script.Parent.FrameClock)
local Quality = require(script.Parent.Quality)
local OutlineManager = require(script.Parent.OutlineManager)

export type Kind = "Art" | "Basic" | "Smear"

export type StepFn = (dt: number) -> ()

export type Deps = {
	now: () -> number, -- the watchdog's clock
	onRender: (fn: StepFn) -> () -> (), -- the render step (RenderStepped); returns its disconnect
	onWatch: (fn: StepFn) -> () -> (), -- Heartbeat (runs while nothing renders); returns its disconnect
	clear: (trail: Trail) -> (), -- Trail:Clear(): drops every segment drawn so far
}

export type Overrides = {
	now: (() -> number)?,
	onRender: ((fn: StepFn) -> () -> ())?,
	onWatch: ((fn: StepFn) -> () -> ())?,
	clear: ((trail: Trail) -> ())?,
}

type Entry = {
	model: Instance,
	weapon: BasePart,
	trail: Trail,
	light: PointLight,
	span: number, -- studs between the two attachments (the trail's natural width)
	baseWidth: number, -- studs the weapon data asks for
	token: string,
	color: Color3,
	active: { [string]: boolean },
	swing: Kind, -- the last swing kind on (Art or Basic): the color, and the width once nothing is on
	flashCancel: (() -> ())?,
	flashing: boolean,
	weaponFlash: Highlight?, -- the activation's flash on the weapon part alone (made on first use)
	weaponFlashCancel: (() -> ())?, -- ends the weapon flash early (a new one, detach)
	weaponFlashSlot: (() -> ())?, -- gives back the Highlight budget slot the weapon flash holds
	lightFade: number?, -- seconds into the cancelled Art's light fade; nil while none runs
	allowed: boolean, -- inside the budget and the distance
	removedCancel: () -> (), -- stops watching the rig for removal
	tip: Attachment, -- TrailEnd: the blade tip swingDirection follows
	tips: { Vector3 }, -- ring of the tip's last world positions
	tipHead: number, -- index of the newest sample in `tips`
	tipCount: number, -- samples recorded so far (at most SWING_SAMPLES)
	lastSwing: Vector3?, -- the last good direction sampled while a trail kind was on
	lastSwingAt: number, -- Engine.now() of that sample
	strikeAt: number?, -- Engine.now() when the strike began (an Art or Basic kind turned on)
	snapFrom: Vector3?, -- the tip's last sample before the strike (its first sample when none)
	snapSwing: Vector3?, -- the tip's chord since then, over the snap frames at most
	snapAt: number, -- Engine.now() of the sample that measured it
}

local KIND_PRIORITY: { Kind } = { "Art", "Smear", "Basic" }
local SWING_SAMPLES = math.max(2, Accents.swing.samples)

local Trails = {}

-- Trail:Clear() is engine-only; under Lune the call fails quietly.
local function engineClear(trail: Trail)
	pcall(function()
		trail:Clear()
	end)
end

local function defaults(overrides: Overrides?): Deps
	local deps: Deps = {
		now = Engine.now,
		onRender = AccentStep.renderStepped,
		onWatch = Engine.onHeartbeat,
		clear = engineClear,
	}
	if overrides ~= nil then
		deps.now = overrides.now or deps.now
		deps.onRender = overrides.onRender or deps.onRender
		deps.onWatch = overrides.onWatch or deps.onWatch
		deps.clear = overrides.clear or deps.clear
	end
	return deps
end

local deps: Deps = defaults(nil)
local entries: { [Instance]: Entry } = {}
local started = false
local stopLoop: (() -> ())? = nil
local stopRender: (() -> ())? = nil
local sinceRank = 0
-- When the render step last ran (deps.now); nil before the first one (and under Lune).
local renderedAt: number? = nil
-- No render step for longer than a jump: every trail is out and cleared until one runs (D-142).
local stalled = false
local endWeaponFlash: (entry: Entry) -> ()
local flashWeapon: (entry: Entry) -> ()

local function sequence(keys: { { number } }): NumberSequence
	local points = {}
	for _, key in keys do
		table.insert(points, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	return NumberSequence.new(points)
end

local function findWeaponPart(model: Instance): BasePart?
	for _, descendant in model:GetDescendants() do
		if descendant.Name == "Weapon" and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

-- The unit axis of a part's longest dimension (the blade direction on a placeholder weapon).
local function longAxis(size: Vector3): Vector3
	if size.Y >= size.X and size.Y >= size.Z then
		return Vector3.yAxis
	elseif size.Z >= size.X then
		return Vector3.zAxis
	end
	return Vector3.xAxis
end

local function ensureAttachment(weapon: BasePart, name: string, fraction: number): Attachment
	local existing = weapon:FindFirstChild(name)
	if existing ~= nil and existing:IsA("Attachment") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	local size = weapon.Size
	local axis = longAxis(size)
	local extent = axis:Dot(size)
	attachment.CFrame = CFrame.new(axis * extent * fraction)
	attachment.Parent = weapon
	return attachment
end

-- Trail color token and width: weapon part attributes, then the entity's weapon def, then defaults.
local function resolveStyle(model: Instance, weapon: BasePart): (string, number)
	local token: string? = nil
	local width: number? = nil
	local attributeToken = weapon:GetAttribute(Fx.trail.colorAttribute)
	if typeof(attributeToken) == "string" and Palette.tokens[attributeToken] ~= nil then
		token = attributeToken
	end
	local attributeWidth = weapon:GetAttribute(Fx.trail.widthAttribute)
	if typeof(attributeWidth) == "number" and attributeWidth > 0 then
		width = attributeWidth
	end
	local weaponId = model:GetAttribute("WeaponId")
	if typeof(weaponId) == "string" then
		local def = Weapons.byId(weaponId)
		if def ~= nil then
			token = token or def.trailColor
			width = width or def.trailWidth
		end
	end
	local isEnemy = model:GetAttribute("EntityKind") == "Enemy"
	if token == nil then
		token = if isEnemy then Fx.trail.enemyToken else Fx.trail.defaultToken
	end
	if width == nil then
		width = if isEnemy then Fx.trail.enemyWidth else Fx.trail.defaultWidth
	end
	return token :: string, width :: number
end

local function ensureTrail(weapon: BasePart, start: Attachment, finish: Attachment): Trail
	local existing = weapon:FindFirstChildOfClass("Trail")
	local trail = existing or Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = start
	trail.Attachment1 = finish
	trail.Lifetime = Fx.trail.lifetime
	trail.LightEmission = Fx.trail.lightEmission
	trail.MinLength = Fx.trail.minLength
	trail.Transparency = sequence(Fx.trail.transparencyKeys)
	trail.FaceCamera = true
	trail.Enabled = false
	if Assets.isReady(Fx.trail.textureAsset) then
		trail.Texture = Assets.url(Fx.trail.textureAsset)
	end
	if existing == nil then
		trail.Parent = weapon
	end
	return trail
end

local function ensureLight(weapon: BasePart): PointLight
	local existing = weapon:FindFirstChildOfClass("PointLight")
	local light = existing or Instance.new("PointLight")
	light.Name = "ActivationLight"
	light.Range = Fx.activationLight.range
	light.Brightness = Fx.activationLight.brightness
	light.Enabled = false
	if existing == nil then
		light.Parent = weapon
	end
	return light
end

local function activeKind(entry: Entry): Kind?
	for _, kind in KIND_PRIORITY do
		if entry.active[kind] then
			return kind
		end
	end
	return nil
end

local function wantsTrail(entry: Entry): boolean
	return entry.flashing or activeKind(entry) ~= nil
end

-- The swing whose look the trail wears: Art over Basic while either is on, else the last one, so
-- neither a Smear frame nor the fade after the swing changes the color.
local function swingKind(entry: Entry): Kind
	if entry.active.Art then
		return "Art"
	elseif entry.active.Basic then
		return "Basic"
	end
	return entry.swing
end

local function applyAppearance(entry: Entry)
	local swing = swingKind(entry)
	entry.swing = swing
	local kind = activeKind(entry) or swing
	local multiplier = Fx.trail.width[kind] or Fx.trail.width.Art
	local scale = if entry.span > 1e-6 then entry.baseWidth / entry.span else 1
	local widthKeys = {}
	for _, key in Fx.trail.widthKeys do
		table.insert(widthKeys, { key[1], key[2] * scale * multiplier })
	end
	entry.trail.WidthScale = sequence(widthKeys)
	local color = entry.color
	if entry.flashing then
		color = Palette.color3(Fx.trail.flashToken :: any)
	elseif swing == "Basic" then
		color = entry.color:Lerp(Palette.color3("TrailWhite"), Fx.trail.basicWhiteBlend)
	end
	entry.trail.Color = ColorSequence.new(color)
	local lit = wantsTrail(entry) and entry.allowed and not stalled
	if lit and not entry.trail.Enabled then
		-- Lit anew, it starts where its blade is now: the engine joins where a trail went out to
		-- where it lights again, which drew a streak from the last window's blade on the still
		-- frame a window opens on, and across an Art's hold between its cuts (issue 11).
		deps.clear(entry.trail)
	end
	entry.trail.Enabled = lit
end

-- Re-ranks which active trails are allowed: nearest first, inside the tier's distance, up to maxTrails.
local function rebalance()
	local params = Quality.params()
	local wanting: { { entry: Entry, distance: number } } = {}
	for _, entry in entries do
		if wantsTrail(entry) then
			local position = Engine.modelPosition(entry.model)
			local distance = if position ~= nil then Engine.distanceTo(position) else 0
			table.insert(wanting, { entry = entry, distance = distance })
		else
			entry.allowed = true
		end
	end
	table.sort(wanting, function(a, b)
		return a.distance < b.distance
	end)
	local budget = math.min(params.maxTrails, Fx.budgets.trails)
	for index, item in wanting do
		local allowed = index <= budget and item.distance <= params.trailDistance
		if allowed ~= item.entry.allowed then
			item.entry.allowed = allowed
			applyAppearance(item.entry)
		end
	end
end

-- Ends the weapon's activation flash now: the Highlight off, its budget slot given back.
endWeaponFlash = function(entry: Entry)
	local cancel = entry.weaponFlashCancel
	entry.weaponFlashCancel = nil
	if cancel ~= nil then
		cancel()
	end
	local highlight = entry.weaponFlash
	if highlight ~= nil then
		highlight.Enabled = false
	end
	local release = entry.weaponFlashSlot
	entry.weaponFlashSlot = nil
	if release ~= nil then
		release()
	end
end

-- The activation's flash: a Highlight on the weapon part alone, SystemWhite for
-- fx.activationLight.flashFrames rendered frames (section 11), holding one Highlight slot while
-- it shows. A new activation restarts it.
flashWeapon = function(entry: Entry)
	local config = Fx.activationLight
	local highlight = entry.weaponFlash
	if highlight == nil or highlight.Parent ~= entry.weapon then
		local made = Instance.new("Highlight")
		made.Name = config.flashName
		made.Adornee = entry.weapon
		made.FillColor = Palette.color3(config.flashToken :: any)
		made.FillTransparency = config.flashFillTransparency
		made.OutlineTransparency = config.flashOutlineTransparency
		made.DepthMode = (Enum.HighlightDepthMode :: any)[Fx.outline.depthMode]
		made.Enabled = false
		made.Parent = entry.weapon
		entry.weaponFlash = made
		highlight = made
	end
	endWeaponFlash(entry)
	entry.weaponFlashSlot = OutlineManager.reserve()
	local shown = highlight :: Highlight
	shown.Enabled = true
	entry.weaponFlashCancel = FrameClock.after(config.flashFrames, function()
		entry.weaponFlashCancel = nil
		endWeaponFlash(entry)
	end)
end

--- Finds (or builds) the Trail and PointLight on a rig's Weapon part; returns nil for rigs without one.
function Trails.attach(model: Instance): boolean
	if entries[model] ~= nil then
		return true
	end
	local weapon = findWeaponPart(model)
	if weapon == nil then
		return false
	end
	Trails.start()
	local start = ensureAttachment(weapon, "TrailStart", Fx.trail.placeholderStart)
	local finish = ensureAttachment(weapon, "TrailEnd", Fx.trail.placeholderEnd)
	local token, width = resolveStyle(model, weapon)
	local color = Palette.color3(token :: any)
	local entry: Entry = {
		model = model,
		weapon = weapon,
		trail = ensureTrail(weapon, start, finish),
		light = ensureLight(weapon),
		span = (start.CFrame.Position - finish.CFrame.Position).Magnitude,
		baseWidth = width,
		token = token,
		color = color,
		active = {},
		swing = "Art",
		flashCancel = nil,
		flashing = false,
		weaponFlash = nil,
		weaponFlashCancel = nil,
		weaponFlashSlot = nil,
		lightFade = nil,
		allowed = true,
		removedCancel = Engine.onRemoved(model, function()
			Trails.detach(model)
		end),
		tip = finish,
		tips = {},
		tipHead = 0,
		tipCount = 0,
		lastSwing = nil,
		lastSwingAt = 0,
		strikeAt = nil,
		snapFrom = nil,
		snapSwing = nil,
		snapAt = 0,
	}
	entry.light.Color = color
	entries[model] = entry
	applyAppearance(entry)
	return true
end

--- Forgets a rig (its instances stay on the weapon; the rig is leaving anyway). Called by the
--- shatter and when the rig leaves the world, so the entry table never grows with dead rigs.
function Trails.detach(model: Instance)
	local entry = entries[model]
	if entry == nil then
		return
	end
	if entry.flashCancel ~= nil then
		entry.flashCancel()
	end
	endWeaponFlash(entry)
	entry.lightFade = nil
	entry.removedCancel()
	entry.trail.Enabled = false
	entry.light.Enabled = false
	entry.light.Brightness = Fx.activationLight.brightness
	entries[model] = nil
end

--- Turns a trail kind on or off: Art (full width, the Art's color), Basic (thinner, whiter), Smear (full).
function Trails.setActive(model: Instance, on: boolean, kind: Kind)
	if entries[model] == nil and not Trails.attach(model) then
		return
	end
	local entry = entries[model] :: Entry
	if on and kind ~= "Smear" then
		-- A strike begins (TrailOn, or the next damage window of the same trail): its snap is new,
		-- a chord from the tip's last sample before it.
		entry.strikeAt = Engine.now()
		entry.snapFrom = if entry.tipCount > 0 then entry.tips[entry.tipHead] else nil
		entry.snapSwing = nil
	end
	entry.active[kind] = if on then true else nil
	applyAppearance(entry)
	rebalance()
end

--- The activation light on the blade (range 8, brightness 2) in the trail color, plus the
--- three-frame SystemWhite flash on the weapon's own Highlight when it turns on (the weapon part
--- alone, never the body: issue 5). `fade` (a cancelled Art) fades the light out over
--- fx.activationLight.cancelFadeSeconds instead of putting it out at once (issue 13).
function Trails.activationLight(model: Instance, on: boolean, token: string?, fade: boolean?)
	if entries[model] == nil and not Trails.attach(model) then
		return
	end
	local entry = entries[model] :: Entry
	if token ~= nil and Palette.tokens[token] ~= nil then
		entry.light.Color = Palette.color3(token :: any)
	else
		entry.light.Color = entry.color
	end
	if not on and fade == true and entry.light.Enabled then
		-- Already fading: it goes on from where it is.
		entry.lightFade = entry.lightFade or 0
		return
	end
	entry.lightFade = nil
	entry.light.Brightness = Fx.activationLight.brightness
	entry.light.Enabled = on
	if on then
		flashWeapon(entry)
	end
end

--- True while a rig's activation light is on (fading counts).
function Trails.isLit(model: Instance): boolean
	local entry = entries[model]
	return entry ~= nil and entry.light.Enabled
end

-- Steps every cancelled Art's light fade by `dt` (Heartbeat): the brightness eases down from the
-- activation's, and the light goes out at the end.
local function stepFades(dt: number)
	local length = Fx.activationLight.cancelFadeSeconds
	for _, entry in entries do
		local elapsed = entry.lightFade
		if elapsed == nil then
			continue
		end
		local t = if length > 0 then math.min(1, (elapsed + dt) / length) else 1
		-- Done within half a frame of the end, so a 60 fps clock a hair fast never adds a frame at 0.
		if elapsed + dt >= length - dt * 0.5 then
			entry.lightFade = nil
			entry.light.Enabled = false
			entry.light.Brightness = Fx.activationLight.brightness
		else
			entry.lightFade = elapsed + dt
			local eased = Easing.evaluate(Fx.activationLight.cancelFadeEasing, t)
			entry.light.Brightness = Fx.activationLight.brightness * (1 - eased)
		end
	end
end

--- Flashes the trail white and on for `frames` rendered frames (Switch landing, parry).
function Trails.flashWhite(model: Instance, frames: number)
	if entries[model] == nil and not Trails.attach(model) then
		return
	end
	local entry = entries[model] :: Entry
	if entry.flashCancel ~= nil then
		entry.flashCancel()
	end
	entry.flashing = true
	applyAppearance(entry)
	rebalance()
	entry.flashCancel = FrameClock.after(frames, function()
		entry.flashing = false
		entry.flashCancel = nil
		applyAppearance(entry)
		rebalance()
	end)
end

--- The trail color token a rig resolved to (for the activation chime); nil when unattached.
function Trails.tokenOf(model: Instance): string?
	local entry = entries[model]
	return if entry ~= nil then entry.token else nil
end

--- True when the rig's trail is currently enabled.
function Trails.isEnabled(model: Instance): boolean
	local entry = entries[model]
	return entry ~= nil and entry.trail.Enabled
end

-- The unit direction of a tip motion; nil when it barely moved or jumped (a respawn, a teleport).
local function unitMotion(motion: Vector3): Vector3?
	local travel = motion.Magnitude
	if travel <= Accents.swing.minTravel or travel > Accents.swing.maxTravel then
		return nil
	end
	return motion / travel
end

-- The unit motion of the tip over the ring; nil when unknown, still, or a jump.
local function ringDirection(entry: Entry): Vector3?
	if entry.tipCount < 2 then
		return nil
	end
	local back = entry.tipCount - 1
	local oldest = entry.tips[(entry.tipHead - 1 - back) % SWING_SAMPLES + 1]
	return unitMotion(entry.tips[entry.tipHead] - oldest)
end

local SNAP_SECONDS = Accents.swing.snapFrames * Accents.frameSeconds

-- Measures the strike's snap: the tip's chord from its last sample before the strike, until the
-- samples span the snap frames (half a frame early, so a 60 fps clock that runs a hair fast never
-- takes a third, and a slow frame that crosses them ends it).
local function measureSnap(entry: Entry, position: Vector3, at: number)
	local strikeAt = entry.strikeAt
	if strikeAt == nil or at < strikeAt then
		return
	end
	local from = entry.snapFrom
	if from == nil then
		entry.snapFrom = position
		return
	end
	local direction = unitMotion(position - from)
	if direction ~= nil then
		entry.snapSwing = direction
		entry.snapAt = at
	end
	if at - strikeAt >= SNAP_SECONDS - Accents.frameSeconds * 0.5 and entry.snapSwing ~= nil then
		entry.strikeAt = nil -- measured: the snap is over
	end
end

--- Records each tracked blade tip's world position in its ring (Heartbeat runs it; specs call
--- it), and remembers the direction of a rig that is swinging (a trail kind on). Only a rig whose
--- answer can matter is read: one swinging, or an idle one within accents.swing.sampleDistance of
--- the viewer; a weapon that left the world is never read. A rig not read this frame starts its
--- ring over, so no chord ever spans the frames it missed.
function Trails.sample()
	local at = Engine.now()
	local viewer = Engine.viewerPosition()
	local range = Accents.swing.sampleDistance
	for _, entry in entries do
		local weapon = entry.weapon
		local swinging = activeKind(entry) ~= nil
		local idleFar = not swinging and (viewer == nil or (weapon.Position - (viewer :: Vector3)).Magnitude > range)
		if weapon.Parent == nil or idleFar then
			entry.tipCount = 0
			continue
		end
		local position = entry.tip.WorldPosition
		entry.tipHead = entry.tipHead % SWING_SAMPLES + 1
		entry.tips[entry.tipHead] = position
		entry.tipCount = math.min(entry.tipCount + 1, SWING_SAMPLES)
		if swinging then
			local direction = ringDirection(entry)
			if direction ~= nil then
				entry.lastSwing = direction
				entry.lastSwingAt = at
			end
			measureSnap(entry, position, at)
		end
	end
end

--- The unit direction the blade swung: the strike's snap inside accents.swing.memorySeconds,
--- else the tip's motion while it swings, else the swing's last good direction inside that
--- window, else the tip's motion now; nil when none is known.
function Trails.swingDirection(model: Instance): Vector3?
	local entry = entries[model]
	if entry == nil then
		return nil
	end
	local now = Engine.now()
	local snap = entry.snapSwing
	if snap ~= nil and now - entry.snapAt <= Accents.swing.memorySeconds then
		return snap
	end
	local current = ringDirection(entry)
	if current ~= nil and activeKind(entry) ~= nil then
		return current
	end
	local remembered = entry.lastSwing
	if remembered ~= nil and now - entry.lastSwingAt <= Accents.swing.memorySeconds then
		return remembered
	end
	return current
end

--- Forgets every rig (a place change, specs): each one's trail and light go off, as on detach.
function Trails.reset()
	local models: { Instance } = {}
	for model in entries do
		table.insert(models, model)
	end
	for _, model in models do
		Trails.detach(model)
	end
end

-- The watchdog (Heartbeat): once no render step has run for longer than a jump, every trail
-- goes out and drops what it drew, before any frame can show it (D-142).
local function watchStall()
	local at = renderedAt
	if stalled or at == nil or deps.now() - at <= ChoreoData.stall.jumpSeconds then
		return
	end
	stalled = true
	for _, entry in entries do
		entry.trail.Enabled = false
		deps.clear(entry.trail)
	end
end

-- The render step: remembers when it ran; the first one after a stall clears each trail again
-- and lights what is still on, from where its blade is now (a trail that lights is cleared as it
-- lights; one that stays out is cleared here).
local function rendered()
	renderedAt = deps.now()
	if not stalled then
		return
	end
	stalled = false
	for _, entry in entries do
		applyAppearance(entry)
		if not entry.trail.Enabled then
			deps.clear(entry.trail)
		end
	end
end

local function connectLoops()
	stopLoop = deps.onWatch(function(dt: number)
		watchStall()
		stepFades(dt)
		Trails.sample()
		sinceRank += dt
		if sinceRank >= Fx.trail.rankInterval then
			sinceRank = 0
			rebalance()
		end
	end)
	stopRender = deps.onRender(function()
		rendered()
	end)
end

local function disconnectLoops()
	local stopWatch, stopStep = stopLoop, stopRender
	stopLoop, stopRender = nil, nil
	if stopWatch ~= nil then
		stopWatch()
	end
	if stopStep ~= nil then
		stopStep()
	end
end

--- Starts the periodic budget re-rank (rigs move), the render-stall watchdog and its render step,
--- and follows quality changes.
function Trails.start()
	if started then
		return
	end
	started = true
	Quality.changed:Connect(function()
		rebalance()
	end)
	connectLoops()
end

--- Replaces the watchdog's clock, the render step, Heartbeat or Trail:Clear() (specs); nil
--- restores the engine. Forgets when the last frame rendered (that time was on the old clock), so
--- no stall is called until a render step runs, and lights again what a stall had put out.
function Trails.bind(overrides: Overrides?)
	disconnectLoops()
	deps = defaults(overrides)
	renderedAt = nil
	if stalled then
		stalled = false
		for _, entry in entries do
			applyAppearance(entry)
		end
	end
	if started then
		connectLoops()
	end
end

return Trails
