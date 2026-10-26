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

	After the frame's ticks, the frame pass runs every awake brain once per Heartbeat (D-184, D-185):
	the attack's timed edges (the wind-up's end, the strike, a rush's stretches and run) resolve on
	the first server frame at or after their beat, and the body turns by the phase's rate times the
	frame's seconds, so it turns smoothly instead of in 20 Hz steps. A movement the frame pass asks
	for (the rush's launch) reaches the mover in the same frame.

	The mover's stuck clock (D-183) starts with each movement: a stop, a switch to or from a direct
	move and a release from hold all restart it, so time spent standing never reads as time stuck.
	A strike's own movement (the rush) is direct: straight MoveTo, never a path. A path that lands
	after the body moved on never sends it back to the waypoint it asked from (where it stood), nor
	to any leading waypoint the body already walked past (D-196): one is passed when the body is on
	the leg that leaves it (within waypointReach of that leg), past its start, and walked that way
	since it asked. A detour that goes back round an obstacle starts with a leg the body is not on,
	and a body that asked because it was stuck walked nowhere since, so both walk the path as it came.

	Room between enemies (D-259): after each free enemy's tick (deciding or walking, never mid-attack,
	staggered or asleep) Spacing steers its mover so no enemy stands, stops or walks inside another's
	footprint (measured on its rig at spawn, every blocker face included, so face to face between
	two enemies with faces, D-332): a goal inside another body moves out to its edge, a walk
	into one slides along it, and a body caught inside one steps out. A strike's own movement is
	never steered. A Return reaches a home another body stands on at its side (context.standOff).

	Hold (D-120): setHeld(id, true) puts one enemy's brain to sleep and stops its mover, and the
	sleep check never wakes it while it is held; setHoldNew(true) makes every enemy spawned after
	it (PlaygroundService respawns included) start held. A held enemy's HP never regenerates
	(EntityService.setHpRegenHeld), so a low HP set up for a hit waits for it. Hits still land on a
	held enemy: HP, the Stagger interrupt, Break, death and the kill path all run through
	EntityService as before.
	Releasing it hands it back to the sleep rules on the next tick. This is the cinematic hold
	(a boss entrance, the announcement, any story beat or cutscene freezes the field) and what
	the Studio dev hook uses to run a controlled fight.

	Studio test hooks (D-333; DevCombat calls them, the game never does): place(id, cframe, held)
	drops whatever a living enemy was doing the way a hold does, pivots its body there, stops it
	dead and makes it its home; walk(id, goal, hold) walks it to a point at its own pace, turning at
	its own rate, through the mover and the room rules (keepRoom) like any walk; charge(id, toward)
	turns a Charger to face the point and starts its rush, which then runs Charger's normal path
	(the crouch, the telegraph, the launch, the sweep, the wall and jam stops). devRushOf reads back
	how that rush launched and stopped. None of them touches a player or the anti-cheat.

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
local Combat = require(Shared.data.combat)
local Enemies = require(Shared.data.enemies)
local Moments = require(Shared.data.moments)
local Rigs = require(Shared.data.rigs)
local Signal = require(Shared.util.Signal)
local RushWorld = require(Shared.choreo.RushWorld)
local Brain = require(script.Parent.Parent.ai.Brain)
local Charger = require(script.Parent.Parent.ai.Charger)
local Brute = require(script.Parent.Parent.ai.Brute)
local Spacing = require(script.Parent.Parent.ai.Spacing)

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
	-- D-167: puts every part of the model in a collision group (CollisionGroups.assign). Nil: no groups.
	setCollisionGroup: ((model: Model, group: string) -> ())?,
	-- D-167: whether the model's root overlaps no player and no other enemy, so it can rejoin the
	-- enemies group without being pushed out of anyone (CollisionGroups.clear). Nil: always clear.
	bodyClear: ((model: Model) -> boolean)?,
	-- D-197: how far ahead of the root's centre along `direction` the world meets the root (what the
	-- root collides with in its own group: a rushing body's walls, never a player or an enemy), its
	-- box moved by `offset` first when given, within `distance` studs, whether that face is ground it
	-- runs over (D-204, D-209) and the face's normal; nil when nothing is in the way
	-- (EnemyService.worldAhead). `walk`: a walking body's question (its snout's room): the world
	-- alone, with the root's box turned to face `direction`. Nil: no world.
	worldAhead: ((
		model: Model,
		direction: Vector3,
		distance: number,
		offset: Vector3?,
		walk: boolean?
	) -> (number?, boolean?, Vector3?))?,
	-- Stops the body dead (no skid): its flat velocity is zeroed and it holds where it stands, or on
	-- `position` when given (a goal it would pass before the next frame). Nil: `stop` stands in.
	halt: ((model: Model, position: Vector3?) -> ())?,
	-- Moves a placed body to `cframe` (Model:PivotTo; the Studio test hook place, D-333). Nil:
	-- Model:PivotTo itself.
	pivot: ((model: Model, cframe: CFrame) -> ())?,
}

-- The world cast worldAhead makes: a box of `size` at `start` moved by `vector`, colliding as
-- `group` does and never with `exclude`; how far it travelled before it met something, or nil, and
-- the normal of the face it met (nil: a face named no way, taken for a wall).
export type WorldCast = (
	start: CFrame,
	size: Vector3,
	vector: Vector3,
	group: string,
	exclude: Instance
) -> (number?, Vector3?)

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
	-- Where the body stood when it asked for the path in hand, and whether that path landed since the
	-- last update: the first update after it lands skips the waypoints the body already passed (D-196).
	pathFrom: Vector3?,
	pathFresh: boolean,
	pathFailedAt: number?,
	computing: boolean,
	pathGeneration: number, -- bumped by every request and every stop; a late result for an old goal is dropped
	-- The stuck clock (D-183): when and where the body last made progress. Nil position: the clock
	-- starts on the next update. Every new movement restarts it (one that starts from standing, after
	-- a stop, a hold or a sleep, and a switch to or from a direct move), so time spent standing never
	-- counts as time stuck.
	lastProgressAt: number,
	lastProgressPosition: Vector3?,
	stuck: boolean,
	-- A strike's own movement (the rush, any lunge): straight MoveTo, never a path (D-183).
	direct: boolean,
	-- A request arrived since the last update: the frame pass applies it in the same frame.
	pending: boolean,
	-- The body's corners at rest and its root's size (spawn): how far its snout leads a walk, so a
	-- walk never pushes it into a wall (snoutRoom). Nil: the root's box alone.
	body: RushWorld.Body?,
	-- A direct goal that is where the body stops (a slam's stop): the body stops dead on it (arrive).
	exact: boolean,
	-- The exact goal the body was stopped dead on (Engine.halt, arrive); nil until it is reached.
	halted: Vector3?,
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
	front: number, -- studs the body reaches ahead of its root (the snout), measured at spawn
	back: number, -- studs it reaches behind its root
	body: RushWorld.Body?, -- its corners at rest and its root's size: what a wall stops (D-205)
	footprint: Spacing.Footprint, -- the ground it takes up, measured at spawn: the room others keep (D-259)
	-- The mover's goal is a step out of another body (D-259), not the brain's: the next tick steps
	-- afresh from where the body stands rather than adding the step to it again.
	stepping: boolean,
	rushEndSent: boolean, -- this rush already told the clients it stopped early (D-169)
	-- The early stop told was "Jammed" or "Wall" (the body still on its way to the stop), and the
	-- stop that ended it after that was told too (D-210).
	rushEndEarly: boolean,
	rushEndFinal: boolean,
	rejoinPending: boolean, -- a stopped rush waits for a clear body to rejoin the enemies group (D-167)
	clearSince: number?, -- since when a waiting body has been clear of every player and enemy (D-190)
	-- The Studio test hooks (D-333): a walk the dev asked for (its brain does not decide meanwhile),
	-- and the log of a rush the dev started. Nil for every enemy the game runs by itself.
	walk: DevWalk?,
	devRush: DevRush?,
}

-- A dev walk (EnemyService.walk): where to, how near counts as there, until when, and whether to
-- hold the body once there.
export type DevWalk = { goal: Vector3, arriveStuds: number, endsAt: number, hold: boolean }
-- What the caller (DevCombat, dev.luau hooks) gives a walk: how near counts as there, how long it
-- may take, and whether the body is held once it is over.
export type DevWalkOptions = { arriveStuds: number, seconds: number, hold: boolean? }

-- A dev rush's log (EnemyService.charge, devRushOf): its launch (server time, crouch point, line)
-- and every stop told for it (reason, how far down its path, server time), in order.
export type DevRushStop = { reason: Brain.RushEnd, distance: number, at: number }
export type DevRush = {
	attackId: string,
	launched: { at: number, origin: Vector3, direction: Vector3 }?,
	stops: { DevRushStop },
}

local FORWARD = -Vector3.zAxis
local FOLDER_NAME = "Enemies"
local ALIGN_NAME = "SkyspireYaw"
local CORNER_SIGNS = { -1, 1 }

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
local frameList: { Entry } = {} -- the frame pass's snapshot, reused every frame (no garbage per frame)
-- Dead enemies whose blocker faces still stand (D-281): model -> the server time they go off.
local corpses: { [Model]: number } = {}

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

local function newMover(model: Model, speed: number, body: RushWorld.Body?): Mover
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
		pathFrom = nil,
		pathFresh = false,
		pathFailedAt = nil,
		computing = false,
		pathGeneration = 0,
		lastProgressAt = -math.huge,
		lastProgressPosition = nil,
		stuck = false,
		direct = false,
		pending = false,
		body = body,
		exact = false,
		halted = nil,
	}
end

-- Starts the stuck clock afresh: the next update measures progress from where the body stands then.
local function restartClock(mover: Mover)
	mover.lastProgressPosition = nil
	mover.stuck = false
end

-- Forgets the path and drops a result still computing (it was asked for another movement).
local function dropPath(mover: Mover)
	mover.path = nil
	mover.pathFresh = false
	mover.pathGeneration += 1
	mover.computing = false
end

-- `direct`: a strike's own movement, straight at the goal and never along a path (D-183). `exact`
-- (direct only): the goal is where the body stops, and it stops dead on it (arrive).
local function moverRequest(mover: Mover, goal: Vector3, speed: number, direct: boolean?, exact: boolean?)
	local isDirect = direct == true
	mover.exact = isDirect and exact == true
	if isDirect ~= mover.direct then
		-- A different kind of movement is a new movement: its own clock, and no path from the old one.
		mover.direct = isDirect
		restartClock(mover)
		dropPath(mover)
	end
	mover.goal = goal
	mover.speed = speed
	mover.pending = true
end

-- `dead`: the body stops dead where it stands (Engine.halt: a jammed or cancelled rush rests where its
-- end told every client, not a skid past it); otherwise it stops as the engine does (Humanoid:MoveTo
-- where it stands).
local function moverStop(mover: Mover, dead: boolean?)
	mover.goal = nil
	mover.pending = false
	mover.direct = false
	mover.exact = false
	mover.halted = nil
	if mover.moving then
		mover.moving = false
		mover.issuedGoal = nil
		-- A path still computing is for a goal that no longer exists; its result is dropped.
		dropPath(mover)
		local engine = dependencies().engine
		local halt = engine.halt
		if dead == true and halt ~= nil then
			halt(mover.model, nil)
		else
			engine.stop(mover.model)
		end
	end
end

-- How far a body facing `facing` walks along the flat unit `direction` before its leading corner meets
-- the face the walk cast found (`travelled`: how far the root's box, turned to face `direction` and
-- starting with its front at the root's centre, ran before it met a face of normal `normal`; nil:
-- head on): where the box would touch, moved by how much further than the box the body reaches
-- toward the face, over how fast the walk closes on it. Huge for a walk along the face.
local function walkRoom(
	body: RushWorld.Body,
	facing: Vector3,
	direction: Vector3,
	travelled: number,
	normal: Vector3?
): number
	local into = if normal ~= nil then Brain.horizontal(-normal) else nil
	local inward: Vector3 = into or direction
	local closing = direction:Dot(inward)
	if closing <= AI.flatEpsilon then
		return math.huge
	end
	local half = body.size / 2
	local square = CFrame.lookAt(Vector3.zero, direction)
	local boxInto = math.abs(square.RightVector:Dot(inward)) * half.X + math.abs(square.LookVector:Dot(inward)) * half.Z
	local bodyInto = RushWorld.support(body.profile, facing, inward)
	return travelled - half.Z + (boxInto - bodyInto) / closing
end

-- How far the body, facing `facing`, can walk along `direction` (flat, unit) within `distance` before
-- its snout meets a wall: `distance` when nothing is in the way or it is ground the body climbs (a
-- slope, a step), less than 0 when the snout would already stand inside one. A long body's head
-- reaches past its root's box, the only part that collides with the world (RigBuilder), so the
-- engine alone lets it walk its head into a wall. The cast asks about the world alone (players,
-- enemies and blockers are the engine's and Spacing's), with the root's box turned to face the walk,
-- moved by `offset` first when given (where the body is on its way to). The second value: the normal
-- of the face that cut the walk (nil when nothing did).
local function snoutWalk(
	mover: Mover,
	facing: Vector3,
	direction: Vector3,
	distance: number,
	offset: Vector3?
): (number, Vector3?)
	local body = mover.body
	local cast = dependencies().engine.worldAhead
	if body == nil or cast == nil then
		return distance, nil
	end
	local lead = RushWorld.support(body.profile, facing, direction)
	local face, ground, normal = cast(mover.model, direction, distance + lead, offset, true)
	if face == nil or ground == true then
		return distance, nil
	end
	local room = walkRoom(body, facing, direction, face, normal)
	if room >= distance then
		return distance, nil
	end
	return room, normal
end

-- Where a walk toward `target` stops so the body's snout never goes into a wall (snoutWalk), the
-- walk's own leading corner set on the face the way a slam's is (D-205). A walk that meets the face
-- at a slant slides along it from there (D-295): the rest of the walk, less its part into the face,
-- goes on along the face as far as the snout lets it, so a body walking up to a player who stands
-- by a wall (the walk a little into the wall, a side of the body already on it) still gets there
-- instead of stopping where it stands. The second value: whether the walk was cut short or bent
-- (its goal is issued at once, never left to the re-issue rule, which would let the body walk on to
-- the longer goal it last heard).
local function snoutRoom(mover: Mover, position: Vector3, target: Vector3): (Vector3, boolean)
	if mover.body == nil then
		return target, false
	end
	local offset = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
	local distance = offset.Magnitude
	if distance < AI.flatEpsilon then
		return target, false
	end
	local direction = offset / distance
	local facing = dependencies().engine.facing(mover.model)
	local room, normal = snoutWalk(mover, facing, direction, distance)
	if room >= distance then
		return target, false
	end
	local stop = direction * math.max(0, room)
	local into = if normal ~= nil then Brain.horizontal(-normal) else nil
	if into ~= nil then
		local rest = offset - stop
		local along = rest - into * rest:Dot(into)
		local length = along.Magnitude
		if length >= AI.flatEpsilon then
			local slide = along / length
			local slid = snoutWalk(mover, facing, slide, length, stop)
			if slid > 0 then
				stop += slide * slid
			end
		end
	end
	return Vector3.new(position.X + stop.X, target.Y, position.Z + stop.Z), true
end

-- How far the body, turned to `facing` where it stands, could walk that way before its snout meets a
-- wall (negative: the snout would stand inside it); its whole front's reach when nothing is that near.
-- A walking body is judged where it stands, not where it is walking to (D-295): the walk to a stop by
-- a wall is cut so the snout as it faces now just meets the face there, so at that stop nearly every
-- other facing reads deeper and a body on its way could not turn at all. The walk itself is checked
-- again with the facing it then has (snoutRoom, every AI tick), which cuts it at once if a turn on
-- the way would carry the snout into the wall.
local function snoutAhead(mover: Mover, facing: Vector3): number
	local body = mover.body
	if body == nil then
		return math.huge
	end
	local room = snoutWalk(mover, facing, facing, RushWorld.support(body.profile, facing, facing))
	return room
end

-- Whether a walking body may turn to `facing`: not when the turn would swing its snout more than
-- movement.snoutSlackStuds into a wall, unless it stands no deeper than it does now (a turn away). A
-- strike's own movement turns by its own rules (RushWorld, D-206).
local function canFace(mover: Mover, facing: Vector3): boolean
	if mover.direct then
		return true
	end
	local room = snoutAhead(mover, facing)
	if room >= -AI.movement.snoutSlackStuds then
		return true
	end
	return room >= snoutAhead(mover, dependencies().engine.facing(mover.model))
end

-- `urgent`: a goal that must be heard at once (a walk cut short at a wall), whatever the re-issue rule.
local function issue(mover: Mover, target: Vector3, now: number, urgent: boolean?)
	local engine = dependencies().engine
	local issued = mover.issuedGoal
	if
		issued == nil
		or (target - issued).Magnitude >= AI.movement.reissueStuds
		or now - mover.issuedAt >= AI.movement.reissueInterval
		or (urgent == true and (target - issued).Magnitude >= AI.flatEpsilon)
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
			-- The first waypoint is where the body stood when it asked; a path that lands after the body
			-- moved on must never walk it back there (D-183).
			local startsHere = #waypoints >= 2
				and Brain.horizontalDistance(waypoints[1], from) <= AI.movement.waypointReach
			mover.pathIndex = if startsHere then 2 else 1
			mover.pathFrom = from
			mover.pathFresh = true
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

-- The first waypoint from `index` on that a path which landed late still has the body walk to
-- (D-196). A leading waypoint is passed when the body is within waypointReach of it, or when the
-- body is on the leg that leaves it (within waypointReach of that leg), past its start, and walked
-- at least stuckProgressStuds that way since it asked for the path (from `from`). A detour that goes
-- back round an obstacle starts with a leg the body is not on, and a body that asked because it was
-- stuck walked nowhere since, so both keep every waypoint. The last waypoint is passed only within
-- reach.
local function firstAhead(path: { Vector3 }, index: number, position: Vector3, from: Vector3): number
	local movement = AI.movement
	local i = index
	while i < #path do
		local start = path[i]
		if Brain.horizontalDistance(position, start) > movement.waypointReach then
			local leg = Brain.horizontal(path[i + 1] - start)
			if leg == nil then
				break
			end
			local offset = Vector3.new(position.X - start.X, 0, position.Z - start.Z)
			local along = offset:Dot(leg)
			local walked = Vector3.new(position.X - from.X, 0, position.Z - from.Z):Dot(leg)
			if
				along <= 0
				or (offset - leg * along).Magnitude > movement.waypointReach
				or walked < movement.stuckProgressStuds
			then
				break
			end
		end
		i += 1
	end
	return i
end

-- Applies the tick's request: direct MoveTo inside pathfindPastStuds, a path beyond it or when stuck;
-- a strike's own movement (direct) always goes straight.
local function moverUpdate(mover: Mover, now: number)
	mover.pending = false
	local goal = mover.goal
	if goal == nil then
		moverStop(mover)
		return
	end
	local engine = dependencies().engine
	local movement = AI.movement
	if not mover.moving then
		-- A new movement from standing (after a stop, a hold or a sleep): standing is not being stuck,
		-- so its clock starts now (D-183).
		restartClock(mover)
	end
	mover.moving = true
	if mover.walkSpeed ~= mover.speed then
		engine.setWalkSpeed(mover.model, mover.speed)
		mover.walkSpeed = mover.speed
	end
	if mover.direct then
		issue(mover, goal, now)
		return
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
		local room, cut = snoutRoom(mover, position, goal)
		issue(mover, room, now, cut)
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
			if mover.pathFresh then
				mover.pathFresh = false
				mover.pathIndex = firstAhead(path, mover.pathIndex, position, mover.pathFrom or position)
			end
			while
				mover.pathIndex <= #path
				and Brain.horizontalDistance(position, path[mover.pathIndex]) <= movement.waypointReach
			do
				mover.pathIndex += 1
			end
			if mover.pathIndex <= #path then
				local room, cut = snoutRoom(mover, position, path[mover.pathIndex])
				issue(mover, room, now, cut)
				return
			end
			mover.path = nil -- walked to its end; the goal is in direct reach
		end
	end
	local room, cut = snoutRoom(mover, position, goal)
	issue(mover, room, now, cut)
end

-- A strike's own movement to where it stops (`exact`: a slam's stop) that would reach it before the
-- next server frame (at its speed over this frame's seconds, at most movement.haltLeadSeconds) stops
-- dead on it (Engine.halt): the body rests on the stop the rush told every client (D-208), never a
-- skid past it. Once per goal.
local function arrive(mover: Mover, dt: number)
	local goal = mover.goal
	if not mover.exact or not mover.moving or goal == nil then
		return
	end
	local engine = dependencies().engine
	local halt = engine.halt
	if halt == nil then
		return
	end
	local halted = mover.halted
	if halted ~= nil and Brain.horizontalDistance(halted, goal) < AI.flatEpsilon then
		return
	end
	local lead = mover.speed * math.clamp(dt, 0, AI.movement.haltLeadSeconds)
	if Brain.horizontalDistance(engine.position(mover.model), goal) <= lead + AI.flatEpsilon then
		mover.halted = goal
		halt(mover.model, goal)
	end
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

local function strike(
	entry: Entry,
	attack: Types.EnemyAttackDef,
	origin: Vector3,
	facing: Vector3,
	options: Types.EnemyStrikeOptions?
)
	local d = dependencies()
	local combat = d.combat
	if combat == nil or typeof(combat.enemyStrike) ~= "function" then
		if not warnedNoCombat then
			warnedNoCombat = true
			warn("[EnemyService] CombatService.enemyStrike is not available; enemy strikes do no damage")
		end
		return
	end
	local ok, err = pcall(combat.enemyStrike, entry.id, attack, origin, Brain.horizontal(facing) or FORWARD, options)
	if not ok then
		warn(("[EnemyService] enemyStrike failed for entity %d (%s): %s"):format(entry.id, entry.defId, tostring(err)))
	end
end

-- Puts an enemy's parts in a collision group through the engine (D-167).
local function setGroup(model: Model, group: string)
	local setter = dependencies().engine.setCollisionGroup
	if setter ~= nil then
		setter(model, group)
	end
end

-- A rush launched (D-169): the body passes through players and enemies until it stops (D-167), and
-- every client hears the line and the clock to draw it on.
local function rushStarted(entry: Entry, rush: Brain.Rush)
	local d = dependencies()
	entry.rushEndSent = false
	entry.rushEndEarly = false
	entry.rushEndFinal = false
	entry.rejoinPending = false
	entry.clearSince = nil
	setGroup(entry.model, AI.collision.rushing)
	d.fireAll("RushStarted", {
		entityId = entry.id,
		attackId = rush.attackId,
		serverTime = rush.startedAt,
		origin = toVec3(rush.origin),
		direction = unitVec3(rush.direction),
		speed = rush.speed,
		duration = rush.duration,
	})
	-- A dev charge's log (D-333) takes its launch; a later rush of its own ends the log.
	local log = entry.devRush
	if log ~= nil then
		if log.launched == nil then
			log.launched = { at = rush.startedAt, origin = rush.origin, direction = rush.direction }
		else
			entry.devRush = nil
		end
	end
end

-- A rush stopped: an early stop is told once, with where the body meets the wall for a slam
-- (D-208); a "Jammed" or a "Wall" (the body still on its way to its stop) is followed by the stop
-- that ends it, once, when an interrupt, a death or a sleep comes before the run's end, so every
-- client hands the body back where the server's stopped (D-210). Every stop but a slam's (a jam
-- stops the body too, D-190) waits to rejoin the enemies group until the body has stayed clear long
-- enough (rejoin, from tickAll); a slam's body waits from the stop that ends its rush.
-- The RushEnded payload for a stop (Types.RushEndedPayload, the remote's own reasons): told as
-- itself, every stop but a run that ran its time ("Done"), which is never told (nil); `contact`
-- and `normal` for a slam only.
local function endedPayload(
	id: number,
	launchedAt: number,
	serverTime: number,
	reason: Brain.RushEnd,
	distance: number,
	contact: RushWorld.Contact?
): Types.RushEndedPayload?
	local told: Types.RushEndedReason
	if reason == "Jammed" then
		told = "Jammed"
	elseif reason == "Wall" then
		told = "Wall"
	elseif reason == "Interrupted" then
		told = "Interrupted"
	elseif reason == "Died" then
		told = "Died"
	elseif reason == "Stopped" then
		told = "Stopped"
	else
		return nil
	end
	local wall = if reason == "Wall" then contact else nil
	return {
		entityId = id,
		launchedAt = launchedAt,
		serverTime = serverTime,
		distance = math.max(0, distance),
		reason = told,
		contact = if wall ~= nil then toVec3(wall.point) else nil,
		normal = if wall ~= nil then unitVec3(wall.normal) else nil,
	}
end

local function rushEnded(
	entry: Entry,
	rush: Brain.Rush,
	reason: Brain.RushEnd,
	distance: number,
	contact: RushWorld.Contact?
)
	local d = dependencies()
	local tell = false
	if reason ~= "Done" and not entry.rushEndSent then
		tell = true
		entry.rushEndSent = true
		entry.rushEndEarly = reason == "Jammed" or reason == "Wall"
	elseif
		reason ~= "Done"
		and entry.rushEndEarly
		and not entry.rushEndFinal
		and reason ~= "Jammed"
		and reason ~= "Wall"
	then
		tell = true
		entry.rushEndFinal = true
	end
	local payload = if tell
		then endedPayload(entry.id, rush.startedAt, d.serverTime(), reason, distance, contact)
		else nil
	if payload ~= nil then
		d.fireAll("RushEnded", payload)
	end
	local log = entry.devRush
	if log ~= nil and log.launched ~= nil then
		table.insert(log.stops, { reason = reason, distance = math.max(0, distance), at = d.serverTime() })
	end
	-- A slam's body is still on its way to its stop (passing through players, D-167): its wait starts
	-- with the stop that ends the rush (the daze's interrupt, a death, its run's end).
	if not entry.rejoinPending and reason ~= "Wall" then
		entry.rejoinPending = true
		entry.clearSince = nil
	end
end

-- A rush's path bent along a glancing wall or sidestepped a clipped corner (D-206, D-207): every client
-- hears its legs (the whole path, so a lost message is mended by the next) and where the body meets
-- the face, to draw it on that path.
local function rushTurned(entry: Entry, rush: Brain.Rush, contact: RushWorld.Contact)
	local d = dependencies()
	local legs = table.create(#rush.legs)
	for _, leg in rush.legs do
		table.insert(legs, {
			at = leg.at,
			from = toVec3(leg.from),
			heading = unitVec3(leg.heading),
			facing = unitVec3(leg.facing),
		})
	end
	d.fireAll("RushTurned", {
		entityId = entry.id,
		launchedAt = rush.startedAt,
		serverTime = d.serverTime(),
		kind = contact.kind,
		at = math.max(0, contact.at),
		legs = legs,
		contact = toVec3(contact.point),
		normal = unitVec3(contact.normal),
	})
end

-- An enemy's blocker faces (D-198, D-315): every part of its model in the blockers group, the
-- body's and one over each part it holds (a kobold's axe); empty when it has none.
local function blockersOf(model: Model): { BasePart }
	local faces: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.CollisionGroup == AI.collision.blockers then
			table.insert(faces, child)
		end
	end
	return faces
end

-- Its blocker faces flat in its root's space (Spacing.Face, D-332): each stands along the root's
-- axes (RigBuilder.addBlocker), so its middle and half its width and depth are all a face needs.
local function facesOf(model: Model): { Spacing.Face }
	local root = model.PrimaryPart
	local faces: { Spacing.Face } = {}
	if root == nil then
		return faces
	end
	for _, part in blockersOf(model) do
		local centre = root.CFrame:PointToObjectSpace(part.CFrame.Position)
		table.insert(faces, {
			centre = Vector3.new(centre.X, 0, centre.Z),
			half = Vector3.new(part.Size.X / 2, 0, part.Size.Z / 2),
		})
	end
	return faces
end

-- Whether two upright boxes overlap (separating axes: the vertical, then each box's two horizontal
-- axes; a blocker turns with its root's yaw only).
local function uprightBoxesOverlap(a: BasePart, b: BasePart): boolean
	local ha, hb = a.Size / 2, b.Size / 2
	local fa, fb = a.CFrame, b.CFrame
	local between = fb.Position - fa.Position
	if math.abs(between.Y) >= ha.Y + hb.Y then
		return false
	end
	for _, axis in { fa.RightVector, fa.LookVector, fb.RightVector, fb.LookVector } do
		local flat = Brain.horizontal(axis)
		if flat ~= nil then
			local reachA = math.abs(fa.RightVector:Dot(flat)) * ha.X + math.abs(fa.LookVector:Dot(flat)) * ha.Z
			local reachB = math.abs(fb.RightVector:Dot(flat)) * hb.X + math.abs(fb.LookVector:Dot(flat)) * hb.Z
			if math.abs(between:Dot(flat)) >= reachA + reachB then
				return false
			end
		end
	end
	return true
end

--- Whether an enemy's blocker stands clear of every other solid enemy's (D-281): a solid blocker
--- meets other enemies' roots and blockers, so a stopped rush whose body stands over a packmate's
--- would be pushed out of it the moment it turned solid. A blocker covers its body's whole
--- footprint, root included, from the floor up past every root's top, so blocker against blocker
--- settles root against blocker too. Every face counts, on both sides: the body's and the one over
--- each part an enemy holds (D-315: a kobold's axe face is solid with its body's). Judged on the
--- parts' own boxes: the engine's queries never see a blocker (CanQuery off). A model with no
--- blocker is clear. A body that died counts too while its faces still stand (until it shatters,
--- see sweepCorpses): the engine pushes out of a corpse's solid face as out of a living one's.
function EnemyService.blockerClear(model: Model): boolean
	local own = blockersOf(model)
	if #own == 0 then
		return true
	end
	local function meets(other: Model): boolean
		if other == model then
			return false
		end
		for _, theirs in blockersOf(other) do
			if theirs.CanCollide then
				for _, face in own do
					if uprightBoxesOverlap(face, theirs) then
						return true
					end
				end
			end
		end
		return false
	end
	for _, entry in entries do
		if meets(entry.model) then
			return false
		end
	end
	for corpse in corpses do
		if meets(corpse) then
			return false
		end
	end
	return true
end

-- A stopped rush's body rejoins the enemies group once its root has overlapped no player and no
-- enemy, and its blocker no other solid enemy's (D-281), for ai.collision.rejoinClearSeconds in a
-- row, so the engine never has to push two bodies apart (that push is what lifted one boar onto
-- another). The wait outlasts the time every client draws a server body late (D-190): a body that
-- turned solid the moment the server saw it clear was still drawn inside the player it had just
-- run through, still moving, and the engine pushed that player out at the rush's speed, up onto
-- its back.
local function rejoin(entry: Entry, now: number)
	if not entry.rejoinPending then
		return
	end
	local clear = dependencies().engine.bodyClear
	if (clear ~= nil and not clear(entry.model)) or not EnemyService.blockerClear(entry.model) then
		entry.clearSince = nil
		return
	end
	local since: number = entry.clearSince or now
	entry.clearSince = since
	if now - since >= AI.collision.rejoinClearSeconds then
		entry.rejoinPending = false
		entry.clearSince = nil
		setGroup(entry.model, AI.collision.enemies)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Room between enemies (D-259)
-- ---------------------------------------------------------------------------------------------

-- Deciding or walking (ai.luau spacing.freePhases): a body that may move to keep its room. Busy
-- (mid-attack, staggered, dead), asleep, held and rooted (moveSpeed 0) bodies stay where they are.
local function isFree(entry: Entry): boolean
	return entry.awake
		and not entry.held
		and entry.def.moveSpeed > 0
		and AI.spacing.freePhases[entry.brain:getPhase()] == true
end

local function spacingBody(entry: Entry): Spacing.Body
	local engine = dependencies().engine
	return {
		position = engine.position(entry.model),
		facing = engine.facing(entry.model),
		footprint = entry.footprint,
	}
end

-- Where `entry` would stand nearest `point` with its room to every other enemy (Spacing.standOff).
local function standOffFor(entry: Entry, point: Vector3): Vector3
	local others: { Spacing.Body } = {}
	for _, other in entries do
		if other ~= entry then
			table.insert(others, spacingBody(other))
		end
	end
	return Spacing.standOff(spacingBody(entry), point, others, AI.spacing.gapStuds, Vector3.xAxis)
end

-- After a free enemy's tick: its goal moves out of any other body, a walk into one slides along it,
-- and a body inside another's room steps out (Spacing.steer). A strike's own movement (the rush)
-- is never steered.
local function keepRoom(entry: Entry)
	local mover = entry.mover
	if mover.direct or not isFree(entry) then
		return
	end
	local neighbors: { Spacing.Neighbor } = {}
	for _, other in entries do
		if other ~= entry then
			table.insert(neighbors, {
				body = spacingBody(other),
				share = if isFree(other) then 0.5 else 1,
				side = if entry.id < other.id then 1 else -1,
			})
		end
	end
	if #neighbors == 0 then
		return
	end
	local goal = if entry.stepping then nil else mover.goal
	local target = Spacing.steer(spacingBody(entry), goal, neighbors)
	if target == nil then
		return
	end
	if goal ~= nil and mover.path ~= nil and Brain.horizontalDistance(target, goal) >= AI.flatEpsilon then
		-- A turn along another body is a short, straight walk: the path to the old goal waits.
		dropPath(mover)
	end
	local speed = if goal ~= nil then mover.speed else entry.def.moveSpeed * AI.spacing.stepSpeedMultiplier
	moverRequest(mover, target, speed, false)
	entry.stepping = goal == nil
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
		moveTo = function(position, speed, direct, exact)
			entry.stepping = false
			moverRequest(mover, position, speed, direct, exact)
		end,
		stop = function()
			entry.stepping = false
			moverStop(mover)
		end,
		halt = function()
			entry.stepping = false
			moverStop(mover, true)
		end,
		standOff = function(point)
			return standOffFor(entry, point)
		end,
		face = function(direction)
			d.engine.setFacing(model, direction)
		end,
		canFace = function(direction)
			return canFace(mover, direction)
		end,
		telegraph = function(attack, origin, facing, shape)
			fireTelegraph(entry, attack, origin, facing, shape)
		end,
		strike = function(attack, origin, facing, options)
			strike(entry, attack, origin, facing, options)
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
		bodyExtents = function()
			return entry.front, entry.back
		end,
		bodyProfile = function()
			return entry.body
		end,
		worldAhead = function(direction, distance, offset)
			local cast = d.engine.worldAhead
			if cast == nil then
				return nil, nil, nil
			end
			return cast(model, direction, distance, offset)
		end,
		rootReach = function(direction)
			return EnemyService.rootReach(model, direction)
		end,
		rushStarted = function(rush)
			rushStarted(entry, rush)
		end,
		rushEnded = function(rush, reason, distance, contact)
			rushEnded(entry, rush, reason, distance, contact)
		end,
		rushTurned = function(rush, contact)
			rushTurned(entry, rush, contact)
		end,
		attackDropped = function(beat)
			-- Reliable, on the beat the clients keep the attack by (its wind-up's end): each drops the
			-- swing, the tell and a launch its telegraph predicted (Replication, D-254). A rush's own
			-- remote, so it stays in order with the launch and the stop it stands in for.
			local payload: Types.RushEndedPayload = {
				entityId = id,
				launchedAt = math.max(0, beat),
				serverTime = d.serverTime(),
				distance = 0,
				reason = "Dropped",
			}
			d.fireAll("RushEnded", payload)
		end,
		daze = function(seconds)
			-- A slam (D-208): a Stagger from the front, through EntityService like a parry's, which
			-- interrupts this brain (connectSignals) and tells every client.
			d.entities.setState(id, "Stagger", seconds, "Front")
		end,
		extendState = function(seconds)
			if typeof(d.entities.extendState) == "function" then
				d.entities.extendState(id, seconds)
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
	if reason == "Died" then
		-- The body stands frozen until every client shatters it (D-281): its faces stay until then.
		corpses[entry.model] = dependencies().serverTime() + Moments.deathDuckDelay() + Combat.deathFreeze
	end
	EnemyService.Despawned:Fire(id, entry.defId, reason)
end

-- A corpse's blocker faces (D-281): solid while the frozen body still stands, so nothing walks or
-- turns solid inside a body still drawn; off from the moment every client shatters it (the kill's
-- hit-stop, Moments.deathDuckDelay, then Combat.deathFreeze), so nobody bumps into a body no longer
-- drawn while the model waits out Combat.corpseRemoveDelay. A model already gone is let go.
local function sweepCorpses(now: number)
	for model, offAt in corpses do
		if model.Parent == nil then
			corpses[model] = nil
		elseif now >= offAt then
			for _, face in blockersOf(model) do
				face.CanCollide = false
			end
			corpses[model] = nil
		end
	end
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
	-- Measured on the rig as built (every part at its rest pose around the root), before it moves.
	local front, back = EnemyService.bodyExtents(model)
	local root = model.PrimaryPart
	local body: RushWorld.Body? = if root ~= nil
		then { profile = RushWorld.profileOf(model), size = root.Size }
		else nil
	-- What players bump into instead of the root (D-198); the enemies group switches it on.
	if typeof(d.rigBuilder.addBlocker) == "function" then
		d.rigBuilder.addBlocker(model)
	end
	-- The room it keeps from other enemies (D-259): every blocker face it was just given counts
	-- (D-332): since D-281 a face meets every other enemy's faces.
	local footprint = Spacing.footprintOf(if body ~= nil then body.profile else {}, facesOf(model))
	setGroup(model, AI.collision.enemies)
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
		mover = newMover(model, def.moveSpeed, body),
		awake = true,
		held = false,
		home = d.engine.position(model),
		front = front,
		back = back,
		body = body,
		footprint = footprint,
		stepping = false,
		rushEndSent = false,
		rushEndEarly = false,
		rushEndFinal = false,
		rejoinPending = false,
		clearSince = nil,
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

--- Hit-stop on an enemy (D-168): CombatService calls it (setEnemyHitStop) when a player's hit on
--- the enemy is confirmed, with the seconds every client freezes the enemy's clip for. An unresolved
--- attack (the wind-up, or the strike before it resolves) pauses with it: Brain.pauseAttack moves
--- the wind-up's end, the strike beat, the cooldown and the Art state, capped per attack by
--- ai.hitStop.maxPausePerAttack. Returns the seconds added (0 when capped, or for a rush already
--- on its way), or nil when the enemy is gone or has no unresolved attack.
function EnemyService.pauseForHit(id: number, seconds: number): number?
	local entry = entries[id]
	if entry == nil then
		return nil
	end
	return entry.brain:pauseAttack(seconds)
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
-- Studio test hooks (D-333): DevCombat's "enemy", "walk" and "charge". The game never calls them.
-- ---------------------------------------------------------------------------------------------

-- Drops whatever a living enemy was doing the way a hold does (its brain sleeps: an attack in its
-- wind-up is dropped and told, a launched rush stops and is told; its mover stops; a dev walk
-- ends), then wakes it at once, free and in Idle.
local function rouse(entry: Entry)
	entry.walk = nil
	hold(entry)
	entry.held = false
	holdRegen(entry.id, false)
	entry.awake = true
	entry.brain:wake()
end

-- Why a living enemy cannot take a dev walk or charge now (staggered, dazed or dead), or nil.
local function busyFor(entry: Entry): string?
	local phase = entry.brain:getPhase()
	if phase == "Interrupted" or phase == "Dead" then
		return ("it is %s (%s); try again once it recovers"):format(phase, tostring(entry.brain.interruptState))
	end
	return nil
end

-- A dev walk's tick (EnemyService.walk), in place of the brain's: the body turns toward the goal at
-- its archetype's rate (turnToward; the frame pass carries the turn out) and walks there at its own
-- pace through the mover; the room rules (keepRoom) and the mover run after it as after any tick.
local function walkTick(entry: Entry, now: number, step: number): boolean
	local walk = entry.walk
	if walk == nil then
		return true
	end
	local brain = entry.brain
	if brain:getPhase() ~= "Idle" then
		entry.walk = nil -- an interrupt (a hit's stagger) took over: the brain decides from here
		return true
	end
	local position = dependencies().engine.position(entry.model)
	if Brain.horizontalDistance(position, walk.goal) <= walk.arriveStuds or now >= walk.endsAt then
		entry.walk = nil
		brain:enterIdle(now) -- stops the mover and the turn
		entry.home = position
		if walk.hold then
			hold(entry)
		end
		return true
	end
	local direction = Brain.horizontal(walk.goal - position)
	if direction ~= nil then
		brain:turnToward(direction, brain.tuning.turnRate, step)
	end
	entry.stepping = false
	moverRequest(entry.mover, walk.goal, entry.def.moveSpeed, false)
	return true
end

--- Places a living enemy (a Studio test hook, D-333): whatever it was doing is dropped the way a
--- hold drops it (an attack in its wind-up is told dropped, a launched rush stops and is told, a dev
--- walk ends), its body pivots to `cframe` (the look's flat part is its facing), stops dead there
--- and takes it as its home. `held` leaves it held; otherwise the sleep rules take it back on the
--- next tick and its brain starts afresh in Idle, as a spawned one does, under every server rule
--- (its room to other enemies, its hits, its walls). False when `id` is no living enemy.
function EnemyService.place(id: number, cframe: CFrame, held: boolean?): boolean
	local entry = entries[id]
	if entry == nil then
		return false
	end
	local engine = dependencies().engine
	local model = entry.model
	entry.walk = nil
	entry.devRush = nil
	hold(entry)
	local pivot = engine.pivot
	if pivot ~= nil then
		pivot(model, cframe)
	else
		model:PivotTo(cframe)
	end
	local look = Brain.horizontal(cframe.LookVector) or FORWARD
	engine.setFacing(model, look)
	entry.brain.facingDir = look
	-- The hold stopped the body where it stood before the move, and a Humanoid walks back to the
	-- spot it was stopped on: stop it dead where it stands now.
	local halt = engine.halt
	if halt ~= nil then
		halt(model, nil)
	else
		engine.stop(model)
	end
	restartClock(entry.mover)
	entry.mover.halted = nil
	entry.stepping = false
	entry.home = engine.position(model)
	if held ~= true then
		entry.held = false
		holdRegen(id, false)
		lastSleepCheck = -math.huge
	end
	return true
end

--- Walks a living enemy to `goal` (a Studio test hook, D-333): whatever it was doing is dropped the
--- way a hold drops it, then it walks there awake at its own pace (its def's moveSpeed), turning at
--- its archetype's rate, through the mover (a path past a wall, the stuck clock, the snout's room)
--- with its room to every other enemy kept (keepRoom); its brain decides nothing meanwhile. The
--- walk is over once the root stands within options.arriveStuds of the goal, after
--- options.seconds, or when the brain leaves Idle (a hit's stagger, a death); the brain then takes
--- over where the body stands, its home there, held when options.hold. False (and why) when `id`
--- is no living enemy or the body cannot walk now.
function EnemyService.walk(id: number, goal: Vector3, options: DevWalkOptions): (boolean, string?)
	local entry = entries[id]
	if entry == nil then
		return false, "no living enemy"
	end
	if entry.def.moveSpeed <= 0 then
		return false, "it is rooted (moveSpeed 0)"
	end
	local busy = busyFor(entry)
	if busy ~= nil then
		return false, busy
	end
	entry.devRush = nil
	rouse(entry)
	entry.walk = {
		goal = goal,
		arriveStuds = options.arriveStuds,
		endsAt = dependencies().serverTime() + options.seconds,
		hold = options.hold == true,
	}
	return true, nil
end

--- Whether a living enemy is on a dev walk (EnemyService.walk).
function EnemyService.walking(id: number): boolean
	local entry = entries[id]
	return entry ~= nil and entry.walk ~= nil
end

--- Starts a Charger's rush at `toward` (a Studio test hook, D-333): whatever it was doing is dropped
--- the way a hold drops it, it wakes facing the point at once (Charger.charge) and crouches; from
--- there the rush runs Charger's normal path: the telegraph and the clip, the wind-up's hold, the
--- launch along the facing, the sweep that hits on contact, the glance, clip, slam and jam stops,
--- the daze and the recovery, after which the brain takes over. devRushOf(id) reads back its launch
--- and its stops. False (and why) when `id` is no living enemy, has no rush, is staggered or dead,
--- or the point is where it stands.
function EnemyService.charge(id: number, toward: Vector3): (boolean, string?)
	local entry = entries[id]
	if entry == nil then
		return false, "no living enemy"
	end
	local attack = Charger.rushOf(entry.def)
	if ARCHETYPES[entry.def.archetype] ~= Charger or attack == nil then
		return false, ("%s is no Charger with a rush"):format(entry.def.id)
	end
	local busy = busyFor(entry)
	if busy ~= nil then
		return false, busy
	end
	local direction = Brain.horizontal(toward - dependencies().engine.position(entry.model))
	if direction == nil then
		return false, "the point is where it stands"
	end
	rouse(entry)
	entry.devRush = { attackId = attack.id, launched = nil, stops = {} }
	local started, reason = Charger.charge(entry.brain, direction)
	if not started then
		entry.devRush = nil
	end
	return started, reason
end

--- How the rush the last charge(id) started launched and stopped (server times, the stops in the
--- order told), or nil: no living enemy, no dev charge, or a later rush of its own since.
function EnemyService.devRushOf(id: number): DevRush?
	local entry = entries[id]
	return if entry ~= nil then entry.devRush else nil
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
		if entry.walk ~= nil then
			continue -- a dev walk (D-333) keeps its body awake until it is over
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

-- One brain's tick and one brain's frame pass, each run under pcall so a failing brain never stops
-- the others (each returns a value so pcall's two results keep their types).
local function runTick(brain: Brain.Brain, step: number): boolean
	brain:tick(step)
	return true
end

local function runFrame(brain: Brain.Brain): boolean
	brain:frame()
	return true
end

local function tickAll(step: number)
	local d = dependencies()
	local now = d.serverTime()
	currentPlayers = d.players()
	refreshSleep(now)
	sweepCorpses(now)
	local snapshot = {}
	for _, entry in entries do
		table.insert(snapshot, entry)
	end
	for _, entry in snapshot do
		if entries[entry.id] ~= entry then
			continue
		end
		rejoin(entry, now) -- asleep or held too: a stopped rush still waits for a clear body
		if not entry.awake then
			continue
		end
		local ok, err
		if entry.walk ~= nil then
			ok, err = pcall(walkTick, entry, now, step)
		else
			ok, err = pcall(runTick, entry.brain, step)
		end
		if not ok then
			warn(("[EnemyService] brain of entity %d (%s) failed: %s"):format(entry.id, entry.defId, tostring(err)))
		end
		if entries[entry.id] == entry then
			keepRoom(entry)
		end
		moverUpdate(entry.mover, now)
	end
end

-- The frame pass (D-184, D-185): every awake brain resolves the attack edges due by now (the
-- wind-up's end, the strike, a rush's stretches and run) and turns its body for the frame; a
-- movement it asked for on the way (the rush's launch) reaches the mover in the same frame, and a
-- strike's own movement about to reach its goal stops dead on it (arrive). Asleep, held and dead
-- enemies are skipped.
local function frameAll(dt: number)
	local d = dependencies()
	local now = d.serverTime()
	table.clear(frameList) -- a pass that errored out last frame left its snapshot behind
	for _, entry in entries do
		if entry.awake then
			table.insert(frameList, entry)
		end
	end
	for _, entry in frameList do
		if entries[entry.id] ~= entry or not entry.awake then
			continue -- a strike earlier in this pass killed or put it to sleep
		end
		local ok, err = pcall(runFrame, entry.brain)
		if not ok then
			warn(("[EnemyService] frame of entity %d (%s) failed: %s"):format(entry.id, entry.defId, tostring(err)))
		end
		if entry.mover.pending then
			moverUpdate(entry.mover, now)
		end
		arrive(entry.mover, dt)
	end
	table.clear(frameList)
end

--- Advances the service by a frame's dt: whole AI ticks run at ai.tickHz (perception, decisions,
--- movement); after a hitch at most ai.maxTicksPerFrame run and the rest of the backlog is dropped.
--- Then the frame pass runs every awake brain once: the attack edges on their beats at the server's
--- frame precision and the body turns (D-184, D-185). Heartbeat calls it; tests and the smoke script
--- call it by hand.
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
	frameAll(dt)
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

--- How far a model's body reaches ahead of (`front`) and behind (`back`) its root along the root's
--- look, over every corner of every BasePart of its body as the parts stand now (spawn() measures
--- the rig as built, at its rest pose). A rush strikes where the snout is (D-166). Its blocker
--- faces (the blockers group, D-198) are not its body: they stand over its idle and what it holds
--- (D-315), so a live enemy reaches as far as the rig spawn() measured. (0, 0) without a root.
function EnemyService.bodyExtents(model: Model): (number, number)
	local root = model.PrimaryPart
	if root == nil then
		return 0, 0
	end
	local rootFrame = root.CFrame
	local front, back = 0, 0
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.CollisionGroup == AI.collision.blockers then
			continue
		end
		local half = part.Size / 2
		local frame = part.CFrame
		for _, x in CORNER_SIGNS do
			for _, y in CORNER_SIGNS do
				for _, z in CORNER_SIGNS do
					local corner = Vector3.new(half.X * x, half.Y * y, half.Z * z)
					local along = rootFrame:PointToObjectSpace(frame:PointToWorldSpace(corner)).Z
					front = math.max(front, -along) -- the root looks down -Z
					back = math.max(back, along)
				end
			end
		end
	end
	return front, back
end

--- The yaw align on an enemy's root (nil once the corpse is gone). Looked up rather than cached per
--- model: EntityService destroys corpses, so a cache keyed by Model would leak one entry per kill.
--- Found by class as well as name: the root also holds the align's Attachment under the same name,
--- and a lookup by name alone returns whichever came first (the Attachment), so the body never
--- turned (D-165).
function EnemyService.alignOf(model: Model): AlignOrientation?
	local root = model.PrimaryPart
	if root == nil then
		return nil
	end
	local first = root:FindFirstChildOfClass("AlignOrientation")
	if first ~= nil and first.Name == ALIGN_NAME then
		return first
	end
	for _, child in root:GetChildren() do
		if child.Name == ALIGN_NAME and child:IsA("AlignOrientation") then
			return child
		end
	end
	return nil
end

--- Gives an enemy's root its yaw align: an Attachment and a rigid one-attachment AlignOrientation,
--- both named ALIGN_NAME, holding `look` (flattened). place() calls it once per enemy, never the tick.
function EnemyService.addYawAlign(root: BasePart, look: Vector3): AlignOrientation
	local attachment = Instance.new("Attachment")
	attachment.Name = ALIGN_NAME
	attachment.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = ALIGN_NAME
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.CFrame = CFrame.lookAt(Vector3.zero, Brain.horizontal(look) or FORWARD)
	align.Parent = root
	return align
end

--- Turns an enemy's body: writes the flat facing into its yaw align. False when the model has no
--- align or the facing has no horizontal direction.
function EnemyService.applyFacing(model: Model, facing: Vector3): boolean
	local align = EnemyService.alignOf(model)
	local flat = Brain.horizontal(facing)
	if align == nil or flat == nil then
		return false
	end
	align.CFrame = CFrame.lookAt(Vector3.zero, flat)
	return true
end

local castParams: RaycastParams? = nil

-- workspace:Blockcast with the parts that collide with `group` and can collide (a hitbox, a
-- decoration that lets bodies through, is not a wall).
local function defaultWorldCast(
	start: CFrame,
	size: Vector3,
	vector: Vector3,
	group: string,
	exclude: Instance
): (number?, Vector3?)
	local params = castParams
	if params == nil then
		local created = RaycastParams.new()
		created.FilterType = Enum.RaycastFilterType.Exclude
		created.RespectCanCollide = true
		castParams = created
		params = created
	end
	local query = params :: RaycastParams
	query.FilterDescendantsInstances = { exclude }
	query.CollisionGroup = group
	local result = workspace:Blockcast(start, size, vector, query)
	if result == nil then
		return nil, nil
	end
	return result.Distance, result.Normal
end

--- Whether a face the world cast met is ground a body climbs, not a wall (D-204): its normal is
--- within ai.luau collision.groundSlopeDegrees of straight up. Nil (a face named no way) is a wall.
--- The one rule both sides judge by (RushWorld.isGround, D-209).
function EnemyService.isGround(normal: Vector3?): boolean
	return RushWorld.isGround(normal)
end

--- How far ahead of a model's root centre along `direction` (flattened) the world stops the root,
--- within `distance` studs, or nil when nothing does (D-197). The root's own box is cast in the
--- root's own collision group (a rushing body's group collides with the world only), from where its
--- front face stands at the root's centre (moved by `offset` first, when given: a sidestep's look,
--- D-207): a root pressed against a wall overlaps it by a hair, and a cast never sees what its box
--- starts in. The second value is whether the face is ground the body runs over (RushWorld.runsOver,
--- D-209): a slope (D-204) or a step it climbs, whose riser the box, cast level, meets two or three
--- treads ahead. A rush's line still never resolves past it (whatever stands behind it is unseen),
--- but it stops no body. The third is the face's normal (nil: named no way). `cast` stands in for
--- workspace:Blockcast.
function EnemyService.worldAhead(
	model: Model,
	direction: Vector3,
	distance: number,
	cast: WorldCast?,
	offset: Vector3?,
	walk: boolean?
): (number?, boolean?, Vector3?)
	local root = model.PrimaryPart
	local flat = Brain.horizontal(direction)
	if root == nil or flat == nil or not (distance > 0) then
		return nil, nil, nil
	end
	local engineCast: WorldCast = cast or defaultWorldCast
	local group = if walk == true then AI.collision.rushing else root.CollisionGroup
	local bound: RushWorld.Cast = function(start: CFrame, size: Vector3, vector: Vector3): (number?, Vector3?)
		return engineCast(start, size, vector, group, model)
	end
	local frame = root.CFrame + (offset or Vector3.zero)
	local reach = EnemyService.rootReach(model, flat)
	if walk == true then
		frame = CFrame.lookAt(frame.Position, frame.Position + flat)
		reach = root.Size.Z / 2
	end
	local ok, travelled, normal = pcall(bound, frame - flat * reach, root.Size, flat * distance)
	if not ok or typeof(travelled) ~= "number" then
		return nil, nil, nil
	end
	local face: Vector3? = if typeof(normal) == "Vector3" then normal else nil
	local free = math.max(0, travelled) - reach
	return math.max(0, travelled), RushWorld.runsOver(bound, frame, root.Size, flat, free, face), face
end

--- How far a model's root box reaches from its centre along `direction` (flattened): half its extent
--- that way, 0 with no root or no direction. A root that worldAhead's face stops stands this far
--- short of the face (D-202).
function EnemyService.rootReach(model: Model, direction: Vector3): number
	local root = model.PrimaryPart
	local flat = Brain.horizontal(direction)
	if root == nil or flat == nil then
		return 0
	end
	local frame = root.CFrame
	local half = root.Size / 2
	return math.abs(frame.RightVector:Dot(flat)) * half.X
		+ math.abs(frame.UpVector:Dot(flat)) * half.Y
		+ math.abs(frame.LookVector:Dot(flat)) * half.Z
end

-- `groups` is world.CollisionGroups (nil while it has not landed: no groups, as before D-167).
local function defaultEngine(groups: any?): Engine
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
			EnemyService.addYawAlign(root, cframe.LookVector)
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
			EnemyService.applyFacing(model, facing)
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
		setCollisionGroup = if groups ~= nil
			then function(model: Model, group: string)
				groups.assign(model, group)
			end
			else nil,
		bodyClear = if groups ~= nil
			then function(model: Model): boolean
				return groups.clear(model)
			end
			else nil,
		worldAhead = function(model, direction, distance, offset, walk)
			return EnemyService.worldAhead(model, direction, distance, nil, offset, walk)
		end,
		halt = function(model, position)
			local humanoid = humanoidOf(model)
			local root = model.PrimaryPart
			if root == nil then
				return
			end
			if position ~= nil then
				-- On the goal it would have passed before the next frame (its yaw and height kept).
				local at = root.Position
				model:PivotTo(CFrame.new(position.X - at.X, 0, position.Z - at.Z) * model:GetPivot())
			end
			local velocity = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
			if humanoid ~= nil then
				humanoid:MoveTo(root.Position)
			end
		end,
		pivot = function(model, cframe)
			model:PivotTo(cframe)
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
	-- D-167: the fighter collision groups (Main registers them first; registering again is a no-op).
	local groups = if world ~= nil then sibling(world, "CollisionGroups") else nil
	if groups ~= nil then
		groups.register()
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
		engine = defaultEngine(groups),
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
	local combat = newDeps.combat
	if combat ~= nil and typeof(combat.setEnemyHitStop) == "function" then
		combat.setEnemyHitStop(EnemyService.pauseForHit)
	end
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
	local combat = if deps ~= nil then (deps :: Deps).combat else nil
	if combat ~= nil and typeof(combat.setEnemyHitStop) == "function" then
		combat.setEnemyHitStop(nil)
	end
	for id in table.clone(entries) do
		forget(id, "Despawned")
	end
	table.clear(entries)
	table.clear(corpses)
	currentPlayers = {}
	accumulator = 0
	lastSleepCheck = -math.huge
	started = false
	warnedNoCombat = false
	holdNew = false
end

return EnemyService
