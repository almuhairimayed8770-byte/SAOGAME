--!strict
--[[
	DevStageLogic: the pure rules under the capture's staging (F12, DevStage.server.luau): where
	the player should stand (the stand spot and its ring) and whether it does, the route a walk into
	the ring takes round the ledge and up its ramp, where the ramp goes, the boxes the ledge and its
	ramp fill and whether a body reaches into one (they are never built around it, and no shot
	stages around a body inside one), where each staged enemy stands and which way it faces, where
	a field enemy that stands too near is moved to, when an enemy may be held, and the request
	rate. Plain numbers in and out, so it runs in Lune.

	Facings are degrees, 0 looking along -Z and + turning left: the look of CFrame.Angles(0,
	rad(f), 0), the playground's convention (playground.luau spawns, DevCombat "place").
]]

local DevStageLogic = {}

-- The stand ring (D-244): the spot's floor point and facing, the flat radius, how far the feet may
-- be off the spot's floor, and for the open shot the box the feet must stand over (the ledge's top:
-- { minX, maxX, minZ, maxZ }). The walk reply hands the same table to the client.
export type Ring = {
	x: number,
	y: number,
	z: number,
	facing: number,
	radius: number,
	tolerance: number,
	over: { number }?,
}

-- A flat box { minX, maxX, minZ, maxZ }.
type Box = { minX: number, maxX: number, minZ: number, maxZ: number }

-- The box a staged part fills: its instance name and its corners { x, y, z }.
export type PartBox = { name: string, min: { number }, max: { number } }

-- The phases an enemy is never held in: inside a wind-up the client already draws the telegraph
-- (a Charger's crouch and red line) and Brain.sleep cancels the attack, so the rush the player saw
-- coming never comes; inside a strike the hit is on its way.
local MID_ATTACK: { [string]: boolean } = { WindUp = true, Strike = true }

--- The flat look (x, z) of a facing.
function DevStageLogic.look(facing: number): (number, number)
	local radians = math.rad(facing)
	return -math.sin(radians), -math.cos(radians)
end

--- The point `distance` studs (flat) from (x, z) at `side` degrees off `facing` (+ = left).
function DevStageLogic.around(x: number, z: number, facing: number, side: number, distance: number): (number, number)
	local lx, lz = DevStageLogic.look(facing + side)
	return x + lx * distance, z + lz * distance
end

--- The facing that looks from (fromX, fromZ) to (toX, toZ); nil when they are the same point.
function DevStageLogic.facingFrom(fromX: number, fromZ: number, toX: number, toZ: number): number?
	local dx, dz = toX - fromX, toZ - fromZ
	if dx == 0 and dz == 0 then
		return nil
	end
	return math.deg(math.atan2(-dx, -dz))
end

-- The flat footprint of the ledge and its ramp together (their bounding box), grown by `grow`.
local function footprint(ledge: any, grow: number): Box
	local position, size, ramp = ledge.position, ledge.size, ledge.ramp.size
	local half = math.max(size[1], ramp[1]) / 2 + grow
	local front = position[3] - size[3] / 2
	local back = position[3] + size[3] / 2 + ramp[3]
	return { minX = position[1] - half, maxX = position[1] + half, minZ = front - grow, maxZ = back + grow }
end

--- Where a field enemy at (x, z) goes so it stands `away` studs (flat) from the spot (spotX,
--- spotZ), straight out along the line from the spot (along +X when it stands on it); nil when it
--- already stands that far or further. With `stage` (capture.stage), a spot that lands within
--- stage.routeMarginStuds of the ledge's and its ramp's footprint goes on out along the same line
--- until it clears that grown footprint by routeMarginStuds again, so a moved enemy is never put
--- on or into the ledge or its ramp (round E: the ramp stands along +Z from the stage area's spot).
function DevStageLogic.awaySpot(
	spotX: number,
	spotZ: number,
	x: number,
	z: number,
	away: number,
	stage: any?
): (number?, number?)
	local dx, dz = x - spotX, z - spotZ
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance >= away then
		return nil, nil
	end
	local ux, uz = 1, 0
	if distance > 0 then
		ux, uz = dx / distance, dz / distance
	end
	local out = away
	if stage ~= nil then
		local margin = stage.routeMarginStuds
		local keep = footprint(stage.ledge, margin)
		local px, pz = spotX + ux * out, spotZ + uz * out
		if px >= keep.minX and px <= keep.maxX and pz >= keep.minZ and pz <= keep.maxZ then
			-- Where the line leaves the grown footprint (the spot's ray through the box).
			local exit = math.huge
			if ux ~= 0 then
				exit = math.min(exit, math.max((keep.minX - spotX) / ux, (keep.maxX - spotX) / ux))
			end
			if uz ~= 0 then
				exit = math.min(exit, math.max((keep.minZ - spotZ) / uz, (keep.maxZ - spotZ) / uz))
			end
			out = math.max(out, exit + margin)
		end
	end
	return spotX + ux * out, spotZ + uz * out
end

--- The floor height under the flat point (x, z): the ledge's top or its ramp's slope once they are
--- built (`built`), else the stage area's floor.
function DevStageLogic.floorAt(stage: any, built: boolean, x: number, z: number): number
	local ledge = stage.ledge
	local field = stage.area.position[2]
	if not built then
		return field
	end
	local position, size, ramp = ledge.position, ledge.size, ledge.ramp.size
	local floor = position[2] - size[2] / 2
	if DevStageLogic.onLedge(ledge, x, z) then
		return floor + size[2]
	end
	if DevStageLogic.onRamp(ledge, x, z) then
		local back = position[3] + size[3] / 2
		return floor + ramp[2] * (1 - (z - back) / ramp[3])
	end
	return field
end

--- Where the player stands for a shot: the floor point (x, floor y, z) and the facing. The open
--- shot stands on the ledge's top, `standInset` studs in from its +Z edge, facing ledge.facing;
--- every other shot at the stage area.
function DevStageLogic.standSpot(open: boolean, area: any, ledge: any): (number, number, number, number)
	if open then
		local position, size = ledge.position, ledge.size
		return position[1], position[2] + size[2] / 2, position[3] + size[3] / 2 - ledge.standInset, ledge.facing
	end
	local position = area.position
	return position[1], position[2], position[3], area.facing
end

--- Whether the flat point (x, z) stands over the ledge's top.
function DevStageLogic.onLedge(ledge: any, x: number, z: number): boolean
	local position, size = ledge.position, ledge.size
	return math.abs(x - position[1]) <= size[1] / 2 and math.abs(z - position[3]) <= size[3] / 2
end

--- Where the ledge's ramp goes: its centre (x, y, z) and its yaw in degrees. A WedgePart's tall
--- face is its back (+Z), so a half turn puts that face against the ledge's +Z face, the slope
--- running down along +Z to the field; centred on the ledge across X, standing on the ledge's floor.
function DevStageLogic.rampFrame(ledge: any): (number, number, number, number)
	local position, size, ramp = ledge.position, ledge.size, ledge.ramp.size
	local floor = position[2] - size[2] / 2
	return position[1], floor + ramp[2] / 2, position[3] + size[3] / 2 + ramp[3] / 2, 180
end

--- Whether the flat point (x, z) stands over the ledge's ramp.
function DevStageLogic.onRamp(ledge: any, x: number, z: number): boolean
	local position, size, ramp = ledge.position, ledge.size, ledge.ramp.size
	local back = position[3] + size[3] / 2
	return math.abs(x - position[1]) <= ramp[1] / 2 and z >= back and z <= back + ramp[3]
end

--- The boxes the staging's parts fill, in build order: the ledge's, then its ramp's (the wedge's
--- bounding box: from the ledge's floor up its height, from the ledge's +Z face back its length).
function DevStageLogic.partBoxes(ledge: any): { PartBox }
	local position, size, ramp = ledge.position, ledge.size, ledge.ramp.size
	local floor = position[2] - size[2] / 2
	local back = position[3] + size[3] / 2
	return {
		{
			name = ledge.name,
			min = { position[1] - size[1] / 2, floor, position[3] - size[3] / 2 },
			max = { position[1] + size[1] / 2, floor + size[2], back },
		},
		{
			name = ledge.ramp.name,
			min = { position[1] - ramp[1] / 2, floor, back },
			max = { position[1] + ramp[1] / 2, floor + ramp[2], back + ramp[3] },
		},
	}
end

--- The name of the staged part (the ledge or its ramp, by partBoxes) a body reaches into, or nil.
--- The body is a box `reach` studs out from its root's flat point (x, z) each way along X and Z
--- (half its flat diagonal, so any yaw fits) and `height` tall from the floor its Humanoid holds it
--- over (floorY). It is inside a part when it overlaps the part's box by more than `touch` studs on
--- every axis: feet on the top, or a side against a face, only touch. `names`: only those parts
--- (nil: both).
function DevStageLogic.bodyInside(
	ledge: any,
	x: number,
	floorY: number,
	z: number,
	reach: number,
	height: number,
	touch: number,
	names: { string }?
): string?
	local low = { x - reach, floorY, z - reach }
	local high = { x + reach, floorY + height, z + reach }
	for _, box in DevStageLogic.partBoxes(ledge) do
		if names ~= nil and table.find(names, box.name) == nil then
			continue
		end
		local inside = true
		for axis = 1, 3 do
			if math.min(high[axis], box.max[axis]) - math.max(low[axis], box.min[axis]) <= touch then
				inside = false
				break
			end
		end
		if inside then
			return box.name
		end
	end
	return nil
end

--- The stand ring of a shot (open: on the ledge's top) from capture.stage.
function DevStageLogic.ring(open: boolean, stage: any): Ring
	local x, y, z, facing = DevStageLogic.standSpot(open, stage.area, stage.ledge)
	local over: { number }? = nil
	if open then
		local position, size = stage.ledge.position, stage.ledge.size
		over = {
			position[1] - size[1] / 2,
			position[1] + size[1] / 2,
			position[3] - size[3] / 2,
			position[3] + size[3] / 2,
		}
	end
	return {
		x = x,
		y = y,
		z = z,
		facing = facing,
		radius = stage.standRadius,
		tolerance = stage.standHeightTolerance,
		over = over,
	}
end

--- Whether feet at (x, floorY, z) stand in the ring: within its radius (flat) of the spot, within
--- its tolerance of the spot's floor, and over its box when it has one.
function DevStageLogic.inRing(ring: Ring, x: number, floorY: number, z: number): boolean
	local dx, dz = x - ring.x, z - ring.z
	if dx * dx + dz * dz > ring.radius * ring.radius or math.abs(floorY - ring.y) > ring.tolerance then
		return false
	end
	local over = ring.over
	return over == nil or (x >= over[1] and x <= over[2] and z >= over[3] and z <= over[4])
end

--- Whether the flat segment from (ax, az) to (bx, bz) runs through the inside of the box
--- { minX, maxX, minZ, maxZ } (touching its edge or running along it does not count).
function DevStageLogic.crosses(box: { number }, ax: number, az: number, bx: number, bz: number): boolean
	local t0, t1 = 0, 1
	local dx, dz = bx - ax, bz - az
	for _, edge in { { -dx, ax - box[1] }, { dx, box[2] - ax }, { -dz, az - box[3] }, { dz, box[4] - az } } do
		local p, q = edge[1], edge[2]
		if p == 0 then
			if q <= 0 then
				return false
			end
		elseif p < 0 then
			t0 = math.max(t0, q / p)
		else
			t1 = math.min(t1, q / p)
		end
	end
	return t0 < t1
end

-- Appends the corners that take a walk from (fx, fz) to (tx, tz) round the outside of `keep` (the
-- footprint grown by the route's margin) when the straight line runs through `solid` (the
-- footprint): out to the side nearer the start (sideways first from in front of, behind or beside
-- it), along that side to the end nearer the goal.
local function detour(path: { { number } }, solid: Box, keep: Box, fx: number, fz: number, tx: number, tz: number)
	if not DevStageLogic.crosses({ solid.minX, solid.maxX, solid.minZ, solid.maxZ }, fx, fz, tx, tz) then
		return
	end
	local centre = (keep.minX + keep.maxX) / 2
	local right = if fx ~= centre then fx > centre else tx >= centre
	local sideX = if right then keep.maxX else keep.minX
	local exitZ = math.clamp(tz, keep.minZ, keep.maxZ)
	if math.abs(fx - centre) < (keep.maxX - keep.minX) / 2 then
		local entryZ = math.clamp(fz, keep.minZ, keep.maxZ)
		table.insert(path, { sideX, entryZ })
		if entryZ == exitZ then
			return
		end
	end
	table.insert(path, { sideX, exitZ })
end

--- The route a walk into a shot's ring takes from (fromX, fromZ), as flat points { x, z }: it ends
--- with the approach (approachStuds behind the spot along its facing) and the spot, so the last leg
--- runs along the facing. The open shot climbs the ramp: from the ledge or the ramp across to their
--- centre line, from the field round them (routeMarginStuds out) to the ramp's foot. Any other shot
--- goes round them once they are built (`built`) when the straight line runs through them.
function DevStageLogic.route(open: boolean, stage: any, built: boolean, fromX: number, fromZ: number): { { number } }
	local ledge = stage.ledge
	local x, _, z, facing = DevStageLogic.standSpot(open, stage.area, ledge)
	local lx, lz = DevStageLogic.look(facing)
	local approachX, approachZ = x - lx * stage.approachStuds, z - lz * stage.approachStuds
	local path: { { number } } = {}
	if open or built then
		local solid = footprint(ledge, 0)
		local keep = footprint(ledge, stage.routeMarginStuds)
		local onTop = DevStageLogic.onLedge(ledge, fromX, fromZ) or DevStageLogic.onRamp(ledge, fromX, fromZ)
		if open and onTop then
			table.insert(path, { ledge.position[1], fromZ })
		elseif open then
			local footX, footZ = ledge.position[1], keep.maxZ
			detour(path, solid, keep, fromX, fromZ, footX, footZ)
			table.insert(path, { footX, footZ })
		elseif not onTop then
			detour(path, solid, keep, fromX, fromZ, approachX, approachZ)
		end
	end
	table.insert(path, { approachX, approachZ })
	table.insert(path, { x, z })
	return path
end

--- Whether an enemy in brain phase `phase` may be held now: never inside its wind-up or strike.
function DevStageLogic.canHold(phase: string?): boolean
	return phase == nil or not MID_ATTACK[phase]
end

--- Whether a request at `now` may run, one player's last having run at `last` (nil: never).
function DevStageLogic.allowed(last: number?, now: number, perSecond: number): boolean
	return last == nil or now - last >= 1 / perSecond
end

--- The index of the shot with id `id` in `shots`, or nil.
function DevStageLogic.shotIndex(shots: { any }, id: unknown): number?
	if typeof(id) ~= "string" then
		return nil
	end
	for index, shot in shots do
		if shot.id == id then
			return index
		end
	end
	return nil
end

return DevStageLogic
