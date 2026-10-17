--!strict
--[[
	The PoseEditor's Session: key and event edits keep their lists sorted, carry notes and joint
	order along, clamp into the clip, and undo / redo restore exact snapshots.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local root = Harness.repoRoot()

local cache: { [string]: any } = {}
local loadTool
function loadTool(path: string): any
	if cache[path] then
		return cache[path]
	end
	local source = fs.readFile(root .. "/tools/PoseEditor/src/" .. path .. ".luau")
	local env = {
		script = {
			Parent = setmetatable({}, {
				__index = function(_self: any, name: string)
					return name
				end,
			}),
		},
		require = function(target: any)
			return loadTool(tostring(target))
		end,
	}
	local result = luau.load(source, { debugName = path, environment = env :: any })()
	cache[path] = result
	return result
end

local Serialize = loadTool("Serialize")
local Session = loadTool("Session")

local function sample(): any
	return {
		id = "player/OneHandedSword/Test",
		rig = "PlayerR15",
		duration = 1,
		loop = false,
		layer = "FullBody",
		keys = {
			{ time = 0, easing = "QuadOut", joints = { Waist = { rot = { 0, 0, 0 } }, Neck = { rot = { 1, 0, 0 } } } },
			{ time = 0.5, easing = "ExpoOut", joints = { Waist = { rot = { 0, 40, 0 } } } },
			{ time = 1, easing = "Spring", joints = { Waist = { rot = { 0, 35, 0 } } } },
		},
		events = {
			{ time = 0.2, kind = "TrailOn" },
			{ time = 0.6, kind = "TrailOff" },
		},
	}
end

local function meta(): any
	return {
		header = "test header",
		keyNotes = { [1] = "ready", [3] = "settle" },
		jointOrder = { [1] = { "Waist", "Neck" } },
	}
end

describe("Session keys", function()
	it("starts with the first key selected and scrubs onto keys", function()
		local session = Session.new(sample(), meta())
		expect(session.selectedKey).toBe(1)
		expect(Session.scrub(session, 0.5001, 0.001)).toBe(2)
		expect(session.selectedKey).toBe(2)
		expect(Session.scrub(session, 0.3, 0.001)).toBeNil()
		expect(session.time).toBeCloseTo(0.3)
		expect(Session.scrub(session, 5, 0.001)).toBe(3)
		expect(session.time).toBe(1)
		expect(Session.nearestKey(session, 0.4)).toBe(2)
	end)

	it("inserts a key in time order with the sampled pose and carries notes along", function()
		local session = Session.new(sample(), meta())
		local index = Session.insertKey(session, 0.25, "SineInOut", { Waist = { rot = { 0, 20, 0 } } }, 0.001)
		expect(index).toBe(2)
		expect(#session.clip.keys).toBe(4)
		expect(session.clip.keys[2].time).toBe(0.25)
		expect(session.clip.keys[2].easing).toBe("SineInOut")
		expect(session.clip.keys[3].time).toBe(0.5)
		expect(session.meta.keyNotes[1]).toBe("ready")
		expect(session.meta.keyNotes[4]).toBe("settle")
		expect(session.meta.keyNotes[3]).toBeNil()
		expect(session.selectedKey).toBe(2)
		expect(session.dirty).toBe(true)
		-- inserting onto an existing key selects it instead
		expect(Session.insertKey(session, 0.5, "Hold", {}, 0.001)).toBe(3)
		expect(#session.clip.keys).toBe(4)
	end)

	it("moves a key and re-sorts, tracking the selection", function()
		local session = Session.new(sample(), meta())
		Session.selectKey(session, 1)
		local newIndex = Session.setKeyTime(session, 1, 0.75)
		expect(newIndex).toBe(2)
		expect(session.selectedKey).toBe(2)
		expect(session.clip.keys[1].time).toBe(0.5)
		expect(session.clip.keys[2].time).toBe(0.75)
		expect(session.meta.keyNotes[2]).toBe("ready")
		expect(session.meta.jointOrder[2]).toEqual({ "Waist", "Neck" })
		-- Clamped to the duration; equal times keep their order, so the moved key stays second.
		expect(Session.setKeyTime(session, 2, 9)).toBe(2)
		expect(session.clip.keys[2].time).toBe(1)
		expect(session.clip.keys[3].time).toBe(1)
	end)

	it("deletes a key but never the last one", function()
		local session = Session.new(sample(), meta())
		expect(Session.deleteKey(session, 1)).toBe(true)
		expect(#session.clip.keys).toBe(2)
		expect(session.meta.keyNotes[2]).toBe("settle")
		expect(session.meta.keyNotes[1]).toBeNil()
		expect(Session.deleteKey(session, 1)).toBe(true)
		expect(Session.deleteKey(session, 1)).toBe(false)
		expect(#session.clip.keys).toBe(1)
	end)

	it("sets, nudges and removes joints, recording the order of new joints", function()
		local session = Session.new(sample(), meta())
		Session.nudgeJoint(session, 1, "Waist", nil, { 5, 0, 0 })
		expect(session.clip.keys[1].joints.Waist.rot).toEqual({ 5, 0, 0 })
		Session.nudgeJoint(session, 1, "RightShoulder", { 0.1, 0, 0 }, { 0, 0, -10 }, { rot = { 30, 0, 0 } })
		expect(session.clip.keys[1].joints.RightShoulder).toEqual({ pos = { 0.1, 0, 0 }, rot = { 30, 0, -10 } })
		expect(session.meta.jointOrder[1]).toEqual({ "Waist", "Neck", "RightShoulder" })
		Session.setJoint(session, 1, "Neck", nil)
		expect(session.clip.keys[1].joints.Neck).toBeNil()
		Session.setEasing(session, 2, "BackOut")
		expect(session.clip.keys[2].easing).toBe("BackOut")
		Session.setRoot(session, 2, { pos = { 0, 0, -1 } })
		expect(session.clip.keys[2].root).toEqual({ pos = { 0, 0, -1 } })
		Session.setKeyNote(session, 2, "the cut")
		expect(session.meta.keyNotes[2]).toBe("the cut")
	end)
end)

describe("Session events, beats and fields", function()
	it("adds, edits and removes events in time order", function()
		local session = Session.new(sample(), meta())
		expect(Session.addEvent(session, 0.4, "HitWindowOpen", { hit = 1 })).toBe(2)
		expect(Session.addEvent(session, 0.5, "HitWindowClose")).toBe(3)
		expect(session.clip.events[4].kind).toBe("TrailOff")
		expect(Session.setEvent(session, 1, { time = 0.9 })).toBe(4)
		expect(session.clip.events[4].kind).toBe("TrailOn")
		expect(Session.setEvent(session, 1, { kind = "SmearOn", data = { axis = "X" } })).toBe(1)
		expect(session.clip.events[1].data).toEqual({ axis = "X" })
		expect(Session.setEvent(session, 1, { data = false })).toBe(1)
		expect(session.clip.events[1].data).toBeNil()
		expect(Session.removeEvent(session, 4)).toBe(true)
		expect(#session.clip.events).toBe(3)
		expect(Session.removeEvent(session, 9)).toBe(false)
	end)

	it("sets beats and top-level fields; shrinking the duration clamps keys and events", function()
		local session = Session.new(sample(), meta())
		Session.setBeat(session, "Snap", 0.5, 0.55)
		expect(session.clip.beats.Snap).toEqual({ start = 0.5, finish = 0.55 })
		Session.setBeat(session, "Hold", 0.6, 0.5)
		expect(session.clip.beats.Hold.finish).toBe(0.6)
		Session.setField(session, "hitStop", "Final")
		expect(session.clip.hitStop).toBe("Final")
		Session.setField(session, "duration", 0.55)
		expect(session.clip.keys[3].time).toBe(0.55)
		expect(session.clip.events[2].time).toBe(0.55)
		expect(function()
			Session.setField(session, "id", "other")
		end).toThrow("not editable")
	end)

	it("lists joint names with the rig order first", function()
		local session = Session.new(sample(), meta())
		expect(Session.jointNames(session, { "Root", "Waist", "Neck" })).toEqual({ "Root", "Waist", "Neck" })
		expect(Session.jointNames(session)).toEqual({ "Neck", "Waist" })
	end)
end)

describe("Session undo and redo", function()
	it("restores exact snapshots and clears redo on a new edit", function()
		local session = Session.new(sample(), meta())
		local before = Serialize.clone(session.clip)
		Session.setEasing(session, 2, "BackOut")
		Session.addEvent(session, 0.1, "Sfx")
		expect(Session.undo(session)).toBe(true)
		expect(#session.clip.events).toBe(2)
		expect(session.clip.keys[2].easing).toBe("BackOut")
		expect(Session.undo(session)).toBe(true)
		expect(session.clip).toEqual(before)
		expect(Session.undo(session)).toBe(false)
		expect(Session.redo(session)).toBe(true)
		expect(session.clip.keys[2].easing).toBe("BackOut")
		Session.setEasing(session, 2, "Spring")
		expect(Session.redo(session)).toBe(false)
	end)

	it("source() serializes the edited clip with its comments", function()
		local session = Session.new(sample(), meta())
		Session.setKeyNote(session, 2, "the cut")
		local source = Session.source(session, { "Waist", "Neck" })
		expect(source).toContain("-- ready")
		expect(source).toContain("-- the cut")
		expect(source).toContain("test header")
		expect(Serialize.parse(source).keys[2].easing).toBe("ExpoOut")
		Session.markSaved(session)
		expect(session.dirty).toBe(false)
	end)
end)

describe("Session invalidation hook", function()
	it("reports the clip after every edit of it, and never on reads or meta-only edits", function()
		local calls: { any } = {}
		Session.setInvalidator(function(clip)
			table.insert(calls, clip)
		end)
		local session = Session.new(sample(), meta())
		Session.scrub(session, 0.5, 0.001)
		Session.selectKey(session, 1)
		Session.jointNames(session)
		Session.setKeyNote(session, 1, "meta only")
		expect(#calls).toBe(0)
		Session.setJoint(session, 1, "RightShoulder", { rot = { 1, 2, 3 } })
		expect(#calls).toBe(1)
		expect(calls[1]).toBe(session.clip)
		expect(Session.insertKey(session, 0.25, "Hold", {}, 0.001)).toBe(2)
		expect(#calls).toBe(2)
		-- Selecting an existing key instead of inserting changes nothing.
		Session.insertKey(session, 0.5, "Hold", {}, 0.001)
		expect(#calls).toBe(2)
		Session.setField(session, "duration", 0.9)
		Session.addEvent(session, 0.1, "Sfx")
		Session.setBeat(session, "Snap", 0.1, 0.2)
		Session.setRoot(session, 1, { pos = { 0, 0, -1 } })
		Session.setEasing(session, 1, "Spring")
		Session.setKeyTime(session, 1, 0.3)
		Session.setEvent(session, 1, { kind = "TrailOn" })
		expect(#calls).toBe(9)
		expect(Session.removeEvent(session, 99)).toBe(false)
		expect(Session.deleteKey(session, 99)).toBe(false)
		expect(#calls).toBe(9)
		expect(Session.removeEvent(session, 1)).toBe(true)
		expect(Session.deleteKey(session, 1)).toBe(true)
		expect(#calls).toBe(11)
		-- Undo and redo swap the clip table in; the one now live is the one reported.
		local live = session.clip
		expect(Session.undo(session)).toBe(true)
		expect(#calls).toBe(12)
		expect(calls[12]).toBe(session.clip)
		expect(calls[12]).never.toBe(live)
		expect(Session.redo(session)).toBe(true)
		expect(calls[13]).toBe(live)
		Session.setInvalidator(nil)
		Session.setEasing(session, 1, "BackOut")
		expect(#calls).toBe(13)
	end)

	it("keeps ClipSampler's cached joint list in step with edits when wired to it", function()
		local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
		Session.setInvalidator(ClipSampler.invalidate)
		local session = Session.new(sample(), meta())
		expect(ClipSampler.jointNames(session.clip)).toEqual({ "Neck", "Waist" })
		expect(ClipSampler.sample(session.clip, 0.5).RightShoulder).toBeNil()
		Session.setJoint(session, 2, "RightShoulder", { rot = { 10, 0, 0 } })
		expect(ClipSampler.jointNames(session.clip)).toEqual({ "Neck", "RightShoulder", "Waist" })
		expect(ClipSampler.sample(session.clip, 0.5).RightShoulder.rot[1]).toBe(10)
		Session.setJoint(session, 2, "RightShoulder", nil)
		expect(ClipSampler.jointNames(session.clip)).toEqual({ "Neck", "Waist" })
		Session.setRoot(session, 1, { pos = { 0, 0, -1 } })
		expect(ClipSampler.rootMotionAt(session.clip, 0)).toEqual({ 0, 0, -1 })
		Session.undo(session)
		expect(ClipSampler.rootMotionAt(session.clip, 0)).toEqual({ 0, 0, 0 })
		Session.setInvalidator(nil)
	end)
end)
