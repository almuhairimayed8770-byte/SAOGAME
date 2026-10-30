--!strict
--[[
	player/OneHandedSword/IdleDrawn: drawn idle, the 12-second cycle. Low stance, left foot
	forward, blade low and forward, free hand open. Weight shifts at 3 s and 9 s and a blade
	re-grip at 6 s (the wrist rolls, the point dips and comes back up). The feet stay where they
	stand at the start through the weight shifts (D-417): each leg is solved at every shift key for
	the root's shift, the front foot flat on the field, the rear one on its ball as the cycle
	starts (0.04 over the field, the heel 0.13). They sank the left foot 0.16 below the field at
	3 s and lifted the rear one to 0.22 off it. The rear ball stays its 0.04 up: set down on the
	field, an attack out of the drawn run sinks the right foot 0.11 as the run hands over to this
	idle (ClipAudit Run@0.5, max 0.10) and the drawn stop drags a foot 0.19 (Stride, max 0.145).
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
	id = "player/OneHandedSword/IdleDrawn",
	rig = "PlayerR15",
	duration = 12,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.2,
	blendOut = 0.2,
	keys = {
		{
			time = 0,
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
				LeftHip = rot(24.7, -1.3, -6.5),
				LeftKnee = rot(-38.1, 0, 0),
				LeftAnkle = rot(13.2, 0, 6.4),
				RightHip = rot(-10, 0, 6),
				RightKnee = rot(-25, 0, 0),
				RightAnkle = rot(35, 0, 0),
			},
		},
		{
			-- weight eases onto the rear (right) leg
			time = 3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.08, -0.15, 0.06, 0, 0, 2),
				Waist = rot(-6, -15, -2),
				Neck = rot(5, 15, 1),
				LeftHip = rot(29.2, -4.1, -10.5),
				LeftKnee = rot(-43.1, 0, 0),
				LeftAnkle = rot(13.4, 0, 9.1),
				RightHip = rot(-3.2, 1, 1.3),
				RightKnee = rot(-34.9, 0, 0),
				RightAnkle = rot(38.1, 0, 2.6),
			},
		},
		{
			time = 5.4,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.08, -0.15, 0.06, 0, 0, 2),
			},
		},
		{
			-- re-grip: the wrist rolls, the point dips
			time = 5.9,
			easing = "QuadOut",
			joints = {
				RightWrist = rot(-35, 0, -12),
				Weapon = rot(-62, 0, -6),
				RightElbow = rot(40, 0, 0),
			},
		},
		{
			time = 6.25,
			easing = "BackOut",
			joints = {
				RightWrist = rot(-22, 0, 4),
				Weapon = rot(-46, 0, 2),
				RightElbow = rot(33, 0, 0),
			},
		},
		{
			time = 6.7,
			easing = "Spring",
			joints = {
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				RightElbow = rot(35, 0, 0),
			},
		},
		{
			-- weight returns forward onto the left foot
			time = 9,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.04, -0.12, -0.04, 0, 0, -1),
				Waist = rot(-9, -10, 1),
				Neck = rot(7, 10, 0),
				LeftHip = rot(23.4, -0.2, -4.4),
				LeftKnee = rot(-37.9, 0, 0),
				LeftAnkle = rot(14.4, 0, 5.1),
				RightHip = rot(-13.3, -0.9, 8.3),
				RightKnee = rot(-20.9, 0, 0),
				RightAnkle = rot(34.3, 0, -1.4),
			},
		},
		{
			time = 11.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.04, -0.12, -0.04, 0, 0, -1),
				Waist = rot(-9, -10, 1),
			},
		},
	},
	events = {},
}

return clip
