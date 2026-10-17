--!strict
--[[
	Archetype smoke (run-in-roblox, Playground place). Plain Luau run on the server after Main has
	started everything: rebinds EnemyService to its real engine with two overrides (a player
	stand-in as the player source and a fireAll that records payloads), spawns the two Phase 0
	archetypes (Frenzy Boar, Kobold Axeman) through EnemyService.spawn, and asserts that each one
	telegraphs its signature attack within a few seconds of the stand-in appearing, that the
	ActionStarted clip ids follow enemy/<Rig>/<clip>, and that the kobold's overhead lands on the
	idle stand-in through CombatService.enemyStrike (HitLanded).

	Run: run-in-roblox --place build/Playground.rbxl --script tests/smoke/archetypes.smoke.luau
	Exits non-zero (error) on the first failed assertion. Not runnable under Lune.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Enemies = require(Shared.data.enemies)
local Rigs = require(Shared.data.rigs)
local Playground = require(Shared.data.playground)
local Net = require(Shared.net.Net)
local EntityService = require(Server.services.EntityService)
local CombatService = require(Server.services.CombatService)
local EnemyService = require(Server.services.EnemyService)

local READY_ATTRIBUTE = "SkyspireReady"
local READY_TIMEOUT = 15
local TELEGRAPH_TIMEOUT = 8 -- seconds after the stand-in appears for each archetype's telegraph
local STRIKE_TIMEOUT = 4 -- seconds after the kobold's telegraph for its hit to land
local BOAR_DISTANCE = 20 -- studs: inside the Charger's charge band, so it crouches straight away
local KOBOLD_DISTANCE = 12 -- studs: a short walk-up before the overhead
local FOLDER_NAME = "Enemies"
local ALIGN_NAME = "SkyspireYaw"

local function check(condition: boolean, message: string)
	if not condition then
		error("[archetypes.smoke] FAILED: " .. message, 0)
	end
	print("[archetypes.smoke] ok: " .. message)
end

-- Wait for Main to bring the services up.
local waited = 0
while workspace:GetAttribute(READY_ATTRIBUTE) ~= true and waited < READY_TIMEOUT do
	waited += task.wait(0.1)
end
check(workspace:GetAttribute(READY_ATTRIBUTE) == true, "server services are up")

-- ------------------------------------------------------------------------------------------
-- The player stand-in: an anchored R15 rig registered as a player so enemy strikes can land
-- ------------------------------------------------------------------------------------------

local description = Instance.new("HumanoidDescription")
local standIn = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
standIn.Name = "StandIn"
standIn.Parent = workspace
standIn:PivotTo(CFrame.new(0, Rigs.PlayerR15.hipHeight + 1, 0))
local standInRoot = standIn.PrimaryPart :: BasePart
standInRoot.Anchored = true
local fakePlayer: any = { Name = "StandIn", DisplayName = "Stand-in", UserId = 0, Parent = nil }
local standInId = EntityService.registerPlayer(fakePlayer, standIn, Playground.loadout)
check(EntityService.get(standInId) ~= nil, "the stand-in is registered as a player")
local standInHp = EntityService.get(standInId).hp

-- ------------------------------------------------------------------------------------------
-- EnemyService on the real engine, with the stand-in as its player source and a recording fireAll
-- ------------------------------------------------------------------------------------------

local telegraphs: { any } = {}
local actions: { any } = {}
local net = Net.server()

EnemyService.despawnAll() -- whatever PlaygroundService put down goes; this run owns the field
EnemyService.bind(EnemyService.defaultDeps({
	fireAll = function(remote: string, payload: any)
		if remote == "Telegraph" then
			table.insert(telegraphs, payload)
		elseif remote == "ActionStarted" then
			table.insert(actions, payload)
		end
		net.fireAll(remote, payload)
	end,
	players = function()
		return { { id = standInId, position = standInRoot.Position } }
	end,
}))
EnemyService.start()

local landed: { any } = {}
CombatService.HitLanded:Connect(function(hit)
	table.insert(landed, hit)
end)

-- ------------------------------------------------------------------------------------------
-- Spawn the Phase 0 archetypes facing the stand-in
-- ------------------------------------------------------------------------------------------

local boarDef = Enemies.byId("FrenzyBoar")
local koboldDef = Enemies.byId("KoboldAxeman")
local standInPosition = standInRoot.Position

local boarFrom = Vector3.new(0, Rigs.Boar.hipHeight, -BOAR_DISTANCE)
local boarId = EnemyService.spawn(
	"FrenzyBoar",
	CFrame.lookAt(boarFrom, Vector3.new(standInPosition.X, boarFrom.Y, standInPosition.Z))
)
local koboldFrom = Vector3.new(KOBOLD_DISTANCE, Rigs.Kobold.hipHeight, 0)
local koboldId = EnemyService.spawn(
	"KoboldAxeman",
	CFrame.lookAt(koboldFrom, Vector3.new(standInPosition.X, koboldFrom.Y, standInPosition.Z))
)
local appearedAt = workspace:GetServerTimeNow()

local enemiesFolder = workspace:FindFirstChild(FOLDER_NAME)
check(enemiesFolder ~= nil, "workspace.Enemies exists")
for _, id in { boarId, koboldId } do
	local model = EnemyService.modelOf(id)
	check(model ~= nil, ("enemy %d has a model"):format(id))
	local enemyModel = model :: Model
	check(enemyModel.Parent == enemiesFolder, enemyModel.Name .. " is parented under workspace.Enemies")
	check(EntityService.get(id) ~= nil, enemyModel.Name .. " is registered with EntityService")
	local root = enemyModel.PrimaryPart
	check(root ~= nil, enemyModel.Name .. " has a PrimaryPart")
	check((root :: BasePart):FindFirstChild(ALIGN_NAME) ~= nil, enemyModel.Name .. " carries the yaw align")
	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	check(humanoid ~= nil, enemyModel.Name .. " has a Humanoid")
	check((humanoid :: Humanoid).AutoRotate == false, enemyModel.Name .. " leaves its yaw to the brain")
	check(EnemyService.isAwake(id), enemyModel.Name .. " is awake")
end
local koboldHumanoid = (EnemyService.modelOf(koboldId) :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
check(koboldHumanoid.WalkSpeed == Enemies.scaled(koboldDef).moveSpeed, "the kobold walks at its def speed")

-- ------------------------------------------------------------------------------------------
-- Each archetype telegraphs its signature attack within a few seconds
-- ------------------------------------------------------------------------------------------

local function telegraphOf(entityId: number): any
	for _, payload in telegraphs do
		if payload.entityId == entityId then
			return payload
		end
	end
	return nil
end

local function actionOf(entityId: number): any
	for _, payload in actions do
		if payload.entityId == entityId then
			return payload
		end
	end
	return nil
end

local phasesSeen: { [number]: { [string]: boolean } } = { [boarId] = {}, [koboldId] = {} }
local function notePhases()
	for id, seen in phasesSeen do
		local brain = EnemyService.brainOf(id)
		if brain ~= nil then
			seen[brain:getPhase()] = true
		end
	end
end

local elapsed = 0
while (telegraphOf(boarId) == nil or telegraphOf(koboldId) == nil) and elapsed < TELEGRAPH_TIMEOUT do
	elapsed += task.wait()
	notePhases()
end

local boarTelegraph = telegraphOf(boarId)
check(boarTelegraph ~= nil, "the boar telegraphed within " .. TELEGRAPH_TIMEOUT .. " s of the stand-in appearing")
check(boarTelegraph.attackId == boarDef.attacks[1].id, "the boar's telegraph is its Charge")
check(boarTelegraph.windUp == boarDef.attacks[1].windUp, "the boar's wind-up is the def's 0.6 s crouch")
check(boarTelegraph.kind == boarDef.attacks[1].telegraph, "the boar's telegraph kind follows the def")
check(boarTelegraph.shape ~= nil and boarTelegraph.shape.kind == "Line", "the boar draws a line on the ground")
check(boarTelegraph.serverTime >= appearedAt, "the boar's telegraph is stamped with server time")
local boarAction = actionOf(boarId)
check(boarAction ~= nil, "the boar announced its clip")
check(
	boarAction.clipId == ("enemy/%s/%s"):format(boarDef.skin, boarDef.attacks[1].clip),
	"the boar's clip id is enemy/<Rig>/<clip>"
)

local koboldTelegraph = telegraphOf(koboldId)
local koboldTelegraphAt = workspace:GetServerTimeNow()
check(koboldTelegraph ~= nil, "the kobold telegraphed within " .. TELEGRAPH_TIMEOUT .. " s of the stand-in appearing")
check(koboldTelegraph.attackId == koboldDef.attacks[1].id, "the kobold's telegraph is its Overhead")
check(koboldTelegraph.windUp == koboldDef.attacks[1].windUp, "the kobold holds the def's 1.0 s overhead")
check(koboldTelegraph.kind == "GuardBreak", "the kobold's overhead is a guard-break telegraph")
check(koboldTelegraph.shape ~= nil and koboldTelegraph.shape.kind == "Cone", "the kobold draws a cone")
local koboldAction = actionOf(koboldId)
check(koboldAction ~= nil, "the kobold announced its clip")
check(
	koboldAction.clipId == ("enemy/%s/%s"):format(koboldDef.skin, koboldDef.attacks[1].clip),
	"the kobold's clip id is enemy/<Rig>/<clip>"
)

-- ------------------------------------------------------------------------------------------
-- The kobold's strike resolves through CombatService against the idle stand-in
-- ------------------------------------------------------------------------------------------

local function koboldHit(): any
	for _, hit in landed do
		if hit.attackerId == koboldId then
			return hit
		end
	end
	return nil
end

elapsed = 0
while koboldHit() == nil and workspace:GetServerTimeNow() - koboldTelegraphAt < STRIKE_TIMEOUT do
	elapsed += task.wait()
	notePhases()
end
local hit = koboldHit()
check(hit ~= nil, "the kobold's overhead landed through CombatService.enemyStrike")
check(hit.targetId == standInId, "the hit landed on the stand-in")
check(hit.damage > 0, "the overhead did damage")
check(EntityService.get(standInId).hp < standInHp, "the stand-in's HP dropped (the server owns HP)")

for _, id in { boarId, koboldId } do
	local seen = phasesSeen[id]
	check(seen.WindUp == true, ("enemy %d passed through WindUp"):format(id))
	check(seen.Chase == true or seen.Alert == true, ("enemy %d noticed the stand-in before attacking"):format(id))
end

-- ------------------------------------------------------------------------------------------
-- Clean up
-- ------------------------------------------------------------------------------------------

EnemyService.despawnAll()
check(EnemyService.count() == 0, "despawnAll cleared the field")
check(EntityService.get(boarId) == nil and EntityService.get(koboldId) == nil, "despawned enemies left the registry")
EntityService.unregister(standInId)
standIn:Destroy()

print("[archetypes.smoke] all checks passed")
