--!strict
--[[
	Validates src/shared/data/impact.luau: the impact-frame looks, the sequences and the flash
	safety limits.

	- Every look's tokens are palette tokens, and a look that draws no figures and no strokes is
	  dark (a plain bright frame would be a bare flash with nothing in it).
	- Every sequence names a hit-stop tier from combat.hitStopFrames and a whole rank of at least 1
	  (no two alike), its steps name real looks with whole positive frame counts, and its frames
	  fit inside that tier's hit-stop.
	- Every sequence's flash cost (ImpactSequence.flashCostOf: the worst of its field, figure and
	  stroke regions, each measured from its palette color's relative luminance) is at most the
	  hard limit.
	- The hard limit: flash.maxPerWindow is at most 3, flash.windowSeconds at least 1, and a
	  transition is a change of at most 0.1 relative luminance (no data change may allow more than
	  3 full-screen flashes in a second, nor stop counting one).
	- The soft dim is low (opacity at most DIM_MAX_OPACITY), eased in over at least 2 frames and
	  out over at least as many, with known easings, and charged: when its dip over the reference
	  scene (ImpactSequence.dimDip, the sRGB blend) is a transition, its flashCost is at least 1,
	  and never above the hard limit. Reduce flashing allows a whole reduced.maxPerWindow of at
	  least 1 dims a window, costing fewer flashes than flash.maxPerWindow.
	- The overlay sits above the HUD, the silhouette and stroke numbers are sane, and every fx
	  quality tier has a row that draws the figures with a whole part cap of at least 1.
	- The overlay's staleness limit (overlay.staleFrames) lets a 30 fps first frame play (at least
	  MIN_STALE_FRAMES) and is no longer than any sequence's hit-stop.
]]

local roblox = require("@lune/roblox")

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

-- Hard limits (photosensitivity): not tunables, so they live here and not in the data.
local MAX_FLASHES_PER_WINDOW = 3
local MIN_WINDOW_SECONDS = 1
local MAX_TRANSITION_DELTA = 0.1 -- WCAG 2.x: 10% of the maximum relative luminance
local DIM_MAX_OPACITY = 0.4
local DIM_MIN_FADE_IN_FRAMES = 2
-- A look with nothing drawn on its field may be no brighter than this (the black beat is ink).
local PLAIN_LOOK_MAX_LUMINANCE = 0.2
-- A 30 fps first frame comes at most this many 60 fps frames after the hit: the staleness limit
-- must still let it play.
local MIN_STALE_FRAMES = 2

local function isWhole(value: any): boolean
	return typeof(value) == "number" and value == value and value % 1 == 0
end

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

return function(ctx: Context): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "impact: " .. message)
		end
	end

	local impact = ctx.load("src/shared/data/impact")
	local palette = ctx.load("src/shared/data/palette")
	local combat = ctx.load("src/shared/data/combat")
	local ui = ctx.load("src/shared/data/ui")
	local fx = ctx.load("src/shared/data/fx")
	local Easing = ctx.load("src/shared/util/Easing")
	local ImpactSequence = ctx.load("src/client/fx/ImpactSequence")

	local function isToken(value: any): boolean
		return typeof(value) == "string" and palette.tokens[value] ~= nil
	end
	local function isEasing(value: any): boolean
		return typeof(value) == "string" and (pcall(Easing.get, value))
	end

	-- Looks
	local looks = impact.looks
	check(typeof(looks) == "table", "looks must be a table")
	if typeof(looks) ~= "table" then
		return problems
	end
	for _, name in sortedKeys(looks) do
		local look = looks[name]
		check(
			isToken(look.background),
			("looks.%s.background '%s' is not a palette token"):format(name, tostring(look.background))
		)
		check(
			look.figures == nil or isToken(look.figures),
			("looks.%s.figures '%s' is not a palette token"):format(name, tostring(look.figures))
		)
		check(typeof(look.strokes) == "boolean", ("looks.%s.strokes must be a boolean"):format(name))
		if look.figures == nil and look.strokes ~= true and isToken(look.background) then
			local luminance = ImpactSequence.luminanceOf(look.background) :: number
			check(
				luminance <= PLAIN_LOOK_MAX_LUMINANCE,
				("looks.%s draws nothing on a bright field (relative luminance %.2f, at most %.2f): a bare flash"):format(
					name,
					luminance,
					PLAIN_LOOK_MAX_LUMINANCE
				)
			)
		end
	end

	-- Flash budget: the hard limit first, so a looser table can never pass.
	local flash = impact.flash
	check(
		isWhole(flash.maxPerWindow) and flash.maxPerWindow >= 1 and flash.maxPerWindow <= MAX_FLASHES_PER_WINDOW,
		("flash.maxPerWindow %s must be a whole number from 1 to %d"):format(
			tostring(flash.maxPerWindow),
			MAX_FLASHES_PER_WINDOW
		)
	)
	check(
		typeof(flash.windowSeconds) == "number" and flash.windowSeconds >= MIN_WINDOW_SECONDS,
		("flash.windowSeconds %s must be at least %d"):format(tostring(flash.windowSeconds), MIN_WINDOW_SECONDS)
	)
	check(
		typeof(flash.transitionDelta) == "number"
			and flash.transitionDelta > 0
			and flash.transitionDelta <= MAX_TRANSITION_DELTA,
		("flash.transitionDelta %s must be above 0 and at most %s (a smaller change still counts)"):format(
			tostring(flash.transitionDelta),
			tostring(MAX_TRANSITION_DELTA)
		)
	)
	local maxCost =
		math.min(if typeof(flash.maxPerWindow) == "number" then flash.maxPerWindow else 0, MAX_FLASHES_PER_WINDOW)

	-- Sequences
	check(impact.frameSeconds == combat.hitStopFrameSeconds, "frameSeconds must point at combat.hitStopFrameSeconds")
	local ranks: { [number]: string } = {}
	for _, name in sortedKeys(impact.sequences) do
		local sequence = impact.sequences[name]
		local tierFrames = combat.hitStopFrames[sequence.tier]
		check(
			tierFrames ~= nil,
			("sequences.%s.tier '%s' is not a combat.hitStopFrames tier"):format(name, tostring(sequence.tier))
		)
		check(
			isWhole(sequence.rank) and sequence.rank >= 1,
			("sequences.%s.rank %s must be a whole number of at least 1"):format(name, tostring(sequence.rank))
		)
		if isWhole(sequence.rank) then
			local other = ranks[sequence.rank]
			check(
				other == nil,
				("sequences.%s.rank %s is also sequences.%s's: which one replaces the other?"):format(
					name,
					tostring(sequence.rank),
					tostring(other)
				)
			)
			ranks[sequence.rank] = name
		end
		check(typeof(sequence.steps) == "table" and #sequence.steps > 0, ("sequences.%s has no steps"):format(name))
		if typeof(sequence.steps) ~= "table" then
			continue
		end
		local frames = 0
		for index, step in sequence.steps do
			check(
				looks[step.look] ~= nil,
				("sequences.%s.steps[%d] look '%s' is not a look"):format(name, index, tostring(step.look))
			)
			check(
				isWhole(step.frames) and step.frames >= 1,
				("sequences.%s.steps[%d] frames %s must be a whole number of at least 1"):format(
					name,
					index,
					tostring(step.frames)
				)
			)
			if typeof(step.frames) == "number" then
				frames += step.frames
			end
		end
		if tierFrames ~= nil then
			check(
				frames <= tierFrames,
				("sequences.%s holds %d frames, more than the %s hit-stop's %d"):format(
					name,
					frames,
					sequence.tier,
					tierFrames
				)
			)
		end
		local cost = ImpactSequence.flashCostOf(sequence, looks)
		check(
			cost <= maxCost,
			("sequences.%s costs %d flashes, more than flash.maxPerWindow allows (%d)"):format(name, cost, maxCost)
		)
	end

	-- The soft dim
	local dim = impact.reduced
	check(isToken(dim.token), ("reduced.token '%s' is not a palette token"):format(tostring(dim.token)))
	check(
		typeof(dim.opacity) == "number" and dim.opacity > 0 and dim.opacity <= DIM_MAX_OPACITY,
		("reduced.opacity %s must be above 0 and at most %s (a soft dim, not a flash)"):format(
			tostring(dim.opacity),
			tostring(DIM_MAX_OPACITY)
		)
	)
	check(
		typeof(dim.fadeInFrames) == "number" and dim.fadeInFrames >= DIM_MIN_FADE_IN_FRAMES,
		("reduced.fadeInFrames %s must be at least %d (never an instant change)"):format(
			tostring(dim.fadeInFrames),
			DIM_MIN_FADE_IN_FRAMES
		)
	)
	check(
		typeof(dim.fadeOutFrames) == "number"
			and typeof(dim.fadeInFrames) == "number"
			and dim.fadeOutFrames >= dim.fadeInFrames,
		"reduced.fadeOutFrames must be at least reduced.fadeInFrames (out over more)"
	)
	check(typeof(dim.holdFrames) == "number" and dim.holdFrames >= 0, "reduced.holdFrames must be 0 or more")
	check(
		isToken(dim.referenceScene),
		("reduced.referenceScene '%s' is not a palette token"):format(tostring(dim.referenceScene))
	)
	check(
		isWhole(dim.flashCost) and dim.flashCost >= 0 and dim.flashCost <= maxCost,
		("reduced.flashCost %s must be a whole number from 0 to %d"):format(tostring(dim.flashCost), maxCost)
	)
	-- ImpactFrames reads it as a count; Reduce flashing must flash less than the full budget.
	check(
		isWhole(dim.maxPerWindow) and dim.maxPerWindow >= 1,
		("reduced.maxPerWindow %s must be a whole number of at least 1"):format(tostring(dim.maxPerWindow))
	)
	local costOk = isWhole(dim.flashCost) and dim.flashCost >= 0 and dim.flashCost <= maxCost
	if isWhole(dim.maxPerWindow) and costOk and typeof(flash.maxPerWindow) == "number" then
		check(
			dim.maxPerWindow * dim.flashCost < flash.maxPerWindow,
			("reduced.maxPerWindow %d dims cost %d flashes, not fewer than flash.maxPerWindow (%d): Reduce flashing must flash less"):format(
				dim.maxPerWindow,
				dim.maxPerWindow * dim.flashCost,
				flash.maxPerWindow
			)
		)
	end
	if isToken(dim.referenceScene) and isToken(dim.token) and typeof(dim.opacity) == "number" then
		local dip = ImpactSequence.dimDip(dim.referenceScene, dim.opacity, dim.token)
		local delta = if typeof(flash.transitionDelta) == "number"
			then math.min(flash.transitionDelta, MAX_TRANSITION_DELTA)
			else MAX_TRANSITION_DELTA
		check(
			dip < delta or (isWhole(dim.flashCost) and dim.flashCost >= 1),
			("reduced dips the %s scene by %.2f relative luminance, a flash: its flashCost must be at least 1"):format(
				tostring(dim.referenceScene),
				dip
			)
		)
	end
	check(isEasing(dim.fadeInEasing), ("reduced.fadeInEasing '%s' is not an easing"):format(tostring(dim.fadeInEasing)))
	check(
		isEasing(dim.fadeOutEasing),
		("reduced.fadeOutEasing '%s' is not an easing"):format(tostring(dim.fadeOutEasing))
	)

	-- The setting
	check(
		typeof(impact.reduceFlashingAttribute) == "string" and impact.reduceFlashingAttribute ~= "",
		"reduceFlashingAttribute must be a non-empty string"
	)
	check(typeof(impact.reduceFlashingDefault) == "boolean", "reduceFlashingDefault must be a boolean")

	-- The overlay
	local overlay = impact.overlay
	check(
		typeof(overlay.displayOrder) == "number" and overlay.displayOrder > ui.hud.displayOrder,
		"overlay.displayOrder must sit above the HUD's (ui.hud.displayOrder)"
	)
	check(typeof(overlay.screenGuiName) == "string" and overlay.screenGuiName ~= "", "overlay.screenGuiName is missing")
	check(
		typeof(overlay.renderStepName) == "string" and overlay.renderStepName ~= "",
		"overlay.renderStepName is missing"
	)
	for _, layer in { "background", "figures", "strokes" } do
		check(typeof(overlay.zIndex[layer]) == "number", ("overlay.zIndex.%s is missing"):format(layer))
	end
	check(
		overlay.zIndex.background < overlay.zIndex.figures and overlay.zIndex.figures <= overlay.zIndex.strokes,
		"overlay.zIndex must stack background < figures <= strokes"
	)
	-- The staleness limit: a 30 fps first frame still plays, and no sequence starts after the
	-- hit-stop that freezes its pose.
	local stale = overlay.staleFrames
	local staleOk = typeof(stale) == "number" and stale == stale and stale >= MIN_STALE_FRAMES
	check(
		staleOk,
		("overlay.staleFrames %s must be at least %d: a 30 fps first frame comes %d frames after the hit and must still play"):format(
			tostring(stale),
			MIN_STALE_FRAMES,
			MIN_STALE_FRAMES
		)
	)
	if staleOk then
		for _, name in sortedKeys(impact.sequences) do
			local sequence = impact.sequences[name]
			local tierFrames = combat.hitStopFrames[sequence.tier]
			if typeof(tierFrames) == "number" then
				check(
					stale <= tierFrames,
					("overlay.staleFrames %s is past sequences.%s's %s hit-stop (%d frames): it could start after the pose it freezes let go"):format(
						tostring(stale),
						name,
						tostring(sequence.tier),
						tierFrames
					)
				)
			end
		end
	end
	check(isToken(impact.viewport.ambientToken), "viewport.ambientToken is not a palette token")
	check(isToken(impact.viewport.lightToken), "viewport.lightToken is not a palette token")

	-- Silhouettes
	local silhouette = impact.silhouette
	check(isToken(silhouette.flatToken), "silhouette.flatToken is not a palette token")
	local okMaterial, material = pcall(function()
		return (roblox.Enum.Material :: any)[silhouette.material]
	end)
	check(
		okMaterial and material ~= nil,
		("silhouette.material '%s' is not an Enum.Material"):format(tostring(silhouette.material))
	)
	check(
		isWhole(silhouette.maxRigs) and silhouette.maxRigs >= 1,
		"silhouette.maxRigs must be a whole number of at least 1"
	)
	check(
		isWhole(silhouette.poolCap) and silhouette.poolCap >= 0,
		"silhouette.poolCap must be a whole number, 0 or more"
	)
	check(typeof(silhouette.excludeNames) == "table", "silhouette.excludeNames must be a list")
	check(typeof(silhouette.skipWrapLayers) == "boolean", "silhouette.skipWrapLayers must be a boolean")

	-- Strokes
	local strokes = impact.strokes
	check(isToken(strokes.token), "strokes.token is not a palette token")
	check(
		isWhole(strokes.count.min)
			and isWhole(strokes.count.max)
			and strokes.count.min >= 1
			and strokes.count.min <= strokes.count.max,
		"strokes.count must be whole numbers with 1 <= min <= max"
	)
	for _, key in { "width", "length" } do
		local range = strokes[key]
		check(range.min > 0 and range.min <= range.max, ("strokes.%s must satisfy 0 < min <= max"):format(key))
	end
	check(
		strokes.spread >= 0 and strokes.slide >= 0 and strokes.laneJitter >= 0,
		"strokes.spread, slide and laneJitter must be 0 or more"
	)
	check(strokes.jitterDegrees >= 0, "strokes.jitterDegrees must be 0 or more")
	check(strokes.fallbackAspect > 0, "strokes.fallbackAspect must be positive")
	local taper = strokes.taper
	check(typeof(taper) == "table" and #taper >= 2, "strokes.taper needs at least two keys")
	if typeof(taper) == "table" and #taper >= 2 then
		check(taper[1][1] == 0 and taper[#taper][1] == 1, "strokes.taper must run from time 0 to time 1")
		for index, key in taper do
			check(key[2] >= 0 and key[2] <= 1, ("strokes.taper[%d] transparency must be in 0..1"):format(index))
			if index > 1 then
				check(key[1] > taper[index - 1][1], ("strokes.taper[%d] time must rise"):format(index))
			end
		end
	end

	-- Quality
	for _, tier in sortedKeys(fx.quality) do
		local row = impact.quality[tier]
		check(
			typeof(row) == "table" and typeof(row.silhouettes) == "boolean" and typeof(row.strokes) == "boolean",
			("quality.%s needs silhouettes and strokes booleans"):format(tier)
		)
		if typeof(row) == "table" then
			check(
				row.silhouettes == true,
				("quality.%s must draw the silhouettes: an impact frame without its figures is a bare blink"):format(
					tier
				)
			)
			check(
				isWhole(row.maxPartsPerRig) and row.maxPartsPerRig >= 1,
				("quality.%s.maxPartsPerRig must be a whole number of at least 1"):format(tier)
			)
		end
	end

	return problems
end
