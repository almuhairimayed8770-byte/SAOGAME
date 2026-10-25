--!strict
--[[
	F17: the HUD at reel level. The reel review found the plates of two boars side by side drawn
	over each other, the death line about 16 px tall (its glyphs at TextSize 26), and the hotbar's
	labels tiny and faint. Each spec below holds the fix: plates lift off each other on screen
	(the nearest stays where it is), the system line is big with a dark edge that reads on a bright
	sky, and the hotbar's labels are large and opaque while in use, their stroke fading with them.

	The modules are fresh copies (their own state) with a Lune Player and PlayerGui standing in
	for the local player's; the stand-in is taken away at the end.
]]

local luau = require("@lune/luau")

local UI = Harness.load("src/shared/data/ui")
local Engine = Harness.load("src/client/fx/Engine")

local players = Harness.stubService("Players", {})
local player = Instance.new("Player")
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = player
players.LocalPlayer = player

local clock = 500
Engine.setClock(function()
	return clock
end)
Engine.setViewer(function()
	return Vector3.zero
end)

-- The review's measure: the death line's glyphs stood about 16 px tall at TextSize 26.
local GLYPH_PER_TEXT_SIZE = 16 / 26
-- A line of system text the reel can read: glyphs at least this tall (pixels).
local READABLE_GLYPH_PIXELS = 24

local function fresh(path: string): any
	local env = Harness.environment()
	env.script = Harness.node(path)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	return luau.load(Harness.readFile(path .. ".luau"), { debugName = path, environment = env :: any })()
end

describe("the death line reads at reel level (F17)", function()
	it("shows the death lines big, with a dark edge thick enough for a bright sky", function()
		local SystemLine = fresh("src/client/ui/SystemLine")
		SystemLine.start()
		local gui = playerGui:FindFirstChild(UI.systemLine.screenGuiName) :: ScreenGui
		local label = gui:FindFirstChild("SystemLine", true) :: TextLabel
		for _, text in { UI.systemLine.deathSelf, UI.systemLine.deathOther:format("Ren") } do
			SystemLine.clear()
			SystemLine.show(text, "SystemWhite")
			clock += UI.systemLine.fadeIn + 0.01
			SystemLine.step()
			SystemLine.step()
			expect(label.Text).toBe(text)
			expect(label.TextTransparency).toBe(0)
			expect(label.TextSize * GLYPH_PER_TEXT_SIZE).toBeGreaterThanOrEqual(READABLE_GLYPH_PIXELS)
			local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
			expect(stroke.Thickness).toBeGreaterThanOrEqual(2)
			expect(stroke.Transparency).toBeLessThanOrEqual(0.3)
			-- The Architect's lines stay larger than every other line.
			expect(UI.systemLine.largeTextSize).toBeGreaterThan(label.TextSize)
		end
		SystemLine.clear()
		expect(label.TextTransparency).toBe(1)
		expect((label:FindFirstChildOfClass("UIStroke") :: UIStroke).Transparency).toBe(1)
	end)
end)

describe("the hotbar reads at reel level (F17)", function()
	it("draws the keys and names large and opaque while in use, their stroke fading with them", function()
		local Hud = fresh("src/client/ui/Hud")
		Hud.start()
		Hud.showArts({ { name = "Horizontal", key = "Q" }, { name = "Vertical", key = "E" } })
		Hud.step(1 / 60)
		local list = Hud.gui():FindFirstChild("Arts") :: Frame
		local labels: { TextLabel } = {}
		for _, child in list:GetDescendants() do
			if child:IsA("TextLabel") then
				table.insert(labels, child)
			end
		end
		expect(#labels).toBe(4)
		for _, label in labels do
			local floor = if label.Name == "Key" then 18 else 20
			expect(label.TextSize).toBeGreaterThanOrEqual(floor)
			expect(label.TextTransparency).toBe(0)
			expect(label.TextStrokeTransparency).toBeLessThanOrEqual(0.3)
		end
		-- Idle past the fade: the text and its stroke go together (no ink ghost left behind).
		clock += UI.hud.artList.idleFade + UI.hud.artList.fadeSeconds + 0.1
		Hud.step(1 / 60)
		for _, label in labels do
			expect(label.TextTransparency).toBe(1)
			expect(label.TextStrokeTransparency).toBe(1)
		end
		-- Used again: back at full at once.
		Hud.noteArtUse()
		Hud.step(1 / 60)
		for _, label in labels do
			expect(label.TextTransparency).toBe(0)
		end
		Hud.stop()
	end)
end)

describe("plates never sit on each other (F17)", function()
	-- A camera at the origin looking down -Z: 20 px a stud across and up, from the screen middle.
	local function projector(world: Vector3): (number?, number?, number?)
		if world.Z >= 0 then
			return nil, nil, nil
		end
		return 960 + world.X * 20, 540 - world.Y * 20, -world.Z
	end

	local nextId = 4000
	local function enemy(position: Vector3): any
		nextId += 1
		local model = Instance.new("Model")
		model.Name = "Boar" .. nextId
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(position)
		root.Parent = model
		model.PrimaryPart = root
		return {
			id = nextId,
			kind = "Enemy",
			model = model,
			name = "Boar",
			hp = 100,
			maxHp = 100,
			gauge = 0,
			maxGauge = 100,
			state = "Idle",
		}
	end

	-- A plate's box on the screen (x, y the middle; y down), as drawn after its lift.
	local function drawn(record: any, plate: any): (number, number, number, number)
		local config = UI.nameplates.enemy
		local x, y =
			projector((record.model.PrimaryPart :: BasePart).CFrame.Position + Vector3.new(0, config.offsetStuds, 0))
		return x :: number, (y :: number) - plate.gui.SizeOffset.Y * config.height, config.width, config.height
	end

	local function overlap(a: any, plateA: any, b: any, plateB: any): boolean
		local ax, ay, aw, ah = drawn(a, plateA)
		local bx, by, bw, bh = drawn(b, plateB)
		return math.abs(ax - bx) < (aw + bw) * 0.5 and math.abs(ay - by) < (ah + bh) * 0.5
	end

	it("lifts the farther plate clear of the nearer one, and lets it down when they part", function()
		local Nameplates = fresh("src/client/ui/Nameplates")
		Nameplates.setGuiParent(function()
			return playerGui
		end)
		Nameplates.setProjector(projector)
		local near = enemy(Vector3.new(0, 0, -10))
		local far = enemy(Vector3.new(2, 0, -14))
		Nameplates.attach(near)
		Nameplates.attach(far)
		local nearPlate, farPlate = Nameplates.plateOf(near.id), Nameplates.plateOf(far.id)
		expect(overlap(near, nearPlate, far, farPlate)).toBe(true)
		for _ = 1, 60 do
			clock += 1 / 60
			Nameplates.step(1 / 60)
		end
		expect(nearPlate.gui.SizeOffset.Y).toBe(0)
		expect(farPlate.gui.SizeOffset.Y).toBeGreaterThan(0)
		expect(overlap(near, nearPlate, far, farPlate)).toBe(false)
		-- Eased, never a jump: the first frames after they part move it part of the way.
		local root = far.model.PrimaryPart :: BasePart
		root.CFrame = CFrame.new(20, 0, -14)
		Nameplates.update()
		local before = farPlate.gui.SizeOffset.Y
		clock += 1 / 60
		Nameplates.step(1 / 60)
		expect(farPlate.gui.SizeOffset.Y).toBeLessThan(before)
		expect(farPlate.gui.SizeOffset.Y).toBeGreaterThan(0)
		for _ = 1, 120 do
			clock += 1 / 60
			Nameplates.step(1 / 60)
		end
		expect(farPlate.gui.SizeOffset.Y).toBe(0)
		Nameplates.detach(near)
		Nameplates.detach(far)
		Nameplates.setProjector(nil)
	end)
	it("keeps two side-by-side enemies' plates apart while their depths swap by a hair", function()
		local Nameplates = fresh("src/client/ui/Nameplates")
		Nameplates.setGuiParent(function()
			return playerGui
		end)
		Nameplates.setProjector(projector)
		local left = enemy(Vector3.new(0, 0, -10))
		local right = enemy(Vector3.new(2, 0, -10.05))
		Nameplates.attach(left)
		Nameplates.attach(right)
		local leftPlate, rightPlate = Nameplates.plateOf(left.id), Nameplates.plateOf(right.id)
		local root = right.model.PrimaryPart :: BasePart
		local touching = 0
		for frame = 1, 360 do
			-- The drawn bodies' noise: the right one is a hair nearer, then a hair farther.
			local z = if (frame // 7) % 2 == 0 then -10.05 else -9.95
			root.CFrame = CFrame.new(2, 0, z)
			clock += 1 / 60
			Nameplates.step(1 / 60)
			if frame > 60 and overlap(left, leftPlate, right, rightPlate) then
				touching += 1
			end
		end
		expect(touching).toBe(0)
		Nameplates.detach(left)
		Nameplates.detach(right)
		Nameplates.setProjector(nil)
	end)
end)

-- The specs after this one run with no local player, as before.
players.LocalPlayer = nil
