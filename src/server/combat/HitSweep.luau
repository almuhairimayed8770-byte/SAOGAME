--!strict
--[[
	HitSweep: the server-side weapon sweep (section 6, docs/DECISIONS.md D-010).

	During a damage window the server samples the attack clip at combat.hitSampleHz through the
	same ClipSampler the client animates with, solves the weapon's TrailStart / TrailEnd through
	Pose, and tests the blade against the world two ways:

	- at every sample, an overlap test of the blade itself (the guard-to-tip segment grown by
	  combat.hitSphereRadius): a broad-phase query for nearby parts (workspace:GetPartBoundsInRadius),
	  then the exact distance from the blade to each fighter part's box;
	- between samples, workspace:Spherecast along the path of the blade's midpoint, so a target the
	  blade passes through between two samples still counts.

	Both are needed because a shapecast never reports a part the shape already overlaps where the
	cast starts (the engine documents this for Spherecast, Blockcast and Shapecast): a blade that
	opens its window inside a target, or a target that walks onto a resting blade, is invisible to
	every cast and only the overlap test sees it. Every entity model the blade touches is a hit,
	each once per window; a part that is not a fighter is never a hit, and stops a cast like a
	wall. The Art timeline in CombatService turns hits into damage. Nothing here decides damage.

	Pure pieces (Lune-tested): samplePath / sampleTimes, bladePath (Pose over Lune Instances),
	segmentBoxDistance, castPath and castBladePath with an injectable caster and broad phase, and the
	cone / line tests enemy strikes use. The only engine calls are the defaults: workspace:Spherecast
	and workspace:GetPartBoundsInRadius.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local Combat = require(Shared.data.combat)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Pose = require(Shared.choreo.Pose)

export type Window = { open: number, close: number }

export type BladeSample = {
	time: number, -- clip time
	start: Vector3, -- TrailStart (the guard)
	finish: Vector3, -- TrailEnd (the tip)
	mid: Vector3,
}

export type Hit = { targetId: number, position: Vector3 }

-- A spherecast: (origin, radius, direction, exclude) -> RaycastResult-like ({Instance, Position}) or nil.
-- The default wraps workspace:Spherecast, which never reports a part the sphere already overlaps at
-- `origin`; tests inject a geometric fake that follows the same rule.
export type Caster = (origin: Vector3, radius: number, direction: Vector3, exclude: { Instance }) -> any

-- A broad-phase overlap: (center, radius, exclude) -> every queryable part whose bounds come within
-- `radius` of `center`, none of them under an excluded Instance. It may return more than touches the
-- blade (HitSweep measures each fighter part itself) but never less. The default wraps
-- workspace:GetPartBoundsInRadius (which skips a part whose CanQuery and CanCollide are both off);
-- tests inject a fake.
export type Overlapper = (center: Vector3, radius: number, exclude: { Instance }) -> { BasePart }

export type CastOptions = {
	radius: number?, -- default combat.hitSphereRadius
	exclude: { Instance }, -- the attacker's model (its weapon hangs inside it) and anything else the blade may not hit
	resolve: (instance: Instance) -> (number?, Model?), -- hit part -> (entity id, entity model)
	maxTargets: number?, -- default combat.maxTargetsPerWindow, counting the window's earlier hits
	alreadyHit: { [number]: boolean }?, -- entity ids this window already hit (mutated)
	cast: Caster?, -- default workspace:Spherecast
	overlap: Overlapper?, -- default workspace:GetPartBoundsInRadius
	-- castBladePath: samples[1] is the previous call's last sample, already overlap-tested; the
	-- sweep starts from it without testing it again.
	continued: boolean?,
}

export type Candidate = { id: number, position: Vector3, radius: number? }

local HitSweep = {}

-- A cast shorter than this is a point: it is not made, and the overlap test at its end stands in
-- for it (the engine rejects a zero direction, and a near-zero one sees nothing it starts inside).
local MIN_CAST_LENGTH = 1e-6

local defaultParams: RaycastParams? = nil
local defaultOverlapParams: OverlapParams? = nil

local function castParams(): RaycastParams
	local existing = defaultParams
	if existing ~= nil then
		return existing
	end
	local created = RaycastParams.new()
	created.FilterType = Enum.RaycastFilterType.Exclude
	defaultParams = created
	return created
end

local function overlapParams(): OverlapParams
	local existing = defaultOverlapParams
	if existing ~= nil then
		return existing
	end
	local created = OverlapParams.new()
	created.FilterType = Enum.RaycastFilterType.Exclude
	defaultOverlapParams = created
	return created
end

local function defaultCaster(origin: Vector3, radius: number, direction: Vector3, exclude: { Instance }): any
	local params = castParams()
	params.FilterDescendantsInstances = exclude
	return workspace:Spherecast(origin, radius, direction, params)
end

local function defaultOverlap(center: Vector3, radius: number, exclude: { Instance }): { BasePart }
	local params = overlapParams()
	params.FilterDescendantsInstances = exclude
	return workspace:GetPartBoundsInRadius(center, radius, params)
end

--- Sample times covering (fromTime, toTime] at `hz`, plus `fromTime` itself when `includeFrom` is set.
--- The last sample is always exactly `toTime` (a sample inside half a step of it is folded into it);
--- an empty or inverted span yields {} (or {fromTime}).
function HitSweep.sampleTimes(fromTime: number, toTime: number, hz: number, includeFrom: boolean?): { number }
	local times = {}
	if includeFrom then
		table.insert(times, fromTime)
	end
	if toTime <= fromTime then
		return times
	end
	local step = 1 / math.max(hz, 1)
	local t = fromTime + step
	while t < toTime - step * 0.5 do
		table.insert(times, t)
		t += step
	end
	table.insert(times, toTime)
	return times
end

--- Sample times of a whole damage window at `hz`: window.open, every 1/hz after it, and window.close.
function HitSweep.samplePath(clip: Types.ClipDef, window: Window, hz: number?): { number }
	local rate = hz or Combat.hitSampleHz
	local open = math.clamp(window.open, 0, clip.duration)
	local close = math.clamp(window.close, 0, clip.duration)
	return HitSweep.sampleTimes(open, close, rate, true)
end

--- Where the blade is at each clip time: TrailStart, TrailEnd and their midpoint, solved through Pose
--- from `rootCFrame` with the clip's joint offsets. Returns nil when an attachment is not on the rig.
function HitSweep.bladePath(
	model: Model,
	rootCFrame: CFrame,
	clip: Types.ClipDef,
	times: { number },
	trailStart: Attachment,
	trailEnd: Attachment
): { BladeSample }?
	local startPart = trailStart.Parent
	local endPart = trailEnd.Parent
	if startPart == nil or endPart == nil or not startPart:IsA("BasePart") or not endPart:IsA("BasePart") then
		return nil
	end
	local samples: { BladeSample } = {}
	for _, time in times do
		local offsets = ClipSampler.sample(clip, time)
		local solved = Pose.solve(model, rootCFrame, offsets)
		local startCFrame = solved[startPart.Name]
		local endCFrame = solved[endPart.Name]
		if startCFrame == nil or endCFrame == nil then
			return nil
		end
		local startPosition = (startCFrame * trailStart.CFrame).Position
		local endPosition = (endCFrame * trailEnd.CFrame).Position
		table.insert(samples, {
			time = time,
			start = startPosition,
			finish = endPosition,
			mid = startPosition:Lerp(endPosition, 0.5),
		})
	end
	return samples
end

-- The cut points of segmentBoxDistance, reused across calls (it never yields).
local cutScratch: { number } = {}

-- Where the segment (origin o, slope d along one box axis) crosses that axis's two slab faces.
local function addCuts(cuts: { number }, o: number, d: number, h: number)
	if d == 0 then
		return
	end
	local low = (-h - o) / d
	local high = (h - o) / d
	if low > 0 and low < 1 then
		table.insert(cuts, low)
	end
	if high > 0 and high < 1 then
		table.insert(cuts, high)
	end
end

-- Adds one axis's share of the squared distance's derivative on a piece where the coordinate at
-- `t` sits outside its slab (inside, the axis adds nothing).
local function accumulate(
	numerator: number,
	denominator: number,
	o: number,
	d: number,
	h: number,
	t: number
): (number, number)
	local value = o + d * t
	if value > h then
		return numerator + (o - h) * d, denominator + d * d
	elseif value < -h then
		return numerator + (o + h) * d, denominator + d * d
	end
	return numerator, denominator
end

-- How far a coordinate sits outside its slab, squared.
local function outsideSquared(value: number, h: number): number
	local outside = math.abs(value) - h
	return if outside > 0 then outside * outside else 0
end

--- Closest approach of the segment a -> b to a box (a part's CFrame and Size): the distance, 0 when
--- they intersect, and the point of the box nearest the segment (a point of the segment inside the
--- box when they intersect). Every part is measured as its box, which holds its real shape, so a
--- ball, a wedge or a mesh is never missed and is at most a box corner generous.
function HitSweep.segmentBoxDistance(a: Vector3, b: Vector3, boxCFrame: CFrame, boxSize: Vector3): (number, Vector3)
	local localA = boxCFrame:PointToObjectSpace(a)
	local localB = boxCFrame:PointToObjectSpace(b)
	local ox, oy, oz = localA.X, localA.Y, localA.Z
	local dx, dy, dz = localB.X - ox, localB.Y - oy, localB.Z - oz
	local hx, hy, hz = boxSize.X * 0.5, boxSize.Y * 0.5, boxSize.Z * 0.5

	-- The squared distance from the point at t to the box is convex and piecewise quadratic in t:
	-- between the points where the segment crosses a slab face, every axis stays below, inside or
	-- above its slab. Cut there and take each piece's exact minimum.
	local cuts = cutScratch
	table.clear(cuts)
	cuts[1] = 0
	cuts[2] = 1
	addCuts(cuts, ox, dx, hx)
	addCuts(cuts, oy, dy, hy)
	addCuts(cuts, oz, dz, hz)
	table.sort(cuts)
	local bestT, bestSquared = 0, math.huge
	for index = 1, #cuts - 1 do
		local from, to = cuts[index], cuts[index + 1]
		local middle = (from + to) * 0.5
		local numerator, denominator = 0, 0
		numerator, denominator = accumulate(numerator, denominator, ox, dx, hx, middle)
		numerator, denominator = accumulate(numerator, denominator, oy, dy, hy, middle)
		numerator, denominator = accumulate(numerator, denominator, oz, dz, hz, middle)
		local t = if denominator > 0 then math.clamp(-numerator / denominator, from, to) else middle
		local squared = outsideSquared(ox + dx * t, hx)
			+ outsideSquared(oy + dy * t, hy)
			+ outsideSquared(oz + dz * t, hz)
		if squared < bestSquared then
			bestSquared = squared
			bestT = t
		end
	end
	local onBox = Vector3.new(
		math.clamp(ox + dx * bestT, -hx, hx),
		math.clamp(oy + dy * bestT, -hy, hy),
		math.clamp(oz + dz * bestT, -hz, hz)
	)
	local contact: Vector3 = boxCFrame:PointToWorldSpace(onBox)
	return math.sqrt(bestSquared), contact
end

-- Distance from a point to the segment a -> b.
local function pointSegmentDistance(point: Vector3, a: Vector3, b: Vector3): number
	local direction = b - a
	local length = direction.Magnitude
	if length < 1e-6 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(direction) / (length * length), 0, 1)
	return (point - (a + direction * t)).Magnitude
end

-- The engine's query rule: spatial queries skip a part only when both CanQuery and CanCollide are
-- off (CanQuery takes effect only on a part that does not collide).
local function isQueryable(part: BasePart): boolean
	return part.CanQuery or part.CanCollide
end

local function isExcluded(part: Instance, model: Model, exclude: { Instance }): boolean
	for _, excluded in exclude do
		if excluded == model or part == excluded or part:IsDescendantOf(excluded) then
			return true
		end
	end
	return false
end

local function countOf(set: { [number]: boolean }): number
	local count = 0
	for _ in set do
		count += 1
	end
	return count
end

-- How many more fighters this window may hit: the cap minus the ones it already hit.
local function budgetOf(options: CastOptions, alreadyHit: { [number]: boolean }): number
	return (options.maxTargets or Combat.maxTargetsPerWindow) - countOf(alreadyHit)
end

-- The overlap test: every fighter the blade (segment start -> finish grown by `radius`) touches
-- right now. The broad phase gathers nearby parts; only fighter parts not hit yet this window are
-- measured, so the floor, a pillar or the attacker's own body is never a hit, and nothing blocks.
local function overlapBlade(
	start: Vector3,
	finish: Vector3,
	radius: number,
	options: CastOptions,
	alreadyHit: { [number]: boolean },
	hits: { Hit },
	budget: number,
	overlap: Overlapper
)
	if #hits >= budget then
		return
	end
	local center = start:Lerp(finish, 0.5)
	local reach = (finish - start).Magnitude * 0.5 + radius
	for _, part in overlap(center, reach, options.exclude) do
		if not part:IsA("BasePart") or not isQueryable(part) then
			continue
		end
		local targetId, targetModel = options.resolve(part)
		if targetId == nil or targetModel == nil or alreadyHit[targetId] then
			continue
		end
		if isExcluded(part, targetModel, options.exclude) then
			continue
		end
		local cframe = part.CFrame
		local size = part.Size
		-- Cheap reject: the part's bounding sphere does not reach the blade.
		if pointSegmentDistance(cframe.Position, start, finish) > radius + size.Magnitude * 0.5 then
			continue
		end
		local distance, contact = HitSweep.segmentBoxDistance(start, finish, cframe, size)
		if distance <= radius then
			alreadyHit[targetId] = true
			table.insert(hits, { targetId = targetId, position = contact })
			if #hits >= budget then
				return
			end
		end
	end
end

-- Casts one segment repeatedly, excluding every entity it already touched, until nothing new is
-- hit, an obstacle stops the blade, or the target cap is reached. Like the engine's cast, it sees
-- nothing the sphere overlaps at `origin`; the overlap test covers that.
local function castSegment(
	origin: Vector3,
	direction: Vector3,
	radius: number,
	exclude: { Instance },
	options: CastOptions,
	alreadyHit: { [number]: boolean },
	hits: { Hit },
	budget: number,
	cast: Caster
)
	if direction.Magnitude < MIN_CAST_LENGTH then
		return
	end
	-- Each cast either ends the segment, lands a new fighter, or meets a fighter the window already
	-- hit (by an earlier frame or by the overlap test) and excludes it; each of those can come up
	-- once, so this bounds the loop even against a caster that ignores the exclude list.
	local safety = countOf(alreadyHit) + math.max(budget - #hits, 0) + 1
	while #hits < budget and safety > 0 do
		safety -= 1
		local result = cast(origin, radius, direction, exclude)
		if result == nil then
			return
		end
		local targetId, targetModel = options.resolve(result.Instance)
		if targetId == nil or targetModel == nil then
			-- Something that is not a fighter (a pillar, the floor): the blade stops here.
			return
		end
		if not alreadyHit[targetId] then
			alreadyHit[targetId] = true
			table.insert(hits, { targetId = targetId, position = result.Position })
		end
		-- Already-hit fighters are excluded from every later cast so one target never blocks another.
		if table.find(exclude, targetModel) == nil then
			table.insert(exclude, targetModel)
		end
	end
end

--- A sphere of the hit radius moved along a chain of points: every fighter it overlaps at the first
--- point (the overlap test) or meets on the way (spherecasts between consecutive points), each once.
--- Zero-length steps are not cast; a chain of one point is only the overlap test.
function HitSweep.castPath(points: { Vector3 }, options: CastOptions): { Hit }
	local hits: { Hit } = {}
	if #points == 0 then
		return hits
	end
	local radius = options.radius or Combat.hitSphereRadius
	local alreadyHit = options.alreadyHit or {}
	local budget = budgetOf(options, alreadyHit)
	local cast = options.cast or defaultCaster
	local overlap = options.overlap or defaultOverlap
	local exclude = table.clone(options.exclude)

	overlapBlade(points[1], points[1], radius, options, alreadyHit, hits, budget, overlap)
	for index = 2, #points do
		if #hits >= budget then
			break
		end
		local origin = points[index - 1]
		castSegment(origin, points[index] - origin, radius, exclude, options, alreadyHit, hits, budget, cast)
	end
	return hits
end

--- Full sweep of a blade path, in time order: at every sample the whole blade (guard to tip) is
--- tested for overlap, so a blade that starts the window inside a target, a target that walks onto
--- a resting blade and a thrust along the blade all register; between samples the blade's midpoint
--- is spherecast, so a cut that crosses a target between two samples registers too. Each fighter
--- counts once per window (`alreadyHit`), up to the window's target cap.
function HitSweep.castBladePath(samples: { BladeSample }, options: CastOptions): { Hit }
	local hits: { Hit } = {}
	if #samples == 0 then
		return hits
	end
	local radius = options.radius or Combat.hitSphereRadius
	local alreadyHit = options.alreadyHit or {}
	local budget = budgetOf(options, alreadyHit)
	local cast = options.cast or defaultCaster
	local overlap = options.overlap or defaultOverlap
	local exclude = table.clone(options.exclude)

	for index, sample in samples do
		if #hits >= budget then
			break
		end
		if index > 1 then
			local origin = samples[index - 1].mid
			castSegment(origin, sample.mid - origin, radius, exclude, options, alreadyHit, hits, budget, cast)
		end
		if index > 1 or not options.continued then
			overlapBlade(sample.start, sample.finish, radius, options, alreadyHit, hits, budget, overlap)
		end
	end
	return hits
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function forwardOf(facing: Vector3): Vector3?
	local horizontal = flat(facing)
	if horizontal.Magnitude < 1e-6 then
		return nil
	end
	return horizontal.Unit
end

--- Candidates inside a horizontal cone: within `reach` (plus their radius) of `origin` and within
--- `arcDegrees` / 2 of `facing`. An arc of 360 is a circle.
function HitSweep.coneTargets(
	origin: Vector3,
	facing: Vector3,
	reach: number,
	arcDegrees: number,
	candidates: { Candidate }
): { Candidate }
	local forward = forwardOf(facing)
	local halfAngle = math.clamp(arcDegrees, 0, 360) / 2
	local full = arcDegrees >= 360
	local inside: { Candidate } = {}
	for _, candidate in candidates do
		local offset = flat(candidate.position - origin)
		local radius = candidate.radius or 0
		local distance = offset.Magnitude
		if distance - radius > reach then
			continue
		end
		if full or distance < 1e-6 then
			table.insert(inside, candidate)
			continue
		end
		if forward == nil then
			continue
		end
		-- The angular half-width of the target grows with its radius, so a wide body on the cone's edge counts.
		local cosine = forward:Dot(offset.Unit)
		local angularSlack = if radius > 0 and distance > radius then math.asin(math.min(radius / distance, 1)) else 0
		local effectiveLimit = math.cos(math.min(math.rad(halfAngle) + angularSlack, math.pi))
		if cosine >= effectiveLimit - 1e-6 then
			table.insert(inside, candidate)
		end
	end
	return inside
end

--- Candidates inside a horizontal line strike: from `origin` along `facing` for `length`, `width` wide,
--- each target expanded by its radius.
function HitSweep.lineTargets(
	origin: Vector3,
	facing: Vector3,
	length: number,
	width: number,
	candidates: { Candidate }
): { Candidate }
	local forward = forwardOf(facing)
	local inside: { Candidate } = {}
	if forward == nil then
		return inside
	end
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local halfWidth = width / 2
	for _, candidate in candidates do
		local offset = flat(candidate.position - origin)
		local radius = candidate.radius or 0
		local along = offset:Dot(forward)
		local across = math.abs(offset:Dot(right))
		if along >= -radius and along <= length + radius and across <= halfWidth + radius then
			table.insert(inside, candidate)
		end
	end
	return inside
end

--- Horizontal half-extent of a model's root part (how far its body reaches from its center).
function HitSweep.bodyRadius(model: Model): number
	local root = model.PrimaryPart
	if root == nil then
		return 0
	end
	local size = root.Size
	return math.max(size.X, size.Z) / 2
end

--- The TrailStart / TrailEnd attachments of a fighter's weapon (anywhere under the model), or nil.
function HitSweep.trailAttachments(model: Model): (Attachment?, Attachment?)
	local startAttachment = model:FindFirstChild("TrailStart", true)
	local endAttachment = model:FindFirstChild("TrailEnd", true)
	if startAttachment ~= nil and not startAttachment:IsA("Attachment") then
		startAttachment = nil
	end
	if endAttachment ~= nil and not endAttachment:IsA("Attachment") then
		endAttachment = nil
	end
	return startAttachment :: Attachment?, endAttachment :: Attachment?
end

return HitSweep
