--!strict
--[[
	Charger: the Frenzy Boar driven with a fake clock and context. Lines up, crouches for the
	0.6 s telegraph with the line on the ground, holds the line through the crouch, rushes at the
	rush speed, strikes 0.5 s in from the crouch point along the line, overshoots past the target,
	recovers for 1.2 s and turns slowly throughout.
]]

local Brain = Harness.load("src/server/ai/Brain")
local Charger = Harness.load("src/server/ai/Charger")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Combat = Harness.load("src/shared/data/combat")

local TICK = AI.tickSeconds()
local FORWARD = Vector3.new(0, 0, -1)
local tuning = AI.archetypes.Charger
local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]

local function world(options: { position: Vector3?, facing: Vector3?, seed: number? }?)
	local opts = options or {}
	local def = Enemies.scaled(BOAR)
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
		facings = {}, -- every facing the brain published, in order
		goals = {}, -- every MoveTo goal with its speed
	}
	w.home = w.position
	w.context = {
		entityId = 3,
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
			table.insert(w.goals, { time = w.time, goal = position, speed = speed })
		end,
		stop = function()
			w.moving = false
			w.goal = nil
		end,
		face = function(direction)
			w.facing = direction
			table.insert(w.facings, { time = w.time, facing = direction })
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
		random = Random.new(opts.seed or 3),
	}
	w.brain = Brain.new(w.context, Charger)
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
	function w.stepUntil(predicate: () -> boolean, maxSeconds: number): boolean
		for _ = 1, math.ceil(maxSeconds / TICK) do
			if predicate() then
				return true
			end
			w.step(1)
		end
		return predicate()
	end
	function w.phase()
		return w.brain:getPhase()
	end
	return w
end

local function player(id: number, x: number, z: number)
	return { id = id, position = Vector3.new(x, 0, z) }
end

describe("Charger", function()
	it(
		"a lined-up boar at 20 studs crouches: the telegraph carries the attack's 0.6 s wind-up and ground line",
		function()
			local w = world()
			w.players = { player(1, 0, -20) }
			expect(w.stepUntil(function()
				return w.phase() == "WindUp"
			end, 2)).toBe(true)
			expect(w.telegraphs).toHaveLength(1)
			local telegraph = w.telegraphs[1]
			expect(telegraph.attack.id).toBe("Charge")
			expect(telegraph.attack.windUp).toBe(0.6)
			expect(telegraph.attack.telegraph).toBe("Normal")
			expect(telegraph.attack.windUp).toBeGreaterThanOrEqual(Combat.telegraphMinWindUp)
			expect(telegraph.shape).toEqual({ kind = "Line", length = CHARGE.reach, width = AI.telegraph.lineWidth })
			expect(telegraph.origin).toEqual(w.position)
			expect(telegraph.facing.Z).toBeCloseTo(-1, 1e-6)
			expect(w.actions[1].clipId).toBe("enemy/Boar/Charge")
			expect(w.states[1].state).toBe("Art")
			expect(w.moving).toBe(false)
			-- The crouch happens before the alert delay plus one chase tick has passed twice over.
			expect(telegraph.time).toBeLessThan(AI.perception.alertDelay * 2 + TICK * 4)
		end
	)

	it("the crouch holds its line: a sidestep during the wind-up does not bend the telegraph", function()
		local w = world()
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.phase() == "WindUp"
		end, 2)
		local facingAtCrouch = w.facing
		w.players = { player(1, 8, -20) }
		w.stepUntil(function()
			return w.phase() == "Strike"
		end, 2)
		expect(w.facing).toEqual(facingAtCrouch)
		expect(w.telegraphs).toHaveLength(1)
	end)

	it("rushes along the line at the rush speed and strikes 0.5 s in from the crouch point", function()
		local w = world()
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.phase() == "WindUp"
		end, 2)
		local crouchAt = w.telegraphs[1].time
		local crouchPosition = w.position
		expect(w.stepUntil(function()
			return w.phase() == "Strike"
		end, 2)).toBe(true)
		local launchAt = w.time - w.brain:phaseElapsed() -- the tick the Strike phase began
		expect(launchAt - crouchAt).toBeGreaterThanOrEqual(CHARGE.windUp - 1e-9)
		expect(launchAt - crouchAt).toBeLessThan(CHARGE.windUp + TICK * 2)
		-- The rush goal is reach + overshoot down the line at the rush speed.
		local rush = w.goals[#w.goals]
		expect(rush.speed).toBeCloseTo(AI.rushSpeed(CHARGE), 1e-9)
		expect(rush.speed).toBe(tuning.chargeSpeed)
		local expectedEnd = crouchPosition + FORWARD * (CHARGE.reach + tuning.overshoot)
		expect((rush.goal - expectedEnd).Magnitude).toBeLessThan(1e-3)

		expect(w.stepUntil(function()
			return #w.strikes == 1
		end, 2)).toBe(true)
		local strike = w.strikes[1]
		expect(strike.time - launchAt).toBeGreaterThanOrEqual(CHARGE.strike - 1e-9)
		expect(strike.time - launchAt).toBeLessThan(CHARGE.strike + TICK * 2)
		expect(strike.attack.id).toBe("Charge")
		expect((strike.origin - crouchPosition).Magnitude).toBeLessThan(1e-6)
		expect(strike.facing.Z).toBeCloseTo(-1, 1e-6)
		-- By the strike the body has swept the whole telegraphed line.
		expect(Brain.horizontalDistance(w.position, crouchPosition)).toBeGreaterThanOrEqual(CHARGE.reach - 1e-3)
	end)

	it("overshoots past the target, then recovers for the attack's 1.2 s with a slow turn back", function()
		local w = world()
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.phase() == "Strike"
		end, 2)
		local crouchPosition = w.telegraphs[1].origin
		expect(w.stepUntil(function()
			return w.phase() == "Recover"
		end, 3)).toBe(true)
		local travelled = Brain.horizontalDistance(w.position, crouchPosition)
		expect(travelled).toBeGreaterThan(20) -- past the player standing at 20
		expect(travelled).toBeCloseTo(CHARGE.reach + tuning.overshoot, tuning.chargeSpeed * TICK)
		expect(w.moving).toBe(false)
		expect(w.states[#w.states].state).toBe("PostMotion")
		expect(w.states[#w.states].duration).toBe(CHARGE.recovery)
		local recoverAt = w.time
		local facingAtRecover = w.facing
		-- The player is now behind: the recovery turns toward them, slowly.
		w.step(1)
		local turned = math.abs(Brain.signedAngle(facingAtRecover, w.facing))
		expect(turned).toBeGreaterThan(0)
		expect(turned).toBeLessThanOrEqual(tuning.recoverTurnRate * TICK + 1e-6)
		expect(w.stepUntil(function()
			return w.phase() ~= "Recover"
		end, 3)).toBe(true)
		expect(w.time - recoverAt).toBeGreaterThanOrEqual(CHARGE.recovery - TICK)
		expect(w.phase()).toBe("Chase")
	end)

	it("turns slowly while chasing: never more than turnRate * dt per tick, so the path is a wide arc", function()
		local w = world()
		w.players = { player(1, -30, -5) } -- off to the side
		w.stepUntil(function()
			return w.phase() == "Chase"
		end, 2)
		local previous = w.facing
		for _ = 1, 10 do
			w.step(1)
			local turned = math.abs(Brain.signedAngle(previous, w.facing))
			expect(turned).toBeLessThanOrEqual(tuning.turnRate * TICK + 1e-3)
			previous = w.facing
		end
		-- It keeps running forward along its facing while it turns, not sideways at the target.
		local lastGoal = w.goals[#w.goals]
		local goalDirection = (lastGoal.goal - w.position).Unit
		expect(goalDirection:Dot(w.facing)).toBeGreaterThan(0.99)
	end)

	it("too close to charge it circles outward and only crouches once the line is clear", function()
		local w = world()
		w.players = { player(1, 2, -5) }
		expect(w.stepUntil(function()
			return #w.telegraphs == 1
		end, tuning.lineUpTimeout + 4)).toBe(true)
		local telegraph = w.telegraphs[1]
		local distance = Brain.horizontalDistance(telegraph.origin, Vector3.new(2, 0, -5))
		expect(distance).toBeGreaterThanOrEqual(tuning.minChargeDistance)
		expect(distance).toBeLessThanOrEqual(tuning.maxChargeDistance)
		local toPlayer = Brain.horizontal(Vector3.new(2, 0, -5) - telegraph.origin)
		local angle = math.abs(Brain.signedAngle(telegraph.facing, toPlayer))
		expect(angle).toBeLessThanOrEqual(tuning.lineUpLooseToleranceDegrees + 1e-6)
	end)

	it("a target beyond the charge band is run at straight; inside it, a line within tolerance is required", function()
		local w = world()
		local target = { id = 1, position = Vector3.new(0, 0, -20), distance = 20, direction = FORWARD }
		expect(Charger.canUse(w.brain, CHARGE, target)).toBe(true)
		local farDistance = tuning.maxChargeDistance + 5
		local far = { id = 1, position = FORWARD * farDistance, distance = farDistance, direction = FORWARD }
		expect(Charger.canUse(w.brain, CHARGE, far)).toBe(false)
		local near = { id = 1, position = Vector3.new(0, 0, -5), distance = 5, direction = FORWARD }
		expect(Charger.canUse(w.brain, CHARGE, near)).toBe(false)
		local offLine = Brain.rotateY(FORWARD, tuning.lineUpToleranceDegrees + 5)
		local sideways = { id = 1, position = offLine * 20, distance = 20, direction = offLine }
		expect(Charger.canUse(w.brain, CHARGE, sideways)).toBe(false)
		-- After the line-up timeout the tolerance widens.
		w.brain.memory.chaseSince = w.time - tuning.lineUpTimeout
		expect(Charger.canUse(w.brain, CHARGE, sideways)).toBe(true)
		local wayOff = Brain.rotateY(FORWARD, tuning.lineUpLooseToleranceDegrees + 5)
		expect(Charger.canUse(w.brain, CHARGE, { id = 1, position = wayOff * 20, distance = 20, direction = wayOff })).toBe(
			false
		)
	end)

	it("an Elite's Trample needs the target under the body and resolves from where it stands", function()
		local w = world()
		local trample = Enemies.eliteAttacks.Charger
		local under = { id = 1, position = Vector3.new(0, 0, -3), distance = 3, direction = FORWARD }
		expect(Charger.canUse(w.brain, trample, under)).toBe(true)
		local behind = { id = 1, position = Vector3.new(0, 0, 3), distance = 3, direction = -FORWARD }
		expect(Charger.canUse(w.brain, trample, behind)).toBe(true) -- a 360 circle
		local away = { id = 1, position = Vector3.new(0, 0, -12), distance = 12, direction = FORWARD }
		expect(Charger.canUse(w.brain, trample, away)).toBe(false)
		w.brain.attack = trample
		Charger.onStrikeStart(w.brain, under)
		expect(w.brain.memory.rushing).toBe(false)
		local origin, facing = Charger.strikeFrame(w.brain)
		expect(origin).toEqual(w.position)
		expect(facing).toEqual(w.facing)
		expect(Charger.onStrike(w.brain, TICK, 0)).toBe(true)
	end)

	it("a boar that is struck into a Stagger mid-crouch never launches", function()
		local w = world()
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.phase() == "WindUp"
		end, 2)
		local positionAtCrouch = w.position
		w.record.state = "Stagger"
		w.brain:interrupt("Stagger", Combat.parryStagger)
		w.record.state = "Idle"
		w.stepUntil(function()
			return w.phase() == "Chase"
		end, 3)
		expect(w.strikes).toHaveLength(0)
		expect(Brain.horizontalDistance(w.position, positionAtCrouch)).toBeLessThan(1e-6)
	end)
end)
