--!strict
--[[
	enemy/Boar/Idle: the Frenzy Boar at rest, a 4 s loop with breathing baked in (the chest
	rises on its legs, the head bobs), two tail swishes, a snort with the jaw at 2.2 s and a weight
	shift at 2 s. Rig: Boar (rigs.luau). Head forward of the Neck joint: Neck X- lowers the head.
	Legs hang from the hips: Hip X+ swings a leg forward. Tail: X- lifts it.
	The breath (1.0 s and 3.2 s) lifts the body 0.05 and 0.04 on the Root joint and tips it 1 degree
	nose up, and every hip takes that back: the leg drawn down out of the body and turned back by
	what the body rose and tipped at its hip (the front hips 0.074 and 0.064, the back 0.025 and
	0.015, slid 0.018 along), so the hooves stand where they stood (D-622). Riding the Root alone,
	the breath lifted the front hooves 0.068 off the field at 1.0 s and 0.058 at 3.2 s.
	The weight shift (2.0-2.6 s) slides the body 0.08 onto its left legs and rolls it 1 degree,
	the hips rolled back the same so the stiff legs hang straight, the body lifted 0.015 so the
	low side's hooves stay on the field, and the front right leg drawn back: every hoof's lowest
	corner within 0.02 of the field through it (D-601). Rolled 2 degrees with the front left leg
	reaching 4 degrees forward, it put that hoof 0.067 into the field (the back left 0.057), which
	showed under the Charge's crouch and in ClipLab's blend out of the Stagger.
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
			-- breath in, tail swish: the chest rises on its legs
			time = 1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.05, 0, 1, 0, 0),
				Neck = rot(-2, 3, 0),
				FrontLeftHip = posRot(0, -0.0743, 0.0185, 1, 0, 0),
				FrontRightHip = posRot(0, -0.0743, 0.0185, -3, 0, 0),
				BackLeftHip = posRot(0, -0.0254, 0.0181, -3, 0, 0),
				BackRightHip = posRot(0, -0.0254, 0.0181, 1, 0, 0),
				TailJoint = rot(0, 18, 0),
			},
		},
		{
			-- weight shift onto the left legs, the hips rolled back under the body's roll
			time = 2,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.08, 0.015, 0, 0, 0, 1),
				Neck = rot(-5, -4, 0),
				FrontLeftHip = rot(2, 0, -1),
				FrontRightHip = rot(-6, 0, -1),
				BackLeftHip = rot(-2, 0, -1),
				BackRightHip = rot(2, 0, -1),
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
				FrontLeftHip = posRot(0, -0.0643, 0.0184, 1, 0, 0),
				FrontRightHip = posRot(0, -0.0643, 0.0184, -3, 0, 0),
				BackLeftHip = posRot(0, -0.0154, 0.0179, -3, 0, 0),
				BackRightHip = posRot(0, -0.0154, 0.0179, 1, 0, 0),
				TailJoint = rot(2, 10, 0),
			},
		},
	},
	events = {
		{ time = 2.2, kind = "Sfx", data = { name = "enemy.ChargerSnort" } },
	},
}

return clip
