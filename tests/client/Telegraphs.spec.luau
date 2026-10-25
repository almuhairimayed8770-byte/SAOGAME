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

describe("a blow's tell holds to its snap and glints white (F7, D-CP1)", function()
	local Engine = Harness.load("src/client/fx/Engine")
	local ai = Harness.load("src/shared/data/ai")
	local F = combat.hitStopFrameSeconds

	-- Shows a 1.0 s wind-up and 0.35 s strike of `kind` on `model` (heard on time, no lead) and
	-- steps it at 60 fps. Returns each lit frame as the run of looks it showed ("kind" in the
	-- kind's color, "glint" at the glint's brightness in the glint's color), the first and last
	-- glinting frames and when the tell went out (seconds since the wind-up began).
	local function watch(model: Model, kind: string, look: () -> string): ({ string }, number?, number?, number?)
		Telegraphs.resetLatency()
		local clock = 100
		Engine.setClock(function(): number
			return clock
		end)
		Telegraphs.show(model, kind, 1.0, Vector3.zero, Vector3.zAxis, nil, nil, 0.35)
		local runs: { string } = {}
		local firstGlint: number? = nil
		local lastGlint: number? = nil
		local ended: number? = nil
		for _ = 1, 120 do
			clock += 1 / 60
			Telegraphs.step()
			if Telegraphs.isShowing(model) then
				local seen = look()
				if seen == "glint" then
					firstGlint = firstGlint or clock - 100
					lastGlint = clock - 100
				end
				if runs[#runs] ~= seen then
					table.insert(runs, seen)
				end
			elseif ended == nil then
				ended = clock - 100
			end
		end
		Telegraphs.forget(model)
		Engine.setClock(nil)
		return runs, firstGlint, lastGlint, ended
	end

	local function same(a: Color3, b: Color3): boolean
		return near(a.R, b.R) and near(a.G, b.G) and near(a.B, b.B)
	end

	it("the Kobold's Overhead stays lit to the axe's snap and goes white, fill and ground, for its glint", function()
		local model = kobold()
		local white = palette.color3(fx.telegraph.glintToken)
		local yellow = palette.color3(fx.telegraph.fillToken.GuardBreak)
		local fill: Highlight? = nil
		local runs, firstGlint, lastGlint, ended = watch(model, "GuardBreak", function(): string
			fill = fill or model:FindFirstChild("TelegraphFill") :: Highlight
			local highlight = fill :: Highlight
			local glinting = near(highlight.FillTransparency, ai.telegraph.glintFillTransparency)
			local color = if glinting then white else yellow
			if not same(highlight.FillColor, color) then
				return "other"
			end
			for _, part in Telegraphs.parts(model) do
				if not same(part.Color, color) then
					return "other"
				end
			end
			return if glinting then "glint" else "kind"
		end)
		-- Yellow, white for the glint, yellow again to the snap, then out.
		expect(runs).toEqual({ "kind", "glint", "kind" })
		local snap = 1.0 + 0.35 - ai.telegraph.snapLeadSeconds
		expect(math.abs((ended :: number) - snap) <= F + 1e-6).toBe(true)
		-- The glint: glintFrames frames on the parry window's middle, glintAimFrames early.
		local centre = 1.0 + 0.35 - combat.parryWindow / 2 - fx.telegraph.glintAimFrames * F
		local opens = centre - fx.telegraph.glintFrames * F / 2
		local closes = centre + fx.telegraph.glintFrames * F / 2
		expect(math.abs((firstGlint :: number) - opens) <= F + 1e-6).toBe(true)
		expect((lastGlint :: number) < closes + 1e-6 and (lastGlint :: number) >= closes - F - 1e-6).toBe(true)
	end)

	it("a rig with no weapon part glints white through its outline tint", function()
		local model = boar()
		OutlineManager.register(model)
		local white = palette.color3(fx.telegraph.glintToken)
		local yellow = palette.color3(fx.telegraph.fillToken.GuardBreak)
		local runs = watch(model, "GuardBreak", function(): string
			local outline = wholeRigHighlights(model)[1]
			if near(outline.FillTransparency, ai.telegraph.glintFillTransparency) then
				return if same(outline.FillColor, white) then "glint" else "other"
			end
			return if same(outline.FillColor, yellow) then "kind" else "other"
		end)
		expect(runs).toEqual({ "kind", "glint", "kind" })
		OutlineManager.unregister(model)
	end)

	it("an Unblockable blow never glints: it must be dodged (D-CP2)", function()
		local model = kobold()
		local red = palette.color3(fx.telegraph.fillToken.Unblockable)
		local fill: Highlight? = nil
		local runs, firstGlint, _, ended = watch(model, "Unblockable", function(): string
			fill = fill or model:FindFirstChild("TelegraphFill") :: Highlight
			local highlight = fill :: Highlight
			if near(highlight.FillTransparency, ai.telegraph.glintFillTransparency) then
				return "glint"
			end
			if not same(highlight.FillColor, red) then
				return "other"
			end
			for _, part in Telegraphs.parts(model) do
				if not same(part.Color, red) then
					return "other"
				end
			end
			return "kind"
		end)
		expect(runs).toEqual({ "kind" })
		expect(firstGlint).toBeNil()
		-- It still holds to the snap.
		local snap = 1.0 + 0.35 - ai.telegraph.snapLeadSeconds
		expect(math.abs((ended :: number) - snap) <= F + 1e-6).toBe(true)
	end)
end)

-- D-289: the server judges a parry on when the press reaches it, the client's one-way latency
-- after the press. The glint comes that much earlier (the least lateness of the last few tells
-- heard, fx.luau telegraph.glintLeadSamples, capped by glintLeadMax), so a press at any glinting
-- frame reaches the server inside the parry window. The server is unchanged.
describe("the glint leads by the client's latency, so a press at it parries (D-289)", function()
	local Engine = Harness.load("src/client/fx/Engine")
	local ai = Harness.load("src/shared/data/ai")
	local WIND_UP, STRIKE = 1.0, 0.35
	local LANDS = WIND_UP + STRIKE
	local STEP = 1 / 240
	local GLINT = fx.telegraph.glintFrames * combat.hitStopFrameSeconds

	-- Hears `heard` earlier tells at those latenesses, then one blow heard `lateBy` late; returns
	-- each glinting moment (seconds on the server's clock since its wind-up began).
	local function glintOf(heard: { number }, lateBy: number): { number }
		Telegraphs.resetLatency()
		local clock = 0
		Engine.setClock(function(): number
			return clock
		end)
		for _, late in heard do
			local earlier = kobold()
			Telegraphs.show(earlier, "Normal", WIND_UP, Vector3.zero, Vector3.zAxis, nil, late, STRIKE)
			Telegraphs.forget(earlier)
		end
		local model = kobold()
		clock = lateBy
		Telegraphs.show(model, "Normal", WIND_UP, Vector3.zero, Vector3.zAxis, nil, lateBy, STRIKE)
		local fill = model:FindFirstChild("TelegraphFill") :: Highlight
		local moments: { number } = {}
		while Telegraphs.isShowing(model) and clock < 3 do
			clock += STEP
			Telegraphs.step()
			if Telegraphs.isShowing(model) and near(fill.FillTransparency, ai.telegraph.glintFillTransparency) then
				table.insert(moments, clock)
			end
		end
		Telegraphs.forget(model)
		Engine.setClock(nil)
		return moments
	end

	-- True when a press at every glinting moment, reaching the server `up` later, parries.
	local function allParry(moments: { number }, up: number): boolean
		for _, at in moments do
			local arrives = at + up
			if arrives < LANDS - combat.parryWindow - 1e-9 or arrives > LANDS + 1e-9 then
				return false
			end
		end
		return true
	end

	it("a press at any glinting frame parries, from no latency to the cap", function()
		for _, latency in { 0, 0.05, 0.067, 0.1, 0.15 } do
			local moments = glintOf({ latency, latency, latency }, latency)
			-- Still the whole glint to see (to a step), only earlier.
			expect(math.abs(#moments * STEP - GLINT) <= 2 * STEP).toBe(true)
			expect(allParry(moments, latency)).toBe(true)
		end
	end)

	it("leads by the least lateness heard, so a slower press still parries", function()
		-- Jittered tells: the least of them is the path's own latency.
		local moments = glintOf({ 0.12, 0.09, 0.1, 0.13, 0.08, 0.11 }, 0.1)
		expect(math.abs(Telegraphs.glintLead() - 0.08)).toBeLessThan(1e-9)
		expect(allParry(moments, 0.08)).toBe(true)
		expect(allParry(moments, 0.12)).toBe(true)
		-- Only the last few count: a path that got slower is learned again.
		local samples = fx.telegraph.glintLeadSamples
		local heard: { number } = {}
		for _ = 1, samples do
			table.insert(heard, 0.02)
		end
		for _ = 1, samples do
			table.insert(heard, 0.1)
		end
		expect(allParry(glintOf(heard, 0.1), 0.1)).toBe(true)
		expect(math.abs(Telegraphs.glintLead() - 0.1)).toBeLessThan(1e-9)
		-- A tell heard with no lateness (nil) teaches nothing; with none heard there is no lead.
		local quiet = kobold()
		Telegraphs.show(quiet, "Normal", WIND_UP, Vector3.zero, Vector3.zAxis, nil, nil, STRIKE)
		Telegraphs.forget(quiet)
		expect(math.abs(Telegraphs.glintLead() - 0.1)).toBeLessThan(1e-9)
		Telegraphs.resetLatency()
		expect(Telegraphs.glintLead()).toBe(0)
	end)

	it("never leads by more than the cap", function()
		local cap = fx.telegraph.glintLeadMax
		local moments = glintOf({ 0.3, 0.3 }, 0.3)
		expect(math.abs(Telegraphs.glintLead() - cap)).toBeLessThan(1e-9)
		local centre = LANDS - combat.parryWindow / 2 - fx.telegraph.glintAimFrames * combat.hitStopFrameSeconds
		local opens = centre - GLINT / 2 - cap
		expect(math.abs(moments[1] - opens) <= STEP + 1e-6).toBe(true)
	end)
end)

describe("the cone lies on the ground as triangles (F11, issue 15)", function()
	local Engine = Harness.load("src/client/fx/Engine")
	local TelegraphShapes = Harness.load("src/client/fx/TelegraphShapes")

	-- The corners of a WedgePart's triangle (its right angle at the bottom of its back face, the
	-- engine's wedge), in world space.
	local function corners(part: BasePart): { Vector3 }
		local h, d = part.Size.Y, part.Size.Z
		return {
			part.CFrame:PointToWorldSpace(Vector3.new(0, -h / 2, d / 2)),
			part.CFrame:PointToWorldSpace(Vector3.new(0, -h / 2, -d / 2)),
			part.CFrame:PointToWorldSpace(Vector3.new(0, h / 2, d / 2)),
		}
	end

	it("every wedge drawn is its piece's triangle, flat, at the origin's height", function()
		local clock = 100
		Engine.setClock(function(): number
			return clock
		end)
		local model = kobold()
		local origin = Vector3.new(4, 0.5, -2)
		local facing = Vector3.new(1, 0, 1).Unit
		local shape = { kind = "Cone", length = 6, width = 60 }
		Telegraphs.show(model, "GuardBreak", 1.0, origin, facing, shape :: any, 0.6)
		local expected = TelegraphShapes.pieces(
			shape :: any,
			{ origin.X, origin.Y, origin.Z },
			{ facing.X, 0, facing.Z }
		)
		local drawn: { BasePart } = {}
		for _, part in Telegraphs.parts(model) do
			expect(part:IsA("WedgePart")).toBe(true)
			expect(part.Transparency < 1).toBe(true)
			table.insert(drawn, part)
		end
		expect(#drawn).toBe(#expected)
		local level = origin.Y + fx.telegraph.decal.groundOffset
		for _, part in drawn do
			-- Laid on its side: its thickness stands up.
			expect(math.abs(part.CFrame.RightVector.Y)).toBeCloseTo(1, 1e-6)
			local seen = corners(part)
			local matched = false
			for _, piece in expected do
				local t = TelegraphShapes.triangle(piece) :: { { number } }
				local all = true
				for index = 1, 3 do
					local want = Vector3.new(t[index][1], t[index][2], t[index][3])
					if (seen[index] - want).Magnitude > 1e-4 then
						all = false
					end
				end
				matched = matched or all
			end
			expect(matched).toBe(true)
			for _, corner in seen do
				expect(corner.Y).toBeCloseTo(level, 1e-4)
			end
		end
		Telegraphs.forget(model)
		Engine.setClock(nil)
	end)
end)
