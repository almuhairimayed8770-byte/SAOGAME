--!strict
--[[
	The Behind staged view frames the boar's whole charge (enemy-boar-charge, FB4): the crouch, the
	launch, the contact, the skid and the turn, the boar whole in frame on every frame, never behind
	the player's body, and the camera standing still while it plays.

	Both bodies are posed frame by frame at 60 Hz as tests/client/CameraStageFraming.spec.luau poses
	them: the player is the hit matrix's avatar with its sword (HitMatrix.standing), the boar the
	RigBuilder rig, at the shot's own placement; each clip is sampled with ClipSampler and solved with
	Pose. The camera is CameraController's, set to the shot's view and side the way the capture panel
	sets it (CameraController.setStage), then run through the capture's countdown before the take.

	The boar's body is drawn where the client draws it (choreo/RushDraw, D-171): the crouch on its
	root, from the launch on the server's timeline, shouldering past the player's body (the pass,
	D-167), the skid to its rest, then the hand-back onto its root (the server's body, replicated
	`LAG` late). After the Charge clip it turns round toward the player in place, either way, at the
	chase's turn rate. The player's root stands; the blow plays the Stagger from the frame the
	drawn snout meets the body.

	A sample point of a boar part is seen when the ray from the lens reaches it before any part of
	the player's body or sword. A point inside a player part (the snout touching the body at the
	contact) is touching, not framed, and is left out: no lens sees it. While the drawn body
	shoulders past (from the frame its snout meets the body until its rump clears the body's far
	edge) it is at the player's guard and under the Stagger's flung arms: the snout under the guard
	forearm it meets, the flung hand over its flank. A sliver may be hidden then (`PAST_SEEN`),
	never at any other frame. No point of the boar is ever inside the player's torso, head or legs
	after the meet frame (FB1: it never runs through the body it hit); its flank may brush the
	flung arms (counted and printed, `brushed`).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local RushDraw = Harness.load("src/client/choreo/RushDraw")
local RushWorld = Harness.load("src/shared/choreo/RushWorld")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local AI = Harness.load("src/shared/data/ai")

local F = 1 / 60
local ASPECT = 16 / 9
local SHOT_ID = "enemy-boar-charge"
-- The capture's countdown runs between the staging (setStage) and the take.
local COUNTDOWN_FRAMES = math.ceil(Dev.capture.countdownSeconds / F)
-- The crouch starts this long after the take's "go" (the server's next AI tick and its telegraph:
-- 0.317 to 0.333 s in the take's own numbers).
local CROUCH_AT = 1 / 3
-- How late the replicated root plays the server's body (RushDraw: 0.2 to 0.3 s).
local LAG = 0.25
-- What the view must hold on every frame of the take.
local EDGE = 0.95 -- the boar's every point inside this much of the frame's half width and height
local MOST_MOVE = 1e-3 -- studs the camera may move in a frame
local MOST_TURN = 1e-2 -- degrees its look may turn in a frame
local LEAST_HEAD = 8 -- studs from the lens to the player's head
local PAST_SEEN = 0.9 -- the least share of the boar seen while it shoulders past the body
-- How near a fixed view staged over another holds to the spot and look a fresh staging takes.
local HELD_STUDS = 0.1
local HELD_DEGREES = 0.5

local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]
local SPEED: number = AI.rushSpeed(CHARGE)
local LENGTH: number = CHARGE.reach + AI.archetypes.Charger.overshoot
local TURN_RATE: number = AI.archetypes.Charger.turnRate

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

-- Lune keeps a part's Position and CFrame apart: set both.
local function place(part: BasePart, frame: CFrame)
	part.CFrame = frame
	part.Position = frame.Position
end

-- Places every part of a rig for a pose.
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
			place(part, frame)
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

-- The player's body proper (torso, head, legs), not the arms the Stagger flings or the sword.
local function isBody(part: BasePart): boolean
	local name = part.Name
	return name:find("Torso") ~= nil or name == "Head" or name:find("Leg") ~= nil or name:find("Foot") ~= nil
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

type Measure = {
	seen: number, -- the least share of the boar's points seen on any frame but while it shoulders past
	seenAt: number,
	seenPast: number, -- the least share seen while it shoulders past (the meet until its rump clears)
	seenPastAt: number,
	through: number, -- boar points inside the player's torso, head or legs after the meet frame (summed)
	throughAt: number,
	brushed: number, -- boar points inside the player's arms or sword after the meet frame (summed)
	edge: number, -- the furthest any boar point came from the frame's centre (1: its edge)
	edgeAt: number,
	playerInFrame: boolean,
	move: number, -- the most the camera moved in a frame of the take (studs)
	moveAt: number,
	turn: number, -- the most its look turned in a frame (degrees)
	head: number, -- the least distance from the lens to the player's head
	met: number?, -- seconds into the take the drawn snout met the body
	rest: number, -- how far down the line the drawn body came to rest
	passed: number, -- the furthest the drawn body swung off the line (studs, to the boar's right)
}

local CHARGE_CLIP = clip("enemy/Boar/Charge")
local BOAR_IDLE = clip("enemy/Boar/Idle")
local IDLE = clip("player/OneHandedSword/Idle")
local STAGGER = clip("player/OneHandedSword/Stagger")

type Stand = { player: Model, playerBase: CFrame, enemy: Model, start: CFrame, origin: Vector3 }

-- The player and the boar standing where the shot stages them: the boar straight ahead along the
-- player's look (-Z), facing it.
local function stand(entry: any): Stand
	local avatar = HitMatrix.standing(Harness)
	local player: Model = avatar.model
	local playerBase: CFrame = avatar.base
	local playerRoot = player.PrimaryPart :: BasePart
	place(playerRoot, playerBase)
	pose(player, playerBase, {})
	local enemy = RigBuilder.build(BOAR.skin)
	local enemyRoot = enemy.PrimaryPart :: BasePart
	local height = PlaygroundLayout.rootHeight(Rigs[BOAR.skin].hipHeight, enemyRoot.Size.Y, World.spawn.groundEpsilon)
	local side = math.rad(entry.side)
	local origin = Vector3.new(
		playerBase.Position.X - math.sin(side) * entry.distance,
		height,
		playerBase.Position.Z - math.cos(side) * entry.distance
	)
	local start = CFrame.new(origin) * CFrame.Angles(0, math.pi + side, 0)
	place(enemyRoot, start)
	pose(enemy, start, {})
	enemy.Parent = Instance.new("Folder")
	return { player = player, playerBase = playerBase, enemy = enemy, start = start, origin = origin }
end

-- One take of the boar's charge through the shot's staged view; the turn after it goes `turn`
-- (1 counter-clockwise from above, -1 clockwise).
local function measure(turn: number): Measure
	local shot = shotOf(SHOT_ID)
	local entry = shot.stage.enemies[1]
	local staged = stand(entry)
	local player, playerBase, enemy = staged.player, staged.playerBase, staged.enemy
	local start, origin = staged.start, staged.origin
	local playerRoot = player.PrimaryPart :: BasePart
	local enemyRoot = enemy.PrimaryPart :: BasePart
	local head = player:FindFirstChild("Head", true) :: BasePart
	local direction = start.LookVector
	local right = start.RightVector

	-- The rush as the client draws it.
	local line = RushDraw.predict(CHARGE, CROUCH_AT, origin, direction)
	local state = RushDraw.new(line)
	local profile = RushWorld.profileOf(enemy)
	RushDraw.setBody(state, { profile = profile, size = enemyRoot.Size }, nil)
	local bodies = { { spot = playerRoot.Position, radius = math.max(playerRoot.Size.X, playerRoot.Size.Z) / 2 } }
	-- The snout meets the body's near edge (D-166) this far down the line.
	local contact = entry.distance - bodies[1].radius - RushWorld.front(profile)
	-- Its rump clears the body's far edge once the drawn root is this far past the body.
	local back = RushWorld.support(profile, direction, -direction)
	local bodyAlong = (playerRoot.Position - origin):Dot(direction)
	local function serverBody(t: number): CFrame
		local d = math.clamp(SPEED * (t - line.startedAt), 0, LENGTH)
		return CFrame.lookAt(origin + direction * d, origin + direction * (d + 1))
	end

	local fixture = loadCamera(player)
	fixture.controller.setStage(Dev.capture.cameras[shot.camera], enemy, shot.cameraSide)
	-- The countdown: both stand where the staging put them, the boar idling.
	for frame = 1, COUNTDOWN_FRAMES do
		pose(enemy, start, ClipSampler.sample(BOAR_IDLE, (frame * F) % BOAR_IDLE.duration))
		place(enemyRoot, start)
		fixture.frames(1)
	end
	local boarParts, playerParts = seenParts(enemy), seenParts(player)
	local result: Measure = {
		seen = 1,
		seenAt = 0,
		seenPast = 1,
		seenPastAt = 0,
		through = 0,
		throughAt = 0,
		brushed = 0,
		edge = 0,
		edgeAt = 0,
		playerInFrame = true,
		move = 0,
		moveAt = 0,
		turn = 0,
		head = math.huge,
		met = nil,
		rest = 0,
		passed = 0,
	}
	local clipEnds = CROUCH_AT + CHARGE_CLIP.duration
	local yaw = 0
	local last: CFrame = fixture.camera.CFrame
	local t = 0
	while t <= shot.seconds + 1e-9 do
		-- The boar: the late root, and the body drawn where RushDraw puts it.
		local root = serverBody(t - LAG)
		if t >= clipEnds then
			-- The turn round toward the player, in place, after the charge.
			yaw = math.min(yaw + math.rad(TURN_RATE) * F, math.pi)
			root = CFrame.new(serverBody(t).Position) * root.Rotation * CFrame.Angles(0, turn * yaw, 0)
		end
		place(enemyRoot, root)
		local drawn = RushDraw.step(state, t, F, root, nil, nil, nil, bodies) or root
		local along = (drawn.Position - origin):Dot(direction)
		result.passed = math.max(result.passed, (drawn.Position - origin):Dot(right))
		result.rest = along
		local offsets = if t < CROUCH_AT
			then ClipSampler.sample(BOAR_IDLE, t % BOAR_IDLE.duration)
			elseif t < clipEnds then ClipSampler.sample(CHARGE_CLIP, t - CROUCH_AT)
			else ClipSampler.sample(BOAR_IDLE, (t - clipEnds) % BOAR_IDLE.duration)
		pose(enemy, drawn, offsets)
		place(enemyRoot, root)
		-- The player: the blow plays the Stagger from the frame the drawn snout meets the body.
		if result.met == nil and t >= line.startedAt and along >= contact then
			result.met = t
		end
		local met = result.met
		pose(
			player,
			playerBase,
			if met ~= nil and t - met < STAGGER.duration
				then ClipSampler.sample(STAGGER, t - met)
				else ClipSampler.sample(IDLE, t % IDLE.duration)
		)
		place(playerRoot, playerBase)
		fixture.frames(1)

		local view: CFrame = fixture.camera.CFrame
		local eye = view.Position
		local moved = (eye - last.Position).Magnitude
		if moved > result.move then
			result.move, result.moveAt = moved, t
		end
		local turned = math.deg(math.acos(math.clamp(view.LookVector:Dot(last.LookVector), -1, 1)))
		result.turn = math.max(result.turn, turned)
		last = view
		result.head = math.min(result.head, (eye - head.Position).Magnitude)
		local total, seen = 0, 0
		local past = met ~= nil and along - back < bodyAlong + bodies[1].radius
		local after = met ~= nil and t > met
		for _, part in boarParts do
			for _, point in samples(part, INNER) do
				local x, y, depth = project(fixture.camera, point)
				local edge = if depth <= 0 then math.huge else math.max(math.abs(x), math.abs(y))
				if edge > result.edge then
					result.edge, result.edgeAt = edge, t
				end
				local touching: BasePart? = nil
				for _, other in playerParts do
					if inside(point, other) then
						touching = other
					end
				end
				if touching ~= nil then
					if after and isBody(touching) then
						result.through += 1
						result.throughAt = t
					elseif after then
						result.brushed += 1
					end
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
			end
		end
		if total > 0 and past then
			if seen / total < result.seenPast then
				result.seenPast, result.seenPastAt = seen / total, t
			end
		elseif total > 0 and seen / total < result.seen then
			result.seen, result.seenAt = seen / total, t
		end
		for _, part in playerParts do
			for _, point in samples(part, CORNERS) do
				local x, y, depth = project(fixture.camera, point)
				if depth <= 0 or math.abs(x) > 1 or math.abs(y) > 1 then
					result.playerInFrame = false
				end
			end
		end
		t += F
	end
	local view = Dev.capture.cameras[shot.camera]
	print(
		("  %s (%s, %s %g degrees, %g studs, %g up, side %d, turn %d): boar seen >= %.1f%% (t=%.2f), >= %.1f%% shouldering past (t=%.2f), %d boar points inside the player's body after the meet (t=%.2f), %d brushing its arms or sword, boar edge %.2f (t=%.2f), camera moved <= %.4f studs/frame (t=%.2f), turned <= %.3f deg/frame, head >= %.2f studs; met at t=%s, rest %.2f, passed %.2f off the line"):format(
			SHOT_ID,
			shot.camera,
			tostring(view.reference),
			view.degrees,
			view.distance,
			view.height,
			shot.cameraSide,
			turn,
			result.seen * 100,
			result.seenAt,
			result.seenPast * 100,
			result.seenPastAt,
			result.through,
			result.throughAt,
			result.brushed,
			result.edge,
			result.edgeAt,
			result.move,
			result.moveAt,
			result.turn,
			result.head,
			if result.met ~= nil then ("%.3f"):format(result.met :: number) else "never",
			result.rest,
			result.passed
		)
	)
	return result
end

describe("The Behind staged view: the boar's whole charge in one still frame (FB4)", function()
	for _, turn in { 1, -1 } do
		it(
			("the crouch, the launch, the contact, the skid and the turn (%s), never behind the player"):format(
				if turn > 0 then "counter-clockwise" else "clockwise"
			),
			function()
				local result = measure(turn)
				-- The take is the charge: it meets the body and runs on to its rest past it.
				expect(result.met ~= nil).toBe(true)
				expect(result.rest > CHARGE.reach).toBe(true)
				-- Still while it plays.
				expect(result.move <= MOST_MOVE).toBe(true)
				expect(result.turn <= MOST_TURN).toBe(true)
				-- The boar whole in frame, and never behind the player's body or sword but for a sliver
				-- of its far flank as it shoulders past.
				expect(result.edge <= EDGE).toBe(true)
				expect(result.seen).toBe(1)
				expect(result.seenPast >= PAST_SEEN).toBe(true)
				-- Past the body it hit, never through it (FB1).
				expect(result.through).toBe(0)
				-- The player in frame, and the lens never at its head.
				expect(result.playerInFrame).toBe(true)
				expect(result.head >= LEAST_HEAD).toBe(true)
			end
		)
	end
end)

describe("A fixed staged view holds where its own pan comes to (FB4)", function()
	it("staged straight over a live view on the far flank, it holds the spot a fresh staging takes", function()
		local shot = shotOf(SHOT_ID)
		local staged = stand(shot.stage.enemies[1])
		local view = Dev.capture.cameras[shot.camera]
		-- A fresh staging: the bearing starts on its spot.
		local fresh = loadCamera(staged.player)
		fresh.controller.setStage(view, staged.enemy, shot.cameraSide)
		fresh.frames(COUNTDOWN_FRAMES)
		-- Staged while the far flank's view is live: the bearing pans round to it, at the lock's cap.
		local over = loadCamera(staged.player)
		over.controller.setStage(view, staged.enemy, -shot.cameraSide)
		over.frames(COUNTDOWN_FRAMES)
		over.controller.setStage(view, staged.enemy, shot.cameraSide)
		over.frames(COUNTDOWN_FRAMES)
		local apart = (over.camera.CFrame.Position - fresh.camera.CFrame.Position).Magnitude
		local turned =
			math.deg(math.acos(math.clamp(over.camera.CFrame.LookVector:Dot(fresh.camera.CFrame.LookVector), -1, 1)))
		print(("  staged over the far flank: %.3f studs and %.3f degrees from a fresh staging"):format(apart, turned))
		expect(apart <= HELD_STUDS).toBe(true)
		expect(turned <= HELD_DEGREES).toBe(true)
	end)
end)
