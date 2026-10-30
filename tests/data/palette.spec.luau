--!strict
local Palette = Harness.load("src/shared/data/palette")

describe("palette", function()
	it("holds the section 11 tokens with their hex values", function()
		local expected = {
			SystemCyan = { 0x7F, 0xE8, 0xFF },
			SystemWhite = { 0xF4, 0xFB, 0xFF },
			HPGreen = { 0x4F, 0xE3, 0x6B },
			HPYellow = { 0xFF, 0xD2, 0x3F },
			HPRed = { 0xFF, 0x3B, 0x3B },
			CursorOrange = { 0xFF, 0x8C, 0x1A },
			CursorRed = { 0xE0, 0x1B, 0x1B },
			TorchWarm = { 0xFF, 0xA3, 0x47 },
			WardedPurple = { 0xB5, 0x7B, 0xFF },
			ShardBlue = { 0x9A, 0xDC, 0xFF },
			ApexEdge = { 0xFF, 0xFF, 0xFF },
		}
		for token, rgb in expected do
			local actual = Palette.rgb(token)
			for channel = 1, 3 do
				expect(actual[channel]).toBeCloseTo(rgb[channel] / 255, 1e-6)
			end
		end
	end)

	it("every token is a valid rgb triple", function()
		for token, rgb in Palette.tokens do
			expect(#rgb).toBe(3)
			for channel = 1, 3 do
				expect(rgb[channel]).toBeGreaterThanOrEqual(0)
				expect(rgb[channel]).toBeLessThanOrEqual(1)
			end
			expect(Palette.color3(token)).toBeTruthy()
		end
	end)

	it("rejects unknown tokens", function()
		expect(function()
			Palette.rgb("Magenta")
		end).toThrow("unknown palette token")
	end)
end)
