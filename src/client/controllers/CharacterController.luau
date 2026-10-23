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
local Types = require(Shared.types)
local Net = require(Shared.net.Net)
local TrailingSend = require(Shared.net.TrailingSend)
local Signal = require(Shared.util.Signal)

local ActionLogic = require(script.Parent.ActionLogic)
local AimLogic = require(script.Parent.AimLogic)
local EntityTracker = require(script.Parent.EntityTracker)
local Replication = require(script.Parent.Replication)
local WeaponInfo = require(script.Parent.WeaponInfo)
local Siblings = require(script.Parent.Siblings)
local CameraController = require(Client.camera.CameraController)

local Choreo = Siblings.load(Client, "choreo.Choreo")
local Locomotion = Siblings.load(Client, "choreo.Locomotion")
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
local timeScale = 1
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
local started = false

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

local function facingTable(): { number }
	local look = if root ~= nil then root.CFrame.LookVector else Vector3.zAxis * -1
	return { look.X, look.Y, look.Z }
end

local function fire(remote: string, payload: any)
	if net ~= nil then
		net.fire(remote, payload)
	end
end

-- ------------------------------------------------------------------ aim (D-112)

-- The locked enemy's position, or nil with no lock (TargetController drops a dead or gone lock).
local function lockPosition(): Vector3?
	local record = Siblings.call(TargetController, "current")
	if record == nil or record.model == nil then
		return nil
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

-- Degrees (+ = left) from the root's look to the lock, or nil (no lock, or standing on it).
local function lockBearing(rootPart: BasePart, lockAt: Vector3): number?
	local frame = rootPart.CFrame
	local look, origin = frame.LookVector, frame.Position
	return AimLogic.bearingTo(look.X, look.Z, origin.X, origin.Z, lockAt.X, lockAt.Z, AIM.minFaceDistance)
end

-- The snap a basic swing or an Art release makes before it reads its facing: the rest of the way
-- to the lock, or with no lock to the soft assist's pick, by at most aim.snapDegrees and never out
-- of what the server can accept from a root it saw up to combat.lagAllowance ago. Returns the
-- facing the request carries: the body's look, or mid-turn the nearest look to it the server can
-- accept (AimLogic.sendOffset).
local function aimForRequest(): { number }
	local rootPart = root
	if rootPart == nil then
		return facingTable()
	end
	local t = now()
	recordYaw(rootPart, t)
	local delta: number? = nil
	local lockAt = lockPosition()
	if lockAt ~= nil then
		delta = lockBearing(rootPart, lockAt)
	else
		local frame = rootPart.CFrame
		local candidates = Siblings.call(TargetController, "assistCandidates", frame.Position, frame.LookVector)
		local pick = if candidates ~= nil then AimLogic.assistPick(candidates, AIM) else nil
		delta = if pick ~= nil then pick.bearing else nil
	end
	if delta ~= nil then
		local lo, hi = AimLogic.range(yawHistory)
		local turn = AimLogic.requestTurn(delta, lo, hi, AIM)
		if turn ~= 0 then
			yawRoot(rootPart, turn)
			recordYaw(rootPart, t)
		end
	end
	local lo, hi = AimLogic.range(yawHistory)
	local offset = AimLogic.sendOffset(lo, hi, AIM)
	local look = (CFrame.Angles(0, math.rad(offset), 0) * rootPart.CFrame.Rotation).LookVector
	return { look.X, look.Y, look.Z }
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

local function setTimeScale(scale: number)
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
	setTimeScale(timeScale)
	stopClip(current.handle)
	-- The wind-up contour ends with the hold, however it ended.
	Impact.cancelActivation(character)
	if character ~= nil then
		Trails.activationLight(character, false, trailToken())
	end
end

--- Freezes the held Art clip at its activation hold (the glowing stance).
function CharacterController.freezeHold()
	if hold == nil or animator == nil then
		return
	end
	local current = hold :: Hold
	if current.frozenClipTime ~= nil then
		return
	end
	current.frozenClipTime = math.max(now() - current.pressedAt, 0)
	setTimeScale(0)
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
	task.delay(Combat.startPoseTime + Combat.activationHold, function()
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
	setState("Art")
	-- The server's Idle normally ends the Art; this is the fallback if that state never arrives.
	actionEndsAt = ActionLogic.artFallbackEnd(releasedAt, plan.freezeClipTime, current.art, Combat.lagAllowance)
	predictDraw()
	fire("ArtRequest", { artId = current.art.id, facing = aimForRequest(), clientTime = serverNow() })
	task.delay(plan.freezeClipTime, function()
		if predicted ~= nil and (predicted :: Predicted).token == launchToken then
			setTimeScale(timeScale)
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
	setState("Basic")
	actionEndsAt = t + Combat.basicHitDuration
	predictDraw()
	fire("BasicAttackRequest", { facing = aimForRequest(), clientTime = serverNow() })
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
	-- The stick, not the Humanoid: the two-step stop keeps moving the Humanoid along the last move
	-- after the stick lets go, and a dodge with no input steps back.
	local stick = if stopCarry.active then Vector3.zero else (humanoid :: Humanoid).MoveDirection
	local moveLocal = rootPart.CFrame:VectorToObjectSpace(stick)
	local direction = ActionLogic.dodgeDirection(moveLocal.X, moveLocal.Z, InputData.dodge.inputDeadzone)
	local look = rootPart.CFrame.LookVector
	local right = rootPart.CFrame.RightVector
	local world = if direction == "Forward"
		then look
		elseif direction == "Back" then -look
		elseif direction == "Left" then -right
		else right
	local clipId = playerClip("Dodge" .. direction)
	local dodgeToken = nextToken()
	predicted = {
		action = "Dodge",
		clipId = clipId or "",
		handle = if clipId ~= nil then animator:play(clipId) else nil,
		token = dodgeToken,
	}
	setState("Dodge")
	actionEndsAt = t + Combat.dodgeDuration
	dodgeReadyAt = t + Combat.dodgeCooldown
	CameraController.fovKick("Dash")
	if character ~= nil then
		-- The speed lines on this screen and the dodge whoosh for anyone near.
		Impact.dodge(character :: Model, true)
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
	setTimeScale(timeScale)
	stopClip(current.handle)
	if character ~= nil and expected == "Art" then
		Trails.activationLight(character, false, trailToken())
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
	setTimeScale(timeScale)
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
	if faceLock and lockAt ~= nil then
		local delta = lockBearing(rootPart, lockAt)
		if delta ~= nil then
			yawRoot(rootPart, AimLogic.turnStep(delta, AIM.lockTurnRate, dt))
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
	local carrySpeed = ActionLogic.stopCarryStep(
		stopCarry,
		moveDir.X,
		moveDir.Z,
		speed,
		walkSpeed,
		grounded,
		state,
		dt,
		STOP_CARRY,
		gait
	)
	local targetSpeed = if carrySpeed > 0 then carrySpeed else walkSpeed
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

	if locomotion ~= nil and state ~= "Dead" then
		locomotion:update(dt, {
			moveDir = moveDir,
			speed = speed,
			sprinting = sprinting and not locked and not faceLock,
			grounded = grounded,
			drawn = drawn,
			turning = turning,
			fallHeight = fallHeight,
			verticalVelocity = velocity.Y,
		})
	end

	if ActionLogic.rootMotionActive(state) then
		local delta = animator:currentRootMotionDelta()
		if typeof(delta) == "Vector3" and delta.Magnitude > 0 then
			rootPart.CFrame = rootPart.CFrame * CFrame.new(delta)
		end
	end
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
	Siblings.call(Choreo, "setLocalModel", nil)
	character, humanoid, root, animator, locomotion = nil, nil, nil, nil, nil
	predicted = nil
	actionEndsAt = nil
	lastWalkSpeed = nil
	lastAutoRotate = nil
	yawHistory = AimLogic.newHistory()
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
	-- The local rig is always stepped at full rate (root motion is read every RenderStepped).
	Siblings.call(Choreo, "setLocalModel", model)
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
	Replication.clipEvent:Connect(function(record: any, clipId: string, event: any)
		if hold == nil or character == nil or record.model ~= character then
			return
		end
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

	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Character.Value + 1, step)
	-- The yaw history is kept on Heartbeat too, which runs while the display sleeps (RenderStepped
	-- does not): a turn made outside the render step (the dev aim hook's face, the engine's own) is
	-- timed when it happens, not taken for a turn made just before the next swing (D-112).
	RunService.Heartbeat:Connect(function()
		local rootPart = root
		if rootPart ~= nil then
			recordYaw(rootPart, now())
		end
	end)
end

return CharacterController
