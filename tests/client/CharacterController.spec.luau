--!strict
--[[
	CharacterController's engine glue, loaded fresh with fakes around it: a Humanoid whose Move sets
	MoveDirection (as the engine's does), a root part, stub Choreo modules (Siblings), the render
	step captured from BindToRenderStep, and Net.client() recording every request. A frame runs the
	way the engine runs it: the control script's Move with the stick first, then the controller's
	step, then physics moves the root at the Humanoid's move and WalkSpeed (so the step reads the
	velocity of the frame before, as it does in the engine). The Humanoid records every property
	write (each one fires Changed, and a client WalkSpeed write is networked), an optional fake
	fx.Impact sibling records the director calls the controller makes, and the camera's FOV kicks
	go in the same ordered log.

	With `choreo` the controller gets a real Choreo (a fresh copy of the module, on the spec's clock)
	animating a real PlayerR15 rig, whose clip events reach the controller as Replication's
	clipEvent does, and task.delay runs on the spec's clock (after Heartbeat, as the engine resumes
	it). The render step's order against Choreo's RenderStepped connection is the spec's to pick
	(`renderOrder`), since the engine does not pin it. A render stall (the display asleep) runs
	Heartbeat and the timers and no render step; an engine hitch runs nothing at all.
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local Siblings = Harness.load("src/client/controllers/Siblings")
local ChoreoData = Harness.load("src/shared/data/choreo")
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
	-- Every scale the controller handed the animator's setTimeScale, in order (options.animator).
	timeScales: { number },
	-- The root motion the animator hands out each frame (options.animator), in the root's space.
	setRootMotion: (delta: Vector3) -> (),
	-- The server refuses the local action (Replication.rejected).
	reject: (action: string) -> (),
	-- The character goes and comes back (CharacterRemoving, then CharacterAdded with the same model).
	respawn: () -> (),
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
	local contactLog: any = { begins = {}, steps = {}, stops = 0, queue = {}, active = false, deps = nil }
	local rigStepCount: () -> number = function(): number
		return 0
	end
	local fakes: { [string]: any } = {
		ContactPredictor = {
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
		timeScales = timeScales,
		setRootMotion = function(delta: Vector3)
			rootMotion = delta
		end,
		reject = function(action: string)
			fakes.Replication.rejected:Fire(action)
		end,
		respawn = function()
			localPlayer.CharacterRemoving:Fire()
			localPlayer.CharacterAdded:Fire(model)
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

local function lastDodge(rig: Rig): Vector3?
	for index = #rig.sent, 1, -1 do
		local entry = rig.sent[index]
		if entry.name == "DodgeRequest" then
			local d = entry.payload.direction
			return Vector3.new(d[1], d[2], d[3])
		end
	end
	return nil
end

local FORWARD = Vector3.new(0, 0, -1) -- the root's look (CFrame.new() faces -Z)

describe("CharacterController's render step (D-139, D-211)", function()
	it("binds at choreo.luau renderOrder.character: after Choreo's rigs, before the camera and every reader", function()
		local rig = load()
		local function priorityOf(row: any): number
			return (Enum.RenderPriority :: any)[row.base].Value + row.offset
		end
		local CameraData = Harness.load("src/shared/data/camera")
		local Fx = Harness.load("src/shared/data/fx")
		expect(rig.renderStep.name).toBe("SkyspireCharacter")
		expect(rig.renderStep.priority).toBe(priorityOf(ChoreoData.renderOrder.character))
		expect(rig.renderStep.priority).toBeGreaterThan(priorityOf(ChoreoData.renderOrder.rigs))
		for _, reader in { CameraData.renderOrder.main, Fx.renderOrder.impactFrames, Fx.renderOrder.poseReaders } do
			expect(rig.renderStep.priority).toBeLessThan(priorityOf(reader))
		end
	end)
end)

describe("CharacterController dodge direction", function()
	it("with the stick held forward the dodge goes forward", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		rig.controller.dodge()
		local direction = lastDodge(rig)
		expect(direction).never.toBeNil()
		expect((direction :: Vector3).Z).toBeCloseTo(FORWARD.Z, 1e-6)
		expect((direction :: Vector3).X).toBeCloseTo(0, 1e-6)
	end)

	it("a dodge pressed during the two-step stop steps back: the stick let go", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		-- The stick lets go: the two-step stop carries the Humanoid along the last move.
		rig.frame(Vector3.zero)
		rig.frame(Vector3.zero)
		expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		rig.controller.dodge()
		local direction = lastDodge(rig)
		expect(direction).never.toBeNil()
		expect((direction :: Vector3).Z).toBeCloseTo(-FORWARD.Z, 1e-6)
		expect((direction :: Vector3).X).toBeCloseTo(0, 1e-6)
	end)

	it("after the stop has run out the Humanoid is still and the dodge steps back", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local frames = math.ceil(ChoreoData.locomotion.stopStepsSeconds / FRAME) + 2
		for _ = 1, frames do
			rig.frame(Vector3.zero)
		end
		expect(rig.humanoid.MoveDirection.Magnitude).toBe(0)
		rig.controller.dodge()
		local direction = lastDodge(rig)
		expect(direction).never.toBeNil()
		expect((direction :: Vector3).Z).toBeCloseTo(-FORWARD.Z, 1e-6)
		expect((direction :: Vector3).X).toBeCloseTo(0, 1e-6)
	end)
end)

-- Humanoid writes of `key` from write index `from` on.
local function writesOf(rig: Rig, key: string, from: number): { any }
	local values = {}
	for index = from, #rig.writes do
		local entry = rig.writes[index]
		if entry.key == key then
			table.insert(values, entry.value)
		end
	end
	return values
end

describe("CharacterController's two-step stop", function()
	it("holds the speed it had through Humanoid.WalkSpeed while the gait has not walked on", function()
		-- The fake gait's phase holds still, so the stop's next Footstep never comes: the carry holds
		-- the run speed along the last move until stopStepsSeconds. Without Locomotion.stopGait the
		-- carry would fall over stopStepsSeconds instead (about 9.3 after 30 frames).
		local rig = load({ stopGait = 0 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		for _ = 1, 30 do
			rig.frame(Vector3.zero)
		end
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.runSpeed)
		expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		expect(rig.humanoid.MoveDirection.X).toBeCloseTo(0, 1e-6)
	end)

	it("slows the Humanoid as the gait walks on to the planted foot, never under stopEndSpeed", function()
		-- 0.02 of a cycle a frame: the first carry frame keeps the run speed (16) with 0.7 of a cycle
		-- to go; on carry frame k, (0.7 - 0.02 (k - 1)) is left and the speed is 16 x that / 0.7.
		local rig = load({ stopGait = 0.02 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local run = ChoreoData.locomotion.runSpeed
		local seen: { [number]: number } = {}
		for frame = 1, 30 do
			rig.frame(Vector3.zero)
			seen[frame] = rig.humanoid.WalkSpeed
			expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		end
		expect(seen[1]).toBeCloseTo(run, 1e-6)
		expect(seen[15]).toBeCloseTo(run * (0.7 - 0.02 * 14) / 0.7, 1e-6)
		expect(seen[30]).toBeCloseTo(ChoreoData.locomotion.stopEndSpeed, 1e-6)
	end)

	it("writes WalkSpeed once a frame at most and AutoRotate only when the lock changes", function()
		-- Each write fires the Humanoid's Changed handlers, and a client WalkSpeed write replicates.
		local rig = load({ stopGait = 0.02 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		-- Walking: one WalkSpeed write and one AutoRotate write in all (the first frame).
		expect(writesOf(rig, "WalkSpeed", 1)).toEqual({ ChoreoData.locomotion.runSpeed })
		expect(writesOf(rig, "AutoRotate", 1)).toEqual({ true })
		local most, autoRotate, frames = 0, 0, 0
		repeat
			local from = #rig.writes + 1
			rig.frame(Vector3.zero)
			frames += 1
			most = math.max(most, #writesOf(rig, "WalkSpeed", from))
			autoRotate += #writesOf(rig, "AutoRotate", from)
		until rig.humanoid.MoveDirection.Magnitude == 0 or frames > 200
		expect(most).toBe(1)
		expect(autoRotate).toBe(0)
		-- The carry is over: the Humanoid has its own speed back, written once.
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.runSpeed)
		local from = #rig.writes + 1
		rig.frame(Vector3.zero)
		rig.frame(FORWARD)
		rig.frame(FORWARD)
		expect(writesOf(rig, "WalkSpeed", from)).toEqual({})
		-- A steady carry (the gait holding still) writes nothing after its first frame.
		local steady = load({ stopGait = 0 })
		for _ = 1, 10 do
			steady.frame(FORWARD)
		end
		local after = #steady.writes + 1
		for _ = 1, 30 do
			steady.frame(Vector3.zero)
		end
		expect(writesOf(steady, "WalkSpeed", after)).toEqual({})
		expect(writesOf(steady, "AutoRotate", after)).toEqual({})
		-- A locked state flips AutoRotate once each way.
		local before = #steady.writes + 1
		steady.controller.dodge()
		for _ = 1, 40 do
			steady.frame(Vector3.zero)
		end
		expect(writesOf(steady, "AutoRotate", before)).toEqual({ false, true })
	end)

	it("hands the Humanoid back its own speed once the carry ends", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local frames = math.ceil(ChoreoData.locomotion.stopStepsSeconds / FRAME) + 2
		for _ = 1, frames do
			rig.frame(Vector3.zero)
		end
		expect(rig.humanoid.MoveDirection.Magnitude).toBe(0)
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.runSpeed)
	end)
end)

-- The fake Impact's calls named `name`, in order.
local function impactCalls(rig: Rig, name: string): { { any } }
	local calls = {}
	for _, entry in rig.log do
		if entry.kind == "impact" and entry.name == name then
			table.insert(calls, entry.args)
		end
	end
	return calls
end

local function sends(rig: Rig, name: string): number
	local count = 0
	for _, entry in rig.sent do
		if entry.name == name then
			count += 1
		end
	end
	return count
end

-- The index in rig.log of the first entry of `kind` named `name`, or nil.
local function firstIndex(rig: Rig, kind: string, name: string): number?
	for index, entry in rig.log do
		if entry.kind == kind and entry.name == name then
			return index
		end
	end
	return nil
end

describe("CharacterController's impact director calls", function()
	it("a predicted guard raise sounds once, before its GuardRequest; a release or a refused raise does not", function()
		local rig = load({ impact = true })
		rig.frame(Vector3.zero)
		rig.controller.setGuard(true)
		local raises = impactCalls(rig, "guardRaise")
		expect(#raises).toBe(1)
		expect(raises[1][1]).toBe(rig.model)
		expect(raises[1][2]).toBe(true)
		local raiseAt = firstIndex(rig, "impact", "guardRaise") :: number
		local requestAt = firstIndex(rig, "send", "GuardRequest") :: number
		expect(raiseAt < requestAt).toBe(true)
		for _ = 1, 30 do
			rig.frame(Vector3.zero)
		end
		rig.controller.setGuard(false)
		expect(#impactCalls(rig, "guardRaise")).toBe(1)
		-- A raise the controller refuses (mid-dodge) predicts nothing and sounds nothing.
		for _ = 1, 30 do
			rig.frame(Vector3.zero)
		end
		rig.controller.dodge()
		rig.controller.setGuard(true)
		expect(rig.controller.state()).toBe("Dodge")
		expect(#impactCalls(rig, "guardRaise")).toBe(1)
	end)

	it("a local dodge out of the two-step stop plays one Dodge cue and sends one DodgeRequest", function()
		local rig = load({ impact = true, stopGait = 0 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		rig.frame(Vector3.zero)
		rig.frame(Vector3.zero)
		rig.controller.dodge()
		local dodges = impactCalls(rig, "dodge")
		expect(#dodges).toBe(1)
		expect(dodges[1][1]).toBe(rig.model)
		expect(dodges[1][2]).toBe(true)
		expect(sends(rig, "DodgeRequest")).toBe(1)
		-- A second press inside the cooldown does neither.
		rig.frame(Vector3.zero)
		rig.controller.dodge()
		expect(#impactCalls(rig, "dodge")).toBe(1)
		expect(sends(rig, "DodgeRequest")).toBe(1)
	end)

	it("an Art release hands the director the clip and its freeze time, once, with the ArtRequest", function()
		local Combat = Harness.load("src/shared/data/combat")
		local rig = load({ impact = true })
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		expect(rig.controller.state()).toBe("Holding")
		local held = 0
		for _ = 1, 12 do
			rig.frame(Vector3.zero)
			held += FRAME
		end
		expect(held < Combat.activationCancelTime).toBe(true)
		rig.controller.releaseArt(1, held)
		expect(rig.controller.state()).toBe("Art")
		local releases = impactCalls(rig, "release")
		expect(#releases).toBe(1)
		local art = rig.controller.slots()[1]
		expect(releases[1][1]).toBe(rig.model)
		expect(releases[1][2]).toBe(art.clip)
		-- No ActivationHold froze the clip (the stub animator fires no events): the freeze is the
		-- whole time the key was down, and the clip waits that long again.
		expect(releases[1][3]).toBeCloseTo(held, 1e-9)
		expect(releases[1][4]).toBeCloseTo(held, 1e-9)
		expect(sends(rig, "ArtRequest")).toBe(1)
		expect(#impactCalls(rig, "cancelActivation")).toBe(0)
	end)

	it("every way a hold ends without a launch cancels the activation once", function()
		-- Let go past the cancel time.
		local Combat = Harness.load("src/shared/data/combat")
		local rig = load({ impact = true })
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.releaseArt(1, Combat.activationCancelTime + 0.05)
		expect(rig.controller.state()).toBe("Idle")
		local cancels = impactCalls(rig, "cancelActivation")
		expect(#cancels).toBe(1)
		expect(cancels[1][1]).toBe(rig.model)
		expect(#impactCalls(rig, "release")).toBe(0)
		expect(sends(rig, "ArtRequest")).toBe(0)
		-- The hold timed out (InputController's cancel).
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.cancelArt(1)
		expect(#impactCalls(rig, "cancelActivation")).toBe(2)
		-- A dodge out of the hold.
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.dodge()
		expect(rig.controller.state()).toBe("Dodge")
		expect(#impactCalls(rig, "cancelActivation")).toBe(3)
		-- Nothing held: a cancel is a no-op.
		rig.controller.cancelArt(1)
		expect(#impactCalls(rig, "cancelActivation")).toBe(3)
	end)

	it("a cancelled hold fades the blade light out instead of cutting it (issue 13)", function()
		local Combat = Harness.load("src/shared/data/combat")
		local function lights(rig: Rig): { { any } }
			local calls = {}
			for _, entry in rig.log do
				if entry.kind == "trails" and entry.name == "activationLight" then
					table.insert(calls, entry.args)
				end
			end
			return calls
		end
		for _, way in { "release late", "timed out", "dodge" } do
			local rig = load({ impact = true, trails = true })
			rig.frame(Vector3.zero)
			rig.controller.beginArt(1)
			if way == "release late" then
				rig.controller.releaseArt(1, Combat.activationCancelTime + 0.05)
			elseif way == "timed out" then
				rig.controller.cancelArt(1)
			else
				rig.controller.dodge()
			end
			local calls = lights(rig)
			expect(#calls).toBe(1)
			expect(calls[1][1]).toBe(rig.model)
			expect(calls[1][2]).toBe(false)
			expect(calls[1][4]).toBe(true)
		end
		-- A launch leaves the light on: the first damage frame puts it out (Replication).
		local rig = load({ impact = true, trails = true })
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.releaseArt(1, 0.2)
		expect(#lights(rig)).toBe(0)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Aim (D-112): the body faces a held lock; a swing snaps the rest by at most aim.snapDegrees
-- ------------------------------------------------------------------------------------------

local Combat = Harness.load("src/shared/data/combat")
local AIM = Combat.aim
local ACCEPTANCE = math.deg(math.acos(1 - Combat.facingTolerance)) -- 49.46

-- The root's yaw (degrees, + = left of -Z).
local function yawOf(rig: Rig): number
	local look = rig.root.CFrame.LookVector
	return AimLogic.yawOf(look.X, look.Z)
end

-- A point `distance` studs from the root at `bearing` degrees (+ = left) from its look.
local function pointAt(rig: Rig, bearing: number, distance: number): Vector3
	local direction = CFrame.Angles(0, math.rad(yawOf(rig) + bearing), 0).LookVector
	return rig.root.Position + direction * distance
end

-- Degrees (+ = left) from the root's look to a point.
local function bearingOf(rig: Rig, point: Vector3): number
	local look = rig.root.CFrame.LookVector
	local offset = point - rig.root.Position
	return AimLogic.bearing(look.X, look.Z, offset.X, offset.Z)
end

-- The facing of the last request named `name`, as a yaw.
local function sentYaw(rig: Rig, name: string): number?
	for index = #rig.sent, 1, -1 do
		local entry = rig.sent[index]
		if entry.name == name then
			local f = entry.payload.facing
			return AimLogic.yawOf(f[1], f[3])
		end
	end
	return nil
end

local function wrapped(degrees: number): number
	return (degrees + 180) % 360 - 180
end

local STILL = Vector3.zero

-- Frames enough for a snap's whip (aim.snapTurnSeconds) to finish showing on the body.
local function settle(rig: Rig)
	for _ = 1, math.ceil(AIM.snapTurnSeconds / FRAME) + 1 do
		rig.frame(STILL)
	end
end

describe("CharacterController aim: the body faces a held lock (D-112)", function()
	it("a body walked away from the target turns back to it at lockTurnRate once it is locked", function()
		local rig = load()
		-- Backing off with S: AutoRotate turns the body to the stick, away from where it looked.
		for _ = 1, 10 do
			rig.frame(Vector3.new(0, 0, 1))
		end
		local frames = math.ceil(ChoreoData.locomotion.stopStepsSeconds / FRAME) + 2
		for _ = 1, frames do
			rig.frame(STILL)
		end
		expect(math.abs(wrapped(yawOf(rig)))).toBeCloseTo(180, 1e-6)
		local boar = pointAt(rig, 165, 5) -- the Play-test's 165 degrees
		rig.setLock(boar)
		local before = #rig.writes + 1
		local turned = 0
		local previous = yawOf(rig)
		for _ = 1, 30 do
			rig.frame(STILL)
			local now = yawOf(rig)
			local step = math.abs(wrapped(now - previous))
			-- CFrames hold single-precision floats: 1e-4 of slack.
			expect(step <= AIM.lockTurnRate * FRAME + 1e-4).toBe(true)
			if step > 1e-4 then
				turned += 1
			end
			previous = now
		end
		-- 165 degrees at 12 a frame: 14 frames, then it holds on the target.
		expect(turned).toBe(14)
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-4)
		-- AutoRotate went off once, on the first locked frame, and was not written again.
		expect(writesOf(rig, "AutoRotate", before)).toEqual({ false })
		-- The turn is the body's own: Locomotion hears no stick angle to turn in place on.
		expect(rig.locomotionInput().turning).toBe(0)
		-- Unlocked, AutoRotate comes back once.
		rig.setLock(nil)
		local after = #rig.writes + 1
		rig.frame(STILL)
		rig.frame(STILL)
		expect(writesOf(rig, "AutoRotate", after)).toEqual({ true })
	end)

	it("strafes around the lock at walk speed, still facing it", function()
		local rig = load()
		rig.frame(STILL)
		local boar = pointAt(rig, 0, 6)
		rig.setLock(boar)
		for _ = 1, 30 do
			rig.frame(Vector3.new(1, 0, 0))
			expect(math.abs(bearingOf(rig, boar)) < 3).toBe(true)
			expect(rig.humanoid.AutoRotate).toBe(false)
			expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.walkSpeed)
			expect(rig.locomotionInput().turning).toBe(0)
		end
		-- The strafe moved the body sideways; the walk set shows it (D-054).
		expect(rig.humanoid.MoveDirection.X).toBeCloseTo(1, 1e-6)
	end)

	it("sprinting hands the facing back to the stick; letting go of sprint faces the lock again", function()
		local rig = load()
		rig.frame(STILL)
		local boar = pointAt(rig, 0, 8)
		rig.setLock(boar)
		rig.frame(STILL)
		expect(rig.humanoid.AutoRotate).toBe(false)
		rig.controller.setSprinting(true)
		-- Sprint held while standing still is not a sprint: the body keeps facing the lock.
		rig.frame(STILL)
		expect(rig.humanoid.AutoRotate).toBe(false)
		for _ = 1, 10 do
			rig.frame(Vector3.new(1, 0, 0))
		end
		expect(rig.humanoid.AutoRotate).toBe(true)
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.sprintSpeed)
		expect(math.abs(bearingOf(rig, boar)) > 45).toBe(true) -- the body follows the stick
		rig.controller.setSprinting(false)
		for _ = 1, 15 do
			rig.frame(Vector3.new(1, 0, 0))
		end
		expect(rig.humanoid.AutoRotate).toBe(false)
		expect(math.abs(bearingOf(rig, boar)) < 3).toBe(true)
	end)

	it("a raised guard and the held Art stance turn to the lock; a dodge or a swing does not", function()
		local rig = load()
		rig.frame(STILL)
		rig.setLock(pointAt(rig, 90, 5))
		rig.controller.setGuard(true)
		for _ = 1, 10 do
			rig.frame(STILL)
		end
		expect(rig.controller.state()).toBe("Guard")
		-- The server's guard cone follows the replicated root, so the guard now covers the target.
		expect(math.abs(yawOf(rig) - 90) < 1e-4).toBe(true)
		rig.controller.setGuard(false)

		local held = load()
		held.frame(STILL)
		held.controller.beginArt(1)
		expect(held.controller.state()).toBe("Holding")
		held.setLock(pointAt(held, -60, 5))
		for _ = 1, 10 do
			held.frame(STILL)
		end
		expect(math.abs(yawOf(held) + 60) < 1e-4).toBe(true)

		local dodging = load()
		for _ = 1, 40 do
			dodging.frame(STILL)
		end
		dodging.setLock(pointAt(dodging, 120, 5))
		dodging.controller.dodge()
		local start = yawOf(dodging)
		for _ = 1, 5 do
			dodging.frame(STILL)
		end
		expect(dodging.controller.state()).toBe("Dodge")
		expect(yawOf(dodging)).toBeCloseTo(start, 1e-9)
	end)
end)

describe("CharacterController aim: a swing turns the rest of the way, at most aim.snapDegrees (D-112)", function()
	-- A rig that has stood still long enough for its basic swing to be ready and the lag window to
	-- hold one yaw.
	local function standing(): Rig
		local rig = load()
		for _ = 1, 30 do
			rig.frame(STILL)
		end
		return rig
	end

	it("a basic swing with the lock 30 degrees off faces the target and sends that facing", function()
		local rig = standing()
		local boar = pointAt(rig, 30, 5)
		rig.setLock(boar) -- no frame in between: the body has not turned yet
		rig.controller.basicAttack()
		expect(rig.controller.state()).toBe("Basic")
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(30, 1e-4)
		settle(rig)
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-4)
	end)

	it("with the lock 120 degrees off the swing turns 40 and no more", function()
		local rig = standing()
		rig.setLock(pointAt(rig, 120, 5))
		rig.controller.basicAttack()
		settle(rig)
		expect(yawOf(rig)).toBeCloseTo(AIM.snapDegrees, 1e-4)
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(AIM.snapDegrees, 1e-4)
		local right = standing()
		right.setLock(pointAt(right, -165, 5))
		right.controller.basicAttack()
		expect(sentYaw(right, "BasicAttackRequest")).toBeCloseTo(-AIM.snapDegrees, 1e-4)
	end)

	it(
		"mid-turn, the swing turns only as far as the server can still accept from where it last saw the body",
		function()
			local rig = standing()
			rig.setLock(pointAt(rig, 120, 5))
			for _ = 1, 3 do
				rig.frame(STILL) -- the lock turn: 36 degrees inside the lag window
			end
			expect(yawOf(rig)).toBeCloseTo(36, 1e-4)
			rig.controller.basicAttack()
			-- 13 more: the facing sits snap + margin (49) from the yaw the window began with, inside 49.46.
			local facing = sentYaw(rig, "BasicAttackRequest") :: number
			expect(facing).toBeCloseTo(AIM.snapDegrees + AIM.replicationMarginDegrees, 1e-4)
			expect(facing <= ACCEPTANCE).toBe(true)
		end
	)

	it("a swing deep in the lock's acquisition turn faces back just enough for the server to accept it", function()
		local rig = standing()
		rig.setLock(pointAt(rig, 165, 5))
		for _ = 1, 7 do
			rig.frame(STILL) -- 84 degrees round in 7 frames, all inside the lag window
		end
		expect(yawOf(rig)).toBeCloseTo(84, 1e-4)
		rig.controller.basicAttack()
		-- No snap: the body already left the server's acceptance of where the window began.
		expect(yawOf(rig)).toBeCloseTo(84, 1e-4)
		-- The request faces 49 from that yaw, not 84: it comes out instead of being refused.
		local facing = sentYaw(rig, "BasicAttackRequest") :: number
		expect(facing).toBeCloseTo(AIM.snapDegrees + AIM.replicationMarginDegrees, 1e-4)
		expect(facing <= ACCEPTANCE).toBe(true)
		-- Once the turn has settled for a lag window, the request faces where the body does.
		local settled = standing()
		settled.setLock(pointAt(settled, 165, 5))
		for _ = 1, 30 do
			settled.frame(STILL)
		end
		settled.controller.basicAttack()
		expect(sentYaw(settled, "BasicAttackRequest")).toBeCloseTo(yawOf(settled), 1e-4)
		expect(math.abs(wrapped(yawOf(settled) - 165)) < 1e-3).toBe(true)
	end)

	it("an Art release snaps the same way and its ArtRequest carries the facing", function()
		local rig = standing()
		rig.controller.beginArt(1)
		for _ = 1, 12 do
			rig.frame(STILL)
		end
		local boar = pointAt(rig, -25, 5)
		rig.setLock(boar)
		rig.controller.releaseArt(1, 12 * FRAME)
		expect(rig.controller.state()).toBe("Art")
		expect(sentYaw(rig, "ArtRequest")).toBeCloseTo(-25, 1e-4)
		settle(rig)
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-4)
	end)

	it("with no lock the soft assist aims at the best enemy in the cone, by at most the snap", function()
		local rig = standing()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 30, 5) } })
		rig.controller.basicAttack()
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(30, 1e-4)

		-- Behind the cone (the Play-test's 165): no unanimated half turn; F is for that.
		local behind = standing()
		behind.setEnemies({ { id = 4, position = pointAt(behind, 165, 5) } })
		behind.controller.basicAttack()
		expect(sentYaw(behind, "BasicAttackRequest")).toBeCloseTo(0, 1e-9)
		expect(yawOf(behind)).toBeCloseTo(0, 1e-9)

		-- Past the assist range: nothing to aim at.
		local far = standing()
		far.setEnemies({ { id = 4, position = pointAt(far, 30, AIM.assistRange + 1) } })
		far.controller.basicAttack()
		expect(sentYaw(far, "BasicAttackRequest")).toBeCloseTo(0, 1e-9)

		-- The nearer of two, angle priced in: 5 studs at 40 beats 9 studs at 10.
		local two = standing()
		two.setEnemies({
			{ id = 1, position = pointAt(two, -10, 9) },
			{ id = 2, position = pointAt(two, 40, 5) },
		})
		two.controller.basicAttack()
		expect(sentYaw(two, "BasicAttackRequest")).toBeCloseTo(40, 1e-4)
	end)

	it(
		"with the display asleep, a turn made on Heartbeat that has settled for a lag window sends the body's own look",
		function()
			-- Studio with its display asleep runs Heartbeat 60 times a second and RenderStepped never
			-- (measured 2026-10-23), so the render step records no yaw. The dev aim hook's "face" turns
			-- the root on Heartbeat at the lock turn's rate, waits, then swings: the server has long seen
			-- that root, so the request must face where the body does.
			local rig = standing()
			local turned = 0
			while turned < 150 do
				local step = math.min(AIM.lockTurnRate * FRAME, 150 - turned)
				local frame = rig.root.CFrame
				rig.root.CFrame = CFrame.new(frame.Position) * CFrame.Angles(0, math.rad(step), 0) * frame.Rotation
				turned += step
				rig.heartbeat()
			end
			for _ = 1, math.ceil(2 * Combat.lagAllowance / FRAME) do
				rig.heartbeat()
			end
			expect(yawOf(rig)).toBeCloseTo(150, 1e-3)
			rig.controller.basicAttack()
			expect(rig.controller.state()).toBe("Basic")
			expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(150, 1e-3)
		end
	)

	it("a held lock wins over the assist", function()
		local rig = standing()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 30, 4) } })
		rig.setLock(pointAt(rig, -20, 6))
		rig.controller.basicAttack()
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(-20, 1e-4)
	end)

	it("a swing at a rushing lock faces the body it is drawn as, not the hidden root it trails (D-193)", function()
		local rig = standing()
		-- The root part lags the drawn body by most of a rush's quarter second.
		local drawn = pointAt(rig, 20, 5)
		rig.setLockDrawn(pointAt(rig, -25, 8), drawn)
		rig.controller.basicAttack()
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(20, 1e-4)
		-- The body comes round to the drawn body and stays on it.
		settle(rig)
		expect(bearingOf(rig, drawn)).toBeCloseTo(0, 1e-3)
		rig.setLock(nil)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The snap's whip (item 102): the request faces the whole snap at once; the body shows it over
-- aim.snapTurnSeconds on aim.snapTurnEasing instead of in one frame
-- ------------------------------------------------------------------------------------------

local Easing = Harness.load("src/shared/util/Easing")

-- Frames in which a whip of aim.snapTurnSeconds turns the body, `scale` the capture's time scale.
local function whipFrames(scale: number): number
	return math.ceil(AIM.snapTurnSeconds / scale / FRAME - 1e-9)
end

describe("CharacterController aim: the snap shows as a whip, not a pop (item 102)", function()
	local function standing(options: Options?): Rig
		local rig = load(options)
		for _ = 1, 30 do
			rig.frame(STILL)
		end
		return rig
	end

	-- Runs frames until the whip is over; returns the yaw step of every frame.
	local function whip(rig: Rig, frames: number): { number }
		local steps = {}
		local previous = yawOf(rig)
		for _ = 1, frames do
			rig.frame(STILL)
			local now = yawOf(rig)
			table.insert(steps, wrapped(now - previous))
			previous = now
		end
		return steps
	end

	it("sends the whole snap at once; the body whips round over a few frames, never most of it in one", function()
		-- The Studio case: unlocked, the boar 35 degrees off at 4 studs, one basic swing.
		local rig = standing()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 35, 4) } })
		rig.controller.basicAttack()
		expect(rig.controller.state()).toBe("Basic")
		-- The server sweeps where the request faces (D-113): the whole snap, now.
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(35, 1e-4)
		-- The body shows none of it before the next frame...
		expect(yawOf(rig)).toBeCloseTo(0, 1e-4)
		local steps = whip(rig, whipFrames(1) + 3)
		-- ...then turns on every frame of the whip, never back, and holds once it is over.
		local turning, biggest = 0, 0
		for index, step in steps do
			expect(step >= -1e-4).toBe(true)
			if step > 1e-4 then
				turning += 1
				expect(index <= whipFrames(1)).toBe(true)
			end
			biggest = math.max(biggest, step)
		end
		expect(turning).toBe(whipFrames(1))
		expect(turning >= 3).toBe(true)
		expect(biggest < 35 / 2).toBe(true)
		-- The first frame shows the curve one frame in.
		expect(steps[1]).toBeCloseTo(35 * Easing.evaluate(AIM.snapTurnEasing, FRAME / AIM.snapTurnSeconds), 1e-3)
		expect(yawOf(rig)).toBeCloseTo(35, 1e-3)
	end)

	it("with the display asleep the whip still ends on time, on Heartbeat", function()
		-- Studio with its display asleep: Heartbeat 60 a second, RenderStepped never (D-117).
		local rig = standing()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 35, 4) } })
		rig.controller.basicAttack()
		for _ = 1, whipFrames(1) do
			rig.heartbeat()
		end
		expect(yawOf(rig)).toBeCloseTo(35, 1e-3)
	end)

	it("the clip's root motion carries the body along the facing the request carried, mid-whip too", function()
		local rig = standing({ animator = true })
		rig.setEnemies({ { id = 4, position = pointAt(rig, 35, 4) } })
		local start = rig.root.Position
		rig.controller.basicAttack()
		rig.setRootMotion(Vector3.new(0, 0, -0.1)) -- a tenth of a stud forward a frame
		whip(rig, whipFrames(1))
		local moved = rig.root.Position - start
		expect(moved.Magnitude).toBeCloseTo(0.1 * whipFrames(1), 1e-3)
		expect(AimLogic.yawOf(moved.X, moved.Z)).toBeCloseTo(35, 1e-3)
	end)

	it("a request mid-whip faces from where the last one left the body, and the whip carries on", function()
		local rig = standing()
		local boar = pointAt(rig, 35, 5)
		rig.setLock(boar)
		rig.controller.basicAttack()
		rig.frame(STILL)
		local first = yawOf(rig)
		expect(first > 1 and first < 35 / 2).toBe(true)
		-- An Art may start from a basic swing: its stance waits for the whip, not the lock turn.
		rig.controller.beginArt(1)
		expect(rig.controller.state()).toBe("Holding")
		rig.frame(STILL)
		local before = yawOf(rig)
		rig.controller.releaseArt(1, FRAME)
		expect(sentYaw(rig, "ArtRequest")).toBeCloseTo(35, 1e-3)
		-- No pop at the release: the rest of the turn keeps whipping.
		expect(yawOf(rig)).toBeCloseTo(before, 1e-4)
		local steps = whip(rig, whipFrames(1) + 3)
		for _, step in steps do
			expect(step >= -1e-4 and step <= first + 1e-3).toBe(true)
		end
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-3)
	end)

	it("a swing refused mid-whip ends on the lock without overshooting it", function()
		local rig = standing()
		local boar = pointAt(rig, 35, 5)
		rig.setLock(boar)
		rig.controller.basicAttack()
		rig.frame(STILL)
		rig.reject("BasicAttack")
		expect(rig.controller.state()).toBe("Idle")
		local most = yawOf(rig)
		for _ = 1, 20 do
			rig.frame(STILL)
			most = math.max(most, yawOf(rig))
		end
		expect(most <= 35 + 1e-3).toBe(true)
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-3)
	end)

	it("a dodge mid-whip steps relative to the facing the swing carried", function()
		local rig = standing()
		rig.setLock(pointAt(rig, 35, 5))
		rig.controller.basicAttack()
		rig.frame(STILL)
		rig.controller.dodge() -- no stick: back
		local direction = lastDodge(rig) :: Vector3
		expect(direction).never.toBeNil()
		expect(AimLogic.yawOf(-direction.X, -direction.Z)).toBeCloseTo(35, 1e-3)
	end)

	it("a respawn mid-whip drops the rest of the turn", function()
		local rig = standing()
		rig.setLock(pointAt(rig, 35, 5))
		rig.controller.basicAttack()
		rig.frame(STILL)
		local shown = yawOf(rig)
		rig.setLock(nil)
		rig.respawn()
		for _ = 1, whipFrames(1) + 3 do
			rig.frame(STILL)
		end
		expect(yawOf(rig)).toBeCloseTo(shown, 1e-4)
	end)

	it("hands DevAim the facing the last request carried", function()
		local rig = standing()
		expect(rig.controller.lastFacing()).toBeNil()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 35, 4) } })
		rig.controller.basicAttack()
		local facing = rig.controller.lastFacing()
		expect(facing).never.toBeNil()
		expect(AimLogic.yawOf(facing[1], facing[3])).toBeCloseTo(35, 1e-4)
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(35, 1e-4)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Capture slow motion (dev.luau timeScale): the local body moves on the capture's clock
-- ------------------------------------------------------------------------------------------

describe("CharacterController in a slowed capture", function()
	local RUN = ChoreoData.locomotion.runSpeed

	local function last(list: { number }): number?
		return list[#list]
	end

	it("walks the body at the capture's scale, so the slowed walk's feet keep their ground", function()
		local rig = load({ capture = true })
		rig.frame(STILL)
		expect(rig.controller.setCaptureTimeScale(0.25)).toBe(true)
		local start = rig.root.Position
		for _ = 1, 30 do
			rig.frame(FORWARD)
			expect(rig.humanoid.WalkSpeed).toBeCloseTo(RUN * 0.25, 1e-9)
		end
		expect((rig.root.Position - start).Magnitude).toBeCloseTo(30 * FRAME * RUN * 0.25, 1e-6)
		-- Locomotion hears the root's own speed: it paces the slowed clips from it (their clock
		-- runs at the same scale), so the walk plants its feet.
		expect(rig.locomotionInput().speed).toBeCloseTo(RUN * 0.25, 1e-6)
		-- ... and the clock it moves on, so the blend reads that speed at 1x: the run, not a walk.
		expect(rig.locomotionInput().clockScale).toBe(0.25)
		expect(rig.controller.setCaptureTimeScale(1)).toBe(true)
		rig.frame(FORWARD)
		expect(rig.humanoid.WalkSpeed).toBe(RUN)
		expect(rig.locomotionInput().clockScale).toBe(1)
	end)

	it("hands locomotion the root's own velocity, the reading its speed came from (D-144)", function()
		local rig = load()
		rig.frame(STILL)
		for _ = 1, 5 do
			rig.frame(FORWARD)
		end
		local input = rig.locomotionInput()
		local velocity = rig.root.AssemblyLinearVelocity
		expect(typeof(input.velocity)).toBe("Vector3")
		expect((input.velocity - velocity).Magnitude).toBeCloseTo(0, 1e-9)
		expect(Vector3.new(input.velocity.X, 0, input.velocity.Z).Magnitude).toBeCloseTo(input.speed, 1e-9)
		expect(input.verticalVelocity).toBe(input.velocity.Y)
	end)

	it("outside a capture place, or at a scale the capture does not offer, nothing slows", function()
		local live = load()
		live.frame(STILL)
		expect(live.controller.setCaptureTimeScale(0.25)).toBe(false)
		for _ = 1, 5 do
			live.frame(FORWARD)
		end
		expect(live.humanoid.WalkSpeed).toBe(RUN)
		local capture = load({ capture = true })
		capture.frame(STILL)
		for _, bad in { 0.3, 2, 0, -1, 0 / 0 } do
			expect(capture.controller.setCaptureTimeScale(bad)).toBe(false)
		end
		for _ = 1, 5 do
			capture.frame(FORWARD)
		end
		expect(capture.humanoid.WalkSpeed).toBe(RUN)
	end)

	it("a capture place played live (the published Playground, not Studio) never slows the body", function()
		-- STUDIO_TASKS 19 publishes places/Playground.rbxl, whose Workspace carries DevCapture, as
		-- the start place: Capture.client runs there too, but the body is a dev-only path.
		local live = load({ capture = true, studio = false, animator = true })
		live.frame(STILL)
		local scales = #live.timeScales
		expect(live.controller.setCaptureTimeScale(0.25)).toBe(false)
		for _ = 1, 5 do
			live.frame(FORWARD)
		end
		expect(live.humanoid.WalkSpeed).toBe(RUN)
		-- Refused, it leaves the animator alone too (Capture.client then slows the clips itself).
		expect(#live.timeScales).toBe(scales)
	end)

	it("turns to the lock and whips a snap on the capture's clock; the request still faces at once", function()
		local rig = load({ capture = true })
		for _ = 1, 30 do
			rig.frame(STILL)
		end
		expect(rig.controller.setCaptureTimeScale(0.25)).toBe(true)
		rig.setLock(pointAt(rig, 120, 5))
		rig.frame(STILL)
		expect(yawOf(rig)).toBeCloseTo(AIM.lockTurnRate * FRAME * 0.25, 1e-4)

		local swing = load({ capture = true })
		for _ = 1, 30 do
			swing.frame(STILL)
		end
		swing.controller.setCaptureTimeScale(0.25)
		swing.setEnemies({ { id = 4, position = pointAt(swing, 35, 4) } })
		swing.controller.basicAttack()
		expect(sentYaw(swing, "BasicAttackRequest")).toBeCloseTo(35, 1e-4)
		local turning = 0
		local previous = yawOf(swing)
		for _ = 1, whipFrames(0.25) + 3 do
			swing.frame(STILL)
			if yawOf(swing) - previous > 1e-4 then
				turning += 1
			end
			previous = yawOf(swing)
		end
		expect(turning).toBe(whipFrames(0.25))
		expect(yawOf(swing)).toBeCloseTo(35, 1e-3)
	end)

	it("runs the two-step stop on the capture's clock, never faster than the slowed body", function()
		local function carry(scale: number): (number, number)
			local rig = load({ capture = true })
			rig.frame(STILL)
			rig.controller.setCaptureTimeScale(scale)
			for _ = 1, 20 do
				rig.frame(FORWARD)
			end
			local frames, fastest = 0, 0
			for _ = 1, 400 do
				rig.frame(STILL)
				if rig.humanoid.MoveDirection.Magnitude > 0 then
					frames += 1
					fastest = math.max(fastest, rig.humanoid.WalkSpeed)
				end
			end
			return frames, fastest
		end
		local full, fullFastest = carry(1)
		local slow, slowFastest = carry(0.25)
		expect(full > 0).toBe(true)
		expect(fullFastest <= RUN + 1e-9).toBe(true)
		expect(slow >= 4 * full - 4).toBe(true)
		expect(slow <= 4 * full + 4).toBe(true)
		expect(slowFastest <= RUN * 0.25 + 1e-9).toBe(true)
	end)

	it("keeps a frozen Art stance frozen, and a hold let go returns to the capture's scale", function()
		local rig = load({ capture = true, animator = true })
		rig.frame(STILL)
		expect(rig.controller.setCaptureTimeScale(0.25)).toBe(true)
		expect(last(rig.timeScales)).toBe(0.25)
		rig.controller.beginArt(1)
		rig.controller.freezeHold()
		expect(last(rig.timeScales)).toBe(0)
		-- The capture panel cycles (or re-applies) the scale while the stance glows.
		rig.controller.setCaptureTimeScale(0.5)
		expect(last(rig.timeScales)).toBe(0)
		rig.controller.cancelArt(1)
		expect(last(rig.timeScales)).toBe(0.5)
		-- A respawned body comes back on the capture's clock.
		rig.respawn()
		expect(last(rig.timeScales)).toBe(0.5)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The Art hold across a render stall (D-132), and the order of the rig's step and the root read
-- (a real Choreo animating a real rig on the spec's clock)
-- ------------------------------------------------------------------------------------------

local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")

type ClipEventRow = { clipId: string, kind: string, jumped: boolean, at: number }

-- The clip time of a clip's first ActivationHold (its glowing hold pose), read from the data.
local function holdTimeOf(clipId: string): number
	local hold = math.huge
	for _, event in ClipLibrary.get(clipId).events do
		if event.kind == "ActivationHold" then
			hold = math.min(hold, event.time)
		end
	end
	return hold
end

-- The rig's clip events of one clip (any clip when nil), from row `from` on.
local function clipEventsOf(rig: Rig, clipId: string?, from: number?): { ClipEventRow }
	local rows = {}
	for index = from or 1, #rig.clipEvents do
		local row = rig.clipEvents[index]
		if clipId == nil or row.clipId == clipId then
			table.insert(rows, row)
		end
	end
	return rows
end

-- A rig that has stood still long enough for every send to be ready.
local function standingRig(options: Options): Rig
	local rig = load(options)
	for _ = 1, 40 do
		rig.frame(STILL)
	end
	return rig
end

-- Lets the held Art go `heldExtra` frames later and follows it: the director hears the clip time
-- it waits at (`frozen`) and waits that long, the clip holds still until then, and from then on
-- it runs on the server's clock (which starts the clip at the release, ActionLogic.syncPlan).
local function releaseInStep(rig: Rig, art: any, handle: any, pressedAt: number, frozen: number)
	for _ = 1, 6 do
		rig.frame(STILL)
	end
	local waiting = handle.time
	local releasedAt = rig.now()
	rig.controller.releaseArt(1, releasedAt - pressedAt)
	local releases = impactCalls(rig, "release")
	expect(#releases).toBe(1)
	expect(releases[1][2]).toBe(art.clip)
	expect(releases[1][3]).toBe(frozen)
	expect(releases[1][4]).toBe(frozen)
	expect(sends(rig, "ArtRequest")).toBe(1)
	local resumedAt: number? = nil
	for _ = 1, 40 do
		rig.frame(STILL)
		if resumedAt == nil then
			if rig.timeScales[#rig.timeScales] ~= 0 then
				resumedAt = rig.now()
			else
				expect(handle.time).toBe(waiting)
			end
		else
			-- The server's clip started at the release: the local one is within a frame of it.
			expect(math.abs(handle.time - (rig.now() - releasedAt)) <= FRAME + 1e-9).toBe(true)
		end
	end
	expect(resumedAt).never.toBeNil()
	expect((resumedAt :: number) >= releasedAt + frozen - 1e-9).toBe(true)
	expect((resumedAt :: number) < releasedAt + frozen + FRAME).toBe(true)
end

describe("CharacterController's Art hold across a render stall (D-132)", function()
	it("display awake: the hold freezes on the frame its clip crosses its ActivationHold", function()
		-- The guard on the normal hold: the freeze, the clip time it waits at, the director's
		-- release and the resume are what they were before the stall fixes, to the bit.
		local rig = standingRig({ choreo = true, impact = true })
		local art = rig.controller.slots()[1]
		local hold = holdTimeOf(art.clip)
		local pressedAt = rig.now()
		rig.controller.beginArt(1)
		local handle = rig.animator.mixer:find(art.clip)
		local frozenAt: number? = nil
		for _ = 1, 60 do
			rig.frame(STILL)
			if rig.timeScales[#rig.timeScales] == 0 then
				frozenAt = rig.now()
				break
			end
		end
		expect(frozenAt).never.toBeNil()
		local holds = clipEventsOf(rig, art.clip)
		expect(#holds).toBe(1)
		expect(holds[1].kind).toBe("ActivationHold")
		expect(holds[1].jumped).toBe(false)
		expect(holds[1].at).toBe(frozenAt)
		-- Frozen where its own steps took it: the first frame at or past the hold.
		local clipAtFreeze = handle.time
		expect(clipAtFreeze >= hold).toBe(true)
		expect(clipAtFreeze < hold + FRAME).toBe(true)
		releaseInStep(rig, art, handle, pressedAt, (frozenAt :: number) - pressedAt)
		expect(clipEventsOf(rig, art.clip)[1].kind).toBe("ActivationHold")
		expect(#clipEventsOf(rig, art.clip, nil) > 1).toBe(true)
	end)

	it("a slowed capture still freezes the stance where its slowed clip has got to at the section 6 time", function()
		-- Dev slow motion (D-111): the clip runs at 0.25x while the fallback waits real seconds. The
		-- rig steps every frame, so this is no stall: nothing moves the clip on to its hold.
		local rig = load({ choreo = true, capture = true })
		rig.frame(STILL)
		expect(rig.controller.setCaptureTimeScale(0.25)).toBe(true)
		for _ = 1, 40 do
			rig.frame(STILL)
		end
		local art = rig.controller.slots()[1]
		rig.controller.beginArt(1)
		local handle = rig.animator.mixer:find(art.clip)
		local frames = 0
		repeat
			rig.frame(STILL)
			frames += 1
		until rig.timeScales[#rig.timeScales] == 0 or frames > 60
		local Combat = Harness.load("src/shared/data/combat")
		expect(frames).toBe(math.ceil((Combat.startPoseTime + Combat.activationHold) / FRAME - 1e-9))
		expect(handle.time).toBeCloseTo(frames * FRAME * 0.25, 1e-9)
		expect(handle.time < holdTimeOf(art.clip)).toBe(true)
		expect(#clipEventsOf(rig, art.clip)).toBe(0)
	end)

	it("an Art pressed while the display sleeps and held at the wake shows its glowing hold pose", function()
		local rig = standingRig({ choreo = true, impact = true })
		local art = rig.controller.slots()[1]
		local hold = holdTimeOf(art.clip)
		for _ = 1, 60 do
			rig.heartbeat() -- the display sleeps: Heartbeat and the timers run, no render step
		end
		local pressedAt = rig.now()
		rig.controller.beginArt(1)
		local handle = rig.animator.mixer:find(art.clip)
		for _ = 1, 30 do
			rig.heartbeat() -- held on in the dark, past the section 6 fallback's freeze
		end
		rig.wake()
		-- The hold pose, and its activation fired as it does on a hold the display saw: unmarked,
		-- so the light glows (Replication starts nothing for a jumped one).
		expect(handle.time).toBeCloseTo(hold, 1e-9)
		local events = clipEventsOf(rig, art.clip)
		expect(#events).toBe(1)
		expect(events[1].kind).toBe("ActivationHold")
		expect(events[1].jumped).toBe(false)
		expect(rig.controller.state()).toBe("Holding")
		-- Launched on a normal hold's timing: frozen at the hold, it waits that long after the release.
		releaseInStep(rig, art, handle, pressedAt, hold)
	end)

	for _, frames in { 18, 36 } do
		it(("pressed before a %d-frame display sleep, held through: hold pose at the wake"):format(frames), function()
			-- 18: a stall shorter than stall.jumpSeconds (the wake is no jump); 36: a jump. The hold
			-- is let go well inside the cancel time either way.
			local rig = standingRig({ choreo = true, impact = true })
			local art = rig.controller.slots()[1]
			local hold = holdTimeOf(art.clip)
			local pressedAt = rig.now()
			rig.controller.beginArt(1)
			local handle = rig.animator.mixer:find(art.clip)
			for _ = 1, 5 do
				rig.frame(STILL)
			end
			expect(handle.time < hold).toBe(true) -- still moving into the stance
			for _ = 1, frames do
				rig.heartbeat()
			end
			rig.wake()
			expect(handle.time).toBeCloseTo(hold, 1e-9)
			local events = clipEventsOf(rig, art.clip)
			expect(#events).toBe(1)
			expect(events[1].kind).toBe("ActivationHold")
			expect(events[1].jumped).toBe(false)
			releaseInStep(rig, art, handle, pressedAt, hold)
		end)
	end

	it("an engine hitch (no timers either): the wake's jump stops the held clip at its hold", function()
		-- The jump comes before task.delay resumes, so the fallback cannot freeze it first; a jump
		-- that carried the clip past its hold would leave the stance mid-swing or ended.
		local rig = standingRig({ choreo = true, impact = true })
		local art = rig.controller.slots()[1]
		local hold = holdTimeOf(art.clip)
		local pressedAt = rig.now()
		rig.controller.beginArt(1)
		local handle = rig.animator.mixer:find(art.clip)
		for _ = 1, 5 do
			rig.frame(STILL)
		end
		rig.hitch(0.6)
		rig.wake()
		expect(handle.time).toBeCloseTo(hold, 1e-9)
		local events = clipEventsOf(rig, art.clip)
		expect(#events).toBe(1)
		expect(events[1].kind).toBe("ActivationHold")
		expect(events[1].jumped).toBe(false)
		expect(rig.controller.state()).toBe("Holding")
		releaseInStep(rig, art, handle, pressedAt, hold)
	end)

	for _, seconds in { 0.2, 0.3, 0.45 } do
		it(
			("a %.2f s engine hitch (shorter than a jump): the wake stops the held clip at its hold"):format(seconds),
			function()
				-- The wake's step is no jump, so the clip would take the whole gap and its events would
				-- start for real: frozen mid-swing with its trail and smear lit. It waits at its hold pose.
				local rig = standingRig({ choreo = true, impact = true })
				local art = rig.controller.slots()[1]
				local hold = holdTimeOf(art.clip)
				local pressedAt = rig.now()
				rig.controller.beginArt(1)
				local handle = rig.animator.mixer:find(art.clip)
				for _ = 1, 5 do
					rig.frame(STILL)
				end
				rig.hitch(seconds)
				rig.wake()
				expect(rig.now() - pressedAt < ChoreoData.stall.jumpSeconds + 5 * FRAME).toBe(true)
				expect(handle.time).toBeCloseTo(hold, 1e-9)
				local events = clipEventsOf(rig, art.clip)
				expect(#events).toBe(1)
				expect(events[1].kind).toBe("ActivationHold")
				expect(events[1].jumped).toBe(false)
				expect(rig.controller.state()).toBe("Holding")
				releaseInStep(rig, art, handle, pressedAt, hold)
			end
		)
	end

	-- One rendered frame `dt` long (a low frame rate): the render step's dt is the whole frame.
	local function longFrame(rig: Rig, dt: number)
		rig.hitch(dt - FRAME)
		rig.wake()
	end

	for _, fps in { 30, 20, 10 } do
		it(("at %d fps the hold freezes where its own steps took it, as it always has"):format(fps), function()
			-- The guard on a slow but steady frame rate: a step that keeps the clip inside its
			-- activation hold (combat.luau activationHold after the hold pose) moves nothing on.
			local rig = standingRig({ choreo = true, impact = true })
			local art = rig.controller.slots()[1]
			local hold = holdTimeOf(art.clip)
			local pressedAt = rig.now()
			rig.controller.beginArt(1)
			local handle = rig.animator.mixer:find(art.clip)
			local frozenAt: number? = nil
			for _ = 1, 20 do
				longFrame(rig, 1 / fps)
				if rig.timeScales[#rig.timeScales] == 0 then
					frozenAt = rig.now()
					break
				end
			end
			expect(frozenAt).never.toBeNil()
			local age = (frozenAt :: number) - pressedAt
			expect(handle.time).toBeCloseTo(age, 1e-9)
			expect(handle.time >= hold and handle.time < hold + 1 / fps).toBe(true)
			local events = clipEventsOf(rig, art.clip)
			expect(#events).toBe(1)
			expect(events[1].kind).toBe("ActivationHold")
			expect(events[1].jumped).toBe(false)
			expect(events[1].at).toBe(frozenAt)
			releaseInStep(rig, art, handle, pressedAt, age)
		end)
	end

	it("in a slowed capture a short hitch moves the held clip by its slowed share, no further", function()
		-- At 0.25x the hitch's frame carries the clip a quarter of the gap, still short of the end
		-- of its activation hold: nothing moves it on, and the section 6 fallback freezes it where
		-- it is, as on any slowed hold.
		local rig = load({ choreo = true, capture = true })
		rig.frame(STILL)
		expect(rig.controller.setCaptureTimeScale(0.25)).toBe(true)
		for _ = 1, 40 do
			rig.frame(STILL)
		end
		local art = rig.controller.slots()[1]
		local pressedAt = rig.now()
		rig.controller.beginArt(1)
		local handle = rig.animator.mixer:find(art.clip)
		for _ = 1, 5 do
			rig.frame(STILL)
		end
		rig.hitch(0.3)
		rig.wake()
		expect(handle.time).toBeCloseTo((rig.now() - pressedAt) * 0.25, 1e-9)
		expect(#clipEventsOf(rig, art.clip)).toBe(0)
		expect(rig.timeScales[#rig.timeScales]).toBe(0)
		expect(rig.controller.state()).toBe("Holding")
	end)

	for _, seconds in { 1, 5 } do
		it(
			("a %d s engine hitch past the cancel time: the wake neither chimes nor holds the stance"):format(seconds),
			function()
				-- The cancel (InputController's timer) lets the hold go in the wake's frame: nothing of
				-- its activation starts (the gap's events come marked), and the stance relaxes.
				local rig = standingRig({ choreo = true, impact = true })
				local art = rig.controller.slots()[1]
				local pressedAt = rig.now()
				rig.controller.beginArt(1)
				for _ = 1, 5 do
					rig.frame(STILL)
				end
				rig.hitch(seconds)
				rig.wake()
				expect(rig.now() - pressedAt >= Combat.activationCancelTime).toBe(true)
				local events = clipEventsOf(rig, art.clip)
				expect(#events > 0).toBe(true)
				for _, row in events do
					expect(row.jumped).toBe(true)
				end
				rig.controller.cancelArt(1)
				expect(rig.controller.state()).toBe("Idle")
				expect(rig.timeScales[#rig.timeScales]).toBe(1)
				expect(sends(rig, "ArtRequest")).toBe(0)
			end
		)
	end

	it("a key pressed in the dark just before the wake plays its start pose on from its own age", function()
		local rig = standingRig({ choreo = true, impact = true })
		local art = rig.controller.slots()[1]
		local hold = holdTimeOf(art.clip)
		for _ = 1, 60 do
			rig.heartbeat()
		end
		local pressedAt = rig.now()
		rig.controller.beginArt(1)
		local handle = rig.animator.mixer:find(art.clip)
		for _ = 1, 3 do
			rig.heartbeat()
		end
		rig.wake()
		-- Younger than its hold: nothing froze it; the wake moved it by its own age (D-132 sinceStep).
		expect(handle.time).toBeCloseTo(rig.now() - pressedAt, 1e-9)
		expect(handle.time < hold).toBe(true)
		expect(#clipEventsOf(rig, art.clip)).toBe(0)
		-- It goes on into the stance and freezes there as any hold does.
		local frames = 0
		repeat
			rig.frame(STILL)
			frames += 1
		until rig.timeScales[#rig.timeScales] == 0 or frames > 30
		local events = clipEventsOf(rig, art.clip)
		expect(#events).toBe(1)
		expect(events[1].jumped).toBe(false)
		expect(handle.time >= hold and handle.time < hold + FRAME).toBe(true)
	end)
end)

describe("CharacterController reads the root motion of the frame its rig stepped", function()
	-- The root offset a clip has reached at a clip time (Types.Vec3 as a Vector3).
	local function rootAt(clip: any, clipTime: number): Vector3
		local offset = ClipSampler.rootMotionAt(clip, clipTime)
		return Vector3.new(offset[1], offset[2], offset[3])
	end

	local function dodgeHandle(rig: Rig): any
		for _, handle in rig.animator.mixer:handles() do
			if string.find(handle.clipId, "/Dodge", 1, true) ~= nil and not handle.stopping then
				return handle
			end
		end
		return nil
	end

	for _, order in { "bound", "connections" } do
		it(("order %s: the root moves by this frame's step, the rig steps once"):format(order), function()
			local rig = standingRig({ choreo = true, renderOrder = order })
			rig.controller.dodge()
			local handle = dodgeHandle(rig)
			expect(handle).never.toBeNil()
			local start = rig.root.Position
			local origin = rootAt(handle.clip, 0)
			local steps = rig.rigSteps()
			for frame = 1, 12 do
				rig.frame(STILL)
				expect(rig.rigSteps()).toBe(steps + frame)
				expect(rig.controller.state()).toBe("Dodge")
				-- The root faces -Z unturned, so the clip's root space is the world's.
				local moved = rig.root.Position - start
				local expected = rootAt(handle.clip, handle.time) - origin
				expect((moved - expected).Magnitude < 1e-4).toBe(true)
			end
			expect((rig.root.Position - start).Magnitude > 1).toBe(true)
		end)
	end

	it("through the controller's step a stalled frame is a jump: no root motion, events marked", function()
		local rig = standingRig({ choreo = true, impact = true })
		local art = rig.controller.slots()[1]
		local pressedAt = rig.now()
		rig.controller.beginArt(1)
		for _ = 1, 15 do
			rig.frame(STILL)
		end
		rig.controller.releaseArt(1, rig.now() - pressedAt)
		local handle = rig.animator.mixer:find(art.clip)
		repeat
			rig.frame(STILL)
		until rig.timeScales[#rig.timeScales] ~= 0
		rig.frame(STILL)
		expect(rig.controller.state()).toBe("Art")
		local clipTime = handle.time
		local before = rig.root.Position
		local from = #rig.clipEvents + 1
		local steps = rig.rigSteps()
		for _ = 1, 48 do
			rig.heartbeat()
		end
		rig.wake()
		expect(rig.rigSteps()).toBe(steps + 1)
		expect(rig.controller.state()).toBe("Art")
		-- The gap carried the clip over its swing...
		expect(handle.time > clipTime + 0.5).toBe(true)
		expect(rootAt(handle.clip, handle.time) ~= rootAt(handle.clip, clipTime)).toBe(true)
		-- ...and the body none of the way: the server saw it stand still through the gap.
		expect((rig.root.Position - before).Magnitude < 1e-6).toBe(true)
		local crossed = clipEventsOf(rig, art.clip, from)
		expect(#crossed > 0).toBe(true)
		for _, row in crossed do
			expect(row.jumped).toBe(true)
		end
	end)
end)

describe("CharacterController's dodge pressed while the display sleeps (D-141)", function()
	-- The root offset a clip has reached at a clip time (Types.Vec3 as a Vector3).
	local function rootAt(clip: any, clipTime: number): Vector3
		local offset = ClipSampler.rootMotionAt(clip, clipTime)
		return Vector3.new(offset[1], offset[2], offset[3])
	end

	-- The local dodge clip on the rig (not stopping), or nil.
	local function dodgeHandle(rig: Rig): any
		for _, handle in rig.animator.mixer:handles() do
			if string.find(handle.clipId, "/Dodge", 1, true) ~= nil and not handle.stopping then
				return handle
			end
		end
		return nil
	end

	-- The log from row `from` on, as "kind name" rows.
	local function logRows(rig: Rig, from: number): { string }
		local rows = {}
		for index = from, #rig.log do
			table.insert(rows, rig.log[index].kind .. " " .. rig.log[index].name)
		end
		return rows
	end

	-- Follows the dodge `handle` for `frames` frames from `startedAt` (when its clip started): the
	-- state is Dodge for dodgeDuration from the start, the root is where the clip's root has got to
	-- on each of those frames' steps and stays there after, and nothing more is kicked, cued or sent.
	local function followDodge(rig: Rig, handle: any, start: Vector3, startedAt: number, frames: number)
		local origin = rootAt(handle.clip, 0)
		local logged = #rig.log
		local reached = Vector3.zero
		for _ = 1, frames do
			rig.frame(STILL)
			local age = rig.now() - startedAt
			expect(handle.time).toBeCloseTo(math.min(age, handle.clip.duration), 1e-9)
			local ended = rig.now() >= startedAt + Combat.dodgeDuration
			expect(rig.controller.state()).toBe(if ended then "Idle" else "Dodge")
			if not ended then
				-- The root faces -Z unturned, so the clip's root space is the world's.
				reached = rootAt(handle.clip, handle.time) - origin
			end
			-- (Vector3 is single precision: the frames' deltas add up to the clip's root within 1e-4.)
			expect((rig.root.Position - start - reached).Magnitude < 1e-4).toBe(true)
		end
		expect(#rig.log).toBe(logged)
	end

	it("display awake: the dodge plays at the press, as it always did (guard)", function()
		local rig = standingRig({ choreo = true, impact = true })
		local from = #rig.log + 1
		local events = #rig.clipEvents + 1
		local start = rig.root.Position
		local pressedAt = rig.now()
		rig.controller.dodge()
		-- The kick, the speed lines and the whoosh, then the request, all in the press.
		expect(logRows(rig, from)).toEqual({ "camera fovKick", "impact dodge", "send DodgeRequest" })
		local handle = dodgeHandle(rig)
		expect(handle).never.toBeNil()
		expect(handle.time).toBe(0)
		expect(rig.controller.state()).toBe("Dodge")
		followDodge(rig, handle, start, pressedAt, 24)
		local footsteps = clipEventsOf(rig, handle.clipId, events)
		expect(#footsteps).toBe(1)
		expect(footsteps[1].jumped).toBe(false)
		expect(footsteps[1].at - pressedAt).toBeCloseTo(0.3, 1e-9)
	end)

	it("an engine hitch (nothing ran) is no sleep: the dodge plays at the press (guard)", function()
		local rig = standingRig({ choreo = true, impact = true })
		rig.hitch(2)
		local from = #rig.log + 1
		local start = rig.root.Position
		local pressedAt = rig.now()
		rig.controller.dodge()
		expect(logRows(rig, from)).toEqual({ "camera fovKick", "impact dodge", "send DodgeRequest" })
		local handle = dodgeHandle(rig)
		expect(handle).never.toBeNil()
		followDodge(rig, handle, start, pressedAt, 20)
	end)

	for _, before in { 12, 16 } do
		it(
			("pressed %d Heartbeats before the wake: the request goes at the press, the whole dodge after the wake"):format(
				before
			),
			function()
				local rig = standingRig({ choreo = true, impact = true })
				for _ = 1, 600 do
					rig.heartbeat()
				end
				local from = #rig.log + 1
				local events = #rig.clipEvents + 1
				local start = rig.root.Position
				rig.controller.dodge()
				-- The server's dodge starts from the request; nothing on this screen or speaker yet.
				expect(logRows(rig, from)).toEqual({ "send DodgeRequest" })
				expect(rig.controller.state()).toBe("Dodge")
				expect(dodgeHandle(rig)).toBeNil()
				for _ = 1, before do
					rig.heartbeat()
				end
				expect(logRows(rig, from)).toEqual({ "send DodgeRequest" })
				rig.wake()
				local wokeAt = rig.now()
				-- The wake shows the body where it stood, the dodge's first pose to come, and its kick
				-- and cue (the landing sound is the cue's, dodgeDuration on: when the travel ends).
				expect((rig.root.Position - start).Magnitude < 1e-9).toBe(true)
				expect(logRows(rig, from)).toEqual({ "send DodgeRequest", "camera fovKick", "impact dodge" })
				local dodges = impactCalls(rig, "dodge")
				expect(dodges[#dodges][1]).toBe(rig.model)
				expect(dodges[#dodges][2]).toBe(true)
				local handle = dodgeHandle(rig)
				expect(handle).never.toBeNil()
				expect(handle.time).toBe(0)
				expect(rig.controller.state()).toBe("Dodge")
				-- Then the dodge a press on the wake's frame would have made, travel and length.
				followDodge(rig, handle, start, wokeAt, 24)
				local footsteps = clipEventsOf(rig, handle.clipId, events)
				expect(#footsteps).toBe(1)
				expect(footsteps[1].jumped).toBe(false)
				expect(footsteps[1].at - wokeAt).toBeCloseTo(0.3, 1e-9)
				expect(sends(rig, "DodgeRequest")).toBe(1)
			end
		)
	end

	it("pressed a moment into a short blackout that is no jump: the dodge still waits for the wake", function()
		local rig = standingRig({ choreo = true, impact = true })
		rig.heartbeat()
		rig.heartbeat()
		local from = #rig.log + 1
		local start = rig.root.Position
		rig.controller.dodge()
		expect(logRows(rig, from)).toEqual({ "send DodgeRequest" })
		rig.heartbeat()
		rig.wake()
		local wokeAt = rig.now()
		expect((rig.root.Position - start).Magnitude < 1e-9).toBe(true)
		local handle = dodgeHandle(rig)
		expect(handle).never.toBeNil()
		followDodge(rig, handle, start, wokeAt, 20)
	end)

	it("pressed longer than a jump before the wake: nothing shows or sounds; the request went", function()
		local rig = standingRig({ choreo = true, impact = true })
		for _ = 1, 600 do
			rig.heartbeat()
		end
		local from = #rig.log + 1
		local start = rig.root.Position
		rig.controller.dodge()
		local pressedAt = rig.now()
		repeat
			rig.heartbeat()
		until rig.now() - pressedAt > ChoreoData.stall.jumpSeconds
		rig.wake()
		expect(rig.controller.state()).toBe("Idle")
		expect(dodgeHandle(rig)).toBeNil()
		for _ = 1, 30 do
			rig.frame(STILL)
			expect((rig.root.Position - start).Magnitude < 1e-9).toBe(true)
		end
		expect(logRows(rig, from)).toEqual({ "send DodgeRequest" })
	end)

	it("refused by the server, or the character gone, in the dark: the wake shows nothing", function()
		for _, ending in { "reject", "respawn" } do
			local rig = standingRig({ choreo = true, impact = true })
			for _ = 1, 600 do
				rig.heartbeat()
			end
			local from = #rig.log + 1
			local start = rig.root.Position
			rig.controller.dodge()
			rig.heartbeat()
			if ending == "reject" then
				rig.reject("Dodge")
			else
				rig.respawn()
			end
			expect(rig.controller.state()).toBe("Idle")
			rig.heartbeat()
			rig.wake()
			for _ = 1, 20 do
				rig.frame(STILL)
				expect((rig.root.Position - start).Magnitude < 1e-9).toBe(true)
			end
			expect(rig.controller.state()).toBe("Idle")
			expect(dodgeHandle(rig)).toBeNil()
			expect(logRows(rig, from)).toEqual({ "send DodgeRequest" })
		end
	end)
end)

describe("CharacterController's blade contacts (issue 4)", function()
	local Weapons = Harness.load("src/shared/data/weapons")
	local Playground = Harness.load("src/shared/data/playground")

	local function contactRows(rig: Rig, from: number?): { any }
		local rows = {}
		for index = from or 1, #rig.log do
			local row = rig.log[index]
			if row.kind == "contact" then
				table.insert(rows, row.args[1])
			end
		end
		return rows
	end

	local function basicHandle(rig: Rig): any
		for _, handle in rig.animator.mixer:handles() do
			if string.find(handle.clipId, "/Basic", 1, true) ~= nil and not handle.stopping then
				return handle
			end
		end
		return nil
	end

	it("a swing predicts its clip's contacts: the basic multiplier, the chain's last swing final", function()
		local rig = standingRig({ choreo = true })
		local attack = Weapons.byId(Playground.loadout.weapon).attack
		for swing = 1, 3 do
			rig.controller.basicAttack()
			local begun = rig.contacts.begins[swing]
			expect(begun).never.toBeNil()
			expect(begun.clip).toBe(basicHandle(rig).clip)
			expect(begun.artId).toBeNil()
			expect(begun.multiplier).toBe(Combat.basicAttackMultiplier)
			expect(begun.finalHit).toBe(swing >= Combat.basicChainLength)
			expect(begun.weaponAttack).toBe(attack)
			for _ = 1, 30 do
				rig.frame(STILL)
			end
		end
		-- The predictor follows the rig's own clip handle and nothing else: it read the predictor's deps.
		expect(typeof(rig.contacts.deps.targets)).toBe("function")
	end)

	it("sweeps each frame after the rig's step and its root motion, with the clip time it shows", function()
		local rig = standingRig({ choreo = true })
		local stepsBefore = rig.rigSteps()
		rig.controller.basicAttack()
		local handle = basicHandle(rig)
		for frame = 1, 12 do
			rig.frame(STILL)
			local row = rig.contacts.steps[#rig.contacts.steps]
			expect(#rig.contacts.steps).toBe(frame)
			-- This frame's rig step had run, and the clip time is the one the rig shows.
			expect(row.rigSteps).toBe(stepsBefore + frame)
			expect(row.time).toBe(handle.time)
			-- The root it read is where this frame left it (after the clip's root motion).
			expect((row.root.Position - rig.root.Position).Magnitude < 1e-9).toBe(true)
		end
	end)

	it("hands every contact to Replication.contact on its frame", function()
		local rig = standingRig({ choreo = true })
		rig.controller.basicAttack()
		rig.frame(STILL)
		local touch = { targetId = 7, windowIndex = 1, tier = "Normal", killed = false }
		rig.contacts.queue = { touch }
		local from = #rig.log + 1
		rig.frame(STILL)
		local rows = contactRows(rig, from)
		expect(#rows).toBe(1)
		expect(rows[1]).toBe(touch)
		rig.frame(STILL)
		expect(#contactRows(rig, from)).toBe(1)
	end)

	it("an Art release predicts the Art's contacts with its id and multiplier, its last window final", function()
		local rig = standingRig({ choreo = true, impact = true })
		local art = rig.controller.slots()[1]
		local pressedAt = rig.now()
		rig.controller.beginArt(1)
		for _ = 1, 20 do
			rig.frame(STILL)
		end
		expect(#rig.contacts.begins).toBe(0)
		rig.controller.releaseArt(1, rig.now() - pressedAt)
		local begun = rig.contacts.begins[1]
		expect(begun).never.toBeNil()
		expect(begun.artId).toBe(art.id)
		expect(begun.multiplier).toBe(art.multiplier)
		expect(begun.finalHit).toBe(true)
		expect(begun.clip).toBe(rig.animator.mixer:find(art.clip).clip)
	end)

	it("stops on a refusal, a dodge or a respawn: no more sweeps of that swing", function()
		for _, ending in { "reject", "dodge", "respawn" } do
			local rig = standingRig({ choreo = true })
			rig.controller.basicAttack()
			rig.frame(STILL)
			local stops = rig.contacts.stops
			if ending == "reject" then
				rig.reject("BasicAttack")
			elseif ending == "dodge" then
				for _ = 1, 40 do
					rig.frame(STILL)
				end
				rig.controller.basicAttack()
				rig.frame(STILL)
				stops = rig.contacts.stops
				rig.controller.dodge()
			else
				rig.respawn()
			end
			rig.frame(STILL)
			local steps = #rig.contacts.steps
			for _ = 1, 5 do
				rig.frame(STILL)
			end
			expect(#rig.contacts.steps).toBe(steps)
			expect(rig.contacts.stops > stops).toBe(true)
		end
	end)

	it("re-baselines the sweep on a render stall's wake frame: no contact across the gap", function()
		for _, sleep in { 36, 18 } do
			local rig = standingRig({ choreo = true, impact = true })
			local pressedAt = rig.now()
			rig.controller.beginArt(1)
			for _ = 1, 15 do
				rig.frame(STILL)
			end
			rig.controller.releaseArt(1, rig.now() - pressedAt)
			for _ = 1, 3 do
				rig.frame(STILL)
			end
			expect(#rig.contacts.begins).toBe(1)
			local before = #rig.contacts.steps
			for _ = 1, sleep do
				rig.heartbeat()
			end
			rig.wake()
			rig.frame(STILL)
			local steps = rig.contacts.steps
			-- The swing still runs: the wake and the frame after it were swept.
			expect(#steps).toBe(before + 2)
			local woke = steps[#steps - 1]
			-- A jump's wake (longer than stall.jumpSeconds) only records the pose; a shorter stall
			-- is no jump and sweeps as any frame.
			expect(woke.jumped == true).toBe(sleep * FRAME > ChoreoData.stall.jumpSeconds)
			for index, row in steps do
				if index ~= #steps - 1 then
					expect(row.jumped == true).toBe(false)
				end
			end
		end
	end)
end)

describe("CharacterController swing sequence numbers (item 4)", function()
	-- The `swing` of every request of these names the rig sent, in order.
	local function swingsOf(rig: Rig): { number }
		local found = {}
		for _, entry in rig.sent do
			if entry.name == "BasicAttackRequest" or entry.name == "ArtRequest" then
				table.insert(found, entry.payload.swing)
			end
		end
		return found
	end

	it("each basic swing and Art release carries the next number", function()
		local Combat = Harness.load("src/shared/data/combat")
		local rig = load()
		for _ = 1, 30 do
			rig.frame(STILL)
		end
		rig.controller.basicAttack()
		for _ = 1, math.ceil(Combat.basicHitDuration / FRAME) + 2 do
			rig.frame(STILL)
		end
		rig.controller.basicAttack()
		for _ = 1, math.ceil((Combat.basicHitDuration + Combat.basicChainWindow) / FRAME) + 30 do
			rig.frame(STILL)
		end
		rig.controller.beginArt(1)
		for _ = 1, 6 do
			rig.frame(STILL)
		end
		rig.controller.releaseArt(1, 6 * FRAME)
		local swings = swingsOf(rig)
		expect(#swings).toBe(3)
		for index, swing in swings do
			expect(typeof(swing)).toBe("number")
			expect(swing >= 1 and swing <= Combat.contact.swingSequenceMax).toBe(true)
			expect(swing == math.floor(swing)).toBe(true)
			if index > 1 then
				expect(swing).toBe(swings[index - 1] % Combat.contact.swingSequenceMax + 1)
			end
		end
	end)
end)
