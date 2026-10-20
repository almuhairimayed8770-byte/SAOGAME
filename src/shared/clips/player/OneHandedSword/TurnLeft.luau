--!strict
--[[
	player/OneHandedSword/TurnLeft: turn in place to the left (section 10: at 45 degrees with no
	movement). The head and torso lead, the left foot lifts and plants outward, the right foot
	drags round, then the torso settles with a spring. The controller yaws the root over the clip.
	The sword rides low, the point forward.
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
	id = "player/OneHandedSword/TurnLeft",
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
				RightElbow = rot(16, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-28, 0, 0),
			},
		},
		{
			-- head and torso lead; left foot lifts
			time = 0.1,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.04, 0, 0, -8, 2),
				Waist = rot(-4, 18, 2),
				Neck = rot(3, 22, 0),
				LeftHip = rot(6, 24, -16),
				LeftKnee = rot(-36, 0, 0),
				LeftAnkle = rot(30, 0, 0),
				RightHip = rot(-2, -6, 3),
				RightKnee = rot(-12, 0, 0),
				RightAnkle = rot(14, 0, 0),
				LeftShoulder = rot(6, 0, -12),
				RightShoulder = rot(-4, 0, 8),
			},
		},
		{
			-- left foot plants, right foot drags round
			time = 0.24,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, 6, -1),
				Waist = rot(-4, -6, -1),
				Neck = rot(4, -4, 0),
				LeftHip = rot(4, 10, -8),
				LeftKnee = rot(-10, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(-6, -22, 10),
				RightKnee = rot(-24, 0, 0),
				RightAnkle = rot(28, 0, 0),
				LeftShoulder = rot(2, 0, -6),
				RightShoulder = rot(4, 0, 6),
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
		{ time = 0.25, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.38, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
