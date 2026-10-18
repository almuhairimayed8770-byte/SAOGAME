--!strict
--[[
	PlaygroundService: the Playground's game loop glue (sections 16 and 20; D-009, D-013).

	start() builds the rim, pillars, clouds and kill volume through PlaygroundBuilder, then:
	- on every character, once the engine has finished it (CharacterReady: CharacterAdded fires
	  before the character is parented and dressed, D-046): writes the anime proportions from
	  rigs.luau PlayerR15.scale into the Humanoid's scale NumberValues (created when the avatar
	  lacks them), sets the baseline WalkSpeed from choreo.luau (the client controller layers
	  walk / run / sprint on top), equips the loadout weapon through WeaponBuilder and registers
	  the fighter with EntityService under playground.loadout;
	- spawns the spawn tables through EnemyService.spawn (pack size, scatter and facing jitter from
	  playground.luau) and, when EnemyService reports an enemy gone, respawns that slot after
	  playground.respawnSeconds;
	- on Heartbeat, kills any fighter whose root fell below playground.killVolume.y (the rim is
	  death; EntityService handles the shatter and the respawn).

	Everything engine-facing comes through `Deps` (bind), so the whole service runs under Lune with
	fakes; start() binds the real engine. Timers are stepped from `tick`, never from task.wait.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local Playground = require(Shared.data.playground)
local World = require(Shared.data.world)
local Rigs = require(Shared.data.rigs)
local Enemies = require(Shared.data.enemies)
local Weapons = require(Shared.data.weapons)
local Choreo = require(Shared.data.choreo)
local Signal = require(Shared.util.Signal)
local PlaygroundLayout = require(script.Parent.Parent.world.PlaygroundLayout)

export type Connection = { Disconnect: (self: any) -> () }

export type Deps = {
	now: () -> number, -- server time
	entities: any, -- EntityService
	enemies: any, -- EnemyService (spawn, Despawned)
	weaponBuilder: any?, -- WeaponBuilder (equip); nil skips weapons
	build: (() -> any)?, -- PlaygroundBuilder.build; nil skips the world build
	players: any?, -- Players service (PlayerAdded, CharacterAdded); nil in tests
	heartbeat: ((handler: (dt: number) -> ()) -> Connection?)?,
	waitForChild: (parent: Instance, name: string, timeout: number) -> Instance?,
	-- CharacterReady.wait: yields until the character is parented, dressed and built; false when it
	-- was replaced or never parented in time. nil (tests) means ready when it is parented.
	characterReady: ((player: any, character: Model, timeout: number) -> boolean)?,
	random: Random,
}

type Slot = { index: number, spawn: Playground.Spawn }
type Pending = { slot: number, dueAt: number }

local PlaygroundService = {}

--- Fires (player, character, entityId) once a character is scaled, armed and registered.
PlaygroundService.PlayerReady = Signal.new() :: Signal.Signal<Player, Model, number>
--- Fires (entityId, slotIndex) for every enemy this service spawns, first wave and respawns alike.
PlaygroundService.EnemySpawned = Signal.new() :: Signal.Signal<number, number>

local deps: Deps? = nil
local slotsById: { [number]: Slot } = {}
local pending: { Pending } = {}
local connections: { Connection } = {}
local heartbeatConnection: Connection? = nil
local killAccumulator = 0
local started = false
local built: any = nil

local function dependencies(): Deps
	if deps == nil then
		error("PlaygroundService: call start() or bind() first")
	end
	return deps :: Deps
end

-- ---------------------------------------------------------------------------------------------
-- Characters
-- ---------------------------------------------------------------------------------------------

--- Writes rigs.luau PlayerR15.scale into the Humanoid's scale NumberValues (creating missing ones).
function PlaygroundService.applyScale(humanoid: Humanoid)
	local scale = Rigs.PlayerR15.scale
	if scale == nil then
		return
	end
	local names = World.character.scaleValues
	local values: { [string]: number } = {
		[names.bodyHeight] = scale.bodyHeight,
		[names.bodyWidth] = scale.bodyWidth,
		[names.bodyDepth] = scale.bodyDepth,
		[names.head] = scale.head,
	}
	for name, value in values do
		local existing = humanoid:FindFirstChild(name)
		local holder: NumberValue
		if existing ~= nil and existing:IsA("NumberValue") then
			holder = existing
		else
			holder = Instance.new("NumberValue")
			holder.Name = name
			holder.Parent = humanoid
		end
		holder.Value = value
	end
end

--- The baseline Humanoid WalkSpeed (choreo.luau's run speed; the client layers walk and sprint on it).
function PlaygroundService.walkSpeed(): number
	return Choreo.locomotion.runSpeed
end

--- The loadout weapon's def, or nil when weapons.luau does not know it.
function PlaygroundService.loadoutWeapon(): Types.WeaponDef?
	return Weapons.byId(Playground.loadout.weapon)
end

--- Prepares a character: proportions, walk speed, the loadout weapon, EntityService registration.
--- Returns the entity id, or nil when the character went away before it was ready.
function PlaygroundService.onCharacter(player: Player, character: Model): number?
	local d = dependencies()
	local timeout = World.character.partWaitSeconds
	local humanoid = d.waitForChild(character, "Humanoid", timeout)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		warn(("[PlaygroundService] %s: no Humanoid arrived; character skipped"):format(player.Name))
		return nil
	end
	-- CharacterAdded fires before the engine parents the character and applies the avatar's
	-- appearance (body parts and its own scale values); scaling, arming or registering before that
	-- is undone or skipped (D-046).
	local ready = if d.characterReady ~= nil
		then d.characterReady(player, character, timeout)
		else character.Parent ~= nil
	if not ready then
		return nil -- replaced (respawned) or never put in the world
	end
	PlaygroundService.applyScale(humanoid)
	humanoid.WalkSpeed = PlaygroundService.walkSpeed()

	local weaponBuilder = d.weaponBuilder
	local weaponDef = PlaygroundService.loadoutWeapon()
	if weaponBuilder ~= nil and weaponDef ~= nil then
		local handName = weaponBuilder.gripJoint().part0
		local hand = d.waitForChild(character, handName, timeout)
		if hand ~= nil then
			local ok, err = pcall(weaponBuilder.equip, character, weaponDef)
			if not ok then
				warn(("[PlaygroundService] %s: weapon equip failed: %s"):format(player.Name, tostring(err)))
			end
		else
			warn(("[PlaygroundService] %s: no %s arrived; no weapon equipped"):format(player.Name, handName))
		end
	elseif weaponDef == nil then
		warn(
			("[PlaygroundService] loadout weapon '%s' is not in weapons.luau"):format(
				tostring(Playground.loadout.weapon)
			)
		)
	end

	if character.Parent == nil then
		return nil -- the player left (or respawned) while the parts were loading
	end
	local id = d.entities.registerPlayer(player, character, Playground.loadout)
	PlaygroundService.PlayerReady:Fire(player, character, id)
	return id
end

local function watchPlayer(player: Player)
	local function onCharacter(character: Model)
		local ok, err = pcall(PlaygroundService.onCharacter, player, character)
		if not ok then
			warn(
				("[PlaygroundService] character setup failed for %s (%d): %s"):format(
					player.Name,
					player.UserId,
					tostring(err)
				)
			)
		end
	end
	table.insert(connections, player.CharacterAdded:Connect(onCharacter))
	local existing = player.Character
	if existing ~= nil then
		task.spawn(onCharacter, existing)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Spawns
-- ---------------------------------------------------------------------------------------------

--- Where a member of spawn table entry `spawn` stands: scattered around the point, at the rig's root height, facing the entry's direction with jitter.
function PlaygroundService.spawnCFrame(spawn: Playground.Spawn): CFrame
	local d = dependencies()
	local def = Enemies.byId(spawn.enemy)
	if def == nil then
		error(("PlaygroundService: spawn table names unknown enemy '%s'"):format(tostring(spawn.enemy)))
	end
	local rig = Rigs[def.skin]
	if rig == nil then
		error(("PlaygroundService: enemy %s uses rig '%s', which rigs.luau does not define"):format(def.id, def.skin))
	end
	local rootSpec = if rig.parts ~= nil then (rig.parts :: any)[rig.rootPart] else nil
	local rootHeight = if rootSpec ~= nil then rootSpec.size[2] else 0
	local x, z = PlaygroundLayout.scatter(spawn.position[1], spawn.position[3], Playground.spawnScatterRadius, d.random)
	local y = spawn.position[2] + PlaygroundLayout.rootHeight(rig.hipHeight, rootHeight, World.spawn.groundEpsilon)
	local facing = PlaygroundLayout.jitterFacing(spawn.facing, Playground.spawnFacingJitterDegrees, d.random)
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(facing), 0)
end

--- Spawns one member for spawn table slot `index`; returns the entity id.
function PlaygroundService.spawnMember(index: number): number
	local d = dependencies()
	local spawn = Playground.spawns[index]
	if spawn == nil then
		error(("PlaygroundService: no spawn table entry %d"):format(index))
	end
	local id = d.enemies.spawn(spawn.enemy, PlaygroundService.spawnCFrame(spawn), {})
	slotsById[id] = { index = index, spawn = spawn }
	PlaygroundService.EnemySpawned:Fire(id, index)
	return id
end

--- Spawns a whole pack for slot `index` (packSize.min..max members); returns the ids.
function PlaygroundService.spawnPack(index: number): { number }
	local d = dependencies()
	local spawn = Playground.spawns[index]
	if spawn == nil then
		error(("PlaygroundService: no spawn table entry %d"):format(index))
	end
	local count = d.random:NextInteger(spawn.packSize.min, spawn.packSize.max)
	local ids = {}
	for _ = 1, count do
		table.insert(ids, PlaygroundService.spawnMember(index))
	end
	return ids
end

--- Spawns every spawn table entry; returns all ids.
function PlaygroundService.spawnAll(): { number }
	local ids = {}
	for index in Playground.spawns do
		for _, id in PlaygroundService.spawnPack(index) do
			table.insert(ids, id)
		end
	end
	return ids
end

--- Ids of the enemies this service spawned that are still standing, ascending.
function PlaygroundService.enemyIds(): { number }
	local ids = {}
	for id in slotsById do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

--- The spawn table slot an enemy came from, or nil.
function PlaygroundService.slotOf(id: number): number?
	local slot = slotsById[id]
	return if slot ~= nil then slot.index else nil
end

--- Respawns waiting on their timer (tests and the smoke script).
function PlaygroundService.pendingRespawns(): number
	return #pending
end

local function onDespawned(id: number)
	local slot = slotsById[id]
	if slot == nil then
		return
	end
	slotsById[id] = nil
	table.insert(pending, { slot = slot.index, dueAt = dependencies().now() + Playground.respawnSeconds })
end

local function stepRespawns(now: number)
	local due = {}
	local index = 1
	while index <= #pending do
		local entry = pending[index]
		if now >= entry.dueAt then
			table.insert(due, entry)
			table.remove(pending, index)
		else
			index += 1
		end
	end
	for _, entry in due do
		local ok, err = pcall(PlaygroundService.spawnMember, entry.slot)
		if not ok then
			warn(("[PlaygroundService] respawn of slot %d failed: %s"):format(entry.slot, tostring(err)))
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Kill volume
-- ---------------------------------------------------------------------------------------------

--- Kills every registered fighter whose root is below the kill plane; returns the ids it killed.
function PlaygroundService.checkKillVolume(): { number }
	local d = dependencies()
	local killed = {}
	for _, record in d.entities.all() do
		if record.state == "Dead" then
			continue
		end
		local position = d.entities.positionOf(record.id)
		if position ~= nil and position.Y < Playground.killVolume.y then
			warn(("[PlaygroundService] %s (%d) fell off the rim"):format(record.name, record.id))
			d.entities.die(record.id, nil)
			table.insert(killed, record.id)
		end
	end
	return killed
end

-- ---------------------------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------------------------

--- One frame: due respawns, and the kill-volume scan every world.killVolume.checkInterval seconds.
function PlaygroundService.tick(dt: number)
	local now = dependencies().now()
	stepRespawns(now)
	killAccumulator += dt
	if killAccumulator >= World.killVolume.checkInterval then
		killAccumulator = 0
		PlaygroundService.checkKillVolume()
	end
end

-- ---------------------------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------------------------

-- A sibling module that may not have landed yet: nil (with a warning) instead of an error.
local function sibling(parent: Instance?, name: string): any
	local node = if parent ~= nil then parent:FindFirstChild(name) else nil
	if node == nil or not node:IsA("ModuleScript") then
		warn(("[PlaygroundService] %s is not available yet"):format(name))
		return nil
	end
	local ok, result = pcall(require, node :: ModuleScript)
	if not ok then
		warn(("[PlaygroundService] %s failed to load: %s"):format(name, tostring(result)))
		return nil
	end
	return result
end

--- The real engine dependencies, with any field replaced by `overrides`.
function PlaygroundService.defaultDeps(overrides: { [string]: any }?): Deps
	local RunService = game:GetService("RunService")
	local Players = game:GetService("Players")
	local Server = script.Parent.Parent
	local world = Server:FindFirstChild("world")
	local entities = sibling(script.Parent, "EntityService")
	if entities == nil then
		error("PlaygroundService: EntityService is required")
	end
	local enemies = sibling(script.Parent, "EnemyService")
	if enemies == nil then
		error("PlaygroundService: EnemyService is required")
	end
	local builder = sibling(world, "PlaygroundBuilder")
	local characterReady = sibling(world, "CharacterReady")
	local result: { [string]: any } = {
		now = function()
			return workspace:GetServerTimeNow()
		end,
		entities = entities,
		enemies = enemies,
		weaponBuilder = sibling(world, "WeaponBuilder"),
		characterReady = if characterReady ~= nil then characterReady.wait else nil,
		build = if builder ~= nil
			then function()
				return builder.build(nil, Random.new())
			end
			else nil,
		players = Players,
		heartbeat = function(handler)
			return RunService.Heartbeat:Connect(handler)
		end,
		waitForChild = function(parent, name, timeout)
			return parent:WaitForChild(name, timeout)
		end,
		random = Random.new(),
	}
	if overrides ~= nil then
		for key, value in overrides do
			result[key] = value
		end
	end
	return result :: any
end

--- Installs dependencies (engine or fakes) and connects EnemyService's Despawned signal; no loop yet.
function PlaygroundService.bind(newDeps: Deps)
	PlaygroundService.reset()
	deps = newDeps
	local despawned = newDeps.enemies.Despawned
	if despawned ~= nil then
		table.insert(
			connections,
			despawned:Connect(function(id: number)
				onDespawned(id)
			end)
		)
	end
end

--- What PlaygroundBuilder returned at start (nil before start or when the build was skipped).
function PlaygroundService.buildResult(): any
	return built
end

--- Starts the service: builds the world, watches players, spawns the first wave, runs the loop.
function PlaygroundService.start()
	if started then
		return
	end
	started = true
	if deps == nil then
		PlaygroundService.bind(PlaygroundService.defaultDeps())
	end
	local d = dependencies()
	if d.build ~= nil then
		local ok, result = pcall(d.build)
		if ok then
			built = result
		else
			warn("[PlaygroundService] world build failed: " .. tostring(result))
		end
	end
	local players = d.players
	if players ~= nil then
		table.insert(connections, players.PlayerAdded:Connect(watchPlayer))
		for _, player in players:GetPlayers() do
			watchPlayer(player)
		end
	end
	local ok, err = pcall(PlaygroundService.spawnAll)
	if not ok then
		warn("[PlaygroundService] first spawn wave failed: " .. tostring(err))
	end
	if d.heartbeat ~= nil then
		heartbeatConnection = d.heartbeat(PlaygroundService.tick)
	end
end

--- Stops the loop and forgets every slot, timer and connection (tests, and re-binding).
function PlaygroundService.reset()
	if heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(slotsById)
	table.clear(pending)
	killAccumulator = 0
	started = false
	built = nil
end

return PlaygroundService
