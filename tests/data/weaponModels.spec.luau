--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")
local Palette = Harness.load("src/shared/data/palette")
local Playground = Harness.load("src/shared/data/playground")
local Rigs = Harness.load("src/shared/data/rigs")

-- tools/validators/weaponModels.luau reads every table through ctx.load and requires nothing, so it
-- loads as a plain chunk; `models` swaps in a deep copy of weaponModels.luau the test has broken.
local function runValidator(models: any?): { string }
	local path = "tools/validators/weaponModels.luau"
	local chunk = luau.load(
		fs.readFile(Harness.repoRoot() .. "/" .. path),
		{ debugName = path, environment = Harness.environment() :: any }
	)
	local validate = chunk()
	return validate({
		load = function(modulePath: string): any
			if models ~= nil and modulePath == "src/shared/data/weaponModels" then
				return models
			end
			return Harness.load(modulePath)
		end,
		listFiles = Harness.listFiles,
		readFile = Harness.readFile,
		repoRoot = Harness.repoRoot(),
	})
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

local function mentions(problems: { string }, needle: string): boolean
	for _, problem in problems do
		if problem:find(needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

-- Every part a PlayerR15 joint links, but the weapon's own.
local function playerParts(): { [string]: boolean }
	local parts = {}
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name ~= WeaponModels.motorName then
			parts[joint.part0] = true
			parts[joint.part1] = true
		end
	end
	return parts
end

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

describe("weaponModels sheaths", function()
	it("the Playground loadout's sword has a back mount on a PlayerR15 body part", function()
		local category = Weapons.byId(Playground.loadout.weapon).category
		local row = WeaponModels.sheath(category)
		expect(row).toBeTruthy()
		expect(row).toBe(WeaponModels.sheaths[category])
		expect(playerParts()[row.part]).toBe(true)
		expect(Palette.tokens[row.scabbard.color]).toBeTruthy()
		expect(row.scabbard.wall).toBeGreaterThan(0)
		expect(row.scabbard.clearance).toBeGreaterThanOrEqual(0)
		expect(#row.mount.pos).toBe(3)
		expect(#row.mount.rot).toBe(3)
	end)

	it("a category without a row keeps its weapon in the hand", function()
		expect(WeaponModels.sheath("Rapier")).toBeNil()
		expect(WeaponModels.sheath("Katana")).toBeNil()
	end)

	it("names the sheath instances apart from every weapon name", function()
		expect(WeaponModels.sheathModelName).toBe("Sheath")
		expect(WeaponModels.scabbardPart).toBe("Scabbard")
		expect(WeaponModels.scabbardWeld).toBe("ScabbardWeld")
	end)

	it("the validator passes the real table", function()
		expect(runValidator()).toEqual({})
	end)

	it("the validator flags a bad part, a non-palette color, a zero wall and an unknown category", function()
		local badPart = deepCopy(WeaponModels)
		badPart.sheaths.OneHandedSword.part = "Backpack"
		expect(mentions(runValidator(badPart), "part 'Backpack' is not a PlayerR15 body part")).toBe(true)
		local weaponPart = deepCopy(WeaponModels)
		weaponPart.sheaths.OneHandedSword.part = "Weapon"
		expect(mentions(runValidator(weaponPart), "part 'Weapon' is not a PlayerR15 body part")).toBe(true)

		local badColor = deepCopy(WeaponModels)
		badColor.sheaths.OneHandedSword.scabbard.color = "Mahogany"
		expect(mentions(runValidator(badColor), "scabbard.color 'Mahogany' is not a palette token")).toBe(true)

		local noWall = deepCopy(WeaponModels)
		noWall.sheaths.OneHandedSword.scabbard.wall = 0
		expect(mentions(runValidator(noWall), "scabbard.wall must be above 0")).toBe(true)

		local unknown = deepCopy(WeaponModels)
		unknown.sheaths.Whip = deepCopy(WeaponModels.sheaths.OneHandedSword)
		expect(mentions(runValidator(unknown), "'Whip' is not a weapon category")).toBe(true)
	end)

	it("the validator flags a broken shape, a missing loadout row and a clashing name", function()
		local shape = deepCopy(WeaponModels)
		shape.sheaths.OneHandedSword.mount.pos = { 0, 1 }
		expect(mentions(runValidator(shape), "sheaths.OneHandedSword: field 'mount'")).toBe(true)
		local negative = deepCopy(WeaponModels)
		negative.sheaths.OneHandedSword.scabbard.clearance = -0.1
		expect(mentions(runValidator(negative), "sheaths.OneHandedSword: field 'scabbard'")).toBe(true)

		local missing = deepCopy(WeaponModels)
		missing.sheaths.OneHandedSword = nil
		expect(mentions(runValidator(missing), "has no sheaths row")).toBe(true)

		for _, clash in { "Weapon", "TrailStart", "TrailEnd", "WeaponGrip", "Grip" } do
			local named = deepCopy(WeaponModels)
			named.scabbardPart = clash
			expect(mentions(runValidator(named), ("scabbardPart '%s' is also"):format(clash))).toBe(true)
		end
		local same = deepCopy(WeaponModels)
		same.scabbardWeld = same.sheathModelName
		expect(mentions(runValidator(same), "scabbardWeld 'Sheath' is also sheathModelName")).toBe(true)
	end)
end)
