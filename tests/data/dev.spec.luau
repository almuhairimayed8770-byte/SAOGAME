--!strict
-- dev.luau's helpers that the dev tools show on screen.
local Dev = Harness.load("src/shared/data/dev")

describe("dev.luau time-scale label", function()
	it("says at 1x only the scale, and below it that only animation slows", function()
		expect(Dev.timeScaleLabel(1)).toBe("Time scale 1x")
		for _, scale in Dev.timeScale.steps do
			if scale ~= 1 then
				local text = Dev.timeScaleLabel(scale)
				expect(text:find(("%gx"):format(scale), 1, true)).never.toBeNil()
				expect(text:find(Dev.timeScale.slowNote, 1, true)).never.toBeNil()
			end
		end
		expect(Dev.timeScaleLabel(0.25)).toBe("Time scale 0.25x (animation only: hit FX and sounds run at 1x)")
	end)

	it("the Capture panel shows that label", function()
		local source = Harness.readFile("src/client/dev/Capture.client.luau")
		expect(source:find("scaleLabel.Text = Dev.timeScaleLabel(Steps[timeScaleIndex])", 1, true)).never.toBeNil()
	end)
end)
