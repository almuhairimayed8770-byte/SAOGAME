--!strict
--[[
	player/OneHandedSword/Sheathe: the sword goes back on the back (UpperBody, the right arm and the
	head only, so it plays over any base). It plays once the server's Drawn attribute has stayed
	false for choreo.luau sheath.sheatheDelay. The base keeps the drawn set under it until it has
	faded in over the arm (Locomotion: the sheathed run and sprint pump an empty sword arm), then
	goes on to the sheathed set. It starts with the arm relaxed, the sword still in the hand with its
	point forward, the hand a little out from the side so the guard clears a run's rising thigh. The
	hand sinks (anticipation), swings the blade up in front and over the right shoulder, the point
	drops behind the head into the scabbard's mouth with the arm high. The three moves of the swing
	(0.08 to 0.22, 0.345 and 0.485 s) each get time in step with how far the tip travels and ease in
	and out, so on the client's own path none moves the tip past 78 studs a second (1.3 a 60 Hz
	frame) or turns the blade past 1030 degrees a second (choreo.luau sheath.sheatheTipSpeed and
	bladeTurnRate, tests/choreo/SheathTip.spec.luau): a whip, where the point used to swing down
	into the mouth 1.7 studs and 25 degrees in one frame from a near stop. An edge goes out through
	the scabbard's wall for 12 ms (0.463 to 0.475 s, under one 60 Hz frame, at most 0.14 studs), and
	the blade slides home along the sheath line, speeding up and then slowing into the seat at
	0.535 s (WeaponSheathe: the Weapon key there lines the blade up with the back mount exactly).
	The middle key is Draw's, solved so that both moves keep the blade inside the scabbard's walls
	and the guard off the head; the wrist turns about the grip on the way, the blade does not. The
	head tucks and leans away from the arm while the hilt passes behind it. The hand lets go and
	falls back to the side with a small spring settle. After WeaponSheathe no key moves Weapon.
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
	id = "player/OneHandedSword/Sheathe",
	rig = "PlayerR15",
	duration = 0.815,
	loop = false,
	layer = "UpperBody",
	priority = 8,
	blendIn = 0.15,
	blendOut = 0.2,
	keys = {
		{
			-- the arm relaxed, the sword still in the hand with its point forward, the hand a
			-- little out from the side so the guard clears a run's rising thigh
			time = 0,
			easing = "SineInOut",
			joints = {
				Neck = rot(3, 2, 0),
				RightShoulder = rot(3, 0, 10),
				RightElbow = rot(8, 0, 0),
				RightWrist = rot(0, 0, 0),
				Weapon = rot(0, 0, 0),
			},
		},
		{
			-- anticipation: the hand sinks a little, still out from the thigh, and the wrist tips
			-- the point up
			time = 0.08,
			easing = "SineInOut",
			joints = {
				RightShoulder = rot(10, 0, 12),
				RightElbow = rot(20, 0, 0),
				RightWrist = rot(-10, 0, 0),
				Weapon = rot(12, 0, 0),
			},
		},
		{
			-- the blade swings up in front and stands straight up
			time = 0.22,
			easing = "SineInOut",
			joints = {
				Neck = rot(0, 6, 2),
				RightShoulder = rot(120, 0, 10),
				RightElbow = rot(40, 0, 0),
				RightWrist = rot(-40, 0, 0),
				Weapon = rot(-32, -28, 0),
			},
		},
		{
			-- over the shoulder: the hand high, the point dropping behind the head
			time = 0.345,
			easing = "SineInOut",
			joints = {
				Neck = rot(-3, 9, 4),
				RightShoulder = rot(170, 10, 15),
				RightElbow = rot(40, 0, 0),
				RightWrist = rot(-30, 20, -20),
				Weapon = rot(-20, -60, 0),
			},
		},
		{
			-- the point finds the sheath: the arm high, the blade on the sheath line with
			-- its lower part already in the mouth
			time = 0.485,
			easing = "SineInOut",
			joints = {
				RightShoulder = rot(160.8, 22.5, 27.6),
				RightElbow = rot(82.9, 0, 0),
				RightWrist = rot(4.5, 15.3, -59.1),
				Weapon = posRot(0.0003, -0.0022, 0.0002, 10.2084, -76.1491, 7.5842),
			},
		},
		{
			-- the blade slides home along the sheath line, speeding up, then slowing into the seat;
			-- on both moves it stays inside the scabbard's walls
			time = 0.51,
			easing = "QuadIn",
			joints = {
				RightShoulder = rot(160.3, 41.4, 46.5),
				RightElbow = rot(101.3, 0, 0),
				RightWrist = rot(-21.9, -4.9, -67.8),
				Weapon = posRot(0, -0.001, -0.0004, 5.5355, -94.0645, 5.5192),
			},
		},
		{
			-- the blade slides home (WeaponSheathe): the grip on the back mount
			time = 0.535,
			easing = "QuadOut",
			joints = {
				RightShoulder = rot(190.1, 56.8, 22),
				RightElbow = rot(125.6, 0, 0),
				RightWrist = rot(-69, -5, -45.4),
				Weapon = posRot(-0.0003, 0.0002, -0.0011, -10.9507, -77.1142, -9.553),
			},
		},
		{
			-- the hand lets go and comes off the hilt beside the head
			time = 0.615,
			easing = "QuadOut",
			joints = {
				Neck = rot(-3, 9, 4),
				RightShoulder = rot(60, 0, 40),
				RightElbow = rot(110, 0, 0),
				RightWrist = rot(-10, 0, 0),
			},
		},
		{
			-- the arm falls to the side and swings a little past it
			time = 0.735,
			easing = "SineInOut",
			joints = {
				Neck = rot(1, 4, 1),
				RightShoulder = rot(-5, 0, 4),
				RightElbow = rot(10, 0, 0),
				RightWrist = rot(-2, 0, 0),
			},
		},
		{
			-- settle: the hand back at the side, the sheathed idle's arm
			time = 0.815,
			easing = "Spring",
			joints = {
				Neck = rot(3, 1, 0),
				RightShoulder = rot(3, 0, 4),
				RightElbow = rot(8, 0, 0),
				RightWrist = rot(0, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.535, kind = "WeaponSheathe" },
	},
}

return clip
