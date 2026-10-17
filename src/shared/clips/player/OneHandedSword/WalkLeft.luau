--!strict
--[[
	player/OneHandedSword/WalkLeft: side-step to the left, a 0.9 s cycle. The left leg reaches
	out, the right leg crosses behind; the torso leans a few degrees into the direction and the
	head stays on the target.
	Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left (a hanging left leg
	with Z- swings out to the left).
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/WalkLeft",
	rig = "PlayerR15",
	duration = 0.9,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left foot plants out to the left
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.06, 0, 0, 0, 3),
				Waist = rot(-3, 0, 4),
				Neck = rot(3, 0, -3),
				LeftHip = rot(2, 0, -22),
				LeftKnee = rot(-8, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(4, 0, 6),
				RightKnee = rot(-10, 0, 0),
				RightAnkle = rot(6, 0, 0),
				LeftShoulder = rot(4, 0, -14),
				LeftElbow = rot(12, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(2, 0, 4),
				RightElbow = rot(8, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-80, 0, 0),
			},
		},
		{
			-- right leg lifts and crosses behind
			time = 0.225,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, 0, 0, 0, 2),
				LeftHip = rot(0, 0, -8),
				LeftKnee = rot(-6, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(-8, 0, -12),
				RightKnee = rot(-45, 0, 0),
				RightAnkle = rot(30, 0, 0),
				LeftShoulder = rot(4, 0, -8),
			},
		},
		{
			-- right foot plants behind the left
			time = 0.45,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.06, 0, 0, 0, 3),
				LeftHip = rot(4, 0, 2),
				LeftKnee = rot(-10, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(-6, 0, -18),
				RightKnee = rot(-8, 0, 0),
				RightAnkle = rot(14, 0, 0),
				LeftShoulder = rot(4, 0, -10),
			},
		},
		{
			-- left leg lifts and reaches out again
			time = 0.675,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, 0, 0, 0, 2),
				LeftHip = rot(2, 0, -30),
				LeftKnee = rot(-34, 0, 0),
				LeftAnkle = rot(24, 0, 0),
				RightHip = rot(0, 0, -4),
				RightKnee = rot(-10, 0, 0),
				RightAnkle = rot(10, 0, 0),
				LeftShoulder = rot(4, 0, -16),
			},
		},
	},
	events = {
		{ time = 0.03, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.48, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
