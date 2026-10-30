--!strict
--[[
	player/OneHandedSword/Horizontal: the first Art (section 8: 1 hit, startup 0.25, total 0.6,
	post-motion 0.4, 1 stud of root motion). A right-to-left cut at chest height.

	Timeline (section 6 / 10):
	  0.00-0.15  start pose (SineInOut): weight back onto the right leg, torso wound right, blade
	             drawn back level with the hip, the free hand opens toward the target
	  0.15-0.25  activation hold (the tell): the stance breathes, the blade lights
	  0.25-0.35  Anticipation (6 frames): the coil deepens, hips turn further right, the hand draws
	             back so the tip pulls back and right against the cut; the front foot lifts
	  0.35-0.40  Snap (3 frames, ExpoOut): the cut, torso whipped left, weight onto the left foot
	             as it steps in; the rear foot pushes off its toe
	  0.36-0.39  Smear (2 frames): on the snap's first two moving frames, off on the third
	  0.35-0.48  Hit window: opens on the snap's first frame (the trail ignites with it), so the
	             server sweeps the whole cut, and closes in the settle
	  0.40-0.43  Hold (the contact; hit-stop pauses the clock here on a hit)
	  0.43-0.55  Settle (QuadIn to 0.49, then QuadOut): a rebound a few degrees off the extreme,
	             the rear foot drawn up into the stance
	  0.60-1.00  Recovery / post-motion: flows back to the guard; the front foot leaves the field
	             by a hair at the end, so the blend back to a stance never drags it
	Re-key (D-374): the start pose eases in from the guard (an ExpoOut threw most of it into the
	first frame); both upper arms stay out of the head through the start pose and the coil (they
	sat 0.17 inside it) and the sword forearm off the chest through the cut and the settle (0.42
	inside it); the hips stay down through the cut; the root's last 0.3 studs come in the settle's
	first half (QuadIn), not through a spring, so the planted front foot does not slide.
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
	duration = 1,
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
			-- start pose
			time = 0.15,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.1, -0.2, 0.05, 0, -6, 0),
				Waist = rot(-6, -29, -4),
				Neck = rot(6, 29, 2),
				RightShoulder = rot(-48.9, 3.2, 52.6),
				RightElbow = rot(44, 0, 0),
				RightWrist = rot(7, -24.4, -10.5),
				Weapon = rot(-30, 0, -8),
				LeftShoulder = rot(58.4, -3.8, -19.9),
				LeftElbow = rot(6.7, 0, 0),
				LeftWrist = rot(8.4, -5.8, 22.6),
				LeftHip = rot(29.1, -3, -10.2),
				LeftKnee = rot(-48, 0, 0),
				LeftAnkle = rot(17.4, 5.5, 10.5),
				RightHip = rot(8.7, 2, 5.4),
				RightKnee = rot(-52.3, 0, 0),
				RightAnkle = rot(32, 6.8, -4.3),
			},
		},
		{
			-- activation hold: alive, not paused
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.11, -0.22, 0.06, 0, -6, 0),
				Waist = rot(-2, -32, 0),
				Neck = rot(4, 31, 0),
				Weapon = rot(-32, 0, -10),
				LeftWrist = rot(8.1, -8.9, 24.7),
				LeftAnkle = rot(18.1, 5.5, 10.9),
				LeftElbow = rot(0, 0, 0),
				LeftHip = rot(30.7, -3.5, -10.6),
				LeftKnee = rot(-50.4, 0, 0),
				LeftShoulder = rot(62.2, -5.2, -17.7),
				RightAnkle = rot(33.4, 6.8, -4),
				RightElbow = rot(29.4, 0, 0),
				RightHip = rot(10.4, 2.1, 5),
				RightKnee = rot(-55.3, 0, 0),
				RightShoulder = rot(-43.2, 11, 51.7),
				RightWrist = rot(9.6, -23.4, -14.2),
			},
		},
		{
			-- anticipation: the coil
			time = 0.35,
			easing = "QuadIn",
			joints = {
				Root = posRot(0.16, -0.26, 0.08, 0, -10, -2),
				Waist = rot(-2, -42, 0),
				Neck = rot(4, 40, 0),
				RightShoulder = rot(-48.5, 23.3, 62),
				RightElbow = rot(0, 0, 0),
				Weapon = rot(-34, 0, -12),
				LeftShoulder = rot(52.3, 11.6, -23),
				LeftElbow = rot(30, 0, 0),
				RightKnee = rot(-64.1, 0, 0),
				RightAnkle = rot(36.4, 10.2, -2.8),
				LeftAnkle = rot(16.9, 7.9, 16.2),
				LeftHip = rot(60.4, -10.4, -12.5),
				LeftKnee = rot(-73.4, 0, 0),
				LeftWrist = rot(-4.1, -15, 29.4),
				RightHip = rot(16.2, 3.5, 6.1),
				RightWrist = rot(30.4, -42.2, -10.4),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap: the cut, past the final pose
			time = 0.4,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.12, -0.16, -0.1, 0, 12, 4),
				Waist = rot(-12, 42, 8),
				Neck = rot(1, -28, -2),
				RightShoulder = rot(53.3, 6.7, -5.8),
				RightElbow = rot(25.9, 0, 0),
				RightWrist = rot(-10.9, -6.3, -27.5),
				Weapon = rot(-62, 0, -26),
				LeftShoulder = rot(-34, 0, -32),
				LeftElbow = rot(42, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(37.5, -0.2, -4.1),
				LeftKnee = rot(-42.8, 0, 0),
				LeftAnkle = rot(5.3, -12.3, -0.7),
				RightHip = rot(-20.1, -0.1, -0.1),
				RightKnee = rot(-42.4, 0, 0),
				RightAnkle = rot(11.7, -3.9, -10.9),
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
			time = 0.49,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(19.4, -10.8, 2.5),
				LeftHip = rot(33, -0.6, -6.2),
				LeftKnee = rot(-51.9, 0, 0),
				LeftShoulder = rot(-28, 0, -30),
				Neck = rot(2, -28, -1),
				RightAnkle = rot(23.3, -2.7, -10.8),
				RightElbow = rot(51.9, 0, 0),
				RightHip = rot(-9.7, 0.2, 2.8),
				RightKnee = rot(-59.4, 0, 0),
				RightShoulder = rot(30.4, 6.7, -4.2),
				RightWrist = rot(-15.2, -11.3, -7.1),
				Root = posRot(-0.1, -0.18, -0.08, 0, 10, 3),
				Waist = rot(-10, 45, 6),
				Weapon = rot(-60, 0, -20),
			},
			root = { pos = { 0, 0, -1 } },
		},
		{
			-- settle: back 5-8 degrees from the extreme
			time = 0.55,
			easing = "QuadOut",
			joints = {
				Root = posRot(-0.1, -0.18, -0.08, 0, 10, 3),
				Waist = rot(-10, 45, 6),
				Neck = rot(2, -28, -1),
				RightShoulder = rot(30.4, 6.7, -4.2),
				RightElbow = rot(51.9, 0, 0),
				Weapon = rot(-60, 0, -20),
				LeftShoulder = rot(-28, 0, -30),
				RightAnkle = rot(31.4, -9.6, -8.1),
				RightHip = rot(-9.1, 1.7, 3.1),
				RightKnee = rot(-35.5, 0, 0),
			},
			root = { pos = { 0, 0, -1 } },
		},
		{
			-- post-motion micro keys: caught in the stance
			time = 0.75,
			easing = "SineInOut",
			joints = {
				Waist = rot(-9.3, 25.1, 3.9),
				Neck = rot(3.4, -14, -0.6),
				Weapon = rot(-56.5, 0, -13),
				RightWrist = rot(-18.6, -7.4, -4.6),
				LeftAnkle = rot(17.3, -7.3, 3.8),
				LeftElbow = rot(44.8, 0, 0),
				LeftHip = rot(30.4, -0.4, -6.4),
				LeftKnee = rot(-47.4, 0, 0),
				LeftShoulder = rot(-9.5, 0, -24.7),
				LeftWrist = rot(0, 0, 3.5),
				RightAnkle = rot(31.3, -7, -7.8),
				RightElbow = rot(46, 0, 0),
				RightHip = rot(-4.9, 2.6, 4.4),
				RightKnee = rot(-39.2, 0, 0),
				RightShoulder = rot(30.2, 4.3, 0.8),
				Root = posRot(-0.065, -0.159, -0.052, 0, 6.5, 2),
			},
		},
		{
			time = 0.9,
			easing = "SineInOut",
			joints = {
				Waist = rot(-8.6, 5.1, 1.8),
				Neck = rot(4.8, 0, -0.3),
				Weapon = rot(-53, 0, -6),
				RightWrist = rot(-22.1, -3.4, -2.1),
				LeftAnkle = rot(15, -3.9, 5.1),
				LeftElbow = rot(47.6, 0, 0),
				LeftHip = rot(27.4, -0.2, -6.6),
				LeftKnee = rot(-42.2, 0, 0),
				LeftShoulder = rot(9.1, 0, -19.5),
				LeftWrist = rot(0, 0, 7),
				RightAnkle = rot(30.8, -4.2, -7.4),
				RightElbow = rot(40.1, 0, 0),
				RightHip = rot(-1.2, 3.6, 5.5),
				RightKnee = rot(-42.2, 0, 0),
				RightShoulder = rot(30.1, 2, 5.7),
				Root = posRot(-0.03, -0.138, -0.024, 0, 3, 0.9),
			},
		},
		{
			time = 1,
			easing = "SineInOut",
			joints = {
				LeftShoulder = rot(17, 0, -17.2),
				RightShoulder = rot(30.1, 1, 7.9),
				RightWrist = rot(-23.5, -1.7, -1.1),
				LeftAnkle = rot(17.9, -2.4, 5.8),
				LeftElbow = rot(48.8, 0, 0),
				LeftHip = rot(30.8, -0.7, -6.9),
				LeftKnee = rot(-48.6, 0, 0),
				LeftWrist = rot(0, 0, 8.5),
				Neck = rot(5.4, 6, -0.2),
				RightAnkle = rot(30.5, -2.9, -7.1),
				RightElbow = rot(37.5, 0, 0),
				RightHip = rot(0.3, 3.9, 5.9),
				RightKnee = rot(-43.3, 0, 0),
				Root = posRot(-0.015, -0.129, -0.012, 0, 1.5, 0.5),
				Waist = rot(-8.3, -3.4, 0.9),
				Weapon = rot(-51.5, 0, -3),
			},
		},
	},
	events = {
		{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },
		{ time = 0.29, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.35, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.35, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.3583, kind = "SmearOn", data = { axis = "X" } },
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
