--!strict
-- WeaponMount on a Lune player rig whose sword WeaponBuilder hung on the right hand, as the
-- server does: the client moves the motor between the hand and the back mount from data.
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
	PreSimulation = fakeSignal(), -- Choreo's pose rewrite: run alone, the spec needs it too
	-- Choreo's rig step (bound just before the camera's): the spec steps the rigs itself.
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
local WeaponMount = Harness.load("src/client/choreo/WeaponMount")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")
local Rigs = Harness.load("src/shared/data/rigs")

local FRAME = 1 / 60
local SWORD = Weapons.byId("TrialistSword")
local ROW = WeaponModels.sheath(SWORD.category)
local IDLE_DRAWN = "player/OneHandedSword/IdleDrawn" -- keys the Weapon joint (the blade re-grip)

-- Lune stores a Motor6D's C0 at a little under float precision, so a frame read back from the
-- instance is compared within this many studs (and unit-vector lengths).
local STORED = 1e-4

local function sameFrame(a: CFrame, b: CFrame, tolerance: number?): boolean
	local limit = tolerance or 1e-6
	return (a.Position - b.Position).Magnitude <= limit
		and (a.RightVector - b.RightVector).Magnitude <= limit
		and (a.UpVector - b.UpVector).Magnitude <= limit
		and (a.LookVector - b.LookVector).Magnitude <= limit
end

-- Records the instance signals Choreo connects to, so a test can fire DescendantAdded by hand
-- (Lune's instances have no events). Returns the fire function and one that restores the default.
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

local world = Instance.new("Folder")
world.Name = "World"

-- A PlayerR15 rig of plain parts and Motor6Ds (no Weapon joint), then the sword through the
-- server's own WeaponBuilder, parented into a world folder. `withoutPart` leaves one body part out.
local function buildRig(withoutPart: string?): any
	local model = Instance.new("Model")
	model.Name = "Player"
	model:SetAttribute("Rig", "PlayerR15")
	local parts = {}
	local function part(name)
		local existing = parts[name]
		if existing ~= nil or name == withoutPart then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Size = Vector3.new(1, 1, 1)
		created.CFrame = CFrame.new(0, 3, 0)
		created.Position = Vector3.new(0, 3, 0) -- Lune keeps the two apart; Choreo reads Position
		created.Parent = model
		parts[name] = created
		return created
	end
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name == WeaponModels.motorName then
			continue
		end
		local part0, part1 = part(joint.part0), part(joint.part1)
		if part0 ~= nil and part1 ~= nil then
			local motor = Instance.new("Motor6D")
			motor.Name = joint.name
			motor.Part0 = part0
			motor.Part1 = part1
			motor.C0 = RigBuilder.frameOf(joint.c0)
			motor.Parent = part1
		end
	end
	model.PrimaryPart = parts.HumanoidRootPart
	WeaponBuilder.equip(model, SWORD)
	model.Parent = world
	return model
end

local function motorOf(model: any): any
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name == WeaponModels.motorName then
			return descendant
		end
	end
	return nil
end

-- A stand-in for a model that counts the method calls made on it and passes them on.
local function countCalls(model: any): (any, { [string]: number })
	local counts: { [string]: number } = {}
	local proxy = setmetatable({}, {
		__index = function(_, key)
			local value = model[key]
			if type(value) == "function" then
				return function(_, ...)
					counts[key] = (counts[key] or 0) + 1
					return value(model, ...)
				end
			end
			return value
		end,
	})
	return proxy, counts
end

describe("WeaponMount", function()
	it("has a back mount for the loadout sword and a hand frame equal to the server's", function()
		expect(ROW).toBeTruthy()
		expect(sameFrame(WeaponMount.handFrame(), RigBuilder.frameOf(WeaponBuilder.gripJoint().c0))).toBe(true)
		local part, frame = WeaponMount.backFrame(SWORD.category)
		expect(part).toBe(ROW.part)
		expect(sameFrame(frame, ClipSampler.toCFrame(ROW.mount))).toBe(true)
		local none, noFrame = WeaponMount.backFrame("Rapier")
		expect(none).toBeNil()
		expect(noFrame).toBeNil()
	end)

	it("Back moves the motor onto the mount from data, leaves C1 and pins the joint at rest", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		local motor = motorOf(model)
		local c1 = motor.C1
		animator:play(IDLE_DRAWN, { blendIn = 0 })
		animator:step(FRAME)
		expect(motor.Transform == CFrame.identity).toBe(false)

		local mount = WeaponMount.new(animator, model)
		expect(mount:sheathable()).toBe(true)
		expect(mount:get()).toBe("Hand")
		mount:set("Back")
		expect(mount:get()).toBe("Back")
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		expect(sameFrame(motor.C0, ClipSampler.toCFrame(ROW.mount), STORED)).toBe(true)
		expect(motor.C1 == c1).toBe(true)
		-- At rest at once, and every step after, though IdleDrawn keys the Weapon joint.
		expect(motor.Transform == CFrame.identity).toBe(true)
		for _ = 1, 5 do
			animator:step(FRAME)
			expect(motor.Transform == CFrame.identity).toBe(true)
		end
		mount:destroy()
		Choreo.release(model)
	end)

	it("Hand puts the motor back on the right hand at the rigs.luau frame and lets the clip pose it", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		animator:play(IDLE_DRAWN, { blendIn = 0 })
		local motor = motorOf(model)
		local mount = WeaponMount.new(animator, model)
		mount:set("Back")
		animator:step(FRAME)
		mount:set("Hand")
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		expect(sameFrame(motor.C0, WeaponMount.handFrame(), STORED)).toBe(true)
		-- Unpinned in the same frame: the clip's Weapon key is back on the joint.
		expect(motor.Transform == CFrame.identity).toBe(false)
		local keyed = motor.Transform
		animator:step(0)
		expect(sameFrame(motor.Transform, keyed)).toBe(true)
		mount:destroy()
		Choreo.release(model)
	end)

	it("a Part0 or C0 moved behind its back is put back on the next step", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		local motor = motorOf(model)
		local mount = WeaponMount.new(animator, model)
		mount:set("Back")
		motor.Part0 = model:FindFirstChild("RightHand")
		motor.C0 = CFrame.identity
		animator:step(FRAME)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		expect(sameFrame(motor.C0, ClipSampler.toCFrame(ROW.mount), STORED)).toBe(true)
		mount:destroy()
		Choreo.release(model)
	end)

	it("a replaced motor (a re-equip) gets the wished place on the next step", function()
		local fire, restore = recordConnections()
		local model = buildRig()
		local animator = Choreo.get(model)
		local mount = WeaponMount.new(animator, model)
		mount:set("Back")
		local generation = mount:generation()
		local old = motorOf(model)
		fire(model, "DescendantRemoving", old)
		WeaponBuilder.equip(model, SWORD)
		local new = motorOf(model)
		fire(model, "DescendantAdded", new)
		expect(new ~= old).toBe(true)
		expect(new.Part0).toBe(model:FindFirstChild("RightHand"))
		animator:step(FRAME)
		expect(new.Part0).toBe(model:FindFirstChild(ROW.part))
		expect(sameFrame(new.C0, ClipSampler.toCFrame(ROW.mount), STORED)).toBe(true)
		expect(mount:generation()).toBe(generation + 1)
		mount:destroy()
		Choreo.release(model)
		restore()
	end)

	it(
		"no category, a category without a row, or a rig without the row's part cannot sheathe: set is a no-op",
		function()
			local function check(model: any)
				local animator = Choreo.get(model)
				animator:play(IDLE_DRAWN, { blendIn = 0 })
				animator:step(FRAME)
				local motor = motorOf(model)
				local part0, c0 = motor.Part0, motor.C0
				local mount = WeaponMount.new(animator, model)
				expect(mount:sheathable()).toBe(false)
				mount:set("Back")
				animator:step(FRAME)
				expect(mount:get()).toBe("Back")
				expect(motor.Part0).toBe(part0)
				expect(motor.C0 == c0).toBe(true)
				expect(motor.Transform == CFrame.identity).toBe(false)
				mount:destroy()
				Choreo.release(model)
			end
			local noCategory = buildRig()
			noCategory:FindFirstChild(WeaponModels.modelName):SetAttribute(WeaponModels.attributes.category, nil)
			check(noCategory)
			local noRow = buildRig()
			noRow:FindFirstChild(WeaponModels.modelName):SetAttribute(WeaponModels.attributes.category, "Rapier")
			check(noRow)
			check(buildRig(ROW.part))
		end
	)

	it(
		"a weapon category or a back part that arrives after the motor still takes the sword to the back (D-519)",
		function()
			-- On d06ff43 the mount worked out once per new motor whether it could sheathe, so a motor
			-- seen before its weapon's category attribute or the sheath row's body part kept the sword
			-- in the hand for good (the owner's PC: Part0 RightHand on every row, sheathed or not).
			local lateCategory = buildRig()
			local weapon = lateCategory:FindFirstChild(WeaponModels.modelName)
			weapon:SetAttribute(WeaponModels.attributes.category, nil)
			local animator = Choreo.get(lateCategory)
			local motor = motorOf(lateCategory)
			local mount = WeaponMount.new(animator, lateCategory)
			mount:set("Back")
			animator:step(FRAME)
			expect(mount:sheathable()).toBe(false)
			expect(motor.Part0).toBe(lateCategory:FindFirstChild("RightHand"))
			weapon:SetAttribute(WeaponModels.attributes.category, SWORD.category)
			animator:step(FRAME)
			expect(mount:sheathable()).toBe(true)
			expect(motor.Part0).toBe(lateCategory:FindFirstChild(ROW.part))
			expect(sameFrame(motor.C0, ClipSampler.toCFrame(ROW.mount), STORED)).toBe(true)
			mount:destroy()
			Choreo.release(lateCategory)

			local latePart = buildRig(ROW.part)
			local animator2 = Choreo.get(latePart)
			local motor2 = motorOf(latePart)
			local mount2 = WeaponMount.new(animator2, latePart)
			mount2:set("Back")
			animator2:step(FRAME)
			expect(motor2.Part0).toBe(latePart:FindFirstChild("RightHand"))
			local body = Instance.new("Part")
			body.Name = ROW.part
			body.Parent = latePart
			animator2:step(FRAME)
			expect(motor2.Part0).toBe(body)
			mount2:destroy()
			Choreo.release(latePart)
		end
	)

	it("names where this client hangs the blade, and why it cannot sheathe, on the character (D-519)", function()
		local MOUNT, WHY = WeaponModels.attributes.mount, WeaponModels.attributes.mountWhy
		local model = buildRig()
		local animator = Choreo.get(model)
		local mount = WeaponMount.new(animator, model)
		expect(model:GetAttribute(MOUNT)).toBe("Hand")
		expect(model:GetAttribute(WHY)).toBeNil()
		mount:set("Back")
		expect(model:GetAttribute(MOUNT)).toBe("Back")
		mount:set("Hand")
		animator:step(FRAME)
		expect(model:GetAttribute(MOUNT)).toBe("Hand")
		mount:destroy()
		expect(model:GetAttribute(MOUNT)).toBeNil()
		Choreo.release(model)

		local noRow = buildRig()
		noRow:FindFirstChild(WeaponModels.modelName):SetAttribute(WeaponModels.attributes.category, "Rapier")
		local animator2 = Choreo.get(noRow)
		local mount2 = WeaponMount.new(animator2, noRow)
		mount2:set("Back")
		expect(noRow:GetAttribute(MOUNT)).toBe("Hand")
		expect(noRow:GetAttribute(WHY)).toBe("no sheath row for Rapier")
		mount2:destroy()
		Choreo.release(noRow)

		local noBack = buildRig(ROW.part)
		local animator3 = Choreo.get(noBack)
		local mount3 = WeaponMount.new(animator3, noBack)
		mount3:set("Back")
		expect(noBack:GetAttribute(MOUNT)).toBe("Hand")
		expect(noBack:GetAttribute(WHY)).toBe("no " .. ROW.part)
		mount3:destroy()
		Choreo.release(noBack)
	end)

	it("looks the hand and the back part up once per new motor, not on every step", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		local motor = motorOf(model)
		local proxy, counts = countCalls(model)
		local mount = WeaponMount.new(animator, proxy)
		expect(mount:sheathable()).toBe(true)
		table.clear(counts)
		for _, place in { "Hand", "Back", "Hand" } do
			mount:set(place)
			for _ = 1, 30 do
				animator:step(FRAME)
			end
		end
		expect(counts.FindFirstChild or 0).toBe(0)
		expect(counts.FindFirstChildOfClass or 0).toBe(0)
		expect(counts.GetDescendants or 0).toBe(0)
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		mount:set("Back")
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		mount:destroy()
		Choreo.release(model)
	end)

	it("destroy puts the sword back in the hand, unpinned, and drops the hook", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		animator:play(IDLE_DRAWN, { blendIn = 0 })
		local motor = motorOf(model)
		local mount = WeaponMount.new(animator, model)
		mount:set("Back")
		mount:destroy()
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		expect(sameFrame(motor.C0, WeaponMount.handFrame(), STORED)).toBe(true)
		animator:step(FRAME)
		expect(motor.Transform == CFrame.identity).toBe(false)
		-- The hook is gone: a later change is not undone.
		motor.Part0 = model:FindFirstChild(ROW.part)
		animator:step(FRAME)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		Choreo.release(model)
	end)

	it("destroy on a model that left the world writes nothing to it", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		local motor = motorOf(model)
		local mount = WeaponMount.new(animator, model)
		mount:set("Back")
		model.Parent = nil
		mount:destroy()
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		Choreo.release(model)
	end)

	it("one mount drives an animator: a second takes over and hands the sword back when destroyed", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		local motor = motorOf(model)
		local first = WeaponMount.new(animator, model)
		first:set("Back")
		local second = WeaponMount.new(animator, model)
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		first:set("Back")
		animator:step(FRAME)
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		second:destroy()
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		first:destroy()
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		-- Destroying a mount that is not driving leaves the sword to the one that is.
		local driving = WeaponMount.new(animator, model)
		local stacked = WeaponMount.new(animator, model)
		stacked:set("Back")
		driving:destroy()
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		stacked:destroy()
		Choreo.release(model)
	end)
end)

-- A stand-in for FrameClock.atStepPose: holds what it is handed until `open` (the frame that draws
-- the step's pose) runs it; `cancels` counts the cancels that dropped one still held.
local function heldGate(): any
	local gate = { waiting = {} :: { any }, cancels = 0, asked = 0 }
	function gate.atStepPose(fn: () -> ()): () -> ()
		gate.asked += 1
		local entry = { fn = fn, cancelled = false }
		table.insert(gate.waiting, entry)
		return function()
			if not entry.cancelled then
				entry.cancelled = true
				gate.cancels += 1
			end
		end
	end
	function gate.open()
		local due = gate.waiting
		gate.waiting = {}
		for _, entry in due do
			if not entry.cancelled then
				entry.fn()
			end
		end
	end
	return gate
end

describe("WeaponMount: a move asked from the step lands with that step's pose (D-555)", function()
	it("waits for the frame that draws its pose; until then the sword stays on the back, pinned", function()
		-- Before, set("Hand", true) moved the motor at once, in the step: the screen put the blade on
		-- the hand of the pose before for one frame (AG 376(b)).
		local model = buildRig()
		local animator = Choreo.get(model)
		animator:play(IDLE_DRAWN, { blendIn = 0 })
		local motor = motorOf(model)
		local gate = heldGate()
		local mount = WeaponMount.new(animator, model, { atStepPose = gate.atStepPose })
		mount:set("Back")
		animator:step(FRAME)
		local back = model:FindFirstChild(ROW.part)
		mount:set("Hand", true)
		expect(mount:get()).toBe("Hand")
		expect(motor.Part0).toBe(back)
		expect(motor.Transform == CFrame.identity).toBe(true)
		expect(model:GetAttribute(WeaponModels.attributes.mount)).toBe("Back")
		-- The step itself (its hook re-reads the joint) keeps it there.
		animator:step(FRAME)
		expect(motor.Part0).toBe(back)
		expect(motor.Transform == CFrame.identity).toBe(true)
		expect(gate.asked).toBe(1)
		gate.open()
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		expect(sameFrame(motor.C0, WeaponMount.handFrame(), STORED)).toBe(true)
		-- Unpinned with the step's own Weapon key.
		expect(motor.Transform == CFrame.identity).toBe(false)
		expect(model:GetAttribute(WeaponModels.attributes.mount)).toBe("Hand")
		mount:destroy()
		Choreo.release(model)
	end)

	it("lets the pin go (or sets it) before Part0 moves, so the blade lands from its new place's Transform", function()
		-- A Part0 or C0 write puts the blade on its new part at once from the joint's Transform as it
		-- stands: the hand takes the pose's Weapon key, the back rest. Before, the pin came after
		-- Part0 (the hand landing read rest, the back landing the hand's key).
		local model = buildRig()
		local animator: any = Choreo.get(model)
		animator:play(IDLE_DRAWN, { blendIn = 0 })
		local motor = motorOf(model)
		local seen: { { pinned: boolean, part0: any } } = {}
		local realPin = animator.pin
		animator.pin = function(self: any, name: string, pinned: boolean)
			if name == WeaponModels.motorName then
				table.insert(seen, { pinned = pinned, part0 = motor.Part0 })
			end
			return realPin(self, name, pinned)
		end
		local gate = heldGate()
		local mount = WeaponMount.new(animator, model, { atStepPose = gate.atStepPose })
		local hand, back = model:FindFirstChild("RightHand"), model:FindFirstChild(ROW.part)
		table.clear(seen)
		mount:set("Back")
		expect(seen[1].pinned).toBe(true)
		expect(seen[1].part0).toBe(hand)
		animator:step(FRAME)
		table.clear(seen)
		mount:set("Hand", true)
		gate.open()
		expect(seen[1].pinned).toBe(false)
		expect(seen[1].part0).toBe(back)
		expect(motor.Part0).toBe(hand)
		mount:destroy()
		Choreo.release(model)
	end)

	it("a new motor (a respawn's re-equip, streaming) takes the wished place at once and drops the wait", function()
		local fire, restore = recordConnections()
		local model = buildRig()
		local animator = Choreo.get(model)
		local gate = heldGate()
		local mount = WeaponMount.new(animator, model, { atStepPose = gate.atStepPose })
		local hand = model:FindFirstChild("RightHand")
		-- Drawn, and the step asks for the back (a Sheathe's WeaponSheathe): the sword waits in the hand.
		mount:set("Back", true)
		expect(motorOf(model).Part0).toBe(hand)
		local old = motorOf(model)
		fire(model, "DescendantRemoving", old)
		WeaponBuilder.equip(model, SWORD)
		local new = motorOf(model)
		fire(model, "DescendantAdded", new)
		animator:step(FRAME)
		expect(new.Part0).toBe(model:FindFirstChild(ROW.part))
		expect(gate.cancels).toBe(1)
		gate.open()
		expect(new.Part0).toBe(model:FindFirstChild(ROW.part))
		mount:destroy()
		Choreo.release(model)
		restore()
	end)

	it("a wish that turns back before its frame moves nothing", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		local motor = motorOf(model)
		local gate = heldGate()
		local mount = WeaponMount.new(animator, model, { atStepPose = gate.atStepPose })
		local back = model:FindFirstChild(ROW.part)
		mount:set("Back")
		mount:set("Hand", true)
		mount:set("Hand", true)
		expect(gate.asked).toBe(1)
		mount:set("Back", true)
		expect(gate.cancels).toBe(1)
		gate.open()
		expect(motor.Part0).toBe(back)
		expect(motor.Transform == CFrame.identity).toBe(true)
		expect(mount:get()).toBe("Back")
		mount:destroy()
		Choreo.release(model)
	end)

	it("destroy drops a move still waiting and writes nothing after", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		local motor = motorOf(model)
		local gate = heldGate()
		local mount = WeaponMount.new(animator, model, { atStepPose = gate.atStepPose })
		mount:set("Back")
		mount:set("Hand", true)
		model.Parent = nil
		mount:destroy()
		expect(gate.cancels).toBe(1)
		gate.open()
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		Choreo.release(model)
	end)

	it("lands at once when asked outside a step, with no atStepPose, or through a gate that runs at once", function()
		local model = buildRig()
		local animator = Choreo.get(model)
		local motor = motorOf(model)
		local hand, back = model:FindFirstChild("RightHand"), model:FindFirstChild(ROW.part)
		local gate = heldGate()
		local mount = WeaponMount.new(animator, model, { atStepPose = gate.atStepPose })
		mount:set("Back")
		expect(motor.Part0).toBe(back)
		mount:set("Hand")
		expect(motor.Part0).toBe(hand)
		expect(gate.asked).toBe(0)
		mount:destroy()

		local plain = WeaponMount.new(animator, model)
		plain:set("Back", true)
		plain:set("Hand", true)
		expect(motor.Part0).toBe(hand)
		plain:destroy()

		-- FrameClock with no render step runs the callback inside the call: nothing is left waiting.
		local now = WeaponMount.new(animator, model, {
			atStepPose = function(fn: () -> ()): () -> ()
				fn()
				return function() end
			end,
		})
		now:set("Back")
		now:set("Hand", true)
		expect(motor.Part0).toBe(hand)
		now:set("Back", true)
		expect(motor.Part0).toBe(back)
		now:destroy()
		Choreo.release(model)
	end)
end)
