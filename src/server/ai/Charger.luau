--!strict
--[[
	Charger (section 9): the Frenzy Boar. A straight-line rusher that turns slowly.

	Chase: the body always runs forward along its facing while the facing turns toward the target
	at the Charger's (slow) turn rate, so the path is a wide arc: the boar circles to get a straight
	line. Too close to crouch (inside minChargeDistance) it bends outward along the tangent until it
	is circleDistance away. When the target sits inside the charge band and within the line-up
	tolerance of the facing, it crouches: the 0.6 s wind-up with the red line on the ground (the
	attack def's telegraph kind and ground shape). The crouch holds the line (turn rate 0).

	Strike: the rush. At the end of the wind-up the body runs along the line at `AI.rushSpeed`
	(at least chargeSpeed, and fast enough to reach the end of the telegraphed line as the hit
	resolves) for reach + overshoot studs. The overshoot carries it past the target; the recovery
	is the skid and the slow turn back.

	The rush hits on contact (D-166): the line is the one the telegraph drew (from the crouch point,
	its reach and width), and it resolves in stretches on the server's clock, not the body's. At the
	launch the body's own length resolves (from its back to its snout, bodyExtents); every server
	frame after it (the frame pass, D-184) resolves the stretch the body swept since the last one, from
	where its back was to where its snout is now (speed * elapsed + front), so each target is hit on
	the first frame the snout reaches it, once, and the whole line has been swept by `attack.strike`,
	never later. That clock starts on the launch beat (the wind-up's own end, which the clients
	predict from the telegraph), not on the frame up to a frame later that starts the body (D-182);
	the body's run, its jam check and its end, counts from that frame (Rush.bodyStartedAt). A target
	the line never reaches (beyond its end, beside it, or stepping in behind the body that already
	passed) is never hit, and a body jammed against something still hits on the clock. Dodge, guard
	and parry are judged per target at its own contact (CombatService.enemyStrike's options).

	The run is the strike's own movement (D-183): it goes straight at the line's end (moveDirect),
	never along a path, so a body that stood still before the launch never walks back to where a
	late path began.

	The launch and an early stop go to EnemyService (rushStarted / rushEnded, D-169): it switches the
	body's collision group so the rush passes through players and other enemies (D-167), and tells
	the clients so they draw the rush on the server's timeline. A body that falls more than
	jamLagStuds behind that timeline reports "Jammed" (the clients stop drawing it ahead of the
	body) and stops where it is (D-190); an interrupt, a death or a sleep reports why it stopped.
	EnemyService puts every stopped body back in the enemies group only once it has stayed clear of
	every player and enemy for longer than the clients draw it late.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local AI = require(Shared.data.ai)
local Brain = require(script.Parent.Brain)

local tuning: AI.ChargerTuning = AI.archetypes.Charger

local Charger: Brain.Archetype = {
	name = "Charger",
} :: any

--- A rush attack: a line on the ground (arc 0).
local function isRush(attack: Types.EnemyAttackDef): boolean
	return attack.arc == 0 or attack.groundShape == "Line"
end

--- A new chase starts outside the circle-out rule.
function Charger.onChaseStart(brain: Brain.Brain)
	brain.memory.tooClose = false
	brain.memory.rushing = false
	brain.memory.rush = nil
end

-- How far down the line the body stands now, clamped to the run.
local function progressOf(brain: Brain.Brain, rush: Brain.Rush): number
	return math.clamp((brain:position() - rush.origin):Dot(rush.direction), 0, rush.length)
end

-- Resolves the stretch of the line the body swept since the last sweep, up to `elapsed` seconds
-- into the rush (never past the attack's strike beat): from where its back was then to where its
-- snout is now, on the rush's clock.
local function sweep(brain: Brain.Brain, rush: Brain.Rush, elapsed: number)
	local attack = brain:currentAttack()
	if attack == nil then
		return
	end
	local memory = brain.memory
	local upTo = math.clamp(elapsed, 0, attack.strike)
	local last: number? = memory.rushSwept
	if last ~= nil and upTo <= last then
		return
	end
	local front, back = brain:bodyExtents()
	memory.rushSwept = upTo
	brain:strikeStretch(
		rush.origin,
		rush.direction,
		rush.speed * (last or 0) - back,
		rush.speed * upTo + front,
		memory.rushHit
	)
end

--- True while the strike in progress is a rush: it resolves by contact (D-166).
function Charger.contactStrike(brain: Brain.Brain): boolean
	return brain.memory.rush ~= nil
end

--- The rush stopped early: an interrupt, a death or a sleep.
function Charger.onCancel(brain: Brain.Brain, reason: Types.RushEndReason)
	local memory = brain.memory
	local rush: Brain.Rush? = memory.rush
	memory.rush = nil
	if memory.rushing == true and rush ~= nil then
		memory.rushing = false
		brain:rushEnded(rush, reason, progressOf(brain, rush))
	end
end

--- Runs forward along the facing while turning toward the target (the wide arc); bends outward
--- when too close; crouches when lined up inside the charge band.
function Charger.chase(brain: Brain.Brain, dt: number, target: Brain.Target): Types.EnemyAttackDef?
	local memory = brain.memory
	if target.distance < tuning.minChargeDistance then
		memory.tooClose = true
	elseif target.distance >= tuning.circleDistance then
		memory.tooClose = false
	end

	local desired = target.direction
	if memory.tooClose == true then
		local facing = brain:getFacing()
		local left = Brain.rotateY(target.direction, 90)
		local right = Brain.rotateY(target.direction, -90)
		local tangent = if left:Dot(facing) >= right:Dot(facing) then left else right
		desired = Brain.horizontal(tangent - target.direction * tuning.circleOutwardBias) or tangent
	end
	-- Wheeling: looking for a line while well off the target, it slows into the turn so the turning
	-- circle tightens. The circle-out runs at full speed; it is the loop the player sees.
	local speed = brain:speed()
	if memory.tooClose ~= true and brain:angleTo(target.direction) > tuning.wheelAngle then
		speed *= tuning.wheelSpeedMultiplier
	end
	brain:turnToward(desired, tuning.turnRate, dt)
	brain:moveForward(speed)
	return brain:pickAttack(target)
end

--- A rush needs the target inside the charge band and on the line (the tolerance widens after
--- lineUpTimeout seconds of chasing); any other attack (an Elite's Trample) needs the target under
--- the body and inside its arc.
function Charger.canUse(brain: Brain.Brain, attack: Types.EnemyAttackDef, target: Brain.Target): boolean
	if isRush(attack) then
		if target.distance < tuning.minChargeDistance or target.distance > tuning.maxChargeDistance then
			return false
		end
		local tolerance = tuning.lineUpToleranceDegrees
		if brain:chaseElapsed() >= tuning.lineUpTimeout then
			tolerance = tuning.lineUpLooseToleranceDegrees
		end
		return brain:angleTo(target.direction) <= tolerance
	end
	if target.distance > attack.reach * tuning.engageFraction then
		return false
	end
	return attack.arc >= 360 or brain:angleTo(target.direction) <= attack.arc / 2
end

--- The crouch holds its line: the Charger's wind-up turn rate is zero, so nothing moves.
function Charger.onWindUp(brain: Brain.Brain, dt: number, target: Brain.Target?)
	if target ~= nil and tuning.windUpTurnRate > 0 then
		brain:turnToward(target.direction, tuning.windUpTurnRate, dt)
	end
end

--- The launch: fixes the line from the crouch point along the facing, starts the rush and resolves
--- the body where it crouched (the launch's own stretch, D-166).
function Charger.onStrikeStart(brain: Brain.Brain, _target: Brain.Target?)
	local attack = brain:currentAttack()
	local memory = brain.memory
	memory.rush = nil
	memory.rushing = false
	if attack == nil or not isRush(attack) then
		return
	end
	local length = attack.reach + tuning.overshoot
	local speed = AI.rushSpeed(attack)
	local rush: Brain.Rush = {
		attackId = attack.id,
		startedAt = brain.phaseStart,
		bodyStartedAt = brain:now(),
		origin = brain:position(),
		direction = brain:getFacing(),
		speed = speed,
		length = length,
		duration = length / speed,
	}
	memory.rush = rush
	memory.rushing = true
	memory.rushJammed = false
	memory.rushSwept = nil
	memory.rushHit = {}
	brain:moveDirect(rush.origin + rush.direction * length, speed)
	brain:rushStarted(rush)
	sweep(brain, rush, rush.bodyStartedAt - rush.startedAt)
end

--- A rush resolves from the crouch point along the line (what the telegraph drew); anything else
--- from the body as it stands.
function Charger.strikeFrame(brain: Brain.Brain): (Vector3, Vector3)
	local rush: Brain.Rush? = brain.memory.rush
	if rush ~= nil then
		return rush.origin, rush.direction
	end
	return brain:position(), brain:getFacing()
end

--- Keeps the rush going and resolves what the body swept since the last pass (every server frame,
--- D-184); it is over when its time has run, so the skid starts on the clip's beat. A body that fell
--- jamLagStuds behind the clock (a wall, a ledge) stops there and waits out the time (D-190). The line resolves on the
--- launch beat's clock (startedAt, what the clients draw); the body's own run (its jam check and its
--- end) on the frame it started (bodyStartedAt), so a launch noticed up to a frame late neither cuts
--- the run short nor reads as a jam.
function Charger.onStrike(brain: Brain.Brain, _dt: number, _phaseElapsed: number): boolean
	local memory = brain.memory
	local rush: Brain.Rush? = memory.rush
	if rush == nil then
		return true
	end
	local now = brain:now()
	sweep(brain, rush, now - rush.startedAt)
	if brain:getPhase() ~= "Strike" or memory.rushing ~= true then
		return true -- a parry on contact interrupted it (onCancel stopped the run)
	end
	local progress = progressOf(brain, rush)
	local ran = now - rush.bodyStartedAt
	if ran >= rush.duration then
		memory.rushing = false
		brain:rushEnded(rush, "Done", progress)
		return true
	end
	if memory.rushJammed ~= true and rush.speed * ran - progress > tuning.jamLagStuds then
		-- The hits stay on the clock and the clients stop drawing it ahead; the body stops where it
		-- jammed (D-190): sent on, it ran past its clock's end still at full speed, and turned solid
		-- in the middle of the player it had just run through.
		memory.rushJammed = true
		brain:rushEnded(rush, "Jammed", progress)
		brain.context.stop()
	end
	if memory.rushJammed ~= true then
		brain:moveDirect(rush.origin + rush.direction * rush.length, rush.speed)
	end
	return false
end

--- The skid and the slow turn back toward the target.
function Charger.onRecover(brain: Brain.Brain, dt: number, target: Brain.Target?)
	brain.memory.rushing = false
	brain.memory.rush = nil
	if target ~= nil then
		brain:turnToward(target.direction, tuning.recoverTurnRate, dt)
	end
end

return Charger
