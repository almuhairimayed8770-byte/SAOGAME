--!strict
--[[
	Net: the typed remote wrapper (section 17, docs/DECISIONS.md D-008).

	Server:
		local net = Net.server()
		net.on("ArtRequest", function(player, payload) ... end)  -- payload already schema-checked
		net.fire("HitConfirmed", player, payload)
		net.fireAll("ActionStarted", payload)
		net.abuse:Connect(function(player, remoteName, reason) ... end)  -- AntiCheat decides kicks

	Client:
		local net = Net.client()
		net.on("HitConfirmed", function(payload) ... end)
		net.fire("ArtRequest", payload)

	Every payload is one table. Server-bound payloads are validated against Remotes.luau and
	rate-limited with a token bucket per player per remote. Net never kicks; it reports abuse on
	a Signal and AntiCheatService applies the policy from combat.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Remotes = require(script.Parent.Remotes)
local Signal = require(script.Parent.Parent.util.Signal)

local FOLDER_NAME = "Net"

export type ServerNet = {
	on: (name: string, handler: (player: Player, payload: any) -> ()) -> (),
	fire: (name: string, player: Player, payload: any) -> (),
	fireAll: (name: string, payload: any) -> (),
	fireExcept: (name: string, except: Player, payload: any) -> (),
	fireList: (name: string, players: { Player }, payload: any) -> (),
	abuse: Signal.Signal<Player, string, string>,
	stats: () -> { [string]: { accepted: number, rejected: number } },
}

export type ClientNet = {
	on: (name: string, handler: (payload: any) -> ()) -> (),
	fire: (name: string, payload: any) -> (),
}

type Bucket = { tokens: number, last: number }

local Net = {}

local function definitionOf(name: string): Remotes.RemoteDef
	local definition = Remotes[name]
	if definition == nil then
		error(("Net: unknown remote '%s'"):format(name), 3)
	end
	return definition
end

local function className(kind: Remotes.Kind): string
	if kind == "Event" then
		return "RemoteEvent"
	elseif kind == "Unreliable" then
		return "UnreliableRemoteEvent"
	end
	return "RemoteFunction"
end

local serverInstance: ServerNet? = nil
local clientInstance: ClientNet? = nil

--- Builds (server) the remote instances under ReplicatedStorage.Net and returns the server API.
function Net.server(): ServerNet
	assert(RunService:IsServer(), "Net.server() called on the client")
	if serverInstance then
		return serverInstance
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	local instances: { [string]: Instance } = {}
	for name, definition in Remotes do
		local remote = Instance.new(className(definition.kind))
		remote.Name = name
		remote.Parent = folder
		instances[name] = remote
	end
	folder.Parent = ReplicatedStorage

	local abuse = Signal.new() :: Signal.Signal<Player, string, string>
	local buckets: { [Player]: { [string]: Bucket } } = {}
	local stats: { [string]: { accepted: number, rejected: number } } = {}
	for name in Remotes do
		stats[name] = { accepted = 0, rejected = 0 }
	end

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	local function allow(player: Player, name: string, definition: Remotes.RemoteDef): boolean
		local rate = definition.rate
		if rate == nil then
			return true
		end
		local playerBuckets = buckets[player]
		if playerBuckets == nil then
			playerBuckets = {}
			buckets[player] = playerBuckets
		end
		local now = os.clock()
		local bucket = playerBuckets[name]
		if bucket == nil then
			bucket = { tokens = rate.burst, last = now }
			playerBuckets[name] = bucket
		end
		bucket.tokens = math.min(rate.burst, bucket.tokens + (now - bucket.last) * rate.perSecond)
		bucket.last = now
		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end

	local function on(name: string, handler: (player: Player, payload: any) -> ())
		local definition = definitionOf(name)
		assert(definition.direction == "ClientToServer", ("Net: '%s' is not client-to-server"):format(name))
		local remote = instances[name]
		local function receive(player: Player, payload: any)
			if not allow(player, name, definition) then
				stats[name].rejected += 1
				abuse:Fire(player, name, "rate")
				return
			end
			local ok, message = definition.schema(payload)
			if not ok then
				stats[name].rejected += 1
				abuse:Fire(player, name, "schema: " .. tostring(message))
				return
			end
			stats[name].accepted += 1
			local success, err = pcall(handler, player, payload)
			if not success then
				warn(("[Net] handler for %s failed for %s: %s"):format(name, player.Name, tostring(err)))
			end
		end
		if remote:IsA("RemoteFunction") then
			remote.OnServerInvoke = function(player: Player, payload: any)
				receive(player, payload)
			end
		else
			(remote :: RemoteEvent).OnServerEvent:Connect(receive)
		end
	end

	local function fire(name: string, player: Player, payload: any)
		local definition = definitionOf(name)
		assert(definition.direction == "ServerToClient", ("Net: '%s' is not server-to-client"):format(name))(
			instances[name] :: RemoteEvent
		):FireClient(player, payload)
	end

	local function fireAll(name: string, payload: any)
		local definition = definitionOf(name)
		assert(definition.direction == "ServerToClient", ("Net: '%s' is not server-to-client"):format(name))(
			instances[name] :: RemoteEvent
		):FireAllClients(payload)
	end

	local function fireExcept(name: string, except: Player, payload: any)
		for _, player in Players:GetPlayers() do
			if player ~= except then
				fire(name, player, payload)
			end
		end
	end

	local function fireList(name: string, players: { Player }, payload: any)
		for _, player in players do
			fire(name, player, payload)
		end
	end

	serverInstance = {
		on = on,
		fire = fire,
		fireAll = fireAll,
		fireExcept = fireExcept,
		fireList = fireList,
		abuse = abuse,
		stats = function()
			return stats
		end,
	}
	return serverInstance :: ServerNet
end

--- Waits for the server's remotes and returns the client API.
function Net.client(): ClientNet
	assert(RunService:IsClient(), "Net.client() called on the server")
	if clientInstance then
		return clientInstance
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)

	local function on(name: string, handler: (payload: any) -> ())
		local definition = definitionOf(name)
		assert(definition.direction == "ServerToClient", ("Net: '%s' is not server-to-client"):format(name))
		local remote = folder:WaitForChild(name) :: RemoteEvent
		remote.OnClientEvent:Connect(function(payload: any)
			local success, err = pcall(handler, payload)
			if not success then
				warn(("[Net] client handler for %s failed: %s"):format(name, tostring(err)))
			end
		end)
	end

	local function fire(name: string, payload: any)
		local definition = definitionOf(name)
		assert(definition.direction == "ClientToServer", ("Net: '%s' is not client-to-server"):format(name))
		local remote = folder:WaitForChild(name)
		if remote:IsA("RemoteFunction") then
			remote:InvokeServer(payload)
		else
			(remote :: RemoteEvent):FireServer(payload)
		end
	end

	clientInstance = { on = on, fire = fire }
	return clientInstance :: ClientNet
end

--- Validates a payload against a remote's schema; exposed for tests and for client-side self-checks.
function Net.validate(name: string, payload: any): (boolean, string?)
	return definitionOf(name).schema(payload)
end

return Net
