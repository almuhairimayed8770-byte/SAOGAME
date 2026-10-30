--!strict
--[[
	ShatterMath: the pure geometry of the shatter (section 11). Given the rig's limb positions and
	a seed, it lays out N shards (where each spawns, which way it drifts, how fast it spins, how
	big it is) and evaluates one shard's offset, scale, rotation and transparency at a normalized
	time. No Roblox datatypes: Shatter.luau turns the plain tables into CFrames every frame.

	Deterministic: the same limbs and seed give the same layout, so a death looks the same to
	every client that shares the seed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Easing = require(Shared.util.Easing)
local Fx = require(Shared.data.fx)

export type Vec3 = { number }

export type Limb = {
	pos: Vec3, -- world position of the limb's center
	size: Vec3, -- the limb's size
}

export type Shard = {
	pos: Vec3, -- spawn position
	dir: Vec3, -- unit drift direction (outward and up)
	speed: number, -- studs per second at t = 0
	axis: Vec3, -- unit spin axis
	spin: number, -- degrees per second
	size: Vec3, -- wedge size
	phase: number, -- 0..1 random offset for per-shard variation
}

export type Params = {
	count: number,
	boss: boolean,
}

export type ShardState = {
	offset: Vec3, -- studs from the spawn position
	scale: number, -- size multiplier
	angle: number, -- degrees around `axis`
	transparency: number,
}

local ShatterMath = {}

-- Seeded Random so a layout is reproducible for a given seed (the harness shims Random in Lune).
local function newRng(seed: number): Random
	return Random.new(math.floor(math.abs(seed)))
end

local function nextUnit(rng: Random): number
	return rng:NextNumber()
end

local function nextRange(rng: Random, min: number, max: number): number
	return min + (max - min) * rng:NextNumber()
end

local function length(v: Vec3): number
	return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
end

local function normalize(v: Vec3): Vec3
	local len = length(v)
	if len < 1e-6 then
		return { 0, 1, 0 }
	end
	return { v[1] / len, v[2] / len, v[3] / len }
end

--- The center of the rig as the mean of its limb centers (the point shards fly away from).
function ShatterMath.center(limbs: { Limb }): Vec3
	local count = #limbs
	if count == 0 then
		return { 0, 0, 0 }
	end
	local x, y, z = 0, 0, 0
	for _, limb in limbs do
		x += limb.pos[1]
		y += limb.pos[2]
		z += limb.pos[3]
	end
	return { x / count, y / count, z / count }
end

--- How many shards a death gets: boss count, or a seeded value in [min, max], scaled by `shardScale`.
function ShatterMath.shardCount(boss: boolean, seed: number, shardScale: number): number
	local shards = Fx.shatter.shards
	local base
	if boss then
		base = shards.boss
	else
		base = math.floor(nextRange(newRng(seed + 1), shards.min, shards.max + 1))
	end
	return math.max(1, math.floor(base * shardScale))
end

--- Lays out `count` shards over the limbs: each shard spawns inside a limb (jittered), drifts
--- outward from the rig center with an upward tilt, and gets its own spin and size.
function ShatterMath.layout(limbs: { Limb }, count: number, seed: number, boss: boolean): { Shard }
	local rng = newRng(seed)
	local config = Fx.shatter
	local sizeRange = if boss then config.bossShardSize else config.shardSize
	local center = ShatterMath.center(limbs)
	local result: { Shard } = {}
	if #limbs == 0 then
		return result
	end
	for index = 1, count do
		-- Round-robin over limbs so every limb sheds shards; the jitter spreads them inside it.
		local limb = limbs[((index - 1) % #limbs) + 1]
		local jitter = config.limbJitter
		local pos: Vec3 = {
			limb.pos[1] + nextRange(rng, -1, 1) * limb.size[1] * 0.5 * jitter,
			limb.pos[2] + nextRange(rng, -1, 1) * limb.size[2] * 0.5 * jitter,
			limb.pos[3] + nextRange(rng, -1, 1) * limb.size[3] * 0.5 * jitter,
		}
		local outward = normalize({ pos[1] - center[1], pos[2] - center[2], pos[3] - center[3] })
		-- A shard at the exact center still needs a direction: scatter it.
		if length({ pos[1] - center[1], pos[2] - center[2], pos[3] - center[3] }) < 1e-6 then
			outward = normalize({ nextRange(rng, -1, 1), nextRange(rng, 0, 1), nextRange(rng, -1, 1) })
		end
		local dir = normalize({
			outward[1],
			outward[2] + config.upwardBias,
			outward[3],
		})
		local axis = normalize({ nextRange(rng, -1, 1), nextRange(rng, -1, 1), nextRange(rng, -1, 1) })
		local base = nextRange(rng, sizeRange.min, sizeRange.max)
		table.insert(result, {
			pos = pos,
			dir = dir,
			speed = nextRange(rng, config.outwardSpeed.min, config.outwardSpeed.max),
			axis = axis,
			spin = nextRange(rng, config.rotationSpeed.min, config.rotationSpeed.max),
			size = {
				base * nextRange(rng, config.shardAspect.min, config.shardAspect.max),
				base,
				base * nextRange(rng, config.shardAspect.min, config.shardAspect.max),
			},
			phase = nextUnit(rng),
		})
	end
	return result
end

--- One shard's state at normalized time `t` (0 = spawn, 1 = gone) for a shatter of `duration`
--- seconds and `rise` studs. Drift decays with drag; the rise eases out; shards shrink and fade.
function ShatterMath.shardState(shard: Shard, t: number, duration: number, rise: number): ShardState
	local config = Fx.shatter
	local clamped = math.clamp(t, 0, 1)
	local seconds = clamped * duration
	-- Outward drift under exponential drag: distance = v0 / k * (1 - e^(-k s)).
	local drag = config.drag
	local drift = if drag > 1e-6 then shard.speed / drag * (1 - math.exp(-drag * seconds)) else shard.speed * seconds
	local lift = rise * Easing.evaluate(config.riseEasing, clamped)
	local offset: Vec3 = {
		shard.dir[1] * drift,
		shard.dir[2] * drift + lift,
		shard.dir[3] * drift,
	}
	local shrink = 1 - (1 - config.shrinkEnd) * (clamped * clamped)
	local fadeStart = config.fadeStart
	local transparency = if clamped <= fadeStart then 0 else (clamped - fadeStart) / math.max(1e-6, 1 - fadeStart)
	return {
		offset = offset,
		scale = shrink,
		angle = (shard.spin * seconds + shard.phase * 360) % 360,
		transparency = math.clamp(transparency, 0, 1),
	}
end

--- The duration and rise for a shatter kind (bosses take longer and climb higher).
function ShatterMath.timing(boss: boolean): (number, number)
	if boss then
		return Fx.shatter.bossDuration, Fx.shatter.bossRise
	end
	return Fx.shatter.duration, Fx.shatter.rise
end

return ShatterMath
