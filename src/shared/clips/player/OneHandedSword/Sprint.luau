--!strict
--[[
	player/OneHandedSword/Sprint: the sheathed set, the sword on the back.
	24 studs/s, a 0.5 s cycle with the same plants as SprintDrawn. A deeper lean than Run, a
	longer stride with a high heel kick, and a hard arm pump; the head drives forward in line with
	the body (tipped back it would meet the hilt). As in Run, the elbows go out at the back of the
	swing past the scabbard and the waist twist stays small enough for the scabbard to clear the
	hips. Each foot stays planted where it lands while the body passes over it (the keys inside a
	stance are 0.02 s apart so the ground speed matches).
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
	id = "player/OneHandedSword/Sprint",
	rig = "PlayerR15",
	duration = 0.5,
	loop = true,
	sheathed = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left foot plants on the ball, the right arm thrown forward
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.1, 0, -10, -7, 0),
				Waist = rot(-18, 8.4, 2),
				Neck = rot(2, -1.5, -1),
				LeftHip = rot(49.2, 8.4, -2),
				LeftKnee = rot(-36.8, 0, 0),
				LeftAnkle = rot(-14, 0, -5),
				RightHip = rot(68, -7.2, -1.8),
				RightKnee = rot(-125, 0, 0),
				RightAnkle = rot(0, 0, 4.8),
				LeftShoulder = rot(-54, 0, -22),
				LeftElbow = rot(65, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(70, 0, 10),
				RightElbow = rot(105, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			time = 0.02,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.16, 0, -10, -6.8, 0),
				Waist = rot(-18.2, 8.1, 1.9),
				Neck = rot(2.1, -1.4, -1),
				LeftHip = rot(37.4, 7.4, 0),
				LeftKnee = rot(-48.1, 0, 0),
				LeftAnkle = rot(20.9, 0, -4.5),
				RightHip = rot(80, -7.3, -1.5),
				RightKnee = rot(-115, 0, 0),
				RightAnkle = rot(-6, 0, 4.8),
				LeftShoulder = rot(-52.1, 0, -22),
				LeftElbow = rot(65.6, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(68.1, 0, 9.3),
				RightElbow = rot(104.4, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			-- left foot flat under the hips, the body at its lowest
			time = 0.04,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.2, 0, -10, -6.1, 0),
				Waist = rot(-18.9, 7.3, 1.8),
				Neck = rot(2.5, -1.2, -0.9),
				LeftHip = rot(20.3, 6.5, 2.5),
				LeftKnee = rot(-46, 0, 0),
				LeftAnkle = rot(35.8, 0, -4.7),
				RightHip = rot(88, -7.4, -1.2),
				RightKnee = rot(-100, 0, 0),
				RightAnkle = rot(-12, 0, 4.8),
				LeftShoulder = rot(-46.3, 0, -20),
				LeftElbow = rot(67.5, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(62.3, 0, 8.6),
				RightElbow = rot(102.5, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			time = 0.06,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.13, 0, -10, -5.1, 0),
				Waist = rot(-19.9, 6.1, 1.5),
				Neck = rot(3, -0.8, -0.7),
				LeftHip = rot(10.7, 7.1, 3.1),
				LeftKnee = rot(-47.9, 0, 0),
				LeftAnkle = rot(19.7, 0, -4.6),
				RightHip = rot(90, -7.4, -0.9),
				RightKnee = rot(-80, 0, 0),
				RightAnkle = rot(-14, 0, 4.8),
				LeftShoulder = rot(-37.2, 0, -17),
				LeftElbow = rot(70.4, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(53.2, 0, 7.9),
				RightElbow = rot(99.6, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			-- left toe drives off, the leg long behind
			time = 0.08,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.02, 0, -10, -3.8, 0),
				Waist = rot(-20.9, 4.5, 1.1),
				Neck = rot(3.5, -0.4, -0.5),
				LeftHip = rot(-9.3, 6.3, 4.5),
				LeftKnee = rot(-22, 0, 0),
				LeftAnkle = rot(-13.8, 0, -4.6),
				RightHip = rot(86, -7.5, -0.6),
				RightKnee = rot(-58, 0, 0),
				RightAnkle = rot(-14, 0, 4.8),
				LeftShoulder = rot(-25.2, 0, -14.5),
				LeftElbow = rot(74.3, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(41.2, 0, 7.5),
				RightElbow = rot(95.7, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			-- flight: the left heel high behind, the right knee up
			time = 0.165,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.08, 0, -10, 3.4, 0),
				Waist = rot(-21.1, -4.1, -1),
				Neck = rot(3.5, 2.2, 0.5),
				LeftHip = rot(22, 6.7, 3.1),
				LeftKnee = rot(-125, 0, 0),
				LeftAnkle = rot(15, 0, -4.7),
				RightHip = rot(62, -8, 0.7),
				RightKnee = rot(-22, 0, 0),
				RightAnkle = rot(-12, 0, 4.9),
				LeftShoulder = rot(37.9, 0, -12.6),
				LeftElbow = rot(94.6, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(-21.9, 0, 10),
				RightElbow = rot(75.4, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			-- right foot plants on the ball, the left arm thrown forward
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.1, 0, -10, 7, 0),
				Waist = rot(-18, -8.4, -2),
				Neck = rot(2, 3.5, 1),
				LeftHip = rot(68, 7.2, 1.8),
				LeftKnee = rot(-125, 0, 0),
				LeftAnkle = rot(0, 0, -4.8),
				RightHip = rot(49.2, -8.4, 2),
				RightKnee = rot(-36.8, 0, 0),
				RightAnkle = rot(-14, 0, 5),
				LeftShoulder = rot(70, 0, -10),
				LeftElbow = rot(105, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(-54, 0, 16),
				RightElbow = rot(65, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			time = 0.27,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.16, 0, -10, 6.8, 0),
				Waist = rot(-18.2, -8.1, -1.9),
				Neck = rot(2.1, 3.4, 1),
				LeftHip = rot(80, 7.3, 1.5),
				LeftKnee = rot(-115, 0, 0),
				LeftAnkle = rot(-6, 0, -4.8),
				RightHip = rot(37.4, -7.4, 0),
				RightKnee = rot(-48.1, 0, 0),
				RightAnkle = rot(20.9, 0, 4.5),
				LeftShoulder = rot(68.1, 0, -9.3),
				LeftElbow = rot(104.4, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(-52.1, 0, 16),
				RightElbow = rot(65.6, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			-- right foot flat under the hips, the body at its lowest
			time = 0.29,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.2, 0, -10, 6.1, 0),
				Waist = rot(-18.9, -7.3, -1.8),
				Neck = rot(2.5, 3.2, 0.9),
				LeftHip = rot(88, 7.4, 1.2),
				LeftKnee = rot(-100, 0, 0),
				LeftAnkle = rot(-12, 0, -4.8),
				RightHip = rot(20.3, -6.5, -2.5),
				RightKnee = rot(-46, 0, 0),
				RightAnkle = rot(35.8, 0, 4.7),
				LeftShoulder = rot(62.3, 0, -8.6),
				LeftElbow = rot(102.5, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(-46.3, 0, 15),
				RightElbow = rot(67.5, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			time = 0.31,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.13, 0, -10, 5.1, 0),
				Waist = rot(-19.9, -6.1, -1.5),
				Neck = rot(3, 2.8, 0.7),
				LeftHip = rot(90, 7.4, 0.9),
				LeftKnee = rot(-80, 0, 0),
				LeftAnkle = rot(-14, 0, -4.8),
				RightHip = rot(10.7, -7.1, -3.1),
				RightKnee = rot(-47.9, 0, 0),
				RightAnkle = rot(19.7, 0, 4.6),
				LeftShoulder = rot(53.2, 0, -7.9),
				LeftElbow = rot(99.6, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(-37.2, 0, 13),
				RightElbow = rot(70.4, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			-- right toe drives off, the leg long behind
			time = 0.33,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.02, 0, -10, 3.8, 0),
				Waist = rot(-20.9, -4.5, -1.1),
				Neck = rot(3.5, 2.4, 0.5),
				LeftHip = rot(86, 7.5, 0.6),
				LeftKnee = rot(-58, 0, 0),
				LeftAnkle = rot(-14, 0, -4.8),
				RightHip = rot(-9.3, -6.3, -4.4),
				RightKnee = rot(-22, 0, 0),
				RightAnkle = rot(-13.8, 0, 4.6),
				LeftShoulder = rot(41.2, 0, -7.5),
				LeftElbow = rot(95.7, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(-25.2, 0, 12.5),
				RightElbow = rot(74.3, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
		{
			-- flight: the right heel high behind, the left knee up
			time = 0.415,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.08, 0, -10, -3.4, 0),
				Waist = rot(-21.1, 4.1, 1),
				Neck = rot(3.5, -0.2, -0.5),
				LeftHip = rot(62, 8, -0.7),
				LeftKnee = rot(-22, 0, 0),
				LeftAnkle = rot(-12, 0, -4.9),
				RightHip = rot(22, -6.7, -3.1),
				RightKnee = rot(-125, 0, 0),
				RightAnkle = rot(15, 0, 4.7),
				LeftShoulder = rot(-21.9, 0, -12),
				LeftElbow = rot(75.4, 0, 0),
				LeftWrist = rot(-8, 0, 0),
				RightShoulder = rot(37.9, 0, 12.6),
				RightElbow = rot(94.6, 0, 0),
				RightWrist = rot(-8, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.02, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.27, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
