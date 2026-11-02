--!strict
--[[
	Brute (section 9): the Kobold Axeman. Slow heavy swings, a big Guard Gauge.

	Chase: walks straight at the target and stops at stopDistance. Well off its target (more than
	wheelAngle) it wheels instead: it walks along its facing at wheelSpeedMultiplier of its pace while
	it turns, so it turns round on its feet. Walked straight at a target behind it, the body went
	sideways and back under a walk whose feet step along the facing, and they slid (the kobold from
	behind, 0.161 / 0.280 a 60 Hz row at 135 / 180 degrees, D-598). With the world close behind the
	target along the line from the body (a fighter backed to a wall or a pillar), the stop grows so
	the fighter's swing has its room between that world and the body's own blocker face
	(stopDistanceFor, D-627): from stopDistance alone a kobold stood 2.2-2.7 from a wall behind a
	fighter, where the swings lean 2.0-2.8 deep, and the engine shoved the body out. That stop is
	landed on (D-643), so the walk's last tick and its brake never carry the body inside it. When the
	target is inside reach * engageFraction and roughly ahead, it begins the attack: the 1.0 s
	overhead wind-up with the yellow (GuardBreak) edge from the attack def. During the wind-up it
	keeps facing the target, but only at the Brute's slow wind-up turn rate, so a late sidestep or a
	dodge leaves the cone. The strike commits (turn rate 0): the 60-degree cone resolves
	`attack.strike` seconds after the wind-up ends, from where the body stands and faces at that
	moment. Then the 1.4 s recovery with the axe stuck low.

	A parry (CombatService staggers the enemy: EntityService.StateChanged "Stagger") reaches the
	brain as interrupt(), which cancels the attack before the strike.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local AI = require(Shared.data.ai)
local Brain = require(script.Parent.Brain)

local tuning: AI.BruteTuning = AI.archetypes.Brute

-- The archetype, plus where its chase stops (the specs and the bench read it, D-627).
type BruteModule = Brain.Archetype & {
	stopDistanceFor: (brain: Brain.Brain, target: Brain.Target) -> number,
}

local Brute: BruteModule = {
	name = "Brute",
} :: any

--- Nothing to remember between chases.
function Brute.onChaseStart(_brain: Brain.Brain) end

--- Where the chase stops (D-627): stopDistance, grown when the world stands close behind the
--- target along the line from the body, so that at least backRoom.leanStuds stand between that
--- world and the body's own blocker face (faceReach: the face across its facing line, square to the
--- target it turns to face), with backRoom.brakeSeconds of its pace to spare, and never past
--- backRoom.maxStopDistance. A grown stop is landed on (chase, D-643), so neither the walk's last
--- tick nor a brake carries the body inside it. The world is looked for only as far behind as a face
--- could still call for more than stopDistance.
function Brute.stopDistanceFor(brain: Brain.Brain, target: Brain.Target): number
	local base = tuning.stopDistance
	local room = tuning.backRoom
	-- The stop that leaves leanStuds with the world at the target's own centre.
	local needed = room.leanStuds + brain:faceReach() + brain:speed() * room.brakeSeconds
	local look = needed - base
	if look <= 0 then
		return base
	end
	local behind = brain:worldBehind(target, look)
	if behind == nil then
		return base
	end
	return math.clamp(needed - behind, base, math.max(base, room.maxStopDistance))
end

--- Turns toward the target and walks up to its stop (stopDistanceFor): along its facing, slowed,
--- while it wheels round from more than wheelAngle off (D-598), then straight at the target. A stop
--- grown for a fighter backed to the world is landed on (D-643): from within the walk's last tick
--- and its brake of it (the pace times AI.tickSeconds() + backRoom.brakeSeconds), the body goes
--- straight onto the stop and rests there (EnemyService's landing, D-525). Between the swing's room
--- (leanStuds) and the attacks' engage range a flush wall leaves a band narrower than a tick's walk
--- (0.2 against the kobold's 0.5): a walk that stops where a tick finds it inside its stop, and
--- then brakes, would stand anywhere across it.
function Brute.chase(brain: Brain.Brain, dt: number, target: Brain.Target): Types.EnemyAttackDef?
	brain:turnToward(target.direction, tuning.turnRate, dt)
	local stop = Brute.stopDistanceFor(brain, target)
	if target.distance > stop then
		local pace = brain:speed()
		if brain:angleTo(target.direction) > tuning.wheelAngle then
			brain:moveForward(pace * tuning.wheelSpeedMultiplier)
		elseif
			stop > tuning.stopDistance
			and target.distance - stop <= pace * (AI.tickSeconds() + tuning.backRoom.brakeSeconds)
		then
			local at = target.position - target.direction * stop
			brain:moveDirect(Vector3.new(at.X, brain:position().Y, at.Z), pace, true)
		else
			brain:moveToward(target.position, pace)
		end
	else
		brain.context.stop()
	end
	return brain:pickAttack(target)
end

--- A melee attack needs the target inside reach * engageFraction and within engageAngle of the facing.
function Brute.canUse(brain: Brain.Brain, attack: Types.EnemyAttackDef, target: Brain.Target): boolean
	if target.distance > attack.reach * tuning.engageFraction then
		return false
	end
	local halfArc = if attack.arc >= 360 then 180 else attack.arc / 2
	return brain:angleTo(target.direction) <= math.min(tuning.engageAngle, halfArc)
end

--- Keeps facing the target during the wind-up, slowly.
function Brute.onWindUp(brain: Brain.Brain, dt: number, target: Brain.Target?)
	if target ~= nil then
		brain:turnToward(target.direction, tuning.windUpTurnRate, dt)
	end
end

--- The swing commits: the body stays planted.
function Brute.onStrikeStart(brain: Brain.Brain, _target: Brain.Target?)
	brain.context.stop()
end

--- The cone resolves from where the body stands and faces as the axe lands.
function Brute.strikeFrame(brain: Brain.Brain): (Vector3, Vector3)
	return brain:position(), brain:getFacing()
end

--- The strike phase is over as soon as the hit resolves (turn rate 0 until then).
function Brute.onStrike(brain: Brain.Brain, dt: number, _elapsed: number): boolean
	local target = brain:getTarget()
	if target ~= nil and tuning.strikeTurnRate > 0 then
		brain:turnToward(target.direction, tuning.strikeTurnRate, dt)
	end
	return true
end

--- The axe is stuck low: a slow turn toward the target while it is freed.
function Brute.onRecover(brain: Brain.Brain, dt: number, target: Brain.Target?)
	if target ~= nil then
		brain:turnToward(target.direction, tuning.recoverTurnRate, dt)
	end
end

return Brute
