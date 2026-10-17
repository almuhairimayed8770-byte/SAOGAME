--!strict
local Mixer = Harness.load("src/client/choreo/Mixer")
local ChoreoData = Harness.load("src/shared/data/choreo")

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

	it("blend-space weights move toward their target at the data rate", function()
		local mixer = Mixer.new()
		local walk = mixer:play(clip("walk", { layer = "Base", loop = true }), { coexist = true, weight = 0 })
		mixer:setWeight(walk, 1)
		mixer:step(0.05)
		expect(walk.weight).toBeCloseTo(0.05 * ChoreoData.locomotion.weightBlendRate, 1e-6)
		mixer:setWeight(walk, 0.25, true)
		expect(walk.weight).toBe(0.25)
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
