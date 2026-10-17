--!strict
--[[
	enemy/Boar/Stagger: the 1.0 s parry stagger (combat.luau parryStagger). Reared up and back in
	4 frames with the front legs off the ground and the jaw open, a BackOut crash back down, a
	spring wobble, then a slow recovery into the idle stance.
	Rig: Boar. Root X+ pitches the nose up.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Boar/Stagger",
	rig = "Boar",
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
			-- reared up
			time = 0.07,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, 0.3, 0.4, 18, 0, 0),
				Neck = rot(26, 0, 0),
				Jaw = rot(-22, 0, 0),
				FrontLeftHip = rot(54, 0, 0),
				FrontRightHip = rot(50, 0, 0),
				BackLeftHip = rot(-12, 0, 0),
				BackRightHip = rot(-12, 0, 0),
				TailJoint = rot(-26, 0, 0),
			},
		},
		{
			time = 0.14,
			easing = "Hold",
			joints = {
				Root = posRot(0, 0.3, 0.4, 18, 0, 0),
			},
		},
		{
			-- crash down
			time = 0.4,
			easing = "BackOut",
			joints = {
				Root = posRot(0, -0.24, 0.2, -6, 0, 4),
				Neck = rot(-16, 6, 0),
				Jaw = rot(-6, 0, 0),
				FrontLeftHip = rot(-6, 0, 0),
				FrontRightHip = rot(4, 0, 0),
				BackLeftHip = rot(6, 0, 0),
				BackRightHip = rot(4, 0, 0),
				TailJoint = rot(10, 0, 0),
			},
		},
		{
			-- wobble
			time = 0.65,
			easing = "Spring",
			joints = {
				Root = posRot(0.06, -0.1, 0.1, -2, 4, -5),
				Neck = rot(-10, -8, 0),
				Jaw = rot(0, 0, 0),
			},
		},
		{
			time = 1.0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Neck = rot(-4, 0, 0),
				FrontLeftHip = rot(2, 0, 0),
				FrontRightHip = rot(-2, 0, 0),
				BackLeftHip = rot(-2, 0, 0),
				BackRightHip = rot(2, 0, 0),
				TailJoint = rot(4, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.05, kind = "Voice", data = { name = "enemy.ChargerStagger" } },
		{ time = 0.42, kind = "Footstep", data = { foot = "Both" } },
	},
}

return clip
