--!strict
--[[
	The Studio combat trace hook (src/server/dev/DevCombat.server.luau, D-114), loaded the way
	Studio runs it: a fresh copy of the Script with a fake CombatService (its traceSink field and
	beginBasic / beginArt), a fake EntityService, a fake RunService and Workspace for the gate, and a
	fake clock behind task.wait and os.clock. The fake CombatService calls the sink from its clock
	the way CombatService.tick does from Heartbeat.
]]

local luau = require("@lune/luau")

local Dev = Harness.load("src/shared/data/dev")
local Playground = Harness.load("src/shared/data/playground")

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
	playerRecord: any,
	sss: any,
	invoke: (command: any, args: any) -> any,
	plan: { windows: number, hits: number, reject: string? },
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
		model = { PrimaryPart = { Position = Vector3.new(0, 3, 0), CFrame = CFrame.new(0, 3, 0) } },
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
	local entities = {
		fromPlayer = function(who: any): any
			return if who == player then playerRecord else nil
		end,
		get = function(id: number): any
			if id == playerRecord.id then
				return playerRecord
			end
			for _, record in enemies do
				if record.id == id then
					return record
				end
			end
			return nil
		end,
		enemies = function(): { any }
			return enemies
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
	local fakes: { [string]: any } = { CombatService = combat, EntityService = entities }
	local created: { any } = {}
	local required: { [string]: boolean } = {}
	local printed: { string } = {}
	local attributes: { [string]: any } = { [Dev.attributes.capture] = options.capture }

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
	env.workspace = {
		GetAttribute = function(_self: any, name: string): any
			return attributes[name]
		end,
	}
	env.Instance = {
		new = function(className: string): any
			local instance = { ClassName = className }
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
		playerRecord = playerRecord,
		sss = sss,
		invoke = function(command: any, args: any): any
			return created[1].OnInvoke(command, args)
		end,
		plan = { windows = 1, hits = 1, reject = nil },
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
		expect(boar.distance).toBe(5)
	end)

	it("answers an unknown command with the command list", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("explode", nil)
		expect(reply.ok).toBe(false)
		expect(table.find(reply.commands, "trace")).never.toBeNil()
	end)
end)
