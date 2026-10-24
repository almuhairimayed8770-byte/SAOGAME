--!strict
--[[
	player/OneHandedSword/DodgeLeft: the 0.25 s dodge step (combat.luau dodgeDuration) carrying
	dodgeDistance studs of root motion, left: a side spring, the body leaning hard into the step, the right leg pushing off; the coat flares procedurally. Two frames of lean
	(anticipation), a 4-frame QuadOut extension
	(the hop spread over its first 2 to 3 frames, D-179), then a BackOut recovery into the ready stance.
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
	id = "player/OneHandedSword/DodgeLeft",
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
				Waist = rot(-10, -4, 16),
				Neck = rot(6, 4, -10),
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
			-- full extension: the torso leans 30 degrees into the dodge (DodgeRight leans 24) so the
			-- scabbard's tip rides over the splayed left leg, not into it
			-- QuadOut, not ExpoOut: ExpoOut put 81% of this key's 4.8 studs into one 60 fps frame (D-179)
			time = 0.07,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.34, 0, 0, 0, 0),
				Waist = rot(-14, -6, 30),
				Neck = rot(8, 6, -16),
				LeftHip = rot(6, 0, -40),
				LeftKnee = rot(-36, 0, 0),
				LeftAnkle = rot(28, 0, 0),
				RightHip = rot(-4, 0, 34),
				RightKnee = rot(-8, 0, 0),
				RightAnkle = rot(10, 0, 0),
				LeftShoulder = rot(10, 0, -50),
				LeftElbow = rot(30, 0, 0),
				RightShoulder = rot(20, 0, 40),
				RightElbow = rot(40, 0, 0),
				Weapon = rot(-54, 0, 0),
			},
			root = { pos = { -4.8, 0, 0 } },
		},
		{
			time = 0.25,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.34, 0, 0, 0, 0),
			},
			root = { pos = { -8, 0, 0 } },
		},
		{
			-- recovery into the ready stance (the head 3 degrees lower than IdleDrawn's, clear of the
			-- sheathed hilt)
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
				LeftHip = rot(15, 0, -6),
				LeftKnee = rot(-20, 0, 0),
				LeftAnkle = rot(5, 0, 0),
				RightHip = rot(-10, 0, 6),
				RightKnee = rot(-25, 0, 0),
				RightAnkle = rot(35, 0, 0),
			},
			root = { pos = { -8, 0, 0 } },
		},
	},
	events = {
		{ time = 0.3, kind = "Footstep", data = { foot = "Both" } },
	},
}

return clip
