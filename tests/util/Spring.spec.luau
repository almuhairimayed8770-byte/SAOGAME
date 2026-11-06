--!strict
local Spring = Harness.load("src/shared/util/Spring")

describe("Spring", function()
	it("settles on its target", function()
		local spring = Spring.new(0, 80, 1)
		spring.target = 10
		for _ = 1, 600 do
			spring:Step(1 / 60)
		end
		expect(spring.position).toBeCloseTo(10, 1e-2)
	end)

	it("a critically damped spring never overshoots", function()
		local spring = Spring.new(0, 80, 1)
		spring.target = 10
		local peak = 0
		for _ = 1, 600 do
			peak = math.max(peak, spring:Step(1 / 60))
		end
		expect(peak).toBeLessThanOrEqual(10.001)
	end)

	it("an underdamped spring overshoots (the hit nudge)", function()
		local spring = Spring.new(0, 200, 0.3)
		spring.target = 1
		local peak = 0
		for _ = 1, 600 do
			peak = math.max(peak, spring:Step(1 / 60))
		end
		expect(peak).toBeGreaterThan(1.1)
	end)

	it("Impulse adds velocity and Snap zeroes it", function()
		local spring = Spring.new(0, 80, 1)
		spring:Impulse(5)
		expect(spring.velocity).toBe(5)
		spring:Snap(3)
		expect(spring.position).toBe(3)
		expect(spring.velocity).toBe(0)
	end)

	it("works on Vector3", function()
		local spring = Spring.new(Vector3.zero, 80, 1)
		spring.target = Vector3.new(0, 5, 0)
		for _ = 1, 600 do
			spring:Step(1 / 60)
		end
		expect(spring.position.Y).toBeCloseTo(5, 1e-2)
	end)
end)
