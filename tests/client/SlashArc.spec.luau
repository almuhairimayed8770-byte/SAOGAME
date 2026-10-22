--!strict
-- The reel's flat-color slash crescent and its thin chromatic slash line. The crescent is one
-- cubic Bezier with its apex on the hit, split there into two halves; each half is a Beam pair
-- between pooled attachments, curved with CurveSize0 / CurveSize1, so the spec rebuilds each
-- Beam's control points from its attachments and checks them against the curve. Time runs on a
-- fake clock and a fake per-frame step handed in through SlashArc.bind. Positions that went
-- through a CFrame are float32, so they compare to 1e-4.
local SlashArc = Harness.load("src/client/fx/SlashArc")
local Quality = Harness.load("src/client/fx/Quality")
local Engine = Harness.load("src/client/fx/Engine")
local accents = Harness.load("src/shared/data/accents")
local palette = Harness.load("src/shared/data/palette")
local Easing = Harness.load("src/shared/util/Easing")

local F = accents.frameSeconds
local arc = accents.slashArc
local slashLine = accents.slashLine

local clock = 0
local stepFn: ((number) -> ())? = nil
local connects = 0
local disconnects = 0

local function fresh()
	SlashArc.bind({
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
	})
	SlashArc.reset()
	clock = 0
	stepFn = nil
	connects = 0
	disconnects = 0
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

local function expectVector(actual: Vector3, expected: Vector3, epsilon: number?)
	local eps = epsilon or 1e-4
	expect(actual.X).toBeCloseTo(expected.X, eps)
	expect(actual.Y).toBeCloseTo(expected.Y, eps)
	expect(actual.Z).toBeCloseTo(expected.Z, eps)
end

local function expectColor(actual: Color3, expected: Color3)
	expect(actual.R).toBeCloseTo(expected.R, 1e-4)
	expect(actual.G).toBeCloseTo(expected.G, 1e-4)
	expect(actual.B).toBeCloseTo(expected.B, 1e-4)
end

local function cubic(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

local function world(attachment: Attachment): CFrame
	return (attachment.Parent :: BasePart).CFrame * attachment.CFrame
end

-- The Beam's two Bezier control points, the way the engine builds them from its attachments.
local function controls(beam: Beam): (Vector3, Vector3, Vector3, Vector3)
	local first = world(beam.Attachment0 :: Attachment)
	local last = world(beam.Attachment1 :: Attachment)
	return first.Position,
		first.Position + first.XVector * beam.CurveSize0,
		last.Position - last.XVector * beam.CurveSize1,
		last.Position
end

local function activeArcs(): { any }
	local list = {}
	for _, view in SlashArc.arcs() do
		if view.active then
			table.insert(list, view)
		end
	end
	return list
end

local function activeLines(): { any }
	local list = {}
	for _, view in SlashArc.lines() do
		if view.active then
			table.insert(list, view)
		end
	end
	return list
end

local HIT = Vector3.new(4, 3, -2)
local TANGENT = Vector3.new(1, 0, 0)
local NORMAL = Vector3.new(0, 1, 0) -- a flat swing turning about world up

describe("SlashArc crescent", function()
	it("puts the apex on the hit and bows along tangent x normal, flat in the swing plane", function()
		for name, size in arc.sizes do
			local shape = SlashArc.geometry(HIT, TANGENT * 3, NORMAL * 2, name)
			expect(shape).never.toBeNil()
			expectVector(shape.m, HIT)
			expectVector(shape.tangent, TANGENT)
			expectVector(shape.normal, NORMAL)
			expectVector(shape.outward, TANGENT:Cross(NORMAL))
			-- The two points lie on a chord along the swing, `length` apart, trailing then leading.
			local chord = shape.b - shape.a
			expect(chord.Magnitude).toBeCloseTo(size.length, 1e-4)
			expect(chord.Unit:Dot(TANGENT)).toBeCloseTo(1, 1e-6)
			-- The apex sits 3/4 of the bow off the chord's middle, on the outward side.
			local sag = shape.m - (shape.a + shape.b) * 0.5
			expectVector(sag, shape.outward * (size.bow * 0.75))
			-- Every point is in the swing plane through the hit.
			for _, point in { shape.a, shape.aControl, shape.mIn, shape.mOut, shape.bControl, shape.b } do
				expect((point - HIT):Dot(shape.normal)).toBeCloseTo(0, 1e-6)
			end
			-- The halves meet smoothly: the apex's two control points are on one line through it.
			local inward = (shape.m - shape.mIn).Unit
			local onward = (shape.mOut - shape.m).Unit
			expect(inward:Dot(onward)).toBeCloseTo(1, 1e-6)
			-- The whole crescent bows outward, and the apex is its farthest point from the chord.
			local deepest = 0
			for step = 0, 20 do
				local t = step / 20
				for _, half in
					{
						{ shape.a, shape.aControl, shape.mIn, shape.m },
						{ shape.m, shape.mOut, shape.bControl, shape.b },
					}
				do
					local point = cubic(half[1], half[2], half[3], half[4], t)
					local off = (point - shape.a):Dot(shape.outward)
					expect(off).toBeGreaterThanOrEqual(-1e-6)
					deepest = math.max(deepest, off)
				end
			end
			expect(deepest).toBeCloseTo(sag.Magnitude, 1e-6)
		end
	end)

	it("bulges the other way when the swing turns the other way", function()
		local clockwise = SlashArc.geometry(HIT, TANGENT, NORMAL, "Medium")
		local counter = SlashArc.geometry(HIT, TANGENT, -NORMAL, "Medium")
		expect(clockwise.outward:Dot(counter.outward)).toBeCloseTo(-1, 1e-6)
		expect((clockwise.a - HIT):Dot(clockwise.outward)).toBeLessThan(0)
		expect((counter.a - HIT):Dot(counter.outward)).toBeLessThan(0)
	end)

	it("squares a slanted normal against the tangent and falls back when there is no plane", function()
		local slanted = SlashArc.geometry(HIT, TANGENT, Vector3.new(0.4, 1, 0), "Medium")
		expectVector(slanted.normal, NORMAL)
		-- A normal along the tangent: the plane that holds the tangent and world up.
		local along = SlashArc.geometry(HIT, TANGENT, TANGENT, "Medium")
		expectVector(along.normal, NORMAL)
		-- A vertical chop with no usable normal still gets a plane.
		local chop = SlashArc.geometry(HIT, -NORMAL, Vector3.zero, "Medium")
		expect(chop).never.toBeNil()
		expect(chop.normal:Dot(chop.tangent)).toBeCloseTo(0, 1e-6)
		expect(chop.normal.Magnitude).toBeCloseTo(1, 1e-6)
		expect(SlashArc.geometry(HIT, Vector3.zero, NORMAL, "Medium")).toBeNil()
	end)

	it("builds the halves as Beam pairs whose curves are the crescent's", function()
		atTier("High", function()
			fresh()
			SlashArc.play(HIT, TANGENT, NORMAL, "TrailCrimson", "Large")
			local views = activeArcs()
			expect(#views).toBe(1)
			local view = views[1]
			local host = view.host :: BasePart
			expect(host.Anchored).toBe(true)
			expect(host.CanCollide).toBe(false)
			expect(host.CanQuery).toBe(false)
			expect(host.CanTouch).toBe(false)
			expect(host.Transparency).toBeCloseTo(1, 1e-6)
			local shape = SlashArc.geometry(HIT, TANGENT, NORMAL, "Large")
			expectVector(world(view.attachments[1]).Position, shape.a)
			expectVector(world(view.attachments[2]).Position, shape.m)
			expectVector(world(view.attachments[3]).Position, shape.b)
			for _, pair in { view.outer, view.inner } do
				local p0, p1, p2, p3 = controls(pair[1])
				expectVector(p0, shape.a)
				expectVector(p1, shape.aControl)
				expectVector(p2, shape.mIn)
				expectVector(p3, shape.m)
				local q0, q1, q2, q3 = controls(pair[2])
				expectVector(q0, shape.m)
				expectVector(q1, shape.mOut)
				expectVector(q2, shape.bControl)
				expectVector(q3, shape.b)
			end
			-- Face axis Y: every attachment's Y axis is the swing plane's normal, so the ribbon is flat.
			for _, attachment in view.attachments do
				expect(math.abs(world(attachment).YVector:Dot(shape.normal))).toBeCloseTo(1, 1e-6)
				expect(world(attachment).XVector:Dot(shape.normal)).toBeCloseTo(0, 1e-6)
			end
		end)
	end)

	it("tapers both points to nothing, flat-colored: token outside, a narrower SystemWhite core", function()
		atTier("High", function()
			fresh()
			SlashArc.play(HIT, TANGENT, NORMAL, "TrailCrimson", "Medium")
			local view = activeArcs()[1]
			local width = arc.sizes.Medium.width
			local innerWidth = width * arc.innerWidthFraction
			for _, pair in { { view.outer, width }, { view.inner, innerWidth } } do
				local beams, widest = pair[1], pair[2]
				expect(beams[1].Width0).toBeCloseTo(0, 1e-6)
				expect(beams[1].Width1).toBeCloseTo(widest, 1e-6)
				expect(beams[2].Width0).toBeCloseTo(widest, 1e-6)
				expect(beams[2].Width1).toBeCloseTo(0, 1e-6)
			end
			for _, beam in view.outer do
				expectColor(beam.Color.Keypoints[1].Value, palette.color3("TrailCrimson"))
				expect(beam.LightEmission).toBeCloseTo(arc.outerLightEmission, 1e-6)
			end
			for _, beam in view.inner do
				expectColor(beam.Color.Keypoints[1].Value, palette.color3("SystemWhite"))
				expect(beam.LightEmission).toBeCloseTo(arc.innerLightEmission, 1e-6)
				expect(beam.ZOffset).toBeGreaterThan(view.outer[1].ZOffset)
			end
			for _, beam in { view.outer[1], view.outer[2], view.inner[1], view.inner[2] } do
				expect(beam.Enabled).toBe(true)
				expect(beam.FaceCamera).toBe(false)
				expect(beam.Texture).toBe("")
				expect(beam.LightInfluence).toBeCloseTo(0, 1e-6)
				expect(beam.Segments).toBe(accents.quality.High.arcSegments)
			end
			-- An unknown token falls back to the default color, an unknown size to the default size.
			fresh()
			SlashArc.play(HIT, TANGENT, NORMAL, "NotAToken", "Huge")
			local fallback = activeArcs()[1]
			expectColor(fallback.outer[1].Color.Keypoints[1].Value, palette.color3(arc.defaultToken))
			expect(fallback.size).toBe(arc.defaultSize)
		end)
	end)

	it("lays the normal on the Z axis when faceAxis says Z", function()
		local before = arc.faceAxis
		arc.faceAxis = "Z"
		local ok, err = pcall(function()
			atTier("High", function()
				fresh()
				SlashArc.play(HIT, TANGENT, NORMAL, "TrailCyanWhite", "Medium")
				local view = activeArcs()[1]
				for _, attachment in view.attachments do
					expect(world(attachment).ZVector:Dot(NORMAL)).toBeCloseTo(1, 1e-6)
				end
				-- The curve does not depend on the face axis.
				local shape = SlashArc.geometry(HIT, TANGENT, NORMAL, "Medium")
				local _, p1 = controls(view.outer[1])
				expectVector(p1, shape.aControl)
			end)
		end)
		arc.faceAxis = before
		if not ok then
			error(err, 0)
		end
	end)

	it("snaps on whole in one frame, holds, then wipes from the trailing point to the leading one", function()
		atTier("High", function()
			fresh()
			local size = arc.sizes.Large
			SlashArc.play(HIT, TANGENT, NORMAL, "TrailJade", "Large")
			local view = activeArcs()[1]
			local function values(beam: Beam): { number }
				local list = {}
				for _, point in beam.Transparency.Keypoints do
					table.insert(list, point.Value)
				end
				return list
			end
			-- The first frame: every key of every beam at full strength.
			for _, value in values(view.outer[1]) do
				expect(value).toBeCloseTo(arc.outerTransparency, 1e-6)
			end
			for _, value in values(view.inner[2]) do
				expect(value).toBeCloseTo(arc.innerTransparency, 1e-6)
			end
			frames(size.holdFrames)
			-- Halfway through the wipe: the trailing point is gone, the leading point still shows,
			-- and the white core is wiped further than the color.
			frames(math.floor(size.wipeFrames * 0.5))
			local trailing = values(view.outer[1])
			local leading = values(view.outer[2])
			expect(trailing[1]).toBeCloseTo(1, 1e-6)
			expect(leading[#leading]).toBeCloseTo(arc.outerTransparency, 1e-6)
			local function gone(list: { number }): number
				local count = 0
				for _, value in list do
					if value > 1 - 1e-6 then
						count += 1
					end
				end
				return count
			end
			local outerGone = gone(trailing) + gone(leading)
			local innerGone = gone(values(view.inner[1])) + gone(values(view.inner[2]))
			expect(outerGone).toBeGreaterThan(0)
			expect(innerGone).toBeGreaterThanOrEqual(outerGone)
			-- Along each half the wipe runs one way: never more see-through toward the leading end.
			for _, list in { trailing, leading } do
				for index = 2, #list do
					expect(list[index]).toBeLessThanOrEqual(list[index - 1] + 1e-6)
				end
			end
			frames(size.wipeFrames)
			expect(SlashArc.activeCount()).toBe(0)
			for _, beam in { view.outer[1], view.outer[2], view.inner[1], view.inner[2] } do
				expect(beam.Enabled).toBe(false)
			end
			expect(disconnects).toBe(1)
		end)
	end)

	it("shows the wipe at its snapped step: at most half a step off, and every wipe frame moves it", function()
		atTier("High", function()
			local halfStep = (1 + arc.wipeSoftness) / arc.wipeSteps / 2
			for _, name in { "Medium", "Large" } do
				fresh()
				local size = arc.sizes[name]
				SlashArc.play(HIT, TANGENT, NORMAL, "TrailJade", name)
				local view = activeArcs()[1]
				local previous: number? = nil
				for frame = 1, size.holdFrames + size.wipeFrames - 1 do
					frames(1)
					local outerFront, innerFront = SlashArc.wipeFront(name, clock)
					local layers = {
						{ view.outer, outerFront :: number, arc.outerTransparency },
						{ view.inner, innerFront :: number, arc.innerTransparency },
					}
					for _, layer in layers do
						local _, snapped = SlashArc.wipeStep(layer[2])
						expect(math.abs(snapped - layer[2])).toBeLessThanOrEqual(halfStep + 1e-9)
						for half, beam in layer[1] do
							local keys = beam.Transparency.Keypoints
							expect(#keys).toBe(math.max(2, arc.wipeKeys))
							for index, key in keys do
								local s = (half - 1) * 0.5 + 0.5 * (index - 1) / (#keys - 1)
								expect(key.Value).toBeCloseTo(SlashArc.transparencyAt(s, snapped, layer[3]), 1e-5)
							end
						end
					end
					if frame > size.holdFrames then
						local step = SlashArc.wipeStep(outerFront :: number)
						expect(step).never.toBe(previous)
						previous = step
					end
				end
			end
			-- Whole before the wipe, gone at the end of it.
			expect(SlashArc.wipeStep(-arc.wipeSoftness)).toBe(0)
			expect(SlashArc.wipeStep(1)).toBe(arc.wipeSteps)
		end)
	end)

	it("eases the wipe front (never linear) and the core leads it", function()
		local size = arc.sizes.Medium
		local hold = size.holdFrames * F
		local wipe = size.wipeFrames * F
		local outer0, inner0 = SlashArc.wipeFront("Medium", 0)
		expect(outer0).toBeCloseTo(-arc.wipeSoftness, 1e-6)
		expect(inner0).toBeCloseTo(-arc.wipeSoftness, 1e-6)
		local previous = outer0
		for step = 1, 9 do
			local outer, inner = SlashArc.wipeFront("Medium", hold + wipe * step / 10)
			expect(outer).toBeGreaterThanOrEqual(previous)
			expect(inner).toBeGreaterThanOrEqual(outer)
			previous = outer
		end
		local half = SlashArc.wipeFront("Medium", hold + wipe * 0.5)
		local linear = -arc.wipeSoftness + (1 + arc.wipeSoftness) * 0.5
		expect(half).toBeCloseTo(
			-arc.wipeSoftness + (1 + arc.wipeSoftness) * Easing.evaluate(arc.wipeEasing, 0.5),
			1e-6
		)
		expect(math.abs(half - linear)).toBeGreaterThan(0.05)
		expect(SlashArc.wipeFront("Medium", SlashArc.seconds("Medium"))).toBeNil()
		-- Behind the front it is gone, past its soft edge it is whole.
		expect(SlashArc.transparencyAt(0.2, 0.3, 0.05)).toBeCloseTo(1, 1e-6)
		expect(SlashArc.transparencyAt(0.3 + arc.wipeSoftness, 0.3, 0.05)).toBeCloseTo(0.05, 1e-6)
		local inside = SlashArc.transparencyAt(0.3 + arc.wipeSoftness * 0.5, 0.3, 0.05)
		expect(inside).toBeGreaterThan(0.05)
		expect(inside).toBeLessThan(1)
	end)

	it("caps crescents at the tier's count, reuses the oldest, and sets the tier's segments", function()
		for _, tier in { "High", "Low" } do
			atTier(tier, function()
				fresh()
				local cap = accents.quality[tier].arcs
				for index = 1, cap do
					SlashArc.play(Vector3.new(index * 10, 0, 0), TANGENT, NORMAL, "TrailJade", "Medium")
				end
				expect(SlashArc.activeCount()).toBe(cap)
				local pooled = #SlashArc.arcs()
				SlashArc.play(Vector3.new(999, 0, 0), TANGENT, NORMAL, "TrailJade", "Medium")
				expect(SlashArc.activeCount()).toBe(cap)
				expect(#SlashArc.arcs()).toBe(pooled)
				local hosts = {}
				for _, view in activeArcs() do
					table.insert(hosts, math.floor((view.host :: BasePart).CFrame.Position.X + 0.5))
					expect(view.outer[1].Segments).toBe(accents.quality[tier].arcSegments)
				end
				expect(table.find(hosts, 999)).never.toBeNil()
				expect(table.find(hosts, 10)).toBeNil()
			end)
		end
		expect(accents.quality.Low.arcSegments).toBeLessThan(accents.quality.High.arcSegments)
	end)

	it("plays nothing for a swing with no direction", function()
		atTier("High", function()
			fresh()
			SlashArc.play(HIT, Vector3.zero, NORMAL, "TrailJade", "Medium")
			expect(SlashArc.activeCount()).toBe(0)
			expect(connects).toBe(0)
		end)
	end)
end)

describe("SlashArc line", function()
	-- Where a line end sits in the world. The line lays its attachments by Position on a host with
	-- no turn; Lune keeps Position apart from CFrame (the engine moves both together).
	local function point(attachment: Attachment): Vector3
		return (attachment.Parent :: BasePart).CFrame * attachment.Position
	end

	-- Runs `body` with the viewer at `viewer` and puts the engine's viewer back afterwards.
	local function seenFrom(viewer: Vector3?, body: () -> ())
		Engine.setViewer(function()
			return viewer
		end)
		local ok, err = pcall(body)
		Engine.setViewer(nil)
		if not ok then
			error(err, 0)
		end
	end

	it("draws a SystemWhite core and two split-edge copies through the hit along the tangent", function()
		seenFrom(HIT + Vector3.new(0, 0, 20), function()
			atTier("High", function()
				fresh()
				local size = slashLine.sizes.Medium
				SlashArc.line(HIT, TANGENT * 5, "Medium")
				local views = activeLines()
				expect(#views).toBe(1)
				local view = views[1]
				expect(#view.beams).toBe(1 + #slashLine.edgeTokens)
				expectColor(view.beams[1].Color.Keypoints[1].Value, palette.color3("SystemWhite"))
				expectColor(view.beams[2].Color.Keypoints[1].Value, palette.color3("TrailRose"))
				expectColor(view.beams[3].Color.Keypoints[1].Value, palette.color3("SystemCyan"))
				for index, beam in view.beams do
					expect(beam.Enabled).toBe(true)
					expect(beam.FaceCamera).toBe(slashLine.faceCamera)
					expect(beam.Texture).toBe("")
					expect(beam.CurveSize0).toBeCloseTo(0, 1e-6)
					expect(beam.CurveSize1).toBeCloseTo(0, 1e-6)
					expect(beam.Width0).toBeCloseTo(size.width, 1e-6)
					local first = point(view.starts[index])
					local last = point(view.ends[index])
					expect((last - first).Unit:Dot(TANGENT)).toBeCloseTo(1, 1e-6)
					-- The first frame: the line already spans most of its length around the hit.
					expect((last - first).Magnitude).toBeCloseTo(size.length * size.startLength, 1e-4)
					-- Faded at both ends.
					local points = beam.Transparency.Keypoints
					expect(points[1].Value).toBeCloseTo(1, 1e-6)
					expect(points[#points].Value).toBeCloseTo(1, 1e-6)
				end
				expect(view.beams[1].ZOffset).toBeGreaterThan(view.beams[2].ZOffset)
				-- The core runs through the hit; the copies sit across the screen, one each way.
				local core = (point(view.starts[1]) + point(view.ends[1])) * 0.5
				expectVector(core, HIT)
				local across = TANGENT:Cross(Vector3.zAxis) -- perpendicular to the line and the view
				for index = 2, #view.beams do
					local middle = (point(view.starts[index]) + point(view.ends[index])) * 0.5
					local offset = middle - HIT
					expect(offset:Dot(TANGENT)).toBeCloseTo(0, 1e-4)
					expect(math.abs(offset:Dot(across))).toBeCloseTo(size.edgeOffset, 1e-4)
					expect(offset:Dot(Vector3.zAxis)).toBeCloseTo(0, 1e-4)
				end
				local rose = (point(view.starts[2]) - HIT):Dot(across)
				local cyan = (point(view.starts[3]) - HIT):Dot(across)
				expect(rose * cyan).toBeLessThan(0)
			end)
		end)
	end)

	it("grows out, holds, thins to nothing and lets go", function()
		seenFrom(nil, function()
			atTier("High", function()
				fresh()
				local size = slashLine.sizes.Large
				SlashArc.line(HIT, TANGENT, "Large")
				local view = activeLines()[1]
				local function length(): number
					return (point(view.ends[1]) - point(view.starts[1])).Magnitude
				end
				local shortest = length()
				frames(size.growFrames)
				expect(length()).toBeCloseTo(size.length, 1e-4)
				expect(length()).toBeGreaterThan(shortest)
				frames(size.holdFrames)
				expect(view.beams[1].Width0).toBeCloseTo(size.width, 1e-6)
				local previous = view.beams[1].Width0
				for _ = 1, size.thinFrames - 1 do
					frames(1)
					expect(view.beams[1].Width0).toBeLessThan(previous)
					previous = view.beams[1].Width0
				end
				expect(SlashArc.activeLines()).toBe(1)
				frames(1)
				expect(SlashArc.activeLines()).toBe(0)
				for _, beam in view.beams do
					expect(beam.Enabled).toBe(false)
				end
				-- The thin-out eases in: past half width at half time, never a straight line.
				local grow, hold = size.growFrames * F, size.holdFrames * F
				local halfway = SlashArc.linePose("Large", grow + hold + size.thinFrames * F * 0.5)
				expect(halfway.width).toBeCloseTo(1 - Easing.evaluate(slashLine.thinEasing, 0.5), 1e-6)
				expect(math.abs(halfway.width - 0.5)).toBeGreaterThan(0.05)
				expect(SlashArc.lineSeconds("Large")).toBeCloseTo(
					F * (size.growFrames + size.holdFrames + size.thinFrames),
					1e-9
				)
			end)
		end)
	end)

	it("splits sideways without a viewer, drops the copies on Low and caps lines at the tier", function()
		seenFrom(nil, function()
			atTier("High", function()
				fresh()
				SlashArc.line(HIT, TANGENT, "Medium")
				local view = activeLines()[1]
				local middle = (point(view.starts[2]) + point(view.ends[2])) * 0.5
				expect((middle - HIT).Magnitude).toBeCloseTo(slashLine.sizes.Medium.edgeOffset, 1e-4)
				expect((middle - HIT):Dot(TANGENT)).toBeCloseTo(0, 1e-4)
			end)
			atTier("Low", function()
				fresh()
				SlashArc.line(HIT, TANGENT, "Medium")
				local view = activeLines()[1]
				expect(view.beams[1].Enabled).toBe(true)
				for index = 2, #view.beams do
					expect(view.beams[index].Enabled).toBe(false)
				end
			end)
			atTier("High", function()
				fresh()
				local cap = accents.quality.High.lines
				for index = 1, cap do
					SlashArc.line(Vector3.new(index * 10, 0, 0), TANGENT, "Medium")
				end
				SlashArc.line(Vector3.new(999, 0, 0), TANGENT, "Medium")
				expect(SlashArc.activeLines()).toBe(cap)
				local hosts = {}
				for _, view in activeLines() do
					table.insert(hosts, math.floor((view.host :: BasePart).CFrame.Position.X + 0.5))
				end
				expect(table.find(hosts, 999)).never.toBeNil()
				expect(table.find(hosts, 10)).toBeNil()
			end)
		end)
	end)

	it("pre-builds both pools to the largest tier's caps", function()
		fresh()
		SlashArc.start()
		local arcsPooled, linesPooled = #SlashArc.arcs(), #SlashArc.lines()
		expect(arcsPooled).toBeGreaterThanOrEqual(accents.quality.High.arcs)
		expect(linesPooled).toBeGreaterThanOrEqual(accents.quality.High.lines)
		atTier("High", function()
			for index = 1, accents.quality.High.arcs * 2 do
				SlashArc.play(Vector3.new(index, 0, 0), TANGENT, NORMAL, "TrailJade", "Medium")
				SlashArc.line(Vector3.new(index, 0, 0), TANGENT, "Medium")
			end
		end)
		expect(#SlashArc.arcs()).toBe(arcsPooled)
		expect(#SlashArc.lines()).toBe(linesPooled)
		SlashArc.reset()
	end)
end)
