--!strict
--[[
	player/OneHandedSword/IdleDrawn: drawn idle, the 12-second cycle. Low stance, left foot
	forward, blade low and forward, free hand open. Weight shifts at 3 s and 9 s and a blade
	re-grip at 6 s (the wrist rolls, the point dips and comes back up).
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
	id = "player/OneHandedSword/IdleDrawn",
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
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-8, -12, 0),
				Neck = rot(6, 12, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
				LeftHip = rot(15, 0, -6),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(5, 0, 0),
				RightHip = rot(-10, 0, 6),
				RightKnee = rot(-25, 0, 0),
				RightAnkle = rot(35, 0, 0),
			},
		},
		{
			-- weight eases onto the rear (right) leg
			time = 3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.08, -0.15, 0.06, 0, 0, 2),
				Waist = rot(-6, -15, -2),
				Neck = rot(5, 15, 1),
				LeftKnee = rot(-12, 0, 0),
				LeftAnkle = rot(-3, 0, 0),
				RightKnee = rot(-32, 0, 0),
				RightAnkle = rot(42, 0, 0),
			},
		},
		{
			time = 5.4,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.08, -0.15, 0.06, 0, 0, 2),
			},
		},
		{
			-- re-grip: the wrist rolls, the point dips
			time = 5.9,
			easing = "QuadOut",
			joints = {
				RightWrist = rot(-35, 0, -12),
				Weapon = rot(-62, 0, -6),
				RightElbow = rot(40, 0, 0),
			},
		},
		{
			time = 6.25,
			easing = "BackOut",
			joints = {
				RightWrist = rot(-22, 0, 4),
				Weapon = rot(-46, 0, 2),
				RightElbow = rot(33, 0, 0),
			},
		},
		{
			time = 6.7,
			easing = "Spring",
			joints = {
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				RightElbow = rot(35, 0, 0),
			},
		},
		{
			-- weight returns forward onto the left foot
			time = 9,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.04, -0.12, -0.04, 0, 0, -1),
				Waist = rot(-9, -10, 1),
				Neck = rot(7, 10, 0),
				LeftKnee = rot(-24, 0, 0),
				LeftAnkle = rot(9, 0, 0),
				RightKnee = rot(-22, 0, 0),
				RightAnkle = rot(32, 0, 0),
			},
		},
		{
			time = 11.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.04, -0.12, -0.04, 0, 0, -1),
				Waist = rot(-9, -10, 1),
			},
		},
	},
	events = {},
}

return clip
