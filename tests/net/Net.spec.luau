--!strict
--[[
	Net.server() under Lune. Net.luau runs in its own environment: `Instance.new` builds recording
	fake remotes and `game` serves fake RunService, Players and ReplicatedStorage, so the shared
	harness DataModel is never touched. Covers the remote tree, fire / fireAll / fireExcept /
	fireList reaching the remotes, the direction guards, unknown names, and the inbound path
	(schema-checked payloads reach the handler, malformed ones are reported as abuse).
]]

local luau = require("@lune/luau")

local Remotes = Harness.load("src/shared/net/Remotes")

local NET_PATH = "src/shared/net/Net"

local CLASS_BY_KIND = {
	Event = "RemoteEvent",
	Unreliable = "UnreliableRemoteEvent",
	Function = "RemoteFunction",
}

type Sent = { method: string, player: any, payload: any }

type World = {
	module: any,
	net: any,
	created: { any },
	folder: any,
	replicatedStorage: any,
	remotes: { [string]: any },
	players: { any },
}

local function newPlayer(name: string, userId: number): any
	return { Name = name, UserId = userId }
end

local function fakeConnection(): any
	return {
		Connected = true,
		Disconnect = function(self: any)
			self.Connected = false
		end,
	}
end

-- Loads a fresh Net module (fresh server singleton) against recording fakes and builds the server.
local function newWorld(): World
	local created: { any } = {}
	local function newInstance(className: string): any
		local fake: any = { ClassName = className, Name = className, Parent = nil }
		fake.sent = {} :: { Sent }
		fake.serverHandlers = {} :: { (...any) -> () }
		function fake.IsA(self: any, name: string): boolean
			return self.ClassName == name
		end
		fake.OnServerEvent = {
			Connect = function(_self: any, handler: (...any) -> ()): any
				table.insert(fake.serverHandlers, handler)
				return fakeConnection()
			end,
		}
		function fake.FireClient(self: any, player: any, payload: any)
			table.insert(self.sent, { method = "FireClient", player = player, payload = payload })
		end
		function fake.FireAllClients(self: any, payload: any)
			table.insert(self.sent, { method = "FireAllClients", player = nil, payload = payload })
		end
		table.insert(created, fake)
		return fake
	end

	local playerList: { any } = {}
	local replicatedStorage = { Name = "ReplicatedStorage", ClassName = "ReplicatedStorage" }
	local services: { [string]: any } = {
		RunService = {
			IsServer = function()
				return true
			end,
			IsClient = function()
				return false
			end,
		},
		Players = {
			PlayerRemoving = {
				Connect = function(_self: any, _handler: (any) -> ()): any
					return fakeConnection()
				end,
			},
			GetPlayers = function(_self: any): { any }
				return table.clone(playerList)
			end,
		},
		ReplicatedStorage = replicatedStorage,
	}

	local env = Harness.environment()
	env.script = Harness.node(NET_PATH)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	env.Instance = { new = newInstance }
	env.game = {
		GetService = function(_self: any, name: string): any
			local service = services[name]
			if service == nil then
				error(("Net.spec: no fake for service '%s'"):format(name), 2)
			end
			return service
		end,
	}
	local source = Harness.readFile(NET_PATH .. ".luau")
	local Net = luau.load(source, { debugName = NET_PATH, environment = env :: any })()

	local net = Net.server()
	local folder = nil
	local remotes: { [string]: any } = {}
	for _, fake in created do
		if fake.ClassName == "Folder" then
			folder = fake
		else
			remotes[fake.Name] = fake
		end
	end
	return {
		module = Net,
		net = net,
		created = created,
		folder = folder,
		replicatedStorage = replicatedStorage,
		remotes = remotes,
		players = playerList,
	}
end

local function hitPayload(): any
	return {
		attackerId = 1,
		targetId = 2,
		damage = 37,
		crit = false,
		gaugeDamage = 12,
		killed = false,
		broke = false,
		hitStop = "Normal",
		position = { 1, 2, 3 },
		parried = false,
		guarded = false,
		reflected = false,
		hitIndex = 1,
	}
end

describe("Net.server remotes", function()
	it("builds one remote per definition, of the right class, under ReplicatedStorage.Net", function()
		local world = newWorld()
		expect(world.folder).toBeTruthy()
		expect(world.folder.Name).toBe("Net")
		expect(world.folder.Parent).toBe(world.replicatedStorage)
		local count = 0
		for name, definition in Remotes do
			count += 1
			local remote = world.remotes[name]
			expect(remote).toBeTruthy()
			expect(remote.ClassName).toBe(CLASS_BY_KIND[definition.kind])
			expect(remote.Parent).toBe(world.folder)
		end
		local built = 0
		for _ in world.remotes do
			built += 1
		end
		expect(built).toBe(count)
	end)

	it("returns the same server API on a second call without building a second tree", function()
		local world = newWorld()
		local before = #world.created
		expect(world.module.server()).toBe(world.net)
		expect(#world.created).toBe(before)
	end)
end)

describe("Net.server sending", function()
	it("fire delivers a HitConfirmed payload to exactly that player", function()
		local world = newWorld()
		local player = newPlayer("Tester", 101)
		local payload = hitPayload()
		world.net.fire("HitConfirmed", player, payload)
		local sent = world.remotes.HitConfirmed.sent
		expect(sent).toHaveLength(1)
		expect(sent[1].method).toBe("FireClient")
		expect(sent[1].player).toBe(player)
		expect(sent[1].payload).toBe(payload)
	end)

	it("fire delivers ActionRejected so the client can cancel its predicted clip", function()
		local world = newWorld()
		local player = newPlayer("Tester", 101)
		local payload = { action = "Art", reason = "cooldown" }
		world.net.fire("ActionRejected", player, payload)
		local sent = world.remotes.ActionRejected.sent
		expect(sent).toHaveLength(1)
		expect(sent[1].player).toBe(player)
		expect(sent[1].payload).toBe(payload)
	end)

	it("fireAll broadcasts a StateChanged payload to every client", function()
		local world = newWorld()
		local payload = { entityId = 7, state = "Idle" }
		world.net.fireAll("StateChanged", payload)
		local sent = world.remotes.StateChanged.sent
		expect(sent).toHaveLength(1)
		expect(sent[1].method).toBe("FireAllClients")
		expect(sent[1].payload).toBe(payload)
	end)

	it("every server-to-client remote, reliable or unreliable, can be fired and broadcast", function()
		local world = newWorld()
		local player = newPlayer("Tester", 101)
		for name, definition in Remotes do
			if definition.direction == "ServerToClient" then
				local payload = { tag = name }
				world.net.fire(name, player, payload)
				world.net.fireAll(name, payload)
				local sent = world.remotes[name].sent
				expect(sent).toHaveLength(2)
				expect(sent[1].method).toBe("FireClient")
				expect(sent[1].player).toBe(player)
				expect(sent[2].method).toBe("FireAllClients")
				expect(sent[2].payload).toBe(payload)
			end
		end
	end)

	it("fireExcept reaches every player but the excluded one", function()
		local world = newWorld()
		local a = newPlayer("A", 1)
		local b = newPlayer("B", 2)
		local c = newPlayer("C", 3)
		table.insert(world.players, a)
		table.insert(world.players, b)
		table.insert(world.players, c)
		world.net.fireExcept("EntityDied", b, { entityId = 4 })
		local sent = world.remotes.EntityDied.sent
		expect(sent).toHaveLength(2)
		local reached = {}
		for _, record in sent do
			reached[record.player] = true
		end
		expect(reached[a]).toBe(true)
		expect(reached[b]).toBeNil()
		expect(reached[c]).toBe(true)
	end)

	it("fireList reaches each listed player once, in order", function()
		local world = newWorld()
		local a = newPlayer("A", 1)
		local b = newPlayer("B", 2)
		world.net.fireList("SystemLine", { a, b }, { text = "Switch!", token = "switch" })
		local sent = world.remotes.SystemLine.sent
		expect(sent).toHaveLength(2)
		expect(sent[1].player).toBe(a)
		expect(sent[2].player).toBe(b)
	end)

	it("fire and fireAll refuse a client-to-server remote and send nothing", function()
		local world = newWorld()
		local player = newPlayer("Tester", 101)
		expect(function()
			world.net.fire("ArtRequest", player, {})
		end).toThrow("'ArtRequest' is not server-to-client")
		expect(function()
			world.net.fireAll("ArtRequest", {})
		end).toThrow("'ArtRequest' is not server-to-client")
		expect(world.remotes.ArtRequest.sent).toHaveLength(0)
	end)

	it("fire and fireAll refuse an unknown remote name", function()
		local world = newWorld()
		expect(function()
			world.net.fire("NoSuchRemote", newPlayer("Tester", 101), {})
		end).toThrow("unknown remote 'NoSuchRemote'")
		expect(function()
			world.net.fireAll("NoSuchRemote", {})
		end).toThrow("unknown remote 'NoSuchRemote'")
	end)
end)

describe("Net.server receiving", function()
	it("passes a schema-valid payload to the handler and reports a malformed one as abuse", function()
		local world = newWorld()
		local player = newPlayer("Tester", 101)
		local received = {}
		world.net.on("ArtRequest", function(from: any, payload: any)
			table.insert(received, { player = from, payload = payload })
		end)
		local abuse = {}
		world.net.abuse:Connect(function(from: any, remoteName: string, reason: string)
			table.insert(abuse, { player = from, remote = remoteName, reason = reason })
		end)

		local handlers = world.remotes.ArtRequest.serverHandlers
		expect(handlers).toHaveLength(1)
		local good = { artId = "OneHandedSword.Horizontal", facing = { 0, 0, -1 }, clientTime = 12.5 }
		handlers[1](player, good)
		expect(received).toHaveLength(1)
		expect(received[1].player).toBe(player)
		expect(received[1].payload).toBe(good)
		expect(abuse).toHaveLength(0)

		handlers[1](player, { artId = 5 })
		expect(received).toHaveLength(1)
		expect(abuse).toHaveLength(1)
		expect(abuse[1].player).toBe(player)
		expect(abuse[1].remote).toBe("ArtRequest")
		expect(abuse[1].reason:sub(1, 7)).toBe("schema:")

		local stats = world.net.stats().ArtRequest
		expect(stats.accepted).toBe(1)
		expect(stats.rejected).toBe(1)
	end)

	it("on refuses a server-to-client remote", function()
		local world = newWorld()
		expect(function()
			world.net.on("HitConfirmed", function() end)
		end).toThrow("'HitConfirmed' is not client-to-server")
	end)
end)
