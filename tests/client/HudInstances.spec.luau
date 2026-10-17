-- Instance-level rules of the HUD package that Lune can check: pooled nameplates survive the rig
-- they pointed at, nothing hangs over a dead or boss rig, and the SWITCH prompt never leaves the
-- HUD's own ScreenGui (a target the server removes mid-window must not take the HUD loop down).
local Engine = Harness.load("src/client/fx/Engine")
local Hud = Harness.load("src/client/ui/Hud")
local Nameplates = Harness.load("src/client/ui/Nameplates")
local EntityTracker = Harness.load("src/client/controllers/EntityTracker")
local UI = Harness.load("src/shared/data/ui")
local Combat = Harness.load("src/shared/data/combat")

Engine.setViewer(function()
	return Vector3.zero
end)
-- The HUD's fades read Engine.now(); a hand-driven clock lets the specs step past the window.
local clock = 100
Engine.setClock(function()
	return clock
end)

local world = Instance.new("Folder")
local handlers: { [any]: { [string]: () -> () } } = {}

EntityTracker.bind({
	tagged = function()
		return {}
	end,
	instanceAdded = function() end,
	instanceRemoved = function() end,
	attributeChanged = function(model, attribute, handler)
		handlers[model] = handlers[model] or {}
		handlers[model][attribute] = handler
		return { Disconnect = function() end }
	end,
	localCharacter = function()
		return nil
	end,
	characterAdded = function() end,
})

local nextId = 500
local function rig(kind: string, boss: boolean?)
	nextId += 1
	local model = Instance.new("Model")
	model.Name = kind .. nextId
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("EntityId", nextId)
	model:SetAttribute("EntityKind", kind)
	model:SetAttribute("DisplayName", model.Name)
	model:SetAttribute("HP", 100)
	model:SetAttribute("MaxHP", 100)
	model:SetAttribute("State", "Idle")
	if boss then
		model:SetAttribute(UI.nameplates.bossAttribute, true)
	end
	model.Parent = world
	return model, nextId
end

local function setAttribute(model, attribute: string, value)
	model:SetAttribute(attribute, value)
	local handler = handlers[model] and handlers[model][attribute]
	if handler ~= nil then
		handler()
	end
end

describe("Nameplates (instances)", function()
	Nameplates.start()

	it("parents every plate to the nameplate folder and points at the rig through Adornee", function()
		local model, id = rig("Enemy")
		EntityTracker.track(model)
		task.wait()
		local plate = Nameplates.plateOf(id)
		expect(plate).never.toBeNil()
		expect(plate.gui.Parent.Name).toBe(UI.nameplates.folderName)
		expect(plate.gui.Parent).never.toBe(model)
		expect(plate.gui.Adornee).toBe(model.PrimaryPart)
		expect(plate.gui.Enabled).toBe(true)
	end)

	it("returns a removed rig's plate to the pool and the next rig gets a live plate", function()
		local first, firstId = rig("Enemy")
		EntityTracker.track(first)
		task.wait()
		local plate = Nameplates.plateOf(firstId)
		EntityTracker.untrack(first)
		task.wait()
		expect(Nameplates.plateOf(firstId)).toBeNil()
		expect(plate.gui.Enabled).toBe(false)
		-- The rig is gone; a plate that lived inside it would be gone too.
		first:Destroy()
		local second, secondId = rig("Enemy")
		EntityTracker.track(second)
		task.wait()
		local reused = Nameplates.plateOf(secondId)
		expect(reused).never.toBeNil()
		expect(reused.gui.Enabled).toBe(true)
		expect(reused.gui.Parent.Name).toBe(UI.nameplates.folderName)
		expect(reused.gui.Adornee).toBe(second.PrimaryPart)
	end)

	it("hides the plate of a dead rig and draws none over a boss", function()
		local model, id = rig("Enemy")
		EntityTracker.track(model)
		task.wait()
		setAttribute(model, "State", "Dead")
		task.wait()
		expect(Nameplates.plateOf(id).gui.Enabled).toBe(false)

		local seen = nil
		Nameplates.bossSeen:Connect(function(record)
			seen = record
		end)
		local boss, bossId = rig("Enemy", true)
		EntityTracker.track(boss)
		task.wait()
		expect(Nameplates.plateOf(bossId)).toBeNil()
		expect(seen).never.toBeNil()
		expect(seen.id).toBe(bossId)
	end)
end)

describe("Hud SWITCH prompt (instances)", function()
	Hud.start()

	it("keeps the billboard under the HUD gui and only adorns the target", function()
		local target = rig("Enemy")
		EntityTracker.track(target)
		task.wait()
		Hud.showSwitchPrompt(Combat.switchWindow, target, "Brann")
		local gui = Hud.gui()
		local billboard = gui:FindFirstChild("SwitchBillboard")
		expect(billboard).never.toBeNil()
		expect(billboard.Parent).toBe(gui)
		expect(billboard.Enabled).toBe(true)
		expect(billboard.Adornee).toBe(target.PrimaryPart)
		local label = billboard:FindFirstChild("SwitchPrompt")
		expect(label).never.toBeNil()
		expect(label.Text).toBe(UI.hud.switchPrompt.text)
		expect(label.TextTransparency).toBe(0)
		expect(label:FindFirstChild("Caller").Text).toBe("Brann")
		-- Nothing of the prompt lives inside the rig.
		for _, descendant in target:GetDescendants() do
			expect(descendant:IsA("BillboardGui")).toBe(false)
		end
		-- The target dies and is removed mid-window: the loop keeps running and the label comes home.
		EntityTracker.untrack(target)
		target:Destroy()
		clock += Combat.switchWindow * UI.hud.switchPrompt.fadeOutFraction * 0.5 -- mid-hold
		Hud.step(1 / 60)
		expect(label.TextTransparency).toBe(0)
		clock += Combat.switchWindow
		Hud.step(1 / 60)
		expect(billboard.Enabled).toBe(false)
		expect(gui:FindFirstChild("SwitchPrompt")).toBe(label)
		expect(label.TextTransparency).toBe(1)
	end)

	it("shows SWITCH on screen when no target is known and fades inside the window", function()
		Hud.showSwitchPrompt(Combat.switchWindow, nil, nil)
		local gui = Hud.gui()
		local label = gui:FindFirstChild("SwitchPrompt")
		expect(label).never.toBeNil()
		expect(label.Parent).toBe(gui)
		expect(label.TextTransparency).toBe(0)
		expect(gui:FindFirstChild("SwitchBillboard").Enabled).toBe(false)
		clock += Combat.switchWindow * (1 + UI.hud.switchPrompt.fadeOutFraction) * 0.5
		Hud.step(1 / 60)
		expect(label.TextTransparency).toBeGreaterThan(0)
		expect(label.TextTransparency).toBeLessThan(1)
		clock += Combat.switchWindow
		Hud.step(1 / 60)
		expect(label.TextTransparency).toBe(1)
		Engine.setClock(nil)
	end)
end)
