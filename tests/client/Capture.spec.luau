--!strict
--[[
	The capture panel (src/client/dev/Capture.client.luau, F12), loaded the way Studio runs it: a
	fresh copy of the LocalScript with real UI instances (El) under a fake PlayerGui, fakes for the
	controllers it drives (CameraController, TargetController, InputController, EntityTracker,
	Replication, ClipLibrary, the Siblings it loads Choreo and the character controller through),
	a fake staging RemoteFunction, fake RenderStepped and InputBegan signals and a fake clock.

	Pins F12: P stages the shot through the server and frames it (the staged view, the lock), the
	counter's text is written before it shows and its box fits its text, the mouse cursor hides for
	the take, the prompt names the move at its moment, the take stops itself at its target length,
	K short of the target asks before it stops (and never marks the take done), and auto-perform
	(off by default, 1x only) presses the shot's keys through InputController.handle, the parry's
	guard timed off the target's overhead as it is drawn.

	And the walk into the stand ring (D-244: the staging never moves the player): a staging reply
	that asks for a walk marks the ring with a disc and walks the body along the reply's route
	through Humanoid:Move from a render step bound between the control script's input and the
	character controller, holding the sprint through the input path, walks the last leg again when
	the stop left the body off the spot, then asks for the shot again (at the server's rate) once
	the body is at rest; a movement key hands the walk over, J and P end it, and the timeout ends
	it with a note. The character is a fake body that moves at run speed along each frame's Move
	(at the sprint's while the sprint is held), on the field, the ledge's top or its ramp, and the
	staging server's fake stages by the real ring rule (DevStageLogic). The real body's stop runs
	in tests/client/CaptureWalk.spec.luau.
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

-- A take's last counted frame at `dt` a frame (FK3): the first whose elapsed time, summed frame by
-- frame as the panel sums it, reaches `seconds`. The take ends on the frame after it.
local function lastCountedFrame(seconds: number, dt: number): number
	local last = 0
	local sum = 0
	while sum < seconds do
		sum += dt
		last += 1
	end
	return last
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

describe("Capture: staging a shot (F12)", function()
	it("asks the server to stage the shot, then frames it with the shot's view and lock", function()
		local world = load()
		goTo(world, "art-horizontal")
		world.key(KEYS.startCountdown)
		expect(world.invokes[1].action).toBe("stage")
		expect(world.invokes[1].shotId).toBe("art-horizontal")
		local last = world.stages[#world.stages]
		expect(last.view).toBe(CAPTURE.cameras.Side)
		expect(last.target).toBe(world.kobold.model)
		expect(last.side).toBe(1)
		expect(world.lockOns[#world.lockOns]).toBe(world.kobold.id)
		-- The take starts: the server lets go of the enemies the shot releases.
		world.untilRecording()
		expect(world.invokes[#world.invokes].action).toBe("go")
	end)

	it("keeps the lock's own camera for the fight, and the boar's charge unlocked behind the boar", function()
		local world = load()
		world.key(KEYS.startCountdown)
		expect(world.stages[#world.stages].view).toBeNil()
		expect(world.lockOns[#world.lockOns]).toBe(world.kobold.id)
		world.untilRecording()
		world.seconds(CAPTURE.shots[1].seconds + 0.1)
		world.frames(math.ceil(CAPTURE.doneHoldSeconds / FRAME) + 1)
		-- Now on shot 2; go to the boar's charge.
		local world2 = load()
		goTo(world2, "enemy-boar-charge")
		world2.key(KEYS.startCountdown)
		expect(world2.stages[#world2.stages].view).toBe(CAPTURE.cameras.Behind)
		expect(world2.clears).toBe(1)
	end)

	it("says why when the staging fails, and does not count down", function()
		local world = load()
		world.reply.ok = false
		world.reply.error = "enemies 12 were still mid-attack"
		world.key(KEYS.startCountdown)
		expect(world.status():find("mid-attack", 1, true)).never.toBeNil()
		world.frames(math.ceil((CAPTURE.countdownSeconds + 1) / FRAME))
		expect(world.counter().Visible).toBe(false)
	end)

	it("still counts down where there is no staging remote (outside Studio)", function()
		local world = load({ remote = false, capture = true })
		world.key(KEYS.startCountdown)
		world.untilRecording()
		expect(world.counter().Visible).toBe(true)
	end)

	it("gives the field back on J", function()
		local world = load()
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(CAPTURE.shots[1].seconds + 0.1)
		world.key(KEYS.releaseStage)
		expect(world.invokes[#world.invokes].action).toBe("release")
		expect(world.stages[#world.stages].view).toBeNil()
	end)

	it("gives the field back on J pressed while a staging runs, once the server has finished it", function()
		-- The server refuses the release while the staging runs (busy) and right after the stage
		-- request (the rate): a J then must still end with the field given back, not a panel that
		-- says so over a field left held and the staged enemies left standing.
		local world = load()
		world.server.paced = true
		world.server.stagingSeconds = 1.2
		world.server.onStage = function()
			world.key(KEYS.releaseStage)
		end
		world.key(KEYS.startCountdown)
		world.seconds(CAPTURE.stageTimeoutSeconds)
		expect(world.server.released).toBe(1)
		expect(world.status():find("Field given back", 1, true)).never.toBeNil()
		-- The staging J cut short frames nothing and counts nothing down.
		expect(world.stages[#world.stages].view).toBeNil()
		expect(world.counter().Visible).toBe(false)
	end)

	it("gives the field back on J pressed right after a failed staging (the rate refuses the first ask)", function()
		local world = load()
		world.server.paced = true
		world.reply.ok = false
		world.reply.error = "enemies 12 were still mid-attack"
		world.key(KEYS.startCountdown)
		world.key(KEYS.releaseStage)
		world.seconds(1)
		expect(world.server.released).toBe(1)
		expect(world.status():find("Field given back", 1, true)).never.toBeNil()
	end)

	it("never says the field is given back while the server still refuses, and says to press J again", function()
		local world = load()
		world.server.stagingSeconds = CAPTURE.stageTimeoutSeconds + 5
		world.server.onStage = function()
			world.key(KEYS.releaseStage)
		end
		world.key(KEYS.startCountdown)
		world.seconds(1)
		expect(world.server.released).toBe(0)
		expect(world.status():find("Field given back", 1, true)).toBeNil()
		expect(world.status():find(KEYS.releaseStage, 1, true)).never.toBeNil()
	end)
end)

-- Every ask of `action` after the clock time `from`, in order.
local function asksOf(world: World, action: string, from: number?): { { action: string, shotId: string?, at: number } }
	local list = {}
	for _, entry in world.invokes do
		if entry.action == action and entry.at >= (from or -math.huge) then
			table.insert(list, entry)
		end
	end
	return list
end

describe("Capture: between takes (D-297)", function()
	it("holds the take's enemies the frame it ends, by itself at its length or on K", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("enemy-boar-charge")]
		goTo(world, shot.id)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		local started = world.clock.now
		expect(#asksOf(world, "hold")).toBe(0)
		world.seconds(shot.seconds + 0.05)
		local holds = asksOf(world, "hold")
		expect(#holds).toBe(1)
		-- Asked on the frame the take stopped, not later: the frame after its last counted frame (FK3).
		expect(holds[1].at - started).toBeGreaterThan(shot.seconds - 1e-6)
		expect(holds[1].at - started).toBeCloseTo((lastCountedFrame(shot.seconds, FRAME) + 1) * FRAME, 1e-6)
		-- Stopped short with K, K: held at once too.
		local again = load()
		goTo(again, shot.id)
		again.key(KEYS.startCountdown)
		again.untilRecording()
		again.seconds(1)
		again.key(KEYS.markDone)
		again.frames(1)
		local stopAt = again.clock.now
		again.key(KEYS.markDone)
		local stopped = asksOf(again, "hold")
		expect(#stopped).toBe(1)
		expect(stopped[1].at).toBeCloseTo(stopAt, 1e-9)
	end)

	it("asks for the hold again at the server's rate until the server holds them", function()
		local world = load()
		world.server.paced = true
		local shot = CAPTURE.shots[shotIndex("enemy-boar-charge")]
		goTo(world, shot.id)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		-- Stopped 0.1 s after the "go": the first hold is too soon for the rate.
		world.seconds(0.05)
		world.key(KEYS.markDone)
		world.frames(1)
		world.key(KEYS.markDone)
		world.seconds(1)
		local holds = asksOf(world, "hold")
		expect(#holds).toBeGreaterThan(1)
		-- The last one got through: the server's own rule says so.
		local last = holds[#holds]
		local go = asksOf(world, "go")[1]
		expect(last.at - go.at).toBeGreaterThan(1 / STAGE.requestsPerSecond - 1e-9)
		local count = #holds
		world.seconds(2)
		expect(#asksOf(world, "hold")).toBe(count)
	end)

	it("stages the next shot at once on P after a take, the ask waiting out the server's rate", function()
		local world = load()
		world.server.paced = true
		goTo(world, "enemy-boar-charge")
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(1)
		world.key(KEYS.markDone)
		world.frames(1)
		world.key(KEYS.markDone)
		-- Straight away: P stages (and is not refused for the rate).
		local pressed = world.clock.now
		world.key(KEYS.startCountdown)
		world.seconds(0.6)
		local stages = asksOf(world, "stage", pressed)
		expect(#stages).toBe(1)
		expect(world.status():find("too many", 1, true)).toBeNil()
		world.untilRecording()
		expect(world.counter().Visible).toBe(true)
		-- The hold's asking stopped once P took the field.
		local holdsAfter = asksOf(world, "hold", stages[1].at)
		expect(#holdsAfter).toBe(0)
	end)
end)

describe("Capture: the take (F12)", function()
	it("writes the counter's text before it shows, and fits its box to the text", function()
		local world = load()
		goTo(world, "art-vertical")
		world.key(KEYS.startCountdown)
		world.untilRecording()
		expect(world.firstShown.text ~= nil and world.firstShown.text ~= "").toBe(true)
		expect((world.firstShown.text :: string):find("art-vertical", 1, true)).never.toBeNil()
		local box = world.counter()
		expect(box.AutomaticSize).toBe(Enum.AutomaticSize.X)
		expect(box.Text.AutomaticSize).toBe(Enum.AutomaticSize.X)
	end)

	it("counts every rendered frame beside f and swaps the corner square's color each frame (D-336)", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("kill-shatter")]
		local tick = CAPTURE.frameTick
		local Palette = Harness.load("src/shared/data/palette")
		local colors = { Palette.color3(tick.tokens[1]), Palette.color3(tick.tokens[2]) }
		local function which(color: Color3): number?
			for index, expected in colors do
				if
					math.abs(color.R - expected.R) < 1e-3
					and math.abs(color.G - expected.G) < 1e-3
					and math.abs(color.B - expected.B) < 1e-3
				then
					return index
				end
			end
			return nil
		end
		goTo(world, shot.id)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		local square = world.gui:FindFirstChild(CAPTURE.panel.screenGuiName):FindFirstChild("FrameTick")
		expect(square).never.toBeNil()
		expect(square.Visible).toBe(true)
		-- A small square in the bottom-right corner.
		expect(square.Size.X.Offset).toBe(tick.size)
		expect(square.Size.Y.Offset).toBe(tick.size)
		expect(square.AnchorPoint).toBe(Vector2.new(1, 1))
		expect(square.Position.X.Scale).toBe(1)
		expect(square.Position.Y.Scale).toBe(1)
		expect(world.counterText():find("f 0  r 0  ", 1, true)).never.toBeNil()
		local last = which(square.BackgroundColor3)
		expect(last).never.toBeNil()
		for frame = 1, 7 do
			world.frames(1)
			expect(world.counterText():find(("f %d  r %d  "):format(frame, frame), 1, true)).never.toBeNil()
			local now = which(square.BackgroundColor3)
			expect(now).never.toBeNil()
			expect(now ~= last).toBe(true)
			last = now
		end
		-- K short of the target pauses neither count.
		world.key(KEYS.markDone)
		world.frames(1)
		expect(world.counterText():find("f 8  r 8  ", 1, true)).never.toBeNil()
		world.seconds(shot.seconds)
		expect(square.Visible).toBe(false)
	end)

	it("hides the mouse cursor for the take and gives it back after", function()
		local world = load()
		goTo(world, "art-vertical")
		world.key(KEYS.startCountdown)
		expect(world.userInput.MouseIconEnabled).toBe(true)
		world.untilRecording()
		expect(world.userInput.MouseIconEnabled).toBe(false)
		world.seconds(CAPTURE.shots[shotIndex("art-vertical")].seconds + 0.1)
		expect(world.userInput.MouseIconEnabled).toBe(true)
	end)

	it("shows the prompt naming the move at its moment", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("art-horizontal")]
		goTo(world, shot.id)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		expect(world.prompt().Visible).toBe(true)
		expect(world.prompt().Text.Text).toBe(shot.prompts[1].text)
		world.seconds(shot.prompts[2].at + 0.05)
		expect(world.prompt().Text.Text).toBe(shot.prompts[2].text)
		-- Bottom-left, above the counter.
		expect(world.prompt().Position.Y.Offset).toBeLessThan(world.counter().Position.Y.Offset)
	end)

	it("stops itself at the target length and marks the shot done", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("art-horizontal")]
		goTo(world, shot.id)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(shot.seconds - 0.2)
		expect(world.counter().Visible).toBe(true)
		world.seconds(0.3)
		expect(world.counter().Visible).toBe(false)
		expect(world.prompt().Visible).toBe(false)
		expect(world.status():find("Shot done", 1, true)).never.toBeNil()
		expect(world.stages[#world.stages].view).toBeNil()
	end)

	it(
		"keeps the panel hidden until the frame after the take's last counted frame, at 30, 60 and 144 fps (FK3)",
		function()
			local shot = CAPTURE.shots[shotIndex("enemy-kobold-overhead")]
			for _, fps in { 30, 60, 144 } do
				local dt = 1 / fps
				local last = lastCountedFrame(shot.seconds, dt)
				local world = load()
				goTo(world, shot.id)
				world.key(KEYS.startCountdown)
				world.untilRecording()
				-- Frame 0: the counter up, the panel hidden.
				expect(world.counter().Visible).toBe(true)
				expect(world.panel().Visible).toBe(false)
				for frame = 1, last do
					world.framesAt(1, dt)
					-- Every counted frame is drawn with its counter and without the panel, the last too.
					expect(world.counter().Visible).toBe(true)
					expect(world.counterText():match("f (%d+)")).toBe(tostring(frame))
					expect(world.panel().Visible).toBe(false)
				end
				-- The shot's length in frames, or one more where the summed frames fall a hair short of it.
				expect(last >= math.round(shot.seconds * fps)).toBe(true)
				expect(last <= math.round(shot.seconds * fps) + 1).toBe(true)
				-- The frame after it: the take is over, marked done, the panel back.
				world.framesAt(1, dt)
				expect(world.counter().Visible).toBe(false)
				expect(world.prompt().Visible).toBe(false)
				expect(world.panel().Visible).toBe(true)
				expect(world.status():find("Shot done", 1, true)).never.toBeNil()
			end
		end
	)

	it("asks before K stops a take short of its target, and never marks that take done", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("art-horizontal")]
		goTo(world, shot.id)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(1)
		world.key(KEYS.markDone)
		expect(world.counter().Visible).toBe(true)
		world.frames(1)
		expect(world.counterText():find(KEYS.markDone .. " again", 1, true)).never.toBeNil()
		-- The window passes: K asks again.
		world.seconds(CAPTURE.confirmSeconds + 0.1)
		world.key(KEYS.markDone)
		expect(world.counter().Visible).toBe(true)
		world.frames(1)
		world.key(KEYS.markDone)
		expect(world.counter().Visible).toBe(false)
		expect(world.status():find("not marked", 1, true)).never.toBeNil()
		expect(world.status():find("Shot done", 1, true)).toBeNil()
	end)
end)

-- The take seconds of a shot's timed lock presses, in order.
local function lockPresses(shot: any): { number }
	local list = {}
	for _, entry in shot.perform do
		if entry.action == "LockOn" and entry.at ~= nil then
			table.insert(list, entry.at)
		end
	end
	table.sort(list)
	return list
end

-- Runs frames until `seconds` of the take that started at `started` have passed.
local function untilElapsed(world: World, started: number, seconds: number)
	while world.clock.now - started < seconds - 1e-9 do
		world.frames(1)
	end
end

describe("Capture: auto-perform (F12)", function()
	it("is off by default: a take presses nothing", function()
		local world = load()
		goTo(world, "art-horizontal")
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(4)
		expect(#world.handled).toBe(0)
	end)

	it("on, presses the shot's Art through the input path at its moment and lets it go after its hold", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("art-sharp-nail")]
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		local started = world.clock.now
		world.seconds(3)
		local perform = shot.perform[1]
		expect(#world.handled).toBe(2)
		expect(world.handled[1].action).toBe(perform.action)
		expect(world.handled[1].state).toBe("Begin")
		expect(world.handled[1].at - started).toBeCloseTo(perform.at, 2 * FRAME)
		expect(world.handled[2].state).toBe("End")
		expect(world.handled[2].at - world.handled[1].at).toBeCloseTo(perform.hold, 2 * FRAME)
	end)

	-- D-298: an Art launches on its key's release (CharacterController.releaseArt sends ArtRequest),
	-- a basic on its press. At the snapshot the prompt said "Q now" at 1.0 s and the key came up
	-- (the launch) at 1.35 s, under that same line; a human tapping on "now" never held the glow.
	it("lands each attack on the beat that says so: hold on the press, let go on the launch (D-298)", function()
		local Combat = Harness.load("src/shared/data/combat")
		local checked = 0
		for _, shot in CAPTURE.shots do
			local entry = shot.perform[1]
			if entry == nil or entry.at == nil then
				continue
			end
			local art = entry.action == "Art" or entry.action:match("^ArtSlot") ~= nil
			if not art and entry.action ~= "BasicAttack" then
				continue
			end
			local world = load()
			goTo(world, shot.id)
			world.key(KEYS.autoPerform)
			world.key(KEYS.startCountdown)
			world.untilRecording()
			local started = world.clock.now
			-- The prompt line and its beat on the frame each key moved.
			local seen: { { state: string, at: number, text: string } } = {}
			while world.clock.now - started < shot.seconds - 0.5 do
				local before = #world.handled
				world.frames(1)
				for index = before + 1, #world.handled do
					table.insert(seen, {
						state = world.handled[index].state,
						at = world.handled[index].at - started,
						text = world.prompt().Text.Text,
					})
				end
			end
			local function beatOf(text: string): number
				for _, beat in shot.prompts do
					if beat.text == text then
						return beat.at
					end
				end
				error("no beat shows " .. text)
			end
			local down, up = seen[1], seen[2]
			print(
				("[D-298] %s: press %.3f s (%q), release %.3f s (%q)"):format(
					shot.id,
					down.at,
					down.text,
					up.at,
					up.text
				)
			)
			expect(down.state).toBe("Begin")
			expect(up.state).toBe("End")
			-- Each key moves on the frame its own beat comes up.
			expect(math.abs(beatOf(down.text) - down.at)).toBeLessThan(1.5 * FRAME)
			if art then
				expect(down.text:lower():find("hold", 1, true)).never.toBeNil()
				-- The release is the launch: its beat says let go, and comes up with it.
				expect(math.abs(beatOf(up.text) - up.at)).toBeLessThan(1.5 * FRAME)
				expect(up.text:lower():find("let go", 1, true)).never.toBeNil()
				-- The blade lights at the clip's hold pose and stays lit until the release.
				local clip = Harness.load(
					"src/shared/clips/player/OneHandedSword/" .. shot.title:gsub("^Art: ", ""):gsub(" ", "")
				)
				local lit = Combat.startPoseTime + Combat.activationHold
				for _, event in clip.events do
					if event.kind == "ActivationHold" then
						lit = math.min(lit, event.time)
					end
				end
				local glow = up.at - (down.at + lit)
				print(("[D-298] %s: glow %.3f s"):format(shot.id, glow))
				expect(glow).toBeGreaterThan(CAPTURE.artGlowSeconds - FRAME)
			else
				expect(down.text:lower():find("now", 1, true)).never.toBeNil()
			end
			checked += 1
		end
		expect(checked).toBe(5)
	end)

	it("presses nothing slowed (the drawn clips run late on the server's clock)", function()
		local world = load()
		goTo(world, "art-horizontal")
		world.key(KEYS.autoPerform)
		world.key(KEYS.cycleTimeScale)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(3)
		expect(#world.handled).toBe(0)
	end)

	it("guards for the parry `lead` before the overhead's hit window, as the client draws it", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("parry-spark")]
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(0.5)
		-- The kobold's overhead starts; its first event (0.15 s in) is heard now.
		local first = Overhead.events[1]
		local heardAt = world.clock.now
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, first, false)
		-- Another fighter's overhead is not the target's.
		world.replication.clipEvent:Fire({ id = 99 }, Overhead.id, first, false)
		world.seconds(2)
		local downs = count(world.handled, function(entry: any): boolean
			return entry.action == "Guard" and entry.state == "Begin"
		end)
		expect(downs).toBe(1)
		local open = 0
		for _, event in Overhead.events do
			if event.kind == "HitWindowOpen" then
				open = event.time
				break
			end
		end
		local perform = shot.perform[1]
		local guardAt = world.handled[1].at - heardAt
		expect(guardAt).toBeCloseTo(open - first.time - perform.lead, 2 * FRAME)
		expect(world.handled[2].action).toBe("Guard")
		expect(world.handled[2].state).toBe("End")
	end)

	-- A press reaches the server a latency after it leaves: it leaves the client's latency lead
	-- early (Telegraphs.glintLead, D-289), as the glint shows, so the guard is down on the server
	-- `lead` before the window at any latency the lead has learnt (Studio item 324(b)).
	it("guards the client's latency lead earlier still, as the glint comes (D-289)", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("parry-spark")]
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(0.5)
		world.lead.seconds = 0.1
		local first = Overhead.events[1]
		local heardAt = world.clock.now
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, first, false)
		world.seconds(2)
		local open = 0
		for _, event in Overhead.events do
			if event.kind == "HitWindowOpen" then
				open = event.time
				break
			end
		end
		expect(world.handled[1].action).toBe("Guard")
		expect(world.handled[1].state).toBe("Begin")
		local guardAt = world.handled[1].at - heardAt
		expect(guardAt).toBeCloseTo(open - first.time - shot.perform[1].lead - 0.1, 2 * FRAME)
	end)

	it("lets go of a key it holds when the take ends early", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("art-horizontal")]
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(shot.perform[1].at + 0.05)
		world.key(KEYS.markDone)
		world.key(KEYS.markDone)
		expect(world.handled[#world.handled].state).toBe("End")
	end)

	-- D-290: the Art key a stopped take still holds comes up with its hold cancelled first, so the
	-- release launches nothing (at HEAD the key's End launched the Art after the take had ended).
	it("cancels a held Art before its key comes up when the take stops, so nothing launches", function()
		local Input = Harness.load("src/shared/data/input")
		local world = load()
		local shot = CAPTURE.shots[shotIndex("art-horizontal")]
		local perform = shot.perform[1]
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(perform.at + 0.05)
		expect(world.handled[#world.handled].state).toBe("Begin")
		local before = #world.handled
		world.key(KEYS.markDone)
		world.key(KEYS.markDone)
		expect(#world.cancels).toBe(1)
		expect(world.cancels[1].slot).toBe(Input.artSlot(perform.action))
		-- Cancelled, then the key comes up (the input path's hold ends too), once.
		expect(world.cancels[1].handledBefore).toBe(before)
		expect(#world.handled).toBe(before + 1)
		expect(world.handled[before + 1].action).toBe(perform.action)
		expect(world.handled[before + 1].state).toBe("End")
		-- Nothing more after the stop: its timed let-go never comes.
		world.seconds(1)
		expect(#world.handled).toBe(before + 1)
	end)

	it("lets a key that is not an Art come up without a cancel", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("parry-spark")]
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(0.5)
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, Overhead.events[1], false)
		-- Until the guard is down, then stop the take while it is.
		for _ = 1, 120 do
			world.frames(1)
			if #world.handled > 0 then
				break
			end
		end
		expect(world.handled[1].action).toBe("Guard")
		world.key(KEYS.markDone)
		world.key(KEYS.markDone)
		expect(#world.cancels).toBe(0)
		expect(world.handled[#world.handled].action).toBe("Guard")
		expect(world.handled[#world.handled].state).toBe("End")
	end)

	-- D-290: the locomotion pass's lock presses act on the staged target alone; the lock key's
	-- own cycle could step the second press on to a field enemy nearer than it. The pass locks on
	-- twice (the draw, then the turn in place, CF), each lock let go by the press after it.
	it("locks the staged target on each of the locomotion pass's lock presses and lets it go on the next", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("locomotion")]
		local presses = lockPresses(shot)
		expect(#presses >= 2).toBe(true)
		expect(#presses % 2).toBe(0)
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		local started = world.clock.now
		expect(world.locked.id).toBeNil()
		for index, at in presses do
			untilElapsed(world, started, at + 0.1)
			expect(world.locked.id).toBe(if index % 2 == 1 then world.kobold.id else nil)
		end
		-- Never through the lock key's path, which would cycle on to whatever ranks next.
		local keyed = count(world.handled, function(entry: any): boolean
			return entry.action == "LockOn"
		end)
		expect(keyed).toBe(0)
	end)

	it("takes the staged target from a field enemy the lock is on, never cycling past it", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("locomotion")]
		local first = lockPresses(shot)[1]
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		-- The player locked a field enemy before the press.
		world.locked.id = 99
		world.seconds(first + 0.1)
		expect(world.locked.id).toBe(world.kobold.id)
	end)

	it("presses the lock key through the input path when the take staged no target", function()
		local world = load({ remote = false, capture = true })
		local shot = CAPTURE.shots[shotIndex("locomotion")]
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		world.seconds(shot.seconds - 1)
		local downs = count(world.handled, function(entry: any): boolean
			return entry.action == "LockOn" and entry.state == "Begin"
		end)
		expect(downs).toBe(#lockPresses(shot))
	end)
end)

-- CF: the fight's auto-perform reacts to what this client draws through the real input path: a
-- guard `lead` before each of the kobold's overheads (the parry), the Arts that follow it in
-- turn, a dodge on the boar's crouch with the lock, the run at its skid and the sprint after it,
-- and between them basics on the lock's target in reach and the lock back on the kobold once it
-- is lost. At the snapshot the fight's perform list was empty: a take pressed nothing.
local function fightEntry(predicate: (any) -> boolean): any
	for _, entry in CAPTURE.shots[shotIndex("fight-boar-kobold")].perform do
		if predicate(entry) then
			return entry
		end
	end
	error("no such entry in the fight's perform list")
end

local function openOf(clip: any): number
	for _, event in clip.events do
		if event.kind == "HitWindowOpen" then
			return event.time
		end
	end
	error("no hit window in " .. clip.id)
end

-- The fight staged (its kobold and its boar), auto-perform on, the take running.
local function fightTake(): (World, number)
	local world = load()
	world.reply.ids = { world.kobold.id, world.boar.id }
	goTo(world, "fight-boar-kobold")
	world.key(KEYS.autoPerform)
	world.key(KEYS.startCountdown)
	world.untilRecording()
	return world, world.clock.now
end

local function handledOf(world: World, action: string, state: string, from: number?): { any }
	local list = {}
	for _, entry in world.handled do
		if entry.action == action and entry.state == state and entry.at >= (from or -math.huge) then
			table.insert(list, entry)
		end
	end
	return list
end

-- The kobold's root `studs` (flat) ahead of the player's.
local function koboldAt(world: World, studs: number)
	local root = world.body.root.Position
	world.kobold.model.PrimaryPart.Position = Vector3.new(root.X, 3, root.Z - studs)
end

describe("Capture: the fight's auto-perform (CF)", function()
	it("guards `lead` before each of the kobold's overheads, then presses the next Art of its cycle", function()
		local world = fightTake()
		koboldAt(world, 20) -- out of the basics' reach: only the reactions press
		local guard = fightEntry(function(entry: any): boolean
			return entry.onClip == Overhead.id
		end)
		expect(guard.action).toBe("Guard")
		expect(guard.repeats).toBe(true)
		local art = guard.chain[1]
		local voice = Overhead.events[1]
		local open = openOf(Overhead)
		local heard = {}
		for _ = 1, 2 do
			world.seconds(0.5)
			table.insert(heard, world.clock.now)
			world.replication.clipEvent:Fire(world.kobold, Overhead.id, voice, false)
			-- Another fighter's overhead is not the kobold's.
			world.replication.clipEvent:Fire({ id = 99 }, Overhead.id, voice, false)
			world.seconds(open - voice.time + 1.5)
			-- The rest of the play is heard too: the window and its close move nothing.
			for _, event in Overhead.events do
				if event.time >= open then
					world.replication.clipEvent:Fire(world.kobold, Overhead.id, event, false)
				end
			end
			world.seconds(0.5)
		end
		local downs = handledOf(world, "Guard", "Begin")
		local ups = handledOf(world, "Guard", "End")
		expect(#downs).toBe(2)
		expect(#ups).toBe(2)
		for play = 1, 2 do
			expect(downs[play].at - heard[play]).toBeCloseTo(open - voice.time - guard.lead, 2 * FRAME)
			expect(ups[play].at - downs[play].at).toBeCloseTo(guard.hold, 2 * FRAME)
			-- The Art of the cycle in turn, `delay` after the guard came up, held its hold.
			local action = art.cycle[play]
			local artDown = handledOf(world, action, "Begin", ups[play].at)[1]
			expect(artDown).never.toBeNil()
			expect(artDown.at - ups[play].at).toBeCloseTo(art.delay, 2 * FRAME)
			local artUp = handledOf(world, action, "End", artDown.at)[1]
			expect(artUp.at - artDown.at).toBeCloseTo(art.hold, 2 * FRAME)
		end
	end)

	-- The take cuts at its length: a press past the guard's `to` (the chain's Art included) would
	-- land its hit after the cut, where the review never sees its number (D-320).
	it("presses nothing of a reaction past its `to`: the guard inside it, the chain's Art never after", function()
		local world, start = fightTake()
		koboldAt(world, 20)
		local guard = fightEntry(function(entry: any): boolean
			return entry.onClip == Overhead.id
		end)
		expect(guard.to).never.toBeNil()
		local art = guard.chain[1]
		local voice = Overhead.events[1]
		local open = openOf(Overhead)
		-- The overhead heard so the guard goes down 0.1 s before `to`: the guard presses, its Art
		-- (`delay` after the guard comes up) would go down past `to` and never does.
		local guardIn = open - voice.time - guard.lead
		world.seconds(guard.to - 0.1 - guardIn)
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, voice, false)
		world.seconds(guardIn + guard.hold + art.delay + art.hold + 0.5)
		local downs = handledOf(world, "Guard", "Begin")
		expect(#downs).toBe(1)
		expect(downs[1].at - start).toBeLessThanOrEqual(guard.to + 1e-6)
		for _, action in art.cycle do
			for _, entry in handledOf(world, action, "Begin") do
				expect(entry.at - start).toBeLessThanOrEqual(guard.to + 1e-6)
			end
		end
		expect(#handledOf(world, art.cycle[1], "Begin", downs[1].at)).toBe(0)
	end)

	-- A hit on the kobold mid-wind-up pauses its attack on the server (attackPause, at most
	-- ai.luau hitStop.maxPausePerAttack) and this client holds its clip as long: the strike comes
	-- that much later. The guard moves with the pause, and with each later event of the play.
	it("moves the guard on by the kobold's hit-stop pause, and with each later event of the play", function()
		local world = fightTake()
		koboldAt(world, 20)
		local guard = fightEntry(function(entry: any): boolean
			return entry.onClip == Overhead.id
		end)
		local open = openOf(Overhead)
		local voice = Overhead.events[1]
		local whoosh = nil :: any
		for _, event in Overhead.events do
			if event.kind == "Sfx" and event.time < open then
				whoosh = event
				break
			end
		end
		world.seconds(0.5)
		local voiceAt = world.clock.now
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, voice, false)
		-- A basic lands 0.3 s in: the attack pauses 0.25 s. Another enemy's pause moves nothing.
		world.seconds(0.3)
		world.replication.hit:Fire({ targetId = world.boar.id, attackPause = 0.25 })
		world.replication.hit:Fire({ targetId = world.kobold.id, attackPause = 0.25 })
		world.seconds(whoosh.time - voice.time - 0.3 + 0.25)
		-- Not yet: unpaused, it would have gone down by now.
		expect(#handledOf(world, "Guard", "Begin")).toBe(0)
		local heardAt = world.clock.now
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, whoosh, false)
		world.seconds(1)
		local downs = handledOf(world, "Guard", "Begin")
		expect(#downs).toBe(1)
		expect(downs[1].at - heardAt).toBeCloseTo(open - whoosh.time - guard.lead, 2 * FRAME)
		expect(downs[1].at - voiceAt).toBeCloseTo(open - voice.time - guard.lead + 0.25, 2 * FRAME)
	end)

	it("moves the guard on by the hit-stop pause with no later event heard", function()
		local world = fightTake()
		koboldAt(world, 20)
		local guard = fightEntry(function(entry: any): boolean
			return entry.onClip == Overhead.id
		end)
		local voice = Overhead.events[1]
		world.seconds(0.5)
		local voiceAt = world.clock.now
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, voice, false)
		world.seconds(0.3)
		world.replication.hit:Fire({ targetId = world.kobold.id, attackPause = 0.2 })
		world.seconds(1.5)
		local downs = handledOf(world, "Guard", "Begin")
		expect(#downs).toBe(1)
		expect(downs[1].at - voiceAt).toBeCloseTo(openOf(Overhead) - voice.time - guard.lead + 0.2, 2 * FRAME)
	end)

	it("takes the lock to the kobold when its overhead is heard, so the guard faces it", function()
		local world = fightTake()
		koboldAt(world, 20)
		world.locked.id = world.boar.id
		world.seconds(0.2)
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, Overhead.events[1], false)
		expect(world.locked.id).toBe(world.kobold.id)
	end)

	it("dodges the boar's crouch, locks the boar and sprints at it, letting go in reach", function()
		local world, started = fightTake()
		koboldAt(world, 20)
		local dodge = fightEntry(function(entry: any): boolean
			return entry.onClip == Charge.id
		end)
		expect(dodge.action).toBe("Dodge")
		local lock, run = dodge.chain[1], dodge.chain[2]
		expect(lock.action).toBe("LockOn")
		expect(run.action).toBe(CAPTURE.perform.moveAction)
		world.seconds(1)
		local first = Charge.events[1]
		local heardAt = world.clock.now
		-- The kobold's crouch is not the boar's: only the boar's own clip is heard.
		world.replication.clipEvent:Fire(world.kobold, Charge.id, first, false)
		world.replication.clipEvent:Fire(world.boar, Charge.id, first, false)
		world.seconds(openOf(Charge) - first.time)
		local dodges = handledOf(world, "Dodge", "Begin")
		expect(#dodges).toBe(1)
		expect(dodges[1].at - heardAt).toBeCloseTo(openOf(Charge) - first.time - dodge.lead, 2 * FRAME)
		local up = handledOf(world, "Dodge", "End")[1]
		-- The lock on the boar, `delay` after the dodge's key came up.
		untilElapsed(world, started, up.at - started + lock.delay + 2 * FRAME)
		expect(world.locked.id).toBe(world.boar.id)
		-- Then the run: the stick forward through Humanoid:Move, on the camera's view, and the sprint.
		local before = #world.body.moves
		world.seconds(run.delay + 0.2)
		local sprints = handledOf(world, "Sprint", "Begin")
		expect(#sprints).toBe(1)
		expect(#world.body.moves > before).toBe(true)
		local move = world.body.moves[#world.body.moves]
		expect(move.relative).toBe(true)
		expect(move.direction.X).toBeCloseTo(0, 1e-6)
		expect(move.direction.Z).toBeCloseTo(-1, 1e-6)
		expect(#handledOf(world, "Sprint", "End")).toBe(0)
		-- The boar's root in reach: the stick and the sprint let go.
		local root = world.body.root.Position
		world.boar.model.PrimaryPart.Position = Vector3.new(root.X + run.within - 0.5, 3, root.Z)
		world.seconds(0.1)
		expect(#handledOf(world, "Sprint", "End")).toBe(1)
		local moves = #world.body.moves
		world.seconds(0.5)
		expect(#world.body.moves).toBe(moves)
	end)

	it("lets the run go at its hold when the boar never comes in reach", function()
		local world = fightTake()
		koboldAt(world, 20)
		local dodge = fightEntry(function(entry: any): boolean
			return entry.onClip == Charge.id
		end)
		local run = dodge.chain[2]
		world.seconds(1)
		world.replication.clipEvent:Fire(world.boar, Charge.id, Charge.events[1], false)
		world.seconds(3)
		local begin = handledOf(world, "Sprint", "Begin")[1]
		local stop = handledOf(world, "Sprint", "End")[1]
		expect(begin).never.toBeNil()
		expect(stop).never.toBeNil()
		expect(stop.at - begin.at).toBeCloseTo(run.hold, 2 * FRAME)
	end)

	it("presses basics on the lock's target in reach between reactions, never while one waits", function()
		local world = fightTake()
		local basics = fightEntry(function(entry: any): boolean
			return entry.action == "BasicAttack" and entry.every ~= nil
		end)
		expect(world.locked.id).toBe(world.kobold.id)
		koboldAt(world, basics.within - 1)
		world.seconds(2)
		local pressed = #handledOf(world, "BasicAttack", "Begin")
		expect(pressed >= math.floor(2 / basics.every) - 1).toBe(true)
		expect(pressed <= math.ceil(2 / basics.every) + 1).toBe(true)
		-- The overhead heard: no basic until its guard has gone down and come up.
		local heardAt = world.clock.now
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, Overhead.events[1], false)
		world.seconds(openOf(Overhead))
		local guard = handledOf(world, "Guard", "Begin")[1]
		expect(guard).never.toBeNil()
		expect(#handledOf(world, "BasicAttack", "Begin", heardAt + FRAME / 2)).toBe(0)
		-- Out of reach: none.
		koboldAt(world, basics.within + 3)
		world.seconds(3)
		local after = world.clock.now
		world.seconds(1)
		expect(#handledOf(world, "BasicAttack", "Begin", after)).toBe(0)
	end)

	it("locks the kobold again once the lock is lost (the boar shattered)", function()
		local world = fightTake()
		koboldAt(world, 20)
		local keep = fightEntry(function(entry: any): boolean
			return entry.action == "LockOn" and entry.every ~= nil
		end)
		world.seconds(0.5)
		world.locked.id = nil
		world.seconds(keep.every + 2 * FRAME)
		expect(world.locked.id).toBe(world.kobold.id)
		-- It never takes a lock that is on: the boar stays locked.
		world.locked.id = world.boar.id
		world.seconds(1)
		expect(world.locked.id).toBe(world.boar.id)
	end)

	it("lets go of the stick and the sprint when the take stops mid-run", function()
		local world = fightTake()
		koboldAt(world, 20)
		world.seconds(1)
		world.replication.clipEvent:Fire(world.boar, Charge.id, Charge.events[1], false)
		for _ = 1, 240 do
			world.frames(1)
			if #handledOf(world, "Sprint", "Begin") > 0 then
				break
			end
		end
		expect(#handledOf(world, "Sprint", "Begin")).toBe(1)
		world.key(KEYS.markDone)
		world.key(KEYS.markDone)
		expect(#handledOf(world, "Sprint", "End")).toBe(1)
		local moves = #world.body.moves
		world.seconds(0.5)
		expect(#world.body.moves).toBe(moves)
	end)
end)

-- EF: shot 1 and the parry shot in Studio (build cebade4). At no lag the fight gave 7 hits (no
-- basic, no Sharp Nail, Rising Arc after the fourth parry); at 0.05 s the sixth overhead got a basic
-- instead of a guard and hit the player; at 0.1 s the parry shot's guard reached the server after
-- the hit. Each case below failed at cebade4.
local function guardEntry(): any
	return fightEntry(function(entry: any): boolean
		return entry.onClip == Overhead.id
	end)
end

local function basicsEntry(): any
	return fightEntry(function(entry: any): boolean
		return entry.action == "BasicAttack" and entry.every ~= nil
	end)
end

local function before(list: { any }, at: number): { any }
	local kept = {}
	for _, entry in list do
		if entry.at < at then
			table.insert(kept, entry)
		end
	end
	return kept
end

describe("Capture: the fight's auto-perform in Studio (EF)", function()
	-- Step 25(b): the guard's `to` (19 s) dropped the sixth overhead's guard (heard late at 0.05 s);
	-- nothing waited, so the standing basic swung into the axe. The guard answers every overhead the
	-- take shows; the chain's Art keeps its own `to`, so no Art launches past the cut (D-320).
	it("guards an overhead heard past the chain's `to`, with no basic swung into it", function()
		local world, start = fightTake()
		local guard, basics = guardEntry(), basicsEntry()
		local art = guard.chain[1]
		expect(art.to).never.toBeNil()
		local voice = Overhead.events[1]
		local guardIn = openOf(Overhead) - voice.time - guard.lead
		koboldAt(world, basics.within - 1)
		untilElapsed(world, start, art.to + 0.3 - guardIn)
		local heardAt = world.clock.now
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, voice, false)
		world.seconds(guardIn + 0.1)
		local downs = handledOf(world, "Guard", "Begin", heardAt)
		expect(#downs).toBe(1)
		expect(downs[1].at - heardAt).toBeCloseTo(guardIn, 2 * FRAME)
		expect(#before(handledOf(world, "BasicAttack", "Begin", heardAt + FRAME / 2), downs[1].at)).toBe(0)
		world.seconds(2)
		for _, action in art.cycle do
			for _, entry in handledOf(world, action, "Begin") do
				expect(entry.at - start).toBeLessThanOrEqual(art.to + 1e-6)
			end
		end
	end)

	-- Step 23: a basic pressed while the body plays an Art does nothing, yet it spent the rule's
	-- beat; the body's next free moment waited out `every`, the next overhead was heard first, and no
	-- basic landed in the take. The rule presses only when the body could start a basic.
	it("presses a standing basic only when the body could start one, on its first free frame", function()
		local world = fightTake()
		local basics = basicsEntry()
		koboldAt(world, basics.within - 1)
		world.bodyState.value = "Art"
		world.seconds(1)
		world.bodyState.value = "Holding"
		world.seconds(0.5)
		expect(#handledOf(world, "BasicAttack", "Begin")).toBe(0)
		world.bodyState.value = "Idle"
		local freeAt = world.clock.now
		world.frames(1)
		expect(#handledOf(world, "BasicAttack", "Begin", freeAt)).toBe(1)
		-- Mid-basic the chain goes on at `every`.
		world.bodyState.value = "Basic"
		world.seconds(basics.every + 2 * FRAME)
		expect(#handledOf(world, "BasicAttack", "Begin", freeAt)).toBe(2)
	end)

	-- Step 23: the boar's crouch was heard after the third chain's Art key had gone down. The chain
	-- dropped, its Art stayed held, the dodge cleared the hold and the Art never launched, yet its
	-- turn of the cycle was spent: no Sharp Nail, and every later parry pressed the Art after the one
	-- meant. A reaction that drops the chain cancels the Art it holds (its key comes up launching
	-- nothing, D-290) and gives its turn back.
	it("cancels the chain's held Art when a reaction drops the chain, and gives its turn back", function()
		local Input = Harness.load("src/shared/data/input")
		local world = fightTake()
		koboldAt(world, 20)
		local art = guardEntry().chain[1]
		local first = art.cycle[1]
		local voice = Overhead.events[1]
		world.seconds(0.5)
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, voice, false)
		for _ = 1, 300 do
			world.frames(1)
			if #handledOf(world, first, "Begin") > 0 then
				break
			end
		end
		expect(#handledOf(world, first, "Begin")).toBe(1)
		world.seconds(art.hold / 2)
		local handledBefore = #world.handled
		world.replication.clipEvent:Fire(world.boar, Charge.id, Charge.events[1], false)
		expect(#world.cancels).toBe(1)
		expect(world.cancels[1].slot).toBe(Input.artSlot(first))
		expect(world.cancels[1].handledBefore).toBe(handledBefore)
		local ups = handledOf(world, first, "End")
		expect(#ups).toBe(1)
		expect(ups[1].at).toBe(world.clock.now)
		-- Its queued key-up never comes on top.
		world.seconds(art.hold + 3)
		expect(#handledOf(world, first, "End")).toBe(1)
		-- The rest of the first play is heard, then the next play: its chain presses that Art again.
		for _, event in Overhead.events do
			if event.time >= openOf(Overhead) then
				world.replication.clipEvent:Fire(world.kobold, Overhead.id, event, false)
			end
		end
		local heard = world.clock.now
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, voice, false)
		world.seconds(openOf(Overhead) - voice.time + 1.5)
		expect(#handledOf(world, first, "Begin", heard)).toBe(1)
		expect(#handledOf(world, art.cycle[2], "Begin", heard)).toBe(0)
	end)

	-- Step 25(a): the guard went down the glint lead early (the least lateness of the last tells:
	-- the way down less this client's clock lag), while a press reaches the server the way up plus
	-- that lag later; at 0.1 s the guard landed after the hit ("Busy:Stagger"). Each staging reply
	-- carries the server's clock at the ask's receipt (DevStage receivedAt): the panel keeps the
	-- least of it less the ask's send time on this client's server clock over the staging's asks,
	-- the lead its presses need, and sets the guard that much early instead.
	it("guards the way up early, read off this staging's replies, not the glint lead", function()
		local world = load({ remote = true, capture = true, clockLag = 0.04 })
		world.link.up = 0.5 -- the stage ask: a slow one, the go ask's is the least
		world.lead.seconds = 0.02
		local shot = CAPTURE.shots[shotIndex("parry-spark")]
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.link.up = 0.09
		world.untilRecording()
		world.seconds(0.5)
		local first = Overhead.events[1]
		local heardAt = world.clock.now
		world.replication.clipEvent:Fire(world.kobold, Overhead.id, first, false)
		world.seconds(2)
		local down = handledOf(world, "Guard", "Begin")[1]
		expect(down).never.toBeNil()
		expect(down.at - heardAt).toBeCloseTo(openOf(Overhead) - first.time - shot.perform[1].lead - 0.13, 2 * FRAME)
	end)
end)

-- CF: the locomotion pass holds the stick through the walk's render step (after the control
-- script's Move, before the character controller reads MoveDirection): a part-pushed stick for
-- the walks, a full one for the runs, the sprint held with it. At the snapshot its perform held
-- two lock presses: the body stood still for the whole take.
describe("Capture: the locomotion pass's auto-perform (CF)", function()
	it("holds each move's stick on the camera's view, and the sprint with the sprints", function()
		local world = load()
		local shot = CAPTURE.shots[shotIndex("locomotion")]
		local moves = {}
		for _, entry in shot.perform do
			if entry.action == CAPTURE.perform.moveAction then
				table.insert(moves, entry)
			end
		end
		expect(#moves >= 4).toBe(true)
		goTo(world, shot.id)
		world.key(KEYS.autoPerform)
		world.key(KEYS.startCountdown)
		world.untilRecording()
		local started = world.clock.now
		local Logic = Harness.load("src/client/dev/CaptureLogic")
		table.sort(moves, function(a: any, b: any): boolean
			return a.at < b.at
		end)
		for _, entry in moves do
			untilElapsed(world, started, entry.at + entry.hold / 2)
			local last = world.body.moves[#world.body.moves]
			expect(last.at > world.clock.now - 1.5 * FRAME).toBe(true)
			expect(last.relative).toBe(true)
			local x, z = Logic.stickMove(entry.stick)
			expect(last.direction.X).toBeCloseTo(x, 1e-6)
			expect(last.direction.Z).toBeCloseTo(z, 1e-6)
			expect(world.body.sprinting).toBe(entry.sprint == true)
		end
		-- After the last move lets go, the stick is the player's again: no Move, no sprint.
		local final = moves[#moves]
		untilElapsed(world, started, final.at + final.hold + 0.1)
		local count = #world.body.moves
		world.seconds(0.3)
		expect(#world.body.moves).toBe(count)
		expect(world.body.sprinting).toBe(false)
	end)
end)

-- Stages the way DevStage does (D-244): a root standing in the shot's ring stages; one outside it
-- gets the ring and a route there (the real DevStageLogic rules).
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

local function inRing(world: World, open: boolean): boolean
	local at = world.body.root.Position
	return StageLogic.inRing(StageLogic.ring(open, STAGE), at.X, at.Y - ROOT_OFFSET, at.Z)
end

describe("Capture: the walk into the stand ring (D-244)", function()
	it("steps between the control script's input and the character controller", function()
		local world = load()
		local Choreo = Harness.load("src/shared/data/choreo")
		expect(#world.steps).toBe(1)
		local priority = world.steps[1].priority
		expect(priority).toBe(Enum.RenderPriority.Input.Value + WALK.renderOrder.offset)
		local character = (Enum.RenderPriority :: any)[Choreo.renderOrder.character.base].Value
			+ Choreo.renderOrder.character.offset
		expect(priority > Enum.RenderPriority.Input.Value and priority < character).toBe(true)
	end)

	it("marks the ring, walks the body in through Humanoid:Move, then asks again and stages", function()
		local world = load()
		ringServer(world)
		goTo(world, "art-horizontal")
		world.standAt(25, 30)
		world.key(KEYS.startCountdown)
		expect(#stageAsks(world)).toBe(1)
		-- The ring: a flat cyan disc on the spot, the stand ring's size, nothing to collide with.
		local ring = world.ring()
		expect(ring ~= nil).toBe(true)
		local x, y, z, facing = StageLogic.standSpot(false, STAGE.area, STAGE.ledge)
		expect(ring.Shape).toBe(Enum.PartType.Cylinder)
		expect(ring.Anchored).toBe(true)
		expect(ring.CanCollide).toBe(false)
		expect(ring.CanQuery).toBe(false)
		expect(ring.CanTouch).toBe(false)
		expect(ring.Material).toBe((Enum.Material :: any)[WALK.ring.material])
		expect(ring.Color).toBe(Harness.load("src/shared/data/palette").color3(WALK.ring.colorToken))
		local diameter = STAGE.standRadius * 2
		expect((ring.Size - Vector3.new(WALK.ring.thickness, diameter, diameter)).Magnitude).toBeLessThan(1e-4)
		expect((ring.CFrame.Position - Vector3.new(x, y + WALK.ring.thickness / 2, z)).Magnitude).toBeLessThan(1e-4)
		expect(ring.CFrame.RightVector:Dot(Vector3.yAxis)).toBeCloseTo(1, 1e-6)
		expect(world.status():find("Walk into the ring", 1, true)).never.toBeNil()
		expect(world.clears).toBe(1) -- no lock turns the walking body
		-- The walk: flat unit directions in world space, the last along the spot's facing.
		expect(untilCountdown(world, WALK.timeoutSeconds)).toBe(true)
		local moves = world.body.moves
		expect(#moves).toBeGreaterThan(0)
		for _, move in moves do
			expect(move.relative).toBe(false)
			expect(move.direction.Y).toBe(0)
			expect(move.direction.Magnitude).toBeCloseTo(1, 1e-5)
		end
		-- Its last leg follows the facing line: the last move runs the shot's way within restDegrees.
		local lx, lz = StageLogic.look(facing)
		expect(moves[#moves].direction:Dot(Vector3.new(lx, 0, lz))).toBeGreaterThan(
			math.cos(math.rad(WALK.restDegrees))
		)
		-- At the sprint (its stop carries nothing), let go and at rest on the spot.
		local sprints = 0
		for _, entry in world.handled do
			if entry.action == WALK.sprintAction then
				sprints += 1
				expect(entry.state).toBe(if sprints % 2 == 1 then "Begin" else "End")
			end
		end
		expect(sprints).toBe(2)
		local at = world.body.root.Position
		expect(Vector3.new(at.X - x, 0, at.Z - z).Magnitude).toBeLessThan(WALK.restStuds)
		-- Asked again once in the ring at rest: staged, the ring gone, the shot framed.
		expect(#stageAsks(world)).toBe(2)
		expect(inRing(world, false)).toBe(true)
		expect(world.ring()).toBeNil()
		expect(world.lockOns[#world.lockOns]).toBe(world.kobold.id)
		world.untilRecording()
		expect(world.counter().Visible).toBe(true)
	end)

	it("climbs the ramp from the field to the open shot's ring on the ledge's top, round the ledge", function()
		local world = load()
		ringServer(world)
		goTo(world, "locomotion")
		world.key(KEYS.startCountdown)
		local ring = world.ring()
		local ledge = STAGE.ledge
		local top = ledge.position[2] + ledge.size[2] / 2
		expect(ring.CFrame.Position.Y).toBeCloseTo(top + WALK.ring.thickness / 2, 1e-4)
		expect(untilCountdown(world, WALK.timeoutSeconds)).toBe(true)
		expect(inRing(world, true)).toBe(true)
		-- Up the ramp from its foot: the first point inside the ledge and ramp's footprint is on
		-- the ramp's low end, and none is on the field beside them.
		local edge = ledge.position[3] + ledge.size[3] / 2
		local half = math.max(ledge.size[1], ledge.ramp.size[1]) / 2
		local first: Vector3? = nil
		for _, at in world.body.trail do
			local inside = math.abs(at.X - ledge.position[1]) < half
				and at.Z > ledge.position[3] - ledge.size[3] / 2
				and at.Z < edge + ledge.ramp.size[3]
			if inside then
				expect(StageLogic.onLedge(ledge, at.X, at.Z) or StageLogic.onRamp(ledge, at.X, at.Z)).toBe(true)
				first = first or at
			end
		end
		expect(first ~= nil).toBe(true)
		expect(StageLogic.onRamp(ledge, (first :: Vector3).X, (first :: Vector3).Z)).toBe(true)
		expect((first :: Vector3).Z).toBeGreaterThan(edge + ledge.ramp.size[3] - 1)
		-- The last leg runs along the shot's facing (-Z): the walk turned the body the shot's way.
		local moves = world.body.moves
		local lx, lz = StageLogic.look(ledge.facing)
		expect(moves[#moves].direction:Dot(Vector3.new(lx, 0, lz))).toBeGreaterThan(0.999)
	end)

	it("hands the walk to the player on a movement key: the ring stays, the ask comes once in it", function()
		local world = load()
		ringServer(world)
		goTo(world, "art-vertical")
		world.standAt(25, 30)
		world.key(KEYS.startCountdown)
		world.frames(10)
		local walked = #world.body.moves
		expect(walked).toBeGreaterThan(0)
		world.key(WALK.cancelKeys[1])
		world.frames(30)
		expect(#world.body.moves).toBe(walked)
		expect(world.ring() ~= nil).toBe(true)
		expect(world.status():find("yourself", 1, true)).never.toBeNil()
		expect(#stageAsks(world)).toBe(1)
		-- The player walks in.
		world.standAt(STAGE.area.position[1] + 1, STAGE.area.position[3])
		expect(untilCountdown(world, 1)).toBe(true)
		expect(#stageAsks(world)).toBe(2)
		expect(world.ring()).toBeNil()
	end)

	it("ends the walk on J: the ring goes, the body is let go, the field is given back", function()
		local world = load()
		ringServer(world)
		world.standAt(25, 30)
		world.key(KEYS.startCountdown)
		world.frames(10)
		world.key(KEYS.releaseStage)
		expect(world.ring()).toBeNil()
		local walked = #world.body.moves
		world.seconds(2)
		expect(#world.body.moves).toBe(walked)
		expect(world.server.released).toBe(1)
		expect(world.status():find("Field given back", 1, true)).never.toBeNil()
		expect(#stageAsks(world)).toBe(1)
	end)

	it("stages afresh on P mid-walk, from where the body stands", function()
		local world = load()
		ringServer(world)
		world.standAt(25, 30)
		world.key(KEYS.startCountdown)
		world.frames(10)
		world.standAt(-40, 10)
		world.key(KEYS.startCountdown)
		expect(#stageAsks(world)).toBe(2)
		expect(world.ring() ~= nil).toBe(true)
		local walked = #world.body.moves
		world.frames(5)
		expect(#world.body.moves).toBeGreaterThan(walked)
		-- Heading from the new spot, not the old route.
		local last = world.body.moves[#world.body.moves].direction
		expect(last.X).toBeGreaterThan(0)
	end)

	it("ends a walk that gets nowhere at the timeout, naming what failed", function()
		local world = load()
		ringServer(world)
		world.body.stuck = true
		world.standAt(25, 30)
		world.key(KEYS.startCountdown)
		world.seconds(WALK.timeoutSeconds - 0.5)
		expect(world.ring() ~= nil).toBe(true)
		world.seconds(1)
		expect(world.ring()).toBeNil()
		local status = world.status()
		expect(status:find("Walk failed", 1, true)).never.toBeNil()
		expect(status:find("auto-walk", 1, true)).never.toBeNil()
		expect(status:find("studs from the spot", 1, true)).never.toBeNil()
		local walked = #world.body.moves
		world.seconds(1)
		expect(#world.body.moves).toBe(walked)
		expect(#stageAsks(world)).toBe(1)
		-- P stages again.
		world.key(KEYS.startCountdown)
		expect(#stageAsks(world)).toBe(2)
	end)

	it("asks again no faster than the server's rate", function()
		local world = load()
		ringServer(world)
		world.server.paced = true
		local area = STAGE.area
		-- Just outside the ring behind the spot: a short walk, in well inside the rate's gap.
		world.standAt(area.position[1], area.position[3] + STAGE.standRadius + 0.5)
		world.key(KEYS.startCountdown)
		expect(untilCountdown(world, 2)).toBe(true)
		local asks = stageAsks(world)
		expect(#asks).toBe(2)
		expect(asks[2].at - asks[1].at).toBeGreaterThanOrEqual(1 / STAGE.requestsPerSecond - 1e-9)
		expect(world.status():find("too many", 1, true)).toBeNil()
	end)

	it("walks the last leg again when the stop carried the body off the spot, and stages on it", function()
		local world = load()
		ringServer(world)
		world.standAt(25, 30)
		-- The stop carries the body on past the ring once.
		world.body.carry = STAGE.standRadius * 2
		world.key(KEYS.startCountdown)
		expect(untilCountdown(world, WALK.timeoutSeconds)).toBe(true)
		-- No ask from outside the ring: the last leg again brought it back first.
		expect(#stageAsks(world)).toBe(2)
		local at = world.body.root.Position
		local x, _, z = StageLogic.standSpot(false, STAGE.area, STAGE.ledge)
		expect(Vector3.new(at.X - x, 0, at.Z - z).Magnitude).toBeLessThan(WALK.restStuds)
	end)

	it("asks from where the second walks left it once they are spent: outside, it walks the new route", function()
		local world = load()
		ringServer(world)
		world.standAt(25, 30)
		-- Every stop slides on past the ring's far side: no let-go lands in it.
		world.body.slide = STAGE.standRadius * 3
		world.key(KEYS.startCountdown)
		for _ = 1, math.ceil(WALK.timeoutSeconds / FRAME) do
			world.frames(1)
			if #stageAsks(world) >= 2 then
				break
			end
		end
		expect(#stageAsks(world)).toBe(2)
		-- One let-go for the walk and one for each second walk before the ask: the walk's runs of
		-- moves, the first at the sprint, the corrections at a walk (CW: never the sprint again).
		local lets, last = 0, -math.huge
		for _, move in world.body.moves do
			if move.at > last + 1.5 * FRAME then
				lets += 1
			end
			last = move.at
		end
		expect(lets).toBe(1 + WALK.secondWalks)
		local sprints = 0
		for _, entry in world.handled do
			if entry.action == WALK.sprintAction and entry.state == "Begin" then
				sprints += 1
			end
		end
		expect(sprints).toBe(1)
		-- Never staged outside the ring: the reply walks it again.
		expect(inRing(world, false)).toBe(false)
		expect(world.ring() ~= nil).toBe(true)
		local walked = #world.body.moves
		world.frames(5)
		expect(#world.body.moves).toBeGreaterThan(walked)
	end)

	it("walks a new walk in from beside the ring once the second walks are spent, never at the sprint (CW)", function()
		local world = load()
		ringServer(world)
		world.standAt(25, 30)
		-- Every stop slides on to stand just outside the ring but beside its spot (within
		-- correctWithinStuds), until the second walks are spent.
		world.body.slide = (STAGE.standRadius + WALK.correctWithinStuds) / 2
		world.key(KEYS.startCountdown)
		for _ = 1, math.ceil(WALK.timeoutSeconds / FRAME) do
			world.frames(1)
			if #stageAsks(world) >= 2 then
				break
			end
		end
		expect(#stageAsks(world)).toBe(2)
		expect(inRing(world, false)).toBe(false)
		-- The engine stops sliding: the new walk walks the body in from where it stands and the
		-- shot stages (a body that only stood and asked again would never come in).
		world.body.slide = 0
		local walked = #world.body.moves
		expect(untilCountdown(world, WALK.timeoutSeconds)).toBe(true)
		expect(#world.body.moves).toBeGreaterThan(walked)
		expect(inRing(world, false)).toBe(true)
		local sprints = 0
		for _, entry in world.handled do
			if entry.action == WALK.sprintAction and entry.state == "Begin" then
				sprints += 1
			end
		end
		expect(sprints).toBe(1)
	end)
end)
