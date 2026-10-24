--!strict
--[[
	player/OneHandedSword/GuardHit: a blocked hit. From the guard pose the blade is knocked back
	into the chest in 3 frames (ExpoOut), the head snaps back, the torso gives; then a spring back
	into the guard. UpperBody so the legs stay under the locomotion layer.
	Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/GuardHit",
	rig = "PlayerR15",
	duration = 0.35,
	loop = false,
	layer = "UpperBody",
	priority = 12,
	blendIn = 0.02,
	blendOut = 0.1,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
			joints = {
				Waist = rot(-10, -4, 0),
				Neck = rot(6, 4, 0),
				RightShoulder = rot(58, 0, -28),
				RightElbow = rot(96, 0, 0),
				RightWrist = rot(-10, 0, 42),
				Weapon = rot(-38, 0, -16),
				LeftShoulder = rot(44, 0, -8),
				LeftElbow = rot(84, 0, 0),
				LeftWrist = rot(-20, 0, -36),
			},
		},
		{
			-- the block takes the hit
			time = 0.05,
			easing = "ExpoOut",
			joints = {
				Waist = rot(4, -14, 2),
				Neck = rot(-10, 10, 0),
				RightShoulder = rot(40, 0, -36),
				RightElbow = rot(114, 0, 0),
				RightWrist = rot(-14, 0, 46),
				Weapon = rot(-34, 0, -20),
				LeftShoulder = rot(30, 0, -14),
				LeftElbow = rot(100, 0, 0),
			},
		},
		{
			time = 0.1,
			easing = "Hold",
			joints = {
				Waist = rot(4, -14, 2),
			},
		},
		{
			-- spring back into the guard
			time = 0.35,
			easing = "Spring",
			joints = {
				Waist = rot(-10, -4, 0),
				Neck = rot(6, 4, 0),
				RightShoulder = rot(58, 0, -28),
				RightElbow = rot(96, 0, 0),
				RightWrist = rot(-10, 0, 42),
				Weapon = rot(-38, 0, -16),
				LeftShoulder = rot(44, 0, -8),
				LeftElbow = rot(84, 0, 0),
			},
		},
	},
	events = {},
}

return clip
