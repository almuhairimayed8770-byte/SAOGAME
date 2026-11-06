--!strict
--[[
	player/OneHandedSword/DrawStep: a standing body takes the drawn stance with a step as the sword
	comes off the back (D-640). From the sheathed Idle's stance (its 0 s, where its feet stand
	through the whole cycle) the right foot lifts, steps back and sets down on its ball, the drawn
	stance's rear foot (at 0.19 s); then the left foot lifts and sets down a little forward and out
	(at 0.36 s), and the hips have sunk to IdleDrawn's height. The end is IdleDrawn's 0 s stance.
	Each planted leg is solved at every key for the hips' drop, so a foot moves only while it is off
	the ground. The lower body only (the Root and the legs): the Draw keeps the arm and the head,
	and the Base set's upper body turns to the drawn one once this clip shows at full weight.
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
	id = "player/OneHandedSword/DrawStep",
	rig = "PlayerR15",
	duration = 0.45,
	loop = false,
	layer = "FullBody",
	priority = 5,
	blendIn = 0.08,
	blendOut = 0.15,
	keys = {
		{
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				LeftHip = rot(2, 0, -3),
				LeftKnee = rot(-6, 0, 0),
				LeftAnkle = rot(4, 0, 0),
				RightHip = rot(-2, 0, 3),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(8, 0, 0),
			},
		},
		{
			time = 0.05,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.06, 0, 0, 0, 0),
				LeftHip = rot(5.8, -0.2, -3),
				LeftKnee = rot(-13.3, 0, 0),
				LeftAnkle = rot(7.4, 0, 0),
				RightHip = rot(18.2, 1.1, 3),
				RightKnee = rot(-44.8, 0, 0),
				RightAnkle = rot(26.6, 0, -0.2),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.078, 0, 0, 0, 0),
				LeftHip = rot(9.8, -0.4, -3),
				LeftKnee = rot(-20.7, 0, 0),
				LeftAnkle = rot(10.9, 0, 0),
				RightHip = rot(13.2, 1.7, 4.6),
				RightKnee = rot(-53.9, 0, 0),
				RightAnkle = rot(40.7, 0, -0.4),
			},
		},
		{
			time = 0.15,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.095, 0, 0, 0, 0),
				LeftHip = rot(12.5, -0.6, -3),
				LeftKnee = rot(-25.8, 0, 0),
				LeftAnkle = rot(13.3, 0, 0.1),
				RightHip = rot(-6.3, 0.4, 6.1),
				RightKnee = rot(-32.8, 0, 0),
				RightAnkle = rot(39.1, 0, -0.1),
			},
		},
		{
			time = 0.19,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.106, 0, 0, 0, 0),
				LeftHip = rot(14, -0.6, -3),
				LeftKnee = rot(-28.6, 0, 0),
				LeftAnkle = rot(14.7, 0, 0.1),
				RightHip = rot(-11.9, -0.2, 5.9),
				RightKnee = rot(-21.1, 0, 0),
				RightAnkle = rot(33, 0, 0),
			},
		},
		{
			time = 0.24,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.113, 0, 0, 0, 0),
				LeftHip = rot(25.9, -1.4, -3),
				LeftKnee = rot(-51.3, 0, 0),
				LeftAnkle = rot(25.3, 0, 0.3),
				RightHip = rot(-10.9, -0.1, 6),
				RightKnee = rot(-23.1, 0, 0),
				RightAnkle = rot(34, 0, 0),
			},
		},
		{
			time = 0.28,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.118, 0, 0, 0, 0),
				LeftHip = rot(32, -2.1, -4.8),
				LeftKnee = rot(-57, 0, 0),
				LeftAnkle = rot(24.9, 0, 3.7),
				RightHip = rot(-10.3, 0, 6),
				RightKnee = rot(-24.5, 0, 0),
				RightAnkle = rot(34.7, 0, 0),
			},
		},
		{
			time = 0.31,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				LeftHip = rot(28.4, -1.8, -6.5),
				LeftKnee = rot(-44.9, 0, 0),
				LeftAnkle = rot(16.3, 0, 6.5),
				RightHip = rot(-10, 0, 6),
				RightKnee = rot(-25, 0, 0),
				RightAnkle = rot(35, 0, 0),
			},
		},
		{
			time = 0.36,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				LeftHip = rot(24.7, -1.3, -6.5),
				LeftKnee = rot(-38.1, 0, 0),
				LeftAnkle = rot(13.2, 0, 6.4),
				RightHip = rot(-10, 0, 6),
				RightKnee = rot(-25, 0, 0),
				RightAnkle = rot(35, 0, 0),
			},
		},
		{
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				LeftHip = rot(24.7, -1.3, -6.5),
				LeftKnee = rot(-38.1, 0, 0),
				LeftAnkle = rot(13.2, 0, 6.4),
				RightHip = rot(-10, 0, 6),
				RightKnee = rot(-25, 0, 0),
				RightAnkle = rot(35, 0, 0),
			},
		},
	},
	-- No Footstep: the feet set down softly under the Draw's or the Sheathe's own sound, and a
	-- step that catches up a stance after a render stall would sound as the stall replaying (D-132).
	events = {},
}

return clip
