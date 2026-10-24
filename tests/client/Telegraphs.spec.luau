--!strict
-- A telegraph's fill on a rig with no weapon part (the boar) tints the rig's own outline
-- Highlight instead of adding a second Highlight to the same model: the engine draws one
-- Highlight per adornee, and the left-over fill kept every boar from showing a hit's white
-- (issue 3). A rig with a weapon keeps its weapon-only fill. A hit's flash over a tint shows white
-- for its frames, then the tint comes back; after the strike the outline is plain again.
local Telegraphs = Harness.load("src/client/fx/Telegraphs")
local OutlineManager = Harness.load("src/client/fx/OutlineManager")
local FrameClock = Harness.load("src/client/fx/FrameClock")
local fx = Harness.load("src/shared/data/fx")
local palette = Harness.load("src/shared/data/palette")
local combat = Harness.load("src/shared/data/combat")

local function boar(): Model
	local model = Instance.new("Model")
	model.Name = "Boar"
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Parent = model
	return model
end

local function kobold(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Kobold"
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Parent = model
	local weapon = Instance.new("Part")
	weapon.Name = "Weapon"
	weapon.Parent = model
	return model, weapon
end

-- Every Highlight that adorns the model itself (its Adornee, or its parent when unset).
local function wholeRigHighlights(model: Model): { Highlight }
	local found: { Highlight } = {}
	for _, child in model:GetDescendants() do
		if child:IsA("Highlight") then
			local adornee = child.Adornee or child.Parent
			if adornee == model then
				table.insert(found, child)
			end
		end
	end
	return found
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-3
end

-- A hand-driven FrameClock; `frame(during)` is one rendered frame.
local function frames(): ((during: (() -> ())?) -> (), () -> ())
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
	return function(during: (() -> ())?)
		(startFn :: (number) -> ())(combat.hitStopFrameSeconds)
		if during ~= nil then
			during()
		end
		(endFn :: (number) -> ())(combat.hitStopFrameSeconds)
	end, function()
		FrameClock.bind(nil)
	end
end

describe("Telegraphs on a rig with no weapon part (issue 3)", function()
	it("tints the rig's own outline: one Highlight on the model, before, during and after", function()
		local model = boar()
		OutlineManager.register(model)
		expect(#wholeRigHighlights(model)).toBe(1)
		Telegraphs.show(model, "Normal", 0.6, Vector3.zero, Vector3.zAxis, nil)
		local all = wholeRigHighlights(model)
		expect(#all).toBe(1)
		local outline = all[1]
		expect(outline.Name).toBe("Outline")
		expect(outline.Enabled).toBe(true)
		local token = fx.telegraph.fillToken.Normal
		local color = palette.color3(token)
		expect(near(outline.FillColor.R, color.R) and near(outline.FillColor.G, color.G)).toBe(true)
		Telegraphs.hide(model)
		expect(#wholeRigHighlights(model)).toBe(1)
		expect(near(outline.FillTransparency, fx.outline.fillTransparency)).toBe(true)
		Telegraphs.forget(model)
		OutlineManager.unregister(model)
	end)

	it("a hit during the wind-up flashes white for its frames, then the tint comes back", function()
		local frame, done = frames()
		local model = boar()
		OutlineManager.register(model)
		Telegraphs.show(model, "Normal", 0.6, Vector3.zero, Vector3.zAxis, nil)
		local outline = wholeRigHighlights(model)[1]
		local tint = outline.FillColor
		local white = palette.color3("SystemWhite")
		local seen: { string } = {}
		local function look(): string
			if
				near(outline.FillTransparency, fx.outline.flashFillTransparency) and near(outline.FillColor.R, white.R)
			then
				return "white"
			elseif near(outline.FillColor.R, tint.R) and near(outline.FillColor.B, tint.B) then
				return "tint"
			end
			return "other"
		end
		frame(function()
			OutlineManager.flash(model, "SystemWhite", combat.highlightFlashFrames)
		end)
		table.insert(seen, look())
		for _ = 1, 3 do
			frame()
			table.insert(seen, look())
		end
		expect(seen).toEqual({ "white", "white", "tint", "tint" })
		Telegraphs.forget(model)
		OutlineManager.unregister(model)
		done()
	end)

	it("after the strike a boar's hit flashes white like any rig's", function()
		local frame, done = frames()
		local model = boar()
		OutlineManager.register(model)
		Telegraphs.show(model, "Normal", 0.6, Vector3.zero, Vector3.zAxis, nil)
		Telegraphs.hide(model)
		local outline = wholeRigHighlights(model)[1]
		local drawn: { boolean } = {}
		frame(function()
			OutlineManager.flash(model, "SystemWhite", combat.highlightFlashFrames)
		end)
		table.insert(drawn, outline.Enabled and near(outline.FillTransparency, fx.outline.flashFillTransparency))
		for _ = 1, 2 do
			frame()
			table.insert(drawn, near(outline.FillTransparency, fx.outline.flashFillTransparency))
		end
		expect(drawn).toEqual({ true, true, false })
		expect(#wholeRigHighlights(model)).toBe(1)
		Telegraphs.forget(model)
		OutlineManager.unregister(model)
		done()
	end)
end)

describe("Telegraphs on a rig with a weapon (guard)", function()
	it("fills the weapon alone with its own Highlight and leaves the outline plain", function()
		local model, weapon = kobold()
		OutlineManager.register(model)
		Telegraphs.show(model, "GuardBreak", 0.6, Vector3.zero, Vector3.zAxis, nil)
		local fill = model:FindFirstChild("TelegraphFill") :: Highlight
		expect(fill).never.toBeNil()
		expect(fill.Adornee).toBe(weapon)
		expect(fill.Enabled).toBe(true)
		local outline = model:FindFirstChild("Outline") :: Highlight
		expect(near(outline.FillTransparency, fx.outline.fillTransparency)).toBe(true)
		Telegraphs.hide(model)
		expect(fill.Enabled).toBe(false)
		Telegraphs.forget(model)
		OutlineManager.unregister(model)
	end)
end)

describe("Telegraphs on the server's beat (D-172)", function()
	local Engine = Harness.load("src/client/fx/Engine")

	-- Shows a 1 s wind-up heard `lateBy` late at `start`, applies `delays` (seconds since the show
	-- -> seconds), and returns when (on the spec clock) it went off, stepping 60 fps.
	local function endOf(lateBy: number?, delays: { { number } }?): number?
		local clock = 100
		Engine.setClock(function(): number
			return clock
		end)
		local model = kobold()
		Telegraphs.show(model, "GuardBreak", 1.0, Vector3.zero, Vector3.zAxis, nil, lateBy)
		local applied: { [number]: boolean } = {}
		local ended: number? = nil
		for _ = 1, 120 do
			clock += 1 / 60
			for index, delay in delays or {} do
				if not applied[index] and clock - 100 >= delay[1] then
					applied[index] = true
					Telegraphs.delay(model, delay[2])
				end
			end
			Telegraphs.step()
			if ended == nil and not Telegraphs.isShowing(model) then
				ended = clock - 100
			end
		end
		Telegraphs.forget(model)
		Engine.setClock(nil)
		return ended
	end

	it("ends with the server's wind-up: one heard late ends that much sooner", function()
		local onTime = endOf(nil) :: number
		expect(math.abs(onTime - 1.0) <= 1 / 60 + 1e-6).toBe(true)
		local late = endOf(0.2) :: number
		expect(math.abs(late - 0.8) <= 1 / 60 + 1e-6).toBe(true)
		-- A negative or absent lateness starts it on receipt, as before.
		expect(endOf(-0.3)).toBe(onTime)
	end)

	it("moves its end by each pause the server gives the attack, and back for one it took back", function()
		local paused = endOf(nil, { { 0.3, 0.05 }, { 0.5, 0.1 } }) :: number
		expect(math.abs(paused - 1.15) <= 1 / 60 + 1e-6).toBe(true)
		local takenBack = endOf(nil, { { 0.3, 0.05 }, { 0.6, -0.05 } }) :: number
		expect(math.abs(takenBack - 1.0) <= 1 / 60 + 1e-6).toBe(true)
		-- A rig showing none is left alone.
		Telegraphs.delay(Instance.new("Model"), 0.1)
	end)
end)
