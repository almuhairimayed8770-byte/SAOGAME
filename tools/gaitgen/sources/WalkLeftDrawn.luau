--!strict
--[[
	WalkLeftDrawn's upper body (D-128): the torso, head, arms and sword of the earlier drawn
	side-step to the left (git 927dbed; the root and legs left out). Gaits.luau samples it at the
	shuffle's key times, lifts the sword arm, and generates the shuffle's pelvis and legs.
]]

local Keys = require("../Keys")

local rot = Keys.rot

return Keys.source(0.9, {
	{
		-- left foot plants out to the left
		time = 0,
		easing = "QuadOut",
		joints = {
			Waist = rot(-3, 0, 4),
			Neck = rot(3, 0, -3),
			LeftShoulder = rot(4, 0, -14),
			LeftElbow = rot(12, 0, 0),
			LeftWrist = rot(0, 0, 0),
			RightShoulder = rot(2, 0, 4),
			RightElbow = rot(16, 0, 0),
			RightWrist = rot(-6, 0, 0),
			Weapon = rot(-34, 0, 0),
		},
	},
	{
		-- right leg lifts and crosses behind
		time = 0.225,
		easing = "SineInOut",
		joints = {
			LeftShoulder = rot(4, 0, -8),
		},
	},
	{
		-- right foot plants behind the left
		time = 0.45,
		easing = "QuadOut",
		joints = {
			LeftShoulder = rot(4, 0, -10),
		},
	},
	{
		-- left leg lifts and reaches out again
		time = 0.675,
		easing = "SineInOut",
		joints = {
			LeftShoulder = rot(4, 0, -16),
		},
	},
})
