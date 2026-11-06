--!strict
--[[
	WalkBackDrawn's upper body (D-054): the hand-keyed drawn backpedal as committed before it took
	WalkBack's legs (git 927dbed; legs left out). Gaits.luau samples its root, torso, head, arms and
	sword at WalkBack's key times and lowers the root to the sheathed backpedal's pelvis.
]]

local Keys = require("../Keys")

local rot, posRot = Keys.rot, Keys.posRot

return Keys.source(0.9, {
	{
		-- left foot reaches back and plants
		time = 0,
		easing = "QuadOut",
		joints = {
			Root = posRot(0, -0.05, 0, 0, 3, 0),
			Waist = rot(2, -3, 0),
			Neck = rot(0, 0, 0),
			LeftShoulder = rot(10, 0, -5),
			LeftElbow = rot(14, 0, 0),
			LeftWrist = rot(0, 0, 0),
			RightShoulder = rot(-10, 0, 6),
			RightElbow = rot(16, 0, 0),
			RightWrist = rot(-6, 0, 0),
			Weapon = rot(-28, 0, 0),
		},
	},
	{
		time = 0.225,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, 0.02, 0, 0, 0, 0),
			Waist = rot(2, 0, 0),
			LeftShoulder = rot(0, 0, -5),
			RightShoulder = rot(0, 0, 6),
		},
	},
	{
		-- right foot reaches back and plants
		time = 0.45,
		easing = "QuadOut",
		joints = {
			Root = posRot(0, -0.05, 0, 0, -3, 0),
			Waist = rot(2, 3, 0),
			LeftShoulder = rot(-10, 0, -5),
			RightShoulder = rot(10, 0, 6),
		},
	},
	{
		time = 0.675,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, 0.02, 0, 0, 0, 0),
			Waist = rot(2, 0, 0),
			LeftShoulder = rot(0, 0, -5),
			RightShoulder = rot(0, 0, 6),
		},
	},
})
