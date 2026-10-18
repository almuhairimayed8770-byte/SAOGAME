--!strict
--[[
	player/OneHandedSword/Draw: the sword comes off the back (UpperBody, the right arm and the head
	only, so it plays over any base: the drawn idle, a walk or a run). A lock-on or a hit taken
	while sheathed plays it; attacks, guard and parry draw-cut instead. The right hand dips
	(anticipation), reaches over the right shoulder and takes the hilt at 0.22 s (WeaponDraw: the
	sword moves from its sheath to the hand, the Weapon key there lining the blade up with the back
	mount exactly). A quick pull up the sheath line to the arm's full reach: 1.2 studs in 0.06 s,
	speeding up to the middle key and slowing into the reach. The middle key is solved so that both
	moves keep the blade inside the scabbard's walls and the guard off the head; the wrist turns
	about the grip on the way, the blade does not. The reach leaves 2 studs of blade in the sheath:
	they come out as the blade swings out behind the head and over the top. It then drops a little
	past the drawn carry (low, the point forward, D-047) and springs back.
	The head tucks and leans away from the reaching arm until the blade is out: the hilt sits just
	behind it, and a run's raised head would meet it.
	Before WeaponDraw the sword is on the back, so no key moves Weapon there.
	Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/Draw",
	rig = "PlayerR15",
	duration = 0.62,
	loop = false,
	sheathed = true,
	layer = "UpperBody",
	priority = 8,
	blendIn = 0.08,
	blendOut = 0.2,
	keys = {
		{
			-- the drawn carry's arm, the hand empty (the sword is still on the back)
			time = 0,
			easing = "SineInOut",
			joints = {
				Neck = rot(4, 6, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
			},
		},
		{
			-- anticipation: the shoulder dips and the elbow starts to lift out
			time = 0.08,
			easing = "SineInOut",
			joints = {
				Neck = rot(-3, 9, 4),
				RightShoulder = rot(14, 0, 20),
				RightElbow = rot(62, 0, 0),
				RightWrist = rot(-6, 0, 0),
			},
		},
		{
			-- the grab: the elbow up, the hand on the hilt over the right shoulder (WeaponDraw)
			time = 0.22,
			easing = "QuadOut",
			joints = {
				RightShoulder = rot(171.8, 30.6, 0.7),
				RightElbow = rot(146.3, 0, 0),
				RightWrist = rot(-70, 35.7, -40),
				Weapon = posRot(-0.001, -0.0003, 0.0034, -6.0927, -77.2179, -3.4319),
			},
		},
		{
			-- the pull: a quick tug up the sheath line, speeding up; from the grab to this key and
			-- on to the next the blade stays inside the scabbard's walls
			time = 0.25,
			easing = "QuadIn",
			joints = {
				RightShoulder = rot(177.7, -6.7, 5.5),
				RightElbow = rot(102.5, 0, 0),
				RightWrist = rot(-5.7, 31.9, -101.3),
				Weapon = posRot(0.0001, -0.0021, 0.0017, 23.2883, -91.0383, 25.9712),
			},
		},
		{
			-- the arm at full reach up the sheath line, the blade 1.2 studs out
			time = 0.28,
			easing = "QuadOut",
			joints = {
				Neck = rot(-3, 9, 4),
				RightShoulder = rot(181.9, 0.6, 21.7),
				RightElbow = rot(42.7, 0, 0),
				RightWrist = rot(46.7, 15.9, -77.8),
				Weapon = posRot(0.0012, -0.004, 0.0001, -5.7525, -77.1789, -3.217),
			},
		},
		{
			-- over the shoulder: the hand high, the blade sweeping out behind the head
			time = 0.36,
			easing = "SineInOut",
			joints = {
				Neck = rot(1, 7, 2),
				RightShoulder = rot(170, 10, 15),
				RightElbow = rot(40, 0, 0),
				RightWrist = rot(-30, 20, -20),
				Weapon = rot(-20, -60, 0),
			},
		},
		{
			-- the blade comes over the top and stands straight up
			time = 0.43,
			easing = "SineInOut",
			joints = {
				RightShoulder = rot(120, 0, 10),
				RightElbow = rot(40, 0, 0),
				RightWrist = rot(-40, 0, 0),
				Weapon = rot(-32, -28, 0),
			},
		},
		{
			-- down into the carry, a little past it (the shoulder and the point lower)
			time = 0.5,
			easing = "QuadOut",
			joints = {
				Neck = rot(5, 9, 0),
				RightShoulder = rot(26, 0, 8),
				RightElbow = rot(30, 0, 0),
				RightWrist = rot(-30, 0, 0),
				Weapon = rot(-54, 0, 0),
			},
		},
		{
			-- settle: the drawn carry (IdleDrawn), low with the point forward
			time = 0.62,
			easing = "Spring",
			joints = {
				Neck = rot(6, 10, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.22, kind = "WeaponDraw" },
	},
}

return clip
