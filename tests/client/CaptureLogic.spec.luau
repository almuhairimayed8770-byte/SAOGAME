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

	it("counts the rendered frames beside f, when it has them (D-336)", function()
		local text = Logic.counterText({
			shotId = "kill-shatter",
			frames = 42,
			rendered = 43,
			elapsed = 0.7,
			target = 5,
			scale = 1,
		})
		expect(text).toBe("kill-shatter  f 42  r 43  0.7 / 5 s  1x")
	end)

	it("the corner square swaps its two colors every rendered frame (D-336)", function()
		local tokens = Dev.capture.frameTick.tokens
		expect(Logic.tickToken(0, tokens)).toBe(tokens[1])
		expect(Logic.tickToken(1, tokens)).toBe(tokens[2])
		expect(Logic.tickToken(2, tokens)).toBe(tokens[1])
		expect(Logic.tickToken(1001, tokens)).toBe(tokens[2])
		for rendered = 0, 20 do
			expect(Logic.tickToken(rendered + 1, tokens) ~= Logic.tickToken(rendered, tokens)).toBe(true)
		end
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

-- CF: the fight's perform reacts to what the client draws (a guard on each kobold overhead, a
-- dodge on the boar's crouch, the keys that follow each) and presses its standing rules between
-- (basics on the lock's target in reach, the lock back on the kobold once it is lost); the
-- locomotion pass holds the stick (a part-pushed stick walks) and the sprint.
describe("CaptureLogic reactions, chains, standing rules and the stick (CF)", function()
	local Charge = Harness.load("src/shared/clips/enemy/Boar/Charge")

	local function openOf(clip: any): number
		for _, event in clip.events do
			if event.kind == "HitWindowOpen" then
				return event.time
			end
		end
		error("no hit window in " .. clip.id)
	end

	local function eventOf(clip: any, kind: string): any
		for _, event in clip.events do
			if event.kind == kind then
				return event
			end
		end
		error("no " .. kind .. " in " .. clip.id)
	end

	it("carries a stick's entry on its presses; standing rules and reactions are no timed presses", function()
		local walk = { action = "Move", at = 0, hold = 2.5, stick = { 0.5, 0 } }
		local presses = Logic.timedPresses({
			walk :: any,
			{ action = "BasicAttack", every = 0.4, from = 0.3, to = 19, within = 5.5, hold = 0.05 },
			{ action = "Dodge", onClip = Charge.id, enemy = 2, lead = 0.3, hold = 0.05 },
		})
		expect(#presses).toBe(2)
		expect(presses[1].action).toBe("Move")
		expect(presses[1].down).toBe(true)
		expect(presses[1].entry).toBe(walk)
		expect(presses[2].down).toBe(false)
		expect(presses[2].at).toBeCloseTo(2.5, 1e-9)
		expect(presses[2].entry).toBe(walk)
	end)

	it("queues a reaction's let-go among the timed presses in time order", function()
		local queue = Logic.timedPresses({
			{ action = "LockOn", at = 5, hold = 0.05 },
			{ action = "Art", at = 1, hold = 0.5 },
		})
		-- At the parry snapshot the guard's let-go went on the end, behind presses due before it.
		Logic.enqueue(queue, { at = 1.2, action = "Guard", down = false })
		Logic.enqueue(queue, { at = 1.5, action = "Dodge", down = true })
		local order = {}
		for _, entry in queue do
			table.insert(order, ("%s%s@%g"):format(entry.action, if entry.down then "+" else "-", entry.at))
		end
		-- A let-go comes before a press at the same moment.
		expect(table.concat(order, " ")).toBe("Art+@1 Guard-@1.2 Art-@1.5 Dodge+@1.5 LockOn+@5 LockOn-@5.05")
	end)

	it("keeps one reaction per clip-timed entry, in list order", function()
		local guard = { action = "Guard", onClip = Overhead.id, lead = 0.08, hold = 0.3, repeats = true }
		local dodge = { action = "Dodge", onClip = Charge.id, enemy = 2, lead = 0.3, hold = 0.05 }
		local reactions = Logic.reactions({ { action = "Art", at = 1, hold = 0.5 }, guard :: any, dodge :: any })
		expect(#reactions).toBe(2)
		expect(reactions[1].entry).toBe(guard)
		expect(reactions[2].entry).toBe(dodge)
		expect(reactions[1].at).toBeNil()
		expect(reactions[1].count).toBe(0)
	end)

	it(
		"sets the press `lead` before the hit window from the event heard, and moves it on with each later one",
		function()
			local reaction = Logic.reactions({
				{ action = "Guard", onClip = Overhead.id, lead = 0.08, hold = 0.3, repeats = true },
			})[1]
			local open = openOf(Overhead)
			local voice = Overhead.events[1]
			-- Heard 2 s into the take at the voice line: the guard goes down open - voice - lead later.
			expect(Logic.hear(reaction, Overhead.events, voice.time, 2)).toBe(true)
			expect(reaction.at).toBeCloseTo(2 + open - voice.time - 0.08, 1e-9)
			-- The whoosh comes 0.2 s late (the kobold's hit-stop held the clip): the guard moves with it.
			local whoosh = eventOf(Overhead, "Sfx")
			local heardAt = 2 + (whoosh.time - voice.time) + 0.2
			expect(Logic.hear(reaction, Overhead.events, whoosh.time, heardAt)).toBe(true)
			expect(reaction.at).toBeCloseTo(heardAt + open - whoosh.time - 0.08, 1e-9)
			-- The window itself is too late to move it.
			local before = reaction.at
			expect(Logic.hear(reaction, Overhead.events, open, heardAt + 0.2)).toBe(false)
			expect(reaction.at).toBe(before)
		end
	)

	it("sets the press the client's latency lead earlier still, never before the moment heard (D-289)", function()
		local reaction = Logic.reactions({
			{ action = "Guard", onClip = Overhead.id, lead = 0.05, hold = 0.4, repeats = true },
		})[1]
		local open = openOf(Overhead)
		local voice = Overhead.events[1]
		-- The press leaves 0.06 s early, as the glint shows: it reaches the server as one with no
		-- latency would.
		expect(Logic.hear(reaction, Overhead.events, voice.time, 2, 0.06)).toBe(true)
		expect(reaction.at).toBeCloseTo(2 + open - voice.time - 0.05 - 0.06, 1e-9)
		-- Heard later than the lead allows: it goes at once, never before the moment it was heard.
		local late = open - 0.07
		expect(Logic.hear(reaction, Overhead.events, late, 3, 0.06)).toBe(true)
		expect(reaction.at).toBeCloseTo(3, 1e-9)
		-- Only a guard leaves early (the server judges the parry window on its clock); a dodge
		-- stays on the clip as drawn, where its chain meets the drawn body.
		local dodge = Logic.reactions({ { action = "Dodge", onClip = Overhead.id, lead = 0.05, hold = 0.05 } })[1]
		expect(Logic.hear(dodge, Overhead.events, voice.time, 2, 0.06)).toBe(true)
		expect(dodge.at).toBeCloseTo(2 + open - voice.time - 0.05, 1e-9)
	end)

	it("sets no press past the reaction's `to`, and keeps a chain's steps inside it (CF, D-320)", function()
		local reaction = Logic.reactions({
			{ action = "Guard", onClip = Overhead.id, lead = 0.04, hold = 0.3, repeats = true, to = 10 },
		})[1]
		local open = openOf(Overhead)
		local voice = Overhead.events[1]
		-- Heard so its press comes at 10 - 0.5: set.
		local heardAt = 10 - 0.5 - (open - voice.time - 0.04)
		expect(Logic.hear(reaction, Overhead.events, voice.time, heardAt)).toBe(true)
		expect(reaction.at).toBeCloseTo(9.5, 1e-9)
		-- The next play heard so its press would come past `to`: nothing waits.
		Logic.pressed(reaction)
		Logic.hear(reaction, Overhead.events, open, heardAt + 1)
		expect(Logic.hear(reaction, Overhead.events, voice.time, heardAt + 1.5)).toBe(false)
		expect(reaction.at).toBeNil()
		-- A chain step goes down at or before its reaction's `to`, never after.
		expect(Logic.inside(reaction.entry, 10)).toBe(true)
		expect(Logic.inside(reaction.entry, 10.01)).toBe(false)
		expect(Logic.inside({ action = "Guard", hold = 0.3 }, 1e6)).toBe(true)
	end)

	it("presses once a play: the rest of a pressed play is not heard, the next play is (repeats)", function()
		local reaction = Logic.reactions({
			{ action = "Guard", onClip = Overhead.id, lead = 0.08, hold = 0.3, repeats = true },
		})[1]
		local voice = Overhead.events[1]
		local whoosh = eventOf(Overhead, "Sfx")
		Logic.hear(reaction, Overhead.events, voice.time, 1)
		Logic.pressed(reaction)
		expect(reaction.at).toBeNil()
		expect(reaction.count).toBe(1)
		-- Still the same play: an event before the window heard after the press moves nothing.
		expect(Logic.hear(reaction, Overhead.events, whoosh.time, 2)).toBe(false)
		expect(reaction.at).toBeNil()
		Logic.hear(reaction, Overhead.events, openOf(Overhead), 2.2)
		-- The next play starts over at its voice line.
		expect(Logic.hear(reaction, Overhead.events, voice.time, 5)).toBe(true)
		expect(reaction.at).never.toBeNil()
	end)

	it("moves a waiting press on by its attacker's hit-stop pause, and nothing else", function()
		local reaction = Logic.reactions({
			{ action = "Guard", onClip = Overhead.id, lead = 0.08, hold = 0.3, repeats = true },
		})[1]
		Logic.pause(reaction, 0.2)
		expect(reaction.at).toBeNil()
		Logic.hear(reaction, Overhead.events, Overhead.events[1].time, 2)
		local at = reaction.at :: number
		Logic.pause(reaction, 0.2)
		expect(reaction.at).toBeCloseTo(at + 0.2, 1e-9)
	end)

	it("presses on the first play only unless it repeats", function()
		local reaction = Logic.reactions({ { action = "Guard", onClip = Overhead.id, lead = 0.05, hold = 0.4 } })[1]
		local voice = Overhead.events[1]
		expect(Logic.hear(reaction, Overhead.events, voice.time, 1)).toBe(true)
		Logic.pressed(reaction)
		Logic.hear(reaction, Overhead.events, openOf(Overhead), 2.2)
		expect(Logic.hear(reaction, Overhead.events, voice.time, 5)).toBe(false)
		expect(reaction.at).toBeNil()
	end)

	it("dodges the boar's crouch `lead` before its launch", function()
		local reaction = Logic.reactions({
			{ action = "Dodge", onClip = Charge.id, enemy = 2, lead = 0.3, hold = 0.05, repeats = true },
		})[1]
		local first = Charge.events[1]
		expect(Logic.hear(reaction, Charge.events, first.time, 9)).toBe(true)
		expect(reaction.at).toBeCloseTo(9 + openOf(Charge) - first.time - 0.3, 1e-9)
	end)

	it("presses a standing rule every `every` seconds inside its span", function()
		local rule = Logic.standing({
			{ action = "Art", at = 1, hold = 0.5 },
			{ action = "BasicAttack", every = 0.4, from = 0.3, to = 19, within = 5.5, hold = 0.05 } :: any,
		})
		expect(#rule).toBe(1)
		local basics = rule[1]
		expect(Logic.standingDue(basics, 0.2)).toBe(false)
		expect(Logic.standingDue(basics, 0.3)).toBe(true)
		basics.last = 0.3
		expect(Logic.standingDue(basics, 0.6)).toBe(false)
		expect(Logic.standingDue(basics, 0.7)).toBe(true)
		basics.last = 18.9
		expect(Logic.standingDue(basics, 19.3)).toBe(false)
		-- With no span it stands for the whole take.
		local keep = Logic.standing({ { action = "LockOn", every = 0.2, hold = 0.05 } })[1]
		expect(Logic.standingDue(keep, 0)).toBe(true)
		expect(Logic.standingDue(keep, 1000)).toBe(true)
	end)

	it("presses the next action of a step's cycle each time it comes round", function()
		local step = { action = "Art", hold = 0.5, delay = 0.15, cycle = { "Art", "ArtSlot2", "ArtSlot4", "ArtSlot3" } }
		expect(Logic.cycleAction(step :: any, 1)).toBe("Art")
		expect(Logic.cycleAction(step :: any, 2)).toBe("ArtSlot2")
		expect(Logic.cycleAction(step :: any, 4)).toBe("ArtSlot3")
		expect(Logic.cycleAction(step :: any, 5)).toBe("Art")
		expect(Logic.cycleAction({ action = "Dodge", hold = 0.05, delay = 0 } :: any, 3)).toBe("Dodge")
	end)

	it("turns a stick on the camera's view into Humanoid:Move's camera-relative vector", function()
		-- Right is +X, forward is -Z (Humanoid:Move relative to the camera).
		local x, z = Logic.stickMove({ 0.5, 0 })
		expect(x).toBeCloseTo(0.5, 1e-9)
		expect(z).toBeCloseTo(0, 1e-9)
		x, z = Logic.stickMove({ 0, 1 })
		expect(x).toBeCloseTo(0, 1e-9)
		expect(z).toBeCloseTo(-1, 1e-9)
		-- Never past a full push.
		x, z = Logic.stickMove({ 3, 4 })
		expect(math.sqrt(x * x + z * z)).toBeCloseTo(1, 1e-9)
	end)

	it("names a staged enemy by its index, the staged target when the reply listed none", function()
		expect(Logic.enemyId({ 21, 22 }, 21, 2)).toBe(22)
		expect(Logic.enemyId({ 21, 22 }, 21, nil)).toBe(21)
		expect(Logic.enemyId({ 21 }, 21, 2)).toBeNil()
		expect(Logic.enemyId(nil, 21, 1)).toBe(21)
		expect(Logic.enemyId(nil, 21, 2)).toBeNil()
		expect(Logic.enemyId(nil, nil, nil)).toBeNil()
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

	it(
		"steers along the route, past each point within reach, follows the last leg's line, lets go the carry short",
		function()
			local walk = Logic.walkFrom(reply(true, 0, -10)) :: any
			local path = walk.path
			local dx, dz = Logic.steer(walk, 0, -10, 1.5, 2, 1.5)
			expect(math.abs(math.sqrt((dx :: number) ^ 2 + (dz :: number) ^ 2) - 1)).toBeLessThan(1e-9)
			expect(walk.index).toBe(1)
			-- At the first point: on to the second.
			Logic.steer(walk, path[1][1] + 1, path[1][2], 1.5, 2, 1.5)
			expect(walk.index).toBe(2)
			-- Near the approach, a stud off the leg's line: on to the last leg, aiming 1.5 studs along it
			-- past the root's foot on the line, back toward it.
			local approach = path[#path - 1]
			local spot = path[#path]
			local lx, lz = StageLogic.look(walk.facing)
			walk.index = #path - 1
			local sideX, sideZ = -lz, lx
			dx, dz = Logic.steer(walk, approach[1] + sideX, approach[2] + sideZ, 1.5, 2, 1.5)
			expect(walk.index).toBe(#path)
			expect((dx :: number) * lx + (dz :: number) * lz).toBeCloseTo(math.cos(math.atan(1 / 1.5)), 1e-9)
			expect((dx :: number) * sideX + (dz :: number) * sideZ).toBeLessThan(0)
			-- On the line: straight along the spot's facing.
			dx, dz = Logic.steer(walk, spot[1] - lx * 4, spot[2] - lz * 4, 1.5, 2, 1.5)
			expect((dx :: number) * lx + (dz :: number) * lz).toBeGreaterThan(1 - 1e-9)
			-- The spot no more than letGo ahead along the leg: let go, wherever across the line the root
			-- stands (and asked again, still let go); past the spot too.
			expect(Logic.steer(walk, spot[1] - lx * 1.9, spot[2] - lz * 1.9, 1.5, 2, 1.5)).toBeNil()
			expect(Logic.steer(walk, spot[1] - lx * 1.9 + sideX, spot[2] - lz * 1.9 + sideZ, 1.5, 2, 1.5)).toBeNil()
			expect(Logic.steer(walk, spot[1] + lx, spot[2] + lz, 1.5, 2, 1.5)).toBeNil()
			-- Pushed back off it: steers for it again.
			expect(Logic.steer(walk, spot[1] - lx * 3, spot[2] - lz * 3, 1.5, 2, 1.5)).never.toBeNil()
		end
	)

	it("steers straight for the spot on a route of the spot alone, and lets go within letGo of it", function()
		local walk = Logic.walkFrom({
			ok = false,
			walk = { x = 0, y = 0, z = -10, facing = 0, radius = 3, tolerance = 1 },
		}) :: any
		expect(Logic.lastLeg(walk)).toBeNil()
		local dx, dz = Logic.steer(walk, 4, -10, 1.5, 0.5, 1.5)
		expect(dx).toBeCloseTo(-1, 1e-9)
		expect(dz).toBeCloseTo(0, 1e-9)
		expect(Logic.steer(walk, 0.4, -10, 1.5, 0.5, 1.5)).toBeNil()
		expect(Logic.ahead(walk, 3, -6)).toBeCloseTo(5, 1e-9)
	end)

	it("reads the last leg and how far the spot is still ahead along it", function()
		local walk = Logic.walkFrom(reply(false, 25, 30)) :: any
		local lx, lz = StageLogic.look(walk.facing)
		local ux, uz = Logic.lastLeg(walk)
		expect(ux).toBeCloseTo(lx, 1e-9)
		expect(uz).toBeCloseTo(lz, 1e-9)
		local spot = walk.path[#walk.path]
		expect(Logic.ahead(walk, spot[1] - lx * 2.5, spot[2] - lz * 2.5)).toBeCloseTo(2.5, 1e-9)
		-- Across the line counts nothing; past the spot is below 0.
		expect(Logic.ahead(walk, spot[1] - lx * 2.5 - lz, spot[2] - lz * 2.5 + lx)).toBeCloseTo(2.5, 1e-9)
		expect(Logic.ahead(walk, spot[1] + lx, spot[2] + lz)).toBeCloseTo(-1, 1e-9)
	end)

	it("lets go the stop's carry short: none past the Skid's threshold, speed x carrySeconds below it", function()
		expect(Logic.stopCarry(24, 18, 0.186)).toBe(0)
		expect(Logic.stopCarry(18.5, 18, 0.186)).toBe(0)
		expect(Logic.stopCarry(16, 18, 0.186)).toBeCloseTo(16 * 0.186, 1e-9)
		expect(Logic.stopCarry(0, 18, 0.186)).toBe(0)
	end)

	it("reads how far a body at rest is off the spot and its facing", function()
		local walk = Logic.walkFrom(reply(false, 25, 30)) :: any
		local lx, lz = StageLogic.look(walk.facing)
		local studs, degrees = Logic.restOff(walk, walk.x, walk.z, lx, lz)
		expect(studs).toBeCloseTo(0, 1e-9)
		expect(degrees).toBeCloseTo(0, 1e-6)
		studs, degrees = Logic.restOff(walk, walk.x + 0.6, walk.z - 0.8, -lz * 3, lx * 3)
		expect(studs).toBeCloseTo(1, 1e-9)
		expect(degrees).toBeCloseTo(90, 1e-6)
		studs, degrees = Logic.restOff(walk, walk.x, walk.z, -lx, -lz)
		expect(degrees).toBeCloseTo(180, 1e-6)
		local turned = math.rad(4)
		local tx = lx * math.cos(turned) - lz * math.sin(turned)
		local tz = lx * math.sin(turned) + lz * math.cos(turned)
		studs, degrees = Logic.restOff(walk, walk.x, walk.z, tx, tz)
		expect(degrees).toBeCloseTo(4, 1e-6)
		-- No look (a root with no facing): as far off as it gets.
		studs, degrees = Logic.restOff(walk, walk.x, walk.z, 0, 0)
		expect(degrees).toBe(180)
	end)

	it("waits out the server's rate before the next ask", function()
		expect(Logic.askWait(nil, 10, 2)).toBe(0)
		expect(Logic.askWait(10, 10.2, 2)).toBeCloseTo(0.3, 1e-9)
		expect(Logic.askWait(10, 10.5, 2)).toBe(0)
		expect(Logic.askWait(10, 11, 2)).toBe(0)
	end)
end)

-- D-290: auto-perform's lock presses in a staged take act on the staged target alone. The lock
-- key's own path (TargetController.toggle) cycles best, next one down, then off, so the
-- locomotion pass's second press could lock a field enemy nearer than the staged one.
describe("CaptureLogic auto-perform's lock press (D-290)", function()
	it("locks the staged target when the lock is off or on another enemy, lets it go when on it", function()
		expect(Logic.lockPress(21, nil)).toBe("Lock")
		expect(Logic.lockPress(21, 99)).toBe("Lock")
		expect(Logic.lockPress(21, 21)).toBe("Release")
	end)

	it("takes the lock key's own path when the take staged no target (outside Studio)", function()
		expect(Logic.lockPress(nil, nil)).toBe("Key")
		expect(Logic.lockPress(nil, 99)).toBe("Key")
	end)
end)

-- D-290: a take that stops lets go of every key auto-perform holds, and none acts on the way up:
-- an Art key's hold is cancelled before its key comes up (the release would launch the Art).
describe("CaptureLogic letting go at a stop (D-290)", function()
	local Input = Harness.load("src/shared/data/input")

	it("lists each held key once, in name order, an Art key with its slot to cancel first", function()
		local keys = Logic.letGo({ Guard = true, ArtSlot2 = true, Art = true }, Input.artSlot)
		expect(#keys).toBe(3)
		expect(keys[1].action).toBe("Art")
		expect(keys[1].slot).toBe(Input.artSlot("Art"))
		expect(keys[2].action).toBe("ArtSlot2")
		expect(keys[2].slot).toBe(2)
		expect(keys[3].action).toBe("Guard")
		expect(keys[3].slot).toBeNil()
		expect(#Logic.letGo({}, Input.artSlot)).toBe(0)
	end)
end)
