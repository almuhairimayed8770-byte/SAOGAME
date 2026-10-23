--!strict
-- ImpactFrames built in Lune: the pooled ScreenGui tree, silhouettes cloned flat and stripped,
-- looks changed by elapsed time through a hand clock and a hand-fired render step, the soft dim
-- (charged) when the flash budget says no or Reduce flashing is on, hits of one frame joining
-- or taking over the sequence showing, cancel and the clone pool, each quality tier's part cap,
-- and render stalls (a hand-fired Heartbeat with no render step: the display asleep). A picture
-- waits for its first drawn frame as long as its own hit-stop (a dim: its own length), D-122.
local ImpactFrames = Harness.load("src/client/fx/ImpactFrames")
local FlashBudget = Harness.load("src/client/fx/FlashBudget")
local ImpactSequence = Harness.load("src/client/fx/ImpactSequence")
local Smear = Harness.load("src/client/fx/Smear")
local fx = Harness.load("src/shared/data/fx")
local impact = Harness.load("src/shared/data/impact")
local palette = Harness.load("src/shared/data/palette")
local combat = Harness.load("src/shared/data/combat")
local ui = Harness.load("src/shared/data/ui")

local F = combat.hitStopFrameSeconds
-- The parts of rig() a silhouette draws: the torso, the head, the hat's handle and the sword.
local FIGURE = 4
local HIT_POINT = Vector2.new(0.4, 0.6) -- where the fake camera projects every world point
local ASPECT = 16 / 9

type World = {
	clock: number,
	render: ((dt: number) -> ())?,
	binds: number,
	unbinds: number,
	heartbeat: ((dt: number) -> ())?,
	gui: Folder,
	camera: Camera,
	quality: string,
	hasGui: boolean,
	renderFails: boolean, -- onRender binds nothing (no engine render step)
}

local world: World = nil :: any

-- A hand clock, a render step the spec fires, a PlayerGui folder and a camera; `random`
-- replaces the stroke layout's generator.
local function withWorld(body: () -> (), random: any?)
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.new(0, 5, 20)
	camera.FieldOfView = 70
	world = {
		clock = 100,
		render = nil,
		binds = 0,
		unbinds = 0,
		heartbeat = nil,
		gui = Instance.new("Folder"),
		camera = camera,
		quality = "High",
		hasGui = true,
		renderFails = false,
	}
	ImpactFrames.bind({
		now = function()
			return world.clock
		end,
		onRender = function(step: (dt: number) -> ())
			if world.renderFails then
				return nil
			end
			world.binds += 1
			world.render = step
			return function()
				world.unbinds += 1
				world.render = nil
			end
		end,
		onHeartbeat = function(step: (dt: number) -> ())
			world.heartbeat = step
			return function()
				if world.heartbeat == step then
					world.heartbeat = nil
				end
			end
		end,
		playerGui = function()
			return if world.hasGui then world.gui else nil
		end,
		camera = function()
			return world.camera
		end,
		project = function(_position: Vector3)
			return HIT_POINT
		end,
		aspect = function()
			return ASPECT
		end,
		quality = function()
			return world.quality
		end,
		random = random or Random.new(7),
	})
	FlashBudget.reset()
	local ok, err = pcall(body)
	ImpactFrames.bind(nil)
	FlashBudget.reset()
	if not ok then
		error(err, 0)
	end
end

-- Moves the hand clock and fires the render step once, as one (possibly long) frame.
local function advance(seconds: number)
	world.clock += seconds
	local render = world.render
	if render ~= nil then
		render(seconds)
	end
end

-- Moves the hand clock and fires Heartbeat only: a frame the window did not render.
local function beat(seconds: number)
	world.clock += seconds
	local heartbeat = world.heartbeat
	if heartbeat ~= nil then
		heartbeat(seconds)
	end
end

local function part(className: string, name: string, parent: Instance, position: Vector3): BasePart
	local made = Instance.new(className) :: BasePart
	made.Name = name
	made.Size = Vector3.new(2, 2, 1)
	made.CFrame = CFrame.new(position)
	made.Parent = parent
	return made
end

-- A rig with four parts the silhouette draws (a torso full of clutter, a textured MeshPart head,
-- an accessory Handle with a SpecialMesh, the sword with its Trail) and everything it must leave
-- out (layered clothing, a hidden part, the root, the sheath and FX).
local function rig(name: string, origin: Vector3): Model
	local model = Instance.new("Model")
	model.Name = name
	part("Part", "HumanoidRootPart", model, origin)

	local torso = part("Part", "UpperTorso", model, origin + Vector3.new(0, 1, 0))
	torso.Size = Vector3.new(2, 2, 1)
	for _, className in { "Decal", "Texture", "Highlight", "Script", "Sound", "Motor6D", "Attachment" } do
		Instance.new(className).Parent = torso
	end

	local head = part("MeshPart", "Head", model, origin + Vector3.new(0, 2.5, 0)) :: MeshPart
	head.TextureID = "rbxassetid://123"
	Instance.new("SurfaceAppearance").Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Parent = head

	local accessory = Instance.new("Accessory")
	accessory.Name = "Hat"
	accessory.Parent = model
	local handle = part("Part", "Handle", accessory, origin + Vector3.new(0, 3.2, 0))
	handle.Size = Vector3.new(1, 1, 1)
	local mesh = Instance.new("SpecialMesh")
	mesh.TextureId = "rbxassetid://456"
	mesh.Parent = handle
	Instance.new("Weld").Parent = handle

	local jacket = Instance.new("Accessory")
	jacket.Name = "Jacket"
	jacket.Parent = model
	Instance.new("WrapLayer").Parent = part("MeshPart", "Coat", jacket, origin + Vector3.new(0, 1, 0))

	local ghost = part("Part", "Ghost", model, origin)
	ghost.Transparency = impact.silhouette.hiddenTransparency

	local weapon = Instance.new("Model")
	weapon.Name = "Weapon"
	weapon.Parent = model
	Instance.new("Trail").Parent = part("Part", "Weapon", weapon, origin + Vector3.new(2, 1, 0))

	local sheath = Instance.new("Model")
	sheath.Name = "Sheath"
	sheath.Parent = model
	part("Part", "Scabbard", sheath, origin + Vector3.new(0, 1, 1))

	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "FX"
	fxFolder.Parent = model
	part("Part", "Glow", fxFolder, origin)

	model.Parent = Instance.new("Folder")
	return model
end

-- The drawn part a clone copies: the first BasePart of that name (the sword's part sits in a
-- Model of the same name).
local function sourceOf(model: Model, name: string): BasePart
	for _, descendant in model:GetDescendants() do
		if descendant.Name == name and descendant:IsA("BasePart") then
			return descendant
		end
	end
	error("no part " .. name, 2)
end

local function expectColor(actual: Color3, token: string)
	local rgb = palette.rgb(token)
	expect(actual.R).toBeCloseTo(rgb[1], 1e-4)
	expect(actual.G).toBeCloseTo(rgb[2], 1e-4)
	expect(actual.B).toBeCloseTo(rgb[3], 1e-4)
end

local function expectFrame(actual: CFrame, expected: CFrame)
	expect((actual.Position - expected.Position).Magnitude).toBeCloseTo(0, 1e-5)
	expect((actual.LookVector - expected.LookVector).Magnitude).toBeCloseTo(0, 1e-5)
end

local function tree(): (ScreenGui, Frame, ViewportFrame, Frame)
	local gui = ImpactFrames.gui() :: ScreenGui
	return gui,
		gui:FindFirstChild("Background") :: Frame,
		gui:FindFirstChild("Figures") :: ViewportFrame,
		gui:FindFirstChild("Strokes") :: Frame
end

local function visibleStrokes(layer: Frame): { Frame }
	local list = {}
	for _, child in layer:GetChildren() do
		if child:IsA("Frame") and child.Visible then
			table.insert(list, child)
		end
	end
	return list
end

local function cloneNames(): { [string]: boolean }
	local names = {}
	for _, clone in ImpactFrames.clones() do
		names[clone.Name] = true
	end
	return names
end

-- A destroyed Instance refuses a new parent.
local function destroyedInstance(instance: Instance): boolean
	local ok = pcall(function()
		instance.Parent = Instance.new("Folder")
	end)
	if ok then
		instance.Parent = nil
	end
	return not ok
end

-- Relative luminance (WCAG 2.x) of a Color3, from the impact table's curve.
local function pictureLuminance(value: Color3): number
	local curve = impact.flash.luminance
	local function linear(channel: number): number
		if channel <= curve.linearBelow then
			return channel / curve.linearDivisor
		end
		return ((channel + curve.offset) / curve.divisor) ^ curve.gamma
	end
	return curve.weights[1] * linear(value.R) + curve.weights[2] * linear(value.G) + curve.weights[3] * linear(value.B)
end

-- When each luminance change of at least `delta` in one region ends: a change is a run in one
-- direction, so an eased fade counts once, not once per frame.
local function transitionTimes(
	samples: { { at: number, values: { number } } },
	region: number,
	delta: number
): { number }
	local times = {}
	if #samples == 0 then
		return times
	end
	local runStart = samples[1].values[region]
	local last = runStart
	local lastAt = samples[1].at
	local direction = 0
	for index = 2, #samples do
		local value = samples[index].values[region]
		local step = value - last
		local turn = if step > 1e-9 then 1 elseif step < -1e-9 then -1 else 0
		if turn ~= 0 and direction ~= 0 and turn ~= direction then
			if math.abs(last - runStart) >= delta then
				table.insert(times, lastAt)
			end
			runStart = last
		end
		if turn ~= 0 then
			direction = turn
			last = value
			lastAt = samples[index].at
		end
	end
	if math.abs(last - runStart) >= delta then
		table.insert(times, lastAt)
	end
	return times
end

describe("ImpactFrames overlay tree", function()
	it("builds one disabled ScreenGui above the HUD under the PlayerGui, once", function()
		withWorld(function()
			ImpactFrames.start()
			local gui, background, figures, strokes = tree()
			expect(gui.Parent).toBe(world.gui)
			expect(gui.Name).toBe(impact.overlay.screenGuiName)
			expect(gui.IgnoreGuiInset).toBe(true)
			expect(gui.ResetOnSpawn).toBe(false)
			expect(gui.Enabled).toBe(false)
			expect(gui.DisplayOrder).toBe(impact.overlay.displayOrder)
			expect(gui.DisplayOrder).toBeGreaterThan(ui.hud.displayOrder)

			expect(background:IsA("Frame")).toBe(true)
			expect(background.Size).toEqual(UDim2.fromScale(1, 1))
			expect(figures:IsA("ViewportFrame")).toBe(true)
			expect(figures.Size).toEqual(UDim2.fromScale(1, 1))
			expect(figures.BackgroundTransparency).toBeCloseTo(1, 1e-6)
			expectColor(figures.Ambient, impact.viewport.ambientToken)
			expectColor(figures.LightColor, impact.viewport.lightToken)
			local camera = figures:FindFirstChild(impact.viewport.cameraName)
			expect(camera).never.toBeNil()
			expect((camera :: Instance):IsA("Camera")).toBe(true)
			expect(ImpactFrames.camera()).toBe(camera)

			local frames = strokes:GetChildren()
			expect(#frames).toBe(impact.strokes.count.max)
			for _, stroke in frames do
				expect(stroke:FindFirstChildOfClass("UICorner")).never.toBeNil()
				local gradient = stroke:FindFirstChildOfClass("UIGradient") :: UIGradient
				expect(gradient).never.toBeNil()
				local keys = gradient.Transparency.Keypoints
				-- Tapered: the stroke runs out to nothing at its tail.
				expect(keys[#keys].Value).toBeCloseTo(1, 1e-6)
				expect((stroke :: Frame).Visible).toBe(false)
			end

			ImpactFrames.start()
			expect(ImpactFrames.gui()).toBe(gui)
			expect(#world.gui:GetChildren()).toBe(1)
		end)
	end)

	it("returns 0 and spends nothing when there is no PlayerGui, no such sequence or no frame", function()
		withWorld(function()
			world.hasGui = false
			expect(ImpactFrames.play("Kill", {})).toBe(0)
			expect(FlashBudget.used(world.clock)).toBe(0)
			world.hasGui = true
			expect(ImpactFrames.play("Nope", {})).toBe(0)
			expect(ImpactFrames.isShowing()).toBe(false)
			-- A sequence whose steps hold no frame shows nothing and costs nothing.
			impact.sequences.Empty = { tier = "Normal", steps = { { look = "Dark", frames = 0 } } }
			local ok, err = pcall(function()
				expect(ImpactFrames.play("Empty", {})).toBe(0)
				expect(ImpactFrames.isShowing()).toBe(false)
				expect(FlashBudget.used(world.clock)).toBe(0)
			end)
			impact.sequences.Empty = nil
			if not ok then
				error(err, 0)
			end
		end)
	end)
end)

describe("ImpactFrames overlay rebuild", function()
	it("builds a new overlay when the PlayerGui lost the old one, ending what showed", function()
		withWorld(function()
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			ImpactFrames.play("Kill", { model })
			local old = ImpactFrames.gui() :: ScreenGui
			old:Destroy()
			world.clock += 2
			expect(ImpactFrames.play("Final", { model })).toBeCloseTo(ImpactSequence.seconds("Final"), 1e-9)
			local gui = ImpactFrames.gui() :: ScreenGui
			expect(gui == old).toBe(false)
			expect(gui.Parent).toBe(world.gui)
			expect(ImpactFrames.look()).toBe("Dark")
			-- The clones that went down with the old overlay were dropped, not pooled.
			expect(#ImpactFrames.clones()).toBe(FIGURE)
			for _, clone in ImpactFrames.clones() do
				expect(clone:IsDescendantOf(gui)).toBe(true)
			end
			expect(world.unbinds).toBe(1)
		end)
	end)
end)

describe("ImpactFrames silhouettes", function()
	it(
		"clones each visible part flat and bare, the sword too, and leaves out the root, sheath, FX and hidden parts",
		function()
			withWorld(function()
				local model = rig("Fighter", Vector3.new(0, 3, 0))
				ImpactFrames.play("Final", { model })
				local clones = ImpactFrames.clones()
				expect(#clones).toBe(FIGURE)
				-- The anime's impact frames draw the blade in the figure (D-066).
				expect(cloneNames()).toEqual({ UpperTorso = true, Head = true, Handle = true, Weapon = true })
				local _, _, figures = tree()
				for _, clone in clones do
					expect(clone:IsDescendantOf(figures)).toBe(true)
					expect(clone.Material).toBe(Enum.Material.SmoothPlastic)
					expectColor(clone.Color, impact.silhouette.flatToken)
					expect(clone.Transparency).toBeCloseTo(0, 1e-6)
					expect(clone.Anchored).toBe(true)
					expect(clone.CanCollide).toBe(false)
					for _, child in clone:GetChildren() do
						-- Only a shape-giving mesh survives, with its texture taken off.
						expect(child:IsA("DataModelMesh")).toBe(true)
						expect((child :: SpecialMesh).TextureId).toBe("")
					end
					if clone:IsA("MeshPart") then
						expect((clone :: MeshPart).TextureID).toBe("")
					end
					local source = sourceOf(model, clone.Name)
					expectFrame(clone.CFrame, source.CFrame)
				end
				-- The rig itself is untouched.
				local torso = model:FindFirstChild("UpperTorso") :: BasePart
				expect(torso:FindFirstChildOfClass("Decal")).never.toBeNil()
				expect(torso:FindFirstChildOfClass("Motor6D")).never.toBeNil()
				expect((model:FindFirstChild("Head") :: MeshPart).TextureID).toBe("rbxassetid://123")
			end)
		end
	)

	it("copies the camera and every source part's CFrame each overlay frame", function()
		withWorld(function()
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			ImpactFrames.play("Kill", { model })
			local own = ImpactFrames.camera() :: Camera
			expectFrame(own.CFrame, world.camera.CFrame)
			expect(own.FieldOfView).toBeCloseTo(70, 1e-4)

			world.camera.CFrame = CFrame.new(4, 6, 18) * CFrame.Angles(0, 0.3, 0)
			world.camera.FieldOfView = 62
			local torso = model:FindFirstChild("UpperTorso") :: BasePart
			torso.CFrame = CFrame.new(1, 4, -2)
			advance(0.5 * F)
			expectFrame(own.CFrame, world.camera.CFrame)
			expect(own.FieldOfView).toBeCloseTo(62, 1e-4)
			for _, clone in ImpactFrames.clones() do
				if clone.Name == "UpperTorso" then
					expectFrame(clone.CFrame, torso.CFrame)
				end
			end
		end)
	end)

	it("draws every rig given once, and skips silhouettes on a look without figures", function()
		withWorld(function()
			local a = rig("A", Vector3.new(0, 3, 0))
			local b = rig("B", Vector3.new(6, 3, 0))
			ImpactFrames.play("Kill", { a, b, a })
			expect(#ImpactFrames.clones()).toBe(2 * FIGURE)
			local _, _, figures = tree()
			-- Kill opens on the black beat: no figures shown yet.
			expect(figures.Visible).toBe(false)
			expect(ImpactFrames.look()).toBe("Black")
		end)
	end)

	it("draws the sword at its rest size while the smear stretches it in a hit-stop", function()
		withWorld(function()
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			local sword = sourceOf(model, "Weapon")
			local rest = sword.Size
			-- The snap's smear frames are on when the hit-stop freezes the clip.
			Smear.apply(model, true, "Y")
			expect(sword.Size.Y).toBeCloseTo(rest.Y * fx.smear.scale, 1e-4)
			-- Smear keeps the size it stored; the figure asks it through Smear.restSize (the real
			-- one: no stand-in).
			local ok, err = pcall(function()
				ImpactFrames.play("Final", { model })
				for _, clone in ImpactFrames.clones() do
					local source = sourceOf(model, clone.Name)
					if clone.Name == "Weapon" then
						expect((clone.Size - rest).Magnitude).toBeCloseTo(0, 1e-5)
					else
						expect((clone.Size - source.Size).Magnitude).toBeCloseTo(0, 1e-5)
					end
				end
				-- The rig keeps its stretch: only the figure is drawn at rest.
				expect(sword.Size.Y).toBeCloseTo(rest.Y * fx.smear.scale, 1e-4)
				-- A pooled clone taken back next time is sized again, at rest too.
				ImpactFrames.cancel()
				world.clock += 2
				ImpactFrames.play("Final", { model })
				for _, clone in ImpactFrames.clones() do
					if clone.Name == "Weapon" then
						expect((clone.Size - rest).Magnitude).toBeCloseTo(0, 1e-5)
					end
				end
				-- A sword the smear let go of and forgot is drawn at the size it has.
				ImpactFrames.cancel()
				world.clock += 2
				Smear.reset(model)
				sword.Size = rest * 1.25
				ImpactFrames.play("Final", { model })
				for _, clone in ImpactFrames.clones() do
					if clone.Name == "Weapon" then
						expect((clone.Size - sword.Size).Magnitude).toBeCloseTo(0, 1e-5)
					end
				end
				sword.Size = rest
			end)
			Smear.reset(model)
			if not ok then
				error(err, 0)
			end
		end)
	end)
end)

describe("ImpactFrames sweep", function()
	it("twelve hits of one frame (a 12-target sweep, kills among them) are one picture, charged once", function()
		withWorld(function()
			local rigs = {}
			for index = 1, 12 do
				table.insert(rigs, rig("T" .. index, Vector3.new(index * 3, 3, 0)))
			end
			local attacker = rig("Attacker", Vector3.new(0, 3, 4))
			-- Eleven final hits and one kill, all in the frame the sweep confirms.
			for index, target in rigs do
				ImpactFrames.play(if index == 7 then "Kill" else "Final", { attacker, target })
			end
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Kill"))
			expect(ImpactFrames.look()).toBe("Black")
			-- One render step runs (the kill's takeover swapped it, never added one).
			expect(world.binds - world.unbinds).toBe(1)
			-- Never more rigs than the cap, the attacker first.
			expect(#ImpactFrames.clones()).toBe(FIGURE * impact.silhouette.maxRigs)
			-- With Reduce flashing on, twelve dims of one frame are one dim, charged once.
			ImpactFrames.cancel()
			world.clock += 2
			FlashBudget.set(true)
			for _, target in rigs do
				ImpactFrames.play("Final", { attacker, target })
			end
			expect(ImpactFrames.look()).toBe("Reduced")
			expect(FlashBudget.used(world.clock)).toBe(impact.reduced.flashCost)
			FlashBudget.set(false)
		end)
	end)
end)

describe("ImpactFrames timing", function()
	it("starts the clock on the first drawn frame, changes looks by elapsed time and hides on time", function()
		withWorld(function()
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			local seconds = ImpactFrames.play("Kill", { model })
			expect(seconds).toBeCloseTo(ImpactSequence.seconds("Kill"), 1e-9)
			local gui, background, figures, strokes = tree()
			expect(gui.Enabled).toBe(true)
			expect(ImpactFrames.isShowing()).toBe(true)
			expect(ImpactFrames.look()).toBe("Black")
			expectColor(background.BackgroundColor3, "OutlineInk")
			expect(background.BackgroundTransparency).toBeCloseTo(0, 1e-6)
			expect(figures.Visible).toBe(false)

			-- The hit landed between frames: the first frame drawn after it is the black beat's first.
			advance(0.7 * F)
			expect(ImpactFrames.look()).toBe("Black")
			expect(ImpactFrames.remaining()).toBeCloseTo(ImpactSequence.seconds("Kill"), 1e-9)

			advance(2.5 * F)
			expect(ImpactFrames.look()).toBe("Dark")
			expectColor(background.BackgroundColor3, "OutlineInk")
			expect(figures.Visible).toBe(true)
			expectColor(figures.ImageColor3, "SystemWhite")
			expect(strokes.Visible).toBe(false)
			expect(ImpactFrames.hiddenSeconds()).toBeCloseTo(3.5 * F, 1e-9)

			advance(3 * F)
			expect(ImpactFrames.look()).toBe("Ink")
			expectColor(background.BackgroundColor3, "SystemWhite")
			expect(figures.Visible).toBe(true)
			expectColor(figures.ImageColor3, "OutlineInk")
			expect(strokes.Visible).toBe(true)
			local shown = visibleStrokes(strokes)
			expect(#shown).toBeGreaterThanOrEqual(impact.strokes.count.min)
			expect(#shown).toBeLessThanOrEqual(impact.strokes.count.max)

			advance(1.6 * F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(ImpactFrames.look()).toBeNil()
			expect(ImpactFrames.remaining()).toBe(0)
			expect(ImpactFrames.hiddenSeconds()).toBe(0)
			expect(gui.Enabled).toBe(false)
			expect(figures.Visible).toBe(false)
			expect(#visibleStrokes(strokes)).toBe(0)
			expect(#ImpactFrames.clones()).toBe(0)
			expect(ImpactFrames.pooledCount()).toBe(FIGURE)
			expect(world.binds).toBe(1)
			expect(world.unbinds).toBe(1)
			-- The clones left the viewport.
			for _, folder in figures:GetChildren() do
				if folder:IsA("Model") then
					expect(#folder:GetChildren()).toBe(0)
				end
			end
		end)
	end)

	it("draws every look once at 30 fps, frame for frame", function()
		withWorld(function()
			ImpactFrames.play("Kill", { rig("Fighter", Vector3.new(0, 3, 0)) })
			local seen = {}
			for _ = 1, 8 do
				advance(2 * F)
				local look = ImpactFrames.look()
				if look == nil then
					break
				end
				table.insert(seen, look)
			end
			expect(seen).toEqual({ "Black", "Dark", "Ink" })
			expect(ImpactFrames.isShowing()).toBe(false)
		end)
	end)

	it("on a slow device gives each look a drawn frame but never shows past the hit-stop", function()
		withWorld(function()
			ImpactFrames.play("Kill", { rig("Fighter", Vector3.new(0, 3, 0)) })
			advance(F)
			expect(ImpactFrames.look()).toBe("Black")
			-- One long frame moves one look on, never past a look nobody saw.
			advance(6 * F)
			expect(ImpactFrames.look()).toBe("Dark")
			-- The next one is past the Kill hit-stop (10 frames): the rigs move again, so it ends.
			advance(5 * F)
			expect(ImpactFrames.isShowing()).toBe(false)
		end)
	end)

	it("shows the parry's one inverted frame: white figures on the system cyan", function()
		withWorld(function()
			expect(ImpactFrames.play("Parry", { rig("Fighter", Vector3.new(0, 3, 0)) })).toBeCloseTo(F, 1e-9)
			local _, background, figures = tree()
			expect(ImpactFrames.look()).toBe("Inverted")
			expectColor(background.BackgroundColor3, "SystemCyan")
			expect(figures.Visible).toBe(true)
			expectColor(figures.ImageColor3, "SystemWhite")
			advance(F)
			expect(ImpactFrames.isShowing()).toBe(true)
			advance(F)
			expect(ImpactFrames.isShowing()).toBe(false)
		end)
	end)

	it("draws the parry's frame at 30 fps too, when the first frame comes two frames after the hit", function()
		withWorld(function()
			ImpactFrames.play("Parry", { rig("Fighter", Vector3.new(0, 3, 0)) })
			advance(2 * F)
			expect(ImpactFrames.look()).toBe("Inverted")
			expect(tree().Enabled).toBe(true)
			advance(2 * F)
			expect(ImpactFrames.isShowing()).toBe(false)
		end)
	end)
end)

describe("ImpactFrames ink strokes", function()
	it("lays 3 to 5 strokes along the slash direction across the hit", function()
		withWorld(function()
			local config = impact.strokes
			ImpactFrames.play("Kill", { rig("Fighter", Vector3.new(0, 3, 0)) }, { slashDirection = Vector2.new(1, 1) })
			-- A first frame inside the staleness limit, then on to the Ink look.
			advance(F)
			advance(2 * F)
			advance(2 * F)
			local _, _, _, strokes = tree()
			local shown = visibleStrokes(strokes)
			expect(#shown >= config.count.min and #shown <= config.count.max).toBe(true)
			local reach = config.spread + config.laneJitter + config.slide
			for _, stroke in shown do
				expect(math.abs(stroke.Rotation - 45)).toBeLessThanOrEqual(config.jitterDegrees + 1e-6)
				expect(stroke.SizeConstraint).toBe(Enum.SizeConstraint.RelativeYY)
				expectColor(stroke.BackgroundColor3, config.token)
				local size = stroke.Size
				expect(size.X.Scale >= config.length.min and size.X.Scale <= config.length.max).toBe(true)
				expect(size.Y.Scale >= config.width.min and size.Y.Scale <= config.width.max).toBe(true)
				-- Each stroke sits on its lane across the hit point.
				expect(math.abs(stroke.Position.Y.Scale - HIT_POINT.Y)).toBeLessThanOrEqual(reach + 1e-6)
				expect(math.abs(stroke.Position.X.Scale - HIT_POINT.X)).toBeLessThanOrEqual(reach / ASPECT + 1e-6)
			end
		end)
	end)

	it("fans the strokes in even lanes across the slash, measured in screen heights", function()
		-- A generator that always answers its maximum: five strokes, every jitter at its top.
		local maxRandom = {
			NextInteger = function(_self: any, _min: number, max: number): number
				return max
			end,
			NextNumber = function(_self: any, _min: number, max: number): number
				return max
			end,
		}
		withWorld(function()
			local config = impact.strokes
			ImpactFrames.play("Kill", {}, { slashDirection = Vector2.new(0, 1), position = Vector3.zero })
			-- A first frame inside the staleness limit, then on to the Ink look.
			advance(F)
			advance(2 * F)
			advance(2 * F)
			local _, _, _, strokes = tree()
			local shown = visibleStrokes(strokes)
			table.sort(shown, function(a, b)
				return a.Position.X.Scale < b.Position.X.Scale
			end)
			expect(#shown).toBe(config.count.max)
			local gap = 2 * config.spread / config.count.max
			for index, stroke in shown do
				expect(stroke.Rotation).toBeCloseTo(90 + config.jitterDegrees, 1e-6)
				expect(stroke.Size.X.Scale).toBeCloseTo(config.length.max, 1e-6)
				expect(stroke.Size.Y.Scale).toBeCloseTo(config.width.max, 1e-6)
				-- A vertical slash slides every stroke down by the same amount.
				expect(stroke.Position.Y.Scale).toBeCloseTo(HIT_POINT.Y + config.slide, 1e-6)
				if index > 1 then
					-- Neighbouring lanes sit one gap apart in screen heights: X scales by the aspect.
					local across = (stroke.Position.X.Scale - shown[index - 1].Position.X.Scale) * ASPECT
					expect(across).toBeCloseTo(gap, 1e-6)
				end
			end
		end, maxRandom)
	end)

	it("falls back to the default angle without a slash direction", function()
		withWorld(function()
			ImpactFrames.play("Kill", {})
			-- A first frame inside the staleness limit, then on to the Ink look.
			advance(F)
			advance(2 * F)
			advance(2 * F)
			local _, _, _, strokes = tree()
			local shown = visibleStrokes(strokes)
			expect(#shown).toBeGreaterThan(0)
			for _, stroke in shown do
				local off = math.abs(stroke.Rotation - impact.strokes.defaultAngle)
				expect(off).toBeLessThanOrEqual(impact.strokes.jitterDegrees + 1e-6)
			end
		end)
	end)
end)

describe("ImpactFrames flash safety", function()
	it("dims the second Kill inside a second instead of flashing, and charges the dim its own cost", function()
		withWorld(function()
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			ImpactFrames.play("Kill", { model })
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Kill"))
			advance(F)
			advance(10 * F)
			expect(ImpactFrames.isShowing()).toBe(false)
			world.clock += 0.5
			local seconds = ImpactFrames.play("Kill", { model })
			expect(seconds).toBeCloseTo(ImpactSequence.dimSeconds(), 1e-9)
			-- The dim's dip is a flash on a bright scene: it is charged too, never free.
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Kill") + impact.reduced.flashCost)
			expect(ImpactFrames.look()).toBe("Reduced")
			expect(ImpactFrames.hiddenSeconds()).toBe(0)
			expect(#ImpactFrames.clones()).toBe(0)

			local gui, background, figures, strokes = tree()
			expect(gui.Enabled).toBe(true)
			expect(figures.Visible).toBe(false)
			expect(strokes.Visible).toBe(false)
			expectColor(background.BackgroundColor3, impact.reduced.token)
			-- Eased in: nothing at the first instant, part of the low peak one frame later.
			expect(background.BackgroundTransparency).toBeCloseTo(1, 1e-6)
			advance(F)
			local opacity = 1 - background.BackgroundTransparency
			expect(opacity).toBeGreaterThan(0)
			expect(opacity).toBeLessThan(impact.reduced.opacity)
			advance((impact.reduced.fadeInFrames + impact.reduced.holdFrames - 1.5) * F)
			expect(1 - background.BackgroundTransparency).toBeCloseTo(impact.reduced.opacity, 1e-6)
			advance(ImpactSequence.dimSeconds())
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(gui.Enabled).toBe(false)
		end)
	end)

	it("shows nothing at all when the budget cannot pay even for the dim", function()
		withWorld(function()
			expect(FlashBudget.request(world.clock, impact.flash.maxPerWindow)).toBe(true)
			expect(ImpactFrames.play("Kill", { rig("Fighter", Vector3.new(0, 3, 0)) })).toBe(0)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(tree().Enabled).toBe(false)
			expect(FlashBudget.used(world.clock)).toBe(impact.flash.maxPerWindow)
		end)
	end)

	it("never puts more than the limit of flashes in any second on screen, dims included", function()
		withWorld(function()
			-- A Kill every 0.2 s for 3 s over a white scene (the worst case for the dim), read off
			-- the overlay every 60 fps frame: no region of the picture may flash more than the limit
			-- in any second.
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			ImpactFrames.start()
			local gui, background, figures, strokes = tree()
			local samples: { { at: number, values: { number } } } = {}
			local function sample()
				local scene = pictureLuminance(Color3.new(1, 1, 1))
				local values = { scene, scene, scene }
				if gui.Enabled then
					local alpha = 1 - background.BackgroundTransparency
					local field = background.BackgroundColor3
					local blend = Color3.new(
						1 - alpha + field.R * alpha,
						1 - alpha + field.G * alpha,
						1 - alpha + field.B * alpha
					)
					local fieldValue = pictureLuminance(blend)
					values = { fieldValue, fieldValue, fieldValue }
					if figures.Visible then
						values[2] = pictureLuminance(figures.ImageColor3)
					end
					if strokes.Visible and #visibleStrokes(strokes) > 0 then
						values[3] = pictureLuminance(palette.color3(impact.strokes.token))
					end
				end
				table.insert(samples, { at = world.clock, values = values })
			end
			for _ = 1, 15 do
				ImpactFrames.play("Kill", { model })
				for _ = 1, 12 do
					advance(1 / 60)
					sample()
				end
			end
			for _ = 1, 90 do
				advance(1 / 60)
				sample()
			end
			-- The burst really flashes: the figures alone change more often than the limit allows.
			expect(#transitionTimes(samples, 2, impact.flash.transitionDelta)).toBeGreaterThan(
				2 * impact.flash.maxPerWindow
			)
			for region = 1, 3 do
				local changes = transitionTimes(samples, region, impact.flash.transitionDelta)
				for _, first in changes do
					local inWindow = 0
					for _, other in changes do
						if other >= first and other < first + impact.flash.windowSeconds then
							inWindow += 1
						end
					end
					-- A flash is a pair of opposing changes.
					expect(inWindow).toBeLessThanOrEqual(2 * impact.flash.maxPerWindow)
				end
			end
		end)
	end)

	it("charges the dim with Reduce flashing on, once for a dim that is still rising or at its peak", function()
		withWorld(function()
			FlashBudget.set(true)
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			for _, name in { "Final", "Parry", "Kill" } do
				expect(ImpactFrames.play(name, { model })).toBeGreaterThan(0)
				expect(ImpactFrames.look()).toBe("Reduced")
				expect(#ImpactFrames.clones()).toBe(0)
				advance(F)
			end
			-- Three hits inside the dim's rise: one dim, one charge, no fade out and in between.
			expect(FlashBudget.used(world.clock)).toBe(impact.reduced.flashCost)
			-- The last hit keeps the peak a full hold from when it landed.
			local hold = ImpactSequence.dimHoldSeconds()
			local fadeIn = impact.reduced.fadeInFrames * F
			local _, background = tree()
			advance(fadeIn + hold - 2.5 * F)
			expect(1 - background.BackgroundTransparency).toBeCloseTo(impact.reduced.opacity, 1e-6)
			expect(ImpactFrames.remaining()).toBeCloseTo(
				ImpactSequence.dimSeconds(2 * F + hold) - (fadeIn + hold + 0.5 * F),
				1e-9
			)
		end)
	end)

	it("charges a dim asked for while one fades out: it is a new dip", function()
		withWorld(function()
			-- Reduce flashing off, the budget too full for a Kill: the hits fall back to the dim.
			-- One cost stays the whole case; another ends just after the first dim starts.
			local window = impact.flash.windowSeconds
			expect(FlashBudget.request(world.clock, 1, 10)).toBe(true)
			expect(FlashBudget.request(world.clock - window + 2 * F, 1, 0)).toBe(true)
			ImpactFrames.play("Kill", {})
			expect(ImpactFrames.look()).toBe("Reduced")
			local fadeIn = impact.reduced.fadeInFrames * F
			advance(F) -- the first drawn frame, inside the staleness limit
			advance(fadeIn + ImpactSequence.dimHoldSeconds() + 3 * F)
			local _, background = tree()
			local fading = 1 - background.BackgroundTransparency
			expect(fading).toBeLessThan(impact.reduced.opacity)
			expect(fading).toBeGreaterThan(0)
			ImpactFrames.play("Kill", {})
			expect(FlashBudget.used(world.clock)).toBe(1 + 2 * impact.reduced.flashCost)
			-- It rises from what shows, never jumping.
			expect(1 - background.BackgroundTransparency).toBeCloseTo(fading, 1e-6)
			advance(F)
			expect(1 - background.BackgroundTransparency).toBeGreaterThan(fading)
		end)
	end)

	it("starts one dim a window with Reduce flashing on, however many hits land", function()
		withWorld(function()
			FlashBudget.set(true)
			local window = impact.flash.windowSeconds
			local start = world.clock
			expect(ImpactFrames.play("Final", {})).toBeCloseTo(ImpactSequence.dimSeconds(), 1e-9)
			local firstEnd = start + ImpactSequence.dimSeconds()
			-- Hits 0.31 s apart, each landing after the last dim faded, and one just inside the
			-- window after the first dim's end.
			local hits = { 0.31, 0.62, 0.93, firstEnd - start + window - 2 * F }
			local nextHit = 1
			local started = 1
			local wasShowing = true
			while world.clock < firstEnd + window - F do
				advance(F)
				local showingNow = ImpactFrames.isShowing()
				if showingNow and not wasShowing then
					started += 1
				end
				wasShowing = showingNow
				while hits[nextHit] ~= nil and world.clock - start >= hits[nextHit] do
					expect(ImpactFrames.play("Kill", {})).toBe(0)
					nextHit += 1
				end
			end
			expect(nextHit).toBe(#hits + 1)
			expect(started).toBe(impact.reduced.maxPerWindow)
			expect(FlashBudget.used(world.clock)).toBe(impact.reduced.flashCost)
			-- A window after the dim's end, the next hit dims again.
			world.clock = firstEnd + window + F
			expect(ImpactFrames.play("Kill", {})).toBeCloseTo(ImpactSequence.dimSeconds(), 1e-9)
			expect(ImpactFrames.look()).toBe("Reduced")
		end)
	end)

	it("keeps a fading dim fading, uncharged, when Reduce flashing already spent its window", function()
		withWorld(function()
			FlashBudget.set(true)
			ImpactFrames.play("Final", {})
			advance(F) -- the first drawn frame, inside the staleness limit
			advance(impact.reduced.fadeInFrames * F + ImpactSequence.dimHoldSeconds() + 3 * F)
			local _, background = tree()
			local before = 1 - background.BackgroundTransparency
			local left = ImpactFrames.remaining()
			expect(ImpactFrames.play("Final", {})).toBeCloseTo(left, 1e-9)
			expect(FlashBudget.used(world.clock)).toBe(impact.reduced.flashCost)
			advance(F)
			expect(1 - background.BackgroundTransparency).toBeLessThan(before)
		end)
	end)

	it("keeps a fading dim fading when the budget refuses the next one", function()
		withWorld(function()
			FlashBudget.set(true)
			ImpactFrames.play("Final", {})
			local fadeIn = impact.reduced.fadeInFrames * F
			advance(F) -- the first drawn frame, inside the staleness limit
			advance(fadeIn + ImpactSequence.dimHoldSeconds() + 3 * F)
			expect(FlashBudget.request(world.clock, impact.flash.maxPerWindow - impact.reduced.flashCost)).toBe(true)
			local left = ImpactFrames.remaining()
			expect(ImpactFrames.play("Final", {})).toBeCloseTo(left, 1e-9)
			expect(FlashBudget.used(world.clock)).toBe(impact.flash.maxPerWindow)
			local _, background = tree()
			local before = 1 - background.BackgroundTransparency
			advance(F)
			expect(1 - background.BackgroundTransparency).toBeLessThan(before)
		end)
	end)

	it("eases a dim over a dim on from the opacity already showing", function()
		withWorld(function()
			FlashBudget.set(true)
			ImpactFrames.play("Final", {})
			advance(F) -- the first drawn frame, inside the staleness limit
			advance(impact.reduced.fadeInFrames * F)
			local _, background = tree()
			local before = background.BackgroundTransparency
			expect(1 - before).toBeCloseTo(impact.reduced.opacity, 1e-6)
			ImpactFrames.play("Final", {})
			expect(background.BackgroundTransparency).toBeCloseTo(before, 1e-6)
			advance(F)
			expect(1 - background.BackgroundTransparency).toBeCloseTo(impact.reduced.opacity, 1e-6)
		end)
	end)

	it("cuts a sequence on screen the moment Reduce flashing turns on", function()
		withWorld(function()
			ImpactFrames.start()
			ImpactFrames.play("Kill", { rig("Fighter", Vector3.new(0, 3, 0)) })
			expect(ImpactFrames.isShowing()).toBe(true)
			FlashBudget.set(true)
			expect(ImpactFrames.isShowing()).toBe(false)
		end)
	end)

	it("keeps a sequence's cost until a window after its last frame", function()
		withWorld(function()
			ImpactFrames.play("Final", {})
			local playedAt = world.clock
			advance(0.9 * F) -- the first drawn frame
			advance(2 * F) -- the last: the overlay hides here
			expect(ImpactFrames.isShowing()).toBe(false)
			local hiddenAt = world.clock
			-- A window after the play, but not yet a window after the scene came back.
			world.clock = playedAt + impact.flash.windowSeconds + 0.5 * F
			expect(world.clock < hiddenAt + impact.flash.windowSeconds).toBe(true)
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Final"))
			world.clock = hiddenAt + impact.flash.windowSeconds
			expect(FlashBudget.used(world.clock)).toBe(0)
		end)
	end)
end)

describe("ImpactFrames cancel and the pool", function()
	it("cancel hides at once and pools the clones; the next play reuses them", function()
		withWorld(function()
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			ImpactFrames.play("Final", { model })
			local first = {}
			for _, clone in ImpactFrames.clones() do
				first[clone] = true
			end
			ImpactFrames.cancel()
			local gui = tree()
			expect(gui.Enabled).toBe(false)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(world.unbinds).toBe(1)
			expect(ImpactFrames.pooledCount()).toBe(FIGURE)
			for clone in first do
				expect(clone.Parent).toBeNil()
			end

			world.clock += 2
			ImpactFrames.play("Final", { model })
			for _, clone in ImpactFrames.clones() do
				expect(first[clone]).toBe(true)
			end
			expect(ImpactFrames.pooledCount()).toBe(0)
		end)
	end)

	it("joins a hit of the same frame into the sequence showing: its rigs drawn too, charged once", function()
		withWorld(function()
			local a = rig("A", Vector3.new(0, 3, 0))
			local b = rig("B", Vector3.new(6, 3, 0))
			-- One sweep kills two enemies: two HitConfirmed in the same frame.
			ImpactFrames.play("Kill", { a })
			expect(ImpactFrames.play("Kill", { b })).toBeCloseTo(ImpactSequence.seconds("Kill"), 1e-9)
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Kill"))
			expect(ImpactFrames.look()).toBe("Black")
			expect(#ImpactFrames.clones()).toBe(2 * FIGURE)
			expect(world.binds).toBe(1)
			-- A lower rank (the parry's frame) joins too, and never cuts the kill short.
			advance(F)
			local c = rig("C", Vector3.new(-6, 3, 0))
			expect(ImpactFrames.play("Parry", { c })).toBeCloseTo(ImpactSequence.seconds("Kill"), 1e-9)
			expect(ImpactFrames.look()).toBe("Black")
			expect(#ImpactFrames.clones()).toBe(3 * FIGURE)
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Kill"))
			advance(2 * F)
			expect(ImpactFrames.look()).toBe("Dark")
		end)
	end)

	it("lets a higher rank take over, charged only what the whole picture adds", function()
		withWorld(function()
			local a = rig("A", Vector3.new(0, 3, 0))
			local b = rig("B", Vector3.new(6, 3, 0))
			-- An Art's final hit and a kill in the same frame: one Kill, never Final then Kill.
			ImpactFrames.play("Final", { a })
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Final"))
			expect(ImpactFrames.play("Kill", { b })).toBeCloseTo(ImpactSequence.seconds("Kill"), 1e-9)
			expect(ImpactFrames.look()).toBe("Black")
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Kill"))
			expect(#ImpactFrames.clones()).toBe(2 * FIGURE)
		end)
	end)

	it("charges a takeover after drawn frames for every look really shown", function()
		withWorld(function()
			ImpactFrames.play("Parry", { rig("A", Vector3.new(0, 3, 0)) })
			advance(F) -- the inverted frame is on screen
			ImpactFrames.play("Kill", { rig("B", Vector3.new(6, 3, 0)) })
			local path = { "Inverted" }
			for _, frame in ImpactSequence.frames("Kill") do
				table.insert(path, frame.look)
			end
			local cost = ImpactSequence.costOfLooks(path, impact.looks)
			expect(cost).toBeGreaterThan(ImpactSequence.flashCost("Kill"))
			expect(FlashBudget.used(world.clock)).toBe(cost)
			expect(ImpactFrames.look()).toBe("Black")
		end)
	end)

	it("charges a second takeover in one frame for the looks the first one took over", function()
		withWorld(function()
			-- The parry's frame is drawn; the next frame a sweep confirms a final hit, then a kill.
			ImpactFrames.play("Parry", { rig("A", Vector3.new(0, 3, 0)) })
			advance(F)
			ImpactFrames.play("Final", { rig("B", Vector3.new(6, 3, 0)) })
			ImpactFrames.play("Kill", { rig("C", Vector3.new(-6, 3, 0)) })
			local path = { "Inverted" }
			for _, frame in ImpactSequence.frames("Kill") do
				table.insert(path, frame.look)
			end
			local cost = ImpactSequence.costOfLooks(path, impact.looks)
			expect(cost).toBe(impact.flash.maxPerWindow)
			expect(FlashBudget.used(world.clock)).toBe(cost)
			for _ = 1, ImpactSequence.frameCount("Kill") + 1 do
				advance(F)
			end
			expect(ImpactFrames.isShowing()).toBe(false)
			-- The whole second is spent: a final hit right after shows nothing, not a second picture.
			expect(ImpactFrames.play("Final", { rig("D", Vector3.new(0, 3, 6)) })).toBe(0)
			expect(ImpactFrames.isShowing()).toBe(false)
		end)
	end)

	it("keeps the sequence showing, joined, when the budget cannot pay for a takeover", function()
		withWorld(function()
			expect(FlashBudget.request(world.clock, impact.flash.maxPerWindow - ImpactSequence.flashCost("Final"))).toBe(
				true
			)
			ImpactFrames.play("Final", { rig("A", Vector3.new(0, 3, 0)) })
			expect(FlashBudget.used(world.clock)).toBe(impact.flash.maxPerWindow)
			ImpactFrames.play("Kill", { rig("B", Vector3.new(6, 3, 0)) })
			-- Never cut to a dim mid-picture, never charged past the limit.
			expect(ImpactFrames.look()).toBe("Dark")
			expect(#ImpactFrames.clones()).toBe(2 * FIGURE)
			expect(FlashBudget.used(world.clock)).toBe(impact.flash.maxPerWindow)
		end)
	end)

	it("draws no more than the rig cap, joined rigs included", function()
		withWorld(function()
			local cap = impact.silhouette.maxRigs
			ImpactFrames.play("Kill", { rig("A", Vector3.new(0, 3, 0)) })
			for index = 1, cap + 2 do
				ImpactFrames.play("Kill", { rig("R" .. index, Vector3.new(index * 4, 3, 0)) })
			end
			expect(#ImpactFrames.clones()).toBe(FIGURE * cap)
		end)
	end)

	it("destroys the oldest clones past the pool cap", function()
		withWorld(function()
			local cap = impact.silhouette.poolCap
			impact.silhouette.poolCap = 2
			local ok, err = pcall(function()
				ImpactFrames.play("Final", { rig("Fighter", Vector3.new(0, 3, 0)) })
				local clones = ImpactFrames.clones()
				ImpactFrames.cancel()
				expect(ImpactFrames.pooledCount()).toBe(2)
				local destroyed = 0
				for _, clone in clones do
					if destroyedInstance(clone) then
						destroyed += 1
					end
				end
				expect(destroyed).toBe(#clones - 2)
				-- The first clone pooled is the one that went.
				expect(destroyedInstance(clones[1])).toBe(true)
			end)
			impact.silhouette.poolCap = cap
			if not ok then
				error(err, 0)
			end
		end)
	end)

	it("destroys the clones of a rig that left the world instead of pooling them", function()
		withWorld(function()
			local gone = rig("Gone", Vector3.new(0, 3, 0))
			ImpactFrames.play("Final", { gone })
			local clones = ImpactFrames.clones()
			expect(#clones).toBe(FIGURE)
			gone:Destroy()
			ImpactFrames.cancel()
			expect(ImpactFrames.pooledCount()).toBe(0)
			for _, clone in clones do
				expect(destroyedInstance(clone)).toBe(true)
			end
		end)
	end)
end)

-- A rig of `count` parts, each a little larger than the one before.
local function crowdRig(count: number): Model
	local model = Instance.new("Model")
	model.Name = "Crowd"
	for index = 1, count do
		local made = part("Part", "P" .. index, model, Vector3.new(index, 3, 0))
		made.Size = Vector3.new(index, 1, 1)
	end
	model.Parent = Instance.new("Folder")
	return model
end

describe("ImpactFrames quality", function()
	it("draws the figures at every tier, the largest parts first past the tier's cap", function()
		withWorld(function()
			for _, tier in { "High", "Medium", "Low" } do
				world.quality = tier
				world.clock += 2
				local cap = impact.quality[tier].maxPartsPerRig
				local model = crowdRig(cap + 3)
				ImpactFrames.play("Kill", { model }, { slashDirection = Vector2.new(1, 0) })
				expect(#ImpactFrames.clones()).toBe(cap)
				local names = cloneNames()
				for index = 1, 3 do
					expect(names["P" .. index]).toBeNil()
				end
				expect(names["P" .. (cap + 3)]).toBe(true)
				advance(F)
				advance(2 * F)
				expect(ImpactFrames.look()).toBe("Dark")
				local _, _, figures = tree()
				expect(figures.Visible).toBe(true)
				ImpactFrames.cancel()
				advance(F) -- the frame that shows it gone (a cut picture counts until then)
			end
		end)
	end)

	it("Low draws a kill's figures and strokes and charges the same flash cost", function()
		withWorld(function()
			world.quality = "Low"
			ImpactFrames.play("Kill", { rig("Fighter", Vector3.new(0, 3, 0)) }, { slashDirection = Vector2.new(1, 0) })
			expect(#ImpactFrames.clones()).toBe(FIGURE)
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Kill"))
			local _, background, figures, strokes = tree()
			advance(F)
			advance(2 * F)
			expect(ImpactFrames.look()).toBe("Dark")
			expectColor(background.BackgroundColor3, "OutlineInk")
			expect(figures.Visible).toBe(true)
			advance(2 * F)
			expect(ImpactFrames.look()).toBe("Ink")
			expectColor(background.BackgroundColor3, "SystemWhite")
			expect(strokes.Visible).toBe(true)
			expect(#visibleStrokes(strokes)).toBeGreaterThan(0)
		end)
	end)
end)

-- Rig folders in the viewport that still hold a clone.
local function filledRigFolders(): number
	local _, _, figures = tree()
	local count = 0
	for _, child in figures:GetChildren() do
		if child:IsA("Model") and #child:GetChildren() > 0 then
			count += 1
		end
	end
	return count
end

describe("ImpactFrames render stalls", function()
	-- How long each picture waits for its first drawn frame: its own hit-stop; a dim, its length.
	local KILL_LIMIT = ImpactSequence.capSeconds("Kill")
	local FINAL_LIMIT = ImpactSequence.capSeconds("Final")
	local DIM_LIMIT = ImpactSequence.dimSeconds()

	it("drops a sequence whose first drawn frame comes past the staleness limit, never starting it", function()
		withWorld(function()
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			-- A first frame just inside the limit starts the picture.
			ImpactFrames.play("Kill", { model })
			advance(KILL_LIMIT - 0.25 * F)
			expect(ImpactFrames.look()).toBe("Black")
			expect(ImpactFrames.remaining()).toBeCloseTo(ImpactSequence.seconds("Kill"), 1e-9)
			ImpactFrames.cancel()
			advance(F) -- the frame that shows it gone settles its claim

			-- One just past it is a hit long gone: the frame shows nothing of it.
			world.clock += 2
			ImpactFrames.play("Kill", { model })
			expect(ImpactFrames.look()).toBe("Black") -- the Kill itself, not a dim the budget chose
			advance(KILL_LIMIT + 0.25 * F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(ImpactFrames.look()).toBeNil()
			local gui, background, figures = tree()
			expect(gui.Enabled).toBe(false)
			expect(background.BackgroundTransparency).toBeCloseTo(1, 1e-6)
			expect(figures.Visible).toBe(false)
			expect(#ImpactFrames.clones()).toBe(0)
			expect(ImpactFrames.pooledCount()).toBe(FIGURE)
			expect(world.render).toBeNil()
			expect(world.heartbeat).toBeNil()
		end)
	end)

	it("lets Heartbeat end a picture no frame drew: the overlay off and its figures freed", function()
		withWorld(function()
			local a = rig("A", Vector3.new(0, 3, 0))
			local b = rig("B", Vector3.new(6, 3, 0))
			ImpactFrames.play("Kill", { a, b })
			local gui = tree()
			expect(gui.Enabled).toBe(true)
			-- Heartbeat runs, RenderStepped does not (the display asleep): inside the limit it waits.
			beat(KILL_LIMIT - 0.5 * F)
			expect(ImpactFrames.isShowing()).toBe(true)
			beat(F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(gui.Enabled).toBe(false)
			expect(#ImpactFrames.clones()).toBe(0)
			expect(ImpactFrames.pooledCount()).toBe(2 * FIGURE)
			expect(filledRigFolders()).toBe(0)
			expect(world.render).toBeNil()
			expect(world.heartbeat).toBeNil()
			expect(ImpactFrames.hiddenSeconds()).toBe(0)
			-- When rendering comes back, its first frame draws nothing of the old hit.
			advance(F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(gui.Enabled).toBe(false)
		end)
	end)

	it("lets Heartbeat end a drawn picture past its hit-stop when rendering stops mid-way", function()
		withWorld(function()
			ImpactFrames.play("Kill", { rig("Fighter", Vector3.new(0, 3, 0)) })
			advance(F) -- the first drawn frame: the clock starts
			expect(ImpactFrames.look()).toBe("Black")
			local cap = ImpactSequence.capSeconds("Kill")
			beat(cap - 0.5 * F)
			expect(ImpactFrames.isShowing()).toBe(true)
			beat(F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(tree().Enabled).toBe(false)
			expect(#ImpactFrames.clones()).toBe(0)
			expect(ImpactFrames.pooledCount()).toBe(FIGURE)
			-- Its cost still counts until a window after the overlay went.
			local endedAt = world.clock
			world.clock = endedAt + impact.flash.windowSeconds - F
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Kill"))
		end)
	end)

	it("keeps a drawn picture Heartbeat ended counted until the frame that shows it gone", function()
		withWorld(function()
			-- Drawn, then rendering stops: the last frame shown still holds the Black look, and
			-- the scene only comes back on the next rendered frame, whenever that is.
			ImpactFrames.play("Kill", { rig("Fighter", Vector3.new(0, 3, 0)) })
			advance(F)
			local cap = ImpactSequence.capSeconds("Kill")
			for _ = 1, math.ceil(cap / F) + 1 do
				beat(F)
			end
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(tree().Enabled).toBe(false)
			expect(#ImpactFrames.clones()).toBe(0)
			-- Two seconds more with nothing rendered, then the frame that comes back.
			for _ = 1, 120 do
				beat(F)
			end
			advance(F)
			local resumedAt = world.clock
			-- That frame is the picture's last change: its cost counts a window after it.
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds - F)).toBe(ImpactSequence.flashCost("Kill"))
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds + F)).toBe(0)
			-- The render step that waited for that frame lets go.
			expect(world.render).toBeNil()
			expect(world.binds - world.unbinds).toBe(0)
		end)
	end)

	it("keeps that picture counted through hits that land while the window still sleeps", function()
		withWorld(function()
			ImpactFrames.play("Kill", { rig("A", Vector3.new(0, 3, 0)) })
			advance(F)
			-- Heartbeat ends it, then the window sleeps on for two seconds.
			for _ = 1, math.ceil(ImpactSequence.capSeconds("Kill") / F) + 1 + 120 do
				beat(F)
			end
			-- A hit while it sleeps asks the budget, which still counts the frozen Kill.
			expect(FlashBudget.used(world.clock)).toBe(ImpactSequence.flashCost("Kill"))
			ImpactFrames.play("Parry", { rig("B", Vector3.new(4, 3, 0)) })
			for _ = 1, 90 do
				beat(F)
			end
			advance(F)
			local resumedAt = world.clock
			-- The frame that comes back is the Kill's last change; the Parry no frame drew is long gone.
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds - F)).toBe(ImpactSequence.flashCost("Kill"))
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds + F)).toBe(0)
		end)
	end)

	it("lets Reduce flashing start no second dim within a window of the frame that shows one gone", function()
		withWorld(function()
			FlashBudget.set(true)
			ImpactFrames.play("Final", {})
			advance(F) -- drawn
			-- Heartbeat ends it at its length; the window sleeps two seconds more.
			for _ = 1, math.ceil(ImpactSequence.dimSeconds() / F) + 120 do
				beat(F)
			end
			expect(ImpactFrames.isShowing()).toBe(false)
			advance(F) -- the frame that shows it gone
			world.clock += F
			-- One dim per window: the one that just left the screen still counts.
			expect(ImpactFrames.play("Final", {})).toBe(0)
			expect(ImpactFrames.isShowing()).toBe(false)
			world.clock += impact.flash.windowSeconds
			expect(ImpactFrames.play("Final", {})).toBeGreaterThan(0)
			FlashBudget.set(false)
		end)
	end)

	it("keeps a drawn picture cut between frames counted until the frame that shows it gone", function()
		withWorld(function()
			ImpactFrames.play("Kill", { rig("A", Vector3.new(0, 3, 0)) })
			advance(F)
			beat(F) -- rendering has stopped
			ImpactFrames.cancel()
			for _ = 1, 120 do
				beat(F)
			end
			advance(F)
			local resumedAt = world.clock
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds - F)).toBe(ImpactSequence.flashCost("Kill"))
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds + F)).toBe(0)
			expect(world.render).toBeNil()
			expect(world.binds - world.unbinds).toBe(0)
		end)
	end)

	it("keeps a taken-over picture counted when the one taking over is never drawn", function()
		withWorld(function()
			ImpactFrames.play("Parry", { rig("A", Vector3.new(0, 3, 0)) })
			advance(F) -- the inverted frame is on screen
			beat(F) -- rendering stops with it there
			-- A kill lands while the window sleeps: it takes the claim, and no frame ever draws it.
			ImpactFrames.play("Kill", { rig("B", Vector3.new(4, 3, 0)) })
			local cost = FlashBudget.used(world.clock)
			expect(cost).toBeGreaterThan(0)
			for _ = 1, 120 do
				beat(F)
			end
			expect(ImpactFrames.isShowing()).toBe(false)
			advance(F)
			local resumedAt = world.clock
			-- The frame that comes back is the parry frame's last change.
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds - F)).toBe(cost)
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds + F)).toBe(0)
			expect(world.binds - world.unbinds).toBe(0)
		end)
	end)

	it("keeps a dim a sequence cut while the window sleeps counted until the frame that shows it gone", function()
		withWorld(function()
			-- An earlier flash (its picture long gone) leaves room for a dim but not a kill.
			local t0 = world.clock
			FlashBudget.request(t0 - 0.8, 2, 0)
			ImpactFrames.play("Kill", { rig("A", Vector3.new(0, 3, 0)) })
			expect(ImpactFrames.look()).toBe("Reduced") -- the dim
			advance(F)
			-- Rendering stops while the dim shows; the earlier flash leaves the window.
			while world.clock < t0 - 0.8 + impact.flash.windowSeconds + F do
				beat(F)
			end
			expect(ImpactFrames.isShowing()).toBe(true)
			expect(ImpactFrames.play("Final", { rig("B", Vector3.new(4, 3, 0)) })).toBeGreaterThan(0)
			expect(ImpactFrames.look()).toBe("Dark")
			for _ = 1, 120 do
				beat(F)
			end
			expect(ImpactFrames.isShowing()).toBe(false)
			advance(F)
			local resumedAt = world.clock
			-- The frozen dim leaves the screen on that frame; the Final no frame drew is long gone.
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds - F)).toBe(impact.reduced.flashCost)
			expect(FlashBudget.used(resumedAt + impact.flash.windowSeconds + F)).toBe(0)
			expect(world.binds - world.unbinds).toBe(0)
		end)
	end)

	it("settles a waiting claim at once when the next picture gets no render step", function()
		withWorld(function()
			ImpactFrames.play("Kill", { rig("A", Vector3.new(0, 3, 0)) })
			advance(F)
			beat(F)
			ImpactFrames.cancel()
			-- The next picture lets go of the render step that waited, and no new one binds: no
			-- frame will ever settle the cut kill, so it ends here.
			world.renderFails = true
			ImpactFrames.play("Parry", { rig("B", Vector3.new(4, 3, 0)) })
			expect(world.render).toBeNil()
			-- Both still count a window on (the kill to a window past the length it asked for)...
			expect(FlashBudget.used(world.clock + impact.flash.windowSeconds - F)).toBe(
				ImpactSequence.flashCost("Kill") + ImpactSequence.flashCost("Parry")
			)
			-- ...and nothing counts the kill for ever.
			expect(FlashBudget.used(world.clock + 2 * impact.flash.windowSeconds)).toBe(0)
			ImpactFrames.cancel()
		end)
	end)

	it("hands the frame it waits for to the next picture's own render step", function()
		withWorld(function()
			ImpactFrames.play("Kill", { rig("A", Vector3.new(0, 3, 0)) })
			advance(F)
			local cap = ImpactSequence.capSeconds("Kill")
			for _ = 1, math.ceil(cap / F) + 1 + 120 do
				beat(F)
			end
			-- A hit while the window still sleeps, its picture dropped unseen; then another
			-- that the frame coming back draws.
			ImpactFrames.play("Parry", { rig("B", Vector3.new(4, 3, 0)) })
			for _ = 1, 30 do
				beat(F)
			end
			expect(ImpactFrames.isShowing()).toBe(false)
			world.clock += 2 -- past every window
			FlashBudget.reset()
			ImpactFrames.play("Final", { rig("C", Vector3.new(8, 3, 0)) })
			expect(world.binds - world.unbinds).toBe(1)
			advance(F)
			expect(ImpactFrames.look()).toBe("Dark")
			advance(2 * F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(world.render).toBeNil()
			expect(world.binds - world.unbinds).toBe(0)
		end)
	end)

	it("replaces an undrawn picture that went stale with the next play, its figures freed", function()
		withWorld(function()
			local a = rig("A", Vector3.new(0, 3, 0))
			local b = rig("B", Vector3.new(6, 3, 0))
			ImpactFrames.play("Kill", { a })
			-- The window froze: no frame and no Heartbeat for two seconds.
			world.clock += 2
			expect(ImpactFrames.play("Final", { b })).toBeCloseTo(ImpactSequence.seconds("Final"), 1e-9)
			-- The new hit's own picture from its start, never joined to the stale kill.
			expect(ImpactFrames.look()).toBe("Dark")
			expect(#ImpactFrames.clones()).toBe(FIGURE)
			for _, clone in ImpactFrames.clones() do
				expectFrame(clone.CFrame, sourceOf(b, clone.Name).CFrame)
			end
			expect(ImpactFrames.pooledCount()).toBe(FIGURE)
			expect(filledRigFolders()).toBe(1)
			expect(world.binds - world.unbinds).toBe(1)
			advance(F)
			expect(ImpactFrames.look()).toBe("Dark")
			advance(2 * F)
			expect(ImpactFrames.isShowing()).toBe(false)
		end)
	end)

	it("treats the soft dim the same: dropped when its first frame is late, ended by Heartbeat", function()
		withWorld(function()
			FlashBudget.set(true)
			local gap = 2 -- seconds between plays, past Reduce flashing's window
			-- First drawn frame past the limit: dropped.
			ImpactFrames.play("Final", {})
			expect(ImpactFrames.look()).toBe("Reduced")
			advance(DIM_LIMIT + 0.25 * F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(tree().Enabled).toBe(false)
			-- Never drawn while Heartbeat runs: ended past the limit.
			world.clock += gap
			ImpactFrames.play("Final", {})
			beat(DIM_LIMIT - 0.5 * F)
			expect(ImpactFrames.look()).toBe("Reduced")
			beat(F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(tree().Enabled).toBe(false)
			-- Drawn, then rendering stops: ended once it has run its length.
			world.clock += gap
			ImpactFrames.play("Final", {})
			advance(F)
			expect(ImpactFrames.look()).toBe("Reduced")
			beat(ImpactSequence.dimSeconds() - 1.5 * F)
			expect(ImpactFrames.isShowing()).toBe(true)
			beat(F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(tree().Enabled).toBe(false)
			FlashBudget.set(false)
		end)
	end)

	it("keeps the display-asleep minute clean: never up past its hit-stop, no figures piling up", function()
		withWorld(function()
			-- Measured in Play: with the display asleep RenderStepped ran 0 times a second and
			-- Heartbeat 60, for 55 s, while hits kept landing.
			local attacker = rig("Attacker", Vector3.new(0, 3, 4))
			local gui: ScreenGui? = nil
			local longestUp = { Kill = 0, Final = 0 }
			local mostClones = 0
			local mostFolders = 0
			for second = 1, 55 do
				local target = rig("T" .. second, Vector3.new(second, 3, 0))
				local name = if second % 2 == 0 then "Kill" else "Final"
				ImpactFrames.play(name, { attacker, target })
				gui = gui or tree()
				local up = 0
				for _ = 1, 60 do
					beat(F)
					if (gui :: ScreenGui).Enabled then
						up += F
					end
					mostClones = math.max(mostClones, #ImpactFrames.clones())
					mostFolders = math.max(mostFolders, filledRigFolders())
				end
				longestUp[name] = math.max(longestUp[name], up)
			end
			expect(longestUp.Kill).toBeLessThanOrEqual(KILL_LIMIT + 1e-9)
			expect(longestUp.Final).toBeLessThanOrEqual(FINAL_LIMIT + 1e-9)
			expect(mostClones).toBeLessThanOrEqual(2 * FIGURE)
			expect(mostFolders).toBeLessThanOrEqual(2)
			-- The display wakes: its first frame draws nothing of any hit from the minute asleep.
			advance(F)
			expect(ImpactFrames.isShowing()).toBe(false)
			expect((gui :: ScreenGui).Enabled).toBe(false)
			expect(#ImpactFrames.clones()).toBe(0)
		end)
	end)

	it("never cuts a picture that renders: every look drawn at 60 and at 30 fps with Heartbeat between", function()
		for _, every in { 1, 2 } do
			withWorld(function()
				ImpactFrames.play("Kill", { rig("Fighter", Vector3.new(0, 3, 0)) })
				local seen = {}
				for tick = 1, 16 do
					-- One 60 fps engine frame: the render step on the frames that draw, then Heartbeat.
					world.clock += F
					local render = world.render
					if tick % every == 0 and render ~= nil then
						render(every * F)
						local look = ImpactFrames.look()
						if look ~= nil and seen[#seen] ~= look then
							table.insert(seen, look)
						end
					end
					local heartbeat = world.heartbeat
					if heartbeat ~= nil then
						heartbeat(F)
					end
				end
				expect(seen).toEqual({ "Black", "Dark", "Ink" })
				expect(ImpactFrames.isShowing()).toBe(false)
			end)
		end
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- Staleness per sequence (D-122): each picture waits for its first drawn frame as long as its
-- own hit-stop, a dim as long as its own length
-- ---------------------------------------------------------------------------------------------

-- A rig of one part: the storm makes thousands, and their figures do not matter here.
local function bareRig(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Parent = model
	model.Parent = Instance.new("Folder")
	return model
end

-- One 60 Hz engine frame: the render step when this frame draws (a display drawing every
-- `every` frames), then Heartbeat.
local function engineFrame(draws: boolean, every: number)
	world.clock += F
	local render = world.render
	if draws and render ~= nil then
		render(every * F)
	end
	local heartbeat = world.heartbeat
	if heartbeat ~= nil then
		heartbeat(F)
	end
end

-- Plays `name` `lead` engine frames before the next drawn frame of a display that draws every
-- `every` frames; the look on each drawn frame ("-" once nothing shows).
local function looksAt(name: string, every: number, lead: number): { string }
	local seen: { string } = {}
	ImpactFrames.play(name, { rig("Fighter", Vector3.new(0, 3, 0)) })
	local tick = every - lead
	for _ = 1, 60 do
		tick += 1
		local draws = tick % every == 0
		engineFrame(draws, every)
		if draws then
			local look = ImpactFrames.look()
			table.insert(seen, look or "-")
			if look == nil then
				break
			end
		end
	end
	return seen
end

describe("ImpactFrames staleness per sequence (D-122)", function()
	it("at 15 fps a Kill and a Final play wherever the hit lands between two drawn frames", function()
		for lead = 1, 4 do
			withWorld(function()
				expect(looksAt("Kill", 4, lead)).toEqual({ "Black", "Dark", "Ink", "-" })
			end)
			withWorld(function()
				expect(looksAt("Final", 4, lead)).toEqual({ "Dark", "-" })
			end)
		end
	end)

	it("at 10 fps a Kill still plays from a first frame six frames after the hit", function()
		for lead = 1, 6 do
			withWorld(function()
				local seen = looksAt("Kill", 6, lead)
				expect(seen[1]).toBe("Black")
				expect(seen[#seen]).toBe("-")
				expect(#seen).toBeGreaterThanOrEqual(3)
			end)
		end
	end)

	it("changes nothing at 60 and 30 fps: the same looks on the same drawn frames", function()
		local expected = {
			[1] = {
				Kill = { "Black", "Black", "Dark", "Dark", "Ink", "Ink", "-" },
				Final = { "Dark", "Dark", "-" },
				Parry = { "Inverted", "-" },
			},
			[2] = {
				Kill = { "Black", "Dark", "Ink", "-" },
				Final = { "Dark", "-" },
				Parry = { "Inverted", "-" },
			},
		}
		for every, rows in expected do
			for name, looks in rows do
				for lead = 1, every do
					withWorld(function()
						expect(looksAt(name, every, lead)).toEqual(looks)
					end)
				end
			end
		end
	end)

	it("waits for the first drawn frame exactly as long as each sequence's own hit-stop", function()
		for _, name in { "Kill", "Final", "Parry" } do
			local limit = ImpactSequence.capSeconds(name)
			local first = ImpactSequence.frames(name)[1].look
			-- Heartbeat only (the window rendered nothing), then a frame just inside the limit: drawn.
			withWorld(function()
				ImpactFrames.play(name, { rig("A", Vector3.new(0, 3, 0)) })
				beat(limit - 0.75 * F)
				expect(ImpactFrames.isShowing()).toBe(true)
				advance(0.5 * F)
				expect(ImpactFrames.look()).toBe(first)
				expect(tree().Enabled).toBe(true)
			end)
			-- Just past it: Heartbeat ends it unseen and the next frame draws nothing of it.
			withWorld(function()
				ImpactFrames.play(name, { rig("A", Vector3.new(0, 3, 0)) })
				beat(limit - 0.5 * F)
				expect(ImpactFrames.isShowing()).toBe(true)
				beat(F)
				expect(ImpactFrames.isShowing()).toBe(false)
				advance(F)
				expect(ImpactFrames.look()).toBeNil()
				expect(tree().Enabled).toBe(false)
				expect(#ImpactFrames.clones()).toBe(0)
			end)
		end
	end)

	it("lets a dim wait for its first drawn frame as long as its own length", function()
		withWorld(function()
			FlashBudget.set(true)
			ImpactFrames.play("Kill", {})
			expect(ImpactFrames.look()).toBe("Reduced")
			beat(ImpactSequence.dimSeconds() - 1.5 * F)
			expect(ImpactFrames.isShowing()).toBe(true)
			advance(0.5 * F)
			-- Drawn late, it shows where its own curve is by now: fading out, never a fresh rise.
			local _, background = tree()
			expect(ImpactFrames.look()).toBe("Reduced")
			expect(1 - background.BackgroundTransparency).toBeLessThan(impact.reduced.opacity)
			FlashBudget.set(false)
		end)
	end)

	it("never puts more than the limit of flashes on screen at 15 or 10 fps, or through hitches", function()
		-- Random hit storms (1 to 3 of Final, Kill or Parry at once, 12% of frames) read off only
		-- the frames that draw: the worst region's luminance changes in any second, where a change
		-- into or out of the dim or the scene counts once.
		local function picture(): { any }
			local gui = ImpactFrames.gui()
			local look = ImpactFrames.look()
			if gui == nil or not (gui :: ScreenGui).Enabled or look == nil then
				return { "Scene" }
			end
			if look == "Reduced" then
				local background = (gui :: ScreenGui):FindFirstChild("Background") :: Frame
				return if background.BackgroundTransparency >= 0.999 then { "Scene" } else { "Dim" }
			end
			local regions = ImpactSequence.regionsOf(impact.looks[look])
			return {
				ImpactSequence.luminanceOf(regions[1]),
				ImpactSequence.luminanceOf(regions[2]),
				ImpactSequence.luminanceOf(regions[3]),
			}
		end
		local function changed(a: { any }, b: { any }): boolean
			if typeof(a[1]) == "string" or typeof(b[1]) == "string" then
				return a[1] ~= b[1]
			end
			for index = 1, 3 do
				if math.abs(a[index] - b[index]) >= impact.flash.transitionDelta then
					return true
				end
			end
			return false
		end
		local function storm(seed: number, every: number, reduced: boolean, hitches: { number }): number
			local most = 0
			withWorld(function()
				FlashBudget.set(reduced)
				local rng = Random.new(seed)
				local names = { "Final", "Kill", "Parry" }
				local changes: { number } = {}
				local last: { any } = { "Scene" }
				local stallLeft = 0
				local plays = 0
				for tick = 1, 60 * 20 do
					local rendering = stallLeft == 0
					if stallLeft > 0 then
						stallLeft -= 1
					elseif rng:NextNumber() < 0.02 then
						stallLeft = rng:NextInteger(hitches[1], hitches[2])
					end
					local draws = rendering and tick % every == 0
					engineFrame(draws, every)
					if draws then
						local now = picture()
						if changed(last, now) then
							table.insert(changes, world.clock)
						end
						last = now
					end
					if rng:NextNumber() < 0.12 then
						for _ = 1, rng:NextInteger(1, 3) do
							plays += 1
							ImpactFrames.play(names[rng:NextInteger(1, 3)], { bareRig("R" .. plays) })
						end
					end
				end
				local first = 1
				for index = 1, #changes do
					while changes[index] - changes[first] >= impact.flash.windowSeconds do
						first += 1
					end
					most = math.max(most, index - first + 1)
				end
				FlashBudget.set(false)
			end)
			return most
		end
		for _, every in { 1, 4, 6 } do
			for _, reduced in { false, true } do
				-- No hitches, short hitches inside a hit-stop, and long stalls.
				for _, hitches in { { 0, 0 }, { 2, 12 }, { 20, 150 } } do
					for seed = 1, 3 do
						local most = storm(seed, every, reduced, hitches)
						local limit = if reduced then 2 * impact.reduced.maxPerWindow else 2 * impact.flash.maxPerWindow
						expect(most).toBeLessThanOrEqual(limit)
					end
				end
			end
		end
	end)

	it("holds the hit's pose past the hit-stop: a picture first drawn late never shows the rigs move again", function()
		withWorld(function()
			local cap = ImpactSequence.capSeconds("Kill")
			local model = rig("Fighter", Vector3.new(0, 3, 0))
			local torso = sourceOf(model, "UpperTorso")
			local hitAt = world.clock
			ImpactFrames.play("Kill", { model })
			local overlay = ImpactFrames.camera() :: Camera
			-- A hitch at the kill. Inside the hit-stop the root still drifts and the camera still
			-- moves, and the first drawn frame (just inside the Kill's wait) copies both.
			beat(cap - 1.5 * F)
			torso.CFrame = torso.CFrame + Vector3.new(0, 0, 0.5)
			world.camera.CFrame = world.camera.CFrame + Vector3.new(0, 0.5, 0)
			advance(F)
			expect(ImpactFrames.look()).toBe("Black")
			local held: { [BasePart]: Vector3 } = {}
			local copied = false
			for _, clone in ImpactFrames.clones() do
				held[clone] = clone.CFrame.Position
				copied = copied or (clone.CFrame.Position - torso.CFrame.Position).Magnitude < 1e-6
			end
			expect(copied).toBe(true)
			local heldCamera = overlay.CFrame
			expect((heldCamera.Position - world.camera.CFrame.Position).Magnitude).toBeLessThan(1e-6)
			-- The hit-stop is over: the rig and the camera move again every frame. The picture runs
			-- its looks to the end, still showing the frozen moment.
			local figuresPast = 0
			for _ = 1, 30 do
				if world.clock - hitAt >= cap then
					torso.CFrame = torso.CFrame + Vector3.new(1, 0, 0)
					world.camera.CFrame = world.camera.CFrame + Vector3.new(0, 0, 1)
				end
				advance(F)
				if not ImpactFrames.isShowing() then
					break
				end
				local look = ImpactFrames.look()
				if world.clock - hitAt > cap and (look == "Dark" or look == "Ink") then
					figuresPast += 1
				end
				for _, clone in ImpactFrames.clones() do
					expect((clone.CFrame.Position - held[clone]).Magnitude).toBeLessThan(1e-6)
				end
				expect((overlay.CFrame.Position - heldCamera.Position).Magnitude).toBeLessThan(1e-6)
			end
			expect(figuresPast).toBeGreaterThan(0)
			expect(ImpactFrames.isShowing()).toBe(false)
		end)
	end)
end)
