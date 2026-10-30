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
Harness.stubService("RunService", {
	RenderStepped = fakeSignal(),
	Heartbeat = fakeSignal(),
	PreSimulation = fakeSignal(),
	-- Choreo's rig step (bound before every reader of a pose, D-211): the spec steps the rigs itself.
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
local LocomotionState = Harness.load("src/client/choreo/LocomotionState")
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

	it("walks an enemy rig at its drawn body's speed while the body is drawn away from its root (D-200)", function()
		local model = buildRig("Boar")
		local root = model.PrimaryPart :: BasePart
		root.CFrame = CFrame.new()
		local animator = Choreo.get(model)
		local state = still()
		local driver = Locomotion.attach(animator, model, { tracker = trackerOf(state) })
		-- A rush's drawing, armed after the rig was watched: its hook runs first each step.
		local drawnAt: Vector3? = nil
		local unhook = animator:onStep(function()
			local at = drawnAt
			animator:setBodyOffset(if at ~= nil then root.CFrame:Inverse() * CFrame.new(at) else nil)
		end)
		local walk = handleOf(animator, ChoreoData.rigs.Boar.walk)
		local walkSpeed = Rigs.Boar.walkSpeed
		animator:step(FRAME) -- the rig stands on its root first
		-- The drawn body runs on ahead of its late root at the rush speed, the root standing.
		local rush = 2 * walkSpeed
		drawnAt = Vector3.zero
		for _ = 1, 3 do
			drawnAt = (drawnAt :: Vector3) + Vector3.new(0, 0, -rush * FRAME)
			animator:step(FRAME)
			expect(walk.targetWeight).toBeCloseTo(1, 1e-3)
			expect(walk.speed).toBeCloseTo(2, 1e-3)
		end
		-- The late root still runs on at the rush speed; the drawn body stands at the wall.
		state.speed = rush
		state.moveDir = Vector3.new(0, 0, -1)
		for _ = 1, 3 do
			root.CFrame = root.CFrame * CFrame.new(0, 0, -rush * FRAME)
			animator:step(FRAME)
			expect(walk.targetWeight).toBe(0)
		end
		-- The drawn body moves at half the walk speed while its root stands.
		state.speed = 0
		state.moveDir = Vector3.zero
		for _ = 1, 3 do
			drawnAt = (drawnAt :: Vector3) + Vector3.new(0, 0, -walkSpeed / 2 * FRAME)
			animator:step(FRAME)
			expect(walk.targetWeight).toBeCloseTo(0.5, 1e-3)
			expect(walk.speed).toBeCloseTo(0.5, 1e-3)
		end
		-- Back on its root: the root's own state again.
		drawnAt = nil
		animator:step(FRAME)
		expect(walk.targetWeight).toBe(0)
		unhook()
		driver:destroy()
		Choreo.release(model)
	end)

	it("hands the tracker's state back untouched while no body is drawn away from its root", function()
		local model = buildRig("Boar")
		local follow = Locomotion.drawnTracker(Choreo.get(model), model)
		local state = still()
		state.speed = 9
		for _ = 1, 3 do
			expect(follow(FRAME, state)).toBe(state)
		end
		-- An animator with no body offset at all (a stand-in) is never followed.
		local plain = Locomotion.drawnTracker({}, model)
		expect(plain(FRAME, state)).toBe(state)
		Choreo.release(model)
	end)

	it("starts an enemy rig's idle and walk loops at the phase it is given", function()
		local model = buildRig("Kobold")
		local animator = Choreo.get(model)
		local driver = Locomotion.attach(animator, model, { tracker = trackerOf(still()), phase = 0.25 })
		local idle = handleOf(animator, ChoreoData.rigs.Kobold.idle)
		local walk = handleOf(animator, ChoreoData.rigs.Kobold.walk)
		expect(idle.time).toBeCloseTo(0.25 * idle.clip.duration, 1e-9)
		expect(walk.time).toBeCloseTo(0.25 * walk.clip.duration, 1e-9)
		driver:destroy()
		Choreo.release(model)
	end)

	it("gives one id the same idle phase every time and spreads ids in a row round the loop", function()
		for id = -3, 64 do
			local phase = Locomotion.idlePhase(id)
			expect(phase >= 0 and phase < 1).toBe(true)
			expect(Locomotion.idlePhase(id)).toBe(phase)
		end
		-- A herd spawns with ids in a row: no two of eight in a row share a phase.
		for first = 1, 64 do
			local phases = {}
			for id = first, first + 7 do
				table.insert(phases, Locomotion.idlePhase(id))
			end
			table.sort(phases)
			local gap = phases[1] + 1 - phases[#phases]
			for index = 2, #phases do
				gap = math.min(gap, phases[index] - phases[index - 1])
			end
			expect(gap > 1 / 24).toBe(true)
		end
	end)

	it("two rigs of one herd roar apart, each once a loop: the hidden fallback idle is silent", function()
		local roars: { [number]: { number } } = {}
		local rigs = {}
		for id = 1, 2 do
			local model = buildRig("Kobold")
			local animator = Choreo.get(model)
			roars[id] = {}
			local clock = 0
			animator.events:Connect(function(_clipId, event)
				if event.kind == "Sfx" then
					table.insert(roars[id], clock)
				end
			end)
			local driver =
				Locomotion.attach(animator, model, { tracker = trackerOf(still()), phase = Locomotion.idlePhase(id) })
			table.insert(rigs, {
				model = model,
				animator = animator,
				driver = driver,
				tick = function()
					clock += FRAME
					animator:step(FRAME)
				end,
			})
		end
		local loop = ClipLibrary.get(ChoreoData.rigs.Kobold.idle).duration
		for _ = 1, math.floor(2 * loop / FRAME) do
			for _, rig in rigs do
				rig.tick()
			end
		end
		expect(#roars[1]).toBe(2)
		expect(#roars[2]).toBe(2)
		expect(math.abs(roars[1][1] - roars[2][1]) > loop / 24).toBe(true)
		for _, rig in rigs do
			rig.driver:destroy()
			Choreo.release(rig.model)
		end
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
		state.speed = Config.stride.groundSpeed.Run
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
		state.speed = Config.stride.groundSpeed.RunDrawn
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
		"an attack or a Parry played on the back takes the sword before its first frame is posed, with no Draw",
		function()
			for _, clipId in { HORIZONTAL, Config.clipPrefix .. "Parry" } do
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
		"a Guard played on the back waits for a Draw over it: the sword leaves the back at its WeaponDraw (D-420)",
		function()
			local model, animator, _state, driver, motor = setup(false)
			animator:play(GUARD, { blendIn = 0 })
			animator:step(FRAME)
			-- No snap off the back with the arm at the side: the Draw plays over the guard instead.
			expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
			expect(animator:isPlaying(DRAW)).toBe(true)
			local draw = handleOf(animator, DRAW)
			expect(draw.priority).toBe(Sheath.overPriority)
			expect(draw.priority > handleOf(animator, GUARD).priority).toBe(true)
			local grab = eventTime(DRAW, "WeaponDraw")
			while draw.time + FRAME < grab do
				animator:step(FRAME)
				expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
			end
			steps(animator, 2 * FRAME)
			expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
			-- Past sheath.handOverTime the Draw blends out into the guard's own pose.
			while draw.time < Sheath.handOverTime do
				animator:step(FRAME)
			end
			animator:step(FRAME)
			expect(draw.stopping).toBe(true)
			expect(draw.blendOut).toBe(Sheath.handOverBlend)
			steps(animator, Sheath.handOverBlend + FRAME)
			expect(animator:isPlaying(DRAW)).toBe(false)
			expect(animator:isPlaying(GUARD)).toBe(true)
			expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
			driver:destroy()
			Choreo.release(model)
		end
	)

	it("a target that turns back before the grab leaves the sword on the back: the Draw fades where it was", function()
		local model, animator, state, driver, motor = setup(false)
		state.drawn = true
		animator:step(FRAME)
		local draw = handleOf(animator, DRAW)
		local grab = eventTime(DRAW, "WeaponDraw")
		-- Turn back just before the grab: played on through its fade, the Draw would cross it.
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
		animator:step(FRAME)
		-- A cut back: stopped over sheath.cutBackBlend with its clock held (Mixer.hold).
		expect(draw.stopping).toBe(true)
		expect(draw.blendOut).toBe(Sheath.cutBackBlend)
		local heldAt = draw.time
		steps(animator, 0.5)
		expect(draw.time).toBe(heldAt)
		expect(fired).toBe(false)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
		expect(animator:isPlaying(SHEATHE)).toBe(false)
		driver:destroy()
		Choreo.release(model)
	end)

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

	it("a weightless clip (a Land on the move) does not hold the Draw back", function()
		local model, animator, state, driver, motor = setup(false)
		local land = animator:play(Config.clipPrefix .. Config.clips.Land, { weight = 0 })
		state.drawn = true
		local swapped = false
		for _ = 1, 600 do
			animator:step(FRAME)
			if motor.Part0 == model:FindFirstChild("RightHand") then
				swapped = true
				break
			end
		end
		expect(swapped).toBe(true)
		-- The sword changed hands before the weightless Land ended.
		expect(land.done).toBe(false)
		driver:destroy()
		Choreo.release(model)
	end)

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

		-- The tag runs out mid-sprint: the sword is still in the hand, so the drawn set and the pose
		-- hold through the sheathe delay, and the pose gives way to the Sheathe as that fades in over
		-- the arm (at most the eased blend in's own step a frame), never dropping at once.
		mark = #weights
		state.drawn = false
		steps(animator, Sheath.sheatheDelay - 2 * FRAME)
		expect(weights[#weights]).toBeCloseTo(ChoreoData.additiveWeights.drawnSprint, 1e-6)
		local blendIn = ClipLibrary.get(SHEATHE).blendIn :: number
		steps(animator, 2 * FRAME + blendIn + 2 * FRAME)
		expect(weights[#weights]).toBe(0)
		expect(largestStep(mark)).toBeLessThan(
			(math.pi / 2) * FRAME / blendIn * ChoreoData.additiveWeights.drawnSprint + 0.01
		)
		driver:destroy()
		Choreo.release(model)
	end)

	it("keeps the drawn set while the sword is in the hand, until the Sheathe has faded in over the arm", function()
		local model, animator, state, driver, motor = setup(true)
		local run = Config.clipPrefix .. Config.clips.Run
		local runDrawn = Config.clipPrefix .. Config.clips.RunDrawn
		state.speed = Config.stride.groundSpeed.RunDrawn
		state.moveDir = Vector3.new(0, 0, -1)
		steps(animator, 0.5)
		expect(handleOf(animator, runDrawn).weight).toBeCloseTo(1, 1e-6)
		-- The sheathed Run pumps an empty sword arm: with the blade still in the hand it swung the
		-- tip about through the sheathe delay and again under the Sheathe's blend in.
		state.drawn = false
		local sheathe = nil
		local frames = 0
		while frames < 120 do
			animator:step(FRAME)
			frames += 1
			sheathe = handleOf(animator, SHEATHE)
			if sheathe ~= nil and sheathe.fade >= 1 then
				break
			end
			expect(motor.Part0).toBe(model:FindFirstChild("RightHand"))
			expect(handleOf(animator, run).weight).toBe(0)
			expect(handleOf(animator, runDrawn).weight).toBeCloseTo(1, 1e-6)
		end
		expect(sheathe).never.toBeNil()
		expect(frames * FRAME).toBeGreaterThan(Sheath.sheatheDelay)
		-- Then the sheathed set comes in under the Sheathe, and is the whole base by the stow.
		local stow = eventTime(SHEATHE, "WeaponSheathe")
		while sheathe.time + FRAME < stow do
			animator:step(FRAME)
		end
		expect(handleOf(animator, run).weight).toBeCloseTo(1, 1e-6)
		expect(handleOf(animator, runDrawn).weight).toBe(0)
		steps(animator, 2 * FRAME)
		expect(motor.Part0).toBe(model:FindFirstChild(ROW.part))
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

	it("each walk, Run and Sprint keeps time with its drawn twin while both show", function()
		local model, animator, state, driver = setup(false)
		state.speed = Config.walkSpeed
		state.moveDir = Vector3.new(0, 0, -1)
		steps(animator, 0.7)
		state.drawn = true
		-- Frame by frame through the set crossfade: a clip with no weight keeps its own clock
		-- until it is about to show, so only pairs that both show are compared.
		local compared = 0
		for _ = 1, math.ceil(1.3 / FRAME) do
			animator:step(FRAME)
			for _, name in { "WalkForward", "WalkBack", "WalkLeft", "WalkRight", "Run", "Sprint" } do
				local plain = handleOf(animator, Config.clipPrefix .. Config.clips[name])
				local drawn = handleOf(animator, Config.clipPrefix .. Config.clips[name .. "Drawn"])
				if plain.weight > 0 and drawn.weight > 0 then
					expect(plain.time).toBeCloseTo(drawn.time, 1e-9)
					compared += 1
				end
			end
		end
		expect(compared).toBeGreaterThan(0)
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

describe("Locomotion: the gait clock", function()
	-- A player rig walking straight along `moveDir` at `speed` for `seconds`.
	local function walker()
		local model = buildRig("PlayerR15")
		local animator = Choreo.get(model)
		local locomotion = Locomotion.new(animator, model, { footIK = false }) :: any
		local function walk(moveDir: Vector3, speed: number, seconds: number, extra: { [string]: any }?)
			for _ = 1, math.ceil(seconds / FRAME - 1e-9) do
				local state: any = { moveDir = moveDir, speed = speed, sprinting = false, grounded = true, turning = 0 }
				for key, value in extra or {} do
					state[key] = value
				end
				locomotion:update(FRAME, state)
				animator:step(FRAME)
			end
		end
		return locomotion, animator, walk, model
	end
	local FORWARD = Vector3.new(0, 0, -1)

	-- Cycles the shared phase moves over one frame.
	local function advance(locomotion: any, walk: any, moveDir: Vector3, speed: number): number
		local before = locomotion.gaitPhase
		walk(moveDir, speed, FRAME)
		return (locomotion.gaitPhase - before) % 1
	end

	it("holds the shared phase and every gait clock through hit-stop", function()
		local locomotion, animator, walk, model = walker()
		walk(FORWARD, Config.walkSpeed, 1)
		local phase = locomotion.gaitPhase
		local handle = locomotion.handles.WalkForward
		local clock = handle.time
		animator:hitStop(4)
		walk(FORWARD, Config.walkSpeed, 2 * FRAME)
		expect(locomotion.gaitPhase).toBe(phase)
		expect(handle.time).toBeCloseTo(clock, 1e-9)
		walk(FORWARD, Config.walkSpeed, 4 * FRAME)
		expect(locomotion.gaitPhase).never.toBe(phase)
		locomotion:destroy()
		Choreo.release(model)
	end)

	it("under the mixer's time scale the phase still covers the root's real travel", function()
		local locomotion, animator, walk, model = walker()
		local speed = Config.stride.groundSpeed.WalkForward * 0.9
		walk(FORWARD, speed, 1)
		local full = advance(locomotion, walk, FORWARD, speed)
		local rate = locomotion.handles.WalkForward.speed
		-- Dev slow motion: the clips run twice as fast on the half-speed clock.
		animator.mixer:setTimeScale(0.5)
		local half = advance(locomotion, walk, FORWARD, speed)
		expect(full).toBeGreaterThan(0)
		expect(half).toBeCloseTo(full, 1e-9)
		expect(locomotion.handles.WalkForward.speed).toBeCloseTo(rate * 2, 1e-9)
		-- A frozen clock (an Art hold) holds the phase.
		animator.mixer:setTimeScale(0)
		expect(advance(locomotion, walk, FORWARD, speed)).toBe(0)
		locomotion:destroy()
		Choreo.release(model)
	end)

	it("a root slowed with its clips (clockScale: a slowed capture's own body) blends its 1x gait", function()
		-- At 1x: a run, and a turn the blend sees as one (stride.turnYawRate) once the yaw moves.
		local reference, _, runAt1x, referenceModel = walker()
		runAt1x(FORWARD, Config.runSpeed, 1)
		local run = reference.handles.Run.weight
		local full = advance(reference, runAt1x, FORWARD, Config.runSpeed)
		expect(run).toBeGreaterThan(0.9)
		-- The local body in a 0.25x capture moves a quarter as fast on a quarter-speed clock: the
		-- same run, not the walk a quarter of the speed would pick, its phase stepping a quarter as far.
		local locomotion, animator, walk, model = walker()
		animator.mixer:setTimeScale(0.25)
		local slowed = { clockScale = 0.25 }
		walk(FORWARD, Config.runSpeed * 0.25, 1, slowed)
		expect(locomotion.handles.Run.weight).toBeCloseTo(run, 1e-6)
		expect(locomotion.handles.WalkForward.weight).toBeCloseTo(reference.handles.WalkForward.weight, 1e-6)
		local before = locomotion.gaitPhase
		walk(FORWARD, Config.runSpeed * 0.25, FRAME, slowed)
		expect((locomotion.gaitPhase - before) % 1).toBeCloseTo(full * 0.25, 1e-9)
		-- Its turn too: a quarter of a turn the blend sees as one (past stride.turnYawRate at 1x)
		-- still counts, so Run keeps its whole stride (runAlong 1) on a move off the facing.
		local root = (model :: any).HumanoidRootPart
		local degreesPerFrame = Config.stride.turnYawRate * 1.5 * 0.25 * FRAME
		for _ = 1, 3 do
			root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(degreesPerFrame), 0)
			walk(Vector3.new(1, 0, -1).Unit, Config.walkSpeed * 0.25, FRAME, slowed)
		end
		expect(locomotion.runAlong).toBe(1)
		-- Without clockScale (a remote rig: its root runs on real time) the speed is read as given.
		local remote, remoteAnimator, remoteWalk, remoteModel = walker()
		remoteAnimator.mixer:setTimeScale(0.25)
		remoteWalk(FORWARD, Config.runSpeed * 0.25, 1)
		expect(remote.handles.Run.weight).toBeLessThan(0.5)
		for _, pair in { { reference, referenceModel }, { locomotion, model }, { remote, remoteModel } } do
			pair[1]:destroy()
			Choreo.release(pair[2])
		end
	end)

	it("plays a walk no faster than stride.rateCeiling past its ground speed", function()
		local locomotion, _, walk, model = walker()
		-- Straight back the walk carries every speed (no Run behind the facing).
		walk(-FORWARD, 26, 1)
		local handle = locomotion.handles.WalkBack
		expect(handle.weight).toBeCloseTo(1, 1e-6)
		expect(handle.speed).toBeCloseTo(Config.stride.rateCeiling, 1e-6)
		locomotion:destroy()
		Choreo.release(model)
	end)

	it("standing puts the shared phase back at stride.startPhase, so every start steps off alike", function()
		local locomotion, _, walk, model = walker()
		walk(FORWARD, Config.walkSpeed, 1.3)
		expect(locomotion.gaitPhase).never.toBeCloseTo(Config.stride.startPhase, 1e-3)
		-- Long enough for the walk's weight to reach zero.
		walk(Vector3.zero, 0, 1)
		expect(locomotion.gaitPhase).toBe(Config.stride.startPhase)
		locomotion:destroy()
		Choreo.release(model)
	end)

	it("holds a walk that still shows at stride.rateFloor below its floor speed", function()
		local locomotion, animator, walk, model = walker()
		walk(FORWARD, Config.stride.groundSpeed.WalkForward, 1)
		-- Frozen weights (hit-stop): the walk still shows whole at a speed far under its floor.
		animator:hitStop(4)
		walk(FORWARD, Config.stride.groundSpeed.WalkForward * Config.stride.rateFloor * 0.5, FRAME)
		expect(locomotion.handles.WalkForward.weight).toBeCloseTo(1, 1e-6)
		expect(locomotion.handles.WalkForward.speed).toBeCloseTo(Config.stride.rateFloor, 1e-6)
		locomotion:destroy()
		Choreo.release(model)
	end)

	it("moving with no stick (a coast, a shove) keeps the last move direction", function()
		local locomotion, _, walk, model = walker()
		walk(-FORWARD, 3, 1)
		expect(locomotion.handles.WalkBack.targetWeight).toBeCloseTo(1, 1e-6)
		walk(Vector3.zero, 3, 0.5)
		expect(locomotion.handles.WalkBack.targetWeight).toBeCloseTo(1, 1e-6)
		expect(locomotion.handles.WalkForward.targetWeight).toBe(0)
		locomotion:destroy()
		Choreo.release(model)
	end)

	it("gives the two-step stop the phase and the settle points of the last move", function()
		local locomotion, _, walk, model = walker()
		walk(-FORWARD, 3, 0.5)
		local into = { phase = -1, leftStep = -1, leftAfter = -1, rightStep = -1, rightAfter = -1 }
		locomotion:stopGait(into)
		expect(into.phase).toBe(locomotion.gaitPhase)
		local leftStep, leftAfter, rightStep, rightAfter = LocomotionState.settlePoints(-1, 0, false)
		expect(into.leftStep).toBe(leftStep)
		expect(into.leftAfter).toBeCloseTo(leftAfter, 1e-9)
		expect(into.rightStep).toBeCloseTo(rightStep, 1e-9)
		expect(into.rightAfter).toBeCloseTo(rightAfter, 1e-9)
		locomotion:destroy()
		Choreo.release(model)
	end)

	it("a turn in place gives way to the first steps", function()
		local locomotion, animator, walk, model = walker()
		local turnId = Config.clipPrefix .. Config.clips.TurnLeft
		walk(Vector3.zero, 0, 0.5)
		-- Lock-on swings the facing with no stick: the turn clip plays.
		walk(Vector3.zero, 0, FRAME, { turning = Config.turnInPlaceDegrees + 10 })
		expect(handleOf(animator, turnId)).never.toBeNil()
		-- The stick goes forward and the root moves well inside the turn clip.
		walk(FORWARD, Config.walkSpeed, FRAME)
		expect(handleOf(animator, turnId)).toBeNil()
		walk(FORWARD, Config.walkSpeed, ChoreoData.oneShotBlendIn + FRAME)
		for _, handle in animator.mixer:handles() do
			expect(handle.clipId == turnId and handle.fade > 0).toBe(false)
		end
		locomotion:destroy()
		Choreo.release(model)
	end)

	it("a landing on the move plays no Land, and a standing Land gives way to the first steps", function()
		local locomotion, animator, walk, model = walker()
		local landId = Config.clipPrefix .. Config.clips.Land
		local fallId = Config.clipPrefix .. Config.clips.Fall
		local fall = { grounded = false, verticalVelocity = -10 }
		local landed = { fallHeight = Config.landing.fullSquashHeight }
		walk(FORWARD, Config.walkSpeed, 1)
		walk(FORWARD, Config.walkSpeed, 0.3, fall)
		expect(handleOf(animator, fallId)).never.toBeNil()
		walk(FORWARD, Config.walkSpeed, FRAME, landed)
		-- Land plays for its sounds, with no weight on the limbs.
		local moving = handleOf(animator, landId)
		expect(moving).never.toBeNil()
		expect(moving.weight).toBe(0)
		expect(handleOf(animator, fallId)).toBeNil()
		-- Standing, the squash plays until the stick moves the root.
		walk(Vector3.zero, 0, 1)
		walk(Vector3.zero, 0, 0.3, fall)
		walk(Vector3.zero, 0, FRAME, landed)
		expect(handleOf(animator, landId)).never.toBeNil()
		walk(FORWARD, Config.walkSpeed, FRAME)
		expect(handleOf(animator, landId)).toBeNil()
		locomotion:destroy()
		Choreo.release(model)
	end)

	it("a remote player's tracker calls a run a run and a sprint a sprint", function()
		local humanoid = { MoveDirection = Vector3.new(0, 0, -1), FloorMaterial = Enum.Material.Plastic }
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
				return nil
			end,
		}
		local tracker = Locomotion.humanoidTracker(character :: any)
		local middle = (Config.runSpeed + Config.sprintSpeed) / 2
		for _, case in
			{
				{ Config.runSpeed * 1.02, false },
				{ middle - 0.1, false },
				{ middle + 0.1, true },
				{ Config.sprintSpeed, true },
			}
		do
			root.AssemblyLinearVelocity = Vector3.new(0, 0, -case[1])
			expect((tracker(FRAME) :: any).sprinting).toBe(case[2])
		end
	end)
end)

describe("Locomotion's jump", function()
	it("the fall takes over when the jump clip ends, even if another clip ends first", function()
		-- A flinch or a guard hit that ends during the jump fires the animator's finished first; it
		-- must not use up the jump's handoff to the fall.
		local fall = Config.clipPrefix .. "Fall"
		ClipLibrary.get(fall) -- loaded first: a handler that loads a module yields in Lune
		for _, other in { false, "FlinchFront", "GuardHit" } do
			local model = buildRig("PlayerR15")
			local animator = Choreo.get(model)
			local state = still()
			local driver = Locomotion.attach(animator, model, { footIK = false, tracker = trackerOf(state) })
			for _ = 1, 30 do
				animator:step(FRAME)
			end
			state.grounded = false
			state.verticalVelocity = Config.jumpVelocity + 10
			animator:step(FRAME)
			state.verticalVelocity = 0
			if other then
				local clip = ClipLibrary.get(Config.clipPrefix .. other)
				-- It must end inside the jump clip for the case to mean anything.
				expect(clip.duration < ClipLibrary.get(Config.clipPrefix .. "Jump").duration).toBe(true)
				animator:play(clip.id)
			end
			-- The jump clip (0.4 s) ends well inside the second in the air.
			for _ = 1, 60 do
				animator:step(FRAME)
			end
			expect(handleOf(animator, fall)).toBeTruthy()
			driver:destroy()
			Choreo.release(model)
		end
	end)

	it("a hop that lands before the jump clip ends leaves no handoff behind", function()
		local model = buildRig("PlayerR15")
		local animator = Choreo.get(model)
		local state = still()
		local driver = Locomotion.attach(animator, model, { footIK = false, tracker = trackerOf(state) })
		animator:step(FRAME)
		local baseline = animator.finished:ConnectionCount()
		for _ = 1, 5 do
			state.grounded = false
			state.verticalVelocity = Config.jumpVelocity + 10
			animator:step(FRAME)
			state.verticalVelocity = 0
			for _ = 1, 6 do
				animator:step(FRAME)
			end
			state.grounded = true
			for _ = 1, 60 do
				animator:step(FRAME)
			end
		end
		expect(animator.finished:ConnectionCount()).toBe(baseline)
		-- And a driver that goes while a jump is in the air leaves none either.
		state.grounded = false
		state.verticalVelocity = Config.jumpVelocity + 10
		animator:step(FRAME)
		driver:destroy()
		expect(animator.finished:ConnectionCount()).toBe(baseline)
		Choreo.release(model)
	end)
end)
