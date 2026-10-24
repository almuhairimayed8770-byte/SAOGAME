--!strict
local TargetRanking = Harness.load("src/client/controllers/TargetRanking")
local camera = Harness.load("src/shared/data/camera")

local params = {
	range = camera.lock.range,
	coneDegrees = camera.lock.coneDegrees,
	angleWeightStuds = camera.lock.angleWeightStuds,
}

local forward = { 0, 0, -1 }
local origin = { 0, 0, 0 }

describe("TargetRanking", function()
	it("measures the angle from the camera's forward", function()
		expect(TargetRanking.angleFrom(forward, origin, { 0, 0, -10 })).toBeCloseTo(0, 1e-6)
		expect(TargetRanking.angleFrom(forward, origin, { 10, 0, 0 })).toBeCloseTo(math.pi / 2, 1e-6)
		expect(TargetRanking.angleFrom(forward, origin, { 0, 0, 10 })).toBeCloseTo(math.pi, 1e-6)
		expect(TargetRanking.angleFrom(forward, origin, origin)).toBe(0)
	end)

	it("drops candidates beyond the range or outside the cone", function()
		expect(TargetRanking.eligible({ id = 1, distance = params.range, angle = 0 }, params)).toBe(true)
		expect(TargetRanking.eligible({ id = 1, distance = params.range + 1, angle = 0 }, params)).toBe(false)
		expect(
			TargetRanking.eligible({ id = 1, distance = 5, angle = math.rad(params.coneDegrees / 2) + 0.01 }, params)
		).toBe(false)
		expect(
			TargetRanking.eligible({ id = 1, distance = 5, angle = math.rad(params.coneDegrees / 2) - 0.01 }, params)
		).toBe(true)
	end)

	it("ranks nearest first with the off-center angle priced in studs", function()
		local ranked = TargetRanking.rank({
			{ id = 1, distance = 30, angle = 0 },
			{ id = 2, distance = 10, angle = 0 },
			{ id = 3, distance = 9, angle = math.rad(50) }, -- near but far off-center
			{ id = 4, distance = 200, angle = 0 }, -- out of range
			{ id = 5, distance = 10, angle = math.pi }, -- behind
		}, params)
		local ids = {}
		for _, candidate in ranked do
			table.insert(ids, candidate.id)
		end
		expect(ids).toEqual({ 2, 3, 1 })
	end)

	it("breaks score ties by id", function()
		local ranked = TargetRanking.rank({
			{ id = 9, distance = 10, angle = 0 },
			{ id = 4, distance = 10, angle = 0 },
		}, params)
		expect(ranked[1].id).toBe(4)
		expect(ranked[2].id).toBe(9)
	end)

	it("cycles through the ranked list and unlocks past the end", function()
		local ids = { 2, 3, 1 }
		expect(TargetRanking.next(ids, nil)).toBe(2)
		expect(TargetRanking.next(ids, 2)).toBe(3)
		expect(TargetRanking.next(ids, 3)).toBe(1)
		expect(TargetRanking.next(ids, 1)).toBeNil()
		expect(TargetRanking.next(ids, 42)).toBe(2)
		expect(TargetRanking.next({}, 2)).toBeNil()
	end)

	it("clears a lock on death, loss or distance", function()
		local breakDistance = camera.lock.breakDistance
		expect(TargetRanking.shouldClear("Idle", 10, breakDistance)).toBe(false)
		expect(TargetRanking.shouldClear("Dead", 10, breakDistance)).toBe(true)
		expect(TargetRanking.shouldClear(nil, 10, breakDistance)).toBe(true)
		expect(TargetRanking.shouldClear("Idle", nil, breakDistance)).toBe(true)
		expect(TargetRanking.shouldClear("Idle", breakDistance + 1, breakDistance)).toBe(true)
		expect(TargetRanking.shouldClear("Stagger", breakDistance, breakDistance)).toBe(false)
	end)
end)
