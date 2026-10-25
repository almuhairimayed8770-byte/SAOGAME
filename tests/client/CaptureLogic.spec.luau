--!strict
--[[
	CaptureLogic (src/client/dev/CaptureLogic.luau): the capture panel's pure rules (F12). The
	counter's line, what K does before and at the target length, the prompt line at a moment of the
	take, and auto-perform's presses: the timed ones from a shot's perform list, and the parry's,
	timed off the attack clip the client is drawing.
]]

local Logic = Harness.load("src/client/dev/CaptureLogic")
local Dev = Harness.load("src/shared/data/dev")
local Overhead = Harness.load("src/shared/clips/enemy/Kobold/Overhead")

local function shotById(id: string): any
	for _, shot in Dev.capture.shots do
		if shot.id == id then
			return shot
		end
	end
	error("no shot " .. id)
end

describe("CaptureLogic counter", function()
	it("names the shot, the frame, the time against the target and the scale", function()
		local text = Logic.counterText({ shotId = "art-vertical", frames = 42, elapsed = 0.7, target = 5, scale = 1 })
		expect(text).toBe("art-vertical  f 42  0.7 / 5 s  1x")
		text = Logic.counterText({ shotId = "locomotion", frames = 0, elapsed = 0, target = 14, scale = 0.25 })
		expect(text).toBe("locomotion  f 0  0.0 / 14 s  0.25x")
	end)

	it("says when auto-perform presses, and what a second K does while a stop waits to be confirmed", function()
		local text = Logic.counterText({
			shotId = "kill-shatter",
			frames = 9,
			elapsed = 0.15,
			target = 5,
			scale = 1,
			auto = true,
			confirming = true,
			markKey = "K",
		})
		expect(text:find("auto", 1, true)).never.toBeNil()
		expect(text:find("K again", 1, true)).never.toBeNil()
	end)
end)

describe("CaptureLogic K (mark done)", function()
	it("marks the take done at or past the target length", function()
		expect(Logic.markDecision(5, 5, 100, nil)).toBe("Done")
		expect(Logic.markDecision(6.2, 5, 100, nil)).toBe("Done")
	end)

	it("asks to confirm before the target, and stops unmarked on a second K inside the window", function()
		expect(Logic.markDecision(2, 5, 100, nil)).toBe("Confirm")
		expect(Logic.markDecision(2.5, 5, 100.5, 102)).toBe("Stop")
		-- The window ran out: asked again.
		expect(Logic.markDecision(4.5, 5, 102.5, 102)).toBe("Confirm")
	end)
end)

describe("CaptureLogic prompt", function()
	local prompts = { { at = 0, text = "a" }, { at = 1, text = "b" }, { at = 2.5, text = "c" } }

	it("shows the last beat that has come", function()
		expect(Logic.promptAt(prompts, 0)).toBe("a")
		expect(Logic.promptAt(prompts, 0.99)).toBe("a")
		expect(Logic.promptAt(prompts, 1)).toBe("b")
		expect(Logic.promptAt(prompts, 4)).toBe("c")
		expect(Logic.promptAt({}, 1)).toBeNil()
		expect(Logic.promptAt({ { at = 1, text = "late" } }, 0.5)).toBeNil()
	end)
end)

describe("CaptureLogic auto-perform", function()
	it("turns a shot's timed keys into downs and ups in time order, leaving the clip-timed ones out", function()
		local presses = Logic.timedPresses({
			{ action = "LockOn", at = 5.8, hold = 0.05 },
			{ action = "Art", at = 1, hold = 0.35 },
			{ action = "Guard", onClip = "enemy/Kobold/Overhead", lead = 0.05, hold = 0.4 },
		})
		expect(#presses).toBe(4)
		expect(presses[1]).toEqual({ at = 1, action = "Art", down = true })
		expect(presses[2].at).toBeCloseTo(1.35, 1e-9)
		expect(presses[2].action).toBe("Art")
		expect(presses[2].down).toBe(false)
		expect(presses[3]).toEqual({ at = 5.8, action = "LockOn", down = true })
		expect(presses[4].down).toBe(false)
	end)

	it("hands out the presses due by a moment, once each, in order", function()
		local queue = Logic.timedPresses({ { action = "Art", at = 1, hold = 0.35 } })
		expect(#Logic.due(queue, 0.5)).toBe(0)
		local first = Logic.due(queue, 1.1)
		expect(#first).toBe(1)
		expect(first[1].down).toBe(true)
		expect(#Logic.due(queue, 1.1)).toBe(0)
		local second = Logic.due(queue, 2)
		expect(#second).toBe(1)
		expect(second[1].down).toBe(false)
		expect(#queue).toBe(0)
	end)

	it("puts the parry's guard `lead` before the overhead's hit window, from whichever event was heard", function()
		local window = nil :: number?
		for _, event in Overhead.events do
			if event.kind == "HitWindowOpen" then
				window = event.time
				break
			end
		end
		expect(window).never.toBeNil()
		local open = window :: number
		-- Heard at the voice line (0.15 s in): the guard goes down open - 0.15 - lead from now.
		expect(Logic.parryDelay(Overhead.events, 0.15, 0.05)).toBeCloseTo(open - 0.15 - 0.05, 1e-9)
		-- Heard too late (the window is on us): nothing.
		expect(Logic.parryDelay(Overhead.events, open, 0.05)).toBeNil()
		-- A clip with no window: nothing.
		expect(Logic.parryDelay({ { time = 0.1, kind = "Voice" } }, 0.1, 0.05)).toBeNil()
		-- The parry lands inside the parry window: the guard is up `lead` before the window opens.
		local combat = Harness.load("src/shared/data/combat")
		local parry = shotById("parry-spark").perform[1]
		expect(parry.lead).toBeGreaterThan(0)
		expect(parry.lead).toBeLessThan(combat.parryWindow)
	end)

	it("presses only when on, and only at 1x", function()
		expect(Logic.performs(true, 1)).toBe(true)
		expect(Logic.performs(false, 1)).toBe(false)
		expect(Logic.performs(true, 0.5)).toBe(false)
	end)
end)

describe("CaptureLogic walk into the stand ring (D-244)", function()
	local StageLogic = Harness.load("src/server/dev/DevStageLogic")
	local Stage = Dev.capture.stage

	-- A walk reply as DevStage sends it.
	local function reply(open: boolean, fromX: number, fromZ: number): any
		local walk = table.clone(StageLogic.ring(open, Stage)) :: any
		walk.path = StageLogic.route(open, Stage, true, fromX, fromZ)
		return { ok = false, error = "walk into the ring first", walk = walk }
	end

	it("reads the walk off a staging reply, steering for the route's first point", function()
		local sent = reply(true, 0, -10)
		local walk = Logic.walkFrom(sent) :: any
		expect(walk ~= nil).toBe(true)
		for _, key in { "x", "y", "z", "facing", "radius", "tolerance" } do
			expect(walk[key]).toBe(sent.walk[key])
		end
		expect(walk.over).toEqual(sent.walk.over)
		expect(walk.path).toEqual(sent.walk.path)
		expect(walk.index).toBe(1)
		-- A fresh table: steering never writes into the reply.
		expect(walk.path ~= sent.walk.path).toBe(true)
	end)

	it("reads no walk off a reply without one, or a malformed one; a walk with no route steers to the spot", function()
		expect(Logic.walkFrom(nil)).toBeNil()
		expect(Logic.walkFrom({ ok = true, targetId = 4 })).toBeNil()
		expect(Logic.walkFrom({ ok = false, error = "busy" })).toBeNil()
		local bad = reply(false, 0, 30)
		bad.walk.radius = "3"
		expect(Logic.walkFrom(bad)).toBeNil()
		bad = reply(true, 0, 30)
		bad.walk.over = { 1, 2, 3 }
		expect(Logic.walkFrom(bad)).toBeNil()
		bad = reply(false, 0, 30)
		bad.walk.path = { { 1, 0 / 0 } }
		expect(Logic.walkFrom(bad)).toBeNil()
		local bare = reply(false, 0, 30)
		bare.walk.path = nil
		local walk = Logic.walkFrom(bare) :: any
		expect(walk.path).toEqual({ { bare.walk.x, bare.walk.z } })
	end)

	it("judges the ring by the rule the server stages by", function()
		for _, open in { false, true } do
			local ring = StageLogic.ring(open, Stage)
			local walk = Logic.walkFrom(reply(open, 0, 90)) :: any
			for dx = -4, 4, 0.5 do
				for dz = -4, 4, 0.5 do
					for _, dy in { -1.5, -0.5, 0, 0.9, 1.5 } do
						local x, y, z = ring.x + dx, ring.y + dy, ring.z + dz
						expect(Logic.inRing(walk, x, y, z)).toBe(StageLogic.inRing(ring, x, y, z))
					end
				end
			end
		end
	end)

	it("steers along the route, past each point within reach, and lets go within arrive of the spot", function()
		local walk = Logic.walkFrom(reply(true, 0, -10)) :: any
		local path = walk.path
		local dx, dz = Logic.steer(walk, 0, -10, 1.5, 2)
		expect(math.abs(math.sqrt((dx :: number) ^ 2 + (dz :: number) ^ 2) - 1)).toBeLessThan(1e-9)
		expect(walk.index).toBe(1)
		-- At the first point: on to the second.
		Logic.steer(walk, path[1][1] + 1, path[1][2], 1.5, 2)
		expect(walk.index).toBe(2)
		-- Near the approach: on to the spot, heading along the facing.
		local approach = path[#path - 1]
		walk.index = #path - 1
		dx, dz = Logic.steer(walk, approach[1], approach[2] + 1, 1.5, 2)
		expect(walk.index).toBe(#path)
		local lx, lz = StageLogic.look(walk.facing)
		expect((dx :: number) * lx + (dz :: number) * lz).toBeGreaterThan(0.999)
		-- Within arrive of the spot: let go (and asked again, still let go).
		local spot = path[#path]
		expect(Logic.steer(walk, spot[1], spot[2] + 1.9, 1.5, 2)).toBeNil()
		expect(Logic.steer(walk, spot[1], spot[2] + 1.9, 1.5, 2)).toBeNil()
		-- Pushed back off it: steers for it again.
		expect(Logic.steer(walk, spot[1], spot[2] + 3, 1.5, 2)).never.toBeNil()
	end)

	it("waits out the server's rate before the next ask", function()
		expect(Logic.askWait(nil, 10, 2)).toBe(0)
		expect(Logic.askWait(10, 10.2, 2)).toBeCloseTo(0.3, 1e-9)
		expect(Logic.askWait(10, 10.5, 2)).toBe(0)
		expect(Logic.askWait(10, 11, 2)).toBe(0)
	end)
end)
