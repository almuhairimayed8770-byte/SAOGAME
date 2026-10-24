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
	or CanCollide).

	Pure apart from reading the Instances it is handed: no engine service, no clock, so Lune runs
	it on real rigs.
]]

local Joints = require(script.Parent.Joints)

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

--- The engine's spatial query rule: a part is skipped only when CanQuery and CanCollide are both off.
function BladeContact.queryable(part: BasePart): boolean
	return part.CanQuery or part.CanCollide
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
