--!strict
-- The pure half of the Studio aim hook (src/client/dev/DevAimLogic.luau, D-114).
local DevAimLogic = Harness.load("src/client/dev/DevAimLogic")
local Dev = Harness.load("src/shared/data/dev")
local InputData = Harness.load("src/shared/data/input")

local LIMITS = { maxSwings = Dev.aim.maxSwings, defaultSlot = InputData.art.defaultSlot, slots = InputData.art.slots }

describe("DevAimLogic.yawOff", function()
	it("is 0 straight ahead and 180 straight behind", function()
		expect(DevAimLogic.yawOff(0, -1, 0, -5)).toBeCloseTo(0, 1e-9)
		expect(math.abs(DevAimLogic.yawOff(0, -1, 0, 5) :: number)).toBeCloseTo(180, 1e-9)
	end)

	it("is positive to the left, the way CFrame.Angles turns a positive yaw", function()
		-- Looking down -Z, the left is -X.
		expect(DevAimLogic.yawOff(0, -1, -3, 0)).toBeCloseTo(90, 1e-9)
		expect(DevAimLogic.yawOff(0, -1, 3, 0)).toBeCloseTo(-90, 1e-9)
		-- The convention a turn by that yaw undoes: CFrame.Angles(0, rad(yaw), 0) faces the point.
		local look = CFrame.Angles(0, math.rad(35), 0).LookVector
		expect(DevAimLogic.yawOff(0, -1, look.X, look.Z)).toBeCloseTo(35, 1e-4)
	end)

	it("matches CombatService's trace bearing on the same offset", function()
		-- traceOf: cross = facing.Z * off.X - facing.X * off.Z, dot = facing . off, atan2(cross, dot).
		local facing = Vector3.new(0.6, 0, -0.8)
		local offset = Vector3.new(-2, 0, 4)
		local cross = facing.Z * offset.X - facing.X * offset.Z
		local dot = facing.X * offset.X + facing.Z * offset.Z
		expect(DevAimLogic.yawOff(facing.X, facing.Z, offset.X, offset.Z)).toBeCloseTo(
			math.deg(math.atan2(cross, dot)),
			1e-9
		)
	end)

	it("gives nil when the look or the offset has no flat length", function()
		expect(DevAimLogic.yawOff(0, 0, 1, 0)).toBeNil()
		expect(DevAimLogic.yawOff(0, -1, 0, 0)).toBeNil()
	end)
end)

describe("DevAimLogic.turnStep", function()
	it("turns the whole way when it fits in the frame, and at the rate when it does not", function()
		expect(DevAimLogic.turnStep(5, 720, 1 / 60)).toBe(5)
		expect(DevAimLogic.turnStep(150, 720, 1 / 60)).toBeCloseTo(12, 1e-9)
		expect(DevAimLogic.turnStep(-150, 720, 1 / 60)).toBeCloseTo(-12, 1e-9)
	end)
end)

describe("DevAimLogic.faced", function()
	it("is true inside the tolerance and false outside it or with no bearing", function()
		expect(DevAimLogic.faced(9.9, 10)).toBe(true)
		expect(DevAimLogic.faced(-10, 10)).toBe(true)
		expect(DevAimLogic.faced(10.1, 10)).toBe(false)
		expect(DevAimLogic.faced(nil, 10)).toBe(false)
	end)
end)

describe("DevAimLogic.pickTarget", function()
	local candidates = {
		{ id = 4, distance = 9 },
		{ id = 7, distance = 3 },
		{ id = 2, distance = 3 },
	}
	it("takes the id asked for first, then the lock, then the nearest (lower id on a tie)", function()
		expect(DevAimLogic.pickTarget(4, 7, candidates)).toBe(4)
		expect(DevAimLogic.pickTarget(nil, 4, candidates)).toBe(4)
		expect(DevAimLogic.pickTarget(nil, nil, candidates)).toBe(2)
		expect(DevAimLogic.pickTarget(nil, nil, {})).toBeNil()
	end)
end)

describe("DevAimLogic.swingPlan", function()
	it("defaults to one basic swing on the default slot", function()
		local plan = DevAimLogic.swingPlan({}, LIMITS)
		expect(plan).toEqual({ kind = "basic", slot = InputData.art.defaultSlot, count = 1 })
	end)

	it("takes an Art slot and a count", function()
		local plan = DevAimLogic.swingPlan({ kind = "art", slot = 2, count = 3 }, LIMITS)
		expect(plan).toEqual({ kind = "art", slot = 2, count = 3 })
	end)

	it("refuses an unknown kind, a slot off the bar, and a count past the cap", function()
		local plan, err = DevAimLogic.swingPlan({ kind = "kick" }, LIMITS)
		expect(plan).toBeNil()
		expect((err :: string):find("kind", 1, true)).never.toBeNil()
		plan, err = DevAimLogic.swingPlan({ kind = "art", slot = InputData.art.slots + 1 }, LIMITS)
		expect(plan).toBeNil()
		expect((err :: string):find("slot", 1, true)).never.toBeNil()
		plan, err = DevAimLogic.swingPlan({ count = Dev.aim.maxSwings + 1 }, LIMITS)
		expect(plan).toBeNil()
		expect((err :: string):find("count", 1, true)).never.toBeNil()
		plan, err = DevAimLogic.swingPlan({ count = 1.5 }, LIMITS)
		expect(plan).toBeNil()
		expect((err :: string):find("count", 1, true)).never.toBeNil()
	end)

	it("reads a missing or non-table args as the defaults", function()
		expect(DevAimLogic.swingPlan(nil, LIMITS)).toEqual({
			kind = "basic",
			slot = InputData.art.defaultSlot,
			count = 1,
		})
		expect(DevAimLogic.args("x")).toEqual({})
		expect(DevAimLogic.args({ a = 1 })).toEqual({ a = 1 })
	end)
end)

describe("DevAimLogic run states", function()
	it("calls Idle and Moving free, everything else busy, and an unknown state free", function()
		expect(DevAimLogic.isFree("Idle")).toBe(true)
		expect(DevAimLogic.isFree("Moving")).toBe(true)
		expect(DevAimLogic.isFree(nil)).toBe(true)
		for _, state in { "Art", "PostMotion", "Guard", "Dodge", "Stagger", "GuardBroken", "Break", "Dead" } do
			expect(DevAimLogic.isFree(state)).toBe(false)
		end
	end)

	it("says an Art run is over once Art was seen and the body is free again", function()
		expect(DevAimLogic.artRunOver({})).toBe(false)
		expect(DevAimLogic.artRunOver({ "Art" })).toBe(false)
		expect(DevAimLogic.artRunOver({ "Art", "PostMotion" })).toBe(false)
		expect(DevAimLogic.artRunOver({ "Art", "PostMotion", "Idle" })).toBe(true)
		expect(DevAimLogic.artRunOver({ "Idle" })).toBe(false)
	end)
end)

describe("DevAimLogic reporting", function()
	it("rounds to the data's places and passes nil through", function()
		expect(DevAimLogic.round(1.23456, 2)).toBe(1.23)
		expect(DevAimLogic.round(-1.236, 2)).toBe(-1.24)
		expect(DevAimLogic.round(nil, 2)).toBeNil()
	end)

	it("tallies hits and damage", function()
		local count, damage = DevAimLogic.tally({ { damage = 4 }, { damage = 2.5 } })
		expect(count).toBe(2)
		expect(damage).toBe(6.5)
		count, damage = DevAimLogic.tally({})
		expect(count).toBe(0)
		expect(damage).toBe(0)
	end)
end)
