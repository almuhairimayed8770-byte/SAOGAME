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
	target, else the camera's right vector. The crescent's plane normal is tangent x up, else the
	camera's right vector when the swing is vertical. The strokes' screen direction is the tangent
	projected through the camera.

	Order on a hit: the cue first (its crack starts with the picture), then the impact frames;
	the 3D accents (glint, crescent, slash line, the Highlight flash, the Switch trail flash) wait
	while the impact frames hide the world for this viewer (ImpactFrames.hiddenSeconds: a
	ScreenGui draws over BillboardGuis, Beams and Highlights), then play, so the white flash and
	the slash line are seen after the frames, as in the reel. The contour and the punch start at
	once.

	The activation riser ends on the clip's first damage frame (its first HitWindowOpen after the
	ActivationHold). A remote fighter's clip plays straight through (its ArtRequest was sent on
	release), so `activation`, called on the ActivationHold event, ends the riser
	(window - hold) / speed later. The local fighter's clip waits at the hold pose until the key
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
	art: boolean?, -- an Art's hit (HitConfirmed carries an artId); only an Art's final hit is FinalHit
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

--- The crescent's plane normal for a tangent: tangent x up, else the camera's right vector when
--- the swing is vertical; nil when neither is known.
function Impact.planeNormal(tangent: Vector3): Vector3?
	return unit(tangent:Cross(Vector3.yAxis)) or unit(cameraRight())
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

-- The Switch row's sound on a Switch hit.
local function switchSound(name: string, row: Moments.Moment, info: HitInfo)
	if row.sound ~= nil and allowed(name, "Sound", info.involved, info.position) then
		call("sfx", "play", row.sound, info.position)
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

	-- The sound first, so its crack starts on the same frame as the picture.
	if row.cue ~= nil and allowed(name, "Cue", involved, position) then
		call("sfx", "cue", row.cue, position)
	end
	if switchName ~= nil and switch ~= nil then
		switchSound(switchName, switch, info)
	end

	local wantsArc = row.slashArc ~= nil and allowed(name, "SlashArc", involved, position)
	local wantsLine = row.slashLine ~= nil and allowed(name, "SlashLine", involved, position)
	local wantsFrames = row.impactSequence ~= nil and allowed(name, "ImpactFrames", involved, position)
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
	local hidden = if deps.impactFrames ~= nil then call("impactFrames", "hiddenSeconds") else nil
	local wait = if typeof(hidden) == "number" and hidden > 0 then hidden else 0
	after(wait, function()
		local glint = row.glint
		if glint ~= nil and allowed(name, "Glint", involved, position) then
			local token = if glint.trailTint then info.trailToken else glint.token
			call("glint", "play", position, glint.size, token)
		end
		if tangent ~= nil then
			local arc = row.slashArc
			if wantsArc and arc ~= nil then
				local normal = Impact.planeNormal(tangent)
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

	if row.contour ~= nil and allowed(name, "Contour", involved, position) then
		call("sfx", "contour", row.contour)
	end
	if row.punch ~= nil and allowed(name, "Punch", involved, position) then
		call("camera", "punch", row.punch)
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
--- speed later (`speed` is the clip's playback speed, 1 when nil). The local fighter's clip
--- waits at the hold pose: they get the wind-up contour now, and the riser from `release`.
function Impact.activation(model: Model, clipId: string, _trailToken: string, isLocal: boolean, speed: number?)
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
	riserEndingIn(name, row, (lead :: number) / rateOf(speed), isLocal, position)
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
function Impact.dodge(model: Model, isLocal: boolean)
	local name = "Dodge"
	local row = Moments.byId(name)
	local position = positionOf(model)
	local lines = row.speedLines
	if lines ~= nil and allowed(name, "SpeedLines", isLocal, position) then
		call("speedLines", "play", lines.kind)
	end
	if row.cue ~= nil and allowed(name, "Cue", isLocal, position) then
		call("sfx", "cue", row.cue, position)
	end
end

--- A death, as its shatter starts: the bloom contour for everyone in range. The shatter's own cue
--- is Shatter.luau's (SfxPool.shatter), never played here.
function Impact.death(_model: Model?, position: Vector3, boss: boolean)
	local name = if boss then "BossDeath" else "Death"
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
