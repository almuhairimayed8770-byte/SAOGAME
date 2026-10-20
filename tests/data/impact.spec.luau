--!strict
-- impact.luau: the impact-frame looks and sequences of the reel style, the flash budget's hard
-- limit and the Reduce flashing setting, as the brief sets them.
local impact = Harness.load("src/shared/data/impact")
local combat = Harness.load("src/shared/data/combat")
local palette = Harness.load("src/shared/data/palette")
local fx = Harness.load("src/shared/data/fx")
local ui = Harness.load("src/shared/data/ui")

local function stepsOf(name: string): { { look: string, frames: number } }
	local list = {}
	for _, step in impact.sequences[name].steps do
		table.insert(list, { look = step.look, frames = step.frames })
	end
	return list
end

describe("impact data", function()
	it("draws each look from palette tokens: ink, white paper and the system cyan", function()
		local expected = {
			Black = { background = "OutlineInk", figures = nil, strokes = false },
			Dark = { background = "OutlineInk", figures = "SystemWhite", strokes = false },
			Light = { background = "SystemWhite", figures = "OutlineInk", strokes = false },
			Ink = { background = "SystemWhite", figures = "OutlineInk", strokes = true },
			Inverted = { background = "SystemCyan", figures = "SystemWhite", strokes = false },
		}
		for name, look in expected do
			local actual = impact.looks[name]
			expect(actual).never.toBeNil()
			expect(actual.background).toBe(look.background)
			expect(actual.figures).toBe(look.figures)
			expect(actual.strokes).toBe(look.strokes)
			expect(palette.tokens[actual.background]).never.toBeNil()
			-- The flash count reads each region's luminance off the palette, never a label.
			expect((actual :: any).luminance).toBeNil()
		end
	end)

	it("holds the three sequences frame for frame, each on the hit-stop it rides", function()
		expect(stepsOf("Final")).toEqual({ { look = "Dark", frames = 2 } })
		-- The kill: a black beat, then 4 impact frames (the reel's "3 to 4").
		expect(stepsOf("Kill")).toEqual({
			{ look = "Black", frames = 2 },
			{ look = "Dark", frames = 2 },
			{ look = "Ink", frames = 2 },
		})
		expect(stepsOf("Parry")).toEqual({ { look = "Inverted", frames = 1 } })
		expect(impact.sequences.Final.tier).toBe("Final")
		expect(impact.sequences.Kill.tier).toBe("Kill")
		expect(impact.sequences.Parry.tier).toBe("Normal")
		expect(impact.frameSeconds).toBe(combat.hitStopFrameSeconds)
	end)

	it("ranks a kill over a final hit over a parry, for hits that land together", function()
		expect(impact.sequences.Kill.rank).toBeGreaterThan(impact.sequences.Final.rank)
		expect(impact.sequences.Final.rank).toBeGreaterThan(impact.sequences.Parry.rank)
	end)

	it("caps full-screen flashes at 3 in any 1-second window", function()
		expect(impact.flash.windowSeconds).toBe(1)
		expect(impact.flash.maxPerWindow).toBe(3)
		-- A transition is a 10% change of relative luminance (WCAG 2.x general flash).
		expect(impact.flash.transitionDelta).toBe(0.1)
		expect(impact.flash.luminance.weights).toEqual({ 0.2126, 0.7152, 0.0722 })
	end)

	it("dims softly instead: low opacity ink, eased in over frames and out over more", function()
		local dim = impact.reduced
		expect(dim.token).toBe("OutlineInk")
		expect(dim.opacity).toBeGreaterThan(0)
		expect(dim.opacity).toBeLessThanOrEqual(0.4)
		expect(dim.fadeInFrames).toBeGreaterThanOrEqual(2)
		expect(dim.fadeOutFrames).toBeGreaterThan(dim.fadeInFrames)
		-- On a white scene the dip is itself a flash: it is charged.
		expect(dim.flashCost).toBe(1)
		expect(palette.tokens[dim.referenceScene]).never.toBeNil()
	end)

	it("reads the Reduce flashing setting from a boolean attribute that starts off", function()
		expect(impact.reduceFlashingAttribute).toBe("SettingReduceFlashing")
		expect(impact.reduceFlashingDefault).toBe(false)
	end)

	it("sits the overlay above the HUD and the system line", function()
		expect(impact.overlay.displayOrder).toBeGreaterThan(ui.hud.displayOrder)
		expect(impact.overlay.displayOrder).toBeGreaterThan(ui.systemLine.displayOrder)
	end)

	it("leaves the root, the sheath, the sword and FX parts out of the silhouettes", function()
		for _, name in { "HumanoidRootPart", "Sheath", "Weapon", "FX" } do
			expect(impact.silhouette.excludeNames).toContain(name)
		end
		expect(impact.silhouette.maxRigs).toBeGreaterThan(0)
		expect(impact.silhouette.poolCap).toBeGreaterThanOrEqual(impact.quality.High.maxPartsPerRig)
	end)

	it("lays 3 to 5 tapered ink strokes", function()
		expect(impact.strokes.count.min).toBe(3)
		expect(impact.strokes.count.max).toBe(5)
		expect(impact.strokes.token).toBe("OutlineInk")
		local taper = impact.strokes.taper
		expect(taper[1][1]).toBe(0)
		expect(taper[#taper][1]).toBe(1)
	end)

	it("has a quality row for every fx tier, each drawing the figures with fewer parts lower down", function()
		for tier in fx.quality do
			local row = impact.quality[tier]
			expect(row).never.toBeNil()
			-- Never a bare luminance blink: every tier draws the fighters.
			expect(row.silhouettes).toBe(true)
			expect(row.maxPartsPerRig).toBeGreaterThan(0)
		end
		expect(impact.quality.High.maxPartsPerRig).toBeGreaterThan(impact.quality.Medium.maxPartsPerRig)
		expect(impact.quality.Medium.maxPartsPerRig).toBeGreaterThan(impact.quality.Low.maxPartsPerRig)
	end)
end)
