--!strict
--[[
	How a rushing body meets the world (D-205 to D-209): RushWorld's rules alone, then a Charger that
	runs them in a box world (head-on and angled walls, a glancing wall, a pillar it clips, a stair).

	The world is a few shapes and the engine's box cast over them: a vertical plane (a wall at any
	angle, its face toward the body) or a box, met by the root's own box swept along a vector. Like
	the engine's it never sees a shape the box starts in. The body is the real Boar (RigBuilder): its
	corners at rest (RushWorld.profileOf) and its root's box (2.4 x 2.4 x 5, its centre 2.8 above the
	ground).
]]

local RushWorld = Harness.load("src/shared/choreo/RushWorld")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Brain = Harness.load("src/server/ai/Brain")
local Charger = Harness.load("src/server/ai/Charger")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")

local WORLD = AI.rushWorld
local TICK = AI.tickSeconds()
local FRAME = 1 / 60
local FORWARD = Vector3.new(0, 0, -1)
local HEIGHT = 2.8 -- the root's centre above the ground (hip height + half the root)

-- RushWorld's own types, spelled out here: a module loaded through the harness carries none.
type Cast = (start: CFrame, size: Vector3, vector: Vector3) -> (number?, Vector3?)
type Probe = (offset: Vector3, direction: Vector3, distance: number) -> number?
type Leg = { at: number, from: Vector3, heading: Vector3, facing: Vector3 }
type Body = { profile: { Vector3 }, size: Vector3 }
type Contact = { kind: string, at: number, legs: { Leg }?, point: Vector3, normal: Vector3 }
type Shape = { kind: string, point: Vector3?, normal: Vector3?, min: Vector3?, max: Vector3? }

local function plane(point: Vector3, normal: Vector3): Shape
	return { kind = "plane", point = point, normal = normal.Unit }
end

local function box(min: Vector3, max: Vector3): Shape
	return { kind = "box", min = min, max = max }
end

local FLOOR = box(Vector3.new(-500, -1, -500), Vector3.new(500, 0, 500))

local function axis(v: Vector3, index: number): number
	return if index == 1 then v.X elseif index == 2 then v.Y else v.Z
end

local function unitAxis(index: number): Vector3
	return if index == 1 then Vector3.xAxis elseif index == 2 then Vector3.yAxis else Vector3.zAxis
end

-- The engine's Blockcast over `shapes`: how far the box of `size` at `start` moves along `vector`
-- before it meets one, and that face's normal.
local function castIn(shapes: { Shape }): Cast
	return function(start: CFrame, size: Vector3, vector: Vector3): (number?, Vector3?)
		local length = vector.Magnitude
		if length < 1e-9 then
			return nil, nil
		end
		local u = vector / length
		local half = size / 2
		local c = start.Position
		local best: number?, bestNormal: Vector3? = nil, nil
		for _, shape in shapes do
			if shape.kind == "plane" then
				local n = shape.normal :: Vector3
				local s = math.abs(start.RightVector:Dot(n)) * half.X
					+ math.abs(start.UpVector:Dot(n)) * half.Y
					+ math.abs(start.LookVector:Dot(n)) * half.Z
				local d0 = (c - (shape.point :: Vector3)):Dot(n)
				local closing = -u:Dot(n)
				if closing > 1e-9 and d0 >= s - 1e-9 then
					local t = (d0 - s) / closing
					if t <= length and (best == nil or t < (best :: number)) then
						best, bestNormal = t, n
					end
				end
			else
				local e = Vector3.new(
					math.abs(start.RightVector.X) * half.X
						+ math.abs(start.UpVector.X) * half.Y
						+ math.abs(start.LookVector.X) * half.Z,
					math.abs(start.RightVector.Y) * half.X
						+ math.abs(start.UpVector.Y) * half.Y
						+ math.abs(start.LookVector.Y) * half.Z,
					math.abs(start.RightVector.Z) * half.X
						+ math.abs(start.UpVector.Z) * half.Y
						+ math.abs(start.LookVector.Z) * half.Z
				)
				local lo, hi = (shape.min :: Vector3) - e, (shape.max :: Vector3) + e
				local inside = true
				for index = 1, 3 do
					local p = axis(c, index)
					if p <= axis(lo, index) or p >= axis(hi, index) then
						inside = false
					end
				end
				if inside then
					continue -- a box that starts in a shape never sees it
				end
				local enter, exit, normal = -math.huge, math.huge, Vector3.zero
				local missed = false
				for index = 1, 3 do
					local p, v = axis(c, index), axis(u, index)
					local l, h = axis(lo, index), axis(hi, index)
					if math.abs(v) < 1e-12 then
						if p <= l or p >= h then
							missed = true
						end
					else
						local t1, t2 = (l - p) / v, (h - p) / v
						if t1 > t2 then
							t1, t2 = t2, t1
						end
						if t1 > enter then
							enter = t1
							normal = unitAxis(index) * (if v > 0 then -1 else 1)
						end
						exit = math.min(exit, t2)
					end
				end
				if not missed and enter <= exit and enter >= 0 and enter <= length then
					if best == nil or enter < (best :: number) then
						best, bestNormal = enter, normal
					end
				end
			end
		end
		return best, bestNormal
	end
end

local function boxReach(frame: CFrame, size: Vector3, direction: Vector3): number
	local half = size / 2
	return math.abs(frame.RightVector:Dot(direction)) * half.X
		+ math.abs(frame.UpVector:Dot(direction)) * half.Y
		+ math.abs(frame.LookVector:Dot(direction)) * half.Z
end

-- What the server's worldAhead and a client's room ask: how far the root's centre at `frame` moves
-- along the flat unit `direction` before its box meets a wall within `distance` (nil: none, or
-- ground it runs over), and the face's normal.
local function freeAhead(
	cast: Cast,
	frame: CFrame,
	size: Vector3,
	direction: Vector3,
	distance: number
): (number?, Vector3?)
	local reach = boxReach(frame, size, direction)
	local travelled, normal = cast(frame - direction * reach, size, direction * (distance + reach))
	if travelled == nil then
		return nil, nil
	end
	local free = math.max(0, travelled - reach)
	if RushWorld.runsOver(cast, frame, size, direction, free, normal) then
		return nil, nil
	end
	return free, normal
end

local function probeOf(cast: Cast, frame: CFrame, size: Vector3): Probe
	return function(offset: Vector3, direction: Vector3, distance: number): number?
		local free = freeAhead(cast, frame + offset, size, direction, distance)
		return free
	end
end

local model = RigBuilder.build("Boar")
local BODY: Body = {
	profile = RushWorld.profileOf(model),
	size = (model.PrimaryPart :: BasePart).Size,
}
local FRONT = RushWorld.front(BODY.profile)
local ROOT_HALF = BODY.size.Z / 2

-- The body's corners in the world, its root at the flat point `at` facing the flat `facing`.
local function corners(at: Vector3, facing: Vector3): { Vector3 }
	local frame = CFrame.lookAt(Vector3.new(at.X, HEIGHT, at.Z), Vector3.new(at.X, HEIGHT, at.Z) + facing)
	local list = {}
	for _, corner in BODY.profile do
		table.insert(list, frame:PointToWorldSpace(corner))
	end
	return list
end

-- How deep the body (root `along` studs down `legs`, facing that leg's way) is inside a plane's
-- face (0: not in it).
local function planeDepth(legs: { Leg }, along: number, wall: Shape): number
	local leg = legs[RushWorld.legIndex(legs, along)]
	local deepest = 0
	for _, corner in corners(RushWorld.pointAt(legs, along), leg.facing) do
		deepest =
			math.max(deepest, -((corner - (wall.point :: Vector3)) * Vector3.new(1, 0, 1)):Dot(wall.normal :: Vector3))
	end
	return deepest
end

-- How deep any corner of the body, or of its root's box, stands inside a box's footprint.
local function boxDepth(at: Vector3, facing: Vector3, shape: Shape): number
	local lo, hi = shape.min :: Vector3, shape.max :: Vector3
	local points = corners(at, facing)
	local frame = CFrame.lookAt(Vector3.new(at.X, HEIGHT, at.Z), Vector3.new(at.X, HEIGHT, at.Z) + facing)
	local half = BODY.size / 2
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(points, frame:PointToWorldSpace(Vector3.new(half.X * x, 0, half.Z * z)))
		end
	end
	local deepest = 0
	for _, p in points do
		local depth = math.min(p.X - lo.X, hi.X - p.X, p.Z - lo.Z, hi.Z - p.Z)
		if p.Y > lo.Y and p.Y < hi.Y then
			deepest = math.max(deepest, depth)
		end
	end
	return deepest
end

local START = CFrame.lookAt(Vector3.new(0, HEIGHT, 0), Vector3.new(0, HEIGHT, -1))

-- RushWorld.contact for a root standing at the line's start, facing down -Z, in `shapes`.
local function contactIn(shapes: { Shape }, legs: { Leg }?): (Contact?, { Leg })
	local cast = castIn(shapes)
	local path = legs or RushWorld.line(Vector3.zero, FORWARD)
	local free, normal = freeAhead(cast, START, BODY.size, FORWARD, 40)
	if free == nil then
		return nil, path
	end
	return RushWorld.contact(path, 0, free, normal, BODY, HEIGHT, probeOf(cast, START, BODY.size)), path
end

-- A wall whose face meets a run down -Z at `meet` degrees, `ahead` studs down it.
local function angled(meet: number, ahead: number): Shape
	local r = math.rad(meet)
	return plane(Vector3.new(0, 0, -ahead), Vector3.new(math.cos(r), 0, math.sin(r)))
end

describe("RushWorld: what the world is to a rushing body (D-209)", function()
	it("a face within groundSlopeDegrees of flat is ground; steeper, or named no way, is a wall", function()
		local slope = AI.collision.groundSlopeDegrees
		local function tilted(degrees: number): Vector3
			local r = math.rad(degrees)
			return Vector3.new(0, math.cos(r), math.sin(r))
		end
		expect(RushWorld.isGround(Vector3.yAxis)).toBe(true)
		expect(RushWorld.isGround(tilted(slope - 1))).toBe(true)
		expect(RushWorld.isGround(tilted(slope + 1))).toBe(false)
		expect(RushWorld.isGround(Vector3.zAxis)).toBe(false)
		expect(RushWorld.isGround(nil)).toBe(false)
	end)

	it("the ground under a spot is the top of what stands there", function()
		local cast = castIn({ FLOOR, box(Vector3.new(2, 0, -2), Vector3.new(4, 1, 2)) })
		expect(RushWorld.groundBelow(cast, Vector3.new(0, 5, 0), WORLD.probeStuds)).toBeCloseTo(0, 1e-6)
		expect(RushWorld.groundBelow(cast, Vector3.new(3, 5, 0), WORLD.probeStuds)).toBeCloseTo(1, 1e-6)
		expect(RushWorld.groundBelow(castIn({}), Vector3.new(0, 5, 0), WORLD.probeStuds)).toBeNil()
	end)

	it("a stair's riser the box meets two treads ahead is climbed; a wall is not; a ramp is ground", function()
		-- Treads 3 studs deep, risers 1 high: the root's box (its bottom 1.6 up) meets the second.
		local stairs = { FLOOR }
		for k = 1, 5 do
			table.insert(stairs, box(Vector3.new(-10, 0, -200), Vector3.new(10, k, -(3 + 3 * k))))
		end
		local cast = castIn(stairs)
		local reach = boxReach(START, BODY.size, FORWARD)
		local travelled, normal = cast(START - FORWARD * reach, BODY.size, FORWARD * 30)
		expect(travelled).never.toBeNil()
		expect(RushWorld.runsOver(cast, START, BODY.size, FORWARD, (travelled :: number) - reach, normal)).toBe(true)
		expect(freeAhead(cast, START, BODY.size, FORWARD, 30)).toBeNil()
		-- A wall: as high as a stair's riser is not, from the floor.
		local wall = castIn({ FLOOR, box(Vector3.new(-10, 0, -200), Vector3.new(10, 10, -9)) })
		local free = freeAhead(wall, START, BODY.size, FORWARD, 30)
		expect(free).toBeCloseTo(9 - ROOT_HALF, 1e-6)
		-- Higher than riserStuds above the tread in front of it is a wall too.
		expect(WORLD.riserStuds).toBeLessThan(2)
		local tall = castIn({ FLOOR, box(Vector3.new(-10, 0, -200), Vector3.new(10, 2, -9)) })
		expect(freeAhead(tall, START, BODY.size, FORWARD, 30)).toBeCloseTo(9 - ROOT_HALF, 1e-6)
		-- A ramp's face is ground whatever stands behind it.
		local up = math.rad(AI.collision.groundSlopeDegrees - 1)
		expect(RushWorld.runsOver(wall, START, BODY.size, FORWARD, 1, Vector3.new(0, math.cos(up), math.sin(up)))).toBe(
			true
		)
	end)
end)

describe("RushWorld: a slam rests the snout on the face (D-205)", function()
	it("the body's front is its snout, 3.1 studs past its root's box", function()
		expect(FRONT).toBeCloseTo(5.6, 0.01)
		expect(RushWorld.pullBack(BODY, FORWARD, FORWARD, -FORWARD)).toBeCloseTo(FRONT - ROOT_HALF, 1e-6)
		expect(RushWorld.meetDegrees(FORWARD, -FORWARD)).toBeCloseTo(90, 1e-6)
		expect(RushWorld.meetDegrees(FORWARD, nil)).toBeCloseTo(90, 1e-6)
	end)

	it("head on: it stops with the snout on the face, never in it", function()
		for _, ahead in { 6, 8, 10, 18 } do
			local wall = plane(Vector3.new(0, 0, -ahead), -FORWARD)
			local contact, legs = contactIn({ FLOOR, wall })
			expect(contact).never.toBeNil()
			local c = contact :: Contact
			expect(c.kind).toBe("Slam")
			expect(c.at).toBeCloseTo(math.max(0, ahead - FRONT), 1e-6)
			if ahead > FRONT then
				expect(planeDepth(legs, c.at, wall)).toBeLessThan(1e-3)
				expect(planeDepth(legs, c.at + 0.05, wall)).toBeGreaterThan(0.04)
			end
			expect(c.point.Z).toBeCloseTo(-ahead, 1e-3)
			expect(c.normal:Dot(-FORWARD)).toBeCloseTo(1, 1e-6)
		end
	end)

	it("a wall met at 45, 60 or 75 degrees: its leading corner rests on the face", function()
		for _, meet in { 45, 60, 75 } do
			local wall = angled(meet, 10)
			local contact, legs = contactIn({ FLOOR, wall })
			local c = contact :: Contact
			expect(c.kind).toBe("Slam")
			-- Touching, not in it: a hair further and it is.
			expect(planeDepth(legs, c.at, wall)).toBeLessThan(1e-3)
			expect(planeDepth(legs, c.at + 0.05, wall)).toBeGreaterThan(0)
			-- The cue's point is on the face.
			expect(math.abs(((c.point - (wall.point :: Vector3)) * Vector3.new(1, 0, 1)):Dot(wall.normal :: Vector3))).toBeLessThan(
				1e-3
			)
		end
	end)
end)

describe("RushWorld: a glancing wall bends the run along it (D-206)", function()
	it("met under glanceDegrees, the path bends along the face where the leading corner touches it", function()
		for _, meet in { 15, 30 } do
			expect(meet).toBeLessThan(WORLD.glanceDegrees)
			local wall = angled(meet, 10)
			local contact = contactIn({ FLOOR, wall }) :: Contact
			expect(contact.kind).toBe("Glance")
			local legs = contact.legs :: { Leg }
			expect(#legs).toBe(2)
			local tangent = legs[2].heading
			expect(math.abs(tangent:Dot(wall.normal :: Vector3))).toBeLessThan(1e-6)
			expect(tangent:Dot(FORWARD)).toBeGreaterThan(0) -- on along the wall, never back
			expect(legs[2].at).toBeCloseTo(contact.at, 1e-9)
			-- On the face at the bend, and along it (facing its way) never in it.
			expect(planeDepth(legs, contact.at - 1e-3, wall)).toBeLessThan(1e-3)
			for step = 0, 40 do
				expect(planeDepth(legs, contact.at + step * 0.25, wall)).toBeLessThan(0.05)
			end
		end
	end)

	it("a run that has used its maxLegs legs only slams", function()
		local legs = RushWorld.line(Vector3.zero, FORWARD)
		for index = 2, WORLD.maxLegs do
			table.insert(
				legs,
				{ at = -1e-3 * (WORLD.maxLegs - index + 1), from = Vector3.zero, heading = FORWARD, facing = FORWARD }
			)
		end
		local contact = contactIn({ FLOOR, angled(30, 10) }, legs) :: Contact
		expect(contact.kind).toBe("Slam")
	end)
end)

describe("RushWorld: a corner it overlaps by a little is shouldered past (D-207)", function()
	-- A pillar whose near side stands `overlap` inside the root box's right side, 12 studs down.
	local function pillar(overlap: number): Shape
		local side = BODY.size.X / 2
		return box(Vector3.new(side - overlap, 0, -14), Vector3.new(side - overlap + 2, 10, -12))
	end

	for _, overlap in { 0.1, 0.25, 0.5, 0.75, 1.0 } do
		it(("overlap %.2f: a sidestep that clears the whole body, then on down the line"):format(overlap), function()
			local shape = pillar(overlap)
			local contact = contactIn({ FLOOR, shape }) :: Contact
			expect(contact.kind).toBe("Clip")
			local legs = contact.legs :: { Leg }
			expect(#legs).toBe(3)
			-- Away from the pillar, by at least the overlap plus the margin, then down the line again.
			expect(legs[3].from.X).toBeLessThan(-(overlap + WORLD.clipMarginStuds) + 1e-6)
			expect(legs[3].heading:Dot(FORWARD)).toBeCloseTo(1, 1e-9)
			expect(legs[2].facing:Dot(FORWARD)).toBeCloseTo(1, 1e-9) -- it sidesteps, facing ahead
			-- The body (every corner, and its root's box) never stands in the pillar along the path.
			for step = 0, 120 do
				local along = step * 0.2
				local leg = legs[RushWorld.legIndex(legs, along)]
				expect(boxDepth(RushWorld.pointAt(legs, along), leg.facing, shape)).toBeLessThan(1e-3)
			end
		end)
	end

	it("a corner deeper than clipStuds is a slam with the snout on its face", function()
		local shape = pillar(WORLD.clipStuds + 0.3)
		local contact = contactIn({ FLOOR, shape }) :: Contact
		expect(contact.kind).toBe("Slam")
		expect(contact.at + FRONT).toBeCloseTo(12, 1e-6)
	end)
end)

describe("RushWorld: the path and the timeline", function()
	it("looks no further than a bend's root, or the snout at the run's end", function()
		local legs = RushWorld.line(Vector3.zero, FORWARD)
		expect(RushWorld.lookLimit(legs, 1, 22, ROOT_HALF, FRONT)).toBeCloseTo(22 + FRONT, 1e-9)
		table.insert(legs, { at = 7, from = Vector3.new(0, 0, -7), heading = Vector3.xAxis, facing = Vector3.xAxis })
		expect(RushWorld.lookLimit(legs, 1, 22, ROOT_HALF, FRONT)).toBeCloseTo(7 + ROOT_HALF, 1e-9)
		expect(RushWorld.lookLimit(legs, 2, 22, ROOT_HALF, FRONT)).toBeCloseTo(22 + FRONT, 1e-9)
	end)

	it("the same path within SAME_STUDS is the same; further off is not", function()
		local a = RushWorld.line(Vector3.zero, FORWARD)
		local b = RushWorld.line(Vector3.new(RushWorld.SAME_STUDS / 2, 0, 0), FORWARD)
		local c = RushWorld.line(Vector3.new(RushWorld.SAME_STUDS * 2, 0, 0), FORWARD)
		expect(RushWorld.sameLegs(a, b)).toBe(true)
		expect(RushWorld.sameLegs(a, c)).toBe(false)
		expect(RushWorld.sameLegs(a, RushWorld.line(Vector3.zero, Vector3.xAxis))).toBe(false)
	end)

	it("timeAt is the timeline's inverse, through the skid", function()
		local speed, length, strike = 28, 22, 0.5
		for step = 0, 44 do
			local d = step * 0.5
			local t = RushWorld.timeAt(speed, length, strike, d)
			expect(RushWorld.distanceAt(speed, length, strike, t)).toBeCloseTo(d, 1e-6)
		end
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- A Charger in a box world
-- ---------------------------------------------------------------------------------------------

local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]

local function chargerIn(shapes: { Shape })
	local cast = castIn(shapes)
	local w: any = {
		time = 0,
		position = Vector3.new(0, HEIGHT, 0),
		facing = FORWARD,
		record = { state = "Idle", threat = {} },
		players = { { id = 1, position = Vector3.new(0, 0, -20) } },
		goal = nil,
		speed = nil,
		moving = false,
		strikes = {},
		ends = {},
		turns = {},
		dazes = {},
		goals = {},
		path = {}, -- where the root stood, and its facing, after every frame
	}
	local function frame(): CFrame
		return CFrame.lookAt(w.position, w.position + w.facing)
	end
	w.context = {
		entityId = 3,
		def = Enemies.scaled(BOAR),
		home = w.position,
		now = function()
			return w.time
		end,
		getRecord = function()
			return w.record
		end,
		players = function()
			return w.players
		end,
		position = function()
			return w.position
		end,
		facing = function()
			return w.facing
		end,
		moveTo = function(position, speed)
			w.goal = position
			w.speed = speed
			w.moving = true
			table.insert(w.goals, { time = w.time, goal = position })
		end,
		stop = function()
			w.moving = false
			w.goal = nil
		end,
		face = function(direction)
			w.facing = direction
		end,
		telegraph = function() end,
		strike = function(_attack, origin, facing, options)
			table.insert(w.strikes, { time = w.time, origin = origin, facing = facing, span = options.span })
		end,
		setState = function(state)
			w.record.state = state
		end,
		actionStarted = function() end,
		random = Random.new(3),
		bodyExtents = function()
			return FRONT, 3.3
		end,
		bodyProfile = function()
			return BODY
		end,
		rootReach = function(direction: Vector3): number
			return boxReach(frame(), BODY.size, direction)
		end,
		worldAhead = function(direction: Vector3, distance: number, offset: Vector3?): (number?, boolean?, Vector3?)
			local flat = (direction * Vector3.new(1, 0, 1)).Unit
			local at = frame() + (offset or Vector3.zero)
			local reach = boxReach(at, BODY.size, flat)
			local travelled, normal = cast(at - flat * reach, BODY.size, flat * distance)
			if travelled == nil then
				return nil, nil, nil
			end
			local free = math.max(0, travelled - reach)
			return math.max(0, travelled), RushWorld.runsOver(cast, at, BODY.size, flat, free, normal), normal
		end,
		rushEnded = function(rush, reason, distance, contact)
			table.insert(
				w.ends,
				{ time = w.time, rush = rush, reason = reason, distance = distance, contact = contact }
			)
		end,
		rushTurned = function(rush, contact)
			table.insert(w.turns, { time = w.time, kind = contact.kind, legs = rush.legs, contact = contact })
		end,
		daze = function(seconds)
			table.insert(w.dazes, { time = w.time, seconds = seconds })
			w.brain:interrupt("Stagger", seconds)
		end,
	}
	w.brain = Brain.new(w.context, Charger)
	w.frames = 0
	-- One server frame: the AI tick when it is due, then the frame pass (D-184), then the body moves.
	function w.step()
		if w.frames % math.round(TICK / FRAME) == 0 then
			w.brain:tick(TICK)
		end
		w.brain:frame()
		if w.moving and w.goal ~= nil then
			local delta = (w.goal - w.position) * Vector3.new(1, 0, 1)
			local reach = (w.speed or 16) * FRAME
			if delta.Magnitude <= reach then
				w.position = Vector3.new(w.goal.X, w.position.Y, w.goal.Z)
			elseif delta.Magnitude > 0 then
				w.position += delta.Unit * reach
			end
			-- It stands on the ground under its root, as a Humanoid steps up a stair it reaches.
			local ground = RushWorld.groundBelow(cast, w.position + Vector3.new(0, 5, 0), 20)
			if ground ~= nil then
				w.position = Vector3.new(w.position.X, ground + HEIGHT, w.position.Z)
			end
		end
		table.insert(w.path, { position = w.position, facing = w.facing })
		w.time += FRAME
		w.frames += 1
	end
	-- Through the launch to the recovery, the daze, or 4 s.
	function w.run()
		local launched = false
		for _ = 1, math.ceil(4 / FRAME) do
			local phase = w.brain:getPhase()
			launched = launched or phase == "Strike"
			if launched and (phase == "Recover" or phase == "Interrupted") then
				break
			end
			w.step()
		end
	end
	return w
end

describe("a Charger meets the world as a body (D-205 to D-209)", function()
	it(
		"a wall ahead: Wall with the snout's stop and where it meets the face, sent there, dazed on the timeline",
		function()
			for _, ahead in { 10, 14 } do
				local wall = plane(Vector3.new(0, 0, -ahead), -FORWARD)
				local w = chargerIn({ FLOOR, wall })
				w.run()
				local ended = w.ends[1]
				expect(ended.reason).toBe("Wall")
				expect(ended.distance).toBeCloseTo(ahead - FRONT, 1e-6)
				expect(ended.contact.point.Z).toBeCloseTo(-ahead, 1e-3)
				expect(ended.contact.normal:Dot(-FORWARD)).toBeCloseTo(1, 1e-6)
				-- The body goes to its stop and no further.
				local origin = ended.rush.origin
				for _, goal in w.goals do
					if goal.time >= ended.time then
						expect((goal.goal - origin):Dot(FORWARD)).toBeLessThanOrEqual(ended.distance + 1e-6)
					end
				end
				-- The line resolves to the face, never past it.
				for _, strike in w.strikes do
					expect(strike.span.to).toBeLessThanOrEqual(ahead + 1e-6)
				end
				-- Dazed once, for slamDazeSeconds, on the tick the timeline brings the snout to the face;
				-- then the rush's end, at the same stop.
				local rush = ended.rush
				local due = rush.startedAt + RushWorld.timeAt(rush.speed, rush.length, CHARGE.strike, ended.distance)
				expect(#w.dazes).toBe(1)
				expect(w.dazes[1].seconds).toBe(WORLD.slamDazeSeconds)
				expect(w.dazes[1].time).toBeGreaterThanOrEqual(due - 1e-9)
				expect(w.dazes[1].time).toBeLessThan(due + FRAME + 1e-9)
				expect(#w.ends).toBe(2)
				expect(w.ends[2].reason).toBe("Interrupted")
				expect(w.ends[2].distance).toBeCloseTo(ended.distance, 1e-6)
			end
		end
	)

	it("a glancing wall bends the rush along it: told once, never a stop, the line along the face", function()
		local wall = angled(30, 9)
		local w = chargerIn({ FLOOR, wall })
		w.run()
		expect(#w.turns).toBe(1)
		expect(w.turns[1].kind).toBe("Glance")
		for _, ended in w.ends do
			expect(ended.reason).toBe("Done")
		end
		local tangent = w.turns[1].legs[2].heading
		local along = false
		for _, strike in w.strikes do
			if math.abs(strike.facing:Dot(tangent) - 1) < 1e-6 then
				along = true
			end
		end
		expect(along).toBe(true)
		-- The body (every corner, as it stood and faced) never stood in the wall.
		local deepest = 0
		for _, sample in w.path do
			for _, corner in corners(sample.position, sample.facing) do
				local offset = (corner - (wall.point :: Vector3)) * Vector3.new(1, 0, 1)
				deepest = math.max(deepest, -offset:Dot(wall.normal :: Vector3))
			end
		end
		expect(deepest).toBeLessThan(0.05)
	end)

	it("a pillar it overlaps by half a stud: a sidestep told once, never a stop", function()
		local side = BODY.size.X / 2
		local shape = box(Vector3.new(side - 0.5, 0, -14), Vector3.new(side + 1.5, 10, -12))
		local w = chargerIn({ FLOOR, shape })
		w.run()
		expect(#w.turns).toBe(1)
		expect(w.turns[1].kind).toBe("Clip")
		for _, ended in w.ends do
			expect(ended.reason).toBe("Done")
		end
	end)

	it("a stair it climbs is no stop", function()
		local stairs = { FLOOR }
		for k = 1, 5 do
			table.insert(stairs, box(Vector3.new(-10, 0, -200), Vector3.new(10, k, -(3 + 3 * k))))
		end
		local w = chargerIn(stairs)
		w.run()
		expect(#w.ends).toBeGreaterThan(0)
		for _, ended in w.ends do
			expect(ended.reason).toBe("Done")
		end
		expect(#w.turns).toBe(0)
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- The numbers (tools/validators/ai.luau)
-- ---------------------------------------------------------------------------------------------

describe("the ai validator checks rushWorld (D-205 to D-209)", function()
	local luau = require("@lune/luau")
	local root = Harness.repoRoot()

	-- The validator over the real ai table with rushWorld changed by `change`.
	local function validate(change: (world: any) -> ()): { string }
		local real = Harness.load("src/shared/data/ai")
		local copy = table.clone(real)
		copy.rushWorld = table.clone(real.rushWorld)
		change(copy.rushWorld)
		local source = Harness.readFile("tools/validators/ai.luau")
		local validator = luau.load(source, {
			debugName = "tools/validators/ai",
			environment = { print = function() end } :: any,
		})()
		return validator({
			load = function(path: string): any
				if path == "src/shared/data/ai" then
					return copy
				end
				return Harness.load(path)
			end,
			listFiles = Harness.listFiles,
			readFile = Harness.readFile,
			repoRoot = root,
		})
	end

	local function names(problems: { string }, needle: string): boolean
		for _, problem in problems do
			if problem:find(needle, 1, true) then
				return true
			end
		end
		return false
	end

	it("passes the real table", function()
		expect(validate(function() end)).toEqual({})
	end)

	it("every number is positive", function()
		expect(names(
			validate(function(world)
				world.slamDazeSeconds = 0
			end),
			"rushWorld.slamDazeSeconds must be positive"
		)).toBe(true)
		expect(names(
			validate(function(world)
				world.fallGravity = nil
			end),
			"rushWorld.fallGravity must be a number"
		)).toBe(true)
	end)

	it("a glance is under 90 degrees; the look ahead holds a sidestep's run; a sidestep fits its run", function()
		expect(names(
			validate(function(world)
				world.glanceDegrees = 90
			end),
			"rushWorld.glanceDegrees must be below 90"
		)).toBe(true)
		expect(names(
			validate(function(world)
				world.lookAheadStuds = world.clipRunStuds - 0.5
			end),
			"rushWorld.lookAheadStuds"
		)).toBe(true)
		expect(names(
			validate(function(world)
				world.clipRunStuds = world.clipStuds
			end),
			"rushWorld.clipRunStuds must be at least clipStuds + clipMarginStuds"
		)).toBe(true)
		expect(names(
			validate(function(world)
				world.maxLegs = 2
			end),
			"rushWorld.maxLegs"
		)).toBe(true)
	end)

	it("the server turns onto a leg as fast as the clients draw it; a daze outlasts a parry's stagger", function()
		expect(names(
			validate(function(world)
				world.turnRate += 1
			end),
			"must equal choreo enemy.rush.turnRate"
		)).toBe(true)
		expect(names(
			validate(function(world)
				world.slamDazeSeconds = 0.5
			end),
			"rushWorld.slamDazeSeconds 0.5 must be at least combat.parryStagger"
		)).toBe(true)
	end)

	it("a step the body climbs is lower than its hip", function()
		expect(names(
			validate(function(world)
				world.riserStuds = 1.6
			end),
			"rushWorld.riserStuds 1.6 must be below rig"
		)).toBe(true)
	end)
end)
