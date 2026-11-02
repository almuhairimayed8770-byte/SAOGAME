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

	The ribbon (D-261, review issue 8): the engine Trail takes one sample a rendered frame, so a cut
	that sweeps most of its arc between two frames drew its chord. A rig with a blade chain (a root
	part and joints out to the Weapon: BladeContact.chain, as ContactPredictor reads it) draws its
	trail as a TrailRibbon instead and its engine Trail stays off. Each render step reads the
	chain's pose and, while the trail is on, solves the blade (BladeContact.blade) at sub-steps
	between the last frame's pose and this one (fx.luau trail.ribbon.maxStep, at most maxSubsteps),
	so the cut draws its arc. Where the clip that lit the trail is known (the rig's Choreo animator
	plays it: the handle whose clock crossed the TrailOn, HitWindowOpen or SmearOn), each sub-step
	poses the blade from that clip at its own clock between the two frames (D-269 amended): the
	clip's pose at that time, with what the frames show on top of the clip (a blend, a procedural
	layer) carried across the frame, the clip's share by its shown weight (Mixer.preview). A trail
	that lights starts a new stroke at the clip time the window opened, never joined to the last
	stroke's tail: the frame before shows the wind-up, which points back along the cut, and the
	window opens between it and this frame. With no such clip (a flash, a rig no animator plays),
	the sub-steps interpolate the two frames' poses and a stroke starts from the frame before. A
	stroke ends on the frame that shows the clip at its strike snap's landing (the stroke's end
	pose, ClipSampler.strikeLandingAt): the hold and the settle after it draw no new segment, with
	or without a hit's freeze (D-539). A clip the network catch-up started late (`lateStroke`,
	D-538) has no frame of its own before its first step: a stroke its first step lights (the window
	Replication lit for it, or one that step opens) is back-filled on the clip's own blade from its
	window's open up to the clock that step reached, each sample aged as if drawn at its own clip
	time, never from the pose before the jump (D-550); it draws that blade at full weight until
	the clip has faded in, waits while a freeze holds the clip where it came in, and draws nothing
	at or past its end pose, so a window whose snap landed before the start stays dark. The
	ribbon's ages stand still while the rig is drawn held (Choreo heldShown, D-353: the frames the
	screen shows its blade frozen, a frame behind the hold's flag), and such a frame lays no sample:
	its pose is the one the frame before drew, and a body that moves under it (a watcher's copy
	whose replicated root goes on, D-556) is no part of the cut. The chain is read again when the
	Weapon's joint changes (WeaponMount moves the sword between the hand and the back), and that
	jump is never a cut. A rig with no chain (a placeholder weapon) keeps the engine Trail.

	`activationLight` turns the blade light on in the trail color and flashes the weapon white for
	three rendered frames: a Highlight of the weapon part alone (fx.activationLight.flashName),
	never the rig's outline, which would turn the whole body white like a hit (issue 5); it holds a
	slot of the Highlight budget while it shows. The blade glows with it (F13, D-263): unlit
	camera-facing bands from the guard to the tip in the light's color at the ribbon's saturation
	(fx.activationLight.glow), so the activation reads on a thin blade in daylight, from the
	activation to the first damage frame. A light put out while the ribbon it lit has laid no
	segment of its stroke yet stays on until the frame that lays one (D-558), so no frame draws
	the lit blade with neither its light nor its trail. A cancelled Art's light and glow fade out over
	fx.activationLight.cancelFadeSeconds (issue 13; the Heartbeat step eases them down).
	`flashWhite` is the two-frame white flash on a Switch landing or a parry.

	Budget: at most fx.quality[tier].maxTrails trails are enabled at once; when more rigs are
	swinging, the farthest from the viewer are disabled first. Trails past the tier's distance
	stay off. Every instance is reused; nothing is created per frame.

	`swingDirection(model)`: every rendered frame the module records each tracked blade tip's
	(TrailEnd's) WorldPosition in a short ring (accents.swing.samples long; only a swinging rig,
	or an idle one within accents.swing.sampleDistance, and never a weapon that left the world; a
	rig skipped for a frame starts its ring over). It reads the tip where that frame draws it: the
	sample runs in the pose readers' render step (fx.luau renderOrder.poseReaders, D-211), after
	Choreo's rigs and the local character's step have posed and moved every body and before the
	draw, never on Heartbeat, where a remote's root has already moved on under last frame's pose.
	It answers with the unit motion from the oldest of those samples to the newest, or nil when
	the tip moved less than accents.swing.minTravel (or jumped more than maxTravel: a respawn, a
	teleport). A sword WeaponMount moved between the back and the hand since the last sample (its
	Weapon joint's Part0 changed) starts the ring over: that move is never a swing (D-473).
	The snap: when a strike begins (an Art or Basic kind turns on: TrailOn, or a HitWindowOpen,
	which opens with the snap), the tip's chord over its first accents.swing.snapFrames (the
	smear's two snap frames, section 10 beat 3) is kept with its time: the chord from the tip's
	last sample before the strike to its first sample past those frames, so a low frame rate
	still reads the strike, not the settle. A strike whose first frame also pulls the sword from
	its sheath (an opener caught up past its TrailOn's frame) measures from its first sample in
	the hand (D-473), as does one a late start's first step lights (D-538), over the snap frames
	from that sample. It answers for
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
	draws. A stall shorter than a jump is a long frame and changes nothing. Nothing is sampled while
	no frame renders, and no chord spans the gap: a rig's first sample more than a jump after its
	last starts its ring over, and a strike begun before the gap loses its snap (one begun on the
	wake frame measures its snap from that frame's sample). The render step, the watchdog, the
	clock and Trail:Clear() sit behind `bind`, so specs drive them by hand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Accents = require(Shared.data.accents)
local ChoreoData = require(Shared.data.choreo)
local Palette = require(Shared.data.palette)
local Weapons = require(Shared.data.weapons)
local WeaponModels = require(Shared.data.weaponModels)
local Easing = require(Shared.util.Easing)
local Assets = require(Shared.data.assets)
local BladeContact = require(Shared.choreo.BladeContact)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Joints = require(Shared.choreo.Joints)
local Engine = require(script.Parent.Engine)
local TrailRibbon = require(script.Parent.TrailRibbon)
local FrameClock = require(script.Parent.FrameClock)
local FrameOrder = require(script.Parent.FrameOrder)
local Quality = require(script.Parent.Quality)
local OutlineManager = require(script.Parent.OutlineManager)

export type Kind = "Art" | "Basic" | "Smear"

export type StepFn = (dt: number) -> ()

export type Deps = {
	now: () -> number, -- the watchdog's clock
	onRender: (fn: StepFn) -> () -> (), -- the pose readers' render step (FrameOrder); returns its leave
	onWatch: (fn: StepFn) -> () -> (), -- Heartbeat (runs while nothing renders); returns its disconnect
	clear: (trail: Trail) -> (), -- Trail:Clear(): drops every segment drawn so far
	held: (model: Instance) -> boolean, -- the rig is drawn held this frame (the ribbon's ages hold)
	-- The rig's Choreo animator (its `mixer` plays the clip that lights the trail), nil for none.
	animator: (model: Instance) -> any,
	-- The drawn pose's render step at a frame's start (FrameOrder at fx.luau renderOrder.drawnPose,
	-- D-479); returns its leave, or nil where there is no render step (Lune): the ribbon then reads
	-- the pose in the pose readers' step.
	onDrawn: (fn: StepFn) -> (() -> ())?,
}

export type Overrides = {
	now: (() -> number)?,
	onRender: ((fn: StepFn) -> () -> ())?,
	onWatch: ((fn: StepFn) -> () -> ())?,
	clear: ((trail: Trail) -> ())?,
	held: ((model: Instance) -> boolean)?,
	animator: ((model: Instance) -> any)?,
	onDrawn: ((fn: StepFn) -> (() -> ())?)?,
}

-- What a rig's chain and clips were at a frame's start (D-479): the pose that frame draws (its
-- rigs' step of the frame before wrote it, D-342) and the clip state of that step. Reused.
type Drawn = {
	at: number, -- the frame start (drawnFrame) that read it; 0 for none
	chain: BladeContact.Chain?, -- the chain it was read on
	pose: BladeContact.Pose, -- the chain's Transforms then (its root is read where the frame draws it)
	light: any, -- the handle whose clip lit a stroke in that step (lighting), nil for none
	mixer: any, -- its mixer
	opened: number?, -- the clip time the window opened at
	from: number, -- the handle's clock over that step
	to: number,
	lightWeight: number, -- its shown weight then
	source: any, -- the stroke's clip then (Entry.source)
	sourceTime: number, -- its clock then
	sourceDone: boolean,
	sourceWeight: number,
	late: boolean, -- `light` is a late start's clip on its first step (lateFirst, D-538)
	pending: boolean, -- a late start's clip whose first step left it where it came in (latePending)
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
	glow: { Beam }?, -- the activation's glow along the blade, per fx.activationLight.glow layer
	allowed: boolean, -- inside the budget and the distance
	removedCancel: () -> (), -- stops watching the rig for removal
	tip: Attachment, -- TrailEnd: the blade tip swingDirection follows
	tips: { Vector3 }, -- ring of the tip's last world positions
	tipHead: number, -- index of the newest sample in `tips`
	tipCount: number, -- samples recorded so far (at most SWING_SAMPLES)
	sampledAt: number, -- Engine.now() of the newest sample
	mount: Joints.Joint?, -- the joint that places the blade (WeaponBuilder's Weapon motor); nil: none
	mountPart0: BasePart?, -- its Part0 at the newest sample (the hand, or the back mount)
	lastSwing: Vector3?, -- the last good direction sampled while a trail kind was on
	lastSwingAt: number, -- Engine.now() of that sample
	strikeAt: number?, -- Engine.now() when the strike began (an Art or Basic kind turned on)
	snapFrom: Vector3?, -- the tip's last sample before the strike (its first sample when none)
	snapLate: boolean, -- a late start's strike (D-538): its snap's clock starts at its first sample
	snapSwing: Vector3?, -- the tip's chord since then, over the snap frames at most
	snapAt: number, -- Engine.now() of the sample that measured it
	lit: boolean, -- the trail is on (the engine Trail or the ribbon draws it)
	chain: BladeContact.Chain?, -- the blade chain the ribbon solves; nil keeps the engine Trail
	chainTried: boolean, -- a chain was looked for since the last swing began
	chainPart0: BasePart?, -- the Weapon joint's Part0 when the chain was read
	pose: BladeContact.Pose, -- this frame's chain pose
	lastPose: BladeContact.Pose, -- the frame before's (the two tables swap)
	hasPose: boolean, -- `pose` holds a frame read at poseAt
	poseAt: number, -- Engine.now() of that frame
	guardAt: Vector3, -- the blade at `pose`
	tipAt: Vector3,
	stroke: boolean, -- the ribbon's newest sample continues a stroke that is still drawing
	cutSourced: boolean, -- the stroke started at its clip's open (D-273), so it may end on a turn back
	-- The tip of the stroke's newest kept sample, or of the last frame drawn held since (the body
	-- that moved under a held pose is no part of the cut, D-556).
	cutTip: Vector3,
	cutWay: Vector3?, -- the unit way the tip went to reach it; nil before the stroke has moved
	cutSwept: number, -- studs the stroke's tip has swept
	cutDone: boolean, -- the tip turned back: the window draws nothing more (D-335)
	drew: boolean, -- the stroke has laid a segment since it began (a sample joined to the one before)
	-- The clip time the stroke's strike snap lands on (its end pose, ClipSampler.strikeLandingAt):
	-- once the frame shows the clip there or past it, the window draws nothing more (D-539).
	cutEnd: number?,
	-- A clip that came in late (Trails.lateStroke, D-538) and the clock it came in at: while its
	-- last step is its first, the frame before shows another clip's pose.
	late: any,
	lateFrom: number,
	-- The stroke draws its clip's own blade at full weight (a late start's, back-filled from its
	-- window's open, D-550), until the clip has faded in over both frames.
	lateFull: boolean,
	source: any, -- the Mixer handle whose clip lit the stroke (its sub-steps sample it); nil: none
	sourceMixer: any, -- the mixer that plays it
	sourceTime: number, -- its clock at `pose`
	fromTime: number, -- its clock at `lastPose`
	sourceWeight: number, -- its share of the limbs this frame (0..1)
	lastWeight: number, -- and at `lastPose`
	sourceOffsets: ClipSampler.Offsets?, -- its clip sampled at sourceTime
	lastOffsets: ClipSampler.Offsets?, -- its clip at the clock `lastPose` showed
	linkNames: { string }, -- each chain link's joint name (the clip's keys), read with the chain
	residuals: { CFrame? }, -- per link, what `lastPose` shows on top of the clip (nil: no key)
	nextResiduals: { CFrame? }, -- the same at `pose`
	between: BladeContact.Pose, -- the in-between pose a sub-step solves (reused)
	ribbon: TrailRibbon.Ribbon?, -- while one draws or fades
	ribbonClock: number, -- seconds the ribbon has aged (stands still in hit-stop)
	ribbonAt: number, -- Engine.now() the clock last moved at
	style: TrailRibbon.Style, -- reused frame to frame
	drawn: Drawn, -- the chain and its clips at this frame's start (D-479)
	-- Counts the activation light's changes made at once (D-479): one asked for the frame that
	-- draws a step's pose carries the count it saw and is dropped once another change came first.
	lightSerial: number,
	-- The light was put out while the lit ribbon had not yet laid its stroke's first segment: it
	-- stays on until the frame that does (D-558).
	lightOut: boolean,
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

-- The pose readers' render step (FrameOrder.POSE_READERS at fx.luau renderOrder.poseReaders):
-- after every step that poses or moves a body, before the draw. A no-op leave under Lune.
local function poseReaders(fn: StepFn): () -> ()
	return FrameOrder.join(FrameOrder.POSE_READERS, Fx.renderOrder.poseReaders, fn) or function() end
end

-- The drawn pose's render step (FrameOrder.DRAWN_POSE at fx.luau renderOrder.drawnPose, D-479):
-- a frame's start, before any rig steps. Nil under Lune (no render step).
local function drawnPoseStep(fn: StepFn): (() -> ())?
	return FrameOrder.join(FrameOrder.DRAWN_POSE, Fx.renderOrder.drawnPose, fn)
end

-- Choreo, found on first use (it never requires this module; nil where it cannot load).
local choreoModule: any = nil
local choreoTried = false

-- The rig's Choreo animator, nil when none plays it.
local function choreoAnimator(model: Instance): any
	if not choreoTried then
		choreoTried = true
		local ok, loaded = pcall(function(): any
			return require(script.Parent.Parent.choreo.Choreo) :: any
		end)
		choreoModule = if ok then loaded else nil
	end
	local module = choreoModule
	if module == nil or not model:IsA("Model") then
		return nil
	end
	return module.find(model)
end

-- The rig's hold as this frame draws it (Choreo's heldShown, D-353): the ribbon's ages stand
-- still on the frames that show the blade frozen, from the first still frame to the last, not on
-- the frames the hold's flag is up (isPaused rises on the contact's step, a frame early). An
-- animator that cannot say keeps isPaused.
local function choreoHeld(model: Instance): boolean
	local animator = choreoAnimator(model)
	if animator == nil then
		return false
	end
	local shown = (animator :: any).heldShown
	if typeof(shown) == "function" then
		return shown(animator) == true
	end
	return animator:isPaused()
end

local function defaults(overrides: Overrides?): Deps
	local deps: Deps = {
		now = Engine.now,
		onRender = poseReaders,
		onWatch = Engine.onHeartbeat,
		clear = engineClear,
		held = choreoHeld,
		animator = choreoAnimator,
		onDrawn = drawnPoseStep,
	}
	if overrides ~= nil then
		deps.now = overrides.now or deps.now
		deps.onRender = overrides.onRender or deps.onRender
		deps.onWatch = overrides.onWatch or deps.onWatch
		deps.clear = overrides.clear or deps.clear
		deps.held = overrides.held or deps.held
		deps.animator = overrides.animator or deps.animator
		deps.onDrawn = overrides.onDrawn or deps.onDrawn
	end
	return deps
end

local deps: Deps = defaults(nil)
local entries: { [Instance]: Entry } = {}
local started = false
local stopLoop: (() -> ())? = nil
local stopRender: (() -> ())? = nil
local stopDrawn: (() -> ())? = nil
-- Frame starts the drawn pose's step has run (D-479); never reset, so a reading from before a
-- bind never passes for this frame's.
local drawnFrame = 0
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

-- Ribbons no rig draws now, kept to be reused (every Instance is made once).
local ribbonPool: { TrailRibbon.Ribbon } = {}

local function acquireRibbon(entry: Entry): TrailRibbon.Ribbon
	local ribbon = entry.ribbon
	if ribbon == nil then
		local taken = table.remove(ribbonPool) or TrailRibbon.new()
		-- The host names the rig it draws now, so a per-frame log can tell whose ribbon is lit
		-- (D-362): every host sits in the one folder under the same name.
		taken.host:SetAttribute(Fx.trail.ribbon.ownerAttribute, entry.model:GetFullName())
		-- And whether its window is lit, so the log times the close's fade from it (D-498).
		taken.host:SetAttribute(Fx.trail.ribbon.litAttribute, entry.lit)
		entry.ribbon = taken
		ribbon = taken
	end
	return ribbon :: TrailRibbon.Ribbon
end

local function releaseRibbon(entry: Entry)
	local ribbon = entry.ribbon
	if ribbon == nil then
		return
	end
	entry.ribbon = nil
	TrailRibbon.clear(ribbon)
	ribbon.host:SetAttribute(Fx.trail.ribbon.ownerAttribute, nil)
	ribbon.host:SetAttribute(Fx.trail.ribbon.litAttribute, nil)
	table.insert(ribbonPool, ribbon)
end

-- The chain still stands as it was read: its root in the world, and the Weapon's own joint (the
-- last link) on the Part0 and C0 it had (WeaponMount moves both between the hand and the back).
local function chainHolds(entry: Entry, chain: BladeContact.Chain): boolean
	if chain.root.Parent == nil then
		return false
	end
	local last = chain.links[#chain.links]
	if last == nil then
		return true
	end
	local part0 = Joints.parts(last.joint)
	local c0 = Joints.frames(last.joint)
	return part0 == entry.chainPart0 and c0 == last.c0
end

-- The rig's blade chain: read again when it no longer stands; a rig that had none is looked at
-- once a swing (`retry` on a swing's start).
local function chainOf(entry: Entry, retry: boolean): BladeContact.Chain?
	local chain = entry.chain
	local stale = chain ~= nil and not chainHolds(entry, chain)
	if stale then
		chain = nil
		entry.chain = nil
		-- The pose was the old chain's: the next sample starts a new stroke.
		entry.hasPose = false
		entry.stroke = false
	end
	if chain == nil and (stale or retry or not entry.chainTried) then
		entry.chainTried = true
		local model = entry.model
		chain = if model:IsA("Model") then BladeContact.chain(model) else nil
		entry.chain = chain
		table.clear(entry.linkNames)
		if chain ~= nil then
			local last = chain.links[#chain.links]
			entry.chainPart0 = if last ~= nil then (Joints.parts(last.joint)) else nil
			for index, link in chain.links do
				entry.linkNames[index] = (link.joint :: any).Name
			end
		end
	end
	return chain
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
	-- A rig with a blade chain draws the ribbon; its engine Trail stays off.
	local engine = lit and entry.chain == nil
	if engine and not entry.trail.Enabled then
		-- Lit anew, it starts where its blade is now: the engine joins where a trail went out to
		-- where it lights again, which drew a streak from the last window's blade on the still
		-- frame a window opens on, and across an Art's hold between its cuts (issue 11).
		deps.clear(entry.trail)
	end
	entry.trail.Enabled = engine
	if not lit then
		-- The ribbon's next light starts a new stroke: never joined to this one's tail (issue 11).
		entry.stroke = false
		local ribbon = entry.ribbon
		if entry.lit and ribbon ~= nil then
			-- The window went out: its arc fades out within trail.ribbon.closeSeconds of the last
			-- frame it drew, so the gap before the next window shows nothing of it (D-360).
			TrailRibbon.close(ribbon, entry.ribbonClock)
		end
	end
	local drawing = entry.ribbon
	if drawing ~= nil and entry.lit ~= lit then
		-- The window's open or close, on the host a log reads (D-498).
		drawing.host:SetAttribute(Fx.trail.ribbon.litAttribute, lit)
	end
	entry.lit = lit
	-- The ribbon's look: the same swing color (saturated; a Basic swing's white blend after), the
	-- same width rule times the ribbon's thickness.
	local style = entry.style
	style.width = entry.baseWidth * multiplier * Fx.trail.ribbon.thickness
	style.color = if entry.flashing then color else entry.color
	style.whiteBlend = if not entry.flashing and swing == "Basic" then Fx.trail.basicWhiteBlend else 0
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

-- [layer]: the glow's own transparency, built once.
local GLOW_FULL: { NumberSequence } = {}
for index, layer in Fx.activationLight.glow.layers do
	GLOW_FULL[index] = NumberSequence.new(layer.transparency)
end

-- The activation's glow along the blade (F13): camera-facing Beams from the guard to the tip,
-- unlit, made on first use.
local function ensureGlow(entry: Entry): { Beam }
	local glow = entry.glow
	if glow ~= nil and #glow > 0 and glow[1].Parent == entry.weapon then
		return glow
	end
	local config = Fx.activationLight.glow
	local made: { Beam } = {}
	for index, layer in config.layers do
		local beam = Instance.new("Beam")
		beam.Name = config.name .. layer.name
		beam.Attachment0 = entry.trail.Attachment0
		beam.Attachment1 = entry.trail.Attachment1
		beam.FaceCamera = true
		beam.Segments = 1
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.Texture = ""
		beam.LightInfluence = 0
		beam.LightEmission = layer.lightEmission
		beam.ZOffset = layer.zOffset
		beam.Width0 = layer.width
		beam.Width1 = layer.width
		beam.Transparency = GLOW_FULL[index]
		beam.Enabled = false
		beam.Parent = entry.weapon
		made[index] = beam
	end
	entry.glow = made
	return made
end

-- The glow on, at full, in the light's color at the ribbon's saturation.
local function showGlow(entry: Entry, color: Color3)
	local glow = ensureGlow(entry)
	local saturated = TrailRibbon.saturate(color)
	for index, layer in Fx.activationLight.glow.layers do
		local beam = glow[index]
		beam.Color = ColorSequence.new(saturated:Lerp(Palette.color3("SystemWhite"), layer.whiteBlend))
		beam.Transparency = GLOW_FULL[index]
		beam.Enabled = true
	end
end

-- The glow `out` (0..1) of the way through a cancelled Art's fade.
local function fadeGlow(entry: Entry, out: number)
	local glow = entry.glow
	if glow == nil then
		return
	end
	for index, layer in Fx.activationLight.glow.layers do
		glow[index].Transparency = NumberSequence.new(1 - (1 - layer.transparency) * (1 - out))
	end
end

local function hideGlow(entry: Entry)
	local glow = entry.glow
	if glow == nil then
		return
	end
	for _, beam in glow do
		beam.Enabled = false
	end
end

-- Where a new rig's ribbon clock starts: the last render step's time, when that was within a jump,
-- so a rig attached inside a frame (by its first trail event) has that whole frame on its ribbon
-- clock, as a rig attached before it does (D-336); else now.
local function ribbonStart(): number
	local now = Engine.now()
	local at = renderedAt
	if at ~= nil and at <= now and now - at <= ChoreoData.stall.jumpSeconds then
		return at
	end
	return now
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
		glow = nil,
		allowed = true,
		removedCancel = Engine.onRemoved(model, function()
			Trails.detach(model)
		end),
		tip = finish,
		tips = {},
		tipHead = 0,
		tipCount = 0,
		sampledAt = 0,
		mount = nil,
		mountPart0 = nil,
		lastSwing = nil,
		lastSwingAt = 0,
		strikeAt = nil,
		snapFrom = nil,
		snapLate = false,
		snapSwing = nil,
		snapAt = 0,
		lit = false,
		chain = nil,
		chainTried = false,
		chainPart0 = nil,
		pose = { root = CFrame.identity, transforms = {} },
		lastPose = { root = CFrame.identity, transforms = {} },
		hasPose = false,
		poseAt = 0,
		guardAt = Vector3.zero,
		tipAt = Vector3.zero,
		stroke = false,
		cutSourced = false,
		cutTip = Vector3.zero,
		cutWay = nil,
		cutSwept = 0,
		cutDone = false,
		drew = false,
		cutEnd = nil,
		late = nil,
		lateFrom = 0,
		lateFull = false,
		source = nil,
		sourceMixer = nil,
		sourceTime = 0,
		fromTime = 0,
		sourceWeight = 1,
		lastWeight = 1,
		sourceOffsets = nil,
		lastOffsets = nil,
		linkNames = {},
		residuals = {},
		nextResiduals = {},
		between = { root = CFrame.identity, transforms = {} },
		ribbon = nil,
		ribbonClock = 0,
		ribbonAt = ribbonStart(),
		style = {
			color = color,
			whiteBlend = 0,
			width = width,
			lifetime = Fx.trail.lifetime,
			closeSeconds = Fx.trail.ribbon.closeSeconds,
			viewer = nil,
		},
		drawn = {
			at = 0,
			chain = nil,
			pose = { root = CFrame.identity, transforms = {} },
			light = nil,
			mixer = nil,
			opened = nil,
			from = 0,
			to = 0,
			lightWeight = 1,
			source = nil,
			sourceTime = 0,
			sourceDone = false,
			sourceWeight = 1,
			late = false,
			pending = false,
		},
		lightSerial = 0,
		lightOut = false,
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
	entry.lightOut = false
	hideGlow(entry)
	entry.removedCancel()
	entry.trail.Enabled = false
	entry.lit = false
	entry.late = nil
	releaseRibbon(entry)
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
		-- a chord from the tip's last sample before it. One that a late start's first step lights
		-- has no sample of its clip before it (the ring holds the pose before the jump): the ring
		-- starts over and the snap measures from its first sample, as a sheath-drawn opener's
		-- does (D-473, D-538).
		local late = entry.late
		local lateStrike = late ~= nil and late.done ~= true and late.lastTime == entry.lateFrom
		if lateStrike then
			entry.tipCount = 0
		end
		entry.snapLate = lateStrike
		entry.strikeAt = Engine.now()
		entry.snapFrom = if entry.tipCount > 0 then entry.tips[entry.tipHead] else nil
		entry.snapSwing = nil
	end
	if on then
		-- The blade chain, before the trail lights: a rig with one draws the ribbon from the start.
		chainOf(entry, entry.chain == nil)
	end
	entry.active[kind] = if on then true else nil
	applyAppearance(entry)
	rebalance()
end

--- A clip that came in late (D-538): the network catch-up started the Mixer `handle` past its
--- start, so the frames before the one that draws its first step showed another clip's pose. A
--- stroke its first step lights (a window the start jumped into, which Replication lights, or an
--- open that first step crosses) waits for that step (a freeze can hold it), then is back-filled
--- from its window's open on the clip's own blade at full weight, each sample aged by its own
--- clip time (D-550), the frame before standing in by the frame's own pose (as on a rig's first
--- read, D-336), never joined to the blade before the jump; nothing at or past its end pose. Call
--- it when the clip starts, before the frame that draws its first step.
function Trails.lateStroke(model: Instance, handle: any)
	if typeof(handle) ~= "table" or typeof(handle.lastTime) ~= "number" then
		return
	end
	if entries[model] == nil and not Trails.attach(model) then
		return
	end
	local entry = entries[model] :: Entry
	entry.late = handle
	entry.lateFrom = handle.lastTime
end

--- The activation light on the blade (range 8, brightness 2) in the trail color and the blade's
--- glow (F13), plus the three-frame SystemWhite flash on the weapon's own Highlight when it turns
--- on (the weapon part alone, never the body: issue 5). `fade` (a cancelled Art) fades the light out over
--- fx.activationLight.cancelFadeSeconds instead of putting it out at once (issue 13). `serial`: a
--- change asked for the frame that draws a step's pose passes the count (Trails.lightSerial) it saw
--- when asked, and is dropped when a change made at once came between (D-479); with none, the
--- change is made at once and counted.
function Trails.activationLight(model: Instance, on: boolean, token: string?, fade: boolean?, serial: number?)
	if entries[model] == nil and not Trails.attach(model) then
		return
	end
	local entry = entries[model] :: Entry
	if serial ~= nil then
		if serial ~= entry.lightSerial then
			return
		end
	else
		entry.lightSerial += 1
	end
	if token ~= nil and Palette.tokens[token] ~= nil then
		entry.light.Color = Palette.color3(token :: any)
	else
		entry.light.Color = entry.color
	end
	-- Any change takes the place of a light-out still waiting for the ribbon.
	entry.lightOut = false
	if
		not on
		and fade ~= true
		and entry.light.Enabled
		and entry.lightFade == nil
		and entry.lit
		and entry.chain ~= nil
		and renderedAt ~= nil
		and not (entry.stroke and entry.drew)
	then
		-- The window that puts the light out lit the ribbon, and its stroke has laid no segment
		-- yet: the light stays on until the frame whose ribbon lays it (stepRibbons). A first
		-- drawn frame that shows the clip a hair past the open (60 fps lands Vertical's 0.35 on
		-- a frame) has the blade under trail.minLength from it: lit, no segment, and dark with
		-- the light out, a still frame between the glow and the trail (D-558).
		entry.lightOut = true
		return
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
		showGlow(entry, entry.light.Color)
		flashWeapon(entry)
	else
		hideGlow(entry)
	end
end

--- How many activation light changes were made at once on a rig (0 for a rig not tracked): what a
--- change asked for a later frame passes to activationLight (D-479).
function Trails.lightSerial(model: Instance): number
	local entry = entries[model]
	return if entry ~= nil then entry.lightSerial else 0
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
			hideGlow(entry)
		else
			entry.lightFade = elapsed + dt
			local eased = Easing.evaluate(Fx.activationLight.cancelFadeEasing, t)
			entry.light.Brightness = Fx.activationLight.brightness * (1 - eased)
			fadeGlow(entry, eased)
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

--- True when the rig's trail is currently on (its engine Trail or its ribbon draws it).
function Trails.isEnabled(model: Instance): boolean
	local entry = entries[model]
	return entry ~= nil and entry.lit
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
		if entry.snapLate then
			-- A late start's strike, lit before the frame that draws its first step: the snap
			-- spans the snap frames from its first sample, as an opener's does (D-473, D-538).
			entry.strikeAt = at
			entry.snapLate = false
		end
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

-- The clip events that light a trail (Replication.routeClipEvent and ClipLab route them so).
local LIGHTS: { [string]: boolean } = { TrailOn = true, HitWindowOpen = true, SmearOn = true }
-- The events that light the clip's trail kind and those that put it out (Replication.routeClipEvent).
local TRAIL_OPENS: { [string]: boolean } = { TrailOn = true, HitWindowOpen = true }
local TRAIL_CLOSES: { [string]: boolean } = { HitWindowClose = true, TrailOff = true, PostMotionStart = true }

-- True when `handle` is the clip a late start jumped in (Trails.lateStroke) and its last step was
-- its first, so the frame before showed another clip's pose (D-538).
local function lateFirst(entry: Entry, handle: any): boolean
	local late = entry.late
	return late ~= nil and handle == late and late.done ~= true and late.lastTime == entry.lateFrom
end

-- The clip time a clip's own events opened the trail lit at clip time `time`: its last open
-- (TrailOn, HitWindowOpen) at or before `time`, when no close (HitWindowClose, TrailOff,
-- PostMotionStart) came after it up to `time`; nil while the trail is out there.
local function windowOpenAt(clip: any, time: number): number?
	local openAt, closeAt = -math.huge, -math.huge
	for _, event in clip.events do
		if event.time <= time then
			if TRAIL_OPENS[event.kind] then
				openAt = math.max(openAt, event.time)
			elseif TRAIL_CLOSES[event.kind] then
				closeAt = math.max(closeAt, event.time)
			end
		end
	end
	return if openAt > closeAt then openAt else nil
end

-- True when a late start's clip is still where it came in after its first step (a freeze held
-- that step: the frame shows the pose from before the jump), so a stroke it lit waits for it.
local function pendingOf(entry: Entry): boolean
	local late = entry.late
	return late ~= nil and lateFirst(entry, late) and late.time <= late.lastTime
end

-- Of the rig's playing clips now, the handle whose clock crossed a lighting event in its last step
-- (Mixer handle.lastTime to its time), its mixer, and the event's clip time (the earliest crossed).
-- With none, a late start's clip on its first step whose trail is lit where it came in (the
-- catch-up jumped into its window, D-538), opened at that clock. Nil when no clip lit it in that
-- step (a flash, a rig no animator plays, a trail that lit while out of the budget).
local function liveLighting(entry: Entry): (any, any, number?)
	local animator = deps.animator(entry.model)
	local mixer = if typeof(animator) == "table" then animator.mixer else nil
	if typeof(mixer) ~= "table" or typeof(mixer.handles) ~= "function" then
		return nil, nil, nil
	end
	local found: any, opened: number? = nil, nil
	for _, handle in mixer:handles() do
		local from, to = handle.lastTime, handle.time
		if handle.done or typeof(from) ~= "number" or typeof(to) ~= "number" or to <= from then
			continue
		end
		for _, event in handle.clip.events do
			if LIGHTS[event.kind] and event.time > from and event.time <= to then
				if opened == nil or event.time < (opened :: number) then
					found, opened = handle, event.time
				end
			end
		end
	end
	local late = entry.late
	if found == nil and late ~= nil then
		if not lateFirst(entry, late) then
			-- Past its first step: the frame before shows its own pose now.
			entry.late = nil
		elseif late.time > late.lastTime and windowOpenAt(late.clip, late.lastTime) ~= nil then
			for _, handle in mixer:handles() do
				if handle == late then
					found, opened = late, late.lastTime
					break
				end
			end
		end
	end
	return found, if found ~= nil then mixer else nil, opened
end

-- The rig's reading at this frame's start (D-479), nil when the drawn pose's step did not read it
-- this frame (none is bound, the rig was not wanted then, its chain changed since).
local function freshDrawn(entry: Entry): Drawn?
	local drawn = entry.drawn
	if drawnFrame > 0 and drawn.at == drawnFrame and drawn.chain ~= nil and drawn.chain == entry.chain then
		return drawn
	end
	return nil
end

-- The clip that lit a stroke on this frame: the handle whose clock crossed a lighting event in the
-- step this frame shows (read at the frame's start where the drawn pose's step runs, D-479, else
-- now), its mixer, the event's clip time and the handle's clock over that step, and whether that
-- step was a late start's first (the frame before shows another clip's pose, D-538).
local function lighting(entry: Entry): (any, any, number?, number, number, boolean)
	local drawn = freshDrawn(entry)
	if drawn ~= nil then
		return drawn.light, drawn.mixer, drawn.opened, drawn.from, drawn.to, drawn.late
	end
	local handle, mixer, opened = liveLighting(entry)
	if handle == nil then
		return nil, nil, nil, 0, 0, false
	end
	return handle, mixer, opened, handle.lastTime, handle.time, lateFirst(entry, handle)
end

-- A late start's clip the step this frame shows left where it came in (pendingOf, D-550).
local function latePending(entry: Entry): boolean
	local drawn = freshDrawn(entry)
	if drawn ~= nil then
		return drawn.pending
	end
	return pendingOf(entry)
end

-- A stroke clip's clock and whether it is done, as the step this frame shows left them.
local function clockOf(entry: Entry, source: any): (number, boolean)
	local drawn = freshDrawn(entry)
	if drawn ~= nil then
		if source == drawn.light then
			return drawn.to, false
		elseif source == drawn.source then
			return drawn.sourceTime, drawn.sourceDone
		end
	end
	return source.time, source.done == true
end

-- What `pose` shows on top of the clip sampled at `offsets`, per link (Transform = clip * this):
-- a blend with another clip, a procedural layer. Nil for a link the clip has no key for.
local function residualsOf(entry: Entry, pose: BladeContact.Pose, offsets: ClipSampler.Offsets, into: { CFrame? })
	table.clear(into)
	for index, name in entry.linkNames do
		local offset = offsets[name]
		local transform: CFrame? = pose.transforms[index]
		if offset ~= nil and transform ~= nil then
			into[index] = ClipSampler.toCFrame(offset):Inverse() * transform
		end
	end
end

-- A handle's share of the limbs (Mixer.preview with no time to move: its eased envelope times its
-- weight, as its last step left it), 0..1.
local function weightOf(mixer: any, handle: any): number
	if typeof(mixer) ~= "table" or typeof(mixer.preview) ~= "function" then
		return 1
	end
	return math.clamp(mixer:preview(handle, 0), 0, 1)
end

-- The stroke clip's share of the limbs as the step that showed this frame left it, 0..1.
local function shownWeight(entry: Entry): number
	local source = entry.source
	local drawn = freshDrawn(entry)
	if drawn ~= nil then
		if source == drawn.light then
			return drawn.lightWeight
		elseif source == drawn.source then
			return drawn.sourceWeight
		end
	end
	return weightOf(entry.sourceMixer, source)
end

-- Follows the stroke's clip across this frame: a new stroke looks for the clip that lit it (and
-- answers the fraction of the frame where it lit), a stroke under way keeps its clip. Samples the
-- clip at both frames' clocks and what each frame shows on top of it. A clip that is gone (or
-- whose clock went back) leaves the stroke to the two frames' poses.
local function followSource(entry: Entry, starting: boolean): number?
	local opened: number? = nil
	if starting then
		local handle, mixer, at, lastTime = lighting(entry)
		entry.source = handle
		entry.sourceMixer = mixer
		if handle ~= nil then
			entry.sourceTime = lastTime
			entry.sourceOffsets = nil
			opened = at
		end
	end
	local source = entry.source
	if source == nil then
		return nil
	end
	local from = entry.sourceTime
	local to, done = clockOf(entry, source)
	if done or to < from then
		entry.source = nil
		return nil
	end
	local before = entry.sourceOffsets or ClipSampler.sample(source.clip, from)
	local after = if to == from then before else ClipSampler.sample(source.clip, to)
	entry.lastOffsets = before
	entry.sourceOffsets = after
	entry.fromTime = from
	entry.sourceTime = to
	local weight = shownWeight(entry)
	entry.lastWeight = if starting then weight else entry.sourceWeight
	entry.sourceWeight = weight
	residualsOf(entry, entry.lastPose, before, entry.residuals)
	residualsOf(entry, entry.pose, after, entry.nextResiduals)
	if opened == nil then
		return nil
	end
	return if to > from then math.clamp(((opened :: number) - from) / (to - from), 0, 1) else 1
end

-- The blade `alpha` (0..1) of the way from the frame before's pose to this one. With the stroke's
-- clip: the clip at its clock that far between the frames, what the frames show on top of it
-- carried across (each link's residual interpolated), by the clip's shown weight over the two
-- frames' interpolated pose. Without: the two frames' poses interpolated (BladeContact.blade).
local function bladeAt(entry: Entry, chain: BladeContact.Chain, alpha: number): (Vector3, Vector3)
	if alpha >= 1 then
		return entry.guardAt, entry.tipAt
	end
	local source = entry.source
	local weight = entry.sourceWeight
	if source == nil or weight <= 0 then
		return BladeContact.blade(chain, entry.pose, entry.lastPose, alpha)
	end
	local sampled = ClipSampler.sample(source.clip, entry.fromTime + (entry.sourceTime - entry.fromTime) * alpha)
	local pose, lastPose, between = entry.pose, entry.lastPose, entry.between
	between.root = lastPose.root:Lerp(pose.root, alpha)
	local transforms = between.transforms
	local residuals, nextResiduals = entry.residuals, entry.nextResiduals
	for index in chain.links do
		local after = pose.transforms[index] or CFrame.identity
		local before = lastPose.transforms[index] or after
		local linear = before:Lerp(after, alpha)
		local offset = sampled[entry.linkNames[index]]
		local r0, r1 = residuals[index], nextResiduals[index]
		if offset ~= nil and r0 ~= nil and r1 ~= nil then
			local clipped = ClipSampler.toCFrame(offset) * r0:Lerp(r1, alpha)
			transforms[index] = if weight >= 1 then clipped else linear:Lerp(clipped, weight)
		else
			transforms[index] = linear
		end
	end
	return BladeContact.blade(chain, between)
end

-- The stroke clip's own blade at clip time `time`, at its full weight (D-550): each link the clip
-- keys posed as the clip has it then, the others (and the root) as the frames show them `alpha` of
-- the way from the frame before's pose to this one.
local function clipBladeAt(entry: Entry, chain: BladeContact.Chain, time: number, alpha: number): (Vector3, Vector3)
	local sampled = ClipSampler.sample(entry.source.clip, time)
	local pose, lastPose, between = entry.pose, entry.lastPose, entry.between
	between.root = lastPose.root:Lerp(pose.root, alpha)
	local transforms = between.transforms
	for index in chain.links do
		local offset = sampled[entry.linkNames[index]]
		if offset ~= nil then
			transforms[index] = ClipSampler.toCFrame(offset)
		else
			local after = pose.transforms[index] or CFrame.identity
			local before = lastPose.transforms[index] or after
			transforms[index] = before:Lerp(after, alpha)
		end
	end
	return BladeContact.blade(chain, between)
end

-- A new stroke's cut starts at `tip`; `sourced` when it starts at its clip's open (D-273).
local function beginCut(entry: Entry, tip: Vector3, sourced: boolean)
	entry.cutSourced = sourced
	entry.cutTip = tip
	entry.cutWay = nil
	entry.cutSwept = 0
	entry.cutDone = false
	entry.drew = false
end

-- The stroke kept a sample at `tip`: the way the tip went and how far it has swept.
local function advanceCut(entry: Entry, tip: Vector3)
	entry.drew = true
	local move = tip - entry.cutTip
	local length = move.Magnitude
	if length > 1e-6 then
		entry.cutWay = move / length
		entry.cutSwept += length
	end
	entry.cutTip = tip
end

-- True when the tip at `tip` turns back on the cut (D-335): a stroke that started at its clip's
-- open, has swept fx.trail.ribbon.turnBackAfter studs and now steps more than turnBackDegrees off
-- the way it was going (a step under trail.minLength is no step). A stroke with no clip (a flash,
-- a stall's wake) may start on wind-up motion, so it never ends this way.
local function turnsBack(entry: Entry, tip: Vector3): boolean
	local way = entry.cutWay
	if not entry.cutSourced or way == nil or entry.cutSwept < Fx.trail.ribbon.turnBackAfter then
		return false
	end
	local move = tip - entry.cutTip
	local length = move.Magnitude
	if length < Fx.trail.minLength then
		return false
	end
	return move:Dot(way) < length * math.cos(math.rad(Fx.trail.ribbon.turnBackDegrees))
end

-- A stroke starting with no pose from the frame before, on a frame its clip lit it (Trails attaches
-- a rig on its first trail event, so a rig's first swing lights on the first frame anything reads
-- it): the pose read now stands in for the frame before too, and pushBlade carries what this frame
-- shows on top of the clip back across the frame unchanged, so the clip at its last clock poses
-- the frame before and the stroke starts at the open, as an attached rig's does (D-273, D-336).
-- False (nothing stood in) with no such clip, or for a step longer than a jump (a stall's wake:
-- nothing across the dark is drawn).
local function standIn(entry: Entry): boolean
	local handle, _, _, from, to = lighting(entry)
	if handle == nil or to - from > ChoreoData.stall.jumpSeconds then
		return false
	end
	local pose, lastPose = entry.pose, entry.lastPose
	lastPose.root = pose.root
	table.clear(lastPose.transforms)
	for index, transform in pose.transforms do
		lastPose.transforms[index] = transform
	end
	return true
end

-- Pushes the stroke clip's own blade from clip time `from` to `to` (D-550) in pieces of a 60 fps
-- frame (choreo.luau frameSeconds), each sub-stepped as a frame is (trail.ribbon.maxStep, at most
-- maxSubsteps), so a stretch longer than this frame's step draws as finely as the frames it spans
-- would have. `born(time)` is a sample's ribbon-clock time, `alphaOf(time)` its share of the way from
-- the frame before's pose to this one. False when the cut turned back (the stroke is over).
local function pushClipSpan(
	entry: Entry,
	chain: BladeContact.Chain,
	ribbon: TrailRibbon.Ribbon,
	from: number,
	to: number,
	born: (time: number) -> number,
	alphaOf: (time: number) -> number
): boolean
	local config = Fx.trail.ribbon
	local pieces = math.max(1, math.ceil((to - from) / ChoreoData.frameSeconds - 1e-6))
	local guardBefore, tipBefore = clipBladeAt(entry, chain, from, alphaOf(from))
	for piece = 1, pieces do
		local pieceFrom = from + (to - from) * (piece - 1) / pieces
		local pieceTo = from + (to - from) * piece / pieces
		local guardEnd, tipEnd = clipBladeAt(entry, chain, pieceTo, alphaOf(pieceTo))
		local steps = BladeContact.steps(guardBefore, tipBefore, guardEnd, tipEnd, config.maxStep, config.maxSubsteps)
		for step = 1, steps do
			local time = pieceFrom + (pieceTo - pieceFrom) * step / steps
			local stepGuard, stepTip = guardEnd, tipEnd
			if step < steps then
				stepGuard, stepTip = clipBladeAt(entry, chain, time, alphaOf(time))
			end
			if turnsBack(entry, stepTip) then
				entry.cutDone = true
				return false
			end
			if TrailRibbon.push(ribbon, stepGuard, stepTip, born(time), true) then
				advanceCut(entry, stepTip)
			end
		end
		guardBefore, tipBefore = guardEnd, tipEnd
	end
	return true
end

-- The first frame that draws a late start's clip (D-550): the catch-up jumped the clip past its
-- window's open, and the frames before showed another clip's pose, so the stroke is drawn here from
-- the open up to the clip time this frame shows, on the clip's own blade at its full weight (the
-- clip is still fading in over the rig's pose: the blade the frame shows is not the stroke's), each
-- sample born as if drawn at its own clip time, so the ribbon looks as the on-time stroke's would
-- at this clip time. `start` is the share of the frame where the step crossed the event that lit
-- it, the open when the window opened in that step. A stroke whose strike already landed draws
-- nothing (D-539).
local function backfill(entry: Entry, chain: BladeContact.Chain, ribbon: TrailRibbon.Ribbon, start: number)
	local source = entry.source
	local clip = source.clip
	local fromTime, toTime = entry.fromTime, entry.sourceTime
	-- The window's own open: before the clip's start when the catch-up jumped into it (a SmearOn
	-- that step crossed is no open), else where the step crossed it.
	local openTime = windowOpenAt(clip, fromTime) or (fromTime + (toTime - fromTime) * start)
	local cutEnd = ClipSampler.strikeLandingAt(clip, openTime)
	entry.stroke = true
	entry.cutEnd = cutEnd
	entry.lateFull = true
	local fromGuard, fromTip = clipBladeAt(entry, chain, openTime, 1)
	beginCut(entry, fromTip, true)
	if cutEnd ~= nil and fromTime >= cutEnd - 1e-6 then
		-- It came in at or past its strike's landing (to the clock's rounding): what is left is the
		-- settle (D-539).
		entry.cutDone = true
		return
	end
	local speed = if typeof(source.speed) == "number" and source.speed > 0 then source.speed else 1
	local clock = entry.ribbonClock
	local function born(time: number): number
		return clock - (toTime - time) / speed
	end
	local function current(_time: number): number
		return 1
	end
	TrailRibbon.push(ribbon, fromGuard, fromTip, born(openTime), false)
	if pushClipSpan(entry, chain, ribbon, openTime, toTime, born, current) and cutEnd ~= nil and toTime >= cutEnd then
		entry.cutDone = true
	end
end

-- A back-filled stroke's move since the last frame while its clip still fades in (D-550): the
-- clip's own blade at its full weight between the two frames' clocks, as the back-fill drew it, so
-- the ribbon goes on from where it stood, never joined to the blade the frame shows.
local function pushFull(entry: Entry, chain: BladeContact.Chain, ribbon: TrailRibbon.Ribbon, clockBefore: number)
	local clock = entry.ribbonClock
	local fromTime, toTime = entry.fromTime, entry.sourceTime
	local span = toTime - fromTime
	local function alphaOf(time: number): number
		return if span > 0 then (time - fromTime) / span else 1
	end
	local function born(time: number): number
		return clockBefore + (clock - clockBefore) * alphaOf(time)
	end
	local cutEnd = entry.cutEnd
	if pushClipSpan(entry, chain, ribbon, fromTime, toTime, born, alphaOf) and cutEnd ~= nil and toTime >= cutEnd then
		entry.cutDone = true
	end
end

-- Adds the blade's move since the last frame to the ribbon: sub-steps from the frame before's pose
-- to this one (each end moving at most trail.ribbon.maxStep), born along the ribbon clock between
-- the two frames, posed from the stroke's clip where it is known (bladeAt). A stroke that starts
-- on a frame its clip lit takes its first sample at the clip time the window opened (the frame
-- before is the wind-up, D-269), even on a rig's first read (standIn) or on a late start's first
-- step (the frame before shows the pose before the jump, D-538); one with no such clip starts
-- from the frame before's blade, and one with no frame before (a stall, a new chain) where the
-- blade is. A clip's stroke ends on the frame that shows its end pose, the clip at or past the
-- landing of the strike snap it began in (D-539), or sooner where its tip turns back on the cut
-- (turnsBack): the settle after a cut is not drawn (D-335).
local function pushBlade(entry: Entry, chain: BladeContact.Chain, hadPose: boolean, clockBefore: number)
	local ribbon = acquireRibbon(entry)
	local guard, tip = entry.guardAt, entry.tipAt
	local clock = entry.ribbonClock
	local standing = false
	local cameLate = false
	if not entry.stroke then
		if latePending(entry) then
			-- A late start's clip lit before its first step moved it (a freeze held that step): the
			-- frame shows the pose from before the jump, so its stroke waits for the clip (D-550).
			return
		end
		-- The clip that lights this stroke came in late on the step this frame shows (the network
		-- catch-up jumped it in): the frame before shows the pose from before the jump, not this
		-- clip's (D-538).
		local _, _, _, _, _, late = lighting(entry)
		cameLate = late
	end
	if not hadPose then
		standing = not entry.stroke and standIn(entry)
		if not standing then
			TrailRibbon.push(ribbon, guard, tip, clock, false)
			entry.stroke = true
			entry.source = nil
			entry.cutEnd = nil
			entry.lateFull = false
			beginCut(entry, tip, false)
			return
		end
	elseif cameLate then
		-- This frame's pose stands in for the frame before, as on a rig's first read (D-538).
		standing = standIn(entry)
	end
	if entry.stroke and entry.cutDone then
		-- The cut turned back: the rest of the window (the settle) draws nothing (D-335).
		return
	end
	if entry.stroke and deps.held(entry.model) then
		-- This frame draws the rig held (a hit-stop, D-353): the pose is the one the frame before
		-- drew, so the stroke lays nothing new, whatever moves the body under it (a watcher's copy
		-- whose replicated root still moves: the stand-off it shows late, D-556). The ribbon's
		-- ages stand still with it, and its stroke's clip clock stands, so the clip is followed on
		-- from where it held. The first frame that moves again goes on from this frame's blade, and
		-- the cut's way is measured from it: the body's move under the held pose is no turn of the cut.
		entry.cutTip = tip
		return
	end
	local starting = not entry.stroke
	local opened = followSource(entry, starting)
	if starting and cameLate and entry.source ~= nil then
		-- The stroke from its window's open, back-filled on its clip's own blade (D-550).
		backfill(entry, chain, ribbon, opened or 0)
		return
	end
	if entry.lateFull then
		if entry.source == nil then
			-- The clip that drew the back-filled stroke is gone: the stroke is over.
			entry.cutDone = true
			return
		elseif entry.lastWeight < 1 or entry.sourceWeight < 1 then
			pushFull(entry, chain, ribbon, clockBefore)
			return
		end
		-- The clip has faded in over both frames: its blade is the one the frame shows.
		entry.lateFull = false
	end
	if standing then
		-- The frame before wears what this one shows on top of the clip (standIn).
		local residuals = entry.residuals
		table.clear(residuals)
		for index, residual in entry.nextResiduals do
			residuals[index] = residual
		end
	end
	local start = opened or 0
	local fromGuard, fromTip
	if start > 0 or standing then
		-- The clip's own blade at the open (or, stood in, at the clock the frame before stands for).
		fromGuard, fromTip = bladeAt(entry, chain, start)
	else
		fromGuard, fromTip = BladeContact.blade(chain, entry.lastPose)
	end
	if starting then
		entry.stroke = true
		entry.lateFull = false
		local source = entry.source
		local openedAt = if source ~= nil and opened ~= nil
			then entry.fromTime + (entry.sourceTime - entry.fromTime) * start
			else nil
		local cutEnd = if openedAt ~= nil then ClipSampler.strikeLandingAt(source.clip, openedAt) else nil
		entry.cutEnd = cutEnd
		if openedAt ~= nil and cutEnd ~= nil and openedAt >= cutEnd then
			-- The stroke's end pose is already behind it (a late start past its snap's landing):
			-- what is left of the window is the settle, and it draws nothing (D-539).
			beginCut(entry, fromTip, true)
			entry.cutDone = true
			return
		end
		TrailRibbon.push(ribbon, fromGuard, fromTip, clockBefore + (clock - clockBefore) * start, false)
		beginCut(entry, fromTip, opened ~= nil)
	end
	local config = Fx.trail.ribbon
	local steps = BladeContact.steps(fromGuard, fromTip, guard, tip, config.maxStep, config.maxSubsteps)
	for step = 1, steps do
		local alpha = start + (1 - start) * step / steps
		local stepGuard, stepTip = guard, tip
		if step < steps then
			stepGuard, stepTip = bladeAt(entry, chain, alpha)
		end
		if turnsBack(entry, stepTip) then
			entry.cutDone = true
			return
		end
		if TrailRibbon.push(ribbon, stepGuard, stepTip, clockBefore + (clock - clockBefore) * alpha, true) then
			advanceCut(entry, stepTip)
		end
	end
	-- This frame shows the stroke's clip at or past its strike snap's landing (the end pose): the
	-- rest of the window (the hold, the overshoot and settle) draws nothing (D-539).
	local cutEnd = entry.cutEnd
	if cutEnd ~= nil and entry.source ~= nil and entry.sourceTime >= cutEnd then
		entry.cutDone = true
	end
end

-- The ribbons' step (after the tip samples, in the pose readers' render step): each rig with a
-- blade chain that is lit, or idle within accents.swing.sampleDistance (so a stroke that lights
-- has the frame before to start between), has its pose read; a lit one adds its blade's move.
-- Every live ribbon is laid for its clock, which stands still while the rig is in hit-stop; one
-- that went out and faded is given back to the pool.
local function stepRibbons(at: number, viewer: Vector3?)
	local range = Accents.swing.sampleDistance
	local jump = ChoreoData.stall.jumpSeconds
	for _, entry in entries do
		local clockBefore = entry.ribbonClock
		local elapsed = at - entry.ribbonAt
		entry.ribbonAt = at
		if (entry.ribbon ~= nil or entry.lit) and elapsed > 0 and not deps.held(entry.model) then
			entry.ribbonClock = clockBefore + elapsed
		end
		local weapon = entry.weapon
		local wanted = weapon.Parent ~= nil
			and (entry.lit or (viewer ~= nil and (weapon.Position - (viewer :: Vector3)).Magnitude <= range))
		local chain = if wanted then chainOf(entry, false) else nil
		if chain == nil then
			entry.hasPose = false
			entry.stroke = false
			if entry.lit and entry.chain == nil and not entry.trail.Enabled then
				-- The chain is gone (the rig was rebuilt): the engine Trail takes the trail back.
				applyAppearance(entry)
			end
		else
			if entry.trail.Enabled then
				-- The chain was found while the engine Trail drew: the ribbon takes over.
				entry.trail.Enabled = false
			end
			local hadPose = entry.hasPose and at - entry.poseAt <= jump
			entry.pose, entry.lastPose = entry.lastPose, entry.pose
			local drawn = freshDrawn(entry)
			if drawn ~= nil then
				-- The pose this frame draws: its Transforms as the frame began (the rigs' step of the
				-- frame before wrote them, D-342) on the root where it stands now (a root moved in
				-- this frame's render steps shows on this frame), D-479.
				BladeContact.copy(drawn.pose, entry.pose)
				entry.pose.root = chain.root.CFrame
			else
				BladeContact.read(chain, entry.pose)
			end
			entry.hasPose = true
			entry.poseAt = at
			entry.guardAt, entry.tipAt = BladeContact.blade(chain, entry.pose)
			if entry.lit then
				pushBlade(entry, chain, hadPose, clockBefore)
			else
				entry.stroke = false
			end
		end
		if entry.lightOut and (chain == nil or not entry.lit or (entry.stroke and (entry.drew or entry.cutDone))) then
			-- The light waited for the stroke's first segment (activationLight, D-558): it goes out
			-- on the frame that lays it, or once the ribbon will lay none (the trail out, no chain,
			-- the stroke over).
			entry.lightOut = false
			entry.light.Enabled = false
			hideGlow(entry)
		end
		local ribbon = entry.ribbon
		if ribbon ~= nil then
			-- The ribbon narrows a cut seen edge-on from here (D-361).
			entry.style.viewer = viewer
			TrailRibbon.draw(ribbon, entry.ribbonClock, entry.style)
			if not entry.lit and not TrailRibbon.live(ribbon) then
				releaseRibbon(entry)
			end
		end
	end
end

-- The drawn pose's step, at a frame's start before any rig steps (fx.luau renderOrder.drawnPose,
-- D-479): a frame draws the pose its rigs' step of the frame before wrote (D-342), so the ribbon of
-- each rig it may draw (lit, or idle within accents.swing.sampleDistance) reads its chain's
-- Transforms here, with the clip that lit a stroke in that step and the stroke clip's clock and
-- weight then; the pose readers' step lays the ribbon from them on the root as it stands there. Read
-- after the rigs' step, the ribbon led the blade it draws beside by a frame and lit on the frame
-- before the window's first drawn pose.
local function readDrawn()
	drawnFrame += 1
	local viewer = Engine.viewerPosition()
	local range = Accents.swing.sampleDistance
	for _, entry in entries do
		local weapon = entry.weapon
		local wanted = weapon.Parent ~= nil
			and (entry.lit or (viewer ~= nil and (weapon.Position - (viewer :: Vector3)).Magnitude <= range))
		local chain = if wanted then chainOf(entry, false) else nil
		if chain == nil then
			continue
		end
		local drawn = entry.drawn
		BladeContact.read(chain, drawn.pose)
		drawn.at = drawnFrame
		drawn.chain = chain
		-- Only a lit rig starts a stroke, so only its step's lighting is looked for.
		local handle, mixer, opened = nil, nil, nil
		if entry.lit then
			handle, mixer, opened = liveLighting(entry)
		end
		drawn.light, drawn.mixer, drawn.opened = handle, mixer, opened
		drawn.from = if handle ~= nil then handle.lastTime else 0
		drawn.to = if handle ~= nil then handle.time else 0
		drawn.lightWeight = if handle ~= nil then weightOf(mixer, handle) else 1
		drawn.late = handle ~= nil and lateFirst(entry, handle)
		drawn.pending = pendingOf(entry)
		local source = entry.source
		drawn.source = source
		if source ~= nil then
			drawn.sourceTime = source.time
			drawn.sourceDone = source.done == true
			drawn.sourceWeight = weightOf(entry.sourceMixer, source)
		end
	end
end

--- Records each tracked blade tip's world position in its ring (the pose readers' render step
--- runs it, so the tip is where this frame draws it; specs call it), and remembers the direction
--- of a rig that is swinging (a trail kind on). Only a rig whose answer can matter is read: one
--- swinging, or an idle one within accents.swing.sampleDistance of the viewer; a weapon that left
--- the world is never read. A rig not read this frame starts its ring over, and so does one read
--- more than choreo.luau stall.jumpSeconds after its last sample (a render stall): no chord ever
--- spans the frames it missed.
-- The part the blade rides on now: its joint's (WeaponBuilder's Weapon motor, Part1 the blade)
-- Part0, the hand or the back mount WeaponMount moved it to; nil for a blade no such joint holds.
-- The joint is looked up again only while none is known or once it left the blade (an equip, a
-- respawn), never by a scan of the weapon's children.
local function mountPart(entry: Entry): BasePart?
	local joint = entry.mount
	local weapon = entry.weapon
	if joint == nil or joint.Parent ~= weapon then
		joint = nil
		local found = weapon:FindFirstChild(WeaponModels.motorName)
		local asJoint = if found ~= nil then Joints.asJoint(found) else nil
		if asJoint ~= nil then
			local _, part1 = Joints.parts(asJoint)
			if part1 == weapon then
				joint = asJoint
			end
		end
		entry.mount = joint
	end
	if joint == nil then
		return nil
	end
	local part0 = Joints.parts(joint)
	return part0
end

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
		local part0 = mountPart(entry)
		if part0 ~= entry.mountPart0 then
			-- The sword changed hands since the last sample (WeaponMount, the back mount and the
			-- hand): the ring starts over, and a strike measures its snap from this sample, its first
			-- in the hand. Kept, the back mount's sample turned an opener's snap 53 to 71 degrees off
			-- its slash (D-473).
			entry.mountPart0 = part0
			entry.tipCount = 0
			entry.snapFrom = nil
		end
		if entry.tipCount > 0 and at - entry.sampledAt > ChoreoData.stall.jumpSeconds then
			-- Nothing rendered for longer than a jump: the ring starts over, a strike from before
			-- the gap loses its snap, and one begun since measures from this sample.
			entry.tipCount = 0
			local strikeAt = entry.strikeAt
			if strikeAt ~= nil and strikeAt <= entry.sampledAt then
				entry.strikeAt = nil
			end
			entry.snapFrom = nil
		end
		entry.sampledAt = at
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
	stepRibbons(at, viewer)
end

--- The rig's newest blade tip sample (where the last rendered frame drew its tip); nil when its
--- ring is empty or the rig is not tracked (specs).
function Trails.lastSample(model: Instance): Vector3?
	local entry = entries[model]
	if entry == nil or entry.tipCount == 0 then
		return nil
	end
	return entry.tips[entry.tipHead]
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

--- What the rig's ribbon draws now: its live samples' points and the Beams showing (specs); nil
--- while it draws none.
function Trails.ribbonOf(model: Instance): TrailRibbon.View?
	local entry = entries[model]
	local ribbon = if entry ~= nil then entry.ribbon else nil
	if ribbon == nil then
		return nil
	end
	return TrailRibbon.view(ribbon)
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
		-- The ribbon goes too, and nothing the blade did before the dark is drawn after it.
		entry.lit = false
		entry.stroke = false
		entry.hasPose = false
		releaseRibbon(entry)
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
		sinceRank += dt
		if sinceRank >= Fx.trail.rankInterval then
			sinceRank = 0
			rebalance()
		end
	end)
	-- The pose readers' step: a stall's wake first, then every blade tip where this frame draws it.
	stopRender = deps.onRender(function()
		rendered()
		Trails.sample()
	end)
	-- The drawn pose at each frame's start (D-479); none bound under Lune.
	stopDrawn = deps.onDrawn(readDrawn)
end

local function disconnectLoops()
	local stopWatch, stopStep, stopStart = stopLoop, stopRender, stopDrawn
	stopLoop, stopRender, stopDrawn = nil, nil, nil
	if stopStart ~= nil then
		stopStart()
	end
	if stopWatch ~= nil then
		stopWatch()
	end
	if stopStep ~= nil then
		stopStep()
	end
end

--- Starts the periodic budget re-rank (rigs move), the render-stall watchdog, the render step
--- (the stall's wake and the blade samples) and follows quality changes.
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
