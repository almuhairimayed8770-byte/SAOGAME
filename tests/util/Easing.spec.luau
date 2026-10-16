local Easing = Harness.load("src/shared/util/Easing")

describe("Easing", function()
	it("every curve starts at 0 and ends at 1", function()
		for _, name in { "Linear", "ExpoOut", "ExpoIn", "BackOut", "Spring", "SineInOut", "QuadIn", "QuadOut", "Hold" } do
			expect(Easing.evaluate(name, 0)).toBeCloseTo(0, 1e-3)
			expect(Easing.evaluate(name, 1)).toBeCloseTo(1, 1e-3)
		end
	end)

	it("ExpoOut is the fastest early mover (the snap)", function()
		expect(Easing.ExpoOut(0.2)).toBeGreaterThan(Easing.QuadOut(0.2))
		expect(Easing.ExpoOut(0.2)).toBeGreaterThan(0.7)
	end)

	it("BackOut overshoots past the key before settling", function()
		local peak = 0
		for step = 0, 100 do
			peak = math.max(peak, Easing.BackOut(step / 100))
		end
		expect(peak).toBeGreaterThan(1.05)
		expect(peak).toBeLessThan(1.15)
	end)

	it("Spring rings past 1 and comes back", function()
		local above, below = false, false
		for step = 1, 99 do
			local value = Easing.Spring(step / 100)
			if value > 1.02 then
				above = true
			elseif above and value < 1 then
				below = true
			end
		end
		expect(above).toBe(true)
		expect(below).toBe(true)
	end)

	it("rejects unknown curve names loudly", function()
		expect(function()
			Easing.get("Tween")
		end).toThrow("unknown easing")
	end)

	it("clamps t outside [0, 1]", function()
		expect(Easing.evaluate("Linear", -2)).toBe(0)
		expect(Easing.evaluate("Linear", 7)).toBe(1)
	end)
end)
