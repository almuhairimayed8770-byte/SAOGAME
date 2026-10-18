--!strict
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
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")

local FRAME = 1 / 60
local HORIZONTAL = "player/OneHandedSword/Horizontal"
local GUARD = "player/OneHandedSword/Guard"
-- The Horizontal clip's first HitWindowOpen, read from the clip so the spec follows the data.
local HIT_OPEN_TIME: number = ClipSampler.hitWindows(ClipLibrary.get(HORIZONTAL))[1].open

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

-- The player character under the Avatar Joint Upgrade: a Humanoid model whose R15 joints are
-- AnimationConstraints between rig attachments (parented to Part1, no Motor6D), with ball sockets
-- on the same attachments and the Weapon on a Motor6D as WeaponBuilder hangs it. With
-- `withJoints` false only the parts exist; the returned function adds the joints later (a
-- replicated rig whose joints arrive after the animator attached) and returns them.
local function buildUpgradedCharacter(withJoints: boolean)
	local model = Instance.new("Model")
	model.Name = "UpgradedCharacter"
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
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
	for _, joint in Rigs.PlayerR15.joints do
		part(joint.part0)
		part(joint.part1)
	end
	model.PrimaryPart = parts.HumanoidRootPart
	local function addJoints()
		local added = {}
		for _, joint in Rigs.PlayerR15.joints do
			local part0, part1 = parts[joint.part0], parts[joint.part1]
			if joint.name == "Weapon" then
				local motor = Instance.new("Motor6D")
				motor.Name = joint.name
				motor.Part0 = part0
				motor.Part1 = part1
				motor.Parent = part1
				table.insert(added, motor)
				continue
			end
			local attachment0 = Instance.new("Attachment")
			attachment0.Name = joint.name .. "RigAttachment"
			attachment0.Parent = part0
			local attachment1 = Instance.new("Attachment")
			attachment1.Name = joint.name .. "RigAttachment"
			attachment1.Parent = part1
			local constraint = Instance.new("AnimationConstraint")
			constraint.Name = joint.name
			constraint.Attachment0 = attachment0
			constraint.Attachment1 = attachment1
			constraint.Parent = part1
			table.insert(added, constraint)
			if joint.name ~= "Root" then
				local socket = Instance.new("BallSocketConstraint")
				socket.Name = joint.name .. "BallSocket"
				socket.Attachment0 = attachment0
				socket.Attachment1 = attachment1
				socket.Parent = part1
				table.insert(added, socket)
			end
		end
		return added
	end
	if withJoints then
		addJoints()
	end
	return model, addJoints
end

-- The joint (either kind) with this name.
local function jointOf(model, name)
	for _, descendant in model:GetDescendants() do
		if (descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint")) and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

-- Records the instance signals Choreo connects to, so a test can fire DescendantAdded by hand
-- (Lune's instances have no events). Returns the recorder and a function that restores the
-- engine's own connect (which fails quietly under Lune, as before).
local function recordConnections()
	local recorded = {}
	Choreo.configure({
		connect = function(instance, eventName, fn)
			local entry = { instance = instance, eventName = eventName, fn = fn, connected = true }
			table.insert(recorded, entry)
			return {
				Disconnect = function()
					entry.connected = false
				end,
			}
		end,
	})
	local function fire(instance, eventName, ...)
		for _, entry in recorded do
			if entry.connected and entry.instance == instance and entry.eventName == eventName then
				entry.fn(...)
			end
		end
	end
	local function restore()
		Choreo.configure({
			connect = function(instance, eventName, fn)
				local ok, result = pcall(function()
					return instance[eventName]:Connect(fn)
				end)
				return if ok then result else nil
			end,
		})
	end
	return fire, restore
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

	it("poses an AnimationConstraint rig (the Avatar Joint Upgrade character) by writing Transform", function()
		local model = buildUpgradedCharacter(true)
		local shoulder = jointOf(model, "RightShoulder")
		expect(shoulder:IsA("AnimationConstraint")).toBe(true)
		expect(shoulder.Transform == CFrame.identity).toBe(true)
		local animator = Choreo.get(model)
		expect(animator.rigId).toBe("PlayerR15")
		-- Posed the frame it appears, on the constraints and on the Weapon Motor6D alike.
		expect(shoulder.Transform == CFrame.identity).toBe(false)
		expect(jointOf(model, "Root").Transform == CFrame.identity).toBe(false)
		expect(motorOf(model, "Weapon").Transform == CFrame.identity).toBe(false)
		-- An Art drives the constraints frame by frame.
		animator:play(HORIZONTAL, { startTime = HIT_OPEN_TIME - 0.1, blendIn = 0 })
		animator:step(0)
		local before = shoulder.Transform
		for _ = 1, 6 do
			animator:step(FRAME)
		end
		expect(shoulder.Transform == before).toBe(false)
		-- Only Transform is written: the rig attachments the Humanoid owns are untouched.
		expect(shoulder.Attachment0.CFrame == CFrame.identity).toBe(true)
		expect(shoulder.Attachment1.CFrame == CFrame.identity).toBe(true)
		Choreo.release(model)
	end)

	it("rescans when the joints arrive after the animator attached (a replicated rig)", function()
		local fire, restore = recordConnections()
		local model, addJoints = buildUpgradedCharacter(false)
		local animator = Choreo.get(model)
		animator:step(FRAME)

		local added = addJoints()
		local shoulder = jointOf(model, "RightShoulder")
		animator:step(FRAME)
		-- No DescendantAdded yet: the joint map is still the empty one.
		expect(shoulder.Transform == CFrame.identity).toBe(true)

		for _, instance in added do
			fire(model, "DescendantAdded", instance)
		end
		animator:step(FRAME)
		expect(shoulder.Transform == CFrame.identity).toBe(false)
		expect(motorOf(model, "Weapon").Transform == CFrame.identity).toBe(false)

		-- A joint that leaves is dropped: its replacement is the one written from then on.
		local replacement = Instance.new("AnimationConstraint")
		replacement.Name = "RightShoulder"
		replacement.Attachment0 = shoulder.Attachment0
		replacement.Attachment1 = shoulder.Attachment1
		local parent = shoulder.Parent
		fire(model, "DescendantRemoving", shoulder)
		shoulder.Parent = nil
		replacement.Parent = parent
		fire(model, "DescendantAdded", replacement)
		animator:step(FRAME)
		expect(replacement.Transform == CFrame.identity).toBe(false)

		-- Two joints of one name for a moment (a rebuild that adds the new joint before the old one
		-- leaves): either may be the one written while both are there, so both orders are played
		-- out, and once one leaves the other is written from the next step on.
		local function sameName(): any
			local joint = Instance.new("AnimationConstraint")
			joint.Name = "RightShoulder"
			joint.Attachment0 = shoulder.Attachment0
			joint.Attachment1 = shoulder.Attachment1
			joint.Parent = parent
			fire(model, "DescendantAdded", joint)
			animator:step(FRAME)
			return joint
		end
		local function leaves(gone: any, stays: any)
			fire(model, "DescendantRemoving", gone)
			gone.Parent = nil
			gone.Transform = CFrame.identity
			stays.Transform = CFrame.identity
			animator:step(FRAME)
			expect(stays.Transform == CFrame.identity).toBe(false)
			expect(gone.Transform == CFrame.identity).toBe(true)
		end
		leaves(sameName(), replacement) -- the newcomer leaves again
		local rebuilt = sameName()
		leaves(replacement, rebuilt) -- the old joint leaves

		Choreo.release(model)
		restore()
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
		-- Half a frame off the 60 Hz grid: the clip's events sit on frame boundaries (the window opens
		-- on the snap key), and which step crosses a boundary event would come down to float rounding.
		local started = 0.1 + FRAME * 0.5
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

	it("pin holds a keyed joint at rest from the moment it is set; unpinning puts the keyed value back", function()
		local model = buildRig("PlayerR15")
		local animator = Choreo.get(model)
		local weapon = motorOf(model, "Weapon")
		local shoulder = motorOf(model, "RightShoulder")
		animator:play(GUARD, { blendIn = 0 })
		animator:setProcedural("test", { Weapon = { pos = { 0, 0, 0 }, rot = { 5, 0, 0 } } }, 1)
		animator:step(FRAME)
		expect(weapon.Transform == CFrame.identity).toBe(false)

		animator:pin("Weapon", true)
		-- At rest at once (a pin set from a clip event shows in that frame), and on every step after,
		-- while the clip and the procedural channel still key it; other joints are untouched.
		expect(weapon.Transform == CFrame.identity).toBe(true)
		for _ = 1, 3 do
			animator:step(FRAME)
			expect(weapon.Transform == CFrame.identity).toBe(true)
			expect(shoulder.Transform == CFrame.identity).toBe(false)
		end

		animator:pin("Weapon", false)
		-- Lune stores a Transform at a little under float precision: compare within 1e-4.
		local expected = ClipSampler.toCFrame(animator.mixer:lastOffsets().Weapon)
		expect((weapon.Transform.Position - expected.Position).Magnitude < 1e-4).toBe(true)
		expect((weapon.Transform.LookVector - expected.LookVector).Magnitude < 1e-4).toBe(true)
		expect(weapon.Transform == CFrame.identity).toBe(false)
		animator:step(FRAME)
		expect(weapon.Transform == CFrame.identity).toBe(false)
		Choreo.release(model)
	end)

	it("only the Base clip the limbs show most sounds its footsteps; other layers sound theirs", function()
		local idleId = "player/OneHandedSword/Idle"
		local runId = "player/OneHandedSword/Run"
		local runDrawnId = "player/OneHandedSword/RunDrawn"
		local landId = "player/OneHandedSword/Land"
		local model = buildRig("PlayerR15")
		local animator = Choreo.get(model)
		local frames: { { string } } = {}
		local current: { string } = {}
		animator.events:Connect(function(clipId, event)
			if event.kind == "Footstep" then
				table.insert(current, clipId)
			end
		end)
		-- The footsteps the mixer crossed, by clip, whatever their weight.
		local crossed: { [string]: number } = {}
		local mixerStep = animator.mixer.step
		animator.mixer.step = function(self, dt)
			local result = mixerStep(self, dt)
			for _, fired in result.events do
				if fired.event.kind == "Footstep" then
					crossed[fired.clipId] = (crossed[fired.clipId] or 0) + 1
				end
			end
			return result
		end
		local function run(seconds: number): { string }
			local all = {}
			table.clear(crossed)
			for _ = 1, math.ceil(seconds / FRAME - 1e-9) do
				current = {}
				animator:step(FRAME)
				table.insert(frames, current)
				for _, clipId in current do
					table.insert(all, clipId)
				end
			end
			return all
		end
		-- The locomotion set: every walk runs at once, the ones not in use at weight zero.
		local idle = animator:play(idleId, { coexist = true, weight = 1, blendIn = 0 })
		local runHandle = animator:play(runId, { coexist = true, weight = 0, blendIn = 0 })
		local runDrawn = animator:play(runDrawnId, { coexist = true, weight = 0, blendIn = 0 })
		local cycle = ClipLibrary.get(runId).duration
		-- Standing still: no footstep, though the mixer crosses the walks' steps.
		expect(#run(3 * cycle)).toBe(0)
		expect(crossed[runId] >= 3).toBe(true)
		expect(crossed[runDrawnId]).toBe(crossed[runId])

		-- Running: Run's own steps.
		animator:setWeight(idle, 0, true)
		animator:setWeight(runHandle, 1, true)
		local running = run(3 * cycle)
		expect(count(running, runId)).toBe(crossed[runId])
		expect(count(running, runDrawnId)).toBe(0)

		-- Halfway into the drawn twin (same clock, same steps): one set, the first of the two.
		animator:setWeight(runHandle, 0.5, true)
		animator:setWeight(runDrawn, 0.5, true)
		local half = run(3 * cycle)
		expect(count(half, runId)).toBe(crossed[runId])
		expect(count(half, runDrawnId)).toBe(0)
		animator:setWeight(runHandle, 0.3, true)
		animator:setWeight(runDrawn, 0.7, true)
		local mostlyDrawn = run(3 * cycle)
		expect(count(mostlyDrawn, runDrawnId)).toBe(crossed[runDrawnId])
		expect(count(mostlyDrawn, runId)).toBe(0)
		for _, fired in frames do
			expect(#fired <= 1).toBe(true)
		end

		-- A clip on another layer sounds its own steps over the walk.
		local landSteps = 0
		for _, event in ClipLibrary.get(landId).events do
			if event.kind == "Footstep" then
				landSteps += 1
			end
		end
		animator:setWeight(runDrawn, 0, true)
		animator:setWeight(idle, 1, true)
		animator:play(landId, { blendIn = 0 })
		expect(landSteps > 0).toBe(true)
		expect(count(run(ClipLibrary.get(landId).duration), landId)).toBe(landSteps)
		Choreo.release(model)
	end)

	it("joint returns the joint Choreo writes for a name, the new one after a replace", function()
		local fire, restore = recordConnections()
		local model = buildRig("PlayerR15")
		local animator = Choreo.get(model)
		local old = motorOf(model, "Weapon")
		expect(animator:joint("Weapon")).toBe(old)
		expect(animator:joint("NoSuchJoint")).toBeNil()
		animator:pin("Weapon", true)

		local replacement = Instance.new("Motor6D")
		replacement.Name = "Weapon"
		replacement.Transform = CFrame.new(0, 1, 0)
		local parent = old.Parent
		fire(model, "DescendantRemoving", old)
		old.Parent = nil
		replacement.Parent = parent
		fire(model, "DescendantAdded", replacement)
		expect(animator:joint("Weapon")).toBe(replacement)
		-- The pin is by name, so the new joint is put at rest and held there too.
		expect(replacement.Transform == CFrame.identity).toBe(true)
		animator:play(GUARD, { blendIn = 0 })
		animator:step(FRAME)
		expect(replacement.Transform == CFrame.identity).toBe(true)
		animator:pin("Weapon", false)
		animator:step(FRAME)
		expect(replacement.Transform == CFrame.identity).toBe(false)
		Choreo.release(model)
		restore()
	end)
end)
