--!strict
--[[
	TelegraphShapes: the pure geometry and timing of enemy telegraphs (sections 6 and 11).

	A ground shape (Line, Cone or Circle) becomes a list of flat pieces, each a center, a yaw and
	a size in plain numbers, so Telegraphs.luau only has to turn them into CFrames on pooled parts.
	The alpha curves say how the decal and the weapon Highlight fill ramp in over the wind-up and
	vanish at the strike. No Roblox datatypes, so every function runs in Lune.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)

export type Vec3 = { number }

export type Shape = {
	kind: "Line" | "Cone" | "Circle",
	length: number,
	width: number, -- line width, cone angle in degrees, or circle radius
}

export type Piece = {
	center: Vec3, -- world position of the piece's center
	yaw: number, -- radians; 0 faces -Z, positive turns left (Roblox convention)
	size: Vec3, -- x = width, y = thickness, z = length
	circle: boolean, -- true for a cylinder piece (a circle), false for a block
}

local TelegraphShapes = {}

local function yawOf(facing: Vec3): number
	-- Roblox forward is -Z; a facing of (0, 0, -1) is yaw 0; (-1, 0, 0) is a quarter turn left.
	return math.atan2(-facing[1], -facing[3])
end

local function forwardFromYaw(yaw: number): Vec3
	return { -math.sin(yaw), 0, -math.cos(yaw) }
end

--- The shape to draw when the broadcast carries none (a short cone in front of the enemy).
function TelegraphShapes.defaultShape(): Shape
	local default = Fx.telegraph.decal.defaultShape
	return { kind = default.kind, length = default.length, width = default.width }
end

--- Lays a shape out on the ground at `origin` facing `facing` as flat pieces.
function TelegraphShapes.pieces(shape: Shape?, origin: Vec3, facing: Vec3): { Piece }
	local decal = Fx.telegraph.decal
	local resolved = shape or TelegraphShapes.defaultShape()
	local thickness = decal.thickness
	local y = origin[2] + decal.groundOffset
	local yaw = yawOf(facing)
	local pieces: { Piece } = {}

	if resolved.kind == "Line" then
		local width = math.max(decal.lineMinWidth, resolved.width)
		local forward = forwardFromYaw(yaw)
		local half = resolved.length * 0.5
		table.insert(pieces, {
			center = { origin[1] + forward[1] * half, y, origin[3] + forward[3] * half },
			yaw = yaw,
			size = { width, thickness, resolved.length },
			circle = false,
		})
	elseif resolved.kind == "Circle" then
		local radius = math.max(decal.lineMinWidth * 0.5, resolved.width)
		table.insert(pieces, {
			center = { origin[1], y, origin[3] },
			yaw = yaw,
			size = { radius * 2, thickness, radius * 2 },
			circle = true,
		})
	else
		-- Cone: a fan of slices across the arc, each a block of the cone's length whose width
		-- covers its share of the arc at the far end (with overlap so the fan has no gaps).
		local slices = math.max(1, decal.coneSlices)
		local arc = math.rad(math.clamp(resolved.width, 1, 360))
		local sliceArc = arc / slices
		local sliceWidth =
			math.max(decal.lineMinWidth, 2 * resolved.length * math.sin(sliceArc * 0.5) * decal.coneOverlap)
		local half = resolved.length * 0.5
		for index = 1, slices do
			local sliceYaw = yaw - arc * 0.5 + sliceArc * (index - 0.5)
			local forward = forwardFromYaw(sliceYaw)
			table.insert(pieces, {
				center = { origin[1] + forward[1] * half, y, origin[3] + forward[3] * half },
				yaw = sliceYaw,
				size = { sliceWidth, thickness, resolved.length },
				circle = false,
			})
		end
	end
	return pieces
end

--- Opacity of the ground decal `elapsed` seconds into a wind-up of `windUp` seconds at a given
--- accessibility intensity: ramps in over the fade-in fraction, holds, and is gone at the strike.
function TelegraphShapes.decalAlpha(elapsed: number, windUp: number, intensity: number): number
	if elapsed < 0 or elapsed >= windUp or windUp <= 0 then
		return 0
	end
	local config = Fx.telegraph
	local fadeIn = math.max(1e-6, windUp * config.fadeInFraction)
	local ramp = math.clamp(elapsed / fadeIn, 0, 1)
	local eased = 1 - (1 - ramp) * (1 - ramp)
	local clampedIntensity = math.clamp(intensity, config.intensityMin, 1)
	return config.decal.alpha * eased * clampedIntensity
end

--- Transparency of the weapon Highlight fill at `elapsed` into the wind-up: 1 (invisible) before
--- and after, ramping to the fill transparency, with a soft pulse near the strike.
function TelegraphShapes.fillTransparency(elapsed: number, windUp: number, intensity: number): number
	if elapsed < 0 or elapsed >= windUp or windUp <= 0 then
		return 1
	end
	local config = Fx.telegraph
	local fadeIn = math.max(1e-6, windUp * config.fadeInFraction)
	local ramp = math.clamp(elapsed / fadeIn, 0, 1)
	local eased = 1 - (1 - ramp) * (1 - ramp)
	local clampedIntensity = math.clamp(intensity, config.intensityMin, 1)
	local opacity = (1 - config.fillTransparency) * eased * clampedIntensity
	local pulseFrom = windUp * config.pulseFromFraction
	if elapsed >= pulseFrom then
		local pulse = 0.5 - 0.5 * math.cos((elapsed - pulseFrom) * config.pulseHz * 2 * math.pi)
		opacity *= 1 - config.pulseDepth * pulse
	end
	return math.clamp(1 - opacity, 0, 1)
end

--- True once the wind-up is over (the strike has landed; the telegraph must be gone).
function TelegraphShapes.isOver(elapsed: number, windUp: number): boolean
	return elapsed >= windUp
end

--- The palette token for a telegraph kind's fill and decal.
function TelegraphShapes.token(kind: string): string
	return Fx.telegraph.fillToken[kind] or Fx.telegraph.fillToken.Normal
end

return TelegraphShapes
