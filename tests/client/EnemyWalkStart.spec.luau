--!strict
--[[
	An enemy's walk start keeps its planted feet on the field (section 21 gate line 4: no sliding
	foot in any clip; AG 392(b): the boar's hooves slid 0.13-0.34 a frame after 0.15 s and stood
	0.06-0.10 in the floor as it set off, on all three takes, where the kobold's held). D-541.

	Played the way the game plays it: the real EnemyService (Charger and Brute brains at the AI's
	tick, the frame pass, the yaw align) spawns the enemy held 15 studs from a player, its facing
	`off` degrees off the player, over BoarHooks.spec's "studio" Humanoid (its walk settled once a
	frame, reaching its WalkSpeed at 1320 studs/s², braking 0.672 a 1/240 s step); a client copy
	(RigBuilder) draws it through Choreo with Locomotion's RigDriver attached as Replication attaches
	it (its default tracker reads the replicated root's velocity). Each 60 Hz frame: the client
	step, the server frame, then the replicated root. The row a frame shows is that step's joints on
	the root physics just moved (Choreo writes the joints before physics; the screen is the part
	CFrames after it). The enemy is let go and its feet are read from the frame its root first moves.

	Measured over the walk start (0.15 to 0.5 s after the root first moves, the PC's window): each
	foot's least-moving corner grounded through a frame (within stride.contact of the field: the
	slide ClipAudit and the PC measure) and the lowest corner of any foot.
	Assumes the client's root and velocity are the server's each frame (no interpolation lag) and a
	rigid yaw (AlignOrientation RigidityEnabled). The 144 Hz client is a Studio line.
]]
local function fakeSignal()
	local signal = {}
	function signal:Connect()
		return { Disconnect = function() end }
	end
	return signal
end
Harness.stubService("CollectionService", {
	AddTag = function(_self, instance, tag)
		instance:AddTag(tag)
	end,
	RemoveTag = function(_self, instance, tag)
		instance:RemoveTag(tag)
	end,
	HasTag = function(_self, instance, tag)
		return instance:HasTag(tag)
	end,
})
Harness.stubService("RunService", {
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
	RenderStepped = fakeSignal(),
	Heartbeat = fakeSignal(),
	PreSimulation = fakeSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local EntityService = Harness.load("src/server/services/EntityService")
local CombatService = Harness.load("src/server/services/CombatService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local AI = Harness.load("src/shared/data/ai")
local Dev = Harness.load("src/shared/data/dev")
local Rigs = Harness.load("src/shared/data/rigs")
local Playground = Harness.load("src/shared/data/playground")
local ChoreoData = Harness.load("src/shared/data/choreo")
local CollectionService = Harness.game():GetService("CollectionService")

local clientNow = 0
local Choreo = Harness.load("src/client/choreo/Choreo")
Choreo.configure({
	now = function()
		return clientNow
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
local Locomotion = Harness.load("src/client/choreo/Locomotion")

local FRAME = 1 / 60
local PHYSICS_STEP = 1 / 240
local GAP = 1e-9
local CONTACT = ChoreoData.locomotion.stride.contact
local SLIDE = Dev.review.audit.footSlideStuds
local FROM, TO = 0.15, 0.5

-- BoarHooks.spec's "studio" Humanoid (the PC's server log on 4b18b5c).
local humanoid = { arriveFrames = 1.7, brake = 0.672, acceleration = 1320 }
local clock = { t = 1000 }
local bodies: { [Model]: any } = {}

-- ------------------------------------------------------------------------------------------
-- The fake engine (BoarHooks.spec's, no walls)
-- ------------------------------------------------------------------------------------------

local function yawOf(model: Model): Vector3
	local align = EnemyService.alignOf(model)
	local look = if align ~= nil then align.CFrame.LookVector else (model.PrimaryPart :: BasePart).CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function placeParts(model: Model, body: any)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.lookAt(body.position, body.position + yawOf(model))
end

local engine = {
	place = function(model: Model, cframe: CFrame)
		local root = model.PrimaryPart :: BasePart
		root.CFrame = cframe
		EnemyService.addYawAlign(root, cframe.LookVector)
		bodies[model] = { position = cframe.Position, velocity = Vector3.zero, walkSpeed = 16, physT = clock.t }
		placeParts(model, bodies[model])
	end,
	pivot = function(model: Model, cframe: CFrame)
		bodies[model].position = cframe.Position
		placeParts(model, bodies[model])
	end,
	position = function(model: Model): Vector3
		return bodies[model].position
	end,
	facing = function(model: Model): Vector3
		return yawOf(model)
	end,
	setFacing = function(model: Model, facing: Vector3)
		EnemyService.applyFacing(model, facing)
	end,
	moveTo = function(model: Model, position: Vector3)
		bodies[model].goal = position
	end,
	stop = function(model: Model)
		bodies[model].goal = bodies[model].position
	end,
	halt = function(model: Model, position: Vector3?)
		local body = bodies[model]
		if position ~= nil then
			body.position = Vector3.new(position.X, body.position.Y, position.Z)
		end
		body.velocity = Vector3.zero
		body.goal = body.position
		body.written = true
		placeParts(model, body)
	end,
	land = function(model: Model, position: Vector3, seconds: number)
		local body = bodies[model]
		local offset = Vector3.new(position.X - body.position.X, 0, position.Z - body.position.Z)
		local pace = if seconds > 0 then offset / seconds else Vector3.zero
		body.velocity = pace
		body.walkSpeed = pace.Magnitude
		body.goal = Vector3.new(position.X, body.position.Y, position.Z)
		body.written = true
	end,
	setWalkSpeed = function(model: Model, speed: number)
		bodies[model].walkSpeed = speed
	end,
	computePath = function()
		return nil
	end,
	destroy = function(model: Model)
		model.Parent = nil
		bodies[model] = nil
	end,
	setCollisionGroup = function(model: Model, group: string)
		CollisionGroups.assign(model, group)
	end,
	bodyClear = function(): boolean
		return true
	end,
	worldAhead = function(model: Model, direction: Vector3, distance: number, offset: Vector3?, walk: Vector3?)
		return EnemyService.worldAhead(model, direction, distance, function()
			return nil, nil
		end, offset, walk)
	end,
	anchor = function(model: Model, anchored: boolean)
		bodies[model].anchored = anchored
	end,
}

-- One server frame of the "studio" Humanoid: the walk settled at the frame's start, then 240 Hz
-- physics steps toward it at `acceleration`, braking when it holds its goal as reached.
local function studioFrame(model: Model, body: any, untilT: number)
	local seconds = untilT - body.physT
	local desired: Vector3? = nil
	local goal = body.goal
	if goal ~= nil and not body.anchored then
		local delta = Vector3.new(goal.X - body.position.X, 0, goal.Z - body.position.Z)
		local reached = humanoid.arriveFrames * body.walkSpeed * math.max(seconds, 0)
		if delta.Magnitude > math.max(reached, 1e-3) then
			desired = delta.Unit * body.walkSpeed
		end
	end
	local kept = body.written == true
	body.written = false
	while body.physT + PHYSICS_STEP <= untilT + GAP do
		body.physT += PHYSICS_STEP
		if body.anchored then
			body.velocity = Vector3.zero
			continue
		end
		if desired ~= nil then
			local change = desired - body.velocity
			local most = humanoid.acceleration * PHYSICS_STEP
			if change.Magnitude > most then
				change = change.Unit * most
			end
			body.velocity += change
		elseif not kept then
			body.velocity *= humanoid.brake
			if body.velocity.Magnitude < 0.01 then
				body.velocity = Vector3.zero
			end
		end
		body.position += body.velocity * PHYSICS_STEP
	end
	placeParts(model, body)
end

local function serverFrame()
	clock.t += FRAME
	for model, body in bodies do
		studioFrame(model, body, clock.t)
	end
	EnemyService.step(FRAME)
	EntityService.tick(FRAME)
	CombatService.tick()
end

local function fresh()
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	clock.t = 1000
	bodies = {}
	local now = function()
		return clock.t
	end
	EntityService.bind({
		now = now,
		fireAll = function() end,
		heartbeat = nil,
		addTag = function(instance, tag)
			CollectionService:AddTag(instance, tag)
		end,
		removeTag = function(instance, tag)
			CollectionService:RemoveTag(instance, tag)
		end,
		respawn = function() end,
		playerRemoving = nil,
	})
	CombatService.bind({
		now = now,
		net = { on = function() end, fire = function() end, fireAll = function() end },
		heartbeat = nil,
		cast = function()
			return nil
		end,
		overlap = function()
			return {}
		end,
		random = Random.new(1),
	})
	EnemyService.bind({
		entities = EntityService,
		combat = CombatService,
		rigBuilder = RigBuilder,
		fireAll = function() end,
		engine = engine,
		players = function()
			local list = {}
			for _, player in EntityService.players() do
				if player.state ~= "Dead" then
					table.insert(list, { id = player.id, position = EntityService.positionOf(player.id) })
				end
			end
			return list
		end,
		heartbeat = nil,
		serverTime = now,
		folder = Instance.new("Folder"),
		random = Random.new(3),
		spawnTask = function(fn)
			fn()
		end,
	} :: any)
end

local function spawnPlayer(position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Trialist1"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position)
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	CollisionGroups.assign(model, AI.collision.players)
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 3101 }
	return EntityService.registerPlayer(player :: any, model, Playground.loadout)
end

-- ------------------------------------------------------------------------------------------
-- The drawn rows
-- ------------------------------------------------------------------------------------------

local function corners(size: Vector3): { Vector3 }
	local list = {}
	local half = size * 0.5
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(list, Vector3.new(x * half.X, y * half.Y, z * half.Z))
			end
		end
	end
	return list
end

-- Every part's CFrame from the root through the Motor6Ds as Choreo wrote them (Part0 * C0 *
-- Transform = Part1 * C1).
local function solve(model: Model, root: CFrame): { [string]: CFrame }
	local out = { [(model.PrimaryPart :: BasePart).Name] = root }
	local motors = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			table.insert(motors, descendant)
		end
	end
	local progressed = true
	while progressed do
		progressed = false
		for _, motor in motors do
			local p0, p1 = (motor.Part0 :: BasePart).Name, (motor.Part1 :: BasePart).Name
			if out[p0] ~= nil and out[p1] == nil then
				out[p1] = out[p0] * motor.C0 * motor.Transform * motor.C1:Inverse()
				progressed = true
			end
		end
	end
	return out
end

local FEET = {
	Boar = { "FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg" },
	Kobold = { "LeftLeg", "RightLeg" },
}
local DEFS = { Boar = "FrenzyBoar", Kobold = "KoboldAxeman" }

type Take = {
	slide: number, -- the worst one-frame slide of a grounded foot over the window
	slideAt: number,
	lowest: number, -- the lowest foot corner over the window
	wheelWalk: number?, -- the least walk weight the driver gives while the body wheels at half speed
}

local function take(rig: string, off: number): Take
	fresh()
	spawnPlayer(Vector3.new(0, 3, 25))
	local height = Rigs[rig].hipHeight + Rigs[rig].parts[Rigs[rig].rootPart].size[2] / 2
	local at = Vector3.new(0, height, 10)
	local id = EnemyService.spawn(DEFS[rig], CFrame.new(at))
	EnemyService.setHeld(id, true)
	local server = EnemyService.modelOf(id) :: Model
	local look = CFrame.Angles(0, math.rad(off), 0):VectorToWorldSpace(Vector3.new(0, 0, 1))
	EnemyService.place(id, CFrame.lookAt(at, at + look), true)
	for _ = 1, 30 do
		serverFrame()
	end

	-- The client copy and its gait, as Replication attaches it (Locomotion.idlePhase, the default
	-- tracker on the replicated root).
	local client = RigBuilder.build(rig)
	local clientRoot = client.PrimaryPart :: BasePart
	local clientHumanoid = client:FindFirstChildOfClass("Humanoid") :: Humanoid
	clientHumanoid.FloorMaterial = Enum.Material.Plastic
	clientHumanoid.MoveDirection = Vector3.zero
	local serverRoot = server.PrimaryPart :: BasePart
	clientRoot.CFrame = serverRoot.CFrame
	clientRoot.Position = serverRoot.CFrame.Position
	clientRoot.AssemblyLinearVelocity = Vector3.zero
	local animator = Choreo.get(client)
	local driver = Locomotion.attach(animator, client, { phase = Locomotion.idlePhase(id) })
	for _ = 1, 60 do
		clientNow += FRAME
		animator:step(FRAME)
	end
	local walkId = ChoreoData.rigs[rig].walk
	local function walkHandle(): any
		for _, handle in animator.mixer:handles() do
			if handle.clipId == walkId and not handle.stopping and not handle.fallback then
				return handle
			end
		end
		return nil
	end

	EnemyService.setHeld(id, false)
	local feet = FEET[rig]
	local local_: { [string]: { Vector3 } } = {}
	for _, foot in feet do
		local_[foot] = corners((client:FindFirstChild(foot) :: BasePart).Size)
	end
	local rest = clientRoot.CFrame.Position
	local started: number? = nil
	local previous: { [string]: { Vector3 } }? = nil
	local result: Take = { slide = 0, slideAt = 0, lowest = math.huge, wheelWalk = nil }
	local walkSpeed = Rigs[rig].walkSpeed
	for frame = 1, 90 do
		clientNow += FRAME
		animator:step(FRAME)
		serverFrame()
		local body = bodies[server]
		clientRoot.CFrame = serverRoot.CFrame
		clientRoot.Position = serverRoot.CFrame.Position
		clientRoot.AssemblyLinearVelocity = body.velocity
		local flat = Vector3.new(body.velocity.X, 0, body.velocity.Z)
		clientHumanoid.MoveDirection = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zero

		local solved = solve(client, clientRoot.CFrame)
		if started == nil and (clientRoot.CFrame.Position - rest).Magnitude > 1e-3 then
			started = frame
		end
		local rowT = if started ~= nil then (frame - (started :: number)) * FRAME else -1
		local inWindow = rowT > FROM + 1e-9 and rowT <= TO + 1e-9
		local points: { [string]: { Vector3 } } = {}
		for _, foot in feet do
			points[foot] = {}
			for index, corner in local_[foot] do
				local point = solved[foot] * corner
				points[foot][index] = point
				if inWindow then
					result.lowest = math.min(result.lowest, point.Y)
				end
			end
			local before = if previous ~= nil then previous[foot] else nil
			if inWindow and before ~= nil then
				local least = math.huge
				for index, point in points[foot] do
					local was = before[index]
					if point.Y <= CONTACT and was.Y <= CONTACT then
						least = math.min(least, Vector3.new(point.X - was.X, 0, point.Z - was.Z).Magnitude)
					end
				end
				if least < math.huge and least > result.slide then
					result.slide, result.slideAt = least, rowT
				end
			end
		end
		previous = points

		-- Wheeling: the body at about half its walk speed, settled into it.
		local handle = walkHandle()
		local share = flat.Magnitude / walkSpeed
		if inWindow and handle ~= nil and share > 0.4 and share < 0.6 then
			result.wheelWalk = math.min(result.wheelWalk or math.huge, handle.targetWeight)
		end
	end
	driver:destroy()
	Choreo.release(client)
	return result
end

-- What the walk start does not meet yet, by rig and off angle: how far its worst slide is past
-- footSlideStuds (rounded up to the hundredth). The boar wheeling round from behind: its back
-- hooves, 1.4 behind the root, sweep sideways at the 110 deg/s yaw (0.045 a frame) on top of the
-- walk sampled between its per-frame keys at half rate (D-482, up to 0.035) and the turn's
-- inner/outer difference (0.03). A rigid walk turned about its root cannot plant them; that needs
-- a steering layer (openIssues). The kobold's Brute chases straight at its target while it turns,
-- so from behind it crab-walks (0.17 and 0.29: unchanged by D-541). An entry never grows.
local PENDING: { [string]: { [number]: number } } = {
	Boar = { [135] = 0.01, [180] = 0.02 },
	Kobold = { [135] = 0.07, [180] = 0.19 },
}

describe("EnemyWalkStart: an enemy sets off on its feet (AG 392(b), D-541)", function()
	for _, case in { { rig = "Boar", offs = { 90, 135, 180 } }, { rig = "Kobold", offs = { 0, 60, 90, 135, 180 } } } do
		for _, off in case.offs do
			it(("%s set off %d deg off its target keeps its feet on the field"):format(case.rig, off), function()
				local result = take(case.rig, off)
				print(
					("%s off %d: slide %.3f at %.3f s, lowest %.3f, walk weight wheeling %s"):format(
						case.rig,
						off,
						result.slide,
						result.slideAt,
						result.lowest,
						if result.wheelWalk ~= nil then ("%.2f"):format(result.wheelWalk) else "-"
					)
				)
				-- No foot in the field: the walk's own keys stand the planted corner within contact.
				if result.lowest < -CONTACT then
					error(("a foot corner %.3f under the field (max %.2f)"):format(-result.lowest, CONTACT))
				end
				-- A body wheeling at half its walk speed is drawn on its walk alone.
				if case.rig == "Boar" then
					expect(result.wheelWalk).toBeCloseTo(1, 1e-6)
				end
				local pending = PENDING[case.rig][off]
				local bar = SLIDE + (pending or 0)
				if result.slide > bar then
					error(
						("a planted foot slides %.3f in a frame at %.3f s (max %.3f)"):format(
							result.slide,
							result.slideAt,
							bar
						)
					)
				end
				if pending ~= nil and result.slide <= SLIDE then
					error(("slides %.3f, within footSlideStuds: take it off PENDING"):format(result.slide))
				end
			end)
		end
	end
end)
