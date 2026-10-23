--!strict
--[[
	The Studio aim hook (src/client/dev/DevAim.client.luau, D-114), loaded the way Studio runs it:
	a fresh copy of the LocalScript with fakes for every controller it reaches, a fake RunService
	and Workspace for its gate, and a fake clock behind task.wait and os.clock (Heartbeat only: no
	render step ever runs unless a test turns the fake lock turn on).
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local Dev = Harness.load("src/shared/data/dev")
local InputData = Harness.load("src/shared/data/input")

local NODE = "src/client/dev/DevAim"
local FILE = "src/client/dev/DevAim.client.luau"
local FRAME = 1 / 60
local AIM = Dev.aim

type Clock = {
	now: number,
	queue: { { at: number, fn: () -> () } },
	after: (seconds: number, fn: () -> ()) -> (),
	advance: (seconds: number) -> (),
	onFrame: ((dt: number) -> ())?,
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
			if clock.onFrame ~= nil then
				clock.onFrame(seconds)
			end
		end,
		onFrame = nil,
	}
	return clock
end

local function yawOf(look: Vector3, offset: Vector3): number
	local cross = look.Z * offset.X - look.X * offset.Z
	local dot = look.X * offset.X + look.Z * offset.Z
	return math.deg(math.atan2(cross, dot))
end

type World = {
	clock: Clock,
	created: { any },
	required: { [string]: boolean },
	root: any,
	player: any,
	enemies: { [number]: any },
	localRecord: any,
	lock: any,
	clientState: string,
	lockOnCalls: { any },
	fired: { string },
	input: any,
	replication: any,
	tracker: any,
	bindable: any,
	invoke: (command: any, args: any) -> any,
	turnRoot: (degrees: number) -> (),
	yawTo: (record: any) -> number,
}

type Options = { studio: boolean?, capture: any, renderSteps: boolean? }

local function enemy(id: number, name: string, position: Vector3, hp: number): any
	return {
		id = id,
		kind = "Enemy",
		name = name,
		hp = hp,
		maxHp = hp,
		state = "Idle",
		model = { PrimaryPart = { Position = position } },
	}
end

local function load(options: Options): World
	local clock = newClock()
	local world: World = nil :: any
	local rootFrame = CFrame.new(0, 3, 0) -- looks down -Z
	local root = setmetatable({ Name = "HumanoidRootPart" }, {
		__index = function(_, key: string): any
			if key == "CFrame" then
				return rootFrame
			elseif key == "Position" then
				return rootFrame.Position
			elseif key == "IsA" then
				return function(_self: any, className: string): boolean
					return className == "BasePart"
				end
			end
			return nil
		end,
		__newindex = function(_, key: string, value: any)
			if key == "CFrame" then
				rootFrame = value
			else
				error("unexpected write " .. key)
			end
		end,
	})
	local character = {
		FindFirstChild = function(_self: any, name: string): any
			return if name == "HumanoidRootPart" then root else nil
		end,
	}
	local player = { Name = "Player1", Character = character }
	local enemies = {
		[11] = enemy(11, "Frenzy Boar", Vector3.new(0, 3, 5), 120), -- straight behind, 5 studs
		[12] = enemy(12, "Kobold Axeman", Vector3.new(-8, 3, -8), 190),
	}
	local localRecord = { id = 1, kind = "Player", name = "Player1", hp = 100, maxHp = 100, state = "Idle" }

	local function stub(signals: { string }): any
		local module: { [string]: any } = {}
		for _, name in signals do
			module[name] = Signal.new()
		end
		return module
	end
	local input =
		stub({ "artPressed", "artReleased", "basicAttack", "guardChanged", "dodge", "lockToggle", "sprintChanged" })
	local replication = stub({ "hit", "rejected" })
	local tracker = stub({ "changed", "localChanged" })
	tracker.all = function(): { any }
		local list = { localRecord }
		for _, record in enemies do
			table.insert(list, record)
		end
		table.sort(list, function(a, b)
			return a.id < b.id
		end)
		return list
	end
	tracker.get = function(id: number): any
		return if id == localRecord.id then localRecord else enemies[id]
	end
	tracker.localRecord = function(): any
		return localRecord
	end
	tracker.peekLocalId = function(): number
		return localRecord.id
	end
	local target = {
		current = function(): any
			return world.lock
		end,
		lockOn = function(id: number?): boolean
			table.insert(world.lockOnCalls, id or "nil")
			if id == nil then
				world.lock = nil
				return true
			end
			local record = enemies[id]
			if record == nil or record.state == "Dead" then
				return false
			end
			world.lock = record
			return true
		end,
	}
	input.lockToggle:Connect(function()
		table.insert(world.fired, "lockToggle")
		world.lock = enemies[11]
	end)
	local character_ = {
		state = function(): string
			return world.clientState
		end,
	}

	local services: { [string]: any } = {
		Players = { LocalPlayer = player },
		RunService = {
			IsStudio = function(): boolean
				return options.studio == true
			end,
		},
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local fakes: { [string]: any } = {
		InputController = input,
		TargetController = target,
		CharacterController = character_,
		EntityTracker = tracker,
		Replication = replication,
	}
	local created: { any } = {}
	local required: { [string]: boolean } = {}
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
	env.task = {
		wait = function(seconds: number?): number
			local dt = if seconds ~= nil and seconds > 0 then seconds else FRAME
			-- A longer wait passes frame by frame, as Heartbeat does.
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
		root = root,
		player = player,
		enemies = enemies,
		localRecord = localRecord,
		lock = nil,
		clientState = "Idle",
		lockOnCalls = {},
		fired = {},
		input = input,
		replication = replication,
		tracker = tracker,
		bindable = nil,
		invoke = function(command: any, args: any): any
			return world.bindable.OnInvoke(command, args)
		end,
		turnRoot = function(degrees: number)
			local frame = root.CFrame
			root.CFrame = CFrame.new(frame.Position) * CFrame.Angles(0, math.rad(degrees), 0) * frame.Rotation
		end,
		yawTo = function(record: any): number
			local offset = record.model.PrimaryPart.Position - root.Position
			return yawOf(root.CFrame.LookVector, offset)
		end,
	}
	-- The game's lock turn (CharacterController, D-112) runs on RenderStepped: only when asked.
	if options.renderSteps then
		clock.onFrame = function(dt: number)
			if world.lock ~= nil then
				local delta = world.yawTo(world.lock)
				world.turnRoot(math.clamp(delta, -720 * dt, 720 * dt))
			end
		end
	end

	luau.load(Harness.readFile(FILE), { debugName = FILE, environment = env :: any })()
	world.bindable = created[1]
	return world
end

-- The server's answer to a request, on the fake clock: the body goes Art, the hit lands, the
-- body is free again.
local function serveSwings(world: World, damage: number, reject: string?)
	local function serve(action: string)
		world.clientState = if action == "BasicAttack" then "Basic" else "Art"
		if reject ~= nil then
			world.clock.after(0.05, function()
				world.replication.rejected:Fire(action, reject, 0)
			end)
			return
		end
		local function state(value: string)
			world.localRecord.state = value
			world.tracker.changed:Fire(world.localRecord, "State", value)
		end
		world.clock.after(0.03, function()
			state("Art")
		end)
		world.clock.after(0.25, function()
			local target = world.lock or world.enemies[11]
			target.hp -= damage
			world.replication.hit:Fire({ attackerId = 1, targetId = target.id, damage = damage, killed = false })
		end)
		if action == "Art" then
			world.clock.after(0.6, function()
				state("PostMotion")
			end)
			world.clock.after(1.0, function()
				state("Idle")
			end)
		else
			world.clock.after(0.35, function()
				state("Idle")
			end)
		end
	end
	world.input.basicAttack:Connect(function()
		table.insert(world.fired, ("basic@%.3f"):format(world.clock.now))
		serve("BasicAttack")
	end)
	world.input.artPressed:Connect(function(slot: number)
		table.insert(world.fired, ("press%d@%.3f"):format(slot, world.clock.now))
		world.clientState = "Holding"
	end)
	world.input.artReleased:Connect(function(slot: number, held: number)
		table.insert(world.fired, ("release%d+%.3f"):format(slot, held))
		serve("Art")
	end)
end

describe("DevAim gate", function()
	it("does nothing outside Studio, even with DevCapture", function()
		local world = load({ studio = false, capture = true })
		expect(#world.created).toBe(0)
		expect(world.required.InputController).toBeNil()
		expect(world.required.CharacterController).toBeNil()
		expect(world.required.TargetController).toBeNil()
	end)

	it("does nothing in Studio without DevCapture, or with it not exactly true", function()
		for _, capture in { nil, false, "true", 1 } do
			local world = load({ studio = true, capture = capture })
			expect(#world.created).toBe(0)
			expect(world.required.InputController).toBeNil()
		end
	end)

	it("in Studio with DevCapture puts one BindableFunction under the LocalPlayer", function()
		local world = load({ studio = true, capture = true })
		expect(#world.created).toBe(1)
		local bindable = world.created[1]
		expect(bindable.ClassName).toBe("BindableFunction")
		expect(bindable.Name).toBe(AIM.bindableName)
		expect(bindable.Parent).toBe(world.player)
		expect(typeof(bindable.OnInvoke)).toBe("function")
	end)

	it("never waits on a render step: everything runs on task.wait (Heartbeat)", function()
		-- The code, without its comments (the header and the hint text say why).
		local code = Harness.readFile(FILE):gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
		expect(code:find("%.RenderStepped")).toBeNil()
		expect(code:find("BindToRenderStep", 1, true)).toBeNil()
		expect(code:find("RunService.Stepped", 1, true)).toBeNil()
		expect(code:find("task.wait(", 1, true) ~= nil).toBe(true)
	end)
end)

describe("DevAim commands", function()
	it("answers an unknown command with the command list", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("teleport", nil)
		expect(reply.ok).toBe(false)
		expect(table.find(reply.commands, "swing")).never.toBeNil()
		local help = world.invoke("help", nil)
		expect(help.ok).toBe(true)
	end)

	it("status lists the enemies nearest first with HP, state, distance and yaw off the body", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("status", nil)
		expect(reply.ok).toBe(true)
		expect(reply.state).toBe("Idle")
		expect(reply.serverState).toBe("Idle")
		expect(reply.lockId).toBeNil()
		expect(#reply.enemies).toBe(2)
		local boar = reply.enemies[1]
		expect(boar.id).toBe(11)
		expect(boar.name).toBe("Frenzy Boar")
		expect(boar.hp).toBe(120)
		expect(boar.distance).toBe(5)
		expect(math.abs(boar.yawOff)).toBe(180)
		local kobold = reply.enemies[2]
		expect(kobold.id).toBe(12)
		expect(kobold.yawOff).toBe(45) -- ahead and to the left
	end)

	it("lock {id} locks through TargetController.lockOn and waits for the game's turn", function()
		local world = load({ studio = true, capture = true, renderSteps = true })
		local reply = world.invoke("lock", { id = 11 })
		expect(world.lockOnCalls[1]).toBe(11)
		expect(reply.ok).toBe(true)
		expect(reply.lockId).toBe(11)
		expect(reply.faced).toBe(true)
		expect(math.abs(reply.yawOff)).toBeLessThanOrEqual(AIM.faceToleranceDegrees)
		expect(math.abs(reply.yawBefore)).toBe(180)
		expect(reply.waited).toBeLessThan(AIM.faceTimeoutSeconds)
	end)

	it("lock reports a body the game never turned when no render step runs, and says why", function()
		local world = load({ studio = true, capture = true, renderSteps = false })
		local reply = world.invoke("lock", { id = 11 })
		expect(reply.ok).toBe(true)
		expect(reply.faced).toBe(false)
		expect(math.abs(reply.yawOff)).toBe(180)
		expect(reply.waited).toBeGreaterThanOrEqual(AIM.faceTimeoutSeconds)
		expect(typeof(reply.hint)).toBe("string")
		expect((reply.hint :: string):find("face", 1, true)).never.toBeNil()
	end)

	it("lock without an id takes the F key's path; lock {clear} lets go", function()
		local world = load({ studio = true, capture = true, renderSteps = true })
		local reply = world.invoke("lock", {})
		expect(world.fired[1]).toBe("lockToggle")
		expect(reply.lockId).toBe(11)
		local cleared = world.invoke("lock", { clear = true })
		expect(cleared.ok).toBe(true)
		expect(world.lock).toBeNil()
	end)

	it("never locks again on its own across the local character's death and respawn", function()
		local world = load({ studio = true, capture = true, renderSteps = true })
		world.invoke("lock", { id = 11 })
		expect(world.lockOnCalls).toEqual({ 11 })
		-- The character dies: TargetController lets the lock go (its own spec); DevAim only watches.
		world.localRecord.state = "Dead"
		world.tracker.changed:Fire(world.localRecord, "State", "Dead")
		world.lock = nil
		world.clock.advance(5)
		-- The respawn: a new local record, straight from the old id and through nil.
		world.tracker.localChanged:Fire(nil)
		world.tracker.localChanged:Fire(2)
		world.localRecord.state = "Idle"
		world.tracker.changed:Fire(world.localRecord, "State", "Idle")
		for _ = 1, 120 do
			world.clock.advance(1 / 60)
		end
		local status = world.invoke("status", nil)
		expect(status.lockId).toBeNil()
		expect(world.lockOnCalls).toEqual({ 11 })
		expect(table.find(world.fired, "lockToggle")).toBeNil()
		expect(world.lock).toBeNil()
	end)

	it("lock refuses an id that is not a lockable enemy", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("lock", { id = 99 })
		expect(reply.ok).toBe(false)
		expect(world.lock).toBeNil()
	end)

	it("face turns the body on Heartbeat to the target and waits for the server to see it", function()
		local world = load({ studio = true, capture = true, renderSteps = false })
		world.lock = world.enemies[11]
		local before = world.clock.now
		local reply = world.invoke("face", nil)
		expect(reply.ok).toBe(true)
		expect(reply.turnedBy).toBe("dev")
		expect(reply.faced).toBe(true)
		expect(math.abs(world.yawTo(world.enemies[11]))).toBeLessThan(0.01)
		-- 180 degrees at faceDegreesPerSecond, then the replication settle.
		expect(world.clock.now - before).toBeGreaterThanOrEqual(
			180 / AIM.faceDegreesPerSecond + AIM.replicationSettleSeconds - 1e-6
		)
	end)

	it("swing basic fires the real input signal and reports the yaw at the send, HP before and after", function()
		local world = load({ studio = true, capture = true })
		serveSwings(world, 4, nil)
		world.lock = world.enemies[11]
		-- The game's snap (D-112) turns the body when the swing goes; here the body already faces it.
		world.turnRoot(180)
		local reply = world.invoke("swing", { kind = "basic", count = 3 })
		expect(reply.ok).toBe(true)
		expect(#reply.swings).toBe(3)
		local sends = {}
		for _, entry in world.fired do
			local at = entry:match("^basic@(.*)$")
			if at ~= nil then
				table.insert(sends, tonumber(at) :: number)
			end
		end
		expect(#sends).toBe(3)
		for i = 2, #sends do
			expect(sends[i] - sends[i - 1]).toBeGreaterThanOrEqual(AIM.swingGapSeconds - 1e-6)
			-- Inside the chain window, so the swings run Basic1, 2, 3.
			expect(sends[i] - sends[i - 1]).toBeLessThanOrEqual(AIM.swingGapSeconds + 2 * FRAME)
		end
		local hp = 120
		for index, swing in reply.swings do
			expect(swing.index).toBe(index)
			expect(swing.targetId).toBe(11)
			expect(math.abs(swing.yawAtSend)).toBeLessThan(0.01)
			expect(swing.hpBefore).toBe(hp)
			expect(swing.hpAfter).toBe(hp - 4)
			expect(swing.hits).toBe(1)
			expect(swing.damage).toBe(4)
			expect(swing.rejected).toBeNil()
			hp -= 4
		end
		expect(reply.landed).toBe(3)
	end)

	it("swing reports a rejection and no HP change", function()
		local world = load({ studio = true, capture = true })
		serveSwings(world, 4, "Facing")
		local reply = world.invoke("swing", { kind = "basic" })
		local swing = reply.swings[1]
		expect(swing.rejected).toBe("BasicAttack: Facing")
		expect(swing.hits).toBe(0)
		expect(swing.hpAfter).toBe(swing.hpBefore)
		-- No lock: the nearest enemy, straight behind the body.
		expect(swing.targetId).toBe(11)
		expect(math.abs(swing.yawAtSend)).toBe(180)
	end)

	it("swing art presses the slot, releases it after the hold and waits for the run to end", function()
		local world = load({ studio = true, capture = true })
		serveSwings(world, 12, nil)
		local reply = world.invoke("swing", { kind = "art", slot = 2 })
		expect(reply.ok).toBe(true)
		expect(world.fired[1]:match("^press2@") ~= nil).toBe(true)
		local held = tonumber(world.fired[2]:match("^release2%+(.*)$"))
		expect(held).never.toBeNil()
		expect(held :: number).toBeGreaterThanOrEqual(AIM.artHoldSeconds - 1e-6)
		expect(held :: number).toBeLessThan(InputData.art.cancelTime)
		local swing = reply.swings[1]
		expect(swing.hits).toBe(1)
		expect(swing.hpAfter).toBe(swing.hpBefore - 12)
		expect(swing.serverStates).toEqual({ "Art", "PostMotion", "Idle" })
	end)

	it("swing art stops waiting on a rejection instead of running out the timeout", function()
		local world = load({ studio = true, capture = true })
		serveSwings(world, 12, "Cooldown")
		local before = world.clock.now
		local reply = world.invoke("swing", { kind = "art" })
		expect(reply.swings[1].rejected).toBe("Art: Cooldown")
		expect(world.clock.now - before).toBeLessThan(AIM.artHoldSeconds + 0.05 + 2 * FRAME)
	end)

	it("swing waits for the server to free the body before it sends", function()
		local world = load({ studio = true, capture = true })
		serveSwings(world, 4, nil)
		world.localRecord.state = "Stagger"
		world.clock.after(0.5, function()
			world.localRecord.state = "Idle"
			world.tracker.changed:Fire(world.localRecord, "State", "Idle")
		end)
		local reply = world.invoke("swing", nil)
		expect(reply.swings[1].wasFree).toBe(true)
		local at = tonumber(world.fired[1]:match("^basic@(.*)$")) :: number
		expect(at).toBeGreaterThanOrEqual(0.5 - 1e-6)
	end)

	it("swing refuses bad args", function()
		local world = load({ studio = true, capture = true })
		expect(world.invoke("swing", { kind = "kick" }).ok).toBe(false)
		expect(world.invoke("swing", { count = AIM.maxSwings + 1 }).ok).toBe(false)
		expect(world.invoke("swing", { id = "boar" }).ok).toBe(false)
	end)

	it("guard and dodge fire their input signals", function()
		local world = load({ studio = true, capture = true })
		local guarded: { boolean } = {}
		world.input.guardChanged:Connect(function(held: boolean)
			table.insert(guarded, held)
		end)
		local dodged = 0
		world.input.dodge:Connect(function()
			dodged += 1
		end)
		expect(world.invoke("guard", { held = true }).ok).toBe(true)
		expect(world.invoke("guard", { held = false }).ok).toBe(true)
		expect(world.invoke("dodge", nil).ok).toBe(true)
		expect(guarded).toEqual({ true, false })
		expect(dodged).toBe(1)
	end)

	it("runs one yielding command at a time", function()
		local world = load({ studio = true, capture = true })
		local nested: any = nil
		world.input.dodge:Connect(function()
			nested = world.invoke("swing", nil)
		end)
		world.invoke("dodge", nil)
		expect(nested.ok).toBe(false)
		expect((nested.error :: string):find("busy", 1, true)).never.toBeNil()
		-- And the next command after it runs.
		expect(world.invoke("guard", { held = false }).ok).toBe(true)
	end)
end)
