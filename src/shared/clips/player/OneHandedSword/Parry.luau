--!strict
--[[
	player/OneHandedSword/Parry: the perfect parry (F8). It plays on the clash frame (the
	Inverted picture), from the Guard it answers: key 0 is the Guard pose, so nothing jumps. The
	blade beats out and up across the strike in 3 frames (QuadOut under a 3-frame blend-in, no
	frame carrying more than about half the move), with a white flash of trail; a 3-frame hold on
	the clash stands in for the hit-stop the rigs no longer take on a parry; a short recoil off the
	blow, then a spring settle into the ready stance.
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
				RightShoulder = rot(58, 0, -28),
				RightElbow = rot(96, 0, 0),
				RightWrist = rot(-10, 0, 42),
				Weapon = rot(-38, 0, -16),
				LeftShoulder = rot(44, 0, -8),
				LeftElbow = rot(84, 0, 0),
				LeftWrist = rot(-20, 0, -36),
			},
		},
		{
			-- the deflect: out and up across the strike, the free hand thrown back
			time = 0.05,
			easing = "QuadOut",
			joints = {
				Waist = rot(-10, 12, 4),
				Neck = rot(4, -6, 0),
				RightShoulder = rot(74, 0, 24),
				RightElbow = rot(38, 0, 0),
				RightWrist = rot(10, 0, -34),
				Weapon = rot(-18, 0, 32),
				LeftShoulder = rot(-20, 0, -34),
				LeftElbow = rot(44, 0, 0),
				LeftWrist = rot(0, 0, 24),
			},
		},
		{
			-- held on the clash
			time = 0.1,
			easing = "Hold",
			joints = {
				Waist = rot(-10, 12, 4),
			},
		},
		{
			-- the recoil off the blow
			time = 0.17,
			easing = "QuadOut",
			joints = {
				Waist = rot(-12, 10, 3),
				RightShoulder = rot(70, 0, 30),
				RightElbow = rot(44, 0, 0),
				Weapon = rot(-22, 0, 36),
			},
		},
		{
			-- settle back to ready
			time = 0.4,
			easing = "Spring",
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
