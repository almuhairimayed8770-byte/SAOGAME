--!strict
--[[
	player/OneHandedSword/GuardHit: a blocked hit. From the guard pose the blade is knocked back
	toward the chest in 3 frames (ExpoOut), the head snaps back, the torso gives; then a spring
	back into the guard. UpperBody so the legs stay under the locomotion layer.
	Re-key (D-381): it starts and ends on the re-keyed Guard pose; the block that takes the hit sits
	0.2 studs further right, so its arms stay off the chest (the sword forearm sat 0.57 inside the
	torso through the whole clip); a 0.2 s blend out (the 0.1 s one turned the sword hand 27 degrees
	in a frame).
	Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/GuardHit",
	rig = "PlayerR15",
	duration = 0.35,
	loop = false,
	layer = "UpperBody",
	priority = 12,
	blendIn = 0.02,
	blendOut = 0.2,
	keys = {
		{
			time = 0,
			easing = "QuadOut",
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
			-- the block takes the hit
			time = 0.05,
			easing = "ExpoOut",
			joints = {
				Waist = rot(4, -14, 2),
				Neck = rot(-10, 10, 0),
				RightShoulder = rot(34.3, 8.8, -3.5),
				RightElbow = rot(105.7, 0, 0),
				RightWrist = rot(7, -29.1, 61.5),
				Weapon = rot(-34, 0, -20),
				LeftShoulder = rot(26, -10.4, -10.9),
				LeftElbow = rot(104.6, 0, 0),
				LeftWrist = rot(-23, -1.6, -47.5),
			},
		},
		{
			time = 0.1,
			easing = "Hold",
			joints = {
				Waist = rot(4, -14, 2),
			},
		},
		{
			-- spring back into the guard
			time = 0.35,
			easing = "Spring",
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
	},
	events = {},
}

return clip
