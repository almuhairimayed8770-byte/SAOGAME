--!strict
--[[
	Item 224 (D-CH3): a freeze holds the whole body and its blade still. In Studio the Rising Arc's
	Normal hold moved the body 0.08-0.2 studs a frame at a point-blank kobold, from two causes:

	- The clip's root motion and its lean carried the body's colliding parts (root, torsos, head)
	  into the enemy's blocker (D-198), 0.24-0.54 studs at the hold, and the engine's solver pushed
	  them back out over the frames of the freeze. The keep-out (ContactPredictor.standOff with
	  options.keepOut, carried by CharacterController.stepStandOff) holds the body back along the
	  stand-off's line as far as the swing would carry it in, so nothing is left to push.
	- The procedural channels (Locomotion's lean, foot IK) kept moving while the Mixer's clips were
	  paused. The Mixer now holds them as the last frame before the pause showed them.

	Both are checked for every Art the weapon has a clip for and for every basic swing: the Mixer
	on 60 and 144 Hz frames with the channels changing every frame, and the keep-out at the touching
	distances a fight stops at (the kobold in front, the boar side-on at Studio's 2.33-2.42 and head
	on at its 6.2), plus one placement already inside the blocker, on 60 and 144 Hz frames. The
	keep-out never costs a cut that reached the body and stays inside the anti-cheat's allowance.

	The kobold holds its axe in a face of its own (D-CH4), hanging beside a body at its front: a
	lean into it there is undone by a step aside, square to the line back, since backing off it
	means past its far end (more than the keep-out's budget). Each sample keeps out what the parts
	sweep from the one before, in pieces when they turn fast (a cut turns the head up to 64 degrees
	a sample), so a frame between two samples never stands deeper.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Arts = Harness.load("src/shared/data/arts")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local Playground = Harness.load("src/shared/data/playground")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local HitSweep = Harness.load("src/server/combat/HitSweep")
local Rules = Harness.load("src/server/anticheat/Rules")
local Mixer = Harness.load("src/client/choreo/Mixer")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local AimLogic = Harness.load("src/client/controllers/AimLogic")

local STAND_OFF = Combat.contact.standOff
local KEEP_OUT = STAND_OFF.keepOut
local PROMISE = Combat.hitSphereRadius - Combat.sweepMaxTipStep / 2
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
local trailStart, trailEnd = HitSweep.trailAttachments(avatar.model)

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
-- against the kobold's axe at its front right (the axe's own face, D-CH4): `yaw` turns the enemy
-- from the hit matrix setup's.
type Placement = { setup: string, distance: number, yaw: number? }
local PLACEMENTS: { Placement } = {
	{ setup = "Kobold", distance = 1.8 },
	{ setup = "Kobold", distance = 2.0 },
	{ setup = "Kobold", distance = 1.5 },
	{ setup = "Kobold", distance = 5.24, yaw = 45 },
	{ setup = "BoarSide", distance = 2.33 },
	{ setup = "BoarSide", distance = 2.42 },
	{ setup = "BoarFacing", distance = 6.2 },
}

-- An enemy's rig in its rest pose where the hit matrix stands it, with its blocker (D-198): its
-- faces, the body's first (D-CH4).
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

describe("a freeze holds the procedural channels (item 224, D-CH3)", function()
	for _, swing in SWINGS do
		for _, fps in { 60, 144 } do
			it(
				("%s: every frame of its first hold shows the contact frame's pose at %d Hz"):format(swing.name, fps),
				function()
					local mixer = Mixer.new()
					local handle = mixer:play(swing.clip)
					-- Locomotion's lean changes its table in place; foot IK hands a new one each frame.
					local lean = { Waist = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } } }
					mixer:setProcedural("lean", lean, 1)
					local tick = 0
					local function owner()
						tick += 1
						lean.Waist.rot[1] = 4 * math.sin(tick * 0.7)
						lean.Waist.rot[3] = 3 * math.cos(tick * 0.4)
						mixer:setProcedural("footIK", {
							LeftHip = { pos = { 0, 0, 0 }, rot = { tick * 0.5, 0, 0 } },
							RightKnee = { pos = { 0, 0.01 * tick, 0 }, rot = { 0, 0, -tick * 0.25 } },
						}, 1)
					end
					local dt = 1 / fps
					local window = ClipSampler.hitWindows(swing.clip)[1]
					local result: any = nil
					repeat
						owner()
						result = mixer:step(dt)
					until handle.time >= window.open
					local contact = result.offsets
					mixer:hitStop(Combat.hitStopFrames[swing.clip.hitStop or "Normal"] - Combat.hitStopShaveFrames)
					local held = 0
					while true do
						owner()
						local step = mixer:step(dt)
						if not step.paused then
							break
						end
						held += 1
						for name, offset in contact do
							local shown = step.offsets[name]
							expect(shown ~= nil).toBe(true)
							for axis = 1, 3 do
								expect(math.abs(shown.pos[axis] - offset.pos[axis]) < 1e-9).toBe(true)
								expect(math.abs(shown.rot[axis] - offset.rot[axis]) < 1e-9).toBe(true)
							end
						end
						for name in step.offsets do
							expect(contact[name] ~= nil).toBe(true)
						end
						expect(step.rootDelta[1] == 0 and step.rootDelta[2] == 0 and step.rootDelta[3] == 0).toBe(true)
					end
					expect(held >= Combat.hitStopFrames.Normal).toBe(true)
					-- Out of the freeze, the channels move on again.
					expect(math.abs(result.offsets.Waist.rot[1] - mixer:lastOffsets().Waist.rot[1]) > 0).toBe(true)
				end
			)
		end
	end
end)

describe("the keep-out holds the body out of the enemy's blocker (item 224, D-CH3)", function()
	for _, swing in SWINGS do
		it(swing.name .. ": no colliding part goes deeper than it started, at 60 and 144 Hz", function()
			for _, placement in PLACEMENTS do
				local model, blocker = place(placement.setup, placement.distance, placement.yaw)
				local plan = planFor(swing, model)
				expect(plan ~= nil).toBe(true)
				expect(plan.keep ~= nil).toBe(true)
				local started = math.max(0, deepest(swing, rootAt(swing, plan, swing.from), swing.from, blocker))
				local allowed = started + KEEP_OUT.depthEpsilon + SLACK
				for _, frame in { { fps = 60, phase = 0 }, { fps = 144, phase = 0.37 } } do
					local last, lastAside = 0, 0
					local tick = 0
					while true do
						local time = swing.from + (tick + frame.phase) / frame.fps
						if time > swing.clip.duration then
							break
						end
						tick += 1
						local keep = plan.keep(time)
						local aside = if plan.keepSide ~= nil then plan.keepSide(time) else 0
						-- Never forward again, nor back aside: a freeze (a held clip time) holds the body
						-- where it is.
						expect(keep >= last - 1e-9).toBe(true)
						expect(aside >= lastAside - 1e-9).toBe(true)
						last, lastAside = keep, aside
						-- The step, back and aside (square to each other) within the one budget.
						expect(math.sqrt((keep + plan.distance) ^ 2 + aside ^ 2) <= KEEP_OUT.maxStuds + 1e-9).toBe(true)
						local worst = deepest(swing, rootAt(swing, plan, time), time, blocker)
						if worst > allowed then
							error(
								("%s at %s %.2f, %d Hz: %.3f deep at clip time %.3f (started %.3f)"):format(
									swing.name,
									placement.setup,
									placement.distance,
									frame.fps,
									worst,
									time,
									started
								)
							)
						end
					end
				end
				model:Destroy()
			end
		end)
	end

	it("went in before: at a touching kobold the Rising Arc's own motion carried the torso into the blocker", function()
		local swing: Swing? = nil
		for _, each in SWINGS do
			if each.name == "RisingArc" then
				swing = each
			end
		end
		assert(swing ~= nil, "no Rising Arc")
		local model, blocker = place("Kobold", 1.8)
		local window = ClipSampler.hitWindows(swing.clip)[1]
		-- Without the keep-out, a hold anywhere in the first window stands deep in the blocker (Studio
		-- measured 0.24 at the first hold).
		local plan = planFor(swing, model)
		local bare, kept = -math.huge, -math.huge
		for k = 0, 8 do
			local time = window.open + (window.close - window.open) * k / 8
			bare = math.max(bare, deepest(swing, rootAt(swing, nil, time), time, blocker))
			kept = math.max(kept, deepest(swing, rootAt(swing, plan, time), time, blocker))
		end
		-- With it, no deeper than the hold pose it was released from stood (a hair, at the touch).
		local started = math.max(0, deepest(swing, rootAt(swing, plan, swing.from), swing.from, blocker))
		expect(bare > 0.2).toBe(true)
		expect(bare - started > 0.2).toBe(true)
		expect(kept <= started + KEEP_OUT.depthEpsilon + SLACK).toBe(true)
		model:Destroy()
	end)

	it(
		"beside the kobold's axe at its front, a lean into the axe steps the body aside, not back past the axe (D-CH4)",
		function()
			-- Measured: Sharp Nail 0.18 and the third basic 0.21 aside at a kobold 2 studs ahead; backing
			-- off the axe instead needs past its far end, 3.85 ahead of the kobold, more than maxStuds.
			local leaned = {}
			for _, swing in SWINGS do
				local model, faces = place("Kobold", 2.0)
				local held: any = nil
				for _, face in faces do
					if face.Name == KEEP_OUT.heldFace then
						held = face
					end
				end
				assert(held ~= nil, "no held face")
				local plan = planFor(swing, model)
				expect(plan.side ~= nil and plan.keepSide ~= nil).toBe(true)
				-- Square to the line back, flat, away from the axe.
				expect(math.abs(plan.side:Dot(plan.away)) < 1e-9).toBe(true)
				expect(math.abs(plan.side.Y) < 1e-9).toBe(true)
				expect(plan.side:Dot(avatar.base.Position - held.CFrame.Position) > 0).toBe(true)
				leaned[swing.name] = plan.keepSide(swing.clip.duration)
				model:Destroy()
			end
			for _, name in { "SharpNail", "Basic3" } do
				expect(leaned[name] > 0.1 and leaned[name] < 0.5).toBe(true)
			end
			-- A body with nothing held beside it is never stepped aside.
			for _, setup in { "BoarSide", "BoarFacing" } do
				local model = place(setup, if setup == "BoarSide" then 2.33 else 6.2)
				for _, swing in SWINGS do
					local plan = planFor(swing, model)
					expect(plan.side == nil and plan.keepSide == nil).toBe(true)
				end
				model:Destroy()
			end
		end
	)

	it("never costs a cut that reached the body", function()
		for _, swing in SWINGS do
			for _, placement in PLACEMENTS do
				local model = place(placement.setup, placement.distance, placement.yaw)
				local plan = planFor(swing, model)
				for index, window in ClipSampler.hitWindows(swing.clip) do
					local function nearest(bare: boolean): number
						local best = math.huge
						for k = 0, STAND_OFF.reachSamples do
							local time = window.open + (window.close - window.open) * k / STAND_OFF.reachSamples
							local sample = HitSweep.bladeAt(
								avatar.model,
								rootAt(swing, plan, time, bare),
								swing.clip,
								time,
								trailStart,
								trailEnd
							)
							for _, part in model:GetDescendants() do
								if part:IsA("BasePart") and BladeContact.queryable(part) then
									local distance =
										HitSweep.segmentBoxDistance(sample.start, sample.finish, part.CFrame, part.Size)
									best = math.min(best, distance)
								end
							end
						end
						return best
					end
					if nearest(true) <= PROMISE then
						local kept = nearest(false)
						if kept > PROMISE then
							error(
								("%s window %d at %s %.2f: the keep-out leaves the cut %.3f off the body"):format(
									swing.name,
									index,
									placement.setup,
									placement.distance,
									kept
								)
							)
						end
					end
				end
				model:Destroy()
			end
		end
	end)
end)

describe("the keep-out stays inside the anti-cheat's limits (D-CH3)", function()
	it("caps the blade step and the keep-out together within the mid-swing slack", function()
		expect(KEEP_OUT.maxStuds <= Combat.rootMotionSlack).toBe(true)
		expect(KEEP_OUT.maxStuds >= STAND_OFF.maxStuds).toBe(true)
	end)

	it("no anti-cheat sample over any swing at any placement travels past its allowance", function()
		local interval = Combat.anticheatSampleInterval
		-- A basic swing runs in the server's Art state too, with no root motion of its own.
		local record = { state = "Art", weaponId = Playground.loadout.weapon }
		for _, swing in SWINGS do
			local motion = if swing.art ~= nil then swing.art.rootMotion else 0
			local allowed = Rules.allowedDistance(interval, record, Combat, motion, 0)
			for _, placement in PLACEMENTS do
				local model = place(placement.setup, placement.distance, placement.yaw)
				local plan = planFor(swing, model)
				for k = 0, 60 do
					local t0 = swing.from + (swing.clip.duration - swing.from) * k / 60
					local a = rootAt(swing, plan, t0).Position
					local b = rootAt(swing, plan, t0 + interval).Position
					expect(Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude <= allowed).toBe(true)
				end
				model:Destroy()
			end
		end
	end)
end)
