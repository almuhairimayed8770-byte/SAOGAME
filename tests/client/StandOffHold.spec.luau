--!strict
--[[
	Item 492(a) (D-604): the Art's activation hold is the tell, so the body holds still through it.
	The PC's boar1 (Vertical at the boar held 3.8 studs ahead, 60 fps) stepped the root 0.051,
	0.049, 0.044, 0.036, 0.029, 0.027 on rows L+21 to L+26, while the pose stood still in the
	root's frame: the plan's step back ran on QuadOut from the release's clip time to the first
	window's open, through the authored hold (0.15 to 0.25). Two parts of the plan do that:

	- the Art's blade step (fix F1), when the start pose's blade does not clear the target;
	- the reach's step for the first strike (D-424), when the blade would stand too deep at its key
	  (the capture's kobold staged 3.5 ahead: 0.65 studs back on Vertical).

	Both now wait for the hold's end (the clip's ActivationHold time plus its data.hold) and are
	done by the open; a step too long to take there within keepOut.maxSpeedStudsPerSecond starts as
	late before it as that speed allows (ContactPredictor.stepStart), and the blade step's first
	move shows with the pose that leaves the hold (D-496's hold-back).

	The path: a fresh copy of the real CharacterController (CharacterController.spec's harness,
	trimmed to an Art) with a real Choreo playing the real Vertical clip on a real rig, on the spec's
	clock at 30, 60 and 144 fps; its ContactPredictor.standOff answers with the real plan
	(ContactPredictor.standOff with the options the controller asked) on the hit matrix's avatar and
	a real kobold rig with its blocker. A row is what item 397's logger reads at Last+2: the root
	after the frame's render step, and the clip the frame before stepped to (the pose drawn, D-342).

	With a lock the press plans the held start pose's keep-out first (D-606): the body steps
	back as the stance forms, and the release plans the swing from where it then stands. The kobold
	stands still in the world, so each plan is the real one for where the root stands when it is
	asked; the root starts on the map, not at the world's origin, as on any real place. A drawn
	clock summed to the hold's end lands a hair past it (0.25 + 6e-17 at 144 fps): the hold-back
	reads it as the hold within combat.contact.keyEpsilon (D-616).

	M12s's open line (D-631): the keep-out's lead, back and aside, also waits for the hold's end.
	On efa907c the step-aside ran inside the hold, 0.20 a 60 fps row sideways at a kobold 2.7 off at
	130 degrees turned 30 (0.42 in all locked, 0.64 unlocked), and the judges above read along
	`away` only. The last describe reads every hold row flat, in every direction, at that placement
	and over a sweep of bearings.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local Siblings = Harness.load("src/client/controllers/Siblings")
local AimLogic = Harness.load("src/client/controllers/AimLogic")
local Combat = Harness.load("src/shared/data/combat")
local Enemies = Harness.load("src/shared/data/enemies")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local BodyShell = Harness.load("src/shared/choreo/BodyShell")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local RealContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local EvenRoot = Harness.load("src/client/choreo/EvenRoot")
local ChoreoData = Harness.load("src/shared/data/choreo")

local CONTROLLER_PATH = "src/client/controllers/CharacterController"
local CHOREO_PATH = "src/client/choreo/Choreo"
local MOVE_INPUT_PATH = "src/client/controllers/MoveInput"
local PHYSICS = 1 / 60 -- the fake physics' step (the root never walks here)
local SPEED: number = Combat.contact.standOff.keepOut.maxSpeedStudsPerSecond
local EVEN_ROOT = ChoreoData.locomotion.stride.evenRoot
local VERTICAL = "player/OneHandedSword/Vertical"

local root = Harness.repoRoot()
-- Where the controller's root stands when the spec starts, facing -Z as the avatar's base: off the
-- world's origin, as on any real place (a float position at the origin keeps a 1e-16 step that
-- one anywhere else drops), and near it, so the rows' float positions still read to 1e-7.
local START = CFrame.new(1.3, 0.6, -1.7)

local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
local avatar = HitMatrix.standing(Harness)

-- A kobold's rig in its rest pose with its blocker (D-198), `distance` studs from the hit matrix's
-- avatar at `bearing` degrees off its facing (+ = to its right), turned `yaw` off facing it.
local function kobold(bearing: number, yaw: number, distance: number): any
	local def = Enemies.byId("KoboldAxeman")
	local model = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local turn = math.rad(bearing)
	local frame = avatar.base
		* CFrame.new(math.sin(turn) * distance, height - avatar.rootHeight, -math.cos(turn) * distance)
		* CFrame.Angles(0, math.pi - turn + math.rad(yaw), 0)
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	assert(RigBuilder.addBlocker(model) ~= nil, "no blocker for the kobold")
	return model
end

-- The kobold as the PC's unlockB takes stood it (item 573(b) on 577a59a): its root at (-60, 72)
-- with yaw 0, the local fighter's at (`x`, `z`) with `yaw` (degrees, Roblox's: 0 looks along -Z,
-- -90 along +X), placed off the avatar as it stood off that root.
local PC_KOBOLD = CFrame.new(-60, 0, 72) -- unit: the PC's place, studs
local function pcKobold(x: number, z: number, yaw: number): any
	local def = Enemies.byId("KoboldAxeman")
	local model = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local rel = (CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)):ToObjectSpace(PC_KOBOLD)
	local frame = avatar.base * CFrame.new(rel.X, height - avatar.rootHeight, rel.Z) * rel.Rotation
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	assert(RigBuilder.addBlocker(model) ~= nil, "no blocker for the kobold")
	return model
end

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

-- A fresh copy of MoveInput (its own bound control module).
local function freshMoveInput(): any
	local env = Harness.environment()
	env.script = Harness.node(MOVE_INPUT_PATH)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	return luau.load(
		Harness.readFile(MOVE_INPUT_PATH .. ".luau"),
		{ debugName = MOVE_INPUT_PATH, environment = env :: any }
	)()
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
	root: any,
	animator: any,
	-- One rendered frame `dt` long, the stick at rest.
	frame: (dt: number) -> (),
	-- Locks an enemy standing at `position`.
	setLock: (position: Vector3) -> (),
	-- With no lock, the soft assist's candidate: an enemy standing at `position`, handed to the
	-- controller straight ahead of where it looks; with `seen`, at the bearing and distance
	-- TargetController.assistCandidates measures from where the controller asks (item 573(b)).
	setAssist: (position: Vector3, seen: boolean?) -> (),
	-- What the controller asked ContactPredictor.standOff for a swing, and the plan it was handed.
	asked: { { from: number, root: CFrame, options: any, plan: any } },
	-- The held start pose's asks at the press (options.stance, D-606), kept apart from the swing's.
	stances: { { from: number, root: CFrame, options: any, plan: any } },
	-- Where the last frame's physics finds the body: on the even root the controller asked
	-- Locomotion for (D-675), or on its root.
	body: () -> CFrame,
}

-- The controller on a real Choreo; its ContactPredictor.standOff hands back the real plan against
-- `target` for the hit matrix's avatar standing where the controller's root stands when it asks:
-- the controller's world is the avatar's, START on the avatar's base (the kobold stands still in
-- it, so a plan asked after the stance's step back sees that step).
local function load(target: any): Rig
	local clock = 0
	local step: ((dt: number) -> ())? = nil
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
			props[key] = value
		end,
	})
	local rootState: { [string]: any } = { CFrame = START, AssemblyLinearVelocity = Vector3.zero }
	local rootPart: any = setmetatable({}, {
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
	local assistRecord: any = nil
	local assistSeen = false
	local model = {
		WaitForChild = function(_self: any, name: string): any
			return if name == "Humanoid" then humanoid else rootPart
		end,
		GetAttribute = function(): any
			return nil
		end,
		GetAttributeChangedSignal = function(): any
			return Signal.new()
		end,
	}
	-- Locomotion's even root (stepEvenRoot, D-675) as the controller asks for it: while the frame's
	-- state says evenRoot on the ground, EvenRoot evens the root as it stands at the update, on by
	-- its flat velocity, and Choreo draws the body there on PreSimulation, on its root past
	-- maxDrawnStuds (offsetOn); asked for nothing, on its root.
	local even = EvenRoot.new()
	local drawnOn: CFrame? = nil
	local locomotion = {
		new = function(): any
			return {
				serverDrawn = function(): boolean
					return false
				end,
				update = function(_self: any, dt: number, state: any)
					if EVEN_ROOT.drawBody and state.evenRoot == true and state.grounded and dt > 0 then
						local velocity: Vector3 = state.velocity or rootState.AssemblyLinearVelocity
						local ahead = rootState.CFrame + Vector3.new(velocity.X, 0, velocity.Z) * dt
						drawnOn = EvenRoot.step(even, ahead, dt, nil, EVEN_ROOT)
					elseif drawnOn ~= nil then
						drawnOn = nil
						EvenRoot.reset(even)
					end
				end,
			}
		end,
	}
	local targetController = {
		current = function(): any
			return lockRecord
		end,
		assistCandidates = function(origin: Vector3, look: Vector3): { any }
			if assistRecord == nil then
				return {}
			end
			local at: Vector3 = assistRecord.model.PrimaryPart.Position
			if assistSeen then
				-- TargetController.assistCandidates: flat, from where the controller asks.
				local dx, dz = at.X - origin.X, at.Z - origin.Z
				return {
					{
						id = assistRecord.id,
						distance = math.sqrt(dx * dx + dz * dz),
						bearing = AimLogic.bearing(look.X, look.Z, dx, dz),
					},
				}
			end
			-- The pick straight ahead, as the lock is: the request's facing does not turn.
			return { { id = assistRecord.id, distance = (at - START.Position).Magnitude, bearing = 0 } }
		end,
	}
	local asked: { { from: number, root: CFrame, options: any, plan: any } } = {}
	local stances: { { from: number, root: CFrame, options: any, plan: any } } = {}
	local moveInput = freshMoveInput()
	moveInput.bind({
		controls = function(): any
			return {
				GetMoveVector = function(_self: any): Vector3
					return Vector3.zero
				end,
			}
		end,
		camera = function(): CFrame?
			return CFrame.identity
		end,
	})
	local fakes: { [string]: any } = {
		MoveInput = moveInput,
		ContactPredictor = {
			standOff = function(
				_model: any,
				clip: any,
				from: number,
				rootCFrame: CFrame,
				_target: any,
				_cast: any,
				options: any
			): any
				local real = RealContactPredictor.standOff(
					avatar.model,
					clip,
					from,
					avatar.base * START:ToObjectSpace(rootCFrame),
					target,
					nil,
					{
						keepOut = options.keepOut,
						step = options.step,
						poseLag = options.poseLag,
						stance = options.stance,
					}
				)
				local function turned(vector: Vector3?): Vector3?
					return if vector ~= nil
						then START:VectorToWorldSpace(avatar.base:VectorToObjectSpace(vector))
						else nil
				end
				local plan = if real ~= nil
					then {
						distance = real.distance,
						away = turned(real.away),
						from = real.from,
						to = real.to,
						keep = real.keep,
						keepUntil = real.keepUntil,
						side = turned(real.side),
						keepSide = real.keepSide,
						still = real.still,
						wait = real.wait,
					}
					else nil
				table.insert(
					if options.stance ~= nil then stances else asked,
					{ from = from, root = rootCFrame, options = options, plan = plan }
				)
				return plan
			end,
			targetMotion = RealContactPredictor.targetMotion,
			-- A body standing free at the kobold (D-692) as the real one steps it, on the avatar.
			keepStanding = function(
				_model: any,
				rootCFrame: CFrame,
				offsets: any,
				_records: { any },
				studs: number
			): Vector3
				local by = RealContactPredictor.keepStanding(
					avatar.model,
					avatar.base * START:ToObjectSpace(rootCFrame),
					offsets,
					{ { model = target } },
					studs,
					function(): number?
						return nil
					end
				)
				return START:VectorToWorldSpace(avatar.base:VectorToObjectSpace(by))
			end,
			worldCast = function(): any
				return function(): number?
					return nil
				end
			end,
			new = function(): any
				return {
					begin = function(): boolean
						return true
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
		Net = {
			client = function(): any
				return { fire = function() end, on = function() end }
			end,
		},
		EntityTracker = {
			localRecord = function(): any
				return nil
			end,
			get = function(id: number): any
				return if assistRecord ~= nil and assistRecord.id == id then assistRecord else nil
			end,
			peekLocalId = function(): any
				return nil
			end,
			-- The kobold is live, picked or not.
			live = function(): { any }
				return { { id = 1, kind = "Enemy", state = "Idle", model = target } }
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
	}
	local choreo: any = nil
	fakes.Siblings = {
		load = function(_parent: any, path: string): (any, boolean)
			if path == "choreo.Locomotion" then
				return locomotion, true
			end
			if path == "choreo.Choreo" then
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
	}
	local heartbeat = Signal.new()
	local renderStepped = Signal.new()
	local preSimulation = Signal.new()
	local localPlayer = { CharacterAdded = Signal.new(), CharacterRemoving = Signal.new(), Character = model }
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, _name: string, _priority: number, fn: (dt: number) -> ())
				step = fn
			end,
			Heartbeat = heartbeat,
			RenderStepped = renderStepped,
			PreSimulation = preSimulation,
			IsStudio = function(): boolean
				return true
			end,
		},
		Players = { LocalPlayer = localPlayer },
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	-- task.delay on the spec's clock, resumed after Heartbeat as the engine does.
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
	local rigAnimator = realChoreo.get(rigModel)
	rigAnimator.events:Connect(function(clipId: string, event: any, jumped: boolean)
		fakes.Replication.clipEvent:Fire({ model = model }, clipId, event, jumped)
	end)
	choreo = {
		get = function(): any
			return rigAnimator
		end,
		setLocalModel = function(targetModel: any, ...: any)
			realChoreo.setLocalModel(if targetModel ~= nil then rigModel else nil, ...)
		end,
		find = function(): any
			return nil
		end,
		stepLocal = realChoreo.stepLocal,
	}
	local env = Harness.environment()
	env.script = Harness.node(CONTROLLER_PATH)
	env.require = function(module: any): any
		return fakes[module.Name] or Harness.loadModule(module)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	env.workspace = {
		GetServerTimeNow = function(): number
			return clock
		end,
		GetAttribute = function(): any
			return nil
		end,
	}
	env.os = {
		clock = function(): number
			return clock
		end,
	}
	env.task = {
		delay = function(seconds: number, fn: () -> ())
			table.insert(timers, { at = clock + seconds, fn = fn })
		end,
	}
	local controller = luau.load(
		Harness.readFile(CONTROLLER_PATH .. ".luau"),
		{ debugName = CONTROLLER_PATH, environment = env :: any }
	)()
	controller.start()
	assert(step ~= nil, "the controller bound no render step")
	return {
		controller = controller,
		root = rootPart,
		animator = rigAnimator,
		frame = function(dt: number)
			clock += dt
			humanoid:Move(Vector3.zero)
			local runStep = step :: (dt: number) -> ()
			runStep(dt)
			renderStepped:Fire(dt)
			preSimulation:Fire(PHYSICS)
			heartbeat:Fire(PHYSICS)
			runTimers()
		end,
		setLock = function(position: Vector3)
			lockRecord = { id = 1, kind = "Enemy", state = "Idle", model = { PrimaryPart = { Position = position } } }
		end,
		setAssist = function(position: Vector3, seen: boolean?)
			assistSeen = seen == true
			assistRecord = { id = 1, kind = "Enemy", state = "Idle", model = { PrimaryPart = { Position = position } } }
		end,
		asked = asked,
		stances = stances,
		body = function(): CFrame
			local frame: CFrame = rootState.CFrame
			local on = drawnOn
			if on == nil then
				return frame
			end
			local shift = on.Position - frame.Position
			shift = Vector3.new(shift.X, 0, shift.Z)
			return if shift.Magnitude > EVEN_ROOT.maxDrawnStuds then frame else frame + shift
		end,
	}
end

-- One row as item 397's logger reads it at Last+2: the clip the frame stepped to, and the root;
-- where the frame's physics found the body (Rig.body), where a row records it.
type Row = { clip: number, root: Vector3, frame: CFrame, body: CFrame? }

-- One Vertical cast: the rows from the release on, the swing's plan and the clip time it was
-- released at; and from the press to the release, the stance's ask (nil with no lock), the rows
-- and what the release call itself moved the root.
type Cast = {
	rows: { Row },
	plan: any,
	released: number,
	stance: any,
	held: { Row },
	releaseStep: Vector3,
}

-- The clip time an Art clip's hold pose stands at: its ActivationHold's time.
local function holdAt(clip: any): number
	for _, event in clip.events do
		if event.kind == "ActivationHold" then
			return event.time
		end
	end
	error("no ActivationHold")
end

-- Vertical cast at `fps` against `target`, at an enemy `ahead` studs in front of the root (where
-- the controller faces), locked or (`locked` false) the soft assist's pick, held 0.2 s at its hold
-- pose and released. `late`: the soft assist has no pick at the press (the enemy comes into its
-- cone while the key is held), so only the release picks it.
local function cast(target: any, ahead: number, fps: number, locked: boolean, late: boolean?): Cast
	local rig = load(target)
	local dt = 1 / fps
	for _ = 1, 40 do
		rig.frame(dt)
	end
	local enemyAt = START.Position + Vector3.new(0, 0, -ahead)
	if locked then
		rig.setLock(enemyAt)
	elseif not late then
		rig.setAssist(enemyAt)
	end
	local slot = 2
	local art = rig.controller.slots()[slot]
	assert(art ~= nil and art.clip == VERTICAL, "quick slot 2 is Vertical")
	local held: { Row } = { { clip = 0, root = rig.root.Position, frame = rig.root.CFrame } }
	rig.controller.beginArt(slot)
	local handle = rig.animator.mixer:find(VERTICAL)
	-- A held lock, or with none the soft assist's pick, plans the stance at the press (D-606,
	-- D-673): one ask, keep-out alone, to the hold pose. No pick, no stance.
	local stanced = locked or not late
	if stanced then
		assert(#rig.stances == 1, "the press at a lock or an assist pick asks for one stance plan")
		local options = rig.stances[1].options
		assert(options.stance == holdAt(handle.clip), "the stance is planned to the hold pose")
		assert(options.step == false, "the stance plans no blade step")
	else
		assert(#rig.stances == 0, "a press with no lock and no pick asks for no stance plan")
		rig.setAssist(enemyAt)
	end
	assert(#rig.asked == 0, "the press asks for no swing plan")
	local holdFrames = math.ceil(0.2 * fps)
	for _ = 1, holdFrames do
		rig.frame(dt)
		table.insert(held, { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame })
	end
	local released = handle.time
	local before = rig.root.Position
	rig.controller.releaseArt(slot, holdFrames * dt)
	local releaseStep = rig.root.Position - before
	assert(#rig.stances == (if stanced then 1 else 0), "the release asks for no stance plan")
	assert(#rig.asked == 1, "the release asks for one swing plan")
	local rows: { Row } = { { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame } }
	while handle.time < 0.45 do
		rig.frame(dt)
		table.insert(rows, { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame })
	end
	return {
		rows = rows,
		plan = rig.asked[1].plan,
		released = released,
		stance = rig.stances[1],
		held = held,
		releaseStep = releaseStep,
	}
end

-- The clip time an Art clip's activation hold ends: its ActivationHold's time plus its data.hold.
local function holdEnd(clip: any): number
	for _, event in clip.events do
		if event.kind == "ActivationHold" then
			return event.time + event.data.hold
		end
	end
	error("no ActivationHold")
end

local vertical = Harness.load("src/shared/clips/" .. VERTICAL)
local HOLD_END = holdEnd(vertical)
local OPEN = ClipSampler.hitWindows(vertical)[1].open

-- Checks the rows of one cast against the plan's own step back at a clip time (`shownAt`: the blade
-- step and the keep-out together): on every row that draws the clip up to the hold's end the root
-- moves no more than `inHold` (0 for the blade step), none of the rows from there to the first
-- row that draws the open or past it (at 30 fps no row draws 0.35 itself) moves faster than
-- keepOut.maxSpeedStudsPerSecond, and on that row the root stands where the plan puts the pose it
-- draws, all of `whole` back. Prints the rows (the report's before and after).
local function judge(
	label: string,
	fps: number,
	rows: { Row },
	away: Vector3,
	shownAt: (number) -> number,
	whole: number,
	inHold: number
)
	local held, moved = {}, {}
	local start = rows[1].root
	for index = 2, #rows do
		local drawn = rows[index - 1].clip
		local stepped = (rows[index].root - rows[index - 1].root):Dot(away)
		if drawn <= HOLD_END + 1e-6 then
			table.insert(held, ("%.3f"):format(stepped))
			if math.abs(stepped) > inHold + 1e-6 then
				error(
					("%s at %d fps: the row drawing clip %.4f (in the hold, to %.2f) steps the root %.4f"):format(
						label,
						fps,
						drawn,
						HOLD_END,
						stepped
					)
				)
			end
		else
			table.insert(moved, ("%.3f"):format(stepped))
			expect(stepped <= SPEED / fps + 1e-6).toBe(true)
			if drawn >= OPEN - 1e-6 then
				-- The row that draws the open: the root stands with its pose, the whole step back.
				local back = (rows[index].root - start):Dot(away)
				expect(back).toBeCloseTo(shownAt(drawn), 1e-4)
				expect(back).toBeCloseTo(whole, 1e-3)
				print(
					("[492a] %s at %d fps: rows drawing to %.2f %s | to the open %s"):format(
						label,
						fps,
						HOLD_END,
						table.concat(held, " "),
						table.concat(moved, " ")
					)
				)
				return
			end
		end
	end
	error(("%s at %d fps: no row drew the open"):format(label, fps))
end

-- Checks the rows from the press to the release of a locked cast against its stance plan
-- (D-606): no row steps toward the kobold or faster than keepOut.maxSpeedStudsPerSecond; from
-- the first row whose clip stands frozen the root stands still (item 498(b)'s line, on the root at
-- Character+1: the stance's step is done as it forms, and a plan that waits for no hold shows its
-- moves on their own frames, D-617); by the release it stands all of the stance's keep-out back
-- at the frozen clip time, no more and no less; and the release itself moves nothing. Prints the
-- rows and returns the stance's whole step back.
local function judgeStance(label: string, fps: number, c: Cast): number
	local stance = c.stance.plan
	expect(stance).never.toBeNil()
	expect(stance.distance).toBe(0)
	-- It waits for no hold: done by the hold pose, with no step and no reach (D-617).
	expect(stance.still).toBeNil()
	local frozen = c.released
	local steps = {}
	for index = 2, #c.held do
		local stepped = c.held[index].root - c.held[index - 1].root
		local along = stepped:Dot(stance.away)
		table.insert(steps, ("%.3f"):format(along))
		expect(along >= -1e-6).toBe(true)
		expect(stepped.Magnitude <= SPEED / fps + 1e-6).toBe(true)
		if c.held[index].clip >= frozen - 1e-9 and stepped.Magnitude > 1e-6 then
			error(
				("%s at %d fps: a held row whose clip stands frozen at %.4f steps the root %.4f"):format(
					label,
					fps,
					c.held[index].clip,
					stepped.Magnitude
				)
			)
		end
	end
	-- The plan's series runs on the stance's clock: the clip time plus its pose's wait (D-691).
	local clock = frozen + (stance.wait or 0)
	local whole = stance.away * stance.keep(clock)
		+ (if stance.side ~= nil and stance.keepSide ~= nil then stance.side * stance.keepSide(clock) else Vector3.zero)
	local shift = c.held[#c.held].root - c.held[1].root
	expect((shift - whole).Magnitude <= 1e-4).toBe(true)
	expect(c.releaseStep.Magnitude).toBe(0)
	print(
		("[498b] %s at %d fps: the press to the release (frozen at %.4f) %s, %.3f back"):format(
			label,
			fps,
			frozen,
			table.concat(steps, " "),
			shift:Dot(stance.away)
		)
	)
	return shift:Dot(stance.away)
end

-- The plan's own step back at a clip time: the blade step and the keep-out together.
local function shownOf(plan: any): (number) -> number
	return function(clipTime: number): number
		return AimLogic.standOffAt(plan.distance, plan.from, plan.to, clipTime, Combat.contact.standOff.easing)
			+ (if plan.keep ~= nil then plan.keep(clipTime) else 0)
	end
end

describe("the Art stand-off waits for the activation hold (item 492(a), D-604)", function()
	it("a blade step: the root stands still on every row that draws the hold, then steps to the open", function()
		-- Lune's avatar meets an enemy with Vertical's start pose only behind its sword arm (the
		-- raised blade over the right shoulder): a kobold there, 2.8 studs off, calls for a 0.30
		-- step, the size the PC's boar1 rows add up to on the owner's larger avatar. Locked, or
		-- picked by the soft assist at the press (D-673), the stance's step back (0.43, D-606)
		-- already takes the blade clear of it, so here the soft assist picks it only at the
		-- release: no stance plan, and the release's plan steps 0.30.
		local target = kobold(120, -30, 2.8)
		for _, fps in { 30, 60, 144 } do
			local picked = cast(target, 2.8, fps, false)
			expect(judgeStance("blade step 0.30, picked at the press", fps, picked) > 0.4).toBe(true)
			expect(picked.plan.distance).toBe(0)
			local c = cast(target, 2.8, fps, false, true)
			local plan = c.plan
			expect(plan).never.toBeNil()
			expect(plan.distance).toBeCloseTo(0.3, 1e-6)
			expect(plan.to).toBe(OPEN)
			-- It waits for the hold's end: a 0.30 step from there to the open is under the speed.
			expect(c.released < HOLD_END).toBe(true)
			expect(plan.from).toBe(HOLD_END)
			expect(plan.still).toBe(HOLD_END)
			expect((c.held[#c.held].root - c.held[1].root).Magnitude).toBe(0)
			expect(c.releaseStep.Magnitude).toBe(0)
			judge("blade step 0.30", fps, c.rows, plan.away, shownOf(plan), plan.distance, 0)
		end
	end)

	it("the reach (D-424) at the kobold the capture stages 3.5 ahead waits for the hold too", function()
		local target = kobold(0, 0, 3.5)
		for _, fps in { 30, 60, 144 } do
			local c = cast(target, 3.5, fps, true)
			-- The stance's hands clear the kobold 3.5 ahead: it plans no step back.
			expect(judgeStance("reach 0.65", fps, c)).toBeCloseTo(0, 1e-6)
			local plan = c.plan
			expect(plan).never.toBeNil()
			-- No blade step: the start pose clears the kobold; the reach holds the blade out at the key.
			expect(plan.distance).toBe(0)
			expect(plan.still).toBe(HOLD_END)
			-- All of it by a plan sample past the open (the samples stand a 60 Hz frame apart from
			-- the release).
			local whole = plan.keep(OPEN + Combat.contact.standOff.keepOut.sampleSeconds)
			expect(whole > 0.5).toBe(true)
			-- Its 0.65 studs from the first 60 Hz sample past the hold's end to the snap need a hair
			-- more than the speed covers in that sample at 144 fps (the plan's samples start at the
			-- release, 0.1528 there); the speed's lead no longer starts it inside the hold (D-631:
			-- under 0.002 a row there before), so no row in the hold reads any of it at any rate.
			judge("reach 0.65", fps, c.rows, plan.away, plan.keep, whole, 0)
		end
	end)

	it("at a lock the stance steps back as it forms, the hold stands still, and the swing's step follows it", function()
		-- D-606 with D-604: a kobold behind the sword arm, 2.5 off at 110 degrees, square to the
		-- body, where the stance's hands reach it and the raised blade meets it from where the stance
		-- leaves the body, the largest blade step after a stance the kobold's placements give (0.25,
		-- Vertical's start pose; behind the sword arm at 120 degrees turned -30 the stance steps out
		-- of the whole start pose: 2.3 off, item 573(b)'s describe below, and 2.6 off now leave the
		-- release no blade step). The body steps back as the stance forms and stands still from the
		-- freeze; the release plans from where the root then stands (nothing of the stance's step
		-- counted twice, nothing taken back), and its 0.25 step waits for the hold's end like any
		-- other.
		local target = kobold(110, 0, 2.5)
		for _, fps in { 30, 60, 144 } do
			local c = cast(target, 2.8, fps, true)
			expect(judgeStance("stance, then blade step 0.25", fps, c) > 0.2).toBe(true)
			local plan = c.plan
			expect(plan).never.toBeNil()
			expect(plan.distance).toBeCloseTo(0.25, 1e-6)
			expect(plan.to).toBe(OPEN)
			expect(plan.from).toBe(HOLD_END)
			expect(plan.still).toBe(HOLD_END)
			judge("stance, then blade step 0.25", fps, c.rows, plan.away, shownOf(plan), plan.distance, 0)
		end
	end)
end)

-- Item M12s's open line (D-631): the keep-out's step-aside ran inside the hold at some
-- placements, up to 0.20 a 60 fps row sideways on the hold rows for a kobold 2.7 off at 130 degrees
-- turned 30 (0.64 in all unlocked, 0.42 locked), and the judges above read along `away` only. The
-- hold rows are read flat here, every direction: the frozen rows from the press to the release
-- and the release's rows that draw the clip up to the hold's end.
local KEEP_OUT = Combat.contact.standOff.keepOut

-- How deep the hit matrix avatar's hands and arms (keepOut.limbs) stand in `target`'s body parts
-- (what a blade may wound) with the controller's root at `frame`, at their deepest over the poses
-- Vertical shows from `clipTime` to the hold's end (every 1/240 s).
local function handsIn(target: any, frame: CFrame, clipTime: number): number
	local deepest = -math.huge
	local rootFrame = avatar.base * START:ToObjectSpace(frame)
	local time = math.min(clipTime, HOLD_END)
	while true do
		local solved = Pose.solve(avatar.model, rootFrame, ClipSampler.sample(vertical, time))
		for _, name in KEEP_OUT.limbs do
			local limb = avatar.model:FindFirstChild(name)
			local at = solved[name]
			if limb == nil or at == nil then
				continue
			end
			for _, part in target:GetDescendants() do
				if part:IsA("BasePart") and BladeContact.hurtbox(part) then
					deepest = math.max(deepest, (BodyShell.depth(at, limb.Size, part.CFrame, part.Size)))
				end
			end
		end
		if time >= HOLD_END then
			return deepest
		end
		time = math.min(time + 1 / 240, HOLD_END)
	end
end

-- Each hold row of a cast that moves the root (flat, any direction), with the clip that row's
-- screen drew before it and how far its step goes square to `away`: the frozen rows from the press
-- to the release, then the release's rows that draw the clip up to the hold's end.
type Moved = { clip: number, step: Vector3, before: Row, frozen: boolean }
local function holdMoves(c: Cast): ({ Moved }, number)
	local moved: { Moved } = {}
	local count = 0
	for index = 2, #c.held do
		if c.held[index - 1].clip >= c.released - 1e-9 then
			count += 1
			local step = c.held[index].root - c.held[index - 1].root
			step = Vector3.new(step.X, 0, step.Z)
			if step.Magnitude > 1e-6 then
				table.insert(
					moved,
					{ clip = c.held[index - 1].clip, step = step, before = c.held[index - 1], frozen = true }
				)
			end
		end
	end
	if c.releaseStep.Magnitude > 1e-6 then
		table.insert(moved, { clip = c.released, step = c.releaseStep, before = c.held[#c.held], frozen = true })
	end
	for index = 2, #c.rows do
		local drawn = c.rows[index - 1].clip
		if drawn <= HOLD_END + 1e-6 then
			count += 1
			local step = c.rows[index].root - c.rows[index - 1].root
			step = Vector3.new(step.X, 0, step.Z)
			if step.Magnitude > 1e-6 then
				table.insert(moved, { clip = drawn, step = step, before = c.rows[index - 1], frozen = false })
			end
		end
	end
	return moved, count
end

-- Judges a cast's hold rows (holdMoves) in every direction: the frozen rows and the release itself
-- move nothing, and no release row that draws the hold moves the root unless a hand or arm stood
-- in the kobold at the release (deeper than keepOut.depthEpsilon, the plan's own bar, over the poses
-- the hold still shows, where the root then stood), which the release's plan takes out there, or
-- the blade step is one too long for the speed from the hold's end (D-604), along `away` alone.
-- Returns the hold rows read, the hands' depth at the release, and the moving rows the hands' and
-- the blade step's.
local function judgeHold(label: string, fps: number, c: Cast, target: any): (number, number, number, number)
	local plan = c.plan
	local moved, count = holdMoves(c)
	local release = c.rows[1]
	local depth = handsIn(target, release.frame, release.clip)
	local early = plan ~= nil and plan.distance > 0 and plan.from < HOLD_END - 1e-6
	local hands, blade = 0, 0
	for _, move in moved do
		local square = if plan ~= nil
			then (move.step - plan.away * move.step:Dot(plan.away)).Magnitude
			else move.step.Magnitude
		if not move.frozen and depth > KEEP_OUT.depthEpsilon then
			hands += 1
		elseif not move.frozen and early and square <= 1e-6 then
			blade += 1
		else
			error(
				("%s at %d fps: a hold row drawing clip %.4f moves the root %.4f (%.4f square to away), the hands %.4f in the kobold at the release"):format(
					label,
					fps,
					move.clip,
					move.step.Magnitude,
					square,
					depth
				)
			)
		end
	end
	return count, depth, hands, blade
end

describe("the hold rows stand still in every direction (M12s, D-604, D-631)", function()
	it("at a kobold 2.7 off at 130 degrees turned 30, locked and not, at 30, 60 and 144", function()
		-- The placement M12s read the step-aside at. The keep-out's lead (back and aside) starts with
		-- the hold's end, under keepOut.maxSpeedStudsPerSecond from there, as the blade step does.
		-- Locked, or picked by the soft assist at the press (D-673), the stance took the held
		-- pose's hands out before the hold (D-606), and no hold row moves. Picked only at the
		-- release, nothing plans before it, and the frozen pose stands with its right hand in the
		-- kobold from the press on, so the release takes the hand out on its first rows (HandsOut's
		-- line) and does nothing more inside the hold.
		local target = kobold(130, 30, 2.7)
		for _, kind in { "locked", "unlocked", "picked late" } do
			local locked = kind == "locked"
			for _, fps in { 30, 60, 144 } do
				local c = cast(target, 2.8, fps, locked, kind == "picked late")
				local label = ("130/30/2.7 %s"):format(kind)
				local plan = c.plan
				expect(plan).never.toBeNil()
				expect(plan.still).toBe(HOLD_END)
				local count, depth, hands, blade = judgeHold(label, fps, c, target)
				local moves = holdMoves(c)
				local total = 0
				for _, move in moves do
					total += move.step.Magnitude
				end
				expect(count > 0).toBe(true)
				expect(blade).toBe(0)
				if kind ~= "picked late" then
					expect(hands).toBe(0)
				else
					-- What moves is the frozen pose's own need, the hand out (and the aside that step
					-- calls for off the axe's face), on the first rows of the release.
					expect(depth > KEEP_OUT.depthEpsilon).toBe(true)
				end
				-- The step-aside still lands, after the hold, within the speed on every row to the open.
				local aside = if plan.keepSide ~= nil then plan.keepSide(OPEN) else 0
				for index = 2, #c.rows do
					local drawn = c.rows[index - 1].clip
					if drawn > HOLD_END + 1e-6 and drawn < OPEN - 1e-6 then
						local step = c.rows[index].root - c.rows[index - 1].root
						local square = step - plan.away * step:Dot(plan.away)
						expect(Vector3.new(square.X, 0, square.Z).Magnitude <= SPEED / fps + 1e-6).toBe(true)
					end
				end
				print(
					("[M12s] %s at %d fps: %d hold rows, %d moved, %.3f in all (a hand %.3f in at the release); aside %.3f by the open, back %.3f"):format(
						label,
						fps,
						count,
						hands,
						total,
						depth,
						aside,
						shownOf(plan)(OPEN)
					)
				)
			end
		end
		target:Destroy()
	end)

	it("over a sweep of bearings, a hold row moves only to take a hand out of the kobold", function()
		-- Locked, or picked by the soft assist at the press (D-673), the stance takes the held pose's
		-- hands out before the hold (D-606); picked only at the release, nothing plans before the
		-- release, so where the frozen pose already stands with a hand in the
		-- kobold, or the hold's own poses bring one in (Vertical's hold key moves the arms on toward
		-- the anticipation), the release's plan takes it out on the hold rows (HandsOut's line),
		-- and nothing more: no step toward a sample past the hold. Here the lock is a point 2.8
		-- ahead, not the kobold, so the release turns the body to it after the stance's step aside
		-- and may leave a hair of a hand in (150/30: 0.007). Every other cast holds every hold row
		-- still, in every direction.
		local fps = 60
		local casts, still, inside, insideRows, blade = 0, 0, 0, 0, 0
		for _, bearing in { 0, 30, 60, 90, 120, 130, 150, 180, -30, -60, -90, -120, -150 } do
			for _, yaw in { -30, 30 } do
				local target = kobold(bearing, yaw, 2.7)
				for _, kind in { "locked", "unlocked", "picked late" } do
					casts += 1
					local c = cast(target, 2.8, fps, kind == "locked", kind == "picked late")
					local label = ("%d/%d/2.7 %s"):format(bearing, yaw, kind)
					local _, depth, hands, steps = judgeHold(label, fps, c, target)
					if hands + steps == 0 then
						still += 1
					end
					if depth > KEEP_OUT.depthEpsilon then
						inside += 1
					end
					insideRows += hands
					blade += steps
				end
				target:Destroy()
			end
		end
		print(
			("[M12s] the sweep at %d fps: %d casts, %d with every hold row still; %d with a hand in the kobold at the release, taken out on %d hold rows; %d rows the blade step's (D-604)"):format(
				fps,
				casts,
				still,
				inside,
				insideRows,
				blade
			)
		)
		expect(still > casts / 2).toBe(true)
	end)
end)

-- Item 516(e)(f)'s V516A_60_boar1 (D-644): A started 4.225 from the boar and stepped back 1.64
-- (z 35.775 to 34.135) to where every other take stood (5.86-5.90), the first move on the row
-- drawing 0.25114, then 0.097, 0.201, 0.216, 0.201, 0.185, 0.204 on the row drawing the open
-- 0.350227, and 0.192, 0.200 and 0.004 after it. A step that long cannot be whole by the open from a
-- tell that stands still: from the hold's end (0.25) the open (0.35) leaves 0.10 s, 1.2 studs at
-- keepOut.maxSpeedStudsPerSecond. The body's spacing is right by the strike's key (0.40, the
-- blade's contact), which is where the anime reading asks for it.
local function boar(distance: number, yaw: number): any
	local def = Enemies.byId("FrenzyBoar")
	local model = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local frame = avatar.base
		* CFrame.new(0, height - avatar.rootHeight, -distance)
		* CFrame.Angles(0, math.pi + math.rad(yaw), 0)
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	assert(RigBuilder.addBlocker(model) ~= nil, "no blocker for the boar")
	return model
end

describe("a stand-off step longer than the hold leaves the open (item 516(e)(f), D-644)", function()
	it("stands still through the tell, steps after it within the speed and is whole by the strike's key", function()
		-- The boar 4.225 ahead with its rump to A (Lune's boar there calls for 1.343 back, 1.180 after
		-- a lock's stance; 5.88 off it calls for none, as the PC's other takes). The keep-out's step
		-- is whole when the pose that leans deepest needs it, Vertical's strike (D-534), not by the
		-- open, which only the blade step and the reach are planned to (D-604). Back and aside are each held to
		-- keepOut.maxSpeedStudsPerSecond of the clip's clock (D-608), so a row's flat step may read up
		-- to that times the square root of 2 where both run.
		local key = RealContactPredictor.strikeKey(vertical, ClipSampler.hitWindows(vertical)[1])
		local target = boar(4.225, 180)
		local far = boar(5.88, 180)
		for _, kind in { "picked late", "unlocked", "locked" } do
			local locked = kind == "locked"
			local late = kind == "picked late"
			for _, fps in { 30, 60, 144 } do
				local label = ("boar 4.225 %s"):format(kind)
				local c = cast(target, 4.225, fps, locked, late)
				local plan = c.plan
				expect(plan).never.toBeNil()
				expect(plan.still).toBe(HOLD_END)
				-- Locked, or picked by the soft assist at the press, the stance steps back as it forms
				-- (D-606, D-673); picked only at the release, nothing moves before it.
				if not late then
					judgeStance(label, fps, c)
				else
					expect((c.held[#c.held].root - c.held[1].root).Magnitude).toBe(0)
				end
				expect(c.releaseStep.Magnitude).toBe(0)
				local final = c.rows[#c.rows].root
				local total = (final - c.rows[1].root).Magnitude
				expect(total > 1).toBe(true)
				local steps, firstDrawn, toOpen, wholeAt = {}, -1, 0, -1
				for index = 2, #c.rows do
					local drawn = c.rows[index - 1].clip
					local step = c.rows[index].root - c.rows[index - 1].root
					local flat = Vector3.new(step.X, 0, step.Z)
					local back = flat:Dot(plan.away)
					local aside = (flat - plan.away * back).Magnitude
					local advance = c.rows[index].clip - drawn
					local before = if index > 2 then drawn - c.rows[index - 2].clip else advance
					local bar = SPEED * math.max(advance, before) + 1e-6
					if flat.Magnitude > 1e-6 then
						table.insert(steps, ("%.3f@%.4f"):format(flat.Magnitude, drawn))
						if firstDrawn < 0 then
							firstDrawn = drawn
						end
					end
					-- The tell stands still: nothing moves on a row that draws the hold or before.
					if drawn <= HOLD_END + 1e-6 then
						expect(flat.Magnitude <= 1e-6).toBe(true)
					end
					expect(math.abs(back) <= bar).toBe(true)
					expect(aside <= bar).toBe(true)
					if drawn < OPEN - 1e-6 then
						toOpen += flat.Magnitude
					end
					-- Whole on the first row that draws the key: nothing moves after it.
					if drawn >= key - 1e-6 then
						if wholeAt < 0 then
							wholeAt = drawn
							expect((c.rows[index].root - final).Magnitude <= 1e-6).toBe(true)
						else
							expect(flat.Magnitude <= 1e-6).toBe(true)
						end
					end
				end
				expect(firstDrawn > HOLD_END).toBe(true)
				expect(wholeAt >= key - 1e-6).toBe(true)
				-- Not whole by the open: what item 516(e)'s line as written failed on.
				expect(total - toOpen > 0.3).toBe(true)
				print(
					("[516ef] %s at %d fps: first move on the row drawing %.4f, %.3f by the open, %.3f in all, whole by the row drawing %.4f (key %.3f) | %s"):format(
						label,
						fps,
						firstDrawn,
						toOpen,
						total,
						wholeAt,
						key,
						table.concat(steps, " ")
					)
				)
				-- 5.88 off the boar: no step at all, as the PC's other takes.
				local still = cast(far, 5.88, fps, locked, late)
				expect((still.rows[#still.rows].root - still.rows[1].root).Magnitude <= 1e-6).toBe(true)
			end
		end
		target:Destroy()
		far:Destroy()
	end)
end)

-- Item 539(a) (D-671): the locked Horizontal's hold rows moved on the PC at 522's rests (3.08 to
-- 3.18 off a kobold square on), 0.005-0.006 a row at 144 (drawn clip 0.159-0.216), 0.021-0.023 at
-- 60 and 0.030-0.031 at 30, about 1 stud/s whatever the rate. The stance (D-606) kept the hold
-- pose's parts out, but Horizontal's hold breathes (the left hand goes 0.005 to 0.0105 into the
-- kobold's torso from 0.15 to 0.25), and the release's plan took that breath out on the hold rows.
-- The stance now keeps out every pose its hold plays, to the hold's end. One Art cast at `fps`,
-- locked on a kobold `ahead` square in front, held 0.2 s and released: every hold row (the frozen
-- rows, the release itself, and the release's rows that draw the clip up to the hold's end) and
-- the most any of them moves the root, flat.
local function lockedHold(target: any, ahead: number, fps: number, slot: number): (number, number, number, number)
	local rig = load(target)
	local dt = 1 / fps
	for _ = 1, 40 do
		rig.frame(dt)
	end
	rig.setLock(START.Position + Vector3.new(0, 0, -ahead))
	local art = rig.controller.slots()[slot]
	rig.controller.beginArt(slot)
	local handle = rig.animator.mixer:find(art.clip)
	local ends = holdEnd(handle.clip)
	local held: { Row } = { { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame } }
	local holdFrames = math.ceil(0.2 * fps)
	for _ = 1, holdFrames do
		rig.frame(dt)
		table.insert(held, { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame })
	end
	local released = handle.time
	local before = rig.root.Position
	rig.controller.releaseArt(slot, holdFrames * dt)
	local rows: { Row } = { { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame } }
	local releaseStep = rig.root.Position - before
	while handle.time < ends + 0.05 do
		rig.frame(dt)
		table.insert(rows, { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame })
	end
	local count, moved, most = 0, 0, 0
	local function judge(step: Vector3)
		count += 1
		local flat = Vector3.new(step.X, 0, step.Z).Magnitude
		if flat > 1e-6 then
			moved += 1
		end
		most = math.max(most, flat)
	end
	for index = 2, #held do
		if held[index - 1].clip >= released - 1e-9 then
			judge(held[index].root - held[index - 1].root)
		end
	end
	judge(releaseStep)
	for index = 2, #rows do
		if rows[index - 1].clip <= ends + 1e-6 then
			judge(rows[index].root - rows[index - 1].root)
		end
	end
	local stance = rig.stances[1]
	local keep = if stance ~= nil and stance.plan ~= nil
		then stance.plan.keep(holdAt(handle.clip) + (stance.plan.wait or 0))
		else 0
	return count, moved, most, keep
end

describe("a locked Art's hold rows stand still at 522's rests (item 539(a), D-671)", function()
	it("every Art, locked on a kobold 3.08 and 3.18 square ahead, at 30, 60 and 144", function()
		-- d310ca7: the locked Horizontal's release rows moved 0.0029 / 0.0019 / 0.0007 at 60 and 7 rows
		-- of 0.0014 falling to 0.0002 at 144, straight back (the release's plan taking the hold's
		-- breath out); the stance kept 0.2254 / 0.1255 back. Now the stance keeps 0.2310 / 0.1310 and
		-- no hold row moves; Vertical, Rising Arc and Sharp Nail stood still before and do now.
		for _, distance in { 3.08, 3.18 } do
			local target = kobold(0, 0, distance)
			for slot = 1, 4 do
				for _, fps in { 30, 60, 144 } do
					local count, moved, most, keep = lockedHold(target, distance, fps, slot)
					print(
						("[539a] slot %d at %.2f, %d fps: %d hold rows, %d moved (most %.4f); the stance keeps %.4f back"):format(
							slot,
							distance,
							fps,
							count,
							moved,
							most,
							keep
						)
					)
					expect(count > 0).toBe(true)
					expect(moved).toBe(0)
				end
			end
			target:Destroy()
		end
	end)
end)

-- F1h's openIssue 1 (item 561(c)(f), D-672): at a tilted stop the keep-out's aside (D-315, off the
-- axe's face) came on Sharp Nail's first lunge row with the clip's own lunge, over the row's long-row
-- bar max(12 x dt, |m N|, |m N-1|) + 0.001 (Lune at 60 0.296-0.315 against 0.285). The aside now
-- shares the row's budget, max(12 x the clip's advance, |m|), with the lunge: the lunge gives up what
-- the aside needs on the row (only its free part, never into the room the cast left), the stand-off
-- takes that back as its own step, and what still does not fit is carried to the next rows.
describe("the keep-out's aside shares a lunge row's budget at a turned face (F1h, D-672)", function()
	it("Sharp Nail locked on a kobold turned 15 and 30 degrees, 2.9 to 3.5 ahead, at 60 and 144", function()
		-- d310ca7 at 60: every cast's first lunge row read 0.3252-0.3484 flat against 0.2863. Now
		-- every row with root motion stays within its bar, every other row within 12 x the clip's
		-- advance along and across the line, and the hands stay off the kobold (its axe included) at
		-- the strike's key.
		local sharpNail = Harness.load("src/shared/clips/player/OneHandedSword/SharpNail")
		local key = RealContactPredictor.strikeKey(sharpNail, ClipSampler.hitWindows(sharpNail)[1])
		local function motionAt(t: number): number
			local m = ClipSampler.rootMotionAt(sharpNail, t)
			return math.sqrt(m[1] * m[1] + m[3] * m[3])
		end
		local function handsAt(target: any, frame: CFrame, clipTime: number): number
			local rootFrame = avatar.base * START:ToObjectSpace(frame)
			local solved = Pose.solve(avatar.model, rootFrame, ClipSampler.sample(sharpNail, clipTime))
			local deepest = -math.huge
			for _, name in KEEP_OUT.limbs do
				local limb = avatar.model:FindFirstChild(name)
				for _, part in target:GetDescendants() do
					if
						limb ~= nil
						and solved[name] ~= nil
						and part:IsA("BasePart")
						and part.Name ~= KEEP_OUT.bodyFace
						and part.Name ~= KEEP_OUT.heldFace
					then
						deepest = math.max(deepest, (BodyShell.depth(solved[name], limb.Size, part.CFrame, part.Size)))
					end
				end
			end
			return deepest
		end
		for _, fps in { 60, 144 } do
			local dt = 1 / fps
			local lungeRows, lungeMost, otherMost, handMost = 0, -math.huge, -math.huge, -math.huge
			for _, yaw in { 15, 30 } do
				for _, distance in { 2.9, 3.2, 3.5 } do
					local target = kobold(0, yaw, distance)
					local rig = load(target)
					for _ = 1, 40 do
						rig.frame(dt)
					end
					rig.setLock(START.Position + Vector3.new(0, 0, -distance))
					local art = rig.controller.slots()[4]
					assert(art ~= nil and art.clip == "player/OneHandedSword/SharpNail", "quick slot 4 is Sharp Nail")
					rig.controller.beginArt(4)
					local handle = rig.animator.mixer:find(art.clip)
					local holdFrames = math.ceil(0.2 * fps)
					for _ = 1, holdFrames do
						rig.frame(dt)
					end
					rig.controller.releaseArt(4, holdFrames * dt)
					local rows: { Row } = { { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame } }
					while handle.time < 0.5 do
						rig.frame(dt)
						table.insert(rows, { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame })
					end
					local away = rig.asked[1].plan.away
					for index = 3, #rows do
						local step = rows[index].root - rows[index - 1].root
						local flat = Vector3.new(step.X, 0, step.Z)
						local m = math.abs(motionAt(rows[index].clip) - motionAt(rows[index - 1].clip))
						local mBefore = math.abs(motionAt(rows[index - 1].clip) - motionAt(rows[index - 2].clip))
						if math.max(m, mBefore) > 12 * dt then
							lungeRows += 1
							local bar = math.max(12 * dt, m, mBefore) + 0.001
							lungeMost = math.max(lungeMost, flat.Magnitude - bar)
							expect(flat.Magnitude <= bar).toBe(true)
						else
							local advance = math.max(
								rows[index].clip - rows[index - 1].clip,
								rows[index - 1].clip - rows[index - 2].clip,
								0
							)
							local back = math.abs(flat:Dot(away))
							local across = (flat - away * flat:Dot(away)).Magnitude
							local bar = 12 * advance + 0.001
							otherMost = math.max(otherMost, math.max(back, across) - bar)
							expect(math.max(back, across) <= bar).toBe(true)
						end
						local drawn = rows[index - 1].clip
						if drawn >= key - 1e-6 and drawn <= key + 0.04 then
							local hand = handsAt(target, rows[index].frame, drawn)
							handMost = math.max(handMost, hand)
							expect(hand <= KEEP_OUT.depthEpsilon).toBe(true)
						end
					end
					target:Destroy()
				end
			end
			print(
				("[F1h aside] %d fps: %d lunge rows, the most past the bar %+.4f; other rows %+.4f past 12 x c + 0.001; the hands at the key %+.3f"):format(
					fps,
					lungeRows,
					lungeMost,
					otherMost,
					handMost
				)
			)
			expect(lungeRows > 0).toBe(true)
		end
	end)
end)

-- Item 539(b) (D-673): the PC cleared the lock and pressed 2.65-2.94 from the kobold, and the root
-- moved while Q was held: Rising Arc 0.091 / 0.100 a row at 144 / 60, Horizontal up to 0.039 /
-- 0.036. The code moved nothing (an unlocked press planned no stance, D-606); Rising Arc's wind-up
-- leans the colliding Head (D-630) 0.17 to 0.29 into the kobold's HeldBlocker from clip 0.05, and
-- the engine pushed it out. An unlocked press now plans its stance off the soft assist's pick as a
-- locked press does, so the body steps off the axe as the start pose forms. One unlocked Art cast
-- at `fps`, the soft assist's pick `ahead` in front at the press (`picked` false: no pick at all),
-- held 0.2 s and released: a Cast (judgeStance's reading) and the deepest any colliding part
-- (keepOut.parts) stands in the kobold's Blocker or HeldBlocker on a row while the key is held, the
-- pose drawn there (the clip the row before stepped to) at the root the row ends on.
local function unlockedHold(target: any, ahead: number, fps: number, slot: number, picked: boolean): (Cast, number)
	local rig = load(target)
	local dt = 1 / fps
	for _ = 1, 40 do
		rig.frame(dt)
	end
	if picked then
		rig.setAssist(START.Position + Vector3.new(0, 0, -ahead))
	end
	local art = rig.controller.slots()[slot]
	local held: { Row } = { { clip = 0, root = rig.root.Position, frame = rig.root.CFrame } }
	rig.controller.beginArt(slot)
	local handle = rig.animator.mixer:find(art.clip)
	local holdFrames = math.ceil(0.2 * fps)
	for _ = 1, holdFrames do
		rig.frame(dt)
		table.insert(held, { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame })
	end
	local released = handle.time
	local before = rig.root.Position
	rig.controller.releaseArt(slot, holdFrames * dt)
	local deepest = -math.huge
	for index = 2, #held do
		local rootFrame = avatar.base * START:ToObjectSpace(held[index].frame)
		local solved = Pose.solve(avatar.model, rootFrame, ClipSampler.sample(handle.clip, held[index - 1].clip))
		for _, name in KEEP_OUT.parts do
			local part = avatar.model:FindFirstChild(name)
			for _, face in target:GetChildren() do
				if
					part ~= nil
					and solved[name] ~= nil
					and face:IsA("BasePart")
					and (face.Name == KEEP_OUT.bodyFace or face.Name == KEEP_OUT.heldFace)
				then
					deepest = math.max(deepest, (BodyShell.depth(solved[name], part.Size, face.CFrame, face.Size)))
				end
			end
		end
	end
	local c: Cast = {
		rows = {},
		plan = rig.asked[1] and rig.asked[1].plan,
		released = released,
		stance = rig.stances[1],
		held = held,
		releaseStep = rig.root.Position - before,
	}
	return c, deepest
end

describe("an unlocked Art's press steps off the kobold as its stance forms (item 539(b), D-673)", function()
	it("Rising Arc and Horizontal at the soft assist's pick 2.65 to 3.18 ahead, at 60 and 144", function()
		-- 9249281: no stance; the root held still while the key was held, with Rising Arc's Head
		-- 0.290 in the HeldBlocker for the engine to push out. Now the stance steps the body off as
		-- the start pose forms, within 12 x dt a row and never toward the kobold, whole by the first
		-- frozen row; the frozen rows stand still; and no colliding part stands in the kobold's
		-- blockers deeper than keepOut.depthEpsilon on any row while the key is held, so the engine
		-- has nothing to push and the whole step is the code's.
		for _, distance in { 2.65, 2.8, 2.94, 3.08, 3.18 } do
			local target = kobold(0, 0, distance)
			for _, slot in { 3, 1 } do
				for _, fps in { 60, 144 } do
					local label = ("slot %d unlocked at %.2f"):format(slot, distance)
					local c, deepest = unlockedHold(target, distance, fps, slot, true)
					expect(c.stance).never.toBeNil()
					local back = judgeStance(label, fps, c)
					local stance = c.stance.plan
					local aside = if stance.keepSide ~= nil then stance.keepSide(c.released + (stance.wait or 0)) else 0
					print(
						("[539b] %s at %d fps: the stance %.3f back, %.3f aside; the colliding parts at most %+.3f in the kobold's blockers while the key is held"):format(
							label,
							fps,
							back,
							aside,
							deepest
						)
					)
					expect(deepest <= KEEP_OUT.depthEpsilon).toBe(true)
				end
			end
			target:Destroy()
		end
	end)

	it("with no pick an unlocked press plans nothing and the root stands still while the key is held", function()
		local target = kobold(0, 0, 2.8)
		for _, fps in { 60, 144 } do
			local c = unlockedHold(target, 2.8, fps, 3, false)
			expect(c.stance).toBeNil()
			expect((c.held[#c.held].root - c.held[1].root).Magnitude).toBe(0)
			expect(c.releaseStep.Magnitude).toBe(0)
		end
		target:Destroy()
	end)
end)

-- Item 573(b) on 577a59a (D-686, D-687): the unlocked presses' stance rows (the press's first
-- rows, to the first frozen row) edged toward the kobold on Horizontal, Rising Arc and Sharp Nail,
-- at most 0.0048 / 0.025 / 0.017 a row at 60 and 0.008 / 0.014 / 0.009 at 144, and one Rising Arc
-- row at 144 moved 0.124 against its 12 x dt of 0.057. The code moves the root only along `away`
-- and `side`, by amounts that only grow, so from a kobold that stands still its own share never
-- nears it: what moved it there was the engine, pushing a colliding part out of the kobold's
-- blockers along a face turned to the line. The judges above read the pose the screen draws (the
-- clip the row before stepped to, D-342); the engine solves the pose the step writes (the clip at
-- the step) at the root the step leaves, and there the stance held two overlaps:
--
-- - D-674 holds a stance's back and aside together to the speed, but its series grew each to the
--   speed, so the aside fell behind it: Rising Arc's Head stood 0.065 / 0.036 in the axe's blocker
--   at 2.65 square ahead at 60 / 144, 0.173 / 0.147 at 10 degrees, 0.39 at 10 degrees with the
--   kobold turned 5, pushed out 0.07-0.09 of the push toward the kobold. The series now grows the
--   two together within the speed (D-686).
-- - A part the press found in a blocker (the cleared-lock walk-ins end 2.65-2.94 off, inside the
--   locked rests) was allowed to stay that deep: the stance kept it there through the hold, and
--   the engine pushed it out along the axe's face, 0.07-0.14 of the push toward the kobold. The
--   stance now steps it out as the start pose forms (D-687).
-- - The body was drawn on an even root through the hold (D-675: no clip moves the root), evened
--   where the root stood before the stance's step and left behind it, up to maxDrawnStuds, toward
--   the kobold: with the two above fixed, Rising Arc's drawn Head still stood 0.037-0.075 in the
--   axe's blocker square ahead 2.65-3.18 off at 60, 0.025-0.052 at 144, and Horizontal and Sharp
--   Nail were drawn up to 0.146 off their root (clear of the kobold). The body is now drawn on its
--   root while a stand-off moves it (D-688).

-- The deepest any colliding part (keepOut.parts) stands in the kobold's Blocker or HeldBlocker,
-- posed at clip time `clipTime` with the controller's root at `frame`.
local function solvedDepth(target: any, clip: any, clipTime: number, frame: CFrame): (number, string)
	local rootFrame = avatar.base * START:ToObjectSpace(frame)
	local solved = Pose.solve(avatar.model, rootFrame, ClipSampler.sample(clip, clipTime))
	local deepest, where = -math.huge, ""
	for _, name in KEEP_OUT.parts do
		local part = avatar.model:FindFirstChild(name)
		for _, face in target:GetChildren() do
			if
				part ~= nil
				and solved[name] ~= nil
				and face:IsA("BasePart")
				and (face.Name == KEEP_OUT.bodyFace or face.Name == KEEP_OUT.heldFace)
			then
				local depth = BodyShell.depth(solved[name], part.Size, face.CFrame, face.Size)
				if depth > deepest then
					deepest, where = depth, name .. " in " .. face.Name
				end
			end
		end
	end
	return deepest, where
end

-- One Art (quick slot `slot`) pressed at `fps` against `target`, locked on it or (`locked` false)
-- at the soft assist's pick of it (`seen`: at its real bearing, Rig.setAssist), held 0.2 s: each row from the press to the release, with the
-- clip the step stepped to and the root it left; the colliding parts' depth at the press; the
-- stance's plan (nil with none); and the kobold's root in the controller's world.
type Pressed = { rows: { Row }, pressDepth: number, plan: any, kobold: Vector3, clip: any, released: number }
local function press(target: any, fps: number, slot: number, locked: boolean, seen: boolean?): Pressed
	local rig = load(target)
	local dt = 1 / fps
	for _ = 1, 40 do
		rig.frame(dt)
	end
	local koboldAt = START:ToWorldSpace(avatar.base:ToObjectSpace(target.PrimaryPart.CFrame)).Position
	if locked then
		rig.setLock(koboldAt)
	else
		rig.setAssist(koboldAt, seen)
	end
	local art = rig.controller.slots()[slot]
	local clip = Harness.load("src/shared/clips/" .. art.clip)
	local pressDepth = solvedDepth(target, clip, 0, rig.root.CFrame)
	rig.controller.beginArt(slot)
	local handle = rig.animator.mixer:find(art.clip)
	assert(#rig.stances == 1, "the press at a lock or an assist pick asks for one stance plan")
	local rows: { Row } =
		{ { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame, body = rig.body() } }
	for _ = 1, math.ceil(0.2 * fps) do
		rig.frame(dt)
		table.insert(rows, { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame, body = rig.body() })
	end
	return {
		rows = rows,
		pressDepth = pressDepth,
		plan = rig.stances[1].plan,
		kobold = koboldAt,
		clip = clip,
		released = handle.time,
	}
end

-- Judges a press's rows by 498(b), read as the PC reads them: every row within 12 x dt flat and
-- never toward the kobold, along the stance's `away` and along the flat line from the kobold's root
-- to where the row starts; and still from the first frozen row. Returns the deepest any colliding
-- part stands on the stance's rows (the press's first rows, to the first frozen row) and on the
-- frozen rows, as the engine solves each row: the pose the step wrote at the root it left, on the
-- body's drawn offset from it where the frame draws one (D-675).
local function judgeSolved(label: string, fps: number, target: any, p: Pressed): (number, number)
	local stanceDeepest, heldDeepest = -math.huge, -math.huge
	for index = 2, #p.rows do
		local row, before = p.rows[index], p.rows[index - 1]
		local step = row.root - before.root
		step = Vector3.new(step.X, 0, step.Z)
		local line = before.root - p.kobold
		line = Vector3.new(line.X, 0, line.Z).Unit
		local along = step:Dot(line)
		if step.Magnitude > SPEED / fps + 1e-6 or along < -1e-6 then
			error(
				("%s at %d fps: the row stepping clip %.4f moves the root %.4f flat, %.5f along the line from the kobold (12 x dt %.4f)"):format(
					label,
					fps,
					row.clip,
					step.Magnitude,
					along,
					SPEED / fps
				)
			)
		end
		if p.plan ~= nil then
			expect(step:Dot(p.plan.away) >= -1e-6).toBe(true)
		end
		local depth = solvedDepth(target, p.clip, row.clip, row.body or row.frame)
		if before.clip >= p.released - 1e-9 then
			expect(step.Magnitude).toBe(0)
			heldDeepest = math.max(heldDeepest, depth)
		else
			stanceDeepest = math.max(stanceDeepest, depth)
		end
	end
	return stanceDeepest, heldDeepest
end

describe(
	"an unlocked Art's stance keeps its colliding parts out where the engine solves them (item 573(b), D-686)",
	function()
		it(
			"every Art at the soft assist's pick 2.65 to 3.18 off, square ahead and 10 degrees aside, at 60 and 144",
			function()
				-- 577a59a: Rising Arc's Head 0.065 / 0.036 in the axe's blocker at 2.65 square ahead at 60 /
				-- 144, 0.173 / 0.147 at 10 degrees; Horizontal, Vertical and Sharp Nail clear.
				local worst = {}
				for _, bearing in { 0, 10 } do
					for _, distance in { 2.65, 2.8, 2.94, 3.08, 3.18 } do
						local target = kobold(bearing, 0, distance)
						for slot = 1, 4 do
							for _, fps in { 60, 144 } do
								local label = ("slot %d at %.2f, %d degrees"):format(slot, distance, bearing)
								local p = press(target, fps, slot, false)
								expect(p.pressDepth <= KEEP_OUT.depthEpsilon).toBe(true)
								local stance, held = judgeSolved(label, fps, target, p)
								local key = ("slot %d at %d fps"):format(slot, fps)
								worst[key] = math.max(worst[key] or -math.huge, stance, held)
								if math.max(stance, held) > KEEP_OUT.depthEpsilon + 1e-6 then
									error(
										("%s at %d fps: a colliding part stands %.4f in the kobold's blockers on the stance's rows, %.4f on the frozen rows"):format(
											label,
											fps,
											stance,
											held
										)
									)
								end
							end
						end
						target:Destroy()
					end
				end
				for slot = 1, 4 do
					print(
						("[573b] slot %d: the deepest colliding part as solved %+.4f at 60, %+.4f at 144"):format(
							slot,
							worst[("slot %d at 60 fps"):format(slot)],
							worst[("slot %d at 144 fps"):format(slot)]
						)
					)
				end
			end
		)
	end
)

describe(
	"a press that finds a colliding part in the kobold's blocker steps it out as the stance forms (item 573(b), D-687)",
	function()
		it("every Art at the pick 2.65 to 2.94 off with the axe's blocker on the Head, at 60 and 144", function()
			-- The kobold turned 6 to 8 degrees, so its axe's blocker stands 0.010 to 0.080 over the Head
			-- at the press. 577a59a: the stance kept that depth through the hold (Horizontal's Head
			-- 0.076 in at 2.65), for the engine to push out along the axe's face, 0.07 to 0.14 of the push
			-- toward the kobold.
			for _, placement in { { 0, 8, 2.65 }, { 10, 6, 2.8 }, { -5, 6, 2.94 } } do
				local bearing, yaw, distance = placement[1], placement[2], placement[3]
				local target = kobold(bearing, yaw, distance)
				for slot = 1, 4 do
					for _, fps in { 60, 144 } do
						local label = ("slot %d at %.2f, %d degrees, turned %d"):format(slot, distance, bearing, yaw)
						local p = press(target, fps, slot, false)
						expect(p.pressDepth > KEEP_OUT.depthEpsilon).toBe(true)
						expect(p.plan).never.toBeNil()
						local stance, held = judgeSolved(label, fps, target, p)
						print(
							("[573b] %s at %d fps: %.4f in at the press, at most %+.4f on the stance's rows and %+.4f on the frozen rows"):format(
								label,
								fps,
								p.pressDepth,
								stance,
								held
							)
						)
						expect(held <= KEEP_OUT.depthEpsilon + 1e-6).toBe(true)
					end
				end
				target:Destroy()
			end
		end)

		it("a locked press with the torso in the kobold's body blocker, at 30, 60 and 144", function()
			-- The blade step's kobold behind the sword arm, 2.3 off at 120 degrees turned -30, where
			-- UpperTorso stands 0.206 in the kobold's Blocker at the press. 577a59a: the stance stepped
			-- 0.692 back, leaving the torso in the blocker on the wind-up's rows, and the release took a
			-- 0.25 blade step after the hold. Now the stance steps the torso out as it forms, 0.930 back
			-- by the hold pose, and the release has no step left to take.
			local target = kobold(120, -30, 2.3)
			for _, fps in { 30, 60, 144 } do
				local label = "Vertical at 2.3, 120 degrees, turned -30, locked"
				local p = press(target, fps, 2, true)
				expect(p.pressDepth > KEEP_OUT.depthEpsilon).toBe(true)
				local stance, held = judgeSolved(label, fps, target, p)
				local c = cast(target, 2.8, fps, true)
				local back = judgeStance(label, fps, c)
				print(
					("[573b] %s at %d fps: %.4f in at the press, at most %+.4f on the stance's rows and %+.4f on the frozen rows; the stance %.3f back, the release's blade step %.3f"):format(
						label,
						fps,
						p.pressDepth,
						stance,
						held,
						back,
						c.plan.distance
					)
				)
				expect(held <= KEEP_OUT.depthEpsilon + 1e-6).toBe(true)
				expect(c.plan.distance).toBe(0)
			end
			target:Destroy()
		end)
	end
)

describe(
	"a stance draws the body on the root its keep-out holds out, not on an even root behind it (item 573(b), D-688)",
	function()
		it("every Art at the pick 2.65 to 2.94 off, square ahead and 10 degrees aside, at 60 and 144", function()
			-- 577a59a with D-686 and D-687: the root itself within depthEpsilon, the body drawn on
			-- the even root left behind the stance's steps, up to 0.146 off it; Rising Arc's Head
			-- 0.037 / 0.043 / 0.054 in the axe's blocker at 2.65 / 2.8 / 2.94 square ahead at 60, and
			-- 0.028 / 0.025 / 0.032 at 144.
			for _, bearing in { 0, 10 } do
				for _, distance in { 2.65, 2.8, 2.94 } do
					local target = kobold(bearing, 0, distance)
					for slot = 1, 4 do
						for _, fps in { 60, 144 } do
							local label = ("slot %d at %.2f, %d degrees"):format(slot, distance, bearing)
							local p = press(target, fps, slot, false)
							expect(p.plan).never.toBeNil()
							local drawnOff = 0
							for index = 2, #p.rows do
								local row = p.rows[index]
								local body = row.body :: CFrame
								drawnOff = math.max(drawnOff, (body.Position - row.frame.Position).Magnitude)
							end
							local stance, held = judgeSolved(label, fps, target, p)
							if drawnOff > 1e-9 or math.max(stance, held) > KEEP_OUT.depthEpsilon + 1e-6 then
								error(
									("%s at %d fps: the body drawn %.4f off its root, a colliding part %.4f in the kobold's blockers on the stance's rows, %.4f on the frozen rows"):format(
										label,
										fps,
										drawnOff,
										stance,
										held
									)
								)
							end
						end
					end
					target:Destroy()
				end
			end
		end)
	end
)

-- G6e-4, item 573(b) on the PC (577a59a with G6e-3), the unlockB takes:
-- - The press planned no stance on any take (the code share 0.0000 on every row): the fighter faced
--   the kobold's axe along +X with the kobold 2.7-3.0 off at about 99 degrees, outside the soft
--   assist's 80 degree cone, so it had no pick. A stance now steps off the nearest enemy in the
--   assist's range at any bearing when there is no pick (D-689).
-- - Planned there, the stance's hands step back (Sharp Nail's 0.127) carried its torso along the
--   axe's face, turned to the stance's line, back into the axe's blocker the aside had just taken it
--   out of (0.029 as planned, 0.028 as solved, mid-stance). The faces are kept out again after any
--   step back past their own (D-690).
-- - The start pose formed faster than the body could step it out at 12 x dt: Rising Arc's Head
--   stood 0.12 in the axe's blocker on the first five rows at 144. The pose waits on its first pose
--   while the body steps (D-691), at most keepOut.stanceWaitSeconds, and the stance keeps its
--   parts within keepOut.stanceDepthStuds, under the held rows' 0.004.

-- A guard on how the start pose forms (not item 573(b)'s bar, which judgeStood below holds): judges
-- a stance's rows as `judgeSolved` does (12 x dt, never toward), and the start pose against
-- the press's own overlap: on every row before the first frozen one no colliding part stands deeper
-- than depthEpsilon, or than the press's pose (the clip at its first pose) stands at that row's
-- root, the overlap the body was already in at the press, which it steps out at the speed; what a
-- row may keep of it never grows from the row before; and the frozen rows stand within
-- stanceDepthStuds. Returns how far past what a stance row may keep its deepest part stands (0 at
-- most), the press's pose's overlap at the first row's root, and the deepest frozen row.
local function judgeForming(label: string, fps: number, target: any, p: Pressed): (number, number, number)
	local _, held = judgeSolved(label, fps, target, p)
	local past, first = -math.huge, -math.huge
	local kept = math.max(p.pressDepth, KEEP_OUT.depthEpsilon)
	for index = 2, #p.rows do
		local row = p.rows[index]
		if p.rows[index - 1].clip < p.released - 1e-9 then
			local frame = row.body or row.frame
			local depth = solvedDepth(target, p.clip, row.clip, frame)
			local own = solvedDepth(target, p.clip, 0, frame)
			if index == 2 then
				first = own
			end
			kept = math.max(math.min(own, kept), KEEP_OUT.depthEpsilon)
			past = math.max(past, depth - kept)
			if depth > kept + 1e-6 then
				error(
					("%s at %d fps: the row drawing clip %.4f stands %.4f in the kobold's blockers, where the press's pose leaves %.4f"):format(
						label,
						fps,
						row.clip,
						depth,
						kept
					)
				)
			end
		end
	end
	if held > KEEP_OUT.stanceDepthStuds + 1e-6 then
		error(("%s at %d fps: a frozen row stands %.4f in the kobold's blockers"):format(label, fps, held))
	end
	return past, first, held
end

describe("an unlocked press beside a kobold it does not face plans a stance (item 573(b), D-689 to D-691)", function()
	it("the PC's six unlockB takes, each at 60 and 144, at the kobold's real bearing", function()
		-- 874c250: no stance on any of them (the assist's cone holds no kobold at 99 degrees), and
		-- Lune's colliding parts stood up to 0.44 / 0.50 in the axe's blocker on the held rows
		-- (Rising Arc at 60 / 144) for the engine to push out. With the stance alone (D-689),
		-- Sharp Nail's torso stood 0.028 in mid-stance, Rising Arc's Head 0.12 on the first rows
		-- at 144 and Horizontal's frozen rows 0.0036.
		for _, take in
			{
				{ "H60", -59.5158, 69.0253, -90.1009, 1 },
				{ "RA60", -59.4285, 69.3646, -89.5342, 3 },
				{ "SN60", -59.3115, 69.3106, -87.1496, 4 },
				{ "H144", -59.4046, 69.3464, -86.8634, 1 },
				{ "RA144", -59.3562, 69.4136, -87.3195, 3 },
				{ "SN144", -59.3850, 69.3918, -88.8721, 4 },
			}
		do
			local target = pcKobold(take[2], take[3], take[4])
			for _, fps in { 60, 144 } do
				local label = ("%s (slot %d)"):format(take[1], take[5])
				local p = press(target, fps, take[5], false, true)
				expect(p.plan).never.toBeNil()
				local moved = (p.rows[#p.rows].root - p.rows[1].root).Magnitude
				expect(moved > 0.1).toBe(true)
				local past, first, held = judgeForming(label, fps, target, p)
				print(
					("[573b] PC %s at %d fps: %.4f in at the press, the stance %.3f in all with its pose waiting %.4f; the press's pose %+.4f at the first row's root, the rows at most %+.4f past it, the frozen rows %+.4f"):format(
						label,
						fps,
						p.pressDepth,
						moved,
						p.plan.wait or 0,
						first,
						past,
						held
					)
				)
			end
			target:Destroy()
		end
	end)
end)

describe("a stance's start pose forms only as fast as the body steps it out (item 573(b), D-691)", function()
	it(
		"every Art at the pick 2.65 to 3.18 off a kobold turned 5 to 8 degrees, square ahead and 10 aside, at 60 and 144",
		function()
			-- 874c250 (after G6e-3): the start pose formed into the axe's blocker faster than 12 x dt could
			-- step it out at 144 and the hands' step carried the torso back into it; a clear press at 2.65,
			-- 10 degrees, turned 5 read 0.0054 on its stance's rows. The release, the key and the server's
			-- clock are the clip's own (ActionLogic.syncPlan), and a 0.2 s tap still freezes at 573(a)'s
			-- clip: 0.150 at 60 and 0.153 at 144.
			local waited = { [60] = 0, [144] = 0 }
			for _, yaw in { 5, 6, 8 } do
				for _, bearing in { 0, 10 } do
					for _, distance in { 2.65, 2.8, 2.94, 3.08, 3.18 } do
						local target = kobold(bearing, yaw, distance)
						for slot = 1, 4 do
							for _, fps in { 60, 144 } do
								local label = ("slot %d at %.2f, %d degrees, turned %d"):format(
									slot,
									distance,
									bearing,
									yaw
								)
								local p = press(target, fps, slot, false)
								expect(p.plan).never.toBeNil()
								local wait = p.plan.wait or 0
								expect(wait <= KEEP_OUT.stanceWaitSeconds + 1e-6).toBe(true)
								waited[fps] = math.max(waited[fps], wait)
								expect(p.released).toBeCloseTo(math.ceil(holdAt(p.clip) * fps - 1e-6) / fps, 1e-6)
								local past = judgeForming(label, fps, target, p)
								if p.pressDepth <= KEEP_OUT.depthEpsilon then
									-- A clear press: every stance row within depthEpsilon.
									expect(past <= 1e-6).toBe(true)
								end
							end
						end
						target:Destroy()
					end
				end
			end
			for _, fps in { 60, 144 } do
				print(
					("[573b] the longest wait at %d fps: %.4f s, %d rows"):format(
						fps,
						waited[fps],
						math.ceil(waited[fps] * fps - 1e-6)
					)
				)
			end
		end
	)
end)

-- G6e-5, item 573(b)'s bar: no colliding part deeper than 0.004 on any row while Q is held, as the
-- PC's logger reads the parts the screen draws. With G6e-4 a press made where the PC's fighter
-- stood (its first pose up to 0.151 in the axe's blocker in Lune) read 0.022-0.083 on the first
-- one or two rows at 144, where one row steps 0.083 at most. Three things stood between the held
-- rows and the bar:
-- - The body stood in the blockers before the press: nothing kept a standing body out (the walk
--   stops at wallGapStuds, WalkShell; the PC's drawn Head stood 0.024-0.068 in the axe's blocker
--   at the press). A body standing free at an enemy steps out of its blockers now (D-692).
-- - The breath: Breathe's chest rise stood the drawn UpperTorso 0.029-0.039 deeper than the clip's
--   pose on the held rows. A held start pose holds its breath (D-693).
-- - The blend in: the start pose blends in from the drawn idle over the clip's blendIn, and the
--   stance kept only the clip's pose out: the drawn Head stood 0.006 in at 144 (Horizontal 2.65
--   square ahead of a kobold turned 8). It keeps the first pose out through the blend too
--   (D-694).
-- The kobold's blockers collide here, as CollisionGroups.assign switches them on in play, and the
-- body stands in the drawn idle Locomotion stands it in.
local BAR = 0.004 -- item 573(b): studs, the deepest a colliding part may stand on a held row
local DRAWN_IDLE = "player/OneHandedSword/IdleDrawn"

-- The deepest any colliding part stands in the kobold's Blocker or HeldBlocker in the pose the
-- mixer drew (`offsets`: the clip's blend in over the idle, and the breathing) on the root `frame`.
local function drawnDepth(target: any, offsets: any, frame: CFrame): number
	local solved = Pose.solve(avatar.model, avatar.base * START:ToObjectSpace(frame), offsets)
	local deepest = -math.huge
	for _, name in KEEP_OUT.parts do
		local part = avatar.model:FindFirstChild(name)
		for _, face in target:GetChildren() do
			if
				part ~= nil
				and solved[name] ~= nil
				and face:IsA("BasePart")
				and (face.Name == KEEP_OUT.bodyFace or face.Name == KEEP_OUT.heldFace)
			then
				deepest = math.max(deepest, (BodyShell.depth(solved[name], part.Size, face.CFrame, face.Size)))
			end
		end
	end
	return deepest
end

-- A press `press` makes after the body stood: the rows it stood (from the frame it appeared), the
-- pose the mixer drew on each of the press's rows (drawn[1] the press's own), and the press.
type Stood = { idle: { Row }, drawn: { any }, pressed: Pressed }

-- The fighter standing drawn at `target`, its blockers colliding, for 40 frames at `fps`, then one
-- Art (quick slot `slot`) pressed at the soft assist's pick (`seen`: at its real bearing) and
-- held 0.2 s, as `press` does.
local function stood(target: any, fps: number, slot: number, seen: boolean?): Stood
	for _, face in target:GetChildren() do
		if face:IsA("BasePart") and (face.Name == KEEP_OUT.bodyFace or face.Name == KEEP_OUT.heldFace) then
			face.CanCollide = true
		end
	end
	local rig = load(target)
	local dt = 1 / fps
	rig.animator:play(DRAWN_IDLE)
	local idle: { Row } = { { clip = 0, root = rig.root.Position, frame = rig.root.CFrame, body = rig.body() } }
	for _ = 1, 40 do
		rig.frame(dt)
		table.insert(idle, { clip = 0, root = rig.root.Position, frame = rig.root.CFrame, body = rig.body() })
	end
	local koboldAt = START:ToWorldSpace(avatar.base:ToObjectSpace(target.PrimaryPart.CFrame)).Position
	rig.setAssist(koboldAt, seen)
	local art = rig.controller.slots()[slot]
	local clip = Harness.load("src/shared/clips/" .. art.clip)
	local pressDepth = solvedDepth(target, clip, 0, rig.root.CFrame)
	local drawn = { rig.animator.mixer:lastOffsets() }
	rig.controller.beginArt(slot)
	local handle = rig.animator.mixer:find(art.clip)
	assert(#rig.stances == 1, "the press at an assist pick asks for one stance plan")
	local rows: { Row } =
		{ { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame, body = rig.body() } }
	for _ = 1, math.ceil(0.2 * fps) do
		rig.frame(dt)
		table.insert(rows, { clip = handle.time, root = rig.root.Position, frame = rig.root.CFrame, body = rig.body() })
		table.insert(drawn, rig.animator.mixer:lastOffsets())
	end
	return {
		idle = idle,
		drawn = drawn,
		pressed = {
			rows = rows,
			pressDepth = pressDepth,
			plan = rig.stances[1].plan,
			kobold = koboldAt,
			clip = clip,
			released = handle.time,
		},
	}
end

-- Judges a stood press by item 573(b)'s bar: every row it stood within 12 x dt flat and never
-- toward the kobold (along the line from its root to where the row starts); the held rows by
-- judgeSolved (12 x dt, never toward, still once frozen); and on the press's row and every held
-- row no colliding part deeper than BAR, as the clip poses it there (judgeSolved's reading) and
-- as the mixer drew it. A 0.2 s tap still freezes on the hold pose's frame. Returns the deepest
-- press, held row as the clip poses it, and held row as drawn.
local function judgeStood(label: string, fps: number, target: any, s: Stood): (number, number, number)
	local p = s.pressed
	for index = 2, #s.idle do
		local row, before = s.idle[index], s.idle[index - 1]
		local step = row.root - before.root
		step = Vector3.new(step.X, 0, step.Z)
		local line = before.root - p.kobold
		line = Vector3.new(line.X, 0, line.Z).Unit
		if step.Magnitude > SPEED / fps + 1e-6 or step:Dot(line) < -1e-6 then
			error(
				("%s at %d fps: standing row %d moves the root %.4f flat, %.5f along the line from the kobold (12 x dt %.4f)"):format(
					label,
					fps,
					index - 1,
					step.Magnitude,
					step:Dot(line),
					SPEED / fps
				)
			)
		end
	end
	judgeSolved(label, fps, target, p)
	expect(p.released).toBeCloseTo(math.ceil(holdAt(p.clip) * fps - 1e-6) / fps, 1e-6)
	expect((p.plan.wait or 0) <= KEEP_OUT.stanceWaitSeconds + 1e-6).toBe(true)
	local first = p.rows[1]
	local pressed = drawnDepth(target, s.drawn[1], first.body or first.frame)
	local posed, drawn = -math.huge, -math.huge
	for index = 2, #p.rows do
		local row = p.rows[index]
		local frame = row.body or row.frame
		local clipDepth = solvedDepth(target, p.clip, row.clip, frame)
		local drawnAt = drawnDepth(target, s.drawn[index], frame)
		if math.max(clipDepth, drawnAt) > BAR then
			error(
				("%s at %d fps: held row %d (clip %.4f) stands %.4f in the kobold's blockers as posed, %.4f as drawn (the bar %.4f)"):format(
					label,
					fps,
					index - 1,
					row.clip,
					clipDepth,
					drawnAt,
					BAR
				)
			)
		end
		posed, drawn = math.max(posed, clipDepth), math.max(drawn, drawnAt)
	end
	if pressed > BAR then
		error(
			("%s at %d fps: the press's row stands %.4f in the kobold's blockers as drawn"):format(label, fps, pressed)
		)
	end
	return pressed, posed, drawn
end

describe("no colliding part stands deeper than 0.004 on a held row (item 573(b), D-692 to D-694)", function()
	it("the PC's six unlockB takes, the body standing there first, at 60 and 144", function()
		for _, take in
			{
				{ "H60", -59.5158, 69.0253, -90.1009, 1 },
				{ "RA60", -59.4285, 69.3646, -89.5342, 3 },
				{ "SN60", -59.3115, 69.3106, -87.1496, 4 },
				{ "H144", -59.4046, 69.3464, -86.8634, 1 },
				{ "RA144", -59.3562, 69.4136, -87.3195, 3 },
				{ "SN144", -59.3850, 69.3918, -88.8721, 4 },
			}
		do
			local target = pcKobold(take[2], take[3], take[4])
			for _, fps in { 60, 144 } do
				local label = ("%s (slot %d)"):format(take[1], take[5])
				local s = stood(target, fps, take[5], true)
				local pressed, posed, drawn = judgeStood(label, fps, target, s)
				print(
					("[573b] PC %s at %d fps: stood %.4f out, the first pose %+.4f at the press; the press's row %+.4f, the held rows %+.4f posed and %+.4f drawn, the pose waiting %.4f"):format(
						label,
						fps,
						(s.idle[#s.idle].root - s.idle[1].root).Magnitude,
						s.pressed.pressDepth,
						pressed,
						posed,
						drawn,
						s.pressed.plan.wait or 0
					)
				)
			end
			target:Destroy()
		end
	end)

	it("every Art at the pick 2.65 to 3.18 off a kobold turned 5 to 8 degrees, square ahead and 10 aside", function()
		local worst = { [60] = { -math.huge, -math.huge, -math.huge }, [144] = { -math.huge, -math.huge, -math.huge } }
		for _, yaw in { 5, 6, 8 } do
			for _, bearing in { 0, 10 } do
				for _, distance in { 2.65, 2.8, 2.94, 3.08, 3.18 } do
					local target = kobold(bearing, yaw, distance)
					for slot = 1, 4 do
						for _, fps in { 60, 144 } do
							local label = ("slot %d at %.2f, %d degrees, turned %d"):format(
								slot,
								distance,
								bearing,
								yaw
							)
							local pressed, posed, drawn = judgeStood(label, fps, target, stood(target, fps, slot))
							local w = worst[fps]
							w[1], w[2], w[3] = math.max(w[1], pressed), math.max(w[2], posed), math.max(w[3], drawn)
						end
					end
					target:Destroy()
				end
			end
		end
		for _, fps in { 60, 144 } do
			local w = worst[fps]
			print(
				("[573b] the turned grid at %d fps: the press's row %+.4f, the held rows %+.4f posed and %+.4f drawn"):format(
					fps,
					w[1],
					w[2],
					w[3]
				)
			)
		end
	end)
end)
