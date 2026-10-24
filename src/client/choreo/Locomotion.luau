--!strict
--[[
	Locomotion: the engine binding of the locomotion blend space (section 10 "Locomotion").

		local locomotion = Locomotion.new(animator, character)
		locomotion:update(dt, { moveDir = Vector3, speed = n, sprinting = b, grounded = b,
		                        drawn = b, turning = degrees, fallHeight = n? })
		locomotion:setDrawn(true)
		locomotion:destroy()

	It keeps one Base-layer handle per locomotion clip (Idle, IdleDrawn, and the walks, Run and
	Sprint twice: the sheathed set under the plain names, the drawn set under the ...Drawn names)
	and drives their weights from LocomotionState every frame. Before every animator step the gait
	clips (the walks, Run and Sprint of both sets) are paced to the root on one shared phase: the
	live weights give the blend's stride (the ground one cycle covers along the move, from
	locomotion.stride.groundSpeed) and natural cycle, the cycle time is that stride over the
	root's speed, and each clip runs its own duration in that time with its clock set from the
	phase (each clip's left Footstep at phase 0). So the planted foot moves back as fast as the root
	moves on, no clip drifts from another, a walk and its drawn twin stay in step, and each clip
	crosses its Footsteps once per plant. One-shots (Jump, Fall, Land, TurnLeft, TurnRight, Skid) play
	on the FullBody layer (a turn in place or a standing Land stops when the root starts to move;
	a landing on the move plays Land with no weight, for its sounds); the lean into turns, the drawn sprint "weapon low and back" pose and the
	raycast foot IK ride as procedural additive channels. The raycast is injected so the IK math
	stays pure and tested; the default uses workspace.

	The sheathed sword (a player rig whose weapon category has a weaponModels.luau sheaths row):
	`drawn` is the target (the server's Drawn attribute, or the local player's prediction). Before
	every animator step a hook feeds SheathState from the live clips and the target, plays or
	stops the Draw and Sheathe clips, and tells WeaponMount where the sword goes; the WeaponDraw and
	WeaponSheathe clip events move it mid-clip. Only the live clip's own event counts: a Draw or
	Sheathe that was stopped still runs through its fade, and its late event changes nothing. An
	attack, Guard, GuardHit or Parry clip pulls the sword to the hand before its first frame is
	posed (a draw-cut). The walk set follows the target at once; the Draw and Sheathe clips cover
	the arms. A clip above them that keys the right arm (a turn, a landing, a dodge, a stagger)
	hides the hand from the hilt, so the sword waits for it (SheathState "covered"). Nothing starts
	while the State attribute is Dead. A rig that cannot sheathe keeps the sword in the hand.

	The Drawn and State attributes are followed through their change signals, so no step reads
	them (`serverDrawn()` gives the Drawn attribute to the character controller). An instance with
	no signals (a Lune test rig) falls back to reading them once a step.

	The drawn sprint pose follows SprintDrawn's live weight, so it fades with the blend space
	instead of jumping when the target flips. It is off while the sword is on its sheath and gives
	way to a Draw or Sheathe clip, so the hand meets the hilt at the handoff.

	For rigs the local CharacterController does not own (other players, enemies),
	Locomotion.attach(animator, character) runs a driver off the animator's own step: a player rig
	gets this same blend space fed by Locomotion.humanoidTracker (MoveDirection, velocity, floor
	contact, fall height); an enemy rig gets its data Idle / Walk pair (data/choreo.luau rigs)
	crossfaded by speed with the walk clip paced to the rig's walkSpeed, so no foot slides. Both of
	an enemy's loops start at its own phase (Locomotion.idlePhase of its entity id, D-123), so
	neighbours never breathe or roar in step.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)
local Rigs = require(Shared.data.rigs)
local WeaponModels = require(Shared.data.weaponModels)
local Types = require(Shared.types)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Easing = require(Shared.util.Easing)
local ClipLibrary = require(script.Parent.ClipLibrary)
local LocomotionState = require(script.Parent.LocomotionState)
local SheathState = require(script.Parent.SheathState)
local WeaponMount = require(script.Parent.WeaponMount)

local Config = ChoreoData.locomotion
local Sheath = ChoreoData.sheath
local Stride = Config.stride
local GAIT_NAMES = LocomotionState.GAIT_NAMES
local WEIGHT_NAMES = LocomotionState.WEIGHT_NAMES

local DRAWN_ATTRIBUTE = "Drawn"
local STATE_ATTRIBUTE = "State"
local DEAD: Types.EntityState = "Dead"
local DRAW_EVENT = "WeaponDraw"
local SHEATHE_EVENT = "WeaponSheathe"

-- The Draw and Sheathe clip ids.
local DRAW_ID = Config.clipPrefix .. Sheath.clips.draw
local SHEATHE_ID = Config.clipPrefix .. Sheath.clips.sheathe

local function sheathClipId(clip: SheathState.Clip): string
	return if clip == "Draw" then DRAW_ID else SHEATHE_ID
end

-- Clip names (the id's last segment) that start with the sword in the hand, besides attacks.
local DRAW_CUT_NAMES: { [string]: boolean } = {}
for _, name in Sheath.drawCutClips do
	DRAW_CUT_NAMES[name] = true
end
local drawCutById: { [string]: boolean } = {}

export type State = {
	moveDir: Vector3, -- world-space move direction (any length; zero when still)
	speed: number, -- horizontal studs per second
	sprinting: boolean,
	grounded: boolean,
	drawn: boolean?, -- overrides setDrawn when given
	turning: number, -- signed degrees from the facing to the desired facing (+ = left)
	fallHeight: number?, -- studs fallen, on the landing frame
	verticalVelocity: number?,
	-- The clock the root itself moves on, when it is slowed with the clips (the local body in a
	-- dev capture, CharacterController.setCaptureTimeScale; nil = real time, as for every remote
	-- rig): the blend reads the root's speed and turn at 1x, dividing by it.
	clockScale: number?,
}

export type Raycast = (origin: Vector3, direction: Vector3) -> Vector3?

export type Dependencies = {
	raycast: Raycast?,
	footIK: boolean?, -- default true
	tracker: ((dt: number) -> State?)?, -- attach only: the state source (default humanoidTracker)
	-- attach only, an enemy rig: how far round the loop (0 .. 1) its idle and walk start
	-- (Locomotion.idlePhase of its entity id; default 0).
	phase: number?,
	-- The change signal of an attribute on the character (default GetAttributeChangedSignal).
	attributeSignal: ((instance: Instance, name: string) -> any)?,
}

export type Locomotion = {
	update: (self: Locomotion, dt: number, state: State) -> LocomotionState.Output,
	setDrawn: (self: Locomotion, drawn: boolean) -> (),
	serverDrawn: (self: Locomotion) -> boolean,
	stopGait: (self: Locomotion, into: LocomotionState.StopGait) -> (),
	destroy: (self: Locomotion) -> (),
}

-- True for a clip that starts with the sword in the hand: an attack or a sheath.drawCutClips name.
local function isDrawCut(clip: Types.ClipDef): boolean
	local cached = drawCutById[clip.id]
	if cached == nil then
		cached = clip.attack == true or DRAW_CUT_NAMES[clip.id:match("[^/]+$") or clip.id] == true
		drawCutById[clip.id] = cached
	end
	return cached :: boolean
end

-- The arm joints the Draw and Sheathe clips move (the sword's own joint left out). Read once from
-- the clips; empty when a build has neither clip.
local sheathArm: { [string]: boolean }? = nil
local function sheathArmJoints(): { [string]: boolean }
	local joints = sheathArm
	if joints == nil then
		local found: { [string]: boolean } = {}
		for _, id in { DRAW_ID, SHEATHE_ID } do
			if ClipLibrary.has(id) then
				for _, key in ClipLibrary.get(id).keys do
					for name in key.joints do
						if name ~= WeaponModels.motorName then
							found[name] = true
						end
					end
				end
			end
		end
		sheathArm = found
		joints = found
	end
	return joints :: { [string]: boolean }
end

-- Clip id -> whether the clip keys one of the sheath clips' arm joints.
local keysArmById: { [string]: boolean } = {}

-- True when a handle hides the hand from the hilt: a clip that outranks Draw and Sheathe on the
-- arm (any FullBody clip, or a higher UpperBody one) and keys an arm joint they move. The caller
-- skips a weightless one (a Land on the move): it hides nothing.
local function coversArm(handle: any): boolean
	local above = handle.layer == "FullBody"
		or (handle.layer == "UpperBody" and handle.priority > ChoreoData.priority.Sheath)
	if not above then
		return false
	end
	local clip: Types.ClipDef = handle.clip
	local keysArm = keysArmById[clip.id]
	if keysArm == nil then
		keysArm = false
		local arm = sheathArmJoints()
		for _, key in clip.keys do
			for name in key.joints do
				if arm[name] then
					keysArm = true
					break
				end
			end
			if keysArm then
				break
			end
		end
		keysArmById[clip.id] = keysArm
	end
	return keysArm :: boolean
end

local Locomotion = {}
Locomotion.__index = Locomotion

local function clipId(name: string): string
	return Config.clipPrefix .. Config.clips[name]
end

local function wrapDegrees(angle: number): number
	return (angle + 180) % 360 - 180
end

local function yawOf(cframe: CFrame): number
	local look = cframe.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

-- The drawn-sprint data pose as full offsets (pos filled with zero) so the mixer can add it.
local function poseOffsets(pose: { [string]: { pos: { number }?, rot: { number }? } }): ClipSampler.Offsets
	local offsets: ClipSampler.Offsets = {}
	for name, key in pose do
		offsets[name] = { pos = key.pos or { 0, 0, 0 }, rot = key.rot or { 0, 0, 0 } }
	end
	return offsets
end

local DRAWN_SPRINT = poseOffsets(Config.drawnSprintPose)

local function defaultRaycast(character: Model): Raycast
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return function(origin: Vector3, direction: Vector3): Vector3?
		local result = workspace:Raycast(origin, direction, params)
		return if result then result.Position else nil
	end
end

-- Enemy rig driver (data Idle / Walk pair), defined below Locomotion; declared here so
-- Locomotion.destroy can dispatch to it.
local RigDriver = {}

local function defaultAttributeSignal(instance: Instance, name: string): any
	return instance:GetAttributeChangedSignal(name)
end

-- Copies the character's Drawn and State attributes onto the driver.
local function readAttributes(self: any)
	self.attributeDrawn = self.character:GetAttribute(DRAWN_ATTRIBUTE) == true
	self.dead = self.character:GetAttribute(STATE_ATTRIBUTE) == DEAD
end

-- Follows the Drawn and State attributes through their change signals. When the character has no
-- signals (Lune), `pollAttributes` is set and the step reads them instead.
local function followAttributes(self: any, signalOf: (instance: Instance, name: string) -> any)
	readAttributes(self)
	for _, name in { DRAWN_ATTRIBUTE, STATE_ATTRIBUTE } do
		local ok, connection = pcall(function()
			return signalOf(self.character, name):Connect(function()
				readAttributes(self)
			end)
		end)
		if ok and connection ~= nil then
			table.insert(self.attributeConnections, connection)
		else
			self.pollAttributes = true
		end
	end
end

-- What the live clips say this step: a draw-cut, a clip that hides the arm, the Draw clip, the
-- Sheathe clip; and the target. Also returns how much of the Draw and Sheathe clips the limbs show
-- (stopping ones included), for the drawn sprint pose.
local function scanClips(self: any): (SheathState.Input, number)
	local cut, covered, drawing, sheathing = false, false, false, false
	local sheathWeight = 0
	for _, handle in self.animator.mixer:handles() do
		if handle.done then
			continue
		end
		local isSheathClip = handle.clipId == DRAW_ID or handle.clipId == SHEATHE_ID
		if isSheathClip then
			local shown = Easing.evaluate(ChoreoData.blendEasing, handle.fade) * handle.weight
			sheathWeight = math.max(sheathWeight, shown)
		end
		if handle.stopping then
			continue
		end
		if handle.clipId == DRAW_ID then
			drawing = true
		elseif handle.clipId == SHEATHE_ID then
			sheathing = true
		else
			if isDrawCut(handle.clip) then
				cut = true
			end
			if handle.weight > 0 and coversArm(handle) then
				covered = true
			end
		end
	end
	local input: SheathState.Input = {
		target = self.drawn,
		cut = cut,
		covered = covered,
		drawing = drawing,
		sheathing = sheathing,
		hold = self.dead,
	}
	return input, sheathWeight
end

-- True when an event comes from the live clip of that id: one that is not stopping and whose
-- clock has reached the event. A stopped Draw or Sheathe still runs through its fade, and a new
-- one may already have started, so the stopped clip's late event moves nothing.
local function fromLiveClip(self: any, clipId: string, time: number): boolean
	for _, handle in self.animator.mixer:handles() do
		if handle.clipId == clipId and not handle.stopping and not handle.done and handle.time >= time then
			return true
		end
	end
	return false
end

local function sheathInput(self: any): SheathState.Input
	local input = scanClips(self)
	return input
end

-- The place the target asks for with no clip in between.
local function targetPlace(self: any): WeaponMount.Place
	return if self.drawn then "Hand" else "Back"
end

-- Plays a sheath clip; a build without the clip moves the sword at once instead.
local function playSheathClip(self: any, clip: SheathState.Clip)
	local id = sheathClipId(clip)
	if ClipLibrary.has(id) then
		self.animator:play(id)
	else
		self.sheath.place = if clip == "Draw" then "Hand" else "Back"
	end
end

-- The sheath step: runs before the mixer, so the sword's move and the clip pose land together.
-- The mount's own step hook runs right after this one and puts the sword where it is wished.
local function stepSheath(self: any, dt: number)
	if self.pollAttributes then
		readAttributes(self)
	end
	local mount = self.mount
	if not mount:sheathable() then
		return
	end
	local generation = mount:generation()
	if generation ~= self.mountGeneration then
		-- A new sword motor (an equip, a respawn, a late stream): snap to the target, no clip.
		self.mountGeneration = generation
		self.sheath.place = targetPlace(self)
	end
	local input, sheathWeight = scanClips(self)
	self.sheathClipWeight = sheathWeight
	local out = self.sheath:step(dt, input)
	if out.stop ~= nil then
		self.animator:stop(sheathClipId(out.stop), Sheath.stopBlend)
	end
	if out.play ~= nil then
		playSheathClip(self, out.play)
	end
	if mount:get() ~= self.sheath.place then
		mount:set(self.sheath.place)
	end
end

-- A WeaponDraw or WeaponSheathe event from the live clip moves the sword mid-clip, when it still
-- fits the target.
local function onClipEvent(self: any, clipId: string, event: Types.ClipEvent)
	local kind = event.kind :: string
	if self.destroyed or (kind ~= DRAW_EVENT and kind ~= SHEATHE_EVENT) or not self.mount:sheathable() then
		return
	end
	if not fromLiveClip(self, clipId, event.time) then
		return
	end
	local place = self.sheath:onEvent(kind, sheathInput(self))
	if place ~= nil then
		self.mount:set(place)
	end
end

-- The shared phase's pace limits (cycles per second): every gait clip's own speed stays inside
-- the mixer's [minSpeed, maxSpeed], so no clock is clamped out of step.
local paceLimits: { number }? = nil
local function paceRange(): (number, number)
	local limits = paceLimits
	if limits == nil then
		local shortest, longest = math.huge, 0
		for _, gait in LocomotionState.gaits() do
			shortest = math.min(shortest, gait.duration)
			longest = math.max(longest, gait.duration)
		end
		limits = { ChoreoData.minSpeed / shortest, ChoreoData.maxSpeed / longest }
		paceLimits = limits
	end
	local range = limits :: { number }
	return range[1], range[2]
end

-- Paces the gait clips to the root (runs before the mixer step; no allocation). The blend's stride
-- is the ground its shown gait clips cover per cycle along the move, over everything the Base set
-- shows (an Idle share shortens the step); its natural cycle is the shown clips' mean duration.
-- The rate that makes the planted foot keep pace with the root is speed x natural / stride, held
-- inside stride.rateFloor .. rateCeiling. A change of weights moves the planted foot too (each
-- clip has it somewhere else: stride.touchdown), so the phase also takes up last step's change.
-- Each clip then runs its duration per cycle from the shared phase, which advances with the
-- mixer's clock (held through hit-stop, scaled with it).
local function stepGait(self: any, dt: number)
	local gaits = LocomotionState.gaits()
	local handles = self.handles
	local shownNow, shownLast = self.shownNow, self.shownLast
	local forward, right = self.travelForward, self.travelRight
	local phase = self.gaitPhase
	local stride, natural, gaitShown, baseShown, planted = 0, 0, 0, 0, 0
	for _, name in WEIGHT_NAMES do
		local handle = handles[name]
		local weight = handle.weight
		local shown = 0
		if weight > 0 then
			shown = Easing.evaluate(ChoreoData.blendEasing, handle.fade) * weight
			baseShown += shown
			local gait = gaits[name]
			if gait ~= nil and shown > 0 then
				local along = if gait.walk then gait.forward * forward + gait.right * right else self.runAlong
				stride += shown * gait.stride * along
				natural += shown * gait.duration
				gaitShown += shown
			end
			planted += shown * LocomotionState.plantedAlong(name, phase, forward, right)
		end
		shownNow[name] = shown
	end
	local minPace, maxPace = paceRange()
	local pace = self.gaitPace or Stride.rateFloor / gaits.WalkForward.duration
	local mixer = self.animator.mixer
	local scale = mixer:timeScale()
	local running = mixer:pauseRemaining() <= ChoreoData.pauseEpsilon
	if gaitShown > 0 then
		natural /= gaitShown
		stride = math.max(stride / baseShown, Stride.minGroundSpeed * natural)
		-- The clips run on the mixer's scaled clock (dev slow motion), the root on real time.
		local speed = if scale > 0 then self.speed / scale else self.speed
		local rate = math.clamp(speed * natural / stride, Stride.rateFloor, Stride.rateCeiling)
		pace = math.clamp(rate / natural, minPace, maxPace)
		if running and dt > 0 and scale > 0 then
			-- Last step's weight change pulled the planted foot along the move by `moved` studs;
			-- the phase takes it up (never backwards) on top of this step's advance.
			planted /= baseShown
			local moved = 0
			for _, name in WEIGHT_NAMES do
				local change = shownNow[name] - shownLast[name]
				if change ~= 0 then
					moved += change * (LocomotionState.plantedAlong(name, phase, forward, right) - planted)
				end
			end
			local advance = dt * scale * pace + moved / baseShown / stride
			pace = math.clamp(advance / (dt * scale), minPace, maxPace)
		end
		self.gaitPace = pace
	else
		-- Standing: every start steps off from the same point of the cycle.
		phase = Stride.startPhase
		self.gaitPhase = phase
	end
	for _, name in WEIGHT_NAMES do
		shownLast[name] = shownNow[name]
	end
	local animator = self.animator
	for _, name in GAIT_NAMES do
		local handle = handles[name]
		-- A clip with no weight now and none ahead keeps its own clock: it is put back on the
		-- phase on the step its target weight rises, before the mixer shows it.
		if handle.weight > 0 or (handle.targetWeight or 0) > 0 then
			local gait = gaits[name]
			handle.time = ((phase + gait.offset) % 1) * gait.duration
			animator:setSpeed(handle, gait.duration * pace)
		end
	end
	if gaitShown > 0 and running then
		self.gaitPhase = (phase + dt * scale * pace) % 1
	end
end

--- Creates the locomotion driver for a player rig's animator and its character model.
function Locomotion.new(animator: any, character: Model, deps: Dependencies?): Locomotion
	local dependencies: Dependencies = deps or {}
	local self = setmetatable({
		animator = animator,
		character = character,
		state = LocomotionState.new(),
		handles = {} :: { [string]: any },
		fallHandle = nil :: any,
		jumpHandle = nil :: any,
		jumpHandoff = nil :: any, -- the finished connection that hands the jump to the fall
		turnHandle = nil :: any,
		landHandle = nil :: any,
		drawn = character:GetAttribute(DRAWN_ATTRIBUTE) == true,
		lastYaw = nil :: number?,
		raycast = dependencies.raycast,
		footIK = dependencies.footIK ~= false,
		hipHeight = (Rigs[animator.rigId] or Rigs.PlayerR15).hipHeight,
		mount = nil :: any,
		sheath = nil :: any,
		mountGeneration = 0,
		sheathClipWeight = 0, -- how much of the Draw and Sheathe clips the limbs showed last step
		unhookSheath = nil :: (() -> ())?,
		clipEvents = nil :: any,
		attributeDrawn = false, -- the Drawn attribute (the server's word), kept by its change signal
		dead = false, -- the State attribute is Dead, kept by its change signal
		attributeConnections = {} :: { any },
		pollAttributes = false, -- the character has no attribute signals: the step reads them
		speed = 0, -- the root's horizontal speed from the last update
		travelForward = 1, -- the last move direction in the character's frame
		travelRight = 0,
		-- How far along the move a stud of Run's or Sprint's stride carries (LocomotionState.runAlong)
		runAlong = 1,
		gaitPhase = Stride.startPhase, -- the shared gait phase: 0..1 of a cycle, 0 at every left Footstep
		gaitPace = nil :: number?, -- cycles per second the phase last advanced at
		shownNow = {} :: { [string]: number }, -- each Base clip's shown weight at this step's start
		shownLast = {} :: { [string]: number }, -- and at the last step's
		destroyed = false,
	}, Locomotion)
	if self.raycast == nil and self.footIK then
		self.raycast = defaultRaycast(character)
	end
	followAttributes(self, dependencies.attributeSignal or defaultAttributeSignal)
	for _, name in LocomotionState.WEIGHT_NAMES do
		self.handles[name] = animator:play(clipId(name), { coexist = true, weight = 0, blendIn = 0 })
		self.shownNow[name] = 0
		self.shownLast[name] = 0
	end
	animator:setWeight(self.handles[LocomotionState.clipFor("Idle", self.drawn)], 1, true)

	-- The sword starts where the target wants it, with no clip.
	self.mount = WeaponMount.new(animator, character)
	self.sheath = SheathState.new(targetPlace(self), Sheath)
	self.mountGeneration = self.mount:generation()
	if self.mount:sheathable() then
		self.mount:set(self.sheath.place)
	end
	self.unhookSheath = animator:onStep(function(dt: number)
		if not self.destroyed then
			stepSheath(self, dt)
			stepGait(self, dt)
		end
	end)
	self.clipEvents = animator.events:Connect(function(eventClipId: string, event: Types.ClipEvent)
		onClipEvent(self, eventClipId, event)
	end)
	return (self :: any) :: Locomotion
end

function Locomotion.setDrawn(self: any, drawn: boolean)
	self.drawn = drawn
end

--- The gait as the two-step stop needs it (ActionLogic.stopCarryStep), written into `into`: the
--- shared phase, and where the walk of the last move direction has each planted foot over its
--- Idle spot (LocomotionState.settlePoints). No allocation.
function Locomotion.stopGait(self: any, into: LocomotionState.StopGait)
	into.phase = self.gaitPhase
	into.leftStep, into.leftAfter, into.rightStep, into.rightAfter =
		LocomotionState.settlePoints(self.travelForward, self.travelRight, self.drawn)
end

--- The character's Drawn attribute (the server's word, nil read as false), kept by its change
--- signal so the caller reads no attribute per frame.
function Locomotion.serverDrawn(self: any): boolean
	if self.pollAttributes then
		readAttributes(self)
	end
	return self.attributeDrawn
end

local function playOneShot(self: any, name: string, weight: number?)
	return self.animator:play(clipId(name), { weight = weight })
end

-- Drops the jump's handoff to the fall (landed before the jump clip ended, jumped again, or gone).
local function dropJumpHandoff(self: any)
	if self.jumpHandoff ~= nil then
		self.jumpHandoff:Disconnect()
		self.jumpHandoff = nil
	end
end

local function footDeltas(self: any, root: BasePart): (number?, number?)
	local raycast: Raycast = self.raycast
	local ik = Config.footIK
	local expectedGround = root.Position.Y - self.hipHeight - root.Size.Y * 0.5
	local rightVector = root.CFrame.RightVector
	local function probe(side: number): number?
		local base = root.Position + rightVector * (side * ik.footSpacing)
		local origin = Vector3.new(base.X, expectedGround + ik.rayStart, base.Z)
		local hit = raycast(origin, Vector3.new(0, -(ik.rayStart + ik.rayLength), 0))
		return if hit then hit.Y - expectedGround else nil
	end
	return probe(-1), probe(1)
end

-- How much of the drawn sprint pose ("weapon low and back") shows. It rides on SprintDrawn's live
-- weight, which the mixer moves at the blend-space rate, so it never jumps when the target flips.
-- It holds a sword in the hand: off while the sword is on its sheath, and it gives way to a Draw or
-- Sheathe clip moving the arm, so the hand is on the hilt when the sword changes hands.
local function drawnSprintWeight(self: any): number
	local handle = self.handles.SprintDrawn
	local weight: number = if handle ~= nil then handle.weight else 0
	if weight <= 0 then
		return 0
	end
	if self.sheath.place == "Back" and self.mount:sheathable() then
		return 0
	end
	return weight * (1 - math.clamp(self.sheathClipWeight, 0, 1))
end

-- The lean as posed: each clip in locomotion.lean.upright holds back a lean toward its side by
-- its shown weight (the drawn left walk would roll the scabbard into its own left leg).
local function uprightLean(self: any, lean: number): number
	for name, side in Config.lean.upright do
		local handle = self.handles[name]
		if handle ~= nil and lean * side > 0 then
			local shown = Easing.evaluate(ChoreoData.blendEasing, handle.fade) * handle.weight
			lean *= 1 - math.clamp(shown, 0, 1)
		end
	end
	return lean
end

function Locomotion.update(self: any, dt: number, state: State): LocomotionState.Output
	local animator = self.animator
	local root: BasePart? = self.character.PrimaryPart or self.character:FindFirstChild("HumanoidRootPart") :: any
	-- A root slowed with its clips is read at 1x (State.clockScale): a slowed capture's run blends
	-- the run, not the walk its slowed speed would pick. The pace keeps the root's real speed.
	local clock = state.clockScale or 1
	local blendSpeed = if clock > 0 then math.max(0, state.speed) / clock else math.max(0, state.speed)
	local forward, right = 0, 0
	local yawRate = 0
	if root ~= nil then
		local cframe = root.CFrame
		local move = Vector3.new(state.moveDir.X, 0, state.moveDir.Z)
		if move.Magnitude > 0 then
			move = move.Unit
			forward = move:Dot(cframe.LookVector)
			right = move:Dot(cframe.RightVector)
		end
		local yaw = yawOf(cframe)
		if self.lastYaw ~= nil and dt > 0 and clock > 0 then
			yawRate = wrapDegrees(yaw - self.lastYaw) / dt / clock
		end
		self.lastYaw = yaw
	end
	if state.drawn ~= nil then
		self.drawn = state.drawn
	end
	self.speed = math.max(0, state.speed)
	if forward ~= 0 or right ~= 0 then
		self.travelForward, self.travelRight = forward, right
	elseif blendSpeed > Config.idleSpeedThreshold then
		-- Moving with no stick (a coast, a shove): the blend keeps the last move direction.
		forward, right = self.travelForward, self.travelRight
	end

	local input: LocomotionState.Input = {
		forward = forward,
		right = right,
		speed = blendSpeed,
		sprinting = state.sprinting,
		grounded = state.grounded,
		drawn = self.drawn,
		turning = state.turning,
		yawRate = yawRate,
		verticalVelocity = state.verticalVelocity or 0,
		fallHeight = state.fallHeight,
	}
	local output = self.state:update(dt, input)
	self.runAlong = LocomotionState.runAlong(input)

	for name, weight in output.weights do
		animator:setWeight(self.handles[name], weight)
	end

	local oneShot = output.oneShot
	if oneShot == "Jump" then
		dropJumpHandoff(self)
		local handle = playOneShot(self, "Jump")
		self.jumpHandle = handle
		-- Fall takes over when the jump clip ends, if still airborne. Another clip (a flinch, a
		-- guard hit, a parry) can finish first, so the handoff waits for the jump's own handle.
		self.jumpHandoff = animator.finished:Connect(function(finished: any)
			if finished ~= handle then
				return
			end
			dropJumpHandoff(self)
			if not self.destroyed and self.state.phase == "Air" then
				self.fallHandle = playOneShot(self, "Fall")
			end
		end)
	elseif oneShot == "Fall" then
		self.fallHandle = playOneShot(self, "Fall")
	elseif oneShot == "Land" then
		dropJumpHandoff(self)
		if self.fallHandle ~= nil then
			animator:stop(self.fallHandle, ChoreoData.oneShotBlendIn)
			self.fallHandle = nil
		end
		if self.jumpHandle ~= nil then
			animator:stop(self.jumpHandle, ChoreoData.oneShotBlendIn)
			self.jumpHandle = nil
		end
		-- On the move Land has no weight: it plays for its sounds only.
		local land = playOneShot(self, "Land", output.oneShotWeight)
		self.landHandle = if output.oneShotWeight > 0 then land else nil
	elseif oneShot == "TurnLeft" or oneShot == "TurnRight" then
		self.turnHandle = playOneShot(self, oneShot)
	elseif oneShot ~= nil then
		playOneShot(self, oneShot)
	end
	-- A turn in place or a standing Land gives way to the first steps (their feet would slide
	-- under the moving root).
	if output.phase == "Move" then
		if self.turnHandle ~= nil then
			animator:stop(self.turnHandle, ChoreoData.oneShotBlendIn)
			self.turnHandle = nil
		end
		if self.landHandle ~= nil then
			animator:stop(self.landHandle, ChoreoData.oneShotBlendIn)
			self.landHandle = nil
		end
	end

	animator:setProcedural(
		"lean",
		LocomotionState.leanOffsets(uprightLean(self, output.lean)),
		ChoreoData.additiveWeights.lean
	)
	animator:setProcedural(
		"drawnSprint",
		DRAWN_SPRINT,
		drawnSprintWeight(self) * ChoreoData.additiveWeights.drawnSprint
	)

	if self.footIK and root ~= nil then
		local weight = LocomotionState.footIKWeight(blendSpeed, state.grounded) * ChoreoData.additiveWeights.footIK
		if weight > 0 then
			local leftDelta, rightDelta = footDeltas(self, root)
			animator:setProcedural("footIK", LocomotionState.footIK(leftDelta, rightDelta, weight))
		else
			animator:setProcedural("footIK", nil)
		end
	end
	return output
end

function Locomotion.destroy(self: any)
	if getmetatable(self) == RigDriver then
		-- An enemy rig driver (Locomotion.attach) has its own teardown.
		RigDriver.destroy(self)
		return
	end
	if self.destroyed then
		return
	end
	self.destroyed = true
	dropJumpHandoff(self)
	if self.unhook ~= nil then
		self.unhook()
		self.unhook = nil
	end
	if self.unhookSheath ~= nil then
		self.unhookSheath()
		self.unhookSheath = nil
	end
	if self.clipEvents ~= nil then
		self.clipEvents:Disconnect()
		self.clipEvents = nil
	end
	for _, connection in self.attributeConnections do
		connection:Disconnect()
	end
	table.clear(self.attributeConnections)
	self.mount:destroy()
	for _, handle in self.handles do
		self.animator:stop(handle)
	end
	if self.fallHandle ~= nil then
		self.animator:stop(self.fallHandle)
	end
	for _, name in { "lean", "drawnSprint", "footIK" } do
		self.animator:setProcedural(name, nil)
	end
	table.clear(self.handles)
end

-- ---------------------------------------------------------------------------------------------
-- Remote rigs
-- ---------------------------------------------------------------------------------------------

-- An enemy rig's locomotion: its data Idle and Walk crossfaded by speed, the walk paced to the
-- rig's walkSpeed. Reactions and attacks ride above on FullBody / Additive as on every rig. Both
-- loops start `phase` of the way round (D-123), so a herd never breathes or roars in step.
RigDriver.__index = RigDriver

local function newRigDriver(animator: any, idleId: string, walkId: string, walkSpeed: number, phase: number): any
	local self = setmetatable({
		animator = animator,
		handles = {} :: { [string]: any },
		walkSpeed = math.max(walkSpeed, Config.idleSpeedThreshold),
		unhook = nil :: (() -> ())?,
		destroyed = false,
	}, RigDriver)
	local idleStart = phase * ClipLibrary.get(idleId).duration
	local walkStart = phase * ClipLibrary.get(walkId).duration
	self.handles.Idle = animator:play(idleId, { coexist = true, weight = 1, blendIn = 0, startTime = idleStart })
	self.handles.Walk = animator:play(walkId, { coexist = true, weight = 0, blendIn = 0, startTime = walkStart })
	return self
end

--- How far round its loops (0 .. 1) an enemy rig's idle and walk start: the fraction part of
--- id x choreo.enemyIdlePhaseStep (D-123). The same id always gets the same phase, and ids in a
--- row (a herd spawned together) land far apart. Cosmetic and client-only.
function Locomotion.idlePhase(entityId: number): number
	return (entityId * ChoreoData.enemyIdlePhaseStep) % 1
end

function RigDriver.update(self: any, _dt: number, state: State): LocomotionState.Output
	local speed = math.max(0, state.speed)
	local walk = if speed > Config.idleSpeedThreshold then math.clamp(speed / self.walkSpeed, 0, 1) else 0
	self.animator:setWeight(self.handles.Walk, walk)
	self.animator:setWeight(self.handles.Idle, 1 - walk)
	if walk > 0 then
		self.animator:setSpeed(self.handles.Walk, speed / self.walkSpeed)
	end
	return {
		weights = { Idle = 1 - walk, Walk = walk },
		oneShot = nil,
		oneShotWeight = 1,
		lean = 0,
		drawnSprint = 0,
		phase = if walk > 0 then "Move" else "Idle",
		airborne = not state.grounded,
	}
end

function RigDriver.setDrawn(_self: any, _drawn: boolean) end

-- An enemy rig keeps no shared phase: its stop needs no settle point.
function RigDriver.stopGait(_self: any, into: LocomotionState.StopGait)
	into.phase, into.leftStep, into.leftAfter, into.rightStep, into.rightAfter = 0, 0, 0, 0.5, 0
end

function RigDriver.serverDrawn(_self: any): boolean
	return false
end

function RigDriver.destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.unhook ~= nil then
		self.unhook()
		self.unhook = nil
	end
	for _, handle in self.handles do
		self.animator:stop(handle)
	end
	table.clear(self.handles)
end

--- Drives a rig the local controller does not own from the animator's own step. The state comes
--- from deps.tracker (default Locomotion.humanoidTracker(character)); a frame with no state (the
--- Humanoid or root is gone) is skipped. A player rig runs the full blend space; an enemy rig its
--- data Idle / Walk pair. Destroy it when the rig leaves (the animator's own destroy drops the hook).
function Locomotion.attach(animator: any, character: Model, deps: Dependencies?): Locomotion
	local dependencies: Dependencies = deps or {}
	local tracker = dependencies.tracker
	local rigId: string = animator.rigId
	local driver: any
	if rigId == "PlayerR15" then
		driver = Locomotion.new(animator, character, dependencies)
		if tracker == nil then
			-- The driver already follows the Drawn attribute; the tracker reads it from there.
			tracker = Locomotion.humanoidTracker(character, function(): boolean
				return driver:serverDrawn()
			end)
		end
	else
		local rigClips = ChoreoData.rigs[rigId]
		assert(
			rigClips ~= nil and rigClips.walk ~= nil,
			("Locomotion.attach: data/choreo.luau rigs.%s needs idle and walk clip ids"):format(rigId)
		)
		local rig = Rigs[rigId]
		driver = newRigDriver(
			animator,
			rigClips.idle,
			rigClips.walk,
			(rig and rig.walkSpeed) or Config.walkSpeed,
			dependencies.phase or 0
		)
	end
	local source: (dt: number) -> State? = tracker or Locomotion.humanoidTracker(character)
	driver.unhook = animator:onStep(function(dt: number)
		if driver.destroyed then
			return
		end
		local state = source(dt)
		if state ~= nil then
			driver:update(dt, state)
		end
	end)
	return (driver :: any) :: Locomotion
end

--- A per-frame state source for rigs driven by a Humanoid (other players, enemies): returns a
--- function(dt) -> State that reads MoveDirection, velocity, floor contact, the Drawn attribute
--- (from `drawnOf` when given, else from the character) and tracks fall height.
function Locomotion.humanoidTracker(character: Model, drawnOf: (() -> boolean)?): (dt: number) -> State?
	local peakY: number? = nil
	local wasGrounded = true
	return function(_dt: number): State?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart") :: any
		if humanoid == nil or root == nil then
			return nil
		end
		local velocity: Vector3 = (root :: BasePart).AssemblyLinearVelocity
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local y = (root :: BasePart).Position.Y
		local fallHeight: number? = nil
		if not grounded then
			peakY = math.max(peakY or y, y)
		elseif not wasGrounded then
			fallHeight = math.max(0, (peakY or y) - y)
			peakY = nil
		end
		wasGrounded = grounded
		return {
			moveDir = humanoid.MoveDirection,
			speed = horizontal.Magnitude,
			-- Sprinting: past halfway from run speed to sprint speed, so a run's noise never flips it.
			sprinting = horizontal.Magnitude > (Config.runSpeed + Config.sprintSpeed) / 2,
			grounded = grounded,
			-- A missing attribute means sheathed (the server writes it on player characters only).
			drawn = if drawnOf ~= nil then drawnOf() else character:GetAttribute(DRAWN_ATTRIBUTE) == true,
			turning = 0,
			fallHeight = fallHeight,
			verticalVelocity = velocity.Y,
		}
	end
end

return Locomotion
