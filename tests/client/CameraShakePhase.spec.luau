--!strict
--[[
	The wall slam's shake by distance (312, round D on the owner's PC: the shake at 28 studs read
	0.19 against 0.18 at 22; 10 studs read 0.23 to 0.40 over its takes). CameraMath.falloff scales
	a slam at 28 studs to 0.741 of one at 22, but the shake's noise runs on the camera's own clock
	(shakeTime, never reset), so each take starts the noise at another phase and its first frames
	move the camera anywhere from 0.78 to 1.32 times the median: a single take at 28 can out-move
	one at 22. A shake from rest starts its noise at the same phase every time, so the same shake
	moves the camera the same way whenever it comes, and a smaller one is the same moves, smaller.

	The harness is tests/client/CameraController.spec.luau's: the real controller on a fake
	camera, a fake clock and the render steps run by priority.
]]

local luau = require("@lune/luau")

local CameraData = Harness.load("src/shared/data/camera")
local CameraMath = Harness.load("src/client/camera/CameraMath")
local combat = Harness.load("src/shared/data/combat")

local PATH = "src/client/camera/CameraController"
local F = combat.hitStopFrameSeconds
local REST = CameraData.fov.rest
local SUBJECT = Vector3.new(0, 3, 0)

type Step = { name: string, priority: number, fn: (dt: number) -> () }

type Fixture = {
	controller: any,
	camera: any,
	-- Moves the clock `seconds` and runs one frame's render steps (in priority order) reporting
	-- `dt` (`seconds` when nil). `between`, when given, runs once inside the frame just before the
	-- first step bound above `after` (a priority): the character controller's contact is
	-- `after = CHARACTER_PRIORITY`, one made before the frame (the network) `after = -1`.
	frame: (seconds: number, dt: number?, after: number?, between: (() -> ())?) -> (),
	-- Runs `count` 60 fps frames.
	frames: (count: number) -> (),
	clock: () -> number,
	-- The render steps the controller bound, in priority order.
	steps: { Step },
}

-- The controller's late pass.
local LATE_STEP = "SkyspireCameraLate"

local function load(options: { withoutLate: boolean? }?): Fixture
	local state = { clock = 50, steps = {} :: { Step } }
	local signal = {
		Connect = function() end,
	}
	local root = {
		Position = SUBJECT,
		IsA = function(_self: any, name: string): boolean
			return name == "BasePart"
		end,
	}
	local character = {
		PrimaryPart = root,
		FindFirstChild = function(_self: any, _name: string): any
			return root
		end,
	}
	local camera = {
		CFrame = CFrame.new(0, 10, 20),
		FieldOfView = 70,
		CameraType = nil,
		Focus = CFrame.new(),
	}
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, name: string, priority: number, fn: (dt: number) -> ())
				if options ~= nil and options.withoutLate and name == LATE_STEP then
					return -- the controller as it was: its main step alone
				end
				table.insert(state.steps, { name = name, priority = priority, fn = fn })
				table.sort(state.steps, function(a: Step, b: Step): boolean
					return a.priority < b.priority
				end)
			end,
		},
		UserInputService = {
			MouseEnabled = true,
			TouchEnabled = false,
			MouseBehavior = nil,
			InputChanged = signal,
			LastInputTypeChanged = signal,
		},
		Players = {
			LocalPlayer = { Character = character, CharacterAdded = signal, CharacterRemoving = signal },
		},
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node(PATH)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	env.workspace = {
		CurrentCamera = camera,
		Spherecast = function(): any
			return nil -- no walls
		end,
	}
	env.RaycastParams = {
		new = function(): any
			return {}
		end,
	}
	env.os = {
		clock = function(): number
			return state.clock
		end,
	}
	local controller = luau.load(Harness.readFile(PATH .. ".luau"), { debugName = PATH, environment = env :: any })()
	controller.start()
	local fixture: Fixture = nil :: any
	fixture = {
		controller = controller,
		camera = camera,
		frame = function(seconds: number, dt: number?, after: number?, between: (() -> ())?)
			state.clock += seconds
			local pending = between
			for _, step in state.steps do
				if pending ~= nil and step.priority > (after :: number) then
					pending()
					pending = nil
				end
				step.fn(if dt ~= nil then dt else seconds)
			end
			if pending ~= nil then
				pending()
			end
		end,
		frames = function(count: number)
			for _ = 1, count do
				fixture.frame(F)
			end
		end,
		clock = function(): number
			return state.clock
		end,
		steps = state.steps,
	}
	return fixture
end

-- A camera settled on its still subject: the FOV at rest and the follow spot reached.
local function settled(options: { withoutLate: boolean? }?): (Fixture, Vector3)
	local fixture = load(options)
	fixture.frames(240)
	expect(fixture.camera.FieldOfView).toBeCloseTo(REST, 1e-4)
	return fixture, fixture.camera.CFrame.Position
end

describe("CameraController: a shake from rest starts its noise at one phase (312)", function()
	it("moves the camera the same way for the same shake whenever it comes, scaled by its falloff", function()
		local slam = Harness.load("src/shared/data/fx").wallSlam
		local near = CameraMath.falloff(22, slam.shakeFullRadius, slam.shakeRadius)
		local far = CameraMath.falloff(28, slam.shakeFullRadius, slam.shakeRadius)
		local early, spot = settled()
		local late = settled()
		local farther = settled()
		-- The same rest, then the slams at different moments of the camera's clock.
		late.frames(37)
		farther.frames(53)
		early.frame(F, nil, -1, function()
			early.controller.shake(slam.shakeTier, near)
		end)
		late.frame(F, nil, -1, function()
			late.controller.shake(slam.shakeTier, near)
		end)
		farther.frame(F, nil, -1, function()
			farther.controller.shake(slam.shakeTier, far)
		end)
		local worst, worstScaled = 0, 0
		for _ = 1, 8 do
			local a = early.camera.CFrame.Position - spot
			local b = late.camera.CFrame.Position - spot
			local c = farther.camera.CFrame.Position - spot
			worst = math.max(worst, (b - a).Magnitude)
			worstScaled = math.max(worstScaled, (c - a * (far / near)).Magnitude)
			early.frames(1)
			late.frames(1)
			farther.frames(1)
		end
		print(
			("312: falloff 22 %.3f, 28 %.3f; worst gap same shake later %.4f, 28-stud shake off 0.741x the 22 %.4f"):format(
				near,
				far,
				worst,
				worstScaled
			)
		)
		expect(worst).toBeLessThan(1e-6)
		expect(worstScaled).toBeLessThan(1e-6)
	end)
end)
