--!strict
--[[
	The walk into the stand ring (D-244) through the real body (D-302 to D-305). A fresh copy of the
	capture panel (Capture.client.luau) walks the local character, and a fresh copy of the real
	CharacterController moves it: its two-step stop (D-059) runs on the real Locomotion's gait
	(stopGait) with the real Choreo animating a real PlayerR15 rig. The Humanoid is a fake whose
	physics moves the root at MoveDirection x WalkSpeed over the field, the ledge's top or its
	ramp, turned to its move while AutoRotate is on. A frame runs as the engine runs it: the
	control script's Move from the movement keys held (camera-relative), the bound render steps
	by priority (the walk, then the controller), RenderStepped, physics, Heartbeat, then the
	timers. The staging server stages by the real ring rule (DevStageLogic): a root at rest in the
	ring stages, one outside gets the ring and a route.

	1. Arrival (D-302, D-303): the walk brings the body to rest within capture.walk.restStuds of the spot,
	   facing the spot's way within restDegrees, from near and far, round the ledge and up its
	   ramp; one that the stop carries off the spot walks the short way back onto it.
	2. The hand-over (D-304): once a movement key went down after P, only the player's keys move the
	   body until P, across the asks between walks too.
	3. J (D-305): J lets the walk go, and the body stops as it stops when the keys let go: the same
	   two-step stop, no farther.
	4. The sprint's sources (D-338): the panel's sprint goes through a fresh copy of the real
	   InputController as the panel's own source, and the sprint key (LeftShift) as the player's,
	   as its ContextActionService binding hands it over; a Shift tap during the walk's sprint
	   leaves the walk as it was.
	5. A Studio-like body (CW): an engine that acts on the move a frame late, speeds up and slows
	   down at a rate and turns at a rate (world.engine), and a server that reads the root as it
	   replicated a moment ago (world.serverLag). From every bearing, round the ledge and below it,
	   the body comes to rest on the spot facing its way and stages there, never sprinting again
	   after the walk's first let-go: an off rest is corrected at a walk, at most
	   capture.walk.secondWalks times, and a walk asked for beside the spot does not move it. P
	   pressed again mid-walk asks only once the body has stood at rest: it never stages a body
	   still moving, nor one the server read in the ring that came to rest outside it.
	6. The facing (step 14): a body whose turn trails its move (world.turnTau, Studio's AutoRotate)
	   comes to rest on the spot short of the shot's facing; it turns there on the spot to it,
	   never walking again for the facing alone, and stages facing the shot's way.
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
		if props.AutoRotate and move.Magnitude > 0 and engine ~= nil then
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

-- The starts for a shot: round the stage area's spot at 5, 12 and 25 studs every 45 degrees; for
-- the open shot round the ledge at 25 studs every 45 degrees, at the ramp's foot, on its top and
-- across the ledge's top from the spot.
local function starts(open: boolean): { Start }
	local list: { Start } = {}
	if not open then
		local spot = STAGE.area.position
		for _, distance in { 5, 12, 25 } do
			for bearing = 0, 315, 45 do
				local lx, lz = StageLogic.look(bearing)
				table.insert(list, {
					x = spot[1] + lx * distance,
					z = spot[3] + lz * distance,
					label = ("area %g@%d"):format(distance, bearing),
				})
			end
		end
		return list
	end
	local ledge = STAGE.ledge
	local centre = ledge.position
	for bearing = 0, 315, 45 do
		local lx, lz = StageLogic.look(bearing)
		table.insert(list, {
			x = centre[1] + lx * 25,
			z = centre[3] + lz * 25,
			label = ("ledge 25@%d"):format(bearing),
		})
	end
	local edge = centre[3] + ledge.size[3] / 2
	table.insert(list, { x = centre[1], z = edge + ledge.ramp.size[3] - 1, label = "ramp foot" })
	table.insert(list, { x = centre[1], z = edge + ledge.ramp.size[3] / 2, label = "ramp middle" })
	table.insert(list, { x = centre[1] + 5, z = centre[3] - ledge.size[3] / 2 + 1, label = "ledge far corner" })
	table.insert(list, { x = centre[1], z = centre[3], label = "ledge centre" })
	return list
end

-- Arrives from every start of both spots; the lines and the worst.
local function arrivals(setup: ((World) -> ())?): ({ string }, Arrival)
	local worst: Arrival = { distance = 0, degrees = 0, asks = 0, seconds = 0, staged = true }
	local lines = {}
	for _, open in { false, true } do
		local shotId = if open then "locomotion" else "art-horizontal"
		for _, start in starts(open) do
			local result = arrive(shotId, start.x, start.z, 90, setup)
			table.insert(
				lines,
				("%s: %s %.2f studs %.1f deg %d asks %.1f s"):format(
					start.label,
					if result.staged then "staged" else "NOT STAGED",
					result.distance,
					result.degrees,
					result.asks,
					result.seconds
				)
			)
			worst.staged = worst.staged and result.staged
			worst.distance = math.max(worst.distance, result.distance)
			worst.degrees = math.max(worst.degrees, result.degrees)
			worst.asks = math.max(worst.asks, result.asks)
			worst.seconds = math.max(worst.seconds, result.seconds)
		end
	end
	return lines, worst
end

-- The auto-walk's moves since frame `from` of the trail (1-based).
local function walkMovesSince(world: World, from: number): number
	local count = 0
	for index = from, #world.trail do
		if world.trail[index].walkMove then
			count += 1
		end
	end
	return count
end

-- Frames until the root is at rest (flat speed under 0.01), at most `limit`.
local function untilRest(world: World, limit: number): number
	for index = 1, limit do
		world.frames(1)
		local v = world.root.AssemblyLinearVelocity
		if Vector3.new(v.X, 0, v.Z).Magnitude < 0.01 then
			return index
		end
	end
	return limit
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

describe("Capture: the walk into the ring through the real body (D-302)", function()
	it("rests on the spot facing the shot's way, from near and far, on the field and on the ledge", function()
		local lines, worst = arrivals(nil)
		print("[D-302] " .. table.concat(lines, "\n[D-302] "))
		print(
			("[D-302] worst %.2f studs, %.1f deg, %d asks, %.1f s"):format(
				worst.distance,
				worst.degrees,
				worst.asks,
				worst.seconds
			)
		)
		expect(worst.staged).toBe(true)
		expect(worst.distance).toBeLessThan(WALK.restStuds)
		expect(worst.degrees).toBeLessThan(WALK.restDegrees)
	end)

	it("walks the short way back onto the spot when the stop slides off it, staging only in the ring", function()
		-- An engine whose stop slides on 2.5 studs: the first rest is off the spot (in the ring or not).
		local lines, worst = arrivals(function(world: World)
			world.engineSlide = 2.5
		end)
		print("[D-302 slide] " .. table.concat(lines, "\n[D-302 slide] "))
		print(
			("[D-302 slide] worst %.2f studs, %.1f deg, %d asks, %.1f s"):format(
				worst.distance,
				worst.degrees,
				worst.asks,
				worst.seconds
			)
		)
		expect(worst.staged).toBe(true)
		expect(worst.distance).toBeLessThan(WALK.restStuds)
		expect(worst.degrees).toBeLessThan(WALK.restDegrees)
	end)

	it("rests on the spot at the slowed capture time scales too (the carry in 1x terms)", function()
		local lines = {}
		local starts = {
			{ shot = "art-horizontal", x = 25, z = -10 },
			{ shot = "art-horizontal", x = -2, z = 2 },
			{ shot = "locomotion", x = 25, z = 40 },
		}
		for presses = 1, #Dev.timeScale.steps - 1 do
			for _, start in starts do
				local result = arrive(start.shot, start.x, start.z, 90, function(world: World)
					for _ = 1, presses do
						world.key(KEYS.cycleTimeScale)
					end
				end)
				table.insert(
					lines,
					("%gx %s from (%g, %g): %s %.2f studs %.1f deg"):format(
						Dev.timeScale.steps[1 + presses],
						start.shot,
						start.x,
						start.z,
						if result.staged then "staged" else "NOT STAGED",
						result.distance,
						result.degrees
					)
				)
				expect(result.staged).toBe(true)
				expect(result.distance).toBeLessThan(WALK.restStuds)
				expect(result.degrees).toBeLessThan(WALK.restDegrees)
			end
		end
		print("[D-302 scale] " .. table.concat(lines, "\n[D-302 scale] "))
	end)

	it("covers every shot's spot: each shot stands on the stage area's spot or the ledge's", function()
		local area = ringOf("art-horizontal")
		local ledge = ringOf("locomotion")
		for _, shot in CAPTURE.shots do
			local ring = ringOf(shot.id)
			local same = function(other: any): boolean
				return ring.x == other.x and ring.y == other.y and ring.z == other.z and ring.facing == other.facing
			end
			expect(same(area) or same(ledge)).toBe(true)
		end
	end)
end)

describe("Capture: a movement key hands the walk over (D-304)", function()
	it("hands it over on a key pressed while P's ask is on its way: the walk never steers", function()
		local world = load()
		goTo(world, "art-horizontal")
		world.latency = 0.4
		world.standAt(25, -10, 90)
		world.frames(2)
		local from = #world.trail + 1
		world.key(KEYS.startCountdown)
		world.frames(6)
		expect(#stageAsks(world)).toBe(1)
		expect(stageAsks(world)[1].repliedAt).toBeNil()
		world.hold("W", true)
		world.frames(4)
		world.hold("W", false)
		world.seconds(4)
		-- The reply asked for a walk: the ring is up, the player walks it.
		expect(stageAsks(world)[1].repliedAt ~= nil).toBe(true)
		expect(world.ring() ~= nil).toBe(true)
		expect(walkMovesSince(world, from)).toBe(0)
		expect(#stageAsks(world)).toBe(1)
	end)

	it("after a tap mid-walk, only the player's keys move the body until P, across the asks", function()
		local world = load()
		goTo(world, "art-horizontal")
		world.latency = 0.1
		world.standAt(25, -10, 90)
		world.frames(2)
		world.key(KEYS.startCountdown)
		world.seconds(0.6)
		expect(world.walkMoves()).toBeGreaterThan(0)
		-- W points away from the spot (the camera looks along -Z): the body ends outside the ring.
		local from = #world.trail + 1
		local down = world.root.Position
		world.hold("W", true)
		world.frames(12)
		local up = world.root.Position
		world.hold("W", false)
		local restFrames = untilRest(world, 120)
		local rest = world.root.Position
		world.seconds(5)
		print(
			("[D-304] tap of 12 frames mid-walk: %.2f studs while held, %.2f after the key came up (%d frames), %.2f in all"):format(
				flatDistance(up, down),
				flatDistance(rest, up),
				restFrames,
				flatDistance(rest, down)
			)
		)
		expect(walkMovesSince(world, from)).toBe(0)
		expect(flatDistance(world.root.Position, rest)).toBeLessThan(1e-6)
		expect(world.ring() ~= nil).toBe(true)
		expect(staged(world)).toBeNil()
		expect(world.sprinting()).toBe(false)
		-- P walks it again.
		world.key(KEYS.startCountdown)
		world.seconds(1)
		expect(walkMovesSince(world, from)).toBeGreaterThan(0)
	end)

	it("keeps the walk the player's when a movement key is held as it would start", function()
		local world = load()
		goTo(world, "art-horizontal")
		world.standAt(25, -10, 90)
		world.frames(2)
		local from = #world.trail + 1
		world.hold("D", true)
		world.key(KEYS.startCountdown)
		world.seconds(1)
		world.hold("D", false)
		world.seconds(2)
		expect(walkMovesSince(world, from)).toBe(0)
		expect(world.ring() ~= nil).toBe(true)
	end)

	it("moves the body after a tap as the same tap from a standing start moves it", function()
		-- The tap's own run and the two-step stop after it, nothing of the walk's.
		local function tap(midWalk: boolean): number
			local world = load()
			goTo(world, "art-horizontal")
			world.standAt(25, -10, 90)
			world.frames(2)
			if midWalk then
				world.key(KEYS.startCountdown)
				world.seconds(0.6)
			end
			local down = world.root.Position
			world.hold("W", true)
			world.frames(12)
			world.hold("W", false)
			untilRest(world, 120)
			return flatDistance(world.root.Position, down)
		end
		local mid, standing = tap(true), tap(false)
		print(("[D-304] a 12-frame W tap moves the body %.2f studs mid-walk, %.2f from standing"):format(mid, standing))
		-- From a run the stop's carry is longer or shorter by where in the stride the key came up;
		-- never longer than the tap plus the stop's longest carry.
		local run = Harness.load("src/shared/data/choreo").locomotion.runSpeed
		expect(mid).toBeLessThan(run * 12 * FRAME + run * WALK.carrySeconds * 2)
	end)
end)

describe("Capture: J lets the walk go (D-305)", function()
	it("stops the body as a key let-go at the walk's speed stops it", function()
		local lines = {}
		local worst = 0
		for _, after in { 0.4, 0.5, 0.6, 0.7, 0.8 } do
			local world = load()
			goTo(world, "art-horizontal")
			world.standAt(25, -10, 90)
			world.frames(2)
			world.key(KEYS.startCountdown)
			world.seconds(after)
			local speed =
				Vector3.new(world.root.AssemblyLinearVelocity.X, 0, world.root.AssemblyLinearVelocity.Z).Magnitude
			local at = world.root.Position
			world.key(KEYS.releaseStage)
			local restFrames = untilRest(world, 120)
			local slide = flatDistance(world.root.Position, at)
			worst = math.max(worst, slide)
			table.insert(
				lines,
				("J %.1f s in at %.1f studs/s: slid %.2f in %d frames"):format(after, speed, slide, restFrames)
			)
			expect(world.ring()).toBeNil()
			expect(world.sprinting()).toBe(false)
		end
		-- The same let-go by the keys: a sprint (the walk's speed) let go from a straight run.
		local keyWorst = 0
		for _, frames in { 24, 30, 36, 42, 48 } do
			local world = load()
			world.standAt(0, 60, 0)
			world.frames(10)
			world.controller.setSprinting(true)
			world.hold("W", true)
			world.frames(frames)
			local at = world.root.Position
			world.hold("W", false)
			untilRest(world, 120)
			keyWorst = math.max(keyWorst, flatDistance(world.root.Position, at))
		end
		table.insert(lines, ("a sprint let go by the key: slid at most %.2f"):format(keyWorst))
		print("[D-305] " .. table.concat(lines, "\n[D-305] "))
		expect(worst).toBeLessThanOrEqual(keyWorst + 1e-6)
		expect(worst).toBeLessThan(WALK.restStuds)
	end)

	it("lets go below the Skid's threshold by the two-step stop's middle carry (walk.carrySeconds)", function()
		-- The run's stop carry by where in the stride the key comes up: one whole stride of let-gos.
		local run = Harness.load("src/shared/data/choreo").locomotion.runSpeed
		local least, most = math.huge, 0
		for frames = 24, 60 do
			local world = load()
			world.standAt(0, 60, 0)
			world.frames(10)
			world.hold("W", true)
			world.frames(frames)
			local at = world.root.Position
			world.hold("W", false)
			untilRest(world, 120)
			local carry = flatDistance(world.root.Position, at)
			least = math.min(least, carry)
			most = math.max(most, carry)
		end
		print(
			("[D-305] the run's stop carries %.2f to %.2f studs (middle %.2f); walk.carrySeconds x run = %.2f"):format(
				least,
				most,
				(least + most) / 2,
				WALK.carrySeconds * run
			)
		)
		expect(WALK.carrySeconds * run).toBeGreaterThan(least)
		expect(WALK.carrySeconds * run).toBeLessThan(most)
		expect(math.abs(WALK.carrySeconds * run - (least + most) / 2)).toBeLessThan((most - least) / 4)
	end)
end)

describe("Capture: the player's sprint key leaves the walk's sprint held (D-338)", function()
	it("walks the same path through a Shift tap mid-sprint, the sprint on throughout", function()
		-- The walk from 25 studs off sprints; `tap` taps Shift (6 frames) 10 frames into the sprint.
		local function walk(tap: boolean): (World, boolean)
			local world = load()
			goTo(world, "art-horizontal")
			world.standAt(25, -10, 90)
			world.frames(2)
			world.key(KEYS.startCountdown)
			for _ = 1, 120 do
				if world.sprinting() then
					break
				end
				world.frames(1)
			end
			expect(world.sprinting()).toBe(true)
			world.frames(10)
			expect(world.sprinting()).toBe(true)
			if tap then
				world.hold("LeftShift", true)
				world.frames(6)
				world.hold("LeftShift", false)
			else
				world.frames(6)
			end
			local held = world.sprinting()
			untilStaged(world, WALK.timeoutSeconds * 3)
			return world, held
		end
		local plain = walk(false)
		local tapped, held = walk(true)
		local worst = 0
		for index = 1, math.min(#tapped.trail, #plain.trail) do
			worst = math.max(worst, (tapped.trail[index].position - plain.trail[index].position).Magnitude)
		end
		local ask, plainAsk = staged(tapped), staged(plain)
		print(
			("[D-338] Shift tap mid-sprint: sprint %s after the tap, path off by at most %.4f studs, %d frames to stage (%d without), %d asks (%d)"):format(
				if held then "on" else "OFF",
				worst,
				#tapped.trail,
				#plain.trail,
				#stageAsks(tapped),
				#stageAsks(plain)
			)
		)
		expect(held).toBe(true)
		expect(ask ~= nil and plainAsk ~= nil).toBe(true)
		expect(#tapped.trail).toBe(#plain.trail)
		expect(worst).toBeLessThan(1e-6)
		-- Every sprint press and let-go the panel made carries its source.
		local sprints = 0
		for _, entry in tapped.handled do
			if entry.action == WALK.sprintAction then
				sprints += 1
				expect(entry.source ~= nil).toBe(true)
			end
		end
		expect(sprints).toBeGreaterThan(1)
	end)
end)

-- A Studio-like body (CW): the move a frame late, 360 studs/s/s up and 576 down (a sprint's stop
-- slides 0.5 studs), turning at 720 degrees a second.
local STUDIO: Engine = { lag = 1, accel = 360, decel = 576, turnRate = 720 }
-- One that slides further than the walk expects (2.4 studs from a sprint) and turns slower.
local SLIDING: Engine = { lag = 1, accel = 288, decel = 120, turnRate = 540 }
-- The server's view trailing the root, as Play Solo showed it (item 316(b): an ask the frame the body
-- stopped was read mid-slide, outside the ring).
local SERVER_LAG = 0.3

-- After the walk's first let-go (its first sprint End): the sprint presses that followed, the
-- walk's corrections (runs of its moves once the body first came to rest) and the body's top flat
-- speed from that rest on.
local function afterLetGo(world: World): (number, number, number)
	local firstEnd: number? = nil
	local sprints = 0
	for _, entry in world.handled do
		if entry.action == WALK.sprintAction then
			if entry.state == "End" and firstEnd == nil then
				firstEnd = entry.at
			elseif entry.state == "Begin" and firstEnd ~= nil then
				sprints += 1
			end
		end
	end
	local corrections, peak = 0, 0
	if firstEnd ~= nil then
		local rested, moving = false, false
		for _, entry in world.trail do
			if entry.at > (firstEnd :: number) then
				if not rested then
					rested = entry.speed < WALK.restSpeed
				else
					peak = math.max(peak, entry.speed)
					if entry.walkMove and not moving then
						corrections += 1
					end
					moving = entry.walkMove
				end
			end
		end
	end
	return sprints, corrections, peak
end

-- The starts round a shot's spot every `step` degrees at `distances` (round the ledge's centre for
-- the open shot, with its starts below the ledge on the field at its foot and up its ramp).
local function startsEvery(shotId: string, step: number, distances: { number }): { Start }
	local open = CAPTURE.shots[shotIndex(shotId)].stage.open
	local ring = ringOf(shotId)
	local ledge = STAGE.ledge
	local cx, cz = ring.x, ring.z
	if open then
		cx, cz = ledge.position[1], ledge.position[3]
	end
	local list: { Start } = {}
	for _, distance in distances do
		for bearing = 0, 359, step do
			local lx, lz = StageLogic.look(bearing)
			table.insert(
				list,
				{ x = cx + lx * distance, z = cz + lz * distance, label = ("%g@%d"):format(distance, bearing) }
			)
		end
	end
	if open then
		local hx, hz = ledge.size[1] / 2, ledge.size[3] / 2
		local edge = cz + hz
		table.insert(list, { x = cx, z = cz - hz - 1.5, label = "below the far edge" })
		table.insert(list, { x = cx + hx + 1.5, z = cz, label = "below the +X side" })
		table.insert(list, { x = cx - hx - 1.5, z = cz, label = "below the -X side" })
		table.insert(list, { x = cx + hx + 1.5, z = cz - hz - 1.5, label = "below the far +X corner" })
		table.insert(list, { x = cx - 6, z = edge + 2, label = "beside the ramp" })
		table.insert(list, { x = cx, z = edge + ledge.ramp.size[3] - 1, label = "ramp foot" })
		table.insert(list, { x = cx, z = edge + ledge.ramp.size[3] / 2, label = "ramp middle" })
		table.insert(list, { x = cx, z = cz, label = "ledge centre" })
	end
	return list
end

describe("Capture: the walk settles on a Studio-like body (CW)", function()
	it("rests on the spot from every bearing with the server's view trailing, never sprinting back", function()
		local lines = {}
		local worst = { distance = 0, degrees = 0, seconds = 0, sprints = 0, corrections = 0, peak = 0 }
		local corrected: { [string]: number } = {}
		for _, case in
			{
				{ "kill-shatter", 20, { 12, 25 } },
				{ "locomotion", 20, { 25 } },
				{ "art-horizontal", 60, { 12 } },
				{ "parry-spark", 60, { 12 } },
			}
		do
			local shotId = case[1] :: string
			for engineName, engine in { studio = STUDIO, sliding = SLIDING } do
				for _, start in startsEvery(shotId, case[2] :: number, case[3] :: { number }) do
					local result, world = arrive(shotId, start.x, start.z, 90, function(world: World)
						world.engine = engine
						world.serverLag = SERVER_LAG
					end)
					local sprints, corrections, peak = afterLetGo(world)
					table.insert(
						lines,
						("%s %s %s: %s %.2f studs %.1f deg %.2f s, %d corrections at up to %.1f studs/s, %d sprints after the let-go"):format(
							engineName,
							shotId,
							start.label,
							if result.staged then "staged" else "NOT STAGED",
							result.distance,
							result.degrees,
							result.seconds,
							corrections,
							peak,
							sprints
						)
					)
					expect(result.staged).toBe(true)
					expect(result.distance).toBeLessThanOrEqual(WALK.restStuds)
					expect(result.degrees).toBeLessThanOrEqual(WALK.restDegrees)
					expect(corrections).toBeLessThanOrEqual(WALK.secondWalks)
					expect(sprints).toBe(0)
					expect(peak).toBeLessThanOrEqual(WALK.correctSpeed + 0.25)
					worst.distance = math.max(worst.distance, result.distance)
					worst.degrees = math.max(worst.degrees, result.degrees)
					worst.seconds = math.max(worst.seconds, result.seconds)
					worst.sprints = math.max(worst.sprints, sprints)
					worst.corrections = math.max(worst.corrections, corrections)
					worst.peak = math.max(worst.peak, peak)
					corrected[engineName] = math.max(corrected[engineName] or 0, corrections)
				end
			end
		end
		print("[CW] " .. table.concat(lines, "\n[CW] "))
		print(
			("[CW] worst %.2f studs, %.1f deg, %.2f s, %d corrections at up to %.1f studs/s, %d sprints after the let-go"):format(
				worst.distance,
				worst.degrees,
				worst.seconds,
				worst.corrections,
				worst.peak,
				worst.sprints
			)
		)
		-- The body that slides further than the walk expects rests off the spot first: it is corrected.
		expect(corrected.sliding).toBeGreaterThan(0)
	end)

	it("does not move a body resting beside the spot when the server read it before it came to rest", function()
		for _, shotId in { "kill-shatter", "locomotion" } do
			local world = load()
			goTo(world, shotId)
			world.engine = STUDIO
			local ring, look = ringOf(shotId)
			-- At rest half a stud past the spot, facing its way.
			world.standAt(ring.x + look.X * 0.5, ring.z + look.Z * 0.5, ring.facing)
			world.frames(2)
			local rest = world.root.Position
			-- The server's first read: where the body was in its slide, at the approach (outside the ring).
			local ax, az = ring.x - look.X * STAGE.approachStuds, ring.z - look.Z * STAGE.approachStuds
			world.staleRead = Vector3.new(ax, floorAt(ax, az) + ROOT_OFFSET, az)
			local from = #world.trail + 1
			world.key(KEYS.startCountdown)
			untilStaged(world, WALK.timeoutSeconds)
			local asks = stageAsks(world)
			print(
				("[CW] %s, the first read stale: %d asks, staged %s, %d walk moves, moved %.3f studs"):format(
					shotId,
					#asks,
					tostring(staged(world) ~= nil),
					walkMovesSince(world, from),
					flatDistance(world.root.Position, rest)
				)
			)
			expect(asks[1].ok).toBe(false)
			expect(staged(world) ~= nil).toBe(true)
			expect(walkMovesSince(world, from)).toBe(0)
			expect(#world.handled).toBe(0)
			expect(flatDistance(world.root.Position, rest)).toBeLessThan(1e-3)
		end
	end)

	it("hands a correction over to a movement key, and J stops it, as they do the walk", function()
		-- The sliding body's first rest is off the spot: the walk corrects it.
		local function correcting(): World
			local world = load()
			goTo(world, "kill-shatter")
			world.engine = SLIDING
			world.serverLag = SERVER_LAG
			local ring = ringOf("kill-shatter")
			local lx, lz = StageLogic.look(160)
			world.standAt(ring.x + lx * 12, ring.z + lz * 12, 90)
			world.frames(2)
			world.key(KEYS.startCountdown)
			local _, corrections = afterLetGo(world)
			local started = world.clock.now
			while corrections == 0 and world.clock.now - started < WALK.timeoutSeconds do
				world.frames(1)
				_, corrections = afterLetGo(world)
			end
			expect(corrections).toBe(1)
			world.frames(10)
			return world
		end

		local world = correcting()
		local from = #world.trail + 1
		world.hold("W", true)
		world.frames(6)
		world.hold("W", false)
		untilRest(world, 120)
		local rest = world.root.Position
		-- The player's walk now: the ask comes once the root stands in the ring at rest, and the
		-- walk never moves the body again.
		world.seconds(3)
		expect(walkMovesSince(world, from)).toBe(0)
		expect(flatDistance(world.root.Position, rest)).toBeLessThan(1e-6)
		expect(world.sprinting()).toBe(false)

		world = correcting()
		from = #world.trail + 1
		local at = world.root.Position
		world.key(KEYS.releaseStage)
		local frames = untilRest(world, 120)
		print(
			("[CW] J mid-correction: slid %.2f studs in %d frames"):format(
				flatDistance(world.root.Position, at),
				frames
			)
		)
		local slide = flatDistance(world.root.Position, at)
		world.seconds(2)
		expect(walkMovesSince(world, from)).toBe(0)
		expect(world.ring()).toBeNil()
		expect(world.sprinting()).toBe(false)
		expect(frames).toBeLessThan(120)
		expect(flatDistance(world.root.Position, at)).toBe(slide)
		-- The two-step stop from the correction's walk, no farther than it carries a run (CS4: at
		-- most 1.4 x its middle carry).
		local run = Harness.load("src/shared/data/choreo").locomotion.runSpeed
		expect(slide).toBeLessThan(run * WALK.carrySeconds * 1.5)
	end)

	it("stages after P pressed again mid-walk only once the body stands at rest in the ring", function()
		-- Asked the moment P went again as the sprint crossed the ring, the server's trailing view
		-- read the body in the ring and staged it as it skidded on out (6.1 studs off the spot).
		local lines = {}
		local worst = { speed = 0, outside = 0 }
		-- At rest: the walk's rest speed, and the controller's standing speed (a stop let go in a
		-- correction's creep carries the root on a step slower than restSpeed).
		local still = math.min(WALK.restSpeed, Harness.load("src/shared/data/choreo").locomotion.idleSpeedThreshold)
		for _, case in { { "kill-shatter", 0, 12 }, { "kill-shatter", 160, 12 }, { "locomotion", 200, 25 } } do
			local shotId = case[1] :: string
			local ring = ringOf(shotId)
			local cx, cz = ring.x, ring.z
			if CAPTURE.shots[shotIndex(shotId)].stage.open then
				cx, cz = STAGE.ledge.position[1], STAGE.ledge.position[3]
			end
			local lx, lz = StageLogic.look(case[2] :: number)
			local x, z = cx + lx * (case[3] :: number), cz + lz * (case[3] :: number)
			for engineName, engine in { studio = STUDIO, sliding = SLIDING } do
				for tenths = 4, 24, 2 do
					local world = load()
					goTo(world, shotId)
					world.engine = engine
					world.serverLag = SERVER_LAG
					world.standAt(x, z, 90)
					world.frames(2)
					world.key(KEYS.startCountdown)
					world.seconds(tenths / 10)
					if staged(world) == nil then
						world.key(KEYS.startCountdown)
						untilStaged(world, WALK.timeoutSeconds * 2)
						local ask = staged(world)
						expect(ask ~= nil).toBe(true)
						-- Where the body stood and how fast it moved the frame the server staged it, and where
						-- it stood a second later.
						local at: Trail? = nil
						for _, entry in world.trail do
							if entry.at <= (ask :: Ask).at + 1e-9 then
								at = entry
							end
						end
						local there = (at :: Trail).position
						local inside = StageLogic.inRing(ring, there.X, there.Y - ROOT_OFFSET, there.Z)
						world.seconds(1)
						local after = world.root.Position
						local stays = StageLogic.inRing(ring, after.X, after.Y - ROOT_OFFSET, after.Z)
						local off = flatDistance(after, Vector3.new(ring.x, 0, ring.z))
						table.insert(
							lines,
							("%s %s %s P again at +%.1f s: staged %.2f studs off at %.1f studs/s, %.2f a second later"):format(
								engineName,
								shotId,
								("%g@%d"):format(case[3] :: number, case[2] :: number),
								tenths / 10,
								flatDistance(there, Vector3.new(ring.x, 0, ring.z)),
								(at :: Trail).speed,
								off
							)
						)
						worst.speed = math.max(worst.speed, (at :: Trail).speed)
						worst.outside = math.max(worst.outside, off - ring.radius)
						expect(inside).toBe(true)
						expect((at :: Trail).speed).toBeLessThanOrEqual(still)
						expect(stays).toBe(true)
					end
				end
			end
		end
		print("[CW] " .. table.concat(lines, "\n[CW] "))
		print(
			("[CW] P again: staged at up to %.2f studs/s, %.2f studs past the ring's edge at worst"):format(
				worst.speed,
				worst.outside
			)
		)
		expect(#lines).toBeGreaterThan(20)
	end)
end)

-- Studio's AutoRotate as the owner's PC showed it (step 14: at rest 0.03 to 0.17 studs off the spot
-- and up to 14.5 degrees off its facing after 1.1 to 2.75 s): the body's turn toward the move
-- closes with a 0.1 s time constant, so the last leg's half turn onto the spot's line is not done
-- when the walk lets go (a sprint covers the 6-stud leg in a quarter second), and the stop holds
-- what is left of it: 15 to 19 degrees here, and the same again after every second walk.
local STUDIO_TURN_TAU = 0.1

describe("Capture: the walk's last turn, on the spot (step 14)", function()
	it("turns on the spot to the shot's facing when the body's turn trails its move, and stages so", function()
		local lines, worst = arrivals(function(world: World)
			world.turnTau = STUDIO_TURN_TAU
		end)
		print("[step 14] " .. table.concat(lines, "\n[step 14] "))
		print(
			("[step 14] worst %.2f studs, %.1f deg, %d asks, %.1f s"):format(
				worst.distance,
				worst.degrees,
				worst.asks,
				worst.seconds
			)
		)
		expect(worst.staged).toBe(true)
		expect(worst.distance).toBeLessThan(WALK.restStuds)
		expect(worst.degrees).toBeLessThan(WALK.restDegrees)
	end)

	it("never walks again for the facing alone: the body stands on the spot while it turns", function()
		-- From 12 studs ahead of the spot, the last leg turns the body half round onto the spot's line
		-- and the stop holds what the trailing turn left of it (about 18 degrees).
		local spot = STAGE.area.position
		local _, world = arrive("art-horizontal", spot[1], spot[3] - 12, 90, function(w: World)
			w.turnTau = STUDIO_TURN_TAU
		end)
		local ask = staged(world)
		expect(ask).never.toBeNil()
		local ring, look = ringOf("art-horizontal")
		-- From where the walk first let go on the spot to the staging: the root's travel and the
		-- walk's moves.
		local walked = false
		local firstRest: Vector3? = nil
		local moved, movesAfter = 0, 0
		for _, entry in world.trail do
			if entry.at > (ask :: Ask).at then
				break
			end
			if firstRest ~= nil then
				moved = math.max(moved, flatDistance(entry.position, firstRest :: Vector3))
				movesAfter += if entry.walkMove then 1 else 0
			elseif entry.walkMove then
				walked = true
			elseif walked and flatDistance(entry.position, Vector3.new(ring.x, 0, ring.z)) < WALK.restStuds then
				firstRest = entry.position
			end
		end
		local degrees = degreesBetween((ask :: Ask).look, look)
		print(
			("[step 14] from 12 ahead: moved %.3f studs after the let-go on the spot, %d walk moves, staged %.1f deg off"):format(
				moved,
				movesAfter,
				degrees
			)
		)
		expect(firstRest).never.toBeNil()
		expect(movesAfter).toBe(0)
		expect(moved).toBeLessThan(0.05)
		expect(degrees).toBeLessThan(WALK.restDegrees)
	end)
end)
