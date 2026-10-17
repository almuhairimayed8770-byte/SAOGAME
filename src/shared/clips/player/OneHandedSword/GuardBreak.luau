--!strict
--[[
	player/OneHandedSword/GuardBreak: the 1.2 s guard-break stagger (combat.luau
	guardBreakStagger). The guard is smashed open: arms flung wide and up, torso thrown back, a
	stumbling step back (1 stud of root motion), knees buckle, then a sag with the head down and a
	slow rise back into the ready stance.
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
	id = "player/OneHandedSword/GuardBreak",
	rig = "PlayerR15",
	duration = 1.2,
	loop = false,
	layer = "FullBody",
	priority = 35,
	blendIn = 0.02,
	blendOut = 0.2,
	keys = {
		{
			-- the guard pose, the moment before it breaks
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-10, -4, 0),
				Neck = rot(6, 4, 0),
				RightShoulder = rot(58, 0, -28),
				RightElbow = rot(96, 0, 0),
				RightWrist = rot(-10, 0, 42),
				Weapon = rot(-38, 0, -16),
				LeftShoulder = rot(44, 0, -8),
				LeftElbow = rot(84, 0, 0),
				LeftWrist = rot(-20, 0, -36),
				LeftHip = rot(15, 0, -6),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(5, 0, 0),
				RightHip = rot(-10, 0, 6),
				RightKnee = rot(-25, 0, 0),
				RightAnkle = rot(35, 0, 0),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- smashed open
			time = 0.06,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.1, 0, 0, 0, 0),
				Waist = rot(26, 6, 0),
				Neck = rot(18, -4, 0),
				RightShoulder = rot(84, 0, 64),
				RightElbow = rot(18, 0, 0),
				RightWrist = rot(10, 0, 20),
				Weapon = rot(-50, 0, 0),
				LeftShoulder = rot(80, 0, -62),
				LeftElbow = rot(22, 0, 0),
				LeftWrist = rot(0, 0, 0),
			},
			root = { pos = { 0, 0, 0.2 } },
		},
		{
			-- stumble back, knees buckling
			time = 0.3,
			easing = "BackOut",
			joints = {
				Root = posRot(0, -0.3, 0, 0, 0, 0),
				Waist = rot(14, 4, 0),
				Neck = rot(8, -2, 0),
				LeftHip = rot(24, 0, -8),
				LeftKnee = rot(-48, 0, 0),
				LeftAnkle = rot(24, 0, 0),
				RightHip = rot(-14, 0, 10),
				RightKnee = rot(-50, 0, 0),
				RightAnkle = rot(64, 0, 0),
				RightShoulder = rot(50, 0, 50),
				LeftShoulder = rot(46, 0, -48),
			},
			root = { pos = { 0, 0, 1 } },
		},
		{
			-- sag: head down, arms heavy
			time = 0.7,
			easing = "Spring",
			joints = {
				Root = posRot(0, -0.34, 0, 0, 0, 0),
				Waist = rot(-14, 0, 0),
				Neck = rot(-16, 0, 0),
				RightShoulder = rot(10, 0, 20),
				RightElbow = rot(30, 0, 0),
				RightWrist = rot(-20, 0, 0),
				Weapon = rot(-70, 0, 0),
				LeftShoulder = rot(6, 0, -24),
				LeftElbow = rot(36, 0, 0),
				LeftKnee = rot(-44, 0, 0),
				LeftAnkle = rot(20, 0, 0),
				RightKnee = rot(-46, 0, 0),
				RightAnkle = rot(60, 0, 0),
			},
			root = { pos = { 0, 0, 1 } },
		},
		{
			-- the slow rise back to ready
			time = 1.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-8, -12, 0),
				Neck = rot(6, 12, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
				LeftHip = rot(15, 0, -6),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(5, 0, 0),
				RightHip = rot(-10, 0, 6),
				RightKnee = rot(-25, 0, 0),
				RightAnkle = rot(35, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.32, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
