--!strict
--[[
	player/OneHandedSword/DodgeRight: the 0.25 s dodge step (combat.luau dodgeDuration) carrying
	dodgeDistance studs of root motion, right: a side spring, the body leaning hard into the step,
	the left leg pushing off, the point kept off the grass; the coat flares procedurally. Two
	frames of lean (anticipation), a 4-frame ExpoOut extension, then a BackOut recovery into the
	ready stance.
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
	id = "player/OneHandedSword/DodgeRight",
	rig = "PlayerR15",
	duration = 0.38,
	loop = false,
	layer = "FullBody",
	priority = 25,
	blendIn = 0.03,
	blendOut = 0.12,
	keys = {
		{
			-- the lean: weight already committed
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.26, 0, 0, 0, 0),
				Waist = rot(-10, -4, -16),
				Neck = rot(6, 4, 10),
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
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- full extension
			time = 0.07,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.34, 0, 0, 0, 0),
				Waist = rot(-14, -6, -24),
				Neck = rot(8, 6, 16),
				LeftHip = rot(-4, 0, -34),
				LeftKnee = rot(-8, 0, 0),
				LeftAnkle = rot(10, 0, 0),
				RightHip = rot(6, 0, 40),
				RightKnee = rot(-36, 0, 0),
				RightAnkle = rot(28, 0, 0),
				LeftShoulder = rot(20, 0, -40),
				LeftElbow = rot(40, 0, 0),
				RightShoulder = rot(10, 0, 50),
				RightElbow = rot(30, 0, 0),
				Weapon = rot(-22, 0, 0),
			},
			root = { pos = { 4.8, 0, 0 } },
		},
		{
			time = 0.25,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.34, 0, 0, 0, 0),
			},
			root = { pos = { 8, 0, 0 } },
		},
		{
			-- recovery into the ready stance
			time = 0.38,
			easing = "BackOut",
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
			root = { pos = { 8, 0, 0 } },
		},
	},
	events = {
		{ time = 0.02, kind = "Sfx", data = { name = "footsteps.LandSoft" } },
		{ time = 0.3, kind = "Footstep", data = { foot = "Both" } },
	},
}

return clip
