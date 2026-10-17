--!strict
--[[
	Sound effects (section 15): one named entry per sound, grouped by family, with the SoundGroup
	each family routes to and the mix rules. Every id is a placeholder (`rbxassetid://0`,
	placeholder = true) until the user uploads sounds; docs/PLACEHOLDERS.md lists them and the
	sfx validator reports any entry that is still a placeholder when placeholder is false.

	Entry fields: id (asset url), placeholder, volume (0..1), pitchRange ({min, max} PlaybackSpeed,
	optional; the pool picks a random value in it), spatial (true = 3D at the source, false = 2D).
]]

export type Entry = {
	id: string,
	placeholder: boolean,
	volume: number,
	pitchRange: { number }?,
	spatial: boolean,
	note: string?,
}

export type Family = {
	group: string, -- SoundGroup name
	entries: { [string]: Entry },
}

local PLACEHOLDER = "rbxassetid://0"

local function sound(volume: number, spatial: boolean, pitchRange: { number }?, note: string?): Entry
	return {
		id = PLACEHOLDER,
		placeholder = true,
		volume = volume,
		pitchRange = pitchRange,
		spatial = spatial,
		note = note,
	}
end

local TRAIL_COLORS = {
	"TrailCyanWhite",
	"TrailPaleGold",
	"TrailCrimson",
	"TrailSilverBlue",
	"TrailViolet",
	"TrailJade",
	"TrailOrange",
	"TrailAmber",
	"TrailWhite",
	"TrailRose",
	"TrailIvory",
}

local ARCHETYPES = {
	"Charger",
	"Brute",
	"Skirmisher",
	"Lancer",
	"Swarm",
	"Guard",
	"CasterBeast",
	"Stalker",
	"WardenConstruct",
}

local SURFACES = { "Stone", "Grass", "Wood", "Water", "Snow", "Gravel" }
local WEIGHTS = { "Light", "Armored" }

-- Art activation chime, one per trail color; the pool pitches it by weapon weight at play time.
local artChime: { [string]: Entry } = {}
for _, color in TRAIL_COLORS do
	artChime[color] = sound(0.7, true, { 0.95, 1.05 }, "pitched down by weapon weight")
end
artChime.TwinFang = sound(0.75, true, { 0.95, 1.05 }, "both colors; a two-note chime")

local vocalizations: { [string]: Entry } = {}
for _, archetype in ARCHETYPES do
	local quiet = archetype == "Stalker"
	local volume = if quiet then 0.25 else 0.8
	vocalizations[archetype .. "WindUp"] = sound(volume, true, { 0.9, 1.1 })
	vocalizations[archetype .. "Strike"] = sound(volume, true, { 0.9, 1.1 })
	vocalizations[archetype .. "Stagger"] = sound(volume, true, { 0.9, 1.1 })
	vocalizations[archetype .. "Death"] = sound(volume, true, { 0.95, 1.05 })
end
vocalizations.SwarmHiss = sound(0.6, true, { 0.9, 1.2 })
vocalizations.ChargerSnort = sound(0.8, true, { 0.9, 1.1 })
vocalizations.BruteRoar = sound(0.9, true, { 0.85, 1.0 })

local footsteps: { [string]: Entry } = {}
for _, surface in SURFACES do
	for _, weight in WEIGHTS do
		footsteps[surface .. weight] = sound(if weight == "Armored" then 0.5 else 0.35, true, { 0.92, 1.08 })
	end
end
footsteps.LandSoft = sound(0.45, true, { 0.95, 1.05 }, "short falls")
footsteps.LandHard = sound(0.7, true, { 0.9, 1.0 }, "scaled by fall height")

local Sfx = {
	placeholderId = PLACEHOLDER,

	--- SoundGroup names (section 15); each has a settings slider.
	groups = { "Master", "Music", "SFX", "UI", "Voice" },

	--- Mix rules (section 15). dB values are offsets applied by the SfxPool / MusicDirector.
	mix = {
		combatOverMusicDb = 3, -- combat SFX sit above music
		heartbeatOverAllDb = 3, -- the HP heartbeat sits above both
		systemVoiceDuckDb = 8, -- the system voice ducks everything
		mobileMusicOffsetDb = -2, -- mobile defaults music lower
		deathDuckSeconds = 0.5, -- silence before the shatter (combat.deathFreeze mirrors this)
		pooledVoicesPerEntry = 4, -- Sound instances pooled per entry
		maxSimultaneousSpatial = 24,
		rolloffMinDistance = 10, -- studs; RollOffMinDistance on 3D sounds
		rolloffMaxDistance = 140,
	},

	--- Adaptive music numbers (section 15) for MusicDirector.
	music = {
		stems = { "ambient", "explore", "combat", "boss" },
		crossfadeSeconds = 2,
		combatEndDelaySeconds = 6, -- combat music ends this long after the last shatter
		bossEntranceSilenceSeconds = 1,
		lowHpHeartbeatFraction = 0.25, -- below this HP fraction the heartbeat layer rises
		townCues = { "day", "night" },
		havenCues = { "fishing" },
		duelistProtocolCue = "duelist",
	},

	families = {
		artChime = { group = "SFX", entries = artChime },

		whoosh = {
			group = "SFX",
			entries = {
				Small = sound(0.5, true, { 0.95, 1.1 }, "daggers, rapier points"),
				Medium = sound(0.6, true, { 0.95, 1.05 }, "one-handed arcs"),
				Large = sound(0.75, true, { 0.85, 1.0 }, "two-handed, axes, spears"),
				Basic = sound(0.4, true, { 0.95, 1.1 }, "the thinner basic swing"),
			},
		},

		impact = {
			group = "SFX",
			entries = {
				Flesh = sound(0.8, true, { 0.95, 1.05 }),
				Armor = sound(0.8, true, { 0.95, 1.05 }),
				Construct = sound(0.8, true, { 0.95, 1.05 }),
				Ring = sound(0.35, true, { 0.98, 1.02 }, "the short metallic ring layered on every impact"),
				FinalHit = sound(0.9, true, { 0.95, 1.0 }, "the last hit of an Art"),
				Kill = sound(1, true, { 0.95, 1.0 }),
			},
		},

		hitStopTick = {
			group = "SFX",
			entries = {
				Normal = sound(0.4, false, nil, "3 frames"),
				Final = sound(0.5, false, nil, "6 frames"),
				Kill = sound(0.6, false, nil, "10 frames"),
			},
		},

		guard = {
			group = "SFX",
			entries = {
				Parry = sound(0.9, true, { 0.98, 1.02 }, "bright steel clash with a 0.3 s ring"),
				Block = sound(0.6, true, { 0.95, 1.05 }, "a dull block"),
				GuardBreak = sound(0.85, true, { 0.95, 1.0 }, "a crack"),
				GuardRaise = sound(0.3, true, { 0.95, 1.05 }),
				MirrorReflect = sound(0.7, true, { 0.98, 1.02 }, "a Mirror Shield sending a hit back"),
			},
		},

		shatter = {
			group = "SFX",
			entries = {
				Crack = sound(0.9, true, nil, "the glass crack"),
				Chime = sound(0.7, true, nil, "the rising chime cluster after the crack"),
				BossCrack = sound(1, true, { 0.7, 0.75 }, "slow version with a low boom"),
				BossBoom = sound(1, false, nil),
				TeleportRise = sound(0.7, true, nil, "the shatter reversed for the Gate"),
				TeleportArrive = sound(0.7, true, nil),
			},
		},

		footsteps = { group = "SFX", entries = footsteps },

		telegraph = {
			group = "SFX",
			entries = {
				Tick = sound(0.5, true, { 0.98, 1.02 }, "the wind-up start"),
				Unblockable = sound(0.6, true, { 0.98, 1.02 }, "red edge"),
				GuardBreak = sound(0.6, true, { 0.98, 1.02 }, "yellow edge"),
			},
		},

		enemy = { group = "SFX", entries = vocalizations },

		ui = {
			group = "UI",
			entries = {
				MenuOpen = sound(0.5, false, nil, "the gesture chime"),
				MenuClose = sound(0.45, false, nil),
				SystemLine = sound(0.5, false, nil, "the short chime under a centered system line"),
				SystemLineWarded = sound(0.5, false, nil, "purple popups"),
				Pickup = sound(0.45, false, { 0.98, 1.02 }),
				Crowns = sound(0.45, false, { 0.98, 1.02 }),
				Equip = sound(0.45, false, nil),
				DropCommon = sound(0.3, true, nil),
				DropUncommon = sound(0.35, true, nil),
				DropRare = sound(0.4, true, nil),
				DropEpic = sound(0.45, true, nil),
				DropLegendary = sound(0.6, true, nil, "rings"),
				SwitchPrompt = sound(0.5, false, nil),
				SwitchLand = sound(0.6, true, nil, "both trails flash white"),
				LevelUp = sound(0.6, false, nil),
				LowHpHeartbeat = sound(0.7, false, nil, "loops below 25% HP"),
				BossBarFill = sound(0.5, false, nil, "one per bar on the entrance"),
				BossBarCrack = sound(0.6, false, nil, "a bar emptied"),
			},
		},

		voice = {
			group = "Voice",
			entries = {
				Countdown = sound(0.8, false, nil, "login ritual sensory checks; TTS stub"),
				FloorClear = sound(0.8, false, nil, "TTS stub"),
				Death = sound(0.8, false, nil, "reads the struck name; TTS stub"),
				Architect = sound(0.9, false, nil, "the announcement; TTS stub"),
				RareRoll = sound(0.8, false, nil, "a Dual Wielder has entered the Spire; TTS stub"),
			},
		},

		world = {
			group = "SFX",
			entries = {
				ShardUse = sound(0.6, true, nil),
				SmithHammer = sound(0.7, true, { 0.95, 1.05 }),
				SmithCrackle = sound(0.4, true, nil, "forge loop"),
				FishingSplash = sound(0.5, true, { 0.95, 1.05 }),
				FishingReel = sound(0.4, true, nil),
				GateHum = sound(0.35, true, nil, "the Teleport Gate pillar loop"),
				TorchFlare = sound(0.5, true, { 0.95, 1.05 }, "boss entrance torches"),
				BossDoors = sound(0.9, true, nil),
			},
		},

		ambience = {
			group = "SFX",
			entries = {
				RimWind = sound(0.35, false, nil, "everywhere at the rim"),
				Plains = sound(0.3, false, nil, "birds"),
				Marsh = sound(0.3, false, nil, "frogs"),
				Forest = sound(0.3, false, nil),
				Coast = sound(0.3, false, nil, "gulls, surf"),
				Cave = sound(0.3, false, nil, "drips"),
				Savanna = sound(0.3, false, nil),
				Snow = sound(0.25, false, nil, "silence with wind"),
				Twilight = sound(0.3, false, nil),
				Volcanic = sound(0.3, false, nil),
				Canyon = sound(0.3, false, nil, "wind through rock"),
				Jungle = sound(0.3, false, nil),
				Ruin = sound(0.3, false, nil, "citadel bells"),
				Labyrinth = sound(0.3, false, nil, "a low drone"),
			},
		},
	} :: { [string]: Family },
}

--- One entry by family and name; errors on an unknown pair so a missing sound fails at load.
function Sfx.get(family: string, name: string): Entry
	local group = Sfx.families[family]
	if group == nil then
		error(("sfx: unknown family '%s'"):format(tostring(family)))
	end
	local entry = group.entries[name]
	if entry == nil then
		error(("sfx: unknown sound '%s.%s'"):format(family, tostring(name)))
	end
	return entry
end

--- Every entry as a flat list of {family, name, entry}, sorted, for validators and the pool.
function Sfx.all(): { { family: string, name: string, entry: Entry } }
	local list = {}
	for family, group in Sfx.families do
		for name, entry in group.entries do
			table.insert(list, { family = family, name = name, entry = entry })
		end
	end
	table.sort(list, function(a, b)
		if a.family == b.family then
			return a.name < b.name
		end
		return a.family < b.family
	end)
	return list
end

--- The SoundGroup a family routes to.
function Sfx.groupOf(family: string): string
	local group = Sfx.families[family]
	if group == nil then
		error(("sfx: unknown family '%s'"):format(tostring(family)))
	end
	return group.group
end

return Sfx
