--!strict
--[[
	Pose: forward kinematics over a rig's joints with Choreo offsets applied.

	The client lets the engine do this when it writes each joint's Transform; the server uses it to
	find where the weapon is during a damage window (section 6: a server-side sweep along the
	weapon's path), so hits are checked against the same motion the client plays.

	A joint is a Motor6D or an AnimationConstraint (the default player character since the Avatar
	Joint Upgrade; Joints.luau reads both). Part CFrames follow the rule both share:
	Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse().

	Reading the joints walks the whole character (every descendant, accessories included), and that
	walk costs far more than the solve itself. Pose.chain reads them once into a plain list in the
	order a solve places their parts; Pose.solve given that list touches no instance. A chain is a
	snapshot: respawns, equips and accessories change the joints, so the server sweep reads a new
	one every frame (CombatService) and never keeps one longer.
]]

local ClipSampler = require(script.Parent.ClipSampler)
local Joints = require(script.Parent.Joints)

export type Solved = { [string]: CFrame }

--- One joint as a solve uses it: the part names on each side and the frames around Transform.
export type Link = {
	name: string, -- the joint's name (the clip offsets are keyed by it)
	part0: string,
	part1: string,
	c0: CFrame,
	c1Inverse: CFrame,
}

--- A rig's joints read once, in the order a solve places their parts (Pose.chain).
export type Chain = {
	rootName: string,
	links: { Link },
}

local Pose = {}

--- Reads a rig's joints once (Joints.collect) and orders them outward from the root part: a
--- joint comes after the joint that places its Part0. A joint off the root's tree, or a second
--- joint onto a part already placed, is left out (a solve could never use it). Errors when the
--- model has no PrimaryPart.
function Pose.chain(model: Model): Chain
	local root = model.PrimaryPart
	if root == nil then
		error(("Pose.solve: %s has no PrimaryPart"):format(model:GetFullName()))
	end
	local rootName = root.Name
	local pending: { Link } = {}
	for _, joint in Joints.collect(model) do
		table.insert(pending, {
			name = joint.name,
			part0 = joint.part0.Name,
			part1 = joint.part1.Name,
			c0 = joint.c0,
			c1Inverse = joint.c1:Inverse(),
		})
	end
	local placed: { [string]: boolean } = { [rootName] = true }
	local links: { Link } = {}
	local remaining = #pending
	-- Propagate outward from the root in list order, pass after pass; a joint joins once its Part0
	-- is placed. A pass that adds nothing ends the walk: what is left can never be placed.
	local progressed = true
	while remaining > 0 and progressed do
		progressed = false
		for _, link in pending do
			if not placed[link.part1] and placed[link.part0] then
				placed[link.part1] = true
				table.insert(links, link)
				remaining -= 1
				progressed = true
			end
		end
	end
	return { rootName = rootName, links = links }
end

--- Solves every part's world CFrame from the root part, given the root's CFrame and joint offsets.
--- With `chain` (Pose.chain, read this frame) it reads nothing from the rig; without one it reads
--- the rig's joints first.
function Pose.solve(model: Model, rootCFrame: CFrame, offsets: ClipSampler.Offsets, chain: Chain?): Solved
	local links = chain or Pose.chain(model)
	local solved: Solved = { [links.rootName] = rootCFrame }
	for _, link in links.links do
		local offset = offsets[link.name]
		local transform = if offset then ClipSampler.toCFrame(offset) else CFrame.identity
		solved[link.part1] = solved[link.part0] * link.c0 * transform * link.c1Inverse
	end
	return solved
end

--- World CFrame of one part under the given offsets.
function Pose.partCFrame(model: Model, rootCFrame: CFrame, offsets: ClipSampler.Offsets, partName: string): CFrame?
	return Pose.solve(model, rootCFrame, offsets)[partName]
end

--- World position of an attachment under the given offsets (nil if its part is not in the rig).
function Pose.attachmentPosition(
	model: Model,
	rootCFrame: CFrame,
	offsets: ClipSampler.Offsets,
	attachment: Attachment
): Vector3?
	local parent = attachment.Parent
	if parent == nil or not parent:IsA("BasePart") then
		return nil
	end
	local partCFrame = Pose.partCFrame(model, rootCFrame, offsets, parent.Name)
	if partCFrame == nil then
		return nil
	end
	return (partCFrame * attachment.CFrame).Position
end

return Pose
