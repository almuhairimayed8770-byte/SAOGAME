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

	The sweep follows the blade's arc, not the frame chords (followArc). A snap is expo-out over 2 to
	4 frames (section 10), so one 60 Hz step can carry the blade through most of its cut, and the
	straight line between two frame samples cuts the corner of that arc: a target inside the arc but
	off the chord is never touched. Between consecutive samples followArc inserts clip-time
	sub-samples, solved through the same Pose, until neither end of the blade moves more than
	combat.sweepMaxTipStep between two of them, spending at most combat.sweepMaxSubdivisions per
	frame on the intervals where the blade moves fastest. A blade that moves less than the step adds
	nothing. Each sub-sample is an ordinary sample to castBladePath: overlap-tested, its midpoint
	cast to the next one, its hits counted against the same window set. Where the cap runs out
	first and an end of the blade still moves more than the step between two samples, castBladePath
	also casts that end's own chord: the overlap tests no longer close the gap there, and the
	midpoint's cast passes half a blade inside the tip's arc.

	The body moves between server frames (the clip's root motion, as the replicated root reports
	it), and the root is never frozen during a window. A sample keeps the root it was solved from,
	and the roots of the samples after the previous frame's last are spread in clip time between
	that sample's root and the live one (bladePath's `from`, followArc's sub-samples), so a frame
	that sweeps several sample times carries the body's travel across them as it happened. A root
	that went farther than a body can travel in that time (jumped: a teleport, a snap back) is not
	followed: the caller starts a new chain at the live root, with no sample, sub-sample or cast on
	the jump. The lag a late root may catch up is a credit spent once per chain, so a jump split
	over several frames is not followed past it either.

	Only fighters the blade may damage (CastOptions.eligible) are hits: a teammate, the attacker's
	own side or a dying enemy on the blade's path never uses up the window's target cap, and the
	blade passes through them.

	A fighter beside the swing (CastOptions.beside: its root outside the aim assist's cone around
	the run's facing, BladeContact.beside, D-275) is cut only where the blade itself crosses its
	body: the overlap test grows the blade by combat.besideHitRadius for it instead of the hit
	radius, the hit radius's casts pass through it, and between two samples the blade is moved
	straight from one to the other in steps no longer than that radius and tested at each
	(BladeContact.sweptTouch, the client's rule too). One broad-phase query per sample still serves
	both: it reaches back over the blade's move from the sample before. The hit radius is for the
	enemy the swing is aimed at, which the snap turned the body onto: it forgives the blade's reach
	to that body, not a cut that ends a stud short of a fighter to the side.

	Every solve of one frame can share one read of the rig's joints (Pose.chain): bladeAt, bladePath
	and solver take it as their last argument, and read the rig themselves without it.

	Pure pieces (Lune-tested): samplePath / sampleTimes, bladeAt / bladePath (Pose over Lune
	Instances), bladeStep and followArc with an injectable solver, segmentBoxDistance, castPath and
	castBladePath with an injectable caster and broad phase, and the cone / line tests enemy strikes
	use. The only engine calls are the defaults: workspace:Spherecast and
	workspace:GetPartBoundsInRadius.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local Combat = require(Shared.data.combat)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Pose = require(Shared.choreo.Pose)
local BladeContact = require(Shared.choreo.BladeContact)

export type Window = { open: number, close: number }

export type BladeSample = {
	time: number, -- clip time
	start: Vector3, -- TrailStart (the guard)
	finish: Vector3, -- TrailEnd (the tip)
	mid: Vector3,
	-- The root CFrame the blade was solved from (bladeAt sets it). followArc places a sub-sample's
	-- root between its neighbours' roots; a hand-built sample may leave it out.
	root: CFrame?,
}

-- Where the blade is at one clip time from one root CFrame, or nil when the rig cannot place it.
-- followArc calls it for each sub-sample; HitSweep.solver builds the one CombatService uses.
export type BladeSolver = (time: number, rootCFrame: CFrame?) -> BladeSample?

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
	-- Whether the blade may damage this fighter (default: every fighter). One it may not is never a
	-- hit, never counts toward maxTargets or alreadyHit, and never stops a cast: the blade passes
	-- through it. Asked at most once per fighter per call.
	eligible: ((targetId: number) -> boolean)?,
	maxTargets: number?, -- default combat.maxTargetsPerWindow, counting the window's earlier hits
	alreadyHit: { [number]: boolean }?, -- entity ids this window already hit (mutated)
	cast: Caster?, -- default workspace:Spherecast
	overlap: Overlapper?, -- default workspace:GetPartBoundsInRadius
	-- castBladePath: samples[1] is the previous call's last sample, already overlap-tested; the
	-- sweep starts from it without testing it again.
	continued: boolean?,
	-- castBladePath: whether this fighter stands beside the swing (D-275). One that does is cut only
	-- where the blade itself reaches it, grown by `besideRadius` (BladeContact.followTouch between
	-- samples); the hit radius's overlap test and casts pass through it. Asked at most once per
	-- fighter per call, and only of a fighter the blade may damage. Nil: none is beside.
	beside: ((targetId: number) -> boolean)?,
	besideRadius: number?, -- default combat.besideHitRadius
	-- castBladePath: poses the blade between two samples (followArc's solver, from a root between
	-- theirs along `clip`'s root motion), so the beside test follows the drawn arc
	-- (combat.besideFollowStep), at most combat.besideMaxSubdivisions splits per call. Nil, or a
	-- sample without its root: the move is taken straight.
	solve: BladeSolver?,
	clip: Types.ClipDef?,
}

export type Candidate = { id: number, position: Vector3, radius: number? }

-- A stretch of a line strike, in studs along the line from its origin (lineTargets).
export type Span = { from: number, to: number }

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

--- Where the blade is at one clip time: TrailStart, TrailEnd and their midpoint, solved through Pose
--- from `rootCFrame` with the clip's joint offsets. `chain` is the rig's joints read this frame
--- (Pose.chain); without it the rig is read for this solve. Returns nil when an attachment is not
--- on the rig.
function HitSweep.bladeAt(
	model: Model,
	rootCFrame: CFrame,
	clip: Types.ClipDef,
	time: number,
	trailStart: Attachment,
	trailEnd: Attachment,
	chain: Pose.Chain?
): BladeSample?
	local startPart = trailStart.Parent
	local endPart = trailEnd.Parent
	if startPart == nil or endPart == nil or not startPart:IsA("BasePart") or not endPart:IsA("BasePart") then
		return nil
	end
	local offsets = ClipSampler.sample(clip, time)
	local solved = Pose.solve(model, rootCFrame, offsets, chain)
	local startCFrame = solved[startPart.Name]
	local endCFrame = solved[endPart.Name]
	if startCFrame == nil or endCFrame == nil then
		return nil
	end
	local startPosition = (startCFrame * trailStart.CFrame).Position
	local endPosition = (endCFrame * trailEnd.CFrame).Position
	return {
		time = time,
		start = startPosition,
		finish = endPosition,
		mid = startPosition:Lerp(endPosition, 0.5),
		root = rootCFrame,
	}
end

--- Where the blade is at each clip time (bladeAt for every time), solved from `rootCFrame`. When
--- `from` is given (the sample this path continues from, the previous frame's last, with the root
--- it was solved from), each sample's root is interpolated in clip time from `from.root` to
--- `rootCFrame`, which the last time reaches: a frame that sweeps several sample times (a server
--- hitch) spreads the body's travel over them instead of solving the earlier ones where the body
--- only is now. `chain` is the rig's joints read this frame (Pose.chain); without it the rig is
--- read once for the whole path. Returns nil when an attachment is not on the rig.
function HitSweep.bladePath(
	model: Model,
	rootCFrame: CFrame,
	clip: Types.ClipDef,
	times: { number },
	trailStart: Attachment,
	trailEnd: Attachment,
	from: BladeSample?,
	chain: Pose.Chain?
): { BladeSample }?
	local fromRoot: CFrame? = if from ~= nil then from.root else nil
	local fromTime = if from ~= nil then from.time else 0
	local span = if #times > 0 then times[#times] - fromTime else 0
	local joints = if chain == nil and #times > 0 then Pose.chain(model) else chain
	local samples: { BladeSample } = {}
	for index, time in times do
		local root = rootCFrame
		if fromRoot ~= nil and span > 0 and index < #times then
			root = fromRoot:Lerp(rootCFrame, math.clamp((time - fromTime) / span, 0, 1))
		end
		local sample = HitSweep.bladeAt(model, root, clip, time, trailStart, trailEnd, joints)
		if sample == nil then
			return nil
		end
		table.insert(samples, sample)
	end
	return samples
end

--- The solver followArc uses for one fighter's clip: bladeAt from the root it is given, through
--- `chain` (the rig's joints read this frame) when one is given.
function HitSweep.solver(
	model: Model,
	clip: Types.ClipDef,
	trailStart: Attachment,
	trailEnd: Attachment,
	chain: Pose.Chain?
): BladeSolver
	return function(time: number, rootCFrame: CFrame?): BladeSample?
		if rootCFrame == nil then
			return nil
		end
		return HitSweep.bladeAt(model, rootCFrame, clip, time, trailStart, trailEnd, chain)
	end
end

--- The lag credit a window's chain starts with: how far combat.sweepMaxRootSpeed goes in
--- combat.lagAllowance (a replicated root can arrive up to the lag late, then catch up in one step).
function HitSweep.fullRootCredit(): number
	return Combat.sweepMaxRootSpeed * Combat.lagAllowance
end

--- Whether the body jumped since `previous`: its root now (`rootCFrame`, at clip time `time`) is
--- farther from the root `previous` was solved from than combat.sweepMaxRootSpeed goes in the time
--- between the two, plus `credit`, what is left of the chain's lag credit (default: full,
--- HitSweep.fullRootCredit). The credit works like the anti-cheat's (docs/DECISIONS.md D-034): a
--- step longer than the speed allows spends it, a shorter one refills it, never above full. So the
--- lag is spent once, not on every frame, and a run of long steps (a jump split over frames) is not
--- followed past it. A jump leaves the credit as it was. Returns whether the body jumped and the
--- credit left. A sample with no root never jumps.
function HitSweep.jumped(previous: BladeSample, rootCFrame: CFrame, time: number, credit: number?): (boolean, number)
	local full = HitSweep.fullRootCredit()
	local left = math.clamp(credit or full, 0, full)
	local from = previous.root
	if from == nil then
		return false, left
	end
	local allowed = Combat.sweepMaxRootSpeed * math.max(time - previous.time, 0)
	local travel = (rootCFrame.Position - from.Position).Magnitude
	if travel > allowed + left then
		return true, left
	end
	return false, math.min(left + allowed - travel, full)
end

--- How far the blade moves from sample `a` to sample `b`: the farther of its two ends (in a cut,
--- the tip; in a thrust or a body carried by root motion, the guard can match it).
function HitSweep.bladeStep(a: BladeSample, b: BladeSample): number
	return math.max((b.finish - a.finish).Magnitude, (b.start - a.start).Magnitude)
end

-- The root a sub-sample is solved from, `alpha` of the way from `a` to `b`: the body moves between
-- two frames the way the replicated root did, so a root that moved with the clip's root motion is
-- spread over the interval instead of landing as one jump that no clip-time split can shrink.
-- Given the swing's `clip`, the root follows the clip's own root motion between the two
-- (BladeContact.rootBow, D-275: a lunge accelerates through the interval), the rest straight.
local function rootBetween(a: BladeSample, b: BladeSample, alpha: number, clip: Types.ClipDef?): CFrame?
	local from, to = a.root, b.root
	if from ~= nil and to ~= nil then
		local root = from:Lerp(to, alpha)
		if clip ~= nil then
			local time = a.time + (b.time - a.time) * alpha
			root += BladeContact.rootBow(clip, a.time, b.time, time, root.Rotation)
		end
		return root
	end
	return to or from
end

--- Follows the blade's arc between consecutive samples of `path`: while the blade moves more than
--- `maxStep` (combat.sweepMaxTipStep) between two neighbours, the interval it moves farthest in is
--- split at its clip-time midpoint with a sub-sample from `solve`, until every step is at most
--- `maxStep` or `maxSubdivisions` (combat.sweepMaxSubdivisions) sub-samples were added. Largest
--- first, so a capped frame spends its sub-samples on the snap, not the settle. The path's own
--- samples are kept in order (the first and last stay first and last); a blade that never moves
--- more than `maxStep` gets the same path back and `solve` is never called. Returns the refined
--- path and how many sub-samples it added. A sub-sample `solve` cannot place ends the refinement.
--- With the swing's `clip`, a sub-sample's root follows the clip's root motion (rootBetween).
function HitSweep.followArc(
	path: { BladeSample },
	solve: BladeSolver,
	maxStep: number?,
	maxSubdivisions: number?,
	clip: Types.ClipDef?
): ({ BladeSample }, number)
	local limit = maxStep or Combat.sweepMaxTipStep
	local budget = maxSubdivisions or Combat.sweepMaxSubdivisions
	if #path < 2 or budget <= 0 then
		return path, 0
	end
	-- steps[index] is the blade's step from refined[index - 1] to refined[index] (steps[1] unused).
	local refined: { BladeSample } = {}
	local steps: { number } = {}
	local needsSplit = false
	for index, sample in path do
		refined[index] = sample
		local step = if index > 1 then HitSweep.bladeStep(path[index - 1], sample) else 0
		steps[index] = step
		if step > limit then
			needsSplit = true
		end
	end
	if not needsSplit then
		return path, 0
	end
	local added = 0
	while added < budget do
		local worstIndex, worstStep = 0, limit
		for index = 2, #refined do
			if steps[index] > worstStep then
				worstIndex, worstStep = index, steps[index]
			end
		end
		if worstIndex == 0 then
			break
		end
		local before, after = refined[worstIndex - 1], refined[worstIndex]
		local time = before.time + (after.time - before.time) * 0.5
		local sample = solve(time, rootBetween(before, after, 0.5, clip))
		if sample == nil then
			break
		end
		table.insert(refined, worstIndex, sample)
		steps[worstIndex] = HitSweep.bladeStep(before, sample)
		table.insert(steps, worstIndex + 1, HitSweep.bladeStep(sample, after))
		added += 1
	end
	return refined, added
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

-- The engine's query rule: spatial queries skip a part when both CanQuery and CanCollide are off
-- (CanQuery takes effect only on a part that does not collide), and, run as Default, a part whose
-- group does not collide with Default (an enemy's blocker, D-198): BladeContact.queryable. Of
-- those, a weapon a fighter holds (the kobold's club) is no hurtbox: a blade that meets it clashes,
-- never wounds (D-277, BladeContact.hurtbox).
local function isQueryable(part: BasePart): boolean
	return BladeContact.hurtbox(part)
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

local function always(_targetId: number): boolean
	return true
end

local function never(_targetId: number): boolean
	return false
end

-- options.beside, asked at most once per fighter for one call (none is beside without it).
local function besideOf(options: CastOptions): (number) -> boolean
	local beside = options.beside
	if beside == nil then
		return never
	end
	local known: { [number]: boolean } = {}
	return function(targetId: number): boolean
		local answer = known[targetId]
		if answer == nil then
			answer = beside(targetId)
			known[targetId] = answer
		end
		return answer
	end
end

-- options.eligible, asked at most once per fighter for one call (every fighter without it).
local function eligibilityOf(options: CastOptions): (number) -> boolean
	local eligible = options.eligible
	if eligible == nil then
		return always
	end
	local known: { [number]: boolean } = {}
	return function(targetId: number): boolean
		local answer = known[targetId]
		if answer == nil then
			answer = eligible(targetId)
			known[targetId] = answer
		end
		return answer
	end
end

-- The broad phase of one sample: the parts near its blade (segment start -> finish grown by
-- `radius`), and with `previous` given (fighters may stand beside the swing) also near the blade's
-- move from that sample, grown by `besideRadius`: every blade the move's arc passes lies within the
-- move's travel of one of its two ends (BladeContact.followTouch).
local function nearBlade(
	start: Vector3,
	finish: Vector3,
	previous: BladeSample?,
	radius: number,
	besideRadius: number,
	options: CastOptions,
	overlap: Overlapper
): { BasePart }
	local center = start:Lerp(finish, 0.5)
	local reach = (finish - start).Magnitude * 0.5 + radius
	if previous ~= nil then
		local travel = math.max((start - previous.start).Magnitude, (finish - previous.finish).Magnitude)
		reach = math.max(
			reach,
			math.max(
				(previous.start - center).Magnitude,
				(previous.finish - center).Magnitude,
				(finish - start).Magnitude * 0.5
			)
				+ travel
				+ besideRadius
		)
	end
	return overlap(center, reach, options.exclude)
end

-- The overlap test: every fighter the blade (segment start -> finish grown by `radius`, or by
-- `besideRadius` for a fighter beside the swing) touches right now, among `near` (nearBlade's
-- parts). Only parts of fighters the blade may damage and has not hit yet this window are measured,
-- so the floor, a pillar, the attacker's own body or a teammate is never a hit, and nothing blocks.
local function overlapBlade(
	start: Vector3,
	finish: Vector3,
	radius: number,
	near: { BasePart },
	options: CastOptions,
	alreadyHit: { [number]: boolean },
	hits: { Hit },
	budget: number,
	eligible: (number) -> boolean,
	beside: (number) -> boolean,
	besideRadius: number
)
	if #hits >= budget then
		return
	end
	for _, part in near do
		if not part:IsA("BasePart") or not isQueryable(part) then
			continue
		end
		local targetId, targetModel = options.resolve(part)
		if targetId == nil or targetModel == nil or alreadyHit[targetId] or not eligible(targetId) then
			continue
		end
		if isExcluded(part, targetModel, options.exclude) then
			continue
		end
		local cframe = part.CFrame
		local size = part.Size
		local reach = if beside(targetId) then besideRadius else radius
		-- Cheap reject: the part's bounding sphere does not reach the blade.
		if pointSegmentDistance(cframe.Position, start, finish) > reach + size.Magnitude * 0.5 then
			continue
		end
		local distance, contact = HitSweep.segmentBoxDistance(start, finish, cframe, size)
		if distance <= reach then
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
-- nothing the sphere overlaps at `origin`; the overlap test covers that. A fighter beside the swing
-- is never a hit here (the hit radius is not its rule): the cast passes through it.
local function castSegment(
	origin: Vector3,
	direction: Vector3,
	radius: number,
	exclude: { Instance },
	options: CastOptions,
	alreadyHit: { [number]: boolean },
	hits: { Hit },
	budget: number,
	cast: Caster,
	eligible: (number) -> boolean,
	beside: (number) -> boolean
)
	if direction.Magnitude < MIN_CAST_LENGTH then
		return
	end
	-- Each cast either ends the segment or meets a fighter and excludes it: a new hit, one the
	-- window already hit, or one the blade may not damage. A fighter met twice means the caster
	-- ignored the exclude list, so the loop stops there instead of spinning.
	local met: { [number]: boolean } = {}
	local clashed: { [Instance]: boolean } = {}
	while #hits < budget do
		local result = cast(origin, radius, direction, exclude)
		if result == nil then
			return
		end
		local instance = result.Instance
		local targetId, targetModel = options.resolve(instance)
		if targetId == nil or targetModel == nil then
			-- Something that is not a fighter (a pillar, the floor): the blade stops here.
			return
		end
		if instance:IsA("BasePart") and BladeContact.held(instance) then
			-- A weapon the fighter holds (D-277): no wound, and its body behind it is still cut. Only
			-- that part leaves the later casts; one met twice means the caster ignored the list.
			if clashed[instance] then
				return
			end
			clashed[instance] = true
			table.insert(exclude, instance)
			continue
		end
		if met[targetId] then
			return
		end
		met[targetId] = true
		if not alreadyHit[targetId] and eligible(targetId) and not beside(targetId) then
			alreadyHit[targetId] = true
			table.insert(hits, { targetId = targetId, position = result.Position })
		end
		-- Every fighter met is excluded from the later casts, so one never blocks another and the
		-- blade passes through a fighter it may not damage or that stands beside the swing.
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
	local eligible = eligibilityOf(options)

	if #hits < budget then
		local near = nearBlade(points[1], points[1], nil, radius, radius, options, overlap)
		overlapBlade(points[1], points[1], radius, near, options, alreadyHit, hits, budget, eligible, never, radius)
	end
	for index = 2, #points do
		if #hits >= budget then
			break
		end
		local origin = points[index - 1]
		castSegment(
			origin,
			points[index] - origin,
			radius,
			exclude,
			options,
			alreadyHit,
			hits,
			budget,
			cast,
			eligible,
			never
		)
	end
	return hits
end

-- Casts the chord one end of the blade travelled from `from` to `to` when it is longer than the arc
-- sweep's step: the step followArc could not reach before its cap ran out.
local function castLongChord(
	from: Vector3,
	to: Vector3,
	radius: number,
	exclude: { Instance },
	options: CastOptions,
	alreadyHit: { [number]: boolean },
	hits: { Hit },
	budget: number,
	cast: Caster,
	eligible: (number) -> boolean,
	beside: (number) -> boolean
)
	local chord = to - from
	if chord.Magnitude > Combat.sweepMaxTipStep then
		castSegment(from, chord, radius, exclude, options, alreadyHit, hits, budget, cast, eligible, beside)
	end
end

-- The blade's move from one sample to the next against every fighter beside the swing (D-275):
-- along the drawn arc (options.solve, from a root between the two samples' roots) while an end
-- moves farther than combat.besideFollowStep, then straight in steps of `besideRadius`, each grown
-- by it (BladeContact.followTouch), spending `arcs.left` splits. `near` is the later sample's broad
-- phase, which reaches back over the move (nearBlade); the original exclude list keeps the
-- attacker out (the casts' list also holds the fighters they passed through).
local function sweepBeside(
	from: BladeSample,
	to: BladeSample,
	besideRadius: number,
	near: { BasePart },
	options: CastOptions,
	alreadyHit: { [number]: boolean },
	hits: { Hit },
	budget: number,
	eligible: (number) -> boolean,
	beside: (number) -> boolean,
	arcs: { left: number }
)
	if #hits >= budget then
		return
	end
	local partsOf: { [number]: { BasePart } } = {}
	local order: { number } = {}
	for _, part in near do
		if not part:IsA("BasePart") or not isQueryable(part) then
			continue
		end
		local targetId, targetModel = options.resolve(part)
		if targetId == nil or targetModel == nil or alreadyHit[targetId] or not eligible(targetId) then
			continue
		end
		if isExcluded(part, targetModel, options.exclude) or not beside(targetId) then
			continue
		end
		local list = partsOf[targetId]
		if list == nil then
			list = {}
			partsOf[targetId] = list
			table.insert(order, targetId)
		end
		table.insert(list, part)
	end
	if #order == 0 then
		return
	end
	local follow: ((time: number) -> (Vector3?, Vector3?))? = nil
	local solve = options.solve
	if solve ~= nil and from.root ~= nil and to.root ~= nil and to.time > from.time then
		local solver: BladeSolver = solve
		local clip = options.clip
		follow = function(time: number): (Vector3?, Vector3?)
			local sample = solver(time, rootBetween(from, to, (time - from.time) / (to.time - from.time), clip))
			if sample == nil then
				return nil, nil
			end
			return sample.start, sample.finish
		end
	end
	for _, targetId in order do
		local touched, at, spent = BladeContact.followTouch(
			from.start,
			from.finish,
			from.time,
			to.start,
			to.finish,
			to.time,
			partsOf[targetId],
			besideRadius,
			Combat.besideFollowStep,
			follow,
			arcs.left
		)
		arcs.left -= spent
		if touched and at ~= nil then
			alreadyHit[targetId] = true
			table.insert(hits, { targetId = targetId, position = at })
			if #hits >= budget then
				return
			end
		end
	end
end

--- Full sweep of a blade path, in time order: at every sample the whole blade (guard to tip) is
--- tested for overlap, so a blade that starts the window inside a target, a target that walks onto
--- a resting blade and a thrust along the blade all register; between samples the blade's midpoint
--- is spherecast, so a cut that crosses a target between two samples registers too. A step in
--- which the tip or the guard still moves more than combat.sweepMaxTipStep (followArc's cap ran out)
--- also casts that end's chord. Each fighter the blade may damage counts once per window
--- (`alreadyHit`), up to the window's target cap; the others are passed through (`eligible`).
--- A fighter beside the swing (`beside`) is cut only by the blade itself (sweepBeside).
function HitSweep.castBladePath(samples: { BladeSample }, options: CastOptions): { Hit }
	local hits: { Hit } = {}
	if #samples == 0 then
		return hits
	end
	local radius = options.radius or Combat.hitSphereRadius
	local besideRadius = options.besideRadius or Combat.besideHitRadius
	local alreadyHit = options.alreadyHit or {}
	local budget = budgetOf(options, alreadyHit)
	local cast = options.cast or defaultCaster
	local overlap = options.overlap or defaultOverlap
	local exclude = table.clone(options.exclude)
	local eligible = eligibilityOf(options)
	local beside = besideOf(options)
	local arcs = { left = Combat.besideMaxSubdivisions }

	for index, sample in samples do
		if #hits >= budget then
			break
		end
		-- This sample's broad phase, queried once when first needed: by the move before it (beside
		-- fighters) or by its own overlap test.
		local near: { BasePart }? = nil
		local reachBack: BladeSample? = if index > 1 and options.beside ~= nil then samples[index - 1] else nil
		if index > 1 then
			local previous = samples[index - 1]
			local origin = previous.mid
			castSegment(
				origin,
				sample.mid - origin,
				radius,
				exclude,
				options,
				alreadyHit,
				hits,
				budget,
				cast,
				eligible,
				beside
			)
			castLongChord(
				previous.finish,
				sample.finish,
				radius,
				exclude,
				options,
				alreadyHit,
				hits,
				budget,
				cast,
				eligible,
				beside
			)
			castLongChord(
				previous.start,
				sample.start,
				radius,
				exclude,
				options,
				alreadyHit,
				hits,
				budget,
				cast,
				eligible,
				beside
			)
			if reachBack ~= nil and #hits < budget then
				local around = nearBlade(sample.start, sample.finish, reachBack, radius, besideRadius, options, overlap)
				near = around
				sweepBeside(
					previous,
					sample,
					besideRadius,
					around,
					options,
					alreadyHit,
					hits,
					budget,
					eligible,
					beside,
					arcs
				)
			end
		end
		if (index > 1 or not options.continued) and #hits < budget then
			overlapBlade(
				sample.start,
				sample.finish,
				radius,
				near or nearBlade(sample.start, sample.finish, reachBack, radius, besideRadius, options, overlap),
				options,
				alreadyHit,
				hits,
				budget,
				eligible,
				beside,
				besideRadius
			)
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
--- each target expanded by its radius. With `span`, only the stretch from `span.from` to `span.to`
--- studs along the line counts as well (a rushing body's sweep of one tick, D-166): a target whose
--- body (along +- radius) misses that stretch is left out, and the line's own ends still bound it.
function HitSweep.lineTargets(
	origin: Vector3,
	facing: Vector3,
	length: number,
	width: number,
	candidates: { Candidate },
	span: Span?
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
		if along < -radius or along > length + radius or across > halfWidth + radius then
			continue
		end
		if span ~= nil and (along + radius < span.from or along - radius > span.to) then
			continue
		end
		table.insert(inside, candidate)
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
