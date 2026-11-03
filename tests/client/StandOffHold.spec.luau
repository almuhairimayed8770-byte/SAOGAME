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

local CONTROLLER_PATH = "src/client/controllers/CharacterController"
local CHOREO_PATH = "src/client/choreo/Choreo"
local MOVE_INPUT_PATH = "src/client/controllers/MoveInput"
local PHYSICS = 1 / 60 -- the fake physics' step (the root never walks here)
local SPEED: number = Combat.contact.standOff.keepOut.maxSpeedStudsPerSecond
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
	-- With no lock, the soft assist's pick: an enemy standing at `position` (no stance plan, D-606).
	setAssist: (position: Vector3) -> (),
	-- What the controller asked ContactPredictor.standOff for a swing, and the plan it was handed.
	asked: { { from: number, root: CFrame, options: any, plan: any } },
	-- The held start pose's asks at the press (options.stance, D-606), kept apart from the swing's.
	stances: { { from: number, root: CFrame, options: any, plan: any } },
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
	local locomotion = {
		new = function(): any
			return {
				serverDrawn = function(): boolean
					return false
				end,
				update = function() end,
			}
		end,
	}
	local targetController = {
		current = function(): any
			return lockRecord
		end,
		assistCandidates = function(): { any }
			-- The pick straight ahead, as the lock is: the request's facing does not turn.
			return if assistRecord ~= nil
				then {
					{
						id = assistRecord.id,
						distance = (assistRecord.model.PrimaryPart.Position - START.Position).Magnitude,
						bearing = 0,
					},
				}
				else {}
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
					}
					else nil
				table.insert(
					if options.stance ~= nil then stances else asked,
					{ from = from, root = rootCFrame, options = options, plan = plan }
				)
				return plan
			end,
			targetMotion = RealContactPredictor.targetMotion,
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
		setAssist = function(position: Vector3)
			assistRecord = { id = 1, kind = "Enemy", state = "Idle", model = { PrimaryPart = { Position = position } } }
		end,
		asked = asked,
		stances = stances,
	}
end

-- One row as item 397's logger reads it at Last+2: the clip the frame stepped to, and the root.
type Row = { clip: number, root: Vector3, frame: CFrame }

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
	local whole = stance.away * stance.keep(frozen)
		+ (
			if stance.side ~= nil and stance.keepSide ~= nil
				then stance.side * stance.keepSide(frozen)
				else Vector3.zero
		)
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
		-- D-606 with D-604: the blade step's kobold behind the sword arm, half a stud nearer
		-- (2.3 off at 120 degrees, turned -30). The stance's hands reach it, so the body steps back as the stance forms and stands still from
		-- the freeze; the release plans from where the root then stands (nothing of the stance's
		-- step counted twice, nothing taken back), and the raised blade still meets the kobold from
		-- there, so its 0.25 step waits for the hold's end like any other.
		local target = kobold(120, -30, 2.3)
		for _, fps in { 30, 60, 144 } do
			local c = cast(target, 2.8, fps, true)
			expect(judgeStance("stance, then blade step 0.25", fps, c) > 0.5).toBe(true)
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
	local keep = if stance ~= nil and stance.plan ~= nil then stance.plan.keep(holdAt(handle.clip)) else 0
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
					local aside = if stance.keepSide ~= nil then stance.keepSide(c.released) else 0
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
