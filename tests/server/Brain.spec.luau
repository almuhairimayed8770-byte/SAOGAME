--!strict
--[[
	Brain: the archetype base driven with a fake clock and a fake context. Perception, threat,
	leash, the attack timeline, cooldowns, interrupts, death and sleep; the archetype hooks are
	the real Charger / Brute or a tiny test archetype where the base's own rules are the point.
]]

local Brain = Harness.load("src/server/ai/Brain")
local Charger = Harness.load("src/server/ai/Charger")
local Brute = Harness.load("src/server/ai/Brute")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Combat = Harness.load("src/shared/data/combat")

local TICK = AI.tickSeconds()
local FORWARD = Vector3.new(0, 0, -1)

type Options = { position: Vector3?, facing: Vector3?, def: any?, archetype: any?, seed: number? }

-- A fake world: a clock, a body the context moves, players, the record EntityService would hold,
-- and a log of every hook the brain fires. `step(n)` ticks the brain n times and moves the body
-- toward its MoveTo goal at the requested speed (a one-line physics stand-in).
local function world(defId: string, options: Options?)
	local opts: Options = options or {}
	local def = opts.def or Enemies.scaled(Enemies.byId(defId))
	local archetype = opts.archetype or (if def.archetype == "Brute" then Brute else Charger)
	local w: any = {
		time = 0,
		position = opts.position or Vector3.zero,
		facing = opts.facing or FORWARD,
		record = { state = "Idle", threat = {} },
		players = {},
		goal = nil,
		speed = nil,
		moving = false,
		telegraphs = {},
		strikes = {},
		states = {},
		actions = {},
		stops = 0,
		threatCleared = 0,
	}
	w.home = w.position
	w.context = {
		entityId = 7,
		def = def,
		home = w.home,
		now = function()
			return w.time
		end,
		getRecord = function()
			return w.record
		end,
		players = function()
			return w.players
		end,
		position = function()
			return w.position
		end,
		facing = function()
			return w.facing
		end,
		moveTo = function(position, speed)
			w.goal = position
			w.speed = speed
			w.moving = true
		end,
		stop = function()
			w.moving = false
			w.goal = nil
			w.stops += 1
		end,
		face = function(direction)
			w.facing = direction
		end,
		telegraph = function(attack, origin, facing, shape)
			table.insert(
				w.telegraphs,
				{ time = w.time, attack = attack, origin = origin, facing = facing, shape = shape }
			)
		end,
		strike = function(attack, origin, facing)
			table.insert(w.strikes, { time = w.time, attack = attack, origin = origin, facing = facing })
		end,
		setState = function(state, duration)
			w.record.state = state
			table.insert(w.states, { time = w.time, state = state, duration = duration })
		end,
		actionStarted = function(clipId, facing)
			table.insert(w.actions, { time = w.time, clipId = clipId, facing = facing })
		end,
		random = Random.new(opts.seed or 1),
		clearThreat = function()
			w.threatCleared += 1
		end,
	}
	w.brain = Brain.new(w.context, archetype)
	function w.step(count: number?)
		for _ = 1, count or 1 do
			w.brain:tick(TICK)
			if w.moving and w.goal ~= nil then
				local delta = w.goal - w.position
				local distance = delta.Magnitude
				local reach = (w.speed or def.moveSpeed) * TICK
				if distance <= reach then
					w.position = w.goal
				elseif distance > 0 then
					w.position = w.position + delta.Unit * reach
				end
			end
			w.time += TICK
		end
	end
	function w.stepSeconds(seconds: number)
		w.step(math.ceil(seconds / TICK))
	end
	function w.stepUntil(predicate: () -> boolean, maxSeconds: number): boolean
		local ticks = math.ceil(maxSeconds / TICK)
		for _ = 1, ticks do
			if predicate() then
				return true
			end
			w.step(1)
		end
		return predicate()
	end
	return w
end

local function player(id: number, x: number, z: number)
	return { id = id, position = Vector3.new(x, 0, z) }
end

describe("Brain helpers", function()
	it("rotateY turns -Z toward -X for a positive angle and signedAngle inverts it", function()
		local turned = Brain.rotateY(FORWARD, 90)
		expect(turned.X).toBeCloseTo(-1, 1e-6)
		expect(turned.Z).toBeCloseTo(0, 1e-6)
		expect(Brain.signedAngle(FORWARD, turned)).toBeCloseTo(90, 1e-6)
		expect(Brain.signedAngle(FORWARD, Vector3.new(1, 0, 0))).toBeCloseTo(-90, 1e-6)
		local back = Brain.rotateY(FORWARD, Brain.signedAngle(FORWARD, Vector3.new(1, 0, 0)))
		expect(back.X).toBeCloseTo(1, 1e-6)
	end)

	it("horizontal drops the vertical part and reports no direction for a vertical vector", function()
		local flat = Brain.horizontal(Vector3.new(3, 9, -4))
		expect(flat.Y).toBe(0)
		expect(flat.Magnitude).toBeCloseTo(1, 1e-6)
		expect(Brain.horizontal(Vector3.new(0, 5, 0))).toBeNil()
	end)

	it("shapeFor draws the attack's ground shape with the right width", function()
		local charge = Enemies.byId("FrenzyBoar").attacks[1]
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		local line = Brain.shapeFor(charge)
		expect(line.kind).toBe("Line")
		expect(line.length).toBe(charge.reach)
		expect(line.width).toBe(AI.telegraph.lineWidth)
		local cone = Brain.shapeFor(overhead)
		expect(cone.kind).toBe("Cone")
		expect(cone.length).toBe(overhead.reach)
		expect(cone.width).toBe(overhead.arc)
		local trample = Enemies.eliteAttacks.Charger
		local circle = Brain.shapeFor(trample)
		expect(circle.kind).toBe("Circle")
		expect(circle.width).toBe(trample.reach)
		expect(Brain.shapeFor({ reach = 4, arc = 60, groundShape = nil })).toBeNil()
	end)

	it("clipIdFor names enemy/<Rig>/<clip>", function()
		local boar = Enemies.byId("FrenzyBoar")
		expect(Brain.clipIdFor(boar, boar.attacks[1])).toBe("enemy/Boar/Charge")
		local kobold = Enemies.byId("KoboldAxeman")
		expect(Brain.clipIdFor(kobold, kobold.attacks[1])).toBe("enemy/Kobold/Overhead")
	end)
end)

describe("Brain perception", function()
	it("a boar at 32 studs alerts after one tick and chases after the alert delay", function()
		local w = world("FrenzyBoar")
		w.players = { player(1, 0, -32) }
		expect(w.brain:getPhase()).toBe("Idle")
		w.step(1)
		expect(w.brain:getPhase()).toBe("Alert")
		w.stepSeconds(AI.perception.alertDelay)
		w.step(1)
		expect(w.brain:getPhase()).toBe("Chase")
		expect(w.brain:getTarget().id).toBe(1)
	end)

	it("nobody inside aggroRange keeps it Idle", function()
		local w = world("FrenzyBoar")
		w.players = { player(1, 0, -(Enemies.byId("FrenzyBoar").aggroRange + 5)) }
		w.stepSeconds(2)
		expect(w.brain:getPhase()).toBe("Idle")
		expect(w.moving).toBe(false)
	end)

	it("picks the taunter over the nearest player from the record's threat table", function()
		local w = world("FrenzyBoar")
		w.players = { player(1, 0, -10), player(2, 0, -35) }
		w.record.threat = { [2] = 30 }
		w.step(1)
		expect(w.brain:getTarget().id).toBe(2)
	end)

	it("switches targets only when the new threat beats the current one by the margin", function()
		local w = world("FrenzyBoar")
		w.players = { player(1, 0, -20), player(2, 5, -20) }
		w.record.threat = { [1] = 10 }
		w.step(1)
		expect(w.brain:getTarget().id).toBe(1)
		w.record.threat = { [1] = 10, [2] = 10 * AI.perception.threatSwitchMargin - 1 }
		w.stepSeconds(AI.perception.retargetInterval + TICK)
		expect(w.brain:getTarget().id).toBe(1)
		w.record.threat = { [1] = 10, [2] = 10 * AI.perception.threatSwitchMargin + 1 }
		w.stepSeconds(AI.perception.retargetInterval + TICK)
		expect(w.brain:getTarget().id).toBe(2)
	end)

	it("keeps the nearest target rather than flipping to whoever is closest each interval", function()
		local w = world("FrenzyBoar")
		w.players = { player(1, 0, -20), player(2, 0, -30) }
		w.step(1)
		expect(w.brain:getTarget().id).toBe(1)
		w.players = { player(1, 0, -25), player(2, 0, -12) }
		w.stepSeconds(AI.perception.retargetInterval * 2)
		expect(w.brain:getTarget().id).toBe(1)
	end)

	it("drops a target that stays beyond the lose range for the grace period", function()
		local w = world("FrenzyBoar")
		local aggro = Enemies.byId("FrenzyBoar").aggroRange
		w.players = { player(1, 0, -20) }
		w.step(1)
		expect(w.brain:getTarget().id).toBe(1)
		-- Far enough that the chase cannot close the gap inside the grace period.
		w.players = { player(1, 0, -(aggro * AI.perception.loseRangeMultiplier + 140)) }
		w.stepSeconds(AI.perception.loseTargetGrace / 2)
		expect(w.brain:getTarget()).toBeTruthy()
		w.stepSeconds(AI.perception.loseTargetGrace)
		expect(w.brain:getTarget()).toBeNil()
		expect(w.brain:getPhase()).toBe("Idle")
	end)

	it("a player who leaves the server is forgotten at once", function()
		local w = world("FrenzyBoar")
		w.players = { player(1, 0, -20) }
		w.step(1)
		w.players = {}
		w.step(2)
		expect(w.brain:getTarget()).toBeNil()
		expect(w.brain:getPhase()).toBe("Idle")
	end)
end)

describe("Brain leash", function()
	it("returns home past the leash range, clears threat, ignores players and idles at home", function()
		local w = world("FrenzyBoar")
		local def = Enemies.byId("FrenzyBoar")
		w.players = { player(1, 0, -35) }
		w.stepSeconds(AI.perception.alertDelay + TICK * 2)
		expect(w.brain:getPhase()).toBe("Chase")
		-- The chase dragged the body past the leash (teleport the stand-in body there).
		w.position = Vector3.new(0, 0, -(def.leashRange + 5))
		w.players = { player(1, 0, -(def.leashRange + 15)) }
		w.step(1)
		expect(w.brain:getPhase()).toBe("Return")
		expect(w.threatCleared).toBe(1)
		expect(w.brain:getTarget()).toBeNil()
		w.step(1)
		expect(w.goal).toEqual(w.home)
		expect(w.speed).toBeCloseTo(def.moveSpeed * AI.leash.returnSpeedMultiplier, 1e-6)
		-- A player standing on the way home does not re-aggro it while it returns.
		w.players = { player(1, 0, -(def.leashRange / 2)) }
		local arrived = w.stepUntil(function()
			return w.brain:getPhase() ~= "Return"
		end, (def.leashRange + 5) / def.moveSpeed + 2)
		expect(arrived).toBe(true)
		expect(w.brain:getPhase()).toBe("Idle")
		expect(Brain.horizontalDistance(w.position, w.home)).toBeLessThanOrEqual(AI.leash.homeRadius)
		expect(w.telegraphs).toHaveLength(0)
	end)

	it("an idle brain that finds itself beyond the leash walks home before it looks for players", function()
		local w = world("FrenzyBoar")
		local def = Enemies.byId("FrenzyBoar")
		w.position = Vector3.new(0, 0, -(def.leashRange + 5))
		w.players = { player(1, 0, -(def.leashRange + 15)) } -- a player right next to it
		w.step(1)
		expect(w.brain:getPhase()).toBe("Return")
		expect(w.stepUntil(function()
			return w.brain:getPhase() ~= "Return"
		end, (def.leashRange + 5) / def.moveSpeed + 2)).toBe(true)
		expect(w.brain:getPhase()).toBe("Idle")
		expect(Brain.horizontalDistance(w.position, w.home)).toBeLessThanOrEqual(AI.leash.homeRadius)
		expect(w.telegraphs).toHaveLength(0)
	end)
end)

describe("Brain attack timeline", function()
	it("WindUp fires the telegraph, the clip and the Art state; Strike resolves after attack.strike", function()
		local w = world("FrenzyBoar")
		local charge = Enemies.byId("FrenzyBoar").attacks[1]
		w.players = { player(1, 0, -20) }
		local windUp = w.stepUntil(function()
			return w.brain:getPhase() == "WindUp"
		end, 3)
		expect(windUp).toBe(true)
		expect(w.telegraphs).toHaveLength(1)
		expect(w.actions).toHaveLength(1)
		expect(w.actions[1].clipId).toBe("enemy/Boar/Charge")
		expect(w.states[1].state).toBe("Art")
		expect(w.states[1].duration).toBeCloseTo(charge.windUp + charge.strike, 1e-9)
		local telegraphAt = w.telegraphs[1].time
		local struck = w.stepUntil(function()
			return #w.strikes == 1
		end, 3)
		expect(struck).toBe(true)
		local strikeAt = w.strikes[1].time
		expect(strikeAt - telegraphAt).toBeGreaterThanOrEqual(charge.windUp + charge.strike - 1e-9)
		expect(strikeAt - telegraphAt).toBeLessThan(charge.windUp + charge.strike + TICK * 2)
		local recovered = w.stepUntil(function()
			return w.brain:getPhase() == "Recover"
		end, 3)
		expect(recovered).toBe(true)
		expect(w.states[#w.states].state).toBe("PostMotion")
		expect(w.states[#w.states].duration).toBe(charge.recovery)
		local recoverAt = w.time
		local back = w.stepUntil(function()
			return w.brain:getPhase() ~= "Recover"
		end, 3)
		expect(back).toBe(true)
		expect(w.time - recoverAt).toBeGreaterThanOrEqual(charge.recovery - TICK)
		expect(w.states[#w.states].state).toBe("Idle")
		expect(w.brain:currentAttack()).toBeNil()
	end)

	it("an attack goes on cooldown for its whole timeline plus the archetype cooldown", function()
		local w = world("FrenzyBoar")
		local charge = Enemies.byId("FrenzyBoar").attacks[1]
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.brain:getPhase() == "WindUp"
		end, 3)
		local startedAt = w.telegraphs[1].time
		local target = { id = 1, position = Vector3.new(0, 0, -20), distance = 20, direction = FORWARD }
		expect(w.brain:readyAttacks(target)).toHaveLength(0)
		local readyAt = startedAt
			+ charge.windUp
			+ charge.strike
			+ charge.recovery
			+ AI.archetypes.Charger.attackCooldown
		w.time = readyAt - TICK
		expect(w.brain:readyAttacks(target)).toHaveLength(0)
		w.time = readyAt
		expect(w.brain:readyAttacks(target)).toHaveLength(1)
	end)

	it("picks among ready attacks by the ai.luau weights", function()
		local base = Enemies.scaled(Enemies.byId("FrenzyBoar"))
		local def = Enemies.variant(base, "Elite") -- Charge (weight 3) and Trample (weight 1)
		local always = {
			name = "Test",
			chase = function(brain, _dt, target)
				return brain:pickAttack(target)
			end,
			canUse = function()
				return true
			end,
			onWindUp = function() end,
			onStrikeStart = function() end,
			strikeFrame = function(brain)
				return brain:position(), brain:getFacing()
			end,
			onStrike = function()
				return true
			end,
			onRecover = function() end,
		}
		local w = world("FrenzyBoar", { def = def, archetype = always, seed = 11 })
		local target = { id = 1, position = Vector3.new(0, 0, -5), distance = 5, direction = FORWARD }
		local counts = { Charge = 0, Trample = 0 }
		for _ = 1, 400 do
			local attack = w.brain:pickAttack(target)
			counts[attack.id] += 1
		end
		expect(counts.Charge + counts.Trample).toBe(400)
		expect(counts.Trample).toBeGreaterThan(40)
		expect(counts.Charge).toBeGreaterThan(counts.Trample * 2)
	end)
end)

describe("Brain interrupts, death and sleep", function()
	it("a Stagger during the wind-up cancels the strike and resumes the chase afterwards", function()
		local w = world("KoboldAxeman")
		w.players = { player(1, 0, -4) }
		local windUp = w.stepUntil(function()
			return w.brain:getPhase() == "WindUp"
		end, 3)
		expect(windUp).toBe(true)
		local stopsBefore = w.stops
		w.record.state = "Stagger"
		w.brain:interrupt("Stagger", 1.0)
		expect(w.brain:getPhase()).toBe("Interrupted")
		expect(w.brain:currentAttack()).toBeNil()
		expect(w.stops).toBe(stopsBefore + 1)
		w.stepSeconds(1.0)
		expect(w.strikes).toHaveLength(0)
		expect(w.brain:getPhase()).toBe("Interrupted")
		w.record.state = "Idle"
		w.stepSeconds(AI.interrupt.resumeDelay + TICK)
		expect(w.strikes).toHaveLength(0)
		expect(w.brain:getPhase()).toBe("Chase")
	end)

	it("a strike that is parried (the record staggers inside the strike hook) leaves the brain stopped", function()
		local w = world("FrenzyBoar")
		w.players = { player(1, 0, -20) }
		-- CombatService.enemyStrike resolves the parry synchronously: EntityService sets Stagger and
		-- EnemyService's StateChanged handler calls interrupt() before the strike hook returns.
		w.context.strike = function(attack, origin, facing)
			table.insert(w.strikes, { time = w.time, attack = attack, origin = origin, facing = facing })
			w.record.state = "Stagger"
			w.brain:interrupt("Stagger", Combat.parryStagger)
		end
		expect(w.stepUntil(function()
			return #w.strikes == 1
		end, 3)).toBe(true)
		expect(w.brain:getPhase()).toBe("Interrupted")
		expect(w.brain:currentAttack()).toBeNil()
		expect(w.moving).toBe(false) -- the rush does not carry on through the stagger
		expect(w.goal).toBeNil()
		local positionAtStrike = w.position
		w.stepSeconds(Combat.parryStagger / 2)
		expect(w.brain:getPhase()).toBe("Interrupted")
		expect(w.states[#w.states].state).never.toBe("PostMotion")
		expect(Brain.horizontalDistance(w.position, positionAtStrike)).toBeLessThan(1e-6)
		w.record.state = "Idle"
		w.stepSeconds(Combat.parryStagger / 2 + AI.interrupt.resumeDelay + TICK)
		expect(w.brain:getPhase()).toBe("Chase")
	end)

	it("a record that reports Stagger on its own interrupts the brain until the state clears", function()
		local w = world("KoboldAxeman")
		w.players = { player(1, 0, -4) }
		w.stepUntil(function()
			return w.brain:getPhase() == "WindUp"
		end, 3)
		w.record.state = "Break"
		w.step(1)
		expect(w.brain:getPhase()).toBe("Interrupted")
		w.stepSeconds(2)
		expect(w.brain:getPhase()).toBe("Interrupted")
		expect(w.strikes).toHaveLength(0)
		w.record.state = "Idle"
		w.step(1)
		expect(w.brain:getPhase()).toBe("Chase")
	end)

	it("a stagger that the record extends (a chained Break) keeps the brain held until stateUntil", function()
		local w = world("KoboldAxeman")
		w.players = { player(1, 0, -4) }
		w.stepUntil(function()
			return w.brain:getPhase() == "WindUp"
		end, 3)
		w.record.state = "Stagger"
		w.brain:interrupt("Stagger", 0.5)
		w.stepSeconds(0.5 + AI.interrupt.resumeDelay)
		w.record.state = "Break"
		w.record.stateUntil = w.time + 1.0
		w.step(1)
		expect(w.brain:getPhase()).toBe("Interrupted")
		w.stepSeconds(0.5)
		expect(w.brain:getPhase()).toBe("Interrupted")
		w.record.state = "Idle"
		w.stepSeconds(0.5 + AI.interrupt.resumeDelay + TICK)
		expect(w.brain:getPhase()).toBe("Chase")
	end)

	it("a dead record stops the brain for good", function()
		local w = world("FrenzyBoar")
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.brain:getPhase() == "WindUp"
		end, 3)
		w.record.state = "Dead"
		w.step(1)
		expect(w.brain:getPhase()).toBe("Dead")
		local calls = #w.telegraphs + #w.strikes + #w.states + #w.actions
		w.record.state = "Idle"
		w.stepSeconds(3)
		expect(w.brain:getPhase()).toBe("Dead")
		expect(#w.telegraphs + #w.strikes + #w.states + #w.actions).toBe(calls)
		w.brain:interrupt("Stagger", 1)
		expect(w.brain:getPhase()).toBe("Dead")
	end)

	it("sleep stops the body and forgets the target; wake resumes perception", function()
		local w = world("FrenzyBoar")
		w.players = { player(1, 0, -35) }
		w.stepSeconds(AI.perception.alertDelay + TICK * 2)
		expect(w.brain:getPhase()).toBe("Chase")
		expect(w.moving).toBe(true)
		w.brain:sleep()
		expect(w.brain:isAwake()).toBe(false)
		expect(w.brain:getPhase()).toBe("Idle")
		expect(w.moving).toBe(false)
		w.stepSeconds(2)
		expect(w.brain:getPhase()).toBe("Idle")
		expect(w.telegraphs).toHaveLength(0)
		w.brain:wake()
		expect(w.brain:isAwake()).toBe(true)
		w.step(1)
		expect(w.brain:getPhase()).toBe("Alert")
	end)

	it("turnToward is rate limited and publishes the facing", function()
		local w = world("FrenzyBoar")
		local remaining = w.brain:turnToward(Vector3.new(1, 0, 0), 100, 0.1)
		expect(remaining).toBeCloseTo(80, 1e-6)
		expect(w.brain:angleTo(Vector3.new(1, 0, 0))).toBeCloseTo(80, 1e-6)
		expect(w.facing.Magnitude).toBeCloseTo(1, 1e-6)
		expect(Brain.signedAngle(FORWARD, w.facing)).toBeCloseTo(-10, 1e-6)
		w.brain:turnToward(Vector3.new(1, 0, 0), 1000, 1)
		expect(w.brain:angleTo(Vector3.new(1, 0, 0))).toBeCloseTo(0, 1e-6)
	end)
end)
