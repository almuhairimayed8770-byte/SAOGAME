--!strict
--[[
	Enemy bodies turn (D-165). The root holds an Attachment and an AlignOrientation that share one
	name, the way EnemyService's place() builds them on a RigBuilder rig; the facing lookup must
	find the AlignOrientation, not the Attachment, or every enemy keeps its spawn yaw for life.

	The integration cases run the real EnemyService and EntityService over RigBuilder rigs with an
	engine that behaves like the rigid align: every physics step turns the root to the align's
	CFrame, and facing() reads the root. So the body's look is what a player sees, and the Charger
	and Brute paths are checked against it: the wide-arc chase, the crouch holding its line, the
	rush along the body, the skid turn, the Brute's slow wind-up track and its strike cone.
]]

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
})

local EntityService = Harness.load("src/server/services/EntityService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Brain = Harness.load("src/server/ai/Brain")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

local TICK = AI.tickSeconds()
local FORWARD = Vector3.new(0, 0, -1)
local CHARGER = AI.archetypes.Charger
local BRUTE = AI.archetypes.Brute
local KOBOLD = Enemies.byId("KoboldAxeman")
local OVERHEAD = KOBOLD.attacks[1]
local SKYSPIRE_YAW = "SkyspireYaw"

-- ------------------------------------------------------------------------------------------
-- The root as place() builds it
-- ------------------------------------------------------------------------------------------

describe("Enemy yaw align", function()
	it("finds the AlignOrientation on a RigBuilder root that also holds its same-named Attachment", function()
		local model = RigBuilder.build("Boar", "Frenzy Boar")
		local root = model.PrimaryPart
		local align = EnemyService.addYawAlign(root, FORWARD)
		-- The Attachment is parented first, so a lookup by name alone returns it.
		expect(root:FindFirstChild(SKYSPIRE_YAW).ClassName).toBe("Attachment")
		expect(EnemyService.alignOf(model)).toBe(align)
		expect(EnemyService.applyFacing(model, Vector3.new(1, 0, 0))).toBe(true)
		expect(align.CFrame.LookVector.X).toBeCloseTo(1, 1e-6)
		expect(align.CFrame.LookVector.Y).toBeCloseTo(0, 1e-6)
		-- A vertical facing has no yaw: the align keeps what it had.
		expect(EnemyService.applyFacing(model, Vector3.new(0, 1, 0))).toBe(false)
		expect(align.CFrame.LookVector.X).toBeCloseTo(1, 1e-6)
	end)

	it("a kobold root finds its align too, and a model without one reports none", function()
		local kobold = RigBuilder.build("Kobold", "Kobold Axeman")
		local align = EnemyService.addYawAlign(kobold.PrimaryPart, Vector3.new(0, 0, 1))
		expect(EnemyService.alignOf(kobold)).toBe(align)
		expect(align.CFrame.LookVector.Z).toBeCloseTo(1, 1e-6)
		local bare = RigBuilder.build("Boar", "Bare")
		expect(EnemyService.alignOf(bare)).toBeNil()
		expect(EnemyService.applyFacing(bare, Vector3.new(1, 0, 0))).toBe(false)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- A world where the rigid align turns the body
-- ------------------------------------------------------------------------------------------

local clock = { t = 2000 }
local players: { any } = {}
local bodies: { [any]: any } = {}
local strikes: { any } = {}
local sent: { any } = {}

-- The root follows the align on every physics step (RigidityEnabled), as the engine does.
local function settleRoot(model: any, body: any)
	local root = model.PrimaryPart
	local align = EnemyService.alignOf(model)
	local rotation = if align ~= nil then align.CFrame.Rotation else root.CFrame.Rotation
	root.CFrame = CFrame.new(body.position) * rotation
end

local engine = {
	place = function(model, cframe)
		local root = model.PrimaryPart
		root.CFrame = cframe
		EnemyService.addYawAlign(root, cframe.LookVector)
		local body = { position = cframe.Position, goal = nil, walkSpeed = nil }
		bodies[model] = body
		settleRoot(model, body)
	end,
	position = function(model)
		return bodies[model].position
	end,
	facing = function(model)
		return model.PrimaryPart.CFrame.LookVector
	end,
	setFacing = function(model, facing)
		EnemyService.applyFacing(model, facing)
	end,
	moveTo = function(model, position)
		bodies[model].goal = position
	end,
	stop = function(model)
		bodies[model].goal = nil
	end,
	setWalkSpeed = function(model, speed)
		bodies[model].walkSpeed = speed
	end,
	computePath = function()
		return nil
	end,
	destroy = function(model)
		model.Parent = nil
	end,
}

local function physics(dt: number)
	for model, body in bodies do
		if body.goal ~= nil then
			local delta = body.goal - body.position
			local reach = (body.walkSpeed or 1) * dt
			if delta.Magnitude <= reach then
				body.position = body.goal
			elseif delta.Magnitude > 0 then
				body.position += delta.Unit * reach
			end
		end
		settleRoot(model, body)
	end
end

local function fresh()
	EnemyService.reset()
	EntityService.reset()
	clock.t = 2000
	players = {}
	bodies = {}
	strikes = {}
	sent = {}
	local function fireAll(remote, payload)
		local ok, message = Net.validate(remote, payload)
		if not ok then
			error(("invalid %s payload: %s"):format(remote, tostring(message)))
		end
		table.insert(sent, { remote = remote, payload = payload })
	end
	EntityService.bind({
		now = function()
			return clock.t
		end,
		fireAll = fireAll,
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
	EnemyService.bind({
		entities = EntityService,
		combat = {
			enemyStrike = function(enemyId, attack, origin, facing, options)
				table.insert(strikes, {
					time = clock.t,
					enemyId = enemyId,
					attack = attack,
					origin = origin,
					facing = facing,
					options = options,
				})
				return {}
			end,
		},
		rigBuilder = RigBuilder,
		fireAll = fireAll,
		engine = engine,
		players = function()
			return players
		end,
		heartbeat = nil,
		serverTime = function()
			return clock.t
		end,
		folder = Instance.new("Folder"),
		random = Random.new(5),
		spawnTask = function(fn)
			fn()
		end,
	} :: any)
end

-- One AI tick: the service decides, the bodies move and the roots follow the align.
local function tick()
	EnemyService.step(TICK)
	physics(TICK)
	EntityService.tick(TICK)
	clock.t += TICK
end

local function lookOf(model: any): Vector3
	local look = model.PrimaryPart.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function turned(a: Vector3, b: Vector3): number
	return math.abs(Brain.signedAngle(a, b))
end

local function phaseOf(id: number): string?
	local brain = EnemyService.brainOf(id)
	return if brain ~= nil then brain:getPhase() else nil
end

describe("Enemy bodies turn with the brain", function()
	it("the boar's body turns on its wide-arc chase, never faster than the Charger's turn rate", function()
		fresh()
		local id = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
		local model = EnemyService.modelOf(id)
		players = { { id = 1, position = Vector3.new(-30, 3, -5) } }
		local spawnLook = lookOf(model)
		local previous = spawnLook
		local maxStep = 0
		local chaseTicks = 0
		for _ = 1, math.ceil(1.5 / TICK) do
			tick()
			local look = lookOf(model)
			maxStep = math.max(maxStep, turned(previous, look))
			previous = look
			if phaseOf(id) == "Chase" then
				chaseTicks += 1
			end
		end
		expect(chaseTicks).toBeGreaterThan(0)
		-- The body faces where the brain faces, and it turned a long way toward the player.
		expect(lookOf(model):Dot(EnemyService.brainOf(id):getFacing())).toBeGreaterThan(0.9999)
		expect(turned(spawnLook, lookOf(model))).toBeGreaterThan(45)
		expect(maxStep).toBeLessThanOrEqual(CHARGER.turnRate * TICK + 1e-3)
	end)

	it("the crouch holds the body's line, the rush runs along the body, and the skid turns it slowly", function()
		fresh()
		local id = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
		local model = EnemyService.modelOf(id)
		local body = bodies[model]
		players = { { id = 1, position = Vector3.new(6, 3, -20) } }
		local guard = 0
		while phaseOf(id) ~= "WindUp" and guard < 200 do
			tick()
			guard += 1
		end
		expect(phaseOf(id)).toBe("WindUp")
		local crouchLook = lookOf(model)
		local telegraph = sent[#sent].payload
		for _, entry in sent do
			if entry.remote == "Telegraph" then
				telegraph = entry.payload
			end
		end
		local drawn = Vector3.new(telegraph.facing[1], 0, telegraph.facing[3])
		expect(crouchLook:Dot(drawn)).toBeGreaterThan(0.9999) -- the red line leaves the snout
		-- A sidestep during the crouch: the body holds its line.
		players[1].position = Vector3.new(14, 3, -20)
		while phaseOf(id) == "WindUp" do
			tick()
			expect(lookOf(model):Dot(crouchLook)).toBeGreaterThan(0.99999)
		end
		expect(phaseOf(id)).toBe("Strike")
		-- The rush heads where the body points: no sideways or backwards slide.
		local heading = body.goal - body.position
		expect(Vector3.new(heading.X, 0, heading.Z).Unit:Dot(lookOf(model))).toBeGreaterThan(0.9999)
		while phaseOf(id) == "Strike" do
			tick()
			expect(lookOf(model):Dot(crouchLook)).toBeGreaterThan(0.99999)
		end
		expect(phaseOf(id)).toBe("Recover")
		-- The skid: the body turns back toward the player, at the recovery's slow rate.
		local skidLook = lookOf(model)
		local previous = skidLook
		while phaseOf(id) == "Recover" do
			tick()
			local look = lookOf(model)
			expect(turned(previous, look)).toBeLessThanOrEqual(CHARGER.recoverTurnRate * TICK + 1e-3)
			previous = look
		end
		local toPlayer = Brain.horizontal(players[1].position - body.position)
		expect(turned(previous, toPlayer)).toBeLessThan(turned(skidLook, toPlayer))
	end)

	it("the kobold's body tracks slowly through the wind-up and its cone resolves along the body", function()
		fresh()
		local id = EnemyService.spawn("KoboldAxeman", CFrame.new(0, 3, 0))
		local model = EnemyService.modelOf(id)
		players = { { id = 1, position = Vector3.new(0, 3, -12) } }
		local guard = 0
		while phaseOf(id) ~= "WindUp" and guard < 200 do
			tick()
			guard += 1
		end
		expect(phaseOf(id)).toBe("WindUp")
		-- The player circles to the side; the body follows at the wind-up's slow rate.
		players[1].position = Vector3.new(4, 3, -3)
		local windUpLook = lookOf(model)
		local previous = windUpLook
		while phaseOf(id) == "WindUp" do
			tick()
			local look = lookOf(model)
			expect(turned(previous, look)).toBeLessThanOrEqual(BRUTE.windUpTurnRate * TICK + 1e-3)
			previous = look
		end
		expect(turned(windUpLook, previous)).toBeGreaterThan(BRUTE.windUpTurnRate * OVERHEAD.windUp * 0.5)
		guard = 0
		while #strikes == 0 and guard < 40 do
			tick()
			guard += 1
		end
		expect(#strikes).toBe(1)
		local strike = strikes[1]
		expect(Vector3.new(strike.facing.X, 0, strike.facing.Z).Unit:Dot(lookOf(model))).toBeGreaterThan(0.9999)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Server frames: the body turns every frame and the attack's edges land on their frame
-- ------------------------------------------------------------------------------------------

-- One server frame in the engine's order: physics moves the bodies and settles the roots on the
-- align, then the Heartbeat runs the service (its ticks, then its frame pass).
local function serverFrame(dt: number)
	clock.t += dt
	physics(dt)
	EnemyService.step(dt)
	EntityService.tick(dt)
end

local function sentOf(remote: string): { any }
	local list = {}
	for _, entry in sent do
		if entry.remote == remote then
			table.insert(list, entry.payload)
		end
	end
	return list
end

describe("Enemy bodies at server frame rate (D-184, D-185)", function()
	it("the kobold and the boar turn their bodies a frame's worth on every frame of a turn", function()
		for _, case in
			{ { defId = "KoboldAxeman", rate = BRUTE.turnRate }, { defId = "FrenzyBoar", rate = CHARGER.turnRate } }
		do
			for _, fps in { 60, 30 } do
				fresh()
				local id = EnemyService.spawn(case.defId, CFrame.new(0, 3, 0))
				local model = EnemyService.modelOf(id)
				players = { { id = 1, position = Vector3.new(-14, 3, 10) } }
				local frame = 1 / fps
				local previous = lookOf(model)
				local turning, moved, maxStep = 0, 0, 0
				for _ = 1, math.ceil(1.2 * fps) do
					local brain = EnemyService.brainOf(id)
					-- Still well off the player at the start of the frame: this frame turns.
					local offTarget = phaseOf(id) == "Chase"
						and brain:angleTo(players[1].position - bodies[model].position) > 5
					serverFrame(frame)
					local look = lookOf(model)
					local step = turned(previous, look)
					previous = look
					maxStep = math.max(maxStep, step)
					if offTarget then
						turning += 1
						if step > 1e-4 then
							moved += 1
						end
					end
				end
				expect(turning).toBeGreaterThan(10)
				expect(moved).toBeGreaterThanOrEqual(turning - 2)
				expect(maxStep).toBeLessThanOrEqual(case.rate * frame + 1e-3)
			end
		end
	end)

	it("a wheeling boar crouches on the line its body already shows: no last-frame turn under the telegraph", function()
		for _, fps in { 60, 30 } do
			fresh()
			local id = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
			local model = EnemyService.modelOf(id)
			players = { { id = 1, position = Vector3.new(-24, 3, 14) } }
			local guard = 0
			while #sentOf("Telegraph") == 0 and guard < 4 * fps do
				serverFrame(1 / fps)
				guard += 1
			end
			expect(phaseOf(id)).toBe("WindUp")
			local telegraph = sentOf("Telegraph")[1]
			local drawn = Vector3.new(telegraph.facing[1], 0, telegraph.facing[3]).Unit
			-- On the telegraph's own frame the root already points down the drawn line.
			expect(turned(drawn, lookOf(model))).toBeLessThan(1e-3)
			expect(turned(drawn, EnemyService.brainOf(id):getFacing())).toBeLessThan(1e-3)
		end
	end)

	it("the kobold's cone resolves on the first server frame at or after its beat, along the body", function()
		for _, seed in { 1, 2, 3 } do
			fresh()
			local id = EnemyService.spawn("KoboldAxeman", CFrame.new(0, 3, 0))
			local model = EnemyService.modelOf(id)
			players = { { id = 1, position = Vector3.new(2, 3, -6) } }
			local random = Random.new(seed)
			local frames: { number } = {}
			local guard = 0
			while #strikes == 0 and guard < 400 do
				serverFrame(1 / 60 + (random:NextNumber() * 2 - 1) * 0.002)
				table.insert(frames, clock.t)
				guard += 1
			end
			expect(#strikes).toBe(1)
			local telegraph = sentOf("Telegraph")[1]
			local beat = telegraph.serverTime + OVERHEAD.windUp + OVERHEAD.strike
			local first = nil
			for _, at in frames do
				if at >= beat - 1e-9 then
					first = at
					break
				end
			end
			expect(strikes[1].time).toBe(first)
			-- On the strike's own frame the root already points along the cone's facing.
			local facing = strikes[1].facing
			expect(turned(Vector3.new(facing.X, 0, facing.Z).Unit, lookOf(model))).toBeLessThan(1e-3)
		end
	end)

	it("the boar's rush leaves on the first server frame at or after the wind-up's end, its MoveTo with it", function()
		fresh()
		local id = EnemyService.spawn("FrenzyBoar", CFrame.new(0, 3, 0))
		local model = EnemyService.modelOf(id)
		local body = bodies[model]
		players = { { id = 1, position = Vector3.new(0, 3, -20) } }
		local guard = 0
		while #sentOf("RushStarted") == 0 and guard < 400 do
			serverFrame(1 / 60)
			guard += 1
		end
		local started = sentOf("RushStarted")[1]
		local telegraph = sentOf("Telegraph")[1]
		local beat = telegraph.serverTime + Enemies.byId("FrenzyBoar").attacks[1].windUp
		expect(started.serverTime).toBeCloseTo(beat, 1e-9)
		expect(clock.t - beat).toBeGreaterThanOrEqual(-1e-9)
		expect(clock.t - beat).toBeLessThan(1 / 60 + 1e-9)
		expect(strikes[1].time).toBe(clock.t)
		-- The body has its goal on the launch frame: the next physics step already runs it.
		expect(body.goal).never.toBeNil()
		local before = body.position
		serverFrame(1 / 60)
		expect((body.position - before):Dot(lookOf(model))).toBeGreaterThan(0)
	end)

	it("a held enemy does nothing on its frames: no strike past its beat, no turn", function()
		fresh()
		local id = EnemyService.spawn("KoboldAxeman", CFrame.new(0, 3, 0))
		local model = EnemyService.modelOf(id)
		players = { { id = 1, position = Vector3.new(0, 3, -4) } }
		local guard = 0
		while phaseOf(id) ~= "WindUp" and guard < 400 do
			serverFrame(1 / 60)
			guard += 1
		end
		EnemyService.setHeld(id, true)
		players[1].position = Vector3.new(6, 3, 0)
		serverFrame(1 / 60)
		local look = lookOf(model)
		for _ = 1, 120 do
			serverFrame(1 / 60)
			expect(turned(look, lookOf(model))).toBeLessThan(1e-4)
		end
		expect(#strikes).toBe(0)
	end)
end)
