--!strict
--[[
	Enemies stand upright through a hold (D-494): the staged takes on the real services
	(DevStage.server.luau loaded the way Studio runs it, the real EnemyService, CombatService and
	EntityService, a RigBuilder enemy, the AI's 20 Hz tick on a fake clock), over a fake engine whose
	Humanoid does what the owner's PC measured in Studio on 48a846f (the jam report):

	- a body whose root is anchored on its first physics step goes from Running to FallingDown (0.015 s
	  after its spawn), unless FallingDown was turned off before that step (SetStateEnabled in the
	  frame the model is made: Running throughout, 3 of 3; one frame later is too late, 3 of 3
	  Jammed);
	- in FallingDown MoveTo does nothing: the body stands where it is (WalkToPoint set, MoveDirection
	  and velocity 0);
	- FallingDown lasts until about 3.0 s after the root is unanchored, then GettingUp, then Running;
	  ChangeState(GettingUp) on the release brings it to Running within 0.033 s;
	- an anchored root does not move.

	A staged enemy (DevStage holds it at its spawn) is anchored on its first step (D-436), so on
	48a846f the staged boar's first charge never moved and ended "Jammed" on its 9th frame, and a staged
	kobold stood 3 s after "go" before it walked. EnemyService keeps every enemy's Humanoid out of the
	fall states from the frame its model is made (Engine.keepUpright) and stands up a fallen body on
	every release (Engine.standUp).
]]

local luau = require("@lune/luau")

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
local CombatService = Harness.load("src/server/services/CombatService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local AI = Harness.load("src/shared/data/ai")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Playground = Harness.load("src/shared/data/playground")
local World = Harness.load("src/shared/data/world")
local Net = Harness.load("src/shared/net/Net")
local CollectionService = Harness.game():GetService("CollectionService")

local TICK = AI.tickSeconds()
local CAPTURE = Dev.capture
local STAGE = CAPTURE.stage
local HIP = 2 -- the player's Humanoid.HipHeight in this world
local COUNTDOWN_TICKS = math.ceil(CAPTURE.countdownSeconds / TICK)

-- The PC's measurements (jam report, 48a846f): FallingDown lasts this long after the unanchor.
local FALL_SECONDS = 3.0

local clock = { t = 3000 }
local timers: { { at: number, fn: () -> () } } = {}
local sent: { any } = {}

type Body = {
	position: Vector3,
	goal: Vector3?,
	walkSpeed: number?,
	state: string, -- the Humanoid's state: Running, FallingDown or GettingUp
	fallOff: boolean, -- FallingDown turned off (Humanoid:SetStateEnabled)
	stepped: boolean, -- it has had a physics step
	anchored: boolean,
	releasedAt: number?, -- when its root was last unanchored
	states: { string }, -- every state it entered, in order
	keptAt: number?, -- when keepUpright was asked, in physics steps it had had then (0: before the first)
	keptSteps: number?,
}
local bodies: { [any]: Body } = {}

local function enter(body: Body, state: string)
	body.state = state
	table.insert(body.states, state)
end

local function record(remote: string, payload: any)
	local ok, message = Net.validate(remote, payload)
	if not ok then
		error(("invalid %s payload: %s"):format(remote, tostring(message)))
	end
	table.insert(sent, { time = clock.t, remote = remote, payload = payload })
end

local function sentOf(remote: string, from: number?): { any }
	local list = {}
	for _, entry in sent do
		if entry.remote == remote and entry.time >= (from or -math.huge) then
			table.insert(list, entry)
		end
	end
	return list
end

-- Which of the two upright seams the engine has: the real one has both; 4ab47c3's had neither.
type Seams = { keepUpright: boolean, standUp: boolean }

local function makeEngine(seams: Seams): any
	local steps: { [any]: number } = {}
	local engine: any = {
		place = function(model, cframe)
			model.PrimaryPart.CFrame = cframe
			EnemyService.addYawAlign(model.PrimaryPart, cframe.LookVector)
			bodies[model] = {
				position = cframe.Position,
				goal = nil,
				walkSpeed = nil,
				state = "Running",
				fallOff = false,
				stepped = false,
				anchored = false,
				releasedAt = nil,
				states = { "Running" },
				keptAt = nil,
				keptSteps = nil,
			}
			steps[model] = 0
		end,
		position = function(model)
			return bodies[model].position
		end,
		facing = function(model)
			local align = EnemyService.alignOf(model)
			return if align ~= nil then align.CFrame.LookVector else model.PrimaryPart.CFrame.LookVector
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
			bodies[model] = nil
		end,
		setCollisionGroup = function() end,
		bodyClear = function(_model)
			return true
		end,
		anchor = function(model, anchored)
			local body = bodies[model]
			body.anchored = anchored
			if not anchored then
				body.releasedAt = clock.t
				body.goal = nil -- the real engine sends the Humanoid to where it stands
			end
		end,
	}
	if seams.keepUpright then
		-- Humanoid:SetStateEnabled(FallingDown, false): it keeps a body that has not had its first step
		-- Running; one that already fell stays down (the PC's one-frame-late case).
		engine.keepUpright = function(model)
			local body = bodies[model]
			body.fallOff = true
			body.keptAt = clock.t
			body.keptSteps = if body.stepped then 1 else 0
		end
	end
	if seams.standUp then
		-- Humanoid:ChangeState(GettingUp) from a fall: Running on the next step.
		engine.standUp = function(model)
			local body = bodies[model]
			if body.state == "FallingDown" then
				enter(body, "GettingUp")
			end
		end
	end
	return engine
end

local function physics(dt: number)
	for model, body in bodies do
		local first = not body.stepped
		body.stepped = true
		if first and body.anchored and not body.fallOff and body.state == "Running" then
			enter(body, "FallingDown")
		end
		if body.state == "FallingDown" then
			local releasedAt = body.releasedAt
			if not body.anchored and releasedAt ~= nil and clock.t - releasedAt >= FALL_SECONDS then
				enter(body, "GettingUp")
			end
		elseif body.state == "GettingUp" then
			enter(body, "Running")
		elseif not body.anchored and body.goal ~= nil then
			local delta = (body.goal :: Vector3) - body.position
			local reach = (body.walkSpeed or 1) * dt
			if delta.Magnitude <= reach then
				body.position = body.goal :: Vector3
			elseif delta.Magnitude > 0 then
				body.position += delta.Unit * reach
			end
		end
		model.PrimaryPart.CFrame = CFrame.new(body.position)
	end
end

local function fresh(seams: Seams)
	EnemyService.reset()
	CombatService.reset()
	EntityService.reset()
	clock.t = 3000
	sent = {}
	bodies = {}
	table.clear(timers)
	local now = function()
		return clock.t
	end
	EntityService.bind({
		now = now,
		fireAll = record,
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
		net = {
			on = function() end,
			fire = function(remote, _player, payload)
				record(remote, payload)
			end,
			fireAll = record,
		},
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
		fireAll = record,
		engine = makeEngine(seams),
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
		random = Random.new(2),
		spawnTask = function(fn)
			fn()
		end,
	} :: any)
end

local function tick()
	EnemyService.step(TICK)
	physics(TICK)
	EntityService.tick(TICK)
	CombatService.tick()
	clock.t += TICK
	local index = 1
	while index <= #timers do
		local timer = timers[index]
		if timer.at <= clock.t + 1e-9 then
			table.remove(timers, index)
			timer.fn()
		else
			index += 1
		end
	end
end

-- DevStage.server.luau as Studio runs it, over the real services bound above.
local function loadStage(): any
	local created: { any } = {}
	local env = Harness.environment()
	env.script = Harness.node("src/server/dev/DevStage")
	env.require = function(node: any): any
		if node.Name == "EnemyService" then
			return EnemyService
		elseif node.Name == "EntityService" then
			return EntityService
		end
		return Harness.loadModule(node)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			if name == "RunService" then
				return {
					IsStudio = function(): boolean
						return true
					end,
				}
			elseif name == "Players" then
				return { PlayerRemoving = { Connect = function() end } }
			end
			return Harness.game():GetService(name)
		end,
	}
	env.workspace = {
		GetAttribute = function(_self: any, name: string): any
			return name == Dev.attributes.capture
		end,
		GetServerTimeNow = function(_self: any): number
			return clock.t
		end,
	}
	env.Instance = {
		new = function(className: string): any
			local instance: any = { ClassName = className }
			table.insert(created, instance)
			return instance
		end,
	}
	env.task = {
		wait = function(seconds: number?): number
			local dt = seconds or TICK
			clock.t += dt
			return dt
		end,
		delay = function(seconds: number, fn: () -> ())
			table.insert(timers, { at = clock.t + seconds, fn = fn })
		end,
	}
	env.os = {
		clock = function(): number
			return clock.t
		end,
	}
	luau.load(
		Harness.readFile("src/server/dev/DevStage.server.luau"),
		{ debugName = "DevStage", environment = env :: any }
	)()
	for _, instance in created do
		if instance.ClassName == "RemoteFunction" then
			return instance
		end
	end
	error("DevStage made no RemoteFunction")
end

-- The player on the stand spot, facing the shot's way, feet on the floor.
local function spawnPlayer(): number
	local area = STAGE.area
	local y = area.position[2] + HIP + 1 + World.spawn.groundEpsilon
	local model = Instance.new("Model")
	model.Name = "Trialist"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(area.position[1], y, area.position[3]) * CFrame.Angles(0, math.rad(area.facing), 0)
	root.Position = root.CFrame.Position
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = HIP
	humanoid.Parent = model
	model.Parent = Instance.new("Folder")
	local player = { Name = model.Name, DisplayName = "Trialist", UserId = 901 }
	return EntityService.registerPlayer(player :: any, model, Playground.loadout)
end

local function shotById(id: string): any
	for _, shot in CAPTURE.shots do
		if shot.id == id then
			return shot
		end
	end
	error("no shot " .. id)
end

type Phase = { phase: string, at: number, position: Vector3 }
type Take = {
	shot: any,
	playerId: number,
	ids: { number },
	models: { any },
	phases: { [number]: { Phase } }, -- each staged enemy's phase changes, `at` from the "go"
	hits: { any }, -- HitConfirmed on the player, `at` from the "go"
	ended: { any }, -- RushEnded, `at` from the "go"
}

-- One take of a shot, the player standing still on the spot (kept above half HP), `seconds` long
-- (the shot's own length when nil).
local function runTake(shotId: string, seams: Seams, seconds: number?): Take
	fresh(seams)
	local shot = shotById(shotId)
	local remote = loadStage()
	local playerId = spawnPlayer()
	local who = EntityService.get(playerId).player
	local function invoke(action: string, id: string?): any
		clock.t += 1 / STAGE.requestsPerSecond
		return remote.OnServerInvoke(who, action, id)
	end
	local staged = invoke("stage", shot.id)
	assert(staged.ok == true, "the staging refused: " .. tostring(staged.error))
	for _ = 1, COUNTDOWN_TICKS do
		tick()
	end
	local go = invoke("go")
	assert(go.ok == true, "go refused: " .. tostring(go.error))
	local t0 = clock.t
	local phases: { [number]: { Phase } } = {}
	local last: { [number]: string } = {}
	local models = {}
	for index, id in staged.ids do
		phases[id] = {}
		models[index] = EnemyService.modelOf(id)
	end
	while clock.t - t0 < (seconds or shot.seconds) do
		tick()
		for _, id in staged.ids do
			local brain = EnemyService.brainOf(id)
			local phase = if brain ~= nil then brain:getPhase() else "Gone"
			if phase ~= last[id] then
				local model = EnemyService.modelOf(id)
				local body = if model ~= nil then bodies[model] else nil
				table.insert(phases[id], {
					phase = phase,
					at = (if brain ~= nil then brain.phaseStart else clock.t) - t0,
					position = if body ~= nil then body.position else Vector3.zero,
				})
				last[id] = phase
			end
		end
		local player = EntityService.get(playerId)
		if player.hp < player.maxHp / 2 then
			EntityService.setHp(playerId, player.maxHp)
		end
	end
	local hits = {}
	for _, entry in sentOf("HitConfirmed", t0) do
		if entry.payload.targetId == playerId then
			table.insert(hits, { at = entry.time - t0, payload = entry.payload })
		end
	end
	local ended = {}
	for _, entry in sentOf("RushEnded", t0) do
		table.insert(ended, { at = entry.time - t0, payload = entry.payload })
	end
	return {
		shot = shot,
		playerId = playerId,
		ids = staged.ids,
		models = models,
		phases = phases,
		hits = hits,
		ended = ended,
	}
end

local function firstOf(list: { Phase }, phase: string, from: number?): Phase?
	for _, entry in list do
		if entry.phase == phase and entry.at >= (from or -math.huge) then
			return entry
		end
	end
	return nil
end

local function rushOf(enemy: string): any
	local def = Enemies.byId(enemy)
	return if def ~= nil and def.archetype == "Charger" then def.attacks[1] else nil
end

local BOTH: Seams = { keepUpright = true, standUp = true }

-- The staged boar's first charge: where it crouched, where it came to rest, and how it ended.
type Charge = {
	distance: number,
	jammed: boolean,
	hits: number,
	states: { string },
	crouchAt: number, -- from the "go"
	hitAt: number?, -- the boar's first hit on the player, from the "go"
}
local function firstCharge(seams: Seams): Charge
	local take = runTake("enemy-boar-charge", seams)
	local boarId = take.ids[1]
	local log = take.phases[boarId]
	local crouch = firstOf(log, "WindUp") :: Phase
	assert(crouch ~= nil, "the boar never crouched")
	local launch = firstOf(log, "Strike", crouch.at) :: Phase
	assert(launch ~= nil, "the boar never launched")
	local skid = firstOf(log, "Recover", launch.at) :: Phase
	assert(skid ~= nil, "the rush never ended")
	-- Where the body rests: on the phase after the skid (the run's end is an exact stop, D-432).
	local after: Phase? = nil
	for _, entry in log do
		if entry.at > skid.at then
			after = entry
			break
		end
	end
	assert(after ~= nil, "the skid never ended")
	local run = ((after :: Phase).position - crouch.position) * Vector3.new(1, 0, 1) -- the line starts at the crouch
	local jammed = false
	for _, entry in take.ended do
		if entry.payload.entityId == boarId and entry.payload.reason == "Jammed" then
			jammed = true
		end
	end
	local hits = 0
	local hitAt: number? = nil
	for _, hit in take.hits do
		if hit.payload.attackerId == boarId then
			hits += 1
			hitAt = hitAt or hit.at
		end
	end
	return {
		distance = run.Magnitude,
		jammed = jammed,
		hits = hits,
		states = bodies[take.models[1]].states,
		crouchAt = crouch.at,
		hitAt = hitAt,
	}
end

describe("Enemies stand upright through a hold (D-494)", function()
	it("the staged charge shot runs its first charge Done at the full length, one hit, never down", function()
		local charge = firstCharge(BOTH)
		local rush = rushOf("FrenzyBoar")
		-- 4ab47c3: Jammed, 0 studs, no hit (the PC's 3 of 3), the Humanoid FallingDown from spawn
		expect(charge.jammed).toBe(false)
		expect(charge.distance).toBeCloseTo(rush.reach + AI.archetypes.Charger.overshoot, 1e-3)
		expect(charge.hits).toBe(1)
		expect(table.concat(charge.states, ",")).toBe("Running")
		-- Item 355(b): the telegraph within 0.35 s of the take's start (0.30 here: the 20 Hz tick and
		-- the alert), the hit once at about 1.1 s (the 0.6 s crouch, then 12 studs at the rush speed).
		expect(charge.crouchAt <= 0.35).toBe(true)
		expect(charge.hitAt).toBeTruthy()
		expect(charge.hitAt :: number).toBeCloseTo(1.1, 0.05)
	end)

	it("keeps every staged enemy upright from the frame its model is made, before its first step", function()
		local checked = 0
		for _, shot in CAPTURE.shots do
			-- The shots that let an enemy go (DevStageTakes' set; the others stage on the ledge, which
			-- this world's stand-in player cannot measure).
			local released = false
			for _, entry in shot.stage.enemies do
				released = released or not entry.held
			end
			if not released then
				continue
			end
			local take = runTake(shot.id, BOTH, 0.5)
			for _, model in take.models do
				local body = bodies[model]
				expect(body.keptAt).toBeTruthy()
				expect(body.keptSteps).toBe(0)
				expect(body.state).toBe("Running")
				checked += 1
			end
		end
		expect(checked >= 6).toBe(true) -- the fight's two, the charge's, the rear charge's, the overhead's and the parry's
	end)

	it("each half alone saves the charge: upright at the spawn, or stood up on the release", function()
		local rush = rushOf("FrenzyBoar")
		local length = rush.reach + AI.archetypes.Charger.overshoot
		local kept = firstCharge({ keepUpright = true, standUp = false })
		expect(kept.jammed).toBe(false)
		expect(kept.distance).toBeCloseTo(length, 1e-3)
		-- The PC's case H: a fallen body stood up as it is let go runs the charge too.
		local stood = firstCharge({ keepUpright = false, standUp = true })
		expect(stood.jammed).toBe(false)
		expect(stood.distance).toBeCloseTo(length, 1e-3)
		expect(table.concat(stood.states, ",")).toBe("Running,FallingDown,GettingUp,Running")
		-- Neither (4ab47c3): the fallen body never moves and the rush jams where it crouched.
		local neither = firstCharge({ keepUpright = false, standUp = false })
		expect(neither.jammed).toBe(true)
		expect(neither.distance < 0.5).toBe(true)
		expect(neither.hits).toBe(0)
	end)

	it("the fight's kobold walks in as soon as it is let go: its first overhead comes on time", function()
		local overhead = Enemies.byId("KoboldAxeman").attacks[1]
		local function firstWindUp(seams: Seams): number
			local take = runTake("fight-boar-kobold", seams, 6)
			local entry = firstOf(take.phases[take.ids[1]], "WindUp")
			assert(entry ~= nil, "the kobold never wound up")
			return entry.at
		end
		local upright = firstWindUp(BOTH)
		local fallen = firstWindUp({ keepUpright = false, standUp = false })
		-- Upright it walks its 9 studs at once; fallen it stands FALL_SECONDS first (the PC's first
		-- parry at r292, 4.87 s, against the 2.2 s the item asks).
		expect(upright + overhead.windUp < 2.2 + 0.25).toBe(true)
		expect(fallen - upright).toBeCloseTo(FALL_SECONDS, 0.25)
	end)

	it("the fight's boar, let go at 8.6 s, crouches at once and runs its charge Done into the player", function()
		local boarEntry = shotById("fight-boar-kobold").stage.enemies[2]
		local take = runTake("fight-boar-kobold", BOTH, 12)
		local boarId = take.ids[2]
		local log = take.phases[boarId]
		local crouch = firstOf(log, "WindUp") :: Phase
		expect(crouch).toBeTruthy()
		-- Its crouch comes inside half a second of its release (item 322(b): let go at about 8.6 s).
		expect(crouch.at >= boarEntry.releaseAfter - 1e-6).toBe(true)
		expect(crouch.at < boarEntry.releaseAfter + 0.5).toBe(true)
		local jammed = false
		for _, entry in take.ended do
			if entry.payload.entityId == boarId and entry.payload.reason == "Jammed" then
				jammed = true
			end
		end
		expect(jammed).toBe(false)
		local fromBoar = 0
		for _, hit in take.hits do
			if hit.payload.attackerId == boarId then
				fromBoar += 1
			end
		end
		-- Standing still on the spot (no dodge here) the charge meets the player once, as staged.
		expect(boarEntry.charge).toBe("Meets")
		expect(fromBoar).toBe(1)
		expect(table.concat(bodies[take.models[2]].states, ",")).toBe("Running")
	end)
end)
