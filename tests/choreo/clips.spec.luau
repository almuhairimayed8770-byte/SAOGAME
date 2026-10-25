--!strict
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers")
local Combat = Harness.load("src/shared/data/combat")
local Choreo = Harness.load("src/shared/data/choreo")

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
				expect(smearOn[1]).toBeCloseTo(clip.beats.Smear.start, EPSILON)
				expect(eventTimes(clip, "TrailOn")[1]).toBeLessThanOrEqual(windows[1].open)
				local trailOffs = eventTimes(clip, "TrailOff")
				expect(trailOffs[#trailOffs]).toBeGreaterThanOrEqual(windows[#windows].close)
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
			-- The window never opens inside the wind-up: it opens with the strike's snap (the boar's
			-- launch snap starts the instant its 0.6 s crouch ends) and holds through it.
			expect(windows[1].open).toBeGreaterThanOrEqual(attack.windUp - EPSILON)
			expect(windows[1].open).toBeCloseTo(clip.beats.Snap.start, EPSILON)
			expect(windows[1].close).toBeGreaterThanOrEqual(clip.beats.Snap.finish)
		end
	end)

	it("every hit window opens on its strike's snap start (beat 2) and stays open through the snap", function()
		for _, clip in attackClips() do
			local windows = ClipSampler.hitWindows(clip)
			local snaps = ReviewMarkers.strikeSnaps(clip)
			if #snaps ~= #windows then
				error(("%s has %d hit windows but %d strike snaps"):format(clip.id, #windows, #snaps))
			end
			for index, window in windows do
				-- On the snap's first frame: not during the wind-up, not into the ExpoOut cut.
				expect(window.open).toBeCloseTo(snaps[index].start, EPSILON)
				expect(window.close).toBeGreaterThanOrEqual(snaps[index].finish)
				-- The trail ignites on the same frame as the strike (section 10), the smear inside the
				-- snap's first frame: on the first frame that shows the blade cutting (F10).
				local smearOn = eventTimes(clip, "SmearOn")[index]
				expect(smearOn).toBeGreaterThanOrEqual(window.open - EPSILON)
				expect(smearOn).toBeLessThan(window.open + FRAME)
			end
			expect(eventTimes(clip, "TrailOn")[1]).toBeCloseTo(windows[1].open, EPSILON)
		end
	end)

	it("every hit window has its own trail: one TrailOn/TrailOff pair each, out between windows (F9)", function()
		for _, clip in attackClips() do
			local windows = ClipSampler.hitWindows(clip)
			local spans = ReviewMarkers.eventSpans(clip, "TrailOn", "TrailOff")
			if #spans ~= #windows then
				error(("%s lights %d trail spans for %d hit windows"):format(clip.id, #spans, #windows))
			end
			for index, window in windows do
				local span = spans[index]
				expect(span.start).toBeLessThanOrEqual(window.open + EPSILON)
				expect(span.finish).toBeGreaterThanOrEqual(window.close - EPSILON)
				local nextWindow = windows[index + 1]
				if nextWindow ~= nil and span.finish >= nextWindow.open - EPSILON then
					error(("%s keeps its trail lit from hit %d into hit %d"):format(clip.id, index, index + 1))
				end
			end
		end
	end)

	it("the smear shows only on frames past the snap's start: the two that show the cut moving (F10)", function()
		-- Played on its own clock at 30, 60 and 144 fps and at four frame phases, a clip turns its
		-- smear on and off on the frames whose step crosses SmearOn and SmearOff (events fire for
		-- times in (previous frame, this frame]). Every frame drawn with the smear on must show the
		-- strike past its snap's start key, where the blade has left the wind-up and cuts: the
		-- frame on the snap start shows the still wind-up extreme. At 60 fps from the snap start,
		-- that is exactly the snap's first two moving frames, the scale back on the third.
		-- Every attack clip with a smear: the player's, Kobold/Overhead and Boar/Charge (D-229).
		local owned = {}
		for _, clip in attackClips() do
			if #ReviewMarkers.eventSpans(clip, "SmearOn", "SmearOff") > 0 then
				table.insert(owned, clip)
			end
		end
		expect(#owned).toBe(9)
		for _, clip in owned do
			local snaps = ReviewMarkers.strikeSnaps(clip)
			local smears = ReviewMarkers.eventSpans(clip, "SmearOn", "SmearOff")
			expect(#smears).toBe(#snaps)
			for index, snap in snaps do
				local smear = smears[index]
				for _, fps in { 30, 60, 144 } do
					local dt = 1 / fps
					for _, phase in { 0, 0.25, 0.5, 0.75 } do
						local lit = false
						local litFrames = 0
						local previous = snap.start - 3 * dt + phase * dt
						for _ = 1, math.ceil((snap.finish - snap.start) / dt) + 6 do
							local now = previous + dt
							if smear.start > previous and smear.start <= now then
								lit = true
							end
							if smear.finish > previous and smear.finish <= now then
								lit = false
							end
							if lit then
								litFrames += 1
								if now <= snap.start + EPSILON then
									error(
										("%s hit %d at %d fps (phase %.2f): the smear is on at %.4f, on the still snap start %.4f"):format(
											clip.id,
											index,
											fps,
											phase,
											now,
											snap.start
										)
									)
								end
							end
							previous = now
						end
						expect(litFrames).toBeGreaterThanOrEqual(1)
						if fps == 60 and phase == 0 then
							expect(litFrames).toBe(2)
						end
					end
				end
			end
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
			-- The arm climbs highest (the blade over the head) between the two hits: on the re-cock the
			-- second snap starts from, which is where the second window opens.
			local windows = ClipSampler.hitWindows(clip)
			local highest
			for _, key in clip.keys do
				local arm = key.joints.RightShoulder
				if arm ~= nil and (highest == nil or arm.rot[1] > highest.joints.RightShoulder.rot[1]) then
					highest = key
				end
			end
			expect(highest.time).toBeGreaterThan(windows[1].close)
			expect(highest.time).toBeLessThanOrEqual(windows[2].open + EPSILON)
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

-- The sheathed weapon (D-050): the plain locomotion names are the sheathed set (the sword on the
-- back, empty hands), the ...Drawn names the drawn set; Draw and Sheathe move the sword between.
local SHEATHED_SET = { "Idle", "WalkForward", "WalkBack", "WalkLeft", "WalkRight", "Run", "Sprint" }

local function counterpart(name: string): string
	return if name == "Idle" then "IdleDrawn" else name .. "Drawn"
end

local function footsteps(clip: any): { { time: number, foot: string } }
	local list = {}
	for _, event in clip.events do
		if event.kind == "Footstep" then
			table.insert(list, { time = event.time, foot = event.data and event.data.foot })
		end
	end
	return list
end

local function keysWeapon(clip: any): { number }
	local times = {}
	for _, key in clip.keys do
		if key.joints.Weapon ~= nil then
			table.insert(times, key.time)
		end
	end
	return times
end

describe("sheathed and drawn sets", function()
	it("every locomotion and sheath clip in choreo.luau exists", function()
		local prefix = Choreo.locomotion.clipPrefix
		for key, name in Choreo.locomotion.clips do
			if not ClipLibrary.has(prefix .. name) then
				error(("locomotion.clips %s: %s%s is missing"):format(key, prefix, name))
			end
		end
		for key, name in Choreo.sheath.clips do
			if not ClipLibrary.has(prefix .. name) then
				error(("sheath.clips %s: %s%s is missing"):format(key, prefix, name))
			end
		end
	end)

	it("each sheathed clip matches its drawn counterpart: duration, loop and footsteps", function()
		for _, name in SHEATHED_SET do
			local plain = ClipLibrary.get("player/OneHandedSword/" .. name)
			local drawn = ClipLibrary.get("player/OneHandedSword/" .. counterpart(name))
			expect(plain.sheathed).toBe(true)
			expect(drawn.sheathed).never.toBe(true)
			expect(plain.duration).toBe(drawn.duration)
			expect(plain.loop).toBe(drawn.loop)
			expect(plain.layer).toBe(drawn.layer)
			local a, b = footsteps(plain), footsteps(drawn)
			expect(#a).toBe(#b)
			for index = 1, #a do
				if math.abs(a[index].time - b[index].time) > FRAME + EPSILON or a[index].foot ~= b[index].foot then
					error(
						("%s Footstep %d (%s at %.3f s) is not %s's (%s at %.3f s)"):format(
							plain.id,
							index,
							tostring(a[index].foot),
							a[index].time,
							drawn.id,
							tostring(b[index].foot),
							b[index].time
						)
					)
				end
			end
		end
	end)

	it("the sheathed set keys no Weapon; Draw keys it only from its WeaponDraw", function()
		for _, name in SHEATHED_SET do
			local clip = ClipLibrary.get("player/OneHandedSword/" .. name)
			expect(keysWeapon(clip)).toEqual({})
		end
		local draw = ClipLibrary.get("player/OneHandedSword/Draw")
		local at = eventTimes(draw, "WeaponDraw")[1]
		local times = keysWeapon(draw)
		expect(times[1]).toBeCloseTo(at, EPSILON)
		for _, time in times do
			expect(time).toBeGreaterThanOrEqual(at - EPSILON)
		end
	end)

	it("Draw and Sheathe each carry exactly one of their events and play over the upper body", function()
		local draw = ClipLibrary.get("player/OneHandedSword/" .. Choreo.sheath.clips.draw)
		local sheathe = ClipLibrary.get("player/OneHandedSword/" .. Choreo.sheath.clips.sheathe)
		expect(#eventTimes(draw, "WeaponDraw")).toBe(1)
		expect(#eventTimes(draw, "WeaponSheathe")).toBe(0)
		expect(#eventTimes(sheathe, "WeaponSheathe")).toBe(1)
		expect(#eventTimes(sheathe, "WeaponDraw")).toBe(0)
		expect(draw.sheathed).toBe(true)
		expect(sheathe.sheathed).never.toBe(true)
		for _, clip in { draw, sheathe } do
			expect(clip.layer).toBe("UpperBody")
			expect(clip.priority).toBe(Choreo.priority.Sheath)
			expect(clip.loop).toBe(false)
			expect(ReviewMarkers.mountProblems(clip)).toEqual({})
		end
		-- After the sword goes home, no key moves it.
		local home = eventTimes(sheathe, "WeaponSheathe")[1]
		for _, time in keysWeapon(sheathe) do
			expect(time).toBeLessThanOrEqual(home + EPSILON)
		end
	end)

	it("the sheathed Idle keeps its 12 s cycle with empty hands", function()
		local idle = ClipLibrary.get("player/OneHandedSword/Idle")
		expect(idle.sheathed).toBe(true)
		expect(idle.duration).toBe(Choreo.locomotion.idleCycle)
		expect(keysWeapon(idle)).toEqual({})
	end)

	it("the pose editor writes sheathed right after loop when it rewrites a clip", function()
		local fs = require("@lune/fs")
		local luau = require("@lune/luau")
		local path = "tools/PoseEditor/src/Serialize.luau"
		local Serialize = luau.load(fs.readFile(Harness.repoRoot() .. "/" .. path), {
			debugName = path,
			environment = {
				require = function(_target: any)
					error("Serialize must not require anything")
				end,
			} :: any,
		})()
		local source = Harness.readFile("src/shared/clips/player/OneHandedSword/Draw.luau")
		local parsed, meta = Serialize.parse(source)
		local written = Serialize.toSource(parsed, { meta = meta })
		expect(written).toContain('\tloop = false,\n\tsheathed = true,\n\tlayer = "UpperBody",')
	end)
end)
