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
local Shatter = Harness.load("src/client/fx/Shatter")
local SfxPool = Harness.load("src/client/audio/SfxPool")

-- The pool's seams with nothing to hear: the shatter's cue plays into the void.
local quietSounds = {
	now = function(): number
		return 0
	end,
	delay = function(_seconds: number, _fn: () -> ()) end,
	onStep = function(_fn: (number) -> ()): () -> ()
		return function() end
	end,
	play = function(_sound: Sound): boolean
		return true
	end,
	stop = function(_sound: Sound) end,
	timeLength = function(_sound: Sound): number
		return 30
	end,
	preload = function(_sounds: { Instance }) end,
}

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
-- `rootLater`: the root part is in the model but not yet its PrimaryPart (the engine's replication
-- can tag a spawned rig before its PrimaryPart reference resolves).
local function rig(kind: string, boss: boolean?, rootLater: boolean?)
	nextId += 1
	local model = Instance.new("Model")
	model.Name = kind .. nextId
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = model
	if not rootLater then
		model.PrimaryPart = root
	end
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

	-- A rig the server spawns is tagged before its root part's reference replicates: the plate is
	-- handed out with PrimaryPart still nil, and a BillboardGui on a Model draws at the Model's
	-- bounding-box centre (the PC on 318f0a3, AP 489: 0.68 up and 1.16 toward the snout of the
	-- root), so the hand-back's last row jumped the plate there off the drawn body. Every plate
	-- goes onto the root part as soon as the rig has one.
	it("moves a plate handed out before its rig had a root part onto that root part when it arrives", function()
		local model, id = rig("Enemy", false, true)
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		EntityTracker.track(model)
		task.wait()
		local plate = Nameplates.plateOf(id)
		expect(plate).never.toBeNil()
		expect(plate.gui.Adornee).toBe(model)
		model.PrimaryPart = root
		Nameplates.step(1 / 60)
		-- 318f0a3 kept the Model it read at attach.
		expect(plate.gui.Adornee).toBe(root)
		EntityTracker.untrack(model)
		task.wait()
	end)

	it(
		"hands a plate its root part while a rush draws the body on its Torso, and puts it there at the hand-back",
		function()
			local DrawnBody = Harness.load("src/client/choreo/DrawnBody")
			local model, id = rig("Enemy", false, true)
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
			local torso = Instance.new("Part")
			torso.Name = "Torso"
			torso.Parent = model
			root.CFrame = CFrame.new(10, 3, 20)
			root.Position = root.CFrame.Position
			torso.CFrame = CFrame.new(10, 3.4, 14)
			torso.Position = torso.CFrame.Position
			EntityTracker.track(model)
			task.wait()
			local plate = Nameplates.plateOf(id)
			expect(plate).never.toBeNil()
			local lift = Vector3.new(0, UI.nameplates.enemy.offsetStuds, 0)
			-- The run: the body drawn on the Torso 6 studs ahead of the root.
			local at = CFrame.new(10, 3, 14)
			DrawnBody.publish(model, CFrame.new(0, 0, -6), torso, at)
			expect(plate.gui.Adornee).toBe(torso)
			model.PrimaryPart = root
			Nameplates.step(1 / 60)
			-- The root arriving never pulls the plate off the drawn body.
			expect(plate.gui.Adornee).toBe(torso)
			local place = torso.Position + plate.gui.StudsOffsetWorldSpace
			expect((place - (at.Position + lift)).Magnitude).toBeLessThan(1e-4)
			-- The hand-back's last row: the body back on its root, and the plate with it (318f0a3 gave
			-- the plate back to the Model it read at attach).
			DrawnBody.publish(model, nil)
			expect(plate.gui.Adornee).toBe(root)
			expect((plate.gui.StudsOffsetWorldSpace - lift).Magnitude).toBeLessThan(1e-4)
			EntityTracker.untrack(model)
			task.wait()
		end
	)

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

	it("goes on the shatter frame itself: Shatter.play takes the plate as it hides the rig (D-147)", function()
		local model, id = rig("Enemy")
		local torso = Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Parent = model
		EntityTracker.track(model)
		task.wait()
		setAttribute(model, "HP", 0)
		setAttribute(model, "State", "Dead")
		task.wait()
		local plate = Nameplates.plateOf(id)
		expect(plate.gui.Enabled).toBe(true)
		-- Well inside the fallback: only the shatter itself can take the plate now.
		clock += 0.01
		Nameplates.update()
		expect(plate.gui.Enabled).toBe(true)
		SfxPool.bind(quietSounds)
		local ok, err = pcall(Shatter.play, model, "Beast")
		SfxPool.reset()
		SfxPool.bind(nil)
		if not ok then
			error(err, 0)
		end
		-- The same frame the rig turns to shards: no update, no Heartbeat in between.
		expect(torso.LocalTransparencyModifier).toBe(1)
		expect(plate.gui.Enabled).toBe(false)
		-- And it stays gone while the rig lingers, the fallback timer still in place.
		setAttribute(model, "Guard", 0)
		Nameplates.update()
		expect(plate.gui.Enabled).toBe(false)
		expect(plate.dueAt).never.toBeNil()
		EntityTracker.untrack(model)
		task.wait()
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
		-- Only the full-screen effects reach past the safe area (D-475); the HUD stays clipped to it.
		expect(gui.ClipToDeviceSafeArea).toBe(true)
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

	-- The prompt's target is the EntityTracker record's model, tracked from its tag, which can come
	-- before its PrimaryPart reference replicates (D-571): a window opened on it then (a partner's
	-- Art connecting with a boar as it spawns) put SWITCH on the Model, which the engine draws at
	-- the bounding box's centre, for the whole window. It goes onto the root part when it arrives.
	it("moves SWITCH shown over a rig with no root part yet onto that root part when it arrives (D-583)", function()
		local DrawnBody = Harness.load("src/client/choreo/DrawnBody")
		local target = rig("Enemy", false, true)
		local root = target:FindFirstChild("HumanoidRootPart") :: BasePart
		EntityTracker.track(target)
		task.wait()
		Hud.showSwitchPrompt(Combat.switchWindow, target, nil)
		local billboard = Hud.gui():FindFirstChild("SwitchBillboard") :: BillboardGui
		local lift = Vector3.new(0, UI.hud.switchPrompt.heightStuds, 0)
		expect(billboard.Enabled).toBe(true)
		expect(billboard.Adornee).toBe(target)
		target.PrimaryPart = root
		Hud.step(1 / 60)
		-- 81b8fef kept the Model it read when the prompt showed.
		expect(billboard.Adornee).toBe(root)
		expect((billboard.StudsOffsetWorldSpace - lift).Magnitude).toBeLessThan(1e-4)
		Hud.step(1 / 60)
		expect(billboard.Adornee).toBe(root)

		-- A second window over a rig a rush draws on its Torso: the root arriving leaves SWITCH on the
		-- drawn body, and the hand-back puts it on the root part, not the Model.
		local rushing = rig("Enemy", false, true)
		local rushingRoot = rushing:FindFirstChild("HumanoidRootPart") :: BasePart
		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Parent = rushing
		rushingRoot.CFrame = CFrame.new(10, 3, 20)
		rushingRoot.Position = rushingRoot.CFrame.Position
		torso.CFrame = CFrame.new(10, 3.4, 14)
		torso.Position = torso.CFrame.Position
		EntityTracker.track(rushing)
		task.wait()
		local at = CFrame.new(10, 3, 14)
		DrawnBody.publish(rushing, CFrame.new(0, 0, -6), torso, at)
		Hud.showSwitchPrompt(Combat.switchWindow, rushing, nil)
		expect(billboard.Adornee).toBe(torso)
		rushing.PrimaryPart = rushingRoot
		Hud.step(1 / 60)
		expect(billboard.Adornee).toBe(torso)
		local place = torso.Position + billboard.StudsOffsetWorldSpace
		expect((place - (at.Position + lift)).Magnitude).toBeLessThan(1e-4)
		DrawnBody.publish(rushing, nil)
		-- 81b8fef gave SWITCH back to the Model at the hand-back.
		expect(billboard.Adornee).toBe(rushingRoot)
		expect((billboard.StudsOffsetWorldSpace - lift).Magnitude).toBeLessThan(1e-4)

		-- The window closes as before, the label back on the HUD (Lune cannot write a nil Adornee).
		clock += Combat.switchWindow * 2
		Hud.step(1 / 60)
		expect(billboard.Enabled).toBe(false)
		expect(Hud.gui():FindFirstChild("SwitchPrompt")).never.toBeNil()
		EntityTracker.untrack(target)
		EntityTracker.untrack(rushing)
		task.wait()
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
