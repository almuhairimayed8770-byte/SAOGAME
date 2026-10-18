--!strict
--[[
	player/OneHandedSword/WalkForwardDrawn: the drawn set, the sword in the hand.
	8 studs/s walk, a 0.9 s cycle (two steps). Contact poses
	snap in with QuadOut so the plant reads; passing poses glide with SineInOut. The sword rides
	low with the point forward, the wrist easing it up as the arm swings back so the point stays
	clear of the grass, and the free arm counter-swings, short at the back so the hand stays in
	front of the scabbard. Footsteps just after each plant.
	Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/WalkForwardDrawn",
	rig = "PlayerR15",
	duration = 0.9,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left foot plants
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.06, 0, 0, 4, 0),
				Waist = rot(-4, -5, 1),
				Neck = rot(4, 1, 0),
				LeftHip = rot(22, 0, -3),
				LeftKnee = rot(-8, 0, 0),
				LeftAnkle = rot(-14, 0, 0),
				RightHip = rot(-18, 0, 3),
				RightKnee = rot(-12, 0, 0),
				RightAnkle = rot(30, 0, 0),
				LeftShoulder = rot(-7, 0, -7),
				LeftElbow = rot(12, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(18, 0, 5),
				RightElbow = rot(16, 0, 0),
				RightWrist = rot(-12, 0, 0),
				Weapon = rot(-22, 0, 0),
			},
		},
		{
			-- right leg passes under the body; the body rides high
			time = 0.225,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.03, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftHip = rot(4, 0, -3),
				LeftKnee = rot(-6, 0, 0),
				LeftAnkle = rot(2, 0, 0),
				RightHip = rot(2, 0, 3),
				RightKnee = rot(-52, 0, 0),
				RightAnkle = rot(28, 0, 0),
				LeftShoulder = rot(0, 0, -4),
				RightShoulder = rot(0, 0, 5),
				RightWrist = rot(-6, 0, 0),
			},
		},
		{
			-- right foot plants
			time = 0.45,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.06, 0, 0, -4, 0),
				Waist = rot(-4, 5, -1),
				Neck = rot(4, -1, 0),
				LeftHip = rot(-18, 0, -3),
				LeftKnee = rot(-12, 0, 0),
				LeftAnkle = rot(30, 0, 0),
				RightHip = rot(22, 0, 3),
				RightKnee = rot(-8, 0, 0),
				RightAnkle = rot(-14, 0, 0),
				LeftShoulder = rot(18, 0, -4),
				RightShoulder = rot(-18, 0, 5),
				RightWrist = rot(0, 0, 0),
			},
		},
		{
			-- left leg passes
			time = 0.675,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.03, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftHip = rot(2, 0, -3),
				LeftKnee = rot(-52, 0, 0),
				LeftAnkle = rot(28, 0, 0),
				RightHip = rot(4, 0, 3),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(2, 0, 0),
				LeftShoulder = rot(0, 0, -4),
				RightShoulder = rot(0, 0, 5),
				RightWrist = rot(-6, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.03, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.48, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
