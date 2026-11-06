--!strict
--[[
	The strike snap's ease (section 10 "Snap (2 to 4 frames)", issue 4; combat.luau snapEase).

	The review saw the snap move the blade in one frame: ExpoOut put about 87% of a 3-frame snap's
	travel into its first 60 fps frame. A strike snap (an ExpoOut key of an attack clip whose
	segment opens a hit window) now eases with a normalized exponential, so the blade's travel is
	spread over the snap's frames while the path, the key it lands on and the time it lands stay
	the same. Every player attack is measured on the hit matrix's body (the TrailEnd the trails
	draw from), at every quarter-frame phase of the 60 fps frames against the clip.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local Easing = Harness.load("src/shared/util/Easing")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers")

local FRAME = 1 / 60
local PHASES = { 0, 0.25, 0.5, 0.75 }
-- The most of a snap's travel one 60 fps frame may show, and the least share a frame needs to
-- count as showing it: a 3-frame snap must read over at least 2 frames.
local MAX_FRAME_SHARE = 0.6
local VISIBLE_SHARE = 0.1

local root = Harness.repoRoot()

-- tools/ modules are plain Lune scripts: load one with only Lune's own libraries to require.
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")

local ATTACKS = { "Basic1", "Basic2", "Basic3", "Horizontal", "Vertical", "RisingArc", "SharpNail" }

local body: any = nil
local function avatar(): any
	if body == nil then
		body = HitMatrix.standing(Harness)
	end
	return body
end

local function tipAt(clip: any, time: number): Vector3
	local current = avatar()
	local tip = current.model:FindFirstChild("TrailEnd", true)
	local position = Pose.attachmentPosition(current.model, current.root.CFrame, ClipSampler.sample(clip, time), tip)
	assert(position ~= nil, "no TrailEnd")
	return position :: Vector3
end

-- Each rendered frame's share of the tip's travel over a snap, frames at `phase` of a frame from
-- the snap's start (the first frame drawn inside it shows the travel up to there).
local function shares(clip: any, snap: any, phase: number): { number }
	local times = { snap.start }
	local t = snap.start + phase * FRAME
	if t <= snap.start then
		t += FRAME
	end
	while t < snap.finish - 1e-9 do
		table.insert(times, t)
		t += FRAME
	end
	table.insert(times, snap.finish)
	local steps: { number } = {}
	local total = 0
	for index = 2, #times do
		local step = (tipAt(clip, times[index]) - tipAt(clip, times[index - 1])).Magnitude
		table.insert(steps, step)
		total += step
	end
	for index, step in steps do
		steps[index] = if total > 0 then step / total else 0
	end
	return steps
end

local function attackClip(name: string): any
	return Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
end

describe("Strike snaps spread over their frames (issue 4)", function()
	it("no 60 fps frame shows more than 60% of a player strike's snap, and each reads over 2+ frames", function()
		local worst = 0
		for _, name in ATTACKS do
			local clip = attackClip(name)
			local snaps = ReviewMarkers.strikeSnaps(clip)
			expect(#snaps > 0).toBe(true)
			for index, snap in snaps do
				for _, phase in PHASES do
					local frameShares = shares(clip, snap, phase)
					local visible = 0
					for _, share in frameShares do
						worst = math.max(worst, share)
						if share >= VISIBLE_SHARE then
							visible += 1
						end
					end
					if visible < 2 then
						error(("%s snap %d at phase %.2f reads in %d frame(s)"):format(name, index, phase, visible))
					end
				end
			end
		end
		expect(worst <= MAX_FRAME_SHARE).toBe(true)
	end)

	it("keeps each snap's 2 to 4 frames, its path and its landing: only the timing along the cut changes", function()
		for _, name in ATTACKS do
			local clip = attackClip(name)
			for index = 2, #clip.keys do
				if ClipSampler.isStrikeSnap(clip, index) then
					local from, to = clip.keys[index - 1], clip.keys[index]
					local frames = (to.time - from.time) / FRAME
					expect(frames >= Dev.review.snapFrames.min - 1e-6).toBe(true)
					expect(frames <= Dev.review.snapFrames.max + 1e-6).toBe(true)
					-- Lands on the key at the key's time.
					local landed = ClipSampler.sample(clip, to.time)
					for joint, value in to.joints do
						if value.rot ~= nil then
							expect(math.abs(landed[joint].rot[1] - value.rot[1]) < 1e-6).toBe(true)
						end
					end
					-- Every sample inside lies on the straight blend from one key to the other: the
					-- same alpha for every joint, the snap ease's at that time.
					for _, u in { 0.2, 0.5, 0.8 } do
						local time = from.time + (to.time - from.time) * u
						local alpha = ClipSampler.snapEase(u)
						local before = ClipSampler.sample(clip, from.time)
						local after = ClipSampler.sample(clip, to.time)
						local inside = ClipSampler.sample(clip, time)
						for joint, value in inside do
							for axis = 1, 3 do
								local a, b = before[joint].rot[axis], after[joint].rot[axis]
								local expected = a + (b - a) * alpha
								if math.abs(value.rot[axis] - expected) > 1e-6 then
									error(("%s %s axis %d off the blend at u %.1f"):format(name, joint, axis, u))
								end
							end
						end
					end
				end
			end
		end
	end)

	it("finds every strike snap the review pairs with a window, and only those", function()
		for _, name in ATTACKS do
			local clip = attackClip(name)
			local found = 0
			for index = 2, #clip.keys do
				if ClipSampler.isStrikeSnap(clip, index) then
					found += 1
				end
			end
			expect(found).toBe(#ClipSampler.hitWindows(clip))
			local snaps = ReviewMarkers.strikeSnaps(clip)
			expect(#snaps).toBe(found)
			for _, snap in snaps do
				local index = nil
				for keyIndex, key in clip.keys do
					if math.abs(key.time - snap.finish) < 1e-6 then
						index = keyIndex
					end
				end
				expect(index ~= nil and ClipSampler.isStrikeSnap(clip, index)).toBe(true)
			end
		end
	end)

	it("eases with the data's normalized exponential, from 0 to 1, each frame about half the last", function()
		local s = Combat.snapEase.sharpness
		expect(s > 0).toBe(true)
		expect(ClipSampler.snapEase(0)).toBe(0)
		expect(ClipSampler.snapEase(1)).toBe(1)
		expect(ClipSampler.snapEase(-1)).toBe(0)
		expect(ClipSampler.snapEase(2)).toBe(1)
		local u = 0.37
		expect(math.abs(ClipSampler.snapEase(u) - (1 - 2 ^ (-s * u)) / (1 - 2 ^ -s)) < 1e-12).toBe(true)
		local previous = 0
		for step = 1, 20 do
			local value = ClipSampler.snapEase(step / 20)
			expect(value > previous).toBe(true)
			previous = value
		end
	end)
end)

describe("Strike snap ease guards", function()
	local function clipWith(attack: boolean?, windowAt: number?): any
		return {
			id = "test/snap",
			rig = "PlayerR15",
			duration = 1,
			loop = false,
			layer = "FullBody",
			attack = attack,
			keys = {
				{ time = 0.3, easing = "QuadIn", joints = { RightShoulder = { rot = { 0, 0, 0 } } } },
				{ time = 0.35, easing = "ExpoOut", joints = { RightShoulder = { rot = { 90, 0, 0 } } } },
				{ time = 0.6, easing = "ExpoOut", joints = { RightShoulder = { rot = { 0, 0, 0 } } } },
			},
			events = if windowAt ~= nil
				then {
					{ time = windowAt, kind = "HitWindowOpen", data = { hit = 1 } },
					{ time = 0.45, kind = "HitWindowClose", data = { hit = 1 } },
				}
				else {},
		}
	end

	it("leaves ExpoOut alone off strike snaps: no window, not an attack, a window after the snap", function()
		local time = 0.3 + 0.05 / 3
		local expo = 90 * Easing.ExpoOut(1 / 3)
		for _, case in { clipWith(true, nil), clipWith(nil, 0.3), clipWith(false, 0.3), clipWith(true, 0.36) } do
			expect(math.abs(ClipSampler.sample(case, time).RightShoulder.rot[1] - expo) < 1e-6).toBe(true)
		end
		-- The later ExpoOut key (the settle back) is no snap either.
		local snapped = clipWith(true, 0.3)
		expect(ClipSampler.isStrikeSnap(snapped, 2)).toBe(true)
		expect(ClipSampler.isStrikeSnap(snapped, 3)).toBe(false)
		local back = 90 - 90 * Easing.ExpoOut(0.5)
		expect(math.abs(ClipSampler.sample(snapped, 0.475).RightShoulder.rot[1] - back) < 1e-6).toBe(true)
	end)

	it("eases a strike snap with snapEase", function()
		local snapped = clipWith(true, 0.3)
		local time = 0.3 + 0.05 / 3
		local expected = 90 * ClipSampler.snapEase(1 / 3)
		expect(math.abs(ClipSampler.sample(snapped, time).RightShoulder.rot[1] - expected) < 1e-6).toBe(true)
		expect(expected < 90 * Easing.ExpoOut(1 / 3)).toBe(true)
	end)
end)
