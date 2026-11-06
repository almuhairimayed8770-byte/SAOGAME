--!strict
--[[
	Brute: the Kobold Axeman driven with a fake clock and context. Walks up, holds the 1.0 s
	overhead (yellow edge, 60-degree cone), tracks the target only slowly while it holds so a dodge
	leaves the cone, strikes 0.35 s after the wind-up from where it stands, recovers 1.4 s; a
	Stagger (a parry) during the wind-up cancels the strike.
]]

local Brain = Harness.load("src/server/ai/Brain")
local Brute = Harness.load("src/server/ai/Brute")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Combat = Harness.load("src/shared/data/combat")

local TICK = AI.tickSeconds()
local FORWARD = Vector3.new(0, 0, -1)
local tuning = AI.archetypes.Brute
local KOBOLD = Enemies.byId("KoboldAxeman")
local OVERHEAD = KOBOLD.attacks[1]

local function world(options: { position: Vector3?, facing: Vector3?, seed: number? }?)
	local opts = options or {}
	local def = Enemies.scaled(KOBOLD)
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
		goals = {},
	}
	w.home = w.position
	w.context = {
		entityId = 4,
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
		random = Random.new(opts.seed or 5),
	}
	w.brain = Brain.new(w.context, Brute)
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

describe("Brute", function()
	it("walks up to the target at its move speed and begins the overhead inside engage range", function()
		local w = world()
		w.players = { player(1, 0, -20) }
		expect(w.stepUntil(function()
			return w.phase() == "Chase"
		end, 2)).toBe(true)
		w.step(1)
		expect(w.moving).toBe(true)
		expect(w.speed).toBe(KOBOLD.moveSpeed)
		expect((w.goal - Vector3.new(0, 0, -20)).Magnitude).toBeLessThan(1e-6)
		expect(w.stepUntil(function()
			return w.phase() == "WindUp"
		end, 5)).toBe(true)
		local distance = Brain.horizontalDistance(w.position, Vector3.new(0, 0, -20))
		expect(distance).toBeLessThanOrEqual(OVERHEAD.reach * tuning.engageFraction + 1e-6)
		expect(distance).toBeGreaterThan(tuning.stopDistance - KOBOLD.moveSpeed * TICK)
		expect(w.moving).toBe(false)
	end)

	it("holds the 1.0 s wind-up with the yellow edge and the 60-degree cone, then strikes 0.35 s later", function()
		local w = world()
		w.players = { player(1, 0, -4) }
		expect(w.stepUntil(function()
			return w.phase() == "WindUp"
		end, 2)).toBe(true)
		local telegraph = w.telegraphs[1]
		expect(telegraph.attack.id).toBe("Overhead")
		expect(telegraph.attack.telegraph).toBe("GuardBreak")
		expect(telegraph.attack.windUp).toBe(1.0)
		expect(telegraph.attack.windUp).toBeGreaterThanOrEqual(Combat.telegraphMinWindUp)
		expect(telegraph.shape).toEqual({ kind = "Cone", length = OVERHEAD.reach, width = OVERHEAD.arc })
		expect(w.actions[1].clipId).toBe("enemy/Kobold/Overhead")
		expect(w.states[1].state).toBe("Art")
		expect(w.states[1].duration).toBeCloseTo(OVERHEAD.windUp + OVERHEAD.strike, 1e-9)

		expect(w.stepUntil(function()
			return #w.strikes == 1
		end, 3)).toBe(true)
		local strike = w.strikes[1]
		local held = strike.time - telegraph.time
		expect(held).toBeGreaterThanOrEqual(OVERHEAD.windUp + OVERHEAD.strike - 1e-9)
		expect(held).toBeLessThan(OVERHEAD.windUp + OVERHEAD.strike + TICK * 2)
		expect(strike.origin).toEqual(w.position)
		expect(strike.facing).toEqual(w.facing)
		-- The strike phase ends with the hit: the recovery starts the same tick.
		expect(w.phase()).toBe("Recover")
		expect(w.states[#w.states].state).toBe("PostMotion")
		expect(w.states[#w.states].duration).toBe(OVERHEAD.recovery)
	end)

	it("recovers for the attack's 1.4 s, then chases again", function()
		local w = world()
		w.players = { player(1, 0, -4) }
		w.stepUntil(function()
			return w.phase() == "Recover"
		end, 3)
		local recoverAt = w.time
		expect(w.stepUntil(function()
			return w.phase() ~= "Recover"
		end, 3)).toBe(true)
		expect(w.time - recoverAt).toBeGreaterThanOrEqual(OVERHEAD.recovery - TICK)
		expect(w.time - recoverAt).toBeLessThan(OVERHEAD.recovery + TICK * 2)
		expect(w.states[#w.states].state).toBe("Idle")
		expect(w.phase()).toBe("Chase")
	end)

	it("tracks the target only slowly during the wind-up, so a dodge leaves the cone", function()
		local w = world()
		local engage = OVERHEAD.reach * tuning.engageFraction
		w.players = { player(1, 0, -engage) }
		expect(w.stepUntil(function()
			return w.phase() == "WindUp"
		end, 2)).toBe(true)
		local facingAtWindUp = w.facing
		-- A dodge (section 6) straight to the side the moment the wind-up begins.
		local dodged = Vector3.new(Combat.dodgeDistance, 0, -engage)
		w.players = { player(1, dodged.X, dodged.Z) }
		expect(w.stepUntil(function()
			return #w.strikes == 1
		end, 3)).toBe(true)
		local strike = w.strikes[1]
		local turned = math.abs(Brain.signedAngle(facingAtWindUp, strike.facing))
		expect(turned).toBeGreaterThan(0) -- it does track...
		expect(turned).toBeLessThanOrEqual(tuning.windUpTurnRate * OVERHEAD.windUp + tuning.windUpTurnRate * TICK * 2)
		local toPlayer = Brain.horizontal(dodged - strike.origin)
		local offCone = math.abs(Brain.signedAngle(strike.facing, toPlayer))
		expect(offCone).toBeGreaterThan(OVERHEAD.arc / 2) -- ...but the dodge is outside the cone
	end)

	it("the strike commits: the facing does not change between the wind-up's end and the hit", function()
		local w = world()
		w.players = { player(1, 0, -4) }
		w.stepUntil(function()
			return w.phase() == "Strike"
		end, 3)
		local facingAtLaunch = w.facing
		w.players = { player(1, 6, -4) }
		w.stepUntil(function()
			return #w.strikes == 1
		end, 2)
		expect(w.strikes[1].facing).toEqual(facingAtLaunch)
	end)

	it("a Stagger during the wind-up (a parry) cancels the strike", function()
		local w = world()
		w.players = { player(1, 0, -4) }
		w.stepUntil(function()
			return w.phase() == "WindUp"
		end, 2)
		w.record.state = "Stagger"
		w.brain:interrupt("Stagger", Combat.parryStagger)
		w.stepUntil(function()
			return w.time >= Combat.parryStagger
		end, 3)
		w.record.state = "Idle"
		expect(w.stepUntil(function()
			return w.phase() == "Chase"
		end, 3)).toBe(true)
		expect(w.strikes).toHaveLength(0)
		expect(w.telegraphs).toHaveLength(1)
		-- It attacks again once the chase resumes and the cooldown has passed.
		expect(w.stepUntil(function()
			return #w.telegraphs == 2
		end, 6)).toBe(true)
	end)

	it("canUse needs the target inside reach * engageFraction and roughly ahead", function()
		local w = world()
		local engage = OVERHEAD.reach * tuning.engageFraction
		local ahead = { id = 1, position = FORWARD * (engage - 0.1), distance = engage - 0.1, direction = FORWARD }
		expect(Brute.canUse(w.brain, OVERHEAD, ahead)).toBe(true)
		local far = { id = 1, position = FORWARD * (engage + 0.5), distance = engage + 0.5, direction = FORWARD }
		expect(Brute.canUse(w.brain, OVERHEAD, far)).toBe(false)
		local limit = math.min(tuning.engageAngle, OVERHEAD.arc / 2)
		local sideDirection = Brain.rotateY(FORWARD, limit + 5)
		local side = { id = 1, position = sideDirection * 3, distance = 3, direction = sideDirection }
		expect(Brute.canUse(w.brain, OVERHEAD, side)).toBe(false)
		local inDirection = Brain.rotateY(FORWARD, limit - 5)
		local inside = { id = 1, position = inDirection * 3, distance = 3, direction = inDirection }
		expect(Brute.canUse(w.brain, OVERHEAD, inside)).toBe(true)
	end)

	it("stops walking inside stopDistance and keeps facing the target", function()
		local w = world()
		w.players = { player(1, 0, -2) }
		w.stepUntil(function()
			return w.phase() == "Chase"
		end, 2)
		w.brain.cooldowns.Overhead = math.huge -- never attack; the walking rule is the point
		w.step(2)
		expect(w.moving).toBe(false)
		w.players = { player(1, 3, -2) }
		w.step(1)
		expect(w.brain:angleTo(Vector3.new(3, 0, -2))).toBeLessThan(
			Brain.signedAngle(FORWARD, Vector3.new(3, 0, -2)) * -1
		)
	end)
end)
