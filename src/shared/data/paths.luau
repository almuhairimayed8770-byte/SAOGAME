--!strict
--[[
	Paths (section 7): the six class-like templates chosen at level 10 at the Firstlight trainer.
	A Path sets the weapons a character may use, a signature mechanic, and the armor class it may
	wear. Origins stack on top; a Dual Wielder keeps Twin Fang under any Path.

	Numbers: multipliers are factors, bonuses are fractions (0.6 = +60%), durations are seconds,
	cones are degrees.
]]

local Types = require(script.Parent.Parent.types)

export type PathId = "Vanguard" | "Striker" | "Duelist" | "Breaker" | "Shade" | "Herald"

export type ArmorClass = "Light" | "Medium" | "Heavy"

export type PathDef = {
	id: PathId,
	name: string,
	weapons: { Types.WeaponCategory }, -- main-hand categories the Path may slot
	offHand: string?, -- off-hand item kind ("Shield", "WarHorn")
	armor: ArmorClass, -- heaviest armor class the Path may wear
	signature: { [string]: any }, -- the signature mechanic as data
	summary: string, -- the section 7 one-liner
}

local Paths = {
	chooseLevel = 10,
	trainerTown = "Firstlight",

	--- One respec per ten floors at the Haven trainer for a fifth of carried Crowns.
	respec = {
		perFloors = 10,
		crownFraction = 0.2,
		trainer = "Haven",
	},

	--- A Dual Wielder keeps the Twin Fang line whatever Path it takes.
	originKeepsWeapons = {
		DualWielder = { "TwinFang" },
		Aegis = { "AegisBlade" },
	} :: { [string]: { Types.WeaponCategory } },

	list = {
		Vanguard = {
			id = "Vanguard",
			name = "Vanguard",
			weapons = { "OneHandedSword", "Mace" },
			offHand = "Shield",
			armor = "Heavy",
			summary = "Taunt (3x threat for 8 s); Bulwark Stance (guard cone 360 degrees, cannot move)",
			signature = {
				taunt = { threatMultiplier = 3, duration = 8 },
				bulwarkStance = { guardConeDegrees = 360, canMove = false },
			},
		},
		Striker = {
			id = "Striker",
			name = "Striker",
			weapons = { "OneHandedSword", "Katana" },
			armor = "Medium",
			summary = "Momentum: each Art that lands cuts the next start pose by 50%, up to 3 stacks",
			signature = {
				momentum = { startPoseCutPerStack = 0.5, maxStacks = 3 },
			},
		},
		Duelist = {
			id = "Duelist",
			name = "Duelist",
			weapons = { "Rapier" },
			armor = "Light",
			summary = "Riposte: a perfect parry grants one free Art with no activation hold",
			signature = {
				riposte = { freeArtsPerParry = 1, activationHold = 0 },
			},
		},
		Breaker = {
			id = "Breaker",
			name = "Breaker",
			weapons = { "TwoHandedSword", "Axe", "Spear" },
			armor = "Heavy",
			summary = "Shatter: +60% Guard Gauge damage; Arts knock back",
			signature = {
				shatter = { gaugeDamageBonus = 0.6, knockback = true },
			},
		},
		Shade = {
			id = "Shade",
			name = "Shade",
			weapons = { "Dagger" },
			armor = "Light",
			summary = "Hide out of combat; first strike from behind 2.5x and opens a Switch window",
			signature = {
				hide = { outOfCombatOnly = true },
				firstStrike = { fromBehindMultiplier = 2.5, opensSwitch = true },
			},
		},
		Herald = {
			id = "Herald",
			name = "Herald",
			weapons = { "OneHandedSword", "Rapier", "Dagger", "Axe", "Mace" },
			offHand = "WarHorn",
			armor = "Medium",
			summary = "Rally: party Tempo cap +2 and +10% Art speed for 10 s; carries two extra Shards",
			signature = {
				rally = { tempoCapBonus = 2, artSpeedBonus = 0.1, duration = 10 },
				extraShards = 2,
			},
		},
	} :: { [PathId]: PathDef },

	order = { "Vanguard", "Striker", "Duelist", "Breaker", "Shade", "Herald" } :: { PathId },
}

--- The Path definition; errors on an unknown id so a bad save fails loudly.
function Paths.get(id: string): PathDef
	local def = Paths.list[id :: PathId]
	if def == nil then
		error(("paths: unknown Path '%s'"):format(tostring(id)))
	end
	return def
end

--- Whether a character on `pathId` with `originId` may slot a weapon category.
function Paths.canWield(pathId: string, weapon: Types.WeaponCategory, originId: string?): boolean
	local def = Paths.get(pathId)
	if table.find(def.weapons, weapon) then
		return true
	end
	if originId then
		local kept = Paths.originKeepsWeapons[originId]
		if kept and table.find(kept, weapon) then
			return true
		end
	end
	return false
end

--- Crowns charged for a respec from a carried total.
function Paths.respecCost(carriedCrowns: number): number
	return math.floor(carriedCrowns * Paths.respec.crownFraction)
end

--- How many respecs a character has earned by the floors it has reached (one per ten floors).
function Paths.respecsEarned(highestFloor: number): number
	return math.floor(highestFloor / Paths.respec.perFloors)
end

return Paths
