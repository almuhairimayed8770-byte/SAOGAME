--!strict
--[[
	Rig smoke (run-in-roblox, Playground place). Plain Luau run on the server after Main has
	started everything; it turns the hand check "confirm the Motor6D names and the Rig attribute"
	into assertions. Every expected name comes from src/shared/data/rigs.luau and scope.luau.

	- Player: an R15 stand-in from a blank HumanoidDescription goes through
	  PlaygroundService.onCharacter, the function CharacterAdded runs for a real player (scale, walk
	  speed, the loadout weapon through WeaponBuilder, EntityService registration). Its Motor6D names
	  must be exactly the PlayerR15 joint list (the 15 R15 joints plus Weapon on RightHand), each one
	  linking the Part0 / Part1 rigs.luau names inside the character, and its Rig attribute must be
	  PlayerR15 and known to Choreo.
	- Enemies: for every rig in scope.luau other than the player's, one in-scope enemy that uses
	  that rig is spawned through EnemyService.spawn. Its Rig attribute must equal the rig id (and be
	  known to Choreo) and its Motor6D names must be exactly that rig's joint list, no missing, no
	  extras, no duplicates, each linking the parts rigs.luau names inside the model.

	Prints one summary line per rig with its joint count, then cleans up what it spawned.

	Run: tools/smoke.sh rigs (installs this file as a server Script in a Run session of the
	Playground; see tools/smoke/SmokeRunner.luau). Errors on the first failed assertion, which the
	runner reports as SMOKE-RESULT: FAIL. Must not return at top level. Not runnable under Lune.

	Written against the services' public API; it has not been run in this environment (no Roblox
	Studio or run-in-roblox here).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local READY_ATTRIBUTE = "SkyspireReady"
local READY_TIMEOUT = 15
local SETTLE_SECONDS = 0.5 -- lets the Humanoid apply the scale values before the joints are read
local ROW_Z = 25 -- studs: where the enemies under test stand, clear of the stand-in at the origin
local ROW_SPACING = 15 -- studs between them

local function check(condition: boolean, message: string)
	if not condition then
		error("[rigs.smoke] FAILED: " .. message, 0)
	end
	print("[rigs.smoke] ok: " .. message)
end

-- The Rojo folders are in the place file, so this returns at once; the timeout keeps a broken build from hanging.
local function folder(parent: Instance, name: string): Instance
	local found = parent:WaitForChild(name, READY_TIMEOUT)
	check(found ~= nil, ("%s.%s is in the place"):format(parent.Name, name))
	return found :: Instance
end

local Shared = folder(ReplicatedStorage, "Shared")
local Server = folder(ServerScriptService, "Server")

local Rigs = require(Shared.data.rigs)
local Scope = require(Shared.data.scope)
local Enemies = require(Shared.data.enemies)
local ChoreoData = require(Shared.data.choreo)
local World = require(Shared.data.world)
local EntityService = require(Server.services.EntityService)
local EnemyService = require(Server.services.EnemyService)
local PlaygroundService = require(Server.services.PlaygroundService)
local RigBuilder = require(Server.world.RigBuilder)
local PlaygroundLayout = require(Server.world.PlaygroundLayout)

local RIG_ATTRIBUTE = RigBuilder.RIG_ATTRIBUTE

-- Wait for Main to bring the services up.
local waited = 0
while workspace:GetAttribute(READY_ATTRIBUTE) ~= true and waited < READY_TIMEOUT do
	waited += task.wait(0.1)
end
check(workspace:GetAttribute(READY_ATTRIBUTE) == true, "server services are up")

-- ------------------------------------------------------------------------------------------
-- The joint check, shared by every rig
-- ------------------------------------------------------------------------------------------

type JointSpec = { name: string, part0: string, part1: string }

-- Every Motor6D under the model, grouped by name (Choreo keys joints by name, so a duplicate is a bug).
local function motorsByName(model: Model): { [string]: { Motor6D } }
	local byName: { [string]: { Motor6D } } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			local list = byName[descendant.Name]
			if list == nil then
				list = {}
				byName[descendant.Name] = list
			end
			table.insert(list, descendant)
		end
	end
	return byName
end

-- The first thing wrong with one rigs.luau joint on the model, or nil when the Motor6D matches it.
local function jointProblem(model: Model, joint: JointSpec, byName: { [string]: { Motor6D } }): string?
	local list = byName[joint.name]
	if list == nil then
		return "no Motor6D of that name"
	end
	if #list ~= 1 then
		return ("%d Motor6Ds share the name"):format(#list)
	end
	local motor = list[1]
	local part0 = motor.Part0
	local part1 = motor.Part1
	if part0 == nil or part1 == nil then
		return ("Part0 is %s, Part1 is %s"):format(tostring(part0), tostring(part1))
	end
	if not part0:IsDescendantOf(model) then
		return ("Part0 %s is outside the model"):format(part0:GetFullName())
	end
	if not part1:IsDescendantOf(model) then
		return ("Part1 %s is outside the model"):format(part1:GetFullName())
	end
	if part0.Name ~= joint.part0 then
		return ("Part0 is %s, rigs.luau says %s"):format(part0.Name, joint.part0)
	end
	if part1.Name ~= joint.part1 then
		return ("Part1 is %s, rigs.luau says %s"):format(part1.Name, joint.part1)
	end
	return nil
end

-- Asserts the model's Motor6Ds are exactly the rig's joint list; returns the joint count.
local function checkJoints(label: string, model: Model, rigId: string): number
	local rig = Rigs[rigId]
	local joints: { JointSpec } = rig.joints
	local byName = motorsByName(model)

	local expected: { [string]: boolean } = {}
	for _, joint in joints do
		expected[joint.name] = true
	end
	local extras: { string } = {}
	for name in byName do
		if not expected[name] then
			table.insert(extras, name)
		end
	end
	table.sort(extras)
	check(
		#extras == 0,
		("%s has no Motor6D that rigs.luau %s leaves out%s"):format(
			label,
			rigId,
			if #extras > 0 then " (extra: " .. table.concat(extras, ", ") .. ")" else ""
		)
	)

	for _, joint in joints do
		local problem = jointProblem(model, joint, byName)
		check(
			problem == nil,
			("%s Motor6D %s links %s -> %s inside the model%s"):format(
				label,
				joint.name,
				joint.part0,
				joint.part1,
				if problem ~= nil then ": " .. problem else ""
			)
		)
	end

	local count = 0
	for _, list in byName do
		count += #list
	end
	check(count == #joints, ("%s carries %d Motor6Ds, one per rigs.luau %s joint"):format(label, count, rigId))
	return count
end

-- Asserts the model's Rig attribute names this rig and that Choreo has clips for it.
local function checkRigAttribute(label: string, model: Model, rigId: string)
	local attribute = model:GetAttribute(RIG_ATTRIBUTE)
	check(
		attribute == rigId,
		("%s carries %s = %s (found %s)"):format(label, RIG_ATTRIBUTE, rigId, tostring(attribute))
	)
	check(
		ChoreoData.rigs[rigId] ~= nil,
		("choreo.luau has an idle for rig %s, so Choreo poses it from frame one"):format(rigId)
	)
end

local summaries: { string } = {}
local function summarize(rigId: string, label: string, count: number)
	table.insert(summaries, ("[rigs.smoke] rig %s: %d joints match rigs.luau (%s)"):format(rigId, count, label))
end

-- ------------------------------------------------------------------------------------------
-- The player: an R15 stand-in through the CharacterAdded path
-- ------------------------------------------------------------------------------------------

local playerRig = Rigs.PlayerR15
check(Scope.hasRig(playerRig.id), ("the player rig %s is in scope"):format(playerRig.id))

local description = Instance.new("HumanoidDescription")
local built, builtModel = pcall(function()
	return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
end)
check(
	built and typeof(builtModel) == "Instance" and builtModel:IsA("Model"),
	"Players:CreateHumanoidModelFromDescription built an R15 stand-in"
		.. (if built then "" else ": " .. tostring(builtModel))
)
local standIn = builtModel :: Model
standIn.Name = "RigStandIn"
standIn.Parent = workspace -- onCharacter skips a character that left the world
standIn:PivotTo(CFrame.new(0, playerRig.hipHeight + 1, 0))
local standInRootPart = standIn.PrimaryPart or standIn:FindFirstChild(playerRig.rootPart)
check(standInRootPart ~= nil and standInRootPart:IsA("BasePart"), "the stand-in has a HumanoidRootPart")
local standInRoot = standInRootPart :: BasePart
standIn.PrimaryPart = standInRoot -- EntityService reads the root through PrimaryPart
standInRoot.Anchored = true

-- A player-like stand-in (no real Player here): AntiCheatService watches registered players.
local fakePlayer: any = {
	Name = "RigStandIn",
	DisplayName = "Rig stand-in",
	UserId = 0,
	Parent = nil,
	attributes = {},
}
function fakePlayer.Kick(_self: any, _text: string?) end
function fakePlayer.SetAttribute(self: any, name: string, value: any)
	self.attributes[name] = value
end
function fakePlayer.GetAttribute(self: any, name: string): any
	return self.attributes[name]
end

local prepared, result = pcall(PlaygroundService.onCharacter, fakePlayer, standIn)
check(
	prepared,
	"PlaygroundService.onCharacter ran on the stand-in" .. (if prepared then "" else ": " .. tostring(result))
)
check(typeof(result) == "number", "onCharacter registered the stand-in and returned its entity id")
local standInId = result :: number
check(EntityService.get(standInId) ~= nil, "the stand-in is in the EntityService registry")
task.wait(SETTLE_SECONDS)

local playerCount = checkJoints("the player stand-in", standIn, playerRig.id)
checkRigAttribute("the player stand-in", standIn, playerRig.id)
summarize(playerRig.id, "player stand-in through PlaygroundService.onCharacter", playerCount)

EntityService.unregister(standInId)
standIn:Destroy()
check(EntityService.get(standInId) == nil, "the stand-in left the registry")

-- ------------------------------------------------------------------------------------------
-- Enemies: one per in-scope enemy rig, through EnemyService.spawn
-- ------------------------------------------------------------------------------------------

-- The first in-scope enemy (scope.luau order) whose skin is this rig, or nil.
local function enemyFor(rigId: string): string?
	for _, defId in Scope.enemies do
		local def = Enemies.byId(defId)
		if def ~= nil and def.skin == rigId then
			return defId
		end
	end
	return nil
end

local enemyRigs: { string } = {}
for _, rigId in Scope.rigs do
	if rigId ~= playerRig.id then
		table.insert(enemyRigs, rigId)
	end
end
check(#enemyRigs > 0, ("scope.luau lists %d enemy rigs"):format(#enemyRigs))

local spawned: { { rigId: string, defId: string, id: number } } = {}
for index, rigId in enemyRigs do
	local rig = Rigs[rigId]
	check(rig ~= nil, ("rigs.luau defines the in-scope rig %s"):format(rigId))
	local defId = enemyFor(rigId)
	check(
		defId ~= nil,
		("an in-scope enemy uses rig %s, so EnemyService can spawn it (a boss rig needs its own spawn path here)"):format(
			rigId
		)
	)
	local rootSpec = if rig.parts ~= nil then rig.parts[rig.rootPart] else nil
	local y = PlaygroundLayout.rootHeight(
		rig.hipHeight,
		if rootSpec ~= nil then rootSpec.size[2] else 0,
		World.spawn.groundEpsilon
	)
	local spawnedOk, spawnResult =
		pcall(EnemyService.spawn, defId :: string, CFrame.new((index - 1) * ROW_SPACING, y, ROW_Z))
	check(
		spawnedOk and typeof(spawnResult) == "number",
		("EnemyService.spawn ran for %s"):format(defId :: string)
			.. (if spawnedOk then "" else ": " .. tostring(spawnResult))
	)
	local id = spawnResult :: number
	check(
		EnemyService.modelOf(id) ~= nil,
		("EnemyService spawned %s (rig %s) as enemy %d"):format(defId :: string, rigId, id)
	)
	table.insert(spawned, { rigId = rigId, defId = defId :: string, id = id })
end
task.wait(SETTLE_SECONDS)

for _, entry in spawned do
	local model = EnemyService.modelOf(entry.id)
	check(model ~= nil, ("%s is still standing for the joint check"):format(entry.defId))
	local enemyModel = model :: Model
	local label = ("%s (rig %s)"):format(entry.defId, entry.rigId)
	checkRigAttribute(label, enemyModel, entry.rigId)
	local count = checkJoints(label, enemyModel, entry.rigId)
	summarize(entry.rigId, entry.defId .. " through EnemyService.spawn", count)
end

-- ------------------------------------------------------------------------------------------
-- Clean up and report
-- ------------------------------------------------------------------------------------------

for _, entry in spawned do
	EnemyService.despawn(entry.id)
	check(
		EnemyService.modelOf(entry.id) == nil and EntityService.get(entry.id) == nil,
		("%s was despawned and left the registry"):format(entry.defId)
	)
end

for _, line in summaries do
	print(line)
end
print("[rigs.smoke] all checks passed")
