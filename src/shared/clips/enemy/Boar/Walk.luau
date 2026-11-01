--!strict
--[[
	enemy/Boar/Walk: a 0.3 s trot on the boar's rigid legs (D-482), paced to rigs.luau Boar walkSpeed
	14 (RigDriver plays it at speed / walkSpeed). Diagonal pairs (front-left with back-right) plant
	together: each planted leg rolls over its sole, heel edge then toe edge, under a hip that moves
	forward at the walk's speed, so the edge on the field holds its place (33.2 deg forward to 33.2
	back, 2.10 studs a stance). The body rides the stiff legs' arc, 0.074 studs below to 0.044 above
	the stance height. The other pair swings through, its hips drawn 0.20 studs up into the body at
	mid-swing (a leg with no knee lifts its sole that way), so the swinging sole clears the field by
	0.042 or more. The head nods against the bob, the tail swishes once a stride. Footsteps on the
	plants.
	Generated: one key a 60 fps frame (the stance angle solved from the distance walked). Rig: Boar.
	Hip X+ swings a leg forward; a hip's pos Y draws the leg up into the body.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Boar/Walk",
	rig = "Boar",
	duration = 0.3,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- front-left and back-right touch down, front-right and back-left lift
			time = 0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.074, 0, 0, 0, 0),
				Neck = rot(-4.51, 2.5, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(33.17, 0, 0),
				FrontRightHip = rot(-33.17, 0, 0),
				BackLeftHip = rot(-33.17, 0, 0),
				BackRightHip = rot(33.17, 0, 0),
				TailJoint = rot(-6, 12, 0),
			},
		},
		{
			time = 0.0167,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.004, 0, 0, 0, 0),
				Neck = rot(-5.92, 2.35, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(25.59, 0, 0),
				FrontRightHip = posRot(0, 0.023, 0, -36.25, 0, 0),
				BackLeftHip = posRot(0, 0.023, 0, -36.25, 0, 0),
				BackRightHip = rot(25.59, 0, 0),
				TailJoint = rot(-6, 11.28, 0),
			},
		},
		{
			time = 0.0333,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.035, 0, 0, 0, 0),
				Neck = rot(-6.7, 1.92, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(18.23, 0, 0),
				FrontRightHip = posRot(0, 0.083, 0, -31.49, 0, 0),
				BackLeftHip = posRot(0, 0.083, 0, -31.49, 0, 0),
				BackRightHip = rot(18.23, 0, 0),
				TailJoint = rot(-6, 9.19, 0),
			},
		},
		{
			time = 0.05,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.043, 0, 0, 0, 0),
				Neck = rot(-6.86, 1.25, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(10.97, 0, 0),
				FrontRightHip = posRot(0, 0.15, 0, -21.14, 0, 0),
				BackLeftHip = posRot(0, 0.15, 0, -21.14, 0, 0),
				BackRightHip = rot(10.97, 0, 0),
				TailJoint = rot(-6, 6, 0),
			},
		},
		{
			time = 0.0667,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.022, 0, 0, 0, 0),
				Neck = rot(-6.44, 0.43, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(3.69, 0, 0),
				FrontRightHip = posRot(0, 0.194, 0, -7.42, 0, 0),
				BackLeftHip = posRot(0, 0.194, 0, -7.42, 0, 0),
				BackRightHip = rot(3.69, 0, 0),
				TailJoint = rot(-6, 2.08, 0),
			},
		},
		{
			time = 0.0833,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.022, 0, 0, 0, 0),
				Neck = rot(-6.44, -0.43, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(-3.69, 0, 0),
				FrontRightHip = posRot(0, 0.194, 0, 7.42, 0, 0),
				BackLeftHip = posRot(0, 0.194, 0, 7.42, 0, 0),
				BackRightHip = rot(-3.69, 0, 0),
				TailJoint = rot(-6, -2.08, 0),
			},
		},
		{
			time = 0.1,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.043, 0, 0, 0, 0),
				Neck = rot(-6.86, -1.25, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(-10.97, 0, 0),
				FrontRightHip = posRot(0, 0.15, 0, 21.14, 0, 0),
				BackLeftHip = posRot(0, 0.15, 0, 21.14, 0, 0),
				BackRightHip = rot(-10.97, 0, 0),
				TailJoint = rot(-6, -6, 0),
			},
		},
		{
			time = 0.1167,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.035, 0, 0, 0, 0),
				Neck = rot(-6.7, -1.92, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(-18.23, 0, 0),
				FrontRightHip = posRot(0, 0.083, 0, 31.49, 0, 0),
				BackLeftHip = posRot(0, 0.083, 0, 31.49, 0, 0),
				BackRightHip = rot(-18.23, 0, 0),
				TailJoint = rot(-6, -9.19, 0),
			},
		},
		{
			time = 0.1333,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.004, 0, 0, 0, 0),
				Neck = rot(-5.92, -2.35, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(-25.59, 0, 0),
				FrontRightHip = posRot(0, 0.023, 0, 36.25, 0, 0),
				BackLeftHip = posRot(0, 0.023, 0, 36.25, 0, 0),
				BackRightHip = rot(-25.59, 0, 0),
				TailJoint = rot(-6, -11.28, 0),
			},
		},
		{
			-- front-right and back-left touch down, front-left and back-right lift
			time = 0.15,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.074, 0, 0, 0, 0),
				Neck = rot(-4.51, -2.5, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(-33.17, 0, 0),
				FrontRightHip = rot(33.17, 0, 0),
				BackLeftHip = rot(33.17, 0, 0),
				BackRightHip = rot(-33.17, 0, 0),
				TailJoint = rot(-6, -12, 0),
			},
		},
		{
			time = 0.1667,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.004, 0, 0, 0, 0),
				Neck = rot(-5.92, -2.35, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = posRot(0, 0.023, 0, -36.25, 0, 0),
				FrontRightHip = rot(25.59, 0, 0),
				BackLeftHip = rot(25.59, 0, 0),
				BackRightHip = posRot(0, 0.023, 0, -36.25, 0, 0),
				TailJoint = rot(-6, -11.28, 0),
			},
		},
		{
			time = 0.1833,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.035, 0, 0, 0, 0),
				Neck = rot(-6.7, -1.92, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = posRot(0, 0.083, 0, -31.49, 0, 0),
				FrontRightHip = rot(18.23, 0, 0),
				BackLeftHip = rot(18.23, 0, 0),
				BackRightHip = posRot(0, 0.083, 0, -31.49, 0, 0),
				TailJoint = rot(-6, -9.19, 0),
			},
		},
		{
			time = 0.2,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.043, 0, 0, 0, 0),
				Neck = rot(-6.86, -1.25, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = posRot(0, 0.15, 0, -21.14, 0, 0),
				FrontRightHip = rot(10.97, 0, 0),
				BackLeftHip = rot(10.97, 0, 0),
				BackRightHip = posRot(0, 0.15, 0, -21.14, 0, 0),
				TailJoint = rot(-6, -6, 0),
			},
		},
		{
			time = 0.2167,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.022, 0, 0, 0, 0),
				Neck = rot(-6.44, -0.43, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = posRot(0, 0.194, 0, -7.42, 0, 0),
				FrontRightHip = rot(3.69, 0, 0),
				BackLeftHip = rot(3.69, 0, 0),
				BackRightHip = posRot(0, 0.194, 0, -7.42, 0, 0),
				TailJoint = rot(-6, -2.08, 0),
			},
		},
		{
			time = 0.2333,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.022, 0, 0, 0, 0),
				Neck = rot(-6.44, 0.43, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = posRot(0, 0.194, 0, 7.42, 0, 0),
				FrontRightHip = rot(-3.69, 0, 0),
				BackLeftHip = rot(-3.69, 0, 0),
				BackRightHip = posRot(0, 0.194, 0, 7.42, 0, 0),
				TailJoint = rot(-6, 2.08, 0),
			},
		},
		{
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.043, 0, 0, 0, 0),
				Neck = rot(-6.86, 1.25, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = posRot(0, 0.15, 0, 21.14, 0, 0),
				FrontRightHip = rot(-10.97, 0, 0),
				BackLeftHip = rot(-10.97, 0, 0),
				BackRightHip = posRot(0, 0.15, 0, 21.14, 0, 0),
				TailJoint = rot(-6, 6, 0),
			},
		},
		{
			time = 0.2667,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.035, 0, 0, 0, 0),
				Neck = rot(-6.7, 1.92, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = posRot(0, 0.083, 0, 31.49, 0, 0),
				FrontRightHip = rot(-18.23, 0, 0),
				BackLeftHip = rot(-18.23, 0, 0),
				BackRightHip = posRot(0, 0.083, 0, 31.49, 0, 0),
				TailJoint = rot(-6, 9.19, 0),
			},
		},
		{
			time = 0.2833,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.004, 0, 0, 0, 0),
				Neck = rot(-5.92, 2.35, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = posRot(0, 0.023, 0, 36.25, 0, 0),
				FrontRightHip = rot(-25.59, 0, 0),
				BackLeftHip = rot(-25.59, 0, 0),
				BackRightHip = posRot(0, 0.023, 0, 36.25, 0, 0),
				TailJoint = rot(-6, 11.28, 0),
			},
		},
	},
	events = {
		{ time = 0, kind = "Footstep", data = { foot = "FrontLeft" } },
		{ time = 0.15, kind = "Footstep", data = { foot = "FrontRight" } },
	},
}

return clip
