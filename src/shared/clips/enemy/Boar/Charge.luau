--!strict
--[[
	enemy/Boar/Charge: the Charger's attack (enemies.luau FrenzyBoar: windUp 0.6, strike 0.5,
	recovery 1.2). Section 9: a 0.6 s crouch, then a straight-line rush that turns slowly.

	  0.00-0.60  Anticipation: the crouch. Head down, weight back, the rear legs loaded under the
	             body, the tail flagged up: readable from behind (the raised tail, the dropped rear)
	             as well as from the front (the lowered tusks). Held, with a tremor, for the whole
	             wind-up.
	  0.60-0.65  Snap: the launch. The body stretches flat, head and tusks come up, rear legs fire.
	  0.65-0.70  Hold, then Settle: the first gallop stride springs in
	  0.70-1.10  the rush: gallop strides (the server moves the model; the clip carries no root)
	  0.60-1.20  hit window: opens on the launch snap with the trail and stays open through the rush
	             to the tusks (the server resolves the Charger's line at windUp + strike = 1.10 s)
	  1.20-2.30  Recovery: a skidding stop, then the slow turn (the head and body swing round)
	Rig: Boar. Root X- pitches the nose down; Neck X- lowers the head; Hip X+ swings a leg
	forward; TailJoint X- lifts the tail.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Boar/Charge",
	rig = "Boar",
	duration = 2.3,
	loop = false,
	layer = "FullBody",
	priority = 20,
	attack = true,
	hitStop = "Normal",
	blendIn = 0.08,
	blendOut = 0.2,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Neck = rot(-4, 0, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(2, 0, 0),
				FrontRightHip = rot(-2, 0, 0),
				BackLeftHip = rot(-2, 0, 0),
				BackRightHip = rot(2, 0, 0),
				TailJoint = rot(4, 0, 0),
			},
		},
		{
			-- drop into the crouch
			time = 0.12,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.35, 0.1, -8, 0, 0),
				Neck = rot(-30, 0, 0),
				Jaw = rot(5, 0, 0),
				FrontLeftHip = rot(-20, 0, 0),
				FrontRightHip = rot(-20, 0, 0),
				BackLeftHip = rot(26, 0, 0),
				BackRightHip = rot(26, 0, 0),
				TailJoint = rot(-22, 0, 0),
			},
		},
		{
			-- deeper, the rear loads
			time = 0.35,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.45, 0.16, -10, 0, 0),
				Neck = rot(-38, 0, 0),
				BackLeftHip = rot(31, 0, 0),
				BackRightHip = rot(31, 0, 0),
				TailJoint = rot(-30, 0, 0),
			},
		},
		{
			-- tremor in the rear legs
			time = 0.48,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.42, 0.14, -9, 0, 1),
				BackLeftHip = rot(28, 0, 0),
				BackRightHip = rot(30, 0, 0),
				TailJoint = rot(-27, 3, 0),
			},
		},
		{
			-- the last coil
			time = 0.6,
			easing = "QuadIn",
			joints = {
				Root = posRot(0, -0.5, 0.2, -11, 0, 0),
				Neck = rot(-42, 0, 0),
				BackLeftHip = rot(34, 0, 0),
				BackRightHip = rot(34, 0, 0),
				TailJoint = rot(-32, 0, 0),
			},
		},
		{
			-- the launch
			time = 0.65,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.08, -0.3, 6, 0, 0),
				Neck = rot(16, 0, 0),
				Jaw = rot(-16, 0, 0),
				FrontLeftHip = rot(42, 0, 0),
				FrontRightHip = rot(40, 0, 0),
				BackLeftHip = rot(-42, 0, 0),
				BackRightHip = rot(-42, 0, 0),
				TailJoint = rot(-8, 0, 0),
			},
		},
		{
			time = 0.7,
			easing = "Hold",
			joints = {
				Root = posRot(0, -0.08, -0.3, 6, 0, 0),
			},
		},
		{
			-- first gallop stride springs in
			time = 0.85,
			easing = "Spring",
			joints = {
				Root = posRot(0, -0.2, -0.2, -3, 0, 0),
				Neck = rot(4, 0, 0),
				FrontLeftHip = rot(-30, 0, 0),
				FrontRightHip = rot(-26, 0, 0),
				BackLeftHip = rot(36, 0, 0),
				BackRightHip = rot(36, 0, 0),
				TailJoint = rot(-14, 0, 0),
			},
		},
		{
			time = 0.95,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0.02, -0.3, 5, 0, 0),
				Neck = rot(10, 0, 0),
				FrontLeftHip = rot(40, 0, 0),
				FrontRightHip = rot(38, 0, 0),
				BackLeftHip = rot(-38, 0, 0),
				BackRightHip = rot(-40, 0, 0),
			},
		},
		{
			-- the tusks drive through
			time = 1.08,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.16, -0.26, 2, 0, 0),
				Neck = rot(18, 0, 0),
				Jaw = rot(-10, 0, 0),
				TuskLeft = rot(-6, 0, 0),
				TuskRight = rot(-6, 0, 0),
				FrontLeftHip = rot(-24, 0, 0),
				FrontRightHip = rot(-20, 0, 0),
				BackLeftHip = rot(34, 0, 0),
				BackRightHip = rot(34, 0, 0),
			},
		},
		{
			-- skid to a stop: front legs planted forward, rear dragging
			time = 1.3,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.14, 0, 5, 0, 0),
				Neck = rot(8, 0, 0),
				Jaw = rot(0, 0, 0),
				TuskLeft = rot(0, 0, 0),
				TuskRight = rot(0, 0, 0),
				FrontLeftHip = rot(32, 0, 0),
				FrontRightHip = rot(30, 0, 0),
				BackLeftHip = rot(-14, 0, 0),
				BackRightHip = rot(-16, 0, 0),
				TailJoint = rot(2, 0, 0),
			},
		},
		{
			-- the slow turn begins: head swings, body follows
			time = 1.65,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.04, 0, 0, 12, -2),
				Neck = rot(-4, 26, 0),
				FrontLeftHip = rot(10, 0, 0),
				FrontRightHip = rot(-12, 0, 0),
				BackLeftHip = rot(-6, 0, 0),
				BackRightHip = rot(8, 0, 0),
				TailJoint = rot(2, 22, 0),
			},
		},
		{
			time = 2.0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.02, 0, 0, 20, -3),
				Neck = rot(-6, 36, 0),
				FrontLeftHip = rot(-8, 0, 0),
				FrontRightHip = rot(10, 0, 0),
				BackLeftHip = rot(6, 0, 0),
				BackRightHip = rot(-6, 0, 0),
				TailJoint = rot(4, 10, 0),
			},
		},
		{
			time = 2.3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Neck = rot(-4, 0, 0),
				FrontLeftHip = rot(2, 0, 0),
				FrontRightHip = rot(-2, 0, 0),
				BackLeftHip = rot(-2, 0, 0),
				BackRightHip = rot(2, 0, 0),
				TailJoint = rot(4, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.1, kind = "Voice", data = { name = "enemy.ChargerWindUp" } },
		{ time = 0.6, kind = "TrailOn", data = { kind = "Basic" } },
		{ time = 0.6, kind = "SmearOn", data = { axis = "Z" } },
		{ time = 0.6, kind = "Voice", data = { name = "enemy.ChargerStrike" } },
		{ time = 0.6, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.6333, kind = "SmearOff" },
		{ time = 0.72, kind = "Footstep", data = { foot = "FrontLeft" } },
		{ time = 0.97, kind = "Footstep", data = { foot = "FrontRight" } },
		{ time = 1.2, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 1.22, kind = "TrailOff" },
		{ time = 1.25, kind = "PostMotionStart" },
		{ time = 1.32, kind = "Footstep", data = { foot = "FrontLeft" } },
	},
	beats = {
		Anticipation = { start = 0, finish = 0.6 },
		Snap = { start = 0.6, finish = 0.65 },
		Smear = { start = 0.6, finish = 0.6333 },
		Hold = { start = 0.65, finish = 0.7 },
		Settle = { start = 0.7, finish = 0.85 },
		Recovery = { start = 1.25, finish = 2.3 },
	},
}

return clip
