--!strict
--[[
	Camera numbers (section 10). Third person, a spring-damped follow with 0.12 s lag, 60-degree
	FOV at rest, +8 degrees on Art activation and dashes, a 0.4-stud nudge toward every hit, shake
	amplitude 0.15 / 0.3 / 0.6 studs for the three hit-stop tiers, lock-on framing that keeps both
	fighters in view, a low tight orbit in duels, a high wide orbit in raids. Mobile uses the same
	system with wider defaults.

	The free camera sits low over the right shoulder: it aims `side` studs right of and `height`
	studs above the pivot, so the player stands left of center with the way ahead open, and its
	look-down is exactly its pitch. A lock frames the two fighters side by side (a two-shot): the
	camera stands a little over their heads behind the player, swung off the line just far enough
	that the target is never behind the player on screen, and aims between them. The follow lags
	on a spring but is leashed along the view, so a dodge toward the camera never brings the lens
	onto the player and the view never tilts with it (D-145, D-146, D-149).

	The punch (the reel's push in on the big hit): an Art's final hit and a kill narrow the FOV by
	a few degrees, eased in inside the hit-stop, then spring back past rest a little and settle.
	It rides on top of the FOV spring, so the Art and dash kicks and the shake are untouched.

	The nudge and shake amplitudes are section 6 numbers already in combat.luau; this table points
	at them so there is one source. Angles are degrees, distances are studs, times are seconds.
	Conventions used by CameraMath: yaw 0 puts the camera behind a rig that faces -Z; pitch is the
	camera's elevation above the focus (positive looks down on the fighters).
]]

local Combat = require(script.Parent.combat)
local Fx = require(script.Parent.fx)

-- One FOV punch (CameraMath.punchOffset). Named by the hit-stop tier it lands on.
export type Punch = {
	degrees: number, -- FOV narrowing at the peak
	attack: number, -- seconds to the peak, eased out (fast push, soft arrival); inside the tier's hit-stop
	settle: number, -- seconds the spring takes from the peak to within `band` of rest
	damping: number, -- spring damping ratio; under 1 it springs a little past rest before it settles
	band: number, -- fraction of `degrees` the spring is inside by `settle`
}

export type Orbit = {
	distance: number, -- studs from the point the camera aims at back to the camera
	height: number, -- studs above the focus the camera aims (and so sits)
	side: number, -- studs right of the focus the camera aims (and so sits): over the right shoulder
	pitch: number, -- degrees of elevation: the camera's look-down
}

local Camera = {
	follow = {
		lag = 0.12, -- seconds; the position spring's time constant (1 / omega)
		damping = 1.0, -- critical: the follow never overshoots on its own
		focusHeight = 1.5, -- studs above the root part: the pivot the rigs are built on (chest)
		snapDistance = 60, -- a subject jump bigger than this (teleport, respawn) snaps the spring
		-- The lagged pivot is held this close to the true one along the view: `closer` studs ahead
		-- of it (the lens nearer the player: a dodge back) and `further` behind it (a dash away)
		-- (D-149); and `side` studs either way across the view, so a sideways dodge never carries
		-- the player toward the screen's edge (D-181; at least nudge.studs, so a hit's nudge still
		-- shows). Vertical lag is left alone.
		leash = {
			closer = 0.75,
			further = 2.5,
			side = 1.0,
		},
	},

	fov = {
		rest = 60,
		artKick = 8, -- added on Art activation
		dashKick = 8, -- added on dodges and dashes
		kickDecay = 6, -- per second; the kick fades exponentially, never linearly
		lag = 0.08, -- seconds; the FOV spring's time constant
		damping = 1.0,
	},

	nudge = {
		studs = Combat.cameraNudgeStuds, -- peak displacement of the impulse toward the hit point
	},

	-- The push in on the big hit. Each attack lands inside its tier's hit-stop (6 and 10 frames),
	-- so the narrowing reads on the frozen frame and the spring back plays as the fight resumes.
	punch = {
		Final = {
			degrees = 3,
			attack = 3 * Combat.hitStopFrameSeconds,
			settle = 0.3,
			damping = 0.55,
			band = 0.02,
		} :: Punch,
		Kill = {
			degrees = 5,
			attack = 4 * Combat.hitStopFrameSeconds,
			settle = 0.45,
			damping = 0.5,
			band = 0.02,
		} :: Punch,
	} :: { [string]: Punch },

	shake = {
		amplitude = Combat.cameraShakeStuds, -- per hit-stop tier
		decay = 14, -- per second; exponential fall-off of the shake energy
		frequency = 23, -- Hz; base frequency of the noise
		-- Three incommensurate sine lanes summed per axis so the shake never repeats or reads as a
		-- linear wobble: {frequency multiplier, phase offset in radians}.
		lanes = { { 1.0, 0.0 }, { 0.731, 1.7 }, { 1.318, 2.9 } },
		cutoff = 0.004, -- studs; energy below this is zeroed
	},

	-- Orbit presets. Default is the field camera, low over the right shoulder; Duel is lower and
	-- tighter; Raid is high and wide.
	orbit = {
		Default = { distance = 10, height = 0.8, side = 2.5, pitch = 8 } :: Orbit,
		Duel = { distance = 8, height = 0.6, side = 1.25, pitch = 4 } :: Orbit,
		Raid = { distance = 22, height = 6, side = 0, pitch = 28 } :: Orbit,
	},

	pitch = {
		min = -20, -- camera below the focus looking up
		max = 75, -- camera nearly overhead
	},

	zoom = {
		min = 6,
		max = 24,
		step = 1.5, -- studs per mouse-wheel notch
	},

	input = {
		mouseDegreesPerPixel = 0.22,
		gamepadDegreesPerSecond = 160,
		gamepadDeadzone = 0.18,
		touchDegreesPerPixel = 0.3,
		invertY = false,
	},

	lock = {
		range = 60, -- studs; candidates further than this are not offered
		coneDegrees = 120, -- in front of the camera
		breakDistance = 80, -- the lock clears beyond this
		angleWeightStuds = 20, -- ranking: one radian of off-center angle costs this many studs
		-- The two-shot (CameraMath.twoShot). Distances are flat studs from the player's root.
		baseDistance = 9,
		minDistance = 8,
		maxDistance = 16,
		distancePerSeparation = 0.25, -- camera distance grows with the fighters' separation
		height = 3.7, -- studs above the player's root: a little over the fighters' heads
		focusBias = 0.5, -- the aim: 0 at the player, 1 at the target; the midpoint is 0.5
		lookHeight = 1.3, -- studs above the line between the roots the camera aims
		-- Half widths (studs) kept apart on screen: the target never stands behind the player.
		playerClearance = 1.6,
		targetClearance = 1.4,
		maxOrbitDegrees = 65, -- the widest swing off the line behind the player (fighters on top of each other)
		sideHysteresis = 15, -- degrees past the line the camera must be before it changes shoulders
		solveSteps = 20, -- bisection steps for the swing (65 / 2^20 degrees)
		yawLag = 0.2, -- seconds; the two-shot eases onto its bearing, distance and aim
		blendLag = 0.12, -- seconds; the shot eases between the free camera and the two-shot
		-- Close fights (F3). Toe to toe no swing stands two bodies apart on screen, and from behind
		-- the player's hat and coat cover the target and the blade; the shot turns to a
		-- three-quarter view of both instead, a little lower. How close is the flat gap from the
		-- player's root to the target's footprint: its blocker (D-198), which covers the body's
		-- rest silhouette, else its root part. At or under closeGap the shot is fully close, from
		-- openGap out not at all, eased between (CameraMath.closeness) and on the yaw spring.
		footprintPart = "Blocker", -- RigBuilder.BLOCKER_NAME (a spec keeps the two the same)
		closeGap = 1.5, -- studs: an arm's length, toe to toe
		openGap = 4.5, -- studs: past a lunge, the two-shot solves its swing alone
		closeSwingDegrees = 80, -- the close shot's least swing off the line behind the player
		closeHeight = 2.7, -- studs above the player's root: about head height, under a hat's brim
		-- The bearing never turns faster than this (degrees per second): a target running past the
		-- player, or two fighters circling toe to toe, swing the shot as a fast pan, never a whip
		-- (issue 12, issue 22). Below it the yaw spring eases as before; only a whip is capped.
		maxTurnDegreesPerSecond = 150,
		-- The aim never comes nearer the lens than this fraction of the player's depth along the
		-- view: a target that ran past to the camera's side would pull the midpoint in under it, a
		-- look straight down onto the player's hat (issue 12).
		aimDepthFraction = 1,
		-- The catch-up (a rush pass): once a target that was on screen is more than catchUpMargin
		-- of the half width past the screen's side, the turn cap lifts to catchUpDegreesPerSecond
		-- (7 degrees a 60 fps frame, and never more than catchUpMostDegrees in a longer frame),
		-- eased on and off over catchUpEase seconds, and the bearing pans straight at its mark
		-- until the target is back inside that margin. A target that only grazes the edge, or a
		-- new lock behind the camera, keeps the cap above.
		catchUpDegreesPerSecond = 420,
		catchUpMostDegrees = 7,
		catchUpMargin = 0.25,
		catchUpEase = 0.05,
		-- A death's still shot (F4, D-239): after the freeze (CameraController.holdLock) the shot
		-- stays still this long more, the shards' rise (fx.luau shatter.duration), framing where
		-- the body stood, and only then eases out to the free camera. A boss's longer rise eases
		-- out over its last part.
		riseHoldSeconds = Fx.shatter.duration,
		-- The still shot is still (D-323): from its first frame no spring moves it, and the kill's
		-- shake and nudge do not play on it; it moves only with the body (rigidly) and the FOV punch.
		-- A deliberate look lets it go at once (D-324): look input adding up to this many degrees
		-- while it holds (a flick of the mouse, a push of the stick), not a twitch.
		lookBreakDegrees = 4,
		-- A wall at the camera's shoulder: once a wall leaves the camera under wallBlockedFraction
		-- of its reach, and the other shoulder's spot opens at least wallGainFraction more of its
		-- own, the shot swings over to the open side (a pan at the turn cap) instead of standing
		-- pressed against the wall. Between two walls neither side opens: it stays and pulls in.
		wallBlockedFraction = 0.6,
		wallGainFraction = 0.3,
		-- After a wall swings the shot to the other shoulder it stays there at least this long
		-- (D-325): a run past pillars on alternate sides changes shoulder at most once a dwell, not
		-- at every pillar (6 changes in 5 s at 16 studs a second). A wall at the shoulder inside the
		-- dwell pulls the camera in, as between two walls.
		wallSwapDwellSeconds = 2,
	},

	mobile = {
		distanceMultiplier = 1.25,
		fovAdd = 5,
		pitchAdd = 4,
	},

	collision = {
		probeRadius = 0.6, -- spherecast radius from the focus to the camera
		minDistance = 1.5, -- never closer than this to the focus
		pullOutLag = 0.25, -- seconds; after a wall, the camera eases back out instead of popping
		-- A probe that hits a character (any model holding a Humanoid: the player's own weapon,
		-- the lock target, other players), an accessory or a part at least this transparent
		-- looks past it and casts again, at most maxPasses times; only the world blocks the view
		-- (D-149).
		seeThrough = 0.25,
		maxPasses = 4,
	},

	scripted = {
		blendOut = 0.6, -- seconds to ease from a scripted shot back to the follow
	},

	-- Render stalls (a display asleep, a minimised window, a long hitch): RenderStepped stops
	-- while the game goes on, then one frame comes back whose dt the engine may report as one
	-- frame or as the whole gap. The camera steps by the real time since its last frame. The
	-- punch, the kicks and the shake run from when they were asked for, so one asked for before
	-- the stall is over when the frame comes back, never replayed. The springs integrate the gap
	-- in pieces of at most maxStepSeconds: their semi-implicit Euler step swings past the target
	-- once omega x step passes 0.5 at critical damping, and blows up past 2 sqrt 2 - 2 (about
	-- 0.83). The stiffest spring (the FOV, lag 0.08 s) starts swinging past 0.04 s, so a 30 fps
	-- frame is still one calm piece. A gap past settleSeconds snaps them where they would have
	-- settled (by then the slowest, the 0.25 s pull-out, is within half a percent of its
	-- target), so a nudge from before the stall never plays out, and a frame never takes more
	-- than settleSeconds / maxStepSeconds pieces (60 here). tools/validators/camera.luau holds
	-- both to these limits (and the pieces to at most 120).
	stall = {
		maxStepSeconds = 1 / 30,
		settleSeconds = 2,
	},

	epsilon = 0.000001, -- vector lengths below this count as zero

	-- Where the camera's render steps run (D-180, D-211): an Enum.RenderPriority name and an offset
	-- from its value. The main step comes after the character's (choreo.luau renderOrder: the
	-- local root moved by its root motion, the contact's nudge, shake, kick and punch asked for),
	-- so it frames the body this frame draws; the late pass still shows an impulse asked for after
	-- it, at the end of the frame.
	renderOrder = {
		main = { base = "Character", offset = 2 }, -- SkyspireCamera (302)
		late = { base = "Last", offset = 0 }, -- SkyspireCameraLate (2000)
	},
}

return Camera
