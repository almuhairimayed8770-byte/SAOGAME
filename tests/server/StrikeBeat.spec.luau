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

	The frame pass (D-184): EnemyService also runs every awake brain once per server frame, after the
	frame's ticks, and the timed edges resolve there: the wind-up's end, the strike, the rush's
	stretches and its run each land on the first server frame at or after their beat (within one
	server frame, never early, never twice), at 60 and at 30 frames a second. An asleep or dead brain
	does nothing in it, and an interrupt or a parry met there stops the attack as the tick would.

	The body turns every frame (D-185): a tick sets where it turns and how fast for the phase, and the
	frames turn it by that rate times their own seconds, so the steps are a frame's worth (not a
	tick's) and the published facing is always the brain's: the telegraph and the strike leave from
	where the body points.
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
local ANGLE_EPSILON = 1e-4 -- degrees: Vector3 holds 32-bit floats

export type ServerOptions = {
	fps: number?, -- server frames a second (60 unless given)
	framePass: boolean?, -- run brain:frame() after the ticks each frame, as EnemyService.step does
}

-- A brain on a fake server: frames of 1 / fps +- JITTER seconds, the body moved toward its MoveTo
-- goal first (physics runs before Heartbeat), then the brain ticked from an accumulator the way
-- EnemyService.step does and, with framePass, its frame pass.
local function server(defId: string, seed: number, playerAt: Vector3, options: ServerOptions?)
	local opts: ServerOptions = options or {}
	local frameSeconds = 1 / (opts.fps or 60)
	local def = Enemies.scaled(Enemies.byId(defId))
	local s: any = {
		time = 1000 + seed * 0.37,
		accumulator = 0,
		random = Random.new(seed),
		position = Vector3.zero,
		facing = Vector3.new(0, 0, -1),
		record = { state = "Idle", threat = {} },
		playerAt = playerAt,
		goal = nil,
		speed = nil,
		telegraphs = {},
		strikes = {},
		rushes = {},
		ended = {},
		ticks = {},
		frames = {},
		faces = {},
		states = {},
		frameSeconds = frameSeconds,
		onStrike = nil,
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
			return { { id = 1, position = s.playerAt } }
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
			table.insert(s.faces, { time = s.time, facing = direction })
		end,
		telegraph = function(_attack, _origin, facing)
			table.insert(s.telegraphs, s.time)
			s.telegraphFacing = facing
		end,
		strike = function(_attack, _origin, facing, options)
			table.insert(
				s.strikes,
				{ time = s.time, facing = facing, span = if options ~= nil then options.span else nil }
			)
			local hook = s.onStrike
			if hook ~= nil then
				hook()
			end
		end,
		setState = function(state)
			s.record.state = state
			table.insert(s.states, { time = s.time, state = state })
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
	-- One server frame of `seconds` (a jittered 1 / fps unless given): physics, the ticks, the frame pass.
	function s.frame(seconds: number?)
		local dt = seconds or (frameSeconds + (s.random:NextNumber() * 2 - 1) * JITTER)
		s.time += dt
		if s.goal ~= nil then
			local delta = s.goal - s.position
			local reach = (s.speed or def.moveSpeed) * dt
			s.position = if delta.Magnitude <= reach then s.goal else s.position + delta.Unit * reach
		end
		s.accumulator += dt
		local ticks = 0
		while s.accumulator >= TICK and ticks < AI.maxTicksPerFrame do
			s.accumulator -= TICK
			ticks += 1
			table.insert(s.ticks, s.time)
			s.brain:tick(TICK)
		end
		if s.accumulator >= TICK then
			s.accumulator = 0
		end
		table.insert(s.frames, s.time)
		if opts.framePass then
			s.brain:frame()
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
	-- The first server frame at or after `beat`.
	function s.firstFrameFrom(beat: number): number?
		for _, at in s.frames do
			if at >= beat - EPSILON then
				return at
			end
		end
		return nil
	end
	function s.frameUntil(predicate: () -> boolean, seconds: number): boolean
		for _ = 1, math.ceil(seconds / frameSeconds) do
			if predicate() then
				return true
			end
			s.frame()
		end
		return predicate()
	end
	return s
end

local function angleBetween(a: Vector3, b: Vector3): number
	return math.abs(Brain.signedAngle(a, b))
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

-- ------------------------------------------------------------------------------------------
-- The frame pass: the edges on the first server frame at or after their beat (D-184)
-- ------------------------------------------------------------------------------------------

local FPS_CASES = { 60, 30 }

describe("the frame pass resolves an attack's edges on the server frame of their beat (D-184)", function()
	it("a Kobold's Overhead resolves once, on the first server frame at or after its beat, at 60 and 30 fps", function()
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		for _, fps in FPS_CASES do
			for seed = 1, 30 do
				local s = server("KoboldAxeman", seed, Vector3.new(0, 0, -4), { fps = fps, framePass = true })
				expect(s.frameUntil(function()
					return #s.telegraphs > 0
				end, 5)).toBe(true)
				local beat = s.telegraphs[1] + overhead.windUp + overhead.strike
				expect(s.frameUntil(function()
					return #s.strikes > 0
				end, 5)).toBe(true)
				expect(s.strikes[1].time).toBe(s.firstFrameFrom(beat))
				expect(s.strikes[1].time - beat).toBeLessThan(s.frameSeconds + JITTER + EPSILON)
				-- The recovery starts on the strike's frame, not a tick later; and nothing resolves twice.
				expect(s.brain:getPhase()).toBe("Recover")
				expect(s.brain.phaseStart).toBe(s.strikes[1].time)
				s.frameUntil(function()
					return s.brain:getPhase() ~= "Recover"
				end, 3)
				expect(#s.strikes).toBe(1)
			end
		end
	end)

	it("hit-stop pauses between frames move the beat the frame pass waits for (D-168)", function()
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		for _, fps in FPS_CASES do
			for seed = 1, 30 do
				local s = server("KoboldAxeman", seed, Vector3.new(0, 0, -4), { fps = fps, framePass = true })
				s.frameUntil(function()
					return #s.telegraphs > 0
				end, 5)
				local paused = 0
				local frames = 0
				s.frameUntil(function()
					frames += 1
					if #s.strikes == 0 and frames % 5 == 0 then
						paused += s.brain:pauseAttack(3 / 60) or 0
					end
					return #s.strikes > 0
				end, 5)
				expect(paused).toBeGreaterThan(0)
				local beat = s.telegraphs[1] + overhead.windUp + overhead.strike + paused
				expect(s.strikes[1].time).toBe(s.firstFrameFrom(beat))
				expect(#s.strikes).toBe(1)
			end
		end
	end)

	it("a Charger's rush launches on the first frame at or after the wind-up's end and sweeps every frame", function()
		local charge = Enemies.byId("FrenzyBoar").attacks[1]
		local front = 5.6
		for _, fps in FPS_CASES do
			for seed = 1, 20 do
				local s = server("FrenzyBoar", seed, Vector3.new(0, 0, -20), { fps = fps, framePass = true })
				expect(s.frameUntil(function()
					return #s.rushes > 0
				end, 5)).toBe(true)
				local rush = s.rushes[1]
				local beat = s.telegraphs[1] + charge.windUp
				expect(rush.startedAt).toBeCloseTo(beat, 1e-9)
				expect(rush.bodyStartedAt).toBe(s.firstFrameFrom(beat))
				expect(s.strikes[1].time).toBe(rush.bodyStartedAt)
				-- The run's goal reaches the mover on the launch frame.
				expect(s.goal).never.toBeNil()
				expect(s.frameUntil(function()
					return s.brain:getPhase() == "Recover"
				end, 3)).toBe(true)
				-- One stretch per frame up to the strike beat, each reaching the snout on the beat's clock,
				-- never one twice.
				local lastTo = -math.huge
				for _, stretch in s.strikes do
					local upTo = math.clamp(stretch.time - beat, 0, charge.strike)
					expect(stretch.span.to).toBeCloseTo(rush.speed * upTo + front, 1e-6)
					expect(stretch.span.to).toBeGreaterThan(lastTo)
					lastTo = stretch.span.to
				end
				expect(s.strikes[#s.strikes].time).toBe(s.firstFrameFrom(beat + charge.strike))
				local framesInStrike = 0
				for _, at in s.frames do
					if at >= rush.bodyStartedAt - EPSILON and at <= s.strikes[#s.strikes].time + EPSILON then
						framesInStrike += 1
					end
				end
				expect(#s.strikes).toBe(framesInStrike)
				-- The run ends on its own frame: no early end, no false jam.
				expect(#s.ended).toBe(1)
				expect(s.ended[1].reason).toBe("Done")
				expect(s.ended[1].time).toBe(s.firstFrameFrom(rush.bodyStartedAt + rush.duration))
				expect(s.brain.phaseStart).toBe(s.ended[1].time)
			end
		end
	end)

	it("a hitch never resolves early and never twice: the long frame that crosses the beat resolves it", function()
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		for _, hitch in { 0.12, 0.3 } do
			local s = server("KoboldAxeman", 3, Vector3.new(0, 0, -4), { framePass = true })
			s.frameUntil(function()
				return #s.telegraphs > 0
			end, 5)
			local beat = s.telegraphs[1] + overhead.windUp + overhead.strike
			s.frameUntil(function()
				return s.time + hitch * 0.5 >= beat
			end, 5)
			expect(#s.strikes).toBe(0)
			s.frame(hitch)
			expect(s.time).toBeGreaterThanOrEqual(beat)
			expect(#s.strikes).toBe(1)
			expect(s.strikes[1].time).toBe(s.time)
			s.frameUntil(function()
				return s.brain:getPhase() ~= "Recover"
			end, 3)
			expect(#s.strikes).toBe(1)
		end
	end)

	it("an asleep or dead brain does nothing in the frame pass", function()
		for _, ending in { "sleep", "die", "recordDead" } do
			local s = server("KoboldAxeman", 5, Vector3.new(0, 0, -4), { framePass = true })
			s.frameUntil(function()
				return #s.telegraphs > 0
			end, 5)
			if ending == "sleep" then
				s.brain:sleep()
			elseif ending == "die" then
				s.brain:die()
			else
				s.record.state = "Dead"
			end
			local phase = s.brain:getPhase()
			local facing = s.brain:getFacing()
			local faces = #s.faces
			s.playerAt = Vector3.new(6, 0, 0) -- somewhere a live brain would turn toward
			for _ = 1, math.ceil(2 / (1 / 60)) do
				s.time += 1 / 60
				s.brain:frame()
			end
			expect(#s.strikes).toBe(0)
			expect(s.brain:getPhase()).toBe(phase)
			expect(angleBetween(s.brain:getFacing(), facing)).toBe(0)
			expect(#s.faces).toBe(faces)
		end
	end)

	it("an interrupting state met in the frame pass stops the wind-up as the tick would", function()
		local s = server("KoboldAxeman", 6, Vector3.new(0, 0, -4), { framePass = true })
		s.frameUntil(function()
			return #s.telegraphs > 0
		end, 5)
		s.frameUntil(function()
			return s.brain:phaseElapsed() >= 0.5
		end, 2)
		-- The stagger lands between ticks (a parry's StateChanged reaches the brain through the record).
		s.record.state = "Stagger"
		s.time += 0.004
		s.brain:frame()
		expect(s.brain:getPhase()).toBe("Interrupted")
		expect(s.goal).toBeNil()
		s.frameUntil(function()
			return false
		end, 1)
		expect(#s.strikes).toBe(0)
	end)

	it("a parry on a strike resolved in the frame pass interrupts it there: no recovery, no step", function()
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		for seed = 1, 10 do
			local s = server("KoboldAxeman", seed, Vector3.new(0, 0, -4), { framePass = true })
			s.onStrike = function()
				s.record.state = "Stagger"
				s.brain:interrupt("Stagger", 1)
			end
			s.frameUntil(function()
				return #s.telegraphs > 0
			end, 5)
			local beat = s.telegraphs[1] + overhead.windUp + overhead.strike
			s.frameUntil(function()
				return #s.strikes > 0
			end, 5)
			expect(s.strikes[1].time).toBe(s.firstFrameFrom(beat))
			expect(s.brain:getPhase()).toBe("Interrupted")
			for _, entry in s.states do
				expect(entry.state).never.toBe("PostMotion")
			end
			expect(s.goal).toBeNil()
			s.frameUntil(function()
				return false
			end, 1)
			expect(#s.strikes).toBe(1)
		end
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The body turns every frame at the phase's rate (D-185)
-- ------------------------------------------------------------------------------------------

describe("the body turns every server frame at the phase's rate (D-185)", function()
	it("a chase turns a frame's worth every frame, never a tick's step at once", function()
		for _, case in
			{
				{ defId = "KoboldAxeman", rate = AI.archetypes.Brute.turnRate },
				{ defId = "FrenzyBoar", rate = AI.archetypes.Charger.turnRate },
			}
		do
			for _, fps in FPS_CASES do
				-- The player stands behind and to the side: a long turn.
				local s = server(case.defId, 2, Vector3.new(-14, 0, 10), { fps = fps, framePass = true })
				local previous = s.facing
				local turning, moved = 0, 0
				local maxStep = 0
				local lastFrame = s.time
				for _ = 1, math.ceil(1.2 * fps) do
					s.frame()
					local dt = s.time - lastFrame
					lastFrame = s.time
					local step = angleBetween(previous, s.facing)
					previous = s.facing
					maxStep = math.max(maxStep, step / dt)
					local phase = s.brain:getPhase()
					if phase == "Chase" and s.brain:angleTo((s.playerAt - s.position)) > 5 then
						turning += 1
						if step > 1e-6 then
							moved += 1
						end
					end
				end
				expect(turning).toBeGreaterThan(10)
				-- Every frame of the turn moves the body (a tick's step would move it every second or
				-- third frame only), and no frame turns faster than the rate.
				expect(moved).toBeGreaterThanOrEqual(turning - 2)
				expect(maxStep).toBeLessThanOrEqual(case.rate * (1 + 1e-4))
			end
		end
	end)

	it("the body is on the brain's line at the telegraph and at the strike", function()
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		for seed = 1, 10 do
			local s = server("KoboldAxeman", seed, Vector3.new(3, 0, -5), { framePass = true })
			s.frameUntil(function()
				return #s.telegraphs > 0
			end, 5)
			expect(angleBetween(s.facing, s.brain:getFacing())).toBeLessThan(ANGLE_EPSILON)
			expect(angleBetween(s.telegraphFacing, s.facing)).toBeLessThan(ANGLE_EPSILON)
			-- The player steps aside: the body tracks at the wind-up's slow rate, every frame.
			s.playerAt = Vector3.new(6, 0, -1)
			local previous = s.facing
			local lastFrame = s.time
			while #s.strikes == 0 and s.brain:getPhase() ~= "Idle" do
				s.frame()
				local dt = s.time - lastFrame
				lastFrame = s.time
				local phase = s.brain:getPhase()
				local rate = if phase == "WindUp"
					then AI.archetypes.Brute.windUpTurnRate
					else AI.archetypes.Brute.strikeTurnRate
				if phase == "WindUp" or (phase == "Strike" and s.brain.phaseStart <= s.time - dt) then
					expect(angleBetween(previous, s.facing)).toBeLessThanOrEqual(rate * dt + ANGLE_EPSILON)
				end
				previous = s.facing
			end
			expect(#s.strikes).toBe(1)
			expect(angleBetween(s.strikes[1].facing, s.facing)).toBeLessThan(ANGLE_EPSILON)
			expect(s.strikes[1].time - (s.telegraphs[1] + overhead.windUp + overhead.strike)).toBeGreaterThanOrEqual(
				-EPSILON
			)
		end
	end)

	it("a hit-stop freeze holds the wind-up's turn; the crouch and the rush hold the boar's line", function()
		local s = server("KoboldAxeman", 4, Vector3.new(0, 0, -4), { framePass = true })
		s.frameUntil(function()
			return #s.telegraphs > 0
		end, 5)
		s.playerAt = Vector3.new(5, 0, -1)
		s.frameUntil(function()
			return s.brain:phaseElapsed() >= 0.2
		end, 1)
		local frozenAt = s.facing
		expect(s.brain:pauseAttack(0.1)).toBeGreaterThan(0)
		local until_ = s.time + 0.1
		while s.time + 1 / 60 + JITTER < until_ do
			s.frame()
			expect(angleBetween(s.facing, frozenAt)).toBeLessThan(ANGLE_EPSILON)
		end
		s.frameUntil(function()
			return s.time > until_ + 0.1
		end, 1)
		expect(angleBetween(s.facing, frozenAt)).toBeGreaterThan(0)

		local b = server("FrenzyBoar", 4, Vector3.new(0, 0, -20), { framePass = true })
		b.frameUntil(function()
			return #b.telegraphs > 0
		end, 5)
		local line = b.facing
		b.playerAt = Vector3.new(8, 0, -18)
		b.frameUntil(function()
			expect(angleBetween(b.facing, line)).toBeLessThan(ANGLE_EPSILON)
			return b.brain:getPhase() == "Recover"
		end, 3)
	end)
end)
