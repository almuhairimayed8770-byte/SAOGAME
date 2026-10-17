local Remotes = Harness.load("src/shared/net/Remotes")

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

	it("animation starts and telegraphs are unreliable, hits are reliable", function()
		expect(Remotes.ActionStarted.kind).toBe("Unreliable")
		expect(Remotes.Telegraph.kind).toBe("Unreliable")
		expect(Remotes.HitConfirmed.kind).toBe("Event")
		expect(Remotes.EntityDied.kind).toBe("Event")
	end)
end)
