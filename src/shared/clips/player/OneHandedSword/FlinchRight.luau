--!strict
--[[
	player/OneHandedSword/FlinchRight: additive hit reaction, a hit from the right: the torso is
	shoved left and turns away, the head follows, the left leg braces. The hit pose shows from the
	clip's first frame and holds through the strike frame and the next (0.04 s), then springs back
	through a small counter-swing to zero at the end. An impact frame: the blow reads on the frame
	it lands at any refresh rate, and also while the rig's clock stands still under it (a frozen Art
	stance, a hit-stop, D-294), where a snap into the pose stood at its rest key and showed nothing.
	Rides on the Additive layer so it works over walking, guarding or an Art.
	Re-key (D-387): the legs carry additive keys that hold the feet where the stance under the
	flinch has them (the drawn idle's places): the hips' shift slid the rear foot 0.17 in
	a frame and 0.36 over the plant.
	The neck keeps 80% of its whip (the head turned 20 degrees in the strike frame).
	The sword arm rides the torso (no right shoulder key): a hit taken during Draw or Sheathe then
	keeps the blade in line with its sheath.
	Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/FlinchRight",
	rig = "PlayerR15",
	duration = 0.3,
	loop = false,
	layer = "Additive",
	priority = 5,
	blendIn = 0,
	blendOut = 0.05,
	keys = {
		{
			-- the hit: the pose the blow throws the body into, on the first frame
			time = 0,
			easing = "Hold",
			joints = {
				Root = posRot(-0.15, 0, 0, 0, 0, 0),
				Waist = rot(-4, 6, 9),
				Neck = rot(0, 0, 8),
				LeftShoulder = rot(0, 0, -10),
				LeftHip = rot(1.6, 0.8, 4.5),
				RightHip = rot(-3.7, 0.4, 4.5),
				LeftAnkle = rot(1.5, 0.4, -4.6),
				LeftKnee = rot(-3.1, 0, 0),
				RightAnkle = rot(-3.4, -1.8, -4.2),
				RightKnee = rot(6.9, 0, 0),
			},
		},
		{
			-- held over the strike frame and the next, then the spring back
			time = 0.04,
			easing = "Hold",
			joints = {
				Root = posRot(-0.15, 0, 0, 0, 0, 0),
				Waist = rot(-4, 6, 9),
				Neck = rot(0, 0, 8),
				LeftShoulder = rot(0, 0, -10),
				LeftHip = rot(1.6, 0.8, 4.5),
				RightHip = rot(-3.7, 0.4, 4.5),
				LeftAnkle = rot(1.5, 0.4, -4.6),
				LeftKnee = rot(-3.1, 0, 0),
				RightAnkle = rot(-3.4, -1.8, -4.2),
				RightKnee = rot(6.9, 0, 0),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(0.03, 0, 0, 0, 0, 0),
				Waist = rot(1, -1.5, -3),
				Neck = rot(0, 0, -2.4),
				LeftShoulder = rot(0, 0, 0.6),
				LeftHip = rot(-0.6, -0.1, -0.9),
				RightHip = rot(0.4, -0.2, -0.9),
				LeftAnkle = rot(-0.6, -0.1, 0.9),
				LeftKnee = rot(1.2, 0, 0),
				RightAnkle = rot(0.4, 0.4, 0.9),
				RightKnee = rot(-0.8, 0, 0),
			},
		},
		{
			time = 0.3,
			easing = "Spring",
			joints = {
				Root = posRot(0, 0, 0, 0, 0, 0),
				Waist = rot(0, 0, 0),
				Neck = rot(0, 0, 0),
				LeftShoulder = rot(0, 0, 0),
				LeftAnkle = rot(0, 0, 0),
				LeftHip = rot(0, 0, 0),
				LeftKnee = rot(0, 0, 0),
				RightAnkle = rot(0, 0, 0),
				RightHip = rot(0, 0, 0),
				RightKnee = rot(0, 0, 0),
			},
		},
	},
	events = {},
}

return clip
