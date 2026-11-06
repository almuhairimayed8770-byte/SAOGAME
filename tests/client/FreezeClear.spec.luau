--!strict
--[[
	Item 286 (D-235, D-314): inside its freezes the Rising Arc at a side-on boar still crept 0.034-0.038
	studs a frame in Studio, at the real touch (2.35-2.41 root to root). The freeze holds the clip
	clock, the root motion and the plan, so the code moves nothing; what moves the body is the engine
	pushing a colliding part out of the boar's blocker. The keep-out lets every part stay as deep as
	the swing found it (ContactPredictor's allowed depth is the start's, plus depthEpsilon): at the
	touch the upper torso starts 0.02-0.05 studs inside the blocker and is held there through both
	cuts, so every freeze holds an overlap for the solver to work on.

	A freeze must be still, so at every cut's key (where the freeze holds the body) no colliding
	part stands in the blocker deeper than depthEpsilon: an overlap the body starts with is stepped
	out over the anticipation, before the first freeze.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Arts = Harness.load("src/shared/data/arts")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local AimLogic = Harness.load("src/client/controllers/AimLogic")

local STAND_OFF = Combat.contact.standOff
local KEEP_OUT = STAND_OFF.keepOut
local HOLD_FALLBACK = Combat.startPoseTime + Combat.activationHold
-- How much deeper than it started a part may stand between two of the plan's samples (it reads a
-- sample ahead, so this only covers the solver's rounding).
local SLACK = 0.01

local root = Harness.repoRoot()

local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
local avatar = HitMatrix.standing(Harness)

type Swing = { name: string, clip: any, art: any?, from: number }

-- Every Art the weapon has a clip for, from its hold pose, and the three basic swings.
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
for index = 1, Combat.basicChainLength do
	local name = "Basic" .. index
	table.insert(
		SWINGS,
		{ name = name, clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name), art = nil, from = 0 }
	)
end

local function setupOf(id: string): any
	for _, setup in Dev.hitMatrix.setups do
		if setup.id == id then
			return setup
		end
	end
	error("no hit matrix setup " .. id)
end

-- The touching distances of item 224's fights (and one body already in the blocker), and a body
-- against the kobold's axe at its front right (the axe's own face, D-315): `yaw` turns the enemy
-- from the hit matrix setup's.
type Placement = { setup: string, distance: number, yaw: number? }

-- An enemy's rig in its rest pose where the hit matrix stands it, with its blocker (D-198): its
-- faces, the body's first (D-315).
local function place(setupId: string, distance: number, yaw: number?): (any, { any })
	local setup = setupOf(setupId)
	local def = Enemies.byId(setup.enemy)
	local model = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local bearing = math.rad(setup.bearing or 0)
	local frame = avatar.base
		* CFrame.new(math.sin(bearing) * distance, height - avatar.rootHeight, -math.cos(bearing) * distance)
		* CFrame.Angles(0, math.pi - bearing + math.rad(yaw or setup.yaw), 0)
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	local blocker = RigBuilder.addBlocker(model)
	assert(blocker ~= nil, "no blocker for " .. setupId)
	local faces = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and (child.Name == KEEP_OUT.bodyFace or child.Name == KEEP_OUT.heldFace) then
			table.insert(faces, child)
		end
	end
	return model, faces
end

-- How deep two boxes overlap (separating axes): > 0 overlapping by that much.
local function depth(aFrame: CFrame, aSize: Vector3, bFrame: CFrame, bSize: Vector3): number
	local aAxes = { aFrame.RightVector, aFrame.UpVector, aFrame.LookVector }
	local bAxes = { bFrame.RightVector, bFrame.UpVector, bFrame.LookVector }
	local aHalf = { aSize.X / 2, aSize.Y / 2, aSize.Z / 2 }
	local bHalf = { bSize.X / 2, bSize.Y / 2, bSize.Z / 2 }
	local between = bFrame.Position - aFrame.Position
	local axes = table.clone(aAxes)
	for _, axis in bAxes do
		table.insert(axes, axis)
	end
	for _, a in aAxes do
		for _, b in bAxes do
			local cross = a:Cross(b)
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

-- The deepest any colliding part stands in any of the blocker's `faces` with the root at
-- `rootFrame` and the clip at `time`.
local function deepest(swing: Swing, rootFrame: CFrame, time: number, faces: { any }): number
	local solved = Pose.solve(avatar.model, rootFrame, ClipSampler.sample(swing.clip, time))
	local worst = -math.huge
	for _, name in KEEP_OUT.parts do
		local part = avatar.model:FindFirstChild(name)
		local frame = solved[name]
		if part ~= nil and frame ~= nil then
			for _, face in faces do
				worst = math.max(worst, depth(frame, part.Size, face.CFrame, face.Size))
			end
		end
	end
	return worst
end

-- What the root shows at clip time `time` under `plan`, as CharacterController.stepStandOff
-- carries it: the clip's root motion from `from`, the blade step and the keep-out, back and aside
-- (none: nil plan, or `bare` for the clip and the step alone).
local function rootAt(swing: Swing, plan: any?, time: number, bare: boolean?): CFrame
	local start = ClipSampler.rootMotionAt(swing.clip, swing.from)
	local now = ClipSampler.rootMotionAt(swing.clip, time)
	local frame = avatar.base * CFrame.new(now[1] - start[1], now[2] - start[2], now[3] - start[3])
	if plan == nil then
		return frame
	end
	local back = AimLogic.standOffAt(plan.distance, plan.from, plan.to, time, STAND_OFF.easing)
	if not bare and plan.keep ~= nil then
		back += plan.keep(time)
	end
	local aside = if not bare
			and plan.side ~= nil
			and plan.keepSide ~= nil
		then plan.side * plan.keepSide(time)
		else Vector3.zero
	return frame + plan.away * back + aside
end

local function planFor(swing: Swing, model: any): any?
	return ContactPredictor.standOff(
		avatar.model,
		swing.clip,
		swing.from,
		avatar.base,
		model,
		nil,
		{ keepOut = true, step = swing.art ~= nil }
	)
end

-- Studio's real touch at a side-on boar (item 286: 2.35-2.41 root to root).
local TOUCH: { number } = { 2.35, 2.38 }
-- Nearer than this avatar's own touch (the blank R15 stops at 2.25-2.28 against the flank; the
-- owner's wider avatar stops at 2.35-2.41, so its torso meets the blocker where this one is still
-- clear), and where a chained swing starts when the one before left the body nearer: the swing
-- starts with a colliding part already in the blocker (the blank avatar's torso 0.01-0.15 in).
local NEAR: { number } = { 2.1, 2.2 }

describe("a freeze at the touch holds no overlap for the engine to push out (item 286, D-314)", function()
	for _, swing in SWINGS do
		for _, case in
			{
				{ label = "at the touch", distances = TOUCH },
				{ label = "starting in the blocker", distances = NEAR },
			}
		do
			it(
				("%s: at every cut's key no colliding part stands in a side-on boar's blocker (%s)"):format(
					swing.name,
					case.label
				),
				function()
					for _, distance in case.distances do
						local model, faces = place("BoarSide", distance)
						local plan = planFor(swing, model)
						expect(plan ~= nil).toBe(true)
						for index, window in ClipSampler.hitWindows(swing.clip) do
							local key = ContactPredictor.strikeKey(swing.clip, window)
							if key < swing.from then
								continue
							end
							local worst = deepest(swing, rootAt(swing, plan, key), key, faces)
							if worst > KEEP_OUT.depthEpsilon + SLACK then
								error(
									("%s at the boar's flank %.2f: cut %d's key %.3f holds a part %.3f studs inside the blocker"):format(
										swing.name,
										distance,
										index,
										key,
										worst
									)
								)
							end
						end
						model:Destroy()
					end
				end
			)
		end
	end
end)
