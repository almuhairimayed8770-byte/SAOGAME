--!strict
--[[
	ReviewMarkers: the timeline marker math the ClipLab draws and tools/animation-review.luau
	writes, on synthetic clips with known timings and on the hand-written Horizontal clip.
]]

local ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Dev = Harness.load("src/shared/data/dev")

local F = 1 / 60

local function attackClip(overrides: { [string]: any }?): any
	local clip = {
		id = "player/OneHandedSword/TestArt",
		rig = "PlayerR15",
		duration = 1.0,
		loop = false,
		layer = "FullBody",
		attack = true,
		hitStop = "Normal",
		keys = {
			{
				time = 0,
				easing = "QuadOut",
				joints = { RightShoulder = { rot = { 0, 0, 0 } } },
				root = { pos = { 0, 0, 0 } },
			},
			{ time = 6 * F, easing = "QuadIn", joints = { RightShoulder = { rot = { -60, 0, 0 } } } },
			{ time = 9 * F, easing = "ExpoOut", joints = { RightShoulder = { rot = { 70, 0, 0 } } } },
			{
				time = 20 * F,
				easing = "Spring",
				joints = { RightShoulder = { rot = { 60, 0, 0 } } },
				root = { pos = { 0, 0, -3 } },
			},
			{
				time = 1.0,
				easing = "SineInOut",
				joints = { RightShoulder = { rot = { 58, 0, 0 } } },
				root = { pos = { 0, 0, -4 } },
			},
		},
		events = {
			{ time = 0, kind = "ActivationHold" },
			{ time = 5 * F, kind = "TrailOn" },
			{ time = 6 * F, kind = "SmearOn" },
			{ time = 6 * F, kind = "HitWindowOpen" },
			{ time = 8 * F, kind = "SmearOff" },
			{ time = 10 * F, kind = "HitWindowClose" },
			{ time = 12 * F, kind = "TrailOff" },
			{ time = 20 * F, kind = "PostMotionStart" },
			{ time = 30 * F, kind = "Footstep" },
		},
		beats = {
			Anticipation = { start = 0, finish = 6 * F },
			Snap = { start = 6 * F, finish = 9 * F },
			Smear = { start = 6 * F, finish = 8 * F },
			Hold = { start = 9 * F, finish = 12 * F },
			Settle = { start = 12 * F, finish = 20 * F },
			Recovery = { start = 20 * F, finish = 1.0 },
		},
	}
	if overrides then
		for key, value in overrides do
			clip[key] = value
		end
	end
	return clip
end

describe("ReviewMarkers frames and fractions", function()
	it("converts seconds to 60 fps frames and clamps fractions", function()
		expect(ReviewMarkers.frames(0.5)).toBeCloseTo(30)
		expect(ReviewMarkers.fractionOf(0.25, 1)).toBeCloseTo(0.25)
		expect(ReviewMarkers.fractionOf(5, 1)).toBe(1)
		expect(ReviewMarkers.fractionOf(0.5, 0)).toBe(0)
		expect(ReviewMarkers.frameLabel(0.383, 1)).toBe("f 23 / 60  0.383 s")
	end)
end)

describe("ReviewMarkers beats", function()
	it("lists the six beats in order with frame counts", function()
		local rows = ReviewMarkers.beatRows(attackClip())
		expect(#rows).toBe(6)
		expect(rows[1].beat).toBe("Anticipation")
		expect(rows[1].frames).toBeCloseTo(6)
		expect(rows[2].beat).toBe("Snap")
		expect(rows[2].frames).toBeCloseTo(3)
		expect(rows[3].frames).toBeCloseTo(2)
		expect(rows[6].beat).toBe("Recovery")
		expect(rows[6].present).toBe(true)
	end)

	it("marks a missing beat absent with zero frames", function()
		local clip = attackClip()
		clip.beats.Hold = nil
		local rows = ReviewMarkers.beatRows(clip)
		expect(rows[4].beat).toBe("Hold")
		expect(rows[4].present).toBe(false)
		expect(rows[4].frames).toBe(0)
		expect(ReviewMarkers.problems(clip)).toContain("missing beat(s): Hold")
	end)
end)

describe("ReviewMarkers trail timing", function()
	it("measures the lead-in and lag-out against the hit windows and smear", function()
		local timing = ReviewMarkers.trailTiming(attackClip())
		expect(#timing.spans).toBe(1)
		expect(timing.leadFrames).toBeCloseTo(1) -- TrailOn at 5f, smear and window at 6f
		expect(timing.lagFrames).toBeCloseTo(2) -- HitWindowClose at 10f, TrailOff at 12f
		expect(timing.uncovered).toEqual({})
		expect(timing.stray).toBe(0)
		expect(timing.summary).toBe("on 1.0f before, off 2.0f after")
	end)

	it("the smear frames count as an allowed trail region (a Charger's rush)", function()
		local clip = attackClip({
			events = {
				{ time = 6 * F, kind = "SmearOn" },
				{ time = 7 * F, kind = "TrailOn" },
				{ time = 8 * F, kind = "SmearOff" },
				{ time = 40 * F, kind = "HitWindowOpen" },
				{ time = 48 * F, kind = "HitWindowClose" },
				{ time = 49 * F, kind = "TrailOff" },
			},
		})
		local timing = ReviewMarkers.trailTiming(clip)
		expect(timing.leadFrames).toBeCloseTo(0)
		expect(timing.lagFrames).toBeCloseTo(1)
		expect(ReviewMarkers.problems(clip)).toEqual({})
	end)

	it("flags a hit window the trail does not cover and a stray trail span", function()
		local clip = attackClip({
			events = {
				{ time = 6 * F, kind = "SmearOn" },
				{ time = 6 * F, kind = "HitWindowOpen" },
				{ time = 8 * F, kind = "SmearOff" },
				{ time = 9 * F, kind = "TrailOn" }, -- ignites after the window opened
				{ time = 10 * F, kind = "HitWindowClose" },
				{ time = 12 * F, kind = "TrailOff" },
				{ time = 30 * F, kind = "TrailOn" }, -- nowhere near a window
				{ time = 34 * F, kind = "TrailOff" },
			},
		})
		local timing = ReviewMarkers.trailTiming(clip)
		expect(timing.uncovered).toEqual({ 1 })
		expect(timing.stray).toBe(1)
		local problems = ReviewMarkers.problems(clip)
		expect(problems).toContain("trail off during hit window 1")
		expect(problems).toContain("trail on outside any hit window (1 span)")
	end)

	it("flags a trail that ignites too early or lingers too long", function()
		local clip = attackClip({
			events = {
				{ time = 0, kind = "TrailOn" },
				{ time = 8 * F, kind = "SmearOn" },
				{ time = 8 * F, kind = "HitWindowOpen" },
				{ time = 10 * F, kind = "SmearOff" },
				{ time = 12 * F, kind = "HitWindowClose" },
				{ time = 32 * F, kind = "TrailOff" },
			},
		})
		local problems = ReviewMarkers.problems(clip)
		expect(problems).toContain(("trail ignites 8.0 frames early (max %d)"):format(Dev.review.trailLeadFramesMax))
		expect(problems).toContain(("trail lingers 20.0 frames (max %d)"):format(Dev.review.trailLagFramesMax))
	end)

	it("an unclosed TrailOn runs to the clip end and a missing trail is a problem", function()
		local spans = ReviewMarkers.eventSpans(
			attackClip({ events = { { time = 0.5, kind = "TrailOn" } } }),
			"TrailOn",
			"TrailOff"
		)
		expect(spans).toEqual({ { start = 0.5, finish = 1.0 } })
		local clip = attackClip({
			events = { { time = 6 * F, kind = "HitWindowOpen" }, { time = 10 * F, kind = "HitWindowClose" } },
		})
		local problems = ReviewMarkers.problems(clip)
		expect(problems).toContain("no trail")
		expect(problems).toContain("no smear")
	end)
end)

describe("ReviewMarkers problems", function()
	it("reports Linear on a limb but not on a root-only key", function()
		local clip = attackClip()
		clip.keys[2].easing = "Linear"
		expect(ReviewMarkers.linearLimbKeys(clip)).toEqual({ 2 })
		expect(ReviewMarkers.problems(clip)).toContain("Linear on a limb at key 2")
		clip = attackClip()
		table.insert(clip.keys, 4, { time = 15 * F, easing = "Linear", joints = {}, root = { pos = { 0, 0, -2 } } })
		expect(ReviewMarkers.linearLimbKeys(clip)).toEqual({})
	end)

	it("checks the Snap, Settle and player Anticipation budgets and the hit-stop tier", function()
		local clip = attackClip()
		clip.beats.Snap = { start = 6 * F, finish = 12 * F }
		clip.beats.Settle = { start = 12 * F, finish = 30 * F }
		clip.beats.Anticipation = { start = 0, finish = 2 * F }
		clip.hitStop = nil
		local problems = ReviewMarkers.problems(clip)
		expect(problems).toContain("Snap 6.0 frames (want 2..4)")
		expect(problems).toContain("Settle 18.0 frames (want 6..12)")
		expect(problems).toContain("Anticipation 2.0 frames (want 4..10)")
		expect(problems).toContain("no hitStop tier")
	end)

	it("a player basic attack is held to the same Anticipation budget as an Art", function()
		local clip = attackClip({ id = "player/OneHandedSword/Basic9" })
		clip.beats.Anticipation = { start = 0, finish = 14 * F }
		expect(ReviewMarkers.problems(clip)).toContain("Anticipation 14.0 frames (want 4..10)")
	end)

	it("an enemy wind-up longer than ten frames is not a problem", function()
		local clip = attackClip({ id = "enemy/Boar/TestCharge", rig = "Boar" })
		clip.beats.Anticipation = { start = 0, finish = 0.6 }
		clip.beats.Snap = { start = 0.6, finish = 0.6 + 3 * F }
		clip.beats.Smear = { start = 0.6, finish = 0.6 + 2 * F }
		clip.beats.Hold = { start = 0.6 + 3 * F, finish = 0.6 + 5 * F }
		clip.beats.Settle = { start = 0.6 + 5 * F, finish = 0.6 + 12 * F }
		clip.beats.Recovery = { start = 0.9, finish = 1.0 }
		clip.events = {
			{ time = 0.6, kind = "SmearOn" },
			{ time = 0.6, kind = "TrailOn" },
			{ time = 0.6, kind = "HitWindowOpen" },
			{ time = 0.6 + 2 * F, kind = "SmearOff" },
			{ time = 0.6 + 4 * F, kind = "HitWindowClose" },
			{ time = 0.6 + 5 * F, kind = "TrailOff" },
		}
		expect(ReviewMarkers.problems(clip)).toEqual({})
	end)

	it("a non-attack clip only reports Linear limbs", function()
		local idle = {
			id = "player/OneHandedSword/TestIdle",
			rig = "PlayerR15",
			duration = 2,
			loop = true,
			layer = "Base",
			keys = {
				{ time = 0, easing = "SineInOut", joints = { Neck = { rot = { 0, 0, 0 } } } },
				{ time = 1, easing = "Linear", joints = { Neck = { rot = { 2, 0, 0 } } } },
			},
			events = {},
		}
		expect(ReviewMarkers.problems(idle)).toEqual({ "Linear on a limb at key 2" })
		idle.keys[2].easing = "SineInOut"
		expect(ReviewMarkers.problems(idle)).toEqual({})
	end)
end)

describe("ReviewMarkers root motion and markers", function()
	it("measures the carry between the first and last root position", function()
		expect(ReviewMarkers.rootMotion(attackClip())).toBeCloseTo(4)
		local still = attackClip()
		for _, key in still.keys do
			key.root = nil
		end
		expect(ReviewMarkers.rootMotion(still)).toBe(0)
	end)

	it("lays the beats, hit windows, trail, smear and other events in lanes with palette tokens", function()
		local Palette = Harness.load("src/shared/data/palette")
		local markers = ReviewMarkers.markers(attackClip())
		local lanes = {}
		for _, marker in markers do
			lanes[marker.lane] = (lanes[marker.lane] or 0) + 1
			expect(Palette.tokens[marker.token]).never.toBeNil()
			expect(marker.finish).toBeGreaterThanOrEqual(marker.start)
		end
		expect(lanes.Beats).toBe(6)
		expect(lanes.HitWindows).toBe(1)
		expect(lanes.TrailSmear).toBe(2)
		expect(lanes.Events).toBe(3) -- ActivationHold, PostMotionStart, Footstep
	end)
end)

describe("ReviewMarkers rows and markdown", function()
	it("builds a row and a markdown line that carries hand-filled cells over", function()
		local row = ReviewMarkers.row(attackClip())
		expect(row.id).toBe("player/OneHandedSword/TestArt")
		expect(row.attack).toBe(true)
		expect(#row.beats).toBe(6)
		expect(row.problems).toEqual({})
		local header = ReviewMarkers.markdownHeader()
		expect(#header).toBe(2)
		local columns = ReviewMarkers.splitMarkdownLine(header[1])
		local line = ReviewMarkers.markdownLine(row, { "yes", "arm pops at f 9", "no" })
		local cells = ReviewMarkers.splitMarkdownLine(line)
		expect(#cells).toBe(#columns)
		expect(cells[1]).toBe("`player/OneHandedSword/TestArt`")
		expect(cells[3]).toBe("attack")
		expect(cells[5]).toBe("Y 6f")
		expect(cells[#cells - 2]).toBe("yes")
		expect(cells[#cells - 1]).toBe("arm pops at f 9")
		expect(cells[#cells]).toBe("no")
		expect(line:find("|", 1, true)).never.toBeNil()
	end)

	it("escapes pipes inside cells so the table stays rectangular", function()
		local row = ReviewMarkers.row(attackClip())
		local line = ReviewMarkers.markdownLine(row, { "a | b", "", "" })
		local cells = ReviewMarkers.splitMarkdownLine(line)
		expect(#cells).toBe(#ReviewMarkers.splitMarkdownLine(ReviewMarkers.markdownHeader()[1]))
		expect(cells[#cells - 2]).toBe("a / b")
	end)

	it("the hand-written Horizontal clip reviews clean", function()
		local clip = ClipLibrary.get("player/OneHandedSword/Horizontal")
		local row = ReviewMarkers.row(clip)
		expect(row.problems).toEqual({})
		expect(row.hitStop).toBe("Normal")
		expect(#row.hitWindows).toBe(1)
		expect(row.rootMotion).toBeCloseTo(1)
		for _, beat in row.beats do
			expect(beat.present).toBe(true)
		end
	end)
end)
