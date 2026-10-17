--!strict
--[[
	HitSweep: the server-side weapon sweep (section 6, docs/DECISIONS.md D-010).

	During a damage window the server samples the attack clip at combat.hitSampleHz through the
	same ClipSampler the client animates with, solves the weapon's TrailStart / TrailEnd through
	Pose, and runs workspace:Spherecast along the blade's path between consecutive samples. Every
	entity model the spheres touch is a hit; the Art timeline in CombatService turns hits into
	damage. Nothing here decides damage.

	Pure pieces (Lune-tested): samplePath / sampleTimes, bladePath (Pose over Lune Instances),
	castPath with an injectable caster, and the cone / line tests enemy strikes use. The only
	engine call is the default caster, workspace:Spherecast.
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
-- The default wraps workspace:Spherecast; tests inject a geometric fake.
export type Caster = (origin: Vector3, radius: number, direction: Vector3, exclude: { Instance }) -> any

export type CastOptions = {
	radius: number?, -- default combat.hitSphereRadius
	exclude: { Instance }, -- the attacker's model (and anything else the blade may not hit)
	resolve: (instance: Instance) -> (number?, Model?), -- hit part -> (entity id, entity model)
	maxTargets: number?, -- default combat.maxTargetsPerWindow
	alreadyHit: { [number]: boolean }?, -- entity ids this window already hit (mutated)
	cast: Caster?, -- default workspace:Spherecast
}

export type Candidate = { id: number, position: Vector3, radius: number? }

local HitSweep = {}

local defaultParams: RaycastParams? = nil

local function defaultCaster(origin: Vector3, radius: number, direction: Vector3, exclude: { Instance }): any
	local params = defaultParams
	if params == nil then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		defaultParams = params
	end
	params.FilterDescendantsInstances = exclude
	return workspace:Spherecast(origin, radius, direction, params)
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

-- Casts one segment repeatedly, excluding every entity it already touched, until nothing new is
-- hit, an obstacle stops the blade, or the target cap is reached.
local function castSegment(
	origin: Vector3,
	direction: Vector3,
	radius: number,
	exclude: { Instance },
	options: CastOptions,
	alreadyHit: { [number]: boolean },
	hits: { Hit },
	maxTargets: number,
	cast: Caster
)
	local safety = maxTargets + 1
	while #hits < maxTargets and safety > 0 do
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

--- Spherecasts along a chain of points (consecutive midpoints of the blade) and returns every
--- fighter touched, each once. Casts with zero length are skipped; a point list of one still casts a
--- zero-length probe so a blade resting on a target at the window's open counts.
function HitSweep.castPath(points: { Vector3 }, options: CastOptions): { Hit }
	local hits: { Hit } = {}
	if #points == 0 then
		return hits
	end
	local radius = options.radius or Combat.hitSphereRadius
	local maxTargets = options.maxTargets or Combat.maxTargetsPerWindow
	local alreadyHit = options.alreadyHit or {}
	local cast = options.cast or defaultCaster
	local exclude = table.clone(options.exclude)

	if #points == 1 then
		-- A probe of near-zero length still detects an overlapping target.
		castSegment(points[1], Vector3.yAxis * 1e-6, radius, exclude, options, alreadyHit, hits, maxTargets, cast)
		return hits
	end
	for index = 2, #points do
		local origin = points[index - 1]
		local direction = points[index] - origin
		if direction.Magnitude < 1e-6 then
			direction = Vector3.yAxis * 1e-6
		end
		castSegment(origin, direction, radius, exclude, options, alreadyHit, hits, maxTargets, cast)
		if #hits >= maxTargets then
			break
		end
	end
	return hits
end

--- Full sweep of a blade path: midpoint chain plus the blade line itself at every sample, so a
--- short cut across a wide target and a thrust along the blade both register.
function HitSweep.castBladePath(samples: { BladeSample }, options: CastOptions): { Hit }
	local hits: { Hit } = {}
	if #samples == 0 then
		return hits
	end
	local alreadyHit = options.alreadyHit or {}
	local shared: CastOptions = {
		radius = options.radius,
		exclude = options.exclude,
		resolve = options.resolve,
		maxTargets = options.maxTargets,
		alreadyHit = alreadyHit,
		cast = options.cast,
	}
	local mids = {}
	for _, sample in samples do
		table.insert(mids, sample.mid)
	end
	for _, hit in HitSweep.castPath(mids, shared) do
		table.insert(hits, hit)
	end
	local maxTargets = options.maxTargets or Combat.maxTargetsPerWindow
	for _, sample in samples do
		if #hits >= maxTargets then
			break
		end
		for _, hit in HitSweep.castPath({ sample.start, sample.finish }, shared) do
			table.insert(hits, hit)
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
