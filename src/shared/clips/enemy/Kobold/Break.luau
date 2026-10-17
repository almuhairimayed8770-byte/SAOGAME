--!strict
--[[
	enemy/Kobold/Break: Guard Break, 3 s (combat.luau breakDuration): the kneel with the weapon
	dropping (section 10). The right leg folds under, the body drops onto that knee and slumps
	forward, the axe arm goes limp with the head on the ground, the head hangs; then a panting
	cycle on the chest until the clip ends (the last key holds if Break outlasts it).
	Rig: Kobold. Root X- slumps forward; Hip X- folds a leg back; Weapon X- tips the axe down.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local function pant(time: number, inhale: boolean): Types.ClipKey
	return {
		time = time,
		easing = "SineInOut",
		joints = {
			Root = posRot(0.04, if inhale then -1.06 else -1.1, 0.1, if inhale then -14 else -18, 6, 2),
			Neck = rot(if inhale then -22 else -28, 0, 0),
			LeftShoulder = rot(if inhale then 14 else 10, 0, -26),
		},
	}
end

local clip: Types.ClipDef = {
	id = "enemy/Kobold/Break",
	rig = "Kobold",
	duration = 3,
	loop = false,
	layer = "FullBody",
	priority = 32,
	blendIn = 0.03,
	blendOut = 0.25,
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
			-- the right leg folds, the body drops
			time = 0.1,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.04, -0.8, 0.1, -12, 4, 2),
				Neck = rot(-10, 0, 0),
				RightHip = rot(-80, 0, 8),
				LeftHip = rot(44, 0, -8),
				RightShoulder = rot(-4, 0, 16),
				Weapon = rot(-70, 0, 0),
				LeftShoulder = rot(20, 0, -30),
			},
		},
		{
			-- the slump; the axe head on the ground
			time = 0.4,
			easing = "BackOut",
			joints = {
				Root = posRot(0.04, -1.1, 0.1, -18, 6, 2),
				Neck = rot(-28, 0, 0),
				RightHip = rot(-86, 0, 8),
				LeftHip = rot(50, 0, -8),
				RightShoulder = rot(-10, 0, 14),
				Weapon = rot(-84, 0, 0),
				LeftShoulder = rot(10, 0, -26),
			},
		},
		pant(0.8, true),
		pant(1.2, false),
		pant(1.6, true),
		pant(2.0, false),
		pant(2.4, true),
		pant(2.8, false),
		{
			time = 3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.04, -1.08, 0.1, -16, 6, 2),
				Neck = rot(-25, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.08, kind = "Voice", data = { name = "KoboldGroan" } },
		{ time = 0.42, kind = "Sfx", data = { name = "BreakKneel" } },
		{ time = 0.44, kind = "Sfx", data = { name = "AxeGround" } },
	},
}

return clip
