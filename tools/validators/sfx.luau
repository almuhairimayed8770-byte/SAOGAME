--!strict
--[[
	SFX validator: every entry has an asset id string, a volume in 0..1, a boolean `spatial`, an
	optional ordered pitchRange, and routes to a declared SoundGroup; the section 15 families are
	present; a placeholder id must be flagged placeholder = true.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local REQUIRED_FAMILIES = {
	"artChime",
	"whoosh",
	"impact",
	"hitStopTick",
	"guard",
	"shatter",
	"footsteps",
	"telegraph",
	"enemy",
	"ui",
	"voice",
	"world",
	"ambience",
}

local REQUIRED_ENTRIES = {
	{ "guard", "Parry" },
	{ "guard", "Block" },
	{ "guard", "GuardBreak" },
	{ "shatter", "Crack" },
	{ "shatter", "BossCrack" },
	{ "telegraph", "Tick" },
	{ "hitStopTick", "Normal" },
	{ "impact", "Flesh" },
	{ "impact", "Armor" },
	{ "impact", "Construct" },
	{ "whoosh", "Small" },
	{ "whoosh", "Medium" },
	{ "whoosh", "Large" },
	{ "ui", "MenuOpen" },
	{ "ui", "MenuClose" },
	{ "voice", "Countdown" },
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

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end

	local Sfx = ctx.load("src/shared/data/sfx")
	local Palette = ctx.load("src/shared/data/palette")

	local groups: { [string]: boolean } = {}
	for _, name in Sfx.groups do
		groups[name] = true
	end
	for _, name in { "Master", "Music", "SFX", "UI", "Voice" } do
		if not groups[name] then
			problem("sfx.groups is missing the '%s' SoundGroup", name)
		end
	end

	for _, family in REQUIRED_FAMILIES do
		if typeof(Sfx.families[family]) ~= "table" then
			problem("sfx.families is missing '%s'", family)
		end
	end
	for _, pair in REQUIRED_ENTRIES do
		local family = Sfx.families[pair[1]]
		if typeof(family) == "table" and typeof(family.entries[pair[2]]) ~= "table" then
			problem("sfx.families.%s is missing the '%s' entry", pair[1], pair[2])
		end
	end

	-- One chime per trail color and one vocalization set per archetype.
	local chimes = if typeof(Sfx.families.artChime) == "table" then Sfx.families.artChime.entries else {}
	for token in Palette.tokens do
		if token:sub(1, 5) == "Trail" and typeof(chimes[token]) ~= "table" then
			problem("sfx.families.artChime has no chime for trail color '%s'", token)
		end
	end
	local enemy = if typeof(Sfx.families.enemy) == "table" then Sfx.families.enemy.entries else {}
	for _, archetype in ARCHETYPES do
		for _, moment in { "WindUp", "Strike", "Stagger", "Death" } do
			if typeof(enemy[archetype .. moment]) ~= "table" then
				problem("sfx.families.enemy is missing '%s%s'", archetype, moment)
			end
		end
	end

	for family, group in Sfx.families do
		if typeof(group.group) ~= "string" or not groups[group.group] then
			problem("sfx.families.%s routes to unknown SoundGroup '%s'", family, tostring(group.group))
		end
		if typeof(group.entries) ~= "table" or next(group.entries) == nil then
			problem("sfx.families.%s has no entries", family)
			continue
		end
		for name, entry in group.entries do
			local label = ("sfx.families.%s.%s"):format(family, name)
			if typeof(entry.id) ~= "string" or not entry.id:match("^rbxassetid://%d+$") then
				problem("%s: id must be an rbxassetid:// string", label)
			end
			if typeof(entry.volume) ~= "number" or entry.volume < 0 or entry.volume > 1 then
				problem("%s: volume must be a number in 0..1", label)
			end
			if typeof(entry.spatial) ~= "boolean" then
				problem("%s: spatial must be a boolean", label)
			end
			if typeof(entry.placeholder) ~= "boolean" then
				problem("%s: placeholder must be a boolean", label)
			elseif entry.id == Sfx.placeholderId and not entry.placeholder then
				problem("%s: a 0 asset id must be marked placeholder = true", label)
			end
			if entry.pitchRange ~= nil then
				local range = entry.pitchRange
				if typeof(range) ~= "table" or typeof(range[1]) ~= "number" or typeof(range[2]) ~= "number" then
					problem("%s: pitchRange must be {min, max}", label)
				elseif range[1] <= 0 or range[1] > range[2] then
					problem("%s: pitchRange must be positive and ordered", label)
				end
			end
		end
	end

	if typeof(Sfx.mix) ~= "table" or typeof(Sfx.mix.systemVoiceDuckDb) ~= "number" then
		problem("sfx.mix must hold the section 15 mix rules")
	elseif Sfx.mix.systemVoiceDuckDb ~= 8 or Sfx.mix.mobileMusicOffsetDb ~= -2 then
		problem("sfx.mix: the system voice ducks by 8 dB and mobile music sits 2 dB lower")
	end

	return problems
end
