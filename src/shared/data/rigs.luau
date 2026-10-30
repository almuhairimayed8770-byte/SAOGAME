--!strict
--[[
	Rig definitions (section 10). The joint names here are the names every clip uses. A joint is
	a Motor6D or an AnimationConstraint (src/shared/choreo/Joints.luau reads both): the same name,
	Part0 / Part1 and Transform either way.

	PlayerR15 lists the 15 standard R15 joints (kept so layered clothing and accessories work);
	the engine builds the character, so its part sizes and joint frames come from the avatar. Under
	the Avatar Joint Upgrade (the default) those 15 are AnimationConstraints whose C0 / C1 are the
	rig attachments; in older places they are Motor6Ds. Their c0 values below are the stand-in rest
	pose for Lune and the fallback rigs and are never written onto a live character's joints. The
	Weapon joint is always a Motor6D that WeaponBuilder adds, with its c0 as C0. Enemy rigs are
	part-built placeholders assembled by src/server/world/RigBuilder.luau (D-009) with a Motor6D
	per joint: every joint names its Part0, Part1, rest pose (C0, studs and degrees), placeholder
	size and color.

	Conventions: parts face -Z (Roblox forward). c0.pos is the joint's position relative to the
	Part0 center; C1 is the joint's position relative to the Part1 center (RigBuilder derives C1
	from `c1` when given, otherwise it uses the Part1 center so the part hangs from the joint).
]]

local Types = require(script.Parent.Parent.types)

export type PlaceholderJoint = Types.RigJoint & { c1: { pos: Types.Vec3, rot: Types.Vec3 }? }

-- What a walk-in stops at on an enemy rig (RigBuilder.addBlocker, D-198, D-237, D-315): upright
-- faces over the body and over each part it holds (trailParts), each the flat box over that part
-- as it stands at rest and in every pose of `clips` (the loops it stands in), posed every
-- sampleSeconds. A walk-in's body shell (BodyShell, item 236) meets each held part as heldSlices
-- oriented boxes, one over each slice of every clip (the face over its whole footprint stops a hand
-- where the part never is).
export type BlockerDef = { clips: { string }, sampleSeconds: number, heldSlices: number? }

-- The poses a rushing body is drawn in (RushWorld.posesOf, D-437): a wall is judged on the rest
-- pose and every pose of `clips` (posed every sampleSeconds), so the slam's stop leaves no pose
-- the clients draw in the face.
export type RushPosesDef = { clips: { string }, sampleSeconds: number }

-- The body shell a character carries (BodyShell.boxes, RigBuilder.playerShell, item 236): one box
-- per part of `parts` in the root's own space, over that part as it stands in every pose of the
-- stance's clips (`sheathed`, `drawn`), posed every sampleSeconds and padded padStuds on every
-- side. The local character's walk stops where a box touches an enemy's body face or what it
-- holds (WalkShell), so a walk-in ends with the arms and hands against the enemy, never inside.
export type ShellDef = {
	parts: { string },
	sheathed: { string },
	drawn: { string },
	sampleSeconds: number,
	padStuds: number,
}

export type Rig = Types.RigDef & {
	joints: { PlaceholderJoint },
	parts: { [string]: { size: Types.Vec3, color: string, shape: ("Block" | "Ball" | "Cylinder")? } }?,
	scale: { bodyHeight: number, bodyWidth: number, bodyDepth: number, head: number }?, -- player proportions
	walkSpeed: number?,
	blocker: BlockerDef?,
	rush: RushPosesDef?,
	shell: ShellDef?,
}

local Rigs: { [string]: Rig } = {
	PlayerR15 = {
		id = "PlayerR15",
		rootPart = "HumanoidRootPart",
		hipHeight = 2.0,
		placeholder = true,
		weaponGrip = "RightHand",
		trailParts = { "Weapon" },
		-- Item 236: the arms and hands the engine does not collide, boxed over the idle the
		-- stance stands in (BodyShell.boxes; WalkShell holds the walk where they touch). Without
		-- it a walk-in stopped with the drawn left hand 1.08 studs inside a side-on boar's torso
		-- and 0.53 inside a kobold's arm, the sheathed one 0.30 inside its axe.
		shell = {
			parts = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand" },
			sheathed = { "player/OneHandedSword/Idle" },
			drawn = { "player/OneHandedSword/IdleDrawn" },
			sampleSeconds = 1 / 30,
			padStuds = 0,
		},
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
			-- The weapon hangs from the right hand on its own Motor6D (whatever kind the R15 joints
			-- are) so Arts can re-grip it.
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
		-- Over the idle as well as the rest pose: its weight shift rolls the torso 0.12 out on the
		-- left flank and its head bob takes the snout 0.03 farther.
		blocker = { clips = { "enemy/Boar/Idle" }, sampleSeconds = 1 / 120 },
		-- Over the Charge as well as the rest pose (D-437): its gallop carries the snout up to 0.23
		-- past the rest pose, and the clip still plays at the slam's stop and through the daze.
		rush = { clips = { "enemy/Boar/Charge" }, sampleSeconds = 1 / 60 },
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
		-- Over the idle as well as the rest pose: it idles hunched, the head 0.5 ahead of its rest
		-- footprint and the arms out, the axe hanging 3.9 ahead at its right (its own face). The
		-- walk shell meets the axe as 8 boxes over the idle (item 236, WalkShell): a drawn walk-in
		-- 15 degrees off its head rests 5.49 from the root on the axe (one box over the whole idle:
		-- 5.58), and head-on 3.27 on its body face, inside the reach a basic hits at (dev.luau
		-- hitMatrix Kobold, 5.25); the face over the axe's whole footprint alone held it at 5.88.
		blocker = { clips = { "enemy/Kobold/Idle" }, sampleSeconds = 1 / 120, heldSlices = 8 },
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
