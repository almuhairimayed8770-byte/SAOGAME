--!strict
--[[
	Floor bosses (section 9). Grolak, Kobold Warlord in full for Phase 0 and floors 2 to 10 as
	rows with their bars, phases, mechanics and Lockstep from the launch-boss table. Every boss
	follows the floor-boss template: a 3 s entrance, one phase per bar group, a guard pack at the
	start and at each phase change, at least one Lockstep, enrage at 8 minutes (+10% damage per
	minute), a 60 s wipe reset, a deterministic Last Attack Bonus, and a 3 s shatter.

	Numbers are TIER-1 BASE VALUES like enemies.luau: `Bosses.scaled(def)` applies the floor's
	tier. Boss attacks are `EnemyAttackDef`s with the same six-beat clips as any enemy; `arts` in a
	phase are player Art ids the boss executes with its own rig (Grolak's curved blade uses the
	Katana list). XP is a level's worth at the boss's floor (tiers.luau), given to the raid.

	Every boss carries a Mirror Shield (section 7). Overwhelm, Duelist Protocol and the raid flow
	numbers live in `Bosses.rules`.
]]

local Types = require(script.Parent.Parent.types)
local Combat = require(script.Parent.combat)
local Tiers = require(script.Parent.tiers)

local GUARD_REGEN = Combat.guardRegenPerSecond

local Bosses = {}

Bosses.rules = {
	entranceSeconds = 3, -- scripted camera: torches, the boss stands, the name card, the bars fill
	barFillSoundPerBar = true,
	minBars = 4,
	maxBars = 6,
	lockstepWindow = 1.0, -- seconds two players have to act together
	enrageStartSeconds = 480, -- 8 minutes
	enrageDamagePerMinute = 0.10,
	wipeResetSeconds = 60,
	overwhelmBelowPlayers = 3, -- fewer than three players in the chamber
	overwhelmAttackSpeed = 1.4, -- +40% attack speed
	overwhelmPackIntervalSeconds = 20,
	duelistProtocolAttackSpeed = 1.25, -- faster, fully readable patterns, one on one
	duelistProtocolTorchDim = 0.3, -- torches dim to a spotlight (fraction of brightness)
	shatterSeconds = 3,
	shatterShards = 300,
	readyCheckSeconds = 30,
	disconnectGraceSeconds = 60,
	successTargets = { -- section 7 expected outcomes, first-clear attempts at level
		soloNoApex = 0,
		soloDualWielder = 0.02,
		soloDualWielderApex = 0.25,
		twoPlayers = 0.10,
		fourPlayersThirdAttempt = 0.40,
		eightPlayersCoordinated = 0.60,
	},
}

-- LAB item ids for floors whose Apex sets are not authored yet (listed so the validator can tell a
-- planned item from a typo). Each becomes a real row when its floor's apex.luau entry lands.
Bosses.pendingLab = {
	"MatriarchsVeil",
	"AshbarkHeartwood",
	"TidecallerFang",
	"BulwarkCore",
	"PaleLantern",
	"RimeclawPelt",
	"HexenCrown",
	"WardensSabre",
}

-- Grolak's attacks, shared across phases so the clip ids stay in one place.
local grolakOverhead: Types.EnemyAttackDef = {
	id = "OverheadCleave",
	name = "Overhead Cleave",
	telegraph = "GuardBreak",
	windUp = 1.0,
	strike = 0.35,
	recovery = 1.4,
	multiplier = 1.8,
	gaugeDamage = 60,
	reach = 7,
	arc = 70,
	clip = "OverheadCleave",
	groundShape = "Cone",
}
local grolakBucklerBash: Types.EnemyAttackDef = {
	id = "BucklerBash",
	name = "Buckler Bash",
	telegraph = "Normal",
	windUp = 0.5,
	strike = 0.25,
	recovery = 1.0,
	multiplier = 1.0,
	gaugeDamage = 40,
	reach = 5,
	arc = 60,
	clip = "BucklerBash",
	groundShape = "Cone",
	status = "Stun",
}
local grolakSweep: Types.EnemyAttackDef = {
	id = "SweepingCleave",
	name = "Sweeping Cleave",
	telegraph = "Unblockable",
	windUp = 0.8,
	strike = 0.4,
	recovery = 1.5,
	multiplier = 1.4,
	gaugeDamage = 30,
	reach = 8,
	arc = 180,
	clip = "SweepingCleave",
	groundShape = "Cone",
}
local grolakWarcry: Types.EnemyAttackDef = {
	id = "Warcry",
	name = "Warcry",
	telegraph = "Normal",
	windUp = 0.6,
	strike = 0.3,
	recovery = 2.0,
	multiplier = 0,
	gaugeDamage = 0,
	reach = 0,
	arc = 0,
	clip = "Warcry",
	groundShape = "Circle",
}
local grolakBucklerThrow: Types.EnemyAttackDef = {
	id = "BucklerThrow",
	name = "Buckler Throw",
	telegraph = "Unblockable",
	windUp = 0.7,
	strike = 0.3,
	recovery = 1.6,
	multiplier = 1.6,
	gaugeDamage = 20,
	reach = 18,
	arc = 0,
	clip = "BucklerThrow",
	groundShape = "Line",
}
local grolakDrawCut: Types.EnemyAttackDef = {
	id = "DrawCut",
	name = "Draw Cut",
	telegraph = "Unblockable",
	windUp = 0.8,
	strike = 0.2,
	recovery = 1.2,
	multiplier = 2.0,
	gaugeDamage = 35,
	reach = 10,
	arc = 0,
	clip = "DrawCut",
	groundShape = "Line",
}
local grolakSkyfall: Types.EnemyAttackDef = {
	id = "SkyfallCut",
	name = "Skyfall Cut",
	telegraph = "Unblockable",
	windUp = 1.2,
	strike = 0.3,
	recovery = 2.0,
	multiplier = 6.0,
	gaugeDamage = 80,
	reach = 8,
	arc = 360,
	clip = "SkyfallCut",
	groundShape = "Circle",
}

local rows: { [string]: Types.BossDef } = {
	-- ================================================================== Floor 1
	Grolak = {
		id = "Grolak",
		name = "Grolak, Kobold Warlord",
		floor = 1,
		tier = 1,
		skin = "KoboldWarlord",
		bars = 4,
		hpPerBar = 5000,
		attack = 30,
		defense = 6,
		guardGauge = 1000,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 12,
		guardPack = { { enemyId = "KoboldSentinel", count = 3 } },
		lockstep = {
			id = "SentinelTotems",
			name = "Sentinel Totems",
			kind = "Lockstep",
			description = "Two totems rise at the chamber's flanks; two players must break both within 1 s or the Sentinels respawn at full HP.",
			window = 1.0,
			targets = 2,
			interval = 45,
			failure = "The guard pack respawns",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F1",
		lab = "MantleOfLastLight",
		shatter = "Boss",
		xp = 120,
		chamber = "Torch-lit stone hall at the top of the Firstlight Labyrinth; house-sized double doors, a throne step, two totem sockets on the flanks.",
		phases = {
			{
				bar = 1,
				name = "Axe and Buckler",
				summary = "A huge kobold with a great axe and a buckler, three Sentinels at his sides. Overhead cleaves teach the raid to parry; the buckler bash stuns whoever stands in front.",
				archetype = "Brute",
				attacks = { grolakOverhead, grolakBucklerBash, grolakSweep },
				mechanics = {
					{
						id = "GuardPack",
						name = "Sentinel Guard",
						kind = "Summon",
						description = "Three Kobold Sentinels enter with him and block frontal Arts.",
						interval = 0,
					},
				},
				summons = { { enemyId = "KoboldSentinel", count = 3 } },
			},
			{
				bar = 2,
				name = "Totem Call",
				summary = "The totems rise. From here the Sentinels come back every time the Lockstep is missed.",
				archetype = "Brute",
				attacks = { grolakOverhead, grolakBucklerBash, grolakSweep, grolakWarcry },
				mechanics = {
					{
						id = "SentinelTotems",
						name = "Sentinel Totems",
						kind = "Lockstep",
						description = "Two totems rise every 45 s; break both within 1 s.",
						window = 1.0,
						targets = 2,
						interval = 45,
						failure = "The guard pack respawns",
					},
				},
				summons = { { enemyId = "KoboldSentinel", count = 3 } },
			},
			{
				bar = 3,
				name = "Buckler Throw",
				summary = "He throws the buckler down the room and calls four more Sentinels. Without the buckler his guard narrows and the sweeps come faster.",
				archetype = "Brute",
				attacks = { grolakOverhead, grolakSweep, grolakBucklerThrow, grolakWarcry },
				mechanics = {
					{
						id = "BucklerThrow",
						name = "Buckler Throw",
						kind = "Hazard",
						description = "An 18-stud unblockable line; the buckler stays on the floor as cover afterward.",
					},
					{
						id = "SecondPack",
						name = "Four More",
						kind = "Summon",
						description = "Calls four more Sentinels on the bar break.",
						interval = 0,
					},
					{
						id = "SentinelTotems",
						name = "Sentinel Totems",
						kind = "Lockstep",
						description = "The totems keep rising.",
						window = 1.0,
						targets = 2,
						interval = 45,
						failure = "The guard pack respawns",
					},
				},
				summons = { { enemyId = "KoboldSentinel", count = 4 } },
			},
			{
				bar = 4,
				name = "Curved Blade",
				summary = "He drops the axe and draws a curved blade. Katana-style Arts, a dash cut through the line, and a jump cut that one-shots a yellow-HP player. The camera pulls back for the draw.",
				archetype = "Skirmisher",
				weapon = "WarlordCurvedBlade",
				arts = { "Katana.IaiCut", "Katana.Reaver", "Katana.Tsujikaze", "Katana.Gengetsu" },
				attacks = { grolakDrawCut, grolakSkyfall, grolakSweep },
				attackSpeed = 1.15,
				mechanics = {
					{
						id = "WeaponSwap",
						name = "The Curved Blade",
						kind = "WeaponSwap",
						description = "Drops the axe, draws a curved blade; stance changes to a Skirmisher's.",
					},
					{
						id = "SkyfallCut",
						name = "Skyfall Cut",
						kind = "Hazard",
						description = "A 1.2 s jump cut on an 8-stud circle; it kills anyone at or below half HP.",
					},
					{
						id = "SentinelTotems",
						name = "Sentinel Totems",
						kind = "Lockstep",
						description = "The totems keep rising.",
						window = 1.0,
						targets = 2,
						interval = 45,
						failure = "The guard pack respawns",
					},
				},
				summons = { { enemyId = "KoboldSentinel", count = 2 } },
			},
		},
	},

	-- ================================================================== Floor 2
	MirefangMatriarch = {
		id = "MirefangMatriarch",
		name = "Mirefang Matriarch",
		floor = 2,
		tier = 2,
		skin = "MirefangMatriarch",
		bars = 4,
		hpPerBar = 5600,
		attack = 32,
		defense = 5,
		guardGauge = 900,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 22,
		guardPack = { { enemyId = "MarshWasp", count = 6 } },
		lockstep = {
			id = "WingTendons",
			name = "Wing Tendons",
			kind = "Lockstep",
			description = "Cut both wing tendons within 1 s to ground her for 10 s.",
			window = 1.0,
			targets = 2,
			interval = 40,
			failure = "She stays airborne and lays eggs",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F2",
		lab = "MatriarchsVeil",
		shatter = "Boss",
		xp = 364,
		chamber = "A flooded nest with three boardwalk platforms; the lower level is reed water.",
		phases = {
			{
				bar = 1,
				name = "Three Platforms",
				summary = "A giant wasp that flies between three boardwalk platforms and stings whoever is slowest to follow.",
				archetype = "Skirmisher",
				attacks = {
					{
						id = "Sting",
						name = "Sting",
						telegraph = "Normal",
						windUp = 0.4,
						strike = 0.2,
						recovery = 0.9,
						multiplier = 1.2,
						gaugeDamage = 20,
						reach = 6,
						arc = 45,
						clip = "Sting",
						groundShape = "Cone",
						status = "Poison",
					},
					{
						id = "DiveSting",
						name = "Dive Sting",
						telegraph = "Unblockable",
						windUp = 0.7,
						strike = 0.3,
						recovery = 1.4,
						multiplier = 1.8,
						gaugeDamage = 30,
						reach = 14,
						arc = 0,
						clip = "Dive",
						groundShape = "Line",
					},
				},
				mechanics = {
					{
						id = "Platforms",
						name = "Boardwalk Platforms",
						kind = "Terrain",
						description = "She lands on one of three platforms; the party chases.",
					},
				},
				summons = { { enemyId = "MarshWasp", count = 6 } },
			},
			{
				bar = 2,
				name = "Eggs",
				summary = "She lays eggs on the platforms that hatch into Swarm unless they are broken.",
				archetype = "Skirmisher",
				attacks = {
					{
						id = "Sting",
						name = "Sting",
						telegraph = "Normal",
						windUp = 0.4,
						strike = 0.2,
						recovery = 0.9,
						multiplier = 1.2,
						gaugeDamage = 20,
						reach = 6,
						arc = 45,
						clip = "Sting",
						groundShape = "Cone",
						status = "Poison",
					},
				},
				mechanics = {
					{
						id = "Eggs",
						name = "Egg Clutch",
						kind = "Summon",
						description = "Eggs hatch six Marsh Wasps after 15 s unless broken.",
						interval = 30,
					},
				},
				summons = { { enemyId = "MarshWasp", count = 6 } },
			},
			{
				bar = 4,
				name = "Poison Fog",
				summary = "Poison fog fills the lower level; the party must stay on the platforms while she dives.",
				archetype = "Skirmisher",
				attacks = {
					{
						id = "DiveSting",
						name = "Dive Sting",
						telegraph = "Unblockable",
						windUp = 0.7,
						strike = 0.3,
						recovery = 1.4,
						multiplier = 1.8,
						gaugeDamage = 30,
						reach = 14,
						arc = 0,
						clip = "Dive",
						groundShape = "Line",
					},
				},
				mechanics = {
					{
						id = "Fog",
						name = "Poison Fog",
						kind = "Hazard",
						description = "Poison on the lower level; the platforms are safe.",
					},
				},
				summons = { { enemyId = "MarshWasp", count = 4 } },
			},
		},
	},

	-- ================================================================== Floor 3
	AshbarkTreant = {
		id = "AshbarkTreant",
		name = "Ashbark Treant",
		floor = 3,
		tier = 3,
		skin = "AshbarkTreant",
		bars = 5,
		hpPerBar = 5200,
		attack = 34,
		defense = 9,
		guardGauge = 1400,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 0,
		guardPack = { { enemyId = "TreantSapling", count = 2 } },
		lockstep = {
			id = "TwinSaplings",
			name = "Twin Saplings",
			kind = "Lockstep",
			description = "Two saplings sprout; cut both at once or it heals a bar.",
			window = 1.0,
			targets = 2,
			interval = 50,
			failure = "Heals one bar",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F3",
		lab = "AshbarkHeartwood",
		shatter = "Boss",
		xp = 696,
		chamber = "A hollow of red-leaf trees with the treant rooted in the center.",
		phases = {
			{
				bar = 1,
				name = "Rooted",
				summary = "Rooted in the chamber's center, it reaches with branches.",
				archetype = "Guard",
				attacks = {
					{
						id = "BranchReach",
						name = "Branch Reach",
						telegraph = "Unblockable",
						windUp = 0.7,
						strike = 0.3,
						recovery = 1.4,
						multiplier = 1.5,
						gaugeDamage = 30,
						reach = 16,
						arc = 0,
						clip = "Thrust",
						groundShape = "Line",
					},
					{
						id = "Swat",
						name = "Branch Swat",
						telegraph = "Normal",
						windUp = 0.6,
						strike = 0.3,
						recovery = 1.3,
						multiplier = 1.3,
						gaugeDamage = 40,
						reach = 8,
						arc = 120,
						clip = "Swat",
						groundShape = "Cone",
					},
				},
				mechanics = {},
				summons = { { enemyId = "TreantSapling", count = 2 } },
			},
			{
				bar = 3,
				name = "Fire",
				summary = "The room catches fire; burn pools spread from the fallen leaves.",
				archetype = "Guard",
				attacks = {
					{
						id = "Swat",
						name = "Branch Swat",
						telegraph = "Normal",
						windUp = 0.6,
						strike = 0.3,
						recovery = 1.3,
						multiplier = 1.3,
						gaugeDamage = 40,
						reach = 8,
						arc = 120,
						clip = "Swat",
						groundShape = "Cone",
					},
				},
				mechanics = {
					{
						id = "BurnPools",
						name = "Burn Pools",
						kind = "Hazard",
						description = "Burning leaf pools that spread every 20 s.",
						interval = 20,
					},
				},
				summons = { { enemyId = "TreantSapling", count = 2 } },
			},
			{
				bar = 5,
				name = "Uprooted",
				summary = "It tears its roots free and becomes a Brute.",
				archetype = "Brute",
				attacks = {
					{
						id = "RootSlam",
						name = "Root Slam",
						telegraph = "GuardBreak",
						windUp = 1.0,
						strike = 0.35,
						recovery = 1.5,
						multiplier = 1.9,
						gaugeDamage = 70,
						reach = 8,
						arc = 70,
						clip = "Overhead",
						groundShape = "Cone",
					},
				},
				mechanics = {
					{
						id = "Uproot",
						name = "Uproot",
						kind = "WeaponSwap",
						description = "Sheds its roots; the camera pulls back for the stand.",
					},
				},
				summons = { { enemyId = "TreantSapling", count = 3 } },
			},
		},
	},

	-- ================================================================== Floor 4
	TidecallerSerpent = {
		id = "TidecallerSerpent",
		name = "Tidecaller Serpent",
		floor = 4,
		tier = 4,
		skin = "TidecallerSerpent",
		bars = 5,
		hpPerBar = 5400,
		attack = 36,
		defense = 7,
		guardGauge = 1300,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 12,
		guardPack = { { enemyId = "SeaLizardman", count = 3 } },
		lockstep = {
			id = "BellChains",
			name = "Bell Chains",
			kind = "Lockstep",
			description = "Strike both bell chains within 1 s to drain the room.",
			window = 1.0,
			targets = 2,
			interval = 20,
			failure = "The water keeps rising",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F4",
		lab = "TidecallerFang",
		shatter = "Boss",
		xp = 1103,
		chamber = "A sea cave that floods in waves on a 20 s cycle; rocks stand above the waterline.",
		phases = {
			{
				bar = 1,
				name = "The Tide",
				summary = "The chamber floods in waves; the serpent strikes from the water.",
				archetype = "CasterBeast",
				attacks = {
					{
						id = "Bite",
						name = "Bite",
						telegraph = "Normal",
						windUp = 0.5,
						strike = 0.3,
						recovery = 1.2,
						multiplier = 1.4,
						gaugeDamage = 30,
						reach = 8,
						arc = 60,
						clip = "Bite",
						groundShape = "Cone",
					},
				},
				mechanics = {
					{
						id = "Flood",
						name = "Flood Cycle",
						kind = "Hazard",
						description = "Water rises for 20 s then drains if the chains are struck.",
						interval = 20,
					},
				},
				summons = { { enemyId = "SeaLizardman", count = 3 } },
			},
			{
				bar = 2,
				name = "Water Jet",
				summary = "Water jets sweep the room.",
				archetype = "CasterBeast",
				attacks = {
					{
						id = "WaterJet",
						name = "Water Jet",
						telegraph = "Unblockable",
						windUp = 1.2,
						strike = 0.4,
						recovery = 1.8,
						multiplier = 1.6,
						gaugeDamage = 30,
						reach = 20,
						arc = 40,
						clip = "Breath",
						groundShape = "Cone",
					},
				},
				mechanics = {},
				summons = { { enemyId = "SeaLizardman", count = 2 } },
			},
			{
				bar = 4,
				name = "Lightning",
				summary = "Lightning on the water; stand on the rocks when the sky flashes.",
				archetype = "CasterBeast",
				attacks = {
					{
						id = "WaterJet",
						name = "Water Jet",
						telegraph = "Unblockable",
						windUp = 1.2,
						strike = 0.4,
						recovery = 1.8,
						multiplier = 1.6,
						gaugeDamage = 30,
						reach = 20,
						arc = 40,
						clip = "Breath",
						groundShape = "Cone",
					},
				},
				mechanics = {
					{
						id = "Lightning",
						name = "Lightning",
						kind = "Hazard",
						description = "Every 15 s the water is lethal for 2 s; rocks are safe.",
						interval = 15,
					},
				},
				summons = { { enemyId = "SeaLizardman", count = 3 } },
			},
		},
	},

	-- ================================================================== Floor 5 (Haven)
	IronBulwarkGolem = {
		id = "IronBulwarkGolem",
		name = "Iron Bulwark Golem",
		floor = 5,
		tier = 5,
		skin = "IronBulwarkGolem",
		bars = 6,
		hpPerBar = 5000,
		attack = 38,
		defense = 14,
		guardGauge = 1800,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 8,
		guardPack = { { enemyId = "ScarecrowConstruct", count = 2 } },
		lockstep = {
			id = "TwinPillars",
			name = "Twin Pillars",
			kind = "Lockstep",
			description = "Both pillars must be struck within 1 s during the overload or the room burns.",
			window = 1.0,
			targets = 2,
			interval = 30,
			failure = "A 10 s burn-everything attack",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F5",
		lab = "BulwarkCore",
		shatter = "Boss",
		xp = 1576,
		chamber = "A highland forge hall with two iron pillars; the Mirror Shield never drops.",
		phases = {
			{
				bar = 1,
				name = "Permanent Shield",
				summary = "The Mirror Shield is permanent: only a Switch or Twin Fang damages it.",
				archetype = "WardenConstruct",
				attacks = {
					{
						id = "Slam",
						name = "Iron Slam",
						telegraph = "GuardBreak",
						windUp = 1.0,
						strike = 0.35,
						recovery = 1.6,
						multiplier = 1.8,
						gaugeDamage = 70,
						reach = 8,
						arc = 70,
						clip = "Overhead",
						groundShape = "Cone",
					},
					{
						id = "Pulse",
						name = "Ward Pulse",
						telegraph = "Unblockable",
						windUp = 1.0,
						strike = 0.4,
						recovery = 2.0,
						multiplier = 1.5,
						gaugeDamage = 30,
						reach = 12,
						arc = 360,
						clip = "Pulse",
						groundShape = "Circle",
					},
				},
				mechanics = {
					{
						id = "PermanentShield",
						name = "Permanent Mirror Shield",
						kind = "Shield",
						description = "The shield never drops; every non-Switch hit reflects.",
					},
				},
				summons = { { enemyId = "ScarecrowConstruct", count = 2 } },
			},
			{
				bar = 3,
				name = "Split",
				summary = "Splits into two golems that must be fought apart.",
				archetype = "WardenConstruct",
				attacks = {
					{
						id = "Slam",
						name = "Iron Slam",
						telegraph = "GuardBreak",
						windUp = 1.0,
						strike = 0.35,
						recovery = 1.6,
						multiplier = 1.5,
						gaugeDamage = 60,
						reach = 7,
						arc = 70,
						clip = "Overhead",
						groundShape = "Cone",
					},
				},
				mechanics = {
					{
						id = "Split",
						name = "Split",
						kind = "Illusion",
						description = "Two half-golems with half the attack each; both must fall.",
					},
				},
				summons = { { enemyId = "ScarecrowConstruct", count = 2 } },
			},
			{
				bar = 6,
				name = "Overload",
				summary = "Fuses back together and overloads; the pillars must be struck together or everything burns.",
				archetype = "WardenConstruct",
				attacks = {
					{
						id = "Overload",
						name = "Overload",
						telegraph = "Unblockable",
						windUp = 1.2,
						strike = 0.4,
						recovery = 2.0,
						multiplier = 4.0,
						gaugeDamage = 100,
						reach = 40,
						arc = 360,
						clip = "Pulse",
						groundShape = "Circle",
						status = "Burn",
					},
				},
				mechanics = {
					{
						id = "TwinPillars",
						name = "Twin Pillars",
						kind = "Lockstep",
						description = "10 s burn-everything attack unless both pillars are struck.",
						window = 1.0,
						targets = 2,
						interval = 30,
						failure = "The room burns",
					},
				},
				summons = { { enemyId = "ScarecrowConstruct", count = 3 } },
			},
		},
	},

	-- ================================================================== Floor 6
	PaleCrawler = {
		id = "PaleCrawler",
		name = "Pale Crawler",
		floor = 6,
		tier = 6,
		skin = "PaleCrawler",
		bars = 5,
		hpPerBar = 5600,
		attack = 40,
		defense = 8,
		guardGauge = 1400,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 16,
		guardPack = { { enemyId = "GlowSpider", count = 3 } },
		lockstep = {
			id = "Braziers",
			name = "Twin Braziers",
			kind = "Lockstep",
			description = "Relight two braziers together to push the darkness back.",
			window = 1.0,
			targets = 2,
			interval = 40,
			failure = "The room goes fully dark",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F6",
		lab = "PaleLantern",
		shatter = "Boss",
		xp = 2110,
		chamber = "Total darkness; only the party's lanterns and two braziers light the cave.",
		phases = {
			{
				bar = 1,
				name = "Darkness",
				summary = "Only the party's lanterns light the room; the crawler comes from outside the light.",
				archetype = "Stalker",
				attacks = {
					{
						id = "Bite",
						name = "Pale Bite",
						telegraph = "Normal",
						windUp = 0.4,
						strike = 0.2,
						recovery = 1.0,
						multiplier = 1.5,
						gaugeDamage = 25,
						reach = 6,
						arc = 45,
						clip = "Bite",
						groundShape = "Cone",
						status = "Paralysis",
					},
					{
						id = "Pounce",
						name = "Pounce",
						telegraph = "Unblockable",
						windUp = 0.6,
						strike = 0.3,
						recovery = 1.2,
						multiplier = 1.7,
						gaugeDamage = 30,
						reach = 14,
						arc = 0,
						clip = "Pounce",
						groundShape = "Line",
					},
				},
				mechanics = {
					{
						id = "Darkness",
						name = "Darkness",
						kind = "Hazard",
						description = "No ambient light; telegraphs read by the lantern's reach.",
					},
				},
				summons = { { enemyId = "GlowSpider", count = 3 } },
			},
			{
				bar = 2,
				name = "Webs",
				summary = "Webs across the floor that paralyze anyone who steps in.",
				archetype = "Stalker",
				attacks = {
					{
						id = "WebSpit",
						name = "Web Spit",
						telegraph = "Unblockable",
						windUp = 1.2,
						strike = 0.4,
						recovery = 1.8,
						multiplier = 1.0,
						gaugeDamage = 10,
						reach = 16,
						arc = 40,
						clip = "Spit",
						groundShape = "Cone",
						status = "Paralysis",
					},
				},
				mechanics = {
					{
						id = "Webs",
						name = "Webs",
						kind = "Hazard",
						description = "Paralysis patches laid every 20 s.",
						interval = 20,
					},
				},
				summons = { { enemyId = "GlowSpider", count = 2 } },
			},
			{
				bar = 5,
				name = "Lantern Eater",
				summary = "It eats a lantern every 20 s; the braziers are the only light left.",
				archetype = "Stalker",
				attacks = {
					{
						id = "Pounce",
						name = "Pounce",
						telegraph = "Unblockable",
						windUp = 0.6,
						strike = 0.3,
						recovery = 1.2,
						multiplier = 1.9,
						gaugeDamage = 30,
						reach = 14,
						arc = 0,
						clip = "Pounce",
						groundShape = "Line",
					},
				},
				mechanics = {
					{
						id = "LanternEater",
						name = "Lantern Eater",
						kind = "Hazard",
						description = "Eats one party lantern per 20 s.",
						interval = 20,
					},
				},
				summons = { { enemyId = "GlowSpider", count = 4 } },
			},
		},
	},

	-- ================================================================== Floor 7
	KhaganOfHooves = {
		id = "KhaganOfHooves",
		name = "Khagan of Hooves",
		floor = 7,
		tier = 7,
		skin = "KhaganOfHooves",
		bars = 5,
		hpPerBar = 6000,
		attack = 44,
		defense = 10,
		guardGauge = 1600,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 14,
		guardPack = { { enemyId = "MinotaurGuard", count = 2 } },
		lockstep = {
			id = "FlankParry",
			name = "Flank Parry",
			kind = "Lockstep",
			description = "A room-crossing charge that must be parried on both flanks within 1 s.",
			window = 1.0,
			targets = 2,
			interval = 35,
			failure = "The charge wipes whoever stands in it",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F7",
		lab = "KhagansGreataxe",
		shatter = "Boss",
		xp = 2700,
		chamber = "A dry arena under acacia; the charge lines are scored into the sand.",
		phases = {
			{
				bar = 1,
				name = "Great Axe",
				summary = "A minotaur with a great axe; charges cross the whole room.",
				archetype = "Brute",
				attacks = {
					{
						id = "Cleave",
						name = "Great Cleave",
						telegraph = "GuardBreak",
						windUp = 1.0,
						strike = 0.35,
						recovery = 1.5,
						multiplier = 1.9,
						gaugeDamage = 70,
						reach = 9,
						arc = 90,
						clip = "Overhead",
						groundShape = "Cone",
					},
					{
						id = "Charge",
						name = "Room Charge",
						telegraph = "Unblockable",
						windUp = 0.8,
						strike = 0.6,
						recovery = 1.8,
						multiplier = 2.2,
						gaugeDamage = 50,
						reach = 60,
						arc = 0,
						clip = "Charge",
						groundShape = "Line",
					},
				},
				mechanics = {},
				summons = { { enemyId = "MinotaurGuard", count = 2 } },
			},
			{
				bar = 3,
				name = "Fists",
				summary = "Throws the axe and fights with fists: Martial Arts kicks and flurries.",
				archetype = "Skirmisher",
				arts = { "MartialArts.PalmStrike", "MartialArts.CrescentKick", "MartialArts.HundredFists" },
				attacks = {
					{
						id = "AxeThrow",
						name = "Axe Throw",
						telegraph = "Unblockable",
						windUp = 0.7,
						strike = 0.3,
						recovery = 1.6,
						multiplier = 1.8,
						gaugeDamage = 40,
						reach = 30,
						arc = 0,
						clip = "AxeThrow",
						groundShape = "Line",
					},
				},
				attackSpeed = 1.2,
				mechanics = {
					{
						id = "AxeThrow",
						name = "Axe Throw",
						kind = "WeaponSwap",
						description = "Throws the axe; it sticks in the sand until bar 5.",
					},
				},
				summons = { { enemyId = "MinotaurGuard", count = 2 } },
			},
			{
				bar = 5,
				name = "Earth Splitter",
				summary = "Picks the axe back up and gains Earth Splitter; the ground shock lines cross the arena.",
				archetype = "Brute",
				weapon = "KhagansGreataxe",
				arts = { "TwoHandedSword.EarthSplitter", "TwoHandedSword.Avalanche" },
				attacks = {
					{
						id = "Cleave",
						name = "Great Cleave",
						telegraph = "GuardBreak",
						windUp = 1.0,
						strike = 0.35,
						recovery = 1.5,
						multiplier = 2.1,
						gaugeDamage = 80,
						reach = 9,
						arc = 90,
						clip = "Overhead",
						groundShape = "Cone",
					},
				},
				mechanics = {
					{
						id = "AxeRecovered",
						name = "The Axe Returns",
						kind = "WeaponSwap",
						description = "Pulls the axe from the sand; Earth Splitter from here.",
					},
				},
				summons = { { enemyId = "MinotaurGuard", count = 3 } },
			},
		},
	},

	-- ================================================================== Floor 8
	RimeclawBehemoth = {
		id = "RimeclawBehemoth",
		name = "Rimeclaw Behemoth",
		floor = 8,
		tier = 8,
		skin = "RimeclawBehemoth",
		bars = 6,
		hpPerBar = 5800,
		attack = 46,
		defense = 11,
		guardGauge = 1900,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 10,
		guardPack = { { enemyId = "FrostWolf", count = 4 } },
		lockstep = {
			id = "IceHearts",
			name = "Ice Hearts",
			kind = "Lockstep",
			description = "Shatter two ice hearts together to clear the freeze stacks on the room.",
			window = 1.0,
			targets = 2,
			interval = 40,
			failure = "Everyone gains a freeze stack",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F8",
		lab = "RimeclawPelt",
		shatter = "Boss",
		xp = 3343,
		chamber = "A frozen cavern; ice pillars for cover, a floor that cracks, a white-out on the last bar.",
		phases = {
			{
				bar = 1,
				name = "Freeze Stacks",
				summary = "Every hit stacks freeze; three stacks freeze a player solid.",
				archetype = "Brute",
				attacks = {
					{
						id = "ClawSweep",
						name = "Claw Sweep",
						telegraph = "GuardBreak",
						windUp = 1.0,
						strike = 0.35,
						recovery = 1.5,
						multiplier = 1.8,
						gaugeDamage = 70,
						reach = 9,
						arc = 120,
						clip = "Overhead",
						groundShape = "Cone",
						status = "Freeze",
					},
				},
				mechanics = {
					{
						id = "FreezeStacks",
						name = "Freeze Stacks",
						kind = "Hazard",
						description = "Three freeze stacks freeze solid for 6 s.",
					},
				},
				summons = { { enemyId = "FrostWolf", count = 4 } },
			},
			{
				bar = 2,
				name = "Ice Pillars",
				summary = "Ice pillars rise as cover against a freezing breath.",
				archetype = "Brute",
				attacks = {
					{
						id = "Breath",
						name = "Freezing Breath",
						telegraph = "Unblockable",
						windUp = 1.2,
						strike = 0.4,
						recovery = 2.0,
						multiplier = 1.6,
						gaugeDamage = 30,
						reach = 30,
						arc = 60,
						clip = "Breath",
						groundShape = "Cone",
						status = "Freeze",
					},
				},
				mechanics = {
					{
						id = "Pillars",
						name = "Ice Pillars",
						kind = "Terrain",
						description = "Pillars block the breath; they shatter after one.",
					},
				},
				summons = { { enemyId = "FrostWolf", count = 2 } },
			},
			{
				bar = 4,
				name = "Cracked Floor",
				summary = "The floor cracks; standing on a crack when it breaks drops the player to the lower ice.",
				archetype = "Brute",
				attacks = {
					{
						id = "Stomp",
						name = "Stomp",
						telegraph = "Unblockable",
						windUp = 0.9,
						strike = 0.4,
						recovery = 1.6,
						multiplier = 1.5,
						gaugeDamage = 40,
						reach = 10,
						arc = 360,
						clip = "Stomp",
						groundShape = "Circle",
					},
				},
				mechanics = {
					{
						id = "CrackedFloor",
						name = "Cracked Floor",
						kind = "Hazard",
						description = "Cracks spread from each stomp.",
						interval = 25,
					},
				},
				summons = { { enemyId = "FrostWolf", count = 4 } },
			},
			{
				bar = 6,
				name = "White-Out",
				summary = "The room goes white; telegraphs are sound only.",
				archetype = "Brute",
				attacks = {
					{
						id = "ClawSweep",
						name = "Claw Sweep",
						telegraph = "GuardBreak",
						windUp = 1.0,
						strike = 0.35,
						recovery = 1.5,
						multiplier = 2.0,
						gaugeDamage = 80,
						reach = 9,
						arc = 120,
						clip = "Overhead",
						groundShape = "Cone",
						status = "Freeze",
					},
				},
				mechanics = {
					{
						id = "WhiteOut",
						name = "White-Out",
						kind = "Hazard",
						description = "Visibility zero; the wind-up vocalizations are the telegraph.",
					},
				},
				summons = { { enemyId = "FrostWolf", count = 4 } },
			},
		},
	},

	-- ================================================================== Floor 9
	HexenStag = {
		id = "HexenStag",
		name = "Hexen Stag",
		floor = 9,
		tier = 9,
		skin = "HexenStag",
		bars = 5,
		hpPerBar = 6200,
		attack = 48,
		defense = 9,
		guardGauge = 1500,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 20,
		guardPack = { { enemyId = "ShadeHound", count = 3 } },
		lockstep = {
			id = "Shrines",
			name = "Twin Shrines",
			kind = "Lockstep",
			description = "Desecrate two shrines in sync to stop the teleports for 15 s.",
			window = 1.0,
			targets = 2,
			interval = 45,
			failure = "It teleports and heals",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F9",
		lab = "HexenCrown",
		shatter = "Boss",
		xp = 4036,
		chamber = "A twilight glade with four shrines; fireflies mark the real stag.",
		phases = {
			{
				bar = 1,
				name = "Four Shrines",
				summary = "Teleports between four shrines and gores whoever stands between them.",
				archetype = "Charger",
				attacks = {
					{
						id = "Charge",
						name = "Antler Charge",
						telegraph = "Normal",
						windUp = 0.6,
						strike = 0.5,
						recovery = 1.4,
						multiplier = 1.9,
						gaugeDamage = 40,
						reach = 24,
						arc = 0,
						clip = "Charge",
						groundShape = "Line",
					},
					{
						id = "Gore",
						name = "Gore",
						telegraph = "Unblockable",
						windUp = 0.7,
						strike = 0.3,
						recovery = 1.2,
						multiplier = 1.7,
						gaugeDamage = 35,
						reach = 10,
						arc = 0,
						clip = "Thrust",
						groundShape = "Line",
					},
				},
				mechanics = {
					{
						id = "Teleport",
						name = "Shrine Teleport",
						kind = "Terrain",
						description = "Blinks to a shrine every 12 s.",
						interval = 12,
					},
				},
				summons = { { enemyId = "ShadeHound", count = 3 } },
			},
			{
				bar = 3,
				name = "False Stags",
				summary = "Two false stags; hit the one with the Switch window.",
				archetype = "Charger",
				attacks = {
					{
						id = "Charge",
						name = "Antler Charge",
						telegraph = "Normal",
						windUp = 0.6,
						strike = 0.5,
						recovery = 1.4,
						multiplier = 1.9,
						gaugeDamage = 40,
						reach = 24,
						arc = 0,
						clip = "Charge",
						groundShape = "Line",
					},
				},
				mechanics = {
					{
						id = "FalseStags",
						name = "False Stags",
						kind = "Illusion",
						description = "Two illusions; only the real one opens a Switch window.",
					},
				},
				summons = { { enemyId = "ShadeHound", count = 2 } },
			},
			{
				bar = 5,
				name = "The Forest Comes In",
				summary = "The forest grows into the room and Stalkers spawn from the undergrowth.",
				archetype = "Charger",
				attacks = {
					{
						id = "Gore",
						name = "Gore",
						telegraph = "Unblockable",
						windUp = 0.7,
						strike = 0.3,
						recovery = 1.2,
						multiplier = 1.9,
						gaugeDamage = 35,
						reach = 10,
						arc = 0,
						clip = "Thrust",
						groundShape = "Line",
					},
				},
				mechanics = {
					{
						id = "Overgrowth",
						name = "Overgrowth",
						kind = "Summon",
						description = "Shade Hounds every 20 s from the undergrowth.",
						interval = 20,
					},
				},
				summons = { { enemyId = "ShadeHound", count = 4 } },
			},
		},
	},

	-- ================================================================== Floor 10 (Haven)
	WardensKnight = {
		id = "WardensKnight",
		name = "The Warden's Knight",
		floor = 10,
		tier = 10,
		skin = "WardensKnight",
		bars = 6,
		hpPerBar = 6000,
		attack = 50,
		defense = 14,
		guardGauge = 2000,
		guardRegenPerSecond = GUARD_REGEN,
		moveSpeed = 16,
		guardPack = { { enemyId = "CitadelKnight", count = 2 }, { enemyId = "HonorGuardCaptain", count = 1 } },
		lockstep = {
			id = "OctaveParry",
			name = "Octave Parry",
			kind = "Lockstep",
			description = "Two players must parry its Howling Octave's third and fifth hits.",
			window = 1.0,
			targets = 2,
			interval = 30,
			failure = "The Octave finishes on the whole raid",
		},
		enrage = { startSeconds = 480, damagePerMinute = 0.1 },
		mirrorShield = true,
		lootTable = "Boss.F10",
		lab = "WardensSabre",
		shatter = "Boss",
		xp = 4777,
		chamber = "A white citadel hall with banners; the first boss that Switches with its own Honor Guard.",
		phases = {
			{
				bar = 1,
				name = "Sword and Shield",
				summary = "A humanoid knight with the full 1H Sword Art list and a shield; it Switches with its Honor Guard.",
				archetype = "Guard",
				arts = {
					"OneHandedSword.Horizontal",
					"OneHandedSword.Vertical",
					"OneHandedSword.RisingArc",
					"OneHandedSword.SharpNail",
					"OneHandedSword.SonicLeap",
					"OneHandedSword.LanceThrust",
					"OneHandedSword.HowlingOctave",
					"OneHandedSword.NovaAscension",
				},
				attacks = {
					{
						id = "ShieldBash",
						name = "Shield Bash",
						telegraph = "Normal",
						windUp = 0.5,
						strike = 0.3,
						recovery = 1.2,
						multiplier = 1.3,
						gaugeDamage = 50,
						reach = 5,
						arc = 60,
						clip = "ShieldBash",
						groundShape = "Cone",
						status = "Stun",
					},
				},
				mechanics = {
					{
						id = "GuardSwitch",
						name = "Honor Guard Switch",
						kind = "Summon",
						description = "The Honor Guard Switches with the Knight; its Arts gain the Switch bonus.",
						interval = 0,
					},
				},
				summons = { { enemyId = "CitadelKnight", count = 2 }, { enemyId = "HonorGuardCaptain", count = 1 } },
			},
			{
				bar = 4,
				name = "Two Blades",
				summary = "Sheds the shield and takes Twin Fang Arts: a foreshadowing.",
				archetype = "Skirmisher",
				weapon = "WardensTwinSabres",
				arts = { "TwinFang.DoubleCircular", "TwinFang.QuadFang", "TwinFang.ShearingWind", "TwinFang.TwinLance" },
				attacks = {
					{
						id = "CrossCut",
						name = "Cross Cut",
						telegraph = "Unblockable",
						windUp = 0.7,
						strike = 0.25,
						recovery = 1.2,
						multiplier = 1.8,
						gaugeDamage = 40,
						reach = 7,
						arc = 90,
						clip = "CrossCut",
						groundShape = "Cone",
					},
				},
				attackSpeed = 1.15,
				mechanics = {
					{
						id = "ShedShield",
						name = "Shed the Shield",
						kind = "WeaponSwap",
						description = "Drops the shield and draws a second blade.",
					},
				},
				summons = { { enemyId = "CitadelKnight", count = 2 } },
			},
			{
				bar = 6,
				name = "Forced Duelist Protocol",
				summary = "Minions leave and the raid fights a swordsman; Duelist Protocol is forced for everyone.",
				archetype = "Skirmisher",
				arts = {
					"TwinFang.DoubleCircular",
					"TwinFang.QuadFang",
					"TwinFang.ShearingWind",
					"TwinFang.TwinLance",
					"TwinFang.MeteorCascade",
				},
				attacks = {
					{
						id = "CrossCut",
						name = "Cross Cut",
						telegraph = "Unblockable",
						windUp = 0.7,
						strike = 0.25,
						recovery = 1.2,
						multiplier = 2.0,
						gaugeDamage = 40,
						reach = 7,
						arc = 90,
						clip = "CrossCut",
						groundShape = "Cone",
					},
				},
				attackSpeed = 1.25,
				mechanics = {
					{
						id = "ForcedDuelist",
						name = "Forced Duelist Protocol",
						kind = "Shield",
						description = "Minions leave, the Mirror Shield drops, torches dim to a spotlight.",
					},
				},
			},
		},
	},
}

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

Bosses.rows = rows

--- The boss with this id (tier-1 base values), or nil.
function Bosses.byId(id: string): Types.BossDef?
	return rows[id]
end

--- The floor boss of a floor, or nil.
function Bosses.forFloor(floor: number): Types.BossDef?
	for _, def in rows do
		if def.floor == floor then
			return def
		end
	end
	return nil
end

--- Every boss sorted by floor.
function Bosses.list(): { Types.BossDef }
	local list = {}
	for _, def in rows do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.floor < b.floor
	end)
	return list
end

--- Total HP across every bar at the boss's floor tier.
function Bosses.totalHp(def: Types.BossDef): number
	return math.floor(def.bars * def.hpPerBar * Tiers.get(def.tier).hp + 0.5)
end

--- A copy with the floor tier applied to hp, attack, defense and gauge (xp is already a level's worth).
function Bosses.scaled(def: Types.BossDef): Types.BossDef
	local copy = table.clone(def)
	local tier = Tiers.get(def.tier)
	copy.hpPerBar = math.floor(def.hpPerBar * tier.hp + 0.5)
	copy.attack = def.attack * tier.attack
	copy.defense = math.floor(def.defense * tier.defense + 0.5)
	copy.guardGauge = math.floor(def.guardGauge * tier.gauge + 0.5)
	return copy
end

--- The phase active on a given bar (1 = first bar): the last phase whose `bar` is at or below it.
function Bosses.phaseForBar(def: Types.BossDef, bar: number): Types.BossPhaseDef
	local active = def.phases[1]
	for _, phase in def.phases do
		if phase.bar <= bar then
			active = phase
		end
	end
	return active
end

--- Damage multiplier from enrage at `elapsed` seconds into the fight: 1 before the start, +10% per minute after.
function Bosses.enrageMultiplier(def: Types.BossDef, elapsed: number): number
	local over = elapsed - def.enrage.startSeconds
	if over <= 0 then
		return 1
	end
	return 1 + def.enrage.damagePerMinute * math.floor(over / 60 + 1)
end

--- Whether Overwhelm applies for a chamber with this many players (section 7).
function Bosses.overwhelms(playerCount: number): boolean
	return playerCount < Bosses.rules.overwhelmBelowPlayers
end

return Bosses
