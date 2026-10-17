--!strict
local Assets = Harness.load("src/shared/data/assets")

describe("assets data", function()
	it("registers everything Phase 0 references as a placeholder", function()
		for _, name in
			{
				"PlayerAnimeRig",
				"BoarRig",
				"KoboldRig",
				"TrialistSword",
				"TrailGradient",
				"Shard",
				"TelegraphLine",
				"TelegraphCone",
				"TelegraphCircle",
				"HexTile",
				"SystemFont",
				"SerifFont",
			}
		do
			local def = Assets.get(name)
			expect(def.id).toBe(0)
			expect(def.placeholder).toBe(true)
			expect(Assets.isReady(name)).toBe(false)
			expect(Assets.url(name)).toBe("rbxassetid://0")
		end
		expect(Assets.get("SystemFont").kind).toBe("Font")
		expect(Assets.get("TrailGradient").kind).toBe("Texture")
		expect(Assets.get("BoarRig").kind).toBe("Mesh")
	end)

	it("lists every missing id, sorted", function()
		local missing = Assets.missing()
		local count = 0
		for _ in Assets.registry do
			count += 1
		end
		expect(#missing).toBe(count)
		for index = 2, #missing do
			expect(missing[index - 1] < missing[index]).toBe(true)
		end
	end)

	it("errors on an unknown asset", function()
		expect(function()
			Assets.url("DragonRig")
		end).toThrow("unknown asset")
	end)
end)
