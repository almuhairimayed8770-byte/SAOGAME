--!strict
--[[
	enemy/Boar/Walk: a 0.7 s trot. Diagonal leg pairs swing together (front-left with back-right),
	the body bobs, the head nods against the stride, the tail flicks. Footsteps on the plants.
	Rig: Boar. Hip X+ swings a leg forward.
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
	duration = 0.7,
	loop = true,
	layer = "Base",
	priority = 0,
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- front-left and back-right forward, planted
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.04, 0, 0, 0, 2),
				Neck = rot(-8, 3, 0),
				Jaw = rot(0, 0, 0),
				FrontLeftHip = rot(26, 0, 0),
				FrontRightHip = rot(-22, 0, 0),
				BackLeftHip = rot(-24, 0, 0),
				BackRightHip = rot(26, 0, 0),
				TailJoint = rot(0, 10, 0),
			},
		},
		{
			-- passing, body high
			time = 0.175,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.05, 0, -1, 0, 0),
				Neck = rot(-3, 0, 0),
				FrontLeftHip = rot(4, 0, 0),
				FrontRightHip = rot(2, 0, 0),
				BackLeftHip = rot(2, 0, 0),
				BackRightHip = rot(4, 0, 0),
				TailJoint = rot(-4, 0, 0),
			},
		},
		{
			-- front-right and back-left forward, planted
			time = 0.35,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.04, 0, 0, 0, -2),
				Neck = rot(-8, -3, 0),
				FrontLeftHip = rot(-22, 0, 0),
				FrontRightHip = rot(26, 0, 0),
				BackLeftHip = rot(26, 0, 0),
				BackRightHip = rot(-24, 0, 0),
				TailJoint = rot(0, -10, 0),
			},
		},
		{
			time = 0.525,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.05, 0, -1, 0, 0),
				Neck = rot(-3, 0, 0),
				FrontLeftHip = rot(2, 0, 0),
				FrontRightHip = rot(4, 0, 0),
				BackLeftHip = rot(4, 0, 0),
				BackRightHip = rot(2, 0, 0),
				TailJoint = rot(-4, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.02, kind = "Footstep", data = { foot = "FrontLeft" } },
		{ time = 0.37, kind = "Footstep", data = { foot = "FrontRight" } },
	},
}

return clip
