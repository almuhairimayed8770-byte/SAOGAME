--!strict
--[[
	Client entry. Starts the gameplay controllers in order (net, entities, replication, character,
	input, target, camera), then the fx / hud / audio modules that exist in this build (each inside
	pcall so a missing sibling logs instead of crashing the client), binds the HUD to the local
	entity and tells the server the client is ready.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = script.Parent

local Net = require(Shared.net.Net)
local EntityTracker = require(Client.controllers.EntityTracker)
local Replication = require(Client.controllers.Replication)
local CharacterController = require(Client.controllers.CharacterController)
local InputController = require(Client.controllers.InputController)
local TargetController = require(Client.controllers.TargetController)
local CameraController = require(Client.camera.CameraController)
local Siblings = require(Client.controllers.Siblings)

local function startStep(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[Main] %s failed to start: %s"):format(name, tostring(err)))
	end
end

local net = Net.client()

startStep("EntityTracker", EntityTracker.start)
startStep("Replication", Replication.start)
startStep("CharacterController", CharacterController.start)
startStep("InputController", InputController.start)
startStep("TargetController", TargetController.start)
startStep("CameraController", CameraController.start)

-- Input -> character.
InputController.artPressed:Connect(CharacterController.beginArt)
InputController.artReleased:Connect(CharacterController.releaseArt)
InputController.artCancelled:Connect(CharacterController.cancelArt)
InputController.basicAttack:Connect(CharacterController.basicAttack)
InputController.guardChanged:Connect(CharacterController.setGuard)
InputController.dodge:Connect(CharacterController.dodge)
InputController.sprintChanged:Connect(CharacterController.setSprinting)
InputController.switchCall:Connect(function()
	net.fire("SwitchCallRequest", {})
end)

-- Sibling packages that may not be in this build yet: load each once, start the ones that exist
-- (every start is idempotent). Quality first: the fx budgets and the HUD read its tier.
local SIBLING_ORDER = {
	"fx.Quality",
	"audio.SfxPool",
	"audio.MusicDirector",
	"fx.OutlineManager",
	"fx.Trails",
	"fx.Shatter",
	"fx.Sparks",
	"fx.Digits",
	"fx.SwitchRing",
	"fx.Telegraphs",
	"ui.Hud",
	"ui.Nameplates",
	"ui.SystemLine",
	"choreo.Choreo",
}
local siblings: { [string]: any } = {}
local present: { [string]: boolean } = {}
for _, path in SIBLING_ORDER do
	local module, loaded = Siblings.load(Client, path)
	siblings[path] = module
	present[path] = loaded
	if loaded and path ~= "choreo.Choreo" then
		startStep(path, function()
			Siblings.call(module, "start")
		end)
	end
end

local Hud, hasHud = siblings["ui.Hud"], present["ui.Hud"]
local Choreo, hasChoreo = siblings["choreo.Choreo"], present["choreo.Choreo"]
local Quality, hasQuality = siblings["fx.Quality"], present["fx.Quality"]
if hasQuality and hasChoreo then
	startStep("Choreo quality", function()
		local quality = Siblings.call(Quality, "get")
		if typeof(quality) == "string" then
			Choreo.setQuality(quality)
		end
	end)
end

-- The telegraph intensity slider lives in the HUD; Telegraphs reads it every frame.
local Telegraphs, hasTelegraphs = siblings["fx.Telegraphs"], present["fx.Telegraphs"]
if hasHud and hasTelegraphs then
	startStep("Telegraphs intensity", function()
		Siblings.call(Telegraphs, "setIntensitySource", Hud.telegraphIntensity)
	end)
end

if hasHud then
	local function bindHud(id: number?)
		if id ~= nil then
			startStep("Hud.bindLocal", function()
				Hud.bindLocal(id)
			end)
		end
	end
	EntityTracker.localChanged:Connect(bindHud)
	task.spawn(function()
		bindHud(EntityTracker.localId())
	end)
end

net.fire("ClientReady", {})
