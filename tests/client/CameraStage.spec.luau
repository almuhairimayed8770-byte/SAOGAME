--!strict
--[[
	The capture's staged views (F12): CameraMath.stageAnchor / stageReference and
	CameraController.setStage, loaded fresh with a fake engine around it (a fake RunService that
	hands the render steps to the spec, a fake clock, a plain camera table, real Lune instances for
	the fighters and no walls).

	Each gate shot frames its move from where it reads: a side view across the line for the Arts
	and the kill, a three-quarter view behind the player for the overhead and the parry, a view
	from behind the boar's tail for its charge (one that pans, never whips, as the boar runs past
	and turns), and a fixed side view of the open run for the locomotion pass. The staged view
	wins over the lock's two-shot, keeps a target that died where it last stood, and eases on and
	off like the lock does.
]]

local luau = require("@lune/luau")

local CameraData = Harness.load("src/shared/data/camera")
local CameraMath = Harness.load("src/client/camera/CameraMath")
local Dev = Harness.load("src/shared/data/dev")

local PATH = "src/client/camera/CameraController"
local F = 1 / 60
local ROOT = Vector3.new(0, 3, 0)
local CAMERAS = Dev.capture.cameras

type Fixture = {
	controller: any,
	camera: any,
	world: Instance,
	subject: Model,
	root: BasePart,
	frames: (count: number) -> (),
	clock: () -> number,
}

-- Lune keeps a part's Position and CFrame apart: set both.
local function place(part: BasePart, frame: CFrame)
	part.CFrame = frame
	part.Position = frame.Position
end

local function character(name: string, position: Vector3, parent: Instance, facing: number?): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	place(root, CFrame.new(position) * CFrame.Angles(0, math.rad(facing or 0), 0))
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	model.Parent = parent
	return model
end

local function load(): Fixture
	local state = { clock = 50, steps = {} :: { { priority: number, fn: (dt: number) -> () } } }
	local signal = { Connect = function() end }
	local world = Instance.new("Folder")
	world.Name = "Workspace"
	local subject = character("Hero", ROOT, world)
	local root = subject.PrimaryPart :: BasePart
	local camera = { CFrame = CFrame.new(0, 10, 20), FieldOfView = 70, CameraType = nil, Focus = CFrame.new() }
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, _name: string, priority: number, fn: (dt: number) -> ())
				table.insert(state.steps, { priority = priority, fn = fn })
				table.sort(state.steps, function(a, b)
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
		Players = { LocalPlayer = { Character = subject, CharacterAdded = signal, CharacterRemoving = signal } },
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
			return nil
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
	return {
		controller = controller,
		camera = camera,
		world = world,
		subject = subject,
		root = root,
		frames = function(count: number)
			for _ = 1, count do
				state.clock += F
				for _, step in state.steps do
					step.fn(F)
				end
			end
		end,
		clock = function(): number
			return state.clock
		end,
	}
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The flat angle in degrees between two directions.
local function angleBetween(a: Vector3, b: Vector3): number
	local fa, fb = flat(a).Unit, flat(b).Unit
	return math.deg(math.acos(math.clamp(fa:Dot(fb), -1, 1)))
end

-- Where a world point lands on screen: x and y in [-1, 1] inside the frame (16:9, the FOV vertical).
local function onScreen(camera: any, point: Vector3): (number, number, number)
	local frame: CFrame = camera.CFrame
	local local_ = frame:PointToObjectSpace(point)
	local depth = -local_.Z
	local half = math.tan(math.rad(camera.FieldOfView) / 2)
	return local_.X / (depth * half * 16 / 9), local_.Y / (depth * half), depth
end

local function bearingOf(from: Vector3, at: Vector3): number
	return CameraMath.yawTowards({ at.X, at.Y, at.Z }, { from.X, from.Y, from.Z })
end

-- ------------------------------------------------------------------ the pure math

describe("CameraMath stage views (F12)", function()
	local player = { 0, 3, 0 }
	local target = { 0, 2, -4 }

	it("anchors on the player, the target or halfway, and on the player alone with no target", function()
		expect(CameraMath.stageAnchor("Player", player, target)).toEqual({ 0, 3, 0 })
		expect(CameraMath.stageAnchor("Target", player, target)).toEqual({ 0, 2, -4 })
		expect(CameraMath.stageAnchor("Middle", player, target)).toEqual({ 0, 2.5, -2 })
		expect(CameraMath.stageAnchor("Target", player, nil)).toEqual({ 0, 3, 0 })
		expect(CameraMath.stageAnchor("Middle", player, nil)).toEqual({ 0, 3, 0 })
	end)

	it("Line puts 0 behind the anchor on the line from the other fighter", function()
		-- The target at -Z of the player: behind the player is +Z (bearing 0).
		expect(CameraMath.stageReference("Line", "Player", player, target, nil)).toBeCloseTo(0, 1e-9)
		expect(CameraMath.stageReference("Line", "Middle", player, target, nil)).toBeCloseTo(0, 1e-9)
		-- Behind the target, on the line from the player: -Z of the target (bearing 180).
		expect(math.abs(CameraMath.stageReference("Line", "Target", player, target, nil))).toBeCloseTo(180, 1e-9)
		-- No target, no line.
		expect(CameraMath.stageReference("Line", "Player", player, nil, nil)).toBeNil()
	end)

	it("Facing puts 0 behind the anchor's own look, and World is the bearing itself", function()
		-- A rig looking along -X: behind it is +X, bearing 90.
		expect(CameraMath.stageReference("Facing", "Target", player, target, { -1, 0, 0 })).toBeCloseTo(90, 1e-9)
		expect(CameraMath.stageReference("Facing", "Player", player, target, { 0, 0, -1 })).toBeCloseTo(0, 1e-9)
		expect(CameraMath.stageReference("Facing", "Player", player, target, { 0, 1, 0 })).toBeNil()
		expect(CameraMath.stageReference("Facing", "Player", player, target, nil)).toBeNil()
		expect(CameraMath.stageReference("World", "Player", player, nil, nil)).toBe(0)
	end)
end)

-- ------------------------------------------------------------------ the controller

describe("CameraController staged views (F12)", function()
	it("Side stands across the line, on the player's right with side 1, both fighters in frame", function()
		local fixture = load()
		local kobold = character("Kobold", ROOT + Vector3.new(0, 0, -3.5), fixture.world, 180)
		fixture.controller.setStage(CAMERAS.Side, kobold, 1)
		fixture.frames(120)
		local position: Vector3 = fixture.camera.CFrame.Position
		local middle = (ROOT + kobold.PrimaryPart.Position) / 2
		-- Square to the line, on +X (the right of a player facing the target along -Z).
		expect(angleBetween(position - middle, Vector3.new(1, 0, 0))).toBeLessThan(2)
		expect(flat(position - middle).Magnitude).toBeCloseTo(CAMERAS.Side.distance, 0.2)
		for _, point in { ROOT, kobold.PrimaryPart.Position } do
			local x, y, depth = onScreen(fixture.camera, point)
			expect(depth).toBeGreaterThan(0)
			expect(math.abs(x)).toBeLessThan(0.6)
			expect(math.abs(y)).toBeLessThan(0.6)
		end
		-- Side -1 is the other side of the line.
		fixture.controller.setStage(CAMERAS.Side, kobold, -1)
		fixture.frames(240)
		expect(angleBetween(fixture.camera.CFrame.Position - middle, Vector3.new(-1, 0, 0))).toBeLessThan(2)
	end)

	it("ThreeQuarter stands behind the player, its degrees off the line", function()
		local fixture = load()
		local kobold = character("Kobold", ROOT + Vector3.new(0, 0, -4.5), fixture.world, 180)
		fixture.controller.setStage(CAMERAS.ThreeQuarter, kobold, 1)
		fixture.frames(120)
		local position: Vector3 = fixture.camera.CFrame.Position
		expect(angleBetween(position - ROOT, Vector3.new(0, 0, 1))).toBeCloseTo(CAMERAS.ThreeQuarter.degrees, 1)
		expect(position.X).toBeGreaterThan(0)
		for _, point in { ROOT, kobold.PrimaryPart.Position } do
			local x, _, depth = onScreen(fixture.camera, point)
			expect(depth).toBeGreaterThan(0)
			expect(math.abs(x)).toBeLessThan(0.6)
		end
	end)

	it("never aims nearer the lens than its anchor: a target that runs to the camera's side", function()
		local fixture = load()
		local kobold = character("Kobold", ROOT + Vector3.new(0, 0, -4.5), fixture.world, 180)
		fixture.controller.setStage(CAMERAS.ThreeQuarter, kobold, 1)
		fixture.frames(120)
		-- The kobold darts past the player to stand a stud short of the camera.
		local toCamera = flat(fixture.camera.CFrame.Position - ROOT)
		place(kobold.PrimaryPart :: BasePart, CFrame.new(ROOT + toCamera.Unit * (toCamera.Magnitude - 1)))
		for _ = 1, 30 do
			fixture.frames(1)
			local frame: CFrame = fixture.camera.CFrame
			local view = flat(frame.LookVector).Unit
			local aimDepth = flat(fixture.camera.Focus.Position - frame.Position):Dot(view)
			local playerDepth = flat(ROOT - frame.Position):Dot(view)
			expect(aimDepth).toBeGreaterThan(playerDepth - 0.05)
		end
	end)

	it("wins over the lock's two-shot while it is set, and gives the shot back to the lock after", function()
		local fixture = load()
		local kobold = character("Kobold", ROOT + Vector3.new(0, 0, -3.5), fixture.world, 180)
		fixture.controller.setLockTarget(kobold)
		fixture.controller.setStage(CAMERAS.Side, kobold, 1)
		fixture.frames(120)
		local middle = (ROOT + kobold.PrimaryPart.Position) / 2
		expect(angleBetween(fixture.camera.CFrame.Position - middle, Vector3.new(1, 0, 0))).toBeLessThan(2)
		fixture.controller.setStage(nil)
		fixture.frames(240)
		-- Back on the two-shot: behind the player, under its widest swing off the line.
		local offLine = angleBetween(fixture.camera.CFrame.Position - ROOT, Vector3.new(0, 0, 1))
		expect(offLine).toBeLessThan(CameraData.lock.closeSwingDegrees + 1)
	end)

	it("Behind follows the boar from its tail and pans, never whips, as it runs past and turns", function()
		local fixture = load()
		-- The boar 18 studs out along -Z, facing the player (+Z).
		local boar = character("Boar", ROOT + Vector3.new(0, 0, -18), fixture.world, 180)
		local boarRoot = boar.PrimaryPart :: BasePart
		fixture.controller.setStage(CAMERAS.Behind, boar, 1)
		fixture.frames(120)
		local position: Vector3 = fixture.camera.CFrame.Position
		-- Behind the tail: further from the player than the boar, within the view's degrees of its back.
		expect(angleBetween(position - boarRoot.Position, -boarRoot.CFrame.LookVector)).toBeCloseTo(
			CAMERAS.Behind.degrees,
			1
		)
		local _, _, depth = onScreen(fixture.camera, boarRoot.Position)
		expect(depth).toBeGreaterThan(0)
		-- The rush: 30 studs along +Z in 1 s, through the player, then the turn back (180 degrees
		-- in 0.3 s). The camera's bearing around the boar never turns faster than the cap.
		local cap = CameraData.lock.maxTurnDegreesPerSecond
		local last = bearingOf(fixture.camera.CFrame.Position, boarRoot.Position)
		local worst = 0
		local start = boarRoot.Position
		for frame = 1, 120 do
			if frame <= 60 then
				place(boarRoot, CFrame.new(start + Vector3.new(0, 0, 30 * frame / 60)) * boarRoot.CFrame.Rotation)
			elseif frame <= 78 then
				place(
					boarRoot,
					CFrame.new(boarRoot.Position) * CFrame.Angles(0, math.rad(10), 0) * boarRoot.CFrame.Rotation
				)
			end
			fixture.frames(1)
			local now = bearingOf(fixture.camera.CFrame.Position, boarRoot.Position)
			worst = math.max(worst, math.abs(CameraMath.shortestDelta(last, now)) / F)
			last = now
			-- The aim never comes in under the lens: the boar stays ahead of the camera.
			local _, _, ahead = onScreen(fixture.camera, boarRoot.Position)
			expect(ahead).toBeGreaterThan(0)
		end
		-- The follow spring's lag lets the measured bearing run a little past the cap.
		expect(worst).toBeLessThan(cap * 1.25)
	end)

	it("Open watches the run from the player's +X, so a run along -Z crosses the screen", function()
		local fixture = load()
		fixture.controller.setStage(CAMERAS.Open, nil, 1)
		fixture.frames(120)
		local position: Vector3 = fixture.camera.CFrame.Position
		expect(angleBetween(position - ROOT, Vector3.new(1, 0, 0))).toBeLessThan(1)
		expect(flat(position - ROOT).Magnitude).toBeCloseTo(CAMERAS.Open.distance, 0.2)
		-- The camera's right is -Z: a run that way goes to screen right.
		expect(fixture.camera.CFrame.RightVector:Dot(Vector3.new(0, 0, -1))).toBeGreaterThan(0.99)
		-- The run: 20 studs a second for 2 s, the player framed all the way.
		for frame = 1, 120 do
			place(fixture.root, CFrame.new(ROOT + Vector3.new(0, 0, -20 * frame / 60)))
			fixture.frames(1)
			local x, y, depth = onScreen(fixture.camera, fixture.root.Position)
			expect(depth).toBeGreaterThan(0)
			expect(math.abs(x)).toBeLessThan(0.5)
			expect(math.abs(y)).toBeLessThan(0.5)
		end
		-- A 6-stud fall stays in the frame.
		for _ = 1, 30 do
			place(fixture.root, CFrame.new(fixture.root.Position - Vector3.new(0, 6 / 30, 0)))
			fixture.frames(1)
			local _, y = onScreen(fixture.camera, fixture.root.Position)
			expect(math.abs(y)).toBeLessThan(0.7)
		end
	end)

	it("keeps a target that died where it last stood (the kill's shatter)", function()
		local fixture = load()
		local kobold = character("Kobold", ROOT + Vector3.new(0, 0, -3.5), fixture.world, 180)
		fixture.controller.setStage(CAMERAS.Side, kobold, 1)
		fixture.frames(120)
		local before: CFrame = fixture.camera.CFrame
		kobold.Parent = nil
		kobold:Destroy()
		fixture.frames(60)
		local after: CFrame = fixture.camera.CFrame
		expect((after.Position - before.Position).Magnitude).toBeLessThan(1e-3)
		expect(after.LookVector:Dot(before.LookVector)).toBeGreaterThan(0.9999)
	end)

	it("eases on and off: no frame jumps the camera", function()
		local fixture = load()
		local kobold = character("Kobold", ROOT + Vector3.new(0, 0, -3.5), fixture.world, 180)
		fixture.frames(60)
		local last: Vector3 = fixture.camera.CFrame.Position
		local worst = 0
		local function run(count: number)
			for _ = 1, count do
				fixture.frames(1)
				local position: Vector3 = fixture.camera.CFrame.Position
				worst = math.max(worst, (position - last).Magnitude)
				last = position
			end
		end
		fixture.controller.setStage(CAMERAS.Side, kobold, 1)
		run(120)
		fixture.controller.setStage(nil)
		run(120)
		-- About 15 studs between the follow and the side view, eased over the blend's lag: no
		-- single frame carries more than a fraction of it.
		expect(worst).toBeLessThan(2)
	end)
end)

describe("CameraController staged views and the lock's stick (D-238)", function()
	it("leaves the stick alone while a staged view holds the camera, even under a live lock", function()
		local fixture = load()
		-- A kobold ahead and to the right: the lock's frame is not the camera's.
		local kobold = character("Kobold", ROOT + Vector3.new(4, 0, -3), fixture.world, 180)
		fixture.controller.setLockTarget(kobold)
		fixture.frames(60)
		local stick = Vector3.new(0.6, 0, -0.8)
		-- Unstaged, the live lock turns the stick into its frame.
		expect((fixture.controller.lockMove(stick) - stick).Magnitude).toBeGreaterThan(0.05)
		-- Staged (the locomotion pass locks on under the fixed Open view), the keys walk the way
		-- the staged view shows them.
		fixture.controller.setStage(CAMERAS.Open, nil, 1)
		fixture.frames(60)
		expect((fixture.controller.lockMove(stick) - stick).Magnitude).toBeLessThan(1e-9)
		fixture.controller.setStage(CAMERAS.Side, kobold, 1)
		fixture.frames(60)
		expect((fixture.controller.lockMove(stick) - stick).Magnitude).toBeLessThan(1e-9)
		-- The stage gone, the lock's frame is back.
		fixture.controller.setStage(nil)
		fixture.frames(60)
		expect((fixture.controller.lockMove(stick) - stick).Magnitude).toBeGreaterThan(0.05)
	end)
end)
