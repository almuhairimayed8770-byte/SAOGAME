--!strict
--[[
	player/OneHandedSword/DodgeLeft: the 0.25 s dodge step (combat.luau dodgeDuration) carrying
	dodgeDistance studs of root motion, left: a side spring, the body leaning hard into the step, the right leg pushing off; the coat flares procedurally. Three frames of
	blend into the lean (anticipation), a 4-frame QuadOut push off into the flight (the hop spread
	over its first 2 to 3 frames, D-179), the landing at 0.25, then a BackOut recovery into the
	ready stance.
	Re-key (D-386): the body hops: both feet leave the field at the push off (they skated the whole
	dodge on it), are carried tucked under the body through the flight and come down by the footstep
	as the root stops, between the drawn and the sheathed stance's places. The lean keeps 30% of the
	old one, the flight goes 30% of the way from it to the old extension and the landing holds
	45% of that extension against the ready stance, so no arm turns past the pop rule (the old
	blend in turned them up to 35 degrees in a frame) and the BackOut recovery comes back to the
	guard inside it; the head stays at least 4 degrees further down than the ready stance's, clear
	of the sheathed hilt. A 0.05 s blend in and a 0.15 s blend out.
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
	id = "player/OneHandedSword/DodgeLeft",
	rig = "PlayerR15",
	duration = 0.38,
	loop = false,
	layer = "FullBody",
	priority = 25,
	blendIn = 0.05,
	blendOut = 0.15,
	keys = {
		{
			-- the lean: weight already committed
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.162, 0, 0, 0, 0),
				Waist = rot(-8.6, -9.6, 4.8),
				Neck = rot(-1, 9.6, -3),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
				LeftHip = rot(30.3, -1.9, -6.5),
				LeftKnee = rot(-48.3, 0, 0),
				LeftAnkle = rot(17.7, 0.4, 6.6),
				RightHip = rot(0.9, 1.5, 6.7),
				RightKnee = rot(-43.9, 0, 0),
				RightAnkle = rot(31, 1, -6.7),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- full extension: the torso leans 30 degrees into the dodge (DodgeRight leans 24) so the scabbard's
			-- tip rides over the splayed left leg, not into it QuadOut, not ExpoOut: ExpoOut put 81% of this
			-- key's 4.8 studs into one 60 fps frame (D-179)
			time = 0.07,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.215, 0, 0, 0, 0),
				Waist = rot(-10.2, -8.5, 12.4),
				Neck = rot(-1, 8.5, -6.9),
				LeftHip = rot(45, -2, -3.3),
				LeftKnee = rot(-74.2, 0, 0),
				LeftAnkle = rot(29.1, 1.1, 3.7),
				RightHip = rot(23.9, -4.9, 11.2),
				RightKnee = rot(-84.5, 0, 0),
				RightAnkle = rot(31.3, 12.8, -2.2),
				LeftShoulder = rot(20.5, 0, -25.5),
				LeftElbow = rot(44, 0, 0),
				RightShoulder = rot(27, 0, 19),
				RightElbow = rot(36.5, 0, 0),
				Weapon = rot(-51.2, 0, 0),
			},
			root = { pos = { -4.8, 0, 0 } },
		},
		{
			time = 0.25,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.26, 0, 0, 0, 0),
				LeftAnkle = rot(25.6, 0.2, 6),
				LeftElbow = rot(41, 0, 0),
				LeftHip = rot(38.8, -2.4, -5.8),
				LeftKnee = rot(-64.6, 0, 0),
				LeftShoulder = rot(18.3, 0, -30.7),
				Neck = rot(-1, 9.3, -7.2),
				RightAnkle = rot(36.8, 9.7, -6.3),
				RightElbow = rot(37.3, 0, 0),
				RightHip = rot(18.6, -3.9, 10.1),
				RightKnee = rot(-68.5, 0, 0),
				RightShoulder = rot(25.5, 0, 23.5),
				Waist = rot(-10.7, -9.3, 13.5),
				Weapon = rot(-51.8, 0, 0),
			},
			root = { pos = { -8, 0, 0 } },
		},
		{
			-- recovery into the ready stance (the head 3 degrees lower than IdleDrawn's, clear of the sheathed
			-- hilt)
			time = 0.38,
			easing = "BackOut",
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
				RightHip = rot(5.6, 1.3, 5),
				RightKnee = rot(-42.7, 0, 0),
				RightAnkle = rot(25.1, 1.3, -5),
			},
			root = { pos = { -8, 0, 0 } },
		},
	},
	events = {
		{ time = 0.3, kind = "Footstep", data = { foot = "Both" } },
	},
}

return clip
