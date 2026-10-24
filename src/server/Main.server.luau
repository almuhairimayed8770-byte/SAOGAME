--!strict
--[[
	Server entry. Brings the network layer up, then starts the services in dependency order:
	EntityService (the registry), CombatService (actions and hits), EnemyService (spawning and AI),
	PlaygroundService (the field, loadouts, respawns), AntiCheatService (speed, timing, abuse policy).

	Every start runs inside pcall and logs its failure; a service module that is not in this build
	yet is reported and skipped, so the server comes up with whatever packages have landed. When
	the last start has run, workspace gets the attribute `SkyspireReady = true` for smoke scripts.
	Before any service, the fighter collision groups are registered (world.CollisionGroups, D-167).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent
local Services = Server:WaitForChild("services")

local Net = require(Shared.net.Net)

local READY_ATTRIBUTE = "SkyspireReady"

-- Start order is a dependency order: each service may call the ones before it at start.
local START_ORDER = {
	"EntityService",
	"CombatService",
	"EnemyService",
	"PlaygroundService",
	"AntiCheatService",
}

local function log(message: string)
	print("[Main] " .. message)
end

local function startService(name: string): boolean
	local module = Services:FindFirstChild(name)
	if module == nil or not module:IsA("ModuleScript") then
		warn(("[Main] %s is not in this build; skipped"):format(name))
		return false
	end
	local loaded, service = pcall(require, module :: ModuleScript)
	if not loaded then
		warn(("[Main] %s failed to load: %s"):format(name, tostring(service)))
		return false
	end
	if typeof(service) ~= "table" or typeof(service.start) ~= "function" then
		warn(("[Main] %s has no start(); skipped"):format(name))
		return false
	end
	local ok, err = pcall(service.start)
	if not ok then
		warn(("[Main] %s failed to start: %s"):format(name, tostring(err)))
		return false
	end
	log(name .. " started")
	return true
end

local netOk, netErr = pcall(Net.server)
if not netOk then
	warn("[Main] Net.server() failed: " .. tostring(netErr))
end

-- The fighter collision groups (D-167) exist before any character or enemy is put in one.
local function registerCollisionGroups()
	local module = Server:WaitForChild("world"):FindFirstChild("CollisionGroups")
	if module == nil or not module:IsA("ModuleScript") then
		warn("[Main] world.CollisionGroups is not in this build; fighters stay in the Default group")
		return
	end
	local loaded, groups = pcall(require, module :: ModuleScript)
	if not loaded or typeof(groups) ~= "table" then
		warn("[Main] collision groups failed to load: " .. tostring(groups))
		return
	end
	local ok, err = pcall(groups.register)
	if not ok then
		warn("[Main] collision groups failed: " .. tostring(err))
	end
end
registerCollisionGroups()

local startedCount = 0
for _, name in START_ORDER do
	if startService(name) then
		startedCount += 1
	end
end

workspace:SetAttribute(READY_ATTRIBUTE, true)
log(("%d of %d services up"):format(startedCount, #START_ORDER))
