--!strict
local Sfx = Harness.load("src/shared/data/sfx")
local Palette = Harness.load("src/shared/data/palette")

describe("sfx data", function()
	it("declares the five SoundGroups and the mix rules", function()
		expect(Sfx.groups).toEqual({ "Master", "Music", "SFX", "UI", "Voice" })
		expect(Sfx.mix.systemVoiceDuckDb).toBe(8)
		expect(Sfx.mix.mobileMusicOffsetDb).toBe(-2)
		expect(Sfx.music.crossfadeSeconds).toBe(2)
		expect(Sfx.music.combatEndDelaySeconds).toBe(6)
		expect(Sfx.music.bossEntranceSilenceSeconds).toBe(1)
	end)

	it("has an activation chime per trail color", function()
		for token in Palette.tokens do
			if token:sub(1, 5) == "Trail" then
				expect(Sfx.get("artChime", token).spatial).toBe(true)
			end
		end
	end)

	it("every entry is a placeholder with an id, a volume and a spatial flag", function()
		local all = Sfx.all()
		expect(#all).toBeGreaterThan(100)
		for _, row in all do
			expect(row.entry.id).toBe("rbxassetid://0")
			expect(row.entry.placeholder).toBe(true)
			expect(row.entry.volume).toBeGreaterThan(0)
			expect(row.entry.volume).toBeLessThanOrEqual(1)
			expect(typeof(row.entry.spatial)).toBe("boolean")
			if row.entry.pitchRange then
				expect(row.entry.pitchRange[1]).toBeLessThanOrEqual(row.entry.pitchRange[2])
			end
		end
		for index = 2, #all do
			local previous, current = all[index - 1], all[index]
			expect(
				previous.family < current.family or (previous.family == current.family and previous.name < current.name)
			).toBe(true)
		end
	end)

	it("routes families to their groups", function()
		expect(Sfx.groupOf("ui")).toBe("UI")
		expect(Sfx.groupOf("voice")).toBe("Voice")
		expect(Sfx.groupOf("impact")).toBe("SFX")
		expect(Sfx.get("guard", "Parry").volume).toBeGreaterThan(Sfx.get("guard", "Block").volume)
		expect(Sfx.get("hitStopTick", "Kill").spatial).toBe(false)
	end)

	it("errors on unknown families and names", function()
		expect(function()
			Sfx.get("magic", "Fireball")
		end).toThrow("unknown family")
		expect(function()
			Sfx.get("guard", "Fireball")
		end).toThrow("unknown sound")
		expect(function()
			Sfx.groupOf("magic")
		end).toThrow("unknown family")
	end)
end)
