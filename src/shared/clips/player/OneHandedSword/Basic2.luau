--!strict
--[[
	player/OneHandedSword/Basic2: the second basic: the backhand return, left to right, the wrist turning the edge over
	(combat.luau basicHitDuration 0.35; the clip runs to 0.45 so the pose drifts toward ready inside
	the chain window and blends cleanly into the next basic). Six beats like every attack: a
	6-frame anticipation from the ready stance, a 3-frame ExpoOut snap with a thin white trail and
	the hit window opening on its first frame, a 2-frame hold on contact, a spring settle, a short
	recovery. No activation hold: basics have no tell.
	Re-key (D-373): the backhand is cocked further left and forward of the chest, the torso turned
	into the wind-up (the sword forearm sat 0.64 inside the chest); the wind-up passes a middle key
	at 0.067 (QuadIn, then SineInOut into the cocked pose), so its last frame before the snap is
	not its fastest. The front foot steps in on the snap and the rear foot is drawn up in the
	recovery (QuadIn, then QuadOut through 0.365); the recovery ends a quarter of the way back to
	the ready guard.
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
	id = "player/OneHandedSword/Basic2",
	rig = "PlayerR15",
	duration = 0.45,
	loop = false,
	layer = "FullBody",
	priority = 15,
	attack = true,
	hitStop = "Normal",
	blendIn = 0.06,
	blendOut = 0.15,
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
			time = 0.0667,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(30.4, -4.8, 5.2),
				LeftHip = rot(46.6, -2.3, -4),
				LeftKnee = rot(-68.6, 0, 0),
				LeftShoulder = rot(9.5, 0, -21.8),
				LeftWrist = rot(0, 0, 3.8),
				Neck = rot(5.4, -9.1, -0.6),
				RightAnkle = rot(16.2, -0.1, -8.1),
				RightElbow = rot(50.6, 0, 0),
				RightHip = rot(8.6, 2.5, 6.7),
				RightKnee = rot(-55.2, 0, 0),
				RightShoulder = rot(29.5, -1.8, 8.5),
				RightWrist = rot(-33.6, -1.8, -12.6),
				Root = posRot(-0.037, -0.132, -0.012, 0, 3.7, 0),
				Waist = rot(-8, 14, 2.5),
				Weapon = rot(-52.5, 0, -14.9),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- anticipation
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.06, -0.14, -0.02, 0, 6, 0),
				Waist = rot(-8, 30, 4),
				Neck = rot(5, -22, -1),
				RightShoulder = rot(29.2, -2.9, 7.6),
				RightElbow = rot(60.2, 0, 0),
				RightWrist = rot(-38.8, -3, -20.3),
				Weapon = rot(-54, 0, -24),
				LeftShoulder = rot(0, 0, -26),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftAnkle = rot(30.3, -7, 4.3),
				LeftHip = rot(47.6, -1.7, -3),
				LeftKnee = rot(-69.4, 0, 0),
				RightAnkle = rot(24.6, -4.2, -7.8),
				RightHip = rot(-4.8, 0.7, 6.3),
				RightKnee = rot(-36.4, 0, 0),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap
			time = 0.15,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.08, -0.14, -0.04, 0, -8, -2),
				Waist = rot(-8, -26, -6),
				Neck = rot(3, 20, 1),
				RightShoulder = rot(52, 0, 40),
				RightElbow = rot(12, 0, 0),
				RightWrist = rot(4, 0, -12),
				Weapon = rot(-56, 0, 26),
				LeftShoulder = rot(36, 0, -34),
				LeftElbow = rot(34, 0, 0),
				LeftWrist = rot(0, 0, 20),
				LeftKnee = rot(-38.1, 0, 0),
				RightKnee = rot(-46.5, 0, 0),
				RightAnkle = rot(19.6, 9, -3.5),
				LeftAnkle = rot(15.8, 3.4, 7.5),
				LeftHip = rot(21.7, -0.6, -5.7),
				RightHip = rot(-2.5, 2.5, 9.6),
			},
			root = { pos = { 0, 0, -0.3 } },
		},
		{
			time = 0.18,
			easing = "Hold",
			joints = {
				Root = posRot(0.08, -0.14, -0.04, 0, -8, -2),
			},
			root = { pos = { 0, 0, -0.3 } },
		},
		{
			-- out of the hold (QuadIn): the settle starts slow, so the first frame after a freeze barely moves
			time = 0.23,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(17.65, 2.4, 7),
				LeftHip = rot(21.1, -0.55, -5.7),
				LeftKnee = rot(-39.2, 0, 0),
				LeftShoulder = rot(33, 0, -32),
				Neck = rot(3.5, 18, 1),
				RightAnkle = rot(17.05, 8.5, -3.5),
				RightElbow = rot(14, 0, 0),
				RightHip = rot(-4.3, 2.05, 9.15),
				RightKnee = rot(-45.2, 0, 0),
				RightShoulder = rot(49, 0, 37),
				Root = posRot(0.07, -0.14, -0.04, 0, -7, -1.5),
				Waist = rot(-8, -23, -5),
				Weapon = rot(-55, 0, 23),
			},
			root = { pos = { 0, 0, -0.35 } },
		},
		{
			-- settle
			time = 0.28,
			easing = "Spring",
			joints = {
				Root = posRot(0.06, -0.14, -0.04, 0, -6, -1),
				Waist = rot(-8, -20, -4),
				Neck = rot(4, 16, 1),
				RightShoulder = rot(46, 0, 34),
				RightElbow = rot(16, 0, 0),
				Weapon = rot(-54, 0, 20),
				LeftShoulder = rot(30, 0, -30),
				LeftAnkle = rot(19.5, 1.4, 6.5),
				LeftHip = rot(20.5, -0.5, -5.7),
				LeftKnee = rot(-40.3, 0, 0),
				RightAnkle = rot(14.5, 8, -3.5),
				RightHip = rot(-6.1, 1.6, 8.7),
				RightKnee = rot(-43.9, 0, 0),
			},
			root = { pos = { 0, 0, -0.4 } },
		},
		{
			time = 0.365,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(18.2, -0.8, 5.8),
				LeftElbow = rot(41.2, 0, 0),
				LeftHip = rot(21.5, -0.5, -5.5),
				LeftKnee = rot(-39.7, 0, 0),
				LeftShoulder = rot(27.9, 0, -23.6),
				LeftWrist = rot(0, 0, 18.8),
				Neck = rot(4.6, 14, 0.5),
				RightAnkle = rot(26.1, 5.9, -5.6),
				RightElbow = rot(22.9, 0, 0),
				RightHip = rot(5.3, 2.9, 8),
				RightKnee = rot(-59, 0, 0),
				RightShoulder = rot(40.2, 0, 25),
				RightWrist = rot(0.4, 0, -10.5),
				Root = posRot(0.038, -0.13, -0.028, 0, -3.8, -0.5),
				Waist = rot(-8, -16.7, -2.4),
				Weapon = rot(-52.7, 0, 12.3),
			},
			root = { pos = { 0, 0, -0.4 } },
		},
		{
			-- recovery: drifting toward ready inside the chain window
			time = 0.45,
			easing = "QuadOut",
			joints = {
				Root = posRot(0.015, -0.12, -0.015, 0, -1.5, 0),
				Waist = rot(-8, -13.5, -0.7),
				Neck = rot(5.3, 12, 0),
				RightShoulder = rot(34.5, 0, 16),
				RightElbow = rot(29.7, 0, 0),
				Weapon = rot(-51.5, 0, 4.5),
				LeftShoulder = rot(25.8, 0, -17.2),
				LeftElbow = rot(48.5, 0, 0),
				LeftAnkle = rot(16.8, -3, 5),
				LeftHip = rot(22.3, -0.5, -5.2),
				LeftKnee = rot(-38.9, 0, 0),
				LeftWrist = rot(0, 0, 17.5),
				RightAnkle = rot(33.6, 2.1, -7.2),
				RightHip = rot(2.5, 2, 7.4),
				RightKnee = rot(-45.9, 0, 0),
				RightWrist = rot(-3.2, 0, -9),
			},
		},
	},
	events = {
		{ time = 0, kind = "Sfx", data = { name = "whoosh.Basic" } },
		{ time = 0.1, kind = "TrailOn", data = { kind = "Basic" } },
		{ time = 0.1, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.1083, kind = "SmearOn", data = { axis = "X" } },
		{ time = 0.1417, kind = "SmearOff" },
		{ time = 0.24, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 0.27, kind = "TrailOff" },
		{ time = 0.3, kind = "PostMotionStart" },
	},
	beats = {
		Anticipation = { start = 0, finish = 0.1 },
		Snap = { start = 0.1, finish = 0.15 },
		Smear = { start = 0.1083, finish = 0.1417 },
		Hold = { start = 0.15, finish = 0.18 },
		Settle = { start = 0.18, finish = 0.28 },
		Recovery = { start = 0.3, finish = 0.45 },
	},
}

return clip
