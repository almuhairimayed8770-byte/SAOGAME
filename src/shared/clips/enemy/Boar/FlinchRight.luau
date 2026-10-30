--!strict
--[[
	enemy/Boar/FlinchRight: additive hit reaction, a hit from the right: the body tips left over its left legs, the right legs come up off the field and splay, the head swings right to see it. A three-frame QuadOut snap away
	from the hit, a BackOut settle, a spring back to zero. Rides on the Additive layer so it
	works over the idle, the walk or an attack. Rig: Boar.
	Four rigid legs on the field let the torso neither pitch nor roll about its centre, so the
	body turns about a line of hips: the root's shift keeps that line where the stance has it and
	every hip turns against the root, so the planted legs keep their stance and the lifted ones
	rise straight up and come down where they stood. The settle keeps the turn's sign (a smaller
	turn about the same hips), so no planted foot is pushed into the field.
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
				FrontLeftHip = rot(0, 0, 0),
				FrontRightHip = rot(0, 0, 0),
				BackLeftHip = rot(0, 0, 0),
				BackRightHip = rot(0, 0, 0),
				TailJoint = rot(0, 0, 0),
			},
		},
		{
			time = 0.05,
			easing = "QuadOut",
			joints = {
				Root = posRot(-0.1303, 0.1, 0.0007, 0, 0, 7),
				Neck = rot(2, -16, 0),
				FrontLeftHip = rot(-0.02, -0.36, -6.99),
				FrontRightHip = rot(0.03, 0.48, -0.98),
				BackLeftHip = rot(0.01, 0.24, -7),
				BackRightHip = rot(-0.01, -0.24, -1),
				TailJoint = rot(0, -10, 0),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(-0.0215, 0.0183, 0.0001, 0, 0, 1.2),
				Neck = rot(-0.5, 4, 0),
				FrontLeftHip = rot(0, -0.06, -1.2),
				FrontRightHip = rot(0, 0.08, -0.2),
				BackLeftHip = rot(0, 0.04, -1.2),
				BackRightHip = rot(0, -0.04, -0.2),
				TailJoint = rot(0, 2.5, 0),
			},
		},
		{
			time = 0.3,
			easing = "Spring",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Neck = rot(0, 0, 0),
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
