--!strict
-- F8 (REVIEW issue 10): the parry's two answers, played through the real Mixer over the pose each
-- rig holds at the clash (the player's Guard, the kobold's landed chop). On the old clips both rigs
-- jumped in one frame (blendIn 0.02 from far-off poses), the deflect landed 7 frames after the
-- clash, and the kobold stood upright again by 0.4 s of its 1.0 s stagger.
local Mixer = Harness.load("src/client/choreo/Mixer")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Combat = Harness.load("src/shared/data/combat")

local FRAME = 1 / 60
local EPSILON = 1e-6
-- Authored key times are rounded to 1e-4 s (0.0667 for 4 frames).
local FRAME_SLACK = 0.01

local PARRY = "player/OneHandedSword/Parry"
local GUARD = "player/OneHandedSword/Guard"
local STAGGER = "enemy/Kobold/Stagger"
local OVERHEAD = "enemy/Kobold/Overhead"

local ARM = { "RightShoulder", "RightElbow", "RightWrist", "Weapon", "LeftShoulder", "Waist" }
local BODY = { "Root", "Neck", "RightShoulder", "LeftShoulder", "Weapon", "LeftHip", "RightHip" }

-- No one frame may carry more than this share of a joint's move into the answer's pose.
local MAX_FRAME_SHARE = 0.6
-- A joint that moves less than this (degrees) is too small to pop.
local MIN_MOVE = 10

local function distance(a: { number }, b: { number }): number
	local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function rotOf(offsets: any, name: string): { number }
	local offset = offsets[name]
	return if offset ~= nil then offset.rot else { 0, 0, 0 }
end

-- The key an answer lands on: the one before its first "Hold"-eased key (the pose it holds).
local function landing(clip: any): (number, any)
	for index, key in clip.keys do
		if key.easing == "Hold" and index > 1 then
			local time = clip.keys[index - 1].time
			return time, ClipSampler.sample(clip, time)
		end
	end
	error(clip.id .. " has no authored hold")
end

-- Plays `under` (from `underStart`, at full weight) for a frame, then the answer, and returns
-- the pose before the answer and the pose on each of the next `count` frames.
local function trace(underId: string, underStart: number, answerId: string, count: number): (any, { any })
	local mixer = Mixer.new()
	mixer:play(ClipLibrary.get(underId), { startTime = underStart, blendIn = 0 })
	local before = mixer:step(FRAME).offsets
	mixer:play(ClipLibrary.get(answerId))
	local poses = {}
	for _ = 1, count do
		table.insert(poses, mixer:step(FRAME).offsets)
	end
	return before, poses
end

-- Every problem of an answer's first frames: it lands 2 to 4 frames after the clash, is fully in
-- by then, and no frame carries more than MAX_FRAME_SHARE of a joint's move.
local function easeProblems(underId: string, underStart: number, answerId: string, joints: { string }): { string }
	local clip = ClipLibrary.get(answerId)
	local time, pose = landing(clip)
	local problems = {}
	local frames = time / FRAME
	if frames < 2 - FRAME_SLACK or frames > 4 + FRAME_SLACK then
		table.insert(problems, ("%s lands %.2f frames after the clash (want 2..4)"):format(answerId, frames))
	end
	local landed = math.max(1, math.floor(frames + 0.5))
	local before, poses = trace(underId, underStart, answerId, landed)
	for _, name in joints do
		local target = rotOf(pose, name)
		local total = distance(rotOf(before, name), target)
		local reached = distance(rotOf(poses[landed], name), target)
		if reached > 3 then
			table.insert(problems, ("%s %s is %.1f deg short on frame %d"):format(answerId, name, reached, landed))
		end
		if total >= MIN_MOVE then
			local previous = before
			for index, current in poses do
				local step = distance(rotOf(previous, name), rotOf(current, name))
				if step > MAX_FRAME_SHARE * total + EPSILON then
					table.insert(
						problems,
						("%s %s moves %.0f%% of its %.0f deg in frame %d"):format(
							answerId,
							name,
							100 * step / total,
							total,
							index
						)
					)
				end
				previous = current
			end
		end
	end
	return problems
end

describe("the parry's deflect (F8)", function()
	it("lands 2 to 4 frames after the clash from the guard, eased in, never in one frame", function()
		local problems = easeProblems(GUARD, 0.5, PARRY, ARM)
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("holds the deflect on the clash for at least 2 frames before it settles", function()
		local clip = ClipLibrary.get(PARRY)
		for index, key in clip.keys do
			if key.easing == "Hold" and index > 1 then
				expect(key.time - clip.keys[index - 1].time).toBeGreaterThanOrEqual(2 * FRAME - EPSILON)
				return
			end
		end
		error("no hold")
	end)

	it("starts from the guard it answers: key 0 is the Guard clip's pose", function()
		local parry = ClipSampler.sample(ClipLibrary.get(PARRY), 0)
		local guard = ClipSampler.sample(ClipLibrary.get(GUARD), 0)
		for _, name in ARM do
			expect(distance(rotOf(parry, name), rotOf(guard, name))).toBeLessThan(1)
		end
	end)
end)

describe("the kobold's parry stagger (F8)", function()
	it("reels back 2 to 4 frames after the clash from its landed chop, eased in", function()
		-- The client's chop is on the server's beat (D-172): the parry is heard as it lands (1.35 s)
		-- or a latency later, in its hold or its rebound.
		for _, start in { 1.35, 1.4, 1.45 } do
			local problems = easeProblems(OVERHEAD, start, STAGGER, BODY)
			expect(table.concat(problems, "\n")).toBe("")
		end
	end)

	it("holds the reeled silhouette for most of its 1.0 s", function()
		local clip = ClipLibrary.get(STAGGER)
		local time, reel = landing(clip)
		local stance = ClipSampler.sample(clip, clip.duration)
		local function away(pose: any): number
			local sum = 0
			for _, name in BODY do
				sum += distance(rotOf(pose, name), rotOf(stance, name))
			end
			return sum
		end
		local reeled = away(reel)
		expect(reeled).toBeGreaterThan(100)
		local untilTime = 0.6 * Combat.parryStagger
		local t = time
		while t <= untilTime + EPSILON do
			local share = away(ClipSampler.sample(clip, t)) / reeled
			if share < 0.6 then
				error(("at %.3f s the stagger is %.0f%% of its reel"):format(t, 100 * share))
			end
			t += FRAME
		end
		-- And it is back in the stance when the server's stagger ends.
		expect(away(ClipSampler.sample(clip, Combat.parryStagger))).toBeLessThan(1)
	end)
end)
