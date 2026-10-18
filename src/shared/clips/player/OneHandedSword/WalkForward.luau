--!strict
--[[
	player/OneHandedSword/WalkForward: the sheathed set, the sword on the back.
	An easy walk, a 0.9 s cycle with the same plants as WalkForwardDrawn. Heel strike, roll to
	the toe, the arms swinging loose and empty against the legs, the body rising over each
	planted foot. The arms swing well forward and only a little back, so the left hand passes in
	front of the scabbard. The planted foot stays put at 3.5 studs/s of ground speed (an easy stride on these
	legs); faster walks are carried by the run blend.
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
	id = "player/OneHandedSword/WalkForward",
	rig = "PlayerR15",
	duration = 0.9,
	loop = true,
	sheathed = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left heel strikes, the right arm forward
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.085, 0, -2, -4, 0),
				Waist = rot(0, 6, 0),
				Neck = rot(2, -2, 0),
				LeftHip = rot(35.5, 3.6, -1.2),
				LeftKnee = rot(-16.1, 0, 0),
				LeftAnkle = rot(-3.4, 0, -1.2),
				RightHip = rot(-0.9, 3.8, -1.1),
				RightKnee = rot(-30, 0, 0),
				RightAnkle = rot(22.9, 0, 1.2),
				LeftShoulder = rot(-7, 0, -7),
				LeftElbow = rot(9, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(20, 0, 6),
				RightElbow = rot(19, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.1125,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.0283, -0.06, 0, -2, -2.8, 1.4),
				Waist = rot(0, 4.2, -1.4),
				Neck = rot(2, -1.4, 0),
				LeftHip = rot(22.6, 2.8, -0.4),
				LeftKnee = rot(-10.5, 0, 0),
				LeftAnkle = rot(-9.9, 0, -2.1),
				RightHip = rot(-1.7, 2.6, -1.6),
				RightKnee = rot(-40.8, 0, 0),
				RightAnkle = rot(4.6, 0, 0.4),
				LeftShoulder = rot(-3, 0, -7),
				LeftElbow = rot(10.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(15, 0, 5.3),
				RightElbow = rot(17.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			-- passing: the body high over the left foot, the right leg swinging through
			time = 0.225,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.04, -0.035, 0, -2, 0, 2),
				Waist = rot(0, 0, -2),
				Neck = rot(2, 0, 0),
				LeftHip = rot(18.9, 0.1, 0.5),
				LeftKnee = rot(-25.3, 0, 0),
				LeftAnkle = rot(8.3, 0, -2.5),
				RightHip = rot(4, 0.5, -0.7),
				RightKnee = rot(-62, 0, 0),
				RightAnkle = rot(30, 0, 0.6),
				LeftShoulder = rot(5, 0, -7),
				LeftElbow = rot(14, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(5, 0, 5),
				RightElbow = rot(14, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.3375,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.0283, -0.06, 0, -2, 2.8, 1.4),
				Waist = rot(0, -4.2, -1.4),
				Neck = rot(2, 1.4, 0),
				LeftHip = rot(8.1, -2.7, 1.1),
				LeftKnee = rot(-26.8, 0, 0),
				LeftAnkle = rot(20.6, 0, -2.1),
				RightHip = rot(32, -1.5, 0.2),
				RightKnee = rot(-52, 0, 0),
				RightAnkle = rot(24, 0, 0.9),
				LeftShoulder = rot(15, 0, -6.7),
				LeftElbow = rot(17.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(-3, 0, 6),
				RightElbow = rot(10.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			-- right heel strikes, the left arm forward
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.085, 0, -2, 4, 0),
				Waist = rot(0, -6, 0),
				Neck = rot(2, 2, 0),
				LeftHip = rot(-0.9, -3.8, 1.1),
				LeftKnee = rot(-30, 0, 0),
				LeftAnkle = rot(22.9, 0, -1.2),
				RightHip = rot(35.5, -3.6, 1.2),
				RightKnee = rot(-16.1, 0, 0),
				RightAnkle = rot(-3.4, 0, 1.2),
				LeftShoulder = rot(20, 0, -6),
				LeftElbow = rot(19, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(-7, 0, 7),
				RightElbow = rot(9, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.5625,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.0283, -0.06, 0, -2, 2.8, -1.4),
				Waist = rot(0, -4.2, 1.4),
				Neck = rot(2, 1.4, 0),
				LeftHip = rot(-1.7, -2.6, 1.6),
				LeftKnee = rot(-40.8, 0, 0),
				LeftAnkle = rot(4.6, 0, -0.4),
				RightHip = rot(22.6, -2.8, 0.4),
				RightKnee = rot(-10.6, 0, 0),
				RightAnkle = rot(-9.9, 0, 2.1),
				LeftShoulder = rot(15, 0, -5.3),
				LeftElbow = rot(17.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(-3, 0, 7),
				RightElbow = rot(10.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			-- passing: the body high over the right foot, the left leg swinging through
			time = 0.675,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.04, -0.035, 0, -2, 0, -2),
				Waist = rot(0, 0, 2),
				Neck = rot(2, 0, 0),
				LeftHip = rot(4, -0.5, 0.7),
				LeftKnee = rot(-62, 0, 0),
				LeftAnkle = rot(30, 0, -0.6),
				RightHip = rot(18.9, -0.1, -0.5),
				RightKnee = rot(-25.3, 0, 0),
				RightAnkle = rot(8.3, 0, 2.5),
				LeftShoulder = rot(5, 0, -5),
				LeftElbow = rot(14, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(5, 0, 7),
				RightElbow = rot(14, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
		{
			time = 0.7875,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.0283, -0.06, 0, -2, -2.8, -1.4),
				Waist = rot(0, 4.2, 1.4),
				Neck = rot(2, -1.4, 0),
				LeftHip = rot(32, 1.5, -0.2),
				LeftKnee = rot(-52, 0, 0),
				LeftAnkle = rot(24, 0, -0.9),
				RightHip = rot(8.1, 2.7, -1.1),
				RightKnee = rot(-26.8, 0, 0),
				RightAnkle = rot(20.6, 0, 2.1),
				LeftShoulder = rot(-3, 0, -6),
				LeftElbow = rot(10.5, 0, 0),
				LeftWrist = rot(-4, 0, 0),
				RightShoulder = rot(15, 0, 6.7),
				RightElbow = rot(17.5, 0, 0),
				RightWrist = rot(-4, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.03, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.48, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
