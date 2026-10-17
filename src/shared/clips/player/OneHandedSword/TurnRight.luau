--!strict
--[[
	player/OneHandedSword/TurnRight: turn in place to the right; the mirror of TurnLeft. The
	head and torso lead, the right foot lifts and plants outward, the left foot drags round.
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
	id = "player/OneHandedSword/TurnRight",
	rig = "PlayerR15",
	duration = 0.4,
	loop = false,
	layer = "FullBody",
	priority = 5,
	blendIn = 0.08,
	blendOut = 0.15,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.06, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftHip = rot(2, 0, -3),
				LeftKnee = rot(-8, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(-2, 0, 3),
				RightKnee = rot(-8, 0, 0),
				RightAnkle = rot(10, 0, 0),
				LeftShoulder = rot(3, 0, -5),
				LeftElbow = rot(10, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(2, 0, 5),
				RightElbow = rot(8, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-80, 0, 0),
			},
		},
		{
			time = 0.1,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.04, 0, 0, 8, -2),
				Waist = rot(-4, -18, -2),
				Neck = rot(4, -22, 0),
				RightHip = rot(6, -24, 16),
				RightKnee = rot(-36, 0, 0),
				RightAnkle = rot(30, 0, 0),
				LeftHip = rot(-2, 6, -3),
				LeftKnee = rot(-12, 0, 0),
				LeftAnkle = rot(14, 0, 0),
				RightShoulder = rot(6, 0, 12),
				LeftShoulder = rot(-4, 0, -8),
			},
		},
		{
			time = 0.24,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, -6, 1),
				Waist = rot(-4, 6, 1),
				Neck = rot(4, 4, 0),
				RightHip = rot(4, -10, 8),
				RightKnee = rot(-10, 0, 0),
				RightAnkle = rot(6, 0, 0),
				LeftHip = rot(-6, 22, -10),
				LeftKnee = rot(-24, 0, 0),
				LeftAnkle = rot(28, 0, 0),
				RightShoulder = rot(2, 0, 6),
				LeftShoulder = rot(4, 0, -6),
			},
		},
		{
			time = 0.4,
			easing = "Spring",
			joints = {
				Root = posRot(0, -0.06, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftHip = rot(2, 0, -3),
				LeftKnee = rot(-8, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(-2, 0, 3),
				RightKnee = rot(-8, 0, 0),
				RightAnkle = rot(10, 0, 0),
				LeftShoulder = rot(3, 0, -5),
				RightShoulder = rot(2, 0, 5),
			},
		},
	},
	events = {
		{ time = 0.25, kind = "Footstep", data = { foot = "Right" } },
		{ time = 0.38, kind = "Footstep", data = { foot = "Left" } },
	},
}

return clip
