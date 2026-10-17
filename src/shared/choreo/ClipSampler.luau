--!strict
--[[
	ClipSampler: pure sampling of Choreo clip data (section 10, docs/DECISIONS.md D-003).

	Both the client animator and the server hit sweep sample clips through this module, so the
	blade path the server checks is the same motion the client shows. No Roblox datatypes are
	created until `toCFrame`, so every function above it runs in Lune.

	A clip is a list of keys; each key holds per-joint offsets (studs, degrees) and the easing used
	to arrive at that key from the previous one. Between keys, every joint present in either key is
	interpolated; a joint missing from a key holds its last value.
]]

local Types = require(script.Parent.Parent.types)
local Easing = require(script.Parent.Parent.util.Easing)

export type Offset = { pos: Types.Vec3, rot: Types.Vec3 }
export type Offsets = { [string]: Offset }

local ClipSampler = {}

local ROOT_KEY = "__root"
ClipSampler.ROOT_KEY = ROOT_KEY

local ZERO: Types.Vec3 = { 0, 0, 0 }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpVec(a: Types.Vec3, b: Types.Vec3, t: number): Types.Vec3
	return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end

local function offsetOf(joint: Types.JointKey?): Offset
	if joint == nil then
		return { pos = ZERO, rot = ZERO }
	end
	return { pos = joint.pos or ZERO, rot = joint.rot or ZERO }
end

--- The set of joint names a clip touches (plus the root if any key moves it).
function ClipSampler.jointNames(clip: Types.ClipDef): { string }
	local seen: { [string]: boolean } = {}
	local names = {}
	for _, key in clip.keys do
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
	return names
end

-- Value of a joint at key index `index`, holding the last authored value when a key omits it.
local function heldValue(clip: Types.ClipDef, name: string, index: number): Offset
	for i = index, 1, -1 do
		local key = clip.keys[i]
		if name == ROOT_KEY then
			if key.root then
				return offsetOf(key.root)
			end
		else
			local joint = key.joints[name]
			if joint then
				return offsetOf(joint)
			end
		end
	end
	return { pos = ZERO, rot = ZERO }
end

--- Interpolated offsets for every joint at `time` (seconds). Looping clips wrap; others clamp.
function ClipSampler.sample(clip: Types.ClipDef, time: number): Offsets
	local keys = clip.keys
	local count = #keys
	if count == 0 then
		return {}
	end
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

	local result: Offsets = {}
	local names = ClipSampler.jointNames(clip)

	if previousIndex < 1 then
		-- Before the first key: hold the first key's values.
		for _, name in names do
			result[name] = heldValue(clip, name, 1)
		end
		return result
	end
	if nextIndex > count then
		if clip.loop and count > 1 then
			-- Wrap from the last key back to the first across the remaining duration.
			local lastKey = keys[count]
			local span = clip.duration - lastKey.time
			local alpha = if span > 0 then Easing.evaluate(keys[1].easing, (t - lastKey.time) / span) else 1
			for _, name in names do
				local a = heldValue(clip, name, count)
				local b = heldValue(clip, name, 1)
				result[name] = { pos = lerpVec(a.pos, b.pos, alpha), rot = lerpVec(a.rot, b.rot, alpha) }
			end
			return result
		end
		for _, name in names do
			result[name] = heldValue(clip, name, count)
		end
		return result
	end

	local previousKey = keys[previousIndex]
	local nextKey = keys[nextIndex]
	local span = nextKey.time - previousKey.time
	local alpha = if span > 0 then Easing.evaluate(nextKey.easing, (t - previousKey.time) / span) else 1
	for _, name in names do
		local a = heldValue(clip, name, previousIndex)
		local b = heldValue(clip, name, nextIndex)
		result[name] = { pos = lerpVec(a.pos, b.pos, alpha), rot = lerpVec(a.rot, b.rot, alpha) }
	end
	return result
end

--- Root motion offset (studs, in the rig's local frame) at `time`.
function ClipSampler.rootMotionAt(clip: Types.ClipDef, time: number): Types.Vec3
	local offsets = ClipSampler.sample(clip, time)
	local root = offsets[ROOT_KEY]
	if root == nil then
		return ZERO
	end
	return root.pos
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
	local rest: Offset = { pos = ZERO, rot = ZERO }
	for name, offset in a do
		local other = b[name] or rest
		result[name] = { pos = lerpVec(offset.pos, other.pos, alpha), rot = lerpVec(offset.rot, other.rot, alpha) }
	end
	for name, offset in b do
		if result[name] == nil then
			result[name] = { pos = lerpVec(rest.pos, offset.pos, alpha), rot = lerpVec(rest.rot, offset.rot, alpha) }
		end
	end
	return result
end

--- Adds offset set `b` on top of `a` (additive layers: breathing, flinch, lean).
function ClipSampler.add(a: Offsets, b: Offsets, weight: number): Offsets
	local result: Offsets = {}
	for name, offset in a do
		result[name] = { pos = table.clone(offset.pos), rot = table.clone(offset.rot) }
	end
	for name, offset in b do
		local base = result[name] or { pos = ZERO, rot = ZERO }
		result[name] = {
			pos = { base.pos[1] + offset.pos[1] * weight, base.pos[2] + offset.pos[2] * weight, base.pos[3] + offset.pos[3] * weight },
			rot = { base.rot[1] + offset.rot[1] * weight, base.rot[2] + offset.rot[2] * weight, base.rot[3] + offset.rot[3] * weight },
		}
	end
	return result
end

return ClipSampler
