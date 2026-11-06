--!strict
--[[
	player/OneHandedSword/DodgeBack: the 0.25 s dodge step (combat.luau dodgeDuration) carrying
	dodgeDistance studs of root motion, back: a hop away, torso back, blade raised between the body and the threat; the coat flares procedurally. Three frames of
	blend into the lean (anticipation), a 4-frame QuadOut push off into the flight (the hop spread
	over its first 2 to 3 frames, D-179), the landing at 0.25, then a BackOut recovery into the
	ready stance.
	Re-key (D-386): the body hops: both feet leave the field at the push off (they skated the whole
	dodge on it), are carried tucked under the body through the flight and come down by the footstep
	as the root stops, between the drawn and the sheathed stance's places. The lean keeps 30% of the
	old one, the flight goes 30% of the way from it to the old extension and the landing holds
	45% of that extension against the ready stance, so no arm turns past the pop rule (the old
	blend in turned them up to 46 degrees in a frame) and the BackOut recovery comes back to the
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
	id = "player/OneHandedSword/DodgeBack",
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
				Root = posRot(0, -0.15, 0, 0, 0, 0),
				Waist = rot(-0.8, -10.8, 0),
				Neck = rot(-1, 10.8, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
				LeftHip = rot(29.3, -1.8, -6.5),
				LeftKnee = rot(-46.5, 0, 0),
				LeftAnkle = rot(16.9, 0.4, 6.5),
				RightHip = rot(0.1, 1.4, 6.7),
				RightKnee = rot(-42, 0, 0),
				RightAnkle = rot(30, 1, -6.7),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- full extension: the torso leans back 18 degrees, no further, so the scabbard's tip stays off the
			-- left thigh as that leg reaches back QuadOut, not ExpoOut: ExpoOut put 81% of this key's 4.8 studs
			-- into one 60 fps frame (D-179)
			time = 0.07,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.195, 0, 0, 0, 0),
				Waist = rot(4.8, -10.6, -0.6),
				Neck = rot(-2.8, 10.6, 0),
				LeftHip = rot(43.7, -5.4, -0.5),
				LeftKnee = rot(-72.1, 0, 0),
				LeftAnkle = rot(28.2, 5.5, 4.1),
				RightHip = rot(22.7, -1.3, 7.2),
				RightKnee = rot(-82.7, 0, 0),
				RightAnkle = rot(30.4, 7.3, -2.9),
				LeftShoulder = rot(28.3, 0, -17.7),
				LeftElbow = rot(50, 0, 0),
				RightShoulder = rot(37.2, 0, 4),
				RightElbow = rot(42.5, 0, 0),
				Weapon = rot(-44, 0, -3),
			},
			root = { pos = { 0, 0, 4.8 } },
		},
		{
			time = 0.25,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.26, 0, 0, 0, 0),
				LeftAnkle = rot(25.6, 5.3, 6.4),
				LeftHip = rot(38.4, -6.6, -2.9),
				LeftKnee = rot(-64.6, 0, 0),
				LeftShoulder = rot(30, 0, -19),
				Neck = rot(-2.9, 11.1, 0),
				RightAnkle = rot(36.8, 6.1, -6),
				RightElbow = rot(46.3, 0, 0),
				RightHip = rot(18.2, -1.1, 8),
				RightKnee = rot(-68.5, 0, 0),
				RightShoulder = rot(40.8, 0, 1),
				Waist = rot(3.7, -11.1, -0.9),
				Weapon = rot(-41, 0, -4.5),
			},
			root = { pos = { 0, 0, 8 } },
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
			root = { pos = { 0, 0, 8 } },
		},
	},
	events = {
		{ time = 0.3, kind = "Footstep", data = { foot = "Both" } },
	},
}

return clip
