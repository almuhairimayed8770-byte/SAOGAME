--!strict
--[[
	Room between enemies (D-259, REVIEW 2026-10-25 issue 22 and F3): after the shatter in the parry
	take the kobold walked into the boar and stayed inside it. Only roots collide between enemies,
	and a root is far smaller than the body it carries (a boar's head and snout, a kobold's arms and
	axe), so two enemies stood inside each other with their roots touching or, a rush's root in the
	rushing group, straight through.

	First the pure rules (Spacing over the real rigs' footprints), then the whole loop: the real
	EnemyService, brains, EntityService and RigBuilder rigs over a fake engine whose bodies walk to
	their MoveTo goals and never collide (the worst case: nothing but the AI keeps them apart). The
	judge is independent of the rule: the ground shadows of every part of two enemies (each part's
	eight corners, projected flat, as a convex hull) must never overlap.
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
local Spacing = Harness.load("src/server/ai/Spacing")
local RushWorld = Harness.load("src/shared/choreo/RushWorld")
local AI = Harness.load("src/shared/data/ai")
local Enemies = Harness.load("src/shared/data/enemies")
local Playground = Harness.load("src/shared/data/playground")
local CollectionService = Harness.game():GetService("CollectionService")

local FRAME = 1 / 60
local GAP = AI.spacing.gapStuds
local FORWARD = Vector3.new(0, 0, -1)

local function footprintOf(rigId: string): any
	return Spacing.footprintOf(RushWorld.profileOf(RigBuilder.build(rigId)))
end

local BOAR_FOOT = footprintOf("Boar")
local KOBOLD_FOOT = footprintOf("Kobold")

local function body(position: Vector3, facing: Vector3, footprint: any): any
	return { position = position, facing = facing, footprint = footprint }
end

-- ------------------------------------------------------------------------------------------
-- The pure rules
-- ------------------------------------------------------------------------------------------

describe("Spacing footprints and clearance (D-259)", function()
	it("measures each rig's whole body, not its root: the boar's snout and the kobold's arms count", function()
		-- The boar's root is 2.4 x 5 (it reaches 2.5 ahead); its head and snout reach farther.
		expect(BOAR_FOOT.front).toBeGreaterThan(2.5 + 1)
		expect(BOAR_FOOT.radius).toBeGreaterThanOrEqual(1.2)
		-- The kobold's root is 2 wide; its arms hang outside it.
		expect(KOBOLD_FOOT.radius).toBeGreaterThan(1)
	end)

	it("is the clear ground between two capsules, negative when they overlap, and points out", function()
		local a = body(Vector3.new(0, 3, 0), FORWARD, { front = 1, back = 1, radius = 1 })
		local b = body(Vector3.new(5, 3, 0), FORWARD, { front = 1, back = 1, radius = 1 })
		local clear, out = Spacing.clearance(a, b, Vector3.xAxis)
		expect(math.abs(clear - 3)).toBeLessThan(1e-6)
		expect((out - Vector3.new(-1, 0, 0)).Magnitude).toBeLessThan(1e-6)
		-- A long boar side on: its spine runs along X, so a kobold beside its snout is near it.
		local boar = body(Vector3.new(0, 3, 0), Vector3.new(1, 0, 0), BOAR_FOOT)
		local kobold = body(Vector3.new(BOAR_FOOT.front, 3, 0), FORWARD, KOBOLD_FOOT)
		local overlap = Spacing.clearance(kobold, boar, Vector3.xAxis)
		expect(overlap).toBeLessThan(0)
		-- Two spines on one spot take the fallback way out.
		local _, fallback = Spacing.clearance(a, body(Vector3.new(0, 3, 0), FORWARD, a.footprint), Vector3.zAxis)
		expect((fallback - Vector3.zAxis).Magnitude).toBeLessThan(1e-6)
	end)
end)

describe("Spacing.steer (D-259)", function()
	local function neighbor(other: any, share: number?): any
		return { body = other, share = share or 1, side = 1 }
	end

	it("leaves a body with room alone", function()
		local me = body(Vector3.new(0, 3, 0), FORWARD, KOBOLD_FOOT)
		local far = body(Vector3.new(30, 3, 0), FORWARD, BOAR_FOOT)
		expect(Spacing.steer(me, nil, { neighbor(far) })).toBe(nil)
		expect(Spacing.steer(me, Vector3.new(0, 3, -20), { neighbor(far) })).toBe(nil)
	end)

	it("steps a standing body out of another, past the gap; half the way when the other steps too", function()
		local boar = body(Vector3.new(0, 3, 0), FORWARD, BOAR_FOOT)
		local me = body(Vector3.new(1.5, 3, 0), FORWARD, KOBOLD_FOOT)
		local before = Spacing.clearance(me, boar, Vector3.xAxis)
		expect(before).toBeLessThan(0)
		local step = Spacing.steer(me, nil, { neighbor(boar) }) :: Vector3
		expect(step).never.toBe(nil)
		local after = Spacing.clearance(body(step, FORWARD, KOBOLD_FOOT), boar, Vector3.xAxis)
		expect(math.abs(after - (GAP + AI.spacing.stepStuds))).toBeLessThan(1e-3)
		local half = Spacing.steer(me, nil, { neighbor(boar, 0.5) }) :: Vector3
		local moved = (step - me.position).Magnitude
		local movedHalf = (half - me.position).Magnitude
		expect(math.abs(movedHalf - ((GAP - before) / 2 + AI.spacing.stepStuds))).toBeLessThan(1e-3)
		expect(movedHalf).toBeLessThan(moved)
	end)

	it("moves a goal inside another body out to its edge", function()
		local boar = body(Vector3.new(0, 3, 0), FORWARD, BOAR_FOOT)
		local me = body(Vector3.new(40, 3, 0), FORWARD, KOBOLD_FOOT)
		local spot = Spacing.steer(me, Vector3.new(0.5, 3, 0), { neighbor(boar) }) :: Vector3
		expect(spot).never.toBe(nil)
		local clear = Spacing.clearance(body(spot, FORWARD, KOBOLD_FOOT), boar, Vector3.xAxis)
		expect(clear).toBeGreaterThanOrEqual(GAP - 1e-3)
		expect(clear).toBeLessThan(GAP + 0.05)
	end)

	it("never walks closer than the gap toward a body between it and its goal, and goes round", function()
		local boar = body(Vector3.new(0, 3, 0), FORWARD, BOAR_FOOT)
		-- The kobold stands at the boar's flank, its goal straight through the boar.
		local start = Vector3.new(KOBOLD_FOOT.radius + BOAR_FOOT.radius + GAP + 0.5, 3, 0)
		local goal = Vector3.new(-20, 3, 0)
		local me = body(start, FORWARD, KOBOLD_FOOT)
		local target = Spacing.steer(me, goal, { neighbor(boar) }) :: Vector3
		expect(target).never.toBe(nil)
		-- The walk this tick turns along the boar (a side step), never into it.
		local walk = target - start
		expect(walk.Magnitude).toBeGreaterThanOrEqual(AI.spacing.slideMinStuds - 1e-3)
		expect(math.abs(walk.X)).toBeLessThan(0.5 + 1e-3)
		local clearAtTarget = Spacing.clearance(body(target, FORWARD, KOBOLD_FOOT), boar, Vector3.xAxis)
		expect(clearAtTarget).toBeGreaterThanOrEqual(GAP - 1e-3)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The whole loop over the real rigs
-- ------------------------------------------------------------------------------------------

type Body = {
	position: Vector3,
	goal: Vector3?,
	walkSpeed: number,
	offsets: { [BasePart]: CFrame },
}

local clock = { t = 6000 }
local bodies: { [Model]: Body } = {}

local function yawOf(model: Model): Vector3
	local align = EnemyService.alignOf(model)
	local look = if align ~= nil then align.CFrame.LookVector else (model.PrimaryPart :: BasePart).CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function placeParts(model: Model, state: Body)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.lookAt(state.position, state.position + yawOf(model))
	for part, offset in state.offsets do
		part.CFrame = root.CFrame * offset
	end
end

local engine = {
	place = function(model: Model, cframe: CFrame)
		local root = model.PrimaryPart :: BasePart
		root.CFrame = CFrame.new()
		local offsets = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= root then
				offsets[part] = root.CFrame:ToObjectSpace(part.CFrame)
			end
		end
		root.CFrame = cframe
		EnemyService.addYawAlign(root, cframe.LookVector)
		local state: Body = { position = cframe.Position, goal = nil, walkSpeed = 16, offsets = offsets }
		bodies[model] = state
		placeParts(model, state)
	end,
	position = function(model: Model): Vector3
		return bodies[model].position
	end,
	facing = function(model: Model): Vector3
		return yawOf(model)
	end,
	setFacing = function(model: Model, facing: Vector3)
		EnemyService.applyFacing(model, facing)
	end,
	moveTo = function(model: Model, position: Vector3)
		bodies[model].goal = position
	end,
	stop = function(model: Model)
		bodies[model].goal = nil
	end,
	setWalkSpeed = function(model: Model, speed: number)
		bodies[model].walkSpeed = speed
	end,
	computePath = function()
		return nil
	end,
	destroy = function(model: Model)
		model.Parent = nil
		bodies[model] = nil
	end,
}

-- Bodies walk straight at their goals at their walk speed and pass through each other.
local function physics(dt: number)
	for model, state in bodies do
		local goal = state.goal
		if goal ~= nil then
			local delta = Vector3.new(goal.X - state.position.X, 0, goal.Z - state.position.Z)
			local reach = state.walkSpeed * dt
			if delta.Magnitude <= reach then
				state.position = Vector3.new(goal.X, state.position.Y, goal.Z)
			else
				state.position += delta.Unit * reach
			end
		end
		placeParts(model, state)
	end
end

local function frame()
	clock.t += FRAME
	physics(FRAME)
	EnemyService.step(FRAME)
	EntityService.tick(FRAME)
end

local function fresh()
	EnemyService.reset()
	EntityService.reset()
	clock.t = 6000
	bodies = {}
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
		combat = {
			setEnemyHitStop = function() end,
			enemyStrike = function()
				return {}
			end,
		},
		rigBuilder = RigBuilder,
		fireAll = function() end,
		engine = engine,
		players = function()
			local list = {}
			for _, player in EntityService.players() do
				if player.state ~= "Dead" then
					table.insert(list, { id = player.id, position = EntityService.positionOf(player.id) })
				end
			end
			return list
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

local playerCount = 0
local function spawnPlayer(position: Vector3): (number, Model)
	playerCount += 1
	local model = Instance.new("Model")
	model.Name = "Spacer" .. playerCount
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position)
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	local player = { Name = model.Name, DisplayName = "Spacer", UserId = 970 + playerCount }
	return EntityService.registerPlayer(player :: any, model, Playground.loadout), model
end

local function teleport(model: Model, position: Vector3)
	local state = bodies[model]
	state.position = position
	state.goal = nil
	placeParts(model, state)
end

-- The flat convex hull of a part's eight corners (its ground shadow), counter-clockwise.
local function shadow(part: BasePart): { Vector3 }
	local half = part.Size / 2
	local points: { Vector3 } = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
				table.insert(points, Vector3.new(corner.X, 0, corner.Z))
			end
		end
	end
	table.sort(points, function(a, b)
		return if a.X == b.X then a.Z < b.Z else a.X < b.X
	end)
	local function cross(o: Vector3, a: Vector3, b: Vector3): number
		return (a.X - o.X) * (b.Z - o.Z) - (a.Z - o.Z) * (b.X - o.X)
	end
	local hull: { Vector3 } = {}
	for _, pass in { 1, -1 } do
		local start = #hull
		local from, to = if pass == 1 then 1 else #points, if pass == 1 then #points else 1
		for index = from, to, pass do
			local point = points[index]
			while #hull >= start + 2 and cross(hull[#hull - 1], hull[#hull], point) <= 0 do
				table.remove(hull)
			end
			table.insert(hull, point)
		end
		table.remove(hull)
	end
	return hull
end

-- How far two convex shadows are apart along their best separating edge normal (negative: the
-- depth they overlap by).
local function separation(a: { Vector3 }, b: { Vector3 }): number
	local best = -math.huge
	for _, polygon in { a, b } do
		for index = 1, #polygon do
			local p, q = polygon[index], polygon[index % #polygon + 1]
			local edge = q - p
			if edge.Magnitude < 1e-9 then
				continue
			end
			local axis = Vector3.new(-edge.Z, 0, edge.X).Unit
			local aMin, aMax, bMin, bMax = math.huge, -math.huge, math.huge, -math.huge
			for _, point in a do
				local d = point:Dot(axis)
				aMin, aMax = math.min(aMin, d), math.max(aMax, d)
			end
			for _, point in b do
				local d = point:Dot(axis)
				bMin, bMax = math.min(bMin, d), math.max(bMax, d)
			end
			best = math.max(best, bMin - aMax, aMin - bMax)
		end
	end
	return best
end

-- The least clear ground between any part of one model and any part of the other (negative: the
-- deepest overlap), over every visible part (the blocker is invisible and only meets players).
local function partsApart(a: Model, b: Model): number
	local least = math.huge
	for _, first in a:GetDescendants() do
		if not first:IsA("BasePart") or first.Transparency >= 1 then
			continue
		end
		local hullA = shadow(first)
		for _, second in b:GetDescendants() do
			if second:IsA("BasePart") and second.Transparency < 1 then
				least = math.min(least, separation(hullA, shadow(second)))
			end
		end
	end
	return least
end

local function phaseOf(id: number): string?
	local brain = EnemyService.brainOf(id)
	return if brain ~= nil then brain:getPhase() else nil
end

describe("EnemyService keeps enemies out of each other (D-259)", function()
	it("a kobold walking home onto the boar that stands there stops at its side, and rests", function()
		fresh()
		-- A player far off keeps both awake (inside the sleep radius, outside every aggro range).
		spawnPlayer(Vector3.new(0, 3, 200))
		local home = Vector3.new(0, 3, 0)
		local koboldId = EnemyService.spawn("KoboldAxeman", CFrame.new(home))
		local kobold = EnemyService.modelOf(koboldId) :: Model
		local boarId = EnemyService.spawn("FrenzyBoar", CFrame.lookAt(Vector3.new(30, 3, 0), Vector3.new(30, 3, -1)))
		local boar = EnemyService.modelOf(boarId) :: Model
		frame()
		-- The boar has come to rest on the kobold's home; the kobold was drawn past its leash.
		teleport(boar, home + Vector3.new(0.5, 0, 0))
		teleport(kobold, Vector3.new(0, 3, Enemies.byId("KoboldAxeman").leashRange + 10))
		local least = math.huge
		local returned = false
		local rested = false
		for _ = 1, 60 * 30 do
			frame()
			least = math.min(least, partsApart(kobold, boar))
			returned = returned or phaseOf(koboldId) == "Return"
			if returned and phaseOf(koboldId) == "Idle" and bodies[kobold].goal == nil then
				rested = true
			end
			if rested then
				break
			end
		end
		for _ = 1, 60 do
			frame()
			least = math.min(least, partsApart(kobold, boar))
		end
		expect(returned).toBe(true)
		expect(least).toBeGreaterThan(0)
		expect(rested).toBe(true)
		expect(phaseOf(koboldId)).toBe("Idle")
	end)

	it("two kobolds spawned on one spot step apart and stay apart", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, 200))
		local a = EnemyService.spawn("KoboldAxeman", CFrame.new(0, 3, 0))
		local b = EnemyService.spawn("KoboldAxeman", CFrame.new(0.4, 3, 0.2))
		local first, second = EnemyService.modelOf(a) :: Model, EnemyService.modelOf(b) :: Model
		expect(partsApart(first, second)).toBeLessThan(0)
		for _ = 1, 60 * 3 do
			frame()
		end
		expect(partsApart(first, second)).toBeGreaterThan(0)
		-- A step out goes just past the gap: they stand apart, they do not scatter.
		local reach = math.max(KOBOLD_FOOT.front, KOBOLD_FOOT.back, KOBOLD_FOOT.radius)
		local most = 2 * reach + GAP + 2 * AI.spacing.stepStuds + 0.1
		expect((bodies[first].position - bodies[second].position).Magnitude).toBeLessThan(most)
		local settled = (bodies[first].position - bodies[second].position).Magnitude
		for _ = 1, 60 * 2 do
			frame()
		end
		-- Settled: no drift once apart.
		expect(math.abs((bodies[first].position - bodies[second].position).Magnitude - settled)).toBeLessThan(1e-3)
	end)

	it("a kobold chasing a player past a boar that stands in its way goes round it", function()
		fresh()
		local playerId = spawnPlayer(Vector3.new(0, 3, -6))
		local koboldId = EnemyService.spawn("KoboldAxeman", CFrame.lookAt(Vector3.new(0, 3, 24), Vector3.new(0, 3, 0)))
		local kobold = EnemyService.modelOf(koboldId) :: Model
		local boarId = EnemyService.spawn("FrenzyBoar", CFrame.lookAt(Vector3.new(0, 3, 10), Vector3.new(1, 3, 10)))
		local boar = EnemyService.modelOf(boarId) :: Model
		-- The boar stands side on across the kobold's line, held (asleep: it never moves).
		EnemyService.setHeld(boarId, true)
		local least = math.huge
		local reached = false
		for _ = 1, 60 * 12 do
			frame()
			least = math.min(least, partsApart(kobold, boar))
			local brain = EnemyService.brainOf(koboldId)
			if brain ~= nil and brain:getPhase() == "WindUp" then
				reached = true
				break
			end
		end
		expect(least).toBeGreaterThan(0)
		-- It still gets to the player and swings.
		expect(reached).toBe(true)
		expect(EntityService.get(playerId)).never.toBe(nil)
	end)

	it("never moves a body mid-attack: a kobold winding up stays planted when a boar lands on it", function()
		fresh()
		spawnPlayer(Vector3.new(0, 3, -3))
		local koboldId = EnemyService.spawn("KoboldAxeman", CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(0, 3, -1)))
		local kobold = EnemyService.modelOf(koboldId) :: Model
		local boarId = EnemyService.spawn("FrenzyBoar", CFrame.new(40, 3, 40))
		EnemyService.setHeld(boarId, true)
		local boar = EnemyService.modelOf(boarId) :: Model
		local guard = 0
		while phaseOf(koboldId) ~= "WindUp" and guard < 600 do
			frame()
			guard += 1
		end
		expect(phaseOf(koboldId)).toBe("WindUp")
		local planted = bodies[kobold].position
		teleport(boar, planted + Vector3.new(1, 0, 0))
		while phaseOf(koboldId) == "WindUp" do
			frame()
			expect((bodies[kobold].position - planted).Magnitude).toBeLessThan(1e-6)
		end
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The numbers (tools/validators/ai.luau)
-- ------------------------------------------------------------------------------------------

describe("the ai validator checks spacing (D-259)", function()
	local luau = require("@lune/luau")
	local root = Harness.repoRoot()

	-- The validator over the real ai table with spacing changed by `change`.
	local function validate(change: (spacing: any) -> ()): { string }
		local real = Harness.load("src/shared/data/ai")
		local copy = table.clone(real)
		copy.spacing = table.clone(real.spacing)
		copy.spacing.freePhases = table.clone(real.spacing.freePhases)
		change(copy.spacing)
		local source = Harness.readFile("tools/validators/ai.luau")
		local validator = luau.load(source, {
			debugName = "tools/validators/ai",
			environment = { print = function() end } :: any,
		})()
		return validator({
			load = function(path: string): any
				if path == "src/shared/data/ai" then
					return copy
				end
				return Harness.load(path)
			end,
			listFiles = Harness.listFiles,
			readFile = Harness.readFile,
			repoRoot = root,
		})
	end

	local function names(problems: { string }, needle: string): boolean
		for _, problem in problems do
			if problem:find(needle, 1, true) then
				return true
			end
		end
		return false
	end

	it("passes the real table", function()
		expect(validate(function() end)).toEqual({})
	end)

	it("every distance and the shuffle's speed are positive, the shuffle no faster than a walk", function()
		expect(names(
			validate(function(spacing)
				spacing.gapStuds = 0
			end),
			"spacing.gapStuds must be positive"
		)).toBe(true)
		expect(names(
			validate(function(spacing)
				spacing.stepSpeedMultiplier = 1.5
			end),
			"spacing.stepSpeedMultiplier must be at most 1"
		)).toBe(true)
		expect(names(
			validate(function(spacing)
				spacing.standOffPasses = 0.5
			end),
			"spacing.standOffPasses must be a whole number of at least 1"
		)).toBe(true)
		expect(names(
			validate(function(spacing)
				spacing.slideMinStuds = AI.movement.moveAheadStuds + 1
			end),
			"spacing.slideMinStuds must be at most movement.moveAheadStuds"
		)).toBe(true)
	end)

	it("never moves a body mid-attack, staggered or dead", function()
		for _, busy in { "WindUp", "Strike", "Recover", "Interrupted", "Dead" } do
			expect(names(
				validate(function(spacing)
					spacing.freePhases[busy] = true
				end),
				"spacing.freePhases must not hold " .. busy
			)).toBe(true)
		end
	end)
end)
