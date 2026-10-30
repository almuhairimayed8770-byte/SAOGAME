--!strict
--[[
	player/OneHandedSword/TurnLeftDrawn: turn in place to the left over the drawn stance, in two steps
	and a close (D-416). The front foot steps back in under the body, the inner corner of its heel
	on the root's axis (Footstep), the body spins on it with the rear foot off the ground until it
	plants where the stance has it (Footstep), and the front foot steps out again (Footstep). The
	turn plant brings the hips round between the first two Footsteps (TurnPlant). The Root takes no
	yaw; the head leads; the guard holds.
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
	id = "player/OneHandedSword/TurnLeftDrawn",
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
				LeftHip = rot(40.7, -3.6, -6.5),
				LeftKnee = rot(-67, 0, 0),
				LeftAnkle = rot(26, 0, 7.3),
				RightHip = rot(-13.8, -0.4, 5.9),
				RightKnee = rot(-17.2, 0, 0),
				RightAnkle = rot(31, 0, 0.1),
			},
		},
		{
			time = 0.075,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.144, 0, 0, 0, 0),
				LeftHip = rot(37.3, 1.2, -0.9),
				LeftKnee = rot(-41.6, 0, 0),
				LeftAnkle = rot(4.3, 0, 0),
				RightHip = rot(-11.9, -0.2, 6),
				RightKnee = rot(-21.2, 0, 0),
				RightAnkle = rot(33, 0, 0),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				Neck = rot(2, 22, 0),
				LeftHip = rot(33.8, 1.3, -0.9),
				LeftKnee = rot(-35.5, 0, 0),
				LeftAnkle = rot(1.7, 0, 0),
				RightHip = rot(-11, -0.1, 6),
				RightKnee = rot(-22.9, 0, 0),
				RightAnkle = rot(33.9, 0, 0),
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
				RightHip = rot(2.7, 2.5, 6.3),
				RightKnee = rot(-51.7, 0, 0),
				RightAnkle = rot(39, 0, -6.5),
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
				Neck = rot(2, 22, 0),
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
		{ time = 0.1, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.36, kind = "Footstep", data = { foot = "Right" } },
		{ time = 0.46, kind = "Footstep", data = { foot = "Left" } },
	},
}

return clip
