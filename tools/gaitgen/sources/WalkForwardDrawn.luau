--!strict
--[[
	WalkForwardDrawn's upper body (D-134): the hand-keyed drawn walk as committed before the drawn
	set took the sheathed legs (git 927dbed; legs left out). Gaits.luau samples its pelvis turn,
	torso, head, arms and sword at WalkForward's key times; the root's height and the legs come
	from WalkForward.
]]

local Keys = require("../Keys")

local rot, posRot = Keys.rot, Keys.posRot

return Keys.source(0.9, {
	{
		-- left foot plants
		time = 0,
		easing = "QuadOut",
		joints = {
			Root = posRot(0, -0.06, 0, 0, 4, 0),
			Waist = rot(-4, -5, 1),
			Neck = rot(4, 1, 0),
			LeftShoulder = rot(-7, 0, -7),
			LeftElbow = rot(12, 0, 0),
			LeftWrist = rot(0, 0, 0),
			RightShoulder = rot(18, 0, 5),
			RightElbow = rot(16, 0, 0),
			RightWrist = rot(-12, 0, 0),
			Weapon = rot(-22, 0, 0),
		},
	},
	{
		-- right leg passes under the body; the body rides high
		time = 0.225,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, 0.03, 0, 0, 0, 0),
			Waist = rot(-4, 0, 0),
			Neck = rot(4, 0, 0),
			LeftShoulder = rot(0, 0, -4),
			RightShoulder = rot(0, 0, 5),
			RightWrist = rot(-6, 0, 0),
		},
	},
	{
		-- right foot plants
		time = 0.45,
		easing = "QuadOut",
		joints = {
			Root = posRot(0, -0.06, 0, 0, -4, 0),
			Waist = rot(-4, 5, -1),
			Neck = rot(4, -1, 0),
			LeftShoulder = rot(18, 0, -4),
			RightShoulder = rot(-18, 0, 5),
			RightWrist = rot(0, 0, 0),
		},
	},
	{
		-- left leg passes
		time = 0.675,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, 0.03, 0, 0, 0, 0),
			Waist = rot(-4, 0, 0),
			Neck = rot(4, 0, 0),
			LeftShoulder = rot(0, 0, -4),
			RightShoulder = rot(0, 0, 5),
			RightWrist = rot(-6, 0, 0),
		},
	},
})
