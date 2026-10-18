--!strict
--[[
	player/OneHandedSword/Idle: sheathed idle, the 12-second cycle (section 10 "Locomotion"). The
	sword rides on its sheath across the back (D-050), so both hands hang empty and relaxed at the
	sides, the elbows a little soft. A weight shift onto the left leg at 4.5 s, back at 7.5 s, a
	glance to the left at 10 s. Breathing rides on the Additive Breathe clip. The hilt sits just
	behind the head over the right shoulder, so the head never tips back more than a few degrees
	or turns to the right; the glance goes left, with the shoulders.
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
	id = "player/OneHandedSword/Idle",
	rig = "PlayerR15",
	duration = 12,
	loop = true,
	sheathed = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.2,
	blendOut = 0.2,
	keys = {
		{
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				Waist = rot(-3, 0, 0),
				Neck = rot(3, 0, 0),
				LeftShoulder = rot(3, 0, -4),
				LeftElbow = rot(8, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(3, 0, 4),
				RightElbow = rot(8, 0, 0),
				RightWrist = rot(0, 0, 0),
				LeftHip = rot(2, 0, -3),
				LeftKnee = rot(-6, 0, 0),
				LeftAnkle = rot(4, 0, 0),
				RightHip = rot(-2, 0, 3),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(8, 0, 0),
			},
		},
		{
			time = 4.5,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				Waist = rot(-3, 0, 0),
				Neck = rot(3, 0, 0),
			},
		},
		{
			-- weight shifts onto the left leg; hip drops to the right, torso counter-leans
			time = 5.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.12, -0.08, 0, 0, 0, -3),
				Waist = rot(-3, 4, 4),
				Neck = rot(2, -1, -2),
				LeftHip = rot(2, 0, -1),
				LeftKnee = rot(-3, 0, 0),
				LeftAnkle = rot(1, 0, 0),
				RightHip = rot(-2, 0, 8),
				RightKnee = rot(-14, 0, 0),
				RightAnkle = rot(16, 0, 0),
				RightShoulder = rot(3, 0, 6),
			},
		},
		{
			time = 7.5,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.12, -0.08, 0, 0, 0, -3),
				Waist = rot(-3, 4, 4),
			},
		},
		{
			time = 8.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				Waist = rot(-3, 0, 0),
				Neck = rot(3, 0, 0),
				LeftHip = rot(2, 0, -3),
				LeftKnee = rot(-6, 0, 0),
				LeftAnkle = rot(4, 0, 0),
				RightHip = rot(-2, 0, 3),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(8, 0, 0),
				RightShoulder = rot(3, 0, 4),
			},
		},
		{
			-- a glance to the left
			time = 10,
			easing = "SineInOut",
			joints = {
				Neck = rot(2, 10, 0),
				Waist = rot(-3, 6, 0),
			},
		},
		{
			time = 10.6,
			easing = "SineInOut",
			joints = {
				Neck = rot(2, 10, 0),
				Waist = rot(-3, 6, 0),
			},
		},
		{
			time = 11.4,
			easing = "SineInOut",
			joints = {
				Neck = rot(3, 0, 0),
				Waist = rot(-3, 0, 0),
			},
		},
	},
	events = {},
}

return clip
