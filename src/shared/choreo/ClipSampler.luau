--!strict
--[[
	ClipSampler: pure sampling of Choreo clip data (section 10, docs/DECISIONS.md D-003).

	Both the client animator and the server hit sweep sample clips through this module, so the
	blade path the server checks is the same motion the client shows. No Roblox datatypes are
	created until `toCFrame`, so every function above it runs in Lune.

	A clip is a list of keys; each key holds per-joint offsets (studs, degrees) and the easing used
	to arrive at that key from the previous one. Between keys, every joint present in either key is
	interpolated; a joint missing from a key holds its last value.

	Clip tables are immutable after load. The sampler keeps a per-clip cache (weak-keyed by the
	clip table) of the clip's structure: the sorted joint list and, for every joint, which key
	authors the value it holds at each key index. Offsets themselves are read live from the keys.
	The animator samples every handle on every rig each frame, so this cache is what keeps
	`sample` down to the result tables callers blend and mutate. An editor that changes a clip's
	keys (the PoseEditor session) calls `ClipSampler.invalidate(clip)` afterwards.
]]

local Types = require(script.Parent.Parent.types)
local Easing = require(script.Parent.Parent.util.Easing)

export type Offset = { pos: Types.Vec3, rot: Types.Vec3 }
export type Offsets = { [string]: Offset }

type ClipCache = {
	names: { string }, -- sorted and frozen; ROOT_KEY included when any key moves the root
	held: { [string]: { number } }, -- per joint: for each key index, the key authoring the held value (0: none yet)
}

local ClipSampler = {}

local ROOT_KEY = "__root"
ClipSampler.ROOT_KEY = ROOT_KEY

local ZERO: Types.Vec3 = { 0, 0, 0 }
local REST: Offset = { pos = ZERO, rot = ZERO }

-- Weak keys: a session clip the editor drops takes its cache entry with it.
local cache: { [Types.ClipDef]: ClipCache } = setmetatable({}, { __mode = "k" }) :: any

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpVec(a: Types.Vec3, b: Types.Vec3, t: number): Types.Vec3
	return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end

-- One pass over the keys: the joint set and, per joint, the authoring key index at every key.
local function buildCache(clip: Types.ClipDef): ClipCache
	local keys = clip.keys
	local count = #keys
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	for _, key in keys do
		for name in key.joints do
			if not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
		if key.root and not seen[ROOT_KEY] then
			seen[ROOT_KEY] = true
			table.insert(names, ROOT_KEY)
		end
	end
	table.sort(names)

	local held: { [string]: { number } } = {}
	for _, name in names do
		local track = table.create(count, 0)
		local authored = 0
		for index = 1, count do
			local key = keys[index]
			local joint = if name == ROOT_KEY then key.root else key.joints[name]
			if joint then
				authored = index
			end
			track[index] = authored
		end
		held[name] = track
	end
	return { names = table.freeze(names), held = held }
end

local function cacheFor(clip: Types.ClipDef): ClipCache
	local entry = cache[clip]
	if entry == nil then
		entry = buildCache(clip)
		cache[clip] = entry
	end
	return entry
end

-- The value a joint holds at key index `index`, read live from the authoring key (rest when none).
local function heldAt(keys: { Types.ClipKey }, track: { number }, name: string, index: number): (Types.Vec3, Types.Vec3)
	-- A stale cache (keys edited without `invalidate`) reads as rest here rather than erroring.
	local authored = track[index]
	if authored == nil or authored == 0 then
		return ZERO, ZERO
	end
	local key = keys[authored]
	if key == nil then
		return ZERO, ZERO
	end
	local joint = if name == ROOT_KEY then key.root else key.joints[name]
	if joint == nil then
		return ZERO, ZERO
	end
	return joint.pos or ZERO, joint.rot or ZERO
end

-- Where `time` falls in the clip: the key indices to blend from and to, and the eased alpha.
-- `from == to` means hold that key's values. Looping clips wrap; others clamp.
local function locate(clip: Types.ClipDef, time: number): (number, number, number)
	local keys = clip.keys
	local count = #keys
	local t = time
	if clip.loop and clip.duration > 0 then
		t = t % clip.duration
	else
		t = math.clamp(t, 0, clip.duration)
	end

	-- Find the key pair surrounding t.
	local nextIndex = count + 1
	for index, key in keys do
		if key.time > t then
			nextIndex = index
			break
		end
	end
	local previousIndex = nextIndex - 1

	if previousIndex < 1 then
		-- Before the first key: hold the first key's values.
		return 1, 1, 1
	end
	if nextIndex > count then
		if clip.loop and count > 1 then
			-- Wrap from the last key back to the first across the remaining duration.
			local lastKey = keys[count]
			local span = clip.duration - lastKey.time
			local alpha = if span > 0 then Easing.evaluate(keys[1].easing, (t - lastKey.time) / span) else 1
			return count, 1, alpha
		end
		return count, count, 1
	end

	local previousKey = keys[previousIndex]
	local nextKey = keys[nextIndex]
	local span = nextKey.time - previousKey.time
	local alpha = if span > 0 then Easing.evaluate(nextKey.easing, (t - previousKey.time) / span) else 1
	return previousIndex, nextIndex, alpha
end

--- The set of joint names a clip touches (plus the root if any key moves it), sorted. The list is
--- cached per clip and frozen: read it, never edit it. After editing a clip's keys call `invalidate`.
function ClipSampler.jointNames(clip: Types.ClipDef): { string }
	return cacheFor(clip).names
end

--- Drops the cached structure of a clip. Editors call this after changing a clip table's keys
--- (adding or removing a key, a joint or the root) so the next sample sees the edit.
function ClipSampler.invalidate(clip: Types.ClipDef)
	cache[clip] = nil
end

--- Interpolated offsets for every joint at `time` (seconds). Looping clips wrap; others clamp.
--- Every call returns a fresh result table with fresh per-joint entries (callers blend and mutate them).
--- The `pos` / `rot` arrays inside an entry are fresh between keys but, while a key is held (before
--- the first key and from the last key on), they are the clip's own arrays: replace them, never
--- write into them (Mixer.addInto does this).
function ClipSampler.sample(clip: Types.ClipDef, time: number): Offsets
	local keys = clip.keys
	if #keys == 0 then
		return {}
	end
	local entry = cacheFor(clip)
	local names = entry.names
	local held = entry.held
	local from, to, alpha = locate(clip, time)

	local result: Offsets = {}
	if from == to then
		for _, name in names do
			local pos, rot = heldAt(keys, held[name], name, from)
			result[name] = { pos = pos, rot = rot }
		end
		return result
	end
	for _, name in names do
		local track = held[name]
		local fromPos, fromRot = heldAt(keys, track, name, from)
		local toPos, toRot = heldAt(keys, track, name, to)
		result[name] = { pos = lerpVec(fromPos, toPos, alpha), rot = lerpVec(fromRot, toRot, alpha) }
	end
	return result
end

--- Root motion offset (studs, in the rig's local frame) at `time`.
function ClipSampler.rootMotionAt(clip: Types.ClipDef, time: number): Types.Vec3
	local keys = clip.keys
	if #keys == 0 then
		return ZERO
	end
	local track = cacheFor(clip).held[ROOT_KEY]
	if track == nil then
		return ZERO
	end
	local from, to, alpha = locate(clip, time)
	local fromPos = heldAt(keys, track, ROOT_KEY, from)
	if from == to then
		return fromPos
	end
	local toPos = heldAt(keys, track, ROOT_KEY, to)
	return lerpVec(fromPos, toPos, alpha)
end

--- Events whose time lies in (fromTime, toTime]. Looping clips are handled by the caller
--- passing unwrapped times; this function does no wrapping.
function ClipSampler.events(clip: Types.ClipDef, fromTime: number, toTime: number): { Types.ClipEvent }
	local crossed = {}
	for _, event in clip.events do
		if event.time > fromTime and event.time <= toTime then
			table.insert(crossed, event)
		end
	end
	return crossed
end

--- The damage windows of an attack clip as {open, close} pairs in clip time, in order.
function ClipSampler.hitWindows(clip: Types.ClipDef): { { open: number, close: number } }
	local windows = {}
	local open: number? = nil
	for _, event in clip.events do
		if event.kind == "HitWindowOpen" then
			open = event.time
		elseif event.kind == "HitWindowClose" and open ~= nil then
			table.insert(windows, { open = open, close = event.time })
			open = nil
		end
	end
	return windows
end

--- Converts a plain offset to a CFrame (Roblox runtime only).
function ClipSampler.toCFrame(offset: Offset): CFrame
	local pos = offset.pos
	local rot = offset.rot
	return CFrame.new(pos[1], pos[2], pos[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
end

--- Linear blend of two offset sets by `alpha` (0 = a, 1 = b); joints missing from one side blend from rest.
function ClipSampler.blend(a: Offsets, b: Offsets, alpha: number): Offsets
	local result: Offsets = {}
	for name, offset in a do
		local other = b[name] or REST
		result[name] = { pos = lerpVec(offset.pos, other.pos, alpha), rot = lerpVec(offset.rot, other.rot, alpha) }
	end
	for name, offset in b do
		if result[name] == nil then
			result[name] = { pos = lerpVec(REST.pos, offset.pos, alpha), rot = lerpVec(REST.rot, offset.rot, alpha) }
		end
	end
	return result
end

-- `base` plus `offset` scaled by `weight`, as a fresh offset.
local function addOffset(base: Offset, offset: Offset, weight: number): Offset
	return {
		pos = {
			base.pos[1] + offset.pos[1] * weight,
			base.pos[2] + offset.pos[2] * weight,
			base.pos[3] + offset.pos[3] * weight,
		},
		rot = {
			base.rot[1] + offset.rot[1] * weight,
			base.rot[2] + offset.rot[2] * weight,
			base.rot[3] + offset.rot[3] * weight,
		},
	}
end

--- Adds offset set `b` on top of `a` (additive layers: breathing, flinch, lean).
function ClipSampler.add(a: Offsets, b: Offsets, weight: number): Offsets
	local result: Offsets = {}
	for name, offset in a do
		local extra = b[name]
		if extra == nil then
			result[name] = { pos = table.clone(offset.pos), rot = table.clone(offset.rot) }
		else
			result[name] = addOffset(offset, extra, weight)
		end
	end
	for name, offset in b do
		if result[name] == nil then
			result[name] = addOffset(REST, offset, weight)
		end
	end
	return result
end

return ClipSampler
