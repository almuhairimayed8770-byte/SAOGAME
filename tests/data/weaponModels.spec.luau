local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")
local Palette = Harness.load("src/shared/data/palette")

describe("weaponModels data", function()
	it("has stand-in geometry for every weapon category weapons.luau ships", function()
		for _, weapon in Weapons.list() do
			local model = WeaponModels.get(weapon.category)
			expect(model.blade.length).toBeGreaterThan(0)
			expect(model.blade.length).toBeGreaterThanOrEqual(model.blade.width)
			expect(model.blade.length).toBeGreaterThanOrEqual(model.blade.thickness)
			expect(model.guard.height).toBeGreaterThan(0)
			expect(model.grip.length).toBeGreaterThan(0)
		end
	end)

	it("puts the hold point below the blade, inside the grip", function()
		for category in WeaponModels.categories do
			local model = WeaponModels.get(category)
			local hold = WeaponModels.holdOffset(category)
			expect(hold).toBeGreaterThan(model.blade.length / 2 + model.guard.height)
			expect(hold).toBeLessThan(model.blade.length / 2 + model.guard.height + model.grip.length)
			expect(WeaponModels.totalLength(category)).toBeCloseTo(
				model.blade.length + model.guard.height + model.grip.length,
				1e-9
			)
		end
	end)

	it("the one-handed sword reads as a sword next to a 5-stud character", function()
		local sword = WeaponModels.get("OneHandedSword")
		expect(sword.blade.length).toBeGreaterThan(2.5)
		expect(sword.blade.length).toBeLessThan(4)
		expect(WeaponModels.get("TwoHandedSword").blade.length).toBeGreaterThan(sword.blade.length)
		expect(WeaponModels.get("Dagger").blade.length).toBeLessThan(sword.blade.length)
	end)

	it("uses palette tokens for its colors and the contract names", function()
		for _, token in WeaponModels.colors do
			expect(Palette.tokens[token]).toBeTruthy()
		end
		expect(WeaponModels.bladePart).toBe("Weapon")
		expect(WeaponModels.modelName).toBe("Weapon")
		expect(WeaponModels.motorName).toBe("Weapon")
		expect(WeaponModels.attachments.trailStart).toBe("TrailStart")
		expect(WeaponModels.attachments.trailEnd).toBe("TrailEnd")
		expect(WeaponModels.attachments.grip).toBe("WeaponGrip")
		expect(WeaponModels.tag).toBe("Placeholder")
	end)

	it("rejects an unknown category loudly", function()
		expect(function()
			WeaponModels.get("Whip")
		end).toThrow("no placeholder geometry")
	end)
end)
