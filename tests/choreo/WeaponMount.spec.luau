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
