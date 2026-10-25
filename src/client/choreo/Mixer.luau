--!strict
--[[
	Mixer: the pure core of the Choreo animator (section 10 "Choreo").

	One Mixer per rig. It owns the clip handles on four layers, advances their clocks, blends them
	into one set of joint offsets per step and reports crossed events, the root-motion delta and
	finished handles. It never touches an Instance, so every rule here is Lune-tested; Choreo.luau
	binds it to RenderStepped and to each joint's Transform (a Motor6D or an AnimationConstraint).

	Layers (data/choreo.luau layerOrder): Base (locomotion blend space), UpperBody (actions that
	leave the legs to locomotion), FullBody (Arts, dodges, staggers: override everything below for
	the joints they key) and Additive (breathing, lean, flinch, foot IK; added on top).

	The clock: every handle has its own time and speed; the mixer has a time scale (Tempo,
	Quickness) and a pause (hit-stop: a frame count at 1/60 s during which no clock advances and
	the rig holds its pose: no blend envelope or blend-space weight moves either). A handle started
	with a server time jumps to the matching position. Handles that ignore the pause (the death
	tremor) run on the unscaled frame time, so a time scale of zero freezes everything but them.

	Inside an override layer, priority wins: the handles of each priority group are mixed by their
	weights and laid over the lower groups, so a locomotion one-shot that fires under an Art never
	shows through it, while a lower clip blending in under a stopping higher one does.

	No limb moves on a straight line between clips: a handle's envelope (`fade`) is linear progress,
	but the limbs see it through the data blendEasing curve. Blend-space weights retargeted on one
	layer all move by one shared fraction per step (the largest mover at weightBlendRate), so a
	blend space whose targets sum to 1 keeps summing to 1 and never dips toward the rest pose.

	Root motion is a gameplay displacement, not a visual: it is never attenuated by a clip's
	blend-in (the dodge travels its whole dodgeDistance) and only fades with a clip that is stopping.

	Render stalls (D-132): RenderStepped stops while the display sleeps or the window is minimised,
	and its first dt after waking is the whole gap. A step longer than choreo.luau
	stall.jumpSeconds is a jump. The clocks, envelopes and weights still take the whole gap (a
	hit-stop asked for during it ends inside it, and the rest of the gap moves the clocks), so
	nothing asked for during the stall plays out after the wake. The root takes none of it: the
	body stays where the server saw it through the gap. The events the gap crossed are still
	reported, each marked `jumped`, so the router closes what they close and starts nothing. A clip
	played inside the gap (the key press that woke the display, a remote's action that arrived just
	before the wake) is the present: it moves only by its own age, the step less its `sinceStep`,
	and that part is a jump only when it is longer than jumpSeconds itself.

	The fallback idle (the rig's idle the animator plays the frame a rig appears) fires its events
	only while it is the Base layer's idle: hidden under another Base clip it keeps its clock but
	reports nothing it crosses, so its sounds never double the clip that shows (D-123).

	The server's beat (D-172): an enemy's attack clip keeps the server's clock up to a mark (its
	first HitWindowOpen) through `keepBeat`. The rig's pause stays the only freeze: every step it
	holds the handle adds the held time to what the handle owes, and `shiftBeat` takes off what
	the server paused the attack for (HitConfirmed attackPause). Whatever is left the clip repays
	by running a little faster (or gives back by running a little slower) at the one rate that
	evens the balance by the mark (data/choreo.luau enemy.beat), so its strike lands on the
	server's beat and nothing freezes twice. Past the mark nothing is corrected.

	A play's `mask` scales an Additive clip per joint (a joint not listed keeps its full weight):
	an enemy's flinch during its attack leaves the weapon arm on the attack (D-173).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared.types)
local ClipSampler = require(Shared.choreo.ClipSampler)
local ChoreoData = require(Shared.data.choreo)
local Easing = require(Shared.util.Easing)

export type Offsets = ClipSampler.Offsets

export type PlayOptions = {
	startTime: number?, -- seconds into the clip
	serverTime: number?, -- with `now`: start at (now - serverTime) * speed, clamped (network catch-up)
	now: number?,
	speed: number?,
	layer: Types.ClipLayer?,
	priority: number?,
	blendIn: number?,
	blendOut: number?,
	weight: number?, -- external weight (blend-space weights, Land squash); default 1
	coexist: boolean?, -- do not fade out other handles on the layer (blend-space clips)
	fallback: boolean?, -- the auto Idle: fades out whenever another Base clip is active
	ignorePause: boolean?, -- keeps advancing through hit-stop (death tremor)
	-- Seconds between the mixer's last step and this play (the caller's clock). Only a jump reads
	-- it: the clip's first step then moves it by the step less this, its own age (D-132).
	sinceStep: number?,
	-- Additive clips only: joint name -> weight multiplier (a joint not listed keeps 1).
	mask: { [string]: number }?,
}

-- The server's beat a handle keeps (Mixer.keepBeat): the clip time it is kept up to and the real
-- seconds the clip runs behind the server there (negative: ahead).
export type Beat = {
	untilTime: number,
	owed: number,
}

export type Handle = {
	id: number,
	clipId: string,
	clip: Types.ClipDef,
	layer: Types.ClipLayer,
	priority: number,
	time: number,
	speed: number,
	fade: number, -- blend envelope 0..1 (linear progress; the limbs see it through blendEasing)
	weight: number, -- external weight 0..1
	targetWeight: number,
	blendIn: number,
	blendOut: number,
	stopping: boolean,
	done: boolean,
	ended: boolean, -- a non-looping clip reached its end
	coexist: boolean,
	fallback: boolean,
	ignorePause: boolean,
	hasRoot: boolean,
	lastRoot: Types.Vec3,
	fresh: boolean,
	sinceStep: number, -- PlayOptions.sinceStep until the handle's first step, then 0
	-- The authored hold a hit-stop stands in for (ClipSampler.strikeHoldAfter's key index, 0 for
	-- none) and how much of it, in clip seconds, the clock may skip when it gets there.
	absorbKey: number,
	absorbSeconds: number,
	mask: { [string]: number }?, -- PlayOptions.mask (Additive only)
	beat: Beat?, -- the server's beat it keeps (keepBeat), nil once past the mark
	held: boolean, -- Mixer.hold: the clock stands still (a stopped clip fading out where it was)
	-- The clock before the latest step moved it (the start time before the first step; a seek's
	-- time after one): the clip time the frame before showed. A reader of this step's pose samples
	-- the clip between the two (the trail ribbon's in-betweens, D-269).
	lastTime: number,
}

-- jumped: a render stall's gap crossed it (the step, or this handle's part of it, was a jump).
export type FiredEvent = { clipId: string, event: Types.ClipEvent, handle: Handle, jumped: boolean }

export type StepResult = {
	offsets: Offsets,
	events: { FiredEvent },
	rootDelta: Types.Vec3,
	finished: { Handle },
	paused: boolean,
	jumped: boolean, -- the step was longer than stall.jumpSeconds (a render stall's gap)
}

export type Mixer = {
	play: (self: Mixer, clip: Types.ClipDef, opts: PlayOptions?) -> Handle,
	stop: (self: Mixer, target: Handle | string, blendOut: number?) -> (),
	hold: (self: Mixer, handle: Handle) -> (),
	setWeight: (self: Mixer, handle: Handle, weight: number, immediate: boolean?) -> (),
	setSpeed: (self: Mixer, handle: Handle, speed: number) -> (),
	hitStop: (self: Mixer, frames: number) -> (),
	pauseRemaining: (self: Mixer) -> number,
	setTimeScale: (self: Mixer, scale: number) -> (),
	timeScale: (self: Mixer) -> number,
	setProcedural: (self: Mixer, name: string, offsets: Offsets?, weight: number?) -> (),
	isPlaying: (self: Mixer, clipId: string) -> boolean,
	find: (self: Mixer, clipId: string) -> Handle?,
	handles: (self: Mixer) -> { Handle },
	step: (self: Mixer, dt: number) -> StepResult,
	preview: (self: Mixer, handle: Handle, dt: number) -> number,
	seek: (self: Mixer, handle: Handle, clipTime: number) -> { FiredEvent },
	keepBeat: (self: Mixer, handle: Handle, untilTime: number, owed: number?) -> (),
	shiftBeat: (self: Mixer, handle: Handle, seconds: number) -> (),
	beatOwed: (self: Mixer, handle: Handle) -> number?,
	lastOffsets: (self: Mixer) -> Offsets,
	clear: (self: Mixer) -> (),
}

local ZERO: Types.Vec3 = { 0, 0, 0 }
local REST: ClipSampler.Offset = { pos = ZERO, rot = ZERO }
local LAYER_ORDER: { Types.ClipLayer } = ChoreoData.layerOrder
local BEAT = ChoreoData.enemy.beat

local Mixer = {}
Mixer.__index = Mixer

local nextHandleId = 0

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpOffset(a: ClipSampler.Offset, b: ClipSampler.Offset, t: number): ClipSampler.Offset
	return {
		pos = { lerp(a.pos[1], b.pos[1], t), lerp(a.pos[2], b.pos[2], t), lerp(a.pos[3], b.pos[3], t) },
		rot = { lerp(a.rot[1], b.rot[1], t), lerp(a.rot[2], b.rot[2], t), lerp(a.rot[3], b.rot[3], t) },
	}
end

local function layerRank(layer: Types.ClipLayer): number
	local index = table.find(LAYER_ORDER, layer)
	return index or #LAYER_ORDER + 1
end

--- Clip-clock position for a clip that started at `serverTime`: the elapsed time scaled by the
--- clip speed, clamped to the clip and to the catch-up limit so a late start still shows the strike.
function Mixer.catchUpStart(now: number, serverTime: number, speed: number, duration: number, maxJump: number?): number
	local elapsed = math.max(0, now - serverTime) * speed
	local limit = math.min(duration, maxJump or ChoreoData.catchUpMaxJump)
	return math.clamp(elapsed, 0, limit)
end

--- Creates an empty mixer.
function Mixer.new(): Mixer
	local self = setmetatable({
		_handles = {} :: { Handle },
		_procedural = {} :: { [string]: { offsets: Offsets, weight: number } },
		_pause = 0,
		_timeScale = 1,
		_last = {} :: Offsets,
	}, Mixer)
	return (self :: any) :: Mixer
end

function Mixer.play(self: any, clip: Types.ClipDef, opts: PlayOptions?): Handle
	local options: PlayOptions = opts or {}
	local layer = options.layer or clip.layer
	local priority = options.priority or clip.priority or 0
	local speed = options.speed or 1
	speed = math.clamp(speed, ChoreoData.minSpeed, ChoreoData.maxSpeed)
	local blendIn = options.blendIn or clip.blendIn or ChoreoData.blendIn
	local blendOut = options.blendOut or clip.blendOut or ChoreoData.blendOut

	local startTime = options.startTime or 0
	if options.serverTime ~= nil and options.now ~= nil then
		startTime = Mixer.catchUpStart(options.now, options.serverTime, speed, clip.duration)
	end
	if clip.loop and clip.duration > 0 then
		startTime = startTime % clip.duration
	else
		startTime = math.clamp(startTime, 0, clip.duration)
	end

	local coexist = options.coexist == true or options.fallback == true
	if not coexist then
		for _, other in self._handles do
			if other.layer == layer and not other.stopping and not other.coexist and other.priority <= priority then
				self:stop(other, blendOut)
			end
		end
	end

	-- A freeze clip (DeathFreeze) holds every other clock for its duration and rides on top.
	local isFreeze = clip.id:sub(-#ChoreoData.freezeClipSuffix) == ChoreoData.freezeClipSuffix
	if isFreeze then
		self._pause = math.max(self._pause, clip.duration - startTime)
	end

	nextHandleId += 1
	local hasRoot = table.find(ClipSampler.jointNames(clip), ClipSampler.ROOT_KEY) ~= nil
	local handle: Handle = {
		id = nextHandleId,
		clipId = clip.id,
		clip = clip,
		layer = layer,
		priority = priority,
		time = startTime,
		speed = speed,
		fade = if blendIn <= 0 then 1 else 0,
		weight = options.weight or 1,
		targetWeight = options.weight or 1,
		blendIn = blendIn,
		blendOut = blendOut,
		stopping = false,
		done = false,
		ended = false,
		coexist = coexist,
		fallback = options.fallback == true,
		ignorePause = options.ignorePause == true or isFreeze,
		hasRoot = hasRoot,
		lastRoot = if hasRoot then ClipSampler.rootMotionAt(clip, startTime) else ZERO,
		fresh = true,
		sinceStep = math.max(0, options.sinceStep or 0),
		absorbKey = 0,
		absorbSeconds = 0,
		mask = options.mask,
		beat = nil,
		held = false,
		lastTime = startTime,
	}
	table.insert(self._handles, handle)
	return handle
end

function Mixer.stop(self: any, target: Handle | string, blendOut: number?)
	if typeof(target) == "string" then
		for _, handle in self._handles do
			if handle.clipId == target and not handle.stopping then
				self:stop(handle, blendOut)
			end
		end
		return
	end
	local handle = target :: Handle
	if handle.stopping or handle.done then
		return
	end
	handle.stopping = true
	if blendOut ~= nil then
		handle.blendOut = blendOut
	end
	if handle.blendOut <= 0 then
		handle.fade = 0
	end
end

--- Stops a handle's clock where it is: from the next step on it shows that pose, fires no event
--- and moves no root, while its envelope and weight move as ever. A clip cut back (stopped because
--- the pose it was heading for is no longer wanted) fades out from where it was instead of playing
--- on into keys meant for a state that will not come (Sheathe's blade lined up with the back mount
--- while the sword stays in the hand).
function Mixer.hold(_self: any, handle: Handle)
	handle.held = true
end

function Mixer.setWeight(_self: any, handle: Handle, weight: number, immediate: boolean?)
	handle.targetWeight = math.clamp(weight, 0, 1)
	if immediate then
		handle.weight = handle.targetWeight
	end
end

--- Changes a handle's clock speed (stride sync: a walk clip paced to the rig's real speed).
function Mixer.setSpeed(_self: any, handle: Handle, speed: number)
	handle.speed = math.clamp(speed, ChoreoData.minSpeed, ChoreoData.maxSpeed)
end

--- Holds the rig `frames` frames (a hit-stop; a longer one already running is kept, never
--- restarted). The hold is the strike's beat 4 (section 10): an attack clip whose strike snap is
--- followed by an authored hold (a "Hold" key after the snap, the still beat a whiff shows) skips
--- up to the hit-stop's length of that hold when its clock reaches it, so a hit holds once, for
--- the longer of the two, never for both in a row (issue 6). The skipped stretch is still, so no
--- frame shows the skip; the events in it still fire.
function Mixer.hitStop(self: any, frames: number)
	local seconds = math.max(0, frames) * ChoreoData.frameSeconds
	self._pause = math.max(self._pause, seconds)
	if seconds <= 0 then
		return
	end
	for _, handle in self._handles do
		if handle.done or handle.ignorePause then
			continue
		end
		local index = ClipSampler.strikeHoldAfter(handle.clip, handle.time)
		if index == nil then
			continue
		end
		local budget = seconds * handle.speed
		if handle.absorbKey == index then
			handle.absorbSeconds = math.max(handle.absorbSeconds, budget)
		else
			handle.absorbKey = index
			handle.absorbSeconds = budget
		end
	end
end

function Mixer.pauseRemaining(self: any): number
	return self._pause
end

--- Keeps a handle on the server's beat up to clip time `untilTime` (D-172): from now on every step
--- the rig's pause holds it is owed back, less what `shiftBeat` says the server paused, and the
--- clip evens the balance by `untilTime`. `owed`: real seconds it already runs behind (a late
--- start the network catch-up could not jump all of). A handle at or past the mark keeps none.
function Mixer.keepBeat(_self: any, handle: Handle, untilTime: number, owed: number?)
	if handle.done or handle.stopping or handle.time >= untilTime then
		handle.beat = nil
		return
	end
	handle.beat = { untilTime = untilTime, owed = owed or 0 }
end

--- The server paused (positive) or un-paused (negative) the beat a handle keeps by `seconds`: the
--- clip owes that much less (more). A handle keeping no beat ignores it.
function Mixer.shiftBeat(_self: any, handle: Handle, seconds: number)
	local beat = handle.beat
	if beat ~= nil then
		beat.owed -= seconds
	end
end

--- Real seconds a handle runs behind the beat it keeps (negative: ahead), or nil when it keeps none.
function Mixer.beatOwed(_self: any, handle: Handle): number?
	local beat = handle.beat
	return if beat ~= nil then beat.owed else nil
end

function Mixer.setTimeScale(self: any, scale: number)
	self._timeScale = math.max(0, scale)
end

function Mixer.timeScale(self: any): number
	return self._timeScale
end

function Mixer.setProcedural(self: any, name: string, offsets: Offsets?, weight: number?)
	if offsets == nil then
		self._procedural[name] = nil
	else
		self._procedural[name] = { offsets = offsets, weight = weight or 1 }
	end
end

function Mixer.isPlaying(self: any, clipId: string): boolean
	for _, handle in self._handles do
		if handle.clipId == clipId and not handle.stopping then
			return true
		end
	end
	return false
end

function Mixer.find(self: any, clipId: string): Handle?
	for _, handle in self._handles do
		if handle.clipId == clipId and not handle.stopping then
			return handle
		end
	end
	return nil
end

function Mixer.handles(self: any): { Handle }
	return table.clone(self._handles)
end

function Mixer.lastOffsets(self: any): Offsets
	return self._last
end

function Mixer.clear(self: any)
	table.clear(self._handles)
	table.clear(self._procedural)
	self._pause = 0
end

-- Where a hidden fallback idle's crossed events go: dropped, cleared every step.
local hiddenEvents: { FiredEvent } = {}

-- Events with time in (from, to], or [from, to] when `inclusive` (the first step after play).
local function collectEvents(
	handle: Handle,
	from: number,
	to: number,
	inclusive: boolean,
	into: { FiredEvent },
	jumped: boolean
)
	for _, event in handle.clip.events do
		local after = if inclusive then event.time >= from else event.time > from
		if after and event.time <= to then
			table.insert(into, { clipId = handle.clipId, event = event, handle = handle, jumped = jumped })
		end
	end
end

-- Root offset of the last key that moves the root: the value a looping clip reaches at its end.
local function rootAtLastKey(clip: Types.ClipDef): Types.Vec3
	for index = #clip.keys, 1, -1 do
		local root = clip.keys[index].root
		if root ~= nil then
			return root.pos or ZERO
		end
	end
	return ZERO
end

-- Advances one handle's clock and collects crossed events (marked `jumped`) and the root-motion delta.
local function advance(
	handle: Handle,
	dt: number,
	paused: boolean,
	events: { FiredEvent },
	rootDelta: Types.Vec3,
	jumped: boolean
)
	local clip = handle.clip
	if dt <= 0 or (paused and not handle.ignorePause) then
		return
	end
	local previous = handle.time
	local inclusive = handle.fresh
	handle.fresh = false
	local target = previous + dt * handle.speed
	if handle.absorbKey > 0 then
		-- A hit-stop already held this strike: the clock skips the authored hold it stands in for.
		local keys = clip.keys
		local holdStart = keys[handle.absorbKey - 1].time
		local holdEnd = keys[handle.absorbKey].time
		if previous >= holdEnd then
			handle.absorbKey = 0
		elseif target > holdStart then
			target += math.min(handle.absorbSeconds, holdEnd - math.max(previous, holdStart))
			handle.absorbKey = 0
		end
	end
	local duration = clip.duration
	local wrapped = false
	if clip.loop and duration > 0 then
		if target >= duration then
			wrapped = true
		end
	elseif target >= duration then
		target = duration
		if not handle.ended then
			handle.ended = true
		end
	end

	-- Events
	if wrapped then
		collectEvents(handle, previous, duration, inclusive, events, jumped)
		local rest = target - duration
		collectEvents(handle, 0, rest, true, events, jumped)
		target = rest % duration
	else
		collectEvents(handle, previous, target, inclusive, events, jumped)
	end

	-- Root motion: the authored displacement in full while the clip plays (never cut by the
	-- blend-in), dying with the fade only once the clip is stopping (a cancelled prediction).
	if handle.hasRoot then
		local weight = handle.weight * (if handle.stopping then handle.fade else 1)
		local now = ClipSampler.rootMotionAt(clip, target)
		local delta: Types.Vec3
		if wrapped then
			local atEnd = rootAtLastKey(clip)
			local atStart = ClipSampler.rootMotionAt(clip, 0)
			delta = {
				(atEnd[1] - handle.lastRoot[1]) + (now[1] - atStart[1]),
				(atEnd[2] - handle.lastRoot[2]) + (now[2] - atStart[2]),
				(atEnd[3] - handle.lastRoot[3]) + (now[3] - atStart[3]),
			}
		else
			delta = { now[1] - handle.lastRoot[1], now[2] - handle.lastRoot[2], now[3] - handle.lastRoot[3] }
		end
		rootDelta[1] += delta[1] * weight
		rootDelta[2] += delta[2] * weight
		rootDelta[3] += delta[3] * weight
		handle.lastRoot = now
	end
	handle.time = target
end

-- What the limbs see of a handle: its eased envelope times its external weight. Root motion
-- reads the raw envelope instead (a gameplay displacement, validated by the server).
local function visibleWeight(handle: Handle): number
	return Easing.evaluate(ChoreoData.blendEasing, handle.fade) * handle.weight
end

-- The rule one step follows, in pieces Mixer.step and Mixer.preview share, so a caller that reads
-- the next step's blend ahead of it never copies (and drifts from) the step's own.

-- True while a pause of `pause` seconds still owes a step of `dt` (D-228 amended): at least half
-- of the step, give or take pauseEpsilon. A hold so counts the rendered frames nearest its length
-- at any refresh rate (3 frames at 60 Hz are 7 at 144 and 12 at 240, never the 6 and 10 a whole
-- last frame short), and a frame the hold owes only a sliver of is not frozen for it.
local function owes(pause: number, dt: number): boolean
	return pause > ChoreoData.pauseEpsilon and pause + ChoreoData.pauseEpsilon >= dt * 0.5
end

-- A step of `dt` with `pause` seconds of hit-stop left: the time the clocks (and envelopes and
-- weights) of handles that keep the pause move by, whether the step is a render stall's jump, and
-- whether the pause still holds. A hit-stop asked for during a stall that is over inside the gap
-- holds nothing: the rest of the gap moves the clocks.
local function clockStep(pause: number, dt: number): (number, boolean, boolean)
	local jumped = dt > ChoreoData.stall.jumpSeconds
	if jumped and pause > ChoreoData.pauseEpsilon and pause < dt then
		return dt - pause, jumped, false
	end
	return dt, jumped, owes(pause, dt)
end

-- One handle's part of a step: the seconds its envelope, weight and clock move by (a handle that
-- ignores the pause takes the whole step), and whether that part is a jump. A clip played inside a
-- jump's gap moves only by its own age, and that is a jump only when it is one too (D-132).
local function handleStep(handle: Handle, dt: number, clockDt: number, jumped: boolean): (number, boolean)
	local handleDt = if handle.ignorePause then dt else clockDt
	if jumped and handle.sinceStep > 0 then
		handleDt = math.max(0, handleDt - handle.sinceStep)
		return handleDt, handleDt > ChoreoData.stall.jumpSeconds
	end
	return handleDt, jumped
end

-- A moving handle's envelope after `handleDt`: a stopping one fades out over its blendOut, a new one
-- fades in over its blendIn.
local function fadeAfter(handle: Handle, handleDt: number): number
	if handle.stopping then
		return if handle.blendOut <= 0 then 0 else math.max(0, handle.fade - handleDt / handle.blendOut)
	elseif handle.fade < 1 then
		return if handle.blendIn <= 0 then 1 else math.min(1, handle.fade + handleDt / handle.blendIn)
	end
	return handle.fade
end

-- Whether any Base clip other than the fallback idle is live (the idle fades out under one).
local function baseActiveOf(handles: { Handle }): boolean
	for _, handle in handles do
		if handle.layer == "Base" and not handle.fallback and not handle.stopping then
			return true
		end
	end
	return false
end

-- How far a handle's retargeted blend-space weight still has to go this step, or nil for one the
-- step does not retarget (the fallback idle, a done handle, one the pause holds).
local function moveLeft(handle: Handle, paused: boolean): number?
	if handle.fallback or handle.done or (paused and not handle.ignorePause) then
		return nil
	end
	return math.abs(handle.targetWeight - handle.weight)
end

-- The fraction of the remaining distance every weight of a layer moves when its furthest mover
-- has `delta` to go: that one travels `dt * weightBlendRate` and the rest keep pace, so the layer's
-- weight sum moves straight to its target sum (and holds when the two agree). It reaches 1 on the
-- last step, so every weight lands exactly on its target.
local function fractionFor(delta: number, dt: number): number
	local reach = dt * ChoreoData.locomotion.weightBlendRate
	return if delta <= reach then 1 else reach / delta
end

-- Per layer, the fraction of the remaining distance every retargeted blend-space weight moves
-- this step (fractionFor of the layer's furthest mover).
local function weightFractions(handles: { Handle }, dt: number, paused: boolean): { [string]: number }
	local largest: { [string]: number } = {}
	for _, handle in handles do
		local delta = moveLeft(handle, paused)
		if delta ~= nil then
			largest[handle.layer] = math.max(largest[handle.layer] or 0, delta)
		end
	end
	local fractions: { [string]: number } = {}
	for layer, delta in largest do
		fractions[layer] = fractionFor(delta, dt)
	end
	return fractions
end

-- One layer's weightFractions entry, with no table.
local function layerFraction(handles: { Handle }, layer: Types.ClipLayer, dt: number, paused: boolean): number
	local largest = 0
	for _, handle in handles do
		local delta = moveLeft(handle, paused)
		if delta ~= nil and handle.layer == layer then
			largest = math.max(largest, delta)
		end
	end
	return fractionFor(largest, dt)
end

-- A moving handle's external weight after `handleDt`: the fallback idle moves at the data rate
-- toward 0 under a live Base clip and toward 1 without one; a retargeted weight moves its layer's
-- `fraction` of the way.
local function weightAfter(handle: Handle, handleDt: number, baseActive: boolean, fraction: number): number
	if handle.fallback then
		local target = if baseActive then 0 else 1
		local rate = handleDt / ChoreoData.fallbackBlend
		return handle.weight + math.clamp(target - handle.weight, -rate, rate)
	elseif handle.weight ~= handle.targetWeight then
		if fraction >= 1 then
			return handle.targetWeight
		end
		return handle.weight + (handle.targetWeight - handle.weight) * fraction
	end
	return handle.weight
end

local function byPriority(a: Handle, b: Handle): boolean
	if a.priority == b.priority then
		return a.id < b.id
	end
	return a.priority < b.priority
end

-- Adds `offsets` scaled by `weight` into `result`, replacing each touched entry with a new table:
-- a sampled entry can alias the clip's own key arrays (ClipSampler holds them by reference at the
-- ends of a clip), and clip data is never written. Untouched entries are left as they are. A
-- `mask` scales the joints it lists further (one it scales to nothing is left out).
local function addInto(result: Offsets, offsets: Offsets, weight: number, mask: { [string]: number }?)
	for name, offset in offsets do
		local scaled = weight
		if mask ~= nil then
			local scale = mask[name]
			if scale ~= nil then
				if scale <= 0 then
					continue
				end
				scaled = weight * scale
			end
		end
		local base = result[name] or REST
		result[name] = {
			pos = {
				base.pos[1] + offset.pos[1] * scaled,
				base.pos[2] + offset.pos[2] * scaled,
				base.pos[3] + offset.pos[3] * scaled,
			},
			rot = {
				base.rot[1] + offset.rot[1] * scaled,
				base.rot[2] + offset.rot[2] * scaled,
				base.rot[3] + offset.rot[3] * scaled,
			},
		}
	end
end

-- The normalized mix of handles[first..last] (one priority group) and the group's total weight.
local function mixGroup(handles: { Handle }, first: number, last: number): (Offsets, number)
	local total = 0
	for index = first, last do
		total += visibleWeight(handles[index])
	end
	if first == last then
		local handle = handles[first]
		return ClipSampler.sample(handle.clip, handle.time), total
	end
	local accumulated: Offsets = {}
	for index = first, last do
		local handle = handles[index]
		addInto(accumulated, ClipSampler.sample(handle.clip, handle.time), visibleWeight(handle) / total)
	end
	return accumulated, total
end

-- Lays one override layer over `result`: priority groups from the lowest up, each lerped over
-- what lies below by its own total weight, so a higher clip at full weight hides a lower one.
local function composeOverrideLayer(result: Offsets, handles: { Handle })
	local active: { Handle } = {}
	for _, handle in handles do
		if visibleWeight(handle) > 0 then
			table.insert(active, handle)
		end
	end
	if #active == 0 then
		return
	end
	table.sort(active, byPriority)
	local first = 1
	while first <= #active do
		local last = first
		while last < #active and active[last + 1].priority == active[first].priority do
			last += 1
		end
		local pose, total = mixGroup(active, first, last)
		local alpha = math.min(1, total)
		for name, offset in pose do
			if alpha >= 1 then
				result[name] = offset
			else
				result[name] = lerpOffset(result[name] or REST, offset, alpha)
			end
		end
		first = last + 1
	end
end

--- Moves one handle's clock forward to `clipTime` now, whatever the pause or the time scale, as if
--- it had played there (the Art hold a render stall kept from its hold pose, D-138): returns the
--- events it crosses, unmarked, each once (the next step goes on from there). The root it covers
--- goes nowhere: the next step's root delta starts at `clipTime`. A time at or before the handle's
--- own, or past a looping clip's end, moves nothing; a clip's end is the next step's to report.
function Mixer.seek(_self: any, handle: Handle, clipTime: number): { FiredEvent }
	local events: { FiredEvent } = {}
	local clip = handle.clip
	local target = math.min(clipTime, clip.duration)
	if handle.done or target <= handle.time or (clip.loop and target >= clip.duration) then
		return events
	end
	collectEvents(handle, handle.time, target, handle.fresh, events, false)
	handle.fresh = false
	if handle.hasRoot then
		handle.lastRoot = ClipSampler.rootMotionAt(clip, target)
	end
	handle.time = target
	-- A seek is no step a frame shows: nothing lies between it and the clock it left.
	handle.lastTime = target
	return events
end

-- One step of a handle that keeps the server's beat (D-172): `held` real seconds the rig's pause
-- held it are owed, then the clip moves by `clipDt` at the rate that evens what it owes by the
-- mark (within data/choreo.luau enemy.beat), never past an even balance. Returns the clip dt.
local function beatStep(handle: Handle, beat: Beat, held: number, clipDt: number): number
	beat.owed += held
	local owed = beat.owed
	if clipDt <= 0 or math.abs(owed) <= ChoreoData.pauseEpsilon then
		return clipDt
	end
	-- Real seconds to the mark at the clip's own rate, and the server's (it is `owed` nearer).
	local remaining = math.max(0, beat.untilTime - handle.time) / handle.speed
	local left = remaining - owed
	-- The server's mark falls inside this step: the whole balance is evened now, faster when the
	-- clip is behind and slower when it is ahead (never a frame further ahead: D-188).
	local rate = if left > clipDt then remaining / left elseif owed > 0 then BEAT.maxRate else BEAT.minRate
	rate = math.clamp(rate, BEAT.minRate, BEAT.maxRate)
	local gain = clipDt * (rate - 1)
	if (owed > 0 and gain > owed) or (owed < 0 and gain < owed) then
		gain = owed
	end
	beat.owed = owed - gain
	return clipDt + gain
end

--- What `handle`'s limbs will show once the next step of `dt` has moved its envelope and its
--- external weight: the eased envelope times the weight, read before that step runs, by the step's
--- own rule (a hit-stop holds it, a render stall's jump moves it by its own part of the gap, a stop
--- with no blend-out lands at once, a retargeted weight keeps its layer's pace). A done handle
--- shows 0. Not foreseen: a clip whose clock reaches its end in that step and stops there with no
--- blend-out (it shows its last pose until the step after).
function Mixer.preview(self: any, handle: Handle, dt: number): number
	if handle.done then
		return 0
	end
	local clockDt, jumped, paused = clockStep(self._pause, dt)
	local fade, weight = handle.fade, handle.weight
	if not paused or handle.ignorePause then
		local handleDt = handleStep(handle, dt, clockDt, jumped)
		fade = fadeAfter(handle, handleDt)
		local fraction = 1
		if not handle.fallback and handle.weight ~= handle.targetWeight then
			fraction = layerFraction(self._handles, handle.layer, clockDt, paused)
		end
		weight = weightAfter(handle, handleDt, handle.fallback and baseActiveOf(self._handles), fraction)
	elseif handle.stopping and handle.blendOut <= 0 then
		-- An immediate stop still lands during a pause.
		fade = 0
	end
	return Easing.evaluate(ChoreoData.blendEasing, fade) * weight
end

function Mixer.step(self: any, dt: number): StepResult
	-- The time the clocks (and envelopes and weights) of handles that keep the pause move by.
	local clockDt, jumped, paused = clockStep(self._pause, dt)
	if paused then
		self._pause = self._pause - dt
		-- What remains under half a step of this length is no frame of its own (D-228 amended): the
		-- hold ends here, so pauseRemaining agrees with the frames it froze.
		if not owes(self._pause, dt) then
			self._pause = 0
		end
	else
		-- A sliver no step is owed for, or a hit-stop asked for during a render stall that is over
		-- inside the gap (the rest of the gap moves the clocks): the hold is over.
		self._pause = 0
	end
	local timeScale = self._timeScale

	-- Fallback idle: visible only while no other Base clip is active.
	local baseActive = baseActiveOf(self._handles)

	local events: { FiredEvent } = {}
	-- A fallback idle hidden under another Base clip fires nothing: its sounds belong to the clip
	-- that shows (an enemy's own idle plays the same loop at its own phase, D-123).
	table.clear(hiddenEvents)
	local finished: { Handle } = {}
	local rootDelta: Types.Vec3 = { 0, 0, 0 }
	-- A jump's root motion goes nowhere: each handle's root still moves on to its new clip time.
	local jumpRoot: Types.Vec3 = { 0, 0, 0 }
	local fractions = weightFractions(self._handles, clockDt, paused)

	for _, handle in self._handles do
		-- A paused handle holds everything: clock, blend envelope and blend-space weight.
		local frozen = paused and not handle.ignorePause
		local handleDt, handleJumped = handleStep(handle, dt, clockDt, jumped)
		handle.sinceStep = 0
		handle.lastTime = handle.time
		local beat = handle.beat
		if beat ~= nil and (handle.stopping or handle.done or handle.time >= beat.untilTime) then
			-- Past the mark (or stopped): the beat is the strike's own from here.
			handle.beat = nil
			beat = nil
		end
		if not frozen then
			-- Envelope
			handle.fade = fadeAfter(handle, handleDt)
			if handle.stopping and handle.fade <= 0 then
				handle.done = true
			end
			-- External weight (fallback idle is driven by the mixer, others by the caller)
			if handle.fallback then
				handle.targetWeight = if baseActive then 0 else 1
			end
			handle.weight = weightAfter(handle, handleDt, baseActive, fractions[handle.layer] or 1)
		elseif handle.stopping and handle.blendOut <= 0 then
			-- An immediate stop still lands during a pause.
			handle.fade = 0
			handle.done = true
		end
		-- Clock (a handle that ignores the pause also ignores the time scale: the death tremor
		-- keeps running while the rest of the rig is frozen at scale zero).
		if not handle.done then
			local wasEnded = handle.ended
			local into = if handle.fallback and handle.targetWeight == 0 then hiddenEvents else events
			local clipDt = if handle.held then 0 elseif handle.ignorePause then handleDt else handleDt * timeScale
			if beat ~= nil and not handle.ignorePause then
				-- The rig's pause held it this step (all of it, or the part of a jump's gap it ended in).
				local held = if frozen then dt else math.max(0, dt - clockDt)
				clipDt = if frozen then 0 else beatStep(handle, beat, held, clipDt)
				if frozen then
					beat.owed += held
				end
			end
			advance(handle, clipDt, paused, into, if handleJumped then jumpRoot else rootDelta, handleJumped)
			if handle.ended and not wasEnded then
				table.insert(finished, handle)
				self:stop(handle)
			end
		end
	end

	-- Compose layers
	local result: Offsets = {}
	local layerHandles: { Handle } = {}
	for _, layer in LAYER_ORDER do
		table.clear(layerHandles)
		for _, handle in self._handles do
			if handle.layer == layer and not handle.done then
				table.insert(layerHandles, handle)
			end
		end
		if layer == "Additive" then
			for _, handle in layerHandles do
				local weight = visibleWeight(handle)
				if weight > 0 then
					addInto(result, ClipSampler.sample(handle.clip, handle.time), weight, handle.mask)
				end
			end
		else
			composeOverrideLayer(result, layerHandles)
		end
	end
	for _, channel in self._procedural do
		if channel.weight > 0 then
			addInto(result, channel.offsets, channel.weight)
		end
	end

	-- Drop finished handles
	for index = #self._handles, 1, -1 do
		if self._handles[index].done then
			table.remove(self._handles, index)
		end
	end

	self._last = result
	return {
		offsets = result,
		events = events,
		rootDelta = rootDelta,
		finished = finished,
		paused = paused,
		jumped = jumped,
	}
end

Mixer.layerRank = layerRank

return Mixer
