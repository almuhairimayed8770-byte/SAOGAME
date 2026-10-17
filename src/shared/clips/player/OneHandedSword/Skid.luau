--!strict
--[[
	player/OneHandedSword/Skid: the stop above run speed. Brakes in 5 frames: the torso leans
	back, the right leg shoots forward flat-footed, the left leg folds under, the arms fly back,
	the body drops. A long spring settle into the ready stance. The controller decelerates the
	root; the clip carries no root motion.
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
	id = "player/OneHandedSword/Skid",
	rig = "PlayerR15",
	duration = 0.5,
	loop = false,
	layer = "FullBody",
	priority = 6,
	blendIn = 0.05,
	blendOut = 0.15,
	keys = {
		{
			-- still running
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.1, 0, 0, 0, 0),
				Waist = rot(-16, 0, 0),
				Neck = rot(12, 0, 0),
				LeftHip = rot(30, 0, -3),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(-10, 0, 0),
				RightHip = rot(-20, 0, 3),
				RightKnee = rot(-30, 0, 0),
				RightAnkle = rot(40, 0, 0),
				LeftShoulder = rot(-20, 0, -6),
				LeftElbow = rot(70, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(20, 0, 8),
				RightElbow = rot(60, 0, 0),
				RightWrist = rot(-10, 0, 0),
				Weapon = rot(-80, 0, 0),
			},
		},
		{
			-- brake
			time = 0.08,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.3, 0, 0, 0, 0),
				Waist = rot(18, 0, -3),
				Neck = rot(-12, 0, 0),
				RightHip = rot(46, 0, 6),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(-40, 0, 0),
				LeftHip = rot(12, 0, -6),
				LeftKnee = rot(-56, 0, 0),
				LeftAnkle = rot(44, 0, 0),
				LeftShoulder = rot(-40, 0, -24),
				LeftElbow = rot(20, 0, 0),
				RightShoulder = rot(-36, 0, 26),
				RightElbow = rot(22, 0, 0),
				Weapon = rot(-70, 0, 0),
			},
		},
		{
			time = 0.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.32, 0, 0, 0, 0),
				Waist = rot(14, 0, -2),
				Neck = rot(-8, 0, 0),
			},
		},
		{
			-- settle into the ready stance
			time = 0.5,
			easing = "Spring",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-6, -6, 0),
				Neck = rot(5, 6, 0),
				RightHip = rot(-8, 0, 6),
				RightKnee = rot(-22, 0, 0),
				RightAnkle = rot(30, 0, 0),
				LeftHip = rot(14, 0, -6),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				LeftShoulder = rot(10, 0, -10),
				LeftElbow = rot(30, 0, 0),
				RightShoulder = rot(8, 0, 8),
				RightElbow = rot(20, 0, 0),
				Weapon = rot(-80, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.06, kind = "Sfx", data = { name = "Skid" } },
	},
}

return clip
