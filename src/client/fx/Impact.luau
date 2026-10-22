--!strict
--[[
	Impact: the impact director. One call per combat moment (a confirmed hit, an Art activation, a
	dodge, a death) picks the moment's row in moments.luau and fires what that row names, by key,
	in the modules that draw and sound it: ImpactFrames (the full-screen silhouettes), Glint,
	SlashArc (the crescent and the slash line), SpeedLines, Trails (the swing direction, the
	Switch flash), SfxPool (cues, contours, the riser), CameraController (the FOV punch),
	OutlineManager (the white Highlight flash a row owns) and ClipLibrary (the activation's timing).
	Every choice comes from moments.luau; nothing here decides what a moment looks like.

	Who gets what (moments.audience, a row may override): "Always" plays on every client; "Range"
	when the local player is involved or the moment's point is within the row's range of the
	camera; "Involved" only for the local attacker or target (for a dodge or an activation, the
	fighter is the local player). Impact frames, the punch and a hit's contour are Involved, so a
	fight across the field never flashes or pushes anyone else's screen; past a moment's range
	nothing but its sound plays.

	The swing tangent for the crescent, the line and the impact frames' strokes is
	Trails.swingDirection(attacker), else the horizontal direction from the attacker to the
	target, else the camera's right vector. The crescent lies in the true swing plane: its normal
	is the hit's radius from the attacker crossed with the tangent (right-hand rule, so it bulges
	away from the attacker), else tangent x up for a thrust or an unknown attacker, else the
	camera's right vector when the swing is vertical; then it turns about the tangent toward the
	camera by at most accents.slashArc.tilt.maxDegrees, so a horizontal swing never reads edge-on.
	The strokes' screen direction is the tangent projected through the camera.

	One sweep through many targets confirms them all within a few frames: inside
	moments.sweep.mergeSeconds each cue and extra sound plays once per attacker (SfxPool's
	same-spot dedupe would let a wide sweep stack them), and the contour and the punch play once,
	or again only for a stronger hit-stop (a kill among final hits takes over; a final hit after
	the kill never undoes its cut). A cue of a weaker hit-stop than one the sweep already played
	adds nothing, unless it is an outcome of its own (a parry, a block), and every cue of a sweep
	sounds at its first hit, so the layers two cues share (the crack, the flesh) are one sound in
	SfxPool. The hits the local player is in are a sweep of their own, apart from the same
	attacker's hits on others: an enemy's cleave through an ally and the local player sounds the
	player's own hit at the player, never folded into the ally's. ImpactFrames joins the frames of
	one sweep into one picture, charged once; a later hit of the sweep whose picture already ended
	draws none again unless its hit-stop is stronger.

	Order on a hit: the cue first (its crack starts with the picture), then the impact frames;
	the 3D accents (glint, crescent, slash line, the Highlight flash, the Switch trail flash) wait
	while the impact frames hide the world for this viewer (ImpactFrames.hiddenSeconds: a
	ScreenGui draws over BillboardGuis, Beams and Highlights), asked again when the wait is over
	(a stronger hit of the same sweep may have lengthened the picture), then play, so the white
	flash and the slash line are seen after the frames, as in the reel. The contour and the punch start at
	once.

	The activation riser ends on the clip's first damage frame (its first HitWindowOpen after the
	ActivationHold). A remote fighter's clip plays straight through (its ArtRequest was sent on
	release), so `activation`, called on the ActivationHold event, ends the riser
	(window - hold) / speed later, less `lateBy` when a late catch-up start jumped over the hold
	(Replication replays it). The local fighter's clip waits at the hold pose until the key
	comes up: `activation` only starts the wind-up contour for them, and `release` (called from
	the controller's release) plays the riser to end on the first window after the release and
	brings the highs back there; `cancelActivation` brings them back at once. A riser shorter
	than the row's minLeadSeconds is skipped.

	Dependencies come in through `Impact.bind(deps)` (specs pass fakes); `Impact.start()` binds the
	real modules through Siblings. A missing module, a missing function or an effect that errors is
	logged once and the moment's other effects still play.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Moments = require(Shared.data.moments)
local Accents = require(Shared.data.accents)
local Combat = require(Shared.data.combat)
local Engine = require(script.Parent.Engine)
local Siblings = require(script.Parent.Parent.controllers.Siblings)

export type Tier = "Normal" | "Final" | "Kill"

-- One confirmed hit, as Replication sees it (HitConfirmed plus who the local player is).
export type HitInfo = {
	tier: Tier, -- the hit-stop tier
	position: Vector3, -- the hit point
	attacker: Model?,
	target: Model?,
	involved: boolean, -- the local player is the attacker or the target
	localAttacker: boolean, -- the local player is the attacker
	trailToken: string, -- the attacker's trail token (palette)
	parried: boolean,
	guarded: boolean,
	crit: boolean,
	isSwitch: boolean,
	killed: boolean,
	-- true for an Art's hit (HitConfirmed carries an artId; only an Art's final hit is FinalHit),
	-- false for a player's basic swing (BasicHit), nil for anything else (an enemy's strike).
	art: boolean?,
	partner: Model?, -- the Switch window's opener, whose trail also flashes when the Switch lands
}

export type Deps = {
	impactFrames: any?, -- play(sequence, models, { slashDirection, now, position }) -> seconds; hiddenSeconds()
	glint: any?, -- play(position, size, token?)
	slashArc: any?, -- play(position, tangent, normal, token, size), line(position, tangent, size)
	speedLines: any?, -- play(kind)
	trails: any?, -- swingDirection(model) -> Vector3?, flashWhite(model, frames)
	sfx: any?, -- cue(name, position?), contour(name), play(name, position?), playEndingAt(name, seconds, position?)
	camera: any?, -- punch(kind)
	outline: any?, -- flash(model, token, frames)
	clipLibrary: any?, -- get(clipId) -> ClipDef
	now: (() -> number)?,
	viewerPosition: (() -> Vector3?)?, -- the camera's position (range checks)
	cameraRight: (() -> Vector3?)?,
	screenDirection: ((position: Vector3, direction: Vector3) -> Vector2?)?, -- world direction -> screen (x right, y down)
	positionOf: ((model: Instance) -> Vector3?)?,
	delay: ((seconds: number, fn: () -> ()) -> ())?, -- runs fn `seconds` later (task.delay)
}

-- Where Impact.start finds each real module, under the client root.
local MODULES: { [string]: string } = {
	impactFrames = "fx.ImpactFrames",
	glint = "fx.Glint",
	slashArc = "fx.SlashArc",
	speedLines = "fx.SpeedLines",
	trails = "fx.Trails",
	sfx = "audio.SfxPool",
	camera = "camera.CameraController",
	outline = "fx.OutlineManager",
	clipLibrary = "choreo.ClipLibrary",
}

local Impact = {}

local deps: Deps = {}
local reported: { [string]: boolean } = {}
local started = false

-- The sounds each attacker's current sweep already fired, the strongest cue, contour, punch and
-- picture it played (by hit-stop frames), where its first cue sounded, and when it began.
type Sweep = { at: number, fired: { [string]: boolean }, strongest: { [string]: number }, cueAt: Vector3? }
-- A removed rig's sweep goes with it. The hits the local player is in are a sweep of their own.
local sweeps: { [any]: Sweep } = setmetatable({}, { __mode = "k" }) :: any
local ownSweeps: { [any]: Sweep } = setmetatable({}, { __mode = "k" }) :: any
local NO_ATTACKER = {} -- the sweep key of a hit whose attacker this client does not track

-- ------------------------------------------------------------------ plumbing

local function report(key: string, message: string)
	if reported[key] then
		return
	end
	reported[key] = true
	warn("[Impact] " .. message)
end

-- Calls deps[name][fn](...) when both exist. A missing module or function, or an error, is logged
-- once per name and returns nil, so one broken effect never stops the moment's others.
local function call(name: string, fn: string, ...: any): any
	local module = (deps :: any)[name]
	if module == nil then
		report(name, ("%s is not available; its effects are skipped"):format(name))
		return nil
	end
	local method = if typeof(module) == "table" then module[fn] else nil
	if typeof(method) ~= "function" then
		report(name .. "." .. fn, ("%s.%s is missing; that effect is skipped"):format(name, fn))
		return nil
	end
	local ok, result = pcall(method, ...)
	if not ok then
		report(name .. "." .. fn .. ":error", ("%s.%s failed (%s); skipped"):format(name, fn, tostring(result)))
		return nil
	end
	return result
end

local function now(): number
	local clock = deps.now
	return if clock ~= nil then clock() else Engine.now()
end

-- Runs `fn` now, or `seconds` later through the scheduler (task.delay when none is bound).
local function after(seconds: number, fn: () -> ())
	if seconds <= 0 then
		fn()
		return
	end
	local schedule = deps.delay
	if schedule ~= nil then
		schedule(seconds, fn)
	else
		task.delay(seconds, fn)
	end
end

local function viewer(): Vector3?
	local fn = deps.viewerPosition
	return if fn ~= nil then fn() else Engine.viewerPosition()
end

local function positionOf(model: Instance?): Vector3?
	if model == nil then
		return nil
	end
	local fn = deps.positionOf
	return if fn ~= nil then fn(model) else Engine.modelPosition(model)
end

local function cameraRight(): Vector3?
	local fn = deps.cameraRight
	if fn ~= nil then
		return fn()
	end
	local camera = Engine.camera()
	return if camera ~= nil then camera.CFrame.RightVector else nil
end

local function unit(v: Vector3?): Vector3?
	if v == nil or typeof(v) ~= "Vector3" then
		return nil
	end
	local length = v.Magnitude
	if length <= Moments.epsilon then
		return nil
	end
	return v / length
end

-- Drops the sweeps that went quiet (past the merge window).
local function dropQuiet(list: { [any]: Sweep }, at: number, window: number)
	for other, old in list do
		if at - old.at > window then
			list[other] = nil
		end
	end
end

-- The sweep a hit belongs to: later hits of the same attacker inside moments.sweep.mergeSeconds
-- of the sweep's first hit are the same sweep, those the local player is in apart from the rest.
local function sweepOf(info: HitInfo): Sweep
	local at = now()
	local window = Moments.sweep.mergeSeconds
	local owner: any = if info.attacker ~= nil then info.attacker else NO_ATTACKER
	local list = if info.involved then ownSweeps else sweeps
	local sweep = list[owner]
	if sweep ~= nil and at - sweep.at <= window then
		return sweep
	end
	-- A new sweep; sweeps of every attacker that went quiet are dropped with it.
	dropQuiet(sweeps, at, window)
	dropQuiet(ownSweeps, at, window)
	local fresh: Sweep = { at = at, fired = {}, strongest = {} }
	list[owner] = fresh
	return fresh
end

-- True the first time a sweep fires `key` (an effect and its name).
local function firstInSweep(info: HitInfo, key: string): boolean
	local sweep = sweepOf(info)
	if sweep.fired[key] then
		return false
	end
	sweep.fired[key] = true
	return true
end

-- Where a sweep's cue sounds (nil: not at all): the first time the sweep fires that cue, unless it
-- already played a stronger hit-stop's cue (a final hit after the kill adds nothing; an outcome of
-- its own, a parry or a block, always sounds); always at the sweep's first cue, so SfxPool folds
-- the layers two cues share.
local function cueInSweep(info: HitInfo, cue: string, tier: string?, position: Vector3): Vector3?
	local sweep = sweepOf(info)
	local rank = (Combat.hitStopFrames :: { [string]: number })[tier or "Normal"] or 0
	local best = sweep.strongest.Cue
	local outcome = info.parried or info.guarded
	if sweep.fired["Cue:" .. cue] or (best ~= nil and rank < best and not outcome) then
		return nil
	end
	sweep.fired["Cue:" .. cue] = true
	sweep.strongest.Cue = if best ~= nil then math.max(best, rank) else rank
	sweep.cueAt = sweep.cueAt or position
	return sweep.cueAt
end

-- True when a sweep's `effect` (the contour, the punch) for a moment on hit-stop `tier` plays:
-- the sweep's first, or one stronger than any it played. A kill among final hits takes the mix
-- over; a final hit confirmed after the kill never undoes its cut or restarts a smaller punch.
local function strongestInSweep(info: HitInfo, effect: string, tier: string?): boolean
	local sweep = sweepOf(info)
	local rank = (Combat.hitStopFrames :: { [string]: number })[tier or "Normal"] or 0
	local best = sweep.strongest[effect]
	if best ~= nil and rank <= best then
		return false
	end
	sweep.strongest[effect] = rank
	return true
end

-- True when `effect` of moment `name` plays for this client.
local function allowed(name: string, effect: string, involved: boolean, position: Vector3?): boolean
	local who = Moments.audienceOf(name, effect)
	if who == "Always" or involved then
		return true
	end
	if who == "Involved" or position == nil then
		return false
	end
	local eye = viewer()
	if eye == nil then
		return false
	end
	return (position - eye).Magnitude <= Moments.rangeOf(name)
end

-- ------------------------------------------------------------------ geometry

--- The swing tangent for a hit: Trails.swingDirection(attacker), else the horizontal direction
--- from the attacker to the target, else the camera's right vector; nil when none is known.
function Impact.swingTangent(info: HitInfo): Vector3?
	local attacker = info.attacker
	if attacker ~= nil then
		local swing = unit(call("trails", "swingDirection", attacker))
		if swing ~= nil then
			return swing
		end
		local from = positionOf(attacker)
		local to = positionOf(info.target)
		if from ~= nil and to ~= nil then
			local delta = to - from
			local flat = unit(Vector3.new(delta.X, 0, delta.Z))
			if flat ~= nil then
				return flat
			end
		end
	end
	return unit(cameraRight())
end

-- `normal` turned about the unit tangent `t` toward the camera (`toCamera` points from the hit to
-- it): just far enough that the crescent's face is at most tilt.faceDegrees off the camera, as far
-- as turning about the swing can bring it, and never more than tilt.maxDegrees. Unchanged without a
-- camera direction or when the camera looks straight along the swing.
local function towardCamera(t: Vector3, normal: Vector3, toCamera: Vector3?): Vector3
	local view = unit(toCamera)
	if view == nil then
		return normal
	end
	local v = view :: Vector3
	local reach = (v - t * v:Dot(t)).Magnitude -- the camera direction seen around the swing axis
	if reach <= Moments.epsilon then
		return normal
	end
	local side = t:Cross(normal)
	local facing = normal:Dot(v)
	local across = side:Dot(v)
	local off = math.deg(math.acos(math.clamp(math.abs(facing) / reach, 0, 1)))
	local tilt = Accents.slashArc.tilt
	local turn = math.clamp(off - tilt.faceDegrees, 0, tilt.maxDegrees)
	if turn <= 0 then
		return normal
	end
	-- Turn the way that opens the face to the camera, whichever side of the plane it is on.
	local sign = (if facing < 0 then -1 else 1) * (if across < 0 then -1 else 1)
	local radians = math.rad(turn)
	return (normal * math.cos(radians) + side * (sign * math.sin(radians))).Unit
end

--- The crescent's plane normal for a tangent: the true swing plane (`radial`, the hit point minus
--- the attacker, crossed with the tangent) when the swing runs across its radius, else tangent x
--- up, else the camera's right vector when the swing is vertical; then turned toward the camera
--- (`toCamera`, the hit to the camera) when it would read edge-on. nil when no plane is known.
function Impact.planeNormal(tangent: Vector3, radial: Vector3?, toCamera: Vector3?): Vector3?
	local t = unit(tangent)
	if t == nil then
		return nil
	end
	local along = t :: Vector3
	local normal: Vector3? = nil
	local r = unit(radial)
	if r ~= nil then
		local cross = (r :: Vector3):Cross(along)
		if cross.Magnitude >= Accents.slashArc.tilt.minPlaneSine then
			normal = cross.Unit
		end
	end
	normal = normal or unit(along:Cross(Vector3.yAxis)) or unit(cameraRight())
	if normal == nil then
		return nil
	end
	return towardCamera(along, normal :: Vector3, toCamera)
end

--- The clip time of a clip's first ActivationHold; nil when it has none (pure).
function Impact.holdTime(clip: any): number?
	if typeof(clip) ~= "table" or typeof(clip.events) ~= "table" then
		return nil
	end
	local hold: number? = nil
	for _, event in clip.events do
		if event.kind == "ActivationHold" and (hold == nil or event.time < (hold :: number)) then
			hold = event.time
		end
	end
	return hold
end

--- The clip time of a clip's first HitWindowOpen at or after `clipTime`; nil when none (pure).
function Impact.windowAfter(clip: any, clipTime: number): number?
	if typeof(clip) ~= "table" or typeof(clip.events) ~= "table" then
		return nil
	end
	local window: number? = nil
	for _, event in clip.events do
		if
			event.kind == "HitWindowOpen"
			and event.time >= clipTime
			and (window == nil or event.time < (window :: number))
		then
			window = event.time
		end
	end
	return window
end

--- Seconds from a clip's ActivationHold to its first HitWindowOpen at or after it; nil when the
--- clip has no ActivationHold or no window after it (pure).
function Impact.riserLead(clip: any): number?
	local hold = Impact.holdTime(clip)
	if hold == nil then
		return nil
	end
	local window = Impact.windowAfter(clip, hold :: number)
	if window == nil then
		return nil
	end
	return (window :: number) - (hold :: number)
end

-- ------------------------------------------------------------------ moments

--- The moment a confirmed hit is (moments.luau select rules, first match wins).
function Impact.select(info: HitInfo): string
	return Moments.selectFor(info :: any)
end

--- True when the hit's moment flashes the target's Highlight itself (Replication then skips its
--- white flash for it).
function Impact.ownsHighlight(info: HitInfo): boolean
	return Moments.byId(Impact.select(info)).highlight ~= nil
end

--- Seconds the impact frames still hide the 3D world on this screen (0 when none): Replication
--- holds its own world-space accents (the parry's trail flash and sparks) for them.
function Impact.hiddenSeconds(): number
	if deps.impactFrames == nil then
		return 0
	end
	local hidden = call("impactFrames", "hiddenSeconds")
	return if typeof(hidden) == "number" and hidden > 0 then hidden else 0
end

-- Runs `fn` once no impact frames hide the world on this screen. A picture that grew while it
-- waited (the kill of a sweep turns its first hits' two frames into the kill's six) holds it again.
local function afterHidden(fn: () -> ())
	local wait = Impact.hiddenSeconds()
	if wait <= 0 then
		fn()
		return
	end
	after(wait, function()
		afterHidden(fn)
	end)
end

-- The Switch row's trail flash on a Switch hit (both blades flash, section 11).
local function switchFlash(name: string, row: Moments.Moment, info: HitInfo)
	local flash = row.trailFlash
	if flash ~= nil and allowed(name, "TrailFlash", info.involved, info.position) then
		if info.attacker ~= nil then
			call("trails", "flashWhite", info.attacker, flash.frames)
		end
		if flash.partner and info.partner ~= nil and info.partner ~= info.attacker then
			call("trails", "flashWhite", info.partner, flash.frames)
		end
	end
end

-- The Switch row's sound on a Switch hit (once per sweep).
local function switchSound(name: string, row: Moments.Moment, info: HitInfo)
	local sound = row.sound
	if
		sound ~= nil
		and allowed(name, "Sound", info.involved, info.position)
		and firstInSweep(info, "Sound:" .. sound)
	then
		call("sfx", "play", sound, info.position)
	end
end

-- The Switch layer a hit carries: its own row on a Switch moment, else the Switch row when another
-- rule claimed a Switch hit and that row layers on.
local function switchRow(name: string, row: Moments.Moment, info: HitInfo): (string?, Moments.Moment?)
	if name == "Switch" then
		return name, row
	end
	if info.isSwitch then
		local switch = Moments.byId("Switch")
		if switch.layerOnSwitch then
			return "Switch", switch
		end
	end
	return nil, nil
end

--- Fires everything a confirmed hit's moment names; returns the moment's name.
function Impact.hit(info: HitInfo): string
	local name = Impact.select(info)
	local row = Moments.byId(name)
	local position = info.position
	local involved = info.involved
	local switchName, switch = switchRow(name, row, info)

	-- The sound first, so its crack starts on the same frame as the picture; one per sweep.
	local cue = row.cue
	if cue ~= nil and allowed(name, "Cue", involved, position) then
		local heardAt = cueInSweep(info, cue, row.hitStop, position)
		if heardAt ~= nil then
			call("sfx", "cue", cue, heardAt)
		end
	end
	if switchName ~= nil and switch ~= nil then
		switchSound(switchName, switch, info)
	end

	local wantsArc = row.slashArc ~= nil and allowed(name, "SlashArc", involved, position)
	local wantsLine = row.slashLine ~= nil and allowed(name, "SlashLine", involved, position)
	local wantsFrames = row.impactSequence ~= nil and allowed(name, "ImpactFrames", involved, position)
	if wantsFrames and not strongestInSweep(info, "Frames", row.hitStop) and Impact.hiddenSeconds() <= 0 then
		-- One sweep, one picture: a later hit of it joins the picture while it shows, and once that
		-- has ended only a stronger hit-stop draws again (a sweep confirmed over frames never twice).
		wantsFrames = false
	end
	local tangent = if wantsArc or wantsLine or wantsFrames then Impact.swingTangent(info) else nil

	if wantsFrames then
		local models: { Model } = {}
		if info.attacker ~= nil then
			table.insert(models, info.attacker :: Model)
		end
		if info.target ~= nil and info.target ~= info.attacker then
			table.insert(models, info.target :: Model)
		end
		local project = deps.screenDirection
		local slashDirection = if tangent ~= nil and project ~= nil then project(position, tangent) else nil
		call(
			"impactFrames",
			"play",
			row.impactSequence,
			models,
			{ slashDirection = slashDirection, now = now(), position = position }
		)
	end

	-- The 3D accents, after whatever impact frames hide the world on this screen (this hit's, or
	-- another's still showing).
	afterHidden(function()
		local glint = row.glint
		if glint ~= nil and allowed(name, "Glint", involved, position) then
			local token = if glint.trailTint then info.trailToken else glint.token
			call("glint", "play", position, glint.size, token)
		end
		if tangent ~= nil then
			local arc = row.slashArc
			if wantsArc and arc ~= nil then
				local from = positionOf(info.attacker)
				local eye = viewer()
				local normal = Impact.planeNormal(
					tangent,
					if from ~= nil then position - from else nil,
					if eye ~= nil then eye - position else nil
				)
				if normal ~= nil then
					call("slashArc", "play", position, tangent, normal, info.trailToken, arc.size)
				end
			end
			local line = row.slashLine
			if wantsLine and line ~= nil then
				call("slashArc", "line", position, tangent, line.size)
			end
		end
		local highlight = row.highlight
		if highlight ~= nil and info.target ~= nil and allowed(name, "Highlight", involved, position) then
			local token = if highlight.trailTint then info.trailToken else highlight.token
			call("outline", "flash", info.target, token, highlight.frames)
		end
		if switchName ~= nil and switch ~= nil then
			switchFlash(switchName, switch, info)
		end
	end)

	local contour = row.contour
	if
		contour ~= nil
		and allowed(name, "Contour", involved, position)
		and strongestInSweep(info, "Contour", row.hitStop)
	then
		call("sfx", "contour", contour)
	end
	local punch = row.punch
	if punch ~= nil and allowed(name, "Punch", involved, position) and strongestInSweep(info, "Punch", row.hitStop) then
		call("camera", "punch", punch)
	end
	return name
end

-- The riser that ends `seconds` from now (skipped under the row's minLeadSeconds).
local function riserEndingIn(name: string, row: Moments.Moment, seconds: number, isLocal: boolean, position: Vector3?)
	local riser = row.riser
	if riser == nil or not allowed(name, "Riser", isLocal, position) then
		return
	end
	if seconds < riser.minLeadSeconds then
		return
	end
	local at = if isLocal and not riser.spatialForLocal then nil else position
	call("sfx", "playEndingAt", riser.sound, seconds, at)
end

local function rateOf(speed: number?): number
	return if speed ~= nil and speed > 0 then speed else 1
end

--- An Art's activation on a rig (call it on the clip's ActivationHold event). A remote fighter's
--- clip plays straight through: the riser ends on its first HitWindowOpen, (window - hold) /
--- speed later (`speed` is the clip's playback speed, 1 when nil), less `lateBy` seconds when a
--- late start jumped over the hold. The local fighter's clip waits at the hold pose: they get the
--- wind-up contour now, and the riser from `release`.
function Impact.activation(
	model: Model,
	clipId: string,
	_trailToken: string,
	isLocal: boolean,
	speed: number?,
	lateBy: number?
)
	local name = "Activation"
	local row = Moments.byId(name)
	local position = positionOf(model)
	if isLocal then
		if row.contour ~= nil and allowed(name, "Contour", isLocal, position) then
			call("sfx", "contour", row.contour)
		end
		return
	end
	if row.riser == nil or not allowed(name, "Riser", isLocal, position) then
		return
	end
	local lead = Impact.riserLead(call("clipLibrary", "get", clipId))
	if lead == nil then
		return
	end
	local late = if lateBy ~= nil and lateBy > 0 then lateBy else 0
	riserEndingIn(name, row, (lead :: number) / rateOf(speed) - late, isLocal, position)
end

--- The local fighter let the Art key up and the clip launches: the riser ends on the clip's first
--- HitWindowOpen at or after `clipTime` (where the clip waits), which comes `frozenSeconds` (the
--- controller's freeze after release) plus the clip time between them over `speed` from now; the
--- wind-up contour's release lands there too.
function Impact.release(model: Model, clipId: string, clipTime: number, frozenSeconds: number, speed: number?)
	local name = "Activation"
	local row = Moments.byId(name)
	local position = positionOf(model)
	local window = Impact.windowAfter(call("clipLibrary", "get", clipId), clipTime)
	local seconds = if window ~= nil
		then math.max(frozenSeconds, 0) + ((window :: number) - clipTime) / rateOf(speed)
		else nil
	local release = row.releaseContour
	if release ~= nil and allowed(name, "Contour", true, position) then
		local contour = release :: string
		after(if seconds ~= nil then seconds :: number else 0, function()
			call("sfx", "contour", contour)
		end)
	end
	if seconds ~= nil then
		riserEndingIn(name, row, seconds :: number, true, position)
	end
end

--- The local fighter let a held Art go past the cancel time (or the hold was cleared): the
--- wind-up contour ends at once.
function Impact.cancelActivation(model: Model?)
	local name = "Activation"
	local row = Moments.byId(name)
	local release = row.releaseContour
	if release ~= nil and allowed(name, "Contour", true, positionOf(model)) then
		call("sfx", "contour", release)
	end
end

--- A dodge: speed lines on the dodging fighter's own screen, the cue for everyone in range.
--- `lateBy` is how far into the dodge clip a remote catch-up started it (seconds), so the cue's
--- layers stay on the clip's clock.
function Impact.dodge(model: Model, isLocal: boolean, lateBy: number?)
	local name = "Dodge"
	local row = Moments.byId(name)
	local position = positionOf(model)
	local lines = row.speedLines
	if lines ~= nil and allowed(name, "SpeedLines", isLocal, position) then
		call("speedLines", "play", lines.kind)
	end
	if row.cue ~= nil and allowed(name, "Cue", isLocal, position) then
		call("sfx", "cue", row.cue, position, lateBy)
	end
end

-- A guard moment's cue and extra sound at the fighter, for this client when allowed.
local function guardMoment(name: string, model: Model?, isLocal: boolean)
	local row = Moments.byId(name)
	local position = positionOf(model)
	if row.cue ~= nil and allowed(name, "Cue", isLocal, position) then
		call("sfx", "cue", row.cue, position)
	end
	if row.sound ~= nil and allowed(name, "Sound", isLocal, position) then
		call("sfx", "play", row.sound, position)
	end
end

--- A guard broke (StateChanged GuardBroken): the GuardBreak cue at the fighter.
function Impact.guardBreak(model: Model?, isLocal: boolean)
	guardMoment("GuardBreak", model, isLocal)
end

--- A guard went up: the raise at the fighter (the local fighter's is predicted on the key press).
function Impact.guardRaise(model: Model?, isLocal: boolean)
	guardMoment("GuardRaise", model, isLocal)
end

--- The cue a shatter plays (moments.luau death rows): the boss's, a player's or an Elite's heavy
--- one, else a mob's.
function Impact.shatterCue(boss: boolean, heavy: boolean?): string
	local cue = Moments.byId(Moments.deathFor(boss, heavy)).shatterCue
	return if cue ~= nil then cue else Moments.byId("Death").shatterCue :: string
end

--- A death, as its shatter starts: the bloom contour for everyone in range. The shatter's own cue
--- is Shatter.luau's (SfxPool.shatter, the cue from `shatterCue`), never played here.
function Impact.death(_model: Model?, position: Vector3, boss: boolean, heavy: boolean?)
	local name = Moments.deathFor(boss, heavy)
	local row = Moments.byId(name)
	if row.contour ~= nil and allowed(name, "Contour", false, position) then
		call("sfx", "contour", row.contour)
	end
end

-- ------------------------------------------------------------------ binding

--- Installs the dependencies (specs pass fakes; a missing one is logged once when first needed).
function Impact.bind(newDeps: Deps)
	deps = newDeps
	table.clear(reported)
	table.clear(sweeps)
	table.clear(ownSweeps)
end

-- The tangent projected through the current camera into a screen direction (x right, y down).
local function projectDirection(position: Vector3, direction: Vector3): Vector2?
	local camera = Engine.camera()
	if camera == nil then
		return nil
	end
	local from = camera:WorldToViewportPoint(position)
	local to = camera:WorldToViewportPoint(position + direction)
	if from.Z <= 0 or to.Z <= 0 then
		return nil
	end
	local delta = Vector2.new(to.X - from.X, to.Y - from.Y)
	if delta.Magnitude <= Moments.epsilon then
		return nil
	end
	return delta.Unit
end

--- Binds the real modules (a missing one logs once through Siblings and its effects are skipped).
function Impact.start()
	if started then
		return
	end
	started = true
	local Client = script.Parent.Parent
	local real: Deps = {
		now = Engine.now,
		viewerPosition = Engine.viewerPosition,
		positionOf = Engine.modelPosition,
		screenDirection = projectDirection,
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
	}
	local missing: { string } = {}
	for name, path in MODULES do
		local module, loaded = Siblings.load(Client, path)
		if loaded then
			(real :: any)[name] = module
		else
			table.insert(missing, name)
		end
	end
	Impact.bind(real)
	-- Siblings has logged each missing module once already.
	for _, name in missing do
		reported[name] = true
	end
end

return Impact
