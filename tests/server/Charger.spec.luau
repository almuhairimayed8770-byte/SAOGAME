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
			expect(telegraph.attack.telegraph).toBe("Unblockable") -- the red line: sidestep, never guard
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

	it(
		"rushes along the line at the rush speed and has struck the whole line 0.5 s in, from the crouch point",
		function()
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

			-- The rush resolves by contact (D-166): stretch after stretch, the last one 0.5 s in.
			w.stepUntil(function()
				return w.phase() ~= "Strike"
			end, 2)
			expect(#w.strikes).toBeGreaterThan(1)
			local last = w.strikes[#w.strikes]
			expect(last.time - launchAt).toBeGreaterThanOrEqual(CHARGE.strike - 1e-9)
			expect(last.time - launchAt).toBeLessThan(CHARGE.strike + TICK * 2)
			for _, strike in w.strikes do
				expect(strike.attack.id).toBe("Charge")
				expect((strike.origin - crouchPosition).Magnitude).toBeLessThan(1e-6)
				expect(strike.facing.Z).toBeCloseTo(-1, 1e-6)
			end
			-- By the last stretch the swept line reaches its end, and the body has run it.
			expect(last.options.span.to).toBeGreaterThanOrEqual(CHARGE.reach)
			local atLast = w.goals[#w.goals]
			expect(atLast ~= nil).toBe(true)
			expect(Brain.horizontalDistance(w.position, crouchPosition)).toBeGreaterThanOrEqual(CHARGE.reach - 1e-3)
		end
	)

	it(
		"the rush strikes by contact: the launch sweeps the body, each tick the stretch it swept, never past 0.5 s (D-166)",
		function()
			local FRONT, BACK = 5.6, 3.3
			local w = world({
				extents = function()
					return FRONT, BACK
				end,
			})
			w.players = { player(1, 0, -20) }
			w.stepUntil(function()
				return w.phase() == "Strike"
			end, 2)
			local launchAt = w.time - w.brain:phaseElapsed()
			local crouchPosition = w.telegraphs[1].origin
			-- The launch tick already resolved the body where it crouched.
			expect(#w.strikes).toBe(1)
			expect(w.strikes[1].time).toBeCloseTo(launchAt, 1e-9)
			expect(w.strikes[1].options.span.from).toBeCloseTo(-BACK, 1e-9)
			expect(w.strikes[1].options.span.to).toBeCloseTo(FRONT, 1e-9)
			w.stepUntil(function()
				return w.phase() ~= "Strike"
			end, 2)
			local speed = AI.rushSpeed(CHARGE)
			local resolved = w.strikes[1].options.resolved
			expect(typeof(resolved)).toBe("table")
			local previous = 0
			for index, strike in w.strikes do
				local elapsed = math.min(strike.time - launchAt, CHARGE.strike)
				expect(strike.time - launchAt).toBeLessThan(CHARGE.strike + TICK - 1e-9) -- never a stretch after the strike's tick
				expect(strike.options.resolved).toBe(resolved) -- one verdict per target for the whole rush
				expect((strike.origin - crouchPosition).Magnitude).toBeLessThan(1e-6)
				if index > 1 then
					-- From where the body's back was on the previous tick to where its front is now.
					expect(strike.options.span.from).toBeCloseTo(speed * previous - BACK, 1e-6)
					expect(strike.options.span.to).toBeCloseTo(speed * elapsed + FRONT, 1e-6)
				end
				previous = elapsed
			end
			expect(previous).toBeCloseTo(CHARGE.strike, 1e-9)
			expect(w.strikes[#w.strikes].options.span.to).toBeCloseTo(speed * CHARGE.strike + FRONT, 1e-6)
		end
	)

	it("the rush moves straight at the run's end, never along a path; the chase walks as usual (D-183)", function()
		local w = world()
		w.players = { player(1, 0, -20) }
		expect(w.stepUntil(function()
			return w.phase() == "Recover"
		end, 4)).toBe(true)
		local rushMoves, chaseMoves = 0, 0
		for _, goal in w.goals do
			if goal.phase == "Strike" then
				rushMoves += 1
				expect(goal.direct).toBe(true)
			else
				chaseMoves += 1
				expect(goal.direct).never.toBe(true)
			end
		end
		expect(rushMoves).toBeGreaterThan(0)
		expect(chaseMoves).toBeGreaterThan(0)
	end)

	it("a jammed body's line ends at its snout: the stretches keep up with the body, not the clock (D-195)", function()
		local FRONT, BACK = 5.6, 3.3
		local function run(blocked: boolean): ({ any }, any, { any }, any)
			local w = world({
				extents = function()
					return FRONT, BACK
				end,
			})
			local rushes, ends = {}, {}
			w.context.rushStarted = function(rush)
				table.insert(rushes, rush)
			end
			w.context.rushEnded = function(_rush, reason, distance)
				table.insert(ends, { time = w.time, reason = reason, distance = distance })
			end
			w.players = { player(1, 0, -20) }
			w.stepUntil(function()
				return w.phase() == "WindUp"
			end, 2)
			w.blocked = blocked
			w.stepUntil(function()
				return w.phase() == "Recover"
			end, 3)
			local spans = {}
			for _, strike in w.strikes do
				table.insert(
					spans,
					{ time = strike.time, from = strike.options.span.from, to = strike.options.span.to }
				)
			end
			return spans, rushes[1], ends, w
		end
		local speed = AI.rushSpeed(CHARGE)
		local free, _, freeEnds = run(false)
		expect(#freeEnds).toBe(1)
		expect(freeEnds[1].reason).toBe("Done")
		expect(free[#free].to).toBeCloseTo(speed * CHARGE.strike + FRONT, 1e-6) -- a free run keeps the clock
		local jammed, rush, ends, w = run(true)
		expect(Brain.horizontalDistance(w.position, w.telegraphs[1].origin)).toBeLessThan(1e-6) -- it never moved
		-- The launch resolves the body where it crouched, as a free run does.
		expect(jammed[1].time).toBeCloseTo(free[1].time, 1e-9)
		expect(jammed[1].from).toBeCloseTo(free[1].from, 1e-9)
		expect(jammed[1].to).toBeCloseTo(free[1].to, 1e-9)
		-- Reported Jammed first, where it stood (the run's end follows when its time is up); no stretch
		-- reaches further than its snout plus the frame it started late and keepUpStuds, and nothing
		-- resolves after the report.
		expect(#ends).toBe(2)
		expect(ends[1].reason).toBe("Jammed")
		expect(ends[2].reason).toBe("Done")
		expect(ends[1].distance).toBeCloseTo(0, 1e-9)
		local late = speed * (rush.bodyStartedAt - rush.startedAt)
		for _, span in jammed do
			expect(span.to).toBeLessThanOrEqual(ends[1].distance + FRONT + late + tuning.keepUpStuds + 1e-9)
			expect(span.to).toBeGreaterThan(span.from)
			expect(span.time).toBeLessThanOrEqual(ends[1].time + 1e-9)
		end
	end)

	it(
		"once jammed the line is over: a body shoved on down the line after the report hits nothing more (D-195)",
		function()
			local FRONT, BACK = 5.6, 3.3
			local w = world({
				extents = function()
					return FRONT, BACK
				end,
			})
			local jammedAt: number? = nil
			w.context.rushEnded = function(_rush, reason)
				if reason == "Jammed" then
					jammedAt = w.time
				end
			end
			w.players = { player(1, 0, -20) }
			w.stepUntil(function()
				return w.phase() == "WindUp"
			end, 2)
			w.blocked = true
			w.stepUntil(function()
				return jammedAt ~= nil
			end, 2)
			local count = #w.strikes
			w.position += w.facing * 6 -- something shoves the stopped body on
			w.stepUntil(function()
				return w.phase() == "Recover"
			end, 3)
			expect(#w.strikes).toBe(count)
		end
	)

	it("a body held back short of a jam leaves no gap: each stretch starts where the last one ended (D-195)", function()
		-- A short body, so the line it keeps up with falls behind the clock's back while it is held.
		local FRONT, BACK = 0.5, 0.5
		local w = world({
			extents = function()
				return FRONT, BACK
			end,
		})
		local ends = {}
		w.context.rushEnded = function(_rush, reason)
			table.insert(ends, reason)
		end
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.phase() == "Strike"
		end, 2)
		local launchAt = w.time - w.brain:phaseElapsed()
		w.blocked = true
		w.step(2)
		w.blocked = false
		w.stepUntil(function()
			return w.phase() == "Recover"
		end, 3)
		expect(ends).toEqual({ "Done" }) -- held, never jammed
		local speed = AI.rushSpeed(CHARGE)
		local behind = false
		for index, strike in w.strikes do
			local span = strike.options.span
			expect(span.to).toBeGreaterThan(span.from)
			if index > 1 then
				expect(span.from).toBeLessThanOrEqual(w.strikes[index - 1].options.span.to + 1e-9)
			end
			local clock = speed * math.min(strike.time - launchAt, CHARGE.strike) + FRONT
			behind = behind or span.to < clock - 1e-6
		end
		expect(behind).toBe(true) -- the line did wait for the body
	end)

	it("a wall ahead of the root ends the line at its face: nothing behind it is reached (D-197)", function()
		-- Only the root collides, so a body held at a wall still has its snout FRONT - ROOT_HALF past
		-- the face; the line stops where the world stops the root, and still reaches the face.
		local FRONT, BACK, ROOT_HALF, FACE = 5.6, 3.3, 2.5, 8
		local w = world({
			extents = function()
				return FRONT, BACK
			end,
		})
		local casts = {}
		w.context.worldAhead = function(direction: Vector3, distance: number): number?
			local along = -w.position.Z -- the line runs down -Z from the origin
			table.insert(casts, { direction = direction, distance = distance })
			local gap = FACE - along
			return if gap >= 0 and gap <= distance then gap else nil
		end
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.phase() == "Strike"
		end, 2)
		local guard = 0
		while w.phase() ~= "Recover" and guard < 200 do
			w.step(1)
			if -w.position.Z > FACE - ROOT_HALF then
				w.position = Vector3.new(w.position.X, w.position.Y, -(FACE - ROOT_HALF)) -- held at the face
			end
			guard += 1
		end
		expect(#casts).toBeGreaterThan(0)
		for _, cast in casts do
			expect(cast.direction:Dot(FORWARD)).toBeCloseTo(1, 1e-6)
			expect(cast.distance).toBeGreaterThan(0)
		end
		local furthest = -math.huge
		for _, strike in w.strikes do
			furthest = math.max(furthest, strike.options.span.to)
			expect(strike.options.span.to).toBeGreaterThan(strike.options.span.from)
		end
		expect(furthest).toBeLessThanOrEqual(FACE + 1e-9)
		expect(furthest).toBeGreaterThan(FACE - 1e-6) -- everything up to the face resolved
	end)

	-- A rush at a wall whose face stands `face` studs down the line (D-202): the world cast sees the face
	-- while `seen()` says so, and the body is held with its root's front at the face. Steps to the
	-- recovery; returns the world, what the rush reported (time, reason, distance) and the stretches.
	type WallOptions = {
		seen: ((ends: { any }) -> boolean)?,
		hold: boolean?,
		ground: boolean?, -- the cast names the face ground the root climbs (a ramp's, D-204)
		onStrike: ((w: any, span: any) -> ())?,
	}
	local function wallRun(face: number, options: WallOptions?): (any, { any }, { any })
		local opts: WallOptions = options or {}
		local FRONT, BACK, ROOT_HALF = 5.6, 3.3, 2.5
		local w = world({
			extents = function()
				return FRONT, BACK
			end,
		})
		local seen = opts.seen
		local ends = {}
		w.context.worldAhead = function(_direction: Vector3, distance: number): (number?, boolean?)
			if seen ~= nil and not seen(ends) then
				return nil
			end
			local gap = face - -w.position.Z -- the line runs down -Z from the origin
			if gap >= 0 and gap <= distance then
				return gap, opts.ground == true
			end
			return nil
		end
		w.context.rootReach = function(direction: Vector3): number
			return math.abs(direction.Z) * ROOT_HALF
		end
		-- Each report with where the root stood and how many MoveTo goals had gone out by then.
		w.context.rushEnded = function(_rush, reason, distance)
			table.insert(
				ends,
				{ time = w.time, reason = reason, distance = distance, at = -w.position.Z, goals = #w.goals }
			)
		end
		local spans = {}
		local strike = w.context.strike
		w.context.strike = function(attack, origin, facing, strikeOptions)
			strike(attack, origin, facing, strikeOptions)
			local span = { time = w.time, from = strikeOptions.span.from, to = strikeOptions.span.to }
			table.insert(spans, span)
			if opts.onStrike ~= nil then
				opts.onStrike(w, span)
			end
		end
		w.players = { player(1, 0, -20) }
		w.stepUntil(function()
			return w.phase() == "WindUp"
		end, 2)
		local guard = 0
		while w.phase() ~= "Recover" and w.phase() ~= "Interrupted" and guard < 200 do
			w.step(1)
			if opts.hold ~= false and -w.position.Z > face - ROOT_HALF then
				w.position = Vector3.new(w.position.X, w.position.Y, -(face - ROOT_HALF)) -- held at the face
			end
			guard += 1
		end
		return w, ends, spans
	end

	it("ground the root climbs caps the line while ahead of it but never ends the rush (D-204)", function()
		-- Faces on the line, and in the overshoot the run looks ahead to once the line has resolved.
		for _, face in { 6, 8, 10, 18, 21 } do
			local _, ends, spans = wallRun(face, { ground = true, hold = false })
			-- The line runs on once the body has climbed past the face; the run is over only when its
			-- time has run.
			if face < 12 then
				local farthest = -math.huge
				for _, span in spans do
					farthest = math.max(farthest, span.to)
				end
				expect(farthest).toBeGreaterThan(face + 1)
			end
			expect(#ends).toBe(1)
			expect(ends[1].reason).toBe("Done")
		end
	end)

	it(
		"a stretch the world caps ends the rush at once (D-202, D-208): Wall with the root's stop at the face, sent no further",
		function()
			local ROOT_HALF = 2.5
			for _, face in { 6, 8, 10 } do
				local w, ends, spans = wallRun(face)
				-- The first stretch the face capped.
				local cappedAt: number? = nil
				for _, span in spans do
					expect(span.to).toBeLessThanOrEqual(face + 1e-9)
					if cappedAt == nil and span.to >= face - 1e-9 then
						cappedAt = span.time
					end
				end
				expect(cappedAt).never.toBeNil()
				-- Reported as soon as the cast sees the face (lookAheadStuds ahead of the clock, so no later
				-- than that tick), with the root standing its own reach short of the face (no body profile to
				-- judge: the root's box is the body). The line still resolves on the clock up to the face,
				-- where the drawn snout meets it, and nothing after; with no daze hook the run still waits
				-- out its time (Done).
				expect(#ends).toBe(2)
				expect(ends[1].reason).toBe("Wall")
				expect(ends[1].time).toBeLessThanOrEqual((cappedAt :: number) + 1e-9)
				expect(ends[1].distance).toBeCloseTo(face - ROOT_HALF, 1e-9)
				expect(ends[2].reason).toBe("Done")
				for _, span in spans do
					expect(span.time).toBeLessThanOrEqual((cappedAt :: number) + 1e-9)
				end
				-- The body was told before its root reached the face, sent straight to that stop and never
				-- past it: no goal after the report reaches further down the line.
				local stop = w.telegraphs[1].origin + FORWARD * (face - ROOT_HALF)
				expect(ends[1].at).toBeLessThan(face - ROOT_HALF - 1e-6)
				local sent = 0
				for index = ends[1].goals + 1, #w.goals do
					local goal = w.goals[index]
					if goal.phase == "Strike" then
						sent += 1
						expect((goal.goal - stop).Magnitude).toBeLessThan(1e-6)
						expect(goal.direct).toBe(true)
					end
				end
				expect(sent).toBeGreaterThan(0)
				expect(w.moving).toBe(false) -- the recovery stopped it there
				expect(Brain.horizontalDistance(w.position, stop)).toBeLessThan(1e-6)
			end
		end
	)

	it("the root is told before it meets the face: never held at the wall unreported (D-202)", function()
		local ROOT_HALF = 2.5
		for _, face in { 6, 8, 10 } do
			local reportedAt: number? = nil
			local heldBefore = false
			local w = world({
				extents = function()
					return 5.6, 3.3
				end,
			})
			w.context.worldAhead = function(_direction: Vector3, distance: number): number?
				local gap = face - -w.position.Z
				return if gap >= 0 and gap <= distance then gap else nil
			end
			w.context.rootReach = function(): number
				return ROOT_HALF
			end
			w.context.rushEnded = function(_rush, reason)
				if reason == "Wall" and reportedAt == nil then
					reportedAt = w.time
				end
			end
			w.players = { player(1, 0, -20) }
			w.stepUntil(function()
				return w.phase() == "Strike"
			end, 2)
			while w.phase() == "Strike" do
				-- Before the brain's tick: is the root already pressed at the face?
				if reportedAt == nil and -w.position.Z >= face - ROOT_HALF - 1e-9 then
					heldBefore = true
				end
				w.step(1)
				if -w.position.Z > face - ROOT_HALF then
					w.position = Vector3.new(w.position.X, w.position.Y, -(face - ROOT_HALF))
				end
			end
			expect(reportedAt).never.toBeNil()
			expect(heldBefore).toBe(false)
		end
	end)

	it("a wall right in front of the crouch ends the rush on its launch (D-202)", function()
		local ROOT_HALF = 2.5
		-- The root can go half a stud, or not at all (pressed against the face).
		for _, room in { 0.5, 0 } do
			local face = ROOT_HALF + room
			local w, ends, spans = wallRun(face)
			local launchAt = spans[1].time
			expect(ends[1].reason).toBe("Wall")
			expect(ends[1].time).toBeCloseTo(launchAt, 1e-9)
			expect(ends[1].distance).toBeCloseTo(room, 1e-9)
			expect(#spans).toBe(1) -- the launch's own stretch, up to the face
			expect(spans[1].to).toBeCloseTo(face, 1e-9)
			expect(Brain.horizontalDistance(w.position, w.telegraphs[1].origin)).toBeLessThan(room + 1e-6)
		end
	end)

	it(
		"once a wall ended it the rush is over: the face gone, the body goes no further and nothing resolves past it",
		function()
			local ROOT_HALF = 2.5
			local face = 10
			local w, ends, spans = wallRun(face, {
				seen = function(ends: { any }): boolean
					return #ends == 0 -- a door that opens on the report
				end,
				hold = false, -- and nothing holds the body after it
			})
			expect(ends[1].reason).toBe("Wall")
			-- The slam stands (D-208): the line resolves on the clock up to the face it saw, never past it.
			for _, span in spans do
				expect(span.to).toBeLessThanOrEqual(face + 1e-9)
			end
			expect(-w.position.Z).toBeCloseTo(face - ROOT_HALF, 1e-6)
		end
	)

	it("a wall in the overshoot, after the line resolved, ends it at once too, hits unchanged (D-202)", function()
		local ROOT_HALF = 2.5
		local length = CHARGE.reach + tuning.overshoot
		local face = length -- the root's stop, 2.5 short of the run's end
		local free = select(3, wallRun(1000))
		local w, ends, spans = wallRun(face)
		expect(ends[1].reason).toBe("Wall")
		expect(ends[1].distance).toBeCloseTo(face - ROOT_HALF, 1e-9)
		-- Told before the root got there, and sent no further than its stop.
		expect(ends[1].at).toBeLessThan(face - ROOT_HALF - 1e-6)
		local stop = w.telegraphs[1].origin + FORWARD * (face - ROOT_HALF)
		for index = ends[1].goals + 1, #w.goals do
			local goal = w.goals[index]
			if goal.phase == "Strike" then
				expect((goal.goal - stop).Magnitude).toBeLessThan(1e-6)
			end
		end
		-- The line resolved by the strike beat exactly as a free run's.
		expect(#spans).toBe(#free)
		for index, span in spans do
			expect(span.time).toBeCloseTo(free[index].time, 1e-9)
			expect(span.from).toBeCloseTo(free[index].from, 1e-9)
			expect(span.to).toBeCloseTo(free[index].to, 1e-9)
		end
	end)

	it(
		"a parry on the stretch the world capped tells Interrupted after the Wall, never Jammed (D-202, D-210)",
		function()
			local face = 8
			local _, ends = wallRun(face, {
				onStrike = function(w, span)
					if span.to >= face - 1e-9 and w.brain:getPhase() == "Strike" then
						w.brain:interrupt("Stagger", 1.0) -- the parry staggers the boar inside its strike
					end
				end,
			})
			-- The slam is told first; the parry's stop is told after it, so every client hands the body
			-- back where the server holds it (D-210).
			expect(#ends).toBe(2)
			expect(ends[1].reason).toBe("Wall")
			expect(ends[2].reason).toBe("Interrupted")
			expect(ends[2].distance).toBeLessThanOrEqual(ends[1].distance + 1e-9)
		end
	)

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
