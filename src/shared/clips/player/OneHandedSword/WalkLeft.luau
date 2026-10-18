--!strict
--[[
	player/OneHandedSword/WalkLeft: the sheathed set, the sword on the back.
	An easy side-step to the left, a 0.9 s cycle with the same plants as WalkLeftDrawn. The left
	foot reaches out, the body shifts over it and the right foot closes in; the torso stays
	square and the empty arms hang loose. The planted foot stays put at 1.5 studs/s of ground
	speed (the feet are wide, so a side-step covers little ground).
	Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left (a hanging left leg
	with Z- swings out to the left).
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/WalkLeft",
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
			-- left foot plants out to the left
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.11, 0, -1, 0, 0),
				Waist = rot(0, 0, 0),
				Neck = rot(1, 0, 0),
				LeftHip = rot(2.1, -0.5, -24),
				LeftKnee = rot(-2.3, 0, 0),
				LeftAnkle = rot(1.1, 0, 29.6),
				RightHip = rot(16.7, 8.2, 18.2),
				RightKnee = rot(-30.4, 0, 0),
				RightAnkle = rot(5.4, 0, -19.8),
				LeftShoulder = rot(-3, 0, -6),
				LeftElbow = rot(9, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(7, 0, 6),
				RightElbow = rot(19, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.1125,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.0566, -0.08, 0, -1, 0, 2.1),
				Waist = rot(0, 0, -2.1),
				Neck = rot(1, 0, 0),
				LeftHip = rot(10.3, -3, -17.9),
				LeftKnee = rot(-18.4, 0, 0),
				LeftAnkle = rot(8.6, 0, 15.9),
				RightHip = rot(1.1, 7.7, 24.2),
				RightKnee = rot(-0.9, 0, 0),
				RightAnkle = rot(-16.4, 0, -27),
				LeftShoulder = rot(-1.5, 0, -6.7),
				LeftElbow = rot(10.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(5.5, 0, 5.3),
				RightElbow = rot(17.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			-- the body shifts over the left foot, the right foot lifts
			time = 0.225,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.08, -0.05, 0, -1, 0, 3),
				Waist = rot(0, 0, -3),
				Neck = rot(1, 0, 0),
				LeftHip = rot(14.1, -3, -12.7),
				LeftKnee = rot(-25.2, 0, 0),
				LeftAnkle = rot(11.8, 0, 10),
				RightHip = rot(6, 4.9, 15.6),
				RightKnee = rot(-42, 0, 0),
				RightAnkle = rot(30, 0, -17.4),
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
				Root = posRot(-0.0566, -0.08, 0, -1, 0, 2.1),
				Waist = rot(0, 0, -2.1),
				Neck = rot(1, 0, 0),
				LeftHip = rot(19.5, -2.5, -7.4),
				LeftKnee = rot(-35.2, 0, 0),
				LeftAnkle = rot(16.5, 0, 5.6),
				RightHip = rot(6, 2.1, 6.9),
				RightKnee = rot(-34, 0, 0),
				RightAnkle = rot(26, 0, -7.7),
				LeftShoulder = rot(5.5, 0, -6.7),
				LeftElbow = rot(17.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(-1.5, 0, 5.3),
				RightElbow = rot(10.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			-- right foot closes in and plants
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.11, 0, -1, 0, 0),
				Waist = rot(0, 0, 0),
				Neck = rot(1, 0, 0),
				LeftHip = rot(28.6, -1.3, -1.8),
				LeftKnee = rot(-49.3, 0, 0),
				LeftAnkle = rot(13.7, 0, 2.2),
				RightHip = rot(21.8, -0.7, -1.8),
				RightKnee = rot(-39.1, 0, 0),
				RightAnkle = rot(18.3, 0, 1.9),
				LeftShoulder = rot(7, 0, -6),
				LeftElbow = rot(19, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(-3, 0, 6),
				RightElbow = rot(9, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.5625,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.0566, -0.08, 0, -1, 0, -2.1),
				Waist = rot(0, 0, 2.1),
				Neck = rot(1, 0, 0),
				LeftHip = rot(31, 2.3, 3),
				LeftKnee = rot(-50.6, 0, 0),
				LeftAnkle = rot(4.6, 0, -1.6),
				RightHip = rot(20.5, 1.3, 3.6),
				RightKnee = rot(-36.8, 0, 0),
				RightAnkle = rot(17.3, 0, -1.7),
				LeftShoulder = rot(5.5, 0, -5.3),
				LeftElbow = rot(17.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(-1.5, 0, 6.7),
				RightElbow = rot(10.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			-- the body shifts over the right foot, the left foot reaches out again
			time = 0.675,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.08, -0.05, 0, -1, 0, -3),
				Waist = rot(0, 0, 3),
				Neck = rot(1, 0, 0),
				LeftHip = rot(6, 1.3, -6),
				LeftKnee = rot(-42, 0, 0),
				LeftAnkle = rot(30, 0, 8.8),
				RightHip = rot(16.7, 2.5, 8.9),
				RightKnee = rot(-29.8, 0, 0),
				RightAnkle = rot(14, 0, -6.2),
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
				Root = posRot(0.0566, -0.08, 0, -1, 0, -2.1),
				Waist = rot(0, 0, 2.1),
				Neck = rot(1, 0, 0),
				LeftHip = rot(6, 0.4, -15),
				LeftKnee = rot(-34, 0, 0),
				LeftAnkle = rot(26, 0, 19.2),
				RightHip = rot(15.3, 3.6, 13.9),
				RightKnee = rot(-27.8, 0, 0),
				RightAnkle = rot(13, 0, -12.2),
				LeftShoulder = rot(-1.5, 0, -5.3),
				LeftElbow = rot(10.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(5.5, 0, 6.7),
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
