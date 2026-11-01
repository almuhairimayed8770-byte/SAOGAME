--!strict
--[[
	Hands out of the enemy (items 331(a), 336(b), 338(b), 366; D-501). The PC saw the player's
	hands inside an enemy's body: 0.69-0.71 studs in a boar's torso on Horizontal and the Sharp Nail
	Final, 0.14-0.24 on the Sharp Nail Normals and Basic1, 0.055-0.43 beside a kobold's axe, and
	0.04-0.55 inside a kobold on first freeze frames. The reach (D-424) prices a hand together with
	the blade, so a blade that stays deep at every step (Basic1 at a side-on boar: 0.78 studs past
	its depth) left the hand 0.58 in, and nothing at all kept a hand out between two strike keys
	(a follow-through: Horizontal 0.31-0.41, Sharp Nail 0.54, Rising Arc 0.37).

	Every swing of the starter sword, Art and basic, from where the drawn body shell walks in to
	(WalkShell.hold, a kobold square on and a boar side-on), through the real plan
	(ContactPredictor.standOff with the keep-out), the real Mixer (hit-stops from the real
	predictor's contacts) and the real clips, at 30, 60, 144 and 240 Hz: no hand or arm stands
	deeper than keepOut.depthEpsilon (plus the same again for a frame read between two samples)
	in any of the enemy's body parts on any frame, and every cut still lands.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Enemies = Harness.load("src/shared/data/enemies")
local Arts = Harness.load("src/shared/data/arts")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local Weapons = Harness.load("src/shared/data/weapons")
local Playground = Harness.load("src/shared/data/playground")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local AimLogic = Harness.load("src/client/controllers/AimLogic")
local WalkShell = Harness.load("src/client/controllers/WalkShell")
local Mixer = Harness.load("src/client/choreo/Mixer")

local STAND_OFF = Combat.contact.standOff
local KEEP_OUT = STAND_OFF.keepOut
local HOLD_FALLBACK = Combat.startPoseTime + Combat.activationHold
local RATES = { 30, 60, 144, 240 }
-- A frame between two samples reads the series on a straight line between them.
local DEEPEST = 2 * KEEP_OUT.depthEpsilon
local WALK_SPEED = 8

local root = Harness.repoRoot()
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end
local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
local avatar = HitMatrix.standing(Harness)
local WEAPON = Weapons.byId(Playground.loadout.weapon)

type Swing = { name: string, clip: any, art: any?, from: number }
local SWINGS: { Swing } = {}
for _, art in Arts.list("OneHandedSword") do
	local name = art.clip:match("[^/]+$")
	if fs.isFile(root .. "/src/shared/clips/player/OneHandedSword/" .. name .. ".luau") then
		local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
		table.insert(
			SWINGS,
			{ name = name, clip = clip, art = art, from = ActionLogic.holdClipTime(clip, HOLD_FALLBACK) }
		)
	end
end
for index = 1, 3 do
	local name = "Basic" .. index
	table.insert(
		SWINGS,
		{ name = name, clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name), art = nil, from = 0 }
	)
end

local sizes: { [string]: Vector3 } = {}
for _, part in avatar.model:GetDescendants() do
	if part:IsA("BasePart") then
		sizes[part.Name] = part.Size
	end
end

-- An enemy in its rest pose with its blockers, its root at `frame`.
local function placeAt(enemyId: string, frame: CFrame): Model
	local def = Enemies.byId(enemyId)
	local model = RigBuilder.build(def.skin)
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	RigBuilder.addBlocker(model)
	-- The blockers collide with players (CollisionGroups; the stand-in engine has no groups).
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and (child.Name == KEEP_OUT.bodyFace or child.Name == KEEP_OUT.heldFace) then
			child.CanCollide = true
		end
	end
	return model
end

local function boxDepth(a: CFrame, aSize: Vector3, b: CFrame, bSize: Vector3): number
	local aAxes = { a.RightVector, a.UpVector, a.LookVector }
	local bAxes = { b.RightVector, b.UpVector, b.LookVector }
	local aHalf = { aSize.X / 2, aSize.Y / 2, aSize.Z / 2 }
	local bHalf = { bSize.X / 2, bSize.Y / 2, bSize.Z / 2 }
	local between = b.Position - a.Position
	local axes = table.clone(aAxes)
	for _, axis in bAxes do
		table.insert(axes, axis)
	end
	for _, u in aAxes do
		for _, v in bAxes do
			local cross = u:Cross(v)
			if cross.Magnitude > 1e-6 then
				table.insert(axes, cross.Unit)
			end
		end
	end
	local least = math.huge
	for _, axis in axes do
		local ra, rb = 0, 0
		for i = 1, 3 do
			ra += math.abs(aAxes[i]:Dot(axis)) * aHalf[i]
			rb += math.abs(bAxes[i]:Dot(axis)) * bHalf[i]
		end
		least = math.min(least, ra + rb - math.abs(between:Dot(axis)))
	end
	return least
end

-- The deepest hand or arm in any of the enemy's body parts (what a blade may wound).
local function limbDepth(hurt: { BasePart }, rootFrame: CFrame, offsets: any): (number, string)
	local solved = Pose.solve(avatar.model, rootFrame, offsets)
	local worst, where = -math.huge, ""
	for _, name in KEEP_OUT.limbs do
		local frame = solved[name]
		if frame == nil then
			continue
		end
		local radius = sizes[name].Magnitude / 2
		for _, part in hurt do
			if (part.CFrame.Position - frame.Position).Magnitude > radius + part.Size.Magnitude / 2 then
				continue
			end
			local depth = boxDepth(frame, sizes[name], part.CFrame, part.Size)
			if depth > worst then
				worst, where = depth, name .. " in " .. part.Name
			end
		end
	end
	return worst, where
end

-- Where the drawn body shell walks in to, straight at the enemy's root from 10 studs (-Z).
local function restOf(enemy: Model, enemyRoot: Vector3, lateral: number): CFrame
	local toward = Vector3.new(0, 0, -1)
	local start = Vector3.new(enemyRoot.X + lateral, avatar.base.Position.Y, enemyRoot.Z + 10)
	local at = CFrame.lookAt(start, start + toward)
	for _ = 1, 900 do
		local direction, share =
			WalkShell.hold(avatar.model, { CFrame = at } :: any, toward, WALK_SPEED / 60, true, { { model = enemy } })
		if share <= 0 or direction.Magnitude < 1e-6 then
			break
		end
		local move = Vector3.new(direction.X, 0, direction.Z).Unit * (WALK_SPEED / 60) * share
		if move.Magnitude < 1e-4 then
			break
		end
		at += move
	end
	return at
end

type Result = { depth: number, where: string, hits: number }

-- One swing at `fps` from `rest`: the deepest limb on any frame and the cuts that landed.
local function swingAt(enemyId: string, enemyFrame: CFrame, rest: CFrame, fps: number, swing: Swing): Result
	local model = placeAt(enemyId, enemyFrame)
	local hurt: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and BladeContact.hurtbox(part) then
			table.insert(hurt, part)
		end
	end
	avatar.root.CFrame = rest
	local plan = ContactPredictor.standOff(
		avatar.model,
		swing.clip,
		swing.from,
		rest,
		model,
		nil,
		{ keepOut = true, step = swing.art ~= nil }
	)
	local records = {
		{ id = 1, model = avatar.model, kind = "Player", state = "Art", weaponId = WEAPON.id },
		{ id = 5, model = model, kind = "Enemy", state = "Idle", hp = 1e6, maxHp = 1e6 },
	}
	local predictor = ContactPredictor.new({
		targets = function()
			return records
		end,
	})
	local mixer = Mixer.new()
	local handle = mixer:play(swing.clip)
	if swing.from > 0 then
		mixer:seek(handle, swing.from)
	end
	local art = swing.art
	assert(predictor:begin({
		model = avatar.model,
		clip = swing.clip,
		artId = if art ~= nil then art.id else nil,
		finalHit = art ~= nil,
		multiplier = if art ~= nil then art.multiplier else Combat.basicAttackMultiplier,
		weaponAttack = WEAPON.attack,
	}))
	local carried = rest
	local result: Result = { depth = -math.huge, where = "", hits = 0 }
	for _ = 1, math.ceil(swing.clip.duration * fps) + 120 do
		local stepped = mixer:step(1 / fps)
		for _, joint in Joints.list(avatar.model) do
			local offset = stepped.offsets[joint.Name]
			joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
		end
		local delta = stepped.rootDelta
		carried += Vector3.new(delta[1], delta[2], delta[3])
		local time = handle.time
		local frame = carried
		if plan ~= nil then
			local back = AimLogic.standOffAt(plan.distance, plan.from, plan.to, time, STAND_OFF.easing)
				+ (if plan.keep ~= nil then plan.keep(time) else 0)
			frame += plan.away * back
			if plan.side ~= nil and plan.keepSide ~= nil then
				frame += plan.side * plan.keepSide(time)
			end
		end
		avatar.root.CFrame = frame
		for _, contact in predictor:step(time) do
			result.hits += 1
			mixer:holdSteps(Combat.hitStopFrames[contact.tier] * fps / 60)
		end
		local depth, where = limbDepth(hurt, frame, stepped.offsets)
		if depth > result.depth then
			result.depth, result.where = depth, ("%s at %.3f s"):format(where, time)
		end
		if handle.done then
			break
		end
	end
	predictor:stop()
	model:Destroy()
	return result
end

-- The root's height above the floor for an enemy's rig, as a spawn stands it.
local function rootHeightOf(enemyId: string): number
	local rig = Rigs[Enemies.byId(enemyId).skin]
	local rootSize = (rig.parts :: any)[rig.rootPart].size[2]
	return PlaygroundLayout.rootHeight(rig.hipHeight, rootSize, World.spawn.groundEpsilon)
end

local function check(label: string, enemyId: string, enemyFrame: CFrame, lateral: number)
	local probe = placeAt(enemyId, enemyFrame)
	local rest = restOf(probe, enemyFrame.Position, lateral)
	probe:Destroy()
	local worst, worstAt = -math.huge, ""
	for _, swing in SWINGS do
		local windows = #ClipSampler.hitWindows(swing.clip)
		for _, fps in RATES do
			local result = swingAt(enemyId, enemyFrame, rest, fps, swing)
			if result.depth > worst then
				worst, worstAt = result.depth, ("%s %d Hz: %s"):format(swing.name, fps, result.where)
			end
			if result.depth > DEEPEST or result.hits ~= windows then
				error(
					("%s, %s at %d Hz: a limb %.3f studs deep (%s), %d of %d cuts landed"):format(
						label,
						swing.name,
						fps,
						result.depth,
						result.where,
						result.hits,
						windows
					)
				)
			end
		end
	end
	print(
		("[hands out] %s (rest %.2f studs from its root): deepest limb %.3f (%s)"):format(
			label,
			(Vector3.new(rest.Position.X, 0, rest.Position.Z) - Vector3.new(
				enemyFrame.Position.X,
				0,
				enemyFrame.Position.Z
			)).Magnitude,
			worst,
			worstAt
		)
	)
end

describe("no hand or arm goes into an enemy's body on any frame (items 331(a), 336(b), 366; D-501)", function()
	it("at a kobold square on, from where the drawn shell walks in to", function()
		local frame = CFrame.new(0, rootHeightOf("KoboldAxeman"), -20) * CFrame.Angles(0, math.pi, 0)
		check("kobold square on", "KoboldAxeman", frame, 0)
	end)

	it("at a side-on boar, from where the drawn shell walks in to, square on its middle and a stud off", function()
		local frame = CFrame.new(0, rootHeightOf("FrenzyBoar"), -20) * CFrame.Angles(0, math.rad(90), 0)
		check("side-on boar", "FrenzyBoar", frame, 0)
		check("side-on boar, a stud off", "FrenzyBoar", frame, 1)
	end)
end)
