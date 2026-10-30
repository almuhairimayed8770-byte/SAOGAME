--!strict
--[[
	enemy/Boar/FlinchFront: additive hit reaction, a hit from the front: the nose is knocked up and the body rears back over the hind legs, the front legs come up off the field and give back. A three-frame QuadOut snap away
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
				Root = posRot(0, 0.1623, 0.1333, 7, 0, 0),
				Neck = rot(12, 0, 0),
				FrontLeftHip = rot(-17, 0.12, 0),
				FrontRightHip = rot(-17, 0.12, 0.02),
				BackLeftHip = rot(-7, 0.12, 0.01),
				BackRightHip = rot(-7, 0.12, 0),
				TailJoint = rot(-6, 0, 0),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(0, 0.029, 0.0214, 1.2, 0, 0),
				Neck = rot(-3.5, 0, 0),
				FrontLeftHip = rot(-3.2, 0.02, 0),
				FrontRightHip = rot(-3.2, 0.02, 0),
				BackLeftHip = rot(-1.2, 0.02, 0),
				BackRightHip = rot(-1.2, 0.02, 0),
				TailJoint = rot(1.5, 0, 0),
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
