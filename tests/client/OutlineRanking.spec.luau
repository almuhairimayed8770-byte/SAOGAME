local OutlineRanking = Harness.load("src/client/fx/OutlineRanking")
local Fx = Harness.load("src/shared/data/fx")
local Palette = Harness.load("src/shared/data/palette")

local function candidate(key, importance, distance)
	return { key = key, importance = importance, distance = distance }
end

describe("OutlineRanking", function()
	it("orders by importance first, then by distance", function()
		local list = {
			candidate("far-normal", "Normal", 100),
			candidate("near-normal", "Normal", 5),
			candidate("party", "Party", 80),
			candidate("boss", "Boss", 300),
			candidate("lock", "Lock", 50),
		}
		local chosen = OutlineRanking.select(list, 10, Fx.outline.distance)
		expect(chosen).toEqual({ "boss", "lock", "party", "near-normal", "far-normal" })
	end)

	it("respects the budget, keeping the best ranked", function()
		local list = {}
		for index = 1, 40 do
			table.insert(list, candidate("n" .. index, "Normal", index))
		end
		local chosen, set = OutlineRanking.select(list, Fx.outline.budget, Fx.outline.distance)
		expect(#chosen).toBe(Fx.outline.budget)
		expect(chosen[1]).toBe("n1")
		expect(set["n31"]).toBe(true)
		expect(set["n32"]).toBeNil()
	end)

	it("drops Normal rigs beyond the distance but keeps Boss / Lock / Party at any distance", function()
		local list = {
			candidate("beyond", "Normal", Fx.outline.distance + 1),
			candidate("edge", "Normal", Fx.outline.distance),
			candidate("far-boss", "Boss", 1000),
			candidate("far-party", "Party", 1000),
			candidate("far-lock", "Lock", 1000),
		}
		local _, set = OutlineRanking.select(list, 31, Fx.outline.distance)
		expect(set["beyond"]).toBeNil()
		expect(set["edge"]).toBe(true)
		expect(set["far-boss"]).toBe(true)
		expect(set["far-party"]).toBe(true)
		expect(set["far-lock"]).toBe(true)
	end)

	it("important rigs push out nearer Normal rigs when the budget is tight", function()
		local list = {
			candidate("n1", "Normal", 1),
			candidate("n2", "Normal", 2),
			candidate("party", "Party", 90),
			candidate("boss", "Boss", 95),
		}
		local chosen = OutlineRanking.select(list, 2, Fx.outline.distance)
		expect(chosen).toEqual({ "boss", "party" })
		expect(#OutlineRanking.select(list, 0, Fx.outline.distance)).toBe(0)
	end)

	it("unknown importances rank as Normal", function()
		local list = { candidate("weird", "Whatever", 1), candidate("normal", "Normal", 2) }
		local chosen = OutlineRanking.select(list, 2, Fx.outline.distance)
		expect(chosen).toEqual({ "weird", "normal" })
	end)

	it("the outline ink darkens the base color toward OutlineInk", function()
		local base = Palette.rgb("PlaceholderBoar")
		local ink = Palette.rgb("OutlineInk")
		local result = OutlineRanking.inkColor(base, ink, Fx.outline.inkBlend)
		for axis = 1, 3 do
			expect(result[axis]).toBeLessThan(base[axis])
			expect(result[axis]).toBeGreaterThanOrEqual(ink[axis] - 1e-6)
		end
		local none = OutlineRanking.inkColor(base, ink, 0)
		local full = OutlineRanking.inkColor(base, ink, 1)
		local over = OutlineRanking.inkColor(base, ink, 5)
		for axis = 1, 3 do
			expect(none[axis]).toBeCloseTo(base[axis], 1e-9)
			expect(full[axis]).toBeCloseTo(ink[axis], 1e-9)
			expect(over[axis]).toBeCloseTo(ink[axis], 1e-9)
		end
	end)
end)
