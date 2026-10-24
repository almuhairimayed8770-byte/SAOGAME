--!strict
--[[
	ReviewMarkers: pure timeline math for the clip review loop (section 10 "Review loop").

	Given a Types.ClipDef it computes what the ClipLab draws on its timeline bar and what
	tools/animation-review.luau writes into docs/ANIMATION_REVIEW.md: the six beats with their
	frame counts at 60 fps, the hit windows, the trail and smear spans, the trail timing relative
	to the hit windows, the root motion in studs, and the problems a reviewer would flag (missing
	beats, Linear on a limb, a trail outside a window, a Snap or Anticipation outside its budget, a
	hit window that does not cover its strike's snap).

	It also derives the strike snap of every hit (strikeSnaps): the clips validator
	(tools/validators/clips.luau) pairs each hit window with it, so the review report and CI read
	the snaps the same way.

	It owns the sheath rules too (docs/DECISIONS.md D-050): mountAt says where the sword is at a
	time (on the back or in the hand, from the clip's `sheathed` field and its WeaponDraw and
	WeaponSheathe events), and mountProblems lists the clip's sheath mistakes. The ClipLab, the
	ground clearance spec, the clips validator and the review all read the sword's place from here.

	No Instances, no Roblox datatypes: ClipLab and the Lune tool both call it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared.types)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Dev = require(Shared.data.dev)

local Review = Dev.review
local FPS = Review.fps
local EPSILON = 1e-6

export type Span = { start: number, finish: number }

export type BeatRow = {
	beat: Types.Beat,
	present: boolean,
	start: number,
	finish: number,
	frames: number, -- at 60 fps; 0 when absent
}

export type TrailTiming = {
	spans: { Span }, -- TrailOn..TrailOff pairs (an unclosed TrailOn runs to the clip end)
	leadFrames: number?, -- frames the first trail ignites before its first hit window opens
	lagFrames: number?, -- frames the last trail lingers after its last hit window closes
	uncovered: { number }, -- hit window indices no trail covers
	stray: number, -- trail spans that contain no hit window
	summary: string, -- one cell of the review table
}

export type Marker = {
	lane: string, -- "Beats" | "HitWindows" | "TrailSmear" | "Events"
	kind: string, -- the beat, "HitWindow", "Trail", "Smear" or the event kind
	label: string,
	start: number, -- seconds
	finish: number, -- seconds; equal to start for an instant event
	token: string, -- palette token
}

export type Row = {
	id: string,
	rig: string,
	attack: boolean,
	loop: boolean,
	duration: number,
	durationFrames: number,
	beats: { BeatRow },
	hitStop: string, -- "Normal" | "Final" | "Kill" | "-"
	hitWindows: { { open: number, close: number } },
	trail: TrailTiming,
	rootMotion: number, -- studs between the clip's first and last root position
	problems: { string },
}

local ReviewMarkers = {}

local BEATS: { Types.Beat } = Review.beats :: { Types.Beat }

--- Seconds to frames at the review frame rate (60 fps).
function ReviewMarkers.frames(seconds: number): number
	return seconds * FPS
end

--- Where a time sits on a bar of the clip's length, 0..1 (clamped).
function ReviewMarkers.fractionOf(time: number, duration: number): number
	if duration <= 0 then
		return 0
	end
	return math.clamp(time / duration, 0, 1)
end

--- The readout under the timeline: "f 23 / 60  0.383 s".
function ReviewMarkers.frameLabel(time: number, duration: number): string
	local frame = math.floor(time * FPS + 0.5)
	local total = math.floor(duration * FPS + 0.5)
	return ("f %d / %d  %.3f s"):format(frame, total, time)
end

local function spanOf(clip: Types.ClipDef, beat: Types.Beat): Span?
	local beats: any = clip.beats
	if typeof(beats) ~= "table" then
		return nil
	end
	local span = (beats :: any)[beat]
	if typeof(span) ~= "table" or typeof(span.start) ~= "number" or typeof(span.finish) ~= "number" then
		return nil
	end
	return { start = span.start, finish = span.finish }
end

--- One row per beat in section 10 order, with frame counts.
function ReviewMarkers.beatRows(clip: Types.ClipDef): { BeatRow }
	local rows = {}
	for _, beat in BEATS do
		local span = spanOf(clip, beat)
		if span == nil then
			table.insert(rows, { beat = beat, present = false, start = 0, finish = 0, frames = 0 })
		else
			table.insert(rows, {
				beat = beat,
				present = true,
				start = span.start,
				finish = span.finish,
				frames = ReviewMarkers.frames(span.finish - span.start),
			})
		end
	end
	return rows
end

--- On/off event pairs as spans; an On with no Off runs to the clip end, an Off with no On is ignored.
function ReviewMarkers.eventSpans(clip: Types.ClipDef, onKind: string, offKind: string): { Span }
	local spans = {}
	local open: number? = nil
	for _, event in clip.events do
		if event.kind == onKind then
			if open == nil then
				open = event.time
			end
		elseif event.kind == offKind and open ~= nil then
			table.insert(spans, { start = open, finish = event.time })
			open = nil
		end
	end
	if open ~= nil then
		table.insert(spans, { start = open, finish = clip.duration })
	end
	return spans
end

local function covers(span: Span, other: Span): boolean
	return span.start <= other.start + EPSILON and span.finish >= other.finish - EPSILON
end

local function overlaps(span: Span, other: Span): boolean
	return other.start < span.finish + EPSILON and other.finish > span.start - EPSILON
end

--- Trail timing relative to the hit windows: lead-in, lag-out, windows no trail covers, stray spans.
--- Section 10 allows the trail during damage windows and the smear frames, so both anchor the lead
--- and lag; a trail span that touches neither is stray.
function ReviewMarkers.trailTiming(clip: Types.ClipDef): TrailTiming
	local spans = ReviewMarkers.eventSpans(clip, "TrailOn", "TrailOff")
	local windows = ClipSampler.hitWindows(clip)
	local anchors: { Span } = {}
	for _, window in windows do
		table.insert(anchors, { start = window.open, finish = window.close })
	end
	for _, smear in ReviewMarkers.eventSpans(clip, "SmearOn", "SmearOff") do
		table.insert(anchors, smear)
	end
	local uncovered = {}
	for index, window in windows do
		local found = false
		for _, span in spans do
			if covers(span, { start = window.open, finish = window.close }) then
				found = true
				break
			end
		end
		if not found then
			table.insert(uncovered, index)
		end
	end
	local stray = 0
	local leadFrames: number? = nil
	local lagFrames: number? = nil
	for _, span in spans do
		local first: number? = nil
		local last: number? = nil
		for _, anchor in anchors do
			if overlaps(span, anchor) then
				first = if first == nil then anchor.start else math.min(first, anchor.start)
				last = if last == nil then anchor.finish else math.max(last, anchor.finish)
			end
		end
		if first == nil or last == nil then
			stray += 1
		else
			local lead = math.max(0, ReviewMarkers.frames(first - span.start))
			local lag = math.max(0, ReviewMarkers.frames(span.finish - last))
			leadFrames = if leadFrames == nil then lead else leadFrames
			lagFrames = lag
		end
	end
	local summary: string
	if #spans == 0 then
		summary = if #windows == 0 then "-" else "no trail"
	elseif leadFrames == nil or lagFrames == nil then
		summary = ("%d span(s), none over a hit window"):format(#spans)
	else
		summary = ("on %.1ff before, off %.1ff after"):format(leadFrames, lagFrames)
		if #uncovered > 0 then
			summary ..= (", window %s uncovered"):format(table.concat(uncovered, ","))
		end
		if stray > 0 then
			summary ..= (", %d stray"):format(stray)
		end
	end
	return {
		spans = spans,
		leadFrames = leadFrames,
		lagFrames = lagFrames,
		uncovered = uncovered,
		stray = stray,
		summary = summary,
	}
end

--- Studs between the root position at the clip's start and at its end (the carry of an Art).
function ReviewMarkers.rootMotion(clip: Types.ClipDef): number
	local first = ClipSampler.rootMotionAt(clip, 0)
	local last = ClipSampler.rootMotionAt(clip, clip.duration)
	local dx = last[1] - first[1]
	local dy = last[2] - first[2]
	local dz = last[3] - first[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Indices of keys that use Linear easing while moving a joint (the root alone may be Linear).
function ReviewMarkers.linearLimbKeys(clip: Types.ClipDef): { number }
	local indices = {}
	for index, key in clip.keys do
		if key.easing == "Linear" and next(key.joints) ~= nil then
			table.insert(indices, index)
		end
	end
	return indices
end

local function inRange(frames: number, range: { min: number, max: number }): boolean
	return frames >= range.min - EPSILON and frames <= range.max + EPSILON
end

--- The strike snaps of an attack clip in clip order (section 10 beat 2), one per strike. The first
--- is the beats table's Snap. The beats table describes only the first strike, so every later one
--- is read from the keys the way that Snap is authored: a key that moves a joint with ExpoOut
--- easing and lands 2..4 frames (the Snap budget) after the key before it; the snap runs from that
--- earlier key (the end of the anticipation or re-wind) to the struck pose. An ExpoOut key outside
--- the budget is not a strike (a start pose eased in over 9 frames, a wind-up crouch, a gore at the
--- end of a rush). Without a beats Snap every such key counts, the first included.
function ReviewMarkers.strikeSnaps(clip: Types.ClipDef): { Span }
	local snaps: { Span } = {}
	local first = spanOf(clip, "Snap")
	if first ~= nil then
		table.insert(snaps, first)
	end
	local after = if first ~= nil then first.finish else -math.huge
	for index = 2, #clip.keys do
		local key = clip.keys[index]
		local previous = clip.keys[index - 1]
		if key.easing == "ExpoOut" and next(key.joints) ~= nil and previous.time >= after - EPSILON then
			if inRange(ReviewMarkers.frames(key.time - previous.time), Review.snapFrames) then
				table.insert(snaps, { start = previous.time, finish = key.time })
			end
		end
	end
	return snaps
end

--- Hit windows against their strikes: the n-th window must open by the n-th snap's start and stay
--- open through that snap's end (within Review.windowSnapToleranceFrames), so the server's sweep
--- covers the whole cut and not only its follow-through. A clip without hit windows has nothing to
--- pair (a guard Art; a missing window is reported on its own). A count mismatch is reported once
--- and the windows that do have a snap are still checked.
function ReviewMarkers.windowSnapProblems(clip: Types.ClipDef): { string }
	local problems = {}
	local windows = ClipSampler.hitWindows(clip)
	if #windows == 0 then
		return problems
	end
	local snaps = ReviewMarkers.strikeSnaps(clip)
	if #snaps ~= #windows then
		table.insert(
			problems,
			("%d hit windows but %d strike snaps (ExpoOut keys %d..%d frames after the key before)"):format(
				#windows,
				#snaps,
				Review.snapFrames.min,
				Review.snapFrames.max
			)
		)
	end
	local tolerance = Review.windowSnapToleranceFrames / FPS
	for index = 1, math.min(#windows, #snaps) do
		local window = windows[index]
		local snap = snaps[index]
		if window.open > snap.start + tolerance then
			table.insert(
				problems,
				("hit window %d opens %.2f frames after its snap starts (f %.2f)"):format(
					index,
					ReviewMarkers.frames(window.open - snap.start),
					ReviewMarkers.frames(snap.start)
				)
			)
		end
		if window.close < snap.finish - tolerance then
			table.insert(
				problems,
				("hit window %d closes %.2f frames before its snap ends (f %.2f)"):format(
					index,
					ReviewMarkers.frames(snap.finish - window.close),
					ReviewMarkers.frames(snap.finish)
				)
			)
		end
	end
	return problems
end

-- Section 10 budgets the Anticipation of every player attack (Arts and basics alike); an enemy's
-- Anticipation is its wind-up from enemies.luau, which the clips validator checks instead.
local function isPlayerAttack(clip: Types.ClipDef): boolean
	return clip.id:sub(1, 7) == "player/"
end

export type Mount = "Hand" | "Back"

-- The first event of a kind with a number time, or nil. Malformed events are skipped here; the
-- clips validator reports them on their own.
local function firstEventTime(clip: Types.ClipDef, kind: string): number?
	local events: any = clip.events
	if typeof(events) ~= "table" then
		return nil
	end
	for _, event in events do
		if typeof(event) == "table" and event.kind == kind and typeof(event.time) == "number" then
			return event.time
		end
	end
	return nil
end

--- Where the sword is at `time` in a clip: on its sheath ("Back") or in the hand ("Hand"). A
--- sheathed clip starts on the back and the hand takes the sword at its WeaponDraw; a clip with a
--- WeaponSheathe puts it back on the back from that event on. The ClipLab, the ground clearance
--- spec and the rules below all read the mount from here.
function ReviewMarkers.mountAt(clip: Types.ClipDef, time: number): Mount
	local draw = firstEventTime(clip, "WeaponDraw")
	if clip.sheathed == true and (draw == nil or time < draw) then
		return "Back"
	end
	local sheathe = firstEventTime(clip, "WeaponSheathe")
	if sheathe ~= nil and time >= sheathe then
		return "Back"
	end
	return "Hand"
end

-- Kinds that light or sweep the blade: none of them may fire while the sword is on the back.
local BLADE_KINDS = { "TrailOn", "SmearOn", "HitWindowOpen" }

--- The sheath rules of one clip (the sword on the back, docs/DECISIONS.md D-050):
--- `sheathed` is a boolean or nil; at most one WeaponDraw and one WeaponSheathe, never both, with
--- no data; WeaponDraw only in a sheathed clip and WeaponSheathe only in one that is not; no key
--- moves Weapon while the sword is on the back, and a key at the WeaponDraw time moves it (the
--- blade lines up with the sheath there); no trail, smear or hit window on the back; attacks are
--- draw-cuts, never sheathed.
function ReviewMarkers.mountProblems(clip: Types.ClipDef): { string }
	local problems = {}
	local sheathedField: any = clip.sheathed
	if sheathedField ~= nil and typeof(sheathedField) ~= "boolean" then
		table.insert(problems, "sheathed must be a boolean")
	end
	local sheathed = sheathedField == true
	local events: any = clip.events
	local draws, sheathes = 0, 0
	if typeof(events) == "table" then
		for _, event in events do
			if typeof(event) ~= "table" then
				continue
			end
			if event.kind == "WeaponDraw" or event.kind == "WeaponSheathe" then
				if event.kind == "WeaponDraw" then
					draws += 1
				else
					sheathes += 1
				end
				if event.data ~= nil then
					table.insert(problems, ("%s carries data"):format(event.kind))
				end
			end
		end
	end
	if draws > 1 then
		table.insert(problems, ("%d WeaponDraw events (at most one)"):format(draws))
	end
	if sheathes > 1 then
		table.insert(problems, ("%d WeaponSheathe events (at most one)"):format(sheathes))
	end
	if draws > 0 and sheathes > 0 then
		table.insert(problems, "both WeaponDraw and WeaponSheathe (one clip moves the sword one way)")
	end
	if draws > 0 and not sheathed then
		table.insert(problems, "WeaponDraw in a clip that is not sheathed")
	end
	if sheathes > 0 and sheathed then
		table.insert(problems, "WeaponSheathe in a sheathed clip")
	end
	if clip.attack == true and sheathed then
		table.insert(problems, "an attack is never sheathed (attacks are draw-cuts)")
	end

	local draw = firstEventTime(clip, "WeaponDraw")
	local sheathe = firstEventTime(clip, "WeaponSheathe")
	local keys: any = clip.keys
	if typeof(keys) == "table" then
		local keyAtDraw = false
		for index, key in keys do
			if typeof(key) ~= "table" or typeof(key.time) ~= "number" or typeof(key.joints) ~= "table" then
				continue
			end
			if key.joints.Weapon == nil then
				continue
			end
			if sheathed and (draw == nil or key.time < draw - EPSILON) then
				table.insert(problems, ("key %d moves Weapon while the sword is on the back"):format(index))
			end
			if draw ~= nil and math.abs(key.time - draw) <= EPSILON then
				keyAtDraw = true
			end
			if sheathe ~= nil and key.time > sheathe + EPSILON then
				table.insert(problems, ("key %d moves Weapon after the WeaponSheathe"):format(index))
			end
		end
		if draw ~= nil and not keyAtDraw then
			table.insert(problems, ("no key at the WeaponDraw (%.3f s) moves Weapon"):format(draw))
		end
	end

	if typeof(events) == "table" then
		for _, event in events do
			if typeof(event) ~= "table" or typeof(event.time) ~= "number" then
				continue
			end
			if table.find(BLADE_KINDS, event.kind) and ReviewMarkers.mountAt(clip, event.time) == "Back" then
				table.insert(problems, ("%s at %.3f s while the sword is on the back"):format(event.kind, event.time))
			end
		end
	end
	return problems
end

--- The problems a reviewer flags from the data alone (what cannot be seen without recording).
function ReviewMarkers.problems(clip: Types.ClipDef): { string }
	local problems = {}
	local linear = ReviewMarkers.linearLimbKeys(clip)
	if #linear > 0 then
		table.insert(problems, ("Linear on a limb at key %s"):format(table.concat(linear, ",")))
	end
	for _, problem in ReviewMarkers.mountProblems(clip) do
		table.insert(problems, problem)
	end
	if not clip.attack then
		return problems
	end
	local rows = ReviewMarkers.beatRows(clip)
	local missing = {}
	local byBeat: { [string]: BeatRow } = {}
	for _, row in rows do
		byBeat[row.beat] = row
		if not row.present then
			table.insert(missing, row.beat)
		end
	end
	if #missing > 0 then
		table.insert(problems, "missing beat(s): " .. table.concat(missing, ", "))
	end
	local anticipation = byBeat.Anticipation
	if anticipation and anticipation.present and isPlayerAttack(clip) then
		if not inRange(anticipation.frames, Review.anticipationFrames) then
			table.insert(
				problems,
				("Anticipation %.1f frames (want %d..%d)"):format(
					anticipation.frames,
					Review.anticipationFrames.min,
					Review.anticipationFrames.max
				)
			)
		end
	end
	local snap = byBeat.Snap
	if snap and snap.present and not inRange(snap.frames, Review.snapFrames) then
		table.insert(
			problems,
			("Snap %.1f frames (want %d..%d)"):format(snap.frames, Review.snapFrames.min, Review.snapFrames.max)
		)
	end
	local settle = byBeat.Settle
	if settle and settle.present and not inRange(settle.frames, Review.settleFrames) then
		table.insert(
			problems,
			("Settle %.1f frames (want %d..%d)"):format(settle.frames, Review.settleFrames.min, Review.settleFrames.max)
		)
	end
	if clip.hitStop == nil then
		table.insert(problems, "no hitStop tier")
	end
	local windows = ClipSampler.hitWindows(clip)
	if #windows == 0 then
		table.insert(problems, "no hit window")
	end
	for _, problem in ReviewMarkers.windowSnapProblems(clip) do
		table.insert(problems, problem)
	end
	local trail = ReviewMarkers.trailTiming(clip)
	if #trail.spans == 0 then
		table.insert(problems, "no trail")
	else
		if #trail.uncovered > 0 then
			table.insert(problems, ("trail off during hit window %s"):format(table.concat(trail.uncovered, ",")))
		end
		if trail.stray > 0 then
			table.insert(problems, ("trail on outside any hit window (%d span)"):format(trail.stray))
		end
		if trail.leadFrames ~= nil and trail.leadFrames > Review.trailLeadFramesMax + EPSILON then
			table.insert(
				problems,
				("trail ignites %.1f frames early (max %d)"):format(trail.leadFrames, Review.trailLeadFramesMax)
			)
		end
		if trail.lagFrames ~= nil and trail.lagFrames > Review.trailLagFramesMax + EPSILON then
			table.insert(
				problems,
				("trail lingers %.1f frames (max %d)"):format(trail.lagFrames, Review.trailLagFramesMax)
			)
		end
	end
	if #ReviewMarkers.eventSpans(clip, "SmearOn", "SmearOff") == 0 then
		table.insert(problems, "no smear")
	end
	return problems
end

--- Everything the timeline bar draws, in lanes, with the palette token for each marker.
function ReviewMarkers.markers(clip: Types.ClipDef): { Marker }
	local timeline = Dev.clipLab.timeline
	local markers: { Marker } = {}
	for _, row in ReviewMarkers.beatRows(clip) do
		if row.present then
			table.insert(markers, {
				lane = "Beats",
				kind = row.beat,
				label = ("%s %.0ff"):format(row.beat, row.frames),
				start = row.start,
				finish = row.finish,
				token = timeline.beatTokens[row.beat],
			})
		end
	end
	for index, window in ClipSampler.hitWindows(clip) do
		table.insert(markers, {
			lane = "HitWindows",
			kind = "HitWindow",
			label = ("hit %d"):format(index),
			start = window.open,
			finish = window.close,
			token = timeline.hitWindowToken,
		})
	end
	for _, span in ReviewMarkers.eventSpans(clip, "TrailOn", "TrailOff") do
		table.insert(markers, {
			lane = "TrailSmear",
			kind = "Trail",
			label = "trail",
			start = span.start,
			finish = span.finish,
			token = timeline.trailToken,
		})
	end
	for _, span in ReviewMarkers.eventSpans(clip, "SmearOn", "SmearOff") do
		table.insert(markers, {
			lane = "TrailSmear",
			kind = "Smear",
			label = "smear",
			start = span.start,
			finish = span.finish,
			token = timeline.smearToken,
		})
	end
	local paired = {
		HitWindowOpen = true,
		HitWindowClose = true,
		TrailOn = true,
		TrailOff = true,
		SmearOn = true,
		SmearOff = true,
	}
	for _, event in clip.events do
		if not paired[event.kind] then
			table.insert(markers, {
				lane = "Events",
				kind = event.kind,
				label = event.kind,
				start = event.time,
				finish = event.time,
				token = timeline.eventTokens[event.kind] or timeline.eventToken,
			})
		end
	end
	return markers
end

--- The review row for one clip (the animation review table and the ClipLab problems box).
function ReviewMarkers.row(clip: Types.ClipDef): Row
	return {
		id = clip.id,
		rig = clip.rig,
		attack = clip.attack == true,
		loop = clip.loop == true,
		duration = clip.duration,
		durationFrames = ReviewMarkers.frames(clip.duration),
		beats = ReviewMarkers.beatRows(clip),
		hitStop = clip.hitStop or "-",
		hitWindows = ClipSampler.hitWindows(clip),
		trail = ReviewMarkers.trailTiming(clip),
		rootMotion = ReviewMarkers.rootMotion(clip),
		problems = ReviewMarkers.problems(clip),
	}
end

--- The markdown table header lines (the generated columns, then the human review columns).
function ReviewMarkers.markdownHeader(): { string }
	local columns = { "Clip", "Rig", "Kind", "Duration" }
	for _, beat in BEATS do
		table.insert(columns, beat)
	end
	for _, column in { "Hit-stop", "Hits", "Trail vs windows", "Root motion", "Problems found" } do
		table.insert(columns, column)
	end
	for _, column in Review.humanColumns do
		table.insert(columns, column)
	end
	local separators = {}
	for _ in columns do
		table.insert(separators, "---")
	end
	return {
		"| " .. table.concat(columns, " | ") .. " |",
		"| " .. table.concat(separators, " | ") .. " |",
	}
end

local function cell(text: string): string
	return (text:gsub("|", "/"))
end

--- One markdown table line for a row; `human` holds the three hand-filled cells to carry over.
function ReviewMarkers.markdownLine(row: Row, human: { string }?): string
	local cells = {
		("`%s`"):format(row.id),
		row.rig,
		if row.attack then "attack" elseif row.loop then "loop" else "one-shot",
		("%.2f s / %.0ff"):format(row.duration, row.durationFrames),
	}
	for _, beat in row.beats do
		if row.attack then
			table.insert(cells, if beat.present then ("Y %.0ff"):format(beat.frames) else "N")
		else
			table.insert(cells, "-")
		end
	end
	table.insert(cells, row.hitStop)
	table.insert(cells, if row.attack then tostring(#row.hitWindows) else "-")
	table.insert(cells, if row.attack then row.trail.summary else "-")
	table.insert(cells, ("%.2f"):format(row.rootMotion))
	table.insert(cells, if #row.problems == 0 then "none" else table.concat(row.problems, "; "))
	local hand = human or {}
	for index = 1, #Review.humanColumns do
		table.insert(cells, hand[index] or "")
	end
	for index, value in cells do
		cells[index] = cell(value)
	end
	return "| " .. table.concat(cells, " | ") .. " |"
end

--- Splits a markdown table line into trimmed cells (for carrying hand-filled columns over).
function ReviewMarkers.splitMarkdownLine(line: string): { string }
	local cells = {}
	local inner = line:match("^%s*|(.*)|%s*$")
	if inner == nil then
		return cells
	end
	for piece in (inner .. "|"):gmatch("(.-)|") do
		table.insert(cells, (piece:match("^%s*(.-)%s*$")))
	end
	return cells
end

return ReviewMarkers
