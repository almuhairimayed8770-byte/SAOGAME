--!strict
-- The pure half of the Studio combat trace hook (src/server/dev/DevTrace.luau, D-114).
local DevTrace = Harness.load("src/server/dev/DevTrace")

local function event(overrides: { [string]: any }?): any
	local base: { [string]: any } = {
		entityId = 7,
		clipId = "player/OneHandedSword/Basic1",
		artId = nil,
		windowIndex = 1,
		windowCount = 1,
		hits = 0,
		facing = Vector3.new(0, 0, -1),
		rootLook = (CFrame.Angles(0, math.rad(3), 0)).LookVector,
		nearest = {
			entityId = 12,
			name = "Frenzy Boar",
			distance = 5.104,
			bearingDegrees = 156.2,
			clearance = 1.6912,
		},
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

describe("DevTrace.yawOf and yawBetween", function()
	it("reads a look's yaw the way CFrame.Angles builds it (0 faces -Z, + turns left)", function()
		expect(DevTrace.yawOf(Vector3.new(0, 0, -1))).toBeCloseTo(0, 1e-9)
		local look = CFrame.Angles(0, math.rad(40), 0).LookVector
		expect(DevTrace.yawOf(look)).toBeCloseTo(40, 1e-4)
		expect(DevTrace.yawOf(Vector3.new(0, 1, 0))).toBeNil()
	end)

	it("gives the signed turn from one look to another, + to the left", function()
		local a = Vector3.new(0, 0, -1)
		local b = CFrame.Angles(0, math.rad(-25), 0).LookVector
		expect(DevTrace.yawBetween(a, b)).toBeCloseTo(-25, 1e-4)
		expect(DevTrace.yawBetween(b, a)).toBeCloseTo(25, 1e-4)
	end)
end)

describe("DevTrace.plain", function()
	it("keeps every field execute_luau can encode, rounded, with no Vector3", function()
		local plain = DevTrace.plain(event(), 2)
		expect(plain.entityId).toBe(7)
		expect(plain.clipId).toBe("player/OneHandedSword/Basic1")
		expect(plain.window).toBe("1/1")
		expect(plain.hits).toBe(0)
		expect(plain.facingYaw).toBe(0)
		expect(plain.rootOff).toBe(3)
		expect(plain.nearest).toEqual({
			entityId = 12,
			name = "Frenzy Boar",
			distance = 5.1,
			bearing = 156.2,
			clearance = 1.69,
		})
		for _, value in plain do
			expect(typeof(value) == "Vector3").toBe(false)
		end
	end)

	it("keeps a missing clearance and a missing enemy as nil", function()
		local plain = DevTrace.plain(event({ nearest = false }), 2)
		expect(plain.nearest).toBeNil()
		local partial = event()
		partial.nearest.clearance = nil
		expect(DevTrace.plain(partial, 2).nearest.clearance).toBeNil()
	end)
end)

describe("DevTrace.line", function()
	it("prints one compact line per window", function()
		local line = DevTrace.line(
			event({ artId = "OneHandedSword.Horizontal", windowIndex = 2, windowCount = 3 }),
			"[DevCombat]",
			2
		)
		expect(line).toBe(
			"[DevCombat] e7 player/OneHandedSword/Basic1 (OneHandedSword.Horizontal) w2/3 hits=0 yaw=0.00 root=+3.00 | Frenzy Boar #12 d=5.10 bearing=+156.20 clear=1.69"
		)
	end)

	it("says so when there is no enemy or no blade clearance", function()
		expect(DevTrace.line(event({ nearest = false }), "[T]", 1)).toBe(
			"[T] e7 player/OneHandedSword/Basic1 w1/1 hits=0 yaw=0.0 root=+3.0 | no enemy"
		)
		local partial = event({ hits = 1 })
		partial.nearest.clearance = nil
		expect(DevTrace.line(partial, "[T]", 1)).toBe(
			"[T] e7 player/OneHandedSword/Basic1 w1/1 hits=1 yaw=0.0 root=+3.0 | Frenzy Boar #12 d=5.1 bearing=+156.2 clear=-"
		)
	end)
end)

describe("DevTrace buffers", function()
	it("keeps only the newest `keep` items, oldest first", function()
		local buffer = {}
		for i = 1, 5 do
			DevTrace.push(buffer, i, 3)
		end
		expect(buffer).toEqual({ 3, 4, 5 })
		expect(DevTrace.last(buffer, 2)).toEqual({ 4, 5 })
		expect(DevTrace.last(buffer, nil)).toEqual({ 3, 4, 5 })
		expect(DevTrace.last(buffer, 10)).toEqual({ 3, 4, 5 })
	end)

	it("calls a run complete once its last window is in", function()
		expect(DevTrace.complete({})).toBe(false)
		expect(DevTrace.complete({ event({ windowIndex = 1, windowCount = 3 }) })).toBe(false)
		expect(DevTrace.complete({ event({ windowIndex = 3, windowCount = 3 }) })).toBe(true)
	end)

	it("adds up a run's hits", function()
		expect(DevTrace.hitsOf({ event({ hits = 1 }), event({ hits = 2 }) })).toBe(3)
	end)
end)

describe("DevTrace.round", function()
	it("rounds to the places asked, passes nil through and never gives a negative zero", function()
		expect(DevTrace.round(5.104, 2)).toBe(5.1)
		expect(DevTrace.round(-1.236, 2)).toBe(-1.24)
		expect(DevTrace.round(nil, 2)).toBeNil()
		expect(tostring(DevTrace.round(-0.001, 2))).toBe("0")
	end)
end)

describe("DevTrace.vector", function()
	it("reads nil, a Vector3 or an {x, y, z} list, and refuses anything else", function()
		local value, err = DevTrace.vector(nil)
		expect(value).toBeNil()
		expect(err).toBeNil()
		expect(DevTrace.vector(Vector3.new(1, 0, 0))).toEqual(Vector3.new(1, 0, 0))
		expect(DevTrace.vector({ 0, 0, -1 })).toEqual(Vector3.new(0, 0, -1))
		value, err = DevTrace.vector({ 1, "a", 0 })
		expect(value).toBeNil()
		expect(err).never.toBeNil()
		value, err = DevTrace.vector("north")
		expect(value).toBeNil()
		expect(err).never.toBeNil()
	end)
end)
