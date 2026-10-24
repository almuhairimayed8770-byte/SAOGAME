--!strict
-- Instance-level rules of the HUD package that Lune can check: pooled nameplates survive the rig
-- they pointed at, nothing hangs over a dead or boss rig, and the SWITCH prompt never leaves the
-- HUD's own ScreenGui (a target the server removes mid-window must not take the HUD loop down).
-- The text strokes and the SWITCH billboard's size come from ui.luau, never from a literal.
local Engine = Harness.load("src/client/fx/Engine")
local Hud = Harness.load("src/client/ui/Hud")
local Nameplates = Harness.load("src/client/ui/Nameplates")
local EntityTracker = Harness.load("src/client/controllers/EntityTracker")
local UI = Harness.load("src/shared/data/ui")
local Combat = Harness.load("src/shared/data/combat")
local Moments = Harness.load("src/shared/data/moments")

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

	it("holds a dead rig's plate through the freeze, HP bar empty, and lets the shatter take it", function()
		local model, id = rig("Enemy")
		EntityTracker.track(model)
		task.wait()
		setAttribute(model, "HP", 0)
		setAttribute(model, "State", "Dead")
		task.wait()
		local plate = Nameplates.plateOf(id)
		expect(plate.gui.Enabled).toBe(true)
		expect((plate.hpFill :: any).Size.X.Scale).toBe(0)
		-- The shatter frame: the rig turns to shards and the plate goes with it.
		Nameplates.hide(model)
		expect(plate.gui.Enabled).toBe(false)
		-- Nothing brings it back while the rig lingers: a late attribute, the fade loop.
		setAttribute(model, "Guard", 0)
		Nameplates.update()
		expect(plate.gui.Enabled).toBe(false)
		-- The pool hands it on whole.
		EntityTracker.untrack(model)
		task.wait()
		local next, nextId = rig("Enemy")
		EntityTracker.track(next)
		task.wait()
		expect(Nameplates.plateOf(nextId).gui.Enabled).toBe(true)
	end)

	it("drops a dead rig's plate when its shatter is due even if nothing hid it", function()
		local model, id = rig("Enemy")
		EntityTracker.track(model)
		task.wait()
		setAttribute(model, "State", "Dead")
		task.wait()
		local plate = Nameplates.plateOf(id)
		local due = Moments.deathDuckDelay() + Combat.deathFreeze
		clock += due - 0.01
		Nameplates.update()
		expect(plate.gui.Enabled).toBe(true)
		clock += 0.02
		Nameplates.update()
		expect(plate.gui.Enabled).toBe(false)
	end)

	it("ignores a hide for a rig with no plate", function()
		expect(function()
			Nameplates.hide(Instance.new("Model"))
		end).never.toThrow()
	end)

	it("draws no plate over a boss", function()
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

	it("draws the name's stroke from ui.luau and fades it with the plate", function()
		local model, id = rig("Enemy")
		EntityTracker.track(model)
		task.wait()
		local plate = Nameplates.plateOf(id)
		local stroke = UI.nameplates.strokeTransparency
		expect(plate.name.TextStrokeTransparency).toBeCloseTo(stroke, 1e-6)
		-- The viewer steps half-way into the fade band: the stroke fades at the name's rate.
		local halfway = UI.nameplates.distance + UI.nameplates.fadeBand * 0.5
		Engine.setViewer(function()
			return Vector3.new(0, 0, halfway)
		end)
		Nameplates.update()
		expect(plate.name.TextTransparency).toBeCloseTo(0.5, 1e-6)
		expect(plate.name.TextStrokeTransparency).toBeCloseTo(stroke + (1 - stroke) * 0.5, 1e-6)
		-- Past the band the stroke is gone with the name.
		Engine.setViewer(function()
			return Vector3.new(0, 0, UI.nameplates.distance + UI.nameplates.fadeBand * 2)
		end)
		Nameplates.update()
		expect(plate.name.TextTransparency).toBe(1)
		expect(plate.name.TextStrokeTransparency).toBe(1)
		Engine.setViewer(function()
			return Vector3.zero
		end)
	end)
end)

describe("Hud SWITCH prompt (instances)", function()
	Hud.start()

	it("keeps the corner clear of the engine's top bar on every screen: the HUD sits in the safe area", function()
		local gui = Hud.gui()
		-- IgnoreGuiInset true would draw the corner under the top bar (its menu and chat buttons).
		expect(gui.IgnoreGuiInset).toBe(false)
		expect(UI.hud.screenInsets).toBe("CoreUISafeInsets")
		expect(gui.ScreenInsets).toBe(Enum.ScreenInsets.CoreUISafeInsets)
		local corner = gui:FindFirstChild("TopLeft")
		expect(corner).never.toBeNil()
		expect(corner.Position).toEqual(UDim2.fromOffset(UI.hud.margin, UI.hud.margin))
		-- The vignette still covers the whole screen, from its own gui just under the HUD.
		expect(gui:FindFirstChild("VignetteTop", true)).toBeNil()
		local vignette = Hud.vignetteGui()
		expect(vignette.Name).toBe(UI.hud.vignetteGuiName)
		expect(vignette.IgnoreGuiInset).toBe(true)
		expect(vignette.DisplayOrder).toBeLessThan(gui.DisplayOrder)
		expect(#vignette:GetChildren()).toBeGreaterThan(0)
	end)

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
		expect(label.TextStrokeTransparency).toBeCloseTo(UI.hud.textStrokeTransparency, 1e-6)
		local size = UI.hud.switchPrompt.billboardSize
		expect(billboard.Size.X.Offset).toBe(size.width)
		expect(billboard.Size.Y.Offset).toBe(size.height)
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
