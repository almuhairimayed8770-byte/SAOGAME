--!strict
--[[
	player/OneHandedSword/Basic1: the first basic: a quick forehand cut right to left at chest height, a half step in
	(combat.luau basicHitDuration 0.35; the clip runs to 0.45 so the pose drifts toward ready inside
	the chain window and blends cleanly into the next basic). Six beats like every attack: a
	6-frame anticipation from the ready stance, a 3-frame ExpoOut snap with a thin white trail and
	the hit window opening on its first frame, a 2-frame hold on contact, a spring settle, a short
	recovery. No activation hold: basics have no tell.
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
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap
			time = 0.15,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.06, -0.14, -0.04, 0, 6, 2),
				Waist = rot(-10, 18, 5),
				Neck = rot(3, -12, -1),
				RightShoulder = rot(56, 0, -26),
				RightElbow = rot(10, 0, 0),
				RightWrist = rot(2, 0, 8),
				Weapon = rot(-58, 0, -18),
				LeftShoulder = rot(-10, 0, -26),
				LeftElbow = rot(44, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftKnee = rot(-26, 0, 0),
				RightKnee = rot(-12, 0, 0),
				RightAnkle = rot(28, 0, 0),
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
			-- settle
			time = 0.28,
			easing = "Spring",
			joints = {
				Root = posRot(-0.05, -0.14, -0.04, 0, 5, 2),
				Waist = rot(-9, 13, 4),
				Neck = rot(4, -8, -1),
				RightShoulder = rot(50, 0, -20),
				RightElbow = rot(14, 0, 0),
				Weapon = rot(-56, 0, -14),
				LeftShoulder = rot(-6, 0, -24),
			},
			root = { pos = { 0, 0, -0.4 } },
		},
		{
			-- recovery: drifting toward ready inside the chain window
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.02, -0.12, -0.02, 0, 2, 0),
				Waist = rot(-8, 2, 1),
				Neck = rot(5, 0, 0),
				RightShoulder = rot(40, 0, -6),
				RightElbow = rot(24, 0, 0),
				Weapon = rot(-52, 0, -4),
				LeftShoulder = rot(10, 0, -18),
				LeftElbow = rot(46, 0, 0),
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
