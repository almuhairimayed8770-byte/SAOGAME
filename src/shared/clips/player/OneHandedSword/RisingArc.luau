--!strict
--[[
	player/OneHandedSword/RisingArc: the launcher (section 8: 2 hits, startup 0.3, total 0.9,
	post-motion 0.5, 1 stud of root motion; launches small enemies). A rising diagonal cut from
	low left to high right that carries the blade over the head, then a follow-through flick at
	the top. The body sinks into the start pose and drives up through the legs on the snap, so
	the whole rig rises with the blade; from behind it reads as a crouch that uncoils upward.

	Timeline (the beats table describes the first strike; the flick repeats the pattern with a
	short re-cock, a 3-frame snap, a hold and a spring settle):
	  0.00-0.15  start pose: the body sinks, the blade hangs low across the body on the left
	             with the point by the left knee, torso wound left, the free hand opens
	  0.15-0.25  activation hold: the blade lights, the crouch breathes
	  0.25-0.33  Anticipation (5 frames): the crouch deepens, the point drags lower and further left
	  0.33-0.38  Snap 1 (3 frames, ExpoOut): the rising cut, the legs drive the hips up onto the
	             toes, the torso whips right                                   (hit 1: 0.35-0.45)
	  0.33-0.37  Smear (2 frames, X: the diagonal)
	  0.38-0.42  Hold (hit-stop pauses the clock here on a hit)
	  0.42-0.52  Settle (Spring, 6 frames): the pose comes back 5-8 degrees from the extreme
	  0.52-0.56  re-cock: the blade carries over the head, the elbow and wrist cock back
	  0.56-0.61  Snap 2: the follow-through flick at the top, elbow and wrist   (hit 2: 0.58-0.68)
	  0.61-0.64  Hold, then Settle to 0.75
	  0.75-0.90  the heels come down, the knees take the weight, the blade stays high
	  0.90-1.40  Recovery / post-motion: caught under the raised blade, breathing, the point trembling
	Hit-stop: Normal on hit 1, Final on hit 2 (the server tiers an Art's last window, as it does
	for Sharp Nail). Root motion: 1 stud forward over the two snaps (-Z is forward).
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
	id = "player/OneHandedSword/RisingArc",
	rig = "PlayerR15",
	duration = 1.4,
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
			-- start pose: the body sinks, the blade hangs low across the body on the left
			time = 0.15,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.06, -0.34, 0.04, 0, 8, 2),
				Waist = rot(-10, 30, 6),
				Neck = rot(8, -28, -2),
				RightShoulder = rot(18, 0, -44),
				RightElbow = rot(24, 0, 0),
				RightWrist = rot(-22, 0, 26),
				Weapon = rot(-70, 0, -32),
				LeftShoulder = rot(36, 0, -24),
				LeftElbow = rot(30, 0, 0),
				LeftWrist = rot(0, 0, 22),
				LeftHip = rot(24, 0, -6),
				LeftKnee = rot(-34, 0, 0),
				LeftAnkle = rot(8, 0, 0),
				RightHip = rot(-12, 0, 8),
				RightKnee = rot(-38, 0, 0),
				RightAnkle = rot(44, 0, 0),
			},
		},
		{
			-- activation hold: the crouch breathes, the point drifts lower
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.06, -0.36, 0.04, 0, 9, 2),
				Waist = rot(-11, 32, 6),
				RightShoulder = rot(17, 0, -46),
				Weapon = rot(-72, 0, -34),
				LeftWrist = rot(0, 0, 26),
			},
		},
		{
			-- anticipation: the crouch deepens, the point drags further left
			time = 0.3333,
			easing = "QuadIn",
			joints = {
				Root = posRot(-0.08, -0.42, 0.06, 0, 12, 3),
				Waist = rot(-14, 40, 8),
				Neck = rot(10, -34, -3),
				RightShoulder = rot(10, 0, -52),
				RightElbow = rot(30, 0, 0),
				RightWrist = rot(-26, 0, 30),
				Weapon = rot(-76, 0, -38),
				LeftShoulder = rot(44, 0, -32),
				LeftElbow = rot(24, 0, 0),
				LeftKnee = rot(-42, 0, 0),
				LeftAnkle = rot(12, 0, 0),
				RightKnee = rot(-44, 0, 0),
				RightAnkle = rot(50, 0, 0),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap 1: the rising cut, past the final pose; the legs drive the hips up onto the toes
			time = 0.3833,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.08, 0.04, -0.06, 0, -12, -4),
				Waist = rot(10, -34, -10),
				Neck = rot(2, 30, 3),
				RightShoulder = rot(134, 0, 40),
				RightElbow = rot(12, 0, 0),
				RightWrist = rot(10, 0, -18),
				Weapon = rot(-46, 0, 20),
				LeftShoulder = rot(-32, 0, -36),
				LeftElbow = rot(38, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(8, 0, -6),
				LeftKnee = rot(-6, 0, 0),
				LeftAnkle = rot(-22, 0, 0),
				RightHip = rot(-16, 0, 8),
				RightKnee = rot(-8, 0, 0),
				RightAnkle = rot(62, 0, 0),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			-- hold on contact
			time = 0.4167,
			easing = "Hold",
			joints = {
				Root = posRot(0.08, 0.04, -0.06, 0, -12, -4),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			-- settle 1 (6 frames): back 5-8 degrees from the extreme
			time = 0.5167,
			easing = "Spring",
			joints = {
				Root = posRot(0.06, 0, -0.08, 0, -10, -3),
				Waist = rot(8, -28, -8),
				Neck = rot(1, 26, 2),
				RightShoulder = rot(128, 0, 34),
				RightElbow = rot(16, 0, 0),
				Weapon = rot(-50, 0, 15),
				LeftShoulder = rot(-26, 0, -34),
			},
			root = { pos = { 0, 0, -0.6 } },
		},
		{
			-- re-cock: the blade carries over the head, the elbow and wrist cock back
			time = 0.56,
			easing = "QuadIn",
			joints = {
				Root = posRot(0.04, -0.02, -0.1, 0, -8, -2),
				Waist = rot(14, -20, -6),
				Neck = rot(-6, 18, 1),
				RightShoulder = rot(148, 0, 24),
				RightElbow = rot(42, 0, 0),
				RightWrist = rot(-26, 0, -6),
				Weapon = rot(-34, 0, 4),
				LeftShoulder = rot(-18, 0, -30),
			},
			root = { pos = { 0, 0, -0.6 } },
		},
		{
			-- snap 2: the follow-through flick at the top, past the final pose
			time = 0.61,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.02, -0.08, -0.14, 0, -14, -4),
				Waist = rot(-4, -28, -10),
				Neck = rot(4, 24, 2),
				RightShoulder = rot(124, 0, 36),
				RightElbow = rot(6, 0, 0),
				RightWrist = rot(18, 0, -22),
				Weapon = rot(-78, 0, 24),
				LeftShoulder = rot(-28, 0, -38),
				LeftElbow = rot(34, 0, 0),
				LeftKnee = rot(-12, 0, 0),
				LeftAnkle = rot(-12, 0, 0),
				RightKnee = rot(-14, 0, 0),
				RightAnkle = rot(54, 0, 0),
			},
			root = { pos = { 0, 0, -0.9 } },
		},
		{
			-- hold 2
			time = 0.64,
			easing = "Hold",
			joints = {
				Root = posRot(0.02, -0.08, -0.14, 0, -14, -4),
			},
			root = { pos = { 0, 0, -0.9 } },
		},
		{
			-- settle 2: the flick springs back 5-8 degrees
			time = 0.75,
			easing = "Spring",
			joints = {
				Root = posRot(0.02, -0.12, -0.14, 0, -12, -3),
				Waist = rot(2, -22, -8),
				Neck = rot(2, 20, 2),
				RightShoulder = rot(118, 0, 30),
				RightElbow = rot(12, 0, 0),
				RightWrist = rot(12, 0, -16),
				Weapon = rot(-72, 0, 18),
				LeftShoulder = rot(-22, 0, -36),
			},
			root = { pos = { 0, 0, -1 } },
		},
		{
			-- end pose: the heels come down, the knees take the weight, the blade stays high
			time = 0.9,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.24, -0.1, 0, -10, -2),
				Waist = rot(0, -20, -6),
				Neck = rot(4, 18, 1),
				RightShoulder = rot(116, 0, 30),
				RightElbow = rot(14, 0, 0),
				Weapon = rot(-70, 0, 16),
				LeftShoulder = rot(-20, 0, -34),
				LeftHip = rot(22, 0, -6),
				LeftKnee = rot(-28, 0, 0),
				LeftAnkle = rot(4, 0, 0),
				RightHip = rot(-14, 0, 8),
				RightKnee = rot(-26, 0, 0),
				RightAnkle = rot(42, 0, 0),
			},
			root = { pos = { 0, 0, -1 } },
		},
		{
			-- post-motion micro keys: caught under the raised blade
			time = 1.05,
			easing = "SineInOut",
			joints = {
				Waist = rot(1, -20, -6),
				Neck = rot(5, 18, 1),
				Weapon = rot(-69, 0, 17),
				RightWrist = rot(13, 0, -15),
			},
		},
		{
			time = 1.2,
			easing = "SineInOut",
			joints = {
				Waist = rot(0, -20, -6),
				Neck = rot(3, 17, 1),
				Weapon = rot(-71, 0, 15),
				RightWrist = rot(11, 0, -17),
			},
		},
		{
			time = 1.4,
			easing = "SineInOut",
			joints = {
				LeftShoulder = rot(-18, 0, -34),
				RightShoulder = rot(115, 0, 30),
				RightWrist = rot(12, 0, -16),
			},
		},
	},
	events = {
		{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },
		{ time = 0.32, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.3333, kind = "SmearOn", data = { axis = "X" } },
		{ time = 0.34, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.35, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.3667, kind = "SmearOff" },
		{ time = 0.45, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 0.56, kind = "SmearOn", data = { axis = "Y" } },
		{ time = 0.57, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.58, kind = "HitWindowOpen", data = { hit = 2 } },
		{ time = 0.5933, kind = "SmearOff" },
		{ time = 0.68, kind = "HitWindowClose", data = { hit = 2 } },
		{ time = 0.72, kind = "TrailOff" },
		{ time = 0.9, kind = "PostMotionStart" },
	},
	beats = {
		Anticipation = { start = 0.25, finish = 0.3333 },
		Snap = { start = 0.3333, finish = 0.3833 },
		Smear = { start = 0.3333, finish = 0.3667 },
		Hold = { start = 0.3833, finish = 0.4167 },
		Settle = { start = 0.4167, finish = 0.5167 },
		Recovery = { start = 0.9, finish = 1.4 },
	},
}

return clip
