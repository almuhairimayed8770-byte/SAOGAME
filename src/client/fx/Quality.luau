--!strict
--[[
	Quality: the FX quality tier (section 11). Read from the local player's settings attribute
	when the menu has written one, otherwise defaulted from the device: touch devices start on
	Medium, everything else on High. Every FX module reads `Quality.get()` and listens to
	`Quality.changed` instead of touching the player or UserInputService itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage.Shared

local Signal = require(Shared.util.Signal)
local Fx = require(Shared.data.fx)

export type Tier = "High" | "Medium" | "Low"

local Quality = {}

--- Fires with the new tier whenever it changes.
Quality.changed = Signal.new() :: Signal.Signal<Tier>

local current: Tier? = nil
local started = false

local function isTier(value: any): boolean
	return typeof(value) == "string" and Fx.quality[value] ~= nil
end

local function localPlayer(): Player?
	local ok, player = pcall(function()
		return (Players :: any).LocalPlayer
	end)
	if ok and typeof(player) == "Instance" then
		return player
	end
	return nil
end

local function deviceDefault(): Tier
	local ok, touch = pcall(function()
		return (game:GetService("UserInputService") :: any).TouchEnabled
	end)
	if ok and touch == true then
		return Fx.qualityDefaultTouch :: Tier
	end
	return Fx.qualityDefaultDesktop :: Tier
end

local function readSetting(): Tier?
	local player = localPlayer()
	if player == nil then
		return nil
	end
	local ok, value = pcall(function()
		return player:GetAttribute(Fx.qualityAttribute)
	end)
	if ok and isTier(value) then
		return value :: Tier
	end
	return nil
end

--- The current tier ("High" | "Medium" | "Low"); resolved on first call.
function Quality.get(): Tier
	if current == nil then
		current = readSetting() or deviceDefault()
	end
	return current :: Tier
end

--- The tier's FX parameters from fx.luau.
function Quality.params(): Fx.QualityTier
	return Fx.quality[Quality.get()]
end

--- Sets the tier (the settings menu, or tests) and fires `changed` when it differs.
function Quality.set(tier: Tier)
	if not isTier(tier) then
		error(("Quality: unknown tier '%s'"):format(tostring(tier)))
	end
	if current == tier then
		return
	end
	current = tier
	Quality.changed:Fire(tier)
end

--- Watches the player's settings attribute so a menu change applies live.
function Quality.start()
	if started then
		return
	end
	started = true
	Quality.get()
	local player = localPlayer()
	if player == nil then
		return
	end
	pcall(function()
		player:GetAttributeChangedSignal(Fx.qualityAttribute):Connect(function()
			local value = readSetting()
			if value ~= nil then
				Quality.set(value)
			end
		end)
	end)
end

return Quality
