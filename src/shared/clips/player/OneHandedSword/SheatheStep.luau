--!strict
--[[
	player/OneHandedSword/SheatheStep: a standing body leaves the drawn stance with a step as the sword
	goes onto the back (D-640); DrawStep backward in its feet. From IdleDrawn's stance (its 0 s,
	where its feet stand through the whole cycle) the rear foot comes off its ball, steps up and
	sets down flat beside the body, the sheathed stance's right foot (at 0.19 s); then the front
	foot lifts and sets down a little back and in (at 0.36 s), and the hips rise to the sheathed
	Idle's height. The end is the sheathed Idle's 0 s stance. Each planted leg is solved at every
	key for the hips' rise, so a foot moves only while it is off the ground. The lower body only:
	the Sheathe keeps the arm and the head.
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
	id = "player/OneHandedSword/SheatheStep",
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
			time = 0.05,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.109, 0, 0, 0, 0),
				LeftHip = rot(23.6, -1.2, -6.5),
				LeftKnee = rot(-36, 0, 0),
				LeftAnkle = rot(12.3, 0, 6.4),
				RightHip = rot(-0.1, 1, 6.4),
				RightKnee = rot(-46.5, 0, 0),
				RightAnkle = rot(46.6, 0, -0.4),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.092, 0, 0, 0, 0),
				LeftHip = rot(21.7, -0.9, -6.5),
				LeftKnee = rot(-32.5, 0, 0),
				LeftAnkle = rot(10.7, 0, 6.3),
				RightHip = rot(14, 1.8, 4.7),
				RightKnee = rot(-55.7, 0, 0),
				RightAnkle = rot(41.6, 0, -0.5),
			},
		},
		{
			time = 0.15,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.074, 0, 0, 0, 0),
				LeftHip = rot(19.5, -0.6, -6.4),
				LeftKnee = rot(-28.4, 0, 0),
				LeftAnkle = rot(8.8, 0, 6.2),
				RightHip = rot(16.8, 1, 3),
				RightKnee = rot(-42.2, 0, 0),
				RightAnkle = rot(25.3, 0, -0.2),
			},
		},
		{
			time = 0.19,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.064, 0, 0, 0, 0),
				LeftHip = rot(18.1, -0.5, -6.4),
				LeftKnee = rot(-25.8, 0, 0),
				LeftAnkle = rot(7.6, 0, 6.2),
				RightHip = rot(2.8, 0.3, 3),
				RightKnee = rot(-15.2, 0, 0),
				RightAnkle = rot(12.4, 0, 0),
			},
		},
		{
			time = 0.24,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.057, 0, 0, 0, 0),
				LeftHip = rot(29.8, -2, -6.5),
				LeftKnee = rot(-47.5, 0, 0),
				LeftAnkle = rot(17.4, 0, 6.6),
				RightHip = rot(0.9, 0.2, 3),
				RightKnee = rot(-11.5, 0, 0),
				RightAnkle = rot(10.6, 0, 0),
			},
		},
		{
			time = 0.28,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.052, 0, 0, 0, 0),
				LeftHip = rot(27.1, -1.5, -4.8),
				LeftKnee = rot(-48, 0, 0),
				LeftAnkle = rot(20.7, 0, 3.5),
				RightHip = rot(-1, 0.1, 3),
				RightKnee = rot(-8, 0, 0),
				RightAnkle = rot(8.9, 0, 0),
			},
		},
		{
			time = 0.31,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, 0, 0, 0),
				LeftHip = rot(18.9, -0.9, -3),
				LeftKnee = rot(-38, 0, 0),
				LeftAnkle = rot(19.1, 0, 0.2),
				RightHip = rot(-2, 0, 3),
				RightKnee = rot(-6, 0, 0),
				RightAnkle = rot(8, 0, 0),
			},
		},
		{
			time = 0.36,
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
			time = 0.45,
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
	},
	-- No Footstep: the feet set down softly under the Draw's or the Sheathe's own sound, and a
	-- step that catches up a stance after a render stall would sound as the stall replaying (D-132).
	events = {},
}

return clip
