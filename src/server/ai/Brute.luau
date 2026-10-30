--!strict
--[[
	Brute (section 9): the Kobold Axeman. Slow heavy swings, a big Guard Gauge.

	Chase: walks straight at the target and stops at stopDistance. When the target is inside
	reach * engageFraction and roughly ahead, it begins the attack: the 1.0 s overhead wind-up with
	the yellow (GuardBreak) edge from the attack def. During the wind-up it keeps facing the target,
	but only at the Brute's slow wind-up turn rate, so a late sidestep or a dodge leaves the cone.
	The strike commits (turn rate 0): the 60-degree cone resolves `attack.strike` seconds after the
	wind-up ends, from where the body stands and faces at that moment. Then the 1.4 s recovery with
	the axe stuck low.

	A parry (CombatService staggers the enemy: EntityService.StateChanged "Stagger") reaches the
	brain as interrupt(), which cancels the attack before the strike.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local AI = require(Shared.data.ai)
local Brain = require(script.Parent.Brain)

local tuning: AI.BruteTuning = AI.archetypes.Brute

local Brute: Brain.Archetype = {
	name = "Brute",
} :: any

--- Nothing to remember between chases.
function Brute.onChaseStart(_brain: Brain.Brain) end

--- Turns toward the target and walks up to stopDistance.
function Brute.chase(brain: Brain.Brain, dt: number, target: Brain.Target): Types.EnemyAttackDef?
	brain:turnToward(target.direction, tuning.turnRate, dt)
	if target.distance > tuning.stopDistance then
		brain:moveToward(target.position, brain:speed())
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
