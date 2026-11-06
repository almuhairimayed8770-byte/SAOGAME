--!strict
--[[
	Ambience (section 15: "wind at the rim everywhere", an ambience bed per biome): the world beds
	under the mix, played through SfxPool.loop (2D, on the SFX group, so the death silence ducks
	them and a hit's bass cut takes them out with the world).

	On the Playground island (playground.luau fieldRadius around the field center) the biome bed
	(fx.audio.ambience.bed) plays at full level and the rim wind (rimWind) rises as the local
	character nears the island's edge: rimFloor from rimBand.far studs inside the edge inward,
	eased (rimEasing) up to full level at rimBand.near studs or closer. Off the island (past the
	edge: over the rail, falling) or with no character, both ramp out and stop. Every change is a
	linear gain ramp over rampSeconds (a bed never jumps), and SfxPool.loop stops a bed whose gain
	falls to fx.audio.stemFadeFloor.

	The per-frame step reads the character's position at sampleHz and moves both gains every
	frame. It allocates nothing (no table, closure or string per frame) and calls the loop only
	when a gain moved.

	Engine seams (`bind`): the per-frame step, the local character's root position and the loop
	call. Specs hand in fakes and drive frames by hand; the defaults are Heartbeat, the local
	player's character and SfxPool.loop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Playground = require(Shared.data.playground)
local Easing = require(Shared.util.Easing)
local Engine = require(script.Parent.Parent.fx.Engine)
local SfxPool = require(script.Parent.SfxPool)

export type StepFn = (dt: number) -> ()

export type Deps = {
	onStep: (fn: StepFn) -> () -> (), -- connects the per-frame step; returns its disconnect
	position: () -> Vector3?, -- the local character's root position, nil with no character
	loop: (name: string, gain: number) -> (), -- SfxPool.loop: a bed at a gain, 0 stops it
}

export type Overrides = {
	onStep: ((fn: StepFn) -> () -> ())?,
	position: (() -> Vector3?)?,
	loop: ((name: string, gain: number) -> ())?,
}

export type State = {
	running: boolean, -- the per-frame step is connected
	onIsland: boolean, -- the last sample stood on the island
	edgeDistance: number?, -- studs inside the edge at the last sample (negative past it), nil with no character
	bed: number, -- the bed's gain now
	rim: number, -- the rim wind's gain now
	bedTarget: number,
	rimTarget: number,
}

local Ambience = {}

-- The local character's root: its PrimaryPart (the HumanoidRootPart). Property reads only, so a
-- sample allocates nothing.
local function characterPosition(): Vector3?
	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character.PrimaryPart
	if root == nil then
		return nil
	end
	return root.Position
end

local function defaultDeps(): Deps
	return {
		onStep = Engine.onHeartbeat,
		position = characterPosition,
		loop = SfxPool.loop,
	}
end

local deps: Deps = defaultDeps()
local stopStep: (() -> ())? = nil
local sinceSample = math.huge -- the first frame samples at once
local onIsland = false
local edgeDistance: number? = nil
local bedGain = 0
local rimGain = 0
local bedTarget = 0
local rimTarget = 0
-- The position handed to Playground.distanceFromCenter, reused so a sample allocates nothing.
local scratch = { 0, 0, 0 }

--- Studs from a position to the island's edge, measured inward (negative past the edge).
function Ambience.edgeDistance(position: Vector3): number
	scratch[1], scratch[2], scratch[3] = position.X, position.Y, position.Z
	return Playground.fieldRadius - Playground.distanceFromCenter(scratch)
end

--- The rim wind's gain `edge` studs inside the island's edge: rimFloor at rimBand.far or farther, eased up to 1 at rimBand.near or closer.
function Ambience.rimGainAt(edge: number): number
	local config = Fx.audio.ambience
	local band = config.rimBand
	local closeness = math.clamp((band.far - edge) / (band.far - band.near), 0, 1)
	return config.rimFloor + (1 - config.rimFloor) * Easing.evaluate(config.rimEasing, closeness)
end

-- Reads where the character stands and sets both targets.
local function sample()
	local position = deps.position()
	if position == nil then
		onIsland = false
		edgeDistance = nil
		bedTarget, rimTarget = 0, 0
		return
	end
	local edge = Ambience.edgeDistance(position)
	edgeDistance = edge
	onIsland = edge >= 0
	if onIsland then
		bedTarget = 1
		rimTarget = Ambience.rimGainAt(edge)
	else
		bedTarget, rimTarget = 0, 0
	end
end

-- `current` moved toward `target` by at most `maxStep`.
local function approach(current: number, target: number, maxStep: number): number
	if current < target then
		return math.min(target, current + maxStep)
	end
	return math.max(target, current - maxStep)
end

local function step(dt: number)
	local config = Fx.audio.ambience
	local interval = 1 / config.sampleHz
	sinceSample += dt
	if sinceSample >= interval then
		-- Keep the rate on average; after a long frame (or the first one) start the count afresh.
		sinceSample = if sinceSample >= 2 * interval then 0 else sinceSample - interval
		sample()
	end
	local maxStep = if config.rampSeconds > 0 then dt / config.rampSeconds else 1
	local nextBed = approach(bedGain, bedTarget, maxStep)
	if nextBed ~= bedGain then
		bedGain = nextBed
		deps.loop(config.bed, bedGain)
	end
	local nextRim = approach(rimGain, rimTarget, maxStep)
	if nextRim ~= rimGain then
		rimGain = nextRim
		deps.loop(config.rimWind, rimGain)
	end
end

--- Connects the per-frame step (idempotent): from the next frame both beds follow the local character.
function Ambience.start()
	if stopStep ~= nil then
		return
	end
	stopStep = deps.onStep(step)
end

--- Stops both beds at once and disconnects the step (a teardown; start() connects it again).
function Ambience.stop()
	if stopStep ~= nil then
		local disconnect = stopStep :: () -> ()
		stopStep = nil
		disconnect()
	end
	local config = Fx.audio.ambience
	if bedGain > 0 then
		deps.loop(config.bed, 0)
	end
	if rimGain > 0 then
		deps.loop(config.rimWind, 0)
	end
	bedGain, rimGain, bedTarget, rimTarget = 0, 0, 0, 0
	onIsland, edgeDistance = false, nil
	sinceSample = math.huge
end

--- Replaces the per-frame step, the character position or the loop call (specs); nil restores the engine. Stops first.
function Ambience.bind(overrides: Overrides?)
	Ambience.stop()
	local base = defaultDeps()
	if overrides ~= nil then
		base.onStep = overrides.onStep or base.onStep
		base.position = overrides.position or base.position
		base.loop = overrides.loop or base.loop
	end
	deps = base
end

--- Where the beds are now (specs and the profiler).
function Ambience.state(): State
	return {
		running = stopStep ~= nil,
		onIsland = onIsland,
		edgeDistance = edgeDistance,
		bed = bedGain,
		rim = rimGain,
		bedTarget = bedTarget,
		rimTarget = rimTarget,
	}
end

return Ambience
