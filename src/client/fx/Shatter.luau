--!strict
--[[
	Shatter (section 11): one effect for every death, the player's included.

	The caller (Replication) has already frozen the rig for combat.deathFreeze with the audio
	ducked. `play(model, kind)` then hides the rig's parts, fires a single white ParticleEmitter
	burst, takes 40 to 80 pooled wedge shards (300 for bosses) from ReplicatedStorage, lays them
	over the limbs with ShatterMath and animates them on the client with CFrames (no physics):
	outward and upward drift, slow rotation, a 6-stud rise over 0.8 s (3 s for bosses), shrinking
	and fading to transparent, then every shard goes back to the pool. The glass crack plays, then
	the rising chime; bosses get the slow crack and the low boom and a camera pull-back hook.

	The pool is pre-warmed on start (spread over frames so it never hitches) at the quality
	tier's size and only grows when a wave of deaths needs more, up to the tier's live cap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Palette = require(Shared.data.palette)
local Signal = require(Shared.util.Signal)
local Engine = require(script.Parent.Engine)
local Quality = require(script.Parent.Quality)
local ShatterMath = require(script.Parent.ShatterMath)
local OutlineManager = require(script.Parent.OutlineManager)
local Trails = require(script.Parent.Trails)
local Telegraphs = require(script.Parent.Telegraphs)
local SfxPool = require(script.Parent.Parent.audio.SfxPool)
local MusicDirector = require(script.Parent.Parent.audio.MusicDirector)

type ShardInstance = {
	part: BasePart,
	shard: ShatterMath.Shard,
	origin: Vector3,
	axis: Vector3,
	size: Vector3,
}

type Live = {
	shards: { ShardInstance },
	start: number,
	duration: number,
	rise: number,
	boss: boolean,
}

local Shatter = {}

--- Fires (center, duration) when a boss shatters, for the camera pull-back (section 11).
Shatter.bossShatter = Signal.new() :: Signal.Signal<Vector3, number>

local pool: { BasePart } = {}
local poolFolder: Instance? = nil
local liveFolder: Instance? = nil
local live: { Live } = {}
local liveShards = 0
local flashPart: BasePart? = nil
local flashEmitter: ParticleEmitter? = nil
local stopLoop: (() -> ())? = nil
local started = false
local seedCounter = 0

local function newShard(): BasePart
	local part = Instance.new("WedgePart")
	part.Name = "Shard"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = poolFolder
	return part
end

local function ensureFolders()
	if poolFolder == nil then
		poolFolder = Engine.folder(ReplicatedStorage, Fx.shatter.poolFolderName)
	end
	if liveFolder == nil then
		liveFolder = Engine.folder(workspace, Fx.shatter.poolFolderName .. "Live")
	end
end

local function ensureFlash()
	if flashEmitter ~= nil then
		return
	end
	ensureFolders()
	local part = Instance.new("Part")
	part.Name = "ShatterFlash"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Flash"
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(Palette.color3(Fx.shatter.flash.token :: any))
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = part
	part.Parent = liveFolder
	flashPart = part
	flashEmitter = emitter
end

local function acquire(): BasePart
	local part = table.remove(pool)
	if part == nil then
		part = newShard()
	end
	return part :: BasePart
end

local function release(part: BasePart)
	part.Transparency = 1
	part.Parent = poolFolder
	table.insert(pool, part)
end

-- The limbs a rig sheds: every visible BasePart except the root, as plain tables.
local function limbsOf(model: Instance): { ShatterMath.Limb }
	local limbs: { ShatterMath.Limb } = {}
	local root: Instance? = nil
	pcall(function()
		root = (model :: any).PrimaryPart
	end)
	for _, part in Engine.parts(model) do
		if part == root or part.Name == "HumanoidRootPart" or part.Transparency >= 1 then
			continue
		end
		table.insert(limbs, { pos = Engine.toTable(part.CFrame.Position), size = Engine.toTable(part.Size) })
	end
	if #limbs == 0 then
		local position = Engine.modelPosition(model)
		if position ~= nil then
			table.insert(limbs, { pos = Engine.toTable(position), size = { 2, 2, 2 } })
		end
	end
	return limbs
end

local function hideRig(model: Instance)
	for _, part in Engine.parts(model) do
		part.LocalTransparencyModifier = Fx.shatter.hiddenTransparency
	end
	OutlineManager.suspend(model, true)
	-- Nothing of the rig's light survives the shatter: a trail or activation light left on by a
	-- death mid-Art, and a wind-up telegraph cut short by the kill.
	Trails.detach(model)
	Telegraphs.hide(model)
end

local function burst(center: Vector3, boss: boolean)
	ensureFlash()
	local flash = Fx.shatter.flash
	local scale = Quality.params().particleScale
	local count = math.floor((if boss then flash.bossParticles else flash.particles) * scale + 0.5)
	local size = if boss then flash.bossSize else flash.size
	local emitter = flashEmitter :: ParticleEmitter
	local part = flashPart :: BasePart
	part.CFrame = CFrame.new(center)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(flash.lifetime)
	emitter.Speed = NumberRange.new(flash.speed)
	if count > 0 then
		pcall(function()
			emitter:Emit(count)
		end)
	end
end

local function step()
	local now = Engine.now()
	for index = #live, 1, -1 do
		local entry = live[index]
		local t = (now - entry.start) / entry.duration
		local done = t >= 1
		for _, instance in entry.shards do
			local state = ShatterMath.shardState(instance.shard, t, entry.duration, entry.rise)
			local part = instance.part
			if done then
				release(part)
			else
				part.CFrame = CFrame.new(instance.origin + Engine.toVector(state.offset))
					* CFrame.fromAxisAngle(instance.axis, math.rad(state.angle))
				part.Size = instance.size * state.scale
				part.Transparency = state.transparency
			end
		end
		if done then
			liveShards -= #entry.shards
			table.remove(live, index)
		end
	end
	if #live == 0 and stopLoop ~= nil then
		stopLoop()
		stopLoop = nil
	end
end

local function ensureLoop()
	if stopLoop ~= nil then
		return
	end
	stopLoop = Engine.onHeartbeat(function()
		step()
	end)
end

--- Pre-warms the pool for the quality tier, a few shards per frame so the floor load never hitches.
function Shatter.start()
	if started then
		return
	end
	started = true
	ensureFolders()
	ensureFlash()
	local target = Quality.params().shatterPoolSize
	local perFrame = Fx.shatter.preWarmPerFrame
	local heartbeat = Engine.heartbeat()
	if heartbeat == nil then
		while #pool < target do
			table.insert(pool, newShard())
		end
		return
	end
	local connection: RBXScriptConnection
	connection = heartbeat:Connect(function()
		for _ = 1, perFrame do
			if #pool >= target then
				connection:Disconnect()
				return
			end
			table.insert(pool, newShard())
		end
	end)
end

--- Hides the frozen rig and plays the shatter for its kind ("Beast" | "Construct" | "Plant" | "Humanoid" | "Boss").
function Shatter.play(model: Instance, kind: string)
	Shatter.start()
	local boss = kind == "Boss"
	local token = Fx.shatter.colors[kind] or Fx.shatter.colors.Beast
	local color = Palette.color3(token :: any)
	local limbs = limbsOf(model)
	local center = Engine.toVector(ShatterMath.center(limbs))
	-- Sounds play at the rig's root (the position the server broadcast). The death reaction leaves
	-- the crack to this call while the rig exists and plays it itself only when the rig is gone.
	local soundPosition = Engine.modelPosition(model) or center
	local params = Quality.params()
	seedCounter += 1
	local seed = math.floor(Engine.now() * 1e6) + seedCounter -- unit: seconds to microseconds for a seed
	local count = ShatterMath.shardCount(boss, seed, params.shardScale)
	local room = params.maxLiveShards - liveShards
	count = math.max(1, math.min(count, room))
	local duration, rise = ShatterMath.timing(boss)

	hideRig(model)
	burst(center, boss)

	local layout = ShatterMath.layout(limbs, count, seed, boss)
	local instances: { ShardInstance } = {}
	for _, shard in layout do
		local part = acquire()
		local size = Engine.toVector(shard.size)
		part.Color = color
		part.Size = size
		part.Transparency = 0
		part.CFrame = CFrame.new(Engine.toVector(shard.pos))
		part.Parent = liveFolder
		table.insert(instances, {
			part = part,
			shard = shard,
			origin = Engine.toVector(shard.pos),
			axis = Engine.toVector(shard.axis),
			size = size,
		})
	end
	liveShards += #instances
	table.insert(live, { shards = instances, start = Engine.now(), duration = duration, rise = rise, boss = boss })
	ensureLoop()

	-- The crack then the rising chime (the slow crack and the boom for a boss) live in SfxPool.
	SfxPool.shatter(soundPosition, boss)
	if boss then
		Shatter.bossShatter:Fire(center, duration)
	end
	MusicDirector.noteShatter()
end

--- Shards animating right now (budget checks and tests).
function Shatter.liveCount(): number
	return liveShards
end

--- Pooled shards waiting (tests and the profiler).
function Shatter.poolCount(): number
	return #pool
end

--- Advances the animation by hand (tests, or a frame outside Heartbeat).
function Shatter.step()
	step()
end

return Shatter
