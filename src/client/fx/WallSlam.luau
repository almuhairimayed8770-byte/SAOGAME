--!strict
--[[
	WallSlam (D-217): the dust a rush throws up where the boar's snout meets a wall.

	One pooled ParticleEmitter on an anchored, invisible, non-colliding part in a workspace folder,
	built the way Sparks builds the parry's. `slam(point, normal)` moves that part to the contact
	point, turns it to look along the face's flat normal (the emitter throws from its front face,
	fanned by spreadAngle along the face) and emits fx.wallSlam.particles scaled by the quality
	tier's particleScale. The puffs live in world space (LockedToPart off), so one emitter serves
	two boars slamming at once and nothing is created per slam. The burst goes through Bursts, which
	clears it on Heartbeat at the longest puff's life, so a slam while nothing renders never billows
	when rendering comes back.

	Dust is lit by the scene and never glows (lightEmission 0): a slam is no flash, so it charges
	nothing against FlashBudget and plays the same with Reduce flashing on. The thud and the shake
	are Replication's, played beside this from fx.wallSlam's cue and shake rows.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Palette = require(Shared.data.palette)
local Engine = require(script.Parent.Engine)
local Quality = require(script.Parent.Quality)
local Bursts = require(script.Parent.Bursts)

local WallSlam = {}

local host: BasePart? = nil
local emitter: ParticleEmitter? = nil

local function ensureEmitter(): (BasePart, ParticleEmitter)
	if host ~= nil and emitter ~= nil then
		return host, emitter
	end
	local dust = Fx.wallSlam
	local part = Instance.new("Part")
	part.Name = "WallSlamDust"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * dust.emitterSize
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Dust"
	particles.Rate = 0
	particles.Enabled = false
	particles.LockedToPart = false
	particles.EmissionDirection = Enum.NormalId.Front
	particles.LightEmission = dust.lightEmission
	particles.Color = ColorSequence.new(Palette.color3(dust.token :: any))
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, dust.transparency.birth),
		NumberSequenceKeypoint.new(1, dust.transparency.death),
	})
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, dust.size.birth),
		NumberSequenceKeypoint.new(1, dust.size.death),
	})
	particles.Lifetime = NumberRange.new(dust.lifetime.min, dust.lifetime.max)
	particles.Speed = NumberRange.new(dust.speed.min, dust.speed.max)
	particles.SpreadAngle = Vector2.new(dust.spreadAngle, dust.spreadAngle)
	particles.Drag = dust.drag
	particles.Acceleration = Vector3.new(0, -dust.gravity, 0)
	particles.Rotation = NumberRange.new(-dust.rotation, dust.rotation)
	particles.RotSpeed = NumberRange.new(-dust.rotSpeed, dust.rotSpeed)
	particles.Parent = part
	part.Parent = Engine.folder(workspace, dust.folderName)
	host = part
	emitter = particles
	return part, particles
end

-- The part's frame at `point`, looking along the face's flat normal (none: as it stood).
local function frameAt(point: Vector3, normal: Vector3, current: CFrame): CFrame
	local flat = Vector3.new(normal.X, 0, normal.Z)
	if flat.Magnitude < 1e-6 then
		return CFrame.new(point) * current.Rotation
	end
	return CFrame.lookAt(point, point + flat.Unit)
end

--- Puffs in one slam at a quality tier's particle scale (rounded, never negative).
function WallSlam.count(scale: number): number
	return math.max(0, math.floor(Fx.wallSlam.particles * scale + 0.5))
end

--- Builds the pooled emitter once so the first slam never allocates (idempotent).
function WallSlam.start()
	ensureEmitter()
end

--- Throws the dust off a wall's face at `point` (`normal`: the face's normal toward the body);
--- returns how many puffs it emitted.
function WallSlam.slam(point: Vector3, normal: Vector3): number
	local part, particles = ensureEmitter()
	local count = WallSlam.count(Quality.params().particleScale)
	part.CFrame = frameAt(point, normal, part.CFrame)
	-- Emit is engine-only; under Lune the call is skipped and the count still reports.
	Bursts.emit(particles, count, Fx.wallSlam.lifetime.max)
	return count
end

--- The pooled emitter, or nil before the first start or slam (tests read its tuning).
function WallSlam.emitter(): ParticleEmitter?
	return emitter
end

return WallSlam
