--!strict
--[[
	Bodies touch, never inside (item 236, item 222): a player who walks into a standing enemy stops
	where the parts the engine collides meet the enemy's blocker faces (D-198, D-237, D-315), and at
	rest there no part of the player's body (the arms and hands too, not only the root, torsos and
	head the engine collides) stands inside a part of the enemy's body, sheathed (Idle) or drawn
	(IdleDrawn), on every side the Studio walk-in tried.

	The player is the hit matrix's avatar (dev.luau hitMatrix.avatar: the engine's blank R15 at
	rigs.luau PlayerR15.scale); the enemies are RigBuilder's rigs with their blocker faces, posed over
	their idle loops. What stops the walk-in is combat.luau contact.standOff.keepOut.parts (what the
	engine collides of a character) plus, once the fix lands, the body shell the character carries
	(RigBuilder.playerShell(model, drawn): boxes in the root's space that collide with the faces).
	The sword is not body: a blade beside an axe is a weapon contact.

	On cebade4 (no shell) it fails: the drawn left hand stands 1.08 studs inside a side-on boar's
	torso on both flanks, 0.51 inside a kobold's right arm head-on and 0.46 inside its torso from
	behind; the sheathed left hand 0.16 inside the kobold's axe head-on and the sheathed right hand
	0.08 inside the boar's flank (Studio: "the head and arms sit inside the boar's torso", "arms and
	hands overlap the kobold's arm, torso and axe"). It stays failing until the shell lands.
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

-- A body part inside an enemy's part by more than this is inside (the gap the stand-off keeps).
local TOUCH: number = Combat.contact.standOff.wallGapStuds
-- The sides the Studio walk-in tried: head-on, both flanks, behind.
local BEARINGS = { 0, 90, 180, 270 }
-- Pose samples: the idles breathe slowly (12 s player loops, 4 s enemy loops).
local PLAYER_STEP = 1
local ENEMY_STEP = 1

local colliding: { string } = Combat.contact.standOff.keepOut.parts
local held: { string } = Rigs.PlayerR15.trailParts or {}
local body: { string } = {}
for name in Dev.hitMatrix.avatar.parts do
	if table.find(held, name) == nil and name ~= Rigs.PlayerR15.rootPart then
		table.insert(body, name)
	end
end
table.sort(body)
local sizes: { [string]: Vector3 } = {}
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") then
		sizes[part.Name] = part.Size
	end
end

-- How deep two boxes overlap: the least push along the fifteen separating axes (0 or less apart).
local function depth(a: CFrame, aSize: Vector3, b: CFrame, bSize: Vector3): number
	local axesA = { a.RightVector, a.UpVector, a.LookVector }
	local axesB = { b.RightVector, b.UpVector, b.LookVector }
	local halfA = { aSize.X / 2, aSize.Y / 2, aSize.Z / 2 }
	local halfB = { bSize.X / 2, bSize.Y / 2, bSize.Z / 2 }
	local between = b.Position - a.Position
	local least = math.huge
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
		least = math.min(least, reach - math.abs(between:Dot(unit)))
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
	return least
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

local STANCES = {
	{
		label = "sheathed",
		drawn = false,
		poses = samples(Harness.load("src/shared/clips/player/OneHandedSword/Idle"), PLAYER_STEP),
	},
	{
		label = "drawn",
		drawn = true,
		poses = samples(Harness.load("src/shared/clips/player/OneHandedSword/IdleDrawn"), PLAYER_STEP),
	},
}

type Box = { name: string, frame: CFrame, size: Vector3 }

-- The shell the fix gives the character (RigBuilder.playerShell), in the root's space; none yet.
local function shellOf(drawn: boolean): { Box }
	local builder = (RigBuilder :: any).playerShell
	if typeof(builder) ~= "function" then
		return {}
	end
	return builder(model, drawn)
end

describe("a walk-in stops with the bodies touching, never inside (items 236, 222)", function()
	for _, enemyId in { "KoboldAxeman", "FrenzyBoar" } do
		it(("at rest on every side of the %s, no part of the body stands inside it"):format(enemyId), function()
			local def = Enemies.byId(enemyId)
			local rig = Rigs[def.skin]
			local enemy = RigBuilder.build(def.skin)
			local height =
				PlaygroundLayout.rootHeight(rig.hipHeight, enemy.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
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
						table.insert(faces, { name = child.Name, frame = child.CFrame, size = child.Size })
					else
						enemySizes[child.Name] = child.Size
					end
				end
			end
			expect(#faces > 0).toBe(true)
			-- The enemy's body over its idle loop, where it stands.
			local enemyPoses: { { Box } } = {}
			for _, offsets in samples(Harness.load("src/shared/clips/enemy/" .. def.skin .. "/Idle"), ENEMY_STEP) do
				local list: { Box } = {}
				for name, frame in Pose.solve(enemy, enemyFrame, offsets) do
					if enemySizes[name] ~= nil then
						table.insert(list, { name = name, frame = frame, size = enemySizes[name] })
					end
				end
				table.insert(enemyPoses, list)
			end
			local centre = enemyFrame.Position
			-- The root `distance` from the enemy's root at `bearing` round it, facing it.
			local function rootAt(bearing: number, distance: number): CFrame
				local turn = math.rad(bearing)
				local at = Vector3.new(
					centre.X + math.sin(turn) * distance,
					avatar.base.Position.Y,
					centre.Z - math.cos(turn) * distance
				)
				return CFrame.lookAt(at, Vector3.new(centre.X, at.Y, centre.Z))
			end
			local problems: { string } = {}
			for _, stance in STANCES do
				local shell = shellOf(stance.drawn)
				-- How deep what the engine collides stands in a face, the root at `frame`.
				local function stopDepth(frame: CFrame): number
					local worst = -math.huge
					for _, offsets in stance.poses do
						local solved = Pose.solve(model, frame, offsets)
						for _, name in colliding do
							for _, face in faces do
								worst = math.max(worst, depth(solved[name], sizes[name], face.frame, face.size))
							end
						end
					end
					for _, box in shell do
						for _, face in faces do
							worst = math.max(worst, depth(frame * box.frame, box.size, face.frame, face.size))
						end
					end
					return worst
				end
				for _, bearing in BEARINGS do
					local near, far = 0, 14
					for _ = 1, 30 do
						local mid = (near + far) / 2
						if stopDepth(rootAt(bearing, mid)) > 0 then
							near = mid
						else
							far = mid
						end
					end
					local frame = rootAt(bearing, far)
					local deepest, where = 0, ""
					for _, offsets in stance.poses do
						local solved = Pose.solve(model, frame, offsets)
						for _, name in body do
							local partFrame, partSize = solved[name], sizes[name]
							local reach = partSize.Magnitude / 2
							for _, list in enemyPoses do
								for _, other in list do
									if
										(partFrame.Position - other.frame.Position).Magnitude
										< reach + other.size.Magnitude / 2
									then
										local inside = depth(partFrame, partSize, other.frame, other.size)
										if inside > deepest then
											deepest, where = inside, name .. " in " .. other.name
										end
									end
								end
							end
						end
					end
					if deepest > TOUCH then
						table.insert(
							problems,
							("%s %s at %d degrees, rest %.2f: %s %.2f"):format(
								enemyId,
								stance.label,
								bearing,
								far,
								where,
								deepest
							)
						)
					end
				end
			end
			enemy:Destroy()
			expect(problems).toEqual({})
		end)
	end
end)
