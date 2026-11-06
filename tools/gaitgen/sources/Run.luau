--!strict
--[[
	Run's upper body: the torso, head and arms of the sheathed run as re-keyed by hand for the
	back mount (D-050, D-055; legs left out): the waist twists less, the head stays in line with the
	torso (tipped back it meets the hilt) and the elbows go out at the back past the scabbard.
	Gaits.luau samples its root and upper body at Run's key times; the legs are generated.
]]

local Keys = require("../Keys")

local rot, posRot = Keys.rot, Keys.posRot

return Keys.source(0.6, {
	{
		-- left foot plants on the ball, the right arm forward
		time = 0,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, -0.08, 0, -6, -6, 0),
			Waist = rot(-14, 8, 2),
			Neck = rot(2, -1, -1),
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
			LeftShoulder = rot(-20, 0, -6.3),
			LeftElbow = rot(77.5, 0, 0),
			LeftWrist = rot(-5, 0, 0),
			RightShoulder = rot(30, 0, 9.7),
			RightElbow = rot(92.5, 0, 0),
			RightWrist = rot(-5, 0, 0),
		},
	},
})
