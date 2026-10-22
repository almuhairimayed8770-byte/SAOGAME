--!strict
local EntityTracker = Harness.load("src/client/controllers/EntityTracker")

-- A minimal RBXScriptSignal stand-in: Connect returns a connection with Disconnect; Fire runs handlers.
local function fakeSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(handler)
		local record = { handler = handler, Connected = true }
		table.insert(handlers, record)
		return {
			Disconnect = function()
				record.Connected = false
				local index = table.find(handlers, record)
				if index then
					table.remove(handlers, index)
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, record in table.clone(handlers) do
			if record.Connected then
				record.handler(...)
			end
		end
	end
	function signal:count()
		return #handlers
	end
	return signal
end

local function entityModel(attributes)
	local model = Instance.new("Model")
	model.Name = attributes.DisplayName or "Entity"
	for name, value in attributes do
		model:SetAttribute(name, value)
	end
	return model
end

-- Builds a fresh tracker environment: a stubbed CollectionService shape and attribute signals.
local function fresh(initialTagged, localCharacter)
	EntityTracker.reset()
	local env = {
		tagged = initialTagged or {},
		added = fakeSignal(),
		removed = fakeSignal(),
		characterAdded = fakeSignal(),
		attributeSignals = {},
		localCharacter = localCharacter,
	}
	local function attributeSignal(model, attribute)
		local perModel = env.attributeSignals[model]
		if perModel == nil then
			perModel = {}
			env.attributeSignals[model] = perModel
		end
		local signal = perModel[attribute]
		if signal == nil then
			signal = fakeSignal()
			perModel[attribute] = signal
		end
		return signal
	end
	env.attributeSignal = attributeSignal
	EntityTracker.bind({
		tagged = function()
			return env.tagged
		end,
		instanceAdded = function(handler)
			env.added:Connect(handler)
		end,
		instanceRemoved = function(handler)
			env.removed:Connect(handler)
		end,
		attributeChanged = function(model, attribute, handler)
			return attributeSignal(model, attribute):Connect(handler)
		end,
		localCharacter = function()
			return env.localCharacter
		end,
		characterAdded = function(handler)
			env.characterAdded:Connect(handler)
		end,
	})
	-- Set an attribute the way the server would, then fire the matching change signal.
	function env.setAttribute(model, attribute, value)
		model:SetAttribute(attribute, value)
		attributeSignal(model, attribute):Fire()
	end
	return env
end

local boarAttributes = {
	EntityId = 7,
	EntityKind = "Enemy",
	DefId = "FrenzyBoar",
	Rig = "Boar",
	DisplayName = "Frenzy Boar",
	HP = 120,
	MaxHP = 120,
	Gauge = 40,
	MaxGauge = 40,
	State = "Idle",
	Level = 1,
}

describe("EntityTracker", function()
	it("turns tagged models into records with every attribute", function()
		local boar = entityModel(boarAttributes)
		fresh({ boar })
		local addedRecords = {}
		EntityTracker.added:Connect(function(record)
			table.insert(addedRecords, record)
		end)
		EntityTracker.wire()
		local record = EntityTracker.get(7)
		expect(record).never.toBeNil()
		expect(record.model).toBe(boar)
		expect(record.kind).toBe("Enemy")
		expect(record.defId).toBe("FrenzyBoar")
		expect(record.rig).toBe("Boar")
		expect(record.name).toBe("Frenzy Boar")
		expect(record.hp).toBe(120)
		expect(record.maxHp).toBe(120)
		expect(record.gauge).toBe(40)
		expect(record.maxGauge).toBe(40)
		expect(record.state).toBe("Idle")
		expect(record.level).toBe(1)
		expect(record.cursor).toBeNil()
		expect(EntityTracker.fromModel(boar)).toBe(record)
		expect(#addedRecords).toBe(1)
		expect(addedRecords[1]).toBe(record)
	end)

	it("reads the server's Elite label into record.elite, false when the model has none", function()
		local boar = entityModel(boarAttributes)
		local eliteAttributes = table.clone(boarAttributes)
		eliteAttributes.EntityId = 8
		eliteAttributes.Elite = true
		local elite = entityModel(eliteAttributes)
		local env = fresh({ boar, elite })
		EntityTracker.wire()
		expect(EntityTracker.get(7).elite).toBe(false)
		expect(EntityTracker.get(8).elite).toBe(true)
		-- A label the server takes off (or never set) reads as false again.
		env.setAttribute(elite, "Elite", nil)
		expect(EntityTracker.get(8).elite).toBe(false)
		env.setAttribute(boar, "Elite", true)
		expect(EntityTracker.get(7).elite).toBe(true)
	end)

	it("tracks models tagged later and waits for the EntityId attribute", function()
		local env = fresh({})
		EntityTracker.wire()
		local kobold = entityModel({ EntityKind = "Enemy", Rig = "Kobold", DisplayName = "Kobold Axeman" })
		env.added:Fire(kobold)
		expect(EntityTracker.fromModel(kobold)).toBeNil()
		expect(#EntityTracker.all()).toBe(0)
		env.setAttribute(kobold, "EntityId", 12)
		local record = EntityTracker.get(12)
		expect(record).never.toBeNil()
		expect(record.rig).toBe("Kobold")
		expect(record.hp).toBe(0)
		expect(record.state).toBe("Idle")
	end)

	it("re-publishes attribute changes on the changed Signal and updates the record", function()
		local boar = entityModel(boarAttributes)
		local env = fresh({ boar })
		EntityTracker.wire()
		local record = EntityTracker.get(7)
		local seen = {}
		EntityTracker.changed:Connect(function(changedRecord, attribute, value)
			table.insert(seen, { record = changedRecord, attribute = attribute, value = value })
		end)
		env.setAttribute(boar, "HP", 80)
		env.setAttribute(boar, "State", "Stagger")
		env.setAttribute(boar, "Cursor", nil)
		expect(record.hp).toBe(80)
		expect(record.state).toBe("Stagger")
		expect(#seen).toBe(3)
		expect(seen[1].record).toBe(record)
		expect(seen[1].attribute).toBe("HP")
		expect(seen[1].value).toBe(80)
		expect(seen[2].attribute).toBe("State")
		expect(seen[2].value).toBe("Stagger")
		expect(seen[3].attribute).toBe("Cursor")
		expect(seen[3].value).toBeNil()
	end)

	it("forgets removed models, disconnects their watchers and fires removed", function()
		local boar = entityModel(boarAttributes)
		local env = fresh({ boar })
		EntityTracker.wire()
		local record = EntityTracker.get(7)
		local removedRecords = {}
		EntityTracker.removed:Connect(function(removed)
			table.insert(removedRecords, removed)
		end)
		expect(env.attributeSignal(boar, "HP"):count()).toBe(1)
		env.removed:Fire(boar)
		expect(EntityTracker.get(7)).toBeNil()
		expect(EntityTracker.fromModel(boar)).toBeNil()
		expect(#removedRecords).toBe(1)
		expect(removedRecords[1]).toBe(record)
		expect(env.attributeSignal(boar, "HP"):count()).toBe(0)
		-- A late attribute change on the removed model is ignored.
		env.setAttribute(boar, "HP", 1)
		expect(record.hp).toBe(120)
	end)

	it("lists every record sorted by id", function()
		local a = entityModel({ EntityId = 30, EntityKind = "Enemy", Rig = "Boar" })
		local b = entityModel({ EntityId = 4, EntityKind = "Player", Rig = "PlayerR15", DisplayName = "Mira" })
		local c = entityModel({ EntityId = 18, EntityKind = "Enemy", Rig = "Kobold" })
		fresh({ a, b, c })
		EntityTracker.wire()
		local ids = {}
		for _, record in EntityTracker.all() do
			table.insert(ids, record.id)
		end
		expect(ids).toEqual({ 4, 18, 30 })
	end)

	it("resolves the local id from the local character and wakes waiters", function()
		local me = entityModel({
			EntityId = 4,
			EntityKind = "Player",
			Rig = "PlayerR15",
			DisplayName = "Mira",
			Cursor = "Green",
		})
		local env = fresh({}, me)
		EntityTracker.wire()
		expect(EntityTracker.peekLocalId()).toBeNil()
		local resolved = nil
		local localIds = {}
		EntityTracker.localChanged:Connect(function(id)
			table.insert(localIds, { id = id })
		end)
		task.spawn(function()
			resolved = EntityTracker.localId()
		end)
		expect(resolved).toBeNil()
		env.added:Fire(me)
		expect(resolved).toBe(4)
		expect(EntityTracker.peekLocalId()).toBe(4)
		expect(EntityTracker.localId()).toBe(4)
		expect(EntityTracker.isLocal(4)).toBe(true)
		expect(EntityTracker.isLocal(5)).toBe(false)
		expect(EntityTracker.localRecord().name).toBe("Mira")
		expect(localIds).toEqual({ { id = 4 } })
		-- The character leaving clears the local id.
		env.removed:Fire(me)
		expect(EntityTracker.peekLocalId()).toBeNil()
		expect(#localIds).toBe(2)
		expect(localIds[2].id).toBeNil()
	end)

	it("resolves the local id when the character spawns after its model was tagged", function()
		local me = entityModel({ EntityId = 9, EntityKind = "Player", Rig = "PlayerR15" })
		local env = fresh({ me }, nil)
		EntityTracker.wire()
		expect(EntityTracker.peekLocalId()).toBeNil()
		env.localCharacter = me
		env.characterAdded:Fire(me)
		expect(EntityTracker.peekLocalId()).toBe(9)
	end)
end)
