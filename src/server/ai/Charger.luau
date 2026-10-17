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
	resolves) for reach + overshoot studs. The strike resolves `attack.strike` seconds in, from the
	crouch point along the line, so what the telegraph drew is exactly what is hit (HitSweep
	lineTargets through CombatService.enemyStrike). The overshoot carries it past the target; the
	recovery is the skid and the slow turn back.
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

--- The launch: fixes the line from the crouch point along the facing and starts the rush.
function Charger.onStrikeStart(brain: Brain.Brain, _target: Brain.Target?)
	local attack = brain:currentAttack()
	local memory = brain.memory
	if attack == nil or not isRush(attack) then
		memory.rushing = false
		return
	end
	local start = brain:position()
	local direction = brain:getFacing()
	local length = attack.reach + tuning.overshoot
	local speed = AI.rushSpeed(attack)
	memory.rushing = true
	memory.rushStart = start
	memory.rushDir = direction
	memory.rushEnd = start + direction * length
	memory.rushSpeed = speed
	memory.rushDuration = length / speed
	brain:moveToward(memory.rushEnd, speed)
end

--- A rush resolves from the crouch point along the line (what the telegraph drew); anything else
--- from the body as it stands.
function Charger.strikeFrame(brain: Brain.Brain): (Vector3, Vector3)
	local memory = brain.memory
	if memory.rushing == true then
		return memory.rushStart, memory.rushDir
	end
	return brain:position(), brain:getFacing()
end

--- Keeps the rush going; it is over when its time has run (a body blocked by a wall simply pushes
--- until then, so the overshoot never ends early and the skid starts on the clip's beat).
function Charger.onStrike(brain: Brain.Brain, _dt: number, elapsed: number): boolean
	local memory = brain.memory
	if memory.rushing ~= true then
		return true
	end
	brain:moveToward(memory.rushEnd, memory.rushSpeed)
	return elapsed >= memory.rushDuration
end

--- The skid and the slow turn back toward the target.
function Charger.onRecover(brain: Brain.Brain, dt: number, target: Brain.Target?)
	brain.memory.rushing = false
	if target ~= nil then
		brain:turnToward(target.direction, tuning.recoverTurnRate, dt)
	end
end

return Charger
