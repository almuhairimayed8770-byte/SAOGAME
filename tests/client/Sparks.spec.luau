--!strict
-- The perfect-parry spark burst (section 6): one pooled emitter tuned from fx.luau's parrySpark
-- block, moved to the clash point and emitting the quality tier's share of the particles.
-- Emit itself is engine-only, so the burst's count is read from the return value.
local Sparks = Harness.load("src/client/fx/Sparks")
local Quality = Harness.load("src/client/fx/Quality")
local fx = Harness.load("src/shared/data/fx")
local palette = Harness.load("src/shared/data/palette")

local spark = fx.parrySpark

-- Runs `body` at a quality tier and restores the tier other specs see.
local function atTier(tier: string, body: () -> ())
	local before = Quality.get()
	Quality.set(tier)
	local ok, err = pcall(body)
	Quality.set(before)
	if not ok then
		error(err, 0)
	end
end

describe("Sparks", function()
	it("names palette tokens and an engine particle orientation", function()
		expect(palette.tokens[spark.token]).never.toBeNil()
		expect(palette.tokens[spark.tailToken]).never.toBeNil()
		expect((Enum.ParticleOrientation :: any)[spark.orientation]).never.toBeNil()
		expect(spark.particles).toBeGreaterThan(0)
		expect(spark.lifetime.max).toBeGreaterThanOrEqual(spark.lifetime.min)
		expect(spark.speed.max).toBeGreaterThanOrEqual(spark.speed.min)
		-- One burst stays a small share of the section 11 scene budget of live particles.
		expect(spark.particles).toBeLessThan(fx.budgets.particles)
	end)

	it("scales the burst by the quality tier's particleScale", function()
		expect(Sparks.count(1)).toBe(spark.particles)
		expect(Sparks.count(fx.quality.Medium.particleScale)).toBe(
			math.floor(spark.particles * fx.quality.Medium.particleScale + 0.5)
		)
		expect(Sparks.count(fx.quality.Low.particleScale)).toBeLessThan(spark.particles)
		expect(Sparks.count(0)).toBe(0)
		atTier("High", function()
			expect(Sparks.parry(Vector3.zero)).toBe(Sparks.count(fx.quality.High.particleScale))
		end)
		atTier("Low", function()
			expect(Sparks.parry(Vector3.zero)).toBe(Sparks.count(fx.quality.Low.particleScale))
		end)
	end)

	it("moves one pooled, invisible, anchored emitter to each clash point", function()
		Sparks.start()
		local emitter = Sparks.emitter() :: ParticleEmitter
		expect(emitter).never.toBeNil()
		local host = emitter.Parent :: BasePart
		expect(host:IsA("BasePart")).toBe(true)
		expect(host.Anchored).toBe(true)
		expect(host.CanCollide).toBe(false)
		expect(host.CanQuery).toBe(false)
		expect(host.Transparency).toBeCloseTo(1, 1e-6)

		Sparks.parry(Vector3.new(4, 5, 6))
		local at = host.CFrame.Position
		expect(at.X).toBeCloseTo(4, 1e-4)
		expect(at.Y).toBeCloseTo(5, 1e-4)
		expect(at.Z).toBeCloseTo(6, 1e-4)
		Sparks.parry(Vector3.new(-2, 1, 9))
		expect(Sparks.emitter()).toBe(emitter)
		expect(host.CFrame.Position.X).toBeCloseTo(-2, 1e-4)
		expect(host.CFrame.Position.Z).toBeCloseTo(9, 1e-4)
	end)

	it("tunes the emitter from fx.parrySpark: bursts only, world-space sparks", function()
		Sparks.start()
		local emitter = Sparks.emitter() :: ParticleEmitter
		expect(emitter.Rate).toBeCloseTo(0, 1e-6)
		expect(emitter.Enabled).toBe(false)
		expect(emitter.LockedToPart).toBe(false)
		expect(emitter.LightEmission).toBeCloseTo(spark.lightEmission, 1e-4)
		expect(emitter.Lifetime.Min).toBeCloseTo(spark.lifetime.min, 1e-4)
		expect(emitter.Lifetime.Max).toBeCloseTo(spark.lifetime.max, 1e-4)
		expect(emitter.Speed.Min).toBeCloseTo(spark.speed.min, 1e-4)
		expect(emitter.Speed.Max).toBeCloseTo(spark.speed.max, 1e-4)
		expect(emitter.Drag).toBeCloseTo(spark.drag, 1e-4)
		expect(emitter.Acceleration.Y).toBeCloseTo(-spark.gravity, 1e-4)
		expect(emitter.SpreadAngle.X).toBeCloseTo(spark.spreadAngle, 1e-4)
		expect(emitter.Orientation).toBe((Enum.ParticleOrientation :: any)[spark.orientation])
		local sizes = emitter.Size.Keypoints
		expect(sizes[1].Value).toBeCloseTo(spark.size, 1e-4)
		expect(sizes[#sizes].Value).toBeCloseTo(0, 1e-6)
	end)
end)
