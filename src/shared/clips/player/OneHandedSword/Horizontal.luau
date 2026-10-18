--!strict
--[[
	player/OneHandedSword/Horizontal: the first Art (section 8: 1 hit, startup 0.25, total 0.6,
	post-motion 0.4, 1 stud of root motion). A right-to-left cut at chest height.

	Timeline (section 6 / 10):
	  0.00-0.15  start pose: weight back onto the right leg, torso wound right, blade drawn back
	             level with the hip, the free hand opens toward the target
	  0.15-0.25  activation hold (the tell): the stance breathes, the blade lights
	  0.25-0.35  Anticipation (6 frames): the coil deepens, hips turn further right
	  0.35-0.40  Snap (3 frames, ExpoOut): the cut, torso whipped left, weight onto the left foot
	  0.35-0.38  Smear (2 frames)
	  0.35-0.48  Hit window: opens on the snap's first frame (the trail ignites with it), so the
	             server sweeps the whole cut, and closes in the settle
	  0.40-0.43  Hold (the contact; hit-stop pauses the clock here on a hit)
	  0.43-0.55  Settle (Spring): the pose comes back 5-8 degrees from the extreme
	  0.60-1.00  Recovery / post-motion: caught in the stance with micro-motion only
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
	id = "player/OneHandedSword/Horizontal",
	rig = "PlayerR15",
	duration = 1.0,
	loop = false,
	layer = "FullBody",
	priority = 20,
	attack = true,
	hitStop = "Normal",
	blendIn = 0.08,
	blendOut = 0.2,
	keys = {
		{
			-- ready stance
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
			-- start pose
			time = 0.15,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.1, -0.2, 0.05, 0, -6, 0),
				Waist = rot(-6, -34, -4),
				Neck = rot(6, 32, 2),
				RightShoulder = rot(-22, 0, 46),
				RightElbow = rot(42, 0, 0),
				RightWrist = rot(-6, 0, -22),
				Weapon = rot(-30, 0, -8),
				LeftShoulder = rot(42, 0, -26),
				LeftElbow = rot(30, 0, 0),
				LeftWrist = rot(0, 0, 22),
				LeftHip = rot(20, 0, -6),
				LeftKnee = rot(-16, 0, 0),
				LeftAnkle = rot(-4, 0, 0),
				RightHip = rot(-14, 0, 8),
				RightKnee = rot(-36, 0, 0),
				RightAnkle = rot(50, 0, 0),
			},
		},
		{
			-- activation hold: alive, not paused
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.11, -0.22, 0.06, 0, -6, 0),
				Waist = rot(-6, -37, -4),
				Neck = rot(6, 34, 2),
				Weapon = rot(-32, 0, -10),
				LeftWrist = rot(0, 0, 26),
			},
		},
		{
			-- anticipation: the coil
			time = 0.35,
			easing = "QuadIn",
			joints = {
				Root = posRot(0.16, -0.26, 0.08, 0, -10, -2),
				Waist = rot(-4, -46, -7),
				Neck = rot(5, 40, 3),
				RightShoulder = rot(-32, 0, 52),
				RightElbow = rot(46, 0, 0),
				Weapon = rot(-34, 0, -12),
				LeftShoulder = rot(52, 0, -36),
				LeftElbow = rot(24, 0, 0),
				RightKnee = rot(-40, 0, 0),
				RightAnkle = rot(54, 0, 0),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap: the cut, past the final pose
			time = 0.4,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.12, -0.16, -0.1, 0, 12, 4),
				Waist = rot(-14, 42, 8),
				Neck = rot(2, -28, -2),
				RightShoulder = rot(64, 0, -36),
				RightElbow = rot(4, 0, 0),
				RightWrist = rot(4, 0, 12),
				Weapon = rot(-62, 0, -26),
				LeftShoulder = rot(-34, 0, -32),
				LeftElbow = rot(42, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(28, 0, -6),
				LeftKnee = rot(-34, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(-32, 0, 8),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(38, 0, 0),
			},
			root = { pos = { 0, 0, -0.7 } },
		},
		{
			-- hold on contact
			time = 0.43,
			easing = "Hold",
			joints = {
				Root = posRot(-0.12, -0.16, -0.1, 0, 12, 4),
			},
			root = { pos = { 0, 0, -0.7 } },
		},
		{
			-- settle: back 5-8 degrees from the extreme
			time = 0.55,
			easing = "Spring",
			joints = {
				Root = posRot(-0.1, -0.18, -0.08, 0, 10, 3),
				Waist = rot(-12, 35, 6),
				Neck = rot(3, -22, -1),
				RightShoulder = rot(58, 0, -30),
				RightElbow = rot(8, 0, 0),
				Weapon = rot(-60, 0, -20),
				LeftShoulder = rot(-28, 0, -30),
			},
			root = { pos = { 0, 0, -1 } },
		},
		{
			-- post-motion micro keys: caught in the stance
			time = 0.75,
			easing = "SineInOut",
			joints = {
				Waist = rot(-13, 35, 6),
				Neck = rot(4, -22, -1),
				Weapon = rot(-59, 0, -21),
				RightWrist = rot(5, 0, 11),
			},
		},
		{
			time = 0.9,
			easing = "SineInOut",
			joints = {
				Waist = rot(-12, 35, 6),
				Neck = rot(3, -23, -1),
				Weapon = rot(-61, 0, -19),
				RightWrist = rot(3, 0, 13),
			},
		},
		{
			time = 1.0,
			easing = "SineInOut",
			joints = {
				LeftShoulder = rot(-26, 0, -30),
				RightShoulder = rot(57, 0, -30),
				RightWrist = rot(4, 0, 12),
			},
		},
	},
	events = {
		{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },
		{ time = 0.35, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.35, kind = "SmearOn", data = { axis = "X" } },
		{ time = 0.35, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.35, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.3833, kind = "SmearOff" },
		{ time = 0.48, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 0.52, kind = "TrailOff" },
		{ time = 0.6, kind = "PostMotionStart" },
	},
	beats = {
		Anticipation = { start = 0.25, finish = 0.35 },
		Snap = { start = 0.35, finish = 0.4 },
		Smear = { start = 0.35, finish = 0.3833 },
		Hold = { start = 0.4, finish = 0.43 },
		Settle = { start = 0.43, finish = 0.55 },
		Recovery = { start = 0.6, finish = 1.0 },
	},
}

return clip
