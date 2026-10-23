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

	The fallback idle (the rig's idle the animator plays the frame a rig appears) fires its events
	only while it is the Base layer's idle: hidden under another Base clip it keeps its clock but
	reports nothing it crosses, so its sounds never double the clip that shows (D-123).
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
}

export type FiredEvent = { clipId: string, event: Types.ClipEvent, handle: Handle }

export type StepResult = {
	offsets: Offsets,
	events: { FiredEvent },
	rootDelta: Types.Vec3,
	finished: { Handle },
	paused: boolean,
}

export type Mixer = {
	play: (self: Mixer, clip: Types.ClipDef, opts: PlayOptions?) -> Handle,
	stop: (self: Mixer, target: Handle | string, blendOut: number?) -> (),
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
	lastOffsets: (self: Mixer) -> Offsets,
	clear: (self: Mixer) -> (),
}

local ZERO: Types.Vec3 = { 0, 0, 0 }
local REST: ClipSampler.Offset = { pos = ZERO, rot = ZERO }
local LAYER_ORDER: { Types.ClipLayer } = ChoreoData.layerOrder

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

function Mixer.hitStop(self: any, frames: number)
	self._pause = math.max(self._pause, math.max(0, frames) * ChoreoData.frameSeconds)
end

function Mixer.pauseRemaining(self: any): number
	return self._pause
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
local function collectEvents(handle: Handle, from: number, to: number, inclusive: boolean, into: { FiredEvent })
	for _, event in handle.clip.events do
		local after = if inclusive then event.time >= from else event.time > from
		if after and event.time <= to then
			table.insert(into, { clipId = handle.clipId, event = event, handle = handle })
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

-- Advances one handle's clock and collects crossed events and the root-motion delta.
local function advance(handle: Handle, dt: number, paused: boolean, events: { FiredEvent }, rootDelta: Types.Vec3)
	local clip = handle.clip
	if dt <= 0 or (paused and not handle.ignorePause) then
		return
	end
	local previous = handle.time
	local inclusive = handle.fresh
	handle.fresh = false
	local target = previous + dt * handle.speed
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
		collectEvents(handle, previous, duration, inclusive, events)
		local rest = target - duration
		collectEvents(handle, 0, rest, true, events)
		target = rest % duration
	else
		collectEvents(handle, previous, target, inclusive, events)
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

-- Per layer, the fraction of the remaining distance every retargeted blend-space weight moves
-- this step: the largest mover travels `dt * weightBlendRate` and the rest keep pace, so the
-- layer's weight sum moves straight to its target sum (and holds when the two agree). The
-- fraction reaches 1 on the last step, so every weight lands exactly on its target.
local function weightFractions(handles: { Handle }, dt: number, paused: boolean): { [string]: number }
	local largest: { [string]: number } = {}
	for _, handle in handles do
		local frozen = paused and not handle.ignorePause
		if not handle.fallback and not handle.done and not frozen then
			local delta = math.abs(handle.targetWeight - handle.weight)
			largest[handle.layer] = math.max(largest[handle.layer] or 0, delta)
		end
	end
	local fractions: { [string]: number } = {}
	local reach = dt * ChoreoData.locomotion.weightBlendRate
	for layer, delta in largest do
		fractions[layer] = if delta <= reach then 1 else reach / delta
	end
	return fractions
end

local function byPriority(a: Handle, b: Handle): boolean
	if a.priority == b.priority then
		return a.id < b.id
	end
	return a.priority < b.priority
end

-- Adds `offsets` scaled by `weight` into `result`, replacing each touched entry with a new table:
-- a sampled entry can alias the clip's own key arrays (ClipSampler holds them by reference at the
-- ends of a clip), and clip data is never written. Untouched entries are left as they are.
local function addInto(result: Offsets, offsets: Offsets, weight: number)
	for name, offset in offsets do
		local base = result[name] or REST
		result[name] = {
			pos = {
				base.pos[1] + offset.pos[1] * weight,
				base.pos[2] + offset.pos[2] * weight,
				base.pos[3] + offset.pos[3] * weight,
			},
			rot = {
				base.rot[1] + offset.rot[1] * weight,
				base.rot[2] + offset.rot[2] * weight,
				base.rot[3] + offset.rot[3] * weight,
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

function Mixer.step(self: any, dt: number): StepResult
	local paused = self._pause > ChoreoData.pauseEpsilon
	if paused then
		self._pause = self._pause - dt
	end
	-- Snap the float residue of the last frame to zero so pauseRemaining agrees with the clocks.
	if self._pause <= ChoreoData.pauseEpsilon then
		self._pause = 0
	end
	local scaledDt = dt * self._timeScale

	-- Fallback idle: visible only while no other Base clip is active.
	local baseActive = false
	for _, handle in self._handles do
		if handle.layer == "Base" and not handle.fallback and not handle.stopping then
			baseActive = true
			break
		end
	end

	local events: { FiredEvent } = {}
	-- A fallback idle hidden under another Base clip fires nothing: its sounds belong to the clip
	-- that shows (an enemy's own idle plays the same loop at its own phase, D-123).
	table.clear(hiddenEvents)
	local finished: { Handle } = {}
	local rootDelta: Types.Vec3 = { 0, 0, 0 }
	local fractions = weightFractions(self._handles, dt, paused)

	for _, handle in self._handles do
		-- A paused handle holds everything: clock, blend envelope and blend-space weight.
		local frozen = paused and not handle.ignorePause
		if not frozen then
			-- Envelope
			if handle.stopping then
				handle.fade = if handle.blendOut <= 0 then 0 else math.max(0, handle.fade - dt / handle.blendOut)
				if handle.fade <= 0 then
					handle.done = true
				end
			elseif handle.fade < 1 then
				handle.fade = if handle.blendIn <= 0 then 1 else math.min(1, handle.fade + dt / handle.blendIn)
			end
			-- External weight (fallback idle is driven by the mixer, others by the caller)
			if handle.fallback then
				handle.targetWeight = if baseActive then 0 else 1
				local rate = dt / ChoreoData.fallbackBlend
				handle.weight = handle.weight + math.clamp(handle.targetWeight - handle.weight, -rate, rate)
			elseif handle.weight ~= handle.targetWeight then
				local fraction = fractions[handle.layer] or 1
				if fraction >= 1 then
					handle.weight = handle.targetWeight
				else
					handle.weight += (handle.targetWeight - handle.weight) * fraction
				end
			end
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
			advance(handle, if handle.ignorePause then dt else scaledDt, paused, into, rootDelta)
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
					addInto(result, ClipSampler.sample(handle.clip, handle.time), weight)
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
	return { offsets = result, events = events, rootDelta = rootDelta, finished = finished, paused = paused }
end

Mixer.layerRank = layerRank

return Mixer
