--!strict
--[[
	Combat smoke (run-in-roblox, Playground place). Plain Luau run on the server after Main has
	started everything. It stages the Phase 0 gate's fight where a real one stands, then asserts
	the server registers the player's Art on the boar:

	- a Frenzy Boar built by the world package's RigBuilder, parented under workspace.Enemies and
	  placed the way EnemyService / PlaygroundService place one (root at the rig's standing height,
	  PlaygroundLayout.rootHeight, so its legs reach the field), side-on with its flank in front of
	  the stand-in: section 9's counter to a Charger is a sidestep and a cut at the flank. It is
	  registered with EntityService only (no brain) and its root is anchored so it holds still;
	- a player stand-in: the R15 rig Players:CreateHumanoidModelFromDescription builds (the joints
	  a real character spawns with), standing on the field at its own hip height, facing -Z, with
	  the Trialist Sword equipped by WeaponBuilder and the Playground loadout registered;
	- both on open field, away from the player spawn pad (an invisible part spatial queries still
	  see) and beyond every Playground spawn's aggro range.

	It checks the server can solve the blade through the stand-in's joints, prints where the blade
	is against the boar through the hit window, runs a Horizontal through CombatService's own entry
	point and asserts HitLanded fired once and the boar's HP dropped by the section 6 number.

	The sheathed sword: the stand-in starts with Drawn = false (the sword on its back, its scabbard
	welded there), the Horizontal turns Drawn true the moment it starts (a draw-cut), the server's
	Weapon Motor6D stays on the RightHand through the strike (clients move the sword, the server
	never does), and Drawn goes back to false combat.combatTagDuration after the post-motion ends.

	It also plays the scripted client of the Phase 0 gate (section 17): the Art requested again
	and again while the first one runs is refused every time and lands nothing extra, and no
	client-to-server remote lets a client report a hit (each request's schema refuses a payload
	that carries a target or damage). The teleport half of that gate line is playground.smoke.

	Run: tools/smoke.sh combat (installs this file as a server Script in a Run session of the
	Playground; see tools/smoke/SmokeRunner.luau). Errors on the first failed assertion, which the
	runner reports as SMOKE-RESULT: FAIL. Must not return at top level. Not runnable under Lune.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Combat = require(Shared.data.combat)
local Enemies = require(Shared.data.enemies)
local Weapons = require(Shared.data.weapons)
local Arts = require(Shared.data.arts)
local Rigs = require(Shared.data.rigs)
local World = require(Shared.data.world)
local Playground = require(Shared.data.playground)
local WeaponModels = require(Shared.data.weaponModels)
local ClipSampler = require(Shared.choreo.ClipSampler)
local EntityService = require(Server.services.EntityService)
local CombatService = require(Server.services.CombatService)
local HitSweep = require(Server.combat.HitSweep)
local Net = require(Shared.net.Net)
local Remotes = require(Shared.net.Remotes)

local READY_ATTRIBUTE = "SkyspireReady"
local READY_TIMEOUT = 15
local HIT_TIMEOUT = 3
local ART_ID = "OneHandedSword.Horizontal"
local ENEMIES_FOLDER = "Enemies" -- D-027: EnemyService parents every enemy here
-- Open field 24 studs out on +Z: off the player spawn pad (8 x 8 at the center) and more than 80
-- studs from every Playground spawn point (the widest aggro range there is 40).
local ARENA = Vector3.new(0, 0, 24)
local FLANK_DISTANCE = 3 -- studs from the stand-in's root to the boar's, the boar side-on
local GROUND_TOLERANCE = 0.3 -- studs the boar's feet may sit above or below the field
local SPAM_COUNT = 20 -- repeats of the Art a scripted client sends while the first one runs
local SHEATHE_SLACK = 1 -- seconds of scheduling slack around combat.combatTagDuration
local POLL_SECONDS = 0.1

local function check(condition: boolean, message: string)
	if not condition then
		error("[combat.smoke] FAILED: " .. message, 0)
	end
	print("[combat.smoke] ok: " .. message)
end

local function fmt(v: Vector3): string
	return ("(%.2f, %.2f, %.2f)"):format(v.X, v.Y, v.Z)
end

-- Wait for Main to bring the services up.
local waited = 0
while workspace:GetAttribute(READY_ATTRIBUTE) ~= true and waited < READY_TIMEOUT do
	waited += task.wait(0.1)
end
check(workspace:GetAttribute(READY_ATTRIBUTE) == true, "server services are up")

local worldFolder = Server:FindFirstChild("world")
check(worldFolder ~= nil, "src/server/world is in the build")
local function worldModule(name: string): any
	local found = (worldFolder :: Instance):WaitForChild(name, READY_TIMEOUT)
	check(found ~= nil and found:IsA("ModuleScript"), "src/server/world/" .. name .. " is in the build")
	return require(found :: ModuleScript)
end
local RigBuilder = worldModule("RigBuilder")
local WeaponBuilder = worldModule("WeaponBuilder")
local PlaygroundLayout = worldModule("PlaygroundLayout")

-- ------------------------------------------------------------------------------------------
-- The player stand-in: an R15 rig with the Trialist Sword on a Weapon Motor6D
-- ------------------------------------------------------------------------------------------

local description = Instance.new("HumanoidDescription")
local standIn = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
standIn.Name = "StandIn"
standIn.Parent = workspace
local standInRoot = standIn.PrimaryPart :: BasePart
local standInHumanoid = standIn:FindFirstChildOfClass("Humanoid")
local hipHeight = if standInHumanoid ~= nil then standInHumanoid.HipHeight else Rigs.PlayerR15.hipHeight
-- Standing on the field like a spawned character: the root's bottom at HipHeight above the ground.
standIn:PivotTo(CFrame.new(ARENA + Vector3.new(0, hipHeight + standInRoot.Size.Y / 2, 0)))
standInRoot.Anchored = true

local weaponDef = Weapons.byId(Playground.loadout.weapon)
check(weaponDef ~= nil, "the loadout weapon exists")
-- The same path PlaygroundService takes for a real character: WeaponBuilder hangs the blade from
-- RightHand on a Motor6D named Weapon (C0 from rigs.luau, C1 at the grip).
standIn:WaitForChild("RightHand", READY_TIMEOUT)
local weaponModel: Model = WeaponBuilder.equip(standIn, weaponDef :: any)
local weaponPart = weaponModel:FindFirstChild("Weapon") :: BasePart?
check(weaponPart ~= nil, "WeaponBuilder's model has a part named Weapon")
check(weaponModel.Parent == standIn, "the weapon is parented under the stand-in")
check(weaponModel:FindFirstChild("TrailStart", true) ~= nil, "the weapon carries TrailStart")
check(weaponModel:FindFirstChild("TrailEnd", true) ~= nil, "the weapon carries TrailEnd")
local gripMotor = (weaponPart :: BasePart):FindFirstChild("Weapon")
check(gripMotor ~= nil and gripMotor:IsA("Motor6D"), "a Motor6D named Weapon hangs the blade from the hand")
local standInHand = standIn:FindFirstChild("RightHand")
check((gripMotor :: Motor6D).Part0 == standInHand, "the Weapon Motor6D's Part0 is the RightHand")
local sheathModel = standIn:FindFirstChild(WeaponModels.sheathModelName)
local scabbard = if sheathModel ~= nil then sheathModel:FindFirstChild(WeaponModels.scabbardPart) else nil
check(
	scabbard ~= nil and scabbard:IsA("BasePart") and not scabbard.CanQuery and not scabbard.CanCollide,
	"the scabbard is on the stand-in's back and out of every spatial query"
)

-- A player-like stand-in for registration (no real Player in run-in-roblox).
local fakePlayer: any = { Name = "StandIn", DisplayName = "Stand-in", UserId = 0, Parent = nil }
local playerId = EntityService.registerPlayer(fakePlayer, standIn, Playground.loadout)
check(EntityService.get(playerId) ~= nil, "the stand-in is registered as a player")
check(standIn:GetAttribute("WeaponId") == Playground.loadout.weapon, "the stand-in publishes WeaponId")
check(standIn:GetAttribute("Drawn") == false, "the stand-in starts with its sword sheathed (Drawn = false)")
-- The server checks the slot (section 17): the Art below must sit in the loadout's quick slots.
check(table.find(Playground.loadout.artSlots, ART_ID) ~= nil, "the smoke Art sits in the loadout's quick slots")
check(
	standIn:GetAttribute("ArtSlots") == table.concat(Playground.loadout.artSlots, ","),
	"the stand-in publishes ArtSlots"
)

-- ------------------------------------------------------------------------------------------
-- The boar, through the world package, placed the way EnemyService places one
-- ------------------------------------------------------------------------------------------

local enemiesFolder = workspace:WaitForChild(ENEMIES_FOLDER, READY_TIMEOUT)
check(enemiesFolder ~= nil, "EnemyService made workspace." .. ENEMIES_FOLDER)
local boarDef = Enemies.scaled(Enemies.byId("FrenzyBoar") :: any)
local boarRig = Rigs.Boar
local boarRootSpec = (boarRig.parts :: any)[boarRig.rootPart]
local boarHeight = PlaygroundLayout.rootHeight(boarRig.hipHeight, boarRootSpec.size[2], World.spawn.groundEpsilon)
local boarModel: Model = RigBuilder.build("Boar", boarDef.name)
check(boarModel.PrimaryPart ~= nil, "RigBuilder gives the boar a PrimaryPart")
local boarRoot = boarModel.PrimaryPart :: BasePart
-- EnemyService parents first, then places.
boarModel.Parent = enemiesFolder
-- Side-on: the boar faces +X (to the stand-in's right), its flank toward the stand-in.
local boarPosition = ARENA + Vector3.new(0, boarHeight, -FLANK_DISTANCE)
boarModel:PivotTo(CFrame.new(boarPosition) * CFrame.Angles(0, -math.pi / 2, 0))
-- The boar stands still for the test: freeze it in place.
boarRoot.Anchored = true
local boarId = EntityService.registerEnemy(boarModel, boarDef)
check(EntityService.get(boarId) ~= nil, "the boar is registered")
check(boarModel:GetAttribute("HP") == boarDef.hp, "the boar publishes its HP attribute")
local boxCFrame, boxSize = boarModel:GetBoundingBox()
local feet = boxCFrame.Position.Y - boxSize.Y / 2
check(
	math.abs(feet - ARENA.Y) <= GROUND_TOLERANCE,
	("the boar stands on the field (feet at y %.2f, field at y %.2f)"):format(feet, ARENA.Y)
)

-- ------------------------------------------------------------------------------------------
-- Where the server will see the blade
-- ------------------------------------------------------------------------------------------

local art = Arts.byId(ART_ID)
check(art ~= nil, "the Art exists")
local clip = CombatService.clipById((art :: any).clip)
check(clip ~= nil, "the Art's clip loads")
local window = ClipSampler.hitWindows(clip :: any)[1]
check(window ~= nil, "the Art's clip has a hit window")
local trailStart, trailEnd = HitSweep.trailAttachments(standIn)
check(trailStart ~= nil and trailEnd ~= nil, "HitSweep finds the trail attachments under the stand-in")
local windowTimes = HitSweep.samplePath(clip :: any, window)
local path = HitSweep.bladePath(
	standIn,
	standInRoot.CFrame,
	clip :: any,
	windowTimes,
	trailStart :: Attachment,
	trailEnd :: Attachment
)
check(path ~= nil, "the server solves the blade through the stand-in's joints (Pose reaches the Weapon part)")

-- The blade against the boar through the window: the nearest boar part to the blade at each sample.
local nearestOverall = math.huge
for _, sample in path :: { HitSweep.BladeSample } do
	local nearestName, nearestDistance = "none", math.huge
	for _, part in boarModel:GetDescendants() do
		if part:IsA("BasePart") then
			local distance = HitSweep.segmentBoxDistance(sample.start, sample.finish, part.CFrame, part.Size)
			if distance < nearestDistance then
				nearestName, nearestDistance = part.Name, distance
			end
		end
	end
	nearestOverall = math.min(nearestOverall, nearestDistance)
	print(
		("[combat.smoke] t=%.3f guard %s tip %s nearest boar part %s at %.2f studs"):format(
			sample.time,
			fmt(sample.start),
			fmt(sample.finish),
			nearestName,
			nearestDistance
		)
	)
end
check(
	nearestOverall <= Combat.hitSphereRadius,
	("the blade comes within the hit radius of the boar inside the window (nearest %.2f studs)"):format(nearestOverall)
)

-- ------------------------------------------------------------------------------------------
-- The Art
-- ------------------------------------------------------------------------------------------

local landed: { any } = {}
local handAtStrike: { boolean } = {}
CombatService.HitLanded:Connect(function(hit)
	table.insert(landed, hit)
	-- The server sweeps the sword in the hand: its motor never moves to the back mount.
	table.insert(handAtStrike, (gripMotor :: Motor6D).Part0 == standInHand)
end)
local ended = false
CombatService.ArtEnded:Connect(function(record)
	if record.id == playerId then
		ended = true
	end
end)

local hpBefore = EntityService.get(boarId).hp
check(standIn:GetAttribute("Drawn") == false, "Drawn is false before the Horizontal")
local ok, reason = CombatService.beginArt(playerId, ART_ID, standInRoot.CFrame.LookVector)
check(ok, if ok then "beginArt accepted the Horizontal" else "beginArt refused the Horizontal: " .. tostring(reason))
check(EntityService.get(playerId).state == "Art", "the stand-in is in the Art state")
check(standIn:GetAttribute("Drawn") == true, "Drawn turns true as the Horizontal starts (a draw-cut)")

-- A scripted client mashing the Art while the first one runs: every repeat is refused.
local refusedWith: { [string]: number } = {}
local accepted = 0
for _ = 1, SPAM_COUNT do
	local again, why = CombatService.beginArt(playerId, ART_ID, standInRoot.CFrame.LookVector)
	if again then
		accepted += 1
	else
		local key = tostring(why)
		refusedWith[key] = (refusedWith[key] or 0) + 1
	end
end
local reasons: { string } = {}
for key, count in refusedWith do
	table.insert(reasons, ("%s x%d"):format(key, count))
end
table.sort(reasons)
check(
	accepted == 0,
	("all %d repeats of the Art while it runs are refused (%s)"):format(SPAM_COUNT, table.concat(reasons, ", "))
)

local elapsed = 0
while #landed == 0 and elapsed < HIT_TIMEOUT do
	elapsed += task.wait()
end
check(#landed >= 1, "HitLanded fired inside the hit window")
check(landed[1].targetId == boarId, "the hit landed on the boar")
check(landed[1].attackerId == playerId, "the hit came from the stand-in")
check(handAtStrike[1] == true, "the server's Weapon Motor6D was on the RightHand at the strike")
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
check(#landed == 1, ("the Horizontal landed once, the spam added nothing (%d hits)"):format(#landed))
check(EntityService.get(playerId).state == "PostMotion", "the stand-in is held in PostMotion")
check(standIn:GetAttribute("Drawn") == true, "the sword stays drawn through the post-motion")
task.wait(Combat.postMotionMin + 0.5)
check(EntityService.get(playerId).state == "Idle", "post-motion released the body")
check(standIn:GetAttribute("Drawn") == true, "the sword is still drawn right after the post-motion")
check((gripMotor :: Motor6D).Part0 == standInHand, "the server's Weapon Motor6D is still on the RightHand")

-- With no more combat, the tag runs out and the server says the sword goes back on the back.
local idleFor = 0
while standIn:GetAttribute("Drawn") == true and idleFor < Combat.combatTagDuration + SHEATHE_SLACK do
	idleFor += task.wait(POLL_SECONDS)
end
check(
	standIn:GetAttribute("Drawn") == false,
	("Drawn turns false once the combat tag runs out (%.1f s after the post-motion)"):format(idleFor)
)
check(
	idleFor >= Combat.combatTagDuration - SHEATHE_SLACK,
	("the sword stayed drawn for the combat tag, about %.1f s (it went after %.1f s)"):format(
		Combat.combatTagDuration,
		idleFor
	)
)

-- ------------------------------------------------------------------------------------------
-- No remote lets a client report a hit (section 17: the server sweeps; clients only ask)
-- ------------------------------------------------------------------------------------------

local netFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Net")
check(netFolder ~= nil, "Net made its remotes folder in ReplicatedStorage")
local requests: { string } = {}
for name, definition in Remotes do
	if definition.direction == "ClientToServer" then
		table.insert(requests, name)
		check((netFolder :: Instance):FindFirstChild(name) ~= nil, "the " .. name .. " remote exists")
	end
end
table.sort(requests)
for _, name in requests do
	local lowered = name:lower()
	check(
		lowered:find("hit", 1, true) == nil and lowered:find("damage", 1, true) == nil,
		name .. " is a request, not a hit report"
	)
end
local forged = {
	artId = ART_ID,
	facing = { 0, 0, -1 },
	clientTime = 0,
	targetId = boarId,
	damage = 9999,
}
local forgedOk, forgedWhy = Net.validate("ArtRequest", forged)
check(not forgedOk, "an ArtRequest that carries a target and damage is refused (" .. tostring(forgedWhy) .. ")")
local honestOk, honestWhy = Net.validate("ArtRequest", { artId = ART_ID, facing = forged.facing, clientTime = 0 })
check(honestOk, "the same ArtRequest without them passes the schema (" .. tostring(honestWhy) .. ")")
print(("[combat.smoke] client-to-server remotes: %s"):format(table.concat(requests, ", ")))

print("[combat.smoke] all checks passed")
