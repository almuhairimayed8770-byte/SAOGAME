--!strict
--[[
	player/OneHandedSword/Basic3: the third basic: a diagonal cut from high right down to the left
	with a committed step, the chain finisher, ending low on the left with the point just off the
	grass (combat.luau basicHitDuration 0.35; the clip runs to 0.45 so the pose drifts toward ready
	inside the chain window and blends cleanly into the next basic). Six beats like every attack: a
	6-frame anticipation from the ready stance, a 3-frame ExpoOut snap with a thin white trail and
	the hit window opening on its first frame, a 2-frame hold on contact, a spring settle, a short
	recovery. No activation hold: basics have no tell.
	Re-key (D-373): a smaller, slower wind-up: the blade is raised high on the right (it swung over
	the head behind, the sword hand turning 37 degrees in a frame), through a middle key at 0.067
	(QuadIn, then SineInOut). The torso turns into the diagonal so the sword arm clears the chest
	and the hip (the forearm sat 0.77 inside the chest); the settle rebounds half as far off the
	extreme. The committed step lands on the snap and the rear foot is drawn up in the recovery
	(QuadIn, then QuadOut through 0.365); the recovery ends a quarter of the way back to the ready
	guard.
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
	id = "player/OneHandedSword/Basic3",
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
				LeftAnkle = rot(26.9, 2.3, 8.5),
				LeftElbow = rot(41.3, 0, 0),
				LeftHip = rot(45.4, -4.8, -7.7),
				LeftKnee = rot(-65, 0, 0),
				LeftShoulder = rot(33.1, 0, -20.6),
				LeftWrist = rot(0, 0, 16.2),
				Neck = rot(2.3, 15.7, 0.6),
				RightAnkle = rot(14.5, 6.2, -3.8),
				RightElbow = rot(71, 0, 0),
				RightHip = rot(14.8, 2.8, 5.9),
				RightKnee = rot(-58.9, 0, 0),
				RightShoulder = rot(20, 16.7, 23.3),
				RightWrist = rot(-30.9, -12.2, 7.9),
				Root = posRot(0.05, -0.12, 0.025, 0, -3.7, 0),
				Waist = rot(-1.8, -14.5, -2.5),
				Weapon = rot(-43.8, 0, -5),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- anticipation
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.08, -0.12, 0.04, 0, -6, 0),
				Waist = rot(2, -16, -4),
				Neck = rot(0, 18, 1),
				RightShoulder = rot(13.8, 26.9, 31.4),
				RightElbow = rot(93, 0, 0),
				RightWrist = rot(-34.5, -19.7, 12.7),
				Weapon = rot(-40, 0, -8),
				LeftShoulder = rot(38, 0, -24),
				LeftElbow = rot(36, 0, 0),
				LeftWrist = rot(0, 0, 20),
				RightKnee = rot(-45.6, 0, 0),
				RightAnkle = rot(23.8, 7.3, -4.3),
				LeftAnkle = rot(26.8, 4.4, 9.8),
				LeftHip = rot(44.4, -5.5, -9),
				LeftKnee = rot(-64.6, 0, 0),
				RightHip = rot(6.3, 1.8, 5.9),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap
			time = 0.15,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.08, -0.26, -0.1, 0, 8, 3),
				Waist = rot(-12, 35, 10),
				Neck = rot(-2, -23, -3),
				RightShoulder = rot(16.9, -3.2, -0.4),
				RightElbow = rot(0, 0, 0),
				RightWrist = rot(-7.4, -4.8, -33.9),
				Weapon = rot(-20, 0, -16),
				LeftShoulder = rot(-24, 0, -28),
				LeftElbow = rot(42, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(39.3, -0.4, -5.1),
				LeftKnee = rot(-62.1, 0, 0),
				LeftAnkle = rot(23.1, -13.9, 1.2),
				RightHip = rot(-40, -1.7, 1.3),
				RightKnee = rot(0, 0, 0),
				RightAnkle = rot(9.5, -3.1, -7.7),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			time = 0.18,
			easing = "Hold",
			joints = {
				Root = posRot(-0.08, -0.26, -0.1, 0, 8, 3),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			-- out of the hold (QuadIn): the settle starts slow, so the first frame after a freeze barely moves
			time = 0.23,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(25.15, -13.65, 1.65),
				LeftHip = rot(37.6, -0.4, -5.35),
				LeftKnee = rot(-62.35, 0, 0),
				LeftShoulder = rot(-23.1, 0, -27.7),
				Neck = rot(-1.25, -23.75, -2.7),
				RightAnkle = rot(7.3, -2.5, -7.7),
				RightElbow = rot(0, 0, 0),
				RightHip = rot(-40.75, -1.8, 1.45),
				RightShoulder = rot(15.9, -4.25, 0.4),
				RightWrist = rot(-3.3, -6.1, -31.05),
				Root = posRot(-0.077, -0.26, -0.1, 0, 7.7, 2.85),
				Waist = rot(-12.6, 36.5, 9.25),
				Weapon = rot(-19.7, 0, -15.4),
			},
			root = { pos = { 0, 0, -0.55 } },
		},
		{
			-- settle
			time = 0.28,
			easing = "Spring",
			joints = {
				Root = posRot(-0.074, -0.26, -0.1, 0, 7.4, 2.7),
				Waist = rot(-13.2, 38, 8.5),
				Neck = rot(-0.5, -24.5, -2.4),
				RightShoulder = rot(14.9, -5.3, 1.2),
				RightElbow = rot(0, 0, 0),
				Weapon = rot(-19.4, 0, -14.8),
				LeftShoulder = rot(-22.2, 0, -27.4),
				LeftAnkle = rot(27.2, -13.4, 2.1),
				LeftHip = rot(35.9, -0.4, -5.6),
				LeftKnee = rot(-62.6, 0, 0),
				RightAnkle = rot(5.1, -1.9, -7.7),
				RightHip = rot(-41.5, -1.9, 1.6),
				RightWrist = rot(0.8, -7.4, -28.2),
			},
			root = { pos = { 0, 0, -0.6 } },
		},
		{
			time = 0.365,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(23.1, -10.4, 3),
				LeftElbow = rot(44.5, 0, 0),
				LeftHip = rot(31.6, 0.2, -5.2),
				LeftKnee = rot(-54.2, 0, 0),
				LeftShoulder = rot(-2.7, 0, -22.3),
				LeftWrist = rot(0, 0, 1.2),
				Neck = rot(2.7, -10, -1.2),
				RightAnkle = rot(29.6, -2.1, -8.1),
				RightElbow = rot(14.1, 0, 0),
				RightHip = rot(-6.9, 1.6, 5),
				RightKnee = rot(-51.1, 0, 0),
				RightShoulder = rot(23.5, -0.8, -0.6),
				RightWrist = rot(-3.6, -5.6, -10.9),
				Root = posRot(-0.045, -0.205, -0.065, 0, 4.5, 1.4),
				Waist = rot(-12.1, 17.5, 4.6),
				Weapon = rot(-36.9, 0, -8.9),
			},
			root = { pos = { 0, 0, -0.6 } },
		},
		{
			-- recovery: drifting toward ready inside the chain window
			time = 0.45,
			easing = "QuadOut",
			joints = {
				Root = posRot(-0.015, -0.15, -0.03, 0, 1.5, 0),
				Waist = rot(-11, -3, 0.8),
				Neck = rot(6, 4.5, 0),
				RightShoulder = rot(32.1, 3.8, -2.5),
				RightElbow = rot(28.2, 0, 0),
				Weapon = rot(-54.5, 0, -3),
				LeftShoulder = rot(16.8, 0, -17.2),
				LeftElbow = rot(47, 0, 0),
				LeftKnee = rot(-44.3, 0, 0),
				RightKnee = rot(-47.2, 0, 0),
				LeftAnkle = rot(18.3, -7.4, 3.9),
				LeftHip = rot(26.5, 0.9, -4.8),
				LeftWrist = rot(0, 0, 2.5),
				RightAnkle = rot(35.8, -2.8, -7.2),
				RightHip = rot(1, 3.7, 6.5),
				RightWrist = rot(-8.1, -3.8, 6.3),
			},
		},
	},
	events = {
		{ time = 0, kind = "Sfx", data = { name = "whoosh.Basic" } },
		{ time = 0.1, kind = "TrailOn", data = { kind = "Basic" } },
		{ time = 0.1, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.1083, kind = "SmearOn", data = { axis = "Y" } },
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
