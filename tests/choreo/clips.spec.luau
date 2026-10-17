--!strict
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Combat = Harness.load("src/shared/data/combat")

local FRAME = 1 / 60
local EPSILON = 1e-6

local PLAYER_ARTS = {
	Horizontal = { hits = 1, total = 0.6, postMotion = 0.4 },
	Vertical = { hits = 1, total = 0.6, postMotion = 0.4 },
	SharpNail = { hits = 3, total = 1.1, postMotion = 0.6 },
	RisingArc = { hits = 2, total = 0.9, postMotion = 0.5 },
}

local ENEMY_ATTACKS = {
	["enemy/Boar/Charge"] = { windUp = 0.6 },
	["enemy/Kobold/Overhead"] = { windUp = 1.0 },
}

local BEATS = { "Anticipation", "Snap", "Smear", "Hold", "Settle", "Recovery" }

local function frames(span)
	return (span.finish - span.start) / FRAME
end

local function attackClips()
	local list = {}
	for _, id in ClipLibrary.all() do
		local clip = ClipLibrary.get(id)
		if clip.attack then
			table.insert(list, clip)
		end
	end
	return list
end

local function eventTimes(clip, kind)
	local times = {}
	for _, event in clip.events do
		if event.kind == kind then
			table.insert(times, event.time)
		end
	end
	return times
end

describe("clip data", function()
	it("every clip starts posed: first key at time 0, keys and events sorted and inside the clip", function()
		for _, id in ClipLibrary.all() do
			local clip = ClipLibrary.get(id)
			expect(clip.keys[1].time).toBe(0)
			local last = -1
			for _, key in clip.keys do
				expect(key.time).toBeGreaterThanOrEqual(last)
				expect(key.time).toBeLessThanOrEqual(clip.duration + EPSILON)
				last = key.time
			end
			last = -1
			for _, event in clip.events do
				expect(event.time).toBeGreaterThanOrEqual(last)
				expect(event.time).toBeLessThanOrEqual(clip.duration + EPSILON)
				last = event.time
			end
		end
	end)

	it("no joint key uses Linear easing (root-only keys may)", function()
		for _, id in ClipLibrary.all() do
			local clip = ClipLibrary.get(id)
			for index, key in clip.keys do
				if key.easing == "Linear" and next(key.joints) ~= nil then
					error(("%s key %d uses Linear on a limb"):format(id, index))
				end
			end
		end
	end)

	it("every attack clip has the six beats, in order, with a 2..4 frame snap and a smear inside the snap", function()
		local attacks = attackClips()
		expect(#attacks).toBe(9)
		for _, clip in attacks do
			expect(clip.beats).toBeTruthy()
			expect(clip.hitStop).toBe("Normal")
			for _, beat in BEATS do
				local span = clip.beats[beat]
				if span == nil then
					error(("%s lacks beat %s"):format(clip.id, beat))
				end
				expect(span.finish).toBeGreaterThanOrEqual(span.start)
			end
			local b = clip.beats
			expect(b.Anticipation.start).toBeLessThan(b.Snap.start)
			expect(b.Snap.start).toBeLessThanOrEqual(b.Smear.start)
			expect(b.Smear.finish).toBeLessThanOrEqual(b.Snap.finish + EPSILON)
			expect(b.Smear.start).toBeLessThan(b.Hold.start)
			expect(b.Hold.start).toBeLessThanOrEqual(b.Settle.start)
			expect(b.Settle.start).toBeLessThan(b.Recovery.start)
			expect(frames(b.Snap)).toBeGreaterThanOrEqual(2 - EPSILON)
			expect(frames(b.Snap)).toBeLessThanOrEqual(4 + EPSILON)
			-- Beat decimals are rounded to four places, so allow a twentieth of a frame.
			expect(frames(b.Smear)).toBeCloseTo(2, 0.05)
			expect(b.Recovery.finish).toBeCloseTo(clip.duration, EPSILON)
		end
	end)

	it("player attack clips hold their anticipation for 4..10 frames", function()
		for _, clip in attackClips() do
			if clip.id:sub(1, 7) == "player/" then
				local count = frames(clip.beats.Anticipation)
				expect(count).toBeGreaterThanOrEqual(4 - 1e-3)
				expect(count).toBeLessThanOrEqual(10 + 1e-3)
			end
		end
	end)

	it("every attack clip settles over 6..12 frames (section 10 beat 5)", function()
		for _, clip in attackClips() do
			local count = frames(clip.beats.Settle)
			if count < 6 - 1e-3 or count > 12 + 1e-3 then
				error(("%s settles over %.1f frames"):format(clip.id, count))
			end
		end
	end)

	it(
		"every attack clip carries trail, smear and hit-window events, balanced and inside the snap-to-settle span",
		function()
			for _, clip in attackClips() do
				local windows = ClipSampler.hitWindows(clip)
				expect(#windows).toBeGreaterThanOrEqual(1)
				expect(#eventTimes(clip, "HitWindowOpen")).toBe(#windows)
				expect(#eventTimes(clip, "HitWindowClose")).toBe(#windows)
				expect(#eventTimes(clip, "TrailOn")).toBeGreaterThanOrEqual(1)
				expect(#eventTimes(clip, "TrailOff")).toBeGreaterThanOrEqual(1)
				expect(#eventTimes(clip, "SmearOn")).toBe(#eventTimes(clip, "SmearOff"))
				expect(#eventTimes(clip, "SmearOn")).toBeGreaterThanOrEqual(1)
				local smearOn = eventTimes(clip, "SmearOn")
				local smearOff = eventTimes(clip, "SmearOff")
				for index, on in smearOn do
					expect(smearOff[index] - on).toBeCloseTo(2 * FRAME, 1e-3)
				end
				expect(smearOn[1]).toBeCloseTo(clip.beats.Snap.start, EPSILON)
				expect(eventTimes(clip, "TrailOn")[1]).toBeLessThanOrEqual(windows[1].open)
				expect(eventTimes(clip, "TrailOff")[1]).toBeGreaterThanOrEqual(windows[#windows].close)
			end
		end
	)

	it(
		"the Phase 0 Arts match the section 8 timeline: hits, ActivationHold at 0.15, PostMotionStart at total, duration = total + post-motion",
		function()
			for name, art in PLAYER_ARTS do
				local clip = ClipLibrary.get("player/OneHandedSword/" .. name)
				expect(clip.attack).toBe(true)
				expect(#ClipSampler.hitWindows(clip)).toBe(art.hits)
				expect(clip.duration).toBeCloseTo(art.total + art.postMotion, EPSILON)
				local activation = eventTimes(clip, "ActivationHold")
				expect(#activation).toBe(1)
				expect(activation[1]).toBeCloseTo(Combat.startPoseTime, EPSILON)
				local post = eventTimes(clip, "PostMotionStart")
				expect(#post).toBe(1)
				expect(post[1]).toBeCloseTo(art.total, EPSILON)
				expect(clip.beats.Recovery.start).toBeCloseTo(art.total, EPSILON)
				-- The first snap comes after the start pose and the activation hold.
				expect(clip.beats.Snap.start).toBeGreaterThanOrEqual(
					Combat.startPoseTime + Combat.activationHold - EPSILON
				)
				-- Every hit window closes by the Art's total.
				for _, window in ClipSampler.hitWindows(clip) do
					expect(window.open).toBeGreaterThan(Combat.startPoseTime + Combat.activationHold)
					expect(window.close).toBeLessThanOrEqual(art.total + EPSILON)
				end
			end
		end
	)

	it("the basic chain hits inside basicHitDuration with a thin trail and no activation hold", function()
		for index = 1, Combat.basicChainLength do
			local clip = ClipLibrary.get("player/OneHandedSword/Basic" .. index)
			expect(clip.attack).toBe(true)
			local windows = ClipSampler.hitWindows(clip)
			expect(#windows).toBe(1)
			expect(windows[1].close).toBeLessThanOrEqual(Combat.basicHitDuration + EPSILON)
			expect(#eventTimes(clip, "ActivationHold")).toBe(0)
			local trailOn
			for _, event in clip.events do
				if event.kind == "TrailOn" then
					trailOn = event
				end
			end
			expect(trailOn.data.kind).toBe("Basic")
		end
	end)

	it("enemy attack clips hold their wind-up for the attack's windUp and carry the hit at the strike", function()
		for id, attack in ENEMY_ATTACKS do
			local clip = ClipLibrary.get(id)
			expect(clip.attack).toBe(true)
			expect(frames(clip.beats.Anticipation) * FRAME).toBeGreaterThanOrEqual(attack.windUp - EPSILON)
			expect(clip.beats.Anticipation.start).toBe(0)
			local windows = ClipSampler.hitWindows(clip)
			expect(#windows).toBe(1)
			expect(windows[1].open).toBeGreaterThan(attack.windUp)
		end
	end)

	it("Arts carry their root motion forward (rig -Z) and the dodges carry dodgeDistance", function()
		local horizontal = ClipLibrary.get("player/OneHandedSword/Horizontal")
		expect(ClipSampler.rootMotionAt(horizontal, horizontal.duration)[3]).toBeCloseTo(-1, EPSILON)
		local sharpNail = ClipLibrary.get("player/OneHandedSword/SharpNail")
		expect(ClipSampler.rootMotionAt(sharpNail, sharpNail.duration)[3]).toBeCloseTo(-2, EPSILON)
		local risingArc = ClipLibrary.get("player/OneHandedSword/RisingArc")
		expect(ClipSampler.rootMotionAt(risingArc, risingArc.duration)[3]).toBeCloseTo(-1, EPSILON)
		local forward = ClipLibrary.get("player/OneHandedSword/DodgeForward")
		expect(ClipSampler.rootMotionAt(forward, forward.duration)[3]).toBeCloseTo(-Combat.dodgeDistance, EPSILON)
		local left = ClipLibrary.get("player/OneHandedSword/DodgeLeft")
		expect(ClipSampler.rootMotionAt(left, left.duration)[1]).toBeCloseTo(-Combat.dodgeDistance, EPSILON)
		expect(ClipSampler.rootMotionAt(left, Combat.dodgeDuration)[1]).toBeCloseTo(-Combat.dodgeDistance, EPSILON)
	end)

	it(
		"Rising Arc sinks, drives up through the legs from low left to high right, carries the blade over the head between the hits and settles back 5..8 degrees",
		function()
			local clip = ClipLibrary.get("player/OneHandedSword/RisingArc")
			local b = clip.beats
			local ready = ClipSampler.sample(clip, 0)
			local wound = ClipSampler.sample(clip, b.Anticipation.finish)
			local snapped = ClipSampler.sample(clip, b.Snap.finish)
			-- The body sinks below the ready stance and the legs drive it up past it on the snap.
			expect(wound.Root.pos[2]).toBeLessThan(ready.Root.pos[2])
			expect(snapped.Root.pos[2]).toBeGreaterThan(ready.Root.pos[2])
			expect(math.abs(snapped.LeftKnee.rot[1])).toBeLessThan(math.abs(wound.LeftKnee.rot[1]))
			expect(math.abs(snapped.RightKnee.rot[1])).toBeLessThan(math.abs(wound.RightKnee.rot[1]))
			-- Low left to high right: the sword arm starts across the body and snaps up and out.
			expect(wound.RightShoulder.rot[3]).toBeLessThan(0)
			expect(snapped.RightShoulder.rot[3]).toBeGreaterThan(0)
			expect(snapped.RightShoulder.rot[1]).toBeGreaterThan(90)
			-- The arm climbs highest (the blade over the head) between the two hit windows.
			local windows = ClipSampler.hitWindows(clip)
			local highest
			for _, key in clip.keys do
				local arm = key.joints.RightShoulder
				if arm ~= nil and (highest == nil or arm.rot[1] > highest.joints.RightShoulder.rot[1]) then
					highest = key
				end
			end
			expect(highest.time).toBeGreaterThan(windows[1].close)
			expect(highest.time).toBeLessThan(windows[2].open)
			-- Both strikes settle (Spring) 5..8 degrees back from their snap (ExpoOut) on the sword arm.
			local settles = 0
			for index, key in clip.keys do
				if key.easing == "Spring" then
					settles += 1
					local snapKey
					for back = index - 1, 1, -1 do
						if clip.keys[back].easing == "ExpoOut" then
							snapKey = clip.keys[back]
							break
						end
					end
					local returned = math.abs(key.joints.RightShoulder.rot[1] - snapKey.joints.RightShoulder.rot[1])
					expect(returned).toBeGreaterThanOrEqual(5)
					expect(returned).toBeLessThanOrEqual(8)
				end
			end
			expect(settles).toBe(2)
		end
	)

	it("timed reaction clips match combat data: stagger, guard break, death freeze, break", function()
		expect(ClipLibrary.get("player/OneHandedSword/Stagger").duration).toBeCloseTo(Combat.staggerDuration, EPSILON)
		expect(ClipLibrary.get("player/OneHandedSword/GuardBreak").duration).toBeCloseTo(
			Combat.guardBreakStagger,
			EPSILON
		)
		for _, id in { "player/OneHandedSword/DeathFreeze", "enemy/Boar/DeathFreeze", "enemy/Kobold/DeathFreeze" } do
			local clip = ClipLibrary.get(id)
			expect(clip.duration).toBeCloseTo(Combat.deathFreeze, EPSILON)
			expect(clip.layer).toBe("Additive")
		end
		for _, rig in { "Boar", "Kobold" } do
			expect(ClipLibrary.get(("enemy/%s/Stagger"):format(rig)).duration).toBeCloseTo(Combat.parryStagger, EPSILON)
			expect(ClipLibrary.get(("enemy/%s/Break"):format(rig)).duration).toBeCloseTo(Combat.breakDuration, EPSILON)
		end
	end)

	it("the post-motion of every Art has micro-motion: the pose keeps changing after PostMotionStart", function()
		for name in PLAYER_ARTS do
			local clip = ClipLibrary.get("player/OneHandedSword/" .. name)
			local start = eventTimes(clip, "PostMotionStart")[1]
			local a = ClipSampler.sample(clip, start + 0.05)
			local b = ClipSampler.sample(clip, (start + clip.duration) / 2)
			local moved = false
			for joint, offset in a do
				local other = b[joint]
				for axis = 1, 3 do
					if math.abs(offset.rot[axis] - other.rot[axis]) > 0.1 then
						moved = true
					end
				end
			end
			expect(moved).toBe(true)
		end
	end)
end)
