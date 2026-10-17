--!strict
--[[
	Rig definitions (section 10). The Motor6D names here are the joint names every clip uses.

	PlayerR15 lists the 15 standard R15 Motor6Ds (kept so layered clothing and accessories work);
	the engine builds the character, so its part sizes come from the avatar. Enemy rigs are
	part-built placeholders assembled by src/server/world/RigBuilder.luau (D-009): every joint
	names its Part0, Part1, rest pose (C0, studs and degrees), placeholder size and color.

	Conventions: parts face -Z (Roblox forward). c0.pos is the joint's position relative to the
	Part0 center; C1 is the joint's position relative to the Part1 center (RigBuilder derives C1
	from `c1` when given, otherwise it uses the Part1 center so the part hangs from the joint).
]]

local Types = require(script.Parent.Parent.types)

export type PlaceholderJoint = Types.RigJoint & { c1: { pos: Types.Vec3, rot: Types.Vec3 }? }

export type Rig = Types.RigDef & {
	joints: { PlaceholderJoint },
	parts: { [string]: { size: Types.Vec3, color: string, shape: ("Block" | "Ball" | "Cylinder")? } }?,
	scale: { bodyHeight: number, bodyWidth: number, bodyDepth: number, head: number }?, -- player proportions
	walkSpeed: number?,
}

local Rigs: { [string]: Rig } = {
	PlayerR15 = {
		id = "PlayerR15",
		rootPart = "HumanoidRootPart",
		hipHeight = 2.0,
		placeholder = true,
		weaponGrip = "RightHand",
		trailParts = { "Weapon" },
		-- Anime proportions (section 10): slightly large head, long legs, narrow waist.
		scale = { bodyHeight = 1.08, bodyWidth = 0.92, bodyDepth = 0.95, head = 1.06 },
		joints = {
			{
				name = "Root",
				part0 = "HumanoidRootPart",
				part1 = "LowerTorso",
				c0 = { pos = { 0, -0.5, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "Waist",
				part0 = "LowerTorso",
				part1 = "UpperTorso",
				c0 = { pos = { 0, 0.2, 0 }, rot = { 0, 0, 0 } },
			},
			{ name = "Neck", part0 = "UpperTorso", part1 = "Head", c0 = { pos = { 0, 0.8, 0 }, rot = { 0, 0, 0 } } },
			{
				name = "LeftShoulder",
				part0 = "UpperTorso",
				part1 = "LeftUpperArm",
				c0 = { pos = { -1, 0.5, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "LeftElbow",
				part0 = "LeftUpperArm",
				part1 = "LeftLowerArm",
				c0 = { pos = { 0, -0.5, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "LeftWrist",
				part0 = "LeftLowerArm",
				part1 = "LeftHand",
				c0 = { pos = { 0, -0.5, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "RightShoulder",
				part0 = "UpperTorso",
				part1 = "RightUpperArm",
				c0 = { pos = { 1, 0.5, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "RightElbow",
				part0 = "RightUpperArm",
				part1 = "RightLowerArm",
				c0 = { pos = { 0, -0.5, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "RightWrist",
				part0 = "RightLowerArm",
				part1 = "RightHand",
				c0 = { pos = { 0, -0.5, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "LeftHip",
				part0 = "LowerTorso",
				part1 = "LeftUpperLeg",
				c0 = { pos = { -0.5, -0.2, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "LeftKnee",
				part0 = "LeftUpperLeg",
				part1 = "LeftLowerLeg",
				c0 = { pos = { 0, -0.6, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "LeftAnkle",
				part0 = "LeftLowerLeg",
				part1 = "LeftFoot",
				c0 = { pos = { 0, -0.6, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "RightHip",
				part0 = "LowerTorso",
				part1 = "RightUpperLeg",
				c0 = { pos = { 0.5, -0.2, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "RightKnee",
				part0 = "RightUpperLeg",
				part1 = "RightLowerLeg",
				c0 = { pos = { 0, -0.6, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "RightAnkle",
				part0 = "RightLowerLeg",
				part1 = "RightFoot",
				c0 = { pos = { 0, -0.6, 0 }, rot = { 0, 0, 0 } },
			},
			-- The weapon hangs from the right hand on its own Motor6D so Arts can re-grip it.
			{
				name = "Weapon",
				part0 = "RightHand",
				part1 = "Weapon",
				c0 = { pos = { 0, -0.3, 0 }, rot = { -90, 0, 0 } },
			},
		},
	},

	Boar = {
		id = "Boar",
		rootPart = "HumanoidRootPart",
		hipHeight = 1.6,
		placeholder = true,
		walkSpeed = 14,
		parts = {
			HumanoidRootPart = { size = { 2.4, 2.4, 5 }, color = "PlaceholderBoar" },
			Torso = { size = { 2.6, 2.4, 4.4 }, color = "PlaceholderBoar" },
			Head = { size = { 2, 2, 2.2 }, color = "PlaceholderBoar" },
			Snout = { size = { 1.2, 1, 1.2 }, color = "PlaceholderSteel" },
			TuskLeft = { size = { 0.25, 0.25, 0.9 }, color = "ApexEdge" },
			TuskRight = { size = { 0.25, 0.25, 0.9 }, color = "ApexEdge" },
			FrontLeftLeg = { size = { 0.8, 1.8, 0.8 }, color = "PlaceholderBoar" },
			FrontRightLeg = { size = { 0.8, 1.8, 0.8 }, color = "PlaceholderBoar" },
			BackLeftLeg = { size = { 0.8, 1.8, 0.8 }, color = "PlaceholderBoar" },
			BackRightLeg = { size = { 0.8, 1.8, 0.8 }, color = "PlaceholderBoar" },
			Tail = { size = { 0.3, 0.3, 1.2 }, color = "PlaceholderBoar" },
		},
		joints = {
			{
				name = "Root",
				part0 = "HumanoidRootPart",
				part1 = "Torso",
				c0 = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "Neck",
				part0 = "Torso",
				part1 = "Head",
				c0 = { pos = { 0, 0.4, -2.2 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 0, 1.1 }, rot = { 0, 0, 0 } },
			},
			{
				name = "Jaw",
				part0 = "Head",
				part1 = "Snout",
				c0 = { pos = { 0, -0.4, -1.1 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 0, 0.6 }, rot = { 0, 0, 0 } },
			},
			{
				name = "TuskLeft",
				part0 = "Head",
				part1 = "TuskLeft",
				c0 = { pos = { -0.6, -0.6, -1.1 }, rot = { 20, 0, 0 } },
				c1 = { pos = { 0, 0, 0.45 }, rot = { 0, 0, 0 } },
			},
			{
				name = "TuskRight",
				part0 = "Head",
				part1 = "TuskRight",
				c0 = { pos = { 0.6, -0.6, -1.1 }, rot = { 20, 0, 0 } },
				c1 = { pos = { 0, 0, 0.45 }, rot = { 0, 0, 0 } },
			},
			{
				name = "FrontLeftHip",
				part0 = "Torso",
				part1 = "FrontLeftLeg",
				c0 = { pos = { -0.9, -1.0, -1.4 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 0.9, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "FrontRightHip",
				part0 = "Torso",
				part1 = "FrontRightLeg",
				c0 = { pos = { 0.9, -1.0, -1.4 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 0.9, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "BackLeftHip",
				part0 = "Torso",
				part1 = "BackLeftLeg",
				c0 = { pos = { -0.9, -1.0, 1.4 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 0.9, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "BackRightHip",
				part0 = "Torso",
				part1 = "BackRightLeg",
				c0 = { pos = { 0.9, -1.0, 1.4 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 0.9, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "TailJoint",
				part0 = "Torso",
				part1 = "Tail",
				c0 = { pos = { 0, 0.6, 2.2 }, rot = { 30, 0, 0 } },
				c1 = { pos = { 0, 0, -0.6 }, rot = { 0, 0, 0 } },
			},
		},
	},

	Kobold = {
		id = "Kobold",
		rootPart = "HumanoidRootPart",
		hipHeight = 2.2,
		placeholder = true,
		walkSpeed = 10,
		weaponGrip = "RightArm",
		trailParts = { "Weapon" },
		parts = {
			HumanoidRootPart = { size = { 2, 2, 1 }, color = "PlaceholderKobold" },
			Torso = { size = { 2.2, 2.4, 1.2 }, color = "PlaceholderKobold" },
			Head = { size = { 1.5, 1.4, 1.5 }, color = "PlaceholderKobold" },
			LeftArm = { size = { 0.9, 2.2, 0.9 }, color = "PlaceholderKobold" },
			RightArm = { size = { 0.9, 2.2, 0.9 }, color = "PlaceholderKobold" },
			LeftLeg = { size = { 0.9, 2.2, 0.9 }, color = "PlaceholderKobold" },
			RightLeg = { size = { 0.9, 2.2, 0.9 }, color = "PlaceholderKobold" },
			Weapon = { size = { 0.3, 3.6, 1.2 }, color = "PlaceholderSteel" },
		},
		joints = {
			{
				name = "Root",
				part0 = "HumanoidRootPart",
				part1 = "Torso",
				c0 = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "Neck",
				part0 = "Torso",
				part1 = "Head",
				c0 = { pos = { 0, 1.2, 0 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, -0.7, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "LeftShoulder",
				part0 = "Torso",
				part1 = "LeftArm",
				c0 = { pos = { -1.55, 0.9, 0 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 0.9, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "RightShoulder",
				part0 = "Torso",
				part1 = "RightArm",
				c0 = { pos = { 1.55, 0.9, 0 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 0.9, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "LeftHip",
				part0 = "Torso",
				part1 = "LeftLeg",
				c0 = { pos = { -0.6, -1.2, 0 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 1.1, 0 }, rot = { 0, 0, 0 } },
			},
			{
				name = "RightHip",
				part0 = "Torso",
				part1 = "RightLeg",
				c0 = { pos = { 0.6, -1.2, 0 }, rot = { 0, 0, 0 } },
				c1 = { pos = { 0, 1.1, 0 }, rot = { 0, 0, 0 } },
			},
			-- Axe held in the right hand, blade forward.
			{
				name = "Weapon",
				part0 = "RightArm",
				part1 = "Weapon",
				c0 = { pos = { 0, -1.0, 0 }, rot = { -90, 0, 0 } },
				c1 = { pos = { 0, -1.4, 0 }, rot = { 0, 0, 0 } },
			},
		},
	},
}

return Rigs
