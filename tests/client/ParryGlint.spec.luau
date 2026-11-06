--!strict
--[[
	The parry glint as the player sees it, end to end (D-316; Studio items 238 and 257).

	The real server: EntityService, EnemyService with the Kobold Axeman's Brute brain and
	CombatService's guard judge, on a 60 fps server clock whose frames jitter by a couple of
	milliseconds. Its Telegraph and ActionStarted remotes reach a client whose 60 fps frames run a
	fraction of a frame after the server's, through the real Replication and Telegraphs. The player
	presses guard one and two frames after a Heartbeat lit the glint (they see it on that frame and
	press on the next ones); the GuardRequest reaches the server `latency` later and is read on its
	next frame, where the server alone judges the parry (section 6: the guard went down at most
	combat.parryWindow before the blow lands).

	Two links: Studio's (a remote reaches the client a frame after it was sent, a request is read
	on the server's very next frame) and a live one (both ways the latency, plus half a frame of
	send work up). The wedge stays lit to the axe's snap, goes white for its glint, and a press at
	the glint's first frame or in its last third parries at 0, 17, 50 and 100 ms each way.
]]

local function frameSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
Harness.stubService("CollectionService", {
	AddTag = function(_self, instance, tag)
		instance:AddTag(tag)
	end,
	RemoveTag = function(_self, instance, tag)
		instance:RemoveTag(tag)
	end,
	HasTag = function(_self, instance, tag)
		return instance:HasTag(tag)
	end,
})
Harness.stubService("RunService", {
	RenderStepped = frameSignal(),
	Heartbeat = frameSignal(),
	PreSimulation = frameSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local EntityService = Harness.load("src/server/services/EntityService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local CombatService = Harness.load("src/server/services/CombatService")
local Replication = Harness.load("src/client/controllers/Replication")
local Telegraphs = Harness.load("src/client/fx/Telegraphs")
local FxEngine = Harness.load("src/client/fx/Engine")
local Choreo = Harness.load("src/client/choreo/Choreo")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local CaptureLogic = Harness.load("src/client/dev/CaptureLogic")
local Dev = Harness.load("src/shared/data/dev")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Enemies = Harness.load("src/shared/data/enemies")
local AI = Harness.load("src/shared/data/ai")
local Combat = Harness.load("src/shared/data/combat")
local Fx = Harness.load("src/shared/data/fx")
local Palette = Harness.load("src/shared/data/palette")
local Rigs = Harness.load("src/shared/data/rigs")
local Playground = Harness.load("src/shared/data/playground")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

local FRAME = 1 / 60
local KOBOLD = Enemies.byId("KoboldAxeman")
local OVERHEAD = KOBOLD.attacks[1]
local LANDS = OVERHEAD.windUp + OVERHEAD.strike
local SNAP = LANDS - AI.telegraph.snapLeadSeconds -- the axe's snap begins (clip on the server's beat, D-172)
local CLIP_ID = ("enemy/%s/%s"):format(KOBOLD.skin, OVERHEAD.clip)
local CLIP = ClipLibrary.get(CLIP_ID)
local CLIENT_OFFSET = 400 -- the client's os.clock runs this far behind the server's clock
local WHITE = Palette.color3("TelegraphWhite") -- the glint (Studio item 238: "goes white")
local KIND_COLOR = Palette.color3(Fx.telegraph.fillToken[OVERHEAD.telegraph])
local JITTER = 0.002
local LATENCIES = { 0, 1 / 60, 0.05, 0.1 }
local PHASES = { 0.1, 0.4, 0.7, 0.95 }
local SEEDS = { 1, 2 }

-- Server fixtures -----------------------------------------------------------------------------

local clock = { t = 1000 }
local handlers: { [string]: any } = {}
local toClient: { any } = {}
local toServer: { any } = {}
local link = { down = 0, up = 0 }

local function deliver(remote: string, payload: any)
	local ok, message = Net.validate(remote, payload)
	if not ok then
		error(("invalid %s payload: %s"):format(remote, tostring(message)))
	end
	if remote == "Telegraph" or remote == "ActionStarted" then
		table.insert(toClient, { at = clock.t + link.down, name = remote, payload = payload })
	end
end

local fakeNet = {
	on = function(name: string, handler: any)
		handlers[name] = handler
	end,
	fire = function(remote: string, _player: any, payload: any)
		local ok, message = Net.validate(remote, payload)
		if not ok then
			error(("invalid %s payload: %s"):format(remote, tostring(message)))
		end
	end,
	fireAll = deliver,
}

local bodies: { [any]: any } = {}
local function bodyOf(model: any): any
	local body = bodies[model]
	if body == nil then
		body = { position = Vector3.zero, facing = Vector3.new(0, 0, -1), goal = nil, walkSpeed = nil }
		bodies[model] = body
	end
	return body
end
local engine = {
	place = function(model: any, cframe: CFrame)
		local body = bodyOf(model)
		body.position = cframe.Position
		body.facing = cframe.LookVector
		model.PrimaryPart.CFrame = cframe
	end,
	position = function(model: any): Vector3
		return bodyOf(model).position
	end,
	facing = function(model: any): Vector3
		return bodyOf(model).facing
	end,
	setFacing = function(model: any, facing: Vector3)
		local body = bodyOf(model)
		body.facing = facing.Unit
		model.PrimaryPart.CFrame = CFrame.lookAt(body.position, body.position + body.facing)
	end,
	moveTo = function(model: any, position: Vector3)
		bodyOf(model).goal = position
	end,
	stop = function(model: any)
		bodyOf(model).goal = nil
	end,
	setWalkSpeed = function(model: any, speed: number)
		bodyOf(model).walkSpeed = speed
	end,
	computePath = function(): { Vector3 }?
		return nil
	end,
	destroy = function(model: any)
		model.Parent = nil
	end,
}
local rigBuilder = {
	build = function(_rigId: string, name: string): Model
		local model = Instance.new("Model")
		model.Name = name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = model
		model.PrimaryPart = root
		Instance.new("Humanoid").Parent = model
		return model
	end,
}

local function cframeOf(t: any): CFrame
	return CFrame.new(t.pos[1], t.pos[2], t.pos[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(t.rot[1]), math.rad(t.rot[2]), math.rad(t.rot[3]))
end

local function playerRig(rootCFrame: CFrame): Model
	local rig = Rigs.PlayerR15
	local model = Instance.new("Model")
	model.Name = "Trialist"
	local parts: { [string]: BasePart } = {}
	local function part(partName: string): BasePart
		local existing = parts[partName]
		if existing then
			return existing
		end
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = Vector3.new(1, 1, 1)
		p.Parent = model
		parts[partName] = p
		return p
	end
	local root = part(rig.rootPart)
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = rootCFrame
	model.PrimaryPart = root
	for _, joint in rig.joints do
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Part0 = part(joint.part0)
		motor.Part1 = part(joint.part1)
		motor.C0 = cframeOf(joint.c0)
		motor.Parent = motor.Part0
	end
	Instance.new("Humanoid").Parent = model
	return model
end

local function recorder(): any
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

-- One blow ----------------------------------------------------------------------------------------

type Options = {
	latency: number, -- one way, each way
	studio: boolean, -- Studio's link: a remote reaches the client a frame late; a request is read on the server's next frame
	phase: number, -- the client's frames run this fraction of a frame after the server's
	seed: number, -- the server's frames jitter by up to JITTER from this seed
	press: number?, -- the client frame (counted from the one the Telegraph was heard on) the guard goes down on
	-- A capture guard reaction (dev.luau perform, CF): the kobold's clip drawn on this client and the
	-- guard down `autoLead` before its hit window, the client's latency lead earlier still, as
	-- Capture.client.luau times it (CaptureLogic.hear with Telegraphs.glintLead, D-289).
	autoLead: number?,
}

type Glint = { index: number, white: boolean }

type Run = {
	glints: { Glint }, -- each Heartbeat that lit the glint: its frame since the tell was heard, and whether fill and ground were white
	kindBefore: boolean, -- every lit frame before the glint showed the blow's kind color, fill and ground
	tellEnd: number?, -- seconds after the wind-up began (server clock) of the first Heartbeat the tell was out
	lastLit: number?, -- and of the last Heartbeat it was lit
	resolve: number?, -- seconds after the wind-up began the server resolved the blow
	guardSince: number?, -- and the server stamped the guard
	parried: boolean,
}

local function run(options: Options): Run
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	-- Earlier tells this client heard (the lead it learned, D-289): on a live link, ones as late as
	-- this one; in Studio, none (the one heard teaches it).
	Telegraphs.resetLatency()
	table.clear(handlers)
	table.clear(toClient)
	table.clear(toServer)
	table.clear(bodies)
	link.down = options.latency + (if options.studio then FRAME else 0)
	link.up = options.latency + (if options.studio then 0 else 0.5 * FRAME)
	clock.t = 1000
	local now = function(): number
		return clock.t
	end
	EntityService.bind({
		now = now,
		fireAll = deliver,
		heartbeat = nil,
		addTag = function(instance, tag)
			CollectionService:AddTag(instance, tag)
		end,
		removeTag = function(instance, tag)
			CollectionService:RemoveTag(instance, tag)
		end,
		respawn = function() end,
		playerRemoving = nil,
	})
	CombatService.bind({
		now = now,
		net = fakeNet,
		heartbeat = nil,
		cast = function()
			return nil
		end,
		overlap = function()
			return {}
		end,
		random = {
			NextNumber = function()
				return 0.999
			end,
		},
	})
	CombatService.start()
	local resolve: number? = nil
	local combat = setmetatable({
		enemyStrike = function(...)
			resolve = clock.t
			return CombatService.enemyStrike(...)
		end,
	}, { __index = CombatService })
	local player = { Name = "Trialist", DisplayName = "Trialist", UserId = 1 }
	local playerAt = Vector3.new(0, 3, 0)
	local playerId = EntityService.registerPlayer(player :: any, playerRig(CFrame.new(playerAt)), Playground.loadout)
	EnemyService.bind({
		entities = EntityService,
		combat = combat,
		rigBuilder = rigBuilder,
		fireAll = deliver,
		engine = engine,
		players = function()
			return { { id = playerId, position = playerAt } }
		end,
		heartbeat = nil,
		serverTime = now,
		folder = Instance.new("Folder"),
		random = Random.new(1),
		spawnTask = function(fn)
			fn()
		end,
	} :: any)
	local koboldId = EnemyService.spawn("KoboldAxeman", CFrame.lookAt(Vector3.new(0, 3, -4), playerAt))
	local parried = false
	local parryConnection = CombatService.Parried:Connect(function()
		parried = true
	end)

	-- The client.
	local clientNow = clock.t - CLIENT_OFFSET
	local serverNow = clock.t
	FxEngine.setClock(function(): number
		return clientNow
	end)
	Choreo.configure({
		now = function(): number
			return serverNow
		end,
		cameraPosition = function(): Vector3
			return Vector3.zero
		end,
	})
	local model = RigBuilder.build(KOBOLD.skin)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.lookAt(Vector3.new(0, 3, -4), playerAt)
	root.Position = root.CFrame.Position
	model.Parent = Instance.new("Folder")
	local record =
		{ id = koboldId, model = model, kind = "Enemy", defId = KOBOLD.id, rig = KOBOLD.skin, state = "Idle" }
	local me = { id = playerId, model = Instance.new("Model"), kind = "Player", state = "Idle" }
	local quiet = {
		hitStop = function() end,
		pauseRemaining = function(): number
			return 0
		end,
		play = function() end,
	}
	local heartbeat: ((dt: number) -> ())? = nil
	local animated = options.autoLead ~= nil
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == koboldId then record elseif id == playerId then me else nil
			end,
			all = function(): { any }
				return if animated then { record } else {}
			end,
		},
		localId = function(): number?
			return playerId
		end,
		locomotion = recorder(),
		choreo = {
			get = function(target: any): any
				return if animated and target == model then Choreo.get(target) else quiet
			end,
		},
		clipLibrary = ClipLibrary,
		trails = recorder(),
		smear = recorder(),
		shatter = recorder(),
		sparks = recorder(),
		telegraphs = Telegraphs,
		outline = recorder(),
		switchRing = recorder(),
		digits = recorder(),
		hud = recorder(),
		systemLine = recorder(),
		sfx = recorder(),
		impact = recorder(),
		camera = recorder(),
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
		now = function(): number
			return clientNow
		end,
		serverNow = function(): number
			return serverNow
		end,
		onHeartbeat = function(fn: (dt: number) -> ())
			heartbeat = fn
		end,
	} :: any)
	if not options.studio then
		local earlier = RigBuilder.build(KOBOLD.skin)
		local heard = options.latency + 0.001
		Telegraphs.show(
			earlier,
			OVERHEAD.telegraph,
			OVERHEAD.windUp,
			Vector3.zero,
			Vector3.zAxis,
			nil,
			heard,
			OVERHEAD.strike
		)
		Telegraphs.forget(earlier)
	end

	-- The capture's guard reaction, heard off the clip this client draws.
	local animator = if animated then Choreo.get(model) else nil
	local reaction = if animated
		then CaptureLogic.reactions({ { action = "Guard", onClip = CLIP_ID, lead = options.autoLead, hold = 0.4 } })[1]
		else nil
	local elapsed = 0
	local eventConnection = Replication.clipEvent:Connect(
		function(who: any, clipId: string, event: any, jumped: boolean)
			if reaction == nil or reaction.pressed or jumped or who ~= record or clipId ~= CLIP_ID then
				return
			end
			CaptureLogic.hear(reaction, CLIP.events, event.time, elapsed, Telegraphs.glintLead())
		end
	)

	local result: Run = {
		glints = {},
		kindBefore = true,
		tellEnd = nil,
		lastLit = nil,
		resolve = nil,
		guardSince = nil,
		parried = false,
	}
	local since: number? = nil
	local heardAt: number? = nil
	local index = 0
	local serverBase = 1000 + FRAME
	local serverK = 0
	local jitterState = options.seed
	local function jitter(): number
		jitterState = (jitterState * 1103515245 + 12345) % 2147483648
		return (jitterState / 2147483648 * 2 - 1) * JITTER
	end
	local serverNext = serverBase
	local lastServer = 1000
	local clientNext = 1000 + options.phase * FRAME
	local pressed = false
	local wasShowing = false
	while clock.t < 1012 do
		if resolve ~= nil and clock.t > (resolve :: number) + 0.1 then
			break
		end
		if serverNext <= clientNext then
			-- A server frame: the requests in by now, then physics, the brains, the services.
			clock.t = serverNext
			serverK += 1
			serverNext = serverBase + serverK * FRAME + jitter()
			local dt = clock.t - lastServer
			lastServer = clock.t
			for _, message in toServer do
				if not message.done and message.at <= clock.t + 1e-9 then
					message.done = true
					handlers.GuardRequest(player, message.payload)
					result.guardSince = EntityService.get(playerId).guardSince
				end
			end
			for m, body in bodies do
				if body.goal ~= nil then
					local delta = body.goal - body.position
					local reach = (body.walkSpeed or 1) * dt
					body.position = if delta.Magnitude <= reach then body.goal else body.position + delta.Unit * reach
					m.PrimaryPart.CFrame = CFrame.lookAt(body.position, body.position + body.facing)
				end
			end
			EnemyService.step(dt)
			EntityService.tick(dt)
			CombatService.tick()
		else
			-- A client frame: input, the remotes in by now, then Heartbeat (the tell's step).
			local t = clientNext
			clientNext += FRAME
			serverNow = t
			clientNow = t - CLIENT_OFFSET
			index += 1
			elapsed += FRAME
			if animator ~= nil then
				animator:step(FRAME)
			end
			local due = (options.press ~= nil and heardAt ~= nil and index - (heardAt :: number) == options.press)
				or (reaction ~= nil and reaction.at ~= nil and elapsed >= (reaction.at :: number) - 1e-9)
			if not pressed and due then
				pressed = true
				if reaction ~= nil then
					CaptureLogic.pressed(reaction)
				end
				table.insert(toServer, {
					at = t + link.up,
					payload = { held = true, facing = { 0, 0, -1 }, clientTime = clientNow },
				})
			end
			for _, message in toClient do
				if not message.done and message.at <= t + 1e-9 then
					message.done = true
					if message.name == "Telegraph" and since == nil then
						since = message.payload.serverTime
						heardAt = index
					end
					Replication.dispatch(message.name, message.payload)
				end
			end
			Telegraphs.step()
			if heartbeat ~= nil then
				(heartbeat :: (number) -> ())(FRAME)
			end
			if since ~= nil then
				local fill = model:FindFirstChild("TelegraphFill") :: Highlight?
				local showing = Telegraphs.isShowing(model)
				if showing and fill ~= nil and fill.Enabled then
					result.lastLit = t - (since :: number)
					local ground = Telegraphs.parts(model)
					local function all(color: Color3): boolean
						if fill.FillColor ~= color then
							return false
						end
						for _, part in ground do
							if part.Color ~= color then
								return false
							end
						end
						return true
					end
					if math.abs(fill.FillTransparency - AI.telegraph.glintFillTransparency) < 1e-3 then
						table.insert(result.glints, { index = index - (heardAt :: number), white = all(WHITE) })
					elseif #result.glints == 0 and not all(KIND_COLOR) then
						result.kindBefore = false
					end
				end
				if wasShowing and not showing and result.tellEnd == nil then
					result.tellEnd = t - (since :: number)
				end
				wasShowing = showing
			end
		end
	end
	result.resolve = if resolve ~= nil and since ~= nil then (resolve :: number) - (since :: number) else nil
	if result.guardSince ~= nil and since ~= nil then
		result.guardSince = (result.guardSince :: number) - (since :: number)
	end
	result.parried = parried
	parryConnection:Disconnect()
	eventConnection:Disconnect()
	Telegraphs.forget(model)
	FxEngine.setClock(nil)
	return result
end

local function label(studio: boolean, latency: number, phase: number, seed: number): string
	return ("%s link, %.0f ms, phase %.2f, seed %d"):format(
		if studio then "Studio" else "live",
		latency * 1000,
		phase,
		seed
	)
end

-- Every case: both links, each latency, each client phase, each jitter seed.
local function eachCase(visit: (studio: boolean, latency: number, phase: number, seed: number) -> ())
	for _, studio in { true, false } do
		for _, latency in LATENCIES do
			for _, phase in PHASES do
				for _, seed in SEEDS do
					visit(studio, latency, phase, seed)
				end
			end
		end
	end
end

describe("the parry glint through the real chain (D-316)", function()
	it("the wedge stays lit to the axe's snap and goes white, fill and ground, for its glint", function()
		eachCase(function(studio, latency, phase, seed)
			local name = label(studio, latency, phase, seed)
			local watch = run({ latency = latency, studio = studio, phase = phase, seed = seed })
			-- The blow lands on its beat, and the tell is out on the first Heartbeat after the snap begins.
			local resolve = watch.resolve :: number
			expect(resolve >= LANDS - 1e-6 and resolve <= LANDS + FRAME + JITTER).toBe(true)
			local tellEnd = watch.tellEnd :: number
			if not (tellEnd >= SNAP - 1e-6 and tellEnd <= SNAP + FRAME + 1e-6) then
				error(
					("%s: the tell went out %.0f ms after the wind-up began, the snap is at %.0f"):format(
						name,
						tellEnd * 1000,
						SNAP * 1000
					)
				)
			end
			-- The glint: a few frames in a row, every one white on the weapon and on the ground.
			for i, glint in watch.glints do
				if not glint.white then
					error(("%s: glint frame %d is not white"):format(name, i))
				end
				if i > 1 and glint.index ~= watch.glints[i - 1].index + 1 then
					error(("%s: the glint broke off at frame %d"):format(name, i))
				end
			end
			local count = #watch.glints
			if count < 2 or count > Fx.telegraph.glintFrames + 1 then
				error(("%s: the glint lit %d frames"):format(name, count))
			end
			-- Before it the tell is its kind's color.
			expect(watch.kindBefore).toBe(true)
		end)
	end)

	-- With half a frame to spare on either side of the window: the guard stamped at least that
	-- long after the window opened and before the blow resolved.
	it("a press at the glint's start and in its last third parries, at 0, 17, 50 and 100 ms", function()
		local spare = FRAME / 2
		eachCase(function(studio, latency, phase, seed)
			local watch = run({ latency = latency, studio = studio, phase = phase, seed = seed })
			local count = #watch.glints
			expect(count >= 1).toBe(true)
			local thirds = math.max(1, math.floor(count / 3 + 0.5))
			local frames: { [number]: string } = { [watch.glints[1].index] = "start" }
			for i = count - thirds + 1, count do
				frames[watch.glints[i].index] = frames[watch.glints[i].index] or "last third"
			end
			for litOn, where in frames do
				-- Seen on the frame the Heartbeat lit, pressed on the next one or the one after.
				for _, after in { 1, 2 } do
					local press =
						run({ latency = latency, studio = studio, phase = phase, seed = seed, press = litOn + after })
					local guard = press.guardSince
					local blow = press.resolve
					local inside = guard ~= nil
						and blow ~= nil
						and guard >= blow - Combat.parryWindow + spare
						and guard <= blow - spare
					if not press.parried or not inside then
						error(
							("%s: a press %d frame(s) after the glint's %s did not parry with time to spare (guard %s, blow %s)"):format(
								label(studio, latency, phase, seed),
								after,
								where,
								if guard ~= nil then ("%.0f ms"):format(guard * 1000) else "never",
								if blow ~= nil then ("%.0f ms"):format(blow * 1000) else "never"
							)
						)
					end
				end
			end
		end)
	end)
	-- The capture panel's auto-perform guards off the clip it draws, `lead` before its hit window
	-- and the latency lead earlier still (the press reaches the server a latency after it leaves,
	-- as the glint comes): every shot's guard on the kobold's overhead parries on both links at
	-- every latency, with half a frame to spare (Studio item 324; the 2727b4c parry-spark failed at 100 ms).
	it("the capture's guard reactions parry at 0, 17, 50 and 100 ms (CaptureLogic.hear, D-289)", function()
		local leads: { [number]: string } = {}
		for _, shot in Dev.capture.shots do
			for _, entry in shot.perform or {} do
				if entry.action == "Guard" and entry.onClip == CLIP_ID then
					leads[entry.lead or 0] = shot.id
				end
			end
		end
		expect(next(leads)).never.toBeNil()
		local spare = FRAME / 2
		for lead, shotId in leads do
			eachCase(function(studio, latency, phase, seed)
				local press = run({ latency = latency, studio = studio, phase = phase, seed = seed, autoLead = lead })
				local guard = press.guardSince
				local blow = press.resolve
				local inside = guard ~= nil
					and blow ~= nil
					and guard >= blow - Combat.parryWindow + spare
					and guard <= blow - spare
				if not press.parried or not inside then
					error(
						("%s: shot %s's guard (lead %.2f) did not parry with time to spare (guard %s, blow %s)"):format(
							label(studio, latency, phase, seed),
							shotId,
							lead,
							if guard ~= nil then ("%.0f ms"):format(guard * 1000) else "never",
							if blow ~= nil then ("%.0f ms"):format(blow * 1000) else "never"
						)
					)
				end
			end)
		end
	end)
end)
