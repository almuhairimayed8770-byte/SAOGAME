--!strict
--[[
	player/OneHandedSword/TurnLeftDraw: turn in place to the left from the sheathed stance into the
	drawn one, for a lock-on that draws the sword under the turn; TurnRightDraw's twin (D-640).
	From the sheathed stance the left foot steps forward under the body, the inner corner of its
	heel on the root's axis as the drawn turn sets it (Footstep), while the hips sink to the drawn
	stance's height over the right foot, its leg solved at every key to hold it where the sheathed
	stance has it. The right foot lifts off as the sheathed turn lifts it, is carried round off
	the ground and plants on its ball behind, where the drawn stance has the rear foot (Footstep);
	then the left foot steps out again (Footstep): from 0.3 s the legs are TurnLeftDrawn's. Each
	foot moves only while it is off the ground. The turn plant brings the hips round between the
	first two Footsteps (TurnPlant); the Base set stands sheathed until this clip shows at full
	weight. The upper body is the sheathed turn's.
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
	id = "player/OneHandedSword/TurnLeftDraw",
	rig = "PlayerR15",
	duration = 0.5,
	loop = false,
	layer = "FullBody",
	priority = 5,
	blendIn = 0.08,
	blendOut = 0.15,
	keys = {
		{
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftShoulder = rot(3, 0, -5),
				LeftElbow = rot(10, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(2, 0, 5),
				RightElbow = rot(16, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-32, 0, 0),
				LeftHip = rot(12.3, -0.6, -3.2),
				LeftKnee = rot(-25.6, 0, 0),
				LeftAnkle = rot(13.2, 0, 3.2),
				RightHip = rot(7.1, 0.5, 3.2),
				RightKnee = rot(-23.4, 0, 0),
				RightAnkle = rot(16.3, 0, -3.2),
			},
		},
		{
			time = 0.04,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.09, 0, 0, 0, 0),
				LeftHip = rot(30.8, -1.8, -3.2),
				LeftKnee = rot(-60.5, 0, 0),
				LeftAnkle = rot(29.6, 0, 3.6),
				RightHip = rot(12.2, 0.8, 3.2),
				RightKnee = rot(-33.3, 0, 0),
				RightAnkle = rot(21, 0, -3.3),
			},
		},
		{
			time = 0.075,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.13, 0, 0, 0, 0),
				LeftHip = rot(35.9, 1.2, -0.9),
				LeftKnee = rot(-39.2, 0, 0),
				LeftAnkle = rot(3.3, 0, 0),
				RightHip = rot(16.2, 1, 3.2),
				RightKnee = rot(-40.9, 0, 0),
				RightAnkle = rot(24.7, 0, -3.3),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				Neck = rot(4, 10, 0),
				LeftHip = rot(33.8, 1.3, -0.9),
				LeftKnee = rot(-35.5, 0, 0),
				LeftAnkle = rot(1.7, 0, 0),
				RightHip = rot(17.9, 1.1, 3.2),
				RightKnee = rot(-44.2, 0, 0),
				RightAnkle = rot(26.3, 0, -3.4),
			},
		},
		{
			time = 0.13,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				LeftHip = rot(33.8, 1.3, -0.9),
				LeftKnee = rot(-35.5, 0, 0),
				LeftAnkle = rot(1.7, 0, 0),
				RightHip = rot(29.4, 2.5, 2.8),
				RightKnee = rot(-65.3, 0, 0),
				RightAnkle = rot(26, 0, -3.8),
			},
		},
		{
			time = 0.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				LeftHip = rot(33.8, 1.3, -0.9),
				LeftKnee = rot(-35.5, 0, 0),
				LeftAnkle = rot(1.7, 0, 0),
				RightHip = rot(0.7, 2, 6.3),
				RightKnee = rot(-47.4, 0, 0),
				RightAnkle = rot(38.6, 0, -6.4),
			},
		},
		{
			time = 0.335,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.144, 0, 0, 0, 0),
				LeftHip = rot(33.1, 1.3, -0.8),
				LeftKnee = rot(-34.3, 0, 0),
				LeftAnkle = rot(1.2, 0, 0),
				RightHip = rot(-7.2, 0.2, 6.5),
				RightKnee = rot(-30.9, 0, 0),
				RightAnkle = rot(38.1, 0, -6.4),
			},
		},
		{
			time = 0.36,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.138, 0, 0, 0, 0),
				Neck = rot(4, 10, 0),
				LeftHip = rot(32.4, 1.3, -0.8),
				LeftKnee = rot(-33.1, 0, 0),
				LeftAnkle = rot(0.7, 0, 0),
				RightHip = rot(-12.8, -0.3, 5.9),
				RightKnee = rot(-19.3, 0, 0),
				RightAnkle = rot(32.1, 0, 0.1),
			},
		},
		{
			time = 0.38,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.135, 0, 0, 0, 0),
				LeftHip = rot(43.7, 1.6, 0.6),
				LeftKnee = rot(-55.3, 0, 0),
				LeftAnkle = rot(20.1, 0, -10),
				RightHip = rot(-13.3, -0.3, 5.9),
				RightKnee = rot(-18.2, 0, 0),
				RightAnkle = rot(31.6, 0, 0.1),
			},
		},
		{
			time = 0.395,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.133, 0, 0, 0, 0),
				LeftHip = rot(48, 1.6, 0.6),
				LeftKnee = rot(-62.3, 0, 0),
				LeftAnkle = rot(22.9, 0, -10.1),
				RightHip = rot(-13.6, -0.4, 5.9),
				RightKnee = rot(-17.7, 0, 0),
				RightAnkle = rot(31.3, 0, 0.1),
			},
		},
		{
			time = 0.415,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.132, 0, 0, 0, 0),
				LeftHip = rot(38, -1.3, -4.2),
				LeftKnee = rot(-54.1, 0, 0),
				LeftAnkle = rot(16, 0, 4.1),
				RightHip = rot(-13.8, -0.4, 5.9),
				RightKnee = rot(-17.2, 0, 0),
				RightAnkle = rot(31, 0, 0.1),
			},
		},
		{
			time = 0.44,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.126, 0, 0, 0, 0),
				LeftHip = rot(28.9, -1.9, -6.5),
				LeftKnee = rot(-45.8, 0, 0),
				LeftAnkle = rot(16.7, 0, 6.6),
				RightHip = rot(-15, -0.5, 5.9),
				RightKnee = rot(-14.7, 0, 0),
				RightAnkle = rot(29.8, 0, 0.1),
			},
		},
		{
			time = 0.46,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				LeftHip = rot(24.7, -1.3, -6.5),
				LeftKnee = rot(-38.1, 0, 0),
				LeftAnkle = rot(13.2, 0, 6.4),
				RightHip = rot(-16.5, -0.6, 5.8),
				RightKnee = rot(-11.8, 0, 0),
				RightAnkle = rot(28.4, 0, 0.1),
			},
		},
		{
			time = 0.5,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftShoulder = rot(3, 0, -5),
				LeftElbow = rot(10, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(2, 0, 5),
				RightElbow = rot(16, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-32, 0, 0),
				LeftHip = rot(24.7, -1.3, -6.5),
				LeftKnee = rot(-38.1, 0, 0),
				LeftAnkle = rot(13.2, 0, 6.4),
				RightHip = rot(-16.5, -0.6, 5.8),
				RightKnee = rot(-11.8, 0, 0),
				RightAnkle = rot(28.4, 0, 0.1),
			},
		},
	},
	events = {
		{ time = 0.1, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.36, kind = "Footstep", data = { foot = "Right" } },
		{ time = 0.46, kind = "Footstep", data = { foot = "Left" } },
	},
}

return clip
