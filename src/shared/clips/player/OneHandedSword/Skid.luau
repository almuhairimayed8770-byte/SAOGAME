--!strict
--[[
	player/OneHandedSword/Skid: the stop above run speed. Brakes in 9 frames (QuadOut) after a
	0.1 s blend in: the torso leans back, the front (left) leg, already reaching forward in the
	run, shoots out onto its heel, toe up, the right leg folds under behind on its toe, the arms
	fly back (the wrist keeps the point up off the grass), the body drops; the heel's scrape sounds
	as it meets the field. An eased settle into the ready stance (QuadIn, then QuadOut through
	0.385, where both feet are drawn in on the field). The controller decelerates the root; the
	clip carries no root motion.
	Re-key (D-383): the brake was on the right foot, which swung 90 degrees from behind the body to
	the front in 5 frames (48 in the first) and back through the field into the stance (0.24 under
	it); the Spring settle put 38% of it into one frame; the carried arms start 30% of the way to
	the guard, so the blend in from a stance does not fling them.
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
	blendIn = 0.1,
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
				LeftHip = rot(32.3, -0.2, -3.2),
				LeftKnee = rot(-24.1, 0, 0),
				LeftAnkle = rot(-8.2, -0.1, 2.8),
				RightHip = rot(-20, 0, 3),
				RightKnee = rot(-30, 0, 0),
				RightAnkle = rot(40, 0, 0),
				LeftShoulder = rot(-6.5, 0, -8.7),
				LeftElbow = rot(64, 0, 0),
				LeftWrist = rot(0, 0, 3),
				RightShoulder = rot(23, 0, 8.6),
				RightElbow = rot(52.5, 0, 0),
				RightWrist = rot(-14.5, 0, 0),
				Weapon = rot(-71, 0, 0),
			},
		},
		{
			-- brake
			time = 0.15,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.3, 0, 0, 0, 0),
				Waist = rot(18, 0, 3),
				Neck = rot(-12, 0, 0),
				RightHip = rot(36.7, 4.3, 7.1),
				RightKnee = rot(-86.4, 0, 0),
				RightAnkle = rot(9.7, 6.7, -5.2),
				LeftHip = rot(47.1, -0.2, -6.3),
				LeftKnee = rot(-18.5, 0, 0),
				LeftAnkle = rot(-13.8, 1, 4.3),
				LeftShoulder = rot(-40, 0, -24),
				LeftElbow = rot(20, 0, 0),
				RightShoulder = rot(-36, 0, 26),
				RightElbow = rot(22, 0, 0),
				Weapon = rot(-16, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightWrist = rot(-10, 0, 0),
			},
		},
		{
			time = 0.27,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.32, 0, 0, 0, 0),
				Waist = rot(14, 0, 2),
				Neck = rot(-8, 0, 0),
				LeftAnkle = rot(-11.7, 0.9, 4.4),
				LeftHip = rot(50.3, -0.5, -6.3),
				LeftKnee = rot(-23.7, 0, 0),
				RightAnkle = rot(10.7, 6.8, -5.3),
				RightHip = rot(37.5, 4.5, 7.1),
				RightKnee = rot(-88.1, 0, 0),
			},
		},
		{
			time = 0.385,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(8.5, 0.3, 2.6),
				LeftElbow = rot(25, 0, 0),
				LeftHip = rot(48.8, -2.2, -6.3),
				LeftKnee = rot(-50, 0, 0),
				LeftShoulder = rot(-15, 0, -17),
				Neck = rot(-2.5, 3, 0),
				RightAnkle = rot(28, 3.4, -3.2),
				RightElbow = rot(21, 0, 0),
				RightHip = rot(21.2, 3.3, 6.7),
				RightKnee = rot(-69.2, 0, 0),
				RightShoulder = rot(-14, 0, 17),
				Root = posRot(0, -0.22, 0, 0, 0, 0),
				Waist = rot(4, -3, 1),
				Weapon = rot(-25, 0, 0),
			},
		},
		{
			-- settle into the ready stance, the head low enough to clear the sheathed hilt
			time = 0.5,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-6, -6, 0),
				Neck = rot(3, 6, 0),
				RightHip = rot(-6.8, 0.1, 6),
				RightKnee = rot(-24.5, 0, 0),
				RightAnkle = rot(31.3, 0, 0),
				LeftHip = rot(27.8, -1.6, -6.2),
				LeftKnee = rot(-45.6, 0, 0),
				LeftAnkle = rot(17.7, 0, 0.4),
				LeftShoulder = rot(10, 0, -10),
				LeftElbow = rot(30, 0, 0),
				RightShoulder = rot(8, 0, 8),
				RightElbow = rot(20, 0, 0),
				Weapon = rot(-34, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.09, kind = "Sfx", data = { name = "footsteps.LandSoft" } },
	},
}

return clip
