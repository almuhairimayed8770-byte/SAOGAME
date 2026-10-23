--!strict
--[[
	TrailingSend on a fake clock, then against Net's real server rate limiter: the client's sends
	travel through an ordered network with latency (a reliable RemoteEvent never reorders) into
	Net.server()'s receive path, loaded with a fake os.clock, so the token bucket runs with the
	world.luau numbers. Mashing a state (lock, next, unlock...) must always end with the server
	holding the client's last state, and never trip the limiter. The control shows the harness can
	lose a state: firing on every change (the old TargetController) loses the last one. Last, the
	real Main.client's Tab gate: mashing Tab at any rate never trips SwitchCallRequest's bucket.
]]

local luau = require("@lune/luau")

local TrailingSend = Harness.load("src/shared/net/TrailingSend")
local World = Harness.load("src/shared/data/world")

local NET_PATH = "src/shared/net/Net"
local RATE = World.anticheat.remoteRates.TargetRequest

-- A discrete-event clock: `after` queues a function, `runUntil` runs every queued one in time order.
local function newClock(): any
	local clock = { now = 0, queue = {} :: { any }, seq = 0 }
	function clock.at(time: number, fn: () -> ())
		clock.seq += 1
		table.insert(clock.queue, { time = time, seq = clock.seq, fn = fn })
		table.sort(clock.queue, function(a: any, b: any): boolean
			if a.time == b.time then
				return a.seq < b.seq
			end
			return a.time < b.time
		end)
	end
	function clock.after(seconds: number, fn: () -> ())
		clock.at(clock.now + seconds, fn)
	end
	function clock.runUntil(time: number)
		while #clock.queue > 0 and clock.queue[1].time <= time do
			local entry = table.remove(clock.queue, 1)
			clock.now = entry.time
			entry.fn()
		end
		clock.now = math.max(clock.now, time)
	end
	return clock
end

-- Net.server() with fake remotes, Players and RunService, its os.clock reading `clock`. Returns
-- the server API and the fake remotes by name (each keeps the server's OnServerEvent handlers).
local function loadServerNet(clock: any): (any, { [string]: any })
	local created: { any } = {}
	local function newInstance(className: string): any
		local fake: any = { ClassName = className, Name = className, Parent = nil, serverHandlers = {} }
		function fake.IsA(self: any, name: string): boolean
			return self.ClassName == name
		end
		fake.OnServerEvent = {
			Connect = function(_self: any, handler: (...any) -> ()): any
				table.insert(fake.serverHandlers, handler)
				return { Disconnect = function() end }
			end,
		}
		table.insert(created, fake)
		return fake
	end
	local services: { [string]: any } = {
		RunService = {
			IsServer = function()
				return true
			end,
			IsClient = function()
				return false
			end,
		},
		Players = {
			PlayerRemoving = {
				Connect = function(_self: any, _handler: any): any
					return { Disconnect = function() end }
				end,
			},
			GetPlayers = function(_self: any): { any }
				return {}
			end,
		},
		ReplicatedStorage = { Name = "ReplicatedStorage", ClassName = "ReplicatedStorage" },
	}
	local env = Harness.environment()
	env.script = Harness.node(NET_PATH)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	env.Instance = { new = newInstance }
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	env.os = {
		clock = function(): number
			return clock.now
		end,
	}
	local Net = luau.load(Harness.readFile(NET_PATH .. ".luau"), { debugName = NET_PATH, environment = env :: any })()
	local server = Net.server()
	local remotes: { [string]: any } = {}
	for _, fake in created do
		remotes[fake.Name] = fake
	end
	return server, remotes
end

export type Link = {
	clock: any,
	fire: (name: string, payload: any) -> (), -- the client's Net.fire
	server: () -> any, -- the state the server holds (TargetRequest's entityId unless told otherwise)
	rejected: () -> number, -- rate-limit rejections of that remote
	forget: () -> (), -- the server drops what it holds (a respawn's new record starts empty)
}

-- A client wired to the real limiter: each fire reaches the server `latency()` later, never
-- before an earlier fire (ordered delivery), so a late packet bunches the ones behind it. The
-- server keeps `field` of the last `remote` payload it accepted (TargetRequest's entityId).
local function newLink(latency: () -> number, remote: string?, field: string?): Link
	local clock = newClock()
	local server, remotes = loadServerNet(clock)
	local player = { Name = "Masher", UserId = 7 }
	local remoteName = remote or "TargetRequest"
	local key = field or "entityId"
	local held: any = nil
	local rejected = 0
	server.on(remoteName, function(_player: any, payload: any)
		held = payload[key]
	end)
	server.abuse:Connect(function(_player: any, name: string, reason: string)
		if name == remoteName and reason == "rate" then
			rejected += 1
		end
	end)
	local lastArrival = 0
	return {
		clock = clock,
		fire = function(name: string, payload: any)
			local arrival = math.max(clock.now + latency(), lastArrival)
			lastArrival = arrival
			clock.at(arrival, function()
				for _, handler in remotes[name].serverHandlers do
					handler(player, payload)
				end
			end)
		end,
		server = function(): any
			return held
		end,
		rejected = function(): number
			return rejected
		end,
		forget = function()
			held = nil
		end,
	}
end

local function newSender(link: Link): any
	return TrailingSend.new({
		gap = TrailingSend.gapOf("TargetRequest"),
		now = function(): number
			return link.clock.now
		end,
		schedule = link.clock.after,
		send = function(entityId: any)
			link.fire("TargetRequest", { entityId = entityId })
		end,
	})
end

-- The lock cycle with two enemies in view: lock the first, the second, then unlock.
local CYCLE = { 11 :: any, 12, false }
local function stateOf(press: number): any
	local value = CYCLE[(press - 1) % #CYCLE + 1]
	return if value == false then nil else value
end

-- Press times for `presses` presses `interval` apart, with up to `jitter` seconds either way.
local function pressTimes(presses: number, interval: number, jitter: number, rng: any): { number }
	local times = {}
	local t = 1
	for _ = 1, presses do
		table.insert(times, t)
		t += math.max(0.005, interval + (rng:NextNumber() * 2 - 1) * jitter)
	end
	return times
end

type Outcome = { lost: boolean, rejected: number, final: any, held: any }

-- A press handler: given the state the lock cycle is at, it changes the client and returns the
-- state the client now holds.
type Policy = (link: Link) -> (state: any) -> any

-- One mash: each press goes through the policy; the clock then runs well past the last send.
-- `remote` and `field` pick what the server keeps (TargetRequest's entityId by default).
local function mash(times: { number }, latency: () -> number, policy: Policy, remote: string?, field: string?): Outcome
	local link = newLink(latency, remote, field)
	local press = policy(link)
	local final: any = nil
	for index, time in times do
		link.clock.runUntil(time)
		final = press(stateOf(index))
	end
	link.clock.runUntil(times[#times] + 2)
	return { lost = link.server() ~= final, rejected = link.rejected(), final = final, held = link.server() }
end

local function paced(link: Link): (any) -> any
	local sender = newSender(link)
	return function(state: any): any
		sender:set(state)
		return state
	end
end

local function everyPress(link: Link): (any) -> any
	return function(state: any): any
		link.fire("TargetRequest", { entityId = state })
		return state
	end
end

-- The real TargetController, loaded fresh with fakes around it: two enemies in front of the
-- camera, the lock key pressed by hand, its os.clock and task.delay on the link's clock and its
-- Net.client() firing into the link. Each press is one TargetController.toggle().
local CONTROLLER_PATH = "src/client/controllers/TargetController"
local Signal = Harness.load("src/shared/util/Signal")

local function fakeEnemy(id: number, position: Vector3): any
	return { id = id, kind = "Enemy", state = "Idle", model = { PrimaryPart = { Position = position } } }
end

-- Loads the controller; returns it and its fake EntityTracker (fire `localChanged` for a respawn).
local function loadTargetController(link: Link): (any, any)
	local enemies = { fakeEnemy(11, Vector3.new(0, 0, -8)), fakeEnemy(12, Vector3.new(4, 0, -14)) }
	local root = {
		Position = Vector3.zero,
		IsA = function(_self: any, className: string): boolean
			return className == "BasePart"
		end,
	}
	local character = {
		FindFirstChild = function(_self: any, name: string): any
			return if name == "HumanoidRootPart" then root else nil
		end,
	}
	local fakes: { [string]: any } = {
		Net = {
			client = function(): any
				return { fire = link.fire, on = function() end }
			end,
		},
		EntityTracker = {
			all = function(): { any }
				return enemies
			end,
			get = function(id: number): any
				for _, record in enemies do
					if record.id == id then
						return record
					end
				end
				return nil
			end,
			removed = Signal.new(),
			changed = Signal.new(),
			localChanged = Signal.new(),
		},
		InputController = { lockToggle = Signal.new() },
		CameraController = { setLockTarget = function() end },
		Siblings = {
			load = function(): (any, boolean)
				return { setImportance = function() end }, true
			end,
		},
	}
	local services: { [string]: any } = {
		RunService = { Heartbeat = Signal.new() },
		Players = { LocalPlayer = { Character = character } },
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node(CONTROLLER_PATH)
	env.require = function(target: any): any
		return fakes[target.Name] or Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	env.workspace = { CurrentCamera = { CFrame = CFrame.new(Vector3.new(0, 5, 10), Vector3.zero) } }
	env.os = {
		clock = function(): number
			return link.clock.now
		end,
	}
	env.task = {
		delay = function(seconds: number, fn: () -> ())
			link.clock.after(seconds, fn)
		end,
	}
	local controller = luau.load(
		Harness.readFile(CONTROLLER_PATH .. ".luau"),
		{ debugName = CONTROLLER_PATH, environment = env :: any }
	)()
	controller.start()
	return controller, fakes.EntityTracker
end

local function controllerPolicy(link: Link): (any) -> any
	local controller = loadTargetController(link)
	return function(expected: any): any
		controller.toggle()
		local current = controller.current()
		local held = if current ~= nil then current.id else nil
		assert(held == expected, "the lock cycle is not the one the spec expects")
		return held
	end
end

-- The real CharacterController, loaded fresh with fakes around it: a standing character, a stub
-- animator and Locomotion (Siblings hands out no-op stubs), its os.clock, task.delay and server
-- clock on the link's clock and its Net.client() firing into the link. Each press flips the
-- guard: setGuard(true) raises it, setGuard(false) lets it go.
local CHARACTER_PATH = "src/client/controllers/CharacterController"

local function guardPolicy(link: Link): (any) -> any
	local Siblings = Harness.load("src/client/controllers/Siblings")
	local humanoid = {
		WalkSpeed = 16,
		JumpPower = 0,
		JumpHeight = 0,
		AutoRotate = true,
		MoveDirection = Vector3.zero,
		FloorMaterial = Enum.Material.Grass,
	}
	local root = { CFrame = CFrame.new(), Position = Vector3.zero, AssemblyLinearVelocity = Vector3.zero }
	local model = {
		WaitForChild = function(_self: any, name: string): any
			return if name == "Humanoid" then humanoid else root
		end,
		GetAttribute = function(): any
			return nil
		end,
		GetAttributeChangedSignal = function(): any
			return Signal.new()
		end,
	}
	local fakes: { [string]: any } = {
		Net = {
			client = function(): any
				return { fire = link.fire, on = function() end }
			end,
		},
		EntityTracker = {
			localRecord = function(): any
				return nil
			end,
			peekLocalId = function(): any
				return nil
			end,
			changed = Signal.new(),
			localChanged = Signal.new(),
		},
		Replication = { rejected = Signal.new(), hit = Signal.new(), clipEvent = Signal.new() },
		CameraController = { fovKick = function() end },
		Siblings = {
			load = function(): (any, boolean)
				return Siblings.stub(), false
			end,
			call = Siblings.call,
			stub = Siblings.stub,
		},
	}
	local services: { [string]: any } = {
		RunService = { BindToRenderStep = function() end, Heartbeat = Signal.new() },
		Players = {
			LocalPlayer = { CharacterAdded = Signal.new(), CharacterRemoving = Signal.new(), Character = model },
		},
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node(CHARACTER_PATH)
	env.require = function(target: any): any
		return fakes[target.Name] or Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	env.workspace = {
		GetServerTimeNow = function(): number
			return link.clock.now
		end,
	}
	env.os = {
		clock = function(): number
			return link.clock.now
		end,
	}
	env.task = {
		delay = function(seconds: number, fn: () -> ())
			link.clock.after(seconds, fn)
		end,
	}
	local controller = luau.load(
		Harness.readFile(CHARACTER_PATH .. ".luau"),
		{ debugName = CHARACTER_PATH, environment = env :: any }
	)()
	controller.start()
	local held = false
	return function(_state: any): any
		held = not held
		controller.setGuard(held)
		assert(controller.state() == (if held then "Guard" else "Idle"), "the guard did not follow the key")
		return held
	end
end

local INTERVALS = { 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.1, 0.11, 0.125, 0.15, 0.2, 0.3 }

-- Every mash of 6 to 30 presses at each interval, steady and jittered, on a steady and a jittery
-- network. Returns the outcomes that lost the last state or tripped the limiter. `remote` and
-- `field` as for mash.
local function sweep(policy: Policy, remote: string?, field: string?): ({ string }, { string }, number)
	local rng = Random.new(51)
	local lost, tripped = {}, {}
	local runs = 0
	for _, interval in INTERVALS do
		for presses = 6, 30 do
			for _, jitter in { 0, interval * 0.4 } do
				for _, spread in { 0, 0.1 } do
					local times = pressTimes(presses, interval, jitter, rng)
					local outcome = mash(times, function(): number
						return 0.05 + rng:NextNumber() * spread
					end, policy, remote, field)
					runs += 1
					local label = ("%d presses every %.3f s (jitter %.3f, latency spread %.2f)"):format(
						presses,
						interval,
						jitter,
						spread
					)
					if outcome.lost then
						table.insert(lost, label)
					end
					if outcome.rejected > 0 then
						table.insert(tripped, label)
					end
				end
			end
		end
	end
	return lost, tripped, runs
end

describe("TrailingSend", function()
	it("the gap is one over the remote's perSecond; an unknown remote is an error", function()
		expect(TrailingSend.gapOf("TargetRequest")).toBeCloseTo(1 / RATE.perSecond, 1e-12)
		expect(TrailingSend.gapOf("GuardRequest")).toBeCloseTo(
			1 / World.anticheat.remoteRates.GuardRequest.perSecond,
			1e-12
		)
		expect(function()
			TrailingSend.gapOf("NoSuchRemote")
		end).toThrow("NoSuchRemote")
	end)

	it("sends the first change at once and another once the gap is over", function()
		local clock = newClock()
		local sent: { any } = {}
		local sender = TrailingSend.new({
			gap = 0.125,
			now = function(): number
				return clock.now
			end,
			schedule = clock.after,
			send = function(state: any)
				table.insert(sent, { at = clock.now, state = state })
			end,
		})
		sender:set(11)
		expect(#sent).toBe(1)
		expect(sent[1].state).toBe(11)
		expect(sender:isPending()).toBe(false)
		clock.runUntil(0.2)
		sender:set(12)
		expect(#sent).toBe(2)
		expect(sent[2].at).toBeCloseTo(0.2, 1e-9)
	end)

	it("a change inside the gap waits for the rest of it; one send carries the latest state", function()
		local clock = newClock()
		local sent: { any } = {}
		local sender = TrailingSend.new({
			gap = 0.125,
			now = function(): number
				return clock.now
			end,
			schedule = clock.after,
			send = function(state: any)
				table.insert(sent, { at = clock.now, state = state })
			end,
		})
		sender:set(11)
		clock.runUntil(0.03)
		sender:set(12)
		expect(sender:isPending()).toBe(true)
		clock.runUntil(0.06)
		sender:set(nil)
		clock.runUntil(0.09)
		sender:set(11)
		clock.runUntil(0.1)
		sender:set(nil) -- the unlock is the last word
		expect(#sent).toBe(1)
		clock.runUntil(1)
		expect(#sent).toBe(2)
		expect(sent[2].at).toBeCloseTo(0.125, 1e-9)
		expect(sent[2].state).toBeNil()
		expect(sender:isPending()).toBe(false)
	end)

	it("never sends two requests closer than the gap", function()
		local clock = newClock()
		local times: { number } = {}
		local sender = TrailingSend.new({
			gap = 0.125,
			now = function(): number
				return clock.now
			end,
			schedule = clock.after,
			send = function(_state: any)
				table.insert(times, clock.now)
			end,
		})
		local rng = Random.new(3)
		local t = 0
		for press = 1, 400 do
			t += rng:NextNumber() * 0.2
			clock.runUntil(t)
			sender:set(press)
		end
		clock.runUntil(t + 1)
		expect(#times > 100).toBe(true)
		for index = 2, #times do
			expect(times[index] - times[index - 1] >= 0.125 - 1e-9).toBe(true)
		end
	end)

	it("paced at the GuardRequest gap, a raise that can parry is never delayed", function()
		-- D-031: a raise parries only after the guard was down parryRearmTime. The release before
		-- it went out at most one gap late, so with the rearm at least two gaps the raise always
		-- finds the gap over and goes out at once; only raises that cannot parry ever wait.
		local Combat = Harness.load("src/shared/data/combat")
		local gap = TrailingSend.gapOf("GuardRequest")
		expect(Combat.parryRearmTime >= 2 * gap).toBe(true)
		local clock = newClock()
		local sent: { any } = {}
		local sender = TrailingSend.new({
			gap = gap,
			now = function(): number
				return clock.now
			end,
			schedule = clock.after,
			send = function(held: any)
				table.insert(sent, { at = clock.now, held = held })
			end,
		})
		local rng = Random.new(31)
		local t, releasedAt = 1, -math.huge
		local parryRaises, delayedReleases = 0, 0
		for _ = 1, 2000 do
			t += rng:NextNumber() * 0.4
			clock.runUntil(t)
			local count = #sent
			sender:set(true)
			if t - releasedAt >= Combat.parryRearmTime then
				parryRaises += 1
				expect(#sent).toBe(count + 1)
				expect(sent[#sent].at).toBe(t)
			end
			t += rng:NextNumber() * 0.2
			clock.runUntil(t)
			sender:set(false)
			releasedAt = t
			if sender:isPending() then
				delayedReleases += 1
			end
		end
		clock.runUntil(t + 1)
		expect(sent[#sent].held).toBe(false)
		expect(parryRaises > 100).toBe(true)
		expect(delayedReleases > 100).toBe(true)
	end)
end)

-- A sender on `clock` that records every send as { at, state }.
local function recordingSender(clock: any, gap: number, burst: number?): (any, { any })
	local sent: { any } = {}
	local sender = TrailingSend.new({
		gap = gap,
		burst = burst,
		now = function(): number
			return clock.now
		end,
		schedule = clock.after,
		send = function(state: any)
			table.insert(sent, { at = clock.now, state = state })
		end,
	})
	return sender, sent
end

-- The guard's sender as CharacterController builds it, with a client burst, firing schema-valid
-- GuardRequests into the link. Each press flips the guard.
local function pacedGuard(burst: number): Policy
	return function(link: Link): (any) -> any
		local sender = TrailingSend.new({
			gap = TrailingSend.gapOf("GuardRequest"),
			burst = burst,
			now = function(): number
				return link.clock.now
			end,
			schedule = link.clock.after,
			send = function(held: any)
				link.fire("GuardRequest", { held = held, facing = { 0, 0, -1 }, clientTime = link.clock.now })
			end,
		})
		local held = false
		return function(_state: any): any
			held = not held
			sender:set(held)
			return held
		end
	end
end

-- A guard tap and the raise after it (raise at 1, release `hold` later, raise again `down` after
-- that) through a sender with `burst` into Net's real server, 50 ms each way. Returns the send
-- times and whether the server's parry rearm (EntityService.setGuard: the last raise parries only
-- when it arrives parryRearmTime or more after the release, by the server's receipt clock) took.
local function tapThenRaise(burst: number, hold: number, down: number): ({ number }, boolean)
	local Combat = Harness.load("src/shared/data/combat")
	local clock = newClock()
	local server, remotes = loadServerNet(clock)
	local receipts: { any } = {}
	server.on("GuardRequest", function(_player: any, payload: any)
		table.insert(receipts, { at = clock.now, held = payload.held })
	end)
	local sends: { number } = {}
	local sender = TrailingSend.new({
		gap = TrailingSend.gapOf("GuardRequest"),
		burst = burst,
		now = function(): number
			return clock.now
		end,
		schedule = clock.after,
		send = function(held: any)
			table.insert(sends, clock.now)
			local payload = { held = held, facing = { 0, 0, -1 }, clientTime = clock.now }
			clock.after(0.05, function()
				for _, handler in remotes.GuardRequest.serverHandlers do
					handler({ Name = "Tapper", UserId = 9 }, payload)
				end
			end)
		end,
	})
	clock.runUntil(1)
	sender:set(true)
	clock.runUntil(1 + hold)
	sender:set(false)
	clock.runUntil(1 + hold + down)
	sender:set(true)
	clock.runUntil(3)
	local held, releasedAt, rearmed = false, nil :: number?, false
	for _, receipt in receipts do
		if receipt.held and not held then
			rearmed = releasedAt == nil or receipt.at - releasedAt >= Combat.parryRearmTime - 1e-9
		elseif not receipt.held and held then
			releasedAt = receipt.at
		end
		held = receipt.held
	end
	return sends, rearmed and #receipts == 3
end

-- The guard's client burst: world.luau anticheat.remoteRates.GuardRequest.clientBurst (2).
local GUARD_BURST: number = (World.anticheat.remoteRates.GuardRequest :: any).clientBurst or 2

describe("TrailingSend with a burst", function()
	it("a burst below one send is an error; burst 1 is the default", function()
		local clock = newClock()
		expect(function()
			recordingSender(clock, 0.1, 0)
		end).toThrow("burst")
		local sender, sent = recordingSender(clock, 0.1)
		sender:set(1)
		sender:set(2)
		expect(#sent).toBe(1)
		expect(sender:isPending()).toBe(true)
	end)

	it("burst 2 sends a tap's two changes at once, then one more per gap", function()
		local clock = newClock()
		local gap = 1 / 12
		local sender, sent = recordingSender(clock, gap, 2)
		sender:set(true)
		clock.runUntil(0.02)
		sender:set(false)
		expect(#sent).toBe(2)
		expect(sent[2].at).toBeCloseTo(0.02, 1e-9)
		-- The bucket is empty: the third change waits until one send has refilled (one gap after
		-- the first), and the fourth for one gap after that.
		clock.runUntil(0.03)
		sender:set(true)
		expect(sender:isPending()).toBe(true)
		clock.runUntil(0.2)
		expect(#sent).toBe(3)
		expect(sent[3].at).toBeCloseTo(gap, 1e-9)
		sender:set(false)
		expect(#sent).toBe(4)
		expect(sent[4].at).toBeCloseTo(0.2, 1e-9)
	end)

	it("never sends more than burst plus one per gap in any stretch of time", function()
		for _, burst in { 1, 2, 3 } do
			local clock = newClock()
			local gap = 0.125
			local sender, sent = recordingSender(clock, gap, burst)
			local rng = Random.new(burst)
			local t = 0
			for press = 1, 400 do
				t += rng:NextNumber() * 0.15
				clock.runUntil(t)
				sender:set(press)
			end
			clock.runUntil(t + 1)
			expect(#sent > 150).toBe(true)
			expect(sent[#sent].state).toBe(400)
			local worst = math.huge
			for first = 1, #sent do
				for last = first + 1, math.min(#sent, first + 8) do
					-- Sends first..last: at most burst + (span / gap) of them.
					local slack = burst + (sent[last].at - sent[first].at) / gap - (last - first + 1)
					worst = math.min(worst, slack)
				end
			end
			expect(worst >= -1e-9).toBe(true)
		end
	end)

	it("burst 2 lets a guard tap and the raise after it out at their presses; the server rearms", function()
		-- A quick tap (hold 20 to 150 ms) and a raise once the guard was down parryRearmTime or
		-- more: the raise must parry. With burst 1 the release waits for the end of the gap after
		-- the raise, the server starts its rearm clock up to 63 ms late and refuses the parry.
		local Combat = Harness.load("src/shared/data/combat")
		local refusedBy: { [number]: { string } } = { [1] = {}, [GUARD_BURST] = {} }
		local cases = 0
		for holdStep = 2, 15 do
			local hold = holdStep / 100
			for downStep = 0, 8 do
				local down = Combat.parryRearmTime + downStep / 100
				cases += 1
				for _, burst in { 1, GUARD_BURST } do
					local sends, rearmed = tapThenRaise(burst, hold, down)
					if not rearmed then
						table.insert(refusedBy[burst], ("hold %.2f down %.2f"):format(hold, down))
					end
					if burst == GUARD_BURST then
						expect(#sends).toBe(3)
						expect(sends[1]).toBeCloseTo(1, 1e-9)
						expect(sends[2]).toBeCloseTo(1 + hold, 1e-9)
						expect(sends[3]).toBeCloseTo(1 + hold + down, 1e-9)
					end
				end
			end
		end
		expect(table.concat(refusedBy[GUARD_BURST], "; ")).toBe("")
		-- The control: paced one per gap, short taps lose parries (28 of 126 here).
		expect(#refusedBy[1] > 0).toBe(true)
		print(
			("  rearm refused: burst 1 %d of %d, burst %d %d"):format(
				#refusedBy[1],
				cases,
				GUARD_BURST,
				#refusedBy[GUARD_BURST]
			)
		)
	end)

	it("burst 2: a raise pressed during a basic swing reaches the server before the swing's hit opens", function()
		-- CombatService.setGuard cancels the server's basic on the raise. The basic can only start
		-- once the guard is down, so: raise, release `hold` later, the basic `wait` after that, the
		-- raise `into` the swing. A raise pressed before the first HitWindowOpen must also go out
		-- before it, or the server lands a hit the client already cancelled.
		local basic = Harness.load("src/shared/clips/player/OneHandedSword/Basic1")
		local opens = math.huge
		for _, event in basic.events do
			if event.kind == "HitWindowOpen" then
				opens = math.min(opens, event.time)
			end
		end
		expect(opens < math.huge).toBe(true)
		local gap = TrailingSend.gapOf("GuardRequest")
		local lateBy: { [number]: number } = { [1] = -math.huge, [GUARD_BURST] = -math.huge }
		for _, burst in { 1, GUARD_BURST } do
			for holdStep = 1, 20 do
				for waitStep = 0, 5 do
					for intoStep = 1, math.floor(opens * 100) - 1 do
						local clock = newClock()
						local sender, sent = recordingSender(clock, gap, burst)
						local hold, wait, into = holdStep / 100, waitStep / 100, intoStep / 100
						sender:set(true)
						clock.runUntil(hold)
						sender:set(false)
						local basicAt = hold + wait
						clock.runUntil(basicAt + into)
						sender:set(true)
						clock.runUntil(2)
						local raiseSent = sent[#sent].at
						expect(sent[#sent].state).toBe(true)
						lateBy[burst] = math.max(lateBy[burst], raiseSent - basicAt - opens)
					end
				end
			end
		end
		expect(lateBy[GUARD_BURST] < 0).toBe(true)
		-- The control: paced one per gap, the cancel can land 57 ms into the hit window.
		expect(lateBy[1] > 0).toBe(true)
		print(
			("  latest raise past the hit opening: burst 1 %+.3f s, burst %d %+.3f s"):format(
				lateBy[1],
				GUARD_BURST,
				lateBy[GUARD_BURST]
			)
		)
	end)
end)

describe("TrailingSend against Net's rate limiter", function()
	it("guard mashing with burst 2 never trips the limiter and always ends on the last state", function()
		local lost, tripped, runs = sweep(pacedGuard(GUARD_BURST), "GuardRequest", "held")
		expect(runs).toBe(#INTERVALS * 25 * 4)
		if #lost > 0 then
			print(("  lost %d of %d, first: %s"):format(#lost, runs, lost[1]))
		end
		expect(#lost).toBe(0)
		expect(#tripped).toBe(0)
	end)

	it("mashing 6 to 30 presses always ends with the server holding the client's last state", function()
		local lost, tripped, runs = sweep(paced)
		expect(runs).toBe(#INTERVALS * 25 * 4)
		expect(#lost).toBe(0)
		if #lost > 0 then
			print("lost: " .. table.concat(lost, "; "))
		end
		-- Never faster than the bucket refills: the limiter never fires, the burst stays spare.
		expect(#tripped).toBe(0)
	end)

	it("control: firing on every press, as before, loses the last state", function()
		local lost, tripped, runs = sweep(everyPress)
		expect(#tripped > 0).toBe(true)
		expect(#lost > 0).toBe(true)
		-- 6 presses 40 ms apart: the sixth, an unlock, finds the bucket under one token, so the
		-- server keeps the second enemy locked (and the sword out). Steady mashes lose from 10
		-- presses at 12.5 a second and 17 at 10 a second.
		local outcome = mash(pressTimes(6, 0.04, 0, Random.new(1)), function(): number
			return 0.05
		end, everyPress)
		expect(outcome.final).toBeNil()
		expect(outcome.held).toBe(12)
		expect(outcome.rejected).toBe(1)
		print(("  firing on every press lost the last state in %d of %d mashes"):format(#lost, runs))
	end)
end)

describe("TargetController over Net's rate limiter", function()
	it("mashing the lock key always leaves the server on the client's last lock or unlock", function()
		local lost, tripped, runs = sweep(controllerPolicy)
		expect(runs).toBe(#INTERVALS * 25 * 4)
		if #lost > 0 then
			print(("  lost %d of %d, first: %s"):format(#lost, runs, lost[1]))
		end
		expect(#lost).toBe(0)
		expect(#tripped).toBe(0)
	end)
end)

describe("TargetController across a respawn", function()
	it("the lock ends with the character, and a lock held when the new record arrives is sent again", function()
		-- EntityService.registerPlayer gives a respawned player a new record with no target.
		local link = newLink(function(): number
			return 0.05
		end)
		local controller, tracker = loadTargetController(link)
		link.clock.runUntil(1)
		controller.toggle()
		link.clock.runUntil(2)
		expect(controller.current().id).toBe(11)
		expect(link.server()).toBe(11)

		-- The character is gone: no lock on either side.
		tracker.localChanged:Fire(nil)
		expect(controller.current()).toBeNil()
		link.clock.runUntil(3)
		expect(link.server()).toBeNil()

		-- The player locks before the server has registered the new character (the request finds
		-- no record), then the new record arrives empty: the client's lock goes to it.
		controller.toggle()
		link.clock.runUntil(4)
		link.forget()
		tracker.localChanged:Fire(21)
		link.clock.runUntil(5)
		expect(controller.current().id).toBe(11)
		expect(link.server()).toBe(11)
		expect(link.rejected()).toBe(0)
	end)
end)

describe("CharacterController's guard over Net's rate limiter", function()
	it("tapping guard always leaves the server on the client's last raise or release", function()
		-- A lost release leaves the server in Guard with no timeout: hits are guarded, the gauge
		-- drains and Drawn stays on until the next action.
		local lost, tripped, runs = sweep(guardPolicy, "GuardRequest", "held")
		expect(runs).toBe(#INTERVALS * 25 * 4)
		if #lost > 0 then
			print(("  lost %d of %d, first: %s"):format(#lost, runs, lost[1]))
		end
		expect(#lost).toBe(0)
		expect(#tripped).toBe(0)
	end)
end)

describe("CharacterController's guard tap and the server's parry rearm", function()
	it("a tap's release reaches the server at once, so a raise after parryRearmTime down still parries", function()
		-- EntityService.setGuard: a raise parries only when the guard was down combat.parryRearmTime
		-- by the server's receipt clock. A release held back to the end of the gap starts that clock
		-- late, and the server refuses a parry the player earned.
		local Combat = Harness.load("src/shared/data/combat")
		local refused: { string } = {}
		for _, hold in { 0.02, 0.04, 0.06, 0.08, 0.1, 0.15 } do
			for step = 0, 8 do
				local down = Combat.parryRearmTime + step * 0.01
				local clock = newClock()
				local server, remotes = loadServerNet(clock)
				local receipts: { any } = {}
				server.on("GuardRequest", function(_player: any, payload: any)
					table.insert(receipts, { at = clock.now, held = payload.held })
				end)
				local link: any = {
					clock = clock,
					fire = function(name: string, payload: any)
						clock.after(0.05, function()
							for _, handler in remotes[name].serverHandlers do
								handler({ Name = "Tapper", UserId = 9 }, payload)
							end
						end)
					end,
				}
				local press = guardPolicy(link)
				clock.runUntil(1)
				press(nil) -- raise
				clock.runUntil(1 + hold)
				press(nil) -- release: the tap
				clock.runUntil(1 + hold + down)
				press(nil) -- the raise meant as a parry
				clock.runUntil(3)
				local held, releasedAt, rearmed = false, nil :: number?, false
				for _, receipt in receipts do
					if receipt.held and not held then
						rearmed = releasedAt == nil or receipt.at - releasedAt >= Combat.parryRearmTime - 1e-9
					elseif not receipt.held and held then
						releasedAt = receipt.at
					end
					held = receipt.held
				end
				if not rearmed then
					table.insert(refused, ("hold %.2f down %.2f"):format(hold, down))
				end
			end
		end
		expect(table.concat(refused, "; ")).toBe("")
	end)
end)

-- The real Main.client, loaded fresh with fakes for every controller it starts: its Net.client()
-- fires into the link and its os.clock reads the link's clock. Each press is one Tab press
-- (InputController.switchCall). No sibling package loads, so nothing else starts.
local MAIN_NODE = "src/client/Main" -- the LocalScript node Rojo builds from Main.client.luau
local MAIN_FILE = "src/client/Main.client.luau"

local function loadMainClient(link: Link): any
	local function stubModule(signals: { string }): any
		local module: { [string]: any } = {}
		for _, name in signals do
			module[name] = Signal.new()
		end
		return setmetatable(module, {
			__index = function(): any
				return function() end
			end,
		})
	end
	local input = stubModule({
		"artPressed",
		"artReleased",
		"artCancelled",
		"basicAttack",
		"guardChanged",
		"dodge",
		"sprintChanged",
		"switchCall",
	})
	local fakes: { [string]: any } = {
		Net = {
			client = function(): any
				return { fire = link.fire, on = function() end }
			end,
		},
		EntityTracker = stubModule({ "localChanged" }),
		Replication = stubModule({}),
		CharacterController = stubModule({}),
		InputController = input,
		TargetController = stubModule({ "targetChanged" }),
		CameraController = stubModule({}),
		Siblings = {
			load = function(): (any, boolean)
				return nil, false
			end,
			call = function() end,
		},
	}
	local services: { [string]: any } = {
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node(MAIN_NODE)
	env.require = function(target: any): any
		return fakes[target.Name] or Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	env.os = {
		clock = function(): number
			return link.clock.now
		end,
	}
	luau.load(Harness.readFile(MAIN_FILE), { debugName = MAIN_FILE, environment = env :: any })()
	return input
end

-- Tab pressed `presses` times `interval` apart from t = 1 through the real Main.client into Net's
-- limiter. Returns the server's rate rejections and the SwitchCallRequests it accepted.
local function mashTab(presses: number, interval: number, latency: () -> number): (number, number)
	local link = newLink(latency, "SwitchCallRequest", "unused")
	local accepted = 0
	link.clock.runUntil(0)
	local input = loadMainClient({
		clock = link.clock,
		fire = function(name: string, payload: any)
			if name == "SwitchCallRequest" then
				accepted += 1
			end
			link.fire(name, payload)
		end,
		server = link.server,
		rejected = link.rejected,
		forget = link.forget,
	})
	for press = 1, presses do
		link.clock.runUntil(1 + (press - 1) * interval)
		input.switchCall:Fire()
	end
	link.clock.runUntil(1 + presses * interval + 2)
	return link.rejected(), accepted - link.rejected()
end

describe("Main.client's Tab over Net's rate limiter", function()
	it("Tab at 4 presses a second for 10 s never trips SwitchCallRequest's bucket", function()
		local rate = World.anticheat.remoteRates.SwitchCallRequest
		local rejected, accepted = mashTab(40, 0.25, function(): number
			return 0.05
		end)
		expect(rejected).toBe(0)
		-- One call per refill goes out: every other press at 4 a second against 2 a second.
		expect(accepted).toBe(math.floor(10 * rate.perSecond))
	end)

	it("mashing Tab at 2.5 to 60 presses a second on a jittery network never trips the bucket", function()
		local rng = Random.new(77)
		local tripped: { string } = {}
		for _, perSecond in { 2.5, 3, 4, 6, 10, 20, 60 } do
			local rejected = mashTab(math.floor(perSecond * 10), 1 / perSecond, function(): number
				return 0.05 + rng:NextNumber() * 0.2
			end)
			if rejected > 0 then
				table.insert(tripped, ("%s a second: %d rejected"):format(tostring(perSecond), rejected))
			end
		end
		expect(table.concat(tripped, "; ")).toBe("")
	end)

	it("a single Tab press after a pause still goes out at once", function()
		local rejected, accepted = mashTab(1, 1, function(): number
			return 0.05
		end)
		expect(rejected).toBe(0)
		expect(accepted).toBe(1)
	end)
end)
