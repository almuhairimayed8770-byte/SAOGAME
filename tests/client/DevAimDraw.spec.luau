--!strict
--[[
	A draw on its own (297, round D on the owner's PC): there is no input that draws the sword by
	itself, so the sprint Draw at 240 fps could not be measured (the draw came with the first
	Basic1, and the tip trace was the cut). DevAim "draw" shows the sword drawn through the
	controller's own prediction (CharacterController.predictDraw, the path a lock-on takes): the
	Draw clip plays from where the body is, sprinting or not, and the server's word follows or the
	sword goes back after choreo.luau sheath.predictSeconds + sheatheDelay. It fires no input
	signal and no request.

	The harness is tests/client/DevAim.spec.luau's: the real LocalScript with fakes for every
	controller it reaches and a fake clock behind task.wait.
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local Dev = Harness.load("src/shared/data/dev")

local NODE = "src/client/dev/DevAim"
local FILE = "src/client/dev/DevAim.client.luau"
local FRAME = 1 / 60

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
	-- What CharacterController.lastFacing returns: the facing the last request carried.
	lastFacing: { number }?,
	lockOnCalls: { any },
	-- Each CharacterController.predictDraw, at its clock time.
	draws: { number },
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
	local draws: { number } = {}
	local character_ = {
		-- The draw a lock-on, a hit or a combat request shows ahead of the server (D-220).
		predictDraw = function()
			table.insert(draws, clock.now)
		end,
		state = function(): string
			return world.clientState
		end,
		lastFacing = function(): { number }?
			return world.lastFacing
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
		lastFacing = nil,
		lockOnCalls = {},
		draws = draws,
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

describe("DevAim draw (297)", function()
	it("is in the command list", function()
		local world = load({ studio = true, capture = true })
		local help = world.invoke("help", nil)
		expect(help.ok).toBe(true)
		expect(table.find(help.commands, "draw")).never.toBeNil()
	end)

	it("draws through CharacterController.predictDraw once, firing no input signal", function()
		local world = load({ studio = true, capture = true })
		local fired = 0
		for _, name in { "artPressed", "artReleased", "basicAttack", "guardChanged", "dodge", "lockToggle" } do
			world.input[name]:Connect(function()
				fired += 1
			end)
		end
		local reply = world.invoke("draw", nil)
		print(
			("297: draw reply ok=%s error=%s, predictDraw calls %d"):format(
				tostring(reply.ok),
				tostring(reply.error),
				#world.draws
			)
		)
		expect(reply.ok).toBe(true)
		expect(#world.draws).toBe(1)
		expect(fired).toBe(0)
		expect(#world.lockOnCalls).toBe(0)
	end)
end)
