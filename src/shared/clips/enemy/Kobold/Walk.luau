--!strict
--[[
	enemy/Kobold/Walk: a 0.5 s waddle on the kobold's rigid legs (D-482), paced to rigs.luau Kobold
	walkSpeed 10 (RigDriver plays it at speed / walkSpeed). Hunched 10 degrees, the axe swinging with
	the right arm, the free arm counter-swinging. Each planted leg rolls over its sole, heel edge then
	toe edge, under a hip that moves forward at the walk's speed, so the edge on the field holds its
	place (32.4 degrees forward to 32.4 back, 2.50 studs a step). The body turns over the planted hip,
	up to 6 degrees, so the other hip rises and the swinging sole, its hip drawn 0.1 up at mid-swing,
	clears the field by 0.054 or more. The body rides the stiff legs' arc, 0.102 below to 0.046 above
	standing straight, its root at the idle's height on average (D-418). Footsteps on the plants.
	Generated: one key a 60 fps frame (the stance angle solved from the distance walked, the root
	placed so the planted hip holds its place). Rig: Kobold. Hip X+ swings a leg forward; Root X-
	hunches forward, Root Z+ lifts the right side.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Kobold/Walk",
	rig = "Kobold",
	duration = 0.5,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- left foot plants, right lifts
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, -10, 0, 0),
				Neck = rot(8, 0, 0),
				LeftHip = rot(42.43, 0, 0),
				RightHip = rot(-22.43, 0, 0),
				LeftShoulder = rot(-24.32, 0, -10),
				RightShoulder = rot(25.46, 0, 12),
				Weapon = rot(-34.22, 0, 0),
			},
		},
		{
			time = 0.0167,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.026, -0.051, -0.002, -10, 0, 1.25),
				Neck = rot(8, 0, -0.87),
				LeftHip = rot(37.94, -0.77, -0.98),
				RightHip = posRot(0, 0.004, 0, -25.28, 0.53, -1.13),
				LeftShoulder = rot(-20.96, 0, -10),
				RightShoulder = rot(22.77, 0, 12),
				Weapon = rot(-33.63, 0, 0),
			},
		},
		{
			time = 0.0333,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.052, 0.002, -0.004, -10, 0, 2.44),
				Neck = rot(8, 0, -1.71),
				LeftHip = rot(33.53, -1.35, -2.03),
				RightHip = posRot(0, 0.017, 0, -25.04, 1.03, -2.21),
				LeftShoulder = rot(-17.67, 0, -10),
				RightShoulder = rot(20.13, 0, 12),
				Weapon = rot(-33.06, 0, 0),
			},
		},
		{
			time = 0.05,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.075, 0.041, -0.006, -10, 0, 3.53),
				Neck = rot(8, 0, -2.47),
				LeftHip = rot(29.19, -1.72, -3.08),
				RightHip = posRot(0, 0.035, 0, -22.2, 1.33, -3.26),
				LeftShoulder = rot(-14.43, 0, -10),
				RightShoulder = rot(17.54, 0, 12),
				Weapon = rot(-32.5, 0, 0),
			},
		},
		{
			time = 0.0667,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.095, 0.066, -0.007, -10, 0, 4.46),
				Neck = rot(8, 0, -3.12),
				LeftHip = rot(24.9, -1.88, -4.04),
				RightHip = posRot(0, 0.055, 0, -17.23, 1.32, -4.26),
				LeftShoulder = rot(-11.22, 0, -10),
				RightShoulder = rot(14.98, 0, 12),
				Weapon = rot(-31.95, 0, 0),
			},
		},
		{
			time = 0.0833,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.111, 0.076, -0.009, -10, 0, 5.2),
				Neck = rot(8, 0, -3.64),
				LeftHip = rot(20.63, -1.84, -4.86),
				RightHip = posRot(0, 0.075, 0, -10.63, 0.96, -5.11),
				LeftShoulder = rot(-8.03, 0, -10),
				RightShoulder = rot(12.43, 0, 12),
				Weapon = rot(-31.39, 0, 0),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.122, 0.071, -0.009, -10, 0, 5.71),
				Neck = rot(8, 0, -3.99),
				LeftHip = rot(16.37, -1.61, -5.47),
				RightHip = posRot(0, 0.09, 0, -2.86, 0.29, -5.7),
				LeftShoulder = rot(-4.84, 0, -10),
				RightShoulder = rot(9.87, 0, 12),
				Weapon = rot(-30.84, 0, 0),
			},
		},
		{
			time = 0.1167,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.128, 0.052, -0.01, -10, 0, 5.97),
				Neck = rot(8, 0, -4.18),
				LeftHip = rot(12.1, -1.26, -5.83),
				RightHip = posRot(0, 0.099, 0, 5.6, -0.58, -5.94),
				LeftShoulder = rot(-1.62, 0, -10),
				RightShoulder = rot(7.3, 0, 12),
				Weapon = rot(-30.28, 0, 0),
			},
		},
		{
			time = 0.1333,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.128, 0.052, -0.01, -10, 0, 5.97),
				Neck = rot(8, 0, -4.18),
				LeftHip = rot(7.8, -0.81, -5.91),
				RightHip = posRot(0, 0.099, 0, 14.3, -1.48, -5.78),
				LeftShoulder = rot(1.62, 0, -10),
				RightShoulder = rot(4.7, 0, 12),
				Weapon = rot(-29.72, 0, 0),
			},
		},
		{
			time = 0.15,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.122, 0.071, -0.009, -10, 0, 5.71),
				Neck = rot(8, 0, -3.99),
				LeftHip = rot(3.53, -0.35, -5.7),
				RightHip = posRot(0, 0.09, 0, 22.77, -2.22, -5.26),
				LeftShoulder = rot(4.84, 0, -10),
				RightShoulder = rot(2.13, 0, 12),
				Weapon = rot(-29.16, 0, 0),
			},
		},
		{
			time = 0.1667,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.111, 0.076, -0.009, -10, 0, 5.2),
				Neck = rot(8, 0, -3.64),
				LeftHip = rot(-0.71, 0.06, -5.2),
				RightHip = posRot(0, 0.075, 0, 30.57, -2.65, -4.47),
				LeftShoulder = rot(8.03, 0, -10),
				RightShoulder = rot(-0.43, 0, 12),
				Weapon = rot(-28.61, 0, 0),
			},
		},
		{
			time = 0.1833,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.095, 0.066, -0.007, -10, 0, 4.46),
				Neck = rot(8, 0, -3.12),
				LeftHip = rot(-4.95, 0.39, -4.44),
				RightHip = posRot(0, 0.055, 0, 37.2, -2.7, -3.55),
				LeftShoulder = rot(11.22, 0, -10),
				RightShoulder = rot(-2.98, 0, 12),
				Weapon = rot(-28.05, 0, 0),
			},
		},
		{
			time = 0.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.075, 0.041, -0.006, -10, 0, 3.53),
				Neck = rot(8, 0, -2.47),
				LeftHip = rot(-9.22, 0.57, -3.48),
				RightHip = posRot(0, 0.035, 0, 42.18, -2.37, -2.61),
				LeftShoulder = rot(14.43, 0, -10),
				RightShoulder = rot(-5.54, 0, 12),
				Weapon = rot(-27.5, 0, 0),
			},
		},
		{
			time = 0.2167,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.052, 0.002, -0.004, -10, 0, 2.44),
				Neck = rot(8, 0, -1.71),
				LeftHip = rot(-13.54, 0.57, -2.37),
				RightHip = posRot(0, 0.017, 0, 45.04, -1.73, -1.72),
				LeftShoulder = rot(17.67, 0, -10),
				RightShoulder = rot(-8.13, 0, 12),
				Weapon = rot(-26.94, 0, 0),
			},
		},
		{
			time = 0.2333,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.026, -0.051, -0.002, -10, 0, 1.25),
				Neck = rot(8, 0, -0.87),
				LeftHip = rot(-17.94, 0.38, -1.19),
				RightHip = posRot(0, 0.004, 0, 45.28, -0.89, -0.88),
				LeftShoulder = rot(20.96, 0, -10),
				RightShoulder = rot(-10.77, 0, 12),
				Weapon = rot(-26.37, 0, 0),
			},
		},
		{
			-- right foot plants, left lifts
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.12, 0, -10, 0, 0),
				Neck = rot(8, 0, 0),
				LeftHip = rot(-22.43, 0, 0),
				RightHip = rot(42.43, 0, 0),
				LeftShoulder = rot(24.32, 0, -10),
				RightShoulder = rot(-13.46, 0, 12),
				Weapon = rot(-25.78, 0, 0),
			},
		},
		{
			time = 0.2667,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.026, -0.051, -0.002, -10, 0, -1.25),
				Neck = rot(8, 0, 0.87),
				LeftHip = posRot(0, 0.004, 0, -25.28, -0.53, 1.13),
				RightHip = rot(37.94, 0.77, 0.98),
				LeftShoulder = rot(26.46, 0, -10),
				RightShoulder = rot(-15.17, 0, 12),
				Weapon = rot(-25.41, 0, 0),
			},
		},
		{
			time = 0.2833,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.052, 0.002, -0.004, -10, 0, -2.44),
				Neck = rot(8, 0, 1.71),
				LeftHip = posRot(0, 0.017, 0, -25.04, -1.03, 2.21),
				RightHip = rot(33.53, 1.35, 2.03),
				LeftShoulder = rot(26.3, 0, -10),
				RightShoulder = rot(-15.04, 0, 12),
				Weapon = rot(-25.44, 0, 0),
			},
		},
		{
			time = 0.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.075, 0.041, -0.006, -10, 0, -3.53),
				Neck = rot(8, 0, 2.47),
				LeftHip = posRot(0, 0.035, 0, -22.2, -1.33, 3.26),
				RightHip = rot(29.19, 1.72, 3.08),
				LeftShoulder = rot(24.18, 0, -10),
				RightShoulder = rot(-13.34, 0, 12),
				Weapon = rot(-25.81, 0, 0),
			},
		},
		{
			time = 0.3167,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.095, 0.066, -0.007, -10, 0, -4.46),
				Neck = rot(8, 0, 3.12),
				LeftHip = posRot(0, 0.055, 0, -17.23, -1.32, 4.26),
				RightHip = rot(24.9, 1.88, 4.04),
				LeftShoulder = rot(20.46, 0, -10),
				RightShoulder = rot(-10.37, 0, 12),
				Weapon = rot(-26.45, 0, 0),
			},
		},
		{
			time = 0.3333,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.111, 0.076, -0.009, -10, 0, -5.2),
				Neck = rot(8, 0, 3.64),
				LeftHip = posRot(0, 0.075, 0, -10.63, -0.96, 5.11),
				RightHip = rot(20.63, 1.84, 4.86),
				LeftShoulder = rot(15.5, 0, -10),
				RightShoulder = rot(-6.4, 0, 12),
				Weapon = rot(-27.31, 0, 0),
			},
		},
		{
			time = 0.35,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.122, 0.071, -0.009, -10, 0, -5.71),
				Neck = rot(8, 0, 3.99),
				LeftHip = posRot(0, 0.09, 0, -2.86, -0.29, 5.7),
				RightHip = rot(16.37, 1.61, 5.47),
				LeftShoulder = rot(9.66, 0, -10),
				RightShoulder = rot(-1.73, 0, 12),
				Weapon = rot(-28.33, 0, 0),
			},
		},
		{
			time = 0.3667,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.128, 0.052, -0.01, -10, 0, -5.97),
				Neck = rot(8, 0, 4.18),
				LeftHip = posRot(0, 0.099, 0, 5.6, 0.58, 5.94),
				RightHip = rot(12.1, 1.26, 5.83),
				LeftShoulder = rot(3.28, 0, -10),
				RightShoulder = rot(3.38, 0, 12),
				Weapon = rot(-29.43, 0, 0),
			},
		},
		{
			time = 0.3833,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.128, 0.052, -0.01, -10, 0, -5.97),
				Neck = rot(8, 0, 4.18),
				LeftHip = posRot(0, 0.099, 0, 14.3, 1.48, 5.78),
				RightHip = rot(7.8, 0.81, 5.91),
				LeftShoulder = rot(-3.28, 0, -10),
				RightShoulder = rot(8.62, 0, 12),
				Weapon = rot(-30.57, 0, 0),
			},
		},
		{
			time = 0.4,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.122, 0.071, -0.009, -10, 0, -5.71),
				Neck = rot(8, 0, 3.99),
				LeftHip = posRot(0, 0.09, 0, 22.77, 2.22, 5.26),
				RightHip = rot(3.53, 0.35, 5.7),
				LeftShoulder = rot(-9.66, 0, -10),
				RightShoulder = rot(13.73, 0, 12),
				Weapon = rot(-31.67, 0, 0),
			},
		},
		{
			time = 0.4167,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.111, 0.076, -0.009, -10, 0, -5.2),
				Neck = rot(8, 0, 3.64),
				LeftHip = posRot(0, 0.075, 0, 30.57, 2.65, 4.47),
				RightHip = rot(-0.71, -0.06, 5.2),
				LeftShoulder = rot(-15.5, 0, -10),
				RightShoulder = rot(18.4, 0, 12),
				Weapon = rot(-32.69, 0, 0),
			},
		},
		{
			time = 0.4333,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.095, 0.066, -0.007, -10, 0, -4.46),
				Neck = rot(8, 0, 3.12),
				LeftHip = posRot(0, 0.055, 0, 37.2, 2.7, 3.55),
				RightHip = rot(-4.95, -0.39, 4.44),
				LeftShoulder = rot(-20.46, 0, -10),
				RightShoulder = rot(22.37, 0, 12),
				Weapon = rot(-33.55, 0, 0),
			},
		},
		{
			time = 0.45,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.075, 0.041, -0.006, -10, 0, -3.53),
				Neck = rot(8, 0, 2.47),
				LeftHip = posRot(0, 0.035, 0, 42.18, 2.37, 2.61),
				RightHip = rot(-9.22, -0.57, 3.48),
				LeftShoulder = rot(-24.18, 0, -10),
				RightShoulder = rot(25.34, 0, 12),
				Weapon = rot(-34.19, 0, 0),
			},
		},
		{
			time = 0.4667,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.052, 0.002, -0.004, -10, 0, -2.44),
				Neck = rot(8, 0, 1.71),
				LeftHip = posRot(0, 0.017, 0, 45.04, 1.73, 1.72),
				RightHip = rot(-13.54, -0.57, 2.37),
				LeftShoulder = rot(-26.3, 0, -10),
				RightShoulder = rot(27.04, 0, 12),
				Weapon = rot(-34.56, 0, 0),
			},
		},
		{
			time = 0.4833,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.026, -0.051, -0.002, -10, 0, -1.25),
				Neck = rot(8, 0, 0.87),
				LeftHip = posRot(0, 0.004, 0, 45.28, 0.89, 0.88),
				RightHip = rot(-17.94, -0.38, 1.19),
				LeftShoulder = rot(-26.46, 0, -10),
				RightShoulder = rot(27.17, 0, 12),
				Weapon = rot(-34.59, 0, 0),
			},
		},
	},
	events = {
		{ time = 0, kind = "Footstep", data = { foot = "Left" } },
		{ time = 0.25, kind = "Footstep", data = { foot = "Right" } },
	},
}

return clip
