--!strict
--[[
	Rig smoke (run-in-roblox, Playground place). Plain Luau run on the server after Main has
	started everything; it turns the hand check "confirm the joint names and the Rig attribute"
	into assertions. Every expected name comes from src/shared/data/rigs.luau and scope.luau.

	A joint is a Motor6D or an AnimationConstraint (src/shared/choreo/Joints.luau): under the
	Avatar Joint Upgrade, the default for new experiences, the engine builds R15 characters with
	AnimationConstraints and no Motor6Ds; the RigBuilder enemies and the Weapon joint are Motor6Ds.
	Either class passes; the summary line says which one each rig carries.

	- Player: an R15 stand-in from a blank HumanoidDescription goes through
	  PlaygroundService.onCharacter, the function CharacterAdded runs for a real player (scale, walk
	  speed, the loadout weapon through WeaponBuilder, EntityService registration). Its joint names
	  must be exactly the PlayerR15 joint list (the 15 R15 joints plus Weapon on RightHand), each one
	  linking the Part0 / Part1 rigs.luau names inside the character, and its Rig attribute must be
	  PlayerR15 and known to Choreo. Prints StarterPlayer.AvatarJointUpgrade (when the property is
	  readable) and the stand-in's joint classes, IsKinematic flags and BallSocketConstraints.
	- The player's sheath: the loadout sword's category has a weaponModels.luau back mount, so the
	  stand-in carries one Sheath model whose Scabbard is welded (a Weld, never a joint) to the
	  row's body part at the mount, sits where the weld holds it, and never collides, touches or
	  answers a spatial query. The joint check above still sees exactly the rigs.luau joints, so
	  the weld adds none. The freshly registered stand-in reads Drawn = false (sword on the back).
	- Enemies: for every rig in scope.luau other than the player's, one in-scope enemy that uses
	  that rig is spawned through EnemyService.spawn. Its Rig attribute must equal the rig id (and be
	  known to Choreo) and its joint names must be exactly that rig's joint list, no missing, no
	  extras, no duplicates, each linking the parts rigs.luau names inside the model.
	- Every rig: Pose.solve from the live root with no clip offsets puts every jointed part where
	  the engine holds it (the server plays no animation, so every Transform is identity). This is
	  the server hit sweep's view of the rig checked against the engine's own, for either joint kind.

	Prints one summary line per rig with its joint count and classes, then cleans up what it spawned.

	Run: tools/smoke.sh rigs (installs this file as a server Script in a Run session of the
	Playground; see tools/smoke/SmokeRunner.luau). Errors on the first failed assertion, which the
	runner reports as SMOKE-RESULT: FAIL. Must not return at top level. Not runnable under Lune.

	Written against the services' public API; it has not been run in this environment (no Roblox
	Studio or run-in-roblox here).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local READY_ATTRIBUTE = "SkyspireReady"
local READY_TIMEOUT = 15
local SETTLE_SECONDS = 0.5 -- lets the Humanoid apply the scale values before the joints are read
local ROW_Z = 25 -- studs: where the enemies under test stand, clear of the stand-in at the origin
local ROW_SPACING = 15 -- studs between them
local POSE_TOLERANCE = 0.05 -- studs: how far a live part may sit from where Pose.solve puts it

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
local Joints = require(Shared.choreo.Joints)
local Pose = require(Shared.choreo.Pose)
local World = require(Shared.data.world)
local Weapons = require(Shared.data.weapons)
local WeaponModels = require(Shared.data.weaponModels)
local Playground = require(Shared.data.playground)
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

-- The first thing wrong with one rigs.luau joint on the model, or nil when the joint matches it.
local function jointProblem(model: Model, joint: JointSpec, byName: { [string]: { Instance } }): string?
	local list = byName[joint.name]
	if list == nil then
		return "no Motor6D or AnimationConstraint of that name"
	end
	if #list ~= 1 then
		return ("%d joints share the name"):format(#list)
	end
	local part0, part1 = Joints.parts(list[1])
	if part0 == nil or part1 == nil then
		return ("%s: Part0 is %s, Part1 is %s"):format(list[1].ClassName, tostring(part0), tostring(part1))
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

-- "15 AnimationConstraint, 1 Motor6D": how many joints of each class the model carries.
local function classSummary(byName: { [string]: { Instance } }): string
	local counts: { [string]: number } = {}
	for _, list in byName do
		for _, joint in list do
			counts[joint.ClassName] = (counts[joint.ClassName] or 0) + 1
		end
	end
	local parts: { string } = {}
	for _, className in Joints.CLASSES do
		local count = counts[className]
		if count ~= nil then
			table.insert(parts, ("%d %s"):format(count, className))
		end
	end
	return if #parts > 0 then table.concat(parts, ", ") else "no joints"
end

-- Asserts the model's joints (either class) are exactly the rig's joint list; returns the joint
-- count and the class summary.
local function checkJoints(label: string, model: Model, rigId: string): (number, string)
	local rig = Rigs[rigId]
	local joints: { JointSpec } = rig.joints
	local byName = Joints.byName(model)

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
		("%s has no joint that rigs.luau %s leaves out%s"):format(
			label,
			rigId,
			if #extras > 0 then " (extra: " .. table.concat(extras, ", ") .. ")" else ""
		)
	)

	for _, joint in joints do
		local problem = jointProblem(model, joint, byName)
		local found = byName[joint.name]
		local className = if found ~= nil and #found == 1 then found[1].ClassName else "joint"
		check(
			problem == nil,
			("%s %s %s links %s -> %s inside the model%s"):format(
				label,
				className,
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
	local classes = classSummary(byName)
	check(
		count == #joints,
		("%s carries %d joints (%s), one per rigs.luau %s joint"):format(label, count, classes, rigId)
	)
	return count, classes
end

-- Asserts Pose.solve, from the live root with no offsets, reaches every rigs.luau joint's Part1
-- (down to the blade on the player) and puts every jointed part where the engine holds it.
-- Returns the largest gap (studs) and the part it was on.
local function checkPose(label: string, model: Model, rigId: string): (number, string)
	local root = model.PrimaryPart
	check(root ~= nil, ("%s has a PrimaryPart for the pose check"):format(label))
	local solved = Pose.solve(model, (root :: BasePart).CFrame, {})
	local unreached: { string } = {}
	for _, joint in Rigs[rigId].joints :: { JointSpec } do
		if solved[joint.part1] == nil then
			table.insert(unreached, joint.part1)
		end
	end
	check(
		#unreached == 0,
		("%s: Pose.solve reaches every rigs.luau %s part from the root (the server sweep's view)%s"):format(
			label,
			rigId,
			if #unreached > 0 then " (unreached: " .. table.concat(unreached, ", ") .. ")" else ""
		)
	)
	local worst, worstPart, compared = 0, "none", 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local expected = solved[descendant.Name]
			if expected ~= nil then
				compared += 1
				local gap = (descendant.Position - expected.Position).Magnitude
				-- Orientation as the distance between the two frames' axis tips one stud out.
				local turn = math.max(
					(descendant.CFrame.RightVector - expected.RightVector).Magnitude,
					(descendant.CFrame.UpVector - expected.UpVector).Magnitude
				)
				if math.max(gap, turn) > worst then
					worst = math.max(gap, turn)
					worstPart = descendant.Name
				end
			end
		end
	end
	check(compared > 1, ("%s: Pose.solve reached %d parts from the root"):format(label, compared))
	check(
		worst <= POSE_TOLERANCE,
		("%s: every jointed part sits where Pose.solve puts it (worst %.4f studs, on %s)"):format(
			label,
			worst,
			worstPart
		)
	)
	return worst, worstPart
end

-- What the engine built the stand-in with: the upgrade setting, kinematic flags, ball sockets.
local function describeStandIn(model: Model)
	local readable, setting = pcall(function(): any
		return (StarterPlayer :: any).AvatarJointUpgrade
	end)
	print(
		("[rigs.smoke] StarterPlayer.AvatarJointUpgrade: %s"):format(
			if readable then tostring(setting) else "not readable (" .. tostring(setting) .. ")"
		)
	)
	local constraints, kinematic = 0, 0
	for _, joint in Joints.list(model) do
		if joint:IsA("AnimationConstraint") then
			constraints += 1
			local ok, value = pcall(function(): any
				return (joint :: any).IsKinematic
			end)
			if ok and value == true then
				kinematic += 1
			end
		end
	end
	local sockets, socketsOn = 0, 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BallSocketConstraint") then
			sockets += 1
			if descendant.Enabled then
				socketsOn += 1
			end
		end
	end
	print(
		("[rigs.smoke] stand-in: %d AnimationConstraints (%d kinematic), %d BallSocketConstraints (%d enabled)"):format(
			constraints,
			kinematic,
			sockets,
			socketsOn
		)
	)
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

-- Asserts the stand-in carries the loadout weapon's sheath: one Sheath model, its Scabbard welded
-- to the row's body part where the weld holds it, out of every collision, touch and query.
local function checkSheath(label: string, model: Model)
	local weaponDef = Weapons.byId(Playground.loadout.weapon)
	check(weaponDef ~= nil, "the loadout weapon exists")
	local category = (weaponDef :: any).category
	local row = WeaponModels.sheath(category)
	check(row ~= nil, ("weaponModels.luau has a back mount for the loadout's %s"):format(category))
	local mount: any = row
	local count = 0
	for _, child in model:GetChildren() do
		if child.Name == WeaponModels.sheathModelName then
			count += 1
		end
	end
	check(count == 1, ("%s carries one %s model (found %d)"):format(label, WeaponModels.sheathModelName, count))
	local sheath = model:FindFirstChild(WeaponModels.sheathModelName)
	check(sheath ~= nil and sheath:IsA("Model"), ("%s's %s is a Model"):format(label, WeaponModels.sheathModelName))
	local scabbard = (sheath :: Instance):FindFirstChild(WeaponModels.scabbardPart)
	check(
		scabbard ~= nil and scabbard:IsA("BasePart"),
		("%s's sheath holds a %s part"):format(label, WeaponModels.scabbardPart)
	)
	local part = scabbard :: BasePart
	check(
		not part.CanCollide and not part.CanQuery and not part.CanTouch and part.Massless,
		("%s's scabbard never collides, touches or answers a query, and weighs nothing"):format(label)
	)
	local weld = part:FindFirstChild(WeaponModels.scabbardWeld)
	check(
		weld ~= nil and weld.ClassName == "Weld",
		("%s's scabbard hangs on a Weld named %s (not a joint)"):format(label, WeaponModels.scabbardWeld)
	)
	local joint = weld :: Weld
	local body = model:FindFirstChild(mount.part)
	check(
		body ~= nil and joint.Part0 == body and joint.Part1 == part,
		("the weld links %s -> %s inside %s"):format(mount.part, WeaponModels.scabbardPart, label)
	)
	local held = (body :: BasePart).CFrame * joint.C0 * joint.C1:Inverse()
	local gap = (part.Position - held.Position).Magnitude
	check(
		gap <= POSE_TOLERANCE,
		("%s's scabbard sits where the weld holds it on the back (gap %.4f studs)"):format(label, gap)
	)
	print(
		("[rigs.smoke] %s's scabbard: %.2f x %.2f x %.2f studs, %s, center at %s"):format(
			label,
			part.Size.X,
			part.Size.Y,
			part.Size.Z,
			mount.part,
			tostring((body :: BasePart).CFrame:PointToObjectSpace(part.Position))
		)
	)
end

local summaries: { string } = {}
local function summarize(rigId: string, label: string, count: number, classes: string, poseGap: number)
	table.insert(
		summaries,
		("[rigs.smoke] rig %s: %d joints match rigs.luau (%s; %s; pose gap %.4f studs)"):format(
			rigId,
			count,
			classes,
			label,
			poseGap
		)
	)
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
check(
	standIn:GetAttribute("Drawn") == false,
	("a freshly registered player reads Drawn = false (found %s)"):format(tostring(standIn:GetAttribute("Drawn")))
)
task.wait(SETTLE_SECONDS)

describeStandIn(standIn)
local playerCount, playerClasses = checkJoints("the player stand-in", standIn, playerRig.id)
checkRigAttribute("the player stand-in", standIn, playerRig.id)
local playerGap = checkPose("the player stand-in", standIn, playerRig.id)
checkSheath("the player stand-in", standIn)
check(
	standIn:GetAttribute("Drawn") == false,
	("with no combat the stand-in still reads Drawn = false (found %s)"):format(tostring(standIn:GetAttribute("Drawn")))
)
summarize(playerRig.id, "player stand-in through PlaygroundService.onCharacter", playerCount, playerClasses, playerGap)

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
	local count, classes = checkJoints(label, enemyModel, entry.rigId)
	local gap = checkPose(label, enemyModel, entry.rigId)
	summarize(entry.rigId, entry.defId .. " through EnemyService.spawn", count, classes, gap)
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
