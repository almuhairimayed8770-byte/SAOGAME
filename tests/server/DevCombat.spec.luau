--!strict
--[[
	The Studio combat trace hook (src/server/dev/DevCombat.server.luau, D-114, D-120, D-121), loaded
	the way Studio runs it: a fresh copy of the Script with a fake CombatService (its traceSink field
	and beginBasic / beginArt), a fake EntityService (setHp and heal as the real one clamps them), a
	fake EnemyService (the hold), a fake AntiCheatService (serverMoved, D-143), a fake RunService
	and Workspace for the gate, and a fake clock behind task.wait and os.clock. The fake
	CombatService calls the sink from its clock the way CombatService.tick does from Heartbeat. The
	player's character model records each PivotTo, in one ordered list with serverMoved.
	The Studio test hooks (D-333): the fake EnemyService records place, walk and charge and plays a
	rush's phases and log on the fake clock; Workspace is a real (Lune) Folder, so "part" makes real
	Parts in a real folder. tests/server/DevEnemyHooks.spec.luau runs the same commands over the
	real EnemyService.
]]

local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Dev = Harness.load("src/shared/data/dev")
local Playground = Harness.load("src/shared/data/playground")
local Enemies = Harness.load("src/shared/data/enemies")

local NODE = "src/server/dev/DevCombat"
local FILE = "src/server/dev/DevCombat.server.luau"
local FRAME = 1 / 60
local TRACE = Dev.trace

type Clock = {
	now: number,
	queue: { { at: number, fn: () -> () } },
	after: (seconds: number, fn: () -> ()) -> (),
	advance: (seconds: number) -> (),
}

local function newClock(): Clock
	local clock: Clock = nil :: any
	clock = {
		now = 0,
		queue = {},
		after = function(seconds: number, fn: () -> ())
			table.insert(clock.queue, { at = clock.now + seconds, fn = fn })
		end,
		advance = function(seconds: number)
			local target = clock.now + seconds
			while true do
				local best, index = nil, nil
				for i, item in clock.queue do
					if item.at <= target + 1e-9 and (best == nil or item.at < best.at) then
						best, index = item, i
					end
				end
				if best == nil or index == nil then
					break
				end
				table.remove(clock.queue, index)
				clock.now = math.max(clock.now, best.at)
				best.fn()
			end
			clock.now = target
		end,
	}
	return clock
end

local function traceEvent(entityId: number, windowIndex: number, windowCount: number, hits: number): any
	return {
		entityId = entityId,
		clipId = "player/OneHandedSword/Basic1",
		artId = nil,
		windowIndex = windowIndex,
		windowCount = windowCount,
		hits = hits,
		facing = Vector3.new(0, 0, -1),
		rootLook = Vector3.new(0, 0, -1),
		nearest = { entityId = 11, name = "Frenzy Boar", distance = 5, bearingDegrees = 2, clearance = -0.4 },
	}
end

type World = {
	clock: Clock,
	created: { any },
	required: { [string]: boolean },
	printed: { string },
	combat: any,
	calls: { any },
	enemies: { any },
	held: { [number]: boolean },
	holdNew: { on: boolean },
	playerRecord: any,
	sss: any,
	invoke: (command: any, args: any) -> any,
	plan: { windows: number, hits: number, reject: string? },
	-- "place": the player's PivotTo and AntiCheatService.serverMoved calls, in the order made.
	moves: { { kind: string, player: any?, seconds: number?, cframe: CFrame? } },
	anticheat: { watched: boolean },
	player: any,
	-- The Studio test hooks (D-333): EnemyService.place / walk / charge calls in order, the walk's
	-- and the charge's plans on the fake clock, and the real Workspace folder.
	hookCalls: { { kind: string, id: number, cframe: CFrame?, held: boolean?, goal: Vector3?, options: any } },
	walkPlan: { seconds: number, reject: string?, arriveAt: Vector3? },
	chargePlan: {
		windUp: number,
		run: number,
		reject: string?,
		stops: { { reason: string, after: number, distance: number } },
	},
	workspace: any,
}

type Options = { studio: boolean?, capture: any }

local function load(options: Options): World
	local clock = newClock()
	local world: World = nil :: any
	local player = { Name = "Player1", UserId = 1 }
	local playerRecord = {
		id = 1,
		kind = "Player",
		name = "Player1",
		hp = 100,
		maxHp = 100,
		state = "Idle",
		player = player,
		artSlots = nil,
		model = {
			PrimaryPart = { Position = Vector3.new(0, 3, 0), CFrame = CFrame.new(0, 3, 0) },
			Parent = { Name = "Workspace" },
			PivotTo = function(self: any, cframe: CFrame)
				table.insert(world.moves, { kind = "pivot", cframe = cframe })
				self.PrimaryPart.CFrame = cframe
				self.PrimaryPart.Position = cframe.Position
			end,
		},
	}
	local enemies = {
		{
			id = 11,
			kind = "Enemy",
			name = "Frenzy Boar",
			hp = 120,
			maxHp = 120,
			state = "Idle",
			model = { PrimaryPart = { Position = Vector3.new(0, 3, -5), CFrame = CFrame.new(0, 3, -5) } },
		},
	}
	local calls: { any } = {}
	-- The swing the fake CombatService runs: `windows` windows 0.1 s apart from 0.24 s, the hits in
	-- the first, the boar's HP down by 4 per hit; or a refusal.
	local combat: any = { traceSink = nil }
	local function run(entityId: number)
		local plan = world.plan
		for window = 1, plan.windows do
			clock.after(0.14 + 0.1 * window, function()
				local hits = if window == 1 then plan.hits else 0
				enemies[1].hp -= 4 * hits
				local sink = combat.traceSink
				if sink ~= nil then
					sink(traceEvent(entityId, window, plan.windows, hits))
				end
			end)
		end
	end
	combat.beginBasic = function(entityId: number, facing: Vector3?): (boolean, string?)
		table.insert(calls, { kind = "basic", entityId = entityId, facing = facing })
		if world.plan.reject ~= nil then
			return false, world.plan.reject
		end
		run(entityId)
		return true, nil
	end
	combat.beginArt = function(entityId: number, artId: string, facing: Vector3?): (boolean, string?)
		table.insert(calls, { kind = "art", entityId = entityId, artId = artId, facing = facing })
		if world.plan.reject ~= nil then
			return false, world.plan.reject
		end
		run(entityId)
		return true, nil
	end
	local function recordOf(id: number): any
		if id == playerRecord.id then
			return playerRecord
		end
		for _, record in enemies do
			if record.id == id then
				return record
			end
		end
		return nil
	end
	local entities = {
		fromPlayer = function(who: any): any
			return if who == player then playerRecord else nil
		end,
		get = recordOf,
		enemies = function(): { any }
			return enemies
		end,
		-- EntityService.setHp's rules: [1, maxHp], nil for an unknown or dead id or a NaN.
		setHp = function(id: number, hp: number): number?
			local record = recordOf(id)
			if record == nil or record.state == "Dead" or hp ~= hp then
				return nil
			end
			record.hp = math.clamp(hp, 1, record.maxHp)
			return record.hp
		end,
		heal = function(id: number, amount: number)
			local record = recordOf(id)
			if record ~= nil and record.state ~= "Dead" and amount > 0 then
				record.hp = math.min(record.maxHp, record.hp + amount)
			end
		end,
	}
	-- EnemyService's hold over the enemies list (a dead one is no living enemy).
	local held: { [number]: boolean } = {}
	local holdNew = { on = false }
	local function living(id: number): boolean
		local record = recordOf(id)
		return record ~= nil and record.kind == "Enemy" and record.state ~= "Dead"
	end
	-- The hooks (D-333): a walk is over after walkPlan.seconds (the body then stands at arriveAt);
	-- a charge crouches for chargePlan.windUp, runs chargePlan.run, then recovers, and its log takes
	-- the launch and chargePlan.stops on the clock.
	local walkEnds: { [number]: number } = {}
	local phases: { [number]: { windUpEnds: number, strikeEnds: number } } = {}
	local rushLogs: { [number]: any } = {}
	local function root(id: number): any
		return (recordOf(id) :: any).model.PrimaryPart
	end
	local function moveRoot(id: number, cframe: CFrame)
		local primary = root(id)
		primary.CFrame = cframe
		primary.Position = cframe.Position
	end
	local enemyService = {
		modelOf = function(id: number): any
			return if living(id) then (recordOf(id) :: any).model else nil
		end,
		defOf = function(id: number): any
			return if living(id) then Enemies.byId("FrenzyBoar") else nil
		end,
		brainOf = function(id: number): any
			if not living(id) then
				return nil
			end
			return {
				getPhase = function(_self: any): string
					local plan = phases[id]
					if plan == nil then
						return "Idle"
					elseif clock.now < plan.windUpEnds then
						return "WindUp"
					elseif clock.now < plan.strikeEnds then
						return "Strike"
					end
					return "Recover"
				end,
			}
		end,
		place = function(id: number, cframe: CFrame, isHeld: boolean?): boolean
			table.insert(world.hookCalls, { kind = "place", id = id, cframe = cframe, held = isHeld })
			if not living(id) then
				return false
			end
			moveRoot(id, cframe)
			held[id] = if isHeld == true then true else nil
			return true
		end,
		walk = function(id: number, goal: Vector3, options: any): (boolean, string?)
			table.insert(world.hookCalls, { kind = "walk", id = id, goal = goal, options = options })
			if not living(id) then
				return false, "no living enemy"
			end
			if world.walkPlan.reject ~= nil then
				return false, world.walkPlan.reject
			end
			walkEnds[id] = clock.now + world.walkPlan.seconds
			clock.after(world.walkPlan.seconds, function()
				walkEnds[id] = nil
				local at = world.walkPlan.arriveAt or goal
				moveRoot(id, CFrame.new(at.X, root(id).Position.Y, at.Z))
				held[id] = if options.hold == true then true else nil
			end)
			return true, nil
		end,
		walking = function(id: number): boolean
			return walkEnds[id] ~= nil
		end,
		charge = function(id: number, toward: Vector3): (boolean, string?)
			table.insert(world.hookCalls, { kind = "charge", id = id, goal = toward })
			if not living(id) then
				return false, "no living enemy"
			end
			local plan = world.chargePlan
			if plan.reject ~= nil then
				return false, plan.reject
			end
			held[id] = nil
			local launchAt = clock.now + plan.windUp
			phases[id] = { windUpEnds = launchAt, strikeEnds = launchAt + plan.run }
			local from = root(id).Position
			local direction = Vector3.new(toward.X - from.X, 0, toward.Z - from.Z).Unit
			local log = { attackId = "Charge", launched = nil, stops = {} }
			rushLogs[id] = log
			clock.after(plan.windUp, function()
				log.launched = { at = clock.now, origin = from, direction = direction }
			end)
			for _, stop in plan.stops do
				clock.after(plan.windUp + stop.after, function()
					table.insert(log.stops, { reason = stop.reason, distance = stop.distance, at = clock.now })
				end)
			end
			return true, nil
		end,
		devRushOf = function(id: number): any
			return rushLogs[id]
		end,
		ids = function(): { number }
			local ids = {}
			for _, record in enemies do
				if record.state ~= "Dead" then
					table.insert(ids, record.id)
				end
			end
			table.sort(ids)
			return ids
		end,
		setHeld = function(id: number, on: boolean): boolean
			if not living(id) then
				return false
			end
			held[id] = if on then true else nil
			return true
		end,
		isHeld = function(id: number): boolean
			return held[id] == true and living(id)
		end,
		heldIds = function(): { number }
			local ids = {}
			for id in held do
				if living(id) then
					table.insert(ids, id)
				end
			end
			table.sort(ids)
			return ids
		end,
		setHoldNew = function(on: boolean)
			holdNew.on = on
		end,
		holdsNew = function(): boolean
			return holdNew.on
		end,
	}
	local sss = { Name = "ServerScriptService" }
	local services: { [string]: any } = {
		Players = {
			GetPlayers = function(): { any }
				return { player }
			end,
		},
		RunService = {
			IsStudio = function(): boolean
				return options.studio == true
			end,
		},
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
		ServerScriptService = sss,
	}
	local antiCheat = {
		serverMoved = function(who: any, seconds: number): boolean
			table.insert(world.moves, { kind = "serverMoved", player = who, seconds = seconds })
			return world.anticheat.watched
		end,
	}
	local fakes: { [string]: any } = {
		CombatService = combat,
		EntityService = entities,
		EnemyService = enemyService,
		AntiCheatService = antiCheat,
	}
	local created: { any } = {}
	local required: { [string]: boolean } = {}
	local printed: { string } = {}
	-- A real Workspace (a Lune Folder) carrying the DevCapture attribute as given.
	local workspace = roblox.Instance.new("Folder")
	workspace.Name = "Workspace"
	workspace:SetAttribute(Dev.attributes.capture, options.capture)

	local env = Harness.environment()
	env.script = Harness.node(NODE)
	env.require = function(node: any): any
		required[node.Name] = true
		return fakes[node.Name] or Harness.loadModule(node)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name] or error("no service " .. name)
		end,
	}
	env.workspace = workspace
	-- The BindableFunction is a plain table the spec invokes; anything else (the hooks' folder and
	-- parts) is a real Lune instance. Every one is recorded.
	env.Instance = {
		new = function(className: string): any
			local instance: any = if className == "BindableFunction"
				then { ClassName = className }
				else roblox.Instance.new(className :: any)
			table.insert(created, instance)
			return instance
		end,
	}
	env.print = function(...: any)
		local parts = {}
		for _, value in { ... } do
			table.insert(parts, tostring(value))
		end
		table.insert(printed, table.concat(parts, " "))
	end
	env.task = {
		wait = function(seconds: number?): number
			local dt = if seconds ~= nil and seconds > 0 then seconds else FRAME
			local left = dt
			while left > 1e-9 do
				local step = math.min(FRAME, left)
				clock.advance(step)
				left -= step
			end
			return dt
		end,
		delay = function(seconds: number, fn: () -> ())
			clock.after(seconds, fn)
		end,
	}
	env.os = {
		clock = function(): number
			return clock.now
		end,
	}

	world = {
		clock = clock,
		created = created,
		required = required,
		printed = printed,
		combat = combat,
		calls = calls,
		enemies = enemies,
		held = held,
		holdNew = holdNew,
		playerRecord = playerRecord,
		sss = sss,
		invoke = function(command: any, args: any): any
			return created[1].OnInvoke(command, args)
		end,
		plan = { windows = 1, hits = 1, reject = nil },
		moves = {},
		anticheat = { watched = true },
		player = player,
		hookCalls = {},
		walkPlan = { seconds = 2, reject = nil, arriveAt = nil },
		chargePlan = { windUp = 0.6, run = 0.7, reject = nil, stops = {} },
		workspace = workspace,
	}
	luau.load(Harness.readFile(FILE), { debugName = FILE, environment = env :: any })()
	return world
end

describe("DevCombat gate", function()
	it("does nothing outside Studio, even with DevCapture", function()
		local world = load({ studio = false, capture = true })
		expect(#world.created).toBe(0)
		expect(world.required.CombatService).toBeNil()
		expect(world.combat.traceSink).toBeNil()
	end)

	it("does nothing in Studio without DevCapture, or with it not exactly true", function()
		for _, capture in { nil, false, "true", 1 } do
			local world = load({ studio = true, capture = capture })
			expect(#world.created).toBe(0)
			expect(world.required.CombatService).toBeNil()
		end
	end)

	it("in Studio with DevCapture puts one BindableFunction under ServerScriptService and sets no sink", function()
		local world = load({ studio = true, capture = true })
		expect(#world.created).toBe(1)
		local bindable = world.created[1]
		expect(bindable.ClassName).toBe("BindableFunction")
		expect(bindable.Name).toBe(TRACE.bindableName)
		expect(bindable.Parent).toBe(world.sss)
		expect(typeof(bindable.OnInvoke)).toBe("function")
		-- Nil by default: the sweep measures nothing for the trace until someone asks.
		expect(world.combat.traceSink).toBeNil()
	end)
end)

describe("DevCombat trace", function()
	it("trace on sets the sink, prints one line per window and keeps the events; off clears it", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("trace", { on = true })
		expect(reply.ok).toBe(true)
		expect(reply.on).toBe(true)
		expect(typeof(world.combat.traceSink)).toBe("function")
		world.combat.traceSink(traceEvent(1, 1, 1, 0))
		expect(#world.printed).toBe(1)
		expect(world.printed[1]:sub(1, #TRACE.printPrefix)).toBe(TRACE.printPrefix)
		expect(world.printed[1]:find("hits=0", 1, true)).never.toBeNil()
		local events = world.invoke("events", nil)
		expect(events.ok).toBe(true)
		expect(#events.events).toBe(1)
		expect(events.events[1].entityId).toBe(1)
		expect(events.events[1].nearest.name).toBe("Frenzy Boar")
		world.invoke("trace", { on = false })
		expect(world.combat.traceSink).toBeNil()
	end)

	it("trace with no args turns the trace on", function()
		local world = load({ studio = true, capture = true })
		expect(world.invoke("trace", nil).on).toBe(true)
		expect(typeof(world.combat.traceSink)).toBe("function")
	end)

	it("keeps only the last keepEvents and can clear them", function()
		local world = load({ studio = true, capture = true })
		world.invoke("trace", { on = true })
		for _ = 1, TRACE.keepEvents + 5 do
			world.combat.traceSink(traceEvent(1, 1, 1, 0))
		end
		expect(#world.invoke("events", nil).events).toBe(TRACE.keepEvents)
		expect(#world.invoke("events", { count = 3 }).events).toBe(3)
		world.invoke("events", { clear = true })
		expect(#world.invoke("events", nil).events).toBe(0)
	end)

	it("chains a sink someone else set, and gives it back when the trace goes off", function()
		local world = load({ studio = true, capture = true })
		local seen = 0
		local other = function(_event: any)
			seen += 1
		end
		world.combat.traceSink = other
		world.invoke("trace", { on = true })
		world.combat.traceSink(traceEvent(1, 1, 1, 0))
		expect(seen).toBe(1)
		world.invoke("trace", { on = false })
		expect(world.combat.traceSink).toBe(other)
	end)

	it("never lets a bad event out of the sink into the combat tick", function()
		local world = load({ studio = true, capture = true })
		world.invoke("trace", { on = true })
		local bad = traceEvent(1, 1, 1, 0)
		bad.facing = nil
		local ok = pcall(world.combat.traceSink, bad)
		expect(ok).toBe(true)
	end)
end)

describe("DevCombat swings", function()
	it("basic swings the first player's entity through the live service and returns its windows", function()
		local world = load({ studio = true, capture = true })
		local before = world.clock.now
		local reply = world.invoke("basic", nil)
		-- Back as soon as the last window is in (0.24 s here), not at the timeout.
		expect(world.clock.now - before).toBeLessThan(0.24 + 2 * FRAME)
		expect(reply.ok).toBe(true)
		expect(world.calls[1].kind).toBe("basic")
		expect(world.calls[1].entityId).toBe(1)
		expect(world.calls[1].facing).toBeNil()
		expect(reply.entityId).toBe(1)
		expect(reply.complete).toBe(true)
		expect(#reply.events).toBe(1)
		expect(reply.hits).toBe(1)
		expect(reply.hp[1].id).toBe(11)
		expect(reply.hp[1].before).toBe(120)
		expect(reply.hp[1].after).toBe(116)
		-- The trace was off: the sink goes back to nil once the swing is in.
		expect(world.combat.traceSink).toBeNil()
		expect(#world.printed).toBe(0)
	end)

	it("basic passes an entity and a facing, and reports a refusal with its reason", function()
		local world = load({ studio = true, capture = true })
		world.plan.reject = "Facing"
		local reply = world.invoke("basic", { entityId = 1, facing = { 0, 0, 1 } })
		expect(reply.ok).toBe(false)
		expect(reply.reason).toBe("Facing")
		expect(world.calls[1].facing).toEqual(Vector3.new(0, 0, 1))
		expect(world.combat.traceSink).toBeNil()
		expect(world.invoke("basic", { facing = "north" }).ok).toBe(false)
		expect(world.invoke("basic", { entityId = "me" }).ok).toBe(false)
	end)

	it("art defaults to the first loadout slot and waits for the run's last window", function()
		local world = load({ studio = true, capture = true })
		world.plan.windows = 3
		local reply = world.invoke("art", nil)
		expect(reply.ok).toBe(true)
		expect(world.calls[1].kind).toBe("art")
		expect(world.calls[1].artId).toBe(Playground.loadout.artSlots[1])
		expect(#reply.events).toBe(3)
		expect(reply.complete).toBe(true)
		local named = world.invoke("art", { artId = "OneHandedSword.SharpNail" })
		expect(world.calls[2].artId).toBe("OneHandedSword.SharpNail")
		expect(named.ok).toBe(true)
	end)

	it("gives up after trace.runTimeoutSeconds when the windows never close", function()
		local world = load({ studio = true, capture = true })
		world.plan.windows = 0
		local before = world.clock.now
		local reply = world.invoke("basic", nil)
		expect(reply.ok).toBe(true)
		expect(reply.complete).toBe(false)
		expect(world.clock.now - before).toBeGreaterThanOrEqual(TRACE.runTimeoutSeconds - 1e-6)
	end)

	it("keeps the run's events in the buffer and prints them when the trace is on", function()
		local world = load({ studio = true, capture = true })
		world.invoke("trace", { on = true })
		world.invoke("basic", nil)
		expect(#world.printed).toBe(1)
		expect(#world.invoke("events", nil).events).toBe(1)
		expect(typeof(world.combat.traceSink)).toBe("function")
	end)

	it("hp lists the enemies with HP, state and distance from the first player", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("hp", nil)
		expect(reply.ok).toBe(true)
		expect(#reply.enemies).toBe(1)
		local boar = reply.enemies[1]
		expect(boar.id).toBe(11)
		expect(boar.name).toBe("Frenzy Boar")
		expect(boar.hp).toBe(120)
		expect(boar.maxHp).toBe(120)
		expect(boar.state).toBe("Idle")
		expect(boar.held).toBe(false)
		expect(boar.distance).toBe(5)
		world.invoke("hold", { ids = { 11 } })
		expect(world.invoke("hp", nil).enemies[1].held).toBe(true)
	end)

	it("answers an unknown command with the command list", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("explode", nil)
		expect(reply.ok).toBe(false)
		expect(table.find(reply.commands, "trace")).never.toBeNil()
	end)
end)

-- A second and a third enemy beside the boar (the kobold and a second boar of the Play-test).
local function addEnemies(world: World)
	table.insert(world.enemies, {
		id = 12,
		kind = "Enemy",
		name = "Kobold Axeman",
		hp = 190,
		maxHp = 190,
		state = "Idle",
		model = { PrimaryPart = { Position = Vector3.new(6, 3, -5), CFrame = CFrame.new(6, 3, -5) } },
	})
	table.insert(world.enemies, {
		id = 13,
		kind = "Enemy",
		name = "Frenzy Boar",
		hp = 120,
		maxHp = 120,
		state = "Idle",
		model = { PrimaryPart = { Position = Vector3.new(-6, 3, -5), CFrame = CFrame.new(-6, 3, -5) } },
	})
end

describe("DevCombat hold (D-120)", function()
	it("with no list holds every enemy and replies the held ids; on = false releases them", function()
		local world = load({ studio = true, capture = true })
		addEnemies(world)
		local reply = world.invoke("hold", nil)
		expect(reply.ok).toBe(true)
		expect(reply.on).toBe(true)
		expect(reply.held).toEqual({ 11, 12, 13 })
		expect(reply.changed).toEqual({ 11, 12, 13 })
		expect(reply.holdNew).toBe(false)
		local released = world.invoke("hold", { on = false })
		expect(released.ok).toBe(true)
		expect(released.on).toBe(false)
		expect(released.held).toEqual({})
		expect(released.changed).toEqual({ 11, 12, 13 })
	end)

	it("ids holds only those; except holds every other enemy", function()
		local world = load({ studio = true, capture = true })
		addEnemies(world)
		expect(world.invoke("hold", { ids = { 13 } }).held).toEqual({ 13 })
		expect(world.invoke("hold", { ids = 12 }).held).toEqual({ 12, 13 }) -- one id needs no list
		world.invoke("hold", { on = false })
		local reply = world.invoke("hold", { except = { 12 } })
		expect(reply.held).toEqual({ 11, 13 })
		expect(world.held[12]).toBeNil()
		-- Releasing all but the kobold leaves the kobold as it was.
		world.invoke("hold", { ids = { 12 } })
		expect(world.invoke("hold", { except = { 12 }, on = false }).held).toEqual({ 12 })
	end)

	it("all = true also holds every enemy spawned later; on = false with all stops that", function()
		local world = load({ studio = true, capture = true })
		addEnemies(world)
		local reply = world.invoke("hold", { except = { 11 }, all = true })
		expect(reply.held).toEqual({ 12, 13 })
		expect(reply.holdNew).toBe(true)
		expect(world.holdNew.on).toBe(true)
		-- Without all, hold-new stays as it is.
		expect(world.invoke("hold", { ids = { 11 }, on = false }).holdNew).toBe(true)
		local off = world.invoke("hold", { on = false, all = true })
		expect(off.held).toEqual({})
		expect(off.holdNew).toBe(false)
	end)

	it("reports ids that are no living enemy as missing and refuses bad lists", function()
		local world = load({ studio = true, capture = true })
		addEnemies(world)
		world.enemies[3].state = "Dead"
		local reply = world.invoke("hold", { ids = { 11, 13, 99, 1 } })
		expect(reply.ok).toBe(true)
		expect(reply.held).toEqual({ 11 })
		expect(reply.missing).toEqual({ 1, 13, 99 })
		expect(world.invoke("hold", { ids = { 11 }, except = { 12 } }).ok).toBe(false)
		expect(world.invoke("hold", { ids = { "boar" } }).ok).toBe(false)
		expect(world.invoke("hold", { except = "boar" }).ok).toBe(false)
		expect(world.invoke("hold", { on = "yes" }).ok).toBe(false)
		expect(world.invoke("hold", { all = 1 }).ok).toBe(false)
	end)
end)

describe("DevCombat sethp and heal (D-121)", function()
	it("sethp sets an enemy's HP through EntityService.setHp and replies old and new", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("sethp", { entityId = 11, hp = 1 })
		expect(reply.ok).toBe(true)
		expect(reply.entityId).toBe(11)
		expect(reply.name).toBe("Frenzy Boar")
		expect(reply.before).toBe(120)
		expect(reply.after).toBe(1)
		expect(reply.maxHp).toBe(120)
		expect(world.enemies[1].hp).toBe(1)
		-- Clamped, never a kill.
		expect(world.invoke("sethp", { entityId = 11, hp = 0 }).after).toBe(1)
		expect(world.invoke("sethp", { entityId = 11, hp = 500 }).after).toBe(120)
	end)

	it("sethp works on the player and refuses a missing id, a missing hp and a dead fighter", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("sethp", { entityId = 1, hp = 30 })
		expect(reply.ok).toBe(true)
		expect(reply.before).toBe(100)
		expect(reply.after).toBe(30)
		expect(world.invoke("sethp", { hp = 30 }).ok).toBe(false)
		expect(world.invoke("sethp", { entityId = 11 }).ok).toBe(false)
		expect(world.invoke("sethp", { entityId = 11, hp = "low" }).ok).toBe(false)
		expect(world.invoke("sethp", { entityId = 99, hp = 5 }).ok).toBe(false)
		world.enemies[1].state = "Dead"
		expect(world.invoke("sethp", { entityId = 11, hp = 5 }).ok).toBe(false)
	end)

	it("heal fills the first player's HP by default, or a named entity's", function()
		local world = load({ studio = true, capture = true })
		world.playerRecord.hp = 12
		local reply = world.invoke("heal", nil)
		expect(reply.ok).toBe(true)
		expect(reply.entityId).toBe(1)
		expect(reply.before).toBe(12)
		expect(reply.after).toBe(100)
		world.enemies[1].hp = 7
		local boar = world.invoke("heal", { entityId = 11 })
		expect(boar.after).toBe(120)
		expect(world.invoke("heal", { entityId = 99 }).ok).toBe(false)
		world.enemies[1].state = "Dead"
		expect(world.invoke("heal", { entityId = 11 }).ok).toBe(false)
	end)

	it("help lists hold, sethp and heal; none of them touches the trace sink", function()
		local world = load({ studio = true, capture = true })
		local commands = world.invoke("help", nil).commands
		for _, name in { "hold", "sethp", "heal" } do
			expect(table.find(commands, name)).never.toBeNil()
		end
		world.invoke("hold", nil)
		world.invoke("sethp", { entityId = 11, hp = 1 })
		world.invoke("heal", nil)
		expect(world.combat.traceSink).toBeNil()
		expect(#world.calls).toBe(0)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- "place": the safe dev teleport (D-143)
-- ------------------------------------------------------------------------------------------

local PLACE = Dev.place

-- The yaw of a CFrame's flat look (0 looks along -Z, + = left).
local function yawOf(cframe: CFrame): number
	local look = cframe.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

describe("DevCombat place (D-143)", function()
	it("tells the anti-cheat first, then pivots the first player's character to the point and facing", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("place", { position = { 10, 4, -20 }, facing = 90 })
		expect(reply.ok).toBe(true)
		expect(reply.entityId).toBe(1)
		expect(reply.from).toEqual({ 0, 3, 0 })
		expect(reply.to).toEqual({ 10, 4, -20 })
		expect(reply.facing).toBe(90)
		expect(reply.settleSeconds).toBe(PLACE.settleSeconds)
		expect(reply.anticheat).toBe(true)
		expect(#world.moves).toBe(2)
		expect(world.moves[1].kind).toBe("serverMoved")
		expect(world.moves[1].player).toBe(world.player)
		expect(world.moves[1].seconds).toBe(PLACE.settleSeconds)
		expect(world.moves[2].kind).toBe("pivot")
		local cframe = world.moves[2].cframe :: CFrame
		expect((cframe.Position - Vector3.new(10, 4, -20)).Magnitude < 1e-4).toBe(true)
		expect(yawOf(cframe)).toBeCloseTo(90, 1e-3)
		-- It sets the fight up and nothing else: no swing, no sink.
		expect(#world.calls).toBe(0)
		expect(world.combat.traceSink).toBeNil()
	end)

	it("keeps the root's own facing when none is given, and takes a Vector3", function()
		local world = load({ studio = true, capture = true })
		world.playerRecord.model.PrimaryPart.CFrame = CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(-45), 0)
		local reply = world.invoke("place", { position = Vector3.new(1, 3, 1) })
		expect(reply.ok).toBe(true)
		expect(reply.facing).toBeCloseTo(-45, 1e-2)
		expect(yawOf(world.moves[2].cframe :: CFrame)).toBeCloseTo(-45, 1e-3)
	end)

	it("picks the player by entity id, Name or UserId", function()
		for _, args in
			{
				{ entityId = 1, position = { 0, 3, 5 } },
				{ player = "Player1", position = { 0, 3, 5 } },
				{ player = 1, position = { 0, 3, 5 } },
			}
		do
			local world = load({ studio = true, capture = true })
			local reply = world.invoke("place", args)
			expect(reply.ok).toBe(true)
			expect(reply.entityId).toBe(1)
			expect(#world.moves).toBe(2)
		end
	end)

	it("says when the anti-cheat does not watch the player (it still moves them)", function()
		local world = load({ studio = true, capture = true })
		world.anticheat.watched = false
		local reply = world.invoke("place", { position = { 0, 3, 5 } })
		expect(reply.ok).toBe(true)
		expect(reply.anticheat).toBe(false)
		expect(world.moves[2].kind).toBe("pivot")
	end)

	it("refuses bad arguments and moves nobody: position, facing, who, and a dead or rootless player", function()
		local far = PLACE.maxCoordinate + 1
		local bad: { { [string]: any } } = {
			{},
			{ position = "0, 3, 0" },
			{ position = { 0, 3 } },
			{ position = { 0, "3", 0 } },
			{ position = { 0, 0 / 0, 0 } },
			{ position = { math.huge, 3, 0 } },
			{ position = { far, 3, 0 } },
			{ position = Vector3.new(0, -far, 0) },
			{ position = { 0, 3, 0 }, facing = "north" },
			{ position = { 0, 3, 0 }, facing = 0 / 0 },
			{ position = { 0, 3, 0 }, entityId = 11 },
			{ position = { 0, 3, 0 }, entityId = 99 },
			{ position = { 0, 3, 0 }, entityId = "1" },
			{ position = { 0, 3, 0 }, player = "Nobody" },
			{ position = { 0, 3, 0 }, player = { 1 } },
			{ position = { 0, 3, 0 }, player = "Player1", entityId = 1 },
		}
		for _, args in bad do
			local world = load({ studio = true, capture = true })
			local reply = world.invoke("place", args)
			expect(reply.ok).toBe(false)
			expect(typeof(reply.error)).toBe("string")
			expect(#world.moves).toBe(0)
		end
		local world = load({ studio = true, capture = true })
		expect(world.invoke("place", nil).ok).toBe(false)
		world.playerRecord.state = "Dead"
		expect(world.invoke("place", { position = { 0, 3, 0 } }).ok).toBe(false)
		world.playerRecord.state = "Idle"
		world.playerRecord.model.Parent = nil
		expect(world.invoke("place", { position = { 0, 3, 0 } }).ok).toBe(false)
		expect(#world.moves).toBe(0)
	end)

	it("exists only where DevCombat does, and only behind the server BindableFunction", function()
		for _, options in { { studio = false, capture = true }, { studio = true, capture = nil } } do
			local world = load(options)
			expect(#world.created).toBe(0)
			expect(world.required.AntiCheatService).toBeNil()
		end
		local world = load({ studio = true, capture = true })
		expect(#world.created).toBe(1)
		expect(world.created[1].ClassName).toBe("BindableFunction")
		expect(world.created[1].Parent).toBe(world.sss)
		-- No remote and no Net handler leads to it: the hook makes none and names none.
		local source = Harness.readFile(FILE)
		for _, word in { "RemoteEvent", "RemoteFunction", "OnServerEvent", "OnServerInvoke", "Net." } do
			expect(source:find(word, 1, true)).toBeNil()
		end
	end)

	it("help lists place with its arguments", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("help", nil)
		expect(table.find(reply.commands, "place")).never.toBeNil()
		for _, name in reply.commands do
			expect(typeof(reply.usage[name])).toBe("string")
		end
		expect(reply.usage.place:find("position", 1, true)).never.toBeNil()
		expect(reply.usage.place:find("facing", 1, true)).never.toBeNil()
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The Studio test hooks (D-333): "enemy", "walk", "charge", "part", "clearparts"
-- ------------------------------------------------------------------------------------------

local HOOKS = Dev.hooks
local Rigs = Harness.load("src/shared/data/rigs")
local WorldData = Harness.load("src/shared/data/world")
local Palette = Harness.load("src/shared/data/palette")

-- The boar's root height over the floor it stands on (as PlaygroundService spawns it).
local BOAR_HEIGHT = (function(): number
	local rig = Rigs.Boar
	return rig.hipHeight + rig.parts[rig.rootPart].size[2] / 2 + WorldData.spawn.groundEpsilon
end)()

local function close(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < 1e-3
end

local function partsIn(world: World): { any }
	local folder = world.workspace:FindFirstChild(HOOKS.folderName)
	return if folder ~= nil then folder:GetChildren() else {}
end

describe("DevCombat Studio test hooks (D-333)", function()
	it("enemy stands a living enemy on the floor point at its rig's root height, facing, held if asked", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("enemy", { entityId = 11, position = { 10, 0, -20 }, facing = 90, hold = true })
		expect(reply.ok).toBe(true)
		expect(reply.entityId).toBe(11)
		expect(reply.name).toBe("Frenzy Boar")
		expect(reply.from).toEqual({ 0, 3, -5 })
		expect(reply.to[1]).toBe(10)
		expect(reply.to[2]).toBeCloseTo(BOAR_HEIGHT, 0.006)
		expect(reply.to[3]).toBe(-20)
		expect(reply.facing).toBe(90)
		expect(reply.held).toBe(true)
		expect(#world.hookCalls).toBe(1)
		local call = world.hookCalls[1]
		expect(call.kind).toBe("place")
		expect(call.id).toBe(11)
		expect(call.held).toBe(true)
		local cframe = call.cframe :: CFrame
		expect(close(cframe.Position, Vector3.new(10, BOAR_HEIGHT, -20))).toBe(true)
		expect(yawOf(cframe)).toBeCloseTo(90, 1e-3)
		-- A server-owned body: no player moved and the anti-cheat never asked.
		expect(#world.moves).toBe(0)
		expect(world.required.AntiCheatService).toBe(true) -- "place" (players) still needs it

		-- No facing keeps the body's own; no hold lets it go.
		local again = load({ studio = true, capture = true })
		again.enemies[1].model.PrimaryPart.CFrame = CFrame.new(0, 3, -5) * CFrame.Angles(0, math.rad(-30), 0)
		local free = again.invoke("enemy", { entityId = 11, position = Vector3.new(4, 1, 4) })
		expect(free.ok).toBe(true)
		expect(free.facing).toBeCloseTo(-30, 0.01)
		expect(free.held).toBe(false)
		expect(again.hookCalls[1].held).toBe(false)
		expect(close((again.hookCalls[1].cframe :: CFrame).Position, Vector3.new(4, 1 + BOAR_HEIGHT, 4))).toBe(true)
	end)

	it("walk hands EnemyService the point and the hooks' numbers and replies at once", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("walk", { entityId = 11, toward = { 0, 0, -25 } })
		expect(reply.ok).toBe(true)
		expect(reply.from).toEqual({ 0, 3, -5 })
		expect(reply.to).toEqual({ 0, 0, -25 })
		expect(reply.distance).toBe(20)
		expect(reply.seconds).toBeCloseTo(20 / 14, 0.006) -- the boar's own pace
		expect(reply.hold).toBe(false)
		expect(reply.over).toBeNil()
		expect(world.clock.now).toBe(0)
		local call = world.hookCalls[1]
		expect(call.kind).toBe("walk")
		expect(close(call.goal :: Vector3, Vector3.new(0, 0, -25))).toBe(true)
		expect(call.options).toEqual({
			arriveStuds = HOOKS.arriveStuds,
			seconds = HOOKS.walkTimeoutSeconds,
			hold = false,
		})
	end)

	it("walk with wait replies once the walk is over: where it stands, whether it arrived, held if asked", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("walk", { entityId = 11, toward = { 0, 0, -25 }, hold = true, wait = true })
		expect(reply.ok).toBe(true)
		expect(reply.over).toBe(true)
		expect(reply.arrived).toBe(true)
		expect(reply.at).toEqual({ 0, 3, -25 })
		expect(reply.took).toBeCloseTo(world.walkPlan.seconds, FRAME + 0.006)
		expect(reply.held).toBe(true)
		expect(world.hookCalls[1].options.hold).toBe(true)

		local short = load({ studio = true, capture = true })
		short.walkPlan.arriveAt = Vector3.new(0, 0, -20) -- stopped 5 studs short (a wall)
		local stopped = short.invoke("walk", { entityId = 11, toward = { 0, 0, -25 }, wait = true })
		expect(stopped.over).toBe(true)
		expect(stopped.arrived).toBe(false)
		expect(stopped.at).toEqual({ 0, 3, -20 })

		-- A walk that is still going when walkTimeoutSeconds pass says so.
		local slow = load({ studio = true, capture = true })
		slow.walkPlan.seconds = HOOKS.walkTimeoutSeconds + 5
		local going = slow.invoke("walk", { entityId = 11, toward = { 0, 0, -25 }, wait = true })
		expect(going.over).toBe(false)
		expect(going.took).toBeCloseTo(HOOKS.walkTimeoutSeconds, FRAME + 0.006)
	end)

	it("charge starts the rush, waits out the wind-up and the run, and replies its launch and stops", function()
		local world = load({ studio = true, capture = true })
		world.chargePlan.stops = {
			{ reason = "Wall", after = 0.3, distance = 5.5 },
			{ reason = "Interrupted", after = 0.5, distance = 5.9 },
		}
		local reply = world.invoke("charge", { entityId = 11, toward = { 10, 0, -5 } })
		expect(reply.ok).toBe(true)
		expect(reply.entityId).toBe(11)
		expect(reply.attackId).toBe("Charge")
		expect(reply.from).toEqual({ 0, 3, -5 })
		expect(reply.toward).toEqual({ 10, 0, -5 })
		expect(reply.launched.origin).toEqual({ 0, 3, -5 })
		expect(reply.launched.direction).toEqual({ 1, 0, 0 })
		expect(#reply.stops).toBe(2)
		expect(reply.stops[1]).toEqual({ reason = "Wall", distance = 5.5, after = 0.3 })
		expect(reply.stops[2].reason).toBe("Interrupted")
		expect(reply.complete).toBe(true)
		expect(reply.phase).toBe("Recover")
		expect(reply.seconds).toBeCloseTo(world.chargePlan.windUp + world.chargePlan.run, FRAME + 0.006)
		expect(world.hookCalls[1].kind).toBe("charge")
		expect(close(world.hookCalls[1].goal :: Vector3, Vector3.new(10, 0, -5))).toBe(true)
		expect(#world.moves).toBe(0)

		-- A run still going after chargeTimeoutSeconds is replied as it stands.
		local long = load({ studio = true, capture = true })
		long.chargePlan.run = HOOKS.chargeTimeoutSeconds + 5
		local going = long.invoke("charge", { entityId = 11, toward = { 10, 0, -5 } })
		expect(going.ok).toBe(true)
		expect(going.complete).toBe(false)
		expect(going.phase).toBe("Strike")
		expect(going.seconds).toBeCloseTo(HOOKS.chargeTimeoutSeconds, FRAME + 0.006)
	end)

	it("walk and charge report EnemyService's refusal, and a waiting hook keeps the others out", function()
		local world = load({ studio = true, capture = true })
		world.chargePlan.reject = "KoboldAxeman is no Charger with a rush"
		local refused = world.invoke("charge", { entityId = 11, toward = { 10, 0, -5 } })
		expect(refused.ok).toBe(false)
		expect(refused.error:find(world.chargePlan.reject :: string, 1, true)).never.toBeNil()
		world.walkPlan.reject = "it is Interrupted (Stagger); try again once it recovers"
		local stuck = world.invoke("walk", { entityId = 11, toward = { 0, 0, -25 } })
		expect(stuck.ok).toBe(false)
		expect(stuck.error:find("Stagger", 1, true)).never.toBeNil()

		local busy = load({ studio = true, capture = true })
		local inner: any = nil
		local walkInner: any = nil
		busy.clock.after(0.1, function()
			inner = busy.invoke("basic", nil)
			walkInner = busy.invoke("walk", { entityId = 11, toward = { 0, 0, -10 }, wait = true })
		end)
		expect(busy.invoke("charge", { entityId = 11, toward = { 10, 0, -5 } }).ok).toBe(true)
		expect(inner.ok).toBe(false)
		expect(inner.error:find("busy", 1, true)).never.toBeNil()
		expect(walkInner.ok).toBe(false)
		expect(#busy.calls).toBe(0)
		-- Once the charge replied the next one goes.
		expect(busy.invoke("charge", { entityId = 11, toward = { 10, 0, -5 } }).ok).toBe(true)
	end)

	it("refuses bad arguments and moves or makes nothing", function()
		local far = PLACE.maxCoordinate + 1
		local longName = string.rep("x", HOOKS.maxNameLength + 1)
		local bad: { { any } } = {
			{ "enemy", {} },
			{ "enemy", { entityId = "11", position = { 0, 0, 0 } } },
			{ "enemy", { entityId = 99, position = { 0, 0, 0 } } },
			{ "enemy", { entityId = 1, position = { 0, 0, 0 } } }, -- the player
			{ "enemy", { entityId = 11 } },
			{ "enemy", { entityId = 11, position = { 0, 0 } } },
			{ "enemy", { entityId = 11, position = { far, 0, 0 } } },
			{ "enemy", { entityId = 11, position = { 0, 0, 0 }, facing = "north" } },
			{ "enemy", { entityId = 11, position = { 0, 0, 0 }, hold = "yes" } },
			{ "walk", { entityId = 11 } },
			{ "walk", { entityId = 11, toward = { 0, 0, -5 - HOOKS.maxWalkStuds - 1 } } },
			{ "walk", { entityId = 11, toward = { 0, 0, 0 / 0 } } },
			{ "walk", { entityId = 11, toward = { 0, 0, -10 }, hold = 1 } },
			{ "walk", { entityId = 11, toward = { 0, 0, -10 }, wait = "yes" } },
			{ "walk", { entityId = 99, toward = { 0, 0, -10 } } },
			{ "charge", { entityId = 11 } },
			{ "charge", { entityId = 11, toward = "north" } },
			{ "charge", { entityId = 99, toward = { 10, 0, -5 } } },
			{ "part", {} },
			{ "part", { size = { 4, 4, 4 } } },
			{ "part", { size = { 0, 4, 4 }, position = { 0, 2, 0 } } },
			{ "part", { size = { HOOKS.maxPartStuds + 1, 4, 4 }, position = { 0, 2, 0 } } },
			{ "part", { size = { 4, 4 }, position = { 0, 2, 0 } } },
			{ "part", { size = { 4, 4, 4 }, position = { 0, far, 0 } } },
			{ "part", { size = { 4, 4, 4 }, position = { 0, 2, 0 }, cframe = CFrame.new() } },
			{ "part", { size = { 4, 4, 4 }, cframe = "here" } },
			{ "part", { size = { 4, 4, 4 }, cframe = CFrame.new(far, 0, 0) } },
			{ "part", { size = { 4, 4, 4 }, position = { 0, 2, 0 }, tilt = "steep" } },
			{ "part", { size = { 4, 4, 4 }, position = { 0, 2, 0 }, tilt = { 40, 0 } } },
			{ "part", { size = { 4, 4, 4 }, position = { 0, 2, 0 }, name = "" } },
			{ "part", { size = { 4, 4, 4 }, position = { 0, 2, 0 }, name = longName } },
			{ "part", { size = { 4, 4, 4 }, position = { 0, 2, 0 }, name = 7 } },
			{ "part", { size = { 4, 4, 4 }, position = { 0, 2, 0 }, after = -1 } },
			{ "part", { size = { 4, 4, 4 }, position = { 0, 2, 0 }, after = HOOKS.maxAfterSeconds + 0.5 } },
		}
		for _, case in bad do
			local world = load({ studio = true, capture = true })
			local reply = world.invoke(case[1], case[2])
			expect(reply.ok).toBe(false)
			expect(typeof(reply.error)).toBe("string")
			expect(#world.hookCalls).toBe(0)
			expect(#world.moves).toBe(0)
			expect(#world.workspace:GetChildren()).toBe(0)
			expect(#world.created).toBe(1) -- the BindableFunction alone
		end
		-- A dead enemy is no living enemy.
		local world = load({ studio = true, capture = true })
		world.enemies[1].state = "Dead"
		for _, command in { "enemy", "walk", "charge" } do
			local reply = world.invoke(command, { entityId = 11, position = { 0, 0, 0 }, toward = { 0, 0, -10 } })
			expect(reply.ok).toBe(false)
		end
		expect(#world.hookCalls).toBe(0)
	end)

	it("part makes an anchored, solid part in the dev folder: centre and tilt, or a CFrame", function()
		local world = load({ studio = true, capture = true })
		local wall = world.invoke("part", { size = { 12, 8, 1 }, position = { 0, 4, -20 }, name = "Wall" })
		expect(wall.ok).toBe(true)
		expect(wall.name).toBe("Wall")
		expect(wall.size).toEqual({ 12, 8, 1 })
		expect(wall.position).toEqual({ 0, 4, -20 })
		expect(wall.tilt).toEqual({ 0, 0, 0 })
		expect(wall.parts).toBe(1)
		local folder = world.workspace:FindFirstChild(HOOKS.folderName)
		expect(folder).never.toBeNil()
		expect(folder.ClassName).toBe("Folder")
		local part = folder:FindFirstChild("Wall")
		expect(part.ClassName).toBe("Part")
		expect(part.Anchored).toBe(true)
		expect(part.CanCollide).toBe(true)
		expect(part.CanQuery).toBe(true)
		expect(part.CanTouch).toBe(false)
		expect(part.Size).toBe(Vector3.new(12, 8, 1))
		expect(close(part.CFrame.Position, Vector3.new(0, 4, -20))).toBe(true)
		expect(part.Material).toBe((Enum.Material :: any)[HOOKS.partMaterial])
		local color = Palette.color3(HOOKS.partColorToken)
		expect(
			(Vector3.new(part.Color.R, part.Color.G, part.Color.B) - Vector3.new(color.R, color.G, color.B)).Magnitude
				< 1e-3
		).toBe(true)

		-- A 40 degree slope: + tilt lifts the -Z end.
		local slope = world.invoke("part", { size = { 8, 1, 20 }, position = { 0, 4, -40 }, tilt = 40 })
		expect(slope.ok).toBe(true)
		expect(slope.name).toBe("Part2")
		expect(slope.tilt[1]).toBeCloseTo(40, 0.006)
		local ramp = folder:FindFirstChild("Part2")
		expect(ramp.CFrame.LookVector.Y).toBeCloseTo(math.sin(math.rad(40)), 1e-4)
		expect(ramp.CFrame.UpVector.Z).toBeCloseTo(math.sin(math.rad(40)), 1e-4)

		-- {x, y, z} degrees, the Orientation order; and a CFrame as given.
		local turned = world.invoke("part", { size = { 8, 1, 20 }, position = { 0, 4, -60 }, tilt = { 35, 90, 0 } })
		expect(turned.tilt[1]).toBeCloseTo(35, 0.006)
		expect(turned.tilt[2]).toBeCloseTo(90, 0.006)
		local cframe = CFrame.new(5, 1, 5) * CFrame.Angles(0, math.rad(30), 0)
		local step = world.invoke("part", { size = { 4, 1, 2 }, cframe = cframe, name = "Step" })
		expect(step.ok).toBe(true)
		local stepPart = folder:FindFirstChild("Step")
		expect(close(stepPart.CFrame.Position, cframe.Position)).toBe(true)
		expect(close(stepPart.CFrame.LookVector, cframe.LookVector)).toBe(true)
		expect(#partsIn(world)).toBe(4)
		-- Parts only: no enemy moved, no anti-cheat, no swing.
		expect(#world.hookCalls).toBe(0)
		expect(#world.moves).toBe(0)
		expect(#world.calls).toBe(0)
	end)

	it("part with after lands that much later; at most maxParts; clearparts removes them and the late ones", function()
		local world = load({ studio = true, capture = true })
		local late = world.invoke("part", { size = { 4, 4, 1 }, position = { 0, 2, -10 }, after = 0.5, name = "Late" })
		expect(late.ok).toBe(true)
		expect(late.after).toBe(0.5)
		expect(world.workspace:FindFirstChild(HOOKS.folderName)).toBeNil()
		world.clock.advance(0.49)
		expect(world.workspace:FindFirstChild(HOOKS.folderName)).toBeNil()
		world.clock.advance(0.02)
		expect(world.workspace:FindFirstChild(HOOKS.folderName):FindFirstChild("Late")).never.toBeNil()

		-- The cap counts the parts standing and the ones still to come.
		local full = load({ studio = true, capture = true })
		expect(full.invoke("part", { size = { 1, 1, 1 }, position = { 0, 1, 0 }, after = 1 }).ok).toBe(true)
		for _ = 2, HOOKS.maxParts do
			expect(full.invoke("part", { size = { 1, 1, 1 }, position = { 0, 1, 0 } }).ok).toBe(true)
		end
		local over = full.invoke("part", { size = { 1, 1, 1 }, position = { 0, 1, 0 } })
		expect(over.ok).toBe(false)
		expect(over.error:find("clearparts", 1, true)).never.toBeNil()
		local cleared = full.invoke("clearparts", nil)
		expect(cleared.ok).toBe(true)
		expect(cleared.removed).toBe(HOOKS.maxParts - 1)
		expect(cleared.cancelled).toBe(1)
		expect(full.workspace:FindFirstChild(HOOKS.folderName)).toBeNil()
		full.clock.advance(2) -- the late part never lands
		expect(full.workspace:FindFirstChild(HOOKS.folderName)).toBeNil()
		expect(full.invoke("part", { size = { 1, 1, 1 }, position = { 0, 1, 0 } }).parts).toBe(1)
		local again = full.invoke("clearparts", nil)
		expect(again.removed).toBe(1)
		expect(full.invoke("clearparts", nil)).toEqual({ ok = true, removed = 0, cancelled = 0 })
	end)

	it("exists only where DevCombat does: outside Studio or without DevCapture nothing is made", function()
		for _, options in
			{
				{ studio = false, capture = true },
				{ studio = true, capture = nil },
				{ studio = true, capture = "true" },
			} :: { Options }
		do
			local world = load(options)
			expect(#world.created).toBe(0)
			expect(world.required.EnemyService).toBeNil()
			expect(world.required.PlaygroundLayout).toBeNil()
			expect(#world.workspace:GetChildren()).toBe(0)
		end
	end)

	it("help lists every hook with its arguments", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("help", nil)
		for _, name in { "enemy", "walk", "charge", "part", "clearparts" } do
			expect(table.find(reply.commands, name)).never.toBeNil()
			expect(typeof(reply.usage[name])).toBe("string")
		end
		for name, words in
			{
				enemy = { "entityId", "position", "facing", "hold" },
				walk = { "entityId", "toward", "hold", "wait" },
				charge = { "entityId", "toward" },
				part = { "size", "cframe", "position", "tilt", "name", "after" },
			} :: { [string]: { string } }
		do
			for _, word in words do
				expect(reply.usage[name]:find(word, 1, true)).never.toBeNil()
			end
		end
	end)
end)
