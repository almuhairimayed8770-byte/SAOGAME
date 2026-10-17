--!strict
--[[
	player/OneHandedSword/Run: 16 studs/s, a 0.6 s cycle. The anime run: leaned forward, the free
	arm pumping, long strides with a real flight phase (the body rides high between plants).
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
	id = "player/OneHandedSword/Run",
	rig = "PlayerR15",
	duration = 0.6,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left foot plants, body low
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 6, 0),
				Waist = rot(-14, -6, 2),
				Neck = rot(12, 2, 0),
				LeftHip = rot(38, 0, -3),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(-18, 0, 0),
				RightHip = rot(-34, 0, 3),
				RightKnee = rot(-30, 0, 0),
				RightAnkle = rot(48, 0, 0),
				LeftShoulder = rot(-36, 0, -6),
				LeftElbow = rot(80, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightShoulder = rot(40, 0, 8),
				RightElbow = rot(70, 0, 0),
				RightWrist = rot(-10, 0, 0),
				Weapon = rot(-80, 0, 0),
			},
		},
		{
			-- flight: both legs folding, the body high
			time = 0.15,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.08, 0, 0, 0, 0),
				Waist = rot(-14, 0, 0),
				Neck = rot(12, 0, 0),
				LeftHip = rot(6, 0, -3),
				LeftKnee = rot(-40, 0, 0),
				LeftAnkle = rot(20, 0, 0),
				RightHip = rot(4, 0, 3),
				RightKnee = rot(-84, 0, 0),
				RightAnkle = rot(40, 0, 0),
				LeftShoulder = rot(0, 0, -6),
				LeftElbow = rot(85, 0, 0),
				RightShoulder = rot(0, 0, 8),
				RightElbow = rot(75, 0, 0),
			},
		},
		{
			-- right foot plants
			time = 0.3,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, -6, 0),
				Waist = rot(-14, 6, -2),
				Neck = rot(12, -2, 0),
				LeftHip = rot(-34, 0, -3),
				LeftKnee = rot(-30, 0, 0),
				LeftAnkle = rot(48, 0, 0),
				RightHip = rot(38, 0, 3),
				RightKnee = rot(-20, 0, 0),
				RightAnkle = rot(-18, 0, 0),
				LeftShoulder = rot(40, 0, -6),
				LeftElbow = rot(70, 0, 0),
				RightShoulder = rot(-36, 0, 8),
				RightElbow = rot(80, 0, 0),
			},
		},
		{
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.08, 0, 0, 0, 0),
				Waist = rot(-14, 0, 0),
				Neck = rot(12, 0, 0),
				LeftHip = rot(4, 0, -3),
				LeftKnee = rot(-84, 0, 0),
				LeftAnkle = rot(40, 0, 0),
				RightHip = rot(6, 0, 3),
				RightKnee = rot(-40, 0, 0),
				RightAnkle = rot(20, 0, 0),
				LeftShoulder = rot(0, 0, -6),
				LeftElbow = rot(75, 0, 0),
				RightShoulder = rot(0, 0, 8),
				RightElbow = rot(85, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.02, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.32, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
