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
	crosses its Footsteps once per plant. The phase also takes up how far the root really went
	(D-334): the engine moves it in whole 1/240 s physics steps, two to six to a rendered frame,
	while its velocity reads steady, so a frame's travel is a step or two off speed x dt. The gap
	(the root's move against speed x dt, held within locomotion.stride.travelSlipSeconds of travel)
	moves the phase too, so the planted foot stays where it is on the ground instead of hopping by
	that step every frame. Grounded and moving only; a teleport or shove past the bound is dropped.
	The root's physics position never changes. One-shots (Jump, Fall, Land, TurnLeft, TurnRight, Skid) play
	on the FullBody layer (a turn in place or a standing Land stops when the root starts to move;
	a landing on the move plays Land with no weight, for its sounds; a Skid called while a FullBody
	clip that outranks it holds the body, a dodge or an attack, does not play: it would only be
	heard, D-472); the lean into turns, the drawn sprint "weapon low and back" pose and the
	raycast foot IK ride as procedural additive channels (D-506: the IK measures the ground
	against the floor the Humanoid holds the root over, its own HipHeight, and a standHeight
	channel raises or lowers the body over its root by the gap between that floor and where this
	avatar's own legs reach in their bind pose, so the soles stand on the floor whatever the
	avatar; State.yawAhead, D-505, is the lock's turn still to land). The raycast is injected so the IK math
	stays pure and tested; the default uses workspace.

	A body held off its stick (D-144: walking into an enemy or a wall, slid along its flank): once
	the stick has settled, a root velocity off it blocks the body (locomotion.stride.blocked). The
	gait then goes the way of the root's smoothed velocity, paced by the root's speed along it, and
	stands while that velocity goes nowhere, so the legs never walk in place or skate. The stick
	letting go, a jump, or a whole walk along the stick ends it. The velocity is State.velocity,
	else the root's own when it is the reading `speed` came from; open ground is untouched.

	The sheathed sword (a player rig whose weapon category has a weaponModels.luau sheaths row):
	`drawn` is the target (the server's Drawn attribute, or the local player's prediction). Before
	every animator step a hook feeds SheathState from the live clips and the target, plays or
	stops the Draw and Sheathe clips, and tells WeaponMount where the sword goes; the WeaponDraw and
	WeaponSheathe clip events move it mid-clip. Only the live clip's own event counts: a Draw or
	Sheathe that was stopped still runs through its fade, and its late event changes nothing. An
	attack, Guard, GuardHit or Parry clip pulls the sword to the hand with its first posed frame
	(a draw-cut). A move the step asks for shows with the pose that step writes: with
	deps.atStepPoseSolve (FrameClock.atStepPoseSolve) WeaponMount lands it right before the physics
	that solves that pose, so the sword never hangs for a frame in the hand of the pose before
	(D-555) and is drawn on the pose's Weapon key, not its old place's rest turn (D-590); with
	deps.atStepPose alone, at the start of the first frame that draws that pose.
	The walk set follows the target at once; the Draw and Sheathe clips cover
	the arms. A clip above them that keys the right arm (a turn, a landing, a dodge, a stagger)
	hides the hand from the hilt, so the sword waits for it (SheathState "covered"), until it has
	faded out. A Skid that starts while a Draw or Sheathe is under way leaves that clip the arm and
	the sword's joint, and the clip's clock stands for the Skid's brake (sheath.skidBrakeSeconds,
	D-579): the stop never takes the swing over in a frame or throws the raised blade with the
	torso. A dodge does the same until it has gone (D-580): the arm stands where the clip had it
	while the body dodges, and the clip plays on after. And so does a stop with no Skid while the
	body brakes out of the run or sprint (sheath.stopBrakeClips and stopBrakeRate, D-611).
	Nothing starts while the State attribute is Dead. A rig that cannot sheathe keeps the sword in
	the hand.

	The Drawn and State attributes are followed through their change signals, so no step reads
	them (`serverDrawn()` gives the Drawn attribute to the character controller). An instance with
	no signals (a Lune test rig) falls back to reading them once a step.

	On the local rig, an attack clip let go before its first damage frame (an Art's stance or
	wind-up taken away by a hit, a refusal or a cancelled hold) fades out where it stood
	(Mixer.hold, D-294): played on, its fade ran the body on through the anticipation toward the
	first cut and crossed its sound and trail keys. Nothing of it has lit but the activation light,
	which CharacterController puts out as it lets the clip go. A clip let go after its first damage
	frame plays on through its fade, as before. A rig Locomotion.attach drives keeps the clock
	running: Replication puts a remote Art's light out on the HitWindowOpen its fade crosses (D-231).

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
local Pose = require(Shared.choreo.Pose)
local Easing = require(Shared.util.Easing)
local ClipLibrary = require(script.Parent.ClipLibrary)
local GaitHandOff = require(script.Parent.GaitHandOff)
local LocomotionState = require(script.Parent.LocomotionState)
local SheathState = require(script.Parent.SheathState)
local TurnPlant = require(script.Parent.TurnPlant)
local WalkTurnPlant = require(script.Parent.WalkTurnPlant)
local WalkStopPlant = require(script.Parent.WalkStopPlant)
local WeaponMount = require(script.Parent.WeaponMount)

local Config = ChoreoData.locomotion
local Sheath = ChoreoData.sheath
local Stride = Config.stride
local Blocked = Stride.blocked
-- A velocity whose direction is within stride.blocked.degrees of the stick has a dot above this.
local BLOCKED_COS = math.cos(math.rad(Blocked.degrees))
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
-- Of those, the ones a Draw plays over when the sword is on the back (a guard raised sheathed).
local DRAW_FIRST_NAMES: { [string]: boolean } = {}
for _, name in Sheath.drawFirstClips do
	DRAW_FIRST_NAMES[name] = true
end

-- Clip ids that come up as the cancel's snap with nothing to cut (choreo.luau
-- handOver.snapClips, D-527): the guard.
local SNAP_IDS: { [string]: boolean } = {}
for _, name in ChoreoData.handOver.snapClips do
	SNAP_IDS[Config.clipPrefix .. name] = true
end

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
	-- The root's velocity, the reading `speed` came from (nil: Locomotion reads the root's own).
	-- With the stick held, a velocity off the stick marks the body blocked (stride.blocked, D-144).
	velocity: Vector3?,
	-- D-505: degrees (+ = left) the root turns after this step and before the frame that shows
	-- this step's pose (the lock's turn, which CharacterController writes on PreSimulation). The
	-- facing is read as the root will stand then, so the turn plant takes back the yaw the frame
	-- shows with this pose, not the one before it. Nil or 0: the root as it stands.
	yawAhead: number?,
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
	-- FrameClock.atStepPose (D-343), handed to WeaponMount: a move of the sword the step asks for
	-- lands on the frame that draws that step's pose (D-555). Nil: it lands at once.
	atStepPose: ((fn: () -> ()) -> () -> ())?,
	-- FrameClock.atStepPoseSolve, handed to WeaponMount ahead of atStepPose: that move lands right
	-- before the physics that solves the step's pose, so the blade is drawn on its key (D-590).
	atStepPoseSolve: ((fn: () -> ()) -> () -> ())?,
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

-- True for a sheath.drawFirstClips clip (never an attack): with the sword on the back the Draw
-- plays over it, where any other draw-cut takes the sword to the hand at once.
local function isDrawFirst(clip: Types.ClipDef): boolean
	return clip.attack ~= true and DRAW_FIRST_NAMES[clip.id:match("[^/]+$") or clip.id] == true
end

-- An attack clip's first damage frame: the time of its first HitWindowOpen, TrailOn or SmearOn
-- (the first thing it lights after the activation), math.huge for a clip with none.
local firstStrikeById: { [string]: number } = {}
local function firstStrike(clip: Types.ClipDef): number
	local cached = firstStrikeById[clip.id]
	if cached == nil then
		local first = math.huge
		local events = clip.events
		if events ~= nil then
			for _, event in events do
				if event.kind == "HitWindowOpen" or event.kind == "TrailOn" or event.kind == "SmearOn" then
					first = math.min(first, event.time)
				end
			end
		end
		cached = first
		firstStrikeById[clip.id] = first
	end
	return cached :: number
end

-- An attack clip let go before its first damage frame fades out where it stood (D-294): its clock
-- stands from this step on, so the fade shows the pose it was let go in and crosses none of its
-- keys or events. Runs before the mixer steps, so a clip let go between frames stands from the
-- step that follows.
local function holdCutAttacks(mixer: any, handles: { any })
	for _, handle in handles do
		if handle.stopping and not handle.held and not handle.done and not handle.ended then
			local clip = handle.clip
			if typeof(clip) == "table" and clip.attack == true and handle.time < firstStrike(clip) then
				mixer:hold(handle)
			end
		end
	end
end

-- An attack that starts while a gait clip shows takes the body from it (D-404, GaitHandOff): on
-- its first step its legs, root and arms get their own blend in (choreo.luau locomotion.handOff),
-- and the gait's phase stands where the attack found it until the attack lets go, so the feet
-- stay where they were and no stride is crossed into the attack's first pose in a frame. An
-- attack chained over one that held the gait holds it on. A dodge that played to its end hands
-- the legs back at locomotion.dodgeHandOff.resumePhase (D-609): every dodge lands in one pose,
-- and a stride picked up where the press found it crossed a lower leg swinging away from that
-- landing in the blend out (25.2 degrees a 60 Hz row out of the sheathed run at 16). The jump is
-- under the dodge's whole pose: its last step showed every joint at full weight. Runs before the
-- mixer steps (a handle played this frame has not stepped yet).
-- True when every clip a fresh `dodge` cut this step (stopping, closing on the cut) is a one-shot
-- it takes the body from as from a stance (GaitHandOff.dodgeTakesFrom, D-613), and it cut one.
local function cutsOnlyStances(handles: { any }, dodge: any): boolean
	local any = false
	for _, other in handles do
		if other ~= dodge and other.closes and other.stopping and not other.done then
			local clip = other.clip
			if typeof(clip) ~= "table" or not GaitHandOff.dodgeTakesFrom(clip) then
				return false
			end
			any = true
		end
	end
	return any
end

local function handOffAttacks(self: any, mixer: any, handles: { any })
	local holder = self.gaitHeldBy
	if holder ~= nil and (holder.stopping or holder.done) then
		self.gaitHeldBy = nil
		if holder.ended and typeof(holder.clip) == "table" and GaitHandOff.dodges(holder.clip) then
			self.gaitPhase = Config.dodgeHandOff.resumePhase
		end
	end
	for _, handle in handles do
		local clip = handle.clip
		if
			handle.fresh
			and not handle.stopping
			and not handle.done
			and typeof(clip) == "table"
			and GaitHandOff.applies(clip)
		then
			if self.gaitShown > 0 then
				mixer:handOff(handle, GaitHandOff.blends(clip))
				self.gaitHeldBy = handle
			elseif holder ~= nil then
				self.gaitHeldBy = handle
			end
		elseif
			handle.fresh
			and not handle.stopping
			and not handle.done
			and typeof(clip) == "table"
			and GaitHandOff.dodges(clip)
		then
			-- A dodge (D-528) takes every stance and gait over its joints' own blends, unless it
			-- cuts an action (the cancel's snap, D-408); a gait's phase stands under it. A turn in
			-- place it cut is a stance (D-613): the turn, held where it was, fades out over the
			-- dodge's longest joint blend, so no joint shows the stance it was turning from.
			if not handle.handOver or cutsOnlyStances(handles, handle) then
				mixer:handOff(handle, GaitHandOff.dodgeBlends())
				if handle.handOver then
					local seconds = GaitHandOff.dodgeBlendSeconds()
					for _, other in handles do
						if other ~= handle and other.closes and other.stopping and not other.done then
							other.blendOut = math.max(other.blendOut, seconds)
						end
					end
				end
			end
			if self.gaitShown > 0 or holder ~= nil then
				self.gaitHeldBy = handle
			end
		end
	end
end

-- The guard comes up as a snap (D-527, choreo.luau handOver.snapClips): raised with the sword in
-- the hand and no Draw or Sheathe under way, a guard that cut nothing takes the body over the
-- cancel's handOver.seconds (Mixer.snapIn) as one out of a basic does (D-408), not its own 0.08 s
-- blend: blended, the arms turned 24 to 34 degrees a 60 Hz row on the fourth row after the press.
-- With the sword on the back the Draw plays over it (SheathState, D-420), and over a Draw or a
-- Sheathe it keeps its blend: the sheath's tip and turn limits hold the blade there. Runs before
-- the sheath step and the mixer (a handle played this frame has not stepped yet).
local function snapRaises(self: any, mixer: any, handles: { any })
	local fresh = false
	for _, handle in handles do
		if handle.fresh and SNAP_IDS[handle.clipId] == true and not handle.handOver then
			fresh = true
		end
	end
	if not fresh then
		return
	end
	if self.mount:sheathable() and self.sheath.place ~= "Hand" then
		return
	end
	for _, handle in handles do
		if (handle.clipId == DRAW_ID or handle.clipId == SHEATHE_ID) and not handle.done then
			return
		end
	end
	for _, handle in handles do
		if handle.fresh and SNAP_IDS[handle.clipId] == true and not handle.handOver then
			mixer:snapIn(handle)
		end
	end
end

-- The turn plant (D-416, TurnPlant): before every step the hips hold the yaw they stood at while
-- the root turns, and come round between a turn clip's two Footsteps on the pivot foot. It holds
-- while the body stands (update sets plantHolds) and no full-body clip but the turn or a standing
-- Land has it; else its lag lets go over locomotion.turnPlant.plantSeconds.
local PLANT_CHANNEL = "turnPlant"
local STAND_CHANNEL = "standHeight" -- D-506
local function stepTurnPlant(self: any, dt: number, handles: { any }?)
	local root: BasePart? = self.character.PrimaryPart
	if root == nil then
		return
	end
	-- As the root will stand on the frame this step's pose shows (D-505, State.yawAhead).
	local yaw = math.deg(math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z)) + (self.yawAhead or 0)
	local last = self.plantYaw
	self.plantYaw = yaw
	local turned = if last ~= nil then (yaw - last + 180) % 360 - 180 else 0
	local turn = self.turnHandle
	local holds = self.plantHolds == true and handles ~= nil
	if holds then
		for _, handle in handles :: { any } do
			if
				handle.layer == "FullBody"
				and not handle.done
				and handle.weight > 0
				and handle ~= turn
				and handle ~= self.landHandle
			then
				holds = false
				break
			end
		end
	end
	local clip: Types.ClipDef? = nil
	local from, to = 0, 0
	if turn ~= nil and not turn.done and not turn.stopping then
		local mixer = self.animator.mixer
		clip = turn.clip
		from = turn.time
		to = from
		if mixer:pauseRemaining() <= ChoreoData.pauseEpsilon then
			to = math.min(from + dt * mixer:timeScale() * turn.speed, turn.clip.duration)
		end
	end
	TurnPlant.step(self.turnPlant, dt, turned, holds, clip, from, to)
	-- D-507: the Waist and Neck yaw the pose gave last step without this channel.
	local stanceWaist: number?, stanceNeck: number? = nil, nil
	local last = self.animator.mixer:lastOffsets()
	local waist = if last ~= nil then last.Waist else nil
	if waist ~= nil and waist.rot ~= nil then
		stanceWaist = (waist.rot[2] or 0) - self.plantWaist
	end
	local neck = if last ~= nil then last.Neck else nil
	if neck ~= nil and neck.rot ~= nil then
		stanceNeck = neck.rot[2] or 0
	end
	-- The turn clip's own look at the clock it steps to: it can come in faster than last step's
	-- pose shows, so the head is held to the larger of the two.
	if clip ~= nil then
		local clipNeck = ClipSampler.sample(clip, to).Neck
		if clipNeck ~= nil and clipNeck.rot ~= nil then
			local look = clipNeck.rot[2] or 0
			if stanceNeck == nil or math.abs(look) > math.abs(stanceNeck :: number) then
				stanceNeck = look
			end
		end
	end
	local offsets = TurnPlant.offsets(self.turnPlant, stanceWaist, stanceNeck)
	self.plantWaist = if offsets ~= nil then offsets.Waist.rot[2] else 0
	self.animator:setProcedural(PLANT_CHANNEL, offsets)
end

-- The turn in place for the stance the body stands in (D-416): over the drawn idle the drawn
-- turn (its feet start and end where the drawn stance has them), else the sheathed one.
local function turnClipName(self: any, name: string): string
	local drawnIdle = self.handles[LocomotionState.clipFor("Idle", true)]
	local idle = self.handles.Idle
	local drawnName = name .. "Drawn"
	if
		drawnIdle ~= nil
		and idle ~= nil
		and drawnIdle.weight > idle.weight
		and (Config.clips :: any)[drawnName] ~= nil
	then
		return drawnName
	end
	return name
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

-- The joints a clip that takes the body leaves a live sheath clip (D-579, D-580): the Draw's and
-- Sheathe's arm joints and the sword's own, each given a blend in that never starts
-- (Mixer.handOff, math.huge).
local leftJoints: { [string]: number }? = nil
local function sheathLeftJoints(): { [string]: number }
	local joints = leftJoints
	if joints == nil then
		local found: { [string]: number } = { [WeaponModels.motorName] = math.huge }
		for name in sheathArmJoints() do
			found[name] = math.huge
		end
		leftJoints = found
		joints = found
	end
	return joints :: { [string]: number }
end

-- A Skid or a dodge that starts while a Draw or Sheathe is under way leaves that clip the arm and
-- the sword's joint: its own keys there never blend in, so it hides nothing from the hilt, and the
-- sheath clip's clock stands under it (stepSkidBrake): through a Skid's brake (D-579), through a
-- dodge until it is gone (`whole`, D-580). The clip's other joints keep the blends they had (a
-- dodge's own, D-528). Taken over by the Skid, the arm crossed from the Sheathe's swing to the
-- Skid's flung-back arm in 0.1 s; taken over by the dodge, the clip's swing showed through the
-- dodge's 0.18 s arm blend (stopped, its own 0.1 s fade crossed it).
local function leaveSheathArm(self: any, handle: any, whole: boolean?)
	if handle == nil or not self.mount:sheathable() then
		return
	end
	local mixer = self.animator.mixer
	if typeof(mixer) ~= "table" or typeof(mixer.handles) ~= "function" then
		return
	end
	for _, other in mixer:handles() do
		if (other.clipId == DRAW_ID or other.clipId == SHEATHE_ID) and not other.stopping and not other.done then
			local blends = sheathLeftJoints()
			local own = handle.jointBlendIn
			if own ~= nil then
				blends = table.clone(own)
				for name, seconds in sheathLeftJoints() do
					blends[name] = seconds
				end
			end
			mixer:handOff(handle, blends)
			self.armLeft[handle] = true
			self.armTaker = handle
			self.armTakerWhole = whole == true
			return
		end
	end
end

-- A dodge's first step (D-580): it leaves a Draw or Sheathe under way the arm until it is gone
-- (leaveSheathArm). A dodge from the drawn run with the DevAim draw's clip still on turned the
-- right forearm up to 88 degrees a 60 Hz row after the press (the owner's PC 31.6 on 209875b).
-- Runs after the dodge's own hand-off and before the brake.
local function dodgeLeavesSheath(self: any, handles: { any })
	for _, handle in handles do
		local clip = handle.clip
		if
			handle.fresh
			and not handle.stopping
			and not handle.done
			and typeof(clip) == "table"
			and GaitHandOff.dodges(clip)
		then
			leaveSheathArm(self, handle, true)
		end
	end
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
-- Sheathe clip; and the target.
local function scanClips(self: any, handles: { any }?): SheathState.Input
	local cut, covered, drawing, sheathing = false, false, false, false
	-- firstCut: a sheath.drawFirstClips clip (a guard) cuts; otherCut: anything else does.
	local firstCut, otherCut, drawOver, drawTime = false, false, false, 0
	local sheatheShown = 0
	for _, handle in handles or self.animator.mixer:handles() do
		if handle.done then
			continue
		end
		if handle.stopping then
			-- A clip above the sheath clips still hides the hand while it fades out (D-579): a
			-- Sheathe that started under a Skid's fade-out took the arm from its last pose while the
			-- Skid let go of it (the tip 85 studs a second at 240 Hz).
			if
				handle.clipId ~= DRAW_ID
				and handle.clipId ~= SHEATHE_ID
				and handle.weight > 0
				and handle.fade > 0
				and coversArm(handle)
				and not isDrawFirst(handle.clip)
				and not self.armLeft[handle]
			then
				covered = true
			end
			continue
		end
		if handle.clipId == DRAW_ID then
			drawing = true
			if handle.priority > ChoreoData.priority.Sheath then
				drawOver = true
			end
			drawTime = math.max(drawTime, handle.time)
		elseif handle.clipId == SHEATHE_ID then
			sheathing = true
			sheatheShown = math.max(sheatheShown, handle.fade * handle.weight)
		else
			-- A guard raised sheathed waits for the Draw played over it: it does not hide the hand.
			local first = isDrawFirst(handle.clip)
			if isDrawCut(handle.clip) then
				cut = true
				if first then
					firstCut = true
				else
					otherCut = true
				end
			end
			if handle.weight > 0 and coversArm(handle) and not first and not self.armLeft[handle] then
				covered = true
			end
		end
	end
	-- A standing turn under way covers the arm before its turn clip starts (323(b)): the lock's
	-- draw waits for the turn, and one Draw plays once it is over.
	if self.turnUnderWay == true then
		covered = true
	end
	local input: SheathState.Input = {
		target = self.drawn,
		cut = cut,
		covered = covered,
		drawing = drawing,
		sheathing = sheathing,
		hold = self.dead,
		drawFirst = firstCut and not otherCut,
		drawOver = drawOver,
		drawTime = drawTime,
	}
	self.sheatheShown = sheatheShown
	return input
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
	return scanClips(self)
end

-- The place the target asks for with no clip in between.
local function targetPlace(self: any): WeaponMount.Place
	return if self.drawn then "Hand" else "Back"
end

-- The set the base shows: the drawn set while the target is drawn, and on while the sword is
-- still in the hand until a Sheathe has faded in over the whole arm. The sheathed set's hands are
-- empty: its run and sprint pump the sword arm, which swung the held blade up to 2 studs a frame
-- through the sheathe delay, and again under the Sheathe's blend in.
local function showsDrawn(self: any): boolean
	if self.drawn then
		return true
	end
	return self.mount:sheathable() and self.sheath.place == "Hand" and self.sheatheShown < 1
end

-- Plays a sheath clip; a build without the clip moves the sword at once instead. Over the cut
-- clips (SheathState's out.over) it plays at sheath.overPriority and no clip of theirs stops it;
-- from out.from it carries on a Draw the arm already showed, so it takes the arm at once.
local function playSheathClip(self: any, clip: SheathState.Clip, over: boolean?, from: number?)
	local id = sheathClipId(clip)
	if ClipLibrary.has(id) then
		local opts: { [string]: any }? = nil
		if over then
			local carried = from ~= nil and from > 0
			opts = {
				priority = Sheath.overPriority,
				coexist = true,
				startTime = from,
				blendIn = if carried then 0 else nil,
			}
		end
		self.animator:play(id, opts)
	else
		self.sheath.place = if clip == "Draw" then "Hand" else "Back"
	end
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

-- How much of the Draw and Sheathe clips (stopping ones included) the limbs show once this step has
-- moved their envelopes, read before the mixer runs it, by the mixer's own rule (Mixer.preview).
local function sheathShownAfter(self: any, dt: number): number
	local mixer = self.animator.mixer
	local shown = 0
	for _, handle in mixer:handles() do
		if handle.clipId == DRAW_ID or handle.clipId == SHEATHE_ID then
			shown = math.max(shown, mixer:preview(handle, dt))
		end
	end
	return shown
end

-- The base clips the stop brake reads (sheath.stopBrakeClips, sheathed and drawn), each with its
-- step of the gait over the walk.
local STOP_BRAKE_NAMES: { string } = {}
local STOP_BRAKE_STEPS: { number } = {}
for name, steps in Sheath.stopBrakeClips do
	table.insert(STOP_BRAKE_NAMES, name)
	table.insert(STOP_BRAKE_STEPS, steps)
	local drawn = LocomotionState.clipFor(name, true)
	if drawn ~= name then
		table.insert(STOP_BRAKE_NAMES, drawn)
		table.insert(STOP_BRAKE_STEPS, steps)
	end
end

-- Whether the body brakes out of the run or sprint this step (D-611): the base's gait, each of
-- sheath.stopBrakeClips by its shown weight times its step, falls faster than
-- sheath.stopBrakeRate steps a second over the step the mixer is about to run (shown now against
-- Mixer.preview, so the rate is the same at any frame rate). A run let go at 16 crosses to the
-- idle at the mixer's weightBlendRate (8 a second); a slow-down eased under the rate never brakes.
local function stopBraking(self: any, dt: number): boolean
	if dt <= 0 then
		return false
	end
	local mixer = self.animator.mixer
	local fall = 0
	for index, name in STOP_BRAKE_NAMES do
		local handle = self.handles[name]
		if handle ~= nil and not handle.done then
			local shown = Easing.evaluate(ChoreoData.blendEasing, handle.fade) * handle.weight
			fall += (shown - mixer:preview(handle, dt)) * STOP_BRAKE_STEPS[index]
		end
	end
	return fall > Sheath.stopBrakeRate * dt
end

-- The sheath clips' stand under the clip that left them the arm (leaveSheathArm): while a Skid is
-- in its first sheath.skidBrakeSeconds (its brake, D-579), or a dodge has not gone yet (D-580,
-- its fade in standing too), every live sheath clip's clock stands (Mixer.hold); and so it does
-- while the body brakes out of the run or sprint with no Skid (stopBraking, D-611: the stop's
-- blend straightened the torso under the Sheathe's raised arm while the clip swung it on, the
-- tip up to 94.5 studs a second from the run eased off over 0.25 s, 92.9 from a sprint eased off
-- over 0.1 s and 87.5 from the run let go at 16, against the 84 cap;
-- tests/choreo/SheathStop.spec.luau). After it, the clocks this stood run on. A sheath clip that
-- was stopped meanwhile keeps the hold (a cut back holds its own). Runs before the mixer steps.
local function stepSkidBrake(self: any, dt: number, handles: { any }?)
	local taker = self.armTaker
	local taken = taker ~= nil
		and not taker.done
		and (self.armTakerWhole or (not taker.stopping and taker.time < Sheath.skidBrakeSeconds))
	if not taken then
		self.armTaker = nil
	end
	local mixer = self.animator.mixer
	local sheathing = handles ~= nil and (mixer:isPlaying(DRAW_ID) or mixer:isPlaying(SHEATHE_ID))
	if handles ~= nil and (taken or (sheathing and stopBraking(self, dt))) then
		-- A dodge's hold stands the fade in too; a Skid's and a stop's leave it.
		local whole = taken and self.armTakerWhole
		for _, handle in handles do
			if
				(handle.clipId == DRAW_ID or handle.clipId == SHEATHE_ID)
				and not handle.stopping
				and not handle.done
			then
				local ours = table.find(self.brakeHeld, handle) ~= nil
				if ours or not handle.held then
					mixer:hold(handle, true, whole)
					if not ours then
						table.insert(self.brakeHeld, handle)
					end
				end
			end
		end
		return
	end
	self.armTaker = nil
	for _, handle in self.brakeHeld do
		if not handle.stopping and not handle.done then
			mixer:hold(handle, false)
		end
	end
	table.clear(self.brakeHeld)
end

-- The sheath step: runs before the mixer, and the sword's move shows with the pose this step
-- writes (WeaponMount's set with the pose, D-555). The mount's own step hook runs right after
-- this one and keeps the sword where it is shown.
local function stepSheath(self: any, dt: number, handles: { any }?)
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
	local input = scanClips(self, handles)
	local out = self.sheath:step(dt, input)
	if out.stop ~= nil then
		local id = sheathClipId(out.stop)
		self.animator:stop(id, out.blend or Sheath.stopBlend)
		if out.blend ~= nil then
			-- A cut back fades out from where it was: played on, Sheathe's keys line the blade up
			-- with the back mount (and Draw's with the hand) while the sword stays where it is.
			local mixer = self.animator.mixer
			for _, handle in mixer:handles() do
				if handle.clipId == id and handle.stopping and not handle.done then
					mixer:hold(handle)
				end
			end
		end
	end
	if out.play ~= nil then
		playSheathClip(self, out.play, out.over, out.from)
	end
	if mount:get() ~= self.sheath.place then
		mount:set(self.sheath.place, true)
	end
	-- The drawn sprint pose gives way to the clips by what they show after this step, with this
	-- step's play or stop in it: a long frame moves a fade a long way in one step, and a pose that
	-- read it a step behind took that share off over the next, normal frame (1.96 studs in one
	-- 60 Hz frame after a 100 ms one at the sprint). Only read while SprintDrawn shows.
	local sprint = self.handles.SprintDrawn
	if sprint ~= nil and sprint.weight > 0 then
		self.sheathClipWeight = sheathShownAfter(self, dt)
	end
	self.animator:setProcedural(
		"drawnSprint",
		DRAWN_SPRINT,
		drawnSprintWeight(self) * ChoreoData.additiveWeights.drawnSprint
	)
end

-- A WeaponDraw or WeaponSheathe event from the live clip moves the sword mid-clip, when it still
-- fits the target, with the pose of the step that fired it (D-555).
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
		self.mount:set(place, true)
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
	-- A hit-stop holds the phase, and so does an attack taking the body (D-404).
	local running = mixer:pauseRemaining() <= ChoreoData.pauseEpsilon and self.gaitHeldBy == nil
	self.gaitShown = gaitShown
	if gaitShown > 0 then
		natural /= gaitShown
		stride = math.max(stride / baseShown, Stride.minGroundSpeed * natural)
		-- The clips run on the mixer's scaled clock (dev slow motion), the root on real time.
		local speed = if scale > 0 then self.speed / scale else self.speed
		local rate = math.clamp(speed * natural / stride, Stride.rateFloor, Stride.rateCeiling)
		-- A dodge holding the gait holds its pace too (D-528): the root's dodge speed and way are
		-- no stride's, and a pace turned to them moved the held legs a row.
		local holder = self.gaitHeldBy
		if not (holder ~= nil and typeof(holder.clip) == "table" and GaitHandOff.dodges(holder.clip)) then
			pace = math.clamp(rate / natural, minPace, maxPace)
		end
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
			-- The root's travel this frame past (or short of) its speed's (stepTravel, D-334): the
			-- planted foot moves back by what the root moved on, so it holds the ground on a frame
			-- the physics stepped long or short.
			local advance = dt * scale * pace + (moved / baseShown + self.travelExtra) / stride
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
	-- This frame's travel is taken (or dropped: standing, or held in a hit-stop).
	self.travelExtra = 0
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
		standDepth = nil :: number?, -- D-506: the bind pose's soles below the root's center (standDepth)
		standKey = nil :: Vector3?, -- the sizes standDepth was measured on
		mount = nil :: any,
		sheath = nil :: any,
		mountGeneration = 0,
		sheathClipWeight = 0, -- the Draw and Sheathe clips' share after the last step SprintDrawn showed
		sheatheShown = 0, -- how much of a live Sheathe clip the limbs showed last step (showsDrawn)
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
		gaitShown = 0, -- the gait clips' shown share at the last step
		gaitHeldBy = nil :: any, -- the attack the gait's phase stands for (D-404)
		-- The root's own travel (stepTravel, D-334): where the root stood at the last update, how
		-- far its travel along the move has run ahead of its speed's (studs, within
		-- stride.travelSlipSeconds of travel at the speed), and this frame's part of that.
		travelFrom = nil :: Vector3?,
		travelSlip = 0,
		travelExtra = 0,
		shownNow = {} :: { [string]: number }, -- each Base clip's shown weight at this step's start
		shownLast = {} :: { [string]: number }, -- and at the last step's
		-- The body is held off its stick (stride.blocked, D-144): the gait follows the velocity.
		blocked = false,
		stickX = 0, -- the last update's stick: a unit world direction, or zero
		stickZ = 0,
		steadyX = 0, -- where the stick settled (a unit world direction, or zero)
		steadyZ = 0,
		stickSteady = 0, -- seconds the stick has stayed within stride.blocked.degrees of it
		followX = 0, -- blocked: the velocity the gait follows (at 1x, smoothed)
		followZ = 0,
		unreadableRoot = nil :: Instance?, -- a root whose velocity cannot be read (a Lune test part)
		-- An attack clip let go before its first damage frame fades out where it stood (D-294);
		-- false on a rig Locomotion.attach drives.
		holdsCutAttacks = true,
		-- The turn plant (D-416): the hips' lag, the root's yaw at the last step, and whether the
		-- body stands for it (set by update).
		turnPlant = TurnPlant.new(),
		plantYaw = nil :: number?,
		yawAhead = 0, -- D-505: the last update's State.yawAhead
		plantWaist = 0, -- D-507: the Waist yaw the turn plant added last step
		plantHolds = false,
		turnUnderWay = false, -- LocomotionState's last word on a standing turn (323(b))
		-- D-579: the Skid that left a live Draw or Sheathe the arm, the sheath clips its brake
		-- stood, and the handles whose arm keys never show (they hide nothing from the hilt).
		armTaker = nil :: any,
		armTakerWhole = false,
		brakeHeld = {} :: { any },
		armLeft = setmetatable({}, { __mode = "k" }) :: { [any]: boolean },
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
	self.mount = WeaponMount.new(
		animator,
		character,
		{ atStepPose = dependencies.atStepPose, atStepPoseSolve = dependencies.atStepPoseSolve }
	)
	self.sheath = SheathState.new(targetPlace(self), Sheath)
	self.mountGeneration = self.mount:generation()
	if self.mount:sheathable() then
		self.mount:set(self.sheath.place)
	end
	self.unhookSheath = animator:onStep(function(dt: number)
		if not self.destroyed then
			-- One copy of the live handles for the step (an animator with no mixer: none).
			local mixer = animator.mixer
			local handles = if typeof(mixer) == "table" and typeof(mixer.handles) == "function"
				then mixer:handles()
				else nil
			if self.holdsCutAttacks and handles ~= nil then
				holdCutAttacks(mixer, handles)
			end
			if handles ~= nil then
				handOffAttacks(self, mixer, handles)
				snapRaises(self, mixer, handles)
			end
			if handles ~= nil then
				dodgeLeavesSheath(self, handles)
			end
			stepSkidBrake(self, dt, handles)
			stepSheath(self, dt, handles)
			stepGait(self, dt)
			stepTurnPlant(self, dt, handles)
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
		LocomotionState.settlePoints(self.travelForward, self.travelRight, showsDrawn(self))
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

-- True while a FullBody clip that outranks the locomotion one-shot `name` holds the body (a
-- dodge, an attack, a stagger): played now, the one-shot would show nothing under it, yet its
-- clip sounds would play (D-472: a sprint cut by a dodge called a Skid whose landing sounded
-- 0.16 s before the dodge's own).
local function actionHoldsBody(self: any, name: string): boolean
	local mixer = self.animator.mixer
	if typeof(mixer) ~= "table" or typeof(mixer.handles) ~= "function" then
		return false
	end
	local id = clipId(name)
	local own = if ClipLibrary.has(id) then ClipLibrary.get(id).priority else nil
	local floor = own or ChoreoData.priority.OneShot
	for _, handle in mixer:handles() do
		if
			handle.layer == "FullBody"
			and handle.priority > floor
			and not handle.done
			and not handle.stopping
			and handle.weight > 0
		then
			return true
		end
	end
	return false
end

-- Drops the jump's handoff to the fall (landed before the jump clip ended, jumped again, or gone).
local function dropJumpHandoff(self: any)
	if self.jumpHandoff ~= nil then
		self.jumpHandoff:Disconnect()
		self.jumpHandoff = nil
	end
end

-- D-506: how far below the root's center this body's soles hang in its bind pose (no clip), from
-- its own parts and joints: the owner's avatar or any other, scaled or not. Measured again when the
-- root's or a foot's size changes (the avatar's scale lands after the character spawns). A body
-- with no feet falls back to the rig table's hipHeight under the root's bottom.
local STAND_FEET = { "LeftFoot", "RightFoot" }
local function standDepth(self: any, root: BasePart): number
	local character: Model = self.character
	local left = character:FindFirstChild("LeftFoot") :: BasePart?
	local right = character:FindFirstChild("RightFoot") :: BasePart?
	if left == nil or right == nil then
		return self.hipHeight + root.Size.Y * 0.5
	end
	local key = Vector3.new(root.Size.Y, left.Size.Y + left.Size.X, right.Size.Y + right.Size.X)
	local cached: number? = self.standDepth
	if cached ~= nil and self.standKey == key then
		return cached
	end
	local ok, solved = pcall(Pose.solve, character, CFrame.new(), {})
	local lowest = math.huge
	local found = 0
	if ok then
		for _, name in STAND_FEET do
			local frame = (solved :: any)[name]
			local part = character:FindFirstChild(name) :: BasePart?
			if frame ~= nil and part ~= nil then
				found += 1
				local size = part.Size
				for _, sx in { -0.5, 0.5 } do
					for _, sz in { -0.5, 0.5 } do
						lowest =
							math.min(lowest, (frame * CFrame.new(sx * size.X, -0.5 * size.Y, sz * size.Z)).Position.Y)
					end
				end
			end
		end
	end
	if found < #STAND_FEET then
		-- A body still being put together: measured again next step.
		return self.hipHeight + root.Size.Y * 0.5
	end
	self.standDepth = -lowest
	self.standKey = key
	return -lowest
end

local function readHipHeight(humanoid: Humanoid): number
	return humanoid.HipHeight
end

-- D-506: how far below the root's center the floor is: the engine holds the root's bottom the
-- Humanoid's own HipHeight over it (not the rig table's), else the body stands on its soles.
local function floorDepth(self: any, root: BasePart): number
	local humanoid = self.humanoid :: Humanoid?
	if humanoid == nil then
		humanoid = self.character:FindFirstChildOfClass("Humanoid")
		self.humanoid = humanoid
	end
	if humanoid ~= nil then
		local ok, hipHeight = pcall(readHipHeight, humanoid)
		if ok and typeof(hipHeight) == "number" and hipHeight > 0 then
			return hipHeight + root.Size.Y * 0.5
		end
	end
	return standDepth(self, root)
end

local function footDeltas(self: any, root: BasePart): (number?, number?)
	local raycast: Raycast = self.raycast
	local ik = Config.footIK
	-- D-506: the IK measures the ground against the floor the Humanoid stands the root over. The
	-- rig table's hipHeight (2.0) is not this avatar's: on the owner-sized body its flat field read
	-- 0.54 high, and the IK lifted both standing feet 0.30 to 0.66 off it.
	local expectedGround = root.Position.Y - floorDepth(self, root)
	local rightVector = root.CFrame.RightVector
	local function probe(side: number): number?
		local base = root.Position + rightVector * (side * ik.footSpacing)
		local origin = Vector3.new(base.X, expectedGround + ik.rayStart, base.Z)
		local hit = raycast(origin, Vector3.new(0, -(ik.rayStart + ik.rayLength), 0))
		return if hit then hit.Y - expectedGround else nil
	end
	return probe(-1), probe(1)
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

local function readVelocity(part: any): Vector3
	return part.AssemblyLinearVelocity
end

-- The root's horizontal velocity (studs a second, real time) when it is the reading the state's
-- speed came from, within stride.blocked.matchSpeed: the state's own, else the root's. Nil when it
-- is unknown or another reading. A part never given a velocity (a Lune test rig) cannot be read;
-- it is tried once. No allocation.
local function trustedVelocity(self: any, root: BasePart, state: State): (number?, number?)
	local velocity = state.velocity
	if velocity == nil then
		if self.unreadableRoot == root then
			return nil, nil
		end
		local ok, value = pcall(readVelocity, root)
		if not ok or typeof(value) ~= "Vector3" then
			self.unreadableRoot = root
			return nil, nil
		end
		velocity = value
	end
	local x, z = (velocity :: Vector3).X, (velocity :: Vector3).Z
	if math.abs(math.sqrt(x * x + z * z) - math.max(0, state.speed)) > Blocked.matchSpeed then
		return nil, nil
	end
	return x, z
end

-- Keeps whether the body is blocked (stride.blocked, D-144) from this update's stick (a unit world
-- direction, or zero; `forward`, `right` in the character's frame) and the root's velocity. While
-- it is blocked it keeps the velocity the gait follows (followX, followZ: at 1x, smoothed over
-- stride.blocked.followSeconds of the root's clock, from zero at the block) and returns the root's
-- velocity (world x and z, real studs a second); nil otherwise. No allocation.
local function stepBlocked(
	self: any,
	root: BasePart,
	state: State,
	dt: number,
	clock: number,
	stickX: number,
	stickZ: number,
	forward: number,
	right: number
): (number?, number?)
	local lastX, lastZ = self.stickX, self.stickZ
	self.stickX, self.stickZ = stickX, stickZ
	if (stickX == 0 and stickZ == 0) or not state.grounded then
		self.blocked = false
		self.steadyX, self.steadyZ, self.stickSteady = 0, 0, 0
		return nil, nil
	end
	-- The stick holds still while it stays within stride.blocked.degrees of where it settled.
	if stickX * self.steadyX + stickZ * self.steadyZ >= BLOCKED_COS then
		self.stickSteady += dt
	else
		self.steadyX, self.steadyZ, self.stickSteady = stickX, stickZ, 0
	end
	local hadStick = lastX ~= 0 or lastZ ~= 0
	local x, z = trustedVelocity(self, root, state)
	if x == nil or z == nil then
		self.blocked = false
		return nil, nil
	end
	local scale = if clock > 0 then clock else 1
	local speed = math.sqrt(x * x + z * z)
	if speed / scale > Config.idleSpeedThreshold then
		local cosine = BLOCKED_COS * speed
		local along = x * stickX + z * stickZ >= cosine or (hadStick and x * lastX + z * lastZ >= cosine)
		if not along then
			if not self.blocked and self.stickSteady >= Blocked.settleSeconds then
				self.blocked = true
				self.followX, self.followZ = 0, 0
			end
		elseif self.blocked and speed / scale >= LocomotionState.wholeWalkSpeed(forward, right, showsDrawn(self)) then
			self.blocked = false
		end
	end
	if not self.blocked then
		return nil, nil
	end
	local blend = math.min(1, dt * scale / Blocked.followSeconds)
	self.followX += (x / scale - self.followX) * blend
	self.followZ += (z / scale - self.followZ) * blend
	return x, z
end

-- Keeps the root's own travel this update against what its speed carries in the frame
-- (stepTravel, D-334). The engine moves the root in whole physics steps, so a rendered frame's
-- travel runs a step long or short while the velocity reads steady; stepGait moves the phase on by
-- this frame's difference so the planted foot moves back exactly as far as the root moved on. On
-- open ground the travel is the length of the root's horizontal move (the speed is the length of
-- its velocity); blocked (D-144) it is the move along the velocity the gait follows (followX,
-- followZ: a unit world direction, or zero while that velocity goes nowhere). The running
-- difference stays within stride.travelSlipSeconds of travel at the speed (a teleport or a shove
-- past it is dropped), forgets itself over stride.travelSlipDecaySeconds (a lasting bias in the
-- root's travel never pins it at the bound, D-411) and starts over standing, in the air, on a
-- stalled frame or held still.
local function stepTravel(self: any, root: BasePart, state: State, dt: number, followX: number?, followZ: number?)
	local position = root.CFrame.Position
	local from = self.travelFrom
	self.travelFrom = position
	local extra = 0
	local speed = self.speed
	if
		from ~= nil
		and dt > 0
		and dt <= ChoreoData.stall.jumpSeconds
		and state.grounded
		and speed > Config.idleSpeedThreshold
		and not (followX == 0 and followZ == 0)
	then
		local moveX, moveZ = position.X - from.X, position.Z - from.Z
		local along = if followX ~= nil and followZ ~= nil
			then moveX * followX + moveZ * followZ
			else math.sqrt(moveX * moveX + moveZ * moveZ)
		local bound = Stride.travelSlipSeconds * speed
		local step = along - speed * dt
		local kept = self.travelSlip * (1 - math.min(1, dt / Stride.travelSlipDecaySeconds))
		if math.abs(kept + step) <= bound then
			-- Inside the bound the frame's step is taken up whole and the memory forgets itself.
			extra = step
			self.travelSlip = kept + step
		else
			-- Past it the overrun is dropped and the memory holds: a lasting one (a stuck or shoved
			-- root) moves the phase no more than it ever did.
			local slip = math.clamp(self.travelSlip + step, -bound, bound)
			extra = slip - self.travelSlip
			self.travelSlip = slip
		end
	else
		self.travelSlip = 0
	end
	self.travelExtra = extra
end

function Locomotion.update(self: any, dt: number, state: State): LocomotionState.Output
	local animator = self.animator
	local root: BasePart? = self.character.PrimaryPart or self.character:FindFirstChild("HumanoidRootPart") :: any
	-- A root slowed with its clips is read at 1x (State.clockScale): a slowed capture's run blends
	-- the run, not the walk its slowed speed would pick. The pace keeps the root's real speed.
	local clock = state.clockScale or 1
	local blendSpeed = if clock > 0 then math.max(0, state.speed) / clock else math.max(0, state.speed)
	local forward, right = 0, 0
	local stickX, stickZ = 0, 0
	local yawRate = 0
	if root ~= nil then
		local cframe = root.CFrame
		local move = Vector3.new(state.moveDir.X, 0, state.moveDir.Z)
		if move.Magnitude > 0 then
			move = move.Unit
			forward = move:Dot(cframe.LookVector)
			right = move:Dot(cframe.RightVector)
			stickX, stickZ = move.X, move.Z
		end
		local yaw = yawOf(cframe) + (state.yawAhead or 0)
		if self.lastYaw ~= nil and dt > 0 and clock > 0 then
			yawRate = wrapDegrees(yaw - self.lastYaw) / dt / clock
		end
		self.lastYaw = yaw
	end
	self.yawAhead = state.yawAhead or 0
	if state.drawn ~= nil then
		self.drawn = state.drawn
	end
	self.speed = math.max(0, state.speed)
	if root ~= nil then
		-- Held off the stick (D-144): the gait follows the root's smoothed velocity and is paced by
		-- the root's speed along it; a jostle that goes nowhere stands, so the feet neither walk in
		-- place nor skate along a flank.
		local x, z = stepBlocked(self, root, state, dt, clock, stickX, stickZ, forward, right)
		-- Blocked, the root's travel is read along the velocity the gait follows (stepTravel).
		local travelX: number?, travelZ: number? = nil, nil
		if x ~= nil and z ~= nil then
			local followX, followZ = self.followX, self.followZ
			local follow = math.sqrt(followX * followX + followZ * followZ)
			travelX, travelZ = 0, 0
			if follow > Config.idleSpeedThreshold then
				followX /= follow
				followZ /= follow
				local cframe = root.CFrame
				local look, side = cframe.LookVector, cframe.RightVector
				forward = followX * look.X + followZ * look.Z
				right = followX * side.X + followZ * side.Z
				self.speed = math.max(0, x * followX + z * followZ)
				blendSpeed = self.speed / (if clock > 0 then clock else 1)
				travelX, travelZ = followX, followZ
			else
				blendSpeed = 0
			end
		end
		stepTravel(self, root, state, dt, travelX, travelZ)
	end
	if forward ~= 0 or right ~= 0 then
		self.travelForward, self.travelRight = forward, right
	elseif blendSpeed > Config.idleSpeedThreshold then
		-- Moving with no stick (a coast, a shove): the blend keeps the last move direction.
		forward, right = self.travelForward, self.travelRight
	end

	-- While a dodge holds the body the gait's weights stand where the dodge found them (D-528;
	-- its pace, stepGait): the root's dodge speed is no run, and a blend that turned to it under
	-- the dodge's fade crossed the legs to another stride in a row. The blend still hears the root
	-- (a stop under the dodge is over when it lets go: no Skid after it, D-472).
	local dodging = typeof(animator.mixer) == "table" and GaitHandOff.dodgeLive(animator.mixer)
	local input: LocomotionState.Input = {
		forward = forward,
		right = right,
		speed = blendSpeed,
		sprinting = state.sprinting,
		grounded = state.grounded,
		drawn = showsDrawn(self),
		turning = state.turning,
		yawRate = yawRate,
		verticalVelocity = state.verticalVelocity or 0,
		fallHeight = state.fallHeight,
	}
	local output = self.state:update(dt, input)
	self.runAlong = LocomotionState.runAlong(input)
	self.turnUnderWay = output.turnUnderWay

	if not dodging then
		for name, weight in output.weights do
			animator:setWeight(self.handles[name], weight)
		end
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
			-- On the move nothing covers the legs (D-521): the Fall hands them to the stride over
			-- locomotion.landOnMoveBlend. Standing, the Land takes them over oneShotBlendIn.
			local moving = output.oneShotWeight <= 0
			animator:stop(self.fallHandle, if moving then Config.landOnMoveBlend else ChoreoData.oneShotBlendIn)
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
		-- A turn steps round what the hips still hold (D-416): the root's yaw the plant has not
		-- taken, or the facing the controller asks for. A turn the last one already took (the
		-- yaw counted on while it played) does not step again.
		local pending = self.turnPlant.lag
		if root ~= nil and self.plantYaw ~= nil then
			pending -= wrapDegrees(yawOf(root.CFrame) - self.plantYaw)
		end
		local half = Config.turnInPlaceDegrees / 2
		if math.abs(pending) > half or math.abs(state.turning) > half then
			self.turnHandle = playOneShot(self, turnClipName(self, oneShot))
		end
	elseif oneShot == "Skid" then
		-- A stop under an action (a sprint cut by a dodge or an attack) is the action's: the Skid
		-- would only sound under it (D-472).
		if not actionHoldsBody(self, oneShot) then
			leaveSheathArm(self, playOneShot(self, oneShot))
		end
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
	-- The turn plant holds the hips while the body stands on the ground (D-416).
	self.plantHolds = output.phase == "Idle" and state.grounded

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
		-- D-506: the body stands on the floor the Humanoid holds the root over, at every speed: a
		-- HipHeight short of this avatar's legs sank every sole into the field (walking too, where
		-- the IK has faded); one past them floated it. Within footIK.maxAdjust.
		local lift = math.clamp(
			standDepth(self, root :: BasePart) - floorDepth(self, root :: BasePart),
			-Config.footIK.maxAdjust,
			Config.footIK.maxAdjust
		)
		if lift ~= 0 then
			animator:setProcedural(STAND_CHANNEL, LocomotionState.standOffsets(lift))
		else
			animator:setProcedural(STAND_CHANNEL, nil)
		end
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
	for _, name in { "lean", "drawnSprint", "footIK", PLANT_CHANNEL, STAND_CHANNEL } do
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
-- The crossfade is the player's own gait rule (LocomotionState.gaitWeights with no Run, D-541):
-- the walk shows alone from stride.rateFloor of the rig's walkSpeed up, paced to the body's speed,
-- and only below that slows to rateFloor and hands weight to Idle. A joint-angle blend of the
-- walk and the idle shortens the planted leg's sweep but not the body's travel, so the old share
-- (speed / walkSpeed) slid a boar wheeling at half speed 0.2 a frame on hooves 0.09 deep.
-- A rig with a start phase (choreo enemy.gait.startPhase, D-599) holds its walk there while the
-- walk shows no weight, so every walk from standing steps off from the same pose.
-- A rig with a walking-turn plant (choreo enemy.gait.turnPlant, D-619, WalkTurnPlant) takes back
-- at each planted foot's hip a share of the sweep the root's turn gives it while the walk shows,
-- and lets every leg go while a full-body clip has the body or the walk shows none.
-- A rig with a stop plant (choreo enemy.gait.stopPlant, D-623, WalkStopPlant) stops its walk's
-- clock when its root brakes under the walk, holds each foot where it stood and steps them into
-- the idle's stand one group at a time while the walk's share falls to 0; a full-body clip or the
-- root setting off again ends it.
RigDriver.__index = RigDriver

-- RigDriver's walking-turn plant channel (D-619) and stop plant channel (D-623).
local WALK_PLANT_CHANNEL = "walkTurnPlant"
local STOP_PLANT_CHANNEL = "walkStopPlant"
local TRAVEL_TIME_SLACK = 1e-9 -- unit: seconds, float noise in a sum of frame times

local function newRigDriver(
	animator: any,
	idleId: string,
	walkId: string,
	walkSpeed: number,
	phase: number,
	startPhase: number?,
	character: Model?,
	plantConfig: WalkTurnPlant.Config?,
	stopConfig: WalkStopPlant.Config?
): any
	local walkDuration = ClipLibrary.get(walkId).duration
	local plan = if character ~= nil and plantConfig ~= nil
		then WalkTurnPlant.plan(character, ClipLibrary.get(walkId), plantConfig)
		else nil
	local stopPlan = if character ~= nil and stopConfig ~= nil
		then WalkStopPlant.plan(character, ClipLibrary.get(walkId).rig, stopConfig)
		else nil
	local self = setmetatable({
		animator = animator,
		handles = {} :: { [string]: any },
		walkSpeed = math.max(walkSpeed, Config.idleSpeedThreshold),
		walkDuration = walkDuration,
		-- Where the walk steps off from standing (choreo enemy.gait.startPhase, D-599), or nil.
		walkStartAt = if startPhase ~= nil then startPhase * walkDuration else nil,
		-- The walking-turn plant (D-619), the root it last read and that step's turn, or nil.
		character = character,
		walkPlant = if plan ~= nil then WalkTurnPlant.new(plan) else nil,
		plantYaw = nil :: CFrame?,
		plantAt = nil :: Vector3?,
		plantClock = 0,
		plantHeading = 0,
		plantTimes = {} :: { number },
		plantHeadings = {} :: { number },
		-- The stop plant (D-623), the root it last read and its flat move then, whether the walk
		-- has shown whole since it last stood (a stop under it is planted), whether the root walked
		-- off from the stop and what is left of its legs then, and whether a stop drew its last step.
		walkStop = if stopPlan ~= nil then WalkStopPlant.new(stopPlan) else nil,
		stopAt = nil :: Vector3?,
		stopMoved = 0,
		walked = false,
		stopFade = 1,
		stopLetGo = false,
		stopEnds = false,
		unhook = nil :: (() -> ())?,
		destroyed = false,
	}, RigDriver)
	local idleStart = phase * ClipLibrary.get(idleId).duration
	local walkStart = self.walkStartAt or phase * walkDuration
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

-- The walking-turn plant's step (D-619): the turn the root will make over the row this step's pose
-- is drawn on, each planted foot's hip taking back its share, while the walk shows and no
-- full-body clip has the body. The turn is read as the root's turning speed over the gait's own
-- travel window (enemy.gait.travelSeconds) times this step's dt: the root a client draws turns
-- unevenly row to row (511(g): -0.15 to -1.28 degrees a 144 Hz row on a steady wheel), and a
-- take-back of the last row's own turn would put that row-to-row difference on the planted sole.
local function stepWalkPlant(self: any, dt: number)
	local plant = self.walkPlant
	local root: BasePart? = if self.character ~= nil then self.character.PrimaryPart else nil
	if plant == nil or root == nil then
		return
	end
	local gait = ChoreoData.enemy.gait
	local rotation = root.CFrame.Rotation
	local at = root.CFrame.Position
	local last: CFrame? = self.plantYaw
	local lastAt: Vector3? = self.plantAt
	self.plantYaw = rotation
	self.plantAt = at
	local times: { number } = self.plantTimes
	local headings: { number } = self.plantHeadings
	if
		last == nil
		or lastAt == nil
		or Vector3.new(at.X - lastAt.X, 0, at.Z - lastAt.Z).Magnitude > ChoreoData.enemy.rush.teleportStuds
	then
		-- A placement: the turn starts afresh from here.
		table.clear(times)
		table.clear(headings)
	else
		local look = (last:Inverse() * rotation).LookVector
		self.plantHeading += math.atan2(-look.X, -look.Z)
	end
	if dt > 0 or #times == 0 then
		self.plantClock += math.max(dt, 0)
		table.insert(times, self.plantClock)
		table.insert(headings, self.plantHeading)
	else
		headings[#headings] = self.plantHeading
	end
	local from = self.plantClock - gait.travelSeconds + TRAVEL_TIME_SLACK
	while #times > 2 and times[2] <= from do
		table.remove(times, 1)
		table.remove(headings, 1)
	end
	local span = self.plantClock - times[1]
	local ahead = if span > 0 then (self.plantHeading - headings[1]) / span * dt else 0
	local walkHandle = self.handles.Walk
	local mixer = self.animator.mixer
	local weight = if walkHandle ~= nil and not walkHandle.done then walkHandle.targetWeight or walkHandle.weight else 0
	if weight > 0 then
		for _, handle in mixer:handles() do
			if handle.layer == "FullBody" and not handle.done and handle.weight > 0 then
				weight = 0
				break
			end
		end
	end
	if weight <= 0 then
		WalkTurnPlant.reset(plant)
		self.animator:setProcedural(WALK_PLANT_CHANNEL, nil)
		return
	end
	local rate = walkHandle.speed or 1
	local time = walkHandle.time
	if mixer:pauseRemaining() <= ChoreoData.pauseEpsilon then
		time += dt * mixer:timeScale() * rate
	end
	local offsets = WalkTurnPlant.step(plant, dt, ahead, time, rate)
	self.animator:setProcedural(WALK_PLANT_CHANNEL, offsets, weight)
end

-- True while a full-body clip shows on `mixer`: it has the body, and the plants let it go.
local function fullBodyShows(mixer: any): boolean
	for _, handle in mixer:handles() do
		if handle.layer == "FullBody" and not handle.done and handle.weight > 0 then
			return true
		end
	end
	return false
end

-- A loop handle's clock once the next step of `dt` has run (the mixer's own advance, wrapped).
local function timeAfter(mixer: any, handle: any, dt: number): number
	local time = handle.time
	if mixer:pauseRemaining() <= ChoreoData.pauseEpsilon and not handle.held then
		time += dt * mixer:timeScale() * (handle.speed or 1)
	end
	local duration = handle.clip.duration
	return if duration > 0 then time % duration else time
end

-- The base layer's pose on a stop's step: the walk and the idle by their shown weights, as the
-- mixer mixes one priority group (normalised by their sum; a joint one clip leaves out counts as
-- rest there).
local function stopBase(
	walkPose: ClipSampler.Offsets,
	walk: number,
	idlePose: ClipSampler.Offsets,
	idle: number
): ClipSampler.Offsets
	local base: ClipSampler.Offsets = {}
	local total = walk + idle
	if total <= 0 then
		return base
	end
	for _, entry in { { walkPose, walk / total }, { idlePose, idle / total } } do
		local pose: ClipSampler.Offsets, weight: number = entry[1] :: any, entry[2] :: any
		for name, offset in pose do
			local into = base[name]
			if into == nil then
				into = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }
				base[name] = into
			end
			for axis = 1, 3 do
				into.pos[axis] += offset.pos[axis] * weight
				into.rot[axis] += offset.rot[axis] * weight
			end
		end
	end
	return base
end

-- Ends a stop: the walk's clock runs again and the stop's channel goes.
local function endWalkStop(self: any)
	WalkStopPlant.cancel(self.walkStop)
	self.animator.mixer:hold(self.handles.Walk, false)
	self.animator:setProcedural(STOP_PLANT_CHANNEL, nil)
	self.stopFade = 1
	self.stopLetGo = false
end

-- The stop plant's step (D-623). The root a step reads is where it was drawn on the last row: a
-- root that moved under stopBrakeShare of the walk's own pace there has braked, and from this row
-- the walk's clock stands and the legs are the stop plant's ("drive": RigDriver.update leaves the
-- gait alone). A full-body clip ends it at once (it has the body). The root moving off again (more
-- than twice its last row's move and more than locomotion.idleSpeedThreshold) hands the rig back to
-- the gait ("letGo"): the stop's legs fade out over the gait's weightBlendRate, so a foot caught
-- mid-step never jumps back onto the walk.
local function stepWalkStop(self: any, dt: number): string?
	local stop = self.walkStop
	local root: BasePart? = if self.character ~= nil then self.character.PrimaryPart else nil
	if stop == nil or root == nil then
		return nil
	end
	local at = root.CFrame.Position
	local last: Vector3? = self.stopAt
	local lastMoved: number = self.stopMoved
	local moved = if last ~= nil then Vector3.new(at.X - last.X, 0, at.Z - last.Z).Magnitude else 0
	self.stopAt = at
	self.stopMoved = moved
	local walkHandle = self.handles.Walk
	local idleHandle = self.handles.Idle
	local mixer = self.animator.mixer
	local full = fullBodyShows(mixer)
	if stop.active then
		if full or self.stopFade <= 0 then
			endWalkStop(self)
			return nil
		end
		if self.stopLetGo then
			return "letGo"
		end
		if moved > math.max(2 * lastMoved, Config.idleSpeedThreshold * dt) then
			mixer:hold(walkHandle, false)
			self.stopLetGo = true
			return "letGo"
		end
	else
		if walkHandle.weight >= 1 - 1e-6 then
			self.walked = true
		elseif walkHandle.weight <= 0 then
			self.walked = false
		end
		local pace = (walkHandle.speed or 0) * self.walkSpeed * dt
		if not self.walked or full or last == nil or moved >= ChoreoData.enemy.gait.stopBrakeShare * pace then
			return nil
		end
		-- The root braked: hold each foot where the last row drew it, the walk's clock where it is.
		WalkStopPlant.begin(
			stop,
			mixer:lastOffsets(),
			ClipSampler.sample(idleHandle.clip, timeAfter(mixer, idleHandle, dt))
		)
		mixer:hold(walkHandle, true)
		self.walked = false
		if self.walkPlant ~= nil then
			-- What the turning plant held is in the pose the stop holds.
			WalkTurnPlant.reset(self.walkPlant)
			self.animator:setProcedural(WALK_PLANT_CHANNEL, nil)
		end
	end
	-- The stop keeps the rig's clock: a hit-stop holds it, a time scale paces it.
	local clockDt = if mixer:pauseRemaining() <= ChoreoData.pauseEpsilon then dt * mixer:timeScale() else 0
	local walk = WalkStopPlant.walkWeight(stop, clockDt)
	self.animator:setWeight(walkHandle, walk, true)
	self.animator:setWeight(idleHandle, 1 - walk, true)
	local idlePose = ClipSampler.sample(idleHandle.clip, timeAfter(mixer, idleHandle, dt))
	local base = stopBase(ClipSampler.sample(walkHandle.clip, walkHandle.time), walk, idlePose, 1 - walk)
	self.animator:setProcedural(STOP_PLANT_CHANNEL, WalkStopPlant.step(stop, clockDt, base, idlePose), 1)
	if WalkStopPlant.done(stop) then
		-- Its last foot is down on the idle's spot and the walk shows none: the idle has the rig.
		WalkStopPlant.cancel(stop)
		self.stopEnds = true
	end
	return "drive"
end

-- A stop the root walked off from, over the gait's own step: its legs as the stop has them, laid
-- over the base the gait set up for this step by what is left of the let-go.
local function letGoWalkStop(self: any, dt: number)
	local stop = self.walkStop
	local mixer = self.animator.mixer
	local walkHandle = self.handles.Walk
	local idleHandle = self.handles.Idle
	local idlePose = ClipSampler.sample(idleHandle.clip, timeAfter(mixer, idleHandle, dt))
	local walkPose = ClipSampler.sample(walkHandle.clip, timeAfter(mixer, walkHandle, dt))
	local base = stopBase(walkPose, mixer:preview(walkHandle, dt), idlePose, mixer:preview(idleHandle, dt))
	local clockDt = if mixer:pauseRemaining() <= ChoreoData.pauseEpsilon then dt * mixer:timeScale() else 0
	self.stopFade = math.max(0, self.stopFade - clockDt * ChoreoData.locomotion.weightBlendRate)
	self.animator:setProcedural(STOP_PLANT_CHANNEL, WalkStopPlant.step(stop, clockDt, base, idlePose), self.stopFade)
end

function RigDriver.update(self: any, dt: number, state: State): LocomotionState.Output
	if self.stopEnds then
		-- The stop's last step drew every leg on the idle: its channel goes.
		self.stopEnds = false
		endWalkStop(self)
	end
	local stopping = stepWalkStop(self, dt)
	if stopping == "drive" then
		local shown = self.handles.Walk.weight
		return {
			weights = { Idle = 1 - shown, Walk = shown },
			oneShot = nil,
			oneShotWeight = 1,
			lean = 0,
			drawnSprint = 0,
			phase = "Idle",
			airborne = not state.grounded,
		}
	end
	local speed = math.max(0, state.speed)
	local walk = 0
	if speed > Config.idleSpeedThreshold then
		walk = LocomotionState.gaitWeights(speed, self.walkSpeed, self.walkDuration)
	end
	local walkHandle = self.handles.Walk
	local startAt: number? = self.walkStartAt
	if startAt ~= nil and walkHandle.weight <= 0 and (walkHandle.targetWeight or 0) <= 0 then
		-- Standing, no walk shown or on its way in: every start steps off from the same point of
		-- the walk's cycle, where its planted foot stands nearest the idle's (D-599).
		walkHandle.time = startAt
	end
	self.animator:setWeight(walkHandle, walk)
	self.animator:setWeight(self.handles.Idle, 1 - walk)
	if walk > 0 then
		self.animator:setSpeed(self.handles.Walk, math.max(speed / self.walkSpeed, Stride.rateFloor))
	end
	stepWalkPlant(self, dt)
	if stopping == "letGo" then
		letGoWalkStop(self, dt)
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
	if self.walkPlant ~= nil then
		self.animator:setProcedural(WALK_PLANT_CHANNEL, nil)
	end
	if self.walkStop ~= nil then
		self.animator:setProcedural(STOP_PLANT_CHANNEL, nil)
	end
end

--- Drives a rig the local controller does not own from the animator's own step. The state comes
--- from deps.tracker (default Locomotion.humanoidTracker(character); an enemy rig's paced by its
--- root's own travel, Locomotion.travelTracker); a frame with no state (the Humanoid or root is
--- gone) is skipped. A player rig runs the full blend space; an enemy rig its
--- data Idle / Walk pair. Destroy it when the rig leaves (the animator's own destroy drops the hook).
function Locomotion.attach(animator: any, character: Model, deps: Dependencies?): Locomotion
	local dependencies: Dependencies = deps or {}
	local tracker = dependencies.tracker
	local rigId: string = animator.rigId
	local driver: any
	if rigId == "PlayerR15" then
		driver = Locomotion.new(animator, character, dependencies)
		-- A remote Art taken away runs its clock through its fade: Replication puts its activation
		-- light out on the HitWindowOpen the fade crosses (D-231), and nothing else would.
		driver.holdsCutAttacks = false
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
			dependencies.phase or 0,
			ChoreoData.enemy.gait.startPhase[rigId],
			character,
			ChoreoData.enemy.gait.turnPlant[rigId],
			ChoreoData.enemy.gait.stopPlant[rigId]
		)
		if tracker == nil then
			tracker = Locomotion.travelTracker(character, Locomotion.humanoidTracker(character))
		end
	end
	local source: (dt: number) -> State? = tracker or Locomotion.humanoidTracker(character)
	local follow = Locomotion.drawnTracker(animator, character)
	driver.unhook = animator:onStep(function(dt: number)
		if driver.destroyed then
			return
		end
		local state = source(dt)
		if state ~= nil then
			driver:update(dt, follow(dt, state))
		end
	end)
	return (driver :: any) :: Locomotion
end

--- The gait of a body drawn away from its root part (a rush, D-171): while the animator draws an
--- offset (Choreo getBodyOffset), `state`'s speed, velocity, move direction and sprint are the drawn
--- body's own over the frame, so the legs stop when it stops and run when it runs, whatever the
--- late root does. Otherwise `state` is handed back untouched. Read after the hook that sets the
--- offset (Choreo runs the newest hook first, and a rush's hook is armed after the rig is watched).
function Locomotion.drawnTracker(animator: any, character: Model): (dt: number, state: State) -> State
	local last: Vector3? = nil
	return function(dt: number, state: State): State
		local root = character.PrimaryPart
		if root == nil then
			last = nil
			return state
		end
		local get = animator.getBodyOffset
		local offset: CFrame? = if typeof(get) == "function" then get(animator) else nil
		local drawn = (if offset ~= nil then root.CFrame * offset else root.CFrame).Position
		local previous = last
		last = drawn
		if offset == nil or previous == nil or not (dt > 0) then
			return state
		end
		local moved = Vector3.new(drawn.X - previous.X, 0, drawn.Z - previous.Z) / dt
		local speed = moved.Magnitude
		local followed = table.clone(state)
		followed.speed = speed
		followed.velocity = Vector3.new(moved.X, if state.velocity ~= nil then state.velocity.Y else 0, moved.Z)
		followed.moveDir = if speed > Config.idleSpeedThreshold then moved.Unit else Vector3.zero
		followed.sprinting = speed > (Config.runSpeed + Config.sprintSpeed) / 2
		return followed
	end
end

--- An enemy rig's gait paced by its root's own travel (D-575): `source`'s state with its flat
--- speed, velocity and move direction those of the root's flat travel over the last
--- choreo.enemy.gait.travelSeconds of frames (all of it until that much has gone by). The
--- replicated velocity the default tracker reads under-reads the root's move (AH 401(c)), and a
--- walk paced short of the root slides its planted feet by the gap each frame. A step longer than
--- choreo.enemy.rush.teleportStuds is a placement: the travel starts afresh there, and until a
--- frame has gone by `source`'s own reading stands. A frame with no time leaves the travel as it was.
function Locomotion.travelTracker(character: Model, source: (dt: number) -> State?): (dt: number) -> State?
	local times: { number } = {}
	local points: { Vector3 } = {}
	local clock = 0
	return function(dt: number): State?
		local state = source(dt)
		local root = character.PrimaryPart
		if state == nil or root == nil then
			table.clear(times)
			table.clear(points)
			return state
		end
		local gait = ChoreoData.enemy.gait
		local at = root.CFrame.Position
		local count = #points
		local last = points[count]
		if
			last ~= nil
			and Vector3.new(at.X - last.X, 0, at.Z - last.Z).Magnitude > ChoreoData.enemy.rush.teleportStuds
		then
			table.clear(times)
			table.clear(points)
			count = 0
		end
		if dt > 0 or count == 0 then
			clock += math.max(dt, 0)
			table.insert(times, clock)
			table.insert(points, at)
		else
			points[count] = at
		end
		-- The oldest sample kept is the newest at or before the window's start (a sum of the same
		-- frames' seconds may land a hair either side of it).
		local from = clock - gait.travelSeconds + TRAVEL_TIME_SLACK
		while #times > 2 and times[2] <= from do
			table.remove(times, 1)
			table.remove(points, 1)
		end
		local span = clock - times[1]
		if not (span > 0) then
			return state
		end
		local first = points[1]
		local moved = Vector3.new(at.X - first.X, 0, at.Z - first.Z) / span
		local speed = moved.Magnitude
		local travelled = table.clone(state)
		travelled.speed = speed
		travelled.velocity = Vector3.new(moved.X, if state.velocity ~= nil then state.velocity.Y else 0, moved.Z)
		travelled.moveDir = if speed > Config.idleSpeedThreshold then moved.Unit else Vector3.zero
		travelled.sprinting = speed > (Config.runSpeed + Config.sprintSpeed) / 2
		return travelled
	end
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
			velocity = velocity,
		}
	end
end

return Locomotion
