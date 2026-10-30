--!strict
--[[
	DevCombat: the Studio combat hook (D-114, D-120, D-121). Runs only in Studio (RunService:IsStudio()) in
	a place whose Workspace carries the DevCapture attribute (places/Playground.project.json);
	anywhere else it returns before it requires a service or makes an instance.

	A Studio MCP execute_luau in the Server context gets a fresh copy of any module it requires, so
	it cannot set the live CombatService's traceSink. This Script can: it puts a BindableFunction
	(data/dev.luau trace.bindableName) under ServerScriptService, and `:Invoke(command, args)` runs
	the command here, inside the game's module cache:

		"help"                         the command list
		"trace" { on }                 on (the default) sets CombatService.traceSink: one compact Output
		                               line per closed damage window of a player's run (the run's
		                               facing, the root's turn off it, the hits, the nearest enemy's
		                               distance, bearing and blade clearance) and the newest
		                               trace.keepEvents kept for "events"; off gives the sink back
		"events" { count?, clear? }    the kept events (plain tables), newest last
		"basic" { entityId?, facing? } CombatService.beginBasic on the live service, then the run's
		                               windows as the trace saw them, its hits, and the enemies whose
		                               HP changed; entityId defaults to the first player's entity,
		                               facing (a Vector3 or {x, y, z}) to the root's look
		"art" { entityId?, artId?, facing? }
		                               the same through CombatService.beginArt; artId defaults to the
		                               entity's first Art slot (the playground loadout's)
		"hp"                           every enemy: id, name, HP, State, whether it is held, flat
		                               distance and bearing from the first player's root
		"hold" { ids?, except?, all?, on? }
		                               EnemyService.setHeld on (the default) or off for the listed
		                               enemy ids (a number or a list), or for every enemy except the
		                               listed ones (every enemy with neither); all = true also sets
		                               EnemyService.setHoldNew(on), so enemies spawned later
		                               (respawns too) start held, and on = false with all releases
		                               everything and stops it. A held enemy stands still, never
		                               attacks and never regenerates HP; hits, staggers and kills
		                               land on it as ever. Replies
		                               the held ids now, hold-new, the ids that changed and the ids
		                               that are no living enemy (missing)
		"sethp" { entityId, hp }       EntityService.setHp on an enemy or a player: HP clamped to
		                               [1, maxHp], never a kill; the regen wait restarts, and a held
		                               enemy never regenerates, so on one the value holds until the
		                               hit however long it takes; replies before and after
		"heal" { entityId? }           full HP through EntityService.heal; entityId defaults to the
		                               first player's entity; replies before and after
		"place" { position, facing?, entityId? | player? }
		                               the safe dev teleport (D-143): pivots a living player's
		                               character so its root stands at position (a Vector3 or
		                               {x, y, z}, each axis within dev.luau place.maxCoordinate)
		                               facing `facing` degrees (0 looks along -Z, + turns left; the
		                               root's own facing when absent), and first tells the
		                               anti-cheat the move is the server's own
		                               (AntiCheatService.serverMoved for place.settleSeconds), so
		                               neither the jump nor the client's positions from before it
		                               count; entityId (a player's entity) or player (a Name or
		                               UserId) picks the player, the first player by default;
		                               replies from, to and facing
		"place" { ..., onWindUp, after? }
		                               the same move timed on an enemy's beat (302(b)): waits on
		                               Heartbeat for the next wind-up that enemy (an entity id)
		                               starts, then moves the player `after` seconds into it (0 by
		                               default, at most hooks.maxPlaceAfterSeconds) and tells the
		                               anti-cheat on that frame; gives up with no move when no
		                               wind-up starts within hooks.windUpWaitSeconds; replies
		                               windUpAt and movedAt (seconds after the call)

	The Studio test hooks (D-333; numbers in dev.luau hooks) put enemies and plain parts where a
	check needs them, so it needs no hand-built scene. Every point is a Vector3 or {x, y, z}, each
	axis within place.maxCoordinate; an enemy's points are floor points (y is the top of the ground
	it stands on: its root goes its rig's root height above, as a spawn's does):
		"enemy" { entityId, position, facing?, hold? }
		                               EnemyService.place: drops whatever the living enemy was doing
		                               (as a hold does), pivots its body to stand on position facing
		                               `facing` degrees (its own facing when absent) and makes that
		                               its home; hold = true leaves it held, otherwise its brain
		                               starts afresh in Idle under every server rule; replies from,
		                               to (the root) and facing
		"walk" { entityId, toward, hold?, wait? }
		                               EnemyService.walk: walks the enemy to toward at its own pace
		                               (its def's moveSpeed) and turn rate through the mover, its room
		                               to the other enemies kept; its brain decides nothing until it
		                               stands within hooks.arriveStuds of the point (or
		                               hooks.walkTimeoutSeconds pass, or a hit staggers it), then
		                               takes over there, held when hold = true; at most
		                               hooks.maxWalkStuds; wait = true replies once it is over
		"charge" { entityId, toward }  EnemyService.charge: a Charger faces toward at once and starts
		                               its rush through Charger's normal path (the crouch, telegraph
		                               and clip, the launch, the contact sweep, the glance, clip,
		                               slam and jam stops, the daze); waits up to
		                               hooks.chargeTimeoutSeconds for the wind-up and the run, then
		                               replies the launch and every stop told for it (reason,
		                               distance down the path, seconds after the launch)
		"part" { size, cframe | position, tilt?, name?, after? }
		                               an anchored, solid part in the Workspace folder
		                               hooks.folderName (a wall, a slope, a stair step): size {x, y,
		                               z} studs, each within hooks.minPartStuds to maxPartStuds; a
		                               CFrame, or its centre position turned by tilt (degrees about
		                               X, + lifts the -Z end; or {x, y, z}, the Orientation order);
		                               after = seconds (at most hooks.maxAfterSeconds) makes it
		                               that much later, into a rush's path; at most hooks.maxParts
		"clearparts"                   removes every part (and a part still to come) and the folder
		"pack" { enemy, position, count, facing? }
		                               spawns a pack the way the world spawns one (item 315): count
		                               members (1 to hooks.maxPackSize) of the enemy def `enemy`,
		                               each through PlaygroundService.spawnCFrame (scattered round
		                               the floor point by playground.spawnScatterRadius, clear of
		                               every living fighter by playground.spawnSpacing, at the
		                               rig's root height, facing `facing` degrees with the spawn
		                               jitter) and EnemyService.spawn, so the members stand where a
		                               natural pack's would (the Playground spawns its kobolds one
		                               to a point); replies the ids and where each stands. They
		                               are no spawn slot's: none respawns

	The sink is set only while a trace is on or a swing is collecting, so CombatService measures
	nothing for it the rest of the time; a sink someone else set is chained and given back. Nothing
	the sink does can break the combat tick that calls it (errors are caught and warned once).
	"basic" and "art" skip the client and the request path: they test the server's sweep alone (the
	client hook, DevAim, drives the real request path). "hold", "sethp" and "heal" only set up the
	fight: they fire no remote and decide no hit, so a kill on a held enemy at 1 HP is still a real
	swing's sweep through CombatService. "enemy", "walk" and "charge" move only a server-owned enemy
	body through EnemyService and never touch a player or the anti-cheat: what the enemy then does
	(its hits, its room to other enemies, its stops at walls) is the game's own code with no dev
	rule in it. "part" and "clearparts" touch only their folder. "place" moves only a player, on the server, and no client
	can ask for it: the BindableFunction lives under ServerScriptService, which never replicates,
	and no remote leads to it (a Studio MCP execute_luau in the Server context invokes it). Every
	wait is task.wait (Heartbeat).
	Replies are plain tables execute_luau can JSON-encode; a failure is { ok = false, error = ... }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dev = require(Shared.data.dev)

if not RunService:IsStudio() or workspace:GetAttribute(Dev.attributes.capture) ~= true then
	return
end

local Server = script.Parent.Parent
local Playground = require(Shared.data.playground)
local Rigs = require(Shared.data.rigs)
local World = require(Shared.data.world)
local Palette = require(Shared.data.palette)
local CombatService = require(Server.services.CombatService)
local EnemyService = require(Server.services.EnemyService)
local EntityService = require(Server.services.EntityService)
local AntiCheatService = require(Server.services.AntiCheatService)
local DevTrace = require(script.Parent.DevTrace)
local PlaygroundLayout = require(Server.world.PlaygroundLayout)
local PlaygroundService = require(Server.services.PlaygroundService)
local Enemies = require(Shared.data.enemies)

type Reply = { [string]: any }
type TraceEvent = CombatService.TraceEvent
type Sink = (event: TraceEvent) -> ()
type Record = EntityService.Record

local Trace = Dev.trace
local Place = Dev.place
local Hooks = Dev.hooks
local COMMANDS = {
	"help",
	"trace",
	"events",
	"basic",
	"art",
	"hp",
	"hold",
	"sethp",
	"heal",
	"place",
	"enemy",
	"walk",
	"charge",
	"part",
	"clearparts",
	"pack",
}
-- One line per command for "help": its arguments (? = optional).
local USAGE: { [string]: string } = {
	help = "help: this list",
	trace = "trace { on? }: a line per closed damage window; off gives the sink back",
	events = "events { count?, clear? }: the kept trace events, newest last",
	basic = "basic { entityId?, facing? }: a basic swing through the live CombatService",
	art = "art { entityId?, artId?, facing? }: an Art through the live CombatService",
	hp = "hp: every enemy's HP, state, hold, distance and bearing",
	hold = "hold { ids? | except?, all?, on? }: freeze enemies (no move, attack or regen)",
	sethp = "sethp { entityId, hp }: HP clamped to [1, maxHp], never a kill",
	heal = "heal { entityId? }: full HP",
	place = "place { position = {x, y, z}, facing? = degrees, entityId? | player?, onWindUp? = enemy id, after? = seconds }: move a player on the server (onWindUp: `after` into that enemy's next wind-up); the anti-cheat lets it settle",
	enemy = "enemy { entityId, position = floor {x, y, z}, facing? = degrees, hold? }: stand a living enemy there, Idle (held if hold)",
	walk = "walk { entityId, toward = floor {x, y, z}, hold?, wait? }: walk an enemy there at its own pace (held there if hold)",
	charge = "charge { entityId, toward = {x, y, z} }: a Charger's real rush at the point; replies its launch and stops",
	part = "part { size = {x, y, z}, cframe | position = {x, y, z}, tilt? = degrees or {x, y, z}, name?, after? = seconds }: an anchored part in the dev folder",
	clearparts = "clearparts: remove every dev part (and any still to come)",
	pack = "pack { enemy = def id, position = floor {x, y, z}, count, facing? = degrees }: spawn a pack the way the world does",
}

local printing = false
local kept: { DevTrace.Plain } = {}
local listeners: { [number]: Sink } = {}
local listenerCount = 0
local previous: Sink? = nil
local warnedSink = false
-- The waiting command ("basic", "art", "charge", "walk" with wait, or "place" on a wind-up), or nil.
local busy: string? = nil
-- "part": parts asked for with `after` still to come, and the token "clearparts" bumps to drop them.
local pendingParts = 0
local partsToken = 0

local function round(value: number?): number?
	return DevTrace.round(value, Trace.decimals)
end

local function fail(message: string): Reply
	return { ok = false, error = message }
end

-- ------------------------------------------------------------------ the sink

local function receive(event: TraceEvent)
	if printing then
		DevTrace.push(kept, DevTrace.plain(event, Trace.decimals), Trace.keepEvents)
		print(DevTrace.line(event, Trace.printPrefix, Trace.decimals))
	end
	for _, listener in listeners do
		listener(event)
	end
end

local function sinkFailed(err: unknown)
	if not warnedSink then
		warnedSink = true
		warn(("%s trace sink failed (the combat tick goes on): %s"):format(Trace.printPrefix, tostring(err)))
	end
end

-- CombatService calls this from its Heartbeat tick: nothing in it may break the tick.
local function sink(event: TraceEvent)
	xpcall(receive, sinkFailed, event)
	local chained = previous
	if chained ~= nil then
		chained(event)
	end
end

-- Sets the sink while a trace is on or a swing listens, and gives the old one back after.
local function refreshSink()
	local wanted = printing or next(listeners) ~= nil
	if wanted then
		if CombatService.traceSink ~= sink then
			previous = CombatService.traceSink
			CombatService.traceSink = sink
		end
	elseif CombatService.traceSink == sink then
		CombatService.traceSink = previous
		previous = nil
	end
end

-- Collects the events of `entityId`'s runs until the returned stop is called.
local function listen(entityId: number): ({ TraceEvent }, () -> ())
	listenerCount += 1
	local key = listenerCount
	local collected: { TraceEvent } = {}
	listeners[key] = function(event: TraceEvent)
		if event.entityId == entityId then
			table.insert(collected, event)
		end
	end
	refreshSink()
	return collected, function()
		listeners[key] = nil
		refreshSink()
	end
end

-- ------------------------------------------------------------------ helpers

local function firstPlayerRecord(): Record?
	local player = Players:GetPlayers()[1]
	return if player ~= nil then EntityService.fromPlayer(player) else nil
end

local function entityOf(args: { [string]: any }): (number?, string?)
	local id = args.entityId
	if id == nil then
		local record = firstPlayerRecord()
		if record == nil then
			return nil, "no player entity yet (is a player in the game and spawned?)"
		end
		return record.id, nil
	end
	if typeof(id) ~= "number" then
		return nil, "entityId must be an entity id (a number)"
	end
	return id, nil
end

-- An entity id or a list of them (nil when the argument is absent).
local function idList(value: unknown, name: string): ({ number }?, string?)
	if value == nil then
		return nil, nil
	end
	if typeof(value) == "number" then
		return { value }, nil
	end
	local message = ("%s must be an entity id or a list of entity ids"):format(name)
	if typeof(value) ~= "table" then
		return nil, message
	end
	local list = {}
	for _, id in value :: { [any]: any } do
		if typeof(id) ~= "number" then
			return nil, message
		end
		table.insert(list, id)
	end
	return list, nil
end

local function ascending(list: { number }): { number }
	table.sort(list)
	return list
end

local function enemyHp(): { [number]: number }
	local map = {}
	for _, record in EntityService.enemies() do
		map[record.id] = record.hp
	end
	return map
end

local function hpChanges(before: { [number]: number }): { Reply }
	local list = {}
	for _, record in EntityService.enemies() do
		local was = before[record.id]
		if was ~= nil and was ~= record.hp then
			table.insert(list, { id = record.id, name = record.name, before = was, after = record.hp })
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

-- ------------------------------------------------------------------ commands

local function help(): Reply
	return { ok = true, commands = COMMANDS, usage = USAGE, bindable = Trace.bindableName }
end

local function trace(args: { [string]: any }): Reply
	printing = args.on ~= false
	refreshSink()
	return { ok = true, on = printing, kept = #kept }
end

local function events(args: { [string]: any }): Reply
	local count = args.count
	if count ~= nil and typeof(count) ~= "number" then
		return fail("count must be a number")
	end
	local list = DevTrace.last(kept, count)
	if args.clear == true then
		table.clear(kept)
	end
	return { ok = true, on = printing, events = list }
end

local function swing(kind: "basic" | "art", args: { [string]: any }): Reply
	local id, entityError = entityOf(args)
	if id == nil then
		return fail(entityError or "no entity")
	end
	local facing, facingError = DevTrace.vector(args.facing)
	if facingError ~= nil then
		return fail(facingError)
	end
	local artId: string? = nil
	if kind == "art" then
		if args.artId ~= nil and typeof(args.artId) ~= "string" then
			return fail("artId must be an Art id such as OneHandedSword.Horizontal")
		end
		artId = args.artId
		if artId == nil then
			local record = EntityService.get(id)
			local slots = if record ~= nil and record.artSlots ~= nil
				then record.artSlots
				else Playground.loadout.artSlots
			artId = slots[1]
		end
		if artId == nil then
			return fail("no Art to swing: give artId")
		end
	end
	local before = enemyHp()
	local collected, stop = listen(id)
	local called, started, reason
	if kind == "basic" then
		called, started, reason = pcall(CombatService.beginBasic, id, facing)
	else
		called, started, reason = pcall(CombatService.beginArt, id, artId :: string, facing)
	end
	if not called or not started then
		stop()
		return {
			ok = false,
			entityId = id,
			artId = artId,
			reason = if called then reason else nil,
			error = if called then ("refused: %s"):format(tostring(reason)) else tostring(started),
		}
	end
	local deadline = os.clock() + Trace.runTimeoutSeconds
	while not DevTrace.complete(collected) and os.clock() < deadline do
		task.wait()
	end
	stop()
	local plain = {}
	for _, event in collected do
		table.insert(plain, DevTrace.plain(event, Trace.decimals))
	end
	return {
		ok = true,
		entityId = id,
		artId = artId,
		complete = DevTrace.complete(collected),
		hits = DevTrace.hitsOf(collected),
		events = plain,
		hp = hpChanges(before),
	}
end

local function hp(): Reply
	local record = firstPlayerRecord()
	local root = if record ~= nil then record.model.PrimaryPart else nil
	local list = {}
	for _, enemy in EntityService.enemies() do
		local primary = enemy.model.PrimaryPart
		local distance: number? = nil
		local bearing: number? = nil
		if root ~= nil and primary ~= nil then
			local offset = primary.Position - root.Position
			distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
			bearing = DevTrace.yawBetween(root.CFrame.LookVector, offset)
		end
		table.insert(list, {
			id = enemy.id,
			name = enemy.name,
			hp = enemy.hp,
			maxHp = enemy.maxHp,
			state = enemy.state,
			held = EnemyService.isHeld(enemy.id),
			distance = round(distance),
			bearing = round(bearing),
		})
	end
	table.sort(list, function(a, b)
		local da, db = a.distance or math.huge, b.distance or math.huge
		if da ~= db then
			return da < db
		end
		return a.id < b.id
	end)
	return { ok = true, entityId = if record ~= nil then record.id else nil, enemies = list }
end

local function holdCommand(args: { [string]: any }): Reply
	local on = if args.on == nil then true else args.on
	if typeof(on) ~= "boolean" then
		return fail("on must be true or false")
	end
	if args.all ~= nil and typeof(args.all) ~= "boolean" then
		return fail("all must be true or false")
	end
	local ids, idsError = idList(args.ids, "ids")
	if idsError ~= nil then
		return fail(idsError)
	end
	local except, exceptError = idList(args.except, "except")
	if exceptError ~= nil then
		return fail(exceptError)
	end
	if ids ~= nil and except ~= nil then
		return fail("give ids or except, not both")
	end
	local targets: { number }
	if ids ~= nil then
		targets = ids
	else
		local skip: { [number]: boolean } = {}
		if except ~= nil then
			for _, id in except do
				skip[id] = true
			end
		end
		targets = {}
		for _, id in EnemyService.ids() do
			if not skip[id] then
				table.insert(targets, id)
			end
		end
	end
	local changed: { number } = {}
	local missing: { number } = {}
	for _, id in targets do
		local was = EnemyService.isHeld(id)
		if not EnemyService.setHeld(id, on) then
			table.insert(missing, id)
		elseif was ~= on then
			table.insert(changed, id)
		end
	end
	if args.all == true then
		EnemyService.setHoldNew(on)
	end
	return {
		ok = true,
		on = on,
		held = EnemyService.heldIds(),
		holdNew = EnemyService.holdsNew(),
		changed = ascending(changed),
		missing = ascending(missing),
	}
end

local function sethp(args: { [string]: any }): Reply
	local id = args.entityId
	if typeof(id) ~= "number" then
		return fail("entityId must be an entity id (a number)")
	end
	if typeof(args.hp) ~= "number" then
		return fail("hp must be a number")
	end
	local record = EntityService.get(id)
	if record == nil then
		return fail(("no entity %d"):format(id))
	end
	local before = record.hp
	local after = EntityService.setHp(id, args.hp)
	if after == nil then
		return fail(("entity %d is dead, or hp is not a number"):format(id))
	end
	return {
		ok = true,
		entityId = id,
		name = record.name,
		kind = record.kind,
		before = round(before),
		after = round(after),
		maxHp = record.maxHp,
	}
end

local function heal(args: { [string]: any }): Reply
	local id, entityError = entityOf(args)
	if id == nil then
		return fail(entityError or "no entity")
	end
	local record = EntityService.get(id)
	if record == nil then
		return fail(("no entity %d"):format(id))
	end
	if record.state == "Dead" then
		return fail(("entity %d is dead"):format(id))
	end
	local before = record.hp
	EntityService.heal(id, record.maxHp - before)
	return {
		ok = true,
		entityId = id,
		name = record.name,
		kind = record.kind,
		before = round(before),
		after = round(record.hp),
		maxHp = record.maxHp,
	}
end

local function isFinite(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- The living player "place" moves: entityId (a player's entity), player (a Name or UserId), or the
-- first player.
local function placedRecord(args: { [string]: any }): (Record?, string?)
	if args.entityId ~= nil and args.player ~= nil then
		return nil, "give entityId or player, not both"
	end
	local record: Record? = nil
	if args.player ~= nil then
		local wanted = args.player
		if typeof(wanted) ~= "string" and typeof(wanted) ~= "number" then
			return nil, "player must be a player's Name or UserId"
		end
		for _, candidate in Players:GetPlayers() do
			if candidate.Name == wanted or candidate.UserId == wanted then
				record = EntityService.fromPlayer(candidate)
				if record == nil then
					return nil, ("player %s has no entity yet (spawning?)"):format(tostring(wanted))
				end
				break
			end
		end
		if record == nil then
			return nil, ("no player %s"):format(tostring(wanted))
		end
	else
		local id, entityError = entityOf(args)
		if id == nil then
			return nil, entityError or "no entity"
		end
		record = EntityService.get(id)
		if record == nil then
			return nil, ("no entity %d"):format(id)
		end
	end
	local found = record :: Record
	if found.kind ~= "Player" or found.player == nil then
		return nil, ("entity %d is not a player"):format(found.id)
	end
	if found.state == "Dead" then
		return nil, ("entity %d is dead"):format(found.id)
	end
	return found, nil
end

local function placePosition(value: unknown, name: string): (Vector3?, string?)
	local message = ("%s must be a Vector3 or an {x, y, z} list of numbers, each within %g studs"):format(
		name,
		Place.maxCoordinate
	)
	local position: Vector3? = nil
	if typeof(value) == "Vector3" then
		position = value
	elseif typeof(value) == "table" then
		local list = value :: { [any]: any }
		if isFinite(list[1]) and isFinite(list[2]) and isFinite(list[3]) then
			position = Vector3.new(list[1], list[2], list[3])
		end
	end
	if position == nil then
		return nil, message
	end
	local point = position :: Vector3
	for _, axis in { point.X, point.Y, point.Z } do
		if not isFinite(axis) or math.abs(axis) > Place.maxCoordinate then
			return nil, message
		end
	end
	return point, nil
end

local function plainVector(value: Vector3): { number }
	return { round(value.X) :: number, round(value.Y) :: number, round(value.Z) :: number }
end

-- The phase of a living enemy's brain, or nil once it is gone.
local function phaseOf(id: number): string?
	local brain = EnemyService.brainOf(id)
	return if brain ~= nil then brain:getPhase() else nil
end

-- "place" on a wind-up (302(b)): waits for the enemy's next wind-up to start (one already under way
-- started at no known time), then `after` seconds into it. Returns when it started and the error.
local function waitForWindUp(id: number, after: number, calledAt: number): (number?, string?)
	local deadline = calledAt + Hooks.windUpWaitSeconds
	local was = phaseOf(id)
	local startedAt: number? = nil
	while startedAt == nil do
		if os.clock() >= deadline then
			return nil, ("no wind-up from enemy %d within %g s"):format(id, Hooks.windUpWaitSeconds)
		end
		task.wait()
		local now = phaseOf(id)
		if now == nil then
			return nil, ("enemy %d died or left before its wind-up"):format(id)
		end
		if now == "WindUp" and was ~= "WindUp" then
			startedAt = os.clock()
		end
		was = now
	end
	local at = startedAt :: number
	while os.clock() < at + after - 1e-6 do
		task.wait()
		if phaseOf(id) == nil then
			return nil, ("enemy %d died or left during its wind-up"):format(id)
		end
	end
	return at, nil
end

local function place(args: { [string]: any }): Reply
	local position, positionError = placePosition(args.position, "position")
	if position == nil then
		return fail(positionError or "no position")
	end
	if args.facing ~= nil and not isFinite(args.facing) then
		return fail("facing must be a number of degrees (0 looks along -Z, + turns left)")
	end
	local record, recordError = placedRecord(args)
	if record == nil then
		return fail(recordError or "no player")
	end
	local onWindUp = args.onWindUp
	local windUpAt: number? = nil
	local calledAt = os.clock()
	if onWindUp ~= nil then
		if typeof(onWindUp) ~= "number" or EnemyService.brainOf(onWindUp) == nil then
			return fail("onWindUp must be a living enemy's entity id (a number; hp lists them)")
		end
		local after = if args.after == nil then 0 else args.after
		if not isFinite(after) or after < 0 or after > Hooks.maxPlaceAfterSeconds then
			return fail(("after must be a number of seconds from 0 to %g"):format(Hooks.maxPlaceAfterSeconds))
		end
		local startedAt, waitError = waitForWindUp(onWindUp, after, calledAt)
		if startedAt == nil then
			return fail(waitError or "no wind-up")
		end
		windUpAt = startedAt
		-- The player may have died or left while it waited.
		record, recordError = placedRecord(args)
		if record == nil then
			return fail(recordError or "no player")
		end
	elseif args.after ~= nil then
		return fail("after times a move on onWindUp: give onWindUp too")
	end
	local placed = record :: Record
	local model = placed.model
	local root = model.PrimaryPart
	if root == nil or model.Parent == nil then
		return fail(("entity %d has no character root in the world (respawning?)"):format(placed.id))
	end
	local from = root.Position
	local facing: number = if args.facing ~= nil then args.facing else DevTrace.yawOf(root.CFrame.LookVector) or 0
	-- The anti-cheat first: the move is the server's own, so no sample judges the jump or the
	-- client's positions from before it.
	local watched = AntiCheatService.serverMoved(placed.player :: Player, Place.settleSeconds)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.rad(facing), 0))
	return {
		ok = true,
		entityId = placed.id,
		name = placed.name,
		from = plainVector(from),
		to = plainVector(position),
		facing = round(facing),
		settleSeconds = Place.settleSeconds,
		anticheat = watched,
		onWindUp = if windUpAt ~= nil then onWindUp else nil,
		windUpAt = if windUpAt ~= nil then round(windUpAt - calledAt) else nil,
		movedAt = if windUpAt ~= nil then round(os.clock() - calledAt) else nil,
	}
end

-- ------------------------------------------------------------------ the Studio test hooks (D-333)

-- The living enemy "enemy", "walk" and "charge" act on, its root and its name.
local function enemyOf(args: { [string]: any }): (number?, BasePart?, string)
	local id = args.entityId
	if typeof(id) ~= "number" then
		return nil, nil, "entityId must be a living enemy's entity id (a number; hp lists them)"
	end
	local model = EnemyService.modelOf(id)
	if model == nil then
		return nil, nil, ("entity %s is no living enemy"):format(tostring(id))
	end
	local root = model.PrimaryPart
	if root == nil then
		return nil, nil, ("enemy %d has no root part"):format(id)
	end
	local record = EntityService.get(id)
	return id, root, if record ~= nil then record.name else tostring(id)
end

-- How far an enemy's root stands above the floor under it (its rig's, as a spawn stands).
local function rootHeightOf(id: number): number?
	local def = EnemyService.defOf(id)
	local rig = if def ~= nil then Rigs[def.skin] else nil
	if rig == nil then
		return nil
	end
	local rootSpec = if rig.parts ~= nil then (rig.parts :: any)[rig.rootPart] else nil
	local rootSize = if rootSpec ~= nil then rootSpec.size[2] else 0
	return PlaygroundLayout.rootHeight(rig.hipHeight, rootSize, World.spawn.groundEpsilon)
end

local function optionalFlag(args: { [string]: any }, name: string): (boolean?, string?)
	local value = args[name]
	if value ~= nil and typeof(value) ~= "boolean" then
		return nil, ("%s must be true or false"):format(name)
	end
	return value == true, nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
end

local function enemyCommand(args: { [string]: any }): Reply
	local id, root, name = enemyOf(args)
	if id == nil or root == nil then
		return fail(name)
	end
	local floor, floorError = placePosition(args.position, "position")
	if floor == nil then
		return fail(floorError or "no position")
	end
	if args.facing ~= nil and not isFinite(args.facing) then
		return fail("facing must be a number of degrees (0 looks along -Z, + turns left)")
	end
	local hold, holdError = optionalFlag(args, "hold")
	if hold == nil then
		return fail(holdError or "bad hold")
	end
	local height = rootHeightOf(id)
	if height == nil then
		return fail(("enemy %d has no rig to stand by"):format(id))
	end
	local from = root.CFrame.Position
	local facing: number = if args.facing ~= nil then args.facing else DevTrace.yawOf(root.CFrame.LookVector) or 0
	local at = floor + Vector3.new(0, height, 0)
	if not EnemyService.place(id, CFrame.new(at) * CFrame.Angles(0, math.rad(facing), 0), hold) then
		return fail(("entity %d is no living enemy"):format(id))
	end
	return {
		ok = true,
		entityId = id,
		name = name,
		from = plainVector(from),
		to = plainVector(at),
		facing = round(facing),
		held = EnemyService.isHeld(id),
	}
end

local function walkCommand(args: { [string]: any }): Reply
	local id, root, name = enemyOf(args)
	if id == nil or root == nil then
		return fail(name)
	end
	local goal, goalError = placePosition(args.toward, "toward")
	if goal == nil then
		return fail(goalError or "no toward")
	end
	local hold, holdError = optionalFlag(args, "hold")
	if hold == nil then
		return fail(holdError or "bad hold")
	end
	local wait, waitError = optionalFlag(args, "wait")
	if wait == nil then
		return fail(waitError or "bad wait")
	end
	local from = root.CFrame.Position
	local distance = flatDistance(from, goal)
	if distance > Hooks.maxWalkStuds then
		return fail(("toward is %.1f studs away; a walk goes at most %g"):format(distance, Hooks.maxWalkStuds))
	end
	local def = EnemyService.defOf(id)
	local started, reason = EnemyService.walk(id, goal, {
		arriveStuds = Hooks.arriveStuds,
		seconds = Hooks.walkTimeoutSeconds,
		hold = hold,
	})
	if not started then
		return { ok = false, entityId = id, name = name, error = ("refused: %s"):format(tostring(reason)) }
	end
	local reply: Reply = {
		ok = true,
		entityId = id,
		name = name,
		from = plainVector(from),
		to = plainVector(goal),
		distance = round(distance),
		seconds = if def ~= nil and def.moveSpeed > 0 then round(distance / def.moveSpeed) else nil,
		hold = hold,
	}
	if wait then
		local startedAt = os.clock()
		local deadline = startedAt + Hooks.walkTimeoutSeconds
		while EnemyService.walking(id) and os.clock() < deadline do
			task.wait()
		end
		local model = EnemyService.modelOf(id)
		local now = if model ~= nil and model.PrimaryPart ~= nil then model.PrimaryPart.CFrame.Position else nil
		reply.over = not EnemyService.walking(id)
		reply.at = if now ~= nil then plainVector(now) else nil
		reply.arrived = now ~= nil and flatDistance(now, goal) <= Hooks.arriveStuds
		reply.took = round(os.clock() - startedAt)
		reply.held = EnemyService.isHeld(id)
	end
	return reply
end

local function chargeCommand(args: { [string]: any }): Reply
	local id, root, name = enemyOf(args)
	if id == nil or root == nil then
		return fail(name)
	end
	local toward, towardError = placePosition(args.toward, "toward")
	if toward == nil then
		return fail(towardError or "no toward")
	end
	local from = root.CFrame.Position
	local startedAt = os.clock()
	local started, reason = EnemyService.charge(id, toward)
	if not started then
		return { ok = false, entityId = id, name = name, error = ("refused: %s"):format(tostring(reason)) }
	end
	-- The wind-up and the run: over once the brain leaves them (Recover after a full run, Interrupted
	-- for a slam's daze or a hit's stagger, Dead).
	local deadline = startedAt + Hooks.chargeTimeoutSeconds
	local function phase(): string?
		local brain = EnemyService.brainOf(id)
		return if brain ~= nil then brain:getPhase() else nil
	end
	while os.clock() < deadline do
		local now = phase()
		if now ~= "WindUp" and now ~= "Strike" then
			break
		end
		task.wait()
	end
	local log = EnemyService.devRushOf(id)
	local launched = if log ~= nil then log.launched else nil
	local stops: { Reply } = {}
	if log ~= nil and launched ~= nil then
		for _, stop in log.stops do
			table.insert(stops, {
				reason = stop.reason,
				distance = round(stop.distance),
				after = round(stop.at - launched.at),
			})
		end
	end
	local model = EnemyService.modelOf(id)
	local now = if model ~= nil and model.PrimaryPart ~= nil then model.PrimaryPart.CFrame.Position else nil
	local phaseNow = phase()
	return {
		ok = true,
		entityId = id,
		name = name,
		attackId = if log ~= nil then log.attackId else nil,
		from = plainVector(from),
		toward = plainVector(toward),
		complete = phaseNow ~= "WindUp" and phaseNow ~= "Strike",
		phase = phaseNow,
		at = if now ~= nil then plainVector(now) else nil,
		launched = if launched ~= nil
			then { origin = plainVector(launched.origin), direction = plainVector(launched.direction) }
			else nil,
		stops = stops,
		seconds = round(os.clock() - startedAt),
	}
end

-- The folder the parts live in (made on the first part).
local function partsFolder(create: boolean): Instance?
	local folder = workspace:FindFirstChild(Hooks.folderName)
	if folder == nil and create then
		folder = Instance.new("Folder")
		folder.Name = Hooks.folderName
		folder.Parent = workspace
	end
	return folder
end

local function partSize(value: unknown): (Vector3?, string?)
	local message = ("size must be a Vector3 or an {x, y, z} list of studs, each from %g to %g"):format(
		Hooks.minPartStuds,
		Hooks.maxPartStuds
	)
	local size: Vector3? = nil
	if typeof(value) == "Vector3" then
		size = value
	elseif typeof(value) == "table" then
		local list = value :: { [any]: any }
		if isFinite(list[1]) and isFinite(list[2]) and isFinite(list[3]) then
			size = Vector3.new(list[1], list[2], list[3])
		end
	end
	if size == nil then
		return nil, message
	end
	local box = size :: Vector3
	for _, side in { box.X, box.Y, box.Z } do
		if not isFinite(side) or side < Hooks.minPartStuds or side > Hooks.maxPartStuds then
			return nil, message
		end
	end
	return box, nil
end

-- tilt: degrees about X (+ lifts the -Z end: a slope rising along -Z), or {x, y, z} degrees in
-- the Orientation order (CFrame.fromOrientation).
local function tiltOf(value: unknown): (CFrame?, string?)
	if value == nil then
		return CFrame.identity, nil
	end
	if isFinite(value) then
		return CFrame.Angles(math.rad(value :: number), 0, 0), nil
	end
	if typeof(value) == "table" then
		local list = value :: { [any]: any }
		if isFinite(list[1]) and isFinite(list[2]) and isFinite(list[3]) then
			return CFrame.fromOrientation(math.rad(list[1]), math.rad(list[2]), math.rad(list[3])), nil
		end
	end
	return nil, "tilt must be degrees about X or an {x, y, z} list of degrees (the Orientation order)"
end

local function partCFrame(args: { [string]: any }): (CFrame?, string?)
	if args.cframe ~= nil then
		if args.position ~= nil or args.tilt ~= nil then
			return nil, "give cframe, or position with tilt, not both"
		end
		if typeof(args.cframe) ~= "CFrame" then
			return nil, "cframe must be a CFrame"
		end
		local cframe = args.cframe :: CFrame
		local _, positionError = placePosition(cframe.Position, "cframe's position")
		if positionError ~= nil then
			return nil, positionError
		end
		return cframe, nil
	end
	local position, positionError = placePosition(args.position, "position")
	if position == nil then
		return nil, positionError or "no position"
	end
	local tilt, tiltError = tiltOf(args.tilt)
	if tilt == nil then
		return nil, tiltError or "bad tilt"
	end
	return CFrame.new(position) * tilt, nil
end

local function makePart(name: string, size: Vector3, cframe: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Material = (Enum.Material :: any)[Hooks.partMaterial]
	part.Color = Palette.color3(Hooks.partColorToken :: any)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = partsFolder(true)
	return part
end

local function partCommand(args: { [string]: any }): Reply
	local size, sizeError = partSize(args.size)
	if size == nil then
		return fail(sizeError or "no size")
	end
	local cframe, cframeError = partCFrame(args)
	if cframe == nil then
		return fail(cframeError or "no cframe")
	end
	local after = args.after
	if after ~= nil and (not isFinite(after) or after < 0 or after > Hooks.maxAfterSeconds) then
		return fail(("after must be seconds from 0 to %g"):format(Hooks.maxAfterSeconds))
	end
	local folder = partsFolder(false)
	local count = (if folder ~= nil then #folder:GetChildren() else 0) + pendingParts
	if count >= Hooks.maxParts then
		return fail(("the dev folder holds %d parts at most; clearparts first"):format(Hooks.maxParts))
	end
	local name = args.name
	if name == nil then
		name = ("Part%d"):format(count + 1)
	elseif typeof(name) ~= "string" or #name == 0 or #name > Hooks.maxNameLength then
		return fail(("name must be a string of 1 to %d characters"):format(Hooks.maxNameLength))
	end
	local partName = name :: string
	local box = size :: Vector3
	local at = cframe :: CFrame
	if after ~= nil and after > 0 then
		pendingParts += 1
		local token = partsToken
		task.delay(after, function()
			if token ~= partsToken then
				return -- a clearparts came first
			end
			pendingParts -= 1
			makePart(partName, box, at)
		end)
	else
		makePart(partName, box, at)
	end
	local rx, ry, rz = at:ToOrientation()
	return {
		ok = true,
		name = partName,
		size = plainVector(box),
		position = plainVector(at.Position),
		tilt = { round(math.deg(rx)), round(math.deg(ry)), round(math.deg(rz)) },
		parts = count + 1,
		after = after,
	}
end

local function clearParts(): Reply
	partsToken += 1
	local cancelled = pendingParts
	pendingParts = 0
	local folder = partsFolder(false)
	local removed = if folder ~= nil then #folder:GetChildren() else 0
	if folder ~= nil then
		folder:Destroy()
	end
	return { ok = true, removed = removed, cancelled = cancelled }
end

-- A pack the way the world spawns one (item 315): every member through the Playground's own
-- spawn placement and EnemyService.spawn, one after another, so each clears the ones before.
local function packCommand(args: { [string]: any }): Reply
	local enemy = args.enemy
	if typeof(enemy) ~= "string" or Enemies.byId(enemy) == nil then
		return fail(("enemy must be an enemy def id from enemies.luau, not %s"):format(tostring(enemy)))
	end
	local count = args.count
	if typeof(count) ~= "number" or count % 1 ~= 0 or count < 1 or count > Hooks.maxPackSize then
		return fail(("count must be a whole number from 1 to %d (hooks.maxPackSize)"):format(Hooks.maxPackSize))
	end
	local floor, floorError = placePosition(args.position, "position")
	if floor == nil then
		return fail(floorError or "no position")
	end
	if args.facing ~= nil and not isFinite(args.facing) then
		return fail("facing must be a number of degrees (0 looks along -Z, + turns left)")
	end
	local point = floor :: Vector3
	local spawn = {
		enemy = enemy,
		position = { point.X, point.Y, point.Z },
		facing = if args.facing ~= nil then args.facing else 0,
		packSize = { min = count, max = count },
	}
	local ids: { number } = {}
	local at: { { number } } = {}
	for _ = 1, count do
		local cframe = PlaygroundService.spawnCFrame(spawn :: any)
		table.insert(ids, EnemyService.spawn(enemy, cframe, {}))
		table.insert(at, plainVector(cframe.Position))
	end
	return { ok = true, enemy = enemy, ids = ids, at = at }
end

-- ------------------------------------------------------------------ the BindableFunction

local HANDLERS: { [string]: (args: { [string]: any }) -> Reply } = {
	help = help,
	trace = trace,
	events = events,
	basic = function(args: { [string]: any }): Reply
		return swing("basic", args)
	end,
	art = function(args: { [string]: any }): Reply
		return swing("art", args)
	end,
	hp = hp,
	hold = holdCommand,
	sethp = sethp,
	heal = heal,
	place = place,
	enemy = enemyCommand,
	walk = walkCommand,
	charge = chargeCommand,
	part = partCommand,
	clearparts = clearParts,
	pack = packCommand,
}
-- The commands that wait (task.wait) before they reply: one at a time.
local function yields(command: string, args: { [string]: any }): boolean
	return command == "basic"
		or command == "art"
		or command == "charge"
		or (command == "walk" and args.wait == true)
		or (command == "place" and args.onWindUp ~= nil)
end

local function invoke(command: unknown, rawArgs: unknown): Reply
	local handler = if typeof(command) == "string" then HANDLERS[command] else nil
	if handler == nil then
		return { ok = false, error = ("unknown command %s"):format(tostring(command)), commands = COMMANDS }
	end
	local args: { [string]: any } = if typeof(rawArgs) == "table" then rawArgs :: any else {}
	local waits = yields(command :: string, args)
	if waits and busy ~= nil then
		return fail(("busy: a %s is still waiting"):format(busy :: string))
	end
	if waits then
		busy = command :: string
	end
	local ok, reply = pcall(handler, args)
	if waits then
		busy = nil
	end
	if not ok then
		return fail(tostring(reply))
	end
	return reply
end

local bindable = Instance.new("BindableFunction")
bindable.Name = Trace.bindableName
bindable.OnInvoke = invoke
bindable.Parent = ServerScriptService
