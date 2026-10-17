--!strict
--[[
	Choreo: the data-driven animator (section 10 "Choreo"). One animator per rig model; every
	frame it samples the active clips through the Mixer and writes the result as Motor6D.Transform
	on the named joints. Nothing here decides gameplay: it predicts motion, fires clip events and
	hands the root-motion delta to the CharacterController, which moves the HumanoidRootPart so
	the server can validate the displacement.

		local animator = Choreo.get(model)            -- posed the same frame (no T-pose, ever)
		local handle = animator:play("player/OneHandedSword/Horizontal", { serverTime = t })
		animator.events:Connect(function(clipId, event) ... end)
		animator:hitStop(frames)                      -- the rig holds; camera/FX read isPaused()
		animator:currentRootMotionDelta()             -- Vector3, rig-local studs since last frame
		Choreo.hitStopAll(models, "Final")
		Choreo.setQuality("Medium")

	Update rates: the local character and the nearest rigs step on RenderStepped; the rest step
	on Heartbeat at the quality tier's distant / far rate (data/choreo.luau quality). A clip id
	that looks like "rbxassetid://..." plays as a Roblox AnimationTrack on the same layer with the
	matching AnimationPriority, so hand-authored clips can replace data clips later.

	The engine surface (clocks, camera, frame signals) is one small table that tests replace with
	Choreo.configure; the logic underneath is the Lune-tested Mixer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared.types)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Signal = require(Shared.util.Signal)
local ChoreoData = require(Shared.data.choreo)
local CombatData = require(Shared.data.combat)
local Mixer = require(script.Parent.Mixer)
local ClipLibrary = require(script.Parent.ClipLibrary)

export type PlayOptions = {
	startTime: number?,
	speed: number?,
	layer: Types.ClipLayer?,
	priority: number?,
	blendIn: number?,
	blendOut: number?,
	serverTime: number?,
	weight: number?,
	coexist: boolean?,
	loop: boolean?, -- Roblox Animation fallback only
}

export type Handle = Mixer.Handle

export type Animator = {
	model: Model,
	rigId: string,
	events: Signal.Signal<string, Types.ClipEvent>,
	finished: Signal.Signal<Handle>,
	play: (self: Animator, clipId: string, opts: PlayOptions?) -> Handle,
	stop: (self: Animator, target: Handle | string, blendOut: number?) -> (),
	hitStop: (self: Animator, frames: number) -> (),
	isPaused: (self: Animator) -> boolean,
	setTimeScale: (self: Animator, scale: number) -> (),
	isPlaying: (self: Animator, clipId: string) -> boolean,
	currentRootMotionDelta: (self: Animator) -> Vector3,
	setWeight: (self: Animator, handle: Handle, weight: number, immediate: boolean?) -> (),
	setSpeed: (self: Animator, handle: Handle, speed: number) -> (),
	setProcedural: (self: Animator, name: string, offsets: ClipSampler.Offsets?, weight: number?) -> (),
	onStep: (self: Animator, fn: (dt: number) -> ()) -> () -> (),
	step: (self: Animator, dt: number) -> (),
	destroy: (self: Animator) -> (),
}

export type Engine = {
	now: () -> number,
	cameraPosition: () -> Vector3?,
	renderStepped: { Connect: (self: any, fn: (dt: number) -> ()) -> any },
	heartbeat: { Connect: (self: any, fn: (dt: number) -> ()) -> any },
	connect: (instance: Instance, eventName: string, fn: (...any) -> ()) -> any,
}

type Rate = "Full" | "Distant" | "Far"

local RBX_PREFIX = "rbxassetid://"
local DEFAULT_ANIMATE_SCRIPT = "Animate"

local Choreo = {}

local AnimatorClass = {}
AnimatorClass.__index = AnimatorClass

local registry: { [Model]: any } = {}
local ordered: { any } = {}
local quality: Types.Quality = "High"
local localModel: Model? = nil
local started = false
local rankTimer = 0

-- The engine surface; replaced by tests with Choreo.configure.
local engine: Engine = {
	now = function(): number
		return workspace:GetServerTimeNow()
	end,
	cameraPosition = function(): Vector3?
		local camera = workspace.CurrentCamera
		return if camera then camera.CFrame.Position else nil
	end,
	renderStepped = RunService.RenderStepped :: any,
	heartbeat = RunService.Heartbeat :: any,
	connect = function(instance: Instance, eventName: string, fn: (...any) -> ()): any
		local ok, result = pcall(function()
			return ((instance :: any)[eventName] :: RBXScriptSignal):Connect(fn)
		end)
		return if ok then result else nil
	end,
}

local function isRbxClip(clipId: string): boolean
	return clipId:sub(1, #RBX_PREFIX) == RBX_PREFIX
end

local function rigIdOf(model: Model): string
	local attribute = model:GetAttribute("Rig")
	if typeof(attribute) == "string" and ChoreoData.rigs[attribute] ~= nil then
		return attribute
	end
	if model:FindFirstChildOfClass("Humanoid") ~= nil then
		return "PlayerR15"
	end
	error(("Choreo: %s has no Rig attribute and no Humanoid"):format(model:GetFullName()))
end

-- ---------------------------------------------------------------------------------------------
-- Animator
-- ---------------------------------------------------------------------------------------------

local function rebuildMotors(self: any)
	local motors: { [string]: Motor6D } = {}
	for _, descendant in self.model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			motors[descendant.Name] = descendant
		end
	end
	self.motors = motors
	self.motorsDirty = false
end

-- Writes the blended offsets to the joints; joints that stopped being keyed return to rest.
-- The two touched sets are reused frame to frame (no per-frame table on RenderStepped).
local function applyOffsets(self: any, offsets: ClipSampler.Offsets)
	local motors = self.motors
	local touched: { [string]: boolean } = self.touchedScratch
	table.clear(touched)
	if not self.rbxActive then
		for name, offset in offsets do
			local motor = motors[name]
			if motor ~= nil then
				motor.Transform = ClipSampler.toCFrame(offset)
				touched[name] = true
			end
		end
	end
	for name in self.touched do
		if not touched[name] then
			local motor = motors[name]
			if motor ~= nil then
				motor.Transform = CFrame.identity
			end
		end
	end
	self.touchedScratch = self.touched
	self.touched = touched
end

local function rbxHost(model: Model): Instance
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end
	local controller = model:FindFirstChildOfClass("AnimationController")
	if controller then
		return controller
	end
	local created = Instance.new("AnimationController")
	created.Parent = model
	return created
end

local function rbxAnimator(model: Model): Instance
	local host = rbxHost(model)
	local animator = host:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	local created = Instance.new("Animator")
	created.Parent = host
	return created
end

-- Stops whatever the engine's default scripts were playing so Transform writes are not overwritten.
local function silenceDefaultAnimations(model: Model)
	local animate = model:FindFirstChild(DEFAULT_ANIMATE_SCRIPT)
	if animate ~= nil and animate:IsA("LuaSourceContainer") then
		animate:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if animator ~= nil then
		pcall(function()
			for _, track in (animator :: any):GetPlayingAnimationTracks() do
				track:Stop(0)
			end
		end)
	end
end

local EVENT_KINDS: { Types.ClipEventKind } = {
	"HitWindowOpen",
	"HitWindowClose",
	"TrailOn",
	"TrailOff",
	"SmearOn",
	"SmearOff",
	"Footstep",
	"Voice",
	"Sfx",
	"ActivationHold",
	"PostMotionStart",
	"WeaponSwap",
	"CameraNudge",
}

local function playRbx(self: any, clipId: string, options: PlayOptions): Handle
	local animations: { [string]: Animation } = self.rbxAnimations
	local animation = animations[clipId]
	if animation == nil then
		animation = Instance.new("Animation")
		animation.AnimationId = clipId
		animations[clipId] = animation
	end
	local layer: Types.ClipLayer = options.layer or "FullBody"
	local track = (rbxAnimator(self.model) :: any):LoadAnimation(animation) :: AnimationTrack
	track.Priority = (Enum.AnimationPriority :: any)[ChoreoData.rbxPriority[layer]]
	track.Looped = options.loop == true
	local speed = math.clamp(options.speed or 1, ChoreoData.minSpeed, ChoreoData.maxSpeed)
	track:Play(options.blendIn or ChoreoData.blendIn, options.weight or 1, speed * self.mixer:timeScale())
	if options.serverTime ~= nil then
		track.TimePosition = Mixer.catchUpStart(engine.now(), options.serverTime, speed, track.Length)
	elseif options.startTime ~= nil then
		track.TimePosition = options.startTime
	end
	local handle: any = {
		id = 0,
		clipId = clipId,
		layer = layer,
		priority = options.priority or 0,
		speed = speed,
		rbx = track,
		stopping = false,
		done = false,
	}
	for _, kind in EVENT_KINDS do
		pcall(function()
			track:GetMarkerReachedSignal(kind):Connect(function(value: string?)
				self.events:Fire(clipId, { time = track.TimePosition, kind = kind, data = { value = value } })
			end)
		end)
	end
	engine.connect(track, "Stopped", function()
		handle.done = true
		self.rbxTracks[handle] = nil
		self.rbxActive = next(self.rbxTracks) ~= nil
		self.finished:Fire(handle)
	end)
	self.rbxTracks[handle] = track
	self.rbxActive = true
	return handle
end

function AnimatorClass.play(self: any, clipId: string, opts: PlayOptions?): Handle
	local options: PlayOptions = opts or {}
	if isRbxClip(clipId) then
		return playRbx(self, clipId, options)
	end
	local clip = ClipLibrary.get(clipId)
	if clip.rig ~= self.rigId and not self.warnedRigs[clipId] then
		self.warnedRigs[clipId] = true
		warn(("[Choreo] clip %s is authored for rig %s but plays on %s"):format(clipId, clip.rig, self.rigId))
	end
	local mixerOptions: Mixer.PlayOptions = {
		startTime = options.startTime,
		speed = options.speed,
		layer = options.layer,
		priority = options.priority,
		blendIn = options.blendIn,
		blendOut = options.blendOut,
		weight = options.weight,
		coexist = options.coexist,
	}
	if options.serverTime ~= nil then
		mixerOptions.serverTime = options.serverTime
		mixerOptions.now = engine.now()
	end
	return self.mixer:play(clip, mixerOptions)
end

function AnimatorClass.stop(self: any, target: Handle | string, blendOut: number?)
	if typeof(target) == "table" and (target :: any).rbx ~= nil then
		((target :: any).rbx :: AnimationTrack):Stop(blendOut or ChoreoData.blendOut)
		return
	end
	if typeof(target) == "string" then
		for handle, track in self.rbxTracks do
			if handle.clipId == target then
				track:Stop(blendOut or ChoreoData.blendOut)
			end
		end
	end
	self.mixer:stop(target, blendOut)
end

function AnimatorClass.hitStop(self: any, frames: number)
	self.mixer:hitStop(frames)
	if next(self.rbxTracks) ~= nil then
		for _, track in self.rbxTracks do
			track:AdjustSpeed(0)
		end
		task.delay(frames * ChoreoData.frameSeconds, function()
			if self.mixer:pauseRemaining() > 0 then
				return
			end
			for handle, track in self.rbxTracks do
				track:AdjustSpeed(handle.speed * self.mixer:timeScale())
			end
		end)
	end
end

function AnimatorClass.isPaused(self: any): boolean
	return self.mixer:pauseRemaining() > 0
end

function AnimatorClass.setTimeScale(self: any, scale: number)
	self.mixer:setTimeScale(scale)
	for handle, track in self.rbxTracks do
		track:AdjustSpeed(handle.speed * self.mixer:timeScale())
	end
end

function AnimatorClass.isPlaying(self: any, clipId: string): boolean
	if self.mixer:isPlaying(clipId) then
		return true
	end
	for handle, track in self.rbxTracks do
		if handle.clipId == clipId and track.IsPlaying then
			return true
		end
	end
	return false
end

function AnimatorClass.currentRootMotionDelta(self: any): Vector3
	return self.rootDelta
end

function AnimatorClass.setWeight(self: any, handle: Handle, weight: number, immediate: boolean?)
	if (handle :: any).rbx ~= nil then
		((handle :: any).rbx :: AnimationTrack):AdjustWeight(weight, if immediate then 0 else ChoreoData.blendIn)
		return
	end
	self.mixer:setWeight(handle, weight, immediate)
end

function AnimatorClass.setSpeed(self: any, handle: Handle, speed: number)
	local rbxHandle = handle :: any
	if rbxHandle.rbx ~= nil then
		local clamped = math.clamp(speed, ChoreoData.minSpeed, ChoreoData.maxSpeed)
		rbxHandle.speed = clamped
		local track: AnimationTrack = rbxHandle.rbx
		track:AdjustSpeed(clamped * self.mixer:timeScale())
		return
	end
	self.mixer:setSpeed(handle, speed)
end

function AnimatorClass.setProcedural(self: any, name: string, offsets: ClipSampler.Offsets?, weight: number?)
	self.mixer:setProcedural(name, offsets, weight)
end

--- Runs `fn(dt)` before every step of this animator (drivers that feed it: a remote rig's
--- locomotion). Returns the function that removes it. Plain callbacks, no Signal: this is per frame.
function AnimatorClass.onStep(self: any, fn: (dt: number) -> ()): () -> ()
	local hooks: { (dt: number) -> () } = self.stepHooks
	table.insert(hooks, fn)
	return function()
		local index = table.find(hooks, fn)
		if index ~= nil then
			table.remove(hooks, index)
		end
	end
end

function AnimatorClass.step(self: any, dt: number)
	if self.destroyed then
		return
	end
	if self.motorsDirty then
		rebuildMotors(self)
	end
	local hooks: { (dt: number) -> () } = self.stepHooks
	for index = #hooks, 1, -1 do
		local hook = hooks[index]
		if hook ~= nil then
			hook(dt)
		end
	end
	local result = self.mixer:step(dt)
	local delta = result.rootDelta
	self.rootDelta = Vector3.new(delta[1], delta[2], delta[3])
	applyOffsets(self, result.offsets)
	for _, fired in result.events do
		self.events:Fire(fired.clipId, fired.event)
	end
	for _, handle in result.finished do
		self.finished:Fire(handle)
	end
end

function AnimatorClass.destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true
	for _, connection in self.connections do
		if connection ~= nil and typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		elseif typeof(connection) == "table" and (connection :: any).Disconnect then
			(connection :: any):Disconnect()
		end
	end
	for _, track in self.rbxTracks do
		track:Stop(0)
	end
	table.clear(self.stepHooks)
	self.mixer:clear()
	self.events:Destroy()
	self.finished:Destroy()
	registry[self.model] = nil
	local index = table.find(ordered, self)
	if index then
		table.remove(ordered, index)
	end
end

local function newAnimator(model: Model): any
	local rigId = rigIdOf(model)
	local self = setmetatable({
		model = model,
		rigId = rigId,
		mixer = Mixer.new(),
		events = Signal.new() :: Signal.Signal<string, Types.ClipEvent>,
		finished = Signal.new() :: Signal.Signal<Handle>,
		motors = {} :: { [string]: Motor6D },
		motorsDirty = true,
		touched = {} :: { [string]: boolean },
		touchedScratch = {} :: { [string]: boolean },
		stepHooks = {} :: { (dt: number) -> () },
		rootDelta = Vector3.zero,
		rbxTracks = {} :: { [any]: AnimationTrack },
		rbxAnimations = {} :: { [string]: Animation },
		rbxActive = false,
		warnedRigs = {} :: { [string]: boolean },
		connections = {} :: { any },
		accumulated = 0,
		rate = "Full" :: Rate,
		distance = 0,
		destroyed = false,
	}, AnimatorClass)

	silenceDefaultAnimations(model)
	rebuildMotors(self)

	local function markDirty()
		self.motorsDirty = true
	end
	-- The character's parts (and the engine's Animate script) can arrive after the model does.
	local function onDescendantAdded(descendant: Instance)
		markDirty()
		if descendant.Name == DEFAULT_ANIMATE_SCRIPT and descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	table.insert(self.connections, engine.connect(model, "DescendantAdded", onDescendantAdded))
	table.insert(self.connections, engine.connect(model, "DescendantRemoving", markDirty))
	table.insert(
		self.connections,
		engine.connect(model, "AncestryChanged", function()
			if model.Parent == nil then
				self:destroy()
			end
		end)
	)

	-- Posed the frame it appears: the rig's idle underneath everything, breathing on top.
	local rigClips = ChoreoData.rigs[rigId]
	if rigClips ~= nil then
		self.mixer:play(ClipLibrary.get(rigClips.idle), { fallback = true, blendIn = 0 })
		if rigClips.breathing ~= nil then
			self.mixer:play(ClipLibrary.get(rigClips.breathing), { coexist = true, blendIn = 0 })
		end
	end
	self:step(0)
	return self
end

-- ---------------------------------------------------------------------------------------------
-- Scheduling
-- ---------------------------------------------------------------------------------------------

local function tier()
	return ChoreoData.quality[quality]
end

-- Ranks every animator by distance from the camera and assigns update rates for the tier.
local function rerank()
	local camera = engine.cameraPosition()
	local limits = tier()
	for _, animator in ordered do
		local primary = animator.model.PrimaryPart
		if camera ~= nil and primary ~= nil then
			animator.distance = (primary.Position - camera).Magnitude
		else
			animator.distance = 0
		end
		if animator.model == localModel then
			animator.distance = -1
		end
	end
	table.sort(ordered, function(a, b)
		return a.distance < b.distance
	end)
	for index, animator in ordered do
		if
			animator.model == localModel or (index <= limits.maxFullRateRigs and animator.distance <= limits.nearRadius)
		then
			animator.rate = "Full"
		elseif index <= limits.maxFullRateRigs * 2 then
			animator.rate = "Distant"
		else
			animator.rate = "Far"
		end
	end
end

local function start()
	if started then
		return
	end
	started = true
	-- Both loops walk `ordered` by index (no per-frame copy); an animator destroyed mid-loop shifts
	-- its neighbour into the slot and that neighbour waits a frame, which is harmless.
	engine.renderStepped:Connect(function(dt: number)
		rankTimer += dt
		if rankTimer >= ChoreoData.rankInterval then
			rankTimer = 0
			rerank()
		end
		for index = 1, #ordered do
			local animator = ordered[index]
			if animator ~= nil and animator.rate == "Full" then
				animator:step(dt)
			end
		end
	end)
	engine.heartbeat:Connect(function(dt: number)
		local limits = tier()
		for index = 1, #ordered do
			local animator = ordered[index]
			if animator ~= nil and animator.rate ~= "Full" then
				animator.accumulated += dt
				local interval = 1 / (if animator.rate == "Distant" then limits.distantHz else limits.farHz)
				if animator.accumulated >= interval then
					animator:step(animator.accumulated)
					animator.accumulated = 0
				end
			end
		end
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------------------------

--- The animator for a rig model, created (and posed) on first call.
function Choreo.get(model: Model): Animator
	local existing = registry[model]
	if existing ~= nil then
		return existing
	end
	start()
	local animator = newAnimator(model)
	registry[model] = animator
	table.insert(ordered, animator)
	rerank()
	return animator
end

--- The animator for a model if one exists (no creation).
function Choreo.find(model: Model): Animator?
	return registry[model]
end

--- Convenience: Choreo.get(model):play(clipId, opts).
function Choreo.play(model: Model, clipId: string, opts: PlayOptions?): Handle
	return Choreo.get(model):play(clipId, opts)
end

--- Destroys the animator for a model (the model itself is left alone).
function Choreo.release(model: Model)
	local animator = registry[model]
	if animator ~= nil then
		animator:destroy()
	end
end

--- Hit-stop on every listed model that has an animator, by tier (section 6: 3 / 6 / 10 frames).
function Choreo.hitStopAll(models: { Model }, hitStopTier: Types.HitStopTier)
	local frames = CombatData.hitStopFrames[hitStopTier] or CombatData.hitStopFrames.Normal
	for _, model in models do
		local animator = registry[model]
		if animator ~= nil then
			animator:hitStop(frames)
		end
	end
end

--- Sets the quality tier (data/choreo.luau quality): update radius, rig budget, distant rates.
function Choreo.setQuality(newQuality: Types.Quality)
	assert(ChoreoData.quality[newQuality] ~= nil, "Choreo.setQuality: unknown tier " .. tostring(newQuality))
	quality = newQuality
	rerank()
end

--- The current quality tier.
function Choreo.quality(): Types.Quality
	return quality
end

--- Marks the local player's model: always full rate, never budgeted out.
function Choreo.setLocalModel(model: Model?)
	localModel = model
	rerank()
end

--- Number of registered animators.
function Choreo.count(): number
	return #ordered
end

--- Replaces engine functions (clock, camera, frame signals) for tests and the ClipLab.
function Choreo.configure(overrides: { [string]: any })
	for key, value in overrides do
		(engine :: any)[key] = value
	end
end

--- Steps every animator once (tests and the ClipLab scrubber).
function Choreo.stepAll(dt: number)
	for _, animator in table.clone(ordered) do
		animator:step(dt)
	end
end

return Choreo
