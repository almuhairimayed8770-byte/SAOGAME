--!strict
--[[
	enemy/Kobold/Overhead: the Brute's attack (enemies.luau KoboldAxeman: windUp 1.0, strike
	0.35, recovery 1.4). Section 9: a 1.0 s overhead with a yellow edge; the counter is a parry.

	  0.00-1.00  the wind-up: the axe rises high behind the head, the body twists to the right and
	             arches back, the free arm out for balance. Held, breathing, for the whole second:
	             readable from behind (the raised axe head, the twisted shoulders).
	  1.00-1.30  the final loading: up onto the toes, the axe a hair higher (QuadIn)
	  1.30-1.35  Snap: the chop. The whole body folds down behind the axe, the weight drops.
	  1.35-1.40  Hold, then Settle: the axe bites the ground and rebounds
	  1.30-1.50  hit window: opens on the snap's first frame with the trail and closes in the settle
	             (the server resolves the Brute's cone at windUp + strike = 1.35 s, inside it)
	  1.55-2.75  Recovery: the axe is stuck low; two tugs free it, then the stance returns
	Rig: Kobold. Root X+ arches back / X- bends forward; Shoulder X+ raises an arm forward and up;
	Weapon X- tips the axe head down.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "enemy/Kobold/Overhead",
	rig = "Kobold",
	duration = 2.75,
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
				Root = posRot(0, -0.05, 0, -8, 0, 0),
				Neck = rot(6, 0, 0),
				LeftShoulder = rot(6, 0, -10),
				RightShoulder = rot(10, 0, 12),
				LeftHip = rot(4, 0, -4),
				RightHip = rot(-4, 0, 4),
				Weapon = rot(-30, 0, 0),
			},
		},
		{
			-- the axe rises
			time = 0.2,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0, -0.02, 0, 8, -20, 0),
				Neck = rot(14, 20, 0),
				RightShoulder = rot(120, 0, 16),
				Weapon = rot(-20, 0, 0),
				LeftShoulder = rot(40, 0, -30),
				LeftHip = rot(14, 0, -4),
				RightHip = rot(-14, 0, 6),
			},
		},
		{
			-- at the top: twisted and arched, the free arm out
			time = 0.5,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.04, -0.1, 0.06, 14, -30, -3),
				Neck = rot(16, 28, 2),
				RightShoulder = rot(165, 0, 26),
				Weapon = rot(-30, 0, 0),
				LeftShoulder = rot(30, 0, -42),
				LeftHip = rot(16, 0, -4),
				RightHip = rot(-16, 0, 8),
			},
		},
		{
			-- the hold breathes: the axe head sways
			time = 0.8,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.05, -0.14, 0.07, 16, -31, -3),
				Neck = rot(15, 29, 2),
				RightShoulder = rot(170, 0, 24),
				Weapon = rot(-33, 0, -3),
			},
		},
		{
			time = 1.0,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.04, -0.12, 0.06, 15, -30, -3),
				RightShoulder = rot(168, 0, 26),
				Weapon = rot(-31, 0, 2),
			},
		},
		{
			-- the final loading: onto the toes, a hair higher
			time = 1.3,
			easing = "QuadIn",
			joints = {
				Root = posRot(0.06, -0.04, 0.1, 19, -36, -4),
				Neck = rot(10, 32, 2),
				RightShoulder = rot(176, 0, 28),
				Weapon = rot(-36, 0, 0),
				LeftShoulder = rot(24, 0, -48),
			},
		},
		{
			-- the chop
			time = 1.35,
			easing = "ExpoOut",
			joints = {
				Root = posRot(-0.04, -0.42, -0.14, -32, 16, 2),
				Neck = rot(-16, -12, 0),
				RightShoulder = rot(18, 0, 0),
				Weapon = rot(-74, 0, 0),
				LeftShoulder = rot(-32, 0, -14),
				LeftHip = rot(36, 0, -6),
				RightHip = rot(-26, 0, 8),
			},
		},
		{
			time = 1.4,
			easing = "Hold",
			joints = {
				Root = posRot(-0.04, -0.42, -0.14, -32, 16, 2),
			},
		},
		{
			-- the axe bites and rebounds
			time = 1.55,
			easing = "Spring",
			joints = {
				Root = posRot(-0.03, -0.38, -0.13, -27, 14, 2),
				Neck = rot(-12, -10, 0),
				RightShoulder = rot(24, 0, 2),
				Weapon = rot(-70, 0, 0),
				LeftShoulder = rot(-26, 0, -14),
			},
		},
		{
			-- stuck low: the first tug
			time = 1.9,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.03, -0.32, -0.12, -22, 12, 2),
				Neck = rot(-6, -8, 0),
				RightShoulder = rot(30, 0, 2),
				Weapon = rot(-72, 0, 0),
				LeftShoulder = rot(-16, 0, -16),
			},
		},
		{
			time = 2.15,
			easing = "QuadIn",
			joints = {
				Root = posRot(-0.03, -0.36, -0.13, -28, 13, 2),
				Neck = rot(-10, -8, 0),
				RightShoulder = rot(22, 0, 2),
			},
		},
		{
			-- the second tug frees it
			time = 2.4,
			easing = "BackOut",
			joints = {
				Root = posRot(-0.01, -0.16, -0.06, -10, 6, 1),
				Neck = rot(2, -4, 0),
				RightShoulder = rot(46, 0, 8),
				Weapon = rot(-42, 0, 0),
				LeftShoulder = rot(-4, 0, -14),
				LeftHip = rot(20, 0, -6),
				RightHip = rot(-14, 0, 6),
			},
		},
		{
			-- back to the stance
			time = 2.75,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.05, 0, -8, 0, 0),
				Neck = rot(6, 0, 0),
				RightShoulder = rot(10, 0, 12),
				Weapon = rot(-30, 0, 0),
				LeftShoulder = rot(6, 0, -10),
				LeftHip = rot(4, 0, -4),
				RightHip = rot(-4, 0, 4),
			},
		},
	},
	events = {
		{ time = 0.15, kind = "Voice", data = { name = "enemy.BruteWindUp" } },
		{ time = 1.3, kind = "TrailOn", data = { kind = "Basic" } },
		{ time = 1.3, kind = "SmearOn", data = { axis = "Y" } },
		{ time = 1.3, kind = "Sfx", data = { name = "whoosh.Large" } },
		{ time = 1.3, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 1.3333, kind = "SmearOff" },
		{ time = 1.37, kind = "Sfx", data = { name = "footsteps.LandHard" } },
		{ time = 1.5, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 1.52, kind = "TrailOff" },
		{ time = 1.55, kind = "PostMotionStart" },
		{ time = 2.4, kind = "Sfx", data = { name = "footsteps.LandSoft" } },
	},
	beats = {
		Anticipation = { start = 0, finish = 1.3 },
		Snap = { start = 1.3, finish = 1.35 },
		Smear = { start = 1.3, finish = 1.3333 },
		Hold = { start = 1.35, finish = 1.4 },
		Settle = { start = 1.4, finish = 1.55 },
		Recovery = { start = 1.55, finish = 2.75 },
	},
}

return clip
