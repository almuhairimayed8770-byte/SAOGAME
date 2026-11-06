--!strict
--[[
	Session: the PoseEditor's editing state and every operation on it, as pure functions over
	plain clip data (no Instances, so Lune tests cover each rule). The plugin UI calls these and
	then re-poses the rig; nothing here knows about Handles or widgets.

	Keys stay sorted by time and events by time after every edit; an edit returns the new index
	of the thing it touched. Every mutating operation pushes an undo snapshot first and, once it
	has changed the clip table, reports it through the invalidator the plugin host registers
	(`Session.setInvalidator(ClipSampler.invalidate)`), so the sampler's per-clip cache follows
	the edit. Session runs under Lune without a DataModel and cannot require shared modules itself.
]]

local Serialize = require(script.Parent.Serialize)

export type Offset = { pos: { number }?, rot: { number }? }

export type Session = {
	clip: any,
	meta: Serialize.Meta,
	time: number, -- scrub position, seconds
	selectedKey: number?, -- index into clip.keys
	selectedJoint: string?,
	undo: { any }, -- snapshots of { clip, meta }
	redo: { any },
	dirty: boolean,
	maxUndo: number,
}

local Session = {}

local EPSILON = 1e-9
local DEFAULT_MAX_UNDO = 64

-- Called with the session's clip after every edit of it; nil until the host registers one.
local invalidate: ((clip: any) -> ())? = nil

local function copyMeta(meta: Serialize.Meta): Serialize.Meta
	return Serialize.clone(meta)
end

-- Reports that the session's clip table changed (the sampler's cache is keyed by that table).
local function changed(session: Session)
	if invalidate ~= nil then
		invalidate(session.clip)
	end
end

--- Registers the function called with the session's clip after every edit of it: the plugin
--- host passes ClipSampler.invalidate so the sampler's per-clip cache follows the edit. nil clears it.
function Session.setInvalidator(fn: ((clip: any) -> ())?)
	invalidate = fn
end

--- Starts a session on a parsed clip (and the comments the parser kept).
function Session.new(clip: any, meta: Serialize.Meta?, maxUndo: number?): Session
	return {
		clip = Serialize.clone(clip),
		meta = if meta then copyMeta(meta) else { header = nil, keyNotes = {}, jointOrder = {} },
		time = 0,
		selectedKey = if #clip.keys > 0 then 1 else nil,
		selectedJoint = nil,
		undo = {},
		redo = {},
		dirty = false,
		maxUndo = maxUndo or DEFAULT_MAX_UNDO,
	}
end

local function snapshot(session: Session)
	table.insert(session.undo, { clip = Serialize.clone(session.clip), meta = copyMeta(session.meta) })
	while #session.undo > session.maxUndo do
		table.remove(session.undo, 1)
	end
	table.clear(session.redo)
	session.dirty = true
end

--- Restores the previous snapshot; false when there is none.
function Session.undo(session: Session): boolean
	local last = table.remove(session.undo)
	if last == nil then
		return false
	end
	table.insert(session.redo, { clip = session.clip, meta = session.meta })
	session.clip = last.clip
	session.meta = last.meta
	Session.clampSelection(session)
	changed(session)
	return true
end

--- Re-applies an undone edit; false when there is none.
function Session.redo(session: Session): boolean
	local next = table.remove(session.redo)
	if next == nil then
		return false
	end
	table.insert(session.undo, { clip = session.clip, meta = session.meta })
	session.clip = next.clip
	session.meta = next.meta
	Session.clampSelection(session)
	changed(session)
	return true
end

--- Keeps the selected key inside the key list after a structural change.
function Session.clampSelection(session: Session)
	local count = #session.clip.keys
	if count == 0 then
		session.selectedKey = nil
	elseif session.selectedKey ~= nil and session.selectedKey > count then
		session.selectedKey = count
	end
end

--- The index of the key at `time` (within `tolerance` seconds), or nil.
function Session.keyAt(session: Session, time: number, tolerance: number): number?
	for index, key in ipairs(session.clip.keys) do
		if math.abs(key.time - time) <= tolerance then
			return index
		end
	end
	return nil
end

--- The nearest key index to `time` (nil for an empty clip).
function Session.nearestKey(session: Session, time: number): number?
	local best: number? = nil
	local bestDistance = math.huge
	for index, key in ipairs(session.clip.keys) do
		local distance = math.abs(key.time - time)
		if distance < bestDistance then
			bestDistance = distance
			best = index
		end
	end
	return best
end

--- Moves the scrub time (clamped to the clip) and selects the key sitting there, if any.
function Session.scrub(session: Session, time: number, tolerance: number): number?
	session.time = math.clamp(time, 0, session.clip.duration)
	local index = Session.keyAt(session, session.time, tolerance)
	if index ~= nil then
		session.selectedKey = index
	end
	return index
end

--- Selects a key by index and moves the scrub time onto it.
function Session.selectKey(session: Session, index: number)
	local key = session.clip.keys[index]
	if key == nil then
		error(("Session.selectKey: no key %d"):format(index))
	end
	session.selectedKey = index
	session.time = key.time
end

-- Re-sorts the keys (stable on equal times) and carries notes / joint order with them.
local function resortKeys(session: Session, trackedIndex: number?): number?
	local keys = session.clip.keys
	local entries = {}
	for index, key in ipairs(keys) do
		table.insert(entries, {
			key = key,
			note = session.meta.keyNotes[index],
			order = session.meta.jointOrder[index],
			original = index,
		})
	end
	table.sort(entries, function(a, b)
		if math.abs(a.key.time - b.key.time) <= EPSILON then
			return a.original < b.original
		end
		return a.key.time < b.key.time
	end)
	local newKeys = {}
	local notes = {}
	local orders = {}
	local tracked: number? = nil
	for index, entry in entries do
		newKeys[index] = entry.key
		notes[index] = entry.note
		orders[index] = entry.order
		if entry.original == trackedIndex then
			tracked = index
		end
	end
	session.clip.keys = newKeys
	session.meta.keyNotes = notes
	session.meta.jointOrder = orders
	return tracked
end

--- Inserts a key at `time` holding `offsets` (the pose sampled there); returns its index.
--- An existing key within `tolerance` is selected instead and nothing is inserted.
function Session.insertKey(
	session: Session,
	time: number,
	easing: string,
	offsets: { [string]: Offset },
	tolerance: number
): number
	local existing = Session.keyAt(session, time, tolerance)
	if existing ~= nil then
		session.selectedKey = existing
		return existing
	end
	snapshot(session)
	local joints = {}
	for name, offset in offsets do
		joints[name] = Serialize.clone(offset)
	end
	local clamped = math.clamp(time, 0, session.clip.duration)
	table.insert(session.clip.keys, { time = clamped, easing = easing, joints = joints })
	local index = resortKeys(session, #session.clip.keys) :: number
	session.selectedKey = index
	session.time = clamped
	changed(session)
	return index
end

--- Deletes a key (never the last one); returns true when something was removed.
function Session.deleteKey(session: Session, index: number): boolean
	local keys = session.clip.keys
	if keys[index] == nil or #keys <= 1 then
		return false
	end
	snapshot(session)
	table.remove(keys, index)
	local notes = {}
	local orders = {}
	for newIndex = 1, #keys do
		local oldIndex = if newIndex >= index then newIndex + 1 else newIndex
		notes[newIndex] = session.meta.keyNotes[oldIndex]
		orders[newIndex] = session.meta.jointOrder[oldIndex]
	end
	session.meta.keyNotes = notes
	session.meta.jointOrder = orders
	Session.clampSelection(session)
	changed(session)
	return true
end

--- Moves a key to a new time (clamped to the clip) and returns its new index.
function Session.setKeyTime(session: Session, index: number, time: number): number
	local key = session.clip.keys[index]
	if key == nil then
		error(("Session.setKeyTime: no key %d"):format(index))
	end
	snapshot(session)
	key.time = math.clamp(time, 0, session.clip.duration)
	local newIndex = resortKeys(session, index) :: number
	if session.selectedKey == index then
		session.selectedKey = newIndex
		session.time = key.time
	end
	changed(session)
	return newIndex
end

--- Sets a key's easing (the curve INTO the key).
function Session.setEasing(session: Session, index: number, easing: string)
	local key = session.clip.keys[index]
	if key == nil then
		error(("Session.setEasing: no key %d"):format(index))
	end
	snapshot(session)
	key.easing = easing
	changed(session)
end

--- Sets a key's note (the comment above it in the source); empty clears it.
function Session.setKeyNote(session: Session, index: number, note: string)
	snapshot(session)
	session.meta.keyNotes[index] = if note == "" then nil else note
end

--- Replaces one joint's offset at a key (nil removes the joint from that key).
function Session.setJoint(session: Session, index: number, joint: string, offset: Offset?)
	local key = session.clip.keys[index]
	if key == nil then
		error(("Session.setJoint: no key %d"):format(index))
	end
	snapshot(session)
	if offset == nil then
		key.joints[joint] = nil
		changed(session)
		return
	end
	local stored: Offset = {}
	if offset.pos ~= nil then
		stored.pos = { offset.pos[1], offset.pos[2], offset.pos[3] }
	end
	if offset.rot ~= nil then
		stored.rot = { offset.rot[1], offset.rot[2], offset.rot[3] }
	end
	if key.joints[joint] == nil then
		local order = session.meta.jointOrder[index]
		if order ~= nil then
			table.insert(order, joint)
		end
	end
	key.joints[joint] = stored
	changed(session)
end

--- Adds a position / rotation delta to a joint at a key, starting from the key's current value
--- (or from `base`, the sampled held value, when the key does not touch that joint yet).
function Session.nudgeJoint(
	session: Session,
	index: number,
	joint: string,
	deltaPos: { number }?,
	deltaRot: { number }?,
	base: Offset?
)
	local key = session.clip.keys[index]
	if key == nil then
		error(("Session.nudgeJoint: no key %d"):format(index))
	end
	local current: Offset = key.joints[joint] or base or {}
	local pos = current.pos
	local rot = current.rot
	if deltaPos ~= nil then
		local p = pos or { 0, 0, 0 }
		pos = { p[1] + deltaPos[1], p[2] + deltaPos[2], p[3] + deltaPos[3] }
	end
	if deltaRot ~= nil then
		local r = rot or { 0, 0, 0 }
		rot = { r[1] + deltaRot[1], r[2] + deltaRot[2], r[3] + deltaRot[3] }
	end
	Session.setJoint(session, index, joint, { pos = pos, rot = rot })
end

--- Sets (or clears) the root-motion offset at a key.
function Session.setRoot(session: Session, index: number, root: Offset?)
	local key = session.clip.keys[index]
	if key == nil then
		error(("Session.setRoot: no key %d"):format(index))
	end
	snapshot(session)
	key.root = if root then Serialize.clone(root) else nil
	changed(session)
end

local function resortEvents(session: Session, tracked: any): number?
	local events = session.clip.events
	local entries = {}
	for index, event in ipairs(events) do
		table.insert(entries, { event = event, original = index })
	end
	table.sort(entries, function(a, b)
		if math.abs(a.event.time - b.event.time) <= EPSILON then
			return a.original < b.original
		end
		return a.event.time < b.event.time
	end)
	local result = {}
	local trackedIndex: number? = nil
	for index, entry in entries do
		result[index] = entry.event
		if entry.event == tracked then
			trackedIndex = index
		end
	end
	session.clip.events = result
	return trackedIndex
end

--- Adds an event and returns its index in time order.
function Session.addEvent(session: Session, time: number, kind: string, data: { [string]: any }?): number
	snapshot(session)
	local event: { [string]: any } = { time = math.clamp(time, 0, session.clip.duration), kind = kind }
	if data ~= nil then
		event.data = Serialize.clone(data)
	end
	table.insert(session.clip.events, event)
	local index = resortEvents(session, event) :: number
	changed(session)
	return index
end

--- Changes an event's time, kind or data; returns its new index.
function Session.setEvent(session: Session, index: number, changes: { time: number?, kind: string?, data: any }): number
	local event = session.clip.events[index]
	if event == nil then
		error(("Session.setEvent: no event %d"):format(index))
	end
	snapshot(session)
	if changes.time ~= nil then
		event.time = math.clamp(changes.time, 0, session.clip.duration)
	end
	if changes.kind ~= nil then
		event.kind = changes.kind
	end
	if changes.data ~= nil then
		event.data = if changes.data == false then nil else Serialize.clone(changes.data)
	end
	local newIndex = resortEvents(session, event) :: number
	changed(session)
	return newIndex
end

--- Removes an event; true when one was removed.
function Session.removeEvent(session: Session, index: number): boolean
	if session.clip.events[index] == nil then
		return false
	end
	snapshot(session)
	table.remove(session.clip.events, index)
	changed(session)
	return true
end

--- Sets one of the six beats (creating the beats table when needed).
function Session.setBeat(session: Session, beat: string, start: number, finish: number)
	snapshot(session)
	local beats = session.clip.beats or {}
	beats[beat] = { start = math.max(0, start), finish = math.max(start, finish) }
	session.clip.beats = beats
	changed(session)
end

--- Sets a top-level field (duration, loop, layer, priority, attack, hitStop, blendIn, blendOut).
--- Shrinking the duration clamps keys and events into it.
function Session.setField(session: Session, field: string, value: any)
	if field == "id" or field == "keys" or field == "events" or field == "beats" or field == "rig" then
		error(("Session.setField: '%s' is not editable here"):format(field))
	end
	snapshot(session)
	session.clip[field] = value
	if field == "duration" and typeof(value) == "number" then
		for _, key in ipairs(session.clip.keys) do
			key.time = math.min(key.time, value)
		end
		for _, event in ipairs(session.clip.events) do
			event.time = math.min(event.time, value)
		end
		resortKeys(session, nil)
		resortEvents(session, nil)
	end
	changed(session)
end

--- Every joint the clip touches plus the rig's joints, sorted; the rig list may be nil.
function Session.jointNames(session: Session, rigJoints: { string }?): { string }
	local seen: { [string]: boolean } = {}
	local names = {}
	if rigJoints ~= nil then
		for _, name in rigJoints do
			if not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
	end
	for _, key in ipairs(session.clip.keys) do
		for name in key.joints do
			if not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
	end
	if rigJoints == nil then
		table.sort(names)
	end
	return names
end

--- The source text the session would save.
function Session.source(session: Session, rigJointOrder: { string }?): string
	return Serialize.toSource(session.clip, { meta = session.meta, jointOrder = rigJointOrder })
end

--- Marks the session saved.
function Session.markSaved(session: Session)
	session.dirty = false
end

return Session
