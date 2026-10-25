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
		-- The ribbon (D-261): the trail drawn from sub-frame blade samples, so a cut that sweeps most
		-- of its arc between two rendered frames still draws that arc (the engine Trail takes one
		-- sample a frame, and drew a straight chord or slab: review issue 8). Every rendered frame
		-- the blade is solved by forward kinematics (BladeContact.blade) at sub-steps between the
		-- last frame's pose and this one, each moving the tip at most `maxStep` studs (at most
		-- `maxSubsteps` a frame); a step that moves the tip less than minLength adds nothing. The
		-- ribbon keeps `maxSamples` samples, each living `lifetime`; the ages stand still while the
		-- rig is in hit-stop, so the cut holds through the freeze. A rig with no blade chain keeps
		-- the engine Trail.
		ribbon = {
			maxStep = 0.3,
			maxSubsteps = 8,
			maxSamples = 48,
			-- The body's width: the weapon's trailWidth x the kind's width x this, so a one-handed
			-- sword's band covers most of its 3.2-stud blade (thick, not the thin engine strip).
			thickness = 2.4,
			-- The trail color's HSV saturation is multiplied by this (at most 1): the pale trail
			-- tokens read as white over a bright sky; the ribbon wears their hue at full strength.
			saturation = 2.6,
			folderName = "SkyspireTrailRibbons",
			hostSize = 0.2,
			-- Built once: a layer's transparency snaps to this many steps.
			transparencySteps = 20,
			-- Each layer is a chain of camera-facing Beams through one point of the blade
			-- (`fraction` of the way from guard to tip), `width` times the body's width, the
			-- saturated color lerped to SystemWhite by `whiteBlend`. lightEmission 0 draws flat
			-- color (it holds over a bright sky); the core glows. Transparency keys run over age.
			layers = {
				{
					name = "Body",
					fraction = 0.6,
					width = 1,
					whiteBlend = 0,
					lightEmission = 0,
					zOffset = 0,
					transparencyKeys = { { 0, 0.05 }, { 0.6, 0.25 }, { 1, 1 } },
				},
				{
					name = "Core",
					fraction = 0.92,
					width = 0.22,
					whiteBlend = 0.8,
					lightEmission = 1,
					zOffset = 0.05,
					transparencyKeys = { { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } },
				},
			},
		},
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
		-- The blade's own glow while the activation holds (F13, D-263; section 5: "the blade glows
		-- in the Art's color"): the light alone moved the lit blade only from about 173/198/217 to
		-- 183/215/228 in daylight. Camera-facing Beams from TrailStart to TrailEnd (Trails names
		-- them name .. layer name), in the light's color at the ribbon's saturation lerped to
		-- SystemWhite by `whiteBlend`, unlit (LightInfluence 0) so the sun cannot wash them out,
		-- `width` studs wide (the body over twice the blade's 0.32), on from the activation to the
		-- first damage frame; a cancelled Art's fades with its light.
		glow = {
			name = "ActivationGlow",
			layers = {
				{
					name = "Body",
					width = 0.75,
					whiteBlend = 0.1,
					lightEmission = 0,
					transparency = 0.15,
					zOffset = 0.1,
				},
				{ name = "Core", width = 0.22, whiteBlend = 0.8, lightEmission = 1, transparency = 0, zOffset = 0.15 },
			},
		},
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

	-- A rush's slam on a wall (D-217): a puff of dust thrown off the face where the snout meets it,
	-- the stone thud (sfx.cues[cue]) and, near the local player, a short shake. Dust is lit by the
	-- scene and never glows (lightEmission 0), so a slam is no flash: it charges nothing against
	-- the flash budget and plays the same with Reduce flashing on.
	wallSlam = {
		particles = 18, -- per slam before the quality tier's particleScale
		size = { birth = 1.2, death = 3.6 }, -- studs: each puff billows as it fades
		transparency = { birth = 0.35, death = 1 }, -- soft at birth, gone by the end of its life
		lifetime = { min = 0.45, max = 0.9 }, -- seconds
		speed = { min = 8, max = 18 }, -- studs per second at birth, off the face
		spreadAngle = 70, -- degrees off the face's normal on both axes: the dust fans out along it
		drag = 6, -- per second; the puff bursts out and hangs
		gravity = 3, -- studs per second squared: the dust settles slowly
		rotation = 180, -- degrees; each puff starts at a random turn within this either way
		rotSpeed = 90, -- degrees per second; each puff turns at a random rate within this either way
		lightEmission = 0, -- dust, never light: a glow here would be a flash outside the budget
		token = "ShatterSilver", -- a pale stone grey
		emitterSize = 0.2, -- studs; the invisible anchored part the burst leaves from
		folderName = "WallSlamDust", -- the workspace folder that holds the pooled emitter part
		cue = "WallSlam", -- sfx.cues: the stone hit, the body's weight and the sub
		-- The shake of a near slam: a camera.luau shake amplitude (combat.cameraShakeStuds tier).
		-- Studio: from behind the boar at 20 studs the Normal tier (0.15) could not be told from the
		-- lock camera's ease (0.34 to 0.38 studs a frame). The Kill tier moves the camera 0.41, 0.66,
		-- 0.52 and 0.42 studs on its first four frames on average (Normal: 0.17 at most) and less
		-- than 0.1 by the tenth: a short, sharp hit.
		shakeTier = "Kill",
		-- Studs from the local player's body to the contact inside which a slam shakes the camera:
		-- the review's 20 studs behind the root plus the boar's snout (5.6 ahead of it) fits, with
		-- room; 24 left that player out, so the shake never fired there.
		shakeRadius = 32,
		-- The shake's falloff (CameraMath.falloff): full up to this many studs from the contact,
		-- fading smoothly to nothing at shakeRadius, so a slam just inside the radius no longer
		-- shakes as hard as one at the player's feet. The review's 25.6 studs keep it all: from
		-- there the shake only just reads over the lock camera's ease.
		shakeFullRadius = 26,
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
		-- The parry glint (D-CP1): a blow's tell (fill and ground) goes glintToken for glintFrames
		-- frames, the fill at ai.luau telegraph.glintFillTransparency and the ground at
		-- glintDecalAlpha, then back to its kind's color until the snap. The glint is centred on the
		-- middle of the parry window (combat.luau parryWindow before the blow lands), glintAimFrames
		-- earlier: a press is read a frame or two after the frame that showed it, and the server reads
		-- it on its next frame. Three frames is as long as it can be with a press at its first frame
		-- and at its last both inside the window on Studio's link and a live one (D-CP1 margins: 18 ms
		-- each side; four frames leave 2). Only the kinds in glintKinds glint: an Unblockable blow
		-- cannot be parried (section 6), so it never shows the cue to press (D-CP2).
		glintFrames = 3,
		glintAimFrames = 1,
		glintToken = "TelegraphWhite",
		glintDecalAlpha = 0.9,
		glintKinds = { Normal = true, GuardBreak = true } :: { [string]: boolean },
		-- The glint comes this client's one-way latency early (D-289): the server judges a parry on
		-- when the press reaches it, so a press at the glint must leave that much before the window.
		-- The latency is the least lateness (lateBy) of the last glintLeadSamples tells heard (jitter
		-- only adds to it), and the shift never passes glintLeadMax seconds: a path slower than that
		-- glints at the cap and parries a little late. Client only; the server is unchanged.
		glintLeadMax = 0.15,
		glintLeadSamples = 8,
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

	-- Where the effects that read a rig's pose run in the frame (D-211): an Enum.RenderPriority
	-- name and an offset from its value, after the rigs, the character and the camera
	-- (choreo.luau and camera.luau renderOrder), so they read the pose, the root and the view
	-- this frame draws, in the same order on every machine. The steps stay bound (FrameOrder).
	renderOrder = {
		-- The impact picture (impact.luau overlay.renderStepName): the camera and the frozen bodies
		-- copied into its figures, and a picture played at the contact counted from that frame (303).
		impactFrames = { base = "Character", offset = 3 },
		-- The pose readers (SkyspirePoseReaders): Trails samples every blade tip where it is drawn (304).
		poseReaders = { base = "Character", offset = 4 },
	},
}

return Fx
