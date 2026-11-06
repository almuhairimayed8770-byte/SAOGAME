--!strict
local HudLogic = Harness.load("src/client/ui/HudLogic")
local UI = Harness.load("src/shared/data/ui")
local Combat = Harness.load("src/shared/data/combat")

describe("HudLogic", function()
	it("maps the HP fraction to green, yellow and red at the section 6 thresholds", function()
		expect(HudLogic.hpToken(1, false)).toBe("HPGreen")
		expect(HudLogic.hpToken(Combat.hpYellowFraction + 0.01, false)).toBe("HPGreen")
		expect(HudLogic.hpToken(Combat.hpYellowFraction, false)).toBe("HPYellow")
		expect(HudLogic.hpToken(Combat.hpRedFraction + 0.01, false)).toBe("HPYellow")
		expect(HudLogic.hpToken(Combat.hpRedFraction, false)).toBe("HPRed")
		expect(HudLogic.hpToken(0, false)).toBe("HPRed")
	end)

	it("colorblind mode swaps the hues for the three bands", function()
		local tokens = UI.hud.hpBar.colorblindTokens
		expect(HudLogic.hpToken(1, true)).toBe(tokens.green)
		expect(HudLogic.hpToken(0.4, true)).toBe(tokens.yellow)
		expect(HudLogic.hpToken(0.1, true)).toBe(tokens.red)
		expect(HudLogic.hpToken(1, true)).never.toBe(HudLogic.hpToken(1, false))
	end)

	it("the fraction clamps and handles an unknown max", function()
		expect(HudLogic.fraction(150, 300)).toBeCloseTo(0.5)
		expect(HudLogic.fraction(400, 300)).toBe(1)
		expect(HudLogic.fraction(-5, 300)).toBe(0)
		expect(HudLogic.fraction(10, 0)).toBe(0)
	end)

	it("flashes only on damage: never on the first bind, a heal or a respawn", function()
		expect(HudLogic.shouldFlash(nil, 300)).toBe(false)
		expect(HudLogic.shouldFlash(300, 250)).toBe(true)
		expect(HudLogic.shouldFlash(250, 300)).toBe(false)
		expect(HudLogic.shouldFlash(250, 250)).toBe(false)
	end)

	it("the flash overlay is brightest at the start and gone after the flash time", function()
		local bar = UI.hud.hpBar
		expect(HudLogic.flashTransparency(0)).toBeCloseTo(bar.flashTransparency)
		local mid = HudLogic.flashTransparency(bar.flashSeconds * 0.5)
		expect(mid).toBeGreaterThan(bar.flashTransparency)
		expect(mid).toBeLessThan(1)
		expect(HudLogic.flashTransparency(bar.flashSeconds)).toBe(1)
		expect(HudLogic.flashTransparency(-1)).toBe(1)
	end)

	it("the low-HP tint is off at and above the red fraction and ramps toward the max at zero", function()
		local tint = UI.hud.lowHpTint
		expect(HudLogic.lowHpTintAlpha(1, 0)).toBe(0)
		expect(HudLogic.lowHpTintAlpha(Combat.hpRedFraction, 0)).toBe(0)
		local some = HudLogic.lowHpTintAlpha(Combat.hpRedFraction * 0.5, 0)
		expect(some).toBeGreaterThan(0)
		expect(some).toBeLessThan(tint.maxAlpha)
		-- At zero HP the pulse peak reaches the max alpha (sin peak at a quarter period).
		local peakTime = 0.25 / tint.pulseHz
		expect(HudLogic.lowHpTintAlpha(0, peakTime)).toBeCloseTo(tint.maxAlpha, 1e-6)
		local troughTime = 0.75 / tint.pulseHz
		expect(HudLogic.lowHpTintAlpha(0, troughTime)).toBeCloseTo(tint.maxAlpha * (1 - tint.pulseDepth), 1e-6)
	end)

	it("the Art list rests visible and fades after the idle time", function()
		local list = UI.hud.artList
		expect(HudLogic.artListTransparency(0)).toBe(list.restTransparency)
		expect(HudLogic.artListTransparency(list.idleFade)).toBe(list.restTransparency)
		local half = HudLogic.artListTransparency(list.idleFade + list.fadeSeconds * 0.5)
		expect(half).toBeGreaterThan(list.restTransparency)
		expect(half).toBeLessThan(1)
		expect(HudLogic.artListTransparency(list.idleFade + list.fadeSeconds)).toBe(1)
	end)

	it("the SWITCH prompt holds, then fades out inside the window", function()
		local duration = Combat.switchWindow
		expect(HudLogic.switchPromptTransparency(0, duration)).toBe(0)
		local fadeFrom = duration * UI.hud.switchPrompt.fadeOutFraction
		expect(HudLogic.switchPromptTransparency(fadeFrom, duration)).toBe(0)
		local late = HudLogic.switchPromptTransparency((fadeFrom + duration) * 0.5, duration)
		expect(late).toBeGreaterThan(0)
		expect(late).toBeLessThan(1)
		expect(HudLogic.switchPromptTransparency(duration, duration)).toBe(1)
		expect(HudLogic.switchPromptTransparency(0, 0)).toBe(1)
	end)

	it("the bar fill approaches its target exponentially and lands exactly", function()
		local step = HudLogic.smoothFill(1, 0.5, 1 / 60)
		expect(step).toBeLessThan(1)
		expect(step).toBeGreaterThan(0.5)
		local value = 1
		for _ = 1, 600 do
			value = HudLogic.smoothFill(value, 0.5, 1 / 60)
		end
		expect(value).toBe(0.5)
		expect(HudLogic.smoothFill(0.5, 0.5, 1)).toBe(0.5)
	end)

	it("formats the HP line and knows which statuses take the full row", function()
		expect(HudLogic.hpText(245.4, 300)).toBe("245 / 300")
		expect(HudLogic.statusFullWidth("Paralysis")).toBe(true)
		expect(HudLogic.statusFullWidth("Bleed")).toBe(false)
	end)

	it("clamps the UI scale and the telegraph intensity into their ranges", function()
		expect(HudLogic.uiScale(nil, false)).toBe(UI.scale.default)
		expect(HudLogic.uiScale(nil, true)).toBe(UI.scale.mobile)
		expect(HudLogic.uiScale(5, false)).toBe(UI.scale.max)
		expect(HudLogic.uiScale(0.1, false)).toBe(UI.scale.min)
		expect(HudLogic.telegraphIntensity(nil)).toBe(UI.hud.telegraphIntensity.default)
		expect(HudLogic.telegraphIntensity(0)).toBe(UI.hud.telegraphIntensity.min)
		expect(HudLogic.telegraphIntensity(9)).toBe(UI.hud.telegraphIntensity.max)
	end)
	describe("declutter: plates lift off each other on screen, the nearest stays (F17)", function()
		local config = UI.nameplates.declutter
		local function box(x: number, y: number, depth: number): any
			return { x = x, y = y, width = 180, height = 56, depth = depth }
		end
		local function overlaps(a: any, liftA: number, b: any, liftB: number): boolean
			local ay, by = a.y - liftA, b.y - liftB
			return math.abs(a.x - b.x) < (a.width + b.width) * 0.5 and math.abs(ay - by) < (a.height + b.height) * 0.5
		end

		it("keeps the nearest plate in place and lifts the farther one clear of it", function()
			local near, far = box(500, 300, 10), box(560, 310, 14)
			local lifts = HudLogic.declutter({ far, near }, config.gapPixels, config.maxLiftHeights)
			expect(lifts[2]).toBe(0)
			expect(lifts[1]).toBeGreaterThan(0)
			expect(overlaps(far, lifts[1], near, lifts[2])).toBe(false)
			-- Just clear, by the gap: its bottom sits gapPixels over the near plate's top.
			local farBottom = far.y - lifts[1] + far.height * 0.5
			expect(farBottom).toBeCloseTo(near.y - near.height * 0.5 - config.gapPixels, 1e-6)
		end)

		it("leaves plates that do not touch alone, and stacks a pile one over another", function()
			local apart =
				HudLogic.declutter({ box(100, 300, 5), box(400, 300, 6) }, config.gapPixels, config.maxLiftHeights)
			expect(apart).toEqual({ 0, 0 })
			local pile = { box(500, 300, 10), box(505, 300, 12), box(510, 300, 14) }
			local lifts = HudLogic.declutter(pile, config.gapPixels, config.maxLiftHeights)
			expect(lifts[1]).toBe(0)
			for i = 1, #pile do
				for j = i + 1, #pile do
					expect(overlaps(pile[i], lifts[i], pile[j], lifts[j])).toBe(false)
				end
			end
			expect(lifts[3]).toBeGreaterThan(lifts[2])
		end)

		it("never lifts a plate more than maxLiftHeights of its own height", function()
			local pile = {}
			for index = 1, 8 do
				table.insert(pile, box(500, 300, index))
			end
			local lifts = HudLogic.declutter(pile, config.gapPixels, config.maxLiftHeights)
			for _, lift in lifts do
				expect(lift).toBeLessThanOrEqual(56 * config.maxLiftHeights + 1e-6)
			end
		end)

		it("keeps which plate climbs while two plates' depths stay within reorderStuds, swapping past it", function()
			-- Two enemies side by side are as near as each other: the depth noise of their drawn
			-- bodies swaps which is nearer every few updates. With the last update's order the
			-- same plate keeps climbing; a real change of more than reorderStuds swaps them.
			local margin = config.reorderStuds
			expect(margin).toBeGreaterThan(0)
			local a, b = box(500, 300, 10), box(540, 300, 10.02)
			a.key, b.key = 7, 9
			local lifts, order = HudLogic.declutter({ a, b }, config.gapPixels, config.maxLiftHeights)
			expect(lifts[1]).toBe(0)
			expect(lifts[2]).toBeGreaterThan(0)
			for step = 1, 12 do
				local noise = if step % 2 == 1 then -0.02 else 0.02
				b.depth = 10 + noise
				lifts, order = HudLogic.declutter({ b, a }, config.gapPixels, config.maxLiftHeights, order)
				expect(lifts[2]).toBe(0)
				expect(lifts[1]).toBeGreaterThan(0)
			end
			b.depth = 10 - margin - 0.01
			lifts, order = HudLogic.declutter({ a, b }, config.gapPixels, config.maxLiftHeights, order)
			expect(lifts[2]).toBe(0)
			expect(lifts[1]).toBeGreaterThan(0)
		end)

		it("eases a plate's lift toward its target frame by frame", function()
			local lift = 0
			local target = 1.2
			local previous = lift
			for _ = 1, 4 do
				lift = HudLogic.easeLift(lift, target, 1 / 60)
				expect(lift).toBeGreaterThan(previous)
				expect(lift).toBeLessThan(target)
				previous = lift
			end
			for _ = 1, 120 do
				lift = HudLogic.easeLift(lift, target, 1 / 60)
			end
			expect(lift).toBe(target)
		end)
	end)
end)
