--!strict
--[[
	enemy/Kobold/FlinchRight: additive hit reaction, a hit from the right: the body tips left over the left leg, the right foot kicks up off the field and the head follows the shove. A three-frame QuadOut snap away
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
			time = 0.05,
			easing = "QuadOut",
			joints = {
				Root = posRot(-0.2209, 0.0756, -0.0405, 0, 5, 10),
				Neck = rot(0, -12, 8),
				LeftShoulder = rot(0, 0, -10),
				RightShoulder = rot(0, 0, -10),
				Weapon = rot(0, 0, 0),
				LeftHip = rot(-1.05, -5.45, -9.75),
				RightHip = rot(-0.92, -4.02, -14.42),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(-0.0428, 0.0177, -0.0116, 0, 1, 2),
				Neck = rot(0, 3, -2),
				LeftShoulder = rot(0, 0, 2.5),
				RightShoulder = rot(0, 0, 2.5),
				Weapon = rot(0, 0, 0),
				LeftHip = rot(-0.07, -1.11, -1.94),
				RightHip = rot(-0.05, -0.82, -3.08),
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
