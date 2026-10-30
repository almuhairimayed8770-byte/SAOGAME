--!strict
--[[
	player/OneHandedSword/TurnRight: turn in place to the right over the sheathed stance, in two steps
	and a close (D-416). The right foot steps in under the body, the inner corner of its sole on
	the root's axis (Footstep), and the body spins on it while the left foot is carried round off
	the ground and plants where the stance has it (Footstep); then the right foot closes back
	(Footstep). Locomotion's turn plant holds the hips while the root turns and brings them round
	between the first two Footsteps (TurnPlant), so neither foot slides. The Root takes no yaw;
	the head leads. The sword rides low, the point forward.
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
	id = "player/OneHandedSword/TurnRight",
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
				LeftHip = rot(14, -0.7, -3.2),
				LeftKnee = rot(-28.7, 0, 0),
				LeftAnkle = rot(14.7, 0, 3.3),
				RightHip = rot(25.8, 1.7, 3.2),
				RightKnee = rot(-59.7, 0, 0),
				RightAnkle = rot(33.9, 0, -3.7),
			},
		},
		{
			time = 0.075,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.074, 0, 0, 0, 0),
				LeftHip = rot(15.5, -0.8, -3.2),
				LeftKnee = rot(-31.5, 0, 0),
				LeftAnkle = rot(16, 0, 3.3),
				RightHip = rot(-0.7, 0.1, 0),
				RightKnee = rot(-26.9, 0, 0),
				RightAnkle = rot(27.6, 0, 0),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, 0, 0),
				Neck = rot(4, -10, 0),
				LeftHip = rot(16.2, -0.8, -3.2),
				LeftKnee = rot(-32.8, 0, 0),
				LeftAnkle = rot(16.6, 0, 3.3),
				RightHip = rot(-6.1, 0.1, 0),
				RightKnee = rot(-16.2, 0, 0),
				RightAnkle = rot(22.3, 0, 0),
			},
		},
		{
			time = 0.13,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, 0, 0),
				LeftHip = rot(30.1, -2.3, -2.9),
				LeftKnee = rot(-57.9, 0, 0),
				LeftAnkle = rot(17.8, 0, 3.7),
				RightHip = rot(-6.1, 0.1, 0),
				RightKnee = rot(-16.2, 0, 0),
				RightAnkle = rot(22.3, 0, 0),
			},
		},
		{
			time = 0.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, 0, 0),
				LeftHip = rot(27.8, -2, -3),
				LeftKnee = rot(-53.8, 0, 0),
				LeftAnkle = rot(18, 0, 3.6),
				RightHip = rot(-6.1, 0.1, 0),
				RightKnee = rot(-16.2, 0, 0),
				RightAnkle = rot(22.3, 0, 0),
			},
		},
		{
			time = 0.335,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.074, 0, 0, 0, 0),
				LeftHip = rot(19.7, -1, -3.2),
				LeftKnee = rot(-39.5, 0, 0),
				LeftAnkle = rot(19.8, 0, 3.4),
				RightHip = rot(-7.5, 0.1, 0),
				RightKnee = rot(-13.5, 0, 0),
				RightAnkle = rot(21, 0, 0),
			},
		},
		{
			time = 0.36,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.068, 0, 0, 0, 0),
				Neck = rot(4, -10, 0),
				LeftHip = rot(14.7, -0.7, -3.2),
				LeftKnee = rot(-30.1, 0, 0),
				LeftAnkle = rot(15.4, 0, 3.3),
				RightHip = rot(-9.3, 0.1, 0),
				RightKnee = rot(-10.1, 0, 0),
				RightAnkle = rot(19.3, 0, 0),
			},
		},
		{
			time = 0.38,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.065, 0, 0, 0, 0),
				LeftHip = rot(14.4, -0.7, -3.2),
				LeftKnee = rot(-29.4, 0, 0),
				LeftAnkle = rot(15, 0, 3.3),
				RightHip = rot(9.9, -1, -1.3),
				RightKnee = rot(-45.1, 0, 0),
				RightAnkle = rot(26.6, 0, 9.9),
			},
		},
		{
			time = 0.395,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.063, 0, 0, 0, 0),
				LeftHip = rot(14.2, -0.7, -3.2),
				LeftKnee = rot(-29, 0, 0),
				LeftAnkle = rot(14.9, 0, 3.3),
				RightHip = rot(13.9, -1.1, -1.3),
				RightKnee = rot(-53.4, 0, 0),
				RightAnkle = rot(30.9, 0, 9.9),
			},
		},
		{
			time = 0.415,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.062, 0, 0, 0, 0),
				LeftHip = rot(14, -0.7, -3.2),
				LeftKnee = rot(-28.7, 0, 0),
				LeftAnkle = rot(14.7, 0, 3.3),
				RightHip = rot(13.7, 0.6, 2),
				RightKnee = rot(-43.9, 0, 0),
				RightAnkle = rot(30.2, 0, -2.1),
			},
		},
		{
			time = 0.44,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.056, 0, 0, 0, 0),
				LeftHip = rot(13.2, -0.6, -3.2),
				LeftKnee = rot(-27.2, 0, 0),
				LeftAnkle = rot(14, 0, 3.3),
				RightHip = rot(12.9, 0.8, 3.2),
				RightKnee = rot(-34.6, 0, 0),
				RightAnkle = rot(21.6, 0, -3.3),
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
		{ time = 0.1, kind = "Footstep", data = { foot = "Right" } },
		{ time = 0.36, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.46, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
