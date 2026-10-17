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
	`attack.recovery`. The brain owns its yaw: every tick it turns toward what the archetype wants
	at the archetype's turn rate for the current phase and hands the result to `context.face`, so
	the Charger's slow turn and the Brute's slow tracking are real, testable numbers.

	An archetype module (Charger, Brute) supplies the hooks: how to chase, which attacks are
	usable, what the body does during the wind-up, the strike and the recovery.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local AI = require(Shared.data.ai)
local Enemies = require(Shared.data.enemies)
local Rng = require(Shared.util.Rng)

export type Phase = "Idle" | "Alert" | "Chase" | "WindUp" | "Strike" | "Recover" | "Return" | "Interrupted" | "Dead"

export type PlayerSnapshot = { id: number, position: Vector3 }

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
	moveTo: (position: Vector3, speed: number) -> (),
	stop: () -> (),
	face: (direction: Vector3) -> (),
	telegraph: (attack: Types.EnemyAttackDef, origin: Vector3, facing: Vector3, shape: Types.TelegraphShape?) -> (),
	strike: (attack: Types.EnemyAttackDef, origin: Vector3, facing: Vector3) -> (),
	setState: (state: Types.EntityState, duration: number?) -> (),
	actionStarted: (clipId: string, facing: Vector3) -> (),
	random: Random,
	clearThreat: (() -> ())?, -- when EntityService offers it, the leash forgets who hit it
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

--- Turns the facing toward `direction` by at most `rateDegreesPerSecond * dt` and publishes it.
--- Returns the unsigned angle still remaining.
function Brain.turnToward(self: Brain, direction: Vector3, rateDegreesPerSecond: number, dt: number): number
	local flat = Brain.horizontal(direction)
	if flat == nil then
		return 0
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

function Brain.enter(self: Brain, phase: Phase, now: number)
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

--- A stagger, break or guard break: the attack in progress is cancelled (no strike), the body
--- stops, and the brain waits `duration` (plus the resume delay) or, with no duration, until the
--- record leaves the interrupting state.
function Brain.interrupt(self: Brain, state: string, duration: number?)
	if self.phase == "Dead" then
		return
	end
	local now = self.context.now()
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
	self.attack = nil
	self.targetId = nil
	self.lastTarget = nil
	self.context.stop()
	self.phase = "Dead"
end

--- Puts the brain to sleep (no player within the sleep radius): it stops and forgets its target.
function Brain.sleep(self: Brain)
	if not self.awake or self.phase == "Dead" then
		return
	end
	self.awake = false
	self.targetId = nil
	self.lastTarget = nil
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
		self.archetype.onWindUp(self, dt, target)
		if now - self.phaseStart >= attack.windUp then
			self:enterStrike(now, target)
		end
	elseif phase == "Strike" then
		local attack = self.attack
		if attack == nil then
			self:enterIdle(now)
			return
		end
		local elapsed = now - self.phaseStart
		if not self.struck and elapsed >= attack.strike then
			self.struck = true
			local origin, facing = self.archetype.strikeFrame(self)
			context.strike(attack, origin, facing)
			-- The strike resolves synchronously: a parry staggers this enemy through EntityService and
			-- interrupt() has already run, so the strike hook must not move the body again.
			if self.phase ~= "Strike" then
				return
			end
		end
		local over = self.archetype.onStrike(self, dt, elapsed)
		if self.struck and over then
			self:enterRecover(now)
		end
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
