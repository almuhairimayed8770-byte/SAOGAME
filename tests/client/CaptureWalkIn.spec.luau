--!strict
--[[
	The staged walk-in as the owner's PC ran it (316(a)(b), round D on 1cf87aa, shot 2 from 8
	bearings): every stop 13 to 16 degrees off the shot's facing, up to 7 asks, a re-walk of the
	whole last leg at the sprint (to the approach point about 5.4 studs back and in again), and a
	take staged 13 to 14 degrees off. The body here is the PC's all at once: Studio's Humanoid
	acting on the move a frame late at its rates (360 studs/s/s up, 576 down), its AutoRotate
	turn trailing the move with a 0.1 s time constant (step 14's measurement) and the server
	reading the root as it replicated up to 0.3 s before. From every bearing the walk stages on the
	spot within walk.restStuds and walk.restDegrees, in at most two asks, never sprinting again
	after its first let-go.

	The harness is tests/client/CaptureWalk.spec.luau's (the real panel, controller, Choreo and
	Locomotion on a fake Humanoid and root), with one change: the trailing turn (world.turnTau)
	applies with the Studio-like engine too, so both run at once.
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local RealSiblings = Harness.load("src/client/controllers/Siblings")
local Dev = Harness.load("src/shared/data/dev")
local World = Harness.load("src/shared/data/world")
local Rigs = Harness.load("src/shared/data/rigs")
local StageLogic = Harness.load("src/server/dev/DevStageLogic")
local Locomotion = Harness.load("src/client/choreo/Locomotion")

local FRAME = 1 / 60
local CAPTURE = Dev.capture
local KEYS = CAPTURE.hotkeys
local STAGE = CAPTURE.stage
local WALK = CAPTURE.walk
local HIP = 2 -- the player's Humanoid.HipHeight in this world
local ROOT_SIZE = Vector3.new(2, 2, 1)
local ROOT_OFFSET = HIP + ROOT_SIZE.Y / 2 + World.spawn.groundEpsilon
local CONTROLLER_PATH = "src/client/controllers/CharacterController"
local CHOREO_PATH = "src/client/choreo/Choreo"
local CAPTURE_NODE = "src/client/dev/Capture"
local CAPTURE_FILE = "src/client/dev/Capture.client.luau"
local INPUT_PATH = "src/client/controllers/InputController"
local SPRINT_KEYS = Harness.load("src/shared/data/input").keyboard.Sprint

-- The default control script's movement keys, camera-relative (forward, right).
local KEY_MOVES: { [string]: { number } } = {
	W = { 1, 0 },
	Up = { 1, 0 },
	S = { -1, 0 },
	Down = { -1, 0 },
	D = { 0, 1 },
	Right = { 0, 1 },
	A = { 0, -1 },
	Left = { 0, -1 },
}

local function shotIndex(id: string): number
	for index, shot in CAPTURE.shots do
		if shot.id == id then
			return index
		end
	end
	error("no shot " .. id)
end

local function inertSignal(): any
	return {
		Connect = function(): any
			return { Disconnect = function() end }
		end,
	}
end

-- A fresh copy of Choreo (its own registry) whose frame loops never run: the controller steps the
-- local rig itself (stepLocal).
local function freshChoreo(): any
	local runService = {
		RenderStepped = inertSignal(),
		Heartbeat = inertSignal(),
		PreSimulation = inertSignal(),
		BindToRenderStep = function() end,
		UnbindFromRenderStep = function() end,
	}
	local env = Harness.environment()
	env.script = Harness.node(CHOREO_PATH)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			if name == "RunService" then
				return runService
			end
			return Harness.game():GetService(name)
		end,
	}
	return luau.load(Harness.readFile(CHOREO_PATH .. ".luau"), { debugName = CHOREO_PATH, environment = env :: any })()
end

-- A fresh copy of the real InputController (its own sprint holds), never started: nothing binds.
local function freshInput(): any
	local env = Harness.environment()
	env.script = Harness.node(INPUT_PATH)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return if name == "ReplicatedStorage" then Harness.game():GetService(name) else {}
		end,
	}
	return luau.load(Harness.readFile(INPUT_PATH .. ".luau"), { debugName = INPUT_PATH, environment = env :: any })()
end

-- A PlayerR15 rig model: one Part per rig part, one Motor6D per joint.
local function buildRig(): any
	local model = Instance.new("Model")
	model.Name = "PlayerR15"
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", false)
	local parts: { [string]: any } = {}
	local function part(name: string): any
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Position = Vector3.zero
		created.Parent = model
		parts[name] = created
		return created
	end
	for _, joint in Rigs.PlayerR15.joints do
		part(joint.part0)
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Parent = part(joint.part1)
	end
	model.PrimaryPart = parts.HumanoidRootPart
	return model
end

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

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Degrees between two flat directions.
local function degreesBetween(a: Vector3, b: Vector3): number
	local fa, fb = flat(a), flat(b)
	if fa.Magnitude == 0 or fb.Magnitude == 0 then
		return 180
	end
	return math.deg(math.acos(math.clamp(fa.Unit:Dot(fb.Unit), -1, 1)))
end

-- One request to the staging remote: when it went and its reply came, what the server answered
-- (stage: staged or not) and where the root stood and faced when the server read it.
type Ask = {
	action: string,
	shotId: string?,
	at: number,
	repliedAt: number?,
	ok: boolean?,
	position: Vector3,
	look: Vector3,
}

-- A Studio-like engine: the Humanoid's move acts `lag` frames late, the body's flat velocity
-- moves toward it at `accel` studs/s/s (`decel` when the move is zero: the stop's slide), and the
-- body turns toward the move at `turnRate` degrees a second.
type Engine = { lag: number, accel: number, decel: number, turnRate: number }

type Trail = { at: number, position: Vector3, speed: number, walkMove: boolean }

type World = {
	clock: { now: number },
	controller: any,
	root: any,
	humanoid: any,
	asks: { Ask },
	-- Seconds a staging request takes there and back (0: answered at once).
	latency: number,
	-- Studs the engine lets the body coast on after the Humanoid's move goes to zero (0: a dead
	-- stop, as the fake Humanoid stops): a stand-in for an engine whose stop slides.
	engineSlide: number,
	-- A Studio-like engine in place of the fake's dead-on moves (nil: none).
	engine: Engine?,
	-- Seconds the server's view of the root trails it (0: the root as it is): a request reads the
	-- root where it stood that long before.
	serverLag: number,
	-- Where the server's next read sees the root, once (a read from before it came to rest), or nil.
	staleRead: Vector3?,
	-- Seconds the body's turn toward its move trails it (0: turned at once, as the fake turns): a
	-- stand-in for Studio's AutoRotate, which closes the turn over a few frames and keeps the
	-- facing it had when the move stops.
	turnTau: number,
	-- The panel's calls into the input path: the action, Begin or End, when, and the source.
	handled: { { action: string, state: string, at: number, source: string? } },
	-- Every frame's root position, flat speed and whether the auto-walk gave the move.
	trail: { Trail },
	key: (name: string) -> (),
	hold: (name: string, down: boolean) -> (),
	frames: (count: number) -> (),
	seconds: (seconds: number) -> (),
	standAt: (x: number, z: number, facing: number?) -> (),
	-- The camera's flat forward, for the movement keys.
	setCamera: (forward: Vector3) -> (),
	walkMoves: () -> number,
	ring: () -> any,
	animator: () -> any,
	-- Whether the character controller has sprint on (the sprint key's path, Main.client).
	sprinting: () -> boolean,
}

local function load(): World
	local world: World = nil :: any
	local clock = { now = 10 }
	local steps: { { name: string, priority: number, fn: (number) -> () } } = {}
	local function bind(_self: any, name: string, priority: number, fn: (number) -> ())
		table.insert(steps, { name = name, priority = priority, fn = fn })
		table.sort(steps, function(a: any, b: any): boolean
			return a.priority < b.priority
		end)
	end
	local renderStepped = Signal.new()
	local heartbeat = Signal.new()
	local inputBegan = Signal.new()
	local timers: { { at: number, fn: () -> () } } = {}
	-- The task scheduler: a spawned thread runs at once; one that waits (task.wait, or a server
	-- call on its way) is resumed after Heartbeat on the first frame its moment has come.
	local threads: { { thread: thread, at: number } } = {}
	local function resume(thread: thread, ...: any)
		local ok, problem = coroutine.resume(thread, ...)
		if not ok then
			error(debug.traceback(thread, tostring(problem)), 0)
		end
	end
	local function waitFor(seconds: number?): number
		assert(coroutine.isyieldable(), "task.wait outside a task")
		local started = clock.now
		table.insert(threads, { thread = coroutine.running(), at = clock.now + math.max(seconds or 0, 0) })
		coroutine.yield()
		return clock.now - started
	end
	local function runThreads()
		local due: { { thread: thread, at: number } } = {}
		for index = #threads, 1, -1 do
			if threads[index].at <= clock.now + 1e-9 then
				table.insert(due, table.remove(threads, index) :: any)
			end
		end
		table.sort(due, function(a: any, b: any): boolean
			return a.at < b.at
		end)
		for _, entry in due do
			resume(entry.thread)
		end
	end
	local function runTimers()
		while true do
			local due: number? = nil
			for index, timer in timers do
				if timer.at <= clock.now and (due == nil or timer.at < timers[due :: number].at) then
					due = index
				end
			end
			if due == nil then
				return
			end
			local timer = table.remove(timers, due :: number)
			if timer ~= nil then
				timer.fn()
			end
		end
	end

	-- The character: a real rig for the animator, a fake Humanoid and root for the engine.
	local rig = buildRig()
	local props: { [string]: any } = {
		WalkSpeed = 16,
		JumpPower = 0,
		JumpHeight = 0,
		HipHeight = HIP,
		AutoRotate = true,
		MoveDirection = Vector3.zero,
		FloorMaterial = Enum.Material.Grass,
	}
	-- The auto-walk's Move this frame (after the control script's), for the trail.
	local walkMoved = false
	local walkMoves = 0
	-- The Humanoid walks at WalkSpeed x the move's length up to 1: a stick pushed part way walks
	-- slower (a half-magnitude Move walks at 8 studs/s in Studio, PROGRESS item 128).
	function props.Move(_self: any, direction: Vector3, _relative: boolean?)
		local length = direction.Magnitude
		props.MoveDirection = if length > 1 then direction.Unit elseif length > 0 then direction else Vector3.zero
	end
	local humanoid: any = setmetatable({}, {
		__index = props,
		__newindex = function(_self: any, key: string, value: any)
			props[key] = value
		end,
	})
	local rootState: { [string]: any } = {
		CFrame = CFrame.new(),
		AssemblyLinearVelocity = Vector3.zero,
		AssemblyAngularVelocity = Vector3.zero,
		Size = ROOT_SIZE,
	}
	local function sync()
		rig.PrimaryPart.CFrame = rootState.CFrame
	end
	local root: any = setmetatable({}, {
		__index = function(_self: any, key: string): any
			if key == "Position" then
				return rootState.CFrame.Position
			end
			return rootState[key]
		end,
		__newindex = function(_self: any, key: string, value: any)
			if key == "Position" then
				rootState.CFrame = rootState.CFrame.Rotation + value
			else
				rootState[key] = value
			end
			sync()
		end,
	})
	local character: any = {
		Name = "Player1",
		PrimaryPart = root,
		WaitForChild = function(_self: any, name: string): any
			return if name == "Humanoid" then humanoid else root
		end,
		FindFirstChildOfClass = function(_self: any, className: string): any
			return if className == "Humanoid" then humanoid else nil
		end,
		GetAttribute = function(_self: any, name: string): any
			return rig:GetAttribute(name)
		end,
		GetAttributeChangedSignal = function(): any
			return Signal.new()
		end,
	}
	local playerGui = Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	local player: any = {
		Character = character,
		CharacterAdded = Signal.new(),
		CharacterRemoving = Signal.new(),
		WaitForChild = function(_self: any, name: string): any
			return if name == "PlayerGui" then playerGui else nil
		end,
	}
	-- No lock in these takes: the walk clears it, and none of these shots is framed.
	local target = {
		current = function(): any
			return nil
		end,
		clear = function() end,
		lockOn = function(): boolean
			return true
		end,
		assistCandidates = function(): { any }
			return {}
		end,
	}

	-- The real CharacterController on the real Locomotion and a fresh Choreo.
	local choreo = freshChoreo()
	choreo.configure({
		now = function(): number
			return clock.now
		end,
		cameraPosition = function(): Vector3
			return Vector3.zero
		end,
	})
	local animator: any = nil
	local function animatorOf(): any
		if animator == nil then
			animator = choreo.get(rig)
		end
		return animator
	end
	local choreoWrap = {
		get = function(_model: any): any
			return animatorOf()
		end,
		find = function(_model: any): any
			return animator
		end,
		setLocalModel = function() end,
		stepLocal = function(dt: number)
			animatorOf():step(dt)
		end,
	}
	local locomotionWrap = setmetatable({
		new = function(anim: any, _model: any): any
			return Locomotion.new(anim, rig, { footIK = false })
		end,
	}, { __index = Locomotion })
	local controllerFakes: { [string]: any } = {
		Net = {
			client = function(): any
				return { fire = function() end, on = function() end }
			end,
		},
		EntityTracker = {
			localRecord = function(): any
				return nil
			end,
			get = function(): any
				return nil
			end,
			peekLocalId = function(): any
				return nil
			end,
			changed = Signal.new(),
			localChanged = Signal.new(),
		},
		Replication = {
			rejected = Signal.new(),
			hit = Signal.new(),
			clipEvent = Signal.new(),
			contact = function(): boolean
				return true
			end,
			confirmedAlready = function(): boolean
				return false
			end,
		},
		CameraController = {
			fovKick = function() end,
			lockMove = function(direction: Vector3): Vector3
				return direction
			end,
		},
		ContactPredictor = {
			standOff = function(): any
				return nil
			end,
			worldCast = function(): any
				return function(): number?
					return nil
				end
			end,
			new = function(): any
				return {
					begin = function(): boolean
						return false
					end,
					stop = function() end,
					active = function(): boolean
						return false
					end,
					step = function(): { any }
						return {}
					end,
				}
			end,
		},
		Siblings = {
			load = function(_parent: any, path: string): (any, boolean)
				if path == "choreo.Locomotion" then
					return locomotionWrap, true
				end
				if path == "choreo.Choreo" then
					return choreoWrap, true
				end
				if path == "controllers.TargetController" then
					return target, true
				end
				if path == "choreo.DrawnBody" then
					return Harness.load("src/client/choreo/DrawnBody"), true
				end
				return RealSiblings.stub(), false
			end,
			call = RealSiblings.call,
			stub = RealSiblings.stub,
		},
	}
	local runService = {
		BindToRenderStep = bind,
		UnbindFromRenderStep = function() end,
		RenderStepped = renderStepped,
		Heartbeat = heartbeat,
		PreSimulation = Signal.new(),
		IsStudio = function(): boolean
			return true
		end,
	}
	local task = {
		delay = function(seconds: number, fn: (...any) -> (), ...: any)
			local args = table.pack(...)
			table.insert(timers, {
				at = clock.now + seconds,
				fn = function()
					fn(table.unpack(args, 1, args.n))
				end,
			})
		end,
		spawn = function(fn: (...any) -> (), ...: any)
			resume(coroutine.create(fn), ...)
		end,
		defer = function(fn: (...any) -> (), ...: any)
			resume(coroutine.create(fn), ...)
		end,
		wait = waitFor,
	}
	local controllerEnv = Harness.environment()
	controllerEnv.script = Harness.node(CONTROLLER_PATH)
	controllerEnv.require = function(node: any): any
		return controllerFakes[node.Name] or Harness.loadModule(node)
	end
	controllerEnv.game = {
		GetService = function(_self: any, name: string): any
			if name == "RunService" then
				return runService
			elseif name == "Players" then
				return { LocalPlayer = player }
			end
			return Harness.game():GetService(name)
		end,
	}
	controllerEnv.workspace = {
		GetServerTimeNow = function(): number
			return clock.now
		end,
		GetAttribute = function(_self: any, name: string): any
			return if name == Dev.attributes.capture then true else nil
		end,
	}
	controllerEnv.os = {
		clock = function(): number
			return clock.now
		end,
	}
	controllerEnv.task = task
	local controller = luau.load(
		Harness.readFile(CONTROLLER_PATH .. ".luau"),
		{ debugName = CONTROLLER_PATH, environment = controllerEnv :: any }
	)()
	controller.start()

	-- Where the server sees the root now: as it stood world.serverLag ago (the oldest frame kept
	-- when none is that old), or the stale read a test set, once.
	local history: { { at: number, position: Vector3, look: Vector3 } } = {}
	local function serverView(): (Vector3, Vector3)
		local stale = world.staleRead
		if stale ~= nil then
			world.staleRead = nil
			return stale, rootState.CFrame.LookVector
		end
		if world.serverLag <= 0 or #history == 0 then
			return root.Position, rootState.CFrame.LookVector
		end
		local seen = history[1]
		for _, entry in history do
			if entry.at <= clock.now - world.serverLag + 1e-9 then
				seen = entry
			end
		end
		return seen.position, seen.look
	end

	-- The capture panel, with the staging server's real ring rule.
	local asks: { Ask } = {}
	local serve: (entry: Ask) -> any
	local remote = {
		ClassName = "RemoteFunction",
		IsA = function(_self: any, className: string): boolean
			return className == "RemoteFunction"
		end,
		InvokeServer = function(_self: any, action: string, shotId: string?): any
			local position, look = serverView()
			local entry: Ask = {
				action = action,
				shotId = shotId,
				at = clock.now,
				position = position,
				look = look,
			}
			table.insert(asks, entry)
			-- On its way: the server reads the root half the round trip later, the reply comes after
			-- the whole of it.
			local latency = world.latency
			if latency > 0 then
				waitFor(latency / 2)
				entry.position, entry.look = serverView()
			end
			local reply = serve(entry)
			if latency > 0 then
				waitFor(latency / 2)
			end
			entry.repliedAt = clock.now
			return reply
		end,
	}
	function serve(entry: Ask): any
		local action, shotId = entry.action, entry.shotId
		if action ~= "stage" then
			return { ok = true }
		end
		local shot = CAPTURE.shots[shotIndex(shotId :: string)]
		local open = shot.stage.open
		local ring = StageLogic.ring(open, STAGE)
		local at = entry.position
		if StageLogic.inRing(ring, at.X, at.Y - ROOT_OFFSET, at.Z) then
			entry.ok = true
			return { ok = true, targetId = 21, ids = { 21 } }
		end
		entry.ok = false
		local walk = table.clone(ring) :: any
		walk.path = StageLogic.route(open, STAGE, true, at.X, at.Z)
		return { ok = false, error = "walk into the ring first", walk = walk }
	end
	local realReplicated = Harness.game():GetService("ReplicatedStorage")
	local handled: { { action: string, state: string, at: number, source: string? } } = {}
	local sprintOn = false
	-- The real input path for the sprint, held per source (D-338); its sprintChanged drives
	-- CharacterController.setSprinting (Main.client).
	local input = freshInput()
	input.sprintChanged:Connect(function(on: boolean)
		sprintOn = on
		controller.setSprinting(on)
	end)
	local held: { [string]: boolean } = {}
	local kobold = { id = 21, kind = "Enemy", model = { Name = "Kobold" } }
	local captureFakes: { [string]: any } = {
		CameraController = { setStage = function() end },
		TargetController = target,
		InputController = {
			handle = function(action: string, state: any, object: any, source: string?)
				table.insert(handled, { action = action, state = state.Name, at = clock.now, source = source })
				if action == "Sprint" then
					input.handle(action, state, object, source)
				end
			end,
		},
		EntityTracker = {
			get = function(id: number): any
				return if id == kobold.id then kobold else nil
			end,
		},
		Replication = { clipEvent = Signal.new(), hit = Signal.new() },
		ClipLibrary = {
			get = function(id: string): any
				error("no clip " .. id)
			end,
		},
		Siblings = {
			load = function(_parent: any, path: string): (any, boolean)
				if path == "controllers.CharacterController" then
					return controller, true
				end
				return {}, false
			end,
			call = function(module: any, name: string, ...: any): any
				local fn = rawget(module, name)
				return if typeof(fn) == "function" then fn(...) else nil
			end,
		},
	}
	local workspaceFolder = Instance.new("Folder")
	workspaceFolder.Name = "Workspace"
	workspaceFolder:SetAttribute(Dev.attributes.capture, true)
	local captureServices: { [string]: any } = {
		Players = { LocalPlayer = player },
		ReplicatedStorage = {
			WaitForChild = function(_self: any, name: string): any
				return realReplicated:WaitForChild(name)
			end,
			FindFirstChild = function(_self: any, name: string): any
				return if name == STAGE.remoteName then remote else nil
			end,
		},
		RunService = { RenderStepped = renderStepped, BindToRenderStep = bind },
		UserInputService = {
			InputBegan = inputBegan,
			MouseIconEnabled = true,
			IsKeyDown = function(_self: any, code: Enum.KeyCode): boolean
				return held[code.Name] == true
			end,
		},
		CollectionService = {
			GetTagged = function(): { any }
				return {}
			end,
		},
	}
	local captureEnv = Harness.environment()
	captureEnv.script = Harness.node(CAPTURE_NODE)
	captureEnv.require = function(node: any): any
		return captureFakes[node.Name] or Harness.loadModule(node)
	end
	captureEnv.game = {
		GetService = function(_self: any, name: string): any
			return captureServices[name] or error("no service " .. name)
		end,
	}
	captureEnv.workspace = workspaceFolder
	captureEnv.task = task
	captureEnv.os = controllerEnv.os

	-- The walk's render step: the auto-walk's Move is the one that lands after the control script's.
	local cameraForward = Vector3.new(0, 0, -1)
	local trail: { Trail } = {}
	local coast = 0
	local lastVelocity = Vector3.zero
	-- The Studio-like engine's state: the moves on their way and the body's flat velocity.
	local pending: { Vector3 } = {}
	local engineVelocity = Vector3.zero
	local function keysMove(): Vector3
		local forward, right = 0, 0
		for name, down in held do
			local move = KEY_MOVES[name]
			if down and move ~= nil then
				forward += move[1]
				right += move[2]
			end
		end
		local look = cameraForward.Unit
		local side = Vector3.new(-look.Z, 0, look.X)
		return look * forward + side * right
	end

	local function frame()
		clock.now += FRAME
		-- The control script's Move: the keys held, every frame (zero for none).
		humanoid:Move(keysMove(), false)
		local before = props.MoveDirection
		walkMoved = false
		for _, step in steps do
			step.fn(FRAME)
			if step.name == "SkyspireCaptureWalk" and props.MoveDirection ~= before then
				walkMoved = true
			end
		end
		if walkMoved then
			walkMoves += 1
		end
		renderStepped:Fire(FRAME)
		-- Physics: the root moves at the Humanoid's move and speed over the floor, turned to its move.
		-- An engine that slides its stops coasts on along the last move for engineSlide studs.
		local move = flat(props.MoveDirection)
		local velocity = move * props.WalkSpeed
		local engine = world.engine
		if engine ~= nil then
			-- The Studio-like engine: the move of `lag` frames ago, reached at its rates.
			table.insert(pending, velocity)
			local applied = Vector3.zero
			if #pending > engine.lag then
				applied = table.remove(pending, 1) :: Vector3
			end
			local change = applied - engineVelocity
			local rate = if applied.Magnitude < 1e-6 then engine.decel else engine.accel
			if change.Magnitude > 1e-9 then
				engineVelocity += change.Unit * math.min(change.Magnitude, rate * FRAME)
			end
			velocity = engineVelocity
			move = if applied.Magnitude > 1e-6 then applied.Unit else Vector3.zero
		elseif move.Magnitude > 0 then
			coast = world.engineSlide
			lastVelocity = velocity
		elseif coast > 0 and lastVelocity.Magnitude > 0 then
			local step = math.min(coast, lastVelocity.Magnitude * FRAME)
			coast -= step
			velocity = lastVelocity.Unit * step / FRAME
		end
		local position = rootState.CFrame.Position
		local x, z = position.X + velocity.X * FRAME, position.Z + velocity.Z * FRAME
		local y = floorAt(x, z) + ROOT_OFFSET
		rootState.AssemblyLinearVelocity = Vector3.new(velocity.X, (y - position.Y) / FRAME, velocity.Z)
		local at = Vector3.new(x, y, z)
		if props.AutoRotate and move.Magnitude > 0 and engine ~= nil and world.turnTau <= 0 then
			-- Turned toward the move at the engine's rate.
			local look = flat(rootState.CFrame.LookVector).Unit
			local angle = math.atan2(look.X * move.Z - look.Z * move.X, look:Dot(move))
			local most = math.rad(engine.turnRate) * FRAME
			local turn = math.clamp(angle, -most, most)
			local c, sn = math.cos(turn), math.sin(turn)
			rootState.CFrame =
				CFrame.lookAt(at, at + Vector3.new(look.X * c - look.Z * sn, 0, look.X * sn + look.Z * c))
		elseif props.AutoRotate and move.Magnitude > 0 and world.turnTau > 0 then
			-- Turned toward the move by 1 - e^(-dt / turnTau) of what is left of the turn.
			local look = flat(rootState.CFrame.LookVector).Unit
			local angle = math.atan2(look.X * move.Z - look.Z * move.X, look:Dot(move))
			local turn = angle * (1 - math.exp(-FRAME / world.turnTau))
			local c, s = math.cos(turn), math.sin(turn)
			rootState.CFrame = CFrame.lookAt(at, at + Vector3.new(look.X * c - look.Z * s, 0, look.X * s + look.Z * c))
		elseif props.AutoRotate and move.Magnitude > 0 then
			rootState.CFrame = CFrame.lookAt(at, at + move)
		else
			rootState.CFrame = rootState.CFrame.Rotation + at
		end
		sync()
		table.insert(trail, { at = clock.now, position = at, speed = flat(velocity).Magnitude, walkMove = walkMoved })
		table.insert(history, { at = clock.now, position = at, look = rootState.CFrame.LookVector })
		heartbeat:Fire(FRAME)
		runTimers()
		runThreads()
	end

	world = {
		clock = clock,
		controller = controller,
		root = root,
		humanoid = humanoid,
		asks = asks,
		latency = 0,
		engineSlide = 0,
		engine = nil,
		serverLag = 0,
		staleRead = nil,
		turnTau = 0,
		handled = handled,
		trail = trail,
		key = function(name: string)
			inputBegan:Fire(
				{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = (Enum.KeyCode :: any)[name] },
				false
			)
		end,
		hold = function(name: string, down: boolean)
			local object = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = (Enum.KeyCode :: any)[name] }
			if down and not held[name] then
				-- The control script binds the movement keys, ContextActionService the sprint key:
				-- they come processed.
				inputBegan:Fire(object, true)
			end
			if table.find(SPRINT_KEYS, name) ~= nil and down ~= (held[name] == true) then
				-- The sprint key's binding hands it to the input path as the player's (no source).
				input.handle("Sprint", if down then Enum.UserInputState.Begin else Enum.UserInputState.End, object)
			end
			held[name] = down
		end,
		frames = function(count: number)
			for _ = 1, count do
				frame()
			end
		end,
		seconds = function(seconds: number)
			world.frames(math.round(seconds / FRAME))
		end,
		standAt = function(x: number, z: number, facing: number?)
			local lx, lz = StageLogic.look(facing or 0)
			local at = Vector3.new(x, floorAt(x, z) + ROOT_OFFSET, z)
			rootState.CFrame = CFrame.lookAt(at, at + Vector3.new(lx, 0, lz))
			rootState.AssemblyLinearVelocity = Vector3.zero
			engineVelocity = Vector3.zero
			table.clear(pending)
			table.clear(history)
			sync()
		end,
		setCamera = function(forward: Vector3)
			cameraForward = flat(forward)
		end,
		walkMoves = function(): number
			return walkMoves
		end,
		ring = function(): any
			return workspaceFolder:FindFirstChild(WALK.ring.name)
		end,
		animator = function(): any
			return animatorOf()
		end,
		sprinting = function(): boolean
			return sprintOn
		end,
	}
	world.standAt(STAGE.area.position[1], STAGE.area.position[3], STAGE.area.facing)
	luau.load(Harness.readFile(CAPTURE_FILE), { debugName = CAPTURE_FILE, environment = captureEnv :: any })()
	-- The idle body settles first (its gait at rest).
	world.frames(30)
	return world
end

local function goTo(world: World, id: string)
	for _ = 1, shotIndex(id) - 1 do
		world.key(KEYS.nextShot)
	end
end

local function stageAsks(world: World): { Ask }
	local list = {}
	for _, ask in world.asks do
		if ask.action == "stage" then
			table.insert(list, ask)
		end
	end
	return list
end

-- The ask that staged (the root at rest in the ring), or nil.
local function staged(world: World): Ask?
	for _, ask in stageAsks(world) do
		if ask.ok == true then
			return ask
		end
	end
	return nil
end

type Arrival = { distance: number, degrees: number, asks: number, seconds: number, staged: boolean }

-- Where the shot's ring is and which way it faces.
local function ringOf(shotId: string): (any, Vector3)
	local open = CAPTURE.shots[shotIndex(shotId)].stage.open
	local ring = StageLogic.ring(open, STAGE)
	local lx, lz = StageLogic.look(ring.facing)
	return ring, Vector3.new(lx, 0, lz)
end

-- Runs frames until the shot stages or `seconds` pass.
local function untilStaged(world: World, seconds: number)
	local started = world.clock.now
	while staged(world) == nil and world.clock.now - started < seconds do
		world.frames(1)
	end
end

-- Walks from (x, z) facing `facing` into the shot's ring: where the body stood and faced when it
-- staged, against the spot, how many stage asks it took and how long. `setup` adjusts the world
-- (latency, an engine slide) before P.
local function arrive(shotId: string, x: number, z: number, facing: number?, setup: ((World) -> ())?): (Arrival, World)
	local world = load()
	goTo(world, shotId)
	if setup ~= nil then
		setup(world)
	end
	world.standAt(x, z, facing)
	world.frames(2)
	local started = world.clock.now
	world.key(KEYS.startCountdown)
	untilStaged(world, WALK.timeoutSeconds * 3)
	local ring, look = ringOf(shotId)
	local ask = staged(world)
	local result: Arrival = {
		distance = math.huge,
		degrees = 180,
		asks = #stageAsks(world),
		seconds = world.clock.now - started,
		staged = ask ~= nil,
	}
	if ask ~= nil then
		local at = ask.position
		result.distance = Vector3.new(at.X - ring.x, 0, at.Z - ring.z).Magnitude
		result.degrees = degreesBetween(ask.look, look)
	end
	return result, world
end

type Start = { x: number, z: number, label: string }

local STUDIO: Engine = { lag = 1, accel = 360, decel = 576, turnRate = 720 }
local STUDIO_TURN_TAU = 0.1

local function sprintBegins(world: World): number
	local count = 0
	for _, entry in world.handled do
		if entry.action == WALK.sprintAction and entry.state == "Begin" then
			count += 1
		end
	end
	return count
end

describe("Capture: the walk-in on the owner's PC body (316(a)(b))", function()
	it("stages on the spot facing the shot's way from 8 bearings, in two asks, sprinting once", function()
		local ring = ringOf("art-horizontal")
		local lines = {}
		local worst = { degrees = 0, distance = 0, asks = 0, sprints = 0 }
		for _, variant in
			{
				{ label = "trailing turn", engine = nil :: Engine?, lag = 0 },
				{ label = "Studio body, server 0.1 s behind", engine = STUDIO :: Engine?, lag = 0.1 },
				{ label = "Studio body, server 0.3 s behind", engine = STUDIO :: Engine?, lag = 0.3 },
			}
		do
			for bearing = 0, 315, 45 do
				local lx, lz = StageLogic.look(bearing)
				local result, world = arrive(
					"art-horizontal",
					ring.x + lx * 12,
					ring.z + lz * 12,
					90,
					function(w: World)
						w.engine = variant.engine
						w.serverLag = variant.lag
						w.turnTau = STUDIO_TURN_TAU
					end
				)
				local sprints = sprintBegins(world)
				table.insert(
					lines,
					("%s, 12@%d: %s %.2f studs %.1f deg, %d asks, %d sprints"):format(
						variant.label,
						bearing,
						if result.staged then "staged" else "NOT STAGED",
						result.distance,
						result.degrees,
						result.asks,
						sprints
					)
				)
				expect(result.staged).toBe(true)
				worst.degrees = math.max(worst.degrees, result.degrees)
				worst.distance = math.max(worst.distance, result.distance)
				worst.asks = math.max(worst.asks, result.asks)
				worst.sprints = math.max(worst.sprints, sprints)
			end
		end
		print("[316 PC body] " .. table.concat(lines, "\n[316 PC body] "))
		expect(worst.distance).toBeLessThanOrEqual(WALK.restStuds)
		expect(worst.degrees).toBeLessThanOrEqual(WALK.restDegrees)
		expect(worst.asks).toBeLessThanOrEqual(2)
		expect(worst.sprints).toBe(1)
	end)
end)
