--!strict
--[[
	player/OneHandedSword/Idle: sheathed idle, the 12-second cycle (section 10 "Locomotion").
	The sword hangs point-down beside the right leg. A weight shift onto the left leg at 4.5 s,
	back at 7.5 s, a glance to the right at 10 s. Breathing rides on the Additive Breathe clip.
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
				RightShoulder = rot(2, 0, 5),
				RightElbow = rot(6, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-80, 0, 0),
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
				Neck = rot(3, -4, -2),
				LeftHip = rot(2, 0, -1),
				LeftKnee = rot(-3, 0, 0),
				LeftAnkle = rot(1, 0, 0),
				RightHip = rot(-2, 0, 8),
				RightKnee = rot(-14, 0, 0),
				RightAnkle = rot(16, 0, 0),
				RightShoulder = rot(2, 0, 7),
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
				RightShoulder = rot(2, 0, 5),
			},
		},
		{
			-- a glance to the right
			time = 10,
			easing = "SineInOut",
			joints = {
				Neck = rot(2, -18, 0),
				Waist = rot(-3, -3, 0),
			},
		},
		{
			time = 10.6,
			easing = "SineInOut",
			joints = {
				Neck = rot(2, -18, 0),
				Waist = rot(-3, -3, 0),
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
