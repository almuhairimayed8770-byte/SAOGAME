--!strict
--[[
	Sprint's upper body: the torso, head and arms of the sheathed sprint as re-keyed by hand for the
	back mount (D-050, D-055; legs left out): the waist twists less, the head stays in line with the
	torso (tipped back it meets the hilt) and the elbows go out at the back past the scabbard.
	Gaits.luau samples its root and upper body at Sprint's key times; the legs are generated.
]]

local Keys = require("../Keys")

local rot, posRot = Keys.rot, Keys.posRot

return Keys.source(0.5, {
	{
		-- left foot plants on the ball, the right arm thrown forward
		time = 0,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, -0.1, 0, -10, -7, 0),
			Waist = rot(-18, 8.4, 2),
			Neck = rot(2, -1.5, -1),
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
			LeftShoulder = rot(-21.9, 0, -12),
			LeftElbow = rot(75.4, 0, 0),
			LeftWrist = rot(-8, 0, 0),
			RightShoulder = rot(37.9, 0, 12.6),
			RightElbow = rot(94.6, 0, 0),
			RightWrist = rot(-8, 0, 0),
		},
	},
})
