--!strict
--[[
	player/OneHandedSword/Sheathe: the sword goes back on the back (UpperBody, the right arm and the
	head only, so it plays over any base). It plays once the server's Drawn attribute has stayed
	false for choreo.luau sheath.sheatheDelay, when the base is already the sheathed set, so it
	starts from what that base shows: the arm relaxed, the sword still in the hand with its point
	forward. The hand sinks (anticipation), swings the blade up in front and over the right
	shoulder, the point drops behind the head into the scabbard's mouth with the arm at full reach,
	and the blade slides home along the sheath line, speeding up and then slowing into the seat at
	0.42 s (WeaponSheathe: the Weapon key there lines the blade up with the back mount exactly). The
	middle key is Draw's, solved so that both moves keep the blade inside the scabbard's walls and
	the guard off the head; the wrist turns about the grip on the way, the blade does not. The head
	tucks and leans away from the arm while the hilt passes behind it. The hand lets go and falls
	back to the side with a small spring settle. After WeaponSheathe no key moves Weapon.
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
	duration = 0.7,
	loop = false,
	layer = "UpperBody",
	priority = 8,
	blendIn = 0.15,
	blendOut = 0.2,
	keys = {
		{
			-- what the sheathed base shows: the arm relaxed, the sword still in the hand, point forward
			time = 0,
			easing = "SineInOut",
			joints = {
				Neck = rot(3, 2, 0),
				RightShoulder = rot(3, 0, 4),
				RightElbow = rot(8, 0, 0),
				RightWrist = rot(0, 0, 0),
				Weapon = rot(0, 0, 0),
			},
		},
		{
			-- anticipation: the hand sinks a little and the wrist tips the point up
			time = 0.1,
			easing = "SineInOut",
			joints = {
				RightShoulder = rot(10, 0, 6),
				RightElbow = rot(20, 0, 0),
				RightWrist = rot(-10, 0, 0),
				Weapon = rot(12, 0, 0),
			},
		},
		{
			-- the blade swings up in front and stands straight up
			time = 0.24,
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
			time = 0.31,
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
			-- the point finds the sheath: the arm at full reach, the blade on the sheath line with
			-- its lower part already in the mouth
			time = 0.37,
			easing = "SineInOut",
			joints = {
				RightShoulder = rot(181.9, 0.6, 21.7),
				RightElbow = rot(42.7, 0, 0),
				RightWrist = rot(46.7, 15.9, -77.8),
				Weapon = posRot(0.0012, -0.004, 0.0001, -5.7525, -77.1789, -3.217),
			},
		},
		{
			-- the blade slides home along the sheath line, speeding up, then slowing into the seat;
			-- on both moves it stays inside the scabbard's walls
			time = 0.395,
			easing = "QuadIn",
			joints = {
				RightShoulder = rot(177.7, -6.7, 5.5),
				RightElbow = rot(102.5, 0, 0),
				RightWrist = rot(-5.7, 31.9, -101.3),
				Weapon = posRot(0.0001, -0.0021, 0.0017, 23.2883, -91.0383, 25.9712),
			},
		},
		{
			-- the blade slides home (WeaponSheathe): the grip on the back mount
			time = 0.42,
			easing = "QuadOut",
			joints = {
				RightShoulder = rot(171.8, 30.6, 0.7),
				RightElbow = rot(146.3, 0, 0),
				RightWrist = rot(-70, 35.7, -40),
				Weapon = posRot(-0.001, -0.0003, 0.0034, -6.0927, -77.2179, -3.4319),
			},
		},
		{
			-- the hand lets go and comes off the hilt beside the head
			time = 0.5,
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
			time = 0.62,
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
			time = 0.7,
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
		{ time = 0.42, kind = "WeaponSheathe" },
	},
}

return clip
