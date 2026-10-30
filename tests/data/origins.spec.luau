--!strict
local Origins = Harness.load("src/shared/data/origins")

local ROLLS = 50000
local TOLERANCE = 0.005 -- 0.5% absolute

describe("origins data", function()
	it("every roll's weights sum to 100", function()
		for _, rollName in Origins.rollNames do
			expect(Origins.totalWeight(rollName)).toBeCloseTo(100, 1e-9)
		end
	end)

	it("holds the section 7 chances", function()
		expect(Origins.chanceOf("lineage", "Lowlander")).toBeCloseTo(0.16)
		expect(Origins.chanceOf("lineage", "Hollowkin")).toBeCloseTo(0.01)
		expect(Origins.chanceOf("origin", "None")).toBeCloseTo(0.92)
		expect(Origins.chanceOf("origin", "DualWielder")).toBeCloseTo(0.01)
		expect(Origins.chanceOf("origin", "Aegis")).toBeCloseTo(0.005)
		expect(Origins.chanceOf("mark", "ArchitectsMark")).toBeCloseTo(0.001)
		expect(Origins.chanceOf("mark", "Nothing")).toBe(0)
	end)

	it("50,000 seeded rolls land within 0.5% of every weight", function()
		local random = Random.new(20261017)
		local counts = { lineage = {}, origin = {}, mark = {} }
		for _ = 1, ROLLS do
			local result = Origins.roll(random)
			for _, rollName in Origins.rollNames do
				local id = result[rollName]
				counts[rollName][id] = (counts[rollName][id] or 0) + 1
			end
		end
		for _, rollName in Origins.rollNames do
			for _, entry in Origins[rollName] do
				local observed = (counts[rollName][entry.value] or 0) / ROLLS
				local want = entry.weight / 100
				expect(math.abs(observed - want)).toBeLessThanOrEqual(TOLERANCE)
			end
		end
		local dualWielder = (counts.origin.DualWielder or 0) / ROLLS
		expect(dualWielder).toBeGreaterThan(0.005)
		expect(dualWielder).toBeLessThan(0.015)
		local aegis = (counts.origin.Aegis or 0) / ROLLS
		expect(aegis).toBeGreaterThan(0.002)
		expect(aegis).toBeLessThan(0.008)
	end)

	it("the same seed gives the same roll", function()
		local a = Origins.roll(Random.new(7))
		local b = Origins.roll(Random.new(7))
		expect(a).toEqual(b)
	end)

	it("every lineage and origin has an effects entry with a description", function()
		for _, rollName in { "lineage", "origin" } do
			for _, entry in Origins[rollName] do
				local effect = Origins.effects[entry.value]
				expect(effect).toBeTruthy()
				expect(typeof(effect.description)).toBe("string")
				expect(typeof(effect.look)).toBe("string")
			end
		end
		expect(Origins.effects.DualWielder.gaugeDamageMultiplier).toBe(2.5)
		expect(Origins.effects.Aegis.parryWindow).toBe(0.25)
		expect(Origins.effects.Hollowkin.maxHpMultiplier).toBe(0.5)
		expect(Origins.effects.Ironhand.parryWindowBonus).toBe(0.05)
	end)

	it("announces the rare rolls and nothing else", function()
		expect(Origins.announcementsFor({ lineage = "Lowlander", origin = "DualWielder", mark = "None" })).toEqual({
			"A Dual Wielder has entered the Spire",
		})
		expect(Origins.announcementsFor({ lineage = "Lowlander", origin = "Aegis", mark = "ArchitectsMark" })).toEqual({
			"An Aegis has entered the Spire",
			"The Architect's Mark has appeared in the Spire",
		})
		expect(Origins.announcementsFor({ lineage = "Starmarked", origin = "None", mark = "None" })).toEqual({})
	end)

	it("only the Dual Wielder and the Aegis change the silhouette", function()
		expect(Origins.hasDistinctSilhouette({ lineage = "Lowlander", origin = "DualWielder", mark = "None" })).toBe(
			true
		)
		expect(Origins.hasDistinctSilhouette({ lineage = "Lowlander", origin = "Aegis", mark = "None" })).toBe(true)
		expect(Origins.hasDistinctSilhouette({ lineage = "Lowlander", origin = "Ironhand", mark = "None" })).toBe(false)
	end)

	it("rejects an unknown roll name", function()
		expect(function()
			Origins.totalWeight("fate")
		end).toThrow("unknown roll")
		expect(function()
			Origins.chanceOf("fate", "Lowlander")
		end).toThrow("unknown roll")
	end)
end)
