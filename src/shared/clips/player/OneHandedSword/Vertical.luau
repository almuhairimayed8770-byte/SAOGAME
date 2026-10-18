--!strict
--[[
	player/OneHandedSword/Vertical: the overhead cut (section 8: 1 hit, startup 0.25, total 0.6,
	post-motion 0.4, no root motion; guard-gauge heavy).

	Timeline:
	  0.00-0.15  start pose: the blade rises high behind the head, the back arches, weight back
	  0.15-0.25  activation hold: the blade lights, the arch breathes
	  0.25-0.35  Anticipation (6 frames): up onto the toes, the arch deepens, the free hand opens
	  0.35-0.40  Snap (3 frames): the chop, the whole body folding down behind it, the torso
	             squaring left so the blade falls on the centre line; it ends low and committed,
	             the blade angled forward and down, the point just above the ground
	  0.35-0.38  Smear
	  0.35-0.48  Hit window: opens on the snap's first frame (the trail ignites with it), so the
	             server sweeps the whole chop, and closes in the settle
	  0.40-0.43  Hold
	  0.43-0.55  Settle (Spring): the torso and the sword arm spring back 5-6 degrees, the point
	             lifts about half a stud off the ground
	  0.60-1.00  Recovery / post-motion: bent low over the blade, breathing, the point hovering
	             about half a stud above the ground
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
	id = "player/OneHandedSword/Vertical",
	rig = "PlayerR15",
	duration = 1.0,
	loop = false,
	layer = "FullBody",
	priority = 20,
	attack = true,
	hitStop = "Normal",
	blendIn = 0.08,
	blendOut = 0.2,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
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
		{
			-- start pose: the blade high behind the head
			time = 0.15,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.04, -0.14, 0.08, 0, -4, 0),
				Waist = rot(10, -14, -3),
				Neck = rot(-4, 14, 0),
				RightShoulder = rot(150, 0, 22),
				RightElbow = rot(62, 0, 0),
				RightWrist = rot(-10, 0, 0),
				Weapon = rot(-40, 0, 0),
				LeftShoulder = rot(46, 0, -22),
				LeftElbow = rot(26, 0, 0),
				LeftWrist = rot(0, 0, 24),
				LeftHip = rot(22, 0, -6),
				LeftKnee = rot(-14, 0, 0),
				LeftAnkle = rot(-8, 0, 0),
				RightHip = rot(-16, 0, 8),
				RightKnee = rot(-30, 0, 0),
				RightAnkle = rot(46, 0, 0),
			},
		},
		{
			-- activation hold
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Waist = rot(11, -15, -3),
				RightShoulder = rot(152, 0, 23),
				Weapon = rot(-42, 0, 0),
				LeftWrist = rot(0, 0, 28),
			},
		},
		{
			-- anticipation: onto the toes, the arch deepens
			time = 0.35,
			easing = "QuadIn",
			joints = {
				Root = posRot(0.04, -0.06, 0.1, 0, -6, 0),
				Waist = rot(16, -18, -4),
				Neck = rot(-8, 16, 0),
				RightShoulder = rot(162, 0, 26),
				RightElbow = rot(70, 0, 0),
				Weapon = rot(-46, 0, 0),
				LeftShoulder = rot(56, 0, -30),
				LeftAnkle = rot(-20, 0, 0),
				RightAnkle = rot(60, 0, 0),
			},
		},
		{
			-- snap: the chop, ending low with the point just above the ground
			time = 0.4,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.42, -0.06, 0, 4, 0),
				Waist = rot(-36, 12, 2),
				Neck = rot(-6, -12, 0),
				RightShoulder = rot(40, 0, 2),
				RightElbow = rot(6, 0, 0),
				RightWrist = rot(-8, 0, 0),
				Weapon = rot(-19, 0, 0),
				LeftShoulder = rot(-26, 0, -28),
				LeftElbow = rot(40, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(34, 0, -8),
				LeftKnee = rot(-44, 0, 0),
				LeftAnkle = rot(10, 0, 0),
				RightHip = rot(-24, 0, 10),
				RightKnee = rot(-36, 0, 0),
				RightAnkle = rot(60, 0, 0),
			},
		},
		{
			time = 0.43,
			easing = "Hold",
			joints = {
				Root = posRot(0, -0.42, -0.06, 0, 4, 0),
			},
		},
		{
			-- settle: the torso and the sword arm spring back 5-6 degrees, the point lifts off the ground
			time = 0.55,
			easing = "Spring",
			joints = {
				Root = posRot(0, -0.4, -0.05, 0, 3, 0),
				Waist = rot(-31, 10, 2),
				Neck = rot(-2, -10, 0),
				RightShoulder = rot(46, 0, 4),
				RightElbow = rot(6, 0, 0),
				Weapon = rot(-27, 0, 0),
				LeftShoulder = rot(-22, 0, -26),
			},
		},
		{
			time = 0.75,
			easing = "SineInOut",
			joints = {
				Waist = rot(-32, 10, 2),
				Neck = rot(-1, -10, 0),
				Weapon = rot(-26, 0, 1),
				RightWrist = rot(-7, 0, 1),
			},
		},
		{
			time = 0.9,
			easing = "SineInOut",
			joints = {
				Waist = rot(-31, 10, 2),
				Neck = rot(-3, -10, 0),
				Weapon = rot(-28, 0, -1),
				RightWrist = rot(-9, 0, -1),
			},
		},
		{
			time = 1.0,
			easing = "SineInOut",
			joints = {
				LeftShoulder = rot(-20, 0, -26),
				RightShoulder = rot(45, 0, 4),
				RightWrist = rot(-8, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },
		{ time = 0.35, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.35, kind = "SmearOn", data = { axis = "Y" } },
		{ time = 0.35, kind = "Sfx", data = { name = "whoosh.Large" } },
		{ time = 0.35, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.3833, kind = "SmearOff" },
		{ time = 0.48, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 0.52, kind = "TrailOff" },
		{ time = 0.6, kind = "PostMotionStart" },
	},
	beats = {
		Anticipation = { start = 0.25, finish = 0.35 },
		Snap = { start = 0.35, finish = 0.4 },
		Smear = { start = 0.35, finish = 0.3833 },
		Hold = { start = 0.4, finish = 0.43 },
		Settle = { start = 0.43, finish = 0.55 },
		Recovery = { start = 0.6, finish = 1.0 },
	},
}

return clip
