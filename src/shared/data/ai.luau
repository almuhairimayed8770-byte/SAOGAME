--!strict
--[[
	AI tunables (sections 9 and 16). Every number the enemy brains and EnemyService use lives
	here: tick rates, perception, leash, movement and pathfinding, interrupts, attack selection
	and the per-archetype behavior numbers. Times are seconds, distances are studs, angles are
	degrees and turn rates are degrees per second.

	The four section 16 rates (the 20 Hz AI tick, the 30 Hz boss tick, the 300-stud sleep radius
	and the 60-stud pathfinding threshold) are owned by enemies.luau (`Enemies.rules`) and are
	re-exported here so a brain reads one table and the number exists once.

	Archetype feel (section 9): the Charger turns slowly, lines up and rushes past its target; the
	Brute walks up, holds a long overhead and tracks its target only slowly while it holds, so a
	late sidestep or a dodge leaves the cone.
]]

local Enemies = require(script.Parent.enemies)
local Combat = require(script.Parent.combat)

export type ArchetypeTuning = {
	turnRate: number, -- while chasing or circling
	windUpTurnRate: number, -- while the wind-up pose is held (0: the pose holds its line)
	strikeTurnRate: number, -- while the strike plays out (0: the strike commits)
	recoverTurnRate: number, -- during the recovery
	attackCooldown: number, -- seconds after the recovery before the same brain may attack again
	chaseSpeedMultiplier: number, -- on the def's moveSpeed while chasing
	engageFraction: number, -- a melee attack is in range at reach * this
	engageAngle: number, -- the target must be within this many degrees of the facing to start
}

export type ChargerTuning = ArchetypeTuning & {
	minChargeDistance: number, -- closer than this the Charger will not crouch; it circles out
	maxChargeDistance: number, -- farther than this it runs straight at the target
	circleDistance: number, -- while too close it spirals outward until it is this far away
	circleOutwardBias: number, -- 0 = pure tangent, 1 = straight away from the target
	lineUpToleranceDegrees: number, -- the target must be within this of the facing to crouch
	lineUpLooseToleranceDegrees: number, -- after lineUpTimeout, this wider tolerance applies
	lineUpTimeout: number, -- seconds of chasing without a line before the tolerance widens
	chargeSpeed: number, -- studs per second along the line, at least; `AI.rushSpeed(attack)` raises
	-- it to reach / strike so the body reaches the end of the telegraphed line as the hit resolves
	overshoot: number, -- studs past the end of the line the rush carries
	wheelAngle: number, -- degrees off the target beyond which the chase slows into the turn
	wheelSpeedMultiplier: number, -- the chase speed while wheeling (a tighter turning circle)
}

export type BruteTuning = ArchetypeTuning & {
	stopDistance: number, -- stops walking this far from the target
}

local AI = {
	-- Section 16 rates (owned by enemies.luau)
	tickHz = Enemies.rules.aiTickHz,
	bossTickHz = Enemies.rules.bossTickHz,
	sleepRadius = Enemies.rules.simulateRadius,
	pathfindPastStuds = Enemies.rules.pathfindBeyondStuds,

	-- The tick loop: the heartbeat accumulates dt and runs whole ticks; after a hitch at most this
	-- many ticks run in one frame and the rest of the backlog is dropped.
	maxTicksPerFrame = 4,
	sleepCheckInterval = 0.5, -- seconds between awake / asleep re-evaluations
	flatEpsilon = 0.001, -- a ground-plane vector shorter than this has no direction

	perception = {
		alertDelay = 0.25, -- the head turn between noticing and chasing
		retargetInterval = 0.5, -- seconds between threat re-evaluations
		threatSwitchMargin = 1.25, -- a new target needs this times the current target's threat
		threatRangeMultiplier = 2, -- a threat holder counts up to aggroRange * this
		loseRangeMultiplier = 1.5, -- the target drops beyond aggroRange * this ...
		loseTargetGrace = 2.0, -- ... after this many seconds out of range
	},

	leash = {
		returnSpeedMultiplier = 1.25, -- walks home a little faster than it chases
		homeRadius = 3, -- within this of the spawn point counts as home
	},

	movement = {
		arriveRadius = 2.5, -- a MoveTo goal within this is reached
		moveAheadStuds = 8, -- "walk along the facing": the goal is placed this far ahead
		reissueStuds = 1, -- a goal that moved less than this does not re-issue MoveTo
		reissueInterval = 0.5, -- but every goal is re-issued at least this often (MoveTo times out)
		stuckSeconds = 1.5, -- no progress for this long switches to pathfinding
		stuckProgressStuds = 0.5,
		waypointReach = 3, -- a path waypoint within this is passed
		repathInterval = 1.0, -- seconds between path computations while following a path
		pathFailRetry = 2.0, -- seconds before retrying after a failed path
		agentRadius = 2.5,
		agentHeight = 5,
		agentCanJump = false,
		-- Section 16: PathfindingService with custom material costs. Placeholder values until the
		-- floors have terrain; tune per biome in Phase 3.
		materialCosts = {
			Water = 20,
			Mud = 4,
			Snow = 3,
			Ice = 2,
			Sand = 1.5,
		},
	},

	interrupt = {
		resumeDelay = 0.3, -- a beat after a stagger or break before the next decision
		-- Fallback hold durations when the StateChanged signal carries none (section 6 numbers).
		durations = {
			Stagger = Combat.staggerDuration,
			Break = Combat.breakDuration,
			GuardBroken = Combat.guardBreakStagger,
		},
	},

	attack = {
		defaultWeight = 1,
		-- Selection weights by attack id (section 9: the signature attack leads, the Elite's second
		-- attack is the surprise).
		weights = {
			Charge = 3,
			Trample = 1,
			Overhead = 3,
			Sweep = 1,
		},
	},

	telegraph = {
		lineWidth = Combat.strikeLineWidth, -- the ground line is exactly as wide as the strike that follows
	},

	archetypes = {
		Charger = {
			turnRate = 110,
			windUpTurnRate = 0,
			strikeTurnRate = 0,
			recoverTurnRate = 70,
			attackCooldown = 1.0,
			chaseSpeedMultiplier = 1,
			engageFraction = 1,
			engageAngle = 8,
			-- Wheeling (turning more than wheelAngle off the target) runs at half speed, so the turning
			-- circle shrinks to moveSpeed * 0.5 / turnRate (about 3.6 studs for the boar) and a line
			-- found from circleDistance away still starts beyond minChargeDistance (the ai validator
			-- checks the geometry).
			minChargeDistance = 10,
			maxChargeDistance = 30,
			circleDistance = 20,
			circleOutwardBias = 0.6,
			lineUpToleranceDegrees = 8,
			lineUpLooseToleranceDegrees = 30,
			lineUpTimeout = 4.0,
			chargeSpeed = 28,
			overshoot = 8,
			wheelAngle = 45,
			wheelSpeedMultiplier = 0.5,
		} :: ChargerTuning,
		Brute = {
			turnRate = 160,
			windUpTurnRate = 25,
			strikeTurnRate = 0,
			recoverTurnRate = 40,
			attackCooldown = 0.5,
			chaseSpeedMultiplier = 1,
			engageFraction = 0.8,
			engageAngle = 45,
			stopDistance = 3.5,
		} :: BruteTuning,
		-- The other seven archetypes land in Phase 1; until then they borrow the Brute's numbers.
		Default = {
			turnRate = 160,
			windUpTurnRate = 25,
			strikeTurnRate = 0,
			recoverTurnRate = 40,
			attackCooldown = 0.5,
			chaseSpeedMultiplier = 1,
			engageFraction = 0.8,
			engageAngle = 45,
		} :: ArchetypeTuning,
	},
}

--- The tuning table for an archetype; archetypes without a brain yet use `Default`.
function AI.tuningFor(archetype: string): ArchetypeTuning
	local tuning = (AI.archetypes :: { [string]: ArchetypeTuning })[archetype]
	return tuning or AI.archetypes.Default
end

--- The selection weight of an attack id.
function AI.attackWeight(attackId: string): number
	return (AI.attack.weights :: { [string]: number })[attackId] or AI.attack.defaultWeight
end

--- Seconds one AI tick lasts.
function AI.tickSeconds(): number
	return 1 / AI.tickHz
end

--- The rush speed of a Charger attack: at least chargeSpeed, and fast enough that the body reaches
--- the end of the telegraphed line (reach) at the moment the hit resolves (strike).
function AI.rushSpeed(attack: { reach: number, strike: number }): number
	local charger = AI.archetypes.Charger
	if attack.strike <= 0 then
		return charger.chargeSpeed
	end
	return math.max(charger.chargeSpeed, attack.reach / attack.strike)
end

--- How far from its target a Charger moving at `moveSpeed` is when it finishes wheeling around from
--- a tangential heading at circleDistance: the turning circle has radius speed / turnRate, and the
--- line is found where the tangent from the target touches it. Zero when it cannot turn tight enough.
function AI.chargerLineUpDistance(moveSpeed: number): number
	local charger = AI.archetypes.Charger
	local radius = moveSpeed * charger.wheelSpeedMultiplier / math.rad(charger.turnRate)
	local centerDistance = charger.circleDistance - radius
	if centerDistance <= radius then
		return 0
	end
	return math.sqrt(centerDistance * centerDistance - radius * radius)
end

return AI
