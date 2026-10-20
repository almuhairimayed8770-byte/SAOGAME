--!strict
--[[
	CharacterController's engine glue, loaded fresh with fakes around it: a Humanoid whose Move sets
	MoveDirection (as the engine's does), a root part, stub Choreo modules (Siblings), the render
	step captured from BindToRenderStep, and Net.client() recording every request. A frame runs the
	way the engine runs it: the control script's Move with the stick first, then the controller's
	step, then physics moves the root at the Humanoid's move and WalkSpeed (so the step reads the
	velocity of the frame before, as it does in the engine).
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
}

local function load(): Rig
	local clock = 0
	local step: ((dt: number) -> ())? = nil
	local sent: { { name: string, payload: any } } = {}
	local humanoid: any = {
		WalkSpeed = 16,
		JumpPower = 0,
		JumpHeight = 0,
		AutoRotate = true,
		MoveDirection = Vector3.zero,
		FloorMaterial = Enum.Material.Grass,
	}
	function humanoid.Move(self: any, direction: Vector3)
		self.MoveDirection = if direction.Magnitude > 0 then direction.Unit else Vector3.zero
	end
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
	local locomotion = {
		new = function(): any
			return {
				serverDrawn = function(): boolean
					return false
				end,
				update = function() end,
			}
		end,
	}
	local fakes: { [string]: any } = {
		Net = {
			client = function(): any
				return {
					fire = function(name: string, payload: any)
						table.insert(sent, { name = name, payload = payload })
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
