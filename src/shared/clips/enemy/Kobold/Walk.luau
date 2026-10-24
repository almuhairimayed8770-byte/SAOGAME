--!strict
--[[
	enemy/Kobold/Walk: a heavy 0.8 s stride, hunched, the axe swinging with the right arm, the
	free arm counter-swinging, the body rolling side to side. Footsteps on the plants.
	Rig: Kobold. Hip X+ swings a leg forward; Shoulder X+ swings an arm forward.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Kobold/Walk",
	rig = "Kobold",
	duration = 0.8,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left foot plants
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.08, 0, -10, 4, 4),
				Neck = rot(8, -3, -2),
				LeftHip = rot(30, 0, -4),
				RightHip = rot(-26, 0, 4),
				LeftShoulder = rot(-22, 0, -10),
				RightShoulder = rot(26, 0, 12),
				Weapon = rot(-34, 0, 0),
			},
		},
		{
			time = 0.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, 0, -9, 0, 0),
				Neck = rot(7, 0, 0),
				LeftHip = rot(2, 0, -4),
				RightHip = rot(4, 0, 4),
				LeftShoulder = rot(0, 0, -10),
				RightShoulder = rot(8, 0, 12),
			},
		},
		{
			-- right foot plants
			time = 0.4,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.08, 0, -10, -4, -4),
				Neck = rot(8, 3, 2),
				LeftHip = rot(-26, 0, -4),
				RightHip = rot(30, 0, 4),
				LeftShoulder = rot(26, 0, -10),
				RightShoulder = rot(-18, 0, 12),
				Weapon = rot(-26, 0, 0),
			},
		},
		{
			time = 0.6,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, 0, -9, 0, 0),
				Neck = rot(7, 0, 0),
				LeftHip = rot(4, 0, -4),
				RightHip = rot(2, 0, 4),
				LeftShoulder = rot(0, 0, -10),
				RightShoulder = rot(8, 0, 12),
			},
		},
	},
	events = {
		{ time = 0.02, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.42, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
