--!strict
local Mixer = Harness.load("src/client/choreo/Mixer")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Easing = Harness.load("src/shared/util/Easing")

local FRAME = 1 / 60

local function clip(id, overrides)
	local def = {
		id = id,
		rig = "PlayerR15",
		duration = 1,
		loop = false,
		layer = "FullBody",
		keys = {
			{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 0, 0 } } } },
			{ time = 1, easing = "Linear", joints = { Neck = { rot = { 0, 100, 0 } } } },
		},
		events = {},
		blendIn = 0,
		blendOut = 0,
	}
	for key, value in overrides or {} do
		def[key] = value
	end
	return def
end

local function stepFrames(mixer, frames)
	local result
	for _ = 1, frames do
		result = mixer:step(FRAME)
	end
	return result
end

describe("Mixer", function()
	it("samples a playing clip and advances its clock", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a"))
		local result = mixer:step(0.5)
		expect(handle.time).toBeCloseTo(0.5)
		expect(result.offsets.Neck.rot[2]).toBeCloseTo(50)
		expect(mixer:isPlaying("a")).toBe(true)
	end)

	it("blends in over blendIn and blends out on stop", function()
		local mixer = Mixer.new()
		mixer:play(clip("a", {
			blendIn = 0.2,
			loop = true,
			keys = { { time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 100, 0 } } } } },
		}))
		local result = mixer:step(0.1)
		expect(result.offsets.Neck.rot[2]).toBeCloseTo(50)
		result = mixer:step(0.1)
		expect(result.offsets.Neck.rot[2]).toBeCloseTo(100)
		mixer:stop("a", 0.2)
		result = mixer:step(0.1)
		expect(result.offsets.Neck.rot[2]).toBeCloseTo(50)
		result = mixer:step(0.1)
		expect(result.offsets.Neck).toBeNil()
		expect(#mixer:handles()).toBe(0)
	end)

	it("FullBody overrides only the joints it keys; Additive adds on top", function()
		local mixer = Mixer.new()
		mixer:play(
			clip("base", {
				layer = "Base",
				loop = true,
				keys = {
					{
						time = 0,
						easing = "Hold",
						joints = { Waist = { rot = { 10, 0, 0 } }, Neck = { rot = { 0, 20, 0 } } },
					},
				},
			}),
			{ coexist = true }
		)
		mixer:play(
			clip("full", { keys = { { time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 80, 0 } } } } } })
		)
		mixer:play(
			clip("breathe", {
				layer = "Additive",
				loop = true,
				keys = { { time = 0, easing = "Hold", joints = { Waist = { rot = { 2, 0, 0 } } } } },
			}),
			{ coexist = true }
		)
		local result = mixer:step(FRAME)
		expect(result.offsets.Neck.rot[2]).toBeCloseTo(80)
		expect(result.offsets.Waist.rot[1]).toBeCloseTo(12)
	end)

	it("hit-stop pauses every clock for the frame count and reports the pause", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a"))
		stepFrames(mixer, 6)
		local before = handle.time
		mixer:hitStop(3)
		local result = stepFrames(mixer, 3)
		expect(result.paused).toBe(true)
		expect(handle.time).toBeCloseTo(before, 1e-6)
		expect(mixer:pauseRemaining()).toBeCloseTo(0, 1e-6)
		result = mixer:step(FRAME)
		expect(result.paused).toBe(false)
		expect(handle.time).toBeCloseTo(before + FRAME, 1e-6)
	end)

	it("the time scale and the handle speed both scale the clock", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a"), { speed = 2 })
		mixer:setTimeScale(0.5)
		mixer:step(0.2)
		expect(handle.time).toBeCloseTo(0.2)
		mixer:setTimeScale(2)
		mixer:step(0.1)
		expect(handle.time).toBeCloseTo(0.6)
	end)

	it("a server time jumps the clock to the matching position, within the catch-up limit", function()
		expect(Mixer.catchUpStart(10.1, 10, 1, 1)).toBeCloseTo(0.1)
		expect(Mixer.catchUpStart(10.1, 10, 2, 1)).toBeCloseTo(0.2)
		expect(Mixer.catchUpStart(12, 10, 1, 1)).toBeCloseTo(ChoreoData.catchUpMaxJump)
		expect(Mixer.catchUpStart(9, 10, 1, 1)).toBe(0)
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a"), { serverTime = 10, now = 10.15 })
		expect(handle.time).toBeCloseTo(0.15)
	end)

	it("fires each event once when its time is crossed, including time 0 on the first step", function()
		local mixer = Mixer.new()
		mixer:play(clip("a", {
			events = {
				{ time = 0, kind = "ActivationHold" },
				{ time = 0.3, kind = "HitWindowOpen" },
				{ time = 0.5, kind = "HitWindowClose" },
			},
		}))
		local first = mixer:step(0.1)
		expect(#first.events).toBe(1)
		expect(first.events[1].event.kind).toBe("ActivationHold")
		local second = mixer:step(0.25)
		expect(#second.events).toBe(1)
		expect(second.events[1].event.kind).toBe("HitWindowOpen")
		local third = mixer:step(0.1)
		expect(#third.events).toBe(0)
		local fourth = mixer:step(0.2)
		expect(#fourth.events).toBe(1)
		expect(fourth.events[1].clipId).toBe("a")
	end)

	it("looping clips wrap and fire the events on both sides of the wrap", function()
		local mixer = Mixer.new()
		local handle = mixer:play(
			clip("walk", {
				loop = true,
				events = { { time = 0.2, kind = "Footstep" }, { time = 0.9, kind = "Footstep" } },
			}),
			{ startTime = 0.85 }
		)
		local result = mixer:step(0.4)
		expect(#result.events).toBe(2)
		expect(handle.time).toBeCloseTo(0.25)
	end)

	it("root motion deltas sum to the clip's travel and stay continuous across a loop wrap", function()
		local mixer = Mixer.new()
		mixer:play(clip("art", {
			keys = {
				{ time = 0, easing = "Hold", joints = {}, root = { pos = { 0, 0, 0 } } },
				{ time = 1, easing = "Linear", joints = {}, root = { pos = { 0, 0, -3 } } },
			},
		}))
		local total = 0
		for _ = 1, 10 do
			total += mixer:step(0.1).rootDelta[3]
		end
		expect(total).toBeCloseTo(-3, 1e-6)

		local looping = Mixer.new()
		looping:play(
			clip("run", {
				loop = true,
				keys = {
					{ time = 0, easing = "Hold", joints = {}, root = { pos = { 0, 0, 0 } } },
					{ time = 1, easing = "Linear", joints = {}, root = { pos = { 0, 0, -2 } } },
				},
			}),
			{ startTime = 0.9 }
		)
		local delta = looping:step(0.2).rootDelta[3]
		expect(delta).toBeCloseTo(-0.4, 1e-6)
	end)

	it("a non-looping clip holds its last key, reports finished once and blends out", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("a", { blendOut = 0.1 }))
		local result = mixer:step(1.2)
		expect(#result.finished).toBe(1)
		expect(result.finished[1]).toBe(handle)
		expect(result.offsets.Neck.rot[2]).toBeCloseTo(100)
		expect(handle.stopping).toBe(true)
		result = mixer:step(0.05)
		expect(#result.finished).toBe(0)
		expect(result.offsets.Neck.rot[2]).toBeCloseTo(50)
		mixer:step(0.1)
		expect(#mixer:handles()).toBe(0)
	end)

	it("a new clip on a layer stops lower-or-equal priority clips but not coexisting ones", function()
		local mixer = Mixer.new()
		local low = mixer:play(clip("low"), { priority = 5 })
		local walk = mixer:play(clip("walk", { layer = "Base", loop = true }), { coexist = true })
		local high = mixer:play(clip("high"), { priority = 20 })
		expect(low.stopping).toBe(true)
		expect(walk.stopping).toBe(false)
		local lower = mixer:play(clip("lower"), { priority = 10 })
		expect(high.stopping).toBe(false)
		expect(lower.stopping).toBe(false)
		mixer:play(clip("walk2", { layer = "Base", loop = true }), { coexist = true })
		expect(walk.stopping).toBe(false)
	end)

	it("the fallback idle fades out while another Base clip is active and back in after", function()
		local mixer = Mixer.new()
		local idle = mixer:play(
			clip("idle", {
				layer = "Base",
				loop = true,
				keys = { { time = 0, easing = "Hold", joints = { Waist = { rot = { 10, 0, 0 } } } } },
			}),
			{ fallback = true }
		)
		local result = mixer:step(FRAME)
		expect(result.offsets.Waist.rot[1]).toBeCloseTo(10)
		local walk = mixer:play(
			clip("walk", {
				layer = "Base",
				loop = true,
				keys = { { time = 0, easing = "Hold", joints = { Waist = { rot = { -10, 0, 0 } } } } },
			}),
			{ coexist = true }
		)
		for _ = 1, 30 do
			mixer:step(FRAME)
		end
		expect(idle.weight).toBeCloseTo(0, 1e-6)
		expect(mixer:step(FRAME).offsets.Waist.rot[1]).toBeCloseTo(-10)
		mixer:stop(walk, 0)
		for _ = 1, 30 do
			mixer:step(FRAME)
		end
		expect(idle.weight).toBeCloseTo(1, 1e-6)
	end)

	it(
		"a fallback idle hidden under another Base clip fires none of its events; it fires again once it shows",
		function()
			local mixer = Mixer.new()
			local events = { { time = 0.25, kind = "Sfx", data = { name = "enemy.BruteRoar" } } }
			mixer:play(clip("idle", { layer = "Base", loop = true, events = events }), { fallback = true })
			local function sounds(frames: number): number
				local count = 0
				for _ = 1, frames do
					for _, fired in mixer:step(FRAME).events do
						if fired.clipId == "idle" then
							count += 1
						end
					end
				end
				return count
			end
			expect(sounds(60)).toBe(1) -- alone, it is the rig's idle: one sound a loop
			-- The same loop played as the rig's own idle (a later phase) hides it: only the shown
			-- copy is heard.
			local shown = mixer:play(
				clip("idle", { layer = "Base", loop = true, events = events }),
				{ coexist = true, startTime = 0.5 }
			)
			local heard = 0
			for _ = 1, 120 do
				for _, fired in mixer:step(FRAME).events do
					expect(fired.handle).toBe(shown)
					heard += 1
				end
			end
			expect(heard).toBe(2)
			mixer:stop(shown, 0)
			expect(sounds(60)).toBe(1)
		end
	)

	it("blend-space weights move toward their target at the data rate", function()
		local mixer = Mixer.new()
		local walk = mixer:play(clip("walk", { layer = "Base", loop = true }), { coexist = true, weight = 0 })
		mixer:setWeight(walk, 1)
		mixer:step(0.05)
		expect(walk.weight).toBeCloseTo(0.05 * ChoreoData.locomotion.weightBlendRate, 1e-6)
		-- The ramp converges exactly: the step that can reach the target lands on it.
		local steps = math.ceil(1 / (0.05 * ChoreoData.locomotion.weightBlendRate))
		for _ = 2, steps do
			mixer:step(0.05)
		end
		expect(walk.weight).toBe(1)
		mixer:setWeight(walk, 0.25, true)
		expect(walk.weight).toBe(0.25)
	end)

	it("retargeted blend-space weights keep their sum, so the Base pose never dips toward rest", function()
		local function held(id, waist)
			return clip(id, {
				layer = "Base",
				loop = true,
				keys = { { time = 0, easing = "Hold", joints = { Waist = { rot = { waist, 0, 0 } } } } },
			})
		end
		local values = { 10, -20, 40 }
		local starts = { 0.25, 0.25, 0.5 }
		local targets = { 1, 0, 0 }
		local mixer = Mixer.new()
		local handles = {}
		for index, value in values do
			handles[index] =
				mixer:play(held("h" .. index, value), { coexist = true, blendIn = 0, weight = starts[index] })
		end
		for index, handle in handles do
			mixer:setWeight(handle, targets[index])
		end
		local reach = FRAME * ChoreoData.locomotion.weightBlendRate
		for step = 1, 8 do
			local before = handles[1].weight
			local result = mixer:step(FRAME)
			local total, mixed = 0, 0
			for index, handle in handles do
				local weight = handle.fade * handle.weight
				total += weight
				mixed += weight * values[index]
			end
			expect(total).toBeCloseTo(1, 1e-6)
			-- The composed pose is the normalized mix alone: no share of it replaced by rest.
			expect(result.offsets.Waist.rot[1]).toBeCloseTo(mixed / total, 1e-6)
			if step == 1 then
				-- The largest mover travels at the data rate; the others keep pace.
				expect(handles[1].weight - before).toBeCloseTo(reach, 1e-6)
				expect(handles[3].weight).toBeCloseTo(2 * handles[2].weight, 1e-9)
			end
		end
		for index, handle in handles do
			expect(handle.weight).toBe(targets[index])
		end
		expect(mixer:step(FRAME).offsets.Waist.rot[1]).toBeCloseTo(values[1], 1e-6)
	end)

	it("a blend envelope is eased: the limbs leave a held pose slowly, speed up, then settle", function()
		local mixer = Mixer.new()
		mixer:play(
			clip("idle", {
				layer = "Base",
				loop = true,
				keys = { { time = 0, easing = "Hold", joints = { RightShoulder = { rot = { 0, 0, 0 } } } } },
			}),
			{ coexist = true }
		)
		local art = mixer:play(clip("art", {
			loop = true,
			blendOut = 0.2,
			keys = { { time = 0, easing = "Hold", joints = { RightShoulder = { rot = { 60, 0, 0 } } } } },
		}))
		local previous = mixer:step(FRAME).offsets.RightShoulder.rot[1]
		expect(previous).toBeCloseTo(60, 1e-6)
		mixer:stop(art, 0.2) -- 12 frames of blend-out
		local values, deltas = {}, {}
		for frame = 1, 11 do
			local now = mixer:step(FRAME).offsets.RightShoulder.rot[1]
			values[frame] = now
			table.insert(deltas, previous - now)
			previous = now
			-- The limbs follow the eased envelope; the envelope itself stays linear progress.
			expect(art.fade).toBeCloseTo(1 - frame / 12, 1e-6)
			expect(now).toBeCloseTo(60 * Easing.evaluate(ChoreoData.blendEasing, art.fade), 1e-6)
		end
		-- Halfway the eased weight still matches the linear one; the ends are slow, the middle fast.
		expect(values[6]).toBeCloseTo(30, 1e-6)
		local mid = deltas[6]
		expect(deltas[1]).toBeGreaterThan(0)
		expect(deltas[1]).toBeLessThan(mid * 0.5)
		expect(deltas[11]).toBeLessThan(mid * 0.5)
		for _ = 1, 3 do
			mixer:step(FRAME)
		end
		expect(#mixer:handles()).toBe(1)
		expect(mixer:step(FRAME).offsets.RightShoulder.rot[1]).toBeCloseTo(0, 1e-6)
	end)

	it("an equal crossfade between two clips keeps the full pose (the eased envelopes sum to 1)", function()
		local mixer = Mixer.new()
		local a = mixer:play(clip("a", {
			loop = true,
			keys = { { time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 40, 0 } } } } },
		}))
		mixer:step(FRAME)
		local b = mixer:play(
			clip("b", {
				loop = true,
				blendIn = 0.2,
				blendOut = 0.2,
				keys = { { time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 80, 0 } } } } },
			}),
			{ blendIn = 0.2 }
		)
		expect(a.stopping).toBe(true)
		local previous = 40
		for _ = 1, 11 do
			local now = mixer:step(FRAME).offsets.Neck.rot[2]
			local fromA = Easing.evaluate(ChoreoData.blendEasing, a.fade)
			local fromB = Easing.evaluate(ChoreoData.blendEasing, b.fade)
			expect(fromA + fromB).toBeCloseTo(1, 1e-6)
			expect(now).toBeCloseTo(fromA * 40 + fromB * 80, 1e-6)
			expect(now).toBeGreaterThan(previous)
			previous = now
		end
		expect(b.fade).toBeCloseTo(11 / 12, 1e-6)
	end)

	it("a DeathFreeze clip holds every other clock for its duration while its tremor keeps running", function()
		local mixer = Mixer.new()
		local art = mixer:play(clip("art"))
		mixer:step(0.1)
		local freeze = mixer:play(clip("player/OneHandedSword/DeathFreeze", { layer = "Additive", duration = 0.5 }))
		local artTime = art.time
		for _ = 1, 30 do
			mixer:step(FRAME)
		end
		expect(art.time).toBeCloseTo(artTime, 1e-6)
		expect(freeze.time).toBeGreaterThan(0.4)
		mixer:step(FRAME)
		expect(art.time).toBeGreaterThan(artTime)
	end)

	it("root motion is never cut by the blend-in and dies with the fade only when the clip is stopping", function()
		local dodge = clip("dodge", {
			blendIn = 0.1,
			blendOut = 0.2,
			keys = {
				{ time = 0, easing = "Hold", joints = {}, root = { pos = { 0, 0, 0 } } },
				{ time = 0.5, easing = "Linear", joints = {}, root = { pos = { 0, 0, -8 } } },
				{ time = 1, easing = "Hold", joints = {}, root = { pos = { 0, 0, -8 } } },
			},
		})
		local mixer = Mixer.new()
		mixer:play(dodge)
		local travel = 0
		for _ = 1, 30 do
			travel += mixer:step(FRAME).rootDelta[3]
		end
		expect(travel).toBeCloseTo(-8, 1e-6)

		local cancelled = Mixer.new()
		local handle = cancelled:play(dodge)
		cancelled:step(0.1) -- 1.6 studs at full weight
		cancelled:stop(handle, 0.2)
		local faded = cancelled:step(0.1).rootDelta[3] -- 1.6 studs authored, fade 1 -> 0.5
		expect(faded).toBeCloseTo(-1.6 * 0.5, 1e-6)
	end)

	it(
		"inside a layer a higher priority clip hides a lower one; the lower shows through as the higher fades",
		function()
			local mixer = Mixer.new()
			local art = mixer:play(
				clip("art", {
					keys = { { time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 90, 0 } } } } },
					blendOut = 0.1,
				}),
				{ priority = 20 }
			)
			-- A locomotion one-shot (Skid, Land) fired while the Art plays: lower priority, same layer.
			local skid = mixer:play(
				clip("skid", { keys = { { time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 10, 0 } } } } } }),
				{ priority = 5 }
			)
			expect(skid.stopping).toBe(false)
			expect(art.stopping).toBe(false)
			expect(mixer:step(FRAME).offsets.Neck.rot[2]).toBeCloseTo(90)
			local late = mixer:play(
				clip("land", { keys = { { time = 0, easing = "Hold", joints = { Neck = { rot = { 0, -30, 0 } } } } } }),
				{ priority = 6 }
			)
			expect(late.stopping).toBe(false)
			expect(art.stopping).toBe(false)
			expect(mixer:step(FRAME).offsets.Neck.rot[2]).toBeCloseTo(90)
			mixer:stop(art, 0.1)
			mixer:step(0.05)
			local result = mixer:step(0) -- art at fade 0.5 over the land clip (fade 1)
			expect(result.offsets.Neck.rot[2]).toBeCloseTo(0.5 * -30 + 0.5 * 90, 1e-6)
		end
	)

	it("a pause holds blend envelopes and blend-space weights, not only the clocks", function()
		local mixer = Mixer.new()
		local art = mixer:play(clip("art", { blendOut = 0.2 }))
		local walk = mixer:play(clip("walk", { layer = "Base", loop = true }), { coexist = true, weight = 0 })
		mixer:step(0.2)
		mixer:stop(art, 0.2)
		mixer:setWeight(walk, 1)
		mixer:hitStop(6)
		for _ = 1, 6 do
			mixer:step(FRAME)
		end
		expect(art.fade).toBe(1)
		expect(walk.weight).toBe(0)
		expect(art.time).toBeCloseTo(0.2, 1e-6)
		mixer:step(FRAME)
		expect(art.fade).toBeLessThan(1)
		expect(walk.weight).toBeGreaterThan(0)
	end)

	it("the death tremor keeps running at time scale zero while everything else is frozen", function()
		local mixer = Mixer.new()
		local art = mixer:play(clip("art"))
		mixer:step(0.1)
		local freeze = mixer:play(clip("enemy/Boar/DeathFreeze", { layer = "Additive", duration = 0.5 }))
		mixer:setTimeScale(0)
		for _ = 1, 12 do
			mixer:step(FRAME)
		end
		expect(art.time).toBeCloseTo(0.1, 1e-6)
		expect(freeze.time).toBeCloseTo(12 * FRAME, 1e-6)
	end)

	it("stepping never writes into clip data (samples at a clip's ends alias its key arrays)", function()
		local held = clip("held", {
			keys = {
				{ time = 0, easing = "Hold", joints = { Waist = { rot = { 5, 0, 0 } }, Neck = { pos = { 1, 2, 3 } } } },
			},
			loop = true,
			layer = "Base",
		})
		local breathe = clip("breathe", {
			layer = "Additive",
			loop = true,
			keys = {
				{ time = 0, easing = "Hold", joints = { Waist = { rot = { 1, 0, 0 } }, Neck = { pos = { 1, 1, 1 } } } },
			},
		})
		local mixer = Mixer.new()
		mixer:play(held, { coexist = true })
		mixer:play(breathe, { coexist = true })
		mixer:setProcedural("lean", { Waist = { pos = { 0, 0, 0 }, rot = { 0, 0, 2 } } }, 1)
		local result
		for _ = 1, 5 do
			result = mixer:step(FRAME)
		end
		expect(result.offsets.Waist.rot[1]).toBeCloseTo(6)
		expect(result.offsets.Waist.rot[3]).toBeCloseTo(2)
		expect(result.offsets.Neck.pos[2]).toBeCloseTo(3)
		expect(held.keys[1].joints.Waist.rot[1]).toBe(5)
		expect(held.keys[1].joints.Neck.pos[2]).toBe(2)
		expect(breathe.keys[1].joints.Waist.rot[1]).toBe(1)
	end)

	it("procedural additive channels add and can be cleared", function()
		local mixer = Mixer.new()
		mixer:play(clip("a"))
		mixer:setProcedural("lean", { Waist = { pos = { 0, 0, 0 }, rot = { 0, 0, 6 } } }, 0.5)
		expect(mixer:step(FRAME).offsets.Waist.rot[3]).toBeCloseTo(3)
		mixer:setProcedural("lean", nil)
		expect(mixer:step(FRAME).offsets.Waist).toBeNil()
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Beat 4, the hold (section 10, issue 6): a hit-stop stands in for the authored hold after the
-- strike's snap, so a hit holds once, never the hit-stop and then the authored hold again.
-- ------------------------------------------------------------------------------------------

describe("Mixer hit-stop and the strike's authored hold", function()
	local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")

	-- Two strikes: anticipation, a 3-frame snap opening a window, a 3-frame authored hold, a settle.
	local function strike(attack: boolean?): any
		local function key(time: number, easing: string, value: number): any
			return { time = time, easing = easing, joints = { Neck = { rot = { 0, value, 0 } } } }
		end
		return clip("strike", {
			attack = attack,
			duration = 1.2,
			keys = {
				key(0, "Hold", 0),
				key(0.3, "QuadIn", -10),
				key(0.35, "ExpoOut", 90), -- snap 1
				{ time = 0.4, easing = "Hold", joints = {} }, -- its hold: the snap's pose
				key(0.6, "Linear", 60), -- settle
				key(0.75, "QuadIn", 70),
				key(0.8, "ExpoOut", -90), -- snap 2
				{ time = 0.85, easing = "Hold", joints = {} },
				key(1.0, "Linear", -60),
			},
			events = {
				{ time = 0.3, kind = "HitWindowOpen", data = { hit = 1 } },
				{ time = 0.38, kind = "SmearOff" },
				{ time = 0.45, kind = "HitWindowClose", data = { hit = 1 } },
				{ time = 0.75, kind = "HitWindowOpen", data = { hit = 2 } },
				{ time = 0.9, kind = "HitWindowClose", data = { hit = 2 } },
			},
		})
	end

	-- Plays the clip at 60 fps, hit-stopping `frames` the first frame its clock reaches `at`;
	-- returns each frame's neck angle and clock, and the events fired.
	local function run(def: any, at: number?, frames: number?): ({ number }, { number }, { string })
		local mixer = Mixer.new()
		local handle = mixer:play(def)
		local angles, clocks, fired = {}, {}, {}
		local stopped = false
		for _ = 1, 66 do
			local result = mixer:step(FRAME)
			table.insert(angles, result.offsets.Neck.rot[2])
			table.insert(clocks, handle.time)
			for _, entry in result.events do
				table.insert(fired, entry.event.kind)
			end
			if at ~= nil and not stopped and handle.time >= at then
				stopped = true
				mixer:hitStop(frames or 0)
			end
		end
		return angles, clocks, fired
	end

	-- The runs of frames that show the same pose as the frame before, as {first frame, length}.
	local function stills(angles: { number }): { { number } }
		local runs = {}
		local current: { number }? = nil
		for index = 2, #angles do
			if math.abs(angles[index] - angles[index - 1]) < 1e-9 then
				if current == nil then
					current = { index, 0 }
					table.insert(runs, current :: { number })
				end
				(current :: { number })[2] += 1
			else
				current = nil
			end
		end
		return runs
	end

	-- The still runs from `from` on, before the clock reaches `until`.
	local function stillsBetween(angles: { number }, clocks: { number }, from: number, before: number): { number }
		local lengths = {}
		for _, entry in stills(angles) do
			local first = entry[1]
			if clocks[first] >= from and clocks[first] < before then
				table.insert(lengths, entry[2])
			end
		end
		return lengths
	end

	it("finds the hold of the snap a hit belongs to, while it is still ahead", function()
		local def = strike(true)
		expect(ClipSampler.strikeHoldAfter(def, 0.2)).toBeNil()
		expect(ClipSampler.strikeHoldAfter(def, 0.3)).toBe(4)
		expect(ClipSampler.strikeHoldAfter(def, 0.33)).toBe(4)
		expect(ClipSampler.strikeHoldAfter(def, 0.39)).toBe(4)
		expect(ClipSampler.strikeHoldAfter(def, 0.4)).toBeNil()
		expect(ClipSampler.strikeHoldAfter(def, 0.44)).toBeNil()
		expect(ClipSampler.strikeHoldAfter(def, 0.76)).toBe(8)
		expect(ClipSampler.strikeHoldAfter(strike(nil), 0.33)).toBeNil()
		-- Every strike of Sharp Nail has its hold right after its snap.
		local sharp = Harness.load("src/shared/clips/player/OneHandedSword/SharpNail")
		for _, case in { { 0.34, 0.4167 }, { 0.6, 0.66 }, { 0.86, 0.95 } } do
			local index = ClipSampler.strikeHoldAfter(sharp, case[1])
			expect(index).never.toBeNil()
			expect(sharp.keys[index :: number].time).toBeCloseTo(case[2], 1e-6)
		end
	end)

	it("a hit-stop on contact mid-snap holds once: the snap lands and the settle follows, no second hold", function()
		-- A whiff shows the authored hold: 3 frames.
		local whiffAngles, whiffClocks = run(strike(true))
		expect(stillsBetween(whiffAngles, whiffClocks, 0.3, 0.6)).toEqual({ 3 })
		local angles, clocks = run(strike(true), 0.32, 6)
		-- The hit-stop's 6 frames, then the snap lands and goes straight into the settle.
		expect(stillsBetween(angles, clocks, 0.3, 0.6)).toEqual({ 6 })
		-- The second strike keeps its own hold.
		expect(stillsBetween(angles, clocks, 0.75, 1.0)).toEqual({ 3 })
		-- The clock skipped the 3 held frames: it ends the run 3 frames nearer the clip's.
		local last = clocks[#clocks]
		local whiffLast = whiffClocks[#whiffClocks]
		expect(last).toBeCloseTo(whiffLast - 6 * FRAME + 0.05, 1e-6)
	end)

	it("a hit-stop inside the authored hold ends it: the first frame after the hit-stop moves", function()
		local angles, clocks = run(strike(true), 0.36, 6)
		local runs = stills(angles)
		local hold = nil
		for _, entry in runs do
			if clocks[entry[1]] >= 0.34 and clocks[entry[1]] < 0.6 then
				expect(hold).toBeNil()
				hold = entry
			end
		end
		expect(hold).never.toBeNil()
		local entry = hold :: { number }
		-- The still frames before the hit plus the hit-stop's 6; not the hold's rest after them.
		expect(entry[2]).toBeLessThan(6 + 3)
		expect(entry[2]).toBeGreaterThan(5)
		local after = entry[1] + entry[2]
		expect(math.abs(angles[after] - angles[after - 1]) > 1e-6).toBe(true)
	end)

	it("keeps the hold of a strike the hit-stop is not in, and of a clip that is not an attack", function()
		-- A hit after snap 1's hold passed (late in window 1): snap 2's hold is not its to skip.
		local angles, clocks = run(strike(true), 0.42, 6)
		expect(stillsBetween(angles, clocks, 0.75, 1.0)).toEqual({ 3 })
		-- Not an attack: the hit-stop and then the authored hold, as before.
		local plain, plainClocks = run(strike(nil), 0.32, 6)
		expect(stillsBetween(plain, plainClocks, 0.3, 0.6)).toEqual({ 6, 3 })
		-- No hit-stop: the hold stays.
		local zero, zeroClocks = run(strike(true), 0.32, 0)
		expect(stillsBetween(zero, zeroClocks, 0.3, 0.6)).toEqual({ 3 })
	end)

	it("still fires the events in the skipped hold once, and a longer hit-stop keeps its own length", function()
		local _, _, fired = run(strike(true), 0.32, 6)
		local smears = 0
		for _, kind in fired do
			if kind == "SmearOff" then
				smears += 1
			end
		end
		expect(smears).toBe(1)
		-- An upgrade (a second, longer hit-stop on the same strike) holds the longer one, once.
		local mixer = Mixer.new()
		local handle = mixer:play(strike(true))
		while handle.time < 0.32 do
			mixer:step(FRAME)
		end
		mixer:hitStop(3)
		mixer:step(FRAME)
		mixer:hitStop(10 - 1)
		local held = 1
		while mixer:pauseRemaining() > 0 do
			mixer:step(FRAME)
			held += 1
		end
		expect(held).toBe(10)
		expect(handle.absorbKey).toBe(4)
		expect(handle.absorbSeconds).toBeCloseTo(9 * FRAME, 1e-9)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Render stalls (D-132): RenderStepped stops while the display sleeps and its first dt after
-- waking is the whole gap. A step longer than choreo.stall.jumpSeconds is a jump.
-- ------------------------------------------------------------------------------------------

describe("Mixer across a render stall", function()
	-- Read per test, so a table without the stall block fails each test on its own.
	local function jumpSeconds(): number
		return ChoreoData.stall.jumpSeconds
	end

	-- An Art-shaped one-shot: a 1-stud lunge over its first 0.5 s, a chime, a whoosh, a trail.
	local function lunge(id: string?)
		return clip(id or "art", {
			keys = {
				{ time = 0, easing = "Hold", joints = { Neck = { rot = { 0, 0, 0 } } }, root = { pos = { 0, 0, 0 } } },
				{
					time = 0.5,
					easing = "Linear",
					joints = { Neck = { rot = { 0, 50, 0 } } },
					root = { pos = { 0, 0, -1 } },
				},
				{
					time = 1,
					easing = "Hold",
					joints = { Neck = { rot = { 0, 100, 0 } } },
					root = { pos = { 0, 0, -1 } },
				},
			},
			events = {
				{ time = 0.15, kind = "ActivationHold" },
				{ time = 0.3, kind = "Sfx", data = { name = "whoosh.Medium" } },
				{ time = 0.35, kind = "TrailOn" },
				{ time = 0.5, kind = "TrailOff" },
				{ time = 0.6, kind = "PostMotionStart" },
			},
			blendOut = 0.2,
		})
	end

	it("the threshold is data, longer than a 60, 30 or 15 fps frame", function()
		expect(typeof(jumpSeconds())).toBe("number")
		expect(jumpSeconds() > 4 * FRAME).toBe(true)
	end)

	it("a step longer than jumpSeconds is a jump: the clocks take the whole gap, the root none of it", function()
		local mixer = Mixer.new()
		local handle = mixer:play(lunge())
		mixer:step(0.1)
		local result = mixer:step(56)
		expect(result.jumped).toBe(true)
		expect(result.rootDelta).toEqual({ 0, 0, 0 })
		-- The clip is over: it ended, reported finished, and holds its last key while it blends out.
		expect(handle.ended).toBe(true)
		expect(#result.finished).toBe(1)
		expect(result.offsets.Neck.rot[2]).toBeCloseTo(100)
		-- The events the gap crossed still reach the router, marked by the jump (it decides).
		local kinds = {}
		for _, fired in result.events do
			table.insert(kinds, fired.event.kind)
		end
		expect(kinds).toEqual({ "ActivationHold", "Sfx", "TrailOn", "TrailOff", "PostMotionStart" })
		-- Nothing of the clip is left to play out after the wake.
		for _ = 1, 30 do
			local after = mixer:step(FRAME)
			expect(#after.events).toBe(0)
			expect(after.rootDelta[3]).toBe(0)
			expect(after.jumped).toBe(false)
		end
	end)

	it("a step of jumpSeconds or less is a plain step: root motion and events as ever", function()
		local mixer = Mixer.new()
		mixer:play(lunge())
		local step = jumpSeconds()
		local result = mixer:step(step)
		expect(result.jumped).toBe(false)
		expect(result.rootDelta[3]).toBeCloseTo(-math.min(step, 0.5) * 2, 1e-6)
	end)

	it("a jump inside a clip keeps the root where it was and continues from the new clip time", function()
		local mixer = Mixer.new()
		local handle = mixer:play(clip("long", {
			duration = 4,
			keys = {
				{ time = 0, easing = "Hold", joints = {}, root = { pos = { 0, 0, 0 } } },
				{ time = 4, easing = "Linear", joints = {}, root = { pos = { 0, 0, -4 } } },
			},
		}))
		mixer:step(0.5)
		expect(mixer:step(1).rootDelta).toEqual({ 0, 0, 0 })
		expect(handle.time).toBeCloseTo(1.5, 1e-6)
		-- The next frame moves one frame's worth from where the clip now is, not the skipped second.
		expect(mixer:step(FRAME).rootDelta[3]).toBeCloseTo(-FRAME, 1e-6)
	end)

	it("a hit-stop asked for during the stall ends inside the gap: the rest of it moves the clocks", function()
		-- The measured wake (item 2026-10-24): a kill's 10-frame hit-stop landed on the rig while the
		-- display slept, so the wake step was all pause and the Art then replayed from its start.
		local mixer = Mixer.new()
		local handle = mixer:play(lunge())
		mixer:hitStop(10)
		local result = mixer:step(56)
		expect(result.jumped).toBe(true)
		expect(result.paused).toBe(false)
		expect(mixer:pauseRemaining()).toBe(0)
		expect(handle.ended).toBe(true)
		expect(result.rootDelta).toEqual({ 0, 0, 0 })
		local replayed = 0
		for _ = 1, 60 do
			local after = mixer:step(FRAME)
			replayed += #after.events
			expect(after.rootDelta[3]).toBe(0)
		end
		expect(replayed).toBe(0)
	end)

	it("a pause longer than the gap still holds: the jump moves nothing it would not have", function()
		local mixer = Mixer.new()
		local handle = mixer:play(lunge())
		mixer:step(0.1)
		local gap = jumpSeconds() + 0.1
		local frames = math.ceil((gap + 0.4) * 60)
		mixer:hitStop(frames)
		local result = mixer:step(gap)
		expect(result.jumped).toBe(true)
		expect(result.paused).toBe(true)
		expect(handle.time).toBeCloseTo(0.1, 1e-6)
		expect(#result.events).toBe(0)
		expect(mixer:pauseRemaining()).toBeCloseTo(frames * FRAME - gap, 1e-6)
	end)

	it("a frozen clock (time scale 0: a held Art stance) stays frozen through a jump", function()
		local mixer = Mixer.new()
		local handle = mixer:play(lunge())
		mixer:step(0.1)
		mixer:setTimeScale(0)
		local result = mixer:step(56)
		expect(result.jumped).toBe(true)
		expect(handle.time).toBeCloseTo(0.1, 1e-6)
		expect(#result.events).toBe(0)
	end)

	it("a death tremor (ignores the pause) still runs the whole gap and ends", function()
		local mixer = Mixer.new()
		mixer:play(lunge())
		local freeze = mixer:play(clip("enemy/Boar/DeathFreeze", { layer = "Additive", duration = 0.5 }))
		mixer:setTimeScale(0)
		local result = mixer:step(56)
		expect(result.jumped).toBe(true)
		expect(freeze.ended).toBe(true)
	end)

	-- The crossed events of one step as { kind, jumped } pairs.
	local function crossed(result: any): { { any } }
		local list = {}
		for _, fired in result.events do
			table.insert(list, { fired.event.kind, fired.jumped })
		end
		return list
	end

	it("every event a jump crossed carries the mark, and a plain step's carry none", function()
		local mixer = Mixer.new()
		mixer:play(lunge())
		expect(crossed(mixer:step(0.2))).toEqual({ { "ActivationHold", false } })
		expect(crossed(mixer:step(56))).toEqual({
			{ "Sfx", true },
			{ "TrailOn", true },
			{ "TrailOff", true },
			{ "PostMotionStart", true },
		})
	end)

	it("a clip played just before the wake moves only by its own age: the present plays on", function()
		-- A key press that wakes the display, or a remote's action that arrives just before it, starts
		-- a clip inside the gap: the wake step must show it where it is now, not jump it to its end.
		local mixer = Mixer.new()
		mixer:step(FRAME)
		local gap = 56
		local handle = mixer:play(lunge(), { sinceStep = gap - 0.2 })
		local result = mixer:step(gap)
		expect(result.jumped).toBe(true)
		expect(handle.time).toBeCloseTo(0.2, 1e-6)
		expect(handle.ended).toBe(false)
		-- Its own 0.2 s is an ordinary step: the chime fires unmarked and the lunge moves the root.
		expect(crossed(result)).toEqual({ { "ActivationHold", false } })
		expect(result.rootDelta[3]).toBeCloseTo(-0.4, 1e-6)
		-- The rest of the clip plays after the wake, as ever.
		local later = {}
		local root = 0
		for _ = 1, 60 do
			local after = mixer:step(FRAME)
			root += after.rootDelta[3]
			for _, pair in crossed(after) do
				table.insert(later, pair)
			end
		end
		expect(later).toEqual({
			{ "Sfx", false },
			{ "TrailOn", false },
			{ "TrailOff", false },
			{ "PostMotionStart", false },
		})
		expect(root).toBeCloseTo(-0.6, 1e-6)
	end)

	it("a clip played early in the gap jumps by its own age: marked, no root, the rest plays on", function()
		local mixer = Mixer.new()
		mixer:step(FRAME)
		local gap = 56
		local handle = mixer:play(
			clip("long", {
				duration = 4,
				keys = {
					{ time = 0, easing = "Hold", joints = {}, root = { pos = { 0, 0, 0 } } },
					{ time = 4, easing = "Linear", joints = {}, root = { pos = { 0, 0, -4 } } },
				},
				events = {
					{ time = 1, kind = "Sfx", data = { name = "whoosh.Medium" } },
					{ time = 3, kind = "Sfx", data = { name = "whoosh.Medium" } },
				},
			}),
			{ sinceStep = gap - 2 }
		)
		local result = mixer:step(gap)
		expect(handle.time).toBeCloseTo(2, 1e-6)
		expect(crossed(result)).toEqual({ { "Sfx", true } })
		expect(result.rootDelta).toEqual({ 0, 0, 0 })
		local later = {}
		for _ = 1, 90 do
			for _, pair in crossed(mixer:step(FRAME)) do
				table.insert(later, pair)
			end
		end
		expect(later).toEqual({ { "Sfx", false } })
	end)

	it("sinceStep only matters on a jump: an ordinary step advances a new clip by the whole step", function()
		local mixer = Mixer.new()
		local handle = mixer:play(lunge(), { sinceStep = 0.01 })
		mixer:step(FRAME)
		expect(handle.time).toBeCloseTo(FRAME, 1e-9)
	end)
end)

--[[
	A cut it hands over takes the cut clip's open trail, window and smear with it (D-408, D-410).

	A cancel holds the clip it cuts (its clock stands while it hands the body over), so the clip's
	own close events (HitWindowClose, TrailOff, SmearOff) are never crossed. A basic a dodge cut
	between its SmearOn and SmearOff kept its trail lit and its blade stretched for as long as the
	rig lived (the merged round-E tree: Basic and Smear still on 90 frames after the cut, local and
	remote alike); one a later basic cut kept its trail through the new swing's anticipation (15
	frames against 6 when the cut clip's fade still ran its clock). The cut clip's next step fires
	its close events past where it stands, once, unmarked, before any event of the clip that cut it.
]]
describe("Mixer hand-over cut closes what the cut clip opened (D-410)", function()
	local function swing()
		return clip("swing", {
			blendOut = 0.2,
			events = {
				{ time = 0.1, kind = "TrailOn", data = { kind = "Basic" } },
				{ time = 0.1, kind = "HitWindowOpen", data = { hit = 1 } },
				{ time = 0.1083, kind = "SmearOn", data = { axis = "X" } },
				{ time = 0.1417, kind = "SmearOff" },
				{ time = 0.24, kind = "HitWindowClose", data = { hit = 1 } },
				{ time = 0.27, kind = "TrailOff" },
				{ time = 0.3, kind = "PostMotionStart" },
				{ time = 0.5, kind = "Sfx", data = { name = "whoosh.Medium" } },
			},
		})
	end
	local function next(id: string)
		return clip(id, { events = { { time = 0.1, kind = "TrailOn", data = { kind = "Basic" } } } })
	end

	for _, rate in { 15, 30, 60, 144, 240 } do
		it(("at %d Hz: the closes past the stood clock fire on the cut clip's next step, once"):format(rate), function()
			local mixer = Mixer.new()
			local cut = mixer:play(swing())
			while cut.time < 0.12 do
				mixer:step(1 / rate)
			end
			local stood = cut.time
			mixer:play(next("cutter"), { handOver = true, cancels = { cut } })
			local fired = {}
			local cutterAt = nil
			for step = 1, math.ceil(rate * 0.5) do
				for _, event in mixer:step(1 / rate).events do
					if event.clipId == "swing" then
						table.insert(
							fired,
							("%d:%s%s"):format(step, event.event.kind, if event.jumped then "!" else "")
						)
					elseif cutterAt == nil then
						cutterAt = #fired
					end
				end
			end
			expect(cut.time).toBeCloseTo(stood, 1e-9)
			expect(table.concat(fired, " ")).toBe("1:SmearOff 1:HitWindowClose 1:TrailOff")
			-- The cutter's own trail lights after them, never under a close of the clip it cut.
			expect(cutterAt).toBe(3)
		end)
	end

	it("a stop, a hold or a cut that is not a hand-over closes nothing it did not cross", function()
		for _, how in { "stop", "hold", "cut" } do
			local mixer = Mixer.new()
			local cut = mixer:play(swing())
			stepFrames(mixer, 8)
			if how == "stop" then
				mixer:stop(cut, 0.2)
				mixer:hold(cut)
			elseif how == "hold" then
				mixer:hold(cut)
			else
				mixer:play(clip("cutter", { blendOut = 0.2 }))
			end
			local fired = {}
			for _ = 1, 30 do
				for _, event in mixer:step(FRAME).events do
					if event.clipId == "swing" then
						table.insert(fired, event.event.kind)
					end
				end
			end
			-- A held clip crosses nothing; a plain cut's fade runs its clock over its own closes.
			expect(table.concat(fired, " ")).toBe(
				if how == "cut" then "SmearOff HitWindowClose TrailOff PostMotionStart" else ""
			)
		end
	end)
end)
