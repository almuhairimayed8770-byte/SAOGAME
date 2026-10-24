--!strict
--[[
	ClipLibrary: resolves clip ids to clip modules (ARCHITECTURE "Clips").

	"player/OneHandedSword/SharpNail" -> ReplicatedStorage.Shared.clips.player.OneHandedSword.SharpNail
	"enemy/Boar/Charge"               -> ReplicatedStorage.Shared.clips.enemy.Boar.Charge

	Every clip is loaded once, checked once (the id matches, the rig exists, every joint the clip
	moves exists in that rig, the first key sits at time 0 so the rig is posed the frame the clip
	starts) and cached. Unknown ids error loudly: a missing clip is a data defect, never a silent
	T-pose.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared.types)
local Rigs = require(Shared.data.rigs)

local ClipLibrary = {}

local clipsFolder: Instance = Shared:WaitForChild("clips")
local cache: { [string]: Types.ClipDef } = {}
local jointSets: { [string]: { [string]: boolean } } = {}

local LAYERS: { [string]: boolean } = { Base = true, UpperBody = true, Additive = true, FullBody = true }

local function jointsOf(rigId: string): { [string]: boolean }?
	local cached = jointSets[rigId]
	if cached then
		return cached
	end
	local rig = Rigs[rigId]
	if rig == nil then
		return nil
	end
	local set: { [string]: boolean } = {}
	for _, joint in rig.joints do
		set[joint.name] = true
	end
	jointSets[rigId] = set
	return set
end

local function moduleFor(id: string): ModuleScript?
	local node: Instance? = clipsFolder
	for segment in id:gmatch("[^/]+") do
		if node == nil then
			return nil
		end
		node = node:FindFirstChild(segment)
	end
	if node ~= nil and node:IsA("ModuleScript") then
		return node
	end
	return nil
end

local function check(id: string, clip: any)
	assert(typeof(clip) == "table", ("clip %s did not return a table"):format(id))
	assert(clip.id == id, ("clip %s declares id '%s'"):format(id, tostring(clip.id)))
	assert(typeof(clip.duration) == "number" and clip.duration > 0, ("clip %s needs a positive duration"):format(id))
	assert(LAYERS[clip.layer] == true, ("clip %s has unknown layer '%s'"):format(id, tostring(clip.layer)))
	assert(typeof(clip.keys) == "table" and #clip.keys > 0, ("clip %s has no keys"):format(id))
	assert(clip.keys[1].time == 0, ("clip %s must start posed: first key at time 0"):format(id))
	assert(typeof(clip.events) == "table", ("clip %s has no events table"):format(id))
	local joints = jointsOf(clip.rig)
	assert(joints ~= nil, ("clip %s names rig '%s' which is not in rigs.luau"):format(id, tostring(clip.rig)))
	for index, key in ipairs(clip.keys) do
		for name in key.joints do
			assert(
				(joints :: any)[name] == true,
				("clip %s key %d moves joint '%s' which rig %s lacks"):format(id, index, name, clip.rig)
			)
		end
	end
end

--- The clip id for a module under the clips folder ("player/OneHandedSword/Idle"), or nil if it is outside it.
function ClipLibrary.idOf(module: Instance): string?
	local parts = {}
	local node: Instance? = module
	while node ~= nil and node ~= clipsFolder do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	if node ~= clipsFolder then
		return nil
	end
	return table.concat(parts, "/")
end

--- True when a clip module exists for the id (no load).
function ClipLibrary.has(id: string): boolean
	return cache[id] ~= nil or moduleFor(id) ~= nil
end

--- Loads, checks and caches the clip for an id; errors on an unknown id or a malformed clip.
function ClipLibrary.get(id: string): Types.ClipDef
	local cached = cache[id]
	if cached then
		return cached
	end
	local module = moduleFor(id)
	if module == nil then
		error(("ClipLibrary: no clip '%s' under %s"):format(id, clipsFolder:GetFullName()), 2)
	end
	local clip = require(module) :: any
	check(id, clip)
	cache[id] = clip
	return clip
end

--- Every clip id under the clips folder, sorted.
function ClipLibrary.all(): { string }
	local ids = {}
	for _, descendant in clipsFolder:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			local id = ClipLibrary.idOf(descendant)
			if id then
				table.insert(ids, id)
			end
		end
	end
	table.sort(ids)
	return ids
end

--- Every clip id for a rig ("PlayerR15", "Boar", "Kobold"), loading each clip once.
function ClipLibrary.forRig(rigId: string): { string }
	local ids = {}
	for _, id in ClipLibrary.all() do
		if ClipLibrary.get(id).rig == rigId then
			table.insert(ids, id)
		end
	end
	return ids
end

--- Drops the cache (tests and the ClipLab reload).
function ClipLibrary.clear()
	table.clear(cache)
end

return ClipLibrary
