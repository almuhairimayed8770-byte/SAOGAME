--!strict
-- Screen-edge speed lines for a dodge or a dash: a ScreenGui of thin Frames on rays from the
-- screen center, from just outside the middle third to past the edge, a quick rush in and pull
-- out over the dodge's 0.25 s. The spec rebuilds each line's two ends in pixels from its Frame
-- (Position, Size, Rotation) and checks the middle third stays clear at several screen shapes.
-- Time runs on a fake clock and a fake per-frame step handed in through SpeedLines.bind.
local SpeedLines = Harness.load("src/client/fx/SpeedLines")
local Quality = Harness.load("src/client/fx/Quality")
local accents = Harness.load("src/shared/data/accents")
local combat = Harness.load("src/shared/data/combat")
local ui = Harness.load("src/shared/data/ui")
local palette = Harness.load("src/shared/data/palette")
local Easing = Harness.load("src/shared/util/Easing")

local F = accents.frameSeconds
local speed = accents.speedLines

local clock = 0
local stepFn: ((number) -> ())? = nil
local connects = 0
local disconnects = 0
local screen: Vector2? = Vector2.new(1920, 1080)

local function fresh(viewport: Vector2?)
	SpeedLines.bind({
		now = function()
			return clock
		end,
		onStep = function(fn: (number) -> ()): () -> ()
			connects += 1
			stepFn = fn
			return function()
				disconnects += 1
				if stepFn == fn then
					stepFn = nil
				end
			end
		end,
		viewport = function(): Vector2?
			return screen
		end,
	})
	SpeedLines.reset()
	clock = 0
	stepFn = nil
	connects = 0
	disconnects = 0
	screen = viewport
end

local function frames(count: number)
	for _ = 1, count do
		clock += F
		local fn = stepFn
		if fn ~= nil then
			fn(F)
		end
	end
end

local function atTier(tier: string, body: () -> ())
	local before = Quality.get()
	Quality.set(tier)
	local ok, err = pcall(body)
	Quality.set(before)
	if not ok then
		error(err, 0)
	end
end

-- A line's inner and outer ends in pixels from the screen center (x right, y down).
local function ends(frame: Frame): (Vector2, Vector2)
	local center = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
	local radians = math.rad(frame.Rotation)
	local along = Vector2.new(math.cos(radians), math.sin(radians)) * (frame.Size.X.Offset * 0.5)
	return center - along, center + along
end

local function visibleLines(): { Frame }
	local list = {}
	for _, line in SpeedLines.view().lines do
		if line.frame.Visible then
			table.insert(list, line.frame)
		end
	end
	return list
end

-- No inner end inside the middle third of a `size` screen.
local function expectClear(size: Vector2)
	local clearX = size.X * speed.clearFraction * 0.5
	local clearY = size.Y * speed.clearFraction * 0.5
	for _, frame in visibleLines() do
		local inner = ends(frame)
		local outside = math.abs(inner.X) >= clearX - 1e-3 or math.abs(inner.Y) >= clearY - 1e-3
		if not outside then
			error(
				("a line's inner end (%.1f, %.1f) is inside the middle third of %dx%d"):format(
					inner.X,
					inner.Y,
					size.X,
					size.Y
				),
				0
			)
		end
	end
end

describe("SpeedLines", function()
	it("builds one ScreenGui under the HUD with a pool of thin lines faded at their inner ends", function()
		fresh(Vector2.new(1920, 1080))
		SpeedLines.start()
		local gui = SpeedLines.view().gui :: ScreenGui
		expect(gui:IsA("ScreenGui")).toBe(true)
		expect(gui.Name).toBe(speed.screenGuiName)
		expect(gui.IgnoreGuiInset).toBe(true)
		expect(gui.ResetOnSpawn).toBe(false)
		expect(gui.DisplayOrder).toBeLessThan(ui.hud.displayOrder)
		expect(gui.Enabled).toBe(false)
		local lines = 0
		for _, descendant in gui:GetDescendants() do
			if descendant:IsA("Frame") and descendant.Name == "Line" then
				lines += 1
				local gradient = descendant:FindFirstChildOfClass("UIGradient") :: UIGradient
				expect(gradient).never.toBeNil()
				local points = gradient.Transparency.Keypoints
				expect(points[1].Value).toBeCloseTo(1, 1e-6) -- the inner end: gone
				expect(points[#points].Value).toBeLessThan(points[1].Value)
				expect(descendant.BackgroundColor3.R).toBeCloseTo(palette.color3(speed.token).R, 1e-4)
			end
		end
		local most = 0
		for _, kind in speed.kinds do
			most = math.max(most, kind.count)
		end
		expect(lines).toBeGreaterThanOrEqual(most)
	end)

	it("shows the kind's count of lines scaled by the quality tier", function()
		for _, tier in { "High", "Medium", "Low" } do
			for name, kind in speed.kinds do
				atTier(tier, function()
					fresh(Vector2.new(1920, 1080))
					SpeedLines.play(name)
					local expected = math.floor(kind.count * accents.quality[tier].speedLineScale + 0.5)
					expect(#visibleLines()).toBe(expected)
					expect(SpeedLines.count(name, tier)).toBe(expected)
					expect((SpeedLines.view().gui :: ScreenGui).Enabled).toBe(true)
				end)
			end
		end
		expect(SpeedLines.count("Dash", "Low")).toBeLessThan(SpeedLines.count("Dash", "High"))
	end)

	it("keeps the middle third clear at any screen shape, every frame of the play", function()
		local shapes = {
			Vector2.new(1920, 1080),
			Vector2.new(2560, 1080),
			Vector2.new(1024, 768),
			Vector2.new(800, 800),
			Vector2.new(1080, 1920),
		}
		atTier("High", function()
			for _, shape in shapes do
				for name, kind in speed.kinds do
					fresh(shape)
					SpeedLines.play(name)
					expectClear(shape)
					for _ = 1, math.ceil(kind.seconds / F) do
						frames(1)
						if SpeedLines.isShowing() then
							expectClear(shape)
						end
					end
				end
			end
		end)
	end)

	it("runs each line from outside the middle third to past the screen edge while held", function()
		atTier("High", function()
			local shape = Vector2.new(1920, 1080)
			fresh(shape)
			local kind = speed.kinds.Dodge
			SpeedLines.play("Dodge")
			frames(kind.inFrames)
			for _, frame in visibleLines() do
				local _, outer = ends(frame)
				local pastEdge = math.abs(outer.X) >= shape.X * 0.5 - 1e-3 or math.abs(outer.Y) >= shape.Y * 0.5 - 1e-3
				expect(pastEdge).toBe(true)
				expect(frame.Size.Y.Offset).toBe(kind.thicknessPixels)
			end
			-- The rays go all the way round.
			local quadrants: { [string]: boolean } = {}
			for _, frame in visibleLines() do
				local inner = ends(frame)
				quadrants[(if inner.X >= 0 then "R" else "L") .. (if inner.Y >= 0 then "D" else "U")] = true
			end
			expect(quadrants.RD and quadrants.RU and quadrants.LD and quadrants.LU).toBe(true)
		end)
	end)

	it("rushes in, holds and pulls back out inside the dodge's 0.25 s, easing both ways", function()
		expect(speed.kinds.Dodge.seconds).toBe(combat.dodgeDuration)
		expect(SpeedLines.seconds("Dodge")).toBe(combat.dodgeDuration)
		for name, kind in speed.kinds do
			local rush, pull = kind.inFrames * F, kind.outFrames * F
			local start = SpeedLines.pose(name, 0)
			expect(start.fade).toBeCloseTo(1, 1e-6)
			expect(start.reachIn).toBeCloseTo(0, 1e-6)
			local halfIn = SpeedLines.pose(name, rush * 0.5)
			expect(halfIn.reachIn).toBeCloseTo(Easing.evaluate(speed.inEasing, 0.5), 1e-6)
			expect(math.abs(halfIn.reachIn - 0.5)).toBeGreaterThan(0.05)
			local held = SpeedLines.pose(name, rush + 1e-4)
			expect(held.fade).toBeCloseTo(0, 1e-6)
			expect(held.reachOut).toBeCloseTo(0, 1e-6)
			local halfOut = SpeedLines.pose(name, kind.seconds - pull * 0.5)
			expect(halfOut.reachOut).toBeCloseTo(Easing.evaluate(speed.outEasing, 0.5), 1e-6)
			expect(math.abs(halfOut.fade - 0.5)).toBeGreaterThan(0.05)
			expect(SpeedLines.pose(name, kind.seconds).done).toBe(true)
		end
	end)

	it("moves the inner ends in, then back out, as the lines fade on the frames", function()
		atTier("High", function()
			fresh(Vector2.new(1920, 1080))
			local kind = speed.kinds.Dash
			SpeedLines.play("Dash")
			local first = visibleLines()[1]
			local function innerDistance(): number
				local inner = ends(first)
				return inner.Magnitude
			end
			expect(first.BackgroundTransparency).toBeCloseTo(1, 1e-6)
			local previous = innerDistance()
			for _ = 1, kind.inFrames do
				frames(1)
				expect(innerDistance()).toBeLessThan(previous)
				previous = innerDistance()
			end
			expect(first.BackgroundTransparency).toBeCloseTo(kind.transparency, 1e-6)
			local holdFrames = math.floor(kind.seconds / F + 0.5) - kind.inFrames - kind.outFrames
			frames(holdFrames)
			expect(innerDistance()).toBeCloseTo(previous, 1e-3)
			local faded = first.BackgroundTransparency
			for _ = 1, kind.outFrames - 1 do
				frames(1)
				expect(innerDistance()).toBeGreaterThan(previous)
				expect(first.BackgroundTransparency).toBeGreaterThan(faded)
				previous = innerDistance()
				faded = first.BackgroundTransparency
			end
			expect(SpeedLines.isShowing()).toBe(true)
			frames(1)
			expect(SpeedLines.isShowing()).toBe(false)
		end)
	end)

	it("connects one step per play, restarts on a new dodge, and lets go at the end", function()
		atTier("High", function()
			fresh(Vector2.new(1920, 1080))
			SpeedLines.play("Dodge")
			frames(speed.kinds.Dodge.inFrames)
			SpeedLines.play("Dodge") -- a second dodge mid-play starts the lines over
			expect(connects).toBe(1)
			expect(SpeedLines.pose("Dodge", 0).fade).toBeCloseTo(1, 1e-6)
			expect(visibleLines()[1].BackgroundTransparency).toBeCloseTo(1, 1e-6)
			frames(math.ceil(speed.kinds.Dodge.seconds / F))
			expect(SpeedLines.isShowing()).toBe(false)
			expect(disconnects).toBe(1)
			expect((SpeedLines.view().gui :: ScreenGui).Enabled).toBe(false)
			expect(#visibleLines()).toBe(0)
		end)
	end)

	-- A render stall (the display asleep): no step for 55 s, then one frame whose dt the engine may
	-- report as one frame or as the whole gap. The lines are timed from their play, so the first
	-- step after the stall hides them before that frame draws and lets the loop go.
	for _, reported in { F, 55 } do
		it(
			("hides lines asked for before a render stall on the first step after it (dt %.3f)"):format(reported),
			function()
				atTier("High", function()
					fresh(Vector2.new(1920, 1080))
					SpeedLines.play("Dash")
					frames(1)
					expect(SpeedLines.isShowing()).toBe(true)
					clock += 55
					local fn = stepFn :: (number) -> ()
					fn(reported)
					expect(SpeedLines.isShowing()).toBe(false)
					expect((SpeedLines.view().gui :: ScreenGui).Enabled).toBe(false)
					expect(#visibleLines()).toBe(0)
					expect(disconnects).toBe(1)
				end)
			end
		)
	end

	it("covers a small share of the screen: thin lines, never a flash", function()
		atTier("High", function()
			local shape = Vector2.new(1920, 1080)
			for name, kind in speed.kinds do
				fresh(shape)
				SpeedLines.play(name)
				frames(kind.inFrames)
				local area = 0
				for _, frame in visibleLines() do
					area += frame.Size.X.Offset * frame.Size.Y.Offset
				end
				expect(area / (shape.X * shape.Y)).toBeLessThanOrEqual(speed.maxCoverage)
				expect(kind.transparency).toBeGreaterThan(0)
			end
		end)
	end)

	it(
		"lays out on the reference screen when the viewport is unknown, and plays the default kind for a bad name",
		function()
			atTier("High", function()
				fresh(nil)
				SpeedLines.play("Somersault")
				local view = SpeedLines.view()
				expect(view.kind).toBe(speed.defaultKind)
				expect(view.viewport.X).toBe(speed.referenceScreen.width)
				expect(view.viewport.Y).toBe(speed.referenceScreen.height)
				expectClear(Vector2.new(speed.referenceScreen.width, speed.referenceScreen.height))
				SpeedLines.reset()
			end)
		end
	)
end)
