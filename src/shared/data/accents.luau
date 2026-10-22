--!strict
--[[
	Hit accents: the flat-color shapes the reel layers on top of the section 10 beats. The
	four-point glint at the contact point, the slash crescent in the swing plane, the thin
	chromatic slash line across the hit on Art final hits and kills, the screen-edge speed lines
	on a dodge or a dash, and the blade-tip history Trails keeps for the swing direction. Every
	number Glint, SlashArc, SpeedLines and Trails.swingDirection use lives here; which moment
	fires which size is the director's (moments.luau).

	Units: studs, screen pixels (px), 60 fps frames (seconds through combat.hitStopFrameSeconds),
	degrees, fractions 0..1. Colors are palette tokens. Easing names are util/Easing names and are
	never Linear: every accent eases.

	None of these is a full-screen flash. The glint and the slash shapes cover a small part of the
	screen and change no screen-wide brightness; the speed lines stay out of the middle third and
	are thin. None of them asks the flash budget, and Reduce flashing leaves them on.
]]

local Combat = require(script.Parent.combat)
local Choreo = require(script.Parent.choreo)

export type Thickness = {
	scale: number, -- fraction of the star's size
	pixels: number, -- plus this many pixels, so a far glint never goes thinner than a line
}

export type GlintSize = {
	studs: number, -- the star's span at full size (the long cross, tip to tip)
	maxPixels: number, -- on-screen cap at full size, so a glint by the camera never fills the view
	thickness: Thickness,
	edgeOffsetPixels: number, -- how far the split-edge copies sit off the core
	startScale: number, -- the punch starts this small
	endScale: number, -- and shrinks to this as it fades
	punchFrames: number, -- out to full size with the overshoot
	holdFrames: number, -- full size
	fadeFrames: number, -- shrink and fade
	turnDegrees: number, -- the star turns this far over its life
}

export type GlintArm = {
	length: number, -- fraction of the star's size
	rotation: number, -- degrees
}

export type ArcSize = {
	length: number, -- studs between the crescent's two points
	bow: number, -- studs the curve's control points sit off the chord; the apex sits 3/4 of it off
	width: number, -- studs at the widest (the middle); both points taper to nothing
	holdFrames: number, -- full after the 1-frame snap on
	wipeFrames: number, -- the wipe from the trailing point to the leading one
}

export type LineSize = {
	length: number, -- studs at full length, centered on the hit
	width: number, -- studs
	edgeOffset: number, -- studs the split-edge copies sit off the core, across the screen
	startLength: number, -- fraction of the length on the first frame
	growFrames: number, -- out to full length
	holdFrames: number, -- full
	thinFrames: number, -- the width goes to nothing
}

export type SpeedLineKind = {
	seconds: number, -- the whole effect, in and out
	count: number, -- lines at quality scale 1
	inFrames: number, -- the lines rush in from the edges
	outFrames: number, -- they pull back out and fade
	transparency: number, -- at full strength
	thicknessPixels: number,
	-- Where each line's inner end sits, as a fraction of the way from the middle third's edge to the
	-- screen's edge along its ray (0 = right on the middle third, 1 = at the screen edge).
	innerReach: { min: number, max: number },
	startReach: number, -- where the inner ends start the rush in (same scale)
	overshoot: number, -- the outer end sits this multiple of the edge distance (past the edge)
	angleJitter: number, -- fraction of the even spacing each ray may move either way
}

export type QualityTier = {
	glints: number, -- concurrent glints; the oldest is reused past it
	glintEdgeScale: number, -- split-edge copies: offset multiplier, 0 skips them
	arcs: number, -- concurrent slash crescents
	arcSegments: number, -- Beam.Segments per crescent half
	lines: number, -- concurrent slash lines
	lineEdges: boolean, -- the slash line's split-edge copies
	speedLineScale: number, -- multiplier on each kind's line count
}

local FRAME = Combat.hitStopFrameSeconds

local Accents = {
	-- Seconds per frame: every *Frames count converts through this.
	frameSeconds = FRAME,

	-- The limits tools/validators/accents.luau holds every effect to: no accent stays at full
	-- strength past the kill hit-stop (10 frames), and none fades longer than maxFadeFrames.
	limits = {
		fullFrames = Combat.hitStopFrames.Kill,
		maxFadeFrames = 12,
	},

	-- The worst case at once (every pool full at High) may use this share of the scene's draw calls.
	budget = {
		drawCallShare = 0.08,
	},

	-- The reel's four-point star with rainbow-split edges, at the contact point. A long cross and a
	-- shorter diagonal cross in a SystemWhite core, with two copies behind it a pixel or two out
	-- in the split-edge tokens, so the edges read as chromatic.
	glint = {
		coreToken = "SystemWhite",
		edgeTokens = { "TrailRose", "SystemCyan" }, -- behind the core, in this order
		-- Pixel direction of each edge copy (x right, y down), times the size's edgeOffsetPixels.
		edgeDirections = { { -1, 1 }, { 1, -1 } },
		edgeTransparency = 0.1,
		tintBlend = 0.55, -- how far an optional token pulls the core away from SystemWhite
		-- The long cross, then the shorter diagonal cross.
		arms = {
			{ length = 1, rotation = 0 },
			{ length = 1, rotation = 90 },
			{ length = 0.42, rotation = 45 },
			{ length = 0.42, rotation = -45 },
		} :: { GlintArm },
		-- Transparency along every arm (tip, middle, tip): solid in the middle, tapering to the tips.
		taper = { { 0, 1 }, { 0.3, 0.6 }, { 0.5, 0 }, { 0.7, 0.6 }, { 1, 1 } },
		punchEasing = "BackOut", -- out to full size with an overshoot
		fadeEasing = "QuadIn", -- the shrink and the fade
		turnEasing = "QuadOut",
		canvasScale = 1.15, -- the BillboardGui's room past full size, so the overshoot is never cut
		jitterDegrees = 6, -- the star starts up to this far off upright, either way
		anchorSize = 0.2, -- studs; the invisible anchored part each glint hangs on
		maxDistance = 160, -- studs; past this the glint draws nothing
		folderName = "FxGlints",
		defaultSize = "Small",
		sizes = {
			-- Basic hits.
			Small = {
				studs = 2.4,
				maxPixels = 150,
				thickness = { scale = 0.03, pixels = 1 },
				edgeOffsetPixels = 1,
				startScale = 0.35,
				endScale = 0.2,
				punchFrames = 2,
				holdFrames = 1,
				fadeFrames = 5,
				turnDegrees = 8,
			},
			-- Crits and Art hits.
			Medium = {
				studs = 3.6,
				maxPixels = 220,
				thickness = { scale = 0.03, pixels = 1 },
				edgeOffsetPixels = 2,
				startScale = 0.3,
				endScale = 0.2,
				punchFrames = 2,
				holdFrames = 2,
				fadeFrames = 6,
				turnDegrees = 10,
			},
			-- Art final hits and kills.
			Large = {
				studs = 5.2,
				maxPixels = 320,
				thickness = { scale = 0.028, pixels = 2 },
				edgeOffsetPixels = 2,
				startScale = 0.25,
				endScale = 0.15,
				punchFrames = 2,
				holdFrames = 3,
				fadeFrames = 8,
				turnDegrees = 12,
			},
			-- The parry's signature: the biggest and the longest.
			Parry = {
				studs = 7.5,
				maxPixels = 440,
				thickness = { scale = 0.026, pixels = 2 },
				edgeOffsetPixels = 3,
				startScale = 0.2,
				endScale = 0.1,
				punchFrames = 2,
				holdFrames = 6,
				fadeFrames = 12,
				turnDegrees = 18,
			},
		} :: { [string]: GlintSize },
	},

	-- The reel's flat-color slash crescent through the hit point, in the swing plane. Each half
	-- is a Beam pair (the token's color outside, a narrower SystemWhite core inside) curved with
	-- CurveSize0 / CurveSize1, so the crescent tapers to a point at both ends. It snaps on in one
	-- frame and wipes out from the trailing point to the leading one.
	slashArc = {
		defaultToken = "TrailCyanWhite", -- when the token given is not a palette token
		innerToken = "SystemWhite",
		innerWidthFraction = 0.38, -- of the outer width
		outerTransparency = 0.05,
		innerTransparency = 0,
		outerLightEmission = 0.4,
		innerLightEmission = 1,
		lightInfluence = 0, -- flat: the light in the scene never shades it
		innerZOffset = 0.04, -- studs toward the camera, so the core draws over the color
		-- Each end's control arm leans this fraction of the length along the swing, so the points
		-- meet the chord at a slant (0 would make the ends stand square on the chord).
		endSpread = 0.3,
		-- The attachment axis that carries the swing plane's normal ("Y" or "Z"). STUDIO_TASKS
		-- checks it: with the right axis the crescent lies flat in the swing plane.
		faceAxis = "Y",
		-- The director lays the crescent in the true swing plane (the hit's radius from the attacker
		-- and the swing direction). Seen near edge-on (a horizontal swing from a camera just above
		-- it) it would read as a line, so it turns about the swing direction toward the camera: just
		-- far enough that its face is at most `faceDegrees` off the camera, and never more than
		-- `maxDegrees`. A swing that runs within asin(minPlaneSine) of its radius (a thrust) has no
		-- plane of its own and stands upright along the swing instead.
		tilt = { faceDegrees = 50, maxDegrees = 30, minPlaneSine = 0.25 },
		wipeEasing = "QuadOut",
		wipeSoftness = 0.18, -- fraction of the crescent the wipe's soft edge spans
		wipeKeys = 9, -- Transparency keypoints along each half while it wipes
		-- The wipe front snaps to this many steps from whole to gone. Each step's Transparency
		-- sequences are built once, so a wiping crescent builds nothing per frame; at least 4
		-- steps per frame of the longest wipe, so every frame of the wipe still moves it.
		wipeSteps = 32,
		innerLead = 0.35, -- the white core finishes its wipe this fraction of the wipe early
		hostSize = 0.2, -- studs; the invisible anchored part the attachments sit on
		folderName = "FxSlashArcs",
		defaultSize = "Medium",
		sizes = {
			Medium = { length = 6.5, bow = 1.6, width = 0.6, holdFrames = 1, wipeFrames = 5 },
			Large = { length = 10, bow = 2.6, width = 1, holdFrames = 2, wipeFrames = 7 },
		} :: { [string]: ArcSize },
	},

	-- The reel's thin chromatic line along the blade's path across the hit, for Art final hits and
	-- kills: a SystemWhite core and two split-edge copies offset across the screen, a few frames.
	slashLine = {
		coreToken = "SystemWhite",
		edgeTokens = { "TrailRose", "SystemCyan" },
		edgeSides = { 1, -1 }, -- which side of the core each edge copy sits on
		coreTransparency = 0,
		edgeTransparency = 0.15,
		lightEmission = 1,
		lightInfluence = 0,
		coreZOffset = 0.02, -- studs toward the camera, so the core draws over its copies
		endFade = 0.18, -- fraction of the line at each end that fades to nothing
		growEasing = "ExpoOut",
		thinEasing = "QuadIn",
		faceCamera = true, -- a line reads as a stroke from any angle
		hostSize = 0.2,
		folderName = "FxSlashLines",
		defaultSize = "Medium",
		sizes = {
			-- Art final hits.
			Medium = {
				length = 14,
				width = 0.08,
				edgeOffset = 0.07,
				startLength = 0.55,
				growFrames = 1,
				holdFrames = 3,
				thinFrames = 4,
			},
			-- Kills.
			Large = {
				length = 22,
				width = 0.12,
				edgeOffset = 0.1,
				startLength = 0.45,
				growFrames = 2,
				holdFrames = 4,
				thinFrames = 5,
			},
		} :: { [string]: LineSize },
	},

	-- Screen-edge speed lines on the local screen for a dodge or a dash: thin lines on rays from
	-- the screen center, from just outside the middle third (the fighter stays readable) to past
	-- the screen edge, their inner ends faded. No screen-wide brightness change: never a flash.
	speedLines = {
		screenGuiName = "FxSpeedLines",
		displayOrder = 5, -- under the HUD (ui.luau hud.displayOrder 10)
		token = "SystemWhite",
		-- Transparency along each line, inner end first: the inner part fades to nothing.
		gradient = { { 0, 1 }, { 0.4, 0.5 }, { 1, 0 } },
		inEasing = "ExpoOut",
		outEasing = "QuadIn",
		-- The middle of the screen the lines never enter, as a fraction of its width and height:
		-- the middle third, so the fighter stays readable.
		clearFraction = 1 / 3,
		-- The screen size used when the viewport cannot be read (Lune, before the camera exists).
		referenceScreen = { width = 1920, height = 1080 },
		-- At most this fraction of the reference screen is covered by lines at once (worst case).
		maxCoverage = 0.03,
		defaultKind = "Dodge",
		kinds = {
			-- The dodge's 0.25 s step (section 6).
			Dodge = {
				seconds = Combat.dodgeDuration,
				count = 14,
				inFrames = 4,
				outFrames = 7,
				transparency = 0.3,
				thicknessPixels = 2,
				innerReach = { min = 0.05, max = 0.4 },
				startReach = 0.7,
				overshoot = 1.05,
				angleJitter = 0.4,
			},
			-- A dash (a gap-closer Art or a sprint burst): a little longer and denser.
			Dash = {
				seconds = 0.35,
				count = 18,
				inFrames = 4,
				outFrames = 11,
				transparency = 0.25,
				thicknessPixels = 2,
				innerReach = { min = 0.03, max = 0.32 },
				startReach = 0.65,
				overshoot = 1.05,
				angleJitter = 0.4,
			},
		} :: { [string]: SpeedLineKind },
	},

	-- Trails.swingDirection: Trails samples each tracked blade tip (TrailEnd) once per Heartbeat
	-- into a short ring and reports the unit motion between the newest sample and the one
	-- `samples - 1` steps before it. While a trail kind is on (the swing itself) each good
	-- direction is also remembered with its time, and for `memorySeconds` after the swing that
	-- direction is the answer: a HitConfirmed that arrives after the window closed (the round trip,
	-- the server's lag allowance) still gets the swing, never the follow-through.
	swing = {
		samples = 5,
		minTravel = 0.25, -- studs; under this the tip has not really moved and the answer is nil
		maxTravel = 30, -- studs; over this the rig jumped (a respawn, a teleport) and the answer is nil
		memorySeconds = 0.4,
		-- Studs from the camera within which an idle blade's tip is sampled (a swinging one always
		-- is): as far as any moment's accents show (moments.luau accentRange and every row's
		-- range), so a far swing's snap still starts from the pose before it. Past it nothing reads
		-- the ring, so it is not kept.
		sampleDistance = 160,
		-- A strike's snap (section 10 beat 2, the smear's frames): the tip's chord over this many
		-- frames from the strike's first sample (TrailOn or a HitWindowOpen) is the swing's
		-- direction, held for memorySeconds, so the overshoot and settle never turn it around.
		snapFrames = Choreo.smearFrames,
	},

	-- Quality tiers (fx.luau names the tiers; Quality.luau picks one).
	quality = {
		High = {
			glints = 6,
			glintEdgeScale = 1,
			arcs = 4,
			arcSegments = 16,
			lines = 3,
			lineEdges = true,
			speedLineScale = 1,
		},
		Medium = {
			glints = 4,
			glintEdgeScale = 0.5,
			arcs = 3,
			arcSegments = 12,
			lines = 2,
			lineEdges = true,
			speedLineScale = 0.7,
		},
		Low = {
			glints = 3,
			glintEdgeScale = 0,
			arcs = 2,
			arcSegments = 8,
			lines = 1,
			lineEdges = false,
			speedLineScale = 0.45,
		},
	} :: { [string]: QualityTier },
}

--- The quality tier's accent numbers; falls back to High for an unknown tier name.
function Accents.tier(name: string): QualityTier
	return Accents.quality[name] or Accents.quality.High
end

--- Seconds that `frames` 60 fps frames take.
function Accents.seconds(frames: number): number
	return frames * FRAME
end

return Accents
