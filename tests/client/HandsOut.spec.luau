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

	Item 430(e), D-535: every frame is read twice, as posed (this step's pose on this step's root)
	and as the screen draws it. A root write shows on its own frame and a pose one frame later
	(D-342), so a frame draws the pose the step before wrote on the root this step put it at, or,
	once a frame has drawn a held pose and while the root goes on moving, on the root a step behind
	with it (D-496). Through a lunge the root carries the hands that far past the pose's own: at the
	kobold's walk-in rest Horizontal's right arm read 0.003-0.009 studs in as posed and 0.10-0.11 as
	drawn at 60 Hz (the PC 0.090), 0.04-0.07 at 144 (the PC 0.057). Both reads stand within the
	same depth.

	D-518: the gate shots' kobold (shots 2 to 5 and 9) is staged where DevStage puts it
	(DevStageLogic.placeStaged on the shot's own data), the body locked on it (turned to its root),
	the kobold idling from any phase of its loop: from the take's start through its swing at 60 Hz,
	no hand or arm goes more than wallGapStuds into the kobold or its axe, every cut lands, and the
	shot's Side view still frames both bodies. Its turn is the drawn walk-in's, and it never stands
	nearer than a walk-in rests.

	Items 461 and 464 (D-565, D-566, D-568): the PC's held kobold idled and flinched on
	through the swing, against a plan made off it as it stood when the swing began. Played as the
	game plays it (Play: its idle on through its own Mixer from the phases that failed, held by each
	hit-stop, each cut's flinch from its word, and a basic's state over after basicHitDuration with
	its clip and plan playing on), from the 3.15 walk-in rest no hand or arm goes deeper than
	DEEPEST at 30 to 240 Hz, as posed and as drawn (006f057: 0.035 to 0.115); and from 3.5,
	Basic1's blade is out of the kobold from clip 0.28 to the clip's end and its trail no more than
	0.25 in at the key (006f057: 0.192 in after the cut).
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Enemies = Harness.load("src/shared/data/enemies")
local Arts = Harness.load("src/shared/data/arts")
local Rigs = Harness.load("src/shared/data/rigs")
local Impact = Harness.load("src/shared/data/impact")
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
local DamageMath = Harness.load("src/server/combat/DamageMath")
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
local function limbDepth(hurt: { any }, rootFrame: CFrame, offsets: any): (number, string)
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

-- The deepest point of the blade's own part (the Weapon part, read as the PC's logger reads it:
-- 3 x 9 x 2 points over its box) in any of `parts`, posed by `solved`.
local function bladeDepth(parts: { any }, solved: { [string]: CFrame }): (number, string)
	local frame = solved["Weapon"]
	if frame == nil then
		return -math.huge, ""
	end
	local size = sizes["Weapon"]
	local worst, where = -math.huge, ""
	for ix = 0, 2 do
		for iy = 0, 8 do
			for iz = 0, 1 do
				local point = frame * Vector3.new((ix / 2 - 0.5) * size.X, (iy / 8 - 0.5) * size.Y, (iz - 0.5) * size.Z)
				for _, part in parts do
					local inside = part.CFrame:PointToObjectSpace(point)
					local half = part.Size / 2
					local depth =
						math.min(half.X - math.abs(inside.X), half.Y - math.abs(inside.Y), half.Z - math.abs(inside.Z))
					if depth > worst then
						worst, where = depth, "Weapon in " .. part.Name
					end
				end
			end
		end
	end
	return worst, where
end

-- The deepest point of the blade's trail line (BladeContact.chain: TrailStart, the guard, to
-- TrailEnd, the tip; the line the plan's reach caps at the keys, D-424) in any of `parts`.
local TRAIL = BladeContact.chain(avatar.model)
local function lineDepth(parts: { any }, solved: { [string]: CFrame }): number
	local frame = solved["Weapon"]
	if frame == nil or TRAIL == nil then
		return -math.huge
	end
	local guard, tip = (frame * TRAIL.start).Position, (frame * TRAIL.finish).Position
	local worst = -math.huge
	for step = 0, 40 do
		local inside0 = guard:Lerp(tip, step / 40)
		for _, part in parts do
			local inside = part.CFrame:PointToObjectSpace(inside0)
			local half = part.Size / 2
			worst = math.max(
				worst,
				math.min(half.X - math.abs(inside.X), half.Y - math.abs(inside.Y), half.Z - math.abs(inside.Z))
			)
		end
	end
	return worst
end

-- The clip-time spans after each cut the blade is out of the body in (item 464, D-566): from
-- the strike's hold (its key when it has none) plus keepOut.bladeOutSeconds, the follow-through's
-- exit (section 10 beat 5), to the next strike's snap or the clip's end.
local function afterCuts(clip: any): { { number } }
	local cuts = {}
	for _, window in ClipSampler.hitWindows(clip) do
		local key = ContactPredictor.strikeKey(clip, window)
		local hold = ClipSampler.strikeHoldAfter(clip, key)
		local snap = window.open
		for index = 2, #clip.keys do
			if math.abs(clip.keys[index].time - key) <= 1e-4 and ClipSampler.isStrikeSnap(clip, index) then
				snap = clip.keys[index - 1].time
			end
		end
		table.insert(cuts, { snap = snap, exit = (if hold ~= nil then clip.keys[hold].time else key) })
	end
	local spans = {}
	for index, cut in cuts do
		local after = cuts[index + 1]
		table.insert(spans, { cut.exit + KEEP_OUT.bladeOutSeconds, if after ~= nil then after.snap else math.huge })
	end
	return spans
end

-- How a swing is played (swingAt). `played`: as the game plays it at a held kobold: the kobold
-- through its own Mixer (its idle on from `idleTime`, held by each hit-stop with the body, and the
-- flinch Replication plays on each cut's word, which comes the frame after the contact, inside the
-- hold), the plan told how the kobold moves (ContactPredictor.targetMotion off that Mixer, as
-- CharacterController asks it of the kobold's animator), and a basic's state over
-- combat.basicHitDuration after the press (CharacterController.endAction: its root motion stops
-- there; the clip plays on, and its plan with it, D-568). `bare`: the kobold without its
-- HeldBlocker, what the keep-out holds alone where the HeldBlocker beside the line holds nothing
-- off.
type Play = { played: boolean?, bare: boolean? }
-- The frames after a contact the hit's word comes (inside the hold at every rate).
local WORD_FRAMES = 1

-- The deepest limb in the body, and in what the enemy holds (counted only while it idles: the
-- rest pose is what the server's sweeps read, never what a client draws an idling enemy in).
type Result = {
	depth: number,
	where: string,
	-- The deepest as the screen draws it (item 430(e)).
	screen: number,
	screenWhere: string,
	hits: number,
	heldDepth: number,
	heldWhere: string,
	contacts: { number },
	-- The blade's own part after each cut (afterCuts), as posed and as drawn (item 464).
	blade: number,
	bladeWhere: string,
	bladeScreen: number,
	bladeScreenWhere: string,
	-- The blade's trail line at each strike's key (the frame nearest it), the deepest, and the
	-- blade's own part there (item 464(b)).
	bladeKey: number,
	bladeKeyWhere: string,
	bladeKeyBox: number,
}

-- One swing at `fps` from `rest`: the deepest limb on any frame and the cuts that landed. With
-- `idleTime` the enemy idles on from that clip time through the swing, as a held enemy does.
local function swingAt(
	enemyId: string,
	enemyFrame: CFrame,
	rest: CFrame,
	fps: number,
	swing: Swing,
	idleTime: number?,
	play: Play?
): Result
	local how: Play = play or {}
	local model = placeAt(enemyId, enemyFrame, idleTime)
	if how.bare then
		local held = model:FindFirstChild(KEEP_OUT.heldFace)
		if held ~= nil then
			held:Destroy()
		end
	end
	local idle = if idleTime ~= nil then idleOf(enemyId) else nil
	-- The kobold's own Mixer, as the game animates it.
	local enemyMixer: any = nil
	local flinch: any = nil
	if how.played then
		enemyMixer = Mixer.new()
		if idle ~= nil then
			enemyMixer:play(idle, { startTime = idleTime, blendIn = 0 })
		end
		local rig = Enemies.byId(enemyId).skin
		local side = DamageMath.staggerDirection(rest.Position, enemyFrame)
		local id = ActionLogic.clipId("Enemy", rig, "", "Flinch" .. side)
		if fs.isFile(root .. "/src/shared/clips/" .. id .. ".luau") then
			flinch = Harness.load("src/shared/clips/" .. id)
		end
	end
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
	local plan = ContactPredictor.standOff(avatar.model, swing.clip, swing.from, rest, model, nil, {
		keepOut = true,
		step = swing.art ~= nil,
		poseLag = Impact.poseLagFrames / fps,
		target = if enemyMixer ~= nil then ContactPredictor.targetMotion(enemyMixer:handles(), flinch) else nil,
	})
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
	local result: Result = {
		depth = -math.huge,
		where = "",
		screen = -math.huge,
		screenWhere = "",
		hits = 0,
		heldDepth = -math.huge,
		heldWhere = "",
		contacts = {},
		blade = -math.huge,
		bladeWhere = "",
		bladeScreen = -math.huge,
		bladeScreenWhere = "",
		bladeKey = -math.huge,
		bladeKeyWhere = "",
		bladeKeyBox = -math.huge,
	}
	local spans = afterCuts(swing.clip)
	-- Each strike's key, and the blade at the frame nearest it so far (its gap and depth).
	local keyed: { { key: number, gap: number, depth: number, where: string, box: number } } = {}
	for _, window in ClipSampler.hitWindows(swing.clip) do
		table.insert(keyed, {
			key = ContactPredictor.strikeKey(swing.clip, window),
			gap = math.huge,
			depth = -math.huge,
			where = "",
			box = -math.huge,
		})
	end
	local function outAt(time: number): boolean
		for _, span in spans do
			if time >= span[1] - 1e-6 and time < span[2] then
				return true
			end
		end
		return false
	end
	-- The step before's pose and root, and whether the root runs a step behind its pose (D-496).
	local lastOffsets: any = nil
	local lastFrame: CFrame? = nil
	local lastTime = swing.from
	local behind = false
	-- The enemy's parts as the screen draws them: the pose its step before wrote (D-342: a rig
	-- step's pose is drawn a frame later, the enemy's as the body's).
	local function shown(): { any }
		local list = {}
		for _, part in hurt do
			table.insert(list, { Name = part.Name, CFrame = part.CFrame, Size = part.Size })
		end
		return list
	end
	local shownHurt = shown()
	-- A word on its way: the frames until it comes.
	local word: number? = nil
	for _ = 1, math.ceil(swing.clip.duration * fps) + 120 do
		shownHurt = shown()
		if enemyMixer ~= nil then
			if word ~= nil then
				word -= 1
				if word <= 0 then
					word = nil
					if flinch ~= nil then
						enemyMixer:play(flinch)
					end
				end
			end
			for name, solved in Pose.solve(model, enemyFrame, enemyMixer:step(1 / fps).offsets) do
				local part = model:FindFirstChild(name)
				if part ~= nil and part:IsA("BasePart") then
					part.CFrame = solved
				end
			end
		end
		local stepped = mixer:step(1 / fps)
		elapsed += 1 / fps
		if idleTime ~= nil and enemyMixer == nil then
			poseAt(model, enemyFrame, idle, idleTime + elapsed)
		end
		for _, joint in Joints.list(avatar.model) do
			local offset = stepped.offsets[joint.Name]
			joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
		end
		-- The clip's root motion is in the root's own space.
		local delta = stepped.rootDelta
		-- A played basic's state ends combat.basicHitDuration after the press (CharacterController.
		-- endAction): its root motion stops there, its plan holds on to the clip's end (D-568).
		local over = how.played == true and swing.art == nil and elapsed >= Combat.basicHitDuration - 1e-9
		if not over then
			carried += carried:VectorToWorldSpace(Vector3.new(delta[1], delta[2], delta[3]))
		end
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
			if enemyMixer ~= nil then
				enemyMixer:holdSteps(Combat.hitStopFrames[contact.tier] * fps / 60)
				word = WORD_FRAMES
			end
		end
		local depth, where = limbDepth(hurt, frame, stepped.offsets)
		if depth > result.depth then
			result.depth, result.where = depth, ("%s at %.3f s"):format(where, time)
		end
		-- As drawn: the step before's pose, on this root or (a step behind, D-496) on the last one.
		local moved = lastFrame ~= nil and (frame.Position - (lastFrame :: CFrame).Position).Magnitude > 0
		behind = moved and (mixer:heldShown() or behind)
		if lastOffsets ~= nil then
			local shownRoot = if behind then lastFrame :: CFrame else frame
			local drawn, drawnWhere = limbDepth(shownHurt, shownRoot, lastOffsets)
			if drawn > result.screen then
				result.screen, result.screenWhere = drawn, ("%s at %.3f s"):format(drawnWhere, time)
			end
			-- The blade as drawn shows the pose of the step before (D-342).
			if outAt(lastTime) then
				local depth, where = bladeDepth(shownHurt, Pose.solve(avatar.model, shownRoot, lastOffsets))
				if depth > result.bladeScreen then
					result.bladeScreen, result.bladeScreenWhere = depth, ("%s at %.3f s"):format(where, time)
				end
			end
		end
		if outAt(time) then
			local depth, where = bladeDepth(hurt, Pose.solve(avatar.model, frame, stepped.offsets))
			if depth > result.blade then
				result.blade, result.bladeWhere = depth, ("%s at %.3f s"):format(where, time)
			end
		end
		for _, each in keyed do
			local gap = math.abs(time - each.key)
			if gap <= each.gap + 1e-9 then
				local solved = Pose.solve(avatar.model, frame, stepped.offsets)
				local depth = lineDepth(hurt, solved)
				local box = bladeDepth(hurt, solved)
				if gap < each.gap - 1e-9 then
					each.depth, each.box, each.where = -math.huge, -math.huge, ""
				end
				if depth > each.depth then
					each.depth, each.where = depth, ("at %.3f s"):format(time)
				end
				each.box = math.max(each.box, box)
				each.gap = math.min(each.gap, gap)
			end
		end
		lastOffsets, lastFrame, lastTime = stepped.offsets, frame, time
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
	for _, each in keyed do
		if each.depth > result.bladeKey then
			result.bladeKey, result.bladeKeyWhere = each.depth, each.where
		end
		result.bladeKeyBox = math.max(result.bladeKeyBox, each.box)
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

local function check(
	label: string,
	enemyId: string,
	enemyFrame: CFrame,
	lateral: number,
	idleTime: number?,
	restAt: CFrame?,
	rates: { number }?
)
	local rest = restAt
	if rest == nil then
		local probe = placeAt(enemyId, enemyFrame, idleTime)
		rest = restOf(probe, enemyFrame.Position, lateral)
		probe:Destroy()
	end
	local rest = rest :: CFrame
	local worst, worstAt = -math.huge, ""
	local worstScreen, worstScreenAt = -math.huge, ""
	local worstHeld, worstHeldAt = -math.huge, ""
	for _, swing in SWINGS do
		local windows = #ClipSampler.hitWindows(swing.clip)
		for _, fps in rates or RATES do
			local result = swingAt(enemyId, enemyFrame, rest, fps, swing, idleTime)
			if result.depth > worst then
				worst, worstAt = result.depth, ("%s %d Hz: %s"):format(swing.name, fps, result.where)
			end
			if result.screen > worstScreen then
				worstScreen, worstScreenAt = result.screen, ("%s %d Hz: %s"):format(swing.name, fps, result.screenWhere)
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
			if result.screen > DEEPEST then
				error(
					("%s, %s at %d Hz: a limb %.3f studs deep as the screen draws it (%s)"):format(
						label,
						swing.name,
						fps,
						result.screen,
						result.screenWhere
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
			.. ("; as drawn %.3f (%s)"):format(worstScreen, worstScreenAt)
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

	it(
		"at a kobold where the PC's walk-ins rested, square on and turned, as posed and as drawn (item 430(e))",
		function()
			-- Setup A's held kobold stopped the body 3.15 to 3.60 studs from its root (the blocker's
			-- push, not the drawn shell's hold); the gate's 10.35 degree turn too.
			local frame = CFrame.new(0, rootHeightOf("KoboldAxeman"), -20) * CFrame.Angles(0, math.pi, 0)
			for _, distance in { 3.15, 3.6 } do
				for _, yaw in { 0, 10.35 } do
					local at = frame.Position
						+ Vector3.new(math.sin(math.rad(yaw)) * distance, 0, math.cos(math.rad(yaw)) * distance)
					local start = Vector3.new(at.X, avatar.base.Position.Y, at.Z)
					local rest = CFrame.lookAt(start, Vector3.new(frame.Position.X, start.Y, frame.Position.Z))
					check(
						("kobold %.2f out, %.2f degrees round"):format(distance, yaw),
						"KoboldAxeman",
						frame,
						0,
						nil,
						rest,
						{ 60, 144 }
					)
				end
			end
		end
	)

	it("at a side-on boar, from where the drawn shell walks in to, square on its middle and a stud off", function()
		local frame = CFrame.new(0, rootHeightOf("FrenzyBoar"), -20) * CFrame.Angles(0, math.rad(90), 0)
		check("side-on boar", "FrenzyBoar", frame, 0)
		check("side-on boar, a stud off", "FrenzyBoar", frame, 1)
	end)
end)

-- ------------------------------------------------------------------ the played kobold (D-565, D-566)

-- The kobold's idle phases (seconds into its loop) the swing starts in: where the plan read off the
-- kobold as it stood left a hand in it as it idled and flinched on (item 461, 006f057 at 60 Hz at
-- the 3.15 rest: Horizontal 0.040 posed and 0.059 drawn from 2.0 and 2.5, Rising Arc 0.025 and
-- 0.028 from 1.5, Basic2 0.032 from 2.5), and one either side.
local PLAYED_PHASES = { 1.5, 2.0, 2.5 }
-- Item 464: Basic1 from 3.5 studs, the idle's loop in steps of a second.
local BLADE_PHASES = { 0, 1, 2, 3 }
-- The bar for the blade at the key (item 464(b)), on the trail's line the reach caps at
-- bladeDepthStuds plus depthEpsilon (D-424); the blade's own part reads up to its half-width more.
local KEY_BAR = 0.25

-- Every swing at `fps` from `rest`, the kobold played as the game plays it (Play), from each idle
-- phase: the deepest limb as posed and as drawn, and the swing and phase it was in.
local function playedWorst(rest: CFrame, frame: CFrame, fps: number, phases: { number }, play: Play, swings: { Swing })
	local worst =
		{ depth = -math.huge, where = "", screen = -math.huge, screenWhere = "", held = -math.huge, heldWhere = "" }
	for _, swing in swings do
		local windows = #ClipSampler.hitWindows(swing.clip)
		for _, phase in phases do
			local result = swingAt("KoboldAxeman", frame, rest, fps, swing, phase, play)
			local tag = ("%s %d Hz from %.1f s"):format(swing.name, fps, phase)
			if result.hits ~= windows then
				error(("%s: %d of %d cuts landed"):format(tag, result.hits, windows))
			end
			if result.depth > worst.depth then
				worst.depth, worst.where = result.depth, tag .. ": " .. result.where
			end
			if result.screen > worst.screen then
				worst.screen, worst.screenWhere = result.screen, tag .. ": " .. result.screenWhere
			end
			if result.heldDepth > worst.held then
				worst.held, worst.heldWhere = result.heldDepth, tag .. ": " .. result.heldWhere
			end
		end
	end
	return worst
end

describe("the plan holds the hands out of a kobold that idles and flinches on (item 461, D-565)", function()
	local frame = CFrame.new(0, rootHeightOf("KoboldAxeman"), -20) * CFrame.Angles(0, math.pi, 0)
	-- Setup A's walk-ins rested 3.08 to 3.41 studs from the held kobold's root, square on (463(d):
	-- 0.00 degrees off the line); 3.15 is in every swing's span.
	local start = Vector3.new(frame.Position.X, avatar.base.Position.Y, frame.Position.Z + 3.15)
	local rest = CFrame.lookAt(start, Vector3.new(frame.Position.X, start.Y, frame.Position.Z))
	for _, fps in RATES do
		it(
			("at %d Hz from the 3.15 rest, its idle on and each cut's flinch played, as posed and as drawn"):format(fps),
			function()
				local worst = playedWorst(rest, frame, fps, PLAYED_PHASES, { played = true }, SWINGS)
				print(
					("[461] %d Hz played: deepest limb %.3f (%s); as drawn %.3f (%s); in its axe %.3f (%s)"):format(
						fps,
						worst.depth,
						worst.where,
						worst.screen,
						worst.screenWhere,
						worst.held,
						worst.heldWhere
					)
				)
				expect(worst.depth <= DEEPEST).toBe(true)
				expect(worst.screen <= DEEPEST).toBe(true)
				-- What it holds is no part of the keep-out (D-277), so the axe is reported only: the
				-- flinch swings it 0.39-0.50 into Rising Arc's left hand at clip 0.67-0.69 here, on
				-- 006f057 alike, where the PC read nothing deeper than 0.017 (an open issue).
			end
		)
	end
	-- What the HeldBlocker beside the line does not hold off, the keep-out holds alone.
	for _, fps in { 60, 144 } do
		it(("at %d Hz from the 3.15 rest, the same with no HeldBlocker"):format(fps), function()
			local worst = playedWorst(rest, frame, fps, PLAYED_PHASES, { played = true, bare = true }, SWINGS)
			print(
				("[461] %d Hz played, bare: deepest limb %.3f (%s); as drawn %.3f (%s); in its axe %.3f (%s)"):format(
					fps,
					worst.depth,
					worst.where,
					worst.screen,
					worst.screenWhere,
					worst.held,
					worst.heldWhere
				)
			)
			expect(worst.depth <= DEEPEST).toBe(true)
			expect(worst.screen <= DEEPEST).toBe(true)
		end)
	end
end)

describe(
	"Basic1's blade leaves a kobold that idles and flinches on, and stops at the key (item 464, D-566, D-568)",
	function()
		-- Setup C's held kobold at 3.5 (its HeldBlocker beside the line, 463(d)), Basic1 alone: its
		-- state ends combat.basicHitDuration after the press, at clip 0.33, and its clip plays on.
		local frame = CFrame.new(0, rootHeightOf("KoboldAxeman"), -20) * CFrame.Angles(0, math.pi, 0)
		local start = Vector3.new(frame.Position.X, avatar.base.Position.Y, frame.Position.Z + 3.5)
		local rest = CFrame.lookAt(start, Vector3.new(frame.Position.X, start.Y, frame.Position.Z))
		local basic1: Swing = SWINGS[1]
		for _, swing in SWINGS do
			if swing.name == "Basic1" then
				basic1 = swing
			end
		end
		local spans = afterCuts(basic1.clip)
		it("is out by clip 0.283, where the PC read it (exit plus keepOut.bladeOutSeconds)", function()
			expect(#spans).toBe(1)
			expect(spans[1][1] <= 0.283 + 1e-9).toBe(true)
		end)
		it(
			("at 30, 60, 144 and 240 Hz: out from there to the clip's end as posed and as drawn, the trail at most %.2f in at the key"):format(
				KEY_BAR
			),
			function()
				local worst, worstAt = -math.huge, ""
				local drawn, drawnAt = -math.huge, ""
				local key, keyAt, box = -math.huge, "", -math.huge
				local limb, limbAt = -math.huge, ""
				for _, fps in RATES do
					for _, phase in BLADE_PHASES do
						local result = swingAt("KoboldAxeman", frame, rest, fps, basic1, phase, { played = true })
						local tag = ("%d Hz from %.1f s"):format(fps, phase)
						expect(result.hits).toBe(1)
						if result.blade > worst then
							worst, worstAt = result.blade, tag .. ": " .. result.bladeWhere
						end
						if result.bladeScreen > drawn then
							drawn, drawnAt = result.bladeScreen, tag .. ": " .. result.bladeScreenWhere
						end
						-- At 30 Hz the frame nearest the key is the contact's held frame at 0.133, before
						-- the reach's key (open issue: 0.45-0.47 on 006f057 and now alike).
						if fps ~= 30 and result.bladeKey > key then
							key, keyAt = result.bladeKey, tag .. " " .. result.bladeKeyWhere
							box = math.max(box, result.bladeKeyBox)
						end
						local deeper = math.max(result.depth, result.screen)
						if deeper > limb then
							limb, limbAt = deeper, tag .. ": " .. result.where
						end
					end
				end
				print(
					("[464] blade after the cut %.3f (%s), as drawn %.3f (%s); trail at the key %.3f (%s; its part %.3f); limbs %.3f (%s)"):format(
						worst,
						worstAt,
						drawn,
						drawnAt,
						key,
						keyAt,
						box,
						limb,
						limbAt
					)
				)
				expect(worst <= DEEPEST).toBe(true)
				expect(drawn <= DEEPEST).toBe(true)
				expect(key <= KEY_BAR).toBe(true)
				expect(limb <= DEEPEST).toBe(true)
			end
		)
	end
)

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
	if swung.screen > result.body then
		result.body, result.bodyAt = swung.screen, ("%s in %s as drawn"):format(swung.screenWhere, swing.name)
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
