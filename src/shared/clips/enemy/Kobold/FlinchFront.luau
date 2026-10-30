--!strict
--[[
	enemy/Kobold/FlinchFront: additive hit reaction, a hit from the front: the chest snaps back over the hips, the head with it, the arms fly up. A three-frame QuadOut snap away
	from the hit, a BackOut counter-swing, a spring back to zero. Rides on the Additive layer so
	it works over the idle, the walk or an attack. Rig: Kobold.
	The legs are rigid blocks, so the body turns about a hip, never about the torso's centre: the
	root's shift keeps the pivot (the hip axis for a pitch, the hip the body tips over for a roll)
	where the stance has it, and the hips turn against the root so the legs keep their stance.
	A pitch keeps both feet planted; a roll lifts the far foot straight up and sets it down where
	it stood. The snap is three frames, not two: an arm turned 26 degrees in the first frame.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Kobold/FlinchFront",
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
			time = 0.05,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, 0.0063, 0.2506, 12, 0, 0),
				Neck = rot(10, 0, 0),
				LeftShoulder = rot(9, 0, -8),
				RightShoulder = rot(9, 0, 8),
				Weapon = rot(8, 0, 0),
				LeftHip = rot(-11.99, 0.31, 0.01),
				RightHip = rot(-11.99, 0.31, 0.06),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(0, -0.0097, -0.062, -3, 0, 0),
				Neck = rot(-4, 0, 0),
				LeftShoulder = rot(-3.5, 0, 2.5),
				RightShoulder = rot(-3.5, 0, -2.5),
				Weapon = rot(-2, 0, 0),
				LeftHip = rot(3, -0.08, 0.01),
				RightHip = rot(3, -0.08, 0),
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
