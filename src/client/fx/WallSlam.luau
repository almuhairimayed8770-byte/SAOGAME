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

	A rush's skid kicks up the same dust, smaller (fx.rushSkid): `skid(point, heading)` puffs it off
	the ground under the hind hooves, thrown back against the way the body slides, from a second
	pooled emitter built the same way in its own folder (RushDraw.takeDust says where and when).
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
local skidHost: BasePart? = nil
local skidEmitter: ParticleEmitter? = nil

-- The tuning a dust emitter is built from (fx.wallSlam, fx.rushSkid).
type Dust = {
	size: { birth: number, death: number },
	transparency: { birth: number, death: number },
	lifetime: { min: number, max: number },
	speed: { min: number, max: number },
	spreadAngle: number,
	drag: number,
	gravity: number,
	rotation: number,
	rotSpeed: number,
	lightEmission: number,
	token: string,
	emitterSize: number,
	folderName: string,
}

-- One pooled dust emitter on an anchored, invisible part named `name` in `dust`'s folder.
local function buildEmitter(dust: Dust, name: string): (BasePart, ParticleEmitter)
	local part = Instance.new("Part")
	part.Name = name
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
	return part, particles
end

local function ensureEmitter(): (BasePart, ParticleEmitter)
	if host ~= nil and emitter ~= nil then
		return host, emitter
	end
	local part, particles = buildEmitter(Fx.wallSlam :: any, "WallSlamDust")
	host = part
	emitter = particles
	return part, particles
end

local function ensureSkidEmitter(): (BasePart, ParticleEmitter)
	if skidHost ~= nil and skidEmitter ~= nil then
		return skidHost, skidEmitter
	end
	local part, particles = buildEmitter(Fx.rushSkid :: any, "RushSkidDust")
	skidHost = part
	skidEmitter = particles
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

--- Puffs in one skid puff at a quality tier's particle scale (rounded, never negative).
function WallSlam.skidCount(scale: number): number
	return math.max(0, math.floor(Fx.rushSkid.particles * scale + 0.5))
end

--- Builds the pooled emitters once so the first slam or skid never allocates (idempotent).
function WallSlam.start()
	ensureEmitter()
	ensureSkidEmitter()
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

--- Kicks up a skid's puff on the ground at `point` (under the hind hooves), thrown back against
--- `heading` (the flat way the body slides); returns how many puffs it emitted.
function WallSlam.skid(point: Vector3, heading: Vector3): number
	local part, particles = ensureSkidEmitter()
	local count = WallSlam.skidCount(Quality.params().particleScale)
	part.CFrame = frameAt(point, -heading, part.CFrame)
	Bursts.emit(particles, count, Fx.rushSkid.lifetime.max)
	return count
end

--- The pooled emitter, or nil before the first start or slam (tests read its tuning).
function WallSlam.emitter(): ParticleEmitter?
	return emitter
end

--- The skid's pooled emitter, or nil before the first start or skid (tests read its tuning).
function WallSlam.skidEmitter(): ParticleEmitter?
	return skidEmitter
end

return WallSlam
