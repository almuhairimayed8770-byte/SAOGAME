--!strict
--[[
	enemy/Kobold/Idle: the Kobold Axeman at rest, a 4 s loop. Hunched, the axe hanging in the
	right hand, breathing on the chest, the head scanning left and right, a weight shift at 2 s
	and a hitch of the axe at 3 s. Rig: Kobold (rigs.luau). Root X- hunches forward; Shoulder
	X+ swings an arm forward; Weapon X- tips the axe head down.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Kobold/Idle",
	rig = "Kobold",
	duration = 4,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.2,
	blendOut = 0.2,
	keys = {
		{
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, -8, 0, 0),
				Neck = rot(6, 0, 0),
				LeftShoulder = rot(6, 0, -10),
				RightShoulder = rot(10, 0, 12),
				LeftHip = rot(4, 0, -4),
				RightHip = rot(-4, 0, 4),
				Weapon = rot(-30, 0, 0),
			},
		},
		{
			-- breath, head scans left
			time = 1.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.02, 0, -6, 0, 0),
				Neck = rot(4, 22, 0),
				LeftShoulder = rot(6, 0, -12),
				RightShoulder = rot(12, 0, 13),
			},
		},
		{
			-- weight shift onto the left leg
			time = 2,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.1, -0.06, 0, -8, 0, 3),
				Neck = rot(6, -4, -2),
				LeftHip = rot(4, 0, 0),
				RightHip = rot(-4, 0, 10),
			},
		},
		{
			-- the axe hitches up and drops, head scans right
			time = 2.9,
			easing = "QuadOut",
			joints = {
				RightShoulder = rot(26, 0, 14),
				Weapon = rot(-44, 0, 0),
				Neck = rot(4, -22, 0),
			},
		},
		{
			time = 3.2,
			easing = "BackOut",
			joints = {
				RightShoulder = rot(10, 0, 12),
				Weapon = rot(-30, 0, 0),
			},
		},
		{
			time = 3.6,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, -8, 0, 0),
				Neck = rot(6, -8, 0),
				LeftHip = rot(4, 0, -4),
				RightHip = rot(-4, 0, 4),
			},
		},
	},
	events = {
		{ time = 2.9, kind = "Sfx", data = { name = "KoboldGrunt" } },
	},
}

return clip
