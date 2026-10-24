--!strict
--[[
	CameraController's framing, loaded fresh with a fake engine around it: a fake RunService that
	hands the render step to the spec, a fake clock, a plain camera table, and a world of real
	Lune instances (the player's character, enemies, walls) under a fake Spherecast that honours
	the exclude filter and CanCollide the way the engine does (boxes grown by the probe radius).

	Pins issue 7: the free camera sits low over the right shoulder; a lock frames both fighters
	side by side; a back dodge never pulls the camera in or tilts it; a lock eases on and off;
	characters, accessories, the player's own weapon and see-through parts never pull the camera
	in, walls still do.
]]

local luau = require("@lune/luau")

local CameraData = Harness.load("src/shared/data/camera")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local DodgeBack = Harness.load("src/shared/clips/player/OneHandedSword/DodgeBack")
local DodgeLeft = Harness.load("src/shared/clips/player/OneHandedSword/DodgeLeft")
local DodgeRight = Harness.load("src/shared/clips/player/OneHandedSword/DodgeRight")

local PATH = "src/client/camera/CameraController"
local F = 1 / 60
local ROOT = Vector3.new(0, 3, 0)
local ASPECT = 16 / 9
-- A fighter's torso column around its root: half width, half depth, below and above the root.
local HALF_WIDTH, HALF_DEPTH, BELOW, ABOVE = 1, 0.5, 2.5, 3

type Fixture = {
	controller: any,
	camera: any,
	world: Instance,
	subject: Model,
	root: BasePart,
	frames: (count: number) -> (),
}

local function part(name: string, position: Vector3, size: Vector3, parent: Instance): BasePart
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.Position = position
	created.CanCollide = true
	created.Parent = parent
	return created
end

-- A character: a Model with a root part and a Humanoid.
local function character(name: string, position: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = part("HumanoidRootPart", position, Vector3.new(2, 2, 1), model)
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	model.Parent = parent
	return model
end

-- The entry distance of a ray (origin, direction) into an axis-aligned box, as a fraction of the
-- direction; nil on a miss or when the ray starts inside (the engine skips shapes the sphere
-- starts in).
local function entry(origin: Vector3, direction: Vector3, low: Vector3, high: Vector3): number?
	local near, far = 0, 1
	local inside = true
	for _, axis in { "X", "Y", "Z" } do
		local o, d = (origin :: any)[axis], (direction :: any)[axis]
		local lo, hi = (low :: any)[axis], (high :: any)[axis]
		if o < lo or o > hi then
			inside = false
		end
		if math.abs(d) < 1e-12 then
			if o < lo or o > hi then
				return nil
			end
		else
			local a, b = (lo - o) / d, (hi - o) / d
			if a > b then
				a, b = b, a
			end
			near = math.max(near, a)
			far = math.min(far, b)
			if near > far then
				return nil
			end
		end
	end
	return if inside then nil else near
end

local function filtered(candidate: Instance, list: { Instance }): boolean
	for _, excluded in list do
		if candidate == excluded or candidate:IsDescendantOf(excluded) then
			return true
		end
	end
	return false
end

type Step = { priority: number, fn: (dt: number) -> () }

local function load(): Fixture
	-- Every render step the controller binds, run in priority order each frame (the main step at
	-- camera.luau renderOrder.main and the late pass at renderOrder.late, D-180, D-211).
	local state = { clock = 50, steps = {} :: { Step } }
	local signal = {
		Connect = function() end,
	}
	local world = Instance.new("Folder")
	world.Name = "Workspace"
	local subject = character("Hero", ROOT, world)
	local root = subject.PrimaryPart :: BasePart
	local camera = {
		CFrame = CFrame.new(0, 10, 20),
		FieldOfView = 70,
		CameraType = nil,
		Focus = CFrame.new(),
	}
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, _name: string, priority: number, fn: (dt: number) -> ())
				table.insert(state.steps, { priority = priority, fn = fn })
				table.sort(state.steps, function(a: Step, b: Step): boolean
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
		Players = {
			LocalPlayer = { Character = subject, CharacterAdded = signal, CharacterRemoving = signal },
		},
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node(PATH)
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
		Spherecast = function(_self: any, origin: Vector3, radius: number, direction: Vector3, params: any): any
			local list = params.FilterDescendantsInstances or {}
			local best: number? = nil
			local hit: BasePart? = nil
			for _, candidate in world:GetDescendants() do
				if not candidate:IsA("BasePart") then
					continue
				end
				local box = candidate :: BasePart
				if (params.RespectCanCollide and not box.CanCollide) or filtered(box, list) then
					continue
				end
				local half = box.Size / 2 + Vector3.new(radius, radius, radius)
				local t = entry(origin, direction, box.Position - half, box.Position + half)
				if t ~= nil and (best == nil or t < best) then
					best, hit = t, box
				end
			end
			if best == nil then
				return nil
			end
			return { Instance = hit, Distance = best * direction.Magnitude, Position = origin + direction * best }
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
	local controller = luau.load(Harness.readFile(PATH .. ".luau"), { debugName = PATH, environment = env :: any })()
	controller.start()
	return {
		controller = controller,
		camera = camera,
		world = world,
		subject = subject,
		root = root,
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

-- Where a world point lands on screen: x and y in -1..1 across the view (positive right and up).
local function project(camera: any, point: Vector3): (number, number)
	local frame: CFrame = camera.CFrame
	local offset = point - frame.Position
	local depth = offset:Dot(frame.LookVector)
	local tangent = math.tan(math.rad(camera.FieldOfView / 2))
	return offset:Dot(frame.RightVector) / depth / tangent / ASPECT, offset:Dot(frame.UpVector) / depth / tangent
end

-- The screen box of a fighter's torso column around `rootAt`: min x, max x, min y, max y.
local function column(camera: any, rootAt: Vector3): (number, number, number, number)
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, dx in { -HALF_WIDTH, HALF_WIDTH } do
		for _, dz in { -HALF_DEPTH, HALF_DEPTH } do
			for _, dy in { -BELOW, ABOVE } do
				local x, y = project(camera, rootAt + Vector3.new(dx, dy, dz))
				minX, maxX = math.min(minX, x), math.max(maxX, x)
				minY, maxY = math.min(minY, y), math.max(maxY, y)
			end
		end
	end
	return minX, maxX, minY, maxY
end

-- Degrees the camera looks down below the horizon.
local function lookDown(camera: any): number
	return math.deg(math.asin(-(camera.CFrame :: CFrame).LookVector.Y))
end

local function angleBetween(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

describe("CameraController framing: the free camera", function()
	it("sits low over the right shoulder: a shallow look down, the player left of center", function()
		local fixture = load()
		fixture.frames(240)
		local camera = fixture.camera
		expect(camera.CFrame.Position.Y - ROOT.Y).toBeLessThanOrEqual(4.2)
		expect(lookDown(camera)).toBeGreaterThan(0)
		expect(lookDown(camera)).toBeLessThanOrEqual(10)
		local minX, maxX, minY, maxY = column(camera, ROOT)
		expect((minX + maxX) / 2).toBeLessThan(-0.05)
		expect(minX).toBeGreaterThan(-1)
		expect(minY).toBeGreaterThan(-1)
		expect(maxY).toBeLessThan(1)
	end)
end)

describe("CameraController framing: the lock-on two-shot", function()
	for _, separation in { 3, 4, 6, 8, 10, 14 } do
		it(("stands both fighters side by side and on screen %d studs apart"):format(separation), function()
			local fixture = load()
			fixture.frames(60)
			local targetAt = ROOT + Vector3.new(0, 0, -separation)
			fixture.controller.setLockTarget(character("Kobold", targetAt, fixture.world))
			fixture.frames(240)
			local camera = fixture.camera
			local pMinX, pMaxX, pMinY, pMaxY = column(camera, ROOT)
			local tMinX, tMaxX, tMinY, tMaxY = column(camera, targetAt)
			-- Apart on screen: the target is never behind the player.
			expect(pMaxX < tMinX or tMaxX < pMinX).toBe(true)
			for _, edge in { pMinX, pMaxX, pMinY, pMaxY, tMinX, tMaxX, tMinY, tMaxY } do
				expect(math.abs(edge)).toBeLessThan(1)
			end
			-- Low: the camera sits a little over the fighters' heads, looking gently down.
			expect(camera.CFrame.Position.Y - ROOT.Y).toBeLessThanOrEqual(4.5)
			expect(lookDown(camera)).toBeLessThanOrEqual(15)
			-- The view sits between the fighters.
			local pCenter, tCenter = (pMinX + pMaxX) / 2, (tMinX + tMaxX) / 2
			expect(math.min(pCenter, tCenter)).toBeLessThan(0)
			expect(math.max(pCenter, tCenter)).toBeGreaterThan(0)
		end)
	end

	it("keeps the camera's flat distance from the player inside the lock distances", function()
		local fixture = load()
		fixture.frames(60)
		fixture.controller.setLockTarget(character("Kobold", ROOT + Vector3.new(0, 0, -6), fixture.world))
		fixture.frames(240)
		local away = flat(fixture.camera.CFrame.Position - ROOT).Magnitude
		expect(away).toBeGreaterThanOrEqual(CameraData.lock.minDistance - 1e-3)
		expect(away).toBeLessThanOrEqual(CameraData.lock.maxDistance + 1e-3)
	end)
end)

-- Plays DodgeBack's root motion on the subject at 60 fps from a settled camera and reports the
-- worst frame: the subject's depth in view against the settled depth, and the largest change of
-- look-down between two frames.
local function dodge(fixture: Fixture): (number, number)
	local camera = fixture.camera
	local function depth(): number
		return (fixture.root.Position - camera.CFrame.Position):Dot(camera.CFrame.LookVector)
	end
	local settled = depth()
	local worstDepth, worstTilt = 1, 0
	local previous = lookDown(camera)
	local t = 0
	while t < DodgeBack.duration + 0.5 do
		t += F
		local motion = ClipSampler.rootMotionAt(DodgeBack, math.min(t, DodgeBack.duration))
		fixture.root.Position = ROOT + Vector3.new(motion[1], motion[2], motion[3])
		fixture.frames(1)
		worstDepth = math.min(worstDepth, depth() / settled)
		local now = lookDown(camera)
		worstTilt = math.max(worstTilt, math.abs(now - previous))
		previous = now
	end
	return worstDepth, worstTilt
end

describe("CameraController framing: dodges", function()
	it("rides a back dodge toward the camera without pulling in on the player or tilting", function()
		local fixture = load()
		fixture.frames(240)
		local worstDepth, worstTilt = dodge(fixture)
		expect(worstDepth).toBeGreaterThanOrEqual(0.92)
		expect(worstTilt).toBeLessThanOrEqual(0.5)
	end)

	it("rides a back dodge out of a lock the same way", function()
		local fixture = load()
		fixture.frames(60)
		fixture.controller.setLockTarget(character("Kobold", ROOT + Vector3.new(0, 0, -6), fixture.world))
		fixture.frames(240)
		local worstDepth, worstTilt = dodge(fixture)
		expect(worstDepth).toBeGreaterThanOrEqual(0.92)
		expect(worstTilt).toBeLessThanOrEqual(0.5)
	end)

	-- A sideways dodge from a settled camera (D-181): measured before the side leash, the free
	-- camera let the player's column slide 0.49 of the half width off its spot (its edge out to
	-- 0.89 on a dodge left) and a lock 0.36 to 0.41 (0.61); held to a stud either way across the
	-- view, about a tenth.
	for _, case in
		{
			{ name = "left", clip = DodgeLeft },
			{ name = "right", clip = DodgeRight },
		}
	do
		for _, locked in { false, true } do
			it(
				("rides a dodge %s %s without carrying the player toward the screen's edge"):format(
					case.name,
					if locked then "out of a lock" else "free"
				),
				function()
					local fixture = load()
					fixture.frames(60)
					if locked then
						fixture.controller.setLockTarget(
							character("Kobold", ROOT + Vector3.new(0, 0, -6), fixture.world)
						)
					end
					fixture.frames(240)
					local camera = fixture.camera
					local minX, maxX = column(camera, ROOT)
					local center, edge = (minX + maxX) / 2, math.max(math.abs(minX), math.abs(maxX))
					local shift, worstEdge, tilt = 0, edge, 0
					local previous = lookDown(camera)
					local clip = case.clip
					local t = 0
					while t < clip.duration + 0.6 do
						t += F
						local motion = ClipSampler.rootMotionAt(clip, math.min(t, clip.duration))
						local at = ROOT + Vector3.new(motion[1], motion[2], motion[3])
						fixture.root.Position = at
						fixture.frames(1)
						local x0, x1 = column(camera, at)
						shift = math.max(shift, math.abs((x0 + x1) / 2 - center))
						worstEdge = math.max(worstEdge, math.abs(x0), math.abs(x1))
						local now = lookDown(camera)
						tilt = math.max(tilt, math.abs(now - previous))
						previous = now
					end
					expect(shift).toBeLessThanOrEqual(0.15)
					expect(worstEdge).toBeLessThanOrEqual(edge + 0.15)
					expect(tilt).toBeLessThanOrEqual(0.5)
				end
			)
		end
	end
end)

-- Steps `count` frames and reports the largest frame-to-frame turn of the view (degrees) and
-- move of the player's root on screen, and the closest the camera came to the root (flat).
-- Eased, the player stays nearly put on screen while the camera swings around them (a lock
-- behind the camera is a half turn: a fast whip, never a cut).
local function watch(fixture: Fixture, count: number): (number, number, number)
	local camera = fixture.camera
	local turn, slide, closest = 0, 0, math.huge
	local look: Vector3 = camera.CFrame.LookVector
	local x, y = project(camera, ROOT)
	for _ = 1, count do
		fixture.frames(1)
		local nextLook: Vector3 = camera.CFrame.LookVector
		local nx, ny = project(camera, ROOT)
		turn = math.max(turn, angleBetween(look, nextLook))
		slide = math.max(slide, math.sqrt((nx - x) ^ 2 + (ny - y) ^ 2))
		closest = math.min(closest, flat(camera.CFrame.Position - ROOT).Magnitude)
		look, x, y = nextLook, nx, ny
	end
	return turn, slide, closest
end

describe("CameraController framing: drawing on a lock", function()
	for _, case in
		{
			{ name = "ahead", at = Vector3.new(0, 0, -6) },
			{ name = "to the side", at = Vector3.new(-7, 0, -2) },
			{ name = "behind the camera", at = Vector3.new(1, 0, 6) },
		}
	do
		it(("eases onto a lock %s and back off it, never through the player"):format(case.name), function()
			local fixture = load()
			fixture.frames(240)
			local target = character("Kobold", ROOT + case.at, fixture.world)
			fixture.controller.setLockTarget(target)
			local turnOn, slideOn, closestOn = watch(fixture, 120)
			fixture.controller.setLockTarget(nil)
			local turnOff, slideOff, closestOff = watch(fixture, 120)
			for _, turn in { turnOn, turnOff } do
				expect(turn).toBeLessThanOrEqual(8)
			end
			for _, slide in { slideOn, slideOff } do
				expect(slide).toBeLessThanOrEqual(0.05)
			end
			for _, closest in { closestOn, closestOff } do
				expect(closest).toBeGreaterThan(CameraData.lock.minDistance * 0.6)
			end
		end)
	end

	it("eases out of a lock whose target is gone (the shatter) from where the target was", function()
		local fixture = load()
		fixture.frames(240)
		local target = character("Kobold", ROOT + Vector3.new(0, 0, -6), fixture.world)
		fixture.controller.setLockTarget(target)
		fixture.frames(240)
		target.Parent = nil
		local turn, slide = watch(fixture, 120)
		expect(turn).toBeLessThanOrEqual(8)
		expect(slide).toBeLessThanOrEqual(0.05)
	end)
end)

describe("CameraController framing: what blocks the view", function()
	-- A settled camera, the point half way from the player's chest to it, and a box size that
	-- fills the line there.
	local function settled(): (Fixture, Vector3, Vector3)
		local fixture = load()
		fixture.frames(240)
		local spot = fixture.camera.CFrame.Position
		local chest = ROOT + Vector3.new(0, CameraData.follow.focusHeight, 0)
		return fixture, spot, chest:Lerp(spot, 0.5)
	end
	local SIZE = Vector3.new(4, 6, 1)

	local cases: { { name: string, place: (fixture: Fixture, at: Vector3) -> () } } = {
		{
			name = "an enemy",
			place = function(fixture, at)
				character("Boar", at, fixture.world)
			end,
		},
		{
			name = "another player's accessory and weapon",
			place = function(fixture, at)
				local other = character("Other", at + Vector3.new(0, 0, -2), fixture.world)
				local accessory = Instance.new("Accessory")
				part("Handle", at, SIZE, accessory)
				accessory.Parent = other
				local weapon = Instance.new("Model")
				weapon.Name = "Weapon"
				part("Blade", at + Vector3.new(0, 0, 0.5), SIZE, weapon)
				weapon.Parent = other
			end,
		},
		{
			name = "a loose accessory",
			place = function(fixture, at)
				local accessory = Instance.new("Accessory")
				part("Handle", at, SIZE, accessory)
				accessory.Parent = fixture.world
			end,
		},
		{
			name = "the player's own weapon and accessory",
			place = function(fixture, at)
				local weapon = Instance.new("Model")
				weapon.Name = "Weapon"
				part("Blade", at, SIZE, weapon)
				weapon.Parent = fixture.subject
				local accessory = Instance.new("Accessory")
				part("Handle", at + Vector3.new(0, 0, 0.5), SIZE, accessory)
				accessory.Parent = fixture.subject
			end,
		},
		{
			name = "a see-through part",
			place = function(fixture, at)
				part("Glass", at, SIZE, fixture.world).Transparency = CameraData.collision.seeThrough
			end,
		},
	}
	for _, case in cases do
		it(("never pulls in for %s"):format(case.name), function()
			local fixture, spot, middle = settled()
			case.place(fixture, middle)
			for _ = 1, 30 do
				fixture.frames(1)
				expect((fixture.camera.CFrame.Position - spot).Magnitude).toBeLessThan(1e-3)
			end
		end)
	end

	it("pulls a two-shot in for a wall too, the camera and its aim together", function()
		local fixture = load()
		fixture.frames(60)
		fixture.controller.setLockTarget(character("Kobold", ROOT + Vector3.new(0, 0, -6), fixture.world))
		fixture.frames(240)
		local spot = fixture.camera.CFrame.Position
		local look = fixture.camera.CFrame.LookVector
		local chest = ROOT + Vector3.new(0, CameraData.follow.focusHeight, 0)
		local middle = chest:Lerp(spot, 0.6)
		part("Pillar", middle, Vector3.new(3, 12, 3), fixture.world)
		fixture.frames(1)
		expect((fixture.camera.CFrame.Position - chest).Magnitude).toBeLessThan((spot - chest).Magnitude * 0.7)
		expect(angleBetween(fixture.camera.CFrame.LookVector, look)).toBeLessThan(0.5)
	end)

	it("still pulls in for a wall, behind a character standing in front of it", function()
		local fixture, spot, middle = settled()
		character("Boar", middle, fixture.world)
		part("Wall", middle + (spot - middle).Unit * 2, Vector3.new(8, 8, 1), fixture.world)
		fixture.frames(2)
		local away = (fixture.camera.CFrame.Position - ROOT).Magnitude
		expect(away).toBeLessThan((spot - ROOT).Magnitude * 0.75)
	end)
end)
