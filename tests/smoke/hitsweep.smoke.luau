--!strict
--[[
	Hit sweep smoke (run-in-roblox, Playground place): the engine half of the server hit sweep
	(section 6, D-010), with nothing between HitSweep and the engine (no injected caster or broad
	phase). Plain Luau run on the server after Main has started everything.

	1. Engine facts, printed so the docs can quote what this Studio build does: whether
	   workspace:Spherecast reports a part the sphere starts inside (the engine documentation says it
	   never does), whether one whose sphere starts overlapping a face reports it, what very short
	   and zero-length casts do, whether workspace:GetPartBoundsInRadius reports a colliding part
	   whose CanQuery is off, and that it reports the part around its center. A cast that enters a
	   part must report it and the bounds query must find the part (and skip it once CanQuery and
	   CanCollide are both off): everything below rests on those, so they are asserted.
	2. A blade that opens its window buried in a boar registers once. The swordsman is built here
	   with Motor6D joints (the rigs.luau PlayerR15 joints), so this smoke does not depend on how the
	   engine builds a character's joints; it holds the Trialist Sword from WeaponBuilder. The
	   Horizontal's blade path comes from HitSweep.bladePath, and a Frenzy Boar from RigBuilder is
	   placed with its body around the whole blade at the window's open. castBladePath over the
	   window reports the boar exactly once and never the swordsman.
	3. A boar that steps onto a resting blade registers on the next sample.
	4. A blade buried in a pillar (a plain anchored Part, not a fighter) registers nothing.

	Everything happens in the air above the field (ARENA), so the field and the player spawn pad
	stay out of every query; everything it builds is destroyed at the end.

	Run: tools/smoke.sh hitsweep (installs this file as a server Script in a Run session of the
	Playground; see tools/smoke/SmokeRunner.luau). Errors on the first failed assertion, which the
	runner reports as SMOKE-RESULT: FAIL. Must not return at top level. Not runnable under Lune.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Weapons = require(Shared.data.weapons)
local Arts = require(Shared.data.arts)
local Rigs = require(Shared.data.rigs)
local Playground = require(Shared.data.playground)
local ClipSampler = require(Shared.choreo.ClipSampler)
local CombatService = require(Server.services.CombatService)
local HitSweep = require(Server.combat.HitSweep)

local PREFIX = "[hitsweep.smoke]"
local READY_ATTRIBUTE = "SkyspireReady"
local READY_TIMEOUT = 15
local ART_ID = "OneHandedSword.Horizontal"
local ARENA = Vector3.new(0, 60, 40) -- the swordsman's root: open air, nothing else within reach
local PROBE_OFFSET = Vector3.new(30, 0, 0) -- the engine-facts part, well clear of the swordsman
local PROBE_SIZE = 4
local PROBE_RADIUS = 0.5
local SHORT_CASTS = { 1e-3, 1e-5, 1e-6 } -- studs
local AWAY = Vector3.new(0, 0, -40) -- where the boar waits before it steps onto the blade
local PILLAR_SIZE = Vector3.new(3, 3, 6)
local BOAR_ID = 1
local SWORDSMAN_ID = 2

-- Approximate R15 part sizes; the sweep only needs the joints, the sizes keep the body honest.
local PART_SIZES: { [string]: Vector3 } = {
	HumanoidRootPart = Vector3.new(2, 2, 1),
	LowerTorso = Vector3.new(2, 0.4, 1),
	UpperTorso = Vector3.new(2, 1.6, 1),
	Head = Vector3.new(1.2, 1.2, 1.2),
	LeftUpperArm = Vector3.new(1, 1.2, 1),
	RightUpperArm = Vector3.new(1, 1.2, 1),
	LeftLowerArm = Vector3.new(1, 1.1, 1),
	RightLowerArm = Vector3.new(1, 1.1, 1),
	LeftHand = Vector3.new(1, 0.3, 1),
	RightHand = Vector3.new(1, 0.3, 1),
	LeftUpperLeg = Vector3.new(1, 1.2, 1),
	RightUpperLeg = Vector3.new(1, 1.2, 1),
	LeftLowerLeg = Vector3.new(1, 1.2, 1),
	RightLowerLeg = Vector3.new(1, 1.2, 1),
	LeftFoot = Vector3.new(1, 0.3, 1),
	RightFoot = Vector3.new(1, 0.3, 1),
}

local function check(condition: boolean, message: string)
	if not condition then
		error(PREFIX .. " FAILED: " .. message, 0)
	end
	print(PREFIX .. " ok: " .. message)
end

local function fmt(v: Vector3): string
	return ("(%.2f, %.2f, %.2f)"):format(v.X, v.Y, v.Z)
end

local function describeResult(result: RaycastResult?): string
	if result == nil then
		return "nil"
	end
	return result.Instance:GetFullName()
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

local created: { Instance } = {}

-- ------------------------------------------------------------------------------------------
-- 1. Engine facts
-- ------------------------------------------------------------------------------------------

local probe = Instance.new("Part")
probe.Name = "SweepProbe"
probe.Anchored = true
probe.Size = Vector3.one * PROBE_SIZE
probe.CFrame = CFrame.new(ARENA + PROBE_OFFSET)
probe.Parent = workspace
table.insert(created, probe)
local center = probe.Position
local forward = Vector3.new(0, 0, -1)
-- A sphere whose center is outside the part but whose surface already overlaps its +Z face.
local grazingOrigin = center + Vector3.new(0, 0, PROBE_SIZE / 2 + PROBE_RADIUS / 2)

local fromInside = workspace:Spherecast(center, PROBE_RADIUS, forward)
print(
	("%s engine: a Spherecast that starts inside a part reports it: %s (result %s)"):format(
		PREFIX,
		tostring(fromInside ~= nil and fromInside.Instance == probe),
		describeResult(fromInside)
	)
)
local grazing = workspace:Spherecast(grazingOrigin, PROBE_RADIUS, forward)
print(
	("%s engine: a Spherecast whose sphere starts overlapping a face reports it: %s (result %s)"):format(
		PREFIX,
		tostring(grazing ~= nil and grazing.Instance == probe),
		describeResult(grazing)
	)
)
for _, length in SHORT_CASTS do
	local castOk, result = pcall(function(): RaycastResult?
		return workspace:Spherecast(grazingOrigin, PROBE_RADIUS, forward * length)
	end)
	print(
		("%s engine: a %g-stud Spherecast from that overlapping start %s"):format(
			PREFIX,
			length,
			if castOk then "returns " .. describeResult(result) else "throws: " .. tostring(result)
		)
	)
end
local zeroOk, zeroResult = pcall(function(): RaycastResult?
	return workspace:Spherecast(grazingOrigin, PROBE_RADIUS, Vector3.zero)
end)
print(
	("%s engine: a zero-length Spherecast %s"):format(
		PREFIX,
		if zeroOk then "returns " .. describeResult(zeroResult) else "throws: " .. tostring(zeroResult)
	)
)

local entering =
	workspace:Spherecast(center + Vector3.new(0, 0, PROBE_SIZE * 2), PROBE_RADIUS, forward * PROBE_SIZE * 2)
check(entering ~= nil and entering.Instance == probe, "a Spherecast that enters a part reports it")
local around = workspace:GetPartBoundsInRadius(center, PROBE_RADIUS)
check(table.find(around, probe) ~= nil, "GetPartBoundsInRadius reports the part around its center")
probe.CanQuery = false
probe.CanCollide = false
local hidden = workspace:GetPartBoundsInRadius(center, PROBE_RADIUS)
check(table.find(hidden, probe) == nil, "GetPartBoundsInRadius skips a part with CanQuery and CanCollide off")
-- HitSweep treats a colliding part as queryable whatever its CanQuery says (the documented rule:
-- CanQuery takes effect only when CanCollide is off); print what this build does.
probe.CanCollide = true
local colliding = workspace:GetPartBoundsInRadius(center, PROBE_RADIUS)
print(
	("%s engine: GetPartBoundsInRadius reports a part with CanQuery off and CanCollide on: %s"):format(
		PREFIX,
		tostring(table.find(colliding, probe) ~= nil)
	)
)
probe.CanCollide = false

-- ------------------------------------------------------------------------------------------
-- 2. A blade that opens its window buried in a boar
-- ------------------------------------------------------------------------------------------

-- A swordsman on Motor6Ds from the rigs.luau PlayerR15 joints (C1 at each part's center), its
-- root anchored at `rootCFrame`; WeaponBuilder adds the Weapon joint.
local function buildSwordsman(rootCFrame: CFrame): Model
	local rig = Rigs.PlayerR15
	local model = Instance.new("Model")
	model.Name = "SweepSwordsman"
	local parts: { [string]: BasePart } = {}
	local function part(name: string): BasePart
		local existing = parts[name]
		if existing ~= nil then
			return existing
		end
		local made = Instance.new("Part")
		made.Name = name
		made.Size = PART_SIZES[name] or Vector3.one
		made.CanCollide = false
		made.Massless = true
		made.CFrame = rootCFrame
		made.Parent = model
		parts[name] = made
		return made
	end
	local root = part(rig.rootPart)
	root.Anchored = true
	root.Massless = false
	model.PrimaryPart = root
	for _, joint in rig.joints do
		if joint.part1 ~= "Weapon" then
			local motor = Instance.new("Motor6D")
			motor.Name = joint.name
			motor.Part0 = part(joint.part0)
			motor.Part1 = part(joint.part1)
			motor.C0 = RigBuilder.frameOf(joint.c0)
			motor.C1 = CFrame.identity
			motor.Parent = motor.Part1
		end
	end
	model.Parent = workspace
	return model
end

local swordsman = buildSwordsman(CFrame.new(ARENA))
table.insert(created, swordsman)
local weaponDef = Weapons.byId(Playground.loadout.weapon)
check(weaponDef ~= nil, "the loadout weapon exists")
WeaponBuilder.equip(swordsman, weaponDef :: any)
local trailStart, trailEnd = HitSweep.trailAttachments(swordsman)
check(trailStart ~= nil and trailEnd ~= nil, "the swordsman's weapon carries TrailStart and TrailEnd")

local art = Arts.byId(ART_ID)
check(art ~= nil, "the Art exists")
local clip = CombatService.clipById((art :: any).clip)
check(clip ~= nil, "the Art's clip loads")
local window = ClipSampler.hitWindows(clip :: any)[1]
check(window ~= nil, "the Art's clip has a hit window")
local times = HitSweep.samplePath(clip :: any, window)
local solved = HitSweep.bladePath(
	swordsman,
	(swordsman.PrimaryPart :: BasePart).CFrame,
	clip :: any,
	times,
	trailStart :: Attachment,
	trailEnd :: Attachment
)
check(solved ~= nil and #(solved :: any) == #times, "the blade path solves through the swordsman's Motor6Ds")
local path = solved :: { HitSweep.BladeSample }
local opening = path[1]
print(
	("%s blade at the window's open (t=%.3f): guard %s tip %s"):format(
		PREFIX,
		opening.time,
		fmt(opening.start),
		fmt(opening.finish)
	)
)

-- The boar's root on the blade: its center on the blade's midpoint, its long axis (5 studs, the
-- blade is shorter) along the blade, so the whole blade is inside its body.
local boar = RigBuilder.build("Boar", "SweepBoar")
table.insert(created, boar)
local boarRoot = boar.PrimaryPart :: BasePart
boar.Parent = workspace
boarRoot.Anchored = true
local buried = CFrame.lookAt(opening.mid, opening.finish)
boar:PivotTo(buried)
local function inside(point: Vector3): boolean
	return HitSweep.segmentBoxDistance(point, point, boarRoot.CFrame, boarRoot.Size) == 0
end
check(
	inside(opening.start) and inside(opening.finish),
	"the whole blade lies inside the boar's body when the window opens"
)

local fighters: { [Instance]: number } = { [boar] = BOAR_ID, [swordsman] = SWORDSMAN_ID }
local function resolve(instance: Instance): (number?, Model?)
	local node: Instance? = instance
	while node ~= nil do
		local id = fighters[node]
		if id ~= nil then
			return id, node :: Model
		end
		node = node.Parent
	end
	return nil, nil
end
local function noOverlap(): { BasePart }
	return {}
end
local function idsOf(hits: { HitSweep.Hit }): string
	local ids = {}
	for _, hit in hits do
		table.insert(ids, ("%d at %s"):format(hit.targetId, fmt(hit.position)))
	end
	return if #ids == 0 then "none" else table.concat(ids, ", ")
end

local castsOnly = HitSweep.castBladePath(path, { exclude = { swordsman }, resolve = resolve, overlap = noOverlap })
print(("%s the engine's casts alone over the window find: %s"):format(PREFIX, idsOf(castsOnly)))
local hits = HitSweep.castBladePath(path, { exclude = { swordsman }, resolve = resolve })
print(("%s the default sweep over the window finds: %s"):format(PREFIX, idsOf(hits)))
check(#hits == 1 and hits[1].targetId == BOAR_ID, "the default sweep registers the boar the blade starts inside, once")
for _, hit in hits do
	check(hit.targetId ~= SWORDSMAN_ID, "the swordsman's own body and weapon never register")
end

-- ------------------------------------------------------------------------------------------
-- 3. A boar that steps onto a resting blade
-- ------------------------------------------------------------------------------------------

boar:PivotTo(buried + AWAY)
task.wait()
local alreadyHit: { [number]: boolean } = {}
local before = HitSweep.castBladePath({ opening }, {
	exclude = { swordsman },
	resolve = resolve,
	alreadyHit = alreadyHit,
})
check(#before == 0, "nothing touches the resting blade while the boar is away")
boar:PivotTo(buried)
task.wait()
local after = HitSweep.castBladePath({ opening, opening }, {
	exclude = { swordsman },
	resolve = resolve,
	alreadyHit = alreadyHit,
	continued = true,
})
print(("%s after the boar steps onto the resting blade: %s"):format(PREFIX, idsOf(after)))
check(#after == 1 and after[1].targetId == BOAR_ID, "a boar that steps onto the resting blade registers")

-- ------------------------------------------------------------------------------------------
-- 4. A blade buried in a pillar
-- ------------------------------------------------------------------------------------------

boar:PivotTo(buried + AWAY)
local pillar = Instance.new("Part")
pillar.Name = "SweepPillar"
pillar.Anchored = true
pillar.Size = PILLAR_SIZE
pillar.CFrame = buried
pillar.Parent = workspace
table.insert(created, pillar)
task.wait()
local walled = HitSweep.castBladePath(path, { exclude = { swordsman }, resolve = resolve })
print(("%s with the blade buried in a pillar: %s"):format(PREFIX, idsOf(walled)))
check(#walled == 0, "a pillar the blade is buried in is never a hit")

for _, instance in created do
	instance:Destroy()
end

print(PREFIX .. " all checks passed")
