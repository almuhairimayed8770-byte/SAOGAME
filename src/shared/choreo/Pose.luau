--!strict
--[[
	Pose: forward kinematics over a rig's Motor6Ds with Choreo offsets applied.

	The client lets the engine do this when it writes Motor6D.Transform; the server uses it to
	find where the weapon is during a damage window (section 6: a server-side sweep along the
	weapon's path), so hits are checked against the same motion the client plays.

	Part CFrames follow Roblox's Motor6D rule: Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse().
]]

local ClipSampler = require(script.Parent.ClipSampler)

export type Solved = { [string]: CFrame }

local Pose = {}

type Joint = { motor: Motor6D, part0: BasePart, part1: BasePart }

local function collectJoints(model: Model): { Joint }
	local joints = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			table.insert(joints, { motor = descendant, part0 = descendant.Part0, part1 = descendant.Part1 })
		end
	end
	return joints
end

--- Solves every part's world CFrame from the root part, given the root's CFrame and joint offsets.
function Pose.solve(model: Model, rootCFrame: CFrame, offsets: ClipSampler.Offsets): Solved
	local root = model.PrimaryPart
	if root == nil then
		error(("Pose.solve: %s has no PrimaryPart"):format(model:GetFullName()))
	end
	local solved: Solved = { [root.Name] = rootCFrame }
	local joints = collectJoints(model)
	local remaining = #joints
	-- Propagate outward from the root; a joint resolves once its Part0 is known.
	local guard = 0
	while remaining > 0 and guard < 64 do
		guard += 1
		for _, joint in joints do
			local part0Name = joint.part0.Name
			local part1Name = joint.part1.Name
			if solved[part1Name] == nil and solved[part0Name] ~= nil then
				local offset = offsets[joint.motor.Name]
				local transform = if offset then ClipSampler.toCFrame(offset) else CFrame.identity
				solved[part1Name] = solved[part0Name] * joint.motor.C0 * transform * joint.motor.C1:Inverse()
				remaining -= 1
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
