--!strict
--[[
	Spacing (D-259): room between enemies, on the ground plane.

	Only the roots of two enemies collide (D-167, D-198), and a root is far smaller than what it
	carries: a kobold's arms and axe and a boar's head and snout reach past it, so two walking
	enemies could stand inside each other with their roots touching, and a stopped rush (its root
	in the rushing group) ended inside whoever it ran through (REVIEW 2026-10-25 issue 22: the
	kobold walked into the boar after the shatter and stayed there).

	Each body is a flat capsule: its spine along the facing, from as far ahead as any part reaches
	at rest to as far behind, less the radius at each end, and its radius the widest part's half
	width (footprintOf, measured on the rig at spawn). `clearance` is the clear ground between two
	of them (negative when they overlap) and which way is out. EnemyService steers each free enemy
	every AI tick with `steer`: a goal inside another body's room moves out to its edge
	(`standOff`), a walk heading into a body within the gap plus the slide band slides along it,
	and a body caught inside another steps out. The rules read ai.luau `spacing`.

	Since D-281 an enemy's blocker faces (RigBuilder.addBlocker: one over the body, one over each
	part it holds, D-315) are solid against every other enemy's faces, and they reach past the
	capsule: a kobold's axe face 1.84 studs past it, 3.85 ahead at its right, the body face's
	corners 1.36. Two kobolds a capsule gap apart could stand with their faces inside each other,
	and the engine shoved them apart. So a footprint also carries the faces (footprintOf, read off
	the model EnemyService spawns), and between two bodies that both have faces the clear ground is
	face to face (D-332): every rule above then keeps every face the gap from every other.

	Pure: plain Vector3 maths, no engine, so every rule runs in Lune.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AI = require(ReplicatedStorage.Shared.data.ai)

-- One blocker face on the ground (D-198, D-315, D-332): a flat box along the root's axes, in the
-- root's space (X to its right, -Z ahead), as RigBuilder.addBlocker welds it.
export type Face = {
	centre: Vector3, -- its middle (only X and Z count)
	half: Vector3, -- half its width across the root (X) and half its depth along it (Z)
}

export type Footprint = {
	front: number, -- studs the body reaches ahead of its root along the facing
	back: number, -- studs it reaches behind
	radius: number, -- half its widest width across the facing
	-- Its blocker faces, when it has them: with faces on both bodies the clear ground between them
	-- is face to face (D-332), else capsule to capsule.
	faces: { Face }?,
}

export type Body = {
	position: Vector3, -- the root's position (only X and Z count)
	facing: Vector3, -- the root's look (flattened here)
	footprint: Footprint,
}

export type Neighbor = {
	body: Body,
	-- How much of a step out this body takes on: 0.5 when the other steps too (both free), 1 when
	-- the other stays where it is (busy, asleep or held).
	share: number,
	-- Which way out when the two spines cross exactly, or two faces' middles line up (no direction
	-- between them): +1 or -1 along world X, opposite for the two of a pair.
	side: number,
}

-- A body within the slide band: how much clear ground there is, which way is out, and its middle.
type Near = { clear: number, out: Vector3, center: Vector3 }

local Spacing = {}

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function unitFlat(vector: Vector3): Vector3?
	local f = flat(vector)
	local length = f.Magnitude
	if length < AI.flatEpsilon then
		return nil
	end
	return f / length
end

--- A body's footprint from its rest corners in the root's space (RushWorld.profileOf: -Z ahead)
--- and its blocker faces (D-332), whose corners the capsule spans too. Without corners or faces it
--- is a point.
function Spacing.footprintOf(profile: { Vector3 }, faces: { Face }?): Footprint
	local front, back, radius = 0, 0, 0
	local function take(x: number, z: number)
		front = math.max(front, -z)
		back = math.max(back, z)
		radius = math.max(radius, math.abs(x))
	end
	for _, corner in profile do
		take(corner.X, corner.Z)
	end
	local kept: { Face }? = nil
	if faces ~= nil and #faces > 0 then
		kept = faces
		for _, face in faces do
			for _, x in { -1, 1 } do
				for _, z in { -1, 1 } do
					take(face.centre.X + x * face.half.X, face.centre.Z + z * face.half.Z)
				end
			end
		end
	end
	return { front = front, back = back, radius = radius, faces = kept }
end

--- The two flat ends of a body's spine: ahead and behind the root along its facing, each a radius
--- short of the body's reach so the capsule ends where the body does. A body no longer than it is
--- wide has a spine of one point, midway between its ends.
function Spacing.spine(body: Body): (Vector3, Vector3)
	local footprint = body.footprint
	local look = unitFlat(body.facing) or -Vector3.zAxis
	local center = flat(body.position)
	local ahead = footprint.front - footprint.radius
	local behind = footprint.back - footprint.radius
	if ahead + behind <= 0 then
		local middle = center + look * ((footprint.front - footprint.back) / 2)
		return middle, middle
	end
	return center + look * ahead, center - look * behind
end

-- The point of segment a0-a1 nearest to `point`.
local function nearestOnSegment(a0: Vector3, a1: Vector3, point: Vector3): Vector3
	local along = a1 - a0
	local lengthSquared = along:Dot(along)
	if lengthSquared < AI.flatEpsilon * AI.flatEpsilon then
		return a0
	end
	local t = math.clamp((point - a0):Dot(along) / lengthSquared, 0, 1)
	return a0 + along * t
end

--- The nearest points of two flat segments (a0-a1 on the first, b0-b1 on the second).
function Spacing.nearestPoints(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3): (Vector3, Vector3)
	local d1, d2, r = a1 - a0, b1 - b0, a0 - b0
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	local tiny = AI.flatEpsilon * AI.flatEpsilon
	local s, t
	if a < tiny and e < tiny then
		return a0, b0
	elseif a < tiny then
		s, t = 0, math.clamp(f / e, 0, 1)
	else
		local c = d1:Dot(r)
		if e < tiny then
			s, t = math.clamp(-c / a, 0, 1), 0
		else
			local b = d1:Dot(d2)
			local denominator = a * e - b * b
			s = if denominator > tiny then math.clamp((b * f - c * e) / denominator, 0, 1) else 0
			t = (b * s + f) / e
			if t < 0 then
				s, t = math.clamp(-c / a, 0, 1), 0
			elseif t > 1 then
				s, t = math.clamp((b - c) / a, 0, 1), 1
			end
		end
	end
	local onA = a0 + d1 * s
	-- Re-project onto b from the clamped point on a so the pair is the true nearest pair.
	return onA, nearestOnSegment(b0, b1, onA)
end

--- A face's four flat corners in world space on a body, counter-clockwise seen from above.
function Spacing.faceCorners(body: Body, face: Face): { Vector3 }
	local look = unitFlat(body.facing) or -Vector3.zAxis
	local right = Vector3.new(-look.Z, 0, look.X)
	-- The root's +Z is behind it: a face centre at (x, z) stands x to the right and -z ahead.
	local centre = flat(body.position) + right * face.centre.X - look * face.centre.Z
	local across, along = right * face.half.X, look * face.half.Z
	return { centre - across - along, centre + across - along, centre + across + along, centre - across + along }
end

-- The projections of a flat polygon's corners on a flat unit axis: least and most.
local function project(polygon: { Vector3 }, axis: Vector3): (number, number)
	local least, most = math.huge, -math.huge
	for _, point in polygon do
		local d = point:Dot(axis)
		least, most = math.min(least, d), math.max(most, d)
	end
	return least, most
end

-- The clear ground between two flat convex polygons that stand apart, and the flat unit direction
-- from `b`'s nearest point to `a`'s; nil when they touch or overlap (no edge normal parts them).
local function polygonsApart(a: { Vector3 }, b: { Vector3 }): (number?, Vector3?)
	local parted = false
	for _, polygon in { a, b } do
		for index = 1, #polygon do
			local edge = polygon[index % #polygon + 1] - polygon[index]
			local length = edge.Magnitude
			if length < AI.flatEpsilon then
				continue
			end
			local axis = Vector3.new(-edge.Z, 0, edge.X) / length
			local aMin, aMax = project(a, axis)
			local bMin, bMax = project(b, axis)
			if aMin - bMax > AI.flatEpsilon or bMin - aMax > AI.flatEpsilon then
				parted = true
				break
			end
		end
		if parted then
			break
		end
	end
	if not parted then
		return nil, nil
	end
	-- Apart: the nearest points are a corner of one on an edge of the other.
	local least, onA, onB = math.huge, a[1], b[1]
	for pass = 1, 2 do
		local fromA = pass == 1
		local points: { Vector3 } = if fromA then a else b
		local edges: { Vector3 } = if fromA then b else a
		for _, point in points do
			for index = 1, #edges do
				local nearest = nearestOnSegment(edges[index], edges[index % #edges + 1], point)
				local distance = (point - nearest).Magnitude
				if distance < least then
					least = distance
					onA, onB = if fromA then point else nearest, if fromA then nearest else point
				end
			end
		end
	end
	return least, (onA - onB) / least
end

-- How far one body's faces stand past another's along a flat unit axis: the least, over every
-- pair of faces, of where this one's begins less where the other's ends (negative: moved that way
-- by its depth, every pair would part along it).
local function setSeparation(mine: { { Vector3 } }, theirs: { { Vector3 } }, axis: Vector3): number
	local least = math.huge
	for _, corners in mine do
		local begins = project(corners, axis)
		for _, otherCorners in theirs do
			local _, ends = project(otherCorners, axis)
			least = math.min(least, begins - ends)
		end
	end
	return least
end

--- The clear ground between two bodies (negative when they overlap) and the flat unit direction
--- from `other` toward `body`, out of it. When both carry their blocker faces (D-332): apart, the
--- least true distance over every pair of faces, out from the nearest point of the other's; in
--- each other, the least push that parts every pair at once, along one of the faces' own axes
--- either way (the same axis and opposite ways for the two of a pair, so the two step apart, and
--- the short way out, never along a boar's length), as a negative clearance. Else it is their
--- capsules' gap. Spines that cross exactly, or two bodies whose pushes tie (one on the other),
--- take `fallback` (a flat unit vector) as the way out.
function Spacing.clearance(body: Body, other: Body, fallback: Vector3): (number, Vector3)
	local mine, theirs = body.footprint.faces, other.footprint.faces
	if mine ~= nil and theirs ~= nil and #mine > 0 and #theirs > 0 then
		local mineCorners: { { Vector3 } } = {}
		local theirCorners: { { Vector3 } } = {}
		for _, face in mine do
			table.insert(mineCorners, Spacing.faceCorners(body, face))
		end
		for _, face in theirs do
			table.insert(theirCorners, Spacing.faceCorners(other, face))
		end
		local best, bestAxis = -math.huge, fallback
		for _, list in { mineCorners, theirCorners } do
			for _, corners in list do
				for index = 1, 2 do
					local edge = corners[index + 1] - corners[index]
					local length = edge.Magnitude
					if length < AI.flatEpsilon then
						continue
					end
					local normal = Vector3.new(-edge.Z, 0, edge.X) / length
					for _, axis in { normal, -normal } do
						local separation = setSeparation(mineCorners, theirCorners, axis)
						local better = separation > best + AI.flatEpsilon
							or (
								separation > best - AI.flatEpsilon
								and axis:Dot(fallback) > bestAxis:Dot(fallback) + AI.flatEpsilon
							)
						if better then
							best, bestAxis = math.max(separation, best), axis
						end
					end
				end
			end
		end
		if best <= 0 then
			return best, bestAxis
		end
		-- Apart along that axis, so every pair is apart: the least true distance between them.
		local least, out = math.huge, bestAxis
		for _, corners in mineCorners do
			for _, otherCorners in theirCorners do
				local apart, direction = polygonsApart(corners, otherCorners)
				if apart ~= nil and direction ~= nil and apart < least then
					least, out = apart, direction
				end
			end
		end
		return if least < math.huge then least else best, out
	end
	local a0, a1 = Spacing.spine(body)
	local b0, b1 = Spacing.spine(other)
	local onBody, onOther = Spacing.nearestPoints(a0, a1, b0, b1)
	local between = onBody - onOther
	local distance = between.Magnitude
	local out = if distance >= AI.flatEpsilon then between / distance else fallback
	return distance - body.footprint.radius - other.footprint.radius, out
end

--- Where a body would stand at `point` (facing as it faces now) with `gap` of clear ground to every
--- one of `others`: the point itself when it already has the room, else pushed out of each body
--- it stands in, over ai.luau spacing.standOffPasses passes (a push out of one can land it in the
--- next). Keeps the point's height.
function Spacing.standOff(body: Body, point: Vector3, others: { Body }, gap: number, fallback: Vector3): Vector3
	local at = point
	for _ = 1, AI.spacing.standOffPasses do
		local moved = false
		for _, other in others do
			local probe: Body = { position = at, facing = body.facing, footprint = body.footprint }
			local clear, out = Spacing.clearance(probe, other, fallback)
			if clear < gap - AI.flatEpsilon then
				at += out * (gap - clear)
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	return at
end

--- The point a free body should walk to this tick to keep its room (ai.luau `spacing`), or nil when
--- it has room and its goal does too (the mover keeps what the brain asked). `goal` is the brain's
--- goal (nil: it stands). Standing, a body inside another's room steps out past the gap; walking,
--- its goal moves out of any body it lies in, and a walk heading into a body within the gap plus
--- the slide band turns along it, never closing past the gap.
function Spacing.steer(body: Body, goal: Vector3?, neighbors: { Neighbor }): Vector3?
	local tuning = AI.spacing
	local gap = tuning.gapStuds
	local position = body.position
	local push = Vector3.zero
	local band: { Near } = {}
	local others: { Body } = {}
	for _, neighbor in neighbors do
		local fallback = Vector3.xAxis * neighbor.side
		local clear, out = Spacing.clearance(body, neighbor.body, fallback)
		if clear < gap then
			push += out * ((gap - clear) * neighbor.share)
		end
		if clear < gap + tuning.slideStuds then
			local front, rear = Spacing.spine(neighbor.body)
			table.insert(band, { clear = clear, out = out, center = (front + rear) / 2 })
		end
		table.insert(others, neighbor.body)
	end

	if goal == nil then
		local size = push.Magnitude
		if size < AI.flatEpsilon then
			return nil
		end
		local step = position + (push / size) * (size + tuning.stepStuds)
		return Vector3.new(step.X, position.Y, step.Z)
	end

	local fallback = if #neighbors > 0 then Vector3.xAxis * neighbors[1].side else Vector3.xAxis
	local spot = Spacing.standOff(body, goal, others, gap, fallback)
	local moved = flat(spot - goal).Magnitude >= AI.flatEpsilon
	if #band == 0 and push.Magnitude < AI.flatEpsilon then
		return if moved then spot else nil
	end

	local want = flat(spot - position)
	local distance = want.Magnitude
	local walk = want
	-- The nearest body the walk had to turn along: the slide goes round it.
	local binding: Near? = nil
	for _, near in band do
		local into = walk:Dot(near.out)
		local room = math.max(0, near.clear - gap)
		if -into > room + AI.flatEpsilon then
			walk += near.out * (-into - room)
			if binding == nil or near.clear < binding.clear then
				binding = near
			end
		end
	end
	if binding ~= nil then
		-- What is left once the walk may close no more: what it may still close (up to the gap) and
		-- the turn along the body. A turn shorter than slideMinStuds (a goal nearly straight behind
		-- the body) is lengthened to it, so the walk goes round rather than creeping, and the whole
		-- walk is a short one (at most the "walk along" goal, movement.moveAheadStuds), re-aimed
		-- every tick as the body goes round.
		local out = binding.out
		local closing = out * walk:Dot(out)
		local along = walk - closing
		if distance > tuning.slideMinStuds then
			-- Round the body on the side this body already stands of the line from the other's middle
			-- to the goal (left on the line): one way round, the turn along its edge kept turning
			-- that way as the edge does. The way the goal leans from here would flip each tick as
			-- the step crosses that line; and along a flat face (D-332) the turn points at the
			-- goal's foot on that face, back across the line, so it would walk to the face's middle
			-- and stay there. A turn that heads back, or is shorter than slideMinStuds (a goal nearly
			-- straight behind the body), becomes slideMinStuds round.
			local left = Vector3.new(-out.Z, 0, out.X)
			local line = unitFlat(spot - binding.center)
			local offset = flat(position - binding.center)
			-- Which side of the line it stands: the turn of the line onto the offset (seen from above).
			local side = if line ~= nil then line.X * offset.Z - line.Z * offset.X else 0
			local direction = if side <= AI.flatEpsilon then left else -left
			if along:Dot(direction) < tuning.slideMinStuds then
				along = direction * tuning.slideMinStuds
			end
		end
		walk = closing + along
		local length = walk.Magnitude
		if length > AI.movement.moveAheadStuds then
			walk *= AI.movement.moveAheadStuds / length
		end
	end
	local target = position + walk + push
	return Vector3.new(target.X, spot.Y, target.Z)
end

return Spacing
