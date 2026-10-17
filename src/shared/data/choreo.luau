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
		idleSpeedThreshold = 0.5, -- below this the character is standing
		weightBlendRate = 8, -- blend-space weights move this many units per second
		-- The 8-direction space: four axis clips; diagonals blend the two neighbours.
		directions = { Forward = 0, Right = 90, Back = 180, Left = 270 },
		turnInPlaceDegrees = 45,
		turnClipDuration = 0.4,
		skidSpeedThreshold = 18, -- above run speed: stopping plays Skid
		stopStepsSeconds = 0.3, -- the two-step stop below the skid threshold
		stopSpeedDrop = 6, -- speed lost in one update that counts as "stopping"
		landing = { minSquash = 0.3, fullSquashHeight = 10, clipDuration = 0.45 },
		jumpVelocity = 2, -- vertical speed above which airborne reads as Jump, not Fall
		idleCycle = 12,
		breathing = { amplitude = 1, cycle = 3.6 }, -- degrees of chest rise; the Breathe clip carries it
		lean = { degreesPerYawRate = 0.04, max = 10, rate = 10 }, -- lean into turns from the yaw rate
		drawnSprintPose = { -- additive "weapon low and back" on top of Sprint when drawn
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
		clips = { -- clip name -> clip id suffix under player/OneHandedSword
			Idle = "Idle",
			IdleDrawn = "IdleDrawn",
			WalkForward = "WalkForward",
			WalkBack = "WalkBack",
			WalkLeft = "WalkLeft",
			WalkRight = "WalkRight",
			Run = "Run",
			Sprint = "Sprint",
			Jump = "Jump",
			Fall = "Fall",
			Land = "Land",
			TurnLeft = "TurnLeft",
			TurnRight = "TurnRight",
			Skid = "Skid",
		},
		clipPrefix = "player/OneHandedSword/",
	},
}

return Choreo
