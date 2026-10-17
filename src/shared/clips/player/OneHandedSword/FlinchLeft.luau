--!strict
--[[
	player/OneHandedSword/FlinchLeft: additive hit reaction, a hit from the left: the torso is shoved right, the head follows. Two frames of
	ExpoOut snap away from the hit, a spring back through a small counter-swing, back to zero at
	the end. Rides on the Additive layer so it works over walking, guarding or an Art.
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
	id = "player/OneHandedSword/FlinchLeft",
	rig = "PlayerR15",
	duration = 0.3,
	loop = false,
	layer = "Additive",
	priority = 5,
	blendIn = 0,
	blendOut = 0.05,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Waist = rot(0, 0, 0),
				Neck = rot(0, 0, 0),
				LeftShoulder = rot(0, 0, 0),
				RightShoulder = rot(0, 0, 0),
				LeftHip = rot(0, 0, 0),
				RightHip = rot(0, 0, 0),
			},
		},
		{
			time = 0.04,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.12, 0, 0, 0, 0, 0),
				Waist = rot(0, 0, -12),
				Neck = rot(0, -6, -10),
				LeftShoulder = rot(0, 0, 10),
				RightShoulder = rot(0, 0, 10),
				LeftHip = rot(0, 0, 4),
				RightHip = rot(0, 0, 4),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(-0.03, 0, 0, 0, 0, 0),
				Waist = rot(0, 0, 3),
				Neck = rot(0, 1.8, 3),
				LeftShoulder = rot(0, 0, -2),
				RightShoulder = rot(0, 0, -2),
				LeftHip = rot(0, 0, 0),
				RightHip = rot(0, 0, 0),
			},
		},
		{
			time = 0.3,
			easing = "Spring",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Waist = rot(0, 0, 0),
				Neck = rot(0, 0, 0),
				LeftShoulder = rot(0, 0, 0),
				RightShoulder = rot(0, 0, 0),
			},
		},
	},
	events = {},
}

return clip
