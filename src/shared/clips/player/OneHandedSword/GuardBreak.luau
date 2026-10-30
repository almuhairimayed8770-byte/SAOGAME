--!strict
--[[
	player/OneHandedSword/GuardBreak: the 1.2 s guard-break stagger (combat.luau
	guardBreakStagger). It cuts in from the Guard pose (no blend in: key 0 is the Guard's) and the
	guard is smashed open over 9 frames (QuadOut): arms flung wide and up, torso thrown back; the
	stumble is a catch step back on the rear foot, down at 0.3 (1 stud of root motion over the
	clip), knees buckle, then an eased sag (SineInOut) with the head down, the point drooping to
	just above the grass, and a slow rise back into the ready stance in which the front foot steps
	back under the body (in the air at 0.95, down by 1.15).
	Re-key (D-382): the ExpoOut smash threw the arms 80+ degrees in its first frame and the guard's
	fade let the idle arms through; both feet skated a stud on the field and sank 0.26; the Spring
	sag put 28% of it into one frame. A 0.15 s blend out.
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
	blendIn = 0,
	blendOut = 0.15,
	keys = {
		{
			-- the guard pose, the moment before it breaks
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-10, -4, 0),
				Neck = rot(6, 4, 0),
				RightShoulder = rot(60.9, 6.4, -6.3),
				RightElbow = rot(90.6, 0, 0),
				RightWrist = rot(-4.4, -22.3, 47.6),
				Weapon = rot(-38, 0, -16),
				LeftShoulder = rot(43, -9.5, -4.6),
				LeftElbow = rot(92.5, 0, 0),
				LeftWrist = rot(-28.5, 1.1, -46.1),
				LeftHip = rot(24.3, -1.1, -6.4),
				LeftKnee = rot(-37.2, 0, 0),
				LeftAnkle = rot(12.7, 0.4, 6.3),
				RightHip = rot(-4.4, 0.8, 6.6),
				RightKnee = rot(-32.4, 0, 0),
				RightAnkle = rot(24.8, 1.1, -6.5),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			time = 0.15,
			easing = "QuadOut",
			joints = {
				LeftAnkle = rot(-0.6, -1.1, 5.7),
				LeftElbow = rot(32.6, 0, 0),
				LeftHip = rot(25.7, 0.3, -6.5),
				LeftKnee = rot(-25.1, 0, 0),
				LeftShoulder = rot(74.5, -1.4, -53.4),
				LeftWrist = rot(-4.3, 0.2, -6.9),
				Neck = rot(11.1, -2.8, 0),
				RightAnkle = rot(29.1, 2.9, -8.1),
				RightElbow = rot(28.9, 0, 0),
				RightHip = rot(-1.2, 1.6, 8.6),
				RightKnee = rot(-52.7, 0, 0),
				RightShoulder = rot(80.5, 1, 53.5),
				RightWrist = rot(7.8, -3.3, 24.1),
				Root = posRot(0, -0.103, 0, 0, 0, 0),
				Waist = rot(20.6, 4.5, 0),
				Weapon = rot(-48.2, 0, -2.4),
			},
			root = { pos = { 0, 0, 0.25 } },
		},
		{
			-- stumble back, knees buckling
			time = 0.3,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.3, 0, 0, 0, 0),
				Waist = rot(14, 4, 0),
				Neck = rot(8, -2, 0),
				LeftHip = rot(47, -2.6, -6.1),
				LeftKnee = rot(-44.6, 0, 0),
				LeftAnkle = rot(-2.6, -0.7, 6),
				RightHip = rot(-29.3, -3, 6.8),
				RightKnee = rot(-13.2, 0, 0),
				RightAnkle = rot(30.9, 1.8, -7.2),
				RightShoulder = rot(50, 0, 50),
				LeftShoulder = rot(46, 0, -48),
				LeftElbow = rot(22, 0, 0),
				LeftWrist = rot(0, 0, 0),
				RightElbow = rot(18, 0, 0),
				RightWrist = rot(10, 0, 20),
				Weapon = rot(-50, 0, 0),
			},
			root = { pos = { 0, 0, 0.55 } },
		},
		{
			-- sag: head down, arms heavy
			time = 0.7,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.34, 0, 0, 0, 0),
				Waist = rot(-14, 0, 0),
				Neck = rot(-16, 0, 0),
				RightShoulder = rot(10, 0, 20),
				RightElbow = rot(30, 0, 0),
				RightWrist = rot(-20, 0, 0),
				Weapon = rot(-23, 0, 0),
				LeftShoulder = rot(6, 0, -24),
				LeftElbow = rot(36, 0, 0),
				LeftKnee = rot(-47, 0, 0),
				LeftAnkle = rot(-3.5, -0.7, 6.1),
				RightKnee = rot(-32.3, 0, 0),
				RightAnkle = rot(39.2, 1.7, -7.3),
				LeftHip = rot(50.3, -3, -5.9),
				RightHip = rot(-18.7, -1.6, 7.4),
			},
			root = { pos = { 0, 0, 0.6 } },
		},
		{
			time = 0.95,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(7.9, -1.9, 7.2),
				LeftElbow = rot(43, 0, 0),
				LeftHip = rot(60, -5.1, -6),
				LeftKnee = rot(-78.1, 0, 0),
				LeftShoulder = rot(15.5, 0, -19.5),
				LeftWrist = rot(0, 0, 5),
				Neck = rot(-6.5, 6, 0),
				RightAnkle = rot(33.4, 1.3, -6.8),
				RightElbow = rot(32.5, 0, 0),
				RightHip = rot(-10, -0.1, 7),
				RightKnee = rot(-35.3, 0, 0),
				RightShoulder = rot(20, 0, 15),
				RightWrist = rot(-22.5, 0, 0),
				Root = posRot(0, -0.23, 0, 0, 0, 0),
				Waist = rot(-11, -6, 0),
				Weapon = rot(-36.5, 0, 0),
			},
			root = { pos = { 0, 0, 0.8 } },
		},
		{
			-- the slow rise back to ready (the head 3 degrees lower than IdleDrawn's, clear of the sheathed
			-- hilt)
			time = 1.2,
			easing = "QuadOut",
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
				LeftHip = rot(24.3, -1.1, -6.4),
				LeftKnee = rot(-37.2, 0, 0),
				LeftAnkle = rot(12.7, 0.4, 6.3),
				RightHip = rot(-4.4, 0.8, 6.6),
				RightKnee = rot(-32.4, 0, 0),
				RightAnkle = rot(24.8, 1.1, -6.5),
			},
			root = { pos = { 0, 0, 1 } },
		},
	},
	events = {
		{ time = 0.3, kind = "Footstep", data = { foot = "Right" } },
		{ time = 1.15, kind = "Footstep", data = { foot = "Left" } },
	},
}

return clip
