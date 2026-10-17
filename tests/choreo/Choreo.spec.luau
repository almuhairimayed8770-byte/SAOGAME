-- A minimal RBXScriptSignal stand-in for RunService frame signals: Connect returns a connection
-- with Disconnect; Fire runs the handlers in order.
local function fakeSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(handler)
		local record = { handler = handler, Connected = true }
		table.insert(handlers, record)
		return {
			Disconnect = function()
				record.Connected = false
				local index = table.find(handlers, record)
				if index then
					table.remove(handlers, index)
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, record in table.clone(handlers) do
			if record.Connected then
				record.handler(...)
			end
		end
	end
	return signal
end

local renderStepped = fakeSignal()
local heartbeat = fakeSignal()
Harness.stubService("RunService", { RenderStepped = renderStepped, Heartbeat = heartbeat })

local Choreo = Harness.load("src/client/choreo/Choreo")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Combat = Harness.load("src/shared/data/combat")
local Rigs = Harness.load("src/shared/data/rigs")

local FRAME = 1 / 60
local HORIZONTAL = "player/OneHandedSword/Horizontal"
local GUARD = "player/OneHandedSword/Guard"
local HIT_OPEN_TIME = 0.36 -- the Horizontal clip's first HitWindowOpen

local clock = 0
local camera = Vector3.zero
Choreo.configure({
	now = function()
		return clock
	end,
	cameraPosition = function()
		return camera
	end,
})

-- Builds a model with one Part per rig part and one Motor6D per rig joint, named like the data.
local function buildRig(rigId, position)
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
		created.Position = position or Vector3.zero
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

-- The Motor6D with this joint name (a Part may share the name, as the Weapon does).
local function motorOf(model, name)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

local function eventKinds(animator)
	local kinds = {}
	animator.events:Connect(function(_clipId, event)
		table.insert(kinds, event.kind)
	end)
	return kinds
end

local function count(list, value)
	local total = 0
	for _, item in list do
		if item == value then
			total += 1
		end
	end
	return total
end

describe("Choreo", function()
	it("registers a rig and poses it the same frame: idle and breathing play, no joint is left at rest", function()
		local model = buildRig("PlayerR15")
		local animator = Choreo.get(model)
		expect(animator.rigId).toBe("PlayerR15")
		expect(Choreo.get(model)).toBe(animator)
		expect(Choreo.find(model)).toBe(animator)
		expect(Choreo.count()).toBe(1)
		expect(animator:isPlaying(ChoreoData.rigs.PlayerR15.idle)).toBe(true)
		expect(animator:isPlaying(ChoreoData.rigs.PlayerR15.breathing)).toBe(true)
		expect(motorOf(model, "Weapon").Transform == CFrame.identity).toBe(false)
		expect(motorOf(model, "RightShoulder").Transform == CFrame.identity).toBe(false)
		expect(typeof(animator:currentRootMotionDelta())).toBe("Vector3")
		Choreo.release(model)
		expect(Choreo.find(model)).toBeNil()
		expect(Choreo.count()).toBe(0)
	end)

	it("a Humanoid model without a Rig attribute is a PlayerR15; a bare model is an error", function()
		local model = Instance.new("Model")
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
		local animator = Choreo.get(model)
		expect(animator.rigId).toBe("PlayerR15")
		Choreo.release(model)
		expect(function()
			Choreo.get(Instance.new("Model"))
		end).toThrow("no Rig attribute")
		expect(Choreo.count()).toBe(0)
	end)

	it("an enemy rig poses from its own idle", function()
		local model = buildRig("Boar")
		local animator = Choreo.get(model)
		expect(animator.rigId).toBe("Boar")
		expect(animator:isPlaying(ChoreoData.rigs.Boar.idle)).toBe(true)
		expect(motorOf(model, "Neck").Transform == CFrame.identity).toBe(false)
		Choreo.release(model)
	end)

	it("a server-timed play catches up, fires events as frames cross them and sums its root motion", function()
		clock = 100
		local model = buildRig("PlayerR15")
		local animator = Choreo.get(model)
		local kinds = eventKinds(animator)
		local finished = 0
		animator.finished:Connect(function()
			finished += 1
		end)
		local started = 0.1
		local handle = animator:play(HORIZONTAL, { serverTime = clock - started, blendIn = 0 })
		expect(animator:isPlaying(HORIZONTAL)).toBe(true)
		expect(handle.clipId).toBe(HORIZONTAL)

		local travel = 0
		local framesToOpen = math.ceil((HIT_OPEN_TIME - started) / FRAME)
		for _ = 1, framesToOpen - 1 do
			animator:step(FRAME)
			travel += animator:currentRootMotionDelta().Z
		end
		expect(count(kinds, "HitWindowOpen")).toBe(0)
		animator:step(FRAME)
		travel += animator:currentRootMotionDelta().Z
		expect(count(kinds, "HitWindowOpen")).toBe(1)
		expect(count(kinds, "ActivationHold")).toBe(1)

		local steps = 0
		while finished == 0 and steps < 200 do
			animator:step(FRAME)
			travel += animator:currentRootMotionDelta().Z
			steps += 1
		end
		expect(finished).toBe(1)
		expect(count(kinds, "HitWindowClose")).toBe(1)
		expect(count(kinds, "PostMotionStart")).toBe(1)
		expect(travel).toBeCloseTo(-1, 1e-3)
		Choreo.release(model)
		clock = 0
	end)

	it("hitStopAll holds every listed rig for the tier's frame count, then motion resumes", function()
		local player = buildRig("PlayerR15")
		local boar = buildRig("Boar")
		local playerAnimator = Choreo.get(player)
		local boarAnimator = Choreo.get(boar)
		playerAnimator:play(HORIZONTAL, { blendIn = 0 })
		Choreo.stepAll(0) -- compose the new clip into the pose without advancing any clock
		local weapon = motorOf(player, "Weapon")
		local neck = motorOf(boar, "Neck")
		local frames = Combat.hitStopFrames.Final

		Choreo.hitStopAll({ player, boar }, "Final")
		expect(playerAnimator:isPaused()).toBe(true)
		expect(boarAnimator:isPaused()).toBe(true)
		local weaponBefore = weapon.Transform
		local neckBefore = neck.Transform
		for _ = 1, frames - 1 do
			Choreo.stepAll(FRAME)
			expect(playerAnimator:isPaused()).toBe(true)
		end
		expect(weapon.Transform == weaponBefore).toBe(true)
		expect(neck.Transform == neckBefore).toBe(true)
		Choreo.stepAll(FRAME)
		expect(playerAnimator:isPaused()).toBe(false)
		expect(boarAnimator:isPaused()).toBe(false)
		for _ = 1, 30 do
			Choreo.stepAll(FRAME)
		end
		expect(weapon.Transform == weaponBefore).toBe(false)
		Choreo.release(player)
		Choreo.release(boar)
	end)

	it("RenderStepped steps the near rigs every frame; Heartbeat steps distant rigs at the tier rate", function()
		camera = Vector3.zero
		local near = buildRig("PlayerR15", Vector3.zero)
		local far = buildRig("Kobold", Vector3.new(ChoreoData.quality.High.nearRadius * 10, 0, 0))
		local nearAnimator = Choreo.get(near)
		local farAnimator = Choreo.get(far)
		local nearKinds = eventKinds(nearAnimator)
		local farKinds = eventKinds(farAnimator)
		local justBefore = HIT_OPEN_TIME - FRAME * 0.5
		nearAnimator:play(HORIZONTAL, { startTime = justBefore, blendIn = 0 })
		farAnimator:play(HORIZONTAL, { startTime = justBefore, blendIn = 0 })

		renderStepped:Fire(FRAME)
		expect(count(nearKinds, "HitWindowOpen")).toBe(1)
		expect(count(farKinds, "HitWindowOpen")).toBe(0)

		heartbeat:Fire(FRAME)
		expect(count(farKinds, "HitWindowOpen")).toBe(0)
		heartbeat:Fire(FRAME)
		heartbeat:Fire(FRAME)
		expect(count(farKinds, "HitWindowOpen")).toBe(1)

		-- The local player's rig is always full rate, however far the camera sits.
		Choreo.setLocalModel(far)
		farAnimator:play(HORIZONTAL, { startTime = justBefore, blendIn = 0 })
		renderStepped:Fire(FRAME)
		expect(count(farKinds, "HitWindowOpen")).toBe(2)
		Choreo.setLocalModel(nil)
		Choreo.release(near)
		Choreo.release(far)
	end)

	it("setQuality switches the tier and rejects unknown ones", function()
		Choreo.setQuality("Low")
		expect(Choreo.quality()).toBe("Low")
		expect(function()
			Choreo.setQuality("Ultra")
		end).toThrow("unknown tier")
		Choreo.setQuality("High")
		expect(Choreo.quality()).toBe("High")
	end)

	it("Choreo.play is a shortcut; stop by clip id ends the clip; release leaves the model intact", function()
		local model = buildRig("PlayerR15")
		local handle = Choreo.play(model, GUARD)
		local animator = Choreo.find(model)
		expect(handle.clipId).toBe(GUARD)
		expect(animator:isPlaying(GUARD)).toBe(true)
		animator:stop(GUARD, 0)
		animator:step(FRAME)
		expect(animator:isPlaying(GUARD)).toBe(false)
		Choreo.release(model)
		expect(motorOf(model, "Weapon")).toBeTruthy()
		expect(model.PrimaryPart.Name).toBe("HumanoidRootPart")
		renderStepped:Fire(FRAME)
		expect(Choreo.count()).toBe(0)
	end)
end)
