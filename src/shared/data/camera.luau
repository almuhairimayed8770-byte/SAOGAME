--!strict
--[[
	Camera numbers (section 10). Third person, a spring-damped follow with 0.12 s lag, 60-degree
	FOV at rest, +8 degrees on Art activation and dashes, a 0.4-stud nudge toward every hit, shake
	amplitude 0.15 / 0.3 / 0.6 studs for the three hit-stop tiers, lock-on framing that keeps both
	fighters in view, a low tight orbit in duels, a high wide orbit in raids. Mobile uses the same
	system with wider defaults.

	The nudge and shake amplitudes are section 6 numbers already in combat.luau; this table points
	at them so there is one source. Angles are degrees, distances are studs, times are seconds.
	Conventions used by CameraMath: yaw 0 puts the camera behind a rig that faces -Z; pitch is the
	camera's elevation above the focus (positive looks down on the fighters).
]]

local Combat = require(script.Parent.combat)

export type Orbit = {
	distance: number, -- studs from the focus to the camera
	height: number, -- studs the camera sits above the focus
	side: number, -- studs the camera is offset to the right (over-the-shoulder)
	pitch: number, -- degrees of elevation
}

local Camera = {
	follow = {
		lag = 0.12, -- seconds; the position spring's time constant (1 / omega)
		damping = 1.0, -- critical: the follow never overshoots on its own
		focusHeight = 2.0, -- studs above the root part the camera looks at (chest height)
		snapDistance = 60, -- a subject jump bigger than this (teleport, respawn) snaps the spring
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

	shake = {
		amplitude = Combat.cameraShakeStuds, -- per hit-stop tier
		decay = 14, -- per second; exponential fall-off of the shake energy
		frequency = 23, -- Hz; base frequency of the noise
		-- Three incommensurate sine lanes summed per axis so the shake never repeats or reads as a
		-- linear wobble: {frequency multiplier, phase offset in radians}.
		lanes = { { 1.0, 0.0 }, { 0.731, 1.7 }, { 1.318, 2.9 } },
		cutoff = 0.004, -- studs; energy below this is zeroed
	},

	-- Orbit presets. Default is the field camera; Duel is low and tight; Raid is high and wide.
	orbit = {
		Default = { distance = 12, height = 1.6, side = 1.75, pitch = 12 } :: Orbit,
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
		baseDistance = 11,
		minDistance = 9,
		maxDistance = 20,
		distancePerSeparation = 0.35, -- camera distance grows with the fighters' separation
		focusBias = 0.35, -- 0 looks at the player, 1 at the target; the midpoint is 0.5
		height = 2.5,
		side = 2.0,
		pitch = 10,
		yawLag = 0.2, -- seconds; the yaw eases onto the player-target line
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
	},

	scripted = {
		blendOut = 0.6, -- seconds to ease from a scripted shot back to the follow
	},

	epsilon = 0.000001, -- vector lengths below this count as zero
}

return Camera
