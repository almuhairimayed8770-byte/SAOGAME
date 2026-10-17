--!strict
-- Locomotion.attach: the driver for rigs the local controller does not own, run through the real
-- Choreo animator on Lune Instances with an injected state tracker (no Humanoid physics in Lune).
local function fakeSignal()
	local signal = {}
	function signal:Connect()
		return { Disconnect = function() end }
	end
	return signal
end
Harness.stubService("RunService", { RenderStepped = fakeSignal(), Heartbeat = fakeSignal() })

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

local FRAME = 1 / 60
local Config = ChoreoData.locomotion

local function buildRig(rigId)
	local model = Instance.new("Model")
	model.Name = rigId
	model:SetAttribute("Rig", rigId)
	local parts = {}
	local function part(name)
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Position = Vector3.zero
		created.Parent = model
		parts[name] = created
		return created
	end
	for _, joint in Rigs[rigId].joints do
		part(joint.part0)
		local child = part(joint.part1)
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Parent = child
	end
	model.PrimaryPart = parts.HumanoidRootPart
	return model
end

local function trackerOf(state)
	return function()
		return state
	end
end

-- The driver's handle for a clip (the animator's own fallback idle shares the idle's clip id).
local function handleOf(animator, clipId)
	for _, handle in animator.mixer:handles() do
		if handle.clipId == clipId and not handle.stopping and not handle.fallback then
			return handle
		end
	end
	return nil
end

local function still()
	return { moveDir = Vector3.zero, speed = 0, sprinting = false, grounded = true, turning = 0 }
end

describe("Locomotion.attach", function()
	it("crossfades an enemy rig from its idle to its walk by speed and paces the walk to the rig", function()
		local model = buildRig("Boar")
		local animator = Choreo.get(model)
		local state = still()
		local driver = Locomotion.attach(animator, model, { tracker = trackerOf(state) })
		animator:step(FRAME)
		local idle = handleOf(animator, ChoreoData.rigs.Boar.idle)
		local walk = handleOf(animator, ChoreoData.rigs.Boar.walk)
		expect(walk).toBeTruthy()
		expect(walk.weight).toBe(0)
		expect(idle.weight).toBe(1)

		local walkSpeed = Rigs.Boar.walkSpeed
		state.speed = walkSpeed / 2
		for _ = 1, 60 do
			animator:step(FRAME)
		end
		expect(walk.weight).toBeCloseTo(0.5, 1e-6)
		expect(walk.speed).toBeCloseTo(0.5, 1e-6)

		state.speed = walkSpeed * 2
		for _ = 1, 60 do
			animator:step(FRAME)
		end
		expect(walk.weight).toBeCloseTo(1, 1e-6)
		expect(walk.speed).toBeCloseTo(2, 1e-6)
		expect(animator:isPlaying(ChoreoData.rigs.Boar.walk)).toBe(true)

		driver:destroy()
		animator:step(FRAME)
		expect(animator:isPlaying(ChoreoData.rigs.Boar.walk)).toBe(false)
		Choreo.release(model)
	end)

	it("runs the full blend space on a remote player rig and skips frames with no state", function()
		local model = buildRig("PlayerR15")
		local animator = Choreo.get(model)
		local state = still()
		local present = true
		local driver = Locomotion.attach(animator, model, {
			footIK = false,
			tracker = function()
				return if present then state else nil
			end,
		})
		animator:step(FRAME)
		local run = handleOf(animator, Config.clipPrefix .. Config.clips.Run)
		expect(run).toBeTruthy()
		state.speed = Config.runSpeed
		state.moveDir = Vector3.new(0, 0, -1)
		for _ = 1, 30 do
			animator:step(FRAME)
		end
		expect(run.weight).toBeCloseTo(1, 1e-6)
		present = false
		state.speed = 0
		for _ = 1, 30 do
			animator:step(FRAME)
		end
		expect(run.weight).toBeCloseTo(1, 1e-6)
		driver:destroy()
		Choreo.release(model)
	end)

	it("the animator's own destroy drops the hook", function()
		local model = buildRig("Kobold")
		local animator = Choreo.get(model)
		local calls = 0
		Locomotion.attach(animator, model, {
			tracker = function()
				calls += 1
				return nil
			end,
		})
		animator:step(FRAME)
		expect(calls).toBe(1)
		Choreo.release(model)
		animator:step(FRAME)
		expect(calls).toBe(1)
	end)
end)
