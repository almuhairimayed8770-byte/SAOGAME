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

	Nor past a wall (D-197): every stretch stops where the world stops the body, cast ahead of its root
	along the leg it runs in the root's own group (the rushing group meets the world only), so nobody
	behind a wall is hit, while a free run's line, with nothing in the way, resolves on the clock.

	A charge meets the world like a body (D-205 to D-210, choreo/RushWorld.luau, the same rules every
	client draws by). The cast looks lookAheadStuds past the clock's snout, so what the run meets is
	known before the clock gets there, on the server and on every screen:
	  - ground (a slope, D-204, or a step the body climbs, D-209) caps the line, stops nothing;
	  - a wall meeting the leg at less than glanceDegrees bends the path along its face where the
	    body's leading corner touches it (a glance, D-206): RushTurned tells the clients the new legs;
	  - a corner the root's box clips by at most clipStuds is shouldered past: the path sidesteps it
	    and carries on along the line (a clip, D-207), told the same way;
	  - any other wall is a slam (D-205, D-208): the body stops with its leading corner on the face (the
	    snout, head on), not its root's box 3.1 studs short of it. The rush is over at once: RushEnded
	    "Wall" carries where the body meets the face, the body runs to its stop and no further (D-190),
	    the line still resolves up to the face on the clock, and when the timeline brings the snout
	    there the body is dazed (rushWorld.slamDazeSeconds, a Stagger from the front).

	The run is the strike's own movement (D-183): it goes straight at its leg's end (moveDirect),
	never along a path, so a body that stood still before the launch never walks back to where a
	late path began.

	The launch and an early stop go to EnemyService (rushStarted / rushEnded, D-169): it switches the
	body's collision group so the rush passes through players and other enemies (D-167), and tells
	the clients so they draw the rush on the server's timeline. A body that falls more than
	jamLagStuds behind that timeline for a reason the cast does not see reports "Jammed" (the clients
	stop drawing it ahead of the body) and stops where it is; an interrupt, a death or a sleep reports
	why it stopped, after a "Jammed" or a "Wall" too (D-210), so every client hands the body back where
	the server's stopped. EnemyService puts every stopped body back in the enemies group only once it
	has stayed clear of every player and enemy for longer than the clients draw it late.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local AI = require(Shared.data.ai)
local RushWorld = require(Shared.choreo.RushWorld)
local Brain = require(script.Parent.Brain)

local tuning: AI.ChargerTuning = AI.archetypes.Charger
local WORLD = AI.rushWorld

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

-- How far down its path the body stands now (on the leg it last stood on or a later one), clamped
-- to the run.
local function progressOf(brain: Brain.Brain, rush: Brain.Rush): number
	local memory = brain.memory
	local d = math.clamp(RushWorld.project(rush.legs, brain:position(), memory.rushProgress), 0, rush.length)
	memory.rushProgress = d
	return d
end

-- The server time the rush's timeline brings it `d` studs down its path (RushWorld.timeAt, the
-- timeline every client draws the body on).
local function timelineAt(rush: Brain.Rush, d: number): number
	return rush.startedAt + RushWorld.timeAt(rush.speed, rush.length, rush.strike, d)
end

-- Resolves the stretch `from` to `to` studs down the rush's path, leg by leg (D-206, D-207): each leg's
-- piece from its own start point along its own heading (the first leg's from behind the crouch point,
-- the body's back at the launch).
local function resolve(brain: Brain.Brain, rush: Brain.Rush, from: number, to: number)
	local memory = brain.memory
	local legs = rush.legs
	for index, leg in legs do
		local a = if index == 1 then from else math.max(from, leg.at)
		local b = math.min(to, RushWorld.legEnd(legs, index))
		if b > a then
			local origin = leg.from - leg.heading * leg.at + Vector3.new(0, rush.origin.Y, 0)
			brain:strikeStretch(origin, leg.heading, a, b, memory.rushHit)
		end
	end
end

-- The slam (D-205, D-208): the body stops with its leading corner on the face, `stop` studs down the
-- path, and the rush is over at once: reported "Wall" with where the body meets the face, the body
-- sent there and no further (D-190), and the daze due when the timeline brings it there. The line
-- still resolves up to the face (`cap`) on the clock. A rush already over is left alone.
local function slam(brain: Brain.Brain, rush: Brain.Rush, contact: RushWorld.Contact, cap: number)
	local memory = brain.memory
	if memory.rushing ~= true or memory.rushWalled == true or brain:getPhase() ~= "Strike" then
		return
	end
	memory.rushWalled = true
	memory.rushCap = math.min(memory.rushCap or math.huge, cap)
	local progress = progressOf(brain, rush)
	local stop = math.clamp(contact.at, progress, rush.length)
	memory.rushStop = stop
	memory.rushDazeAt = timelineAt(rush, stop)
	brain:rushEnded(rush, "Wall", stop, contact)
	if stop > progress then
		brain:moveDirect(RushWorld.pointAt(rush.legs, stop) + Vector3.new(0, rush.origin.Y, 0), rush.speed)
	else
		brain.context.stop()
	end
end

-- The root's box, standing where it does, looked at from `offset` along `direction` (RushWorld.Probe):
-- how far its centre runs before it meets a wall, within `distance`.
local function probeOf(brain: Brain.Brain): RushWorld.Probe
	return function(offset: Vector3, direction: Vector3, distance: number): number?
		local reach = brain:rootReach(direction)
		local face, ground = brain:worldAhead(direction, distance + reach, offset)
		if face == nil or ground then
			return nil
		end
		return math.max(0, face - reach)
	end
end

-- Looks at the world ahead of the root along the leg it runs, as far as the line resolves (`ahead`
-- studs down the path: the clock's snout, never past where the body keeps up) plus lookAheadStuds,
-- never past the leg's end nor the snout at the run's end. Ground caps the line (D-204, D-209); a wall
-- bends the path (a glance), sidesteps it (a clipped corner) or stops the body (a slam).
local function look(brain: Brain.Brain, rush: Brain.Rush, ahead: number)
	local memory = brain.memory
	if memory.rushWalled == true or memory.rushJammed == true then
		return
	end
	local front = brain:bodyExtents()
	local rootAt = progressOf(brain, rush)
	local index = RushWorld.legIndex(rush.legs, rootAt)
	local leg = rush.legs[index]
	local reach = brain:rootReach(leg.heading)
	local farthest =
		math.min(ahead + WORLD.lookAheadStuds, RushWorld.lookLimit(rush.legs, index, rush.length, reach, front))
	local wall, ground, normal = brain:worldAhead(leg.heading, farthest - rootAt)
	if wall == nil then
		return
	end
	local face = rootAt + wall
	if ground then
		memory.rushGround = face
		return
	end
	local body = brain:bodyProfile()
	if body == nil then
		-- No body to judge: the root's box stops at the face (D-202).
		slam(brain, rush, {
			kind = "Slam",
			at = face - reach,
			legs = nil,
			point = RushWorld.pointAt(rush.legs, face) + Vector3.new(0, brain:position().Y, 0),
			normal = -leg.heading,
		}, face)
		return
	end
	local contact = RushWorld.contact(
		rush.legs,
		rootAt,
		wall - reach,
		normal,
		body :: RushWorld.Body,
		brain:position().Y,
		probeOf(brain)
	)
	local legs = contact.legs
	if contact.kind == "Slam" or legs == nil then
		slam(brain, rush, contact, face)
		return
	end
	if RushWorld.sameLegs(legs, rush.legs) then
		return -- the bend or the sidestep the path already has
	end
	rush.legs = legs
	brain:rushTurned(rush, contact)
end

-- Resolves the stretch of the path the body swept since the last sweep, up to `elapsed` seconds
-- into the rush (never past the attack's strike beat): from where its back was then to where its
-- snout is now, on the rush's clock, but never further ahead of the body's own snout than its late
-- start plus keepUpStuds (D-195), never past a slam's face (D-197) nor ground ahead (D-204), and
-- never again once the rush jammed. Every pass first looks at the world ahead (look): the line,
-- its bends and its sidesteps are known before the clock reaches them, on the server and on every
-- client, and a slam ends the rush at once (D-202, D-205).
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
	local looked: number? = memory.rushLooked
	if looked == nil or elapsed > looked then
		-- Once a pass: the frame and the tick of one moment look once.
		memory.rushLooked = elapsed
		memory.rushGround = nil
		local clock = math.clamp(elapsed, 0, rush.duration)
		look(brain, rush, math.min(rush.speed * clock + front, reached))
	end
	if memory.rushJammed == true or brain:getPhase() ~= "Strike" then
		return
	end
	local upTo = math.clamp(elapsed, 0, attack.strike)
	local last: number? = memory.rushSwept
	if last ~= nil and upTo <= last then
		return -- the line has resolved: the strike beat has passed
	end
	memory.rushSwept = upTo
	local to = math.min(rush.speed * upTo + front, reached, memory.rushCap or math.huge, memory.rushGround or math.huge)
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
		resolve(brain, rush, from, to)
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
	memory.rushDazeAt = nil
	if memory.rushing == true and rush ~= nil then
		memory.rushing = false
		local stop: number? = memory.rushStop
		local distance = progressOf(brain, rush)
		if memory.rushDazing == true and stop ~= nil then
			distance = math.max(distance, stop) -- the daze: the body carries on to its stop
		end
		brain:rushEnded(rush, reason, distance)
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
		strike = attack.strike,
		legs = RushWorld.line(brain:position(), brain:getFacing()),
	}
	memory.rush = rush
	memory.rushing = true
	memory.rushJammed = false
	memory.rushWalled = false
	memory.rushCap = nil
	memory.rushStop = nil
	memory.rushDazeAt = nil
	memory.rushDazing = false
	memory.rushGround = nil
	memory.rushProgress = nil
	memory.rushPassedAt = nil
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
--- D-184); it is over when its time has run, so the skid starts on the clip's beat. The body runs
--- its path leg by leg, turning onto each new leg at rushWorld.turnRate. A slam the cast sees has
--- already ended it in the sweep (D-202, D-205): the body runs to its stop and waits there until the
--- timeline brings its snout to the face, and is dazed then (D-208), however late that is. A body that
--- fell jamLagStuds behind the clock for a reason the cast misses (a ledge) stops there and waits out
--- the time (D-190), and its line ends at its snout (D-195). The line resolves on the launch beat's
--- clock (startedAt, what the clients draw) as far as the body keeps up; the body's own run (its jam
--- check and its end) on the frame it started (bodyStartedAt), so a launch noticed up to a frame late
--- neither cuts the run short nor reads as a jam.
function Charger.onStrike(brain: Brain.Brain, dt: number, _phaseElapsed: number): boolean
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
	local dazeAt: number? = memory.rushDazeAt
	if dazeAt ~= nil and now >= dazeAt then
		-- The snout is on the face on every screen: the slam dazes the body, which interrupts this
		-- brain (onCancel tells where the body will stand). The interrupt stops the mover; a body a
		-- hair short of its stop carries on to it through the daze, so it rests where every client
		-- drew it, snout on the face.
		memory.rushDazeAt = nil
		memory.rushDazing = true
		local stop = RushWorld.pointAt(rush.legs, memory.rushStop or progressOf(brain, rush))
		brain:daze(WORLD.slamDazeSeconds)
		memory.rushDazing = false
		if brain:getPhase() ~= "Strike" or memory.rushing ~= true then
			brain:moveDirect(stop + Vector3.new(0, rush.origin.Y, 0), rush.speed)
			return true
		end
	end
	local progress = progressOf(brain, rush)
	local ran = now - rush.bodyStartedAt
	if ran >= rush.duration and memory.rushDazeAt == nil then
		memory.rushing = false
		brain:rushEnded(rush, "Done", progress)
		return true
	end
	if memory.rushWalled == true then
		return false -- slam() sent the body to its stop; it waits there for the daze
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
		-- Down the leg it runs, and onto the next one when it would reach the bend before the next
		-- pass (the passes' own gap, every server frame), so a body never pulls up at a corner of its
		-- own path and cuts a sidestep's corner by no more than a frame's run.
		local legs = rush.legs
		local index = RushWorld.legIndex(legs, progress)
		local passedAt: number? = memory.rushPassedAt
		local gap = if passedAt ~= nil then math.clamp(now - passedAt, 0, AI.tickSeconds()) else AI.tickSeconds()
		memory.rushPassedAt = now
		if legs[index + 1] ~= nil and RushWorld.legEnd(legs, index) - progress <= rush.speed * gap then
			index += 1
		end
		local goal = math.min(RushWorld.legEnd(legs, index), rush.length)
		brain:moveDirect(RushWorld.pointAt(legs, goal) + Vector3.new(0, rush.origin.Y, 0), rush.speed)
		if #legs > 1 then
			brain:turnToward(legs[index].facing, WORLD.turnRate, dt)
		end
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
