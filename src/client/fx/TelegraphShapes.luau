--!strict
--[[
	TelegraphShapes: the pure geometry and timing of enemy telegraphs (sections 6 and 11).

	A ground shape (Line, Cone or Circle) becomes a list of flat pieces, each a center, a yaw and
	a size in plain numbers, so Telegraphs.luau only has to turn them into CFrames on pooled parts.
	A cone is a fan of flat triangles (each slice from the apex to its chord, cut in two along its
	axis into right triangles a WedgePart laid on its side draws): they share their edges and
	never overlap, so the translucent fan shows no seams where the old overlapping blocks doubled
	their alpha (issue 15). The alpha curves say how the decal and the weapon Highlight fill ramp
	in over the wind-up and vanish at the strike; a blow's tell holds through its strike until its
	snap and glints over the parry window before it (`timing`, F7). No Roblox datatypes, so every
	function runs in Lune.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local AI = require(Shared.data.ai)
local Combat = require(Shared.data.combat)

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
	-- A flat right triangle (a WedgePart laid on its side) instead of a block: 1 when its leg across
	-- runs to the right of its yaw's facing, -1 to the left. Its right angle is at the far end of its
	-- leg along the facing, on the yaw's axis (TelegraphShapes.triangle).
	wedge: number?,
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
		-- Cone: a fan of slices across the arc, each the triangle from the apex to its chord, drawn
		-- as two right triangles meeting on its axis (where the chord's midpoint is).
		local slices = math.max(1, decal.coneSlices)
		local arc = math.rad(math.clamp(resolved.width, 1, 360))
		local sliceArc = arc / slices
		local along = resolved.length * math.cos(sliceArc * 0.5)
		local across = resolved.length * math.sin(sliceArc * 0.5)
		for index = 1, slices do
			local sliceYaw = yaw - arc * 0.5 + sliceArc * (index - 0.5)
			local forward = forwardFromYaw(sliceYaw)
			local right = { math.cos(sliceYaw), 0, -math.sin(sliceYaw) }
			for _, side in { -1, 1 } do
				table.insert(pieces, {
					center = {
						origin[1] + forward[1] * along * 0.5 + right[1] * side * across * 0.5,
						y,
						origin[3] + forward[3] * along * 0.5 + right[3] * side * across * 0.5,
					},
					yaw = sliceYaw,
					size = { across, thickness, along },
					circle = false,
					wedge = side,
				})
			end
		end
	end
	return pieces
end

--- The three corners of a wedge piece's triangle on the ground (its height the piece's centre's):
--- the right angle on its axis at the far end, the apex end of that leg, and the end of its leg
--- across. Nil for a block or a cylinder.
function TelegraphShapes.triangle(piece: Piece): { Vec3 }?
	local side = piece.wedge
	if side == nil then
		return nil
	end
	local forward = forwardFromYaw(piece.yaw)
	local right = { math.cos(piece.yaw), 0, -math.sin(piece.yaw) }
	local across, along = piece.size[1], piece.size[3]
	local c = piece.center
	local corner = {
		c[1] + forward[1] * along * 0.5 - right[1] * side * across * 0.5,
		c[2],
		c[3] + forward[3] * along * 0.5 - right[3] * side * across * 0.5,
	}
	return {
		corner,
		{ corner[1] - forward[1] * along, c[2], corner[3] - forward[3] * along },
		{ corner[1] + right[1] * side * across, c[2], corner[3] + right[3] * side * across },
	}
end

--- When a tell ends and its glint begins, in seconds into the wind-up (F7). A blow's (`strike`, the
--- seconds from the wind-up's end to where it lands) stays lit through the strike until its snap
--- begins, ai.luau telegraph.snapLeadSeconds before it lands, and glints over the parry window
--- before the landing (combat.luau parryWindow). Without a strike (a rush's line: the run is the
--- strike) it ends with the wind-up and never glints.
--- `lead` (D-289): seconds the glint opens and closes early, this client's one-way latency (a
--- press reaches the server that late); capped by fx.luau telegraph.glintLeadMax, none when nil or
--- negative. The third result is when the glint closes (`ends` with no lead); the tell itself still
--- holds to `ends`.
function TelegraphShapes.timing(windUp: number, strike: number?, lead: number?): (number, number, number)
	local base = math.max(0, windUp)
	if strike == nil or not (strike > 0) then
		return base, base, base
	end
	local lands = base + strike
	local ends = math.max(base, lands - AI.telegraph.snapLeadSeconds)
	local shift = math.clamp(lead or 0, 0, Fx.telegraph.glintLeadMax)
	local glintUntil = math.clamp(ends - shift, 0, ends)
	local glintFrom = math.clamp(lands - Combat.parryWindow - shift, 0, glintUntil)
	return ends, glintFrom, glintUntil
end

--- Opacity of the ground decal `elapsed` seconds into a wind-up of `windUp` seconds at a given
--- accessibility intensity: ramps in over the fade-in fraction, holds, and is gone at the strike
--- (`ends`, TelegraphShapes.timing; the wind-up's end without it).
function TelegraphShapes.decalAlpha(elapsed: number, windUp: number, intensity: number, ends: number?): number
	local over = math.max(windUp, ends or windUp)
	if elapsed < 0 or elapsed >= over or windUp <= 0 then
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
--- and after (`ends`, the wind-up's end without it), ramping to the fill transparency, with a soft
--- pulse near the strike, and from `glintFrom` to `glintUntil` (the end without it) the glint:
--- steady at ai.luau telegraph.glintFillTransparency (F7, D-289).
function TelegraphShapes.fillTransparency(
	elapsed: number,
	windUp: number,
	intensity: number,
	ends: number?,
	glintFrom: number?,
	glintUntil: number?
): number
	local over = math.max(windUp, ends or windUp)
	if elapsed < 0 or elapsed >= over or windUp <= 0 then
		return 1
	end
	local config = Fx.telegraph
	local clampedIntensity = math.clamp(intensity, config.intensityMin, 1)
	local closes = math.min(over, glintUntil or over)
	if glintFrom ~= nil and glintFrom < closes and elapsed >= glintFrom and elapsed < closes then
		return math.clamp(1 - (1 - AI.telegraph.glintFillTransparency) * clampedIntensity, 0, 1)
	end
	local fadeIn = math.max(1e-6, windUp * config.fadeInFraction)
	local ramp = math.clamp(elapsed / fadeIn, 0, 1)
	local eased = 1 - (1 - ramp) * (1 - ramp)
	local opacity = (1 - config.fillTransparency) * eased * clampedIntensity
	local pulseFrom = windUp * config.pulseFromFraction
	if elapsed >= pulseFrom then
		local pulse = 0.5 - 0.5 * math.cos((elapsed - pulseFrom) * config.pulseHz * 2 * math.pi)
		opacity *= 1 - config.pulseDepth * pulse
	end
	return math.clamp(1 - opacity, 0, 1)
end

--- True when `point` stands inside a blow's strike shape by at least `marginStuds` (and, in a cone,
--- `marginDegrees` off its edges), on the ground plane: the shape the server resolves the blow on
--- (CombatService.enemyStrike), laid at `origin` facing `facing`. `arc` > 0 is a cone of `reach`
--- and `arc` degrees (360 or more: a circle); `arc` <= 0 is a line of `reach` and `lineWidth`. A
--- body this deep in cannot be judged out by the server's own copy of it (F16, D-258).
function TelegraphShapes.deepInside(
	reach: number,
	arc: number,
	lineWidth: number,
	origin: Vec3,
	facing: Vec3,
	point: Vec3,
	marginStuds: number,
	marginDegrees: number
): boolean
	local dx, dz = point[1] - origin[1], point[3] - origin[3]
	local fx, fz = facing[1], facing[3]
	local length = math.sqrt(fx * fx + fz * fz)
	if length < AI.flatEpsilon then
		return false
	end
	fx, fz = fx / length, fz / length
	local along = dx * fx + dz * fz
	if arc <= 0 then
		local across = math.abs(dx * fz - dz * fx)
		return along >= marginStuds and along <= reach - marginStuds and across <= lineWidth / 2 - marginStuds
	end
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance > reach - marginStuds then
		return false
	end
	if arc >= 360 then
		return true
	end
	if distance < AI.flatEpsilon then
		return true
	end
	local angle = math.deg(math.acos(math.clamp(along / distance, -1, 1)))
	return angle <= arc / 2 - marginDegrees
end

--- True once the tell is over (`ends`: the wind-up's end, or TelegraphShapes.timing's for a blow).
function TelegraphShapes.isOver(elapsed: number, ends: number): boolean
	return elapsed >= ends
end

--- The palette token for a telegraph kind's fill and decal.
function TelegraphShapes.token(kind: string): string
	return Fx.telegraph.fillToken[kind] or Fx.telegraph.fillToken.Normal
end

return TelegraphShapes
