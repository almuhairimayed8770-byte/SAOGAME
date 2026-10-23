--!strict
--[[
	A real player's swing from the remote to the boar's HP (D-112, D-113), as close to the Play-test
	as Lune allows: an Avatar-Joint-Upgrade character (AnimationConstraints, BallSockets, rig
	attachments, an accessory) put through the real PlaygroundService.onCharacter (CharacterReady,
	applyScale, WeaponBuilder.equip, registerPlayer); the boar built by RigBuilder and placed the way
	EnemyService.spawn places one; the request through the real Net.luau receive path
	(OnServerEvent, rate bucket, schema); the engine queries from tools/hitmatrix (the fake spherecast
	and bounds query the hit matrix holds to the engine's rules); a server-sized clock; the
	replicated root a latency plus an interpolation buffer behind the client's body.

	The client's side is AimLogic's rules (CharacterController's, tested there): the lock turn at
	aim.lockTurnRate, the swing's snap and the facing the request carries. CombatService.traceSink
	reports each closed window.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

Harness.stubService("CollectionService", {
	AddTag = function(_self: any, instance: any, tag: string)
		instance:AddTag(tag)
	end,
	RemoveTag = function(_self: any, instance: any, tag: string)
		instance:RemoveTag(tag)
	end,
	HasTag = function(_self: any, instance: any, tag: string): boolean
		return instance:HasTag(tag)
	end,
})
Harness.stubService("RunService", {
	IsServer = function(): boolean
		return true
	end,
	IsClient = function(): boolean
		return false
	end,
})

local EntityService = Harness.load("src/server/services/EntityService")
local CombatService = Harness.load("src/server/services/CombatService")
local PlaygroundService = Harness.load("src/server/services/PlaygroundService")
local CharacterReady = Harness.load("src/server/world/CharacterReady")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local AimLogic = Harness.load("src/client/controllers/AimLogic")
local Rigs = Harness.load("src/shared/data/rigs")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Combat = Harness.load("src/shared/data/combat")
local World = Harness.load("src/shared/data/world")
local RandomShim = Harness.environment().Random

local AIM = Combat.aim
local FRAME = 1 / 60
local SERVER_EPOCH = 1792745000 -- the size workspace:GetServerTimeNow returns
local LATENCY = 0.06 -- one way, seconds
local INTERPOLATION = 0.05 -- the replicated root's buffer, seconds

-- tools/ modules are plain Lune scripts: load one with only Lune's own libraries to require.
local function loadTool(path: string): any
	local source = fs.readFile(Harness.repoRoot() .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "a tool may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
local _, FIELD = HitMatrix.standing(Harness)

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- ---------------------------------------------------------------------------------------------
-- The real Net over recording fake remotes (tests/net/Net.spec.luau's loader)
-- ---------------------------------------------------------------------------------------------

local NET_PATH = "src/shared/net/Net"

local function newNet(): (any, { [string]: any }, { string })
	local created: { any } = {}
	local function connection(): any
		return {
			Connected = true,
			Disconnect = function(self: any)
				self.Connected = false
			end,
		}
	end
	local function newInstance(className: string): any
		local fake: any = { ClassName = className, Name = className, Parent = nil, sent = {}, handlers = {} }
		function fake.IsA(self: any, name: string): boolean
			return self.ClassName == name
		end
		fake.OnServerEvent = {
			Connect = function(_self: any, handler: any): any
				table.insert(fake.handlers, handler)
				return connection()
			end,
		}
		function fake.FireClient(self: any, player: any, payload: any)
			table.insert(self.sent, { player = player, payload = payload })
		end
		function fake.FireAllClients(self: any, payload: any)
			table.insert(self.sent, { payload = payload })
		end
		table.insert(created, fake)
		return fake
	end
	local services: { [string]: any } = {
		RunService = {
			IsServer = function(): boolean
				return true
			end,
			IsClient = function(): boolean
				return false
			end,
		},
		Players = {
			PlayerRemoving = {
				Connect = function(): any
					return connection()
				end,
			},
			GetPlayers = function(): { any }
				return {}
			end,
		},
		ReplicatedStorage = { Name = "ReplicatedStorage", ClassName = "ReplicatedStorage" },
	}
	local env = Harness.environment()
	env.script = Harness.node(NET_PATH)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	env.Instance = { new = newInstance }
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	local Net = luau.load(Harness.readFile(NET_PATH .. ".luau"), { debugName = NET_PATH, environment = env :: any })()
	local net = Net.server()
	local remotes: { [string]: any } = {}
	for _, fake in created do
		if fake.ClassName ~= "Folder" then
			remotes[fake.Name] = fake
		end
	end
	local abuse: { string } = {}
	net.abuse:Connect(function(_player: any, name: string, reason: string)
		table.insert(abuse, name .. ": " .. reason)
	end)
	return net, remotes, abuse
end

-- ---------------------------------------------------------------------------------------------
-- An Avatar-Joint-Upgrade player character, sized from dev.luau hitMatrix.avatar
-- ---------------------------------------------------------------------------------------------

local EXTRA_ATTACHMENTS: { [string]: { string } } = {
	HumanoidRootPart = { "RootAttachment" },
	RightHand = { "RightGripAttachment" },
	LeftHand = { "LeftGripAttachment" },
	Head = { "HatAttachment", "HairAttachment", "FaceFrontAttachment" },
	UpperTorso = { "BodyBackAttachment", "BodyFrontAttachment", "NeckAttachment" },
	LowerTorso = { "WaistCenterAttachment", "WaistBackAttachment" },
}

-- The engine's child order: the Humanoid's parts first (Pose.chain reads GetDescendants in order).
local PART_ORDER = {
	"HumanoidRootPart",
	"LowerTorso",
	"UpperTorso",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local COLLIDES = { HumanoidRootPart = true, UpperTorso = true, LowerTorso = true, Head = true }

-- The character and the root height that stands its feet on the field.
local function buildCharacter(name: string): (any, number)
	local spec = Dev.hitMatrix.avatar
	local scale = Rigs.PlayerR15.scale
	local body = Vector3.new(scale.bodyWidth, scale.bodyHeight, scale.bodyDepth)
	local head = Vector3.new(scale.head, scale.head, scale.head)
	local function scaleOf(partName: string): Vector3
		return if partName == "Head" then head else body
	end
	local model = Instance.new("Model")
	model.Name = name
	local parts: { [string]: any } = {}
	for _, partName in PART_ORDER do
		local part = Instance.new("MeshPart")
		part.Name = partName
		part.Size = vec(spec.parts[partName]) * scaleOf(partName)
		part.CanCollide = COLLIDES[partName] == true
		part.Parent = model
		parts[partName] = part
		for _, extra in EXTRA_ATTACHMENTS[partName] or {} do
			local attachment = Instance.new("Attachment")
			attachment.Name = extra
			attachment.Parent = part
		end
	end
	model.PrimaryPart = parts.HumanoidRootPart
	for _, joint in Rigs.PlayerR15.joints do
		local pair = spec.attachments[joint.name]
		if pair == nil then
			continue -- the Weapon: WeaponBuilder hangs it
		end
		local a0 = Instance.new("Attachment")
		a0.Name = joint.name .. "RigAttachment"
		a0.CFrame = CFrame.new(vec(pair[1]) * scaleOf(joint.part0))
		a0.Parent = parts[joint.part0]
		local a1 = Instance.new("Attachment")
		a1.Name = joint.name .. "RigAttachment"
		a1.CFrame = CFrame.new(vec(pair[2]) * scaleOf(joint.part1))
		a1.Parent = parts[joint.part1]
		local constraint = Instance.new("AnimationConstraint")
		constraint.Name = joint.name
		constraint.Attachment0 = a0
		constraint.Attachment1 = a1
		constraint.Parent = parts[joint.part1]
		if joint.name ~= "Root" then
			local ball = Instance.new("BallSocketConstraint")
			ball.Name = joint.name .. "BallSocket"
			ball.Attachment0 = a0
			ball.Attachment1 = a1
			ball.Parent = parts[joint.part1]
		end
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	-- One accessory on the head, on an AccessoryWeld, as a dressed avatar carries.
	local accessory = Instance.new("Accessory")
	accessory.Name = "Hair"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(2, 1, 2)
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Parent = accessory
	local hairAttachment = Instance.new("Attachment")
	hairAttachment.Name = "HairAttachment"
	hairAttachment.Parent = handle
	local weld = Instance.new("Weld")
	weld.Name = "AccessoryWeld"
	weld.Part0 = handle
	weld.Part1 = parts.Head
	weld.Parent = handle
	accessory.Parent = model
	-- Feet on the field (y = 0), as the Humanoid's HipHeight holds a spawned character.
	local lowest = math.huge
	for partName, frame in Pose.solve(model, CFrame.new(), {}) do
		local part = parts[partName]
		if part ~= nil then
			local half = part.Size * 0.5
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						lowest = math.min(
							lowest,
							frame:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)).Y
						)
					end
				end
			end
		end
	end
	return model, -lowest
end

local function placeParts(model: any, rootCFrame: CFrame)
	for partName, frame in Pose.solve(model, rootCFrame, {}) do
		local part = model:FindFirstChild(partName, true)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = frame
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- One swing
-- ---------------------------------------------------------------------------------------------

type Swing = {
	boarBearing: number, -- degrees from the body's starting look (+ = left), 5 studs out
	-- The client's body yaw (degrees from the starting look, + = left) at a time since the send
	-- window opened; the replicated root shows it LATENCY + INTERPOLATION later. Nil: never turns.
	bodyYaw: ((t: number) -> number)?,
	sendAt: number?, -- seconds after the window opens that the request is sent (default 0.05)
	-- The facing the request carries, degrees from the starting look; nil: computed by AimLogic
	-- from the body's yaw history and `lockBearing` (or the soft assist with no lock).
	facingYaw: number?,
	lockBearing: number?, -- the lock's bearing from the starting look (nil: no lock)
}

type Result = {
	rejected: { string },
	abuse: { string },
	hpBefore: number,
	hpAfter: number,
	events: { any },
	facingYaw: number,
	facing: Vector3, -- the request's facing, world space
	serverYawAtReceipt: number,
}

local BASE_YAW = 30 -- any world heading: the swing works in the body's frame

local function yawCFrame(degrees: number): CFrame
	return CFrame.Angles(0, math.rad(degrees), 0)
end

local function wrapped(degrees: number): number
	return (degrees + 180) % 360 - 180
end

local function swing(s: Swing): Result
	CombatService.reset()
	EntityService.reset()
	PlaygroundService.reset()
	local clock = { t = SERVER_EPOCH + 0.37 }
	local function now(): number
		return clock.t
	end
	local net, remotes, abuse = newNet()
	EntityService.bind({
		now = now,
		fireAll = nil,
		heartbeat = nil,
		addTag = function(instance: any, tag: string)
			instance:AddTag(tag)
		end,
		removeTag = function(instance: any, tag: string)
			instance:RemoveTag(tag)
		end,
		respawn = function() end,
		playerRemoving = nil,
	})
	local workspaceFolder = Instance.new("Folder")
	workspaceFolder.Name = "Workspace"

	-- The player, through PlaygroundService.onCharacter.
	local character, rootHeight = buildCharacter("Player1")
	local base = CFrame.new(10, rootHeight, -4) * yawCFrame(BASE_YAW)
	placeParts(character, base)
	character.Parent = workspaceFolder
	local player: any = { Name = "Player1", DisplayName = "Player1", UserId = 1 }
	PlaygroundService.bind({
		now = now,
		entities = EntityService,
		enemies = {
			Despawned = {
				Connect = function(): any
					return { Disconnect = function() end }
				end,
			},
			spawn = function() end,
		},
		weaponBuilder = WeaponBuilder,
		build = nil,
		players = nil,
		heartbeat = nil,
		waitForChild = function(parent: any, name: string): any
			return parent:FindFirstChild(name)
		end,
		characterReady = function(p: any, c: any, timeout: number): any
			local fake = { t = 0 }
			return CharacterReady.wait(p, c, timeout, {
				now = function(): number
					return fake.t
				end,
				step = function()
					fake.t += FRAME
				end,
				appearanceLoaded = function(): boolean
					return true
				end,
			})
		end,
		random = RandomShim.new(7),
	})
	local playerId = PlaygroundService.onCharacter(player, character)
	assert(playerId ~= nil, "onCharacter did not register the player")
	placeParts(character, base) -- equip placed the sword from the hand at equip time

	-- The boar, the way EnemyService.spawn places one: 5 studs out at its bearing, facing the player.
	local boarDef = Enemies.scaled(Enemies.byId("FrenzyBoar"))
	local boar = RigBuilder.build(boarDef.skin, boarDef.name)
	local humanoid = boar:FindFirstChildOfClass("Humanoid")
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = boarDef.moveSpeed
	boar.Parent = workspaceFolder
	local boarHeight =
		PlaygroundLayout.rootHeight(Rigs[boarDef.skin].hipHeight, boar.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local out = (base * yawCFrame(s.boarBearing)).LookVector
	local origin = base.Position
	local at = Vector3.new(origin.X, boarHeight, origin.Z) + out * 5
	placeParts(boar, CFrame.lookAt(at, Vector3.new(origin.X, boarHeight, origin.Z)))
	local yawAttachment = Instance.new("Attachment")
	yawAttachment.Name = "EnemyYaw"
	yawAttachment.Parent = boar.PrimaryPart
	EntityService.registerEnemy(boar, boarDef, {})
	local hpBefore = boar:GetAttribute("HP")

	-- The engine queries over everything in the world.
	local all: { any } = { FIELD }
	for _, model in { character, boar } do
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(all, descendant)
			end
		end
	end
	local world = HitMatrix.world(all)
	CombatService.bind({
		now = now,
		net = net,
		heartbeat = nil,
		cast = world.cast,
		overlap = world.overlap,
		random = RandomShim.new(11),
	})
	CombatService.start()
	remotes.ClientReady.handlers[1](player, {})
	local events: { any } = {}
	CombatService.traceSink = function(event: any)
		table.insert(events, event)
	end

	local bodyYaw = s.bodyYaw or function(_t: number): number
		return 0
	end
	local opened = clock.t
	local clipId: string? = nil
	local clipStart = 0
	-- The replicated root: the body as it was LATENCY + INTERPOLATION ago, carried by the clip's
	-- root motion along its own look once the swing began.
	local function serverRoot(t: number): CFrame
		local seen = t - LATENCY - INTERPOLATION
		local frame = base * yawCFrame(bodyYaw(seen - opened))
		if clipId == nil then
			return frame
		end
		local clip = CombatService.clipById(clipId)
		local tau = math.clamp(seen - clipStart, 0, clip.duration)
		local a = ClipSampler.rootMotionAt(clip, 0)
		local b = ClipSampler.rootMotionAt(clip, tau)
		return frame * CFrame.new(b[1] - a[1], b[2] - a[2], b[3] - a[3])
	end
	local function heartbeat()
		clock.t += FRAME
		character.PrimaryPart.CFrame = serverRoot(clock.t)
		EntityService.tick(FRAME)
		CombatService.tick()
	end

	-- The client's facing: its body yaw history over the lag window, then the swing's snap.
	local sendAt = s.sendAt or 0.05
	local facingYaw = s.facingYaw
	if facingYaw == nil then
		local history = AimLogic.newHistory()
		local t = 0
		while t < sendAt + 1e-9 do
			AimLogic.record(history, t, bodyYaw(t), Combat.lagAllowance)
			t += FRAME
		end
		local yaw = bodyYaw(sendAt)
		local delta: number? = nil
		if s.lockBearing ~= nil then
			delta = wrapped(s.lockBearing - yaw)
		else
			local pick = AimLogic.assistPick({ { id = 1, distance = 5, bearing = wrapped(s.boarBearing - yaw) } }, AIM)
			delta = if pick ~= nil then pick.bearing else nil
		end
		if delta ~= nil then
			local lo, hi = AimLogic.range(history)
			yaw += AimLogic.requestTurn(delta, lo, hi, AIM)
			AimLogic.record(history, sendAt, yaw, Combat.lagAllowance)
		end
		local lo, hi = AimLogic.range(history)
		facingYaw = yaw + AimLogic.sendOffset(lo, hi, AIM)
	end
	local facingLook = (base * yawCFrame(facingYaw :: number)).LookVector

	-- Frames up to the send, the request between two Heartbeats, then the swing plays out.
	while clock.t + FRAME < opened + sendAt do
		heartbeat()
	end
	local receipt = opened + sendAt
	clock.t = receipt
	character.PrimaryPart.CFrame = serverRoot(receipt)
	local serverLook = character.PrimaryPart.CFrame.LookVector
	local serverYawAtReceipt = AimLogic.bearing(base.LookVector.X, base.LookVector.Z, serverLook.X, serverLook.Z)
	remotes.BasicAttackRequest.handlers[1](player, {
		facing = { facingLook.X, facingLook.Y, facingLook.Z },
		clientTime = receipt - LATENCY,
	})
	local rejected: { string } = {}
	for _, entry in remotes.ActionRejected.sent do
		table.insert(rejected, entry.payload.reason)
	end
	for _, entry in remotes.ActionStarted.sent do
		clipId = entry.payload.clipId
		clipStart = receipt - LATENCY -- the client began its clip when it sent
	end
	local stopAt = clock.t + 1.2
	while clock.t < stopAt do
		heartbeat()
	end
	CombatService.traceSink = nil
	return {
		rejected = rejected,
		abuse = abuse,
		hpBefore = hpBefore,
		hpAfter = boar:GetAttribute("HP"),
		events = events,
		facingYaw = facingYaw :: number,
		facing = facingLook,
		serverYawAtReceipt = serverYawAtReceipt,
	}
end

-- The lock's acquisition turn: still until `from`, then at aim.lockTurnRate to `target`.
local function lockTurn(from: number, target: number): (t: number) -> number
	return function(t: number): number
		return math.min(target, math.max(0, t - from) * AIM.lockTurnRate)
	end
end

describe("A player's basic swing through the real remote (D-112, D-113)", function()
	it("cuts a boar 5 studs ahead, or 25 degrees either side, and takes its HP", function()
		-- Facing the body's look, and with the soft assist's snap toward the boar (the client's rule).
		for _, bearing in { 0, 25, -25 } do
			for _, facingYaw in { 0 :: number?, nil } do
				local result = swing({ boarBearing = bearing, facingYaw = facingYaw })
				expect(result.rejected).toEqual({})
				expect(result.abuse).toEqual({})
				expect(result.facingYaw).toBeCloseTo(if facingYaw == nil then bearing else 0, 1e-6)
				expect(result.hpAfter < result.hpBefore).toBe(true)
				local event = result.events[1]
				expect(event).never.toBeNil()
				expect(event.hits).toBe(1)
				-- Measured from the run's facing (the clip's root motion carries the body a little).
				expect(math.abs(event.nearest.bearingDegrees - wrapped(bearing - result.facingYaw)) < 3).toBe(true)
			end
		end
	end)

	it("a body 165 degrees away with no lock swings at the air: the assist never turns that far", function()
		local result = swing({ boarBearing = 165 })
		expect(result.rejected).toEqual({})
		expect(result.facingYaw).toBe(0) -- the boar is outside the soft assist's cone
		expect(result.hpAfter).toBe(result.hpBefore)
		local event = result.events[#result.events]
		expect(event.hits).toBe(0)
		expect(math.abs(event.nearest.bearingDegrees - 165) < 3).toBe(true)
		expect(event.nearest.clearance > 0).toBe(true)
	end)

	it("locked on and swung at once, the snap reaches a boar 75 off before the root has turned (D-113)", function()
		-- The body's own look misses it (the arc ends near 60 to the left at 5 studs).
		local unaimed = swing({ boarBearing = 75, facingYaw = 0 })
		expect(unaimed.rejected).toEqual({})
		expect(unaimed.hpAfter).toBe(unaimed.hpBefore)
		-- The swing snaps 40 toward the lock; the replicated root still looks where it did, and the
		-- server sweeps where the request faces.
		local result = swing({ boarBearing = 75, lockBearing = 75 })
		expect(result.rejected).toEqual({})
		expect(result.facingYaw).toBeCloseTo(AIM.snapDegrees, 1e-6)
		expect(math.abs(result.serverYawAtReceipt) < 1e-3).toBe(true)
		expect(result.hpAfter < result.hpBefore).toBe(true)
		expect(result.events[1].rootLook:Dot(result.events[1].facing) < math.cos(math.rad(30))).toBe(true)
	end)

	it("locked on, the body turns to the boar and the same swing lands", function()
		-- F at 0.05 s; the turn takes 165 / 720 s; the swing goes once the replicated root has it.
		local result = swing({ boarBearing = 165, lockBearing = 165, bodyYaw = lockTurn(0.05, 165), sendAt = 0.6 })
		expect(result.rejected).toEqual({})
		expect(result.facingYaw).toBeCloseTo(165, 1e-6)
		expect(math.abs(result.serverYawAtReceipt - 165) < 1e-3).toBe(true)
		expect(result.hpAfter < result.hpBefore).toBe(true)
		expect(result.events[1].hits).toBe(1)
	end)

	it("a swing sent mid-turn is accepted, swept between the server's root and the body", function()
		-- 0.12 s into the turn the body is 86 round; the replicated root shows 7. The body's own look
		-- would be refused (79 off); the request faces 49 from where the lag window began instead.
		local turn = lockTurn(0.05, 165)
		local refused = swing({ boarBearing = 165, bodyYaw = turn, sendAt = 0.17, facingYaw = turn(0.17) })
		expect(refused.rejected).toEqual({ "Facing" })
		local result = swing({ boarBearing = 165, lockBearing = 165, bodyYaw = turn, sendAt = 0.17 })
		expect(result.rejected).toEqual({})
		expect(result.facingYaw < turn(0.17)).toBe(true)
		expect(
			math.abs(result.facingYaw - result.serverYawAtReceipt) <= math.deg(math.acos(1 - Combat.facingTolerance))
		).toBe(true)
		-- The server swept along the facing the request carried (D-113).
		expect(result.events[1].facing:Dot(result.facing)).toBeCloseTo(1, 1e-6)
	end)
end)
