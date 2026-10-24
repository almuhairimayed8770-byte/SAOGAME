--!strict
--[[
	Brain: the archetype base for enemy AI (sections 6, 9 and 16; ARCHITECTURE "Combat flow" step 3).

	A brain is decision logic over an injected context: the clock, the entity record, the alive
	players, movement and facing requests, the telegraph / strike / state hooks and a Random.
	EnemyService builds the context from the engine; the Lune specs build it from tables, so the
	whole loop (perception, threat, leash, the attack timeline, interrupts) runs in tests.

	Phases: Idle -> Alert -> Chase -> WindUp -> Strike -> Recover -> (Chase | Idle), plus Return
	(the leash), Interrupted (stagger, break, guard break) and Dead. The attack timeline follows the
	attack def exactly: the telegraph and ActionStarted fire at WindUp start; the strike resolves
	`attack.strike` seconds after the wind-up ends (the clip's hit window); the recovery holds for
	`attack.recovery`. The brain owns its yaw: every tick it aims at what the archetype wants at the
	archetype's turn rate for the current phase, the frame pass turns it there (D-185) and hands the
	result to `context.face`, so the Charger's slow turn and the Brute's slow tracking are real,
	testable numbers.

	An archetype module (Charger, Brute) supplies the hooks: how to chase, which attacks are
	usable, what the body does during the wind-up, the strike and the recovery.

	A strike the archetype resolves by contact (contactStrike: the Charger's rush, D-166) skips the
	single resolve at `attack.strike`: the archetype resolves the line in stretches as its body
	sweeps it (strikeStretch), each target once, and finishes by `attack.strike`. An attack that is
	cancelled (interrupt, death, sleep) tells the archetype through onCancel.

	Hit-stop (D-168): a player's confirmed hit on this enemy while its attack is unresolved (the
	wind-up, or the strike before it resolves) pauses the attack's timeline for the hit-stop the
	clients freeze its clip for (pauseAttack), capped per attack by ai.hitStop.maxPausePerAttack.
	The wind-up, the strike beat, the cooldown and the entity's Art state all move by the same
	amount; a rush that has launched is never paused.

	Two clocks (D-184, D-185). Perception and decisions (targets, the chase, which attack, where to
	walk, which way to turn and how fast) run on the AI tick. The frame pass (frame, every server
	Heartbeat after the ticks) resolves what is timed: the wind-up's end, the strike's resolve, a
	contact strike's stretches and its run, each on the first server frame at or after its beat, and
	it turns the body. A tick's turnToward sets where the body turns and how fast for the phase; the
	frame pass, last thing each frame, turns the facing by that rate * the frame's seconds and
	publishes it. So the body turns smoothly at the phase's rate, and the facing never changes between
	two frame passes: every decision and every resolve in a frame (the telegraph's line, the strike's
	facing, the rush's direction) reads the facing the body already shows (the rigid align put the
	root on it in the physics step before). A brain that never gets a frame (the Lune specs that only
	tick) turns per tick as before.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local AI = require(Shared.data.ai)
local Enemies = require(Shared.data.enemies)
local Rng = require(Shared.util.Rng)

export type Phase = "Idle" | "Alert" | "Chase" | "WindUp" | "Strike" | "Recover" | "Return" | "Interrupted" | "Dead"

export type PlayerSnapshot = { id: number, position: Vector3 }

-- A Charger's rush as the server runs it (D-166, D-169): the line from the crouch point, the speed
-- and how long the run lasts. EnemyService turns it into the RushStarted remote.
export type Rush = {
	attackId: string,
	-- The launch beat: the wind-up's own end (the strike phase's start), which the clients predict
	-- and draw the rush from. The line resolves on this clock (RushStarted carries it).
	startedAt: number,
	bodyStartedAt: number, -- the server frame the body started running (up to a frame after startedAt)
	origin: Vector3, -- the crouch point (where the root stood)
	direction: Vector3, -- horizontal unit vector along the line
	speed: number, -- studs per second
	length: number, -- reach + overshoot
	duration: number, -- length / speed
}

-- Why a rush stopped: "Done" when it ran its time, else one of the early reasons the clients hear.
export type RushEnd = "Done" | Types.RushEndReason

export type Target = {
	id: number,
	position: Vector3,
	distance: number, -- horizontal studs
	direction: Vector3, -- horizontal unit vector from the brain to the target
}

export type Context = {
	entityId: number,
	def: Enemies.Enemy,
	home: Vector3, -- the spawn point the leash pulls back to
	now: () -> number,
	getRecord: () -> any, -- the EntityService record (state, threat) or nil once removed
	players: () -> { PlayerSnapshot }, -- alive player fighters
	position: () -> Vector3,
	facing: () -> Vector3, -- the body's facing when the brain is created
	-- `direct`: a strike's own movement (the rush, any lunge) goes straight at the point, never along
	-- a path (D-183). Nil or false: the mover may pathfind past a wall or a long way.
	moveTo: (position: Vector3, speed: number, direct: boolean?) -> (),
	stop: () -> (),
	face: (direction: Vector3) -> (),
	telegraph: (attack: Types.EnemyAttackDef, origin: Vector3, facing: Vector3, shape: Types.TelegraphShape?) -> (),
	strike: (
		attack: Types.EnemyAttackDef,
		origin: Vector3,
		facing: Vector3,
		options: Types.EnemyStrikeOptions?
	) -> (),
	setState: (state: Types.EntityState, duration: number?) -> (),
	actionStarted: (clipId: string, facing: Vector3) -> (),
	random: Random,
	clearThreat: (() -> ())?, -- when EntityService offers it, the leash forgets who hit it
	-- Studs the body reaches ahead of and behind its root along the facing (a rush sweeps it, D-166).
	-- Nil: the root alone (0, 0).
	bodyExtents: (() -> (number, number))?,
	-- How far ahead of the root's centre along `direction` the world meets the root, within
	-- `distance` studs, and whether that face is ground the root climbs (D-204); nil when nothing does
	-- (D-197: a rush's line ends at the face). Nil: no world.
	worldAhead: ((direction: Vector3, distance: number) -> (number?, boolean?))?,
	-- How far the root's own box reaches ahead of its centre along `direction`: a root stopped by a
	-- face that worldAhead found stands this far short of it (D-202). Nil: 0.
	rootReach: ((direction: Vector3) -> number)?,
	-- A rush launched / stopped (D-169): EnemyService switches collision groups and tells the clients.
	rushStarted: ((rush: Rush) -> ())?,
	rushEnded: ((rush: Rush, reason: RushEnd, distance: number) -> ())?,
	-- Pushes the entity's timed state (the attack's Art) later by `seconds` (a hit-stop pause, D-168).
	extendState: ((seconds: number) -> ())?,
}

local Brain = {}
Brain.__index = Brain

type Fields = {
	context: Context,
	archetype: Archetype,
	tuning: AI.ArchetypeTuning,
	def: Enemies.Enemy,
	phase: Phase,
	phaseStart: number,
	awake: boolean,
	facingDir: Vector3,
	targetId: number?,
	targetLastInRange: number,
	lastRetarget: number,
	lastTarget: Target?,
	attack: Types.EnemyAttackDef?,
	struck: boolean,
	cooldowns: { [string]: number },
	heldUntil: number?,
	interruptState: string?,
	memory: { [string]: any },
	attackPaused: number, -- seconds this attack's timeline has been paused by hit-stop (D-168)
	pauseEndsAt: number, -- when the latest hit-stop freeze on this attack ends
	-- The frame-rate turn (D-185): where the facing turns, how fast (degrees per second, the phase's
	-- rate) and up to when it has turned. Nil goal: it holds.
	turnGoal: Vector3?,
	turnRate: number,
	turnedAt: number,
	framed: boolean, -- the frame pass runs this brain: turns spread over frames
}

export type Brain = typeof(setmetatable({} :: Fields, Brain))

export type Archetype = {
	name: string,
	-- Chase: steer and move toward a line or a range; returns the attack to begin, or nil.
	chase: (brain: Brain, dt: number, target: Target) -> Types.EnemyAttackDef?,
	-- Whether an attack may start against this target right now (range and angle).
	canUse: (brain: Brain, attack: Types.EnemyAttackDef, target: Target) -> boolean,
	onChaseStart: ((brain: Brain) -> ())?,
	onWindUp: (brain: Brain, dt: number, target: Target?) -> (),
	onStrikeStart: (brain: Brain, target: Target?) -> (),
	strikeFrame: (brain: Brain) -> (Vector3, Vector3), -- the origin and facing the strike resolves from
	onStrike: (brain: Brain, dt: number, elapsed: number) -> boolean, -- true once the strike phase is over
	onRecover: (brain: Brain, dt: number, target: Target?) -> (),
	-- True while the strike in progress resolves by contact (the archetype sweeps it in stretches
	-- through strikeStretch); the brain then skips its single resolve at attack.strike (D-166).
	contactStrike: ((brain: Brain) -> boolean)?,
	-- The attack in progress was cancelled: "Interrupted", "Died" or "Stopped" (sleep or hold).
	onCancel: ((brain: Brain, reason: Types.RushEndReason) -> ())?,
}

local FORWARD = -Vector3.zAxis -- Roblox forward (parts face -Z)

local INTERRUPTING: { [string]: boolean } = { Stagger = true, Break = true, GuardBroken = true }

-- ---------------------------------------------------------------------------------------------
-- Vector helpers (horizontal plane)
-- ---------------------------------------------------------------------------------------------

--- The ground-plane part of a vector as a unit vector, or nil when it has no horizontal direction.
function Brain.horizontal(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < AI.flatEpsilon then
		return nil
	end
	return flat.Unit
end

--- Rotates a vector about the vertical axis by `degrees` (positive turns left, toward -X from -Z).
function Brain.rotateY(vector: Vector3, degrees: number): Vector3
	local radians = math.rad(degrees)
	local cos, sin = math.cos(radians), math.sin(radians)
	return Vector3.new(vector.X * cos + vector.Z * sin, vector.Y, -vector.X * sin + vector.Z * cos)
end

--- Signed horizontal angle in degrees from `from` to `to`; rotateY(from, angle) points along `to`.
function Brain.signedAngle(from: Vector3, to: Vector3): number
	local cross = from:Cross(to)
	return math.deg(math.atan2(cross.Y, from:Dot(to)))
end

--- Horizontal distance between two points.
function Brain.horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

--- The ground shape a telegraph draws for an attack (nil when the attack has none).
function Brain.shapeFor(attack: Types.EnemyAttackDef): Types.TelegraphShape?
	local kind = attack.groundShape
	if kind == nil then
		return nil
	end
	local width = attack.reach
	if kind == "Line" then
		width = AI.telegraph.lineWidth
	elseif kind == "Cone" then
		width = attack.arc
	end
	return { kind = kind, length = attack.reach, width = width }
end

--- The clip id an enemy attack plays: enemy/<Rig>/<attack.clip> (ARCHITECTURE "Clips").
function Brain.clipIdFor(def: Enemies.Enemy, attack: Types.EnemyAttackDef): string
	return ("enemy/%s/%s"):format(def.skin, attack.clip)
end

-- ---------------------------------------------------------------------------------------------
-- Construction and accessors
-- ---------------------------------------------------------------------------------------------

--- Creates a brain for an entity with the given archetype hooks; it starts Idle, awake and facing
--- the way the body faces.
function Brain.new(context: Context, archetype: Archetype): Brain
	local now = context.now()
	local facing = Brain.horizontal(context.facing()) or FORWARD
	local self: Fields = {
		context = context,
		archetype = archetype,
		tuning = AI.tuningFor(context.def.archetype),
		def = context.def,
		phase = "Idle",
		phaseStart = now,
		awake = true,
		facingDir = facing,
		targetId = nil,
		targetLastInRange = now,
		lastRetarget = -math.huge,
		lastTarget = nil,
		attack = nil,
		struck = false,
		cooldowns = {},
		heldUntil = nil,
		interruptState = nil,
		memory = {},
		attackPaused = 0,
		pauseEndsAt = -math.huge,
		turnGoal = nil,
		turnRate = 0,
		turnedAt = now,
		framed = false,
	}
	return setmetatable(self, Brain)
end

--- The current phase.
function Brain.getPhase(self: Brain): Phase
	return self.phase
end

--- Seconds spent in the current phase.
function Brain.phaseElapsed(self: Brain): number
	return self.context.now() - self.phaseStart
end

--- The target the last tick saw, or nil.
function Brain.getTarget(self: Brain): Target?
	return self.lastTarget
end

--- The brain's own facing (the body follows it through context.face).
function Brain.getFacing(self: Brain): Vector3
	return self.facingDir
end

--- The attack in progress (WindUp, Strike or Recover), or nil.
function Brain.currentAttack(self: Brain): Types.EnemyAttackDef?
	return self.attack
end

--- The clock.
function Brain.now(self: Brain): number
	return self.context.now()
end

--- The body's position.
function Brain.position(self: Brain): Vector3
	return self.context.position()
end

--- Chase speed: the def's moveSpeed scaled by the archetype.
function Brain.speed(self: Brain): number
	return self.def.moveSpeed * self.tuning.chaseSpeedMultiplier
end

--- Whether the brain is awake (ticked) or asleep (beyond the sleep radius).
function Brain.isAwake(self: Brain): boolean
	return self.awake
end

-- ---------------------------------------------------------------------------------------------
-- Steering helpers for archetypes
-- ---------------------------------------------------------------------------------------------

--- Unsigned horizontal angle in degrees between the facing and a direction.
function Brain.angleTo(self: Brain, direction: Vector3): number
	local flat = Brain.horizontal(direction)
	if flat == nil then
		return 0
	end
	return math.abs(Brain.signedAngle(self.facingDir, flat))
end

-- Turns the facing toward `goal` by at most `maxStep` degrees and publishes it when it moved.
-- Returns the unsigned angle still remaining.
local function stepFacing(self: Brain, goal: Vector3, maxStep: number): number
	local angle = Brain.signedAngle(self.facingDir, goal)
	local step = math.clamp(angle, -maxStep, maxStep)
	if step ~= 0 then
		local turned = Brain.horizontal(Brain.rotateY(self.facingDir, step))
		if turned ~= nil then
			self.facingDir = turned
			self.context.face(self.facingDir)
		end
	end
	return math.abs(angle - step)
end

--- The frame-rate turn (D-185): turns the facing toward the tick's turn goal at its rate for the
--- time since the last frame pass, up to `at`, and publishes it. Only the frame pass calls it, after
--- the frame's ticks and edges. A hit-stop freeze on the attack holds the wind-up's turn until the
--- freeze ends (the clip is frozen), and a hitch turns at most as far as the ticks it would have run
--- (ai.maxTicksPerFrame).
function Brain.advanceTurn(self: Brain, at: number)
	local from = self.turnedAt
	if at <= from then
		return
	end
	self.turnedAt = at
	local goal = self.turnGoal
	if goal == nil or self.turnRate <= 0 then
		return
	end
	if self.phase == "WindUp" or self.phase == "Strike" then
		from = math.max(from, math.min(self.pauseEndsAt, at))
	end
	local seconds = math.min(at - from, AI.maxTicksPerFrame * AI.tickSeconds())
	if seconds > 0 then
		stepFacing(self, goal, self.turnRate * seconds)
	end
end

--- Turns the facing toward `direction` at `rateDegreesPerSecond`. Ticked alone (no frame pass) it
--- turns by at most rate * dt at once and publishes it. Under the frame pass (D-185) it sets the turn
--- the frame pass carries out, at this rate, from the last frame pass on; the facing itself holds
--- until then. Returns the unsigned angle still remaining.
function Brain.turnToward(self: Brain, direction: Vector3, rateDegreesPerSecond: number, dt: number): number
	local flat = Brain.horizontal(direction)
	if flat == nil then
		return 0
	end
	if self.framed then
		self.turnGoal = flat
		self.turnRate = rateDegreesPerSecond
		return math.abs(Brain.signedAngle(self.facingDir, flat))
	end
	local angle = Brain.signedAngle(self.facingDir, flat)
	local maxStep = rateDegreesPerSecond * dt
	local step = math.clamp(angle, -maxStep, maxStep)
	if step ~= 0 then
		local turned = Brain.horizontal(Brain.rotateY(self.facingDir, step))
		if turned ~= nil then
			self.facingDir = turned
		end
	end
	self.context.face(self.facingDir)
	return math.abs(angle - step)
end

--- Walks along the facing: the goal sits moveAheadStuds ahead of the body.
function Brain.moveForward(self: Brain, speed: number)
	self.context.moveTo(self.context.position() + self.facingDir * AI.movement.moveAheadStuds, speed)
end

--- Walks toward a point.
function Brain.moveToward(self: Brain, position: Vector3, speed: number)
	self.context.moveTo(position, speed)
end

--- A strike's own movement (the rush, any lunge): straight at the point, never along a path or a
--- waypoint behind the body (D-183).
function Brain.moveDirect(self: Brain, position: Vector3, speed: number)
	self.context.moveTo(position, speed, true)
end

--- Studs the body reaches ahead of and behind its root along its facing (0, 0 when unknown).
function Brain.bodyExtents(self: Brain): (number, number)
	local extents = self.context.bodyExtents
	if extents == nil then
		return 0, 0
	end
	return extents()
end

--- How far ahead of the root's centre along `direction` the world meets the body, within
--- `distance` studs, and whether that face is ground the root climbs (true) or a wall that stops it
--- (D-204); nil when nothing does or the context knows no world (D-197).
function Brain.worldAhead(self: Brain, direction: Vector3, distance: number): (number?, boolean)
	local cast = self.context.worldAhead
	if cast == nil or not (distance > 0) then
		return nil, false
	end
	local face, ground = cast(direction, distance)
	return face, ground == true
end

--- How far the root's own box reaches ahead of its centre along `direction` (0 when the context
--- knows no root): where a face found by worldAhead stops the root's centre (D-202).
function Brain.rootReach(self: Brain, direction: Vector3): number
	local reach = self.context.rootReach
	if reach == nil then
		return 0
	end
	return math.max(0, reach(direction))
end

--- Resolves one stretch of the attack's line, `from` to `to` studs along it from `origin` (the
--- stretch a rushing body swept, D-166); `resolved` carries the targets this attack already reached.
function Brain.strikeStretch(
	self: Brain,
	origin: Vector3,
	facing: Vector3,
	from: number,
	to: number,
	resolved: { [number]: boolean }
)
	local attack = self.attack
	if attack == nil then
		return
	end
	self.context.strike(attack, origin, facing, { span = { from = from, to = to }, resolved = resolved })
end

--- Tells EnemyService a rush launched (collision group, RushStarted).
function Brain.rushStarted(self: Brain, rush: Rush)
	local hook = self.context.rushStarted
	if hook ~= nil then
		hook(rush)
	end
end

--- Tells EnemyService a rush stopped (`distance` studs down the line, as the body stands).
function Brain.rushEnded(self: Brain, rush: Rush, reason: RushEnd, distance: number)
	local hook = self.context.rushEnded
	if hook ~= nil then
		hook(rush, reason, distance)
	end
end

--- The attacks that are off cooldown and usable against the target right now.
function Brain.readyAttacks(self: Brain, target: Target): { Types.EnemyAttackDef }
	local now = self.context.now()
	local ready = {}
	for _, attack in self.def.attacks do
		local readyAt = self.cooldowns[attack.id]
		if (readyAt == nil or now >= readyAt) and self.archetype.canUse(self, attack, target) then
			table.insert(ready, attack)
		end
	end
	return ready
end

--- A weighted choice among the ready attacks (ai.luau weights), or nil when none is usable.
function Brain.pickAttack(self: Brain, target: Target): Types.EnemyAttackDef?
	local ready = self:readyAttacks(target)
	if #ready == 0 then
		return nil
	end
	if #ready == 1 then
		return ready[1]
	end
	local entries = {}
	for _, attack in ready do
		table.insert(entries, { value = attack, weight = AI.attackWeight(attack.id) })
	end
	return Rng.weighted(self.context.random, entries)
end

-- ---------------------------------------------------------------------------------------------
-- Perception and threat
-- ---------------------------------------------------------------------------------------------

local function threatTable(record: any): { [number]: number }
	if typeof(record) == "table" and typeof(record.threat) == "table" then
		return record.threat
	end
	return {}
end

-- Picks or keeps the target: the highest threat holder in threat range (switching only past the
-- margin), else the nearest player inside aggroRange; drops a target that stays out of range.
function Brain.perceive(self: Brain, now: number, record: any): Target?
	local players = self.context.players()
	local byId: { [number]: PlayerSnapshot } = {}
	for _, snapshot in players do
		byId[snapshot.id] = snapshot
	end
	local position = self.context.position()
	local aggro = self.def.aggroRange
	local perception = AI.perception

	local current = if self.targetId ~= nil then byId[self.targetId] else nil
	if current == nil or now - self.lastRetarget >= perception.retargetInterval then
		self.lastRetarget = now
		local threat = threatTable(record)
		local bestId: number? = nil
		local bestThreat = 0
		for id, value in threat do
			local snapshot = byId[id]
			if
				snapshot ~= nil
				and value > bestThreat
				and Brain.horizontalDistance(position, snapshot.position)
					<= aggro * perception.threatRangeMultiplier
			then
				bestId, bestThreat = id, value
			end
		end
		if bestId ~= nil then
			local currentThreat = if current ~= nil then (threat[current.id] or 0) else 0
			if
				current == nil
				or bestId == current.id
				or bestThreat >= currentThreat * perception.threatSwitchMargin
			then
				self.targetId = bestId
			end
		elseif current == nil then
			local nearestId: number? = nil
			local nearest = aggro
			for _, snapshot in players do
				local distance = Brain.horizontalDistance(position, snapshot.position)
				if distance <= nearest then
					nearestId, nearest = snapshot.id, distance
				end
			end
			self.targetId = nearestId
		end
		if self.targetId ~= nil and (current == nil or current.id ~= self.targetId) then
			self.targetLastInRange = now
		end
		current = if self.targetId ~= nil then byId[self.targetId] else nil
	end

	if current == nil then
		self.targetId = nil
		return nil
	end
	local distance = Brain.horizontalDistance(position, current.position)
	if distance <= aggro * perception.loseRangeMultiplier then
		self.targetLastInRange = now
	elseif now - self.targetLastInRange > perception.loseTargetGrace then
		self.targetId = nil
		return nil
	end
	local direction = Brain.horizontal(current.position - position) or self.facingDir
	return { id = current.id, position = current.position, distance = distance, direction = direction }
end

-- ---------------------------------------------------------------------------------------------
-- Phase transitions
-- ---------------------------------------------------------------------------------------------

-- A new phase turns at its own rate: the old turn goal ends with the old phase (the chase keeps the
-- alert's or the recovery's goal until its own first tick sets one). Under the frame pass the facing
-- stays where the body shows it, so a wind-up starts on the line the body already points along.
function Brain.enter(self: Brain, phase: Phase, now: number)
	if phase ~= "Chase" then
		self.turnGoal = nil
	end
	self.phase = phase
	self.phaseStart = now
end

function Brain.enterIdle(self: Brain, now: number)
	self.context.stop()
	self.attack = nil
	self:enter("Idle", now)
end

function Brain.enterChase(self: Brain, now: number)
	self:enter("Chase", now)
	self.memory.chaseSince = now
	local hook = self.archetype.onChaseStart
	if hook ~= nil then
		hook(self)
	end
end

function Brain.enterReturn(self: Brain, now: number)
	self.targetId = nil
	self.lastTarget = nil
	self.attack = nil
	local clear = self.context.clearThreat
	if clear ~= nil then
		clear()
	end
	self:enter("Return", now)
end

--- Seconds of chasing since the chase began (for line-up timeouts).
function Brain.chaseElapsed(self: Brain): number
	local since = self.memory.chaseSince
	if typeof(since) ~= "number" then
		return 0
	end
	return self.context.now() - since
end

--- True when the body has wandered past the def's leash range from home.
function Brain.beyondLeash(self: Brain): boolean
	return Brain.horizontalDistance(self.context.position(), self.context.home) > self.def.leashRange
end

-- Starts an attack: the telegraph and clip go out now, the body holds the wind-up pose.
function Brain.beginAttack(self: Brain, attack: Types.EnemyAttackDef, now: number)
	local context = self.context
	self.attack = attack
	self.struck = false
	self.attackPaused = 0
	self.pauseEndsAt = -math.huge
	self:enter("WindUp", now)
	context.stop()
	local origin = context.position()
	local facing = self.facingDir
	context.telegraph(attack, origin, facing, Brain.shapeFor(attack))
	context.actionStarted(Brain.clipIdFor(self.def, attack), facing)
	context.setState("Art", attack.windUp + attack.strike)
	self.cooldowns[attack.id] = now + attack.windUp + attack.strike + attack.recovery + self.tuning.attackCooldown
end

function Brain.enterStrike(self: Brain, now: number, target: Target?)
	self:enter("Strike", now)
	self.archetype.onStrikeStart(self, target)
end

function Brain.enterRecover(self: Brain, now: number)
	local attack = self.attack
	self:enter("Recover", now)
	self.context.stop()
	if attack ~= nil then
		self.context.setState("PostMotion", attack.recovery)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Interrupts, death, sleep
-- ---------------------------------------------------------------------------------------------

-- Tells the archetype the attack in progress is being dropped (a rush stops early, D-169).
function Brain.cancelAttack(self: Brain, reason: Types.RushEndReason)
	local hook = self.archetype.onCancel
	if hook ~= nil and self.attack ~= nil then
		hook(self, reason)
	end
end

--- Hit-stop on this enemy (D-168): a player's confirmed hit pauses its unresolved attack for
--- `seconds`, the way every client freezes its clip. Freezes overlap the way the clients' do (the
--- pause runs to the later of the running freeze's end and now + seconds), and one attack pauses
--- at most ai.hitStop.maxPausePerAttack in all. The wind-up end, the strike beat, the cooldown and
--- the entity's timed state move by what was added. Returns the seconds added (0 when capped, or
--- during a rush that has launched), or nil when there is no unresolved attack to pause.
function Brain.pauseAttack(self: Brain, seconds: number): number?
	local attack = self.attack
	local phase = self.phase
	if attack == nil or not (phase == "WindUp" or (phase == "Strike" and not self.struck)) then
		return nil
	end
	local contact = self.archetype.contactStrike
	if phase == "Strike" and contact ~= nil and contact(self) then
		return 0 -- the rush runs on its own clock (the clients draw it on the server's)
	end
	local now = self.context.now()
	local freezeEnd = math.max(self.pauseEndsAt, now)
	local wanted = math.max(0, now + math.max(0, seconds) - freezeEnd)
	local added = math.min(wanted, math.max(0, AI.hitStop.maxPausePerAttack - self.attackPaused))
	if added <= 0 then
		return 0
	end
	self.attackPaused += added
	self.pauseEndsAt = freezeEnd + added
	self.phaseStart += added
	local readyAt = self.cooldowns[attack.id]
	if readyAt ~= nil then
		self.cooldowns[attack.id] = readyAt + added
	end
	local extend = self.context.extendState
	if extend ~= nil then
		extend(added)
	end
	return added
end

--- Whether a hit-stop freeze holds the attack right now (the wind-up pose does not turn).
function Brain.frozen(self: Brain): boolean
	return self.context.now() < self.pauseEndsAt
end

--- A stagger, break or guard break: the attack in progress is cancelled (no strike), the body
--- stops, and the brain waits `duration` (plus the resume delay) or, with no duration, until the
--- record leaves the interrupting state.
function Brain.interrupt(self: Brain, state: string, duration: number?)
	if self.phase == "Dead" then
		return
	end
	local now = self.context.now()
	self:cancelAttack("Interrupted")
	self.attack = nil
	self.struck = false
	self.context.stop()
	self.interruptState = state
	self.heldUntil = if duration ~= nil then now + duration + AI.interrupt.resumeDelay else nil
	self:enter("Interrupted", now)
end

--- Stops everything for good; the entity is dead.
function Brain.die(self: Brain)
	if self.phase == "Dead" then
		return
	end
	self:cancelAttack("Died")
	self.attack = nil
	self.targetId = nil
	self.lastTarget = nil
	self.turnGoal = nil
	self.context.stop()
	self.phase = "Dead"
end

--- Puts the brain to sleep (no player within the sleep radius): it stops and forgets its target.
function Brain.sleep(self: Brain)
	if not self.awake or self.phase == "Dead" then
		return
	end
	self.awake = false
	self:cancelAttack("Stopped")
	self.targetId = nil
	self.lastTarget = nil
	self.turnGoal = nil
	if self.phase ~= "Interrupted" then
		self:enterIdle(self.context.now())
	else
		self.context.stop()
	end
end

--- Wakes the brain; perception resumes on the next tick.
function Brain.wake(self: Brain)
	if self.awake or self.phase == "Dead" then
		return
	end
	self.awake = true
	self.phaseStart = self.context.now()
	self.turnedAt = self.phaseStart
end

function Brain.tickInterrupted(self: Brain, now: number, record: any)
	local over: boolean
	if self.heldUntil ~= nil then
		over = now >= self.heldUntil
	else
		over = not INTERRUPTING[record.state]
	end
	if not over then
		return
	end
	if INTERRUPTING[record.state] then
		-- The duration passed but the record still holds (a Break chained onto a stagger): follow it.
		local until_ = record.stateUntil
		if typeof(until_) == "number" and until_ > now then
			self.heldUntil = until_ + AI.interrupt.resumeDelay
		else
			self.heldUntil = nil
		end
		self.interruptState = record.state
		return
	end
	self.heldUntil = nil
	self.interruptState = nil
	if self.targetId ~= nil then
		self:enterChase(now)
	else
		self:enterIdle(now)
	end
end

function Brain.tickReturn(self: Brain, now: number, dt: number)
	local context = self.context
	local home = context.home
	local position = context.position()
	if Brain.horizontalDistance(position, home) <= AI.leash.homeRadius then
		self:enterIdle(now)
		return
	end
	local direction = Brain.horizontal(home - position)
	if direction ~= nil then
		self:turnToward(direction, self.tuning.turnRate, dt)
	end
	context.moveTo(home, self.def.moveSpeed * AI.leash.returnSpeedMultiplier)
end

-- ---------------------------------------------------------------------------------------------
-- Timed edges: the wind-up's end and the strike (D-182, D-184)
-- ---------------------------------------------------------------------------------------------

-- The strike phase up to `now`: the single resolve at attack.strike (a contact strike resolves in
-- stretches inside onStrike instead), then the archetype's strike hook, then the recovery once both
-- say it is over. `dt` is the tick's seconds, or 0 from a frame.
function Brain.advanceStrike(self: Brain, now: number, dt: number)
	local attack = self.attack
	if attack == nil then
		return
	end
	local elapsed = now - self.phaseStart
	if not self.struck and elapsed >= attack.strike then
		self.struck = true
		local contact = self.archetype.contactStrike
		if contact == nil or not contact(self) then
			local origin, facing = self.archetype.strikeFrame(self)
			self.context.strike(attack, origin, facing)
			-- The strike resolves synchronously: a parry staggers this enemy through EntityService and
			-- interrupt() has already run, so the strike hook must not move the body again.
			if self.phase ~= "Strike" then
				return
			end
		end
	end
	local over = self.archetype.onStrike(self, dt, elapsed)
	-- A contact strike resolves inside onStrike, and a parry there interrupts this brain the same way.
	if self.phase ~= "Strike" then
		return
	end
	if self.struck and over then
		self:enterRecover(now)
	end
end

--- Resolves the attack's timed edges due by `now`: the wind-up's end (the strike phase starts on the
--- wind-up's own beat, never on the pass that noticed it, D-182) and then the strike phase (its
--- resolve, a contact strike's stretches and run). Never early: each edge waits for its beat, and
--- the hit-stop pauses (pauseAttack) move every beat. The tick and the frame pass both call it; an
--- edge already passed is not resolved twice.
function Brain.beat(self: Brain, now: number, dt: number)
	if self.phase == "WindUp" then
		local attack = self.attack
		if attack == nil or now - self.phaseStart < attack.windUp then
			return
		end
		self:enterStrike(self.phaseStart + attack.windUp, self.lastTarget)
	end
	if self.phase == "Strike" then
		-- A strike phase that began inside this pass has run only since its beat.
		self:advanceStrike(now, math.clamp(now - self.phaseStart, 0, dt))
	end
end

--- The frame pass (D-184, D-185): EnemyService calls it on every server frame (Heartbeat) after the
--- frame's AI ticks, while the brain is awake. It resolves the attack edges on the first frame at or
--- after their beats and turns the body at the phase's rate for the frame's time. A brain asleep,
--- held (asleep) or dead does nothing; an interrupting state on the record stops the attack here
--- just as the tick does, and a parry during a strike resolved here interrupts it the same way.
function Brain.frame(self: Brain)
	if not self.awake or self.phase == "Dead" then
		return
	end
	self.framed = true
	local now = self.context.now()
	local record = self.context.getRecord()
	if record == nil or record.state == "Dead" then
		return -- the tick takes it from here (die)
	end
	if self.phase ~= "Interrupted" and INTERRUPTING[record.state] then
		self:interrupt(record.state, nil)
	end
	if self.phase == "WindUp" or self.phase == "Strike" then
		self:beat(now, 0)
	end
	self:advanceTurn(now)
end

-- ---------------------------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------------------------

--- One AI tick of `dt` seconds (EnemyService calls it at ai.tickHz while the brain is awake).
function Brain.tick(self: Brain, dt: number)
	if not self.awake or self.phase == "Dead" then
		return
	end
	local context = self.context
	local now = context.now()
	local record = context.getRecord()
	if record == nil or record.state == "Dead" then
		self:die()
		return
	end
	if self.phase ~= "Interrupted" and INTERRUPTING[record.state] then
		self:interrupt(record.state, nil)
	end

	local phase = self.phase
	if phase == "Interrupted" then
		self:tickInterrupted(now, record)
		return
	end
	if phase == "Return" then
		self:tickReturn(now, dt)
		return
	end

	local target = self:perceive(now, record)
	self.lastTarget = target
	local tuning = self.tuning

	if phase == "Idle" then
		if self:beyondLeash() then
			-- Woken far from home, or interrupted on the way back: walk home before anything else.
			self:enterReturn(now)
		elseif target ~= nil then
			self:enter("Alert", now)
		end
	elseif phase == "Alert" then
		if target == nil then
			self:enterIdle(now)
			return
		end
		self:turnToward(target.direction, tuning.turnRate, dt)
		if now - self.phaseStart >= AI.perception.alertDelay then
			self:enterChase(now)
		end
	elseif phase == "Chase" then
		if target == nil then
			self:enterIdle(now)
			return
		end
		if self:beyondLeash() then
			self:enterReturn(now)
			return
		end
		local attack = self.archetype.chase(self, dt, target)
		if attack ~= nil then
			self:beginAttack(attack, now)
		end
	elseif phase == "WindUp" then
		local attack = self.attack
		if attack == nil then
			self:enterIdle(now)
			return
		end
		if not self:frozen() then
			self.archetype.onWindUp(self, dt, target)
		end
		-- The wind-up's end and the strike are timed edges: the same pass the frames run (D-184).
		self:beat(now, dt)
	elseif phase == "Strike" then
		if self.attack == nil then
			self:enterIdle(now)
			return
		end
		self:beat(now, dt)
	elseif phase == "Recover" then
		local attack = self.attack
		if attack == nil then
			self:enterIdle(now)
			return
		end
		self.archetype.onRecover(self, dt, target)
		if now - self.phaseStart >= attack.recovery then
			context.setState("Idle")
			self.attack = nil
			if target ~= nil then
				self:enterChase(now)
			else
				self:enterIdle(now)
			end
		end
	end
end

return Brain
