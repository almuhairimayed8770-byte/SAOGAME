--!strict
--[[
	WeaponInfo: what the client needs to know about an entity's equipped weapon (the `WeaponId`
	attribute): its category (which names the clip folder, ARCHITECTURE "Clips") and its trail
	color token (section 8). Unknown or missing ids fall back to the hero weapon so a rig never
	plays nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Weapons = require(ReplicatedStorage.Shared.data.weapons)

local WeaponInfo = {}

WeaponInfo.DEFAULT_CATEGORY = "OneHandedSword"
WeaponInfo.DEFAULT_TRAIL = "TrailCyanWhite"

--- The weapon definition for an id, or nil.
function WeaponInfo.def(weaponId: string?): any
	if weaponId == nil then
		return nil
	end
	return Weapons.byId(weaponId)
end

--- The weapon category for an id (OneHandedSword when unknown).
function WeaponInfo.categoryOf(weaponId: string?): string
	local def = WeaponInfo.def(weaponId)
	return if def ~= nil then def.category else WeaponInfo.DEFAULT_CATEGORY
end

--- The trail color token for an id (the one-handed sword's cyan-white when unknown).
function WeaponInfo.trailTokenOf(weaponId: string?): string
	local def = WeaponInfo.def(weaponId)
	return if def ~= nil and def.trailColor ~= nil then def.trailColor else WeaponInfo.DEFAULT_TRAIL
end

return WeaponInfo
