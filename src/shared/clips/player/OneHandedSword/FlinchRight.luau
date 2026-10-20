--!strict
--[[
	player/OneHandedSword/FlinchRight: additive hit reaction, a hit from the right: the torso is
	shoved left and turns away, the head follows, the left leg braces. Two frames of ExpoOut snap
	away from the hit, a spring back through a small counter-swing, back to zero at the end. Rides
	on the Additive layer so it works over walking, guarding or an Art.
	The sword arm rides the torso (no right shoulder key): a hit taken during Draw or Sheathe then
	keeps the blade in line with its sheath.
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
	id = "player/OneHandedSword/FlinchRight",
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
				LeftHip = rot(0, 0, 0),
				RightHip = rot(0, 0, 0),
			},
		},
		{
			time = 0.04,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.15, 0, 0, 0, 0, 0),
				Waist = rot(-4, 6, 9),
				Neck = rot(0, 0, 10),
				LeftShoulder = rot(0, 0, -10),
				LeftHip = rot(2, 0, 4),
				RightHip = rot(0, 0, -4),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(0.03, 0, 0, 0, 0, 0),
				Waist = rot(1, -1.5, -3),
				Neck = rot(0, 0, -3),
				LeftShoulder = rot(0, 0, 0.6),
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
			},
		},
	},
	events = {},
}

return clip
