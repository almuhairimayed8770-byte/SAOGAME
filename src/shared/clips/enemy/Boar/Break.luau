--!strict
--[[
	enemy/Boar/Break: Guard Break, 3 s (combat.luau breakDuration): the kneel with the weapon
	dropping (section 10). The front legs fold back, the chest drops to the ground, the tusks dip
	into the dirt, the tail goes limp; then a panting cycle on the jaw and chest until the clip
	ends (the last key holds if Break outlasts it).
	Rig: Boar. Root X- pitches the nose down; Hip X- folds a leg back.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local function pant(time: number, open: boolean): Types.ClipKey
	return {
		time = time,
		easing = "SineInOut",
		joints = {
			Root = posRot(0, if open then -0.62 else -0.66, 0.1, -14, 0, 0),
			Jaw = rot(if open then -14 else -4, 0, 0),
			Neck = rot(if open then -24 else -28, 0, 0),
		},
	}
end

local clip: Types.ClipDef = {
	id = "enemy/Boar/Break",
	rig = "Boar",
	duration = 3,
	loop = false,
	layer = "FullBody",
	priority = 32,
	blendIn = 0.03,
	blendOut = 0.25,
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
			-- the front legs give
			time = 0.1,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.5, 0.1, -12, 0, 3),
				Neck = rot(-20, 4, 0),
				Jaw = rot(-8, 0, 0),
				FrontLeftHip = rot(-64, 0, 0),
				FrontRightHip = rot(-60, 0, 0),
				BackLeftHip = rot(8, 0, 0),
				BackRightHip = rot(10, 0, 0),
				TailJoint = rot(24, 0, 0),
			},
		},
		{
			-- settle into the kneel, tusks in the dirt
			time = 0.4,
			easing = "BackOut",
			joints = {
				Root = posRot(0, -0.66, 0.1, -14, 0, 0),
				Neck = rot(-28, 0, 0),
				Jaw = rot(-4, 0, 0),
				TuskLeft = rot(-4, 0, 0),
				TuskRight = rot(-4, 0, 0),
				FrontLeftHip = rot(-72, 0, 0),
				FrontRightHip = rot(-70, 0, 0),
				BackLeftHip = rot(12, 0, 0),
				BackRightHip = rot(12, 0, 0),
				TailJoint = rot(30, 0, 0),
			},
		},
		pant(0.8, true),
		pant(1.2, false),
		pant(1.6, true),
		pant(2.0, false),
		pant(2.4, true),
		pant(2.8, false),
		{
			time = 3,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.64, 0.1, -14, 0, 0),
				Jaw = rot(-6, 0, 0),
			},
		},
	},
	events = {
		{ time = 0.08, kind = "Voice", data = { name = "enemy.ChargerStagger" } },
		{ time = 0.42, kind = "Sfx", data = { name = "footsteps.LandHard" } },
	},
}

return clip
