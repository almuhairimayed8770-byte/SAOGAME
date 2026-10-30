--!strict
--[[
	RunDrawn's upper body (D-134): the hand-keyed drawn run as committed before the drawn set took
	the sheathed legs (git 927dbed; legs left out). Gaits.luau samples its pelvis turn, torso, head,
	arms and sword at Run's key times; the root's height and the legs come from Run.
]]

local Keys = require("../Keys")

local rot, posRot = Keys.rot, Keys.posRot

return Keys.source(0.6, {
	{
		-- left foot plants, body low
		time = 0,
		easing = "QuadOut",
		joints = {
			Root = posRot(0, -0.12, 0, 0, 6, 0),
			Waist = rot(-14, -6, 2),
			Neck = rot(12, 2, 0),
			LeftShoulder = rot(-36, 0, -6),
			LeftElbow = rot(80, 0, 0),
			LeftWrist = rot(0, 0, 0),
			RightShoulder = rot(24, 0, 8),
			RightElbow = rot(70, 0, 0),
			RightWrist = rot(-10, 0, 0),
			Weapon = rot(-80, 0, 0),
		},
	},
	{
		-- flight: both legs folding, the body high
		time = 0.15,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, 0.08, 0, 0, 0, 0),
			Waist = rot(-14, 0, 0),
			Neck = rot(12, 0, 0),
			LeftShoulder = rot(0, 0, -6),
			LeftElbow = rot(85, 0, 0),
			RightShoulder = rot(0, 0, 8),
			RightElbow = rot(75, 0, 0),
			RightWrist = rot(0, 0, 0),
		},
	},
	{
		-- right foot plants
		time = 0.3,
		easing = "QuadOut",
		joints = {
			Root = posRot(0, -0.12, 0, 0, -6, 0),
			Waist = rot(-14, 6, -2),
			Neck = rot(12, -2, 0),
			LeftShoulder = rot(40, 0, -6),
			LeftElbow = rot(70, 0, 0),
			RightShoulder = rot(-20, 0, 8),
			RightElbow = rot(80, 0, 0),
			RightWrist = rot(8, 0, 0),
		},
	},
	{
		time = 0.45,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, 0.08, 0, 0, 0, 0),
			Waist = rot(-14, 0, 0),
			Neck = rot(12, 0, 0),
			LeftShoulder = rot(0, 0, -6),
			LeftElbow = rot(75, 0, 0),
			RightShoulder = rot(0, 0, 8),
			RightElbow = rot(85, 0, 0),
			RightWrist = rot(-9, 0, 0),
		},
	},
})
