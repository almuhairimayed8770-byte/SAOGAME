--!strict
--[[
	player/OneHandedSword/Parry: the perfect parry (F8). It plays on the clash frame (the
	Inverted picture), from the Guard it answers: key 0 is the Guard pose, so nothing jumps. The
	blade beats out and up across the strike in 3 frames (SineInOut under a 3-frame blend-in): the
	torso turns more than half way, the arms part of the way out and up while the blade turns in the
	grip and the free hand leaves the flat, with a white flash of trail; a 3-frame hold on the clash
	stands in for the hit-stop the rigs no longer take on a parry; the blow carries the arms further
	out in a short recoil (QuadOut), then an eased settle (SineInOut) into the ready stance.
	Re-key (D-380): key 0 is the re-keyed Guard pose; the old deflect turned the free forearm 60
	degrees in a frame and the spring settle threw the whole return into one.
	UpperBody so the feet stay planted by the locomotion layer. Not an attack: no hit windows.
	Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/Parry",
	rig = "PlayerR15",
	duration = 0.4,
	loop = false,
	layer = "UpperBody",
	priority = 14,
	blendIn = 0.05,
	blendOut = 0.12,
	keys = {
		{
			-- the guard it answers (player/OneHandedSword/Guard key 0)
			time = 0,
			easing = "QuadOut",
			joints = {
				Waist = rot(-10, -4, 0),
				Neck = rot(6, 4, 0),
				RightShoulder = rot(60.9, 6.4, -6.3),
				RightElbow = rot(90.6, 0, 0),
				RightWrist = rot(-4.4, -22.3, 47.6),
				Weapon = rot(-38, 0, -16),
				LeftShoulder = rot(43, -9.5, -4.6),
				LeftElbow = rot(92.5, 0, 0),
				LeftWrist = rot(-28.5, 1.1, -46.1),
			},
		},
		{
			-- the deflect: out and up across the strike, the free hand thrown back
			time = 0.05,
			easing = "SineInOut",
			joints = {
				Waist = rot(-10, 5.6, 2.4),
				Neck = rot(4.8, -2, 0),
				RightShoulder = rot(65.1, 4.4, 3.4),
				RightElbow = rot(73.8, 0, 0),
				RightWrist = rot(0.2, -15.2, 21.5),
				Weapon = rot(-18, 0, 32),
				LeftShoulder = rot(30.4, -7.6, -10.5),
				LeftElbow = rot(82.8, 0, 0),
				LeftWrist = rot(-22.8, 0.9, -32.1),
			},
		},
		{
			-- held on the clash
			time = 0.1,
			easing = "Hold",
			joints = {
				Waist = rot(-10, 5.6, 2.4),
			},
		},
		{
			-- the recoil off the blow
			time = 0.17,
			easing = "QuadOut",
			joints = {
				Waist = rot(-11.8, 8.6, 2.7),
				RightShoulder = rot(66.8, 2.2, 17.3),
				RightElbow = rot(60.3, 0, 0),
				Weapon = rot(-22, 0, 36),
				LeftElbow = rot(70.7, 0, 0),
				LeftShoulder = rot(14.7, -5.2, -17.8),
				LeftWrist = rot(-15.7, 0.6, -14.6),
				Neck = rot(4.2, -5, 0),
				RightWrist = rot(5, -7.8, -5.4),
			},
		},
		{
			-- settle back to ready
			time = 0.4,
			easing = "SineInOut",
			joints = {
				Waist = rot(-8, -12, 0),
				Neck = rot(6, 12, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
			},
		},
	},
	events = {
		{ time = 0.01, kind = "TrailOn", data = { kind = "Basic" } },
		{ time = 0.0167, kind = "SmearOn", data = { axis = "Y" } },
		{ time = 0.05, kind = "SmearOff" },
		{ time = 0.12, kind = "TrailOff" },
	},
}

return clip
