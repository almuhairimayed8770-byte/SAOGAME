--!strict
--[[
	SwitchRing (section 11): a thin SystemCyan ring that expands from the enemy's hit point over
	the Switch window. The ring is a circle of pooled thin Neon segments laid tangent around the
	radius; the radius grows with an ease-out (never linear) and the ring fades in its last part.
	Every segment is reused; nothing is created after the first ring.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Palette = require(Shared.data.palette)
local Easing = require(Shared.util.Easing)
local Engine = require(script.Parent.Engine)

type Ring = {
	segments: { BasePart },
	center: Vector3,
	start: number,
	duration: number,
	busy: boolean,
}

local SwitchRing = {}

local rings: { Ring } = {}
local folder: Instance? = nil
local stopLoop: (() -> ())? = nil

local function ensureFolder(): Instance
	if folder == nil then
		folder = Engine.folder(workspace, "FxSwitchRings")
	end
	return folder :: Instance
end

local function newRing(): Ring
	local config = Fx.switchRing
	local color = Palette.color3(config.token :: any)
	local segments: { BasePart } = {}
	for _ = 1, config.segments do
		local part = Instance.new("Part")
		part.Name = "RingSegment"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = 1
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = ensureFolder()
		table.insert(segments, part)
	end
	return { segments = segments, center = Vector3.zero, start = 0, duration = 1, busy = false }
end

local function acquire(): Ring
	for _, ring in rings do
		if not ring.busy then
			return ring
		end
	end
	local ring = newRing()
	table.insert(rings, ring)
	return ring
end

local function layRing(ring: Ring, radius: number, transparency: number)
	local config = Fx.switchRing
	local count = #ring.segments
	local arcLength = 2 * math.pi * radius / count * config.segmentOverlap
	for index, part in ring.segments do
		local angle = 2 * math.pi * (index - 1) / count
		local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local center = ring.center + offset
		part.Size = Vector3.new(config.thickness, config.height, arcLength)
		part.CFrame = CFrame.lookAt(center, center + tangent)
		part.Transparency = transparency
	end
end

local function step()
	local now = Engine.now()
	local config = Fx.switchRing
	local anyBusy = false
	for _, ring in rings do
		if not ring.busy then
			continue
		end
		local t = (now - ring.start) / ring.duration
		if t >= 1 then
			ring.busy = false
			for _, part in ring.segments do
				part.Transparency = 1
			end
			continue
		end
		anyBusy = true
		local eased = Easing.evaluate(config.easing, t)
		local radius = config.radiusStart + (config.radiusEnd - config.radiusStart) * eased
		local transparency = 0
		if t > config.fadeStartFraction then
			transparency = (t - config.fadeStartFraction) / math.max(1e-6, 1 - config.fadeStartFraction)
		end
		layRing(ring, radius, transparency)
	end
	if not anyBusy and stopLoop ~= nil then
		stopLoop()
		stopLoop = nil
	end
end

--- Expands a ring from `position` over `duration` seconds (combat.switchWindow for a Switch).
function SwitchRing.show(position: Vector3, duration: number)
	local ring = acquire()
	ring.center = position
	ring.start = Engine.now()
	ring.duration = math.max(duration, 1e-6)
	ring.busy = true
	layRing(ring, Fx.switchRing.radiusStart, 0)
	if stopLoop == nil then
		stopLoop = Engine.onHeartbeat(function()
			step()
		end)
	end
end

--- Rings expanding right now.
function SwitchRing.activeCount(): number
	local count = 0
	for _, ring in rings do
		if ring.busy then
			count += 1
		end
	end
	return count
end

--- Advances the rings by hand (tests).
function SwitchRing.step()
	step()
end

--- Pre-builds the pool so the first Switch never allocates.
function SwitchRing.start()
	while #rings < Fx.switchRing.poolSize do
		table.insert(rings, newRing())
	end
end

return SwitchRing
