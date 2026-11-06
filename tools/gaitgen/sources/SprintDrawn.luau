--!strict
--[[
	SprintDrawn's upper body (D-134): the hand-keyed drawn sprint as committed before the drawn set
	took the sheathed legs (git 927dbed; legs left out). Gaits.luau samples its pelvis turn, torso,
	head, arms and sword at Sprint's key times; the root's height and the legs come from Sprint.
]]

local Keys = require("../Keys")

local rot, posRot = Keys.rot, Keys.posRot

return Keys.source(0.5, {
	{
		time = 0,
		easing = "QuadOut",
		joints = {
			Root = posRot(0, -0.14, 0, 0, 8, 0),
			Waist = rot(-22, -8, 3),
			Neck = rot(16, 3, 0),
			LeftShoulder = rot(-48, 0, -8),
			LeftElbow = rot(88, 0, 0),
			LeftWrist = rot(0, 0, 0),
			RightShoulder = rot(30, 0, 10),
			RightElbow = rot(78, 0, 0),
			RightWrist = rot(-14, 0, 0),
			Weapon = rot(-80, 0, 0),
		},
	},
	{
		time = 0.125,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, 0.1, 0, 0, 0, 0),
			Waist = rot(-22, 0, 0),
			Neck = rot(16, 0, 0),
			LeftShoulder = rot(0, 0, -8),
			LeftElbow = rot(92, 0, 0),
			RightShoulder = rot(0, 0, 10),
			RightElbow = rot(84, 0, 0),
			RightWrist = rot(2, 0, 0),
		},
	},
	{
		time = 0.25,
		easing = "QuadOut",
		joints = {
			Root = posRot(0, -0.14, 0, 0, -8, 0),
			Waist = rot(-22, 8, -3),
			Neck = rot(16, -3, 0),
			LeftShoulder = rot(50, 0, -8),
			LeftElbow = rot(78, 0, 0),
			RightShoulder = rot(-28, 0, 10),
			RightElbow = rot(88, 0, 0),
			RightWrist = rot(18, 0, 0),
		},
	},
	{
		time = 0.375,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, 0.1, 0, 0, 0, 0),
			Waist = rot(-22, 0, 0),
			Neck = rot(16, 0, 0),
			LeftShoulder = rot(0, 0, -8),
			LeftElbow = rot(84, 0, 0),
			RightShoulder = rot(0, 0, 10),
			RightElbow = rot(92, 0, 0),
			RightWrist = rot(-6, 0, 0),
		},
	},
})
