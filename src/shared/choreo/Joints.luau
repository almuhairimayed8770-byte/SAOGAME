--!strict
--[[
	Joints: one reader for the two kinds of animatable joint a rig can carry (section 10 "Rigs").

	- Motor6D: the RigBuilder enemies, the Weapon joint WeaponBuilder hangs from the hand, and
	  characters in places that predate the Avatar Joint Upgrade.
	- AnimationConstraint: the default player character. With the Avatar Joint Upgrade
	  (StarterPlayer.AvatarJointUpgrade, the default for new experiences) an R15 character spawns
	  with 15 AnimationConstraints named like the R15 Motor6Ds (Root, Waist, Neck, ...) and no
	  Motor6D at all; BallSocketConstraints named <Joint>BallSocket share their attachments.

	Both kinds pose by one rule, Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse(), and
	Transform means the same on both (a kinematic AnimationConstraint, the default, behaves like a
	Motor6D). On an AnimationConstraint, C0 / C1 / Part0 / Part1 are read-only aliases of
	Attachment0.CFrame / Attachment1.CFrame and the attachments' parts; this module reads the
	attachments themselves (Lune's instances leave the aliases unset, so the specs see what the
	engine sees). Nothing here writes C0, C1, an attachment or IsKinematic: the Humanoid owns the
	rig attachments, and Choreo only ever writes Transform.
]]

export type Joint = Motor6D | AnimationConstraint

--- One joint with everything forward kinematics needs, read once.
export type Resolved = {
	joint: Joint,
	name: string,
	part0: BasePart,
	part1: BasePart,
	c0: CFrame,
	c1: CFrame,
}

local Joints = {}

--- The class names that count as animatable joints, in report order.
Joints.CLASSES = table.freeze({ "Motor6D", "AnimationConstraint" })

--- True for a Motor6D or an AnimationConstraint.
function Joints.isJoint(instance: Instance): boolean
	return instance:IsA("Motor6D") or instance:IsA("AnimationConstraint")
end

--- The instance as a joint, or nil when it is neither kind.
function Joints.asJoint(instance: Instance): Joint?
	if instance:IsA("Motor6D") then
		return instance
	elseif instance:IsA("AnimationConstraint") then
		return instance
	end
	return nil
end

-- The part an attachment rides on and the attachment's frame in that part's space. An attachment
-- nested in another attachment is relative to it, so the frames compose up to the part.
local function mount(attachment: Attachment?): (BasePart?, CFrame)
	if attachment == nil then
		return nil, CFrame.identity
	end
	local frame = attachment.CFrame
	local parent = attachment.Parent
	while parent ~= nil and parent:IsA("Attachment") do
		frame = parent.CFrame * frame
		parent = parent.Parent
	end
	if parent ~= nil and parent:IsA("BasePart") then
		return parent, frame
	end
	return nil, frame
end

--- Part0 and Part1 of a joint of either kind (nil where unset).
function Joints.parts(joint: Joint): (BasePart?, BasePart?)
	if joint:IsA("Motor6D") then
		return joint.Part0, joint.Part1
	end
	local constraint = joint :: AnimationConstraint
	local part0 = mount(constraint.Attachment0)
	local part1 = mount(constraint.Attachment1)
	return part0, part1
end

--- C0 and C1 of a joint of either kind: a Motor6D's own, or an AnimationConstraint's attachment
--- frames in their parts' space (identity where an attachment is unset).
function Joints.frames(joint: Joint): (CFrame, CFrame)
	if joint:IsA("Motor6D") then
		return joint.C0, joint.C1
	end
	local constraint = joint :: AnimationConstraint
	local _, c0 = mount(constraint.Attachment0)
	local _, c1 = mount(constraint.Attachment1)
	return c0, c1
end

--- Everything forward kinematics needs for one joint, or nil while its Part0 or Part1 is unset.
function Joints.resolve(joint: Joint): Resolved?
	local part0, part1 = Joints.parts(joint)
	if part0 == nil or part1 == nil then
		return nil
	end
	local c0, c1 = Joints.frames(joint)
	return { joint = joint, name = joint.Name, part0 = part0, part1 = part1, c0 = c0, c1 = c1 }
end

--- Every joint of either kind under `root`, in GetDescendants order.
function Joints.list(root: Instance): { Joint }
	local found: { Joint } = {}
	for _, descendant in root:GetDescendants() do
		local joint = Joints.asJoint(descendant)
		if joint ~= nil then
			table.insert(found, joint)
		end
	end
	return found
end

--- Every joint under `root` whose parts are both set, resolved (Pose's input).
function Joints.collect(root: Instance): { Resolved }
	local resolved: { Resolved } = {}
	for _, joint in Joints.list(root) do
		local entry = Joints.resolve(joint)
		if entry ~= nil then
			table.insert(resolved, entry)
		end
	end
	return resolved
end

--- Every joint under `root` grouped by name, one list per name so a duplicate shows.
function Joints.byName(root: Instance): { [string]: { Joint } }
	local grouped: { [string]: { Joint } } = {}
	for _, joint in Joints.list(root) do
		local list = grouped[joint.Name]
		if list == nil then
			list = {}
			grouped[joint.Name] = list
		end
		table.insert(list, joint)
	end
	return grouped
end

--- Name -> joint for writing Transform (the first by GetDescendants order when a name repeats).
function Joints.map(root: Instance): { [string]: Joint }
	local named: { [string]: Joint } = {}
	for _, joint in Joints.list(root) do
		if named[joint.Name] == nil then
			named[joint.Name] = joint
		end
	end
	return named
end

--- Writes Transform on a joint of either kind (the property means the same on both).
function Joints.setTransform(joint: Joint, transform: CFrame)
	if joint:IsA("Motor6D") then
		joint.Transform = transform
	else
		(joint :: AnimationConstraint).Transform = transform
	end
end

return Joints
