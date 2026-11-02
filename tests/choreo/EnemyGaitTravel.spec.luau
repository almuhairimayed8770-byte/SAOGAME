--!strict
--[[
	An enemy rig's gait is paced by its root's own travel (D-575; AO 473(a), (e)): the replicated
	AssemblyLinearVelocity under-reads the root's move (AH 401(c)), and a walk paced short of the
	root slides its planted feet by the gap every row. Locomotion.travelTracker hands on its
	source's state with the flat speed, velocity and move direction of the root's travel over the
	last choreo.enemy.gait.travelSeconds; a step past enemy.rush.teleportStuds (a placement) starts
	it afresh; a frame with no time keeps it. Locomotion.attach gives every enemy rig it by default,
	over the Humanoid tracker; a tracker passed in still wins, and the drawn rush's own tracker
	(drawnTracker) still overrides it while a body offset is drawn.
]]
local function fakeSignal()
	local signal = {}
	function signal:Connect()
		return { Disconnect = function() end }
	end
	return signal
end
Harness.stubService("RunService", {
	RenderStepped = fakeSignal(),
	Heartbeat = fakeSignal(),
	PreSimulation = fakeSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
Choreo.configure({
	now = function()
		return 0
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local RigBuilder = Harness.load("src/server/world/RigBuilder")

local FRAME = 1 / 60
-- Vector3 holds single floats: a speed over a 0.05 s window carries about 1e-4 of their rounding.
local CLOSE = 2e-3
local WINDOW = ChoreoData.enemy.gait.travelSeconds
local TELEPORT = ChoreoData.enemy.rush.teleportStuds

local function rootOnly(): (Model, BasePart)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(0, 3, 0)
	root.Position = root.CFrame.Position
	root.Parent = model
	model.PrimaryPart = root
	return model, root
end

-- The Humanoid tracker's reading: a velocity at `share` of the root's real one.
local function reading(velocity: Vector3): any
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	return {
		moveDir = if flat.Magnitude > 0 then flat.Unit else Vector3.zero,
		speed = flat.Magnitude,
		sprinting = false,
		grounded = true,
		drawn = false,
		turning = 0,
		verticalVelocity = velocity.Y,
		velocity = velocity,
	}
end

describe("Locomotion.travelTracker: an enemy gait paced by its root's travel (D-575)", function()
	it("reads the root's flat travel over the window, not the velocity it is told", function()
		local model, root = rootOnly()
		local told = Vector3.new(7, 0, 0) -- half of what the root really does
		local tracker = Locomotion.travelTracker(model, function()
			return reading(told)
		end)
		-- The first frame has no travel yet: the source's own reading stands.
		local first = tracker(FRAME)
		expect(first.speed).toBeCloseTo(7, 1e-9)
		local frames = math.ceil(WINDOW / FRAME) + 3
		local state
		for _ = 1, frames do
			root.CFrame += Vector3.new(14 * FRAME, 0.05, 0) -- a hair of rise is not travel
			state = tracker(FRAME)
		end
		expect(state.speed).toBeCloseTo(14, CLOSE)
		expect(state.velocity.X).toBeCloseTo(14, CLOSE)
		expect(state.velocity.Y).toBe(0) -- the told vertical velocity is kept
		expect(state.moveDir.X).toBeCloseTo(1, 1e-6)
		expect(state.grounded).toBe(true)
	end)

	it("averages uneven rows over the window: a root stepping 0.2 then 0 a row reads its mean", function()
		local model, root = rootOnly()
		local tracker = Locomotion.travelTracker(model, function()
			return reading(Vector3.zero)
		end)
		tracker(FRAME)
		local speeds = {}
		for row = 1, 12 do
			if row % 2 == 1 then
				root.CFrame += Vector3.new(0, 0, 0.2)
			end
			local state = tracker(FRAME)
			if row > 6 then
				table.insert(speeds, state.speed)
			end
		end
		-- 0.1 a 60 Hz row is 6 studs/s; a window of an odd number of rows reads within a row's step of it.
		for _, speed in speeds do
			expect(math.abs(speed - 6)).toBeLessThanOrEqual(0.2 / WINDOW / 2 + CLOSE)
		end
	end)

	it("follows a change of pace within the window", function()
		local model, root = rootOnly()
		local tracker = Locomotion.travelTracker(model, function()
			return reading(Vector3.zero)
		end)
		tracker(FRAME)
		for _ = 1, 10 do
			root.CFrame += Vector3.new(7 * FRAME, 0, 0)
			tracker(FRAME)
		end
		local state
		for _ = 1, math.ceil(WINDOW / FRAME + 1e-6) do
			root.CFrame += Vector3.new(14 * FRAME, 0, 0)
			state = tracker(FRAME)
		end
		expect(state.speed).toBeCloseTo(14, CLOSE)
	end)

	it("starts afresh after a placement and never reads it as a run", function()
		local model, root = rootOnly()
		local tracker = Locomotion.travelTracker(model, function()
			return reading(Vector3.new(3, 0, 0))
		end)
		tracker(FRAME)
		for _ = 1, 5 do
			root.CFrame += Vector3.new(3 * FRAME, 0, 0)
			tracker(FRAME)
		end
		root.CFrame += Vector3.new(0, 0, TELEPORT + 0.5)
		local placed = tracker(FRAME)
		expect(placed.speed).toBeCloseTo(3, CLOSE) -- the source's own reading, not 270 studs/s
		root.CFrame += Vector3.new(3 * FRAME, 0, 0)
		local after = tracker(FRAME)
		expect(after.speed).toBeCloseTo(3, CLOSE)
		-- A step just within teleportStuds is travel.
		local model2, root2 = rootOnly()
		local tracker2 = Locomotion.travelTracker(model2, function()
			return reading(Vector3.zero)
		end)
		tracker2(FRAME)
		root2.CFrame += Vector3.new(TELEPORT - 0.01, 0, 0)
		expect(tracker2(FRAME).speed).toBeCloseTo((TELEPORT - 0.01) / FRAME, CLOSE)
	end)

	it("keeps its travel through frames with no time and hands on a missing state", function()
		local model, root = rootOnly()
		local present = true
		local tracker = Locomotion.travelTracker(model, function()
			return if present then reading(Vector3.zero) else nil
		end)
		tracker(FRAME)
		for _ = 1, 5 do
			root.CFrame += Vector3.new(10 * FRAME, 0, 0)
			tracker(FRAME)
		end
		for _ = 1, 200 do
			expect(tracker(0).speed).toBeCloseTo(10, CLOSE)
		end
		present = false
		expect(tracker(FRAME)).toBe(nil)
		present = true
		-- After a gap with no state the travel starts afresh.
		root.CFrame += Vector3.new(50, 0, 0)
		expect(tracker(FRAME).speed).toBe(0)
	end)
end)

describe("Locomotion.attach: an enemy rig's walk paced by its root's travel (D-575)", function()
	local function walkOf(animator: any, rig: string): any
		for _, handle in animator.mixer:handles() do
			if handle.clipId == ChoreoData.rigs[rig].walk and not handle.stopping and not handle.fallback then
				return handle
			end
		end
		return nil
	end

	for _, rig in { "Boar", "Kobold" } do
		it(("plays the %s's walk at the rate of its root's travel when the velocity reads half"):format(rig), function()
			local model = RigBuilder.build(rig)
			local root = model.PrimaryPart :: BasePart
			root.Position = root.CFrame.Position
			local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
			humanoid.FloorMaterial = Enum.Material.Plastic
			local animator = Choreo.get(model)
			local driver = Locomotion.attach(animator, model, { phase = 0 })
			local walkSpeed = Rigs[rig].walkSpeed
			for _ = 1, 30 do
				root.CFrame += Vector3.new(0, 0, walkSpeed * FRAME)
				root.Position = root.CFrame.Position
				root.AssemblyLinearVelocity = Vector3.new(0, 0, walkSpeed / 2)
				humanoid.MoveDirection = Vector3.new(0, 0, 1)
				animator:step(FRAME)
			end
			local walk = walkOf(animator, rig)
			expect(walk).toBeTruthy()
			expect(walk.speed).toBeCloseTo(1, CLOSE)
			expect(walk.targetWeight).toBeCloseTo(1, 1e-6)
			driver:destroy()
			Choreo.release(model)
		end)
	end

	it("keeps a tracker passed in", function()
		local model = RigBuilder.build("Boar")
		local root = model.PrimaryPart :: BasePart
		root.Position = root.CFrame.Position
		local animator = Choreo.get(model)
		local told = reading(Vector3.new(0, 0, 7))
		local driver = Locomotion.attach(animator, model, {
			phase = 0,
			tracker = function()
				return told
			end,
		})
		for _ = 1, 30 do
			root.CFrame += Vector3.new(0, 0, 14 * FRAME)
			root.Position = root.CFrame.Position
			animator:step(FRAME)
		end
		expect(walkOf(animator, "Boar").speed).toBeCloseTo(0.5, CLOSE)
		driver:destroy()
		Choreo.release(model)
	end)
end)
