--!strict
local Sfx = Harness.load("src/shared/data/sfx")
local Palette = Harness.load("src/shared/data/palette")
local Fx = Harness.load("src/shared/data/fx")
local Combat = Harness.load("src/shared/data/combat")

local function entryOf(name: string): any
	local family, entryName = name:match("^([^%.]+)%.(.+)$")
	return Sfx.get(family :: string, entryName :: string)
end

describe("sfx data", function()
	it("declares the five SoundGroups and the mix rules", function()
		expect(Sfx.groups).toEqual({ "Master", "Music", "SFX", "UI", "Voice" })
		expect(Sfx.mix.systemVoiceDuckDb).toBe(8)
		expect(Sfx.mix.mobileMusicOffsetDb).toBe(-2)
		expect(Sfx.music.crossfadeSeconds).toBe(2)
		expect(Sfx.music.combatEndDelaySeconds).toBe(6)
		expect(Sfx.music.bossEntranceSilenceSeconds).toBe(1)
	end)

	it("has an activation chime per trail color", function()
		for token in Palette.tokens do
			if token:sub(1, 5) == "Trail" then
				expect(Sfx.get("artChime", token).spatial).toBe(true)
			end
		end
	end)

	it("gives every entry an id, a volume and a spatial flag; a placeholder is rbxassetid://0", function()
		local all = Sfx.all()
		expect(#all).toBeGreaterThan(100)
		for _, row in all do
			local entry = row.entry
			if entry.placeholder then
				expect(entry.id).toBe("rbxassetid://0")
				expect(Sfx.isReal(entry)).toBe(false)
			else
				expect(entry.id:match("^rbxassetid://[1-9]%d*$")).never.toBeNil()
				expect(Sfx.isReal(entry)).toBe(true)
			end
			expect(entry.volume).toBeGreaterThan(0)
			expect(entry.volume).toBeLessThanOrEqual(1)
			expect(typeof(entry.spatial)).toBe("boolean")
			if entry.pitchRange then
				expect(entry.pitchRange[1]).toBeLessThanOrEqual(entry.pitchRange[2])
			end
		end
		for index = 2, #all do
			local previous, current = all[index - 1], all[index]
			expect(
				previous.family < current.family or (previous.family == current.family and previous.name < current.name)
			).toBe(true)
		end
	end)

	it("routes families to their groups", function()
		expect(Sfx.groupOf("ui")).toBe("UI")
		expect(Sfx.groupOf("voice")).toBe("Voice")
		expect(Sfx.groupOf("impact")).toBe("SFX")
		expect(Sfx.get("hitStopTick", "Kill").spatial).toBe(false)
	end)

	it("errors on unknown families and names", function()
		expect(function()
			Sfx.get("magic", "Fireball")
		end).toThrow("unknown family")
		expect(function()
			Sfx.get("guard", "Fireball")
		end).toThrow("unknown sound")
		expect(function()
			Sfx.groupOf("magic")
		end).toThrow("unknown family")
		expect(function()
			Sfx.vocalName("Dragon", "Death")
		end).toThrow("unknown sound")
	end)

	it("names an archetype's vocalizations and an entry's audible region", function()
		expect(Sfx.vocalName("Charger", "Death")).toBe("enemy.ChargerDeath")
		expect(Sfx.vocalMoments).toEqual({ "WindUp", "Strike", "Stagger", "Death" })
		-- The riser plays 0.15..0.46 of its asset; its end lands on the first damage frame.
		local first, last = Sfx.region(Sfx.get("whoosh", "Riser"))
		expect(first).toBe(0.15)
		expect(last).toBe(0.46)
		-- No trim: the whole asset, or past any asset when its length is not listed either.
		first, last =
			Sfx.region({ id = "rbxassetid://5", placeholder = false, volume = 1, spatial = false, length = 2 })
		expect(first).toBe(0)
		expect(last).toBe(2)
		first, last = Sfx.region(Sfx.get("voice", "Countdown"))
		expect(first).toBe(0)
		expect(last).toBe(Sfx.playback.openEndSeconds)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The 50 picks from the licensed library, exactly as the pick list gives them, with the title,
-- creator and length the library lists for each id
-- ------------------------------------------------------------------------------------------

-- { slot, id, startAt, stopAt, fadeOut, volume, pitchMin, pitchMax, loop, length, creator, title }
local PICKS: { { any } } = {
	{
		"whoosh.Small",
		"9119749145",
		0,
		0.32,
		0.06,
		0.35,
		0.95,
		1.1,
		false,
		0.96,
		"ProSoundEffects",
		"Sword Swish 102 (SFX)",
	},
	{
		"whoosh.Medium",
		"9119749044",
		0.34,
		0.55,
		0.06,
		0.32,
		0.95,
		1.05,
		false,
		0.9,
		"ProSoundEffects",
		"Sword Swish 201 (SFX)",
	},
	{
		"whoosh.Large",
		"9126229280",
		0.09,
		0.53,
		0.08,
		0.36,
		0.85,
		1,
		false,
		1.45,
		"ProSoundEffects",
		"Whoosh By Fast Airy Swooshing Whipping Thuds (SFX)",
	},
	{
		"whoosh.Basic",
		"9119750698",
		1.03,
		1.75,
		0.3,
		0.8,
		0.95,
		1.1,
		false,
		3.08,
		"ProSoundEffects",
		"Sword Whip 104 (SFX)",
	},
	{
		"whoosh.Dodge",
		"9114890978",
		0.2,
		0.58,
		0.08,
		0.5,
		0.95,
		1.08,
		false,
		0.91,
		"ProSoundEffects",
		"Jump Swish 1 (SFX)",
	},
	{
		"whoosh.Riser",
		"9118158252",
		0.15,
		0.46,
		0,
		0.7,
		0.98,
		1.02,
		false,
		1.5,
		"ProSoundEffects",
		"Reversed Whoosh Backwards Hissing Burst 3 (SFX)",
	},
	{
		"impact.Crack",
		"9120660382",
		0.39,
		0.62,
		0.05,
		0.65,
		0.96,
		1.04,
		false,
		1.18,
		"ProSoundEffects",
		"Whip Cracks 2 (SFX)",
	},
	{ "impact.Body", "9113502506", 0, 0.5, 0.3, 0.8, 0.95, 1.05, false, 1.12, "ProSoundEffects", "Body Hits 8 (SFX)" },
	{ "impact.Sub", "1837830050", 0.04, 0.85, 0.55, 0.7, 0.97, 1.02, false, 4.32, "APMOfficial", "BOOM-Sub Boom 01" },
	{
		"impact.Ring",
		"9125362690",
		0,
		0.27,
		0.05,
		0.65,
		0.98,
		1.02,
		false,
		1.09,
		"ProSoundEffects",
		"Anvil Hits Ringing Metal Clinks Some Muted 3 (SFX)",
	},
	{
		"impact.RingTail",
		"9119747477",
		0.25,
		2.5,
		1.4,
		0.38,
		0.98,
		1.02,
		false,
		18.4,
		"ProSoundEffects",
		"Sword Long Metallic Ring Decay 1 (SFX)",
	},
	{
		"impact.SubDrop",
		"1835344220",
		0.22,
		2.2,
		0.7,
		0.55,
		1,
		1,
		false,
		2.44,
		"APMOfficial",
		"Super Predator Bass Drop",
	},
	{
		"impact.Flesh",
		"9116485156",
		0.27,
		0.72,
		0.15,
		0.6,
		0.95,
		1.05,
		false,
		1.37,
		"ProSoundEffects",
		"Meat Hack Fleshy Hits 2 (SFX)",
	},
	{
		"impact.Armor",
		"9119072660",
		0,
		0.3,
		0.05,
		0.28,
		0.95,
		1.05,
		false,
		0.74,
		"ProSoundEffects",
		"Shield Clang As Hit Metal Sword Hubcap 1 (SFX)",
	},
	{
		"impact.Construct",
		"9118587701",
		0.25,
		0.5,
		0.08,
		1,
		0.95,
		1.05,
		false,
		2.01,
		"ProSoundEffects",
		"Rock Drop On Concrete Drops Breaks 4 (SFX)",
	},
	{
		"impact.FinalHit",
		"9119746592",
		0.17,
		0.36,
		0.05,
		0.4,
		0.95,
		1,
		false,
		1.19,
		"ProSoundEffects",
		"Sword Hit 2 (SFX)",
	},
	{ "impact.Kill", "9120113588", 0.1, 0.75, 0.4, 1, 0.95, 1, false, 2.71, "ProSoundEffects", "Tonal Impact 2 (SFX)" },
	{
		"hitStopTick.Normal",
		"9119717529",
		0,
		0.08,
		0.02,
		0.2,
		1,
		1,
		false,
		0.23,
		"ProSoundEffects",
		"Switch Click On Or Off Toggle Button 1 (SFX)",
	},
	{
		"hitStopTick.Final",
		"9120490110",
		0.05,
		0.22,
		0.05,
		0.74,
		1,
		1,
		false,
		0.43,
		"ProSoundEffects",
		"Wall Switch Turning On Off Clicking Thunks 4 (SFX)",
	},
	{
		"hitStopTick.Kill",
		"9116896380",
		0,
		0.12,
		0.02,
		1,
		1,
		1,
		false,
		0.83,
		"ProSoundEffects",
		"Metal Thunk 14 (SFX)",
	},
	{
		"guard.Parry",
		"9116690113",
		0.39,
		0.82,
		0.12,
		1,
		0.98,
		1.02,
		false,
		3.39,
		"ProSoundEffects",
		"Metal Impacts 3 (SFX)",
	},
	{
		"guard.ParryRing",
		"9119747479",
		0.3,
		2.8,
		1.5,
		0.45,
		0.98,
		1.02,
		false,
		18.21,
		"ProSoundEffects",
		"Sword Long Metallic Ring Decay 2 (SFX)",
	},
	{
		"guard.Block",
		"9116673678",
		0.02,
		0.5,
		0.15,
		0.2,
		0.95,
		1.05,
		false,
		1.46,
		"ProSoundEffects",
		"Metal Impact Heavy Clunking Hits Scraping 1 (SFX)",
	},
	{
		"guard.GuardBreak",
		"9120801590",
		0.45,
		0.8,
		0.12,
		0.5,
		0.95,
		1,
		false,
		1.48,
		"ProSoundEffects",
		"Wood Break 1 (SFX)",
	},
	{
		"guard.GuardRaise",
		"9119075376",
		0.27,
		0.58,
		0.12,
		0.14,
		0.95,
		1.05,
		false,
		2.34,
		"ProSoundEffects",
		"Shield Impacts 13 (SFX)",
	},
	{
		"shatter.Crack",
		"9114615010",
		0.3,
		0.64,
		0.1,
		1,
		0.97,
		1.03,
		false,
		2.06,
		"ProSoundEffects",
		"Glass Smashes 7 (SFX)",
	},
	{
		"shatter.Chime",
		"9125644310",
		0.18,
		1.25,
		0.3,
		0.7,
		1,
		1,
		false,
		1.9,
		"ProSoundEffects",
		"Magic Twirling Small High Pitch Spinning Chi (SFX)",
	},
	{
		"shatter.Slam",
		"9125484367",
		0.07,
		1.2,
		0.7,
		0.9,
		0.97,
		1,
		false,
		4.44,
		"ProSoundEffects",
		"Deep Hits Big Reverberant Booms Rumbling Tai (SFX)",
	},
	{
		"shatter.BossCrack",
		"9114590265",
		0.57,
		2.8,
		1,
		1,
		0.7,
		0.75,
		false,
		5.02,
		"ProSoundEffects",
		"Glass Break 2 (SFX)",
	},
	{
		"shatter.BossBoom",
		"9120769456",
		0.985,
		2,
		0.4,
		0.5,
		1,
		1,
		false,
		8.96,
		"ProSoundEffects",
		"Wind Whoosh Sonic Boom Low End Impact 2 (SFX)",
	},
	{
		"telegraph.Tick",
		"9113399659",
		0.085,
		0.32,
		0.1,
		0.55,
		0.98,
		1.02,
		false,
		1.4,
		"ProSoundEffects",
		"Beeps Short And Long Bursts 10 (SFX)",
	},
	{
		"telegraph.Unblockable",
		"9113086354",
		0.36,
		0.95,
		0.15,
		0.75,
		0.98,
		1.02,
		false,
		2.23,
		"ProSoundEffects",
		"Alarm Buzzer 2 (SFX)",
	},
	{
		"telegraph.GuardBreak",
		"9125673878",
		0,
		0.45,
		0.08,
		0.6,
		0.98,
		1.02,
		false,
		1.09,
		"ProSoundEffects",
		"Metallic Beeps Quick Tones Some Dual Bursts (SFX)",
	},
	{
		"ui.SystemLine",
		"9126072698",
		0.29,
		1.25,
		0.3,
		0.65,
		1,
		1,
		false,
		2.34,
		"ProSoundEffects",
		"Synth Sparkle Tone High Pitch Bell Tone Ding (SFX)",
	},
	{ "ui.SwitchPrompt", "15675037413", 0.05, 0.34, 0.06, 0.5, 1, 1, false, 0.62, "Roblox", "Roblox_UI_Paper_Swipe" },
	{
		"ui.SwitchLand",
		"9116730789",
		0.12,
		0.45,
		0.1,
		0.3,
		1,
		1,
		false,
		1.09,
		"ProSoundEffects",
		"Metallic Beeps Quick Tones 5 (SFX)",
	},
	{ "ui.LowHpHeartbeat", "1841124374", 0.18, 1.12, 0, 0.7, 1, 1, true, 29.21, "APMOfficial", "Heartbeat Pulse" },
	{
		"artChime.TrailCyanWhite",
		"9119833793",
		0.035,
		0.35,
		0.06,
		0.6,
		0.95,
		1.05,
		false,
		1.23,
		"ProSoundEffects",
		"Synth Sparkle Tone High Pitch Tone Burst 4 (SFX)",
	},
	{
		"footsteps.GrassLight",
		"9120062559",
		0,
		0.3,
		0.1,
		1,
		0.92,
		1.08,
		false,
		0.8,
		"ProSoundEffects",
		"Tip Toe Of Object Onto Grass 1 (SFX)",
	},
	{
		"footsteps.StoneLight",
		"9118250959",
		0,
		0.18,
		0.05,
		0.14,
		0.92,
		1.08,
		false,
		0.84,
		"ProSoundEffects",
		"Robot Footsteps On Concrete 27 (SFX)",
	},
	{
		"footsteps.LandSoft",
		"9120879856",
		0,
		0.15,
		0.06,
		1,
		0.95,
		1.05,
		false,
		2.31,
		"ProSoundEffects",
		"Wood Grab Muted Thuds 10 (SFX)",
	},
	{
		"footsteps.LandHard",
		"9113480915",
		0.07,
		0.24,
		0.06,
		0.45,
		0.9,
		1,
		false,
		1.08,
		"ProSoundEffects",
		"Body Fall Thud 2 (SFX)",
	},
	{
		"enemy.ChargerSnort",
		"9113634896",
		0.04,
		0.36,
		0.04,
		1,
		0.9,
		1.1,
		false,
		0.39,
		"ProSoundEffects",
		"Bull Goblin Snorts 6 (SFX)",
	},
	{
		"enemy.ChargerWindUp",
		"9117369876",
		0.2,
		0.85,
		0.2,
		0.75,
		0.9,
		1.1,
		false,
		2.54,
		"ProSoundEffects",
		"Pig Squeals 1 (SFX)",
	},
	{
		"enemy.ChargerDeath",
		"9118314102",
		0.58,
		1.05,
		0.12,
		0.65,
		0.95,
		1.05,
		false,
		1.99,
		"ProSoundEffects",
		"Robot Screams Pig Squeals 52 (SFX)",
	},
	{
		"enemy.BruteRoar",
		"9114624343",
		0.2,
		1.8,
		0.45,
		0.7,
		0.85,
		1,
		false,
		3,
		"ProSoundEffects",
		"Goblin Growl 2 (SFX)",
	},
	{
		"enemy.BruteWindUp",
		"9114624510",
		0.25,
		1.55,
		0.1,
		0.55,
		0.95,
		1.05,
		false,
		1.75,
		"ProSoundEffects",
		"Goblin Growl 4 (SFX)",
	},
	{
		"enemy.BruteDeath",
		"9113988191",
		0.04,
		0.76,
		0.1,
		1,
		0.85,
		0.92,
		false,
		0.84,
		"ProSoundEffects",
		"Creature Vocal Pterodactyl Death Shriek 2 (SFX)",
	},
	{
		"ambience.RimWind",
		"9113286782",
		0.3,
		11.5,
		0,
		1,
		1,
		1,
		true,
		11.95,
		"ProSoundEffects",
		"Barstow Wind Light Blustery Low Howl 1 (SFX)",
	},
	{
		"ambience.Plains",
		"9119383684",
		2,
		125,
		0,
		0.36,
		1,
		1,
		true,
		127.61,
		"ProSoundEffects",
		"Sonoma Morning Birds California Chirping 2 (SFX)",
	},
}

-- The Phase 0 slots with no pick of their own: the pick each one borrows, and the level and pitch
-- range it plays that asset at.
type Reuse = { source: string, volume: number, pitch: { number } }
local REUSES: { [string]: Reuse } = {
	["enemy.ChargerStrike"] = { source = "enemy.ChargerSnort", volume = 1, pitch = { 0.74, 0.84 } },
	["enemy.ChargerStagger"] = { source = "enemy.ChargerDeath", volume = 0.45, pitch = { 1.12, 1.22 } },
	["enemy.BruteStrike"] = { source = "enemy.BruteDeath", volume = 0.75, pitch = { 0.98, 1.04 } },
	["enemy.BruteStagger"] = { source = "enemy.BruteDeath", volume = 0.6, pitch = { 1.11, 1.19 } },
}

-- How far apart two pitch ranges sit: the ratio between their nearest ends (under 1 when they meet).
local function pitchGap(a: { number }, b: { number }): number
	return math.max(a[1] / b[2], b[1] / a[2])
end

describe("sfx picks", function()
	it("applies every pick exactly: id, trim, fade, volume, pitch range, loop and the library listing", function()
		expect(#PICKS).toBe(50)
		for _, pick in PICKS do
			local slot = pick[1]
			local entry = entryOf(slot)
			local function same(field: string, actual: any, expected: any)
				if actual ~= expected then
					error(
						("%s.%s is %s, the pick says %s"):format(slot, field, tostring(actual), tostring(expected)),
						0
					)
				end
			end
			same("id", entry.id, "rbxassetid://" .. pick[2])
			same("placeholder", entry.placeholder, false)
			same("startAt", entry.startAt, pick[3])
			same("stopAt", entry.stopAt, pick[4])
			same("fadeOut", entry.fadeOut, pick[5])
			same("volume", entry.volume, pick[6])
			same("pitchRange[1]", entry.pitchRange[1], pick[7])
			same("pitchRange[2]", entry.pitchRange[2], pick[8])
			same("loop", entry.loop, pick[9])
			same("length", entry.length, pick[10])
			same("creator", entry.creator, pick[11])
			same("title", entry.title, pick[12])
		end
	end)

	it("makes real exactly the picks and the Phase 0 reuses; every other slot stays a placeholder", function()
		local expected: { [string]: boolean } = {}
		for _, pick in PICKS do
			expected[pick[1]] = true
		end
		for slot in REUSES do
			expected[slot] = true
		end
		for _, row in Sfx.all() do
			local name = row.family .. "." .. row.name
			if Sfx.isReal(row.entry) ~= (expected[name] == true) then
				error(("%s is %s"):format(name, if Sfx.isReal(row.entry) then "real" else "a placeholder"), 0)
			end
		end
	end)

	it("reuses the closest pick's asset, trim and title, at its own level and a pitch a semitone away", function()
		-- One semitone is a pitch ratio of 2^(1/12), about 1.06.
		expect(Sfx.limits.sharedAssetSemitones).toBeGreaterThanOrEqual(1)
		local apart = 2 ^ (Sfx.limits.sharedAssetSemitones / 12)
		for slot, reuse in REUSES do
			local entry, from = entryOf(slot), entryOf(reuse.source)
			for _, field in { "id", "startAt", "stopAt", "fadeOut", "loop", "length", "title", "creator", "spatial" } do
				expect(entry[field]).toBe(from[field])
			end
			expect(entry.note).toBe(("reuses %s until its own sound is picked"):format(reuse.source))
			expect(entry.volume).toBe(reuse.volume)
			expect(entry.pitchRange[1]).toBe(reuse.pitch[1])
			expect(entry.pitchRange[2]).toBe(reuse.pitch[2])
			-- Never heard as its source: the nearest ends at least a semitone apart.
			expect(pitchGap(entry.pitchRange, from.pitchRange)).toBeGreaterThanOrEqual(apart)
		end
		-- The kobold's strike and stagger share the shriek with its death and with each other, apart.
		local strike, stagger = entryOf("enemy.BruteStrike").pitchRange, entryOf("enemy.BruteStagger").pitchRange
		expect(pitchGap(strike, stagger)).toBeGreaterThanOrEqual(apart)
		-- The strike is the attack, never quieter than the idle snort it borrows; a stagger's yelp
		-- sits well under the death scream it borrows.
		expect(entryOf("enemy.ChargerStrike").volume).toBeGreaterThanOrEqual(entryOf("enemy.ChargerSnort").volume)
		expect(entryOf("enemy.ChargerStagger").volume).toBeLessThan(entryOf("enemy.ChargerDeath").volume)
		expect(entryOf("enemy.BruteStagger").volume).toBeLessThan(entryOf("enemy.BruteDeath").volume)
	end)

	it("keeps the riser's end on its plateau at full level, and the loops seamless", function()
		local riser = Sfx.get("whoosh", "Riser")
		expect(riser.fadeOut).toBe(0)
		expect(riser.stopAt - riser.startAt).toBeCloseTo(0.31, 1e-9)
		for _, name in { "ui.LowHpHeartbeat", "ambience.RimWind", "ambience.Plains" } do
			local entry = entryOf(name)
			expect(entry.loop).toBe(true)
			expect(entry.fadeOut).toBe(0)
			expect(entry.stopAt - entry.startAt).toBeGreaterThan(Sfx.limits.loopMinSeconds)
		end
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The cue gains from the recipe notes (picks.cues): a layer's gainDb is the "cue" number, 0 when
-- the recipe gives none; the hit-stop tick is Replication's, never a cue layer
-- ------------------------------------------------------------------------------------------

local RECIPES: { [string]: { [string]: number } } = {
	HitNormal = { ["impact.Crack"] = 0, ["impact.Flesh"] = 0, ["impact.Body"] = 0, ["impact.Ring"] = 0 },
	HitBasic = { ["impact.Crack"] = -3, ["impact.Flesh"] = 0, ["impact.Body"] = -3, ["impact.Ring"] = 0 },
	HitCrit = { ["impact.Crack"] = 2, ["impact.Flesh"] = 0, ["impact.Body"] = 0, ["impact.Ring"] = 3.5 },
	HitFinal = {
		["impact.Crack"] = 0,
		["impact.FinalHit"] = 0,
		["impact.Flesh"] = 0,
		["impact.Sub"] = 0,
		["impact.RingTail"] = 0,
	},
	HitKill = {
		["impact.Crack"] = 2,
		["impact.Kill"] = 0,
		["impact.Flesh"] = -3,
		["impact.Ring"] = 3,
		["impact.RingTail"] = 0,
	},
	Parry = { ["guard.Parry"] = 0, ["guard.ParryRing"] = 0 },
	Block = { ["guard.Block"] = 0 },
	GuardBreak = { ["guard.GuardBreak"] = 0, ["impact.Sub"] = -6 },
	Shatter = { ["shatter.Crack"] = 0, ["shatter.Slam"] = 0, ["shatter.Chime"] = 0, ["impact.SubDrop"] = -3 },
	ShatterHeavy = { ["shatter.Crack"] = 0, ["shatter.Slam"] = 0, ["shatter.Chime"] = 0, ["impact.SubDrop"] = 0 },
	BossShatter = {
		["shatter.BossCrack"] = 0,
		["shatter.BossBoom"] = 0,
		["shatter.Chime"] = 0,
		["impact.SubDrop"] = 0,
	},
	Dodge = { ["whoosh.Dodge"] = 0, ["footsteps.LandSoft"] = 0 },
	-- A rush's slam on a wall (D-217): the stone hit, the body's weight 3 dB down and the sub 6 dB
	-- down under them, all on the contact frame (impact entries already picked: no new sounds).
	WallSlam = { ["impact.Construct"] = 0, ["impact.Body"] = -3, ["impact.Sub"] = -6 },
}

local function layerOf(cueName: string, name: string): any
	for _, layer in Sfx.cue(cueName) do
		if layer.name == name then
			return layer
		end
	end
	return nil
end

local function stepOf(contourName: string, group: string, key: string, predicate: (number) -> boolean): any
	for _, step in Sfx.contour(contourName) do
		if step.group == group and step[key] ~= nil and predicate(step[key]) then
			return step
		end
	end
	return nil
end

describe("sfx cue gains", function()
	it("has exactly the recipes' cues, each with the recipe's layers and gains", function()
		local names = {}
		for name in RECIPES do
			table.insert(names, name)
		end
		table.sort(names)
		expect(Sfx.cueNames()).toEqual(names)
		for cueName, recipe in RECIPES do
			local seen: { [string]: number } = {}
			for _, layer in Sfx.cue(cueName) do
				if seen[layer.name] ~= nil then
					error(("%s plays %s twice"):format(cueName, layer.name), 0)
				end
				seen[layer.name] = layer.gainDb
			end
			expect(seen).toEqual(recipe)
		end
	end)

	it("never takes a layer above volume 1 (entry volume x 10^(gainDb / 20))", function()
		for _, cueName in Sfx.cueNames() do
			for _, layer in Sfx.cue(cueName) do
				local volume = entryOf(layer.name).volume * Sfx.gainOf(layer.gainDb)
				expect(volume).toBeLessThanOrEqual(Sfx.limits.maxPlayVolume)
			end
		end
		-- The loudest layer of the set: the crit's ring, 3.5 dB over its 0.65.
		expect(entryOf("impact.Ring").volume * Sfx.gainOf(3.5)).toBeCloseTo(0.9725, 1e-3)
	end)

	it("brightens the crit at the top of the crack's and the ring's pitch ranges", function()
		expect(layerOf("HitCrit", "impact.Crack").pitch).toBe(Sfx.get("impact", "Crack").pitchRange[2])
		expect(layerOf("HitCrit", "impact.Ring").pitch).toBe(Sfx.get("impact", "Ring").pitchRange[2])
		-- Every other layer plays at a random pitch in its entry's range.
		for _, cueName in Sfx.cueNames() do
			for _, layer in Sfx.cue(cueName) do
				local pitched = (cueName == "HitCrit" and (layer.name == "impact.Crack" or layer.name == "impact.Ring"))
					or (cueName == "BossShatter" and layer.name == "shatter.Chime")
				expect(layer.pitch ~= nil).toBe(pitched)
			end
		end
	end)

	it("plays the boss crack in its own slow range and the chime at the slow 0.75", function()
		expect(Sfx.get("shatter", "BossCrack").pitchRange).toEqual({ 0.7, 0.75 })
		expect(layerOf("BossShatter", "shatter.BossCrack").pitch).toBeNil()
		expect(layerOf("BossShatter", "shatter.Chime").pitch).toBe(0.75)
		-- No slam: the boom replaces it.
		expect(layerOf("BossShatter", "shatter.Slam")).toBeNil()
	end)

	it("starts every contact layer with the crack on the contact frame; only the final hold's sub waits", function()
		local finalHold = Combat.hitStopFrames.Final * Combat.hitStopFrameSeconds
		for _, name in { "HitNormal", "HitBasic", "HitCrit", "HitFinal", "HitKill" } do
			expect(Sfx.cue(name)[1].name).toBe("impact.Crack")
			for _, layer in Sfx.cue(name) do
				-- Five layers at contact (the recipe): each pick's startAt sits about 30 ms before its
				-- attack, so the stack fuses into one hit.
				local expected = if name == "HitFinal" and layer.name == "impact.Sub" then finalHold else 0
				expect(layer.delay).toBe(expected)
			end
		end
		expect(layerOf("HitFinal", "impact.Body")).toBeNil()
		expect(layerOf("HitFinal", "impact.Ring")).toBeNil()
		expect(layerOf("GuardBreak", "impact.Sub").delay).toBe(0)
		-- The moments spec and validator read HitFinal's sub as its fifth layer.
		expect(Sfx.cue("HitFinal")[5].name).toBe("impact.Sub")
	end)

	it("waits no cue layer under a frame: a delay is 0 or at least playback.sameFrameSeconds", function()
		-- A scheduled thread resumes once per frame, so a few-ms wait would land a whole frame late.
		expect(Sfx.playback.sameFrameSeconds).toBe(Combat.hitStopFrameSeconds)
		for _, cueName in Sfx.cueNames() do
			for _, layer in Sfx.cue(cueName) do
				if layer.delay ~= 0 and layer.delay < Sfx.playback.sameFrameSeconds then
					error(("%s's %s waits %s s, under a frame"):format(cueName, layer.name, tostring(layer.delay)), 0)
				end
			end
		end
	end)

	it("keeps the body and the bass out of the kill", function()
		for _, name in { "impact.Body", "impact.Sub", "impact.SubDrop", "shatter.BossBoom" } do
			expect(layerOf("HitKill", name)).toBeNil()
		end
	end)

	it("starts everything on the shatter's white-flash frame, and the parry's ring with its clash", function()
		for _, cueName in { "Shatter", "ShatterHeavy", "BossShatter", "Parry" } do
			for _, layer in Sfx.cue(cueName) do
				expect(layer.delay).toBe(0)
			end
		end
		expect(layerOf("Parry", "impact.Crack")).toBeNil()
	end)

	it("shatters a player or an Elite heavier: the Shatter stack with the bass dive at full level", function()
		local normal, heavy = Sfx.cue(Sfx.shatterCues.normal), Sfx.cue(Sfx.shatterCues.heavy)
		expect(#heavy).toBe(#normal)
		for index, layer in normal do
			local other = heavy[index]
			expect(other.name).toBe(layer.name)
			expect(other.delay).toBe(layer.delay)
			expect(other.pitch).toBe(layer.pitch)
			if layer.name == "impact.SubDrop" then
				expect(other.gainDb).toBe(0)
				expect(other.gainDb).toBeGreaterThan(layer.gainDb)
			else
				expect(other.gainDb).toBe(layer.gainDb)
			end
		end
	end)

	it("lands the dodge's soft step as the 0.25 s step ends", function()
		expect(layerOf("Dodge", "whoosh.Dodge").delay).toBe(0)
		expect(layerOf("Dodge", "footsteps.LandSoft").delay).toBe(Combat.dodgeDuration)
		expect(Combat.dodgeDuration).toBe(0.25)
	end)

	it("plays no hit-stop tick from a cue (Replication plays it in 2D for the fighters in the hit)", function()
		for _, cueName in Sfx.cueNames() do
			for _, layer in Sfx.cue(cueName) do
				expect(layer.name:sub(1, 12)).never.toBe("hitStopTick.")
			end
		end
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Phase 0 coverage: every sound the slice can play is a real sound
-- ------------------------------------------------------------------------------------------

local serde = require("@lune/serde")

local Scope = Harness.load("src/shared/data/scope")
local Enemies = Harness.load("src/shared/data/enemies")
local Weapons = Harness.load("src/shared/data/weapons")
local Arts = Harness.load("src/shared/data/arts")
local Playground = Harness.load("src/shared/data/playground")
local World = Harness.load("src/shared/data/world")
local Moments = Harness.load("src/shared/data/moments")

-- Names a source file mentions that no Phase 0 flow reaches, and why.
local OUT_OF_SCOPE: { [string]: string } = {
	["ui.SystemLineWarded"] = "Warded popups come with Warded zones and objects, after Phase 0",
}

-- Real sounds nothing in the slice plays yet, and why (docs/PLACEHOLDERS.md lists them too).
local UNPLAYED: { [string]: string } = {
	["impact.Armor"] = "no in-scope enemy has an armored surface",
	["impact.Construct"] = "no in-scope enemy is a construct",
	["shatter.BossCrack"] = "Phase 0 has no boss to play BossShatter",
	["shatter.BossBoom"] = "Phase 0 has no boss to play BossShatter",
	["telegraph.Tick"] = "every in-scope attack telegraphs Unblockable or GuardBreak",
}

-- Files whose sound names are not plays: sfx.luau itself, SfxPool's own helpers (hit, parry and
-- hitStopTick have no caller) and Main.client's module paths ("ui.SystemLine" is a module there).
local NOT_CALLERS: { [string]: boolean } = {
	["src/shared/data/sfx.luau"] = true,
	["src/client/audio/SfxPool.luau"] = true,
	["src/client/Main.client.luau"] = true,
}

-- Every "family.Name" string in a file that names an sfx.luau entry.
local function mentionedIn(path: string, into: { [string]: string })
	local source = Harness.readFile(path)
	for family, name in source:gmatch('"(%a%w*)%.(%a%w*)"') do
		local group = Sfx.families[family]
		if group ~= nil and group.entries[name] ~= nil then
			into[family .. "." .. name] = into[family .. "." .. name] or path
		end
	end
end

-- Every Material a place file's parts use.
local function placeMaterials(path: string, into: { [string]: boolean })
	local function walk(node: any)
		if typeof(node) ~= "table" then
			return
		end
		for key, value in node do
			if key == "Material" and typeof(value) == "string" then
				into[value] = true
			else
				walk(value)
			end
		end
	end
	walk(serde.decode("json", Harness.readFile(path)))
end

-- The sounds Phase 0 can play, each with where it comes from.
local function phase0Sounds(): { [string]: string }
	local sounds: { [string]: string } = {}
	-- What the client plays by name: Replication's reactions, the clips' Sfx and Voice events,
	-- the telegraphs, the heartbeat, the ambience beds, the system line's chime, the moments'
	-- riser and sound. fx.luau's telegraph sounds play by attack kind (added below for the
	-- in-scope attacks).
	local byKindOrUnread: { [string]: boolean } = {}
	for _, name in Fx.telegraph.sounds do
		byKindOrUnread[name] = true
	end
	-- A client file that plays an archetype's death vocal by name (Sfx.vocalName(archetype,
	-- "Death"), called directly or through pcall) plays every in-scope enemy's (added below).
	local deathVocalCaller: string? = nil
	for _, directory in { "src/client", "src/shared/clips", "src/shared/data" } do
		for _, path in Harness.listFiles(directory, "%.luau$") do
			if NOT_CALLERS[path] then
				continue
			end
			local found: { [string]: string } = {}
			mentionedIn(path, found)
			if path:sub(1, #"src/client/") == "src/client/" and deathVocalCaller == nil then
				if Harness.readFile(path):find('vocalName[%(,][^)]*"Death"') ~= nil then
					deathVocalCaller = path
				end
			end
			for name, from in found do
				if path == "src/shared/data/fx.luau" and byKindOrUnread[name] then
					continue
				end
				sounds[name] = sounds[name] or from
			end
		end
	end
	sounds[Fx.audio.heartbeatLoop] = "the low-HP heartbeat"
	for name in OUT_OF_SCOPE do
		sounds[name] = nil
	end
	-- The cues the moments play; the boss shatter only once a phase has bosses.
	for _, momentName in Moments.list() do
		local row = Moments.byId(momentName)
		local cues = { row.cue }
		if row.shatterCue ~= nil and (row.shatterCue ~= Sfx.shatterCues.boss or #Scope.bosses > 0) then
			table.insert(cues, row.shatterCue)
		end
		for _, cueName in cues do
			for _, layer in Sfx.cue(cueName) do
				sounds[layer.name] = sounds[layer.name] or ("cue " .. cueName)
			end
		end
	end
	-- The activation chime of every in-scope Art's trail color and of the loadout weapon.
	for _, artId in Scope.arts do
		local token = Weapons.trailColor[Arts.byId(artId).weapon]
		sounds["artChime." .. token] = "Art " .. artId
	end
	sounds["artChime." .. Weapons.byId(Playground.loadout.weapon).trailColor] = "the loadout weapon"
	-- Footsteps on every surface the Phase 0 places can put under a foot, at the Light weight
	-- (nothing on the server writes the Armored attribute yet; see the check below).
	local materials: { [string]: boolean } = {
		[World.railing.material] = true,
		[World.pillars.material] = true,
	}
	for _, path in { "places/Playground.project.json", "places/ClipLab.project.json" } do
		placeMaterials(path, materials)
	end
	for material in materials do
		local surface = Fx.audio.materialSurface[material] or Fx.audio.defaultSurface
		sounds["footsteps." .. surface .. "Light"] = "material " .. material
	end
	-- The telegraph of every in-scope enemy attack (Telegraphs.show plays it by kind). The
	-- vocals come from the enemies' clip events above, the death vocal from its caller.
	for _, enemyId in Scope.enemies do
		local def = Enemies.byId(enemyId)
		for _, attack in def.attacks do
			local sound = Fx.telegraph.sounds[attack.telegraph] or Fx.telegraph.sounds.Normal
			sounds[sound] = "a " .. tostring(attack.telegraph) .. " telegraph of " .. enemyId
		end
		if deathVocalCaller ~= nil then
			local vocal = Sfx.vocalName(def.archetype, "Death")
			sounds[vocal] = sounds[vocal] or (deathVocalCaller :: string)
		end
	end
	return sounds
end

describe("sfx Phase 0 coverage", function()
	it("gives every sound the slice can play a real asset", function()
		local sounds = phase0Sounds()
		local count = 0
		for name, source in sounds do
			count += 1
			if not Sfx.isReal(entryOf(name)) then
				error(("%s (from %s) is still a placeholder"):format(name, source), 0)
			end
		end
		-- 43 names today; the floor only guards a scan that reads nothing.
		expect(count).toBeGreaterThanOrEqual(40)
		-- Spot checks of each source the scan reads.
		for _, name in
			{
				"impact.Flesh", -- the HitNormal and HitBasic cues' flesh layer
				"enemy.ChargerStrike", -- a clip event
				"telegraph.Unblockable", -- the boar's charge telegraph
				"telegraph.GuardBreak", -- the kobold's overhead telegraph
				"ui.LowHpHeartbeat", -- fx.luau's heartbeat
				"whoosh.Riser", -- moments.luau's riser
				"impact.Body", -- a moment's cue
				"artChime.TrailCyanWhite", -- the Art chime
				"footsteps.GrassLight", -- the Playground field
				"footsteps.StoneLight", -- slate, smooth plastic and every unmapped material
				"enemy.BruteStagger", -- the kobold's stagger clip
				"ui.SystemLine", -- Replication's system line chime
			}
		do
			expect(sounds[name]).never.toBeNil()
		end
		-- The Armored weight is never chosen in Phase 0.
		expect(sounds["footsteps.GrassArmored"]).toBeNil()
	end)

	it("plays every real sound but the unplayed ones, and says why each of those is unplayed", function()
		local sounds = phase0Sounds()
		for _, row in Sfx.all() do
			local name = row.family .. "." .. row.name
			if not Sfx.isReal(row.entry) then
				expect(UNPLAYED[name]).toBeNil()
				continue
			end
			if sounds[name] == nil and UNPLAYED[name] == nil then
				error(("%s is real but nothing in the slice plays it: list it in UNPLAYED with why"):format(name), 0)
			elseif sounds[name] ~= nil and UNPLAYED[name] ~= nil then
				error(("%s is listed unplayed, but %s plays it"):format(name, sounds[name]), 0)
			end
		end
		-- Names that only sit in a table nothing reads, or in the pool's own helpers, are no caller.
		expect(sounds["shatter.BossCrack"]).toBeNil()
		expect(sounds["telegraph.Tick"]).toBeNil()
	end)

	it("keeps the out-of-scope names silent and every reuse played or listed unplayed", function()
		for name in OUT_OF_SCOPE do
			expect(Sfx.isReal(entryOf(name))).toBe(false)
		end
		local sounds = phase0Sounds()
		for slot in REUSES do
			expect(sounds[slot] ~= nil or UNPLAYED[slot] ~= nil).toBe(true)
		end
	end)

	it("preloads every one-shot the slice plays, so no first play of a session starts late", function()
		local SfxPool = Harness.load("src/client/audio/SfxPool")
		local preloaded: { [string]: boolean } = {}
		for _, name in SfxPool.preloadNames() do
			preloaded[name] = true
		end
		for name, source in phase0Sounds() do
			if entryOf(name).loop ~= true and not preloaded[name] then
				error(("%s (from %s) is not preloaded: add it to sfx.preload"):format(name, source), 0)
			end
		end
		-- The death vocals load ahead of the caller the kill is about to get.
		expect(preloaded["enemy.ChargerDeath"]).toBe(true)
		expect(preloaded["enemy.BruteDeath"]).toBe(true)
	end)

	it("routes the ambience beds through SFX: the death silence ducks them, the hit's bass cut drops them", function()
		expect(Sfx.groupOf("ambience")).toBe("SFX")
		expect(table.find(Sfx.effects.groups, "SFX")).never.toBeNil()
	end)

	it("plays no Armored footstep in Phase 0: nothing on the server writes the attribute", function()
		local attribute = Fx.audio.armoredAttribute
		for _, path in Harness.listFiles("src/server", "%.luau$") do
			local source = Harness.readFile(path)
			if source:find('"' .. attribute .. '"', 1, true) ~= nil then
				error(
					("%s writes '%s': give footsteps.*Armored real sounds and add them to the coverage"):format(
						path,
						attribute
					),
					0
				)
			end
		end
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The reel layer: contours, effects and how the cues sit on them
-- ------------------------------------------------------------------------------------------

describe("sfx reel layers", function()
	it("gives the layered-hit entries a note saying what each layer is", function()
		for _, pair in
			{
				{ "impact", "Crack" },
				{ "impact", "Body" },
				{ "impact", "Sub" },
				{ "impact", "RingTail" },
				{ "impact", "SubDrop" },
				{ "whoosh", "Riser" },
				{ "whoosh", "Dodge" },
				{ "guard", "ParryRing" },
				{ "shatter", "Slam" },
			}
		do
			local entry = Sfx.get(pair[1], pair[2])
			expect(typeof(entry.note)).toBe("string")
			expect(#(entry.note :: string)).toBeGreaterThan(10)
		end
	end)

	it("stacks the big hits 4 to 6 deep", function()
		for _, name in { "HitNormal", "HitCrit", "HitFinal", "HitKill", "Shatter", "ShatterHeavy", "BossShatter" } do
			expect(#Sfx.cue(name)).toBeGreaterThanOrEqual(4)
			expect(#Sfx.cue(name)).toBeLessThanOrEqual(6)
		end
	end)

	it("lands the final hit's sub with its bass all the way back, at the end of the 6-frame freeze", function()
		local hold = Combat.hitStopFrames.Final * Combat.hitStopFrameSeconds
		local back = stepOf("FinalHit", "SFX", "low", function(value)
			return value == 0
		end)
		local cut = stepOf("FinalHit", "SFX", "low", function(value)
			return value < 0
		end)
		expect(cut.at).toBe(0)
		expect(cut.low).toBeLessThanOrEqual(-24)
		-- The bass finishes coming back on the freeze's last frame, the moment the sub thumps: it
		-- slams in, never swells in under the cut.
		expect(back.at + back.ramp).toBeCloseTo(hold, 1e-9)
		expect(back.at).toBeGreaterThan(cut.at + cut.ramp)
		expect(layerOf("HitFinal", "impact.Sub").delay).toBeCloseTo(hold, 1e-9)
		expect(layerOf("HitFinal", "impact.Sub").delay).toBeGreaterThanOrEqual(back.at + back.ramp - 1e-9)
		-- The kill's bass comes back as its 10-frame freeze ends, under the death freeze's duck.
		local killBack = stepOf("KillCut", "SFX", "low", function(value)
			return value == 0
		end)
		expect(killBack.at).toBeCloseTo(Combat.hitStopFrames.Kill * Combat.hitStopFrameSeconds, 1e-9)
		-- The kill's cut goes deeper than the recipe's -30 dB: the reel drops the bass completely.
		local killCut = stepOf("KillCut", "SFX", "low", function(value)
			return value < 0
		end)
		expect(killCut.low).toBeLessThanOrEqual(-30)
		expect(stepOf("KillCut", "Music", "low", function(value)
			return value < 0
		end)).never.toBeNil()
	end)

	it("names the shatter cues SfxPool.shatter plays", function()
		expect(Sfx.shatterCues.normal).toBe("Shatter")
		expect(Sfx.shatterCues.heavy).toBe("ShatterHeavy")
		expect(Sfx.shatterCues.boss).toBe("BossShatter")
	end)

	it("blooms the reverb on the shatter and the parry and dries it inside about half a second", function()
		for _, name in { "ShatterBloom", "ParryRing" } do
			local steps = Sfx.contour(name)
			expect(steps[1].at).toBe(0)
			expect(steps[1].wet).toBeGreaterThan(Sfx.effects.reverb.wet + 40)
			local last = steps[#steps]
			expect(last.wet).toBe(Sfx.effects.reverb.wet)
			expect(last.at + last.ramp).toBeGreaterThanOrEqual(0.4)
			expect(last.at + last.ramp).toBeLessThanOrEqual(0.8)
		end
	end)

	it("idles flat and dry on the Master, Music and SFX groups", function()
		expect(Sfx.effects.groups).toEqual({ "Master", "Music", "SFX" })
		expect(Sfx.effects.equalizer.low).toBe(0)
		expect(Sfx.effects.equalizer.mid).toBe(0)
		expect(Sfx.effects.equalizer.high).toBe(0)
		expect(Sfx.effects.reverb.wet).toBe(Sfx.engine.reverbLevelDb.min)
		expect(Sfx.effects.reverb.dry).toBe(0)
		expect(Sfx.effects.easing).never.toBe("Linear")
	end)

	it("names cues and contours, sorted, and errors on unknown ones", function()
		local cues = Sfx.cueNames()
		expect(#cues).toBe(13)
		for index = 2, #cues do
			expect(cues[index - 1] < cues[index]).toBe(true)
		end
		local contours = Sfx.contourNames()
		expect(table.find(contours, "FinalHit")).never.toBeNil()
		expect(table.find(contours, "KillCut")).never.toBeNil()
		expect(function()
			Sfx.cue("HitEnormous")
		end).toThrow("unknown cue")
		expect(function()
			Sfx.contour("Wobble")
		end).toThrow("unknown contour")
	end)

	it("turns dB into an amplitude", function()
		expect(Sfx.gainOf(0)).toBe(1)
		expect(Sfx.gainOf(20)).toBeCloseTo(10, 1e-9)
		expect(Sfx.gainOf(-6)).toBeCloseTo(0.501187, 1e-6)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Clip sound events: the whooshes peak on the snap, the dodge lands once, the strikes are voiced
-- ------------------------------------------------------------------------------------------

-- Every clip module under src/shared/clips, by its repo path without the extension.
local function clipModules(): { { path: string, clip: any } }
	local list = {}
	for _, file in Harness.listFiles("src/shared/clips", "%.luau$") do
		local path = (file:gsub("%.luau$", ""))
		table.insert(list, { path = path, clip = Harness.load(path) })
	end
	return list
end

-- A clip event's sound name, or nil for an event that plays none.
local function soundOf(event: any): string?
	if (event.kind == "Sfx" or event.kind == "Voice") and typeof(event.data) == "table" then
		return event.data.name
	end
	return nil
end

-- The clip events fire on the frame that crosses them, so half a frame either way is on time.
local ON_TIME = Combat.hitStopFrameSeconds / 2

describe("sfx clip sound events", function()
	it("measures each clip whoosh's peak inside its audible part and leads it by the pitch's middle", function()
		for _, name in { "Small", "Medium", "Large", "Basic" } do
			local entry = Sfx.get("whoosh", name)
			expect(typeof(entry.peakAt)).toBe("number")
			expect(entry.peakAt).toBeGreaterThan(entry.startAt or 0)
			expect(entry.peakAt).toBeLessThan(entry.stopAt)
		end
		-- (peakAt - startAt) / the middle of the pitch range: the real seconds from Play to the peak.
		expect(Sfx.peakLead(Sfx.get("whoosh", "Medium"))).toBeCloseTo(0.061, 1e-9)
		expect(Sfx.peakLead(Sfx.get("whoosh", "Large"))).toBeCloseTo(0.144 / 0.925, 1e-9)
		expect(Sfx.peakLead(Sfx.get("whoosh", "Small"))).toBeCloseTo(0.066 / 1.025, 1e-9)
		expect(Sfx.peakLead(Sfx.get("impact", "Crack"))).toBeNil()
	end)

	it("starts every clip whoosh so its swell peaks as its strike's hit window opens", function()
		local checked = 0
		for _, module in clipModules() do
			local opens: { number } = {}
			for _, event in module.clip.events do
				if event.kind == "HitWindowOpen" then
					table.insert(opens, event.time)
				end
			end
			local nextOpen = 1
			for _, event in module.clip.events do
				local name = soundOf(event)
				if name == nil or name:sub(1, #"whoosh.") ~= "whoosh." then
					continue
				end
				-- The whoosh leads the strike after it: the next hit window at or after the event.
				while opens[nextOpen] ~= nil and opens[nextOpen] < event.time - 1e-9 do
					nextOpen += 1
				end
				local open = opens[nextOpen]
				if open == nil then
					error(("%s: %s at %s has no hit window after it"):format(module.path, name, event.time), 0)
				end
				local lead = Sfx.peakLead(entryOf(name))
				if lead == nil then
					error(("%s: %s has no measured peakAt to time it by"):format(module.path, name), 0)
				end
				-- A basic's anticipation is shorter than the swell: the whoosh starts with the clip.
				local expected = math.max(0, open - (lead :: number))
				if math.abs(event.time - expected) > ON_TIME then
					error(
						("%s: %s at %s peaks off its strike; start it at %.3f (window %s - lead %.3f)"):format(
							module.path,
							name,
							event.time,
							expected,
							open,
							lead :: number
						),
						0
					)
				end
				nextOpen += 1
				checked += 1
			end
		end
		-- Basic1-3, Horizontal, Vertical, Rising Arc's two, Sharp Nail's three, the kobold's Overhead.
		expect(checked).toBe(11)
	end)

	it("keeps an Art's strike sounds out of its hold's step down to 20 fps", function()
		-- The local clip freezes on the step that crosses its ActivationHold, and that step's other
		-- events still fire: a sound less than one 20 fps frame after the hold could sound as the
		-- stance starts glowing, a whole hold before its strike.
		local slowFrame = 1 / 20
		local holds = 0
		for _, module in clipModules() do
			local hold: number?, open: number? = nil, nil
			for _, event in module.clip.events do
				if event.kind == "ActivationHold" then
					hold = event.time
				elseif event.kind == "HitWindowOpen" and (open == nil or event.time < (open :: number)) then
					open = event.time
				end
			end
			if hold == nil then
				continue
			end
			holds += 1
			for _, event in module.clip.events do
				local name = soundOf(event)
				local after = event.time - (hold :: number)
				local beforeStrike = open == nil or event.time < (open :: number)
				if name ~= nil and beforeStrike and after > 0 and after < slowFrame - 1e-9 then
					error(
						("%s: %s at %s is %.3f s after the hold; keep it %.2f s clear"):format(
							module.path,
							name,
							event.time,
							after,
							slowFrame
						),
						0
					)
				end
			end
		end
		-- Horizontal, Vertical, Rising Arc, Sharp Nail.
		expect(holds).toBe(4)
	end)

	it("lands a dodge once: the Dodge cue plays the soft step, so no dodge clip names it", function()
		local landing = layerOf("Dodge", "footsteps.LandSoft")
		expect(landing).never.toBeNil()
		local dodges = 0
		for _, module in clipModules() do
			if not module.path:find("/Dodge", 1, true) then
				continue
			end
			dodges += 1
			for _, event in module.clip.events do
				if soundOf(event) == landing.name then
					error(("%s plays %s; the Dodge cue already lands the step"):format(module.path, landing.name), 0)
				end
			end
		end
		expect(dodges).toBe(4)
	end)

	it("voices every in-scope enemy strike on its strike frame, as a Voice event", function()
		local voiced = 0
		for _, enemyId in Scope.enemies do
			local def = Enemies.byId(enemyId)
			local strike = Sfx.vocalName(def.archetype, "Strike")
			if not Sfx.isReal(entryOf(strike)) then
				continue
			end
			for _, attack in def.attacks do
				local path = ("src/shared/clips/enemy/%s/%s"):format(def.skin, attack.clip)
				local clip = Harness.load(path)
				local open: number? = nil
				for _, event in clip.events do
					if event.kind == "HitWindowOpen" then
						open = event.time
						break
					end
				end
				expect(open).never.toBeNil()
				local found = 0
				for _, event in clip.events do
					if soundOf(event) == strike then
						found += 1
						expect(event.kind).toBe("Voice")
						expect(event.time).toBeCloseTo(open :: number, 1e-9)
					end
				end
				if found ~= 1 then
					error(("%s voices %s %d times; once on the strike"):format(path, strike, found), 0)
				end
				voiced += 1
			end
		end
		-- The boar's Charge and the kobold's Overhead.
		expect(voiced).toBe(2)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- tools/validators/sfx.luau on synthetic tables
-- ------------------------------------------------------------------------------------------

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local validatorSource = fs.readFile(Harness.repoRoot() .. "/tools/validators/sfx.luau")
local validate = luau.load(validatorSource, { debugName = "tools/validators/sfx", environment = {} :: any })()

local function deepClone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepClone(inner)
	end
	return copy
end

-- Runs the validator against a copy of the real sfx.luau that `mutate` edits.
local function problemsWith(mutate: ((any) -> ())?): { string }
	local data = deepClone(Sfx)
	if mutate ~= nil then
		mutate(data)
	end
	return validate({
		load = function(path: string): any
			if path == "src/shared/data/sfx" then
				return data
			end
			return Harness.load(path)
		end,
		listFiles = Harness.listFiles,
		readFile = Harness.readFile,
		repoRoot = Harness.repoRoot(),
	})
end

-- Exactly one problem, containing `needle`.
local function expectOnly(problems: { string }, needle: string)
	expect(#problems).toBe(1)
	expect(problems[1]).toContain(needle)
end

-- No problem at all.
local function expectClean(mutate: (any) -> ())
	expect(problemsWith(mutate)).toEqual({})
end

describe("sfx validator: real sounds and their trims", function()
	local CRACK = "sfx.families.impact.Crack"
	local HEARTBEAT = "sfx.families.ui.LowHpHeartbeat"

	it("passes the real table", function()
		expect(problemsWith(nil)).toEqual({})
	end)

	it("wants an rbxassetid:// id, and a 0 id marked as a placeholder", function()
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.id = "9120660382"
			end),
			CRACK .. ": id must be an rbxassetid:// string"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.id = "rbxassetid://0"
			end),
			CRACK .. ": a 0 asset id must be marked placeholder = true"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.id = "rbxassetid://000"
			end),
			CRACK .. ": a 0 asset id must be marked placeholder = true"
		)
		expectClean(function(data)
			data.families.impact.entries.Crack.id = "rbxassetid://0"
			data.families.impact.entries.Crack.placeholder = true
		end)
	end)

	it("keeps placeholder = false for a real id", function()
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.placeholder = true
			end),
			CRACK .. ": a real asset id must be marked placeholder = false"
		)
		expectClean(function(data)
			data.families.impact.entries.Crack.id = "rbxassetid://9113612888"
		end)
	end)

	it("wants a real sound's title, licensed creator and length", function()
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.title = nil
			end),
			CRACK .. ": a real sound needs its library title"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.creator = "SomeUploader"
			end),
			CRACK .. ": creator 'SomeUploader' must be ProSoundEffects, APMOfficial or Roblox"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.creator = nil
			end),
			CRACK .. ": creator 'nil' must be"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.length = nil
			end),
			CRACK .. ": a real sound needs the asset's length"
		)
		for _, creator in { "ProSoundEffects", "APMOfficial", "Roblox" } do
			expectClean(function(data)
				data.families.impact.entries.Crack.creator = creator
			end)
		end
		-- A placeholder needs none of them.
		expectClean(function(data)
			data.families.guard.entries.MirrorReflect.title = nil
		end)
	end)

	it("starts the trim at 0 or later", function()
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.startAt = -0.01
			end),
			CRACK .. ": startAt must be 0 or more seconds"
		)
		expectClean(function(data)
			data.families.impact.entries.Crack.startAt = 0
		end)
	end)

	it("ends the trim after its start and inside the asset", function()
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.stopAt = 0.39
			end),
			CRACK .. ": stopAt 0.39 must be after startAt 0.39"
		)
		expectClean(function(data)
			data.families.impact.entries.Crack.stopAt = 0.45
		end)
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.stopAt = 1.2
			end),
			CRACK .. ": stopAt 1.2 is past the asset's length 1.18"
		)
		expectClean(function(data)
			data.families.impact.entries.Crack.stopAt = 1.18
		end)
		-- With no stopAt the asset's end is the end, so the start must be inside it.
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.stopAt = nil
				data.families.impact.entries.Crack.startAt = 1.18
			end),
			CRACK .. ": startAt 1.18 is past the asset's length 1.18"
		)
		expectClean(function(data)
			data.families.impact.entries.Crack.stopAt = nil
		end)
	end)

	it("fits the fade inside the audible part", function()
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.fadeOut = 0.3
			end),
			CRACK .. ": fadeOut 0.3 is longer than the audible part (0.39 to 0.62)"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.fadeOut = -0.05
			end),
			CRACK .. ": fadeOut must be 0 or more seconds"
		)
		expectClean(function(data)
			data.families.impact.entries.Crack.fadeOut = 0.2
		end)
		expectClean(function(data)
			data.families.impact.entries.Crack.fadeOut = 0
		end)
		expectOnly(
			problemsWith(function(data)
				local entry = data.families.impact.entries.Crack
				entry.id, entry.placeholder, entry.length, entry.stopAt = "rbxassetid://0", true, nil, nil
			end),
			CRACK .. ": fadeOut needs a stopAt or a length to end at"
		)
	end)

	it("keeps a measured peak inside the audible part", function()
		local MEDIUM = "sfx.families.whoosh.Medium"
		expectOnly(
			problemsWith(function(data)
				data.families.whoosh.entries.Medium.peakAt = 0.3
			end),
			MEDIUM .. ": peakAt 0.3 must lie in the audible part (0.34 to 0.55)"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.whoosh.entries.Medium.peakAt = 0.6
			end),
			MEDIUM .. ": peakAt 0.6 must lie in the audible part (0.34 to 0.55)"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.whoosh.entries.Medium.peakAt = "loud"
			end),
			MEDIUM .. ": peakAt must be seconds of the asset"
		)
		expectClean(function(data)
			data.families.whoosh.entries.Medium.peakAt = 0.55
		end)
		expectClean(function(data)
			data.families.whoosh.entries.Medium.peakAt = nil
		end)
		-- With no stopAt the asset's length ends the audible part.
		expectClean(function(data)
			local entry = data.families.impact.entries.RingTail
			entry.stopAt, entry.peakAt = nil, 18
		end)
		expectOnly(
			problemsWith(function(data)
				local entry = data.families.impact.entries.Crack
				entry.stopAt, entry.fadeOut, entry.peakAt = nil, 0, 1.3
			end),
			CRACK .. ": peakAt 1.3 must lie in the audible part (0.39 to 1.18)"
		)
	end)

	it("loops only a region with a stopAt, longer than the minimum, with no per-cycle fade", function()
		expectOnly(
			problemsWith(function(data)
				data.families.ui.entries.LowHpHeartbeat.stopAt = nil
			end),
			HEARTBEAT .. ": a loop needs a stopAt"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.ui.entries.LowHpHeartbeat.stopAt = 0.6
			end),
			HEARTBEAT .. ": the loop region 0.18..0.6 must be longer than 0.5 s"
		)
		expectClean(function(data)
			data.families.ui.entries.LowHpHeartbeat.stopAt = 0.7
		end)
		expectOnly(
			problemsWith(function(data)
				data.families.ui.entries.LowHpHeartbeat.fadeOut = 0.2
			end),
			HEARTBEAT .. ": a loop has no fadeOut"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.ui.entries.LowHpHeartbeat.loop = "yes"
			end),
			HEARTBEAT .. ": loop must be a boolean"
		)
		-- The same short region is fine on a one-shot.
		expectClean(function(data)
			data.families.ui.entries.LowHpHeartbeat.loop = false
			data.families.ui.entries.LowHpHeartbeat.stopAt = 0.6
		end)
	end)

	it("keeps every pitch range inside the PlaybackSpeed range", function()
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.pitchRange = { 0.96, 2.5 }
			end),
			CRACK .. ": pitchRange 0.96..2.5 is outside the PlaybackSpeed range 0.5..2"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.Crack.pitchRange = { 0.4, 1 }
			end),
			"is outside the PlaybackSpeed range"
		)
		expectClean(function(data)
			data.families.impact.entries.Crack.pitchRange = { 0.5, 2 }
		end)
	end)

	it("needs its own ranges and limits", function()
		expectOnly(
			problemsWith(function(data)
				data.engine.playbackSpeed = nil
			end),
			"sfx.engine.playbackSpeed must be a {min, max} range"
		)
		expectOnly(
			problemsWith(function(data)
				data.engine.playbackSpeed = { min = 1.2, max = 2 }
			end),
			"sfx.engine.playbackSpeed must be positive and hold 1"
		)
		expectOnly(
			problemsWith(function(data)
				data.limits.maxPlayVolume = nil
			end),
			"sfx.limits.maxPlayVolume must be a positive volume"
		)
		expectOnly(
			problemsWith(function(data)
				data.limits.maxPlayVolume = 12
			end),
			"sfx.limits.maxPlayVolume must be inside the engine's Sound.Volume range"
		)
		expectOnly(
			problemsWith(function(data)
				data.limits.loopMinSeconds = 0
			end),
			"sfx.limits.loopMinSeconds must be a positive number of seconds"
		)
		expectOnly(
			problemsWith(function(data)
				data.playback.openEndSeconds = nil
			end),
			"sfx.playback.openEndSeconds must be a positive number of seconds"
		)
		expectOnly(
			problemsWith(function(data)
				data.playback.sameFrameSeconds = 0
			end),
			"sfx.playback.sameFrameSeconds must be a positive number of seconds (one frame)"
		)
		expectOnly(
			problemsWith(function(data)
				data.limits.sharedAssetSemitones = nil
			end),
			"sfx.limits.sharedAssetSemitones must be a positive number of semitones"
		)
	end)

	it("keeps the slots that share one asset at least limits.sharedAssetSemitones apart in pitch", function()
		-- The strike's old range: its top (0.88) 0.39 semitone under the snort's bottom (0.9).
		expectOnly(
			problemsWith(function(data)
				data.families.enemy.entries.ChargerStrike.pitchRange = { 0.78, 0.88 }
			end),
			"sfx.families.enemy.ChargerSnort and enemy.ChargerStrike share rbxassetid://9113634896: their pitch ranges 0.9..1.1 and 0.78..0.88 must be 1 semitone(s) apart"
		)
		-- Ranges that meet are one sound; an entry with no range plays at the asset's own speed, 1
		-- (the stagger at 1 is still 1.4 semitones over the death's 0.92, but inside the strike's).
		local brute = problemsWith(function(data)
			data.families.enemy.entries.BruteStagger.pitchRange = nil
			data.families.enemy.entries.BruteStrike.pitchRange = { 0.9, 1.1 }
		end)
		expect(#brute).toBe(2)
		expect(brute[1]).toContain("enemy.BruteDeath and enemy.BruteStrike share rbxassetid://9113988191")
		expect(brute[2]).toContain("enemy.BruteStagger and enemy.BruteStrike share rbxassetid://9113988191")
		expect(brute[2]).toContain("1..1 and 0.9..1.1")
		-- 0.84 x 2^(1/12) = 0.89: a semitone and a little under the snort.
		expectClean(function(data)
			data.families.enemy.entries.ChargerStrike.pitchRange = { 0.74, 0.84 }
		end)
		-- Two placeholders share rbxassetid://0 and are never compared.
		expectClean(function(data)
			data.families.ui.entries.MenuOpen.pitchRange = { 1, 1 }
			data.families.ui.entries.MenuClose.pitchRange = { 1, 1 }
		end)
	end)

	it("keeps the HP heartbeat at or under volume 1 with its lift above the mix", function()
		-- 0.8 x 10^(3 / 20) = 1.13.
		expectOnly(
			problemsWith(function(data)
				data.families.ui.entries.LowHpHeartbeat.volume = 0.8
			end),
			"ui.LowHpHeartbeat plays at volume 1.13 with the heartbeat's +3 dB, over limits.maxPlayVolume 1"
		)
		-- 0.7 x 10^(3 / 20) = 0.99: still inside.
		expectClean(function(data)
			data.families.ui.entries.LowHpHeartbeat.volume = 0.7
		end)
		expectOnly(
			problemsWith(function(data)
				data.mix.heartbeatOverAllDb = nil
			end),
			"sfx.mix.heartbeatOverAllDb must be a number of dB"
		)
	end)
end)

describe("sfx validator: cues and contours", function()
	it("wants every required cue and contour", function()
		expectOnly(
			problemsWith(function(data)
				data.cues.Parry = nil
			end),
			"sfx.cues is missing 'Parry'"
		)
		expectOnly(
			problemsWith(function(data)
				data.cues.HitBasic = nil
			end),
			"sfx.cues is missing 'HitBasic'"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.KillCut = nil
			end),
			"sfx.contours is missing 'KillCut'"
		)
	end)

	it("holds a cue to 1..6 layers and a Hit cue to a stack of 3", function()
		expectOnly(
			problemsWith(function(data)
				table.remove(data.cues.HitNormal)
				table.remove(data.cues.HitNormal)
			end),
			"sfx.cues.HitNormal has 2 layers; a hit is a stack of at least 3"
		)
		expectOnly(
			problemsWith(function(data)
				data.cues.Block = {}
			end),
			"sfx.cues.Block has 0 layers (a cue has 1 to 6)"
		)
		expectOnly(
			problemsWith(function(data)
				for _ = 1, 3 do
					table.insert(data.cues.BossShatter, { name = "impact.Ring", delay = 0.1, gainDb = -6 })
				end
			end),
			"sfx.cues.BossShatter has 7 layers"
		)
	end)

	it("resolves every layer and keeps delays in 0..1 s and gains in range", function()
		expectOnly(
			problemsWith(function(data)
				data.cues.Dodge[2].name = "whoosh.Enormous"
			end),
			"sfx.cues.Dodge layer 2 sound 'whoosh.Enormous' is not a sfx.luau 'family.Name'"
		)
		local delays = problemsWith(function(data)
			data.cues.Dodge[2].delay = -0.01
			data.cues.GuardBreak[2].delay = 1
		end)
		expect(#delays).toBe(2)
		expect(delays[1]).toContain("sfx.cues.Dodge layer 2 delay -0.01 must be 0 or more")
		expect(delays[2]).toContain("sfx.cues.GuardBreak layer 2 delay 1 must be 0 or more and under 1 s")
		-- Under a frame: the pool plays it with the cue, so the data must not claim a wait.
		expectOnly(
			problemsWith(function(data)
				data.cues.HitNormal[2].delay = 0.004
			end),
			"sfx.cues.HitNormal layer 2 delay 0.004 is under one frame"
		)
		-- Exactly a frame is a real wait.
		expectClean(function(data)
			data.cues.HitNormal[4].delay = Combat.hitStopFrameSeconds
		end)
		expectOnly(
			problemsWith(function(data)
				data.cues.HitCrit[1].gainDb = 12
			end),
			"sfx.cues.HitCrit layer 1 gainDb 12 must be in -30..6 dB"
		)
	end)

	it("keeps every layer at or under volume 1 after its gain", function()
		-- The kill's ring: 0.65 x 10^(4 / 20) = 1.03.
		expectOnly(
			problemsWith(function(data)
				data.cues.HitKill[4].gainDb = 4
			end),
			"sfx.cues.HitKill layer 4 plays at volume 1.03, over limits.maxPlayVolume 1"
		)
		-- 0.65 x 10^(3.7 / 20) = 0.995: still inside.
		expectClean(function(data)
			data.cues.HitKill[4].gainDb = 3.7
		end)
	end)

	it("keeps a layer's own pitch inside the PlaybackSpeed range", function()
		expectOnly(
			problemsWith(function(data)
				data.cues.BossShatter[3].pitch = 0.3
			end),
			"sfx.cues.BossShatter layer 3 pitch 0.3 must be a PlaybackSpeed in 0.5..2"
		)
		expectOnly(
			problemsWith(function(data)
				data.cues.HitCrit[1].pitch = "high"
			end),
			"sfx.cues.HitCrit layer 1 pitch high must be a PlaybackSpeed"
		)
		expectClean(function(data)
			data.cues.BossShatter[3].pitch = 0.5
		end)
	end)

	it("keeps the sub-bass out of HitKill", function()
		expectOnly(
			problemsWith(function(data)
				table.insert(data.cues.HitKill, { name = "impact.Sub", delay = 0, gainDb = 0 })
			end),
			"sfx.cues.HitKill carries the sub-bass layer 'impact.Sub'"
		)
	end)

	it("holds contour steps to the effect groups, the engine ranges, the length and an eased curve", function()
		expectOnly(
			problemsWith(function(data)
				data.contours.ParryRing[1].group = "UI"
			end),
			"sfx.contours.ParryRing step 1 group 'UI' is not in sfx.effects.groups"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.FinalHit[1].low = -90
			end),
			"sfx.contours.FinalHit step 1 low -90 dB is outside the EQ gain range -80..10"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.WindUp[1].high = 12
			end),
			"sfx.contours.WindUp step 1 high 12 dB is outside the EQ gain range"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.ShatterBloom[1].wet = 25
			end),
			"sfx.contours.ShatterBloom step 1 wet 25 dB is outside the reverb WetLevel range -80..20"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.ShatterBloom[2].easing = "Linear"
			end),
			"sfx.contours.ShatterBloom step 2 easing 'Linear' must ease"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.ShatterBloom[2].easing = "Wobble"
			end),
			"easing 'Wobble' is not a known curve"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.KillCut[1] = { at = 0, group = "SFX", ramp = 0 }
			end),
			"sfx.contours.KillCut step 1 sets nothing"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.ParryRing[3].at = 3.98
			end),
			"sfx.contours.ParryRing step 3 ends at 4.03 s, past the 4 s"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.ParryRing[2].ramp = -0.1
			end),
			"sfx.contours.ParryRing step 2 ramp must be 0 or more"
		)
	end)

	it("keeps the effects flat and dry while idle, and the shatter table resolving", function()
		expectOnly(
			problemsWith(function(data)
				data.effects.reverb.wet = -20
			end),
			"sfx.effects.reverb.wet must be -80 dB (dry while no contour runs)"
		)
		expectOnly(
			problemsWith(function(data)
				data.effects.equalizer.low = -20
			end),
			"sfx.effects.equalizer.low must be 0"
		)
		expectOnly(
			problemsWith(function(data)
				data.effects.easing = "Linear"
			end),
			"sfx.effects easing 'Linear' must ease"
		)
		expectOnly(
			problemsWith(function(data)
				data.shatterCues.boss = "BossSplat"
			end),
			"sfx.shatterCues.boss 'BossSplat' is not in sfx.cues"
		)
		expectOnly(
			problemsWith(function(data)
				data.shatterCues.heavy = nil
			end),
			"sfx.shatterCues.heavy must name the cue SfxPool.shatter plays"
		)
		expectOnly(
			problemsWith(function(data)
				data.families.impact.entries.RingTail.note = nil
			end),
			"sfx.families.impact.RingTail needs a note"
		)
	end)

	it("checks the preloaded risers, the sub layers and the bass-back level", function()
		expectOnly(
			problemsWith(function(data)
				data.preload = { "whoosh.Nope" }
			end),
			"sfx.preload[1] 'whoosh.Nope' is not a sfx.luau 'family.Name'"
		)
		expectOnly(
			problemsWith(function(data)
				data.limits.subLayers = { "impact.Sub", "impact" }
			end),
			"sfx.limits.subLayers[2] 'impact' is not a sfx.luau 'family.Name'"
		)
		expectOnly(
			problemsWith(function(data)
				data.limits.bassBackDb = 3
			end),
			"sfx.limits.bassBackDb must be a gain in dB at or under 0"
		)
		expectOnly(
			problemsWith(function(data)
				data.contours.WindUpRelease = nil
			end),
			"sfx.contours is missing 'WindUpRelease'"
		)
	end)
end)

describe("sfx activation contours", function()
	it("takes the music's highs out for the hold and brings them back on WindUpRelease", function()
		local windUp = Sfx.contour("WindUp")
		expect(windUp[1].at).toBe(0)
		expect(windUp[1].group).toBe("Music")
		expect(windUp[1].high).toBeLessThan(-6)
		-- The safety return comes after any hold can last (it cancels itself at the cancel time).
		expect(windUp[#windUp].high).toBe(0)
		expect(windUp[#windUp].at).toBeGreaterThan(Combat.activationCancelTime)
		local release = Sfx.contour("WindUpRelease")
		expect(#release).toBe(1)
		expect(release[1].at).toBe(0)
		expect(release[1].group).toBe("Music")
		expect(release[1].high).toBe(0)
		expect(Sfx.preload[1]).toBe("whoosh.Riser")
	end)

	it("plays the activation recipe without a cue: the chime, the riser and the clip's whoosh", function()
		-- ArtRelease is gone: Replication plays the chime on the hold, the activation moment the
		-- riser into the first damage frame, the Art's clip its whoosh at the anticipation.
		expect(Sfx.cues.ArtRelease).toBeNil()
		expect(Moments.byId("Activation").riser.sound).toBe("whoosh.Riser")
		expect(Sfx.isReal(Sfx.get("artChime", "TrailCyanWhite"))).toBe(true)
	end)
end)

describe("sfx validator: music stem ids", function()
	it("wants one id per stem in music.stemIds, each an rbxassetid:// string", function()
		expectOnly(
			problemsWith(function(data)
				data.music.stemIds.boss = nil
			end),
			"sfx.music.stemIds is missing the 'boss' stem"
		)
		expectOnly(
			problemsWith(function(data)
				data.music.stemIds.fishing = "rbxassetid://0"
			end),
			"sfx.music.stemIds.fishing is not a stem in music.stems"
		)
		expectOnly(
			problemsWith(function(data)
				data.music.stemIds.combat = "9120660382"
			end),
			"sfx.music.stemIds.combat must be an rbxassetid:// string"
		)
		expectClean(function(data)
			data.music.stemIds.combat = "rbxassetid://9120660382"
		end)
	end)
end)
