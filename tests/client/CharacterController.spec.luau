--!strict
--[[
	CharacterController's engine glue, loaded fresh with fakes around it: a Humanoid whose Move sets
	MoveDirection (as the engine's does), a root part, stub Choreo modules (Siblings), the render
	step captured from BindToRenderStep, and Net.client() recording every request. A frame runs the
	way the engine runs it: the control script's Move with the stick first, then the controller's
	step, then physics moves the root at the Humanoid's move and WalkSpeed (so the step reads the
	velocity of the frame before, as it does in the engine). The Humanoid records every property
	write (each one fires Changed, and a client WalkSpeed write is networked), and an optional fake
	fx.Impact sibling records the director calls the controller makes.
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local Siblings = Harness.load("src/client/controllers/Siblings")
local ChoreoData = Harness.load("src/shared/data/choreo")

local CONTROLLER_PATH = "src/client/controllers/CharacterController"
local FRAME = 1 / 60

type Rig = {
	controller: any,
	sent: { { name: string, payload: any } },
	-- One frame with the stick at a world direction (zero for none).
	frame: (stick: Vector3) -> (),
	humanoid: any,
	model: any,
	-- Every Humanoid property write, in order ({ key, value }).
	writes: { { key: string, value: any } },
	-- The sends and the fake Impact's calls in one ordered list ({ kind = "send" | "impact", name, args }).
	log: { { kind: string, name: string, args: { any } } },
}

type Options = {
	-- The fake Locomotion's stopGait, with the gait phase moving on by this much per call (0 holds
	-- it still). It starts at 0.1, the left foot plants at 0 and the right at 0.5, each 0.3 of a
	-- cycle before it is over its Idle spot: a carry that starts there runs 0.7 of a cycle.
	stopGait: number?,
	-- Hand the controller a recording fx.Impact sibling instead of a stub.
	impact: boolean?,
}

local IMPACT_CALLS = { "guardRaise", "dodge", "release", "cancelActivation", "activation" }

local function load(options: Options?): Rig
	local opts: Options = options or {}
	local clock = 0
	local step: ((dt: number) -> ())? = nil
	local sent: { { name: string, payload: any } } = {}
	local writes: { { key: string, value: any } } = {}
	local log: { { kind: string, name: string, args: { any } } } = {}
	local props: { [string]: any } = {
		WalkSpeed = 16,
		JumpPower = 0,
		JumpHeight = 0,
		AutoRotate = true,
		MoveDirection = Vector3.zero,
		FloorMaterial = Enum.Material.Grass,
	}
	function props.Move(self: any, direction: Vector3)
		self.MoveDirection = if direction.Magnitude > 0 then direction.Unit else Vector3.zero
	end
	local humanoid: any = setmetatable({}, {
		__index = props,
		__newindex = function(_self: any, key: string, value: any)
			table.insert(writes, { key = key, value = value })
			props[key] = value
		end,
	})
	local root: any = { CFrame = CFrame.new(), Position = Vector3.zero, AssemblyLinearVelocity = Vector3.zero }
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
	local gaitPhase = 0.1 - (opts.stopGait or 0)
	local locomotion = {
		new = function(): any
			return {
				serverDrawn = function(): boolean
					return false
				end,
				update = function() end,
				stopGait = if opts.stopGait ~= nil
					then function(_self: any, into: any)
						gaitPhase = (gaitPhase + (opts.stopGait :: number)) % 1
						into.phase, into.leftStep, into.leftAfter, into.rightStep, into.rightAfter =
							gaitPhase, 0, 0.3, 0.5, 0.3
					end
					else nil,
			}
		end,
	}
	local impact: { [string]: any } = {}
	for _, name in IMPACT_CALLS do
		impact[name] = function(...: any)
			table.insert(log, { kind = "impact", name = name, args = { ... } })
		end
	end
	local fakes: { [string]: any } = {
		Net = {
			client = function(): any
				return {
					fire = function(name: string, payload: any)
						table.insert(sent, { name = name, payload = payload })
						table.insert(log, { kind = "send", name = name, args = { payload } })
					end,
					on = function() end,
				}
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
			load = function(_parent: any, path: string): (any, boolean)
				if path == "choreo.Locomotion" then
					return locomotion, true
				end
				if path == "fx.Impact" and opts.impact then
					return impact, true
				end
				return Siblings.stub(), false
			end,
			call = Siblings.call,
			stub = Siblings.stub,
		},
	}
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, _name: string, _priority: number, fn: (dt: number) -> ())
				step = fn
			end,
		},
		Players = {
			LocalPlayer = { CharacterAdded = Signal.new(), CharacterRemoving = Signal.new(), Character = model },
		},
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
	env.workspace = {
		GetServerTimeNow = function(): number
			return clock
		end,
	}
	env.os = {
		clock = function(): number
			return clock
		end,
	}
	env.task = { delay = function() end }
	local controller = luau.load(
		Harness.readFile(CONTROLLER_PATH .. ".luau"),
		{ debugName = CONTROLLER_PATH, environment = env :: any }
	)()
	controller.start()
	assert(step ~= nil, "the controller bound no render step")
	return {
		controller = controller,
		sent = sent,
		humanoid = humanoid,
		model = model,
		writes = writes,
		log = log,
		frame = function(stick: Vector3)
			clock += FRAME
			humanoid:Move(stick)
			local runStep = step :: (dt: number) -> ()
			runStep(FRAME)
			root.AssemblyLinearVelocity = humanoid.MoveDirection * humanoid.WalkSpeed
			root.Position += root.AssemblyLinearVelocity * FRAME
		end,
	}
end

local function lastDodge(rig: Rig): Vector3?
	for index = #rig.sent, 1, -1 do
		local entry = rig.sent[index]
		if entry.name == "DodgeRequest" then
			local d = entry.payload.direction
			return Vector3.new(d[1], d[2], d[3])
		end
	end
	return nil
end

local FORWARD = Vector3.new(0, 0, -1) -- the root's look (CFrame.new() faces -Z)

describe("CharacterController dodge direction", function()
	it("with the stick held forward the dodge goes forward", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		rig.controller.dodge()
		local direction = lastDodge(rig)
		expect(direction).never.toBeNil()
		expect((direction :: Vector3).Z).toBeCloseTo(FORWARD.Z, 1e-6)
		expect((direction :: Vector3).X).toBeCloseTo(0, 1e-6)
	end)

	it("a dodge pressed during the two-step stop steps back: the stick let go", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		-- The stick lets go: the two-step stop carries the Humanoid along the last move.
		rig.frame(Vector3.zero)
		rig.frame(Vector3.zero)
		expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		rig.controller.dodge()
		local direction = lastDodge(rig)
		expect(direction).never.toBeNil()
		expect((direction :: Vector3).Z).toBeCloseTo(-FORWARD.Z, 1e-6)
		expect((direction :: Vector3).X).toBeCloseTo(0, 1e-6)
	end)

	it("after the stop has run out the Humanoid is still and the dodge steps back", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local frames = math.ceil(ChoreoData.locomotion.stopStepsSeconds / FRAME) + 2
		for _ = 1, frames do
			rig.frame(Vector3.zero)
		end
		expect(rig.humanoid.MoveDirection.Magnitude).toBe(0)
		rig.controller.dodge()
		local direction = lastDodge(rig)
		expect(direction).never.toBeNil()
		expect((direction :: Vector3).Z).toBeCloseTo(-FORWARD.Z, 1e-6)
		expect((direction :: Vector3).X).toBeCloseTo(0, 1e-6)
	end)
end)

-- Humanoid writes of `key` from write index `from` on.
local function writesOf(rig: Rig, key: string, from: number): { any }
	local values = {}
	for index = from, #rig.writes do
		local entry = rig.writes[index]
		if entry.key == key then
			table.insert(values, entry.value)
		end
	end
	return values
end

describe("CharacterController's two-step stop", function()
	it("holds the speed it had through Humanoid.WalkSpeed while the gait has not walked on", function()
		-- The fake gait's phase holds still, so the stop's next Footstep never comes: the carry holds
		-- the run speed along the last move until stopStepsSeconds. Without Locomotion.stopGait the
		-- carry would fall over stopStepsSeconds instead (about 9.3 after 30 frames).
		local rig = load({ stopGait = 0 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		for _ = 1, 30 do
			rig.frame(Vector3.zero)
		end
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.runSpeed)
		expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		expect(rig.humanoid.MoveDirection.X).toBeCloseTo(0, 1e-6)
	end)

	it("slows the Humanoid as the gait walks on to the planted foot, never under stopEndSpeed", function()
		-- 0.02 of a cycle a frame: the first carry frame keeps the run speed (16) with 0.7 of a cycle
		-- to go; on carry frame k, (0.7 - 0.02 (k - 1)) is left and the speed is 16 x that / 0.7.
		local rig = load({ stopGait = 0.02 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local run = ChoreoData.locomotion.runSpeed
		local seen: { [number]: number } = {}
		for frame = 1, 30 do
			rig.frame(Vector3.zero)
			seen[frame] = rig.humanoid.WalkSpeed
			expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		end
		expect(seen[1]).toBeCloseTo(run, 1e-6)
		expect(seen[15]).toBeCloseTo(run * (0.7 - 0.02 * 14) / 0.7, 1e-6)
		expect(seen[30]).toBeCloseTo(ChoreoData.locomotion.stopEndSpeed, 1e-6)
	end)

	it("writes WalkSpeed once a frame at most and AutoRotate only when the lock changes", function()
		-- Each write fires the Humanoid's Changed handlers, and a client WalkSpeed write replicates.
		local rig = load({ stopGait = 0.02 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		-- Walking: one WalkSpeed write and one AutoRotate write in all (the first frame).
		expect(writesOf(rig, "WalkSpeed", 1)).toEqual({ ChoreoData.locomotion.runSpeed })
		expect(writesOf(rig, "AutoRotate", 1)).toEqual({ true })
		local most, autoRotate, frames = 0, 0, 0
		repeat
			local from = #rig.writes + 1
			rig.frame(Vector3.zero)
			frames += 1
			most = math.max(most, #writesOf(rig, "WalkSpeed", from))
			autoRotate += #writesOf(rig, "AutoRotate", from)
		until rig.humanoid.MoveDirection.Magnitude == 0 or frames > 200
		expect(most).toBe(1)
		expect(autoRotate).toBe(0)
		-- The carry is over: the Humanoid has its own speed back, written once.
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.runSpeed)
		local from = #rig.writes + 1
		rig.frame(Vector3.zero)
		rig.frame(FORWARD)
		rig.frame(FORWARD)
		expect(writesOf(rig, "WalkSpeed", from)).toEqual({})
		-- A steady carry (the gait holding still) writes nothing after its first frame.
		local steady = load({ stopGait = 0 })
		for _ = 1, 10 do
			steady.frame(FORWARD)
		end
		local after = #steady.writes + 1
		for _ = 1, 30 do
			steady.frame(Vector3.zero)
		end
		expect(writesOf(steady, "WalkSpeed", after)).toEqual({})
		expect(writesOf(steady, "AutoRotate", after)).toEqual({})
		-- A locked state flips AutoRotate once each way.
		local before = #steady.writes + 1
		steady.controller.dodge()
		for _ = 1, 40 do
			steady.frame(Vector3.zero)
		end
		expect(writesOf(steady, "AutoRotate", before)).toEqual({ false, true })
	end)

	it("hands the Humanoid back its own speed once the carry ends", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local frames = math.ceil(ChoreoData.locomotion.stopStepsSeconds / FRAME) + 2
		for _ = 1, frames do
			rig.frame(Vector3.zero)
		end
		expect(rig.humanoid.MoveDirection.Magnitude).toBe(0)
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.runSpeed)
	end)
end)

-- The fake Impact's calls named `name`, in order.
local function impactCalls(rig: Rig, name: string): { { any } }
	local calls = {}
	for _, entry in rig.log do
		if entry.kind == "impact" and entry.name == name then
			table.insert(calls, entry.args)
		end
	end
	return calls
end

local function sends(rig: Rig, name: string): number
	local count = 0
	for _, entry in rig.sent do
		if entry.name == name then
			count += 1
		end
	end
	return count
end

-- The index in rig.log of the first entry of `kind` named `name`, or nil.
local function firstIndex(rig: Rig, kind: string, name: string): number?
	for index, entry in rig.log do
		if entry.kind == kind and entry.name == name then
			return index
		end
	end
	return nil
end

describe("CharacterController's impact director calls", function()
	it("a predicted guard raise sounds once, before its GuardRequest; a release or a refused raise does not", function()
		local rig = load({ impact = true })
		rig.frame(Vector3.zero)
		rig.controller.setGuard(true)
		local raises = impactCalls(rig, "guardRaise")
		expect(#raises).toBe(1)
		expect(raises[1][1]).toBe(rig.model)
		expect(raises[1][2]).toBe(true)
		local raiseAt = firstIndex(rig, "impact", "guardRaise") :: number
		local requestAt = firstIndex(rig, "send", "GuardRequest") :: number
		expect(raiseAt < requestAt).toBe(true)
		for _ = 1, 30 do
			rig.frame(Vector3.zero)
		end
		rig.controller.setGuard(false)
		expect(#impactCalls(rig, "guardRaise")).toBe(1)
		-- A raise the controller refuses (mid-dodge) predicts nothing and sounds nothing.
		for _ = 1, 30 do
			rig.frame(Vector3.zero)
		end
		rig.controller.dodge()
		rig.controller.setGuard(true)
		expect(rig.controller.state()).toBe("Dodge")
		expect(#impactCalls(rig, "guardRaise")).toBe(1)
	end)

	it("a local dodge out of the two-step stop plays one Dodge cue and sends one DodgeRequest", function()
		local rig = load({ impact = true, stopGait = 0 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		rig.frame(Vector3.zero)
		rig.frame(Vector3.zero)
		rig.controller.dodge()
		local dodges = impactCalls(rig, "dodge")
		expect(#dodges).toBe(1)
		expect(dodges[1][1]).toBe(rig.model)
		expect(dodges[1][2]).toBe(true)
		expect(sends(rig, "DodgeRequest")).toBe(1)
		-- A second press inside the cooldown does neither.
		rig.frame(Vector3.zero)
		rig.controller.dodge()
		expect(#impactCalls(rig, "dodge")).toBe(1)
		expect(sends(rig, "DodgeRequest")).toBe(1)
	end)

	it("an Art release hands the director the clip and its freeze time, once, with the ArtRequest", function()
		local Combat = Harness.load("src/shared/data/combat")
		local rig = load({ impact = true })
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		expect(rig.controller.state()).toBe("Holding")
		local held = 0
		for _ = 1, 12 do
			rig.frame(Vector3.zero)
			held += FRAME
		end
		expect(held < Combat.activationCancelTime).toBe(true)
		rig.controller.releaseArt(1, held)
		expect(rig.controller.state()).toBe("Art")
		local releases = impactCalls(rig, "release")
		expect(#releases).toBe(1)
		local art = rig.controller.slots()[1]
		expect(releases[1][1]).toBe(rig.model)
		expect(releases[1][2]).toBe(art.clip)
		-- No ActivationHold froze the clip (the stub animator fires no events): the freeze is the
		-- whole time the key was down, and the clip waits that long again.
		expect(releases[1][3]).toBeCloseTo(held, 1e-9)
		expect(releases[1][4]).toBeCloseTo(held, 1e-9)
		expect(sends(rig, "ArtRequest")).toBe(1)
		expect(#impactCalls(rig, "cancelActivation")).toBe(0)
	end)

	it("every way a hold ends without a launch cancels the activation once", function()
		-- Let go past the cancel time.
		local Combat = Harness.load("src/shared/data/combat")
		local rig = load({ impact = true })
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.releaseArt(1, Combat.activationCancelTime + 0.05)
		expect(rig.controller.state()).toBe("Idle")
		local cancels = impactCalls(rig, "cancelActivation")
		expect(#cancels).toBe(1)
		expect(cancels[1][1]).toBe(rig.model)
		expect(#impactCalls(rig, "release")).toBe(0)
		expect(sends(rig, "ArtRequest")).toBe(0)
		-- The hold timed out (InputController's cancel).
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.cancelArt(1)
		expect(#impactCalls(rig, "cancelActivation")).toBe(2)
		-- A dodge out of the hold.
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.dodge()
		expect(rig.controller.state()).toBe("Dodge")
		expect(#impactCalls(rig, "cancelActivation")).toBe(3)
		-- Nothing held: a cancel is a no-op.
		rig.controller.cancelArt(1)
		expect(#impactCalls(rig, "cancelActivation")).toBe(3)
	end)
end)
