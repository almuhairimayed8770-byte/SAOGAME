--!strict
--[[
	FX tunables (section 11): budgets, trails, the activation light, outlines, the shatter, the
	parry sparks, telegraphs, the Switch ring, floating digits, quality tiers, the cloud billboards
	and the client audio pool. Every number the fx / audio packages use lives here; the modules under
	src/client/fx and src/client/audio hold none.

	Units: studs, seconds, degrees, fractions 0..1. Frames are 60 fps frames and convert through
	combat.hitStopFrameSeconds. Colors are palette tokens, never hex.
]]

local Combat = require(script.Parent.combat)
local Choreo = require(script.Parent.choreo)

export type QualityTier = {
	particleScale: number, -- multiplier on every particle count
	shardScale: number, -- multiplier on shard counts
	outlineDistance: number, -- studs; Highlights beyond this are dropped unless important
	trailDistance: number, -- studs; trails on rigs beyond this stay disabled
	maxTrails: number, -- concurrent Trail instances enabled
	maxLiveShards: number, -- shards animated at once across every shatter
	shatterPoolSize: number, -- pre-warmed WedgeParts in ReplicatedStorage
	groundDecals: boolean, -- telegraph ground decals drawn at all
	cloudBillboards: number, -- cloud billboards below the rim
	nameplateHz: number, -- nameplate fade / hover updates per second
}

local Fx = {
	-- Section 11 per-scene budgets. Highlights is the engine's hard cap (31 rendered at once).
	budgets = {
		highlights = 31,
		particles = 400,
		trails = 20,
		parts = 60000,
		drawCalls = 1500,
	},

	-- The player attribute the settings menu writes (Quality.luau reads it; "High" | "Medium" | "Low").
	qualityAttribute = "SettingQuality",
	qualityDefaultDesktop = "High",
	qualityDefaultTouch = "Medium",

	-- Weapon trails (section 10): width from the weapon data, lifetime 0.18 s, LightEmission 1.
	trail = {
		lifetime = 0.18,
		lightEmission = 1,
		minLength = 0.05, -- Trail.MinLength; below this no segment is emitted
		-- Width multipliers on the weapon's trailWidth per activation kind.
		width = { Art = 1.0, Basic = 0.55, Smear = 1.0 },
		-- How far a Basic trail's color moves toward TrailWhite (thinner and whiter, section 10).
		basicWhiteBlend = 0.65,
		-- Width keypoints along the trail (head -> tail) and transparency keypoints.
		widthKeys = { { 0, 1 }, { 0.7, 0.8 }, { 1, 0.25 } },
		transparencyKeys = { { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } },
		defaultWidth = 0.9, -- studs when a rig has no weapon def or TrailWidth attribute
		enemyWidth = 0.8, -- placeholder enemy weapons
		defaultToken = "TrailCyanWhite",
		enemyToken = "TrailWhite",
		flashToken = "TrailWhite", -- Switch landing / parry flash color
		-- Attribute names a WeaponBuilder may write on the Weapon part to override the data lookup.
		widthAttribute = "TrailWidth",
		colorAttribute = "TrailColor",
		-- Placeholder attachments when a weapon part lacks TrailStart / TrailEnd: fractions of the
		-- part's long axis from its center (guard near the grip, tip at the end).
		placeholderStart = -0.35,
		placeholderEnd = 0.5,
		textureAsset = "TrailGradient",
		rankInterval = 0.25, -- seconds between budget re-ranks (farthest disabled first)
	},

	-- Art activation (section 11): a PointLight on the blade and a flash on the weapon's Highlight.
	activationLight = {
		range = 8,
		brightness = 2,
		flashFrames = 3,
		flashToken = "SystemWhite",
		-- The flash is a Highlight of the weapon part alone (Trails names it flashName), never the
		-- body's outline: a whole white body reads as being hit (issue 5). It draws no outline (the
		-- rig's own Highlight owns that) and takes a slot of the Highlight budget while it shows.
		flashName = "ActivationFlash",
		flashFillTransparency = 0.1,
		flashOutlineTransparency = 1,
		-- A cancelled Art's blade light fades out over this instead of cutting off in a frame
		-- (issue 13); a released Art's goes out on its first damage frame, as the cut takes over.
		cancelFadeSeconds = 0.2,
		cancelFadeEasing = "QuadOut",
	},

	-- Smear (section 10 beat 3): the weapon part scaled along the swing axis for the smear frames.
	smear = {
		scale = Choreo.smearScale,
		frames = Choreo.smearFrames,
		defaultAxis = "X",
	},

	-- Outlines (section 11): one Highlight per fighter, near-black outline from the base color.
	outline = {
		outlineTransparency = 0,
		fillTransparency = 1,
		inkBlend = 0.78, -- how far the base color moves toward OutlineInk for the outline
		distance = 120, -- studs (overridden per quality tier)
		budget = 31,
		rerankInterval = 0.25, -- seconds
		-- Lower ranks win the budget; Boss / Lock / Party are always on regardless of distance.
		importanceRank = { Boss = 0, Lock = 1, Party = 2, Normal = 3 },
		alwaysOn = { Boss = true, Lock = true, Party = true },
		flashFillTransparency = 0.1, -- fill while a flash is on
		flashFrames = Combat.highlightFlashFrames,
		depthMode = "Occluded",
		basePartNames = { "UpperTorso", "Torso", "HumanoidRootPart" }, -- where the base color is read, in order
	},

	-- The shatter (section 11): one effect for every death.
	shatter = {
		shards = { min = 40, max = 80, boss = 300 },
		duration = 0.8,
		bossDuration = 3,
		rise = 6,
		bossRise = 9,
		shardSize = { min = 0.3, max = 0.85 },
		bossShardSize = { min = 0.5, max = 1.6 },
		shardAspect = { min = 0.5, max = 1 }, -- X and Z extents as a fraction of a shard's base size
		outwardSpeed = { min = 2.5, max = 7 }, -- studs per second at t = 0
		upwardBias = 0.35, -- fraction of the outward direction tilted up
		drag = 2.2, -- per second; outward speed decays exponentially
		rotationSpeed = { min = 60, max = 200 }, -- degrees per second
		shrinkEnd = 0.08, -- final scale fraction
		fadeStart = 0.35, -- fraction of the life where transparency begins to rise
		riseEasing = "QuadOut",
		fallbackLimbSize = 2, -- studs; the stand-in limb for a rig with no visible parts
		limbJitter = 0.6, -- fraction of a limb's half-size the spawn point is scattered by
		hiddenTransparency = 1,
		flash = {
			particles = 28,
			size = 5,
			lifetime = 0.28,
			speed = 4,
			bossParticles = 80,
			bossSize = 14,
			token = "SystemWhite",
		},
		colors = {
			Beast = "ShardBlue",
			Humanoid = "ShardBlue",
			Boss = "ShardBlue",
			Construct = "ShatterSilver",
			Plant = "ShatterGreenGold",
		},
		bossCameraPullBack = 10, -- studs the camera eases back for a boss shatter
		poolFolderName = "ShatterPool",
		preWarmPerFrame = 40, -- shards created per frame while pre-warming (never a hitch)
	},

	-- Perfect parry (section 6): a spark burst beside the metallic ring, from one pooled emitter.
	parrySpark = {
		particles = 26, -- per burst before the quality tier's particleScale
		size = 0.3, -- studs at birth; each spark shrinks to nothing
		lifetime = { min = 0.12, max = 0.3 }, -- seconds
		speed = { min = 16, max = 34 }, -- studs per second at birth
		spreadAngle = 180, -- degrees on both axes: sparks fly every way from the clash
		drag = 7, -- per second; the burst snaps out and stalls
		gravity = 40, -- studs per second squared pulling the sparks down
		lightEmission = 1,
		token = "TrailWhite", -- the hot core at birth
		tailToken = "TrailAmber", -- the color a spark cools to as it fades
		orientation = "VelocityParallel", -- Enum.ParticleOrientation: sparks streak along their flight
		emitterSize = 0.2, -- studs; the invisible anchored part the burst leaves from
		folderName = "ParrySparks", -- the workspace folder that holds the pooled emitter part
	},

	-- Telegraphs (section 11): Highlight fill on the weapon plus a flat ground decal.
	telegraph = {
		fillToken = { Normal = "TelegraphWhite", Unblockable = "TelegraphRed", GuardBreak = "TelegraphYellow" },
		fillTransparency = 0.2, -- at full intensity
		outlineTransparency = 1, -- the telegraph Highlight draws no outline (OutlineManager owns it)
		fadeInFraction = 0.35, -- of the wind-up; the decal and fill ramp in over this
		pulseHz = 3, -- a soft pulse of the fill in the last part of the wind-up
		pulseDepth = 0.15,
		pulseFromFraction = 0.7, -- of the wind-up
		decal = {
			alpha = 0.55, -- peak opacity of the ground decal at full intensity
			thickness = 0.12, -- studs; the flat part's height
			groundOffset = 0.06, -- studs above the ground
			lineMinWidth = 1.5,
			coneSlices = 7, -- flat parts fanned to draw an arc
			coneOverlap = 1.15, -- slice width multiplier so the fan has no gaps
			circleSegments = 1, -- a circle is one cylinder part
			poolSize = 24,
			defaultShape = { kind = "Cone", length = 8, width = 60 },
			textureAssets = { Line = "TelegraphLine", Cone = "TelegraphCone", Circle = "TelegraphCircle" },
		},
		sounds = {
			Normal = "telegraph.Tick",
			Unblockable = "telegraph.Unblockable",
			GuardBreak = "telegraph.GuardBreak",
		},
		intensityMin = 0.5, -- the accessibility slider's floor: still visible
	},

	-- Switch window (section 11): a thin SystemCyan ring expanding from the hit point.
	switchRing = {
		token = "SystemCyan",
		radiusStart = 0.8,
		radiusEnd = 7,
		thickness = 0.22,
		height = 0.1,
		segments = 28,
		segmentOverlap = 1.2,
		easing = "QuadOut",
		fadeStartFraction = 0.55,
		poolSize = 3, -- concurrent rings (each uses `segments` parts)
	},

	-- Floating digits (section 14): the real number, 0.6 s fade, rise 2.5 studs.
	digits = {
		rise = Combat.digitRise,
		fadeTime = Combat.digitFadeTime,
		riseEasing = "QuadOut",
		fadeStartFraction = 0.45,
		textSize = { Normal = 18, Crit = 26, Switch = 22, Taken = 20 },
		tokens = { Normal = "DigitWhite", Crit = "DigitYellow", Switch = "DigitCyan", Taken = "DigitRed" },
		strokeTransparency = 0.4,
		spread = 0.7, -- studs of random horizontal jitter so stacked numbers separate
		startHeight = 1.5, -- studs above the hit point
		poolSize = 32,
		maxDistance = 140,
		billboardSize = { width = 120, height = 40 }, -- pixels
		punchScale = 1.35, -- the number starts large and settles (overshoot, never linear)
		punchTime = 0.12,
	},

	-- Quality tiers (section 11). Every FX module reads its tier through Quality.get().
	quality = {
		High = {
			particleScale = 1,
			shardScale = 1,
			outlineDistance = 120,
			trailDistance = 120,
			maxTrails = 20,
			maxLiveShards = 700,
			shatterPoolSize = 420,
			groundDecals = true,
			cloudBillboards = 24,
			nameplateHz = 30,
		},
		Medium = {
			particleScale = 0.6,
			shardScale = 0.6,
			outlineDistance = 90,
			trailDistance = 80,
			maxTrails = 12,
			maxLiveShards = 360,
			shatterPoolSize = 240,
			groundDecals = true,
			cloudBillboards = 16,
			nameplateHz = 20,
		},
		Low = {
			particleScale = 0.3,
			shardScale = 0.35,
			outlineDistance = 60,
			trailDistance = 50,
			maxTrails = 6,
			maxLiveShards = 160,
			shatterPoolSize = 120,
			groundDecals = true,
			cloudBillboards = 8,
			nameplateHz = 12,
		},
	} :: { [string]: QualityTier },

	-- Cloud billboards below the rim (section 11): counts per tier live in `quality`; these shape them.
	clouds = {
		driftStudsPerSecond = 1.5,
		sizeJitter = 0.3, -- fraction of the base size
		transparency = 0.35,
	},

	-- Client audio pool (section 15 numbers that are the pool's, not the sound list's).
	audio = {
		groupVolumes = { Master = 1, Music = 0.7, SFX = 1, UI = 0.85, Voice = 1 },
		-- The death silence's carve-out (issue 9): a SoundGroup beside SFX under Master, at SFX's
		-- level and slider, that no duck lowers. While a death's silence holds, the local player's
		-- own SFX (their clip sounds, footsteps, dodge, guard and the hits they are in, marked with
		-- SfxPool.asOwn) start in it, so the swing and the hit after the kill are heard at full
		-- while the music, the beds, the other fighters and the UI stay down.
		ownGroupName = "OwnSFX",
		dedupeSeconds = 0.03, -- the same sound at the same spot inside this window plays once
		-- studs; wide enough that the death reaction's crack (at the server's death position) and
		-- the shatter's crack (at the client's rig, which may trail a charging rig by a few studs)
		-- are one sound
		dedupeDistance = 6,
		emitterFolderName = "FxAudio",
		emitterPoolSize = 24,
		emitterReleaseDelay = 0.1, -- seconds after a sound ends before its emitter returns
		maxSoundLength = 8, -- seconds a one-shot may hold a voice before it is reclaimed
		heartbeatLoop = "ui.LowHpHeartbeat",
		heartbeatRampSeconds = 1.5,
		stemFadeFloor = 0.001, -- volumes below this are zero (stems are then paused)
		materialSurface = { -- Enum.Material name -> footstep surface in sfx.luau
			Grass = "Grass",
			LeafyGrass = "Grass",
			Mud = "Grass",
			Ground = "Gravel",
			Sand = "Gravel",
			Pebble = "Gravel",
			Snow = "Snow",
			Ice = "Snow",
			Glacier = "Snow",
			Water = "Water",
			Wood = "Wood",
			WoodPlanks = "Wood",
			Fabric = "Wood",
		},
		defaultSurface = "Stone",
		armoredAttribute = "Armored", -- a character attribute the server writes for heavy sets
		-- The world beds (section 15: wind at the rim everywhere, an ambience per biome), played by
		-- Ambience.luau through SfxPool.loop. On the Playground island (playground.luau fieldRadius
		-- around the field center) the bed plays and the rim wind rises as the local character nears
		-- the edge; off the island, or with no character, both ramp out and stop.
		ambience = {
			bed = "ambience.Plains", -- the Playground's biome bed
			rimWind = "ambience.RimWind",
			rampSeconds = 2, -- a bed's gain moves all the way (0 to 1, or back) over this
			sampleHz = 10, -- reads per second of the character's distance to the island's edge
			-- Studs inside the edge: the full rim wind at `near` or closer, `rimFloor` at `far` or farther.
			rimBand = { near = 15, far = 140 },
			rimFloor = 0.2, -- the rim wind's gain deep inside the island: faint, never gone
			rimEasing = "QuadIn", -- the wind rises slowly at first and fastest near the edge
		},
	},
}

return Fx
