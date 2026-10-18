--!strict
--[[
	player/OneHandedSword/WalkBack: the sheathed set, the sword on the back.
	An easy backpedal, a 0.9 s cycle with the same plants as WalkBackDrawn. Each foot reaches
	back and lands on the toe, rolls flat and peels off the heel; the torso stays upright and
	the empty arms swing short. The planted foot stays put at 3 studs/s of ground speed.
	Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/WalkBack",
	rig = "PlayerR15",
	duration = 0.9,
	loop = true,
	sheathed = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left toe touches down behind, the left arm forward
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.13, 0, 0, 3, 0),
				Waist = rot(-2, -4, 0),
				Neck = rot(2, 1, 0),
				LeftHip = rot(-13.9, -2.9, 0.5),
				LeftKnee = rot(-22.7, 0, 0),
				LeftAnkle = rot(24.5, 0, -1.2),
				RightHip = rot(37.3, -3, 0.7),
				RightKnee = rot(-46.1, 0, 0),
				RightAnkle = rot(16.8, 0, 1.3),
				LeftShoulder = rot(14, 0, -6),
				LeftElbow = rot(9, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(-10, 0, 6),
				RightElbow = rot(19, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.1125,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.0283, -0.1, 0, 0, 2.1, 1.4),
				Waist = rot(-2, -2.8, -1.4),
				Neck = rot(2, 0.7, 0),
				LeftHip = rot(-6.6, -2.2, 0.5),
				LeftKnee = rot(-19.9, 0, 0),
				LeftAnkle = rot(26.4, 0, -2.2),
				RightHip = rot(39.5, -2.6, -0.1),
				RightKnee = rot(-33.1, 0, 0),
				RightAnkle = rot(9.6, 0, 0.4),
				LeftShoulder = rot(10.5, 0, -6.7),
				LeftElbow = rot(10.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(-6.5, 0, 5.3),
				RightElbow = rot(17.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			-- the body over the left foot, the right leg swinging back
			time = 0.225,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.04, -0.07, 0, 0, 0, 2),
				Waist = rot(-2, 0, -2),
				Neck = rot(2, 0, 0),
				LeftHip = rot(9.5, 0.1, 0.5),
				LeftKnee = rot(-31.4, 0, 0),
				LeftAnkle = rot(21.9, 0, -2.5),
				RightHip = rot(18, -0.8, -0.2),
				RightKnee = rot(-50, 0, 0),
				RightAnkle = rot(30, 0, 0.6),
				LeftShoulder = rot(2, 0, -7),
				LeftElbow = rot(14, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(2, 0, 5),
				RightElbow = rot(14, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.3375,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.0283, -0.1, 0, 0, -2.1, 1.4),
				Waist = rot(-2, 2.8, -1.4),
				Neck = rot(2, -0.7, 0),
				LeftHip = rot(23.8, 2.2, -0.1),
				LeftKnee = rot(-38.9, 0, 0),
				LeftAnkle = rot(15.2, 0, -2.2),
				RightHip = rot(-4, 1.1, -0.4),
				RightKnee = rot(-48, 0, 0),
				RightAnkle = rot(35, 0, 0.9),
				LeftShoulder = rot(-6.5, 0, -6.7),
				LeftElbow = rot(17.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(10.5, 0, 5.3),
				RightElbow = rot(10.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			-- right toe touches down behind, the right arm forward
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.13, 0, 0, -3, 0),
				Waist = rot(-2, 4, 0),
				Neck = rot(2, -1, 0),
				LeftHip = rot(37.3, 3, -0.7),
				LeftKnee = rot(-46.1, 0, 0),
				LeftAnkle = rot(16.8, 0, -1.3),
				RightHip = rot(-13.9, 2.9, -0.5),
				RightKnee = rot(-22.7, 0, 0),
				RightAnkle = rot(24.5, 0, 1.2),
				LeftShoulder = rot(-10, 0, -6),
				LeftElbow = rot(19, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(14, 0, 6),
				RightElbow = rot(9, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.5625,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.0283, -0.1, 0, 0, -2.1, -1.4),
				Waist = rot(-2, 2.8, 1.4),
				Neck = rot(2, -0.7, 0),
				LeftHip = rot(39.5, 2.6, 0.1),
				LeftKnee = rot(-33.1, 0, 0),
				LeftAnkle = rot(9.6, 0, -0.4),
				RightHip = rot(-6.6, 2.2, -0.5),
				RightKnee = rot(-19.9, 0, 0),
				RightAnkle = rot(26.4, 0, 2.2),
				LeftShoulder = rot(-6.5, 0, -5.3),
				LeftElbow = rot(17.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(10.5, 0, 6.7),
				RightElbow = rot(10.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			-- the body over the right foot, the left leg swinging back
			time = 0.675,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.04, -0.07, 0, 0, 0, -2),
				Waist = rot(-2, 0, 2),
				Neck = rot(2, 0, 0),
				LeftHip = rot(18, 0.8, 0.2),
				LeftKnee = rot(-50, 0, 0),
				LeftAnkle = rot(30, 0, -0.6),
				RightHip = rot(9.5, -0.1, -0.5),
				RightKnee = rot(-31.4, 0, 0),
				RightAnkle = rot(21.9, 0, 2.5),
				LeftShoulder = rot(2, 0, -5),
				LeftElbow = rot(14, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(2, 0, 7),
				RightElbow = rot(14, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.7875,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.0283, -0.1, 0, 0, 2.1, -1.4),
				Waist = rot(-2, -2.8, 1.4),
				Neck = rot(2, 0.7, 0),
				LeftHip = rot(-4, -1.1, 0.4),
				LeftKnee = rot(-48, 0, 0),
				LeftAnkle = rot(35, 0, -0.9),
				RightHip = rot(23.8, -2.2, 0.1),
				RightKnee = rot(-38.9, 0, 0),
				RightAnkle = rot(15.2, 0, 2.2),
				LeftShoulder = rot(10.5, 0, -5.3),
				LeftElbow = rot(10.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(-6.5, 0, 6.7),
				RightElbow = rot(17.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.03, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.48, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
