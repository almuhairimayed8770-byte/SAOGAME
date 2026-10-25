--!strict
--[[
	The capture's staging (src/server/dev/DevStage.server.luau, F12), loaded the way Studio runs it:
	a fresh copy of the Script with a fake EnemyService (spawn, despawn, the hold, brains whose
	phase a test sets), a fake EntityService (heal, setHp, fromPlayer), a fake RunService and
	Workspace for the gate, and a fake clock behind task.wait and os.clock. The RemoteFunction it
	makes is called the way the client's InvokeServer arrives.

	The staging never moves the player (D-244): it requires no anti-cheat, never pivots the
	player's character, and stages only around a root that already stands in the shot's ring;
	outside it the reply asks for a walk there.
]]

local luau = require("@lune/luau")

local Dev = Harness.load("src/shared/data/dev")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local Enemies = Harness.load("src/shared/data/enemies")
local StageLogic = Harness.load("src/server/dev/DevStageLogic")

local NODE = "src/server/dev/DevStage"
local FILE = "src/server/dev/DevStage.server.luau"
local FRAME = 1 / 60
local CAPTURE = Dev.capture
local STAGE = CAPTURE.stage
local HIP = 2 -- the player's Humanoid.HipHeight in this world
local ROOT_SIZE = Vector3.new(2, 2, 1)

local function shotById(id: string): any
	for _, shot in CAPTURE.shots do
		if shot.id == id then
			return shot
		end
	end
	error("no shot " .. id)
end

type Model = {
	PrimaryPart: any,
	Parent: any,
	PivotTo: (self: Model, cframe: CFrame) -> (),
	GetPivot: (self: Model) -> CFrame,
	FindFirstChildOfClass: (self: Model, className: string) -> any,
}

local function model(cframe: CFrame): any
	local m: any = nil
	m = {
		PrimaryPart = {
			Position = cframe.Position,
			CFrame = cframe,
			Size = ROOT_SIZE,
			AssemblyLinearVelocity = Vector3.one,
		},
		Parent = { Name = "Workspace" },
		PivotTo = function(self: any, frame: CFrame)
			self.PrimaryPart.CFrame = frame
			self.PrimaryPart.Position = frame.Position
		end,
		GetPivot = function(self: any): CFrame
			return self.PrimaryPart.CFrame
		end,
		FindFirstChildOfClass = function(_self: any, className: string): any
			return if className == "Humanoid" then { HipHeight = HIP } else nil
		end,
	}
	return m
end

type Enemy = { id: number, defId: string, model: any, phase: string, held: boolean, hp: number, maxHp: number }

type World = {
	clock: { now: number },
	created: { any },
	required: { [string]: boolean },
	enemies: { [number]: Enemy },
	order: { { kind: string, id: number?, seconds: number? } },
	player: any,
	record: any,
	holdNew: { on: boolean },
	remote: () -> any,
	invoke: (action: any, shotId: any) -> any,
	-- Stands the player's root with its feet at (x, feetY, z), facing `facing` (the test's move,
	-- not the server's).
	standAt: (x: number, feetY: number, z: number, facing: number) -> (),
	addEnemy: (defId: string, position: Vector3, phase: string?) -> number,
	advance: (seconds: number) -> (),
	ledge: () -> any,
	ramp: () -> any,
	-- Called once a frame while the script waits (task.wait): a test moves a brain's phase on.
	onWait: ((now: number) -> ())?,
}

type Options = { studio: boolean?, capture: any }

local function load(options: Options): World
	local world: World = nil :: any
	local clock = { now = 100 }
	local nextId = 10
	local enemies: { [number]: Enemy } = {}
	local order: { { kind: string, id: number?, seconds: number? } } = {}
	local holdNew = { on = false }
	local player = { Name = "Player1", UserId = 1 }
	local area = STAGE.area
	local record = {
		id = 1,
		kind = "Player",
		state = "Idle",
		hp = 40,
		maxHp = 100,
		player = player,
		-- Standing on the stage area's spot, facing its way, until a test stands it elsewhere.
		model = model(
			CFrame.new(
				area.position[1],
				area.position[2] + HIP + ROOT_SIZE.Y / 2 + World.spawn.groundEpsilon,
				area.position[3]
			) * CFrame.Angles(0, math.rad(area.facing), 0)
		),
	}
	-- The server never moves the player (D-244): a pivot is recorded, and still applied.
	local pivotTo = record.model.PivotTo
	record.model.PivotTo = function(self: any, frame: CFrame)
		table.insert(order, { kind = "pivotPlayer" })
		pivotTo(self, frame)
	end
	local function living(id: number): Enemy?
		local enemy = enemies[id]
		return if enemy ~= nil and enemy.phase ~= "Dead" then enemy else nil
	end
	local enemyService = {
		ids = function(): { number }
			local ids = {}
			for id in enemies do
				table.insert(ids, id)
			end
			table.sort(ids)
			return ids
		end,
		isHeld = function(id: number): boolean
			local enemy = living(id)
			return enemy ~= nil and enemy.held
		end,
		setHeld = function(id: number, on: boolean): boolean
			local enemy = living(id)
			if enemy == nil then
				return false
			end
			if on and (enemy.phase == "WindUp" or enemy.phase == "Strike") then
				-- What the real hold does mid-attack: the attack is cancelled (the phantom rush).
				table.insert(order, { kind = "heldMidAttack", id = id })
			end
			enemy.held = on
			table.insert(order, { kind = if on then "hold" else "release", id = id })
			return true
		end,
		heldIds = function(): { number }
			local ids = {}
			for id, enemy in enemies do
				if enemy.held then
					table.insert(ids, id)
				end
			end
			table.sort(ids)
			return ids
		end,
		holdsNew = function(): boolean
			return holdNew.on
		end,
		setHoldNew = function(on: boolean)
			holdNew.on = on
		end,
		brainOf = function(id: number): any
			local enemy = enemies[id]
			if enemy == nil then
				return nil
			end
			return {
				getPhase = function(_self: any): string
					return enemy.phase
				end,
			}
		end,
		modelOf = function(id: number): any
			local enemy = enemies[id]
			return if enemy ~= nil then enemy.model else nil
		end,
		spawn = function(defId: string, cframe: CFrame): number
			nextId += 1
			local def = Enemies.byId(defId)
			enemies[nextId] = {
				id = nextId,
				defId = defId,
				model = model(cframe),
				phase = "Idle",
				held = holdNew.on,
				hp = def.hp,
				maxHp = def.hp,
			}
			table.insert(order, { kind = "spawn", id = nextId })
			return nextId
		end,
		despawn = function(id: number)
			enemies[id] = nil
			table.insert(order, { kind = "despawn", id = id })
		end,
	}
	local entityService = {
		fromPlayer = function(who: any): any
			return if who == player then record else nil
		end,
		heal = function(id: number, amount: number)
			if id == record.id and amount > 0 then
				record.hp = math.min(record.maxHp, record.hp + amount)
				table.insert(order, { kind = "heal", id = id })
			end
		end,
		setHp = function(id: number, hp: number): number?
			local enemy = living(id)
			if enemy == nil then
				return nil
			end
			enemy.hp = math.clamp(hp, 1, enemy.maxHp)
			return enemy.hp
		end,
	}
	local playerRemoving = { Connect = function() end }
	local replicated = Harness.game():GetService("ReplicatedStorage")
	local created: { any } = {}
	local services: { [string]: any } = {
		Players = { PlayerRemoving = playerRemoving },
		RunService = {
			IsStudio = function(): boolean
				return options.studio == true
			end,
		},
		ReplicatedStorage = replicated,
	}
	local fakes: { [string]: any } = {
		EnemyService = enemyService,
		EntityService = entityService,
	}
	local required: { [string]: boolean } = {}
	local attributes: { [string]: any } = { [Dev.attributes.capture] = options.capture }
	local workspaceFake = {
		GetAttribute = function(_self: any, name: string): any
			return attributes[name]
		end,
	}
	local env = Harness.environment()
	env.script = Harness.node(NODE)
	env.require = function(node: any): any
		required[node.Name] = true
		return fakes[node.Name] or Harness.loadModule(node)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name] or error("no service " .. name)
		end,
	}
	env.workspace = workspaceFake
	env.Instance = {
		new = function(className: string): any
			local instance = { ClassName = className }
			table.insert(created, instance)
			return instance
		end,
	}
	env.task = {
		wait = function(seconds: number?): number
			local dt = if seconds ~= nil and seconds > 0 then seconds else FRAME
			clock.now += dt
			if world.onWait ~= nil then
				(world.onWait :: (number) -> ())(clock.now)
			end
			return dt
		end,
	}
	env.os = {
		clock = function(): number
			return clock.now
		end,
	}

	world = {
		clock = clock,
		created = created,
		required = required,
		enemies = enemies,
		order = order,
		player = player,
		record = record,
		holdNew = holdNew,
		remote = function(): any
			for _, instance in created do
				if instance.ClassName == "RemoteFunction" then
					return instance
				end
			end
			return nil
		end,
		invoke = function(action: any, shotId: any): any
			-- Requests come no faster than the rate limit unless a test says otherwise.
			clock.now += 1 / STAGE.requestsPerSecond
			return world.remote().OnServerInvoke(player, action, shotId)
		end,
		standAt = function(x: number, feetY: number, z: number, facing: number)
			local root = record.model.PrimaryPart
			root.CFrame = CFrame.new(x, feetY + HIP + ROOT_SIZE.Y / 2 + World.spawn.groundEpsilon, z)
				* CFrame.Angles(0, math.rad(facing), 0)
			root.Position = root.CFrame.Position
		end,
		addEnemy = function(defId: string, position: Vector3, phase: string?): number
			local id = enemyService.spawn(defId, CFrame.new(position))
			enemies[id].held = false
			enemies[id].phase = phase or "Idle"
			table.clear(order)
			return id
		end,
		advance = function(seconds: number)
			clock.now += seconds
		end,
		ledge = function(): any
			for _, instance in created do
				if instance.ClassName == "Part" and instance.Name == STAGE.ledge.name then
					return instance
				end
			end
			return nil
		end,
		ramp = function(): any
			for _, instance in created do
				if instance.ClassName == "WedgePart" and instance.Name == STAGE.ledge.ramp.name then
					return instance
				end
			end
			return nil
		end,
		onWait = nil,
	}
	luau.load(Harness.readFile(FILE), { debugName = FILE, environment = env :: any })()
	return world
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function indexOf(order: { any }, kind: string, id: number?): number?
	for index, entry in order do
		if entry.kind == kind and (id == nil or entry.id == id) then
			return index
		end
	end
	return nil
end

local function rootHeight(defId: string): number
	local rig = Rigs[Enemies.byId(defId).skin]
	return rig.hipHeight + rig.parts[rig.rootPart].size[2] / 2 + World.spawn.groundEpsilon
end

-- ------------------------------------------------------------------ the gate

describe("DevStage: the gate (Studio with DevCapture only)", function()
	it("makes nothing and requires no service outside Studio, or in a place without DevCapture", function()
		for _, options in { { studio = false, capture = true }, { studio = true, capture = nil } } do
			local world = load(options :: any)
			expect(#world.created).toBe(0)
			expect(world.required.EnemyService).toBeNil()
			expect(world.required.EntityService).toBeNil()
		end
	end)

	it("never moves the player: no anti-cheat required, no serverMoved, no move of any player (D-244)", function()
		local source = Harness.readFile(FILE)
		expect(source:find("serverMoved", 1, true)).toBeNil()
		expect(source:find("AntiCheatService", 1, true)).toBeNil()
		local world = load({ studio = true, capture = true })
		world.invoke("stage", "art-horizontal")
		world.invoke("stage", "locomotion")
		world.standAt(30, 0, 30, 90)
		world.invoke("stage", "kill-shatter")
		expect(world.required.AntiCheatService).toBeNil()
		expect(indexOf(world.order, "pivotPlayer")).toBeNil()
	end)

	it("makes its RemoteFunction under ReplicatedStorage in Studio with DevCapture", function()
		local world = load({ studio = true, capture = true })
		local remote = world.remote()
		expect(remote ~= nil).toBe(true)
		expect(remote.Name).toBe(STAGE.remoteName)
		expect(remote.Parent.Name).toBe("ReplicatedStorage")
		expect(remote.OnServerInvoke).never.toBeNil()
	end)
end)

-- ------------------------------------------------------------------ staging

describe("DevStage: a shot stages itself (F12)", function()
	it(
		"stages around where the player stands and faces in the ring: healed, its enemy in front, never moved",
		function()
			local world = load({ studio = true, capture = true })
			local shot = shotById("art-horizontal")
			local area = STAGE.area
			-- Inside the ring but off its centre, turned off the area's facing.
			local standX, standZ, facing = area.position[1] + 1.2, area.position[3] - 0.9, area.facing + 30
			world.standAt(standX, area.position[2], standZ, facing)
			local root = world.record.model.PrimaryPart
			local before = root.CFrame
			local reply = world.invoke("stage", shot.id)
			expect(reply.ok).toBe(true)
			expect(reply.shot).toBe(shot.id)
			-- The player: where it stood, as it faced, its velocity untouched; only healed.
			expect(root.CFrame).toBe(before)
			expect(root.AssemblyLinearVelocity).toBe(Vector3.one)
			expect(indexOf(world.order, "pivotPlayer")).toBeNil()
			expect(world.record.hp).toBe(world.record.maxHp)
			-- The target: the shot's first enemy, its distance out ahead of the actual facing, facing
			-- the player, on the field, held.
			local entry = shot.stage.enemies[1]
			local target = world.enemies[reply.targetId]
			expect(target.defId).toBe(entry.enemy)
			local offset = target.model.PrimaryPart.Position - root.Position
			expect(flat(offset).Magnitude).toBeCloseTo(entry.distance, 1e-6)
			local look = CFrame.Angles(0, math.rad(facing), 0).LookVector
			expect(flat(offset).Unit:Dot(look)).toBeGreaterThan(0.9999)
			expect(target.model.PrimaryPart.CFrame.LookVector:Dot(-flat(offset).Unit)).toBeGreaterThan(0.9999)
			expect(target.model.PrimaryPart.Position.Y).toBeCloseTo(area.position[2] + rootHeight(entry.enemy), 1e-6)
			expect(target.held).toBe(true)
		end
	)

	it("asks a player outside the ring to walk into it, with the ring and a route, and spawns nothing", function()
		local world = load({ studio = true, capture = true })
		local area = STAGE.area
		local near = world.addEnemy("FrenzyBoar", Vector3.new(area.position[1] - 12, 2, area.position[3]))
		world.standAt(30, 0, 30, 90)
		local root = world.record.model.PrimaryPart
		local before = root.CFrame
		local reply = world.invoke("stage", "art-horizontal")
		expect(reply.ok).toBe(false)
		expect(reply.error).toBe("walk into the ring first")
		local walk = reply.walk
		local x, y, z, facing = StageLogic.standSpot(false, area, STAGE.ledge)
		expect(walk.x).toBe(x)
		expect(walk.y).toBe(y)
		expect(walk.z).toBe(z)
		expect(walk.facing).toBe(facing)
		expect(walk.radius).toBe(STAGE.standRadius)
		expect(walk.tolerance).toBe(STAGE.standHeightTolerance)
		expect(walk.over).toBeNil()
		-- The route ends with the approach along the facing, then the spot.
		local path = walk.path
		expect(path[#path][1]).toBe(x)
		expect(path[#path][2]).toBe(z)
		expect(path).toEqual(StageLogic.route(false, STAGE, false, 30, 30))
		-- Nothing spawned, the player neither moved nor healed; the field is held and cleared.
		expect(indexOf(world.order, "spawn")).toBeNil()
		expect(indexOf(world.order, "pivotPlayer")).toBeNil()
		expect(root.CFrame).toBe(before)
		expect(world.record.hp).toBe(40)
		expect(world.enemies[near].held).toBe(true)
		expect(flat(world.enemies[near].model.PrimaryPart.Position - Vector3.new(x, 0, z)).Magnitude).toBeCloseTo(
			STAGE.awayStuds,
			1e-6
		)
		expect(reply.moved).toBe(1)
		-- Once it stands in the ring the shot stages.
		world.standAt(x + 0.5, y, z - 0.5, facing)
		expect(world.invoke("stage", "art-horizontal").ok).toBe(true)
	end)

	it("asks for the walk when the feet stand off the spot's floor, even over the spot", function()
		local world = load({ studio = true, capture = true })
		local area = STAGE.area
		world.standAt(area.position[1], area.position[2] + STAGE.standHeightTolerance + 0.5, area.position[3], 0)
		local reply = world.invoke("stage", "art-vertical")
		expect(reply.ok).toBe(false)
		expect(reply.walk ~= nil).toBe(true)
		expect(indexOf(world.order, "spawn")).toBeNil()
	end)

	it("holds every field enemy, and moves the near ones out past the lock's range", function()
		local world = load({ studio = true, capture = true })
		local area = STAGE.area
		local near = world.addEnemy("FrenzyBoar", Vector3.new(area.position[1] + 10, 2, area.position[3]))
		local far = world.addEnemy("KoboldAxeman", Vector3.new(150, 2, 0))
		local reply = world.invoke("stage", "art-vertical")
		expect(reply.ok).toBe(true)
		expect(world.enemies[near].held).toBe(true)
		expect(world.enemies[far].held).toBe(true)
		expect(world.holdNew.on).toBe(true)
		local spot = Vector3.new(area.position[1], 0, area.position[3])
		expect(flat(world.enemies[near].model.PrimaryPart.Position - spot).Magnitude).toBeCloseTo(STAGE.awayStuds, 1e-6)
		expect(world.enemies[near].model.PrimaryPart.Position.Y).toBe(2)
		expect(world.enemies[far].model.PrimaryPart.Position).toBe(Vector3.new(150, 2, 0))
		expect(reply.moved).toBe(1)
		expect(STAGE.awayStuds).toBeGreaterThan(Harness.load("src/shared/data/camera").lock.range)
	end)

	it("waits out a wind-up before it holds (never a hold mid-attack, the phantom rush)", function()
		local world = load({ studio = true, capture = true })
		local boar = world.addEnemy("FrenzyBoar", Vector3.new(120, 2, 0), "WindUp")
		local started = world.clock.now
		world.onWait = function(now: number)
			-- The crouch ends into the rush, then the recovery.
			if now - started > 0.6 + 0.5 then
				world.enemies[boar].phase = "Recover"
			elseif now - started > 0.6 then
				world.enemies[boar].phase = "Strike"
			end
		end
		local reply = world.invoke("stage", "art-horizontal")
		expect(reply.ok).toBe(true)
		expect(world.enemies[boar].held).toBe(true)
		expect(indexOf(world.order, "heldMidAttack")).toBeNil()
	end)

	it("fails, holding nobody mid-attack, when an attack outlasts the wait", function()
		local world = load({ studio = true, capture = true })
		local boar = world.addEnemy("FrenzyBoar", Vector3.new(120, 2, 0), "WindUp")
		local reply = world.invoke("stage", "art-horizontal")
		expect(reply.ok).toBe(false)
		expect(reply.error:find(tostring(boar), 1, true)).never.toBeNil()
		expect(world.enemies[boar].held).toBe(false)
		expect(indexOf(world.order, "heldMidAttack")).toBeNil()
		-- Nothing was spawned, and the player was not moved.
		expect(indexOf(world.order, "pivotPlayer")).toBeNil()
		expect(indexOf(world.order, "spawn")).toBeNil()
	end)

	it("lets go only the staged enemies the shot releases, when the take starts", function()
		local world = load({ studio = true, capture = true })
		local fight = shotById("fight-boar-kobold")
		local reply = world.invoke("stage", fight.id)
		expect(reply.ok).toBe(true)
		expect(#reply.ids).toBe(#fight.stage.enemies)
		for _, id in reply.ids do
			expect(world.enemies[id].held).toBe(true)
		end
		local go = world.invoke("go")
		expect(go.ok).toBe(true)
		for index, id in reply.ids do
			expect(world.enemies[id].held).toBe(fight.stage.enemies[index].held)
		end
		-- An Art's target stays held through the take.
		local art = world.invoke("stage", "art-sharp-nail")
		world.invoke("go")
		expect(world.enemies[art.targetId].held).toBe(true)
	end)

	it("removes the last staging's enemies when the next shot stages", function()
		local world = load({ studio = true, capture = true })
		local first = world.invoke("stage", "parry-spark")
		local second = world.invoke("stage", "enemy-boar-charge")
		expect(second.ok).toBe(true)
		expect(world.enemies[first.targetId]).toBeNil()
		expect(world.enemies[second.targetId]).never.toBeNil()
	end)

	it("sets the kill shot's target to its HP", function()
		local world = load({ studio = true, capture = true })
		local shot = shotById("kill-shatter")
		local reply = world.invoke("stage", shot.id)
		expect(world.enemies[reply.targetId].hp).toBe(shot.stage.enemies[1].hp)
	end)

	it("builds the ledge and its ramp once for the open shot, and asks a player on the field to walk up", function()
		local world = load({ studio = true, capture = true })
		local reply = world.invoke("stage", "locomotion")
		expect(reply.ok).toBe(false)
		expect(reply.error).toBe("walk into the ring first")
		local data = STAGE.ledge
		local ledge = world.ledge()
		expect(ledge).never.toBeNil()
		expect(ledge.Anchored).toBe(true)
		expect(ledge.Size).toBe(Vector3.new(data.size[1], data.size[2], data.size[3]))
		expect(ledge.CFrame.Position).toBe(Vector3.new(data.position[1], data.position[2], data.position[3]))
		-- The ramp: an anchored wedge, its tall back face (+Z) against the ledge's +Z face across the
		-- ledge's whole height, sloping down along +Z, all of it behind the ledge (off the run).
		local ramp = world.ramp()
		expect(ramp).never.toBeNil()
		local size = data.ramp.size
		expect(ramp.Anchored).toBe(true)
		expect(ramp.Size).toBe(Vector3.new(size[1], size[2], size[3]))
		local edge = data.position[3] + data.size[3] / 2
		local back = ramp.CFrame:PointToWorldSpace(Vector3.new(0, 0, size[3] / 2))
		expect(back.Z).toBeCloseTo(edge, 1e-6)
		expect(back.X).toBeCloseTo(data.position[1], 1e-6)
		expect(back.Y).toBeCloseTo(data.position[2], 1e-6)
		local front = ramp.CFrame:PointToWorldSpace(Vector3.new(0, 0, -size[3] / 2))
		expect(front.Z).toBeCloseTo(edge + size[3], 1e-6)
		expect(ramp.CFrame.UpVector:Dot(Vector3.yAxis)).toBeCloseTo(1, 1e-6)
		-- The walk: the ring on the ledge's top, over it, and a route up the ramp to the spot.
		local walk = reply.walk
		local x, y, z, facing = StageLogic.standSpot(true, STAGE.area, data)
		expect(walk.x).toBe(x)
		expect(walk.y).toBe(y)
		expect(walk.z).toBe(z)
		expect(walk.facing).toBe(facing)
		expect(walk.over).toEqual({
			data.position[1] - data.size[1] / 2,
			data.position[1] + data.size[1] / 2,
			data.position[3] - data.size[3] / 2,
			edge,
		})
		local area = STAGE.area
		expect(walk.path).toEqual(StageLogic.route(true, STAGE, true, area.position[1], area.position[3]))
		expect(indexOf(world.order, "spawn")).toBeNil()
		-- Up on the ledge's top in the ring: the shot stages, the kobold on the field.
		world.standAt(x, y, z, facing)
		local staged = world.invoke("stage", "locomotion")
		expect(staged.ok).toBe(true)
		local kobold = world.enemies[staged.targetId].model.PrimaryPart.Position
		expect(kobold.Y).toBeCloseTo(STAGE.area.position[2] + rootHeight("KoboldAxeman"), 1e-6)
		expect(indexOf(world.order, "pivotPlayer")).toBeNil()
		-- Staged again: still one ledge and one ramp.
		world.invoke("stage", "locomotion")
		local parts, wedges = 0, 0
		for _, instance in world.created do
			if instance.ClassName == "Part" then
				parts += 1
			elseif instance.ClassName == "WedgePart" then
				wedges += 1
			end
		end
		expect(parts).toBe(1)
		expect(wedges).toBe(1)
	end)

	it("asks for the walk unless the feet stand up on the ledge's top, inside the ring", function()
		local world = load({ studio = true, capture = true })
		local data = STAGE.ledge
		local x, y, z = StageLogic.standSpot(true, STAGE.area, data)
		-- Over the spot but at the field's height (the height check).
		world.standAt(x, STAGE.area.position[2], z, 0)
		expect(world.invoke("stage", "locomotion").walk ~= nil).toBe(true)
		-- On the ramp just past the ledge's +Z edge: inside the ring's radius and near the top's
		-- height, but not over the ledge's top.
		local edge = data.position[3] + data.size[3] / 2
		local past = edge + (STAGE.standRadius - data.standInset) / 2
		local rise = data.ramp.size[2] / data.ramp.size[3]
		world.standAt(x, y - (past - edge) * rise, past, 0)
		expect(world.invoke("stage", "locomotion").walk ~= nil).toBe(true)
		expect(indexOf(world.order, "spawn")).toBeNil()
		-- On the top inside the ring: staged.
		world.standAt(x, y, edge - 0.25, 0)
		expect(world.invoke("stage", "locomotion").ok).toBe(true)
	end)

	it("gives the field back on release: staged enemies gone, its holds let go, hold-new as it was", function()
		local world = load({ studio = true, capture = true })
		local alreadyHeld = world.addEnemy("KoboldAxeman", Vector3.new(-150, 2, 0))
		world.enemies[alreadyHeld].held = true
		local field = world.addEnemy("FrenzyBoar", Vector3.new(150, 2, 0))
		local reply = world.invoke("stage", "art-horizontal")
		expect(world.enemies[field].held).toBe(true)
		local done = world.invoke("release")
		expect(done.ok).toBe(true)
		expect(world.enemies[reply.targetId]).toBeNil()
		expect(world.enemies[field].held).toBe(false)
		-- Held before the staging (the dev hook, a cutscene): left held.
		expect(world.enemies[alreadyHeld].held).toBe(true)
		expect(world.holdNew.on).toBe(false)
	end)

	it("refuses an unknown shot or action, a dead player, and requests faster than the rate", function()
		local world = load({ studio = true, capture = true })
		expect(world.invoke("stage", "no-such-shot").ok).toBe(false)
		expect(world.invoke("dance").ok).toBe(false)
		expect(world.invoke(42).ok).toBe(false)
		-- Two at once: the second is refused.
		local remote = world.remote()
		world.advance(1)
		expect(remote.OnServerInvoke(world.player, "go").ok).toBe(true)
		expect(remote.OnServerInvoke(world.player, "go").ok).toBe(false)
		world.record.state = "Dead"
		expect(world.invoke("stage", "art-horizontal").ok).toBe(false)
	end)
end)
