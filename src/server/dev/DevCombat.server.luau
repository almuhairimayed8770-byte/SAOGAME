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

	The sink is set only while a trace is on or a swing is collecting, so CombatService measures
	nothing for it the rest of the time; a sink someone else set is chained and given back. Nothing
	the sink does can break the combat tick that calls it (errors are caught and warned once).
	"basic" and "art" skip the client and the request path: they test the server's sweep alone (the
	client hook, DevAim, drives the real request path). "hold", "sethp" and "heal" only set up the
	fight: they fire no remote and decide no hit, so a kill on a held enemy at 1 HP is still a real
	swing's sweep through CombatService. "place" moves only a player, on the server, and no client
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
local CombatService = require(Server.services.CombatService)
local EnemyService = require(Server.services.EnemyService)
local EntityService = require(Server.services.EntityService)
local AntiCheatService = require(Server.services.AntiCheatService)
local DevTrace = require(script.Parent.DevTrace)

type Reply = { [string]: any }
type TraceEvent = CombatService.TraceEvent
type Sink = (event: TraceEvent) -> ()
type Record = EntityService.Record

local Trace = Dev.trace
local Place = Dev.place
local COMMANDS = { "help", "trace", "events", "basic", "art", "hp", "hold", "sethp", "heal", "place" }
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
	place = "place { position = {x, y, z}, facing? = degrees, entityId? | player? }: move a player on the server; the anti-cheat lets it settle",
}

local printing = false
local kept: { DevTrace.Plain } = {}
local listeners: { [number]: Sink } = {}
local listenerCount = 0
local previous: Sink? = nil
local warnedSink = false
local busy = false

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

local function placePosition(value: unknown): (Vector3?, string?)
	local message = ("position must be a Vector3 or an {x, y, z} list of numbers, each within %g studs"):format(
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

local function place(args: { [string]: any }): Reply
	local position, positionError = placePosition(args.position)
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
	local model = record.model
	local root = model.PrimaryPart
	if root == nil or model.Parent == nil then
		return fail(("entity %d has no character root in the world (respawning?)"):format(record.id))
	end
	local from = root.Position
	local facing: number = if args.facing ~= nil then args.facing else DevTrace.yawOf(root.CFrame.LookVector) or 0
	-- The anti-cheat first: the move is the server's own, so no sample judges the jump or the
	-- client's positions from before it.
	local watched = AntiCheatService.serverMoved(record.player :: Player, Place.settleSeconds)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.rad(facing), 0))
	return {
		ok = true,
		entityId = record.id,
		name = record.name,
		from = plainVector(from),
		to = plainVector(position),
		facing = round(facing),
		settleSeconds = Place.settleSeconds,
		anticheat = watched,
	}
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
}
local YIELDS: { [string]: boolean } = { basic = true, art = true }

local function invoke(command: unknown, rawArgs: unknown): Reply
	local handler = if typeof(command) == "string" then HANDLERS[command] else nil
	if handler == nil then
		return { ok = false, error = ("unknown command %s"):format(tostring(command)), commands = COMMANDS }
	end
	local yields = YIELDS[command :: string] == true
	if yields and busy then
		return fail("busy: another swing is still collecting")
	end
	busy = busy or yields
	local args: { [string]: any } = if typeof(rawArgs) == "table" then rawArgs :: any else {}
	local ok, reply = pcall(handler, args)
	if yields then
		busy = false
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
