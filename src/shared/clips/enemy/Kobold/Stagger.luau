--!strict
--[[
	enemy/Kobold/Stagger: the 1.0 s parry stagger (combat.luau parryStagger, F8). It plays on the
	clash frame from the landed chop it answers (key 0 is enemy/Kobold/Overhead at 1.35 s, the
	server's strike), so nothing jumps: the axe is knocked back up and wide and the body thrown
	back over 4 frames (QuadOut under a 0.06 s blend-in), held on the clash for 3 frames, then the
	reeled silhouette teeters back, still open, until 0.6 s. A step back, a BackOut catch on the
	back leg at 0.75 s, and the recovery into the stance by 1.0 s.
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
	blendIn = 0.06,
	blendOut = 0.2,
	keys = {
		{
			-- the landed chop it answers
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(-0.04, -0.42, -0.14, -32, 16, 2),
				Neck = rot(-16, -12, 0),
				RightShoulder = rot(18, 0, 0),
				Weapon = rot(-74, 0, 0),
				LeftShoulder = rot(-32, 0, -14),
				LeftHip = rot(36, 0, -6),
				RightHip = rot(-26, 0, 8),
			},
		},
		{
			-- knocked back: the axe thrown up and wide, the head up, the free arm flung out
			time = 0.0667,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0.3, 22, -12, -5),
				Neck = rot(24, -10, 0),
				RightShoulder = rot(100, 0, 60),
				Weapon = rot(-6, 0, 24),
				LeftShoulder = rot(55, 0, -50),
				LeftHip = rot(28, 0, -6),
				RightHip = rot(-30, 0, 8),
			},
		},
		{
			-- held on the clash
			time = 0.12,
			easing = "Hold",
			joints = {
				Root = posRot(0, -0.12, 0.3, 22, -12, -5),
			},
		},
		{
			-- teetering back, still open
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.02, -0.16, 0.42, 18, -10, -6),
				Neck = rot(18, -8, 2),
				RightShoulder = rot(94, 0, 56),
				Weapon = rot(-10, 0, 20),
				LeftShoulder = rot(50, 0, -46),
				LeftHip = rot(30, 0, -6),
				RightHip = rot(-34, 0, 8),
			},
		},
		{
			-- the step back
			time = 0.6,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.02, -0.22, 0.5, 15, -8, -4),
				Neck = rot(14, -6, 2),
				RightShoulder = rot(88, 0, 52),
				Weapon = rot(-12, 0, 18),
				LeftShoulder = rot(46, 0, -42),
			},
		},
		{
			-- the catch on the back leg
			time = 0.75,
			easing = "BackOut",
			joints = {
				Root = posRot(0, -0.3, 0.45, 6, -4, 2),
				Neck = rot(6, -2, 0),
				RightShoulder = rot(50, 0, 36),
				Weapon = rot(-26, 0, 8),
				LeftShoulder = rot(30, 0, -30),
				LeftHip = rot(20, 0, -6),
				RightHip = rot(-20, 0, 8),
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
		{ time = 0.03, kind = "Voice", data = { name = "enemy.BruteStagger" } },
		{ time = 0.62, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
