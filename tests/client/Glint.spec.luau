--!strict
-- The reel's four-point glint at the contact point: a pooled BillboardGui star (a long cross and a
-- shorter diagonal cross in a SystemWhite core, two split-edge copies behind it a pixel or two
-- out), punched out over two frames with an overshoot, turned, then shrunk and faded. Time runs on
-- a fake clock and a fake per-frame step handed in through Glint.bind.
local Glint = Harness.load("src/client/fx/Glint")
local Quality = Harness.load("src/client/fx/Quality")
local accents = Harness.load("src/shared/data/accents")
local palette = Harness.load("src/shared/data/palette")
local Easing = Harness.load("src/shared/util/Easing")

local F = accents.frameSeconds
local glint = accents.glint

local clock = 0
local stepFn: ((number) -> ())? = nil
local watchFn: ((number) -> ())? = nil
local connects = 0
local disconnects = 0

-- A fresh fake clock, render step and Heartbeat watchdog; every glint from an earlier test is hidden.
local function fresh()
	Glint.bind({
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
		onWatch = function(fn: (number) -> ()): () -> ()
			watchFn = fn
			return function()
				if watchFn == fn then
					watchFn = nil
				end
			end
		end,
	} :: any)
	Glint.reset()
	-- Counted after the bind: letting the last test's loop go is not this test's disconnect.
	clock = 0
	stepFn = nil
	watchFn = nil
	connects = 0
	disconnects = 0
end

-- Advances the fake clock `count` engine frames with nothing rendered (the display asleep):
-- Heartbeat runs, the render step does not.
local function beats(count: number)
	for _ = 1, count do
		clock += F
		local fn = watchFn
		if fn ~= nil then
			fn(F)
		end
	end
end

-- Advances the fake clock `count` frames, running the bound step once per frame.
local function frames(count: number)
	for _ = 1, count do
		clock += F
		local fn = stepFn
		if fn ~= nil then
			fn(F)
		end
	end
end

-- Runs `body` at a quality tier and puts the tier back.
local function atTier(tier: string, body: () -> ())
	local before = Quality.get()
	Quality.set(tier)
	local ok, err = pcall(body)
	Quality.set(before)
	if not ok then
		error(err, 0)
	end
end

local function activeViews(): { any }
	local list = {}
	for _, view in Glint.slots() do
		if view.active then
			table.insert(list, view)
		end
	end
	return list
end

local function expectColor(actual: Color3, expected: Color3)
	expect(actual.R).toBeCloseTo(expected.R, 1e-4)
	expect(actual.G).toBeCloseTo(expected.G, 1e-4)
	expect(actual.B).toBeCloseTo(expected.B, 1e-4)
end

local function armsOf(layer: Frame): { Frame }
	local list = {}
	for _, child in layer:GetChildren() do
		if child:IsA("Frame") and child.Name == "Arm" then
			table.insert(list, child)
		end
	end
	return list
end

describe("Glint", function()
	it("builds a pooled, always-on-top BillboardGui star on an anchored invisible part", function()
		atTier("High", function()
			fresh()
			local at = Vector3.new(3, 4, -5)
			Glint.play(at, "Medium")
			local views = activeViews()
			expect(#views).toBe(1)
			local view = views[1]
			local gui = view.gui :: BillboardGui
			expect(gui.AlwaysOnTop).toBe(true)
			expect(gui.LightInfluence).toBeCloseTo(0, 1e-6)
			expect(gui.Enabled).toBe(true)
			expect(gui.Adornee).toBe(view.anchor)
			expect(gui.MaxDistance).toBeCloseTo(glint.maxDistance, 1e-6)
			-- Sized in studs (the scale component), with room for the overshoot.
			expect(gui.Size.X.Scale).toBeCloseTo(glint.sizes.Medium.studs * glint.canvasScale, 1e-4)
			expect(gui.Size.X.Offset).toBe(0)
			local anchor = view.anchor :: BasePart
			expect(anchor.Anchored).toBe(true)
			expect(anchor.CanCollide).toBe(false)
			expect(anchor.CanQuery).toBe(false)
			expect(anchor.CanTouch).toBe(false)
			expect(anchor.Transparency).toBeCloseTo(1, 1e-6)
			expect(anchor.CFrame.Position.X).toBeCloseTo(at.X, 1e-4)
			expect(anchor.CFrame.Position.Y).toBeCloseTo(at.Y, 1e-4)
			expect(anchor.CFrame.Position.Z).toBeCloseTo(at.Z, 1e-4)
			-- Nothing on the part can shade or light the star: no Neon, no image.
			for _, descendant in anchor:GetDescendants() do
				expect(descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") or descendant:IsA("Decal")).toBe(
					false
				)
			end
		end)
	end)

	it("draws a long cross and a shorter diagonal cross, each arm tapering to both tips", function()
		atTier("High", function()
			fresh()
			Glint.play(Vector3.zero, "Large")
			local view = activeViews()[1]
			local arms = armsOf(view.core)
			expect(#arms).toBe(#glint.arms)
			local long, diagonal = 0, 0
			for index, arm in arms do
				local def = glint.arms[index]
				expect(arm.Rotation).toBeCloseTo(def.rotation, 1e-4)
				expect(arm.Size.X.Scale).toBeCloseTo(def.length, 1e-4)
				expect(arm.Size.Y.Scale).toBeCloseTo(glint.sizes.Large.thickness.scale, 1e-6)
				expect(arm.Size.Y.Offset).toBe(glint.sizes.Large.thickness.pixels)
				if def.length >= 1 then
					long += 1
				else
					diagonal += 1
					expect(math.abs(def.rotation) % 90).toBeCloseTo(45, 1e-4)
				end
				local gradient = arm:FindFirstChildOfClass("UIGradient") :: UIGradient
				expect(gradient).never.toBeNil()
				local points = gradient.Transparency.Keypoints
				expect(points[1].Value).toBeCloseTo(1, 1e-6) -- a tip
				expect(points[#points].Value).toBeCloseTo(1, 1e-6) -- the other tip
				local middle = 1
				for _, point in points do
					if math.abs(point.Time - 0.5) < 1e-6 then
						middle = point.Value
					end
				end
				expect(middle).toBeCloseTo(0, 1e-6) -- solid in the middle
			end
			expect(long).toBe(2)
			expect(diagonal).toBe(2)
		end)
	end)

	it("puts two split-edge copies behind a SystemWhite core, offset a pixel or two each way", function()
		atTier("High", function()
			fresh()
			Glint.play(Vector3.zero, "Medium")
			local view = activeViews()[1]
			expectColor(armsOf(view.core)[1].BackgroundColor3, palette.color3("SystemWhite"))
			expect(#view.edges).toBe(#glint.edgeTokens)
			local offset = glint.sizes.Medium.edgeOffsetPixels
			for index, edge in view.edges do
				expect(edge.Visible).toBe(true)
				expect(edge.ZIndex).toBeLessThan(view.core.ZIndex)
				expectColor(armsOf(edge)[1].BackgroundColor3, palette.color3(glint.edgeTokens[index]))
				expect(edge.Position.X.Offset).toBe(glint.edgeDirections[index][1] * offset)
				expect(edge.Position.Y.Offset).toBe(glint.edgeDirections[index][2] * offset)
			end
			expectColor(armsOf(view.edges[1])[1].BackgroundColor3, palette.color3("TrailRose"))
			expectColor(armsOf(view.edges[2])[1].BackgroundColor3, palette.color3("SystemCyan"))
			-- The two copies sit on opposite sides of the core.
			expect(view.edges[1].Position.X.Offset).toBe(-view.edges[2].Position.X.Offset)
		end)
	end)

	it("punches out over two frames with an overshoot, holds, turns, then shrinks and fades", function()
		for name, size in glint.sizes do
			expect(Glint.pose(name, 0).scale).toBeCloseTo(size.startScale, 1e-6)
			-- The frame between: past full size (the overshoot), never a straight line.
			local between = Glint.pose(name, F * size.punchFrames * 0.5)
			expect(between.scale).toBeGreaterThan(1)
			local linear = size.startScale + (1 - size.startScale) * 0.5
			expect(math.abs(between.scale - linear)).toBeGreaterThan(0.05)
			expect(Glint.pose(name, F * size.punchFrames).scale).toBeCloseTo(1, 1e-6)
			local held = Glint.pose(name, F * (size.punchFrames + size.holdFrames) - 1e-4)
			expect(held.scale).toBeCloseTo(1, 1e-6)
			expect(held.transparency).toBeCloseTo(0, 1e-6)
			-- The fade: smaller and fainter frame after frame, easing in.
			local fadeStart = F * (size.punchFrames + size.holdFrames)
			local previous = Glint.pose(name, fadeStart)
			for index = 1, size.fadeFrames - 1 do
				local pose = Glint.pose(name, fadeStart + index * F)
				expect(pose.scale).toBeLessThan(previous.scale)
				expect(pose.transparency).toBeGreaterThan(previous.transparency)
				expect(pose.done).toBe(false)
				previous = pose
			end
			local halfway = Glint.pose(name, fadeStart + size.fadeFrames * F * 0.5)
			expect(halfway.transparency).toBeCloseTo(Easing.evaluate(glint.fadeEasing, 0.5), 1e-6)
			expect(math.abs(halfway.transparency - 0.5)).toBeGreaterThan(0.05)
			-- It turns a few degrees, steadily one way.
			local turned = 0
			for index = 0, size.punchFrames + size.holdFrames + size.fadeFrames - 1 do
				local pose = Glint.pose(name, index * F)
				expect(pose.rotation).toBeGreaterThanOrEqual(turned)
				turned = pose.rotation
			end
			expect(turned).toBeGreaterThan(0)
			expect(turned).toBeLessThanOrEqual(size.turnDegrees + 1e-6)
			expect(Glint.pose(name, Glint.seconds(name)).done).toBe(true)
			expect(Glint.seconds(name)).toBeCloseTo(F * (size.punchFrames + size.holdFrames + size.fadeFrames), 1e-9)
		end
	end)

	it("shows each frame's pose on the instances, capped in pixels, and turns from its start angle", function()
		atTier("High", function()
			fresh()
			Glint.play(Vector3.zero, "Parry")
			local view = activeViews()[1]
			local star = view.star :: Frame
			local cap = star:FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
			local size = glint.sizes.Parry
			local start = star.Rotation
			expect(math.abs(start)).toBeLessThanOrEqual(glint.jitterDegrees + 1e-6)
			expect(star.Size.X.Scale).toBeCloseTo(size.startScale / glint.canvasScale, 1e-4)
			expect(cap.MaxSize.X).toBeCloseTo(size.maxPixels * size.startScale, 1e-3)
			frames(1)
			local pose = Glint.pose("Parry", F)
			expect(star.Size.X.Scale).toBeCloseTo(pose.scale / glint.canvasScale, 1e-4)
			expect(star.Size.X.Scale).toBeGreaterThan(1 / glint.canvasScale) -- the overshoot shows
			expect(star.Size.X.Scale).toBeLessThanOrEqual(1) -- and fits the canvas
			expect(cap.MaxSize.X).toBeCloseTo(size.maxPixels * pose.scale, 1e-3)
			expect(star.Rotation).toBeCloseTo(start + pose.rotation, 1e-4)
			frames(size.punchFrames + size.holdFrames)
			local arm = armsOf(view.core)[1]
			local faded = Glint.pose("Parry", clock)
			expect(arm.BackgroundTransparency).toBeCloseTo(faded.transparency, 1e-4)
			local edgeArm = armsOf(view.edges[1])[1]
			expect(edgeArm.BackgroundTransparency).toBeCloseTo(
				glint.edgeTransparency + (1 - glint.edgeTransparency) * faded.transparency,
				1e-4
			)
		end)
	end)

	it("connects one step on play and lets it go once every glint is gone", function()
		atTier("High", function()
			fresh()
			Glint.play(Vector3.zero, "Small")
			Glint.play(Vector3.one, "Small")
			expect(connects).toBe(1)
			expect(Glint.activeCount()).toBe(2)
			local total = glint.sizes.Small.punchFrames + glint.sizes.Small.holdFrames + glint.sizes.Small.fadeFrames
			frames(total - 1)
			expect(Glint.activeCount()).toBe(2)
			expect(disconnects).toBe(0)
			frames(1)
			expect(Glint.activeCount()).toBe(0)
			expect(disconnects).toBe(1)
			for _, view in Glint.slots() do
				expect((view.gui :: BillboardGui).Enabled).toBe(false)
			end
			Glint.play(Vector3.zero, "Small")
			expect(connects).toBe(2)
		end)
	end)

	-- A render stall (the display asleep): no step for 55 s, then one frame whose dt the engine may
	-- report as one frame or as the whole gap. The glint is timed from its play, so the first step
	-- after the stall hides it (a render step runs before its frame draws) and lets the loop go.
	for _, reported in { F, 55 } do
		it(
			("hides a glint asked for before a render stall on the first step after it (dt %.3f)"):format(reported),
			function()
				atTier("High", function()
					fresh()
					Glint.play(Vector3.zero, "Large")
					frames(1)
					expect(Glint.activeCount()).toBe(1)
					clock += 55
					local fn = stepFn :: (number) -> ()
					fn(reported)
					expect(Glint.activeCount()).toBe(0)
					expect(disconnects).toBe(1)
					for _, view in Glint.slots() do
						expect((view.gui :: BillboardGui).Enabled).toBe(false)
					end
				end)
			end
		)
	end

	-- The display asleep (measured in Studio: RenderStepped 0/s, Heartbeat 60/s). A glint asked
	-- for then (the director lets its accents go once an undrawn impact picture gives up its wait)
	-- must not stay enabled until a render step comes: a frame presented or captured before the
	-- first render step after the stall showed it, and every one asked for during the stall stayed
	-- enabled seconds after the wake. The Heartbeat watchdog ends each at its own length.
	it("ends a glint on Heartbeat at its own length while no frame renders", function()
		atTier("High", function()
			fresh()
			Glint.play(Vector3.zero, "Large")
			local view = Glint.slots()[1]
			local playedSize = view.star.Size
			expect(watchFn).never.toBeNil()
			beats(1)
			-- Heartbeat only ends what is over; the pose is the render step's (nothing written).
			expect(view.star.Size).toBe(playedSize)
			expect(Glint.activeCount()).toBe(1)
			local total = Glint.seconds("Large")
			local count = 1
			while Glint.activeCount() > 0 and count < 600 do
				beats(1)
				count += 1
			end
			expect(Glint.activeCount()).toBe(0)
			expect(count * F).toBeLessThanOrEqual(total + F + 1e-9)
			expect(count * F).toBeGreaterThanOrEqual(total - 1e-9)
			for _, slot in Glint.slots() do
				expect((slot.gui :: BillboardGui).Enabled).toBe(false)
			end
			-- Both loops let go: nothing runs while no glint shows.
			expect(watchFn).toBeNil()
			expect(stepFn).toBeNil()
			expect(disconnects).toBe(1)
		end)
	end)

	it("a stall full of glints leaves none enabled for the frame that comes back", function()
		atTier("High", function()
			fresh()
			-- A hit a second for 54 s while nothing renders (more than the pool's cap).
			local cap = accents.quality.High.glints
			for _ = 1, 54 do
				Glint.play(Vector3.new(0, 3, 0), "Large")
				expect(Glint.activeCount()).toBe(1)
				beats(60)
			end
			expect(Glint.activeCount()).toBe(0)
			local enabled = 0
			for _, slot in Glint.slots() do
				if (slot.gui :: BillboardGui).Enabled then
					enabled += 1
				end
			end
			expect(enabled).toBe(0)
			expect(#Glint.slots()).toBeLessThanOrEqual(math.max(cap, 1))
		end)
	end)

	it("caps concurrent glints at the tier's count and reuses the oldest past it", function()
		for _, tier in { "High", "Low" } do
			atTier(tier, function()
				fresh()
				local cap = accents.quality[tier].glints
				local before = #Glint.slots()
				for index = 1, cap do
					Glint.play(Vector3.new(index, 0, 0), "Small")
					frames(1) -- each one a frame later, all still showing
				end
				expect(Glint.activeCount()).toBe(cap)
				local pooled = #Glint.slots()
				expect(pooled).toBeLessThanOrEqual(math.max(before, cap))
				Glint.play(Vector3.new(100, 0, 0), "Small")
				expect(Glint.activeCount()).toBe(cap)
				expect(#Glint.slots()).toBe(pooled)
				-- The first glint's slot took the new hit; the second one is still where it was.
				local positions = {}
				for _, view in activeViews() do
					table.insert(positions, (view.anchor :: BasePart).CFrame.Position.X)
				end
				expect(table.find(positions, 100)).never.toBeNil()
				expect(table.find(positions, 1)).toBeNil()
				if cap >= 2 then
					expect(table.find(positions, 2)).never.toBeNil()
				end
			end)
		end
	end)

	it("scales the split-edge offset by the tier and skips the copies on Low", function()
		local offset = glint.sizes.Parry.edgeOffsetPixels
		atTier("Medium", function()
			fresh()
			Glint.play(Vector3.zero, "Parry")
			local scaled = math.max(1, math.floor(offset * accents.quality.Medium.glintEdgeScale + 0.5))
			for index, edge in activeViews()[1].edges do
				expect(edge.Visible).toBe(true)
				expect(edge.Position.X.Offset).toBe(glint.edgeDirections[index][1] * scaled)
			end
			expect(scaled).toBeLessThan(offset)
		end)
		atTier("Low", function()
			fresh()
			Glint.play(Vector3.zero, "Parry")
			for _, edge in activeViews()[1].edges do
				expect(edge.Visible).toBe(false)
			end
		end)
		atTier("High", function()
			fresh()
			Glint.play(Vector3.zero, "Parry")
			for _, edge in activeViews()[1].edges do
				expect(edge.Visible).toBe(true)
			end
		end)
	end)

	it("tints the core toward an optional token and keeps SystemWhite without one", function()
		local white = palette.color3("SystemWhite")
		expectColor(Glint.coreColor(nil), white)
		expectColor(Glint.coreColor("NotAToken"), white)
		local tinted = Glint.coreColor("TrailCrimson")
		expectColor(tinted, white:Lerp(palette.color3("TrailCrimson"), glint.tintBlend))
		atTier("High", function()
			fresh()
			Glint.play(Vector3.zero, "Large", "TrailCrimson")
			local view = activeViews()[1]
			for _, arm in armsOf(view.core) do
				expectColor(arm.BackgroundColor3, tinted)
			end
			-- The split edges keep their own colors.
			expectColor(armsOf(view.edges[1])[1].BackgroundColor3, palette.color3(glint.edgeTokens[1]))
			-- A later untinted glint in the same slot is white again.
			Glint.reset()
			Glint.play(Vector3.zero, "Large")
			expectColor(armsOf(activeViews()[1].core)[1].BackgroundColor3, white)
		end)
	end)

	it("falls back to the default size for a name it does not know", function()
		atTier("High", function()
			fresh()
			Glint.play(Vector3.zero, "Gigantic")
			local view = activeViews()[1]
			expect(view.size).toBe(glint.defaultSize)
			expect(Glint.seconds("Gigantic")).toBeCloseTo(Glint.seconds(glint.defaultSize), 1e-9)
		end)
	end)

	it("pre-builds the largest tier's pool so a burst of hits never allocates", function()
		fresh()
		Glint.start()
		local most = 0
		for _, tier in accents.quality do
			most = math.max(most, tier.glints)
		end
		local pooled = #Glint.slots()
		expect(pooled).toBeGreaterThanOrEqual(most)
		atTier("High", function()
			for index = 1, most * 2 do
				Glint.play(Vector3.new(index, 0, 0), "Medium")
			end
		end)
		expect(#Glint.slots()).toBe(pooled)
		Glint.reset()
	end)
end)
