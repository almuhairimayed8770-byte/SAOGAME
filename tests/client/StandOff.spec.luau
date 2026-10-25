--!strict
--[[
	The Art stand-off (fix F1): an Art whose first cut would start with the blade already in the
	target's body steps the body straight away from it over the anticipation, from the hold pose to
	the first window's open, so the cut starts outside the body and moves into it on screen.

	ContactPredictor.standOff picks the step on the hit matrix's body and rigs (dev.luau hitMatrix):
	the least multiple of combat.contact.standOff.stepStuds that leaves the start pose's blade
	clearStuds from the body, at most maxStuds, and only when the cut still passes deeper than the
	sweep's promise. These cases re-pose the blade with the server's own solver (HitSweep.bladeAt)
	to check it, and hold the step inside the anti-cheat's mid-Art allowance (anticheat Rules).
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
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local HitSweep = Harness.load("src/server/combat/HitSweep")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local Rules = Harness.load("src/server/anticheat/Rules")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local AimLogic = Harness.load("src/client/controllers/AimLogic")

local STAND_OFF = Combat.contact.standOff
local PROMISE = Combat.hitSphereRadius - Combat.sweepMaxTipStep / 2
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
local trailStart, trailEnd = HitSweep.trailAttachments(avatar.model)

local function setupOf(id: string): any
	for _, setup in Dev.hitMatrix.setups do
		if setup.id == id then
			return setup
		end
	end
	error("no hit matrix setup " .. id)
end

-- An enemy's rig in its rest pose where the hit matrix stands it (its bearing, yaw and height).
local function place(setup: any, distance: number): any
	local def = Enemies.byId(setup.enemy)
	local model = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local bearing = math.rad(setup.bearing or 0)
	local frame = avatar.base
		* CFrame.new(math.sin(bearing) * distance, height - avatar.rootHeight, -math.cos(bearing) * distance)
		* CFrame.Angles(0, math.pi - bearing + math.rad(setup.yaw), 0)
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	return model
end

local function artClip(artId: string): any
	return Harness.load("src/shared/clips/player/OneHandedSword/" .. Arts.byId(artId).clip:match("[^/]+$"))
end

-- The clip time an Art is released from: its hold pose.
local function holdTime(clip: any): number
	return ActionLogic.holdClipTime(clip, HOLD_FALLBACK) :: number
end

-- The body's root at clip time `time`: standing at the matrix's base at `from`, carried by the
-- clip's root motion, stepped `back` along `away`.
local function rootAt(clip: any, from: number, time: number, away: Vector3, back: number): CFrame
	local start = ClipSampler.rootMotionAt(clip, from)
	local now = ClipSampler.rootMotionAt(clip, time)
	return avatar.base * CFrame.new(now[1] - start[1], now[2] - start[2], now[3] - start[3]) + away * back
end

-- The nearest the server's blade comes to the enemy at `time`: to the parts its queries see (an
-- enemy's blocker, D-198, is not one), and with `held` to its body alone, not the weapon it holds
-- (rigs.luau trailParts).
local function gap(model: any, clip: any, root: CFrame, time: number, held: { string }?): number
	local sample = HitSweep.bladeAt(avatar.model, root, clip, time, trailStart, trailEnd)
	local best = math.huge
	for _, part in model:GetDescendants() do
		if
			part:IsA("BasePart")
			and BladeContact.queryable(part)
			and (held == nil or table.find(held, part.Name) == nil)
		then
			local distance = HitSweep.segmentBoxDistance(sample.start, sample.finish, part.CFrame, part.Size)
			best = math.min(best, distance)
		end
	end
	return best
end

local function standOffFor(artId: string, setupId: string, distance: number): (any, any, any, number)
	local clip = artClip(artId)
	local model = place(setupOf(setupId), distance)
	local from = holdTime(clip)
	local plan = ContactPredictor.standOff(avatar.model, clip, from, avatar.base, model)
	return plan, clip, model, from
end

describe("the Art stand-off picks its step (fix F1)", function()
	it("an Art whose first cut starts in the body steps just far enough away for it to start clear", function()
		-- The Rising Arc's first cut starts low on the right, in the flank of a boar side-on at the touch.
		local plan, clip, model, from = standOffFor("OneHandedSword.RisingArc", "BoarSide", 1.8)
		local window = ClipSampler.hitWindows(clip)[1]
		local still = rootAt(clip, from, window.open, Vector3.zero, 0)
		expect(gap(model, clip, still, window.open) < STAND_OFF.clearStuds).toBe(true)
		expect(plan).never.toBeNil()
		expect(plan.distance > 0 and plan.distance <= STAND_OFF.maxStuds + 1e-9).toBe(true)
		expect(plan.from).toBe(from)
		expect(plan.to).toBe(window.open)
		-- Straight back from the boar ahead.
		expect(plan.away:Dot(Vector3.new(0, 0, 1))).toBeCloseTo(1, 1e-6)
		local steps = plan.distance / STAND_OFF.stepStuds
		expect(math.abs(steps - math.round(steps)) < 1e-6).toBe(true)
		local stepped = rootAt(clip, from, window.open, plan.away, plan.distance)
		expect(gap(model, clip, stepped, window.open) >= STAND_OFF.clearStuds).toBe(true)
		-- One step less would not do.
		local short = rootAt(clip, from, window.open, plan.away, plan.distance - STAND_OFF.stepStuds)
		expect(gap(model, clip, short, window.open) < STAND_OFF.clearStuds).toBe(true)
	end)

	it("a first cut that starts clear of the body takes no step", function()
		for _, case in
			{ { "OneHandedSword.Vertical", "Kobold", 2.3 }, { "OneHandedSword.Horizontal", "BoarFacing", 7 } }
		do
			local plan = standOffFor(case[1], case[2], case[3])
			expect(plan).toBeNil()
		end
	end)

	it("never costs a hit: after any step every cut that passed deeper than the promise still does", function()
		-- The body stays stepped for the rest of the Art, so every window counts, not just the first.
		local planned = 0
		for _, artId in Playground.loadout.artSlots do
			for _, setup in Dev.hitMatrix.setups do
				for _, distance in setup.distances do
					local plan, clip, model, from = standOffFor(artId, setup.id, distance)
					if plan == nil then
						continue
					end
					planned += 1
					for index, window in ClipSampler.hitWindows(clip) do
						local function deepest(away: Vector3, back: number): number
							local best = math.huge
							for k = 0, 48 do
								local time = window.open + (window.close - window.open) * k / 48
								best = math.min(best, gap(model, clip, rootAt(clip, from, time, away, back), time))
							end
							return best
						end
						local stood, stepped = deepest(Vector3.zero, 0), deepest(plan.away, plan.distance)
						if (index == 1 or stood <= PROMISE) and stepped > PROMISE then
							error(
								("%s hit %d vs %s at %.2f: after a %.2f step the cut passes %.2f from the body"):format(
									artId,
									index,
									setup.id,
									distance,
									plan.distance,
									stepped
								)
							)
						end
					end
				end
			end
		end
		-- The shoulder placements and the boar's flank call for it.
		expect(planned >= 5).toBe(true)
	end)

	it("in a locked fight the first cut never starts inside the body", function()
		-- Straight ahead, where a lock or the assist turns the body, at every real-fight placement.
		-- The body, not the weapon it holds: the kobold's club, beside the player at the touch, runs
		-- along the step, so no step back clears the Rising Arc's start pose of it; a touch there
		-- plays on the strike's key (contact.keyEpsilon), with the blade on the move.
		for _, artId in Playground.loadout.artSlots do
			for _, setup in Dev.hitMatrix.setups do
				if setup.pointBlank then
					continue
				end
				for _, distance in setup.distances do
					if distance < setup.realFight.min - 1e-9 or distance > setup.realFight.max + 1e-9 then
						continue
					end
					local plan, clip, model, from = standOffFor(artId, setup.id, distance)
					local window = ClipSampler.hitWindows(clip)[1]
					local away = if plan ~= nil then plan.away else Vector3.zero
					local back = if plan ~= nil then plan.distance else 0
					local held = Rigs[Enemies.byId(setup.enemy).skin].trailParts
					local start = gap(model, clip, rootAt(clip, from, window.open, away, back), window.open, held)
					if start < STAND_OFF.clearStuds then
						error(
							("%s vs %s at %.2f: the first cut starts %.2f from the body"):format(
								artId,
								setup.id,
								distance,
								start
							)
						)
					end
				end
			end
		end
	end)
end)

describe("the Art stand-off stays inside the anti-cheat's limits", function()
	it("is at most the mid-Art slack and well under the sprint cap over the shortest anticipation", function()
		expect(STAND_OFF.maxStuds <= Combat.rootMotionSlack).toBe(true)
		for _, artId in Playground.loadout.artSlots do
			local clip = artClip(artId)
			local anticipation = ClipSampler.hitWindows(clip)[1].open - holdTime(clip)
			expect(anticipation > 0).toBe(true)
			expect(STAND_OFF.maxStuds / anticipation <= Combat.maxSpeedStudsPerSecond).toBe(true)
		end
	end)

	it("no anti-cheat sample over an Art with the largest step travels past its mid-Art allowance", function()
		local interval = Combat.anticheatSampleInterval
		for _, artId in Playground.loadout.artSlots do
			local art = Arts.byId(artId)
			local clip = artClip(artId)
			local from = holdTime(clip)
			local open = ClipSampler.hitWindows(clip)[1].open
			local record = { state = "Art", weaponId = Playground.loadout.weapon }
			local allowed = Rules.allowedDistance(interval, record, Combat, art.rootMotion, 0)
			local duration = clip.duration or clip.keys[#clip.keys].time
			for k = 0, 40 do
				local t0 = duration * k / 40
				local t1 = t0 + interval
				local a = rootAt(clip, 0, t0, Vector3.zero, 0).Position
				local b = rootAt(clip, 0, t1, Vector3.zero, 0).Position
				local step = AimLogic.standOffAt(STAND_OFF.maxStuds, from, open, t1, STAND_OFF.easing)
					- AimLogic.standOffAt(STAND_OFF.maxStuds, from, open, t0, STAND_OFF.easing)
				local travel = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude + step
				expect(travel <= allowed).toBe(true)
			end
		end
	end)
end)
