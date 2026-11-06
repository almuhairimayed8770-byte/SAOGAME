--!strict
--[[
	BodyShell (item 236): what a walk-in meets of two bodies, each in its own root's space.

	The engine collides only a character's root, torsos and head (combat.luau
	contact.standOff.keepOut.parts) with an enemy's blocker faces (RigBuilder.addBlocker, D-315), so
	a walk-in stopped with the arms and hands already inside the enemy: the drawn left hand 1.08
	studs inside a side-on boar's torso and 0.53 inside a kobold's arm, the sheathed one 0.30 inside
	its axe. The shell is the rest of the body, as boxes:
	- boxes(model, drawn): one box per part of the rig's `shell.parts` (rigs.luau PlayerR15.shell),
	  in the root's space, over that part (corners and all) in every pose of the stance's clips,
	  posed every shell.sampleSeconds with each clip's end included, padded shell.padStuds. It
	  stands still in the root's space, so the idle's breathing never pushes with it.
	- heldShapes(model): what an enemy holds (its rig's trailParts: the kobold's axe) as
	  blocker.heldSlices oriented boxes, each over that part in the poses of one slice of its
	  blocker clips (the loops it stands in), posed every blocker.sampleSeconds. The face over the
	  held part's whole footprint, floor to blockerHeight (D-315), stops a hand where the axe never
	  is: a drawn walk-in met it 5.88 studs from a kobold's root, past the reach a basic hits at.
	- depth(a, aSize, b, bSize): how deep two boxes overlap (the least push along the fifteen
	  separating axes, 0 or less apart) and the way out for `a`.

	Measured once per rig, stance and set of part sizes (the avatar decides the limbs' sizes).
	WalkShell (client) holds the local character's walk where the shell touches (D-430).
]]

local Shared = script.Parent.Parent

local Rigs = require(Shared.data.rigs)
local Types = require(Shared.types)
local Pose = require(script.Parent.Pose)
local ClipSampler = require(script.Parent.ClipSampler)

local BodyShell = {}

-- The name every shell box starts with.
BodyShell.PREFIX = "Shell"
-- The name every held shape starts with.
BodyShell.HELD_PREFIX = "Held"

--- One box in its root's space.
export type Box = { name: string, frame: CFrame, size: Vector3 }

local CORNERS = { -1, 1 }

local function clipById(id: string): Types.ClipDef?
	local node: Instance? = Shared:FindFirstChild("clips")
	for segment in id:gmatch("[^/]+") do
		if node == nil then
			return nil
		end
		node = (node :: Instance):FindFirstChild(segment)
	end
	if node == nil or not (node :: Instance):IsA("ModuleScript") then
		return nil
	end
	local ok, clip = pcall(require, node :: ModuleScript)
	if not ok or typeof(clip) ~= "table" then
		return nil
	end
	return clip :: Types.ClipDef
end

-- The rig a model was built as (its Rig attribute), the player's for a character without one.
local function rigOf(model: Model): Rigs.Rig?
	local rigId = model:GetAttribute("Rig")
	return Rigs[if typeof(rigId) == "string" then rigId else "PlayerR15"]
end

-- The times a stretch of a clip is posed at: every `step` from `from`, and `to`.
local function timesOf(from: number, to: number, step: number): { number }
	local times: { number } = {}
	local count = math.max(1, math.ceil((to - from) / step - 1e-6))
	for k = 0, count do
		table.insert(times, math.min(from + k * step, to))
	end
	return times
end

-- A key for the part sizes a measure depends on.
local function sizesKey(model: Model, names: { string }): string
	local sizes: { string } = {}
	for _, partName in names do
		local part = model:FindFirstChild(partName)
		if part ~= nil and part:IsA("BasePart") then
			local size = (part :: BasePart).Size
			table.insert(sizes, ("%s=%.4f,%.4f,%.4f"):format(partName, size.X, size.Y, size.Z))
		end
	end
	return table.concat(sizes, ";")
end

-- The box along `axes` (unit, root space) over every corner of a part of half-size `half` at
-- `frames`, padded `pad`.
local function boxOver(frames: { CFrame }, half: Vector3, axes: { Vector3 }, pad: number): (CFrame?, Vector3?)
	local low = { math.huge, math.huge, math.huge }
	local high = { -math.huge, -math.huge, -math.huge }
	for _, frame in frames do
		for _, x in CORNERS do
			for _, y in CORNERS do
				for _, z in CORNERS do
					local corner = frame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
					for index = 1, 3 do
						local along = corner:Dot(axes[index])
						low[index] = math.min(low[index], along)
						high[index] = math.max(high[index], along)
					end
				end
			end
		end
	end
	if low[1] > high[1] then
		return nil
	end
	local middle = Vector3.zero
	for index = 1, 3 do
		low[index] -= pad
		high[index] += pad
		middle += axes[index] * ((low[index] + high[index]) / 2)
	end
	return CFrame.fromMatrix(middle, axes[1], axes[2], axes[3]),
		Vector3.new(high[1] - low[1], high[2] - low[2], high[3] - low[3])
end

local ROOT_AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

local shells: { [string]: { Box } } = {}

--- The body shell a character carries in its root's space (see the header): empty for a rig with
--- no shell or a model without a root. A clip that does not load is left out, with a warning.
function BodyShell.boxes(model: Model, drawn: boolean): { Box }
	local rig = rigOf(model)
	local shell = if rig ~= nil then rig.shell else nil
	local root = model.PrimaryPart
	if rig == nil or shell == nil or root == nil then
		return {}
	end
	local key = ("%s|%s|%s"):format(rig.id, if drawn then "drawn" else "sheathed", sizesKey(model, shell.parts))
	local known = shells[key]
	if known ~= nil then
		return known
	end
	local chain = Pose.chain(model)
	local framesOf: { [string]: { CFrame } } = {}
	for _, partName in shell.parts do
		framesOf[partName] = {}
	end
	for _, id in if drawn then shell.drawn else shell.sheathed do
		local clip = clipById(id)
		if clip == nil or not (shell.sampleSeconds > 0) then
			warn(("BodyShell: rig '%s' shells clip '%s', which does not load"):format(rig.id, id))
			continue
		end
		for _, time in timesOf(0, clip.duration, shell.sampleSeconds) do
			local solved = Pose.solve(model, CFrame.identity, ClipSampler.sample(clip, time), chain)
			for _, partName in shell.parts do
				local frame = solved[partName]
				if frame ~= nil then
					table.insert(framesOf[partName], frame)
				end
			end
		end
	end
	local boxes: { Box } = {}
	for _, partName in shell.parts do
		local part = model:FindFirstChild(partName)
		if part == nil or not part:IsA("BasePart") then
			continue
		end
		local frame, size = boxOver(framesOf[partName], (part :: BasePart).Size / 2, ROOT_AXES, shell.padStuds)
		if frame ~= nil and size ~= nil then
			table.insert(boxes, { name = BodyShell.PREFIX .. partName, frame = frame, size = size })
		end
	end
	shells[key] = boxes
	return boxes
end

local held: { [string]: { Box } } = {}

--- What an enemy holds, as oriented boxes in its root's space (see the header): empty for a rig
--- that holds nothing or has no blocker clips, or a model without a root.
function BodyShell.heldShapes(model: Model): { Box }
	local rig = rigOf(model)
	local blocker = if rig ~= nil then rig.blocker else nil
	local names: { string } = if rig ~= nil then rig.trailParts or {} else {}
	if rig == nil or blocker == nil or #names == 0 or model.PrimaryPart == nil then
		return {}
	end
	local key = ("%s|%s"):format(rig.id, sizesKey(model, names))
	local known = held[key]
	if known ~= nil then
		return known
	end
	local chain = Pose.chain(model)
	local slices = math.max(1, blocker.heldSlices or 1)
	local shapes: { Box } = {}
	for _, id in blocker.clips do
		local clip = clipById(id)
		if clip == nil or not (blocker.sampleSeconds > 0) then
			warn(("BodyShell: rig '%s' stands in clip '%s', which does not load"):format(rig.id, id))
			continue
		end
		for slice = 1, slices do
			local from = (slice - 1) * clip.duration / slices
			local to = slice * clip.duration / slices
			local middle = Pose.solve(model, CFrame.identity, ClipSampler.sample(clip, (from + to) / 2), chain)
			local posed: { Pose.Solved } = {}
			for _, time in timesOf(from, to, blocker.sampleSeconds) do
				table.insert(posed, Pose.solve(model, CFrame.identity, ClipSampler.sample(clip, time), chain))
			end
			for _, partName in names do
				local part = model:FindFirstChild(partName)
				local axesFrame = middle[partName]
				if part == nil or not part:IsA("BasePart") or axesFrame == nil then
					continue
				end
				local frames: { CFrame } = {}
				for _, solved in posed do
					local frame = solved[partName]
					if frame ~= nil then
						table.insert(frames, frame)
					end
				end
				local axes = { axesFrame.RightVector, axesFrame.UpVector, axesFrame.LookVector }
				local frame, size = boxOver(frames, (part :: BasePart).Size / 2, axes, 0)
				if frame ~= nil and size ~= nil then
					table.insert(shapes, { name = BodyShell.HELD_PREFIX .. partName, frame = frame, size = size })
				end
			end
		end
	end
	held[key] = shapes
	return shapes
end

--- How deep box `a` stands in box `b`: the least push along the fifteen separating axes (0 or less
--- when they are apart), and that push's direction for `a` (unit, away from `b`; nil when apart).
function BodyShell.depth(a: CFrame, aSize: Vector3, b: CFrame, bSize: Vector3): (number, Vector3?)
	local axesA = { a.RightVector, a.UpVector, a.LookVector }
	local axesB = { b.RightVector, b.UpVector, b.LookVector }
	local halfA = { aSize.X / 2, aSize.Y / 2, aSize.Z / 2 }
	local halfB = { bSize.X / 2, bSize.Y / 2, bSize.Z / 2 }
	local between = a.Position - b.Position
	local least = math.huge
	local out: Vector3? = nil
	local function along(axis: Vector3)
		local length = axis.Magnitude
		if length < 1e-6 then
			return
		end
		local unit = axis / length
		local reach = 0
		for index = 1, 3 do
			reach += halfA[index] * math.abs(axesA[index]:Dot(unit)) + halfB[index] * math.abs(axesB[index]:Dot(unit))
		end
		local apart = between:Dot(unit)
		local overlap = reach - math.abs(apart)
		if overlap < least then
			least = overlap
			out = if apart >= 0 then unit else -unit
		end
	end
	for _, u in axesA do
		along(u)
	end
	for _, v in axesB do
		along(v)
	end
	for _, u in axesA do
		for _, v in axesB do
			along(u:Cross(v))
		end
	end
	return least, if least > 0 then out else nil
end

return BodyShell
