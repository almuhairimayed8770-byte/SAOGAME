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
end)
