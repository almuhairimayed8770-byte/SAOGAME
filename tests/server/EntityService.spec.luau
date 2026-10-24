--!strict
-- EntityService under Lune: fake clock, fake net, fake tags; models built with Instance.new.
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
local Combat = Harness.load("src/shared/data/combat")
local Enemies = Harness.load("src/shared/data/enemies")
local Playground = Harness.load("src/shared/data/playground")
local Net = Harness.load("src/shared/net/Net")
local Armor = Harness.load("src/shared/data/armor")
local CollectionService = Harness.game():GetService("CollectionService")

local BOAR = Enemies.byId("FrenzyBoar")
local KOBOLD = Enemies.byId("KoboldAxeman")

local function loadoutDefense()
	local ids = {}
	for _, id in Playground.loadout.armor do
		table.insert(ids, id)
	end
	return Armor.totals(ids).defense
end
local PLAYER_DEFENSE = loadoutDefense()

-- ------------------------------------------------------------------------------------------
-- Fixtures
-- ------------------------------------------------------------------------------------------

local clock = { t = 1000 }
local sent = {}
local respawned = {}

local function fresh()
	EntityService.reset()
	clock.t = 1000
	sent = {}
	respawned = {}
	EntityService.bind({
		now = function()
			return clock.t
		end,
		fireAll = function(remote, payload)
			local ok, message = Net.validate(remote, payload)
			if not ok then
				error(("invalid %s payload: %s"):format(remote, tostring(message)))
			end
			table.insert(sent, { remote = remote, payload = payload })
		end,
		heartbeat = nil,
		addTag = function(instance, tag)
			CollectionService:AddTag(instance, tag)
		end,
		removeTag = function(instance, tag)
			CollectionService:RemoveTag(instance, tag)
		end,
		respawn = function(player)
			table.insert(respawned, player)
		end,
		playerRemoving = nil,
	})
end

local function sentOf(remote)
	local list = {}
	for _, entry in sent do
		if entry.remote == remote then
			table.insert(list, entry.payload)
		end
	end
	return list
end

local function rigModel(name, position, size)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = size
	root.CFrame = CFrame.new(position)
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	return model, root, humanoid
end

local function spawnBoar(position)
	local model = rigModel("FrenzyBoar", position or Vector3.new(0, 1.6, -6), Vector3.new(2.4, 2.4, 5))
	return EntityService.registerEnemy(model, BOAR), model
end

local function spawnPlayer(name, position)
	local player = { Name = name or "Tester", DisplayName = name or "Tester", UserId = 7 }
	local character = rigModel(player.Name, position or Vector3.new(0, 3, 0), Vector3.new(2, 2, 1))
	local id = EntityService.registerPlayer(player, character, Playground.loadout)
	return id, character, player
end

-- Advances the clock in small steps so timers, regen and expiry behave as on Heartbeat.
local function advance(seconds, step)
	local dt = step or 1 / 60
	local remaining = seconds
	while remaining > 1e-9 do
		local slice = math.min(dt, remaining)
		clock.t += slice
		EntityService.tick(slice)
		remaining -= slice
	end
end

-- A tier-1 Horizontal from the Trialist Sword (attack 18, STR 10) on the attack side.
local RAW_HORIZONTAL = 18 * 1.0 * (1 + 10 * Combat.strDamageScale)

local function artHit(attackerId, rawDamage, gauge, hitStop)
	return {
		attackerId = attackerId,
		rawDamage = rawDamage or RAW_HORIZONTAL,
		gaugeDamage = gauge or 20,
		crit = false,
		parried = false,
		guarded = false,
		artId = "OneHandedSword.Horizontal",
		hitIndex = 1,
		hitStop = hitStop or "Normal",
		position = { 0, 2, -4 },
	}
end

-- ------------------------------------------------------------------------------------------
-- Registration and attributes
-- ------------------------------------------------------------------------------------------

describe("EntityService registration", function()
	it("registers a player from the Playground loadout with section 6 HP and gauge", function()
		fresh()
		local id, character = spawnPlayer()
		local record = EntityService.get(id)
		expect(record).never.toBeNil()
		expect(record.kind).toBe("Player")
		expect(record.maxHp).toBe(Combat.basePlayerHp + Combat.hpPerLevel * (Playground.loadout.level - 1))
		expect(record.hp).toBe(record.maxHp)
		expect(record.maxGauge).toBe(Combat.playerGuardGaugeBase)
		expect(record.defense).toBe(PLAYER_DEFENSE) -- the Trialist cloth set's flat sum
		expect(PLAYER_DEFENSE).toBeGreaterThan(0)
		expect(record.attack).toBe(18) -- Trialist Sword
		expect(record.weaponId).toBe("TrialistSword")
		expect(record.proficiency.OneHandedSword).toBe(150)
		expect(record.stats).toEqual({ str = 10, agi = 10, level = 1 })
		expect(record.artSlots).toEqual(Playground.loadout.artSlots)
		expect(record.artSlots).never.toBe(Playground.loadout.artSlots) -- a copy, never the shared data table
		-- ARCHITECTURE attribute table
		expect(character:GetAttribute("EntityId")).toBe(id)
		expect(character:GetAttribute("EntityKind")).toBe("Player")
		expect(character:GetAttribute("DefId")).toBe("Player")
		expect(character:GetAttribute("Rig")).toBe("PlayerR15")
		expect(character:GetAttribute("DisplayName")).toBe("Tester")
		expect(character:GetAttribute("HP")).toBe(300)
		expect(character:GetAttribute("MaxHP")).toBe(300)
		expect(character:GetAttribute("Gauge")).toBe(100)
		expect(character:GetAttribute("MaxGauge")).toBe(100)
		expect(character:GetAttribute("State")).toBe("Idle")
		expect(character:GetAttribute("Cursor")).toBe("Green")
		expect(character:GetAttribute("Level")).toBe(1)
		expect(character:GetAttribute("WeaponId")).toBe("TrialistSword")
		expect(character:GetAttribute("ArtSlots")).toBe(table.concat(Playground.loadout.artSlots, ","))
		expect(CollectionService:HasTag(character, "SkyspireEntity")).toBe(true)
		expect(CollectionService:HasTag(character, "SkyspirePlayer")).toBe(true)
		expect(CollectionService:HasTag(character, "SkyspireEnemy")).toBe(false)
	end)

	it("registers an enemy from its def and publishes its attributes and tags", function()
		fresh()
		local id, model = spawnBoar()
		local record = EntityService.get(id)
		expect(record.kind).toBe("Enemy")
		expect(record.hp).toBe(BOAR.hp)
		expect(record.maxGauge).toBe(BOAR.guardGauge)
		expect(record.defense).toBe(BOAR.defense)
		expect(record.attack).toBe(BOAR.attack)
		expect(record.shatter).toBe("Beast")
		expect(record.artSlots).toBeNil() -- no quick slots: CombatService skips the slot check for enemies
		expect(model:GetAttribute("EntityKind")).toBe("Enemy")
		expect(model:GetAttribute("DefId")).toBe("FrenzyBoar")
		expect(model:GetAttribute("Rig")).toBe("Boar")
		expect(model:GetAttribute("DisplayName")).toBe("Frenzy Boar")
		expect(model:GetAttribute("HP")).toBe(120)
		expect(model:GetAttribute("MaxGauge")).toBe(60)
		expect(model:GetAttribute("Level")).toBe(1)
		expect(model:GetAttribute("Cursor")).toBeNil()
		expect(CollectionService:HasTag(model, "SkyspireEnemy")).toBe(true)
	end)

	it("labels an Elite variant's model Elite next to its DefId; an ordinary mob carries no label", function()
		fresh()
		-- The server still owns everything; Elite is a replicated label (the client shatters it heavy).
		local _, boarModel = spawnBoar()
		expect(boarModel:GetAttribute("Elite")).toBeNil()
		local elite = Enemies.variant(BOAR, "Elite")
		local model = rigModel("EliteBoar", Vector3.new(6, 1.6, -6), Vector3.new(2.4, 2.4, 5))
		local id = EntityService.registerEnemy(model, elite)
		expect(model:GetAttribute("DefId")).toBe("FrenzyBoar")
		expect(model:GetAttribute("Elite")).toBe(true)
		-- Published once: later ticks leave it alone, and it survives them.
		advance(0.2)
		expect(model:GetAttribute("Elite")).toBe(true)
		expect(EntityService.get(id).enemyDef.elite).toBe(true)
	end)

	it("pins the engine Humanoid's health (D-012) and re-pins it every tick", function()
		fresh()
		local _, model = spawnBoar()
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		expect(humanoid.Health).toBe(Combat.humanoidPinnedHealth)
		expect(humanoid.MaxHealth).toBe(Combat.humanoidPinnedHealth)
		humanoid.Health = 3
		advance(0.1)
		expect(humanoid.Health).toBe(Combat.humanoidPinnedHealth)
	end)

	it("hands out unique integer ids and finds records by id, model, part and player", function()
		fresh()
		local boarId, boarModel = spawnBoar()
		local playerId, character, player = spawnPlayer()
		expect(boarId).never.toBe(playerId)
		expect(boarId % 1).toBe(0)
		expect(EntityService.fromModel(boarModel).id).toBe(boarId)
		expect(EntityService.fromInstance(boarModel.PrimaryPart).id).toBe(boarId)
		expect(EntityService.fromInstance(Instance.new("Part"))).toBeNil()
		expect(EntityService.fromPlayer(player).id).toBe(playerId)
		expect(#EntityService.all()).toBe(2)
		expect(#EntityService.players()).toBe(1)
		expect(#EntityService.enemies()).toBe(1)
		expect(EntityService.players()[1].model).toBe(character)
	end)

	it("a player's new character replaces the old record", function()
		fresh()
		local firstId, _, player = spawnPlayer()
		local character = rigModel("Tester", Vector3.new(0, 3, 0), Vector3.new(2, 2, 1))
		local secondId = EntityService.registerPlayer(player, character, Playground.loadout)
		expect(EntityService.get(firstId)).toBeNil()
		expect(EntityService.fromPlayer(player).id).toBe(secondId)
	end)

	it("unregister clears tags and fires Unregistered", function()
		fresh()
		local id, model = spawnBoar()
		local gone = nil
		EntityService.Unregistered:Connect(function(record)
			gone = record.id
		end)
		EntityService.unregister(id)
		task.wait()
		expect(gone).toBe(id)
		expect(EntityService.get(id)).toBeNil()
		expect(CollectionService:HasTag(model, "SkyspireEntity")).toBe(false)
	end)

	it("nearest finds the closest living fighter of a kind inside the radius", function()
		fresh()
		local nearId = spawnBoar(Vector3.new(0, 1, -5))
		spawnBoar(Vector3.new(0, 1, -20))
		spawnPlayer("Tester", Vector3.new(0, 3, -2))
		expect(EntityService.nearest(Vector3.new(0, 1, 0), 50, "Enemy").id).toBe(nearId)
		expect(EntityService.nearest(Vector3.new(0, 1, 0), 3, "Enemy")).toBeNil()
		expect(EntityService.nearest(Vector3.new(0, 1, 0), 50, "Player").kind).toBe("Player")
	end)

	it("refuses a model without a PrimaryPart", function()
		fresh()
		expect(function()
			EntityService.registerEnemy(Instance.new("Model"), BOAR)
		end).toThrow("PrimaryPart")
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Hits, Break, death
-- ------------------------------------------------------------------------------------------

describe("EntityService.applyHit", function()
	it("applies defense, drops HP and gauge, adds threat, tags combat and fires HpChanged", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId, model = spawnBoar()
		local changes = {}
		EntityService.HpChanged:Connect(function(record, old, new)
			table.insert(changes, { record.id, old, new })
		end)
		local result = EntityService.applyHit(boarId, artHit(playerId))
		task.wait()
		local expected = math.floor(RAW_HORIZONTAL - BOAR.defense + 0.5)
		expect(result.damage).toBe(expected)
		expect(result.killed).toBe(false)
		expect(result.broke).toBe(false)
		expect(result.wasInBreak).toBe(false)
		expect(result.hitStop).toBe("Normal")
		expect(result.gaugeDamage).toBe(20)
		expect(result.hpAfter).toBe(BOAR.hp - expected)
		expect(result.gaugeAfter).toBe(BOAR.guardGauge - 20)
		expect(result.staggerDirection).toBe("Back") -- the player stands behind a boar facing -Z
		expect(model:GetAttribute("HP")).toBe(BOAR.hp - expected)
		expect(model:GetAttribute("Gauge")).toBe(BOAR.guardGauge - 20)
		expect(changes[1]).toEqual({ boarId, BOAR.hp, BOAR.hp - expected })
		expect(EntityService.threatOf(boarId)[playerId]).toBeCloseTo(expected * Combat.threatPerDamage, 1e-9)
		expect(EntityService.topThreat(boarId)).toBe(playerId)
		expect(EntityService.inCombat(boarId)).toBe(true)
		expect(EntityService.inCombat(playerId)).toBe(true)
	end)

	it("a level-1 Horizontal needs 6 to 8 hits on a boar (section 9)", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		local hits = 0
		while EntityService.isAlive(boarId) do
			EntityService.applyHit(boarId, artHit(playerId, RAW_HORIZONTAL, 0))
			hits += 1
			expect(hits).toBeLessThan(20)
		end
		expect(hits).toBeGreaterThanOrEqual(6)
		expect(hits).toBeLessThanOrEqual(8)
	end)

	it("empties the gauge into Break: 2x damage, zero post-motion flag, refill when it ends", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId, model = spawnBoar()
		local broke = nil
		EntityService.Broke:Connect(function(record)
			broke = record.id
		end)
		-- Two Verticals (35 gauge each) against a 60 gauge: the second one breaks.
		local first = EntityService.applyHit(boarId, artHit(playerId, RAW_HORIZONTAL, 35))
		expect(first.broke).toBe(false)
		local second = EntityService.applyHit(boarId, artHit(playerId, RAW_HORIZONTAL, 35))
		task.wait()
		expect(second.broke).toBe(true)
		expect(second.wasInBreak).toBe(false)
		expect(second.gaugeAfter).toBe(0)
		expect(broke).toBe(boarId)
		expect(EntityService.get(boarId).state).toBe("Break")
		expect(model:GetAttribute("State")).toBe("Break")
		local states = sentOf("StateChanged")
		local last = states[#states]
		expect(last.entityId).toBe(boarId)
		expect(last.state).toBe("Break")
		expect(last.duration).toBe(Combat.breakDuration)
		-- Hits on a Broken enemy do double damage and report wasInBreak; gauge damage is ignored.
		local normal = math.floor(RAW_HORIZONTAL - BOAR.defense + 0.5)
		local third = EntityService.applyHit(boarId, artHit(playerId, RAW_HORIZONTAL, 35))
		expect(third.wasInBreak).toBe(true)
		expect(third.damage).toBe(math.floor(normal * Combat.breakDamageMultiplier + 0.5))
		expect(third.gaugeDamage).toBe(0)
		expect(third.broke).toBe(false)
		-- The Break expires on its own and the gauge comes back full.
		advance(Combat.breakDuration - 0.1)
		expect(EntityService.get(boarId).state).toBe("Break")
		advance(0.2)
		expect(EntityService.get(boarId).state).toBe("Idle")
		expect(EntityService.get(boarId).gauge).toBe(BOAR.guardGauge)
	end)

	it("kills at 0 HP: Dead state, Kill hit-stop, EntityDied to all, Died signal, corpse removed later", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId, model = spawnBoar()
		local died = nil
		EntityService.Died:Connect(function(record, killerId)
			died = { record.id, killerId }
		end)
		local result = EntityService.applyHit(boarId, artHit(playerId, 10000, 0, "Final"))
		task.wait()
		expect(result.killed).toBe(true)
		expect(result.hitStop).toBe("Kill")
		expect(result.hpAfter).toBe(0)
		expect(EntityService.get(boarId).state).toBe("Dead")
		expect(EntityService.isAlive(boarId)).toBe(false)
		expect(model:GetAttribute("HP")).toBe(0)
		expect(model:GetAttribute("State")).toBe("Dead")
		expect(died).toEqual({ boarId, playerId })
		local deaths = sentOf("EntityDied")
		expect(#deaths).toBe(1)
		expect(deaths[1].entityId).toBe(boarId)
		expect(deaths[1].shatter).toBe("Beast")
		expect(deaths[1].name).toBe("Frenzy Boar")
		expect(deaths[1].byPlayer).toBe(true)
		expect(#deaths[1].position).toBe(3)
		-- Further hits do nothing to a corpse.
		local again = EntityService.applyHit(boarId, artHit(playerId))
		expect(again.damage).toBe(0)
		expect(again.killed).toBe(false)
		-- The model stays for the freeze and the shatter, then goes.
		advance(Combat.corpseRemoveDelay - 0.2)
		expect(EntityService.get(boarId)).never.toBeNil()
		advance(0.4)
		expect(EntityService.get(boarId)).toBeNil()
	end)

	it("a parried hit deals nothing and changes nothing", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		local hit = artHit(boarId, 50, 15)
		hit.parried = true
		local result = EntityService.applyHit(playerId, hit)
		expect(result.parried).toBe(true)
		expect(result.damage).toBe(0)
		expect(result.gaugeDamage).toBe(0)
		expect(EntityService.get(playerId).hp).toBe(300)
		expect(EntityService.get(playerId).gauge).toBe(100)
	end)

	it("a guarded hit takes 70% off and drains the player's gauge into GuardBroken at zero", function()
		fresh()
		local playerId, character = spawnPlayer()
		local boarId = spawnBoar()
		local raw = 40
		local hit = artHit(boarId, raw, 60)
		hit.guarded = true
		hit.artId = nil
		local first = EntityService.applyHit(playerId, hit)
		local open = math.floor(raw - PLAYER_DEFENSE + 0.5)
		expect(first.guarded).toBe(true)
		expect(first.damage).toBe(math.floor(open * (1 - Combat.guardReduction) + 0.5))
		expect(first.gaugeDamage).toBeCloseTo(60 * Combat.guardGaugeDrainFraction, 1e-9)
		expect(first.broke).toBe(false)
		local second = EntityService.applyHit(playerId, hit)
		expect(second.broke).toBe(true)
		expect(EntityService.get(playerId).state).toBe("GuardBroken")
		expect(character:GetAttribute("State")).toBe("GuardBroken")
		expect(EntityService.get(playerId).guardHeld).toBe(false)
		advance(Combat.guardBreakStagger + 0.05)
		expect(EntityService.get(playerId).state).toBe("Idle")
		expect(EntityService.get(playerId).gauge).toBe(100)
	end)

	it("a GuardBreak telegraph empties the gauge outright and deals full damage", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		local hit = artHit(boarId, 40, 5)
		hit.breakGuard = true
		local result = EntityService.applyHit(playerId, hit)
		expect(result.damage).toBe(math.floor(40 - PLAYER_DEFENSE + 0.5))
		expect(result.broke).toBe(true)
		expect(result.gaugeAfter).toBe(0)
		expect(EntityService.get(playerId).state).toBe("GuardBroken")
	end)

	it("a player who dies respawns after respawnDelay and the record goes", function()
		fresh()
		local playerId, _, player = spawnPlayer()
		local boarId = spawnBoar()
		local result = EntityService.applyHit(playerId, artHit(boarId, 10000, 0))
		expect(result.killed).toBe(true)
		local deaths = sentOf("EntityDied")
		expect(deaths[1].byPlayer).toBe(false)
		expect(deaths[1].shatter).toBe("Humanoid")
		advance(Combat.respawnDelay - 0.1)
		expect(#respawned).toBe(0)
		advance(0.2)
		expect(#respawned).toBe(1)
		expect(respawned[1]).toBe(player)
		expect(EntityService.get(playerId)).toBeNil()
	end)

	it("dying clears the dead fighter from every threat table", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.applyHit(boarId, artHit(playerId))
		expect(EntityService.topThreat(boarId)).toBe(playerId)
		EntityService.die(playerId)
		expect(EntityService.threatOf(boarId)[playerId]).toBeNil()
		expect(EntityService.topThreat(boarId)).toBeNil()
	end)

	it("errors on an unknown target", function()
		fresh()
		expect(function()
			EntityService.applyHit(999, artHit(1))
		end).toThrow("no entity")
	end)
end)

-- ------------------------------------------------------------------------------------------
-- States, guard, timers
-- ------------------------------------------------------------------------------------------

describe("EntityService states and timers", function()
	it("timed states lock the body and expire back to Idle", function()
		fresh()
		local id, character = spawnPlayer()
		EntityService.setState(id, "Stagger", Combat.staggerDuration, "Left")
		local record = EntityService.get(id)
		expect(record.state).toBe("Stagger")
		expect(character:GetAttribute("State")).toBe("Stagger")
		expect(record.lockUntil).toBeCloseTo(clock.t + Combat.staggerDuration, 1e-9)
		expect(EntityService.isLocked(id)).toBe(true)
		local states = sentOf("StateChanged")
		expect(states[#states].direction).toBe("Left")
		expect(states[#states].duration).toBe(Combat.staggerDuration)
		-- Inside the request tolerance the lock already reads as open.
		clock.t += Combat.staggerDuration - Combat.artRequestTolerance + 0.001
		expect(EntityService.isLocked(id)).toBe(false)
		expect(record.state).toBe("Stagger")
		advance(Combat.artRequestTolerance)
		expect(record.state).toBe("Idle")
		expect(character:GetAttribute("State")).toBe("Idle")
	end)

	it("an Art lock covers the whole estimated duration and PostMotion replaces it", function()
		fresh()
		local id = spawnPlayer()
		EntityService.setState(id, "Art", 1.0)
		expect(EntityService.get(id).lockUntil).toBeCloseTo(clock.t + 1.0, 1e-9)
		clock.t += 0.6
		EntityService.setState(id, "PostMotion", 0.4)
		expect(EntityService.get(id).lockUntil).toBeCloseTo(clock.t + 0.4, 1e-9)
		advance(0.45)
		expect(EntityService.get(id).state).toBe("Idle")
		expect(EntityService.isLocked(id)).toBe(false)
	end)

	it("extendState pushes a timed state's end and its lock later, quietly (D-168)", function()
		fresh()
		local id = spawnBoar()
		EntityService.setState(id, "Art", 1.0)
		local record = EntityService.get(id)
		local until_, lock = record.stateUntil, record.lockUntil
		local changes = #sentOf("StateChanged")
		expect(EntityService.extendState(id, 0.05)).toBe(true)
		expect(record.stateUntil).toBeCloseTo(until_ + 0.05, 1e-9)
		expect(record.lockUntil).toBeCloseTo(lock + 0.05, 1e-9)
		expect(#sentOf("StateChanged")).toBe(changes) -- HitConfirmed carries the pause instead
		advance(1.0)
		expect(record.state).toBe("Art") -- the unextended end has passed
		advance(0.2) -- past the extended end, on the enemies' slower tick
		expect(record.state).toBe("Idle")
		-- Nothing to extend: an untimed state, a zero push, an unknown or dead fighter.
		expect(EntityService.extendState(id, 0.05)).toBe(false)
		EntityService.setState(id, "Art", 1.0)
		expect(EntityService.extendState(id, 0)).toBe(false)
		expect(EntityService.extendState(999, 0.05)).toBe(false)
		EntityService.die(id)
		expect(EntityService.extendState(id, 0.05)).toBe(false)
	end)

	it("entering a lock state drops the guard; a dead fighter never changes state again", function()
		fresh()
		local id = spawnPlayer()
		EntityService.setGuard(id, true)
		expect(EntityService.get(id).state).toBe("Guard")
		EntityService.setState(id, "Stagger", Combat.staggerDuration)
		expect(EntityService.get(id).guardHeld).toBe(false)
		EntityService.die(id)
		EntityService.setState(id, "Idle")
		expect(EntityService.get(id).state).toBe("Dead")
	end)

	it("guard raise records guardSince, release returns to Idle", function()
		fresh()
		local id = spawnPlayer()
		expect(EntityService.setGuard(id, true)).toBe(true)
		local record = EntityService.get(id)
		expect(record.state).toBe("Guard")
		expect(record.guardHeld).toBe(true)
		expect(record.guardSince).toBe(clock.t)
		-- No stored axis: the guard cone is judged against the root at strike time (CombatService).
		expect(record.guardFacing).toBeNil()
		expect(EntityService.isLocked(id)).toBe(false)
		clock.t += 1
		-- Holding does not refresh the parry timestamp.
		EntityService.setGuard(id, true)
		expect(record.guardSince).toBe(clock.t - 1)
		EntityService.setGuard(id, false)
		expect(record.state).toBe("Idle")
		expect(record.guardHeld).toBe(false)
		expect(record.guardSince).toBeNil()
	end)

	it("a raise inside parryRearmTime of the last release cannot parry; a later one can", function()
		fresh()
		local id = spawnPlayer()
		EntityService.setGuard(id, true)
		clock.t += 0.5
		EntityService.setGuard(id, false)
		clock.t += Combat.parryRearmTime / 2
		EntityService.setGuard(id, true)
		expect(EntityService.get(id).state).toBe("Guard")
		expect(EntityService.get(id).guardSince).toBeNil()
		EntityService.setGuard(id, false)
		clock.t += Combat.parryRearmTime + 0.01
		EntityService.setGuard(id, true)
		expect(EntityService.get(id).guardSince).toBe(clock.t)
	end)

	it("a guard cannot be raised from a locked state but can cancel a basic swing", function()
		fresh()
		local id = spawnPlayer()
		EntityService.setState(id, "PostMotion", 0.4)
		expect(EntityService.setGuard(id, true)).toBe(false)
		expect(EntityService.get(id).guardHeld).toBe(false)
		expect(EntityService.get(id).state).toBe("PostMotion")
		advance(0.5)
		EntityService.setState(id, "Art", Combat.basicHitDuration, nil, "Basic")
		expect(EntityService.canGuard(id)).toBe(true)
		expect(EntityService.setGuard(id, true)).toBe(true)
		expect(EntityService.get(id).state).toBe("Guard")
	end)

	it("invulnerability and targets", function()
		fresh()
		local id = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.setInvulnerable(id, clock.t + Combat.dodgeInvulnerability)
		expect(EntityService.isInvulnerable(id)).toBe(true)
		clock.t += Combat.dodgeInvulnerability + 0.001
		expect(EntityService.isInvulnerable(id)).toBe(false)
		expect(EntityService.setTarget(id, boarId)).toBe(true)
		expect(EntityService.get(id).targetId).toBe(boarId)
		expect(EntityService.setTarget(id, 4242)).toBe(false)
		expect(EntityService.setTarget(id, nil)).toBe(true)
		expect(EntityService.get(id).targetId).toBeNil()
	end)

	it("setWeapon changes a player's attack and the WeaponId attribute", function()
		fresh()
		local id, character = spawnPlayer()
		EntityService.setWeapon(id, "TrialistKatana")
		expect(EntityService.get(id).weaponId).toBe("TrialistKatana")
		expect(EntityService.get(id).attack).toBe(20)
		expect(character:GetAttribute("WeaponId")).toBe("TrialistKatana")
	end)

	it("StateChanged payloads pass the remote schema and skip Idle -> Idle repeats", function()
		fresh()
		local id = spawnPlayer()
		local before = #sentOf("StateChanged")
		EntityService.setState(id, "Idle")
		expect(#sentOf("StateChanged")).toBe(before)
		EntityService.setState(id, "Dodge", Combat.dodgeDuration)
		expect(#sentOf("StateChanged")).toBe(before + 1)
	end)
end)

describe("EntityService regen", function()
	it("Guard Gauge regenerates 10%/s after guardRegenDelay since the last Art hit, not before", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.applyHit(boarId, artHit(playerId, RAW_HORIZONTAL, 30))
		local record = EntityService.get(boarId)
		expect(record.gauge).toBe(30)
		advance(Combat.guardRegenDelay - 0.1)
		expect(record.gauge).toBe(30)
		advance(1.1) -- 1.0 s of regen at 10% of 60 per second
		expect(record.gauge).toBeCloseTo(36, 0.5)
		advance(10)
		expect(record.gauge).toBe(BOAR.guardGauge)
	end)

	it("a basic attack's gauge damage does not pause the regen", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		local hit = artHit(playerId, RAW_HORIZONTAL * 0.3, 2)
		hit.artId = nil
		hit.isBasic = true
		EntityService.applyHit(boarId, hit)
		local record = EntityService.get(boarId)
		expect(record.gauge).toBe(58)
		expect(record.lastArtHitAt).toBeNil()
		advance(0.1)
		expect(record.gauge).toBeGreaterThan(58)
	end)

	it("HP regenerates 1%/s only after outOfCombatRegenDelay without a hit", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.applyHit(playerId, artHit(boarId, 50, 0))
		local record = EntityService.get(playerId)
		local hurt = record.hp
		expect(hurt).toBeLessThan(300)
		advance(Combat.outOfCombatRegenDelay - 0.1)
		expect(record.hp).toBe(hurt)
		expect(EntityService.inCombat(playerId)).toBe(false) -- the tag lasts combatTagDuration
		advance(1.1)
		expect(record.hp).toBeCloseTo(hurt + 3, 0.2) -- 1% of 300 per second
		-- Dealing a hit counts as combat too and stops the regen.
		local healed = record.hp
		EntityService.applyHit(boarId, artHit(playerId))
		advance(1)
		expect(record.hp).toBeCloseTo(healed, 1e-6)
		advance(60)
		expect(record.hp).toBe(300)
	end)

	it("enemies step at enemyTickHz, players every frame", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.setState(playerId, "Stagger", 0.02)
		EntityService.setState(boarId, "Stagger", 0.02)
		clock.t += 0.025
		EntityService.tick(0.025) -- below the enemy step: only the player expires
		expect(EntityService.get(playerId).state).toBe("Idle")
		expect(EntityService.get(boarId).state).toBe("Stagger")
		clock.t += 0.03
		EntityService.tick(0.03)
		expect(EntityService.get(boarId).state).toBe("Idle")
	end)

	it("heal restores HP up to the maximum", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.applyHit(playerId, artHit(boarId, 100, 0))
		EntityService.heal(playerId, 1000)
		expect(EntityService.get(playerId).hp).toBe(300)
	end)
end)

describe("EntityService.setHp (dev and GM only, D-121)", function()
	it("sets HP, clamped to [1, maxHp], publishes the HP attribute and fires HpChanged", function()
		fresh()
		local boarId, model = spawnBoar()
		local record = EntityService.get(boarId)
		local changes = {}
		local connection = EntityService.HpChanged:Connect(function(changed, old, new)
			table.insert(changes, { id = changed.id, old = old, new = new })
		end)
		expect(EntityService.setHp(boarId, 1)).toBe(1)
		expect(record.hp).toBe(1)
		expect(model:GetAttribute("HP")).toBe(1)
		expect(changes).toEqual({ { id = boarId, old = record.maxHp, new = 1 } })
		-- Never kills: zero and below clamp to 1; above the maximum clamps to it.
		expect(EntityService.setHp(boarId, 0)).toBe(1)
		expect(EntityService.setHp(boarId, -50)).toBe(1)
		expect(record.state).never.toBe("Dead")
		expect(EntityService.isAlive(boarId)).toBe(true)
		expect(EntityService.setHp(boarId, record.maxHp * 4)).toBe(record.maxHp)
		expect(model:GetAttribute("HP")).toBe(record.maxHp)
		expect(EntityService.setHp(boarId, 37.4)).toBe(37.4)
		expect(model:GetAttribute("HP")).toBe(37)
		expect(sentOf("EntityDied")).toHaveLength(0)
		connection:Disconnect()
	end)

	it("works on a player and draws no sword", function()
		fresh()
		local playerId, character = spawnPlayer()
		expect(EntityService.setHp(playerId, 40)).toBe(40)
		expect(character:GetAttribute("HP")).toBe(40)
		expect(character:GetAttribute("Drawn")).toBe(false)
		expect(EntityService.inCombat(playerId)).toBe(false)
	end)

	it("refuses an unknown id, a dead fighter and a value that is not a number", function()
		fresh()
		local boarId = spawnBoar()
		expect(EntityService.setHp(999, 10)).toBeNil()
		expect(EntityService.setHp(boarId, 0 / 0)).toBeNil()
		expect(EntityService.get(boarId).hp).toBe(EntityService.get(boarId).maxHp)
		EntityService.die(boarId)
		expect(EntityService.setHp(boarId, 10)).toBeNil()
		expect(EntityService.get(boarId).hp).toBe(0)
		expect(EntityService.get(boarId).state).toBe("Dead")
	end)

	it("restarts the out-of-combat regen wait, so the set value holds until the hit", function()
		fresh()
		local boarId = spawnBoar()
		advance(Combat.outOfCombatRegenDelay + 1) -- long out of combat: regen would run at once
		EntityService.setHp(boarId, 1)
		advance(Combat.outOfCombatRegenDelay - 0.5)
		expect(EntityService.get(boarId).hp).toBe(1)
		advance(2)
		expect(EntityService.get(boarId).hp).toBeGreaterThan(1)
	end)

	it("the next real hit on a fighter set to 1 HP is the kill: Kill hit-stop, Dead, EntityDied", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.setHp(boarId, 1)
		local applied = EntityService.applyHit(boarId, artHit(playerId, RAW_HORIZONTAL, 0))
		expect(applied.killed).toBe(true)
		expect(applied.hitStop).toBe("Kill")
		expect(EntityService.get(boarId).state).toBe("Dead")
		local died = sentOf("EntityDied")
		expect(died).toHaveLength(1)
		expect(died[1].entityId).toBe(boarId)
		expect(died[1].byPlayer).toBe(true)
	end)
end)

describe("EntityService.setHpRegenHeld (the hold, D-120)", function()
	it("pauses HP regen while set (the Guard Gauge still refills); clearing it resumes the rule", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.applyHit(boarId, artHit(playerId, RAW_HORIZONTAL, 30))
		local record = EntityService.get(boarId)
		local hurt = record.hp
		expect(hurt).toBeLessThan(record.maxHp)
		expect(EntityService.setHpRegenHeld(boarId, true)).toBe(true)
		advance(math.max(Combat.outOfCombatRegenDelay, Combat.guardRegenDelay) + 5)
		expect(record.hp).toBe(hurt)
		expect(record.gauge).toBeGreaterThan(30)
		-- Holding twice changes nothing; the out-of-combat wait is long over, so a release
		-- regenerates on the next step.
		expect(EntityService.setHpRegenHeld(boarId, true)).toBe(true)
		expect(EntityService.setHpRegenHeld(boarId, false)).toBe(true)
		advance(1)
		expect(record.hp).toBeGreaterThan(hurt)
	end)

	it("hits, heal, setHp and the kill still land on a fighter whose regen is held", function()
		fresh()
		local playerId = spawnPlayer()
		local boarId = spawnBoar()
		local record = EntityService.get(boarId)
		expect(EntityService.setHpRegenHeld(boarId, true)).toBe(true)
		expect(EntityService.setHp(boarId, 1)).toBe(1)
		EntityService.heal(boarId, 9)
		expect(record.hp).toBe(10)
		expect(EntityService.setHp(boarId, 1)).toBe(1)
		advance(Combat.outOfCombatRegenDelay + 5)
		expect(record.hp).toBe(1)
		local applied = EntityService.applyHit(boarId, artHit(playerId, RAW_HORIZONTAL, 0))
		expect(applied.killed).toBe(true)
		expect(applied.hitStop).toBe("Kill")
		expect(sentOf("EntityDied")).toHaveLength(1)
	end)

	it("refuses an unknown id and a dead fighter", function()
		fresh()
		local boarId = spawnBoar()
		expect(EntityService.setHpRegenHeld(999, true)).toBe(false)
		EntityService.die(boarId)
		expect(EntityService.setHpRegenHeld(boarId, true)).toBe(false)
		expect(EntityService.setHpRegenHeld(boarId, false)).toBe(false)
	end)
end)

describe("EntityService with a Kobold", function()
	it("a level-1 Horizontal needs 10 to 14 hits (section 9) and Break takes four Verticals", function()
		fresh()
		local playerId = spawnPlayer()
		local model = rigModel("KoboldAxeman", Vector3.new(0, 2.2, -5), Vector3.new(2, 2, 1))
		local koboldId = EntityService.registerEnemy(model, KOBOLD)
		local hits = 0
		while EntityService.isAlive(koboldId) do
			EntityService.applyHit(koboldId, artHit(playerId, RAW_HORIZONTAL, 0))
			hits += 1
		end
		expect(hits).toBeGreaterThanOrEqual(10)
		expect(hits).toBeLessThanOrEqual(14)
		local id2 =
			EntityService.registerEnemy(rigModel("KoboldAxeman", Vector3.new(5, 2.2, -5), Vector3.new(2, 2, 1)), KOBOLD)
		local verticals = 0
		while EntityService.get(id2).state ~= "Break" do
			EntityService.applyHit(id2, artHit(playerId, 1, 35))
			verticals += 1
		end
		expect(verticals).toBe(4) -- 120 gauge / 35 per hit
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Drawn: the server's word on whether a player's sword is out (the combat tag)
-- ------------------------------------------------------------------------------------------

describe("Drawn", function()
	it("a new player publishes Drawn false; an enemy carries no Drawn at all", function()
		fresh()
		local _, character = spawnPlayer()
		local _, boar = spawnBoar()
		expect(character:GetAttribute("Drawn")).toBe(false)
		expect(boar:GetAttribute("Drawn")).toBeNil()
		advance(0.5)
		expect(character:GetAttribute("Drawn")).toBe(false)
		expect(boar:GetAttribute("Drawn")).toBeNil()
	end)

	it("an Art or a basic swing draws the sword in the same publish as the State", function()
		fresh()
		local id, character = spawnPlayer()
		EntityService.setState(id, "Art", 1.0)
		expect(character:GetAttribute("State")).toBe("Art")
		expect(character:GetAttribute("Drawn")).toBe(true)
		local basicId, basic = spawnPlayer("Basic")
		EntityService.setState(basicId, "Art", Combat.basicHitDuration, nil, "Basic")
		expect(basic:GetAttribute("State")).toBe("Art")
		expect(basic:GetAttribute("Drawn")).toBe(true)
		-- CombatService marks combat as it starts a swing; that publishes too.
		local markedId, marked = spawnPlayer("Marked")
		EntityService.markCombat(markedId)
		expect(marked:GetAttribute("Drawn")).toBe(true)
	end)

	it("an Art keeps the sword out through its post-motion, then 6 s more", function()
		fresh()
		local id, character = spawnPlayer()
		EntityService.setState(id, "Art", Combat.combatTagDuration)
		advance(Combat.combatTagDuration - 0.1)
		EntityService.setState(id, "PostMotion", 2)
		advance(1.9)
		expect(character:GetAttribute("State")).toBe("PostMotion")
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(0.2)
		expect(character:GetAttribute("State")).toBe("Idle")
		advance(Combat.combatTagDuration - 0.2)
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(0.2)
		expect(character:GetAttribute("Drawn")).toBe(false)
	end)

	it("a guard draws the sword and holds it out; it goes combatTagDuration after the release", function()
		fresh()
		local id, character = spawnPlayer()
		expect(EntityService.setGuard(id, true)).toBe(true)
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(Combat.combatTagDuration + 1)
		expect(character:GetAttribute("State")).toBe("Guard")
		expect(character:GetAttribute("Drawn")).toBe(true)
		EntityService.setGuard(id, false)
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(Combat.combatTagDuration - 0.1)
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(0.2)
		expect(character:GetAttribute("Drawn")).toBe(false)
	end)

	it("a refused guard does not draw", function()
		fresh()
		local id, character = spawnPlayer()
		EntityService.setState(id, "Stagger", Combat.staggerDuration)
		expect(EntityService.setGuard(id, true)).toBe(false)
		expect(character:GetAttribute("Drawn")).toBe(false)
	end)

	it("a lock-on draws the sword and holds it while the target lives; it goes 6 s after the target dies", function()
		fresh()
		local id, character = spawnPlayer()
		local boarId = spawnBoar()
		expect(EntityService.setTarget(id, boarId)).toBe(true)
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(Combat.combatTagDuration + 1)
		expect(character:GetAttribute("Drawn")).toBe(true)
		EntityService.die(boarId)
		advance(Combat.combatTagDuration - 0.1)
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(0.2)
		expect(character:GetAttribute("Drawn")).toBe(false)
	end)

	it("a lock-on on a fighter that leaves the registry runs out 6 s later", function()
		fresh()
		local id, character = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.setTarget(id, boarId)
		advance(1)
		EntityService.unregister(boarId)
		advance(Combat.combatTagDuration - 0.1)
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(0.2)
		expect(character:GetAttribute("Drawn")).toBe(false)
	end)

	it("clearing the lock-on does not sheathe at once; the tag runs out on its own", function()
		fresh()
		local id, character = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.setTarget(id, boarId)
		advance(1)
		expect(EntityService.setTarget(id, nil)).toBe(true)
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(Combat.combatTagDuration - 0.1)
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(0.2)
		expect(character:GetAttribute("Drawn")).toBe(false)
		-- A refused lock-on (an unknown id) draws nothing.
		expect(EntityService.setTarget(id, 4242)).toBe(false)
		expect(character:GetAttribute("Drawn")).toBe(false)
	end)

	it("a hit draws the attacker's and the target's swords, a parried hit too", function()
		fresh()
		local attackerId, attacker = spawnPlayer("Attacker")
		local boarId = spawnBoar()
		EntityService.applyHit(boarId, artHit(attackerId))
		expect(attacker:GetAttribute("Drawn")).toBe(true)
		local targetId, target = spawnPlayer("Target")
		EntityService.applyHit(targetId, artHit(boarId, 20, 0))
		expect(target:GetAttribute("Drawn")).toBe(true)
		-- One player parries another: nothing lands, both swords are out.
		local leftId, left = spawnPlayer("Left")
		local rightId, right = spawnPlayer("Right")
		local hit = artHit(leftId)
		hit.parried = true
		local result = EntityService.applyHit(rightId, hit)
		expect(result.parried).toBe(true)
		expect(left:GetAttribute("Drawn")).toBe(true)
		expect(right:GetAttribute("Drawn")).toBe(true)
	end)

	it("with no more combat the sword goes back after combatTagDuration", function()
		fresh()
		local id, character = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.applyHit(id, artHit(boarId, 20, 0))
		expect(character:GetAttribute("Drawn")).toBe(true)
		advance(Combat.combatTagDuration - 0.1)
		expect(character:GetAttribute("Drawn")).toBe(true)
		expect(EntityService.inCombat(id)).toBe(true)
		advance(0.2)
		expect(character:GetAttribute("Drawn")).toBe(false)
		expect(EntityService.inCombat(id)).toBe(false)
	end)

	it("a dodge, a stagger or a move does not draw the sword", function()
		fresh()
		local id, character = spawnPlayer()
		EntityService.setState(id, "Dodge", Combat.dodgeDuration)
		expect(character:GetAttribute("State")).toBe("Dodge")
		expect(character:GetAttribute("Drawn")).toBe(false)
		advance(Combat.dodgeDuration + 0.1)
		expect(character:GetAttribute("Drawn")).toBe(false)
		EntityService.setState(id, "Stagger", Combat.staggerDuration)
		EntityService.setState(id, "Moving")
		advance(0.1)
		expect(character:GetAttribute("Drawn")).toBe(false)
	end)

	it("a guard or a lock-on never moves lastCombatAt: HP regen waits on the last hit only", function()
		fresh()
		local id, character = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.applyHit(id, artHit(boarId, 50, 0))
		local record = EntityService.get(id)
		local hitAt = clock.t
		local hurt = record.hp
		expect(record.lastCombatAt).toBe(hitAt)
		advance(1)
		EntityService.setTarget(id, boarId)
		EntityService.setGuard(id, true)
		EntityService.setGuard(id, false)
		expect(record.lastCombatAt).toBe(hitAt)
		advance(Combat.outOfCombatRegenDelay - 1.1)
		expect(record.hp).toBe(hurt)
		advance(1.1)
		-- Still locked on, so still drawn, but the HP has started to come back.
		expect(character:GetAttribute("Drawn")).toBe(true)
		expect(record.hp).toBeGreaterThan(hurt)
		expect(record.lastCombatAt).toBe(hitAt)
	end)

	it("a new character (a respawn) starts sheathed", function()
		fresh()
		local id, character, player = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.applyHit(id, artHit(boarId, 20, 0))
		expect(character:GetAttribute("Drawn")).toBe(true)
		local respawned = rigModel("Tester", Vector3.new(0, 3, 0), Vector3.new(2, 2, 1))
		EntityService.registerPlayer(player, respawned, Playground.loadout)
		expect(EntityService.get(id)).toBeNil()
		expect(respawned:GetAttribute("Drawn")).toBe(false)
	end)
end)
