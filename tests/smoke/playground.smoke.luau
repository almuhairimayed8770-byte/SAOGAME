--!strict
--[[
	Playground smoke (run-in-roblox, Playground place). Plain Luau run on the server after Main has
	started everything: asserts that PlaygroundService built the rim (Railing, Pillars, Clouds and
	the KillVolume under workspace.Playground) inside the part budget, that the first spawn wave put
	a Frenzy Boar in workspace.Enemies with an EntityId attribute, and that a cheat script that
	teleports a registered player stand-in 200 studs five times inside a second is shadow-flagged
	and kicked by AntiCheatService through a system line (never on the first teleport).

	Run: tools/smoke.sh playground (installs this file as a server Script in a Run session of the
	Playground; see tools/smoke/SmokeRunner.luau). Errors on the first failed assertion, which the
	runner reports as SMOKE-RESULT: FAIL. Must not return at top level. Not runnable under Lune.

	Written against the services' public API; it has not been run in this environment (no Roblox
	Studio or run-in-roblox here). See docs/STUDIO_TASKS.md for the manual pass.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Combat = require(Shared.data.combat)
local World = require(Shared.data.world)
local Rigs = require(Shared.data.rigs)
local Playground = require(Shared.data.playground)
local EntityService = require(Server.services.EntityService)
local PlaygroundService = require(Server.services.PlaygroundService)
local AntiCheatService = require(Server.services.AntiCheatService)

local READY_ATTRIBUTE = "SkyspireReady"
local READY_TIMEOUT = 15
local SPAWN_TIMEOUT = 10 -- seconds for the first wave to land in workspace.Enemies
local KICK_TIMEOUT = 5 -- seconds after the last teleport for the sampler and the kick delay
local TELEPORT_STUDS = 200
local TELEPORT_COUNT = 5
local TELEPORT_GAP = 0.2 -- five teleports inside a second
local BOAR_DEF = "FrenzyBoar"

local function check(condition: boolean, message: string)
	if not condition then
		error("[playground.smoke] FAILED: " .. message, 0)
	end
	print("[playground.smoke] ok: " .. message)
end

-- Wait for Main to bring the services up.
local waited = 0
while workspace:GetAttribute(READY_ATTRIBUTE) ~= true and waited < READY_TIMEOUT do
	waited += task.wait(0.1)
end
check(workspace:GetAttribute(READY_ATTRIBUTE) == true, "server services are up")

-- ------------------------------------------------------------------------------------------
-- The built world
-- ------------------------------------------------------------------------------------------

local playground = workspace:FindFirstChild(World.playground.modelName)
check(playground ~= nil, "workspace.Playground exists")
local model = playground :: Instance
local folders = World.playground.folders
check(model:FindFirstChild(folders.railing) ~= nil, "the Railing folder was built")
check(model:FindFirstChild(folders.pillars) ~= nil, "the Pillars folder was built")
check(model:FindFirstChild(folders.clouds) ~= nil, "the Clouds folder was built")
check(model:FindFirstChild(World.playground.killVolumeName) ~= nil, "the KillVolume was built")
check(#(model:FindFirstChild(folders.railing) :: Instance):GetChildren() > 0, "the railing has posts and rails")
check(
	#(model:FindFirstChild(folders.pillars) :: Instance):GetChildren() == Playground.rim.pillarCount,
	"every pillar stands"
)

local partCount = model:GetAttribute(World.playground.partCountAttribute)
check(typeof(partCount) == "number", "Playground carries the PartCount attribute")
check(
	(partCount :: number) < World.playground.partBudget,
	("PartCount %s is under the budget"):format(tostring(partCount))
)
local counted = 0
for _, descendant in model:GetDescendants() do
	if descendant:IsA("BasePart") then
		counted += 1
	end
end
check(counted == partCount, "PartCount matches the parts in the model")
check(workspace:FindFirstChild(folders.enemies) ~= nil, "workspace.Enemies exists for EnemyService")

local built = PlaygroundService.buildResult()
check(built ~= nil and built.partCount == partCount, "PlaygroundService kept the build result")

-- ------------------------------------------------------------------------------------------
-- The first wave: a boar with an EntityId
-- ------------------------------------------------------------------------------------------

local function findBoar(): Model?
	local enemies = workspace:FindFirstChild(folders.enemies)
	if enemies == nil then
		return nil
	end
	for _, child in enemies:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("EntityId") ~= nil then
			local record = EntityService.get(child:GetAttribute("EntityId") :: number)
			if record ~= nil and record.defId == BOAR_DEF then
				return child
			end
		end
	end
	return nil
end

local boar: Model? = findBoar()
waited = 0
while boar == nil and waited < SPAWN_TIMEOUT do
	waited += task.wait(0.1)
	boar = findBoar()
end
check(boar ~= nil, "a Frenzy Boar from the spawn table stands in workspace.Enemies")
local boarModel = boar :: Model
check(boarModel:GetAttribute("EntityId") ~= nil, "the boar carries its EntityId attribute")
check(boarModel:GetAttribute("Rig") == "Boar", "the boar came from RigBuilder (Rig attribute)")
check(boarModel.PrimaryPart ~= nil, "the boar has a PrimaryPart")
check(#PlaygroundService.enemyIds() >= #Playground.spawns, "every spawn slot produced at least one enemy")

-- ------------------------------------------------------------------------------------------
-- The cheat: a registered stand-in teleports 200 studs five times inside a second
-- ------------------------------------------------------------------------------------------

local description = Instance.new("HumanoidDescription")
local standIn = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
standIn.Name = "Cheater"
standIn.Parent = workspace
standIn:PivotTo(CFrame.new(0, Rigs.PlayerR15.hipHeight + 1, 0))
local standInRootPart = standIn.PrimaryPart or standIn:FindFirstChild(Rigs.PlayerR15.rootPart)
check(standInRootPart ~= nil and standInRootPart:IsA("BasePart"), "the stand-in has a HumanoidRootPart")
local standInRoot = standInRootPart :: BasePart
standIn.PrimaryPart = standInRoot -- EntityService reads the root through PrimaryPart
standInRoot.Anchored = true

-- A player-like stand-in: Kick and SetAttribute record what the service did (no real Player here).
local kickedWith: string? = nil
local fakePlayer: any = {
	Name = "Cheater",
	DisplayName = "Cheater",
	UserId = 0,
	Parent = nil,
	attributes = {},
}
function fakePlayer.Kick(_self: any, text: string?)
	kickedWith = text or ""
end
function fakePlayer.SetAttribute(self: any, name: string, value: any)
	self.attributes[name] = value
end
function fakePlayer.GetAttribute(self: any, name: string): any
	return self.attributes[name]
end

local statsBefore = AntiCheatService.stats()
local playerId = EntityService.registerPlayer(fakePlayer, standIn, Playground.loadout)
check(EntityService.get(playerId) ~= nil, "the stand-in is registered as a player")
task.wait() -- Registered fires on its own thread
check(AntiCheatService.isWatched(fakePlayer), "AntiCheatService watches the registered stand-in")
task.wait(Combat.anticheatSampleInterval * 2) -- the first sample records where the stand-in stands

check(not AntiCheatService.isKicked(fakePlayer), "an honest stand-in is not kicked")
for index = 1, TELEPORT_COUNT do
	local position = standInRoot.CFrame.Position
	standInRoot.CFrame = CFrame.new(position.X + TELEPORT_STUDS, position.Y, position.Z)
	if index == 1 then
		task.wait(Combat.anticheatSampleInterval * 2)
		check(not AntiCheatService.isKicked(fakePlayer), "the first teleport alone does not kick")
	else
		task.wait(TELEPORT_GAP)
	end
end

waited = 0
while kickedWith == nil and waited < KICK_TIMEOUT do
	waited += task.wait(0.1)
end
check(AntiCheatService.isKicked(fakePlayer), "AntiCheatService kicked the teleporting stand-in")
check(kickedWith == World.anticheat.kickText, "the kick carries the system line text")
check(fakePlayer.attributes[World.anticheat.shadowAttribute] == true, "the stand-in was shadow-flagged first")

local stats = AntiCheatService.stats()
check(
	stats.teleport - statsBefore.teleport >= World.anticheat.minimumAnomalies,
	"several teleport anomalies were recorded"
)
check(stats.kicked - statsBefore.kicked == 1, "exactly one kick was recorded")
check(stats.shadowed - statsBefore.shadowed == 1, "exactly one shadow flag was recorded")
check(
	EntityService.get(playerId) ~= nil and EntityService.get(playerId).hp > 0,
	"the service never touched the stand-in's HP"
)

print("[playground.smoke] all checks passed")
