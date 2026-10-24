--!strict
--[[
	player/OneHandedSword/Parry: the perfect parry. A 4-frame draw-in (anticipation), then the
	blade flicks out and up across the incoming strike in 3 frames (ExpoOut) with a white flash
	of trail, a 2-frame hold on the clash, and a spring settle back into the ready stance.
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
	blendIn = 0.02,
	blendOut = 0.12,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
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
		{
			-- draw in: the blade pulls to the hip, the free hand opens wide
			time = 0.07,
			easing = "QuadIn",
			joints = {
				Waist = rot(-6, -22, -2),
				Neck = rot(6, 20, 0),
				RightShoulder = rot(10, 0, 14),
				RightElbow = rot(60, 0, 0),
				RightWrist = rot(-30, 0, -10),
				Weapon = rot(-44, 0, -10),
				LeftShoulder = rot(40, 0, -30),
				LeftElbow = rot(36, 0, 0),
				LeftWrist = rot(0, 0, 24),
			},
		},
		{
			-- the flick: out and up across the strike
			time = 0.12,
			easing = "ExpoOut",
			joints = {
				Waist = rot(-10, 12, 4),
				Neck = rot(4, -6, 0),
				RightShoulder = rot(74, 0, 24),
				RightElbow = rot(38, 0, 0),
				RightWrist = rot(10, 0, -34),
				Weapon = rot(-18, 0, 32),
				LeftShoulder = rot(-20, 0, -34),
				LeftElbow = rot(44, 0, 0),
			},
		},
		{
			time = 0.15,
			easing = "Hold",
			joints = {
				Waist = rot(-10, 12, 4),
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
		{ time = 0.1, kind = "TrailOn", data = { kind = "Basic" } },
		{ time = 0.12, kind = "SmearOn", data = { axis = "Y" } },
		{ time = 0.1533, kind = "SmearOff" },
		{ time = 0.22, kind = "TrailOff" },
	},
}

return clip
