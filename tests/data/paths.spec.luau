--!strict
local Paths = Harness.load("src/shared/data/paths")

describe("paths data", function()
	it("holds the six section 7 Paths in order", function()
		expect(Paths.order).toEqual({ "Vanguard", "Striker", "Duelist", "Breaker", "Shade", "Herald" })
		for _, id in Paths.order do
			expect(Paths.get(id).id).toBe(id)
		end
	end)

	it("is chosen at level 10 with one respec per ten floors for 20% of Crowns", function()
		expect(Paths.chooseLevel).toBe(10)
		expect(Paths.trainerTown).toBe("Firstlight")
		expect(Paths.respec.perFloors).toBe(10)
		expect(Paths.respec.crownFraction).toBe(0.2)
		expect(Paths.respecCost(1000)).toBe(200)
		expect(Paths.respecCost(7)).toBe(1)
		expect(Paths.respecsEarned(9)).toBe(0)
		expect(Paths.respecsEarned(25)).toBe(2)
	end)

	it("carries the signature numbers", function()
		local vanguard = Paths.get("Vanguard").signature
		expect(vanguard.taunt).toEqual({ threatMultiplier = 3, duration = 8 })
		expect(vanguard.bulwarkStance.guardConeDegrees).toBe(360)
		expect(Paths.get("Striker").signature.momentum).toEqual({ startPoseCutPerStack = 0.5, maxStacks = 3 })
		expect(Paths.get("Duelist").signature.riposte.activationHold).toBe(0)
		expect(Paths.get("Breaker").signature.shatter.gaugeDamageBonus).toBe(0.6)
		expect(Paths.get("Shade").signature.firstStrike.fromBehindMultiplier).toBe(2.5)
		expect(Paths.get("Shade").signature.firstStrike.opensSwitch).toBe(true)
		local rally = Paths.get("Herald").signature.rally
		expect(rally).toEqual({ tempoCapBonus = 2, artSpeedBonus = 0.1, duration = 10 })
		expect(Paths.get("Herald").signature.extraShards).toBe(2)
	end)

	it("limits weapons per Path", function()
		expect(Paths.canWield("Vanguard", "Mace")).toBe(true)
		expect(Paths.canWield("Vanguard", "Dagger")).toBe(false)
		expect(Paths.canWield("Duelist", "Rapier")).toBe(true)
		expect(Paths.canWield("Breaker", "Spear")).toBe(true)
		expect(Paths.canWield("Shade", "Mace")).toBe(false)
		expect(Paths.get("Vanguard").offHand).toBe("Shield")
		expect(Paths.get("Herald").offHand).toBe("WarHorn")
	end)

	it("a Dual Wielder keeps Twin Fang under any Path", function()
		for _, id in Paths.order do
			expect(Paths.canWield(id, "TwinFang")).toBe(false)
			expect(Paths.canWield(id, "TwinFang", "DualWielder")).toBe(true)
		end
		expect(Paths.canWield("Shade", "TwinFang", "Ironhand")).toBe(false)
	end)

	it("errors on an unknown Path", function()
		expect(function()
			Paths.get("Paladin")
		end).toThrow("unknown Path")
	end)
end)
