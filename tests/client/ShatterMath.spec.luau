local ShatterMath = Harness.load("src/client/fx/ShatterMath")
local Fx = Harness.load("src/shared/data/fx")

local function koboldLimbs()
	return {
		{ pos = { 0, 3, 0 }, size = { 2.2, 2.4, 1.2 } }, -- torso
		{ pos = { 0, 5, 0 }, size = { 1.5, 1.4, 1.5 } }, -- head
		{ pos = { -1.5, 3, 0 }, size = { 0.9, 2.2, 0.9 } }, -- left arm
		{ pos = { 1.5, 3, 0 }, size = { 0.9, 2.2, 0.9 } }, -- right arm
		{ pos = { -0.6, 1, 0 }, size = { 0.9, 2.2, 0.9 } }, -- left leg
		{ pos = { 0.6, 1, 0 }, size = { 0.9, 2.2, 0.9 } }, -- right leg
	}
end

local function length(v)
	return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
end

describe("ShatterMath", function()
	it("centers the rig on the mean of its limbs", function()
		local center = ShatterMath.center(koboldLimbs())
		expect(center[1]).toBeCloseTo(0)
		expect(center[2]).toBeCloseTo((3 + 5 + 3 + 3 + 1 + 1) / 6)
		expect(ShatterMath.center({})).toEqual({ 0, 0, 0 })
	end)

	it("shard counts sit in the spec's range and bosses get the boss count", function()
		local shards = Fx.shatter.shards
		for seed = 1, 50 do
			local count = ShatterMath.shardCount(false, seed, 1)
			expect(count).toBeGreaterThanOrEqual(shards.min)
			expect(count).toBeLessThanOrEqual(shards.max)
		end
		expect(ShatterMath.shardCount(true, 1, 1)).toBe(shards.boss)
		expect(ShatterMath.shardCount(true, 1, 0.5)).toBe(shards.boss / 2)
		expect(ShatterMath.shardCount(false, 3, 0)).toBe(1)
	end)

	it("lays out the requested number of shards deterministically", function()
		local a = ShatterMath.layout(koboldLimbs(), 60, 42, false)
		local b = ShatterMath.layout(koboldLimbs(), 60, 42, false)
		local c = ShatterMath.layout(koboldLimbs(), 60, 43, false)
		expect(#a).toBe(60)
		expect(a).toEqual(b)
		expect(a[1].pos).never.toEqual(c[1].pos)
		expect(#ShatterMath.layout({}, 10, 1, false)).toBe(0)
	end)

	it("every shard spawns inside its limb, drifts outward and up, and has a unit axis", function()
		local limbs = koboldLimbs()
		local center = ShatterMath.center(limbs)
		local shards = ShatterMath.layout(limbs, 80, 7, false)
		for index, shard in shards do
			local limb = limbs[((index - 1) % #limbs) + 1]
			for axis = 1, 3 do
				expect(math.abs(shard.pos[axis] - limb.pos[axis])).toBeLessThanOrEqual(limb.size[axis] * 0.5 + 1e-6)
			end
			expect(length(shard.dir)).toBeCloseTo(1, 1e-6)
			expect(length(shard.axis)).toBeCloseTo(1, 1e-6)
			expect(shard.dir[2]).toBeGreaterThan(-1) -- never straight down
			-- Outward: the horizontal part of the direction points away from the center.
			local dx, dz = shard.pos[1] - center[1], shard.pos[3] - center[3]
			if math.abs(dx) + math.abs(dz) > 0.2 then
				expect(shard.dir[1] * dx + shard.dir[3] * dz).toBeGreaterThanOrEqual(-1e-6)
			end
			expect(shard.speed).toBeGreaterThanOrEqual(Fx.shatter.outwardSpeed.min)
			expect(shard.speed).toBeLessThanOrEqual(Fx.shatter.outwardSpeed.max)
			expect(shard.size[2]).toBeGreaterThanOrEqual(Fx.shatter.shardSize.min)
			expect(shard.size[2]).toBeLessThanOrEqual(Fx.shatter.shardSize.max)
		end
	end)

	it("boss shards are bigger", function()
		local shards = ShatterMath.layout(koboldLimbs(), 300, 9, true)
		expect(#shards).toBe(300)
		for _, shard in shards do
			expect(shard.size[2]).toBeGreaterThanOrEqual(Fx.shatter.bossShardSize.min)
		end
	end)

	it("a shard rises the full height, shrinks and fades to transparent by the end", function()
		local shard = ShatterMath.layout(koboldLimbs(), 1, 5, false)[1]
		local duration, rise = ShatterMath.timing(false)
		expect(duration).toBe(Fx.shatter.duration)
		local start = ShatterMath.shardState(shard, 0, duration, rise)
		expect(start.offset).toEqual({ 0, 0, 0 })
		expect(start.scale).toBeCloseTo(1)
		expect(start.transparency).toBe(0)

		local finish = ShatterMath.shardState(shard, 1, duration, rise)
		expect(finish.transparency).toBeCloseTo(1)
		expect(finish.scale).toBeCloseTo(Fx.shatter.shrinkEnd)
		-- The rise is the eased lift plus whatever upward drift the shard carries.
		expect(finish.offset[2]).toBeGreaterThanOrEqual(rise - 1e-6)

		local mid = ShatterMath.shardState(shard, 0.5, duration, rise)
		expect(mid.offset[2]).toBeGreaterThan(0)
		expect(mid.offset[2]).toBeLessThan(finish.offset[2])
		expect(mid.scale).toBeLessThan(1)
		expect(mid.scale).toBeGreaterThan(finish.scale)
		-- Past the end it clamps instead of exploding.
		expect(ShatterMath.shardState(shard, 2, duration, rise).transparency).toBeCloseTo(1)
	end)

	it("the rise eases out: more than half the height by half the time", function()
		local shard = ShatterMath.layout(koboldLimbs(), 1, 11, false)[1]
		shard.dir = { 1, 0, 0 } -- isolate the lift from the drift
		local duration, rise = ShatterMath.timing(false)
		local mid = ShatterMath.shardState(shard, 0.5, duration, rise)
		expect(mid.offset[2]).toBeGreaterThan(rise * 0.5)
		-- Drift slows under drag: the second half covers less ground than the first.
		local quarter = ShatterMath.shardState(shard, 0.25, duration, rise).offset[1]
		local half = mid.offset[1]
		local full = ShatterMath.shardState(shard, 1, duration, rise).offset[1]
		expect(half - quarter).toBeLessThan(quarter)
		expect(full - half).toBeLessThan(half)
	end)

	it("fades only after the fade start and spins continuously", function()
		local shard = ShatterMath.layout(koboldLimbs(), 1, 13, false)[1]
		local duration, rise = ShatterMath.timing(true)
		expect(duration).toBe(Fx.shatter.bossDuration)
		local before = ShatterMath.shardState(shard, Fx.shatter.fadeStart - 0.01, duration, rise)
		expect(before.transparency).toBe(0)
		local after = ShatterMath.shardState(shard, Fx.shatter.fadeStart + 0.1, duration, rise)
		expect(after.transparency).toBeGreaterThan(0)
		local a = ShatterMath.shardState(shard, 0.1, duration, rise).angle
		local b = ShatterMath.shardState(shard, 0.2, duration, rise).angle
		expect(a).never.toBe(b)
		expect(a).toBeGreaterThanOrEqual(0)
		expect(a).toBeLessThan(360)
	end)
end)
