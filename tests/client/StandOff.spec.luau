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

-- An enemy's rig in its rest pose where the hit matrix stands it (its bearing, yaw and height),
-- `below` studs lower when it stands on ground below the player's.
local function place(setup: any, distance: number, below: number?): any
	local def = Enemies.byId(setup.enemy)
	local model = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local bearing = math.rad(setup.bearing or 0)
	local frame = avatar.base
		* CFrame.new(
			math.sin(bearing) * distance,
			height - avatar.rootHeight - (below or 0),
			-math.cos(bearing) * distance
		)
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

-- The clip time an Art's activation hold ends (the tell): its first ActivationHold plus its hold.
local function holdEnd(clip: any): number
	for _, event in clip.events do
		if event.kind == "ActivationHold" then
			return event.time + event.data.hold
		end
	end
	error(clip.id .. " has no ActivationHold")
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

local function standOffFor(artId: string, setupId: string, distance: number, below: number?): (any, any, any, number)
	local clip = artClip(artId)
	local model = place(setupOf(setupId), distance, below)
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
		-- The step waits for the activation hold (D-604): it starts where stepStart puts it, after
		-- the release and by the hold's end (0.25), as late as the speed lets a step this long.
		expect(plan.from).toBe(ContactPredictor.stepStart(clip, from, window.open, plan.distance))
		expect(plan.from >= from and plan.from <= holdEnd(clip) + 1e-9).toBe(true)
		expect(plan.still).toBeCloseTo(holdEnd(clip), 1e-9)
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
			{ { "OneHandedSword.Vertical", "Kobold", 2.3 }, { "OneHandedSword.Horizontal", "BoarFacing", 7 } } :: { { any } }
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
			-- Where that step starts (D-604): it waits for the hold as far as the speed lets it.
			from = ContactPredictor.stepStart(clip, from, open, STAND_OFF.maxStuds)
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

describe("the Art stand-off waits for the activation hold (D-604)", function()
	local CAP: number = STAND_OFF.keepOut.maxSpeedStudsPerSecond
	local PIECE: number = STAND_OFF.keepOut.sampleSeconds / STAND_OFF.keepOut.speedPieces
	local FRAME_RATES = { 30, 60, 144 }

	-- The fastest a step from `start` to `to` moves the body over any frame at `fps`, at every frame
	-- phase of the hit matrix, and its first moving frame's speed (the most of the phases).
	local function frameSpeeds(distance: number, start: number, to: number, fps: number): (number, number)
		local frame = 1 / fps
		local fastest, first = 0, 0
		for _, phase in Dev.hitMatrix.framePhases do
			local time, before, moved = start - phase * frame, 0, false
			while time < to + frame do
				time += frame
				local after = AimLogic.standOffAt(distance, start, to, time, STAND_OFF.easing)
				local speed = (after - before) / frame
				fastest = math.max(fastest, speed)
				if not moved and after > before then
					first, moved = math.max(first, speed), true
				end
				before = after
			end
		end
		return fastest, first
	end

	it("starts at the hold's end, or as late before it as the speed cap allows, and lands by the open", function()
		for _, artId in Playground.loadout.artSlots do
			local clip = artClip(artId)
			local open = ClipSampler.hitWindows(clip)[1].open
			local ends = holdEnd(clip)
			expect(ends < open).toBe(true)
			-- Released at the hold pose, a frame past it at 60 fps, and early (a tap).
			for _, from in { holdTime(clip), holdTime(clip) + 1 / 60, holdTime(clip) / 2 } do
				for k = 1, math.round(STAND_OFF.maxStuds / STAND_OFF.stepStuds) do
					local distance = k * STAND_OFF.stepStuds
					local start = ContactPredictor.stepStart(clip, from, open, distance)
					expect(start >= from - 1e-9 and start <= ends + 1e-9).toBe(true)
					expect(AimLogic.standOffAt(distance, start, open, open, STAND_OFF.easing)).toBe(distance)
					local fastest = select(1, frameSpeeds(distance, start, open, 144))
					if start > from + 1e-9 then
						-- Waiting never takes it past the cap at any frame rate.
						for _, fps in FRAME_RATES do
							expect(select(1, frameSpeeds(distance, start, open, fps)) <= CAP + 1e-6).toBe(true)
						end
						-- And it waits as long as the cap lets it: the hold's end, or a piece later
						-- would be too fast.
						if start < ends - 1e-9 then
							local later = select(1, frameSpeeds(distance, start + PIECE, open, 144))
							expect(later > CAP - 1e-6).toBe(true)
						end
					else
						-- A step even the release leaves too fast keeps the release's timing (the
						-- longest it can take).
						expect(start).toBeCloseTo(from, 1e-9)
						expect(fastest > CAP - 0.5).toBe(true)
					end
				end
			end
		end
	end)

	it("keeps the release's timing for a basic (no hold) and an Art released past its hold", function()
		local basic = Harness.load("src/shared/clips/player/OneHandedSword/Basic1")
		local open = ClipSampler.hitWindows(basic)[1].open
		expect(ContactPredictor.stepStart(basic, 0, open, 0.3)).toBe(0)
		local vertical = artClip("OneHandedSword.Vertical")
		local late = holdEnd(vertical) + 0.01
		expect(ContactPredictor.stepStart(vertical, late, ClipSampler.hitWindows(vertical)[1].open, 0.3)).toBe(late)
	end)

	it("a hold that ends at or past the open steps as late before the open as the cap allows", function()
		local vertical = table.clone(artClip("OneHandedSword.Vertical"))
		local open = ClipSampler.hitWindows(vertical)[1].open
		local events = {}
		for _, event in vertical.events do
			if event.kind == "ActivationHold" then
				event = table.clone(event)
				event.data = { hold = open - event.time + 0.05 }
			end
			table.insert(events, event)
		end
		vertical.events = events
		local from = holdTime(vertical)
		local start = ContactPredictor.stepStart(vertical, from, open, 0.3)
		expect(start > from and start < open).toBe(true)
		expect(select(1, frameSpeeds(0.3, start, open, 144)) <= CAP + 1e-6).toBe(true)
		expect(select(1, frameSpeeds(0.3, start + PIECE, open, 144)) > CAP - 1e-6).toBe(true)
	end)

	it("prints the first frame's step at 30, 60 and 144 fps for the steps an Art asks for", function()
		for _, artId in { "OneHandedSword.Vertical", "OneHandedSword.RisingArc" } do
			local clip = artClip(artId)
			local open = ClipSampler.hitWindows(clip)[1].open
			local from = holdTime(clip) + 1 / 60
			for _, distance in { 0.3, 0.6, 1.0, 1.5 } do
				local start = ContactPredictor.stepStart(clip, from, open, distance)
				local cells = {}
				for _, fps in FRAME_RATES do
					local fastest, first = frameSpeeds(distance, start, open, fps)
					table.insert(
						cells,
						("%d fps first %.3f (%.1f/s) most %.1f/s"):format(fps, first / fps, first, fastest)
					)
				end
				print(
					("[H1 step] %s %.2f studs from %.4f (release %.4f, open %.4f): %s"):format(
						artId,
						distance,
						start,
						from,
						open,
						table.concat(cells, "; ")
					)
				)
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
				local list: { Instance } = if item:IsA("BasePart") then { item :: Instance } else item:GetDescendants()
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
		local fighters = ContactPredictor.fighters(
			avatar.model,
			scene,
			{
				{ Character = other },
				{ Character = nil },
				{ Character = avatar.model },
			} :: { any }
		)
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
		-- A wall nearer than the step: the longest whole step that keeps the gap, from whichever
		-- colliding part stands farthest back (D-517: the matrix avatar's Head, 0.055 behind the
		-- root's box; the root's box alone let the step take that 0.055 too), as it stands now or
		-- as the clip poses it anywhere from the step on (D-534: the step stays, and Rising Arc's
		-- later lean carries the head and torsos past where they stood).
		local widest = 0
		local function backmost(rootFrame: CFrame, frames: { [string]: CFrame }): number
			local most = 0
			for _, name in STAND_OFF.keepOut.parts do
				local part = avatar.model:FindFirstChild(name)
				if part ~= nil and part:IsA("BasePart") and frames[name] ~= nil then
					local frame = rootFrame:ToObjectSpace(frames[name])
					local half = part.Size / 2
					for _, x in { -1, 1 } do
						for _, y in { -1, 1 } do
							for _, z in { -1, 1 } do
								local corner = frame * Vector3.new(x * half.X, y * half.Y, z * half.Z)
								most = math.max(most, corner.Z - rootSize.Z / 2)
								widest = math.max(widest, math.abs(corner.X) - rootSize.X / 2)
							end
						end
					end
				end
			end
			return most
		end
		local live: { [string]: CFrame } = {}
		for _, name in STAND_OFF.keepOut.parts do
			local part = avatar.model:FindFirstChild(name)
			if part ~= nil and part:IsA("BasePart") then
				live[name] = part.CFrame
			end
		end
		local standing = backmost(avatar.model.PrimaryPart.CFrame, live)
		expect(standing > 0.05).toBe(true)
		local behind = standing
		local time = from
		while true do
			behind = math.max(
				behind,
				backmost(CFrame.identity, Pose.solve(avatar.model, CFrame.identity, ClipSampler.sample(clip, time)))
			)
			if time >= clip.duration then
				break
			end
			time = math.min(time + STAND_OFF.keepOut.sampleSeconds, clip.duration)
		end
		-- The clip's lean past the standing column is what the old walls (0.3 and 0.17 behind the
		-- root's box) gave the step: it is now the clip's own, so the walls stand that far back.
		expect(behind > standing).toBe(true)
		for _, wall in { behind + 0.3 - standing, behind + 0.17 - standing, behind + GAP + need - 0.01 } do
			local plan = planWith({ wallBehind(wall) })
			local fits = math.floor((wall - behind - GAP) / STAND_OFF.stepStuds + 1e-6) * STAND_OFF.stepStuds
			expect(plan).never.toBeNil()
			expect(plan.distance).toBeCloseTo(fits, 1e-6)
			expect(wall - behind - plan.distance >= GAP - 0.003).toBe(true)
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
		-- A pillar beside the line leaves the step whole (beside what the clip's poses sweep too).
		local beside = planWith({ pillarBehind(0.1, rootSize.X / 2 + widest + 0.6) })
		expect(beside.distance).toBeCloseTo(need, 1e-9)
		model:Destroy()
	end)

	-- Item 410 (D-517): with the back flush to a wall the drawn body touches it with its torso,
	-- which the idle leans 0.28 behind the root's box. The room was cast with the root's box alone,
	-- so the keep-out's step back carried the torso into the wall for the engine to push out (the
	-- PC: the root box 0.48 in and the body slid 3.1 to 3.4 along the wall), and a torso the clip
	-- had already leant into the wall was never met (a cast never meets a part it starts in).
	it("never steps a torso or the head into a wall the root's box stands clear of (item 410)", function()
		local swings = {
			{ name = "Basic1", clip = Harness.load("src/shared/clips/player/OneHandedSword/Basic1"), art = false },
			{ name = "SharpNail", clip = artClip("OneHandedSword.SharpNail"), art = true },
		}
		local saved: { [BasePart]: CFrame } = {}
		for _, part in avatar.model:GetDescendants() do
			if part:IsA("BasePart") then
				saved[part] = part.CFrame
			end
		end
		local enemy = place(setupOf("Kobold"), 2.3)
		RigBuilder.addBlocker(enemy)
		for _, child in enemy:GetChildren() do
			if child:IsA("BasePart") and child.Name == STAND_OFF.keepOut.bodyFace then
				child.CanCollide = true
			end
		end
		for _, swing in swings do
			local from = if swing.art then holdTime(swing.clip) else 0
			-- The body in the swing's own start pose, as the plan finds it.
			for name, solved in Pose.solve(avatar.model, avatar.base, ClipSampler.sample(swing.clip, from)) do
				local part = avatar.model:FindFirstChild(name)
				if part ~= nil and part:IsA("BasePart") then
					part.CFrame = solved
				end
			end
			-- How far the column's backmost corner stands behind the root's box.
			local behind, who = 0, ""
			for _, name in STAND_OFF.keepOut.parts do
				local part = avatar.model:FindFirstChild(name) :: BasePart
				local frame = avatar.base:ToObjectSpace(part.CFrame)
				local half = part.Size / 2
				for _, x in { -1, 1 } do
					for _, y in { -1, 1 } do
						for _, z in { -1, 1 } do
							local back = (frame * Vector3.new(x * half.X, y * half.Y, z * half.Z)).Z - rootSize.Z / 2
							if back > behind then
								behind, who = back, name
							end
						end
					end
				end
			end
			-- A wall the clip has already leant the part 0.1 into, one it touches, one 0.3 behind it.
			for _, clear in { -0.1, 0, 0.3 } do
				local wall = wallBehind(behind + clear)
				local cast = ContactPredictor.worldCast(avatar.model, engineCast({ wall }), { avatar.model })
				local plan = ContactPredictor.standOff(
					avatar.model,
					swing.clip,
					from,
					avatar.base,
					enemy,
					cast,
					{ keepOut = true, step = swing.art }
				)
				expect(plan).never.toBeNil()
				expect(typeof(plan.room)).toBe("function")
				local step = plan.room(avatar.base, 1)
				-- After the step, how deep the backmost part stands in the wall (negative: short of it):
				-- the gap short of it, or no step at all from a wall it already touches.
				local into = behind + step - (behind + clear)
				local allowed = if clear >= GAP then -GAP else -clear
				print(
					("[410] %s, %s %.3f behind the root's box, wall %.2f past it: step %.3f, %s %.3f into the wall"):format(
						swing.name,
						who,
						behind,
						clear,
						step,
						who,
						into
					)
				)
				if into > allowed + 0.003 then
					error(
						("%s: the step %.3f put %s %.3f into a wall %.2f behind it"):format(
							swing.name,
							step,
							who,
							into,
							clear
						)
					)
				end
				wall:Destroy()
			end
		end
		for part, frame in saved do
			part.CFrame = frame
		end
		enemy:Destroy()
	end)
end)

describe("the Art stand-off steps back from the body, not from the weapon it holds (D-277)", function()
	it("the Rising Arc's start pose that meets only the kobold's club takes no step", function()
		-- The kobold on ground 0.2 below the player's: its rest pose stands on its floor (D-483), so
		-- on level ground its club hangs 0.27 above where the cut starts, clear of it; 0.2 lower it
		-- holds the club where the cut starts, as it did when its feet stood 0.2 into the field.
		local plan, clip, model, from = standOffFor("OneHandedSword.RisingArc", "Kobold", 3.5, 0.2)
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

-- ------------------------------------------------------------------ the sword on the back (D-537)

-- The plan poses the blade as the swing holds it: in the hand. This client alone hangs the sword on
-- its back mount between fights (WeaponMount: the Weapon motor's Part0 and C0 rewritten, the server
-- and the hit matrix keep it in the hand), and a plan made on a frame that still drew it there read
-- the blade off the back: the PC's plan probe (the sword on the back after a timed-out draw) gave
-- the third basic no keep-out at all at 3.2 to 3.75 studs from a held kobold and the first basic
-- none at 3.5 (Lune 1.30 to 0.75 and 1.05 with it in the hand), so the cut went 0.47 into the body.
describe("a sword this client hangs on its back is planned in the hand (item 437(e), D-537)", function()
	it("plans the keep-out and the blade step exactly as with the sword in the hand", function()
		local WeaponModels = Harness.load("src/shared/data/weaponModels")
		local motor: Motor6D? = nil
		for _, each in avatar.model:GetDescendants() do
			if each:IsA("Motor6D") and each.Name == WeaponModels.motorName then
				motor = each :: Motor6D
			end
		end
		assert(motor ~= nil, "the matrix body holds its sword on a Weapon motor")
		local hand, handC0 = motor.Part0, motor.C0
		local row = WeaponModels.sheaths.OneHandedSword
		local back = avatar.model:FindFirstChild(row.part) :: BasePart
		local setup = setupOf("Kobold")
		local swings = {
			{ clip = Harness.load("src/shared/clips/player/OneHandedSword/Basic1"), from = 0, step = false },
			{ clip = Harness.load("src/shared/clips/player/OneHandedSword/Basic3"), from = 0, step = false },
		}
		for _, artId in { "OneHandedSword.SharpNail", "OneHandedSword.RisingArc" } do
			local clip = artClip(artId)
			table.insert(swings, { clip = clip, from = holdTime(clip), step = true })
		end
		local function planned(swing: any, distance: number): any
			local model = place(setup, distance)
			RigBuilder.addBlocker(model)
			local plan = ContactPredictor.standOff(
				avatar.model,
				swing.clip,
				swing.from,
				avatar.base,
				model,
				nil,
				{ keepOut = true, step = swing.step }
			)
			model:Destroy()
			return plan
		end
		local moved = 0
		for _, swing in swings do
			for _, distance in { 2.3, 3.2, 3.5, 3.75 } do
				motor.Part0, motor.C0 = hand, handC0
				local held = planned(swing, distance)
				motor.Part0, motor.C0 = back, ClipSampler.toCFrame(row.mount)
				local sheathed = planned(swing, distance)
				motor.Part0, motor.C0 = hand, handC0
				expect(held ~= nil).toBe(sheathed ~= nil)
				if held == nil then
					continue
				end
				expect(sheathed.distance).toBeCloseTo(held.distance, 1e-9)
				local time = swing.from
				while time <= swing.clip.duration do
					local keep = if held.keep ~= nil then held.keep(time) else 0
					expect(if sheathed.keep ~= nil then sheathed.keep(time) else 0).toBeCloseTo(keep, 1e-9)
					if held.keepSide ~= nil then
						expect(sheathed.keepSide(time)).toBeCloseTo(held.keepSide(time), 1e-9)
					end
					moved = math.max(moved, keep + held.distance)
					time += STAND_OFF.keepOut.sampleSeconds
				end
			end
		end
		-- The cases above step the body: a plan that read nothing would pass them with zeros.
		expect(moved > 1).toBe(true)
	end)
end)

describe("the plan reads how the target moves on off its rig's handles (D-565)", function()
	it("takes the Base clip that shows, on from its clock, and the flinch it is given", function()
		local idle = Harness.load("src/shared/clips/enemy/Kobold/Idle")
		local walk = Harness.load("src/shared/clips/enemy/Kobold/Walk")
		local flinch = Harness.load("src/shared/clips/enemy/Kobold/FlinchFront")
		local base = { layer = "Base", clip = idle, time = 1.25, speed = 1, fade = 0.4, weight = 1 }
		local handles: { any } = {
			-- A walk fading out under it, a stopped one and the flinch's own Additive handle: none.
			{ layer = "Base", clip = walk, time = 0.3, speed = 1, fade = 0.9, weight = 1, stopping = true },
			{ layer = "Base", clip = walk, time = 0.3, speed = 1, fade = 1, weight = 1, done = true },
			{ layer = "Additive", clip = flinch, time = 0.1, speed = 1, fade = 1, weight = 1 },
			base,
		}
		local motion = ContactPredictor.targetMotion(handles, flinch)
		assert(motion ~= nil and motion.base ~= nil, "a motion with its Base clip")
		expect(motion.base.clip).toBe(idle)
		expect(motion.base.time).toBe(1.25)
		expect(motion.base.speed).toBe(1)
		expect(motion.flinch).toBe(flinch)
		-- A held handle (Mixer.hold) stands still; one at half speed runs at half speed.
		base.held = true
		expect((ContactPredictor.targetMotion(handles, nil) :: any).base.speed).toBe(0)
		base.held, base.speed = false, 0.5
		expect((ContactPredictor.targetMotion(handles, nil) :: any).base.speed).toBe(0.5)
		-- Nothing that shows and no flinch: no motion (the plan reads the target as it stands).
		expect(ContactPredictor.targetMotion({ handles[1], handles[3] }, nil)).toBe(nil)
		expect(ContactPredictor.targetMotion({}, flinch) ~= nil).toBe(true)
	end)

	it("plans exactly as before with no motion, and as the parts stand at the start with one", function()
		local setup = setupOf("Kobold")
		local clip = Harness.load("src/shared/clips/player/OneHandedSword/Basic1")
		local idle = Harness.load("src/shared/clips/enemy/Kobold/Idle")
		local model = place(setup, 3.3)
		RigBuilder.addBlocker(model)
		local function planned(target: any): any
			return ContactPredictor.standOff(
				avatar.model,
				clip,
				0,
				avatar.base,
				model,
				nil,
				{ keepOut = true, step = false, target = target }
			)
		end
		local still = planned(nil)
		-- An idle that does not move (speed 0) at the rest pose's clock leaves the plan the same.
		local frozen = planned({ base = { clip = idle, time = 0, speed = 0 } })
		assert(still ~= nil and frozen ~= nil, "both plan a keep-out")
		local time = 0
		while time <= clip.duration do
			expect(frozen.keep(time)).toBeCloseTo(still.keep(time), 1e-6)
			time += Combat.contact.standOff.keepOut.sampleSeconds
		end
		model:Destroy()
	end)
end)
