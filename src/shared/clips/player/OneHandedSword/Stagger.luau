--!strict
--[[
	player/OneHandedSword/Stagger: the 0.5 s stagger (combat.luau staggerDuration). Thrown back
	off the feet in 3 frames: torso and head back, arms flung up, a stumbling step with 1.5 studs
	of root motion back, then a BackOut catch of the balance and a spring into the ready stance.
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
	id = "player/OneHandedSword/Stagger",
	rig = "PlayerR15",
	duration = 0.5,
	loop = false,
	layer = "FullBody",
	priority = 30,
	blendIn = 0.02,
	blendOut = 0.15,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-8, -12, 0),
				Neck = rot(3, 12, 0),
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
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- thrown back
			time = 0.05,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.16, 0, 0, 0, 0),
				Waist = rot(28, 2, -4),
				Neck = rot(12, -6, 0),
				RightShoulder = rot(60, 0, 40),
				RightElbow = rot(40, 0, 0),
				RightWrist = rot(0, 0, 10),
				Weapon = rot(-40, 0, 10),
				LeftShoulder = rot(56, 0, -44),
				LeftElbow = rot(36, 0, 0),
				LeftHip = rot(30, 0, -8),
				LeftKnee = rot(-10, 0, 0),
				LeftAnkle = rot(-20, 0, 0),
				RightHip = rot(-24, 0, 10),
				RightKnee = rot(-34, 0, 0),
				RightAnkle = rot(58, 0, 0),
			},
			root = { pos = { 0, 0, 0.6 } },
		},
		{
			-- catching the balance on the back foot
			time = 0.25,
			easing = "BackOut",
			joints = {
				Root = posRot(0, -0.28, 0, 0, 0, 0),
				Waist = rot(6, -4, 2),
				Neck = rot(4, 4, 0),
				RightShoulder = rot(36, 0, 24),
				RightElbow = rot(44, 0, 0),
				LeftShoulder = rot(30, 0, -30),
				LeftElbow = rot(44, 0, 0),
				LeftHip = rot(20, 0, -8),
				LeftKnee = rot(-30, 0, 0),
				LeftAnkle = rot(10, 0, 0),
				RightHip = rot(-18, 0, 10),
				RightKnee = rot(-48, 0, 0),
				RightAnkle = rot(66, 0, 0),
			},
			root = { pos = { 0, 0, 1.5 } },
		},
		{
			-- ready again (the head 3 degrees lower than IdleDrawn's, clear of the sheathed hilt)
			time = 0.5,
			easing = "Spring",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-8, -12, 0),
				Neck = rot(3, 12, 0),
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
			root = { pos = { 0, 0, 1.5 } },
		},
	},
	events = {
		{ time = 0.26, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
