--!strict
--[[
	RushWorld: how a rushing body meets the world (D-205 to D-210), one set of rules for the server
	(Charger moves the body and resolves the hits, EnemyService casts its world) and for every
	client (RushDraw draws the body ahead of its late root). Pure: every world question goes
	through the cast it is handed; the numbers are ai.luau rushWorld's.

	The world cast is the root's own box (only the root collides, RigBuilder) in the rushing group
	(the world only, D-167), moved along the leg it runs. What it meets is one of:

	  Ground   a face within collision.groundSlopeDegrees of flat (a ramp's, D-204), or a riser no
	           higher than riserStuds above the ground in front of it (a stair's: the box, cast level
	           from lower ground, meets the risers two and three treads ahead, which the body climbs
	           one at a time). The line resolves no further (what stands behind is unseen) but no
	           body stops.
	  Glance   a wall meeting the leg at less than glanceDegrees: the rush bends along the face where
	           the body's leading corner touches it, at the same speed, for the rest of its run.
	  Clip     a corner the root's box overlaps sideways by at most clipStuds (a pillar, a post): the
	           rush sidesteps by the overlap plus clipMarginStuds over the clipRunStuds before the
	           root meets it, and carries on along its line.
	  Slam     any other wall: the body stops with its leading corner on the face (the snout, head
	           on), not its root's box, and is dazed.

	Every distance down a rush is along its path: the line, then the legs its bends and sidesteps
	add (`Leg`), each starting `at` that far down the path from the flat point `from`, running along
	`heading` with the body facing `facing`. The timeline (distanceAt, timeAt) is the clients'
	(RushDraw): the rush speed to the strike beat, then a skid that sheds it evenly over the rest.
]]

local Shared = script.Parent.Parent

local AI = require(Shared.data.ai)
local Pose = require(script.Parent.Pose)

local TUNING = AI.rushWorld

-- The world cast, bound by its caller to the rushing group and the body's own model: a box of
-- `size` at `start` moved by `vector`; how far it travelled before it met something, or nil, and
-- the normal of the face it met (nil: a face named no way, taken for a wall).
export type Cast = (start: CFrame, size: Vector3, vector: Vector3) -> (number?, Vector3?)

--- One stretch of a rush's path (the line is the first).
export type Leg = {
	at: number, -- studs down the path where it starts
	from: Vector3, -- the flat point it starts at (Y 0)
	heading: Vector3, -- flat unit vector it runs along
	facing: Vector3, -- flat unit vector the body faces while on it
}

--- The body a contact is judged on: its corners at rest in its root's space and its root's size.
export type Body = {
	profile: { Vector3 },
	size: Vector3,
}

export type Kind = "Slam" | "Glance" | "Clip"

--- What a rush does about a wall its cast met (RushWorld.contact).
export type Contact = {
	kind: Kind,
	-- Slam: where down the path the root stops. Glance and Clip: where the bend or the sidestep's
	-- end is, where the cue plays.
	at: number,
	legs: { Leg }?, -- Glance and Clip: the path from here on (the legs before kept)
	point: Vector3, -- where the body meets the face (the cue's place)
	normal: Vector3, -- the face's flat normal, toward the body
}

local RushWorld = {}

--- How near two distances down a path are the same place: a hundredth of a stud (positions are
--- single precision; the server's and a client's sums of the same path agree to about this).
RushWorld.SAME_STUDS = 1e-2

local CORNERS = { -1, 1 }
-- The ground probe: a small box dropped straight down (a ray falls through the seams between
-- parts; a wider box finds a step's top before the spot is over it), and how far in front of a face
-- the riser rule reads the ground.
local PROBE_SIZE = Vector3.new(0.1, 0.1, 0.1)
local PROBE_BEFORE = 0.25
local PROBE_PAST = 0.5
local EPSILON = 1e-6

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitFlat(v: Vector3?, fallback: Vector3): Vector3
	if v == nil then
		return fallback
	end
	local f = flat(v)
	if f.Magnitude < EPSILON then
		return fallback
	end
	return f.Unit
end

-- The flat right of a flat heading.
local function rightOf(heading: Vector3): Vector3
	return Vector3.new(-heading.Z, 0, heading.X)
end

-- ---------------------------------------------------------------------------------------------
-- Ground
-- ---------------------------------------------------------------------------------------------

--- Whether a face's normal is ground a body climbs (D-204): within ai.luau
--- collision.groundSlopeDegrees of straight up. Nil (a face named no way) is a wall.
function RushWorld.isGround(normal: Vector3?): boolean
	if normal == nil or normal.Magnitude < EPSILON then
		return false
	end
	return normal.Unit.Y >= math.cos(math.rad(AI.collision.groundSlopeDegrees))
end

--- The height of the ground under `spot` (its X and Z), looking down from `spot`'s own height by
--- `depth` studs; nil when nothing is there (or the probe starts inside something).
function RushWorld.groundBelow(cast: Cast, spot: Vector3, depth: number): number?
	if not (depth > 0) then
		return nil
	end
	local ok, travelled, _ = pcall(cast, CFrame.new(spot), PROBE_SIZE, Vector3.new(0, -depth, 0))
	if not ok or typeof(travelled) ~= "number" then
		return nil
	end
	return spot.Y - travelled - PROBE_SIZE.Y / 2
end

-- How far a box of `size` at `frame` reaches from its centre along `direction`.
local function boxReach(frame: CFrame, size: Vector3, direction: Vector3): number
	local half = size / 2
	return math.abs(frame.RightVector:Dot(direction)) * half.X
		+ math.abs(frame.UpVector:Dot(direction)) * half.Y
		+ math.abs(frame.LookVector:Dot(direction)) * half.Z
end

--- Whether the face a root's box at `frame` met after its centre moved `free` studs along the flat
--- unit `direction` is a step the body climbs: nothing stands higher than riserStuds above the
--- ground just in front of the face, across the box's width. False with no ground in front of it.
function RushWorld.climbable(cast: Cast, frame: CFrame, size: Vector3, direction: Vector3, free: number): boolean
	local reach = boxReach(frame, size, direction)
	local before = frame.Position + direction * math.max(0, free + reach - PROBE_BEFORE)
	local ground = RushWorld.groundBelow(cast, before, TUNING.probeStuds)
	if ground == nil then
		return false
	end
	local width = 2 * boxReach(frame, size, rightOf(direction))
	local rail = Vector3.new(width, PROBE_SIZE.Y, PROBE_SIZE.Y)
	local top = Vector3.new(before.X, ground + TUNING.riserStuds + PROBE_SIZE.Y, before.Z)
	local ok, travelled, _ =
		pcall(cast, CFrame.lookAt(top, top + direction), rail, direction * (PROBE_BEFORE + PROBE_PAST))
	return ok and typeof(travelled) ~= "number"
end

--- Whether what a root's box at `frame` met (the cast's normal, after its centre moved `free` along
--- `direction`) is ground the body runs on: a gentle slope or a step it climbs (RushWorld.climbable).
function RushWorld.runsOver(
	cast: Cast,
	frame: CFrame,
	size: Vector3,
	direction: Vector3,
	free: number,
	normal: Vector3?
): boolean
	return RushWorld.isGround(normal) or RushWorld.climbable(cast, frame, size, direction, free)
end

-- ---------------------------------------------------------------------------------------------
-- The body
-- ---------------------------------------------------------------------------------------------

--- A body's corners at rest in its root's space: every BasePart's eight, placed by the rig's joints
--- at rest (Pose.solve with no offsets) so an animated client and the server read the same body,
--- or where they stand when no joint places them (a model without joints). Its blocker faces (the
--- blockers group, D-198, D-CH4) are not its body: they stand over its idle and what it holds, and
--- the server measures the rig before it has them (EnemyService.spawn), so the client's replicated
--- model, faces and all, reads the same body (D-CI5). Empty without a root.
function RushWorld.profileOf(model: Model): { Vector3 }
	local root = model.PrimaryPart
	local corners: { Vector3 } = {}
	if root == nil then
		return corners
	end
	local ok, solved = pcall(Pose.solve, model, CFrame.identity, {})
	local rest: Pose.Solved = if ok then solved else {}
	local rootFrame = root.CFrame
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.CollisionGroup == AI.collision.blockers then
			continue
		end
		local frame = rest[part.Name] or rootFrame:ToObjectSpace(part.CFrame)
		local half = part.Size / 2
		for _, x in CORNERS do
			for _, y in CORNERS do
				for _, z in CORNERS do
					table.insert(corners, frame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z)))
				end
			end
		end
	end
	return corners
end

--- How far a body facing the flat `facing` reaches from its root's centre along `direction`
--- (flattened), over its corners; 0 for no corners.
function RushWorld.support(profile: { Vector3 }, facing: Vector3, direction: Vector3): number
	local look = unitFlat(facing, -Vector3.zAxis)
	local local_ = CFrame.lookAt(Vector3.zero, look):VectorToObjectSpace(flat(direction))
	local best = 0
	for _, corner in profile do
		best = math.max(best, corner.X * local_.X + corner.Z * local_.Z)
	end
	return best
end

-- The corner that reaches farthest along `direction` (in world axes, from the root's centre).
local function leadCorner(profile: { Vector3 }, facing: Vector3, direction: Vector3): Vector3
	local frame = CFrame.lookAt(Vector3.zero, unitFlat(facing, -Vector3.zAxis))
	local d = flat(direction)
	local best, bestValue = Vector3.zero, -math.huge
	for _, corner in profile do
		local world = frame:VectorToWorldSpace(corner)
		local value = world.X * d.X + world.Z * d.Z
		if value > bestValue then
			best, bestValue = world, value
		end
	end
	return best
end

--- How far the body reaches ahead of its root's centre along its own look (the snout).
function RushWorld.front(profile: { Vector3 }): number
	local best = 0
	for _, corner in profile do
		best = math.max(best, -corner.Z)
	end
	return best
end

--- How far short of where its root's box meets a face (normal `normal`) the root stops so the
--- body's leading corner rests on it, the body facing `facing` and running along `heading`: the
--- body's reach toward the face past the box's, over how fast the run closes on it. Never more
--- than the body's reach past the box along the run (the snout head on), never less than 0.
function RushWorld.pullBack(body: Body, facing: Vector3, heading: Vector3, normal: Vector3?): number
	local run = unitFlat(heading, -Vector3.zAxis)
	local look = unitFlat(facing, run)
	local into = -unitFlat(normal, -run)
	local closing = run:Dot(into)
	local frame = CFrame.lookAt(Vector3.zero, look)
	local most = math.max(0, RushWorld.support(body.profile, look, run) - boxReach(frame, body.size, run))
	if closing <= EPSILON then
		return 0
	end
	local past = RushWorld.support(body.profile, look, into) - boxReach(frame, body.size, into)
	return math.clamp(past / closing, 0, most)
end

--- The angle in degrees a face (normal `normal`) meets a run along `heading`: 90 head on, 0 along
--- it. A face named no way is head on.
function RushWorld.meetDegrees(heading: Vector3, normal: Vector3?): number
	local run = unitFlat(heading, -Vector3.zAxis)
	local into = -unitFlat(normal, -run)
	return math.deg(math.asin(math.clamp(run:Dot(into), 0, 1)))
end

-- ---------------------------------------------------------------------------------------------
-- The path
-- ---------------------------------------------------------------------------------------------

--- A rush's path before any bend: its line from `origin` along `direction`.
function RushWorld.line(origin: Vector3, direction: Vector3): { Leg }
	local heading = unitFlat(direction, -Vector3.zAxis)
	return { { at = 0, from = flat(origin), heading = heading, facing = heading } }
end

--- The index of the leg `d` studs down the path lies on.
function RushWorld.legIndex(legs: { Leg }, d: number): number
	local index = 1
	for i = 2, #legs do
		if legs[i].at <= d then
			index = i
		else
			break
		end
	end
	return index
end

--- Where the leg `index` ends down the path (math.huge for the last).
function RushWorld.legEnd(legs: { Leg }, index: number): number
	local nextLeg = legs[index + 1]
	return if nextLeg ~= nil then nextLeg.at else math.huge
end

--- The flat point `d` studs down the path.
function RushWorld.pointAt(legs: { Leg }, d: number): Vector3
	local leg = legs[RushWorld.legIndex(legs, d)]
	return leg.from + leg.heading * (d - leg.at)
end

--- How far down the path the flat point nearest `position` is (never before `from`'s leg, so a
--- body is never read back onto a leg it left).
function RushWorld.project(legs: { Leg }, position: Vector3, from: number?): number
	local p = flat(position)
	local first = if from ~= nil then RushWorld.legIndex(legs, from) else 1
	local best, bestGap = 0, math.huge
	for index = first, #legs do
		local leg = legs[index]
		local length = RushWorld.legEnd(legs, index) - leg.at
		local along = math.clamp((p - leg.from):Dot(leg.heading), 0, math.max(0, length))
		local gap = (p - (leg.from + leg.heading * along)).Magnitude
		if gap <= bestGap + EPSILON then
			best, bestGap = leg.at + along, gap
		end
	end
	return best
end

--- Whether two paths are the same (every leg within a hundredth of a stud and of a degree): a look
--- that finds the bend or the sidestep the path already has changes nothing.
function RushWorld.sameLegs(a: { Leg }, b: { Leg }): boolean
	if #a ~= #b then
		return false
	end
	for index, leg in a do
		local other = b[index]
		if
			math.abs(leg.at - other.at) > RushWorld.SAME_STUDS
			or (leg.from - other.from).Magnitude > RushWorld.SAME_STUDS
			or leg.heading:Dot(other.heading) < 1 - 1e-4
			or leg.facing:Dot(other.facing) < 1 - 1e-4
		then
			return false
		end
	end
	return true
end

--- How far down the path the root's box may look along the leg `index` runs (its front, when the
--- root stands at the leg's end): a leg that bends looks no further than where its root turns
--- (`reach` past its end), the last as far as the body's snout gets at the run's end (`front` past
--- `length`), so a wall the snout would reach is a slam.
function RushWorld.lookLimit(legs: { Leg }, index: number, length: number, reach: number, front: number): number
	if legs[index + 1] ~= nil then
		return RushWorld.legEnd(legs, index) + reach
	end
	return length + front
end

-- The legs up to and including `index`, a fresh list.
local function keep(legs: { Leg }, index: number): { Leg }
	local kept = table.create(index)
	for i = 1, index do
		kept[i] = legs[i]
	end
	return kept
end

-- ---------------------------------------------------------------------------------------------
-- Contact
-- ---------------------------------------------------------------------------------------------

--- How far the root's box, moved by the flat `offset` from where it stands, runs along the flat
--- unit `direction` before it meets a wall, when that is within `distance`; nil when it runs that far
--- (ground it runs over is no wall). The server casts it from its root, a client from its drawn body.
export type Probe = (offset: Vector3, direction: Vector3, distance: number) -> number?

-- Whether the root's box, shifted sideways by `shift`, gets there without meeting a wall and then
-- runs `distance` along `heading` clear (a box that starts inside a wall is never told it is).
local function clearAt(probe: Probe, shift: Vector3, heading: Vector3, distance: number): boolean
	local length = shift.Magnitude
	if length > EPSILON and probe(Vector3.zero, shift / length, length) ~= nil then
		return false
	end
	return probe(shift, heading, distance) == nil
end

--- What the rush does about a wall: the root, `along` studs down the path (on the leg there) and
--- standing at height `y`, has `free` studs to run along that leg before its box meets a face of
--- normal `normal` (not ground). `probe` asks the world whether a sidestep clears a corner (nil: no
--- corner is shouldered past). A rush that has run maxLegs legs only slams.
function RushWorld.contact(
	legs: { Leg },
	along: number,
	free: number,
	normal: Vector3?,
	body: Body,
	y: number,
	probe: Probe?
): Contact
	local index = RushWorld.legIndex(legs, along)
	local leg = legs[index]
	local heading = leg.heading
	local face = unitFlat(normal, -heading)
	local touch = along + math.max(0, free) -- where the root's box meets the face
	local meet = RushWorld.meetDegrees(heading, face)
	local pull = RushWorld.pullBack(body, leg.facing, heading, face)
	local room = TUNING.maxLegs - #legs

	if meet < TUNING.glanceDegrees and room >= 1 then
		local at = math.max(along, touch - pull)
		local tangent = unitFlat(heading - face * heading:Dot(face), heading)
		local legsNow = keep(legs, index)
		local start = RushWorld.pointAt(legs, at)
		table.insert(legsNow, { at = at, from = start, heading = tangent, facing = tangent })
		local corner = leadCorner(body.profile, leg.facing, -face)
		return {
			kind = "Glance",
			at = at,
			legs = legsNow,
			point = start + corner + Vector3.new(0, y, 0),
			normal = face,
		}
	end

	if probe ~= nil and room >= 2 then
		local right = rightOf(heading)
		local distance = math.max(0, free) + TUNING.clipPassStuds
		local best: number? = nil
		local bestSide = 1
		for _, sign in CORNERS do
			if not clearAt(probe, right * (sign * TUNING.clipStuds), heading, distance) then
				continue
			end
			local low, high = 0, TUNING.clipStuds
			for _ = 1, TUNING.clipBisections do
				local mid = (low + high) / 2
				if clearAt(probe, right * (sign * mid), heading, distance) then
					high = mid
				else
					low = mid
				end
			end
			if best == nil or high < (best :: number) then
				best, bestSide = high, sign
			end
		end
		if best ~= nil then
			local overlap = best :: number
			-- The body's side toward the corner reaches past its root's box by `wider` (a flank, a
			-- leg): the sidestep clears the body, not just the box.
			local frame = CFrame.lookAt(Vector3.zero, leg.facing)
			local wider = math.max(
				0,
				RushWorld.support(body.profile, leg.facing, right * -bestSide) - boxReach(frame, body.size, right)
			)
			local shift = right * (bestSide * (overlap + wider + TUNING.clipMarginStuds))
			-- The sidestep is done when the body's front (the snout, ahead of the root's box by
			-- `lead`) reaches the corner's face, over the clipRunStuds before that; one steeper than
			-- it is wide (a corner seen too late) is no shoulder past it: a slam.
			local reach = boxReach(frame, body.size, heading)
			local lead = math.max(0, RushWorld.support(body.profile, leg.facing, heading) - reach)
			local sideEnd = touch - lead
			local a1 = math.max(along, sideEnd - TUNING.clipRunStuds)
			local run = sideEnd - a1
			if run >= shift.Magnitude then
				local start = RushWorld.pointAt(legs, a1)
				local side = heading * run + shift
				local sideLength = side.Magnitude
				local legsNow = keep(legs, index)
				table.insert(legsNow, { at = a1, from = start, heading = side.Unit, facing = leg.facing })
				local back = start + side
				local at = a1 + sideLength
				table.insert(legsNow, { at = at, from = back, heading = heading, facing = leg.facing })
				local half = boxReach(frame, body.size, right)
				local corner = RushWorld.pointAt(legs, touch) + heading * reach - right * (bestSide * (half - overlap))
				return {
					kind = "Clip",
					at = at,
					legs = legsNow,
					point = corner + Vector3.new(0, y, 0),
					normal = face,
				}
			end
		end
	end

	local stop = math.max(along, touch - pull)
	local corner = leadCorner(body.profile, leg.facing, -face)
	return {
		kind = "Slam",
		at = stop,
		legs = nil,
		point = RushWorld.pointAt(legs, stop) + corner + Vector3.new(0, y, 0),
		normal = face,
	}
end

-- ---------------------------------------------------------------------------------------------
-- The timeline
-- ---------------------------------------------------------------------------------------------

-- Seconds after the launch the full speed ends and the skid begins.
local function cruiseSeconds(speed: number, length: number, strike: number): number
	if speed <= 0 then
		return 0
	end
	return math.clamp(strike, 0, length / speed)
end

--- How far down its path the timeline has a rush `t` seconds after its launch: `speed` studs a
--- second until `strike`, then a skid that sheds that speed evenly over the rest of `length`.
function RushWorld.distanceAt(speed: number, length: number, strike: number, t: number): number
	if t <= 0 or speed <= 0 then
		return 0
	end
	local cruise = cruiseSeconds(speed, length, strike)
	if t <= cruise then
		return speed * t
	end
	local covered = speed * cruise
	local rest = math.max(0, length - covered)
	if rest <= 0 then
		return length
	end
	local skid = 2 * rest / speed
	local u = math.min(t - cruise, skid)
	return covered + speed * u - 0.5 * (speed / skid) * u * u
end

--- Seconds after its launch the timeline brings a rush `d` studs down its path (distanceAt's
--- inverse; the skid's end for `d` at or past `length`).
function RushWorld.timeAt(speed: number, length: number, strike: number, d: number): number
	if d <= 0 or speed <= 0 then
		return 0
	end
	local cruise = cruiseSeconds(speed, length, strike)
	local covered = speed * cruise
	if d <= covered then
		return d / speed
	end
	local rest = math.max(0, length - covered)
	if rest <= 0 then
		return cruise
	end
	local skid = 2 * rest / speed
	local slowing = speed / skid
	local left = math.min(d, length) - covered
	local u = (speed - math.sqrt(math.max(0, speed * speed - 2 * slowing * left))) / slowing
	return cruise + math.clamp(u, 0, skid)
end

return RushWorld
