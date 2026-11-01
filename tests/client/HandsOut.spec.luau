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
	in any of the enemy's parts on any frame, and every cut still lands.

	Item 409: the enemy's parts include what it holds, as the PC's logger reads them (the kobold's
	axe, its Weapon part). The keep-out holds the hands out of the body only (D-501); from where a
	walk can stand no swing needs more, which the idling case pins: a held kobold idles on through
	the swing, carrying its axe up to 0.5 studs on. The PC's hand in the axe came from the gate
	shots' 3.5-stud staging, nearer than the shell lets a walk stand (see docs, item 409).

	D-518: the gate shots' kobold (shots 2 to 5 and 9) is staged where DevStage puts it
	(DevStageLogic.placeStaged on the shot's own data), the body locked on it (turned to its root),
	the kobold idling from any phase of its loop: from the take's start through its swing at 60 Hz,
	no hand or arm goes more than wallGapStuds into the kobold or its axe, every cut lands, and the
	shot's Side view still frames both bodies. Its turn is the drawn walk-in's, and it never stands
	nearer than a walk-in rests.
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

-- Poses an enemy's rig with its root at `frame`: its rest pose, or its Idle at `idleTime`.
local function poseAt(model: Model, frame: CFrame, idle: any?, idleTime: number?)
	local offsets = if idle ~= nil and idleTime ~= nil then ClipSampler.sample(idle, idleTime % idle.duration) else {}
	for name, solved in Pose.solve(model, frame, offsets) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
end

-- The Idle clip an enemy's rig stands in (its blocker's loop), nil for none.
local function idleOf(enemyId: string): any?
	local rig = Rigs[Enemies.byId(enemyId).skin]
	local id = if rig.blocker ~= nil then rig.blocker.clips[1] else nil
	return if id ~= nil then Harness.load("src/shared/clips/" .. id) else nil
end

-- An enemy in its rest pose (or its Idle at `idleTime`) with its blockers, its root at `frame`.
local function placeAt(enemyId: string, frame: CFrame, idleTime: number?): Model
	local def = Enemies.byId(enemyId)
	local model = RigBuilder.build(def.skin)
	poseAt(model, frame, idleOf(enemyId), idleTime)
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

-- The deepest hand or arm in any of `parts` of the enemy.
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

-- The deepest limb in the body, and in what the enemy holds (counted only while it idles: the
-- rest pose is what the server's sweeps read, never what a client draws an idling enemy in).
type Result = {
	depth: number,
	where: string,
	hits: number,
	heldDepth: number,
	heldWhere: string,
	contacts: { number },
}

-- One swing at `fps` from `rest`: the deepest limb on any frame and the cuts that landed. With
-- `idleTime` the enemy idles on from that clip time through the swing, as a held enemy does.
local function swingAt(
	enemyId: string,
	enemyFrame: CFrame,
	rest: CFrame,
	fps: number,
	swing: Swing,
	idleTime: number?
): Result
	local model = placeAt(enemyId, enemyFrame, idleTime)
	local idle = if idleTime ~= nil then idleOf(enemyId) else nil
	local hurt: { BasePart } = {}
	local held: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and BladeContact.hurtbox(part) then
			table.insert(hurt, part)
		elseif part:IsA("BasePart") and BladeContact.held(part) then
			table.insert(held, part)
		end
	end
	local elapsed = 0
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
	local result: Result =
		{ depth = -math.huge, where = "", hits = 0, heldDepth = -math.huge, heldWhere = "", contacts = {} }
	for _ = 1, math.ceil(swing.clip.duration * fps) + 120 do
		local stepped = mixer:step(1 / fps)
		elapsed += 1 / fps
		if idleTime ~= nil then
			poseAt(model, enemyFrame, idle, idleTime + elapsed)
		end
		for _, joint in Joints.list(avatar.model) do
			local offset = stepped.offsets[joint.Name]
			joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
		end
		-- The clip's root motion is in the root's own space.
		local delta = stepped.rootDelta
		carried += carried:VectorToWorldSpace(Vector3.new(delta[1], delta[2], delta[3]))
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
			table.insert(result.contacts, time)
			mixer:holdSteps(Combat.hitStopFrames[contact.tier] * fps / 60)
		end
		local depth, where = limbDepth(hurt, frame, stepped.offsets)
		if depth > result.depth then
			result.depth, result.where = depth, ("%s at %.3f s"):format(where, time)
		end
		if idleTime ~= nil and #held > 0 then
			local inHeld, whereHeld = limbDepth(held, frame, stepped.offsets)
			if inHeld > result.heldDepth then
				result.heldDepth, result.heldWhere = inHeld, ("%s at %.3f s"):format(whereHeld, time)
			end
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

local function check(label: string, enemyId: string, enemyFrame: CFrame, lateral: number, idleTime: number?)
	local probe = placeAt(enemyId, enemyFrame, idleTime)
	local rest = restOf(probe, enemyFrame.Position, lateral)
	probe:Destroy()
	local worst, worstAt = -math.huge, ""
	local worstHeld, worstHeldAt = -math.huge, ""
	for _, swing in SWINGS do
		local windows = #ClipSampler.hitWindows(swing.clip)
		for _, fps in RATES do
			local result = swingAt(enemyId, enemyFrame, rest, fps, swing, idleTime)
			if result.depth > worst then
				worst, worstAt = result.depth, ("%s %d Hz: %s"):format(swing.name, fps, result.where)
			end
			if result.heldDepth > worstHeld then
				worstHeld, worstHeldAt = result.heldDepth, ("%s %d Hz: %s"):format(swing.name, fps, result.heldWhere)
			end
			-- What it holds is no part of the keep-out (D-277: clash-only); from a walk-in rest a hand
			-- meets it no deeper than the walk shell itself lets a hand rest in it (wallGapStuds).
			if result.heldDepth > STAND_OFF.wallGapStuds then
				error(
					("%s, %s at %d Hz: a limb %.3f studs inside what the enemy holds (%s)"):format(
						label,
						swing.name,
						fps,
						result.heldDepth,
						result.heldWhere
					)
				)
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
			.. (if worstHeld > -math.huge then ("; in what it holds %.3f (%s)"):format(worstHeld, worstHeldAt) else "")
	)
end

describe("no hand or arm goes into an enemy's body on any frame (items 331(a), 336(b), 366; D-501)", function()
	it("at a kobold square on, from where the drawn shell walks in to", function()
		local frame = CFrame.new(0, rootHeightOf("KoboldAxeman"), -20) * CFrame.Angles(0, math.pi, 0)
		check("kobold square on", "KoboldAxeman", frame, 0)
	end)

	it("at a kobold square on idling its axe on through the swing, its axe counted (item 409)", function()
		local frame = CFrame.new(0, rootHeightOf("KoboldAxeman"), -20) * CFrame.Angles(0, math.pi, 0)
		-- From 2.3 s the idle's weight shift carries the axe 0.4 on through the swing (from 1.0 s it
		-- hangs still: -0.044 at its deepest).
		check("kobold square on, idling from 2.3 s", "KoboldAxeman", frame, 0, 2.3)
	end)

	it("at a side-on boar, from where the drawn shell walks in to, square on its middle and a stud off", function()
		local frame = CFrame.new(0, rootHeightOf("FrenzyBoar"), -20) * CFrame.Angles(0, math.rad(90), 0)
		check("side-on boar", "FrenzyBoar", frame, 0)
		check("side-on boar, a stud off", "FrenzyBoar", frame, 1)
	end)
end)

-- ------------------------------------------------------------------ the gate shots (D-518)

local Dev = Harness.load("src/shared/data/dev")
local DevStageLogic = Harness.load("src/server/dev/DevStageLogic")
local CameraMath = Harness.load("src/client/camera/CameraMath")
local CameraData = Harness.load("src/shared/data/camera")
local IDLE_DRAWN = Harness.load("src/shared/clips/player/OneHandedSword/IdleDrawn")
local TAKE_HZ = 60
-- The kobold's idle phases the take starts in (it idles from its spawn, so any of them).
local PHASES = 16
-- Where a lens point lands inside the frame, as a share of its half width and half height.
local IN_FRAME = 1
local ASPECT = 16 / 9

-- The capture shots that stage a held kobold for one swing: the four Arts and the kill.
local function gateShots(): { any }
	local list = {}
	for _, shot in Dev.capture.shots do
		local entry = shot.stage.enemies[1]
		local step = shot.perform[1]
		if
			#shot.stage.enemies == 1
			and entry.enemy == "KoboldAxeman"
			and entry.held
			and shot.stage.lock
			and #shot.perform == 1
			and (step.action == "BasicAttack" or step.action:match("^Art") ~= nil)
		then
			table.insert(list, shot)
		end
	end
	return list
end

-- The swing a shot presses (Art is slot 1, ArtSlotN slot N; BasicAttack the first basic), when it
-- goes down and when it is let go (an Art launches on its release).
local function swingOf(shot: any): (Swing, number, number)
	local step = shot.perform[1]
	if step.action == "BasicAttack" then
		for _, swing in SWINGS do
			if swing.name == "Basic1" then
				return swing, step.at, step.at
			end
		end
	end
	local slot = if step.action == "Art" then 1 else tonumber(step.action:match("^ArtSlot(%d)$"))
	local artId = Playground.loadout.artSlots[slot :: number]
	for _, swing in SWINGS do
		if swing.art ~= nil and swing.art.id == artId then
			return swing, step.at, step.at + step.hold
		end
	end
	error("no swing for " .. shot.id)
end

-- The shot staged as DevStage stages it around the matrix's body, and that body turned to the
-- kobold's root by the lock: the kobold's frame and the player's root.
local function staged(shot: any): (CFrame, CFrame)
	local entry = shot.stage.enemies[1]
	local base = avatar.base
	local facing = DevStageLogic.facingFrom(0, 0, base.LookVector.X, base.LookVector.Z) or 0
	local ex, ez, face =
		DevStageLogic.placeStaged(base.Position.X, base.Position.Z, facing, entry.side, entry.distance, entry.yaw)
	local enemyFrame = CFrame.new(ex, rootHeightOf(entry.enemy), ez) * CFrame.Angles(0, math.rad(face), 0)
	return enemyFrame, CFrame.lookAt(base.Position, Vector3.new(ex, base.Position.Y, ez))
end

type Take = { body: number, bodyAt: string, held: number, heldAt: string, lost: number, contacts: { string } }

-- Every frame of one shot's take, the kobold's idle starting at `phase`: the drawn idle until the
-- press, the swing's start pose (an Art's hold) until the release, then the swing itself.
local function take(shot: any, phase: number): Take
	local swing, press, release = swingOf(shot)
	local enemyId = shot.stage.enemies[1].enemy
	local enemyFrame, rest = staged(shot)
	local idle = idleOf(enemyId)
	local model = placeAt(enemyId, enemyFrame, phase)
	local hurt: { BasePart } = {}
	local held: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and BladeContact.hurtbox(part) then
			table.insert(hurt, part)
		elseif part:IsA("BasePart") and BladeContact.held(part) then
			table.insert(held, part)
		end
	end
	local result: Take = { body = -math.huge, bodyAt = "", held = -math.huge, heldAt = "", lost = 0, contacts = {} }
	for frame = 0, math.ceil(release * TAKE_HZ) - 1 do
		local t = frame / TAKE_HZ
		local offsets = if t < press
			then ClipSampler.sample(IDLE_DRAWN, t % IDLE_DRAWN.duration)
			else ClipSampler.sample(swing.clip, math.min(t - press, swing.from))
		poseAt(model, enemyFrame, idle, phase + t)
		local depth, where = limbDepth(hurt, rest, offsets)
		if depth > result.body then
			result.body, result.bodyAt = depth, ("%s standing at %.2f s"):format(where, t)
		end
		local inHeld, whereHeld = limbDepth(held, rest, offsets)
		if inHeld > result.held then
			result.held, result.heldAt = inHeld, ("%s standing at %.2f s"):format(whereHeld, t)
		end
	end
	model:Destroy()
	local swung = swingAt(enemyId, enemyFrame, rest, TAKE_HZ, swing, phase + release)
	if swung.depth > result.body then
		result.body, result.bodyAt = swung.depth, ("%s in %s"):format(swung.where, swing.name)
	end
	if swung.heldDepth > result.held then
		result.held, result.heldAt = swung.heldDepth, ("%s in %s"):format(swung.heldWhere, swing.name)
	end
	local windows = #ClipSampler.hitWindows(swing.clip)
	result.lost = windows - swung.hits
	for _, at in swung.contacts do
		table.insert(result.contacts, ("%.3f"):format(at))
	end
	return result
end

-- Where a point lands in a lens's frame: x and y as shares of the half width and half height.
local function inFrame(lens: CFrame, point: Vector3): (number, number, number)
	local local_ = lens:PointToObjectSpace(point)
	local depth = -local_.Z
	local half = math.tan(math.rad(CameraData.fov.rest / 2))
	return local_.X / (depth * half * ASPECT), local_.Y / (depth * half), depth
end

describe("the gate shots' kobold stands where a walk-in rests (item 409, D-518)", function()
	it("stages the turn a drawn walk-in leaves, never nearer than it rests", function()
		local shots = gateShots()
		expect(#shots).toBe(5)
		-- The walk-in: straight at a held kobold that faces it, until the drawn shell stops it.
		local frame = CFrame.new(0, rootHeightOf("KoboldAxeman"), -20) * CFrame.Angles(0, math.pi, 0)
		local probe = placeAt("KoboldAxeman", frame)
		local rest = restOf(probe, frame.Position, 0)
		probe:Destroy()
		local offset = frame:PointToObjectSpace(rest.Position)
		local restDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		-- How far round from the kobold's look the body rests, + to its left (facing convention).
		local bearing = math.deg(math.atan2(-offset.X, -offset.Z))
		print(
			("[gate] the drawn walk-in rests %.3f studs out, %.2f degrees on the kobold's left"):format(
				restDistance,
				bearing
			)
		)
		for _, shot in shots do
			local entry = shot.stage.enemies[1]
			-- Turned toward its own right by the walk-in's bearing: the player on its left, off the axe.
			expect(math.abs(-(entry.yaw or 0) - bearing)).toBeLessThan(0.5)
			expect(entry.side).toBe(0)
			expect(entry.distance >= restDistance - 1e-6).toBe(true)
			-- As DevStage stands it: the player that far round from its look.
			local enemyFrame, player = staged(shot)
			local seen = enemyFrame:PointToObjectSpace(player.Position)
			expect(math.deg(math.atan2(-seen.X, -seen.Z))).toBeCloseTo(-(entry.yaw or 0), 1e-3)
		end
	end)

	it("keeps every hand and arm out of the idling kobold and its axe, the take through, every cut landing", function()
		for _, shot in gateShots() do
			local worst: Take? = nil
			local worstPhase = 0
			local idle = idleOf(shot.stage.enemies[1].enemy)
			local cuts = ""
			for k = 0, PHASES - 1 do
				local phase = idle.duration * k / PHASES
				local result = take(shot, phase)
				if k == 0 then
					cuts = table.concat(result.contacts, ", ")
				end
				if result.lost > 0 then
					error(("%s, the kobold's idle from %.2f s: %d cuts lost"):format(shot.id, phase, result.lost))
				end
				if worst == nil or math.max(result.body, result.held) > math.max(worst.body, worst.held) then
					worst, worstPhase = result, phase
				end
			end
			local found = worst :: Take
			print(
				("[gate] %s: deepest in the kobold %.3f (%s), in its axe %.3f (%s), its idle from %.2f s; cuts at clip %s"):format(
					shot.id,
					found.body,
					found.bodyAt,
					found.held,
					found.heldAt,
					worstPhase,
					cuts
				)
			)
			if found.body > STAND_OFF.wallGapStuds or found.held > STAND_OFF.wallGapStuds then
				error(
					("%s: a hand or arm %.3f into the kobold (%s) and %.3f into its axe (%s)"):format(
						shot.id,
						found.body,
						found.bodyAt,
						found.held,
						found.heldAt
					)
				)
			end
		end
	end)

	it("the Side view still frames both bodies whole", function()
		for _, shot in gateShots() do
			local enemyFrame, player = staged(shot)
			local model = placeAt(shot.stage.enemies[1].enemy, enemyFrame)
			local view = Dev.capture.cameras[shot.camera]
			local function vec(v: Vector3): { number }
				return { v.X, v.Y, v.Z }
			end
			local function toVector(v: { number }): Vector3
				return Vector3.new(v[1], v[2], v[3])
			end
			local at, target = player.Position, enemyFrame.Position
			local anchor = CameraMath.stageAnchor(view.anchor, vec(at), vec(target))
			local reference = CameraMath.stageReference(view.reference, view.anchor, vec(at), vec(target), nil)
			assert(reference ~= nil, "the staged view has a reference")
			local bearing = (reference :: number) + shot.cameraSide * view.degrees
			local lens = CFrame.lookAt(
				toVector(CameraMath.twoShotCamera(anchor, bearing, view.distance, view.height)),
				toVector(CameraMath.twoShotLook(vec(at), vec(target), view.focusBias, view.lookHeight))
			)
			local most = 0
			for _, rig in { { model = avatar.model, root = player }, { model = model, root = nil :: CFrame? } } do
				local solved = if rig.root ~= nil then Pose.solve(rig.model, rig.root, {}) else nil
				for _, part in rig.model:GetDescendants() do
					if not part:IsA("BasePart") or part.Transparency >= 1 then
						continue
					end
					local frame = if solved ~= nil then solved[part.Name] else part.CFrame
					if frame == nil then
						continue
					end
					local half = part.Size / 2
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local x, y, depth =
									inFrame(lens, frame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
								expect(depth > 0).toBe(true)
								most = math.max(most, math.abs(x), math.abs(y))
							end
						end
					end
				end
			end
			model:Destroy()
			print(
				("[gate] %s: the %s view frames both bodies to %.2f of its half frame"):format(
					shot.id,
					shot.camera,
					most
				)
			)
			expect(most <= IN_FRAME).toBe(true)
		end
	end)
end)
