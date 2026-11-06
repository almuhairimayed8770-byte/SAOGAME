--!strict
--[[
	Sparks (section 6): the perfect-parry spark burst that goes with the metallic ring.

	One pooled ParticleEmitter on an anchored, invisible, non-colliding part in a workspace folder.
	`parry(position)` moves that part to the clash point and emits fx.parrySpark.particles scaled by
	the quality tier's particleScale. The sparks fly in world space (LockedToPart off), so the one
	emitter serves back-to-back parries at different points and nothing is created per burst. The
	burst goes through Bursts, which clears it on Heartbeat at the longest spark's life, so a parry
	while nothing renders (the display asleep) never flies when rendering comes back.
	Every number lives in fx.luau's parrySpark block; the ring itself is SfxPool's guard.Parry,
	which Replication plays beside the burst.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Palette = require(Shared.data.palette)
local Engine = require(script.Parent.Engine)
local Quality = require(script.Parent.Quality)
local Bursts = require(script.Parent.Bursts)

local Sparks = {}

local host: BasePart? = nil
local emitter: ParticleEmitter? = nil

local function ensureEmitter(): (BasePart, ParticleEmitter)
	if host ~= nil and emitter ~= nil then
		return host, emitter
	end
	local spark = Fx.parrySpark
	local part = Instance.new("Part")
	part.Name = "ParrySparks"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * spark.emitterSize
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Sparks"
	particles.Rate = 0
	particles.Enabled = false
	particles.LockedToPart = false
	particles.LightEmission = spark.lightEmission
	particles.Color = ColorSequence.new(Palette.color3(spark.token :: any), Palette.color3(spark.tailToken :: any))
	particles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spark.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Lifetime = NumberRange.new(spark.lifetime.min, spark.lifetime.max)
	particles.Speed = NumberRange.new(spark.speed.min, spark.speed.max)
	particles.SpreadAngle = Vector2.new(spark.spreadAngle, spark.spreadAngle)
	particles.Drag = spark.drag
	particles.Acceleration = Vector3.new(0, -spark.gravity, 0)
	particles.Orientation = (Enum.ParticleOrientation :: any)[spark.orientation]
	particles.Parent = part
	part.Parent = Engine.folder(workspace, spark.folderName)
	host = part
	emitter = particles
	return part, particles
end

--- Particles in one burst at a quality tier's particle scale (rounded, never negative).
function Sparks.count(scale: number): number
	return math.max(0, math.floor(Fx.parrySpark.particles * scale + 0.5))
end

--- Builds the pooled emitter once so the first parry never allocates (idempotent).
function Sparks.start()
	ensureEmitter()
end

--- Throws the spark burst at a world position; returns how many particles it emitted.
function Sparks.parry(position: Vector3): number
	local part, particles = ensureEmitter()
	local count = Sparks.count(Quality.params().particleScale)
	part.CFrame = CFrame.new(position)
	-- Emit is engine-only; under Lune the call is skipped and the count still reports.
	Bursts.emit(particles, count, Fx.parrySpark.lifetime.max)
	return count
end

--- The pooled emitter, or nil before the first start or burst (tests read its tuning).
function Sparks.emitter(): ParticleEmitter?
	return emitter
end

return Sparks
