--!strict
local HitSweep = Harness.load("src/server/combat/HitSweep")
local Combat = Harness.load("src/shared/data/combat")
local Rigs = Harness.load("src/shared/data/rigs")
local Horizontal = Harness.load("src/shared/clips/player/OneHandedSword/Horizontal")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")

-- ------------------------------------------------------------------------------------------
-- Pure sampling
-- ------------------------------------------------------------------------------------------

describe("HitSweep.sampleTimes", function()
	it("covers (from, to] at the rate and always ends exactly on `to`", function()
		-- 0.12 s is 7.2 frames: six interior frames (the seventh sits inside half a frame of the end) + the end.
		local times = HitSweep.sampleTimes(0.36, 0.48, 60)
		expect(#times).toBe(7)
		expect(times[#times]).toBe(0.48)
		for index = 2, #times do
			expect(times[index]).toBeGreaterThan(times[index - 1])
		end
		expect(times[1]).toBeCloseTo(0.36 + 1 / 60, 1e-9)
	end)

	it("prepends `from` when asked and yields only it on an empty span", function()
		expect(HitSweep.sampleTimes(1, 1, 60, true)).toEqual({ 1 })
		expect(HitSweep.sampleTimes(1, 0.5, 60)).toEqual({})
		local withFrom = HitSweep.sampleTimes(0, 0.1, 60, true)
		expect(withFrom[1]).toBe(0)
		expect(withFrom[#withFrom]).toBe(0.1)
	end)

	it("never emits two samples closer than a frame to the end", function()
		-- A span that is not a multiple of the step: 0.0333 would land 0.0001 before the end.
		local times = HitSweep.sampleTimes(0, 1 / 30 + 0.0001, 60)
		expect(#times).toBe(2)
	end)
end)

describe("HitSweep.samplePath", function()
	it("samples a window at hitSampleHz from open to close inclusive, monotonic", function()
		local windows = ClipSampler.hitWindows(Horizontal)
		expect(#windows).toBe(1)
		local times = HitSweep.samplePath(Horizontal, windows[1])
		-- open, every step that is more than half a step before close, then close.
		local step = 1 / Combat.hitSampleHz
		local expected = 2
		local k = 1
		while windows[1].open + k * step < windows[1].close - step * 0.5 do
			expected += 1
			k += 1
		end
		expect(#times).toBe(expected)
		expect(expected).toBeGreaterThan(4)
		expect(times[1]).toBe(windows[1].open)
		expect(times[#times]).toBe(windows[1].close)
		for index = 2, #times do
			expect(times[index]).toBeGreaterThan(times[index - 1])
		end
	end)

	it("clamps a window to the clip's duration", function()
		local times = HitSweep.samplePath(Horizontal, { open = 0.9, close = 5 }, 10)
		expect(times[#times]).toBe(Horizontal.duration)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- A placeholder rig built the way RigBuilder does it (Motor6Ds with C0/C1 from rigs.luau)
-- ------------------------------------------------------------------------------------------

local function cframeOf(t)
	return CFrame.new(t.pos[1], t.pos[2], t.pos[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(t.rot[1]), math.rad(t.rot[2]), math.rad(t.rot[3]))
end

-- Builds the PlayerR15 rig as parts and Motor6Ds (unit sizes; the sweep only needs the joints),
-- with a Weapon part carrying TrailStart (guard) and TrailEnd (tip) attachments.
local function buildPlayerRig(rootCFrame: CFrame)
	local rig = Rigs.PlayerR15
	local model = Instance.new("Model")
	model.Name = "Swordsman"
	local parts = {}
	local function part(name)
		local existing = parts[name]
		if existing then
			return existing
		end
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(1, 1, 1)
		p.Parent = model
		parts[name] = p
		return p
	end
	local root = part(rig.rootPart)
	root.CFrame = rootCFrame
	model.PrimaryPart = root
	for _, joint in rig.joints do
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Part0 = part(joint.part0)
		motor.Part1 = part(joint.part1)
		motor.C0 = cframeOf(joint.c0)
		motor.C1 = CFrame.new()
		motor.Parent = motor.Part0
	end
	local weapon = parts.Weapon
	local trailStart = Instance.new("Attachment")
	trailStart.Name = "TrailStart"
	trailStart.CFrame = CFrame.new(0, 0.5, 0)
	trailStart.Parent = weapon
	local trailEnd = Instance.new("Attachment")
	trailEnd.Name = "TrailEnd"
	trailEnd.CFrame = CFrame.new(0, 4.5, 0)
	trailEnd.Parent = weapon
	return model, trailStart, trailEnd
end

describe("HitSweep.bladePath", function()
	it("solves the blade through the rig for every sample and moves it across the Horizontal cut", function()
		local model, trailStart, trailEnd = buildPlayerRig(CFrame.new(0, 3, 0))
		local windows = ClipSampler.hitWindows(Horizontal)
		local times = HitSweep.samplePath(Horizontal, windows[1])
		local samples = HitSweep.bladePath(model, CFrame.new(0, 3, 0), Horizontal, times, trailStart, trailEnd)
		expect(samples).never.toBeNil()
		expect(#samples).toBe(#times)
		for index, sample in samples do
			expect(sample.time).toBe(times[index])
			expect((sample.finish - sample.start).Magnitude).toBeCloseTo(4, 1e-3)
			expect((sample.mid - sample.start:Lerp(sample.finish, 0.5)).Magnitude).toBeCloseTo(0, 1e-6)
		end
		-- A right-to-left cut: the tip travels sideways across the window.
		local first = samples[1].finish
		local last = samples[#samples].finish
		expect((last - first).Magnitude).toBeGreaterThan(1)
	end)

	it("returns nil when an attachment is not under a part of the rig", function()
		local model, trailStart = buildPlayerRig(CFrame.new())
		local loose = Instance.new("Attachment")
		expect(HitSweep.bladePath(model, CFrame.new(), Horizontal, { 0.4 }, trailStart, loose)).toBeNil()
	end)

	it("finds the TrailStart / TrailEnd attachments anywhere under the model", function()
		local model, trailStart, trailEnd = buildPlayerRig(CFrame.new())
		local foundStart, foundEnd = HitSweep.trailAttachments(model)
		expect(foundStart).toBe(trailStart)
		expect(foundEnd).toBe(trailEnd)
		local bare = Instance.new("Model")
		local none, none2 = HitSweep.trailAttachments(bare)
		expect(none).toBeNil()
		expect(none2).toBeNil()
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Casting against a geometric fake engine
-- ------------------------------------------------------------------------------------------
-- The fakes follow the engine's documented rules, so the specs cannot pass on behaviour Studio
-- does not have:
-- - the caster is workspace:Spherecast: the first thing along the direction the swept sphere
--   touches, never a part the sphere already overlaps at the origin;
-- - the broad phase is workspace:GetPartBoundsInRadius: every queryable part whose axis-aligned
--   bounds come within the radius, never one under an excluded Instance;
-- - a part is queryable unless its CanQuery and CanCollide are both off (CanQuery takes effect
--   only on a part that does not collide).

-- A target: a Model with a root Part at `position`. The caster treats it as a sphere of `size`
-- studs (so a spherecast of radius r touches it within r + size); its Part is the cube around
-- that sphere, which is what the overlap test measures.
local function makeTarget(id, position, size)
	local model = Instance.new("Model")
	model.Name = "Target" .. tostring(id)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(position)
	root.Size = Vector3.new(size * 2, size * 2, size * 2)
	root.Parent = model
	model.PrimaryPart = root
	return { id = id, model = model, root = root, position = position, size = size }
end

-- Something that is not a fighter (a pillar, a slab of floor), described the same way.
local function makeObstacle(position, size)
	local part = Instance.new("Part")
	part.Name = "Pillar"
	part.Anchored = true
	part.CFrame = CFrame.new(position)
	part.Size = Vector3.new(size * 2, size * 2, size * 2)
	return { part = part, position = position, size = size }
end

local function moveTarget(target, position)
	target.position = position
	target.root.CFrame = CFrame.new(position)
end

-- Distance from a point to a segment, and how far along the segment (0..1) the closest approach is.
local function segmentDistance(point: Vector3, origin: Vector3, direction: Vector3): (number, number)
	local lengthSquared = direction:Dot(direction)
	if lengthSquared < 1e-12 then
		return (point - origin).Magnitude, 0
	end
	local t = math.clamp((point - origin):Dot(direction) / lengthSquared, 0, 1)
	return (point - (origin + direction * t)).Magnitude, t
end

local function queryable(part)
	return part.CanQuery or part.CanCollide
end

local function isUnder(instance, exclude)
	for _, excluded in exclude do
		if instance == excluded or instance:IsDescendantOf(excluded) then
			return true
		end
	end
	return false
end

-- Half size of a part's axis-aligned bounds.
local function boundsHalf(part)
	local cframe = part.CFrame
	local half = part.Size / 2
	local right, up, back = cframe.RightVector, cframe.UpVector, cframe.LookVector
	return Vector3.new(
		math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(back.X) * half.Z,
		math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(back.Y) * half.Z,
		math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(back.Z) * half.Z
	)
end

-- Like workspace:GetPartBoundsInRadius over `parts`.
local function boundsQuery(parts, center, radius, exclude)
	local found = {}
	for _, part in parts do
		if queryable(part) and not isUnder(part, exclude) then
			local half = boundsHalf(part)
			local offset = center - part.CFrame.Position
			local outside = Vector3.new(
				math.max(math.abs(offset.X) - half.X, 0),
				math.max(math.abs(offset.Y) - half.Y, 0),
				math.max(math.abs(offset.Z) - half.Z, 0)
			)
			if outside.Magnitude <= radius then
				table.insert(found, part)
			end
		end
	end
	return found
end

-- A fake engine over targets and obstacles; `extraParts` are more parts the broad phase can see
-- (a swordsman's own body). Counts every cast and every broad-phase query.
local function fakeWorld(targets, obstacles, extraParts)
	local world = { targets = targets, obstacles = obstacles or {}, casts = 0, tinyCasts = 0, overlaps = 0 }
	function world.cast(origin, radius, direction, exclude)
		world.casts += 1
		if direction.Magnitude < 1e-3 then
			world.tinyCasts += 1
		end
		local best, bestAlong = nil, math.huge
		local function consider(instance, position, size)
			if (position - origin).Magnitude <= radius + size then
				return -- the sphere starts inside it: the engine never reports it
			end
			local distance, along = segmentDistance(position, origin, direction)
			if distance <= radius + size and along < bestAlong then
				best = { Instance = instance, Position = position }
				bestAlong = along
			end
		end
		for _, target in targets do
			if not isUnder(target.root, exclude) and queryable(target.root) then
				consider(target.root, target.position, target.size)
			end
		end
		for _, obstacle in world.obstacles do
			if not isUnder(obstacle.part, exclude) and queryable(obstacle.part) then
				consider(obstacle.part, obstacle.position, obstacle.size)
			end
		end
		return best
	end
	function world.overlap(center, radius, exclude)
		world.overlaps += 1
		world.lastExclude = exclude
		local parts = {}
		for _, target in targets do
			table.insert(parts, target.root)
		end
		for _, obstacle in world.obstacles do
			table.insert(parts, obstacle.part)
		end
		for _, part in extraParts or {} do
			table.insert(parts, part)
		end
		return boundsQuery(parts, center, radius, exclude)
	end
	function world.resolve(instance)
		for _, target in targets do
			if instance == target.root or instance:IsDescendantOf(target.model) then
				return target.id, target.model
			end
		end
		return nil, nil
	end
	function world.options(extra)
		local options = { exclude = {}, resolve = world.resolve, cast = world.cast, overlap = world.overlap }
		for key, value in extra or {} do
			options[key] = value
		end
		return options
	end
	return world
end

-- A broad phase that finds nothing: the engine's casts alone.
local function noOverlap()
	return {}
end

-- A blade sample with its guard at `start` and its tip at `finish`.
local function bladeSample(time, start, finish)
	return { time = time, start = start, finish = finish, mid = start:Lerp(finish, 0.5) }
end

describe("HitSweep.segmentBoxDistance", function()
	-- Distance from a point to a box, the slow way.
	local function pointBoxDistance(point, cframe, size)
		local localPoint = cframe:PointToObjectSpace(point)
		local half = size / 2
		return Vector3.new(
			math.max(math.abs(localPoint.X) - half.X, 0),
			math.max(math.abs(localPoint.Y) - half.Y, 0),
			math.max(math.abs(localPoint.Z) - half.Z, 0)
		).Magnitude
	end

	it("is zero through the box, with the contact on the blade inside it", function()
		local box = CFrame.new(0, 2, -5)
		local distance, contact =
			HitSweep.segmentBoxDistance(Vector3.new(-4, 2, -5), Vector3.new(4, 2.5, -5), box, Vector3.new(2, 2, 2))
		expect(distance).toBe(0)
		expect(pointBoxDistance(contact, box, Vector3.new(2, 2, 2))).toBe(0)
		expect(math.abs(contact.Z + 5)).toBeLessThan(1e-5)
	end)

	it("measures a segment beside a face, a point off a corner and a turned box", function()
		local size = Vector3.new(2, 2, 2)
		-- Parallel to the +X face, 0.5 out.
		local distance, contact =
			HitSweep.segmentBoxDistance(Vector3.new(1.5, -3, 0), Vector3.new(1.5, 3, 0), CFrame.new(), size)
		-- (Vector3 and CFrame hold 32-bit floats.)
		expect(distance).toBeCloseTo(0.5, 1e-5)
		expect(contact.X).toBeCloseTo(1, 1e-5)
		-- A point (zero-length segment) off the (+1, +1, +1) corner.
		distance = HitSweep.segmentBoxDistance(Vector3.new(2, 2, 2), Vector3.new(2, 2, 2), CFrame.new(), size)
		expect(distance).toBeCloseTo(math.sqrt(3), 1e-5)
		-- A box turned 45 degrees about Y reaches sqrt(2) along X.
		local turned = CFrame.Angles(0, math.rad(45), 0)
		distance = HitSweep.segmentBoxDistance(Vector3.new(2, -3, 0), Vector3.new(2, 3, 0), turned, size)
		expect(distance).toBeCloseTo(2 - math.sqrt(2), 1e-5)
	end)

	it("matches a brute-force search on random segments and turned boxes", function()
		local random = Random.new(41)
		local function vector(scale)
			return Vector3.new(
				random:NextNumber(-scale, scale),
				random:NextNumber(-scale, scale),
				random:NextNumber(-scale, scale)
			)
		end
		for _ = 1, 120 do
			local cframe = CFrame.new(vector(3))
				* CFrame.Angles(random:NextNumber(-3, 3), random:NextNumber(-3, 3), random:NextNumber(-3, 3))
			local size = Vector3.new(random:NextNumber(0.2, 5), random:NextNumber(0.2, 5), random:NextNumber(0.2, 5))
			local a, b = vector(6), vector(6)
			local distance, contact = HitSweep.segmentBoxDistance(a, b, cframe, size)
			local brute = math.huge
			local steps = 1000
			for step = 0, steps do
				brute = math.min(brute, pointBoxDistance(a:Lerp(b, step / steps), cframe, size))
			end
			-- Never more than the true minimum, and the sampled minimum can only sit above it.
			expect(distance).toBeLessThan(brute + 1e-4)
			expect(distance).toBeGreaterThan(brute - (b - a).Magnitude / steps - 1e-4)
			-- The contact lies on the box, `distance` from the segment.
			expect(pointBoxDistance(contact, cframe, size)).toBeLessThan(1e-4)
			local toSegment = segmentDistance(contact, a, b - a)
			expect(math.abs(toSegment - distance)).toBeLessThan(1e-4)
		end
	end)
end)

describe("HitSweep.castPath", function()
	it("hits a target the path passes through, once, and leaves far targets alone", function()
		local near = makeTarget(1, Vector3.new(0, 3, -3), 1)
		local far = makeTarget(2, Vector3.new(0, 3, -30), 1)
		local world = fakeWorld({ near, far })
		local path = { Vector3.new(-3, 3, -3), Vector3.new(0, 3, -3), Vector3.new(3, 3, -3) }
		local hits = HitSweep.castPath(path, world.options())
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(1)
		expect(hits[1].position).toEqual(near.position)
	end)

	it("collects several targets along one path and respects the per-window cap", function()
		local targets = {}
		for index = 1, 4 do
			table.insert(targets, makeTarget(index, Vector3.new(index * 3, 3, -3), 1))
		end
		local world = fakeWorld(targets)
		local path = { Vector3.new(-3, 3, -3), Vector3.new(15, 3, -3) }
		local hits = HitSweep.castPath(path, world.options())
		expect(#hits).toBe(4)
		local capped = HitSweep.castPath(path, world.options({ maxTargets = 2 }))
		expect(#capped).toBe(2)
	end)

	it("the cap counts the fighters the window already hit", function()
		local targets = {}
		for index = 1, 4 do
			table.insert(targets, makeTarget(index, Vector3.new(index * 3, 3, -3), 1))
		end
		local world = fakeWorld(targets)
		local path = { Vector3.new(-3, 3, -3), Vector3.new(15, 3, -3) }
		local alreadyHit = { [99] = true }
		local hits = HitSweep.castPath(path, world.options({ maxTargets = 2, alreadyHit = alreadyHit }))
		expect(#hits).toBe(1)
		expect(#HitSweep.castPath(path, world.options({ maxTargets = 2, alreadyHit = alreadyHit }))).toBe(0)
	end)

	it("a cast reaches a new fighter behind the ones the window already hit", function()
		local targets = {}
		for index = 1, 5 do
			table.insert(targets, makeTarget(index, Vector3.new(index * 3, 3, -3), 1))
		end
		local world = fakeWorld(targets)
		-- The first four were hit earlier in the window (an earlier frame or the overlap test); the
		-- cast meets each of them again on its way to the fifth.
		local alreadyHit = { [1] = true, [2] = true, [3] = true, [4] = true }
		local hits = HitSweep.castPath(
			{ Vector3.new(-3, 3, -3), Vector3.new(20, 3, -3) },
			world.options({ maxTargets = 6, alreadyHit = alreadyHit, overlap = noOverlap })
		)
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(5)
	end)

	it("never hits the attacker or anything on the exclude list", function()
		local attacker = makeTarget(7, Vector3.new(0, 3, 0), 1)
		local enemy = makeTarget(1, Vector3.new(0, 3, -4), 1)
		local world = fakeWorld({ attacker, enemy })
		local path = { Vector3.new(0, 3, 3), Vector3.new(0, 3, -5) }
		local hits = HitSweep.castPath(path, world.options({ exclude = { attacker.model } }))
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(1)
	end)

	it("stops at an obstacle that is not a fighter", function()
		local pillar = makeObstacle(Vector3.new(3.5, 3, -3), 1)
		local behind = makeTarget(1, Vector3.new(6, 3, -3), 1)
		local world = fakeWorld({ behind }, { pillar })
		local path = { Vector3.new(0, 3, -3), Vector3.new(8, 3, -3) }
		expect(#HitSweep.castPath(path, world.options())).toBe(0)
		-- Without the pillar the same path reaches the target.
		local open = fakeWorld({ behind })
		expect(#HitSweep.castPath(path, open.options())).toBe(1)
	end)

	it("shares the alreadyHit set across calls so a window hits each fighter once", function()
		local target = makeTarget(1, Vector3.new(0, 3, -3), 1)
		local world = fakeWorld({ target })
		local options = world.options({ alreadyHit = {} })
		expect(#HitSweep.castPath({ Vector3.new(-4, 3, -3), Vector3.new(4, 3, -3) }, options)).toBe(1)
		expect(#HitSweep.castPath({ Vector3.new(-4, 3, -3), Vector3.new(4, 3, -3) }, options)).toBe(0)
	end)

	it("a single point is the overlap test alone, never a near-zero cast", function()
		local target = makeTarget(1, Vector3.new(0, 3, -3), 1)
		local world = fakeWorld({ target })
		local hits = HitSweep.castPath({ Vector3.new(0.5, 3, -3) }, world.options())
		expect(#hits).toBe(1)
		expect(world.casts).toBe(0)
		expect(#HitSweep.castPath({}, world.options())).toBe(0)
		-- A path that rests in place (two equal points) casts nothing either.
		HitSweep.castPath({ Vector3.new(0, 3, -10), Vector3.new(0, 3, -10) }, world.options())
		expect(world.casts).toBe(0)
		expect(world.tinyCasts).toBe(0)
		-- The engine's cast alone would have missed the first target: the sphere starts inside it.
		expect(world.cast(Vector3.new(0.5, 3, -3), Combat.hitSphereRadius, Vector3.zAxis * -0.5, {})).toBeNil()
	end)
end)

describe("HitSweep.castBladePath", function()
	it("a Horizontal swung at a boar-sized target in front of the rig connects", function()
		local rootCFrame = CFrame.new(0, 3, 0) -- faces -Z
		local model, trailStart, trailEnd = buildPlayerRig(rootCFrame)
		local windows = ClipSampler.hitWindows(Horizontal)
		local times = HitSweep.samplePath(Horizontal, windows[1])
		local samples = HitSweep.bladePath(model, rootCFrame, Horizontal, times, trailStart, trailEnd)
		-- Find where the blade actually is and put the target there (the test checks the plumbing,
		-- not the choreography): a target the size of a boar torso at the tip's mid-window position.
		local midSample = samples[math.ceil(#samples / 2)]
		local boar = makeTarget(1, midSample.finish + Vector3.new(0, 0, -0.5), 1.3)
		local world = fakeWorld({ boar })
		local hits = HitSweep.castBladePath(samples, world.options({ exclude = { model } }))
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(1)
		-- Something ten studs behind the swordsman is never touched.
		local behind = makeTarget(2, rootCFrame.Position + Vector3.new(0, 0, 10), 1.3)
		local world2 = fakeWorld({ behind })
		expect(#HitSweep.castBladePath(samples, world2.options({ exclude = { model } }))).toBe(0)
	end)

	it("a blade that starts its window inside a target registers once, through the overlap test", function()
		local target = makeTarget(1, Vector3.new(0, 3, -4), 2)
		local world = fakeWorld({ target })
		-- The blade lies buried in the target at the window's open and stays inside as it moves.
		local samples = {}
		for index = 0, 4 do
			local x = -0.6 + index * 0.3
			table.insert(samples, bladeSample(index / 60, Vector3.new(x, 3, -3), Vector3.new(x, 3.2, -5)))
		end
		local hits = HitSweep.castBladePath(samples, world.options())
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(1)
		-- The contact point is on the blade, inside the target.
		expect((hits[1].position - target.position).Magnitude).toBeLessThan(2 * math.sqrt(3))
		-- The engine's casts alone never see it: every one starts inside.
		local castsOnly = HitSweep.castBladePath(samples, world.options({ overlap = noOverlap }))
		expect(#castsOnly).toBe(0)
		expect(world.casts).toBeGreaterThan(0)
	end)

	it("a target that walks onto a resting blade registers on the next sample", function()
		local target = makeTarget(1, Vector3.new(0, 3, -20), 1)
		local world = fakeWorld({ target })
		local resting = bladeSample(0.4, Vector3.new(0, 3, -2), Vector3.new(0, 3, -5.2))
		local alreadyHit = {}
		-- The window opens with nothing near the blade.
		expect(#HitSweep.castBladePath({ resting }, world.options({ alreadyHit = alreadyHit }))).toBe(0)
		-- The target steps onto the blade while it holds still (the clip's Hold key).
		moveTarget(target, Vector3.new(0.5, 3, -4))
		local still = bladeSample(0.4 + 1 / 60, resting.start, resting.finish)
		local hits =
			HitSweep.castBladePath({ resting, still }, world.options({ alreadyHit = alreadyHit, continued = true }))
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(1)
		-- The step between two equal samples is never cast, and the casts alone would not have seen it.
		expect(world.tinyCasts).toBe(0)
		expect(#HitSweep.castBladePath({ resting, still }, world.options({ overlap = noOverlap, continued = true }))).toBe(
			0
		)
		-- It stays one hit for the rest of the window.
		expect(#HitSweep.castBladePath({ still, still }, world.options({ alreadyHit = alreadyHit, continued = true }))).toBe(
			0
		)
	end)

	it("a continued sweep does not test the sample it continues from again", function()
		local target = makeTarget(1, Vector3.new(0, 3, -4), 1)
		local world = fakeWorld({ target })
		local first = bladeSample(0, Vector3.new(0, 3, -2), Vector3.new(0, 3, -5))
		local second = bladeSample(1 / 60, Vector3.new(0, 30, -2), Vector3.new(0, 30, -5))
		HitSweep.castBladePath({ first, second }, world.options({ continued = true }))
		expect(world.overlaps).toBe(1)
		HitSweep.castBladePath({ first, second }, world.options())
		expect(world.overlaps).toBe(3)
	end)

	it("the overlap test never counts a target the cast already hit", function()
		local target = makeTarget(1, Vector3.new(0, 3, -6), 1)
		local world = fakeWorld({ target })
		-- The midpoint's cast enters the target between the samples; the second sample's blade then
		-- lies inside it.
		local before = bladeSample(0, Vector3.new(-1.6, 3, -2), Vector3.new(1.6, 3, -2))
		local inside = bladeSample(1 / 60, Vector3.new(-1.6, 3, -6), Vector3.new(1.6, 3, -6))
		local alreadyHit = {}
		local hits = HitSweep.castBladePath({ before, inside }, world.options({ alreadyHit = alreadyHit }))
		expect(#hits).toBe(1)
		-- The cast found it first: its position is the cast's, not a point on the blade.
		expect(hits[1].position).toEqual(target.position)
		-- The window keeps it hit: the next frame finds nothing new.
		local after = bladeSample(2 / 60, Vector3.new(-1.6, 3, -7), Vector3.new(1.6, 3, -7))
		expect(#HitSweep.castBladePath({ inside, after }, world.options({ alreadyHit = alreadyHit, continued = true }))).toBe(
			0
		)
	end)

	it("the attacker's own body and weapon never register, even if the broad phase returns them", function()
		local attacker = makeTarget(7, Vector3.new(0, 3, 0), 1)
		local weaponModel = Instance.new("Model")
		weaponModel.Name = "Weapon"
		weaponModel.Parent = attacker.model
		local blade = Instance.new("Part")
		blade.Name = "Weapon"
		blade.CFrame = CFrame.new(0, 3, -2)
		blade.Size = Vector3.new(0.3, 0.1, 3.2)
		blade.Parent = weaponModel
		local world = fakeWorld({ attacker }, {}, { blade })
		-- The blade lies along the attacker's own weapon and through its body.
		local samples = {
			bladeSample(0, Vector3.new(0, 3, 0.5), Vector3.new(0, 3, -3.5)),
			bladeSample(1 / 60, Vector3.new(0.2, 3, 0.5), Vector3.new(0.2, 3, -3.5)),
		}
		local options = world.options({ exclude = { attacker.model } })
		expect(#HitSweep.castBladePath(samples, options)).toBe(0)
		-- The broad phase itself is asked to leave the attacker out.
		expect(table.find(world.lastExclude, attacker.model)).never.toBeNil()
		-- A broad phase that ignores the exclude list still never yields the attacker.
		local careless = function(center, radius)
			return world.overlap(center, radius, {})
		end
		expect(#HitSweep.castBladePath(samples, world.options({ exclude = { attacker.model }, overlap = careless }))).toBe(
			0
		)
	end)

	it("a pillar or the floor the blade is buried in is never a hit and never blocks one", function()
		local pillar = makeObstacle(Vector3.new(0, 3, -4), 1.5)
		local floor = makeObstacle(Vector3.new(0, -2, -4), 2)
		local world = fakeWorld({}, { pillar, floor })
		local buried = {
			bladeSample(0, Vector3.new(0, 3, -3), Vector3.new(0, -0.5, -5)),
			bladeSample(1 / 60, Vector3.new(0.3, 3, -3), Vector3.new(0.3, -0.5, -5)),
		}
		expect(#HitSweep.castBladePath(buried, world.options())).toBe(0)
		expect(world.overlaps).toBeGreaterThan(0)
		-- A fighter the same blade also touches still registers.
		local enemy = makeTarget(1, Vector3.new(0, 2, -6), 1)
		local crowded = fakeWorld({ enemy }, { pillar, floor })
		local hits = HitSweep.castBladePath(buried, crowded.options())
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(1)
	end)

	it("a part with CanQuery and CanCollide off is never a hit; a colliding part always is", function()
		local target = makeTarget(1, Vector3.new(0, 3, -4), 1)
		target.root.CanQuery = false
		target.root.CanCollide = false
		local world = fakeWorld({ target })
		local samples = { bladeSample(0, Vector3.new(0, 3, -3), Vector3.new(0, 3, -5)) }
		expect(#HitSweep.castBladePath(samples, world.options())).toBe(0)
		-- Even a broad phase that returns it (a fake that forgets the flags) does not count it.
		local careless = function()
			return { target.root }
		end
		expect(#HitSweep.castBladePath(samples, world.options({ overlap = careless }))).toBe(0)
		-- CanQuery takes effect only on a part that does not collide: the engine queries a colliding
		-- part whatever its CanQuery says, and so does the overlap test.
		target.root.CanCollide = true
		expect(#HitSweep.castBladePath(samples, world.options({ overlap = careless }))).toBe(1)
	end)

	it("the overlap test reaches exactly the hit radius from a part's box, and lands on the box", function()
		local radius = Combat.hitSphereRadius
		-- A 2-stud box (x -1..1, y 2..4, z -5..-3); the blade runs past its +X face, parallel to it.
		local target = makeTarget(1, Vector3.new(0, 3, -4), 1)
		local world = fakeWorld({ target })
		local function sweepAt(x)
			local blade = { bladeSample(0, Vector3.new(x, 3, -2), Vector3.new(x, 3, -6)) }
			return HitSweep.castBladePath(blade, world.options())
		end
		local hits = sweepAt(1 + radius - 0.05)
		expect(#hits).toBe(1)
		-- The contact is the point of the box nearest the blade: on the +X face, beside the blade.
		expect(hits[1].position.X).toBeCloseTo(1, 1e-4)
		expect(hits[1].position.Y).toBeCloseTo(3, 1e-4)
		expect(hits[1].position.Z).toBeLessThan(-3 + 1e-4)
		expect(hits[1].position.Z).toBeGreaterThan(-5 - 1e-4)
		expect(#sweepAt(1 + radius + 0.05)).toBe(0)
	end)

	it("the broad phase covers the whole blade, guard to tip", function()
		-- Small targets just past the tip and just behind the guard: inside the hit radius of the
		-- blade's ends, far outside it from the blade's middle.
		local nearTip = makeTarget(1, Vector3.new(0, 3, -6.9), 0.3)
		local nearGuard = makeTarget(2, Vector3.new(0, 3, -1.1), 0.3)
		local world = fakeWorld({ nearTip, nearGuard })
		local blade = { bladeSample(0, Vector3.new(0, 3, -2), Vector3.new(0, 3, -6)) }
		expect(#HitSweep.castBladePath(blade, world.options())).toBe(2)
	end)

	it("the overlap test stops at the window's target cap", function()
		local targets = {}
		for index = 1, 5 do
			table.insert(targets, makeTarget(index, Vector3.new(0, 3, -1 - index), 0.3))
		end
		local world = fakeWorld(targets)
		-- One blade lying along all five.
		local blade = { bladeSample(0, Vector3.new(0.5, 3, -1.5), Vector3.new(0.5, 3, -6.5)) }
		expect(#HitSweep.castBladePath(blade, world.options({ maxTargets = 10 }))).toBe(5)
		-- A cap of 3 with one fighter already hit this window leaves room for two.
		local alreadyHit = { [99] = true }
		local hits = HitSweep.castBladePath(blade, world.options({ maxTargets = 3, alreadyHit = alreadyHit }))
		expect(#hits).toBe(2)
		local count = 0
		for _ in alreadyHit do
			count += 1
		end
		expect(count).toBe(3)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Enemy strike shapes
-- ------------------------------------------------------------------------------------------

describe("HitSweep.coneTargets", function()
	local origin = Vector3.new(0, 0, 0)
	local facing = Vector3.new(0, 0, -1)
	local function candidate(id, x, z, radius)
		return { id = id, position = Vector3.new(x, 0, z), radius = radius }
	end

	it("takes targets inside the reach and the arc, drops the rest", function()
		local inside = HitSweep.coneTargets(origin, facing, 6, 60, {
			candidate(1, 0, -4), -- dead ahead
			candidate(2, 1.5, -4), -- 20 degrees off
			candidate(3, 4, -4), -- 45 degrees off: outside a 60-degree cone
			candidate(4, 0, -9), -- too far
			candidate(5, 0, 4), -- behind
		})
		local ids = {}
		for _, c in inside do
			table.insert(ids, c.id)
		end
		expect(ids).toEqual({ 1, 2 })
	end)

	it("a target's radius lets it reach into the cone and the reach", function()
		expect(#HitSweep.coneTargets(origin, facing, 6, 60, { candidate(1, 0, -7, 1.5) })).toBe(1)
		expect(#HitSweep.coneTargets(origin, facing, 6, 60, { candidate(1, 0, -7, 0.5) })).toBe(0)
		expect(#HitSweep.coneTargets(origin, facing, 6, 60, { candidate(1, 4, -4, 1.5) })).toBe(1)
	end)

	it("an arc of 360 is a circle and a target on the origin always counts", function()
		expect(#HitSweep.coneTargets(origin, facing, 6, 360, { candidate(1, 0, 4) })).toBe(1)
		expect(#HitSweep.coneTargets(origin, facing, 6, 10, { candidate(1, 0, 0) })).toBe(1)
	end)

	it("ignores height", function()
		expect(#HitSweep.coneTargets(origin, facing, 6, 60, { { id = 1, position = Vector3.new(0, 50, -4) } })).toBe(1)
	end)
end)

describe("HitSweep.lineTargets", function()
	local origin = Vector3.new(0, 0, 0)
	local facing = Vector3.new(0, 0, -1)
	local function candidate(id, x, z, radius)
		return { id = id, position = Vector3.new(x, 0, z), radius = radius }
	end

	it("takes targets along the line within half the width and the length", function()
		local inside = HitSweep.lineTargets(origin, facing, 14, 4, {
			candidate(1, 0, -10),
			candidate(2, 1.9, -13),
			candidate(3, 3, -5), -- too far to the side
			candidate(4, 0, -16), -- past the end
			candidate(5, 0, 2), -- behind the origin
		})
		local ids = {}
		for _, c in inside do
			table.insert(ids, c.id)
		end
		expect(ids).toEqual({ 1, 2 })
	end)

	it("a target's radius widens the line and extends its ends", function()
		expect(#HitSweep.lineTargets(origin, facing, 14, 4, { candidate(1, 3, -5, 1.2) })).toBe(1)
		expect(#HitSweep.lineTargets(origin, facing, 14, 4, { candidate(1, 0, -15, 1.2) })).toBe(1)
		expect(#HitSweep.lineTargets(origin, facing, 14, 4, { candidate(1, 0, 1, 1.2) })).toBe(1)
	end)

	it("works for any horizontal facing and returns nothing for a vertical one", function()
		local east = Vector3.new(1, 0, 0)
		expect(#HitSweep.lineTargets(origin, east, 14, 4, { candidate(1, 10, 0) })).toBe(1)
		expect(#HitSweep.lineTargets(origin, east, 14, 4, { candidate(1, 0, -10) })).toBe(0)
		expect(#HitSweep.lineTargets(origin, Vector3.new(0, 1, 0), 14, 4, { candidate(1, 0, -5) })).toBe(0)
	end)

	it("bodyRadius is half the root part's widest horizontal side", function()
		local target = makeTarget(1, Vector3.new(), 1.3)
		expect(HitSweep.bodyRadius(target.model)).toBeCloseTo(1.3, 1e-3)
		expect(HitSweep.bodyRadius(Instance.new("Model"))).toBe(0)
	end)
end)
