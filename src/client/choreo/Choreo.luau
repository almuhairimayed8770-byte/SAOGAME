--!strict
--[[
	Choreo: the data-driven animator (section 10 "Choreo"). One animator per rig model; every
	frame it samples the active clips through the Mixer and writes the result as the Transform of
	the named joints. A joint is a Motor6D (RigBuilder enemies, the Weapon joint) or an
	AnimationConstraint (the default player character since the Avatar Joint Upgrade); Transform
	means the same on both (shared/choreo/Joints.luau), and Choreo writes nothing else on a joint.
	Nothing here decides gameplay: it predicts motion, fires clip events and hands the root-motion
	delta to the CharacterController, which moves the HumanoidRootPart so the server can validate
	the displacement.

		local animator = Choreo.get(model)            -- posed the same frame (no T-pose, ever)
		local handle = animator:play("player/OneHandedSword/Horizontal", { serverTime = t })
		animator.events:Connect(function(clipId, event, jumped) ... end)
		animator:hitStop(frames)                      -- the rig holds; camera/FX read isPaused()
		animator:currentRootMotionDelta()             -- Vector3, rig-local studs since last frame (zero once stale)
		animator:seek(handle, clipTime)               -- the clip's clock forward now: its events fire, no root
		animator:joint("Weapon")                      -- the joint Choreo writes for that name
		animator:pin("Weapon", true)                  -- the joint rests at identity, whatever is keyed
		Choreo.hitStopAll(models, "Final")
		Choreo.setQuality("Medium")
		Choreo.setLocalModel(character, true)         -- its owner steps it: Choreo.stepLocal(dt)

	Footsteps: the Base layer blends many walk clips (and a drawn twin of each), all running at
	once, and each has its own steps. Only the one the limbs show most sounds its Footstep events,
	so a still rig is silent and a blend of walks steps once. FullBody clips that cover more of the
	limbs than they leave to the walk (a dodge, a landing, a jump, a fall, an Art) silence it: the
	feet are theirs, and only their own steps sound, so nothing steps in the air.

	Render stalls (D-132): RenderStepped stops while the display sleeps or the window is minimised,
	and its first dt after waking is the whole gap. A step longer than data/choreo.luau
	stall.jumpSeconds is a jump (Mixer): the clips take the gap, the root none of it, and every
	event the gap crossed fires with `jumped` true, so listeners close what it closes (Replication
	starts no sound, trail, smear, light or kick for it; Locomotion still moves the sword on a
	WeaponDraw or WeaponSheathe; the Art hold still freezes). Every other event fires with false.
	A long step covers the clock's time since the rig's last step (engine.now), whatever dt it was
	handed: a wake that reports one frame is a jump too, a rig that kept stepping on Heartbeat
	through the stall and is full rate after the wake's re-rank does not take the gap again, and a
	rig the re-rank made distant jumps on its first Heartbeat step. A clip played inside the gap
	(the key press that woke the display, a remote's action just before the wake) is the present:
	the wake moves it only by its own age (Mixer sinceStep), so what is still ahead of it plays as
	ever. A root delta older than jumpSeconds reads as zero, so a reader that steps before the
	wake step does not move the body by the last frame before the stall.

	Update rates: the local character and the nearest rigs step every rendered frame, in a render
	step bound just before the camera's (Choreo.RENDER_STEP at Choreo.renderPriority(), Camera
	priority - 1); the rest step on Heartbeat at the quality tier's distant / far rate
	(data/choreo.luau quality). The engine does not pin a RenderStepped connection's order against
	a BindToRenderStep callback, so the rigs' step is a bound one: the camera (Camera priority)
	frames the body offset and pose of this frame's step, as do the local controller's step and
	its contact read (Character + 1), whatever order the engine runs the rest in. While its
	owner drives the local character (setLocalModel(model, true): the character controller), the
	owner steps it from its own render step with Choreo.stepLocal and the rigs' step leaves it
	alone, so the owner reads the root delta of this frame's step (D-139). A clip id
	that looks like "rbxassetid://..." plays as a Roblox AnimationTrack on the same layer with the
	matching AnimationPriority, so hand-authored clips can replace data clips later.

	The engine's Animator (the default player character carries one under its Humanoid) puts
	every joint's Transform back to rest in its animation step, which runs after RenderStepped
	and before PreSimulation, even with no AnimationTrack playing. So on a rig that has one, the
	pose written by the step is written again on PreSimulation every frame, and that write is the
	one physics and the next rendered frame see (D-053, measured in Play on the user's PC: a
	RenderStepped or PreAnimation write read back as rest in Heartbeat, a PreSimulation write
	held). A rig without an Animator (the RigBuilder rigs) keeps its writes.

	An enemy's attack clip keeps the server's beat (D-172): `keepBeat` marks the handle ActionStarted
	played (up to its first HitWindowOpen, owing what the network catch-up could not jump), and
	`shiftBeat` takes off what the server paused the attack for; the Mixer evens the rest by the
	clip's rate, never with a second freeze.

	A rush is drawn on the server's timeline (D-171): `setBodyOffset` draws the body away from the
	root part by an offset in the root's space, composed into the root joint's Transform (the
	joint whose Part0 is the PrimaryPart) on top of whatever the clips key there, so the root keeps
	its physics and its replicated place while the body shows where the server's clock has it.
	Nil puts the body back on its root. The offset is written every step and on PreSimulation
	with the rest of the pose. The step that writes it publishes it (DrawnBody.publish, D-193), so
	every reader of where the body is drawn, and every billboard over it, follows the body.

	The engine surface (clocks, camera, frame signals) is one small table that tests replace with
	Choreo.configure; the logic underneath is the Lune-tested Mixer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared.types)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Joints = require(Shared.choreo.Joints)
local Signal = require(Shared.util.Signal)
local Easing = require(Shared.util.Easing)
local ChoreoData = require(Shared.data.choreo)
local CombatData = require(Shared.data.combat)
local Mixer = require(script.Parent.Mixer)
local ClipLibrary = require(script.Parent.ClipLibrary)
local DrawnBody = require(script.Parent.DrawnBody)

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
	mask: { [string]: number }?, -- Additive clips: joint name -> weight multiplier (Mixer)
}

export type Handle = Mixer.Handle

export type Animator = {
	model: Model,
	rigId: string,
	-- (clipId, event, jumped): jumped is true for an event a render stall's gap crossed (D-132).
	events: Signal.Signal<string, Types.ClipEvent, boolean>,
	finished: Signal.Signal<Handle>,
	play: (self: Animator, clipId: string, opts: PlayOptions?) -> Handle,
	stop: (self: Animator, target: Handle | string, blendOut: number?) -> (),
	hitStop: (self: Animator, frames: number) -> (),
	isPaused: (self: Animator) -> boolean,
	pauseRemaining: (self: Animator) -> number,
	setTimeScale: (self: Animator, scale: number) -> (),
	isPlaying: (self: Animator, clipId: string) -> boolean,
	currentRootMotionDelta: (self: Animator) -> Vector3,
	seek: (self: Animator, handle: Handle, clipTime: number) -> (),
	keepBeat: (self: Animator, handle: Handle, serverTime: number?) -> (),
	shiftBeat: (self: Animator, handle: Handle, seconds: number) -> (),
	setBodyOffset: (self: Animator, offset: CFrame?) -> (),
	getBodyOffset: (self: Animator) -> CFrame?,
	setWeight: (self: Animator, handle: Handle, weight: number, immediate: boolean?) -> (),
	setSpeed: (self: Animator, handle: Handle, speed: number) -> (),
	setProcedural: (self: Animator, name: string, offsets: ClipSampler.Offsets?, weight: number?) -> (),
	onStep: (self: Animator, fn: (dt: number) -> ()) -> () -> (),
	joint: (self: Animator, name: string) -> Instance?,
	pin: (self: Animator, name: string, pinned: boolean) -> (),
	step: (self: Animator, dt: number) -> (),
	destroy: (self: Animator) -> (),
}

export type Engine = {
	now: () -> number,
	cameraPosition: () -> Vector3?,
	renderStepped: { Connect: (self: any, fn: (dt: number) -> ()) -> any },
	heartbeat: { Connect: (self: any, fn: (dt: number) -> ()) -> any },
	-- Fires after the engine's animation step; nil where the engine has none (Lune).
	preSimulation: { Connect: (self: any, fn: (dt: number) -> ()) -> any }?,
	connect: (instance: Instance, eventName: string, fn: (...any) -> ()) -> any,
	-- Runs `fn` at the next resumption point (task.defer): after the engine finishes the change
	-- that fired the current handler, such as parenting the default Animate script.
	defer: (fn: () -> ()) -> (),
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
-- The local model's owner steps it (Choreo.stepLocal); RenderStepped leaves it alone (D-139).
local localDriven = false
local started = false
local rankTimer = 0

--- The render step the rigs step in, bound just before the camera's (Choreo.renderPriority).
Choreo.RENDER_STEP = "SkyspireRigs"

--- The rigs' render step priority: one before the camera's (Enum.RenderPriority.Camera), so the
--- camera and everything bound after it read this frame's poses and body offsets.
function Choreo.renderPriority(): number
	return Enum.RenderPriority.Camera.Value - 1
end

-- The engine's per-frame render signal for the rigs: a render step bound at renderPriority, not a
-- RenderStepped connection (whose order against the camera's bound step the engine leaves open).
local boundRenderStep = {
	Connect = function(_self: any, fn: (dt: number) -> ()): any
		RunService:BindToRenderStep(Choreo.RENDER_STEP, Choreo.renderPriority(), fn)
		return {
			Disconnect = function()
				RunService:UnbindFromRenderStep(Choreo.RENDER_STEP)
			end,
		}
	end,
}

-- The engine surface; replaced by tests with Choreo.configure.
local engine: Engine = {
	now = function(): number
		return workspace:GetServerTimeNow()
	end,
	cameraPosition = function(): Vector3?
		local camera = workspace.CurrentCamera
		return if camera then camera.CFrame.Position else nil
	end,
	renderStepped = boundRenderStep,
	heartbeat = RunService.Heartbeat :: any,
	preSimulation = (RunService :: any).PreSimulation,
	connect = function(instance: Instance, eventName: string, fn: (...any) -> ()): any
		local ok, result = pcall(function()
			return ((instance :: any)[eventName] :: RBXScriptSignal):Connect(fn)
		end)
		return if ok then result else nil
	end,
	defer = function(fn: () -> ())
		task.defer(fn)
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

-- True when the engine animates the rig: an Animator under its Humanoid or AnimationController.
-- That Animator puts every joint back to rest each frame after RenderStepped (D-053).
local function engineAnimates(model: Model): boolean
	for _, className in { "Humanoid", "AnimationController" } do
		local host = model:FindFirstChildOfClass(className)
		if host ~= nil and host:FindFirstChildOfClass("Animator") ~= nil then
			return true
		end
	end
	return false
end

-- Name -> joint (Motor6D or AnimationConstraint). Rebuilt on the next step whenever a joint
-- arrives or leaves, so a rig whose joints replicate after the animator attached still animates.
-- A pinned name's new joint is put at rest at once.
local function rebuildMotors(self: any)
	self.motors = Joints.map(self.model)
	self.motorsDirty = false
	self.rootJoint = nil
	self.engineAnimated = engineAnimates(self.model)
	for name in self.pinned do
		local joint = self.motors[name]
		if joint ~= nil then
			Joints.setTransform(joint, CFrame.identity)
		end
	end
end

-- The name of the joint that hangs the body on the root part (its Part0 is the PrimaryPart), found
-- once per joint map; nil while the rig has none.
local function rootJointName(self: any): string?
	local cached = self.rootJoint
	if cached ~= nil then
		return cached
	end
	local primary = self.model.PrimaryPart
	if primary == nil then
		return nil
	end
	for name, joint in self.motors :: { [string]: Joints.Joint } do
		local part0 = Joints.parts(joint)
		if part0 == primary then
			self.rootJoint = name
			return name
		end
	end
	return nil
end

-- Writes the blended offsets to the joints' Transform; joints that stopped being keyed return to
-- rest. A pinned joint is skipped, so it returns to rest too and stays there. Every written
-- Transform is kept in `pose` for the PreSimulation rewrite (reapplyPose). The two touched sets
-- are reused frame to frame (no per-frame table on RenderStepped). A body offset (setBodyOffset)
-- is composed into the root joint's Transform: Part1 = Part0 * C0 * Transform * C1^-1, so
-- C0^-1 * offset * C0 in front of the clip's own Transform draws the body as if the root part
-- stood at root * offset. The offset drawn (nil when none is) is published to DrawnBody (D-193).
local function applyOffsets(self: any, offsets: ClipSampler.Offsets)
	local motors = self.motors
	local pinned: { [string]: boolean } = self.pinned
	local touched: { [string]: boolean } = self.touchedScratch
	local pose: { [string]: CFrame } = self.pose
	local drawnAt: CFrame? = nil
	table.clear(touched)
	if not self.rbxActive then
		for name, offset in offsets do
			local motor = motors[name]
			if motor ~= nil and not pinned[name] then
				local transform = ClipSampler.toCFrame(offset)
				motor.Transform = transform
				pose[name] = transform
				touched[name] = true
			end
		end
		local body: CFrame? = self.bodyOffset
		if body ~= nil then
			local name = rootJointName(self)
			local motor = if name ~= nil then motors[name] else nil
			if name ~= nil and motor ~= nil and not pinned[name] then
				local c0 = Joints.frames(motor)
				local keyed = if touched[name] then pose[name] else CFrame.identity
				local transform = c0:Inverse() * body * c0 * keyed
				motor.Transform = transform
				pose[name] = transform
				touched[name] = true
				drawnAt = body
			end
		end
	end
	if drawnAt ~= nil or self.drawnPublished then
		self.drawnPublished = drawnAt ~= nil
		DrawnBody.publish(self.model, drawnAt)
	end
	for name in self.touched do
		if not touched[name] then
			local motor = motors[name]
			if motor ~= nil then
				motor.Transform = CFrame.identity
			end
			pose[name] = nil
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

-- Stops every track the engine's Animator is playing that Choreo did not start (the default
-- Animate script's), so Transform writes are not overwritten.
local function stopForeignTracks(self: any)
	local humanoid = self.model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if animator == nil then
		return
	end
	local ours: { [any]: AnimationTrack } = self.rbxTracks
	pcall(function()
		for _, track in (animator :: any):GetPlayingAnimationTracks() do
			local own = false
			for _, playing in ours do
				if playing == track then
					own = true
					break
				end
			end
			if not own then
				track:Stop(0)
			end
		end
	end)
end

-- Silences the default Animate script: disabled and its tracks stopped at once, so not one frame
-- of the default animations plays, then destroyed at the next resumption point. Destroying it
-- right away, while the engine is still parenting it (it fires DescendantAdded, and the character
-- can be handed to Choreo mid-parent), makes Studio print "Something unexpectedly tried to set
-- the parent of Animate to NULL".
local function silenceAnimate(self: any, animate: Instance)
	pcall(function()
		(animate :: any).Enabled = false
	end)
	stopForeignTracks(self)
	engine.defer(function()
		animate:Destroy()
	end)
end

-- Stops whatever the engine's default scripts were playing so Transform writes are not overwritten.
local function silenceDefaultAnimations(self: any)
	local animate = self.model:FindFirstChild(DEFAULT_ANIMATE_SCRIPT)
	if animate ~= nil and animate:IsA("LuaSourceContainer") then
		silenceAnimate(self, animate)
	else
		stopForeignTracks(self)
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
	"WeaponDraw",
	"WeaponSheathe",
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
				self.events:Fire(clipId, { time = track.TimePosition, kind = kind, data = { value = value } }, false)
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
		mask = options.mask,
	}
	local now = engine.now()
	if options.serverTime ~= nil then
		mixerOptions.serverTime = options.serverTime
		mixerOptions.now = now
	end
	-- Played inside a render stall's gap, the clip is the present: the wake moves it by its own age.
	mixerOptions.sinceStep = math.max(0, now - self.rootDeltaAt)
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

--- Seconds of hit-stop the rig still holds (0 when none): a confirmation that extends a predicted
--- contact's hold reads how much of it is left.
function AnimatorClass.pauseRemaining(self: any): number
	return self.mixer:pauseRemaining()
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
	-- A delta older than a render stall (D-132) belongs to the frame before the stall: a reader whose
	-- step runs before this rig's wake step must not move the root by it.
	if engine.now() - self.rootDeltaAt > ChoreoData.stall.jumpSeconds then
		return Vector3.zero
	end
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
--- locomotion), the newest hook first: a rush's drawing (added when it is armed) runs before the
--- locomotion that reads its offset (added when the rig is watched). Returns the function that
--- removes it. Plain callbacks, no Signal: this is per frame.
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

--- The joint Choreo writes for a name (a Motor6D or an AnimationConstraint), or nil. A map that a
--- joint arriving or leaving marked dirty is rebuilt first.
function AnimatorClass.joint(self: any, name: string): Instance?
	if self.motorsDirty then
		rebuildMotors(self)
	end
	return self.motors[name]
end

--- Pins a joint at rest: while pinned, its Transform stays identity whatever any clip, additive
--- or procedural channel keys (the sword on its back mount). The change lands on the joint at
--- once, so a pin set from a clip event already shows in the frame that fired it.
function AnimatorClass.pin(self: any, name: string, pinned: boolean)
	local pins: { [string]: boolean } = self.pinned
	if (pins[name] == true) == pinned then
		return
	end
	if pinned then
		pins[name] = true
	else
		pins[name] = nil
	end
	local joint = self:joint(name)
	if joint == nil then
		return
	end
	if pinned then
		Joints.setTransform(joint :: any, CFrame.identity)
		self.touched[name] = nil
		self.pose[name] = nil
		return
	end
	local offset = if self.rbxActive then nil else self.mixer:lastOffsets()[name]
	if offset ~= nil then
		local transform = ClipSampler.toCFrame(offset)
		Joints.setTransform(joint :: any, transform)
		self.touched[name] = true
		self.pose[name] = transform
	end
end

local FOOTSTEP: Types.ClipEventKind = "Footstep"

-- Clip id -> whether the clip has a Footstep event.
local footstepsById: { [string]: boolean } = {}
local function hasFootsteps(clip: Types.ClipDef): boolean
	local cached = footstepsById[clip.id]
	if cached == nil then
		cached = false
		for _, event in clip.events do
			if event.kind == FOOTSTEP then
				cached = true
				break
			end
		end
		footstepsById[clip.id] = cached
	end
	return cached :: boolean
end

-- Reused by footstepSource: the shown weight of each FullBody priority group.
local fullBodyGroups: { [number]: number } = {}

-- The Base handle whose footsteps sound: of the Base clips with steps, the one the limbs show
-- most (the first one on a tie). Nil when none shows at all, so a still rig makes no sound, and
-- nil while FullBody clips cover more of the limbs than they leave to the walk: a dodge, a
-- landing, a jump, a fall, an Art or a stagger moves the feet then, and only its own steps (if
-- it has any) sound. Its blend-in and fade-out tails, and a light landing, leave the walk's.
local function footstepSource(self: any): Handle?
	local best: Handle? = nil
	local bestWeight = 0
	table.clear(fullBodyGroups)
	for _, handle in self.mixer:handles() do
		local layer = handle.layer
		if layer == "FullBody" or (layer == "Base" and hasFootsteps(handle.clip)) then
			local shown = Easing.evaluate(ChoreoData.blendEasing, handle.fade) * handle.weight
			if layer == "FullBody" then
				fullBodyGroups[handle.priority] = (fullBodyGroups[handle.priority] or 0) + shown
			elseif shown > bestWeight then
				best = handle
				bestWeight = shown
			end
		end
	end
	-- What the walk keeps of the limbs: the Mixer lays each FullBody priority group over the
	-- layers below at its summed shown weight (at most all of it).
	local walkShare = 1
	for _, shown in fullBodyGroups do
		walkShare *= 1 - math.min(1, shown)
	end
	if walkShare < 1 - walkShare then
		return nil
	end
	return best
end

-- Fires crossed events (a step's or a seek's) on the animator's `events`; of the Base layer's
-- footsteps only those of the walk the limbs show most sound (footstepSource).
local function fireEvents(self: any, events: { Mixer.FiredEvent })
	local stepSource: Handle? = nil
	local sourceKnown = false
	for _, fired in events do
		if fired.event.kind == FOOTSTEP and fired.handle.layer == "Base" then
			if not sourceKnown then
				stepSource = footstepSource(self)
				sourceKnown = true
			end
			if fired.handle ~= stepSource then
				continue
			end
		end
		self.events:Fire(fired.clipId, fired.event, fired.jumped)
	end
end

--- Moves a playing clip's clock forward to `clipTime` now, whatever the time scale or a hit-stop,
--- as if it had played there: fires the events it crosses, unmarked, and moves no root; the pose
--- shows at the rig's next step. An engine Animation's handle is left alone. (The Art hold whose
--- clip a render stall kept from its hold pose, D-138.)
function AnimatorClass.seek(self: any, handle: Handle, clipTime: number)
	if self.destroyed or (handle :: any).rbx ~= nil then
		return
	end
	fireEvents(self, self.mixer:seek(handle, clipTime))
end

--- Keeps a playing clip on the server's beat up to its first HitWindowOpen (D-172): an enemy's
--- attack clip ActionStarted played at `serverTime`. What the network catch-up could not jump of
--- the time since `serverTime` is owed from the start (less the part of a frame its first step
--- credits from before the play); every hit-stop on the rig is owed back less what shiftBeat says
--- the server paused. A clip without a hit window, an engine Animation's handle or one past its
--- mark keeps none.
function AnimatorClass.keepBeat(self: any, handle: Handle, serverTime: number?)
	if self.destroyed or (handle :: any).rbx ~= nil then
		return
	end
	local windows = ClipSampler.hitWindows(handle.clip)
	local first = windows[1]
	if first == nil then
		return
	end
	local owed = 0
	if serverTime ~= nil then
		owed = math.max(0, (engine.now() - serverTime) - handle.time / handle.speed)
	end
	-- Its first step moves it by the whole frame, the part before it was played too: that much
	-- ahead of the server, it gives that back.
	owed -= (handle :: any).sinceStep or 0
	self.mixer:keepBeat(handle, first.open, owed)
end

--- The server paused the attack a kept beat belongs to by `seconds` (negative takes back a pause
--- it never gave): the clip owes that much less.
function AnimatorClass.shiftBeat(self: any, handle: Handle, seconds: number)
	if (handle :: any).rbx ~= nil then
		return
	end
	self.mixer:shiftBeat(handle, seconds)
end

--- Draws the body `offset` away from the root part (in the root part's space) from this step on,
--- or back on its root with nil (D-171). The root part itself does not move.
function AnimatorClass.setBodyOffset(self: any, offset: CFrame?)
	self.bodyOffset = offset
end

--- The offset the body is drawn at from its root part (setBodyOffset), nil while it is on its root.
--- A step hook added after the one that sets it reads this step's (newer hooks run first).
function AnimatorClass.getBodyOffset(self: any): CFrame?
	return self.bodyOffset
end

function AnimatorClass.step(self: any, dt: number)
	if self.destroyed then
		return
	end
	if self.motorsDirty then
		rebuildMotors(self)
	end
	-- A render stall (D-132): a long step covers the time since this rig's last step on the clock.
	-- The clock saw the gap even if the engine's dt did not (an engine that hands back one frame
	-- after a stall would otherwise resume every clip where it stopped), and a rig that kept
	-- stepping on Heartbeat through the stall (ranked full rate only at the wake) does not take the
	-- gap a second time.
	local now = engine.now()
	local wall = math.max(0, now - self.rootDeltaAt)
	local jumpSeconds = ChoreoData.stall.jumpSeconds
	if (wall > jumpSeconds and wall > dt) or (dt > jumpSeconds and wall < dt) then
		dt = wall
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
	self.rootDeltaAt = now
	applyOffsets(self, result.offsets)
	fireEvents(self, result.events)
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
	if self.drawnPublished then
		self.drawnPublished = false
		DrawnBody.publish(self.model, nil)
	end
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
		events = Signal.new() :: Signal.Signal<string, Types.ClipEvent, boolean>,
		finished = Signal.new() :: Signal.Signal<Handle>,
		motors = {} :: { [string]: Joints.Joint },
		motorsDirty = true,
		pinned = {} :: { [string]: boolean },
		touched = {} :: { [string]: boolean },
		touchedScratch = {} :: { [string]: boolean },
		pose = {} :: { [string]: CFrame }, -- the Transform last written per joint name
		engineAnimated = false, -- an engine Animator resets the rig each frame (D-053)
		rootJoint = nil :: string?, -- the joint hanging the body on the root part (rootJointName)
		bodyOffset = nil :: CFrame?, -- where the body is drawn from its root part (setBodyOffset)
		drawnPublished = false, -- the last step published a body offset to DrawnBody
		stepHooks = {} :: { (dt: number) -> () },
		rootDelta = Vector3.zero,
		rootDeltaAt = engine.now(), -- engine.now() of the last step (the one that wrote rootDelta)
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

	silenceDefaultAnimations(self)
	rebuildMotors(self)

	-- The character's joints (and the engine's Animate script) can arrive after the model does: a
	-- replicated rig streams in part by part, and the engine can rebuild its joints (a respawn, a
	-- scale change). Any joint of either kind arriving or leaving rescans the map on the next step.
	local function onDescendantAdded(descendant: Instance)
		if Joints.isJoint(descendant) or descendant:IsA("Animator") then
			self.motorsDirty = true
		elseif descendant.Name == DEFAULT_ANIMATE_SCRIPT and descendant:IsA("LuaSourceContainer") then
			silenceAnimate(self, descendant)
		end
	end
	local function onDescendantRemoving(descendant: Instance)
		if Joints.isJoint(descendant) or descendant:IsA("Animator") then
			self.motorsDirty = true
		end
	end
	table.insert(self.connections, engine.connect(model, "DescendantAdded", onDescendantAdded))
	table.insert(self.connections, engine.connect(model, "DescendantRemoving", onDescendantRemoving))
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

-- Writes the rig's last pose again, after the engine's Animator put it back to rest (D-053). Only
-- a rig the engine animates needs it; a pinned joint stays at rest. Runs on PreSimulation for
-- every rig, whatever its update rate, since the Animator resets every frame.
local function reapplyPose(self: any)
	if self.destroyed or not self.engineAnimated or self.rbxActive then
		return
	end
	local motors = self.motors
	local pinned: { [string]: boolean } = self.pinned
	for name, transform in self.pose :: { [string]: CFrame } do
		local motor = motors[name]
		if motor ~= nil and not pinned[name] then
			motor.Transform = transform
		end
	end
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
		-- From where the body is drawn (a rush draws it ahead of its root part, D-193).
		local drawn = DrawnBody.position(animator.model)
		if camera ~= nil and drawn ~= nil then
			animator.distance = (drawn - camera).Magnitude
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
			-- A driven local rig is its owner's to step (stepLocal), never twice in a frame.
			if animator ~= nil and animator.rate == "Full" and not (localDriven and animator.model == localModel) then
				animator:step(dt)
			end
		end
	end)
	local preSimulation = engine.preSimulation
	if preSimulation ~= nil then
		preSimulation:Connect(function()
			for index = 1, #ordered do
				local animator = ordered[index]
				if animator ~= nil then
					reapplyPose(animator)
				end
			end
		end)
	end
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

--- Marks the local player's model: always full rate, never budgeted out. `driven`: its owner (the
--- character controller) steps it itself with Choreo.stepLocal from its own render step, so what
--- it reads of the rig (the root delta) comes from this frame's step; RenderStepped leaves it
--- alone then (D-139). Without it, RenderStepped steps it as any near rig (the ClipLab).
function Choreo.setLocalModel(model: Model?, driven: boolean?)
	localModel = model
	localDriven = model ~= nil and driven == true
	rerank()
end

--- Steps the local model's rig once, while its owner drives it (setLocalModel(model, true)); a
--- no-op otherwise, so the rig is never stepped twice in a frame. A step that comes back from a
--- render stall is a jump, as on RenderStepped (the rig's own clock saw the gap, D-132).
function Choreo.stepLocal(dt: number)
	local model = localModel
	if not localDriven or model == nil then
		return
	end
	local animator = registry[model]
	if animator ~= nil then
		animator:step(dt)
	end
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
