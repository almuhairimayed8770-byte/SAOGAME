--!strict
--[[
	ImpactSequence (pure, no Instances): the timing and the flash cost of the impact sequences in
	impact.luau, and the soft dim's opacity curve.

	Timing: a sequence is a list of looks, each held for some 60 fps frames. `frames(name)` gives
	each look its start and finish in seconds (frames x combat.hitStopFrameSeconds); the overlay
	shows each look for at least one drawn frame and never past the hit-stop it rides on
	(`capSeconds`), so a slow frame neither stretches the sequence nor drops a look.

	Flash cost: a look paints three regions, the field (its background), the figures (the
	silhouettes, or the field where it draws none) and the strokes (the ink strokes, or the field
	where it draws none). Along Scene -> look 1 -> ... -> look n -> Scene each region makes a
	transition wherever its relative luminance (from the palette color, WCAG 2.x) changes by at
	least impact.flash.transitionDelta; the scene is unknown, so leaving it and coming back always
	count. A flash is a pair of opposing transitions, so a region costs ceil(transitions / 2) and a
	sequence costs its worst region. Final (Dark) costs 1; Kill (Black, Dark, Ink) costs 2: the
	figures go ink, white, ink, so four transitions; Parry (Inverted) costs 1. `costOfLooks` scores
	any path, so a sequence that replaces another mid-way is charged for what was really shown.

	The `...Of` functions take the data as arguments so the impact validator can score a table
	that is not the live one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Impact = require(Shared.data.impact)
local Combat = require(Shared.data.combat)
local Palette = require(Shared.data.palette)
local Easing = require(Shared.util.Easing)

-- One look of a sequence with its place on the clock.
export type Frame = {
	look: string,
	frames: number,
	start: number, -- seconds after the sequence starts
	finish: number, -- seconds; the next look starts here
}

-- The regions a look paints, in the order the flash count reads them.
local REGIONS = { "background", "figures", "strokes" }

local ImpactSequence = {}

local function sequenceOf(name: string): Impact.Sequence
	local sequence = Impact.sequences[name]
	if sequence == nil then
		error(("ImpactSequence: unknown sequence '%s'"):format(tostring(name)))
	end
	return sequence
end

local function linear(channel: number): number
	local curve = Impact.flash.luminance
	if channel <= curve.linearBelow then
		return channel / curve.linearDivisor
	end
	return ((channel + curve.offset) / curve.divisor) ^ curve.gamma
end

local function luminanceOfRgb(rgb: { number }): number
	local weights = Impact.flash.luminance.weights
	return weights[1] * linear(rgb[1]) + weights[2] * linear(rgb[2]) + weights[3] * linear(rgb[3])
end

--- The relative luminance (WCAG 2.x, 0..1) of a palette token; nil for a name that is not one.
function ImpactSequence.luminanceOf(token: string?): number?
	if typeof(token) ~= "string" then
		return nil
	end
	local rgb = (Palette.tokens :: any)[token]
	if rgb == nil then
		return nil
	end
	return luminanceOfRgb(rgb)
end

--- The palette token each region of a look shows: { background, figures, strokes }.
function ImpactSequence.regionsOf(look: Impact.Look): { string }
	local background = look.background
	return {
		background,
		look.figures or background,
		if look.strokes then Impact.strokes.token else background,
	}
end

--- The look names of a sequence table, one per step that holds a frame, in order.
function ImpactSequence.looksOf(sequence: Impact.Sequence): { string }
	local names: { string } = {}
	for _, step in sequence.steps do
		if step.frames > 0 then
			table.insert(names, step.look)
		end
	end
	return names
end

--- Transitions each region (background, figures, strokes) makes along Scene -> the looks ->
--- Scene; an unknown look counts as unknown luminance, so it never hides a change.
function ImpactSequence.regionTransitions(names: { string }, looks: { [string]: Impact.Look }): { number }
	local counts = { 0, 0, 0 }
	if #names == 0 then
		return counts
	end
	local delta = Impact.flash.transitionDelta
	for region = 1, #REGIONS do
		local previous: number? = nil -- the scene: unknown
		local transitions = 0
		for index, name in names do
			local look = looks[name]
			local current = if look ~= nil
				then ImpactSequence.luminanceOf(ImpactSequence.regionsOf(look)[region])
				else nil
			-- Out of the scene, or to or from an unknown luminance, always counts.
			local changes = index == 1
				or previous == nil
				or current == nil
				or math.abs((current :: number) - (previous :: number)) >= delta
			if changes then
				transitions += 1
			end
			previous = current
		end
		transitions += 1 -- back to the scene
		counts[region] = transitions
	end
	return counts
end

--- The most transitions any region makes along the path.
function ImpactSequence.transitionsOfLooks(names: { string }, looks: { [string]: Impact.Look }): number
	local most = 0
	for _, count in ImpactSequence.regionTransitions(names, looks) do
		most = math.max(most, count)
	end
	return most
end

--- The flash cost of a path of looks: ceil(the worst region's transitions / 2).
function ImpactSequence.costOfLooks(names: { string }, looks: { [string]: Impact.Look }): number
	return math.ceil(ImpactSequence.transitionsOfLooks(names, looks) / 2)
end

--- The looks of a sequence table with start and finish times at `frameSeconds` per frame.
function ImpactSequence.framesOf(sequence: Impact.Sequence, frameSeconds: number): { Frame }
	local list: { Frame } = {}
	local frameCount = 0
	for _, step in sequence.steps do
		if step.frames <= 0 then
			continue -- a step that holds no frame never shows
		end
		local start = frameCount * frameSeconds
		frameCount += step.frames
		table.insert(list, {
			look = step.look,
			frames = step.frames,
			start = start,
			finish = frameCount * frameSeconds,
		})
	end
	return list
end

--- Frames a sequence table holds in all (the number that must fit its hit-stop tier).
function ImpactSequence.frameCountOf(sequence: Impact.Sequence): number
	local total = 0
	for _, step in sequence.steps do
		total += math.max(0, step.frames)
	end
	return total
end

--- The worst region's luminance transitions a sequence table makes from the scene and back.
function ImpactSequence.transitionsOf(sequence: Impact.Sequence, looks: { [string]: Impact.Look }): number
	return ImpactSequence.transitionsOfLooks(ImpactSequence.looksOf(sequence), looks)
end

--- The flash cost of a sequence table: ceil(the worst region's transitions / 2).
function ImpactSequence.flashCostOf(sequence: Impact.Sequence, looks: { [string]: Impact.Look }): number
	return ImpactSequence.costOfLooks(ImpactSequence.looksOf(sequence), looks)
end

--- The looks of impact.sequences[name] with start and finish times in seconds.
function ImpactSequence.frames(name: string): { Frame }
	return ImpactSequence.framesOf(sequenceOf(name), Impact.frameSeconds)
end

--- Seconds impact.sequences[name] lasts.
function ImpactSequence.seconds(name: string): number
	return ImpactSequence.frameCountOf(sequenceOf(name)) * Impact.frameSeconds
end

--- Frames impact.sequences[name] holds in all.
function ImpactSequence.frameCount(name: string): number
	return ImpactSequence.frameCountOf(sequenceOf(name))
end

--- The full-screen flashes impact.sequences[name] costs from the flash budget.
function ImpactSequence.flashCost(name: string): number
	return ImpactSequence.flashCostOf(sequenceOf(name), Impact.looks)
end

--- The hit-stop tier impact.sequences[name] rides on.
function ImpactSequence.tier(name: string): string
	return sequenceOf(name).tier
end

--- The rank of impact.sequences[name]: a higher one replaces a lower one showing.
function ImpactSequence.rank(name: string): number
	return sequenceOf(name).rank
end

--- Seconds of the hit-stop impact.sequences[name] rides on: the overlay never shows past them.
function ImpactSequence.capSeconds(name: string): number
	local frames = Combat.hitStopFrames[sequenceOf(name).tier] or ImpactSequence.frameCount(name)
	return frames * Impact.frameSeconds
end

--- True when `name` is a sequence in impact.luau.
function ImpactSequence.has(name: string): boolean
	return Impact.sequences[name] ~= nil
end

--- Every sequence name, sorted.
function ImpactSequence.names(): { string }
	local names = {}
	for name in Impact.sequences do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--- The look showing `elapsed` seconds into a frame list, or nil once the list has ended.
function ImpactSequence.lookAt(frames: { Frame }, elapsed: number): string?
	local t = math.max(0, elapsed)
	for _, frame in frames do
		if t < frame.finish then
			return frame.look
		end
	end
	return nil
end

--- Seconds the soft dim's peak holds (impact.reduced.holdFrames).
function ImpactSequence.dimHoldSeconds(): number
	return Impact.reduced.holdFrames * Impact.frameSeconds
end

--- Seconds the soft dim lasts (fade in, hold, fade out); `holdSeconds` replaces the data hold.
function ImpactSequence.dimSeconds(holdSeconds: number?): number
	local dim = Impact.reduced
	local hold = if holdSeconds ~= nil then holdSeconds else ImpactSequence.dimHoldSeconds()
	return (dim.fadeInFrames + dim.fadeOutFrames) * Impact.frameSeconds + math.max(hold, 0)
end

--- The soft dim's opacity `elapsed` seconds in: eased from `from` (a dim already showing, else
--- 0) up to the peak, held `holdSeconds` (the data hold when nil), then eased back to 0.
function ImpactSequence.dimOpacity(elapsed: number, from: number?, holdSeconds: number?): number
	local dim = Impact.reduced
	local seconds = Impact.frameSeconds
	local peak = dim.opacity
	local start = math.clamp(from or 0, 0, peak)
	local fadeIn = dim.fadeInFrames * seconds
	local hold = math.max(if holdSeconds ~= nil then holdSeconds else ImpactSequence.dimHoldSeconds(), 0)
	local fadeOut = dim.fadeOutFrames * seconds
	local t = math.max(0, elapsed)
	if t < fadeIn then
		return start + (peak - start) * Easing.evaluate(dim.fadeInEasing, t / fadeIn)
	end
	if t < fadeIn + hold then
		return peak
	end
	if t < fadeIn + hold + fadeOut then
		return peak * (1 - Easing.evaluate(dim.fadeOutEasing, (t - fadeIn - hold) / fadeOut))
	end
	return 0
end

--- The relative-luminance drop the dim makes at its peak over `sceneToken` (impact.reduced
--- referenceScene when nil), blending in sRGB as the UI does (the darker, worst case).
function ImpactSequence.dimDip(sceneToken: string?, opacity: number?, inkToken: string?): number
	local dim = Impact.reduced
	local scene = (Palette.tokens :: any)[sceneToken or dim.referenceScene]
	local ink = (Palette.tokens :: any)[inkToken or dim.token]
	if scene == nil or ink == nil then
		return 1 -- an unknown color is treated as the worst case
	end
	local alpha = math.clamp(if opacity ~= nil then opacity else dim.opacity, 0, 1)
	local blended = {}
	for channel = 1, #scene do
		blended[channel] = scene[channel] * (1 - alpha) + ink[channel] * alpha
	end
	return luminanceOfRgb(scene) - luminanceOfRgb(blended)
end

return ImpactSequence
