--!strict
--[[
	Item 236 (D-430): a walk into a standing enemy ends with the bodies touching, never inside,
	through the real hold (WalkShell.hold on the stick's walk, BodyShell's shell and held shapes,
	the enemy's own blocker faces from RigBuilder.addBlocker).

	The player is the hit matrix's avatar (BodyFit.spec's); the enemies are RigBuilder's rigs with
	their blockers, solid. A frame (60 fps) asks for a walk straight at the enemy from 12 studs at
	8, 16 (the stick) and 24 studs a second (the sprint cap), at BodyFit's bearings, in each stance;
	the hold cuts it (the share of the speed it gives is the Humanoid's WalkSpeed), then the engine
	stops the colliding column (keepOut.parts over the stance's idle) at the blocker faces, never
	past touching. The walk is over once five frames in a row move the root less than a thousandth
	of a stud.

	At rest no part of the body stands deeper than wallGapStuds inside a part of the enemy over its
	idle (BodyFit's measure), the shell never stood deeper than that in what it meets on any frame,
	and a walk-in at the enemy's head or flank rests inside the hit matrix's real-fight range for
	that side (dev.luau hitMatrix realFight.max: past it a basic falls short).

	Before the hold (cebade4 and 7bad96a: no WalkShell) the column alone stops the walk with the
	hands inside the enemy: the drawn left hand 1.08 inside a side-on boar's torso, 0.53 inside a
	kobold's right arm head-on, 0.50 inside its torso from behind; the sheathed left hand 0.30
	inside the kobold's axe head-on.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")

-- The hold under test. Before item 236 there was none: the walk stopped at the column alone.
local loaded, WalkShell = pcall(Harness.load, "src/client/controllers/WalkShell")
local BodyShellLoaded, BodyShell = pcall(Harness.load, "src/shared/choreo/BodyShell")
local hasHold = loaded and BodyShellLoaded

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
local model = avatar.model

local TOUCH: number = Combat.contact.standOff.wallGapStuds
local FRAME = 1 / 60
local SPEEDS = { 8, 16, Combat.maxSpeedStudsPerSecond }
local BEARINGS = { 0, 90, 180, 270 }
local START = 12
-- A frame that moves the root less than this is a frame stopped.
local STILL = 1e-3

-- The farthest a walk-in may rest from each enemy at each bearing: the hit matrix's real-fight
-- range for the setup facing that side (yaw 0: head-on; yaw 90: side-on, both flanks).
local REACH: { [string]: { [number]: number } } = {}
for _, setup in Dev.hitMatrix.setups do
	if setup.bearing ~= nil or setup.pointBlank then
		continue
	end
	local byBearing = REACH[setup.enemy] or {}
	REACH[setup.enemy] = byBearing
	if setup.yaw == 0 then
		byBearing[0] = setup.realFight.max
	elseif setup.yaw == 90 then
		byBearing[90] = setup.realFight.max
		byBearing[270] = setup.realFight.max
	end
end

local colliding: { string } = Combat.contact.standOff.keepOut.parts
local held: { string } = Rigs.PlayerR15.trailParts or {}
local sizes: { [string]: Vector3 } = {}
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") then
		sizes[part.Name] = part.Size
	end
end
local body: { string } = {}
for name in Dev.hitMatrix.avatar.parts do
	if table.find(held, name) == nil and name ~= Rigs.PlayerR15.rootPart then
		table.insert(body, name)
	end
end
table.sort(body)

-- How deep two boxes overlap: the least push along the fifteen separating axes (0 or less apart),
-- and that push's way out for `a` (horizontal or not).
local function depthOut(a: CFrame, aSize: Vector3, b: CFrame, bSize: Vector3): (number, Vector3)
	local axesA = { a.RightVector, a.UpVector, a.LookVector }
	local axesB = { b.RightVector, b.UpVector, b.LookVector }
	local halfA = { aSize.X / 2, aSize.Y / 2, aSize.Z / 2 }
	local halfB = { bSize.X / 2, bSize.Y / 2, bSize.Z / 2 }
	local between = a.Position - b.Position
	local least, out = math.huge, Vector3.yAxis
	local function along(axis: Vector3)
		local length = axis.Magnitude
		if length < 1e-6 then
			return
		end
		local unit = axis / length
		local reach = 0
		for index = 1, 3 do
			reach += halfA[index] * math.abs(axesA[index]:Dot(unit)) + halfB[index] * math.abs(axesB[index]:Dot(unit))
		end
		local apart = between:Dot(unit)
		if reach - math.abs(apart) < least then
			least = reach - math.abs(apart)
			out = if apart >= 0 then unit else -unit
		end
	end
	for _, u in axesA do
		along(u)
	end
	for _, v in axesB do
		along(v)
	end
	for _, u in axesA do
		for _, v in axesB do
			along(u:Cross(v))
		end
	end
	return least, out
end

local function depth(a: CFrame, aSize: Vector3, b: CFrame, bSize: Vector3): number
	return (depthOut(a, aSize, b, bSize))
end

local function samples(clip: any, step: number): { any }
	local list = {}
	local time = 0
	while time <= clip.duration + 1e-9 do
		table.insert(list, ClipSampler.sample(clip, time))
		time += step
	end
	return list
end

type Box = { name: string, frame: CFrame, size: Vector3 }

-- Each stance's idle as root-space boxes: the colliding column and the whole body, every second.
local function stanceOf(label: string, drawn: boolean, clipName: string): any
	local column: { { Box } } = {}
	local whole: { { Box } } = {}
	for _, offsets in samples(Harness.load("src/shared/clips/player/OneHandedSword/" .. clipName), 1) do
		local solved = Pose.solve(model, CFrame.identity, offsets)
		local columnPose: { Box } = {}
		for _, name in colliding do
			table.insert(columnPose, { name = name, frame = solved[name], size = sizes[name] })
		end
		table.insert(column, columnPose)
		local bodyPose: { Box } = {}
		for _, name in body do
			table.insert(bodyPose, { name = name, frame = solved[name], size = sizes[name] })
		end
		table.insert(whole, bodyPose)
	end
	return { label = label, drawn = drawn, column = column, body = whole }
end

local STANCES = {
	stanceOf("sheathed", false, "Idle"),
	stanceOf("drawn", true, "IdleDrawn"),
}

-- A solid enemy where BodyFit stands it: its model, its faces, its parts over its idle.
local function enemyOf(enemyId: string): any
	local def = Enemies.byId(enemyId)
	local rig = Rigs[def.skin]
	local enemy = RigBuilder.build(def.skin)
	local height = PlaygroundLayout.rootHeight(rig.hipHeight, enemy.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local enemyFrame = avatar.base * CFrame.new(0, height - avatar.rootHeight, 0)
	for name, solved in Pose.solve(enemy, enemyFrame, {}) do
		local part = enemy:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	RigBuilder.addBlocker(enemy)
	local faces: { Box } = {}
	local enemySizes: { [string]: Vector3 } = {}
	for _, child in enemy:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == RigBuilder.BLOCKER_NAME or child.Name == RigBuilder.HELD_BLOCKER_NAME then
				-- Solid, as CollisionGroups.assign leaves a standing enemy's faces.
				child.CanCollide = true
				table.insert(faces, { name = child.Name, frame = child.CFrame, size = child.Size })
			else
				enemySizes[child.Name] = child.Size
			end
		end
	end
	local poses: { { Box } } = {}
	for _, offsets in samples(Harness.load("src/shared/clips/enemy/" .. def.skin .. "/Idle"), 1) do
		local list: { Box } = {}
		for name, frame in Pose.solve(enemy, enemyFrame, offsets) do
			if enemySizes[name] ~= nil then
				table.insert(list, { name = name, frame = frame, size = enemySizes[name] })
			end
		end
		table.insert(poses, list)
	end
	return { id = enemyId, model = enemy, faces = faces, poses = poses, centre = enemyFrame.Position }
end

local ENEMIES = { enemyOf("KoboldAxeman"), enemyOf("FrenzyBoar") }

-- The root `distance` from the enemy's root at `bearing` round it, facing it.
local function rootAt(enemy: any, bearing: number, distance: number): CFrame
	local turn = math.rad(bearing)
	local centre = enemy.centre
	local at =
		Vector3.new(centre.X + math.sin(turn) * distance, avatar.base.Position.Y, centre.Z - math.cos(turn) * distance)
	return CFrame.lookAt(at, Vector3.new(centre.X, at.Y, centre.Z))
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- How deep the colliding column stands in the enemy's faces, the root at `at`, and the way out.
local function columnDepth(stance: any, enemy: any, at: CFrame): (number, Vector3)
	local worst, out = -math.huge, Vector3.yAxis
	for _, pose in stance.column do
		for _, box in pose do
			local frame = at * box.frame
			for _, face in enemy.faces do
				local inside, way = depthOut(frame, box.size, face.frame, face.size)
				if inside > worst then
					worst, out = inside, way
				end
			end
		end
	end
	return worst, out
end

-- The share of `move` from `at` the column takes before it stands deeper than `allowed`, and the
-- share where it first does.
local function columnShare(stance: any, enemy: any, at: CFrame, move: Vector3, allowed: number): (number, number)
	if (columnDepth(stance, enemy, at + move)) <= allowed then
		return 1, 1
	end
	local low, high = 0, 1
	for _ = 1, 20 do
		local middle = (low + high) / 2
		if (columnDepth(stance, enemy, at + move * middle)) <= allowed then
			low = middle
		else
			high = middle
		end
	end
	return low, high
end

-- The engine's share of `move`: the column stops touching the faces (never deeper than it stood)
-- and slides along the face it met, as the physics does.
local function engineMove(stance: any, enemy: any, at: CFrame, move: Vector3): Vector3
	local allowed = math.max(0, (columnDepth(stance, enemy, at)))
	local first, meets = columnShare(stance, enemy, at, move, allowed)
	if first >= 1 then
		return move
	end
	local taken = move * first
	local _, out = columnDepth(stance, enemy, at + move * meets)
	local flat = Vector3.new(out.X, 0, out.Z)
	if flat.Magnitude < 1e-6 then
		return taken
	end
	local normal = flat.Unit
	local rest = move - taken
	local along = rest - normal * rest:Dot(normal)
	if along.Magnitude < 1e-6 then
		return taken
	end
	return taken + along * (columnShare(stance, enemy, at + taken, along, allowed))
end

-- The deepest any part of the body stands inside a part of the enemy over its idle, and where.
local function deepestInside(stance: any, enemy: any, at: CFrame): (number, string)
	local deepest, where = 0, ""
	for _, pose in stance.body do
		for _, box in pose do
			local frame = at * box.frame
			local reach = box.size.Magnitude / 2
			for _, list in enemy.poses do
				for _, other in list do
					if (frame.Position - other.frame.Position).Magnitude < reach + other.size.Magnitude / 2 then
						local inside = depth(frame, box.size, other.frame, other.size)
						if inside > deepest then
							deepest, where = inside, box.name .. " in " .. other.name
						end
					end
				end
			end
		end
	end
	return deepest, where
end

-- How deep the shell stands in what it meets, the root at `at` (none before the hold).
local function shellDepth(stance: any, enemy: any, at: CFrame): number
	if not hasHold then
		return -math.huge
	end
	local obstacles = WalkShell.obstaclesOf(enemy.model, {})
	return (WalkShell.deepest(at, BodyShell.boxes(model, stance.drawn), obstacles))
end

-- One frame's walk along `direction` at `speed` from `at`: the hold's share, then the engine's.
local function stepWalk(stance: any, enemy: any, at: CFrame, direction: Vector3, speed: number): Vector3
	local studs = speed * FRAME
	local heldDirection, share = direction, 1
	if hasHold then
		heldDirection, share =
			WalkShell.hold(model, { CFrame = at } :: any, direction, studs, stance.drawn, { { model = enemy.model } })
	end
	if heldDirection.Magnitude < 1e-9 or share <= 0 then
		return Vector3.zero
	end
	local move = Vector3.new(heldDirection.X, 0, heldDirection.Z).Unit * studs * share
	return engineMove(stance, enemy, at, move)
end

-- Walks straight at the enemy from START at `bearing`; the rest and the deepest the shell stood.
local function walkIn(stance: any, enemy: any, bearing: number, speed: number): (CFrame, number)
	local at = rootAt(enemy, bearing, START)
	local deepestShell = -math.huge
	local still = 0
	for _ = 1, 600 do
		local toward = Vector3.new(enemy.centre.X - at.Position.X, 0, enemy.centre.Z - at.Position.Z).Unit
		local move = stepWalk(stance, enemy, at, toward, speed)
		at += move
		deepestShell = math.max(deepestShell, shellDepth(stance, enemy, at))
		still = if move.Magnitude < STILL then still + 1 else 0
		if still >= 5 then
			break
		end
	end
	return at, deepestShell
end

describe("a walk-in ends with the bodies touching, never inside (item 236, D-430)", function()
	for _, enemy in ENEMIES do
		it(("at every side of the %s, in both stances and at every speed"):format(enemy.id), function()
			local problems: { string } = {}
			for _, stance in STANCES do
				for _, bearing in BEARINGS do
					for _, speed in SPEEDS do
						local at, deepestShell = walkIn(stance, enemy, bearing, speed)
						local rest = flatDistance(at.Position, enemy.centre)
						local label = ("%s %s at %d degrees, %d studs/s, rest %.2f"):format(
							enemy.id,
							stance.label,
							bearing,
							speed,
							rest
						)
						local inside, where = deepestInside(stance, enemy, at)
						if inside > TOUCH then
							table.insert(problems, ("%s: %s %.2f"):format(label, where, inside))
						end
						if deepestShell > TOUCH + 1e-6 then
							table.insert(problems, ("%s: the shell stood %.3f deep"):format(label, deepestShell))
						end
						local reach = (REACH[enemy.id] or {})[bearing]
						if reach ~= nil and rest > reach then
							table.insert(
								problems,
								("%s: past the real-fight range (%.2f), a basic falls short"):format(label, reach)
							)
						end
					end
				end
			end
			expect(problems).toEqual({})
		end)
	end

	it("slides along a side-on boar's flank when walked into at 45 degrees, never sticking", function()
		expect(hasHold).toBe(true)
		local boar = ENEMIES[2]
		for _, stance in STANCES do
			local at = rootAt(boar, 90, 5)
			local inward = Vector3.new(boar.centre.X - at.Position.X, 0, boar.centre.Z - at.Position.Z).Unit
			local tangent = Vector3.new(-inward.Z, 0, inward.X)
			local direction = (inward + tangent).Unit
			local start = at.Position
			local deepestShell = -math.huge
			local frames = 90
			for _ = 1, frames do
				at += stepWalk(stance, boar, at, direction, 16)
				deepestShell = math.max(deepestShell, shellDepth(stance, boar, at))
			end
			local sideways = (at.Position - start):Dot(tangent)
			-- The walk's own sideways share is 16 * sin 45 a second; the slide keeps most of it.
			expect(sideways >= 0.8 * 16 * math.sin(math.rad(45)) * frames * FRAME).toBe(true)
			expect(deepestShell <= TOUCH + 1e-6).toBe(true)
		end
	end)

	it("never holds a step out, and never lets a step in go deeper than the body already stands", function()
		expect(hasHold).toBe(true)
		local kobold = ENEMIES[1]
		local drawn = STANCES[2]
		-- The kobold walked in on a drawn player: the hand stands inside the axe's shapes.
		local at = rootAt(kobold, 0, 3.4)
		local before = shellDepth(drawn, kobold, at)
		expect(before > TOUCH).toBe(true)
		local away = Vector3.new(at.Position.X - kobold.centre.X, 0, at.Position.Z - kobold.centre.Z).Unit
		local direction, share =
			WalkShell.hold(model, { CFrame = at } :: any, away, 0.27, true, { { model = kobold.model } })
		expect(direction).toBe(away)
		expect(share).toBe(1)
		local inDirection, inShare =
			WalkShell.hold(model, { CFrame = at } :: any, -away, 0.27, true, { { model = kobold.model } })
		local moved = if inShare > 0 then inDirection.Unit * 0.27 * inShare else Vector3.zero
		expect(shellDepth(drawn, kobold, at + moved) <= before + 1e-6).toBe(true)
	end)

	it("holds nothing against a face that does not collide (a rushing body, a shattered corpse)", function()
		expect(hasHold).toBe(true)
		local kobold = ENEMIES[1]
		local face = kobold.model:FindFirstChild(RigBuilder.BLOCKER_NAME) :: BasePart
		face.CanCollide = false
		local at = rootAt(kobold, 0, 3.4)
		local toward = Vector3.new(kobold.centre.X - at.Position.X, 0, kobold.centre.Z - at.Position.Z).Unit
		local direction, share =
			WalkShell.hold(model, { CFrame = at } :: any, toward, 0.27, true, { { model = kobold.model } })
		face.CanCollide = true
		expect(direction).toBe(toward)
		expect(share).toBe(1)
	end)
end)
