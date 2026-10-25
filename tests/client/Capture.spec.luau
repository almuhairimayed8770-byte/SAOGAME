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
	character controller, then asks for the shot again (at the server's rate) once the body is at
	rest; a movement key hands the walk over, J and P end it, and the timeout ends it with a note.
	The character is a fake body that moves at a set speed along each frame's Move, on the field,
	the ledge's top or its ramp, and the staging server's fake stages by the real ring rule
	(DevStageLogic).
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local Dev = Harness.load("src/shared/data/dev")
local Overhead = Harness.load("src/shared/clips/enemy/Kobold/Overhead")
local World = Harness.load("src/shared/data/world")
local StageLogic = Harness.load("src/server/dev/DevStageLogic")

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
-- frame's Humanoid:Move (none: it stops, after `carry` studs more along its last move if set),
-- standing on the field, the ledge's top or its ramp; `stuck` keeps it where it is.
type Body = {
	root: any,
	humanoid: any,
	moves: { { direction: Vector3, relative: boolean?, at: number } },
	pending: Vector3?,
	lastDirection: Vector3?,
	carry: number,
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
	status: () -> string,
	invokes: { { action: string, shotId: string?, at: number } },
	reply: { [string]: any },
	stages: { { view: any, target: any, side: number? } },
	lockOns: { any },
	clears: number,
	handled: { { action: string, state: string, at: number } },
	input: any,
	userInput: any,
	replication: any,
	key: (name: string) -> (),
	frames: (count: number) -> (),
	seconds: (seconds: number) -> (),
	-- Runs until the take starts (the countdown done), returning the frame the counter first shows.
	untilRecording: () -> (),
	firstShown: { text: string? },
	kobold: any,
	body: Body,
	ring: () -> any,
	-- Stands the body with its feet on the floor under (x, z).
	standAt: (x: number, z: number) -> (),
	steps: { { name: string, priority: number, fn: (number) -> () } },
}

type Options = { remote: boolean?, capture: any }

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
	if direction ~= nil and not body.stuck then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		step = if flat.Magnitude > 0 then flat.Unit * SPEED * dt else Vector3.zero
		body.lastDirection = flat
	elseif direction == nil and body.carry > 0 and body.lastDirection ~= nil then
		local distance = math.min(body.carry, SPEED * dt)
		body.carry -= distance
		step = (body.lastDirection :: Vector3).Unit * distance
	end
	local x, z = root.Position.X + step.X, root.Position.Z + step.Z
	root.Position = Vector3.new(x, floorAt(x, z) + ROOT_OFFSET, z)
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
	local kobold = { id = 21, kind = "Enemy", model = { Name = "Kobold" } }
	local invokes: { { action: string, shotId: string?, at: number } } = {}
	local reply: { [string]: any } = { ok = true, targetId = 21, ids = { 21 } }
	local server: Server = { paced = false, stagingSeconds = 0, busyUntil = -math.huge, released = 0 }
	local remote = {
		ClassName = "RemoteFunction",
		IsA = function(_self: any, className: string): boolean
			return className == "RemoteFunction"
		end,
		InvokeServer = function(_self: any, action: string, shotId: string?): any
			table.insert(invokes, { action = action, shotId = shotId, at = clock.now })
			if server.paced then
				local last = server.lastAt
				if last ~= nil and clock.now - last < 1 / CAPTURE.stage.requestsPerSecond then
					return { ok = false, error = "too many requests" }
				end
				server.lastAt = clock.now
			end
			if clock.now < server.busyUntil then
				return { ok = false, error = "busy: a staging is still running" }
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
				return if answer ~= nil then answer(shotId :: string) else world.reply
			end
			if action == "release" then
				server.released += 1
			end
			return { ok = true }
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
	local userInput = { InputBegan = inputBegan, MouseIconEnabled = true }
	local stages: { { view: any, target: any, side: number? } } = {}
	local steps: { { name: string, priority: number, fn: (number) -> () } } = {}
	local body: Body = nil :: any
	body = {
		root = {
			Position = Vector3.zero,
			Size = ROOT_SIZE,
			AssemblyLinearVelocity = Vector3.zero,
		},
		humanoid = {
			HipHeight = HIP,
			Move = function(_self: any, direction: Vector3, relative: boolean?)
				table.insert(body.moves, { direction = direction, relative = relative, at = clock.now })
				body.pending = direction
			end,
		},
		moves = {},
		pending = nil,
		lastDirection = nil,
		carry = 0,
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
	local handled: { { action: string, state: string, at: number } } = {}
	local camera = {
		setStage = function(view: any, target: any, side: number?)
			table.insert(stages, { view = view, target = target, side = side })
		end,
	}
	local target = {
		lockOn = function(id: number?): boolean
			table.insert(lockOns, id or "nil")
			return true
		end,
		clear = function()
			world.clears += 1
		end,
	}
	local input = {
		handle = function(action: string, state: any, _object: any)
			table.insert(handled, { action = action, state = state.Name, at = clock.now })
		end,
	}
	local tracker = {
		get = function(id: number): any
			return if id == kobold.id then kobold else nil
		end,
	}
	local replication = { clipEvent = Signal.new() }
	local clipLibrary = {
		get = function(id: string): any
			if id == Overhead.id then
				return Overhead
			end
			error("no clip " .. id)
		end,
	}
	local character = {
		setCaptureTimeScale = function(_scale: number): boolean
			return true
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
		handled = handled,
		input = input,
		userInput = userInput,
		replication = replication,
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
		body = body,
		ring = function(): any
			return workspaceFolder:FindFirstChild(WALK.ring.name)
		end,
		standAt = function(x: number, z: number)
			body.root.Position = Vector3.new(x, floorAt(x, z) + ROOT_OFFSET, z)
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
		-- Its last leg starts within waypointStuds of the approach's point on the facing line.
		local lx, lz = StageLogic.look(facing)
		local off = math.atan(WALK.waypointStuds / (STAGE.approachStuds - WALK.arriveStuds))
		expect(moves[#moves].direction:Dot(Vector3.new(lx, 0, lz))).toBeGreaterThan(math.cos(off))
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

	it("asks again where the let-go carried the body out of the ring, and walks again", function()
		local world = load()
		ringServer(world)
		world.standAt(25, 30)
		-- The two-step stop carries the body on past the ring once.
		world.body.carry = STAGE.standRadius + WALK.arriveStuds + 1
		world.key(KEYS.startCountdown)
		expect(untilCountdown(world, WALK.timeoutSeconds)).toBe(true)
		expect(#stageAsks(world)).toBe(3)
		expect(inRing(world, false)).toBe(true)
	end)
end)
