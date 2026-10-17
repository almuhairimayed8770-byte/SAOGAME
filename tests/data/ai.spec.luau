--!strict
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Combat = Harness.load("src/shared/data/combat")

describe("ai data", function()
	it("re-exports the section 16 rates from enemies.rules so each number exists once", function()
		expect(AI.tickHz).toBe(Enemies.rules.aiTickHz)
		expect(AI.tickHz).toBe(20)
		expect(AI.bossTickHz).toBe(Enemies.rules.bossTickHz)
		expect(AI.bossTickHz).toBe(30)
		expect(AI.sleepRadius).toBe(Enemies.rules.simulateRadius)
		expect(AI.sleepRadius).toBe(300)
		expect(AI.pathfindPastStuds).toBe(Enemies.rules.pathfindBeyondStuds)
		expect(AI.pathfindPastStuds).toBe(60)
		expect(AI.tickSeconds()).toBeCloseTo(1 / 20, 1e-9)
	end)

	it("the Charger covers the telegraphed line by the time its hit resolves", function()
		local charger = AI.archetypes.Charger
		for _, def in Enemies.list() do
			if def.archetype == "Charger" then
				for _, attack in def.attacks do
					if attack.groundShape == "Line" then
						local speed = AI.rushSpeed(attack)
						expect(speed).toBeGreaterThanOrEqual(charger.chargeSpeed)
						expect(speed * attack.strike).toBeGreaterThanOrEqual(attack.reach - 1e-9)
					end
				end
			end
		end
		-- The Frenzy Boar's own line is covered by the base speed; a field boss's longer line raises it.
		local boar = Enemies.byId("FrenzyBoar").attacks[1]
		expect(AI.rushSpeed(boar)).toBe(charger.chargeSpeed)
		expect(AI.rushSpeed({ reach = 18, strike = 0.5 })).toBeCloseTo(36, 1e-9)
		expect(AI.rushSpeed({ reach = 18, strike = 0 })).toBe(charger.chargeSpeed)
	end)

	it("the Charger's charge band sits inside its aggro range and its overshoot is a real pass", function()
		local charger = AI.archetypes.Charger
		local boar = Enemies.byId("FrenzyBoar")
		expect(charger.minChargeDistance).toBeLessThan(charger.circleDistance)
		expect(charger.circleDistance).toBeLessThan(charger.maxChargeDistance)
		expect(charger.maxChargeDistance).toBeLessThan(boar.aggroRange)
		expect(charger.overshoot).toBeGreaterThan(0)
		expect(charger.chargeSpeed).toBeGreaterThan(boar.moveSpeed)
		expect(charger.lineUpToleranceDegrees).toBeLessThan(charger.lineUpLooseToleranceDegrees)
		expect(charger.wheelSpeedMultiplier).toBeGreaterThan(0)
		expect(charger.wheelSpeedMultiplier).toBeLessThanOrEqual(1)
		expect(charger.wheelAngle).toBeGreaterThan(charger.lineUpLooseToleranceDegrees)
	end)

	it("every Charger can find a line from circleDistance that starts inside the charge band", function()
		local charger = AI.archetypes.Charger
		for _, def in Enemies.list() do
			if def.archetype == "Charger" then
				local lineUp = AI.chargerLineUpDistance(def.moveSpeed)
				expect(lineUp).toBeGreaterThanOrEqual(charger.minChargeDistance)
				expect(lineUp).toBeLessThanOrEqual(charger.maxChargeDistance)
			end
		end
		expect(AI.chargerLineUpDistance(1e6)).toBe(0)
	end)

	it("the Charger holds its line through the crouch and the rush; the Brute tracks slowly while it holds", function()
		expect(AI.archetypes.Charger.windUpTurnRate).toBe(0)
		expect(AI.archetypes.Charger.strikeTurnRate).toBe(0)
		expect(AI.archetypes.Charger.turnRate).toBeLessThan(AI.archetypes.Brute.turnRate)
		local brute = AI.archetypes.Brute
		expect(brute.windUpTurnRate).toBeGreaterThan(0)
		expect(brute.windUpTurnRate).toBeLessThan(brute.turnRate)
		expect(brute.strikeTurnRate).toBe(0)
		-- A dodge (section 6) from the Brute's engage distance leaves the Overhead cone even when the
		-- Brute tracks for the whole wind-up.
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		local engage = overhead.reach * brute.engageFraction
		local dodgeAngle = math.deg(math.atan(Combat.dodgeDistance / engage))
		expect(dodgeAngle - brute.windUpTurnRate * overhead.windUp).toBeGreaterThan(overhead.arc / 2)
	end)

	it("tuningFor falls back to Default for archetypes without a brain", function()
		expect(AI.tuningFor("Charger")).toBe(AI.archetypes.Charger)
		expect(AI.tuningFor("Brute")).toBe(AI.archetypes.Brute)
		expect(AI.tuningFor("Skirmisher")).toBe(AI.archetypes.Default)
		expect(AI.tuningFor("Nothing")).toBe(AI.archetypes.Default)
	end)

	it("attack weights favor the signature attack and default to 1", function()
		expect(AI.attackWeight("Charge")).toBeGreaterThan(AI.attackWeight("Trample"))
		expect(AI.attackWeight("Overhead")).toBeGreaterThan(AI.attackWeight("Sweep"))
		expect(AI.attackWeight("Unknown")).toBe(AI.attack.defaultWeight)
		for _, weight in AI.attack.weights do
			expect(weight).toBeGreaterThan(0)
		end
	end)

	it("every archetype tuning has positive rates and a sane engage rule", function()
		for name, tuning in AI.archetypes do
			expect(tuning.turnRate).toBeGreaterThan(0)
			expect(tuning.windUpTurnRate).toBeGreaterThanOrEqual(0)
			expect(tuning.strikeTurnRate).toBeGreaterThanOrEqual(0)
			expect(tuning.recoverTurnRate).toBeGreaterThan(0)
			expect(tuning.attackCooldown).toBeGreaterThanOrEqual(0)
			expect(tuning.chaseSpeedMultiplier).toBeGreaterThan(0)
			expect(tuning.engageFraction).toBeGreaterThan(0)
			expect(tuning.engageFraction).toBeLessThanOrEqual(1)
			expect(tuning.engageAngle).toBeGreaterThan(0)
			expect(tuning.engageAngle).toBeLessThanOrEqual(180)
			expect(typeof(name)).toBe("string")
		end
	end)

	it("interrupt fallbacks are the section 6 durations", function()
		expect(AI.interrupt.durations.Stagger).toBe(Combat.staggerDuration)
		expect(AI.interrupt.durations.Break).toBe(Combat.breakDuration)
		expect(AI.interrupt.durations.GuardBroken).toBe(Combat.guardBreakStagger)
		expect(AI.interrupt.resumeDelay).toBeGreaterThan(0)
	end)

	it("perception, leash and movement numbers are consistent", function()
		expect(AI.perception.loseRangeMultiplier).toBeGreaterThan(1)
		expect(AI.perception.threatRangeMultiplier).toBeGreaterThanOrEqual(AI.perception.loseRangeMultiplier)
		expect(AI.perception.threatSwitchMargin).toBeGreaterThan(1)
		expect(AI.leash.homeRadius).toBeGreaterThan(AI.movement.arriveRadius * 0)
		expect(AI.leash.returnSpeedMultiplier).toBeGreaterThanOrEqual(1)
		expect(AI.movement.moveAheadStuds).toBeGreaterThan(AI.movement.arriveRadius)
		expect(AI.movement.stuckProgressStuds).toBeLessThan(AI.movement.arriveRadius)
		expect(AI.movement.waypointReach).toBeGreaterThanOrEqual(AI.movement.arriveRadius)
		for _, cost in AI.movement.materialCosts do
			expect(cost).toBeGreaterThan(0)
		end
		expect(AI.maxTicksPerFrame).toBeGreaterThanOrEqual(1)
		expect(AI.sleepCheckInterval).toBeGreaterThan(AI.tickSeconds())
	end)
end)
