--!strict
--[[
	player/OneHandedSword/Run: the sheathed set, the sword on the back.
	16 studs/s, a 0.6 s cycle with the same plants as RunDrawn. The anime run: the body leans
	forward with the head in line with it, both arms pump hard with the elbows bent and a little
	out at the back of the swing, and the feet strike on the ball and push off the toe with a long
	flight between. The head stays in line because the hilt sits just behind it: tipped back to
	look up, it would meet the hilt. The elbows go out at the back so the left hand passes outside
	the scabbard, and the waist twists only 8 degrees so the scabbard clears the hips. Each foot
	stays planted where it lands while the body passes over it (the keys inside a stance are
	0.025 s apart so the ground speed matches).
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
	id = "player/OneHandedSword/Run",
	rig = "PlayerR15",
	duration = 0.6,
	loop = true,
	sheathed = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left foot plants on the ball, the right arm forward
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.08, 0, -6, -6, 0),
				Waist = rot(-14, 8, 2),
				Neck = rot(2, -1, -1),
				LeftHip = rot(41.1, 6.8, -1.5),
				LeftKnee = rot(-37.7, 0, 0),
				LeftAnkle = rot(-7.1, 0, -3.4),
				RightHip = rot(55, -5.6, -1.2),
				RightKnee = rot(-120, 0, 0),
				RightAnkle = rot(0, 0, 3.3),
				LeftShoulder = rot(-45, 0, -13),
				LeftElbow = rot(70, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(55, 0, 8),
				RightElbow = rot(100, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			time = 0.025,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.13, 0, -6, -5.8, 0),
				Waist = rot(-14.3, 7.8, 1.9),
				Neck = rot(2.2, -0.9, -1),
				LeftHip = rot(29.2, 6.2, 0.1),
				LeftKnee = rot(-43.2, 0, 0),
				LeftAnkle = rot(20.1, 0, -3.2),
				RightHip = rot(66, -5.7, -0.9),
				RightKnee = rot(-112, 0, 0),
				RightAnkle = rot(-5, 0, 3.3),
				LeftShoulder = rot(-43.3, 0, -13),
				LeftElbow = rot(70.5, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(53.3, 0, 7.5),
				RightElbow = rot(99.5, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			-- left foot flat under the hips, the body at its lowest
			time = 0.05,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.16, 0, -6, -5.2, 0),
				Waist = rot(-15, 7, 1.7),
				Neck = rot(2.5, -0.8, -0.9),
				LeftHip = rot(14.9, 5.5, 1.9),
				LeftKnee = rot(-40.8, 0, 0),
				LeftAnkle = rot(31.9, 0, -3.2),
				RightHip = rot(74, -5.8, -0.7),
				RightKnee = rot(-100, 0, 0),
				RightAnkle = rot(-10, 0, 3.3),
				LeftShoulder = rot(-38.3, 0, -12.5),
				LeftElbow = rot(72, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(48.3, 0, 7),
				RightElbow = rot(98, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			time = 0.075,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, -6, -4.2, 0),
				Waist = rot(-16, 5.7, 1.4),
				Neck = rot(3, -0.4, -0.7),
				LeftHip = rot(9.2, 5.5, 2.3),
				LeftKnee = rot(-47.2, 0, 0),
				LeftAnkle = rot(21.5, 0, -3.2),
				RightHip = rot(78, -5.9, -0.5),
				RightKnee = rot(-82, 0, 0),
				RightAnkle = rot(-12, 0, 3.3),
				LeftShoulder = rot(-30.4, 0, -11.5),
				LeftElbow = rot(74.4, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(40.4, 0, 6.6),
				RightElbow = rot(95.6, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			-- left toe pushes off
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.04, 0, -6, -3, 0),
				Waist = rot(-17, 4, 1),
				Neck = rot(3.5, 0, -0.5),
				LeftHip = rot(-3.5, 4.8, 2.9),
				LeftKnee = rot(-34.9, 0, 0),
				LeftAnkle = rot(-0.6, 0, -3.3),
				RightHip = rot(76, -6, -0.3),
				RightKnee = rot(-62, 0, 0),
				RightAnkle = rot(-12, 0, 3.3),
				LeftShoulder = rot(-20, 0, -9.7),
				LeftElbow = rot(77.5, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(30, 0, 6.3),
				RightElbow = rot(92.5, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			-- flight: the left heel kicks up behind, the right knee drives through
			time = 0.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.06, 0, -6, 3, 0),
				Waist = rot(-17, -4, -1),
				Neck = rot(3.5, 2, 0.5),
				LeftHip = rot(15, 5.2, 2),
				LeftKnee = rot(-115, 0, 0),
				LeftAnkle = rot(15, 0, -3.3),
				RightHip = rot(55, -6.4, 0.6),
				RightKnee = rot(-22, 0, 0),
				RightAnkle = rot(-10, 0, 3.3),
				LeftShoulder = rot(30, 0, -9.7),
				LeftElbow = rot(92.5, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(-20, 0, 6.3),
				RightElbow = rot(77.5, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			-- right foot plants on the ball, the left arm forward
			time = 0.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.08, 0, -6, 6, 0),
				Waist = rot(-14, -8, -2),
				Neck = rot(2, 3, 1),
				LeftHip = rot(55, 5.6, 1.2),
				LeftKnee = rot(-120, 0, 0),
				LeftAnkle = rot(0, 0, -3.3),
				RightHip = rot(41.1, -6.8, 1.5),
				RightKnee = rot(-37.7, 0, 0),
				RightAnkle = rot(-7.1, 0, 3.4),
				LeftShoulder = rot(55, 0, -8),
				LeftElbow = rot(100, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(-45, 0, 13),
				RightElbow = rot(70, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			time = 0.325,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.13, 0, -6, 5.8, 0),
				Waist = rot(-14.3, -7.8, -1.9),
				Neck = rot(2.2, 3, 1),
				LeftHip = rot(66, 5.7, 0.9),
				LeftKnee = rot(-112, 0, 0),
				LeftAnkle = rot(-5, 0, -3.3),
				RightHip = rot(29.2, -6.2, -0.1),
				RightKnee = rot(-43.2, 0, 0),
				RightAnkle = rot(20.1, 0, 3.2),
				LeftShoulder = rot(53.3, 0, -7.5),
				LeftElbow = rot(99.5, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(-43.3, 0, 13),
				RightElbow = rot(70.5, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			-- right foot flat under the hips, the body at its lowest
			time = 0.35,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.16, 0, -6, 5.2, 0),
				Waist = rot(-15, -7, -1.7),
				Neck = rot(2.5, 2.8, 0.9),
				LeftHip = rot(74, 5.8, 0.7),
				LeftKnee = rot(-100, 0, 0),
				LeftAnkle = rot(-10, 0, -3.3),
				RightHip = rot(14.9, -5.5, -1.9),
				RightKnee = rot(-40.8, 0, 0),
				RightAnkle = rot(31.9, 0, 3.2),
				LeftShoulder = rot(48.3, 0, -7),
				LeftElbow = rot(98, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(-38.3, 0, 12.5),
				RightElbow = rot(72, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			time = 0.375,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, -6, 4.2, 0),
				Waist = rot(-16, -5.7, -1.4),
				Neck = rot(3, 2.4, 0.7),
				LeftHip = rot(78, 5.9, 0.5),
				LeftKnee = rot(-82, 0, 0),
				LeftAnkle = rot(-12, 0, -3.3),
				RightHip = rot(9.2, -5.5, -2.3),
				RightKnee = rot(-47.2, 0, 0),
				RightAnkle = rot(21.5, 0, 3.2),
				LeftShoulder = rot(40.4, 0, -6.6),
				LeftElbow = rot(95.6, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(-30.4, 0, 11.5),
				RightElbow = rot(74.4, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			-- right toe pushes off
			time = 0.4,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.04, 0, -6, 3, 0),
				Waist = rot(-17, -4, -1),
				Neck = rot(3.5, 2, 0.5),
				LeftHip = rot(76, 6, 0.3),
				LeftKnee = rot(-62, 0, 0),
				LeftAnkle = rot(-12, 0, -3.3),
				RightHip = rot(-3.5, -4.8, -2.9),
				RightKnee = rot(-34.9, 0, 0),
				RightAnkle = rot(-0.6, 0, 3.3),
				LeftShoulder = rot(30, 0, -6.3),
				LeftElbow = rot(92.5, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(-20, 0, 9.7),
				RightElbow = rot(77.5, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
		{
			-- flight: the right heel kicks up behind, the left knee drives through
			time = 0.5,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.06, 0, -6, -3, 0),
				Waist = rot(-17, 4, 1),
				Neck = rot(3.5, 0, -0.5),
				LeftHip = rot(55, 6.4, -0.6),
				LeftKnee = rot(-22, 0, 0),
				LeftAnkle = rot(-10, 0, -3.3),
				RightHip = rot(15, -5.2, -2),
				RightKnee = rot(-115, 0, 0),
				RightAnkle = rot(15, 0, 3.3),
				LeftShoulder = rot(-20, 0, -6.3),
				LeftElbow = rot(77.5, 0, 0),
				LeftWrist = rot(-5, 0, 0),
				RightShoulder = rot(30, 0, 9.7),
				RightElbow = rot(92.5, 0, 0),
				RightWrist = rot(-5, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.02, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.32, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
