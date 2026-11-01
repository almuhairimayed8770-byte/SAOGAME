--!strict
-- OutlineManager keeps every rig Highlight it lights inside the engine's budget (D-476). The engine
-- draws fx.luau budgets.highlights (31) at once; a hit's flash (OutlineManager.flash) and a
-- telegraph's tint used to light a Highlight the ranking had off, so a wide kill past the
-- budget's nearest 31 rigs lit one more Highlight per flash. A flash or tint now ranks inside the
-- budget, between the always-on importances (Boss, Lock, Party) and a resting outline: it takes
-- the farthest resting outline's slot for its frames, the always-on keep theirs, and among the
-- flashes the nearer wins. Drives the real OutlineManager on a hand-driven FrameClock, with the
-- viewer at the origin.
local OutlineManager = Harness.load("src/client/fx/OutlineManager")
local Engine = Harness.load("src/client/fx/Engine")
local FrameClock = Harness.load("src/client/fx/FrameClock")
local Quality = Harness.load("src/client/fx/Quality")
local fx = Harness.load("src/shared/data/fx")
local combat = Harness.load("src/shared/data/combat")

local BUDGET = fx.budgets.highlights
local FLASH_FRAMES = combat.highlightFlashFrames

-- A rig whose only part stands `distance` studs from the viewer.
-- Every rig a spec made, unregistered when it ends (pass or fail) so the next starts empty.
local made: { Model } = {}

local function rig(distance: number): Model
	local model = Instance.new("Model")
	table.insert(made, model)
	model.Name = "Rig" .. distance
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(distance, 0, 0)
	root.Parent = model
	model.PrimaryPart = root
	return model
end

local function lit(model: Model): boolean
	local outline = model:FindFirstChild("Outline") :: Highlight?
	return outline ~= nil and outline.Enabled
end

local function flashing(model: Model): boolean
	local outline = model:FindFirstChild("Outline") :: Highlight?
	return outline ~= nil
		and outline.Enabled
		and math.abs(outline.FillTransparency - fx.outline.flashFillTransparency) < 1e-3
end

-- Highlights the engine would draw: every lit outline among `rigs`, plus `reserved` other slots.
local function drawn(rigs: { Model }, reserved: number): number
	local count = reserved
	for _, model in rigs do
		if lit(model) then
			count += 1
		end
	end
	return count
end

-- Runs `body` with a hand-driven FrameClock (one `frame()` is one rendered frame), the viewer at
-- the origin and nothing registered (the module is shared by the whole suite: rigs other specs
-- left registered would take slots); afterwards every rig is unregistered and the clock and viewer
-- are restored.
local function withStage(body: (frame: (during: (() -> ())?) -> ()) -> ())
	OutlineManager.reset()
	local startFn: ((number) -> ())? = nil
	local endFn: ((number) -> ())? = nil
	FrameClock.bind({
		now = function(): number
			return 0
		end,
		onFrameStart = function(fn)
			startFn = fn
			return function() end
		end,
		onFrameEnd = function(fn)
			endFn = fn
			return function() end
		end,
		onHeartbeat = function()
			return function() end
		end,
	})
	Engine.setViewer(function(): Vector3?
		return Vector3.zero
	end)
	Quality.set("High")
	local ok, err = pcall(body, function(during: (() -> ())?)
		(startFn :: (number) -> ())(combat.hitStopFrameSeconds)
		if during ~= nil then
			during()
		end
		(endFn :: (number) -> ())(combat.hitStopFrameSeconds)
	end)
	for _, model in made do
		OutlineManager.unregister(model)
	end
	table.clear(made)
	FrameClock.bind(nil)
	Engine.setViewer(nil)
	if not ok then
		error(err, 0)
	end
end

-- `count` Normal rigs at 2, 4, 6 ... studs, all inside the tier's outline distance, registered.
local function crowd(count: number): { Model }
	local rigs: { Model } = {}
	for index = 1, count do
		local model = rig(index * 2)
		OutlineManager.register(model)
		table.insert(rigs, model)
	end
	return rigs
end

describe("OutlineManager: flashes stay inside the Highlight budget (D-476)", function()
	it("a wide kill on the 10 rigs past the nearest 31 lights 31 Highlights, not 41, and every flash shows", function()
		withStage(function(frame)
			local rigs = crowd(41)
			expect(Quality.params().outlineDistance).toBeGreaterThan(41 * 2)
			expect(drawn(rigs, 0)).toBe(BUDGET)
			local struck: { Model } = {}
			for index = BUDGET + 1, 41 do
				table.insert(struck, rigs[index])
			end
			local counts: { number } = {}
			local shown: { number } = {}
			local function look()
				table.insert(counts, drawn(rigs, 0))
				local count = 0
				for _, model in struck do
					if flashing(model) then
						count += 1
					end
				end
				table.insert(shown, count)
			end
			frame(function()
				for _, model in struck do
					OutlineManager.flash(model, "SystemWhite", FLASH_FRAMES)
				end
			end)
			look()
			-- The flashes took the farthest resting slots: rigs 1 to 21 keep theirs, 22 to 31 wait.
			for index = 1, BUDGET - #struck do
				expect(lit(rigs[index])).toBe(true)
			end
			for index = BUDGET - #struck + 1, BUDGET do
				expect(lit(rigs[index])).toBe(false)
			end
			for _ = 1, FLASH_FRAMES do
				frame()
				look()
			end
			expect(counts).toEqual({ BUDGET, BUDGET, BUDGET })
			expect(shown).toEqual({ #struck, #struck, 0 })
			-- The flash over, the nearest 31 rest lit again and the struck go dark.
			for index = 1, BUDGET do
				expect(lit(rigs[index])).toBe(true)
			end
			for _, model in struck do
				expect(lit(model)).toBe(false)
			end
		end)
	end)

	it("the always-on keep their slots, nearer flashes win the rest, and reserved slots count", function()
		withStage(function(frame)
			local rigs = crowd(40)
			-- A far party member and a far boss: always on, at any distance.
			local party = rig(500)
			local boss = rig(600)
			OutlineManager.register(party, "Party")
			OutlineManager.register(boss, "Boss")
			local everyone = table.clone(rigs)
			table.insert(everyone, party)
			table.insert(everyone, boss)
			-- Two telegraph weapon fills hold their own slots.
			local releaseA = OutlineManager.reserve()
			local releaseB = OutlineManager.reserve()
			expect(drawn(everyone, 2)).toBe(BUDGET)
			-- Every Normal rig flashes at once (a sweep through the crowd).
			frame(function()
				for _, model in rigs do
					OutlineManager.flash(model, "SystemWhite", FLASH_FRAMES)
				end
			end)
			expect(drawn(everyone, 2)).toBe(BUDGET)
			expect(OutlineManager.enabledCount()).toBe(BUDGET)
			expect(lit(party) and lit(boss)).toBe(true)
			-- The nearest flashes win the 27 slots left: rigs 1 to 27 show, 28 to 40 wait.
			local left = BUDGET - 2 - 2
			for index = 1, left do
				expect(flashing(rigs[index])).toBe(true)
			end
			for index = left + 1, 40 do
				expect(lit(rigs[index])).toBe(false)
			end
			frame()
			frame()
			expect(drawn(everyone, 2)).toBe(BUDGET)
			releaseA()
			releaseB()
			expect(drawn(everyone, 0)).toBe(BUDGET)
		end)
	end)

	it("a flash beyond the outline distance still shows while slots are free, then goes", function()
		withStage(function(frame)
			local near = crowd(3)
			local far = rig(Quality.params().outlineDistance + 50)
			OutlineManager.register(far)
			expect(lit(far)).toBe(false)
			frame(function()
				OutlineManager.flash(far, "HPRed", FLASH_FRAMES)
			end)
			expect(flashing(far)).toBe(true)
			frame()
			expect(flashing(far)).toBe(true)
			frame()
			expect(lit(far)).toBe(false)
			expect(drawn(near, 0)).toBe(3)
		end)
	end)

	it("a tint past the nearest 31 ranks inside the budget too, and gives its slot back on untint", function()
		withStage(function()
			local rigs = crowd(40)
			local tinted = rigs[40]
			OutlineManager.tint(tinted, Color3.new(1, 0, 0), 0.5)
			expect(drawn(rigs, 0)).toBe(BUDGET)
			expect(lit(tinted)).toBe(true)
			expect(lit(rigs[BUDGET])).toBe(false)
			OutlineManager.untint(tinted)
			expect(lit(tinted)).toBe(false)
			expect(lit(rigs[BUDGET])).toBe(true)
			expect(drawn(rigs, 0)).toBe(BUDGET)
		end)
	end)

	it("a shattered rig's flash lights nothing", function()
		withStage(function(frame)
			local rigs = crowd(2)
			OutlineManager.suspend(rigs[1], true)
			frame(function()
				OutlineManager.flash(rigs[1], "SystemWhite", FLASH_FRAMES)
			end)
			expect(lit(rigs[1])).toBe(false)
			expect(lit(rigs[2])).toBe(true)
			OutlineManager.suspend(rigs[1], false)
			expect(lit(rigs[1])).toBe(true)
		end)
	end)
end)
