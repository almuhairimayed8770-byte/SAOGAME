--!strict
--[[
	CameraController loaded fresh with a fake engine around it: a fake RunService that hands the
	render step to the spec, a fake clock behind os.clock, a plain camera table, a still subject and
	no walls. Covers the transients (the FOV punch, the Art and dash kick, the shake, the nudge)
	across a render stall (the display asleep: no render step for 55 s, then one frame whose dt
	the engine may report as one frame or as the whole gap) and a long hitch.
]]

local luau = require("@lune/luau")

local CameraData = Harness.load("src/shared/data/camera")
local CameraMath = Harness.load("src/client/camera/CameraMath")
local combat = Harness.load("src/shared/data/combat")

local PATH = "src/client/camera/CameraController"
local F = combat.hitStopFrameSeconds
local REST = CameraData.fov.rest
local SUBJECT = Vector3.new(0, 3, 0)

type Fixture = {
	controller: any,
	camera: any,
	-- Moves the clock `seconds` and runs one render step reporting `dt` (`seconds` when nil).
	frame: (seconds: number, dt: number?) -> (),
	-- Runs `count` 60 fps frames.
	frames: (count: number) -> (),
	clock: () -> number,
}

local function load(): Fixture
	local state = { clock = 50, step = nil :: ((dt: number) -> ())? }
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
			BindToRenderStep = function(_self: any, _name: string, _priority: number, fn: (dt: number) -> ())
				state.step = fn
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
		frame = function(seconds: number, dt: number?)
			state.clock += seconds
			local step = state.step
			if step ~= nil then
				step(if dt ~= nil then dt else seconds)
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
	}
	return fixture
end

-- A camera settled on its still subject: the FOV at rest and the follow spot reached.
local function settled(): (Fixture, Vector3)
	local fixture = load()
	fixture.frames(240)
	expect(fixture.camera.FieldOfView).toBeCloseTo(REST, 1e-4)
	return fixture, fixture.camera.CFrame.Position
end

describe("CameraController transients", function()
	it("shows the punch's curve at 60 fps, timed from when it was asked for", function()
		local fixture = settled()
		local params = CameraData.punch.Kill
		local askedAt = fixture.clock()
		fixture.controller.punch("Kill")
		for _ = 1, 12 do
			fixture.frames(1)
			local offset = CameraMath.punchOffset(fixture.clock() - askedAt, params, 0)
			expect(fixture.camera.FieldOfView - REST).toBeCloseTo(offset, 1e-6)
		end
	end)

	it("keeps the kick decaying from when it was asked for, frame by frame", function()
		local fixture = settled()
		local askedAt = fixture.clock()
		fixture.controller.fovKick("Art")
		fixture.frames(30)
		local kick = CameraMath.decay(CameraData.fov.artKick, CameraData.fov.kickDecay, fixture.clock() - askedAt)
		-- The FOV spring trails the kick a little; it never runs ahead of it or past rest.
		expect(fixture.camera.FieldOfView).toBeGreaterThan(REST)
		expect(fixture.camera.FieldOfView - REST).toBeLessThan(CameraData.fov.artKick)
		expect(kick).toBeGreaterThan(0)
	end)
end)

describe("CameraController render stalls", function()
	for _, case in { { name = "one frame", dt = F }, { name = "the whole gap", dt = 55 } } do
		it(
			("ends a punch, a kick, a shake and a nudge asked for before a 55 s stall (the engine reports %s)"):format(
				case.name
			),
			function()
				local fixture, spot = settled()
				fixture.controller.punch("Kill")
				fixture.controller.fovKick("Art")
				fixture.controller.shake("Kill")
				fixture.controller.nudge(spot + Vector3.new(4, 0, -4), CameraData.nudge.studs)
				-- The display sleeps: no render step for 55 s, then the first frame that comes back.
				fixture.frame(55, case.dt)
				expect(fixture.camera.FieldOfView).toBeCloseTo(REST, 1e-3)
				expect((fixture.camera.CFrame.Position - spot).Magnitude).toBeLessThan(1e-3)
				-- And it stays there: nothing of the old hit plays out on the frames after.
				for _ = 1, 30 do
					fixture.frames(1)
					expect(fixture.camera.FieldOfView).toBeCloseTo(REST, 1e-3)
					expect((fixture.camera.CFrame.Position - spot).Magnitude).toBeLessThan(1e-3)
				end
			end
		)
	end

	it("starts a punch asked for during a stall from rest, not from an offset left over before it", function()
		local fixture = settled()
		fixture.controller.punch("Kill")
		fixture.frames(2) -- part way into the push
		expect(fixture.camera.FieldOfView).toBeLessThan(REST)
		fixture.frame(30, F) -- the window sleeps; the punch is long over
		local askedAt = fixture.clock()
		fixture.controller.punch("Final")
		fixture.frames(1)
		local params = CameraData.punch.Final
		expect(fixture.camera.FieldOfView - REST).toBeCloseTo(CameraMath.punchOffset(F, params, 0), 1e-6)
		expect(fixture.clock() - askedAt).toBeCloseTo(F, 1e-9)
	end)

	it("never throws the springs on a long hitch: a quarter-second frame after a kick and a nudge", function()
		local fixture, spot = settled()
		fixture.controller.fovKick("Dash")
		fixture.controller.nudge(spot + Vector3.new(4, 0, -4), CameraData.nudge.studs)
		fixture.frame(0.25)
		for _ = 1, 60 do
			local fov = fixture.camera.FieldOfView
			expect(fov).toBeGreaterThan(REST - 1e-3)
			expect(fov).toBeLessThan(REST + CameraData.fov.dashKick + 1e-3)
			-- The nudge peaks at its studs; a thrown spring would fly past.
			expect((fixture.camera.CFrame.Position - spot).Magnitude).toBeLessThan(2 * CameraData.nudge.studs)
			fixture.frames(1)
		end
	end)
end)
