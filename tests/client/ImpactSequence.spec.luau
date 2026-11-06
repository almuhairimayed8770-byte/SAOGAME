--!strict
-- ImpactSequence: when each look of an impact sequence shows (frames through the 60 fps frame
-- length) and how many full-screen flashes it costs: in each region (field, figures, strokes)
-- the changes of relative luminance of at least impact.flash.transitionDelta along Scene ->
-- looks -> Scene, a flash being a pair of opposing transitions, so cost = ceil(the worst
-- region's transitions / 2).
local ImpactSequence = Harness.load("src/client/fx/ImpactSequence")
local impact = Harness.load("src/shared/data/impact")
local combat = Harness.load("src/shared/data/combat")

local F = combat.hitStopFrameSeconds

describe("ImpactSequence timing", function()
	it("gives each look of the Kill its start and finish in seconds", function()
		local frames = ImpactSequence.frames("Kill")
		expect(#frames).toBe(3)
		expect(frames[1].look).toBe("Black")
		expect(frames[1].start).toBeCloseTo(0, 1e-9)
		expect(frames[1].finish).toBeCloseTo(2 * F, 1e-9)
		expect(frames[2].look).toBe("Dark")
		expect(frames[2].start).toBeCloseTo(2 * F, 1e-9)
		expect(frames[2].finish).toBeCloseTo(4 * F, 1e-9)
		expect(frames[3].look).toBe("Ink")
		expect(frames[3].start).toBeCloseTo(4 * F, 1e-9)
		expect(frames[3].finish).toBeCloseTo(6 * F, 1e-9)
		expect(ImpactSequence.seconds("Kill")).toBeCloseTo(6 * F, 1e-9)
		expect(ImpactSequence.frameCount("Kill")).toBe(6)
	end)

	it("caps each sequence at the hit-stop it rides on, and ranks Kill over Final over Parry", function()
		expect(ImpactSequence.capSeconds("Kill")).toBeCloseTo(combat.hitStopFrames.Kill * F, 1e-9)
		expect(ImpactSequence.capSeconds("Final")).toBeCloseTo(combat.hitStopFrames.Final * F, 1e-9)
		expect(ImpactSequence.capSeconds("Parry")).toBeCloseTo(combat.hitStopFrames.Normal * F, 1e-9)
		expect(ImpactSequence.rank("Kill")).toBeGreaterThan(ImpactSequence.rank("Final"))
		expect(ImpactSequence.rank("Final")).toBeGreaterThan(ImpactSequence.rank("Parry"))
	end)

	it("times Final and Parry", function()
		expect(ImpactSequence.seconds("Final")).toBeCloseTo(2 * F, 1e-9)
		expect(ImpactSequence.seconds("Parry")).toBeCloseTo(F, 1e-9)
		local parry = ImpactSequence.frames("Parry")
		expect(#parry).toBe(1)
		expect(parry[1].look).toBe("Inverted")
	end)

	it("fits every sequence inside the hit-stop it rides on", function()
		for _, name in ImpactSequence.names() do
			local tier = ImpactSequence.tier(name)
			expect(combat.hitStopFrames[tier]).never.toBeNil()
			expect(ImpactSequence.frameCount(name)).toBeLessThanOrEqual(combat.hitStopFrames[tier])
		end
	end)

	it("picks the look by elapsed time, so a slow frame skips ahead and never stretches", function()
		local frames = ImpactSequence.frames("Kill")
		expect(ImpactSequence.lookAt(frames, 0)).toBe("Black")
		expect(ImpactSequence.lookAt(frames, 1.9 * F)).toBe("Black")
		expect(ImpactSequence.lookAt(frames, 2.1 * F)).toBe("Dark")
		-- One long frame from 0 straight to 5 frames lands on Ink: Dark is skipped, not held.
		expect(ImpactSequence.lookAt(frames, 5 * F)).toBe("Ink")
		expect(ImpactSequence.lookAt(frames, 6.01 * F)).toBeNil()
		expect(ImpactSequence.lookAt(frames, 1)).toBeNil()
		expect(ImpactSequence.lookAt(frames, -1)).toBe("Black")
	end)

	it("errors on an unknown sequence name", function()
		expect(function()
			ImpactSequence.frames("Nope")
		end).toThrow("unknown sequence 'Nope'")
		expect(ImpactSequence.has("Nope")).toBe(false)
		expect(ImpactSequence.has("Kill")).toBe(true)
	end)
end)

describe("ImpactSequence flash cost", function()
	it("costs Final 1, Kill 2 and Parry 1", function()
		expect(ImpactSequence.flashCost("Final")).toBe(1)
		expect(ImpactSequence.flashCost("Kill")).toBe(2)
		expect(ImpactSequence.flashCost("Parry")).toBe(1)
	end)

	it("measures each region from its palette color: the Kill's figures go ink, white, ink", function()
		expect(ImpactSequence.luminanceOf("OutlineInk") :: number).toBeLessThan(0.01)
		expect(ImpactSequence.luminanceOf("TrailWhite") :: number).toBeCloseTo(1, 1e-9)
		expect(ImpactSequence.luminanceOf("Nope")).toBeNil()
		-- Field: scene, ink, ink, white, scene. Figures: scene, ink (no figures), white, ink, scene.
		-- Strokes: scene, ink, ink, ink (the strokes), scene.
		local kill = ImpactSequence.regionTransitions(ImpactSequence.looksOf(impact.sequences.Kill), impact.looks)
		expect(kill).toEqual({ 3, 4, 2 })
		expect(ImpactSequence.transitionsOf(impact.sequences.Kill, impact.looks)).toBe(4)
		expect(ImpactSequence.transitionsOf(impact.sequences.Final, impact.looks)).toBe(2)
	end)

	it("counts a strobe of the figures alone, on a field that never changes", function()
		-- The checker's case: Dark and Black share the ink field, but the figures flip white/ink.
		local steps = {}
		for index = 1, 6 do
			table.insert(steps, { look = if index % 2 == 1 then "Dark" else "Black", frames = 1 })
		end
		local strobe = { tier = "Final", rank = 2, steps = steps }
		local regions = ImpactSequence.regionTransitions(ImpactSequence.looksOf(strobe), impact.looks)
		expect(regions[1]).toBe(2) -- the field: in and out only
		expect(regions[2]).toBe(7) -- the figures: in, five flips, out
		expect(ImpactSequence.flashCostOf(strobe, impact.looks)).toBe(4)
	end)

	it("counts the strokes coming and going on a field and figures that hold", function()
		local steps = {}
		for index = 1, 4 do
			table.insert(steps, { look = if index % 2 == 1 then "Ink" else "Light", frames = 1 })
		end
		local strobe = { tier = "Kill", rank = 3, steps = steps }
		local regions = ImpactSequence.regionTransitions(ImpactSequence.looksOf(strobe), impact.looks)
		expect(regions[1]).toBe(2)
		expect(regions[2]).toBe(2)
		expect(regions[3]).toBe(5)
		expect(ImpactSequence.flashCostOf(strobe, impact.looks)).toBe(3)
	end)

	it("counts a cyan-to-white flip that two bright looks hide from a light/dark class", function()
		local strobe = {
			tier = "Kill",
			rank = 3,
			steps = {
				{ look = "Inverted", frames = 1 },
				{ look = "Light", frames = 1 },
				{ look = "Inverted", frames = 1 },
				{ look = "Light", frames = 1 },
			},
		}
		-- SystemCyan 0.69 and SystemWhite 0.95 differ by more than the 0.1 a transition needs: a
		-- light/dark class would see one bright field and count 2 transitions, not 5.
		local regions = ImpactSequence.regionTransitions(ImpactSequence.looksOf(strobe), impact.looks)
		expect(regions[1]).toBe(5)
		expect(ImpactSequence.flashCostOf(strobe, impact.looks)).toBe(3)
	end)

	it("scores any path, an empty one as nothing and an unknown look as a change", function()
		expect(ImpactSequence.costOfLooks({}, impact.looks)).toBe(0)
		local empty = { tier = "Kill", rank = 3, steps = { { look = "Dark", frames = 0 } } }
		expect(ImpactSequence.flashCostOf(empty, impact.looks)).toBe(0)
		local same =
			{ tier = "Kill", rank = 3, steps = { { look = "Dark", frames = 2 }, { look = "Dark", frames = 2 } } }
		expect(ImpactSequence.flashCostOf(same, impact.looks)).toBe(1)
		expect(ImpactSequence.transitionsOfLooks({ "Dark", "Nope", "Dark" }, impact.looks)).toBe(4)
		-- A Final that a Kill replaces after its first frame: Dark, then Black, Dark, Ink.
		expect(ImpactSequence.costOfLooks({ "Dark", "Black", "Dark", "Ink" }, impact.looks)).toBe(3)
	end)
end)

describe("ImpactSequence soft dim", function()
	local dim = impact.reduced

	it("lasts fade in + hold + fade out frames", function()
		expect(ImpactSequence.dimSeconds()).toBeCloseTo(
			(dim.fadeInFrames + dim.holdFrames + dim.fadeOutFrames) * F,
			1e-9
		)
	end)

	it("starts at nothing, eases up to the low peak, holds, and eases back to nothing", function()
		expect(ImpactSequence.dimOpacity(0)).toBeCloseTo(0, 1e-9)
		local previous = 0
		local inSeconds = dim.fadeInFrames * F
		for step = 1, 10 do
			local value = ImpactSequence.dimOpacity(inSeconds * step / 10 - 1e-9)
			expect(value).toBeGreaterThanOrEqual(previous)
			expect(value).toBeLessThanOrEqual(dim.opacity + 1e-9)
			previous = value
		end
		-- One frame in is a step of the eased ramp, never the whole peak at once.
		expect(ImpactSequence.dimOpacity(F)).toBeLessThan(dim.opacity)
		expect(ImpactSequence.dimOpacity(inSeconds + 0.5 * dim.holdFrames * F)).toBeCloseTo(dim.opacity, 1e-9)
		local outStart = (dim.fadeInFrames + dim.holdFrames) * F
		expect(ImpactSequence.dimOpacity(outStart + F)).toBeLessThan(dim.opacity)
		expect(ImpactSequence.dimOpacity(outStart + F)).toBeGreaterThan(0)
		expect(ImpactSequence.dimOpacity(ImpactSequence.dimSeconds())).toBeCloseTo(0, 1e-9)
	end)

	it("eases on from a dim already showing instead of dropping to nothing", function()
		local from = dim.opacity * 0.5
		expect(ImpactSequence.dimOpacity(0, from)).toBeCloseTo(from, 1e-9)
		expect(ImpactSequence.dimOpacity(F, from)).toBeGreaterThan(from)
	end)

	it("holds the peak longer when a dim merges into it", function()
		local longer = ImpactSequence.dimHoldSeconds() + 10 * F
		expect(ImpactSequence.dimSeconds(longer)).toBeCloseTo(ImpactSequence.dimSeconds() + 10 * F, 1e-9)
		local outStart = dim.fadeInFrames * F + longer
		expect(ImpactSequence.dimOpacity(outStart - F, 0, longer)).toBeCloseTo(dim.opacity, 1e-9)
		expect(ImpactSequence.dimOpacity(outStart + F, 0, longer)).toBeLessThan(dim.opacity)
	end)

	it("dips a white scene by more than a transition: the dim is a flash and is charged", function()
		local dip = ImpactSequence.dimDip()
		expect(dip).toBeGreaterThan(impact.flash.transitionDelta)
		expect(dim.flashCost).toBeGreaterThanOrEqual(1)
		-- A dim faint enough to stay under a transition on white would cost nothing.
		expect(ImpactSequence.dimDip(nil, 0.03)).toBeLessThan(impact.flash.transitionDelta)
		-- The ink scene cannot get darker.
		expect(ImpactSequence.dimDip("OutlineInk")).toBeCloseTo(0, 1e-9)
	end)
end)
