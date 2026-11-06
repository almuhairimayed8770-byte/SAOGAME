--!strict
local Verlet = Harness.load("src/shared/util/Verlet")

describe("Verlet", function()
	it("keeps segment lengths under gravity", function()
		local chain = Verlet.new({ 0, 10, 0 }, { 0, -1, 0 }, 5, 1)
		for _ = 1, 120 do
			Verlet.step(chain, { 0, 10, 0 }, 1 / 60)
		end
		for index = 2, #chain.points do
			local a = chain.points[index - 1]
			local b = chain.points[index]
			local length = Verlet.length({ b[1] - a[1], b[2] - a[2], b[3] - a[3] })
			expect(length).toBeCloseTo(1, 0.05)
		end
	end)

	it("pins the first point to the anchor", function()
		local chain = Verlet.new({ 0, 10, 0 }, { 0, -1, 0 }, 4, 1)
		Verlet.step(chain, { 3, 12, 1 }, 1 / 60)
		expect(chain.points[1]).toEqual({ 3, 12, 1 })
	end)

	it("hangs down over time and flares with wind", function()
		local chain = Verlet.new({ 0, 10, 0 }, { 1, 0, 0 }, 4, 1)
		for _ = 1, 240 do
			Verlet.step(chain, { 0, 10, 0 }, 1 / 60)
		end
		expect(chain.points[4][2]).toBeLessThan(8)
		chain.wind = { 200, 0, 0 }
		for _ = 1, 120 do
			Verlet.step(chain, { 0, 10, 0 }, 1 / 60)
		end
		expect(chain.points[4][1]).toBeGreaterThan(1)
	end)

	it("pushes points out of the collision sphere", function()
		local chain = Verlet.new({ 0, 10, 0 }, { 0, -1, 0 }, 4, 1)
		chain.collisionCenter = { 0, 8, 0 }
		chain.collisionRadius = 1.5
		for _ = 1, 60 do
			Verlet.step(chain, { 0, 10, 0 }, 1 / 60)
		end
		for index = 2, #chain.points do
			local p = chain.points[index]
			local distance = Verlet.length({ p[1], p[2] - 8, p[3] })
			expect(distance).toBeGreaterThanOrEqual(1.5 - 1e-3)
		end
	end)
end)
