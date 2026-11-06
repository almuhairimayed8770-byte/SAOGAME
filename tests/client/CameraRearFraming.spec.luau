--!strict
--[[
	The Rear staged view (enemy-boar-charge-rear): the boar's charge staged as enemy-boar-charge
	stages it, seen from behind the boar, so its wind-up reads from behind as well as the front
	(GAME_SPEC section 10 "Enemy animation rules": wind-up poses are held and readable from behind as
	well as the front; the phase gate: a colored telegraph that reads from behind). The Behind view
	(tests/client/CameraBehindFraming.spec.luau) frames the whole charge from high on the boar's right
	flank, 75 degrees off the line behind it: no still view within 30 degrees of that line keeps the
	skid and the turn clear of the player's body (at 10 to 30 degrees the boar is down to 23 to 91
	percent seen in the turn), so the read from behind is its own take.

	Through the crouch the lens stands within REAR_FLAT degrees of the line behind the boar (flat)
	and within REAR_UP degrees of it counting the height; from the go until the drawn snout meets the
	player the boar is whole in frame and nothing of the player hides it, the camera holds still, and
	at least LINE_SEEN of the red ground line's centre (two studs ahead of the root to the attack's
	reach) shows past the boar's body on every crouch frame.

	Bodies, clips, the rush and the camera are posed and run as CameraBehindFraming.spec poses them.
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
local REAR_ID = "enemy-boar-charge-rear"
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
-- How near a fixed view staged over another holds to the spot and look a fresh staging takes.
-- The read from behind.
local REAR_FLAT = 20 -- degrees off the line behind the crouching boar, flat
local REAR_UP = 35 -- degrees off that line counting the lens's height
local LINE_SEEN = 0.2 -- the least share of the red line's centre seen past the boar's body

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
-- The red line's centre: points from LINE_FROM studs ahead of the boar's root to the attack's
-- reach, just over the ground (fx.luau telegraph.decal.groundOffset).
local LINE_POINTS = 20
local LINE_FROM = 2
local LINE_HEIGHT = 0.06

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
	rearFlat: number, -- the most the lens stood off the line behind the crouch (degrees, flat)
	rearUp: number, -- the same counting its height
	seenBefore: number, -- the least share of the boar seen from the go until the meet
	edgeBefore: number, -- the furthest a boar point came from the frame's centre until the meet
	lineSeen: number, -- the least share of the red line's centre seen on a crouch frame
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

-- One take of the boar's charge through shot `shotId`'s staged view; the turn after it goes `turn`
-- (1 counter-clockwise from above, -1 clockwise).
local function measure(shotId: string, turn: number): Measure
	local shot = shotOf(shotId)
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
		rearFlat = 0,
		rearUp = 0,
		seenBefore = 1,
		edgeBefore = 0,
		lineSeen = 1,
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
		-- The chord between the two looks, not the arc-cosine of their dot: a dot read in single
		-- precision floors that at about 0.02 degrees, over MOST_TURN, for a look that never moved.
		local turned = math.deg(2 * math.asin(math.clamp((view.LookVector - last.LookVector).Magnitude / 2, 0, 1)))
		result.turn = math.max(result.turn, turned)
		last = view
		result.head = math.min(result.head, (eye - head.Position).Magnitude)
		if t >= CROUCH_AT and t < CROUCH_AT + CHARGE.windUp then
			local toLens = eye - drawn.Position
			local flat = Vector3.new(toLens.X, 0, toLens.Z).Unit
			result.rearFlat = math.max(result.rearFlat, math.deg(math.acos(math.clamp(flat:Dot(-direction), -1, 1))))
			result.rearUp = math.max(result.rearUp, math.deg(math.acos(math.clamp(toLens.Unit:Dot(-direction), -1, 1))))
			local lineTotal, lineSeen = 0, 0
			for i = 0, LINE_POINTS do
				local ground = Vector3.new(origin.X, LINE_HEIGHT, origin.Z)
				local point = ground + direction * (LINE_FROM + (CHARGE.reach - LINE_FROM) * i / LINE_POINTS)
				local x, y, depth = project(fixture.camera, point)
				local open = depth > 0 and math.abs(x) <= 1 and math.abs(y) <= 1
				for _, list in { boarParts, playerParts } do
					for _, other in list do
						if open and blocks(eye, point, other) then
							open = false
						end
					end
				end
				lineTotal += 1
				lineSeen += if open then 1 else 0
			end
			result.lineSeen = math.min(result.lineSeen, lineSeen / lineTotal)
		end
		local total, seen = 0, 0
		local past = met ~= nil and along - back < bodyAlong + bodies[1].radius
		local after = met ~= nil and t > met
		for _, part in boarParts do
			for _, point in samples(part, INNER) do
				local x, y, depth = project(fixture.camera, point)
				local edge = if depth <= 0 then math.huge else math.max(math.abs(x), math.abs(y))
				if result.met == nil then
					result.edgeBefore = math.max(result.edgeBefore, edge)
				end
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
		if total > 0 and result.met == nil then
			result.seenBefore = math.min(result.seenBefore, seen / total)
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
		("  %s (%s, %g degrees, %g studs, %g up): crouch %.1f degrees off the line behind it (%.1f with the height), boar seen >= %.1f%% and edge %.2f until the meet (t=%s), red line seen >= %.1f%%, camera moved <= %.4f studs/frame"):format(
			shotId,
			shot.camera,
			view.degrees,
			view.distance,
			view.height,
			result.rearFlat,
			result.rearUp,
			result.seenBefore * 100,
			result.edgeBefore,
			if result.met ~= nil then ("%.3f"):format(result.met :: number) else "never",
			result.lineSeen * 100,
			result.move
		)
	)
	return result
end

describe("The Rear staged view: the boar's wind-up read from behind it", function()
	it("is the charge shot staged again, with its own still view", function()
		local rear = shotOf(REAR_ID)
		local charge = shotOf(SHOT_ID)
		expect(rear.camera).toBe("Rear")
		expect(Dev.capture.cameras.Rear.fixed).toBe(true)
		expect(rear.stage).toEqual(charge.stage)
	end)

	it("stands behind the crouch, the boar whole, unhidden and still until it meets the player", function()
		local result = measure(REAR_ID, 1)
		expect(result.met ~= nil).toBe(true)
		expect(result.rearFlat <= REAR_FLAT + 1e-6).toBe(true)
		expect(result.rearUp <= REAR_UP).toBe(true)
		expect(result.seenBefore).toBe(1)
		expect(result.edgeBefore <= EDGE).toBe(true)
		expect(result.lineSeen >= LINE_SEEN).toBe(true)
		expect(result.move <= MOST_MOVE).toBe(true)
		expect(result.turn <= MOST_TURN).toBe(true)
	end)

	it("the Behind take stays the whole charge from the flank: it is no read from behind", function()
		local result = measure(SHOT_ID, 1)
		expect(result.rearFlat > REAR_FLAT).toBe(true)
	end)
end)
