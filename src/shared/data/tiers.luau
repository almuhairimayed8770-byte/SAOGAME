--!strict
--[[
	Tier multipliers and level math (sections 9 and 13).

	Every enemy and boss row is authored at tier 1; `Tiers.get(floor)` returns the multipliers that
	scale it to its floor. Floors 1 to 25 are hand-tuned rows (a floor is one tier); floors 26 to
	100 extend tier 25 geometrically with `Tiers.extension` so the Floor Generator has numbers for
	every floor without another table. XP follows the level curve (floor^1.6) so roughly thirty kills
	make a level on every floor; HP and attack grow faster than defense so late fights get longer
	and more dangerous rather than tankier.

	Level math is section 13: XP to next = 120 * level^1.6, +10 max HP and 3 stat points per level,
	halved XP more than 5 levels over a floor's tier, doubled damage taken more than 5 under it.
]]

local Combat = require(script.Parent.combat)

export type TierMultipliers = { hp: number, attack: number, defense: number, gauge: number, xp: number }

local Tiers = {}

-- Level rules (section 13)
Tiers.levelCap = 100
Tiers.maxFloor = 100
Tiers.handTunedFloors = 25
Tiers.xpBase = 120
Tiers.xpExponent = 1.6
Tiers.basePlayerHp = Combat.basePlayerHp
Tiers.hpPerLevel = Combat.hpPerLevel
Tiers.statPointsPerLevel = 3
Tiers.overLevelXpHalving = 5 -- levels above a floor's tier before XP there halves
Tiers.overLevelXpMultiplier = 0.5
Tiers.underLevelDamageDoubling = 5 -- levels below a floor's tier before damage taken doubles
Tiers.underLevelDamageMultiplier = 2
Tiers.bossXpLevelsToRaid = 1 -- a boss gives a level's worth of XP to the raid
Tiers.agiArtSpeedMax = 0.15 -- AGI raises Art speed up to +15%

-- Floors 1 to 25: hand-tuned rows. hp = 1 + 0.18k + 0.012k^2, attack = 1 + 0.12k + 0.006k^2,
-- defense = 1 + 0.10k + 0.004k^2, gauge = 1 + 0.10k + 0.005k^2, xp = floor^1.6 (k = floor - 1).
Tiers.table = {
	[1] = { hp = 1, attack = 1, defense = 1, gauge = 1, xp = 1 },
	[2] = { hp = 1.19, attack = 1.13, defense = 1.1, gauge = 1.11, xp = 3.03 },
	[3] = { hp = 1.41, attack = 1.26, defense = 1.22, gauge = 1.22, xp = 5.8 },
	[4] = { hp = 1.65, attack = 1.41, defense = 1.34, gauge = 1.35, xp = 9.19 },
	[5] = { hp = 1.91, attack = 1.58, defense = 1.46, gauge = 1.48, xp = 13.13 },
	[6] = { hp = 2.2, attack = 1.75, defense = 1.6, gauge = 1.63, xp = 17.58 },
	[7] = { hp = 2.51, attack = 1.94, defense = 1.74, gauge = 1.78, xp = 22.5 },
	[8] = { hp = 2.85, attack = 2.13, defense = 1.9, gauge = 1.95, xp = 27.86 },
	[9] = { hp = 3.21, attack = 2.34, defense = 2.06, gauge = 2.12, xp = 33.63 },
	[10] = { hp = 3.59, attack = 2.57, defense = 2.22, gauge = 2.3, xp = 39.81 },
	[11] = { hp = 4, attack = 2.8, defense = 2.4, gauge = 2.5, xp = 46.37 },
	[12] = { hp = 4.43, attack = 3.05, defense = 2.58, gauge = 2.71, xp = 53.3 },
	[13] = { hp = 4.89, attack = 3.3, defense = 2.78, gauge = 2.92, xp = 60.58 },
	[14] = { hp = 5.37, attack = 3.57, defense = 2.98, gauge = 3.14, xp = 68.2 },
	[15] = { hp = 5.87, attack = 3.86, defense = 3.18, gauge = 3.38, xp = 76.16 },
	[16] = { hp = 6.4, attack = 4.15, defense = 3.4, gauge = 3.63, xp = 84.45 },
	[17] = { hp = 6.95, attack = 4.46, defense = 3.62, gauge = 3.88, xp = 93.05 },
	[18] = { hp = 7.53, attack = 4.77, defense = 3.86, gauge = 4.15, xp = 101.96 },
	[19] = { hp = 8.13, attack = 5.1, defense = 4.1, gauge = 4.42, xp = 111.17 },
	[20] = { hp = 8.75, attack = 5.45, defense = 4.34, gauge = 4.71, xp = 120.68 },
	[21] = { hp = 9.4, attack = 5.8, defense = 4.6, gauge = 5, xp = 130.48 },
	[22] = { hp = 10.07, attack = 6.17, defense = 4.86, gauge = 5.31, xp = 140.56 },
	[23] = { hp = 10.77, attack = 6.54, defense = 5.14, gauge = 5.62, xp = 150.93 },
	[24] = { hp = 11.49, attack = 6.93, defense = 5.42, gauge = 5.95, xp = 161.56 },
	[25] = { hp = 12.23, attack = 7.34, defense = 5.7, gauge = 6.28, xp = 172.47 },
} :: { [number]: TierMultipliers }

-- Floors 26 to 100: tier 25 times these per-floor growth factors, compounded.
Tiers.extension = { hp = 1.055, attack = 1.045, defense = 1.04, gauge = 1.04, xp = 1.06 } :: TierMultipliers

--- Multipliers for a floor's tier; floors outside 1..maxFloor clamp to the nearest edge.
function Tiers.get(floor: number): TierMultipliers
	local tier = math.clamp(math.floor(floor), 1, Tiers.maxFloor)
	local row = Tiers.table[tier]
	if row ~= nil then
		return table.clone(row)
	end
	local base = Tiers.table[Tiers.handTunedFloors]
	local steps = tier - Tiers.handTunedFloors
	local growth = Tiers.extension
	return {
		hp = base.hp * growth.hp ^ steps,
		attack = base.attack * growth.attack ^ steps,
		defense = base.defense * growth.defense ^ steps,
		gauge = base.gauge * growth.gauge ^ steps,
		xp = base.xp * growth.xp ^ steps,
	}
end

--- XP needed to go from `level` to `level + 1` (section 13: 120 * level^1.6), as a whole number.
function Tiers.xpToNext(level: number): number
	local clamped = math.clamp(math.floor(level), 1, Tiers.levelCap)
	return math.floor(Tiers.xpBase * clamped ^ Tiers.xpExponent + 0.5)
end

--- Total XP accumulated on reaching `level` from level 1.
function Tiers.totalXpForLevel(level: number): number
	local total = 0
	for current = 1, math.clamp(math.floor(level), 1, Tiers.levelCap) - 1 do
		total += Tiers.xpToNext(current)
	end
	return total
end

--- The level a character with `totalXp` holds, capped at the level cap.
function Tiers.levelFromTotalXp(totalXp: number): number
	local level = 1
	local remaining = math.max(totalXp, 0)
	while level < Tiers.levelCap do
		local needed = Tiers.xpToNext(level)
		if remaining < needed then
			break
		end
		remaining -= needed
		level += 1
	end
	return level
end

--- Max HP at a level: the section 6 base plus 10 per level gained.
function Tiers.maxHp(level: number): number
	local clamped = math.clamp(math.floor(level), 1, Tiers.levelCap)
	return Tiers.basePlayerHp + Tiers.hpPerLevel * (clamped - 1)
end

--- Stat points a character has earned by `level` (3 per level gained).
function Tiers.statPointsEarned(level: number): number
	local clamped = math.clamp(math.floor(level), 1, Tiers.levelCap)
	return Tiers.statPointsPerLevel * (clamped - 1)
end

--- XP multiplier for a level fighting on a floor: halved when more than 5 levels over its tier.
function Tiers.xpMultiplier(level: number, floorTier: number): number
	if level - floorTier > Tiers.overLevelXpHalving then
		return Tiers.overLevelXpMultiplier
	end
	return 1
end

--- Damage-taken multiplier for a level on a floor: doubled when more than 5 levels under its tier.
function Tiers.damageTakenMultiplier(level: number, floorTier: number): number
	if floorTier - level > Tiers.underLevelDamageDoubling then
		return Tiers.underLevelDamageMultiplier
	end
	return 1
end

--- XP a kill is worth: the row's tier-1 xp times the floor's xp multiplier, rounded, at least 1.
function Tiers.scaleXp(baseXp: number, floor: number): number
	return math.max(1, math.floor(baseXp * Tiers.get(floor).xp + 0.5))
end

return Tiers
