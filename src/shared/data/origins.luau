--!strict
--[[
	Character creation rolls (section 7): Lineage, Origin and Mark. Three rolls at creation,
	permanent, visible to other players. Weights are percentages and sum to 100 per roll (the
	validator checks it). Rolls happen on the server through Rng.weighted with a Random seeded per
	request (Rng.forRequest); the client never rolls.

	Effects are data: a service reads the numbers it cares about (defense, speed, parry window)
	and ignores the rest. Multipliers are factors (1.05 = +5%), bonuses are added, windows are
	seconds. `look` is for the character builder and the modeler.
]]

local Rng = require(script.Parent.Parent.util.Rng)

export type LineageId =
	"Lowlander"
	| "Highborn"
	| "Woodling"
	| "Ironfolk"
	| "Driftkin"
	| "Stormblood"
	| "Nightveil"
	| "Ashborn"
	| "Starmarked"
	| "Hollowkin"

export type OriginId = "None" | "Ironhand" | "Beastbond" | "Flashdraw" | "DualWielder" | "Aegis"

export type MarkId = "None" | "ArchitectsMark"

export type RollResult = {
	lineage: LineageId,
	origin: OriginId,
	mark: MarkId,
}

export type Effect = {
	description: string, -- one line for the profile card
	look: string, -- what the character builder shows
	[string]: any, -- the numbers, named per effect
}

local Origins = {
	rollNames = { "lineage", "origin", "mark" },

	lineage = {
		{ value = "Lowlander", weight = 16 },
		{ value = "Highborn", weight = 16 },
		{ value = "Woodling", weight = 16 },
		{ value = "Ironfolk", weight = 16 },
		{ value = "Driftkin", weight = 16 },
		{ value = "Stormblood", weight = 6 },
		{ value = "Nightveil", weight = 6 },
		{ value = "Ashborn", weight = 5 },
		{ value = "Starmarked", weight = 2 },
		{ value = "Hollowkin", weight = 1 },
	} :: { Rng.Weighted<LineageId> },

	origin = {
		{ value = "None", weight = 92 },
		{ value = "Ironhand", weight = 3 },
		{ value = "Beastbond", weight = 2 },
		{ value = "Flashdraw", weight = 1.5 },
		{ value = "DualWielder", weight = 1 },
		{ value = "Aegis", weight = 0.5 },
	} :: { Rng.Weighted<OriginId> },

	mark = {
		{ value = "ArchitectsMark", weight = 0.1 },
		{ value = "None", weight = 99.9 },
	} :: { Rng.Weighted<MarkId> },

	displayNames = {
		Lowlander = "Lowlander",
		Highborn = "Highborn",
		Woodling = "Woodling",
		Ironfolk = "Ironfolk",
		Driftkin = "Driftkin",
		Stormblood = "Stormblood",
		Nightveil = "Nightveil",
		Ashborn = "Ashborn",
		Starmarked = "Starmarked",
		Hollowkin = "Hollowkin",
		None = "None",
		Ironhand = "Ironhand",
		Beastbond = "Beastbond",
		Flashdraw = "Flashdraw",
		DualWielder = "Dual Wielder",
		Aegis = "Aegis",
		ArchitectsMark = "Architect's Mark",
	} :: { [string]: string },

	effects = {
		-- Lineage
		Lowlander = { description = "Vendor prices -5%", look = "plain look", vendorPriceMultiplier = 0.95 },
		Highborn = { description = "Defense +3%", look = "tailored default clothes", defenseMultiplier = 1.03 },
		Woodling = {
			description = "Field move speed +5%",
			look = "leaf-green eye tint",
			fieldMoveSpeedMultiplier = 1.05,
			eyeTint = "LeafGreen",
		},
		Ironfolk = {
			description = "Durability loss -10%, smithing success +5%",
			look = "broad build",
			durabilityLossMultiplier = 0.9,
			smithingSuccessBonus = 0.05,
		},
		Driftkin = {
			description = "Fall damage -50%, faster climbing",
			look = "wind-tousled hair",
			fallDamageMultiplier = 0.5,
			climbSpeedMultiplier = 1.25,
		},
		Stormblood = {
			description = "AGI +8%",
			look = "hair glows faint blue at night",
			agiMultiplier = 1.08,
			nightHairGlow = true,
		},
		Nightveil = {
			description = "Damage +10% at night, -3% by day",
			look = "black sclera",
			nightDamageMultiplier = 1.1,
			dayDamageMultiplier = 0.97,
		},
		Ashborn = {
			description = "Burn immune, STR +5%",
			look = "ember freckles",
			burnImmune = true,
			strMultiplier = 1.05,
		},
		Starmarked = {
			description = "All stats +10%, one extra Art slot",
			look = "constellation marks on skin",
			allStatsMultiplier = 1.1,
			extraArtSlots = 1,
		},
		Hollowkin = {
			description = "Max HP -50%, damage x2",
			look = "glowing cracks across the body",
			maxHpMultiplier = 0.5,
			damageMultiplier = 2,
		},
		-- Origin
		None = { description = "Standard swordsman", look = "no mark" },
		Ironhand = {
			description = "Guard Gauge +15%, parry window +50 ms",
			look = "iron-banded gauntlet",
			guardGaugeMultiplier = 1.15,
			parryWindowBonus = 0.05,
		},
		Beastbond = {
			description = "Can tame rare creatures as fighting pets",
			look = "a feathered wyrmling, Plume, at the shoulder",
			canTame = true,
			firstPet = "Plume",
		},
		Flashdraw = {
			description = "Katana Arts skip the start pose; +30% post-motion",
			look = "sheath worn high at the hip",
			katanaSkipsStartPose = true,
			postMotionMultiplier = 1.3,
		},
		DualWielder = {
			description = "Twin Fang skill line; two blades; the solo build",
			look = "two crossed sheaths on the back, a different idle, a different run",
			skillLine = "TwinFang",
			gaugeDamageMultiplier = 2.5, -- a Twin Fang Art counts as two Art hits on the Guard Gauge
			artDamagePerSecondMultiplier = 1.8,
			activationHold = 0.2, -- seconds, on every Twin Fang Art (punishable)
			whiffPostMotionMultiplier = 2,
			canUseShield = false,
			armorWeightCapMultiplier = 0.8, -- the lighter armor cap
			distinctSilhouette = true,
		},
		Aegis = {
			description = "Guard never breaks, parry window 250 ms, zero Art damage bonus",
			look = "a shield mount on the forearm; story reveal at floor 75",
			guardNeverBreaks = true,
			parryWindow = 0.25,
			artDamageBonus = 0,
			storyRevealFloor = 75,
			distinctSilhouette = true,
		},
		-- Mark
		ArchitectsMark = {
			description = "A glowing sigil on the back of the hand",
			look = "cosmetic sigil, cannot be hidden",
			cosmeticOnly = true,
		},
	} :: { [string]: Effect },

	--- Server-wide system lines fired when a rare roll enters the Spire (section 7).
	announcements = {
		DualWielder = "A Dual Wielder has entered the Spire",
		Aegis = "An Aegis has entered the Spire",
		ArchitectsMark = "The Architect's Mark has appeared in the Spire",
	} :: { [string]: string },

	--- The one re-roll in the game: a Haven boss drop that re-rolls Lineage or Origin.
	mirrorOfOrigins = {
		dropChance = 0.0005, -- 0.05% from Haven bosses
		rerolls = { "lineage", "origin" },
	},
}

local function sum(entries: { Rng.Weighted<any> }): number
	local total = 0
	for _, entry in entries do
		total += entry.weight
	end
	return total
end

--- Rolls Lineage, Origin and Mark on the given Random (server only; seed it with Rng.forRequest).
function Origins.roll(random: Random): RollResult
	return {
		lineage = Rng.weighted(random, Origins.lineage),
		origin = Rng.weighted(random, Origins.origin),
		mark = Rng.weighted(random, Origins.mark),
	}
end

--- The system lines a roll result should broadcast, in order (empty for an ordinary roll).
function Origins.announcementsFor(result: RollResult): { string }
	local lines = {}
	for _, id in { result.origin, result.mark } do
		local line = Origins.announcements[id]
		if line then
			table.insert(lines, line)
		end
	end
	return lines
end

--- Whether a roll result changes the character's silhouette (crossed sheaths, shield mount).
function Origins.hasDistinctSilhouette(result: RollResult): boolean
	local effect = Origins.effects[result.origin]
	return effect ~= nil and effect.distinctSilhouette == true
end

-- One roll's weighted entries by name ("lineage", "origin", "mark"); errors on any other name.
local function entriesOf(rollName: string): { Rng.Weighted<string> }
	if table.find(Origins.rollNames, rollName) == nil then
		error(("origins: unknown roll '%s'"):format(tostring(rollName)))
	end
	return (Origins :: any)[rollName]
end

--- Total weight of one roll's table; 100 for every roll by rule.
function Origins.totalWeight(rollName: string): number
	return sum(entriesOf(rollName))
end

--- The fraction (0..1) of one result in a roll; 0 when the id is not in that roll, an error on
--- an unknown roll name.
function Origins.chanceOf(rollName: string, id: string): number
	local entries = entriesOf(rollName)
	for _, entry in entries do
		if entry.value == id then
			return entry.weight / sum(entries)
		end
	end
	return 0
end

return Origins
