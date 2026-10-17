--!strict
--[[
	enemy/Boar/FlinchRight: additive hit reaction, a hit from the right: the body is shoved left, the head swings right to see it. Two frames of ExpoOut snap away
	from the hit, a BackOut counter-swing, a spring back to zero. Rides on the Additive layer so
	it works over the idle, the walk or an attack. Rig: Boar.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Boar/FlinchRight",
	rig = "Boar",
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
				Jaw = rot(0, 0, 0),
				FrontLeftHip = rot(0, 0, 0),
				FrontRightHip = rot(0, 0, 0),
				BackLeftHip = rot(0, 0, 0),
				BackRightHip = rot(0, 0, 0),
				TailJoint = rot(0, 0, 0),
			},
		},
		{
			time = 0.04,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.14, 0, 0, 0, 0, 7),
				Neck = rot(2, -16, 0),
				FrontRightHip = rot(0, 0, 6),
				BackRightHip = rot(0, 0, 6),
				TailJoint = rot(0, -10, 0),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(0.035, 0, 0, 0, 0, -1.75),
				Neck = rot(-0.5, 4, 0),
				FrontRightHip = rot(0, 0, -1.5),
				BackRightHip = rot(0, 0, -1.5),
				TailJoint = rot(0, 2.5, 0),
			},
		},
		{
			time = 0.3,
			easing = "Spring",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Neck = rot(0, 0, 0),
				Jaw = rot(0, 0, 0),
				FrontLeftHip = rot(0, 0, 0),
				FrontRightHip = rot(0, 0, 0),
				BackLeftHip = rot(0, 0, 0),
				BackRightHip = rot(0, 0, 0),
				TailJoint = rot(0, 0, 0),
			},
		},
	},
	events = {},
}

return clip
