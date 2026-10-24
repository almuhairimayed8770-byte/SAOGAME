--!strict
--[[
	enemy/Kobold/FlinchBack: additive hit reaction, a hit from behind: the chest is thrown forward, the head whips back. Two frames of ExpoOut snap away
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
	id = "enemy/Kobold/FlinchBack",
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
				Root = posRot(0, 0, -0.14, -12, 0, 0),
				Neck = rot(14, 0, 0),
				LeftShoulder = rot(-10, 0, -6),
				RightShoulder = rot(-10, 0, 6),
				Weapon = rot(-8, 0, 0),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(0, 0, 0.035, 3, 0, 0),
				Neck = rot(-3.5, 0, 0),
				LeftShoulder = rot(2.5, 0, 1.5),
				RightShoulder = rot(2.5, 0, -1.5),
				Weapon = rot(2, 0, 0),
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
