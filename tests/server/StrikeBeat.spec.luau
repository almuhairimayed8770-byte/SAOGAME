--!strict
--[[
	The strike's beat on a real server clock: EnemyService ticks the brains at ai.tickHz from a
	Heartbeat whose frames jitter, so the AI tick that notices the wind-up ended is up to a tick
	after it. The clients draw the chop and the telegraph's end on the attack's own beat (the
	telegraph's serverTime + windUp + strike + the hit-stop pauses), so the strike must resolve on
	the first tick at or after that beat: never early, and never a second tick late because the
	strike phase was timed from the tick that noticed the wind-up end. A Charger's rush resolves its
	line on the same beat (the wind-up's end, which RushStarted carries and the clients predict),
	while its body runs from the tick it started.
]]

local Brain = Harness.load("src/server/ai/Brain")
local Charger = Harness.load("src/server/ai/Charger")
local Brute = Harness.load("src/server/ai/Brute")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")

local TICK = AI.tickSeconds()
local FRAME = 1 / 60
local JITTER = 0.002 -- seconds a Heartbeat frame runs early or late
local EPSILON = 1e-9

-- A brain on a fake server: frames of FRAME +- JITTER seconds, the brain ticked from an accumulator
-- the way EnemyService.step does, and a body that runs toward its MoveTo goal each frame.
local function server(defId: string, seed: number, playerAt: Vector3)
	local def = Enemies.scaled(Enemies.byId(defId))
	local s: any = {
		time = 1000 + seed * 0.37,
		accumulator = 0,
		random = Random.new(seed),
		position = Vector3.zero,
		facing = Vector3.new(0, 0, -1),
		record = { state = "Idle", threat = {} },
		goal = nil,
		speed = nil,
		telegraphs = {},
		strikes = {},
		rushes = {},
		ended = {},
		ticks = {},
	}
	s.context = {
		entityId = 7,
		def = def,
		home = Vector3.zero,
		now = function()
			return s.time
		end,
		getRecord = function()
			return s.record
		end,
		players = function()
			return { { id = 1, position = playerAt } }
		end,
		position = function()
			return s.position
		end,
		facing = function()
			return s.facing
		end,
		moveTo = function(position, speed)
			s.goal = position
			s.speed = speed
		end,
		stop = function()
			s.goal = nil
		end,
		face = function(direction)
			s.facing = direction
		end,
		telegraph = function()
			table.insert(s.telegraphs, s.time)
		end,
		strike = function(_attack, _origin, _facing, options)
			table.insert(s.strikes, { time = s.time, span = if options ~= nil then options.span else nil })
		end,
		setState = function(state)
			s.record.state = state
		end,
		actionStarted = function() end,
		random = Random.new(seed),
		bodyExtents = function()
			return 5.6, 3.3
		end,
		rushStarted = function(rush)
			table.insert(s.rushes, rush)
		end,
		rushEnded = function(rush, reason)
			table.insert(s.ended, { time = s.time, reason = reason, rush = rush })
		end,
	}
	s.brain = Brain.new(s.context, if def.archetype == "Brute" then Brute else Charger)
	function s.frame()
		local dt = FRAME + (s.random:NextNumber() * 2 - 1) * JITTER
		s.time += dt
		s.accumulator += dt
		while s.accumulator >= TICK do
			s.accumulator -= TICK
			table.insert(s.ticks, s.time)
			s.brain:tick(TICK)
		end
		if s.goal ~= nil then
			local delta = s.goal - s.position
			local reach = (s.speed or def.moveSpeed) * dt
			s.position = if delta.Magnitude <= reach then s.goal else s.position + delta.Unit * reach
		end
	end
	-- The first AI tick at or after `beat`.
	function s.firstTickFrom(beat: number): number?
		for _, at in s.ticks do
			if at >= beat - EPSILON then
				return at
			end
		end
		return nil
	end
	function s.frameUntil(predicate: () -> boolean, seconds: number): boolean
		for _ = 1, math.ceil(seconds / FRAME) do
			if predicate() then
				return true
			end
			s.frame()
		end
		return predicate()
	end
	return s
end

describe("an enemy's strike resolves on its own beat, the clients' beat (D-182)", function()
	it("a Kobold's Overhead resolves on the first AI tick at or after windUp + strike, never a tick later", function()
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		for seed = 1, 40 do
			local s = server("KoboldAxeman", seed, Vector3.new(0, 0, -4))
			expect(s.frameUntil(function()
				return #s.telegraphs > 0
			end, 5)).toBe(true)
			expect(s.frameUntil(function()
				return #s.strikes > 0
			end, 5)).toBe(true)
			local beat = s.telegraphs[1] + overhead.windUp + overhead.strike
			expect(s.strikes[1].time).toBe(s.firstTickFrom(beat))
		end
	end)

	it("hit-stop pauses that land between ticks move the beat and nothing else (D-168)", function()
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		for seed = 1, 40 do
			local s = server("KoboldAxeman", seed, Vector3.new(0, 0, -4))
			s.frameUntil(function()
				return #s.telegraphs > 0
			end, 5)
			local paused = 0
			local frames = 0
			s.frameUntil(function()
				frames += 1
				if #s.strikes == 0 and frames % 7 == 0 then
					paused += s.brain:pauseAttack(4 * FRAME) or 0
				end
				return #s.strikes > 0
			end, 5)
			expect(paused).toBeGreaterThan(0)
			local beat = s.telegraphs[1] + overhead.windUp + overhead.strike + paused
			expect(s.strikes[1].time).toBe(s.firstTickFrom(beat))
		end
	end)

	it("a Charger's rush resolves its line on the launch beat and runs its body from the launch tick", function()
		local charge = Enemies.byId("FrenzyBoar").attacks[1]
		local front = 5.6
		for seed = 1, 20 do
			local s = server("FrenzyBoar", seed, Vector3.new(0, 0, -20))
			expect(s.frameUntil(function()
				return #s.rushes > 0
			end, 5)).toBe(true)
			local rush = s.rushes[1]
			local beat = s.telegraphs[1] + charge.windUp
			-- RushStarted carries the beat the clients predicted from the telegraph; the body starts on
			-- the first tick at or after it, where the launch's own stretch resolves.
			expect(rush.startedAt).toBeCloseTo(beat, 1e-9)
			expect(rush.bodyStartedAt).toBe(s.firstTickFrom(beat))
			expect(s.strikes[1].time).toBe(rush.bodyStartedAt)
			expect(s.frameUntil(function()
				return s.brain:getPhase() == "Recover"
			end, 3)).toBe(true)
			-- Every stretch reaches the snout on the beat's clock (what the clients draw), never past the
			-- strike beat, and the whole line has resolved on the first tick at or after it.
			for _, stretch in s.strikes do
				local upTo = math.clamp(stretch.time - beat, 0, charge.strike)
				expect(stretch.span.to).toBeCloseTo(rush.speed * upTo + front, 1e-6)
			end
			expect(s.strikes[#s.strikes].time).toBe(s.firstTickFrom(beat + charge.strike))
			-- The body runs its whole duration from the tick it started: no early end, no false jam.
			expect(#s.ended).toBe(1)
			expect(s.ended[1].reason).toBe("Done")
			expect(s.ended[1].time).toBe(s.firstTickFrom(rush.bodyStartedAt + rush.duration))
		end
	end)
end)
