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
