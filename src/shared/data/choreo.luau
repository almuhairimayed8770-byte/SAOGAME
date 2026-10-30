--!strict
--[[
	Choreo tunables (section 10). Every animation number lives here: blend times, the clip clock,
	hit-stop and smear, layer priorities, quality tiers, and the whole locomotion blend space.
	Times are seconds, distances are studs, angles are degrees, rates are per second.

	Rotation convention for every clip (XYZ Euler offsets applied in the joint's parent frame,
	parts face -Z): X+ pitches the top of a part back and swings a hanging limb forward; Y+ turns
	left; Z+ rolls the top of a part to its left (a hanging right arm swings out to the right).
]]

local Choreo = {
	-- Blending (section 6: 0.2 s from the end pose back to locomotion)
	blendIn = 0.08,
	blendOut = 0.2,
	oneShotBlendIn = 0.05,
	fallbackBlend = 0.15, -- the auto Idle fades out at this rate when a real Base clip arrives
	-- Curve of every blend envelope (blend in, blend out, crossfade) as the limbs see it: no
	-- linear tween on a limb, even between clips. Symmetric, so equal crossfades keep their sum.
	blendEasing = "SineInOut",
	-- A cancel (D-408): an action that cuts a live one (the next basic, an Art or the guard out of a
	-- basic, a dodge out of a basic, the guard or an Art's start-pose hold; Mixer.play handOver)
	-- takes the body as a snap (section 10 beat 2: 2 to 4 frames, eased out, "the eye reads the
	-- pose, not the path"). The cut clip holds its pose and fades out over `seconds` while the new
	-- one fades in over the same, eased by `easing` and laid over it. At most dev.luau
	-- review.audit.cancel.snapFrames frames (tools/validators/choreo.luau).
	handOver = {
		seconds = 0.05,
		easing = "ExpoOut",
	},

	-- Clip clock
	frameSeconds = 1 / 60, -- hit-stop frame length (section 6)
	pauseEpsilon = 0.0005, -- a pause remainder below this is over (float residue after N frames)
	catchUpMaxJump = 0.25, -- a late ActionStarted starts at most this far into the clip
	minSpeed = 0.1,
	maxSpeed = 4,
	freezeClipSuffix = "DeathFreeze", -- a clip named this freezes every other clock for its duration

	-- Render stalls (D-132). RenderStepped stops while the display sleeps or the window is
	-- minimised (Heartbeat, the server and the remotes go on), and its first dt after waking is the
	-- whole gap: 5.4 to 188 s measured. A step longer than jumpSeconds is a jump: the clocks still
	-- take the whole gap (a hit-stop asked for in it ends inside it), but no root motion moves the
	-- body, and the events the gap crossed reach the listeners marked as jumped, so Replication
	-- closes what they close (trail and smear off, the light out, the post-motion) and starts
	-- nothing (no sound, footstep, chime, riser, FOV kick, trail or smear). A far rig steps on
	-- Heartbeat every 1 / farHz; tools/validators/choreo.luau keeps jumpSeconds at least twice the
	-- slowest of those steps and at most the camera's stall settleSeconds.
	stall = {
		jumpSeconds = 0.5,
	},

	-- Smear (section 10 beat 3)
	smearScale = 1.6,
	smearFrames = 2,

	-- Layer priorities: higher wins inside a layer. Clips carry their own; these are the defaults.
	priority = {
		Locomotion = 0,
		Breathing = 0,
		OneShot = 5,
		Flinch = 5,
		Sheath = 8, -- Draw and Sheathe: above locomotion, below Guard
		Guard = 10,
		Basic = 15,
		Art = 20,
		Dodge = 25,
		Stagger = 30,
		GuardBreak = 35,
		Death = 100,
	},

	-- Layer composition order; override layers first, additive last.
	layerOrder = { "Base", "UpperBody", "FullBody", "Additive" },

	-- Additive layer weights
	additiveWeights = {
		breathing = 1,
		lean = 1,
		flinch = 1,
		footIK = 1,
		drawnSprint = 1,
	},

	-- Clips the animator plays the frame a rig appears (no T-pose, ever) and keeps underneath;
	-- `walk` is the loop Locomotion.attach crossfades in by speed on a rig the server moves.
	rigs = {
		PlayerR15 = { idle = "player/OneHandedSword/Idle", breathing = "player/OneHandedSword/Breathe" },
		Boar = { idle = "enemy/Boar/Idle", walk = "enemy/Boar/Walk" },
		Kobold = { idle = "enemy/Kobold/Idle", walk = "enemy/Kobold/Walk" },
	} :: { [string]: { idle: string, breathing: string?, walk: string? } },
	-- An enemy rig's idle and walk loops start this far round the loop per entity id: the phase is
	-- the fraction part of id x step (D-123). A herd spawns with ids in a row, and the golden-ratio
	-- step puts every run of ids far apart round the loop, so neighbours never breathe, sniff or
	-- roar in step. Cosmetic and client-only: no server roll. The clips validator keeps any eight
	-- ids in a row at least a third of an even share (1 / 24 of the loop) apart.
	enemyIdlePhaseStep = 0.6180339887,

	-- Roblox Animation fallback (clip ids that look like rbxassetid://): layer -> AnimationPriority name
	rbxPriority = {
		Base = "Movement",
		UpperBody = "Action",
		Additive = "Action2",
		FullBody = "Action3",
	},

	-- Quality tiers (section 11 budgets). Near rigs update every RenderStepped; the rest on Heartbeat.
	quality = {
		High = { nearRadius = 80, maxFullRateRigs = 24, distantHz = 30, farHz = 10 },
		Medium = { nearRadius = 50, maxFullRateRigs = 12, distantHz = 20, farHz = 6 },
		Low = { nearRadius = 30, maxFullRateRigs = 6, distantHz = 12, farHz = 4 },
	},
	rankInterval = 0.5, -- seconds between distance re-ranks

	-- Where the client's render steps that pose rigs run in the frame (D-201, D-139, D-211): an
	-- Enum.RenderPriority name and an offset from its value. Every reader of a pose runs after
	-- both (camera.luau and fx.luau renderOrder), in this one order on every machine.
	renderOrder = {
		rigs = { base = "Camera", offset = -1 }, -- SkyspireRigs: Choreo's full-rate rigs (199)
		character = { base = "Character", offset = 1 }, -- the controller: local rig, root motion, contact (301)
	},

	-- Locomotion (section 10)
	locomotion = {
		walkSpeed = 8,
		runSpeed = 16,
		sprintSpeed = 24,
		idleSpeedThreshold = 0.25, -- below this the character is standing
		-- Blend-space weights: the largest mover on a layer travels this many units per second and
		-- the layer's other retargeted weights move by the same fraction, so their sum holds.
		weightBlendRate = 8,
		-- The 8-direction space: four axis clips; diagonals blend the two neighbours.
		directions = { Forward = 0, Right = 90, Back = 180, Left = 270 },
		turnInPlaceDegrees = 45,
		turnClipDuration = 0.5,
		-- A standing body's feet hold the ground while its root turns (D-416, TurnPlant): the hips
		-- keep the yaw they stood at, the Waist turns the upper body on toward the root's facing by
		-- up to twistDegrees, and the hips come round only between a turn clip's two Footsteps
		-- (the pivot foot set with a corner of its sole on the root's axis, the other foot lifted)
		-- on `easing` over that clip time, at most stepDegrees in a 60 Hz frame (dev.luau
		-- review.audit.popDegrees is the most). A lag no turn took lets go evenly over
		-- plantSeconds once the body moves off, leaves the ground or a full-body clip takes it:
		-- done by every attack's first strike key (tools/validators/choreo.luau).
		turnPlant = {
			stepDegrees = 20,
			plantSeconds = 0.12,
			twistDegrees = 45,
			easing = "SineInOut",
		},
		-- An attack that cuts a moving gait (D-404): the gait's phase stands where the attack
		-- found it until the attack lets go, and the attack takes each joint listed here over its
		-- own blend in: `seconds` (or the clip's blendIn when longer) times the joint's factor. The
		-- stride and the arm swing come into the attack's first pose over 5 to 14 frames, not
		-- the clip's 4 to 9 cut over a running body (a foot turned 31 degrees in one frame, past
		-- review.audit.popDegrees). The root goes last so the hips never swing round over planted
		-- feet; an unlisted joint (the spine, the head, the sword's grip) keeps the clip's blendIn,
		-- and a factor that leaves a joint's blend under the clip's own does nothing. Every blend is
		-- done by the attack's first strike key, where its hit is drawn (tools/validators/choreo.luau:
		-- the basics' 0.1 s base times 1.5 ends on their 0.15 s key).
		handOff = {
			seconds = 0.1,
			joints = {
				Root = 1.4,
				LeftHip = 0.9,
				RightHip = 0.9,
				LeftKnee = 1,
				RightKnee = 1,
				LeftAnkle = 0.9,
				RightAnkle = 0.9,
				LeftShoulder = 1.5,
				LeftElbow = 1.5,
				LeftWrist = 1.5,
				RightShoulder = 1.5,
				RightElbow = 1.5,
				RightWrist = 1.5,
			} :: { [string]: number },
		},
		skidSpeedThreshold = 18, -- above run speed: stopping plays Skid
		-- The two-step stop below the skid threshold: after the stick lets go the root slows down
		-- (to stopEndSpeed at the slowest) through the next Footstep at least stopMinCycles of the
		-- gait phase away, and stops where that foot is over its Idle spot (stride.touchdown).
		-- stopStepsSeconds caps it.
		stopStepsSeconds = 1.2,
		stopMinCycles = 0.2,
		stopEndSpeed = 3,
		-- A settle point this many cycles or fewer before the other foot's Footstep would hand that
		-- foot over to Idle as it comes down (a skate to its Idle spot): the stop goes on to the
		-- other foot's settle point half a cycle on instead (LocomotionState.settlePoints).
		stopHandOverCycles = 0.15,
		stopSpeedDrop = 6, -- speed lost in one update that counts as "stopping"
		-- Foot plant. groundSpeed: studs per second a gait clip's planted foot moves back under the
		-- root at rate 1, from each Footstep to lift-off, measured on the hit matrix's player at
		-- measureHz (Stride.spec.luau re-measures every clip). Locomotion paces the gait clips to
		-- the root's speed from these.
		stride = {
			groundSpeed = {
				WalkForward = 3.5,
				WalkBack = 3,
				WalkLeft = 3.2,
				WalkRight = 3.2,
				Run = 15.98,
				Sprint = 24.12,
				WalkForwardDrawn = 3.5,
				WalkBackDrawn = 2.99,
				WalkLeftDrawn = 3.2,
				WalkRightDrawn = 3.2,
				RunDrawn = 15.99,
				SprintDrawn = 24.06,
			},
			groundSpeedTolerance = 0.05, -- studs per second the measurement may drift from groundSpeed
			measureHz = 240,
			contact = 0.02, -- a foot corner this close to the ground counts as planted (studs)
			rateFloor = 0.25, -- slowest a walk plays; below it Idle takes weight and the steps shorten
			rateCeiling = 3, -- fastest a gait plays past its ground speed (a 0.9 s walk: 6.7 steps a second)
			minGroundSpeed = 0.25, -- floor of a walk blend's ground speed along the move
			-- The shared phase a start steps off from (0 is every gait clip's left Footstep, 0.5 its
			-- right one): it holds there while no gait clip shows.
			startPhase = 0.5,
			-- Degrees a second: a facing turning faster than this is turning to the move (a reversal),
			-- so Run and Sprint keep carrying a move behind it. Lock-on circling turns slower. The
			-- lock's acquisition turn (combat.luau aim.lockTurnRate, D-112) is faster for at most a
			-- quarter second, at the walk speed a body facing its lock is held to.
			turnYawRate = 300,
			-- Most a planted foot may slide in one stance (studs): a tenth of the foot's length,
			-- under a 60 Hz frame of travel at a walk, so a plant reads as planted at 0.25x.
			slideBar = 0.1,
			-- Most a plant may slide through a change of gait (a start, the set crossfade, the
			-- two-step stop and its hand-over to Idle): the clips have the feet in different places
			-- at one phase, and pacing takes up most but not all of it (measured worst: 0.28).
			-- Under a third of the foot's length: the foot pivots, it never skates.
			transientBar = 0.3,
			-- On the engine's own steps (60 Hz rendered frames, the root moved in whole 1/240 s
			-- physics steps; item 282, D-334): a foot is flat while its centre is within flatBand
			-- of its height standing, and while flat it moves no more than frameBar between two
			-- rendered frames (a SineInOut key slows a limb at both ends, so a planted foot weaves
			-- about its line by a tenth of the ground between keys) and no more than slideBar over
			-- the whole time it is flat. A third of a pixel-wide shimmer on a 1080p side shot.
			flatBand = 0.09,
			frameBar = 0.04,
			-- Seconds the walks take to carry a held move alone (LocomotionState.heldShare, D-292)
			-- once its speed comes down to them: a run's two-step stop passes walkSpeed in a tenth
			-- of a second and hands the run to the walk by cadence as it slows (a quicker swap moves
			-- the planted foot faster than the phase can take up), while a body a lock or Guard
			-- holds to walkSpeed is on its walks alone within a step or two. Falling, it is at once.
			heldRiseSeconds = 0.4,
			-- Seconds of travel at the speed the root's own travel may run ahead of (or behind)
			-- what its speed carries and still move the gait phase (D-334). The
			-- engine moves the root in whole 1/240 s physics steps, two to six to a rendered
			-- frame, while its velocity reads steady: a frame's travel is a step or two off
			-- speed x dt, and the phase takes that up so the planted foot holds the ground. Four
			-- physics steps of headroom; a teleport or a shove past it is dropped.
			travelSlipSeconds = 1 / 30,
			-- The running difference forgets itself over this many seconds (D-411): a root that
			-- travels a lasting fraction off the speed it reads (0.6% in the owner's own run log)
			-- held it at travelSlipSeconds after about 5.5 s, and from then on every long physics
			-- frame went uncompensated (a flat foot moved 0.15 studs a frame at sprint). With it, a
			-- 0.6% bias holds the difference at 0.15% of a second of travel, a twentieth of the
			-- bound, and each frame's own step is still taken up whole.
			travelSlipDecaySeconds = 0.25,
			-- A body held off its stick (D-144): walking into an enemy or a wall, or slid along its
			-- flank. Once the stick has stayed within `degrees` of one direction for
			-- `settleSeconds` (a turn swings the root's velocity across after the stick; a pan
			-- faster than degrees / settleSeconds never settles), a root velocity more than
			-- `degrees` from both this frame's stick and the last one's (the engine moves the root
			-- a frame behind the stick) marks the body blocked. It stays blocked until the stick
			-- lets go, the body leaves the ground, or the velocity runs along the stick again at a
			-- whole walk (the speed from which the walk shows alone, at rateFloor). Blocked, the
			-- gait goes the way of the root's velocity smoothed over `followSeconds` (from zero at
			-- the block), paced by the root's speed along it, and stands while that smoothed
			-- velocity is under idleSpeedThreshold: a jostle never walks the body in place.
			-- `matchSpeed`: studs a second the root's velocity may differ from the speed the
			-- caller gave and still be the reading that speed came from (else nothing is blocked).
			blocked = { degrees = 3, settleSeconds = 0.2, followSeconds = 0.15, matchSpeed = 0.01 },
			-- Where each clip has its feet (studs from the root: forward, right): a gait clip at
			-- that foot's Footstep, an Idle at its start. From the Footstep a gait clip's foot moves
			-- straight back along its axis at its ground speed. When the weights change (a start, a
			-- stop, the set crossfade, a gait handing over), each clip pulls the planted foot
			-- toward its own spot; Locomotion moves the phase to take that up.
			touchdown = {
				Idle = { left = { -0.039, -0.564 }, right = { -0.17, 0.564 } },
				IdleDrawn = { left = { 0.14, -0.662 }, right = { -0.726, 0.659 } },
				WalkForward = { left = { 0.756, -0.421 }, right = { 0.756, 0.421 } },
				WalkBack = { left = { -0.777, -0.419 }, right = { -0.778, 0.419 } },
				WalkLeft = { left = { -0.001, -1.079 }, right = { 0.001, 0.17 } },
				WalkRight = { left = { 0.001, -0.17 }, right = { -0.001, 1.079 } },
				Run = { left = { 0.144, -0.361 }, right = { 0.146, 0.36 } },
				Sprint = { left = { 0.1, -0.319 }, right = { 0.1, 0.319 } },
				WalkForwardDrawn = { left = { 0.757, -0.418 }, right = { 0.757, 0.418 } },
				WalkBackDrawn = { left = { -0.779, -0.419 }, right = { -0.779, 0.419 } },
				WalkLeftDrawn = { left = { -0.001, -1.079 }, right = { 0.001, 0.17 } },
				WalkRightDrawn = { left = { 0.001, -0.17 }, right = { -0.001, 1.079 } },
				RunDrawn = { left = { 0.146, -0.36 }, right = { 0.145, 0.36 } },
				SprintDrawn = { left = { 0.1, -0.32 }, right = { 0.1, 0.32 } },
			} :: { [string]: { left: { number }, right: { number } } },
			touchdownTolerance = 0.01, -- studs the measurement may drift from touchdown
		},
		landing = { minSquash = 0.3, fullSquashHeight = 10, clipDuration = 0.45 },
		jumpVelocity = 2, -- vertical speed above which airborne reads as Jump, not Fall
		idleCycle = 12,
		breathing = { amplitude = 1, cycle = 3.6 }, -- degrees of chest rise; the Breathe clip carries it
		lean = { -- lean into turns from the yaw rate
			degreesPerYawRate = 0.04,
			max = 10,
			rate = 10,
			neckCounterFraction = 0.5, -- share of the waist lean the head cancels
			-- Clips that hold the torso upright, each with the side of the lean it holds back (1 a
			-- lean to the left, -1 to the right): Locomotion scales that lean by one minus the
			-- clip's shown weight. The drawn left walk steps its left leg out under the scabbard's
			-- lower end, and the waist rolling left would put the scabbard into that leg in a drawn
			-- left turn (TurnClearance.spec.luau).
			upright = { WalkLeftDrawn = 1 } :: { [string]: number },
		},
		drawnSprintPose = { -- additive "weapon low and back" on top of SprintDrawn
			RightShoulder = { rot = { -40, 0, 18 } },
			RightElbow = { rot = { 20, 0, 0 } },
			RightWrist = { rot = { -10, 0, 0 } },
			Weapon = { rot = { 25, 0, 0 } },
		},
		footIK = {
			rayLength = 3, -- studs below the hip the foot ray reaches
			rayStart = 1, -- studs above the foot the ray starts
			maxAdjust = 0.8, -- the most a foot or the pelvis moves
			thighLength = 1.5,
			shinLength = 1.5,
			fadeSpeed = 6, -- IK fades out as speed rises toward this
			footSpacing = 0.5, -- half the distance between the feet, from the root
		},
		-- Clip name -> clip id suffix under player/OneHandedSword. The plain walk, run and sprint
		-- names are the sheathed set (empty hands); the ...Drawn names are the drawn set.
		clips = {
			Idle = "Idle",
			IdleDrawn = "IdleDrawn",
			WalkForward = "WalkForward",
			WalkBack = "WalkBack",
			WalkLeft = "WalkLeft",
			WalkRight = "WalkRight",
			Run = "Run",
			Sprint = "Sprint",
			WalkForwardDrawn = "WalkForwardDrawn",
			WalkBackDrawn = "WalkBackDrawn",
			WalkLeftDrawn = "WalkLeftDrawn",
			WalkRightDrawn = "WalkRightDrawn",
			RunDrawn = "RunDrawn",
			SprintDrawn = "SprintDrawn",
			Jump = "Jump",
			Fall = "Fall",
			Land = "Land",
			TurnLeft = "TurnLeft",
			TurnRight = "TurnRight",
			-- Over the drawn stance (D-416): Locomotion plays these when the drawn idle shows.
			TurnLeftDrawn = "TurnLeftDrawn",
			TurnRightDrawn = "TurnRightDrawn",
			Skid = "Skid",
		},
		clipPrefix = "player/OneHandedSword/",
	},

	-- The sheathed weapon (weaponModels.luau sheaths): the server's Drawn attribute says where the
	-- sword should be; each client plays Draw and Sheathe and moves the sword between hand and back.
	sheath = {
		clips = { draw = "Draw", sheathe = "Sheathe" }, -- suffixes under locomotion.clipPrefix
		-- These clips start with the sword in the hand (a draw-cut), as every clip with `attack` does.
		drawCutClips = { "Guard", "GuardHit", "Parry" },
		-- Of those, the guard's: raised with the sword on the back, the blade would come off the back
		-- in one frame while the arm hangs at the side (6.2 studs in a 240 Hz step). So the Draw
		-- plays over them instead (SheathState, D-420), at overPriority: above every one of them
		-- (Guard 10, GuardHit 12), below Parry (14) and the attacks, which still draw-cut. Once its
		-- clock passes handOverTime (the blade over the shoulder, past WeaponDraw) it blends out
		-- over handOverBlend into the guard's own pose: the tip at most 71.3 studs a second over 48
		-- points of a gait's cycle, the guard raised 0 to 0.7 s after the flip, at 240 Hz (it was
		-- 1665: tests/choreo/SheathTip.spec.luau, the guard cases).
		drawFirstClips = { "Guard", "GuardHit" },
		overPriority = 13,
		handOverTime = 0.445,
		handOverBlend = 0.25,
		predictSeconds = 1.5, -- the local player shows drawn this long after sending a combat request, until the attribute lands
		sheatheDelay = 0.3, -- Drawn must stay false this long before the Sheathe clip starts
		stopBlend = 0.1, -- blend-out of a Draw or Sheathe that a draw-cut or a cover cuts short
		-- Blend-out of a Draw or Sheathe the target turned away from (a lock-on mid-Sheathe, a fight
		-- that ends mid-Draw): nothing hides the arm, so the pose comes back under drawTipSpeed and
		-- sheatheTipSpeed (tests/choreo/SheathTip.spec.luau, the cut-back cases). At stopBlend the
		-- blade swung back at up to 347 studs a second.
		cutBackBlend = 0.45,
		-- A remote rig's Drawn rise counts only after this long (SheathState.riseFilter): the
		-- attribute can land up to three 60 Hz frames before the unreliable ActionStarted of the
		-- attack that set it, which then draw-cuts with no Draw flashing in first.
		remoteDrawDelay = 0.06,
		-- How fast Draw and Sheathe may move the blade, so each swing reads as a whip and never as a
		-- jump. Measured as the client plays them (tests/choreo/SheathTip.spec.luau: SheathState,
		-- the mixer's blends over locomotion and WeaponMount's swap, on the hit matrix's player), in
		-- the root part's space the camera follows, every 60 Hz frame and every 240 Hz sample,
		-- standing, walking, running and sprinting; and with each clip posed alone over its base
		-- (GroundClearance). The tip, in studs a second: 84 is 1.4 studs a 60 Hz frame and 2.3 in a
		-- 9 fps window capture of the 0.25x review. Studio read 3.37 studs in a frame (Draw dropping
		-- from straight up to the guard) and 1.72 (Sheathe's point swinging down into the mouth) as
		-- jumps, and the 2.74 before that.
		drawTipSpeed = 84,
		sheatheTipSpeed = 84,
		-- Over a moving base Studio reads the tip faster than the Lune path does: a Draw at a sprint
		-- read 1.44 studs in a rendered frame where the path read at most 1.36 (81.7 studs a second
		-- at the worst point of the sprint's cycle), 6% more; standing and running the two agree
		-- within 2%. So a Draw over a walk, a run or a sprint, flipped at any point of the gait's
		-- cycle, keeps under drawTipSpeed times this on the path (SheathTip.spec, D-293), and
		-- under drawTipSpeed in Studio.
		movingTipShare = 0.92,
		-- The blade's line, in degrees a second: 18 degrees a 60 Hz frame. Sheathe's jump turned it
		-- 24.8 in a frame, Draw's 36.4.
		bladeTurnRate = 1080,
	},

	-- Enemy attacks on the server's beat. The server pauses an enemy's unresolved attack for the
	-- hit-stop a player's hit gives it (HitConfirmed attackPause: at most ai.luau
	-- hitStop.maxPausePerAttack an attack, nothing once a rush has launched).
	enemy = {
		-- The attack clip ActionStarted plays keeps that beat up to its first HitWindowOpen (D-172):
		-- the rig's hit-stop is the only freeze, and what it held beyond the server's pause (or
		-- short of it) the clip evens by running at most maxRate (at least minRate) of its speed,
		-- at the one rate that evens it by the mark.
		beat = {
			maxRate = 2,
			minRate = 0.5,
		},
		-- A rush drawn on the server's timeline (D-171, RushDraw): the body is drawn where the
		-- launch, the speed and the line say it is while the replicated root catches up behind it.
		rush = {
			-- Each frame the drawn body moves the timeline's own travel give or take this fraction of
			-- a frame's travel at the rush speed while it closes on the timeline (no jump), and an
			-- offset off the line closes at the same pace.
			catchUpFraction = 0.5,
			turnRate = 720, -- degrees a second the drawn body turns onto the line
			-- The hand-back: once the run is over the body waits until the replicated root is this
			-- close to where the server's body stopped (or this long), then slides onto the root over
			-- at least handBackSeconds (more for a longer way, at the catch-up pace) on handBackEasing.
			settleStuds = 0.5,
			settleSeconds = 0.6,
			handBackSeconds = 0.2,
			handBackEasing = "QuadOut",
			-- The root part the body is drawn away from hides meanwhile (LocalTransparencyModifier).
			hiddenRootTransparency = 1,
			-- The pass (RushDraw.pass): the server's body runs through a player in its path (D-167),
			-- the drawn one shoulders past it. Its path swings off the line from leadStuds before
			-- its snout meets the body, so the snout still meets it (the blow lands on the body's
			-- side), to the full clearance (the drawn body's half width + the body's radius +
			-- marginStuds) fullStuds after; it holds that until its tail is past the body, then comes
			-- back onto the line by the run's end, so it rests where the server's body stops. A body
			-- within centreStuds of the line's middle is passed on the rusher's right; a body the run
			-- cannot get past with at least returnStuds left to come back is not passed. The body's
			-- radius is its root's half width, the torso's; marginStuds is about an arm's width more
			-- (an R15 arm hangs a stud outside the torso), so the flank clears the hanging arm too.
			pass = {
				leadStuds = 2,
				fullStuds = 6,
				marginStuds = 0.9,
				centreStuds = 0.5,
				returnStuds = 3,
			},
		},
	},

	-- Reactions. A directional flinch on an enemy whose attack clip is still before its
	-- PostMotionStart (the wind-up and the strike) plays with these per-joint weights (D-173): the
	-- weapon arm stays on the attack, so the flinch never dips the weapon into a false strike.
	-- A joint not listed, a rig not listed and every flinch outside an attack keep full weight.
	reaction = {
		attackFlinch = {
			Kobold = { RightShoulder = 0, Weapon = 0, Root = 0.35 },
		} :: { [string]: { [string]: number } },
	},
}

return Choreo
