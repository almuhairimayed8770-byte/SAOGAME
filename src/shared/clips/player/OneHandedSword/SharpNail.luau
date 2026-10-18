--!strict
--[[
	player/OneHandedSword/SharpNail: the bread-and-butter combo (section 8: 3 hits, startup 0.3,
	total 1.1, post-motion 0.6, 2 studs of root motion). A diagonal cut down-left, a return cut
	up-right, and a lunging thrust.

	Timeline (the beats table describes the first strike; strikes two and three repeat the
	pattern: a short re-wind, a 3-frame snap, a hold, a spring settle):
	  0.00-0.15  start pose: blade high on the right, torso wound right, weight back
	  0.15-0.25  activation hold
	  0.25-0.33  Anticipation (5 frames): the coil deepens
	  0.33-0.38  Snap 1: the diagonal cut down and across to the left     (hit 1: 0.33-0.45)
	  0.38-0.42  Hold, then Settle to 0.52
	  0.50-0.58  re-wind: the wrist turns, the point dips low on the left, just off the grass
	  0.58-0.63  Snap 2: the return cut up and to the right                 (hit 2: 0.58-0.70)
	  0.75-0.85  draw back for the thrust: the blade along the forearm, torso wound
	  0.85-0.90  Snap 3: the lunge, the left leg far forward                (hit 3: 0.85-0.98)
	  1.10-1.70  Recovery / post-motion: extended in the lunge, breathing, the point trembling
	Each hit window opens on its snap's first frame (the trail ignites with the first), so the
	server sweeps the whole cut, and closes in the settle.
	Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/SharpNail",
	rig = "PlayerR15",
	duration = 1.7,
	loop = false,
	layer = "FullBody",
	priority = 20,
	attack = true,
	hitStop = "Normal",
	blendIn = 0.08,
	blendOut = 0.2,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-8, -12, 0),
				Neck = rot(6, 12, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
				LeftHip = rot(15, 0, -6),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(5, 0, 0),
				RightHip = rot(-10, 0, 6),
				RightKnee = rot(-25, 0, 0),
				RightAnkle = rot(35, 0, 0),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- start pose: blade high right
			time = 0.15,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.08, -0.18, 0.04, 0, -6, 0),
				Waist = rot(-4, -30, -4),
				Neck = rot(4, 30, 2),
				RightShoulder = rot(112, 0, 42),
				RightElbow = rot(52, 0, 0),
				RightWrist = rot(-12, 0, -10),
				Weapon = rot(-40, 0, -10),
				LeftShoulder = rot(40, 0, -26),
				LeftElbow = rot(34, 0, 0),
				LeftWrist = rot(0, 0, 22),
				LeftHip = rot(20, 0, -6),
				LeftKnee = rot(-18, 0, 0),
				LeftAnkle = rot(-2, 0, 0),
				RightHip = rot(-14, 0, 8),
				RightKnee = rot(-34, 0, 0),
				RightAnkle = rot(48, 0, 0),
			},
		},
		{
			-- activation hold
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Waist = rot(-4, -32, -4),
				RightShoulder = rot(114, 0, 43),
				Weapon = rot(-42, 0, -11),
				LeftWrist = rot(0, 0, 26),
			},
		},
		{
			-- anticipation
			time = 0.3333,
			easing = "QuadIn",
			joints = {
				Root = posRot(0.12, -0.22, 0.06, 0, -9, -2),
				Waist = rot(-2, -40, -6),
				Neck = rot(3, 36, 3),
				RightShoulder = rot(122, 0, 48),
				RightElbow = rot(56, 0, 0),
				LeftShoulder = rot(48, 0, -34),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap 1: diagonal down-left
			time = 0.3833,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.08, -0.2, -0.08, 0, 10, 3),
				Waist = rot(-18, 28, 7),
				Neck = rot(2, -20, -2),
				RightShoulder = rot(28, 0, -38),
				RightElbow = rot(8, 0, 0),
				RightWrist = rot(0, 0, 10),
				Weapon = rot(-36, 0, -22),
				LeftShoulder = rot(-26, 0, -30),
				LeftElbow = rot(40, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(26, 0, -6),
				LeftKnee = rot(-32, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(-26, 0, 8),
				RightKnee = rot(-10, 0, 0),
				RightAnkle = rot(36, 0, 0),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			time = 0.4167,
			easing = "Hold",
			joints = {
				Root = posRot(-0.08, -0.2, -0.08, 0, 10, 3),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			-- settle 1 (6 frames: section 10 beat 5 asks for 6 to 12)
			time = 0.5167,
			easing = "Spring",
			joints = {
				Root = posRot(-0.06, -0.2, -0.1, 0, 8, 2),
				Waist = rot(-14, 22, 5),
				Neck = rot(3, -16, -1),
				RightShoulder = rot(34, 0, -32),
				RightElbow = rot(12, 0, 0),
				Weapon = rot(-34, 0, -18),
			},
			root = { pos = { 0, 0, -0.7 } },
		},
		{
			-- re-wind: the point dips low on the left
			time = 0.58,
			easing = "QuadIn",
			joints = {
				RightShoulder = rot(14, 0, -40),
				RightElbow = rot(20, 0, 0),
				RightWrist = rot(-20, 0, 24),
				Weapon = rot(-20, 0, -30),
				Waist = rot(-16, 30, 8),
				Neck = rot(3, -22, -2),
				LeftShoulder = rot(-20, 0, -26),
			},
			root = { pos = { 0, 0, -0.7 } },
		},
		{
			-- snap 2: the return cut up-right
			time = 0.63,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.08, -0.16, -0.16, 0, -10, -3),
				Waist = rot(-6, -26, -8),
				Neck = rot(2, 22, 2),
				RightShoulder = rot(84, 0, 38),
				RightElbow = rot(14, 0, 0),
				RightWrist = rot(6, 0, -14),
				Weapon = rot(-50, 0, 22),
				LeftShoulder = rot(30, 0, -40),
				LeftElbow = rot(30, 0, 0),
				LeftHip = rot(18, 0, -6),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(2, 0, 0),
				RightHip = rot(-10, 0, 8),
				RightKnee = rot(-28, 0, 0),
				RightAnkle = rot(38, 0, 0),
			},
			root = { pos = { 0, 0, -1.1 } },
		},
		{
			time = 0.66,
			easing = "Hold",
			joints = {
				Root = posRot(0.08, -0.16, -0.16, 0, -10, -3),
			},
			root = { pos = { 0, 0, -1.1 } },
		},
		{
			-- settle 2
			time = 0.75,
			easing = "Spring",
			joints = {
				Root = posRot(0.06, -0.18, -0.18, 0, -8, -2),
				Waist = rot(-6, -20, -6),
				Neck = rot(3, 18, 1),
				RightShoulder = rot(78, 0, 32),
				RightElbow = rot(18, 0, 0),
				Weapon = rot(-50, 0, 18),
			},
			root = { pos = { 0, 0, -1.2 } },
		},
		{
			-- draw back for the thrust: the blade along the forearm
			time = 0.85,
			easing = "QuadIn",
			joints = {
				Root = posRot(0.1, -0.22, -0.14, 0, -10, 0),
				Waist = rot(-4, -36, -4),
				Neck = rot(4, 34, 2),
				RightShoulder = rot(-12, 0, 24),
				RightElbow = rot(74, 0, 0),
				RightWrist = rot(-20, 0, 0),
				Weapon = rot(-80, 0, 0),
				LeftShoulder = rot(44, 0, -30),
				LeftElbow = rot(36, 0, 0),
				LeftWrist = rot(0, 0, 24),
				RightKnee = rot(-40, 0, 0),
				RightAnkle = rot(50, 0, 0),
			},
			root = { pos = { 0, 0, -1.2 } },
		},
		{
			-- snap 3: the thrust
			time = 0.9,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.1, -0.3, -0.3, 0, 14, 2),
				Waist = rot(-22, 24, 4),
				Neck = rot(10, -18, -1),
				RightShoulder = rot(88, 0, -6),
				RightElbow = rot(2, 0, 0),
				RightWrist = rot(2, 0, 0),
				Weapon = rot(-92, 0, 0),
				LeftShoulder = rot(-36, 0, -30),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(48, 0, -8),
				LeftKnee = rot(-44, 0, 0),
				LeftAnkle = rot(-4, 0, 0),
				RightHip = rot(-36, 0, 8),
				RightKnee = rot(-4, 0, 0),
				RightAnkle = rot(40, 0, 0),
			},
			root = { pos = { 0, 0, -1.9 } },
		},
		{
			time = 0.95,
			easing = "Hold",
			joints = {
				Root = posRot(-0.1, -0.3, -0.3, 0, 14, 2),
			},
			root = { pos = { 0, 0, -1.9 } },
		},
		{
			-- settle 3
			time = 1.08,
			easing = "Spring",
			joints = {
				Root = posRot(-0.08, -0.3, -0.3, 0, 12, 2),
				Waist = rot(-20, 18, 3),
				Neck = rot(8, -14, -1),
				RightShoulder = rot(82, 0, -4),
				RightElbow = rot(6, 0, 0),
				Weapon = rot(-88, 0, 0),
				LeftShoulder = rot(-32, 0, -30),
			},
			root = { pos = { 0, 0, -2 } },
		},
		{
			-- post-motion micro keys
			time = 1.3,
			easing = "SineInOut",
			joints = {
				Waist = rot(-21, 18, 3),
				Neck = rot(9, -14, -1),
				Weapon = rot(-87, 0, 1),
				RightWrist = rot(3, 0, 1),
			},
		},
		{
			time = 1.5,
			easing = "SineInOut",
			joints = {
				Waist = rot(-20, 18, 3),
				Neck = rot(8, -15, -1),
				Weapon = rot(-89, 0, -1),
				RightWrist = rot(1, 0, -1),
			},
		},
		{
			time = 1.7,
			easing = "SineInOut",
			joints = {
				LeftShoulder = rot(-30, 0, -30),
				RightShoulder = rot(81, 0, -4),
				RightWrist = rot(2, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },
		{ time = 0.3333, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.3333, kind = "SmearOn", data = { axis = "X" } },
		{ time = 0.3333, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.34, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.3667, kind = "SmearOff" },
		{ time = 0.45, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 0.58, kind = "SmearOn", data = { axis = "X" } },
		{ time = 0.58, kind = "HitWindowOpen", data = { hit = 2 } },
		{ time = 0.59, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.6133, kind = "SmearOff" },
		{ time = 0.7, kind = "HitWindowClose", data = { hit = 2 } },
		{ time = 0.85, kind = "SmearOn", data = { axis = "Z" } },
		{ time = 0.85, kind = "HitWindowOpen", data = { hit = 3 } },
		{ time = 0.86, kind = "Sfx", data = { name = "whoosh.Small" } },
		{ time = 0.8833, kind = "SmearOff" },
		{ time = 0.98, kind = "HitWindowClose", data = { hit = 3 } },
		{ time = 1.02, kind = "TrailOff" },
		{ time = 1.1, kind = "PostMotionStart" },
	},
	beats = {
		Anticipation = { start = 0.25, finish = 0.3333 },
		Snap = { start = 0.3333, finish = 0.3833 },
		Smear = { start = 0.3333, finish = 0.3667 },
		Hold = { start = 0.3833, finish = 0.4167 },
		Settle = { start = 0.4167, finish = 0.5167 },
		Recovery = { start = 1.1, finish = 1.7 },
	},
}

return clip
