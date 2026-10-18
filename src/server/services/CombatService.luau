--!strict
--[[
	CombatService: the authority for player actions and enemy strikes (ARCHITECTURE "Combat flow",
	sections 6, 10, 17).

	Players send requests (ArtRequest, BasicAttackRequest, GuardRequest, DodgeRequest,
	TargetRequest); this service validates each one against the entity record and the data tables,
	answers a bad one with ActionRejected, and on a good one changes the entity's state through
	EntityService, tells every client with ActionStarted, and runs the authoritative timeline:
	for each hit window of the clip it samples the blade through ClipSampler + Pose, tests the whole
	blade for overlap at every sample and spherecasts its midpoint between samples (HitSweep); every
	touch becomes damage through DamageMath and EntityService.applyHit and a HitConfirmed to all
	clients. The sweep follows the blade's arc, not the frame chords: where the blade moves more
	than combat.sweepMaxTipStep between two samples it solves sub-samples in between, at most
	combat.sweepMaxSubdivisions per fighter per frame (HitSweep.followArc). After the last window
	the body is held in PostMotion (zero when the target was in Break), then freed. A requested Art
	or basic swing runs that timeline from its clientTime clamped into combat.lagAllowance and
	floored at the moment the body was last free (runStartOf), so a lagged swing's damage windows
	line up with what its client already showed without ever overlapping the lock before it.

	Enemy strikes come from EnemyService (enemyStrike): each player in the attack's cone or line
	is checked for dodge frames, a parry (guard raised inside parryWindow), a guard (cone and
	reduction, GuardBreak telegraphs smash through), then damage.

	Timelines are stepped from one Heartbeat (`tick`), never from task.wait, so they are
	deterministic and run under Lune with a fake clock, a fake spherecast and a fake overlap
	query. `bind(deps)` swaps the engine; `start()` binds the real one and registers the Net
	handlers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local Combat = require(Shared.data.combat)
local Arts = require(Shared.data.arts)
local Weapons = require(Shared.data.weapons)
local Net = require(Shared.net.Net)
local Signal = require(Shared.util.Signal)
local ClipSampler = require(Shared.choreo.ClipSampler)
local DamageMath = require(script.Parent.Parent.combat.DamageMath)
local HitSweep = require(script.Parent.Parent.combat.HitSweep)
local EntityService = require(script.Parent.EntityService)

export type Record = Types.EntityRecord

export type Connection = { Disconnect: (self: any) -> () }

-- The slice of Net.ServerNet this service uses (a test fake provides the same three).
export type NetLike = {
	on: (name: string, handler: (player: Player, payload: any) -> ()) -> (),
	fire: (name: string, player: Player, payload: any) -> (),
	fireAll: (name: string, payload: any) -> (),
}

export type Deps = {
	now: () -> number, -- server time (workspace:GetServerTimeNow)
	net: NetLike?,
	heartbeat: ((handler: (dt: number) -> ()) -> Connection?)?,
	cast: HitSweep.Caster?, -- nil: workspace:Spherecast
	overlap: HitSweep.Overlapper?, -- nil: workspace:GetPartBoundsInRadius
	random: Random,
}

export type ValidationContext = {
	lookVector: Vector3?, -- the server's view of the root's look vector (default: from the model)
	stances: { Types.Precondition }?, -- default: computed from the Humanoid and the parry timer
	lastParryAt: number?,
}

export type ArtPayload = { artId: string, facing: { number }, clientTime: number }
export type BasicPayload = { facing: { number }, clientTime: number }
export type DodgePayload = { direction: { number }, clientTime: number }

type Session = {
	generation: number,
	basicChain: number,
	basicLastAt: number,
	dodgeReadyAt: number,
	lastParryAt: number?,
	run: ArtRun?,
	ready: boolean,
	warnedNoTrail: boolean,
	warnedNoBlade: boolean,
}

type ArtRun = {
	entityId: number,
	generation: number,
	art: Arts.Art?, -- nil for a basic swing
	isBasic: boolean,
	clipId: string,
	clip: Types.ClipDef,
	windows: { HitSweep.Window },
	startedAt: number,
	postMotionAt: number, -- clip time the body freezes in its end pose
	multiplier: number,
	gaugePerHit: number,
	finalHit: boolean, -- the last window is the move's final hit (every Art; only the chain's last basic)
	windowIndex: number,
	sampledTo: number?, -- clip time the current window has been swept up to
	lastSample: HitSweep.BladeSample?,
	windowHits: { [number]: boolean },
	hitAny: boolean,
	hitBreak: boolean, -- a target was in Break: zero post-motion
	switchShown: boolean,
}

local STAGE_PLAYER = "player"
local CLIP_SEPARATOR = "/"

local CombatService = {}

--- Fires (record, art) when an Art's timeline starts.
CombatService.ArtStarted = Signal.new() :: Signal.Signal<Record, Arts.Art>
--- Fires (record, art, landed) when an Art's timeline ends or is cancelled.
CombatService.ArtEnded = Signal.new() :: Signal.Signal<Record, Arts.Art, boolean>
--- Fires (appliedHit) for every hit the server applied, player Arts and enemy strikes alike.
CombatService.HitLanded = Signal.new() :: Signal.Signal<Types.AppliedHit>
--- Fires (playerRecord, enemyRecord) on a perfect parry.
CombatService.Parried = Signal.new() :: Signal.Signal<Record, Record>

local deps: Deps? = nil
local sessions: { [number]: Session } = {}
local clipCache: { [string]: Types.ClipDef } = {}
local heartbeatConnection: Connection? = nil
local signalConnections: { Connection } = {}
local started = false

-- ------------------------------------------------------------------------------------------
-- Engine seam and helpers
-- ------------------------------------------------------------------------------------------

local function dependencies(): Deps
	if deps == nil then
		error("CombatService: call start() or bind() first")
	end
	return deps :: Deps
end

--- Installs the engine (or test) dependencies without registering handlers.
function CombatService.bind(newDeps: Deps)
	deps = newDeps
end

--- The server clock (workspace:GetServerTimeNow in production, a manual clock in tests).
function CombatService.now(): number
	return dependencies().now()
end

local function sessionOf(id: number): Session
	local session = sessions[id]
	if session == nil then
		session = {
			generation = 0,
			basicChain = 0,
			basicLastAt = -math.huge,
			dodgeReadyAt = -math.huge,
			lastParryAt = nil,
			run = nil,
			ready = false,
			warnedNoTrail = false,
			warnedNoBlade = false,
		}
		sessions[id] = session
	end
	return session
end

local function toVec3(v: Vector3): Types.Vec3
	return { v.X, v.Y, v.Z }
end

local function asVector(value: any): Vector3
	if typeof(value) == "Vector3" then
		return value
	end
	if typeof(value) == "table" and #value == 3 then -- index: a plain {x, y, z} has three components
		return Vector3.new(value[1], value[2], value[3])
	end
	return Vector3.zero
end

local function unitOrNil(v: Vector3): Vector3?
	if v.Magnitude < 1e-6 then
		return nil
	end
	return v.Unit
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function fireAll(remote: string, payload: any)
	local net = dependencies().net
	if net ~= nil then
		net.fireAll(remote, payload)
	end
end

local function fireTo(player: Player?, remote: string, payload: any)
	local net = dependencies().net
	if net ~= nil and player ~= nil then
		net.fire(remote, player, payload)
	end
end

local function reject(record: Record?, player: Player?, action: string, reason: string, clientTime: number?)
	local target = player or (if record ~= nil then record.player else nil)
	fireTo(target, "ActionRejected", { action = action, reason = reason, clientTime = clientTime })
end

--- Resolves a clip id ("player/OneHandedSword/Horizontal") to its module under Shared.clips, or nil.
function CombatService.clipById(id: string): Types.ClipDef?
	local cached = clipCache[id]
	if cached ~= nil then
		return cached
	end
	local node: Instance? = Shared:FindFirstChild("clips")
	for segment in id:gmatch("[^/]+") do
		if node == nil then
			return nil
		end
		node = node:FindFirstChild(segment)
	end
	if node == nil or not node:IsA("ModuleScript") then
		return nil
	end
	local ok, clip = pcall(require, node :: ModuleScript)
	if not ok or typeof(clip) ~= "table" then
		warn(("[CombatService] clip %s failed to load: %s"):format(id, tostring(clip)))
		return nil
	end
	clipCache[id] = clip
	return clip
end

local function weaponOf(record: Record): Weapons.Weapon?
	local weaponId = record.weaponId
	if weaponId == nil then
		return nil
	end
	return Weapons.byId(weaponId)
end

-- "player/<WeaponCategory>/<ClipName>" for the equipped weapon, or nil without one.
local function playerClipId(record: Record, clipName: string): string?
	local weapon = weaponOf(record)
	if weapon == nil then
		return nil
	end
	return STAGE_PLAYER .. CLIP_SEPARATOR .. weapon.category .. CLIP_SEPARATOR .. clipName
end

local function hitPayload(applied: Types.AppliedHit): any
	return {
		attackerId = applied.attackerId,
		targetId = applied.targetId,
		damage = applied.damage,
		crit = applied.crit,
		gaugeDamage = applied.gaugeDamage,
		killed = applied.killed,
		broke = applied.broke,
		hitStop = applied.hitStop,
		position = applied.position,
		parried = applied.parried,
		guarded = applied.guarded,
		reflected = applied.reflected,
		artId = applied.artId,
		hitIndex = applied.hitIndex,
		-- The side the blow came from in the target's frame: enemies play their directional
		-- flinch from it (section 10, "Stagger has four directional clips").
		staggerDirection = applied.staggerDirection,
	}
end

local function announceHit(applied: Types.AppliedHit)
	fireAll("HitConfirmed", hitPayload(applied))
	CombatService.HitLanded:Fire(applied)
end

local function showSwitchWindow(enemy: Record, opener: Record, now: number)
	fireAll("SwitchWindow", {
		entityId = enemy.id,
		openerId = opener.id,
		position = toVec3(EntityService.positionOf(enemy.id) or Vector3.zero),
		duration = Combat.switchWindow,
		serverTime = now,
	})
end

-- Property reads that fail on a rig without the engine behind it (Lune) read as nil.
local function readProperty(instance: Instance, name: string): any
	local ok, value = pcall(function()
		return (instance :: any)[name]
	end)
	return if ok then value else nil
end

-- The stances a fighter satisfies right now (section 6: moving, standing, mid-air, after a parry).
local function stancesOf(record: Record, now: number, lastParryAt: number?): { Types.Precondition }
	local list: { Types.Precondition } = {}
	local humanoid = record.model:FindFirstChildOfClass("Humanoid")
	local airborne = false
	local moving = false
	if humanoid ~= nil then
		local floor = readProperty(humanoid, "FloorMaterial")
		airborne = floor == Enum.Material.Air
		local moveDirection = readProperty(humanoid, "MoveDirection")
		moving = typeof(moveDirection) == "Vector3" and (moveDirection :: Vector3).Magnitude > 0
	end
	if airborne then
		table.insert(list, "Airborne")
	elseif moving then
		table.insert(list, "Moving")
	else
		table.insert(list, "Standing")
	end
	if lastParryAt ~= nil and now - lastParryAt <= Combat.switchWindow then
		table.insert(list, "AfterParry")
	end
	return list
end

local function facingMatches(record: Record, facing: { number }, lookVector: Vector3?): boolean
	local reported = unitOrNil(flat(asVector(facing)))
	if reported == nil then
		return false
	end
	local look = lookVector or EntityService.lookVectorOf(record.id)
	if look == nil then
		return true -- no root to compare against; the request is otherwise valid
	end
	local actual = unitOrNil(flat(look))
	if actual == nil then
		return true
	end
	return reported:Dot(actual) >= 1 - Combat.facingTolerance
end

--- When a requested action's server timeline starts: the client's stamp (workspace:GetServerTimeNow
--- on the client, the same clock as `now`) clamped into [max(now - lagAllowance, min(freeAt, now)), now].
--- A lagged swing catches up by at most combat.lagAllowance, never starts in the future, and never
--- starts before `freeAt`, the fighter's lockUntil read before the new action replaces it: a stamp
--- cannot pull an Art or basic swing back into the post-motion, stagger or swing before it (sections
--- 6 and 17, D-010). A lock still running at receipt (a request inside artRequestTolerance, a basic
--- swing being cancelled) floors the start at `now`.
function CombatService.runStartOf(clientTime: any, now: number, freeAt: number?): number
	if typeof(clientTime) ~= "number" or clientTime ~= clientTime then
		return now -- missing or NaN: no rewind
	end
	local earliest = now - Combat.lagAllowance
	if freeAt ~= nil and freeAt == freeAt then
		earliest = math.max(earliest, math.min(freeAt, now))
	end
	return math.clamp(clientTime, earliest, now)
end

-- A body is free to start an action when it is in a free state, cancelling a basic swing, or its
-- lock has (almost) run out; an Art in flight and a Break never are.
local function busyReason(record: Record, now: number): string?
	if record.state == "Art" and record.stateTag == "Basic" then
		return nil -- a basic swing is cancelable: the next basic, an Art, a guard or a dodge may cut it
	end
	if record.lockUntil - Combat.artRequestTolerance > now then
		return "Locked"
	end
	if record.state == "Break" or record.state == "Art" then
		return "Busy:" .. record.state
	end
	return nil
end

-- ------------------------------------------------------------------------------------------
-- Validation (pure given a record; Lune-tested for every reason)
-- ------------------------------------------------------------------------------------------

--- Checks an ArtRequest against the record and the data; returns (ok, reason).
function CombatService.validateArtRequest(
	record: Record?,
	art: Arts.Art?,
	payload: ArtPayload,
	now: number,
	context: ValidationContext?
): (boolean, string?)
	if record == nil then
		return false, "NoEntity"
	end
	if record.state == "Dead" then
		return false, "Dead"
	end
	if art == nil then
		return false, "UnknownArt"
	end
	local weaponId = record.weaponId
	if weaponId == nil or Weapons.byId(weaponId) == nil then
		return false, "NoWeapon"
	end
	if not Weapons.matchesArt(weaponId, art.weapon) then
		return false, "WeaponMismatch"
	end
	if (record.proficiency[art.weapon] or 0) < art.unlock then
		return false, "Proficiency"
	end
	-- Section 17: the Art must sit in the fighter's quick slots. A record without slots (an enemy
	-- with Arts, a stand-in, a test rig) has no ring to check against and skips this.
	local slots = record.artSlots
	if slots ~= nil and table.find(slots, art.id) == nil then
		return false, "NotSlotted"
	end
	local busy = busyReason(record, now)
	if busy ~= nil then
		return false, busy
	end
	local ctx: ValidationContext = context or {}
	if not facingMatches(record, payload.facing, ctx.lookVector) then
		return false, "Facing"
	end
	local preconditions = art.preconditions
	if preconditions ~= nil and #preconditions > 0 then
		local stances = ctx.stances or stancesOf(record, now, ctx.lastParryAt)
		local satisfied = false
		for _, stance in stances do
			if table.find(preconditions, stance) ~= nil then
				satisfied = true
				break
			end
		end
		if not satisfied then
			return false, "Stance"
		end
	end
	if CombatService.clipById(art.clip) == nil then
		return false, "NoClip"
	end
	return true, nil
end

--- Checks a BasicAttackRequest; `clipId` is the chain hit the server picked.
function CombatService.validateBasicRequest(
	record: Record?,
	clipId: string?,
	payload: BasicPayload,
	now: number,
	context: ValidationContext?
): (boolean, string?)
	if record == nil then
		return false, "NoEntity"
	end
	if record.state == "Dead" then
		return false, "Dead"
	end
	if record.weaponId == nil or weaponOf(record) == nil then
		return false, "NoWeapon"
	end
	local busy = busyReason(record, now)
	if busy ~= nil then
		return false, busy
	end
	local ctx: ValidationContext = context or {}
	if not facingMatches(record, payload.facing, ctx.lookVector) then
		return false, "Facing"
	end
	if clipId == nil or CombatService.clipById(clipId) == nil then
		return false, "NoClip"
	end
	return true, nil
end

--- Checks a DodgeRequest: free body, cooldown over, a real direction.
function CombatService.validateDodgeRequest(
	record: Record?,
	payload: DodgePayload,
	now: number,
	dodgeReadyAt: number?
): (boolean, string?)
	if record == nil then
		return false, "NoEntity"
	end
	if record.state == "Dead" then
		return false, "Dead"
	end
	local busy = busyReason(record, now)
	if busy ~= nil then
		return false, busy
	end
	if dodgeReadyAt ~= nil and dodgeReadyAt - Combat.artRequestTolerance > now then
		return false, "Cooldown"
	end
	if unitOrNil(flat(asVector(payload.direction))) == nil then
		return false, "Direction"
	end
	return true, nil
end

--- Checks a GuardRequest {held = true}: alive and in a state a guard can be raised from.
function CombatService.validateGuardRequest(record: Record?): (boolean, string?)
	if record == nil then
		return false, "NoEntity"
	end
	if record.state == "Dead" then
		return false, "Dead"
	end
	if not EntityService.canGuard(record.id) then
		return false, "Busy:" .. record.state
	end
	return true, nil
end

--- The next hit of the three-hit chain: 1 when the chain is empty, finished or the window closed.
function CombatService.nextBasicIndex(chainIndex: number, lastAt: number, now: number): number
	if chainIndex <= 0 or chainIndex >= Combat.basicChainLength or now - lastAt > Combat.basicChainWindow then
		return 1
	end
	return chainIndex + 1
end

--- The dodge clip name for a world direction relative to the body ("DodgeBack" when it points behind).
function CombatService.dodgeClipName(rootCFrame: CFrame, direction: Vector3): string
	local localDirection = rootCFrame:VectorToObjectSpace(flat(direction))
	local suffix
	if math.abs(localDirection.Z) >= math.abs(localDirection.X) then
		suffix = if localDirection.Z <= 0 then "Forward" else "Back"
	else
		suffix = if localDirection.X > 0 then "Right" else "Left"
	end
	return "Dodge" .. suffix
end

-- ------------------------------------------------------------------------------------------
-- Timelines
-- ------------------------------------------------------------------------------------------

-- Clip time the end pose freezes: the clip's PostMotionStart event, else the Art's total.
local function postMotionStartOf(clip: Types.ClipDef, fallback: number): number
	for _, event in clip.events do
		if event.kind == "PostMotionStart" then
			return event.time
		end
	end
	return fallback
end

-- The gauge a basic swing drains: a tenth of the category's first Art, scaled by the weapon.
local function basicGaugeOf(weapon: Weapons.Weapon): number
	local firstArt = Arts.list(weapon.category)[1]
	local reference = if firstArt ~= nil then firstArt.gaugeDamage else 0
	return DamageMath.gaugeDamage(reference * weapon.gaugeDamage, true)
end

local function cancelRun(session: Session, record: Record?)
	local run = session.run
	if run == nil then
		return
	end
	session.run = nil
	session.generation += 1
	if run.art ~= nil and record ~= nil then
		CombatService.ArtEnded:Fire(record, run.art, run.hitAny)
	end
end

local function finishRun(session: Session, run: ArtRun, record: Record)
	session.run = nil
	if run.art ~= nil then
		local postMotion = if run.hitBreak then Combat.breakPostMotion else run.art.postMotion
		if postMotion > 0 then
			EntityService.setState(record.id, "PostMotion", postMotion)
		else
			EntityService.setState(record.id, "Idle")
		end
		CombatService.ArtEnded:Fire(record, run.art, run.hitAny)
	end
	-- A basic swing's Art state expires on EntityService's timer (basicHitDuration).
end

-- A blade touch becomes a hit: crit roll, attack value, applyHit, HitConfirmed to all.
local function landHit(run: ArtRun, attacker: Record, hit: HitSweep.Hit, now: number)
	local target = EntityService.get(hit.targetId)
	if target == nil or target.state == "Dead" or target.id == attacker.id then
		return
	end
	-- Phase 0: no PvP; a player's blade passes through other players.
	if target.kind == attacker.kind then
		return
	end
	local d = dependencies()
	local crit = DamageMath.rollCrit(d.random, attacker.stats.agi)
	local raw = DamageMath.attackValue(attacker.attack, run.multiplier, attacker.stats.str, crit)
	-- Section 6: 6 frames on the final hit. A basic chain's final hit is its third swing, not every swing.
	local isLast = run.finalHit and run.windowIndex >= #run.windows
	local applied = EntityService.applyHit(target.id, {
		attackerId = attacker.id,
		rawDamage = raw,
		gaugeDamage = run.gaugePerHit,
		crit = crit,
		parried = false,
		guarded = false,
		isBasic = run.isBasic,
		artId = if run.art ~= nil then run.art.id else nil,
		hitIndex = run.windowIndex,
		hitStop = DamageMath.hitStopTier(isLast, false),
		position = toVec3(hit.position),
	})
	if applied.wasInBreak then
		run.hitBreak = true
	end
	run.hitAny = true
	announceHit(applied)
	-- An Art that connects opens a Switch window on the enemy (Phase 1 logic, Phase 0 ring).
	if run.art ~= nil and not run.switchShown and target.kind == "Enemy" and not applied.killed then
		run.switchShown = true
		showSwitchWindow(target, attacker, now)
	end
end

-- Sweeps the blade over this frame's sample times; returns how many arc sub-samples it spent out
-- of `subdivisions` (what is left of this frame's combat.sweepMaxSubdivisions).
local function sweep(
	run: ArtRun,
	session: Session,
	record: Record,
	times: { number },
	now: number,
	subdivisions: number
): number
	if #times == 0 then
		return 0
	end
	local root = record.model.PrimaryPart
	if root == nil then
		return 0
	end
	local trailStart, trailEnd = HitSweep.trailAttachments(record.model)
	if trailStart == nil or trailEnd == nil then
		if not session.warnedNoTrail then
			session.warnedNoTrail = true
			warn(("[CombatService] %s has no TrailStart/TrailEnd; its swings cannot hit"):format(record.name))
		end
		return 0
	end
	-- This frame's samples are solved from the live root (the body the clients see, carried by the
	-- clip's root motion); each keeps its root so the next frame can interpolate from it. A frame
	-- that sweeps several sample times (a hitch) spreads the root's travel since the previous frame's
	-- last sample over them in clip time; the last one is solved from the live root.
	local samples = HitSweep.bladePath(record.model, root.CFrame, run.clip, times, trailStart, trailEnd, run.lastSample)
	if samples == nil then
		if not session.warnedNoBlade then
			session.warnedNoBlade = true
			warn(
				("[CombatService] %s: the blade cannot be solved through the rig's joints; its swings cannot hit"):format(
					record.name
				)
			)
		end
		return 0
	end
	-- Connect this frame's path to where the blade was at the end of the previous one; that sample
	-- was overlap-tested last frame, so the sweep continues from it without testing it again.
	local continued = run.lastSample ~= nil
	local chain: { HitSweep.BladeSample } = {}
	if run.lastSample ~= nil then
		table.insert(chain, run.lastSample :: HitSweep.BladeSample)
	end
	for _, sample in samples do
		table.insert(chain, sample)
	end
	run.lastSample = samples[#samples]
	-- Follow the arc between the samples, not their chords. The root is not frozen during a window,
	-- so a sub-sample between last frame's sample and this frame's first is solved from a root
	-- interpolated between the two frames' roots (HitSweep.followArc): the body's own travel is
	-- spread over the interval as it happened, instead of landing in one step no split can shrink.
	local path, added = HitSweep.followArc(
		chain,
		HitSweep.solver(record.model, run.clip, trailStart, trailEnd),
		Combat.sweepMaxTipStep,
		subdivisions
	)
	local d = dependencies()
	local hits = HitSweep.castBladePath(path, {
		exclude = { record.model },
		resolve = function(instance: Instance): (number?, Model?)
			local target = EntityService.fromInstance(instance)
			if target == nil then
				return nil, nil
			end
			return target.id, target.model
		end,
		alreadyHit = run.windowHits,
		cast = d.cast,
		overlap = d.overlap,
		continued = continued,
	})
	for _, hit in hits do
		landHit(run, record, hit, now)
		if EntityService.get(record.id) == nil or record.state ~= "Art" then
			return added -- the attacker fell or was knocked out of the Art by a reaction
		end
	end
	return added
end

local function stepRun(session: Session, run: ArtRun, now: number)
	local record = EntityService.get(run.entityId)
	if record == nil or record.state ~= "Art" or session.generation ~= run.generation then
		cancelRun(session, record)
		return
	end
	local clipTime = now - run.startedAt
	-- The frame's arc sub-samples, shared by every window this frame sweeps (a caught-up frame can
	-- close one window and open the next), so one fighter never adds more than the cap per frame.
	local subdivisions = Combat.sweepMaxSubdivisions
	while run.windowIndex <= #run.windows do
		local window = run.windows[run.windowIndex]
		if clipTime < window.open then
			break
		end
		local fromTime = run.sampledTo or window.open
		local toTime = math.min(clipTime, window.close)
		local times = HitSweep.sampleTimes(fromTime, toTime, Combat.hitSampleHz, run.sampledTo == nil)
		subdivisions -= sweep(run, session, record, times, now, subdivisions)
		if session.run ~= run then
			return -- cancelled from inside a reaction
		end
		run.sampledTo = toTime
		if clipTime >= window.close then
			run.windowIndex += 1
			run.sampledTo = nil
			run.lastSample = nil
			run.windowHits = {}
		else
			break
		end
	end
	if run.windowIndex > #run.windows and clipTime >= run.postMotionAt then
		finishRun(session, run, record)
	end
end

--- Steps every running timeline against the clock; Heartbeat calls it, tests call it by hand.
function CombatService.tick()
	local now = dependencies().now()
	for _, session in sessions do
		local run = session.run
		if run ~= nil then
			stepRun(session, run, now)
		end
	end
end

local function beginRun(
	record: Record,
	art: Arts.Art?,
	clipId: string,
	clip: Types.ClipDef,
	multiplier: number,
	gaugePerHit: number,
	facing: Vector3,
	now: number,
	startAt: number, -- clip time zero: `now`, or a request's clamped client stamp (runStartOf)
	finalHit: boolean
)
	local session = sessionOf(record.id)
	cancelRun(session, record)
	session.generation += 1
	local windows = ClipSampler.hitWindows(clip)
	local postMotionAt = postMotionStartOf(clip, if art ~= nil then art.total else clip.duration)
	-- The whole timeline (windows, freeze, lock) runs on the clip clock from startAt.
	local elapsed = now - startAt
	if art ~= nil then
		EntityService.setState(record.id, "Art", postMotionAt + art.postMotion - elapsed)
	else
		EntityService.setState(record.id, "Art", Combat.basicHitDuration - elapsed, nil, "Basic")
	end
	EntityService.markCombat(record.id)
	session.run = {
		entityId = record.id,
		generation = session.generation,
		art = art,
		isBasic = art == nil,
		clipId = clipId,
		clip = clip,
		windows = windows,
		startedAt = startAt,
		postMotionAt = postMotionAt,
		multiplier = multiplier,
		gaugePerHit = gaugePerHit,
		finalHit = finalHit,
		windowIndex = 1,
		sampledTo = nil,
		lastSample = nil,
		windowHits = {},
		hitAny = false,
		hitBreak = false,
		switchShown = false,
	}
	fireAll("ActionStarted", {
		entityId = record.id,
		clipId = clipId,
		serverTime = startAt, -- other clients start the clip at this clock position
		facing = toVec3(facing),
		artId = if art ~= nil then art.id else nil,
	})
	if art ~= nil then
		CombatService.ArtStarted:Fire(record, art)
	end
end

local function facingOf(record: Record, requested: Vector3?): Vector3
	local look = requested or EntityService.lookVectorOf(record.id)
	local unit = if look ~= nil then unitOrNil(flat(look)) else nil
	return unit or (Vector3.zAxis * -1)
end

--- Starts an Art for a fighter after validation (the ArtRequest handler, bosses with Arts, smoke
--- tests). Returns (ok, reason).
function CombatService.beginArt(entityId: number, artId: string, facing: Vector3?): (boolean, string?)
	local record = EntityService.get(entityId)
	local art = Arts.byId(artId)
	local now = dependencies().now()
	local look = if record ~= nil then facingOf(record, facing) else Vector3.zAxis * -1
	local payload: ArtPayload = { artId = artId, facing = toVec3(look), clientTime = 0 }
	local session = if record ~= nil then sessionOf(record.id) else nil
	local ok, reason = CombatService.validateArtRequest(record, art, payload, now, {
		lastParryAt = if session ~= nil then session.lastParryAt else nil,
	})
	if not ok or record == nil or art == nil then
		return false, reason
	end
	local clip = CombatService.clipById(art.clip)
	if clip == nil then
		return false, "NoClip"
	end
	local weapon = weaponOf(record)
	local gaugeScale = if weapon ~= nil then weapon.gaugeDamage else 1
	beginRun(
		record,
		art,
		art.clip,
		clip,
		art.multiplier,
		DamageMath.gaugeDamage(art.gaugeDamage * gaugeScale, false),
		look,
		now,
		now,
		true
	)
	return true, nil
end

-- The next basic-chain swing after validation; `clientTime` (a request's stamp) or nil (code callers).
-- The swing, its chain index and the chain clock all run from the same start: the clamped stamp,
-- floored at the moment the body was last free (runStartOf), or `now` for code callers.
local function startBasic(entityId: number, facing: Vector3?, clientTime: number?): (boolean, string?)
	local record = EntityService.get(entityId)
	local now = dependencies().now()
	local session = if record ~= nil then sessionOf(record.id) else nil
	local startAt = if record ~= nil and clientTime ~= nil
		then CombatService.runStartOf(clientTime, now, record.lockUntil)
		else now
	local index = if session ~= nil
		then CombatService.nextBasicIndex(session.basicChain, session.basicLastAt, startAt)
		else 1
	local clipId = if record ~= nil then playerClipId(record, "Basic" .. tostring(index)) else nil
	local look = if record ~= nil then facingOf(record, facing) else Vector3.zAxis * -1
	local payload: BasicPayload = { facing = toVec3(look), clientTime = 0 }
	local ok, reason = CombatService.validateBasicRequest(record, clipId, payload, now)
	if not ok or record == nil or clipId == nil or session == nil then
		return false, reason
	end
	local clip = CombatService.clipById(clipId)
	local weapon = weaponOf(record)
	if clip == nil or weapon == nil then
		return false, "NoClip"
	end
	session.basicChain = index
	session.basicLastAt = startAt
	local finalHit = index >= Combat.basicChainLength
	beginRun(
		record,
		nil,
		clipId,
		clip,
		Combat.basicAttackMultiplier,
		basicGaugeOf(weapon),
		look,
		now,
		startAt,
		finalHit
	)
	return true, nil
end

--- Starts the next basic-chain swing for a fighter after validation. Returns (ok, reason).
function CombatService.beginBasic(entityId: number, facing: Vector3?): (boolean, string?)
	return startBasic(entityId, facing, nil)
end

--- Starts a dodge after validation: Dodge state, invulnerability frames, cooldown, the clip to all.
function CombatService.beginDodge(entityId: number, direction: Vector3): (boolean, string?)
	local record = EntityService.get(entityId)
	local now = dependencies().now()
	local session = if record ~= nil then sessionOf(record.id) else nil
	local payload: DodgePayload = { direction = toVec3(direction), clientTime = 0 }
	local ok, reason =
		CombatService.validateDodgeRequest(record, payload, now, if session ~= nil then session.dodgeReadyAt else nil)
	if not ok or record == nil or session == nil then
		return false, reason
	end
	local root = record.model.PrimaryPart
	local rootCFrame = if root ~= nil then root.CFrame else CFrame.identity
	local clipId = playerClipId(record, CombatService.dodgeClipName(rootCFrame, direction))
	cancelRun(session, record)
	session.dodgeReadyAt = now + Combat.dodgeCooldown
	EntityService.setGuard(record.id, false)
	EntityService.setState(record.id, "Dodge", Combat.dodgeDuration)
	EntityService.setInvulnerable(record.id, now + Combat.dodgeInvulnerability)
	if clipId ~= nil then
		fireAll("ActionStarted", {
			entityId = record.id,
			clipId = clipId,
			serverTime = now,
			facing = toVec3(facingOf(record, nil)),
		})
	end
	return true, nil
end

--- Raises or lowers a fighter's guard after validation. Returns (ok, reason). The guard cone always
--- faces the server's root (enemyStrike reads it at strike time); a client cannot aim it.
function CombatService.setGuard(entityId: number, held: boolean): (boolean, string?)
	local record = EntityService.get(entityId)
	if held then
		local ok, reason = CombatService.validateGuardRequest(record)
		if not ok or record == nil then
			return false, reason
		end
		cancelRun(sessionOf(record.id), record)
	elseif record == nil then
		return false, "NoEntity"
	end
	EntityService.setGuard(entityId, held)
	return true, nil
end

--- Cancels whatever timeline a fighter is running (a stagger, a death, a disconnect).
function CombatService.cancelAction(entityId: number)
	local session = sessions[entityId]
	if session ~= nil then
		cancelRun(session, EntityService.get(entityId))
	end
end

--- The Art a fighter is executing and when it started, or nil (AntiCheat's root-motion allowance).
function CombatService.currentArt(entityId: number): (Arts.Art?, number?)
	local session = sessions[entityId]
	if session == nil or session.run == nil then
		return nil, nil
	end
	local run = session.run :: ArtRun
	return run.art, run.startedAt
end

--- Studs the body may travel beyond its walk speed right now: the Art's root motion plus slack.
function CombatService.rootMotionAllowance(entityId: number): number
	local art = CombatService.currentArt(entityId)
	if art == nil then
		local session = sessions[entityId]
		if session ~= nil and session.run ~= nil then
			return Combat.rootMotionSlack -- a basic swing carries no root motion of its own
		end
		return 0
	end
	return art.rootMotion + Combat.rootMotionSlack
end

--- True once the player's client reported ClientReady.
function CombatService.isReady(player: Player): boolean
	local record = EntityService.fromPlayer(player)
	if record == nil then
		return false
	end
	local session = sessions[record.id]
	return session ~= nil and session.ready
end

-- ------------------------------------------------------------------------------------------
-- Enemy strikes
-- ------------------------------------------------------------------------------------------

--- Resolves an enemy attack at strike time against every player in its cone or line: dodge frames,
--- parry, guard, damage. Returns the hits it applied (parries included). Origin and facing may be
--- Vector3 or {x, y, z}.
function CombatService.enemyStrike(
	enemyId: number,
	attackDef: Types.EnemyAttackDef,
	origin: any,
	facing: any
): { Types.AppliedHit }
	local results: { Types.AppliedHit } = {}
	local enemy = EntityService.get(enemyId)
	if enemy == nil or enemy.state == "Dead" then
		return results
	end
	local now = dependencies().now()
	local originVector = asVector(origin)
	local facingVector = unitOrNil(flat(asVector(facing))) or facingOf(enemy, nil)

	local candidates: { HitSweep.Candidate } = {}
	for _, player in EntityService.players() do
		if player.state ~= "Dead" then
			table.insert(candidates, {
				id = player.id,
				position = EntityService.positionOf(player.id) or Vector3.zero,
				radius = HitSweep.bodyRadius(player.model),
			})
		end
	end
	local struck = if attackDef.arc <= 0
		then HitSweep.lineTargets(originVector, facingVector, attackDef.reach, Combat.strikeLineWidth, candidates)
		else HitSweep.coneTargets(originVector, facingVector, attackDef.reach, attackDef.arc, candidates)

	for _, candidate in struck do
		local player = EntityService.get(candidate.id)
		if player == nil or player.state == "Dead" then
			continue
		end
		if EntityService.isInvulnerable(player.id, now) then
			continue -- a clean dodge: nothing to show
		end
		local playerPosition = candidate.position
		-- Section 6: the guard cone is the body's facing, read from the server's root at strike time.
		local guardFacing = EntityService.lookVectorOf(player.id) or Vector3.zAxis * -1
		local inGuardCone =
			DamageMath.inCone(playerPosition, guardFacing, originVector, DamageMath.guardCone(player.hasShield))
		local guarding = player.state == "Guard" and player.guardHeld and inGuardCone
		local session = sessionOf(player.id)

		if guarding and attackDef.telegraph ~= "Unblockable" and DamageMath.parryWindowOpen(player.guardSince, now) then
			-- A perfect parry: no damage, the enemy staggers, a Switch window opens on it.
			local applied = EntityService.applyHit(player.id, {
				attackerId = enemy.id,
				rawDamage = 0,
				gaugeDamage = 0,
				crit = false,
				parried = true,
				guarded = false,
				hitIndex = 1,
				hitStop = "Normal",
				position = toVec3(playerPosition),
			})
			session.lastParryAt = now
			CombatService.cancelAction(enemy.id)
			EntityService.setState(enemy.id, "Stagger", Combat.parryStagger)
			announceHit(applied)
			showSwitchWindow(enemy, player, now)
			CombatService.Parried:Fire(player, enemy)
			table.insert(results, applied)
			continue
		end

		local guarded = guarding and attackDef.telegraph == "Normal"
		local breakGuard = guarding and attackDef.telegraph == "GuardBreak"
		-- Section 6: guarding drains the player's own Guard Gauge; an open hit costs HP and a stagger,
		-- never gauge (a GuardBreak telegraph on a held guard empties it through breakGuard).
		local applied = EntityService.applyHit(player.id, {
			attackerId = enemy.id,
			rawDamage = DamageMath.attackValue(enemy.attack, attackDef.multiplier, 0, false),
			gaugeDamage = if guarded then attackDef.gaugeDamage else 0,
			crit = false,
			parried = false,
			guarded = guarded,
			breakGuard = breakGuard,
			hitIndex = 1,
			hitStop = "Normal",
			position = toVec3(playerPosition),
		})
		if not guarded and not applied.killed and not applied.broke then
			-- The blow lands: the body flinches from the side it came from, and any Art is lost.
			CombatService.cancelAction(player.id)
			EntityService.setState(player.id, "Stagger", Combat.staggerDuration, applied.staggerDirection)
		end
		announceHit(applied)
		table.insert(results, applied)
	end
	return results
end

-- ------------------------------------------------------------------------------------------
-- Net handlers
-- ------------------------------------------------------------------------------------------

local function onArtRequest(player: Player, payload: any)
	local record = EntityService.fromPlayer(player)
	local art = Arts.byId(payload.artId)
	local now = dependencies().now()
	local session = if record ~= nil then sessionOf(record.id) else nil
	local ok, reason = CombatService.validateArtRequest(record, art, payload, now, {
		lastParryAt = if session ~= nil then session.lastParryAt else nil,
	})
	if not ok or record == nil or art == nil then
		reject(record, player, "Art", reason or "Rejected", payload.clientTime)
		return
	end
	local clip = CombatService.clipById(art.clip)
	if clip == nil then
		reject(record, player, "Art", "NoClip", payload.clientTime)
		return
	end
	local weapon = weaponOf(record)
	local gaugeScale = if weapon ~= nil then weapon.gaugeDamage else 1
	local facing = unitOrNil(flat(asVector(payload.facing))) or facingOf(record, nil)
	-- Read the lock before beginRun replaces it: the rewind never reaches back past it.
	local startAt = CombatService.runStartOf(payload.clientTime, now, record.lockUntil)
	beginRun(
		record,
		art,
		art.clip,
		clip,
		art.multiplier,
		DamageMath.gaugeDamage(art.gaugeDamage * gaugeScale, false),
		facing,
		now,
		startAt,
		true
	)
end

local function onBasicAttackRequest(player: Player, payload: any)
	local record = EntityService.fromPlayer(player)
	local facing = unitOrNil(flat(asVector(payload.facing)))
	local ok: boolean, reason: string?
	if record == nil then
		ok, reason = false, "NoEntity"
	elseif not facingMatches(record, payload.facing, nil) then
		ok, reason = false, "Facing"
	else
		ok, reason = startBasic(record.id, facing, payload.clientTime)
	end
	if not ok then
		reject(record, player, "BasicAttack", reason or "Rejected", payload.clientTime)
	end
end

local function onGuardRequest(player: Player, payload: any)
	local record = EntityService.fromPlayer(player)
	if record == nil then
		reject(nil, player, "Guard", "NoEntity", payload.clientTime)
		return
	end
	-- The payload's facing is never read: the cone follows the server's root (section 6, 17).
	local ok, reason = CombatService.setGuard(record.id, payload.held == true)
	if not ok and payload.held == true then
		reject(record, player, "Guard", reason or "Rejected", payload.clientTime)
	end
end

local function onDodgeRequest(player: Player, payload: any)
	local record = EntityService.fromPlayer(player)
	if record == nil then
		reject(nil, player, "Dodge", "NoEntity", payload.clientTime)
		return
	end
	local ok, reason = CombatService.beginDodge(record.id, asVector(payload.direction))
	if not ok then
		reject(record, player, "Dodge", reason or "Rejected", payload.clientTime)
	end
end

local function onTargetRequest(player: Player, payload: any)
	local record = EntityService.fromPlayer(player)
	if record == nil then
		return
	end
	if not EntityService.setTarget(record.id, payload.entityId) then
		reject(record, player, "Target", "UnknownTarget", nil)
	end
end

local function onSwitchCallRequest(_player: Player, _payload: any)
	-- Phase 1: the SWITCH ping to the nearest party member. Accepted and ignored in Phase 0.
end

local function onClientReady(player: Player, _payload: any)
	local record = EntityService.fromPlayer(player)
	if record ~= nil then
		sessionOf(record.id).ready = true
	end
end

--- Runs a request handler by remote name with a payload (what `net.on` calls; tests call it directly).
function CombatService.handle(name: string, player: Player, payload: any)
	local handlers: { [string]: (Player, any) -> () } = {
		ArtRequest = onArtRequest,
		BasicAttackRequest = onBasicAttackRequest,
		GuardRequest = onGuardRequest,
		DodgeRequest = onDodgeRequest,
		TargetRequest = onTargetRequest,
		SwitchCallRequest = onSwitchCallRequest,
		ClientReady = onClientReady,
	}
	local handler = handlers[name]
	if handler == nil then
		error(("CombatService: no handler for %s"):format(name))
	end
	handler(player, payload)
end

local REQUESTS = {
	"ArtRequest",
	"BasicAttackRequest",
	"GuardRequest",
	"DodgeRequest",
	"TargetRequest",
	"SwitchCallRequest",
	"ClientReady",
}

local function engineDeps(): Deps
	local RunService = game:GetService("RunService")
	return {
		now = function()
			return workspace:GetServerTimeNow()
		end,
		net = Net.server(),
		heartbeat = function(handler)
			return RunService.Heartbeat:Connect(handler)
		end,
		cast = nil,
		overlap = nil,
		random = Random.new(),
	}
end

local function wireEntitySignals()
	table.insert(
		signalConnections,
		EntityService.StateChanged:Connect(function(record, state)
			if state ~= "Art" and state ~= "PostMotion" then
				local session = sessions[record.id]
				if session ~= nil and session.run ~= nil then
					cancelRun(session, record)
				end
			end
		end)
	)
	table.insert(
		signalConnections,
		EntityService.Unregistered:Connect(function(record)
			local session = sessions[record.id]
			if session ~= nil then
				cancelRun(session, record)
				sessions[record.id] = nil
			end
		end)
	)
end

--- Starts the service: Net handlers, the Heartbeat step, cancellation on stagger and death.
function CombatService.start()
	if started then
		return
	end
	started = true
	if deps == nil then
		deps = engineDeps()
	end
	local d = dependencies()
	local net = d.net
	if net ~= nil then
		for _, name in REQUESTS do
			net.on(name, function(player, payload)
				CombatService.handle(name, player, payload)
			end)
		end
		EntityService.setFireAll(net.fireAll)
	end
	if d.heartbeat ~= nil then
		heartbeatConnection = d.heartbeat(function()
			CombatService.tick()
		end)
	end
	wireEntitySignals()
end

--- Forgets every session and stops the loop (tests).
function CombatService.reset()
	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	for _, connection in signalConnections do
		connection:Disconnect()
	end
	table.clear(signalConnections)
	table.clear(sessions)
	started = false
end

return CombatService
