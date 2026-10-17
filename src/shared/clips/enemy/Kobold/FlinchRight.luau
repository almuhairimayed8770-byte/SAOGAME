--!strict
--[[
	enemy/Kobold/FlinchRight: additive hit reaction, a hit from the right: the body is shoved left, the head follows. Two frames of ExpoOut snap away
	from the hit, a BackOut counter-swing, a spring back to zero. Rides on the Additive layer so
	it works over the idle, the walk or an attack. Rig: Kobold.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Kobold/FlinchRight",
	rig = "Kobold",
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
				Neck = rot(0, 0, 0),
				LeftShoulder = rot(0, 0, 0),
				RightShoulder = rot(0, 0, 0),
				LeftHip = rot(0, 0, 0),
				RightHip = rot(0, 0, 0),
				Weapon = rot(0, 0, 0),
			},
		},
		{
			time = 0.04,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.14, 0, 0, 0, 6, 12),
				Neck = rot(0, -12, 8),
				LeftShoulder = rot(0, 0, -10),
				RightShoulder = rot(0, 0, -10),
				RightHip = rot(0, 0, -4),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(0.035, 0, 0, 0, -1.5, -3),
				Neck = rot(0, 3, -2),
				LeftShoulder = rot(0, 0, 2.5),
				RightShoulder = rot(0, 0, 2.5),
				RightHip = rot(0, 0, 1),
			},
		},
		{
			time = 0.3,
			easing = "Spring",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Neck = rot(0, 0, 0),
				LeftShoulder = rot(0, 0, 0),
				RightShoulder = rot(0, 0, 0),
				LeftHip = rot(0, 0, 0),
				RightHip = rot(0, 0, 0),
				Weapon = rot(0, 0, 0),
			},
		},
	},
	events = {},
}

return clip
