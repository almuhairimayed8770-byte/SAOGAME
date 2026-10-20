--!strict
--[[
	AntiCheatService (section 17): speed and teleport checks on every player's HumanoidRootPart,
	plus the Net layer's abuse reports, folded into one sliding anomaly window per player.

	Every combat.anticheatSampleInterval seconds (stepped from Heartbeat, never task.wait) the service
	reads a watched player's root position through EntityService and judges the horizontal distance
	since the last sample against Rules.allowedDistance: the sprint cap times combat.speedMargin over
	the interval (D-052), plus the running Art's rootMotion and combat.rootMotionSlack mid-Art
	(CombatService.currentArt says which Art; without CombatService the weapon category's largest
	Art is assumed), plus combat.dodgeDistance mid-Dodge, plus the player's lag credit. The interval
	before a sample is covered by whichever of the previous and current states is more permissive,
	so an Art that ends between samples is not punished. The lag credit is the combat.lagAllowance budget spent once,
	not per sample (Rules.maxCredit / Rules.nextCredit): it starts full, a sample that travels past
	its allowance without credit spends it, a sample that travels less refills it, so replication
	jitter never flags an honest sprinter while a sustained walk over the cap is flagged within a
	few samples. A character without a root (reset, removed, respawning) is not judged: the sample
	resets (and the credit refills) rather than reading the origin as a teleport. A delta beyond
	combat.teleportFlagDistance is a teleport anomaly weighted by the distances it spans; anything
	else over the allowance is an over-speed anomaly. Net.server().abuse (rate limits, schema
	failures) adds an anomaly per report.

	Anomalies live combat.anomalyWindow seconds. At world.anticheat.shadowFraction of
	combat.anomalyKickThreshold the player gets the attribute world.anticheat.shadowAttribute = true
	(the shadow flag; Trial-server routing is a later phase). At the threshold, and never for a
	single anomaly, the player receives a SystemLine and is kicked. Every flag is logged with the
	player's UserId and the reason.

	The service only reads EntityService and CombatService; it never writes HP or positions.
	Everything engine-facing comes through `Deps` (bind), so it runs under Lune with fakes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Combat = require(Shared.data.combat)
local World = require(Shared.data.world)
local Signal = require(Shared.util.Signal)
local Rules = require(script.Parent.Parent.anticheat.Rules)

export type Connection = { Disconnect: (self: any) -> () }

export type Deps = {
	now: () -> number, -- server time
	entities: any, -- EntityService (fromPlayer, positionOf, players, Registered, Unregistered)
	combat: any?, -- CombatService (currentArt); nil assumes the weapon category's largest Art
	net: any?, -- Net.server(): abuse Signal and fire("SystemLine"); nil in tests
	players: any?, -- Players service (PlayerRemoving); nil in tests
	heartbeat: ((handler: (dt: number) -> ()) -> Connection?)?,
	setAttribute: (player: Player, name: string, value: any) -> (),
	kick: (player: Player, text: string) -> (),
	log: ((message: string) -> ())?,
}

export type Stats = {
	watched: number,
	samples: number,
	flags: number,
	speed: number,
	teleport: number,
	abuse: number,
	shadowed: number,
	kicked: number,
}

type Entry = {
	player: Player,
	model: Model?, -- the character sampled last; a new one resets the sample
	lastPosition: Vector3?,
	lastState: string,
	lastMotion: number?,
	credit: number, -- studs of lag credit left (Rules.maxCredit when full)
	elapsed: number, -- seconds since the last sample
	flags: { Rules.Flag },
	shadowed: boolean,
	kicked: boolean,
}

local KIND_SPEED = "speed"
local KIND_TELEPORT = "teleport"
local KIND_ABUSE = "abuse"
local STATE_DEAD = "Dead"
local STATE_IDLE = "Idle"
local KIND_PLAYER = "Player"
local SYSTEM_LINE = "SystemLine"
local LOG_PREFIX = "[AntiCheat]"

local AntiCheatService = {}

--- Fires (player, reason, weight) for every anomaly recorded.
AntiCheatService.Flagged = Signal.new() :: Signal.Signal<Player, string, number>
--- Fires (player) once when a player crosses world.anticheat.shadowFraction of the kick threshold
--- and is shadow-flagged.
AntiCheatService.Shadowed = Signal.new() :: Signal.Signal<Player>
--- Fires (player, reason) when a player is kicked; the reason is the anomaly that tipped the window.
AntiCheatService.Kicked = Signal.new() :: Signal.Signal<Player, string>

local deps: Deps? = nil
local entries: { [Player]: Entry } = {}
local connections: { Connection } = {}
local heartbeatConnection: Connection? = nil
local started = false
local stats: Stats = {
	watched = 0,
	samples = 0,
	flags = 0,
	speed = 0,
	teleport = 0,
	abuse = 0,
	shadowed = 0,
	kicked = 0,
}

local function dependencies(): Deps
	if deps == nil then
		error("AntiCheatService: call start() or bind() first")
	end
	return deps :: Deps
end

local function log(message: string)
	local d = dependencies()
	if d.log ~= nil then
		d.log(LOG_PREFIX .. " " .. message)
	end
end

local function userIdOf(player: Player): number
	local userId = (player :: any).UserId
	return if typeof(userId) == "number" then userId else 0
end

-- ---------------------------------------------------------------------------------------------
-- Watching
-- ---------------------------------------------------------------------------------------------

local function newEntry(player: Player): Entry
	return {
		player = player,
		model = nil,
		lastPosition = nil,
		lastState = STATE_IDLE,
		lastMotion = nil,
		credit = Rules.maxCredit(Combat),
		elapsed = 0,
		flags = {},
		shadowed = false,
		kicked = false,
	}
end

--- Starts (or keeps) watching a player; the next sample only records a position. Returns the entry's flags.
function AntiCheatService.watch(player: Player): { Rules.Flag }
	local entry = entries[player]
	if entry == nil then
		entry = newEntry(player)
		entries[player] = entry
		stats.watched += 1
	end
	return entry.flags
end

--- Stops watching a player and forgets their flags (they left the server).
function AntiCheatService.forget(player: Player)
	if entries[player] ~= nil then
		entries[player] = nil
		stats.watched -= 1
	end
end

--- True while the player is watched.
function AntiCheatService.isWatched(player: Player): boolean
	return entries[player] ~= nil
end

--- A copy of the player's anomalies still inside the window.
function AntiCheatService.flagsOf(player: Player): { Rules.Flag }
	local entry = entries[player]
	if entry == nil then
		return {}
	end
	Rules.prune(entry.flags, dependencies().now(), Combat)
	return table.clone(entry.flags)
end

--- True once the player has been shadow-flagged this session.
function AntiCheatService.isShadowed(player: Player): boolean
	local entry = entries[player]
	return entry ~= nil and entry.shadowed
end

--- True once the player has been kicked by this service.
function AntiCheatService.isKicked(player: Player): boolean
	local entry = entries[player]
	return entry ~= nil and entry.kicked
end

-- The sample forgets where the character was (death, respawn, a new character, no root); the
-- next reading starts fresh, so the lag credit is full again.
local function resetSample(entry: Entry)
	entry.lastPosition = nil
	entry.lastState = STATE_IDLE
	entry.lastMotion = nil
	entry.credit = Rules.maxCredit(Combat)
end

-- ---------------------------------------------------------------------------------------------
-- Flags, the shadow flag and the kick
-- ---------------------------------------------------------------------------------------------

local function shadow(entry: Entry)
	local d = dependencies()
	entry.shadowed = true
	stats.shadowed += 1
	local ok, err = pcall(d.setAttribute, entry.player, World.anticheat.shadowAttribute, true)
	if not ok then
		warn(("%s userId=%d shadow attribute failed: %s"):format(LOG_PREFIX, userIdOf(entry.player), tostring(err)))
	end
	warn(
		("%s userId=%d shadow-flagged at window weight %d"):format(
			LOG_PREFIX,
			userIdOf(entry.player),
			Rules.weight(entry.flags, d.now(), Combat)
		)
	)
	AntiCheatService.Shadowed:Fire(entry.player)
end

local function kick(entry: Entry, reason: string)
	local d = dependencies()
	entry.kicked = true
	stats.kicked += 1
	local policy = World.anticheat
	warn(
		("%s userId=%d kicked: %d anomalies, window weight %d, last: %s"):format(
			LOG_PREFIX,
			userIdOf(entry.player),
			Rules.count(entry.flags, d.now(), Combat),
			Rules.weight(entry.flags, d.now(), Combat),
			reason
		)
	)
	local net = d.net
	if net ~= nil and net.fire ~= nil then
		local ok, err = pcall(net.fire, SYSTEM_LINE, entry.player, { text = policy.kickText, token = policy.lineToken })
		if not ok then
			warn(("%s userId=%d system line failed: %s"):format(LOG_PREFIX, userIdOf(entry.player), tostring(err)))
		end
	end
	local ok, err = pcall(d.kick, entry.player, policy.kickText)
	if not ok then
		warn(("%s userId=%d kick failed: %s"):format(LOG_PREFIX, userIdOf(entry.player), tostring(err)))
	end
	AntiCheatService.Kicked:Fire(entry.player, reason)
end

--- Records one anomaly against a player (watching them if needed), then applies the shadow flag
--- and the kick policy. `kind` is one of world.anticheat.reasons for the counters.
function AntiCheatService.flag(player: Player, reason: string, weight: number, kind: string?)
	local d = dependencies()
	AntiCheatService.watch(player)
	local entry = entries[player] :: Entry
	if entry.kicked then
		return
	end
	local now = d.now()
	table.insert(entry.flags, { at = now, weight = weight, reason = reason })
	Rules.prune(entry.flags, now, Combat)
	stats.flags += 1
	if kind == KIND_SPEED then
		stats.speed += 1
	elseif kind == KIND_TELEPORT then
		stats.teleport += 1
	elseif kind == KIND_ABUSE then
		stats.abuse += 1
	end
	log(
		("userId=%d flagged (weight %d, window %d/%d): %s"):format(
			userIdOf(player),
			weight,
			Rules.weight(entry.flags, now, Combat),
			Combat.anomalyKickThreshold,
			reason
		)
	)
	AntiCheatService.Flagged:Fire(player, reason, weight)
	if not entry.shadowed and Rules.shouldShadow(entry.flags, now, Combat) then
		shadow(entry)
	end
	if Rules.shouldKick(entry.flags, now, Combat) then
		kick(entry, reason)
	end
end

--- Net reported a client misbehaving (rate limit or schema failure): one abuse anomaly.
function AntiCheatService.reportAbuse(player: Player, remoteName: string, reason: string)
	local reasons = World.anticheat.reasons
	AntiCheatService.flag(
		player,
		("%s: %s %s"):format(reasons.abuse, tostring(remoteName), tostring(reason)),
		World.anticheat.abuseWeight,
		KIND_ABUSE
	)
end

-- ---------------------------------------------------------------------------------------------
-- Sampling
-- ---------------------------------------------------------------------------------------------

-- The running Art's rootMotion from CombatService (0 for a basic swing), or nil when it cannot say.
local function artMotion(entityId: number): number?
	local combatService = dependencies().combat
	if combatService == nil or combatService.currentArt == nil then
		return nil
	end
	local ok, art = pcall(combatService.currentArt, entityId)
	if not ok then
		return nil
	end
	if art == nil then
		return 0
	end
	return art.rootMotion
end

--- Judges one player's movement over `interval` seconds; returns the verdict, or nil when nothing was judged.
function AntiCheatService.sample(player: Player, interval: number): Rules.Verdict?
	local d = dependencies()
	local entry = entries[player]
	if entry == nil or entry.kicked then
		return nil
	end
	local record = d.entities.fromPlayer(player)
	if record == nil or record.kind ~= KIND_PLAYER or record.state == STATE_DEAD then
		resetSample(entry)
		return nil
	end
	if record.model ~= entry.model then
		entry.model = record.model
		resetSample(entry)
	end
	-- EntityService.positionOf answers the origin, not nil, for a model without a root; a character
	-- that was reset or removed while its record lives must not read as a teleport to (0, 0).
	local model = record.model
	local root = model.PrimaryPart
	if root == nil or root.Parent == nil or model.Parent == nil then
		resetSample(entry)
		return nil
	end
	local position = d.entities.positionOf(record.id)
	if position == nil then
		resetSample(entry)
		return nil
	end
	local motion = artMotion(record.id)
	local verdict: Rules.Verdict? = nil
	local last = entry.lastPosition
	if last ~= nil then
		local delta = Rules.horizontalDistance(last, position)
		local allowedNow = Rules.allowedDistance(interval, record, Combat, motion)
		local allowedBefore = Rules.allowedDistance(
			interval,
			{ state = entry.lastState, weaponId = record.weaponId },
			Combat,
			entry.lastMotion
		)
		-- The allowance without credit (Art or Dodge grant included) both judges and refills.
		local base = math.max(allowedNow, allowedBefore)
		verdict = Rules.evaluate(delta, base + entry.credit, Combat)
		entry.credit = Rules.nextCredit(entry.credit, base, delta, Combat)
		stats.samples += 1
		if (verdict :: Rules.Verdict).kind ~= "ok" then
			local v = verdict :: Rules.Verdict
			AntiCheatService.flag(player, v.reason, v.weight, v.kind)
		end
	end
	entry.lastPosition = position
	entry.lastState = record.state
	entry.lastMotion = motion
	return verdict
end

--- Advances every watched player's sample clock by `dt` seconds and samples those that are due.
function AntiCheatService.tick(dt: number)
	local interval = Combat.anticheatSampleInterval
	for player, entry in entries do
		entry.elapsed += dt
		if entry.elapsed >= interval then
			local elapsed = entry.elapsed
			entry.elapsed = 0
			local ok, err = pcall(AntiCheatService.sample, player, elapsed)
			if not ok then
				warn(("%s userId=%d sample failed: %s"):format(LOG_PREFIX, userIdOf(player), tostring(err)))
			end
		end
	end
end

--- Counters for smoke tests and the dev overlay (a copy).
function AntiCheatService.stats(): Stats
	return table.clone(stats)
end

-- ---------------------------------------------------------------------------------------------
-- Engine seam
-- ---------------------------------------------------------------------------------------------

-- A sibling module that may not have landed yet: nil (with a warning) instead of an error.
local function sibling(parent: Instance?, name: string): any
	local node = if parent ~= nil then parent:FindFirstChild(name) else nil
	if node == nil or not node:IsA("ModuleScript") then
		warn(("%s %s is not available yet"):format(LOG_PREFIX, name))
		return nil
	end
	local ok, result = pcall(require, node :: ModuleScript)
	if not ok then
		warn(("%s %s failed to load: %s"):format(LOG_PREFIX, name, tostring(result)))
		return nil
	end
	return result
end

--- The real engine dependencies, with any field replaced by `overrides`.
function AntiCheatService.defaultDeps(overrides: { [string]: any }?): Deps
	local RunService = game:GetService("RunService")
	local Players = game:GetService("Players")
	local entities = sibling(script.Parent, "EntityService")
	if entities == nil then
		error("AntiCheatService: EntityService is required")
	end
	local netOk, net = pcall(function()
		local Net = require(Shared.net.Net)
		return Net.server()
	end)
	if not netOk then
		warn(("%s Net.server() is not available: %s"):format(LOG_PREFIX, tostring(net)))
		net = nil
	end
	local result: { [string]: any } = {
		now = function()
			return workspace:GetServerTimeNow()
		end,
		entities = entities,
		combat = sibling(script.Parent, "CombatService"),
		net = net,
		players = Players,
		heartbeat = function(handler)
			return RunService.Heartbeat:Connect(handler)
		end,
		setAttribute = function(player, name, value)
			player:SetAttribute(name, value)
		end,
		kick = function(player, text)
			-- The system line goes out first; the kick follows once the client has shown it.
			task.delay(World.anticheat.kickDelay, function()
				local ok, err = pcall(function()
					(player :: any):Kick(text)
				end)
				if not ok then
					warn(("%s userId=%d Kick failed: %s"):format(LOG_PREFIX, userIdOf(player), tostring(err)))
				end
			end)
		end,
		log = print,
	}
	if overrides ~= nil then
		for key, value in overrides do
			result[key] = value
		end
	end
	return result :: any
end

local function wire()
	local d = dependencies()
	local entities = d.entities
	if entities.Registered ~= nil then
		table.insert(
			connections,
			entities.Registered:Connect(function(record)
				if record.kind == KIND_PLAYER and record.player ~= nil then
					AntiCheatService.watch(record.player)
				end
			end)
		)
	end
	if entities.Unregistered ~= nil then
		table.insert(
			connections,
			entities.Unregistered:Connect(function(record)
				local entry = if record.player ~= nil then entries[record.player] else nil
				if entry ~= nil then
					resetSample(entry) -- the flags stay: the player is still here
				end
			end)
		)
	end
	local net = d.net
	if net ~= nil and net.abuse ~= nil then
		table.insert(
			connections,
			net.abuse:Connect(function(player, remoteName, reason)
				AntiCheatService.reportAbuse(player, remoteName, reason)
			end)
		)
	end
	local players = d.players
	if players ~= nil then
		table.insert(connections, players.PlayerRemoving:Connect(AntiCheatService.forget))
	end
end

--- Installs dependencies (engine or fakes) and connects the registry, Net abuse and PlayerRemoving; no loop yet.
function AntiCheatService.bind(newDeps: Deps)
	AntiCheatService.reset()
	deps = newDeps
	wire()
end

--- Starts the service: watches every registered player and steps the sampler from Heartbeat.
function AntiCheatService.start()
	if started then
		return
	end
	started = true
	if deps == nil then
		AntiCheatService.bind(AntiCheatService.defaultDeps())
	end
	local d = dependencies()
	if d.entities.players ~= nil then
		for _, record in d.entities.players() do
			if record.player ~= nil then
				AntiCheatService.watch(record.player)
			end
		end
	end
	if d.heartbeat ~= nil then
		heartbeatConnection = d.heartbeat(AntiCheatService.tick)
	end
end

--- Stops the loop and forgets every player, flag and connection (tests, and re-binding).
function AntiCheatService.reset()
	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(entries)
	for key in stats do
		(stats :: any)[key] = 0
	end
	started = false
end

return AntiCheatService
