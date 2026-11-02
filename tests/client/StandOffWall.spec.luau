--!strict
--[[
	Item 287 (D-276, D-314): the keep-out against a wall behind. In Studio, with the back flush to a
	wall or a pillar and a kobold touching in front, the code step moved the root FORWARD 0.13-0.21
	studs a frame through Sharp Nail (the clip's own lunge) while the physics step pushed it 0.16-0.51
	back, pressing the root box up to 0.35-0.39 studs into the wall: the keep-out's back step was
	cut by the wall (its room is 0) and nothing held the lunge, so the clip's root motion carried the
	colliding parts into the enemy's blocker, and the engine split the overlap between the blocker and
	the wall. With no room behind, the clip's own motion toward the target must be held back by what
	the wall took off the keep-out, so the root never goes deeper than it stood.

	The harness is CharacterController.spec's (a real Choreo animating a real rig on the spec's
	clock, the fake ContactPredictor.standOff answering the plan the test hands it).
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
	-- How long each frame from now on lasts (its clock, render step and physics).
	setFrameSeconds: (seconds: number) -> (),
	-- With `choreo`: the real animator, its clip events in order, and how many steps it took.
	animator: any,
	clipEvents: { { clipId: string, kind: string, jumped: boolean, at: number } },
	rigSteps: () -> number,
	-- The fake ContactPredictor: what it was asked (begins, steps, stops) and the contacts it hands
	-- the next step (queue); Replication.contact's calls land in `log` as kind "contact".
	contacts: any,
	-- The name and priority the controller bound its render step at.
	renderStep: { name: string, priority: number },
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
	-- The real stand-off (item 462): ContactPredictor.standOff's arguments as the controller hands
	-- them, answered in place of `standOff` (the body and the target the spec stands for them).
	standOffWith: ((
		model: any,
		clip: any,
		from: number,
		rootCFrame: CFrame,
		target: any,
		cast: any,
		options: any
	) -> any)?,
	-- The world cast ContactPredictor.worldCast hands the controller (a cast that meets nothing
	-- by default).
	worldCast: any?,
	-- Seconds each rendered frame (and its physics) takes; a 60 Hz frame by default.
	frameSeconds: number?,
	-- The physics of a frame of `dt` after the render step (item 462: a Studio-like body), in place
	-- of the Humanoid's walk alone.
	physics: ((dt: number) -> ())?,
}

local IMPACT_CALLS = { "guardRaise", "dodge", "release", "cancelActivation", "activation" }

local function load(options: Options?): Rig
	local opts: Options = options or {}
	local frameSeconds: number = opts.frameSeconds or FRAME
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
	local fakes: { [string]: any } = {
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
				local with = opts.standOffWith
				if with ~= nil then
					return with(model, clip, from, rootCFrame, target, cast, options)
				end
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
				local cast = opts.worldCast or function(): number?
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
		preSimulation:Fire(frameSeconds)
		local physics = opts.physics
		if physics ~= nil then
			physics(frameSeconds)
		else
			root.AssemblyLinearVelocity = humanoid.MoveDirection * humanoid.WalkSpeed
			root.Position += root.AssemblyLinearVelocity * frameSeconds
			local move = humanoid.MoveDirection
			if props.AutoRotate and move.Magnitude > 0 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(move.X, 0, move.Z))
			end
		end
		heartbeat:Fire(frameSeconds) -- after the render step and the physics, as in a frame
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
			clock += frameSeconds
			heartbeat:Fire(frameSeconds)
			runTimers()
		end,
		frame = function(stick: Vector3)
			clock += frameSeconds
			render(stick, frameSeconds)
		end,
		setFrameSeconds = function(seconds: number)
			frameSeconds = seconds
		end,
		now = function(): number
			return clock
		end,
		wake = function()
			clock += frameSeconds
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
		renderStep = renderStep,
	}
end

-- ------------------------------------------------------------------------------------------

local STILL = Vector3.zero

local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")

-- How far toward the target (along -away) the clip's own root motion carries the body from clip
-- time `from` to `to`, in the root's space (the clip's look is -Z).
local function lungeOf(clip: any, from: number, to: number): number
	local a = ClipSampler.rootMotionAt(clip, from)
	local b = ClipSampler.rootMotionAt(clip, to)
	return -(b[3] - a[3])
end

describe("the keep-out with the world flush behind (item 287, D-276, D-314)", function()
	it(
		"an Art whose clip lunges at a touching enemy never carries the root toward it while the wall leaves no room",
		function()
			-- The target ahead (-Z), the stand-off's line straight back (+Z), a keep-out that grows with
			-- the clip's lunge (what the swing's motion would carry the parts in) and a wall flush behind:
			-- the room is 0 on every frame.
			local away = Vector3.new(0, 0, 1)
			local art = load({ choreo = true }).controller.slots()[1]
			assert(art ~= nil, "no Art in slot 1")
			local clipDef = Harness.load("src/shared/clips/" .. art.clip)
			local from = 0
			local function keep(t: number): number
				return math.max(0, lungeOf(clipDef, from, t))
			end
			local asked = 0
			local plan = {
				distance = 0,
				away = away,
				to = 0,
				keep = keep,
				keepUntil = 10,
				room = function(_at: CFrame, _distance: number): number
					asked += 1
					return 0
				end,
			}
			local rig = load({ choreo = true, impact = true, standOff = plan })
			for _ = 1, 40 do
				rig.frame(STILL)
			end
			rig.setLock(Vector3.new(0, 0, -1.9))
			rig.controller.beginArt(1)
			for _ = 1, 12 do
				rig.frame(STILL)
			end
			rig.controller.releaseArt(1, 12 * FRAME)
			local handle = rig.animator.mixer:find(art.clip)
			from = handle.time
			local start = rig.root.Position:Dot(away)
			local deepest = 0
			local lunged = 0
			for _ = 1, 120 do
				rig.frame(STILL)
				lunged = math.max(lunged, keep(handle.time))
				deepest = math.max(deepest, start - rig.root.Position:Dot(away))
				if handle.time >= clipDef.duration - 1e-6 or rig.controller.state() ~= "Art" then
					break
				end
			end
			-- The clip does lunge (else this proves nothing), the wall was asked, and the root never
			-- went toward the target past where it stood at the release.
			expect(lunged > 0.3).toBe(true)
			expect(asked > 0).toBe(true)
			if deepest > 1e-3 then
				error(
					("the root went %.3f studs toward the target with the wall flush behind (lunge %.3f)"):format(
						deepest,
						lunged
					)
				)
			end
		end
	)

	-- Item 337 (D-502): in Studio the root box went 0.48 into a wall flush behind and the body was
	-- squeezed 5.4 studs along it. The world's real room (ContactPredictor.room, cast from where the
	-- root stands) opens as far as the frame's own lunge carried the root off the wall; the step
	-- took that room, and then the hold (D-429) took the same lunge back again with no cast, so the
	-- root went past where it stood, into the wall, by the frame's lunge.
	it(
		"the step and the hold never take the same lunge twice: the root box stays out of a wall flush behind",
		function()
			local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
			local away = Vector3.new(0, 0, 1)
			local art = load({ choreo = true }).controller.slots()[1]
			assert(art ~= nil, "no Art in slot 1")
			local clipDef = Harness.load("src/shared/clips/" .. art.clip)
			local from = 0
			-- What the swing's motion would carry the parts in, and a step back before the lunge starts
			-- (Basic1 at a held kobold asks 0.72 studs over its first six frames), which the wall takes.
			local function keep(t: number): number
				return math.max(0, lungeOf(clipDef, from, t)) + math.clamp((t - from) * 6, 0, 0.5)
			end
			-- A wall square to `away`, the root box's back face on it at the release.
			local ROOT_SIZE = Vector3.new(2, 2, 1)
			local wallAt = math.huge
			local function cast(start: CFrame, size: Vector3, vector: Vector3): number?
				local length = vector.Magnitude
				local direction = vector / length
				local reach = math.abs(start.RightVector:Dot(away)) * size.X / 2
					+ math.abs(start.UpVector:Dot(away)) * size.Y / 2
					+ math.abs(start.LookVector:Dot(away)) * size.Z / 2
				local gap = wallAt - (start.Position:Dot(away) + reach)
				local rate = direction:Dot(away)
				if gap >= -1e-9 and rate > 1e-9 and gap / rate <= length then
					return gap / rate
				end
				return nil
			end
			local plan = {
				distance = 0,
				away = away,
				to = 0,
				keep = keep,
				keepUntil = 10,
				room = function(at: CFrame, distance: number): number
					return ContactPredictor.room(at, ROOT_SIZE, away, distance, cast)
				end,
			}
			local rig = load({ choreo = true, impact = true, standOff = plan })
			for _ = 1, 40 do
				rig.frame(STILL)
			end
			rig.setLock(Vector3.new(0, 0, -1.9))
			rig.controller.beginArt(1)
			for _ = 1, 12 do
				rig.frame(STILL)
			end
			rig.controller.releaseArt(1, 12 * FRAME)
			local handle = rig.animator.mixer:find(art.clip)
			from = handle.time
			local start = rig.root.Position:Dot(away)
			wallAt = start + ROOT_SIZE.Z / 2
			local inWall, toward, lunged = 0, 0, 0
			for _ = 1, 120 do
				rig.frame(STILL)
				lunged = math.max(lunged, keep(handle.time))
				inWall = math.max(inWall, rig.root.Position:Dot(away) + ROOT_SIZE.Z / 2 - wallAt)
				toward = math.max(toward, start - rig.root.Position:Dot(away))
				if handle.time >= clipDef.duration - 1e-6 or rig.controller.state() ~= "Art" then
					break
				end
			end
			print(
				("[337] keep %.3f: root box %.3f into the wall, %.3f toward the target"):format(lunged, inWall, toward)
			)
			expect(lunged > 0.3).toBe(true)
			expect(inWall <= 1e-3).toBe(true)
			expect(toward <= Harness.load("src/shared/data/combat").contact.standOff.wallGapStuds + 1e-3).toBe(true)
		end
	)
end)

-- Item 431 (D-534): at a wall flush behind, the PC's code step still moved the root back on rows
-- the body touched the face (up to 0.095 a row at the wall) and the root moved toward the kobold
-- over Basic1 (+0.090; the engine pushing the body out of the wall). The room was cast with the
-- column as it stands as the step is taken: a frame whose pose leans forward (Basic1 at clip
-- 0.117, Sharp Nail's lunge at 0.350) opened room the next pose leans back into, and the frame
-- that shows the stepped root still draws the pose before (a root shows on its own frame, a pose
-- one frame later), so the drawn body went that far into the wall. Through the real plan
-- (ContactPredictor.standOff with the keep-out at a touching kobold, cast against a wall or a
-- pillar flush behind) and the real controller and clips at 60 Hz, the parts posed where Lune
-- reads them (this step's pose), with the engine pushing a part the clip leans into the world back
-- out after each frame: on every frame the code steps the root back, the column as drawn (the clip
-- time before) and as stepped (this one) stands the gap short of the world.
describe("the stand-off at a wall or a pillar flush behind (item 431, D-534)", function()
	it("never steps the root back while the drawn or the stepped body touches the face", function()
		local fs = require("@lune/fs")
		local Combat = Harness.load("src/shared/data/combat")
		local Enemies = Harness.load("src/shared/data/enemies")
		local World = Harness.load("src/shared/data/world")
		local Pose = Harness.load("src/shared/choreo/Pose")
		local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
		local RigBuilder = Harness.load("src/server/world/RigBuilder")
		local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
		local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
		local STAND_OFF = Combat.contact.standOff
		local GAP: number = STAND_OFF.wallGapStuds
		local source = fs.readFile(Harness.repoRoot() .. "/tools/hitmatrix/HitMatrix.luau")
		local HitMatrix = luau.load(source, {
			debugName = "tools/hitmatrix/HitMatrix",
			environment = { require = require } :: any,
		})()
		local avatar = HitMatrix.standing(Harness)
		local clip = Harness.load("src/shared/clips/player/OneHandedSword/Basic1")
		local clipId = "player/OneHandedSword/Basic1"
		local away = Vector3.new(0, 0, 1)
		-- A kobold touching in front of the matrix body (its root 2.3 studs ahead), blocker on.
		local def = Enemies.byId("KoboldAxeman")
		local kobold = RigBuilder.build(def.skin)
		local height =
			PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, kobold.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
		local koboldAt = avatar.base * CFrame.new(0, height - avatar.rootHeight, -2.3) * CFrame.Angles(0, math.pi, 0)
		for name, solved in Pose.solve(kobold, koboldAt, {}) do
			local part = kobold:FindFirstChild(name)
			if part ~= nil and part:IsA("BasePart") then
				part.CFrame = solved
			end
		end
		RigBuilder.addBlocker(kobold)
		for _, child in kobold:GetChildren() do
			if child:IsA("BasePart") and child.Name == STAND_OFF.keepOut.bodyFace then
				child.CanCollide = true
			end
		end
		-- The column posed by the clip at `time` with the root at `root`: how far its backmost
		-- corner stands past the plane `face` along `away` (negative: short of it), within `span`
		-- of the line when given (a pillar).
		local column = STAND_OFF.keepOut.parts
		local function depthPast(root: CFrame, time: number, face: number, span: number?): number
			local solved = Pose.solve(avatar.model, root, ClipSampler.sample(clip, math.min(time, clip.duration)))
			local most = -math.huge
			for _, name in column do
				local part = avatar.model:FindFirstChild(name) :: BasePart
				local half = part.Size / 2
				for _, x in { -1, 1 } do
					for _, y in { -1, 1 } do
						for _, z in { -1, 1 } do
							local corner = solved[name] * Vector3.new(x * half.X, y * half.Y, z * half.Z)
							if span == nil or math.abs(corner.X) <= span then
								most = math.max(most, corner:Dot(away) - face)
							end
						end
					end
				end
			end
			return most
		end
		-- The engine's Blockcast against one box (to 1e-6), never a box it starts in.
		local function boxCast(world: { BasePart }): (CFrame, Vector3, Vector3) -> number?
			local function inside(at: CFrame, size: Vector3, part: BasePart): boolean
				local corners = {}
				for _, x in { -1, 1 } do
					for _, y in { -1, 1 } do
						for _, z in { -1, 1 } do
							table.insert(corners, at * Vector3.new(x * size.X / 2, y * size.Y / 2, z * size.Z / 2))
						end
					end
				end
				-- separating axes of two boxes
				local axes = {
					at.RightVector,
					at.UpVector,
					at.LookVector,
					part.CFrame.RightVector,
					part.CFrame.UpVector,
					part.CFrame.LookVector,
				}
				for _, axis in axes do
					local lo, hi = math.huge, -math.huge
					for _, corner in corners do
						local d = corner:Dot(axis)
						lo, hi = math.min(lo, d), math.max(hi, d)
					end
					local c = part.CFrame.Position:Dot(axis)
					local r = part.Size.X / 2 * math.abs(part.CFrame.RightVector:Dot(axis))
						+ part.Size.Y / 2 * math.abs(part.CFrame.UpVector:Dot(axis))
						+ part.Size.Z / 2 * math.abs(part.CFrame.LookVector:Dot(axis))
					if hi < c - r - 1e-9 or lo > c + r + 1e-9 then
						return false
					end
				end
				return true
			end
			return function(start: CFrame, size: Vector3, vector: Vector3): number?
				local length = vector.Magnitude
				if length < 1e-9 then
					return nil
				end
				local best: number? = nil
				for _, part in world do
					if inside(start, size, part) then
						continue
					end
					if not inside(start + vector, size, part) then
						local hit = false
						for k = 1, 200 do
							if inside(start + vector * (k / 200), size, part) then
								hit = true
								break
							end
						end
						if not hit then
							continue
						end
					end
					local lo, hi = 0, length
					for _ = 1, 40 do
						local mid = (lo + hi) / 2
						if inside(start + vector.Unit * mid, size, part) then
							hi = mid
						else
							lo = mid
						end
					end
					if best == nil or hi < (best :: number) then
						best = hi
					end
				end
				return best
			end
		end
		local checked = 0
		for _, shape in { "wall", "pillar" } do
			local from = FRAME
			-- The world flush behind the column as the swing starts (the root at the origin, the
			-- controller's), a wall across the line or a 1-stud pillar on it.
			local start = CFrame.new()
			local face = depthPast(start, 0, 0)
			local size = if shape == "wall" then Vector3.new(30, 30, 1) else Vector3.new(1, 30, 1)
			local block = Instance.new("Part")
			block.Size = size
			block.CFrame = CFrame.new(away * (face + 0.5))
			block.Anchored = true
			local cast = boxCast({ block })
			-- Parts at the clip's pose the controller's step has just written (Lune's read): the live
			-- swing's clock as the room is asked.
			local handleTime = 0
			local live: any = nil
			local function poseLive()
				local time = if live ~= nil then live.time else handleTime
				for name, solved in Pose.solve(avatar.model, avatar.base, ClipSampler.sample(clip, time)) do
					local part = avatar.model:FindFirstChild(name)
					if part ~= nil and part:IsA("BasePart") then
						part.CFrame = solved
					end
				end
			end
			handleTime = from
			poseLive()
			local real = ContactPredictor.standOff(
				avatar.model,
				clip,
				from,
				avatar.base,
				kobold,
				cast,
				{ keepOut = true, step = false }
			)
			assert(real ~= nil and real.room ~= nil, "no plan against the touching kobold")
			local plan = {
				distance = real.distance,
				away = real.away,
				to = real.to,
				keep = real.keep,
				keepUntil = real.keepUntil,
				side = real.side,
				keepSide = real.keepSide,
				room = function(at: CFrame, distance: number, clipTime: number?): number
					poseLive()
					return (real.room :: any)(at, distance, clipTime)
				end,
				roomSide = if real.roomSide ~= nil
					then function(at: CFrame, distance: number, clipTime: number?): number
						poseLive()
						return (real.roomSide :: any)(at, distance, clipTime)
					end
					else nil,
			}
			local rig = load({ choreo = true, impact = true, standOff = plan })
			for _ = 1, 40 do
				rig.frame(STILL)
			end
			rig.root.CFrame = start
			rig.setLock(Vector3.new(0, 0, -2.3))
			rig.controller.basicAttack()
			local handle: any = rig.animator.mixer:find(clipId)
			live = handle
			local drawn = 0
			local steps, toward, keepMost, codeNet, pushed = 0, 0, 0, 0, 0
			for _ = 1, 40 do
				local before = rig.root.CFrame
				rig.frame(STILL)
				keepMost = math.max(keepMost, if real.keep ~= nil then real.keep(handle.time) else 0)
				-- The root's step back, less any the clip's own root motion took back (Basic1's root
				-- settles 0.004 back after its lunge), read apart; a lunge held is no step.
				local motionBefore = ClipSampler.rootMotionAt(clip, drawn)
				local motionNow = ClipSampler.rootMotionAt(clip, handle.time)
				local carried = Vector3.new(motionNow[1] - motionBefore[1], 0, motionNow[3] - motionBefore[3])
				local back = (rig.root.Position - before.Position):Dot(away) - math.max(carried:Dot(away), 0)
				codeNet += (rig.root.Position - before.Position):Dot(away)
				toward = math.max(toward, -codeNet)
				local span = if shape == "pillar" then size.X / 2 else nil
				if back > 1e-4 then
					steps += 1
					local drawnDepth = depthPast(rig.root.CFrame, drawn, face, span)
					local stepped = depthPast(rig.root.CFrame, handle.time, face, span)
					if math.max(drawnDepth, stepped) > -GAP + 0.003 then
						error(
							("%s: at clip %.3f the code stepped the root %.3f back with the body drawn %.3f and stepped %.3f past the face"):format(
								shape,
								handle.time,
								back,
								drawnDepth,
								stepped
							)
						)
					end
				end
				-- The engine: physics with this step's pose pushes a part the clip leant into the world
				-- back out, toward the kobold (Studio's push, up to 0.6 a row).
				local into = depthPast(rig.root.CFrame, handle.time, face, span)
				if into > 0 then
					rig.root.CFrame = rig.root.CFrame - away * into
					pushed += into
				end
				drawn = handle.time
				checked += 1
				if handle.time >= clip.duration - 1e-6 or rig.controller.state() ~= "Basic" then
					break
				end
			end
			-- The keep-out wanted the body back and the clip leant into the world (else this proves
			-- nothing), and the code never took the root toward the kobold (the hold takes the lunge
			-- the wall left no room to step from, D-502); the engine's push is apart.
			expect(keepMost > 0.5).toBe(true)
			expect(pushed > 0).toBe(true)
			expect(toward <= 1e-3).toBe(true)
			print(
				("[431] %s: %d frames, %d steps back, keep up to %.3f, code toward %.4f, engine push %.3f"):format(
					shape,
					checked,
					steps,
					keepMost,
					toward,
					pushed
				)
			)
			block:Destroy()
		end
		expect(checked > 20).toBe(true)
		kobold:Destroy()
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Item 462 (D-560): the PC's takes through the real path, with a Studio-like body.

-- The separating-axis test's 15 axes for two boxes (their faces' normals and their edges' crosses).
local function boxAxes(aFrame: CFrame, bFrame: CFrame): { Vector3 }
	local axes = {
		aFrame.RightVector,
		aFrame.UpVector,
		aFrame.LookVector,
		bFrame.RightVector,
		bFrame.UpVector,
		bFrame.LookVector,
	}
	for i = 1, 3 do
		for j = 4, 6 do
			local cross = axes[i]:Cross(axes[j])
			if cross.Magnitude > 1e-4 then
				table.insert(axes, cross.Unit)
			end
		end
	end
	return axes
end

-- Half a box's extent along `axis`.
local function halfAlong(frame: CFrame, size: Vector3, axis: Vector3): number
	return size.X / 2 * math.abs(frame.RightVector:Dot(axis))
		+ size.Y / 2 * math.abs(frame.UpVector:Dot(axis))
		+ size.Z / 2 * math.abs(frame.LookVector:Dot(axis))
end

-- How far apart two boxes stand along the axis that parts them most, and that axis pointing from
-- `b` to `a`. Negative when they overlap: by the least the engine must push `a` along that axis
-- to part them.
local function separation(aFrame: CFrame, aSize: Vector3, bFrame: CFrame, bSize: Vector3): (number, Vector3)
	local offset = aFrame.Position - bFrame.Position
	local most, along = -math.huge, Vector3.zero
	for _, axis in boxAxes(aFrame, bFrame) do
		local d = offset:Dot(axis)
		local apart = math.abs(d) - halfAlong(aFrame, aSize, axis) - halfAlong(bFrame, bSize, axis)
		if apart > most then
			most = apart
			along = if d >= 0 then axis else -axis
		end
	end
	return most, along
end

-- The engine's Blockcast against `world`: how far along `vector` the box first touches a part
-- (exact: the moving box overlaps a part while it overlaps it along all 15 axes at once), never a
-- part it starts in.
local function blockcast(world: { BasePart }): (CFrame, Vector3, Vector3) -> number?
	return function(start: CFrame, size: Vector3, vector: Vector3): number?
		local length = vector.Magnitude
		if length < 1e-9 then
			return nil
		end
		local best: number? = nil
		for _, part in world do
			local offset = start.Position - part.CFrame.Position
			local enter, leave = -math.huge, math.huge
			for _, axis in boxAxes(start, part.CFrame) do
				local reach = halfAlong(start, size, axis) + halfAlong(part.CFrame, part.Size, axis)
				local d, speed = offset:Dot(axis), vector:Dot(axis)
				if math.abs(speed) < 1e-12 then
					if math.abs(d) >= reach then
						enter, leave = math.huge, -math.huge
						break
					end
				else
					local t1, t2 = (-reach - d) / speed, (reach - d) / speed
					enter, leave = math.max(enter, math.min(t1, t2)), math.min(leave, math.max(t1, t2))
				end
			end
			if enter >= 0 and enter <= 1 and enter < leave then
				local hit = enter * length
				if best == nil or hit < (best :: number) then
					best = hit
				end
			end
		end
		return best
	end
end

-- Where the held kobold stands (its root goes its rig's root height above).
local KOBOLD_AT = Vector3.new(30, 0, 30)

-- The matrix's stand-in for the owner's avatar and a real kobold held at KOBOLD_AT facing the
-- player (-Z), its blockers colliding (SkyspireBlockers: the parts a player collides with).
local function bench(): any
	local fs = require("@lune/fs")
	local Combat = Harness.load("src/shared/data/combat")
	local Enemies = Harness.load("src/shared/data/enemies")
	local World = Harness.load("src/shared/data/world")
	local Pose = Harness.load("src/shared/choreo/Pose")
	local RigBuilder = Harness.load("src/server/world/RigBuilder")
	local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
	local source = fs.readFile(Harness.repoRoot() .. "/tools/hitmatrix/HitMatrix.luau")
	local HitMatrix = luau.load(source, {
		debugName = "tools/hitmatrix/HitMatrix",
		environment = { require = require } :: any,
	})()
	local avatar = HitMatrix.standing(Harness)
	local def = Enemies.byId("KoboldAxeman")
	local kobold = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, kobold.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local koboldRoot = CFrame.new(KOBOLD_AT.X, height, KOBOLD_AT.Z)
	for name, solved in Pose.solve(kobold, koboldRoot, {}) do
		local part = kobold:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	RigBuilder.addBlocker(kobold)
	local blockers: { BasePart } = {}
	for _, child in kobold:GetChildren() do
		if child:IsA("BasePart") and (child.Name == "Blocker" or child.Name == "HeldBlocker") then
			child.CanCollide = true
			table.insert(blockers, child)
		end
	end
	local chain = Pose.chain(avatar.model)
	local STAND_OFF = Combat.contact.standOff
	return {
		avatar = avatar,
		kobold = kobold,
		koboldRoot = koboldRoot,
		blockers = blockers,
		chain = chain,
		column = STAND_OFF.keepOut.parts,
		gap = STAND_OFF.wallGapStuds :: number,
		-- Every part's world CFrame with the root at `root` and the joints at `transforms`.
		solve = function(root: CFrame, transforms: { [string]: CFrame }): { [string]: CFrame }
			local solved: { [string]: CFrame } = { [chain.rootName] = root }
			for _, link in chain.links do
				local transform = transforms[link.name] or CFrame.identity
				solved[link.part1] = solved[link.part0] * link.c0 * transform * link.c1Inverse
			end
			return solved
		end,
	}
end

-- The world flush behind: a {10, 8, 1} wall or a 2x8x2 pillar on the line, its face at z `face`.
local function blockAt(shape: string, face: number): Part
	local block = Instance.new("Part")
	block.Anchored = true
	if shape == "wall" then
		block.Size = Vector3.new(10, 8, 1)
		block.CFrame = CFrame.new(30, 4, face - 0.5)
	else
		block.Size = Vector3.new(2, 8, 2)
		block.CFrame = CFrame.new(30, 4, face - 1)
	end
	return block
end

-- Studio's body as this bench assumes it (item 462: an assumption, not a measurement): physics
-- in 1/240 s substeps, the Humanoid's walk (MoveDirection x WalkSpeed, flat), then each colliding
-- part (keepOut.parts, posed by this frame's Choreo pose on the root) pushed out of the world and
-- the kobold's blockers along the least way out, flattened (the Humanoid stands upright), the
-- pushes summed and applied at a quarter, four passes a substep. The wall, the pillar and the
-- held kobold never move.
local SUBSTEP_HZ = 240
local PUSH_SHARE = 0.25
local PUSH_PASSES = 4

-- What the PC's take on the owner's avatar has that the bench's plain take leaves out (item 496),
-- each an assumption fitted to the PC's rows, not a measurement of the engine:
-- `hits`: each cut lands on its strike key and holds the rig there (a Normal 3 frames, Sharp
-- Nail's last a Final 6), so after each freeze the root runs a step behind its pose (D-496);
-- `jitter`: each frame lasts 1/fps times 1 plus up to this share either way (the PC's 144 rows ran
-- 3.5 to 8.1 ms); `contact`: the engine leaves a pressed colliding part this deep in the face (the
-- PC's walk-in rests the deepest colliding part 0.050-0.056 in; 0.04 rests the bench's at
-- 0.055-0.058); `headDepth` and `headCollides`: the owner's Head, a MeshPart 1.27 deep that does
-- not collide (with `headCollides` nil each column part collides as its CanCollide reads, D-630);
-- `art`: the Art swung 3 times after Basic1 (a clip name; Sharp Nail when nil).
local CombatData = Harness.load("src/shared/data/combat")
local HIT_STOP_FRAMES = CombatData.hitStopFrames
local STRIKE_EPSILON: number = CombatData.contact.keyEpsilon
local ChoreoPose = Harness.load("src/shared/choreo/Pose")

type Conditions = {
	hits: boolean?,
	jitter: number?,
	contact: number?,
	headDepth: number?,
	headCollides: boolean?,
	-- The Art swung 3 times after Basic1 (a name in its clip id; Sharp Nail when nil), D-627.
	art: string?,
}

-- One take as the PC ran it: placed at z `start` facing the kobold (locked), still 0.3 s, S held
-- 0.5 s, still 0.3 s, Basic1, still 0.4 s, then 3 times Sharp Nail (held 0.2 s, released) and
-- still 0.4 s, at `fps`. The code's root (Character+1) is the root after the frame less what the
-- body did in physics; the screen is the pose before on that root (D-535).
local function take(b: any, shape: string, face: number, fps: number, start: number, conditions: Conditions?): any
	local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
	local pc: Conditions = conditions or {}
	local avatar = b.avatar
	local GAP: number = b.gap
	local block = blockAt(shape, face)
	local obstacles: { BasePart } = { block }
	for _, blocker in b.blockers do
		table.insert(obstacles, blocker)
	end
	local cast = blockcast({ block })
	local headPart = avatar.model:FindFirstChild("Head") :: BasePart
	local headSize = headPart.Size
	if pc.headDepth ~= nil then
		headPart.Size = Vector3.new(headSize.X, headSize.Y, pc.headDepth)
	end
	local sizes: { [string]: Vector3 } = {}
	for _, name in b.column do
		sizes[name] = (avatar.model:FindFirstChild(name) :: BasePart).Size
	end
	-- What the engine collides (and pushes out): the column, less a Head that does not collide, and
	-- with `headCollides` nil less any part whose CanCollide reads false (D-630).
	local colliding: { string } = {}
	for _, name in b.column do
		local collides = if name == "Head" and pc.headCollides ~= nil
			then pc.headCollides
			else (avatar.model:FindFirstChild(name) :: BasePart).CanCollide
		if collides then
			table.insert(colliding, name)
		end
	end
	local contact: number = pc.contact or 0
	local function pose(root: CFrame, transforms: { [string]: CFrame })
		for name, solved in b.solve(root, transforms) do
			local part = avatar.model:FindFirstChild(name)
			if part ~= nil and part:IsA("BasePart") then
				part.CFrame = solved
			end
		end
	end
	local rig: any = nil
	local shown: { [string]: CFrame } = {}
	-- The real plan on the avatar as the screen shows it, asked again on the root of the moment.
	local function standOffWith(
		_model: any,
		clip: any,
		from: number,
		rootCFrame: CFrame,
		_target: any,
		_cast: any,
		options: any
	): any
		pose(rootCFrame, shown)
		local real = ContactPredictor.standOff(avatar.model, clip, from, rootCFrame, b.kobold, cast, options)
		if real == nil then
			return nil
		end
		local plan = table.clone(real)
		local room, roomSide = real.room, real.roomSide
		if room ~= nil then
			plan.room = function(at: CFrame, distance: number, clipTime: number?): number
				pose(rig.root.CFrame, shown)
				return room(at, distance, clipTime)
			end
		end
		if roomSide ~= nil then
			plan.roomSide = function(at: CFrame, distance: number, clipTime: number?): number
				pose(rig.root.CFrame, shown)
				return roomSide(at, distance, clipTime)
			end
		end
		return plan
	end
	-- `byKobold`: the share of the push out of the kobold's blockers alone (D-627).
	local pushed, walked, byKobold = Vector3.zero, Vector3.zero, Vector3.zero
	local function physics(dt: number)
		local count = math.max(1, math.floor(dt * SUBSTEP_HZ + 0.5))
		local h = dt / count
		local transforms = rig.animator.pose
		pushed, walked, byKobold = Vector3.zero, Vector3.zero, Vector3.zero
		for _ = 1, count do
			local velocity = rig.humanoid.MoveDirection * rig.humanoid.WalkSpeed
			local walk = Vector3.new(velocity.X, 0, velocity.Z) * h
			rig.root.CFrame = rig.root.CFrame + walk
			walked += walk
			for _ = 1, PUSH_PASSES do
				local solved = b.solve(rig.root.CFrame, transforms)
				local push, fromKobold = Vector3.zero, Vector3.zero
				for _, name in colliding do
					for _, obstacle in obstacles do
						local apart, along = separation(solved[name], sizes[name], obstacle.CFrame, obstacle.Size)
						if apart < -contact then
							local out = Vector3.new(along.X, 0, along.Z) * (-apart - contact)
							push += out
							if obstacle ~= block then
								fromKobold += out
							end
						end
					end
				end
				rig.root.CFrame = rig.root.CFrame + push * PUSH_SHARE
				pushed += push * PUSH_SHARE
				byKobold += fromKobold * PUSH_SHARE
			end
		end
	end
	rig = load({
		choreo = true,
		impact = true,
		standOffWith = standOffWith,
		worldCast = cast,
		frameSeconds = 1 / fps,
		physics = physics,
	})
	local ry: number = avatar.rootHeight
	local koboldAt = Vector3.new(KOBOLD_AT.X, b.koboldRoot.Position.Y, KOBOLD_AT.Z)
	rig.root.CFrame = CFrame.lookAt(Vector3.new(30, ry, start), Vector3.new(KOBOLD_AT.X, ry, KOBOLD_AT.Z))
	rig.setLock(koboldAt)
	rig.animator:play("player/OneHandedSword/IdleDrawn", {})
	local basicId = "player/OneHandedSword/Basic1"
	local slot, artId = 1, ""
	local artName = pc.art or "SharpNail"
	for index, art in rig.controller.slots() do
		if art.clip:find(artName) then
			slot, artId = index, art.clip
		end
	end
	assert(artId ~= "", "no " .. artName .. " in the slots")
	local clips = {
		[basicId] = Harness.load("src/shared/clips/" .. basicId),
		[artId] = Harness.load("src/shared/clips/" .. artId),
	}
	-- Each cut's strike key and its hold (combat.luau hitStopFrames: an Art's last cut is its Final).
	local strikes: { [string]: { { key: number, frames: number } } } = {}
	for id, clip in clips do
		local windows = ClipSampler.hitWindows(clip)
		local list = {}
		for index, window in windows do
			local final = id == artId and index == #windows
			table.insert(list, {
				key = ContactPredictor.strikeKey(clip, window),
				frames = if final then HIT_STOP_FRAMES.Final else HIT_STOP_FRAMES.Normal,
			})
		end
		strikes[id] = list
	end
	-- A fixed sequence of frame times (a linear congruential generator), the same every run.
	local seed = 7
	local function nextShare(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return 2 * seed / 2147483648 - 1
	end
	local rows: { any } = {}
	local swingWas: { [number]: number } = {}
	local function row(label: string)
		local dt = 1 / fps
		if pc.jitter ~= nil then
			dt *= 1 + pc.jitter * nextShare()
		end
		rig.setFrameSeconds(dt)
		local first = rig.root.CFrame
		shown = table.clone(rig.animator.pose)
		local drawn = shown
		local before: { [string]: number } = {}
		for id in clips do
			local handle = rig.animator.mixer:find(id)
			if handle ~= nil then
				before[id] = handle.time
			end
		end
		local stick = Vector3.zero
		if label == "S" then
			local back = Vector3.new(first.X - KOBOLD_AT.X, 0, first.Z - KOBOLD_AT.Z)
			stick = back.Unit
		end
		rig.frame(stick)
		-- What the clip's own root motion carried this frame (the controller's `carried`).
		local carried = Vector3.zero
		for id, clip in clips do
			local handle = rig.animator.mixer:find(id)
			local was = before[id]
			if handle ~= nil and was ~= nil and handle.time >= was then
				local a = ClipSampler.rootMotionAt(clip, was)
				local c = ClipSampler.rootMotionAt(clip, handle.time)
				carried += first:VectorToWorldSpace(Vector3.new(c[1] - a[1], 0, c[3] - a[3]))
				if pc.hits then
					for _, strike in strikes[id] do
						if was < strike.key - STRIKE_EPSILON and handle.time >= strike.key - STRIKE_EPSILON then
							rig.animator:hitStop(strike.frames)
						end
					end
				end
			end
		end
		-- The swing the rig plays (fading in or out included) and its clip time before and now.
		local swing: any = nil
		for _, handle in rig.animator:handles() do
			local clip = clips[handle.clipId]
			if clip ~= nil and not handle.done then
				swing = {
					id = handle.id,
					clip = clip,
					time = handle.time,
					was = swingWas[handle.id] or handle.time,
					alone = handle.fade >= 1 - 1e-6 and handle.weight >= 1 - 1e-6 and not handle.stopping,
				}
				swingWas[handle.id] = handle.time
			end
		end
		local after = rig.root.CFrame
		table.insert(rows, {
			label = label,
			dt = dt,
			first = first,
			code = after - pushed - walked,
			after = after,
			kobold = Vector3.new(byKobold.X, 0, byKobold.Z).Magnitude,
			drawn = drawn,
			carried = carried,
			swing = swing,
		})
	end
	local function hold(label: string, seconds: number)
		for _ = 1, math.floor(seconds * fps + 0.5) do
			row(label)
		end
	end
	hold("place", 0.3)
	hold("S", 0.5)
	local holdEnd = #rows
	hold("rest", 0.3)
	local chainStart = #rows + 1
	rig.controller.basicAttack()
	for _ = 1, math.floor(1.2 * fps) do
		row("Basic1")
		if rig.controller.state() ~= "Basic" then
			break
		end
	end
	hold("idle", 0.4)
	for k = 1, 3 do
		rig.controller.beginArt(slot)
		hold("hold", 0.2)
		rig.controller.releaseArt(slot, 0.2)
		for _ = 1, math.floor(2.5 * fps) do
			row("Art" .. k)
			if rig.controller.state() ~= "Art" and rig.controller.state() ~= "Holding" then
				break
			end
		end
		hold("idle", 0.4)
	end
	-- The lines (462 and 431(c)/(e)) on this bench.
	local result = {
		before = -math.huge, -- the column's deepest on the screen before the chain
		codeShare = 0, -- (a) over Basic1, toward the kobold
		engineShare = 0,
		touching = 0, -- (b) rows a colliding part on the screen is within the gap of the block
		into = 0, -- (b) the most the code's step (less the clip's own motion) took a touching part closer
		intoRows = 0,
		back = 0, -- (b) as written: the code's step back (less the clip's own) on touching rows
		root = -math.huge, -- (c) the root box's deepest, at Character+1 and after physics
		step = -math.huge, -- (d) the most the code's step went past 12 x dt and the clip's own motion
		stepOver = 0,
		raw = 0, -- (d) the code's step as written
		rawOver = 0,
		torso = { UpperTorso = -math.huge, LowerTorso = -math.huge, Head = -math.huge } :: { [string]: number }, -- (e) on the screen
		firstOver = 0, -- (e) First-to-First rows over 12 x dt
		engineSlide = 0, -- (e) the engine's move along the face over the take
		slide = 0, -- (e) the body's move along the face over the take
		rows = #rows - chainStart + 1,
		-- Item 496's readings:
		pre = -math.huge, -- the pre-check: the colliding parts' deepest on the S hold's last row
		preHead = 0, -- and the Head's
		normal = 0, -- (b) the code's step along the inward normal of the face a touching part is nearest
		stepLag = -math.huge, -- (d) past max(12 x the longer of this frame and the one before, m, m before)
		alone = 0, -- (e) |uto - utoClip(tPrev)| on rows that draw the swing alone at full weight
		aloneRows = 0,
		blend = 0, -- (e) the same on rows that draw it fading in or out
		blendRows = 0,
		firstLag = 0, -- (f) First-to-First rows over (d)'s long-row bar
		-- The engine's shove over the chain (D-627): the most it moved the root on one row (out of
		-- the world and the blockers, flat) and the path it moved it in all.
		push = 0,
		pushPath = 0,
		-- Of it, the share out of the kobold's blockers: the most on one row and the path in all.
		koboldPush = 0,
		koboldPath = 0,
	}
	local rootSize: Vector3 = avatar.model.PrimaryPart.Size
	local function depth(frame: CFrame, size: Vector3): number
		return -separation(frame, size, block.CFrame, block.Size)
	end
	do
		local r = rows[holdEnd]
		local screen = b.solve(r.code, r.drawn)
		for _, name in colliding do
			result.pre = math.max(result.pre, depth(screen[name], sizes[name]))
		end
		result.preHead = depth(screen.Head, sizes.Head)
	end
	local dt = 1 / fps
	local function ownMotion(r: any): Vector3
		local swing = r.swing
		if swing == nil then
			return Vector3.zero
		end
		local a = ClipSampler.rootMotionAt(swing.clip, swing.was)
		local c = ClipSampler.rootMotionAt(swing.clip, swing.time)
		return Vector3.new(c[1] - a[1], 0, c[3] - a[3])
	end
	for index, r in rows do
		local toward = Vector3.new(KOBOLD_AT.X - r.first.X, 0, KOBOLD_AT.Z - r.first.Z).Unit
		local code = r.code.Position - r.first.Position
		local engine = r.after.Position - r.code.Position
		local screen = b.solve(r.code, r.drawn)
		if index < chainStart then
			for _, name in b.column do
				result.before = math.max(result.before, depth(screen[name], sizes[name]))
			end
			continue
		end
		if r.label == "Basic1" then
			result.codeShare += code:Dot(toward)
			result.engineShare += engine:Dot(toward)
		end
		local shove = Vector3.new(engine.X, 0, engine.Z).Magnitude
		result.push = math.max(result.push, shove)
		result.pushPath += shove
		result.koboldPush = math.max(result.koboldPush, r.kobold)
		result.koboldPath += r.kobold
		-- The code's own step, its turn left out (the stand-off moves the root; the facing is apart),
		-- and the clip's root motion alone, each against the screen at First.
		local fromFirst = b.solve(r.first, r.drawn)
		local stepped = b.solve(CFrame.new(r.code.Position) * r.first.Rotation, r.drawn)
		local carriedOnly = b.solve(r.first + r.carried, r.drawn)
		local near, worst = false, 0
		for _, name in colliding do
			local was, along = separation(fromFirst[name], sizes[name], block.CFrame, block.Size)
			if was < GAP then
				near = true
				local now = separation(stepped[name], sizes[name], block.CFrame, block.Size)
				local clipOwn = separation(carriedOnly[name], sizes[name], block.CFrame, block.Size)
				worst = math.max(worst, (was - now) - math.max(was - clipOwn, 0))
				-- Item 496 (b): along the inward normal of the face it is nearest (`along` points out).
				local inward = -Vector3.new(along.X, 0, along.Z)
				if inward.Magnitude > 1e-6 then
					inward = inward.Unit
					result.normal = math.max(result.normal, code:Dot(inward) - math.max(r.carried:Dot(inward), 0))
				end
			end
		end
		if near then
			result.touching += 1
			result.into = math.max(result.into, worst)
			if worst > 1e-3 then
				result.intoRows += 1
			end
			-- As the 431 spec reads it: less any of the step back the clip's own motion took.
			result.back = math.max(result.back, -code:Dot(toward) - math.max(-r.carried:Dot(toward), 0))
		end
		result.root = math.max(result.root, depth(r.code, rootSize), depth(r.after, rootSize))
		for name in result.torso do
			result.torso[name] = math.max(result.torso[name], depth(screen[name], sizes[name]))
		end
		-- Past 12 x dt only by the clip's own root motion (Sharp Nail's lunge, 0.285 a frame at 60
		-- where nothing holds it) is the clip's, not a step of the code's.
		local flat = Vector3.new(code.X, 0, code.Z).Magnitude
		local beyond = flat - math.max(12 * dt, r.carried.Magnitude)
		result.step = math.max(result.step, beyond)
		if beyond > 1e-4 then
			result.stepOver += 1
		end
		result.raw = math.max(result.raw, flat)
		if flat > 12 * dt + 1e-4 then
			result.rawOver += 1
		end
		-- Item 496 (d) on the PC's own columns: m from the handle's clip times, and after a freeze the
		-- root shows the step before's share (D-496), so the frame before counts too (item 500).
		local previous = rows[index - 1]
		local m = ownMotion(r)
		local mBefore = if previous.swing ~= nil
				and r.swing ~= nil
				and previous.swing.id == r.swing.id
			then ownMotion(previous)
			else Vector3.zero
		local bar = math.max(12 * math.max(r.dt, previous.dt), m.Magnitude, mBefore.Magnitude)
		result.stepLag = math.max(result.stepLag, flat - bar)
		local nextFirst = if rows[index + 1] ~= nil then rows[index + 1].first else r.after
		local firstStep = Vector3.new(nextFirst.X - r.first.X, 0, nextFirst.Z - r.first.Z).Magnitude
		if firstStep > 12 * dt + 1e-4 then
			result.firstOver += 1
		end
		if firstStep > bar + 1e-3 then
			result.firstLag += 1
		end
		-- Item 496 (e): the UpperTorso in the root's frame as the screen draws it (the pose before)
		-- against the clip's own at the clip time that pose was written at.
		local swing, swingBefore = r.swing, previous.swing
		if swing ~= nil and r.label ~= "hold" then
			local uto = b.solve(CFrame.identity, r.drawn).UpperTorso.Position
			local own =
				ChoreoPose.solve(avatar.model, CFrame.identity, ClipSampler.sample(swing.clip, swing.was)).UpperTorso.Position
			local off = (uto - own).Magnitude
			if swingBefore ~= nil and swingBefore.id == swing.id and swingBefore.alone then
				result.alone = math.max(result.alone, off)
				result.aloneRows += 1
			else
				result.blend = math.max(result.blend, off)
				result.blendRows += 1
			end
		end
		result.engineSlide += engine.X
	end
	result.slide = rows[#rows].after.X - rows[1].first.X
	local line = ("[462] %s %d face %.2f: before the chain %.3f in | (a) code %.4f engine %.3f | (b) touching %d, into %.4f on %d, back %.4f | (c) root %.3f | (d) %.3f past the line (as written %.3f, %d over %.3f) | (e) UT %.3f LT %.3f Head %.3f; First-to-First over %d; slide %.2f (engine %.2f)"):format(
		shape,
		fps,
		face,
		result.before,
		result.codeShare,
		result.engineShare,
		result.touching,
		result.into,
		result.intoRows,
		result.back,
		result.root,
		result.step,
		result.raw,
		result.rawOver,
		12 * dt,
		result.torso.UpperTorso,
		result.torso.LowerTorso,
		result.torso.Head,
		result.firstOver,
		result.slide,
		result.engineSlide
	)
	if conditions ~= nil then
		line ..= (" || [496] pre-check colliding %.3f, Head %.3f | (b) along the face's normal %.4f | (d) past the long-row bar %.4f | (e) alone %.3f on %d, fading %.3f on %d | (f) First-to-First over the long-row bar %d"):format(
			result.pre,
			result.preHead,
			result.normal,
			result.stepLag,
			result.alone,
			result.aloneRows,
			result.blend,
			result.blendRows,
			result.firstLag
		)
	end
	print(line)
	headPart.Size = headSize
	block:Destroy()
	return result
end

describe("the stand-off against a Studio-like body at a wall or a pillar flush behind (item 462, D-560)", function()
	it("the PC's setup leaves the body less room than its drawn idle needs, before any swing", function()
		-- Along the line from the kobold: where its blockers' face stands, against how deep the matrix
		-- column is drawn (the idle) and swung (Basic1, Sharp Nail, their lunge held as the stand-off
		-- holds it against a touching target, D-502), from the front of the column to its back.
		local b = bench()
		local Pose = Harness.load("src/shared/choreo/Pose")
		-- The blockers across the line (x within the root box's half width of 30) the body backs onto.
		local blockerFace = math.huge
		local rootHalf = (b.avatar.model.PrimaryPart :: BasePart).Size.X / 2
		for _, blocker in b.blockers do
			local half = blocker.Size / 2
			local frame = blocker.CFrame
			local reachZ = half.X * math.abs(frame.RightVector.Z)
				+ half.Y * math.abs(frame.UpVector.Z)
				+ half.Z * math.abs(frame.LookVector.Z)
			local reachX = half.X * math.abs(frame.RightVector.X)
				+ half.Y * math.abs(frame.UpVector.X)
				+ half.Z * math.abs(frame.LookVector.X)
			print(
				("[462] %s at (%.3f, %.3f), %.3f across, %.3f deep"):format(
					blocker.Name,
					frame.Position.X,
					frame.Position.Z,
					2 * reachX,
					2 * reachZ
				)
			)
			if math.abs(frame.Position.X - KOBOLD_AT.X) < reachX + rootHalf then
				blockerFace = math.min(blockerFace, frame.Position.Z - reachZ)
			end
		end
		local facing = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, 1))
		local function columnDepth(id: string): number
			local clip = Harness.load("src/shared/clips/" .. id)
			local most = -math.huge
			local time = 0
			while true do
				local front, back = -math.huge, -math.huge
				local solved = Pose.solve(b.avatar.model, facing, ClipSampler.sample(clip, time))
				for _, name in b.column do
					local part = b.avatar.model:FindFirstChild(name) :: BasePart
					local frame = solved[name]
					local half = part.Size / 2
					local reach = half.X * math.abs(frame.RightVector.Z)
						+ half.Y * math.abs(frame.UpVector.Z)
						+ half.Z * math.abs(frame.LookVector.Z)
					front = math.max(front, frame.Position.Z + reach)
					back = math.max(back, -(frame.Position.Z - reach))
				end
				most = math.max(most, front + back)
				if time >= clip.duration then
					break
				end
				time = math.min(time + 1 / 60, clip.duration)
			end
			return most
		end
		local idle = columnDepth("player/OneHandedSword/IdleDrawn")
		local basic = columnDepth("player/OneHandedSword/Basic1")
		local art = columnDepth("player/OneHandedSword/SharpNail")
		local pcGap = blockerFace - 27.6
		local gap = blockerFace - 25.7
		print(
			("[462] blockers' face z %.3f: the PC's gap %.3f, the drawn idle's column %.3f, Basic1's %.3f, Sharp Nail's %.3f; the kobold's own stand (face 25.70) %.3f"):format(
				blockerFace,
				pcGap,
				idle,
				basic,
				art,
				gap
			)
		)
		-- The PC's take (face 27.6) has the body overlap the wall or the blockers before it swings:
		-- the engine, not the code, decides where it goes (D-561). Face 25.7 (a kobold at its stop
		-- distance from a body backed to the wall) leaves every swing its column and the gap twice.
		expect(pcGap < idle).toBe(true)
		expect(gap >= math.max(idle, basic, art) + 2 * b.gap).toBe(true)
		b.kobold:Destroy()
	end)

	it("leaves no room behind a root box the engine has pressed into the world (D-560)", function()
		-- The matrix body drawn, its root 2.3 from the kobold; a low block behind (a crate) that only
		-- the root's box reaches (below the torsos and the head over all of Basic1), standing out of
		-- it or `into` deep in it. The real plan's room straight back must be the gap short of it, and
		-- none once the box is in: the engine's Blockcast never meets a part it starts in, so a root
		-- cast from where it stands found no world and stepped on in, a tenth a frame (the pillar
		-- take below).
		local b = bench()
		local Pose = Harness.load("src/shared/choreo/Pose")
		local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
		local clip = Harness.load("src/shared/clips/player/OneHandedSword/Basic1")
		local idle = Harness.load("src/shared/clips/player/OneHandedSword/IdleDrawn")
		local model = b.avatar.model
		local rootPart = model.PrimaryPart :: BasePart
		local ry: number = b.avatar.rootHeight
		local rootCFrame = CFrame.lookAt(Vector3.new(30, ry, KOBOLD_AT.Z - 2.3), Vector3.new(30, ry, KOBOLD_AT.Z))
		for name, solved in Pose.solve(model, rootCFrame, ClipSampler.sample(idle, 0)) do
			local part = model:FindFirstChild(name)
			if part ~= nil and part:IsA("BasePart") then
				part.CFrame = solved
			end
		end
		local lowest = math.huge
		local time = 0
		while true do
			local solved = Pose.solve(model, rootCFrame, ClipSampler.sample(clip, time))
			for _, name in b.column do
				local part = model:FindFirstChild(name) :: BasePart
				if part ~= rootPart then
					for _, frame in { solved[name], part.CFrame } do
						local half = part.Size / 2
						local reach = half.X * math.abs(frame.RightVector.Y)
							+ half.Y * math.abs(frame.UpVector.Y)
							+ half.Z * math.abs(frame.LookVector.Y)
						lowest = math.min(lowest, frame.Position.Y - reach)
					end
				end
			end
			if time >= clip.duration then
				break
			end
			time = math.min(time + 1 / 60, clip.duration)
		end
		local rootBottom = rootCFrame.Position.Y - rootPart.Size.Y / 2
		local rootBack = rootCFrame.Position.Z - rootPart.Size.Z / 2
		local top = lowest - 0.1
		assert(top > rootBottom + 0.3, "no room for a block only the root's box reaches")
		local crate = Instance.new("Part")
		crate.Anchored = true
		crate.Size = Vector3.new(6, top - (rootBottom - 1), 2)
		local cast = blockcast({ crate })
		local function roomWith(into: number): number
			crate.CFrame = CFrame.new(30, (top + rootBottom - 1) / 2, rootBack + into - 1)
			local plan = ContactPredictor.standOff(
				model,
				clip,
				FRAME,
				rootCFrame,
				b.kobold,
				cast,
				{ keepOut = true, step = false }
			)
			assert(plan ~= nil and plan.room ~= nil, "no plan against the touching kobold")
			expect(plan.away.Z < -0.99).toBe(true)
			return plan.room(rootCFrame, 0.5, FRAME)
		end
		local out = roomWith(-0.3)
		local touching = roomWith(0.03)
		local pressed = { roomWith(0.1), roomWith(0.25), roomWith(0.5) }
		print(
			("[462] the root box 0.3 out: room %.4f; 0.03 in: %.4f; 0.1, 0.25 and 0.5 in: %.4f %.4f %.4f"):format(
				out,
				touching,
				pressed[1],
				pressed[2],
				pressed[3]
			)
		)
		expect(math.abs(out - (0.3 - b.gap)) <= 1e-3).toBe(true)
		expect(touching).toBe(0)
		for _, room in pressed do
			expect(room).toBe(0)
		end
		crate:Destroy()
		b.kobold:Destroy()
	end)

	it("never steps the body deeper into a pillar the engine has pushed it into, at 30, 60 and 144", function()
		-- A pillar 0.45 further back than the PC's (face 27.15): the drawn idle fits between it and
		-- the blockers, the swings do not, so the engine presses the root box 0.4 into the pillar and
		-- turns the body round its edge. Before D-560 the code then stepped the root on into the
		-- pillar, a tenth of a stud a frame (0.106 on 11 rows at 30, 0.100 on 11 at 60). The engine's
		-- push, the slide round the edge and the steps back along its side are the squeeze's (the
		-- PC's setup, the first test), not a step into the world.
		local b = bench()
		for _, fps in { 30, 60, 144 } do
			local result = take(b, "pillar", 27.15, fps, 27.625)
			expect(result.touching > 100).toBe(true)
			expect(result.into <= 1e-3).toBe(true)
			-- Item 496 (h): nor along the inward normal of the face each touching part is nearest, the
			-- front or a side; the UpperTorso's 0.49-0.51 and the rows over 12 x dt are the engine's.
			expect(result.normal <= 1e-3).toBe(true)
		end
		b.kobold:Destroy()
	end)

	it("keeps the visible body out of a wall or a pillar at the kobold's own stand, at 30, 60 and 144", function()
		-- The face at 25.7 (a kobold at its stop distance from a body backed to the wall), the player
		-- placed at 26.6 and S held into it: 462 (a) to (e) and 431 (c) on the Studio-like body.
		local b = bench()
		for _, shape in { "wall", "pillar" } do
			for _, fps in { 30, 60, 144 } do
				local result = take(b, shape, 25.7, fps, 26.6)
				expect(result.before <= b.gap).toBe(true)
				expect(result.codeShare <= 1e-3).toBe(true)
				expect(result.touching > 30).toBe(true)
				expect(result.into <= 1e-3).toBe(true)
				expect(result.root <= b.gap).toBe(true)
				expect(result.step <= 1e-4).toBe(true)
				expect(result.back <= 1e-3).toBe(true)
				for _, deepest in result.torso do
					expect(deepest <= b.gap).toBe(true)
				end
				-- The slide is the code's own aside (D-315) and, at the pillar's edge, the engine pushing
				-- the clip's own lean out sideways (431(e)); the PC's 3.4 to 5.9 was the squeeze's.
				expect(math.abs(result.slide) <= 1).toBe(true)
				if shape == "wall" then
					expect(math.abs(result.engineSlide) <= 0.05).toBe(true)
				end
			end
		end
		b.kobold:Destroy()
	end)
end)

describe("the stand-off at the kobold's own stand under the PC's conditions (item 496)", function()
	it("never steps a body resting on the face into it, along the face's normal, at 30, 60 and 144", function()
		-- The PC's take on the owner's avatar (82b82d4): each cut holds the rig on its key, so the
		-- root runs a step behind its pose after each freeze (D-496); 144 Hz frames 3.8 to 10 ms; the
		-- engine rests a pressed colliding part on the face (the PC's walk-in 0.050-0.056 in); the
		-- Head is 1.27 deep and does not collide. (b) as written reads the step on the line to the
		-- kobold, which turns 7 to 10 degrees off the face's normal once the body has slid 0.5 to 0.6
		-- along it, so a step along the face reads as back (Lune up to 0.0017, the PC up to 0.016):
		-- along the face's own normal, judged where the body stood at First, it is none.
		local b = bench()
		for _, shape in { "wall", "pillar" } do
			for _, fps in { 30, 60, 144 } do
				local result = take(b, shape, 25.7, fps, 26.6, {
					hits = true,
					jitter = if fps == 144 then 0.45 else nil,
					contact = 0.04,
					headDepth = 1.27,
					headCollides = false,
				})
				-- The pre-check on the colliding parts: the engine's own contact, not a squeeze.
				expect(result.pre > b.gap).toBe(true)
				expect(result.pre <= 0.07).toBe(true)
				-- (b) along the face's normal, and (b) as the separation reads it.
				expect(result.touching > 30).toBe(true)
				expect(result.normal <= 1e-3).toBe(true)
				expect(result.into <= 1e-3).toBe(true)
				-- (c) and (f): no colliding part deeper than the engine's contact holds it.
				expect(result.root <= 0.07).toBe(true)
				expect(result.torso.UpperTorso <= 0.07).toBe(true)
				expect(result.torso.LowerTorso <= 0.07).toBe(true)
				-- (d) with the long-row rule: a row after a freeze shows the step before's share.
				expect(result.stepLag <= 1e-3).toBe(true)
				-- (e) on the rows the screen draws the swing alone at full weight; the fade in from the
				-- idle or the Art's hold and the fade out after the clip's end are the boundary rows.
				expect(result.aloneRows > 100).toBe(true)
				expect(result.alone <= 0.05).toBe(true)
				expect(result.blendRows > 0).toBe(true)
				expect(math.abs(result.slide) <= 1).toBe(true)
			end
		end
		b.kobold:Destroy()
	end)
end)

-- The owner's Head as the PC logged it (F1e, items 496 and 519; dev.luau hitMatrix.ownerHead): a
-- MeshPart 1.27 deep whose box's back sits 0.16 behind the UpperTorso's at the drawn idle (the
-- pre-check read UpperTorso 0.050 in and the Head 0.212), arriving with CanCollide off. The bench's
-- own Head sits further forward on the torso, so its neck is moved back until the box stands there,
-- measured on the avatar's own parts as the drawn idle poses them (as HitMatrix.leanColumns fits
-- its second body, D-642): the Head the bench pushes is the part as posed, not a number.
local OWNER_HEAD = Harness.load("src/shared/data/dev").hitMatrix.ownerHead
local OWNER_HEAD_DEPTH: number = OWNER_HEAD.depthStuds
local OWNER_HEAD_BEHIND: number = OWNER_HEAD.behindStuds

-- How far back (+Z, the root's space) a box's furthest corner stands.
local function backOf(frame: CFrame, size: Vector3): number
	local most = -math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				most = math.max(most, frame:PointToWorldSpace(size / 2 * Vector3.new(x, y, z)).Z)
			end
		end
	end
	return most
end

local function ownerHead(b: any): BasePart
	local Joints = Harness.load("src/shared/choreo/Joints")
	local Pose = Harness.load("src/shared/choreo/Pose")
	local model = b.avatar.model
	local head = model:FindFirstChild("Head") :: BasePart
	local torso = model:FindFirstChild("UpperTorso") :: BasePart
	head.Size = Vector3.new(head.Size.X, head.Size.Y, OWNER_HEAD_DEPTH)
	local idle = ClipSampler.sample(Harness.load("src/shared/clips/player/OneHandedSword/IdleDrawn"), 0)
	for _ = 1, 2 do
		local solved = Pose.solve(model, CFrame.identity, idle)
		local shift = backOf(solved.UpperTorso, torso.Size) + OWNER_HEAD_BEHIND - backOf(solved.Head, head.Size)
		for _, joint in Joints.list(model) do
			if joint.Name == "Neck" then
				if joint:IsA("Motor6D") then
					joint.C0 = CFrame.new(0, 0, shift) * joint.C0
				else
					local attachment = (joint :: any).Attachment0 :: Attachment
					attachment.CFrame = CFrame.new(0, 0, shift) * attachment.CFrame
				end
			end
		end
		local chain = Pose.chain(model)
		b.chain = chain
		b.solve = function(root: CFrame, transforms: { [string]: CFrame }): { [string]: CFrame }
			local posed: { [string]: CFrame } = { [chain.rootName] = root }
			for _, link in chain.links do
				local transform = transforms[link.name] or CFrame.identity
				posed[link.part1] = posed[link.part0] * link.c0 * transform * link.c1Inverse
			end
			return posed
		end
	end
	local solved = Pose.solve(model, CFrame.identity, idle)
	local behind = backOf(solved.Head, head.Size) - backOf(solved.UpperTorso, torso.Size)
	assert(math.abs(behind - OWNER_HEAD_BEHIND) < 1e-3, ("the owner's Head stands %.4f behind"):format(behind))
	head.CanCollide = false
	return head
end

describe("the stand-off at a Brute's stop by a fighter backed to the world (D-627, D-642)", function()
	it(
		"leaves Sharp Nail and Vertical their lean with the owner's Head colliding, the kobold's blockers never pushing the body, at 60 and 144",
		function()
			-- A Brute stops far enough off a fighter backed to a wall or a pillar to leave its lean
			-- (ai.luau backRoom.leanStuds) between the world and its Blocker, and lands on that stop
			-- (D-643): server/BruteBackRoom measures the gap through EnemyService, data/ai pins
			-- leanStuds to the deepest lean column. The column is read on the parts that collide, on a
			-- body whose Head stands where the owner's does (D-642): the owner's Head collides
			-- (D-630), and Vertical's held start pose leans it 1.68 behind the root, into a wall the
			-- engine then pushes the body off, 2.01 in front at the strike 0.07 s later. Here the PC's
			-- take swings Basic1 and three of the Art at that gap with the owner's colliding Head, and
			-- the engine never pushes the body out of the kobold's blockers (the share `koboldPush`
			-- reads). At c4f0e1c's lean (2.95, read on the matrix's Head, which sits forward of the
			-- owner's, as the deepest front plus the behind at the same moment) Vertical is squeezed
			-- between the two: the engine pushes the leaning Head off the wall and the kobold shoves
			-- the strike back.
			local AI = Harness.load("src/shared/data/ai")
			local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
			local b = bench()
			local head = ownerHead(b)
			CollisionGroups.joinPlayers(b.avatar.model)
			-- The blockers' face on the line (x within the root box's half width of the kobold's).
			local rootSize = (b.avatar.model.PrimaryPart :: BasePart).Size
			local blockerFace = math.huge
			for _, blocker in b.blockers do
				local half = blocker.Size / 2
				local frame = blocker.CFrame
				local reachZ = half.X * math.abs(frame.RightVector.Z)
					+ half.Y * math.abs(frame.UpVector.Z)
					+ half.Z * math.abs(frame.LookVector.Z)
				local reachX = half.X * math.abs(frame.RightVector.X)
					+ half.Y * math.abs(frame.UpVector.X)
					+ half.Z * math.abs(frame.LookVector.X)
				if math.abs(frame.Position.X - KOBOLD_AT.X) < reachX + rootSize.X / 2 then
					blockerFace = math.min(blockerFace, frame.Position.Z - reachZ)
				end
			end
			local function conditions(fps: number, art: string): Conditions
				return {
					hits = true,
					jitter = if fps == 144 then 0.45 else nil,
					contact = 0.04,
					art = art,
				}
			end
			local function line(label: string, art: string, shape: string, fps: number, gap: number, result: any)
				print(
					("[F1g] %s %s %s %d, gap %.3f, Head CanCollide %s: pre %.3f | root %.3f UT %.3f LT %.3f Head %.3f | First-to-First over the long-row bar %d | push %.3f (path %.3f), of it the kobold's %.3f (path %.3f)"):format(
						label,
						art,
						shape,
						fps,
						gap,
						tostring(head.CanCollide),
						result.pre,
						result.root,
						result.torso.UpperTorso,
						result.torso.LowerTorso,
						result.torso.Head,
						result.firstLag,
						result.push,
						result.pushPath,
						result.koboldPush,
						result.koboldPath
					)
				)
			end
			expect(head.CanCollide).toBe(true)
			local lean: number = AI.archetypes.Brute.backRoom.leanStuds
			for _, art in { "SharpNail", "Vertical" } do
				for _, shape in { "wall", "pillar" } do
					for _, fps in { 60, 144 } do
						local face = blockerFace - lean
						local result = take(b, shape, face, fps, face + 0.9, conditions(fps, art))
						line("the stop", art, shape, fps, lean, result)
						-- The engine's own contact before the chain, no colliding part deeper through it.
						expect(result.pre <= 0.07).toBe(true)
						expect(result.root <= 0.07).toBe(true)
						expect(result.torso.UpperTorso <= 0.07).toBe(true)
						expect(result.torso.LowerTorso <= 0.07).toBe(true)
						expect(result.torso.Head <= 0.07).toBe(true)
						expect(result.firstLag).toBe(0)
						-- The swing fits between the two faces: the kobold's blockers never push the body.
						expect(result.koboldPush <= 1e-6).toBe(true)
						expect(result.koboldPath <= 1e-6).toBe(true)
					end
				end
			end
			-- The stops before, as gaps: c4f0e1c's lean (the least gap its stop left), and the old stop
			-- root to root (stopDistance less the last tick's walk, and efa907c's stop square on a wall,
			-- 3.367) less the Blocker's front, plus the root resting the engine's 0.05 in the wall (its
			-- half depth off the face). Each is squeezed with the owner's Head: the kobold shoves it.
			local brute = AI.archetypes.Brute
			local pace = Harness.load("src/shared/data/enemies").byId("KoboldAxeman").moveSpeed
				* brute.chaseSpeedMultiplier
			local front = KOBOLD_AT.Z - blockerFace
			local behind = rootSize.Z / 2 - 0.05
			for _, old in
				{
					{ label = "c4f0e1c's lean", art = "Vertical", gap = 2.95 },
					{
						label = "the old stop",
						art = "SharpNail",
						gap = brute.stopDistance - pace * AI.tickSeconds() - front + behind,
					},
					{ label = "the old stop", art = "Vertical", gap = 3.367 - front + behind },
				}
			do
				local face = blockerFace - old.gap
				local result = take(b, "wall", face, 60, face + 0.9, conditions(60, old.art))
				line(old.label, old.art, "wall", 60, old.gap, result)
				expect(old.gap < lean).toBe(true)
				expect(result.koboldPush > 0.05).toBe(true)
			end
			b.kobold:Destroy()
		end
	)
end)

describe("the owner's Head at a flush wall and a pillar behind (item 519, D-630)", function()
	it("the character's column collides: the Head rests and swings no deeper than the torsos", function()
		-- Item 519's takes on the owner's Head, as the server's own join leaves the character: the
		-- Head arrives not colliding, CharacterReady joins it (CollisionGroups.joinPlayers), and the
		-- bench's engine pushes what then collides. Before D-630 nothing pushed the Head: it stood
		-- 0.19 in at rest, 0.24 through Sharp Nail and 0.56 through Vertical, whose lean carries the
		-- Head about 0.5 behind the torso's back (the PC 0.14-0.21 and up to 0.40). Now it rests on
		-- the face with the torsos, at the engine's contact, and no lean carries it deeper. Every
		-- other line of item 519 holds on the colliding Head. Vertical at the kobold's own stand is
		-- a squeeze for the colliding Head (the face leaves 2.44 to the Blocker): the engine pushes
		-- the leaning body forward and the Blocker pushes it back at the strike, 0.24-0.30 a row on
		-- 3 / 6 / 5 rows at 30 / 60 / 144, all the engine's, so there (f) holds by its code share.
		local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
		local b = bench()
		local head = ownerHead(b)
		CollisionGroups.joinPlayers(b.avatar.model)
		for _, art in { "SharpNail", "Vertical" } do
			for _, shape in (if art == "SharpNail" then { "wall", "pillar" } else { "wall" }) do
				for _, fps in { 30, 60, 144 } do
					local result = take(b, shape, 25.7, fps, 26.6, {
						hits = true,
						jitter = if fps == 144 then 0.45 else nil,
						contact = 0.04,
						art = art,
					})
					print(
						("[519 Head] %s %s %d: CanCollide %s, size %.2f x %.2f x %.2f | pre-check Head %.3f, colliding %.3f | through the take Head %.3f, UpperTorso %.3f, LowerTorso %.3f, root %.3f | (d) past the long-row bar %.4f | (f) First-to-First over it %d | slide %.2f"):format(
							art,
							shape,
							fps,
							tostring(head.CanCollide),
							head.Size.X,
							head.Size.Y,
							head.Size.Z,
							result.preHead,
							result.pre,
							result.torso.Head,
							result.torso.UpperTorso,
							result.torso.LowerTorso,
							result.root,
							result.stepLag,
							result.firstLag,
							result.slide
						)
					)
					-- The Head at rest and through the swings, as the colliding parts (item 519's 0.07).
					expect(result.preHead <= 0.07).toBe(true)
					expect(result.torso.Head <= 0.07).toBe(true)
					-- The pre-check: the engine's own contact, not a squeeze.
					expect(result.pre > b.gap).toBe(true)
					expect(result.pre <= 0.07).toBe(true)
					-- (b), (c), (d) and (f) as item 519 reads them.
					expect(result.touching > 30).toBe(true)
					expect(result.normal <= 1e-3).toBe(true)
					expect(result.into <= 1e-3).toBe(true)
					expect(result.root <= 0.07).toBe(true)
					expect(result.torso.UpperTorso <= 0.07).toBe(true)
					expect(result.torso.LowerTorso <= 0.07).toBe(true)
					expect(result.stepLag <= 1e-3).toBe(true)
					if art == "SharpNail" then
						expect(result.firstLag).toBe(0)
					end
					expect(math.abs(result.slide) <= 1).toBe(true)
					-- (e) on the rows that draw the swing alone at full weight.
					expect(result.aloneRows > 100).toBe(true)
					expect(result.alone <= 0.05).toBe(true)
				end
			end
		end
		b.kobold:Destroy()
	end)
end)
