--!strict
--[[
	The breath gives way under a strike (D-685; section 10: the strike reads crisp, and beat 6's
	post-motion is "held with micro-motion only (breathing, blade tremor)").

	Every player rig breathes: Choreo plays its breathing clip (choreo.luau rigs.PlayerR15.breathing)
	from the frame the rig appears and never stops it, each screen from its own start, a hit-stop
	pausing it. Its waist, shoulder, wrist and sword keys carried the blade through every strike: a
	basic's first trail point moved up to 0.12 with the breath's phase on the swinger's own screen,
	where a watcher's late copy, which cannot know that phase, draws none (AU 571(a)). Now the joints
	choreo.luau breathYield lists leave the breath over the last breathYield.outSeconds of the
	attack's Anticipation beat (the breath catches on the cut: the wind-up breathes, and so does an
	Art's tell, D-637), stay out of it through every strike's snap and hold, and take it back over
	the Settle beat's length after the last strike's hold, as far as the attack shows (Mixer
	PlayOptions.yields).

	- ClipSampler.breathYield on every player attack: nothing through the wind-up but its last
	  outSeconds and through an activation hold, rising to all of it by the first snap, all of it
	  through every strike to the last hold, falling to nothing over the settle, nothing from the
	  Recovery (the post-motion) on.
	- The Mixer: a breath that yields gives way on breathYield's joints only, by the attack's shown
	  weight; a breath that does not is untouched; the breath comes back as a cut attack fades out.
	- The pop rule (review.audit.popDegrees a 60 Hz frame, outside a strike's snap): what the fade
	  itself turns a joint in a frame at 60 and 144, from 16 points of the breath's cycle, and every
	  basic and Art played as the game plays it (ClipAudit.plans, its breath yielding) with no Pop at
	  60 and 144 and at the animation review's 240. Gone in the wind-up's last frame alone (ExpoOut
	  over 1/60 s), the breath took Basic3's forearm from 19.05 degrees to 20.11 in the last 240 Hz
	  step short of its snap from a run (Run@0.5): the whole turn of a frame counts, the clip's and
	  the fade's. Gathering over the last two (QuadIn), 19.72.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Dev = Harness.load("src/shared/data/dev")
local ChoreoData = Harness.load("src/shared/data/choreo")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Mixer = Harness.load("src/client/choreo/Mixer")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")

local Audit = Dev.review.audit
local BREATHE = ClipLibrary.get(ChoreoData.rigs.PlayerR15.breathing)
local JOINTS: { string } = ChoreoData.breathYield.joints
local BREATH_PHASES = 16
local EPSILON = 1e-9

-- Every player attack, basics and Arts.
local ATTACKS: { any } = {}
for _, id in ClipLibrary.forRig("PlayerR15") do
	local clip = ClipLibrary.get(id)
	if clip.attack == true then
		table.insert(ATTACKS, clip)
	end
end
table.sort(ATTACKS, function(a, b)
	return a.id < b.id
end)

local function eventTime(clip: any, kind: string): number?
	for _, event in clip.events do
		if event.kind == kind then
			return event.time
		end
	end
	return nil
end

-- An Art's activation hold's end (combat.luau activationHold, or the event's own), nil for a basic.
local function holdEndOf(clip: any): number?
	for _, event in clip.events do
		if event.kind == "ActivationHold" then
			local data = event.data
			return event.time
				+ (
					if data ~= nil and typeof(data.hold) == "number"
						then data.hold
						else Harness.load("src/shared/data/combat").activationHold
				)
		end
	end
	return nil
end

-- The last strike's hold: the Hold key after the last strike snap's landing (the landing without one).
local function lastHoldOf(clip: any): number
	local last = 0
	for index = 2, #clip.keys do
		if ClipSampler.isStrikeSnap(clip, index) then
			last = index
		end
	end
	local after = clip.keys[last + 1]
	return if after ~= nil and after.easing == "Hold" then after.time else clip.keys[last].time
end

local function isJoint(name: string): boolean
	return table.find(JOINTS, name) ~= nil
end

-- Offsets read in doubles (a Vector3 holds 32-bit floats): one joint's rot or pos, rest when absent.
type V = { number }
local function rotOf(offsets: any, name: string): V
	local offset = offsets[name]
	return if offset == nil then { 0, 0, 0 } else { offset.rot[1], offset.rot[2], offset.rot[3] }
end

local function posOf(offsets: any, name: string): V
	local offset = offsets[name]
	return if offset == nil then { 0, 0, 0 } else { offset.pos[1], offset.pos[2], offset.pos[3] }
end

-- a - b * scale.
local function less(a: V, b: V, scale: number?): V
	local k = scale or 1
	return { a[1] - b[1] * k, a[2] - b[2] * k, a[3] - b[3] * k }
end

local function size(a: V): number
	return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
end

-- A mixer playing `clip` from clip 0 over the breath from `phase` (yielding or not, or none).
local function mixerWith(clip: any, phase: number, breath: "yields" | "keeps" | "none"): any
	local mixer = Mixer.new()
	if breath ~= "none" then
		mixer:play(BREATHE, { coexist = true, blendIn = 0, startTime = phase, yields = breath == "yields" })
	end
	return mixer, mixer:play(clip, { blendIn = 0 })
end

describe("the breath gives way under a strike (D-685)", function()
	it("the data names the blade's joints, the wind-up's last two frames and the easings", function()
		expect(#JOINTS > 0).toBe(true)
		for _, name in { "Waist", "Neck", "RightShoulder", "RightWrist", "Weapon" } do
			expect({ name, isJoint(name) }).toEqual({ name, true })
		end
		-- The off arm breathes on: the body never stills whole.
		expect(isJoint("LeftShoulder")).toBe(false)
		expect(typeof(ChoreoData.breathYield.outEasing)).toBe("string")
		expect(typeof(ChoreoData.breathYield.inEasing)).toBe("string")
		expect(ChoreoData.breathYield.outSeconds > 0).toBe(true)
		expect(#ATTACKS >= 7).toBe(true)
	end)

	it(
		"every attack: none through its wind-up but the last two frames and through a tell, all from the snap to the last hold, none from the Recovery on",
		function()
			local lines = {}
			for _, clip in ATTACKS do
				local beats = clip.beats
				local holdEnd = holdEndOf(clip)
				local firstOpen = eventTime(clip, "HitWindowOpen") :: number
				local outFrom =
					math.max(beats.Anticipation.start, holdEnd or 0, firstOpen - ChoreoData.breathYield.outSeconds)
				local lastHold = lastHoldOf(clip)
				local settled = lastHold + beats.Settle.finish - beats.Settle.start
				local postMotion = eventTime(clip, "PostMotionStart") or beats.Recovery.start
				local before, peak = 0, 0
				-- Every 240 Hz frame, each time taken whole (no sum drifting off the authored times).
				local bad: string? = nil
				for index = 0, math.floor(clip.duration * 240 + 0.5) do
					local t = index / 240
					local share = ClipSampler.breathYield(clip, t)
					if share < -EPSILON or share > 1 + EPSILON then
						bad = ("%.4f: %.4f out of 0..1"):format(t, share)
					elseif t <= outFrom + EPSILON and share > EPSILON then
						-- The tell breathes (D-637), and so does the wind-up up to its last two frames.
						bad = ("%.4f: %.4f in the wind-up or the tell"):format(t, share)
					elseif t < firstOpen - EPSILON and share < before - EPSILON then
						bad = ("%.4f: %.4f falls going out"):format(t, share)
					elseif t >= firstOpen - EPSILON and t <= lastHold + EPSILON and share < 1 - EPSILON then
						bad = ("%.4f: %.4f under a strike"):format(t, share)
					elseif t > lastHold + EPSILON and share > before + EPSILON then
						bad = ("%.4f: %.4f rises coming back"):format(t, share)
					elseif t >= math.min(settled, postMotion) - EPSILON and share > EPSILON then
						bad = ("%.4f: %.4f settled"):format(t, share)
					end
					if bad ~= nil then
						break
					end
					before, peak = share, math.max(peak, share)
				end
				expect({ clip.id, bad or "" }).toEqual({ clip.id, "" })
				expect({ clip.id, peak }).toEqual({ clip.id, 1 })
				-- Every stroke's first point is drawn with the breath out of the blade.
				for _, event in clip.events do
					if event.kind == "TrailOn" or event.kind == "HitWindowOpen" then
						expect({ clip.id, event.time, ClipSampler.breathYield(clip, event.time) }).toEqual({
							clip.id,
							event.time,
							1,
						})
					end
				end
				table.insert(
					lines,
					("%s out %.4f-%.4f back %.4f-%.4f%s"):format(
						clip.id,
						outFrom,
						firstOpen,
						lastHold,
						settled,
						if holdEnd ~= nil then (" (tell to %.4f)"):format(holdEnd) else ""
					)
				)
			end
			print("[D-685] the breath's give: " .. table.concat(lines, "; "))
			-- Not an attack: never.
			expect(ClipSampler.breathYield(BREATHE, 0.5)).toBe(0)
			expect(ClipSampler.breathYield(ClipLibrary.get("player/OneHandedSword/Guard"), 0.1)).toBe(0)
		end
	)

	it(
		"the Mixer: a breath that yields leaves the blade's joints by the attack's weight; one that does not keeps them",
		function()
			local basic = ClipLibrary.get("player/OneHandedSword/Basic1")
			local phase = 0.675
			local yields, yieldsBasic = mixerWith(basic, phase, "yields")
			local keeps = mixerWith(basic, phase, "keeps")
			local bare = mixerWith(basic, phase, "none")
			local dt = 1 / 60
			local stopped = false
			for frame = 1, math.ceil(basic.duration / dt) do
				local a = yields:step(dt).offsets
				local b = keeps:step(dt).offsets
				local c = bare:step(dt).offsets
				local time = yieldsBasic.time
				local breath = ClipSampler.sample(BREATHE, phase + frame * dt)
				local share = if stopped then 0 else ClipSampler.breathYield(basic, time)
				for name in breath do
					-- What the breath adds, yielding and not.
					local keep = if isJoint(name) then 1 - share else 1
					local label = ("%s at clip %.4f"):format(name, time)
					local kept = size(less(less(rotOf(b, name), rotOf(c, name)), rotOf(breath, name)))
					expect({ label, kept < 1e-9 }).toEqual({ label, true })
					if not stopped then
						local given = size(less(less(rotOf(a, name), rotOf(c, name)), rotOf(breath, name), keep))
						local moved = size(less(less(posOf(a, name), posOf(c, name)), posOf(breath, name), keep))
						expect({ label, given < 1e-9, moved < 1e-9 }).toEqual({ label, true, true })
					end
				end
				if not stopped and time >= 0.12 then
					-- At the snap the blade's joints carry none of the breath; the rest all of it.
					for name in breath do
						local given = size(less(rotOf(a, name), rotOf(c, name)))
						expect({ name, if isJoint(name) then given < 1e-9 else given > 0 }).toEqual({
							name,
							true,
						})
					end
					-- A cut: the attack fades out where it stands, and the breath comes back with it.
					yields:stop(yieldsBasic, 0.1)
					stopped = true
				end
			end
			-- Faded out, the breath is whole again.
			local a = yields:step(dt).offsets
			local breath = ClipSampler.sample(BREATHE, phase + (math.ceil(basic.duration / dt) + 1) * dt)
			for _, name in JOINTS do
				if breath[name] ~= nil then
					expect({ name, size(less(rotOf(a, name), rotOf(breath, name))) < 1e-9 }).toEqual({ name, true })
				end
			end
		end
	)

	it(
		"the fade turns no joint past the pop rule in a 60 Hz frame, from every point of the breath, at 60 and 144",
		function()
			local worst: { [number]: number } = { [60] = 0, [144] = 0 }
			local worstAt: { [number]: string } = {}
			for _, fps in { 60, 144 } do
				local dt = 1 / fps
				for _, clip in ATTACKS do
					for step = 0, BREATH_PHASES - 1 do
						local phase = BREATHE.duration * step / BREATH_PHASES
						local yields, handle = mixerWith(clip, phase, "yields")
						local keeps = mixerWith(clip, phase, "keeps")
						local last: { [string]: V } = {}
						for _ = 1, math.ceil(clip.duration / dt) do
							local a = yields:step(dt).offsets
							local b = keeps:step(dt).offsets
							for _, name in JOINTS do
								-- What the fade takes away, and how far it moves in a frame, per 60 Hz frame.
								local taken = less(rotOf(b, name), rotOf(a, name))
								local before = last[name]
								if before ~= nil then
									local degrees = size(less(taken, before)) * fps / 60
									if degrees > worst[fps] then
										worst[fps], worstAt[fps] =
											degrees,
											("%s %s at clip %.4f, breath from %.3f s"):format(
												clip.id,
												name,
												handle.time,
												phase
											)
									end
								end
								last[name] = taken
							end
						end
					end
				end
			end
			print(
				("[D-685] the fade turns a joint at most %.3f / %.3f degrees a 60 Hz frame at 60 / 144 (%s; %s), the pop rule %d"):format(
					worst[60],
					worst[144],
					worstAt[60] or "",
					worstAt[144] or "",
					Audit.popDegrees
				)
			)
			expect(math.max(worst[60], worst[144]) <= Audit.popDegrees).toBe(true)
		end
	)
end)

-- tools/ modules are plain Lune scripts: load one with only Lune's own libraries to require.
local function loadTool(path: string): any
	local source = fs.readFile(Harness.repoRoot() .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

describe("every basic and Art with its breath yielding, as the game plays it (ClipAudit.plans)", function()
	local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
	local avatar, field = HitMatrix.standing(Harness)
	local body = ClipAudit.body(avatar.model, "PlayerR15", avatar.base, ClipAudit.topOf(field.CFrame, field.Size))
	for _, clip in ATTACKS do
		it(("%s: no pop at 60, 144 and 240"):format(clip.id), function()
			local lines = {}
			local yielding = 0
			for _, plan in ClipAudit.plans(clip, ClipLibrary.get) do
				for _, play in plan.plays do
					if play.clip == BREATHE then
						expect({ plan.label, play.yields }).toEqual({ plan.label, true })
						yielding += 1
					end
				end
				for _, hz in { 60, 144, 240 } do
					for _, finding in ClipAudit.findings(clip, ClipAudit.run(body, clip, plan, hz)) do
						if finding.kind == "Pop" then
							table.insert(lines, ("%s at %d: %s"):format(plan.label, hz, finding.text))
						end
					end
				end
			end
			expect(yielding > 0).toBe(true)
			expect(table.concat(lines, "\n")).toBe("")
		end)
	end
end)
