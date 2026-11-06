--!strict
--[[
	scope.luau (D-015): the Phase 0 content whose clips must ship, every id resolving to a row of
	its table, and the has* helpers answering from the lists.
]]

local Scope = Harness.load("src/shared/data/scope")
local Arts = Harness.load("src/shared/data/arts")
local Enemies = Harness.load("src/shared/data/enemies")
local Bosses = Harness.load("src/shared/data/bosses")
local Rigs = Harness.load("src/shared/data/rigs")

local function hasDuplicates(list: { string }): boolean
	local seen: { [string]: boolean } = {}
	for _, id in list do
		if seen[id] then
			return true
		end
		seen[id] = true
	end
	return false
end

describe("scope data", function()
	it("is Phase 0", function()
		expect(Scope.phase).toBe(0)
	end)

	it("names the Phase 0 slice: four One-Handed Sword Arts, the boar and the kobold, no boss", function()
		expect(Scope.arts).toEqual({
			"OneHandedSword.Horizontal",
			"OneHandedSword.Vertical",
			"OneHandedSword.RisingArc",
			"OneHandedSword.SharpNail",
		})
		expect(Scope.enemies).toEqual({ "FrenzyBoar", "KoboldAxeman" })
		expect(Scope.bosses).toEqual({})
		expect(Scope.rigs).toEqual({ "PlayerR15", "Boar", "Kobold" })
	end)

	it("every id resolves to a row of its table", function()
		for _, id in Scope.arts do
			expect(Arts.byId(id)).toBeTruthy()
		end
		for _, id in Scope.enemies do
			expect(Enemies.byId(id)).toBeTruthy()
		end
		for _, id in Scope.bosses do
			expect(Bosses.byId(id)).toBeTruthy()
		end
		for _, id in Scope.rigs do
			expect(Rigs[id]).toBeTruthy()
		end
	end)

	it("lists nothing twice", function()
		expect(hasDuplicates(Scope.arts)).toBe(false)
		expect(hasDuplicates(Scope.enemies)).toBe(false)
		expect(hasDuplicates(Scope.bosses)).toBe(false)
		expect(hasDuplicates(Scope.rigs)).toBe(false)
	end)

	it("helpers answer from the lists", function()
		expect(Scope.hasArt("OneHandedSword.SharpNail")).toBe(true)
		expect(Scope.hasArt("OneHandedSword.SonicLeap")).toBe(false)
		expect(Scope.hasArt("")).toBe(false)
		expect(Scope.hasEnemy("FrenzyBoar")).toBe(true)
		expect(Scope.hasEnemy("KoboldAxeman")).toBe(true)
		expect(Scope.hasEnemy("DireWolf")).toBe(false)
		expect(Scope.hasBoss("Grolak")).toBe(false)
		expect(Scope.hasRig("PlayerR15")).toBe(true)
		expect(Scope.hasRig("Boar")).toBe(true)
		expect(Scope.hasRig("Kobold")).toBe(true)
		expect(Scope.hasRig("WarboarKing")).toBe(false)
	end)

	it("the gate Arts are in scope and every in-scope Art is a One-Handed Sword Art", function()
		expect(Scope.hasArt("OneHandedSword.Horizontal")).toBe(true)
		expect(Scope.hasArt("OneHandedSword.SharpNail")).toBe(true)
		for _, id in Scope.arts do
			expect(Arts.byId(id).weapon).toBe("OneHandedSword")
		end
	end)

	it("in-scope enemies are the Phase 0 Charger and Brute on in-scope rigs", function()
		expect(Enemies.byId("FrenzyBoar").archetype).toBe("Charger")
		expect(Enemies.byId("KoboldAxeman").archetype).toBe("Brute")
		for _, id in Scope.enemies do
			expect(Scope.hasRig(Enemies.byId(id).skin)).toBe(true)
		end
	end)
end)
