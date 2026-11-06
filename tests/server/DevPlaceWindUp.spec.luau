--!strict
--[[
	DevCombat "place" on an enemy's wind-up (Studio item 302(b)): the move that makes a blow miss has
	to land a set time after the wind-up starts, which no hand can time. With onWindUp (an enemy's
	entity id) and after (seconds), "place" waits on Heartbeat for that enemy's next WindUp phase,
	then `after` seconds into it tells the anti-cheat and pivots the player, as a plain "place" does.
	The harness is tests/server/DevCombat.spec.luau's: the Script loaded the way Studio runs it, with
	a fake EnemyService whose "charge" plays a wind-up on the fake clock behind task.wait and
	os.clock; every serverMoved and PivotTo is recorded with the clock time it came at.
]]

local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")

local NODE = "src/server/dev/DevCombat"
local FILE = "src/server/dev/DevCombat.server.luau"
local FRAME = 1 / 60

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
	moves: { { kind: string, player: any?, seconds: number?, cframe: CFrame?, at: number? } },
	enemyService: any,
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
				table.insert(world.moves, { kind = "pivot", cframe = cframe, at = clock.now })
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
			table.insert(world.moves, { kind = "serverMoved", player = who, seconds = seconds, at = clock.now })
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
		enemyService = enemyService,
	}
	luau.load(Harness.readFile(FILE), { debugName = FILE, environment = env :: any })()
	return world
end

local HOOKS = Dev.hooks
local BOAR = 11
local TOWARD = Vector3.new(10, 0, -5)

local function close(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < 1e-3
end

describe("DevCombat place on a wind-up (302(b))", function()
	it("waits for the enemy's next wind-up and moves the player `after` seconds into it", function()
		local world = load({ studio = true, capture = true })
		-- The boar starts its wind-up (0.6 s) half a second after the call.
		world.clock.after(0.5, function()
			world.enemyService.charge(BOAR, TOWARD)
		end)
		local reply = world.invoke("place", { position = { 4, 3, 0 }, facing = 90, onWindUp = BOAR, after = 0.45 })
		expect(reply.ok).toBe(true)
		expect(#world.moves).toBe(2)
		local told, pivot = world.moves[1], world.moves[2]
		expect(told.kind).toBe("serverMoved")
		expect(pivot.kind).toBe("pivot")
		print(
			("  wind-up at 0.50 s, after 0.45: told at %.3f s, pivoted at %.3f s"):format(told.at or -1, pivot.at or -1)
		)
		-- Within a Heartbeat of 0.5 + 0.45 s, the anti-cheat told on that frame, not when asked.
		expect(math.abs((pivot.at :: number) - 0.95) <= FRAME + 1e-6).toBe(true)
		expect(told.at).toBe(pivot.at)
		expect(close((pivot.cframe :: CFrame).Position, Vector3.new(4, 3, 0))).toBe(true)
		-- Still inside the wind-up: the blow has not landed yet.
		expect(world.enemyService.brainOf(BOAR):getPhase()).toBe("WindUp")
		expect(reply.onWindUp).toBe(BOAR)
		expect(math.abs((reply.windUpAt :: number) - 0.5) <= FRAME + 1e-6).toBe(true)
	end)

	it("refuses a bad after or a wind-up of no living enemy, and gives up with no move when none comes", function()
		local world = load({ studio = true, capture = true })
		for _, bad in { -0.1, HOOKS.maxPlaceAfterSeconds + 0.1, "soon" } do
			local reply = world.invoke("place", { position = { 4, 3, 0 }, onWindUp = BOAR, after = bad })
			expect(reply.ok).toBe(false)
		end
		expect(world.invoke("place", { position = { 4, 3, 0 }, onWindUp = 99, after = 0.2 }).ok).toBe(false)
		expect(#world.moves).toBe(0)
		local started = world.clock.now
		local idle = world.invoke("place", { position = { 4, 3, 0 }, onWindUp = BOAR, after = 0.2 })
		expect(idle.ok).toBe(false)
		expect(idle.error:find("wind-up", 1, true)).never.toBeNil()
		expect(math.abs(world.clock.now - started - HOOKS.windUpWaitSeconds) <= FRAME + 1e-6).toBe(true)
		expect(#world.moves).toBe(0)
	end)

	it("keeps the other commands out while it waits, and help lists onWindUp", function()
		local world = load({ studio = true, capture = true })
		local inner: any = nil
		world.clock.after(0.1, function()
			inner = world.invoke("basic", nil)
		end)
		world.clock.after(0.3, function()
			world.enemyService.charge(BOAR, TOWARD)
		end)
		expect(world.invoke("place", { position = { 4, 3, 0 }, onWindUp = BOAR, after = 0.2 }).ok).toBe(true)
		expect(inner.ok).toBe(false)
		expect(inner.error:find("busy", 1, true)).never.toBeNil()
		local help = world.invoke("help", nil)
		expect(help.usage.place:find("onWindUp", 1, true)).never.toBeNil()
	end)
end)
