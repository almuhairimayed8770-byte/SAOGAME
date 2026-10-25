--!strict
--[[
	player/OneHandedSword/FlinchFront: additive hit reaction, a hit from the front: the head and
	chest snap back, the shoulders hunch. The hit pose shows from the clip's first frame and holds
	through the strike frame and the next (0.04 s), then springs back through a small counter-swing
	to zero at the end. An impact frame: the blow reads on the frame it lands at any refresh rate,
	and also while the rig's clock stands still under it (a frozen Art stance, a hit-stop, D-294),
	where a snap into the pose stood at its rest key and showed nothing. Rides on the Additive layer
	so it works over walking, guarding or an Art.
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
	id = "player/OneHandedSword/FlinchFront",
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
				Root = posRot(0, 0, 0.12, 0, 0, 0),
				Waist = rot(12, 0, 0),
				Neck = rot(15, 0, 0),
				LeftShoulder = rot(-1, 0, -8),
				LeftHip = rot(8, 0, 0),
				RightHip = rot(-4, 0, 0),
			},
		},
		{
			-- held over the strike frame and the next, then the spring back
			time = 0.04,
			easing = "Hold",
			joints = {
				Root = posRot(0, 0, 0.12, 0, 0, 0),
				Waist = rot(12, 0, 0),
				Neck = rot(15, 0, 0),
				LeftShoulder = rot(-1, 0, -8),
				LeftHip = rot(8, 0, 0),
				RightHip = rot(-4, 0, 0),
			},
		},
		{
			time = 0.16,
			easing = "BackOut",
			joints = {
				Root = posRot(0, 0, -0.03, 0, 0, 0),
				Waist = rot(-3, 0, 0),
				Neck = rot(-4.8, 0, 0),
				LeftShoulder = rot(1.2, 0, 0.8),
				LeftHip = rot(0, 0, 0),
				RightHip = rot(0, 0, 0),
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
			},
		},
	},
	events = {},
}

return clip
