--!strict
--[[
	Validates src/shared/data/accents.luau: the glints, slash crescents, slash lines, speed lines
	and the swing-direction ring.

	- Every color is a palette token.
	- Every size the contract names exists (glints Small, Medium, Large, Parry; crescents and lines
	  Medium, Large; speed lines Dodge, Dash), every default names one, and every size moments.luau
	  names (fields `glint` / `glintSize`, `slashArc` / `arcSize`, `slashLine` / `lineSize`,
	  `speedLines` / `speedLineKind`, as a string or a table with `size` / `kind`) exists.
	- Durations are short: no effect stays at full strength past the 10-frame kill hit-stop
	  (limits.fullFrames) and none fades longer than limits.maxFadeFrames; the Dodge lines last the
	  dodge (combat.dodgeDuration).
	- Every easing is a util/Easing curve and never Linear or Hold.
	- The crescent's turn toward the camera is bounded (0 < maxDegrees, 0 < faceDegrees < 90, a
	  full turn from edge-on stops no nearer than faceDegrees, 0 < minPlaneSine < 1), and the
	  swing memory outlasts the sample ring, stays under a second and holds the snap's frames.
	- The crescent's wipe snaps to at least 4 steps per frame of the longest wipe, and an idle
	  blade is sampled as far as any moment's accents show (moments.accentRange, every row's range).
	- Sizes grow in order and the Parry glint is the biggest and the longest.
	- The speed lines stay out of the middle third and cover at most maxCoverage of the screen.
	- Every fx.luau quality tier has a row; counts never grow from High to Low; the worst case at
	  once stays inside budget.drawCallShare of fx.budgets.drawCalls.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local GLINT_SIZES = { "Small", "Medium", "Large", "Parry" }
local ARC_SIZES = { "Medium", "Large" }
local LINE_SIZES = { "Medium", "Large" }
local SPEED_KINDS = { "Dodge", "Dash" }
local TIER_ORDER = { "High", "Medium", "Low" }
local BEAMS_PER_ARC = 4 -- two halves, each an outer Beam and a core Beam
local BEAM_KEYPOINT_LIMIT = 20 -- the engine's NumberSequence keypoint cap
local EASING_SAMPLES = 200

return function(ctx: Context): { string }
	local problems: { string } = {}
	local function check(ok: boolean, message: string, ...: any)
		if not ok then
			table.insert(problems, "accents: " .. string.format(message, ...))
		end
	end

	local accents = ctx.load("src/shared/data/accents")
	local palette = ctx.load("src/shared/data/palette")
	local fx = ctx.load("src/shared/data/fx")
	local combat = ctx.load("src/shared/data/combat")
	local ui = ctx.load("src/shared/data/ui")
	local Easing = ctx.load("src/shared/util/Easing")

	local function isNumber(value: any): boolean
		return typeof(value) == "number" and value == value
	end
	local function isInteger(value: any): boolean
		return isNumber(value) and value % 1 == 0
	end
	local function inRange(value: any, low: number, high: number): boolean
		return isNumber(value) and value >= low and value <= high
	end
	local function token(value: any, where: string)
		check(
			typeof(value) == "string" and palette.tokens[value] ~= nil,
			"%s '%s' is not a palette token",
			where,
			tostring(value)
		)
	end
	local function easing(value: any, where: string)
		local ok = typeof(value) == "string" and pcall(Easing.get, value)
		check(ok, "%s '%s' is not a util/Easing curve", where, tostring(value))
		check(value ~= "Linear" and value ~= "Hold", "%s must ease (never Linear or Hold)", where)
	end
	local function keys(value: any, where: string)
		local ok = typeof(value) == "table" and #value >= 2
		if ok then
			local previous = -1
			for index, key in value do
				local good = typeof(key) == "table" and isNumber(key[1]) and inRange(key[2], 0, 1) and key[1] > previous
				previous = if good then key[1] else previous
				ok = ok and good
				if index == 1 then
					ok = ok and key[1] == 0
				end
			end
			ok = ok and value[#value][1] == 1
		end
		check(ok, "%s must be {time, value} keys from time 0 to 1, ascending, values in 0..1", where)
	end

	local limits = accents.limits
	local frame = combat.hitStopFrameSeconds
	check(accents.frameSeconds == frame, "frameSeconds must be combat.hitStopFrameSeconds")
	check(limits.fullFrames == combat.hitStopFrames.Kill, "limits.fullFrames must be combat.hitStopFrames.Kill")
	check(
		isInteger(limits.maxFadeFrames) and limits.maxFadeFrames >= 1,
		"limits.maxFadeFrames must be a whole frame count"
	)
	local function full(frames: number, where: string)
		check(
			isNumber(frames) and frames <= limits.fullFrames,
			"%s is at full strength %s frames, past the %s-frame kill hit-stop",
			where,
			tostring(frames),
			limits.fullFrames
		)
	end
	local function fade(frames: any, where: string)
		check(
			isInteger(frames) and frames >= 1 and frames <= limits.maxFadeFrames,
			"%s fades over %s frames (1..%s)",
			where,
			tostring(frames),
			limits.maxFadeFrames
		)
	end
	local function frames(value: any, where: string)
		check(isInteger(value) and value >= 0, "%s must be a whole number of frames, got %s", where, tostring(value))
	end

	-- ------------------------------------------------------------------ glint
	local glint = accents.glint
	token(glint.coreToken, "glint.coreToken")
	check(
		typeof(glint.edgeTokens) == "table" and #glint.edgeTokens >= 1,
		"glint.edgeTokens needs the split-edge tokens"
	)
	for index, value in glint.edgeTokens or {} do
		token(value, ("glint.edgeTokens[%d]"):format(index))
		local direction = (glint.edgeDirections or {})[index]
		check(
			typeof(direction) == "table" and isNumber(direction[1]) and isNumber(direction[2]),
			"glint.edgeDirections[%d] must be {x, y} for each edge token",
			index
		)
	end
	check(inRange(glint.edgeTransparency, 0, 1), "glint.edgeTransparency must be in 0..1")
	check(inRange(glint.tintBlend, 0, 1), "glint.tintBlend must be in 0..1")
	check(typeof(glint.arms) == "table" and #glint.arms >= 2, "glint.arms needs at least the long cross")
	for index, arm in glint.arms or {} do
		check(inRange(arm.length, 1e-6, 1), "glint.arms[%d].length must be in (0, 1]", index)
		check(isNumber(arm.rotation), "glint.arms[%d].rotation must be degrees", index)
	end
	keys(glint.taper, "glint.taper")
	easing(glint.punchEasing, "glint.punchEasing")
	easing(glint.fadeEasing, "glint.fadeEasing")
	easing(glint.turnEasing, "glint.turnEasing")
	local peak = 0
	if typeof(glint.punchEasing) == "string" and pcall(Easing.get, glint.punchEasing) then
		for sample = 0, EASING_SAMPLES do
			peak = math.max(peak, Easing.evaluate(glint.punchEasing, sample / EASING_SAMPLES))
		end
	end
	check(
		isNumber(glint.canvasScale) and glint.canvasScale >= peak,
		"glint.canvasScale %s must leave room for the punch's overshoot (%.3f)",
		tostring(glint.canvasScale),
		peak
	)
	check(inRange(glint.jitterDegrees, 0, 45), "glint.jitterDegrees must be in 0..45")
	check(isNumber(glint.anchorSize) and glint.anchorSize > 0, "glint.anchorSize must be positive")
	check(isNumber(glint.maxDistance) and glint.maxDistance > 0, "glint.maxDistance must be positive")
	local glintTotals: { [string]: number } = {}
	for name, size in glint.sizes do
		local where = "glint.sizes." .. name
		check(isNumber(size.studs) and size.studs > 0, "%s.studs must be positive", where)
		check(isNumber(size.maxPixels) and size.maxPixels > 0, "%s.maxPixels must be positive", where)
		check(
			typeof(size.thickness) == "table"
				and inRange(size.thickness.scale, 0, 1)
				and isNumber(size.thickness.pixels)
				and size.thickness.pixels >= 1,
			"%s.thickness must be {scale 0..1, pixels >= 1}",
			where
		)
		check(
			isNumber(size.edgeOffsetPixels) and size.edgeOffsetPixels >= 1,
			"%s.edgeOffsetPixels must be at least 1",
			where
		)
		check(inRange(size.startScale, 1e-6, 1), "%s.startScale must be in (0, 1]", where)
		check(inRange(size.endScale, 1e-6, 1), "%s.endScale must be in (0, 1]", where)
		check(isInteger(size.punchFrames) and size.punchFrames >= 1, "%s.punchFrames must be at least one frame", where)
		frames(size.holdFrames, where .. ".holdFrames")
		full((size.punchFrames or 0) + (size.holdFrames or 0), where)
		fade(size.fadeFrames, where)
		check(
			isNumber(size.turnDegrees) and math.abs(size.turnDegrees) <= 45,
			"%s.turnDegrees must be a few degrees",
			where
		)
		glintTotals[name] = (size.punchFrames or 0) + (size.holdFrames or 0) + (size.fadeFrames or 0)
	end
	for _, name in GLINT_SIZES do
		check(glint.sizes[name] ~= nil, "glint.sizes is missing %s", name)
	end
	check(glint.sizes[glint.defaultSize] ~= nil, "glint.defaultSize '%s' is not a size", tostring(glint.defaultSize))
	for index = 2, #GLINT_SIZES do
		local smaller, larger = glint.sizes[GLINT_SIZES[index - 1]], glint.sizes[GLINT_SIZES[index]]
		if smaller ~= nil and larger ~= nil then
			check(
				larger.studs > smaller.studs and larger.maxPixels > smaller.maxPixels,
				"glint %s must be bigger than %s",
				GLINT_SIZES[index],
				GLINT_SIZES[index - 1]
			)
		end
	end
	if glintTotals.Parry ~= nil then
		for name, total in glintTotals do
			check(
				name == "Parry" or total < glintTotals.Parry,
				"the Parry glint must last longest (%s lasts %s frames, Parry %s)",
				name,
				total,
				glintTotals.Parry
			)
		end
	end

	-- ------------------------------------------------------------------ slash crescent
	local arc = accents.slashArc
	token(arc.defaultToken, "slashArc.defaultToken")
	token(arc.innerToken, "slashArc.innerToken")
	check(inRange(arc.innerWidthFraction, 1e-6, 1 - 1e-6), "slashArc.innerWidthFraction must be in (0, 1)")
	check(
		inRange(arc.outerTransparency, 0, 1) and inRange(arc.innerTransparency, 0, 1),
		"slashArc transparencies must be in 0..1"
	)
	check(
		inRange(arc.outerLightEmission, 0, 1) and inRange(arc.innerLightEmission, 0, 1),
		"slashArc light emissions must be in 0..1"
	)
	check(inRange(arc.lightInfluence, 0, 1), "slashArc.lightInfluence must be in 0..1")
	check(isNumber(arc.innerZOffset) and arc.innerZOffset >= 0, "slashArc.innerZOffset must put the core in front")
	check(inRange(arc.endSpread, 0, 0.5 - 1e-6), "slashArc.endSpread must be in [0, 0.5)")
	check(arc.faceAxis == "Y" or arc.faceAxis == "Z", 'slashArc.faceAxis must be "Y" or "Z"')
	easing(arc.wipeEasing, "slashArc.wipeEasing")
	check(inRange(arc.wipeSoftness, 1e-6, 1), "slashArc.wipeSoftness must be in (0, 1]")
	check(
		isInteger(arc.wipeKeys) and arc.wipeKeys >= 2 and arc.wipeKeys <= BEAM_KEYPOINT_LIMIT,
		"slashArc.wipeKeys must be 2..%d (a Beam's keypoint cap)",
		BEAM_KEYPOINT_LIMIT
	)
	-- The wipe front snaps to wipeSteps steps: at least 4 per frame of the longest wipe, so every
	-- frame of the wipe still moves it.
	local longestWipe = 0
	if typeof(arc.sizes) == "table" then
		for _, size in arc.sizes do
			if typeof(size) == "table" and isInteger(size.wipeFrames) then
				longestWipe = math.max(longestWipe, size.wipeFrames)
			end
		end
	end
	check(
		isInteger(arc.wipeSteps) and arc.wipeSteps >= math.max(1, 4 * longestWipe),
		"slashArc.wipeSteps %s must be a whole number, at least 4 per frame of the longest wipe (%d)",
		tostring(arc.wipeSteps),
		4 * longestWipe
	)
	check(inRange(arc.innerLead, 0, 1 - 1e-6), "slashArc.innerLead must be in [0, 1)")
	-- The turn toward the camera: a face more than faceDegrees off turns by at most maxDegrees, so
	-- a full turn from edge-on (90) leaves it no nearer than faceDegrees and the swing plane reads.
	local tilt = arc.tilt
	check(typeof(tilt) == "table", "slashArc.tilt must be {faceDegrees, maxDegrees, minPlaneSine}")
	if typeof(tilt) == "table" then
		check(isNumber(tilt.maxDegrees) and tilt.maxDegrees > 0, "slashArc.tilt.maxDegrees must be above 0")
		check(
			isNumber(tilt.faceDegrees) and tilt.faceDegrees > 0 and tilt.faceDegrees < 90,
			"slashArc.tilt.faceDegrees must be above 0 and below 90"
		)
		check(
			not isNumber(tilt.maxDegrees) or not isNumber(tilt.faceDegrees) or 90 - tilt.maxDegrees >= tilt.faceDegrees,
			"slashArc.tilt.maxDegrees %s turns an edge-on crescent nearer the camera than faceDegrees %s",
			tostring(tilt.maxDegrees),
			tostring(tilt.faceDegrees)
		)
		check(
			isNumber(tilt.minPlaneSine) and tilt.minPlaneSine > 0 and tilt.minPlaneSine < 1,
			"slashArc.tilt.minPlaneSine must be above 0 and below 1 (the sine of a swing's least angle to its radius)"
		)
	end
	check(isNumber(arc.hostSize) and arc.hostSize > 0, "slashArc.hostSize must be positive")
	for name, size in arc.sizes do
		local where = "slashArc.sizes." .. name
		check(isNumber(size.length) and size.length > 0, "%s.length must be positive", where)
		check(isNumber(size.bow) and size.bow > 0, "%s.bow must be positive (it is a crescent)", where)
		check(isNumber(size.width) and size.width > 0, "%s.width must be positive", where)
		frames(size.holdFrames, where .. ".holdFrames")
		full(1 + (size.holdFrames or 0), where) -- the snap frame, then the hold
		fade(size.wipeFrames, where)
	end
	for _, name in ARC_SIZES do
		check(arc.sizes[name] ~= nil, "slashArc.sizes is missing %s", name)
	end
	check(arc.sizes[arc.defaultSize] ~= nil, "slashArc.defaultSize '%s' is not a size", tostring(arc.defaultSize))
	if arc.sizes.Medium ~= nil and arc.sizes.Large ~= nil then
		check(
			arc.sizes.Large.length > arc.sizes.Medium.length and arc.sizes.Large.width > arc.sizes.Medium.width,
			"the Large crescent must be longer and wider than the Medium one"
		)
	end

	-- ------------------------------------------------------------------ slash line
	local line = accents.slashLine
	token(line.coreToken, "slashLine.coreToken")
	check(
		typeof(line.edgeTokens) == "table" and #line.edgeTokens >= 1,
		"slashLine.edgeTokens needs the split-edge tokens"
	)
	for index, value in line.edgeTokens or {} do
		token(value, ("slashLine.edgeTokens[%d]"):format(index))
		check(
			isNumber((line.edgeSides or {})[index]),
			"slashLine.edgeSides[%d] must be a side for each edge token",
			index
		)
	end
	check(
		inRange(line.coreTransparency, 0, 1) and inRange(line.edgeTransparency, 0, 1),
		"slashLine transparencies must be in 0..1"
	)
	check(
		inRange(line.lightEmission, 0, 1) and inRange(line.lightInfluence, 0, 1),
		"slashLine light numbers must be in 0..1"
	)
	check(isNumber(line.coreZOffset) and line.coreZOffset >= 0, "slashLine.coreZOffset must put the core in front")
	check(inRange(line.endFade, 1e-6, 0.5 - 1e-6), "slashLine.endFade must be in (0, 0.5)")
	easing(line.growEasing, "slashLine.growEasing")
	easing(line.thinEasing, "slashLine.thinEasing")
	check(typeof(line.faceCamera) == "boolean", "slashLine.faceCamera must be a boolean")
	for name, size in line.sizes do
		local where = "slashLine.sizes." .. name
		check(isNumber(size.length) and size.length > 0, "%s.length must be positive", where)
		check(isNumber(size.width) and size.width > 0, "%s.width must be positive", where)
		check(isNumber(size.edgeOffset) and size.edgeOffset > 0, "%s.edgeOffset must be positive", where)
		check(inRange(size.startLength, 1e-6, 1), "%s.startLength must be in (0, 1]", where)
		frames(size.growFrames, where .. ".growFrames")
		frames(size.holdFrames, where .. ".holdFrames")
		full((size.growFrames or 0) + (size.holdFrames or 0), where)
		fade(size.thinFrames, where)
	end
	for _, name in LINE_SIZES do
		check(line.sizes[name] ~= nil, "slashLine.sizes is missing %s", name)
	end
	check(line.sizes[line.defaultSize] ~= nil, "slashLine.defaultSize '%s' is not a size", tostring(line.defaultSize))
	if line.sizes.Medium ~= nil and line.sizes.Large ~= nil then
		check(
			line.sizes.Large.length > line.sizes.Medium.length,
			"the Large slash line must be longer than the Medium one"
		)
	end

	-- ------------------------------------------------------------------ speed lines
	local speed = accents.speedLines
	token(speed.token, "speedLines.token")
	keys(speed.gradient, "speedLines.gradient")
	if typeof(speed.gradient) == "table" and typeof(speed.gradient[1]) == "table" then
		check(speed.gradient[1][2] == 1, "speedLines.gradient must fade each line's inner end to nothing")
	end
	easing(speed.inEasing, "speedLines.inEasing")
	easing(speed.outEasing, "speedLines.outEasing")
	check(inRange(speed.clearFraction, 1e-6, 1 - 1e-6), "speedLines.clearFraction must be in (0, 1)")
	check(
		isNumber(speed.clearFraction) and speed.clearFraction >= 1 / 3 - 1e-9,
		"speedLines.clearFraction must keep at least the middle third clear"
	)
	check(isInteger(speed.displayOrder), "speedLines.displayOrder must be an integer")
	check(
		isNumber(speed.displayOrder) and speed.displayOrder < ui.hud.displayOrder,
		"speedLines.displayOrder must sit under the HUD (%s)",
		ui.hud.displayOrder
	)
	local reference = speed.referenceScreen
	check(
		typeof(reference) == "table"
			and isNumber(reference.width)
			and isNumber(reference.height)
			and reference.width > 0
			and reference.height > 0,
		"speedLines.referenceScreen must be {width, height} in pixels"
	)
	check(inRange(speed.maxCoverage, 1e-6, 0.05), "speedLines.maxCoverage must be in (0, 0.05]: lines, never a flash")
	local highScale = (accents.quality.High or {}).speedLineScale or 1
	for name, kind in speed.kinds do
		local where = "speedLines.kinds." .. name
		check(isNumber(kind.seconds) and kind.seconds > 0, "%s.seconds must be positive", where)
		local total = (kind.seconds or 0) / frame
		check(isInteger(kind.count) and kind.count >= 1, "%s.count must be at least one line", where)
		check(isInteger(kind.inFrames) and kind.inFrames >= 1, "%s.inFrames must be at least one frame", where)
		fade(kind.outFrames, where)
		check(
			(kind.inFrames or 0) + (kind.outFrames or 0) <= total + 1e-6,
			"%s rushes in and out over more than its %.1f frames",
			where,
			total
		)
		full(total - (kind.outFrames or 0), where)
		check(inRange(kind.transparency, 0, 1), "%s.transparency must be in 0..1", where)
		check(
			isNumber(kind.thicknessPixels) and kind.thicknessPixels >= 1,
			"%s.thicknessPixels must be at least 1",
			where
		)
		local reach = kind.innerReach
		check(
			typeof(reach) == "table"
				and inRange(reach.min, 0, 1)
				and inRange(reach.max, 0, 1 - 1e-6)
				and reach.min <= reach.max,
			"%s.innerReach must be 0 <= min <= max < 1 (0 is the middle third's edge)",
			where
		)
		if typeof(reach) == "table" and isNumber(reach.max) then
			check(
				inRange(kind.startReach, reach.max, 1 - 1e-6),
				"%s.startReach must sit between innerReach.max and the edge: the lines rush in",
				where
			)
		end
		check(isNumber(kind.overshoot) and kind.overshoot >= 1, "%s.overshoot must reach the screen edge (>= 1)", where)
		check(inRange(kind.angleJitter, 0, 0.5 - 1e-6), "%s.angleJitter must be in [0, 0.5) so rays never cross", where)
		if typeof(reference) == "table" and isNumber(reference.width) and isNumber(reference.height) then
			-- Upper bound: every line as long as the half-diagonal past the edge.
			local longest = math.sqrt(reference.width ^ 2 + reference.height ^ 2) * 0.5 * (kind.overshoot or 1)
			local lines = math.floor((kind.count or 0) * highScale + 0.5)
			local coverage = lines * (kind.thicknessPixels or 0) * longest / (reference.width * reference.height)
			check(
				coverage <= (speed.maxCoverage or 0),
				"%s covers up to %.3f of the screen, past maxCoverage %s",
				where,
				coverage,
				tostring(speed.maxCoverage)
			)
		end
	end
	for _, name in SPEED_KINDS do
		check(speed.kinds[name] ~= nil, "speedLines.kinds is missing %s", name)
	end
	check(
		speed.kinds[speed.defaultKind] ~= nil,
		"speedLines.defaultKind '%s' is not a kind",
		tostring(speed.defaultKind)
	)
	if speed.kinds.Dodge ~= nil then
		check(
			speed.kinds.Dodge.seconds == combat.dodgeDuration,
			"speedLines.kinds.Dodge.seconds must be combat.dodgeDuration"
		)
	end

	-- ------------------------------------------------------------------ swing direction
	local swing = accents.swing
	check(isInteger(swing.samples) and swing.samples >= 2, "swing.samples must be at least 2")
	check(
		isNumber(swing.minTravel)
			and isNumber(swing.maxTravel)
			and swing.minTravel > 0
			and swing.minTravel < swing.maxTravel,
		"swing needs 0 < minTravel < maxTravel"
	)
	-- A late HitConfirmed (the round trip, the lag allowance) still finds the swing; the next
	-- swing of a basic chain (within a second) never finds this one.
	check(
		isNumber(swing.memorySeconds)
			and swing.memorySeconds < 1
			and swing.memorySeconds > (if isInteger(swing.samples) then swing.samples else 0) * frame,
		"swing.memorySeconds %s must be longer than the %s-sample ring and below 1 second",
		tostring(swing.memorySeconds),
		tostring(swing.samples)
	)
	check(
		isInteger(swing.snapFrames)
			and swing.snapFrames >= 1
			and isNumber(swing.memorySeconds)
			and swing.snapFrames * frame < swing.memorySeconds,
		"swing.snapFrames %s must be a whole number of frames, at least 1, read well inside swing.memorySeconds",
		tostring(swing.snapFrames)
	)
	check(isNumber(swing.sampleDistance) and swing.sampleDistance > 0, "swing.sampleDistance must be above 0")

	-- ------------------------------------------------------------------ quality and budget
	for tierName in fx.quality do
		local tier = accents.quality[tierName]
		check(tier ~= nil, "quality.%s is missing (fx.luau has the tier)", tierName)
		if tier ~= nil then
			for _, field in { "glints", "arcs", "lines", "arcSegments" } do
				check(
					isInteger(tier[field]) and tier[field] >= 1,
					"quality.%s.%s must be a whole count of at least 1",
					tierName,
					field
				)
			end
			check(inRange(tier.glintEdgeScale, 0, 1), "quality.%s.glintEdgeScale must be in 0..1", tierName)
			check(inRange(tier.speedLineScale, 1e-6, 1), "quality.%s.speedLineScale must be in (0, 1]", tierName)
			check(typeof(tier.lineEdges) == "boolean", "quality.%s.lineEdges must be a boolean", tierName)
		end
	end
	for tierName in accents.quality do
		check(fx.quality[tierName] ~= nil, "quality.%s is not an fx.luau tier", tierName)
	end
	for index = 2, #TIER_ORDER do
		local higher, lower = accents.quality[TIER_ORDER[index - 1]], accents.quality[TIER_ORDER[index]]
		if higher ~= nil and lower ~= nil then
			for _, field in { "glints", "arcs", "lines", "arcSegments", "glintEdgeScale", "speedLineScale" } do
				check(
					not isNumber(lower[field]) or not isNumber(higher[field]) or lower[field] <= higher[field],
					"quality.%s.%s is above quality.%s's",
					TIER_ORDER[index],
					field,
					TIER_ORDER[index - 1]
				)
			end
		end
	end
	check(inRange(accents.budget.drawCallShare, 1e-6, 0.1), "budget.drawCallShare must be in (0, 0.1]")
	for tierName, tier in accents.quality do
		local edges = #(glint.edgeTokens or {})
		local glintCalls = (tier.glints or 0)
			* (1 + (if (tier.glintEdgeScale or 0) > 0 then edges else 0))
			* #(glint.arms or {})
		local arcCalls = (tier.arcs or 0) * BEAMS_PER_ARC
		local lineCalls = (tier.lines or 0) * (1 + (if tier.lineEdges then #(line.edgeTokens or {}) else 0))
		local speedCalls = 0
		for _, kind in speed.kinds do
			speedCalls = math.max(speedCalls, math.floor((kind.count or 0) * (tier.speedLineScale or 0) + 0.5))
		end
		local worst = glintCalls + arcCalls + lineCalls + speedCalls
		local allowed = fx.budgets.drawCalls * (accents.budget.drawCallShare or 0)
		check(
			worst <= allowed,
			"quality.%s can draw %s accent pieces at once, past %.0f (budget.drawCallShare of fx.budgets.drawCalls)",
			tierName,
			worst,
			allowed
		)
	end

	-- ------------------------------------------------------------------ moments.luau names
	local okMoments, moments = pcall(ctx.load, "src/shared/data/moments")
	if okMoments and typeof(moments) == "table" then
		-- An idle blade is sampled as far as any moment's accents show, so a far swing's snap
		-- still starts from the pose before it. (A missing or non-positive distance is reported
		-- once, above.)
		local distance = swing.sampleDistance
		if isNumber(distance) and distance > 0 then
			check(
				not isNumber(moments.accentRange) or distance >= moments.accentRange,
				"swing.sampleDistance %s must reach moments.accentRange %s",
				tostring(distance),
				tostring(moments.accentRange)
			)
			if typeof(moments.rows) == "table" then
				for name, row in moments.rows do
					local range = if typeof(row) == "table" then row.range else nil
					check(
						not isNumber(range) or distance >= range,
						"swing.sampleDistance %s must reach moments.rows.%s.range %s",
						tostring(distance),
						tostring(name),
						tostring(range)
					)
				end
			end
		end
		local fields = {
			glint = { table = glint.sizes, label = "glint size" },
			glintSize = { table = glint.sizes, label = "glint size" },
			slashArc = { table = arc.sizes, label = "slash crescent size" },
			arcSize = { table = arc.sizes, label = "slash crescent size" },
			slashLine = { table = line.sizes, label = "slash line size" },
			lineSize = { table = line.sizes, label = "slash line size" },
			speedLines = { table = speed.kinds, label = "speed-line kind" },
			speedLineKind = { table = speed.kinds, label = "speed-line kind" },
		}
		local seen: { [any]: boolean } = {}
		local function walk(node: any, path: string)
			if typeof(node) ~= "table" or seen[node] then
				return
			end
			seen[node] = true
			for key, value in node do
				local here = path .. "." .. tostring(key)
				local field = if typeof(key) == "string" then fields[key] else nil
				if field ~= nil then
					local name = value
					if typeof(value) == "table" then
						name = value.size or value.kind
					end
					if typeof(name) == "string" then
						check(
							field.table[name] ~= nil,
							"moments%s names %s '%s', which accents.luau does not have",
							here,
							field.label,
							name
						)
					end
				end
				if typeof(value) == "table" then
					walk(value, here)
				end
			end
		end
		walk(moments, "")
	end

	return problems
end
