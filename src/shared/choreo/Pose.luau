--!strict
--[[
	Pose: forward kinematics over a rig's joints with Choreo offsets applied.

	The client lets the engine do this when it writes each joint's Transform; the server uses it to
	find where the weapon is during a damage window (section 6: a server-side sweep along the
	weapon's path), so hits are checked against the same motion the client plays.

	A joint is a Motor6D or an AnimationConstraint (the default player character since the Avatar
	Joint Upgrade; Joints.luau reads both). Part CFrames follow the rule both share:
	Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse().
]]

local ClipSampler = require(script.Parent.ClipSampler)
local Joints = require(script.Parent.Joints)

export type Solved = { [string]: CFrame }

local Pose = {}

--- Solves every part's world CFrame from the root part, given the root's CFrame and joint offsets.
function Pose.solve(model: Model, rootCFrame: CFrame, offsets: ClipSampler.Offsets): Solved
	local root = model.PrimaryPart
	if root == nil then
		error(("Pose.solve: %s has no PrimaryPart"):format(model:GetFullName()))
	end
	local solved: Solved = { [root.Name] = rootCFrame }
	local joints = Joints.collect(model)
	local remaining = #joints
	-- Propagate outward from the root; a joint resolves once its Part0 is known. A pass that
	-- resolves nothing ends the solve: what is left (a joint off the root's tree, a second joint
	-- on an already solved part) can never resolve, so the server sweep does not spin on it.
	local progressed = true
	while remaining > 0 and progressed do
		progressed = false
		for _, joint in joints do
			local part0Name = joint.part0.Name
			local part1Name = joint.part1.Name
			if solved[part1Name] == nil and solved[part0Name] ~= nil then
				local offset = offsets[joint.name]
				local transform = if offset then ClipSampler.toCFrame(offset) else CFrame.identity
				solved[part1Name] = solved[part0Name] * joint.c0 * transform * joint.c1:Inverse()
				remaining -= 1
				progressed = true
			end
		end
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
