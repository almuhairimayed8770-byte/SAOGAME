--!strict
--[[
	Every per-frame reader of a rig's pose sees this frame's pose (D-211).

	The client's render steps run in one order, from data, on every machine: Choreo's full-rate
	rigs (choreo.luau renderOrder.rigs), the local character's step (renderOrder.character: its
	rig, root motion and contact), the camera (camera.luau renderOrder.main), the impact picture
	and the pose readers (fx.luau renderOrder.impactFrames, poseReaders), the camera's late pass
	(renderOrder.late). FrameOrder keeps the steps those readers join bound.

	The integration cases load the real client modules fresh over a fake engine. Its frame is the
	engine's: RenderStepped connections before or after every bound step (the engine pins neither,
	D-201), the steps bound before the frame began by priority (one bound inside the frame waits
	for the next), the draw (sampled here), PreSimulation, physics (a root moves, its pose kept)
	and Heartbeat. The rigs are posed by a stand-in at Choreo's priority; the local character's
	step is a stand-in at the controller's that moves the root and makes the contact (the Final
	picture, a nudge, a shake and a punch, as a predicted contact does). Lune derives no part
	frames from a pose, so the stand-ins place every part and the blade tip themselves.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ChoreoData = Harness.load("src/shared/data/choreo")
local CameraData = Harness.load("src/shared/data/camera")
local Fx = Harness.load("src/shared/data/fx")
local Impact = Harness.load("src/shared/data/impact")
local Accents = Harness.load("src/shared/data/accents")

local FRAME = 1 / 60
local ORDERS = { "RenderStepped first", "RenderStepped last" }
-- Vector3 is single precision: positions some studs out agree to about this.
local EPSILON = 1e-4

local function orderRow(data: any, key: string): any
	local order = data.renderOrder
	return if order ~= nil then order[key] else nil
end

local function priorityOf(row: any, fallback: number): number
	if row == nil then
		return fallback
	end
	return (Enum.RenderPriority :: any)[row.base].Value + row.offset
end

-- Where the stand-ins bind: the data's rows, or where the steps were before them.
local RIGS = priorityOf(orderRow(ChoreoData, "rigs"), Enum.RenderPriority.Camera.Value - 1)
local CHARACTER = priorityOf(orderRow(ChoreoData, "character"), Enum.RenderPriority.Character.Value + 1)

-- ---------------------------------------------------------------------------------------------
-- The data
-- ---------------------------------------------------------------------------------------------

describe("The client's render order (D-211)", function()
	it("is one order from data: rigs, character, camera, picture, pose readers, late pass", function()
		local rows = {
			orderRow(ChoreoData, "rigs"),
			orderRow(ChoreoData, "character"),
			orderRow(CameraData, "main"),
			orderRow(Fx, "impactFrames"),
			orderRow(Fx, "poseReaders"),
			orderRow(CameraData, "late"),
		}
		expect(#rows).toBe(6)
		local previous = Enum.RenderPriority.First.Value
		for index = 1, 6 do
			local row = rows[index]
			expect(row).never.toBeNil()
			expect(typeof(row.base)).toBe("string")
			expect(typeof(row.offset)).toBe("number")
			local priority = priorityOf(row, -1)
			expect(priority).toBeGreaterThan(previous)
			expect(priority).toBeLessThanOrEqual(Enum.RenderPriority.Last.Value)
			previous = priority
		end
	end)

	it("keeps the rigs just before the camera's priority and the controller just after Character's", function()
		-- D-201 and D-139: the rigs' step and the controller's own stay where they were.
		expect(priorityOf(orderRow(ChoreoData, "rigs"), -1)).toBe(Enum.RenderPriority.Camera.Value - 1)
		expect(priorityOf(orderRow(ChoreoData, "character"), -1)).toBe(Enum.RenderPriority.Character.Value + 1)
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- FrameOrder
-- ---------------------------------------------------------------------------------------------

local function loadFrameOrder(): any
	local ok, module = pcall(Harness.load, "src/client/fx/FrameOrder")
	expect(ok).toBe(true)
	return module
end

type FakeStep = { name: string, priority: number, fn: (dt: number) -> () }

-- A fake BindToRenderStep: every bind, in order.
local function fakeBinder(): ((name: string, priority: number, fn: (dt: number) -> ()) -> boolean, { FakeStep })
	local binds: { FakeStep } = {}
	return function(name: string, priority: number, fn: (dt: number) -> ()): boolean
		table.insert(binds, { name = name, priority = priority, fn = fn })
		return true
	end,
		binds
end

local PROBE_ROW = { base = "Character", offset = 4 }

describe("FrameOrder", function()
	it("binds a named step once, at its row's priority, and keeps it bound with nobody in it", function()
		local FrameOrder = loadFrameOrder()
		local binder, binds = fakeBinder()
		FrameOrder.bind({ bindRenderStep = binder })
		local calls: { string } = {}
		local leaveA = FrameOrder.join("Probe", PROBE_ROW, function()
			table.insert(calls, "a")
		end)
		local leaveB = FrameOrder.join("Probe", PROBE_ROW, function()
			table.insert(calls, "b")
		end)
		expect(#binds).toBe(1)
		expect(binds[1].name).toBe("Probe")
		expect(binds[1].priority).toBe(Enum.RenderPriority.Character.Value + 4)
		expect(FrameOrder.priority(PROBE_ROW)).toBe(Enum.RenderPriority.Character.Value + 4)
		binds[1].fn(FRAME)
		expect(calls).toEqual({ "a", "b" })
		leaveA()
		leaveB()
		binds[1].fn(FRAME)
		expect(calls).toEqual({ "a", "b" })
		-- Empty, it stays bound: the next reader joins it without a new bind.
		FrameOrder.join("Probe", PROBE_ROW, function()
			table.insert(calls, "c")
		end)
		expect(#binds).toBe(1)
		binds[1].fn(FRAME)
		expect(calls).toEqual({ "a", "b", "c" })
		FrameOrder.bind(nil)
	end)

	it("runs a reader that joins a prepared step inside the frame on that same frame", function()
		local FrameOrder = loadFrameOrder()
		-- One frame's bound steps, fixed when the frame begins (a step bound inside it waits).
		local steps: { FakeStep } = {}
		FrameOrder.bind({
			bindRenderStep = function(name: string, priority: number, fn: (dt: number) -> ()): boolean
				table.insert(steps, { name = name, priority = priority, fn = fn })
				table.sort(steps, function(a: FakeStep, b: FakeStep): boolean
					return a.priority < b.priority
				end)
				return true
			end,
		})
		local ran = 0
		local contact = false
		table.insert(steps, {
			name = "Contact",
			priority = CHARACTER,
			fn = function()
				if contact then
					contact = false
					FrameOrder.join("Probe", PROBE_ROW, function()
						ran += 1
					end)
				end
			end,
		})
		expect(FrameOrder.prepare("Probe", PROBE_ROW)).toBe(true)
		local function frame()
			for _, step in table.clone(steps) do
				step.fn(FRAME)
			end
		end
		frame()
		contact = true
		frame()
		expect(ran).toBe(1)
		frame()
		expect(ran).toBe(2)
		FrameOrder.bind(nil)
	end)

	it("runs a reader joined during the pass in that pass, and none that left, even mid-pass", function()
		local FrameOrder = loadFrameOrder()
		local binder, binds = fakeBinder()
		FrameOrder.bind({ bindRenderStep = binder })
		local calls: { string } = {}
		local leaveC: (() -> ())? = nil
		local leaveB: (() -> ())? = nil
		local first = true
		FrameOrder.join("Probe", PROBE_ROW, function()
			table.insert(calls, "a")
			if first then
				first = false
				-- b leaves before its turn; c joins and runs in this pass.
				local stopB = leaveB :: () -> ()
				stopB()
				leaveC = FrameOrder.join("Probe", PROBE_ROW, function()
					table.insert(calls, "c")
				end)
			end
		end)
		leaveB = FrameOrder.join("Probe", PROBE_ROW, function()
			table.insert(calls, "b")
		end)
		binds[1].fn(FRAME)
		expect(calls).toEqual({ "a", "c" })
		binds[1].fn(FRAME)
		expect(calls).toEqual({ "a", "c", "a", "c" })
		local stopC = leaveC :: () -> ()
		stopC()
		-- Leaving twice is harmless.
		stopC()
		binds[1].fn(FRAME)
		expect(calls).toEqual({ "a", "c", "a", "c", "a" })
		FrameOrder.bind(nil)
	end)

	it("isolates a reader that throws: the others run and a warning names the step", function()
		local FrameOrder = loadFrameOrder()
		local binder, binds = fakeBinder()
		FrameOrder.bind({ bindRenderStep = binder })
		local ran = 0
		FrameOrder.join("Probe", PROBE_ROW, function()
			error("boom")
		end)
		FrameOrder.join("Probe", PROBE_ROW, function()
			ran += 1
		end)
		local before = #Harness.warnings()
		binds[1].fn(FRAME)
		expect(ran).toBe(1)
		local warnings = Harness.warnings()
		expect(#warnings).toBe(before + 1)
		expect((warnings[#warnings] :: string):find("Probe", 1, true) ~= nil).toBe(true)
		FrameOrder.bind(nil)
	end)

	it("allocates nothing per frame", function()
		local FrameOrder = loadFrameOrder()
		local binder, binds = fakeBinder()
		FrameOrder.bind({ bindRenderStep = binder })
		local sum = 0
		for _ = 1, 3 do
			FrameOrder.join("Probe", PROBE_ROW, function(dt: number)
				sum += dt
			end)
		end
		local fn = binds[1].fn
		fn(FRAME)
		-- The heap in whole kilobytes, read around windows of a thousand frames: nothing allocated
		-- leaves it exactly as it was (the collector only steps when something is allocated), while
		-- one small table a frame is tens of kilobytes a window, which no window's collection hides
		-- every time.
		local changed = 0
		for _ = 1, 20 do
			local before = gcinfo()
			for _ = 1, 1000 do
				fn(FRAME)
			end
			if gcinfo() ~= before then
				changed += 1
			end
		end
		expect(changed).toBe(0)
		expect(sum).toBeGreaterThan(0)
		FrameOrder.bind(nil)
	end)

	it("joins nothing where there is no render step (Lune): join is nil and prepare false", function()
		local FrameOrder = loadFrameOrder()
		FrameOrder.bind({
			bindRenderStep = function(): boolean
				return false
			end,
		})
		expect(FrameOrder.prepare("Probe", PROBE_ROW)).toBe(false)
		expect(FrameOrder.join("Probe", PROBE_ROW, function() end)).toBeNil()
		FrameOrder.bind(nil)
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- The fake engine and fresh client modules
-- ---------------------------------------------------------------------------------------------

type Bound = { name: string, priority: number, fn: (dt: number) -> (), seq: number, live: boolean }
type Listener = { fn: (...any) -> (), live: boolean }

type Engine = {
	order: string,
	runService: any,
	camera: any,
	playerGui: Instance,
	clock: () -> number,
	-- One rendered frame of `dt`: `draw` samples what the frame shows.
	frame: (dt: number, draw: (() -> ())?) -> (),
	-- `seconds` with no render step: PreSimulation, physics and Heartbeat go on.
	sleep: (seconds: number, dt: number) -> (),
	-- `seconds` with nothing at all (the whole window frozen): only the clock moves.
	freeze: (seconds: number) -> (),
	-- Runs after PreSimulation each frame, before Heartbeat.
	physics: { (dt: number) -> () },
	bound: () -> { Bound },
	load: (path: string) -> any,
}

local function makeEngine(order: string): Engine
	local state = { clock = 100 }
	local signals: { [any]: boolean } = {}
	local function signal(list: { Listener }): any
		local made: any = {}
		function made.Connect(_self: any, fn: (...any) -> ()): any
			local entry: Listener = { fn = fn, live = true }
			table.insert(list, entry)
			return {
				Disconnect = function()
					entry.live = false
				end,
			}
		end
		function made.Once(self: any, fn: (...any) -> ()): any
			local connection: any = nil
			connection = self:Connect(function(...: any)
				connection.Disconnect()
				fn(...)
			end)
			return connection
		end
		signals[made] = true
		return made
	end
	local renderStepped: { Listener } = {}
	local heartbeat: { Listener } = {}
	local preSimulation: { Listener } = {}
	local bound: { Bound } = {}
	local seq = 0
	local function unbind(name: string)
		for index = #bound, 1, -1 do
			if bound[index].name == name then
				bound[index].live = false
				table.remove(bound, index)
			end
		end
	end
	local runService = {
		IsServer = function(): boolean
			return false
		end,
		IsClient = function(): boolean
			return true
		end,
		IsStudio = function(): boolean
			return true
		end,
		BindToRenderStep = function(_self: any, name: string, priority: number, fn: (dt: number) -> ())
			unbind(name)
			seq += 1
			table.insert(bound, { name = name, priority = priority, fn = fn, seq = seq, live = true })
			table.sort(bound, function(a: Bound, b: Bound): boolean
				if a.priority ~= b.priority then
					return a.priority < b.priority
				end
				return a.seq < b.seq
			end)
		end,
		UnbindFromRenderStep = function(_self: any, name: string)
			unbind(name)
		end,
		RenderStepped = signal(renderStepped),
		Heartbeat = signal(heartbeat),
		PreSimulation = signal(preSimulation),
	}
	local baseTypeof = Harness.environment().typeof
	local function engineTypeof(value: any): string
		if signals[value] then
			return "RBXScriptSignal"
		end
		return baseTypeof(value)
	end
	local camera = {
		CFrame = CFrame.new(0, 10, 20),
		FieldOfView = 70,
		CameraType = nil,
		Focus = CFrame.new(),
		ViewportSize = Vector2.new(1920, 1080),
	}
	local playerGui = Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	local localPlayer = {
		Name = "Spec",
		UserId = 1,
		Character = nil,
		CharacterAdded = signal({}),
		CharacterRemoving = signal({}),
		FindFirstChildOfClass = function(_self: any, className: string): any
			return if className == "PlayerGui" then playerGui else nil
		end,
		WaitForChild = function(_self: any, name: string): any
			return if name == "PlayerGui" then playerGui else nil
		end,
	}
	local services: { [string]: any } = {
		RunService = runService,
		Players = { LocalPlayer = localPlayer },
		UserInputService = {
			MouseEnabled = true,
			TouchEnabled = false,
			MouseBehavior = nil,
			InputChanged = signal({}),
			LastInputTypeChanged = signal({}),
		},
	}
	local gameStub = {
		GetService = function(_self: any, name: string): any
			return services[name] or Harness.game():GetService(name)
		end,
	}
	local workspaceStub = {
		CurrentCamera = camera,
		Spherecast = function(): any
			return nil
		end,
		GetServerTimeNow = function(): number
			return state.clock
		end,
	}
	local osStub = {
		clock = function(): number
			return state.clock
		end,
		time = os.time,
		date = os.date,
	}
	-- Client modules load fresh here (their own state, this engine); shared ones are the harness's.
	local cache: { [any]: any } = {}
	local function loadNode(node: any): any
		local hit = cache[node]
		if hit ~= nil then
			return hit
		end
		local path = rawget(node, "_path") :: string
		if path:find("/src/client/", 1, true) == nil then
			return Harness.loadModule(node)
		end
		local env = Harness.environment()
		env.typeof = engineTypeof
		env.script = node
		env.game = gameStub
		env.workspace = workspaceStub
		env.os = osStub
		env.RaycastParams = {
			new = function(): any
				return {}
			end,
		}
		env.require = function(target: any): any
			return loadNode(target)
		end
		local result = luau.load(fs.readFile(path), { debugName = path, environment = env :: any })()
		cache[node] = result
		return result
	end
	local physics: { (dt: number) -> () } = {}
	local function fire(list: { Listener }, dt: number)
		for _, entry in table.clone(list) do
			if entry.live then
				entry.fn(dt)
			end
		end
	end
	local engine: Engine = {
		order = order,
		runService = runService,
		camera = camera,
		playerGui = playerGui,
		clock = function(): number
			return state.clock
		end,
		frame = function(dt: number, draw: (() -> ())?)
			state.clock += dt
			if order == "RenderStepped first" then
				fire(renderStepped, dt)
			end
			for _, step in table.clone(bound) do
				if step.live then
					step.fn(dt)
				end
			end
			if order ~= "RenderStepped first" then
				fire(renderStepped, dt)
			end
			if draw ~= nil then
				draw()
			end
			fire(preSimulation, dt)
			for _, fn in physics do
				fn(dt)
			end
			fire(heartbeat, dt)
		end,
		sleep = function(seconds: number, dt: number)
			local untilAt = state.clock + seconds
			while state.clock < untilAt do
				state.clock += dt
				fire(preSimulation, dt)
				for _, fn in physics do
					fn(dt)
				end
				fire(heartbeat, dt)
			end
		end,
		freeze = function(seconds: number)
			state.clock += seconds
		end,
		physics = physics,
		bound = function(): { Bound }
			return bound
		end,
		load = function(path: string): any
			return loadNode(Harness.node(path))
		end,
	}
	return engine
end

-- A fighter: a root, a body and (armed) a sword whose tip (TrailEnd) sweeps round the root as
-- `swing` turns. Every part's name is its own, so a figure finds its body by name.
type Fighter = {
	model: Model,
	root: BasePart,
	body: BasePart,
	weapon: BasePart?,
	tip: Attachment?,
	swing: number,
}

local function newPart(name: string, size: Vector3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Parent = parent
	return part
end

local function fighter(name: string, at: CFrame, parent: Instance, armed: boolean): Fighter
	local model = Instance.new("Model")
	model.Name = name
	local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), model)
	model.PrimaryPart = root
	local body = newPart(name .. "Body", Vector3.new(2, 2, 1), model)
	local weapon: BasePart? = nil
	local tip: Attachment? = nil
	if armed then
		local blade = newPart("Weapon", Vector3.new(0.2, 0.2, 4), model)
		local start = Instance.new("Attachment")
		start.Name = "TrailStart"
		start.CFrame = CFrame.new(0, 0, 1.5)
		start.Parent = blade
		local finish = Instance.new("Attachment")
		finish.Name = "TrailEnd"
		finish.CFrame = CFrame.new(0, 0, -2)
		finish.Parent = blade
		weapon, tip = blade, finish
	end
	model.Parent = parent
	root.CFrame = at
	return { model = model, root = root, body = body, weapon = weapon, tip = tip, swing = 0 }
end

-- Places every part from the root and the pose (what the engine's joints do for a drawn rig).
local function pose(f: Fighter)
	local root = f.root.CFrame
	f.root.Position = root.Position
	local body = root * CFrame.new(0, 1.5, 0)
	f.body.CFrame = body
	f.body.Position = body.Position
	local weapon, tip = f.weapon, f.tip
	if weapon ~= nil and tip ~= nil then
		local frame = root * CFrame.Angles(0, f.swing, 0) * CFrame.new(1, 1, -3)
		weapon.CFrame = frame
		weapon.Position = frame.Position
		tip.WorldPosition = (frame * tip.CFrame).Position
	end
end

local function tipOf(f: Fighter): Vector3
	return (f.tip :: Attachment).WorldPosition
end

local function angleBetween(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

-- ---------------------------------------------------------------------------------------------
-- The rigs
-- ---------------------------------------------------------------------------------------------

describe("Choreo's rigs step where data says (D-201)", function()
	it("binds its rigs' step at renderOrder.rigs, before the controller and every reader", function()
		local engine = makeEngine(ORDERS[1])
		local Choreo = engine.load("src/client/choreo/Choreo")
		expect(Choreo.renderPriority()).toBe(priorityOf(orderRow(ChoreoData, "rigs"), -1))
		-- The first rig starts Choreo's loops.
		local rig = fighter("Rig", CFrame.new(0, 3, 0), Instance.new("Folder"), false)
		rig.model:SetAttribute("Rig", "PlayerR15")
		pose(rig)
		Choreo.get(rig.model)
		local found: number? = nil
		for _, step in engine.bound() do
			if step.name == Choreo.RENDER_STEP then
				found = step.priority
			end
		end
		expect(found).toBe(RIGS)
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- The camera
-- ---------------------------------------------------------------------------------------------

describe("The camera frames this frame's body (D-211)", function()
	for _, order in ORDERS do
		it(("reads the local root after the character's step has moved it (%s)"):format(order), function()
			local engine = makeEngine(order)
			local Camera = engine.load("src/client/camera/CameraController")
			local world = Instance.new("Folder")
			local me = fighter("Me", CFrame.new(0, 3, 0), world, false)
			pose(me)
			-- The camera reads the root through this proxy, so the spec sees what it read.
			local read: Vector3? = nil
			local proxy = setmetatable({}, {
				__index = function(_self: any, key: string): any
					if key == "Position" then
						read = me.root.Position
						return read
					elseif key == "CFrame" then
						return me.root.CFrame
					elseif key == "IsA" then
						return function(_s: any, className: string): boolean
							return className == "BasePart"
						end
					end
					return nil
				end,
			})
			local subject = {
				PrimaryPart = proxy,
				FindFirstChild = function(): any
					return proxy
				end,
			}
			Camera.start()
			Camera.setSubject(subject :: any)
			-- The character's step: a dodge's root motion, 20 studs a second along -Z.
			local moving = false
			engine.runService:BindToRenderStep("SpecCharacter", CHARACTER, function(dt: number)
				if moving then
					me.root.CFrame = me.root.CFrame + Vector3.new(0, 0, -20 * dt)
					pose(me)
				end
			end)
			for _ = 1, 30 do
				engine.frame(FRAME)
			end
			moving = true
			local worst = 0
			local seen = 0
			for _ = 1, 20 do
				engine.frame(FRAME, function()
					local value = read
					if value ~= nil then
						seen += 1
						worst = math.max(worst, (value - me.root.Position).Magnitude)
					end
					read = nil
				end)
			end
			expect(seen).toBe(20)
			expect(worst).toBeLessThan(EPSILON)
			-- The bound steps the camera took: its main step and its late pass, where data says.
			local priorities: { [string]: number } = {}
			for _, step in engine.bound() do
				priorities[step.name] = step.priority
			end
			expect(priorities.SkyspireCamera).toBe(priorityOf(orderRow(CameraData, "main"), -1))
			expect(priorities.SkyspireCameraLate).toBe(priorityOf(orderRow(CameraData, "late"), -1))
		end)
	end
end)

-- ---------------------------------------------------------------------------------------------
-- The impact picture at the contact
-- ---------------------------------------------------------------------------------------------

describe("The impact picture shows this frame's camera and bodies (D-211)", function()
	for _, order in ORDERS do
		for _, fps in { 60, 30 } do
			it(("from the contact frame on, for exactly its drawn frames (%s, %d fps)"):format(order, fps), function()
				local dt = 1 / fps
				local engine = makeEngine(order)
				-- FrameClock binds its two steps as it loads, as in the client.
				engine.load("src/client/fx/FrameClock")
				local Camera = engine.load("src/client/camera/CameraController")
				local ImpactFrames = engine.load("src/client/fx/ImpactFrames")
				local world = Instance.new("Folder")
				local me = fighter("Me", CFrame.new(0, 3, 0), world, true)
				local boar = fighter("Boar", CFrame.new(0, 3, -6) * CFrame.Angles(0, math.pi, 0), world, false)
				pose(me)
				pose(boar)
				ImpactFrames.bind({
					now = engine.clock,
					playerGui = function(): Instance
						return engine.playerGui
					end,
					camera = function(): any
						return engine.camera
					end,
					quality = function(): string
						return "High"
					end,
					project = function(): Vector2
						return Vector2.new(0.5, 0.5)
					end,
					aspect = function(): number
						return 16 / 9
					end,
				})
				ImpactFrames.start()
				Camera.start()
				Camera.setSubject(me.model)
				-- The rigs' step: the sword swings until the hit-stop freezes it.
				local frozen = false
				engine.runService:BindToRenderStep("SpecRigs", RIGS, function(step: number)
					if not frozen then
						me.swing += 6 * step
					end
					pose(me)
					pose(boar)
				end)
				-- The character's step: root motion, a lock turn that goes on through the hold,
				-- and the contact.
				local contactDue = false
				engine.runService:BindToRenderStep("SpecCharacter", CHARACTER, function(step: number)
					if frozen then
						me.root.CFrame = me.root.CFrame * CFrame.Angles(0, math.rad(90) * step, 0)
					else
						me.root.CFrame = me.root.CFrame + Vector3.new(0, 0, -4 * step)
					end
					pose(me)
					if contactDue then
						contactDue = false
						frozen = true
						local hit = tipOf(me)
						ImpactFrames.play("Final", { me.model, boar.model }, { position = hit })
						Camera.nudge(hit, CameraData.nudge.studs)
						Camera.shake("Final")
						Camera.punch("Final")
					end
				end)
				for _ = 1, fps do
					engine.frame(dt)
				end
				local shown = 0
				local cameraGap = 0
				local fovGap = 0
				local figureGap = 0
				local figures = 0
				local function draw()
					local gui = ImpactFrames.gui()
					if gui == nil or not gui.Enabled then
						return
					end
					shown += 1
					local own = ImpactFrames.camera()
					local world = engine.camera
					if own ~= nil then
						cameraGap = math.max(
							cameraGap,
							(own.CFrame.Position - world.CFrame.Position).Magnitude,
							angleBetween(own.CFrame.LookVector, world.CFrame.LookVector)
						)
						fovGap = math.max(fovGap, math.abs(own.FieldOfView - world.FieldOfView))
					end
					for _, clone in ImpactFrames.clones() do
						for _, body in { me, boar } do
							local source = body.model:FindFirstChild(clone.Name)
							if source ~= nil and clone:IsDescendantOf(engine.playerGui) then
								local part = source :: BasePart
								figures += 1
								figureGap = math.max(
									figureGap,
									(clone.CFrame.Position - part.CFrame.Position).Magnitude
										+ (clone.CFrame.LookVector - part.CFrame.LookVector).Magnitude
								)
							end
						end
					end
				end
				contactDue = true
				local contactShown = false
				engine.frame(dt, function()
					draw()
					contactShown = shown == 1
				end)
				for _ = 1, fps // 2 do
					engine.frame(dt, draw)
				end
				-- Final is Dark for its frames, counted in drawn frames from the contact frame.
				local steps = Impact.sequences.Final.steps
				local expected = 0
				for _, stepRow in steps do
					expected += math.max(1, math.round(stepRow.frames * Impact.frameSeconds / dt))
				end
				expect(contactShown).toBe(true)
				expect(figures).toBeGreaterThan(0)
				expect(figureGap).toBeLessThan(EPSILON)
				expect(cameraGap).toBeLessThan(EPSILON)
				expect(fovGap).toBeLessThan(EPSILON)
				expect(shown).toBe(expected)
			end)
		end
	end
end)

-- ---------------------------------------------------------------------------------------------
-- The trail's blade samples
-- ---------------------------------------------------------------------------------------------

type TrailRun = { engine: Engine, Trails: any, Engine: any, remote: Fighter }

-- A remote fighter swinging while its replicated root runs and turns (physics, after the draw).
local function trailRun(order: string): TrailRun
	local engine = makeEngine(order)
	local FxEngine = engine.load("src/client/fx/Engine")
	FxEngine.setClock(engine.clock)
	FxEngine.setViewer(function(): Vector3
		return Vector3.zero
	end)
	local Trails = engine.load("src/client/fx/Trails")
	local world = Instance.new("Folder")
	local remote = fighter("Remote", CFrame.new(4, 3, -8), world, true)
	pose(remote)
	engine.runService:BindToRenderStep("SpecRigs", RIGS, function(step: number)
		remote.swing += 8 * step
		pose(remote)
	end)
	table.insert(engine.physics, function(step: number)
		remote.root.CFrame = remote.root.CFrame * CFrame.Angles(0, math.rad(120) * step, 0)
			+ Vector3.new(14 * step, 0, 0)
		pose(remote)
	end)
	Trails.start()
	Trails.attach(remote.model)
	Trails.setActive(remote.model, true, "Art")
	return { engine = engine, Trails = Trails, Engine = FxEngine, remote = remote }
end

describe("Trails samples the blade where the frame draws it (D-211)", function()
	for _, order in ORDERS do
		it(
			("its ring's newest sample is the drawn tip, and its direction the drawn swing (%s)"):format(order),
			function()
				local run = trailRun(order)
				local remote = run.remote
				local drawn: { Vector3 } = {}
				local worst = 0
				local worstTurn = 0
				local samples = math.max(2, Accents.swing.samples)
				-- Past the strike's snap memory, the direction is the ring's own chord.
				local warm = math.ceil(Accents.swing.memorySeconds / FRAME) + 2
				for _ = 1, warm do
					run.engine.frame(FRAME)
				end
				for _ = 1, 20 do
					run.engine.frame(FRAME, function()
						local tip = tipOf(remote)
						table.insert(drawn, tip)
						local newest = run.Trails.lastSample(remote.model)
						expect(newest).never.toBeNil()
						worst = math.max(worst, ((newest :: Vector3) - tip).Magnitude)
						if #drawn >= samples then
							local chord = tip - drawn[#drawn - samples + 1]
							local direction = run.Trails.swingDirection(remote.model)
							expect(direction).never.toBeNil()
							worstTurn = math.max(worstTurn, ((direction :: Vector3) - chord.Unit).Magnitude)
						end
					end)
				end
				expect(worst).toBeLessThan(EPSILON)
				expect(worstTurn).toBeLessThan(EPSILON)
			end
		)
	end

	it("never joins a chord across a render stall: the ring starts over at the wake", function()
		for _, order in ORDERS do
			for _, heartbeats in { true, false } do
				local run = trailRun(order)
				local remote = run.remote
				for _ = 1, 10 do
					run.engine.frame(FRAME)
				end
				expect(run.Trails.swingDirection(remote.model)).never.toBeNil()
				-- The display sleeps past a jump (Heartbeat going on, or the whole window frozen).
				local gap = ChoreoData.stall.jumpSeconds + 0.1
				if heartbeats then
					run.engine.sleep(gap, FRAME)
				else
					run.engine.freeze(gap)
					remote.root.CFrame = remote.root.CFrame + Vector3.new(6, 0, 0)
					remote.swing += 1
					pose(remote)
				end
				-- The wake's frame: one sample since the stall, so no direction from the tip yet,
				-- and nothing remembered from before it.
				local wakeDirection: Vector3? = Vector3.zero
				run.engine.frame(FRAME, function()
					wakeDirection = run.Trails.swingDirection(remote.model)
				end)
				expect(wakeDirection).toBeNil()
				run.engine.frame(FRAME)
				expect(run.Trails.swingDirection(remote.model)).never.toBeNil()
			end
		end
	end)
end)
