--!strict
--[[
	WalkForward's arm swing (D-135): the torso, head and arms of the sheathed walk as committed
	before it was keyed every 0.028125 s (git 927dbed; the root and legs left out). The swing is
	tuned to pass the scabbard (GroundClearance). Gaits.luau samples it at WalkForward's key times;
	the root and legs are generated.
]]

local Keys = require("../Keys")

local rot = Keys.rot

return Keys.source(0.9, {
	{
		-- left heel strikes, the right arm forward
		time = 0,
		easing = "SineInOut",
		joints = {
			Waist = rot(0, 6, 0),
			Neck = rot(2, -2, 0),
			LeftShoulder = rot(-7, 0, -7),
			LeftElbow = rot(9, 0, 0),
			LeftWrist = rot(-4, 0, 0),
			RightShoulder = rot(20, 0, 6),
			RightElbow = rot(19, 0, 0),
			RightWrist = rot(-4, 0, 0),
		},
	},
	{
		time = 0.1125,
		easing = "SineInOut",
		joints = {
			Waist = rot(0, 4.2, -1.4),
			Neck = rot(2, -1.4, 0),
			LeftShoulder = rot(-3, 0, -7),
			LeftElbow = rot(10.5, 0, 0),
			LeftWrist = rot(-4, 0, 0),
			RightShoulder = rot(15, 0, 5.3),
			RightElbow = rot(17.5, 0, 0),
			RightWrist = rot(-4, 0, 0),
		},
	},
	{
		-- passing: the body high over the left foot, the right leg swinging through
		time = 0.225,
		easing = "SineInOut",
		joints = {
			Waist = rot(0, 0, -2),
			Neck = rot(2, 0, 0),
			LeftShoulder = rot(5, 0, -7),
			LeftElbow = rot(14, 0, 0),
			LeftWrist = rot(-4, 0, 0),
			RightShoulder = rot(5, 0, 5),
			RightElbow = rot(14, 0, 0),
			RightWrist = rot(-4, 0, 0),
		},
	},
	{
		time = 0.3375,
		easing = "SineInOut",
		joints = {
			Waist = rot(0, -4.2, -1.4),
			Neck = rot(2, 1.4, 0),
			LeftShoulder = rot(15, 0, -6.7),
			LeftElbow = rot(17.5, 0, 0),
			LeftWrist = rot(-4, 0, 0),
			RightShoulder = rot(-3, 0, 6),
			RightElbow = rot(10.5, 0, 0),
			RightWrist = rot(-4, 0, 0),
		},
	},
	{
		-- right heel strikes, the left arm forward
		time = 0.45,
		easing = "SineInOut",
		joints = {
			Waist = rot(0, -6, 0),
			Neck = rot(2, 2, 0),
			LeftShoulder = rot(20, 0, -6),
			LeftElbow = rot(19, 0, 0),
			LeftWrist = rot(-4, 0, 0),
			RightShoulder = rot(-7, 0, 7),
			RightElbow = rot(9, 0, 0),
			RightWrist = rot(-4, 0, 0),
		},
	},
	{
		time = 0.5625,
		easing = "SineInOut",
		joints = {
			Waist = rot(0, -4.2, 1.4),
			Neck = rot(2, 1.4, 0),
			LeftShoulder = rot(15, 0, -5.3),
			LeftElbow = rot(17.5, 0, 0),
			LeftWrist = rot(-4, 0, 0),
			RightShoulder = rot(-3, 0, 7),
			RightElbow = rot(10.5, 0, 0),
			RightWrist = rot(-4, 0, 0),
		},
	},
	{
		-- passing: the body high over the right foot, the left leg swinging through
		time = 0.675,
		easing = "SineInOut",
		joints = {
			Waist = rot(0, 0, 2),
			Neck = rot(2, 0, 0),
			LeftShoulder = rot(5, 0, -5),
			LeftElbow = rot(14, 0, 0),
			LeftWrist = rot(-4, 0, 0),
			RightShoulder = rot(5, 0, 7),
			RightElbow = rot(14, 0, 0),
			RightWrist = rot(-4, 0, 0),
		},
	},
	{
		time = 0.7875,
		easing = "SineInOut",
		joints = {
			Waist = rot(0, 4.2, 1.4),
			Neck = rot(2, -1.4, 0),
			LeftShoulder = rot(-3, 0, -6),
			LeftElbow = rot(10.5, 0, 0),
			LeftWrist = rot(-4, 0, 0),
			RightShoulder = rot(15, 0, 6.7),
			RightElbow = rot(17.5, 0, 0),
			RightWrist = rot(-4, 0, 0),
		},
	},
})
