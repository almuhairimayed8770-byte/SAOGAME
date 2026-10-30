--!strict
--[[
	A Boar's rush blow on the local fighter freezes the fighter, never the rush (the predicted rush
	blow, FB1 / D-258 for a rush, meeting the enemy strike's hold, D-355 / D-347). RushMeet.spec
	pins the moment, the flash and the flinch on the drawn contact frame; nothing pinned the freeze:
	showStrike holds the fighter's rig for the blow's tier from that frame and skips the striker
	while its rush runs, and the word (HitConfirmed) holds on the shown freeze (holdShownWord), again
	skipping a rushing striker.

	The harness is RushMeet.spec's (a RigBuilder Boar posed by a real Choreo animator, the remotes
	through the real Replication, the server's body `lag` late, every message `latency` late), with a
	local fighter's animator that keeps its freeze: hitStop(frames) holds it that many frames from
	now (a longer freeze already on is kept), and each frame of the take spends one.
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
local Combat = Harness.load("src/shared/data/combat")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")

local FRAME = 1 / 60
local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]
local SPEED: number = AI.rushSpeed(CHARGE)
local LENGTH: number = CHARGE.reach + AI.archetypes.Charger.overshoot
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
	frozen: boolean, -- the local fighter's rig held still this frame
	boarFrozen: boolean, -- the Boar's animator held a freeze going into this frame
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
	-- The fighter's freeze: seconds it still holds, and every hitStop it was asked for.
	local myHeld = 0
	local myAnimator = {
		hitStop = function(_self: any, frames: number)
			table.insert(calls, { module = "me", fn = "hitStop", args = { frames }, at = clock })
			myHeld = math.max(myHeld, frames * FRAME)
		end,
		pauseRemaining = function(): number
			return myHeld
		end,
		play = function(_self: any, clipId: string): any
			table.insert(calls, { module = "me", fn = "play", args = { clipId }, at = clock })
			return { clipId = clipId }
		end,
		stop = function() end,
	}
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
		local boarHeld = (animator :: any):pauseRemaining()
		animator:step(FRAME)
		local mine = myHeld > ChoreoData.pauseEpsilon
		myHeld = math.max(0, myHeld - FRAME)
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
			frozen = mine,
			boarFrozen = boarHeld > ChoreoData.pauseEpsilon,
		})
		-- The drawn contact: the drawn root has run as far as the server's sweep needs.
		if run.contactFrame == nil and along >= options.distance - RADIUS - front - 1e-4 then
			run.contactFrame = index
		end
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

local NORMAL = Combat.hitStopFrames.Normal - Combat.hitStopShaveFrames

local function hitStopsOnMe(run: Run): { { at: number, frames: number } }
	local list = {}
	for _, call in run.calls do
		if call.module == "me" and call.fn == "hitStop" then
			table.insert(list, { at = call.at, frames = call.args[1] })
		end
	end
	return list
end

describe("a rush's blow freezes the fighter it meets and never the rush (critic item 14, FB1 x D-355)", function()
	for _, case in
		{
			{ latency = FRAME * 2, lag = 0.25 }, -- Play Solo
			{ latency = 0.05, lag = 0.25 },
			{ latency = 0.1, lag = 0.25 },
			{ latency = 0.2, lag = 0.5 },
		}
	do
		it(("latency %.3f s, root %.2f s late"):format(case.latency, case.lag), function()
			local run = meet({ latency = case.latency, lag = case.lag, distance = 12 })
			local contact = run.contactFrame :: number
			expect(contact ~= nil).toBe(true)
			expect(firstShown(run)).toBe(contact)
			-- The fighter freezes from the frame after the one that shows the blow (the pose lags a
			-- frame, D-355) for the blow's tier, in one run.
			local stops = hitStopsOnMe(run)
			expect(#stops >= 1).toBe(true)
			expect(stops[1].frames >= NORMAL - 1e-6).toBe(true)
			local frozen = 0
			local first: number? = nil
			for index = contact, #run.frames do
				if run.frames[index].frozen then
					first = first or index
					frozen += 1
				elseif first ~= nil then
					break
				end
			end
			expect(first ~= nil and (first :: number) <= contact + 1).toBe(true)
			expect(frozen >= NORMAL).toBe(true)
			-- Never frozen twice: once let go, nothing holds the fighter again for this blow.
			local runs, was = 0, false
			for _, frame in run.frames do
				if frame.frozen and not was then
					runs += 1
				end
				was = frame.frozen
			end
			expect(runs).toBe(1)
			-- The rush never stops for it: the Boar's animator holds no freeze, and the drawn body goes
			-- on down the line every frame from the contact until it nears its rest.
			for index = contact, #run.frames do
				local frame = run.frames[index]
				expect(frame.boarFrozen).toBe(false)
				if index > contact and frame.along < LENGTH - FRAME_TRAVEL then
					expect(frame.along > run.frames[index - 1].along + 1e-4).toBe(true)
				end
			end
		end)
	end
end)
