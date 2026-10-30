--!strict
--[[
	player/OneHandedSword/SharpNail: the bread-and-butter combo (section 8: 3 hits, startup 0.3,
	total 1.1, post-motion 0.6, 2 studs of root motion). A diagonal cut down-left, a return cut
	up-right, and a lunging thrust.

	Timeline (the beats table describes the first strike; strikes two and three repeat the
	pattern: a short re-wind, a 3-frame snap and a hold; the first and the last strike then settle
	with a spring, the second flows on into the draw-back):
	  0.00-0.15  start pose (SineInOut): the blade raised upright on the right, torso wound right,
	             weight back
	  0.15-0.25  activation hold
	  0.25-0.33  Anticipation (5 frames): the blade cocks back over the right shoulder, the hands
	             rising, against the diagonal cut; the front foot lifts
	  0.33-0.38  Snap 1: the diagonal cut down and across to the left     (hit 1: 0.33-0.45)
	  0.38-0.42  Hold, then Settle to 0.52
	  0.50-0.58  re-wind: the wrist turns, the point dips low on the left, just off the grass
	  0.58-0.63  Snap 2: the return cut up and to the right                 (hit 2: 0.58-0.70)
	  0.66-0.85  the return cut flows on into the draw-back for the thrust (QuadIn / QuadOut
	             through 0.72, then the chamber eases in and out through 0.8, so the thrust
	             bursts from a still blade): the blade along the forearm, torso wound
	  0.85-0.90  Snap 3: the lunge, the left leg far forward                (hit 3: 0.85-0.98)
	  1.10-1.70  Recovery / post-motion: the upper body flows back to the guard while the feet step
	             out of the lunge, the rear foot first, then the front foot (through 1.6)
	Each hit window opens on its snap's first frame (its trail ignites with it), so the server
	sweeps the whole cut, and closes in the settle; each trail goes out in its settle, so the
	re-wind and the draw-back between the cuts draw none. Each smear lights on its snap's first
	two moving frames, half a frame after the snap start, and is off on the third.
	Re-key (D-376): the cuts end with the sword arm out in front of the chest, the torso turning
	with them (the sword forearm sat 0.87 inside the chest); the re-wind dips the point low on the
	left beside the body, where the camera still sees it; the blade is rolled about itself at the
	re-wind and at the return cut's end, so the second smear, stretched along the edge, lies along
	the arc it sweeps. The front foot glides in on each cut (off the field from the end of its
	anticipation, down at the cut's end); the rear foot pushes off on its toe and is drawn up in
	the re-wind and the draw-back; the root does not travel in a spring settle. A 0.15 s blend out.
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
	blendOut = 0.15,
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
				LeftHip = rot(24.3, -1.1, -6.4),
				LeftKnee = rot(-37.2, 0, 0),
				LeftAnkle = rot(12.7, 0.4, 6.3),
				RightHip = rot(-4.4, 0.8, 6.6),
				RightKnee = rot(-32.4, 0, 0),
				RightAnkle = rot(24.8, 1.1, -6.5),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- start pose: blade high right
			time = 0.15,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.08, -0.18, 0.04, 0, -6, 0),
				Waist = rot(-4, -30, -4),
				Neck = rot(4, 30, 2),
				RightShoulder = rot(83.2, -0.1, -3.2),
				RightElbow = rot(60.1, 0, 0),
				RightWrist = rot(-41.3, -0.3, -2),
				Weapon = rot(0, 0, 0),
				LeftShoulder = rot(45.2, 5.7, -24),
				LeftElbow = rot(34, 0, 0),
				LeftWrist = rot(-2.2, -7.4, 24.1),
				LeftHip = rot(27.6, -2.4, -9.6),
				LeftKnee = rot(-45.6, 0, 0),
				LeftAnkle = rot(16.7, 5.6, 9.7),
				RightHip = rot(6.9, 2.1, 6),
				RightKnee = rot(-48.9, 0, 0),
				RightAnkle = rot(30.6, 6.7, -4.9),
			},
		},
		{
			-- activation hold
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Waist = rot(-4, -32, -4),
				RightShoulder = rot(84.8, 0.7, -4.7),
				Weapon = rot(0, 0, 0),
				LeftWrist = rot(-2.2, -7.4, 24.1),
				RightAnkle = rot(29.5, 6.9, -4.7),
				RightElbow = rot(55.2, 0, 0),
				RightHip = rot(8.5, 2.3, 5.9),
				RightKnee = rot(-51.4, 0, 0),
				RightWrist = rot(-38.1, -1, -2.2),
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
				RightShoulder = rot(119.9, -6.8, -2.7),
				RightElbow = rot(43.2, 0, 0),
				LeftShoulder = rot(59.7, 10, -30.4),
				LeftAnkle = rot(29.6, 11.7, 9.7),
				LeftHip = rot(45.7, -4.7, -8.2),
				LeftKnee = rot(-70, 0, 0),
				LeftWrist = rot(-4.1, -14.8, 29.9),
				RightAnkle = rot(19.7, 9.8, -0.7),
				RightHip = rot(24.7, 4.8, 6),
				RightKnee = rot(-74.2, 0, 0),
				RightWrist = rot(-45.2, -8.1, -15.9),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap 1: diagonal down-left
			time = 0.3833,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.18, -0.2, -0.08, 0, 10, 6),
				Waist = rot(-24, 73, 7),
				Neck = rot(5, -47, -2),
				RightShoulder = rot(7.8, -20.8, 8.8),
				RightElbow = rot(51.7, 0, 0),
				RightWrist = rot(-18.9, -23.9, -12.6),
				Weapon = rot(-36, 0, -22),
				LeftShoulder = rot(0.9, 27.4, -22.8),
				LeftElbow = rot(40, 0, 0),
				LeftWrist = rot(-8.6, -37, 10.4),
				LeftHip = rot(36, -1.3, -6.4),
				LeftKnee = rot(-58.1, 0, 0),
				LeftAnkle = rot(22.2, -6.7, -0.1),
				RightHip = rot(-12, -0.1, 2.5),
				RightKnee = rot(-39, 0, 0),
				RightAnkle = rot(5.3, -0.6, -12.7),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			time = 0.4167,
			easing = "Hold",
			joints = {
				Root = posRot(-0.18, -0.2, -0.08, 0, 10, 6),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			-- out of the hold (QuadIn): the settle starts slow, so the first frame after a freeze barely moves
			time = 0.4667,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(22.65, -5.7, 0.4),
				LeftHip = rot(35.2, -1.2, -6.4),
				LeftKnee = rot(-57.75, 0, 0),
				Neck = rot(5, -47, -2),
				RightAnkle = rot(7.15, -0.65, -12.05),
				RightElbow = rot(59.9, 0, 0),
				RightHip = rot(-13.85, -0.05, 2.95),
				RightKnee = rot(-36.45, 0, 0),
				RightShoulder = rot(2.4, -16.5, 6.65),
				RightWrist = rot(-12.7, -26.05, -2),
				Root = posRot(-0.17, -0.2, -0.09, 0, 9, 5.5),
				Waist = rot(-24, 73, 7),
				Weapon = rot(-36, 0, -22),
			},
		},
		{
			-- settle 1 (6 frames: section 10 beat 5 asks for 6 to 12)
			time = 0.5167,
			easing = "Spring",
			joints = {
				Root = posRot(-0.16, -0.2, -0.1, 0, 8, 5),
				Waist = rot(-24, 73, 7),
				Neck = rot(5, -47, -2),
				RightShoulder = rot(-3, -12.2, 4.5),
				RightElbow = rot(68.1, 0, 0),
				Weapon = rot(-36, 0, -22),
				LeftAnkle = rot(23.1, -4.7, 0.9),
				LeftHip = rot(34.4, -1.1, -6.4),
				LeftKnee = rot(-57.4, 0, 0),
				RightAnkle = rot(9, -0.7, -11.4),
				RightHip = rot(-15.7, 0, 3.4),
				RightKnee = rot(-33.9, 0, 0),
				RightWrist = rot(-6.5, -28.2, 8.6),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			-- re-wind: the point dips low on the left
			time = 0.58,
			easing = "QuadIn",
			joints = {
				RightShoulder = rot(16.5, 4.4, 5.5),
				RightElbow = rot(47.6, 0, 0),
				RightWrist = rot(-33.9, -13.6, -8.7),
				Weapon = rot(-36, 0, -22),
				Waist = rot(-24, 73, 7),
				Neck = rot(5, -47, -2),
				LeftShoulder = rot(7.5, 32.2, -18.7),
				LeftAnkle = rot(37.3, -4.1, 4.8),
				LeftHip = rot(52.5, -3.3, -6),
				LeftKnee = rot(-81.7, 0, 0),
				LeftWrist = rot(-9.2, -40.7, 11.3),
				RightAnkle = rot(32.9, -5.1, -8),
				RightHip = rot(-4.7, 0.7, 3.3),
				RightKnee = rot(-52.9, 0, 0),
				Root = posRot(-0.06, -0.2, -0.1, 0, 8, 2),
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
				RightShoulder = rot(83.3, -0.3, 36.5),
				RightElbow = rot(12.6, 0, 0),
				RightWrist = rot(24.2, 29.4, 6.4),
				Weapon = rot(-50, 0, 22),
				LeftShoulder = rot(33.2, 2.1, -39),
				LeftElbow = rot(30, 0, 0),
				LeftHip = rot(15.7, 0.2, -6),
				LeftKnee = rot(-38.4, 0, 0),
				LeftAnkle = rot(20.3, 14, 9),
				RightHip = rot(-18.3, 0.3, 12.9),
				RightKnee = rot(-31.8, 0, 0),
				RightAnkle = rot(11.1, 10.9, -2.8),
				LeftWrist = rot(-1.1, -3.7, 0.9),
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
			-- out of hold 2: QuadIn over two thirds of the settle, then QuadOut, so the return cut leaves
			-- the freeze slowly (D-405); the legs keep their draw-up
			time = 0.72,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(23.7, 13.4, 8.9),
				LeftElbow = rot(31.6, 0, 0),
				LeftHip = rot(16.3, -0.1, -6.8),
				LeftKnee = rot(-42.3, 0, 0),
				LeftShoulder = rot(36.867, 2.233, -36.333),
				LeftWrist = rot(-1.1, -3.7, 7.367),
				Neck = rot(2.933, 23.6, 1.6),
				RightAnkle = rot(30.8, 10.3, -5),
				RightElbow = rot(31.134, 0, 0),
				RightHip = rot(-2.9, 2.9, 11.4),
				RightKnee = rot(-54.9, 0, 0),
				RightShoulder = rot(55.765, -0.1, 31.366),
				RightWrist = rot(5.132, 9.799, -3.467),
				Root = posRot(0.078, -0.178, -0.162, 0, -9.4, -2.1),
				Waist = rot(-5.467, -26.267, -6.133),
				Weapon = rot(-58, 0, 14.533),
			},
			root = { pos = { 0, 0, -1.167 } },
		},
		{
			-- settle 2
			time = 0.75,
			easing = "QuadOut",
			joints = {
				Root = posRot(0.076, -0.196, -0.164, 0, -8.8, -1.2),
				Waist = rot(-5.2, -26.4, -5.2),
				Neck = rot(3.4, 24.4, 1.4),
				RightShoulder = rot(42, 0, 28.8),
				RightElbow = rot(40.4, 0, 0),
				Weapon = rot(-62, 0, 10.8),
				LeftAnkle = rot(26.9, 13, 8.7),
				LeftElbow = rot(32.4, 0, 0),
				LeftHip = rot(16.6, -0.5, -7.5),
				LeftKnee = rot(-45.7, 0, 0),
				LeftShoulder = rot(38.7, 2.3, -35),
				LeftWrist = rot(-1.1, -3.7, 10.6),
				RightAnkle = rot(31.4, 9.6, -5.7),
				RightHip = rot(0.9, 2.2, 9.2),
				RightKnee = rot(-47.4, 0, 0),
				RightWrist = rot(-4.4, 0, -8.4),
			},
			root = { pos = { 0, 0, -1.2 } },
		},
		{
			time = 0.8,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(45.2, 17.2, 9.4),
				LeftElbow = rot(34.2, 0, 0),
				LeftHip = rot(46.7, -7.2, -9.6),
				LeftKnee = rot(-83.9, 0, 0),
				LeftShoulder = rot(45.5, 5.1, -31),
				LeftWrist = rot(-2.1, -7.4, 18.9),
				Neck = rot(3.7, 29.2, 1.7),
				RightAnkle = rot(29.7, 10.8, -4.7),
				RightElbow = rot(57.2, 0, 0),
				RightHip = rot(5.7, 2.6, 8.4),
				RightKnee = rot(-54.4, 0, 0),
				RightShoulder = rot(15, 0, 26.4),
				RightWrist = rot(-12.2, 0, -4.2),
				Root = posRot(0.088, -0.208, -0.152, 0, -9.4, -0.6),
				Waist = rot(-4.6, -31.2, -4.6),
				Weapon = rot(-71, 0, 5.4),
			},
			root = { pos = { 0, 0, -1.2 } },
		},
		{
			-- draw back for the thrust: the blade along the forearm
			time = 0.85,
			easing = "QuadOut",
			joints = {
				Root = posRot(0.1, -0.22, -0.14, 0, -10, 0),
				Waist = rot(-4, -36, -4),
				Neck = rot(4, 34, 2),
				RightShoulder = rot(-12, 0, 24),
				RightElbow = rot(74, 0, 0),
				RightWrist = rot(-20, 0, 0),
				Weapon = rot(-80, 0, 0),
				LeftShoulder = rot(52.2, 7.9, -26.9),
				LeftElbow = rot(36, 0, 0),
				LeftWrist = rot(-3.2, -11, 27.2),
				RightKnee = rot(-65.9, 0, 0),
				RightAnkle = rot(22.6, 12.2, -2),
				LeftAnkle = rot(30.2, 19.2, 9.7),
				LeftHip = rot(72.6, -11.7, -9.2),
				LeftKnee = rot(-93, 0, 0),
				RightHip = rot(14.1, 3.2, 7.2),
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
				LeftHip = rot(49.3, 0.2, -7.1),
				LeftKnee = rot(-46.8, 0, 0),
				LeftAnkle = rot(-2.4, -1.6, 2.5),
				RightHip = rot(-22, -2.3, -0.1),
				RightKnee = rot(-52.7, 0, 0),
				RightAnkle = rot(23.9, -4.8, -10),
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
			-- out of the hold (QuadIn): the settle starts slow, so the first frame after a freeze barely moves
			time = 1.015,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(-2.1, -0.9, 3.15),
				LeftHip = rot(49.15, -0.1, -7.8),
				LeftKnee = rot(-47.05, 0, 0),
				LeftShoulder = rot(-34, 0, -30),
				Neck = rot(9, -16, -1),
				RightAnkle = rot(22.9, -4.8, -9.4),
				RightElbow = rot(4, 0, 0),
				RightHip = rot(-22.55, -1.9, 0.05),
				RightKnee = rot(-48.6, 0, 0),
				RightShoulder = rot(85, 0, -5),
				Root = posRot(-0.09, -0.3, -0.3, 0, 13, 2),
				Waist = rot(-21, 21, 3.5),
				Weapon = rot(-90, 0, 0),
			},
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
				LeftAnkle = rot(-1.8, -0.2, 3.8),
				LeftHip = rot(49, -0.4, -8.5),
				LeftKnee = rot(-47.3, 0, 0),
				RightAnkle = rot(21.9, -4.8, -8.8),
				RightHip = rot(-23.1, -1.5, 0.2),
				RightKnee = rot(-44.5, 0, 0),
			},
			root = { pos = { 0, 0, -1.9 } },
		},
		{
			-- post-motion micro keys
			time = 1.3,
			easing = "SineInOut",
			joints = {
				Waist = rot(-16.4, 7.5, 2),
				Neck = rot(8, -4.9, -0.6),
				Weapon = rot(-74, 0, 0.7),
				RightWrist = rot(-6.8, 0, 0.7),
				LeftAnkle = rot(-4.8, 3.4, 6.2),
				LeftHip = rot(41.9, 0.1, -10.1),
				LeftKnee = rot(-37.7, 0, 0),
				LeftShoulder = rot(-12, 0, -24.7),
				LeftWrist = rot(0, 0, 3.5),
				RightAnkle = rot(30, -5.6, -6.7),
				RightElbow = rot(16.2, 0, 0),
				RightHip = rot(-20.2, 0.4, 2.5),
				RightKnee = rot(-36.4, 0, 0),
				RightShoulder = rot(63.8, 0, 0.9),
				Root = posRot(-0.052, -0.237, -0.195, 0, 7.8, 1.3),
			},
			root = { pos = { 0, 0, -2 } },
		},
		{
			time = 1.5,
			easing = "SineInOut",
			joints = {
				Waist = rot(-11, -4.5, 0.8),
				Neck = rot(6.5, 5.3, -0.2),
				Weapon = rot(-59.7, 0, -0.2),
				RightWrist = rot(-18.5, 0, -0.2),
				LeftAnkle = rot(-24.2, 7.6, 8),
				LeftHip = rot(23, 3.4, -10.6),
				LeftKnee = rot(0, 0, 0),
				LeftShoulder = rot(10.8, 0, -18.7),
				LeftWrist = rot(0, 0, 7.5),
				RightAnkle = rot(27.8, -4.5, -5.9),
				RightElbow = rot(27.8, 0, 0),
				RightHip = rot(-8.8, 3, 4.8),
				RightKnee = rot(-31.5, 0, 0),
				RightShoulder = rot(43, 0, 6.5),
				Root = posRot(-0.02, -0.165, -0.075, 0, 3, 0.5),
			},
		},
		{
			time = 1.6,
			easing = "SineInOut",
			joints = {
				LeftAnkle = rot(20.7, 2.3, 7.5),
				LeftHip = rot(47.7, -1.5, -10.4),
				LeftKnee = rot(-61.1, 0, 0),
				LeftShoulder = rot(15.7, 0, -17.5),
				LeftWrist = rot(0, 0, 8.4),
				Neck = rot(6.3, 7.5, -0.2),
				RightAnkle = rot(26.9, -3.7, -5.9),
				RightElbow = rot(30.2, 0, 0),
				RightHip = rot(-7.3, 3.3, 5.1),
				RightKnee = rot(-31.9, 0, 0),
				RightShoulder = rot(38.5, 0, 7.7),
				RightWrist = rot(-20.7, 0, -0.1),
				Root = posRot(-0.013, -0.15, -0.049, 0, 2, 0.3),
				Waist = rot(-10, -7.1, 0.5),
				Weapon = rot(-56.4, 0, -0.2),
			},
			root = { pos = { 0, 0, -2 } },
		},
		{
			time = 1.7,
			easing = "SineInOut",
			joints = {
				LeftShoulder = rot(20.6, 0, -16.2),
				RightShoulder = rot(34.1, 0, 8.9),
				RightWrist = rot(-22.8, 0, 0),
				LeftAnkle = rot(14.7, -4.9, 5.8),
				LeftHip = rot(26.1, 2.8, -8),
				LeftKnee = rot(-40.4, 0, 0),
				LeftWrist = rot(0, 0, 9.2),
				Neck = rot(6.2, 9.8, -0.1),
				RightAnkle = rot(31.5, -2.9, -6.1),
				RightElbow = rot(32.7, 0, 0),
				RightHip = rot(-1.2, 4.1, 5.3),
				RightKnee = rot(-42.6, 0, 0),
				Root = posRot(-0.006, -0.134, -0.024, 0, 1, 0.2),
				Waist = rot(-9, -9.6, 0.2),
				Weapon = rot(-53.1, 0, -0.1),
			},
		},
	},
	events = {
		{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },
		{ time = 0.27, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.3333, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.3333, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.3416, kind = "SmearOn", data = { axis = "X" } },
		{ time = 0.375, kind = "SmearOff" },
		{ time = 0.45, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 0.49, kind = "TrailOff" },
		{ time = 0.52, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.58, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.58, kind = "HitWindowOpen", data = { hit = 2 } },
		{ time = 0.5883, kind = "SmearOn", data = { axis = "X" } },
		{ time = 0.6217, kind = "SmearOff" },
		{ time = 0.7, kind = "HitWindowClose", data = { hit = 2 } },
		{ time = 0.74, kind = "TrailOff" },
		{ time = 0.79, kind = "Sfx", data = { name = "whoosh.Small" } },
		{ time = 0.85, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.85, kind = "HitWindowOpen", data = { hit = 3 } },
		{ time = 0.8583, kind = "SmearOn", data = { axis = "Z" } },
		{ time = 0.8917, kind = "SmearOff" },
		{ time = 0.98, kind = "HitWindowClose", data = { hit = 3 } },
		{ time = 1.02, kind = "TrailOff" },
		{ time = 1.1, kind = "PostMotionStart" },
	},
	beats = {
		Anticipation = { start = 0.25, finish = 0.3333 },
		Snap = { start = 0.3333, finish = 0.3833 },
		Smear = { start = 0.3416, finish = 0.375 },
		Hold = { start = 0.3833, finish = 0.4167 },
		Settle = { start = 0.4167, finish = 0.5167 },
		Recovery = { start = 1.1, finish = 1.7 },
	},
}

return clip
