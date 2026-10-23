--!strict
--[[
	EnemyService: spawning, the 20 Hz AI tick, sleep, telegraphs and enemy strikes (sections 9
	and 16; ARCHITECTURE "Combat flow" step 3).

	spawn(defId, cframe, options) builds the placeholder rig through RigBuilder, registers it with
	EntityService (which owns HP, state and threat), parents it under workspace.Enemies and gives
	it a Brain for its archetype (Charger, Brute). The Heartbeat accumulates dt into whole AI ticks;
	every awake brain ticks, then its mover turns the brain's MoveTo requests into Humanoid:MoveTo
	calls, with a PathfindingService path (custom material costs) once the goal is farther than
	ai.pathfindPastStuds or the body is stuck. Brains farther than ai.sleepRadius from every player
	sleep. The brain owns its yaw and publishes it through an AlignOrientation on the root, so a
	Charger really does turn slowly.

	Hold (D-120): setHeld(id, true) puts one enemy's brain to sleep and stops its mover, and the
	sleep check never wakes it while it is held; setHoldNew(true) makes every enemy spawned after
	it (PlaygroundService respawns included) start held. A held enemy's HP never regenerates
	(EntityService.setHpRegenHeld), so a low HP set up for a hit waits for it. Hits still land on a
	held enemy: HP, the Stagger interrupt, Break, death and the kill path all run through
	EntityService as before.
	Releasing it hands it back to the sleep rules on the next tick. This is the cinematic hold
	(a boss entrance, the announcement, any story beat or cutscene freezes the field) and what
	the Studio dev hook uses to run a controlled fight.

	A brain's telegraph becomes the Telegraph remote (wind-up, kind, origin, facing, ground shape),
	its clip the ActionStarted remote, its strike a CombatService.enemyStrike call, its state an
	EntityService.setState call (EntityService fires StateChanged itself). EntityService's Died and
	StateChanged signals stop a brain or interrupt its attack (Stagger, Break, GuardBroken).

	Everything engine-facing goes through `Deps` / `Engine` (bind), so the whole service runs in
	Lune with a fake world; `start()` binds the real engine.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local AI = require(Shared.data.ai)
local Enemies = require(Shared.data.enemies)
local Rigs = require(Shared.data.rigs)
local Signal = require(Shared.util.Signal)
local Brain = require(script.Parent.Parent.ai.Brain)
local Charger = require(script.Parent.Parent.ai.Charger)
local Brute = require(script.Parent.Parent.ai.Brute)

export type SpawnOptions = {
	band: Types.ThreatBand?, -- overrides the def's band (spawn tables)
	elite: boolean?, -- Enemies.variant Elite: 1.5x stats, Mirror Shield, a second attack
	night: boolean?, -- Enemies.variant Night: +25% damage
	name: string?, -- display name override
	level: number?, -- Level attribute override
}

export type Connection = { Disconnect: (self: any) -> () }

-- The engine calls the service makes, one function each, so tests can fake a world.
export type Engine = {
	place: (model: Model, cframe: CFrame) -> (), -- PivotTo, server network ownership, the yaw align
	position: (model: Model) -> Vector3,
	facing: (model: Model) -> Vector3,
	setFacing: (model: Model, facing: Vector3) -> (),
	moveTo: (model: Model, position: Vector3) -> (), -- Humanoid:MoveTo
	stop: (model: Model) -> (),
	setWalkSpeed: (model: Model, speed: number) -> (),
	computePath: (from: Vector3, to: Vector3) -> { Vector3 }?, -- may yield; nil when no path
	destroy: (model: Model) -> (),
}

export type Deps = {
	entities: any, -- EntityService
	combat: any?, -- CombatService (enemyStrike); nil logs strikes until it lands
	rigBuilder: any, -- RigBuilder.build(rigId, name) -> Model
	fireAll: (remote: string, payload: any) -> (), -- Net.server().fireAll
	engine: Engine,
	players: () -> { Brain.PlayerSnapshot }, -- alive player fighters with positions
	heartbeat: ((handler: (dt: number) -> ()) -> Connection?)?, -- RunService.Heartbeat; nil in tests
	serverTime: () -> number, -- workspace:GetServerTimeNow
	folder: Instance, -- workspace.Enemies
	random: Random,
	spawnTask: ((fn: () -> ()) -> ())?, -- task.spawn for path computation; nil runs it inline
}

type Mover = {
	model: Model,
	goal: Vector3?,
	speed: number,
	moving: boolean,
	issuedGoal: Vector3?,
	issuedAt: number,
	walkSpeed: number?,
	path: { Vector3 }?,
	pathIndex: number,
	pathComputedAt: number,
	pathFailedAt: number?,
	computing: boolean,
	pathGeneration: number, -- bumped by every request and every stop; a late result for an old goal is dropped
	lastProgressAt: number,
	lastProgressPosition: Vector3?,
	stuck: boolean,
}

export type Entry = {
	id: number,
	defId: string,
	def: Enemies.Enemy,
	model: Model,
	brain: Brain.Brain,
	mover: Mover,
	awake: boolean,
	held: boolean, -- the cinematic / dev hold: asleep, and the sleep check never wakes it
	home: Vector3,
}

local FORWARD = -Vector3.zAxis
local FOLDER_NAME = "Enemies"
local ALIGN_NAME = "SkyspireYaw"

local INTERRUPTING: { [string]: boolean } = { Stagger = true, Break = true, GuardBroken = true }

local ARCHETYPES: { [string]: Brain.Archetype } = {
	Charger = Charger,
	Brute = Brute,
}

local EnemyService = {}

--- Fires (entityId, defId, model) after an enemy is registered and has a brain.
EnemyService.Spawned = Signal.new() :: Signal.Signal<number, string, Model>
--- Fires (entityId, defId, reason) when an enemy is gone for the spawner: "Died", "Despawned" or
--- "Unregistered" (EntityService dropped it). PlaygroundService schedules respawns from it.
EnemyService.Despawned = Signal.new() :: Signal.Signal<number, string, string>

local deps: Deps? = nil
local entries: { [number]: Entry } = {}
local currentPlayers: { Brain.PlayerSnapshot } = {}
local accumulator = 0
local lastSleepCheck = -math.huge
local heartbeatConnection: Connection? = nil
local signalConnections: { Connection } = {}
local started = false
local warnedNoCombat = false
local holdNew = false

local function dependencies(): Deps
	if deps == nil then
		error("EnemyService: call start() or bind() first")
	end
	return deps :: Deps
end

-- ---------------------------------------------------------------------------------------------
-- Payload helpers
-- ---------------------------------------------------------------------------------------------

local function toVec3(vector: Vector3): Types.Vec3
	return { vector.X, vector.Y, vector.Z }
end

local function unitVec3(vector: Vector3): Types.Vec3
	local flat = Brain.horizontal(vector) or FORWARD
	return { flat.X, flat.Y, flat.Z }
end

-- ---------------------------------------------------------------------------------------------
-- Mover: MoveTo with a pathfinding fallback
-- ---------------------------------------------------------------------------------------------

local function newMover(model: Model, speed: number): Mover
	return {
		model = model,
		goal = nil,
		speed = speed,
		moving = false,
		issuedGoal = nil,
		issuedAt = -math.huge,
		walkSpeed = nil,
		path = nil,
		pathIndex = 1,
		pathComputedAt = -math.huge,
		pathFailedAt = nil,
		computing = false,
		pathGeneration = 0,
		lastProgressAt = -math.huge,
		lastProgressPosition = nil,
		stuck = false,
	}
end

local function moverRequest(mover: Mover, goal: Vector3, speed: number)
	mover.goal = goal
	mover.speed = speed
end

local function moverStop(mover: Mover)
	mover.goal = nil
	if mover.moving then
		mover.moving = false
		mover.issuedGoal = nil
		mover.path = nil
		mover.stuck = false
		-- A path still computing is for a goal that no longer exists; its result is dropped.
		mover.pathGeneration += 1
		mover.computing = false
		dependencies().engine.stop(mover.model)
	end
end

local function issue(mover: Mover, target: Vector3, now: number)
	local engine = dependencies().engine
	local issued = mover.issuedGoal
	if
		issued == nil
		or (target - issued).Magnitude >= AI.movement.reissueStuds
		or now - mover.issuedAt >= AI.movement.reissueInterval
	then
		engine.moveTo(mover.model, target)
		mover.issuedGoal = target
		mover.issuedAt = now
	end
end

local function requestPath(mover: Mover, from: Vector3, to: Vector3, now: number)
	local d = dependencies()
	mover.pathGeneration += 1
	local generation = mover.pathGeneration
	mover.computing = true
	local function compute()
		local waypoints = d.engine.computePath(from, to)
		if mover.pathGeneration ~= generation then
			return -- the mover stopped (or was re-requested) while the path computed
		end
		mover.computing = false
		mover.pathComputedAt = d.serverTime()
		if waypoints ~= nil and #waypoints > 0 then
			mover.path = waypoints
			mover.pathIndex = 1
			mover.pathFailedAt = nil
		else
			mover.path = nil
			mover.pathFailedAt = now
		end
	end
	if d.spawnTask ~= nil then
		d.spawnTask(compute)
	else
		compute()
	end
end

-- Applies the tick's request: direct MoveTo inside pathfindPastStuds, a path beyond it or when stuck.
local function moverUpdate(mover: Mover, now: number)
	local goal = mover.goal
	if goal == nil then
		moverStop(mover)
		return
	end
	local engine = dependencies().engine
	local movement = AI.movement
	mover.moving = true
	if mover.walkSpeed ~= mover.speed then
		engine.setWalkSpeed(mover.model, mover.speed)
		mover.walkSpeed = mover.speed
	end

	local position = engine.position(mover.model)
	local lastProgress = mover.lastProgressPosition
	if lastProgress == nil or (position - lastProgress).Magnitude >= movement.stuckProgressStuds then
		mover.lastProgressAt = now
		mover.lastProgressPosition = position
		mover.stuck = false
	elseif now - mover.lastProgressAt >= movement.stuckSeconds then
		mover.stuck = true
	end

	local distance = Brain.horizontalDistance(position, goal)
	if distance <= movement.arriveRadius then
		mover.path = nil
		issue(mover, goal, now)
		return
	end

	-- A path is wanted past the direct range or when stuck, and a path once taken is walked to its
	-- end (dropping it on the first step of progress would steer straight back into the wall).
	local path = mover.path
	if distance > AI.pathfindPastStuds or mover.stuck or path ~= nil then
		local failedAt = mover.pathFailedAt
		local retryOk = failedAt == nil or now - failedAt >= movement.pathFailRetry
		local stale = path == nil or now - mover.pathComputedAt >= movement.repathInterval
		if not mover.computing and retryOk and stale then
			requestPath(mover, position, goal, now)
			path = mover.path -- filled at once when the computation ran inline
		end
		if path ~= nil then
			while
				mover.pathIndex <= #path
				and Brain.horizontalDistance(position, path[mover.pathIndex]) <= movement.waypointReach
			do
				mover.pathIndex += 1
			end
			if mover.pathIndex <= #path then
				issue(mover, path[mover.pathIndex], now)
				return
			end
			mover.path = nil -- walked to its end; the goal is in direct reach
		end
	end
	issue(mover, goal, now)
end

-- ---------------------------------------------------------------------------------------------
-- Brain context: the bridge from decisions to the engine, the remotes and the sibling services
-- ---------------------------------------------------------------------------------------------

local function fireTelegraph(
	entry: Entry,
	attack: Types.EnemyAttackDef,
	origin: Vector3,
	facing: Vector3,
	shape: Types.TelegraphShape?
)
	local d = dependencies()
	d.fireAll("Telegraph", {
		entityId = entry.id,
		attackId = attack.id,
		kind = attack.telegraph,
		windUp = attack.windUp,
		serverTime = d.serverTime(),
		origin = toVec3(origin),
		facing = unitVec3(facing),
		shape = shape,
	})
end

local function fireActionStarted(entry: Entry, clipId: string, facing: Vector3)
	local d = dependencies()
	d.fireAll("ActionStarted", {
		entityId = entry.id,
		clipId = clipId,
		serverTime = d.serverTime(),
		facing = unitVec3(facing),
	})
end

local function strike(entry: Entry, attack: Types.EnemyAttackDef, origin: Vector3, facing: Vector3)
	local d = dependencies()
	local combat = d.combat
	if combat == nil or typeof(combat.enemyStrike) ~= "function" then
		if not warnedNoCombat then
			warnedNoCombat = true
			warn("[EnemyService] CombatService.enemyStrike is not available; enemy strikes do no damage")
		end
		return
	end
	local ok, err = pcall(combat.enemyStrike, entry.id, attack, origin, Brain.horizontal(facing) or FORWARD)
	if not ok then
		warn(("[EnemyService] enemyStrike failed for entity %d (%s): %s"):format(entry.id, entry.defId, tostring(err)))
	end
end

local function makeContext(entry: Entry): Brain.Context
	local d = dependencies()
	local id = entry.id
	local model = entry.model
	local mover = entry.mover
	return {
		entityId = id,
		def = entry.def,
		home = entry.home,
		now = d.serverTime,
		getRecord = function()
			return d.entities.get(id)
		end,
		players = function()
			return currentPlayers
		end,
		position = function()
			return d.engine.position(model)
		end,
		facing = function()
			return d.engine.facing(model)
		end,
		moveTo = function(position, speed)
			moverRequest(mover, position, speed)
		end,
		stop = function()
			moverStop(mover)
		end,
		face = function(direction)
			d.engine.setFacing(model, direction)
		end,
		telegraph = function(attack, origin, facing, shape)
			fireTelegraph(entry, attack, origin, facing, shape)
		end,
		strike = function(attack, origin, facing)
			strike(entry, attack, origin, facing)
		end,
		setState = function(state, duration)
			d.entities.setState(id, state, duration)
		end,
		actionStarted = function(clipId, facing)
			fireActionStarted(entry, clipId, facing)
		end,
		random = d.random,
		clearThreat = function()
			if typeof(d.entities.threatOf) ~= "function" or typeof(d.entities.clearThreat) ~= "function" then
				return
			end
			for attackerId in d.entities.threatOf(id) do
				d.entities.clearThreat(id, attackerId)
			end
		end,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------------------------

local function archetypeFor(def: Enemies.Enemy): Brain.Archetype
	local archetype = ARCHETYPES[def.archetype]
	if archetype == nil then
		warn(("[EnemyService] no brain for archetype %s (%s); using the Brute's"):format(def.archetype, def.id))
		return Brute
	end
	return archetype
end

-- Pauses (true) or resumes (false) an enemy's HP regen in EntityService (setHpRegenHeld).
local function holdRegen(id: number, held: boolean)
	local entities = dependencies().entities
	if typeof(entities.setHpRegenHeld) == "function" then
		entities.setHpRegenHeld(id, held)
	end
end

local function forget(id: number, reason: string)
	local entry = entries[id]
	if entry == nil then
		return
	end
	entries[id] = nil
	if entry.held then
		-- A record that outlives the entry (reset) gets its regen back; a dead or gone one is a no-op.
		entry.held = false
		holdRegen(id, false)
	end
	entry.awake = false
	entry.brain:die()
	moverStop(entry.mover)
	EnemyService.Despawned:Fire(id, entry.defId, reason)
end

-- Holds an enemy: its brain sleeps (it stops and forgets its target), its mover stops and its HP
-- stops regenerating.
local function hold(entry: Entry)
	entry.held = true
	if entry.awake then
		entry.awake = false
		entry.brain:sleep()
	end
	moverStop(entry.mover)
	holdRegen(entry.id, true)
end

--- The scaled, variant-applied def an enemy spawns with (what EntityService registers).
function EnemyService.resolveDef(defId: string, options: SpawnOptions?): Enemies.Enemy
	local base = Enemies.byId(defId)
	if base == nil then
		error(("EnemyService: unknown enemy def '%s'"):format(tostring(defId)))
	end
	local opts: SpawnOptions = options or {}
	local def = Enemies.scaled(base)
	if opts.elite then
		def = Enemies.variant(def, "Elite")
	end
	if opts.night then
		def = Enemies.variant(def, "Night")
	end
	if opts.band ~= nil then
		def.band = opts.band
	end
	return def
end

--- Spawns an enemy at a CFrame: builds the rig, registers the entity, parents it under
--- workspace.Enemies and starts its brain. Returns the entity id.
function EnemyService.spawn(defId: string, cframe: CFrame, options: SpawnOptions?): number
	local d = dependencies()
	local opts: SpawnOptions = options or {}
	local def = EnemyService.resolveDef(defId, opts)
	local rig = Rigs[def.skin]
	if rig == nil then
		error(("EnemyService: %s uses rig '%s', which rigs.luau does not define yet"):format(def.id, def.skin))
	end

	local model: Model = d.rigBuilder.build(def.skin, def.name)
	if model.PrimaryPart == nil then
		local root = model:FindFirstChild(rig.rootPart)
		if root ~= nil and root:IsA("BasePart") then
			model.PrimaryPart = root
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.AutoRotate = false -- the brain owns the yaw
		humanoid.WalkSpeed = def.moveSpeed
	end
	-- Parent first: the engine's place() claims server network ownership of the root, which the
	-- engine refuses for a part that is not under Workspace yet.
	model.Parent = d.folder
	d.engine.place(model, cframe)

	local id = d.entities.registerEnemy(model, def, { name = opts.name, level = opts.level })
	local entry: Entry = {
		id = id,
		defId = defId,
		def = def,
		model = model,
		mover = newMover(model, def.moveSpeed),
		awake = true,
		held = false,
		home = d.engine.position(model),
		brain = nil :: any,
	}
	entry.brain = Brain.new(makeContext(entry), archetypeFor(def))
	entries[id] = entry
	if holdNew then
		hold(entry)
	end
	EnemyService.Spawned:Fire(id, defId, model)
	return id
end

--- Removes an enemy the spawner no longer wants: the brain stops, EntityService forgets it, the
--- model is destroyed and Despawned fires with reason "Despawned".
function EnemyService.despawn(id: number)
	local entry = entries[id]
	if entry == nil then
		return
	end
	local d = dependencies()
	forget(id, "Despawned")
	if d.entities.get(id) ~= nil then
		d.entities.unregister(id)
	end
	d.engine.destroy(entry.model)
end

--- Despawns every enemy.
function EnemyService.despawnAll()
	for id in table.clone(entries) do
		EnemyService.despawn(id)
	end
end

--- The brain of a living enemy, or nil (tests and the smoke script read phases through it).
function EnemyService.brainOf(id: number): Brain.Brain?
	local entry = entries[id]
	return if entry ~= nil then entry.brain else nil
end

--- The model of a living enemy, or nil.
function EnemyService.modelOf(id: number): Model?
	local entry = entries[id]
	return if entry ~= nil then entry.model else nil
end

--- The def an enemy was spawned with, or nil.
function EnemyService.defOf(id: number): Enemies.Enemy?
	local entry = entries[id]
	return if entry ~= nil then entry.def else nil
end

--- Whether an enemy is awake (inside the sleep radius of a player).
function EnemyService.isAwake(id: number): boolean
	local entry = entries[id]
	return entry ~= nil and entry.awake
end

--- Holds (true) or releases (false) a living enemy: a held enemy's brain sleeps, its mover stops,
--- the sleep check never wakes it and its HP never regenerates (EntityService.setHpRegenHeld);
--- hits, staggers and death still land on it. A release hands it back to the sleep rules on the
--- next tick and lets its HP regenerate again. The cinematic hold (boss entrances, story
--- beats, cutscenes) and the Studio dev hook (D-120). Returns false when `id` is no living enemy.
function EnemyService.setHeld(id: number, held: boolean): boolean
	local entry = entries[id]
	if entry == nil then
		return false
	end
	if held then
		hold(entry)
	elseif entry.held then
		entry.held = false
		holdRegen(id, false)
		-- Asleep until the sleep check says otherwise: run it on the next tick, not in up to
		-- ai.sleepCheckInterval.
		lastSleepCheck = -math.huge
	end
	return true
end

--- Whether a living enemy is held.
function EnemyService.isHeld(id: number): boolean
	local entry = entries[id]
	return entry ~= nil and entry.held
end

--- Every held enemy id, ascending.
function EnemyService.heldIds(): { number }
	local ids = {}
	for id, entry in entries do
		if entry.held then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

--- Hold-new: true makes every enemy spawned from now on (PlaygroundService respawns too) start
--- held; false stops that and releases nobody. reset() turns it off.
function EnemyService.setHoldNew(held: boolean)
	holdNew = held
end

--- Whether enemies spawned now start held.
function EnemyService.holdsNew(): boolean
	return holdNew
end

--- Every living enemy id, ascending.
function EnemyService.ids(): { number }
	local ids = {}
	for id in entries do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

--- Number of living enemies.
function EnemyService.count(): number
	return #EnemyService.ids()
end

-- ---------------------------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------------------------

local function refreshSleep(now: number)
	if now - lastSleepCheck < AI.sleepCheckInterval then
		return
	end
	lastSleepCheck = now
	local engine = dependencies().engine
	local radius = AI.sleepRadius
	for _, entry in entries do
		if entry.held then
			continue -- held: asleep until released, whoever stands next to it
		end
		local position = engine.position(entry.model)
		local awake = false
		for _, player in currentPlayers do
			if (player.position - position).Magnitude <= radius then
				awake = true
				break
			end
		end
		if awake ~= entry.awake then
			entry.awake = awake
			if awake then
				entry.brain:wake()
			else
				entry.brain:sleep()
				moverStop(entry.mover)
			end
		end
	end
end

local function tickAll(step: number)
	local d = dependencies()
	local now = d.serverTime()
	currentPlayers = d.players()
	refreshSleep(now)
	local snapshot = {}
	for _, entry in entries do
		table.insert(snapshot, entry)
	end
	for _, entry in snapshot do
		if entries[entry.id] ~= entry or not entry.awake then
			continue
		end
		local ok, err = pcall(entry.brain.tick, entry.brain, step)
		if not ok then
			warn(("[EnemyService] brain of entity %d (%s) failed: %s"):format(entry.id, entry.defId, tostring(err)))
		end
		moverUpdate(entry.mover, now)
	end
end

--- Advances the service by a frame's dt: whole AI ticks run at ai.tickHz; after a hitch at most
--- ai.maxTicksPerFrame run and the rest of the backlog is dropped. Heartbeat calls it; tests and
--- the smoke script call it by hand.
function EnemyService.step(dt: number)
	accumulator += dt
	local stepSeconds = AI.tickSeconds()
	local ticks = 0
	while accumulator >= stepSeconds and ticks < AI.maxTicksPerFrame do
		accumulator -= stepSeconds
		ticks += 1
		tickAll(stepSeconds)
	end
	if accumulator >= stepSeconds then
		accumulator = 0
	end
end

-- ---------------------------------------------------------------------------------------------
-- Wiring: EntityService signals
-- ---------------------------------------------------------------------------------------------

local function idOf(recordOrId: any): number?
	if typeof(recordOrId) == "number" then
		return recordOrId
	end
	if typeof(recordOrId) == "table" and typeof(recordOrId.id) == "number" then
		return recordOrId.id
	end
	return nil
end

local function connectSignals()
	local d = dependencies()
	local entities = d.entities
	if entities.Died ~= nil then
		table.insert(
			signalConnections,
			entities.Died:Connect(function(recordOrId: any)
				local id = idOf(recordOrId)
				if id ~= nil then
					forget(id, "Died")
				end
			end)
		)
	end
	if entities.Unregistered ~= nil then
		table.insert(
			signalConnections,
			entities.Unregistered:Connect(function(recordOrId: any)
				local id = idOf(recordOrId)
				if id ~= nil then
					forget(id, "Unregistered")
				end
			end)
		)
	end
	if entities.StateChanged ~= nil then
		table.insert(
			signalConnections,
			entities.StateChanged:Connect(function(recordOrId: any, state: string, duration: number?)
				local id = idOf(recordOrId)
				local entry = if id ~= nil then entries[id] else nil
				if entry == nil then
					return
				end
				if state == "Dead" then
					forget(entry.id, "Died")
				elseif INTERRUPTING[state] then
					entry.brain:interrupt(state, duration or AI.interrupt.durations[state])
				end
			end)
		)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Engine
-- ---------------------------------------------------------------------------------------------

local function humanoidOf(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

-- The yaw align on an enemy's root (nil once the corpse is gone). Looked up by name rather than cached
-- per model: EntityService destroys corpses, so a cache keyed by Model would leak one entry per kill.
local function alignOf(model: Model): AlignOrientation?
	local root = model.PrimaryPart
	local align = if root ~= nil then root:FindFirstChild(ALIGN_NAME) else nil
	return if align ~= nil and align:IsA("AlignOrientation") then align else nil
end

local function defaultEngine(): Engine
	local PathfindingService = game:GetService("PathfindingService")
	return {
		place = function(model, cframe)
			model:PivotTo(cframe)
			local root = model.PrimaryPart
			if root == nil then
				return
			end
			-- The server simulates every enemy (spawn() parents the model before calling this).
			local owned, err = pcall(root.SetNetworkOwner, root, nil)
			if not owned then
				warn(("[EnemyService] %s: SetNetworkOwner failed: %s"):format(model.Name, tostring(err)))
			end
			-- One AlignOrientation per enemy (made here, once, never in the tick) carries the yaw.
			local attachment = Instance.new("Attachment")
			attachment.Name = ALIGN_NAME
			attachment.Parent = root
			local align = Instance.new("AlignOrientation")
			align.Name = ALIGN_NAME
			align.Mode = Enum.OrientationAlignmentMode.OneAttachment
			align.Attachment0 = attachment
			align.RigidityEnabled = true
			align.CFrame = CFrame.lookAt(Vector3.zero, Brain.horizontal(cframe.LookVector) or FORWARD)
			align.Parent = root
		end,
		position = function(model)
			local root = model.PrimaryPart
			return if root ~= nil then root.Position else Vector3.zero
		end,
		facing = function(model)
			local root = model.PrimaryPart
			return if root ~= nil then root.CFrame.LookVector else FORWARD
		end,
		setFacing = function(model, facing)
			local align = alignOf(model)
			local flat = Brain.horizontal(facing)
			if align ~= nil and flat ~= nil then
				align.CFrame = CFrame.lookAt(Vector3.zero, flat)
			end
		end,
		moveTo = function(model, position)
			local humanoid = humanoidOf(model)
			if humanoid ~= nil then
				humanoid:MoveTo(position)
			end
		end,
		stop = function(model)
			local humanoid = humanoidOf(model)
			local root = model.PrimaryPart
			if humanoid ~= nil and root ~= nil then
				humanoid:MoveTo(root.Position)
			end
		end,
		setWalkSpeed = function(model, speed)
			local humanoid = humanoidOf(model)
			if humanoid ~= nil then
				humanoid.WalkSpeed = speed
			end
		end,
		computePath = function(from, to)
			local movement = AI.movement
			local path = PathfindingService:CreatePath({
				AgentRadius = movement.agentRadius,
				AgentHeight = movement.agentHeight,
				AgentCanJump = movement.agentCanJump,
				Costs = movement.materialCosts,
			})
			local ok = pcall(path.ComputeAsync, path, from, to)
			if not ok or path.Status ~= Enum.PathStatus.Success then
				return nil
			end
			local waypoints = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(waypoints, waypoint.Position)
			end
			return waypoints
		end,
		destroy = function(model)
			model:Destroy()
		end,
	}
end

-- A sibling server module that may not have landed yet: nil (with a warning) instead of an error.
local function sibling(parent: Instance, name: string): any
	local node = parent:FindFirstChild(name)
	if node == nil or not node:IsA("ModuleScript") then
		warn(("[EnemyService] %s is not available yet"):format(name))
		return nil
	end
	local ok, result = pcall(require, node :: ModuleScript)
	if not ok then
		warn(("[EnemyService] %s failed to load: %s"):format(name, tostring(result)))
		return nil
	end
	return result
end

--- The real engine dependencies, with any field replaced by `overrides` (the smoke script swaps
--- the player source for a stand-in and wraps fireAll to record payloads).
function EnemyService.defaultDeps(overrides: { [string]: any }?): Deps
	local RunService = game:GetService("RunService")
	local Server = script.Parent.Parent
	local entities = sibling(script.Parent, "EntityService")
	if entities == nil then
		error("EnemyService: EntityService is required")
	end
	local world = Server:FindFirstChild("world")
	local rigBuilder = if world ~= nil then sibling(world, "RigBuilder") else nil
	if rigBuilder == nil then
		error("EnemyService: world.RigBuilder is required")
	end
	local Net = require(Shared.net.Net)
	local net = Net.server()

	local folder = workspace:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = workspace
	end

	local built: { [string]: any } = {
		entities = entities,
		combat = sibling(script.Parent, "CombatService"),
		rigBuilder = rigBuilder,
		fireAll = net.fireAll,
		engine = defaultEngine(),
		players = function()
			local list = {}
			for _, record in entities.players() do
				if record.state ~= "Dead" and record.hp > 0 then
					local position = entities.positionOf(record.id)
					if position ~= nil then
						table.insert(list, { id = record.id, position = position })
					end
				end
			end
			return list
		end,
		heartbeat = function(handler)
			return RunService.Heartbeat:Connect(handler)
		end,
		serverTime = function()
			return workspace:GetServerTimeNow()
		end,
		folder = folder,
		random = Random.new(),
		spawnTask = function(fn)
			task.spawn(fn)
		end,
	}
	if overrides ~= nil then
		for key, value in overrides do
			built[key] = value
		end
	end
	return built :: any
end

--- Installs dependencies (engine or fakes) and connects EntityService's signals; no loop yet.
function EnemyService.bind(newDeps: Deps)
	EnemyService.reset()
	deps = newDeps
	connectSignals()
end

--- Starts the service on the engine: binds the real dependencies (unless bound already) and the
--- Heartbeat loop. Safe to call once.
function EnemyService.start()
	if started then
		return
	end
	started = true
	if deps == nil then
		EnemyService.bind(EnemyService.defaultDeps())
	end
	local d = dependencies()
	if d.heartbeat ~= nil then
		heartbeatConnection = d.heartbeat(EnemyService.step)
	end
end

--- Stops the loop, drops every brain and signal connection (tests, and re-binding).
function EnemyService.reset()
	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	for _, connection in signalConnections do
		connection:Disconnect()
	end
	table.clear(signalConnections)
	for id in table.clone(entries) do
		forget(id, "Despawned")
	end
	table.clear(entries)
	currentPlayers = {}
	accumulator = 0
	lastSleepCheck = -math.huge
	started = false
	warnedNoCombat = false
	holdNew = false
end

return EnemyService
