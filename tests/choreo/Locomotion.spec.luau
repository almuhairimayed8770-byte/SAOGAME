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
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")

local FRAME = 1 / 60
local Config = ChoreoData.locomotion
local Sheath = ChoreoData.sheath
local DRAW = Config.clipPrefix .. Sheath.clips.draw
local SHEATHE = Config.clipPrefix .. Sheath.clips.sheathe
local HORIZONTAL = Config.clipPrefix .. "Horizontal"
local GUARD = Config.clipPrefix .. "Guard"
local DODGE = Config.clipPrefix .. "DodgeBack"
local SWORD = Weapons.byId("TrialistSword")
local ROW = WeaponModels.sheath(SWORD.category)

local function eventTime(clipId: string, kind: string): number
	for _, event in ClipLibrary.get(clipId).events do
		if event.kind == kind then
			return event.time
		end
	end
	error(clipId .. " has no " .. kind)
end

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

local world = Instance.new("Folder")
world.Name = "World"

-- A player rig whose sword the server's WeaponBuilder hung on the right hand (with its scabbard),
-- in a world folder. `armed` false leaves the sword off.
local function buildSwordRig(armed: boolean?)
	local model = Instance.new("Model")
	model.Name = "Player"
	model:SetAttribute("Rig", "PlayerR15")
	local parts = {}
	local function part(name)
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Size = Vector3.new(1, 1, 1)
		created.CFrame = CFrame.new(0, 3, 0)
		created.Position = Vector3.new(0, 3, 0)
		created.Parent = model
		parts[name] = created
		return created
	end
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name == WeaponModels.motorName then
			continue
		end
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Part0 = part(joint.part0)
		motor.Part1 = part(joint.part1)
		motor.C0 = RigBuilder.frameOf(joint.c0)
		motor.Parent = motor.Part1
	end
	model.PrimaryPart = parts.HumanoidRootPart
	if armed ~= false then
		WeaponBuilder.equip(model, SWORD)
	end
	model.Parent = world
	return model
end

local function swordMotor(model)
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

local function steps(animator, seconds: number)
	for _ = 1, math.ceil(seconds / FRAME - 1e-9) do
		animator:step(FRAME)
	end
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

describe("Locomotion: the sheathed sword", function()
	local function setup(drawn: boolean)
		local model = buildSwordRig()
		-- The server's attribute, read when the driver starts; the tracker carries it after that.
		model:SetAttribute("Drawn", drawn)
		local animator = Choreo.get(model)
		local state = still()
		state.drawn = drawn
		local driver = Locomotion.attach(animator, model, { footIK = false, tracker = trackerOf(state) })
		animator:step(FRAME)
		return model, animator, state, driver, swordMotor(model)
	end

	it("starts on the back over the sheathed Idle, with no clip", function()
		local model, animator, _state, driver, motor = setup(false)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		expect(motor.Transform == CFrame.identity).toBe(true)
		expect(handleOf(animator, Config.clipPrefix .. Config.clips.Idle).weight).toBe(1)
		expect(animator:isPlaying(DRAW)).toBe(false)
		expect(animator:isPlaying(SHEATHE)).toBe(false)
		driver:destroy()
		Choreo.release(model)
	end)

	it("a true target plays Draw, switches to the drawn set and takes the sword at WeaponDraw", function()
		local model, animator, state, driver, motor = setup(false)
		local seen = {}
		animator.events:Connect(function(clipId, event)
			if clipId == DRAW and event.kind == "WeaponDraw" then
				-- Locomotion's own handler ran first: the sword is already in the hand.
				table.insert(seen, motor.Part0)
			end
		end)
		state.drawn = true
		animator:step(FRAME)
		expect(animator:isPlaying(DRAW)).toBe(true)
		local draw = handleOf(animator, DRAW)
		local grab = eventTime(DRAW, "WeaponDraw")
		while draw.time + FRAME < grab do
			animator:step(FRAME)
			expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		end
		steps(animator, 2 * FRAME)
		expect(#seen).toBe(1)
		expect(seen[1]).toBe(model:FindFirstChild("RightHand"))
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		steps(animator, 1)
		expect(handleOf(animator, Config.clipPrefix .. Config.clips.IdleDrawn).weight).toBeCloseTo(1, 1e-6)
		state.speed = Config.runSpeed
		state.moveDir = Vector3.new(0, 0, -1)
		steps(animator, 0.5)
		expect(handleOf(animator, Config.clipPrefix .. Config.clips.RunDrawn).weight).toBeCloseTo(1, 1e-6)
		expect(handleOf(animator, Config.clipPrefix .. Config.clips.Run).weight).toBe(0)
		driver:destroy()
		Choreo.release(model)
	end)

	it("a false target plays Sheathe only after sheatheDelay and puts the sword back at WeaponSheathe", function()
		local model, animator, state, driver, motor = setup(true)
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		state.drawn = false
		steps(animator, Sheath.sheatheDelay - 2 * FRAME)
		expect(animator:isPlaying(SHEATHE)).toBe(false)
		steps(animator, 3 * FRAME)
		expect(animator:isPlaying(SHEATHE)).toBe(true)
		local sheathe = handleOf(animator, SHEATHE)
		local stow = eventTime(SHEATHE, "WeaponSheathe")
		while sheathe.time + FRAME < stow do
			animator:step(FRAME)
			expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		end
		steps(animator, 2 * FRAME)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		expect(motor.Transform == CFrame.identity).toBe(true)
		driver:destroy()
		Choreo.release(model)
	end)

	it(
		"an attack or a Guard played on the back takes the sword before its first frame is posed, with no Draw",
		function()
			for _, clipId in { HORIZONTAL, GUARD } do
				local model, animator, _state, driver, motor = setup(false)
				expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
				animator:play(clipId, { blendIn = 0 })
				animator:step(FRAME)
				expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
				-- The clip's own Weapon key is on the joint in that same step, not the pinned rest.
				expect(motor.Transform == CFrame.identity).toBe(false)
				expect(animator:isPlaying(DRAW)).toBe(false)
				driver:destroy()
				Choreo.release(model)
			end
		end
	)

	it(
		"a target that turns back before the grab leaves the sword on the back, though the Draw fades past it",
		function()
			local model, animator, state, driver, motor = setup(false)
			state.drawn = true
			animator:step(FRAME)
			local draw = handleOf(animator, DRAW)
			local grab = eventTime(DRAW, "WeaponDraw")
			-- Turn back while the fading Draw will still cross its WeaponDraw.
			while draw.time + Sheath.stopBlend * 0.5 < grab do
				animator:step(FRAME)
			end
			state.drawn = false
			local fired = false
			animator.events:Connect(function(clipId, event)
				if clipId == DRAW and event.kind == "WeaponDraw" then
					fired = true
				end
			end)
			steps(animator, 0.5)
			expect(fired).toBe(true)
			expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
			expect(animator:isPlaying(SHEATHE)).toBe(false)
			driver:destroy()
			Choreo.release(model)
		end
	)

	it(
		"a late event from a Draw or Sheathe stopped under a cover moves nothing; the new clip's own event does",
		function()
			for _, case in
				{
					{ drawn = false, clipId = DRAW, kind = "WeaponDraw", to = "RightHand" },
					{ drawn = true, clipId = SHEATHE, kind = "WeaponSheathe", to = ROW.part },
				}
			do
				local model, animator, state, driver, motor = setup(case.drawn)
				local destination = model:FindFirstChild(case.to)
				local at = eventTime(case.clipId, case.kind)
				state.drawn = not case.drawn
				local clip = nil
				for _ = 1, 120 do
					animator:step(FRAME)
					clip = handleOf(animator, case.clipId)
					if clip ~= nil then
						break
					end
				end
				expect(clip).toBeTruthy()
				-- A dodge a few frames before the event hides the arm, so the clip stops. The server
				-- refuses the dodge at once: the arm is free again and the clip starts over, while the
				-- stopped one still fades past its event.
				while clip.time + 3 * FRAME < at do
					animator:step(FRAME)
				end
				local dodge = animator:play(DODGE)
				animator:step(FRAME)
				expect(clip.stopping).toBe(true)
				animator:stop(dodge, 0.2)
				local staleFired = false
				animator.events:Connect(function(clipId, event)
					if clipId == case.clipId and event.kind == case.kind and not clip.done then
						staleFired = staleFired or clip.time >= at
					end
				end)
				-- The live clip's time when the sword arrives.
				local arrivedAt: number? = nil
				for _ = 1, 120 do
					animator:step(FRAME)
					if arrivedAt == nil and motor.Part0 == destination then
						local live = handleOf(animator, case.clipId)
						arrivedAt = if live ~= nil then live.time else math.huge
					end
				end
				expect(staleFired).toBe(true)
				expect(arrivedAt).toBeTruthy()
				expect(arrivedAt :: number >= at).toBe(true)
				expect(motor.Part0).toBe(destination)
				driver:destroy()
				Choreo.release(model)
			end
		end
	)

	it(
		"a turn or a stagger that hides the arm holds the Draw back; the sword changes hands once the arm is free",
		function()
			for _, cover in { "TurnLeft", "Stagger" } do
				local model, animator, state, driver, motor = setup(false)
				local coverId = Config.clipPrefix .. cover
				local underCover = 0
				animator.events:Connect(function(clipId, event)
					if
						clipId == DRAW
						and event.kind == "WeaponDraw"
						and motor.Part0 == model:FindFirstChild("RightHand")
					then
						-- The sword just changed hands: nothing may hide the arm now.
						for _, handle in animator.mixer:handles() do
							if handle.clipId == coverId and not handle.stopping and not handle.done then
								underCover += 1
							end
						end
					end
				end)
				local coverHandle = animator:play(coverId)
				state.drawn = true
				for _ = 1, 600 do
					if coverHandle.stopping or coverHandle.done then
						break
					end
					animator:step(FRAME)
					expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
				end
				expect(coverHandle.stopping or coverHandle.done).toBe(true)
				steps(animator, 1)
				expect(underCover).toBe(0)
				expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
				driver:destroy()
				Choreo.release(model)
			end
		end
	)

	it("the drawn sprint pose waits for the sword in the hand and fades in and out with SprintDrawn", function()
		local model, animator, state, driver, motor = setup(false)
		local weights = {}
		local setProcedural = animator.setProcedural
		animator.setProcedural = function(self, name, offsets, weight)
			if name == "drawnSprint" then
				table.insert(weights, weight or 0)
			end
			return setProcedural(self, name, offsets, weight)
		end
		state.speed = Config.sprintSpeed
		state.sprinting = true
		state.moveDir = Vector3.new(0, 0, -1)
		steps(animator, 0.6)
		expect(weights[#weights]).toBe(0)

		-- Lock-on while sprinting: the Draw plays over SprintDrawn. Until the Draw has handed the
		-- sword over and let go of the arm, the pose stays off, so the hand meets the hilt.
		state.drawn = true
		local grabbed = false
		animator.events:Connect(function(clipId, event)
			if clipId == DRAW and event.kind == "WeaponDraw" then
				grabbed = true
			end
		end)
		for _ = 1, 120 do
			animator:step(FRAME)
			expect(weights[#weights]).toBe(0)
			if grabbed then
				break
			end
		end
		expect(grabbed).toBe(true)
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))

		local function largestStep(from: number): number
			local largest = 0
			for index = from + 1, #weights do
				largest = math.max(largest, math.abs(weights[index] - weights[index - 1]))
			end
			return largest
		end
		local mark = #weights
		steps(animator, 1.5)
		expect(weights[#weights]).toBeCloseTo(ChoreoData.additiveWeights.drawnSprint, 1e-6)
		expect(largestStep(mark)).toBeLessThan(0.15)

		-- The tag runs out mid-sprint: the pose fades with SprintDrawn instead of dropping at once.
		mark = #weights
		state.drawn = false
		steps(animator, 0.3)
		expect(weights[#weights]).toBe(0)
		expect(largestStep(mark)).toBeLessThan(0.15)
		driver:destroy()
		Choreo.release(model)
	end)

	it("a dodge does not draw", function()
		local model, animator, _state, driver, motor = setup(false)
		animator:play(DODGE, { blendIn = 0 })
		steps(animator, 0.2)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		expect(motor.Transform == CFrame.identity).toBe(true)
		expect(animator:isPlaying(DRAW)).toBe(false)
		driver:destroy()
		Choreo.release(model)
	end)

	it("nothing starts while the fighter is dead", function()
		local model, animator, state, driver, motor = setup(false)
		model:SetAttribute("State", "Dead")
		state.drawn = true
		steps(animator, 0.5)
		expect(animator:isPlaying(DRAW)).toBe(false)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		driver:destroy()
		Choreo.release(model)
	end)

	it("each walk, Run and Sprint keeps time with its drawn twin", function()
		local model, animator, state, driver = setup(false)
		state.speed = Config.walkSpeed
		state.moveDir = Vector3.new(0, 0, -1)
		steps(animator, 0.7)
		state.drawn = true
		steps(animator, 1.3)
		for _, name in { "WalkForward", "WalkBack", "WalkLeft", "WalkRight", "Run", "Sprint" } do
			local plain = handleOf(animator, Config.clipPrefix .. Config.clips[name])
			local drawn = handleOf(animator, Config.clipPrefix .. Config.clips[name .. "Drawn"])
			expect(plain.time).toBeCloseTo(drawn.time, 1e-9)
		end
		driver:destroy()
		Choreo.release(model)
	end)

	it("a sword that arrives later snaps to the target with no clip", function()
		local fire, restore = recordConnections()
		local model = buildSwordRig(false)
		local animator = Choreo.get(model)
		local state = still()
		state.drawn = false
		local driver = Locomotion.attach(animator, model, { footIK = false, tracker = trackerOf(state) })
		animator:step(FRAME)
		WeaponBuilder.equip(model, SWORD)
		local motor = swordMotor(model)
		fire(model, "DescendantAdded", motor)
		animator:step(FRAME)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		steps(animator, 1)
		expect(animator:isPlaying(SHEATHE)).toBe(false)
		expect(animator:isPlaying(DRAW)).toBe(false)
		driver:destroy()
		Choreo.release(model)
		restore()
	end)

	it("destroy puts the sword back in the hand", function()
		local model, animator, _state, driver, motor = setup(false)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		driver:destroy()
		expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
		animator:step(FRAME)
		expect(motor.Transform == CFrame.identity).toBe(false)
		Choreo.release(model)
	end)
end)

describe("Locomotion: the Drawn and State attributes", function()
	-- Stands in for GetAttributeChangedSignal (Lune's instances have no signals): the test fires a
	-- change by hand. Returns the signal maker, fire, and the count of live connections.
	local function attributeSignals()
		local connections = {}
		local function signalOf(_instance, name)
			return {
				Connect = function(_, fn)
					local entry = { name = name, fn = fn, connected = true }
					table.insert(connections, entry)
					return {
						Disconnect = function()
							entry.connected = false
						end,
					}
				end,
			}
		end
		local function fire(name)
			for _, entry in connections do
				if entry.connected and entry.name == name then
					entry.fn()
				end
			end
		end
		local function live(): number
			local total = 0
			for _, entry in connections do
				if entry.connected then
					total += 1
				end
			end
			return total
		end
		return signalOf, fire, live
	end

	it("follows them through their change signals and reads neither on a step", function()
		local model = buildSwordRig()
		model:SetAttribute("Drawn", false)
		local animator = Choreo.get(model)
		local proxy, counts = countCalls(model)
		local signalOf, fire, live = attributeSignals()
		local driver = Locomotion.new(animator, proxy, { footIK = false, attributeSignal = signalOf })
		local motor = swordMotor(model)
		local state = still()
		state.drawn = false
		-- Steps the driver and the animator; returns the attribute reads made meanwhile.
		local function run(seconds: number): number
			local before = counts.GetAttribute or 0
			for _ = 1, math.ceil(seconds / FRAME - 1e-9) do
				driver:update(FRAME, state)
				animator:step(FRAME)
			end
			return (counts.GetAttribute or 0) - before
		end
		expect(run(0.5)).toBe(0)
		expect(live()).toBe(2)
		expect(driver:serverDrawn()).toBe(false)

		-- The server draws: the driver sees it when the signal fires, not before.
		model:SetAttribute("Drawn", true)
		expect(driver:serverDrawn()).toBe(false)
		fire("Drawn")
		expect(driver:serverDrawn()).toBe(true)
		model:SetAttribute("Drawn", false)
		fire("Drawn")

		-- Dead holds the sword where it is from the moment its signal fires.
		model:SetAttribute("State", "Dead")
		fire("State")
		state.drawn = true
		expect(run(0.5)).toBe(0)
		expect(animator:isPlaying(DRAW)).toBe(false)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		model:SetAttribute("State", "Idle")
		fire("State")
		expect(run(FRAME)).toBe(0)
		expect(animator:isPlaying(DRAW)).toBe(true)

		driver:destroy()
		expect(live()).toBe(0)
		Choreo.release(model)
	end)

	it("a remote player's tracker takes Drawn from the driver, not from the character", function()
		local reads = 0
		local humanoid = { MoveDirection = Vector3.zero, FloorMaterial = Enum.Material.Plastic }
		local root = { AssemblyLinearVelocity = Vector3.zero, Position = Vector3.zero }
		local character = {
			PrimaryPart = root,
			FindFirstChildOfClass = function()
				return humanoid
			end,
			FindFirstChild = function()
				return root
			end,
			GetAttribute = function()
				reads += 1
				return nil
			end,
		}
		local drawn = true
		local tracker = Locomotion.humanoidTracker(character :: any, function(): boolean
			return drawn
		end)
		expect(tracker(FRAME).drawn).toBe(true)
		drawn = false
		expect(tracker(FRAME).drawn).toBe(false)
		expect(reads).toBe(0)
		-- With no source it reads the attribute; a missing one means sheathed.
		expect(Locomotion.humanoidTracker(character :: any)(FRAME).drawn).toBe(false)
		expect(reads).toBe(1)
	end)
end)
