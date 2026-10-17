--!strict
--[[
	enemy/Kobold/Stagger: the 1.0 s parry stagger (combat.luau parryStagger). The axe is knocked
	wide, the body reels back in 4 frames with the head thrown up, a BackOut catch on a bent
	back leg, a spring wobble, then a slow recovery into the stance.
	Rig: Kobold. Root X+ arches back.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Kobold/Stagger",
	rig = "Kobold",
	duration = 1.0,
	loop = false,
	layer = "FullBody",
	priority = 30,
	blendIn = 0.02,
	blendOut = 0.2,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
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
			-- reeling back, the axe knocked wide
			time = 0.07,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.1, 0.3, 24, -10, -4),
				Neck = rot(22, -8, 0),
				RightShoulder = rot(70, 0, 70),
				Weapon = rot(-10, 0, 20),
				LeftShoulder = rot(60, 0, -50),
				LeftHip = rot(26, 0, -6),
				RightHip = rot(-30, 0, 8),
			},
		},
		{
			time = 0.14,
			easing = "Hold",
			joints = {
				Root = posRot(0, -0.1, 0.3, 24, -10, -4),
			},
		},
		{
			-- the catch on the back leg
			time = 0.4,
			easing = "BackOut",
			joints = {
				Root = posRot(0, -0.3, 0.3, 6, -4, 3),
				Neck = rot(4, -2, 0),
				RightShoulder = rot(40, 0, 40),
				Weapon = rot(-30, 0, 10),
				LeftShoulder = rot(30, 0, -34),
				LeftHip = rot(20, 0, -6),
				RightHip = rot(-20, 0, 8),
			},
		},
		{
			-- wobble
			time = 0.65,
			easing = "Spring",
			joints = {
				Root = posRot(0.04, -0.2, 0.2, -2, 2, -4),
				Neck = rot(2, 4, 0),
				RightShoulder = rot(24, 0, 24),
				LeftShoulder = rot(16, 0, -22),
			},
		},
		{
			time = 1.0,
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
	},
	events = {
		{ time = 0.05, kind = "Voice", data = { name = "enemy.BruteStagger" } },
		{ time = 0.42, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
