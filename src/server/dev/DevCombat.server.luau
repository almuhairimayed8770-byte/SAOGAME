--!strict
--[[
	DevCombat: the Studio combat trace hook (D-114). Runs only in Studio (RunService:IsStudio()) in
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
		"hp"                           every enemy: id, name, HP, State, flat distance and bearing
		                               from the first player's root

	The sink is set only while a trace is on or a swing is collecting, so CombatService measures
	nothing for it the rest of the time; a sink someone else set is chained and given back. Nothing
	the sink does can break the combat tick that calls it (errors are caught and warned once).
	"basic" and "art" skip the client and the request path: they test the server's sweep alone (the
	client hook, DevAim, drives the real request path). Every wait is task.wait (Heartbeat).
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
local EntityService = require(Server.services.EntityService)
local DevTrace = require(script.Parent.DevTrace)

type Reply = { [string]: any }
type TraceEvent = CombatService.TraceEvent
type Sink = (event: TraceEvent) -> ()
type Record = EntityService.Record

local Trace = Dev.trace
local COMMANDS = { "help", "trace", "events", "basic", "art", "hp" }

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
	return { ok = true, commands = COMMANDS, bindable = Trace.bindableName }
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
