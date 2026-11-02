--!strict
--[[
	A held enemy stands upright on this client too (D-508, D-523, D-543, D-544, the client side
	of D-494). The server turns its enemy Humanoids' fall states off (ai.upright.offStates) on the
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
	  3.40-3.46, lowest leg corner -0.032 to 0.000 with and without FallingDown).

	One frame here: the beforePhysics step (PreSimulation), then what replication brings (each
	arrival with its handlers, in order; a Humanoid's parenting fires the model's arrival seam,
	start()'s ChildAdded), then this client's physics on every copy, then the logged row. Where in
	Studio's frame the copy first falls is not measured; that it has fallen by the next
	PreSimulation and not inside its own arrival handler is (442, P1). Also assumed for one case
	only: an engine that loses the first SetStateEnabled made on a copy (never seen since 4b18b5c).
]]

local EntityTracker = Harness.load("src/client/controllers/EntityTracker")
local Replication = Harness.load("src/client/controllers/Replication")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local AI = Harness.load("src/shared/data/ai")

local UPRIGHT = AI.upright.client
local NAMES = UPRIGHT.attributes
local FALLS = UPRIGHT.offStates

-- The PC's longest held stretch in a take (rows from the spawn to the release, 398(a)).
local HELD_ROWS = 196
local AFTER_ROWS = 60

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
}

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

local function newCopy(loseFirstSet: boolean, root: BasePart): Copy
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
	}
end

-- What the seam's FindFirstChildOfClass hands Replication: the copy behind the engine's methods
-- and its EvaluateStateMachine property.
local function engineHumanoid(copy: Copy): any
	local methods = {
		GetState = function(_self: any): any
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

local function world(withSeam: boolean, onField: { Model }, loseFirstSet: boolean?): World
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
			copy = newCopy(loseFirstSet == true, rootOf(humanoid.Parent :: Model))
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
			if copy.evaluates and copy.root.Anchored then
				-- An anchored copy falls on its step while FallingDown is on, and stays down: the
				-- state machine never takes it out while the root stays anchored (P1 L4).
				if copy.state ~= "FallingDown" then
					copy.state = if copy.enabled.FallingDown then "FallingDown" else "Running"
				end
			elseif copy.evaluates then
				copy.state = "Running" -- the server's state, once the root is let go
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
-- stood up (StoodUp) read it on the one row before and has its state machine off (P1 L3).
local function expectUpright(w: World, model: Model, state: string, tries: number)
	local copy = copyOf(w, model)
	expect(copy.fallingRows).toBe(if state == UPRIGHT.states.stoodUp then 1 else 0)
	expect(copy.state).toBe("Running")
	expect(copy.evaluates).toBe(state ~= UPRIGHT.states.stoodUp)
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
