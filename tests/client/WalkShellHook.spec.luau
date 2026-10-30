--!strict
--[[
	Item 236 (D-430): CharacterController hands the stick's walk (and the two-step stop's carry) to
	WalkShell.hold every free frame and walks what it gives back: the share of the speed that fits
	is the Humanoid's WalkSpeed, the direction it gives (the way along an enemy's side, or none) is
	the Humanoid's Move. A swing, a dodge or any action that locks movement is never held (its root
	motion and the keep-out, D-314, are the swing's own).

	WalkShell.spec proves the hold stops the shell at touching and slides it along the enemy; this
	proves the controller walks what the hold gives. Before the hold (7bad96a) the controller never
	asked: the walk ran at the stick's full speed and way, and the engine stopped only the
	colliding column, with the hands inside the enemy.

	The harness is StandOffWall.spec's (CharacterController.spec's, with a recording fake WalkShell
	and the tracker's live records): physics moves the root at the Humanoid's MoveDirection times
	its WalkSpeed each frame.
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local Siblings = Harness.load("src/client/controllers/Siblings")
local AimLogic = Harness.load("src/client/controllers/AimLogic")
local Rigs = Harness.load("src/shared/data/rigs")

local CONTROLLER_PATH = "src/client/controllers/CharacterController"
local CHOREO_PATH = "src/client/choreo/Choreo"
local FRAME = 1 / 60

-- A fresh copy of Choreo (its own registry and frame loops) whose RunService is `runService`.
local function freshChoreo(runService: any): any
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

-- A PlayerR15 rig model: one Part per rig part, one Motor6D per joint (as tests/choreo/Choreo.spec).
local function buildPlayerRig(): any
	local model = Instance.new("Model")
	model.Name = "PlayerR15"
	model:SetAttribute("Rig", "PlayerR15")
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

type Rig = {
	controller: any,
	sent: { { name: string, payload: any } },
	-- One frame with the stick at a world direction (zero for none).
	frame: (stick: Vector3) -> (),
	-- One frame with the display asleep: the clock moves and Heartbeat fires, no render step runs.
	heartbeat: () -> (),
	humanoid: any,
	model: any,
	-- Every Humanoid property write, in order ({ key, value }).
	writes: { { key: string, value: any } },
	-- The sends, the fake Impact's calls and the camera's FOV kicks in one ordered list
	-- ({ kind = "send" | "impact" | "camera", name, args }).
	log: { { kind: string, name: string, args: { any } } },
	-- The HumanoidRootPart (CFrame and Position kept in step, as on a part).
	root: any,
	-- Locks an enemy standing at `position` (nil: no lock).
	setLock: (position: Vector3?) -> (),
	-- Locks an enemy whose body a rush draws at `drawn`, ahead of its root part at `root` (D-193).
	setLockDrawn: (root: Vector3, drawn: Vector3) -> (),
	-- The enemies the soft assist sees: { id, position }.
	setEnemies: (enemies: { { id: number, position: Vector3 } }) -> (),
	-- The last input the controller handed Locomotion.update.
	locomotionInput: () -> any,
	-- What the fake CameraController.lockMove does to the stick it is handed (D-238): nil hands
	-- it back untouched (no live lock), as the real one does.
	setLockMove: (turn: ((Vector3) -> Vector3)?) -> (),
	-- Every direction the controller handed CameraController.lockMove, in order.
	lockMoves: { Vector3 },
	-- Every scale the controller handed the animator's setTimeScale, in order (options.animator).
	timeScales: { number },
	-- The root motion the animator hands out each frame (options.animator), in the root's space.
	setRootMotion: (delta: Vector3) -> (),
	-- The server refuses the local action (Replication.rejected).
	reject: (action: string) -> (),
	-- The server's State attribute on the local entity changes (EntityTracker.changed).
	serverState: (value: string) -> (),
	-- The character goes and comes back (CharacterRemoving, then CharacterAdded with the same model).
	respawn: () -> (),
	-- The character goes (CharacterRemoving) and no new one comes yet.
	despawn: () -> (),
	-- The spec's clock (os.clock and the server clock both read it).
	now: () -> number,
	-- The first rendered frame after a render stall: the render step's dt is the whole gap.
	wake: () -> (),
	-- An engine hitch: the clock moves `seconds` and nothing runs (no Heartbeat, no timers).
	hitch: (seconds: number) -> (),
	-- With `choreo`: the real animator, its clip events in order, and how many steps it took.
	animator: any,
	clipEvents: { { clipId: string, kind: string, jumped: boolean, at: number } },
	rigSteps: () -> number,
	-- The fake ContactPredictor: what it was asked (begins, steps, stops) and the contacts it hands
	-- the next step (queue); Replication.contact's calls land in `log` as kind "contact".
	contacts: any,
	-- The name and priority the controller bound its render step at.
	renderStep: { name: string, priority: number },
	-- Every WalkShell.hold the controller asked (item 236), in order, and what it was handed.
	holds: { { direction: Vector3, studs: number, drawn: boolean, enemies: { any }, root: CFrame } },
}

type Options = {
	-- The fake Locomotion's stopGait, with the gait phase moving on by this much per call (0 holds
	-- it still). It starts at 0.1, the left foot plants at 0 and the right at 0.5, each 0.3 of a
	-- cycle before it is over its Idle spot: a carry that starts there runs 0.7 of a cycle.
	stopGait: number?,
	-- Hand the controller a recording fx.Impact sibling instead of a stub.
	impact: boolean?,
	-- Hand the controller a recording fx.Trails sibling (its activationLight) instead of a stub.
	trails: boolean?,
	-- Hand the controller a Choreo whose animator records setTimeScale and hands out root motion.
	animator: boolean?,
	-- The place is a capture place (workspace DevCapture attribute, dev.luau attributes.capture).
	capture: boolean?,
	-- false: the place runs on a live server, not in Studio (RunService:IsStudio()); default Studio.
	studio: boolean?,
	-- Hand the controller a real Choreo animating a real rig, and run task.delay on the clock.
	choreo: boolean?,
	-- Which runs first in a rendered frame: "bound" (the controller's render step, the default) or
	-- "connections" (Choreo's RenderStepped connection).
	renderOrder: string?,
	-- What the fake ContactPredictor.standOff answers (fix F1): step this far along `away`, to
	-- the clip time `to`, from the clip time the controller asks from, with `room` the world it
	-- leaves (D-235 amended), and `keep` the keep-out at each clip time (D-314), with `keepSide`
	-- along `side` off a held part's face (D-315) and `roomSide` the world aside. Nil: no stand-off.
	standOff: {
		distance: number,
		away: Vector3,
		to: number,
		room: ((CFrame, number) -> number)?,
		keep: ((number) -> number)?,
		keepUntil: number?,
		side: Vector3?,
		keepSide: ((number) -> number)?,
		roomSide: ((CFrame, number) -> number)?,
	}?,
	-- What the fake WalkShell.hold answers for the walk it is handed (item 236): the direction
	-- to walk and the share of the speed that fits. Nil: the walk is never held.
	hold: ((direction: Vector3, studs: number) -> (Vector3, number))?,
	-- The tracker's live records (EntityTracker.live).
	live: { any }?,
}

local IMPACT_CALLS = { "guardRaise", "dodge", "release", "cancelActivation", "activation" }

local function load(options: Options?): Rig
	local opts: Options = options or {}
	local clock = 0
	local step: ((dt: number) -> ())? = nil
	local renderStep = { name = "", priority = -1 }
	local sent: { { name: string, payload: any } } = {}
	local writes: { { key: string, value: any } } = {}
	local log: { { kind: string, name: string, args: { any } } } = {}
	local props: { [string]: any } = {
		WalkSpeed = 16,
		JumpPower = 0,
		JumpHeight = 0,
		AutoRotate = true,
		MoveDirection = Vector3.zero,
		FloorMaterial = Enum.Material.Grass,
	}
	function props.Move(self: any, direction: Vector3)
		self.MoveDirection = if direction.Magnitude > 0 then direction.Unit else Vector3.zero
	end
	local humanoid: any = setmetatable({}, {
		__index = props,
		__newindex = function(_self: any, key: string, value: any)
			table.insert(writes, { key = key, value = value })
			props[key] = value
		end,
	})
	local rootState: { [string]: any } = { CFrame = CFrame.new(), AssemblyLinearVelocity = Vector3.zero }
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
		end,
	})
	local lockRecord: any = nil
	local enemies: { { id: number, position: Vector3 } } = {}
	local lastInput: any = nil
	local lockTurn: ((Vector3) -> Vector3)? = nil
	local lockMoves: { Vector3 } = {}
	local model = {
		WaitForChild = function(_self: any, name: string): any
			return if name == "Humanoid" then humanoid else root
		end,
		GetAttribute = function(): any
			return nil
		end,
		GetAttributeChangedSignal = function(): any
			return Signal.new()
		end,
	}
	local gaitPhase = 0.1 - (opts.stopGait or 0)
	local locomotion = {
		new = function(): any
			return {
				serverDrawn = function(): boolean
					return false
				end,
				update = function(_self: any, _dt: number, input: any)
					lastInput = input
				end,
				stopGait = if opts.stopGait ~= nil
					then function(_self: any, into: any)
						gaitPhase = (gaitPhase + (opts.stopGait :: number)) % 1
						into.phase, into.leftStep, into.leftAfter, into.rightStep, into.rightAfter =
							gaitPhase, 0, 0.3, 0.5, 0.3
					end
					else nil,
			}
		end,
	}
	local timeScales: { number } = {}
	local rootMotion = Vector3.zero
	local animator = {
		play = function(_self: any, clipId: string): any
			return { clipId = clipId }
		end,
		stop = function() end,
		setTimeScale = function(_self: any, scale: number)
			table.insert(timeScales, scale)
		end,
		currentRootMotionDelta = function(_self: any): Vector3
			return rootMotion
		end,
		onStep = function(): () -> ()
			return function() end
		end,
	}
	local choreo: any = {
		get = function(): any
			return animator
		end,
		setLocalModel = function() end,
	}
	local impact: { [string]: any } = {}
	for _, name in IMPACT_CALLS do
		impact[name] = function(...: any)
			table.insert(log, { kind = "impact", name = name, args = { ... } })
		end
	end
	-- TargetController, through Siblings: the lock and the soft assist's candidates.
	local targetController = {
		current = function(): any
			return lockRecord
		end,
		assistCandidates = function(origin: Vector3, look: Vector3): { any }
			local list = {}
			for _, enemy in enemies do
				local dx, dz = enemy.position.X - origin.X, enemy.position.Z - origin.Z
				table.insert(list, {
					id = enemy.id,
					distance = math.sqrt(dx * dx + dz * dz),
					bearing = AimLogic.bearing(look.X, look.Z, dx, dz),
				})
			end
			return list
		end,
	}
	-- ContactPredictor (issue 4): a recording fake. Its steps note the clip time asked for, the root
	-- at that moment and how many times the rig had stepped by then.
	local contactLog: any =
		{ begins = {}, steps = {}, stops = 0, queue = {}, active = false, deps = nil, standOffs = {}, worldCasts = {} }
	local rigStepCount: () -> number = function(): number
		return 0
	end
	local holds: { { direction: Vector3, studs: number, drawn: boolean, enemies: { any }, root: CFrame } } = {}
	local liveRecords: { any } = opts.live or {}
	local fakes: { [string]: any } = {
		WalkShell = {
			hold = function(
				_model: any,
				rootPart: any,
				direction: Vector3,
				studs: number,
				drawn: boolean,
				enemies: { any }
			): (Vector3, number)
				table.insert(holds, {
					direction = direction,
					studs = studs,
					drawn = drawn,
					enemies = enemies,
					root = rootPart.CFrame,
				})
				local answer = opts.hold
				if answer == nil then
					return direction, 1
				end
				return answer(direction, studs)
			end,
		},
		ContactPredictor = {
			standOff = function(
				model: any,
				clip: any,
				from: number,
				rootCFrame: CFrame,
				target: any,
				cast: any,
				options: any
			): any
				table.insert(contactLog.standOffs, {
					model = model,
					clip = clip,
					from = from,
					root = rootCFrame,
					target = target,
					cast = cast,
					options = options,
				})
				local plan = opts.standOff
				if plan == nil then
					return nil
				end
				return {
					distance = plan.distance,
					away = plan.away,
					from = from,
					to = plan.to,
					room = plan.room,
					keep = plan.keep,
					keepUntil = plan.keepUntil,
					side = plan.side,
					keepSide = plan.keepSide,
					roomSide = plan.roomSide,
				}
			end,
			-- The world the stand-off may not step into (D-235 amended): a marker the plan is asked with.
			worldCast = function(model: any): any
				local cast = function(): number?
					return nil
				end
				table.insert(contactLog.worldCasts, { model = model, cast = cast })
				return cast
			end,
			new = function(deps: any): any
				contactLog.deps = deps
				return {
					begin = function(_self: any, swing: any): boolean
						table.insert(contactLog.begins, swing)
						contactLog.active = true
						return true
					end,
					stop = function(_self: any)
						contactLog.stops += 1
						contactLog.active = false
					end,
					active = function(_self: any): boolean
						return contactLog.active
					end,
					step = function(_self: any, clipTime: number, jumped: boolean?): { any }
						table.insert(contactLog.steps, {
							time = clipTime,
							root = rootState.CFrame,
							rigSteps = rigStepCount(),
							jumped = jumped,
						})
						local out = contactLog.queue
						contactLog.queue = {}
						return out
					end,
				}
			end,
		},
		Net = {
			client = function(): any
				return {
					fire = function(name: string, payload: any)
						table.insert(sent, { name = name, payload = payload })
						table.insert(log, { kind = "send", name = name, args = { payload } })
					end,
					on = function() end,
				}
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
			live = function(): { any }
				return liveRecords
			end,
		},
		Replication = {
			rejected = Signal.new(),
			hit = Signal.new(),
			clipEvent = Signal.new(),
			contact = function(contact: any): boolean
				table.insert(log, { kind = "contact", name = "contact", args = { contact } })
				return true
			end,
			confirmedAlready = function(): boolean
				return false
			end,
		},
		CameraController = {
			fovKick = function(...: any)
				table.insert(log, { kind = "camera", name = "fovKick", args = { ... } })
			end,
			lockMove = function(direction: Vector3): Vector3
				table.insert(lockMoves, direction)
				local turn = lockTurn
				return if turn ~= nil then turn(direction) else direction
			end,
		},
		Siblings = {
			load = function(_parent: any, path: string): (any, boolean)
				if path == "choreo.Locomotion" then
					return locomotion, true
				end
				if path == "fx.Impact" and opts.impact then
					return impact, true
				end
				if path == "fx.Trails" and opts.trails then
					return {
						activationLight = function(...: any)
							table.insert(log, { kind = "trails", name = "activationLight", args = { ... } })
						end,
					},
						true
				end
				if path == "choreo.Choreo" and (opts.animator or opts.choreo) then
					return choreo, true
				end
				if path == "controllers.TargetController" then
					return targetController, true
				end
				if path == "choreo.DrawnBody" then
					return Harness.load("src/client/choreo/DrawnBody"), true
				end
				return Siblings.stub(), false
			end,
			call = Siblings.call,
			stub = Siblings.stub,
		},
	}
	local heartbeat = Signal.new()
	local renderStepped = Signal.new()
	local preSimulation = Signal.new()
	local localPlayer = { CharacterAdded = Signal.new(), CharacterRemoving = Signal.new(), Character = model }
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, name: string, priority: number, fn: (dt: number) -> ())
				step = fn
				renderStep.name = name
				renderStep.priority = priority
			end,
			Heartbeat = heartbeat,
			RenderStepped = renderStepped,
			PreSimulation = preSimulation,
			IsStudio = function(_self: any): boolean
				return opts.studio ~= false
			end,
		},
		Players = { LocalPlayer = localPlayer },
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	-- task.delay on the spec's clock (with `choreo`; a no-op otherwise, as before).
	local timers: { { at: number, fn: () -> () } } = {}
	local function runTimers()
		while true do
			local due: number? = nil
			for index, timer in timers do
				if timer.at <= clock and (due == nil or timer.at < timers[due :: number].at) then
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
	-- The real Choreo, its rig and what it did.
	local rigAnimator: any = nil
	local clipEvents: { { clipId: string, kind: string, jumped: boolean, at: number } } = {}
	local rigSteps = 0
	if opts.choreo then
		local realChoreo = freshChoreo(services.RunService)
		realChoreo.configure({
			now = function(): number
				return clock
			end,
			cameraPosition = function(): Vector3?
				return Vector3.zero
			end,
		})
		local rigModel = buildPlayerRig()
		rigAnimator = realChoreo.get(rigModel)
		local setScale = rigAnimator.setTimeScale
		rigAnimator.setTimeScale = function(self: any, scale: number)
			table.insert(timeScales, scale)
			setScale(self, scale)
		end
		rigAnimator:onStep(function()
			rigSteps += 1
		end)
		rigStepCount = function(): number
			return rigSteps
		end
		rigAnimator.events:Connect(function(clipId: string, event: any, jumped: boolean)
			table.insert(clipEvents, { clipId = clipId, kind = event.kind, jumped = jumped, at = clock })
			fakes.Replication.clipEvent:Fire({ model = model }, clipId, event, jumped)
		end)
		local wrapper: { [string]: any } = {
			get = function(): any
				return rigAnimator
			end,
			setLocalModel = function(target: any, ...: any)
				realChoreo.setLocalModel(if target ~= nil then rigModel else nil, ...)
			end,
		}
		-- Only where this Choreo has it.
		wrapper.stepLocal = realChoreo.stepLocal
		choreo = wrapper :: any
	end
	local env = Harness.environment()
	env.script = Harness.node(CONTROLLER_PATH)
	env.require = function(target: any): any
		return fakes[target.Name] or Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	local attributes: { [string]: any } = { DevCapture = opts.capture }
	env.workspace = {
		GetServerTimeNow = function(): number
			return clock
		end,
		GetAttribute = function(_self: any, name: string): any
			return attributes[name]
		end,
	}
	env.os = {
		clock = function(): number
			return clock
		end,
	}
	env.task = {
		delay = function(seconds: number, fn: () -> ())
			if opts.choreo then
				table.insert(timers, { at = clock + seconds, fn = fn })
			end
		end,
	}
	local controller = luau.load(
		Harness.readFile(CONTROLLER_PATH .. ".luau"),
		{ debugName = CONTROLLER_PATH, environment = env :: any }
	)()
	controller.start()
	assert(step ~= nil, "the controller bound no render step")
	local lastRenderAt = clock
	-- One rendered frame of `dt`: the control script's Move, the render step and Choreo's
	-- RenderStepped connection in the order the spec picked, the physics, then Heartbeat and the
	-- timers due by now (task.delay resumes there).
	local function render(stick: Vector3, dt: number)
		humanoid:Move(stick)
		local runStep = step :: (dt: number) -> ()
		if opts.renderOrder == "connections" then
			renderStepped:Fire(dt)
		end
		runStep(dt)
		if opts.renderOrder ~= "connections" then
			renderStepped:Fire(dt)
		end
		lastRenderAt = clock
		preSimulation:Fire(FRAME)
		root.AssemblyLinearVelocity = humanoid.MoveDirection * humanoid.WalkSpeed
		root.Position += root.AssemblyLinearVelocity * FRAME
		local move = humanoid.MoveDirection
		if props.AutoRotate and move.Magnitude > 0 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(move.X, 0, move.Z))
		end
		heartbeat:Fire(FRAME) -- after the render step and the physics, as in a frame
		runTimers()
	end
	return {
		controller = controller,
		sent = sent,
		humanoid = humanoid,
		model = model,
		writes = writes,
		log = log,
		root = root,
		setLock = function(position: Vector3?)
			lockRecord = if position ~= nil
				then { id = 1, kind = "Enemy", state = "Idle", model = { PrimaryPart = { Position = position } } }
				else nil
		end,
		setLockDrawn = function(rootAt: Vector3, drawnAt: Vector3)
			local DrawnBody = Harness.load("src/client/choreo/DrawnBody")
			local lockModel = { PrimaryPart = { Position = rootAt, CFrame = CFrame.new(rootAt) } }
			lockRecord = { id = 1, kind = "Enemy", state = "Idle", model = lockModel }
			DrawnBody.publish(lockModel, CFrame.new(drawnAt - rootAt))
		end,
		setEnemies = function(list: { { id: number, position: Vector3 } })
			enemies = list
		end,
		locomotionInput = function(): any
			return lastInput
		end,
		setLockMove = function(turn: ((Vector3) -> Vector3)?)
			lockTurn = turn
		end,
		lockMoves = lockMoves,
		timeScales = timeScales,
		setRootMotion = function(delta: Vector3)
			rootMotion = delta
		end,
		reject = function(action: string)
			fakes.Replication.rejected:Fire(action)
		end,
		serverState = function(value: string)
			fakes.EntityTracker.changed:Fire({ id = nil }, "State", value)
		end,
		respawn = function()
			localPlayer.CharacterRemoving:Fire()
			localPlayer.CharacterAdded:Fire(model)
		end,
		despawn = function()
			localPlayer.CharacterRemoving:Fire()
		end,
		heartbeat = function()
			clock += FRAME
			heartbeat:Fire(FRAME)
			runTimers()
		end,
		frame = function(stick: Vector3)
			clock += FRAME
			render(stick, FRAME)
		end,
		now = function(): number
			return clock
		end,
		wake = function()
			clock += FRAME
			render(Vector3.zero, clock - lastRenderAt)
		end,
		hitch = function(seconds: number)
			clock += seconds
		end,
		animator = rigAnimator,
		clipEvents = clipEvents,
		rigSteps = function(): number
			return rigSteps
		end,
		contacts = contactLog,
		holds = holds,
		renderStep = renderStep,
	}
end

-- ------------------------------------------------------------------------------------------

local ChoreoData = Harness.load("src/shared/data/choreo")

local STILL = Vector3.zero
local FORWARD = Vector3.new(0, 0, -1)
local SIDEWAYS = Vector3.new(1, 0, 0)

-- How far the root moved from `from`, along `axis`.
local function along(rig: Rig, from: Vector3, axis: Vector3): number
	return (rig.root.Position - from):Dot(axis)
end

describe("the controller walks what the walk's shell leaves (item 236, D-430)", function()
	it(
		"asks the hold each free frame with the stick's walk, this frame's studs, the stance and the live records",
		function()
			local records = { { id = 7, model = "the kobold" } }
			local rig = load({ live = records })
			for _ = 1, 10 do
				rig.frame(STILL)
			end
			expect(#rig.holds).toBe(0) -- no stick, no walk to hold
			for _ = 1, 20 do
				rig.frame(FORWARD)
			end
			expect(#rig.holds).toBe(20)
			local last = rig.holds[#rig.holds]
			expect(last.direction.X).toBeCloseTo(FORWARD.X, 1e-6)
			expect(last.direction.Z).toBeCloseTo(FORWARD.Z, 1e-6)
			-- One frame of the Humanoid's speed (the run speed the stick walks at here).
			expect(last.studs).toBeCloseTo(ChoreoData.locomotion.runSpeed / 60, 1e-6)
			expect(last.drawn).toBe(false)
			expect(last.enemies).toBe(records)
		end
	)

	it("walks the share of the speed that fits, the way the hold slides it", function()
		local free = load()
		local held = load({
			hold = function(_direction: Vector3, _studs: number): (Vector3, number)
				return SIDEWAYS, 0.5
			end,
		})
		for _, rig in { free, held } do
			for _ = 1, 10 do
				rig.frame(STILL)
			end
		end
		local freeFrom, heldFrom = free.root.Position, held.root.Position
		for _ = 1, 30 do
			free.frame(FORWARD)
			held.frame(FORWARD)
		end
		local run = ChoreoData.locomotion.runSpeed
		expect(free.humanoid.WalkSpeed).toBeCloseTo(run, 1e-6)
		expect(held.humanoid.WalkSpeed).toBeCloseTo(run * 0.5, 1e-6)
		expect(held.humanoid.MoveDirection.X).toBeCloseTo(1, 1e-6)
		expect(held.humanoid.MoveDirection.Z).toBeCloseTo(0, 1e-6)
		-- The free walk went 30 frames at the run speed straight ahead; the held one went half as
		-- far, all of it along the side, none of it ahead.
		expect(along(free, freeFrom, FORWARD)).toBeCloseTo(run * 30 / 60, 1e-4)
		expect(along(held, heldFrom, SIDEWAYS)).toBeCloseTo(run * 0.5 * 30 / 60, 1e-4)
		expect(math.abs(along(held, heldFrom, FORWARD)) < 1e-6).toBe(true)
	end)

	it("stands still where nothing fits, and walks on at once when the hold lets go", function()
		local blocked = true
		local rig = load({
			hold = function(direction: Vector3, _studs: number): (Vector3, number)
				if blocked then
					return Vector3.zero, 0
				end
				return direction, 1
			end,
		})
		for _ = 1, 10 do
			rig.frame(STILL)
		end
		local from = rig.root.Position
		for _ = 1, 30 do
			rig.frame(FORWARD)
		end
		expect((rig.root.Position - from).Magnitude < 1e-6).toBe(true)
		expect(rig.humanoid.MoveDirection.Magnitude).toBe(0)
		blocked = false
		rig.frame(FORWARD)
		expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(-1, 1e-6)
		expect(rig.humanoid.WalkSpeed).toBeCloseTo(ChoreoData.locomotion.runSpeed, 1e-6)
		expect(along(rig, from, FORWARD) > 0).toBe(true)
	end)

	it("holds the two-step stop's carry along its own way too", function()
		-- The walk goes free; once the stick lets go, the carry is held to a quarter.
		local carrying = false
		local rig = load({
			stopGait = 0,
			hold = function(direction: Vector3, _studs: number): (Vector3, number)
				return direction, if carrying then 0.25 else 1
			end,
		})
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local walked = #rig.holds
		carrying = true
		for _ = 1, 10 do
			rig.frame(STILL)
		end
		-- The stick let go: the carry runs along the last move, and the hold is asked with that way.
		expect(#rig.holds).toBe(walked + 10)
		local last = rig.holds[#rig.holds]
		expect(last.direction.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		expect(rig.humanoid.WalkSpeed).toBeCloseTo(ChoreoData.locomotion.runSpeed * 0.25, 1e-6)
		expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
	end)

	it("never holds a swing: no hold is asked while the action locks movement", function()
		local rig = load({
			hold = function(_direction: Vector3, _studs: number): (Vector3, number)
				return Vector3.zero, 0
			end,
		})
		for _ = 1, 30 do
			rig.frame(STILL)
		end
		rig.controller.basicAttack()
		expect(rig.controller.state()).toBe("Basic")
		local before = #rig.holds
		for _ = 1, 5 do
			rig.frame(FORWARD)
		end
		expect(rig.controller.state()).toBe("Basic")
		expect(#rig.holds).toBe(before)
	end)
end)
