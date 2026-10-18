--!strict
--[[
	player/OneHandedSword/WalkRight: side-step to the right, a 0.9 s cycle; the mirror of
	WalkLeft. The right (sword) leg reaches out, the left leg crosses behind, the torso leans
	into the direction, the head stays on the target. The sword rides low, the point forward.
	Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left (a hanging right leg
	with Z+ swings out to the right).
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/WalkRight",
	rig = "PlayerR15",
	duration = 0.9,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- right foot plants out to the right
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.06, 0, 0, 0, -3),
				Waist = rot(-3, 0, -4),
				Neck = rot(3, 0, 3),
				RightHip = rot(2, 0, 22),
				RightKnee = rot(-8, 0, 0),
				RightAnkle = rot(6, 0, 0),
				LeftHip = rot(4, 0, -6),
				LeftKnee = rot(-10, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightShoulder = rot(4, 0, 14),
				RightElbow = rot(16, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-34, 0, 0),
				LeftShoulder = rot(2, 0, -4),
				LeftElbow = rot(8, 0, 0),
				LeftWrist = rot(0, 0, 0),
			},
		},
		{
			-- left leg lifts and crosses behind
			time = 0.225,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, 0, 0, 0, -2),
				RightHip = rot(0, 0, 8),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(6, 0, 0),
				LeftHip = rot(-8, 0, 12),
				LeftKnee = rot(-45, 0, 0),
				LeftAnkle = rot(30, 0, 0),
				RightShoulder = rot(4, 0, 8),
			},
		},
		{
			-- left foot plants behind the right
			time = 0.45,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.06, 0, 0, 0, -3),
				RightHip = rot(4, 0, -2),
				RightKnee = rot(-10, 0, 0),
				RightAnkle = rot(6, 0, 0),
				LeftHip = rot(-6, 0, 18),
				LeftKnee = rot(-8, 0, 0),
				LeftAnkle = rot(14, 0, 0),
				RightShoulder = rot(4, 0, 10),
			},
		},
		{
			-- right leg lifts and reaches out again
			time = 0.675,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, 0, 0, 0, -2),
				RightHip = rot(2, 0, 30),
				RightKnee = rot(-34, 0, 0),
				RightAnkle = rot(24, 0, 0),
				LeftHip = rot(0, 0, 4),
				LeftKnee = rot(-10, 0, 0),
				LeftAnkle = rot(10, 0, 0),
				RightShoulder = rot(4, 0, 16),
			},
		},
	},
	events = {
		{ time = 0.03, kind = "Footstep", data = { foot = "Right" } },
		{ time = 0.48, kind = "Footstep", data = { foot = "Left" } },
	},
}

return clip
