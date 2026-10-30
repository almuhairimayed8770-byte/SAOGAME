--!strict
--[[
	BladeContact: the blade a rig shows on the frame it renders, and the fighters it touches
	between two rendered frames (issue 4: the hit lands on contact, not a round trip later).

	The blade is the segment the trails draw: the weapon's TrailStart (the guard) to TrailEnd (the
	tip), found anywhere under the model as the server's sweep finds them
	(HitSweep.trailAttachments). `chain(model)` reads, once per swing, the joints from the root part
	out to the part those attachments ride on. `read(chain)` takes one rendered frame: the root
	part's CFrame and each of those joints' Transform as Choreo wrote it this frame. `blade(chain,
	pose, from, alpha)` solves the guard and the tip by forward kinematics (Part1 = Part0 * C0 *
	Transform * C1:Inverse(), the rule Pose uses): at `pose`, or `alpha` of the way from `from`
	(the frame before) to it, the root and every joint's Transform interpolated, so a sub-sample
	between two frames follows the swing's arc around the shoulder instead of cutting its chord.
	Reading the Transforms the animator wrote, rather than the parts, gives this frame's blade
	whether or not the engine has moved the parts yet.

	`touch(start, finish, parts, radius)` is the server's overlap rule (HitSweep): a part counts
	when the segment, grown by `radius` (combat.hitSphereRadius), reaches its box. Every part is
	measured as its box (segmentBoxDistance, the server's math), after a cheap bounding-sphere
	reject. `queryable(part)` is the engine's query rule the server's broad phase follows (CanQuery
	or CanCollide, and a group that collides with Default, which the queries run as: an enemy's
	blocker, D-198, is never seen). `hurtbox(part)` is what a blade may wound: a queryable part that
	is not a weapon its fighter holds (`held`: a part of a rigged model named in its rig's
	trailParts, the kobold's club). A blade that meets a held weapon clashes with it; it never
	wounds the fighter through it, and the server's sweep and the client's prediction both pass it
	by (D-277).

	A fighter beside the swing (`beside`: its root outside the aim assist's cone around the swing's
	facing, combat.aim.assistConeDegrees) is cut only by the blade itself (D-275): `followTouch`
	follows the blade's drawn arc from one sample to the next (split at the middle, posed by the
	caller's solver, while an end moves farther than combat.besideFollowStep and the body is near)
	and `sweptTouch` takes each short piece straight in steps no end travels farther than `step`,
	testing each against the parts grown by combat.besideHitRadius, so a blade that passes through
	the body between two samples touches it and one that stops short of it does not, whichever
	samples it starts from. The server's sweep and the client's prediction both use these, so they
	agree on it. Both pose a blade between two samples from a root between theirs that moves the way
	the swing's clip carries the body (`rootBow`), not along the chord: a lunge's root motion
	accelerates through a frame, and a straight root put a 30 fps client's blade 0.06 studs off the
	one the server's 60 Hz samples drew.

	Pure apart from reading the Instances it is handed: no engine service, no clock, so Lune runs
	it on real rigs.
]]

local Joints = require(script.Parent.Joints)
local ClipSampler = require(script.Parent.ClipSampler)
local Types = require(script.Parent.Parent.types)
local AI = require(script.Parent.Parent.data.ai)
local Rigs = require(script.Parent.Parent.data.rigs)

-- The rig id attribute a built model carries (RigBuilder.RIG_ATTRIBUTE; Choreo reads it too).
local RIG_ATTRIBUTE = "Rig"

export type Link = { joint: Joints.Joint, c0: CFrame, c1Inverse: CFrame }

--- The joints from the root part out to the blade's part, read once per swing.
export type Chain = {
	root: BasePart,
	links: { Link },
	start: CFrame, -- TrailStart in the blade part's space
	finish: CFrame, -- TrailEnd in the blade part's space
}

--- One rendered frame of a chain: the root part's CFrame and each link's Transform.
export type Pose = { root: CFrame, transforms: { CFrame } }

local BladeContact = {}

-- The part an attachment rides on and its frame in that part's space (nested attachments compose).
local function mount(attachment: Instance): (BasePart?, CFrame)
	local frame = CFrame.identity
	local node: Instance? = attachment
	while node ~= nil and node:IsA("Attachment") do
		frame = (node :: Attachment).CFrame * frame
		node = node.Parent
	end
	if node ~= nil and node:IsA("BasePart") then
		return node :: BasePart, frame
	end
	return nil, frame
end

local function attachmentNamed(model: Instance, name: string): Attachment?
	local found = model:FindFirstChild(name, true)
	if found ~= nil and found:IsA("Attachment") then
		return found :: Attachment
	end
	return nil
end

--- The rig's blade chain: its root part, the joints out to the part TrailStart and TrailEnd ride
--- on (both on one part), and their frames there. Nil when the model has no PrimaryPart, no
--- trail attachments, or no joint path from the root to the blade.
function BladeContact.chain(model: Model): Chain?
	local root = model.PrimaryPart
	local startAttachment = attachmentNamed(model, "TrailStart")
	local finishAttachment = attachmentNamed(model, "TrailEnd")
	if root == nil or startAttachment == nil or finishAttachment == nil then
		return nil
	end
	local blade, start = mount(startAttachment)
	local finishPart, finish = mount(finishAttachment)
	if blade == nil or finishPart ~= blade then
		return nil
	end
	-- part1 -> the joint that places it; walk back from the blade to the root.
	local placing: { [BasePart]: Joints.Resolved } = {}
	for _, resolved in Joints.collect(model) do
		if placing[resolved.part1] == nil then
			placing[resolved.part1] = resolved
		end
	end
	local reversed: { Link } = {}
	local part: BasePart = blade
	local guard = 0
	while part ~= root do
		local resolved = placing[part]
		guard += 1
		if resolved == nil or guard > 64 then
			return nil
		end
		table.insert(reversed, { joint = resolved.joint, c0 = resolved.c0, c1Inverse = resolved.c1:Inverse() })
		part = resolved.part0
	end
	local links: { Link } = {}
	for index = #reversed, 1, -1 do
		table.insert(links, reversed[index])
	end
	return { root = root, links = links, start = start, finish = finish }
end

--- This frame of a chain: the root part's CFrame and each link's Transform, into `into` when given
--- (reused frame to frame), else a new pose.
function BladeContact.read(chain: Chain, into: Pose?): Pose
	local pose: Pose = into or { root = CFrame.identity, transforms = {} }
	pose.root = chain.root.CFrame
	local transforms = pose.transforms
	for index, link in chain.links do
		transforms[index] = (link.joint :: any).Transform
	end
	for index = #chain.links + 1, #transforms do
		transforms[index] = nil
	end
	return pose
end

--- A copy of a pose (the frame before, kept while the next one is read into the original).
function BladeContact.copy(pose: Pose, into: Pose?): Pose
	local copied: Pose = into or { root = CFrame.identity, transforms = {} }
	copied.root = pose.root
	table.clear(copied.transforms)
	for index, transform in pose.transforms do
		copied.transforms[index] = transform
	end
	return copied
end

--- The guard and the tip at `pose`, or `alpha` (0..1) of the way from `from` to it.
function BladeContact.blade(chain: Chain, pose: Pose, from: Pose?, alpha: number?): (Vector3, Vector3)
	local t = if from ~= nil and alpha ~= nil then math.clamp(alpha, 0, 1) else 1
	local frame = if from ~= nil and t < 1 then from.root:Lerp(pose.root, t) else pose.root
	for index, link in chain.links do
		local transform = pose.transforms[index] or CFrame.identity
		if from ~= nil and t < 1 then
			local before = from.transforms[index] or transform
			transform = before:Lerp(transform, t)
		end
		frame = frame * link.c0 * transform * link.c1Inverse
	end
	return (frame * chain.start).Position, (frame * chain.finish).Position
end

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

local function outsideSquared(value: number, h: number): number
	local outside = math.abs(value) - h
	return if outside > 0 then outside * outside else 0
end

local cutScratch: { number } = {}

--- Closest approach of the segment a -> b to a box: the distance (0 when they intersect) and the
--- point of the box nearest the segment. The server's math (HitSweep.segmentBoxDistance), so a
--- touch here is a touch there.
function BladeContact.segmentBoxDistance(a: Vector3, b: Vector3, boxCFrame: CFrame, boxSize: Vector3): (number, Vector3)
	local localA = boxCFrame:PointToObjectSpace(a)
	local localB = boxCFrame:PointToObjectSpace(b)
	local ox, oy, oz = localA.X, localA.Y, localA.Z
	local dx, dy, dz = localB.X - ox, localB.Y - oy, localB.Z - oz
	local hx, hy, hz = boxSize.X * 0.5, boxSize.Y * 0.5, boxSize.Z * 0.5
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
	return math.sqrt(bestSquared), boxCFrame:PointToWorldSpace(onBox)
end

local function pointSegmentDistance(point: Vector3, a: Vector3, b: Vector3): number
	local direction = b - a
	local length = direction.Magnitude
	if length < 1e-6 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(direction) / (length * length), 0, 1)
	return (point - (a + direction * t)).Magnitude
end

-- The groups ai.collision.apart keeps from Default: a query, which runs as Default unless it names
-- a group, never sees their parts (an enemy's blocker, D-198).
local unseen: { [string]: boolean } = {}
for _, pair in AI.collision.apart do
	if pair[1] == "Default" then
		unseen[pair[2]] = true
	elseif pair[2] == "Default" then
		unseen[pair[1]] = true
	end
end

--- The engine's spatial query rule for a query run as Default: a part is skipped when CanQuery and
--- CanCollide are both off, or when its collision group does not collide with Default (D-198).
function BladeContact.queryable(part: BasePart): boolean
	return (part.CanQuery or part.CanCollide) and not unseen[part.CollisionGroup]
end

--- Whether `part` is a weapon its fighter holds, not its body (D-277): a child of a rigged model
--- (the "Rig" attribute RigBuilder sets) named in that rig's trailParts (rigs.luau). A blade that
--- meets it clashes with it; it never wounds.
function BladeContact.held(part: BasePart): boolean
	local model = part.Parent
	if model == nil or not model:IsA("Model") then
		return false
	end
	local rigId = model:GetAttribute(RIG_ATTRIBUTE)
	local rig = if typeof(rigId) == "string" then Rigs[rigId] else nil
	local names = if rig ~= nil then rig.trailParts else nil
	return names ~= nil and table.find(names, part.Name) ~= nil
end

--- Whether a blade touching `part` may wound its fighter: the engine's query sees it (queryable)
--- and it is the fighter's body, not a weapon it holds (held).
function BladeContact.hurtbox(part: BasePart): boolean
	return BladeContact.queryable(part) and not BladeContact.held(part)
end

--- Whether the blade (start -> finish grown by `radius`) touches any of `parts`, and where: the
--- point of the nearest touched part's box nearest the blade.
function BladeContact.touch(start: Vector3, finish: Vector3, parts: { BasePart }, radius: number): (boolean, Vector3?)
	local best: number? = nil
	local at: Vector3? = nil
	for _, part in parts do
		local cframe = part.CFrame
		local size = part.Size
		if pointSegmentDistance(cframe.Position, start, finish) > radius + size.Magnitude * 0.5 then
			continue
		end
		local distance, contact = BladeContact.segmentBoxDistance(start, finish, cframe, size)
		if distance <= radius and (best == nil or distance < best) then
			best = distance
			at = contact
		end
	end
	return at ~= nil, at
end

--- Whether a fighter whose root stands at `target` is beside a swing from `origin` facing `facing`:
--- flat, its bearing from the facing is more than half of `coneDegrees` either way. One within
--- `minDistance` (flat) of the origin gives no bearing, and a facing with no flat part gives no
--- cone: both are in front.
function BladeContact.beside(
	origin: Vector3,
	facing: Vector3,
	target: Vector3,
	coneDegrees: number,
	minDistance: number
): boolean
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	local offset = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	local distance = offset.Magnitude
	if flatFacing.Magnitude < 1e-6 or distance < math.max(minDistance, 1e-6) then
		return false
	end
	return offset:Dot(flatFacing.Unit) < distance * math.cos(math.rad(coneDegrees / 2))
end

--- Whether the blade, moving straight from (a0, b0) (the guard and the tip) to (a1, b1), passes
--- within `radius` of any of `parts`: tested at every step along the move, no end travelling
--- farther than `step` between two (so a box the blade passes through lies within half a step of
--- one of them), from the first step after (a0, b0), which the move before tested as its end, to
--- (a1, b1) itself. The first touch's point: of the nearest touched part's box, nearest the blade.
function BladeContact.sweptTouch(
	a0: Vector3,
	b0: Vector3,
	a1: Vector3,
	b1: Vector3,
	parts: { BasePart },
	radius: number,
	step: number
): (boolean, Vector3?)
	local travel = math.max((a1 - a0).Magnitude, (b1 - b0).Magnitude)
	if travel < 1e-9 then
		return false, nil
	end
	local count = if step > 0 then math.max(1, math.ceil(travel / step)) else 1
	for index = 1, count do
		local alpha = index / count
		local touched, at = BladeContact.touch(a0:Lerp(a1, alpha), b0:Lerp(b1, alpha), parts, radius)
		if touched then
			return true, at
		end
	end
	return false, nil
end

--- How far the clip's own root motion at clip time `time` bows off its straight line from `from` to
--- `to`, turned into the world by `rotation` (the root's facing). Added to a root interpolated
--- between the roots at `from` and `to`, it carries the body between two samples the way its clip
--- does instead of along the chord; zero at both ends, and when `to` is not after `from`.
function BladeContact.rootBow(clip: Types.ClipDef, from: number, to: number, time: number, rotation: CFrame): Vector3
	if to <= from then
		return Vector3.zero
	end
	local alpha = math.clamp((time - from) / (to - from), 0, 1)
	local a = ClipSampler.rootMotionAt(clip, from)
	local b = ClipSampler.rootMotionAt(clip, to)
	local m = ClipSampler.rootMotionAt(clip, time)
	return rotation:VectorToWorldSpace(
		Vector3.new(
			m[1] - (a[1] + (b[1] - a[1]) * alpha),
			m[2] - (a[2] + (b[2] - a[2]) * alpha),
			m[3] - (a[3] + (b[3] - a[3]) * alpha)
		)
	)
end

-- The least distance from the blade (start -> finish) to the boxes of `parts`.
local function nearestOf(start: Vector3, finish: Vector3, parts: { BasePart }): number
	local best = math.huge
	for _, part in parts do
		local cframe = part.CFrame
		local size = part.Size
		if pointSegmentDistance(cframe.Position, start, finish) - size.Magnitude * 0.5 >= best then
			continue
		end
		best = math.min(best, (BladeContact.segmentBoxDistance(start, finish, cframe, size)))
	end
	return best
end

--- Whether the blade, moving from (a0, b0) at parameter `t0` to (a1, b1) at `t1` along the path
--- `solve` poses (the guard and the tip at a parameter between; nil where it cannot), touches any
--- of `parts` grown by `radius`. The move is split at its middle parameter while an end still
--- travels farther than `fine` and the body is near enough to touch, at most `budget` splits; a
--- move short enough (or the budget spent, or no solver) is taken straight in steps of `radius`
--- (sweptTouch). A move whose nearer end is farther from the body than `radius` plus its travel is
--- skipped: no blade between bows that far (an arc is never twice its chord). So it follows the
--- drawn arc to within the sagitta of a `fine` chord, whatever samples it starts from. The blade
--- at `t0` is not tested (the move before ended on it). Returns the touch, its point (as
--- sweptTouch) and the splits spent.
function BladeContact.followTouch(
	a0: Vector3,
	b0: Vector3,
	t0: number,
	a1: Vector3,
	b1: Vector3,
	t1: number,
	parts: { BasePart },
	radius: number,
	fine: number,
	solve: ((t: number) -> (Vector3?, Vector3?))?,
	budget: number
): (boolean, Vector3?, number)
	local spent = 0
	local function follow(
		guard0: Vector3,
		tip0: Vector3,
		from: number,
		guard1: Vector3,
		tip1: Vector3,
		to: number
	): (boolean, Vector3?)
		local travel = math.max((guard1 - guard0).Magnitude, (tip1 - tip0).Magnitude)
		if travel < 1e-9 then
			return false, nil
		end
		local near = math.min(nearestOf(guard0, tip0, parts), nearestOf(guard1, tip1, parts))
		if near - travel > radius then
			return false, nil
		end
		if travel <= fine or solve == nil or spent >= budget then
			return BladeContact.sweptTouch(guard0, tip0, guard1, tip1, parts, radius, radius)
		end
		local middle = (from + to) * 0.5
		local guard, tip = solve(middle)
		spent += 1
		if guard == nil or tip == nil then
			return BladeContact.sweptTouch(guard0, tip0, guard1, tip1, parts, radius, radius)
		end
		local touched, at = follow(guard0, tip0, from, guard, tip, middle)
		if touched then
			return true, at
		end
		return follow(guard, tip, middle, guard1, tip1, to)
	end
	local touched, at = follow(a0, b0, t0, a1, b1, t1)
	return touched, at, spent
end

--- How many sub-samples split the blade's move from (a0, b0) to (a1, b1) so neither end moves
--- farther than `maxStep` between two of them: at least 1, at most `cap`.
function BladeContact.steps(a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, maxStep: number, cap: number): number
	local travel = math.max((a1 - a0).Magnitude, (b1 - b0).Magnitude)
	if maxStep <= 0 then
		return 1
	end
	return math.clamp(math.ceil(travel / maxStep), 1, math.max(1, cap))
end

return BladeContact
