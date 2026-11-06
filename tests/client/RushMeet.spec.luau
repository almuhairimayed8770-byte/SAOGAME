--!strict
--[[
	A Boar's rush meeting the local player's body (the gate's boar-charge shot, FB1).

	The real path, as tests/client/RushDraw.spec.luau runs it: a RigBuilder Boar posed every 60 fps
	frame by a real Choreo animator, the remotes through the real Replication, its root part played
	as the engine replicates the server's body (`lag` seconds late), every message `latency` seconds
	after the server sent it. The local player stands on the charge's line `distance` studs from the
	crouch point, `across` studs to the line's right: a root part as wide as a player's (its half
	width is the body's radius, HitSweep.bodyRadius).

	The server's sweep reaches the body when the root has run `distance` - radius - front (D-166).
	Its HitConfirmed reaches this client a latency after that frame. The blow shows on the local body
	(the flinch, the white flash, the hit's moment) on the frame the drawn snout gets there (D-258 for
	a rush), not when the word comes. The drawn body then shoulders past the body (RushDraw's pass):
	its snout still meets it on that frame, nothing of it is inside the body once the swing is full,
	and it rests where the server's body stops.
]]

local function frameSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
Harness.stubService("RunService", {
	RenderStepped = frameSignal(),
	Heartbeat = frameSignal(),
	PreSimulation = frameSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
local Replication = Harness.load("src/client/controllers/Replication")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local EnemyService = Harness.load("src/server/services/EnemyService")
local Enemies = Harness.load("src/shared/data/enemies")
local AI = Harness.load("src/shared/data/ai")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Pose = Harness.load("src/shared/choreo/Pose")
local RushWorld = Harness.load("src/shared/choreo/RushWorld")
local Joints = Harness.load("src/shared/choreo/Joints")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local FrameClock = Harness.load("src/client/fx/FrameClock")

local FRAME = 1 / 60
local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]
local SPEED: number = AI.rushSpeed(CHARGE)
local LENGTH: number = CHARGE.reach + AI.archetypes.Charger.overshoot
local PASS = ChoreoData.enemy.rush.pass
local RADIUS = 1 -- the player's root half width (2 x 2 x 1)

local WIND_UP_START = 10
local LAUNCH = WIND_UP_START + CHARGE.windUp
local ORIGIN = Vector3.new(10, 3, 20)
local DIRECTION = Vector3.new(1, 0, -1).Unit
local RIGHT = Vector3.new(-DIRECTION.Z, 0, DIRECTION.X)

local clock = 0
Choreo.configure({
	now = function()
		return clock
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

-- The server's body `t` seconds into the take: at the rush speed from the launch until it stops at
-- `rest` studs down the line (the run's end, or where a slam or a jam stopped it).
local function bodyAt(t: number, rest: number?): CFrame
	local d = math.clamp(SPEED * (t - LAUNCH), 0, rest or LENGTH)
	local position = ORIGIN + DIRECTION * d
	return CFrame.lookAt(position, position + DIRECTION)
end

local function velocityAt(t: number, rest: number?): Vector3
	local d = SPEED * (t - LAUNCH)
	return if d > 0 and d < (rest or LENGTH) then DIRECTION * SPEED else Vector3.zero
end

local function recorder(calls: { any }, name: string): any
	return setmetatable({}, {
		__index = function(_self: any, key: string): any
			return function(...: any): any
				table.insert(calls, { module = name, fn = key, args = { ... }, at = clock })
				return nil
			end
		end,
	})
end

-- Every part's world CFrame from the root part's CFrame and the joints' Transforms (what the engine
-- draws).
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

-- The flat distance from the body's upright axis at `spot` to the nearest of a drawn part's sample
-- points (its corners and the points between them, 3 x 3 x 3).
local function nearest(part: BasePart, frame: CFrame, spot: Vector3): number
	local half = part.Size / 2
	local best = math.huge
	for _, x in { -1, 0, 1 } do
		for _, y in { -1, 0, 1 } do
			for _, z in { -1, 0, 1 } do
				local point = frame * Vector3.new(half.X * x, half.Y * y, half.Z * z)
				local gap = Vector3.new(point.X - spot.X, 0, point.Z - spot.Z).Magnitude
				best = math.min(best, gap)
			end
		end
	end
	return best
end

local SNOUT = { Snout = true, TuskLeft = true, TuskRight = true }

type Frame = {
	t: number, -- server seconds since the launch
	along: number, -- the drawn root down the line
	off: number, -- the drawn root off the line (to its right)
	drawn: Vector3,
	inside: number, -- how deep the drawn body's deepest point is inside the player's body
	snoutGap: number, -- how far the snout's nearest point is outside the player's body
	shown: boolean, -- the blow showed on the local body by this frame (moment, flash or flinch)
	word: boolean, -- its HitConfirmed had come by this frame
}

type Options = {
	latency: number,
	lag: number,
	distance: number,
	across: number?,
	defence: string?, -- the local fighter's state (default Idle)
	confirm: boolean?, -- the server confirms the blow (default true)
	frames: number?,
	-- The server's RushEnded (a slam's or a jam's stop `distance` studs down the line, sent
	-- `after` seconds after the launch); the server's body rests there.
	ended: { reason: string, distance: number, after: number }?,
	-- The real FrameClock on the loop's render steps (its start, the rigs' step, its posed mark,
	-- its end), given to Replication as the client's start() does (D-342, D-343).
	frameClock: boolean?,
}

type Run = { frames: { Frame }, front: number, calls: { any }, contactFrame: number?, wordFrame: number? }

local function meet(options: Options): Run
	clock = WIND_UP_START - 0.2
	local model = RigBuilder.build("Boar")
	local front = EnemyService.bodyExtents(model)
	local root = model.PrimaryPart :: BasePart
	root.LocalTransparencyModifier = 0
	local rest = if options.ended ~= nil then options.ended.distance else nil
	local function place()
		local frame = bodyAt(clock - options.lag, rest)
		root.CFrame = frame
		root.Position = frame.Position
		root.AssemblyLinearVelocity = velocityAt(clock - options.lag, rest)
	end
	place()
	local folder = Instance.new("Folder")
	model.Parent = folder
	local boar = {
		id = 5,
		model = model,
		kind = "Enemy",
		defId = BOAR.id,
		rig = BOAR.skin,
		state = "Idle",
		hp = 100,
		maxHp = 120,
	}
	-- The local player: a root part as wide as a player's, on the charge's line.
	local spot = ORIGIN + DIRECTION * options.distance + RIGHT * (options.across or 0)
	local me = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = Vector3.new(2 * RADIUS, 2, 1)
	body.CFrame = CFrame.lookAt(spot, spot - DIRECTION)
	body.Position = spot
	body.Parent = me
	me.PrimaryPart = body
	local mine = { id = 1, model = me, kind = "Player", rig = "Player", state = "Idle", weaponId = "TrialistSword" }
	local calls: { any } = {}
	local myAnimator = {
		hitStop = function() end,
		pauseRemaining = function(): number
			return 0
		end,
		play = function(_self: any, clipId: string): any
			table.insert(calls, { module = "me", fn = "play", args = { clipId }, at = clock })
			return { clipId = clipId }
		end,
		stop = function() end,
	}
	local clockStart: ((dt: number) -> ())? = nil
	local clockPosed: ((dt: number) -> ())? = nil
	local clockEnd: ((dt: number) -> ())? = nil
	if options.frameClock then
		FrameClock.bind({
			now = function(): number
				return clock
			end,
			onFrameStart = function(fn: any): () -> ()
				clockStart = fn
				return function()
					clockStart = nil
				end
			end,
			onPosed = function(fn: any): () -> ()
				clockPosed = fn
				return function()
					clockPosed = nil
				end
			end,
			onFrameEnd = function(fn: any): () -> ()
				clockEnd = fn
				return function()
					clockEnd = nil
				end
			end,
			onHeartbeat = function(): () -> ()
				return function() end
			end,
		} :: any)
	end
	local frameClock: any = if options.frameClock then FrameClock else {}
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == 5 then boar elseif id == 1 then mine else nil
			end,
			all = function(): { any }
				return { boar, mine }
			end,
		},
		localId = function(): number?
			return 1
		end,
		locomotion = recorder(calls, "locomotion"),
		choreo = {
			get = function(target: any): any
				return if target == me then myAnimator else Choreo.get(target)
			end,
		},
		clipLibrary = ClipLibrary,
		trails = recorder(calls, "trails"),
		smear = recorder(calls, "smear"),
		shatter = recorder(calls, "shatter"),
		sparks = recorder(calls, "sparks"),
		telegraphs = recorder(calls, "telegraphs"),
		outline = recorder(calls, "outline"),
		switchRing = recorder(calls, "switchRing"),
		digits = recorder(calls, "digits"),
		hud = recorder(calls, "hud"),
		systemLine = recorder(calls, "systemLine"),
		sfx = recorder(calls, "sfx"),
		impact = recorder(calls, "impact"),
		camera = recorder(calls, "camera"),
		wallSlam = recorder(calls, "wallSlam"),
		weaponCategory = function(): string
			return "OneHandedSword"
		end,
		trailToken = function(): string
			return "TrailCyanWhite"
		end,
		positionOf = function(target: Instance): Vector3
			return if target == me then spot else root.Position
		end,
		schedule = function() end,
		now = function(): number
			return clock
		end,
		serverNow = function(): number
			return clock
		end,
		localDefence = function(): (string, number?)
			return options.defence or "Idle", nil
		end,
		atPose = frameClock.atPose,
		atStepPose = frameClock.atStepPose,
	} :: any)
	local animator = Choreo.get(model)
	animator:step(FRAME)

	-- The server's sweep reaches the body on its first frame at or after the contact (D-166).
	local contact = math.max(0, options.distance - RADIUS - front) / SPEED
	local hitAt = math.ceil(contact / FRAME - 1e-9) * FRAME
	local messages: { { at: number, name: string, payload: any, sent: boolean? } } = {
		{
			at = WIND_UP_START + options.latency,
			name = "Telegraph",
			payload = {
				entityId = 5,
				attackId = CHARGE.id,
				kind = CHARGE.telegraph,
				windUp = CHARGE.windUp,
				serverTime = WIND_UP_START,
				origin = vec(ORIGIN),
				facing = vec(DIRECTION),
			},
		},
		{
			at = WIND_UP_START + options.latency,
			name = "ActionStarted",
			payload = {
				entityId = 5,
				clipId = "enemy/" .. BOAR.skin .. "/" .. CHARGE.clip,
				serverTime = WIND_UP_START,
				facing = vec(DIRECTION),
			},
		},
		{
			at = LAUNCH + options.latency,
			name = "RushStarted",
			payload = {
				entityId = 5,
				attackId = CHARGE.id,
				serverTime = LAUNCH,
				origin = vec(ORIGIN),
				direction = vec(DIRECTION),
				speed = SPEED,
				duration = LENGTH / SPEED,
			},
		},
	}
	if options.confirm ~= false then
		table.insert(messages, {
			at = LAUNCH + hitAt + options.latency,
			name = "HitConfirmed",
			payload = {
				attackerId = 5,
				targetId = 1,
				damage = 16,
				crit = false,
				gaugeDamage = 0,
				killed = false,
				broke = false,
				hitStop = "Normal",
				position = vec(spot),
				parried = false,
				guarded = false,
				reflected = false,
				hitIndex = 1,
				staggerDirection = "Front",
			},
		})
	end

	local ended = options.ended
	if ended ~= nil then
		local stop = ORIGIN + DIRECTION * ended.distance
		table.insert(messages, {
			at = LAUNCH + ended.after + options.latency,
			name = "RushEnded",
			payload = {
				entityId = 5,
				launchedAt = LAUNCH,
				serverTime = LAUNCH + ended.after,
				distance = ended.distance,
				reason = ended.reason,
				contact = if ended.reason == "Wall" then vec(stop + DIRECTION * front) else nil,
				normal = if ended.reason == "Wall" then vec(-DIRECTION) else nil,
			},
		})
	end

	local parts: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			table.insert(parts, part)
		end
	end
	local run: Run = { frames = {}, front = front, calls = calls, contactFrame = nil, wordFrame = nil }
	local word = false
	for index = 1, options.frames or 110 do
		clock += FRAME
		for _, message in messages do
			if not message.sent and clock >= message.at - 1e-9 then
				message.sent = true
				if message.name == "HitConfirmed" then
					word = true
					run.wordFrame = run.wordFrame or index
				end
				Replication.dispatch(message.name, message.payload)
			end
		end
		place()
		-- The frame's render steps: FrameClock's start, the rigs' (this animator), its posed mark.
		if clockStart ~= nil then
			clockStart(FRAME)
		end
		animator:step(FRAME)
		if clockPosed ~= nil then
			clockPosed(FRAME)
		end
		if clockEnd ~= nil then
			clockEnd(FRAME)
		end
		local offset: CFrame? = (animator :: any).bodyOffset
		local drawn = root.CFrame * (offset or CFrame.identity)
		local solved = solve(model, root.CFrame)
		local inside, snoutGap = 0, math.huge
		for _, part in parts do
			local frame = solved[part.Name]
			if frame ~= nil then
				local gap = nearest(part, frame, spot)
				inside = math.max(inside, RADIUS - gap)
				if SNOUT[part.Name] then
					snoutGap = math.min(snoutGap, gap - RADIUS)
				end
			end
		end
		local shown = false
		for _, call in calls do
			if
				(call.module == "impact" and call.fn == "hit")
				or (call.module == "outline" and call.fn == "flash" and call.args[1] == me)
				or (call.module == "me" and call.fn == "play")
			then
				shown = true
			end
		end
		local rel = drawn.Position - ORIGIN
		local along = rel:Dot(DIRECTION)
		table.insert(run.frames, {
			t = clock - LAUNCH,
			along = along,
			off = rel:Dot(RIGHT),
			drawn = drawn.Position,
			inside = inside,
			snoutGap = snoutGap,
			shown = shown,
			word = word,
		})
		-- The drawn contact: the drawn root has run as far as the server's sweep needs.
		if run.contactFrame == nil and along >= options.distance - RADIUS - front - 1e-4 then
			run.contactFrame = index
		end
	end
	if options.frameClock then
		FrameClock.bind(nil)
	end
	return run
end

local function firstShown(run: Run): number?
	for index, frame in run.frames do
		if frame.shown then
			return index
		end
	end
	return nil
end

-- One frame of the run's own travel, and the most a pass's swing adds to a frame's move.
local FRAME_TRAVEL = SPEED * FRAME

describe("a rush's blow on the local player shows when the drawn snout meets the body (FB1)", function()
	for _, case in
		{
			{ latency = FRAME * 2, lag = 0.25 }, -- Play Solo: the word two frames after the sweep
			{ latency = 0.05, lag = 0.25 },
			{ latency = 0.1, lag = 0.25 },
			{ latency = 0.2, lag = 0.5 },
		}
	do
		it(
			("on the drawn contact frame, before its word (latency %.3f s, root %.2f s late)"):format(
				case.latency,
				case.lag
			),
			function()
				local run = meet({ latency = case.latency, lag = case.lag, distance = 12 })
				expect(run.contactFrame ~= nil).toBe(true)
				expect(run.wordFrame ~= nil).toBe(true)
				expect((run.wordFrame :: number) > (run.contactFrame :: number)).toBe(true)
				-- The blow shows on the frame the drawn root has run to the server's contact.
				expect(firstShown(run)).toBe(run.contactFrame)
				-- Its moment plays once before the word: the flinch from the front, one flash.
				local moments, flashes, flinches = 0, 0, {}
				for _, call in run.calls do
					if call.at < LAUNCH + run.frames[run.wordFrame :: number].t - 1e-9 then
						if call.module == "impact" and call.fn == "hit" then
							moments += 1
						elseif call.module == "outline" and call.fn == "flash" then
							flashes += 1
						elseif call.module == "me" and call.fn == "play" then
							table.insert(flinches, call.args[1])
						end
					end
				end
				expect(moments).toBe(1)
				expect(flashes).toBe(1)
				expect(#flinches).toBe(1)
				expect(string.find(flinches[1], "FlinchFront", 1, true) ~= nil).toBe(true)
			end
		)
	end

	it("leaves a body in a guard, beside the line or past its reach to the word", function()
		local function shownBeforeWord(run: Run): boolean
			local shown = firstShown(run)
			return shown ~= nil and (run.wordFrame == nil or shown < (run.wordFrame :: number))
		end
		expect(shownBeforeWord(meet({ latency = 0.1, lag = 0.25, distance = 12, defence = "Guard" }))).toBe(false)
		expect(shownBeforeWord(meet({ latency = 0.1, lag = 0.25, distance = 12, defence = "Dodge" }))).toBe(false)
		-- Off the line by its half width plus the radius, less the prediction's margin: the word's.
		local margin = AI.strikePrediction.marginStuds
		local beside = 4 / 2 + RADIUS - margin + 0.1
		expect(shownBeforeWord(meet({ latency = 0.1, lag = 0.25, distance = 12, across = beside, confirm = false }))).toBe(
			false
		)
		expect(shownBeforeWord(meet({ latency = 0.1, lag = 0.25, distance = CHARGE.reach + RADIUS, confirm = false }))).toBe(
			false
		)
		-- A blow the server never confirms is taken back (D-258), never left standing.
		local missed = meet({ latency = 0.1, lag = 0.25, distance = 12, confirm = false, frames = 110 })
		expect(firstShown(missed)).toBe(missed.contactFrame)
	end)
end)

describe("the drawn rush shoulders past the body it meets (FB1, D-167)", function()
	for _, case in
		{
			{ across = 0, lag = 0.25, latency = 0.05 },
			{ across = 0, lag = 0, latency = FRAME * 2 },
			{ across = 0, lag = 0.5, latency = 0.2 },
			{ across = 0.8, lag = 0.25, latency = 0.05 },
			{ across = -1.5, lag = 0.25, latency = 0.05 },
		}
	do
		it(
			("a body %.1f studs off the line: the snout meets it, nothing runs through it, it rests on the line (root %.2f s late)"):format(
				case.across,
				case.lag
			),
			function()
				local run =
					meet({ latency = case.latency, lag = case.lag, distance = 12, across = case.across, frames = 120 })
				local contact = run.contactFrame :: number
				expect(contact ~= nil).toBe(true)
				-- The snout meets the body on the contact frame: within a frame's travel of its side.
				local touch = math.huge
				for index = contact - 1, contact + 1 do
					touch = math.min(touch, run.frames[index].snoutGap)
				end
				expect(touch <= FRAME_TRAVEL).toBe(true)
				-- Once the swing is full (fullStuds after the contact), nothing of the drawn body is inside
				-- the player's; before that only the snout's brush at the blow, never deeper than the
				-- snout's own half width.
				local full = contact + math.ceil(PASS.fullStuds / FRAME_TRAVEL)
				local deepest, after = 0, 0
				for index, frame in run.frames do
					deepest = math.max(deepest, frame.inside)
					if index >= full then
						after = math.max(after, frame.inside)
					end
				end
				expect(after <= 1e-3).toBe(true)
				expect(deepest <= 0.6).toBe(true)
				-- The swing is no jump: each frame's move stays near the run's own travel.
				for index = 2, #run.frames do
					local step = (run.frames[index].drawn - run.frames[index - 1].drawn).Magnitude
					expect(step <= 1.2 * FRAME_TRAVEL + 1e-3).toBe(true)
				end
				-- It is back on the line where the server's body stops.
				local last = run.frames[#run.frames]
				expect(math.abs(last.along - LENGTH) < 1e-3).toBe(true)
				expect(math.abs(last.off) < 1e-3).toBe(true)
			end
		)
	end

	it("passes a body square on the line on its right, one off the line away from its side", function()
		local function widest(run: Run): number
			local most = 0
			for _, frame in run.frames do
				if math.abs(frame.off) > math.abs(most) then
					most = frame.off
				end
			end
			return most
		end
		expect(widest(meet({ latency = 0.05, lag = 0.25, distance = 12, across = 0 })) > 1).toBe(true)
		expect(widest(meet({ latency = 0.05, lag = 0.25, distance = 12, across = 0.8 })) < -1).toBe(true)
		expect(widest(meet({ latency = 0.05, lag = 0.25, distance = 12, across = -1.5 })) > 0.5).toBe(true)
		-- A body clear of the drawn body's width (its half width, the body's radius and the pass's
		-- margin) is not swung round.
		local half = 0
		for _, corner in RushWorld.profileOf(RigBuilder.build(BOAR.skin)) do
			half = math.max(half, math.abs(corner.X))
		end
		local beside = half + RADIUS + PASS.marginStuds + 0.1
		local clear = meet({ latency = 0.05, lag = 0.25, distance = 12, across = beside, confirm = false })
		expect(math.abs(widest(clear)) < 1e-3).toBe(true)
	end)
end)

-- The skid's puffs a run threw up (fx.rushSkid through the wallSlam dep's skid): the frame each
-- rose on, where, and the drawn body's place on that frame.
type Puff = { frame: number, point: Vector3, heading: Vector3, drawn: Vector3, along: number }
local function puffsOf(run: Run): { Puff }
	local puffs: { Puff } = {}
	for _, call in run.calls do
		if call.module == "wallSlam" and call.fn == "skid" then
			for index, frame in run.frames do
				if math.abs(LAUNCH + frame.t - call.at) < 1e-6 then
					table.insert(puffs, {
						frame = index,
						point = call.args[1],
						heading = call.args[2],
						drawn = frame.drawn,
						along = frame.along,
					})
					break
				end
			end
		end
	end
	return puffs
end

local SKID = Harness.load("src/shared/data/fx").rushSkid
-- Where the timeline's full speed ends and the skid begins (the strike beat).
local SKID_FROM = SPEED * CHARGE.strike

describe("the drawn rush's skid throws dust from the strike beat to its rest (FB2)", function()
	it("puffs under the hind hooves every everyStuds it slides, from the strike beat to the run's end", function()
		-- The player stands clear of the line: nothing to pass, no blow.
		local run = meet({ latency = 0.05, lag = 0.25, distance = 12, across = 6, confirm = false, frames = 110 })
		local puffs = puffsOf(run)
		-- A puff at every mark short of the stop (none on the stop itself: the slide is spent there).
		expect(#puffs).toBe(math.ceil((LENGTH - SKID_FROM) / SKID.everyStuds - 1e-6))
		-- The first on the frame the drawn body passes the strike beat, none before it.
		local skidFrame: number? = nil
		for index, frame in run.frames do
			if frame.along >= SKID_FROM - 1e-4 then
				skidFrame = index
				break
			end
		end
		expect(skidFrame ~= nil).toBe(true)
		expect(puffs[1].frame).toBe(skidFrame :: number)
		for index, puff in puffs do
			-- Each on the frame the body slides past its mark.
			local mark = SKID_FROM + (index - 1) * SKID.everyStuds
			expect(puff.along >= mark - 1e-4).toBe(true)
			expect(run.frames[puff.frame - 1].along < mark - 1e-4).toBe(true)
			-- On the ground under the body's back half, thrown back along the way it slides.
			local behind = (puff.drawn - puff.point):Dot(DIRECTION)
			expect(behind > 0.5 and behind < 3).toBe(true)
			expect(math.abs((puff.point - ORIGIN):Dot(RIGHT)) < 0.1).toBe(true)
			expect(puff.drawn.Y - puff.point.Y > 1.5).toBe(true)
			expect(puff.heading:Dot(DIRECTION) > 0.99).toBe(true)
			-- The skid slows: the puffs come further apart in time.
			if index > 2 then
				expect(puff.frame - puffs[index - 1].frame >= puffs[index - 1].frame - puffs[index - 2].frame).toBe(
					true
				)
			end
		end
		-- The last within a mark of the run's end, never on it.
		expect(puffs[#puffs].along < LENGTH).toBe(true)
		expect(puffs[#puffs].along > LENGTH - SKID.everyStuds - 1e-3).toBe(true)
	end)

	it("ends at a slam's face in the skid, and a slam or a jam before the strike beat throws none", function()
		local slam = puffsOf(meet({
			latency = 0.05,
			lag = 0.25,
			distance = 12,
			across = 6,
			confirm = false,
			frames = 110,
			ended = { reason = "Wall", distance = 18, after = 0.3 },
		}))
		-- The skid's puffs short of the face; the slam's own burst is at the face.
		expect(#slam).toBe(math.ceil((18 - SKID_FROM) / SKID.everyStuds - 1e-6))
		for _, puff in slam do
			expect(puff.along < 18).toBe(true)
		end
		for _, ended in
			{
				{ reason = "Wall", distance = 10, after = 0.25 },
				{ reason = "Jammed", distance = 8, after = 0.29 },
			}
		do
			local run = meet({
				latency = 0.05,
				lag = 0.25,
				distance = 12,
				across = 6,
				confirm = false,
				frames = 110,
				ended = ended,
			})
			expect(#puffsOf(run)).toBe(0)
		end
	end)
end)

-- The frame (index into run.frames) a call was made on, or nil.
local function frameOf(run: Run, at: number): number?
	for index, frame in run.frames do
		if math.abs(LAUNCH + frame.t - at) < 1e-6 then
			return index
		end
	end
	return nil
end

-- The engine draws a rig step's pose a frame after the step writes it (D-053, impact.poseLagFrames).
local ENGINE_LAG = Harness.load("src/shared/data/impact").poseLagFrames

describe("what a rush's own step finds shows on the frame that draws it (D-342, D-343 with FB1, FB2)", function()
	for _, case in
		{
			{ latency = FRAME * 2, lag = 0.25 },
			{ latency = 0.05, lag = 0.25 },
			{ latency = 0.2, lag = 0.5 },
		}
	do
		it(
			("the blow's white flash and moment on the first frame that draws the snout at the body, the flinch on its step (latency %.3f s, root %.2f s late)"):format(
				case.latency,
				case.lag
			),
			function()
				local run = meet({ latency = case.latency, lag = case.lag, distance = 12, frameClock = true })
				local contact = run.contactFrame :: number
				expect(contact ~= nil).toBe(true)
				local flashFrame, momentFrame, flinchFrame = nil, nil, nil
				for _, call in run.calls do
					local index = frameOf(run, call.at)
					if call.module == "outline" and call.fn == "flash" then
						flashFrame = flashFrame or index
					elseif call.module == "impact" and call.fn == "hit" then
						momentFrame = momentFrame or index
					elseif call.module == "me" and call.fn == "play" then
						flinchFrame = flinchFrame or index
					end
				end
				-- The step that ran the drawn root to the contact poses the flinch and starts the holds;
				-- what the screen shows of the blow waits for the frame that draws that step's pose.
				expect(flinchFrame).toBe(contact)
				expect(flashFrame).toBe(contact + ENGINE_LAG)
				expect(momentFrame).toBe(contact + ENGINE_LAG)
			end
		)
	end

	it("the skid's puffs on the first frame that draws the hooves that slid past their marks", function()
		local run = meet({
			latency = 0.05,
			lag = 0.25,
			distance = 12,
			across = 6,
			confirm = false,
			frames = 110,
			frameClock = true,
		})
		local puffs = puffsOf(run)
		expect(#puffs).toBe(math.ceil((LENGTH - SKID_FROM) / SKID.everyStuds - 1e-6))
		for index, puff in puffs do
			local mark = SKID_FROM + (index - 1) * SKID.everyStuds
			-- The step that slid past the mark wrote the pose this frame draws (the frame before's).
			local wrote = puff.frame - ENGINE_LAG
			expect(run.frames[wrote].along >= mark - 1e-4).toBe(true)
			expect(run.frames[wrote - 1].along < mark - 1e-4).toBe(true)
		end
	end)
end)
