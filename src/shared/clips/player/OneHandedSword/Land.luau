--!strict
--[[
	player/OneHandedSword/Land: landing squash. Contact after a 5-frame blend in, a 5-frame drop
	(QuadOut) into a deep crouch with the arms thrown forward and out (the point stays up off the
	grass), a short hold, then an eased rise tall (QuadOut) and a settle (SineInOut). The feet land
	on places between the drawn and the sheathed stance's and stay planted on them; the right foot's
	last key leaves the field by a hair, as the drawn idle holds it. The locomotion layer scales
	this clip's weight by fall height.
	Re-key (D-384): the ExpoOut threw the hips 0.4 down in one frame and the BackOut rise put 30%
	of its turn into one; both feet sank 0.2 in the squash and the right foot drifted 0.69 handing
	back to a stance; the contact's arms start 60% of the way to the guard.
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
	id = "player/OneHandedSword/Land",
	rig = "PlayerR15",
	duration = 0.45,
	loop = false,
	layer = "FullBody",
	priority = 6,
	blendIn = 0.08,
	blendOut = 0.15,
	keys = {
		{
			-- contact: legs reaching for the ground
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				Waist = rot(-6, 0, 0),
				Neck = rot(6, 0, 0),
				LeftHip = rot(13.9, 0.3, -4.8),
				LeftKnee = rot(-23.1, 0, 0),
				LeftAnkle = rot(9.2, -0.4, 4.6),
				RightHip = rot(-13.5, -2.8, 4.2),
				RightKnee = rot(0, 0, 0),
				RightAnkle = rot(13.8, 2.7, -4.8),
				LeftShoulder = rot(23, 0, -21),
				LeftElbow = rot(38, 0, 0),
				LeftWrist = rot(0, 0, 6),
				RightShoulder = rot(24.4, 0, 18),
				RightElbow = rot(29, 0, 0),
				RightWrist = rot(-17.4, 0, 0),
				Weapon = rot(-52.4, 0, 0),
			},
		},
		{
			-- squash
			time = 0.09,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.45, 0, 0, 0, 0),
				Waist = rot(-26, 0, 0),
				Neck = rot(14, 0, 0),
				LeftHip = rot(45, 0.5, -8.5),
				LeftKnee = rot(-79.7, 0, 0),
				LeftAnkle = rot(34.9, -5.3, 5.7),
				RightHip = rot(22.4, -3.1, 9.4),
				RightKnee = rot(-73.1, 0, 0),
				RightAnkle = rot(51.5, 7.4, -7.6),
				LeftShoulder = rot(37.7, 0, -31.5),
				LeftElbow = rot(19.8, 0, 0),
				RightShoulder = rot(35.3, 0, 30.6),
				RightElbow = rot(17.1, 0, 0),
				Weapon = rot(-47.9, 0, 0),
				LeftWrist = rot(0, 0, 1.8),
				RightWrist = rot(-9.4, 0, 0),
			},
		},
		{
			time = 0.14,
			easing = "Hold",
			joints = {
				Root = posRot(0, -0.45, 0, 0, 0, 0),
			},
		},
		{
			-- rise, overshooting tall
			time = 0.34,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftHip = rot(18, -1, -4.6),
				LeftKnee = rot(-30.9, 0, 0),
				LeftAnkle = rot(12.9, 0.6, 4.7),
				RightHip = rot(-6.3, -0.6, 4.4),
				RightKnee = rot(-14.4, 0, 0),
				RightAnkle = rot(20.7, 1.2, -4.5),
				LeftShoulder = rot(4, 0, -6),
				LeftElbow = rot(10, 0, 0),
				RightShoulder = rot(2, 0, 6),
				RightElbow = rot(16, 0, 0),
				Weapon = rot(-30, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightWrist = rot(-6, 0, 0),
			},
		},
		{
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				LeftAnkle = rot(9.2, 0.6, 4.6),
				LeftHip = rot(13.8, -0.7, -4.6),
				LeftKnee = rot(-23.1, 0, 0),
				RightAnkle = rot(21.8, 1.2, -4.5),
				RightHip = rot(-5.1, -0.6, 4.4),
				RightKnee = rot(-16.6, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.02, kind = "Footstep", data = { foot = "Both", landing = true } },
		{ time = 0.03, kind = "Sfx", data = { name = "footsteps.LandHard" } },
	},
}

return clip
