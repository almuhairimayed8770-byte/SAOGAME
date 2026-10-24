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

type Step = { name: string, priority: number, fn: (dt: number) -> () }

type Fixture = {
	controller: any,
	camera: any,
	-- Moves the clock `seconds` and runs one frame's render steps (in priority order) reporting
	-- `dt` (`seconds` when nil). `between`, when given, runs once inside the frame just before the
	-- first step bound above `after` (a priority): a contact made at render priority 301 is
	-- `after = 301`, one made before the frame (the network) `after = -1`.
	frame: (seconds: number, dt: number?, after: number?, between: (() -> ())?) -> (),
	-- Runs `count` 60 fps frames.
	frames: (count: number) -> (),
	clock: () -> number,
	-- The render steps the controller bound, in priority order.
	steps: { Step },
}

-- Enum.RenderPriority values the controller binds against.
local CAMERA_PRIORITY = 200
local CHARACTER_PRIORITY = 301

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
				if options ~= nil and options.withoutLate and priority > CAMERA_PRIORITY then
					return -- the controller as it was: one step at Camera priority
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

-- A nudge and a shake asked for on a frame. `after` is where in the frame (a render priority; -1
-- before the frame's steps), and the run goes on for `count` frames after it. Returns the camera
-- CFrame of every frame from the asking one.
local function hitAt(fixture: Fixture, spot: Vector3, after: number, count: number, nudgeOnly: boolean?): { CFrame }
	local shown: { CFrame } = {}
	fixture.frame(F, nil, after, function()
		fixture.controller.nudge(spot + Vector3.new(4, 0, -4), CameraData.nudge.studs)
		if not nudgeOnly then
			fixture.controller.shake("Kill")
		end
	end)
	table.insert(shown, fixture.camera.CFrame)
	for _ = 1, count do
		fixture.frames(1)
		table.insert(shown, fixture.camera.CFrame)
	end
	return shown
end

-- Whether two runs drew the same frames: every position and view direction within `epsilon`
-- (0: the very same numbers).
local function sameFrames(a: { CFrame }, b: { CFrame }, epsilon: number): boolean
	for index, frame in a do
		local other = b[index]
		local moved = frame.Position - other.Position
		local turned = frame.LookVector - other.LookVector
		for _, gap in { moved.X, moved.Y, moved.Z, turned.X, turned.Y, turned.Z } do
			if math.abs(gap) > epsilon then
				return false
			end
		end
	end
	return true
end

describe("CameraController on the contact frame (D-180)", function()
	it("shows a nudge and a shake asked for after its step (the contact, at 301) on that same frame", function()
		local before, spot = settled()
		-- The frames the hit gives when it is asked for before the camera steps: the reference.
		local reference = hitAt(before, spot, -1, 30)
		local contact = settled()
		local shown = hitAt(contact, spot, CHARACTER_PRIORITY, 30)
		-- The contact frame already moves, and every frame matches the reference.
		expect((shown[1].Position - spot).Magnitude).toBeGreaterThan(0.05)
		expect(sameFrames(shown, reference, 1e-6)).toBe(true)
		-- The camera's own step at 200 had drawn the frame without them.
		expect(contact.steps[1].priority).toBe(CAMERA_PRIORITY)
		expect(#contact.steps).toBe(2)
		expect(contact.steps[2].priority).toBeGreaterThan(CHARACTER_PRIORITY)
	end)

	it("shows only the shake on the contact frame when no nudge comes with it", function()
		local fixture, spot = settled()
		fixture.frame(F, nil, CHARACTER_PRIORITY, function()
			fixture.controller.shake("Final")
		end)
		local moved = (fixture.camera.CFrame.Position - spot).Magnitude
		expect(moved).toBeGreaterThan(0)
		expect(moved).toBeLessThanOrEqual(CameraData.shake.amplitude.Final + 1e-6)
	end)

	it("changes nothing on frames whose hits came before its step: the same frames as one step alone", function()
		local late, spot = settled()
		local alone = settled({ withoutLate = true })
		expect(#alone.steps).toBe(1)
		local a = hitAt(late, spot, -1, 40)
		local b = hitAt(alone, spot, -1, 40)
		expect(sameFrames(a, b, 0)).toBe(true)
		-- And frames with no hit at all.
		local quiet: { CFrame } = {}
		local quietAlone: { CFrame } = {}
		for _ = 1, 30 do
			late.frames(1)
			alone.frames(1)
			table.insert(quiet, late.camera.CFrame)
			table.insert(quietAlone, alone.camera.CFrame)
		end
		expect(sameFrames(quiet, quietAlone, 0)).toBe(true)
	end)

	it("plays a late nudge out exactly as the old one-step camera did, one frame sooner", function()
		local late, spot = settled()
		local alone = settled({ withoutLate = true })
		local a = hitAt(late, spot, CHARACTER_PRIORITY, 30, true)
		local b = hitAt(alone, spot, CHARACTER_PRIORITY, 31, true)
		-- The one-step camera showed nothing on the contact frame and the nudge from the next one.
		expect((b[1].Position - spot).Magnitude).toBeLessThan(1e-9)
		local shifted = table.move(b, 2, #b, 1, {})
		expect(sameFrames(a, shifted, 1e-4)).toBe(true)
	end)

	it("lets a hit asked for between frames (the network) show on the next frame, as before", function()
		local late, spot = settled()
		local alone = settled({ withoutLate = true })
		-- After the frame's steps (and its late pass): nothing is drawn until the next frame.
		local a = hitAt(late, spot, 1e9, 20)
		local b = hitAt(alone, spot, 1e9, 20)
		expect(sameFrames(a, b, 0)).toBe(true)
	end)

	it("never replays a late hit after a render stall: the 55 s gap snaps it out", function()
		local fixture, spot = settled()
		fixture.frame(55, F, CHARACTER_PRIORITY, function()
			fixture.controller.nudge(spot + Vector3.new(4, 0, -4), CameraData.nudge.studs)
		end)
		-- The stalled frame settles every spring: the nudge asked for in it is gone with them.
		expect((fixture.camera.CFrame.Position - spot).Magnitude).toBeLessThan(1e-3)
		for _ = 1, 20 do
			fixture.frames(1)
			expect((fixture.camera.CFrame.Position - spot).Magnitude).toBeLessThan(1e-3)
		end
	end)
end)
