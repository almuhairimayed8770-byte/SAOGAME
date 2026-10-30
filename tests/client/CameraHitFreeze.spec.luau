--!strict
--[[
	A hit's freeze holds the shot's follow with the bodies (D-357; Studio item 300).

	The PC on 1cf87aa (Basic3 and Rising Arc kills on a locked kobold, 60 fps): through the kill's
	freeze the camera kept following until the word came: 2 frames (0.38 and 0.29 studs) at no
	lag, 3 to 5 at 50 ms, 7 to 8 (up to 0.63 studs a frame) at 100 ms. Only the kill's word held the
	shot (TargetController hands it to CameraController.holdLock, D-323); nothing held it while the
	contact's freeze waited for the word, so the follow springs went on catching up with bodies
	that had stopped. Through this path before D-357: 0.14 to 0.16 studs of camera travel on every
	frozen frame until the word.

	The path: the real CameraController (its main step and late pass in priority order), the
	fighter's rig a real Choreo animator stepped before the camera each frame as the character's
	step does, its hit-stop asked after the contact step as Replication.contact asks it, and held on
	a frame at a time while it waits for its word as Replication's holdForWords holds it. The
	contact's cue (the first frame that draws the contact pose, D-342) asks holdFollow before the
	nudge, as Replication's cue does.

	- From the cue's frame on every frame the rig is drawn held, its wait for the word included, the
	  follow and the rig's springs stand: the camera does not move.
	- The kill's word hands the shot to the still shot with no move between them.
	- A Normal hit's freeze lets the follow go once the rig is drawn moving again, and the shot
	  follows the bodies again.
	- The nudge still plays on the freeze (section 10's hold), and the follow comes back to its rest.
]]

local luau = require("@lune/luau")

local function frameSignal(): any
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
Harness.stubService("RunService", {
	RenderStepped = frameSignal(),
	Heartbeat = frameSignal(),
	PreSimulation = frameSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
local Combat = Harness.load("src/shared/data/combat")

local PATH = "src/client/camera/CameraController"
local F = 1 / 60
local ROOT = Vector3.new(0, 3, 0)
-- Moves under this are no move at all (single-precision positions some studs out).
local STILL = 1e-3

-- One clock for the camera (os.clock) and the rig (Choreo's engine clock).
local clock = 50
Choreo.configure({
	now = function(): number
		return clock
	end,
	cameraPosition = function(): Vector3?
		return Vector3.zero
	end,
})

type Step = { priority: number, fn: (dt: number) -> () }

type Fixture = {
	controller: any,
	camera: any,
	world: Instance,
	subject: Model,
	root: BasePart,
	animator: any,
	-- One 60 fps frame: `atStart` (the frame's first render step: the cues due on it), the rig's
	-- step, `afterRig` (the character's step: contacts and the wait for the word), then the
	-- camera's render steps.
	frame: (atStart: (() -> ())?, afterRig: (() -> ())?) -> (),
}

local function part(name: string, position: Vector3, size: Vector3, parent: Instance): BasePart
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.Position = position
	created.CanCollide = true
	created.Parent = parent
	return created
end

-- A character: a Model with a root part and a Humanoid.
local function character(name: string, position: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = part("HumanoidRootPart", position, Vector3.new(2, 2, 1), model)
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	model.Parent = parent
	return model
end

local function load(): Fixture
	local state = { steps = {} :: { Step } }
	local signal = {
		Connect = function() end,
	}
	local world = Instance.new("Folder")
	world.Name = "Workspace"
	local subject = character("Hero", ROOT, world)
	local root = subject.PrimaryPart :: BasePart
	local camera = {
		CFrame = CFrame.new(0, 10, 20),
		FieldOfView = 70,
		ViewportSize = Vector2.new(1920, 1080),
		CameraType = nil,
		Focus = CFrame.new(),
	}
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, _name: string, priority: number, fn: (dt: number) -> ())
				table.insert(state.steps, { priority = priority, fn = fn })
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
			LocalPlayer = { Character = subject, CharacterAdded = signal, CharacterRemoving = signal },
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
	-- No walls: the probe sees nothing.
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
			return clock
		end,
	}
	local controller = luau.load(Harness.readFile(PATH .. ".luau"), { debugName = PATH, environment = env :: any })()
	controller.start()
	-- The fighter's rig, as the character controller makes it (Choreo.get) and steps it.
	local animator = Choreo.get(subject)
	return {
		controller = controller,
		camera = camera,
		world = world,
		subject = subject,
		root = root,
		animator = animator,
		frame = function(atStart: (() -> ())?, afterRig: (() -> ())?)
			clock += F
			if atStart ~= nil then
				atStart()
			end
			animator:step(F)
			if afterRig ~= nil then
				afterRig()
			end
			for _, step in state.steps do
				step.fn(F)
			end
		end,
	}
end

-- The shot moving into a contact: a lock on a kobold 6 studs ahead, the fighter lunging and the
-- target stepping for 10 frames; the contact is found on the last of them.
local function intoContact(): (Fixture, Model)
	local fixture = load()
	for _ = 1, 60 do
		fixture.frame()
	end
	local target = character("Kobold", ROOT + Vector3.new(0, 0, -6), fixture.world)
	fixture.controller.setLockTarget(target)
	for _ = 1, 240 do
		fixture.frame()
	end
	local targetRoot = target.PrimaryPart :: BasePart
	for _ = 1, 10 do
		fixture.root.Position += Vector3.new(0, 0, -0.3)
		targetRoot.Position += Vector3.new(0.15, 0, 0)
		fixture.frame()
	end
	return fixture, target
end

-- What a hold of `tier` asks the rig for, in seconds (Replication's heldFrames: its frames less
-- the shave that keeps a frame a hair short of 1/60 from freezing one more, F6).
local function asked(tier: string): number
	return (Combat.hitStopFrames[tier] - Combat.hitStopShaveFrames) * F
end

type Run = {
	moves: { number }, -- the camera's move on each frame from the cue's frame on (studs)
	at: { Vector3 }, -- where the camera stood on it
	held: { boolean }, -- whether that frame drew the rig held
}

-- Plays a contact found on the frame before (its hit-stop of `tier` asked after that frame's
-- rig step), its cue on the next frame, and `frames` frames from the cue on. While `waitFor`
-- frames from the cue have not passed, the hold waits for its word a frame at a time (holdForWords:
-- one more step whenever what it holds would let the next one go). `onCue` and `onFrame(f)` run at
-- the start of the cue's frame and of frame f.
local function play(fixture: Fixture, tier: string, frames: number, waitFor: number, onFrame: ((f: number) -> ())?): Run
	local animator = fixture.animator
	animator:hitStop(Combat.hitStopFrames[tier] - Combat.hitStopShaveFrames)
	local run: Run = { moves = {}, at = {}, held = {} }
	local last: Vector3 = fixture.camera.CFrame.Position
	for f = 1, frames do
		fixture.frame(function()
			if f == 1 then
				-- The contact's cue: the follow holds, then the nudge (here none) would play.
				fixture.controller.holdFollow(asked(tier))
			end
			if onFrame ~= nil then
				onFrame(f)
			end
		end, function()
			if f < waitFor and animator:pauseRemaining() < F * 0.5 then
				animator:hitStop(1)
			end
		end)
		local now: Vector3 = fixture.camera.CFrame.Position
		table.insert(run.moves, (now - last).Magnitude)
		table.insert(run.at, now)
		table.insert(run.held, animator:heldShown())
		last = now
	end
	return run
end

describe("a hit's freeze holds the shot's follow with the bodies (D-357, 300)", function()
	it("holds it from the cue's frame through every held frame, the wait for the word included", function()
		for _, waitFor in { 1, 4, 8, 14 } do
			local fixture = intoContact()
			expect(typeof(fixture.controller.holdFollow)).toBe("function")
			local run = play(fixture, "Normal", waitFor + 12, waitFor)
			local heldFrames = 0
			for f, moved in run.moves do
				if f == 1 or run.held[f] then
					heldFrames += 1
					if moved > STILL then
						error(
							("word wait %d: frame %d from the cue draws the rig held, but the camera moved %.3f studs"):format(
								waitFor,
								f,
								moved
							)
						)
					end
				end
			end
			-- The Normal's own frames at least, and every frame it waited.
			expect(heldFrames >= Combat.hitStopFrames.Normal).toBe(true)
			expect(heldFrames >= waitFor).toBe(true)
		end
	end)

	it("hands over to the kill's still shot with no move between them", function()
		for _, wordAt in { 1, 3, 6, 9 } do
			local fixture = intoContact()
			local run = play(fixture, "Normal", wordAt + 30, wordAt + 1, function(f: number)
				if f == wordAt then
					-- The kill's word: TargetController hands the shot to the still shot (D-323).
					fixture.controller.holdLock(0.5)
				end
			end)
			for f, moved in run.moves do
				if moved > STILL then
					error(("word at %d: frame %d from the cue moved the camera %.3f studs"):format(wordAt, f, moved))
				end
			end
		end
	end)

	it("lets a Normal's follow go once the rig is drawn moving again, and the shot follows again", function()
		local fixture = intoContact()
		local run = play(fixture, "Normal", 14, 0)
		local lastHeld = 0
		for f, held in run.held do
			if held then
				lastHeld = f
			end
		end
		expect(lastHeld >= Combat.hitStopFrames.Normal).toBe(true)
		local after = 0
		for f = lastHeld + 1, #run.moves do
			after += run.moves[f]
		end
		-- The springs pick up where they stood: the shot settles onto the bodies again.
		expect(after > 0.05).toBe(true)
	end)

	-- A kill this client proves on the target the shot is locked on (D-358): Replication's contact
	-- cue asks the follow's hold and, lockedOn saying the shot is locked on that target, plays no
	-- nudge or shake; the word's still shot (holdLock, D-323) takes over whenever it comes. With
	-- the Kill shake and the nudge the cue gave it before, the camera moved 0.37 to 0.73 studs on
	-- each frozen frame until the word.
	it("a kill proven on the locked target stands still from its cue through the still shot (D-358)", function()
		for _, wordAt in { 1, 2, 4, 7 } do
			local fixture, target = intoContact()
			local controller = fixture.controller
			expect(typeof(controller.lockedOn)).toBe("function")
			expect(controller.lockedOn(target)).toBe(true)
			expect(controller.lockedOn(nil)).toBe(false)
			expect(controller.lockedOn(fixture.subject)).toBe(false)
			local still = controller.lockedOn(target)
			local run = play(fixture, "Kill", wordAt + 30, wordAt + 1, function(f: number)
				if f == 1 and not still then
					controller.nudge(ROOT + Vector3.new(0, 0, -4), Combat.cameraNudgeStuds)
					controller.shake("Kill")
				end
				if f == wordAt then
					controller.holdLock(0.5)
				end
			end)
			for f, moved in run.moves do
				if moved > STILL then
					error(("word at %d: frame %d from the cue moved the camera %.3f studs"):format(wordAt, f, moved))
				end
			end
		end
	end)

	it("still plays the hit's nudge on the freeze, about the follow's rest", function()
		local fixture = intoContact()
		local start: Vector3 = fixture.camera.CFrame.Position
		local run = play(fixture, "Final", 9, 0, function(f: number)
			if f == 1 then
				fixture.controller.nudge(ROOT + Vector3.new(0, 0, -4), Combat.cameraNudgeStuds)
			end
		end)
		local farthest = 0
		for f, at in run.at do
			if f == 1 or run.held[f] then
				farthest = math.max(farthest, (at - start).Magnitude)
			end
		end
		-- The nudge pushes the shot while the bodies stand, as far as section 10's nudge and no
		-- more: the follow's own catch-up waits for the freeze's end.
		expect(farthest > 0.1).toBe(true)
		expect(farthest <= Combat.cameraNudgeStuds + 1e-3).toBe(true)
	end)
end)
