--!strict
--[[
	player/OneHandedSword/Jump: take-off. A crouch carried in by a 0.08 s blend (the point level,
	off the grass, the arms only 30% of the way from the guard to back and out, so the left hand
	clears the scabbard), an extension over 9 frames (SineInOut) with the arms thrown up and back,
	then the legs tuck (QuadOut). Fall takes over when the clip ends.
	Re-key (D-378): the ExpoOut extension threw the arms' 90-degree swing into its first frame (55
	degrees) and the 3-frame blend in carried the crouch's arm turn too fast; the BackOut tuck is
	eased.
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
	id = "player/OneHandedSword/Jump",
	rig = "PlayerR15",
	duration = 0.4,
	loop = false,
	layer = "FullBody",
	priority = 5,
	blendIn = 0.08,
	blendOut = 0.15,
	keys = {
		{
			-- crouch
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.25, 0, 0, 0, 0),
				Waist = rot(-14, 0, 0),
				Neck = rot(10, 0, 0),
				LeftHip = rot(30, 0, -4),
				LeftKnee = rot(-50, 0, 0),
				LeftAnkle = rot(20, 0, 0),
				RightHip = rot(30, 0, 4),
				RightKnee = rot(-50, 0, 0),
				RightAnkle = rot(20, 0, 0),
				LeftShoulder = rot(8.5, 0, -15.6),
				LeftElbow = rot(41, 0, 0),
				LeftWrist = rot(0, 0, 7),
				RightShoulder = rot(12, 0, 12.1),
				RightElbow = rot(30.5, 0, 0),
				RightWrist = rot(-19.3, 0, 0),
				Weapon = rot(4, 0, 0),
			},
		},
		{
			-- extension: everything up
			time = 0.15,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.1, 0, 0, 0, 0),
				Waist = rot(4, 0, 0),
				Neck = rot(2, 0, 0),
				LeftHip = rot(-6, 0, -4),
				LeftKnee = rot(-4, 0, 0),
				LeftAnkle = rot(-30, 0, 0),
				RightHip = rot(-6, 0, 4),
				RightKnee = rot(-4, 0, 0),
				RightAnkle = rot(-30, 0, 0),
				LeftShoulder = rot(60, 0, -20),
				LeftElbow = rot(10, 0, 0),
				RightShoulder = rot(50, 0, 20),
				RightElbow = rot(14, 0, 0),
				Weapon = rot(-70, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightWrist = rot(-6, 0, 0),
			},
		},
		{
			-- tuck
			time = 0.3,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, 0.04, 0, 0, 0, 0),
				Waist = rot(-6, 0, 0),
				Neck = rot(4, 0, 0),
				LeftHip = rot(28, 0, -4),
				LeftKnee = rot(-60, 0, 0),
				LeftAnkle = rot(18, 0, 0),
				RightHip = rot(20, 0, 4),
				RightKnee = rot(-48, 0, 0),
				RightAnkle = rot(14, 0, 0),
				LeftShoulder = rot(30, 0, -34),
				LeftElbow = rot(30, 0, 0),
				RightShoulder = rot(24, 0, 34),
				RightElbow = rot(30, 0, 0),
			},
		},
		{
			time = 0.4,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, 0, 0, 0, 0),
				LeftKnee = rot(-56, 0, 0),
				RightKnee = rot(-44, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.08, kind = "Sfx", data = { name = "footsteps.LandSoft" } },
	},
}

return clip
