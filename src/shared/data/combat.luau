--!strict
--[[
	Core combat tunables (section 6). Starting values; tune here, never in a gameplay script.
	Times are seconds, distances are studs, fractions are 0..1.
]]

-- The blade's hit radius (section 6, D-010). The arc sweep's step is tied to it below.
local HIT_SPHERE_RADIUS = 1.2

local Combat = {
	-- Blade Art timeline
	startPoseTime = 0.15, -- the body moves into the stance
	activationHold = 0.1, -- trail ignites, chime, the tell
	activationCancelTime = 1.0, -- holding the key past this cancels the Art
	postMotionMin = 0.2, -- the shortest a Switch can cut a post-motion to (Phase 1)
	locomotionBlendOut = 0.2, -- blend from the end pose back to locomotion

	-- Hit-stop in frames at 60 fps (section 6) and the camera response to each tier (section 10)
	hitStopFrames = {
		Normal = 3,
		Final = 6,
		Kill = 10,
	},
	hitStopFrameSeconds = 1 / 60,
	cameraNudgeStuds = 0.4,
	cameraShakeStuds = {
		Normal = 0.15,
		Final = 0.3,
		Kill = 0.6,
	},
	highlightFlashFrames = 2,

	-- Damage formula: weaponAttack * artMultiplier * (1 + STR * strScale) * crit - targetDefense
	strDamageScale = 0.012,
	critMultiplier = 1.5,
	critChancePerAgi = 0.004, -- 100 AGI = 40% crit chance
	critChanceMax = 0.6,
	minimumDamage = 1,
	basicAttackMultiplier = 0.3, -- each basic hit is about 30% of a tier-1 Art
	basicAttackGaugeFraction = 0.1, -- basic attacks deal a tenth of Art gauge damage
	basicChainLength = 3,
	basicChainWindow = 0.6, -- seconds after the previous swing STARTED in which the next basic continues the chain
	basicHitDuration = 0.35,

	-- Guard Gauge and Break
	guardRegenPerSecond = 0.1, -- fraction of max per second while not hit by Arts
	guardRegenDelay = 0.5, -- seconds after an Art hit before regen resumes
	breakDuration = 3.0,
	breakDamageMultiplier = 2.0,
	breakPostMotion = 0, -- Arts landed on a Broken enemy have zero post-motion

	-- Switch (Phase 1 uses these; the window is drawn in Phase 0 for review)
	switchWindow = 0.8,
	switchDamageBonus = 0.25,
	switchGaugeBonus = 0.5,
	switchPostMotionCut = 0.2,
	tempoMaxStacks = 5,
	tempoDamagePerStack = 0.04,
	tempoDecay = 3.0,

	-- Guard and parry
	guardConeDegrees = 120,
	guardReduction = 0.7,
	shieldConeDegrees = 180,
	shieldReduction = 0.85,
	guardGaugeDrainFraction = 1.0, -- fraction of incoming gauge damage applied to the guarding player
	guardBreakStagger = 1.2,
	parryWindow = 0.15,
	parryRearmTime = 0.25, -- seconds the guard must stay down before a new raise can parry (no tap spam)
	parryStagger = 1.0,
	playerGuardGaugeBase = 100,

	-- Dodge
	dodgeDuration = 0.25,
	dodgeInvulnerability = 0.1,
	dodgeCooldown = 0.6,
	dodgeDistance = 8,

	-- Enemy telegraphs (section 6): wind-up held 0.4 to 1.2 s; the hard rule floor is 0.3
	telegraphMinWindUp = 0.3,
	telegraphDefaultWindUp = 0.4,
	telegraphMaxWindUp = 1.2,

	-- Stagger
	staggerDuration = 0.5,
	staggerDirections = 4,

	-- HP and recovery
	outOfCombatRegenDelay = 8.0,
	outOfCombatRegenPerSecond = 0.01,
	combatTagDuration = 6.0, -- seconds after the last hit before "out of combat"
	hpYellowFraction = 0.5,
	hpRedFraction = 0.25,
	lowHpMusicDuck = 6, -- dB
	basePlayerHp = 300,
	hpPerLevel = 10,

	-- Death (section 6)
	deathFreeze = 0.5, -- silence and freeze before the shatter
	deathDuckDb = 40, -- dB the Music, SFX and UI groups drop for the freeze (section 11: all sound ducked); reads as silence

	-- Server hit detection (section 6, D-010)
	hitSampleHz = 60,
	lagAllowance = 0.15,
	hitSphereRadius = HIT_SPHERE_RADIUS,
	maxTargetsPerWindow = 6,
	-- The sweep follows the blade's arc, not the 60 Hz chords (HitSweep.followArc): between two
	-- samples it adds clip-time sub-samples until neither end of the blade moves farther than this.
	-- One hit radius: every point the blade passes between two sub-samples lies within half a step
	-- of one of them, so a blade that passes through a target always touches it with half the radius
	-- to spare. tools/validators/combat.luau keeps it at or under two radii, where that margin is 0.
	-- Where the cap below leaves a step longer than this, the sweep also casts the chord of each end
	-- of the blade that moved farther (HitSweep.castBladePath). A chord cuts the corner of its end's
	-- arc, so on such a step the half-radius margin above does not hold: a target the true blade only
	-- grazes can fall between the casts, and a chord can reach a little past the true blade. The cap
	-- binds on the snap frames of the Vertical, the Rising Arc, Sharp Nail and the third basic swing
	-- (they would need 17 to 22 sub-samples); the Horizontal (12) and the first two basics fit.
	sweepMaxTipStep = HIT_SPHERE_RADIUS,
	-- Sub-samples one fighter's sweep may add in one server frame, spent where the blade moves
	-- farthest (an expo-out snap carries most of its cut in one frame). Each costs a Pose.solve, a
	-- GetPartBoundsInRadius and a Spherecast, and a step the cap leaves long up to two more casts.
	-- The frame reads the fighter's joints once (Pose.chain) and solves every sample from that
	-- read. The read walks the whole character, accessories too, and costs more than a solve; at
	-- the old cap of 4 every solve walked it again. One fighter's worst frame (a window's first
	-- frame solves its open too) is now 1 joint read, 14 solves, 14 bounds queries and up to 39
	-- casts, 3 on each of its 13 steps (24 at most on the Phase 0 clips), plus one for each
	-- fighter a cast meets; at 4 it was 6 reads, 6 solves, 6 queries and up to 15 casts. Timed in
	-- Lune on the hit matrix's body, that frame takes 2.2 to 2.8 ms, against 3.6 to 4.4 ms at 4; a
	-- cap of 16 took up to 3.7 ms, so 12 is the highest cap that is clearly cheaper. The
	-- Vertical's snap would need 22 to keep every step within sweepMaxTipStep. perf.smoke with 8
	-- stand-ins swinging Arts must stay at or under what it measured at 4 (p95 2.72 ms, max 8.27
	-- ms; the budget is world.performance.maxServerHeartbeatMs, 12 ms; docs/DECISIONS.md D-044);
	-- if it does not, use 8. The cap bounds only the sub-samples: a hitch or a rewound swing adds
	-- a solve, a query and up to three casts for each frame sample it catches up.
	sweepMaxSubdivisions = 12,
	-- A root that moved farther since the sweep's last sample than an honest body can travel has
	-- jumped (a teleport, a snap back), and the sweep does not follow it across: the frame starts
	-- a new chain at the live root (HitSweep.jumped). The bound is this speed times the time since
	-- that sample, plus what is left of the window's lag credit: this speed times lagAllowance
	-- when full (a replicated root can arrive late, then catch up in one step). A longer step
	-- spends the credit and a shorter one refills it, never above full, so the lag is spent once
	-- (the anti-cheat's rule, D-034) and a jump split over frames is not followed past it. The
	-- speed is the fastest honest travel over any span of at least lagAllowance, times
	-- sweepRootSpeedMargin: the sprint cap (maxSpeedStudsPerSecond, 24) plus the longest path any
	-- player clip's root motion carries the body in that span (a dodge: 7.0 studs in 0.15 s), 70.8
	-- studs a second, so 88.4 with the margin. tools/validators/combat.luau derives it from the
	-- clips, the dodge and the anti-cheat allowances. One 60 Hz frame with the full credit allows
	-- 15 studs; a second step at once allows 1.5 more and what the first left.
	sweepMaxRootSpeed = 90,
	sweepRootSpeedMargin = 1.25, -- how much faster than the fastest honest travel a jump must be
	facingTolerance = 0.35, -- cosine slack when comparing reported facing to the server's

	-- The strike snap's ease (section 10 "Snap (2 to 4 frames)", issue 4). A key segment eased
	-- ExpoOut that opens a hit window (a HitWindowOpen at its start) in an attack clip is a strike
	-- snap, and ClipSampler eases it with the normalized exponential (1 - 2^(-s * u)) / (1 - 2^(-s)),
	-- s = sharpness, instead of ExpoOut's 1 - 2^(-10 * u). Each 60 fps frame of a 3-frame snap then
	-- shows about half the travel of the frame before (57, 29 and 14%) where ExpoOut put 87% in the
	-- first and left 1% for the last, so the eye sees the blade arrive over the snap's frames. Only
	-- the timing along the cut changes: every pose the snap passes through, the key it lands on and
	-- the frame it lands on stay the same, on the client and in the server's sweep alike. Higher is
	-- snappier; 10 is ExpoOut again.
	snapEase = {
		sharpness = 3,
	},

	-- Local contact prediction (section 6 "Authority and feel", issue 4). While a damage window of
	-- the local fighter's own swing or Art is open, ContactPredictor sweeps the blade the trails draw
	-- (TrailStart to TrailEnd) between rendered frames and Replication.contact plays the hit's
	-- hit-stop, flash, camera and sounds on the frame it first touches an enemy's body. The server's
	-- HitConfirmed still decides the hit and brings the number. Nothing here decides damage.
	contact = {
		-- Seconds a predicted hit waits for its HitConfirmed. A confirmation later than this is a hit
		-- of its own (it plays in full); a prediction never confirmed shows no number.
		confirmSeconds = 1.0,
		-- Sub-samples one rendered frame of the local sweep may take, as sweepMaxSubdivisions does
		-- for the server's; each one solves the blade and tests it against the fighters near it, and
		-- no end of the blade moves more than sweepMaxTipStep between two of them while they last.
		maxSubdivisions = 12,
		-- A contact is predicted to kill only when the hit cannot do less than the enemy has left:
		-- its least damage (the weapon's attack times the move's multiplier, less the enemy's
		-- defense, rounded and at least minimumDamage; STR, a crit, Switch, Tempo and Break only add)
		-- reaches the enemy's replicated HP plus half a point (the attribute is rounded) plus what
		-- out-of-combat regen (outOfCombatRegenPerSecond) gives back in this many seconds. Anything
		-- the client cannot be sure of (an unknown def, an unconfirmed earlier hit) predicts no kill;
		-- the server's Kill then extends the hold from the contact frame.
		killRegenSeconds = 1.0,
	},

	-- Aim (D-112). While a lock is held and the body is free (Idle, Guard, the held Art stance), the
	-- body turns to face the target instead of the stick, and the stick strafes at walk speed. A
	-- basic swing or an Art release faces the rest of the way at once, but never more than
	-- snapDegrees (a bigger unanimated turn reads as a pop, section 10); with no lock the same snap
	-- aims at the best enemy in the assist cone. The server sweeps where the request faces and
	-- accepts a facing within acos(1 - facingTolerance) (49.46 degrees) of the root it has seen, so
	-- snapDegrees plus replicationMarginDegrees, the turn the server may not have seen yet, must fit
	-- inside it (tools/validators/combat.luau).
	aim = {
		lockTurnRate = 720, -- degrees a second the body turns toward the lock (180 in 0.25 s)
		lockFaceWhileSprinting = false, -- sprinting hands the facing back to the stick
		snapDegrees = 40, -- the most a swing or a release turns the body at once
		-- The snap as the body shows it (item 102): the request faces the whole snap the instant it
		-- is sent, but the body whips round to it over snapTurnSeconds on snapTurnEasing, a fast
		-- start that settles into the facing, so a 35-degree snap reads as a turn over five frames
		-- instead of a one-frame pop. It ends before the earliest player hit window opens (Basic1-3
		-- at 0.1 s), so the blade comes round facing its target, and no 60 fps frame shows more
		-- than half of it (tools/validators/combat.luau). A slowed capture stretches it with the
		-- clips (dev.luau timeScale).
		snapTurnSeconds = 0.08,
		snapTurnEasing = "QuadOut",
		replicationMarginDegrees = 9, -- turn the server may still be behind on when a request lands
		assistRange = 10.5, -- studs, flat, root to root: the farthest real-fight placement (10.1) and a little
		assistConeDegrees = 90, -- the whole assist cone around the body's look (45 each side)
		assistAngleWeightStuds = 6, -- assist ranking: one radian off the look costs this many studs
		minFaceDistance = 0.5, -- studs, flat: a target closer than this gives no direction to face
	},

	-- Anti-cheat basics (section 17)
	artRequestTolerance = 0.05, -- seconds early an Art may be requested before its lock ends
	maxSpeedStudsPerSecond = 24, -- sprint cap outside root motion
	-- The speed check's tolerance on the sprint cap (D-052): a sample may travel the cap times this
	-- over its interval. Physics and replication carry an honest root a little past the cap in some
	-- samples, and at no margin the lag credit drains on a long sprint and every reading past the cap
	-- is flagged (an honest 15 s sprint in Studio was kicked, 6.5 studs against 6.4). A body over the
	-- cap times the margin still drains the credit and is flagged on every sample after.
	speedMargin = 1.1,
	rootMotionSlack = 4, -- extra studs allowed while an Art carries the body
	teleportFlagDistance = 40, -- horizontal studs between two anti-cheat samples; beyond this is a teleport, not over-speed
	anomalyKickThreshold = 12, -- flags inside the window before a kick
	anomalyWindow = 30, -- seconds
	anticheatSampleInterval = 0.25, -- seconds between root position samples per player (AntiCheatService)

	-- Threat (section 6)
	threatPerDamage = 1.0,
	threatTauntMultiplier = 3.0,
	threatHealMultiplier = 0.5,

	-- Floating digits (section 14)
	digitFadeTime = 0.6,
	digitRise = 2.5,

	-- Entity lifecycle and server bookkeeping (EntityService / CombatService; D-012)
	respawnDelay = 5, -- seconds a dead player waits before the character reloads (Lucid deletion is Phase 2)
	corpseRemoveDelay = 4, -- seconds after death before an enemy model is removed (freeze + shatter + margin)
	humanoidPinnedHealth = 100, -- the engine Humanoid's Health and MaxHealth, pinned and ignored
	enemyTickHz = 20, -- enemy regen and state timers step at this rate; players step every frame
	strikeLineWidth = 4, -- studs; the width of an enemy line strike (attack arc = 0)

	-- Status effects (section 6)
	status = {
		Bleed = { duration = 8, tickInterval = 1, damageFraction = 0.02 },
		Poison = { duration = 20, tickInterval = 2, damageFraction = 0.015, blocksPotions = true },
		Paralysis = { duration = 3 },
		Stun = { duration = 1.5 },
		Burn = { duration = 5, tickInterval = 0.5, damageFraction = 0.01 },
		Freeze = { duration = 6, speedMultiplier = 0.6 },
	},
}

return Combat
