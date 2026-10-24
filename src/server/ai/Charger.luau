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
	passed) is never hit. Dodge, guard and parry are judged per target at its own contact
	(CombatService.enemyStrike's options).

	A charge only hits what it reaches (D-195): the line never resolves further ahead of the body's
	own snout than the run the body started late (speed * (bodyStartedAt - startedAt)) plus
	keepUpStuds, more than a free-running body trails its own run by, so a free run resolves exactly
	on the clock while a body held back by a wall stops the line within keepUpStuds (and that late
	start) of its snout, long before the jam is told. Once the rush reports "Jammed" the line is
	over: nothing past the body's front at the jam is hit, nor anyone who walks into the stopped body
	afterwards. A stretch starts where the last one ended when that is behind the clock's back, so a
	body that falls behind and catches up leaves no gap.

	Nor past a wall (D-197): only the root collides (RigBuilder), so a body held at a wall still has
	its snout front - the root's half length beyond the wall's face, and the late start and
	keepUpStuds reach further still. Every stretch stops where the world stops the root, cast ahead
	of it along the line in the root's own group (the rushing group meets the world only), so nobody
	behind a wall is hit, while a free run's line, with nothing in the way, resolves on the clock.

	The run is the strike's own movement (D-183): it goes straight at the line's end (moveDirect),
	never along a path, so a body that stood still before the launch never walks back to where a
	late path began.

	The launch and an early stop go to EnemyService (rushStarted / rushEnded, D-169): it switches the
	body's collision group so the rush passes through players and other enemies (D-167), and tells
	the clients so they draw the rush on the server's timeline. A stretch the world caps (the cast
	above) ends the rush on that frame (D-202): it reports "Jammed" with where the root will stand,
	its own reach short of the face, before the body gets there, and the body runs there and no
	further (D-190). A body that falls more than jamLagStuds behind that timeline for a reason the
	cast does not see reports "Jammed" too (the clients stop drawing it ahead of the body) and stops
	where it is; an interrupt, a death or a sleep reports why it stopped.
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

-- The world stops the root ahead (the cast saw a face `face` studs down the line, D-202): the rush is
-- over at once. It is reported Jammed with where the root will stand, its own reach short of the
-- face, and the body is sent there and no further (D-190); the rejoin wait follows as for any stop.
-- A rush a parry on this stretch already interrupted, or one already over, is left alone.
local function stopAtWall(brain: Brain.Brain, rush: Brain.Rush, face: number)
	local memory = brain.memory
	if memory.rushing ~= true or memory.rushJammed == true or brain:getPhase() ~= "Strike" then
		return
	end
	memory.rushJammed = true
	local progress = progressOf(brain, rush)
	local stop = math.clamp(face - brain:rootReach(rush.direction), progress, rush.length)
	brain:rushEnded(rush, "Jammed", stop)
	if stop > progress then
		brain:moveDirect(rush.origin + rush.direction * stop, rush.speed)
	else
		brain.context.stop()
	end
end

-- Resolves the stretch of the line the body swept since the last sweep, up to `elapsed` seconds
-- into the rush (never past the attack's strike beat): from where its back was then to where its
-- snout is now, on the rush's clock, but never further ahead of the body's own snout than its late
-- start plus keepUpStuds (D-195), never past the world that stops its root (D-197), and never again
-- once the rush jammed. A stretch a wall caps ends the rush there at once (stopAtWall, D-202);
-- ground the root climbs (a ramp's face, D-204) caps the stretch the same way, since whatever
-- stands behind it is unseen, but stops no body: the cast moves on up the ramp with the root.
-- Once the line has resolved (past the strike beat) the run still looks as far ahead each pass, on
-- the rush's clock and up to its end, so a wall in the overshoot ends it the same way.
local function sweep(brain: Brain.Brain, rush: Brain.Rush, elapsed: number)
	local attack = brain:currentAttack()
	if attack == nil then
		return
	end
	local memory = brain.memory
	if memory.rushJammed == true then
		return
	end
	local front, back = brain:bodyExtents()
	local lateStart = rush.speed * math.max(0, rush.bodyStartedAt - rush.startedAt)
	local reached = progressOf(brain, rush) + front + lateStart + tuning.keepUpStuds
	local rootAt = (brain:position() - rush.origin):Dot(rush.direction)
	local upTo = math.clamp(elapsed, 0, attack.strike)
	local last: number? = memory.rushSwept
	if last ~= nil and upTo <= last then
		-- The line has resolved: the run looks ahead on its own clock, once a pass, to its end.
		local looked: number? = memory.rushLooked
		if elapsed <= attack.strike or (looked ~= nil and elapsed <= looked) then
			return
		end
		memory.rushLooked = elapsed
		local ahead = math.min(rush.speed * elapsed + front, reached, rush.length + brain:rootReach(rush.direction))
		local wall, ground = brain:worldAhead(rush.direction, ahead - rootAt)
		if wall ~= nil and not ground then
			stopAtWall(brain, rush, rootAt + wall)
		end
		return
	end
	memory.rushSwept = upTo
	local to = math.min(rush.speed * upTo + front, reached)
	local wall, ground = brain:worldAhead(rush.direction, to - rootAt)
	local face: number? = if wall ~= nil then rootAt + wall else nil
	if face ~= nil then
		to = math.min(to, face)
	end
	local from = rush.speed * (last or 0) - back
	local resolved: number? = memory.rushResolved
	local due: boolean
	if resolved ~= nil then
		from = math.min(from, resolved)
		due = to > resolved -- otherwise the body has not got past what already resolved
	else
		due = to > from -- otherwise nothing lies between the body's back and the face yet
	end
	if due then
		memory.rushResolved = to
		brain:strikeStretch(rush.origin, rush.direction, from, to, memory.rushHit)
	end
	if face ~= nil and not ground then
		stopAtWall(brain, rush, face)
	end
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
	memory.rushLooked = nil
	memory.rushResolved = nil
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
--- D-184); it is over when its time has run, so the skid starts on the clip's beat. A wall the cast
--- sees has already ended it in the sweep (D-202); a body that fell jamLagStuds behind the clock for
--- a reason the cast misses (a ledge, a glancing corner) stops there and waits out the time (D-190),
--- and its line ends at its snout (D-195). The line resolves on the launch beat's clock (startedAt, what
--- the clients draw) as far as the body keeps up; the body's own run (its jam check and its end) on
--- the frame it started (bodyStartedAt), so a launch noticed up to a frame late neither cuts the run
--- short nor reads as a jam.
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
		-- The line ends here (D-195) and the clients stop drawing it ahead; the body stops where it
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
