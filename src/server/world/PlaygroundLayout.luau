--!strict
--[[
	PlaygroundLayout: the pure layout math behind PlaygroundBuilder and PlaygroundService (sections
	5, 11, 20; D-013). Where every rim post, rail, pillar and cloud goes, how big the kill volume is,
	how many parts the rim costs, and where a pack member stands around its spawn point, clear of
	every living fighter (spacedScatter, D-170). Plain numbers in and out so every rule runs under
	Lune; the builder turns them into CFrames.

	Angles are degrees around the field center, 0 along +X and increasing toward +Z (the direction
	`ring` walks), so a tangent at angle a is (-sin a, cos a). Distances are studs; y is up.
]]

export type Point = { x: number, y: number, z: number, angle: number }
export type Rail = { x: number, y: number, z: number, length: number, dirX: number, dirZ: number }
export type Cloud = Point & { dirX: number, dirZ: number } -- the tangent the cloud drifts along
export type Box = { x: number, y: number, z: number, size: { number } }

local PlaygroundLayout = {}

local FULL_TURN = 2 * math.pi -- unit: radians in a circle

--- How many posts (or anything) fit around a circle of `radius` at `spacing` studs apart; never fewer than one.
function PlaygroundLayout.ringCount(radius: number, spacing: number): number
	if spacing <= 0 then
		error("PlaygroundLayout.ringCount: spacing must be positive")
	end
	return math.max(1, math.floor(FULL_TURN * radius / spacing))
end

--- `count` points evenly spaced on a circle of `radius` at height `y`, starting at `startDegrees` (0 = +X).
function PlaygroundLayout.ring(count: number, radius: number, y: number, startDegrees: number?): { Point }
	local points: { Point } = {}
	if count <= 0 then
		return points
	end
	local step = 360 / count -- unit: degrees per slot
	local start = startDegrees or 0
	for index = 0, count - 1 do
		local angle = start + index * step
		local radians = math.rad(angle)
		table.insert(points, {
			x = radius * math.cos(radians),
			y = y,
			z = radius * math.sin(radians),
			angle = angle,
		})
	end
	return points
end

--- Rim posts: their centers sit half a post inside the field edge, spaced `spacing` apart along the rim.
function PlaygroundLayout.posts(fieldRadius: number, spacing: number, postSize: { number }): { Point }
	local count = PlaygroundLayout.ringCount(fieldRadius, spacing)
	local radius = fieldRadius - postSize[1] / 2
	return PlaygroundLayout.ring(count, radius, postSize[2] / 2)
end

--- Rail heights for `railCount` rails: the top rail sits flush with the post top, the rest divide the height evenly.
function PlaygroundLayout.railHeights(railingHeight: number, railThickness: number, railCount: number): { number }
	local heights = {}
	local top = railingHeight - railThickness / 2
	for index = 1, railCount do
		table.insert(heights, top * (railCount - index + 1) / railCount)
	end
	return heights
end

--- One rail per height between each pair of neighbouring posts (the ring closes), running `overlap`
--- studs past the chord so rails meet inside their posts.
function PlaygroundLayout.rails(posts: { Point }, heights: { number }, overlap: number): { Rail }
	local rails: { Rail } = {}
	local count = #posts
	if count < 2 then
		return rails
	end
	for index, from in posts do
		local to = posts[index % count + 1]
		local dx = to.x - from.x
		local dz = to.z - from.z
		local chord = math.sqrt(dx * dx + dz * dz)
		if chord <= 0 then
			continue
		end
		for _, height in heights do
			table.insert(rails, {
				x = (from.x + to.x) / 2,
				y = height,
				z = (from.z + to.z) / 2,
				length = chord + overlap,
				dirX = dx / chord,
				dirZ = dz / chord,
			})
		end
	end
	return rails
end

--- The outer pillars: `count` points at `distance`, centered vertically on `centerY`.
function PlaygroundLayout.pillars(count: number, distance: number, centerY: number): { Point }
	return PlaygroundLayout.ring(count, distance, centerY)
end

--- Vertical center of a pillar whose top sits `gap` studs under the ceiling underside.
function PlaygroundLayout.pillarCenterY(ceilingUnderside: number, gap: number, pillarHeight: number): number
	return ceilingUnderside - gap - pillarHeight / 2
end

--- Cloud billboard hosts on a ring `dropBelow` studs under the field, each with the tangent it drifts
--- along; `jitter` scatters them radially and vertically through `random` (none when nil).
function PlaygroundLayout.clouds(
	count: number,
	radius: number,
	dropBelow: number,
	jitter: { radial: number, height: number }?,
	random: Random?
): { Cloud }
	local clouds: { Cloud } = {}
	for _, point in PlaygroundLayout.ring(count, radius, -dropBelow) do
		local radians = math.rad(point.angle)
		local cloud: Cloud = {
			x = point.x,
			y = point.y,
			z = point.z,
			angle = point.angle,
			dirX = -math.sin(radians),
			dirZ = math.cos(radians),
		}
		if jitter ~= nil and random ~= nil then
			local radial = random:NextNumber(-jitter.radial, jitter.radial)
			cloud.x += math.cos(radians) * radial
			cloud.z += math.sin(radians) * radial
			cloud.y += random:NextNumber(-jitter.height, jitter.height)
		end
		table.insert(clouds, cloud)
	end
	return clouds
end

--- The kill volume's center and size: a slab whose top face is the kill plane.
function PlaygroundLayout.killVolume(volume: { y: number, halfExtent: number, thickness: number }): Box
	return {
		x = 0,
		y = volume.y - volume.thickness / 2,
		z = 0,
		size = { volume.halfExtent * 2, volume.thickness, volume.halfExtent * 2 },
	}
end

--- Parts the builder adds to the Playground: posts, rails, pillars, clouds and the kill volume.
function PlaygroundLayout.partEstimate(
	fieldRadius: number,
	postSpacing: number,
	railCount: number,
	pillarCount: number,
	cloudCount: number
): number
	local posts = PlaygroundLayout.ringCount(fieldRadius, postSpacing)
	return posts + posts * railCount + pillarCount + cloudCount + 1
end

--- A point uniformly scattered inside a disc of `radius` around (centerX, centerZ).
function PlaygroundLayout.scatter(centerX: number, centerZ: number, radius: number, random: Random): (number, number)
	local distance = radius * math.sqrt(random:NextNumber())
	local radians = random:NextNumber() * FULL_TURN
	return centerX + math.cos(radians) * distance, centerZ + math.sin(radians) * distance
end

-- How spacedScatter keeps spawns apart (playground.luau spawnSpacing).
export type Spacing = { minStuds: number, tries: number, widenStuds: number, widenings: number }
export type Spot = { x: number, z: number }

-- Distance from (x, z) to the nearest occupied spot (math.huge with none).
local function clearance(x: number, z: number, occupied: { Spot }): number
	local nearest = math.huge
	for _, spot in occupied do
		nearest = math.min(nearest, PlaygroundLayout.distance(x, z, spot.x, spot.z))
	end
	return nearest
end

--- A scattered spot at least `spacing.minStuds` from every `occupied` spot (D-170). It draws
--- `spacing.tries` spots in the disc of `radius`, then widens the disc by `spacing.widenStuds` and
--- draws again, up to `spacing.widenings` times, so a pack stays as close as the spacing allows.
--- The first clear draw wins: with nobody near, it draws exactly what `scatter` draws. With no clear
--- spot anywhere it returns the roomiest spot it drew, and false.
function PlaygroundLayout.spacedScatter(
	centerX: number,
	centerZ: number,
	radius: number,
	spacing: Spacing,
	occupied: { Spot },
	random: Random
): (number, number, boolean)
	local bestX, bestZ, bestRoom = centerX, centerZ, -math.huge
	for widening = 0, spacing.widenings do
		local discRadius = radius + widening * spacing.widenStuds
		for _ = 1, spacing.tries do
			local x, z = PlaygroundLayout.scatter(centerX, centerZ, discRadius, random)
			local room = clearance(x, z, occupied)
			if room >= spacing.minStuds then
				return x, z, true
			end
			if room > bestRoom then
				bestX, bestZ, bestRoom = x, z, room
			end
		end
	end
	return bestX, bestZ, false
end

--- A facing in degrees jittered by up to `jitterDegrees` either way.
function PlaygroundLayout.jitterFacing(facing: number, jitterDegrees: number, random: Random): number
	return facing + random:NextNumber(-jitterDegrees, jitterDegrees)
end

--- Height of a Humanoid rig's root center above the ground it stands on: the hip height plus half
--- the root part, lifted by `epsilon` so a fresh rig never starts inside the floor.
function PlaygroundLayout.rootHeight(hipHeight: number, rootSizeY: number, epsilon: number): number
	return hipHeight + rootSizeY / 2 + epsilon
end

--- Horizontal distance between two points on the field.
function PlaygroundLayout.distance(ax: number, az: number, bx: number, bz: number): number
	local dx = bx - ax
	local dz = bz - az
	return math.sqrt(dx * dx + dz * dz)
end

return PlaygroundLayout
