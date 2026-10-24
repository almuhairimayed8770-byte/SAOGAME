--!strict
local Remotes = Harness.load("src/shared/net/Remotes")
local World = Harness.load("src/shared/data/world")

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

	it("a rush's launch and early end are unreliable messages with the server's line and clock (D-169)", function()
		expect(Remotes.RushStarted.kind).toBe("Unreliable")
		expect(Remotes.RushStarted.direction).toBe("ServerToClient")
		expect(Remotes.RushEnded.kind).toBe("Unreliable")
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
