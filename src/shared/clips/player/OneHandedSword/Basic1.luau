--!strict
--[[
	player/OneHandedSword/Basic1: the first basic: a quick forehand cut right to left at chest height, a half step in
	(combat.luau basicHitDuration 0.35; the clip runs to 0.45 so the pose drifts toward ready inside
	the chain window and blends cleanly into the next basic). Six beats like every attack: a
	6-frame anticipation from the ready stance, a 3-frame ExpoOut snap with a thin white trail and
	the hit window opening on its first frame, a 2-frame hold on contact, a spring settle, a short
	recovery. No activation hold: basics have no tell.
	Re-key (D-373): the front (left) foot leaves the field in the anticipation and steps in a third
	of a stud, landing on the snap; the rear foot stays on its toe through the settle and is drawn
	up after the root in the recovery (through a middle key at 0.365), so no planted foot slides
	while the root travels. The torso turns into the cut until the sword forearm clears the chest
	(it sat 0.36 inside it); the recovery ends 40% of the way back to the ready guard; a 0.09 s
	blend in.
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
	id = "player/OneHandedSword/Basic1",
	rig = "PlayerR15",
	duration = 0.45,
	loop = false,
	layer = "FullBody",
	priority = 15,
	attack = true,
	hitStop = "Normal",
	blendIn = 0.09,
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
			-- anticipation
			time = 0.1,
			easing = "QuadIn",
			joints = {
				Root = posRot(0.06, -0.14, 0.02, 0, -4, 0),
				Waist = rot(-6, -24, -3),
				Neck = rot(5, 22, 1),
				RightShoulder = rot(10, 0, 34),
				RightElbow = rot(50, 0, 0),
				RightWrist = rot(-10, 0, -14),
				Weapon = rot(-36, 0, -8),
				LeftShoulder = rot(34, 0, -22),
				LeftElbow = rot(40, 0, 0),
				LeftWrist = rot(0, 0, 18),
				LeftAnkle = rot(30.9, 6.1, 8.5),
				LeftHip = rot(44.4, -5, -8),
				LeftKnee = rot(-68.7, 0, 0),
				RightAnkle = rot(25.6, 5.4, -4.9),
				RightHip = rot(5.3, 1.7, 6.1),
				RightKnee = rot(-46.4, 0, 0),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap
			time = 0.15,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.06, -0.14, -0.04, 0, 6, 2),
				Waist = rot(-10, 43, 8),
				Neck = rot(3, -27, -2.5),
				RightShoulder = rot(13.8, 10, -1.4),
				RightElbow = rot(65.9, 0, 0),
				RightWrist = rot(-7.8, -21.9, 14.4),
				Weapon = rot(-58, 0, -18),
				LeftShoulder = rot(-10, 0, -26),
				LeftElbow = rot(44, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftKnee = rot(-44.3, 0, 0),
				RightKnee = rot(-27.9, 0, 0),
				RightAnkle = rot(13.7, -1.2, -7.9),
				LeftAnkle = rot(14.4, -4.3, 1.9),
				LeftHip = rot(30, -0.8, -4.1),
				RightHip = rot(-16.1, -1.2, 4),
			},
			root = { pos = { 0, 0, -0.3 } },
		},
		{
			time = 0.18,
			easing = "Hold",
			joints = {
				Root = posRot(-0.06, -0.14, -0.04, 0, 6, 2),
			},
			root = { pos = { 0, 0, -0.3 } },
		},
		{
			-- out of the hold (QuadIn): the settle starts slow, so the first frame after a freeze barely moves
			time = 0.23,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(16.5, -3.9, 2.3),
				LeftHip = rot(28.55, -0.8, -4.5),
				LeftKnee = rot(-44.95, 0, 0),
				LeftShoulder = rot(-8, 0, -25),
				Neck = rot(3.5, -22.75, -2.5),
				RightAnkle = rot(11.65, -0.35, -7.7),
				RightElbow = rot(59.7, 0, 0),
				RightHip = rot(-16.6, -1.2, 4.1),
				RightKnee = rot(-28.25, 0, 0),
				RightShoulder = rot(16, 10.3, -1.45),
				RightWrist = rot(-5.15, -21.55, 13.75),
				Root = posRot(-0.055, -0.14, -0.04, 0, 5.5, 2),
				Waist = rot(-9.5, 36.75, 7.5),
				Weapon = rot(-57, 0, -16),
			},
			root = { pos = { 0, 0, -0.35 } },
		},
		{
			-- settle
			time = 0.28,
			easing = "Spring",
			joints = {
				Root = posRot(-0.05, -0.14, -0.04, 0, 5, 2),
				Waist = rot(-9, 30.5, 7),
				Neck = rot(4, -18.5, -2.5),
				RightShoulder = rot(18.2, 10.6, -1.5),
				RightElbow = rot(53.5, 0, 0),
				Weapon = rot(-56, 0, -14),
				LeftShoulder = rot(-6, 0, -24),
				LeftAnkle = rot(18.6, -3.5, 2.7),
				LeftHip = rot(27.1, -0.8, -4.9),
				LeftKnee = rot(-45.6, 0, 0),
				RightAnkle = rot(9.6, 0.5, -7.5),
				RightHip = rot(-17.1, -1.2, 4.2),
				RightKnee = rot(-28.6, 0, 0),
				RightWrist = rot(-2.5, -21.2, 13.1),
			},
			root = { pos = { 0, 0, -0.4 } },
		},
		{
			time = 0.365,
			easing = "SineInOut",
			joints = {
				LeftAnkle = rot(16, 0, 3.9),
				LeftElbow = rot(47.2, 0, 0),
				LeftHip = rot(23.8, -0.3, -4.3),
				LeftKnee = rot(-39.8, 0, 0),
				LeftShoulder = rot(13.8, 0, -17.5),
				LeftWrist = rot(0, 0, 3.6),
				Neck = rot(5.3, 2.5, -0.2),
				RightAnkle = rot(25, 1.5, -7.4),
				RightElbow = rot(30.9, 0, 0),
				RightHip = rot(1.8, 1.9, 7),
				RightKnee = rot(-54.9, 0, 0),
				RightShoulder = rot(34.2, 1.1, 0.2),
				RightWrist = rot(-8.2, -2.1, 5.6),
				Root = posRot(-0.016, -0.122, -0.015, 0, 1.6, 0.2),
				Waist = rot(-8.1, -0.2, 1.2),
				Weapon = rot(-51.7, 0, -3.6),
			},
			root = { pos = { 0, 0, -0.4 } },
		},
		{
			-- recovery: drifting toward ready inside the chain window
			time = 0.45,
			easing = "QuadOut",
			joints = {
				Root = posRot(-0.012, -0.12, -0.012, 0, 1.2, 0),
				Waist = rot(-8, -3.6, 0.6),
				Neck = rot(5.4, 4.8, 0),
				RightShoulder = rot(36, 0, 0.4),
				RightElbow = rot(28.4, 0, 0),
				Weapon = rot(-51.2, 0, -2.4),
				LeftShoulder = rot(16, 0, -16.8),
				LeftElbow = rot(47.6, 0, 0),
				LeftAnkle = rot(15.6, 0.3, 4),
				LeftHip = rot(23.4, -0.2, -4.3),
				LeftKnee = rot(-39.1, 0, 0),
				LeftWrist = rot(0, 0, 4),
				RightAnkle = rot(33.4, -0.5, -7.5),
				RightHip = rot(0.7, 1.7, 7.3),
				RightKnee = rot(-44.2, 0, 0),
				RightWrist = rot(-8.8, 0, 4.8),
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
