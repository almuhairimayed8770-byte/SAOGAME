--!strict
--[[
	Validates data/rigs.luau's rest poses (D-483). RigBuilder stands a rig built from parts with
	its root part's centre hipHeight plus half the root's height above the floor (PlaygroundLayout
	.rootHeight), and the server never animates it: its hit sweeps, stand-off and blockers read that
	rest pose. Every clip of the rig poses its torso from that same root.

	- Every rig with parts has a rootPart among them, a positive hipHeight and a joint chain that
	  reaches every part from the root.
	- The rest pose (every joint at c0 * c1^-1, no clip) stands on the floor: its lowest corner is
	  within choreo.luau locomotion.stride.contact of it, neither below (a foot in the field: the
	  kobold at hipHeight 2.2 stood 0.2 into it) nor above (a body floating over its own feet).
	The player's R15 is the avatar's, not built from rigs.luau parts, so it has no rest pose here.
]]

local roblox = require("@lune/roblox")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local function vector(value: any): boolean
	return typeof(value) == "table"
		and typeof(value[1]) == "number"
		and typeof(value[2]) == "number"
		and typeof(value[3]) == "number"
end

local function transform(value: any): CFrame
	if typeof(value) ~= "table" then
		return CFrame.new()
	end
	local pos = if vector(value.pos) then value.pos else { 0, 0, 0 }
	local rot = if vector(value.rot) then value.rot else { 0, 0, 0 }
	return CFrame.new(pos[1], pos[2], pos[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
end

return function(ctx: any): { string }
	local problems: { string } = {}
	local function problem(format: string, ...: any)
		table.insert(problems, "rigs: " .. string.format(format, ...))
	end

	local Rigs = ctx.load("src/shared/data/rigs")
	local choreo = ctx.load("src/shared/data/choreo")
	local stride = if typeof(choreo.locomotion) == "table" then choreo.locomotion.stride else nil
	local contact = if typeof(stride) == "table" then stride.contact else nil
	if typeof(contact) ~= "number" or not (contact >= 0) then
		problem("choreo.luau locomotion.stride.contact must be a number of studs at least 0")
		return problems
	end

	local ids: { string } = {}
	for id, rig in Rigs do
		if typeof(rig) == "table" and rig.parts ~= nil then
			table.insert(ids, id)
		end
	end
	table.sort(ids)

	for _, id in ids do
		local rig = Rigs[id]
		local parts = rig.parts
		local rootPart = if typeof(parts) == "table" then parts[rig.rootPart] else nil
		if typeof(rootPart) ~= "table" or not vector(rootPart.size) then
			problem("%s's rootPart %s is not one of its parts with a size", id, tostring(rig.rootPart))
			continue
		end
		if typeof(rig.hipHeight) ~= "number" or not (rig.hipHeight > 0) then
			problem("%s's hipHeight must be a number above 0", id)
			continue
		end
		-- The rest pose: the root's centre above a floor at 0, each part at its joint's c0 * c1^-1.
		local frames: { [string]: CFrame } = {
			[rig.rootPart] = CFrame.new(0, rig.hipHeight + rootPart.size[2] / 2, 0),
		}
		local placed = true
		while placed do
			placed = false
			for _, joint in rig.joints or {} do
				local from = frames[joint.part0]
				if from ~= nil and frames[joint.part1] == nil then
					frames[joint.part1] = from * transform(joint.c0) * transform(joint.c1):Inverse()
					placed = true
				end
			end
		end
		local lowest, lowestPart = math.huge, ""
		local names: { string } = {}
		for name in parts do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local frame = frames[name]
			local size = parts[name].size
			if frame == nil then
				problem("%s's part %s is not reached from %s by its joints", id, name, rig.rootPart)
				continue
			end
			if not vector(size) then
				continue
			end
			for _, sx in { -0.5, 0.5 } do
				for _, sy in { -0.5, 0.5 } do
					for _, sz in { -0.5, 0.5 } do
						local y = (frame * Vector3.new(sx * size[1], sy * size[2], sz * size[3])).Y
						if y < lowest then
							lowest, lowestPart = y, name
						end
					end
				end
			end
		end
		if lowest < math.huge and math.abs(lowest) > contact + 1e-6 then
			problem(
				"%s's rest pose at hipHeight %s has its lowest corner (%s) %.3f studs %s the floor: it must stand within locomotion.stride.contact %s of it",
				id,
				tostring(rig.hipHeight),
				lowestPart,
				math.abs(lowest),
				if lowest < 0 then "below" else "above",
				tostring(contact)
			)
		end
	end
	return problems
end
