--!strict
--[[
	player/OneHandedSword/TurnRightDraw: turn in place to the right from the sheathed stance into the
	drawn one, for a lock-on that draws the sword under the turn (D-640). From the sheathed stance
	the right foot steps in under the body onto its ball, the inner corner of its ball on the
	root's axis as the drawn turn sets it (Footstep), while the hips sink to the drawn stance's
	height over the left foot, its leg solved at every key to hold it where the sheathed stance
	has it. The left foot lifts off as the sheathed turn lifts it, is carried round off the ground
	and plants forward, where the drawn stance has it (Footstep); then the right foot steps back
	onto its ball (Footstep): from 0.3 s the legs are TurnRightDrawn's. Each foot moves only while
	it is off the ground. Locomotion's turn plant brings the hips round between the first two
	Footsteps (TurnPlant); the Base set stands sheathed until this clip shows at full weight and
	turns to the drawn set under it. The upper body is the sheathed turn's: the Draw plays once
	the turn has gone.
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
	id = "player/OneHandedSword/TurnRightDraw",
	rig = "PlayerR15",
	duration = 0.5,
	loop = false,
	layer = "FullBody",
	priority = 5,
	blendIn = 0.08,
	blendOut = 0.15,
	keys = {
		{
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftShoulder = rot(3, 0, -5),
				LeftElbow = rot(10, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(2, 0, 5),
				RightElbow = rot(16, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-32, 0, 0),
				LeftHip = rot(12.3, -0.6, -3.2),
				LeftKnee = rot(-25.6, 0, 0),
				LeftAnkle = rot(13.2, 0, 3.2),
				RightHip = rot(7.1, 0.5, 3.2),
				RightKnee = rot(-23.4, 0, 0),
				RightAnkle = rot(16.3, 0, -3.2),
			},
		},
		{
			time = 0.04,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.09, 0, 0, 0, 0),
				LeftHip = rot(17.2, -0.9, -3.2),
				LeftKnee = rot(-34.9, 0, 0),
				LeftAnkle = rot(17.6, 0, 3.3),
				RightHip = rot(25.7, 1.7, 3.2),
				RightKnee = rot(-59.5, 0, 0),
				RightAnkle = rot(33.8, 0, -3.6),
			},
		},
		{
			time = 0.075,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.13, 0, 0, 0, 0),
				LeftHip = rot(21.1, -1.1, -3.2),
				LeftKnee = rot(-42.3, 0, 0),
				LeftAnkle = rot(21.1, 0, 3.3),
				RightHip = rot(9.1, 0.9, -0.8),
				RightKnee = rot(-46.6, 0, 0),
				RightAnkle = rot(37.4, 0, 0.7),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				Neck = rot(4, -10, 0),
				LeftHip = rot(22.8, -1.2, -3.2),
				LeftKnee = rot(-45.5, 0, 0),
				LeftAnkle = rot(22.6, 0, 3.4),
				RightHip = rot(7.6, 0.9, -1.2),
				RightKnee = rot(-43.3, 0, 0),
				RightAnkle = rot(35.7, 0, 6.9),
			},
		},
		{
			time = 0.13,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				LeftHip = rot(34.5, -2.6, -2.8),
				LeftKnee = rot(-66.2, 0, 0),
				LeftAnkle = rot(21.6, 0, 3.9),
				RightHip = rot(7.6, 0.9, -1.2),
				RightKnee = rot(-43.3, 0, 0),
				RightAnkle = rot(35.7, 0, 6.9),
			},
		},
		{
			time = 0.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				LeftHip = rot(37.5, -4, -6),
				LeftKnee = rot(-60.6, 0, 0),
				LeftAnkle = rot(14.8, 0, 7.2),
				RightHip = rot(7.6, 0.9, -1.2),
				RightKnee = rot(-43.3, 0, 0),
				RightAnkle = rot(35.7, 0, 6.9),
			},
		},
		{
			time = 0.335,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.144, 0, 0, 0, 0),
				LeftHip = rot(30.4, -2.1, -6.5),
				LeftKnee = rot(-48.6, 0, 0),
				LeftAnkle = rot(17.9, 0, 6.7),
				RightHip = rot(7.2, 0.9, -1.1),
				RightKnee = rot(-42.4, 0, 0),
				RightAnkle = rot(35.2, 0, 6.9),
			},
		},
		{
			time = 0.36,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.138, 0, 0, 0, 0),
				Neck = rot(4, -10, 0),
				LeftHip = rot(26.4, -1.5, -6.5),
				LeftKnee = rot(-41.3, 0, 0),
				LeftAnkle = rot(14.6, 0, 6.5),
				RightHip = rot(6.7, 0.9, -1.1),
				RightKnee = rot(-41.4, 0, 0),
				RightAnkle = rot(34.7, 0, 6.9),
			},
		},
		{
			time = 0.38,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.135, 0, 0, 0, 0),
				LeftHip = rot(26.2, -1.5, -6.5),
				LeftKnee = rot(-40.8, 0, 0),
				LeftAnkle = rot(14.4, 0, 6.5),
				RightHip = rot(17.6, -0.9, -2.7),
				RightKnee = rot(-60.2, 0, 0),
				RightAnkle = rot(33.8, 0, 17),
			},
		},
		{
			time = 0.395,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.133, 0, 0, 0, 0),
				LeftHip = rot(26, -1.5, -6.5),
				LeftKnee = rot(-40.5, 0, 0),
				LeftAnkle = rot(14.3, 0, 6.4),
				RightHip = rot(20.6, -1.1, -2.7),
				RightKnee = rot(-66.7, 0, 0),
				RightAnkle = rot(37.3, 0, 17.1),
			},
		},
		{
			time = 0.415,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.132, 0, 0, 0, 0),
				LeftHip = rot(25.9, -1.5, -6.5),
				LeftKnee = rot(-40.3, 0, 0),
				LeftAnkle = rot(14.2, 0, 6.4),
				RightHip = rot(4.1, 1.3, 3.6),
				RightKnee = rot(-47.4, 0, 0),
				RightAnkle = rot(43.4, 0, -3.7),
			},
		},
		{
			time = 0.44,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.126, 0, 0, 0, 0),
				LeftHip = rot(25.3, -1.4, -6.5),
				LeftKnee = rot(-39.2, 0, 0),
				LeftAnkle = rot(13.7, 0, 6.4),
				RightHip = rot(-9.1, 0, 6.4),
				RightKnee = rot(-26.9, 0, 0),
				RightAnkle = rot(36, 0, -6.3),
			},
		},
		{
			time = 0.46,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				LeftHip = rot(24.7, -1.3, -6.5),
				LeftKnee = rot(-38.1, 0, 0),
				LeftAnkle = rot(13.2, 0, 6.4),
				RightHip = rot(-16.5, -0.6, 5.8),
				RightKnee = rot(-11.8, 0, 0),
				RightAnkle = rot(28.4, 0, 0.1),
			},
		},
		{
			time = 0.5,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftShoulder = rot(3, 0, -5),
				LeftElbow = rot(10, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(2, 0, 5),
				RightElbow = rot(16, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-32, 0, 0),
				LeftHip = rot(24.7, -1.3, -6.5),
				LeftKnee = rot(-38.1, 0, 0),
				LeftAnkle = rot(13.2, 0, 6.4),
				RightHip = rot(-16.5, -0.6, 5.8),
				RightKnee = rot(-11.8, 0, 0),
				RightAnkle = rot(28.4, 0, 0.1),
			},
		},
	},
	events = {
		{ time = 0.1, kind = "Footstep", data = { foot = "Right" } },
		{ time = 0.36, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.46, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
