--!strict
--[[
	player/OneHandedSword/DeathFreeze: the 0.5 s freeze before the shatter (combat.luau
	deathFreeze). Additive: the rig holds whatever pose it died in (the animator freezes every
	other clock for this clip's duration, data/choreo.luau freezeClipSuffix) and this layers a
	fine tremor over it, fading out as the body locks.
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
			Waist = rot(0, 0, 0.9 * sign * scale),
			Neck = rot(0.7 * sign * scale, 0, -0.5 * sign * scale),
			RightWrist = rot(1.2 * sign * scale, 0, 0),
			Weapon = rot(1.6 * sign * scale, 0, 0.8 * sign * scale),
			LeftWrist = rot(-0.8 * sign * scale, 0, 0),
			LeftKnee = rot(0.6 * sign * scale, 0, 0),
			RightKnee = rot(-0.6 * sign * scale, 0, 0),
		},
	}
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/DeathFreeze",
	rig = "PlayerR15",
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
