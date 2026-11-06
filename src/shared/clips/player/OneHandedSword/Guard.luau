--!strict
--[[
	player/OneHandedSword/Guard: the guard loop on the UpperBody layer so the legs keep walking.
	The blade stands across the body in front of the face, the free hand braces the flat near
	the guard, the torso squares to the threat and sinks. A 2 s breath keeps it alive.
	Re-key (D-379): both hands sit 0.2 studs further right and 0.1 higher, the arms re-solved to
	them, so the sword forearm stays off the chest (it sat 0.35 inside it). Parry, GuardHit and
	GuardBreak start from this pose (their key 0 is the Guard's).
	Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/Guard",
	rig = "PlayerR15",
	duration = 2,
	loop = true,
	layer = "UpperBody",
	priority = 10,
	blendIn = 0.08,
	blendOut = 0.15,
	keys = {
		{
			time = 0,
			easing = "SineInOut",
			joints = {
				Waist = rot(-10, -4, 0),
				Neck = rot(6, 4, 0),
				RightShoulder = rot(60.9, 6.4, -6.3),
				RightElbow = rot(90.6, 0, 0),
				RightWrist = rot(-4.4, -22.3, 47.6),
				Weapon = rot(-38, 0, -16),
				LeftShoulder = rot(43, -9.5, -4.6),
				LeftElbow = rot(92.5, 0, 0),
				LeftWrist = rot(-28.5, 1.1, -46.1),
			},
		},
		{
			time = 1,
			easing = "SineInOut",
			joints = {
				Waist = rot(-9, -4, 0),
				RightShoulder = rot(61.9, 6.4, -6.3),
				LeftShoulder = rot(44, -9.5, -4.6),
			},
		},
	},
	events = {},
}

return clip
