--!strict
--[[
	A dead rig's plate leaves on the body's own frame (Studio at c73cfa8: the plate went 0.834 s
	after the killing swing and the body's parts hid at 0.852 s, one frame apart).

	The real chain: Replication's EntityDied schedules the shatter (Combat.deathFreeze after the
	kill's hit-stop, Moments.deathDuckDelay) and Shatter's hideRig hides the rig's parts and takes
	its plate; Nameplates, told by EntityTracker that the record turned Dead, keeps its own
	fallback for a rig that never shatters here. Both deadlines are the same sum, but they run on
	two clocks: the plate's on Engine.now (os.clock) checked each Heartbeat, the shatter's on the
	engine's task.delay.

	The engine is played frame by frame at 60 fps (with a little jitter): the network's messages
	are handled early in the frame, the local blade's contact in the render step, the Heartbeat
	late in the frame, and what stands after the Heartbeat is what the next frame draws. task.delay
	is played three ways, since the specs cannot see the engine's scheduler:
	  frameClock  the deadline is the clock at the call plus the seconds, and a delayed function
	              resumes on the first Heartbeat whose frame (its start) has passed it: the plate's
	              os.clock check passes on the frame before (what Studio showed);
	  precise     it resumes on the first Heartbeat whose clock has passed it;
	  late        frameClock, and the delayed functions run after the Heartbeat's connections.
]]

local Engine = Harness.load("src/client/fx/Engine")
local Nameplates = Harness.load("src/client/ui/Nameplates")
local EntityTracker = Harness.load("src/client/controllers/EntityTracker")
local Replication = Harness.load("src/client/controllers/Replication")
local Shatter = Harness.load("src/client/fx/Shatter")
local SfxPool = Harness.load("src/client/audio/SfxPool")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local UI = Harness.load("src/shared/data/ui")
local Combat = Harness.load("src/shared/data/combat")
local Moments = Harness.load("src/shared/data/moments")
local Enemies = Harness.load("src/shared/data/enemies")

local FRAME = 1 / 60
-- Where in its frame each step runs, in frames from the frame's start.
local NETWORK_AT = 0.15
local RENDER_AT = 0.3
local HEARTBEAT_AT = 0.8
-- The fallback of a shatter that is coming: after its time, by the grace.
local DEATH_SECONDS = Moments.deathDuckDelay() + Combat.deathFreeze

local BOAR = Enemies.byId("FrenzyBoar")

local clock = 1000
Engine.setClock(function()
	return clock
end)
Engine.setViewer(function()
	return Vector3.zero
end)

-- The shatter's cue plays into the void.
local quietSounds = {
	now = function(): number
		return clock
	end,
	delay = function(_seconds: number, _fn: () -> ()) end,
	onStep = function(_fn: (number) -> ()): () -> ()
		return function() end
	end,
	play = function(_sound: Sound): boolean
		return true
	end,
	stop = function(_sound: Sound) end,
	timeLength = function(_sound: Sound): number
		return 30
	end,
	preload = function(_sounds: { Instance }) end,
}

local handlers: { [any]: { [string]: () -> () } } = {}

local function bindTracker()
	EntityTracker.bind({
		tagged = function()
			return {}
		end,
		instanceAdded = function() end,
		instanceRemoved = function() end,
		attributeChanged = function(model, attribute, handler)
			handlers[model] = handlers[model] or {}
			handlers[model][attribute] = handler
			return { Disconnect = function() end }
		end,
		localCharacter = function()
			return nil
		end,
		characterAdded = function() end,
	})
end

local function setAttribute(model: Instance, attribute: string, value: any)
	model:SetAttribute(attribute, value)
	local handler = handlers[model] and handlers[model][attribute]
	if handler ~= nil then
		handler()
	end
end

-- Every call is a no-op; a few answer what Replication reads back.
local function quiet(): any
	return setmetatable({}, {
		__index = function()
			return function()
				return nil
			end
		end,
	})
end

local function fakeAnimator(): any
	return setmetatable({}, {
		__index = function(_self: any, key: string): any
			if key == "pauseRemaining" then
				return function(): number
					return 0
				end
			elseif key == "play" then
				return function(): any
					return {}
				end
			elseif key == "events" then
				return nil
			end
			return function() end
		end,
	})
end

local nextId = 7000
local function rig(kind: string, defId: string?): (Model, number, BasePart)
	nextId += 1
	local model = Instance.new("Model")
	model.Name = kind .. nextId
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = model
	model.PrimaryPart = root
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Parent = model
	-- Lune keeps no engine defaults: the parts start drawn.
	root.LocalTransparencyModifier = 0
	torso.LocalTransparencyModifier = 0
	model:SetAttribute("EntityId", nextId)
	model:SetAttribute("EntityKind", kind)
	model:SetAttribute("DisplayName", model.Name)
	model:SetAttribute("HP", 100)
	model:SetAttribute("MaxHP", 100)
	model:SetAttribute("State", "Idle")
	if defId ~= nil then
		model:SetAttribute("DefId", defId)
		model:SetAttribute("Rig", BOAR.skin)
	end
	return model, nextId, torso
end

type Scheduler = "frameClock" | "precise" | "late"
type Kill = {
	killer: "local" | "remote",
	contactTier: string?, -- the local blade's contact (nil: no contact)
	artId: string?,
	windowIndex: number,
	confirmAfter: number, -- seconds from the contact (or the start) to the server's word
	diedFirst: boolean?, -- EntityDied handled before the Dead attribute
	noDeath: boolean?, -- EntityDied never comes (a rig that never shatters here)
	dropShatter: boolean?, -- the scheduled shatter never runs
	scheduler: Scheduler,
	jitter: number?,
	stallFrame: number?, -- this frame takes `stall` seconds (a render stall)
	stall: number?,
}

type Outcome = { plate: number?, body: number?, contactFrame: number, confirmFrame: number? }

local function runKill(kill: Kill): Outcome
	bindTracker()
	Nameplates.start()
	local me, meId = rig("Player")
	local other, otherId = rig("Player")
	local boar, boarId, torso = rig("Enemy", BOAR.id)
	for _, model in { me, other, boar } do
		EntityTracker.track(model)
	end
	local animators = { [me] = fakeAnimator(), [other] = fakeAnimator(), [boar] = fakeAnimator() }
	local pending: { { deadline: number, fn: () -> (), order: number } } = {}
	local order = 0
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return EntityTracker.get(id)
			end,
		},
		localId = function(): number?
			return meId
		end,
		locomotion = quiet(),
		choreo = {
			get = function(model: any): any
				return animators[model] or fakeAnimator()
			end,
		},
		clipLibrary = ClipLibrary,
		trails = quiet(),
		smear = quiet(),
		shatter = Shatter,
		sparks = quiet(),
		telegraphs = quiet(),
		outline = quiet(),
		switchRing = quiet(),
		digits = quiet(),
		hud = quiet(),
		systemLine = quiet(),
		sfx = quiet(),
		impact = quiet(),
		camera = quiet(),
		weaponCategory = function(): string
			return "OneHandedSword"
		end,
		trailToken = function(): string
			return "TrailCyanWhite"
		end,
		positionOf = function(): Vector3
			return Vector3.zero
		end,
		schedule = function(seconds: number, fn: () -> ())
			order += 1
			table.insert(pending, { deadline = clock + seconds, fn = fn, order = order })
		end,
		now = function(): number
			return clock
		end,
		serverNow = function(): number
			return clock
		end,
	} :: any)
	SfxPool.bind(quietSounds)

	local plate = Nameplates.plateOf(boarId)
	assert(plate ~= nil and plate.gui.Enabled, "the boar has a live plate")
	local random = Random.new(nextId)
	local contactFrame = 10
	local confirmAt: number? = nil
	local outcome: Outcome = { plate = nil, body = nil, contactFrame = contactFrame, confirmFrame = nil }
	local start = clock
	local killer = if kill.killer == "local" then meId else otherId

	local function confirm()
		local function died()
			Replication.dispatch("EntityDied", {
				entityId = boarId,
				shatter = BOAR.shatter,
				position = { 0, 3, 0 },
				name = BOAR.name,
				byPlayer = true,
			})
		end
		if kill.diedFirst and not kill.noDeath then
			died()
		end
		setAttribute(boar, "HP", 0)
		setAttribute(boar, "State", "Dead")
		Replication.dispatch("StateChanged", { entityId = boarId, state = "Dead" })
		if not kill.diedFirst and not kill.noDeath then
			died()
		end
		Replication.dispatch("HitConfirmed", {
			attackerId = killer,
			targetId = boarId,
			hitIndex = kill.windowIndex,
			artId = kill.artId,
			damage = 100,
			crit = false,
			killed = true,
			hitStop = "Kill",
			position = { 0, 3, 0 },
		})
	end

	local function runDue(frameStart: number)
		table.sort(pending, function(a, b)
			if a.deadline ~= b.deadline then
				return a.deadline < b.deadline
			end
			return a.order < b.order
		end)
		local passed = if kill.scheduler == "precise" then clock else frameStart
		while pending[1] ~= nil and pending[1].deadline <= passed do
			local entry = table.remove(pending, 1) :: any
			-- The shatter is the one scheduled at the death's full length.
			local isShatter = math.abs((entry.deadline - (confirmAt or 0)) - DEATH_SECONDS) < 0.05
			if not (kill.dropShatter and isShatter) then
				entry.fn()
			end
		end
	end

	for frame = 1, 140 do
		local length = FRAME + (if kill.jitter ~= nil then (random:NextNumber() * 2 - 1) * kill.jitter else 0)
		if kill.stallFrame ~= nil and frame == kill.stallFrame then
			length = kill.stall :: number
		end
		local frameStart = start
		-- The network: the server's word on the kill.
		clock = frameStart + NETWORK_AT * length
		local confirmFrame = contactFrame + math.ceil(kill.confirmAfter / FRAME - 1e-9)
		if frame == confirmFrame then
			confirmAt = clock
			outcome.confirmFrame = frame
			confirm()
		end
		-- The render step: the local blade touches the boar.
		clock = frameStart + RENDER_AT * length
		if frame == contactFrame and kill.contactTier ~= nil then
			Replication.contact({
				targetId = boarId,
				windowIndex = kill.windowIndex,
				artId = kill.artId,
				tier = kill.contactTier,
				position = Vector3.new(0, 3, 0),
			})
		end
		-- The Heartbeat: delayed functions and the plates' step, in the engine's order.
		clock = frameStart + HEARTBEAT_AT * length
		if kill.scheduler ~= "late" then
			runDue(frameStart)
		end
		Nameplates.step(length)
		if kill.scheduler == "late" then
			runDue(frameStart)
		end
		-- What the next frame draws.
		if outcome.plate == nil and not plate.gui.Enabled then
			outcome.plate = frame
		end
		if outcome.body == nil and torso.LocalTransparencyModifier >= 1 then
			outcome.body = frame
		end
		start = frameStart + length
		clock = start
	end
	SfxPool.reset()
	SfxPool.bind(nil)
	for _, model in { me, other, boar } do
		EntityTracker.untrack(model)
	end
	return outcome
end

local KILLS: { { label: string, kill: Kill } } = {}
for _, after in { 0, 0.1, 0.25 } do
	table.insert(KILLS, {
		label = ("a basic swing's kill confirmed %.2f s after its contact"):format(after),
		kill = {
			killer = "local",
			contactTier = "Normal",
			windowIndex = 1,
			confirmAfter = after,
			scheduler = "frameClock",
		},
	})
end
table.insert(KILLS, {
	label = "an Art's final cut, proven a kill on contact",
	kill = {
		killer = "local",
		contactTier = "Kill",
		artId = "SharpNail",
		windowIndex = 3,
		confirmAfter = 0.1,
		scheduler = "frameClock",
	},
})
table.insert(KILLS, {
	label = "an Art's final cut, the Kill upgraded by the server",
	kill = {
		killer = "local",
		contactTier = "Final",
		artId = "SharpNail",
		windowIndex = 3,
		confirmAfter = 0.1,
		scheduler = "frameClock",
	},
})
table.insert(KILLS, {
	label = "a remote player's kill",
	kill = { killer = "remote", windowIndex = 1, confirmAfter = 0, scheduler = "frameClock" },
})

describe("a dead rig's plate and its body leave on the same frame", function()
	for _, case in KILLS do
		for _, scheduler in { "frameClock", "precise", "late" } do
			it(("%s (task.delay %s)"):format(case.label, scheduler), function()
				local kill = table.clone(case.kill)
				kill.scheduler = scheduler :: Scheduler
				for _, jitter in { 0, 0.002 } do
					kill.jitter = jitter
					local outcome = runKill(kill)
					expect(outcome.body).never.toBeNil()
					expect(outcome.plate).toBe(outcome.body)
				end
			end)
		end
	end

	it("holds when EntityDied is handled before the Dead attribute", function()
		for _, scheduler in { "frameClock", "precise", "late" } do
			local outcome = runKill({
				killer = "local",
				contactTier = "Normal",
				windowIndex = 1,
				confirmAfter = 0.1,
				diedFirst = true,
				scheduler = scheduler :: Scheduler,
			})
			expect(outcome.body).never.toBeNil()
			expect(outcome.plate).toBe(outcome.body)
		end
	end)
end)

describe("a render stall across the shatter's time (D-191)", function()
	-- One frame stalls from up to `back` frames before the shatter is due to well past its grace:
	-- the Heartbeat that ends the stall finds the plate's fallback over while the delayed shatter
	-- still waits for the next frame's start, so the fallback must give it that frame.
	local confirmFrame = 10 + math.ceil(0.1 / FRAME - 1e-9)
	local dueFrame = confirmFrame + math.floor(DEATH_SECONDS / FRAME)
	for _, stall in { 0.35, 0.5, 1, 2 } do
		it(("keeps the plate with the body through a %.2f s stall"):format(stall), function()
			for _, scheduler in { "frameClock", "precise", "late" } do
				for _, back in { 0, 1, 3, 8 } do
					for _, killer in { "local", "remote" } do
						local outcome = runKill({
							killer = killer :: any,
							contactTier = if killer == "local" then "Normal" else nil,
							windowIndex = 1,
							confirmAfter = 0.1,
							scheduler = scheduler :: Scheduler,
							stallFrame = dueFrame - back,
							stall = stall,
						})
						expect(outcome.body).never.toBeNil()
						expect(outcome.plate).toBe(outcome.body)
					end
				end
			end
		end)
	end

	it("still drops a plate whose coming shatter never runs, a frame after the stall", function()
		local outcome = runKill({
			killer = "remote",
			windowIndex = 1,
			confirmAfter = 0,
			dropShatter = true,
			scheduler = "frameClock",
			stallFrame = 10 + math.floor(DEATH_SECONDS / FRAME),
			stall = 1,
		})
		expect(outcome.body).toBeNil()
		expect(outcome.plate).toBe(10 + math.floor(DEATH_SECONDS / FRAME) + 1)
	end)
end)

describe("the plate's fallback", function()
	it("drops the plate of a rig that never shatters here on the death's schedule", function()
		local outcome = runKill({
			killer = "remote",
			windowIndex = 1,
			confirmAfter = 0,
			noDeath = true,
			scheduler = "frameClock",
		})
		expect(outcome.body).toBeNil()
		local frames = (outcome.plate :: number) - (outcome.confirmFrame :: number)
		expect(math.abs(frames * FRAME - DEATH_SECONDS) <= FRAME + 1e-6).toBe(true)
	end)

	it("still drops a plate whose coming shatter never runs, once the grace is over", function()
		local outcome = runKill({
			killer = "remote",
			windowIndex = 1,
			confirmAfter = 0,
			dropShatter = true,
			scheduler = "frameClock",
		})
		expect(outcome.body).toBeNil()
		local frames = (outcome.plate :: number) - (outcome.confirmFrame :: number)
		local due = DEATH_SECONDS + UI.nameplates.shatterGraceSeconds
		expect(math.abs(frames * FRAME - due) <= FRAME + 1e-6).toBe(true)
	end)

	it("lets a revive take back a scheduled shatter's hold", function()
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = model
		model.PrimaryPart = root
		local record = {
			id = 7001,
			kind = "Enemy",
			model = model,
			name = "Revived",
			hp = 0,
			maxHp = 100,
			gauge = 0,
			maxGauge = 100,
			state = "Dead",
		}
		Nameplates.attach(record)
		local plate = Nameplates.plateOf(record.id) :: any
		Nameplates.expect(model, DEATH_SECONDS)
		expect(plate.expected).never.toBeNil()
		record.state = "Idle"
		record.hp = 100
		Nameplates.refresh(record)
		expect(plate.expected).toBeNil()
		clock += DEATH_SECONDS + UI.nameplates.shatterGraceSeconds + FRAME
		Nameplates.update()
		expect(plate.gui.Enabled).toBe(true)
		Nameplates.detach(record)
	end)

	it("waits at least a frame at the lowest rate past the shatter's time (ui.luau)", function()
		local grace = UI.nameplates.shatterGraceSeconds
		expect(typeof(grace)).toBe("number")
		-- A coming shatter is at most a frame behind the plate's clock; 10 fps is the floor.
		expect(grace >= 0.1).toBe(true)
		-- And short enough that a lost shatter's plate never outlives the shatter's own length.
		expect(grace <= Combat.deathFreeze).toBe(true)
	end)
end)
