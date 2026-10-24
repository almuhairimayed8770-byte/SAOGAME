--!strict
--[[
	What the player sees on a charging boar follows its drawn body, not its lagging root (D-193).

	The real path: a RigBuilder Boar posed every 60 fps frame by a real Choreo animator, the remotes
	going through the real Replication (RushDraw draws the body on the server's timeline, D-171), its
	plate from a real Nameplates, the SWITCH prompt from a real Hud, and the lock framed by a real
	CameraController. The root part is the server's body shown `lag` seconds late (0.25 s, and 0.5 s
	for a first move after a long stand); the remotes arrive `LATENCY` after they are sent.

	Each frame the plate's anchor (its adornee, the root part, plus StudsOffsetWorldSpace, less its
	own height) is held against the drawn body (the root part moved by the animator's body offset),
	and the lock camera against an ideal one locked on a stand-in rig standing exactly on the drawn
	body. The rig steps before the camera here; with `order` the frame is the engine's instead:
	Choreo's own frame loop and the real camera run on one list of render steps, with RenderStepped
	connections before or after every bound step (the engine pins neither, D-201).
]]

local luau = require("@lune/luau")

local function frameSignal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
Harness.stubService("RunService", {
	RenderStepped = frameSignal(),
	Heartbeat = frameSignal(),
	PreSimulation = frameSignal(),
	-- Choreo's rig step (bound before every reader of a pose, D-211): the spec steps the rig itself.
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

-- The engine's render steps for `order` runs: RenderStepped connections and bound steps (by
-- priority, a name bound again replacing its step), shared by a fresh Choreo and the lock camera.
type Bound = { name: string, priority: number, fn: (dt: number) -> () }
local connections: { (dt: number) -> () } = {}
local bound: { Bound } = {}
local function bind(name: string, priority: number, fn: (dt: number) -> ())
	for index, entry in bound do
		if entry.name == name then
			table.remove(bound, index)
			break
		end
	end
	table.insert(bound, { name = name, priority = priority, fn = fn })
	table.sort(bound, function(a, b)
		return a.priority < b.priority
	end)
end
local engineRunService = {
	RenderStepped = {
		Connect = function(_self: any, fn: (dt: number) -> ()): any
			table.insert(connections, fn)
			return { Disconnect = function() end }
		end,
	},
	Heartbeat = frameSignal(),
	PreSimulation = frameSignal(),
	BindToRenderStep = function(_self: any, name: string, priority: number, fn: (dt: number) -> ())
		bind(name, priority, fn)
	end,
	UnbindFromRenderStep = function() end,
}

-- One engine frame: RenderStepped's connections before or after every bound step.
local function engineFrame(order: string)
	if order == "RenderStepped first" then
		for _, fn in connections do
			fn(1 / 60)
		end
	end
	for _, entry in table.clone(bound) do
		entry.fn(1 / 60)
	end
	if order ~= "RenderStepped first" then
		for _, fn in connections do
			fn(1 / 60)
		end
	end
end

local Choreo = Harness.load("src/client/choreo/Choreo")
local Replication = Harness.load("src/client/controllers/Replication")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Enemies = Harness.load("src/shared/data/enemies")
local AI = Harness.load("src/shared/data/ai")
local UI = Harness.load("src/shared/data/ui")
local Combat = Harness.load("src/shared/data/combat")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Engine = Harness.load("src/client/fx/Engine")

local FRAME = 1 / 60
local LATENCY = 0.05
local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]
local SPEED: number = AI.rushSpeed(CHARGE)
local LENGTH: number = CHARGE.reach + AI.archetypes.Charger.overshoot
local PLATE_LIFT = Vector3.new(0, UI.nameplates.enemy.offsetStuds, 0)
local SWITCH_LIFT = Vector3.new(0, UI.hud.switchPrompt.heightStuds, 0)
-- One frame of the run's own travel at the rush speed.
local FRAME_TRAVEL = SPEED * FRAME
-- Vector3 is single precision: positions some tens of studs out agree to about this.
local EPSILON = 1e-3

local clock = 0
Choreo.configure({
	now = function()
		return clock
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
Engine.setClock(function()
	return clock
end)
Engine.setViewer(function()
	return Vector3.zero
end)

local function recorder(): any
	return setmetatable({}, {
		__index = function(_self: any, _key: string): any
			return function(): any
				return nil
			end
		end,
	})
end

-- A fresh copy of a client module: its own state, the shared modules (DrawnBody, Engine) under it.
local function fresh(path: string, overrides: { [string]: any }?): any
	local env = Harness.environment()
	env.script = Harness.node(path)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	if overrides ~= nil then
		for key, value in overrides do
			env[key] = value
		end
	end
	return luau.load(Harness.readFile(path .. ".luau"), { debugName = path, environment = env :: any })()
end

-- A fresh Choreo whose frame loop runs on the engine's render steps (its own registry and loops:
-- the shared copy started on another spec's engine).
local function engineChoreo(): any
	table.clear(connections)
	local choreo = fresh("src/client/choreo/Choreo", {
		game = {
			GetService = function(_self: any, name: string): any
				if name == "RunService" then
					return engineRunService
				end
				return Harness.game():GetService(name)
			end,
		},
	})
	choreo.configure({
		now = function()
			return clock
		end,
		cameraPosition = function()
			return Vector3.zero
		end,
	})
	return choreo
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function angle(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

local WIND_UP_START = 10
local LAUNCH = WIND_UP_START + CHARGE.windUp
local ORIGIN = Vector3.new(10, 3, 20)
local DIRECTION = Vector3.new(1, 0, -1).Unit
local RIGHT = DIRECTION:Cross(Vector3.yAxis).Unit
-- The player sidestepped the charge: 10 studs down the line, 4 to its side.
local PLAYER = ORIGIN + DIRECTION * 10 + RIGHT * 4

local function part(name: string, position: Vector3, size: Vector3, parent: Instance): BasePart
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.CFrame = CFrame.new(position)
	created.Position = position
	created.Parent = parent
	return created
end

local function character(name: string, position: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.PrimaryPart = part("HumanoidRootPart", position, Vector3.new(2, 2, 1), model)
	Instance.new("Humanoid").Parent = model
	model.Parent = parent
	return model
end

type Cam = { controller: any, camera: any, steps: { { priority: number, fn: (number) -> () } } }

-- A real CameraController with a fake engine around it (as CameraFraming.spec), its render steps
-- collected so the frame can run them by hand, or (`engine`) bound with the engine's.
local function makeCamera(subject: Model, engine: boolean?): Cam
	local steps: { { priority: number, fn: (number) -> () } } = {}
	local signal = { Connect = function() end }
	local camera = { CFrame = CFrame.new(0, 10, 20), FieldOfView = 70, CameraType = nil, Focus = CFrame.new() }
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, name: string, priority: number, fn: (number) -> ())
				if engine then
					bind(name, priority, fn)
					return
				end
				table.insert(steps, { priority = priority, fn = fn })
				table.sort(steps, function(a, b)
					return a.priority < b.priority
				end)
			end,
		},
		UserInputService = {
			MouseEnabled = true,
			TouchEnabled = false,
			MouseBehavior = nil,
			InputChanged = signal,
			LastInputTypeChanged = signal,
		},
		Players = { LocalPlayer = { Character = subject, CharacterAdded = signal, CharacterRemoving = signal } },
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local controller = fresh("src/client/camera/CameraController", {
		game = {
			GetService = function(_self: any, name: string): any
				return services[name]
			end,
		},
		workspace = {
			CurrentCamera = camera,
			Spherecast = function(): any
				return nil
			end,
		},
		RaycastParams = {
			new = function(): any
				return {}
			end,
		},
		os = {
			clock = function(): number
				return clock
			end,
		},
	})
	controller.start()
	return { controller = controller, camera = camera, steps = steps }
end

local function stepCamera(cam: Cam)
	for _, step in cam.steps do
		step.fn(FRAME)
	end
end

type Options = {
	lag: number,
	deathAt: number?, -- seconds after the launch the server kills it
	staggerAt: number?, -- seconds after the launch a parry staggers it (and opens a Switch window)
	frames: number?,
	-- The engine's frame ("RenderStepped first" or "RenderStepped last") steps the rig and the lock
	-- camera instead of the spec (nil: the rig, then the camera, by hand).
	order: string?,
}

type Row = {
	t: number,
	drawing: boolean, -- the animator draws the body off its root this frame
	drawn: Vector3, -- the drawn body
	rootGap: number, -- flat studs from the root part to the drawn body
	plate: Vector3?, -- the plate's anchor, flat studs from the drawn body below
	plateGap: number?,
	plateLift: Vector3?, -- the plate's StudsOffsetWorldSpace
	switchGap: number?, -- the SWITCH prompt's anchor from the drawn body, while it shows
	switchLift: Vector3?, -- the SWITCH billboard's StudsOffsetWorldSpace
	camGap: number, -- studs from the lock camera to the ideal one
	camTurn: number, -- degrees from the lock camera's look to the ideal one's
	camStep: number, -- studs the lock camera moved this frame
	idealStep: number, -- studs the ideal camera moved this frame
	locked: boolean,
}

local function run(options: Options): { Row }
	clock = WIND_UP_START - 0.4
	local order = options.order
	local choreo = if order ~= nil then engineChoreo() else Choreo
	local world = Instance.new("Folder")
	local model = RigBuilder.build("Boar")
	local root = model.PrimaryPart :: BasePart
	root.LocalTransparencyModifier = 0
	local function place(frame: CFrame)
		root.CFrame = frame
		root.Position = frame.Position
	end
	place(CFrame.lookAt(ORIGIN, ORIGIN + DIRECTION))
	model.Parent = world
	local record = {
		id = 5,
		model = model,
		kind = "Enemy",
		defId = BOAR.id,
		rig = BOAR.skin,
		name = "Frenzy Boar",
		state = "Idle",
		hp = 100,
		maxHp = 120,
		gauge = 10,
		maxGauge = 10,
	}
	local hero = character("Hero", PLAYER, world)
	local me = { id = 1, model = hero, kind = "Player", state = "Idle", weaponId = "TrialistSword" }
	local myAnimator = recorder()
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == 5 then record elseif id == 1 then me else nil
			end,
		},
		localId = function(): number?
			return 1
		end,
		locomotion = recorder(),
		choreo = {
			get = function(target: any): any
				return if target == hero then myAnimator else choreo.get(target)
			end,
		},
		clipLibrary = ClipLibrary,
		trails = recorder(),
		smear = recorder(),
		shatter = recorder(),
		sparks = recorder(),
		telegraphs = recorder(),
		outline = recorder(),
		switchRing = recorder(),
		digits = recorder(),
		hud = recorder(),
		systemLine = recorder(),
		sfx = recorder(),
		impact = recorder(),
		camera = recorder(),
		weaponCategory = function(): string
			return "OneHandedSword"
		end,
		trailToken = function(): string
			return "TrailCyanWhite"
		end,
		positionOf = function(): Vector3
			return Vector3.zero
		end,
		schedule = function() end,
		now = function(): number
			return clock
		end,
		serverNow = function(): number
			return clock
		end,
	} :: any)
	local animator = choreo.get(model)
	animator:step(FRAME)
	local Nameplates = fresh("src/client/ui/Nameplates")
	local Hud = fresh("src/client/ui/Hud")
	Nameplates.attach(record)
	local plate = Nameplates.plateOf(5)
	expect(plate).never.toBeNil()

	-- The lock camera on the boar, and the ideal one on a stand-in standing on the drawn body.
	local proxy = character("Proxy", root.Position, world)
	local proxyRoot = proxy.PrimaryPart :: BasePart
	local actual = makeCamera(hero, order ~= nil)
	local ideal = makeCamera(hero)
	for _ = 1, 30 do
		clock += FRAME
		if order ~= nil then
			engineFrame(order)
		else
			stepCamera(actual)
		end
		stepCamera(ideal)
	end
	actual.controller.setLockTarget(model)
	ideal.controller.setLockTarget(proxy)
	local locked = true

	type Message = { at: number, name: string, payload: any, sent: boolean?, apply: (() -> ())? }
	local messages: { Message } = {
		{
			at = WIND_UP_START + LATENCY,
			name = "Telegraph",
			payload = {
				entityId = 5,
				attackId = CHARGE.id,
				kind = CHARGE.telegraph,
				windUp = CHARGE.windUp,
				serverTime = WIND_UP_START,
				origin = vec(ORIGIN),
				facing = vec(DIRECTION),
			},
		},
		{
			at = WIND_UP_START + LATENCY,
			name = "ActionStarted",
			payload = {
				entityId = 5,
				clipId = "enemy/" .. BOAR.skin .. "/" .. CHARGE.clip,
				serverTime = WIND_UP_START,
				facing = vec(DIRECTION),
			},
		},
		{
			at = LAUNCH + LATENCY,
			name = "RushStarted",
			payload = {
				entityId = 5,
				attackId = CHARGE.id,
				serverTime = LAUNCH,
				origin = vec(ORIGIN),
				direction = vec(DIRECTION),
				speed = SPEED,
				duration = LENGTH / SPEED,
			},
		},
	}
	local stopAt: number? = options.deathAt or options.staggerAt
	if options.deathAt ~= nil then
		local at = options.deathAt :: number
		table.insert(messages, {
			at = LAUNCH + at + LATENCY,
			name = "EntityDied",
			payload = {
				entityId = 5,
				position = vec(ORIGIN + DIRECTION * SPEED * at),
				shatter = "Beast",
				name = "Boar",
			},
			apply = function()
				record.state = "Dead"
				Nameplates.refresh(record)
				-- TargetController drops the lock on a death.
				actual.controller.setLockTarget(nil)
				ideal.controller.setLockTarget(nil)
				locked = false
			end,
		})
		table.insert(messages, {
			at = LAUNCH + at + LATENCY,
			name = "RushEnded",
			payload = {
				entityId = 5,
				reason = "Died",
				launchedAt = LAUNCH,
				serverTime = LAUNCH + at,
				distance = SPEED * at,
			},
		})
	end
	if options.staggerAt ~= nil then
		local at = options.staggerAt :: number
		table.insert(messages, {
			at = LAUNCH + at + LATENCY,
			name = "StateChanged",
			payload = { entityId = 5, state = "Stagger", duration = 0.6, direction = "Front" },
			apply = function()
				-- The parry's Switch window: SWITCH over the staggered boar.
				Hud.showSwitchPrompt(Combat.switchWindow, model, nil)
			end,
		})
		table.insert(messages, {
			at = LAUNCH + at + LATENCY,
			name = "RushEnded",
			payload = {
				entityId = 5,
				reason = "Interrupted",
				launchedAt = LAUNCH,
				serverTime = LAUNCH + at,
				distance = SPEED * at,
			},
		})
	end
	local billboard = Hud.gui():FindFirstChild("SwitchBillboard") :: BillboardGui

	local rows: { Row } = {}
	local lastCam: CFrame? = nil
	local lastIdeal: CFrame? = nil
	clock = WIND_UP_START - 0.2
	for _ = 1, options.frames or 200 do
		clock += FRAME
		for _, message in messages do
			if not message.sent and clock >= message.at - 1e-9 then
				message.sent = true
				Replication.dispatch(message.name, message.payload)
				if message.apply ~= nil then
					message.apply()
				end
			end
		end
		-- The root part: the server's body `lag` seconds ago, stopped where it died or was staggered.
		local d = math.clamp(SPEED * (clock - options.lag - LAUNCH), 0, LENGTH)
		if stopAt ~= nil then
			d = math.min(d, SPEED * stopAt)
		end
		local position = ORIGIN + DIRECTION * d
		place(CFrame.lookAt(position, position + DIRECTION))
		if order ~= nil then
			engineFrame(order)
		else
			animator:step(FRAME)
		end
		local offset: CFrame? = (animator :: any).bodyOffset
		local drawn = root.CFrame * (offset or CFrame.identity)
		proxyRoot.CFrame = drawn
		proxyRoot.Position = drawn.Position
		if order == nil then
			stepCamera(actual)
		end
		stepCamera(ideal)
		Nameplates.step(FRAME)
		Hud.step(FRAME)
		local row: Row = {
			t = clock - LAUNCH,
			drawing = offset ~= nil,
			drawn = drawn.Position,
			rootGap = (flat(root.CFrame.Position) - flat(drawn.Position)).Magnitude,
			camGap = (actual.camera.CFrame.Position - ideal.camera.CFrame.Position).Magnitude,
			camTurn = angle(actual.camera.CFrame.LookVector, ideal.camera.CFrame.LookVector),
			camStep = if lastCam ~= nil then (actual.camera.CFrame.Position - lastCam.Position).Magnitude else 0,
			idealStep = if lastIdeal ~= nil then (ideal.camera.CFrame.Position - lastIdeal.Position).Magnitude else 0,
			locked = locked,
		}
		if plate.gui.Enabled and not plate.gone then
			local adornee = plate.gui.Adornee :: BasePart
			row.plate = adornee.CFrame.Position + plate.gui.StudsOffsetWorldSpace - PLATE_LIFT
			row.plateGap = (flat(row.plate :: Vector3) - flat(drawn.Position)).Magnitude
		end
		row.plateLift = plate.gui.StudsOffsetWorldSpace
		if billboard.Enabled then
			local adornee = billboard.Adornee :: BasePart
			local anchor = adornee.CFrame.Position + billboard.StudsOffsetWorldSpace - SWITCH_LIFT
			row.switchGap = (flat(anchor) - flat(drawn.Position)).Magnitude
		end
		row.switchLift = billboard.StudsOffsetWorldSpace
		table.insert(rows, row)
		lastCam = actual.camera.CFrame
		lastIdeal = ideal.camera.CFrame
	end
	Nameplates.detach(record)
	choreo.release(model)
	return rows
end

-- The largest of `pick` over the rows from the launch on.
local function most(rows: { Row }, pick: (Row) -> number?): number
	local best = 0
	for _, row in rows do
		if row.t >= -FRAME then
			local value = pick(row)
			if value ~= nil then
				best = math.max(best, value)
			end
		end
	end
	return best
end

-- The index of the last frame the body is drawn off its root.
local function lastDrawn(rows: { Row }): number
	local last = 0
	for index, row in rows do
		if row.drawing then
			last = index
		end
	end
	return last
end

describe("a charging boar's plate and lock camera follow its drawn body (D-193)", function()
	for _, lag in { 0.25, 0.5 } do
		it(("keeps the plate over the body every frame at %.2f s of root lag"):format(lag), function()
			local rows = run({ lag = lag })
			-- The root trails the body by most of a lag's run: what the plate used to stand over.
			expect(most(rows, function(row)
				return if row.drawing then row.rootGap else nil
			end)).toBeGreaterThan(SPEED * lag * 0.9)
			expect(most(rows, function(row)
				return row.plateGap
			end)).toBeLessThan(EPSILON)
			-- Back on its own height over the root once the body is back on it.
			local last = lastDrawn(rows)
			expect(last).toBeGreaterThan(0)
			expect(last).toBeLessThan(#rows)
			expect(((rows[#rows].plateLift :: Vector3) - PLATE_LIFT).Magnitude).toBeLessThan(EPSILON)
		end)

		it(("frames the lock on the drawn body at %.2f s of root lag"):format(lag), function()
			local rows = run({ lag = lag })
			expect(most(rows, function(row)
				return row.camGap
			end)).toBeLessThan(0.02)
			expect(most(rows, function(row)
				return row.camTurn
			end)).toBeLessThan(0.25)
		end)

		it(("hands the plate and the lock back onto the root with no pop at %.2f s of root lag"):format(lag), function()
			local rows = run({ lag = lag })
			local last = lastDrawn(rows)
			for index = math.max(2, last - 8), math.min(#rows, last + 8) do
				local row, previous = rows[index], rows[index - 1]
				local plateStep = (flat(row.plate :: Vector3) - flat(previous.plate :: Vector3)).Magnitude
				local bodyStep = (flat(row.drawn) - flat(previous.drawn)).Magnitude
				-- The plate moves exactly as the body does, and the body never more than a frame of the run.
				expect(math.abs(plateStep - bodyStep)).toBeLessThan(EPSILON)
				expect(plateStep).toBeLessThan(FRAME_TRAVEL)
				-- The camera steps as the ideal one does.
				expect(math.abs(row.camStep - row.idealStep)).toBeLessThan(0.02)
			end
		end)
	end

	it("keeps the plate over the body a death mid-rush froze, at 0.5 s of root lag", function()
		local rows = run({ lag = 0.5, deathAt = 0.3, frames = 120 })
		local frozen = 0
		for _, row in rows do
			if row.drawing and row.t > 0.3 + LATENCY then
				frozen += 1
			end
		end
		expect(frozen).toBeGreaterThan(0)
		expect(most(rows, function(row)
			return if row.drawing then row.rootGap else nil
		end)).toBeGreaterThan(5)
		expect(most(rows, function(row)
			return row.plateGap
		end)).toBeLessThan(EPSILON)
		-- The camera framed the body until the lock let go at the death.
		expect(most(rows, function(row)
			return if row.locked then row.camGap else nil
		end)).toBeLessThan(0.02)
	end)

	it("keeps the plate and SWITCH over a body a parry staggered mid-rush, and hands both back", function()
		local rows = run({ lag = 0.25, staggerAt = 0.2 })
		local shown = 0
		for _, row in rows do
			if row.switchGap ~= nil then
				shown += 1
				expect(row.switchGap).toBeLessThan(EPSILON)
			end
		end
		expect(shown).toBeGreaterThan(0)
		expect(most(rows, function(row)
			return if row.drawing then row.rootGap else nil
		end)).toBeGreaterThan(5)
		expect(most(rows, function(row)
			return row.plateGap
		end)).toBeLessThan(EPSILON)
		expect(most(rows, function(row)
			return row.camGap
		end)).toBeLessThan(0.02)
		local final = rows[#rows]
		expect(((final.plateLift :: Vector3) - PLATE_LIFT).Magnitude).toBeLessThan(EPSILON)
		expect(((final.switchLift :: Vector3) - SWITCH_LIFT).Magnitude).toBeLessThan(EPSILON)
	end)
end)

describe("the lock camera frames this frame's drawn body whichever way the engine orders its frame (D-201)", function()
	for _, order in { "RenderStepped first", "RenderStepped last" } do
		for _, lag in { 0.25, 0.5 } do
			it(("%s, %.2f s of root lag"):format(order, lag), function()
				local rows = run({ lag = lag, order = order })
				expect(most(rows, function(row)
					return if row.drawing then row.rootGap else nil
				end)).toBeGreaterThan(SPEED * lag * 0.9)
				expect(most(rows, function(row)
					return row.camGap
				end)).toBeLessThan(0.02)
				expect(most(rows, function(row)
					return row.camTurn
				end)).toBeLessThan(0.25)
			end)
		end
	end
end)
