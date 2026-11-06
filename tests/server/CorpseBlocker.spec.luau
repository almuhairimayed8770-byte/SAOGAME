--!strict
--[[
	A dead enemy's blocker faces (D-198, D-281, D-315) end to end: the real EnemyService,
	EntityService, RigBuilder rigs and CollisionGroups over a fake engine.

	Blocker faces are solid to players, enemies and other faces (D-281). A body that died stays in
	the world for Combat.corpseRemoveDelay, but every client shatters it once the kill's hit-stop
	(Moments.deathDuckDelay) and the death freeze (Combat.deathFreeze) have passed. So:
	- while the frozen body still stands, its faces stay solid, and blockerClear counts them: a
	  stopped rush over a body still standing does not turn solid inside it;
	- from the shatter on, every face is off: nobody bumps into a body no longer drawn, and a
	  stopped rush over it may rejoin.
]]

Harness.stubService("CollectionService", {
	AddTag = function(_self, instance, tag)
		instance:AddTag(tag)
	end,
	RemoveTag = function(_self, instance, tag)
		instance:RemoveTag(tag)
	end,
	HasTag = function(_self, instance, tag)
		return instance:HasTag(tag)
	end,
})
Harness.stubService("RunService", {
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
})

local EntityService = Harness.load("src/server/services/EntityService")
local EnemyService = Harness.load("src/server/services/EnemyService")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local AI = Harness.load("src/shared/data/ai")
local Combat = Harness.load("src/shared/data/combat")
local Moments = Harness.load("src/shared/data/moments")
local CollectionService = Harness.game():GetService("CollectionService")

local FRAME = 1 / 60
local GROUPS = AI.collision
-- When every client shatters a body: the kill's hit-stop, then the death freeze.
local SHATTER = Moments.deathDuckDelay() + Combat.deathFreeze

local clock = { t = 7000 }
local positions: { [Model]: Vector3 } = {}
local offsets: { [Model]: { [BasePart]: CFrame } } = {}

local function yawOf(model: Model): Vector3
	local align = EnemyService.alignOf(model)
	local look = if align ~= nil then align.CFrame.LookVector else (model.PrimaryPart :: BasePart).CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function placeParts(model: Model)
	local root = model.PrimaryPart :: BasePart
	local position = positions[model]
	root.CFrame = CFrame.lookAt(position, position + yawOf(model))
	for part, offset in offsets[model] do
		part.CFrame = root.CFrame * offset
	end
end

local engine = {
	place = function(model: Model, cframe: CFrame)
		local root = model.PrimaryPart :: BasePart
		root.CFrame = CFrame.new()
		local list: { [BasePart]: CFrame } = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= root then
				list[part] = root.CFrame:ToObjectSpace(part.CFrame)
			end
		end
		offsets[model] = list
		root.CFrame = cframe
		EnemyService.addYawAlign(root, cframe.LookVector)
		positions[model] = cframe.Position
		placeParts(model)
	end,
	position = function(model: Model): Vector3
		return positions[model]
	end,
	facing = function(model: Model): Vector3
		return yawOf(model)
	end,
	setFacing = function(model: Model, facing: Vector3)
		EnemyService.applyFacing(model, facing)
	end,
	moveTo = function() end,
	stop = function() end,
	setWalkSpeed = function() end,
	computePath = function()
		return nil
	end,
	destroy = function(model: Model)
		model.Parent = nil
	end,
	setCollisionGroup = function(model: Model, group: string)
		CollisionGroups.assign(model, group)
	end,
	bodyClear = function(): boolean
		return true
	end,
}

local function frame()
	clock.t += FRAME
	EnemyService.step(FRAME)
	EntityService.tick(FRAME)
end

local function fresh()
	EnemyService.reset()
	EntityService.reset()
	clock.t = 7000
	positions = {}
	offsets = {}
	local now = function()
		return clock.t
	end
	EntityService.bind({
		now = now,
		fireAll = function() end,
		heartbeat = nil,
		addTag = function(instance, tag)
			CollectionService:AddTag(instance, tag)
		end,
		removeTag = function(instance, tag)
			CollectionService:RemoveTag(instance, tag)
		end,
		respawn = function() end,
		playerRemoving = nil,
	})
	EnemyService.bind({
		entities = EntityService,
		combat = { enemyStrike = function() end },
		rigBuilder = RigBuilder,
		fireAll = function() end,
		engine = engine,
		players = function()
			return {}
		end,
		heartbeat = nil,
		serverTime = now,
		folder = Instance.new("Folder"),
		random = Random.new(5),
		spawnTask = function(fn)
			fn()
		end,
	} :: any)
end

local function facesOf(model: Model): { BasePart }
	local faces: { BasePart } = {}
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.CollisionGroup == GROUPS.blockers then
			table.insert(faces, part)
		end
	end
	return faces
end

local function anySolid(model: Model): boolean
	for _, face in facesOf(model) do
		if face.CanCollide then
			return true
		end
	end
	return false
end

-- A held kobold at the origin, killed now; returns its model and the server time it died.
local function deadKobold(): (Model, number)
	local id = EnemyService.spawn("KoboldAxeman", CFrame.new(0, 3, 0))
	EnemyService.setHeld(id, true)
	local model = EnemyService.modelOf(id) :: Model
	frame()
	expect(#facesOf(model)).toBe(2) -- the body's face and the axe's (D-315)
	expect(anySolid(model)).toBe(true)
	local diedAt = clock.t
	EntityService.die(id)
	return model, diedAt
end

describe("a dead enemy's blocker faces (D-281)", function()
	it("stay solid while the frozen body stands, and are all off from the shatter on", function()
		fresh()
		local model, diedAt = deadKobold()
		local offAt: number? = nil
		while clock.t - diedAt < Combat.corpseRemoveDelay - 0.1 do
			frame()
			local solid = anySolid(model)
			if clock.t - diedAt < SHATTER - 1e-9 then
				expect(solid).toBe(true)
			elseif not solid and offAt == nil then
				offAt = clock.t
			end
			if offAt ~= nil then
				expect(solid).toBe(false) -- off, and never back on
			end
		end
		expect(offAt).never.toBeNil()
		-- Off within one AI tick of the shatter: nobody walks into a body no longer drawn.
		expect((offAt :: number) - diedAt).toBeLessThan(SHATTER + AI.tickSeconds() + FRAME)
		expect(model.Parent).never.toBeNil() -- the model itself still waits out corpseRemoveDelay
		for _, face in facesOf(model) do
			expect(face.CollisionGroup).toBe(GROUPS.blockers)
		end
	end)

	it("count in blockerClear while the body stands, and no longer once it shattered", function()
		fresh()
		local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(40, 3, 0))
		EnemyService.setHeld(boarId, true)
		local boar = EnemyService.modelOf(boarId) :: Model
		local corpse, diedAt = deadKobold()
		-- The boar's body over the corpse's: a stopped rush that ended there.
		positions[boar] = Vector3.new(0.5, 3, 0)
		placeParts(boar)
		expect(EnemyService.blockerClear(boar)).toBe(false)
		while clock.t - diedAt < SHATTER - FRAME do
			frame()
			expect(anySolid(corpse)).toBe(true)
			expect(EnemyService.blockerClear(boar)).toBe(false)
		end
		while clock.t - diedAt < SHATTER + AI.tickSeconds() + FRAME do
			frame()
		end
		expect(anySolid(corpse)).toBe(false)
		expect(EnemyService.blockerClear(boar)).toBe(true)
		-- A corpse far from the boar never held it up, and the destroyed model is let go.
		while clock.t - diedAt < Combat.corpseRemoveDelay + 0.2 do
			frame()
		end
		expect(corpse.Parent).toBeNil()
		expect(EnemyService.blockerClear(boar)).toBe(true)
	end)

	it("a body that never died (despawned, reset) leaves no corpse behind", function()
		fresh()
		local id = EnemyService.spawn("KoboldAxeman", CFrame.new(0, 3, 0))
		local model = EnemyService.modelOf(id) :: Model
		local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(0.5, 3, 0))
		local boar = EnemyService.modelOf(boarId) :: Model
		EnemyService.setHeld(id, true)
		EnemyService.setHeld(boarId, true)
		expect(EnemyService.blockerClear(boar)).toBe(false)
		EnemyService.reset()
		-- Nothing is tracked past a reset: the boar's question meets no entry and no corpse.
		expect(EnemyService.blockerClear(boar)).toBe(true)
		expect(anySolid(model)).toBe(true) -- a reset changes no part; the model goes with its owner
	end)
end)
