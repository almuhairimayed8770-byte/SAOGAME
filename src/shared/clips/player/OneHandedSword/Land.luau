--!strict
--[[
	player/OneHandedSword/Land: landing squash. Contact, a 4-frame ExpoOut drop into a deep
	crouch with the arms thrown forward and out, a short hold, then a BackOut rise that overshoots
	tall and settles. The locomotion layer scales this clip's weight by fall height.
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
	blendIn = 0.03,
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
				LeftHip = rot(14, 0, -6),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(14, 0, 6),
				RightKnee = rot(-20, 0, 0),
				RightAnkle = rot(6, 0, 0),
				LeftShoulder = rot(20, 0, -30),
				LeftElbow = rot(20, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(16, 0, 30),
				RightElbow = rot(20, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-76, 0, 0),
			},
		},
		{
			-- squash
			time = 0.07,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.5, 0, 0, 0, 0),
				Waist = rot(-26, 0, 0),
				Neck = rot(14, 0, 0),
				LeftHip = rot(40, 0, -10),
				LeftKnee = rot(-78, 0, 0),
				LeftAnkle = rot(38, 0, 0),
				RightHip = rot(40, 0, 10),
				RightKnee = rot(-78, 0, 0),
				RightAnkle = rot(38, 0, 0),
				LeftShoulder = rot(44, 0, -36),
				LeftElbow = rot(12, 0, 0),
				RightShoulder = rot(40, 0, 36),
				RightElbow = rot(12, 0, 0),
				Weapon = rot(-60, 0, 0),
			},
		},
		{
			time = 0.14,
			easing = "Hold",
			joints = {
				Root = posRot(0, -0.5, 0, 0, 0, 0),
			},
		},
		{
			-- rise, overshooting tall
			time = 0.4,
			easing = "BackOut",
			joints = {
				Root = posRot(0, -0.08, 0, 0, 0, 0),
				Waist = rot(-4, 0, 0),
				Neck = rot(4, 0, 0),
				LeftHip = rot(6, 0, -4),
				LeftKnee = rot(-12, 0, 0),
				LeftAnkle = rot(6, 0, 0),
				RightHip = rot(4, 0, 4),
				RightKnee = rot(-12, 0, 0),
				RightAnkle = rot(8, 0, 0),
				LeftShoulder = rot(4, 0, -6),
				LeftElbow = rot(10, 0, 0),
				RightShoulder = rot(2, 0, 6),
				RightElbow = rot(8, 0, 0),
				Weapon = rot(-80, 0, 0),
			},
		},
		{
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.02, kind = "Footstep", data = { foot = "Both", landing = true } },
		{ time = 0.03, kind = "Sfx", data = { name = "footsteps.LandHard" } },
	},
}

return clip
