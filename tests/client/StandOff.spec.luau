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
		-- The body, not the weapon it holds: a blade that meets the kobold's club clashes, it never
		-- wounds (D-277), so the stand-off does not step back from it either.
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

describe("the Art stand-off never steps into the world (D-235 amended)", function()
	local rootSize: Vector3 = avatar.model.PrimaryPart.Size
	local AWAY = Vector3.new(0, 0, 1) -- straight back from a target ahead of the matrix's base
	local GAP: number = STAND_OFF.wallGapStuds

	-- Whether two boxes overlap (separating axes), touching included.
	local function overlaps(a: CFrame, aSize: Vector3, b: CFrame, bSize: Vector3): boolean
		local axesA = { a.RightVector, a.UpVector, a.LookVector }
		local axesB = { b.RightVector, b.UpVector, b.LookVector }
		local halfA = { aSize.X / 2, aSize.Y / 2, aSize.Z / 2 }
		local halfB = { bSize.X / 2, bSize.Y / 2, bSize.Z / 2 }
		local axes = table.clone(axesA)
		for _, axis in axesB do
			table.insert(axes, axis)
		end
		for _, u in axesA do
			for _, v in axesB do
				local cross = u:Cross(v)
				if cross.Magnitude > 1e-6 then
					table.insert(axes, cross.Unit)
				end
			end
		end
		local between = b.Position - a.Position
		for _, axis in axes do
			local reachA, reachB = 0, 0
			for index = 1, 3 do
				reachA += halfA[index] * math.abs(axesA[index]:Dot(axis))
				reachB += halfB[index] * math.abs(axesB[index]:Dot(axis))
			end
			if math.abs(between:Dot(axis)) > reachA + reachB + 1e-9 then
				return false
			end
		end
		return true
	end

	-- The engine's Blockcast over `world` (parts, or models of parts) to within 0.001 studs: it
	-- meets only parts that can collide and are not under `exclude`, and never one the box starts
	-- in. `excludes` collects what each call left out.
	local function engineCast(world: { Instance }, excludes: { { Instance } }?)
		return function(start: CFrame, size: Vector3, vector: Vector3, exclude: { Instance }): number?
			if excludes ~= nil then
				table.insert(excludes, exclude)
			end
			local length = vector.Magnitude
			if length < 1e-9 then
				return nil
			end
			local direction = vector.Unit
			local parts: { BasePart } = {}
			for _, item in world do
				local list = if item:IsA("BasePart") then { item } else item:GetDescendants()
				for _, part in list do
					if part:IsA("BasePart") and part.CanCollide then
						local left = false
						for _, skip in exclude do
							if part == skip or part:IsDescendantOf(skip) then
								left = true
							end
						end
						if not left then
							table.insert(parts, part)
						end
					end
				end
			end
			local best: number? = nil
			for _, part in parts do
				if overlaps(start, size, part.CFrame, part.Size) then
					continue
				end
				local travelled = 0
				while travelled <= length do
					if overlaps(start + direction * travelled, size, part.CFrame, part.Size) then
						if best == nil or travelled < (best :: number) then
							best = travelled
						end
						break
					end
					travelled += 0.001
				end
			end
			return best
		end
	end

	local function block(frame: CFrame, size: Vector3): Part
		local part = Instance.new("Part")
		part.Size = size
		part.CFrame = frame
		part.Anchored = true
		return part
	end

	-- A wall across the step whose face stands `gap` studs behind the root's box.
	local function wallBehind(gap: number): Part
		return block(avatar.base * CFrame.new(0, 0, rootSize.Z / 2 + gap + 0.5), Vector3.new(20, 10, 1))
	end

	-- A 1-stud pillar behind the root's box, its near face `gap` studs back, `side` studs off the line.
	local function pillarBehind(gap: number, side: number, yawDegrees: number?): Part
		local frame = avatar.base * CFrame.new(side, 0, rootSize.Z / 2 + gap + 0.5)
		if yawDegrees ~= nil then
			-- Turned about its own axis; its corner then points at the body (half its diagonal out).
			local corner = math.sqrt(0.5) - 0.5
			frame = avatar.base
				* CFrame.new(side, 0, rootSize.Z / 2 + gap + 0.5 + corner)
				* CFrame.Angles(0, math.rad(yawDegrees), 0)
		end
		return block(frame, Vector3.new(1, 10, 1))
	end

	local function roomWith(world: { Instance }, distance: number): number
		local cast = ContactPredictor.worldCast(avatar.model, engineCast(world))
		return ContactPredictor.room(avatar.base, rootSize, AWAY, distance, cast)
	end

	it("keeps a gap from the world that is under one step", function()
		expect(GAP > 0).toBe(true)
		expect(GAP <= STAND_OFF.stepStuds + 1e-9).toBe(true)
	end)

	it("measures the room behind the root's box, its gap short of a wall, a pillar or a pillar's corner", function()
		expect(roomWith({}, 1.5)).toBeCloseTo(1.5, 1e-9)
		expect(roomWith({ wallBehind(3) }, 1.5)).toBeCloseTo(1.5, 1e-9)
		expect(roomWith({ wallBehind(0.3) }, 1.5)).toBeCloseTo(0.3 - GAP, 0.003)
		-- Against the wall already, or a hair into it: no room, never through it.
		expect(roomWith({ wallBehind(0) }, 1.5)).toBe(0)
		expect(roomWith({ wallBehind(-GAP / 2) }, 1.5)).toBe(0)
		-- Never more than asked.
		expect(roomWith({ wallBehind(0.3) }, 0.1)).toBeCloseTo(0.1, 1e-9)
		-- A pillar on the line, one that only clips the box's edge, one beside it, one corner-on.
		expect(roomWith({ pillarBehind(0.4, 0) }, 1.5)).toBeCloseTo(0.4 - GAP, 0.003)
		local clip = rootSize.X / 2 + 0.5 - 0.1
		expect(roomWith({ pillarBehind(0.4, clip) }, 1.5)).toBeCloseTo(0.4 - GAP, 0.003)
		local beside = rootSize.X / 2 + 0.5 + 0.1
		expect(roomWith({ pillarBehind(0.4, beside) }, 1.5)).toBeCloseTo(1.5, 1e-9)
		expect(roomWith({ pillarBehind(0.5, 0, 45) }, 1.5)).toBeCloseTo(0.5 - GAP, 0.003)
	end)

	it("never meets a fighter: the body itself, an enemy, a stand-in or another player", function()
		local scene = Instance.new("Folder")
		local enemies = Instance.new("Folder")
		enemies.Name = World.playground.folders.enemies
		enemies.Parent = scene
		local entities = Instance.new("Folder")
		entities.Name = World.playground.folders.entities
		entities.Parent = scene
		local boar = place(setupOf("BoarSide"), 1.8)
		local behind = avatar.base * CFrame.new(0, 0, rootSize.Z / 2 + 0.3 + 0.5)
		-- An enemy and a stand-in right behind the body, and another player's character there too.
		local enemy = Instance.new("Model")
		block(behind, Vector3.new(4, 10, 1)).Parent = enemy
		enemy.Parent = enemies
		local dummy = Instance.new("Model")
		block(behind, Vector3.new(4, 10, 1)).Parent = dummy
		dummy.Parent = entities
		local other = Instance.new("Model")
		block(behind, Vector3.new(4, 10, 1)).Parent = other
		local fighters = ContactPredictor.fighters(avatar.model, scene, {
			{ Character = other },
			{ Character = nil },
			{ Character = avatar.model },
		})
		for _, expected in { avatar.model, enemies, entities, other } do
			expect(table.find(fighters, expected)).never.toBeNil()
		end
		local count = 0
		for _, item in fighters do
			if item == avatar.model then
				count += 1
			end
		end
		expect(count).toBe(1)
		local excludes: { { Instance } } = {}
		local cast =
			ContactPredictor.worldCast(avatar.model, engineCast({ enemy, dummy, other, boar }, excludes), fighters)
		expect(ContactPredictor.room(avatar.base, rootSize, AWAY, 1.5, cast)).toBeCloseTo(1.5, 1e-9)
		expect(excludes[1]).toBe(fighters)
		-- Without that list they would stop it.
		local bare = ContactPredictor.worldCast(avatar.model, engineCast({ enemy }), { avatar.model })
		expect(ContactPredictor.room(avatar.base, rootSize, AWAY, 1.5, bare) < 0.3).toBe(true)
		boar:Destroy()
	end)

	it("takes the longest step the world behind leaves, none against a wall it touches", function()
		local open = standOffFor("OneHandedSword.RisingArc", "BoarSide", 1.8)
		expect(open).never.toBeNil()
		local need = open.distance
		local clip = artClip("OneHandedSword.RisingArc")
		local model = place(setupOf("BoarSide"), 1.8)
		local from = holdTime(clip)
		local function planWith(world: { Instance }): any
			local cast = ContactPredictor.worldCast(avatar.model, engineCast(world), { avatar.model })
			return ContactPredictor.standOff(avatar.model, clip, from, avatar.base, model, cast)
		end
		-- Room enough: the same step, and the plan carries the world for the frames that take it.
		local far = planWith({ wallBehind(3) })
		expect(far.distance).toBeCloseTo(need, 1e-9)
		expect(typeof(far.room)).toBe("function")
		expect(far.room(avatar.base, 0.2)).toBeCloseTo(0.2, 1e-9)
		-- A wall nearer than the step: the longest whole step that keeps the gap.
		for _, wall in { 0.3, 0.17, need - 0.01 } do
			local plan = planWith({ wallBehind(wall) })
			local fits = math.floor((wall - GAP) / STAND_OFF.stepStuds + 1e-6) * STAND_OFF.stepStuds
			expect(plan).never.toBeNil()
			expect(plan.distance).toBeCloseTo(fits, 1e-6)
			expect(wall - plan.distance >= GAP - 0.003).toBe(true)
			-- The frames that take it meet the same wall: the rest of the step is not there.
			expect(plan.room(avatar.base + AWAY * plan.distance, need) <= 0.003 + STAND_OFF.stepStuds).toBe(true)
			-- Still never a hit lost: a shorter step leaves every cut at least as deep as the full one.
			for index, window in ClipSampler.hitWindows(clip) do
				local function deepest(back: number): number
					local best = math.huge
					for k = 0, 48 do
						local time = window.open + (window.close - window.open) * k / 48
						best = math.min(best, gap(model, clip, rootAt(clip, from, time, AWAY, back), time))
					end
					return best
				end
				if index == 1 or deepest(0) <= PROMISE then
					expect(deepest(plan.distance) <= PROMISE).toBe(true)
				end
			end
		end
		-- Backed against the wall (or a pillar on the line): no step at all.
		expect(planWith({ wallBehind(0) })).toBeNil()
		expect(planWith({ wallBehind(GAP / 2) })).toBeNil()
		expect(planWith({ pillarBehind(0.02, 0) })).toBeNil()
		-- A pillar beside the line leaves the step whole.
		local beside = planWith({ pillarBehind(0.1, rootSize.X / 2 + 0.6) })
		expect(beside.distance).toBeCloseTo(need, 1e-9)
		model:Destroy()
	end)
end)

describe("the Art stand-off steps back from the body, not from the weapon it holds (D-277)", function()
	it("the Rising Arc's start pose that meets only the kobold's club takes no step", function()
		local plan, clip, model, from = standOffFor("OneHandedSword.RisingArc", "Kobold", 3.5)
		expect(plan).toBeNil()
		-- The start pose is in the club, and clear of the body.
		local window = ClipSampler.hitWindows(clip)[1]
		local still = rootAt(clip, from, window.open, Vector3.zero, 0)
		local held = Rigs[Enemies.byId(setupOf("Kobold").enemy).skin].trailParts
		expect(gap(model, clip, still, window.open) < STAND_OFF.clearStuds).toBe(true)
		expect(gap(model, clip, still, window.open, held) >= STAND_OFF.clearStuds).toBe(true)
		model:Destroy()
	end)
end)
