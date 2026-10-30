--!strict
--[[
	player/OneHandedSword/TurnRightDrawn: turn in place to the right over the drawn stance (left foot
	forward, the rear foot on its ball), in two steps and a close (D-416). The rear foot steps in
	under the body, the inner corner of its ball on the root's axis (Footstep), the body spins on it
	with the front foot off the ground until it plants where the stance has it (Footstep), and the
	rear foot steps back (Footstep). The turn plant brings the hips round between the first two
	Footsteps (TurnPlant). The Root takes no yaw; the head leads; the guard holds.
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
	id = "player/OneHandedSword/TurnRightDrawn",
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
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-8, -12, 0),
				Neck = rot(2, 12, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				LeftHip = rot(24.7, -1.3, -6.5),
				LeftKnee = rot(-38.1, 0, 0),
				LeftAnkle = rot(13.2, 0, 6.4),
				RightHip = rot(-16.5, -0.6, 5.8),
				RightKnee = rot(-11.8, 0, 0),
				RightAnkle = rot(28.4, 0, 0.1),
			},
		},
		{
			time = 0.04,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.132, 0, 0, 0, 0),
				LeftHip = rot(25.9, -1.5, -6.5),
				LeftKnee = rot(-40.3, 0, 0),
				LeftAnkle = rot(14.2, 0, 6.4),
				RightHip = rot(2.8, 1.4, 7),
				RightKnee = rot(-53.5, 0, 0),
				RightAnkle = rot(50.7, 0, -7),
			},
		},
		{
			time = 0.075,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.144, 0, 0, 0, 0),
				LeftHip = rot(27, -1.6, -6.5),
				LeftKnee = rot(-42.3, 0, 0),
				LeftAnkle = rot(15.1, 0, 6.5),
				RightHip = rot(10.1, 0.9, -0.8),
				RightKnee = rot(-48.6, 0, 0),
				RightAnkle = rot(38.5, 0, 0.7),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				Neck = rot(2, 2, 0),
				LeftHip = rot(27.5, -1.7, -6.5),
				LeftKnee = rot(-43.3, 0, 0),
				LeftAnkle = rot(15.5, 0, 6.5),
				RightHip = rot(7.6, 0.9, -1.2),
				RightKnee = rot(-43.3, 0, 0),
				RightAnkle = rot(35.7, 0, 6.9),
			},
		},
		{
			time = 0.13,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				LeftHip = rot(39.7, -4.5, -5.8),
				LeftKnee = rot(-64.2, 0, 0),
				LeftAnkle = rot(14.2, 0, 7.5),
				RightHip = rot(7.6, 0.9, -1.2),
				RightKnee = rot(-43.3, 0, 0),
				RightAnkle = rot(35.7, 0, 6.9),
			},
		},
		{
			time = 0.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				LeftHip = rot(37.5, -4, -6),
				LeftKnee = rot(-60.6, 0, 0),
				LeftAnkle = rot(14.8, 0, 7.2),
				RightHip = rot(7.6, 0.9, -1.2),
				RightKnee = rot(-43.3, 0, 0),
				RightAnkle = rot(35.7, 0, 6.9),
			},
		},
		{
			time = 0.335,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.144, 0, 0, 0, 0),
				LeftHip = rot(30.4, -2.1, -6.5),
				LeftKnee = rot(-48.6, 0, 0),
				LeftAnkle = rot(17.9, 0, 6.7),
				RightHip = rot(7.2, 0.9, -1.1),
				RightKnee = rot(-42.4, 0, 0),
				RightAnkle = rot(35.2, 0, 6.9),
			},
		},
		{
			time = 0.36,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.138, 0, 0, 0, 0),
				Neck = rot(2, 2, 0),
				LeftHip = rot(26.4, -1.5, -6.5),
				LeftKnee = rot(-41.3, 0, 0),
				LeftAnkle = rot(14.6, 0, 6.5),
				RightHip = rot(6.7, 0.9, -1.1),
				RightKnee = rot(-41.4, 0, 0),
				RightAnkle = rot(34.7, 0, 6.9),
			},
		},
		{
			time = 0.38,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.135, 0, 0, 0, 0),
				LeftHip = rot(26.2, -1.5, -6.5),
				LeftKnee = rot(-40.8, 0, 0),
				LeftAnkle = rot(14.4, 0, 6.5),
				RightHip = rot(17.6, -0.9, -2.7),
				RightKnee = rot(-60.2, 0, 0),
				RightAnkle = rot(33.8, 0, 17),
			},
		},
		{
			time = 0.395,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.133, 0, 0, 0, 0),
				LeftHip = rot(26, -1.5, -6.5),
				LeftKnee = rot(-40.5, 0, 0),
				LeftAnkle = rot(14.3, 0, 6.4),
				RightHip = rot(20.6, -1.1, -2.7),
				RightKnee = rot(-66.7, 0, 0),
				RightAnkle = rot(37.3, 0, 17.1),
			},
		},
		{
			time = 0.415,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.132, 0, 0, 0, 0),
				LeftHip = rot(25.9, -1.5, -6.5),
				LeftKnee = rot(-40.3, 0, 0),
				LeftAnkle = rot(14.2, 0, 6.4),
				RightHip = rot(4.1, 1.3, 3.6),
				RightKnee = rot(-47.4, 0, 0),
				RightAnkle = rot(43.4, 0, -3.7),
			},
		},
		{
			time = 0.44,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.126, 0, 0, 0, 0),
				LeftHip = rot(25.3, -1.4, -6.5),
				LeftKnee = rot(-39.2, 0, 0),
				LeftAnkle = rot(13.7, 0, 6.4),
				RightHip = rot(-9.1, 0, 6.4),
				RightKnee = rot(-26.9, 0, 0),
				RightAnkle = rot(36, 0, -6.3),
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
				Waist = rot(-8, -12, 0),
				Neck = rot(2, 12, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
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
		{ time = 0.1, kind = "Footstep", data = { foot = "Right" } },
		{ time = 0.36, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.46, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
