--!strict
--[[
	The local character's respawn under Lune (D-177). Measured in Studio after LoadCharacter: the
	engine empties the PlayerGui, keeping only the LayerCollectors whose ResetOnSpawn is false, and
	PlayerGui.SkyspireNameplates was gone with every plate in it. `respawn` below does what the
	engine does to the PlayerGui's children.

	The modules are fresh copies (their own state) over the shared ones, with a Lune Player and
	PlayerGui standing in for the local player's; the stand-in is taken away at the end so the
	specs after this one see no local player, as before.
]]

local luau = require("@lune/luau")

local UI = Harness.load("src/shared/data/ui")
local Combat = Harness.load("src/shared/data/combat")
local Moments = Harness.load("src/shared/data/moments")
local Engine = Harness.load("src/client/fx/Engine")

local players = Harness.stubService("Players", {})
local player = Instance.new("Player")
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = player
players.LocalPlayer = player

local clock = 300
Engine.setClock(function()
	return clock
end)
Engine.setViewer(function()
	return Vector3.zero
end)

-- What the engine does to the PlayerGui when the local character respawns.
local function respawn(gui: Instance)
	for _, child in gui:GetChildren() do
		if not (child:IsA("LayerCollector") and (child :: any).ResetOnSpawn == false) then
			child:Destroy()
		end
	end
end

-- A fresh copy of a client module: its own state, the shared modules under it. Each spec starts
-- with an empty PlayerGui.
local function fresh(path: string): any
	playerGui:ClearAllChildren()
	local env = Harness.environment()
	env.script = Harness.node(path)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	return luau.load(Harness.readFile(path .. ".luau"), { debugName = path, environment = env :: any })()
end

local nextId = 900
local function record(kind: string, state: string?): any
	nextId += 1
	local model = Instance.new("Model")
	model.Name = kind .. nextId
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = model
	model.PrimaryPart = root
	return {
		id = nextId,
		kind = kind,
		model = model,
		name = model.Name,
		hp = if state == "Dead" then 0 else 80,
		maxHp = 100,
		gauge = 40,
		maxGauge = 100,
		state = state or "Idle",
	}
end

local function folderIn(gui: Instance): Instance?
	return gui:FindFirstChild(UI.nameplates.folderName)
end

describe("Nameplates across a respawn", function()
	it("keeps every plate over its rig after the PlayerGui reset, state carried over", function()
		local Nameplates = fresh("src/client/ui/Nameplates")
		local live, dead, shattered, other = record("Enemy"), record("Enemy"), record("Enemy"), record("Player")
		for _, entry in { live, dead, shattered, other } do
			Nameplates.attach(entry)
		end
		local folder = folderIn(playerGui)
		expect(folder).never.toBeNil()
		expect(Nameplates.plateOf(live.id).gui.Parent).toBe(folder)
		-- One rig dies (its plate holds through the freeze), one has shattered (its plate is gone).
		dead.state = "Dead"
		dead.hp = 0
		Nameplates.refresh(dead)
		local due = Nameplates.plateOf(dead.id).dueAt
		Nameplates.hide(shattered.model)

		respawn(playerGui)
		expect(folderIn(playerGui)).toBeNil() -- what Studio showed

		Nameplates.update()
		local rebuilt = folderIn(playerGui)
		expect(rebuilt).never.toBeNil()
		for _, entry in { live, dead, shattered, other } do
			local plate = Nameplates.plateOf(entry.id)
			expect(plate).never.toBeNil()
			expect(plate.gui.Parent).toBe(rebuilt)
			expect(plate.gui.Adornee).toBe(entry.model.PrimaryPart)
			expect(plate.name.Text).toBe(entry.name)
		end
		expect(Nameplates.plateOf(live.id).gui.Enabled).toBe(true)
		expect((Nameplates.plateOf(live.id).hpFill :: any).Size.X.Scale).toBeCloseTo(0.8, 1e-6)
		expect(Nameplates.plateOf(other.id).gui.Enabled).toBe(true)
		-- The dead rig keeps its plate, HP bar empty, until the shatter it was already waiting for.
		local deadPlate = Nameplates.plateOf(dead.id)
		expect(deadPlate.gui.Enabled).toBe(true)
		expect(deadPlate.dueAt).toBe(due)
		expect((deadPlate.hpFill :: any).Size.X.Scale).toBe(0)
		-- The shattered rig's plate stays gone.
		expect(Nameplates.plateOf(shattered.id).gone).toBe(true)
		expect(Nameplates.plateOf(shattered.id).gui.Enabled).toBe(false)
		clock += Moments.deathDuckDelay() + Combat.deathFreeze
		Nameplates.update()
		expect(deadPlate.gui.Enabled).toBe(false)
		for _, entry in { live, dead, shattered, other } do
			Nameplates.detach(entry)
		end
	end)

	it("keeps a dead rig's plate waiting for its scheduled shatter across the reset (D-187)", function()
		local Nameplates = fresh("src/client/ui/Nameplates")
		local dead = record("Enemy")
		Nameplates.attach(dead)
		local death = Moments.deathDuckDelay() + Combat.deathFreeze
		Nameplates.expect(dead.model, death)
		dead.state = "Dead"
		dead.hp = 0
		Nameplates.refresh(dead)
		local expected = Nameplates.plateOf(dead.id).expected
		expect(expected).never.toBeNil()

		respawn(playerGui)
		Nameplates.update()
		local plate = Nameplates.plateOf(dead.id)
		expect(plate.gui.Parent).toBe(folderIn(playerGui))
		expect(plate.expected).toBe(expected)
		-- Past the death's own fallback the coming shatter still owns the plate.
		clock += death + 0.01
		Nameplates.update()
		expect(plate.gui.Enabled).toBe(true)
		-- A shatter that never came: the plate goes once the grace is over, on the Heartbeat after
		-- the first that found it over (the shatter's delay gets that frame, D-191).
		clock += UI.nameplates.shatterGraceSeconds
		Nameplates.step(1 / 60)
		expect(plate.gui.Enabled).toBe(true)
		Nameplates.step(1 / 60)
		expect(plate.gui.Enabled).toBe(false)
		Nameplates.detach(dead)
	end)

	it("hands a rig spawned on the respawn frame a live plate before any update", function()
		local Nameplates = fresh("src/client/ui/Nameplates")
		local first = record("Enemy")
		Nameplates.attach(first)
		Nameplates.detach(first) -- its plate waits in the pool, inside the folder
		respawn(playerGui)
		-- The new character (or an enemy) is tracked in the same frame, before the Heartbeat.
		local spawned = record("Player")
		Nameplates.attach(spawned)
		local plate = Nameplates.plateOf(spawned.id)
		expect(plate.gui.Parent).toBe(folderIn(playerGui))
		expect(plate.gui.Enabled).toBe(true)
		expect(plate.gui.Adornee).toBe(spawned.model.PrimaryPart)
		Nameplates.detach(spawned)
	end)

	it("rebuilds on the Heartbeat after the reset, every time", function()
		local Nameplates = fresh("src/client/ui/Nameplates")
		local entry = record("Enemy")
		Nameplates.attach(entry)
		for _ = 1, 3 do
			respawn(playerGui)
			Nameplates.step(1 / 60)
			local plate = Nameplates.plateOf(entry.id)
			expect(plate.gui.Parent).toBe(folderIn(playerGui))
			expect(plate.gui.Enabled).toBe(true)
		end
		Nameplates.detach(entry)
	end)

	it("puts a folder that was only taken out back, the same plates in it", function()
		local Nameplates = fresh("src/client/ui/Nameplates")
		local entry = record("Enemy")
		Nameplates.attach(entry)
		local folder = folderIn(playerGui) :: Instance
		local plate = Nameplates.plateOf(entry.id)
		folder.Parent = nil
		Nameplates.step(1 / 60)
		expect(folder.Parent).toBe(playerGui)
		expect(Nameplates.plateOf(entry.id)).toBe(plate)
		expect(plate.gui.Parent).toBe(folder)
		Nameplates.detach(entry)
	end)

	it("changes nothing on a frame without a reset", function()
		local Nameplates = fresh("src/client/ui/Nameplates")
		local entry = record("Enemy")
		Nameplates.attach(entry)
		local folder = folderIn(playerGui)
		local plate = Nameplates.plateOf(entry.id)
		for _ = 1, 10 do
			Nameplates.step(1 / 60)
		end
		expect(folderIn(playerGui)).toBe(folder)
		expect(Nameplates.plateOf(entry.id)).toBe(plate)
		expect(#playerGui:GetChildren()).toBe(1)
		Nameplates.detach(entry)
	end)
end)

describe("every client ScreenGui across a respawn", function()
	it("keeps the HUD and its vignette gui", function()
		local Hud = fresh("src/client/ui/Hud")
		local gui, vignette = Hud.gui(), Hud.vignetteGui()
		expect(gui.Parent).toBe(playerGui)
		expect(vignette.Parent).toBe(playerGui)
		respawn(playerGui)
		expect(gui.Parent).toBe(playerGui)
		expect(vignette.Parent).toBe(playerGui)
		expect(Hud.gui()).toBe(gui)
	end)

	it("keeps the system line", function()
		local SystemLine = fresh("src/client/ui/SystemLine")
		SystemLine.start()
		local gui = playerGui:FindFirstChild(UI.systemLine.screenGuiName)
		expect(gui).never.toBeNil()
		respawn(playerGui)
		expect((gui :: Instance).Parent).toBe(playerGui)
	end)

	it("makes every ScreenGui in the client code with ResetOnSpawn off", function()
		local missing = {}
		for _, path in Harness.listFiles("src/client", "%.luau$") do
			local source = Harness.readFile(path)
			local _, made = source:gsub('%(%s*"ScreenGui"', "")
			if made == 0 then
				continue
			end
			local _, kept = source:gsub("ResetOnSpawn%s*=%s*false", "")
			if kept < made then
				table.insert(missing, ("%s: %d ScreenGui, %d with ResetOnSpawn false"):format(path, made, kept))
			end
		end
		expect(missing).toEqual({})
	end)
end)

-- The specs after this one run with no local player, as before.
players.LocalPlayer = nil
Engine.setClock(nil)
Engine.setViewer(nil)
