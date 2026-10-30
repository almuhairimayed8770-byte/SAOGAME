--!strict
--[[
	EntityService: the entity registry and the authority on HP, Guard Gauge and state
	(ARCHITECTURE "Entities", section 6, docs/DECISIONS.md D-006 and D-012).

	Every fighter, player or enemy, is registered here, gets an integer id, a CollectionService tag
	(SkyspireEntity plus SkyspirePlayer / SkyspireEnemy) and its state published as attributes on
	its Model, written only by the server. Remotes carry events (StateChanged, EntityDied); the HUD
	reads attributes. CombatService decides the attack side of a hit and calls applyHit; this file
	applies defense, Break, gauge, threat, the combat tag, death and respawn.

	Clocks and timers: `tick(dt)` runs on Heartbeat (players every frame, enemies at
	combat.enemyTickHz) and expires states, regenerates gauge and HP, pins the engine Humanoid's
	health, removes corpses and reloads dead players' characters. `EntityService.bind(deps)`
	swaps the engine (clock, net, tags, respawn, heartbeat) for fakes so every rule runs in Lune.

	The combat tag (combatUntil) also says whether a player's sword is out: a player character
	carries the Drawn attribute, true while the tag holds. Hits dealt or taken set the tag; an Art,
	a basic swing, a guard and a lock-on refresh it, and Art, PostMotion, Guard and a live lock-on
	keep refreshing it, so it ends combat.combatTagDuration after the last of them. A refresh never
	moves lastCombatAt, so HP regen still waits on the last hit only.

	Other services talk to this one through its functions and Signals; nobody writes a record.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local Combat = require(Shared.data.combat)
local Rigs = require(Shared.data.rigs)
local Weapons = require(Shared.data.weapons)
local Armor = require(Shared.data.armor)
local Signal = require(Shared.util.Signal)
local DamageMath = require(script.Parent.Parent.combat.DamageMath)

export type Record = Types.EntityRecord
export type Kind = Types.EntityKind
export type State = Types.EntityState

export type Connection = { Disconnect: (self: any) -> () }

export type Deps = {
	now: () -> number, -- server time (workspace:GetServerTimeNow)
	fireAll: ((remote: string, payload: any) -> ())?, -- Net.server().fireAll; nil before Net is up
	heartbeat: ((handler: (dt: number) -> ()) -> Connection?)?, -- RunService.Heartbeat; nil in tests
	addTag: (instance: Instance, tag: string) -> (),
	removeTag: (instance: Instance, tag: string) -> (),
	respawn: (player: Player) -> (), -- Player:LoadCharacter()
	playerRemoving: ((handler: (player: Player) -> ()) -> ())?,
}

export type EnemyOptions = {
	name: string?, -- display name override
	level: number?, -- Level attribute; defaults to the def's floor
	hasShield: boolean?,
}

local TAG_ENTITY = "SkyspireEntity"
local TAG_PLAYER = "SkyspirePlayer"
local TAG_ENEMY = "SkyspireEnemy"
local PLAYER_DEF_ID = "Player"
local PLAYER_RIG = Rigs.PlayerR15.id
local ART_SLOTS_ATTRIBUTE = "ArtSlots"

-- States the body cannot act from; entering one drops the guard and sets the lock.
local LOCK_STATES: { [string]: boolean } = {
	Art = true,
	PostMotion = true,
	Dodge = true,
	Stagger = true,
	Break = true,
	GuardBroken = true,
	Dead = true,
}

-- States a guard can be raised from (and that a held guard returns to).
local FREE_STATES: { [string]: boolean } = { Idle = true, Moving = true, Guard = true }

-- States that keep a player's combat tag (and so the drawn sword) fresh for as long as they last.
local HOLD_STATES: { [string]: boolean } = { Art = true, PostMotion = true, Guard = true }

local EntityService = {}

EntityService.TAG_ENTITY = TAG_ENTITY
EntityService.TAG_PLAYER = TAG_PLAYER
EntityService.TAG_ENEMY = TAG_ENEMY

--- Fires (record) when a fighter joins the registry.
EntityService.Registered = Signal.new() :: Signal.Signal<Record>
--- Fires (record) when a fighter leaves it (death cleanup, character removed, player left).
EntityService.Unregistered = Signal.new() :: Signal.Signal<Record>
--- Fires (record, oldHp, newHp) on every HP change, hits and regen alike.
EntityService.HpChanged = Signal.new() :: Signal.Signal<Record, number, number>
--- Fires (record, state, duration?, direction?) on every state change.
EntityService.StateChanged = Signal.new() :: Signal.Signal<Record, State, number?, string?>
--- Fires (record, killerId?) once when a fighter dies.
EntityService.Died = Signal.new() :: Signal.Signal<Record, number?>
--- Fires (record) when a Guard Gauge empties: an enemy enters Break, a player is guard-broken.
EntityService.Broke = Signal.new() :: Signal.Signal<Record>

local deps: Deps? = nil
local records: { [number]: Record } = {}
local byModel: { [Instance]: Record } = {}
local published: { [number]: { [string]: any } } = {}
local nextId = 1
local enemyAccumulator = 0
local heartbeatConnection: Connection? = nil
local started = false
local warnedNoNet = false

-- ------------------------------------------------------------------------------------------
-- Engine seam
-- ------------------------------------------------------------------------------------------

local function dependencies(): Deps
	if deps == nil then
		error("EntityService: call start() or bind() first")
	end
	return deps :: Deps
end

local function engineDeps(): Deps
	local RunService = game:GetService("RunService")
	local Players = game:GetService("Players")
	local CollectionService = game:GetService("CollectionService")
	return {
		now = function()
			return workspace:GetServerTimeNow()
		end,
		fireAll = nil,
		heartbeat = function(handler)
			return RunService.Heartbeat:Connect(handler)
		end,
		addTag = function(instance, tag)
			CollectionService:AddTag(instance, tag)
		end,
		removeTag = function(instance, tag)
			CollectionService:RemoveTag(instance, tag)
		end,
		respawn = function(player)
			if player.Parent ~= nil then
				player:LoadCharacter()
			end
		end,
		playerRemoving = function(handler)
			Players.PlayerRemoving:Connect(handler)
		end,
	}
end

--- Installs the engine (or test) dependencies without starting the loop.
function EntityService.bind(newDeps: Deps)
	deps = newDeps
end

--- Replaces the clock (tests drive time by hand).
function EntityService.setClock(now: () -> number)
	dependencies().now = now
end

--- Gives the service its outbound remotes (Main passes Net.server().fireAll after Net is up).
function EntityService.setFireAll(fireAll: ((remote: string, payload: any) -> ())?)
	dependencies().fireAll = fireAll
end

--- The server clock every timer in this service runs on.
function EntityService.now(): number
	return dependencies().now()
end

local function fireAll(remote: string, payload: any)
	local fire = dependencies().fireAll
	if fire == nil then
		if not warnedNoNet then
			warnedNoNet = true
			warn("[EntityService] no Net bound; " .. remote .. " not sent")
		end
		return
	end
	fire(remote, payload)
end

-- ------------------------------------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------------------------------------

local function rootOf(record: Record): BasePart?
	return record.model.PrimaryPart
end

local function positionOf(record: Record): Vector3
	local root = rootOf(record)
	return if root ~= nil then root.CFrame.Position else Vector3.zero
end

local function toVec3(v: Vector3): Types.Vec3
	return { v.X, v.Y, v.Z }
end

local function humanoidOf(record: Record): Humanoid?
	local humanoid = record.model:FindFirstChildOfClass("Humanoid")
	return humanoid
end

-- D-012: the engine Humanoid's health is a constant the game ignores. `force` writes without
-- reading (a never-set property cannot be read under Lune); ticks compare first to avoid replication.
local function pinHumanoid(record: Record, force: boolean?)
	local humanoid = humanoidOf(record)
	if humanoid == nil then
		return
	end
	local pinned = Combat.humanoidPinnedHealth
	if force or humanoid.MaxHealth ~= pinned then
		humanoid.MaxHealth = pinned
	end
	if force or humanoid.Health ~= pinned then
		humanoid.Health = pinned
	end
end

local function setAttribute(record: Record, name: string, value: any)
	local cache = published[record.id]
	if cache == nil then
		cache = {}
		published[record.id] = cache
	end
	if cache[name] == value then
		return
	end
	cache[name] = value
	record.model:SetAttribute(name, value)
end

local function roundValue(value: number): number
	return math.floor(value + 0.5)
end

-- Writes the ARCHITECTURE attribute table; only values that changed reach the Instance.
local function publish(record: Record)
	setAttribute(record, "EntityId", record.id)
	setAttribute(record, "EntityKind", record.kind)
	setAttribute(record, "DefId", record.defId)
	-- A spawn-time Elite variant (Enemies.variant) carries a replicated label; the client only
	-- reads it (an Elite's death shatters heavy). Ordinary mobs carry none.
	local enemyDef = record.enemyDef
	if enemyDef ~= nil and enemyDef.elite == true then
		setAttribute(record, "Elite", true)
	end
	setAttribute(record, "Rig", record.rig)
	setAttribute(record, "DisplayName", record.name)
	setAttribute(record, "HP", roundValue(record.hp))
	setAttribute(record, "MaxHP", roundValue(record.maxHp))
	setAttribute(record, "Gauge", roundValue(record.gauge))
	setAttribute(record, "MaxGauge", roundValue(record.maxGauge))
	setAttribute(record, "State", record.state)
	setAttribute(record, "Level", record.level)
	if record.kind == "Player" then
		setAttribute(record, "Cursor", "Green")
		setAttribute(record, "WeaponId", record.weaponId)
		setAttribute(record, "Drawn", dependencies().now() < record.combatUntil)
	end
end

-- A hit dealt or taken: HP regen waits from now and the combat tag runs from now.
local function markCombat(record: Record, now: number)
	record.lastCombatAt = now
	record.combatUntil = now + Combat.combatTagDuration
end

-- A combat action that is not a hit (an Art, a guard, a lock-on): the player's tag runs at least
-- combatTagDuration from now. HP regen is left alone. Enemies never carry the tag this way.
local function refreshTag(record: Record, now: number)
	if record.kind ~= "Player" then
		return
	end
	record.combatUntil = math.max(record.combatUntil, now + Combat.combatTagDuration)
end

-- True while the lock-on target is a live fighter.
local function hasLiveTarget(record: Record): boolean
	local targetId = record.targetId
	if targetId == nil then
		return false
	end
	local target = records[targetId]
	return target ~= nil and target.state ~= "Dead"
end

local function setHp(record: Record, value: number)
	local old = record.hp
	local new = math.clamp(value, 0, record.maxHp)
	if new == old then
		return
	end
	record.hp = new
	EntityService.HpChanged:Fire(record, old, new)
end

-- ------------------------------------------------------------------------------------------
-- Registry
-- ------------------------------------------------------------------------------------------

local function register(record: Record): number
	local d = dependencies()
	local existing = byModel[record.model]
	if existing ~= nil then
		EntityService.unregister(existing.id)
	end
	records[record.id] = record
	byModel[record.model] = record
	pinHumanoid(record, true)
	local humanoid = humanoidOf(record)
	if humanoid ~= nil then
		humanoid.BreakJointsOnDeath = false
	end
	publish(record)
	d.addTag(record.model, TAG_ENTITY)
	d.addTag(record.model, if record.kind == "Player" then TAG_PLAYER else TAG_ENEMY)
	EntityService.Registered:Fire(record)
	return record.id
end

local function baseRecord(kind: Kind, model: Model): Record
	if model.PrimaryPart == nil then
		error(("EntityService: %s has no PrimaryPart"):format(model:GetFullName()))
	end
	local now = dependencies().now()
	local id = nextId
	nextId += 1
	return {
		id = id,
		kind = kind,
		defId = PLAYER_DEF_ID,
		name = model.Name,
		model = model,
		rig = PLAYER_RIG,
		hp = 0,
		maxHp = 0,
		gauge = 0,
		maxGauge = 0,
		gaugeRegenPerSecond = Combat.guardRegenPerSecond,
		defense = 0,
		attack = 0,
		stats = { str = 0, agi = 0, level = 1 },
		state = "Idle",
		stateTag = nil,
		stateUntil = nil,
		lockUntil = now,
		guardHeld = false,
		guardSince = nil,
		guardReleasedAt = nil,
		hasShield = false,
		invulnerableUntil = now,
		combatUntil = now,
		lastCombatAt = nil,
		hpRegenHeld = nil,
		lastArtHitAt = nil,
		proficiency = {},
		weaponId = nil,
		threat = {},
		targetId = nil,
		player = nil,
		enemyDef = nil,
		shatter = "Humanoid",
		level = 1,
		killedBy = nil,
		diedAt = nil,
		artSlots = nil,
	}
end

--- Registers a player's character with its Playground loadout; returns the entity id.
function EntityService.registerPlayer(player: Player, character: Model, loadout: Types.Loadout): number
	-- A player has one live record: a previous character's record goes first.
	for _, previous in records do
		if previous.player == player then
			EntityService.unregister(previous.id)
		end
	end
	local record = baseRecord("Player", character)
	local weapon = Weapons.byId(loadout.weapon)
	local armorIds: { string } = {}
	if loadout.armor ~= nil then
		for _, armorId in loadout.armor :: { [string]: string } do
			table.insert(armorIds, armorId)
		end
	end
	local level = math.max(math.floor(loadout.level), 1)
	record.player = player
	record.name = player.DisplayName
	record.level = level
	record.stats = { str = loadout.str, agi = loadout.agi, level = level }
	record.maxHp = Combat.basePlayerHp + Combat.hpPerLevel * (level - 1)
	record.hp = record.maxHp
	record.maxGauge = Combat.playerGuardGaugeBase
	record.gauge = record.maxGauge
	record.defense = Armor.totals(armorIds).defense
	record.proficiency = table.clone(loadout.proficiency)
	record.weaponId = loadout.weapon
	record.attack = if weapon ~= nil then weapon.attack else 0
	record.hasShield = loadout.hasShield == true
	record.shatter = "Humanoid"
	if loadout.artSlots ~= nil then
		record.artSlots = table.clone(loadout.artSlots) -- the record's own copy: CombatService checks requests against it
		character:SetAttribute(ART_SLOTS_ATTRIBUTE, table.concat(loadout.artSlots, ","))
	end
	return register(record)
end

--- Registers an enemy model with its (already tier-scaled) def; returns the entity id.
function EntityService.registerEnemy(model: Model, enemyDef: Types.EnemyDef, options: EnemyOptions?): number
	local record = baseRecord("Enemy", model)
	local opts: EnemyOptions = options or {}
	record.defId = enemyDef.id
	record.name = opts.name or enemyDef.name
	record.rig = enemyDef.skin
	record.level = opts.level or enemyDef.floor
	record.stats = { str = 0, agi = 0, level = record.level }
	record.maxHp = enemyDef.hp
	record.hp = enemyDef.hp
	record.maxGauge = enemyDef.guardGauge
	record.gauge = enemyDef.guardGauge
	record.gaugeRegenPerSecond = enemyDef.guardRegenPerSecond
	record.defense = enemyDef.defense
	record.attack = enemyDef.attack
	record.enemyDef = enemyDef
	record.shatter = enemyDef.shatter
	record.hasShield = opts.hasShield == true
	return register(record)
end

--- Removes a fighter from the registry (tags cleared, Unregistered fired). The model is left alone.
function EntityService.unregister(id: number)
	local record = records[id]
	if record == nil then
		return
	end
	records[id] = nil
	published[id] = nil
	if byModel[record.model] == record then
		byModel[record.model] = nil
	end
	local d = dependencies()
	d.removeTag(record.model, TAG_ENTITY)
	d.removeTag(record.model, if record.kind == "Player" then TAG_PLAYER else TAG_ENEMY)
	EntityService.Unregistered:Fire(record)
end

--- The record with this id, or nil.
function EntityService.get(id: number): Record?
	return records[id]
end

--- The record whose Model this is, or nil.
function EntityService.fromModel(model: Instance): Record?
	return byModel[model]
end

--- The record owning this instance (a part of its model, an attachment, the model itself), or nil.
function EntityService.fromInstance(instance: Instance?): Record?
	local node = instance
	while node ~= nil do
		local record = byModel[node]
		if record ~= nil then
			return record
		end
		node = node.Parent
	end
	return nil
end

--- The live record of a player's current character, or nil.
function EntityService.fromPlayer(player: Player): Record?
	for _, record in records do
		if record.player == player then
			return record
		end
	end
	return nil
end

--- Every record, sorted by id.
function EntityService.all(): { Record }
	local list = {}
	for _, record in records do
		table.insert(list, record)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

local function ofKind(kind: Kind): { Record }
	local list = {}
	for _, record in EntityService.all() do
		if record.kind == kind then
			table.insert(list, record)
		end
	end
	return list
end

--- Every player record.
function EntityService.players(): { Record }
	return ofKind("Player")
end

--- Every enemy record.
function EntityService.enemies(): { Record }
	return ofKind("Enemy")
end

--- The nearest living fighter (of `kind` when given) within `radius` of a position, or nil.
function EntityService.nearest(position: Vector3, radius: number, kind: Kind?): Record?
	local best: Record? = nil
	local bestDistance = radius
	for _, record in records do
		if record.state == "Dead" or (kind ~= nil and record.kind ~= kind) then
			continue
		end
		local distance = (positionOf(record) - position).Magnitude
		if distance <= bestDistance then
			best = record
			bestDistance = distance
		end
	end
	return best
end

--- World position of a fighter's root (zero when it has none).
function EntityService.positionOf(id: number): Vector3?
	local record = records[id]
	if record == nil then
		return nil
	end
	return positionOf(record)
end

--- The fighter's root part.
function EntityService.rootOf(id: number): BasePart?
	local record = records[id]
	return if record ~= nil then rootOf(record) else nil
end

--- Horizontal look direction of a fighter's root, or nil.
function EntityService.lookVectorOf(id: number): Vector3?
	local root = EntityService.rootOf(id)
	if root == nil then
		return nil
	end
	return root.CFrame.LookVector
end

--- True while the fighter is alive and registered.
function EntityService.isAlive(id: number): boolean
	local record = records[id]
	return record ~= nil and record.state ~= "Dead"
end

--- True while a lock (Art, post-motion, stagger, dodge...) holds the body, allowing the request tolerance.
function EntityService.isLocked(id: number, now: number?): boolean
	local record = records[id]
	if record == nil then
		return false
	end
	local t = now or dependencies().now()
	return record.lockUntil - Combat.artRequestTolerance > t
end

-- ------------------------------------------------------------------------------------------
-- State
-- ------------------------------------------------------------------------------------------

--- Sets a fighter's state; `duration` makes it expire back to Idle on its own and locks the body
--- for that long; `direction` names the flinch clip; `tag` marks a variant ("Basic" under Art).
function EntityService.setState(id: number, state: State, duration: number?, direction: string?, tag: string?)
	local record = records[id]
	if record == nil then
		return
	end
	if record.state == "Dead" and state ~= "Dead" then
		return
	end
	local now = dependencies().now()
	local previous = record.state
	record.state = state
	record.stateTag = tag
	record.stateUntil = if duration ~= nil then now + duration else nil
	if LOCK_STATES[state] then
		record.guardHeld = false
		record.guardSince = nil
		record.lockUntil = if duration ~= nil then now + duration else record.lockUntil
		if state == "Dead" then
			record.stateUntil = nil
		end
	else
		record.lockUntil = now
	end
	if HOLD_STATES[state] then
		refreshTag(record, now)
	end
	publish(record)
	if previous == state and state == "Idle" and duration == nil then
		return
	end
	EntityService.StateChanged:Fire(record, state, duration, direction)
	fireAll("StateChanged", { entityId = id, state = state, duration = duration, direction = direction })
end

--- Pushes a timed state's end, and the lock it holds, `seconds` later without changing the state
--- and without a StateChanged: an enemy's attack paused by hit-stop (D-168; HitConfirmed carries the
--- pause to the clients). False for an unknown or dead fighter, an untimed state or a push of zero.
function EntityService.extendState(id: number, seconds: number): boolean
	local record = records[id]
	if record == nil or record.state == "Dead" or not (seconds > 0) then
		return false
	end
	local stateUntil = record.stateUntil
	if stateUntil == nil then
		return false
	end
	record.stateUntil = stateUntil + seconds
	if LOCK_STATES[record.state] then
		record.lockUntil += seconds
	end
	publish(record)
	return true
end

-- A timed state ran out: Break and GuardBroken refill the gauge; everything returns to Idle.
local function expireState(record: Record)
	if record.state == "Break" or record.state == "GuardBroken" then
		record.gauge = record.maxGauge
	end
	record.stateUntil = nil
	EntityService.setState(record.id, "Idle")
end

--- True when a guard can be raised from the fighter's current state (free, or cancelling a basic swing).
function EntityService.canGuard(id: number): boolean
	local record = records[id]
	if record == nil then
		return false
	end
	return FREE_STATES[record.state] == true or (record.state == "Art" and record.stateTag == "Basic")
end

--- Raises or lowers a guard; returns whether the request took effect. The parry window opens at
--- the raise unless the guard came back up inside parryRearmTime of its last release (tap spam
--- cannot fish for parries). A raise from a locked state is refused, never remembered. The guard
--- has no stored axis: CombatService.enemyStrike judges the cone against the root's look vector.
function EntityService.setGuard(id: number, held: boolean): boolean
	local record = records[id]
	if record == nil or record.state == "Dead" then
		return false
	end
	local now = dependencies().now()
	if held then
		if not EntityService.canGuard(id) then
			return false
		end
		if not record.guardHeld then
			local releasedAt = record.guardReleasedAt
			local rearmed = releasedAt == nil or now - releasedAt >= Combat.parryRearmTime
			record.guardSince = if rearmed then now else nil
		end
		record.guardHeld = true
		refreshTag(record, now)
		if record.state ~= "Guard" then
			EntityService.setState(id, "Guard")
		else
			publish(record)
		end
		return true
	end
	if record.guardHeld then
		record.guardReleasedAt = now
	end
	record.guardHeld = false
	record.guardSince = nil
	if record.state == "Guard" then
		EntityService.setState(id, "Idle")
	end
	return true
end

--- Grants invulnerability (dodge frames) until the given server time.
function EntityService.setInvulnerable(id: number, untilTime: number)
	local record = records[id]
	if record ~= nil then
		record.invulnerableUntil = math.max(record.invulnerableUntil, untilTime)
	end
end

--- True while dodge frames protect the fighter.
function EntityService.isInvulnerable(id: number, now: number?): boolean
	local record = records[id]
	if record == nil then
		return false
	end
	return (now or dependencies().now()) < record.invulnerableUntil
end

--- Stores the lock-on target (nil clears it); the target must be a registered fighter. A lock-on
--- refreshes a player's combat tag (the sword comes out); clearing it lets the tag run out.
function EntityService.setTarget(id: number, targetId: number?): boolean
	local record = records[id]
	if record == nil then
		return false
	end
	if targetId ~= nil and records[targetId] == nil then
		return false
	end
	record.targetId = targetId
	if targetId ~= nil then
		refreshTag(record, dependencies().now())
		publish(record)
	end
	return true
end

--- Changes a player's equipped weapon: attack and the WeaponId attribute follow.
function EntityService.setWeapon(id: number, weaponId: string?)
	local record = records[id]
	if record == nil then
		return
	end
	record.weaponId = weaponId
	local weapon = if weaponId ~= nil then Weapons.byId(weaponId) else nil
	if record.kind == "Player" then
		record.attack = if weapon ~= nil then weapon.attack else 0
	end
	publish(record)
end

--- Marks a fighter as in combat now (HP regen waits, the combat tag refreshes) and publishes it.
function EntityService.markCombat(id: number)
	local record = records[id]
	if record ~= nil then
		markCombat(record, dependencies().now())
		publish(record)
	end
end

--- True while the combat tag holds (for a player: while its sword is drawn).
function EntityService.inCombat(id: number, now: number?): boolean
	local record = records[id]
	if record == nil then
		return false
	end
	return (now or dependencies().now()) < record.combatUntil
end

-- ------------------------------------------------------------------------------------------
-- Threat
-- ------------------------------------------------------------------------------------------

--- Adds threat toward `attackerId` on an enemy (damage x1, taunt x3, healing x0.5 by the caller).
function EntityService.addThreat(id: number, attackerId: number, amount: number)
	local record = records[id]
	if record == nil or amount <= 0 then
		return
	end
	record.threat[attackerId] = (record.threat[attackerId] or 0) + amount
end

--- A copy of an enemy's threat table.
function EntityService.threatOf(id: number): { [number]: number }
	local record = records[id]
	return if record ~= nil then table.clone(record.threat) else {}
end

--- The living attacker with the most threat on this fighter, or nil.
function EntityService.topThreat(id: number): number?
	local record = records[id]
	if record == nil then
		return nil
	end
	local best: number? = nil
	local bestValue = 0
	for attackerId, value in record.threat do
		local attacker = records[attackerId]
		if attacker ~= nil and attacker.state ~= "Dead" and value > bestValue then
			best = attackerId
			bestValue = value
		end
	end
	return best
end

--- Forgets one attacker's threat (it died or left); threat tables never hold stale ids for long.
function EntityService.clearThreat(id: number, attackerId: number)
	local record = records[id]
	if record ~= nil then
		record.threat[attackerId] = nil
	end
end

-- ------------------------------------------------------------------------------------------
-- Hits and death
-- ------------------------------------------------------------------------------------------

--- Kills a fighter: Dead state, EntityDied to every client, Died signal. Cleanup runs from tick.
function EntityService.die(id: number, killerId: number?)
	local record = records[id]
	if record == nil or record.state == "Dead" then
		return
	end
	local now = dependencies().now()
	setHp(record, 0)
	record.killedBy = killerId
	record.diedAt = now
	record.gauge = 0
	EntityService.setState(id, "Dead")
	local killer = if killerId ~= nil then records[killerId] else nil
	for _, other in records do
		other.threat[id] = nil
	end
	fireAll("EntityDied", {
		entityId = id,
		shatter = record.shatter,
		position = toVec3(positionOf(record)),
		name = record.name,
		byPlayer = killer ~= nil and killer.kind == "Player",
	})
	EntityService.Died:Fire(record, killerId)
end

local function zeroHit(target: Record, hit: Types.HitRequest): Types.AppliedHit
	return {
		attackerId = hit.attackerId,
		targetId = target.id,
		damage = 0,
		hpRemoved = 0,
		crit = false,
		gaugeDamage = 0,
		killed = false,
		broke = false,
		hitStop = hit.hitStop,
		position = hit.position,
		parried = hit.parried,
		guarded = false,
		reflected = false,
		artId = hit.artId,
		hitIndex = hit.hitIndex,
		wasInBreak = target.state == "Break",
		hpAfter = target.hp,
		gaugeAfter = target.gauge,
		staggerDirection = nil,
	}
end

--- Applies a hit the caller already resolved on the attack side (raw damage, guard / parry flags):
--- defense, Break doubling, gauge damage with the Break / guard-break transition, threat, the combat
--- tag, death. Returns what landed; `wasInBreak` tells the Art timeline to skip its post-motion.
function EntityService.applyHit(targetId: number, hit: Types.HitRequest): Types.AppliedHit
	local target = records[targetId]
	if target == nil then
		error(("EntityService.applyHit: no entity %d"):format(targetId))
	end
	local now = dependencies().now()
	local attacker = records[hit.attackerId]
	local wasInBreak = target.state == "Break"
	local result = zeroHit(target, hit)

	if target.state == "Dead" then
		return result
	end
	markCombat(target, now)
	if attacker ~= nil then
		markCombat(attacker, now)
		publish(attacker)
	end

	local attackerPosition = if attacker ~= nil then positionOf(attacker) else nil
	local root = rootOf(target)
	if attackerPosition ~= nil and root ~= nil then
		result.staggerDirection = DamageMath.staggerDirection(attackerPosition, root.CFrame)
	end

	if hit.parried then
		result.parried = true
		publish(target)
		return result
	end

	-- Damage: defense, guard reduction, Break doubling, floored at the minimum.
	local damage = DamageMath.resolve(
		hit.rawDamage,
		target.defense,
		{ inBreak = wasInBreak, guarded = hit.guarded, hasShield = target.hasShield }
	)
	result.damage = damage
	result.crit = hit.crit
	result.guarded = hit.guarded

	-- Gauge: Arts drain it; basics a tenth (already folded into hit.gaugeDamage); a guard drains the
	-- guarding player's own gauge; a GuardBreak telegraph empties it outright. No drain while Broken.
	local gaugeDamage = if hit.guarded then DamageMath.guardDrain(hit.gaugeDamage) else hit.gaugeDamage
	if hit.breakGuard then
		gaugeDamage = math.max(gaugeDamage, target.gauge)
	end
	local broke = false
	if gaugeDamage > 0 and target.state ~= "Break" and target.state ~= "GuardBroken" then
		target.gauge = math.max(0, target.gauge - gaugeDamage)
		if not hit.isBasic then
			target.lastArtHitAt = now
		end
		broke = target.gauge <= 0
		result.gaugeDamage = gaugeDamage
	end

	-- What the HP bar loses (FK5): all of the damage, or only the HP that was left when it kills.
	result.hpRemoved = math.min(damage, target.hp)
	setHp(target, target.hp - damage)
	if target.kind == "Enemy" and attacker ~= nil then
		EntityService.addThreat(target.id, attacker.id, damage * Combat.threatPerDamage)
	end

	local killed = target.hp <= 0
	result.killed = killed
	result.broke = broke
	result.hitStop = if killed then "Kill" else hit.hitStop
	result.hpAfter = target.hp
	result.gaugeAfter = target.gauge

	if killed then
		EntityService.die(target.id, hit.attackerId)
	elseif broke then
		if target.kind == "Enemy" then
			EntityService.setState(target.id, "Break", Combat.breakDuration)
		else
			EntityService.setState(target.id, "GuardBroken", Combat.guardBreakStagger)
		end
		EntityService.Broke:Fire(target)
	else
		publish(target)
	end
	return result
end

--- Heals a living fighter by a flat amount (potions, Mend Shards).
function EntityService.heal(id: number, amount: number)
	local record = records[id]
	if record == nil or record.state == "Dead" or amount <= 0 then
		return
	end
	setHp(record, record.hp + amount)
	publish(record)
end

--- Dev and GM only (the Studio dev hook, D-121; never a remote or a gameplay rule): sets a living
--- fighter's HP to `hp` clamped to [1, maxHp] and publishes it as heal does. It never kills (a
--- death only comes from a hit) and never revives. It restarts the out-of-combat regen wait
--- (combat.outOfCombatRegenDelay), and an enemy held through EnemyService.setHeld never
--- regenerates (setHpRegenHeld), so a low value waits for the hit it is set up for. It draws no
--- sword. Returns the HP the fighter has now, or nil for an unknown or dead id or a NaN.
function EntityService.setHp(id: number, hp: number): number?
	local record = records[id]
	if record == nil or record.state == "Dead" or hp ~= hp then
		return nil
	end
	record.lastCombatAt = dependencies().now()
	setHp(record, math.clamp(hp, math.min(1, record.maxHp), record.maxHp))
	publish(record)
	return record.hp
end

--- The hold's half in here (EnemyService.setHeld, D-120): true stops a living fighter's HP regen
--- until false (the Guard Gauge still refills), so a low HP set up for a hit waits for it however
--- long the tester takes. Hits, heal, setHp and death are untouched. Returns false for an unknown
--- or dead id.
function EntityService.setHpRegenHeld(id: number, held: boolean): boolean
	local record = records[id]
	if record == nil or record.state == "Dead" then
		return false
	end
	record.hpRegenHeld = if held then true else nil
	return true
end

-- ------------------------------------------------------------------------------------------
-- The loop
-- ------------------------------------------------------------------------------------------

local function stepDead(record: Record, now: number)
	local diedAt = record.diedAt
	if diedAt == nil then
		return
	end
	if record.kind == "Enemy" then
		if now - diedAt >= Combat.corpseRemoveDelay then
			local model = record.model
			EntityService.unregister(record.id)
			model:Destroy()
		end
	else
		if now - diedAt >= Combat.respawnDelay then
			local player = record.player
			EntityService.unregister(record.id)
			if player ~= nil then
				dependencies().respawn(player)
			end
		end
	end
end

local function stepAlive(record: Record, dt: number, now: number)
	local stateUntil = record.stateUntil
	if stateUntil ~= nil and now >= stateUntil then
		expireState(record)
	end

	-- Guard Gauge regen: 10%/s (the def's rate for enemies) once no Art has hit for guardRegenDelay.
	if record.state ~= "Break" and record.state ~= "GuardBroken" and record.gauge < record.maxGauge then
		local lastArtHitAt = record.lastArtHitAt
		if lastArtHitAt == nil or now - lastArtHitAt >= Combat.guardRegenDelay then
			record.gauge = math.min(record.maxGauge, record.gauge + record.maxGauge * record.gaugeRegenPerSecond * dt)
		end
	end

	-- HP never regenerates in combat: 1%/s after outOfCombatRegenDelay since the last hit dealt or
	-- taken. A held fighter (D-120) never regenerates.
	if record.hp < record.maxHp and not record.hpRegenHeld then
		local lastCombatAt = record.lastCombatAt
		if lastCombatAt == nil or now - lastCombatAt >= Combat.outOfCombatRegenDelay then
			setHp(record, record.hp + record.maxHp * Combat.outOfCombatRegenPerSecond * dt)
		end
	end

	-- A held Art, post-motion or guard, or a live lock-on, keeps a player's sword out.
	if HOLD_STATES[record.state] or hasLiveTarget(record) then
		refreshTag(record, now)
	end

	pinHumanoid(record)
	publish(record)
end

--- One step of the service: players every call, enemies at combat.enemyTickHz. Heartbeat calls it
--- with the frame's dt; tests call it by hand with a manual clock.
function EntityService.tick(dt: number)
	local now = dependencies().now()
	enemyAccumulator += dt
	local enemyStep = 1 / Combat.enemyTickHz
	local stepEnemies = enemyAccumulator >= enemyStep
	local enemyDt = enemyAccumulator
	if stepEnemies then
		enemyAccumulator = 0
	end
	for _, record in EntityService.all() do
		if records[record.id] == nil then
			continue
		end
		if record.kind == "Player" then
			if record.state == "Dead" then
				stepDead(record, now)
			else
				stepAlive(record, dt, now)
			end
		elseif stepEnemies then
			if record.state == "Dead" then
				stepDead(record, now)
			else
				stepAlive(record, enemyDt, now)
			end
		end
	end
end

--- Starts the service on the engine: Heartbeat loop, player cleanup. Safe to call once.
function EntityService.start()
	if started then
		return
	end
	started = true
	if deps == nil then
		deps = engineDeps()
	end
	local d = dependencies()
	if d.heartbeat ~= nil then
		heartbeatConnection = d.heartbeat(EntityService.tick)
	end
	if d.playerRemoving ~= nil then
		d.playerRemoving(function(player)
			for _, record in EntityService.all() do
				if record.player == player then
					EntityService.unregister(record.id)
				end
			end
		end)
	end
end

--- Stops the loop and forgets every record (tests).
function EntityService.reset()
	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	for _, record in EntityService.all() do
		EntityService.unregister(record.id)
	end
	table.clear(records)
	table.clear(byModel)
	table.clear(published)
	nextId = 1
	enemyAccumulator = 0
	started = false
	warnedNoNet = false
end

return EntityService
