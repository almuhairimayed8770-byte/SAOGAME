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

	-- Clip clock
	frameSeconds = 1 / 60, -- hit-stop frame length (section 6)
	pauseEpsilon = 0.0005, -- a pause remainder below this is over (float residue after N frames)
	catchUpMaxJump = 0.25, -- a late ActionStarted starts at most this far into the clip
	minSpeed = 0.1,
	maxSpeed = 4,
	freezeClipSuffix = "DeathFreeze", -- a clip named this freezes every other clock for its duration

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
		turnClipDuration = 0.4,
		skidSpeedThreshold = 18, -- above run speed: stopping plays Skid
		-- The two-step stop below the skid threshold: after the stick lets go the root slows down
		-- (to stopEndSpeed at the slowest) through the next Footstep at least stopMinCycles of the
		-- gait phase away, and stops where that foot is over its Idle spot (stride.touchdown).
		-- stopStepsSeconds caps it.
		stopStepsSeconds = 1.2,
		stopMinCycles = 0.2,
		stopEndSpeed = 3,
		stopSpeedDrop = 6, -- speed lost in one update that counts as "stopping"
		-- Foot plant. groundSpeed: studs per second a gait clip's planted foot moves back under the
		-- root at rate 1, from each Footstep to lift-off, measured on the hit matrix's player at
		-- measureHz (Stride.spec.luau re-measures every clip). Locomotion paces the gait clips to
		-- the root's speed from these.
		stride = {
			groundSpeed = {
				WalkForward = 3.49,
				WalkBack = 3,
				WalkLeft = 1.46,
				WalkRight = 1.46,
				Run = 15.55,
				Sprint = 23.31,
				WalkForwardDrawn = 3.47,
				WalkBackDrawn = 2.99,
				WalkLeftDrawn = 0.69,
				WalkRightDrawn = 0.69,
				RunDrawn = 14.37,
				SprintDrawn = 20.73,
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
			-- so Run and Sprint keep carrying a move behind it. Lock-on circling turns slower.
			turnYawRate = 300,
			-- Most a planted foot may slide in one stance (studs): a tenth of the foot's length,
			-- under a 60 Hz frame of travel at a walk, so a plant reads as planted at 0.25x.
			slideBar = 0.1,
			-- Most a plant may slide through a change of gait (a start, the set crossfade, the
			-- two-step stop and its hand-over to Idle): the clips have the feet in different places
			-- at one phase, and pacing takes up most but not all of it (measured worst: 0.28).
			-- Under a third of the foot's length: the foot pivots, it never skates.
			transientBar = 0.3,
			-- Where each clip has its feet (studs from the root: forward, right): a gait clip at
			-- that foot's Footstep, an Idle at its start. From the Footstep a gait clip's foot moves
			-- straight back along its axis at its ground speed. When the weights change (a start, a
			-- stop, the set crossfade, a gait handing over), each clip pulls the planted foot
			-- toward its own spot; Locomotion moves the phase to take that up.
			touchdown = {
				Idle = { left = { -0.039, -0.564 }, right = { -0.17, 0.564 } },
				IdleDrawn = { left = { 0.14, -0.662 }, right = { -0.726, 0.659 } },
				WalkForward = { left = { 0.791, -0.423 }, right = { 0.791, 0.423 } },
				WalkBack = { left = { -0.777, -0.419 }, right = { -0.778, 0.419 } },
				WalkLeft = { left = { 0, -1.187 }, right = { 0.001, 0.428 } },
				WalkRight = { left = { 0.001, -0.428 }, right = { 0, 1.187 } },
				Run = { left = { 0.091, -0.362 }, right = { 0.09, 0.362 } },
				Sprint = { left = { 0.1, -0.319 }, right = { 0.1, 0.319 } },
				WalkForwardDrawn = { left = { 0.512, -0.599 }, right = { 0.512, 0.599 } },
				WalkBackDrawn = { left = { -0.779, -0.419 }, right = { -0.779, 0.419 } },
				WalkLeftDrawn = { left = { -0.079, -1.088 }, right = { -0.319, -0.037 } },
				WalkRightDrawn = { left = { -0.319, 0.037 }, right = { -0.08, 1.088 } },
				RunDrawn = { left = { 0.738, -0.637 }, right = { 0.738, 0.637 } },
				SprintDrawn = { left = { 0.873, -0.678 }, right = { 0.873, 0.678 } },
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
		predictSeconds = 1.5, -- the local player shows drawn this long after sending a combat request, until the attribute lands
		sheatheDelay = 0.3, -- Drawn must stay false this long before the Sheathe clip starts
		stopBlend = 0.1, -- blend-out of a Draw or Sheathe that is cut short
		-- A remote rig's Drawn rise counts only after this long (SheathState.riseFilter): the
		-- attribute can land up to three 60 Hz frames before the unreliable ActionStarted of the
		-- attack that set it, which then draw-cuts with no Draw flashing in first.
		remoteDrawDelay = 0.06,
	},
}

return Choreo
