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
		-- Clips (names under locomotion.clipPrefix) that come up as this snap even with nothing
		-- live to cut (D-527, Locomotion): the guard is raised in 2 to 4 frames (section 10 beat
		-- 2) whether it cuts a basic or rises from the stance with the sword in the hand. Blended
		-- over its own 0.08 s from the stance, the arms turned 11.3 / 28.4 / 32.7 / 24.1 / 6.6
		-- degrees on the rows after the press (the owner's PC 9.5 / 29.6 / 29.8 / 25.6 / 7.7):
		-- five moving rows, three over review.audit.popDegrees. With the sword on the back, or
		-- over a Draw or a Sheathe, it keeps its blend (the sheath's limits, D-420). Not an attack
		-- (tools/validators/choreo.luau).
		snapClips = { "Guard" },
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
		-- A landing on the move (D-521): Land plays with no weight there (its sounds only), so the
		-- Fall's pose hands the legs straight to the stride. It lets go over this many seconds, as
		-- long as it took them (the Fall clip's own blendIn), not oneShotBlendIn: over 0.05 s a run
		-- landing turned a foot 24 to 39 degrees on the touch-down frame, past the stride's own 15
		-- to 33. At most landOnMoveBlendMost (tools/validators/choreo.luau).
		landOnMoveBlend = 0.15,
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
		-- A dodge that cuts nothing (D-528): pressed from the stance or a gait it was not authored
		-- from (the sheathed stance, a walk, a run), its own 0.05 s blend in crossed the arms and the
		-- stride into its first pose in two rows: up to 58.6 degrees a row on the arms and 40.2 on
		-- the legs (the owner's PC 30.9 to 60.3, before the State read Dodge). So the dodge takes
		-- each joint listed here over these seconds (Mixer.handOff); the gait's phase and blend stand
		-- where the dodge found them until it lets go (the root's dodge speed is not a run). A dodge
		-- that cuts an action keeps the cancel's snap (handOver, D-408). Each blend is done by the
		-- dodge's move end, combat.luau dodgeDuration (tools/validators/choreo.luau). The legs take
		-- 0.13 s (D-610): over 0.12 s a dodge out of the drawn run at 16 crossed the held
		-- stride's lower leg into the lean at up to 21.1 degrees on the fourth row after the press
		-- at 2 of 24 points of the stride (21.3 over the four dodges); over 0.13 s every row from
		-- the second to the let-go is at most 19.6 (tests/choreo/DodgeRun.spec.luau).
		dodgeHandOff = {
			clips = { "DodgeForward", "DodgeBack", "DodgeLeft", "DodgeRight" },
			joints = {
				Root = 0.12,
				Waist = 0.12,
				Neck = 0.12,
				LeftHip = 0.13,
				RightHip = 0.13,
				LeftKnee = 0.13,
				RightKnee = 0.13,
				LeftAnkle = 0.13,
				RightAnkle = 0.13,
				LeftShoulder = 0.18,
				LeftElbow = 0.18,
				LeftWrist = 0.18,
				RightShoulder = 0.18,
				RightElbow = 0.18,
				RightWrist = 0.18,
			} :: { [string]: number },
			-- The point of the stride (the shared gait phase, 0 at the left Footstep) a dodge that
			-- played to its end hands the legs back to the gait at (D-609). Every dodge lands in
			-- one pose, while the stride stood wherever the press found it: picked up there, the
			-- 0.15 s blend out crossed a lower leg swinging away from the landing, up to 25.2
			-- degrees a 60 Hz row out of the sheathed run at 16 (7 of 24 points of the stride over
			-- max(20, the stride's own + 1)) and 21.9 out of the drawn run. From here (the left
			-- foot down under the landing, the right swinging through) every part turns at most
			-- 15.4 there from any point (tests/choreo/DodgeRun.spec.luau; 0.18 to 0.25 all hold).
			resumePhase = 0.21,
			-- Locomotion one-shots (locomotion.clips names) a dodge takes the body from over these
			-- joints' blends, as from a stance, with the one-shot standing under it until they have
			-- come in, instead of the cancel's snap a cut action gets (D-613). Cut as an action, a
			-- turn in place took the arms and legs over handOver.seconds: a dodge pressed in the
			-- first frames of a standing turn turned the left forearm 40.9 and the left hand up to
			-- 48.9 degrees on its first 60 Hz row (the owner's PC on c78acd1, 515(b): the sheathed
			-- standing dodge to the left, its right lower leg 33.6 on the second row).
			takesFrom = { "TurnLeft", "TurnRight", "TurnLeftDrawn", "TurnRightDrawn" },
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
		-- Speed lost within stopDropSeconds that counts as "stopping" (the Skid's drop): a fall
		-- faster than stopSpeedDrop / stopDropSeconds (360 studs a second, each second) from above
		-- skidSpeedThreshold, at any frame rate (D-612). Read once an update, a drop of 6 in one
		-- 60 Hz update skidded where the same stop at 240 fps lost under 6 in each of its updates:
		-- the owner's PC at 240 fps stopped from the sprint in about 0.03 s with no Skid on 7 of
		-- 10 takes (512(b), c78acd1), at 60 fps on none.
		stopSpeedDrop = 6,
		stopDropSeconds = 1 / 60,
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
		-- A Skid that starts while a Draw or Sheathe is under way leaves that clip the arm and the
		-- sword's joint, and the clip's clock stands for the Skid's brake, its first
		-- skidBrakeSeconds (D-579). Taken over by the Skid, the arm crossed from the Sheathe's
		-- swing to the Skid's flung-back arm in 0.1 s (the tip up to 423 studs a second at 240 Hz,
		-- the owner's PC 241); left to the Sheathe but still swinging, the brake's torso (thrown
		-- back 34 degrees in 0.15 s) carried the raised blade at up to 137. Held through the brake,
		-- at most 79 (tests/choreo/SheathSkid.spec.luau).
		skidBrakeSeconds = 0.27,
		-- A plain stop or slow-down out of the run or sprint (no Skid) while a Draw or Sheathe is
		-- under way (D-611): while the base's gait falls faster than stopBrakeRate steps a second
		-- (each of stopBrakeClips, sheathed and drawn, by its shown weight times its step over the
		-- walk), the body straightening out of the run's lean, the sheath clip's clock stands, as
		-- under a Skid's brake. Swung on over the stop's blend, the Sheathe's tip read up to 94.5
		-- studs a second (the run eased off over 0.25 s, 240 Hz), 92.9 from the sprint eased off
		-- over 0.1 s and 87.5 from the run let go at 16, the blade up to 1188 degrees a second;
		-- braked, at most 79.7 and 1041 (tests/choreo/SheathStop.spec.luau). A run let go at once
		-- falls at weightBlendRate (8 steps a second), a sprint to the idle at 16; at 2 a second the
		-- brake let go mid-stop on a run eased off over 0.5 s and the swing read 84.0, at 1 it
		-- holds through it (73.3). The brake stands the clip for 0.1 to 0.4 s.
		stopBrakeClips = { Run = 1, Sprint = 2 },
		stopBrakeRate = 1,
	},

	-- Enemy attacks on the server's beat. The server pauses an enemy's unresolved attack for the
	-- hit-stop a player's hit gives it (HitConfirmed attackPause: at most ai.luau
	-- hitStop.maxPausePerAttack an attack, nothing once a rush has launched).
	enemy = {
		-- An enemy rig's gait (Locomotion.attach, D-575) is paced by its root's own flat travel over
		-- the last travelSeconds of frames, not by the replicated velocity: that under-reads the
		-- root's move (AH 401(c): 0.74-0.95 of it at 144 fps, as low as 0.08 at 60), and a gait
		-- paced short of the root slides its planted feet by the gap every frame. A step longer
		-- than enemy.rush.teleportStuds is a placement: the travel starts afresh from there. At most
		-- 1 / locomotion.weightBlendRate (tools/validators/choreo.luau), so the gait never answers a
		-- change of pace later than its own crossfade does.
		gait = {
			travelSeconds = 0.05,
			-- Where in its cycle (0 .. 1) a rig's walk steps off from standing (D-599): the walk
			-- holds there while it shows no weight, so the Idle-to-Walk crossfade starts from that pose.
			-- A walk that joins its idle at any point of its cycle pulled the planted foot from the
			-- idle's spot toward the walk's over the crossfade (up to 1.25 studs on the kobold's
			-- 2.5-stud step), 0.2 to 0.36 a 60 Hz row on rows 1 to 8, in the field to 0.087. The
			-- kobold steps off just before its left foot's mid-stance (0.115 s of 0.5, D-625): the
			-- planted sole 0.26 from the idle's left foot and the lifted right sole 0.31 ahead of the
			-- idle's right. At mid-stance (0.25) the right sole stood 0.49 ahead, and the crossfade's
			-- first 144 Hz rows dragged the idle's right foot, still on the field, toward it: 0.045 and
			-- 0.050 a 144 Hz row set off at 0 and 180 degrees, now 0.032 and 0.037 (at 60 Hz the start
			-- rows read 0.032 to 0.066, were 0.033 to 0.054; the bar is 0.1). The boar steps off
			-- at its front-left hoof's mid-stance too (0.075 s of its 0.3 s trot, D-621): its start
			-- rows (0 to 0.15 s after the root moves) read 0.056 a 60 Hz row at 90 degrees and 0.035
			-- at 144, against 0.17 / 0.07 joining at 0 and up to 0.33 / 0.15 elsewhere in its cycle,
			-- and its window holds 0.020-0.038 a 144 Hz row at every phase. A rig with none joins at
			-- any point.
			startPhase = {
				Kobold = 0.23,
				Boar = 0.25,
			} :: { [string]: number },
			-- A rig's walking-turn plant (D-619, WalkTurnPlant; tools/validators/choreo.luau): while
			-- its walk shows, each of `feet` (parts hung from their own hip joints) takes back `share`
			-- of the sweep its root's turn gives it while it is down, set out into the turn for its
			-- next stance while it is up, the hip rolling the leg at most maxRollDegrees sideways and
			-- sliding it at most maxShiftStuds along the body. A boar wheeling at the Charger's 110
			-- degrees a second on its walk slid its planted hooves 0.064 a 60 Hz row and 0.041 at
			-- 144; held, 0.025 and 0.019. 10 degrees takes the 1.8-stud leg 0.31 sideways, as far as a
			-- whole stance's turn sets a back hoof out at the trot's pace; 0.3 studs along keeps the
			-- leg inside its 0.8-stud hip.
			turnPlant = {
				Boar = {
					feet = { "FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg" },
					share = 1,
					maxRollDegrees = 10,
					maxShiftStuds = 0.3,
				},
			} :: {
				[string]: {
					feet: { string },
					share: number,
					maxRollDegrees: number,
					maxShiftStuds: number,
				},
			},
			-- A rig's stop plant (D-623, WalkStopPlant; tools/validators/choreo.luau): when its root
			-- stands under its walk, the walk's clock stops and each group of `groups` (feet hung from
			-- their own hips) holds where it stood, then steps over stepSeconds to where the idle
			-- stands it, its sole liftStuds clear of its straight path at the step's middle: every
			-- group but the lowest first (the swinging foot lands), the lowest last. A group already
			-- within settleStuds of the idle's spots glides there instead. The walk's share falls
			-- evenly to 0 over the steps. The kobold slid 0.12 / 0.24 a 60 Hz row at its stop at 0 /
			-- 90 degrees (0.100 / 0.105 at 144) and the boar 0.379 (0.166) as it stopped at 60 degrees
			-- before its Charge, with hooves to -0.036.
			stopPlant = {
				Kobold = {
					groups = { { "LeftLeg" }, { "RightLeg" } },
					stepSeconds = 0.15,
					liftStuds = 0.15,
					settleStuds = 0.1,
				},
				Boar = {
					groups = { { "FrontLeftLeg", "BackRightLeg" }, { "FrontRightLeg", "BackLeftLeg" } },
					stepSeconds = 0.15,
					liftStuds = 0.12,
					settleStuds = 0.1,
				},
			} :: {
				[string]: {
					groups: { { string } },
					stepSeconds: number,
					liftStuds: number,
					settleStuds: number,
				},
			},
			-- A root that moved less than this share of its walk's own pace over a row has braked (the
			-- server's Humanoid stops it within two frames): the stop plant takes the legs from the
			-- next row. A walking root a 144 Hz client draws steps at least 0.6 of its pace a row
			-- (511(g) on c78acd1: 0.030 to 0.066 a row at 7 studs/s).
			stopBrakeShare = 0.5,
		},
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
			-- A late root within settleStuds of where the body stood that still comes nearer it faster
			-- than this (studs a second) is still being landed by the server (D-525): the slide waits
			-- for it (its clock held, at most settleSeconds), so the body never slides back toward a
			-- root that then carries it forward again (D-602; AR 506(c): 0.024 to 0.064 back at 30
			-- fps, then forward). Under the slowest a landing root moves before the server stops it
			-- dead (ai.luau movement.landSlackStuds over landFrames 60 Hz frames: 0.6), so a root
			-- still landing never reads at rest.
			settleRestSpeed = 0.5,
			-- A replicated root that moves more than this in one step, flat, other than forward down
			-- the path, was put there (a placement, a teleport, D-553): the drawn rush is over at
			-- once and the body is drawn on its root where it now stands, never slid there. A late
			-- root catching up runs down the path (AI 423(b): 1.7 studs in one row); a placement
			-- during a charge moved it 13 to 16 studs (the PC's P3).
			teleportStuds = 4,
			-- The root part the body is drawn away from hides meanwhile (LocalTransparencyModifier).
			hiddenRootTransparency = 1,
			-- While the run, its settle, its hand-back or a frozen death draws the body away from its
			-- root, this client draws the body's Torso itself (the root joint off and the Torso
			-- anchored on this client only), so the replicated root's own move at physics carries
			-- nothing of it (D-531). False draws it through the root joint, where every row the root
			-- moves other than its velocity foretold shows on the body (AI 423).
			detachBody = true,
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
