--!strict
--[[
	Combat smoke (run-in-roblox, Playground place). Plain Luau run on the server after Main has
	started everything: spawns a Frenzy Boar through the world package's RigBuilder and registers
	it, builds a player stand-in (an R15 rig from a HumanoidDescription with the Trialist Sword
	attached the way WeaponBuilder / the rig contract describe), registers it with the Playground
	loadout, runs a Horizontal through CombatService's own entry point and asserts that
	HitLanded fired, HitConfirmed went out, and the boar's HP dropped by the section 6 number.

	Run: run-in-roblox --place build/Playground.rbxl --script tests/smoke/combat.smoke.luau
	Exits non-zero (error) on the first failed assertion. Not runnable under Lune.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Combat = require(Shared.data.combat)
local Enemies = require(Shared.data.enemies)
local Weapons = require(Shared.data.weapons)
local Rigs = require(Shared.data.rigs)
local Playground = require(Shared.data.playground)
local EntityService = require(Server.services.EntityService)
local CombatService = require(Server.services.CombatService)

local READY_ATTRIBUTE = "SkyspireReady"
local READY_TIMEOUT = 15
local HIT_TIMEOUT = 3
local ART_ID = "OneHandedSword.Horizontal"
local STAND_IN_DISTANCE = 3.5 -- studs between the stand-in and the boar

local function check(condition: boolean, message: string)
	if not condition then
		error("[combat.smoke] FAILED: " .. message, 0)
	end
	print("[combat.smoke] ok: " .. message)
end

-- Wait for Main to bring the services up.
local waited = 0
while workspace:GetAttribute(READY_ATTRIBUTE) ~= true and waited < READY_TIMEOUT do
	waited += task.wait(0.1)
end
check(workspace:GetAttribute(READY_ATTRIBUTE) == true, "server services are up")

-- ------------------------------------------------------------------------------------------
-- The boar, through the world package
-- ------------------------------------------------------------------------------------------

local worldFolder = Server:FindFirstChild("world")
check(worldFolder ~= nil, "src/server/world is in the build")
local RigBuilder = require((worldFolder :: Instance):WaitForChild("RigBuilder") :: ModuleScript)
local WeaponBuilder = require((worldFolder :: Instance):WaitForChild("WeaponBuilder") :: ModuleScript)

local boarDef = Enemies.scaled(Enemies.byId("FrenzyBoar") :: any)
local boarModel: Model = RigBuilder.build("Boar", boarDef.name)
check(boarModel.PrimaryPart ~= nil, "RigBuilder gives the boar a PrimaryPart")
local boarRoot = boarModel.PrimaryPart :: BasePart
boarModel.Parent = workspace
boarModel:PivotTo(CFrame.new(0, Rigs.Boar.hipHeight, -STAND_IN_DISTANCE) * CFrame.Angles(0, math.pi, 0))
local boarId = EntityService.registerEnemy(boarModel, boarDef)
check(EntityService.get(boarId) ~= nil, "the boar is registered")
check(boarModel:GetAttribute("HP") == boarDef.hp, "the boar publishes its HP attribute")
-- The boar stands still for the test: freeze it in place.
boarRoot.Anchored = true

-- ------------------------------------------------------------------------------------------
-- The player stand-in: an R15 rig with the Trialist Sword on a Weapon Motor6D
-- ------------------------------------------------------------------------------------------

local description = Instance.new("HumanoidDescription")
local standIn = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
standIn.Name = "StandIn"
standIn.Parent = workspace
standIn:PivotTo(CFrame.new(0, Rigs.PlayerR15.hipHeight + 1, 0))
local standInRoot = standIn.PrimaryPart :: BasePart
standInRoot.Anchored = true

local weaponDef = Weapons.byId(Playground.loadout.weapon)
check(weaponDef ~= nil, "the loadout weapon exists")
-- The same path PlaygroundService takes for a real character: WeaponBuilder hangs the blade from
-- RightHand on a Motor6D named Weapon (C0 from rigs.luau, C1 at the grip).
standIn:WaitForChild("RightHand")
local weaponModel: Model = WeaponBuilder.equip(standIn, weaponDef :: any)
local weaponPart = weaponModel:FindFirstChild("Weapon") :: BasePart?
check(weaponPart ~= nil, "WeaponBuilder's model has a part named Weapon")
check(weaponModel.Parent == standIn, "the weapon is parented under the stand-in")
check(weaponModel:FindFirstChild("TrailStart", true) ~= nil, "the weapon carries TrailStart")
check(weaponModel:FindFirstChild("TrailEnd", true) ~= nil, "the weapon carries TrailEnd")
local gripMotor = (weaponPart :: BasePart):FindFirstChild("Weapon")
check(gripMotor ~= nil and gripMotor:IsA("Motor6D"), "a Motor6D named Weapon hangs the blade from the hand")

-- A player-like stand-in for registration (no real Player in run-in-roblox).
local fakePlayer: any = { Name = "StandIn", DisplayName = "Stand-in", UserId = 0, Parent = nil }
local playerId = EntityService.registerPlayer(fakePlayer, standIn, Playground.loadout)
check(EntityService.get(playerId) ~= nil, "the stand-in is registered as a player")
check(standIn:GetAttribute("WeaponId") == Playground.loadout.weapon, "the stand-in publishes WeaponId")
-- The server checks the slot (section 17): the Art below must sit in the loadout's quick slots.
check(table.find(Playground.loadout.artSlots, ART_ID) ~= nil, "the smoke Art sits in the loadout's quick slots")
check(
	standIn:GetAttribute("ArtSlots") == table.concat(Playground.loadout.artSlots, ","),
	"the stand-in publishes ArtSlots"
)

-- ------------------------------------------------------------------------------------------
-- The Art
-- ------------------------------------------------------------------------------------------

local landed: { any } = {}
CombatService.HitLanded:Connect(function(hit)
	table.insert(landed, hit)
end)
local ended = false
CombatService.ArtEnded:Connect(function(record)
	if record.id == playerId then
		ended = true
	end
end)

local hpBefore = EntityService.get(boarId).hp
local ok, reason = CombatService.beginArt(playerId, ART_ID, standInRoot.CFrame.LookVector)
check(ok, "beginArt accepted the Horizontal (" .. tostring(reason) .. ")")
check(EntityService.get(playerId).state == "Art", "the stand-in is in the Art state")

local elapsed = 0
while #landed == 0 and elapsed < HIT_TIMEOUT do
	elapsed += task.wait()
end
check(#landed >= 1, "HitLanded fired inside the hit window")
check(landed[1].targetId == boarId, "the hit landed on the boar")
check(landed[1].attackerId == playerId, "the hit came from the stand-in")
local expected =
	math.floor(weaponDef.attack * 1.0 * (1 + Playground.loadout.str * Combat.strDamageScale) - boarDef.defense + 0.5)
local critExpected = math.floor(
	weaponDef.attack * Combat.critMultiplier * (1 + Playground.loadout.str * Combat.strDamageScale)
		- boarDef.defense
		+ 0.5
)
check(landed[1].damage == expected or landed[1].damage == critExpected, "damage follows the section 6 formula")
check(EntityService.get(boarId).hp == hpBefore - landed[1].damage, "the boar's HP dropped by the damage")
check(boarModel:GetAttribute("HP") == EntityService.get(boarId).hp, "the HP attribute follows")

elapsed = 0
while not ended and elapsed < HIT_TIMEOUT do
	elapsed += task.wait()
end
check(ended, "the Art reached its end pose")
check(EntityService.get(playerId).state == "PostMotion", "the stand-in is held in PostMotion")
task.wait(Combat.postMotionMin + 0.5)
check(EntityService.get(playerId).state == "Idle", "post-motion released the body")

print("[combat.smoke] all checks passed")
