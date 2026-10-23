--!strict
--[[
	Impact frames (the reel style on top of section 10 beat 4): on the biggest hits the picture
	turns for a few frames into flat silhouettes of the fighters on a solid field, the anime's
	impact frames. Every number ImpactFrames, ImpactSequence and FlashBudget use lives here.

	Units: frames are 60 fps frames and convert through combat.hitStopFrameSeconds; seconds;
	screen fractions; degrees; relative luminance (0 black .. 1 white). Colors are palette tokens,
	never hex.

	Flash safety is a hard limit, not a tunable: full-screen flashes never exceed 3 in any
	1-second window (tools/validators/impact.luau fails a table that allows more). A flash is a
	pair of opposing changes in relative luminance of at least flash.transitionDelta (the WCAG
	general-flash rule). ImpactSequence measures every look's regions (the field, the figures,
	the strokes) from their palette colors, so a sequence that strobes any of them is costed. The
	"Reduce flashing" setting swaps every impact sequence for the soft dim in `reduced`, which is
	charged to the same budget when its dip is itself a flash.
]]

local Combat = require(script.Parent.combat)

-- One full-screen picture. `figures` is the palette token the rigs' silhouettes take (nil draws
-- no figures); `strokes` lays the ink brush strokes across the hit. The flash count reads the
-- relative luminance of each region's token (ImpactSequence.regionsOf).
export type Look = {
	background: string,
	figures: string?,
	strokes: boolean,
}

export type Step = { look: string, frames: number }

-- A sequence rides on a hit-stop tier (combat.hitStopFrames) and must fit inside it: the rigs are
-- frozen while it shows, so the silhouettes hold the pose of the hit. One first drawn late (a
-- stall, D-122) runs past that hit-stop, and from there its figures keep the last frozen frame
-- instead of following the rigs. `rank` orders sequences that
-- land on top of each other: a higher rank replaces the one showing, a lower or equal one joins
-- it (its rigs are drawn too) and is never charged.
export type Sequence = { tier: string, rank: number, steps: { Step } }

export type Range = { min: number, max: number }

export type QualityRow = {
	silhouettes: boolean, -- clone the rigs into the overlay
	strokes: boolean, -- the Ink look's brush strokes
	maxPartsPerRig: number, -- the largest parts of each rig the silhouette draws
}

local Impact = {
	-- Seconds per frame (the same 60 fps frame as hit-stop).
	frameSeconds = Combat.hitStopFrameSeconds,

	looks = {
		-- The black beat before a big hit: nothing but ink.
		Black = { background = "OutlineInk", figures = nil, strokes = false },
		-- The reel's white figure on black.
		Dark = { background = "OutlineInk", figures = "SystemWhite", strokes = false },
		-- The inverse: ink figures on white.
		Light = { background = "SystemWhite", figures = "OutlineInk", strokes = false },
		-- White paper, ink figures, and tapered brush strokes along the slash.
		Ink = { background = "SystemWhite", figures = "OutlineInk", strokes = true },
		-- The reel's pale fighter on a teal sky, in the system cyan: the parry frame.
		Inverted = { background = "SystemCyan", figures = "SystemWhite", strokes = false },
	} :: { [string]: Look },

	sequences = {
		-- An Art's final hit (6-frame hit-stop): two frames of white figures on black.
		Final = { tier = "Final", rank = 2, steps = { { look = "Dark", frames = 2 } } },
		-- A kill (10-frame hit-stop): a black beat, then 4 impact frames (the reel's "3 to 4"): the
		-- figures, then the ink strokes.
		Kill = {
			tier = "Kill",
			rank = 3,
			steps = {
				{ look = "Black", frames = 2 },
				{ look = "Dark", frames = 2 },
				{ look = "Ink", frames = 2 },
			},
		},
		-- A perfect parry rides the normal 3-frame hit-stop: one inverted frame.
		Parry = { tier = "Normal", rank = 1, steps = { { look = "Inverted", frames = 1 } } },
	} :: { [string]: Sequence },

	-- The rolling flash budget (the common photosensitivity limit: 3 flashes in any second).
	-- A flash is a pair of opposing luminance transitions; ImpactSequence.flashCost counts them in
	-- each region. A cost counts until one window after the last change its picture makes (the
	-- overlay's end), not after its start.
	flash = {
		windowSeconds = 1,
		maxPerWindow = 3,
		-- A transition is a change of at least this much relative luminance (10% of the maximum,
		-- the WCAG 2.x general-flash rule); the validator never lets it rise above 0.1.
		transitionDelta = 0.1,
		-- Relative luminance of an sRGB palette color (WCAG 2.x): each channel is linearised
		-- (c / linearDivisor below linearBelow, else ((c + offset) / divisor) ^ gamma), then
		-- weighted red, green, blue.
		luminance = {
			weights = { 0.2126, 0.7152, 0.0722 },
			linearBelow = 0.04045,
			linearDivisor = 12.92,
			offset = 0.055,
			divisor = 1.055,
			gamma = 2.4,
		},
	},

	-- The soft dim that replaces an impact sequence when the budget says no or the setting is
	-- on: OutlineInk at a low opacity, eased in over a few frames and out over more, never an
	-- instant full-screen change. On a bright scene its dip is itself a general flash (the
	-- validator measures it over `referenceScene` with the UI's sRGB blend), so each dim onset is
	-- charged `flashCost` from the same budget and nothing shows when that is refused. A dim asked
	-- for while one rises or holds keeps it at the peak instead of fading out and in again.
	reduced = {
		token = "OutlineInk",
		opacity = 0.3, -- peak opacity (BackgroundTransparency 0.7)
		fadeInFrames = 3,
		holdFrames = 3, -- the peak sits on the hit-stop
		fadeOutFrames = 12,
		fadeInEasing = "SineInOut",
		fadeOutEasing = "SineInOut",
		flashCost = 1, -- one down-and-up pair
		referenceScene = "TrailWhite", -- the brightest scene the dim can fall on (pure white)
		-- With Reduce flashing on, at most this many dims in any flash window (counted, like the
		-- budget, until a window after each one's end): the setting means fewer flashes, never
		-- the full budget of soft ones. A hit asked for past it shows nothing; one landing while a
		-- dim rises or holds still keeps that dim at its peak.
		maxPerWindow = 1,
	},

	-- The local player's boolean attribute the settings menu writes (FlashBudget reads it).
	reduceFlashingAttribute = "SettingReduceFlashing",
	reduceFlashingDefault = false,

	-- The pooled ScreenGui under PlayerGui. Above the HUD (ui.hud 10) and the system line (20),
	-- below the dev capture panels (dev.luau 40 / 50) so gate-clip prompts stay readable.
	overlay = {
		screenGuiName = "SkyspireImpact",
		displayOrder = 30,
		renderStepName = "SkyspireImpactFrames", -- bound after the camera's step
		zIndex = { background = 1, figures = 2, strokes = 3 },
		-- No number of its own for how long a picture waits for its first drawn frame (D-122):
		-- a sequence waits as long as the hit-stop it rides on (combat.hitStopFrames[tier]; the
		-- world is frozen for all of it, so a first frame anywhere inside it still shows the
		-- frozen moment) and the soft dim as long as its own length (past it nothing of the dim
		-- would show). Later, it is dropped, never started, and the Heartbeat watchdog ends it
		-- while nothing renders. The validator keeps every hit-stop a sequence rides on at least
		-- 2 frames, so a 30 fps first frame always plays.
	},

	-- The ViewportFrame lights every clone flat: white ambient, no directional light, so the
	-- look's ImageColor3 alone sets the silhouette color. TrailWhite is the palette's pure white.
	viewport = {
		ambientToken = "TrailWhite",
		lightToken = "OutlineInk",
		cameraName = "ImpactCamera",
	},

	-- The rigs' silhouettes: each visible BasePart is cloned once per play (or taken back from
	-- the pool), stripped to its bare mesh, and made flat white SmoothPlastic.
	silhouette = {
		flatToken = "TrailWhite",
		material = "SmoothPlastic",
		hiddenTransparency = 1, -- parts at or above this transparency are left out
		-- A part named one of these, or any part under a model or folder named one of these, is
		-- left out: the root, the sheath and FX parts. The sword is part of the figure, as in the
		-- anime's impact frames, drawn at its rest size: the smear's stretch (section 10 beat 3)
		-- may still be on while hit-stop freezes the snap, and the figure never shows it.
		excludeNames = { "HumanoidRootPart", "Sheath", "FX" },
		-- Layered clothing (a part with a WrapLayer) only fits the body through the engine's
		-- deformation, which a lone clone does not get: its raw cage would break the outline.
		skipWrapLayers = true,
		maxRigs = 4, -- rigs drawn per play (rigs of hits that join a showing sequence count too)
		poolCap = 96, -- idle clones kept for the next play; the oldest past this are destroyed
	},

	-- The Ink look's brush strokes: OutlineInk Frames with round ends (UICorner) and a
	-- transparency taper (UIGradient), rotated to the slash. Width, length, spread and slide are
	-- fractions of the screen height (the stroke Frames size against the height only).
	strokes = {
		token = "OutlineInk",
		count = { min = 3, max = 5 },
		width = { min = 0.014, max = 0.04 },
		length = { min = 0.6, max = 1.15 },
		spread = 0.14, -- the lanes fan this far either side of the line through the hit
		laneJitter = 0.025, -- each lane moves up to this much off its even spacing
		slide = 0.1, -- each stroke slides up to this much along the slash
		jitterDegrees = 7, -- each stroke turns up to this much off the slash angle
		defaultAngle = -30, -- degrees, screen space (clockwise, y down) when no slash direction is given
		cornerRadius = 0.5, -- UICorner scale on the short side: a fully round brush end
		-- UIGradient transparency keys along the stroke (time, transparency): a pressed start
		-- that runs out into a dry tail.
		taper = { { 0, 0.35 }, { 0.08, 0 }, { 0.62, 0 }, { 1, 1 } },
		fallbackAspect = 16 / 9, -- screen width / height when the camera cannot say
		directionEpsilon = 1e-3, -- a slash direction shorter than this uses defaultAngle
	},

	-- Quality tiers (fx/Quality.luau). Every tier draws the figures (an impact frame without them
	-- is a bare luminance blink that hides the fight); lower tiers draw fewer of each rig's parts,
	-- the largest first (torso, legs and head carry the silhouette). The flash budget treats every
	-- tier the same.
	quality = {
		High = { silhouettes = true, strokes = true, maxPartsPerRig = 48 },
		Medium = { silhouettes = true, strokes = true, maxPartsPerRig = 24 },
		Low = { silhouettes = true, strokes = true, maxPartsPerRig = 12 },
	} :: { [string]: QualityRow },
}

return Impact
