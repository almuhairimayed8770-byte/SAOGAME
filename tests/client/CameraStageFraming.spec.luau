--!strict
--[[
	The ThreeQuarter staged view frames the kobold's overhead (enemy-kobold-overhead) and the parry
	(parry-spark) with the kobold whole and its axe in sight (CS6). Both bodies are posed frame by
	frame at 60 Hz: the player is the hit matrix's avatar with its sword (HitMatrix.standing), the
	kobold the RigBuilder rig with its axe, at the shot's own placement; each clip is sampled with
	ClipSampler and solved with Pose. The camera is CameraController's, set to the shot's view and
	side the way the capture panel sets it (CameraController.setStage).

	A sample point of a kobold part is seen when the ray from the lens reaches it before any part of
	the player's body or sword. A point inside a player part (the axe stuck low beside the player's
	hand in the recovery) is touching, not framed, and is left out: no lens sees it.

	The overhead: the wind-up, the chop and the recovery. The parry: the wind-up, the clash (the
	player's Guard, then its Parry), the spark and the kobold's Stagger.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")

local F = 1 / 60
local ASPECT = 16 / 9
local SETTLE_FRAMES = 180
-- What the view must keep in sight on every frame of the take.
local KOBOLD_SEEN = 0.95
local AXE_SEEN = 0.8

-- tools/ modules are plain Lune scripts: load one with only Lune's own libraries to require.
local function loadTool(path: string): any
	local source = fs.readFile(Harness.repoRoot() .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end
local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")

local function clip(id: string): any
	return Harness.load("src/shared/clips/" .. id)
end

local function shotOf(id: string): any
	for _, shot in Dev.capture.shots do
		if shot.id == id then
			return shot
		end
	end
	error("no shot " .. id)
end

type Fixture = { controller: any, camera: any, frames: (count: number) -> () }

-- CameraController around the player's character, with a fake render loop and clock.
local function loadCamera(subject: Model): Fixture
	local state = { clock = 50, steps = {} :: { { priority: number, fn: (dt: number) -> () } } }
	local signal = { Connect = function() end }
	local camera = { CFrame = CFrame.new(0, 10, 20), FieldOfView = 70, CameraType = nil, Focus = CFrame.new() }
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, _name: string, priority: number, fn: (dt: number) -> ())
				table.insert(state.steps, { priority = priority, fn = fn })
				table.sort(state.steps, function(a, b)
					return a.priority < b.priority
				end)
			end,
		},
		UserInputService = {
			MouseEnabled = true,
			TouchEnabled = false,
			MouseBehavior = nil,
			InputChanged = signal,
			LastInputTypeChanged = signal,
		},
		Players = { LocalPlayer = { Character = subject, CharacterAdded = signal, CharacterRemoving = signal } },
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node("src/client/camera/CameraController")
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	env.workspace = {
		CurrentCamera = camera,
		Spherecast = function(): any
			return nil
		end,
	}
	env.RaycastParams = {
		new = function(): any
			return {}
		end,
	}
	env.os = {
		clock = function(): number
			return state.clock
		end,
	}
	local controller = luau.load(
		Harness.readFile("src/client/camera/CameraController.luau"),
		{ debugName = "CameraController", environment = env :: any }
	)()
	controller.start()
	return {
		controller = controller,
		camera = camera,
		frames = function(count: number)
			for _ = 1, count do
				state.clock += F
				for _, step in state.steps do
					step.fn(F)
				end
			end
		end,
	}
end

-- Places every part of a rig for a pose (Lune keeps a part's Position and CFrame apart: set both).
local chains: { [Model]: any } = {}
local partsOf: { [Model]: { [string]: BasePart } } = {}
local function pose(model: Model, base: CFrame, offsets: any)
	local chain = chains[model]
	local parts = partsOf[model]
	if chain == nil or parts == nil then
		chain = Pose.chain(model)
		chains[model] = chain
		parts = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				(parts :: any)[part.Name] = part
			end
		end
		partsOf[model] = parts
	end
	for name, frame in Pose.solve(model, base, offsets, chain) do
		local part = (parts :: any)[name]
		if part ~= nil then
			part.CFrame = frame
			part.Position = frame.Position
		end
	end
end

-- The parts a viewer sees: no root, no blocker, nothing see-through.
local function seenParts(model: Model): { BasePart }
	local list = {}
	for _, part in model:GetDescendants() do
		if
			part:IsA("BasePart")
			and part.Name ~= "HumanoidRootPart"
			and part.Name ~= RigBuilder.BLOCKER_NAME
			and part.Transparency < 1
		then
			table.insert(list, part)
		end
	end
	return list
end

-- Where a world point lands on screen: x and y in [-1, 1] inside the frame, and its depth.
local function project(camera: any, point: Vector3): (number, number, number)
	local l = (camera.CFrame :: CFrame):PointToObjectSpace(point)
	local depth = -l.Z
	local half = math.tan(math.rad(camera.FieldOfView) / 2)
	return l.X / (depth * half * ASPECT), l.Y / (depth * half), depth
end

local function inside(point: Vector3, part: BasePart): boolean
	local l = part.CFrame:PointToObjectSpace(point)
	local h = part.Size / 2
	return math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z
end

-- Whether the segment from `origin` to `point` enters the part's box before reaching the point.
local function blocks(origin: Vector3, point: Vector3, part: BasePart): boolean
	local o = part.CFrame:PointToObjectSpace(origin)
	local d = part.CFrame:PointToObjectSpace(point) - o
	local h = part.Size / 2
	local enter, leave = 0, 1
	for _, axis in { { o.X, d.X, h.X }, { o.Y, d.Y, h.Y }, { o.Z, d.Z, h.Z } } do
		local from, along, half = axis[1], axis[2], axis[3]
		if math.abs(along) < 1e-9 then
			if math.abs(from) > half then
				return false
			end
		else
			local a, b = (-half - from) / along, (half - from) / along
			enter = math.max(enter, math.min(a, b))
			leave = math.min(leave, math.max(a, b))
			if enter > leave then
				return false
			end
		end
	end
	return enter < 1 - 1e-4
end

-- Points through a part's box at these fractions of its half size along each axis.
local function samples(part: BasePart, steps: { number }): { Vector3 }
	local list = {}
	local h = part.Size / 2
	for _, x in steps do
		for _, y in steps do
			for _, z in steps do
				table.insert(list, part.CFrame:PointToWorldSpace(Vector3.new(h.X * x, h.Y * y, h.Z * z)))
			end
		end
	end
	return list
end
-- 27 points: the centre, faces, edges and corners pulled 20% in.
local INNER = { -0.8, 0, 0.8 }
-- The 8 corners.
local CORNERS = { -1, 1 }

type Frame = { enemy: any, enemyTime: number, player: any?, playerTime: number }
type Measure = {
	seen: number, -- the least share of the kobold's points seen on any frame
	seenAt: number,
	axe: number, -- the least share of the axe's points seen
	axeAt: number,
	koboldInFrame: boolean,
	playerInFrame: boolean,
	koboldBox: { number }, -- x0, x1, y0, y1 over the take
	playerBox: { number },
}

local function grow(box: { number }, x: number, y: number)
	box[1], box[2] = math.min(box[1], x), math.max(box[2], x)
	box[3], box[4] = math.min(box[3], y), math.max(box[4], y)
end

-- One take of a shot through its staged view: `timeline(t)` gives both clips and their times.
local function measure(shotId: string, seconds: number, timeline: (t: number) -> Frame): Measure
	local shot = shotOf(shotId)
	local entry = shot.stage.enemies[1]
	local def = Enemies.byId(entry.enemy)
	local avatar = HitMatrix.standing(Harness)
	local player: Model = avatar.model
	local playerBase: CFrame = avatar.base
	avatar.root.Position = playerBase.Position
	pose(player, playerBase, {})
	-- The kobold at the shot's placement (straight ahead along the player's look, -Z), facing it.
	local enemy = RigBuilder.build(def.skin)
	local height = PlaygroundLayout.rootHeight(
		Rigs[def.skin].hipHeight,
		(enemy.PrimaryPart :: BasePart).Size.Y,
		World.spawn.groundEpsilon
	)
	local side = math.rad(entry.side)
	local enemyBase = CFrame.new(
		playerBase.Position.X - math.sin(side) * entry.distance,
		height,
		playerBase.Position.Z - math.cos(side) * entry.distance
	) * CFrame.Angles(0, math.pi + side, 0)
	pose(enemy, enemyBase, {})
	enemy.Parent = Instance.new("Folder")
	local fixture = loadCamera(player)
	fixture.controller.setStage(Dev.capture.cameras[shot.camera], enemy, shot.cameraSide)
	fixture.frames(SETTLE_FRAMES)
	local koboldParts, playerParts = seenParts(enemy), seenParts(player)
	local result: Measure = {
		seen = 1,
		seenAt = 0,
		axe = 1,
		axeAt = 0,
		koboldInFrame = true,
		playerInFrame = true,
		koboldBox = { math.huge, -math.huge, math.huge, -math.huge },
		playerBox = { math.huge, -math.huge, math.huge, -math.huge },
	}
	local t = 0
	while t <= seconds do
		local frame = timeline(t)
		pose(enemy, enemyBase, ClipSampler.sample(frame.enemy, frame.enemyTime))
		pose(player, playerBase, if frame.player ~= nil then ClipSampler.sample(frame.player, frame.playerTime) else {})
		fixture.frames(1)
		local eye = (fixture.camera.CFrame :: CFrame).Position
		local total, seen, axeTotal, axeSeen = 0, 0, 0, 0
		for _, part in koboldParts do
			for _, point in samples(part, INNER) do
				local x, y, depth = project(fixture.camera, point)
				grow(result.koboldBox, x, y)
				if depth <= 0 or math.abs(x) > 1 or math.abs(y) > 1 then
					result.koboldInFrame = false
				end
				local touching = false
				for _, other in playerParts do
					touching = touching or inside(point, other)
				end
				if touching then
					continue
				end
				local blocked = false
				for _, other in playerParts do
					if blocks(eye, point, other) then
						blocked = true
						break
					end
				end
				total += 1
				seen += if blocked then 0 else 1
				if part.Name == "Weapon" then
					axeTotal += 1
					axeSeen += if blocked then 0 else 1
				end
			end
		end
		for _, part in playerParts do
			for _, point in samples(part, CORNERS) do
				local x, y, depth = project(fixture.camera, point)
				grow(result.playerBox, x, y)
				if depth <= 0 or math.abs(x) > 1 or math.abs(y) > 1 then
					result.playerInFrame = false
				end
			end
		end
		if seen / total < result.seen then
			result.seen, result.seenAt = seen / total, t
		end
		if axeTotal > 0 and axeSeen / axeTotal < result.axe then
			result.axe, result.axeAt = axeSeen / axeTotal, t
		end
		t += F
	end
	print(
		("  %s (%s, %g degrees, %g studs, side %d): kobold seen >= %.1f%% (t=%.2f), axe >= %.1f%% (t=%.2f); kobold box x[%.2f, %.2f] y[%.2f, %.2f], player box x[%.2f, %.2f] y[%.2f, %.2f]"):format(
			shotId,
			shot.camera,
			Dev.capture.cameras[shot.camera].degrees,
			Dev.capture.cameras[shot.camera].distance,
			shot.cameraSide,
			result.seen * 100,
			result.seenAt,
			result.axe * 100,
			result.axeAt,
			result.koboldBox[1],
			result.koboldBox[2],
			result.koboldBox[3],
			result.koboldBox[4],
			result.playerBox[1],
			result.playerBox[2],
			result.playerBox[3],
			result.playerBox[4]
		)
	)
	return result
end

local OVERHEAD = clip("enemy/Kobold/Overhead")
local STAGGER = clip("enemy/Kobold/Stagger")
local IDLE = clip("player/OneHandedSword/Idle")
local IDLE_DRAWN = clip("player/OneHandedSword/IdleDrawn")
local GUARD = clip("player/OneHandedSword/Guard")
local PARRY = clip("player/OneHandedSword/Parry")

-- The overhead's clash: its hit window opens with the chop.
local function clashOf(attack: any): number
	return ClipSampler.hitWindows(attack)[1].open
end

describe("The ThreeQuarter staged view: the kobold whole, its axe in sight (CS6)", function()
	it("the overhead: the wind-up, the chop and the recovery, never behind the player", function()
		local result = measure("enemy-kobold-overhead", OVERHEAD.duration, function(t: number): Frame
			return { enemy = OVERHEAD, enemyTime = t, player = IDLE, playerTime = t % IDLE.duration }
		end)
		expect(result.koboldInFrame).toBe(true)
		expect(result.playerInFrame).toBe(true)
		expect(result.seen >= KOBOLD_SEEN).toBe(true)
		expect(result.axe >= AXE_SEEN).toBe(true)
	end)

	it("the parry: the wind-up, the clash, the spark and the stagger, never behind the player", function()
		local shot = shotOf("parry-spark")
		local lead = shot.perform[1].lead
		local clash = clashOf(OVERHEAD)
		local result = measure("parry-spark", clash + STAGGER.duration, function(t: number): Frame
			if t < clash then
				if t >= clash - lead then
					return { enemy = OVERHEAD, enemyTime = t, player = GUARD, playerTime = t - (clash - lead) }
				end
				return { enemy = OVERHEAD, enemyTime = t, player = IDLE_DRAWN, playerTime = t % IDLE_DRAWN.duration }
			end
			return {
				enemy = STAGGER,
				enemyTime = t - clash,
				player = PARRY,
				playerTime = math.min(t - clash, PARRY.duration),
			}
		end)
		expect(result.koboldInFrame).toBe(true)
		expect(result.playerInFrame).toBe(true)
		expect(result.seen >= KOBOLD_SEEN).toBe(true)
		expect(result.axe >= AXE_SEEN).toBe(true)
	end)
end)
