--!strict
--[[
	Item 285 (D-314, D-315): beside the kobold's axe the keep-out moves the body in jumps. In Studio
	every move over 0.15 studs was in the code step (the physics step 0.000): each Sharp Nail crept
	forward 0.20-0.24 studs a frame (its own lunge, nothing holding it) and then stepped back
	0.37-0.47 studs on each of two frames around the Final's word; the first cast also stepped
	0.43 back and 0.30 aside in one frame. The plan reads a sample ahead: where the clip's lunge
	carries the parts in on the next frame, the keep-out takes the whole step back one frame early,
	before the root motion moves, and the root motion then lands on top of it.

	What the root shows each frame is the clip's root motion plus the plan (the blade step, the
	keep-out back and aside), as CharacterController.stepStandOff carries it with nothing behind.
	At the touch none of it may jump: no frame steps the body back or aside more than a frame's
	share of the lunge it is holding back (JUMP at 60 Hz, scaled to the frame at 144).
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
local Mixer = Harness.load("src/client/choreo/Mixer")
local Joints = Harness.load("src/shared/choreo/Joints")
local Weapons = Harness.load("src/shared/data/weapons")
local Playground = Harness.load("src/shared/data/playground")

local STAND_OFF = Combat.contact.standOff
local KEEP_OUT = STAND_OFF.keepOut
local HOLD_FALLBACK = Combat.startPoseTime + Combat.activationHold

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

-- The largest step a frame at 60 Hz may show at the touch: Sharp Nail's own lunge moves the root
-- 0.2 studs a frame through its cuts (12 studs a second), and Studio read 0.44-0.64 as a snap and
-- 0.03 as still.
local JUMP = 0.2

-- Item 285's placements: touching the kobold's front beside its axe (Studio stood 1.99 from it),
-- and nearer and farther by a little.
local TOUCH: { number } = { 1.8, 1.99, 2.0 }

describe("the keep-out at the kobold's axe moves the body without a jump (item 285, D-314, D-315)", function()
	for _, swing in SWINGS do
		if swing.name ~= "SharpNail" and swing.name:sub(1, 5) ~= "Basic" then
			continue
		end
		for _, fps in { 60, 144 } do
			it(
				("%s at %d Hz: no frame steps the body back or aside by more than a frame's share"):format(
					swing.name,
					fps
				),
				function()
					local cap = JUMP * 60 / fps
					for _, distance in TOUCH do
						local model = place("Kobold", distance)
						local plan = planFor(swing, model)
						expect(plan ~= nil and plan.keep ~= nil).toBe(true)
						local look = avatar.base.LookVector
						local before = rootAt(swing, plan, swing.from)
						local tick = 0
						while true do
							tick += 1
							local time = swing.from + tick / fps
							if time > swing.clip.duration then
								break
							end
							local now = rootAt(swing, plan, time)
							local moved = now.Position - before.Position
							local back = -moved:Dot(look)
							local aside = if plan.side ~= nil then math.abs(moved:Dot(plan.side)) else 0
							if back > cap + 1e-6 or aside > cap + 1e-6 then
								error(
									("%s at the kobold %.2f, %d Hz: clip time %.3f steps %.3f back and %.3f aside in one frame (cap %.3f)"):format(
										swing.name,
										distance,
										fps,
										time,
										back,
										aside,
										cap
									)
								)
							end
							before = now
						end
						model:Destroy()
					end
				end
			)
		end
	end
end)

-- Through the Mixer (item 285 in Studio): a contact's hit-stop holds the clip clock, and the step
-- after it skips the strike's authored hold the hit-stop stood in for (Mixer.hitStop, section 10
-- beat 4), so one frame carries the clip 0.03-0.05 s further than its length. What the plan grew
-- over that stretch lands in the one frame: before this rule Sharp Nail at the kobold stepped back
-- 0.50 studs in the frame after its second cut's freeze at 60 Hz, and 0.39 at 144 (a frame's share
-- 0.083), where the clip sampled at the frame's length alone never moved more than 0.2.
describe("the keep-out does not jump when a hit-stop skips a strike's hold (item 285, D-427)", function()
	local WEAPON = Weapons.byId(Playground.loadout.weapon)
	for _, swing in SWINGS do
		if swing.name ~= "SharpNail" and swing.name:sub(1, 5) ~= "Basic" then
			continue
		end
		for _, fps in { 30, 60, 144, 240 } do
			it(
				("%s at %d Hz with its hits held: no frame steps the body back or aside by more than a frame's share"):format(
					swing.name,
					fps
				),
				function()
					local cap = JUMP * 60 / fps
					local art = swing.art
					for _, distance in TOUCH do
						local model = place("Kobold", distance)
						local plan = planFor(swing, model)
						expect(plan ~= nil and plan.keep ~= nil).toBe(true)
						local records = {
							{ id = 1, model = avatar.model, kind = "Player", state = "Art", weaponId = WEAPON.id },
							{ id = 5, model = model, kind = "Enemy", state = "Idle", hp = 1e6, maxHp = 1e6 },
						}
						local predictor = ContactPredictor.new({
							targets = function(): { any }
								return records
							end,
						})
						local mixer = Mixer.new()
						local handle = mixer:play(swing.clip)
						if swing.from > 0 then
							mixer:seek(handle, swing.from)
						end
						avatar.root.CFrame = avatar.base
						assert(predictor:begin({
							model = avatar.model,
							clip = swing.clip,
							artId = if art ~= nil then art.id else nil,
							finalHit = art ~= nil,
							multiplier = if art ~= nil then art.multiplier else Combat.basicAttackMultiplier,
							weaponAttack = WEAPON.attack,
						}))
						local look = avatar.base.LookVector
						local carried = avatar.base
						local before = avatar.base
						local held = 0
						for frame = 1, math.ceil(swing.clip.duration * fps) + 60 do
							local stepped = mixer:step(1 / fps)
							for _, joint in Joints.list(avatar.model) do
								local offset = stepped.offsets[joint.Name]
								joint.Transform = if offset ~= nil
									then ClipSampler.toCFrame(offset)
									else CFrame.identity
							end
							local delta = stepped.rootDelta
							carried += Vector3.new(delta[1], delta[2], delta[3])
							local time = handle.time
							local back = AimLogic.standOffAt(plan.distance, plan.from, plan.to, time, STAND_OFF.easing)
								+ plan.keep(time)
							local aside = if plan.side ~= nil and plan.keepSide ~= nil
								then plan.side * plan.keepSide(time)
								else Vector3.zero
							avatar.root.CFrame = carried + plan.away * back + aside
							for _, contact in predictor:step(time) do
								held += 1
								mixer:holdSteps(Combat.hitStopFrames[contact.tier] * fps / 60)
							end
							local moved = avatar.root.CFrame.Position - before.Position
							local stepBack = -moved:Dot(look)
							local stepAside = if plan.side ~= nil then math.abs(moved:Dot(plan.side)) else 0
							-- (The root is summed frame by frame in 32-bit floats: 1e-4 is their noise.)
							if stepBack > cap + 1e-4 or stepAside > cap + 1e-4 then
								error(
									("%s at the kobold %.2f, %d Hz, frame %d: clip time %.3f steps %.5f back and %.5f aside in one frame (cap %.5f)"):format(
										swing.name,
										distance,
										fps,
										frame,
										time,
										stepBack,
										stepAside,
										cap
									)
								)
							end
							before = avatar.root.CFrame
							if handle.done then
								break
							end
						end
						-- The swing hit (else nothing was held, and the case proves nothing).
						expect(held > 0).toBe(true)
						predictor:stop()
						avatar.root.CFrame = avatar.base
						model:Destroy()
					end
				end
			)
		end
	end
end)
