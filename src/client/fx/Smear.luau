--!strict
--[[
	Smear (section 10, beat 3): for the two snap frames the weapon part is scaled 1.6x along the
	swing axis so the blade reads as a streak; on the third frame the size returns. The clip's
	SmearOn event carries the axis ("X", "Y" or "Z" in the weapon's own space); Choreo fires
	SmearOff and this module restores the size it stored the first time it touched the part.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Engine = require(script.Parent.Engine)

local Smear = {}

local originals: { [BasePart]: Vector3 } = {}
local activeAxis: { [BasePart]: string } = {}

local function forget(weapon: BasePart)
	originals[weapon] = nil
	activeAxis[weapon] = nil
end

local function findWeaponPart(model: Instance): BasePart?
	for _, descendant in model:GetDescendants() do
		if descendant.Name == "Weapon" and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function scaled(size: Vector3, axis: string, scale: number): Vector3
	if axis == "Y" then
		return Vector3.new(size.X, size.Y * scale, size.Z)
	elseif axis == "Z" then
		return Vector3.new(size.X, size.Y, size.Z * scale)
	end
	return Vector3.new(size.X * scale, size.Y, size.Z)
end

--- Stretches (on) or restores (off) the rig's Weapon part along `axis` ("X" | "Y" | "Z").
function Smear.apply(model: Instance, on: boolean, axis: string?)
	local weapon = findWeaponPart(model)
	if weapon == nil then
		return
	end
	local original = originals[weapon]
	if original == nil then
		original = weapon.Size
		originals[weapon] = original
		-- A weapon that leaves the world (its rig shattered and was removed) is forgotten.
		Engine.onRemoved(weapon, function()
			forget(weapon)
		end)
	end
	if on then
		local useAxis = if axis == "X" or axis == "Y" or axis == "Z" then axis :: string else Fx.smear.defaultAxis
		activeAxis[weapon] = useAxis
		weapon.Size = scaled(original :: Vector3, useAxis, Fx.smear.scale)
	else
		activeAxis[weapon] = nil
		weapon.Size = original :: Vector3
	end
end

--- True while the rig's weapon is stretched.
function Smear.isActive(model: Instance): boolean
	local weapon = findWeaponPart(model)
	return weapon ~= nil and activeAxis[weapon] ~= nil
end

--- Restores and forgets a rig's weapon (the rig is leaving or its weapon was swapped).
function Smear.reset(model: Instance)
	local weapon = findWeaponPart(model)
	if weapon == nil then
		return
	end
	local original = originals[weapon]
	if original ~= nil and activeAxis[weapon] ~= nil then
		weapon.Size = original
	end
	forget(weapon)
end

return Smear
