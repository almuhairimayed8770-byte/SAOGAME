--!strict
--[[
	player/OneHandedSword/Stagger: the 0.5 s stagger (combat.luau staggerDuration). Thrown back
	off the feet over 9 frames (QuadOut, after a near-cut blend in): torso and head back, arms
	flung up, a hop back with 1.5 studs of root motion: the rear foot leaves the field with the
	throw and comes down steeply at its new place at 0.25 (QuadOut, the catch), the front foot is
	carried back high and lands under the body at 0.4, then an eased settle (SineInOut) into the
	ready stance. Both feet end between the drawn and the sheathed stance's places.
	Re-key (D-385): the ExpoOut threw the arms 60-87 degrees in the first frame; the front foot
	skated 1.3 studs on the field and sank 0.26; the BackOut catch and the Spring settle are eased.
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
	blendIn = 0.01,
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
				LeftHip = rot(24.3, -1.1, -6.4),
				LeftKnee = rot(-37.2, 0, 0),
				LeftAnkle = rot(12.7, 0.4, 6.3),
				RightHip = rot(-4.4, 0.8, 6.6),
				RightKnee = rot(-32.4, 0, 0),
				RightAnkle = rot(24.8, 1.1, -6.5),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- thrown back
			time = 0.15,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.152, 0, 0, 0, 0),
				Waist = rot(20.8, -0.8, -3.2),
				Neck = rot(10.2, -2.4, 0),
				RightShoulder = rot(54, 0, 34),
				RightElbow = rot(39, 0, 0),
				RightWrist = rot(-5, 0, 8),
				Weapon = rot(-42, 0, 8),
				LeftShoulder = rot(49.8, 0, -38.2),
				LeftElbow = rot(38.8, 0, 0),
				LeftHip = rot(43.5, -1.5, -7.1),
				LeftKnee = rot(-55.1, 0, 0),
				LeftAnkle = rot(3.6, -2.6, 5.8),
				RightHip = rot(-24.9, -0.7, 8.4),
				RightKnee = rot(-33.6, 0, 0),
				RightAnkle = rot(33.7, 1.6, -8),
			},
			root = { pos = { 0, 0, 0.45 } },
		},
		{
			-- catching the balance on the back foot
			time = 0.25,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.28, 0, 0, 0, 0),
				Waist = rot(6, -4, 2),
				Neck = rot(4, 4, 0),
				RightShoulder = rot(36, 0, 24),
				RightElbow = rot(44, 0, 0),
				LeftShoulder = rot(30, 0, -30),
				LeftElbow = rot(44, 0, 0),
				LeftHip = rot(60.1, -5.5, -6.5),
				LeftKnee = rot(-87.4, 0, 0),
				LeftAnkle = rot(15, -2.5, 7.6),
				RightHip = rot(-18.6, -1.2, 6.1),
				RightKnee = rot(-28.2, 0, 0),
				RightAnkle = rot(35, 1.4, -5.9),
				RightWrist = rot(0, 0, 10),
				Weapon = rot(-40, 0, 10),
			},
			root = { pos = { 0, 0, 1.05 } },
		},
		{
			time = 0.4,
			easing = "QuadOut",
			joints = {
				LeftAnkle = rot(23.8, 0, 5.7),
				LeftElbow = rot(47.6, 0, 0),
				LeftHip = rot(25.2, -0.6, -6),
				LeftKnee = rot(-49.1, 0, 0),
				LeftShoulder = rot(27, 0, -21),
				Neck = rot(3.4, 8.8, 0),
				RightAnkle = rot(31, 1.2, -5.7),
				RightElbow = rot(38.6, 0, 0),
				RightHip = rot(-2.2, 0.8, 5.9),
				RightKnee = rot(-40.7, 0, 0),
				RightShoulder = rot(32.4, 0, 15.6),
				RightWrist = rot(-15, 0, 4),
				Root = posRot(0, -0.184, 0, 0, 0, 0),
				Waist = rot(-2.4, -8.8, 0.8),
				Weapon = rot(-46, 0, 4),
			},
			root = { pos = { 0, 0, 1.35 } },
		},
		{
			-- ready again (the head 3 degrees lower than IdleDrawn's, clear of the sheathed hilt)
			time = 0.5,
			easing = "SineInOut",
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
				LeftHip = rot(24.1, -0.8, -5.5),
				LeftKnee = rot(-38.1, 0, 0),
				LeftAnkle = rot(13.8, 0.5, 5.4),
				RightHip = rot(2.5, 1.2, 5.7),
				RightKnee = rot(-39.7, 0, 0),
				RightAnkle = rot(25.3, 1.2, -5.6),
			},
			root = { pos = { 0, 0, 1.5 } },
		},
	},
	events = {
		{ time = 0.25, kind = "Footstep", data = { foot = "Right" } },
		{ time = 0.38, kind = "Footstep", data = { foot = "Left" } },
	},
}

return clip
