--!strict
--[[
	A held enemy stands upright on this client too (D-508, the client side of D-494). The server
	turns its enemy Humanoids' fall states off (ai.upright.offStates) on the frame each model is made,
	but Humanoid:SetStateEnabled does not replicate. The real EntityTracker meets the models the way
	Studio hands them over (the SkyspireEntity tag's InstanceAdded, the attributes the server
	published), the real Replication watches them, and the rigs are RigBuilder's own. The fake engine
	behind deps.keepUpright is this client's copy of each Humanoid, doing what the owner's PC
	measured in Studio on 0582a04 (item 398(a), staged shots 1, 6 and 11):

	- the server's SetStateEnabled does not reach the copy: GetStateEnabled(FallingDown) reads true;
	- a copy whose root comes anchored (a staged enemy is held from its spawn, D-436) reads
	  FallingDown on every row while it is held and anchored (183 to 196 rows a take), unless
	  FallingDown was turned off before this client's first physics step on it;
	- from the row its root is let go it reads the server's state (Running);
	- its root stays at its standing height throughout (nothing visible was measured).

	Assumed, not measured: the tag's InstanceAdded runs before this client's first physics step on
	the model, as the server's keepUpright runs before the server's (Studio's deferred signals run
	the replication batch's handlers before the frame's simulation). Item 398(e) logs it.
]]

local EntityTracker = Harness.load("src/client/controllers/EntityTracker")
local Replication = Harness.load("src/client/controllers/Replication")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local AI = Harness.load("src/shared/data/ai")

-- The PC's longest held stretch in a take (rows from the spawn to the release, 398(a)).
local HELD_ROWS = 196
local AFTER_ROWS = 60

local function fakeSignal(): any
	local handlers: { (...any) -> () } = {}
	return {
		Connect = function(_, handler)
			table.insert(handlers, handler)
			return {
				Disconnect = function()
					local index = table.find(handlers, handler)
					if index ~= nil then
						table.remove(handlers, index)
					end
				end,
			}
		end,
		Fire = function(_, ...)
			for _, handler in table.clone(handlers) do
				handler(...)
			end
		end,
	}
end

local function recorder(): any
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

-- This client's copy of a Humanoid as Studio ran it (above).
type Copy = {
	state: string,
	enabled: { [string]: boolean },
	stepped: boolean,
	asked: number, -- how often keepUpright reached it
	askedSteps: number?, -- the physics steps it had had when it was first asked
	fallingRows: number,
	enabledOnFirstRow: boolean?, -- GetStateEnabled(FallingDown) on the staged frame
}

type World = {
	copies: { [Instance]: Copy },
	tag: (model: Model) -> (), -- the replication batch that brings a tagged model to this client
	step: () -> (), -- one rendered row: this client's physics on every copy it has met
	localModel: Model,
}

local function newCopy(): Copy
	return {
		state = "Running",
		enabled = { FallingDown = true, Ragdoll = true },
		stepped = false,
		asked = 0,
		askedSteps = nil,
		fallingRows = 0,
		enabledOnFirstRow = nil,
	}
end

local function rootOf(model: Model): BasePart
	return model.PrimaryPart :: BasePart
end

local function player(id: number, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Parent = model
	model.PrimaryPart = root
	Instance.new("Humanoid").Parent = model
	model:SetAttribute("EntityId", id)
	model:SetAttribute("EntityKind", "Player")
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("DisplayName", name)
	return model
end

-- An enemy as EnemyService makes it for a staged take: RigBuilder's rig, held (anchored) from its
-- spawn, published as EntityService publishes it.
local function enemy(id: number, rigId: string, defId: string): Model
	local model = RigBuilder.build(rigId, defId)
	rootOf(model).Anchored = true
	model:SetAttribute("EntityId", id)
	model:SetAttribute("EntityKind", "Enemy")
	model:SetAttribute("DefId", defId)
	model:SetAttribute("Rig", rigId)
	model:SetAttribute("DisplayName", defId)
	return model
end

local function world(withSeam: boolean, onField: { Model }): World
	EntityTracker.reset()
	local copies: { [Instance]: Copy } = {}
	local localModel = player(1, "Trialist")
	local added = fakeSignal()
	local function copyOf(model: Instance): Copy
		local humanoid = (model :: Model):FindFirstChildOfClass("Humanoid") :: Instance
		local copy = copies[humanoid]
		if copy == nil then
			copy = newCopy()
			copies[humanoid] = copy
		end
		return copy
	end
	EntityTracker.bind({
		tagged = function()
			return onField
		end,
		instanceAdded = function(handler)
			added:Connect(handler)
		end,
		instanceRemoved = function() end,
		attributeChanged = function()
			return { Disconnect = function() end }
		end,
		localCharacter = function()
			return localModel
		end,
		characterAdded = function() end,
	})
	-- Main.client's order: the tracker first (it tracks what is already on the field), then Replication.
	EntityTracker.wire()
	local deps: any = {
		net = { on = function() end },
		entities = EntityTracker,
		localId = EntityTracker.peekLocalId,
		localCharacter = function()
			return localModel
		end,
		locomotion = recorder(),
		choreo = {
			get = function()
				return { events = fakeSignal() }
			end,
		},
		clipLibrary = {
			has = function()
				return true
			end,
		},
		trails = recorder(),
		smear = recorder(),
		shatter = recorder(),
		sparks = recorder(),
		telegraphs = recorder(),
		outline = recorder(),
		switchRing = recorder(),
		digits = recorder(),
		hud = recorder(),
		systemLine = recorder(),
		sfx = recorder(),
		impact = recorder(),
		camera = recorder(),
		weaponCategory = function()
			return "OneHandedSword"
		end,
		trailToken = function()
			return "TrailCyanWhite"
		end,
		positionOf = function()
			return Vector3.zero
		end,
		schedule = function() end,
	}
	if withSeam then
		-- Replication.start's seam on this client's copy: the real loop over ai.upright.offStates,
		-- each Humanoid:SetStateEnabled reaching the copy.
		deps.keepUpright = function(model: Model)
			local copy = copyOf(model)
			copy.asked += 1
			if copy.askedSteps == nil then
				copy.askedSteps = if copy.stepped then 1 else 0
			end
			Replication.keepUpright({
				SetStateEnabled = function(_self: any, stateType: any, on: boolean)
					copy.enabled[stateType.Name] = on
				end,
			})
		end
	end
	Replication.bind(deps)
	return {
		copies = copies,
		localModel = localModel,
		tag = function(model: Model)
			copyOf(model)
			added:Fire(model)
		end,
		step = function()
			for _, record in EntityTracker.all() do
				local copy = copyOf(record.model)
				local root = rootOf(record.model)
				if copy.enabledOnFirstRow == nil then
					copy.enabledOnFirstRow = copy.enabled.FallingDown
				end
				local first = not copy.stepped
				copy.stepped = true
				if root.Anchored then
					if first and copy.enabled.FallingDown and copy.state == "Running" then
						copy.state = "FallingDown"
					end
				else
					copy.state = "Running" -- the server's state, once the root is let go
				end
				if copy.state == "FallingDown" then
					copy.fallingRows += 1
				end
			end
		end,
	}
end

-- A staged take on this client: the shot's enemies come in one batch, held HELD_ROWS rows, then let go.
local function take(withSeam: boolean): (World, { Model })
	local onField = enemy(9, "Kobold", "KoboldAxeman") -- a field enemy already there when the client starts
	local w = world(withSeam, { onField })
	local remote = player(2, "Partner")
	w.tag(w.localModel)
	w.tag(remote)
	local boar = enemy(7, "Boar", "FrenzyBoar")
	local kobold = enemy(8, "Kobold", "KoboldAxeman")
	w.tag(boar)
	w.tag(kobold)
	for _ = 1, HELD_ROWS do
		w.step()
	end
	for _, model in { boar, kobold, onField } do
		rootOf(model).Anchored = false
	end
	for _ = 1, AFTER_ROWS do
		w.step()
	end
	return w, { boar, kobold, onField, w.localModel, remote }
end

local function copyOf(w: World, model: Model): Copy
	return w.copies[model:FindFirstChildOfClass("Humanoid") :: Instance]
end

describe("A held enemy stands upright on this client (D-508)", function()
	it("turns the fall states off on every enemy's copy the frame it is met: no FallingDown row", function()
		local w, models = take(true)
		for index = 1, 3 do
			local copy = copyOf(w, models[index])
			-- 0582a04: FallingDown on 196 of 196 held rows (the PC's 183 to 196), never asked
			expect(copy.asked).toBe(1)
			expect(copy.askedSteps).toBe(0)
			expect(copy.enabledOnFirstRow).toBe(false)
			expect(copy.fallingRows).toBe(0)
			expect(copy.state).toBe("Running")
			for _, name in AI.upright.offStates do
				expect(copy.enabled[name]).toBe(false)
			end
		end
	end)

	it("never touches a player's character, the local one or another's", function()
		local w, models = take(true)
		for index = 4, 5 do
			local copy = copyOf(w, models[index])
			expect(copy.asked).toBe(0)
			expect(copy.enabled.FallingDown).toBe(true)
			expect(copy.enabled.Ragdoll).toBe(true)
		end
	end)

	it("without the seam the held copies read FallingDown from the spawn to the release", function()
		local w, models = take(false)
		for index = 1, 3 do
			local copy = copyOf(w, models[index])
			expect(copy.enabledOnFirstRow).toBe(true)
			expect(copy.fallingRows).toBe(HELD_ROWS)
		end
	end)

	it("keepUpright turns off exactly the data's fall states, as the server does", function()
		local calls: { { string | boolean } } = {}
		Replication.keepUpright({
			SetStateEnabled = function(_self: any, stateType: any, on: boolean)
				table.insert(calls, { stateType.Name, on })
			end,
		})
		expect(#calls).toBe(#AI.upright.offStates)
		for index, name in AI.upright.offStates do
			expect(calls[index][1]).toBe(name)
			expect(calls[index][2]).toBe(false)
		end
	end)
end)
