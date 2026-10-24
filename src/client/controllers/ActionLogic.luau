--!strict
--[[
	ActionLogic: the pure decisions under CharacterController (section 6 inputs, section 17
	prediction). Which Art a key picks, when an action may start, how the local state follows the
	server's, when root motion applies, how the held start pose stays in sync with the server's
	clip clock. No Roblox types, no engine calls, so every rule is tested in Lune.

	The hold rule (Art key held, then released): the clip starts on press and freezes at the
	activation hold; the server starts its own copy at the release. The local clip therefore
	stays frozen for exactly the clip time it had reached, then resumes in step with the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.types)

export type LocalState =
	"Idle"
	| "Holding"
	| "Art"
	| "PostMotion"
	| "Basic"
	| "Guard"
	| "Dodge"
	| "Stagger"
	| "GuardBroken"
	| "Dead"

export type Action = "Art" | "Basic" | "Guard" | "Dodge"
export type Stance = { moving: boolean, airborne: boolean, afterParry: boolean }
export type Direction = "Forward" | "Back" | "Left" | "Right"
export type Reconcile = "None" | "EndAction" | "Stagger" | "GuardBroken" | "Break" | "Die"
export type Speeds = { walk: number, run: number, sprint: number }
export type FallTracker = { airborneSince: number?, peakY: number }
export type SyncPlan = { freezeClipTime: number, resumeAt: number }
-- The two-step stop's carry (ActionLogic.stopCarryStep).
export type StopCarry = {
	active: boolean,
	moving: boolean, -- the stick asked for a move last frame
	x: number, -- the last move direction (horizontal, unit)
	z: number,
	from: number, -- studs per second the carry started at
	elapsed: number, -- seconds since it started
	phase: number, -- the gait phase last frame
	total: number, -- cycles of the gait phase from the release to the settle point
	left: number, -- cycles of it still to go
}
export type StopCarryConfig = {
	seconds: number, -- choreo locomotion.stopStepsSeconds: the longest a carry runs
	minCycles: number, -- locomotion.stopMinCycles: the least gait phase before the Footstep that settles
	endSpeed: number, -- locomotion.stopEndSpeed: the slowest it gets before it ends
	minSpeed: number, -- locomotion.idleSpeedThreshold: slower than this is standing
	maxSpeed: number, -- locomotion.skidSpeedThreshold: faster stops are the Skid clip's
}
-- The gait as the carry reads it (Locomotion.stopGait): the shared phase and, for each foot, the
-- shared phase of the walk's Footstep and the cycles after it at which the foot is over its Idle
-- spot.
export type StopGait = { phase: number, leftStep: number, leftAfter: number, rightStep: number, rightAfter: number }

local ActionLogic = {}

-- Local states from which each action may start; the server has the final say.
local STARTABLE: { [Action]: { [LocalState]: boolean } } = {
	Art = { Idle = true, Basic = true },
	Basic = { Idle = true, Basic = true },
	Guard = { Idle = true, Basic = true },
	Dodge = { Idle = true, Guard = true, Basic = true, Holding = true },
}

local MOVEMENT_LOCKED: { [LocalState]: boolean } = {
	Holding = true,
	Art = true,
	PostMotion = true,
	Basic = true,
	Dodge = true,
	Stagger = true,
	GuardBroken = true,
	Dead = true,
}

local ROOT_MOTION: { [LocalState]: boolean } = {
	Art = true,
	Dodge = true,
	Basic = true,
}

--- "Launch" when the key was released inside the cancel time, "Cancel" past it.
function ActionLogic.holdOutcome(heldSeconds: number, cancelTime: number): "Launch" | "Cancel"
	return if heldSeconds <= cancelTime then "Launch" else "Cancel"
end

--- Whether an action may start from the current local state (and, for dodges, off cooldown).
function ActionLogic.canStart(state: LocalState, action: Action, now: number, dodgeReadyAt: number): (boolean, string?)
	local allowed = STARTABLE[action]
	if allowed == nil or not allowed[state] then
		return false, "state:" .. state
	end
	if action == "Dodge" and now < dodgeReadyAt then
		return false, "cooldown"
	end
	return true, nil
end

--- The preconditions a stance satisfies (Airborne beats Moving beats Standing; AfterParry adds).
function ActionLogic.stances(stance: Stance): { Types.Precondition }
	local list: { Types.Precondition } = {}
	if stance.airborne then
		table.insert(list, "Airborne")
	elseif stance.moving then
		table.insert(list, "Moving")
	else
		table.insert(list, "Standing")
	end
	if stance.afterParry then
		table.insert(list, "AfterParry")
	end
	return list
end

--- True when the Art has no preconditions or one of them matches the stance.
function ActionLogic.allowed(art: Types.ArtDef, stance: Stance): boolean
	local preconditions = art.preconditions
	if preconditions == nil or #preconditions == 0 then
		return true
	end
	for _, satisfied in ActionLogic.stances(stance) do
		if table.find(preconditions, satisfied) then
			return true
		end
	end
	return false
end

--- The Art a slot key launches from this stance: the slot's Art when its preconditions fit,
--- otherwise the first other equipped Art whose preconditions fit, otherwise nil.
function ActionLogic.pickArt(
	slots: { [number]: Types.ArtDef },
	slotIndex: number,
	slotCount: number,
	stance: Stance
): Types.ArtDef?
	local chosen = slots[slotIndex]
	if chosen ~= nil and ActionLogic.allowed(chosen, stance) then
		return chosen
	end
	for index = 1, slotCount do
		local art = slots[index]
		if index ~= slotIndex and art ~= nil and ActionLogic.allowed(art, stance) then
			return art
		end
	end
	return nil
end

--- Maps quick-slot Art ids to definitions, dropping unknown Arts and Arts without a clip.
function ActionLogic.slotArts(
	ids: { string },
	byId: (string) -> Types.ArtDef?,
	hasClip: (string) -> boolean,
	slotCount: number
): { [number]: Types.ArtDef }
	local slots: { [number]: Types.ArtDef } = {}
	for index = 1, math.min(#ids, slotCount) do
		local art = byId(ids[index])
		if art ~= nil and hasClip(art.clip) then
			slots[index] = art
		end
	end
	return slots
end

--- Dodge direction from the move input in the rig's local frame (-Z forward, +X right).
function ActionLogic.dodgeDirection(localX: number, localZ: number, deadzone: number): Direction
	if math.sqrt(localX * localX + localZ * localZ) < deadzone then
		return "Back"
	end
	if math.abs(localX) > math.abs(localZ) then
		return if localX > 0 then "Right" else "Left"
	end
	return if localZ < 0 then "Forward" else "Back"
end

--- True when a basic attack may go out: at least `minInterval` seconds since the last one sent.
--- The controller passes the BasicAttackRequest refill interval (1 / world.luau perSecond), so
--- a player mashing the button never outruns the server's rate limit (section 17).
function ActionLogic.basicReady(lastTime: number, now: number, minInterval: number): boolean
	return now - lastTime >= minInterval
end

--- The next basic-attack chain index: continues inside the window, otherwise restarts at 1.
function ActionLogic.nextBasic(
	chainIndex: number,
	lastTime: number,
	now: number,
	window: number,
	length: number
): number
	if chainIndex <= 0 or chainIndex >= length or now - lastTime > window then
		return 1
	end
	return chainIndex + 1
end

--- Clip id for a rig: players use their weapon category, enemies their rig id (ARCHITECTURE "Clips").
function ActionLogic.clipId(kind: Types.EntityKind, rig: string, weaponCategory: string, name: string): string
	if kind == "Player" then
		return "player/" .. weaponCategory .. "/" .. name
	end
	return "enemy/" .. rig .. "/" .. name
end

--- What the local fighter does when the server's State attribute changes (Replication plays the
--- reaction clips for every rig; this only moves the local state machine).
function ActionLogic.reconcile(localState: LocalState, serverState: string): Reconcile
	if serverState == "Dead" then
		return "Die"
	elseif serverState == "Stagger" then
		return "Stagger"
	elseif serverState == "GuardBroken" then
		return "GuardBroken"
	elseif serverState == "Break" then
		return "Break"
	elseif serverState == "Idle" or serverState == "Moving" then
		if
			localState == "Art"
			or localState == "PostMotion"
			or localState == "Stagger"
			or localState == "GuardBroken"
			or localState == "Dead"
		then
			return "EndAction"
		end
	end
	return "None"
end

--- True while Humanoid movement input must be ignored (WalkSpeed 0).
function ActionLogic.movementLocked(state: LocalState): boolean
	return MOVEMENT_LOCKED[state] == true
end

--- True while the clip's root motion carries the body.
function ActionLogic.rootMotionActive(state: LocalState): boolean
	return ROOT_MOTION[state] == true
end

--- The Humanoid speed for a state: 0 while locked, sprint while sprinting, walk while guarding.
function ActionLogic.speedFor(state: LocalState, sprinting: boolean, speeds: Speeds): number
	if ActionLogic.movementLocked(state) then
		return 0
	end
	if state == "Guard" then
		return speeds.walk
	end
	return if sprinting then speeds.sprint else speeds.run
end

local function firstNumber(table_: any, names: { string }): number?
	if typeof(table_) ~= "table" then
		return nil
	end
	for _, name in names do
		local value = table_[name]
		if typeof(value) == "number" then
			return value
		end
	end
	return nil
end

--- Locomotion speeds from choreo.luau (locomotion.walkSpeed / speeds.walk / walkSpeed shapes),
--- falling back per field to `fallback` when the table does not carry one.
function ActionLogic.resolveSpeeds(choreoData: any, fallback: Speeds): Speeds
	local sources: { any } = {}
	if typeof(choreoData) == "table" then
		table.insert(sources, choreoData.locomotion)
		table.insert(sources, choreoData.speeds)
		table.insert(sources, choreoData)
	end
	local function resolve(names: { string }, default: number): number
		for _, source in sources do
			local value = firstNumber(source, names)
			if value ~= nil then
				return value
			end
		end
		return default
	end
	return {
		walk = resolve({ "walkSpeed", "walk" }, fallback.walk),
		run = resolve({ "runSpeed", "run" }, fallback.run),
		sprint = resolve({ "sprintSpeed", "sprint" }, fallback.sprint),
	}
end

--- Whether the local fighter's sword should be drawn: the server's Drawn attribute, or a combat
--- request this client sent in the last `predictSeconds` (until the attribute lands).
function ActionLogic.drawnTarget(
	attributeDrawn: boolean,
	lastPredictAt: number?,
	now: number,
	predictSeconds: number
): boolean
	return attributeDrawn or (lastPredictAt ~= nil and now - lastPredictAt <= predictSeconds)
end

--- Signed angle in degrees (positive = to the left) from the rig's look direction to the move
--- direction it wants to face; 0 when there is no move input. Locomotion turns in place past
--- choreo.locomotion.turnInPlaceDegrees.
function ActionLogic.turnAngle(lookX: number, lookZ: number, moveX: number, moveZ: number): number
	if moveX == 0 and moveZ == 0 then
		return 0
	end
	local cross = lookZ * moveX - lookX * moveZ
	local dot = lookX * moveX + lookZ * moveZ
	return math.deg(math.atan2(cross, dot))
end

--- The latest the predicted Art may hold the body when the server's state never arrives: the
--- clip resumes after `freezeClipTime`, runs to its last hit, holds the post-motion, plus `slack`.
function ActionLogic.artFallbackEnd(
	releasedAt: number,
	freezeClipTime: number,
	art: Types.ArtDef,
	slack: number
): number
	return releasedAt + freezeClipTime + art.total + art.postMotion + slack
end

--- Tracks airborne height; returns the fall height on the frame the rig lands, nil otherwise.
function ActionLogic.fallStep(tracker: FallTracker, grounded: boolean, y: number, now: number): number?
	if not grounded then
		if tracker.airborneSince == nil then
			tracker.airborneSince = now
			tracker.peakY = y
		else
			tracker.peakY = math.max(tracker.peakY, y)
		end
		return nil
	end
	if tracker.airborneSince ~= nil then
		local height = math.max(tracker.peakY - y, 0)
		tracker.airborneSince = nil
		return height
	end
	return nil
end

--- A carry that is not running.
function ActionLogic.newStopCarry(): StopCarry
	return {
		active = false,
		moving = false,
		x = 0,
		z = -1,
		from = 0,
		elapsed = 0,
		phase = 0,
		total = 0,
		left = 0,
	}
end

-- Cycles of the gait phase from `phase` to `target`, at least `least`.
local function cyclesTo(phase: number, target: number, least: number): number
	local cycles = (target - phase) % 1
	if cycles < least then
		cycles += math.ceil(least - cycles)
	end
	return cycles
end

--- The two-step stop below the skid threshold. On the frame the stick lets go, a grounded fighter
--- that is free to move (Idle or Guard) and was moving keeps going along its last move direction
--- and slows down as the gait walks on: through the next Footstep at least `config.minCycles` of
--- the phase away, to where that foot is over its Idle spot (`gait`, Locomotion.stopGait), its
--- speed falling with the phase still to go (never below `config.endSpeed`). There it stops, so
--- the feet step the body to a stop and hand over to Idle where Idle has them, instead of the body
--- stopping dead under walking legs. It starts at the speed the fighter had and never goes above
--- `walkSpeed` (the Humanoid's speed for the state, which a Guard mid-carry lowers). Above
--- config.maxSpeed no carry starts: the Skid clip owns that stop. Any input, another state, leaving
--- the ground or `config.seconds` ends it; with no gait (no animator) the speed just falls to zero
--- over `config.seconds`. `moveX`, `moveZ` are the stick's world move direction, `speed` the
--- root's horizontal speed. Returns this frame's carry speed (0 when there is none); the direction
--- is (carry.x, carry.z).
function ActionLogic.stopCarryStep(
	carry: StopCarry,
	moveX: number,
	moveZ: number,
	speed: number,
	walkSpeed: number,
	grounded: boolean,
	state: LocalState,
	dt: number,
	config: StopCarryConfig,
	gait: StopGait?
): number
	local length = math.sqrt(moveX * moveX + moveZ * moveZ)
	if length > 1e-6 then
		carry.x, carry.z = moveX / length, moveZ / length
		carry.active = false
		carry.moving = true
		return 0
	end
	local wasMoving = carry.moving
	carry.moving = false
	if not grounded or (state ~= "Idle" and state ~= "Guard") then
		carry.active = false
		return 0
	end
	if not carry.active then
		if not wasMoving or speed <= config.minSpeed or speed > config.maxSpeed then
			return 0
		end
		carry.active = true
		carry.from = math.min(speed, walkSpeed)
		carry.elapsed = 0
		carry.total = if gait ~= nil
			then math.min(
				cyclesTo(gait.phase, gait.leftStep, config.minCycles) + gait.leftAfter,
				cyclesTo(gait.phase, gait.rightStep, config.minCycles) + gait.rightAfter
			)
			else 1
		carry.left = carry.total
	elseif gait ~= nil then
		carry.left -= (gait.phase - carry.phase) % 1
	end
	carry.elapsed += dt
	if gait ~= nil then
		carry.phase = gait.phase
	else
		carry.left = 1 - carry.elapsed / config.seconds
	end
	if carry.left <= 0 or carry.elapsed >= config.seconds then
		carry.active = false
		return 0
	end
	local slowing = carry.from * carry.left / carry.total
	if gait ~= nil then
		slowing = math.max(config.endSpeed, slowing)
	end
	return math.min(carry.from, slowing, walkSpeed)
end

--- The clip time of an Art clip's hold pose: its first ActivationHold, or `fallback` (the section 6
--- time, combat.luau startPoseTime + activationHold) when that comes first or the clip has none,
--- since the hold freezes at whichever comes first. Nil for a clip that is not clip data.
function ActionLogic.holdClipTime(clip: any, fallback: number): number?
	if typeof(clip) ~= "table" or typeof(clip.events) ~= "table" then
		return nil
	end
	local at = fallback
	for _, event in clip.events do
		if typeof(event) == "table" and event.kind == "ActivationHold" and typeof(event.time) == "number" then
			at = math.min(at, event.time)
		end
	end
	return at
end

--- The clip time the held Art freezes at, and whether the clip must be moved there first. Normally
--- the rig's own steps took the clip there: it freezes where it is, at the time the key has been
--- down. After a render stall (D-138) the rig was last stepped (`steppedAt`; nil, never) before the
--- clip could reach its hold pose (`holdAt`, nil when it has no clip clock) and still shows an
--- earlier pose: it freezes at the hold pose, moved there (true).
function ActionLogic.freezeAt(pressedAt: number, now: number, holdAt: number?, steppedAt: number?): (number, boolean)
	local held = math.max(now - pressedAt, 0)
	if holdAt ~= nil and held >= holdAt and (steppedAt == nil or steppedAt < pressedAt + holdAt) then
		return holdAt, true
	end
	return held, false
end

--- Whether the local rig sleeps (D-141): a frame went by with no render step. In a frame the
--- render step comes before Heartbeat, so a press in the display's light has seen one Heartbeat
--- since the rig last stepped; a second means a whole frame ran (Heartbeat goes on while the
--- display sleeps) and nothing on screen moved.
function ActionLogic.rigAsleep(heartbeatsSinceStep: number): boolean
	return heartbeatsSinceStep > 1
end

--- What a dodge pressed while the rig slept does at the wake's step (D-141): a press no older
--- than `jumpSeconds` shows the whole dodge from the wake ("Show"); an older one lies in the time
--- the stall skipped, like the events it crossed, and shows nothing ("Drop"). The server ran its
--- dodge from the request either way.
function ActionLogic.wokenDodge(pressedAt: number, now: number, jumpSeconds: number): "Show" | "Drop"
	return if now - pressedAt <= jumpSeconds then "Show" else "Drop"
end

--- When the local clip resumes after a release so its clock matches the server's, which starts
--- the clip at the release: the clip stays frozen for the clip time it had reached.
function ActionLogic.syncPlan(pressedAt: number, frozenClipTime: number?, releasedAt: number): SyncPlan
	local freezeClipTime = if frozenClipTime ~= nil then frozenClipTime else releasedAt - pressedAt
	freezeClipTime = math.max(freezeClipTime, 0)
	return { freezeClipTime = freezeClipTime, resumeAt = releasedAt + freezeClipTime }
end

--- The local state an action puts the fighter in.
function ActionLogic.stateForAction(action: Action): LocalState
	if action == "Art" then
		return "Art"
	elseif action == "Basic" then
		return "Basic"
	elseif action == "Guard" then
		return "Guard"
	end
	return "Dodge"
end

return ActionLogic
