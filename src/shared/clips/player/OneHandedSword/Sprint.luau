--!strict
--[[
	player/OneHandedSword/Sprint: 24 studs/s, a 0.5 s cycle. Deeper lean, bigger arm pumps, the
	head driving forward. With a drawn weapon the locomotion layer adds the "low and back" pose
	from data/choreo.luau on top of this clip.
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
	id = "player/OneHandedSword/Sprint",
	rig = "PlayerR15",
	duration = 0.5,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.14, 0, 0, 8, 0),
				Waist = rot(-22, -8, 3),
				Neck = rot(16, 3, 0),
				LeftHip = rot(46, 0, -3),
				LeftKnee = rot(-22, 0, 0),
				LeftAnkle = rot(-24, 0, 0),
				RightHip = rot(-42, 0, 3),
				RightKnee = rot(-34, 0, 0),
				RightAnkle = rot(56, 0, 0),
				LeftShoulder = rot(-48, 0, -8),
				LeftElbow = rot(88, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(50, 0, 10),
				RightElbow = rot(78, 0, 0),
				RightWrist = rot(-10, 0, 0),
				Weapon = rot(-80, 0, 0),
			},
		},
		{
			time = 0.125,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.1, 0, 0, 0, 0),
				Waist = rot(-22, 0, 0),
				Neck = rot(16, 0, 0),
				LeftHip = rot(8, 0, -3),
				LeftKnee = rot(-46, 0, 0),
				LeftAnkle = rot(24, 0, 0),
				RightHip = rot(6, 0, 3),
				RightKnee = rot(-96, 0, 0),
				RightAnkle = rot(46, 0, 0),
				LeftShoulder = rot(0, 0, -8),
				LeftElbow = rot(92, 0, 0),
				RightShoulder = rot(0, 0, 10),
				RightElbow = rot(84, 0, 0),
			},
		},
		{
			time = 0.25,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.14, 0, 0, -8, 0),
				Waist = rot(-22, 8, -3),
				Neck = rot(16, -3, 0),
				LeftHip = rot(-42, 0, -3),
				LeftKnee = rot(-34, 0, 0),
				LeftAnkle = rot(56, 0, 0),
				RightHip = rot(46, 0, 3),
				RightKnee = rot(-22, 0, 0),
				RightAnkle = rot(-24, 0, 0),
				LeftShoulder = rot(50, 0, -8),
				LeftElbow = rot(78, 0, 0),
				RightShoulder = rot(-48, 0, 10),
				RightElbow = rot(88, 0, 0),
			},
		},
		{
			time = 0.375,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.1, 0, 0, 0, 0),
				Waist = rot(-22, 0, 0),
				Neck = rot(16, 0, 0),
				LeftHip = rot(6, 0, -3),
				LeftKnee = rot(-96, 0, 0),
				LeftAnkle = rot(46, 0, 0),
				RightHip = rot(8, 0, 3),
				RightKnee = rot(-46, 0, 0),
				RightAnkle = rot(24, 0, 0),
				LeftShoulder = rot(0, 0, -8),
				LeftElbow = rot(84, 0, 0),
				RightShoulder = rot(0, 0, 10),
				RightElbow = rot(92, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.02, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.27, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
