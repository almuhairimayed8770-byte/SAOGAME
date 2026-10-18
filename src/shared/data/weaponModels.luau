--!strict
--[[
	Placeholder weapon geometry (section 19 asset pipeline, D-009). Until the weapon meshes in
	assets.luau are uploaded, WeaponBuilder assembles every weapon from three parts: a blade part
	named "Weapon" (the part Smear scales, Trails attaches to and HitSweep sweeps), a guard and a
	grip welded to it. The numbers here are the stand-in's shape per weapon category; the combat
	numbers (reach, trail width, trail color) stay in weapons.luau.

	Blade convention: the blade part's long axis is +Y with the tip at +Y and the guard at -Y, so
	the rigs.luau PlayerR15 "Weapon" joint (C0 rotated -90 degrees about X) points it forward out
	of the hand. The hold point (where the Motor6D's C1 puts the hand) is the center of the grip:
	`WeaponModels.holdOffset(category)` studs below the blade center along -Y.

	Sheaths: a category with a `sheaths` row carries its weapon on the body out of combat. The row
	names the body part, the Weapon joint's C0 on that part while sheathed (the hold point; the
	joint's +Y runs down the blade to the tip, as in the hand) and the scabbard's shape. The server
	welds a scabbard there and keeps the sword in the hand; each client moves the sword between
	hand and back from the Drawn attribute.

	Units: studs and degrees. Colors are palette tokens.
]]

local Types = require(script.Parent.Parent.types)

export type Blade = { length: number, width: number, thickness: number }
export type Guard = { width: number, height: number, depth: number } -- height runs along the blade axis
export type Grip = { length: number, width: number }
export type CategoryModel = {
	blade: Blade,
	guard: Guard,
	grip: Grip,
	shape: ("Block" | "Ball" | "Cylinder")?, -- the blade part's shape (Block when nil)
	note: string,
}
export type SheathMount = {
	part: string, -- the body part that carries the scabbard and the sheathed sword (a PlayerR15 part)
	-- The Weapon joint's C0 on `part` while sheathed: the grip's center (the hold point) in the
	-- part's space. The joint's +Y runs down the blade to the tip, as in the hand. Studs, degrees.
	mount: { pos: Types.Vec3, rot: Types.Vec3 },
	scabbard: { wall: number, clearance: number, color: string },
}

local WeaponModels = {
	-- Names the rest of the game relies on (ARCHITECTURE "Rigs, weapons and joints").
	modelName = "Weapon",
	bladePart = "Weapon",
	guardPart = "Guard",
	gripPart = "Grip",
	-- The Motor6D RightHand -> Weapon (a Motor6D even when the R15 joints are AnimationConstraints);
	-- its C0 is the rigs.luau PlayerR15 joint.
	motorName = "Weapon",
	attachments = { grip = "WeaponGrip", trailStart = "TrailStart", trailEnd = "TrailEnd" },
	lightName = "ActivationLight",
	trailName = "Trail",
	tag = "Placeholder",
	material = "SmoothPlastic",
	colors = { blade = "PlaceholderSteel", guard = "PlaceholderSteel", grip = "PlaceholderWood" },

	-- Attributes WeaponBuilder writes: on the weapon Model (id and category) and on the character.
	attributes = { weaponId = "WeaponId", category = "WeaponCategory" },

	partsPerWeapon = 3, -- blade, guard, grip

	categories = {
		OneHandedSword = {
			blade = { length = 3.2, width = 0.32, thickness = 0.1 },
			guard = { width = 1.0, height = 0.18, depth = 0.3 },
			grip = { length = 0.8, width = 0.22 },
			note = "straight blade, cross guard",
		},
		Rapier = {
			blade = { length = 3.6, width = 0.16, thickness = 0.08 },
			guard = { width = 0.7, height = 0.22, depth = 0.7 },
			grip = { length = 0.7, width = 0.2 },
			note = "needle blade, cup guard",
		},
		TwoHandedSword = {
			blade = { length = 4.6, width = 0.5, thickness = 0.14 },
			guard = { width = 1.6, height = 0.22, depth = 0.36 },
			grip = { length = 1.3, width = 0.26 },
			note = "wide blade, long two-hand grip",
		},
		Katana = {
			blade = { length = 3.4, width = 0.26, thickness = 0.08 },
			guard = { width = 0.6, height = 0.12, depth = 0.6 },
			grip = { length = 1.0, width = 0.22 },
			note = "slim blade, round guard, long grip",
		},
		Dagger = {
			blade = { length = 1.4, width = 0.24, thickness = 0.08 },
			guard = { width = 0.6, height = 0.12, depth = 0.24 },
			grip = { length = 0.6, width = 0.2 },
			note = "short blade",
		},
		Spear = {
			blade = { length = 6.0, width = 0.22, thickness = 0.22 },
			guard = { width = 0.4, height = 0.1, depth = 0.4 },
			grip = { length = 2.6, width = 0.2 },
			note = "the upper shaft and head as one part; the collar is the guard",
		},
		Axe = {
			blade = { length = 3.0, width = 0.3, thickness = 1.1 },
			guard = { width = 0.5, height = 0.14, depth = 0.5 },
			grip = { length = 1.0, width = 0.24 },
			note = "one slab: the head reads from the depth, as the Kobold's axe in rigs.luau",
		},
		Mace = {
			blade = { length = 2.4, width = 0.6, thickness = 0.6 },
			guard = { width = 0.5, height = 0.14, depth = 0.5 },
			grip = { length = 1.0, width = 0.24 },
			note = "a heavy head and upper shaft",
		},
		Shield = {
			blade = { length = 2.2, width = 0.16, thickness = 2.2 },
			guard = { width = 0.5, height = 0.1, depth = 0.5 },
			grip = { length = 0.5, width = 0.24 },
			shape = "Cylinder",
			note = "a round buckler disc; the bash arc runs along its rim",
		},
		MartialArts = {
			blade = { length = 0.7, width = 0.6, thickness = 0.5 },
			guard = { width = 0.5, height = 0.04, depth = 0.5 },
			grip = { length = 0.3, width = 0.4 },
			note = "hand wraps: a knuckle block so trails and sweeps have a part",
		},
		TwinFang = {
			blade = { length = 2.9, width = 0.3, thickness = 0.1 },
			guard = { width = 0.9, height = 0.16, depth = 0.28 },
			grip = { length = 0.8, width = 0.22 },
			note = "the right-hand blade of the pair (the left arrives with the Dual Wielder rig)",
		},
		AegisBlade = {
			blade = { length = 3.4, width = 0.42, thickness = 0.12 },
			guard = { width = 1.3, height = 0.2, depth = 0.34 },
			grip = { length = 0.9, width = 0.24 },
			note = "broad blade; the tower shield mount is Phase 1",
		},
	} :: { [Types.WeaponCategory]: CategoryModel },

	-- The sheath WeaponBuilder hangs on the body: a Model next to the Weapon model holding one
	-- scabbard part, welded to the row's part by a Weld.
	sheathModelName = "Sheath",
	scabbardPart = "Scabbard",
	scabbardWeld = "ScabbardWeld",

	-- A category without a row keeps its weapon in the hand (no scabbard, no back mount).
	-- Later: Dual Wielder two crossed back sheaths, Flashdraw a katana sheath high at the hip, rapiers at the hip.
	sheaths = {
		OneHandedSword = {
			part = "UpperTorso",
			-- Hilt above the right shoulder, blade diagonal across the back, flat against it, the tip
			-- by the left hip. Rotating 140 degrees about Z points +Y down and to the left.
			mount = { pos = { 0.75, 1.05, 0.7 }, rot = { 0, 0, 140 } },
			scabbard = {
				wall = 0.06, -- added on each side of the blade's width and thickness
				clearance = 0.15, -- how far the scabbard runs past the tip
				color = "PlaceholderWood",
			},
		},
	} :: { [Types.WeaponCategory]: SheathMount },
}

--- The stand-in geometry of a weapon category; errors on an unknown category so a bad weapon row fails loudly.
function WeaponModels.get(category: Types.WeaponCategory): CategoryModel
	local model = WeaponModels.categories[category]
	if model == nil then
		error(("weaponModels: no placeholder geometry for category '%s'"):format(tostring(category)))
	end
	return model
end

--- Studs from the blade part's center down to the hand's hold point (the grip's center).
function WeaponModels.holdOffset(category: Types.WeaponCategory): number
	local model = WeaponModels.get(category)
	return model.blade.length / 2 + model.guard.height + model.grip.length / 2
end

--- Overall length of the stand-in from pommel to tip.
function WeaponModels.totalLength(category: Types.WeaponCategory): number
	local model = WeaponModels.get(category)
	return model.blade.length + model.guard.height + model.grip.length
end

--- The category's back mount, or nil when its weapon stays in the hand.
function WeaponModels.sheath(category: Types.WeaponCategory): SheathMount?
	return WeaponModels.sheaths[category]
end

return WeaponModels
