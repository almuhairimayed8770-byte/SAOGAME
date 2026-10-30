--!strict
--[[
	The walk into the stand ring when it cannot get there, and the ask a player takes over (316(b),
	317(a), round D on the owner's PC): a wall across the walk's last leg held the body 4.1 studs
	from the spot while the auto-walk pushed it into the wall at the sprint for the whole
	walk.timeoutSeconds (15 s), then "Walk failed"; and "Walk into the ring yourself" (a movement
	key handed the walk over) timed out to "Walk failed" after the same 15 s, though the player had
	not pressed P again. A walk the world stops lets go of the body within walk.blockedSeconds of
	its last progress and hands the ring and the ask to the player, as a movement key does; the
	ask a player holds stays until the body stands in the ring at rest, or P or J.

	The harness is tests/client/Capture.spec.luau's: the real panel (Capture.client.luau) on a
	fake body that runs at the run or sprint speed along each frame's Move, and the staging
	server's fake that stages by the real ring rule (DevStageLogic). The wall is a plane the body
	cannot cross: the frame it would, it stands at the plane and makes no more progress.
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local Dev = Harness.load("src/shared/data/dev")
local Overhead = Harness.load("src/shared/clips/enemy/Kobold/Overhead")
local Charge = Harness.load("src/shared/clips/enemy/Boar/Charge")
local World = Harness.load("src/shared/data/world")
local StageLogic = Harness.load("src/server/dev/DevStageLogic")
local Combat = Harness.load("src/shared/data/combat")

local NODE = "src/client/dev/Capture"
local FILE = "src/client/dev/Capture.client.luau"
local FRAME = 1 / 60
local CAPTURE = Dev.capture
local KEYS = CAPTURE.hotkeys
local STAGE = CAPTURE.stage
local WALK = CAPTURE.walk
local HIP = 2 -- the player's Humanoid.HipHeight in this world
local ROOT_SIZE = Vector3.new(2, 2, 1)
local ROOT_OFFSET = HIP + ROOT_SIZE.Y / 2 + World.spawn.groundEpsilon
local SPEED = 16 -- studs per second the fake body moves along a Move
local SPRINT = Combat.maxSpeedStudsPerSecond -- the same while the sprint is held

local function shotIndex(id: string): number
	for index, shot in CAPTURE.shots do
		if shot.id == id then
			return index
		end
	end
	error("no shot " .. id)
end

-- The staging server as the panel meets it (DevStage.server.luau's handler): one staging at a
-- time (a request while one runs is refused busy), and, when paced, one request a player per
-- 1 / requestsPerSecond (a faster one is refused before anything else). A staging takes
-- stagingSeconds; onStage runs while it does (a key pressed mid-staging).
type Server = {
	paced: boolean,
	stagingSeconds: number,
	busyUntil: number,
	lastAt: number?,
	onStage: (() -> ())?,
	released: number,
	-- Answers "stage" instead of world.reply (the ring rule, DevStage's walk reply).
	stage: ((shotId: string) -> any)?,
}

-- The local character as the walk meets it: a root that moves SPEED studs a second along each
-- frame's Humanoid:Move, times the move's length up to 1 (a part-pushed stick walks slower; SPRINT
-- while the sprint is held, the Humanoid's WalkSpeed with it; none: it stops, after `carry` studs
-- more along its last move once, and `slide` studs more after every stop), standing on the field,
-- the ledge's top or its ramp; `stuck` keeps it where it is.
type Body = {
	root: any,
	humanoid: any,
	moves: { { direction: Vector3, relative: boolean?, at: number } },
	pending: Vector3?,
	lastDirection: Vector3?,
	carry: number,
	slide: number,
	coast: number,
	sprinting: boolean,
	stuck: boolean,
	trail: { Vector3 },
}

type World = {
	clock: { now: number },
	server: Server,
	gui: any,
	counter: () -> any,
	counterText: () -> string,
	prompt: () -> any,
	panel: () -> any,
	-- Runs `count` rendered frames of `dt` seconds each (frames runs them at 1/60).
	framesAt: (count: number, dt: number) -> (),
	status: () -> string,
	invokes: { { action: string, shotId: string?, at: number } },
	reply: { [string]: any },
	stages: { { view: any, target: any, side: number? } },
	lockOns: { any },
	clears: number,
	-- The lock as the fake TargetController holds it (TargetController.current), by id.
	locked: { id: number? },
	handled: { { action: string, state: string, at: number } },
	-- Each CharacterController.cancelArt: its slot and how many input-path calls came before it.
	cancels: { { slot: number, handledBefore: number } },
	input: any,
	userInput: any,
	replication: any,
	-- The client's latency lead the fake Telegraphs reports (Telegraphs.glintLead, D-289).
	lead: { seconds: number },
	-- The local body's state as the fake character controller reports it (CharacterController.state).
	bodyState: { value: string },
	-- With a server clock (Options.clockLag): how long a request takes to reach the staging server;
	-- each staging reply carries the server's clock at its receipt (receivedAt).
	link: { up: number },
	key: (name: string) -> (),
	frames: (count: number) -> (),
	seconds: (seconds: number) -> (),
	-- Runs until the take starts (the countdown done), returning the frame the counter first shows.
	untilRecording: () -> (),
	firstShown: { text: string? },
	kobold: any,
	boar: any,
	body: Body,
	ring: () -> any,
	-- Stands the body with its feet on the floor under (x, z).
	standAt: (x: number, z: number) -> (),
	steps: { { name: string, priority: number, fn: (number) -> () } },
}

-- `clockLag`: the client has a server clock (workspace:GetServerTimeNow) that many seconds behind
-- the server's, and the staging server stamps each reply with its clock at receipt.
type Options = { remote: boolean?, capture: any, clockLag: number? }

-- The floor under (x, z): the ledge's top, its ramp, or the field.
local function floorAt(x: number, z: number): number
	local ledge = STAGE.ledge
	local top = ledge.position[2] + ledge.size[2] / 2
	if StageLogic.onLedge(ledge, x, z) then
		return top
	end
	if StageLogic.onRamp(ledge, x, z) then
		local edge = ledge.position[3] + ledge.size[3] / 2
		return top - (z - edge) * ledge.ramp.size[2] / ledge.ramp.size[3]
	end
	return STAGE.area.position[2]
end

-- Moves the body by one frame: along this frame's Move, else on along its carry, else at rest.
local function stepBody(body: Body, dt: number)
	local root = body.root
	local direction = body.pending
	body.pending = nil
	local step = Vector3.zero
	local speed = if body.sprinting then SPRINT else SPEED
	if direction ~= nil and not body.stuck then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		step = if flat.Magnitude > 0 then flat.Unit * speed * math.min(flat.Magnitude, 1) * dt else Vector3.zero
		body.lastDirection = flat
		body.coast = body.slide
	elseif direction == nil and body.carry + body.coast > 0 and body.lastDirection ~= nil then
		local distance = math.min(body.carry + body.coast, speed * dt)
		local fromCarry = math.min(body.carry, distance)
		body.carry -= fromCarry
		body.coast -= distance - fromCarry
		step = (body.lastDirection :: Vector3).Unit * distance
	end
	local x, z = root.Position.X + step.X, root.Position.Z + step.Z
	root.Position = Vector3.new(x, floorAt(x, z) + ROOT_OFFSET, z)
	-- Turned to its move (AutoRotate), and still facing the same way at rest.
	local facing = body.lastDirection
	root.CFrame = if facing ~= nil and facing.Magnitude > 0
		then CFrame.lookAt(root.Position, root.Position + facing)
		else root.CFrame.Rotation + root.Position
	root.AssemblyLinearVelocity = step / dt
	table.insert(body.trail, root.Position)
end

local function load(options: Options?): World
	local opts: Options = options or { remote = true, capture = true }
	local world: World = nil :: any
	local clock = { now = 10 }
	local renderStepped = Signal.new()
	local inputBegan = Signal.new()
	local playerGui = Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	local player = {
		Character = nil :: any,
		CharacterAdded = Signal.new(),
		WaitForChild = function(_self: any, name: string): any
			return if name == "PlayerGui" then playerGui else nil
		end,
	}
	-- The staged target 9 studs ahead of the stand spot (the fight's kobold), and a second staged
	-- enemy (the fight's boar) out to the side; a test moves their roots.
	local kobold = {
		id = 21,
		kind = "Enemy",
		model = { Name = "Kobold", PrimaryPart = { Position = Vector3.new(0, 3, -19) } },
	}
	local boar = {
		id = 22,
		kind = "Enemy",
		model = { Name = "Boar", PrimaryPart = { Position = Vector3.new(-12, 3, -10) } },
	}
	local invokes: { { action: string, shotId: string?, at: number } } = {}
	local reply: { [string]: any } = { ok = true, targetId = 21, ids = { 21 } }
	local server: Server = { paced = false, stagingSeconds = 0, busyUntil = -math.huge, released = 0 }
	local link = { up = 0 }
	-- The reply as it leaves the server: with a server clock, stamped with the server's clock at its
	-- receipt (DevStage's receivedAt), a request `link.up` after it left the client.
	local function stamped(answer: any, receivedAt: number): any
		if opts.clockLag == nil or typeof(answer) ~= "table" then
			return answer
		end
		local copy = table.clone(answer)
		copy.receivedAt = receivedAt
		return copy
	end
	local remote = {
		ClassName = "RemoteFunction",
		IsA = function(_self: any, className: string): boolean
			return className == "RemoteFunction"
		end,
		InvokeServer = function(_self: any, action: string, shotId: string?): any
			table.insert(invokes, { action = action, shotId = shotId, at = clock.now })
			local receivedAt = clock.now + link.up
			if server.paced then
				local last = server.lastAt
				if last ~= nil and clock.now - last < 1 / CAPTURE.stage.requestsPerSecond then
					return stamped({ ok = false, error = "too many requests" }, receivedAt)
				end
				server.lastAt = clock.now
			end
			if clock.now < server.busyUntil then
				return stamped({ ok = false, error = "busy: a staging is still running" }, receivedAt)
			end
			if action == "stage" then
				server.busyUntil = clock.now + server.stagingSeconds
				local hook = server.onStage
				server.onStage = nil
				if hook ~= nil then
					hook()
				end
				-- The reply comes when the staging is done.
				clock.now = math.max(clock.now, server.busyUntil)
				local answer = server.stage
				return stamped(if answer ~= nil then answer(shotId :: string) else world.reply, receivedAt)
			end
			if action == "release" then
				server.released += 1
			end
			return stamped({ ok = true }, receivedAt)
		end,
	}
	local realReplicated = Harness.game():GetService("ReplicatedStorage")
	local replicated = {
		WaitForChild = function(_self: any, name: string): any
			return realReplicated:WaitForChild(name)
		end,
		FindFirstChild = function(_self: any, name: string): any
			if name == CAPTURE.stage.remoteName and opts.remote == true then
				return remote
			end
			return nil
		end,
	}
	-- The keys this spec presses are taps: none is still down by the next frame.
	local userInput = {
		InputBegan = inputBegan,
		MouseIconEnabled = true,
		IsKeyDown = function(_self: any, _code: Enum.KeyCode): boolean
			return false
		end,
	}
	local stages: { { view: any, target: any, side: number? } } = {}
	local steps: { { name: string, priority: number, fn: (number) -> () } } = {}
	local body: Body = nil :: any
	body = {
		root = {
			Position = Vector3.zero,
			CFrame = CFrame.new(),
			Size = ROOT_SIZE,
			AssemblyLinearVelocity = Vector3.zero,
		},
		humanoid = {
			HipHeight = HIP,
			WalkSpeed = SPEED,
			Move = function(_self: any, direction: Vector3, relative: boolean?)
				table.insert(body.moves, { direction = direction, relative = relative, at = clock.now })
				body.pending = direction
			end,
		},
		moves = {},
		pending = nil,
		lastDirection = nil,
		carry = 0,
		slide = 0,
		coast = 0,
		sprinting = false,
		stuck = false,
		trail = {},
	}
	player.Character = {
		PrimaryPart = body.root,
		FindFirstChildOfClass = function(_self: any, className: string): any
			return if className == "Humanoid" then body.humanoid else nil
		end,
	} :: any
	local lockOns: { any } = {}
	local locked: { id: number? } = { id = nil }
	local handled: { { action: string, state: string, at: number } } = {}
	local cancels: { { slot: number, handledBefore: number } } = {}
	local camera = {
		setStage = function(view: any, target: any, side: number?)
			table.insert(stages, { view = view, target = target, side = side })
		end,
	}
	local target = {
		lockOn = function(id: number?): boolean
			table.insert(lockOns, id or "nil")
			locked.id = id
			return true
		end,
		clear = function()
			world.clears += 1
			locked.id = nil
		end,
		current = function(): any
			return if locked.id ~= nil then { id = locked.id } else nil
		end,
	}
	local input = {
		handle = function(action: string, state: any, _object: any)
			table.insert(handled, { action = action, state = state.Name, at = clock.now })
			if action == WALK.sprintAction then
				body.sprinting = state == Enum.UserInputState.Begin
				body.humanoid.WalkSpeed = if body.sprinting then SPRINT else SPEED
			end
		end,
	}
	local tracker = {
		get = function(id: number): any
			return if id == kobold.id then kobold elseif id == boar.id then boar else nil
		end,
	}
	local replication = { clipEvent = Signal.new(), hit = Signal.new() }
	local lead = { seconds = 0 }
	local telegraphs = {
		glintLead = function(): number
			return lead.seconds
		end,
	}
	local clipLibrary = {
		get = function(id: string): any
			if id == Overhead.id then
				return Overhead
			elseif id == Charge.id then
				return Charge
			end
			error("no clip " .. id)
		end,
	}
	local bodyState = { value = "Idle" }
	local character = {
		setCaptureTimeScale = function(_scale: number): boolean
			return true
		end,
		state = function(): string
			return bodyState.value
		end,
		cancelArt = function(slot: number)
			table.insert(cancels, { slot = slot, handledBefore = #handled })
		end,
	}
	local siblings = {
		load = function(_parent: any, path: string): (any, boolean)
			if path == "controllers.CharacterController" then
				return character, true
			end
			return {}, false
		end,
		call = function(module: any, name: string, ...: any): any
			local fn = rawget(module, name)
			return if typeof(fn) == "function" then fn(...) else nil
		end,
	}
	local fakes: { [string]: any } = {
		CameraController = camera,
		TargetController = target,
		InputController = input,
		EntityTracker = tracker,
		Replication = replication,
		Telegraphs = telegraphs,
		ClipLibrary = clipLibrary,
		Siblings = siblings,
	}
	local services: { [string]: any } = {
		Players = { LocalPlayer = player },
		ReplicatedStorage = replicated,
		RunService = {
			RenderStepped = renderStepped,
			BindToRenderStep = function(_self: any, name: string, priority: number, fn: (number) -> ())
				table.insert(steps, { name = name, priority = priority, fn = fn })
				table.sort(steps, function(a: any, b: any): boolean
					return a.priority < b.priority
				end)
			end,
		},
		UserInputService = userInput,
		CollectionService = {
			GetTagged = function(): { any }
				return {}
			end,
		},
	}
	-- A real Workspace folder, so the ring's disc has somewhere to go.
	local workspaceFolder = Instance.new("Folder")
	workspaceFolder.Name = "Workspace"
	if opts.capture ~= nil then
		workspaceFolder:SetAttribute(Dev.attributes.capture, opts.capture)
	end
	local env = Harness.environment()
	env.script = Harness.node(NODE)
	env.require = function(node: any): any
		return fakes[node.Name] or Harness.loadModule(node)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name] or error("no service " .. name)
		end,
	}
	env.workspace = workspaceFolder
	local clockLag = opts.clockLag
	if clockLag ~= nil then
		-- The client's Workspace with its server clock (the fight stages no walk, so no disc).
		env.workspace = {
			GetAttribute = function(_self: any, name: string): any
				return workspaceFolder:GetAttribute(name)
			end,
			GetServerTimeNow = function(_self: any): number
				return clock.now - clockLag
			end,
		}
	end
	env.task = {
		spawn = function(fn: (...any) -> (), ...: any)
			fn(...)
		end,
		defer = function(fn: (...any) -> (), ...: any)
			fn(...)
		end,
		wait = function(seconds: number?): number
			local dt = if seconds ~= nil and seconds > 0 then seconds else FRAME
			clock.now += dt
			return dt
		end,
	}
	env.os = {
		clock = function(): number
			return clock.now
		end,
	}

	local function find(name: string): any
		local gui = playerGui:FindFirstChild(CAPTURE.panel.screenGuiName)
		return if gui ~= nil then gui:FindFirstChild(name) else nil
	end
	local firstShown: { text: string? } = { text = nil }
	world = {
		clock = clock,
		server = server,
		gui = playerGui,
		counter = function(): any
			return find("Counter")
		end,
		counterText = function(): string
			return (find("Counter") :: any).Text.Text
		end,
		prompt = function(): any
			return find("Prompt")
		end,
		panel = function(): any
			return find("Panel")
		end,
		framesAt = function(count: number, dt: number)
			for _ = 1, count do
				clock.now += dt
				for _, step in steps do
					step.fn(dt)
				end
				stepBody(body, dt)
				renderStepped:Fire(dt)
			end
		end,
		status = function(): string
			local panel = find("Panel")
			local best = ""
			for _, child in panel:GetChildren() do
				if child:IsA("TextLabel") and child.LayoutOrder == 104 then
					best = child.Text
				end
			end
			return best
		end,
		invokes = invokes,
		reply = reply,
		stages = stages,
		lockOns = lockOns,
		clears = 0,
		locked = locked,
		handled = handled,
		cancels = cancels,
		input = input,
		userInput = userInput,
		replication = replication,
		lead = lead,
		bodyState = bodyState,
		link = link,
		key = function(name: string)
			inputBegan:Fire(
				{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = (Enum.KeyCode :: any)[name] },
				false
			)
		end,
		frames = function(count: number)
			for _ = 1, count do
				clock.now += FRAME
				local counterBox = find("Counter")
				local wasVisible = counterBox ~= nil and counterBox.Visible
				-- The bound render steps by priority, the body's physics, then RenderStepped.
				for _, step in steps do
					step.fn(FRAME)
				end
				stepBody(body, FRAME)
				renderStepped:Fire(FRAME)
				if counterBox ~= nil and counterBox.Visible and not wasVisible and firstShown.text == nil then
					firstShown.text = counterBox.Text.Text
				end
			end
		end,
		seconds = function(seconds: number)
			world.frames(math.round(seconds / FRAME))
		end,
		untilRecording = function()
			for _ = 1, math.ceil((CAPTURE.countdownSeconds + 1) / FRAME) do
				world.frames(1)
				local counterBox = find("Counter")
				if counterBox ~= nil and counterBox.Visible then
					return
				end
			end
			error("the take never started")
		end,
		firstShown = firstShown,
		kobold = kobold,
		boar = boar,
		body = body,
		ring = function(): any
			return workspaceFolder:FindFirstChild(WALK.ring.name)
		end,
		standAt = function(x: number, z: number)
			body.root.Position = Vector3.new(x, floorAt(x, z) + ROOT_OFFSET, z)
			body.root.CFrame = body.root.CFrame.Rotation + body.root.Position
			body.root.AssemblyLinearVelocity = Vector3.zero
		end,
		steps = steps,
	}
	-- On the stage area's spot until a test stands it elsewhere.
	world.standAt(STAGE.area.position[1], STAGE.area.position[3])
	luau.load(Harness.readFile(FILE), { debugName = FILE, environment = env :: any })()
	return world
end

local function goTo(world: World, id: string)
	for _ = 1, shotIndex(id) - 1 do
		world.key(KEYS.nextShot)
	end
end

local function count(list: { any }, predicate: (any) -> boolean): number
	local n = 0
	for _, item in list do
		if predicate(item) then
			n += 1
		end
	end
	return n
end

local function ringServer(world: World)
	world.server.stage = function(shotId: string): any
		local shot = CAPTURE.shots[shotIndex(shotId)]
		local open = shot.stage.open
		local ring = StageLogic.ring(open, STAGE)
		local at = world.body.root.Position
		if StageLogic.inRing(ring, at.X, at.Y - ROOT_OFFSET, at.Z) then
			return { ok = true, targetId = world.kobold.id, ids = { world.kobold.id } }
		end
		local walk = table.clone(ring) :: any
		walk.path = StageLogic.route(open, STAGE, true, at.X, at.Z)
		return { ok = false, error = "walk into the ring first", walk = walk }
	end
end

local function stageAsks(world: World): { any }
	local list = {}
	for _, entry in world.invokes do
		if entry.action == "stage" then
			table.insert(list, entry)
		end
	end
	return list
end

-- Runs frames until the countdown shows or `seconds` pass; true when it showed.
local function untilCountdown(world: World, seconds: number): boolean
	for _ = 1, math.ceil(seconds / FRAME) do
		world.frames(1)
		local panel = world.gui:FindFirstChild(CAPTURE.panel.screenGuiName):FindFirstChild("Panel")
		for _, child in panel:GetChildren() do
			if child:IsA("TextLabel") and child.LayoutOrder == 102 and child.Visible then
				return true
			end
		end
	end
	return false
end

-- The wall across the last leg (from the approach at z -4 to the spot at z -10): the body stands
-- 4.1 studs from the spot against it, as on the owner's PC.
local SPOT = STAGE.area.position
local WALL_Z = SPOT[3] + 4.1

-- One frame with the wall: a body that would cross the plane stands at it, stuck.
local function frameAgainstWall(world: World): boolean
	world.frames(1)
	local root = world.body.root
	if root.Position.Z < WALL_Z and math.abs(root.Position.X - SPOT[1]) < 4 then
		world.standAt(root.Position.X, WALL_Z)
		world.body.stuck = true
		return true
	end
	return world.body.stuck
end

local function sprintEnds(world: World): number
	return count(world.handled, function(entry: any): boolean
		return entry.action == WALK.sprintAction and entry.state == "End"
	end)
end

-- Walks from (25, 30) into art-horizontal's ring until the wall stops the body; returns the
-- world, the moves the walk made up to blockedSeconds after the stop, and the clock then.
local function blockedWalk(): (World, number)
	local world = load()
	ringServer(world)
	goTo(world, "art-horizontal")
	world.standAt(25, 30)
	world.key(KEYS.startCountdown)
	expect(#stageAsks(world)).toBe(1)
	local stopped = false
	for _ = 1, math.ceil(WALK.timeoutSeconds / FRAME) do
		if frameAgainstWall(world) then
			stopped = true
			break
		end
	end
	expect(stopped).toBe(true)
	-- The walk's last moves land inside blockedSeconds of the stop.
	world.seconds(WALK.blockedSeconds + 2 * FRAME)
	return world, #world.body.moves
end

describe("Capture: a walk the world stops hands the ring to the player (316(b))", function()
	it("lets go of a body held against a wall on the last leg within walk.blockedSeconds", function()
		local world, moves = blockedWalk()
		world.seconds(1)
		print(
			("[316(b) wall] stopped %.2f studs from the spot; %d moves in the second after blockedSeconds; sprint let go %d times; status %q"):format(
				math.abs(world.body.root.Position.Z - SPOT[3]),
				#world.body.moves - moves,
				sprintEnds(world),
				world.status()
			)
		)
		expect(#world.body.moves).toBe(moves)
		expect(sprintEnds(world)).toBeGreaterThan(0)
		-- The ring and the ask stay, with the player told to walk in: never staged outside.
		expect(world.ring() ~= nil).toBe(true)
		expect(world.status():find("blocked", 1, true)).never.toBeNil()
		expect(world.status():find("yourself", 1, true)).never.toBeNil()
		expect(world.status():find("studs from the spot", 1, true)).never.toBeNil()
		expect(#stageAsks(world)).toBe(1)
		-- The player takes it (a movement key) and stays outside past the walk's timeout: the ask
		-- is theirs, never "Walk failed".
		world.key(WALK.cancelKeys[1])
		world.seconds(WALK.timeoutSeconds + 1)
		expect(world.ring() ~= nil).toBe(true)
		expect(world.status():find("Walk failed", 1, true)).toBeNil()
		expect(#world.body.moves).toBe(moves)
		expect(#stageAsks(world)).toBe(1)
		-- The player walks round the wall into the ring: it stages.
		world.body.stuck = false
		world.standAt(SPOT[1] + 1, SPOT[3])
		expect(untilCountdown(world, 2)).toBe(true)
		expect(#stageAsks(world)).toBe(2)
	end)

	it("ends a blocked walk nobody takes at the timeout, naming the block, never staged outside", function()
		local world, moves = blockedWalk()
		world.seconds(WALK.timeoutSeconds)
		expect(world.ring()).toBeNil()
		local status = world.status()
		expect(status:find("Walk failed", 1, true)).never.toBeNil()
		expect(status:find("blocked", 1, true)).never.toBeNil()
		expect(status:find("studs from the spot", 1, true)).never.toBeNil()
		expect(#world.body.moves).toBe(moves)
		expect(#stageAsks(world)).toBe(1)
	end)

	it("never reads the correction's creep in as blocked", function()
		local world = load()
		ringServer(world)
		goTo(world, "art-horizontal")
		-- Beside the spot, outside the ring: the new walk is a correction walked in from here.
		world.standAt(SPOT[1], SPOT[3] + STAGE.standRadius + 0.5)
		world.key(KEYS.startCountdown)
		expect(untilCountdown(world, WALK.timeoutSeconds)).toBe(true)
		expect(world.status():find("blocked", 1, true)).toBeNil()
		expect(#stageAsks(world)).toBe(2)
	end)
end)

describe("Capture: the ask a player takes over stays until the ring, P or J (317(a))", function()
	it("keeps 'Walk into the ring yourself' past walk.timeoutSeconds while the player stands outside", function()
		local world = load()
		ringServer(world)
		goTo(world, "art-vertical")
		world.standAt(25, 30)
		world.key(KEYS.startCountdown)
		world.frames(10)
		world.key(WALK.cancelKeys[1])
		world.frames(2)
		expect(world.status():find("yourself", 1, true)).never.toBeNil()
		-- The player stands outside the ring, 4 studs past its edge, for longer than the timeout.
		world.standAt(SPOT[1] + STAGE.standRadius + 4, SPOT[3])
		world.seconds(WALK.timeoutSeconds + 5)
		print(
			("[317(a)] after %g s outside: ring %s, status %q"):format(
				WALK.timeoutSeconds + 5,
				if world.ring() ~= nil then "shown" else "gone",
				world.status()
			)
		)
		expect(world.ring() ~= nil).toBe(true)
		expect(world.status():find("Walk failed", 1, true)).toBeNil()
		expect(world.status():find("yourself", 1, true)).never.toBeNil()
		expect(#stageAsks(world)).toBe(1)
		-- Walks in: the ask comes and stages.
		world.standAt(SPOT[1] + 1, SPOT[3])
		expect(untilCountdown(world, 2)).toBe(true)
		expect(#stageAsks(world)).toBe(2)
	end)

	it("still ends on J and stages afresh on P while the player holds the ask", function()
		local world = load()
		ringServer(world)
		world.standAt(25, 30)
		world.key(KEYS.startCountdown)
		world.frames(10)
		world.key(WALK.cancelKeys[1])
		world.seconds(WALK.timeoutSeconds + 1)
		world.key(KEYS.releaseStage)
		expect(world.ring()).toBeNil()
		expect(world.server.released).toBe(1)
		world.key(KEYS.startCountdown)
		expect(#stageAsks(world)).toBe(2)
	end)
end)
