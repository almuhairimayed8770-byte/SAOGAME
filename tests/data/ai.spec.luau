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

	it(
		"a walk's change of pace eases over frames, and a Charger comes out of its wheel within a re-issue (D-574)",
		function()
			local rate = AI.movement.paceChangeRate
			local charger = AI.archetypes.Charger
			expect(rate).toBeGreaterThan(0)
			-- The slide a frame's change gives a gait a frame behind its root stays inside the contact band.
			local contact = Harness.load("src/shared/data/choreo").locomotion.stride.contact
			expect(rate / 60 / 60).toBeLessThanOrEqual(contact)
			for _, def in Enemies.list() do
				if def.archetype == "Charger" then
					local change = def.moveSpeed * charger.chaseSpeedMultiplier * (1 - charger.wheelSpeedMultiplier)
					local seconds = change / rate
					expect(seconds).toBeGreaterThan(1 / 60)
					expect(seconds).toBeLessThanOrEqual(AI.movement.reissueInterval)
				end
			end
			-- The Frenzy Boar: 7 to 14 studs/s over 0.23 s.
			expect(7 / rate).toBeCloseTo(0.2333, 1e-3)
		end
	)

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

	it("every enemy body keeps out of the engine's falls: FallingDown and Ragdoll (D-494)", function()
		-- Section 10: "Death is a 0.5 s freeze in the last pose (no ragdoll)"; the brain owns the body.
		expect(table.find(AI.upright.offStates, "FallingDown")).toBeTruthy()
		expect(table.find(AI.upright.offStates, "Ragdoll")).toBeTruthy()
		for _, name in AI.upright.offStates do
			expect(name ~= "Running" and name ~= "GettingUp" and name ~= "Freefall" and name ~= "Dead").toBe(true)
		end
	end)

	it("a client's copy stands up to the state the server holds it in (D-523)", function()
		-- The PC's server log: Running on every held row; the client copy stands up to the same.
		expect(AI.upright.client.standUpState).toBe("Running")
		expect(table.find(AI.upright.offStates, AI.upright.client.standUpState)).toBeNil()
		-- Retries span seconds of PreSimulation steps, so a Humanoid replicated late is still met.
		expect(AI.upright.client.maxTries / 60).toBeGreaterThan(1)
	end)

	it(
		"a client's copy is caught as its Humanoid arrives and a fallen one stands up with its state machine off (D-543, D-544)",
		function()
			local client = AI.upright.client
			-- P1 L2 on 4e60f11: the four states off inside the arrival handler, Running on every row
			expect(client.catchOnArrival).toBe(true)
			for _, name in { "FallingDown", "Ragdoll", "Physics", "PlatformStanding" } do
				expect(table.find(client.offStates, name)).toBeTruthy()
			end
			for _, name in AI.upright.offStates do
				expect(table.find(client.offStates, name)).toBeTruthy()
			end
			expect(table.find(client.offStates, client.standUpState)).toBeNil()
			-- P1 L3: EvaluateStateMachine false, then ChangeState: the only stand-up that took while held
			expect(client.rescue).toBe(client.rescues.stateMachine)
		end
	)

	it("a rescued copy gets its state machine back at its release and is read back for a second (D-559)", function()
		local client = AI.upright.client
		-- 474(e) on 209875b: with it off, FloorMaterial Air on 536 of 536 rows held and walking
		expect(client.resumeOnRelease).toBe(true)
		-- P1: every copy let go with it on read Running over the 60 rows logged after its release
		expect(client.resumeChecks).toBeGreaterThanOrEqual(60)
		expect(client.resumeChecks % 1).toBe(0)
	end)

	it("a turned-on copy's own fall is waited out for a few steps before the read-back judges it (D-589)", function()
		local client = AI.upright.client
		-- 495(d) and (i) on 82b82d4: one FallingDown row on each of 3 turn-ons, then the server's
		-- Running once let go; a 60 Hz server on a 240 Hz client is 4 frames a packet, 12 at 20 Hz
		expect(client.resumeSettleSteps % 1).toBe(0)
		expect(client.resumeSettleSteps).toBeGreaterThanOrEqual(4)
		-- still well inside the read-back, so a copy that stays down is kept off within it
		expect(client.resumeSettleSteps).toBeLessThan(client.resumeChecks)
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

	-- The rush's ground probe (choreo/RushWorld, D-582): a small box, so it neither falls through a
	-- seam between parts nor finds a step's top from the spot it reads in front of the step's face;
	-- the riser rail starts there and looks past the face for anything over riserStuds.
	it("the rush's ground probe is a small box that reads the ground in front of a face, not on it", function()
		local world = AI.rushWorld
		expect(world.probeBoxStuds).toBeGreaterThan(0)
		expect(world.probeBoxStuds / 2).toBeLessThan(world.riserBeforeStuds)
		expect(world.riserPastStuds).toBeGreaterThan(0)
	end)

	it("a rush's landing rests within the 0.05 of AI 423(c) and is over before its recovery (D-525)", function()
		local movement = AI.movement
		expect(movement.landFrames).toBeGreaterThanOrEqual(1)
		-- A frame up to twice the last one never carries a landing past its stop (Studio's server
		-- frames jitter; the PC's slam ran a whole frame past).
		expect(movement.landFrames).toBeGreaterThanOrEqual(2)
		expect(movement.landSlackStuds).toBeGreaterThan(0)
		expect(movement.landSlackStuds).toBeLessThan(0.05)
		expect(movement.landMaxSeconds).toBeGreaterThan(movement.haltLeadSeconds)
		for _, def in Enemies.list() do
			if def.archetype == "Charger" then
				for _, attack in def.attacks do
					if attack.groundShape == "Line" then
						expect(movement.landMaxSeconds).toBeLessThan(attack.recovery)
					end
				end
			end
		end
	end)

	it("a rush's landing aims past the stop by more than Studio's MoveTo tolerance (AI 440, 441, D-548)", function()
		local movement = AI.movement
		-- The PC's P2 probe: a goal within 0.933 never starts a standing Humanoid; walks stop 0.933 to
		-- 1.4 short of their goal.
		expect(movement.moveToToleranceStuds).toBeGreaterThanOrEqual(1.4)
		-- Past that and the most a landing begins short of its stop (the rush speed times
		-- haltLeadSeconds), and no farther than the PC walked a goal past a mark at full pace (5).
		local fastest = 0
		for _, def in Enemies.list() do
			if def.archetype == "Charger" then
				for _, attack in def.attacks do
					if attack.arc == 0 or attack.groundShape == "Line" then
						fastest = math.max(fastest, AI.rushSpeed(attack))
					end
				end
			end
		end
		expect(movement.landAimStuds).toBeGreaterThan(
			movement.moveToToleranceStuds + fastest * movement.haltLeadSeconds
		)
		expect(movement.landAimStuds).toBeLessThanOrEqual(5)
	end)
end)
