--!strict
--[[
	player/OneHandedSword/DodgeForward: the 0.25 s dodge step (combat.luau dodgeDuration) carrying
	dodgeDistance studs of root motion, forward: a low lunge, head down, the blade trailing behind; the coat flares procedurally. Two frames of lean
	(anticipation), a 4-frame ExpoOut extension, then a BackOut recovery into the ready stance.
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
	blendIn = 0.03,
	blendOut = 0.12,
	keys = {
		{
			-- the lean: weight already committed
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.3, 0, 0, 0, 0),
				Waist = rot(-34, -6, 0),
				Neck = rot(14, 6, 0),
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
				Root = posRot(0, -0.36, 0, 0, 0, 0),
				Waist = rot(-44, -8, 2),
				Neck = rot(20, 8, 0),
				LeftHip = rot(50, 0, -8),
				LeftKnee = rot(-24, 0, 0),
				LeftAnkle = rot(-20, 0, 0),
				RightHip = rot(-42, 0, 8),
				RightKnee = rot(-20, 0, 0),
				RightAnkle = rot(60, 0, 0),
				LeftShoulder = rot(-30, 0, -24),
				LeftElbow = rot(30, 0, 0),
				RightShoulder = rot(-46, 0, 22),
				RightElbow = rot(34, 0, 0),
				Weapon = rot(-60, 0, 0),
			},
			root = { pos = { 0, 0, -4.8 } },
		},
		{
			time = 0.25,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.36, 0, 0, 0, 0),
			},
			root = { pos = { 0, 0, -8 } },
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
			root = { pos = { 0, 0, -8 } },
		},
	},
	events = {
		{ time = 0.02, kind = "Sfx", data = { name = "DodgeStep" } },
		{ time = 0.3, kind = "Footstep", data = { foot = "Both" } },
	},
}

return clip
