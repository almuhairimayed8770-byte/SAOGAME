--!strict
--[[
	enemy/Boar/FlinchFront: additive hit reaction, a hit from the front: the nose is knocked up, the front legs give back. Two frames of ExpoOut snap away
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
	id = "enemy/Boar/FlinchFront",
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
				Root = posRot(0, 0, 0.14, 7, 0, 0),
				Neck = rot(14, 0, 0),
				Jaw = rot(-8, 0, 0),
				FrontLeftHip = rot(-10, 0, 0),
				FrontRightHip = rot(-10, 0, 0),
				TailJoint = rot(-6, 0, 0),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(0, 0, -0.035, -1.75, 0, 0),
				Neck = rot(-3.5, 0, 0),
				Jaw = rot(2, 0, 0),
				FrontLeftHip = rot(2.5, 0, 0),
				FrontRightHip = rot(2.5, 0, 0),
				TailJoint = rot(1.5, 0, 0),
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
