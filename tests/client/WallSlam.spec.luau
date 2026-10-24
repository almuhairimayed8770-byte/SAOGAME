--!strict
-- A rush's slam on a wall (D-217): one pooled dust emitter tuned from fx.luau's wallSlam block,
-- moved to where the snout meets the face and turned to throw the dust off it, emitting the
-- quality tier's share of the puffs. Dust is lit by the scene and never glows, so a slam charges
-- no flash: it stays out of the flash budget (3 a second) and plays the same with Reduce flashing.
-- Emit itself is engine-only, so the burst's count is read from the return value.
local WallSlam = Harness.load("src/client/fx/WallSlam")
local Bursts = Harness.load("src/client/fx/Bursts")
local Quality = Harness.load("src/client/fx/Quality")
local FlashBudget = Harness.load("src/client/fx/FlashBudget")
local fx = Harness.load("src/shared/data/fx")
local palette = Harness.load("src/shared/data/palette")
local Sfx = Harness.load("src/shared/data/sfx")
local Combat = Harness.load("src/shared/data/combat")

local slam = fx.wallSlam

-- Runs `body` at a quality tier and restores the tier other specs see.
local function atTier(tier: string, body: () -> ())
	local before = Quality.get()
	Quality.set(tier)
	-- Typed to return a value so the failure's message has a slot (the body returns none).
	local ok, err = pcall(body :: () -> any)
	Quality.set(before)
	if not ok then
		error(err, 0)
	end
end

describe("WallSlam", function()
	it("names a palette token, an sfx cue and a shake tier, and stays a small share of the budget", function()
		expect(palette.tokens[slam.token]).never.toBeNil()
		expect(Sfx.cues[slam.cue]).never.toBeNil()
		expect(Combat.cameraShakeStuds[slam.shakeTier]).never.toBeNil()
		expect(slam.particles).toBeGreaterThan(0)
		expect(slam.particles).toBeLessThan(fx.budgets.particles)
		expect(slam.lifetime.max).toBeGreaterThanOrEqual(slam.lifetime.min)
		expect(slam.speed.max).toBeGreaterThanOrEqual(slam.speed.min)
		expect(slam.size.death).toBeGreaterThan(slam.size.birth)
		expect(slam.shakeRadius).toBeGreaterThan(0)
	end)

	it("is dust, never light: no glow, so it is never a flash", function()
		expect(slam.lightEmission).toBe(0)
		WallSlam.start()
		local emitter = WallSlam.emitter() :: ParticleEmitter
		expect(emitter.LightEmission).toBeCloseTo(0, 1e-6)
	end)

	it("scales the burst by the quality tier's particleScale", function()
		expect(WallSlam.count(1)).toBe(slam.particles)
		expect(WallSlam.count(fx.quality.Medium.particleScale)).toBe(
			math.floor(slam.particles * fx.quality.Medium.particleScale + 0.5)
		)
		expect(WallSlam.count(fx.quality.Low.particleScale)).toBeLessThan(slam.particles)
		expect(WallSlam.count(0)).toBe(0)
		atTier("High", function()
			expect(WallSlam.slam(Vector3.zero, Vector3.zAxis)).toBe(WallSlam.count(fx.quality.High.particleScale))
		end)
		atTier("Low", function()
			expect(WallSlam.slam(Vector3.zero, Vector3.zAxis)).toBe(WallSlam.count(fx.quality.Low.particleScale))
		end)
	end)

	it("moves one pooled, invisible, anchored emitter to each contact, throwing the dust off the face", function()
		WallSlam.start()
		local emitter = WallSlam.emitter() :: ParticleEmitter
		expect(emitter).never.toBeNil()
		local host = emitter.Parent :: BasePart
		expect(host:IsA("BasePart")).toBe(true)
		expect(host.Anchored).toBe(true)
		expect(host.CanCollide).toBe(false)
		expect(host.CanQuery).toBe(false)
		expect(host.CanTouch).toBe(false)
		expect(host.Transparency).toBeCloseTo(1, 1e-6)
		-- The emitter throws from its part's front face: the part looks along the face's normal.
		expect(emitter.EmissionDirection).toBe(Enum.NormalId.Front)

		local normal = Vector3.new(1, 0, -1).Unit
		WallSlam.slam(Vector3.new(4, 5, 6), normal)
		local frame = host.CFrame
		expect(frame.Position.X).toBeCloseTo(4, 1e-4)
		expect(frame.Position.Y).toBeCloseTo(5, 1e-4)
		expect(frame.Position.Z).toBeCloseTo(6, 1e-4)
		expect(frame.LookVector:Dot(normal)).toBeCloseTo(1, 1e-4)
		WallSlam.slam(Vector3.new(-2, 1, 9), -Vector3.xAxis)
		expect(WallSlam.emitter()).toBe(emitter)
		expect(host.CFrame.Position.X).toBeCloseTo(-2, 1e-4)
		expect(host.CFrame.Position.Z).toBeCloseTo(9, 1e-4)
		expect(host.CFrame.LookVector:Dot(-Vector3.xAxis)).toBeCloseTo(1, 1e-4)
		-- A normal with a tilt in it (a sloped face) or none at all: the dust leaves flat off the face.
		WallSlam.slam(Vector3.zero, Vector3.new(0, 0.5, 1))
		expect(host.CFrame.LookVector.Y).toBeCloseTo(0, 1e-4)
		expect(host.CFrame.LookVector.Z).toBeCloseTo(1, 1e-4)
		WallSlam.slam(Vector3.new(1, 2, 3), Vector3.zero)
		expect(host.CFrame.Position.X).toBeCloseTo(1, 1e-4)
	end)

	it("tunes the emitter from fx.wallSlam: bursts only, world-space puffs that billow and fade", function()
		WallSlam.start()
		local emitter = WallSlam.emitter() :: ParticleEmitter
		expect(emitter.Rate).toBeCloseTo(0, 1e-6)
		expect(emitter.Enabled).toBe(false)
		expect(emitter.LockedToPart).toBe(false)
		expect(emitter.Lifetime.Min).toBeCloseTo(slam.lifetime.min, 1e-4)
		expect(emitter.Lifetime.Max).toBeCloseTo(slam.lifetime.max, 1e-4)
		expect(emitter.Speed.Min).toBeCloseTo(slam.speed.min, 1e-4)
		expect(emitter.Speed.Max).toBeCloseTo(slam.speed.max, 1e-4)
		expect(emitter.Drag).toBeCloseTo(slam.drag, 1e-4)
		expect(emitter.Acceleration.Y).toBeCloseTo(-slam.gravity, 1e-4)
		expect(emitter.SpreadAngle.X).toBeCloseTo(slam.spreadAngle, 1e-4)
		local sizes = emitter.Size.Keypoints
		expect(sizes[1].Value).toBeCloseTo(slam.size.birth, 1e-4)
		expect(sizes[#sizes].Value).toBeCloseTo(slam.size.death, 1e-4)
		local fades = emitter.Transparency.Keypoints
		expect(fades[1].Value).toBeCloseTo(slam.transparency.birth, 1e-4)
		expect(fades[#fades].Value).toBeCloseTo(1, 1e-6)
	end)

	it("charges no flash: any number of slams leave the flash budget as it was, Reduce flashing or not", function()
		FlashBudget.reset()
		local ok, err = pcall(function()
			for _, reduced in { false, true } do
				FlashBudget.set(reduced)
				local before = FlashBudget.used(100)
				for index = 1, 10 do
					expect(WallSlam.slam(Vector3.new(index, 0, 0), Vector3.zAxis)).toBe(
						WallSlam.count(Quality.params().particleScale)
					)
				end
				expect(FlashBudget.used(100)).toBe(before)
				-- Three flashes still fit the second after them.
				expect(FlashBudget.request(100, 1)).toBe(true)
				expect(FlashBudget.request(100, 1)).toBe(true)
				expect(FlashBudget.request(100, 1)).toBe(true)
				FlashBudget.reset()
			end
		end)
		FlashBudget.reset()
		if not ok then
			error(err, 0)
		end
	end)

	it("is started by Main after the quality tier and bound into Replication as its wallSlam", function()
		local main = Harness.readFile("src/client/Main.client.luau")
		local block = main:match("local SIBLING_ORDER = (%b{})")
		expect(block).never.toBeNil()
		local order = {}
		for path in (block :: string):gmatch('"([%w%.]+)"') do
			table.insert(order, path)
		end
		local at = table.find(order, "fx.WallSlam")
		expect(at).never.toBeNil()
		expect(at :: number).toBeGreaterThan(table.find(order, "fx.Quality") :: number)
		local replication = Harness.readFile("src/client/controllers/Replication.luau")
		expect(replication:find('wallSlam = Siblings.load(Client, "fx.WallSlam")', 1, true)).never.toBeNil()
	end)

	-- The display asleep (RenderStepped 0/s, Heartbeat 60/s): a slam then never flies when
	-- rendering comes back; the burst is cleared on Heartbeat at its longest puff's life.
	it("clears a slam's burst on Heartbeat at its longest puff's life (a render stall)", function()
		local clock = 0
		local watch: ((number) -> ())? = nil
		local cleared: { { emitter: any, at: number } } = {}
		local emitted = 0
		Bursts.bind({
			now = function(): number
				return clock
			end,
			onHeartbeat = function(fn: (number) -> ()): () -> ()
				watch = fn
				return function()
					if watch == fn then
						watch = nil
					end
				end
			end,
			emit = function(_emitter: any, count: number)
				emitted += count
			end,
			clear = function(emitter: any)
				table.insert(cleared, { emitter = emitter, at = clock })
			end,
		})
		local ok, err = pcall(function()
			atTier("High", function()
				local count = WallSlam.slam(Vector3.new(1, 2, 3), Vector3.xAxis)
				expect(emitted).toBe(count)
				expect(watch).never.toBeNil()
				local F = 1 / 60
				while watch ~= nil and clock < 5 do
					clock += F
					local beat = watch :: (number) -> ()
					beat(F)
				end
				expect(#cleared).toBe(1)
				expect(cleared[1].emitter).toBe(WallSlam.emitter())
				expect(cleared[1].at).toBeGreaterThanOrEqual(slam.lifetime.max - 1e-9)
				expect(cleared[1].at).toBeLessThanOrEqual(slam.lifetime.max + F + 1e-9)
			end)
		end)
		Bursts.reset()
		Bursts.bind(nil)
		if not ok then
			error(err, 0)
		end
	end)
end)
