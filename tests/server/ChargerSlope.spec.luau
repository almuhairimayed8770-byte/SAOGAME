--!strict
--[[
	A Frenzy Boar's rush up a 40 degree slope (STUDIO_TASKS 308(a), PC 1cf87aa D1): the body never
	stops, it climbs. On the PC it ran 28 studs/s on the flat, then from 6.75 studs along it climbed
	at a steady 19.0 studs/s across and 10.9 up (21.9 along the slope) until the rush's clock ran
	4 studs ahead of its flat progress and the jam lag ended it "Jammed" at 15.46 studs. A climbing
	body is moving, not stuck: the rush runs its time and ends Done. A body that does not move at
	all is still jammed (RushContact.spec, Charger.spec).

	The fake world is Charger.spec's, with the body's own motion replaced by the PC's climb.
]]

local Brain = Harness.load("src/server/ai/Brain")
local Charger = Harness.load("src/server/ai/Charger")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")

local TICK = AI.tickSeconds()
local FORWARD = Vector3.new(0, 0, -1)
local BOAR = Enemies.byId("FrenzyBoar")

local function world(
	options: { position: Vector3?, facing: Vector3?, seed: number?, extents: (() -> (number, number))? }?
)
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
		moveTo = function(position, speed, direct)
			w.goal = position
			w.speed = speed
			w.moving = true
			table.insert(
				w.goals,
				{ time = w.time, goal = position, speed = speed, direct = direct, phase = w.brain:getPhase() }
			)
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
		strike = function(attack, origin, facing, options)
			table.insert(
				w.strikes,
				{ time = w.time, attack = attack, origin = origin, facing = facing, options = options }
			)
		end,
		setState = function(state, duration)
			w.record.state = state
			table.insert(w.states, { time = w.time, state = state, duration = duration })
		end,
		actionStarted = function(clipId, facing)
			table.insert(w.actions, { time = w.time, clipId = clipId, facing = facing })
		end,
		random = Random.new(opts.seed or 3),
		bodyExtents = opts.extents,
	}
	w.blocked = false -- a jammed body: MoveTo goals are taken but the body does not move
	w.brain = Brain.new(w.context, Charger)
	function w.step(count: number?)
		for _ = 1, count or 1 do
			w.brain:tick(TICK)
			if w.moving and w.goal ~= nil and not w.blocked then
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

-- The PC's climb (1cf87aa D1): where the slope starts along the run, and the body's speed across
-- and up while it climbs.
local SLOPE_FROM = 6.75
local CLIMB_ACROSS = 19.0
local CLIMB_UP = 10.9

local function climbing(w: any)
	function w.step(count: number?)
		for _ = 1, count or 1 do
			w.brain:tick(TICK)
			if w.moving and w.goal ~= nil and not w.blocked then
				local flatDelta = Vector3.new(w.goal.X - w.position.X, 0, w.goal.Z - w.position.Z)
				local distance = flatDelta.Magnitude
				local onSlope = -w.position.Z >= SLOPE_FROM
				local speed = w.speed or w.context.def.moveSpeed
				if onSlope then
					speed = math.min(speed, CLIMB_ACROSS)
				end
				local reach = speed * TICK
				local across = if distance <= reach then flatDelta else flatDelta.Unit * reach
				local up = if onSlope and distance > 0 then CLIMB_UP * TICK * (across.Magnitude / reach) else 0
				w.position = w.position + across + Vector3.new(0, up, 0)
			end
			w.time += TICK
		end
	end
end

describe("Charger on a climbable slope (308)", function()
	it("a body climbing a 40 degree slope runs its rush to its end, never Jammed", function()
		local w = world({
			extents = function()
				return 5.6, 3.3
			end,
		})
		climbing(w)
		local ends = {}
		w.context.rushEnded = function(_rush, reason, distance)
			table.insert(ends, { time = w.time, reason = reason, distance = distance })
		end
		w.players = { player(1, 0, -20) }
		expect(w.stepUntil(function()
			return w.phase() == "WindUp"
		end, 2)).toBe(true)
		expect(w.stepUntil(function()
			return w.phase() == "Recover"
		end, 3)).toBe(true)
		expect(ends[1] ~= nil and ("%s at %.2f"):format(ends[1].reason, ends[1].distance)).toBe(
			("Done at %.2f"):format(ends[1] ~= nil and ends[1].distance or 0)
		)
		expect(#ends).toBe(1)
		-- It climbed: the body rose on its way, so the case is the slope's, not the flat's.
		expect(w.position.Y).toBeGreaterThan(CLIMB_UP * 0.3)
	end)

	it("a body that stops dead on the slope is still Jammed", function()
		local w = world({
			extents = function()
				return 5.6, 3.3
			end,
		})
		climbing(w)
		local ends = {}
		w.context.rushEnded = function(_rush, reason, distance)
			table.insert(ends, { time = w.time, reason = reason, distance = distance })
		end
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.phase() == "Strike"
		end, 2)
		w.stepUntil(function()
			return -w.position.Z >= SLOPE_FROM + 2
		end, 1)
		w.blocked = true
		w.stepUntil(function()
			return w.phase() == "Recover"
		end, 3)
		expect(#ends >= 1).toBe(true)
		expect(ends[1].reason).toBe("Jammed")
	end)
end)
