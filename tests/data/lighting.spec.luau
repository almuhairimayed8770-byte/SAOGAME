--!strict
local Lighting = Harness.load("src/shared/data/lighting")
local Floors = Harness.load("src/shared/data/floors")

describe("lighting data", function()
	it("holds the section 11 values", function()
		expect(Lighting.base.technology).toBe("Future")
		expect(Lighting.base.shadowSoftness).toBe(0.2)
		expect(Lighting.base.environmentDiffuseScale).toBe(0.6)
		expect(Lighting.base.environmentSpecularScale).toBe(0.3)
		expect(Lighting.colorCorrection).toEqual({ saturation = 0.15, contrast = 0.1 })
		expect(Lighting.bloom).toEqual({ intensity = 0.4, size = 24, threshold = 0.9 })
		expect(Lighting.sunRays.intensity).toBe(0.1)
		expect(Lighting.atmosphere.density).toBe(0.3)
		expect(Lighting.atmosphere.haze).toBe(1.5)
		expect(Lighting.atmosphere.glare).toBe(0.4)
		expect(Lighting.town.depthOfField.focusDistance).toBe(180)
		expect(Lighting.town.depthOfField.farIntensity).toBe(0.3)
		expect(Lighting.night.brightness).toBe(0.8)
		expect(Lighting.night.bloomIntensity).toBe(0.6)
	end)

	it("has a preset for every generator kit and Floor1, with colors in 0..1", function()
		expect(Lighting.preset("Floor1")).toBeTruthy()
		for _, kit in Floors.biomeKits do
			local preset = Lighting.preset(kit)
			for _, field in { "tint", "atmosphere", "decay", "ambient", "outdoorAmbient" } do
				expect(#preset[field]).toBe(3)
				for channel = 1, 3 do
					expect(preset[field][channel]).toBeGreaterThanOrEqual(0)
					expect(preset[field][channel]).toBeLessThanOrEqual(1)
				end
			end
		end
	end)

	it("Floor 1 is the warmest preset", function()
		local floor1 = Lighting.preset("Floor1").tint
		for name, preset in Lighting.biomes do
			if name ~= "Floor1" then
				expect(preset.tint[1] - preset.tint[3]).toBeLessThan(floor1[1] - floor1[3])
			end
		end
	end)

	it("maps floor 1 to Floor1 and every other floor to its biome", function()
		expect(Lighting.presetName(1, "plains")).toBe("Floor1")
		expect(Lighting.presetName(6, "cave")).toBe("cave")
		for _, def in Floors.list do
			expect(Lighting.preset(Lighting.presetName(def.number, def.biome))).toBeTruthy()
		end
	end)

	it("knows night hours", function()
		expect(Lighting.isNightHour(22)).toBe(true)
		expect(Lighting.isNightHour(3)).toBe(true)
		expect(Lighting.isNightHour(12)).toBe(false)
		expect(Lighting.isNightHour(Lighting.dayCycle.nightEndHour)).toBe(false)
	end)

	it("errors on an unknown preset", function()
		expect(function()
			Lighting.preset("citadel")
		end).toThrow("unknown preset")
	end)
end)
