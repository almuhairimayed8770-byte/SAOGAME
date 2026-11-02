--!strict
--[[
	An enemy's walk start keeps its planted feet on the field (section 21 gate line 4: no sliding
	foot in any clip; AG 392(b): the boar's hooves slid 0.13-0.34 a frame after 0.15 s and stood
	0.06-0.10 in the floor as it set off, on all three takes, where the kobold's held). D-541.

	Played the way the game plays it: the real EnemyService (Charger and Brute brains at the AI's
	tick, the frame pass, the yaw align) spawns the enemy held 15 studs from a player, its facing
	`off` degrees off the player, over BoarHooks.spec's "studio" Humanoid (its walk settled once a
	frame, reaching its WalkSpeed at 1320 studs/s², braking 0.672 a 1/240 s step); a client copy
	(RigBuilder) draws it through Choreo with Locomotion's RigDriver attached as Replication attaches
	it (its default tracker paces the gait by the replicated root's own travel, D-575). Each row:
	the client step, the server frames due by then, then the replicated root. The row shows that
	step's joints on the root physics just moved (Choreo writes the joints before physics; the screen
	is the part CFrames after it). The enemy is let go and its feet are read from the row its root
	first moves.

	Measured over the walk start (0.15 to 0.5 s after the root first moves, the PC's window): each
	foot's least-moving corner grounded through a frame (within stride.contact of the field: the
	slide ClipAudit and the PC measure) and the lowest corner of any foot.
	The first block takes the client's root and velocity as the server's each 60 Hz frame; the second
	takes the PC's view (AO 473 on 209875b): a replicated velocity that under-reads the root's move,
	and a 144 Hz client drawing the root between the server's frames. Both assume a rigid yaw
	(AlignOrientation RigidityEnabled).
]]
local function fakeSignal()
	local signal = {}
	function signal:Connect()
		return { Disconnect = function() end }
	end
	return signal
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
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
	RenderStepped = fakeSignal(),
	Heartbeat = fakeSignal(),
	PreSimulation = fakeSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local EntityService = Harness.load("src/server/services/EntityService")
local CombatService = Harness.load("src/server/services/CombatService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local AI = Harness.load("src/shared/data/ai")
local Dev = Harness.load("src/shared/data/dev")
local Rigs = Harness.load("src/shared/data/rigs")
local Playground = Harness.load("src/shared/data/playground")
local ChoreoData = Harness.load("src/shared/data/choreo")
local CollectionService = Harness.game():GetService("CollectionService")

local clientNow = 0
local Choreo = Harness.load("src/client/choreo/Choreo")
Choreo.configure({
	now = function()
		return clientNow
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")

local FRAME = 1 / 60
local PHYSICS_STEP = 1 / 240
local GAP = 1e-9
local Stride = ChoreoData.locomotion.stride
local CONTACT = Stride.contact
local SLIDE = Dev.review.audit.footSlideStuds
local FROM, TO = 0.15, 0.5
-- The stop (D-623): from the brake row (the first row, once the root has walked, whose flat step
-- is under BRAKE of the row before's) for STOP_SECONDS.
local BRAKE = 0.5
local STOP_SECONDS = 0.5
-- An attack out of the walk (D-632): its first CROUCH_SECONDS, from the first row it is drawn.
local CROUCH_SECONDS = 0.3
-- What the server sends while a take runs (EnemyService's fireAll): a take that draws actions
-- plays an ActionStarted's clip on the client copy as Replication does.
local onFire: ((string, any) -> ())? = nil

-- BoarHooks.spec's "studio" Humanoid (the PC's server log on 4b18b5c).
local humanoid = { arriveFrames = 1.7, brake = 0.672, acceleration = 1320 }
local clock = { t = 1000 }
local bodies: { [Model]: any } = {}

-- ------------------------------------------------------------------------------------------
-- The fake engine (BoarHooks.spec's, no walls)
-- ------------------------------------------------------------------------------------------

local function yawOf(model: Model): Vector3
	local align = EnemyService.alignOf(model)
	local look = if align ~= nil then align.CFrame.LookVector else (model.PrimaryPart :: BasePart).CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function placeParts(model: Model, body: any)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.lookAt(body.position, body.position + yawOf(model))
end

local engine = {
	place = function(model: Model, cframe: CFrame)
		local root = model.PrimaryPart :: BasePart
		root.CFrame = cframe
		EnemyService.addYawAlign(root, cframe.LookVector)
		bodies[model] = { position = cframe.Position, velocity = Vector3.zero, walkSpeed = 16, physT = clock.t }
		placeParts(model, bodies[model])
	end,
	pivot = function(model: Model, cframe: CFrame)
		bodies[model].position = cframe.Position
		placeParts(model, bodies[model])
	end,
	position = function(model: Model): Vector3
		return bodies[model].position
	end,
	facing = function(model: Model): Vector3
		return yawOf(model)
	end,
	setFacing = function(model: Model, facing: Vector3)
		EnemyService.applyFacing(model, facing)
	end,
	moveTo = function(model: Model, position: Vector3)
		bodies[model].goal = position
	end,
	stop = function(model: Model)
		bodies[model].goal = bodies[model].position
	end,
	halt = function(model: Model, position: Vector3?)
		local body = bodies[model]
		if position ~= nil then
			body.position = Vector3.new(position.X, body.position.Y, position.Z)
		end
		body.velocity = Vector3.zero
		body.goal = body.position
		body.written = true
		placeParts(model, body)
	end,
	land = function(model: Model, position: Vector3, seconds: number)
		local body = bodies[model]
		local offset = Vector3.new(position.X - body.position.X, 0, position.Z - body.position.Z)
		local pace = if seconds > 0 then offset / seconds else Vector3.zero
		body.velocity = pace
		body.walkSpeed = pace.Magnitude
		body.goal = Vector3.new(position.X, body.position.Y, position.Z)
		body.written = true
	end,
	setWalkSpeed = function(model: Model, speed: number)
		bodies[model].walkSpeed = speed
	end,
	computePath = function()
		return nil
	end,
	destroy = function(model: Model)
		model.Parent = nil
		bodies[model] = nil
	end,
	setCollisionGroup = function(model: Model, group: string)
		CollisionGroups.assign(model, group)
	end,
	bodyClear = function(): boolean
		return true
	end,
	worldAhead = function(model: Model, direction: Vector3, distance: number, offset: Vector3?, walk: Vector3?)
		return EnemyService.worldAhead(model, direction, distance, function()
			return nil, nil
		end, offset, walk)
	end,
	anchor = function(model: Model, anchored: boolean)
		bodies[model].anchored = anchored
	end,
}

-- One server frame of the "studio" Humanoid: the walk settled at the frame's start, then 240 Hz
-- physics steps toward it at `acceleration`, braking when it holds its goal as reached.
local function studioFrame(model: Model, body: any, untilT: number)
	local seconds = untilT - body.physT
	local desired: Vector3? = nil
	local goal = body.goal
	if goal ~= nil and not body.anchored then
		local delta = Vector3.new(goal.X - body.position.X, 0, goal.Z - body.position.Z)
		local reached = humanoid.arriveFrames * body.walkSpeed * math.max(seconds, 0)
		if delta.Magnitude > math.max(reached, 1e-3) then
			desired = delta.Unit * body.walkSpeed
		end
	end
	local kept = body.written == true
	body.written = false
	while body.physT + PHYSICS_STEP <= untilT + GAP do
		body.physT += PHYSICS_STEP
		if body.anchored then
			body.velocity = Vector3.zero
			continue
		end
		if desired ~= nil then
			local change = desired - body.velocity
			local most = humanoid.acceleration * PHYSICS_STEP
			if change.Magnitude > most then
				change = change.Unit * most
			end
			body.velocity += change
		elseif not kept then
			body.velocity *= humanoid.brake
			if body.velocity.Magnitude < 0.01 then
				body.velocity = Vector3.zero
			end
		end
		body.position += body.velocity * PHYSICS_STEP
	end
	placeParts(model, body)
end

local function serverFrame()
	clock.t += FRAME
	for model, body in bodies do
		studioFrame(model, body, clock.t)
	end
	EnemyService.step(FRAME)
	EntityService.tick(FRAME)
	CombatService.tick()
end

local function fresh()
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	clock.t = 1000
	bodies = {}
	local now = function()
		return clock.t
	end
	EntityService.bind({
		now = now,
		fireAll = function() end,
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
		net = { on = function() end, fire = function() end, fireAll = function() end },
		heartbeat = nil,
		cast = function()
			return nil
		end,
		overlap = function()
			return {}
		end,
		random = Random.new(1),
	})
	EnemyService.bind({
		entities = EntityService,
		combat = CombatService,
		rigBuilder = RigBuilder,
		fireAll = function(name: string, payload: any)
			if onFire ~= nil then
				onFire(name, payload)
			end
		end,
		engine = engine,
		players = function()
			local list = {}
			for _, player in EntityService.players() do
				if player.state ~= "Dead" then
					table.insert(list, { id = player.id, position = EntityService.positionOf(player.id) })
				end
			end
			return list
		end,
		heartbeat = nil,
		serverTime = now,
		folder = Instance.new("Folder"),
		random = Random.new(3),
		spawnTask = function(fn)
			fn()
		end,
	} :: any)
end

local function spawnPlayer(position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Trialist1"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position)
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	CollisionGroups.assign(model, AI.collision.players)
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 3101 }
	return EntityService.registerPlayer(player :: any, model, Playground.loadout)
end

-- ------------------------------------------------------------------------------------------
-- The drawn rows
-- ------------------------------------------------------------------------------------------

local function corners(size: Vector3): { Vector3 }
	local list = {}
	local half = size * 0.5
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(list, Vector3.new(x * half.X, y * half.Y, z * half.Z))
			end
		end
	end
	return list
end

-- Every part's CFrame from the root through the Motor6Ds as Choreo wrote them (Part0 * C0 *
-- Transform = Part1 * C1).
local function solve(model: Model, root: CFrame): { [string]: CFrame }
	local out = { [(model.PrimaryPart :: BasePart).Name] = root }
	local motors = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			table.insert(motors, descendant)
		end
	end
	local progressed = true
	while progressed do
		progressed = false
		for _, motor in motors do
			local p0, p1 = (motor.Part0 :: BasePart).Name, (motor.Part1 :: BasePart).Name
			if out[p0] ~= nil and out[p1] == nil then
				out[p1] = out[p0] * motor.C0 * motor.Transform * motor.C1:Inverse()
				progressed = true
			end
		end
	end
	return out
end

local FEET = {
	Boar = { "FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg" },
	Kobold = { "LeftLeg", "RightLeg" },
}
local DEFS = { Boar = "FrenzyBoar", Kobold = "KoboldAxeman" }

type Take = {
	slide: number, -- the worst one-row slide of a grounded foot over the window
	slideAt: number,
	lowest: number, -- the lowest foot corner over the window
	wheelWalk: number?, -- the least walk weight the driver gives while the body wheels at half speed
	paces: { number }, -- the server body's WalkSpeed after each server frame from the release on
	crab: number, -- the most the server body walked off its facing (degrees), over the whole take
	startSlide: number, -- the worst one-row slide of a grounded foot from the release up to the window (but row 0)
	startSlideAt: number,
	startLowest: number, -- the lowest foot corner from the release up to the window (but row 0)
	standLowest: number, -- the lowest foot corner on the row the root first moves (the idle's stand)
	-- The stop (D-623), when the take runs on to it: the brake row (seconds after the root first
	-- moved), the worst one-row slide of a grounded foot and the lowest corner from it for
	-- STOP_SECONDS, and on the stop's last row the walk's weight, whether the stop plant's channel is
	-- still on the rig and the highest foot's lowest corner (every foot down: at most contact).
	stopAt: number?,
	stopSlide: number,
	stopSlideAt: number,
	stopLowest: number,
	stopWalk: number?,
	stopChannel: boolean?,
	stopHighest: number?,
	-- Clips the take's ActionStarted played on the client, and whether the stop plant's channel was
	-- on the rig on a row a full-body clip showed.
	played: { string },
	channelUnderFullBody: boolean,
	-- The first attack clip ActionStarted played (D-632), when the take draws actions: its id, its
	-- first drawn row (seconds after the release; a clip that waited for the drawn body, D-652,
	-- shows from the row it stops waiting, crouchWaited seconds after it was played), the walk's
	-- weight on the row before it, and over
	-- its first CROUCH_SECONDS (that row on) the worst one-row slide of a grounded foot, where (seconds
	-- after the attack's first row), which foot, the root's flat step on that row, and the lowest
	-- corner of any foot; the lowest corner the clip's own pose puts a foot at on those rows (the
	-- clip alone at the time it showed, on the root it was drawn on: what its crouch sinks itself),
	-- and whether a pose hook (the attack plant's) was still on the mixer on the last of them.
	crouchClip: string?,
	crouchAt: number?,
	crouchWaited: number?,
	crouchWalk: number?,
	crouchSlide: number,
	crouchSlideAt: number,
	crouchFoot: string,
	crouchStep: number,
	crouchLowest: number,
	crouchOwnLowest: number,
	crouchHooked: boolean?,
	-- Each of those rows: seconds after the attack's first row, the root's flat step, and per foot
	-- its slide (-1 when no corner was grounded through the row), its lowest corner and the clip's.
	crouchRows: { { at: number, step: number, feet: { [string]: { slide: number, low: number, own: number } } } },
}

-- How the client sees the server's root. `hz`: client rows a second. `interpolated`: the root is
-- drawn 1/60 s behind the server's latest frame, lerped between its 60 Hz frames, as Roblox draws
-- a replicated part between the snapshots it buffers (the PC's 473(g): at 144 the root steps every
-- row); otherwise it is the server's root of the frame just run (60 Hz, the server's own frames).
-- `share`: the share of the root's velocity the replicated AssemblyLinearVelocity reads on a row
-- (nil: all of it).
-- `lag`: how far behind the server's latest frame an interpolated root is drawn (nil: 1/60 s).
-- `arrival`: ActionStarted and Telegraph play on the row the server sent them (a remote event comes
-- in ahead of the replicated root that lags it), not once the drawn root reached their time.
-- `yawLead`: the seconds the drawn yaw leads the drawn position on a row (an uneven drawn turn).
type View = {
	hz: number,
	interpolated: boolean,
	share: ((row: number) -> number)?,
	lag: number?,
	arrival: boolean?,
	yawLead: ((row: number) -> number)?,
}

local SERVER: View = { hz = 60, interpolated = false }

-- The replicated velocity under-reads the root's move (AH 401(c): the drawn rush's root read
-- 0.08-0.74 of it at 60 fps, 0.74-0.95 at 144). At walk pace, the PC's walk-start takes (473 on
-- 209875b) are read back from the real path on 318f0a3's gait by a milder under-read: a share
-- cycling over 0.5-1.0 at 60 fps (the boar at 90 deg: 0.190, the PC 0.168; the kobold at 0, 60
-- and 90: 0.116, the PC 0.140, 0.036 and 0.084) and over 0.5-0.95 at 144 on the interpolated root
-- (the boar at 90, 135 and 180: 0.090, 0.058 and 0.053, the PC 0.086, 0.078 and 0.062; the kobold
-- at 0, 60, 90, 135 and 180: 0.059, 0.059, 0.063, 0.069 and 0.120, the PC 0.098, 0.094, 0.062,
-- 0.096 and 0.140). The gait paced by the root's own travel (D-575) reads none of it.
local function underRead(low: number, high: number): (row: number) -> number
	return function(row: number): number
		return low + (high - low) * ((row * 7) % 10) / 9
	end
end
local PC60: View = { hz = 60, interpolated = false, share = underRead(0.5, 1) }
local PC144: View = { hz = 144, interpolated = true, share = underRead(0.5, 0.95) }

-- The server's root `seconds` ago, lerped between its frames, and its velocity likewise.
local function sampled(history: { any }, at: number): (CFrame, Vector3)
	local a, b = history[1], history[1]
	for index, entry in history do
		if entry.t <= at + GAP then
			a = entry
			b = history[index + 1] or entry
		end
	end
	if b.t <= a.t then
		return a.cframe, a.velocity
	end
	local f = math.clamp((at - a.t) / (b.t - a.t), 0, 1)
	return a.cframe:Lerp(b.cframe, f), a.velocity:Lerp(b.velocity, f)
end

-- `seconds`: how long the take runs from the release (1.5 when nil). `actions`: ActionStarted's
-- clips play on the client copy once the drawn root has reached the server time they were sent at
-- (the view's `arrival`: as they are sent), and each Telegraph names its wind-up's origin to the
-- driver as Replication does (Locomotion.windUpAt, D-652).
local function take(rig: string, off: number, view: View?, seconds: number?, actions: boolean?): Take
	local seen = view or SERVER
	fresh()
	spawnPlayer(Vector3.new(0, 3, 25))
	local height = Rigs[rig].hipHeight + Rigs[rig].parts[Rigs[rig].rootPart].size[2] / 2
	local at = Vector3.new(0, height, 10)
	local id = EnemyService.spawn(DEFS[rig], CFrame.new(at))
	EnemyService.setHeld(id, true)
	local server = EnemyService.modelOf(id) :: Model
	local look = CFrame.Angles(0, math.rad(off), 0):VectorToWorldSpace(Vector3.new(0, 0, 1))
	EnemyService.place(id, CFrame.lookAt(at, at + look), true)
	for _ = 1, 30 do
		serverFrame()
	end

	-- The client copy and its gait, as Replication attaches it (Locomotion.idlePhase, the default
	-- tracker on the replicated root).
	local client = RigBuilder.build(rig)
	local clientRoot = client.PrimaryPart :: BasePart
	local clientHumanoid = client:FindFirstChildOfClass("Humanoid") :: Humanoid
	clientHumanoid.FloorMaterial = Enum.Material.Plastic
	clientHumanoid.MoveDirection = Vector3.zero
	local serverRoot = server.PrimaryPart :: BasePart
	clientRoot.CFrame = serverRoot.CFrame
	clientRoot.Position = serverRoot.CFrame.Position
	clientRoot.AssemblyLinearVelocity = Vector3.zero
	local animator = Choreo.get(client)
	local driver = Locomotion.attach(animator, client, { phase = Locomotion.idlePhase(id) })
	for _ = 1, 60 do
		clientNow += FRAME
		animator:step(FRAME)
	end
	local walkId = ChoreoData.rigs[rig].walk
	local function walkHandle(): any
		for _, handle in animator.mixer:handles() do
			if handle.clipId == walkId and not handle.stopping and not handle.fallback then
				return handle
			end
		end
		return nil
	end

	EnemyService.setHeld(id, false)
	local feet = FEET[rig]
	local local_: { [string]: { Vector3 } } = {}
	for _, foot in feet do
		local_[foot] = corners((client:FindFirstChild(foot) :: BasePart).Size)
	end
	local rest = clientRoot.CFrame.Position
	local started: number? = nil
	local previous: { [string]: { Vector3 } }? = nil
	local result: Take = {
		slide = 0,
		slideAt = 0,
		lowest = math.huge,
		wheelWalk = nil,
		paces = {},
		crab = 0,
		startSlide = 0,
		startSlideAt = 0,
		startLowest = math.huge,
		standLowest = math.huge,
		stopAt = nil,
		stopSlide = 0,
		stopSlideAt = 0,
		stopLowest = math.huge,
		stopWalk = nil,
		stopChannel = nil,
		stopHighest = nil,
		played = {},
		channelUnderFullBody = false,
		crouchClip = nil,
		crouchAt = nil,
		crouchWaited = nil,
		crouchWalk = nil,
		crouchSlide = 0,
		crouchSlideAt = 0,
		crouchFoot = "",
		crouchStep = 0,
		crouchLowest = math.huge,
		crouchOwnLowest = math.huge,
		crouchHooked = nil,
		crouchRows = {},
	}
	local crouchRow: number? = nil
	local crouchHandle: any = nil
	local crouchPlayed: number? = nil
	local walkBefore = 0
	local sent: { any } = {}
	onFire = function(name: string, payload: any)
		if actions == true and (name == "ActionStarted" or name == "Telegraph") then
			table.insert(sent, { name = name, payload = payload })
		end
	end
	local windUpAt = (Locomotion :: any).windUpAt
	local lag = seen.lag or FRAME
	local mixer = animator.mixer :: any
	local lastAt: Vector3? = nil
	local lastStep: number? = nil
	local walked = false
	local brakeRow: number? = nil
	local walkSpeed = Rigs[rig].walkSpeed
	local dt = 1 / seen.hz
	local clientT = clock.t
	local history = { { t = clock.t, cframe = serverRoot.CFrame, velocity = Vector3.zero } }
	for row = 1, math.ceil((seconds or 1.5) * seen.hz) do
		-- The client's step (Camera - 1, on the root as the last frame left it), then the server
		-- frames due by the row's end, then the root this client draws the row on.
		clientNow += dt
		clientT += dt
		local drawnT = if seen.interpolated then clientT - lag else clock.t
		local playBy = if seen.arrival == true then clock.t else drawnT
		local walkShown = walkHandle()
		walkBefore = if walkShown ~= nil then walkShown.weight else 0
		while #sent > 0 and sent[1].payload.serverTime <= playBy + GAP do
			local entry = table.remove(sent, 1)
			local payload = entry.payload
			if entry.name == "Telegraph" then
				if windUpAt ~= nil and payload.origin ~= nil then
					windUpAt(driver, Vector3.new(table.unpack(payload.origin)))
				end
				continue
			end
			-- As Replication plays an enemy's ActionStarted: on the server's clock (Choreo's clock is
			-- the server's; here the client's runs clientT - clientNow behind it), so the network
			-- catch-up jumps it by the time since it was sent, its attack kept on the server's beat
			-- (D-172). An enemy's ActionStarted carries no speed.
			local sentAt = payload.serverTime - (clientT - clientNow)
			local handle = animator:play(payload.clipId, { serverTime = sentAt })
			if handle.clip.attack == true then
				animator:keepBeat(handle, sentAt)
				if crouchHandle == nil then
					crouchHandle = handle
					crouchPlayed = row
					result.crouchClip = payload.clipId
				end
			end
			table.insert(result.played, payload.clipId)
		end
		animator:step(dt)
		if crouchHandle ~= nil and crouchRow == nil and crouchHandle.fadeHeld ~= true then
			-- Its first drawn row: the clip shows (it waits, hidden, while its fade in stands).
			crouchRow = row
			result.crouchAt = row * dt
			result.crouchWaited = (row - (crouchPlayed :: number)) * dt
			result.crouchWalk = walkBefore
		end
		local fullBody = false
		for _, handle in mixer:handles() do
			if handle.layer == "FullBody" and not handle.done and handle.weight > 0 then
				fullBody = true
			end
		end
		if fullBody and mixer._procedural.walkStopPlant ~= nil then
			result.channelUnderFullBody = true
		end
		while clock.t + FRAME <= clientT + GAP do
			serverFrame()
			table.insert(history, { t = clock.t, cframe = serverRoot.CFrame, velocity = bodies[server].velocity })
			table.insert(result.paces, bodies[server].walkSpeed)
			-- The way the body walks against the way it faces (a walk's feet step along the facing).
			local moving = Vector3.new(bodies[server].velocity.X, 0, bodies[server].velocity.Z)
			if moving.Magnitude > walkSpeed * Stride.rateFloor then
				local facing = yawOf(server)
				local off = math.deg(math.acos(math.clamp(facing:Dot(moving.Unit), -1, 1)))
				result.crab = math.max(result.crab, off)
			end
		end
		local cframe, velocity
		if seen.interpolated then
			cframe, velocity = sampled(history, clientT - lag)
			if seen.yawLead ~= nil then
				local turned = sampled(history, clientT - lag + seen.yawLead(row))
				cframe = CFrame.new(cframe.Position) * turned.Rotation
			end
		else
			local last = history[#history]
			cframe, velocity = last.cframe, last.velocity
		end
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		clientRoot.CFrame = cframe
		clientRoot.Position = cframe.Position
		clientRoot.AssemblyLinearVelocity = velocity * (if seen.share ~= nil then seen.share(row) else 1)
		clientHumanoid.MoveDirection = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zero

		local solved = solve(client, clientRoot.CFrame)
		if started == nil and (clientRoot.CFrame.Position - rest).Magnitude > 1e-3 then
			started = row
		end
		local rowT = if started ~= nil then (row - (started :: number)) * dt else -1
		-- The brake row: the root's flat step falls under BRAKE of the row before's, once it walked
		-- (stepped at least the walk's rateFloor pace a row).
		local here = clientRoot.CFrame.Position
		local step = if lastAt ~= nil
			then Vector3.new(here.X - (lastAt :: Vector3).X, 0, here.Z - (lastAt :: Vector3).Z).Magnitude
			else nil
		if step ~= nil then
			if step > Stride.rateFloor * walkSpeed * dt then
				walked = true
			end
			if brakeRow == nil and walked and lastStep ~= nil and step < BRAKE * (lastStep :: number) then
				brakeRow = row
				result.stopAt = rowT
			end
		end
		lastAt, lastStep = here, step
		local stopRows = math.floor(STOP_SECONDS * seen.hz + 0.5)
		local inStop = brakeRow ~= nil and row - (brakeRow :: number) <= stopRows
		local crouchRows = math.floor(CROUCH_SECONDS * seen.hz + 0.5)
		local inCrouch = crouchRow ~= nil and row - (crouchRow :: number) <= crouchRows
		local own = if inCrouch
			then Pose.solve(client, clientRoot.CFrame, ClipSampler.sample(crouchHandle.clip, crouchHandle.time))
			else nil
		if crouchRow ~= nil and row - (crouchRow :: number) == crouchRows then
			local hooks = mixer._poseHooks
			result.crouchHooked = hooks ~= nil and next(hooks) ~= nil
		end
		local stopEnd = brakeRow ~= nil and row - (brakeRow :: number) == stopRows
		local highest = -math.huge
		local inWindow = rowT > FROM + 1e-9 and rowT <= TO + 1e-9
		-- Row 0 is drawn on the step before the root moved (the gait cannot know yet); the start's
		-- rows are the release's up to the window but row 0 (the PC's row 0 is not Lune's first move,
		-- see the start's describe below).
		local inStart = (started == nil or rowT > GAP) and rowT <= FROM + 1e-9
		local standing = started ~= nil and math.abs(rowT) < GAP
		local points: { [string]: { Vector3 } } = {}
		local crouchFeet: { [string]: { slide: number, low: number, own: number } } = {}
		if inCrouch then
			table.insert(
				result.crouchRows,
				{ at = (row - (crouchRow :: number)) * dt, step = step or 0, feet = crouchFeet }
			)
		end
		for _, foot in feet do
			points[foot] = {}
			local footLowest = math.huge
			local ownLowest = math.huge
			for index, corner in local_[foot] do
				local point = solved[foot] * corner
				points[foot][index] = point
				footLowest = math.min(footLowest, point.Y)
				if inStop then
					result.stopLowest = math.min(result.stopLowest, point.Y)
				end
				if inCrouch then
					result.crouchLowest = math.min(result.crouchLowest, point.Y)
				end
				if own ~= nil then
					ownLowest = math.min(ownLowest, (own[foot] * corner).Y)
					result.crouchOwnLowest = math.min(result.crouchOwnLowest, ownLowest)
				end
				if inWindow then
					result.lowest = math.min(result.lowest, point.Y)
				end
				if inStart then
					result.startLowest = math.min(result.startLowest, point.Y)
				end
				if standing then
					result.standLowest = math.min(result.standLowest, point.Y)
				end
			end
			highest = math.max(highest, footLowest)
			crouchFeet[foot] = { slide = -1, low = footLowest, own = ownLowest }
			local before = if previous ~= nil then previous[foot] else nil
			if (inWindow or inStart or inStop or inCrouch) and before ~= nil then
				local least = math.huge
				for index, point in points[foot] do
					local was = before[index]
					if point.Y <= CONTACT and was.Y <= CONTACT then
						least = math.min(least, Vector3.new(point.X - was.X, 0, point.Z - was.Z).Magnitude)
					end
				end
				if least < math.huge and inWindow and least > result.slide then
					result.slide, result.slideAt = least, rowT
				end
				if least < math.huge and inStart and least > result.startSlide then
					result.startSlide, result.startSlideAt = least, rowT
				end
				if least < math.huge and inStop and least > result.stopSlide then
					result.stopSlide, result.stopSlideAt = least, rowT
				end
				if least < math.huge then
					crouchFeet[foot].slide = least
				end
				if least < math.huge and inCrouch and least > result.crouchSlide then
					result.crouchSlide = least
					result.crouchSlideAt = (row - (crouchRow :: number)) * dt
					result.crouchFoot = foot
					result.crouchStep = step or 0
				end
			end
		end
		previous = points
		if stopEnd then
			local handle = walkHandle()
			result.stopWalk = if handle ~= nil then handle.weight else 0
			result.stopChannel = mixer._procedural.walkStopPlant ~= nil
			result.stopHighest = highest
		end

		-- Wheeling: the body at about half its walk speed, settled into it.
		local handle = walkHandle()
		local share = flat.Magnitude / walkSpeed
		if inWindow and handle ~= nil and share > 0.4 and share < 0.6 then
			result.wheelWalk = math.min(result.wheelWalk or math.huge, handle.targetWeight)
		end
	end
	onFire = nil
	driver:destroy()
	Choreo.release(client)
	return result
end

-- The take's checks: no foot corner under the field, a boar wheeling at half its walk speed drawn
-- on its walk alone, and no planted foot sliding more than footSlideStuds a 60 Hz frame (the
-- same pace a row at the take's rate: footSlideStuds x 60 / hz) plus what PENDING allows.
local function check(rig: string, off: number, result: Take, hz: number, pending: number?, wheels: boolean)
	print(
		("%s off %d @%d Hz: slide %.3f at %.3f s, lowest %.3f, walk weight wheeling %s"):format(
			rig,
			off,
			hz,
			result.slide,
			result.slideAt,
			result.lowest,
			if result.wheelWalk ~= nil then ("%.2f"):format(result.wheelWalk) else "-"
		)
	)
	-- No foot in the field: the walk's own keys stand the planted corner within contact.
	if result.lowest < -CONTACT then
		error(("a foot corner %.3f under the field (max %.2f)"):format(-result.lowest, CONTACT))
	end
	-- A body wheeling at half its walk speed is drawn on its walk alone.
	if wheels and rig == "Boar" then
		expect(result.wheelWalk).toBeCloseTo(1, 1e-6)
	end
	local bound = SLIDE * 60 / hz
	local bar = bound + (pending or 0)
	if result.slide > bar then
		error(("a planted foot slides %.3f in a row at %.3f s (max %.3f)"):format(result.slide, result.slideAt, bar))
	end
	if pending ~= nil and result.slide <= bound then
		error(("slides %.3f, within the bound %.3f: take it off PENDING"):format(result.slide, bound))
	end
end

-- What the walk start does not meet yet, by rig and off angle: how far its worst slide is past
-- footSlideStuds (rounded up to the hundredth). An entry never grows. The boar at 135 and 180 came
-- within the bound with D-574 to D-576 (0.077 and 0.076; were 0.100 and 0.113). The kobold's
-- Brute chased straight at its target while it turned, so from behind it crab-walked (0.161 and
-- 0.280 at 135 and 180, PENDING 0.07 and 0.19 on 81b8fef); it wheels round on its walk now
-- (D-598).
local PENDING: { [string]: { [number]: number } } = {
	Boar = {},
	Kobold = {},
}

describe("EnemyWalkStart: an enemy sets off on its feet (AG 392(b), D-541)", function()
	for _, case in { { rig = "Boar", offs = { 90, 135, 180 } }, { rig = "Kobold", offs = { 0, 60, 90, 135, 180 } } } do
		for _, off in case.offs do
			it(("%s set off %d deg off its target keeps its feet on the field"):format(case.rig, off), function()
				check(case.rig, off, take(case.rig, off), 60, PENDING[case.rig][off], true)
			end)
		end
	end
end)

-- The PC's own view (AO 473(a), (e) on 209875b): the replicated velocity reads short of the root's
-- move, and on a 144 Hz client the root is drawn between the server's frames. The gait paced on
-- that velocity slid a planted foot by the gap every row (on 318f0a3: the boar at 90 0.190 a 60 Hz
-- row and 0.090 a 144 Hz row, the kobold at 0, 60 and 90 0.116 and 0.059 to 0.063), and walks keyed
-- once a 60 fps frame stop and go between their keys on a 144 Hz row (the kobold at 0: 0.035 with
-- no under-read). Keyed four times a frame (D-576), the boar's chase stepping its WalkSpeed from 7
-- to 14 at once slid its hooves 0.126 on that 60 Hz row (the gait a frame behind the root). Now the
-- gait follows the root's travel (D-575) and the walk's pace eases (D-574). At 144 the bound
-- is footSlideStuds over a 144 Hz row (0.042, the PC's bar); the window is the same 0.15-0.5 s (rows
-- 22-72). The boar at 135 and 180 and the kobold at 135 and 180 are the PC's report-only takes,
-- all within the bound: the kobold's crab-walk (0.070 and 0.123, PENDING 0.03 and 0.09 on 81b8fef)
-- is gone with its wheel (D-598).
local PENDING144: { [string]: { [number]: number } } = {
	Boar = {},
	Kobold = {},
}

describe("EnemyWalkStart: the walk start as the PC sees it (AO 473(a), (e); D-574 to D-576)", function()
	for _, case in { { rig = "Boar", offs = { 90 } }, { rig = "Kobold", offs = { 0, 60, 90, 135, 180 } } } do
		for _, off in case.offs do
			it(("%s set off %d deg on a velocity that under-reads the root, 60 Hz"):format(case.rig, off), function()
				check(case.rig, off, take(case.rig, off, PC60), 60, nil, false)
			end)
		end
	end
	for _, case in { { rig = "Boar", offs = { 90, 135, 180 } }, { rig = "Kobold", offs = { 0, 60, 90, 135, 180 } } } do
		for _, off in case.offs do
			it(("%s set off %d deg on a 144 Hz client over the interpolated root"):format(case.rig, off), function()
				check(case.rig, off, take(case.rig, off, PC144), 144, PENDING144[case.rig][off], false)
			end)
		end
	end
end)

describe("EnemyWalkStart: the boar's chase eases out of its wheel (D-574)", function()
	it("takes its WalkSpeed from the wheel's 7 to 14 at paceChangeRate, never in one frame", function()
		local result = take("Boar", 90)
		local rate = AI.movement.paceChangeRate
		local boar = Harness.load("src/shared/data/enemies").byId("FrenzyBoar")
		local full = boar.moveSpeed * AI.archetypes.Charger.chaseSpeedMultiplier
		local wheel = full * AI.archetypes.Charger.wheelSpeedMultiplier
		-- It sets off wheeling at half speed (from standing its pace eases up to the wheel's from
		-- movement.startPace first, D-618).
		local start: number? = nil
		for index, pace in result.paces do
			if math.abs(pace - wheel) < 1e-9 then
				start = index
				break
			end
		end
		expect(start).toBeTruthy()
		local leftAt: number? = nil
		local reachedAt: number? = nil
		for index = (start :: number) + 1, #result.paces do
			local pace, before = result.paces[index], result.paces[index - 1]
			if math.abs(pace - before) > rate * FRAME + 1e-9 then
				error(
					("the WalkSpeed stepped %.3f to %.3f in one frame (most %.3f)"):format(before, pace, rate * FRAME)
				)
			end
			if leftAt == nil and pace > wheel + 1e-9 then
				leftAt = index
			end
			if reachedAt == nil and pace >= full - 1e-9 then
				reachedAt = index
			end
		end
		expect(leftAt).toBeTruthy()
		expect(reachedAt).toBeTruthy()
		-- 7 studs/s at paceChangeRate: (full - wheel) / rate seconds of frames.
		local frames = (reachedAt :: number) - (leftAt :: number) + 1
		expect(frames).toBe(math.ceil((full - wheel) / (rate * FRAME) - 1e-9))
	end)
end)

-- The kobold's Brute walked straight at a target behind it while it turned (160 degrees a second
-- after the 0.25 s alert turn): its root went 138 degrees off its facing at 180, under a walk whose
-- planted feet step back along the facing, and they slid 0.280 a 60 Hz row (0.161 at 135). Now it
-- wheels: more than wheelAngle off its target it walks along its facing at wheelSpeedMultiplier of
-- its pace and turns on its feet, and from within wheelAngle walks straight at it (D-598). Its
-- walk is at most wheelAngle off its facing, plus the turn of one AI tick (the walk's goal is set
-- each tick, the turn spread over the frames).
describe("EnemyWalkStart: the kobold wheels round on its feet (D-598)", function()
	for _, off in { 90, 135, 180 } do
		it(("walks at most wheelAngle off its facing from %d deg off its target"):format(off), function()
			local brute = AI.archetypes.Brute
			local most = brute.wheelAngle + brute.turnRate * AI.tickSeconds()
			local result = take("Kobold", off)
			print(("Kobold off %d: walked at most %.1f deg off its facing (most %.1f)"):format(off, result.crab, most))
			expect(result.crab <= most + 1e-6).toBe(true)
		end)
	end
end)

-- The start's own rows, from the release up to the window (AO 511: 0.2-0.32 a row, the boar's
-- hooves -0.069 and -0.074 in the field). The PC read the kobold at 0, 60 and 90 at 0.160 / 0.221 /
-- 0.101 a 60 Hz row in its window on 81b8fef, feet to -0.083, where Lune read 0.001 / 0.001 /
-- 0.059: Lune gives the PC's numbers with the PC's row 0 4 to 6 rows (0.07-0.1 s) before Lune's
-- first move (0.148-0.246 at 60 and 0.048-0.056 at 144 on 81b8fef), which puts the start's rows in
-- the PC's window; what moves the PC's root that early is Studio's to log (item 511(h)). So the
-- start is judged from the release on, whatever row the PC calls row 0, through the alert turn and
-- the boar's wheel in place before it walks. Row 0 is drawn before the root moved. Two things slid them on
-- 81b8fef. The walk joined at the idle's phase of its cycle, which for the kobold was mid-swing:
-- the crossfade pulled its feet up to 1.25 studs, 0.2-0.36 a 60 Hz row on rows 1-8 and 0.068 into
-- the field; the walk now joins at enemy.gait.startPhase, by the kobold's left mid-stance (D-599).
-- The boar's idle weight shift stood a hoof 0.067 into the field under the walk's first key (now
-- re-keyed, D-601). The server's pace was the last: the Humanoid took its full WalkSpeed on the
-- first frame (the root 0.167 a 60 Hz row for the kobold) while the Idle-Walk crossfade takes
-- locomotion.weightBlendRate (0.125 s), and the idle's feet rode the root until the walk had the
-- weight. A walk from standing now eases up from movement.startPace (D-618), and the boar steps
-- off at its own start phase (D-621). The kobold's at 0 and 180 on a 144 Hz client read 0.045 and
-- 0.050 (START_PENDING 0.01 each): the crossfade's first rows dragged the idle's right foot, still on
-- the field, toward the walk's lifted right sole 0.49 ahead; it steps off a little earlier in its
-- cycle now (D-625), the sole 0.31 ahead, and every start is within the bar (0.032 and 0.037).
-- The bar is the window's (footSlideStuds a 60 Hz frame); no
-- foot lower than the idle stood on row 0 or stride.contact, whichever is deeper. START_PENDING: how
-- far the worst slide is past that bar, by view, rig and off angle (rounded up to the hundredth);
-- START_LOW: how far the lowest corner is past its bar. Neither grows.
local START_PENDING: { [string]: { [string]: { [number]: number } } } = {
	["60"] = { Boar = {}, Kobold = {} },
	["144"] = { Boar = {}, Kobold = {} },
}
local START_LOW: { [string]: { [string]: { [number]: number } } } = {
	["60"] = { Boar = {}, Kobold = {} },
	["144"] = { Boar = {}, Kobold = {} },
}

local function startCheck(rig: string, off: number, result: Take, hz: number)
	local key = tostring(hz)
	local pending = START_PENDING[key][rig][off]
	local lowPending = START_LOW[key][rig][off]
	print(
		("%s off %d @%d Hz from the release: slide %.4f at %.3f s, lowest %.4f (stood %.4f)"):format(
			rig,
			off,
			hz,
			result.startSlide,
			result.startSlideAt,
			result.startLowest,
			result.standLowest
		)
	)
	local bound = SLIDE * 60 / hz
	if result.startSlide > bound + (pending or 0) then
		error(
			("a planted foot slides %.3f in a row at %.3f s (max %.3f)"):format(
				result.startSlide,
				result.startSlideAt,
				bound + (pending or 0)
			)
		)
	end
	if pending ~= nil and result.startSlide <= bound then
		error(
			("slides %.3f from the release, within the bound %.3f: take it off START_PENDING"):format(
				result.startSlide,
				bound
			)
		)
	end
	local floor = math.min(result.standLowest, -CONTACT)
	if result.startLowest < floor - (lowPending or 0) - 1e-6 then
		error(
			("a foot corner %.3f under the field from the release (max %.3f)"):format(
				-result.startLowest,
				-(floor - (lowPending or 0))
			)
		)
	end
	if lowPending ~= nil and result.startLowest >= floor - 1e-6 then
		error(("lowest %.3f from the release, within %.3f: take it off START_LOW"):format(result.startLowest, floor))
	end
end

describe("EnemyWalkStart: the start's first rows, from the release (AO 511; D-599, D-601, D-618)", function()
	for _, case in { { rig = "Boar", offs = { 90, 135, 180 } }, { rig = "Kobold", offs = { 0, 60, 90, 135, 180 } } } do
		for _, off in case.offs do
			it(("%s set off %d deg, 60 Hz"):format(case.rig, off), function()
				startCheck(case.rig, off, take(case.rig, off), 60)
			end)
			it(("%s set off %d deg on a 144 Hz client over the interpolated root"):format(case.rig, off), function()
				startCheck(case.rig, off, take(case.rig, off, PC144), 144)
			end)
		end
	end
end)

-- An enemy's stop (D-623, AO 511(k)). The server's Humanoid brakes the root within two frames
-- while the client's walk ran on at its slowest rate and crossfaded into the idle over
-- locomotion.weightBlendRate with the root standing: each planted foot swung about its hip from the
-- walk's stance to the idle's and the swinging foot was drawn onto the field on the way. On
-- 0ba630b, from the brake row for STOP_SECONDS: the kobold at 0 and 90 degrees 0.120 and 0.244 a
-- 60 Hz row (0.100 and 0.105 at 144), feet to -0.015 and -0.041; the boar at 60 degrees (its stop
-- before the Charge) 0.379 (0.166), hooves to -0.036 (-0.037). RigDriver's stop plant holds each
-- foot where it stood and steps them onto the idle's spots, the swinging foot first. Bars: the
-- start's (footSlideStuds a 60 Hz row, the window's; no corner under the idle's stand or
-- stride.contact, whichever is deeper), and once the stop is over the walk shows none, the plant's
-- channel is gone and every foot is down. STOP_PENDING: how far the worst slide is past the bar
-- (rounded up to the hundredth), by view, rig and off angle. Only the brake row is past it: the
-- row the server's brake lands on is drawn before the client can see the brake, so its walk ran a
-- whole row's pace over a root that moved only part of it (the kobold at 90: 0.1006 at 60 and
-- 0.0459 at 144; the boar at 60: 0.0423 at 144). An entry never grows.
local STOP_PENDING: { [string]: { [string]: { [number]: number } } } = {
	["60"] = { Boar = {}, Kobold = { [90] = 0.01 } },
	["144"] = { Boar = { [60] = 0.01 }, Kobold = { [90] = 0.01 } },
}

describe("EnemyWalkStart: an enemy's stop keeps its feet planted (AO 511(k); D-623)", function()
	for _, case in
		{
			{ rig = "Kobold", off = 0, seconds = 2.2 },
			{ rig = "Kobold", off = 90, seconds = 2.2 },
			{ rig = "Boar", off = 60, seconds = 1.2 },
		}
	do
		for _, view in { SERVER, PC144 } do
			local label = if view.interpolated then "on a 144 Hz client over the interpolated root" else "60 Hz"
			it(("%s stopping after it set off %d deg, %s"):format(case.rig, case.off, label), function()
				local result = take(case.rig, case.off, view, case.seconds)
				local key = tostring(view.hz)
				local pending = STOP_PENDING[key][case.rig][case.off]
				print(
					("%s off %d @%d Hz, the stop at %s s: slide %.4f at %.3f s, lowest %.4f (stood %.4f); after it walk %s, channel %s, highest foot %s"):format(
						case.rig,
						case.off,
						view.hz,
						if result.stopAt ~= nil then ("%.3f"):format(result.stopAt :: number) else "-",
						result.stopSlide,
						result.stopSlideAt,
						result.stopLowest,
						result.standLowest,
						tostring(result.stopWalk),
						tostring(result.stopChannel),
						if result.stopHighest ~= nil then ("%.4f"):format(result.stopHighest :: number) else "-"
					)
				)
				assert(result.stopAt ~= nil and result.stopWalk ~= nil, "the take ended before its stop did")
				local bound = SLIDE * 60 / view.hz
				local bar = bound + (pending or 0)
				if result.stopSlide > bar then
					error(
						("a planted foot slides %.3f in a row at %.3f s as it stops (max %.3f)"):format(
							result.stopSlide,
							result.stopSlideAt,
							bar
						)
					)
				end
				if pending ~= nil and result.stopSlide <= bound then
					error(
						("slides %.3f as it stops, within the bound %.3f: take it off STOP_PENDING"):format(
							result.stopSlide,
							bound
						)
					)
				end
				local floor = math.min(result.standLowest, -CONTACT)
				if result.stopLowest < floor - 1e-6 then
					error(
						("a foot corner %.3f under the field as it stops (max %.3f)"):format(-result.stopLowest, -floor)
					)
				end
				-- The swinging foot landed and the idle has the rig.
				expect(result.stopWalk).toBe(0)
				expect(result.stopChannel).toBe(false)
				expect((result.stopHighest :: number) <= CONTACT).toBe(true)
			end)
		end
	end

	it("the boar's Charge out of its stop is the Charge's: no stop plant under a full-body clip", function()
		-- Its ActionStarted played on the client as Replication plays it: the crouch comes on the
		-- brake row (the server stops the body as the wind-up starts), so the stop plant never
		-- holds a leg under it (nor under a Stagger's clip: any full-body clip lets it go).
		for _, view in { SERVER, PC144 } do
			local result = take("Boar", 60, view, 1.2, true)
			expect(table.find(result.played, "enemy/Boar/Charge") ~= nil).toBe(true)
			expect(result.channelUnderFullBody).toBe(false)
		end
	end)
end)

-- An attack out of the walk (D-632, AO 511(c)). An attack clip is authored from the idle's stand
-- and blended in over the walking legs, so the blend swept each planted foot across the field from
-- where it stood to where the clip has it (ActionStarted played as Replication plays it, on the
-- server's beat). On c3d0e8f, over the clip's first CROUCH_SECONDS: the boar's Charge slid a hoof
-- 0.509 and 0.458 a 60 Hz row out of the walk at 60 and 90 degrees (0.430 and 0.251 at 144), 0.250
-- and 0.362 at 135 and 180 (0.255, 0.181) and 0.248 out of its idle (0.114), hooves to -0.082 (its
-- own crouch -0.029); the kobold's Overhead 0.088 to 0.511 (0.093 to 0.228), feet to -0.065 (its
-- own -0.010).
-- RigDriver's attack plant holds each foot on the field point it stood on and digs the ones the
-- clip has elsewhere in, lifted, one group at a time. Bars, over the clip's first CROUCH_SECONDS
-- from its first drawn row: the walk start's (footSlideStuds a 60 Hz row, as many at 144 as its
-- share of the frame); no corner under stride.contact or the clip's own pose, whichever is deeper
-- (the Charge's crouch sinks its front right hoof 0.029 itself, inside ClipAudit's footSinkStuds:
-- its pose after the blend-in is the clip's); and by the window's end the plant has let the legs
-- go (no pose hook is left on the mixer). The boar at 0 degrees charges out of its idle; every
-- other take attacks out of the walk at its walkSpeed (the kobold's Overhead as it closes in).
-- The clip's own pose re-solved from its clock (Pose.solve) and the one Choreo drew differ by float
-- noise: 0.00003 at most over these takes.
local OWN_SLACK = 1e-4
local CROUCH_TAKES: { { rig: string, off: number, seconds: number } } = {
	{ rig = "Boar", off = 0, seconds = 1 },
	{ rig = "Boar", off = 60, seconds = 1.2 },
	{ rig = "Boar", off = 90, seconds = 1.5 },
	{ rig = "Boar", off = 135, seconds = 5.4 },
	{ rig = "Boar", off = 180, seconds = 2.6 },
	{ rig = "Kobold", off = 0, seconds = 2.1 },
	{ rig = "Kobold", off = 60, seconds = 2.1 },
	{ rig = "Kobold", off = 90, seconds = 2.2 },
	{ rig = "Kobold", off = 135, seconds = 2.4 },
	{ rig = "Kobold", off = 180, seconds = 2.8 },
}

-- The crouch's bars (above) on a take of `case` attacking.
local function crouchCheck(case: { rig: string, off: number, seconds: number }, view: View, result: Take)
	print(
		("%s off %d @%d Hz, %s from %s s (waited %s, walk %s): slide %.4f at +%.3f s (%s, root step %.4f), lowest %.4f (own %.4f), hooked %s"):format(
			case.rig,
			case.off,
			view.hz,
			tostring(result.crouchClip),
			if result.crouchAt ~= nil then ("%.3f"):format(result.crouchAt :: number) else "-",
			if result.crouchWaited ~= nil then ("%.3f"):format(result.crouchWaited :: number) else "-",
			if result.crouchWalk ~= nil then ("%.2f"):format(result.crouchWalk :: number) else "-",
			result.crouchSlide,
			result.crouchSlideAt,
			result.crouchFoot,
			result.crouchStep,
			result.crouchLowest,
			result.crouchOwnLowest,
			tostring(result.crouchHooked)
		)
	)
	assert(result.crouchHooked ~= nil, "the take ended before the attack's first CROUCH_SECONDS did")
	expect(result.crouchClip).toBe(if case.rig == "Boar" then "enemy/Boar/Charge" else "enemy/Kobold/Overhead")
	local bound = SLIDE * 60 / view.hz
	if result.crouchSlide > bound then
		error(
			("a planted foot slides %.3f in a row %.3f s into the attack (max %.3f)"):format(
				result.crouchSlide,
				result.crouchSlideAt,
				bound
			)
		)
	end
	local floor = math.min(result.crouchOwnLowest, -CONTACT)
	if result.crouchLowest < floor - OWN_SLACK then
		error(
			("a foot corner %.3f under the field as the attack comes in (max %.3f)"):format(
				-result.crouchLowest,
				-floor
			)
		)
	end
	expect(result.crouchHooked).toBe(false)
end

describe("EnemyWalkStart: an attack out of the walk keeps its feet planted (AO 511(c); D-632)", function()
	for _, case in CROUCH_TAKES do
		for _, view in { SERVER, PC144 } do
			local label = if view.interpolated then "on a 144 Hz client over the interpolated root" else "60 Hz"
			it(("%s attacking after it set off %d deg, %s"):format(case.rig, case.off, label), function()
				crouchCheck(case, view, take(case.rig, case.off, view, case.seconds, true))
			end)
		end
	end
end)

-- An attack out of the walk as the PC draws it (AT 532(a), (h), (k); D-652). The PC draws an
-- enemy's root 0.13 to 0.27 s behind the server (the replicated root's interpolation: the client's
-- row 0 came 8 to 16 rows at 60 and 20 to 27 at 144 after the server's first MoveTo), while
-- ActionStarted comes in on the server's beat: the attack clip came in with the drawn body still
-- walking to where the server's body began its wind-up, and the attack plant (built for the brake
-- row) dug the clip's legs in under a root that walked on. Here the root is drawn LAG_60 (60 Hz)
-- and LAG_144 (144 Hz) behind the server and ActionStarted and Telegraph play as the server sends
-- them. On 6ac48e7, over the clip's first CROUCH_SECONDS: PENDING_LAG's numbers.
-- RigDriver's attack wait holds the clip, hidden, while the drawn body walks to the Telegraph's
-- origin: the crouch's bars as above, from the clip's first drawn row, and it waits at most
-- attackWaitSeconds. The boar's turning walk keeps the walk start's window bars on such a client,
-- attacking: on 6ac48e7 the Charge came in over the window's last rows at 90 deg (0.055 a 144 Hz
-- row, bar 0.042; 0.044 at 60).
local LAG_60, LAG_144 = 0.2, 0.17
local PC60_LAG: View = { hz = 60, interpolated = true, lag = FRAME + LAG_60, arrival = true }
local PC144_LAG: View =
	{ hz = 144, interpolated = true, lag = FRAME + LAG_144, arrival = true, share = underRead(0.5, 0.95) }

describe("EnemyWalkStart: an attack waits for the body the PC draws behind the server (AT 532; D-652)", function()
	for _, case in CROUCH_TAKES do
		for _, view in { PC60_LAG, PC144_LAG } do
			it(
				("%s attacking after it set off %d deg, its root drawn behind at %d Hz"):format(
					case.rig,
					case.off,
					view.hz
				),
				function()
					local result = take(case.rig, case.off, view, case.seconds + (view.lag :: number), true)
					crouchCheck(case, view, result)
					expect(
						(result.crouchWaited :: number) <= ChoreoData.enemy.gait.attackWaitSeconds + 1 / view.hz + 1e-9
					).toBe(true)
				end
			)
		end
	end
	for _, off in { 90, 135, 180 } do
		for _, view in { PC60_LAG, PC144_LAG } do
			it(
				("the boar set off %d deg keeps its feet over the window, its root drawn behind at %d Hz"):format(
					off,
					view.hz
				),
				function()
					check("Boar", off, take("Boar", off, view, 1.5 + (view.lag :: number), true), view.hz, nil, false)
				end
			)
		end
	end
end)

-- A stop the root walks off from mid-step (D-623): the client copy alone, its root carried at
-- the kobold's walkSpeed along its facing for a second, standing for 0.1 s (a foot in its step),
-- then walking on. The stop plant takes the legs on the row after the root stood and lets them go
-- over locomotion.weightBlendRate once it walks on, so a foot caught mid-step comes back to the walk
-- without a pop: no leg's hip turns more than popDegrees a 60 Hz frame (as many a row at 144 as
-- its share of the frame), the plant's channel is gone and the walk shows whole.
local function walkOffMidStop(hz: number): { engaged: boolean, goneAfter: number?, walk: number, worstTurn: number }
	local client = RigBuilder.build("Kobold")
	local root = client.PrimaryPart :: BasePart
	local humanoid = client:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.FloorMaterial = Enum.Material.Plastic
	humanoid.MoveDirection = Vector3.zero
	local at = Vector3.new(0, Rigs.Kobold.hipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.new(at)
	root.Position = at
	root.AssemblyLinearVelocity = Vector3.zero
	local animator = Choreo.get(client)
	local driver = Locomotion.attach(animator, client, { phase = 0 })
	local mixer = animator.mixer :: any
	local hips: { string } = {}
	for _, joint in Rigs.Kobold.joints do
		if table.find(FEET.Kobold, joint.part1) ~= nil then
			table.insert(hips, joint.name)
		end
	end
	local speed = Rigs.Kobold.walkSpeed
	local dt = 1 / hz
	local standFrom, standTo = hz, hz + math.floor(0.1 * hz + 0.5)
	local result = { engaged = false, goneAfter = nil :: number?, walk = 0, worstTurn = 0 }
	local last: { [string]: { number } } = {}
	for row = 1, standTo + 2 * hz do
		clientNow += dt
		animator:step(dt)
		local shown = mixer:lastOffsets()
		for _, name in hips do
			local offset = shown[name]
			local rot = if offset ~= nil then offset.rot else { 0, 0, 0 }
			local before = last[name]
			if before ~= nil and row > 1 then
				for axis = 1, 3 do
					result.worstTurn = math.max(result.worstTurn, math.abs(rot[axis] - before[axis]))
				end
			end
			last[name] = { rot[1], rot[2], rot[3] }
		end
		local channel = mixer._procedural.walkStopPlant ~= nil
		if row > standFrom and row <= standTo and channel then
			result.engaged = true
		end
		if row > standTo and not channel and result.goneAfter == nil then
			result.goneAfter = (row - standTo) * dt
		end
		local moving = row < standFrom or row >= standTo
		if moving then
			at += Vector3.new(0, 0, -speed * dt)
		end
		local cframe = CFrame.new(at)
		root.CFrame = cframe
		root.Position = at
		root.AssemblyLinearVelocity = if moving then cframe.LookVector * speed else Vector3.zero
		humanoid.MoveDirection = if moving then cframe.LookVector else Vector3.zero
	end
	for _, handle in mixer:handles() do
		if handle.clipId == ChoreoData.rigs.Kobold.walk and not handle.stopping and not handle.fallback then
			result.walk = handle.weight
		end
	end
	driver:destroy()
	Choreo.release(client)
	return result
end

describe("EnemyWalkStart: a stop the root walks off from mid-step (D-623)", function()
	for _, hz in { 60, 144 } do
		it(("at %d Hz the stop's legs go back to the walk without a pop"):format(hz), function()
			local result = walkOffMidStop(hz)
			print(
				("Kobold walks off mid-stop @%d Hz: engaged %s, channel gone %s s after, walk %.2f, worst hip turn %.2f deg a row"):format(
					hz,
					tostring(result.engaged),
					tostring(result.goneAfter),
					result.walk,
					result.worstTurn
				)
			)
			expect(result.engaged).toBe(true)
			expect(result.goneAfter ~= nil).toBe(true)
			expect((result.goneAfter :: number) <= 1 / ChoreoData.locomotion.weightBlendRate + 3 / hz + GAP).toBe(true)
			expect(result.walk).toBe(1)
			expect(result.worstTurn <= Dev.review.audit.popDegrees * 60 / hz).toBe(true)
		end)
	end
end)

-- A boar wheeling on its walk (D-619): the server turns its root about its own axis at the
-- Charger's turnRate (110 degrees a second) while it walks, and the walk's planted hooves, 1.0 to
-- 2.3 studs off that axis, swung round it with the root: 0.056 a 144 Hz row and 0.070 a 60 Hz row
-- on 4c725c9 at its full walk speed. RigDriver's walking-turn plant (WalkTurnPlant) takes the turn
-- back at each planted hoof's hip. Drawn here on the client alone: the root carried at the rig's
-- walkSpeed along its facing and turned at the turn rate each row, Locomotion's own tracker pacing
-- the gait, the walk's planted hooves read after its first second (the gait settled).
local function wheelSlide(hz: number, plant: boolean): number
	local plants = ChoreoData.enemy.gait.turnPlant
	local config = plants.Boar
	if not plant then
		plants.Boar = nil
	end
	local client = RigBuilder.build("Boar")
	local root = client.PrimaryPart :: BasePart
	local humanoid = client:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.FloorMaterial = Enum.Material.Plastic
	humanoid.MoveDirection = Vector3.zero
	local at = Vector3.new(0, Rigs.Boar.hipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.new(at)
	root.Position = at
	root.AssemblyLinearVelocity = Vector3.zero
	local animator = Choreo.get(client)
	local driver = Locomotion.attach(animator, client, { phase = 0 })
	plants.Boar = config
	local spin = math.rad(AI.archetypes.Charger.turnRate)
	local speed = Rigs.Boar.walkSpeed
	local dt = 1 / hz
	local local_: { [string]: { Vector3 } } = {}
	for _, foot in FEET.Boar do
		local_[foot] = corners((client:FindFirstChild(foot) :: BasePart).Size)
	end
	local yaw = 0
	local previous: { [string]: { Vector3 } }? = nil
	local worst = 0
	for row = 1, 2 * hz do
		clientNow += dt
		animator:step(dt)
		yaw += spin * dt
		at += CFrame.Angles(0, yaw, 0).LookVector * speed * dt
		local cframe = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
		root.CFrame = cframe
		root.Position = at
		root.AssemblyLinearVelocity = cframe.LookVector * speed
		humanoid.MoveDirection = cframe.LookVector
		local solved = solve(client, cframe)
		local points: { [string]: { Vector3 } } = {}
		for _, foot in FEET.Boar do
			points[foot] = {}
			for index, corner in local_[foot] do
				points[foot][index] = solved[foot] * corner
			end
			local before = if previous ~= nil then previous[foot] else nil
			if before ~= nil and row > hz then
				local least = math.huge
				for index, point in points[foot] do
					local was = before[index]
					if point.Y <= CONTACT and was.Y <= CONTACT then
						least = math.min(least, Vector3.new(point.X - was.X, 0, point.Z - was.Z).Magnitude)
					end
				end
				if least < math.huge then
					worst = math.max(worst, least)
				end
			end
		end
		previous = points
	end
	driver:destroy()
	Choreo.release(client)
	return worst
end

describe("EnemyWalkStart: a wheeling boar's planted hooves hold the field (D-619)", function()
	for _, hz in { 60, 144 } do
		it(("at %d Hz the turn plant takes back over half the wheel's slide, within the bar"):format(hz), function()
			local planted = wheelSlide(hz, true)
			local free = wheelSlide(hz, false)
			print(
				("Boar wheeling at %d Hz: planted hooves slide %.4f a row (%.4f without the plant)"):format(
					hz,
					planted,
					free
				)
			)
			expect(planted <= SLIDE * 60 / hz).toBe(true)
			expect(planted <= free / 2).toBe(true)
		end)
	end
end)
