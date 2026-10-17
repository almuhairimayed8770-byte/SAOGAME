--!strict
--[[
	player/OneHandedSword/Breathe: the Additive micro-motion that never stops (section 10 beat 6:
	post-motion is a person caught in a stance, not a paused game). A 3.6 s breath on the chest and
	head and a faster blade tremor on the wrist and weapon. Values are degrees added on top of
	whatever the other layers produce.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/Breathe",
	rig = "PlayerR15",
	duration = 3.6,
	loop = true,
	layer = "Additive",
	priority = 0,
	blendIn = 0.5,
	blendOut = 0.2,
	keys = {
		{
			time = 0,
			easing = "SineInOut",
			joints = {
				Waist = rot(-1, 0, 0),
				Neck = rot(0.6, 0, 0),
				LeftShoulder = rot(0, 0, 0.8),
				RightShoulder = rot(0, 0, -0.8),
				RightWrist = rot(0.4, 0, 0),
				Weapon = rot(0.6, 0, 0.3),
			},
		},
		{
			time = 0.45,
			easing = "SineInOut",
			joints = {
				RightWrist = rot(-0.5, 0, 0.3),
				Weapon = rot(-0.8, 0, -0.4),
			},
		},
		{
			time = 0.9,
			easing = "SineInOut",
			joints = {
				RightWrist = rot(0.6, 0, -0.2),
				Weapon = rot(0.9, 0, 0.2),
			},
		},
		{
			time = 1.35,
			easing = "SineInOut",
			joints = {
				RightWrist = rot(-0.3, 0, 0.4),
				Weapon = rot(-0.5, 0, 0.5),
			},
		},
		{
			-- top of the breath: chest rises, shoulders lift
			time = 1.8,
			easing = "SineInOut",
			joints = {
				Waist = rot(1, 0, 0),
				Neck = rot(-0.6, 0, 0),
				LeftShoulder = rot(0, 0, -0.8),
				RightShoulder = rot(0, 0, 0.8),
				RightWrist = rot(0.5, 0, -0.3),
				Weapon = rot(0.7, 0, -0.3),
			},
		},
		{
			time = 2.25,
			easing = "SineInOut",
			joints = {
				RightWrist = rot(-0.6, 0, 0.2),
				Weapon = rot(-0.9, 0, 0.4),
			},
		},
		{
			time = 2.7,
			easing = "SineInOut",
			joints = {
				RightWrist = rot(0.3, 0, -0.4),
				Weapon = rot(0.5, 0, -0.5),
			},
		},
		{
			time = 3.15,
			easing = "SineInOut",
			joints = {
				RightWrist = rot(-0.4, 0, 0.1),
				Weapon = rot(-0.6, 0, 0.2),
			},
		},
	},
	events = {},
}

return clip
