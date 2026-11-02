--!strict
--[[
	A held enemy stands upright on this client too (D-508, D-523, D-543, D-544, the client side
	of D-494), and a copy stood up with its state machine off gets it back at its release (D-559).
	The server turns its enemy Humanoids' fall states off (ai.upright.offStates) on the
	frame each model is made, but Humanoid:SetStateEnabled does not replicate. The real
	EntityTracker meets the models the way Studio hands them over (the SkyspireEntity tag's
	InstanceAdded, the attributes the server published, each attribute change on its own signal),
	the real Replication watches them and asks its real seam (Replication.uprightModel, which start()
	hands it), and the rigs are RigBuilder's own. The fake engine is this client's copy of each
	Humanoid, doing what the owner's PC measured in Studio (item 398(a) on 0582a04, item 425 and the
	upright probe on 4b18b5c, items 442 and 443 on 9063a60, probe P1 on 4e60f11):

	- the server's SetStateEnabled does not reach the copy: GetStateEnabled(FallingDown) reads true;
	- the tag comes before the Humanoid (442; P1: the tag's handler never finds one), and a copy
	  reads None in the handler of its own arrival (P1);
	- a copy whose root is anchored goes FallingDown on its physics step while FallingDown is on;
	  one that comes after the tag has had that step by the next PreSimulation (442: StoodUp, tries
	  2, FallingDown, GetStateEnabled false, on every held row; P1 L0);
	- once FallingDown with its root anchored it stays there: neither turning the state off nor a
	  ChangeState (Running, GettingUp, the same frame or the next) takes it out (P1 L4, 473 of 473);
	- the client's own SetStateEnabled false made in the Humanoid's arrival handler holds, and the
	  copy reads Running on every row, held at spawn or later (P1 L2, 2260 and 2080 rows);
	- with Humanoid.EvaluateStateMachine false the state machine no longer moves the copy, and a
	  ChangeState takes at once, held or not (P1 L3: Running on 862 of 862 anchored rows);
	- with the state machine on, from the row its root is let go it reads the server's state
	  (Running), FallingDown or not before;
	- its root stays at its standing height throughout (nothing visible was measured: P1 Torso y
	  3.40-3.46, lowest leg corner -0.032 to 0.000 with and without FallingDown);
	- with the state machine on, physics reads the floor under the copy into FloorMaterial (474(a)
	  on 209875b: Grass on the field); with it off the copy reads Air (474(e): 536 of 536 rows,
	  held and walking). Written on the copy's Humanoid, so the real SfxPool.surfaceOf and
	  Locomotion.humanoidTracker read it.

	One frame here: the beforePhysics step (PreSimulation), then what replication brings (each
	arrival with its handlers, in order; a Humanoid's parenting fires the model's arrival seam,
	start()'s ChildAdded; a hold's end is the root's Anchored replicated), then this client's
	physics on every copy, then the logged row. Where in Studio's frame the copy first falls is not
	measured; that it has fallen by the next PreSimulation and not inside its own arrival handler
	is (442, P1). Assumed: a state machine turned back on reads the floor again on its next step
	(474(e) checks it). Also assumed, each for one case only: an engine that loses the first
	SetStateEnabled made on a copy (never seen since 4b18b5c), and one whose state machine, turned
	back on, lays the copy down on its next step (seen since: 495 below).

	The cases that take `Measured` run the engine the PC measured on 82b82d4 (item 495, the rescue
	build: catchOnArrival false in a copy), where a frame starts with what the server's physics
	replication brings, then PreSimulation, then physics:
	- the hold's end lands before that frame's PreSimulation (495(b): EvaluateStateMachine reads
	  true on R, the first row its root reads let go, on both takes);
	- a state machine turned back on puts the copy in FallingDown on its first step with it on,
	  held or let go, its fall states off (495(d): R on 2 of 2 takes; 495(i): the row the command
	  bar turned it on, held), and a copy in a fall state reads FloorMaterial Air (R, 495(c));
	- with it on and the root let go, the copy takes the server's state, Running, before the next
	  PreSimulation (495(d): Running from R+1, and the read-back between never turned it off:
	  EvaluateStateMachine true on 565 of 565 rows); with the root anchored nothing comes and the
	  copy stays down (P1 L0 #8; 495(i): the read-back turned it off on the next row).
	Assumed for one case each: that the server's state comes only on the frames a server step
	lands (`packets`: a 60 Hz server on a 144 Hz client; Studio solo at 60 fps is every frame),
	and an engine that keeps the copy down once turned back on (`staysDown`, never seen).
]]

local EntityTracker = Harness.load("src/client/controllers/EntityTracker")
local Replication = Harness.load("src/client/controllers/Replication")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local SfxPool = Harness.load("src/client/audio/SfxPool")
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local AI = Harness.load("src/shared/data/ai")
local Fx = Harness.load("src/shared/data/fx")

local UPRIGHT = AI.upright.client
local NAMES = UPRIGHT.attributes
local FALLS = UPRIGHT.offStates
-- The Playground field under the copies (the PC's FloorMaterial on 474(a)) and its footstep surface.
local FIELD = "Grass"
local FIELD_SURFACE = Fx.audio.materialSurface[FIELD]

-- The PC's longest held stretch in a take (rows from the spawn to the release, 398(a)).
local HELD_ROWS = 196
local AFTER_ROWS = 60
-- 474(e)'s walk after the release: 5 s at 60 Hz, 39 studs.
local WALK_ROWS = 300
local WALK_STEP = 39 / WALK_ROWS

local function fakeSignal(): any
	local handlers: { (...any) -> () } = {}
	return {
		Connect = function(_, handler)
			table.insert(handlers, handler)
			return {
				Disconnect = function()
					local index = table.find(handlers, handler)
					if index ~= nil then
						table.remove(handlers, index)
					end
				end,
			}
		end,
		Fire = function(_, ...)
			for _, handler in table.clone(handlers) do
				handler(...)
			end
		end,
		count = function(): number
			return #handlers
		end,
	}
end

local function recorder(): any
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

-- This client's copy of a Humanoid as Studio ran it (above).
type Copy = {
	state: string,
	enabled: { [string]: boolean },
	evaluates: boolean, -- Humanoid.EvaluateStateMachine
	root: BasePart,
	stepped: boolean,
	sets: number,
	loseFirstSet: boolean, -- the one assumed engine (see the header)
	asked: number, -- how often the seam reached it
	askedSteps: number?, -- the physics steps it had had when it was first asked
	askedState: string?, -- what GetState read when it was first asked
	fallingRows: number,
	enabledOnFirstRow: boolean?, -- GetStateEnabled(FallingDown) on the first logged row
	stateOnFirstRow: string?,
	floor: string, -- Humanoid.FloorMaterial's name, as physics last left it
	heldEvaluates: boolean?, -- EvaluateStateMachine on the last row its root was anchored
	machineWrites: { boolean }, -- every EvaluateStateMachine write, in order
	reads: number, -- GetState calls
	downOnResume: boolean, -- the other assumed engine (see the header)
	layDown: boolean, -- that engine lays it down on its next step
	measured: Measured?, -- the engine 495 measured (see the header)
	turnedOn: boolean, -- that engine: turned back on, it falls on its next step
	wasTurnedOn: boolean, -- it was turned back on at least once (for `staysDown`)
}

-- The engine the PC measured on 82b82d4 (header), and its two assumed variants.
type Measured = {
	packets: ((frame: number) -> boolean)?, -- frames the server's state lands on; nil: every frame
	staysDown: boolean?, -- turned back on, the copy stays down whatever the server says
}

local FALLEN: { [string]: boolean } = {}
for _, name in FALLS do
	FALLEN[name] = true
end

type World = {
	copies: { [Instance]: Copy },
	tag: (model: Model) -> (), -- the replication batch that brings a tagged model to this client
	attribute: (model: Model, name: string, value: any) -> (), -- an attribute change replicated
	frame: (arrivals: { () -> () }?) -> (), -- one frame: PreSimulation, arrivals, physics, the row
	parent: (humanoid: Instance?, model: Model) -> (), -- a Humanoid replicated into its model
	catches: (model: Model) -> number, -- arrival handlers connected on the model
	localModel: Model,
	players: { [Instance]: boolean }, -- Players:GetPlayerFromCharacter
}

local function newCopy(loseFirstSet: boolean, root: BasePart, downOnResume: boolean?, measured: Measured?): Copy
	local enabled: { [string]: boolean } = {}
	for _, name in FALLS do
		enabled[name] = true
	end
	return {
		state = "None",
		enabled = enabled,
		evaluates = true,
		root = root,
		stepped = false,
		sets = 0,
		loseFirstSet = loseFirstSet,
		asked = 0,
		askedSteps = nil,
		askedState = nil,
		fallingRows = 0,
		enabledOnFirstRow = nil,
		stateOnFirstRow = nil,
		floor = "Air",
		heldEvaluates = nil,
		machineWrites = {},
		reads = 0,
		downOnResume = downOnResume == true,
		layDown = false,
		measured = measured,
		turnedOn = false,
		wasTurnedOn = false,
	}
end

-- What the seam's FindFirstChildOfClass hands Replication: the copy behind the engine's methods
-- and its EvaluateStateMachine property.
local function engineHumanoid(copy: Copy): any
	local methods = {
		GetState = function(_self: any): any
			copy.reads += 1
			return (Enum.HumanoidStateType :: any)[copy.state]
		end,
		GetStateEnabled = function(_self: any, stateType: any): boolean
			return copy.enabled[stateType.Name] ~= false
		end,
		SetStateEnabled = function(_self: any, stateType: any, on: boolean)
			copy.sets += 1
			if copy.loseFirstSet and copy.sets == 1 then
				return
			end
			copy.enabled[stateType.Name] = on
		end,
		ChangeState = function(_self: any, stateType: any)
			if copy.enabled[stateType.Name] == false then
				return
			end
			-- P1 L4: an anchored copy already down stays down while its state machine runs.
			if copy.evaluates and copy.root.Anchored and copy.state == "FallingDown" then
				return
			end
			copy.state = stateType.Name
		end,
	}
	return setmetatable({}, {
		__index = function(_, key: string): any
			if key == "EvaluateStateMachine" then
				return copy.evaluates
			end
			return methods[key]
		end,
		__newindex = function(_, key: string, value: any)
			assert(key == "EvaluateStateMachine", "the fake Humanoid has no property " .. key)
			table.insert(copy.machineWrites, value == true)
			if value == true and not copy.evaluates and copy.downOnResume then
				copy.layDown = true
			end
			if value == true and not copy.evaluates and copy.measured ~= nil then
				copy.turnedOn = true -- 495(d), (i): its first step with it on falls
				copy.wasTurnedOn = true
			end
			copy.evaluates = value == true
		end,
	})
end

local function rootOf(model: Model): BasePart
	return model.PrimaryPart :: BasePart
end

local function player(id: number, name: string, kind: boolean?): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	model:SetAttribute("EntityId", id)
	if kind ~= false then
		model:SetAttribute("EntityKind", "Player")
	end
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("DisplayName", name)
	return model
end

-- An enemy as EnemyService makes it for a staged take: RigBuilder's rig, held (anchored) from its
-- spawn, published as EntityService publishes it. `withId` and `withKind` false leave those
-- attributes to come later; `humanoidLater` takes the Humanoid out, returned to parent later.
local function enemy(
	id: number,
	rigId: string,
	defId: string,
	withId: boolean?,
	withKind: boolean?,
	humanoidLater: boolean?
): (Model, Instance?)
	local model = RigBuilder.build(rigId, defId)
	rootOf(model).Anchored = true
	if withId ~= false then
		model:SetAttribute("EntityId", id)
	end
	if withKind ~= false then
		model:SetAttribute("EntityKind", "Enemy")
	end
	model:SetAttribute("DefId", defId)
	model:SetAttribute("Rig", rigId)
	model:SetAttribute("DisplayName", defId)
	local humanoid: Instance? = nil
	if humanoidLater then
		humanoid = model:FindFirstChildOfClass("Humanoid");
		(humanoid :: Instance).Parent = nil
	end
	return model, humanoid
end

local function world(
	withSeam: boolean,
	onField: { Model },
	loseFirstSet: boolean?,
	downOnResume: boolean?,
	measured: Measured?
): World
	EntityTracker.reset()
	local copies: { [Instance]: Copy } = {}
	local players: { [Instance]: boolean } = {}
	local localModel = player(1, "Trialist")
	players[localModel] = true
	local added = fakeSignal()
	local attributeHandlers: { [Instance]: { [string]: any } } = {}
	local arrivals: { [Instance]: any } = {}
	local beforePhysics: { () -> () } = {}
	local function copyOf(humanoid: Instance): Copy
		local copy = copies[humanoid]
		if copy == nil then
			copy = newCopy(loseFirstSet == true, rootOf(humanoid.Parent :: Model), downOnResume, measured)
			copies[humanoid] = copy
		end
		return copy
	end
	local function arrivalOf(model: Instance): any
		local signal = arrivals[model]
		if signal == nil then
			signal = fakeSignal()
			arrivals[model] = signal
		end
		return signal
	end
	EntityTracker.bind({
		tagged = function()
			return onField
		end,
		instanceAdded = function(handler)
			added:Connect(handler)
		end,
		instanceRemoved = function() end,
		attributeChanged = function(model, attribute, handler)
			local byName = attributeHandlers[model]
			if byName == nil then
				byName = {}
				attributeHandlers[model] = byName
			end
			local signal = byName[attribute]
			if signal == nil then
				signal = fakeSignal()
				byName[attribute] = signal
			end
			return signal:Connect(handler)
		end,
		localCharacter = function()
			return localModel
		end,
		characterAdded = function() end,
	})
	-- Main.client's order: the tracker first (it tracks what is already on the field), then Replication.
	EntityTracker.wire()
	local deps: any = {
		net = { on = function() end },
		entities = EntityTracker,
		localId = EntityTracker.peekLocalId,
		localCharacter = function()
			return localModel
		end,
		locomotion = recorder(),
		choreo = {
			get = function()
				return { events = fakeSignal() }
			end,
		},
		clipLibrary = {
			has = function()
				return true
			end,
		},
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
		weaponCategory = function()
			return "OneHandedSword"
		end,
		trailToken = function()
			return "TrailCyanWhite"
		end,
		positionOf = function()
			return Vector3.zero
		end,
		schedule = function() end,
		beforePhysics = function(fn: () -> ())
			table.insert(beforePhysics, fn)
		end,
		-- start()'s seam: the model's ChildAdded, for a Humanoid child, handled at once.
		humanoidAdded = function(model: Model, fn: () -> ()): any
			return arrivalOf(model):Connect(fn)
		end,
	}
	if withSeam then
		-- Replication.start's seam on this client's copy: the real Replication.uprightModel, with
		-- Players:GetPlayerFromCharacter and FindFirstChildOfClass("Humanoid") reaching the fakes.
		deps.keepUpright = function(model: Model): (string?, string?)
			return Replication.uprightModel(model, function(character: Model): boolean
				return players[character] == true
			end, function(body: Model): any
				local humanoid = body:FindFirstChildOfClass("Humanoid")
				if humanoid == nil then
					return nil
				end
				local copy = copyOf(humanoid)
				copy.asked += 1
				if copy.askedSteps == nil then
					copy.askedSteps = if copy.stepped then 1 else 0
					copy.askedState = copy.state
				end
				return engineHumanoid(copy)
			end)
		end
		-- start()'s resume seam on the same copy: the real Replication.resumeModel (D-559).
		deps.resumeUpright = function(model: Model, settling: boolean): string?
			return Replication.resumeModel(model, function(body: Model): any
				local humanoid = body:FindFirstChildOfClass("Humanoid")
				return if humanoid ~= nil then engineHumanoid(copyOf(humanoid)) else nil
			end, settling)
		end
	end
	Replication.bind(deps)
	local function stepCopies()
		for _, record in EntityTracker.all() do
			local humanoid = record.model:FindFirstChildOfClass("Humanoid")
			if humanoid == nil then
				continue
			end
			local copy = copyOf(humanoid)
			copy.stepped = true
			-- P1 L1, L3: with its state machine off, physics leaves the copy's state where it is.
			if copy.measured ~= nil then
				if copy.evaluates and (copy.turnedOn or (copy.measured.staysDown and copy.wasTurnedOn)) then
					-- 495(d), (i): the first step with the state machine back on falls, held or let go
					copy.state = "FallingDown"
					copy.turnedOn = false
				elseif copy.evaluates and copy.root.Anchored and copy.state ~= "FallingDown" then
					copy.state = if copy.enabled.FallingDown then "FallingDown" else "Running"
				end
				-- a let-go copy's state is the server's, which replication brings (frame)
			elseif copy.evaluates and copy.root.Anchored then
				-- An anchored copy falls on its step while FallingDown is on, and stays down: the
				-- state machine never takes it out while the root stays anchored (P1 L4).
				if copy.state ~= "FallingDown" then
					copy.state = if copy.enabled.FallingDown then "FallingDown" else "Running"
				end
			elseif copy.evaluates then
				copy.state = "Running" -- the server's state, once the root is let go
			end
			if copy.layDown and copy.evaluates then
				copy.state = "FallingDown" -- the assumed engine (header)
				copy.layDown = false
			end
			-- 474(a): the state machine reads the field under it; 474(e): with it off, Air; 495(c):
			-- Air on its fall row.
			copy.floor = if copy.evaluates and not (copy.measured ~= nil and FALLEN[copy.state]) then FIELD else "Air"
			(humanoid :: any).FloorMaterial = (Enum.Material :: any)[copy.floor]
			if copy.root.Anchored then
				copy.heldEvaluates = copy.evaluates
			end
			if copy.enabledOnFirstRow == nil then
				copy.enabledOnFirstRow = copy.enabled.FallingDown
				copy.stateOnFirstRow = copy.state
			end
			if copy.state == "FallingDown" then
				copy.fallingRows += 1
			end
		end
	end
	local frames = 0
	-- 495: what the server's physics replication brings at a frame's start, before PreSimulation:
	-- the server's state (Running) to a let-go copy whose state machine is on.
	local function serverState()
		frames += 1
		if measured == nil or (measured.packets ~= nil and not measured.packets(frames)) then
			return
		end
		for _, copy in copies do
			if copy.evaluates and not copy.root.Anchored and not (measured.staysDown and copy.wasTurnedOn) then
				copy.state = "Running"
			end
		end
	end
	return {
		copies = copies,
		localModel = localModel,
		players = players,
		tag = function(model: Model)
			added:Fire(model)
		end,
		attribute = function(model: Model, name: string, value: any)
			model:SetAttribute(name, value)
			local byName = attributeHandlers[model]
			local signal = if byName ~= nil then byName[name] else nil
			if signal ~= nil then
				signal:Fire()
			end
		end,
		frame = function(arriving: { () -> () }?)
			serverState()
			for _, fn in beforePhysics do
				fn()
			end
			for _, arrive in arriving or {} do
				arrive()
			end
			stepCopies()
		end,
		parent = function(humanoid: Instance?, model: Model)
			(humanoid :: Instance).Parent = model
			arrivalOf(model):Fire()
		end,
		catches = function(model: Model): number
			local signal = arrivals[model]
			return if signal ~= nil then signal.count() else 0
		end,
	}
end

-- Holds every staged enemy HELD_ROWS rows from its first frame, then lets it go for AFTER_ROWS.
local function holdAndRelease(w: World, models: { Model }, firstFrame: { () -> () }, secondFrame: { () -> () }?)
	w.frame(firstFrame)
	w.frame(secondFrame)
	for _ = 3, HELD_ROWS do
		w.frame()
	end
	for _, model in models do
		rootOf(model).Anchored = false
	end
	for _ = 1, AFTER_ROWS do
		w.frame()
	end
end

-- A staged take on this client: the shot's enemies come in one batch, held HELD_ROWS rows, then let go.
local function take(withSeam: boolean, loseFirstSet: boolean?): (World, { Model })
	local onField = enemy(9, "Kobold", "KoboldAxeman") -- a field enemy already there when the client starts
	local w = world(withSeam, { onField }, loseFirstSet)
	local remote = player(2, "Partner")
	w.players[remote] = true
	w.tag(w.localModel)
	w.tag(remote)
	local boar = enemy(7, "Boar", "FrenzyBoar")
	local kobold = enemy(8, "Kobold", "KoboldAxeman")
	holdAndRelease(w, { boar, kobold, onField }, {
		function()
			w.tag(boar)
			w.tag(kobold)
		end,
	})
	return w, { boar, kobold, onField, w.localModel, remote }
end

local function copyOf(w: World, model: Model): Copy
	return w.copies[model:FindFirstChildOfClass("Humanoid") :: Instance]
end

-- Upright to the end: Running through the release, the client's fall states read off, the log aid
-- done. A copy caught in time keeps its state machine (P1 L2) and never reads FallingDown; one
-- stood up (StoodUp) read it on the one row before and has its state machine off while it is held
-- (P1 L3), back on from the step after its release (D-559), so every copy ends on the field's
-- floor with it on.
local function expectUpright(w: World, model: Model, state: string, tries: number)
	local copy = copyOf(w, model)
	expect(copy.fallingRows).toBe(if state == UPRIGHT.states.stoodUp then 1 else 0)
	expect(copy.state).toBe("Running")
	expect(copy.heldEvaluates).toBe(state ~= UPRIGHT.states.stoodUp)
	expect(copy.evaluates).toBe(true)
	expect(copy.floor).toBe(FIELD)
	for _, name in FALLS do
		expect(copy.enabled[name]).toBe(false)
	end
	expect(model:GetAttribute(NAMES.state)).toBe(state)
	expect(model:GetAttribute(NAMES.why)).toBeNil()
	expect(model:GetAttribute(NAMES.tries)).toBe(tries)
end

-- Runs `body` with ai.upright.client's switches set as given, then puts them back.
local function withSwitches(switches: { [string]: any }, body: () -> ())
	local before: { [string]: any } = {}
	for key, value in switches do
		before[key] = (UPRIGHT :: any)[key];
		(UPRIGHT :: any)[key] = value
	end
	local ok, problem = pcall(body)
	for key, value in before do
		(UPRIGHT :: any)[key] = value
	end
	if not ok then
		error(problem, 0)
	end
end

-- A staged shot's boar and a kobold held at spawn whose Humanoids come after their tags in the
-- same frame (442's staged enemies; 443's #38; P1 #8, #10, #12).
local function lateHumanoids(): (World, { Model })
	local w = world(true, {})
	local boar, boarHumanoid = enemy(7, "Boar", "FrenzyBoar", true, true, true)
	local kobold, koboldHumanoid = enemy(38, "Kobold", "KoboldAxeman", true, true, true)
	holdAndRelease(w, { boar, kobold }, {
		function()
			w.tag(boar)
			w.tag(kobold)
			expect(boar:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.waiting)
			expect(boar:GetAttribute(NAMES.why)).toBe(UPRIGHT.whys.noHumanoid)
		end,
		function()
			w.parent(boarHumanoid, boar)
			w.parent(koboldHumanoid, kobold)
		end,
	})
	return w, { boar, kobold }
end

describe("A held enemy stands upright on this client (D-508)", function()
	it("turns the fall states off on every enemy's copy the frame it is met: no FallingDown row", function()
		local w, models = take(true)
		for index = 1, 3 do
			local copy = copyOf(w, models[index])
			-- 0582a04: FallingDown on 196 of 196 held rows (the PC's 183 to 196), never asked
			expect(copy.asked).toBe(1)
			expect(copy.askedSteps).toBe(0)
			expect(copy.enabledOnFirstRow).toBe(false)
			expect(copy.fallingRows).toBe(0)
			expect(copy.state).toBe("Running")
			for _, name in AI.upright.offStates do
				expect(copy.enabled[name]).toBe(false)
			end
		end
	end)

	it("never touches a player's character, the local one or another's", function()
		local w, models = take(true)
		for index = 4, 5 do
			local copy = copyOf(w, models[index])
			expect(copy.asked).toBe(0)
			expect(copy.enabled.FallingDown).toBe(true)
			expect(copy.enabled.Ragdoll).toBe(true)
			expect(models[index]:GetAttribute(NAMES.state)).toBeNil()
		end
	end)

	it("without the seam the held copies read FallingDown from the spawn to the release", function()
		local w, models = take(false)
		for index = 1, 3 do
			local copy = copyOf(w, models[index])
			expect(copy.enabledOnFirstRow).toBe(true)
			expect(copy.fallingRows).toBe(HELD_ROWS)
		end
	end)

	it("keepUpright turns off exactly the data's fall states, as the server does", function()
		local calls: { { string | boolean } } = {}
		Replication.keepUpright({
			SetStateEnabled = function(_self: any, stateType: any, on: boolean)
				table.insert(calls, { stateType.Name, on })
			end,
		})
		expect(#calls).toBe(#AI.upright.offStates)
		for index, name in AI.upright.offStates do
			expect(calls[index][1]).toBe(name)
			expect(calls[index][2]).toBe(false)
		end
	end)
end)

describe("A Humanoid that comes after its tag is caught as it arrives (D-543)", function()
	it("turns the states off inside the Humanoid's arrival: Running on every held row, Off, tries 2", function()
		-- 9063a60 and 4e60f11 (442, 443 #38, P1 L0): StoodUp, tries 2, FallingDown on every held
		-- row with GetStateEnabled(FallingDown) false; P1 L2 at the arrival: Running every row, Off / 2
		local w, models = lateHumanoids()
		for _, model in models do
			local copy = copyOf(w, model)
			expect(copy.askedSteps).toBe(0)
			expect(copy.askedState).toBe("None")
			expect(copy.enabledOnFirstRow).toBe(false)
			expect(copy.stateOnFirstRow).toBe("Running")
			expectUpright(w, model, UPRIGHT.states.off, 2)
		end
	end)

	it("lets the arrival handler go once the copy is upright, and when the rig leaves", function()
		local w, models = lateHumanoids()
		for _, model in models do
			expect(w.catches(model)).toBe(0)
		end
		local kobold, humanoid = enemy(39, "Kobold", "KoboldAxeman", true, true, true)
		w.frame({
			function()
				w.tag(kobold)
			end,
		})
		expect(w.catches(kobold)).toBe(if UPRIGHT.catchOnArrival then 1 else 0)
		Replication.unwatch(EntityTracker.fromModel(kobold))
		expect(w.catches(kobold)).toBe(0)
		w.frame({
			function()
				w.parent(humanoid, kobold)
			end,
		})
		expect(copyOf(w, kobold).asked).toBe(0)
	end)

	it("a player's character whose Humanoid and EntityKind come late is never touched", function()
		local w = world(true, {})
		local remote = player(2, "Partner", false)
		w.players[remote] = true
		local humanoid = remote:FindFirstChildOfClass("Humanoid") :: Instance
		humanoid.Parent = nil
		holdAndRelease(w, {}, {
			function()
				w.tag(remote)
			end,
			function()
				w.parent(humanoid, remote)
			end,
		}, {
			function()
				w.attribute(remote, "EntityKind", "Player")
			end,
		})
		local copy = copyOf(w, remote)
		expect(copy.asked).toBe(0)
		expect(copy.sets).toBe(0)
		expect(copy.evaluates).toBe(true)
		expect(remote:GetAttribute(NAMES.state)).toBeNil()
		expect(w.catches(remote)).toBe(0)
	end)

	it("with the arrival catch and the stand-up switched back, the copy reads the PC's 9063a60 rows", function()
		-- The fake against the PC (442, P1 L0): StoodUp, tries 2, FallingDown on every held row
		-- with GetStateEnabled(FallingDown) false, Running from the release row
		withSwitches({ catchOnArrival = false, rescue = UPRIGHT.rescues.changeState }, function()
			local w, models = lateHumanoids()
			for _, model in models do
				local copy = copyOf(w, model)
				expect(copy.askedState).toBe("FallingDown")
				expect(copy.fallingRows).toBe(HELD_ROWS)
				expect(copy.enabled.FallingDown).toBe(false)
				expect(copy.state).toBe("Running")
				expect(model:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.stoodUp)
				expect(model:GetAttribute(NAMES.tries)).toBe(2)
			end
		end)
	end)
end)

describe("A copy found already down is stood up with its state machine off (D-544)", function()
	it("without the catch, a held copy already down reads Running from the next row, still held", function()
		-- P1 L3 (#14): EvaluateStateMachine false then ChangeState(Running): Running at once and on
		-- 862 of 862 anchored rows; 4e60f11 (L4): FallingDown on every held row
		withSwitches({ catchOnArrival = false }, function()
			local w, models = lateHumanoids()
			for _, model in models do
				expect(copyOf(w, model).askedState).toBe("FallingDown")
				expectUpright(w, model, UPRIGHT.states.stoodUp, 2)
			end
		end)
	end)

	it("the ChangeState stand-up alone leaves a held copy down until its release (P1 L4)", function()
		withSwitches({ catchOnArrival = false, rescue = UPRIGHT.rescues.changeState }, function()
			local w = world(true, {})
			local boar = enemy(7, "Boar", "FrenzyBoar", true, false)
			holdAndRelease(w, { boar }, {
				function()
					w.tag(boar)
				end,
			}, {
				function()
					w.attribute(boar, "EntityKind", "Enemy")
				end,
			})
			local copy = copyOf(w, boar)
			expect(copy.fallingRows).toBe(HELD_ROWS)
			expect(copy.evaluates).toBe(true)
			expect(boar:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.stoodUp)
		end)
	end)
end)

describe("Every arrival order keeps the copy upright from its first physics step (D-523)", function()
	it("writes the log aid: Off on the first try when the batch brings everything", function()
		local w, models = take(true)
		for index = 1, 3 do
			expectUpright(w, models[index], UPRIGHT.states.off, 1)
		end
	end)

	it("an EntityKind that comes after the tag, in the same frame: off before the first step", function()
		-- 4b18b5c: never asked (EntityKind read nil when watched), FallingDown 196 of 196 held rows
		local w = world(true, {})
		local boar = enemy(7, "Boar", "FrenzyBoar", true, false)
		holdAndRelease(w, { boar }, {
			function()
				w.tag(boar)
				expect(boar:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.waiting)
				expect(boar:GetAttribute(NAMES.why)).toBe(UPRIGHT.whys.notEnemy)
			end,
			function()
				w.attribute(boar, "EntityKind", "Enemy")
			end,
		})
		expect(copyOf(w, boar).askedSteps).toBe(0)
		expect(copyOf(w, boar).enabledOnFirstRow).toBe(false)
		expectUpright(w, boar, UPRIGHT.states.off, 2)
	end)

	it("an EntityKind a frame late: the copy already down is stood up, one FallingDown row", function()
		-- 4b18b5c: FallingDown 196 of 196 held rows; 4e60f11 (stand-up by ChangeState, P1 L4): 196
		local w = world(true, {})
		local boar = enemy(7, "Boar", "FrenzyBoar", true, false)
		holdAndRelease(w, { boar }, {
			function()
				w.tag(boar)
			end,
		}, {
			function()
				w.attribute(boar, "EntityKind", "Enemy")
			end,
		})
		expect(copyOf(w, boar).stateOnFirstRow).toBe("FallingDown")
		-- the tag's try, the first PreSimulation's, then the EntityKind change's
		expectUpright(w, boar, UPRIGHT.states.stoodUp, 3)
	end)

	it("the tag before EntityId and EntityKind (the tracker's EntityId wait): off before the first step", function()
		-- 4b18b5c: never asked, FallingDown 196 of 196 held rows
		local w = world(true, {})
		local kobold = enemy(8, "Kobold", "KoboldAxeman", false, false)
		holdAndRelease(w, { kobold }, {
			function()
				w.tag(kobold)
				expect(EntityTracker.fromModel(kobold)).toBeNil()
			end,
			function()
				w.attribute(kobold, "EntityId", 8)
			end,
			function()
				w.attribute(kobold, "EntityKind", "Enemy")
			end,
		})
		expect(copyOf(w, kobold).enabledOnFirstRow).toBe(false)
		expectUpright(w, kobold, UPRIGHT.states.off, 2)
	end)

	it("a Humanoid a frame late: caught as it arrives, before its first physics step", function()
		-- 4e60f11: met at the next PreSimulation already down, FallingDown on every held row
		local w = world(true, {})
		local boar, humanoid = enemy(7, "Boar", "FrenzyBoar", true, true, true)
		holdAndRelease(w, { boar }, {
			function()
				w.tag(boar)
			end,
		}, {
			function()
				w.parent(humanoid, boar)
			end,
		})
		expect(copyOf(w, boar).askedSteps).toBe(0)
		expect(copyOf(w, boar).askedState).toBe("None")
		-- the tag's try, the PreSimulation's before the Humanoid came, then its arrival's
		expectUpright(w, boar, UPRIGHT.states.off, 3)
	end)

	it("a turn-off the engine drops is read back, and the copy it let fall is stood up", function()
		-- The assumed engine (header). 4b18b5c: GetStateEnabled true on the first row, FallingDown
		-- 196 of 196 held rows; 4e60f11 (stand-up by ChangeState, P1 L4): 196
		local w, models = take(true, true)
		-- the shot's boar and kobold: asked as tagged, fallen on that frame's physics step
		for index = 1, 2 do
			expect(copyOf(w, models[index]).enabledOnFirstRow).toBe(true)
			expectUpright(w, models[index], UPRIGHT.states.stoodUp, 2)
		end
		-- the field kobold, met before the first frame: asked again at its PreSimulation, in time
		expect(copyOf(w, models[3]).enabledOnFirstRow).toBe(false)
		expectUpright(w, models[3], UPRIGHT.states.off, 2)
	end)

	it("a pack-spawned kobold, standing at spawn and held later, is kept upright in every arrival order", function()
		-- PC 435(h) on 4b18b5c: a kobold's client Humanoid read FallingDown on 331 of 440 Idle rows.
		-- Each order brings an unanchored kobold; 60 rows later a hold anchors it (S("hold")) for
		-- HELD_ROWS rows, then lets it go. 4b18b5c: no FallingDown row only for the whole batch; every
		-- other order HELD_ROWS rows from the hold on, never asked. P1 L0 and L2 (#9, #13): Running.
		local function tag(w: World, model: Model): () -> ()
			return function()
				w.tag(model)
			end
		end
		local function set(w: World, model: Model, name: string, value: any): () -> ()
			return function()
				w.attribute(model, name, value)
			end
		end
		local function parent(w: World, humanoid: Instance?, model: Model): () -> ()
			return function()
				w.parent(humanoid, model)
			end
		end
		local orders: { any } = {
			{ name = "batch", tries = 1, first = { "tag" } },
			{ name = "EntityKind after the tag", tries = 2, kind = false, first = { "tag", "kind" } },
			{ name = "EntityKind a frame late", tries = 3, kind = false, first = { "tag" }, second = { "kind" } },
			{ name = "tag before EntityId", tries = 2, id = false, kind = false, first = { "tag", "id", "kind" } },
			{ name = "Humanoid after the tag", tries = 2, late = true, first = { "tag", "humanoid" } },
			{ name = "Humanoid a frame late", tries = 3, late = true, first = { "tag" }, second = { "humanoid" } },
			{ name = "first turn-off dropped", tries = 2, lose = true, first = { "tag" } },
		}
		for _, order in orders do
			local w = world(true, {}, order.lose)
			local kobold, humanoid = enemy(23, "Kobold", "KoboldAxeman", order.id, order.kind, order.late)
			rootOf(kobold).Anchored = false -- pack-spawned: standing, not held at spawn
			local function steps(names: { string }?): { () -> () }
				local list: { () -> () } = {}
				for _, step in names or {} do
					table.insert(
						list,
						if step == "tag"
							then tag(w, kobold)
							elseif step == "id" then set(w, kobold, "EntityId", 23)
							elseif step == "kind" then set(w, kobold, "EntityKind", "Enemy")
							else parent(w, humanoid, kobold)
					)
				end
				return list
			end
			w.frame(steps(order.first))
			w.frame(steps(order.second))
			for _ = 3, 60 do
				w.frame()
			end
			rootOf(kobold).Anchored = true
			for _ = 1, HELD_ROWS do
				w.frame()
			end
			rootOf(kobold).Anchored = false
			for _ = 1, AFTER_ROWS do
				w.frame()
			end
			local copy = copyOf(w, kobold)
			expect(order.name .. " " .. copy.fallingRows).toBe(order.name .. " 0")
			expect(order.name .. " " .. tostring(kobold:GetAttribute(NAMES.tries))).toBe(
				order.name .. " " .. order.tries
			)
			expectUpright(w, kobold, UPRIGHT.states.off, order.tries)
		end
	end)

	it("a player's character whose EntityKind comes late is never touched", function()
		local w = world(true, {})
		local remote = player(2, "Partner", false)
		w.players[remote] = true
		holdAndRelease(w, {}, {
			function()
				w.tag(remote)
				expect(remote:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.waiting)
			end,
		}, {
			function()
				w.attribute(remote, "EntityKind", "Player")
			end,
		})
		local copy = copyOf(w, remote)
		expect(copy.asked).toBe(0)
		expect(copy.sets).toBe(0)
		expect(remote:GetAttribute(NAMES.state)).toBeNil()
		expect(remote:GetAttribute(NAMES.why)).toBeNil()
		expect(remote:GetAttribute(NAMES.tries)).toBeNil()
	end)

	it("stops asking a copy that never comes up after maxTries steps", function()
		local w = world(true, {})
		local boar = enemy(7, "Boar", "FrenzyBoar", true, false)
		w.frame({
			function()
				w.tag(boar)
			end,
		})
		for _ = 1, UPRIGHT.maxTries + 20 do
			w.frame()
		end
		expect(boar:GetAttribute(NAMES.tries)).toBe(UPRIGHT.maxTries)
		expect(boar:GetAttribute(NAMES.why)).toBe(UPRIGHT.whys.notEnemy)
		-- an EntityKind that comes after that still asks at once
		w.frame({
			function()
				w.attribute(boar, "EntityKind", "Enemy")
			end,
		})
		expect(boar:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.stoodUp)
		expect(copyOf(w, boar).state).toBe("Running")
	end)

	it("standUpright reads the copy first, turns the states off, reads them back, then stands it up", function()
		local calls: { string } = {}
		local copy = newCopy(false, Instance.new("Part"))
		copy.state = "FallingDown"
		copy.root.Anchored = true
		local engine = engineHumanoid(copy)
		local spy: any = setmetatable({}, {
			__index = function(_, method: string)
				return function(_self: any, ...: any)
					local args = { ... }
					table.insert(calls, method .. (if args[1] ~= nil then " " .. args[1].Name else ""))
					return engine[method](engine, ...)
				end
			end,
			__newindex = function(_, property: string, value: any)
				table.insert(calls, property .. " " .. tostring(value))
				engine[property] = value
			end,
		})
		local state, why = Replication.standUpright(spy)
		expect(state).toBe(UPRIGHT.states.stoodUp)
		expect(why).toBeNil()
		expect(calls[1]).toBe("GetState")
		expect(calls[#calls]).toBe("ChangeState " .. UPRIGHT.standUpState)
		expect(copy.state).toBe(UPRIGHT.standUpState)
		expect(copy.evaluates).toBe(false)
		-- P1 L3's order: the state machine off before the ChangeState, on a copy still held
		expect(table.concat(calls, ",")).toBe(
			"GetState,GetStateEnabled FallingDown,SetStateEnabled FallingDown,GetStateEnabled Ragdoll,"
				.. "SetStateEnabled Ragdoll,GetStateEnabled Physics,SetStateEnabled Physics,"
				.. "GetStateEnabled PlatformStanding,SetStateEnabled PlatformStanding,GetStateEnabled FallingDown,"
				.. "GetStateEnabled Ragdoll,GetStateEnabled Physics,GetStateEnabled PlatformStanding,"
				.. "EvaluateStateMachine false,ChangeState Running"
		)
	end)
end)

-- One logged row of 474(e)'s take: the copy as the engine left it, and what the game's readers
-- of its floor get from it (the real SfxPool's footstep surface, the real enemy gait tracker's
-- grounded).
type Row = {
	held: boolean,
	state: string,
	evaluates: boolean,
	floor: string,
	surface: string,
	grounded: boolean,
}

-- 474(e)'s take on this client (P1 #8, 443 #38): a fresh kobold whose Humanoid comes after its tag
-- in the same frame, held at spawn for HELD_ROWS rows, let go (its root's Anchored replicated in a
-- frame's arrivals), then walking WALK_ROWS rows (39 studs over 5 s). Rows from the first frame.
local function rescueWalk(downOnResume: boolean?): (World, Model, { Row })
	local w = world(true, {}, nil, downOnResume)
	local kobold, humanoid = enemy(8, "Kobold", "KoboldAxeman", true, true, true)
	local root = rootOf(kobold)
	-- Lune's parts keep Position apart from CFrame; the tracker reads both.
	root.Position = root.CFrame.Position
	root.AssemblyLinearVelocity = Vector3.zero;
	(humanoid :: any).MoveDirection = Vector3.zero
	local tracker = Locomotion.humanoidTracker(kobold)
	local rows: { Row } = {}
	local function log()
		local copy = copyOf(w, kobold)
		local state = tracker(1 / 60)
		table.insert(rows, {
			held = root.Anchored,
			state = copy.state,
			evaluates = copy.evaluates,
			floor = copy.floor,
			surface = SfxPool.surfaceOf(kobold),
			grounded = state ~= nil and state.grounded == true,
		})
	end
	w.frame({
		function()
			w.tag(kobold)
		end,
		function()
			w.parent(humanoid, kobold)
		end,
	})
	log()
	for _ = 2, HELD_ROWS do
		w.frame()
		log()
	end
	w.frame({
		function()
			root.Anchored = false
		end,
	})
	log()
	for _ = 2, WALK_ROWS do
		root.CFrame += Vector3.new(0, 0, WALK_STEP)
		root.Position = root.CFrame.Position
		root.AssemblyLinearVelocity = Vector3.new(0, 0, WALK_STEP * 60)
		w.frame()
		log()
	end
	return w, kobold, rows
end

-- How many of rows[from .. to] match.
local function count(rows: { Row }, from: number, to: number, match: (row: Row) -> boolean): number
	local n = 0
	for index = from, to do
		if match(rows[index]) then
			n += 1
		end
	end
	return n
end

local function onField(row: Row): boolean
	return row.floor == FIELD and row.surface == FIELD_SURFACE and row.grounded
end

describe("A copy stood up with its state machine off gets it back at its release (D-559)", function()
	local RELEASE = HELD_ROWS + 1 -- the row whose frame let the root go
	local LAST = HELD_ROWS + WALK_ROWS

	it("with the stand-up's state machine kept off, the copy reads the PC's 474(e) rows on 209875b", function()
		-- The fake against the PC (474(e), the rescue build): StoodUp, tries 2, Running on every held
		-- row, EvaluateStateMachine false, FloorMaterial Air on every row held and walking (536 of 536)
		withSwitches({ catchOnArrival = false, resumeOnRelease = false }, function()
			local w, kobold, rows = rescueWalk()
			-- the fall on the first step (the PC's first logged row is after the stand-up), then
			-- every row from the stand-up on
			expect(rows[1].state).toBe("FallingDown")
			expect(count(rows, 2, LAST, function(row)
				return row.state == "Running" and not row.evaluates
			end)).toBe(LAST - 1)
			expect(count(rows, 2, LAST, function(row)
				return row.floor == "Air" and row.surface == Fx.audio.defaultSurface and not row.grounded
			end)).toBe(LAST - 1)
			expect(kobold:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.stoodUp)
			expect(kobold:GetAttribute(NAMES.tries)).toBe(2)
			expect(copyOf(w, kobold).machineWrites).toEqual({ false })
		end)
	end)

	it(
		"the rescue build: off while held, back on the step after the release, the field's floor on every walking row",
		function()
			-- 318f0a3: FloorMaterial Air, footsteps on Stone and the gait tracker airborne on 300 of 300
			-- released rows, the state machine off for good
			withSwitches({ catchOnArrival = false }, function()
				local w, kobold, rows = rescueWalk()
				local copy = copyOf(w, kobold)
				-- held: P1 L3's rows, unchanged (FallingDown on at most the first row, then Running)
				expect(rows[1].state).toBe("FallingDown")
				expect(count(rows, 2, HELD_ROWS, function(row)
					return row.held and row.state == "Running" and not row.evaluates
				end)).toBe(HELD_ROWS - 1)
				-- the release row is stepped before the next PreSimulation sees it: still off, Air
				expect(rows[RELEASE].held).toBe(false)
				expect(rows[RELEASE].evaluates).toBe(false)
				expect(rows[RELEASE].floor).toBe("Air")
				-- every walking row after it: the state machine on, Running, the field's floor and surface
				expect(count(rows, RELEASE + 1, LAST, function(row)
					return row.evaluates and row.state == "Running" and onField(row)
				end)).toBe(WALK_ROWS - 1)
				expect(copy.fallingRows).toBe(1)
				expect(copy.machineWrites).toEqual({ false, true })
				-- read once by the stand-up, then resumeChecks times after the turn-on, then let go
				expect(copy.reads).toBe(1 + UPRIGHT.resumeChecks)
				expect(kobold:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.stoodUp)
				expect(kobold:GetAttribute(NAMES.tries)).toBe(2)
				for _, name in FALLS do
					expect(copy.enabled[name]).toBe(false)
				end
				-- held again later (S("hold")): the main path's copy, Running on every row (P1 L2 #13)
				rootOf(kobold).Anchored = true
				for _ = 1, HELD_ROWS do
					w.frame()
				end
				expect(copy.fallingRows).toBe(1)
				expect(copy.state).toBe("Running")
				expect(copy.evaluates).toBe(true)
				expect(copy.floor).toBe(FIELD)
			end)
		end
	)

	it("the main path is unchanged: caught at its arrival, the state machine never written", function()
		-- D-543 (474(a) on 209875b): Off, tries 2, Running and EvaluateStateMachine true on every
		-- row, FloorMaterial Grass
		local w, kobold, rows = rescueWalk()
		expect(count(rows, 1, LAST, function(row)
			return row.evaluates and row.state == "Running" and onField(row)
		end)).toBe(LAST)
		expect(copyOf(w, kobold).machineWrites).toEqual({})
		expect(kobold:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.off)
		expect(kobold:GetAttribute(NAMES.tries)).toBe(2)
	end)

	it("a copy the state machine lays down for the step after its turn-on rides it out (D-589)", function()
		-- The once-assumed engine (header), since measured (495(d), (i) on 82b82d4): the step after
		-- the turn-on reads FallingDown, the server's Running follows. The next PreSimulation's
		-- read-back waits it out: the state machine stays on. 81b8fef: read back at once, the state
		-- machine off for good (writes false, true, false) and Air with it on every row after.
		withSwitches({ catchOnArrival = false }, function()
			local w, kobold, rows = rescueWalk(true)
			local copy = copyOf(w, kobold)
			expect(rows[RELEASE + 1].state).toBe("FallingDown")
			expect(rows[RELEASE + 1].evaluates).toBe(true)
			expect(count(rows, RELEASE + 2, LAST, function(row)
				return row.state == "Running" and row.evaluates and onField(row)
			end)).toBe(WALK_ROWS - 2)
			expect(copy.fallingRows).toBe(2)
			expect(copy.machineWrites).toEqual({ false, true })
			expect(copy.state).toBe("Running")
		end)
	end)

	it("the ChangeState stand-up never turns the state machine off, so nothing comes back on", function()
		withSwitches({ catchOnArrival = false, rescue = UPRIGHT.rescues.changeState }, function()
			local w, kobold, rows = rescueWalk()
			local copy = copyOf(w, kobold)
			-- P1 L4: FallingDown on every held row; Running from the release with it on
			expect(copy.fallingRows).toBe(HELD_ROWS)
			expect(copy.machineWrites).toEqual({})
			expect(count(rows, RELEASE, LAST, function(row)
				return row.evaluates and row.state == "Running" and onField(row)
			end)).toBe(WALK_ROWS)
		end)
	end)

	it("resumeUpright waits while held, turns the state machine on once let go, then reads the copy back", function()
		local calls: { string } = {}
		local copy = newCopy(false, Instance.new("Part"))
		copy.root.Anchored = true
		copy.evaluates = false
		copy.state = "Running"
		local engine = engineHumanoid(copy)
		local spy: any = setmetatable({}, {
			__index = function(_, key: string): any
				if key == "EvaluateStateMachine" then
					return engine.EvaluateStateMachine
				end
				return function(_self: any, ...: any)
					local args = { ... }
					table.insert(calls, key .. (if args[1] ~= nil then " " .. args[1].Name else ""))
					return engine[key](engine, ...)
				end
			end,
			__newindex = function(_, property: string, value: any)
				table.insert(calls, property .. " " .. tostring(value))
				engine[property] = value
			end,
		})
		local RESUME = Replication.RESUME
		-- held: nothing written (P1 L3's anchored copy, off)
		expect(Replication.resumeUpright(spy, copy.root)).toBe(RESUME.held)
		expect(table.concat(calls, ",")).toBe("")
		-- let go: on, before that step's physics
		copy.root.Anchored = false
		expect(Replication.resumeUpright(spy, copy.root)).toBe(RESUME.resumed)
		expect(table.concat(calls, ",")).toBe("EvaluateStateMachine true")
		-- read back upright
		expect(Replication.resumeUpright(spy, copy.root)).toBe(RESUME.on)
		-- read back in a fall state: D-544's stand-up, the state machine off first
		copy.state = "FallingDown"
		expect(Replication.resumeUpright(spy, copy.root)).toBe(RESUME.keptOff)
		expect(table.concat(calls, ",")).toBe(
			"EvaluateStateMachine true,GetState,GetState,EvaluateStateMachine false,ChangeState Running"
		)
		expect(copy.state).toBe(UPRIGHT.standUpState)
		expect(copy.evaluates).toBe(false)
		-- no root (a model without its PrimaryPart yet) counts as held
		local idle = newCopy(false, Instance.new("Part"))
		idle.evaluates = false
		expect(Replication.resumeUpright(engineHumanoid(idle), nil)).toBe(RESUME.held)
		expect(idle.machineWrites).toEqual({})
	end)

	it("a copy that leaves before its release is let go", function()
		withSwitches({ catchOnArrival = false }, function()
			local w = world(true, {})
			local kobold, humanoid = enemy(8, "Kobold", "KoboldAxeman", true, true, true)
			holdAndRelease(w, {}, {
				function()
					w.tag(kobold)
				end,
				function()
					w.parent(humanoid, kobold)
				end,
			})
			local copy = copyOf(w, kobold)
			expect(copy.machineWrites).toEqual({ false })
			Replication.unwatch(EntityTracker.fromModel(kobold))
			rootOf(kobold).Anchored = false
			for _ = 1, 5 do
				w.frame()
			end
			expect(copy.machineWrites).toEqual({ false })
		end)
	end)
end)

-- 495's take on this client (82b82d4's rescue build, catchOnArrival false), on the engine the PC
-- measured there (`Measured`, header): rescueWalk's kobold held at spawn HELD_ROWS rows, `turnOnAt`
-- (495(i)) the held row whose frame turns its state machine on from outside (the Client command
-- bar, after that frame's PreSimulation), the hold's end landing before the next frame's
-- PreSimulation (R = HELD_ROWS + 1), WALK_ROWS walking rows, then (`again`, actions 3) held
-- HELD_ROWS rows more and let go for AFTER_ROWS.
local function take495(measured: Measured, turnOnAt: number?, again: boolean?): (World, Model, { Row })
	local w = world(true, {}, nil, nil, measured)
	local kobold, humanoid = enemy(8, "Kobold", "KoboldAxeman", true, true, true)
	local root = rootOf(kobold)
	root.Position = root.CFrame.Position
	root.AssemblyLinearVelocity = Vector3.zero;
	(humanoid :: any).MoveDirection = Vector3.zero
	local tracker = Locomotion.humanoidTracker(kobold)
	local rows: { Row } = {}
	local function log()
		local copy = copyOf(w, kobold)
		local state = tracker(1 / 60)
		table.insert(rows, {
			held = root.Anchored,
			state = copy.state,
			evaluates = copy.evaluates,
			floor = copy.floor,
			surface = SfxPool.surfaceOf(kobold),
			grounded = state ~= nil and state.grounded == true,
		})
	end
	w.frame({
		function()
			w.tag(kobold)
		end,
		function()
			w.parent(humanoid, kobold)
		end,
	})
	log()
	for row = 2, HELD_ROWS do
		w.frame(if row == turnOnAt
			then {
				function()
					engineHumanoid(copyOf(w, kobold)).EvaluateStateMachine = true
				end,
			}
			else nil)
		log()
	end
	root.Anchored = false
	for row = 1, WALK_ROWS do
		if row > 1 then
			root.CFrame += Vector3.new(0, 0, WALK_STEP)
			root.Position = root.CFrame.Position
			root.AssemblyLinearVelocity = Vector3.new(0, 0, WALK_STEP * 60)
		end
		w.frame()
		log()
	end
	if again then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
		for _ = 1, HELD_ROWS do
			w.frame()
			log()
		end
		root.Anchored = false
		for _ = 1, AFTER_ROWS do
			w.frame()
			log()
		end
	end
	return w, kobold, rows
end

-- A 60 Hz server's steps on a 144 Hz client: frame n brings the server's state when a step landed
-- since frame n - 1 (60 of every 144 frames).
local function serverAt144(n: number): boolean
	return math.floor(n * 60 / 144) > math.floor((n - 1) * 60 / 144)
end

describe("The turn-on's own fall is waited out, held or let go (495 on 82b82d4, D-589)", function()
	local R = HELD_ROWS + 1 -- the first row whose root reads let go
	local LAST = HELD_ROWS + WALK_ROWS

	it("the rescue build reads the PC's 495 rows on 82b82d4: one FallingDown row on R, then Running", function()
		-- The fake against the PC (82b82d4, the rescue build at 60 fps): held rows Running with the
		-- state machine off (204 of 204), R FallingDown with EvaluateStateMachine true, Anchored
		-- false and Air, then Running, Grass and the state machine on every row (565 of 565) through
		-- the walk, the second hold (204 of 204) and the rows after. Unchanged by D-589.
		withSwitches({ catchOnArrival = false }, function()
			local w, kobold, rows = take495({}, nil, true)
			local copy = copyOf(w, kobold)
			expect(count(rows, 2, HELD_ROWS, function(row)
				return row.held and row.state == "Running" and not row.evaluates and row.floor == "Air"
			end)).toBe(HELD_ROWS - 1)
			expect(rows[R].held).toBe(false)
			expect(rows[R].evaluates).toBe(true)
			expect(rows[R].state).toBe("FallingDown")
			expect(rows[R].floor).toBe("Air")
			expect(count(rows, R + 1, #rows, function(row)
				return row.evaluates and row.state == "Running" and onField(row)
			end)).toBe(#rows - R)
			expect(count(rows, LAST + 1, LAST + HELD_ROWS, function(row)
				return row.held
			end)).toBe(HELD_ROWS)
			expect(copy.machineWrites).toEqual({ false, true })
			expect(copy.fallingRows).toBe(2) -- the first held row (before the stand-up) and R
			expect(kobold:GetAttribute(NAMES.state)).toBe(UPRIGHT.states.stoodUp)
			expect(kobold:GetAttribute(NAMES.tries)).toBe(2)
		end)
	end)

	it("a turn-on while held falls for its row, goes back off until the release, then comes back", function()
		-- 495(i) on 82b82d4: the command bar's turn-on reads true with FallingDown on its row, then
		-- false with Running and Air on every held row after (204 of 204). 81b8fef: that read-back
		-- keeps it off for good, so after the release the walk reads Air, the stone footstep set
		-- and the gait airborne on every row (0 of 299 on the field; machine writes false, true,
		-- false); now 299 of 299, as a copy never turned on while held.
		withSwitches({ catchOnArrival = false }, function()
			local turnOnAt = 100
			local w, kobold, rows = take495({}, turnOnAt)
			local copy = copyOf(w, kobold)
			expect(rows[turnOnAt].evaluates).toBe(true)
			expect(rows[turnOnAt].state).toBe("FallingDown")
			expect(count(rows, turnOnAt + 1, HELD_ROWS, function(row)
				return row.held and row.state == "Running" and not row.evaluates and row.floor == "Air"
			end)).toBe(HELD_ROWS - turnOnAt)
			expect(rows[R].evaluates).toBe(true)
			expect(count(rows, R + 1, LAST, function(row)
				return row.evaluates and row.state == "Running" and onField(row)
			end)).toBe(WALK_ROWS - 1)
			-- the stand-up, the command bar, the read-back's turn-off while held, the release
			expect(copy.machineWrites).toEqual({ false, true, false, true })
		end)
	end)

	it("a let-go copy the server's state reaches a few frames late keeps its state machine (assumed engine)", function()
		-- `packets`: a 60 Hz server on a 144 Hz client (header). The frames after R's bring no server
		-- step, so the read-back meets the turn-on's fall: 81b8fef turned the state machine off for
		-- good there (Air, stone footsteps and the gait airborne on every row after: 0 of 297 on
		-- the field); now it waits for the copy's first Running (3 fall rows, then 297 of 297).
		withSwitches({ catchOnArrival = false }, function()
			expect(serverAt144(R + 1)).toBe(false)
			expect(serverAt144(R + 2)).toBe(false)
			expect(serverAt144(R + 3)).toBe(true)
			local w, kobold, rows = take495({ packets = serverAt144 })
			local copy = copyOf(w, kobold)
			expect(count(rows, R, R + 2, function(row)
				return row.state == "FallingDown" and row.evaluates
			end)).toBe(3)
			expect(count(rows, R + 3, LAST, function(row)
				return row.evaluates and row.state == "Running" and onField(row)
			end)).toBe(WALK_ROWS - 3)
			expect(copy.machineWrites).toEqual({ false, true })
		end)
	end)

	it("a copy kept down after its turn-on is stood up with it off for good after resumeSettleSteps (D-544)", function()
		-- `staysDown` (assumed, never seen): every step with the state machine on lays it down
		-- whatever the server says. The read-back waits resumeSettleSteps steps, then D-544's
		-- stand-up for good. 81b8fef: the same end, one row after R.
		withSwitches({ catchOnArrival = false }, function()
			local settle = UPRIGHT.resumeSettleSteps
			local w, kobold, rows = take495({ staysDown = true })
			local copy = copyOf(w, kobold)
			expect(count(rows, R, R + settle, function(row)
				return row.state == "FallingDown" and row.evaluates
			end)).toBe(settle + 1)
			expect(count(rows, R + settle + 1, LAST, function(row)
				return row.state == "Running" and not row.evaluates and row.floor == "Air"
			end)).toBe(LAST - R - settle)
			expect(copy.machineWrites).toEqual({ false, true, false })
		end)
	end)

	it("resumeUpright waits out a let-go copy's fall while settling, and puts a held one back off", function()
		local calls: { string } = {}
		local copy = newCopy(false, Instance.new("Part"))
		copy.state = "FallingDown"
		local engine = engineHumanoid(copy)
		local spy: any = setmetatable({}, {
			__index = function(_, key: string): any
				if key == "EvaluateStateMachine" then
					return engine.EvaluateStateMachine
				end
				return function(_self: any, ...: any)
					local args = { ... }
					table.insert(calls, key .. (if args[1] ~= nil then " " .. args[1].Name else ""))
					return engine[key](engine, ...)
				end
			end,
			__newindex = function(_, property: string, value: any)
				table.insert(calls, property .. " " .. tostring(value))
				engine[property] = value
			end,
		})
		local RESUME = Replication.RESUME
		-- let go, the state machine on, in its turn-on's fall: read, nothing written
		copy.root.Anchored = false
		expect(Replication.resumeUpright(spy, copy.root, true)).toBe(RESUME.settling)
		expect(table.concat(calls, ",")).toBe("GetState")
		expect(copy.evaluates).toBe(true)
		-- held, the state machine on, down (495(i)): D-544's stand-up, waiting for the release
		copy.root.Anchored = true
		expect(Replication.resumeUpright(spy, copy.root, true)).toBe(RESUME.heldOff)
		expect(table.concat(calls, ",")).toBe(
			"GetState,GetState,EvaluateStateMachine false,ChangeState " .. UPRIGHT.standUpState
		)
		expect(copy.evaluates).toBe(false)
		expect(copy.state).toBe(UPRIGHT.standUpState)
	end)
end)
