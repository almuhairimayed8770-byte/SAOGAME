--!strict
--[[
	PlaygroundService under Lune: the real EntityService (fake clock, net, tags) and WeaponBuilder, a
	fake EnemyService that records spawn CFrames and owns a real Despawned Signal, no world build.
	Character setup (scale values, walk speed, weapon, registration), the spawn tables, respawns on
	the service clock, spawn spacing (D-170), and the kill-volume scan.
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

local PlaygroundService = Harness.load("src/server/services/PlaygroundService")
local EntityService = Harness.load("src/server/services/EntityService")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local Signal = Harness.load("src/shared/util/Signal")
local Playground = Harness.load("src/shared/data/playground")
local Rigs = Harness.load("src/shared/data/rigs")
local Enemies = Harness.load("src/shared/data/enemies")
local Choreo = Harness.load("src/shared/data/choreo")
local World = Harness.load("src/shared/data/world")
local CollectionService = Harness.game():GetService("CollectionService")

-- ------------------------------------------------------------------------------------------
-- Fixtures
-- ------------------------------------------------------------------------------------------

local clock = { t = 1000 }
local spawns: { any } = {}
local nextEnemyId = 100
local fakeEnemies: any = nil
local built = 0

local function fresh(overrides: { [string]: any }?)
	PlaygroundService.reset()
	EntityService.reset()
	clock.t = 1000
	spawns = {}
	nextEnemyId = 100
	built = 0
	EntityService.bind({
		now = function()
			return clock.t
		end,
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
	fakeEnemies = {
		Despawned = Signal.new(),
		spawn = function(defId, cframe, options)
			nextEnemyId += 1
			local def = Enemies.scaled(Enemies.byId(defId))
			local model = RigBuilder.build(def.skin, def.name)
			local root = model.PrimaryPart
			-- Place the rig's root at the requested CFrame (what the engine's PivotTo does).
			root.CFrame = cframe
			local id = EntityService.registerEnemy(model, def)
			table.insert(spawns, { id = id, defId = defId, cframe = cframe, options = options, model = model })
			return id
		end,
	}
	local deps: { [string]: any } = {
		now = function()
			return clock.t
		end,
		entities = EntityService,
		enemies = fakeEnemies,
		weaponBuilder = WeaponBuilder,
		build = function()
			built += 1
			return { partCount = 0 }
		end,
		players = nil,
		heartbeat = nil,
		waitForChild = function(parent, name)
			return parent:FindFirstChild(name)
		end,
		random = Random.new(21),
	}
	if overrides ~= nil then
		for key, value in overrides do
			deps[key] = value
		end
	end
	PlaygroundService.bind(deps :: any)
end

local function character(name: string?): (any, any, any)
	local model = Instance.new("Model")
	model.Name = name or "Tester"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = model
	model.PrimaryPart = root
	local hand = Instance.new("Part")
	hand.Name = "RightHand"
	hand.Size = Vector3.new(1, 0.4, 1)
	hand.CFrame = CFrame.new(1.5, 1.2, 0)
	hand.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	local parent = Instance.new("Folder")
	model.Parent = parent
	return model, humanoid, hand
end

local function player(name: string): any
	return { Name = name, DisplayName = name, UserId = 7 }
end

local function advance(seconds: number, step: number?)
	local dt = step or 1 / 60
	local remaining = seconds
	while remaining > 1e-9 do
		local slice = math.min(dt, remaining)
		clock.t += slice
		PlaygroundService.tick(slice)
		remaining -= slice
	end
end

-- ------------------------------------------------------------------------------------------
-- Characters
-- ------------------------------------------------------------------------------------------

describe("PlaygroundService.onCharacter", function()
	it("writes the anime proportions into the Humanoid scale values, creating missing ones", function()
		fresh()
		local model, humanoid = character()
		local existing = Instance.new("NumberValue")
		existing.Name = "HeadScale"
		existing.Value = 1
		existing.Parent = humanoid
		PlaygroundService.onCharacter(player("Tester"), model)
		local scale = Rigs.PlayerR15.scale
		local names = World.character.scaleValues
		expect(humanoid:FindFirstChild(names.bodyHeight).Value).toBeCloseTo(scale.bodyHeight, 1e-6)
		expect(humanoid:FindFirstChild(names.bodyWidth).Value).toBeCloseTo(scale.bodyWidth, 1e-6)
		expect(humanoid:FindFirstChild(names.bodyDepth).Value).toBeCloseTo(scale.bodyDepth, 1e-6)
		expect(humanoid:FindFirstChild(names.head)).toBe(existing)
		expect(existing.Value).toBeCloseTo(scale.head, 1e-6)
		local count = 0
		for _, child in humanoid:GetChildren() do
			if child:IsA("NumberValue") then
				count += 1
			end
		end
		expect(count).toBe(4)
	end)

	it("sets the baseline walk speed from choreo.luau", function()
		fresh()
		local model, humanoid = character()
		PlaygroundService.onCharacter(player("Tester"), model)
		expect(humanoid.WalkSpeed).toBeCloseTo(Choreo.locomotion.runSpeed, 1e-5)
		expect(PlaygroundService.walkSpeed()).toBe(Choreo.locomotion.runSpeed)
	end)

	it("equips the loadout weapon on the right hand and registers the fighter with the loadout", function()
		fresh()
		local model, _, hand = character()
		local ready = nil
		PlaygroundService.PlayerReady:Connect(function(_player, _character, id)
			ready = id
		end)
		local id = PlaygroundService.onCharacter(player("Tester"), model)
		task.wait()
		expect(id).toBeTruthy()
		expect(ready).toBe(id)
		local weapon = model:FindFirstChild("Weapon")
		expect(weapon).toBeTruthy()
		expect(weapon:IsA("Model")).toBe(true)
		expect(weapon.PrimaryPart:FindFirstChild("Weapon").Part0).toBe(hand)
		expect(model:GetAttribute("WeaponId")).toBe(Playground.loadout.weapon)
		local record = EntityService.get(id)
		expect(record.kind).toBe("Player")
		expect(record.weaponId).toBe("TrialistSword")
		expect(record.proficiency.OneHandedSword).toBe(Playground.loadout.proficiency.OneHandedSword)
		expect(model:GetAttribute("EntityId")).toBe(id)
		expect(model:GetAttribute("ArtSlots")).toBe(table.concat(Playground.loadout.artSlots, ","))
		expect(CollectionService:HasTag(model, "SkyspirePlayer")).toBe(true)
	end)

	it("waits for the engine to finish the character before it scales, arms and registers it", function()
		-- What the engine does after CharacterAdded (D-046): parents the character, applies the
		-- avatar's appearance (its own scale values, a new RightHand), then builds the rig.
		local finishedHand: any = nil
		local waited = 0
		fresh({
			characterReady = function(_player, model: any, timeout: number): boolean
				waited += 1
				expect(timeout).toBe(World.character.partWaitSeconds)
				expect(model:GetAttribute("WeaponId")).toBeNil() -- nothing written before it is ready
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				for _, name in World.character.scaleValues do
					local value = Instance.new("NumberValue")
					value.Name = name
					value.Value = 1 -- the avatar's own proportions
					value.Parent = humanoid
				end
				model:FindFirstChild("RightHand"):Destroy()
				finishedHand = Instance.new("Part")
				finishedHand.Name = "RightHand"
				finishedHand.Size = Vector3.new(1, 0.4, 1)
				finishedHand.CFrame = CFrame.new(1.5, 1.2, 0)
				finishedHand.Parent = model
				model.Parent = Instance.new("Folder")
				return true
			end,
		})
		local model, humanoid = character()
		model.Parent = nil -- CharacterAdded fires before the engine parents the character
		local id = PlaygroundService.onCharacter(player("Tester"), model)
		expect(waited).toBe(1)
		expect(id).toBeTruthy()
		expect(EntityService.get(id).model).toBe(model)
		local names = World.character.scaleValues
		expect(humanoid:FindFirstChild(names.bodyHeight).Value).toBeCloseTo(Rigs.PlayerR15.scale.bodyHeight, 1e-6)
		expect(humanoid:FindFirstChild(names.head).Value).toBeCloseTo(Rigs.PlayerR15.scale.head, 1e-6)
		local weapon = model:FindFirstChild("Weapon")
		expect(weapon).toBeTruthy()
		expect(weapon.PrimaryPart:FindFirstChild("Weapon").Part0).toBe(finishedHand)
		expect(model:GetAttribute("Rig")).toBe(Rigs.PlayerR15.id)
	end)

	it("leaves a character the engine never finished untouched and unregistered", function()
		fresh({
			characterReady = function(): boolean
				return false
			end,
		})
		local model, humanoid = character("Respawned")
		expect(PlaygroundService.onCharacter(player("Respawned"), model)).toBeNil()
		expect(model:FindFirstChild("Weapon")).toBeNil()
		expect(model:GetAttribute("WeaponId")).toBeNil()
		expect(humanoid:FindFirstChild(World.character.scaleValues.bodyHeight)).toBeNil()
		expect(#EntityService.players()).toBe(0)
	end)

	it("skips a character whose Humanoid never arrives, and one that left before it was ready", function()
		fresh()
		local model = Instance.new("Model")
		expect(PlaygroundService.onCharacter(player("Ghost"), model)).toBeNil()
		local gone = character("Leaver")
		gone.Parent = nil
		expect(PlaygroundService.onCharacter(player("Leaver"), gone)).toBeNil()
		expect(#EntityService.players()).toBe(0)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Spawns and respawns
-- ------------------------------------------------------------------------------------------

describe("PlaygroundService spawns", function()
	it(
		"spawnCFrame scatters inside spawnScatterRadius, stands the rig on the field and faces the entry with jitter",
		function()
			fresh()
			local boarRig = Rigs.Boar
			local rootHeight = boarRig.hipHeight
				+ boarRig.parts.HumanoidRootPart.size[2] / 2
				+ World.spawn.groundEpsilon
			for _ = 1, 30 do
				local spawn = Playground.spawns[1]
				local cframe = PlaygroundService.spawnCFrame(spawn)
				local dx = cframe.Position.X - spawn.position[1]
				local dz = cframe.Position.Z - spawn.position[3]
				expect(math.sqrt(dx * dx + dz * dz)).toBeLessThanOrEqual(Playground.spawnScatterRadius + 1e-3)
				expect(cframe.Position.Y).toBeCloseTo(rootHeight, 1e-3)
				-- facing 180 looks down +Z; jitter stays inside spawnFacingJitterDegrees.
				local look = cframe.LookVector
				local yaw = math.deg(math.atan2(-look.X, -look.Z))
				local difference = math.abs(((yaw - spawn.facing + 180) % 360) - 180)
				expect(difference).toBeLessThanOrEqual(Playground.spawnFacingJitterDegrees + 1e-3)
			end
		end
	)

	it("spawnAll spawns every entry with a pack size inside its range, through EnemyService.spawn", function()
		fresh()
		local ids = PlaygroundService.spawnAll()
		expect(#ids).toBe(#spawns)
		local perSlot: { [number]: number } = {}
		for _, id in ids do
			local slot = PlaygroundService.slotOf(id)
			expect(slot).toBeTruthy()
			perSlot[slot] = (perSlot[slot] or 0) + 1
		end
		for index, spawn in Playground.spawns do
			expect(perSlot[index]).toBeGreaterThanOrEqual(spawn.packSize.min)
			expect(perSlot[index]).toBeLessThanOrEqual(spawn.packSize.max)
		end
		for _, entry in spawns do
			expect(Playground.spawns[PlaygroundService.slotOf(entry.id)].enemy).toBe(entry.defId)
			expect(entry.model:GetAttribute("EntityId")).toBe(entry.id)
		end
		expect(#PlaygroundService.enemyIds()).toBe(#ids)
		expect(#EntityService.enemies()).toBe(#ids)
	end)

	it("respawns a slot playground.respawnSeconds after EnemyService reports it gone", function()
		fresh()
		local ids = PlaygroundService.spawnAll()
		local before = #spawns
		local victim = ids[1]
		local slot = PlaygroundService.slotOf(victim)
		local spawnedAgain = nil
		PlaygroundService.EnemySpawned:Connect(function(id, slotIndex)
			if id ~= victim then
				spawnedAgain = { id = id, slot = slotIndex }
			end
		end)
		fakeEnemies.Despawned:Fire(victim, "FrenzyBoar", "Died")
		task.wait()
		expect(PlaygroundService.pendingRespawns()).toBe(1)
		expect(PlaygroundService.slotOf(victim)).toBeNil()
		advance(Playground.respawnSeconds - 0.2)
		expect(#spawns).toBe(before)
		advance(0.4)
		task.wait()
		expect(#spawns).toBe(before + 1)
		expect(PlaygroundService.pendingRespawns()).toBe(0)
		expect(spawnedAgain).toBeTruthy()
		expect(spawnedAgain.slot).toBe(slot)
		expect(spawns[#spawns].defId).toBe(Playground.spawns[slot].enemy)
	end)

	it("ignores Despawned for enemies it did not spawn, and a reset forgets pending respawns", function()
		fresh()
		PlaygroundService.spawnAll()
		fakeEnemies.Despawned:Fire(9999, "FrenzyBoar", "Died")
		task.wait()
		expect(PlaygroundService.pendingRespawns()).toBe(0)
		fakeEnemies.Despawned:Fire(PlaygroundService.enemyIds()[1], "FrenzyBoar", "Died")
		task.wait()
		expect(PlaygroundService.pendingRespawns()).toBe(1)
		PlaygroundService.reset()
		expect(PlaygroundService.pendingRespawns()).toBe(0)
		expect(#PlaygroundService.enemyIds()).toBe(0)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Kill volume and start
-- ------------------------------------------------------------------------------------------

describe("PlaygroundService kill volume", function()
	it("kills any fighter whose root is below killVolume.y on the check interval, players and enemies alike", function()
		fresh()
		local ids = PlaygroundService.spawnAll()
		local model = character()
		local playerId = PlaygroundService.onCharacter(player("Faller"), model)
		local fallen = spawns[1].model
		fallen.PrimaryPart.CFrame = CFrame.new(0, Playground.killVolume.y - 1, 0)
		model.PrimaryPart.CFrame = CFrame.new(10, Playground.killVolume.y - 50, 0)
		advance(World.killVolume.checkInterval - 0.01)
		expect(EntityService.get(spawns[1].id).state).toBe("Idle")
		advance(0.05)
		expect(EntityService.get(spawns[1].id).state).toBe("Dead")
		expect(EntityService.get(playerId).state).toBe("Dead")
		-- Fighters still on the field are untouched.
		for _, id in ids do
			if id ~= spawns[1].id then
				expect(EntityService.get(id).state).toBe("Idle")
			end
		end
		expect(#PlaygroundService.checkKillVolume()).toBe(0) -- the dead are not killed twice
	end)
end)

describe("PlaygroundService.start", function()
	it("builds the world once, spawns the first wave and is safe to call twice", function()
		fresh()
		PlaygroundService.start()
		PlaygroundService.start()
		expect(built).toBe(1)
		expect(PlaygroundService.buildResult()).toEqual({ partCount = 0 })
		expect(#PlaygroundService.enemyIds()).toBeGreaterThanOrEqual(#Playground.spawns)
		PlaygroundService.reset()
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Spawn spacing (D-170)
-- ------------------------------------------------------------------------------------------

describe("PlaygroundService spawn spacing (D-170)", function()
	local function flat(cframe: CFrame): (number, number)
		return cframe.Position.X, cframe.Position.Z
	end

	local function apart(a: CFrame, b: CFrame): number
		local ax, az = flat(a)
		local bx, bz = flat(b)
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	it("no two enemies of the first wave stand on each other, packmates included", function()
		local minStuds = Playground.spawnSpacing.minStuds
		local packsOfTwo = 0
		for seed = 1, 40 do
			fresh({ random = Random.new(seed) })
			PlaygroundService.spawnAll()
			for i = 1, #spawns do
				for j = i + 1, #spawns do
					if PlaygroundService.slotOf(spawns[i].id) == PlaygroundService.slotOf(spawns[j].id) then
						packsOfTwo += 1
					end
					expect(apart(spawns[i].cframe, spawns[j].cframe)).toBeGreaterThanOrEqual(minStuds - 1e-6)
				end
			end
		end
		expect(packsOfTwo).toBeGreaterThan(10) -- the seeds really drew packs of two
	end)

	it("a respawn never lands on a living fighter: not on the player at the spawn point, not on a packmate", function()
		local minStuds = Playground.spawnSpacing.minStuds
		for seed = 1, 12 do
			fresh({ random = Random.new(seed) })
			PlaygroundService.spawnAll()
			local victim = spawns[1].id
			local slot = PlaygroundService.slotOf(victim)
			local point = Playground.spawns[slot].position
			local model = character("Camper")
			local playerId = PlaygroundService.onCharacter(player("Camper"), model)
			model.PrimaryPart.CFrame = CFrame.new(point[1], point[2] + 3, point[3])
			fakeEnemies.Despawned:Fire(victim, Playground.spawns[slot].enemy, "Died")
			EntityService.unregister(victim)
			task.wait()
			advance(Playground.respawnSeconds + 0.1)
			local respawned = spawns[#spawns]
			expect(PlaygroundService.slotOf(respawned.id)).toBe(slot)
			local camper = EntityService.positionOf(playerId)
			expect(apart(respawned.cframe, CFrame.new(camper))).toBeGreaterThanOrEqual(minStuds - 1e-6)
			for _, other in spawns do
				if other.id ~= respawned.id and other.id ~= victim then
					expect(apart(respawned.cframe, other.cframe)).toBeGreaterThanOrEqual(minStuds - 1e-6)
				end
			end
		end
	end)

	it("the dead are not in the way: a fallen player on the spawn point does not push a spawn out", function()
		fresh({ random = Random.new(4) })
		local spawn = Playground.spawns[1]
		local model = character("Fallen")
		local playerId = PlaygroundService.onCharacter(player("Fallen"), model)
		model.PrimaryPart.CFrame = CFrame.new(spawn.position[1], 3, spawn.position[3])
		EntityService.die(playerId, nil)
		local expected = Random.new(4)
		local ex, ez =
			PlaygroundLayout.scatter(spawn.position[1], spawn.position[3], Playground.spawnScatterRadius, expected)
		local x, z = flat(PlaygroundService.spawnCFrame(spawn))
		expect(x).toBeCloseTo(ex, 1e-3) -- a CFrame holds single precision
		expect(z).toBeCloseTo(ez, 1e-3)
	end)

	it("minStuds clears two of the largest Playground bodies at any facing", function()
		local reach = 0
		for _, spawn in Playground.spawns do
			local def = Enemies.byId(spawn.enemy)
			local model = RigBuilder.build(def.skin, def.name)
			local root = model.PrimaryPart
			for _, part in model:GetDescendants() do
				if not part:IsA("BasePart") then
					continue
				end
				local half = part.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local corner =
								part.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
							local p = root.CFrame:PointToObjectSpace(corner)
							reach = math.max(reach, math.sqrt(p.X * p.X + p.Z * p.Z))
						end
					end
				end
			end
		end
		expect(reach).toBeGreaterThan(0)
		expect(2 * reach).toBeLessThanOrEqual(Playground.spawnSpacing.minStuds)
	end)
end)
