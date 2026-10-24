--!strict
--[[
	CharacterController: the local fighter (sections 6, 10, 17). Owns the Choreo animator and the
	Locomotion blend space for the local character, feeds locomotion its state every frame, applies
	the clip's root motion to the HumanoidRootPart, locks Humanoid movement while an Art, dodge,
	stagger or post-motion holds the body, and predicts every action the instant the key is
	pressed: the clip plays now and the request goes to the server; a rejection cancels the clip
	and nothing else. The server owns HP and hits; this file never decides damage.

	The Art key: press enters the start pose (the Art clip starts and freezes at its activation
	hold, glowing); release launches it (the request goes out and the clip resumes in step with
	the server's copy, see ActionLogic.syncPlan); holding past the cancel time lets go of it.

	The hold across a render stall (D-138): RenderStepped stops while the display sleeps and
	Heartbeat and task.delay do not, so the section 6 fallback can freeze a hold whose rig was not
	stepped far enough to reach its hold pose; and an engine hitch stops the timers too, so the
	wake's step (a jump, or a shorter hitch's long frame) would carry the held clip past it. Either
	way the clip is moved on to its hold pose as it freezes (Choreo seek, ActionLogic.freezeAt), its
	ActivationHold firing as on a hold the display saw: the stance glows at the wake, and the
	release launches on a normal hold's timing. A hold the cancel time ran out on during a hitch is
	left to the cancel that comes in the same frame.

	The rig's step (D-139): the controller steps the local rig itself (Choreo.stepLocal) between
	feeding Locomotion and reading the root delta, so the body moves by this frame's root motion.
	Its render step runs at choreo.luau renderOrder.character: after Choreo's rigs and before
	every reader of a pose (the camera, the impact picture, the trails' blade samples: camera.luau
	and fx.luau renderOrder, D-211), so what this step moves and asks for (the root, the contact's
	nudge, shake and picture) shows on this frame.

	A dodge pressed while the display sleeps (D-141): the rig is asleep when a whole frame went by
	with no render step (ActionLogic.rigAsleep, Heartbeat counted). The DodgeRequest goes at the
	press, so the server's dodge (its i-frames, its cooldown) runs as ever; the show waits for the
	wake's step: after that step the clip plays from its start and the FOV kick, the speed lines
	and the whoosh with its landing go with it, so the body travels the whole dodge after the wake
	and nothing sounds before it moves. A press older than stall.jumpSeconds at the wake lies in the
	time the stall skipped and shows nothing (ActionLogic.wokenDodge).

	The sheathed sword: the server's Drawn attribute says whether the sword is out. Every combat
	request this client sends (an Art, a basic attack, a guard), a hit dealt or taken and a lock-on
	also predict it for choreo.luau sheath.predictSeconds, so the draw shows at once; a dodge does
	not. Locomotion moves the sword and plays Draw and Sheathe from that target.

	The two-step stop: when the stick lets go below the skid threshold, the root keeps going along
	its last move direction and slows down as the gait walks on, and stops where the walk's planted
	foot is over its Idle spot (ActionLogic.stopCarryStep, Locomotion.stopGait), never faster than
	it was moving, so the walk paced to it plants its feet instead of sliding over a body that
	stopped dead. Any input ends it.

	Lock-facing and aim (D-112): while TargetController holds a lock and the body is free (Idle,
	Guard, the held Art stance; not while the stick sprints), AutoRotate is off and the root turns
	toward the target at combat.luau aim.lockTurnRate on this render step, so the stick strafes and
	backs off around it at walk speed. A basic swing or an Art release turns the rest of the way to
	the lock at once, by at most aim.snapDegrees (with no lock, to the best enemy in the soft assist's
	cone), and only then reads the facing it sends: the server sweeps where that facing points
	(D-113). The snap also keeps the facing inside what the server accepts from a root it saw up to
	combat.lagAllowance ago (AimLogic.requestTurn and the yaw history), and a request sent while the
	lock's own turn is still sweeping the body round carries the nearest facing the server accepts
	(AimLogic.sendOffset), so the swing comes out instead of being refused.

	The snap's whip (item 102): the request faces the whole snap the instant it goes, but the body
	shows it over aim.snapTurnSeconds on aim.snapTurnEasing, stepped by time on the render step and
	on Heartbeat (which runs while the display sleeps), so it never pops a whole snap in one frame.
	Until it is over, everything that reads where the body aims (a new request, a dodge, a guard's
	facing, the clip's root motion) reads the facing the request carried, and the lock turn waits.

	Capture slow motion (dev.luau timeScale, D-111): in Studio in a capture place Capture.client hands the
	controller its time scale (setCaptureTimeScale) and the local body moves on that clock: the
	Humanoid's speed, the two-step stop, the lock turn and the snap's whip all run at the scale the
	clips do, so a slowed recording shows feet that keep their ground. Anywhere else (live play of
	the published Playground too) it stays 1.

	The hit on contact (issue 4): while a swing or a released Art plays, ContactPredictor sweeps the
	blade the rig shows each frame, right after the rig's step and its root motion, and every
	enemy it touches goes to Replication.contact on that frame: its hit-stop, the white flash, the
	camera and the sounds play as the blade lands, not a round trip later. The server's
	HitConfirmed still decides the hit and brings the number. A swing that ends, is refused or is
	taken from the body (a stagger, a new action, a respawn) predicts nothing more.

	Every decision is in ActionLogic and AimLogic (tested); this file is the engine glue around them.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Client = script.Parent.Parent

local Combat = require(Shared.data.combat)
local ChoreoData = require(Shared.data.choreo)
local InputData = require(Shared.data.input)
local Playground = require(Shared.data.playground)
local World = require(Shared.data.world)
local Arts = require(Shared.data.arts)
local Dev = require(Shared.data.dev)
local Types = require(Shared.types)
local Net = require(Shared.net.Net)
local TrailingSend = require(Shared.net.TrailingSend)
local Signal = require(Shared.util.Signal)

local ActionLogic = require(script.Parent.ActionLogic)
local AimLogic = require(script.Parent.AimLogic)
local ContactPredictor = require(script.Parent.ContactPredictor)
local EntityTracker = require(script.Parent.EntityTracker)
local Replication = require(script.Parent.Replication)
local WeaponInfo = require(script.Parent.WeaponInfo)
local Siblings = require(script.Parent.Siblings)
local CameraController = require(Client.camera.CameraController)
local FrameOrder = require(Client.fx.FrameOrder)

local Choreo = Siblings.load(Client, "choreo.Choreo")
local Locomotion = Siblings.load(Client, "choreo.Locomotion")
local DrawnBody = Siblings.load(Client, "choreo.DrawnBody")
local ClipLibrary, hasClipLibrary = Siblings.load(Client, "choreo.ClipLibrary")
local Trails = Siblings.load(Client, "fx.Trails")
local Hud = Siblings.load(Client, "ui.Hud")
local Impact = Siblings.load(Client, "fx.Impact")
-- The lock (D-112). Through Siblings and Siblings.call, so a harness that loads this controller
-- without the lock-on (or a build where it fails to load) simply has no lock and no assist.
local TargetController = Siblings.load(Client, "controllers.TargetController")

local RENDER_STEP_NAME = "SkyspireCharacter"
local ART_SLOTS_ATTRIBUTE = "ArtSlots"
local AIM: AimLogic.Config = Combat.aim
-- The section 6 time an Art hold freezes by when its clip carries no earlier ActivationHold.
local HOLD_FALLBACK = Combat.startPoseTime + Combat.activationHold

type Hold = {
	slot: number,
	art: Types.ArtDef,
	handle: any,
	pressedAt: number,
	frozenClipTime: number?,
	token: number,
}

type Predicted = {
	action: ActionLogic.Action,
	clipId: string,
	handle: any,
	token: number,
}

local CharacterController = {}

export type SlotEntry = { slot: number, art: Types.ArtDef, key: string }

--- Fires the new local state on every transition.
CharacterController.stateChanged = Signal.new() :: Signal.Signal<ActionLogic.LocalState>
--- Fires the quick-slot Art list ({slot, art, key} rows) whenever it is rebuilt.
CharacterController.slotsChanged = Signal.new() :: Signal.Signal<{ SlotEntry }>

local net: Net.ClientNet? = nil
local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local animator: any = nil
local locomotion: any = nil

local state: ActionLogic.LocalState = "Idle"
local sprinting = false
-- The capture's time scale (dev.luau timeScale; 1 in play): the clips' clock and, in a capture
-- place, the body's own movement run at it (setCaptureTimeScale).
local captureScale = 1
-- The scale last handed the animator: 0 while the Art stance or a release holds the clip frozen.
local appliedScale = 1
-- The snap the body is still whipping round to (item 102), or nil.
local snap: AimLogic.Snap? = nil
-- The facing the last ArtRequest or BasicAttackRequest carried (DevAim reports it).
local lastFacing: { number }? = nil
local lastPredictAt: number? = nil
local lastParryAt: number? = nil
local lastWalkSpeed: number? = nil
local lastAutoRotate: boolean? = nil
-- The root's yaw over the last combat.lagAllowance: what the server may still see (D-112).
local yawHistory: AimLogic.YawHistory = AimLogic.newHistory()
local dodgeReadyAt = 0
local basicChain = 0
local basicLastTime = 0
local actionEndsAt: number? = nil
local speeds: ActionLogic.Speeds = { walk = 0, run = 0, sprint = 0 }
local slots: { [number]: Types.ArtDef } = {}
local hold: Hold? = nil
local predicted: Predicted? = nil
local token = 0
local fallTracker: ActionLogic.FallTracker = { airborneSince = nil, peakY = 0 }
local stopCarry: ActionLogic.StopCarry = ActionLogic.newStopCarry()
local carrying = false -- the two-step stop moved the Humanoid last frame
local STOP_CARRY: ActionLogic.StopCarryConfig = {
	seconds = ChoreoData.locomotion.stopStepsSeconds,
	minCycles = ChoreoData.locomotion.stopMinCycles,
	endSpeed = ChoreoData.locomotion.stopEndSpeed,
	minSpeed = ChoreoData.locomotion.idleSpeedThreshold,
	maxSpeed = ChoreoData.locomotion.skidSpeedThreshold,
}
-- Locomotion.stopGait writes it.
local stopGait: ActionLogic.StopGait = { phase = 0, leftStep = 0, leftAfter = 0, rightStep = 0.5, rightAfter = 0 }
-- When the local rig last stepped (now()); nil before its first step. A render stall stops it.
local rigSteppedAt: number? = nil
-- The rig's last step was a render stall's jump (longer than choreo.luau stall.jumpSeconds): the
-- blade's sweep starts again from the pose it shows (ContactPredictor.step's `jumped`).
local rigJumped = false
-- Heartbeats since the local rig last stepped: past one, a frame went by unrendered (D-141).
local heartbeatsSinceRigStep = 0
-- A dodge pressed while the rig slept (D-141): its press time and token; its show waits for the wake.
local sleptDodge: { pressedAt: number, token: number }? = nil
local unhookRigStep: (() -> ())? = nil
local started = false
-- The local swing's blade contacts (issue 4), and the clip handle it follows.
local contacts = ContactPredictor.new({
	-- The tracker's live list, read every frame without a copy (item 5).
	targets = function(): { any }
		return EntityTracker.live()
	end,
	confirmed = Replication.confirmedAlready,
	hidden = Replication.drawnAway,
})
local contactHandle: any = nil
-- The last swing's sequence number (combat.luau contact.swingSequenceMax): each ArtRequest and
-- BasicAttackRequest carries the next, and its HitConfirmed echoes it (item 4).
local swingSequence = 0

-- The next swing's sequence number: 1 .. contact.swingSequenceMax, then round again.
local function nextSwing(): number
	swingSequence = swingSequence % Combat.contact.swingSequenceMax + 1
	return swingSequence
end

local function now(): number
	return os.clock()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function nextToken(): number
	token += 1
	return token
end

local function setState(newState: ActionLogic.LocalState)
	if newState == state then
		return
	end
	state = newState
	CharacterController.stateChanged:Fire(newState)
end

-- The root's rotation with the rest of a showing snap on it: where the last request faced the body
-- (before its sendOffset), which every new aim, request, dodge and root motion step reads.
local function aimRotation(rootPart: BasePart): CFrame
	local rotation = rootPart.CFrame.Rotation
	local current = snap
	if current == nil then
		return rotation
	end
	return CFrame.Angles(0, math.rad(AimLogic.snapLeft(current)), 0) * rotation
end

local function facingTable(): { number }
	local look = if root ~= nil then aimRotation(root).LookVector else Vector3.zAxis * -1
	return { look.X, look.Y, look.Z }
end

local function fire(remote: string, payload: any)
	if net ~= nil then
		net.fire(remote, payload)
	end
end

-- ------------------------------------------------------------------ aim (D-112)

-- The locked enemy's position, or nil with no lock (TargetController drops a dead or gone lock):
-- where its body is drawn (D-193), so the body turns to the boar the player sees, not to the
-- hidden root a rush leaves behind it.
local function lockPosition(): Vector3?
	local record = Siblings.call(TargetController, "current")
	if record == nil or record.model == nil then
		return nil
	end
	local drawn = Siblings.call(DrawnBody, "position", record.model)
	if drawn ~= nil then
		return drawn
	end
	local primary = record.model.PrimaryPart
	return if primary ~= nil then primary.Position else nil
end

-- Turns the root about the world's up axis by `degrees` (+ = left), where it stands.
local function yawRoot(rootPart: BasePart, degrees: number)
	if degrees == 0 then
		return
	end
	local frame = rootPart.CFrame
	rootPart.CFrame = CFrame.new(frame.Position) * CFrame.Angles(0, math.rad(degrees), 0) * frame.Rotation
end

local function recordYaw(rootPart: BasePart, t: number)
	local look = rootPart.CFrame.LookVector
	AimLogic.record(yawHistory, t, AimLogic.yawOf(look.X, look.Z), Combat.lagAllowance)
end

-- Shows the next part of a showing snap at time `t` (the render step and Heartbeat, so it ends on
-- time while the display sleeps too); forgets the snap once the body shows all of it.
local function stepSnap(rootPart: BasePart, t: number)
	local current = snap
	if current == nil then
		return
	end
	yawRoot(rootPart, AimLogic.snapStep(current, t, AIM.snapTurnEasing))
	if AimLogic.snapLeft(current) == 0 then
		snap = nil
	end
end

-- Degrees (+ = left) from a frame's look to the lock, or nil (no lock, or standing on it).
local function lockBearing(frame: CFrame, lockAt: Vector3): number?
	local look, origin = frame.LookVector, frame.Position
	return AimLogic.bearingTo(look.X, look.Z, origin.X, origin.Z, lockAt.X, lockAt.Z, AIM.minFaceDistance)
end

-- The snap a basic swing or an Art release makes before it reads its facing: the rest of the way
-- to the lock, or with no lock to the soft assist's pick, by at most aim.snapDegrees and never out
-- of what the server can accept from a root it saw up to combat.lagAllowance ago. Returns the
-- facing the request carries: the snapped look, or mid-turn the nearest look to it the server can
-- accept (AimLogic.sendOffset). The body shows the snap as a whip over aim.snapTurnSeconds (item
-- 102); a whip still showing from the last request is counted as done here and carries on.
local function aimForRequest(): { number }
	local rootPart = root
	if rootPart == nil then
		return facingTable()
	end
	local t = now()
	-- What the server may have seen: the body as it shows now, and where the last request faced it.
	recordYaw(rootPart, t)
	local rotation = aimRotation(rootPart)
	local left = if snap ~= nil then AimLogic.snapLeft(snap) else 0
	local aimLook = rotation.LookVector
	local aimYaw = AimLogic.yawOf(aimLook.X, aimLook.Z)
	if left ~= 0 then
		AimLogic.record(yawHistory, t, aimYaw, Combat.lagAllowance)
	end
	local frame = CFrame.new(rootPart.Position) * rotation
	local delta: number? = nil
	local lockAt = lockPosition()
	if lockAt ~= nil then
		delta = lockBearing(frame, lockAt)
	else
		local candidates = Siblings.call(TargetController, "assistCandidates", frame.Position, aimLook)
		local pick = if candidates ~= nil then AimLogic.assistPick(candidates, AIM) else nil
		delta = if pick ~= nil then pick.bearing else nil
	end
	local turn = 0
	if delta ~= nil then
		local lo, hi = AimLogic.range(yawHistory)
		turn = AimLogic.requestTurn(delta, lo, hi, AIM)
		if turn ~= 0 then
			-- The request faces the whole snap now: the server sweeps there (D-113) and may see the
			-- root anywhere along the whip, between the two yaws the history now holds.
			AimLogic.record(yawHistory, t, aimYaw + turn, Combat.lagAllowance)
		end
	end
	local whole = left + turn
	snap = if whole ~= 0 then AimLogic.newSnap(whole, t, AimLogic.snapSeconds(AIM, captureScale)) else nil
	local lo, hi = AimLogic.range(yawHistory)
	local offset = AimLogic.sendOffset(lo, hi, AIM)
	local look = (CFrame.Angles(0, math.rad(turn + offset), 0) * rotation).LookVector
	local facing = { look.X, look.Y, look.Z }
	lastFacing = facing
	return facing
end

-- GuardRequest goes through TrailingSend: never faster than its rate limit, and the last raise or
-- release always arrives, so tapping guard cannot leave the server holding a guard (and the sword
-- drawn) the client let go of. The facing and clock are read when the request goes out.
local guardSender: TrailingSend.TrailingSend? = nil
local function sendGuard(held: boolean)
	if guardSender == nil then
		guardSender = TrailingSend.new({
			gap = TrailingSend.gapOf("GuardRequest"),
			burst = World.anticheat.remoteRates.GuardRequest.clientBurst,
			now = now,
			schedule = function(seconds: number, fn: () -> ())
				task.delay(seconds, fn)
			end,
			send = function(isHeld: boolean)
				fire("GuardRequest", { held = isHeld, facing = facingTable(), clientTime = serverNow() })
			end,
		})
	end
	(guardSender :: TrailingSend.TrailingSend):set(held)
end

local function weaponCategory(): string
	local record = EntityTracker.localRecord()
	return WeaponInfo.categoryOf(if record ~= nil then record.weaponId else nil)
end

local function trailToken(): string
	local record = EntityTracker.localRecord()
	return WeaponInfo.trailTokenOf(if record ~= nil then record.weaponId else nil)
end

local function playerClip(name: string): string?
	local record = EntityTracker.localRecord()
	local rig = if record ~= nil then record.rig else ""
	local id = ActionLogic.clipId("Player", rig, weaponCategory(), name)
	if not hasClipLibrary or ClipLibrary.has(id) == true then
		return id
	end
	return nil
end

-- The equipped weapon's attack (the kill rule's least damage), the loadout's before the tracker knows.
local function weaponAttack(): number
	local record = EntityTracker.localRecord()
	local def = WeaponInfo.def(if record ~= nil then record.weaponId else Playground.loadout.weapon)
	return if def ~= nil and typeof(def.attack) == "number" then def.attack else 0
end

-- Predicts the blade's contacts for the swing or Art a clip handle plays (a data clip only: an
-- engine Animation has no clip to sweep).
local function predictContacts(handle: any, artId: string?, finalHit: boolean, multiplier: number, sequence: number)
	contacts:stop()
	contactHandle = nil
	local model = character
	if model == nil or typeof(handle) ~= "table" or typeof(handle.clip) ~= "table" then
		return
	end
	local swing: ContactPredictor.Swing = {
		model = model :: Model,
		clip = handle.clip,
		artId = artId,
		finalHit = finalHit,
		multiplier = multiplier,
		weaponAttack = weaponAttack(),
		swing = sequence,
	}
	if contacts:begin(swing) then
		contactHandle = handle
	end
end

-- This frame's contacts, on the pose the rig just showed (after its step and the root motion).
-- The swing's clip must still be the one playing.
local function stepContacts()
	if contactHandle == nil then
		return
	end
	local current = predicted
	local handle = contactHandle
	if current == nil or current.handle ~= handle or handle.done == true or typeof(handle.time) ~= "number" then
		contacts:stop()
		contactHandle = nil
		return
	end
	local jumped = rigJumped
	rigJumped = false
	for _, contact in contacts:step(handle.time, jumped) do
		if Replication.contact(contact) then
			CharacterController.predictDraw()
		end
	end
end

local function setTimeScale(scale: number)
	appliedScale = scale
	if animator ~= nil then
		animator:setTimeScale(scale)
	end
end

local function stopClip(handle: any)
	if animator ~= nil and handle ~= nil then
		animator:stop(handle, Combat.locomotionBlendOut)
	end
end

local function stance(): ActionLogic.Stance
	local moving = false
	local airborne = false
	if humanoid ~= nil then
		moving = humanoid.MoveDirection.Magnitude > 0
		airborne = humanoid.FloorMaterial == Enum.Material.Air
	end
	local afterParry = lastParryAt ~= nil and now() - (lastParryAt :: number) <= Combat.parryStagger
	return { moving = moving, airborne = airborne, afterParry = afterParry }
end

--- Shows the sword drawn now, ahead of the server's Drawn attribute (a combat request was sent,
--- a hit landed, or a target was locked).
function CharacterController.predictDraw()
	lastPredictAt = now()
end
local predictDraw = CharacterController.predictDraw

-- ------------------------------------------------------------------ Art hold / launch / cancel

local function clearHold()
	if hold == nil then
		return
	end
	local current = hold :: Hold
	hold = nil
	setTimeScale(captureScale)
	stopClip(current.handle)
	-- The wind-up contour ends with the hold, however it ended, and the blade light fades out
	-- (issue 13): a hold that ends without a launch lets its glow go, never cuts it in a frame.
	Impact.cancelActivation(character)
	if character ~= nil then
		Trails.activationLight(character, false, trailToken(), true)
	end
end

-- The clip time of the held Art's hold pose (ActionLogic.holdClipTime), or nil when its handle has
-- no clip clock (an engine Animation).
local function holdClipTime(current: Hold): number?
	local handle = current.handle
	if typeof(handle) ~= "table" or typeof(handle.time) ~= "number" then
		return nil
	end
	return ActionLogic.holdClipTime(handle.clip, HOLD_FALLBACK)
end

--- Freezes the held Art clip at its activation hold (the glowing stance). A clip a render stall
--- kept from getting there (the rig was not stepped since before it could) is moved on to its
--- hold pose first, its ActivationHold firing on the way as it would have (D-138).
function CharacterController.freezeHold()
	if hold == nil or animator == nil then
		return
	end
	local current = hold :: Hold
	if current.frozenClipTime ~= nil then
		return
	end
	local clipTime, seek = ActionLogic.freezeAt(current.pressedAt, now(), holdClipTime(current), rigSteppedAt)
	current.frozenClipTime = clipTime
	setTimeScale(0)
	if seek then
		-- Replication lights the blade and chimes on the ActivationHold; the clipEvent listener
		-- finds the hold frozen already.
		animator:seek(current.handle, clipTime)
	end
end

-- Runs before every step of the local rig (Choreo onStep, with the dt the rig takes). A render
-- stall's jump would carry a held clip past its hold pose in one step, and after an engine hitch
-- the wake's step comes before task.delay resumes the fallback; a hitch shorter than a jump is
-- no jump at all, so its step would carry the clip on into the swing with its trail and smear
-- lit. A hold old enough to be at its hold pose that nothing froze yet freezes there first when
-- the step is a jump or would carry the clip past its activation hold (combat.luau
-- activationHold after the hold pose; no steady frame rate of 10 fps or more does); one the
-- cancel time has run out on is left to the cancel, which comes in the same frame (D-138). Then
-- the step is remembered, so a freeze can tell a rig that was not stepped from one that was.
local function beforeRigStep(dt: number)
	local current = hold
	if current ~= nil and current.frozenClipTime == nil then
		local holdAt = holdClipTime(current)
		local age = now() - current.pressedAt
		if holdAt ~= nil and age >= holdAt and age < Combat.activationCancelTime then
			-- Where the step would leave the clip (an Art plays at speed 1, ActionLogic.freezeAt).
			local reached = current.handle.time + dt * appliedScale
			if dt > ChoreoData.stall.jumpSeconds or reached > holdAt + Combat.activationHold then
				CharacterController.freezeHold()
			end
		end
	end
	rigSteppedAt = now()
	rigJumped = dt > ChoreoData.stall.jumpSeconds
	heartbeatsSinceRigStep = 0
end

--- The Art key went down: enter the start pose of the Art this slot picks from the current stance.
function CharacterController.beginArt(slot: number)
	if animator == nil or hold ~= nil then
		return
	end
	local ok = ActionLogic.canStart(state, "Art", now(), dodgeReadyAt)
	if not ok then
		return
	end
	local art = ActionLogic.pickArt(slots, slot, InputData.art.slots, stance())
	if art == nil then
		return
	end
	local holdToken = nextToken()
	hold = {
		slot = slot,
		art = art,
		handle = animator:play(art.clip),
		pressedAt = now(),
		frozenClipTime = nil,
		token = holdToken,
	}
	setState("Holding")
	predictDraw()
	Siblings.call(Hud, "noteArtUse")
	-- If the clip carries no ActivationHold event the freeze still lands at the section 6 time.
	task.delay(HOLD_FALLBACK, function()
		if hold ~= nil and (hold :: Hold).token == holdToken then
			CharacterController.freezeHold()
		end
	end)
end

--- The Art key came up after `heldSeconds`: launch inside the cancel time, let go past it.
function CharacterController.releaseArt(slot: number, heldSeconds: number)
	if hold == nil or (hold :: Hold).slot ~= slot then
		return
	end
	local current = hold :: Hold
	if ActionLogic.holdOutcome(heldSeconds, Combat.activationCancelTime) == "Cancel" then
		clearHold()
		setState("Idle")
		return
	end
	local releasedAt = now()
	local plan = ActionLogic.syncPlan(current.pressedAt, current.frozenClipTime, releasedAt)
	if character ~= nil then
		-- The clip waits at freezeClipTime for freezeClipTime more: the riser and the highs land on
		-- its first damage frame after that.
		Impact.release(character :: Model, current.art.clip, plan.freezeClipTime, plan.freezeClipTime)
	end
	if current.frozenClipTime == nil then
		setTimeScale(0)
	end
	hold = nil
	local launchToken = current.token
	predicted = { action = "Art", clipId = current.art.clip, handle = current.handle, token = launchToken }
	-- Every Art's last window is its final hit (section 6).
	local sequence = nextSwing()
	predictContacts(current.handle, current.art.id, true, current.art.multiplier, sequence)
	setState("Art")
	-- The server's Idle normally ends the Art; this is the fallback if that state never arrives.
	actionEndsAt = ActionLogic.artFallbackEnd(releasedAt, plan.freezeClipTime, current.art, Combat.lagAllowance)
	predictDraw()
	fire("ArtRequest", { artId = current.art.id, facing = aimForRequest(), clientTime = serverNow(), swing = sequence })
	task.delay(plan.freezeClipTime, function()
		if predicted ~= nil and (predicted :: Predicted).token == launchToken then
			setTimeScale(captureScale)
		end
	end)
end

--- The hold passed the cancel time: the glow fades and the stance relaxes.
function CharacterController.cancelArt(slot: number)
	if hold == nil or (hold :: Hold).slot ~= slot then
		return
	end
	clearHold()
	setState("Idle")
end

-- ------------------------------------------------------------------ basic, guard, dodge

--- Basic attack: the next hit of the three-hit chain (section 6). Clicks faster than the
--- server's BasicAttackRequest refill are dropped here, so honest mashing never reads as abuse.
function CharacterController.basicAttack()
	if animator == nil then
		return
	end
	local t = now()
	local ok = ActionLogic.canStart(state, "Basic", t, dodgeReadyAt)
	if not ok then
		return
	end
	if not ActionLogic.basicReady(basicLastTime, t, 1 / World.anticheat.remoteRates.BasicAttackRequest.perSecond) then
		return
	end
	basicChain = ActionLogic.nextBasic(basicChain, basicLastTime, t, Combat.basicChainWindow, Combat.basicChainLength)
	basicLastTime = t
	local clipId = playerClip("Basic" .. tostring(basicChain))
	if clipId == nil then
		return
	end
	local basicToken = nextToken()
	predicted = { action = "Basic", clipId = clipId, handle = animator:play(clipId), token = basicToken }
	-- A basic chain's final hit is its last swing (section 6).
	local sequence = nextSwing()
	predictContacts(
		(predicted :: Predicted).handle,
		nil,
		basicChain >= Combat.basicChainLength,
		Combat.basicAttackMultiplier,
		sequence
	)
	setState("Basic")
	actionEndsAt = t + Combat.basicHitDuration
	predictDraw()
	fire("BasicAttackRequest", { facing = aimForRequest(), clientTime = serverNow(), swing = sequence })
end

--- Guard held or released; a tap inside the parry window is the server's call.
function CharacterController.setGuard(held: boolean)
	if animator == nil then
		return
	end
	if held then
		local ok = ActionLogic.canStart(state, "Guard", now(), dodgeReadyAt)
		if not ok then
			return
		end
		local clipId = playerClip("Guard")
		local guardToken = nextToken()
		predicted = {
			action = "Guard",
			clipId = clipId or "",
			handle = if clipId ~= nil then animator:play(clipId) else nil,
			token = guardToken,
		}
		setState("Guard")
		predictDraw()
		-- The raise sounds with the predicted pose (Replication plays it for everyone else).
		Impact.guardRaise(character, true)
		sendGuard(true)
	elseif state == "Guard" then
		if predicted ~= nil then
			stopClip((predicted :: Predicted).handle)
			predicted = nil
		end
		setState("Idle")
		sendGuard(false)
	end
end

-- The dodge's show on this screen: the FOV kick, the speed lines and the whoosh for anyone near.
local function showDodge()
	CameraController.fovKick("Dash")
	if character ~= nil then
		Impact.dodge(character :: Model, true)
	end
end

--- Dodge: a 0.25 s step in the move direction (back when there is no input), 0.6 s cooldown.
function CharacterController.dodge()
	if animator == nil or root == nil or humanoid == nil then
		return
	end
	local t = now()
	local ok = ActionLogic.canStart(state, "Dodge", t, dodgeReadyAt)
	if not ok then
		return
	end
	if state == "Holding" then
		clearHold()
	elseif state == "Guard" and predicted ~= nil then
		stopClip((predicted :: Predicted).handle)
		sendGuard(false)
	end
	local rootPart = root :: BasePart
	-- Relative to where the body aims: a snap's whip still showing turns it to the last request's facing.
	local rotation = aimRotation(rootPart)
	-- The stick, not the Humanoid: the two-step stop keeps moving the Humanoid along the last move
	-- after the stick lets go, and a dodge with no input steps back.
	local stick = if stopCarry.active then Vector3.zero else (humanoid :: Humanoid).MoveDirection
	local moveLocal = rotation:VectorToObjectSpace(stick)
	local direction = ActionLogic.dodgeDirection(moveLocal.X, moveLocal.Z, InputData.dodge.inputDeadzone)
	local look = rotation.LookVector
	local right = rotation.RightVector
	local world = if direction == "Forward"
		then look
		elseif direction == "Back" then -look
		elseif direction == "Left" then -right
		else right
	local clipId = playerClip("Dodge" .. direction)
	local dodgeToken = nextToken()
	-- Pressed while the rig sleeps (D-141): the request goes now and the show waits for the wake.
	local asleep = rigSteppedAt ~= nil and ActionLogic.rigAsleep(heartbeatsSinceRigStep)
	predicted = {
		action = "Dodge",
		clipId = clipId or "",
		handle = if clipId ~= nil and not asleep then animator:play(clipId) else nil,
		token = dodgeToken,
	}
	setState("Dodge")
	dodgeReadyAt = t + Combat.dodgeCooldown
	if asleep then
		actionEndsAt = nil
		sleptDodge = { pressedAt = t, token = dodgeToken }
	else
		actionEndsAt = t + Combat.dodgeDuration
		showDodge()
	end
	fire("DodgeRequest", { direction = { world.X, world.Y, world.Z }, clientTime = serverNow() })
end

--- Sprint on or off (hold on keyboard, toggle on gamepad and touch).
function CharacterController.setSprinting(on: boolean)
	sprinting = on
end

--- The current local state.
function CharacterController.state(): ActionLogic.LocalState
	return state
end

--- The facing ({x, y, z}) the last ArtRequest or BasicAttackRequest carried, or nil before the
--- first. Each request gets a new table. The body whips round to it over aim.snapTurnSeconds, so
--- right after the send the root may still look elsewhere (DevAim reports this one).
function CharacterController.lastFacing(): { number }?
	return lastFacing
end

--- Dev capture slow motion (Capture.client, dev.luau timeScale, D-111): runs the local body on the
--- capture's clock, one of dev.luau timeScale.steps, so a slowed recording shows the body moving
--- at the pace its slowed clips step (the walk and strafe, the two-step stop, the lock turn, the
--- snap's whip), and hands the animator the scale unless the Art stance or a release holds the
--- clip frozen (that scale comes back when it lets go). Only in Studio in a capture place (workspace
--- DevCapture; the published Playground carries it too, and live play never slows): anywhere
--- else, or at a scale the capture does not offer, it refuses and returns false. Never faster than
--- 1x, so no anti-cheat speed check can see it.
function CharacterController.setCaptureTimeScale(scale: number): boolean
	if not RunService:IsStudio() or workspace:GetAttribute(Dev.attributes.capture) ~= true then
		return false
	end
	if table.find(Dev.timeScale.steps, scale) == nil or scale <= 0 or scale > 1 then
		return false
	end
	captureScale = scale
	if appliedScale ~= 0 then
		setTimeScale(scale)
	end
	return true
end

-- ------------------------------------------------------------------ server reconciliation

local function endAction()
	predicted = nil
	actionEndsAt = nil
	setState("Idle")
end

local function onRejected(action: string)
	local map: { [string]: ActionLogic.Action } =
		{ Art = "Art", BasicAttack = "Basic", Guard = "Guard", Dodge = "Dodge" }
	local expected = map[action]
	if expected == nil or predicted == nil or (predicted :: Predicted).action ~= expected then
		return
	end
	local current = predicted :: Predicted
	predicted = nil
	setTimeScale(captureScale)
	stopClip(current.handle)
	if character ~= nil and expected == "Art" then
		-- A refused Art is a cancelled one: its glow fades (issue 13).
		Trails.activationLight(character, false, trailToken(), true)
	end
	actionEndsAt = nil
	setState("Idle")
end

local function onServerState(serverState: string)
	local verb = ActionLogic.reconcile(state, serverState)
	if verb == "None" then
		return
	end
	if hold ~= nil then
		clearHold()
	end
	if verb == "EndAction" then
		endAction()
		return
	end
	-- Stagger, GuardBroken, Break, Die: the body is taken from the player; Replication plays the clip.
	if predicted ~= nil then
		stopClip((predicted :: Predicted).handle)
		predicted = nil
	end
	setTimeScale(captureScale)
	actionEndsAt = nil
	if verb == "Die" then
		setState("Dead")
	elseif verb == "GuardBroken" then
		setState("GuardBroken")
	else
		setState("Stagger")
	end
end

local function onHit(payload: any)
	local localId = EntityTracker.peekLocalId()
	if localId == nil then
		return
	end
	if payload.targetId == localId then
		predictDraw()
		if payload.parried then
			lastParryAt = now()
		end
	elseif payload.attackerId == localId then
		predictDraw()
	end
end

-- ------------------------------------------------------------------ slots

local function slotIds(): { string }
	local attribute = if character ~= nil then character:GetAttribute(ART_SLOTS_ATTRIBUTE) else nil
	if typeof(attribute) == "string" and attribute ~= "" then
		local ids = {}
		for id in attribute:gmatch("[^,%s]+") do
			table.insert(ids, id)
		end
		return ids
	end
	return Playground.loadout.artSlots
end

local function slotAction(index: number): string
	return if index == InputData.art.defaultSlot then "Art" else "ArtSlot" .. tostring(index)
end

local function refreshSlots()
	slots = ActionLogic.slotArts(slotIds(), Arts.byId, function(clipId)
		return not hasClipLibrary or ClipLibrary.has(clipId) == true
	end, InputData.art.slots)
	local list: { SlotEntry } = {}
	local hudRows: { { name: string, key: string } } = {}
	for index = 1, InputData.art.slots do
		local art = slots[index]
		if art ~= nil then
			local key = InputData.keyLabel(slotAction(index), "keyboard")
			table.insert(list, { slot = index, art = art, key = key })
			table.insert(hudRows, { name = art.name, key = key })
		end
	end
	CharacterController.slotsChanged:Fire(list)
	-- Hud.showArts takes {name, key} rows (the bottom-center Art list, section 14).
	Hud.showArts(hudRows)
end

--- The quick-slot Arts (slot index -> Art).
function CharacterController.slots(): { [number]: Types.ArtDef }
	return slots
end

-- ------------------------------------------------------------------ per-frame

-- The wake's step for a dodge pressed while the rig slept (D-141), after the rig's step: the clip
-- plays from its start (the next step moves it, so the wake's long step carries none of it) with
-- its kick and cue, and the dodge lasts its whole length from here; a press the stall skipped
-- ends it unseen. A dodge the server refused, or a respawn, in the dark has left nothing to show.
local function wakeSleptDodge(t: number)
	local slept = sleptDodge
	if slept == nil then
		return
	end
	sleptDodge = nil
	local current = predicted
	if current == nil or current.token ~= slept.token then
		return
	end
	if ActionLogic.wokenDodge(slept.pressedAt, t, ChoreoData.stall.jumpSeconds) == "Drop" then
		endAction()
		return
	end
	if current.clipId ~= "" then
		current.handle = animator:play(current.clipId)
	end
	actionEndsAt = t + Combat.dodgeDuration
	showDodge()
end

local function step(dt: number)
	local model, hum, rootPart = character, humanoid, root
	if model == nil or hum == nil or rootPart == nil or animator == nil then
		return
	end
	local t = now()
	if
		actionEndsAt ~= nil
		and t >= (actionEndsAt :: number)
		and (state == "Basic" or state == "Dodge" or state == "Art")
	then
		endAction()
	end
	-- The snap's whip (item 102); the lock turn below waits until the body shows all of it.
	stepSnap(rootPart, t)

	local locked = ActionLogic.movementLocked(state)
	-- A held lock turns a free body to face it (D-112); a sprint (the sprint key with the stick
	-- moving) hands the facing back to the stick unless aim.lockFaceWhileSprinting.
	local lockAt = lockPosition()
	local sprintingNow = sprinting and hum.MoveDirection.Magnitude > 0
	local faceLock = AimLogic.facesLock(state, lockAt ~= nil, sprintingNow, AIM)
	-- Facing the lock, the stick strafes and backs off at walk speed (the walk set's feet, D-054).
	local walkSpeed = AimLogic.moveSpeed(ActionLogic.speedFor(state, sprinting, speeds), faceLock, speeds.walk)
	-- Each Humanoid write fires its Changed handlers (and WalkSpeed replicates), so each property
	-- is written once, only when it changes: AutoRotate here, WalkSpeed below with the carry.
	local autoRotate = not locked and not faceLock
	if autoRotate ~= lastAutoRotate then
		hum.AutoRotate = autoRotate
		lastAutoRotate = autoRotate
	end
	if faceLock and lockAt ~= nil and snap == nil then
		local delta = lockBearing(rootPart.CFrame, lockAt)
		if delta ~= nil then
			-- On the capture's clock (1 in play).
			yawRoot(rootPart, AimLogic.turnStep(delta, AIM.lockTurnRate, dt * captureScale))
		end
	end

	-- Locomotion keeps the Drawn attribute from its change signal, so no attribute is read per frame.
	local drawn = ActionLogic.drawnTarget(
		if locomotion ~= nil then locomotion:serverDrawn() else false,
		lastPredictAt,
		t,
		ChoreoData.sheath.predictSeconds
	)

	local velocity = rootPart.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local fallHeight = ActionLogic.fallStep(fallTracker, grounded, rootPart.Position.Y, t)
	local look = rootPart.CFrame.LookVector
	local moveDir = hum.MoveDirection
	-- The two-step stop: after the stick lets go the root slows to a stop along its last move
	-- direction (the control script's Move ran earlier this frame; this one overrides it).
	local gait: ActionLogic.StopGait? = nil
	if locomotion ~= nil and moveDir.Magnitude == 0 and typeof(locomotion.stopGait) == "function" then
		locomotion:stopGait(stopGait)
		gait = stopGait
	end
	-- The carry and the Humanoid's speed run on the capture's clock (1 in play): the carry in 1x
	-- terms, its speed slowed back down for the Humanoid.
	local carrySpeed = ActionLogic.stopCarryStep(
		stopCarry,
		moveDir.X,
		moveDir.Z,
		speed / captureScale,
		walkSpeed,
		grounded,
		state,
		dt * captureScale,
		STOP_CARRY,
		gait
	)
	local targetSpeed = (if carrySpeed > 0 then carrySpeed else walkSpeed) * captureScale
	if targetSpeed ~= lastWalkSpeed then
		hum.WalkSpeed = targetSpeed
		lastWalkSpeed = targetSpeed
	end
	if carrySpeed > 0 then
		moveDir = Vector3.new(stopCarry.x, 0, stopCarry.z)
		hum:Move(moveDir)
		carrying = true
	elseif carrying then
		carrying = false
		if moveDir.Magnitude == 0 then
			hum:Move(Vector3.zero)
		end
	end
	-- Degrees from the facing to the direction the stick asks for (+ = left): Locomotion turns in
	-- place past choreo.locomotion.turnInPlaceDegrees.
	-- Facing a lock, the body turns itself: the stick's angle is a strafe, not a turn.
	local turning = if locked or faceLock then 0 else ActionLogic.turnAngle(look.X, look.Z, moveDir.X, moveDir.Z)

	-- Locomotion hears the root's own speed: it paces the clips on the mixer's scaled clock itself,
	-- and reads the speed at 1x for the blend from the clock the body moves on (the capture's).
	if locomotion ~= nil and state ~= "Dead" then
		locomotion:update(dt, {
			moveDir = moveDir,
			speed = speed,
			clockScale = captureScale,
			sprinting = sprinting and not locked and not faceLock,
			grounded = grounded,
			drawn = drawn,
			turning = turning,
			fallHeight = fallHeight,
			verticalVelocity = velocity.Y,
			-- The reading `speed` came from: a velocity off the stick blocks the body (D-144).
			velocity = velocity,
		})
	end

	-- The rig's step, here and nowhere else (D-139): this frame's pose, clip events and root delta,
	-- moved by just below. A step after a render stall is a jump (Choreo, D-132).
	Siblings.call(Choreo, "stepLocal", dt)

	if ActionLogic.rootMotionActive(state) then
		local delta = animator:currentRootMotionDelta()
		if typeof(delta) == "Vector3" and delta.Magnitude > 0 then
			-- Along the facing the request carried: a whip still showing has the rest of its turn to
			-- come (with none, this is the root's own space).
			rootPart.CFrame = rootPart.CFrame + aimRotation(rootPart):VectorToWorldSpace(delta)
		end
	end
	-- The blade on the pose this frame shows: a touch plays its hit now (issue 4).
	stepContacts()
	wakeSleptDodge(t)
	recordYaw(rootPart, t)
end

-- ------------------------------------------------------------------ character lifecycle

local function clearCharacter()
	if hold ~= nil then
		clearHold()
	end
	if typeof(locomotion) == "table" and typeof(locomotion.destroy) == "function" then
		locomotion:destroy()
	end
	if unhookRigStep ~= nil then
		unhookRigStep()
		unhookRigStep = nil
	end
	rigSteppedAt = nil
	rigJumped = false
	heartbeatsSinceRigStep = 0
	sleptDodge = nil
	Siblings.call(Choreo, "setLocalModel", nil)
	character, humanoid, root, animator, locomotion = nil, nil, nil, nil, nil
	predicted = nil
	contacts:stop()
	contactHandle = nil
	actionEndsAt = nil
	lastWalkSpeed = nil
	lastAutoRotate = nil
	yawHistory = AimLogic.newHistory()
	snap = nil
	lastPredictAt = nil
	fallTracker = { airborneSince = nil, peakY = 0 }
	stopCarry = ActionLogic.newStopCarry()
	carrying = false
	setState("Idle")
end

local function onCharacter(model: Model)
	clearCharacter()
	character = model
	local hum = model:WaitForChild("Humanoid") :: Humanoid
	local rootPart = model:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid = hum
	root = rootPart
	-- Phase 0 has no jump (Space is the dodge, section 6); ledges still produce falls.
	hum.JumpPower = 0
	hum.JumpHeight = 0
	speeds = ActionLogic.resolveSpeeds(
		ChoreoData,
		{ walk = hum.WalkSpeed, run = hum.WalkSpeed, sprint = Combat.maxSpeedStudsPerSecond }
	)
	animator = Choreo.get(model)
	-- A new animator runs at 1x; in a slowed capture the body comes back on the capture's clock.
	appliedScale = 1
	if captureScale ~= 1 then
		setTimeScale(captureScale)
	end
	unhookRigStep = animator:onStep(beforeRigStep)
	-- The local rig is always at full rate, and this controller's to step (stepLocal, D-139).
	Siblings.call(Choreo, "setLocalModel", model, true)
	locomotion = Locomotion.new(animator, model)
	model:GetAttributeChangedSignal(ART_SLOTS_ATTRIBUTE):Connect(refreshSlots)
	refreshSlots()
end

--- Starts the controller: character hooks, server reconciliation, the per-frame step.
function CharacterController.start()
	if started then
		return
	end
	started = true
	net = Net.client()
	local player = Players.LocalPlayer

	Replication.rejected:Connect(function(action: string)
		onRejected(action)
	end)
	Replication.hit:Connect(onHit)
	Replication.clipEvent:Connect(function(record: any, clipId: string, event: any, _jumped: boolean)
		if hold == nil or character == nil or record.model ~= character then
			return
		end
		-- A jumped one freezes it too: the hold is state (D-132). None should come: before a jump
		-- that would carry the clip past its hold, beforeRigStep froze it at its hold pose.
		if event.kind == "ActivationHold" and clipId == (hold :: Hold).art.clip then
			CharacterController.freezeHold()
		end
	end)
	EntityTracker.changed:Connect(function(record: any, attribute: string, value: any)
		if record.id ~= EntityTracker.peekLocalId() then
			return
		end
		if attribute == "State" and typeof(value) == "string" then
			onServerState(value)
		elseif attribute == "WeaponId" then
			refreshSlots()
		end
	end)
	EntityTracker.localChanged:Connect(function(id: number?)
		if id ~= nil then
			refreshSlots()
		end
	end)

	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		clearCharacter()
	end)
	if player.Character ~= nil then
		onCharacter(player.Character :: Model)
	end

	RunService:BindToRenderStep(RENDER_STEP_NAME, FrameOrder.priority(ChoreoData.renderOrder.character), step)
	-- The yaw history is kept on Heartbeat too, which runs while the display sleeps (RenderStepped
	-- does not): a turn made outside the render step (the dev aim hook's face, the engine's own) is
	-- timed when it happens, not taken for a turn made just before the next swing (D-112). The snap's
	-- whip steps here too, so it ends on time while nothing renders. A second Heartbeat with no rig
	-- step tells a dodge the display sleeps (D-141).
	RunService.Heartbeat:Connect(function()
		heartbeatsSinceRigStep += 1
		local rootPart = root
		if rootPart ~= nil then
			local t = now()
			stepSnap(rootPart, t)
			recordYaw(rootPart, t)
		end
	end)
end

return CharacterController
