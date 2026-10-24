--!strict
--[[
	An enemy's attack on the server's beat (D-172, item 2) and its flinch during the attack (D-173,
	item 3), through the real path: a RigBuilder Kobold posed by a real Choreo animator at 60 fps,
	the remotes through the real Replication, the telegraph through the real Telegraphs.

	The server is played by a small model of Brain.pauseAttack: the Overhead winds up at server
	time START and resolves its strike at START + windUp + strike plus every pause the player's
	hits add (a hit holds the attack for its hit-stop, freezes overlap, at most
	ai.hitStop.maxPausePerAttack an attack, nothing once it resolved). The local blade touches the
	kobold at client times; the server resolves each hit `latency` later and its HitConfirmed comes
	back `latency` after that, carrying the pause it added (attackPause). The clip's chop lands
	where its clip time reaches the server's resolve beat (windUp + strike); it must land within a
	frame or two of the server's resolve, the telegraph must end with the server's wind-up, and
	the rig must never hold longer than the hits' own hit-stops.
]]

local function frameSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
Harness.stubService(
	"RunService",
	{ RenderStepped = frameSignal(), Heartbeat = frameSignal(), PreSimulation = frameSignal() }
)

local Choreo = Harness.load("src/client/choreo/Choreo")
local Mixer = Harness.load("src/client/choreo/Mixer")
local Replication = Harness.load("src/client/controllers/Replication")
local Telegraphs = Harness.load("src/client/fx/Telegraphs")
local FxEngine = Harness.load("src/client/fx/Engine")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Enemies = Harness.load("src/shared/data/enemies")
local AI = Harness.load("src/shared/data/ai")
local Combat = Harness.load("src/shared/data/combat")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")

local FRAME = 1 / 60
local KOBOLD = Enemies.byId("KoboldAxeman")
local OVERHEAD = KOBOLD.attacks[1]
local CLIP_ID = "enemy/" .. KOBOLD.skin .. "/" .. OVERHEAD.clip
local CLIP = ClipLibrary.get(CLIP_ID)
local RESOLVE = OVERHEAD.windUp + OVERHEAD.strike -- the server's strike beat (clip time of the chop)
local MARK = ClipSampler.hitWindows(CLIP)[1].open -- the beat is kept up to here
local CAP = AI.hitStop.maxPausePerAttack
local START = 20 -- the server's wind-up start (server clock = client clock here)
local SECONDS_PER_FRAME = ChoreoData.frameSeconds

local clock = 0
local function now(): number
	return clock
end
Choreo.configure({
	now = now,
	cameraPosition = function()
		return Vector3.zero
	end,
})

local function recorder(calls: { any }, name: string): any
	return setmetatable({}, {
		__index = function(_self: any, key: string): any
			return function(...: any): any
				table.insert(calls, { module = name, fn = key, args = { ... } })
				return nil
			end
		end,
	})
end

-- ---------------------------------------------------------------------------------------------
-- The Mixer's beat (unit)
-- ---------------------------------------------------------------------------------------------

describe("Mixer keepBeat / shiftBeat (D-172)", function()
	it("repays a hold by the mark at one rate, never freezing twice", function()
		local mixer = Mixer.new()
		local handle = mixer:play(CLIP)
		mixer:keepBeat(handle, MARK, 0)
		local elapsed = 0
		for _ = 1, 12 do
			mixer:step(FRAME)
			elapsed += FRAME
		end
		mixer:hitStop(3)
		local frozen = 0
		local last = handle.time
		while handle.time < MARK do
			mixer:step(FRAME)
			elapsed += FRAME
			if handle.time == last then
				frozen += 1
			end
			last = handle.time
		end
		expect(frozen).toBe(3) -- the hit-stop, once
		-- The mark on the clip's own clock: what the hold took, the clip made up.
		expect(math.abs(elapsed - MARK) <= FRAME + 1e-9).toBe(true)
		mixer:step(FRAME)
		expect(mixer:beatOwed(handle)).toBe(nil) -- past the mark the strike is its own
	end)

	it("a pause the server gave is not repaid: the mark moves by it", function()
		local mixer = Mixer.new()
		local handle = mixer:play(CLIP)
		mixer:keepBeat(handle, MARK, 0)
		local elapsed = 0
		for _ = 1, 12 do
			mixer:step(FRAME)
			elapsed += FRAME
		end
		mixer:hitStop(3)
		mixer:shiftBeat(handle, 3 * SECONDS_PER_FRAME)
		while handle.time < MARK do
			mixer:step(FRAME)
			elapsed += FRAME
		end
		expect(math.abs(elapsed - (MARK + 3 * SECONDS_PER_FRAME)) <= FRAME + 1e-9).toBe(true)
	end)

	it("never runs faster than maxRate nor slower than minRate", function()
		local mixer = Mixer.new()
		local handle = mixer:play(CLIP)
		-- Behind by as much as the mark is away: even the fastest rate cannot even it in time.
		mixer:keepBeat(handle, MARK, MARK)
		local last = handle.time
		mixer:step(FRAME)
		expect(handle.time - last).toBeCloseTo(FRAME * ChoreoData.enemy.beat.maxRate, 1e-9)
		-- Then far ahead (a pause bigger than the way left): the slowest.
		mixer:shiftBeat(handle, 3 * MARK)
		last = handle.time
		mixer:step(FRAME)
		expect(handle.time - last).toBeCloseTo(FRAME * ChoreoData.enemy.beat.minRate, 1e-9)
	end)

	it("keeps nothing past the mark, and a handle keeping no beat steps as before", function()
		local mixer = Mixer.new()
		local handle = mixer:play(CLIP)
		handle.time = MARK + 0.01
		mixer:keepBeat(handle, MARK, 0.2)
		expect(mixer:beatOwed(handle)).toBe(nil)
		-- The guard: two mixers, one keeping a balanced beat, step alike.
		local plain, kept = Mixer.new(), Mixer.new()
		local a, b = plain:play(CLIP), kept:play(CLIP)
		kept:keepBeat(b, MARK, 0)
		for frame = 1, 120 do
			if frame == 30 then
				plain:hitStop(3)
				kept:hitStop(3)
				kept:shiftBeat(b, 3 * SECONDS_PER_FRAME) -- the server paused exactly the hold
			end
			plain:step(FRAME)
			kept:step(FRAME)
			expect(b.time).toBeCloseTo(a.time, 1e-9)
		end
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- The real path
-- ---------------------------------------------------------------------------------------------

type Hit = {
	at: number, -- seconds after START the local blade touches the kobold (client clock)
	tier: string?, -- hit-stop tier (Normal)
	rejected: boolean?, -- the server never confirms it
	confirmDelay: number?, -- its HitConfirmed comes this much later than the round trip
	serverFirst: boolean?, -- the server's word comes before this client's blade gets there
	other: boolean?, -- another player's hit (no contact here; only its HitConfirmed)
	flinch: string?, -- the HitConfirmed's staggerDirection
}

type Options = {
	latency: number, -- one way, seconds
	startLatency: number?, -- the Telegraph's and ActionStarted's (default `latency`)
	hits: { Hit }?,
	frames: number?,
	-- The chop strikes the local player: its HitConfirmed comes `latency` after the server's
	-- resolve, plus `late` more, at hit-stop `tier` (D-176).
	strike: { tier: string, late: number? }?,
}

type Run = {
	chopAt: number?, -- client time the clip reached the server's strike beat
	resolveAt: number, -- server time the server resolved the strike
	telegraphEnd: number?, -- client time the telegraph went off
	windUpEnd: number, -- server time the server's wind-up ended
	paused: number, -- the pause the server gave the attack
	held: number, -- frames the kobold's clip stood still before the mark
	holds: number, -- frames of hit-stop the contacts and confirmations asked of the rig
	times: { number }, -- the clip time each frame showed
	clock: { number },
	tips: { Vector3 }, -- the axe head each frame
	animator: any,
	model: Model,
}

-- The axe head: the Weapon part's corner farthest from the right hand.
local function axeTip(model: Model, solved: { [string]: CFrame }): Vector3
	local weapon = model:FindFirstChild("Weapon", true) :: BasePart
	local frame = solved[weapon.Name]
	local hand = solved.RightArm.Position
	local half = weapon.Size / 2
	local best, far = Vector3.zero, -1
	for _, sy in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = frame * Vector3.new(0, sy * half.Y, sz * half.Z)
			local away = (corner - hand).Magnitude
			if away > far then
				best, far = corner, away
			end
		end
	end
	return best
end

local function solve(model: Model, rootFrame: CFrame): { [string]: CFrame }
	local chain = Pose.chain(model)
	local motors = Joints.map(model)
	local solved: { [string]: CFrame } = { [chain.rootName] = rootFrame }
	for _, link in chain.links do
		local motor: any = motors[link.name]
		local transform = if motor ~= nil then motor.Transform else CFrame.identity
		solved[link.part1] = solved[link.part0] * link.c0 * transform * link.c1Inverse
	end
	return solved
end

local function overhead(options: Options): Run
	clock = START - 0.1
	FxEngine.setClock(now)
	local model = RigBuilder.build(KOBOLD.skin)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.new(0, 3, 0)
	root.Position = root.CFrame.Position
	local folder = Instance.new("Folder")
	model.Parent = folder
	local record = {
		id = 7,
		model = model,
		kind = "Enemy",
		defId = KOBOLD.id,
		rig = KOBOLD.skin,
		state = "Art",
		hp = 150,
		maxHp = 190,
	}
	local me = Instance.new("Model")
	local mine = { id = 1, model = me, kind = "Player", state = "Art", weaponId = "TrialistSword" }
	local them = Instance.new("Model")
	local theirs = { id = 2, model = them, kind = "Player", state = "Art", weaponId = "TrialistSword" }
	local quiet = {
		hitStop = function() end,
		pauseRemaining = function(): number
			return 0
		end,
		play = function() end,
	}
	local calls: { any } = {}
	local heartbeat: ((dt: number) -> ())? = nil
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == 7 then record elseif id == 1 then mine elseif id == 2 then theirs else nil
			end,
		},
		localId = function(): number?
			return 1
		end,
		locomotion = recorder(calls, "locomotion"),
		choreo = {
			get = function(target: any): any
				return if target == me or target == them then quiet else Choreo.get(target)
			end,
		},
		clipLibrary = ClipLibrary,
		trails = recorder(calls, "trails"),
		smear = recorder(calls, "smear"),
		shatter = recorder(calls, "shatter"),
		sparks = recorder(calls, "sparks"),
		telegraphs = Telegraphs,
		outline = recorder(calls, "outline"),
		switchRing = recorder(calls, "switchRing"),
		digits = recorder(calls, "digits"),
		hud = recorder(calls, "hud"),
		systemLine = recorder(calls, "systemLine"),
		sfx = recorder(calls, "sfx"),
		impact = recorder(calls, "impact"),
		camera = recorder(calls, "camera"),
		weaponCategory = function(): string
			return "OneHandedSword"
		end,
		trailToken = function(): string
			return "TrailCyanWhite"
		end,
		positionOf = function(): Vector3
			return Vector3.zero
		end,
		schedule = function() end,
		now = now,
		serverNow = now,
		onHeartbeat = function(fn: (dt: number) -> ())
			heartbeat = fn
		end,
	} :: any)
	local animator = Choreo.get(model)
	animator:step(FRAME)

	-- The server (Brain.pauseAttack): the strike resolves at `resolveAt`, pushed back by each pause.
	local server =
		{ pauseEndsAt = -math.huge, paused = 0, resolveAt = START + RESOLVE, windUpEnd = START + OVERHEAD.windUp }
	local function serverHit(at: number, seconds: number): number?
		if at >= server.resolveAt then
			return nil -- resolved: nothing to pause
		end
		local freezeEnd = math.max(server.pauseEndsAt, at)
		local wanted = math.max(0, at + seconds - freezeEnd)
		local added = math.min(wanted, math.max(0, CAP - server.paused))
		if added <= 0 then
			return 0
		end
		server.paused += added
		server.pauseEndsAt = freezeEnd + added
		server.resolveAt += added
		if at < server.windUpEnd then
			server.windUpEnd += added
		end
		return added
	end

	type Message = { at: number, name: string, payload: any, sent: boolean?, contact: any? }
	local messages: { Message } = {}
	local startLatency = options.startLatency or options.latency
	table.insert(messages, {
		at = START + startLatency,
		name = "Telegraph",
		payload = {
			entityId = 7,
			attackId = OVERHEAD.id,
			kind = OVERHEAD.telegraph,
			windUp = OVERHEAD.windUp,
			serverTime = START,
			origin = { 0, 3, 0 },
			facing = { 0, 0, -1 },
		},
	})
	table.insert(messages, {
		at = START + startLatency,
		name = "ActionStarted",
		payload = { entityId = 7, clipId = CLIP_ID, serverTime = START, facing = { 0, 0, -1 } },
	})
	local holds = 0
	for index, hit in options.hits or {} do
		local tier = hit.tier or "Normal"
		local frames = Combat.hitStopFrames[tier]
		local contactAt = START + hit.at
		-- When the server resolves it: after the blade got here (the request's way), or before.
		local serverAt = if hit.serverFirst
			then contactAt - options.latency - 2 * FRAME
			elseif hit.other then contactAt - options.latency
			else contactAt + options.latency
		local payload = {
			attackerId = if hit.other then 2 else 1,
			targetId = 7,
			damage = 10,
			crit = false,
			gaugeDamage = 4,
			killed = false,
			broke = false,
			hitStop = tier,
			position = { 0, 4, -1 },
			parried = false,
			guarded = false,
			reflected = false,
			hitIndex = index,
			swing = if hit.other then nil else index,
			staggerDirection = hit.flinch,
		}
		if not hit.rejected then
			table.insert(
				messages,
				{
					at = serverAt + options.latency + (hit.confirmDelay or 0),
					name = "HitConfirmed",
					payload = payload,
					serverAt = serverAt,
					frames = frames,
				} :: any
			)
		end
		if not hit.other then
			table.insert(
				messages,
				{
					at = contactAt,
					name = "contact",
					payload = nil,
					contact = {
						targetId = 7,
						windowIndex = index,
						artId = nil,
						swing = index,
						tier = tier,
						position = Vector3.new(0, 4, -1),
					},
					serverAt = if hit.rejected then nil else serverAt,
					frames = frames,
				} :: any
			)
		end
	end
	-- The server's pauses in the order it resolves the hits.
	local resolved: { any } = {}
	for _, message in messages do
		local m: any = message
		if m.name == "HitConfirmed" then
			table.insert(resolved, m)
		end
	end
	table.sort(resolved, function(a, b)
		return a.serverAt < b.serverAt
	end)
	for _, m in resolved do
		m.payload.attackPause = serverHit(m.serverAt, m.frames * SECONDS_PER_FRAME)
	end
	local strike = options.strike
	if strike ~= nil then
		table.insert(messages, {
			at = server.resolveAt + options.latency + (strike.late or 0),
			name = "HitConfirmed",
			payload = {
				attackerId = 7,
				targetId = 1,
				damage = 30,
				crit = false,
				gaugeDamage = 0,
				killed = strike.tier == "Kill",
				broke = false,
				hitStop = strike.tier,
				position = { 0, 2, -3 },
				parried = false,
				guarded = false,
				reflected = false,
				hitIndex = 1,
			},
		})
	end
	table.sort(messages, function(a, b)
		return a.at < b.at
	end)

	local run: Run = {
		chopAt = nil,
		resolveAt = server.resolveAt,
		telegraphEnd = nil,
		windUpEnd = server.windUpEnd,
		paused = server.paused,
		held = 0,
		holds = 0,
		times = {},
		clock = {},
		tips = {},
		animator = animator,
		model = model,
	}
	local handle: any = nil
	local showing = false
	local lastTime: number? = nil
	for _ = 1, options.frames or 150 do
		clock += FRAME
		for _, message in messages do
			local m: any = message
			if not m.sent and clock >= m.at - 1e-9 then
				m.sent = true
				if m.name == "contact" then
					-- The predictor asks first: a hit the server already confirmed is not predicted.
					local contact = m.contact
					if not Replication.confirmedAlready(7, contact.windowIndex, nil, contact.swing) then
						Replication.contact(contact)
						holds += m.frames
					end
				else
					if m.name == "HitConfirmed" and m.payload.attackerId == 2 then
						holds += m.frames
					elseif m.name == "HitConfirmed" and m.payload.attackerId == 1 then
						-- A confirmation before the contact holds the rig itself (it played no contact).
						local predicted = false
						for _, other in messages do
							local o: any = other
							if o.name == "contact" and o.sent and o.contact.windowIndex == m.payload.hitIndex then
								predicted = true
							end
						end
						if not predicted then
							holds += m.frames
						end
					end
					Replication.dispatch(m.name, m.payload)
				end
			end
		end
		animator:step(FRAME)
		Telegraphs.step()
		if heartbeat ~= nil then
			heartbeat(FRAME)
		end
		if handle == nil then
			for _, candidate in animator.mixer:handles() do
				if candidate.clipId == CLIP_ID then
					handle = candidate
				end
			end
		end
		local time = if handle ~= nil then handle.time else 0
		if handle ~= nil then
			if lastTime ~= nil and time == lastTime and time < MARK then
				run.held += 1
			end
			if run.chopAt == nil and lastTime ~= nil and time >= RESOLVE then
				-- Where between this frame and the last the clip crossed the beat.
				local u = (RESOLVE - lastTime) / math.max(time - lastTime, 1e-9)
				run.chopAt = clock - FRAME + u * FRAME
			end
			lastTime = time
		end
		local isShowing = Telegraphs.isShowing(model)
		if showing and not isShowing and run.telegraphEnd == nil then
			run.telegraphEnd = clock
		end
		showing = isShowing
		table.insert(run.times, time)
		table.insert(run.clock, clock)
		table.insert(run.tips, axeTip(model, solve(model, root.CFrame)))
	end
	run.holds = holds
	Telegraphs.forget(model)
	FxEngine.setClock(nil)
	return run
end

-- The chop lands with the server's resolve, the telegraph ends with its wind-up, and nothing
-- freezes beyond the hits' own hit-stops.
local function onBeat(run: Run, frames: number?)
	local slack = (frames or 2) * FRAME + 1e-6
	expect(run.chopAt ~= nil).toBe(true)
	expect(math.abs((run.chopAt :: number) - run.resolveAt) <= slack).toBe(true)
	expect(run.telegraphEnd ~= nil).toBe(true)
	expect(math.abs((run.telegraphEnd :: number) - run.windUpEnd) <= FRAME + 1e-6).toBe(true)
	expect(run.held <= run.holds).toBe(true)
end

describe("the Kobold's Overhead keeps the server's beat (D-172, item 2)", function()
	for _, latency in { 0.05, 0.1 } do
		it(("with no hit, the chop lands on the server's resolve (%.2f s each way)"):format(latency), function()
			local run = overhead({ latency = latency })
			expect(run.paused).toBe(0)
			onBeat(run)
			expect(run.held).toBe(0)
			-- Not a frame ahead either: the clip's first step is not a frame early.
			expect(math.abs((run.chopAt :: number) - run.resolveAt) <= 0.5 * FRAME).toBe(true)
		end)

		it(
			("one hit in the wind-up pauses chop and telegraph by its hold (%.2f s each way)"):format(latency),
			function()
				local run = overhead({ latency = latency, hits = { { at = 0.4 } } })
				expect(run.paused).toBeCloseTo(3 * SECONDS_PER_FRAME, 1e-9)
				onBeat(run)
				expect(run.held).toBe(3)
			end
		)

		it(
			("four hits in the wind-up: four holds, the chop that much later (%.2f s each way)"):format(latency),
			function()
				local run = overhead({
					latency = latency,
					hits = { { at = 0.2 }, { at = 0.4 }, { at = 0.6 }, { at = 0.8 } },
				})
				expect(run.paused).toBeCloseTo(4 * 3 * SECONDS_PER_FRAME, 1e-9)
				onBeat(run)
				expect(run.held).toBe(12)
			end
		)

		it(("hits past the per-attack cap hold the rig but not the chop (%.2f s each way)"):format(latency), function()
			local run = overhead({
				latency = latency,
				hits = {
					{ at = 0.1 },
					{ at = 0.25 },
					{ at = 0.4 },
					{ at = 0.55, tier = "Final" },
					{ at = 0.7 },
					{ at = 0.85 },
				},
			})
			expect(run.paused).toBeCloseTo(CAP, 1e-9)
			onBeat(run)
		end)
	end

	it("a contact the server never confirms gives its pause back, and the chop comes on time", function()
		local run = overhead({ latency = 0.05, hits = { { at = 0.1, rejected = true } } })
		expect(run.paused).toBe(0)
		onBeat(run)
		expect(run.held).toBe(3)
	end)

	it("a contact rejected too near the mark to give its pause back in time costs at most its hold", function()
		-- Given back allowanceSeconds after the contact, past the mark: the chop is late by the hold.
		local run = overhead({ latency = 0.05, hits = { { at = 1.0, rejected = true } } })
		expect(Combat.contact.allowanceSeconds > MARK - 1.0).toBe(true)
		local late = (run.chopAt :: number) - run.resolveAt
		expect(late > 0).toBe(true)
		expect(late <= 3 * SECONDS_PER_FRAME + FRAME).toBe(true)
	end)

	it("a confirmation that comes late changes nothing it agrees with", function()
		local run = overhead({ latency = 0.05, hits = { { at = 0.3, confirmDelay = 0.6 } } })
		onBeat(run)
		expect(run.held).toBe(3)
	end)

	it("a confirmation late past the mark still has the chop on the server's beat", function()
		local run = overhead({ latency = 0.05, hits = { { at = 0.9, confirmDelay = 0.5 } } })
		onBeat(run)
	end)

	it("the server's word before the blade: the rig holds once and the contact is not played again", function()
		local run = overhead({ latency = 0.05, hits = { { at = 0.5, serverFirst = true } } })
		onBeat(run)
		expect(run.held).toBe(3)
		expect(run.holds).toBe(3)
	end)

	it("another player's hits hold it when they are heard, and the chop stays on the beat", function()
		local run = overhead({ latency = 0.1, hits = { { at = 0.3, other = true }, { at = 0.6, other = true } } })
		onBeat(run)
		expect(run.held).toBe(6)
	end)

	it("a contact before the attack was heard of: the server's pause still moves the chop", function()
		-- The telegraph and the clip arrive 0.2 s after the wind-up began; the first contact comes
		-- before them (its hold held the idle, not the attack).
		local run = overhead({ latency = 0.2, hits = { { at = 0.1 }, { at = 0.4 } } })
		expect(run.paused).toBeCloseTo(2 * 3 * SECONDS_PER_FRAME, 1e-9)
		onBeat(run)
	end)

	it("an ActionStarted heard late catches up to the beat", function()
		local run = overhead({ latency = 0.05, startLatency = 0.4 })
		onBeat(run)
	end)

	-- The frames the clip stands still from the mark on: frozen, or inside the hold after the chop.
	local function stillsAfterMark(run: Run): (number, number)
		local keys = CLIP.keys
		local holdStart, holdEnd = 0, 0
		for index = 3, #keys do
			if ClipSampler.isStrikeSnap(CLIP, index - 1) and keys[index].easing == "Hold" then
				holdStart, holdEnd = keys[index - 1].time, keys[index].time
			end
		end
		local stills, runs, before = 0, 0, false
		for index = 2, #run.times do
			local a, b = run.times[index - 1], run.times[index]
			local still = a >= MARK and (b == a or (a >= holdStart - 1e-6 and b <= holdEnd + 1e-6))
			if still then
				stills += 1
				if not before then
					runs += 1
				end
			end
			before = still
		end
		return stills, runs
	end

	it("the chop's own hold stands for its strike's hit-stop, whenever the HitConfirmed comes (D-176)", function()
		local holdFrames = 3
		for _, tier in { "Normal", "Kill" } do
			local frames = Combat.hitStopFrames[tier]
			for _, late in { -0.04, -0.02, 0, 0.02, 0.05, 0.1, 0.2 } do
				local run = overhead({ latency = 0.05, strike = { tier = tier, late = late } })
				local stills, runs = stillsAfterMark(run)
				-- One still at the impact as long as the longer of the two, never their sum; a
				-- stronger tier's rest may come apart from the hold once the hold has played.
				expect(math.abs(stills - math.max(frames, holdFrames)) <= 1).toBe(true)
				expect(runs <= (if frames > holdFrames then 2 else 1)).toBe(true)
			end
		end
		-- With no strike the hold is the clip's own, once (two or three repeated frames, as the
		-- frames fall on it).
		local plain = overhead({ latency = 0.05 })
		local stills, runs = stillsAfterMark(plain)
		expect(math.abs(stills - holdFrames) <= 1).toBe(true)
		expect(runs).toBe(1)
	end)

	it("the chop is drawn over two to four frames and its own hold is not doubled by a hit's", function()
		for _, hits in { {}, { { at = 0.4 } } } do
			local run = overhead({ latency = 0.05, hits = hits :: any })
			-- The frames that move the axe head across the snap (1.30 - 1.35 in clip time).
			local moving = 0
			for index = 2, #run.times do
				local a, b = run.times[index - 1], run.times[index]
				if b > MARK and a < RESOLVE and (run.tips[index] - run.tips[index - 1]).Magnitude > 1e-3 then
					moving += 1
				end
			end
			expect(moving >= 2 and moving <= 4).toBe(true)
			-- Past the mark nothing holds but the clip's own authored hold.
			local stills = 0
			for index = 2, #run.times do
				if run.times[index - 1] >= MARK and run.times[index] == run.times[index - 1] then
					stills += 1
				end
			end
			expect(stills).toBe(0)
		end
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- Item 3: a flinch during the attack
-- ---------------------------------------------------------------------------------------------

-- How far a flinch moves the axe head along the chop (from where the plain attack has it at the
-- mark to where it has it at the strike beat) at most, before the chop: a false chop moves it there.
local function alongChop(with: Run, plain: Run): number
	local from: Vector3? = nil
	local to: Vector3? = nil
	for index = 2, #plain.times do
		if from == nil and plain.times[index] >= MARK then
			from = plain.tips[index - 1]
		end
		if to == nil and plain.times[index] >= RESOLVE then
			to = plain.tips[index]
		end
	end
	local chop = ((to :: Vector3) - (from :: Vector3)).Unit
	local worst = 0
	for index = 1, math.min(#with.tips, #plain.tips) do
		if plain.times[index] < MARK then
			worst = math.max(worst, (with.tips[index] - plain.tips[index]):Dot(chop))
		end
	end
	return worst
end

describe("a flinch during the Overhead keeps the axe on the attack (D-173, item 3)", function()
	it("a hit late in the wind-up flinches the body, never the axe into a false chop", function()
		-- Hits at 1.0 and 1.2 s: their flinch plays over the last of the wind-up, up to the chop
		-- (the review's dip at +1.32 s). Without the attack's weights the Front flinch alone moved
		-- the axe head 1.8 studs down the chop in two frames.
		for _, at in { 1.0, 1.2 } do
			for _, direction in { "Front", "Back", "Left", "Right" } do
				local plain = overhead({ latency = 0.05, hits = { { at = at } } })
				local flinched = overhead({ latency = 0.05, hits = { { at = at, flinch = direction } } })
				expect(alongChop(flinched, plain) < 0.25).toBe(true)
			end
		end
	end)

	it("outside an attack a flinch plays at full weight, as before", function()
		local mixer = Mixer.new()
		local flinch = ClipLibrary.get("enemy/" .. KOBOLD.skin .. "/FlinchFront")
		local masked = mixer:play(flinch, { mask = ChoreoData.reaction.attackFlinch.Kobold })
		local plainMixer = Mixer.new()
		local plain = plainMixer:play(flinch)
		local a = mixer:step(0.04).offsets
		local b = plainMixer:step(0.04).offsets
		expect(masked.mask ~= nil).toBe(true)
		expect(plain.mask).toBe(nil)
		-- The mask zeroes the weapon arm and scales the root; every other joint is the same.
		expect(a.RightShoulder).toBe(nil)
		expect(a.Weapon).toBe(nil)
		expect(b.RightShoulder ~= nil).toBe(true)
		expect(a.Neck.rot[1]).toBeCloseTo(b.Neck.rot[1], 1e-9)
		expect(a.Root.rot[1]).toBeCloseTo(b.Root.rot[1] * ChoreoData.reaction.attackFlinch.Kobold.Root, 1e-9)
	end)

	it("Replication masks only a flinch that lands before the attack's post-motion", function()
		local during = overhead({ latency = 0.05, hits = { { at = 0.5, flinch = "Front" } }, frames = 50 })
		local masks: { any } = {}
		for _, handle in during.animator.mixer:handles() do
			if string.find(handle.clipId, "Flinch", 1, true) then
				table.insert(masks, handle.mask)
			end
		end
		expect(#masks).toBe(1)
		expect(masks[1]).toBe(ChoreoData.reaction.attackFlinch.Kobold)
		-- After the post-motion begins (and with no attack at all) the flinch is whole.
		local after =
			overhead({ latency = 0.05, hits = { { at = 2.2, flinch = "Front", other = true } }, frames = 150 })
		local whole: { any } = {}
		for _, handle in after.animator.mixer:handles() do
			if string.find(handle.clipId, "Flinch", 1, true) then
				table.insert(whole, handle)
			end
		end
		expect(#whole).toBe(1)
		expect(whole[1].mask).toBe(nil)
	end)
end)
