--!strict
--[[
	player/OneHandedSword/Vertical: the overhead cut (section 8: 1 hit, startup 0.25, total 0.6,
	post-motion 0.4, no root motion; guard-gauge heavy).

	Timeline:
	  0.00-0.15  start pose (SineInOut): the blade raised upright beside the head, the back arches,
	             weight back
	  0.15-0.25  activation hold: the blade lights and holds still, the arch breathes
	  0.25-0.35  Anticipation (6 frames): the hands rise and draw back over the right shoulder, the
	             blade cocking back against the chop, the rear heel up onto its toe, the arch
	             deepens, the free hand opens
	  0.35-0.40  Snap (3 frames): the chop, the whole body folding down behind it, the torso
	             squaring left so the blade falls on the centre line; it ends low and committed,
	             the blade angled forward and down, the point just above the ground
	  0.36-0.39  Smear (2 frames): on the snap's first two moving frames, off on the third
	  0.35-0.48  Hit window: opens on the snap's first frame (the trail ignites with it), so the
	             server sweeps the whole chop, and closes in the settle
	  0.40-0.43  Hold
	  0.43-0.55  Settle (Spring): the torso and the sword arm spring back 5-6 degrees, the point
	             lifts about half a stud off the ground
	  0.60-1.00  Recovery / post-motion: rises out of the crouch back up to the guard; the rear toe
	             leaves the field by a hair at the end, so the blend back never drags it
	Re-key (D-375): the old start pose behind the head turned the sword hand 79 degrees in a frame;
	the raise beside the head fits the pop rule over its 9 frames. Both feet stay planted under the
	crouch (the front foot slid and sank 0.29 into the field); a 0.15 s blend out.
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
	id = "player/OneHandedSword/Vertical",
	rig = "PlayerR15",
	duration = 1,
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
		},
		{
			-- start pose: the blade high behind the head
			time = 0.15,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.04, -0.14, 0.08, 0, -4, 0),
				Waist = rot(10, -14, -3),
				Neck = rot(-4, 14, 0),
				RightShoulder = rot(76.5, 2.8, -6.7),
				RightElbow = rot(31.7, 0, 0),
				RightWrist = rot(-23.9, 1.7, -16),
				Weapon = rot(0, 0, 0),
				LeftShoulder = rot(46, 0, -22),
				LeftElbow = rot(26, 0, 0),
				LeftWrist = rot(0, 0, 24),
				LeftHip = rot(26.4, -1.3, -8.3),
				LeftKnee = rot(-39.1, 0, 0),
				LeftAnkle = rot(12, 3.5, 8),
				RightHip = rot(5.1, 2.4, 6.3),
				RightKnee = rot(-43.8, 0, 0),
				RightAnkle = rot(27, 4.4, -5.7),
			},
		},
		{
			-- activation hold
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Waist = rot(10, -14, -3),
				RightShoulder = rot(76.5, 2.8, -6.7),
				Weapon = rot(0, 0, 0),
				LeftWrist = rot(0, 0, 24),
			},
		},
		{
			-- anticipation: onto the toes, the arch deepens
			time = 0.35,
			easing = "QuadIn",
			joints = {
				Root = posRot(0.04, -0.06, 0.1, 0, -6, 0),
				Waist = rot(10, -14, -3),
				Neck = rot(-4, 14, 0),
				RightShoulder = rot(86, 0.1, -4.9),
				RightElbow = rot(71.5, 0, 0),
				Weapon = rot(0, 0, 0),
				LeftShoulder = rot(46, 0, -22),
				LeftAnkle = rot(3.3, 5.5, 7.9),
				RightAnkle = rot(8.7, 7.7, -3.4),
				LeftHip = rot(16, 0.2, -8.3),
				LeftKnee = rot(-20.2, 0, 0),
				RightHip = rot(16.2, 3.8, 6),
				RightKnee = rot(-54.5, 0, 0),
				RightWrist = rot(-30.6, -11.3, -14.8),
			},
		},
		{
			-- snap: the chop, ending low with the point just above the ground
			time = 0.4,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.42, -0.06, 0, 4, 0),
				Waist = rot(-36, 12, 2),
				Neck = rot(-6, -12, 0),
				RightShoulder = rot(40, 0, 2),
				RightElbow = rot(6, 0, 0),
				RightWrist = rot(-8, 0, 0),
				Weapon = rot(-19, 0, 0),
				LeftShoulder = rot(-26, 0, -28),
				LeftElbow = rot(40, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(45.6, -1.9, -8.2),
				LeftKnee = rot(-75.9, 0, 0),
				LeftAnkle = rot(30.7, -6.5, 7.1),
				RightHip = rot(17.2, 4.2, 5),
				RightKnee = rot(-82, 0, 0),
				RightAnkle = rot(34.4, -1.8, -8),
			},
		},
		{
			time = 0.43,
			easing = "Hold",
			joints = {
				Root = posRot(0, -0.42, -0.06, 0, 4, 0),
			},
		},
		{
			-- out of the hold (QuadIn): the settle starts slow, so the first frame after a freeze barely moves
			time = 0.49,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(30.2, -6, 7.1),
				LeftHip = rot(45, -1.8, -8.2),
				LeftKnee = rot(-74.9, 0, 0),
				LeftShoulder = rot(-24, 0, -27),
				Neck = rot(-4, -11, 0),
				RightAnkle = rot(36.15, -1.75, -7.75),
				RightElbow = rot(6, 0, 0),
				RightHip = rot(15.65, 4.1, 5.15),
				RightKnee = rot(-79.2, 0, 0),
				RightShoulder = rot(43, 0, 3),
				Root = posRot(0, -0.41, -0.055, 0, 3.5, 0),
				Waist = rot(-33.5, 11, 2),
				Weapon = rot(-23, 0, 0),
			},
		},
		{
			-- settle: the torso and the sword arm spring back 5-6 degrees, the point lifts off the ground
			time = 0.55,
			easing = "Spring",
			joints = {
				Root = posRot(0, -0.4, -0.05, 0, 3, 0),
				Waist = rot(-31, 10, 2),
				Neck = rot(-2, -10, 0),
				RightShoulder = rot(46, 0, 4),
				RightElbow = rot(6, 0, 0),
				Weapon = rot(-27, 0, 0),
				LeftShoulder = rot(-22, 0, -26),
				LeftAnkle = rot(29.7, -5.5, 7.1),
				LeftHip = rot(44.4, -1.7, -8.2),
				LeftKnee = rot(-73.9, 0, 0),
				RightAnkle = rot(37.9, -1.7, -7.5),
				RightHip = rot(14.1, 4, 5.3),
				RightKnee = rot(-76.4, 0, 0),
			},
		},
		{
			time = 0.75,
			easing = "SineInOut",
			joints = {
				Waist = rot(-23, 2.3, 1.3),
				Neck = rot(0.8, -2.3, 0),
				Weapon = rot(-35, 0, 0),
				RightWrist = rot(-13.9, 0, 0),
				LeftAnkle = rot(24.9, -4.4, 6.7),
				LeftElbow = rot(43.5, 0, 0),
				LeftHip = rot(38.6, -0.7, -8),
				LeftKnee = rot(-63.3, 0, 0),
				LeftShoulder = rot(-5.6, 0, -22.1),
				LeftWrist = rot(0, 0, 3.5),
				RightAnkle = rot(36.1, -1.5, -6.8),
				RightElbow = rot(16.2, 0, 0),
				RightHip = rot(8.3, 3.5, 5.6),
				RightKnee = rot(-62.7, 0, 0),
				RightShoulder = rot(40.4, 0, 6.1),
				Root = posRot(0, -0.302, -0.032, 0, 2, 0),
			},
		},
		{
			time = 0.9,
			easing = "SineInOut",
			joints = {
				Waist = rot(-14.9, -5.4, 0.6),
				Neck = rot(3.6, 5.4, 0),
				Weapon = rot(-43.1, 0, 0),
				RightWrist = rot(-19.9, 0, 0),
				LeftAnkle = rot(19.1, -3.3, 6.3),
				LeftElbow = rot(47, 0, 0),
				LeftHip = rot(31.9, 0.4, -7.7),
				LeftKnee = rot(-50.8, 0, 0),
				LeftShoulder = rot(10.9, 0, -18.3),
				LeftWrist = rot(0, 0, 7),
				RightAnkle = rot(31.5, -1.1, -6.4),
				RightElbow = rot(26.3, 0, 0),
				RightHip = rot(2.1, 2.9, 5.8),
				RightKnee = rot(-47.8, 0, 0),
				RightShoulder = rot(34.8, 0, 8.2),
				Root = posRot(0, -0.204, -0.015, 0, 0.9, 0),
			},
		},
		{
			time = 1,
			easing = "SineInOut",
			joints = {
				LeftShoulder = rot(17.9, 0, -16.6),
				RightShoulder = rot(32.4, 0, 9.1),
				RightWrist = rot(-22.4, 0, 0),
				LeftAnkle = rot(19.8, -2.9, 6.4),
				LeftElbow = rot(48.5, 0, 0),
				LeftHip = rot(32.9, 0.3, -7.8),
				LeftKnee = rot(-52.6, 0, 0),
				LeftWrist = rot(0, 0, 8.5),
				Neck = rot(4.8, 8.7, 0),
				RightAnkle = rot(33.8, -0.9, -6.5),
				RightElbow = rot(30.7, 0, 0),
				RightHip = rot(2.2, 3, 6),
				RightKnee = rot(-48.2, 0, 0),
				Root = posRot(0, -0.162, -0.007, 0, 0.5, 0),
				Waist = rot(-11.4, -8.7, 0.3),
				Weapon = rot(-46.5, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },
		{ time = 0.2, kind = "Sfx", data = { name = "whoosh.Large" } },
		{ time = 0.35, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.35, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.3583, kind = "SmearOn", data = { axis = "Y" } },
		{ time = 0.3917, kind = "SmearOff" },
		{ time = 0.48, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 0.52, kind = "TrailOff" },
		{ time = 0.6, kind = "PostMotionStart" },
	},
	beats = {
		Anticipation = { start = 0.25, finish = 0.35 },
		Snap = { start = 0.35, finish = 0.4 },
		Smear = { start = 0.3583, finish = 0.3917 },
		Hold = { start = 0.4, finish = 0.43 },
		Settle = { start = 0.43, finish = 0.55 },
		Recovery = { start = 0.6, finish = 1 },
	},
}

return clip
