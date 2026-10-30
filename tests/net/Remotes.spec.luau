--!strict
local Remotes = Harness.load("src/shared/net/Remotes")
local World = Harness.load("src/shared/data/world")
local AI = Harness.load("src/shared/data/ai")

describe("Remotes", function()
	it("every client-to-server remote has a rate limit and a strict schema", function()
		for _, definition in Remotes do
			if definition.direction == "ClientToServer" then
				expect(definition.rate).toBeTruthy()
				expect(definition.rate.perSecond).toBeGreaterThan(0)
				expect(definition.rate.burst).toBeGreaterThanOrEqual(1)
				-- a strict schema rejects an unexpected field
				local ok = definition.schema({ unexpectedField = true })
				expect(ok).toBe(false)
			else
				expect(definition.rate).toBeNil()
			end
			expect(definition.kind == "Event" or definition.kind == "Unreliable" or definition.kind == "Function").toBe(
				true
			)
		end
	end)

	it("every rate limit comes from world.luau anticheat.remoteRates under the remote's name", function()
		local rates = World.anticheat.remoteRates
		local limited = 0
		for name, definition in Remotes do
			if definition.direction == "ClientToServer" then
				limited += 1
				expect(rates[name]).toBeTruthy()
				expect(definition.rate).toBe(rates[name])
			end
		end
		local listed = 0
		for name in rates do
			listed += 1
			expect(Remotes[name]).toBeTruthy()
			expect(Remotes[name].direction).toBe("ClientToServer")
		end
		expect(listed).toBe(limited)
	end)

	it("ArtRequest accepts a well-formed payload and rejects a non-unit facing", function()
		local good = { artId = "OneHandedSword.Horizontal", facing = { 0, 0, -1 }, clientTime = 12.5 }
		expect(Remotes.ArtRequest.schema(good)).toBe(true)
		local bad = { artId = "OneHandedSword.Horizontal", facing = { 0, 0, -50 }, clientTime = 12.5 }
		expect(Remotes.ArtRequest.schema(bad)).toBe(false)
		expect(Remotes.ArtRequest.schema({ artId = 5, facing = { 0, 0, -1 }, clientTime = 1 })).toBe(false)
		expect(Remotes.ArtRequest.schema("ArtRequest")).toBe(false)
	end)

	it("HitConfirmed carries the hit-stop tier and the real damage", function()
		local payload = {
			attackerId = 1,
			targetId = 2,
			damage = 37,
			crit = false,
			gaugeDamage = 12,
			killed = false,
			broke = false,
			hitStop = "Normal",
			position = { 1, 2, 3 },
			parried = false,
			guarded = false,
			reflected = false,
			hitIndex = 1,
		}
		expect(Remotes.HitConfirmed.schema(payload)).toBe(true)
		payload.hitStop = "Huge"
		expect(Remotes.HitConfirmed.schema(payload)).toBe(false)
	end)

	it("HitConfirmed carries the HP the hit removed beside its damage (FK5)", function()
		local payload = {
			attackerId = 1,
			targetId = 2,
			damage = 37,
			hpRemoved = 1,
			crit = true,
			gaugeDamage = 12,
			killed = true,
			broke = false,
			hitStop = "Kill",
			position = { 1, 2, 3 },
			parried = false,
			guarded = false,
			reflected = false,
			hitIndex = 1,
		}
		expect(Remotes.HitConfirmed.schema(payload)).toBe(true)
		payload.hpRemoved = 0
		expect(Remotes.HitConfirmed.schema(payload)).toBe(true)
		payload.hpRemoved = -1
		expect(Remotes.HitConfirmed.schema(payload)).toBe(false)
		payload.hpRemoved = "1" :: any
		expect(Remotes.HitConfirmed.schema(payload)).toBe(false)
	end)

	it("HitConfirmed may carry the pause it added to the target's attack (D-168)", function()
		local payload = {
			attackerId = 1,
			targetId = 2,
			damage = 37,
			crit = false,
			gaugeDamage = 12,
			killed = false,
			broke = false,
			hitStop = "Normal",
			position = { 1, 2, 3 },
			parried = false,
			guarded = false,
			reflected = false,
			hitIndex = 1,
			attackPause = 0.05,
		}
		expect(Remotes.HitConfirmed.schema(payload)).toBe(true)
		payload.attackPause = 0
		expect(Remotes.HitConfirmed.schema(payload)).toBe(true)
		payload.attackPause = -0.05
		expect(Remotes.HitConfirmed.schema(payload)).toBe(false)
		payload.attackPause = 5
		expect(Remotes.HitConfirmed.schema(payload)).toBe(false)
	end)

	it("a rush's launch and early end are reliable messages with the server's line and clock (D-169)", function()
		-- Reliable: a rush the server launched is drawn on every client even when a packet is lost;
		-- a lost launch drew the telegraph's guess and a lost end ran the body on past its stop.
		expect(Remotes.RushStarted.kind).toBe("Event")
		expect(Remotes.RushStarted.direction).toBe("ServerToClient")
		expect(Remotes.RushEnded.kind).toBe("Event")
		expect(Remotes.RushEnded.direction).toBe("ServerToClient")
		local started = {
			entityId = 4,
			attackId = "Charge",
			serverTime = 120.5,
			origin = { 10, 3, -4 },
			direction = { 0, 0, -1 },
			speed = 28,
			duration = 0.786,
		}
		expect(Remotes.RushStarted.schema(started)).toBe(true)
		started.direction = { 0, 0, -3 }
		expect(Remotes.RushStarted.schema(started)).toBe(false)
		local ended = { entityId = 4, launchedAt = 120.5, serverTime = 120.8, distance = 6.5, reason = "Jammed" }
		expect(Remotes.RushEnded.schema(ended)).toBe(true)
		for _, reason in { "Interrupted", "Died", "Stopped" } do
			ended.reason = reason
			expect(Remotes.RushEnded.schema(ended)).toBe(true)
		end
		ended.reason = "Done" -- a rush that ran its time sends nothing
		expect(Remotes.RushEnded.schema(ended)).toBe(false)
		ended.reason = "Jammed"
		ended.distance = -1
		expect(Remotes.RushEnded.schema(ended)).toBe(false)
	end)

	it("RushEnded carries every RushEndedReason, and a dropped attack with no contact (D-254)", function()
		-- The server builds this payload as a Types.RushEndedPayload: these are Types.RushEndedReason.
		local reasons = { "Jammed", "Interrupted", "Died", "Stopped", "Wall", "Dropped" }
		local ended: any = { entityId = 4, launchedAt = 120.5, serverTime = 120.8, distance = 0, reason = "Dropped" }
		for _, reason in reasons do
			ended.reason = reason
			expect(Remotes.RushEnded.schema(ended)).toBe(true)
		end
		for _, reason in { "Done", "Dropped ", "jammed", "" } do
			ended.reason = reason
			expect(Remotes.RushEnded.schema(ended)).toBe(false)
		end
	end)

	it("a slam ends a rush with where the body meets the face (D-208)", function()
		local ended: any = {
			entityId = 4,
			launchedAt = 120.5,
			serverTime = 120.55,
			distance = 2.4,
			reason = "Wall",
			contact = { 10, 2.3, -12 },
			normal = { 0, 0, 1 },
		}
		expect(Remotes.RushEnded.schema(ended)).toBe(true)
		-- The contact is optional (an old server, a stop with no face), a normal must be a unit.
		ended.contact = nil
		ended.normal = nil
		expect(Remotes.RushEnded.schema(ended)).toBe(true)
		ended.normal = { 0, 0, 3 }
		expect(Remotes.RushEnded.schema(ended)).toBe(false)
		ended.normal = { 0, 0, 1 }
		ended.contact = { 0 / 0, 0, 0 }
		expect(Remotes.RushEnded.schema(ended)).toBe(false)
	end)

	it("a rush's bend or sidestep is a reliable message with its whole path (D-206, D-207)", function()
		expect(Remotes.RushTurned.kind).toBe("Event")
		expect(Remotes.RushTurned.direction).toBe("ServerToClient")
		local leg = function(at: number, z: number): any
			return { at = at, from = { 0, 0, z }, heading = { 0, 0, -1 }, facing = { 0, 0, -1 } }
		end
		local turned: any = {
			entityId = 4,
			launchedAt = 120.5,
			serverTime = 120.6,
			kind = "Clip",
			at = 7.2,
			legs = { leg(0, 0), leg(3.4, -3.4), leg(6.5, -6.5) },
			contact = { 0.7, 2.3, -12 },
			normal = { 0, 0, 1 },
		}
		expect(Remotes.RushTurned.schema(turned)).toBe(true)
		turned.kind = "Glance"
		expect(Remotes.RushTurned.schema(turned)).toBe(true)
		turned.kind = "Slam" -- a slam is a RushEnded
		expect(Remotes.RushTurned.schema(turned)).toBe(false)
		turned.kind = "Clip"
		turned.legs[2].heading = { 0, 0, -2 }
		expect(Remotes.RushTurned.schema(turned)).toBe(false)
		turned.legs[2].heading = { 0, 0, -1 }
		-- No more legs than a rush may run.
		for index = #turned.legs + 1, AI.rushWorld.maxLegs + 1 do
			turned.legs[index] = leg(index, -index)
		end
		expect(Remotes.RushTurned.schema(turned)).toBe(false)
	end)

	it("animation starts and telegraphs are unreliable, hits are reliable", function()
		expect(Remotes.ActionStarted.kind).toBe("Unreliable")
		expect(Remotes.Telegraph.kind).toBe("Unreliable")
		expect(Remotes.HitConfirmed.kind).toBe("Event")
		expect(Remotes.EntityDied.kind).toBe("Event")
	end)
end)

describe("a swing's sequence number (item 4)", function()
	local Combat = Harness.load("src/shared/data/combat")
	local MAX = Combat.contact.swingSequenceMax

	it("ArtRequest and BasicAttackRequest may carry a whole number from 1 to the wrap", function()
		local art = { artId = "OneHandedSword.SharpNail", facing = { 0, 0, -1 }, clientTime = 12.5 }
		local basic = { facing = { 0, 0, -1 }, clientTime = 12.5 }
		for _, payload in { art, basic } do
			local schema = if payload == art then Remotes.ArtRequest.schema else Remotes.BasicAttackRequest.schema
			expect(schema(payload)).toBe(true) -- an older client sends none
			for _, good in { 1, 2, MAX } do
				(payload :: any).swing = good
				expect(schema(payload)).toBe(true)
			end
			for _, bad in { 0, -1, 1.5, MAX + 1, "3", math.huge, 0 / 0 } do
				(payload :: any).swing = bad
				expect(schema(payload)).toBe(false)
			end
		end
	end)

	it("HitConfirmed may echo it", function()
		local payload: any = {
			attackerId = 1,
			targetId = 2,
			damage = 37,
			crit = false,
			gaugeDamage = 12,
			killed = false,
			broke = false,
			hitStop = "Normal",
			position = { 1, 2, 3 },
			parried = false,
			guarded = false,
			reflected = false,
			hitIndex = 1,
		}
		expect(Remotes.HitConfirmed.schema(payload)).toBe(true)
		payload.swing = 7
		expect(Remotes.HitConfirmed.schema(payload)).toBe(true)
		payload.swing = MAX + 1
		expect(Remotes.HitConfirmed.schema(payload)).toBe(false)
	end)
end)
