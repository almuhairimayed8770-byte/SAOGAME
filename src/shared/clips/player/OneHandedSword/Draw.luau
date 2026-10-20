--!strict
--[[
	player/OneHandedSword/Draw: the sword comes off the back (UpperBody, the right arm and the head
	only, so it plays over any base: the drawn idle, a walk or a run). A lock-on or a hit taken
	while sheathed plays it; attacks, guard and parry draw-cut instead. The right hand dips
	(anticipation), reaches back over the right shoulder and takes the hilt behind it at 0.22 s
	(WeaponDraw: the sword moves from its sheath to the hand, the Weapon key there lining the blade
	up with the back mount exactly). A quick pull up the sheath line, the arm rising: 1.2 studs in
	0.06 s, speeding up to the middle key and slowing into the reach. The middle key is solved so
	that both moves keep the blade inside the scabbard's walls and the guard off the head; the
	wrist turns about the grip on the way, the blade does not. The reach leaves the grip 1.53
	studs from the shoulder, the elbow still bent, and 2 studs of blade in the sheath: they come
	out as the blade swings out over the mouth, behind the head, an edge out through the wall for
	7 ms (0.287 to 0.294 s, under two frames at 240 Hz). It then drops a little past the carry
	(low, the point forward, D-047) and springs back, the point higher than the drawn idle's so
	that a sprint's lean under it keeps it off the field.
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
			-- the grab: the elbow up, the hand back over the right shoulder on the hilt (WeaponDraw)
			time = 0.22,
			easing = "QuadOut",
			joints = {
				RightShoulder = rot(190.1, 56.8, 22),
				RightElbow = rot(125.6, 0, 0),
				RightWrist = rot(-69, -5, -45.4),
				Weapon = posRot(-0.0003, 0.0002, -0.0011, -10.9507, -77.1142, -9.553),
			},
		},
		{
			-- the pull: a quick tug up the sheath line, speeding up; from the grab to this key and
			-- on to the next the blade stays inside the scabbard's walls
			time = 0.25,
			easing = "QuadIn",
			joints = {
				RightShoulder = rot(160.3, 41.4, 46.5),
				RightElbow = rot(101.3, 0, 0),
				RightWrist = rot(-21.9, -4.9, -67.8),
				Weapon = posRot(0, -0.001, -0.0004, 5.5355, -94.0645, 5.5192),
			},
		},
		{
			-- the arm high up the sheath line, the blade 1.2 studs out
			time = 0.28,
			easing = "QuadOut",
			joints = {
				Neck = rot(-3, 9, 4),
				RightShoulder = rot(160.8, 22.5, 27.6),
				RightElbow = rot(82.9, 0, 0),
				RightWrist = rot(4.5, 15.3, -59.1),
				Weapon = posRot(0.0003, -0.0022, 0.0002, 10.2084, -76.1491, 7.5842),
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
				Weapon = rot(-30, 0, 0),
			},
		},
		{
			-- settle: the drawn idle's arm, the point 24 degrees higher than its carry so a run's
			-- or a sprint's lean under it keeps the point off the field; the blend out hands the
			-- sword to the base's own carry
			time = 0.62,
			easing = "Spring",
			joints = {
				Neck = rot(6, 10, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-26, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.22, kind = "WeaponDraw" },
	},
}

return clip
