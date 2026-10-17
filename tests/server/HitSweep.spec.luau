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
-- Casting with a geometric fake caster: spheres of `radius` around targets' centers
-- ------------------------------------------------------------------------------------------

-- A target: a Model with a root Part at `position`; the fake caster treats it as a sphere of
-- `size` studs (so a spherecast of radius r hits when the segment passes within r + size).
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

-- Distance from a point to a segment, and how far along the segment (0..1) the closest approach is.
local function segmentDistance(point: Vector3, origin: Vector3, direction: Vector3): (number, number)
	local lengthSquared = direction:Dot(direction)
	if lengthSquared < 1e-12 then
		return (point - origin).Magnitude, 0
	end
	local t = math.clamp((point - origin):Dot(direction) / lengthSquared, 0, 1)
	return (point - (origin + direction * t)).Magnitude, t
end

-- Like workspace:Spherecast: the first thing along the direction whose sphere the swept sphere touches.
local function fakeWorld(targets, obstacles)
	local world = { targets = targets, obstacles = obstacles or {}, casts = 0 }
	function world.cast(origin, radius, direction, exclude)
		world.casts += 1
		local best, bestAlong = nil, math.huge
		for _, target in targets do
			if table.find(exclude, target.model) == nil then
				local distance, along = segmentDistance(target.position, origin, direction)
				if distance <= radius + target.size and along < bestAlong then
					best = { Instance = target.root, Position = target.position }
					bestAlong = along
				end
			end
		end
		for _, obstacle in world.obstacles do
			local distance, along = segmentDistance(obstacle.position, origin, direction)
			if distance <= radius + obstacle.size and along < bestAlong then
				best = { Instance = obstacle.part, Position = obstacle.position }
				bestAlong = along
			end
		end
		return best
	end
	function world.resolve(instance)
		for _, target in targets do
			if target.root == instance then
				return target.id, target.model
			end
		end
		return nil, nil
	end
	return world
end

describe("HitSweep.castPath", function()
	it("hits a target the path passes through, once, and leaves far targets alone", function()
		local near = makeTarget(1, Vector3.new(0, 3, -3), 1)
		local far = makeTarget(2, Vector3.new(0, 3, -30), 1)
		local world = fakeWorld({ near, far })
		local path = { Vector3.new(-3, 3, -3), Vector3.new(0, 3, -3), Vector3.new(3, 3, -3) }
		local hits = HitSweep.castPath(path, { exclude = {}, resolve = world.resolve, cast = world.cast })
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
		local path = { Vector3.new(0, 3, -3), Vector3.new(15, 3, -3) }
		local hits = HitSweep.castPath(path, { exclude = {}, resolve = world.resolve, cast = world.cast })
		expect(#hits).toBe(4)
		local capped =
			HitSweep.castPath(path, { exclude = {}, resolve = world.resolve, cast = world.cast, maxTargets = 2 })
		expect(#capped).toBe(2)
	end)

	it("never hits the attacker or anything on the exclude list", function()
		local attacker = makeTarget(7, Vector3.new(0, 3, 0), 1)
		local enemy = makeTarget(1, Vector3.new(0, 3, -3), 1)
		local world = fakeWorld({ attacker, enemy })
		local path = { Vector3.new(0, 3, 1), Vector3.new(0, 3, -4) }
		local hits =
			HitSweep.castPath(path, { exclude = { attacker.model }, resolve = world.resolve, cast = world.cast })
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(1)
	end)

	it("stops at an obstacle that is not a fighter", function()
		local pillar = Instance.new("Part")
		local behind = makeTarget(1, Vector3.new(6, 3, -3), 1)
		local world = fakeWorld({ behind }, { { part = pillar, position = Vector3.new(2, 3, -3), size = 1 } })
		local path = { Vector3.new(0, 3, -3), Vector3.new(8, 3, -3) }
		local hits = HitSweep.castPath(path, { exclude = {}, resolve = world.resolve, cast = world.cast })
		expect(#hits).toBe(0)
	end)

	it("shares the alreadyHit set across calls so a window hits each fighter once", function()
		local target = makeTarget(1, Vector3.new(0, 3, -3), 1)
		local world = fakeWorld({ target })
		local alreadyHit = {}
		local options = { exclude = {}, resolve = world.resolve, cast = world.cast, alreadyHit = alreadyHit }
		expect(#HitSweep.castPath({ Vector3.new(-2, 3, -3), Vector3.new(2, 3, -3) }, options)).toBe(1)
		expect(#HitSweep.castPath({ Vector3.new(-2, 3, -3), Vector3.new(2, 3, -3) }, options)).toBe(0)
	end)

	it("a single point still probes for an overlapping target", function()
		local target = makeTarget(1, Vector3.new(0, 3, -3), 1)
		local world = fakeWorld({ target })
		local hits = HitSweep.castPath(
			{ Vector3.new(0.5, 3, -3) },
			{ exclude = {}, resolve = world.resolve, cast = world.cast }
		)
		expect(#hits).toBe(1)
		expect(#HitSweep.castPath({}, { exclude = {}, resolve = world.resolve, cast = world.cast })).toBe(0)
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
		local hits =
			HitSweep.castBladePath(samples, { exclude = { model }, resolve = world.resolve, cast = world.cast })
		expect(#hits).toBe(1)
		expect(hits[1].targetId).toBe(1)
		-- Something ten studs behind the swordsman is never touched.
		local behind = makeTarget(2, rootCFrame.Position + Vector3.new(0, 0, 10), 1.3)
		local world2 = fakeWorld({ behind })
		expect(#HitSweep.castBladePath(samples, { exclude = { model }, resolve = world2.resolve, cast = world2.cast })).toBe(
			0
		)
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
