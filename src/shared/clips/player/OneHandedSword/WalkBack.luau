--!strict
--[[
	player/OneHandedSword/WalkBack: backpedal, a 0.9 s cycle. The legs reach behind, the torso
	stays upright and the head stays on the target. Shorter arm swing than the forward walk.
	Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/WalkBack",
	rig = "PlayerR15",
	duration = 0.9,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left foot reaches back and plants
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 3, 0),
				Waist = rot(2, -3, 0),
				Neck = rot(0, 0, 0),
				LeftHip = rot(-20, 0, -3),
				LeftKnee = rot(-10, 0, 0),
				LeftAnkle = rot(30, 0, 0),
				RightHip = rot(14, 0, 3),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(-8, 0, 0),
				LeftShoulder = rot(10, 0, -5),
				LeftElbow = rot(14, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(-10, 0, 6),
				RightElbow = rot(10, 0, 0),
				RightWrist = rot(-6, 0, 0),
				Weapon = rot(-80, 0, 0),
			},
		},
		{
			time = 0.225,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, 0, 0, 0, 0),
				Waist = rot(2, 0, 0),
				LeftHip = rot(-4, 0, -3),
				LeftKnee = rot(-6, 0, 0),
				LeftAnkle = rot(10, 0, 0),
				RightHip = rot(0, 0, 3),
				RightKnee = rot(-40, 0, 0),
				RightAnkle = rot(26, 0, 0),
				LeftShoulder = rot(0, 0, -5),
				RightShoulder = rot(0, 0, 6),
			},
		},
		{
			-- right foot reaches back and plants
			time = 0.45,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, -3, 0),
				Waist = rot(2, 3, 0),
				LeftHip = rot(14, 0, -3),
				LeftKnee = rot(-6, 0, 0),
				LeftAnkle = rot(-8, 0, 0),
				RightHip = rot(-20, 0, 3),
				RightKnee = rot(-10, 0, 0),
				RightAnkle = rot(30, 0, 0),
				LeftShoulder = rot(-10, 0, -5),
				RightShoulder = rot(10, 0, 6),
			},
		},
		{
			time = 0.675,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, 0, 0, 0, 0),
				Waist = rot(2, 0, 0),
				LeftHip = rot(0, 0, -3),
				LeftKnee = rot(-40, 0, 0),
				LeftAnkle = rot(26, 0, 0),
				RightHip = rot(-4, 0, 3),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(10, 0, 0),
				LeftShoulder = rot(0, 0, -5),
				RightShoulder = rot(0, 0, 6),
			},
		},
	},
	events = {
		{ time = 0.03, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.48, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
