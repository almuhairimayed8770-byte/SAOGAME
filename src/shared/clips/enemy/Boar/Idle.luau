--!strict
--[[
	enemy/Boar/Idle: the Frenzy Boar at rest, a 4 s loop with breathing baked in (the chest
	rises on the Root joint, the head bobs), two tail swishes, a snort with the jaw at 2.2 s and
	a weight shift at 2 s. Rig: Boar (rigs.luau). Head forward of the Neck joint: Neck X- lowers
	the head. Legs hang from the hips: Hip X+ swings a leg forward. Tail: X- lifts it.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Boar/Idle",
	rig = "Boar",
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
				Root = posRot(0, 0, 0, 0, 0, 0),
				Neck = rot(-4, 0, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(2, 0, 0),
				FrontRightHip = rot(-2, 0, 0),
				BackLeftHip = rot(-2, 0, 0),
				BackRightHip = rot(2, 0, 0),
				TailJoint = rot(4, 0, 0),
			},
		},
		{
			-- breath in, tail swish
			time = 1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.05, 0, 1, 0, 0),
				Neck = rot(-2, 3, 0),
				TailJoint = rot(0, 18, 0),
			},
		},
		{
			-- weight shift onto the left legs
			time = 2,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.08, 0, 0, 0, 0, 2),
				Neck = rot(-5, -4, 0),
				FrontLeftHip = rot(4, 0, 0),
				FrontRightHip = rot(-6, 0, 0),
				TailJoint = rot(6, -14, 0),
			},
		},
		{
			-- snort
			time = 2.2,
			easing = "ExpoOut",
			joints = {
				Neck = rot(-14, -4, 0),
				Jaw = rot(-10, 0, 0),
			},
		},
		{
			time = 2.6,
			easing = "BackOut",
			joints = {
				Neck = rot(-3, 2, 0),
				Jaw = rot(0, 0, 0),
			},
		},
		{
			time = 3.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.04, 0, 1, 0, 0),
				FrontLeftHip = rot(2, 0, 0),
				FrontRightHip = rot(-2, 0, 0),
				TailJoint = rot(2, 10, 0),
			},
		},
	},
	events = {
		{ time = 2.2, kind = "Sfx", data = { name = "BoarSnort" } },
	},
}

return clip
