--!strict
--[[
	enemy/Kobold/DeathFreeze: the 0.5 s freeze before the shatter (combat.luau deathFreeze).
	Additive: the animator freezes every other clock for this clip's duration (data/choreo.luau
	freezeClipSuffix) and this layers a fading tremor on top of the last pose.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function tremor(time: number, sign: number, scale: number): Types.ClipKey
	return {
		time = time,
		easing = "SineInOut",
		joints = {
			Root = rot(0.6 * sign * scale, 0, 0.9 * sign * scale),
			Neck = rot(1.0 * sign * scale, 0.5 * sign * scale, 0),
			RightShoulder = rot(1.2 * sign * scale, 0, 0.5 * sign * scale),
			LeftShoulder = rot(-0.8 * sign * scale, 0, 0),
			Weapon = rot(1.8 * sign * scale, 0, 0.6 * sign * scale),
		},
	}
end

local clip: Types.ClipDef = {
	id = "enemy/Kobold/DeathFreeze",
	rig = "Kobold",
	duration = 0.5,
	loop = false,
	layer = "Additive",
	priority = 100,
	blendIn = 0,
	blendOut = 0,
	keys = {
		tremor(0, 0, 0),
		tremor(0.05, 1, 1),
		tremor(0.1, -1, 1),
		tremor(0.15, 1, 0.9),
		tremor(0.2, -1, 0.8),
		tremor(0.25, 1, 0.7),
		tremor(0.3, -1, 0.6),
		tremor(0.35, 1, 0.45),
		tremor(0.4, -1, 0.3),
		tremor(0.45, 1, 0.15),
		tremor(0.5, 0, 0),
	},
	events = {},
}

return clip
