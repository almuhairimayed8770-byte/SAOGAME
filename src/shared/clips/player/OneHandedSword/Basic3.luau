--!strict
--[[
	player/OneHandedSword/Basic3: the third basic: a diagonal cut from high right down to the left with a committed step, the chain finisher
	(combat.luau basicHitDuration 0.35; the clip runs to 0.45 so the pose drifts toward ready inside
	the chain window and blends cleanly into the next basic). Six beats like every attack: a
	6-frame anticipation from the ready stance, a 3-frame ExpoOut snap with a thin white trail, a
	2-frame hold on contact, a spring settle, a short recovery. No activation hold: basics have no
	tell.
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
				Root = posRot(0.08, -0.12, 0.04, 0, -6, 0),
				Waist = rot(2, -26, -4),
				Neck = rot(0, 24, 1),
				RightShoulder = rot(118, 0, 32),
				RightElbow = rot(50, 0, 0),
				RightWrist = rot(-12, 0, -8),
				Weapon = rot(-40, 0, -8),
				LeftShoulder = rot(38, 0, -24),
				LeftElbow = rot(36, 0, 0),
				LeftWrist = rot(0, 0, 20),
				RightKnee = rot(-32, 0, 0),
				RightAnkle = rot(44, 0, 0),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap
			time = 0.15,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.08, -0.26, -0.1, 0, 8, 3),
				Waist = rot(-24, 20, 6),
				Neck = rot(4, -14, -1),
				RightShoulder = rot(22, 0, -32),
				RightElbow = rot(8, 0, 0),
				RightWrist = rot(-4, 0, 8),
				Weapon = rot(-72, 0, -16),
				LeftShoulder = rot(-24, 0, -28),
				LeftElbow = rot(42, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(30, 0, -6),
				LeftKnee = rot(-40, 0, 0),
				LeftAnkle = rot(10, 0, 0),
				RightHip = rot(-28, 0, 8),
				RightKnee = rot(-8, 0, 0),
				RightAnkle = rot(36, 0, 0),
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
			-- settle
			time = 0.28,
			easing = "Spring",
			joints = {
				Root = posRot(-0.06, -0.26, -0.1, 0, 6, 2),
				Waist = rot(-20, 15, 5),
				Neck = rot(5, -10, -1),
				RightShoulder = rot(28, 0, -26),
				RightElbow = rot(12, 0, 0),
				Weapon = rot(-70, 0, -12),
				LeftShoulder = rot(-18, 0, -26),
			},
			root = { pos = { 0, 0, -0.6 } },
		},
		{
			-- recovery: drifting toward ready inside the chain window
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.02, -0.16, -0.04, 0, 2, 0),
				Waist = rot(-12, 0, 1),
				Neck = rot(6, 2, 0),
				RightShoulder = rot(34, 0, -8),
				RightElbow = rot(26, 0, 0),
				Weapon = rot(-56, 0, -4),
				LeftShoulder = rot(14, 0, -18),
				LeftElbow = rot(46, 0, 0),
				LeftKnee = rot(-24, 0, 0),
				RightKnee = rot(-22, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.09, kind = "TrailOn", data = { kind = "Basic" } },
		{ time = 0.1, kind = "SmearOn", data = { axis = "Y" } },
		{ time = 0.1, kind = "Sfx", data = { name = "BasicSwingHeavy" } },
		{ time = 0.12, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.1333, kind = "SmearOff" },
		{ time = 0.24, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 0.27, kind = "TrailOff" },
		{ time = 0.3, kind = "PostMotionStart" },
	},
	beats = {
		Anticipation = { start = 0, finish = 0.1 },
		Snap = { start = 0.1, finish = 0.15 },
		Smear = { start = 0.1, finish = 0.1333 },
		Hold = { start = 0.15, finish = 0.18 },
		Settle = { start = 0.18, finish = 0.28 },
		Recovery = { start = 0.3, finish = 0.45 },
	},
}

return clip
