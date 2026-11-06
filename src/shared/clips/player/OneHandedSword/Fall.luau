--!strict
--[[
	player/OneHandedSword/Fall: airborne loop. Arms out for balance, legs hanging with one knee
	up, a slow sway, the coat (procedural) flaring. Land takes over on contact.
	Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/Fall",
	rig = "PlayerR15",
	duration = 0.8,
	loop = true,
	layer = "FullBody",
	priority = 4,
	blendIn = 0.15,
	blendOut = 0.1,
	keys = {
		{
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Waist = rot(-8, 0, 2),
				Neck = rot(10, 0, -1),
				LeftHip = rot(24, 0, -8),
				LeftKnee = rot(-50, 0, 0),
				LeftAnkle = rot(16, 0, 0),
				RightHip = rot(6, 0, 8),
				RightKnee = rot(-22, 0, 0),
				RightAnkle = rot(10, 0, 0),
				LeftShoulder = rot(20, 0, -55),
				LeftElbow = rot(24, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(16, 0, 50),
				RightElbow = rot(26, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-76, 0, 0),
			},
		},
		{
			time = 0.4,
			easing = "SineInOut",
			joints = {
				Waist = rot(-6, 0, -2),
				Neck = rot(9, 0, 1),
				LeftHip = rot(20, 0, -10),
				LeftKnee = rot(-46, 0, 0),
				RightHip = rot(10, 0, 10),
				RightKnee = rot(-26, 0, 0),
				LeftShoulder = rot(24, 0, -60),
				RightShoulder = rot(20, 0, 56),
			},
		},
	},
	events = {},
}

return clip
