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
	jamLagStuds: number, -- a rushing body this far behind the rush's clock is jammed (D-169)
	keepUpStuds: number, -- the rush's line resolves at most this far past where the body's snout
	-- keeps up with its run (D-195); above a free body's physics lag, below jamLagStuds
}

export type BruteTuning = ArchetypeTuning & {
	stopDistance: number, -- stops walking this far from the target
}

-- How a rush meets the world (D-205 to D-210): the same rules on the server, which moves the body and
-- resolves the hits, and on every client, which draws the body ahead of its late root
-- (choreo/RushWorld.luau holds the rules; Charger.luau and RushDraw.luau use them).
export type RushWorldTuning = {
	riserStuds: number, -- a face whose top is at most this above the ground in front of it is a step
	probeStuds: number, -- how far below the root's centre a ground probe looks
	glanceDegrees: number, -- a wall meeting the line at less than this turns the rush along its face
	clipStuds: number, -- a corner the root's box overlaps sideways by at most this is shouldered past
	clipMarginStuds: number, -- the sidestep clears the corner by this much more
	clipRunStuds: number, -- the sidestep's run along the line, ending where the root meets the corner
	clipPassStuds: number, -- a sidestepped box must run this far past the corner's face to be clear
	clipBisections: number, -- halvings that find the smallest sidestep that clears
	lookAheadStuds: number, -- every cast looks this far past the body's snout
	maxLegs: number, -- legs one rush runs at most; past them a wall stops it
	turnRate: number, -- degrees per second the server's body turns onto a new leg
	slamDazeSeconds: number, -- a body that slams into a wall staggers this long, from the front
	fallGravity: number, -- studs a second squared the drawn body drops onto lower ground under
	restStuds: number, -- a late root that moves less than this over restSeconds is at rest
	restSeconds: number, -- how long a late root stays put before a client calls it at rest
	restSpeed: number, -- studs a second at most a root at rest carries (its replicated velocity)
}

local AI = {
	-- Section 16 rates (owned by enemies.luau)
	tickHz = Enemies.rules.aiTickHz,
	bossTickHz = Enemies.rules.bossTickHz,
	sleepRadius = Enemies.rules.simulateRadius,
	pathfindPastStuds = Enemies.rules.pathfindBeyondStuds,

	-- The tick loop: the heartbeat accumulates dt and runs whole ticks; after a hitch at most this
	-- many ticks run in one frame and the rest of the backlog is dropped. The frame pass's body turn
	-- (D-185) turns at most as far as these ticks would have in one frame.
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

	-- Room between enemies (D-259): no enemy stands, stops or walks inside another. Each body's
	-- footprint is a flat capsule measured on its rig at spawn (Spacing.footprintOf: its spine along
	-- the facing, as far ahead and behind as any part reaches, its radius the widest part's half
	-- width), so a boar's snout and a kobold's axe count, not only the roots the engine collides.
	-- A free enemy (one of `freePhases`: deciding or walking, never mid-attack, staggered or dead)
	-- keeps gapStuds of clear ground to every other body: a goal inside another's room moves out to
	-- its edge (a home a boar now stands on is reached at the boar's side), a walk that heads into a
	-- body within gapStuds + slideStuds slides along it instead, and a body caught inside another
	-- (a rush ran into it, it was spawned there, it stood still while the other walked up) steps
	-- out. Two free bodies each step half the way; a busy or asleep one does not move.
	spacing = {
		gapStuds = 1, -- clear ground every two enemy footprints keep between them
		slideStuds = 2, -- within the gap plus this, a walk into another body turns along it
		-- A slide shorter than this (a goal nearly straight behind the other body) is lengthened to
		-- it, so the walk goes round rather than creeping, while the goal is farther than it.
		slideMinStuds = 2,
		stepStuds = 0.5, -- a step out goes this far past the gap, so it ends clear, not on the edge
		stepSpeedMultiplier = 0.6, -- on the def's moveSpeed: a step aside is a shuffle, not a run
		standOffPasses = 3, -- passes over the others when one push out lands a goal in another
		freePhases = { Idle = true, Alert = true, Chase = true, Return = true },
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
		-- A blow's tell (the weapon's fill and the ground shape) stays lit past the wind-up, through the
		-- strike, until this long before the blow lands (windUp + strike): the frames its clip's snap
		-- takes to fall (the Kobold's Overhead snaps from 1.30 to 1.35, three 60 fps frames). The
		-- light goes out as the blade falls, never 18 frames before it (F7). A rush's line still ends
		-- at its launch: the run is the strike.
		snapLeadSeconds = 0.05,
		-- Over the parry window before the blow (combat.luau parryWindow) the fill is at its
		-- brightest, steady, no pulse: the last glint that marks the window (F7). 0 is solid.
		glintFillTransparency = 0,
	},

	-- An enemy's blow on the local fighter, shown on its strike's server frame (F16, D-258): the
	-- flinch, the white flash and the hit's sound play on this client when the blow lands on the
	-- server's clock, before the server's word, if this client sees nothing that could stop it. HP,
	-- the number and the hit-stop still wait for the server; a word that never comes, or a guard or
	-- parry in it, takes the flinch back. Only a blow with a known strike frame (not a rush).
	strikePrediction = {
		enabled = true,
		-- The local fighter's states (CharacterController) a blow lands on as far as this client can
		-- tell. A guard, a dodge, a stagger or a guard break waits for the server.
		exposedStates = { Idle = true, Holding = true, Art = true, PostMotion = true, Basic = true },
		-- A guard or a dodge let go less than this long ago may still stand on the server (the
		-- release travels up a latency later): a tapped parry is never shown as a hit.
		defenceGraceSeconds = 0.25,
		-- The body must stand this far inside the blow's shape (studs off its reach and off a
		-- line's sides, degrees off a cone's edges): the client's body is a latency ahead of the
		-- server's, so a body near an edge waits for the server's verdict.
		marginStuds = 1,
		marginDegrees = 8,
		-- A strike frame this client first sees later than this (a stall, a late message) is left to
		-- the server's word, which is close behind.
		lateSeconds = 0.1,
		-- Seconds of play a shown blow waits for its HitConfirmed before the flinch is taken back.
		confirmSeconds = 0.5,
		-- How fast a flinch the server did not confirm fades out.
		takeBackBlendOut = 0.08,
	},

	-- Hit-stop on an attacking enemy (D-168): a player's confirmed hit pauses the enemy's unresolved
	-- attack (wind-up, or strike before it resolves) for the hit-stop its clip freezes for, at most
	-- this many seconds per attack in all: a full basic chain (3 + 3 + 3 + 6 frames at 60 fps) and no
	-- more, so a combo can delay a telegraphed blow by a beat but never hold it off.
	hitStop = {
		maxPausePerAttack = 0.25,
	},

	-- Collision groups (D-167), registered on the server through PhysicsService. Player characters
	-- join `players` when they are ready (CharacterReady), enemies `enemies` at spawn. A rushing
	-- enemy is `rushing` from its launch until its body has stayed clear of every player and enemy
	-- for rejoinClearSeconds after the rush stops: it collides with the world (Default) only, so a
	-- rush runs through the players it hits and through its packmates instead of jamming on them.
	-- Players collide with players, enemies with enemies (a pack never melts into one body) and the
	-- world. What a player bumps into on an enemy is its blocker (D-198), not its root: the root
	-- floats at HipHeight with its top edge at a player's chest, and a player walking into that edge
	-- bobbed on it and slid off sideways. The blocker is one upright, invisible box over the root's
	-- footprint from the floor to blockerHeight, in `blockers`: it collides with players only (never
	-- the world, so the body moves as before, nor any query, which runs as Default), and only while
	-- the enemy is solid (CollisionGroups.assign turns it off for a rush).
	collision = {
		players = "SkyspirePlayers",
		enemies = "SkyspireEnemies",
		rushing = "SkyspireRushing",
		blockers = "SkyspireBlockers",
		-- Studs above the floor an enemy's blocker reaches: above every colliding part of a standing
		-- player (an R15 at the place's 1.08 body scale stands about 5.6 studs; its legs never
		-- collide, its root's bottom is at HipHeight), so a walk-in meets one flat face, no edge.
		blockerHeight = 7,
		-- Degrees from straight up within which a face a rushing root's world cast meets is ground the
		-- body climbs, not a wall (D-204): the server's rush still never resolves its line past it but
		-- does not end there, and the client's drawn rush runs on through it (RushDraw.room). At least
		-- every Charger root's climb (the slope its box's front edge first touches, atan(hipHeight /
		-- half its length): 32.6 for the Boar) and below a wall's 90 (the ai validator checks both);
		-- a face steeper than the root climbs but within this stops the body on its own (the jam).
		groundSlopeDegrees = 45,
		-- Engine fact: every client draws a server-owned body up to this late (physics replication),
		-- while a part's collision group reaches it sooner.
		clientDrawLagSeconds = 0.3,
		-- A stopped rush turns solid again only once its root has stayed clear of every player and
		-- enemy for this long (D-190): longer than clientDrawLagSeconds, so no client still shows it
		-- inside someone when it collides again (the engine would push that player out at the rush's
		-- speed, onto the boar's back), and shorter than every rush's recovery, so a clean rush is
		-- solid before it moves off (the ai validator checks both).
		rejoinClearSeconds = 0.5,
		-- Pairs that pass through each other; every other pair collides. Default is the world.
		apart = {
			{ "SkyspireRushing", "SkyspirePlayers" },
			{ "SkyspireRushing", "SkyspireEnemies" },
			{ "SkyspireRushing", "SkyspireRushing" },
			{ "SkyspireEnemies", "SkyspirePlayers" },
			{ "SkyspireBlockers", "Default" },
			{ "SkyspireBlockers", "SkyspireEnemies" },
			{ "SkyspireBlockers", "SkyspireRushing" },
			{ "SkyspireBlockers", "SkyspireBlockers" },
		},
	},

	-- A rush that meets the world (D-205 to D-210), the same on the server and on every client
	-- (choreo/RushWorld.luau). The world cast is the root's own box in the rushing group (D-197).
	rushWorld = {
		-- A face the box meets is a step the body climbs, not a wall, when nothing stands higher than
		-- this above the ground just in front of it: below the Boar's 1.6 hip height, so its root's
		-- box clears the step's top when it gets there (the server's Humanoid climbs it), while the
		-- box, cast level from lower ground, meets a stair's risers two and three treads ahead.
		riserStuds = 1.5,
		-- A ground probe looks this far below the root's centre (the hip height plus a fall).
		probeStuds = 8,
		-- A wall meeting the line at less than this many degrees turns the rush along its face (a
		-- scrape that keeps the charge's speed); at this or more the body slams into it, stops with
		-- its snout on the face and is dazed. 30 glances, 45, 60 and 75 slam.
		glanceDegrees = 40,
		-- A corner (a pillar, a post) the root's box overlaps sideways by at most this is shouldered
		-- past: the rush sidesteps by the overlap (plus what the body's flank reaches past the root's
		-- side, plus clipMarginStuds) over the clipRunStuds before its snout reaches the corner's face,
		-- and carries on along its line. More overlap than clipStuds is a wall.
		clipStuds = 1.0,
		clipMarginStuds = 0.15,
		clipRunStuds = 3,
		-- A sidestepped box is clear of the corner when it runs this far past where the straight box
		-- met it: a wall at glanceDegrees or more moves at most clipStuds / tan(40) = 1.2 studs that
		-- way, a pillar's flank never meets a box running beside it.
		clipPassStuds = 3,
		clipBisections = 4,
		-- Every cast (the server's and each client's) looks this far past the body's snout, so a bend
		-- or a sidestep is known on both sides before the body reaches its start: at least
		-- clipRunStuds plus a frame's run (0.47 studs at 60 fps), so a sidestep seen at once still
		-- has its whole run.
		lookAheadStuds = 3.5,
		-- A rush runs at most this many legs (its line plus bends); a wall past them stops it.
		maxLegs = 6,
		-- The server's body turns onto a new leg this fast (the clients draw it at choreo.luau
		-- enemy.rush.turnRate, the same number).
		turnRate = 720,
		-- A slam staggers the body from the front for this long, from the moment the server's timeline
		-- brings its snout to the face: longer than a parry's 1.0 s (section 6), the Stun's 1.5 s, so
		-- baiting a boar into a wall is the best opening it gives.
		slamDazeSeconds = 1.5,
		-- The drawn body stands on the ground under it: a step lifts it at once (its root's Humanoid
		-- steps up as it gets there), and it drops onto lower ground under this gravity (the
		-- workspace's default, the root's own fall), studs a second squared.
		fallGravity = 196.2,
		-- A client calls the server's body stuck before its word comes (D-256) when its late root has
		-- moved less than restStuds over restSeconds, carries at most restSpeed, has left its crouch
		-- (keepUpStuds) and stands more than jamLagStuds behind the drawn body: a free run only rests
		-- at its end. A replication stall freezes the root's place but keeps its velocity, so it is
		-- no rest. 0.1 s is 6 frames at 60 fps: a quarter stud over it is 2.5 studs a second, where a
		-- rush runs 28.
		restStuds = 0.25,
		restSeconds = 0.1,
		restSpeed = 2.5,
	} :: RushWorldTuning,

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
			-- A body this far behind the rush's clock is stuck, not slow to accelerate (D-169). Checked
			-- every server frame (D-184): a free body on flat ground trails it by under a stud at 30 and
			-- 60 fps with frame jitter, a body held to 0.85 of the rush speed by 3.7, a throttled 0.1 s
			-- hitch by 2.7; a stop the world cast misses is still told within about 0.13 s. A wall the
			-- cast sees ends the rush at once instead (D-202, D-203).
			jamLagStuds = 4,
			-- A free-running body trails its own run by well under a stud (its acceleration over the
			-- first frame); a body held back by a wall falls further behind, and the rush's line stops
			-- this far past its snout, so a charge only hits what it reaches (D-195).
			keepUpStuds = 1,
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
