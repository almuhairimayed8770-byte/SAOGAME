--!strict
--[[
	Combat moments: what the impact director (src/client/fx/Impact.luau) fires for each moment of
	a fight, by key into the tables that draw and sound it. The reel's hit style goes on top of the
	section 10 beats (anticipation, snap, hold with hit-stop, recovery), never instead of them.

	Keys point into:
	  glint / slashArc / slashLine / speedLines  accents.luau (sizes and kinds)
	  impactSequence                             impact.luau sequences
	  cue / shatterCue                           sfx.luau cues (layered sounds)
	  contour                                    sfx.luau contours (EQ and reverb automation)
	  sound / riser.sound                        sfx.luau entries ("family.Name")
	  punch                                      camera.luau punch (named by hit-stop tier)
	  tokens                                     palette.luau
	tools/validators/moments.luau checks every key against those files.

	Who sees what: `audience` maps each effect to "Always" (every client), "Range" (the local
	player is involved, or the moment's point is within its `range` of the camera) or "Involved"
	(only the local attacker or target; for a dodge, the dodging fighter). A row's own `audience`
	overrides the default for that row. Impact frames, the contour and the punch are for the
	people in the fight; past a moment's range nothing but its sound plays.

	`select` picks the moment for a confirmed hit: the first rule whose every `when` field equals
	the hit's wins, else `fallback`. A death always plays the Kill moment (even through a guard),
	and only an Art's final hit gets FinalHit (a basic chain's last swing also rides the Final
	hit-stop, but stays a basic hit: section 6, basics are weak).

	The 3D accents (glint, crescent, slash line, Highlight, trail flash) of a hit wait while the
	local player's impact frames hide the world (ImpactFrames.hiddenSeconds), then play: the
	reel's order, impact frames first and the slash line back in the dark world after. A row
	that names `highlight` owns the target's white Highlight flash for that hit (Replication skips
	its own), so the flash is seen after the frames instead of under them.

	Units: studs, seconds, 60 fps frames (combat.hitStopFrameSeconds).
]]

local Combat = require(script.Parent.combat)

export type Audience = "Always" | "Range" | "Involved"

-- A four-point glint at the hit. `token` tints the core (a palette token); `trailTint` tints it
-- with the hit's trail token instead.
export type GlintSpec = { size: string, token: string?, trailTint: boolean? }

-- A slash crescent or a slash line in the hit's trail token.
export type SizeSpec = { size: string }

-- The target's Highlight fill for `frames` frames, in `token` or (trailTint) the trail token. The
-- spec's hit flash is white (section 10 beat 4, section 11 Outlines).
export type HighlightSpec = { token: string?, trailTint: boolean?, frames: number }

-- Trails.flashWhite on the attacker's blade (and the Switch partner's when `partner`).
export type TrailFlashSpec = { frames: number, partner: boolean }

-- A reverse riser that ends on the clip's first damage frame (its first HitWindowOpen after the
-- ActivationHold). Skipped when that gap is under `minLeadSeconds`. The local fighter hears it in
-- 2D unless spatialForLocal, and from the release (the local clip waits at the hold pose until
-- the key comes up).
export type RiserSpec = { sound: string, minLeadSeconds: number, spatialForLocal: boolean }

export type SpeedLinesSpec = { kind: string }

export type Moment = {
	hitStop: string?, -- the hit-stop tier this moment's hits ride on (its sequence and punch match it)
	range: number?, -- studs from the camera; nil uses accentRange
	glint: GlintSpec?,
	slashArc: SizeSpec?,
	slashLine: SizeSpec?,
	impactSequence: string?,
	cue: string?,
	sound: string?, -- one more sfx.luau entry on top of the cue
	contour: string?,
	punch: string?,
	highlight: HighlightSpec?,
	trailFlash: TrailFlashSpec?,
	-- A Switch hit that another rule claims (a Final hit, a kill) still gets this row's trail flash
	-- and sound: section 11 flashes both trails on every Switch that lands.
	layerOnSwitch: boolean?,
	riser: RiserSpec?,
	-- The contour that ends `contour` for the local fighter: on the first damage frame after the
	-- release, or at once when the hold is let go past the cancel time.
	releaseContour: string?,
	speedLines: SpeedLinesSpec?,
	-- The cue the shatter plays (Shatter.luau through SfxPool.shatter); the director never plays it.
	shatterCue: string?,
	audience: { [string]: Audience }?,
}

-- A select rule: the hit matches when every field in `when` equals the hit's.
export type Rule = { when: { [string]: any }, moment: string }

local Moments = {
	-- The effect kinds the director fires, in the order it fires them (the 3D accents after the
	-- impact frames). Each has a default audience.
	effects = {
		"Cue",
		"Sound",
		"ImpactFrames",
		"Glint",
		"SlashArc",
		"SlashLine",
		"Highlight",
		"TrailFlash",
		"Contour",
		"Punch",
		"Riser",
		"SpeedLines",
	},

	audience = {
		Glint = "Range",
		SlashArc = "Range",
		SlashLine = "Range",
		-- The white hit flash is every client's (Replication flashes it for everyone), so a row
		-- that takes it over keeps it for everyone.
		Highlight = "Always",
		TrailFlash = "Range",
		-- The full-screen silhouettes are never shown to bystanders: a fight across the field must
		-- not flash anyone's screen, and the flash budget is the local player's own.
		ImpactFrames = "Involved",
		-- The mix and the camera are the local player's: only their own hits push them.
		Contour = "Involved",
		Punch = "Involved",
		Cue = "Always",
		Sound = "Always",
		Riser = "Always",
		-- The speed lines are drawn on the dodging fighter's own screen.
		SpeedLines = "Involved",
	} :: { [string]: Audience },

	-- Studs from the camera within which bystanders see a moment's accents: the section 11 outline
	-- distance, so an accent shows where the rigs' outlines do.
	accentRange = 120,

	-- Vector lengths below this count as zero (a swing that did not move, a vertical tangent).
	epsilon = 1e-6,

	-- Which moment a confirmed hit is. The first rule that matches wins. A parried hit deals no
	-- damage, so it comes first; every death is a Kill, even one through a guard.
	select = {
		{ when = { parried = true }, moment = "Parry" },
		{ when = { killed = true }, moment = "Kill" },
		{ when = { tier = "Kill" }, moment = "Kill" },
		{ when = { guarded = true }, moment = "Guarded" },
		{ when = { tier = "Final", art = true }, moment = "FinalHit" },
		{ when = { crit = true }, moment = "Crit" },
		{ when = { isSwitch = true }, moment = "Switch" },
	} :: { Rule },
	fallback = "Hit",

	-- The hit fields a rule may test (the director's HitInfo).
	hitFields = {
		tier = "string",
		art = "boolean", -- the hit is an Art's (HitConfirmed carries its artId)
		parried = "boolean",
		guarded = "boolean",
		killed = "boolean",
		crit = "boolean",
		isSwitch = "boolean",
		involved = "boolean",
		localAttacker = "boolean",
	},

	-- The death silence (combat.deathDuckDb for combat.deathFreeze) starts after the kill's
	-- hit-stop, so the kill's crack is heard under its impact frames and the silence comes after;
	-- the shatter moves later by the same amount (Replication's EntityDied).
	death = {
		duckDelayFrames = Combat.hitStopFrames.Kill,
	},

	rows = {
		-- A basic hit or a non-final Art hit (3-frame hit-stop): the 4-layer hit and a small glint.
		Hit = {
			hitStop = "Normal",
			range = 60, -- small glints far off are noise
			glint = { size = "Small" },
			cue = "HitNormal",
		},
		Crit = {
			hitStop = "Normal",
			range = 90,
			glint = { size = "Medium" },
			cue = "HitCrit",
		},
		-- A hit into a guard: the dull block, and the small glint tinted toward ink so it reads as a
		-- contact, never as a clean hit.
		Guarded = {
			hitStop = "Normal",
			range = 60,
			glint = { size = "Small", token = "OutlineInk" },
			cue = "Block",
		},
		-- An Art's final hit (6-frame hit-stop): the Art's color on the glint and the crescent, the
		-- white Highlight flash after the impact frames; the line along the blade; two impact
		-- frames, the push in.
		FinalHit = {
			hitStop = "Final",
			glint = { size = "Large", trailTint = true },
			slashArc = { size = "Medium" },
			slashLine = { size = "Medium" },
			impactSequence = "Final",
			cue = "HitFinal",
			contour = "FinalHit",
			punch = "Final",
			highlight = { token = "SystemWhite", frames = Combat.highlightFlashFrames },
		},
		-- A kill (10-frame hit-stop): the biggest of everything, the black beat and ink strokes, the
		-- bass cut under the impact frames.
		Kill = {
			hitStop = "Kill",
			range = 160, -- the kill reads across the fight
			glint = { size = "Large" },
			slashArc = { size = "Large" },
			slashLine = { size = "Large" },
			impactSequence = "Kill",
			cue = "HitKill",
			contour = "KillCut",
			punch = "Kill",
			highlight = { token = "SystemWhite", frames = Combat.highlightFlashFrames },
		},
		-- A perfect parry: the big rainbow-edged glint, one inverted frame, the long ring.
		Parry = {
			hitStop = "Normal",
			glint = { size = "Parry" },
			impactSequence = "Parry",
			cue = "Parry",
			contour = "ParryRing",
		},
		-- A Switch landing: both blades' trails flash white for 2 frames (section 11).
		Switch = {
			hitStop = "Normal",
			glint = { size = "Medium" },
			cue = "HitNormal",
			sound = "ui.SwitchLand",
			trailFlash = { frames = Combat.highlightFlashFrames, partner = true },
			layerOnSwitch = true,
		},
		-- Art activation: the chime (Replication) plus a reverse riser into the first damage frame;
		-- for the fighter who holds it, the highs leave the music while the blade glows (frequency
		-- contrast: the hit lands into space) and come back on that first damage frame.
		Activation = {
			riser = { sound = "whoosh.Riser", minLeadSeconds = 0.1, spatialForLocal = false },
			contour = "WindUp",
			releaseContour = "WindUpRelease",
		},
		-- A dodge: speed lines on the dodging fighter's screen, the whoosh for everyone near it.
		Dodge = {
			range = 60,
			speedLines = { kind = "Dodge" },
			cue = "Dodge",
			audience = { Cue = "Range" } :: { [string]: Audience },
		},
		-- A death: the shatter plays its own cue; the director blooms the mix after the silence for
		-- everyone near it.
		Death = {
			shatterCue = "Shatter",
			contour = "ShatterBloom",
			audience = { Contour = "Range" } :: { [string]: Audience },
		},
		BossDeath = {
			range = 160,
			shatterCue = "BossShatter",
			contour = "BossShatterBloom",
			audience = { Contour = "Range" } :: { [string]: Audience },
		},
	} :: { [string]: Moment },
}

--- The row for a moment; errors on an unknown name so a typo fails where it is made.
function Moments.byId(name: string): Moment
	local row = Moments.rows[name]
	if row == nil then
		error(("moments: unknown moment '%s'"):format(tostring(name)))
	end
	return row
end

--- Every moment name, sorted.
function Moments.list(): { string }
	local names = {}
	for name in Moments.rows do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--- Studs from the camera within which bystanders see the moment's accents.
function Moments.rangeOf(name: string): number
	return Moments.byId(name).range or Moments.accentRange
end

--- Who sees an effect of a moment: the row's override, else the default for the effect.
function Moments.audienceOf(name: string, effect: string): Audience
	local row = Moments.byId(name)
	local override = if row.audience ~= nil then row.audience[effect] else nil
	return (override or Moments.audience[effect] or "Always") :: Audience
end

--- True when every field of a rule's `when` equals the hit's.
function Moments.matches(rule: Rule, hit: { [string]: any }): boolean
	for field, value in rule.when do
		if hit[field] ~= value then
			return false
		end
	end
	return true
end

--- The moment a confirmed hit is: the first `select` rule it matches, else `fallback`.
function Moments.selectFor(hit: { [string]: any }): string
	for _, rule in Moments.select do
		if Moments.matches(rule, hit) then
			return rule.moment
		end
	end
	return Moments.fallback
end

--- Seconds the death silence waits after EntityDied (the kill's hit-stop).
function Moments.deathDuckDelay(): number
	return Moments.death.duckDelayFrames * Combat.hitStopFrameSeconds
end

return Moments
