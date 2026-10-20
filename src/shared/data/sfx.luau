--!strict
--[[
	Sound effects (section 15): one named entry per sound, grouped by family, with the SoundGroup
	each family routes to and the mix rules.

	Where the sounds come from. Real sounds are picks from Roblox's licensed sound library (the
	creators ProSoundEffects, APMOfficial and Roblox), one per slot, each loaded and measured in
	Studio Play: `licensed(...)` builds those entries from the pick (the asset id, its library
	title, creator and length, and the trim, fade, volume and pitch range it plays with). A slot
	the Phase 0 slice plays that has no pick of its own yet borrows the closest pick's asset, trim
	and title with its own pitch range or volume (`reuse(...)`, note "reuses <slot> until its own
	sound is picked"). Every other slot is still a placeholder (`rbxassetid://0`, placeholder =
	true) that SfxPool never plays. docs/PLACEHOLDERS.md lists every sound, real or not.

	Entry fields: id (asset url), placeholder, volume (0..1), pitchRange ({min, max} PlaybackSpeed,
	optional; the pool picks a random value in it), spatial (true = 3D at the source, false = 2D),
	note. The trim, all in seconds of the asset before PlaybackSpeed:
	- startAt: where the audible part starts (nil = 0)
	- stopAt: where it ends (nil = the asset's end)
	- fadeOut: a linear fade to silence that ends at stopAt (nil or 0 = a hard stop)
	- loop: true loops startAt..stopAt (only the heartbeat layer and the ambience beds)
	The credits: length (the asset's full length as the library lists it; stopAt never passes
	it), title (the library title) and creator. peakAt (seconds of the asset, measured in Studio
	Play at PlaybackSpeed 1, optional) is where the play is loudest: a clip whoosh's Sfx event sits
	`peakLead` before its strike's HitWindowOpen so the swell peaks on the snap.

	Levels. "0 dB" is a PlaybackLoudness peak x volume of 200, the level of the hit's crack and
	body. Each pick's volume puts its own peak where the mix wants it (whoosh.Small at 0.35 is
	-4.8 dB, impact.Sub at 0.7 is +3.5), so a cue layer's gainDb is only the change for that
	play, and no layer ends above volume 1 (limits.maxPlayVolume).

	The reel style on top of section 15 (the hit sound is a stack, not one sample):
	- `cues`: layered recipes. Every big hit is 4 to 6 layers at once (a whoosh before contact from
	  the clip, a crack at contact, a body, a material layer, a sub-bass thump, a metal ring or
	  tail after), all started on the contact frame: each pick's startAt sits about 30 ms before
	  its own attack, so the layers fuse into one hit. Each layer is {name = "family.Name", delay
	  = seconds after the cue, gainDb = a per-play offset on the entry's volume, pitch = an
	  optional PlaybackSpeed for this play in place of the entry's random pitch}; SfxPool.cue
	  plays them through its normal path (dedupe, placeholders). A delay is 0 or at least
	  playback.sameFrameSeconds: the engine resumes a waiting thread once per frame, so a
	  few-ms offset would land a whole frame late (a flam). The hit-stop tick is not a cue layer: Replication plays it in
	  2D for the fighters in the hit (it is their own frame freezing), and a cue plays for every
	  client in range.
	- `contours`: mix automation over time on the SoundGroups in `effects.groups`. Frequency
	  contrast: the bass leaves during the impact frames and slams back on the release; the
	  reverb is wet on the big moment and dry right after so fast hits stay clean. Each step is
	  {at = seconds, group, low / mid / high = EqualizerSoundEffect gains in dB, wet = the
	  ReverbSoundEffect WetLevel in dB, ramp = seconds, easing = an Easing name (optional)}.
	  A contour that ends off the defaults eases back to them (flat EQ, dry reverb).
	- `effects`: the one EqualizerSoundEffect and one ReverbSoundEffect each contour group carries,
	  flat and dry when no contour runs. `engine`: the property ranges the engine accepts.
	  `playback`: how SfxPool maps a trim onto its Sound, and the shortest wait a cue layer
	  can have. `limits`: the rules the sfx validator
	  holds the entries, cues and contours to.
]]

local Combat = require(script.Parent.combat)

export type Entry = {
	id: string,
	placeholder: boolean,
	volume: number,
	pitchRange: { number }?,
	spatial: boolean,
	note: string?,
	startAt: number?, -- seconds of the asset before PlaybackSpeed; nil = 0
	stopAt: number?, -- nil = the asset's end
	fadeOut: number?, -- a linear fade to silence ending at stopAt; nil or 0 = a hard stop
	loop: boolean?, -- loops startAt..stopAt (SfxPool.loop and the ambience beds only)
	length: number?, -- the asset's full length as the library lists it
	title: string?, -- the library title, for the credits list
	creator: string?, -- "ProSoundEffects" | "APMOfficial" | "Roblox"
	peakAt: number?, -- seconds of the asset where it is loudest (measured); a clip whoosh times by it
}

export type Family = {
	group: string, -- SoundGroup name
	entries: { [string]: Entry },
}

-- One layer of a cue: a sound by "family.Name", when it starts after the cue, its offset in dB on
-- the entry's volume for this play only (the entry's base volume never changes) and, when set,
-- the PlaybackSpeed of this play in place of a random pick in the entry's pitchRange.
export type CueLayer = { name: string, delay: number, gainDb: number, pitch: number? }

-- One step of a contour: from `at` seconds after the contour starts, ease the named group's EQ
-- bands (dB) and reverb wet level (dB) from where they are to these values over `ramp` seconds.
export type ContourStep = {
	at: number,
	group: string,
	low: number?,
	mid: number?,
	high: number?,
	wet: number?,
	ramp: number,
	easing: string?,
}

export type Range = { min: number, max: number }

-- One pick from the licensed library: the asset id's digits, its library listing, and the trim
-- (seconds of the asset), volume and pitch range it plays with.
type Take = {
	id: string,
	title: string,
	creator: string,
	length: number,
	startAt: number,
	stopAt: number,
	fadeOut: number,
	volume: number,
	pitch: { number },
	loop: boolean?,
	peakAt: number?,
}

local PLACEHOLDER = "rbxassetid://0"
local ASSET_PREFIX = "rbxassetid://"

-- The hit-stop holds the impact frames ride in (they must fit inside them, impact.luau): the bass
-- is out for the whole freeze and slams back as the clip clock lets go.
local FINAL_HOLD = Combat.hitStopFrames.Final * Combat.hitStopFrameSeconds
local KILL_HOLD = Combat.hitStopFrames.Kill * Combat.hitStopFrameSeconds
-- FinalHit's SFX bass comes back over this ramp and is all the way back on FINAL_HOLD, the moment
-- HitFinal's sub thumps (a sub under the cut would swell in instead of slamming).
local FINAL_BASS_RAMP = 0.04

-- Pitch ranges a cue reads too: a crit plays the crack and the ring at the top of theirs.
local CRACK_PITCH = { 0.96, 1.04 }
local RING_PITCH = { 0.98, 1.02 }
-- The boss crack plays slowed (about 3 s of glass); the boss shatter's chime is the slow version.
local BOSS_CRACK_PITCH = { 0.7, 0.75 }
local SLOW_CHIME_PITCH = 0.75

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

-- A real sound from the licensed library, from its pick.
local function licensed(spatial: boolean, take: Take, note: string?): Entry
	return {
		id = ASSET_PREFIX .. take.id,
		placeholder = false,
		volume = take.volume,
		pitchRange = { take.pitch[1], take.pitch[2] },
		spatial = spatial,
		note = note,
		startAt = take.startAt,
		stopAt = take.stopAt,
		fadeOut = take.fadeOut,
		loop = take.loop == true,
		length = take.length,
		title = take.title,
		creator = take.creator,
		peakAt = take.peakAt,
	}
end

-- A slot the slice plays with no pick of its own yet: the pick of `slot` (its asset, trim and
-- title) at this slot's own volume and pitch range, so the two never sound alike.
local function reuse(slot: string, source: Entry, volume: number, pitchRange: { number }): Entry
	local entry = table.clone(source)
	entry.volume = volume
	entry.pitchRange = pitchRange
	entry.note = ("reuses %s until its own sound is picked"):format(slot)
	return entry
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

-- Section 15: a vocalization per archetype for each of these.
local VOCAL_MOMENTS = { "WindUp", "Strike", "Stagger", "Death" }

local SURFACES = { "Stone", "Grass", "Wood", "Water", "Snow", "Gravel" }
local WEIGHTS = { "Light", "Armored" }

-- Art activation chime, one per trail color; the pool pitches it by weapon weight at play time.
local artChime: { [string]: Entry } = {}
for _, color in TRAIL_COLORS do
	artChime[color] = sound(0.7, true, { 0.95, 1.05 }, "pitched down by weapon weight")
end
artChime.TrailCyanWhite = licensed(true, {
	id = "9119833793",
	title = "Synth Sparkle Tone High Pitch Tone Burst 4 (SFX)",
	creator = "ProSoundEffects",
	length = 1.23,
	startAt = 0.035,
	stopAt = 0.35,
	fadeOut = 0.06,
	volume = 0.6,
	pitch = { 0.95, 1.05 },
}, "pitched down by weapon weight; an 84% high burst that sits above the riser it plays with")
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

-- The boar (Charger) and the kobold (Brute), the Phase 0 enemies.
vocalizations.ChargerSnort = licensed(true, {
	id = "9113634896",
	title = "Bull Goblin Snorts 6 (SFX)",
	creator = "ProSoundEffects",
	length = 0.39,
	startAt = 0.04,
	stopAt = 0.36,
	fadeOut = 0.04,
	volume = 1,
	pitch = { 0.9, 1.1 },
}, "one snort that reads above the combat lows")
vocalizations.ChargerWindUp = licensed(true, {
	id = "9117369876",
	title = "Pig Squeals 1 (SFX)",
	creator = "ProSoundEffects",
	length = 2.54,
	startAt = 0.2,
	stopAt = 0.85,
	fadeOut = 0.2,
	volume = 0.75,
	pitch = { 0.9, 1.1 },
}, "an angry squeal from the first frame of the 0.6 s crouch")
vocalizations.ChargerDeath = licensed(true, {
	id = "9118314102",
	title = "Robot Screams Pig Squeals 52 (SFX)",
	creator = "ProSoundEffects",
	length = 1.99,
	startAt = 0.58,
	stopAt = 1.05,
	fadeOut = 0.12,
	volume = 0.65,
	pitch = { 0.95, 1.05 },
}, "the louder second squeal; its peak lands inside the kill's hit-stop, before the death silence")
vocalizations.BruteRoar = licensed(true, {
	id = "9114624343",
	title = "Goblin Growl 2 (SFX)",
	creator = "ProSoundEffects",
	length = 3,
	startAt = 0.2,
	stopAt = 1.8,
	fadeOut = 0.45,
	volume = 0.7,
	pitch = { 0.85, 1 },
}, "a growl that builds to a long hold")
vocalizations.BruteWindUp = licensed(true, {
	id = "9114624510",
	title = "Goblin Growl 4 (SFX)",
	creator = "ProSoundEffects",
	length = 1.75,
	startAt = 0.25,
	stopAt = 1.55,
	fadeOut = 0.1,
	volume = 0.55,
	pitch = { 0.95, 1.05 },
}, "one crescendo whose climax lands on the end of the 1.0 s overhead")
vocalizations.BruteDeath = licensed(true, {
	id = "9113988191",
	title = "Creature Vocal Pterodactyl Death Shriek 2 (SFX)",
	creator = "ProSoundEffects",
	length = 0.84,
	startAt = 0.04,
	stopAt = 0.76,
	fadeOut = 0.1,
	volume = 1,
	pitch = { 0.85, 0.92 },
}, "a shriek pitched down; its peak lands inside the kill's hit-stop")
-- The Phase 0 vocals with no pick of their own: the nearest pick, pitched at least
-- limits.sharedAssetSemitones away from every other slot on the same asset (the sfx validator).
-- The strike is the snort dropped about 3 semitones into a grunt, at full level like its source
-- (it is the attack, never quieter than the idle snort). The staggers are the death screams up
-- about 2 semitones and well under them: a pained yelp, not a wind-up growl, which would read as
-- the telegraph. The strikes are Voice events on the strike frame of the Charge and Overhead clips.
vocalizations.ChargerStrike = reuse("enemy.ChargerSnort", vocalizations.ChargerSnort, 1, { 0.74, 0.84 })
vocalizations.ChargerStagger = reuse("enemy.ChargerDeath", vocalizations.ChargerDeath, 0.45, { 1.12, 1.22 })
vocalizations.BruteStrike = reuse("enemy.BruteDeath", vocalizations.BruteDeath, 0.75, { 0.98, 1.04 })
vocalizations.BruteStagger = reuse("enemy.BruteDeath", vocalizations.BruteDeath, 0.6, { 1.11, 1.19 })

local footsteps: { [string]: Entry } = {}
for _, surface in SURFACES do
	for _, weight in WEIGHTS do
		footsteps[surface .. weight] = sound(if weight == "Armored" then 0.5 else 0.35, true, { 0.92, 1.08 })
	end
end
footsteps.GrassLight = licensed(true, {
	id = "9120062559",
	title = "Tip Toe Of Object Onto Grass 1 (SFX)",
	creator = "ProSoundEffects",
	length = 0.8,
	startAt = 0,
	stopAt = 0.3,
	fadeOut = 0.1,
	volume = 1,
	pitch = { 0.92, 1.08 },
}, "one instant grass contact and a little rustle; ends before the next step at run cadence")
footsteps.StoneLight = licensed(true, {
	id = "9118250959",
	title = "Robot Footsteps On Concrete 27 (SFX)",
	creator = "ProSoundEffects",
	length = 0.84,
	startAt = 0,
	stopAt = 0.18,
	fadeOut = 0.05,
	volume = 0.14,
	pitch = { 0.92, 1.08 },
}, "one hard instant contact on stone (also every surface fx.audio does not map)")
footsteps.LandSoft = licensed(true, {
	id = "9120879856",
	title = "Wood Grab Muted Thuds 10 (SFX)",
	creator = "ProSoundEffects",
	length = 2.31,
	startAt = 0,
	stopAt = 0.15,
	fadeOut = 0.06,
	volume = 1,
	pitch = { 0.95, 1.05 },
}, "short falls and the dodge's step end: the first 0.15 s of a muted thud")
footsteps.LandHard = licensed(true, {
	id = "9113480915",
	title = "Body Fall Thud 2 (SFX)",
	creator = "ProSoundEffects",
	length = 1.08,
	startAt = 0.07,
	stopAt = 0.24,
	fadeOut = 0.06,
	volume = 0.45,
	pitch = { 0.9, 1 },
}, "scaled by fall height; cut before the settle bump that reads as falling down")

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
				Small = licensed(true, {
					id = "9119749145",
					title = "Sword Swish 102 (SFX)",
					creator = "ProSoundEffects",
					length = 0.96,
					startAt = 0,
					stopAt = 0.32,
					fadeOut = 0.06,
					volume = 0.35,
					pitch = { 0.95, 1.1 },
					peakAt = 0.066,
				}, "daggers, rapier points"),
				Medium = licensed(true, {
					id = "9119749044",
					title = "Sword Swish 201 (SFX)",
					creator = "ProSoundEffects",
					length = 0.9,
					startAt = 0.34,
					stopAt = 0.55,
					fadeOut = 0.06,
					volume = 0.32,
					pitch = { 0.95, 1.05 },
					peakAt = 0.401,
				}, "one-handed arcs; the louder second swish of the file"),
				Large = licensed(true, {
					id = "9126229280",
					title = "Whoosh By Fast Airy Swooshing Whipping Thuds (SFX)",
					creator = "ProSoundEffects",
					length = 1.45,
					startAt = 0.09,
					stopAt = 0.53,
					fadeOut = 0.08,
					volume = 0.36,
					pitch = { 0.85, 1 },
					peakAt = 0.234,
				}, "two-handed, axes, spears; one low swell, the loudest whoosh"),
				Basic = licensed(true, {
					id = "9119750698",
					title = "Sword Whip 104 (SFX)",
					creator = "ProSoundEffects",
					length = 3.08,
					startAt = 1.03,
					stopAt = 1.75,
					fadeOut = 0.3,
					volume = 0.8,
					pitch = { 0.95, 1.1 },
					peakAt = 1.199,
				}, "the thinner basic swing, quieter than Small"),
				Riser = licensed(
					true,
					{
						id = "9118158252",
						title = "Reversed Whoosh Backwards Hissing Burst 3 (SFX)",
						creator = "ProSoundEffects",
						length = 1.5,
						startAt = 0.15,
						stopAt = 0.46,
						fadeOut = 0,
						volume = 0.7,
						pitch = { 0.98, 1.02 },
					},
					"a short reverse suck-back that builds into the hit and stops at full level on its plateau; SfxPool.playEndingAt lands its stopAt on the first damage frame (the pool places it by the play's PlaybackSpeed)"
				),
				Dodge = licensed(true, {
					id = "9114890978",
					title = "Jump Swish 1 (SFX)",
					creator = "ProSoundEffects",
					length = 0.91,
					startAt = 0.2,
					stopAt = 0.58,
					fadeOut = 0.08,
					volume = 0.5,
					pitch = { 0.95, 1.08 },
				}, "the dodge step's short body whoosh; its peak lands about 0.17 s into the 0.25 s step"),
			},
		},

		impact = {
			group = "SFX",
			entries = {
				Flesh = licensed(true, {
					id = "9116485156",
					title = "Meat Hack Fleshy Hits 2 (SFX)",
					creator = "ProSoundEffects",
					length = 1.37,
					startAt = 0.27,
					stopAt = 0.72,
					fadeOut = 0.15,
					volume = 0.6,
					pitch = { 0.95, 1.05 },
				}, "the material layer on flesh: a wet mid and high texture over the body"),
				Armor = licensed(true, {
					id = "9119072660",
					title = "Shield Clang As Hit Metal Sword Hubcap 1 (SFX)",
					creator = "ProSoundEffects",
					length = 0.74,
					startAt = 0,
					stopAt = 0.3,
					fadeOut = 0.05,
					volume = 0.28,
					pitch = { 0.95, 1.05 },
				}, "the material layer on armor: a plate clang"),
				Construct = licensed(true, {
					id = "9118587701",
					title = "Rock Drop On Concrete Drops Breaks 4 (SFX)",
					creator = "ProSoundEffects",
					length = 2.01,
					startAt = 0.25,
					stopAt = 0.5,
					fadeOut = 0.08,
					volume = 1,
					pitch = { 0.95, 1.05 },
				}, "the material layer on constructs: the first stone hit, without the debris pops"),
				Ring = licensed(true, {
					id = "9125362690",
					title = "Anvil Hits Ringing Metal Clinks Some Muted 3 (SFX)",
					creator = "ProSoundEffects",
					length = 1.09,
					startAt = 0,
					stopAt = 0.27,
					fadeOut = 0.05,
					volume = 0.65,
					pitch = table.clone(RING_PITCH),
				}, "the short metallic ring layered on every impact"),
				FinalHit = licensed(true, {
					id = "9119746592",
					title = "Sword Hit 2 (SFX)",
					creator = "ProSoundEffects",
					length = 1.19,
					startAt = 0.17,
					stopAt = 0.36,
					fadeOut = 0.05,
					volume = 0.4,
					pitch = { 0.95, 1 },
				}, "the last hit of an Art: a strong mid and low weight in place of the body"),
				Kill = licensed(true, {
					id = "9120113588",
					title = "Tonal Impact 2 (SFX)",
					creator = "ProSoundEffects",
					length = 2.71,
					startAt = 0.1,
					stopAt = 0.75,
					fadeOut = 0.4,
					volume = 1,
					pitch = { 0.95, 1 },
				}, "the kill's weight, the loudest contact layer; ends just before the shatter"),
				Crack = licensed(true, {
					id = "9120660382",
					title = "Whip Cracks 2 (SFX)",
					creator = "ProSoundEffects",
					length = 1.18,
					startAt = 0.39,
					stopAt = 0.62,
					fadeOut = 0.05,
					volume = 0.65,
					pitch = table.clone(CRACK_PITCH),
				}, "the sharp transient at contact, the 0 dB reference of the hit"),
				Body = licensed(true, {
					id = "9113502506",
					title = "Body Hits 8 (SFX)",
					creator = "ProSoundEffects",
					length = 1.12,
					startAt = 0,
					stopAt = 0.5,
					fadeOut = 0.3,
					volume = 0.8,
					pitch = { 0.95, 1.05 },
				}, "the mid-range body under the crack: the blow's weight"),
				Sub = licensed(true, {
					id = "1837830050",
					title = "BOOM-Sub Boom 01",
					creator = "APMOfficial",
					length = 4.32,
					startAt = 0.04,
					stopAt = 0.85,
					fadeOut = 0.55,
					volume = 0.7,
					pitch = { 0.97, 1.02 },
				}, "the sub-bass thump (all low) as the bass slams back in"),
				RingTail = licensed(true, {
					id = "9119747477",
					title = "Sword Long Metallic Ring Decay 1 (SFX)",
					creator = "ProSoundEffects",
					length = 18.4,
					startAt = 0.25,
					stopAt = 2.5,
					fadeOut = 1.4,
					volume = 0.38,
					pitch = { 0.98, 1.02 },
				}, "a sword ring with a long tail: 2.25 s of the strike and ring, faded over the last 1.4 s"),
				SubDrop = licensed(true, {
					id = "1835344220",
					title = "Super Predator Bass Drop",
					creator = "APMOfficial",
					length = 2.44,
					startAt = 0.22,
					stopAt = 2.2,
					fadeOut = 0.7,
					volume = 0.55,
					pitch = { 1, 1 },
				}, "a 2 s bass dive under the shatter; its own lead brings it in about 0.1 s after the slam"),
			},
		},

		hitStopTick = {
			group = "SFX",
			entries = {
				Normal = licensed(false, {
					id = "9119717529",
					title = "Switch Click On Or Off Toggle Button 1 (SFX)",
					creator = "ProSoundEffects",
					length = 0.23,
					startAt = 0,
					stopAt = 0.08,
					fadeOut = 0.02,
					volume = 0.2,
					pitch = { 1, 1 },
				}, "3 frames; a click under the crack"),
				Final = licensed(false, {
					id = "9120490110",
					title = "Wall Switch Turning On Off Clicking Thunks 4 (SFX)",
					creator = "ProSoundEffects",
					length = 0.43,
					startAt = 0.05,
					stopAt = 0.22,
					fadeOut = 0.05,
					volume = 0.74,
					pitch = { 1, 1 },
				}, "6 frames; a click with a thunk"),
				Kill = licensed(false, {
					id = "9116896380",
					title = "Metal Thunk 14 (SFX)",
					creator = "ProSoundEffects",
					length = 0.83,
					startAt = 0,
					stopAt = 0.12,
					fadeOut = 0.02,
					volume = 1,
					pitch = { 1, 1 },
				}, "10 frames; one instant thunk with little low for the bass-cut kill frames"),
			},
		},

		guard = {
			group = "SFX",
			entries = {
				Parry = licensed(true, {
					id = "9116690113",
					title = "Metal Impacts 3 (SFX)",
					creator = "ProSoundEffects",
					length = 3.39,
					startAt = 0.39,
					stopAt = 0.82,
					fadeOut = 0.12,
					volume = 1,
					pitch = { 0.98, 1.02 },
				}, "bright steel clash with a 0.3 s ring"),
				Block = licensed(true, {
					id = "9116673678",
					title = "Metal Impact Heavy Clunking Hits Scraping 1 (SFX)",
					creator = "ProSoundEffects",
					length = 1.46,
					startAt = 0.02,
					stopAt = 0.5,
					fadeOut = 0.15,
					volume = 0.2,
					pitch = { 0.95, 1.05 },
				}, "a dull low block with no ring, so it is never heard as a parry"),
				GuardBreak = licensed(true, {
					id = "9120801590",
					title = "Wood Break 1 (SFX)",
					creator = "ProSoundEffects",
					length = 1.48,
					startAt = 0.45,
					stopAt = 0.8,
					fadeOut = 0.12,
					volume = 0.5,
					pitch = { 0.95, 1 },
				}, "a crack: only the break, with more low than the hit's crack"),
				GuardRaise = licensed(true, {
					id = "9119075376",
					title = "Shield Impacts 13 (SFX)",
					creator = "ProSoundEffects",
					length = 2.34,
					startAt = 0.27,
					stopAt = 0.58,
					fadeOut = 0.12,
					volume = 0.14,
					pitch = { 0.95, 1.05 },
				}, "a quiet shield lift tap"),
				MirrorReflect = sound(0.7, true, { 0.98, 1.02 }, "a Mirror Shield sending a hit back"),
				ParryRing = licensed(true, {
					id = "9119747479",
					title = "Sword Long Metallic Ring Decay 2 (SFX)",
					creator = "ProSoundEffects",
					length = 18.21,
					startAt = 0.3,
					stopAt = 2.8,
					fadeOut = 1.5,
					volume = 0.45,
					pitch = { 0.98, 1.02 },
				}, "the parry's long ring after the clash: 2.5 s, faded over the last 1.5 s"),
			},
		},

		shatter = {
			group = "SFX",
			entries = {
				Crack = licensed(true, {
					id = "9114615010",
					title = "Glass Smashes 7 (SFX)",
					creator = "ProSoundEffects",
					length = 2.06,
					startAt = 0.3,
					stopAt = 0.64,
					fadeOut = 0.1,
					volume = 1,
					pitch = { 0.97, 1.03 },
				}, "the glass crack: the first smash, stopped before the second rises"),
				Chime = licensed(true, {
					id = "9125644310",
					title = "Magic Twirling Small High Pitch Spinning Chi (SFX)",
					creator = "ProSoundEffects",
					length = 1.9,
					startAt = 0.18,
					stopAt = 1.25,
					fadeOut = 0.3,
					volume = 0.7,
					pitch = { 1, 1 },
				}, "the rising chime cluster: it peaks about 0.25 s in, as the crack fades"),
				BossCrack = licensed(true, {
					id = "9114590265",
					title = "Glass Break 2 (SFX)",
					creator = "ProSoundEffects",
					length = 5.02,
					startAt = 0.57,
					stopAt = 2.8,
					fadeOut = 1,
					volume = 1,
					pitch = table.clone(BOSS_CRACK_PITCH),
				}, "slow version: 2.23 s of glass at 0.70 to 0.75x plays the 3 s burst"),
				BossBoom = licensed(false, {
					id = "9120769456",
					title = "Wind Whoosh Sonic Boom Low End Impact 2 (SFX)",
					creator = "ProSoundEffects",
					length = 8.96,
					startAt = 0.985,
					stopAt = 2,
					fadeOut = 0.4,
					volume = 0.5,
					pitch = { 1, 1 },
				}, "the boss shatter's low boom, level with the slam"),
				TeleportRise = sound(0.7, true, nil, "the shatter reversed for the Gate"),
				TeleportArrive = sound(0.7, true, nil),
				Slam = licensed(true, {
					id = "9125484367",
					title = "Deep Hits Big Reverberant Booms Rumbling Tai (SFX)",
					creator = "ProSoundEffects",
					length = 4.44,
					startAt = 0.07,
					stopAt = 1.2,
					fadeOut = 0.7,
					volume = 0.9,
					pitch = { 0.97, 1 },
				}, "the slam after the death freeze, the loudest moment: the bass back at once under the glass"),
			},
		},

		footsteps = { group = "SFX", entries = footsteps },

		telegraph = {
			group = "SFX",
			entries = {
				Tick = licensed(true, {
					id = "9113399659",
					title = "Beeps Short And Long Bursts 10 (SFX)",
					creator = "ProSoundEffects",
					length = 1.4,
					startAt = 0.085,
					stopAt = 0.32,
					fadeOut = 0.1,
					volume = 0.55,
					pitch = { 0.98, 1.02 },
				}, "the wind-up start: one beep, its ring-out cut so many wind-ups never pile up"),
				Unblockable = licensed(true, {
					id = "9113086354",
					title = "Alarm Buzzer 2 (SFX)",
					creator = "ProSoundEffects",
					length = 2.23,
					startAt = 0.36,
					stopAt = 0.95,
					fadeOut = 0.15,
					volume = 0.75,
					pitch = { 0.98, 1.02 },
				}, "red edge: a buzzer over the 0.6 s crouch, the loudest telegraph"),
				GuardBreak = licensed(true, {
					id = "9125673878",
					title = "Metallic Beeps Quick Tones Some Dual Bursts (SFX)",
					creator = "ProSoundEffects",
					length = 1.09,
					startAt = 0,
					stopAt = 0.45,
					fadeOut = 0.08,
					volume = 0.6,
					pitch = { 0.98, 1.02 },
				}, "yellow edge: a two-burst tone, a rhythm apart from the white beep and the red buzz"),
			},
		},

		enemy = { group = "SFX", entries = vocalizations },

		ui = {
			group = "UI",
			entries = {
				MenuOpen = sound(0.5, false, nil, "the gesture chime"),
				MenuClose = sound(0.45, false, nil),
				SystemLine = licensed(false, {
					id = "9126072698",
					title = "Synth Sparkle Tone High Pitch Bell Tone Ding (SFX)",
					creator = "ProSoundEffects",
					length = 2.34,
					startAt = 0.29,
					stopAt = 1.25,
					fadeOut = 0.3,
					volume = 0.65,
					pitch = { 1, 1 },
				}, "the short chime under a centered system line: a cyan-white sparkle"),
				SystemLineWarded = sound(0.5, false, nil, "purple popups"),
				Pickup = sound(0.45, false, { 0.98, 1.02 }),
				Crowns = sound(0.45, false, { 0.98, 1.02 }),
				Equip = sound(0.45, false, nil),
				DropCommon = sound(0.3, true, nil),
				DropUncommon = sound(0.35, true, nil),
				DropRare = sound(0.4, true, nil),
				DropEpic = sound(0.45, true, nil),
				DropLegendary = sound(0.6, true, nil, "rings"),
				SwitchPrompt = licensed(false, {
					id = "15675037413",
					title = "Roblox_UI_Paper_Swipe",
					creator = "Roblox",
					length = 0.62,
					startAt = 0.05,
					stopAt = 0.34,
					fadeOut = 0.06,
					volume = 0.5,
					pitch = { 1, 1 },
				}, "one swipe early in the 0.8 s Switch window"),
				SwitchLand = licensed(true, {
					id = "9116730789",
					title = "Metallic Beeps Quick Tones 5 (SFX)",
					creator = "ProSoundEffects",
					length = 1.09,
					startAt = 0.12,
					stopAt = 0.45,
					fadeOut = 0.1,
					volume = 0.3,
					pitch = { 1, 1 },
				}, "both trails flash white; it lands inside the hit's stop"),
				LevelUp = sound(0.6, false, nil),
				LowHpHeartbeat = licensed(false, {
					id = "1841124374",
					title = "Heartbeat Pulse",
					creator = "APMOfficial",
					length = 29.21,
					startAt = 0.18,
					stopAt = 1.12,
					fadeOut = 0,
					volume = 0.7,
					pitch = { 1, 1 },
					loop = true,
				}, "loops below 25% HP: one lub-dub, a seamless 64 bpm (MusicState ramps it in and out)"),
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

		-- The beds ride the SFX group on purpose: the death silence ducks them with everything else,
		-- and the impact frames' bass cut takes the world out with the hit (the reel's drop-out).
		ambience = {
			group = "SFX",
			entries = {
				RimWind = licensed(false, {
					id = "9113286782",
					title = "Barstow Wind Light Blustery Low Howl 1 (SFX)",
					creator = "ProSoundEffects",
					length = 11.95,
					startAt = 0.3,
					stopAt = 11.5,
					fadeOut = 0,
					volume = 1,
					pitch = { 1, 1 },
					loop = true,
				}, "everywhere at the rim: a steady light wind bed"),
				Plains = licensed(false, {
					id = "9119383684",
					title = "Sonoma Morning Birds California Chirping 2 (SFX)",
					creator = "ProSoundEffects",
					length = 127.61,
					startAt = 2,
					stopAt = 125,
					fadeOut = 0,
					volume = 0.36,
					pitch = { 1, 1 },
					loop = true,
				}, "birds, high above the hit layers"),
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

	--- Section 15: the moments every archetype has a vocalization for ("enemy.<Archetype><Moment>").
	vocalMoments = VOCAL_MOMENTS,

	--- Layered hits (the reel's 4 to 6 layers on the big moments). Delays are seconds after the
	--- cue: every contact layer starts with the crack (0), and only a beat a frame or more later
	--- (the sub after the final hold, the dodge's landing) waits.
	cues = {
		-- A non-final Art hit (3-frame hit-stop): the crack and the body at the 0 dB reference, the
		-- material just under them, the short ring 7 dB down. With the clip's whoosh before contact
		-- it is five layers; the hit-stop tick is Replication's (2D, for the fighters in the hit).
		HitNormal = {
			{ name = "impact.Crack", delay = 0, gainDb = 0 },
			{ name = "impact.Flesh", delay = 0, gainDb = 0 },
			{ name = "impact.Body", delay = 0, gainDb = 0 },
			{ name = "impact.Ring", delay = 0, gainDb = 0 },
		},
		-- A basic attack's hit: HitNormal with the crack and the body 3 dB down (basics are weak).
		HitBasic = {
			{ name = "impact.Crack", delay = 0, gainDb = -3 },
			{ name = "impact.Flesh", delay = 0, gainDb = 0 },
			{ name = "impact.Body", delay = 0, gainDb = -3 },
			{ name = "impact.Ring", delay = 0, gainDb = 0 },
		},
		-- A crit: the HitNormal stack brighter, not heavier (it never competes with HitFinal): the
		-- crack 2 dB up and the ring 3.5 dB up, both at the top of their pitch ranges.
		HitCrit = {
			{ name = "impact.Crack", delay = 0, gainDb = 2, pitch = CRACK_PITCH[2] },
			{ name = "impact.Flesh", delay = 0, gainDb = 0 },
			{ name = "impact.Body", delay = 0, gainDb = 0 },
			{ name = "impact.Ring", delay = 0, gainDb = 3.5, pitch = RING_PITCH[2] },
		},
		-- An Art's final hit (6 frames): FinalHit's weight in place of the body and the long ring
		-- tail in place of the short ring. FinalHit's contour takes the bass out for the freeze, so
		-- the crack and the ring sit alone in the impact frames; the sub thumps as the bass slams
		-- back (moments.luau's validator holds it to that).
		HitFinal = {
			{ name = "impact.Crack", delay = 0, gainDb = 0 },
			{ name = "impact.FinalHit", delay = 0, gainDb = 0 },
			{ name = "impact.Flesh", delay = 0, gainDb = 0 },
			{ name = "impact.RingTail", delay = 0, gainDb = 0 },
			{ name = "impact.Sub", delay = FINAL_HOLD, gainDb = 0 },
		},
		-- A kill (10 frames): the crack 2 dB up, the kill's weight (the loudest contact layer), the
		-- material 3 dB down, the short ring 3 dB up and the long tail. No body and no sub: the
		-- bass is cut through the kill's impact frames (KillCut), the death silence follows, and
		-- the slam brings it back after (Shatter). The death vocal is the caller's (vocalName).
		HitKill = {
			{ name = "impact.Crack", delay = 0, gainDb = 2 },
			{ name = "impact.Kill", delay = 0, gainDb = 0 },
			{ name = "impact.Flesh", delay = 0, gainDb = -3 },
			{ name = "impact.Ring", delay = 0, gainDb = 3 },
			{ name = "impact.RingTail", delay = 0, gainDb = 0 },
		},
		-- The shatter after the 0.5 s silence: everything starts on the white-flash frame. The slam
		-- (the loudest moment) brings the bass back under the glass crack, the chime rises to its
		-- peak as the crack fades, and the bass dive comes in under it all 3 dB down.
		Shatter = {
			{ name = "shatter.Slam", delay = 0, gainDb = 0 },
			{ name = "shatter.Crack", delay = 0, gainDb = 0 },
			{ name = "shatter.Chime", delay = 0, gainDb = 0 },
			{ name = "impact.SubDrop", delay = 0, gainDb = -3 },
		},
		-- A player's or an Elite's shatter: the Shatter stack with the bass dive at full level, so the
		-- death of someone who matters lands heavier than a mob's (the boss keeps its slow version).
		ShatterHeavy = {
			{ name = "shatter.Slam", delay = 0, gainDb = 0 },
			{ name = "shatter.Crack", delay = 0, gainDb = 0 },
			{ name = "shatter.Chime", delay = 0, gainDb = 0 },
			{ name = "impact.SubDrop", delay = 0, gainDb = 0 },
		},
		-- The boss shatter on its white flash: the slow crack (its own 0.70 to 0.75x range), the
		-- low boom in place of the slam, the chime slowed to its slow version, the full bass dive.
		BossShatter = {
			{ name = "shatter.BossCrack", delay = 0, gainDb = 0 },
			{ name = "shatter.BossBoom", delay = 0, gainDb = 0 },
			{ name = "shatter.Chime", delay = 0, gainDb = 0, pitch = SLOW_CHIME_PITCH },
			{ name = "impact.SubDrop", delay = 0, gainDb = 0 },
		},
		-- A perfect parry: the bright clash and the long ring, started on the same frame. No crack
		-- and no tick, so the clash's highs are not doubled.
		Parry = {
			{ name = "guard.Parry", delay = 0, gainDb = 0 },
			{ name = "guard.ParryRing", delay = 0, gainDb = 0 },
		},
		-- A guarded hit: the dull block alone (low, no ring: never heard as a parry). The hit-stop
		-- tick a guarded hit gets is Replication's.
		Block = {
			{ name = "guard.Block", delay = 0, gainDb = 0 },
		},
		-- A guard break: the crack with the sub 6 dB down under it for the stagger's weight.
		GuardBreak = {
			{ name = "guard.GuardBreak", delay = 0, gainDb = 0 },
			{ name = "impact.Sub", delay = 0, gainDb = -6 },
		},
		-- A dodge: the body whoosh at the step start (its peak about 0.17 s in) and the soft landing
		-- when the step ends.
		Dodge = {
			{ name = "whoosh.Dodge", delay = 0, gainDb = 0 },
			{ name = "footsteps.LandSoft", delay = Combat.dodgeDuration, gainDb = 0 },
		},
	} :: { [string]: { CueLayer } },

	--- Mix automation over time (frequency contrast and the reverb on the big moments).
	contours = {
		-- An Art's final hit: the bass leaves for the 6-frame freeze, then slams back in.
		FinalHit = {
			{ at = 0, group = "SFX", low = -36, ramp = 0.008 },
			{ at = 0, group = "Music", low = -24, ramp = 0.008 },
			{ at = FINAL_HOLD - FINAL_BASS_RAMP, group = "SFX", low = 0, ramp = FINAL_BASS_RAMP },
			{ at = FINAL_HOLD, group = "Music", low = 0, ramp = 0.08 },
		},
		-- A kill: the bass is cut through the 10-frame freeze the kill's impact frames ride in; the
		-- death freeze's duck follows, and the Shatter cue brings everything back.
		KillCut = {
			{ at = 0, group = "SFX", low = -48, ramp = 0.006 },
			{ at = 0, group = "Music", low = -48, ramp = 0.006 },
			{ at = KILL_HOLD, group = "SFX", low = 0, ramp = 0.06 },
			{ at = KILL_HOLD, group = "Music", low = 0, ramp = 0.06 },
		},
		-- The shatter: the slam rings out wet, then dries over about half a second.
		ShatterBloom = {
			{ at = 0, group = "SFX", wet = -3, ramp = 0.01 },
			{ at = 0.1, group = "SFX", wet = -30, ramp = 0.45 },
			{ at = 0.55, group = "SFX", wet = -80, ramp = 0.05 },
		},
		-- The boss shatter: wetter and slower, under its 3 s of shards.
		BossShatterBloom = {
			{ at = 0, group = "SFX", wet = -1, ramp = 0.02 },
			{ at = 0.4, group = "SFX", wet = -30, ramp = 1.6 },
			{ at = 2, group = "SFX", wet = -80, ramp = 0.1 },
		},
		-- A perfect parry: a short reverb pulse under the ring.
		ParryRing = {
			{ at = 0, group = "SFX", wet = -6, ramp = 0.008 },
			{ at = 0.08, group = "SFX", wet = -28, ramp = 0.3 },
			{ at = 0.4, group = "SFX", wet = -80, ramp = 0.05 },
		},
		-- An Art's activation, for the fighter holding it: the highs leave the music while the blade
		-- glows, so the hit lands into space. WindUpRelease brings them back on the first damage
		-- frame (or when the hold is let go); the step at 2 s is only the safety return for a hold
		-- that never resolves (the hold cancels itself at combat.activationCancelTime, 1 s).
		WindUp = {
			{ at = 0, group = "Music", high = -14, ramp = 0.06 },
			{ at = 2, group = "Music", high = 0, ramp = 0.1 },
		},
		-- The first damage frame after the release: the highs are back with the hit.
		WindUpRelease = {
			{ at = 0, group = "Music", high = 0, ramp = 0.03 },
		},
	} :: { [string]: { ContourStep } },

	--- The one EqualizerSoundEffect and one ReverbSoundEffect on each SoundGroup a contour may name.
	--- Idle values: flat EQ, a dry reverb (WetLevel at the engine floor, DryLevel at unity).
	effects = {
		groups = { "Master", "Music", "SFX" },
		equalizer = { name = "ContourEQ", low = 0, mid = 0, high = 0, priority = 2 },
		reverb = {
			name = "ContourReverb",
			wet = -80,
			dry = 0,
			decayTime = 1.6, -- seconds
			density = 0.9,
			diffusion = 0.85,
			priority = 1, -- after the EQ, so a bass cut also leaves the reverb's tail
		},
		easing = "SineInOut", -- every ramp eases (never linear); a step may name its own
		restoreSeconds = 0.05, -- a contour that ends off the defaults, or is replaced, eases back this fast
	},

	--- The property ranges the engine accepts.
	engine = {
		eqGainDb = { min = -80, max = 10 }, -- EqualizerSoundEffect Low / Mid / HighGain
		reverbLevelDb = { min = -80, max = 20 }, -- ReverbSoundEffect WetLevel / DryLevel
		reverbDecaySeconds = { min = 0.1, max = 20 },
		unit = { min = 0, max = 1 }, -- ReverbSoundEffect Density / Diffusion
		soundVolume = { min = 0, max = 10 }, -- Sound.Volume
		-- Sound.PlaybackSpeed the data may ask for: an octave either way. The engine itself takes a
		-- wider range that nobody has measured, so every pitch range and cue pitch stays inside this.
		playbackSpeed = { min = 0.5, max = 2 },
	} :: { [string]: Range },

	--- How SfxPool maps an entry's trim onto its Sound (seconds of the asset, before PlaybackSpeed):
	--- PlaybackRegion = startAt .. the region end, and a loop entry's LoopRegion = startAt .. stopAt.
	playback = {
		-- The PlaybackRegion end for an entry with neither stopAt nor length: past any asset, so
		-- the sound plays to its own end.
		openEndSeconds = 3600,
		-- One frame at 60 fps. A cue layer due sooner than this plays with the cue (a waiting
		-- thread resumes only on a frame, so it would land 17 to 33 ms late); a cue's delays are 0
		-- or at least this.
		sameFrameSeconds = Combat.hitStopFrameSeconds,
	},

	--- What the sfx validator holds entries, cues and contours to.
	limits = {
		cueLayers = { min = 1, max = 6 }, -- a guarded hit is the dull block alone
		hitCueMinLayers = 3, -- a Hit* cue under this is not a stack (the reel's big hits are 4 to 6)
		cueDelaySeconds = 1, -- every layer starts under this after its cue
		layerGainDb = { min = -30, max = 6 }, -- quieter is inaudible under the stack; louder clips it
		-- No play ends above this volume: the picks' volumes are set against the 0 dB reference
		-- (peak x volume of 200), and a cue's gain only moves a layer inside that scale.
		maxPlayVolume = 1,
		-- A loop region shorter than this buzzes instead of looping (seconds of the asset).
		loopMinSeconds = 0.5,
		contourSeconds = 4, -- every contour step ends (at + ramp) inside this
		-- The sub-bass layers: where a moment pairs a cue with a contour (moments.luau), each of
		-- these layers starts with its group's low band back to at least bassBackDb, so the bass
		-- slams back on the hit instead of swelling in under the cut (the moments validator).
		subLayers = { "impact.Sub", "impact.SubDrop", "shatter.BossBoom" },
		bassBackDb = -3,
		-- Slots that share one asset (the reuses) keep their pitch ranges at least this far apart,
		-- so each still reads as its own sound.
		sharedAssetSemitones = 1,
	},

	--- Entries SfxPool.start() creates the voices of and preloads, on top of every cue's layers and
	--- the impact, hitStopTick and guard families: every Phase 0 one-shot played outside those,
	--- and the death vocals the kill's caller is about to play. A riser is placed by its length
	--- (it must end on the hit), and a first play whose asset is still loading starts late with no
	--- fade, so each has to be loaded before its first play.
	preload = {
		"whoosh.Riser",
		"whoosh.Small",
		"whoosh.Medium",
		"whoosh.Large",
		"whoosh.Basic",
		"artChime.TrailCyanWhite",
		"telegraph.Unblockable",
		"telegraph.GuardBreak",
		"ui.SwitchPrompt",
		"ui.SwitchLand",
		"ui.SystemLine",
		"footsteps.GrassLight",
		"footsteps.StoneLight",
		"footsteps.LandHard",
		"enemy.ChargerSnort",
		"enemy.ChargerWindUp",
		"enemy.ChargerStrike",
		"enemy.ChargerStagger",
		"enemy.ChargerDeath",
		"enemy.BruteRoar",
		"enemy.BruteWindUp",
		"enemy.BruteStrike",
		"enemy.BruteStagger",
		"enemy.BruteDeath",
	},

	--- The cue SfxPool.shatter plays by the caller's weight (Shatter.luau calls it): a mob's
	--- normal, a player's or an Elite's heavy, a boss's boss. The reverb bloom is not part of it:
	--- a contour colors the whole SFX group, so the impact director fires ShatterBloom only for a
	--- death near the camera (moments.luau `Death` / `BossDeath`).
	shatterCues = { normal = "Shatter", heavy = "ShatterHeavy", boss = "BossShatter" },
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
type Row = { family: string, name: string, entry: Entry }

function Sfx.all(): { Row }
	local list: { Row } = {}
	for family, group in Sfx.families do
		for name, entry in group.entries do
			table.insert(list, { family = family, name = name, entry = entry })
		end
	end
	table.sort(list, function(a: Row, b: Row): boolean
		if a.family == b.family then
			return a.name < b.name
		end
		return a.family < b.family
	end)
	return list
end

--- A cue's layers by name; errors on an unknown cue so a bad moment fails loudly.
function Sfx.cue(name: string): { CueLayer }
	local layers = Sfx.cues[name]
	if layers == nil then
		error(("sfx: unknown cue '%s'"):format(tostring(name)))
	end
	return layers
end

--- A contour's steps by name; errors on an unknown contour.
function Sfx.contour(name: string): { ContourStep }
	local steps = Sfx.contours[name]
	if steps == nil then
		error(("sfx: unknown contour '%s'"):format(tostring(name)))
	end
	return steps
end

local function sortedKeys(map: { [string]: any }): { string }
	local names = {}
	for name in map do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--- Every cue name, sorted.
function Sfx.cueNames(): { string }
	return sortedKeys(Sfx.cues)
end

--- Every contour name, sorted.
function Sfx.contourNames(): { string }
	return sortedKeys(Sfx.contours)
end

--- The amplitude multiplier for a gain in dB (+6 dB is about 2x, -6 dB about 0.5x).
function Sfx.gainOf(db: number): number
	return 10 ^ (db / 20) -- unit: decibels to amplitude
end

--- The SoundGroup a family routes to.
function Sfx.groupOf(family: string): string
	local group = Sfx.families[family]
	if group == nil then
		error(("sfx: unknown family '%s'"):format(tostring(family)))
	end
	return group.group
end

--- An entry's audible part in seconds of the asset (before PlaybackSpeed): startAt (0 when nil) to stopAt, else its length, else playback.openEndSeconds.
function Sfx.region(entry: Entry): (number, number)
	local first = entry.startAt or 0
	local last = entry.stopAt or entry.length or Sfx.playback.openEndSeconds
	return first, last
end

--- Real seconds from Play to an entry's peak at the middle of its pitch range: (peakAt - startAt) / PlaybackSpeed; nil without a peakAt.
function Sfx.peakLead(entry: Entry): number?
	local peakAt = entry.peakAt
	if peakAt == nil then
		return nil
	end
	local range = entry.pitchRange
	local speed = if range ~= nil then (range[1] + range[2]) / 2 else 1
	return (peakAt - (entry.startAt or 0)) / speed
end

--- True for a sound from the library (a real asset id); false for a placeholder.
function Sfx.isReal(entry: Entry): boolean
	return not entry.placeholder and entry.id ~= PLACEHOLDER
end

--- The "family.Name" of an archetype's vocalization ("Charger", "Death" -> "enemy.ChargerDeath"); errors when there is none.
function Sfx.vocalName(archetype: string, moment: string): string
	Sfx.get("enemy", archetype .. moment)
	return "enemy." .. archetype .. moment
end

return Sfx
