--!strict
--[[
	Validates src/shared/data/moments.luau, the impact director's table, against the tables its
	keys point into:

	- Every moment the director plays exists (Hit, Crit, Guarded, FinalHit, Kill, Parry, Switch,
	  Activation, Dodge, Death, BossDeath), every select rule tests hit fields with values of
	  their type and names a moment, and the fallback is a moment.
	- Selection, over every combination of the hit fields: a hit that kills (or rides the Kill
	  hit-stop) and was not parried plays a Kill-tier moment, even through a guard; an Art's final
	  hit that is not parried, guarded or killing plays a Final-tier moment; a hit that is not an
	  Art's and does not kill never plays a moment above Normal (basics stay weak, section 6).
	- Every key exists: glint, crescent and line sizes and speed-line kinds in accents.luau; impact
	  sequences in impact.luau; cues, shatter cues and contours in sfx.luau (`cues`, `contours`);
	  sounds and the riser in sfx.luau entries; punches in camera.luau. Death and BossDeath name
  the cues SfxPool.shatter plays (sfx.shatterCues normal and boss). A file (or a table in it)
	  that is not there yet is a problem: by the end of the round all four builders' files exist.
	- Every token is a palette token; frames are whole and positive; ranges are positive and no
	  further than a glint can be drawn (accents glint.maxDistance).
	- A moment's impact sequence and punch ride on the moment's hit-stop tier.
	- Audiences are "Always", "Range" or "Involved" for known effects; impact frames and the
	  punch are only ever "Involved" (bystanders never get a full-screen flash or a camera push),
	  and a hit's contour too (only a death's contour may reach bystanders in range).
	- The death silence waits at least the kill's hit-stop.
	- The bass is back when the sub thumps: for a moment with both a cue and a contour, every
	  sfx.limits.subLayers layer of the cue starts with its group's low band, as the contour
	  eases it, at or above sfx.limits.bassBackDb.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local REQUIRED = {
	"Hit",
	"Crit",
	"Guarded",
	"FinalHit",
	"Kill",
	"Parry",
	"Switch",
	"Activation",
	"Dodge",
	"Death",
	"BossDeath",
}
local AUDIENCES = { Always = true, Range = true, Involved = true }
local DEATH_ROWS = { Death = true, BossDeath = true }
-- The sfx.shatterCues key each death row's shatterCue must match.
local SHATTER_KINDS = { Death = "normal", BossDeath = "boss" }
local INVOLVED_ONLY = { "ImpactFrames", "Punch" }
local TIERS = { "Normal", "Final", "Kill" }

return function(ctx: Context): { string }
	local problems: { string } = {}
	local function check(ok: boolean, message: string, ...: any)
		if not ok then
			table.insert(problems, "moments: " .. string.format(message, ...))
		end
	end

	local okMoments, moments = pcall(ctx.load, "src/shared/data/moments")
	if not okMoments or typeof(moments) ~= "table" then
		check(false, "src/shared/data/moments.luau does not load (%s)", tostring(moments))
		return problems
	end
	local palette = ctx.load("src/shared/data/palette")
	local combat = ctx.load("src/shared/data/combat")

	-- The other builders' files: a file that is not there yet is reported once and its keys skipped.
	local function loadOther(path: string, owner: string): any
		local ok, result = pcall(ctx.load, path)
		if not ok or typeof(result) ~= "table" then
			check(false, "%s.luau is not there yet (the %s builder's table): its keys cannot be checked", path, owner)
			return nil
		end
		return result
	end
	local accents = loadOther("src/shared/data/accents", "ACCENTS")
	local impact = loadOther("src/shared/data/impact", "FRAMES")
	local sfx = loadOther("src/shared/data/sfx", "SOUND")
	local camera = loadOther("src/shared/data/camera", "DIRECTOR")

	-- A sub-table of another file, reported once when missing.
	local reportedMissing: { [string]: boolean } = {}
	local function section(root: any, path: { string }, label: string): any
		if root == nil then
			return nil
		end
		local node = root
		for _, key in path do
			node = if typeof(node) == "table" then node[key] else nil
		end
		if typeof(node) ~= "table" then
			if not reportedMissing[label] then
				reportedMissing[label] = true
				check(false, "%s is missing, so no moment can name one", label)
			end
			return nil
		end
		return node
	end
	local glintSizes = section(accents, { "glint", "sizes" }, "accents.glint.sizes")
	local arcSizes = section(accents, { "slashArc", "sizes" }, "accents.slashArc.sizes")
	local lineSizes = section(accents, { "slashLine", "sizes" }, "accents.slashLine.sizes")
	local speedKinds = section(accents, { "speedLines", "kinds" }, "accents.speedLines.kinds")
	local sequences = section(impact, { "sequences" }, "impact.sequences")
	local cues = section(sfx, { "cues" }, "sfx.cues")
	local contours = section(sfx, { "contours" }, "sfx.contours")
	local families = section(sfx, { "families" }, "sfx.families")
	local shatterCues = section(sfx, { "shatterCues" }, "sfx.shatterCues")
	local punches = section(camera, { "punch" }, "camera.punch")

	local function isNumber(value: any): boolean
		return typeof(value) == "number" and value == value
	end
	local function isWholePositive(value: any): boolean
		return isNumber(value) and value >= 1 and value % 1 == 0
	end
	local function isToken(value: any): boolean
		return typeof(value) == "string" and palette.tokens[value] ~= nil
	end
	-- `name` must be a key of `tableOf` (skipped when that table is missing; already reported).
	local function named(tableOf: any, name: any, where: string, what: string, file: string)
		if typeof(name) ~= "string" then
			check(false, "%s must name a %s (a string)", where, what)
			return
		end
		if tableOf == nil then
			return
		end
		check(tableOf[name] ~= nil, "%s names %s '%s', which %s does not have", where, what, name, file)
	end
	local function entry(name: any, where: string)
		if typeof(name) ~= "string" then
			check(false, "%s must name an sfx.luau entry ('family.Name')", where)
			return
		end
		local family, entryName = name:match("^([^%.]+)%.(.+)$")
		if family == nil or entryName == nil then
			check(false, "%s '%s' is not 'family.Name'", where, name)
			return
		end
		if families == nil then
			return
		end
		local group = families[family]
		check(
			typeof(group) == "table" and typeof(group.entries) == "table" and group.entries[entryName] ~= nil,
			"%s names sound '%s', which sfx.luau does not have",
			where,
			name
		)
	end

	-- ------------------------------------------------------------------ shape
	local rows = moments.rows
	if typeof(rows) ~= "table" then
		check(false, "rows is missing")
		return problems
	end
	for _, name in REQUIRED do
		check(typeof(rows[name]) == "table", "the director plays '%s', which has no row", name)
	end

	local effects: { [string]: boolean } = {}
	if typeof(moments.effects) == "table" then
		for _, effect in moments.effects do
			effects[effect] = true
		end
	else
		check(false, "effects (the effect kinds the director fires) is missing")
	end
	local defaults = moments.audience
	if typeof(defaults) ~= "table" then
		check(false, "audience (the default audience per effect) is missing")
		defaults = {}
	end
	for effect in effects do
		check(AUDIENCES[defaults[effect]] == true, "audience.%s must be Always, Range or Involved", effect)
	end
	for effect, who in defaults do
		check(effects[effect] == true, "audience.%s is not an effect the director fires", tostring(effect))
		check(
			AUDIENCES[who] == true,
			"audience.%s '%s' must be Always, Range or Involved",
			tostring(effect),
			tostring(who)
		)
	end
	for _, effect in INVOLVED_ONLY do
		check(
			defaults[effect] == "Involved",
			"audience.%s must be Involved: only the people in the fight get it",
			effect
		)
	end
	check(
		defaults.Contour == "Involved",
		"audience.Contour must be Involved: only the people in the fight get a hit's contour"
	)

	check(isNumber(moments.accentRange) and moments.accentRange > 0, "accentRange must be a positive number of studs")
	check(
		isNumber(moments.epsilon) and moments.epsilon > 0 and moments.epsilon < 0.001,
		"epsilon must be a small positive number"
	)

	-- ------------------------------------------------------------------ selection
	local hitFields = moments.hitFields
	if typeof(hitFields) ~= "table" then
		check(false, "hitFields (the hit fields a rule may test) is missing")
		hitFields = {}
	end
	local rulesOk = typeof(moments.select) == "table" and #moments.select > 0
	if not rulesOk then
		check(false, "select must list the rules that pick a hit's moment")
	else
		for index, rule in moments.select do
			local where = ("select[%d]"):format(index)
			if typeof(rule) ~= "table" or typeof(rule.when) ~= "table" or next(rule.when) == nil then
				check(false, "%s must be { when = { field = value, ... }, moment }", where)
				rulesOk = false
				continue
			end
			for field, value in rule.when do
				local fieldType = hitFields[field]
				check(fieldType ~= nil, "%s tests '%s', which is not a hit field", where, tostring(field))
				if fieldType ~= nil then
					check(
						typeof(value) == fieldType,
						"%s compares %s to a %s, not a %s",
						where,
						tostring(field),
						typeof(value),
						fieldType
					)
				end
				if field == "tier" and typeof(value) == "string" then
					check(combat.hitStopFrames[value] ~= nil, "%s tier '%s' is not a hit-stop tier", where, value)
				end
			end
			check(
				typeof(rule.moment) == "string" and typeof(rows[rule.moment]) == "table",
				"%s names moment '%s', which has no row",
				where,
				tostring(rule.moment)
			)
		end
	end
	check(
		typeof(moments.fallback) == "string" and typeof(rows[moments.fallback]) == "table",
		"fallback must name a moment with a row"
	)

	-- Every combination of the boolean hit fields on each tier, through the rules in order.
	if rulesOk and typeof(rows[moments.fallback]) == "table" then
		local flags: { string } = {}
		for field, fieldType in hitFields do
			if fieldType == "boolean" then
				table.insert(flags, field)
			end
		end
		table.sort(flags)
		local function pick(hit: { [string]: any }): string
			for _, rule in moments.select do
				local all = true
				for field, value in rule.when do
					if hit[field] ~= value then
						all = false
						break
					end
				end
				if all then
					return rule.moment
				end
			end
			return moments.fallback
		end
		local function describe(hit: { [string]: any }): string
			local parts = { "tier " .. tostring(hit.tier) }
			for _, field in flags do
				if hit[field] then
					table.insert(parts, field)
				end
			end
			return table.concat(parts, ", ")
		end
		local reported: { [string]: boolean } = {}
		local function expectTier(rule: string, hit: { [string]: any }, ok: (tier: string) -> boolean, want: string)
			if reported[rule] then
				return
			end
			local name = pick(hit)
			local row = rows[name]
			local tier = if typeof(row) == "table" and row.hitStop ~= nil then row.hitStop else "Normal"
			if not ok(tier) then
				reported[rule] = true
				check(
					false,
					"select plays '%s' (hitStop %s) for a hit (%s): %s",
					name,
					tostring(tier),
					describe(hit),
					want
				)
			end
		end
		for mask = 0, 2 ^ #flags - 1 do
			for _, tierName in TIERS do
				local hit: { [string]: any } = { tier = tierName }
				for bit, field in flags do
					hit[field] = (mask // 2 ^ (bit - 1)) % 2 == 1
				end
				local parried = hit.parried == true
				local killing = hit.killed == true or tierName == "Kill"
				if not parried and killing then
					expectTier("kill", hit, function(tier)
						return tier == "Kill"
					end, "a death plays the Kill moment, even through a guard")
				end
				if not parried and not killing and not hit.guarded and tierName == "Final" and hit.art then
					expectTier("final", hit, function(tier)
						return tier == "Final"
					end, "an Art's final hit plays a Final-tier moment")
				end
				if not hit.art and not killing then
					expectTier("basic", hit, function(tier)
						return tier == "Normal"
					end, "a hit that is not an Art's and does not kill stays a Normal moment (basics are weak)")
				end
			end
		end
	end

	-- ------------------------------------------------------------------ the bass under a sub
	local limits = if sfx ~= nil and typeof(sfx.limits) == "table" then sfx.limits else nil
	local easingDefault = if sfx ~= nil and typeof(sfx.effects) == "table" then sfx.effects.easing else nil
	local okEasing, Easing = pcall(ctx.load, "src/shared/util/Easing")
	-- The low band of `group` `t` seconds into contour `steps`, eased from wherever it was.
	local function lowAt(steps: { any }, group: string, t: number): number
		local ordered: { any } = {}
		for _, step in steps do
			if typeof(step) == "table" and step.group == group and isNumber(step.low) and isNumber(step.at) then
				table.insert(ordered, step)
			end
		end
		table.sort(ordered, function(a, b)
			return a.at < b.at
		end)
		local from, to, at, ramp, easing = 0, 0, 0, 0, easingDefault
		local function valueAt(x: number): number
			if ramp <= 0 or x >= at + ramp then
				return to
			end
			local fraction = math.clamp((x - at) / ramp, 0, 1)
			local eased = fraction
			if okEasing and typeof(Easing) == "table" and typeof(easing) == "string" then
				local ok, value = pcall(Easing.evaluate, easing, fraction)
				if ok and isNumber(value) then
					eased = value
				end
			end
			return from + (to - from) * eased
		end
		for _, step in ordered do
			if step.at > t then
				break
			end
			from = valueAt(step.at)
			to = step.low
			at = step.at
			ramp = if isNumber(step.ramp) then step.ramp else 0
			easing = step.easing or easingDefault
		end
		return valueAt(t)
	end
	local function bassBack(here: string, row: any)
		if limits == nil or cues == nil or contours == nil or families == nil then
			return
		end
		if typeof(limits.subLayers) ~= "table" or not isNumber(limits.bassBackDb) then
			return
		end
		local layers = if typeof(row.cue) == "string" then cues[row.cue] else nil
		local steps = if typeof(row.contour) == "string" then contours[row.contour] else nil
		if typeof(layers) ~= "table" or typeof(steps) ~= "table" then
			return
		end
		local isSub: { [string]: boolean } = {}
		for _, name in limits.subLayers do
			isSub[name] = true
		end
		for index, layer in layers do
			if typeof(layer) ~= "table" or not isSub[layer.name] or not isNumber(layer.delay) then
				continue
			end
			local family = tostring(layer.name):match("^([^%.]+)%.")
			local group = if family ~= nil and typeof(families[family]) == "table" then families[family].group else nil
			if typeof(group) ~= "string" then
				continue
			end
			local low = lowAt(steps, group, layer.delay)
			check(
				low >= limits.bassBackDb,
				"%s: cue %s layer %d (%s) starts at %.3f s with the %s low band at %.1f dB under contour %s; the bass must be back to %s dB first",
				here,
				tostring(row.cue),
				index,
				tostring(layer.name),
				layer.delay,
				group,
				low,
				tostring(row.contour),
				tostring(limits.bassBackDb)
			)
		end
	end

	-- ------------------------------------------------------------------ rows
	local maxGlintDistance = if accents ~= nil and typeof(accents.glint) == "table"
		then accents.glint.maxDistance
		else nil
	local names = {}
	for name in rows do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local row = rows[name]
		local here = "rows." .. tostring(name)
		if typeof(row) ~= "table" then
			check(false, "%s must be a table", here)
			continue
		end
		local tier = row.hitStop
		if tier ~= nil then
			check(combat.hitStopFrames[tier] ~= nil, "%s.hitStop '%s' is not a hit-stop tier", here, tostring(tier))
		end
		local range = row.range
		if range ~= nil then
			check(isNumber(range) and range > 0, "%s.range must be a positive number of studs", here)
		end
		local resolvedRange = if range ~= nil then range else moments.accentRange

		if row.glint ~= nil then
			local glint = row.glint
			if typeof(glint) ~= "table" then
				check(false, "%s.glint must be a table { size, token?, trailTint? }", here)
			else
				named(glintSizes, glint.size, here .. ".glint", "glint size", "accents.luau")
				if glint.token ~= nil then
					check(
						isToken(glint.token),
						"%s.glint.token '%s' is not a palette token",
						here,
						tostring(glint.token)
					)
				end
				check(
					not (glint.token ~= nil and glint.trailTint == true),
					"%s.glint has both a token and trailTint: pick one",
					here
				)
				if isNumber(maxGlintDistance) and isNumber(resolvedRange) then
					check(
						resolvedRange <= maxGlintDistance,
						"%s range %s is past the glint's draw distance (accents glint.maxDistance %s)",
						here,
						tostring(resolvedRange),
						tostring(maxGlintDistance)
					)
				end
			end
		end
		if row.slashArc ~= nil then
			named(
				arcSizes,
				if typeof(row.slashArc) == "table" then row.slashArc.size else nil,
				here .. ".slashArc",
				"slash crescent size",
				"accents.luau"
			)
		end
		if row.slashLine ~= nil then
			named(
				lineSizes,
				if typeof(row.slashLine) == "table" then row.slashLine.size else nil,
				here .. ".slashLine",
				"slash line size",
				"accents.luau"
			)
		end
		if row.speedLines ~= nil then
			named(
				speedKinds,
				if typeof(row.speedLines) == "table" then row.speedLines.kind else nil,
				here .. ".speedLines",
				"speed-line kind",
				"accents.luau"
			)
		end
		if row.impactSequence ~= nil then
			named(sequences, row.impactSequence, here .. ".impactSequence", "impact sequence", "impact.luau")
			check(tier ~= nil, "%s has an impact sequence but no hitStop tier for it to ride on", here)
			local sequence = if sequences ~= nil then sequences[row.impactSequence] else nil
			if typeof(sequence) == "table" and tier ~= nil then
				check(
					sequence.tier == tier,
					"%s plays impact sequence '%s', which rides on the %s hit-stop, not this moment's %s",
					here,
					tostring(row.impactSequence),
					tostring(sequence.tier),
					tostring(tier)
				)
			end
		end
		if row.punch ~= nil then
			named(punches, row.punch, here .. ".punch", "camera punch", "camera.luau")
			check(
				row.punch == tier,
				"%s punch '%s' must be its hitStop tier '%s'",
				here,
				tostring(row.punch),
				tostring(tier)
			)
		end
		if row.cue ~= nil then
			named(cues, row.cue, here .. ".cue", "cue", "sfx.luau")
		end
		if row.shatterCue ~= nil then
			named(cues, row.shatterCue, here .. ".shatterCue", "cue", "sfx.luau")
		end
		local shatterKind = SHATTER_KINDS[name]
		if shatterKind ~= nil and shatterCues ~= nil then
			check(
				row.shatterCue == shatterCues[shatterKind],
				"%s.shatterCue '%s' must be sfx.shatterCues.%s ('%s'), the cue SfxPool.shatter plays",
				here,
				tostring(row.shatterCue),
				shatterKind,
				tostring(shatterCues[shatterKind])
			)
		end
		if row.contour ~= nil then
			named(contours, row.contour, here .. ".contour", "contour", "sfx.luau")
		end
		if row.releaseContour ~= nil then
			named(contours, row.releaseContour, here .. ".releaseContour", "contour", "sfx.luau")
			check(row.contour ~= nil, "%s has a releaseContour but no contour for it to end", here)
		end
		bassBack(here, row)
		if row.sound ~= nil then
			entry(row.sound, here .. ".sound")
		end
		if row.riser ~= nil then
			local riser = row.riser
			if typeof(riser) ~= "table" then
				check(false, "%s.riser must be a table { sound, minLeadSeconds, spatialForLocal }", here)
			else
				entry(riser.sound, here .. ".riser.sound")
				check(
					isNumber(riser.minLeadSeconds) and riser.minLeadSeconds > 0,
					"%s.riser.minLeadSeconds must be positive",
					here
				)
				check(typeof(riser.spatialForLocal) == "boolean", "%s.riser.spatialForLocal must be a boolean", here)
			end
		end
		if row.highlight ~= nil then
			local highlight = row.highlight
			if typeof(highlight) ~= "table" then
				check(false, "%s.highlight must be a table { token? | trailTint, frames }", here)
			else
				check(
					isWholePositive(highlight.frames),
					"%s.highlight.frames must be a whole number of at least 1",
					here
				)
				check(
					(highlight.trailTint == true) ~= (highlight.token ~= nil),
					"%s.highlight needs exactly one of token and trailTint",
					here
				)
				if highlight.token ~= nil then
					check(
						isToken(highlight.token),
						"%s.highlight.token '%s' is not a palette token",
						here,
						tostring(highlight.token)
					)
				end
			end
		end
		if row.trailFlash ~= nil then
			local flash = row.trailFlash
			if typeof(flash) ~= "table" then
				check(false, "%s.trailFlash must be a table { frames, partner }", here)
			else
				check(isWholePositive(flash.frames), "%s.trailFlash.frames must be a whole number of at least 1", here)
				check(typeof(flash.partner) == "boolean", "%s.trailFlash.partner must be a boolean", here)
			end
		end
		if row.audience ~= nil then
			if typeof(row.audience) ~= "table" then
				check(false, "%s.audience must be a table of effect -> audience", here)
			else
				for effect, who in row.audience do
					check(
						effects[effect] == true,
						"%s.audience.%s is not an effect the director fires",
						here,
						tostring(effect)
					)
					check(
						AUDIENCES[who] == true,
						"%s.audience.%s '%s' must be Always, Range or Involved",
						here,
						tostring(effect),
						tostring(who)
					)
				end
				for _, effect in INVOLVED_ONLY do
					local who = row.audience[effect]
					check(who == nil or who == "Involved", "%s.audience.%s must stay Involved", here, effect)
				end
				local contour = row.audience.Contour
				check(
					contour == nil or contour == "Involved" or DEATH_ROWS[name] == true,
					"%s.audience.Contour must stay Involved (only a death's contour may reach bystanders)",
					here
				)
			end
		end
	end

	-- ------------------------------------------------------------------ death
	local death = moments.death
	if typeof(death) ~= "table" then
		check(false, "death (the silence's delay after the kill) is missing")
	else
		check(isNumber(death.duckDelayFrames), "death.duckDelayFrames must be a number of frames")
		if isNumber(death.duckDelayFrames) then
			check(
				death.duckDelayFrames >= combat.hitStopFrames.Kill,
				"death.duckDelayFrames must be at least the kill's hit-stop (%d frames), so its crack is heard",
				combat.hitStopFrames.Kill
			)
		end
	end

	return problems
end
