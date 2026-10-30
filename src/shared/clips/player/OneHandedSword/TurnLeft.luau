--!strict
--[[
	player/OneHandedSword/TurnLeft: turn in place to the left over the sheathed stance; the mirror of
	TurnRight (D-416). The left foot steps in under the body, the inner corner of its sole on the
	root's axis (Footstep), the body spins on it with the right foot off the ground until it plants
	(Footstep), and the left foot closes back (Footstep). The turn plant brings the hips round
	between the first two Footsteps (TurnPlant). The Root takes no yaw; the head leads. The sword
	rides low, the point forward.
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
	id = "player/OneHandedSword/TurnLeft",
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
				Root = posRot(0, -0.062, 0, 0, 0, 0),
				LeftHip = rot(31, -1.8, -3.2),
				LeftKnee = rot(-60.8, 0, 0),
				LeftAnkle = rot(29.7, 0, 3.7),
				RightHip = rot(8.9, 0.6, 3.2),
				RightKnee = rot(-26.8, 0, 0),
				RightAnkle = rot(17.9, 0, -3.3),
			},
		},
		{
			time = 0.075,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.074, 0, 0, 0, 0),
				LeftHip = rot(-0.8, 0.1, 0),
				LeftKnee = rot(-26.8, 0, 0),
				LeftAnkle = rot(27.6, 0, 0),
				RightHip = rot(10.4, 0.7, 3.2),
				RightKnee = rot(-29.8, 0, 0),
				RightAnkle = rot(19.3, 0, -3.3),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, 0, 0),
				Neck = rot(4, 10, 0),
				LeftHip = rot(-6.2, 0.1, 0),
				LeftKnee = rot(-16.1, 0, 0),
				LeftAnkle = rot(22.3, 0, 0),
				RightHip = rot(11.1, 0.7, 3.2),
				RightKnee = rot(-31.1, 0, 0),
				RightAnkle = rot(20, 0, -3.3),
			},
		},
		{
			time = 0.13,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, 0, 0),
				LeftHip = rot(-6.2, 0.1, 0),
				LeftKnee = rot(-16.1, 0, 0),
				LeftAnkle = rot(22.3, 0, 0),
				RightHip = rot(25.1, 2.2, 2.9),
				RightKnee = rot(-57, 0, 0),
				RightAnkle = rot(21.9, 0, -3.6),
			},
		},
		{
			time = 0.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, 0, 0),
				LeftHip = rot(-6.2, 0.1, 0),
				LeftKnee = rot(-16.1, 0, 0),
				LeftAnkle = rot(22.3, 0, 0),
				RightHip = rot(22.8, 1.9, 3),
				RightKnee = rot(-52.9, 0, 0),
				RightAnkle = rot(22, 0, -3.5),
			},
		},
		{
			time = 0.335,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.074, 0, 0, 0, 0),
				LeftHip = rot(-7.7, 0.1, 0),
				LeftKnee = rot(-13.3, 0, 0),
				LeftAnkle = rot(20.9, 0, 0),
				RightHip = rot(14.7, 1, 3.2),
				RightKnee = rot(-38.1, 0, 0),
				RightAnkle = rot(23.3, 0, -3.4),
			},
		},
		{
			time = 0.36,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.068, 0, 0, 0, 0),
				Neck = rot(4, 10, 0),
				LeftHip = rot(-9.5, 0.1, 0),
				LeftKnee = rot(-9.8, 0, 0),
				LeftAnkle = rot(19.2, 0, 0),
				RightHip = rot(9.7, 0.7, 3.2),
				RightKnee = rot(-28.3, 0, 0),
				RightAnkle = rot(18.6, 0, -3.3),
			},
		},
		{
			time = 0.38,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.065, 0, 0, 0, 0),
				LeftHip = rot(9.8, 1.2, 1.3),
				LeftKnee = rot(-45, 0, 0),
				LeftAnkle = rot(26.6, 0, -9.9),
				RightHip = rot(9.3, 0.6, 3.2),
				RightKnee = rot(-27.6, 0, 0),
				RightAnkle = rot(18.3, 0, -3.3),
			},
		},
		{
			time = 0.395,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.063, 0, 0, 0, 0),
				LeftHip = rot(13.8, 1.3, 1.2),
				LeftKnee = rot(-53.3, 0, 0),
				LeftAnkle = rot(31, 0, -9.9),
				RightHip = rot(9.1, 0.6, 3.2),
				RightKnee = rot(-27.2, 0, 0),
				RightAnkle = rot(18.1, 0, -3.3),
			},
		},
		{
			time = 0.415,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.062, 0, 0, 0, 0),
				LeftHip = rot(17.2, -0.5, -2),
				LeftKnee = rot(-45.7, 0, 0),
				LeftAnkle = rot(28.5, 0, 2.1),
				RightHip = rot(8.9, 0.6, 3.2),
				RightKnee = rot(-26.8, 0, 0),
				RightAnkle = rot(17.9, 0, -3.3),
			},
		},
		{
			time = 0.44,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.056, 0, 0, 0, 0),
				LeftHip = rot(17.9, -0.9, -3.2),
				LeftKnee = rot(-36.1, 0, 0),
				LeftAnkle = rot(18.2, 0, 3.3),
				RightHip = rot(8, 0.6, 3.2),
				RightKnee = rot(-25.2, 0, 0),
				RightAnkle = rot(17.1, 0, -3.2),
			},
		},
		{
			time = 0.46,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				LeftHip = rot(12.3, -0.6, -3.2),
				LeftKnee = rot(-25.6, 0, 0),
				LeftAnkle = rot(13.2, 0, 3.2),
				RightHip = rot(7.1, 0.5, 3.2),
				RightKnee = rot(-23.4, 0, 0),
				RightAnkle = rot(16.3, 0, -3.2),
			},
		},
		{
			time = 0.5,
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
	},
	events = {
		{ time = 0.1, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.36, kind = "Footstep", data = { foot = "Right" } },
		{ time = 0.46, kind = "Footstep", data = { foot = "Left" } },
	},
}

return clip
