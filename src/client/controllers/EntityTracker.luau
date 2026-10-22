--!strict
--[[
	EntityTracker: the client-side entity registry (ARCHITECTURE "Entities", D-006). The server
	tags every fighter's Model `SkyspireEntity` and publishes its state as attributes; this module
	turns tagged models into records and re-publishes every attribute change on a Signal, so no
	other client module touches CollectionService or attributes directly.

		EntityTracker.get(entityId) -> record?      EntityTracker.fromModel(model) -> record?
		EntityTracker.all() -> { record }            EntityTracker.localId() -> number (yields)
		EntityTracker.added / removed : Signal<record>
		EntityTracker.changed : Signal<record, attributeName, value>

	Engine access goes through a small `Deps` table so Lune tests drive it with plain Instances and
	fake signals (`EntityTracker.bind`); `EntityTracker.start()` binds the real services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.util.Signal)

export type Record = {
	id: number,
	model: Model,
	kind: string,
	defId: string,
	rig: string,
	hp: number,
	maxHp: number,
	gauge: number,
	maxGauge: number,
	state: string,
	name: string,
	cursor: string?,
	level: number,
	weaponId: string?,
	elite: boolean?, -- the server's Elite label (a spawn-time Elite variant); false when absent
}

export type Connection = { Disconnect: (self: any) -> () }

export type Deps = {
	tagged: () -> { Instance },
	instanceAdded: (handler: (Instance) -> ()) -> (),
	instanceRemoved: (handler: (Instance) -> ()) -> (),
	attributeChanged: (model: Instance, attribute: string, handler: () -> ()) -> Connection,
	localCharacter: () -> Instance?,
	characterAdded: (handler: (Instance) -> ()) -> (),
}

local TAG = "SkyspireEntity"

-- Attribute name -> record field (ARCHITECTURE "Entities" table plus the weapon id).
local ATTRIBUTE_FIELDS: { [string]: string } = {
	EntityId = "id",
	EntityKind = "kind",
	DefId = "defId",
	Rig = "rig",
	DisplayName = "name",
	HP = "hp",
	MaxHP = "maxHp",
	Gauge = "gauge",
	MaxGauge = "maxGauge",
	State = "state",
	Cursor = "cursor",
	Level = "level",
	WeaponId = "weaponId",
	Elite = "elite",
}

local DEFAULTS: { [string]: any } = {
	kind = "Enemy",
	defId = "",
	rig = "",
	name = "",
	hp = 0,
	maxHp = 0,
	gauge = 0,
	maxGauge = 0,
	state = "Idle",
	level = 1,
	elite = false,
}

local EntityTracker = {}

EntityTracker.TAG = TAG
EntityTracker.added = Signal.new() :: Signal.Signal<Record>
EntityTracker.removed = Signal.new() :: Signal.Signal<Record>
EntityTracker.changed = Signal.new() :: Signal.Signal<Record, string, any>
--- Fires with the local entity id when it becomes known, and with nil when the local rig is gone.
EntityTracker.localChanged = Signal.new() :: Signal.Signal<number?>

local records: { [number]: Record } = {}
local byModel: { [Instance]: Record } = {}
local connections: { [Instance]: { Connection } } = {}
local pending: { [Instance]: Connection } = {}
local localIdValue: number? = nil
local localWaiters: { thread } = {}
local deps: Deps? = nil

local function dependencies(): Deps
	if deps == nil then
		error("EntityTracker: call bind() or start() first")
	end
	return deps :: Deps
end

local function resolveLocal(record: Record)
	local character = dependencies().localCharacter()
	if character == nil or character ~= record.model then
		return
	end
	localIdValue = record.id
	local waiters = localWaiters
	localWaiters = {}
	for _, thread in waiters do
		task.spawn(thread, record.id)
	end
	EntityTracker.localChanged:Fire(record.id)
end

--- Installs the engine (or test) dependencies without wiring anything.
function EntityTracker.bind(newDeps: Deps)
	deps = newDeps
end

--- Starts tracking a tagged model; waits for its EntityId attribute when it is not there yet.
function EntityTracker.track(model: Instance)
	if byModel[model] ~= nil or pending[model] ~= nil then
		return
	end
	local d = dependencies()
	local id = model:GetAttribute("EntityId")
	if typeof(id) ~= "number" then
		local connection: Connection
		connection = d.attributeChanged(model, "EntityId", function()
			if typeof(model:GetAttribute("EntityId")) ~= "number" then
				return
			end
			connection:Disconnect()
			pending[model] = nil
			EntityTracker.track(model)
		end)
		pending[model] = connection
		return
	end

	local record: any = { id = id, model = model }
	for field, default in DEFAULTS do
		record[field] = default
	end
	for attribute, field in ATTRIBUTE_FIELDS do
		local value = model:GetAttribute(attribute)
		if value ~= nil then
			record[field] = value
		end
	end

	local list: { Connection } = {}
	for attribute, field in ATTRIBUTE_FIELDS do
		if attribute == "EntityId" then
			continue
		end
		table.insert(
			list,
			d.attributeChanged(model, attribute, function()
				local value = model:GetAttribute(attribute)
				record[field] = if value == nil then DEFAULTS[field] else value
				EntityTracker.changed:Fire(record :: Record, attribute, value)
			end)
		)
	end
	connections[model] = list

	local typed = record :: Record
	records[typed.id] = typed
	byModel[model] = typed
	EntityTracker.added:Fire(typed)
	resolveLocal(typed)
end

--- Forgets a model: disconnects its attribute watchers and fires `removed`.
function EntityTracker.untrack(model: Instance)
	local waiting = pending[model]
	if waiting ~= nil then
		waiting:Disconnect()
		pending[model] = nil
	end
	local record = byModel[model]
	if record == nil then
		return
	end
	for _, connection in connections[model] or {} do
		connection:Disconnect()
	end
	connections[model] = nil
	byModel[model] = nil
	if records[record.id] == record then
		records[record.id] = nil
	end
	EntityTracker.removed:Fire(record)
	if localIdValue == record.id then
		localIdValue = nil
		EntityTracker.localChanged:Fire(nil)
	end
end

--- Wires the bound dependencies: existing tagged models, tag added/removed, character spawns.
function EntityTracker.wire()
	local d = dependencies()
	for _, model in d.tagged() do
		EntityTracker.track(model)
	end
	d.instanceAdded(EntityTracker.track)
	d.instanceRemoved(EntityTracker.untrack)
	d.characterAdded(function(character)
		local record = byModel[character]
		if record ~= nil then
			resolveLocal(record)
		end
	end)
end

--- Binds the real CollectionService / Players and starts tracking.
function EntityTracker.start()
	local CollectionService = game:GetService("CollectionService")
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	EntityTracker.bind({
		tagged = function()
			return CollectionService:GetTagged(TAG)
		end,
		instanceAdded = function(handler)
			CollectionService:GetInstanceAddedSignal(TAG):Connect(handler)
		end,
		instanceRemoved = function(handler)
			CollectionService:GetInstanceRemovedSignal(TAG):Connect(handler)
		end,
		attributeChanged = function(model, attribute, handler)
			return model:GetAttributeChangedSignal(attribute):Connect(handler)
		end,
		localCharacter = function()
			return player.Character
		end,
		characterAdded = function(handler)
			player.CharacterAdded:Connect(handler)
		end,
	})
	EntityTracker.wire()
end

--- The record for an entity id, or nil.
function EntityTracker.get(entityId: number): Record?
	return records[entityId]
end

--- The record whose model is `model`, or nil.
function EntityTracker.fromModel(model: Instance): Record?
	return byModel[model]
end

--- Every tracked record, sorted by id.
function EntityTracker.all(): { Record }
	local list = {}
	for _, record in records do
		table.insert(list, record)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

--- The local entity id if it is already known (never yields).
function EntityTracker.peekLocalId(): number?
	return localIdValue
end

--- The local character's entity id; yields until the server has tagged the character.
function EntityTracker.localId(): number
	if localIdValue ~= nil then
		return localIdValue
	end
	table.insert(localWaiters, coroutine.running())
	return coroutine.yield()
end

--- The local record if it is known.
function EntityTracker.localRecord(): Record?
	return if localIdValue ~= nil then records[localIdValue] else nil
end

--- True when the id is the local player's entity.
function EntityTracker.isLocal(entityId: number?): boolean
	return entityId ~= nil and entityId == localIdValue
end

--- Drops every record and waiter (tests, place teardown).
function EntityTracker.reset()
	for model in byModel do
		for _, connection in connections[model] or {} do
			connection:Disconnect()
		end
	end
	for _, connection in pending do
		connection:Disconnect()
	end
	table.clear(records)
	table.clear(byModel)
	table.clear(connections)
	table.clear(pending)
	table.clear(localWaiters)
	localIdValue = nil
end

return EntityTracker
