--!strict
--[[
	player/OneHandedSword/DodgeForward: the 0.25 s dodge step (combat.luau dodgeDuration) carrying
	dodgeDistance studs of root motion, forward: a low lunge, head down, the blade held low and
	forward, its point clear of the grass; the coat flares procedurally. Three frames of
	blend into the lean (anticipation), a 4-frame QuadOut push off into the flight (the hop spread
	over its first 2 to 3 frames, D-179), the landing at 0.25, then a BackOut recovery into the
	ready stance.
	Re-key (D-386): the body hops: both feet leave the field at the push off (they skated the whole
	dodge on it), are carried tucked under the body through the flight and come down by the footstep
	as the root stops, between the drawn and the sheathed stance's places. The lean keeps 30% of the
	old one, the flight goes 25% of the way from it to the old extension and the landing holds
	35% of that extension against the ready stance, so no arm turns past the pop rule (the old
	blend in turned them up to 65 degrees in a frame) and the BackOut recovery comes back to the
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
	id = "player/OneHandedSword/DodgeForward",
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
				Root = posRot(0, -0.174, 0, 0, 0, 0),
				Waist = rot(-15.8, -9, 0),
				Neck = rot(-1, 9, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-42.8, 0, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
				LeftHip = rot(31.3, -2, -6.5),
				LeftKnee = rot(-50, 0, 0),
				LeftAnkle = rot(18.5, 0.4, 6.6),
				RightHip = rot(1.7, 1.6, 6.8),
				RightKnee = rot(-45.6, 0, 0),
				RightAnkle = rot(32, 1, -6.7),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- full extension QuadOut, not ExpoOut: ExpoOut put 81% of this key's 4.8 studs into one 60 fps frame
			-- (D-179)
			time = 0.07,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.22, 0, 0, 0, 0),
				Waist = rot(-22.8, -7.2, 0.5),
				Neck = rot(-1, 7.3, 0),
				LeftHip = rot(45.6, 1.8, -6.5),
				LeftKnee = rot(-74.7, 0, 0),
				LeftAnkle = rot(29.3, -4, 3.3),
				RightHip = rot(23, 4.9, 1.1),
				RightKnee = rot(-84.9, 0, 0),
				RightAnkle = rot(31.8, -1.2, -4.1),
				LeftShoulder = rot(11.3, 0, -17.2),
				LeftElbow = rot(45, 0, 0),
				RightShoulder = rot(20, 0, 13),
				RightElbow = rot(36.3, 0, 0),
				Weapon = rot(-34.1, 0, 0),
				RightWrist = rot(-18.7, 0, 0),
			},
			root = { pos = { 0, 0, -4.8 } },
		},
		{
			time = 0.25,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.26, 0, 0, 0, 0),
				LeftAnkle = rot(25.6, -4.2, 5.6),
				LeftElbow = rot(43, 0, 0),
				LeftHip = rot(39.2, 1.2, -8.3),
				LeftKnee = rot(-64.6, 0, 0),
				LeftShoulder = rot(5.8, 0, -18.1),
				Neck = rot(-1, 8.5, 0),
				RightAnkle = rot(36.8, -2.6, -5.2),
				RightElbow = rot(36.8, 0, 0),
				RightHip = rot(17.5, 5.9, 2.8),
				RightKnee = rot(-68.5, 0, 0),
				RightShoulder = rot(16, 0, 14.2),
				RightWrist = rot(-16.2, 0, 0),
				Waist = rot(-20.6, -8.5, 0.7),
				Weapon = rot(-35.3, 0, 0),
			},
			root = { pos = { 0, 0, -8 } },
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
				RightAnkle = rot(25.1, 1.2, -5),
			},
			root = { pos = { 0, 0, -8 } },
		},
	},
	events = {
		{ time = 0.3, kind = "Footstep", data = { foot = "Both" } },
	},
}

return clip
