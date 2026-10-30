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
	-- A stance the server takes away before the Art's first cut (a hit, a guard break, death:
	-- CharacterController's Stagger, GuardBroken, Break and Dead) fades out over this instead
	-- (D-340). Over locomotionBlendOut the raised stance came down past the front of the body as
	-- a cut: Sharp Nail's tip 12 studs at up to 93 studs a second, the Vertical's 17 at up to 130,
	-- with no trail, while the fighter is the one being hit. The fighter cannot act while the stance
	-- falls (at most staggerDuration), so nothing it does next plays under it.
	struckStanceBlendOut = 0.5,
	-- The fastest that fade may move the blade's tip, in studs a second, in the root part's space
	-- (tests/choreo/StanceLetGo.spec.luau): one stud a 60 Hz frame, the sword let down, not swung.
	-- The Arts' own wind-ups move it up to 35, their cuts 280 to 540.
	struckStanceTipSpeed = 60,

	-- Hit-stop in frames at 60 fps (section 6) and the camera response to each tier (section 10)
	hitStopFrames = {
		Normal = 3,
		Final = 6,
		Kill = 10,
	},
	hitStopFrameSeconds = 1 / 60,
	-- A hold asks the rig for this many frames less than its count (F6). It is 0: the rig itself
	-- ends a pause once what is left is under half of the step (Mixer, D-228 amended), which counts
	-- 3, 6 and 10 frames at 60 Hz under frame-time jitter, as half a frame short did, and the
	-- frames nearest 50, 100 and 166.7 ms at any other refresh rate (half a frame short of 1/60 cut
	-- a Normal to 41.7 ms at 120, 144 and 240 Hz).
	hitStopShaveFrames = 0,
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
	-- A fighter beside a player's swing (its root outside the aim assist's cone, aim.assistConeDegrees,
	-- around the swing's facing, read where the body stands as each window opens) is cut only where
	-- the drawn blade itself crosses its body: the blade's line (TrailStart to TrailEnd) grown by
	-- this radius, not hitSphereRadius. The hit radius stays for the enemy the swing is aimed at,
	-- the one the snap turned the body onto: it forgives the blade's reach to that enemy's body (the
	-- hit matrix's real-fight placements need it), not a cut that ends a stud short of a fighter to
	-- the side. A hair under half the one-handed blade's width (weaponModels.luau categories.
	-- OneHandedSword, 0.32): the blade's edge is in the body. The hit matrix's shoulder placements
	-- sit 0.107 and 0.194 studs from the blade's line on either side of it, so frame timing never
	-- flips one.
	besideHitRadius = 0.15,
	-- Beside the swing the blade's move between two samples follows the drawn arc: split at its
	-- middle (the clip posed there) while an end still moves farther than this and the body is near
	-- enough to touch, then taken straight in steps of besideHitRadius. Its chord then strays from
	-- the arc by under 0.01 studs, so the server's 60 Hz samples and a 30 fps client's frames agree
	-- (BladeContact.followTouch).
	besideFollowStep = 0.3,
	besideMaxSubdivisions = 16, -- arc splits of that test per fighter per sweep (server) or frame (client)
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
		-- A contact's hold on an enemy's attack stands for the pause the server will give that
		-- attack (D-172) until the HitConfirmed brings the server's own; a contact not confirmed
		-- within this many seconds of play gives it back (the server did not pause the attack), so
		-- the wind-up keeps the server's beat. A confirmation later than this still corrects it.
		allowanceSeconds = 0.4,
		-- Sub-samples one rendered frame of the local sweep may take, as sweepMaxSubdivisions does
		-- for the server's; each one solves the blade and tests it against the fighters near it, and
		-- no end of the blade moves more than sweepMaxTipStep between two of them while they last.
		maxSubdivisions = 12,
		-- Clip seconds within which a clock counts as at a key: a clock summed from 60 fps steps
		-- lands a hair short of a key written to four decimals. A touch before its strike's key
		-- waits for the first frame at or past it (F1).
		keyEpsilon = 1e-4,
		-- The server's word waits for the key too (D-267): a HitConfirmed for the local swing's hit
		-- whose strike key this client's blade has yet to show (the server counts a point-blank cut
		-- at the window's open, and runs ahead of the client by every hit-stop the client held)
		-- plays on the key frame, not on arrival; at most this many seconds of play, longer than
		-- a Normal hold still running plus a window's open to its key (a 4-frame snap) and a frame.
		-- A kill's word waits the same way, and its EntityDied with it (D-267 amended): the death's
		-- freeze, silence and shatter start on the key frame, the Kill hold on the frame after.
		wordWaitSeconds = 0.25,
		-- A contact's hold waits for its word (D-312): when the server's HitConfirmed has not come
		-- by the last frame of the contact's tier, the hold on both rigs goes on a frame at a time
		-- until it comes, at most this many seconds from the contact frame, so the server's number
		-- shows inside the freeze at up to about 0.15 s of latency (a 0.1 s lag, a frame of the
		-- engine's own and a frame of the server's tick). The frame that first shows the number is
		-- still held; a word that never comes (a refused hit, a hit past the cap) lets the rigs go
		-- with no number. At least the Kill hold, so a kill's word that comes inside it upgrades
		-- the hold in place, never as a second freeze.
		wordHoldSeconds = 0.2,
		-- The walk's body shell (item 236, WalkShell): the local character's stick walk stops where
		-- a box of its shell (rigs.luau PlayerR15.shell) would stand deeper than
		-- standOff.wallGapStuds in a solid enemy's body face or in what it holds, and slides along
		-- the rest; a walk never goes deeper than it already stands, and out is always free. The
		-- longest share of a frame's move that fits is found in this many halvings (10: within half a
		-- thousandth of a stud of a frame at the sprint cap, 0.4 studs at 60 fps).
		walkShell = { halvings = 10 },
		-- The Art stand-off (fix F1): an Art whose first cut would start with the blade already in
		-- the target's body (the review's kobold at the hip or the shoulder) steps the body straight
		-- away from the target over the anticipation, from the hold pose to the first window's
		-- open, on `easing` (a push off that settles into the start pose). The step is the least
		-- multiple of stepStuds that leaves the start pose's blade clearStuds from every part of
		-- the target a blade can hit, at most maxStuds; none when no such step clears it, or when a
		-- window's cut that passed deeper than the sweep's promise (hitSphereRadius less half of
		-- sweepMaxTipStep: every hit that deep registers) would then pass shallower, so a stand-off
		-- never costs a hit (the key rule plays a touch at the start pose on the key). Never a step
		-- in: that would add reach the Art does not have. maxStuds stays within rootMotionSlack, so
		-- the anti-cheat's mid-Art allowance covers it with any Art's own root motion, and over the
		-- shortest anticipation (0.1833 s) it is well under maxSpeedStudsPerSecond (spec StandOff).
		standOff = {
			maxStuds = 1.5,
			clearStuds = 0.25,
			stepStuds = 0.05,
			easing = "QuadOut",
			-- Samples of each damage window the reach check poses the cut at.
			reachSamples = 16,
			-- The step never goes into the world: the root's box is cast back along it (Blockcast,
			-- never meeting a character or an enemy), shrunk by this on every side so a body already
			-- touching a wall still finds it, and the body stops this far short of what it meets. A
			-- wall nearer than the step the target calls for takes the longest step that fits.
			wallGapStuds = 0.05,
			-- The keep-out (D-314): a swing's own motion (the clip's root motion, its pose, and the
			-- step above) never carries the body's colliding parts (`parts`: the R15 root, torsos and
			-- head, what the engine collides of a character) deeper into the target's blocker
			-- (D-198: its faces, the body's `bodyFace` and one `heldFace` over each part it holds,
			-- D-315) than the swing found them. The plan poses the
			-- clip every sampleSeconds from where the swing starts to its end and steps the body
			-- back along the stand-off's line (straight away from the target) as far as the pose
			-- went in (to within depthEpsilon of where it started); off a held part's face (a
			-- kobold's axe, beside a body at its front) it steps the body aside instead, square to
			-- that line, when that is the shorter step. Never forward again, so a freeze
			-- holds where the body stands. Every Art and every basic swing plans it against
			-- the aimed enemy. In Studio the engine's solver pushed a body the root motion had put
			-- 0.24-0.54 studs into a point-blank kobold's blocker back out at 0.08-0.2 studs a frame,
			-- through the hit-stop (Rising Arc's Normal hold, item 224). maxStuds caps the step above
			-- and the keep-out together (back and aside as one distance) and stays within
			-- rootMotionSlack, so the anti-cheat's mid-Art
			-- allowance covers both with any Art's own root motion (Sharp Nail's lunge at a touching
			-- kobold needs 2.9 back: its 2 studs of root motion and the head going forward into the
			-- thrust; and 0.2 aside off the axe beside it).
			keepOut = {
				parts = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head" },
				bodyFace = "Blocker", -- RigBuilder.BLOCKER_NAME
				heldFace = "HeldBlocker", -- RigBuilder.HELD_BLOCKER_NAME
				maxStuds = 3.5,
				sampleSeconds = 1 / 60,
				depthEpsilon = 0.005,
				-- Passes over the faces a sample takes to settle the back and the aside steps (a
				-- step off a held part's face can call for more back from the body's).
				rounds = 3,
				-- Each sample keeps out what the parts sweep from the one before (the hull of the two
				-- poses); a part that turns bows out past that hull, so a sample whose parts turn
				-- more than maxTurnDegrees is swept in pieces, at most maxPieces (a cut turns the torso
				-- and head up to 64 degrees a sample, Horizontal's; 10 leaves a corner 1.5 studs out
				-- within 0.006 of the hull).
				maxTurnDegrees = 10,
				maxPieces = 8,
				-- What the body shows of the keep-out and the reach (item 285): never a move back or
				-- aside faster than maxSpeedStudsPerSecond, the clip's own root motion and the blade
				-- step counted in (a lunge held still is no move), measured over speedPieces pieces of
				-- each sample, and led by leadSeconds, so each step back starts early enough to be
				-- taken at that speed. Sharp Nail's own lunge moves the root 0.2 studs a frame (12 a
				-- second); Studio read 0.44-0.64 studs a frame as a snap. Without it a basic beside
				-- the kobold's axe stepped back 0.40 studs a frame for its first three frames and
				-- Sharp Nail 0.26; the lead covers a whole stand-off step (standOff.maxStuds) at
				-- that speed.
				maxSpeedStudsPerSecond = 12,
				leadSeconds = 0.15,
				speedPieces = 4,
				-- The reach (D-424): at each strike's key (the pose its hit-stop holds) the plan
				-- holds the body back so that the blade (guard to tip) stands no deeper in any of
				-- the target's body parts (what the blade may wound) than bladeDepthStuds, or than
				-- it stood at the swing's start when a touch there put it deeper, and no hand or
				-- arm (`limbs`) deeper than it stood at the start. A step has a price: each stud
				-- of it counts as 1 / stepPerDepth of a stud of depth, and the plan takes the step
				-- of standOff.stepStuds, at most standOff.maxStuds a strike, whose price and the
				-- depth it leaves past those come to least (the least step that clears the key,
				-- unless a shorter one leaves it a hair deep for far less ground). The body takes
				-- that step over the strike's anticipation on standOff.easing, and holds it
				-- through the hit-stop; a key the keep-out's aside carries deeper once the cut has
				-- begun is posed again and takes the rest of its step in the frames left to it.
				-- The reach never carries the body back faster than maxSpeedStudsPerSecond (the
				-- aside's own step that sample counted in), and no key steps farther than that
				-- speed reaches by it: the third basic at 3.5, whose aside grows 0.34 in its cut,
				-- stepped 0.60 back in one 60 Hz frame and 1.00 in one 30 Hz frame before. The cut
				-- meets the body at its surface and never sinks to its root: at a kobold staged
				-- 3.5 studs ahead the frozen pose put Sharp Nail's right hand 0.82 into its torso
				-- at the third thrust (the left 0.82 at the second) and the blade 0.36 deep there,
				-- Rising Arc's 0.44, Vertical's 0.32 and a first basic's 0.43; every key there
				-- more than 0.01 too deep clears for 1 to 5.5 studs of ground a stud of depth.
				-- Without a price the first basic at 4.8 slid back 1.3 studs in its 0.15 s
				-- anticipation (0.72 in one 30 Hz frame) for 0.04 of depth, and Rising Arc beside
				-- a boar 1.5 for 0.03. A blade at this depth still touches the body, well inside
				-- the sweep's promise, so the hit stands (the hit matrix checks every placement).
				limbs = { "RightHand", "RightLowerArm", "RightUpperArm", "LeftHand", "LeftLowerArm", "LeftUpperArm" },
				bladeDepthStuds = 0.2,
				stepPerDepth = 8, -- unit: studs of step one stud of depth is worth
			},
		},
		-- A contact is predicted to kill only when the hit cannot do less than the enemy has left:
		-- its least damage (the weapon's attack times the move's multiplier, less the enemy's
		-- defense, rounded and at least minimumDamage; STR, a crit, Switch, Tempo and Break only add)
		-- reaches the enemy's replicated HP plus half a point (the attribute is rounded) plus what
		-- out-of-combat regen (outOfCombatRegenPerSecond) gives back in this many seconds. Anything
		-- the client cannot be sure of (an unknown def, an unconfirmed earlier hit) predicts no kill;
		-- the server's Kill then extends the hold from the contact frame.
		killRegenSeconds = 1.0,
		-- Each swing or Art release the local fighter sends carries its own sequence number
		-- (ArtRequest / BasicAttackRequest `swing`), counting up from 1 and wrapping after this, and
		-- the server echoes it on that swing's HitConfirmed: a prediction matches the swing that
		-- made it, never a quick second swing's hit on the same target, window and Art.
		swingSequenceMax = 65535,
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
		-- The whole assist cone around the body's look (40 each side): no wider than twice the snap,
		-- so a swing at an enemy inside it turns the body all the way onto it before the cut. An
		-- enemy outside it is beside the swing, and only the blade itself cuts it (besideHitRadius).
		assistConeDegrees = 80,
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
