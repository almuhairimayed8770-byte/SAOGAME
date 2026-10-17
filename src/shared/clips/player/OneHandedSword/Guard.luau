--!strict
--[[
	player/OneHandedSword/Guard: the guard loop on the UpperBody layer so the legs keep walking.
	The blade stands across the body in front of the face, the free hand braces the flat near
	the guard, the torso squares to the threat and sinks. A 2 s breath keeps it alive.
	Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/Guard",
	rig = "PlayerR15",
	duration = 2,
	loop = true,
	layer = "UpperBody",
	priority = 10,
	blendIn = 0.08,
	blendOut = 0.15,
	keys = {
		{
			time = 0,
			easing = "SineInOut",
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
			time = 1,
			easing = "SineInOut",
			joints = {
				Waist = rot(-9, -4, 0),
				RightShoulder = rot(59, 0, -27),
				LeftShoulder = rot(45, 0, -8),
			},
		},
	},
	events = {},
}

return clip
