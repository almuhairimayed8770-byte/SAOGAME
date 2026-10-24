--!strict
local TelegraphShapes = Harness.load("src/client/fx/TelegraphShapes")
local Fx = Harness.load("src/shared/data/fx")

local ORIGIN = { 10, 0, -5 }
local FORWARD = { 0, 0, -1 } -- Roblox forward

describe("TelegraphShapes", function()
	it("a line is one block centered half way along the facing", function()
		local pieces = TelegraphShapes.pieces({ kind = "Line", length = 8, width = 2 }, ORIGIN, FORWARD)
		expect(#pieces).toBe(1)
		local piece = pieces[1]
		expect(piece.circle).toBe(false)
		expect(piece.center[1]).toBeCloseTo(10)
		expect(piece.center[2]).toBeCloseTo(Fx.telegraph.decal.groundOffset)
		expect(piece.center[3]).toBeCloseTo(-5 - 4)
		expect(piece.yaw).toBeCloseTo(0)
		expect(piece.size).toEqual({ 2, Fx.telegraph.decal.thickness, 8 })
	end)

	it("a thin line is widened to the minimum readable width", function()
		local piece = TelegraphShapes.pieces({ kind = "Line", length = 6, width = 0.2 }, ORIGIN, FORWARD)[1]
		expect(piece.size[1]).toBe(Fx.telegraph.decal.lineMinWidth)
	end)

	it("a line follows the facing: facing +X turns the yaw a quarter to the right", function()
		local piece = TelegraphShapes.pieces({ kind = "Line", length = 4, width = 2 }, ORIGIN, { 1, 0, 0 })[1]
		expect(piece.center[1]).toBeCloseTo(12)
		expect(piece.center[3]).toBeCloseTo(-5)
		expect(math.abs(piece.yaw)).toBeCloseTo(math.pi / 2, 1e-6)
	end)

	it("a circle is one cylinder of diameter twice the radius at the origin", function()
		local pieces = TelegraphShapes.pieces({ kind = "Circle", length = 0, width = 5 }, ORIGIN, FORWARD)
		expect(#pieces).toBe(1)
		expect(pieces[1].circle).toBe(true)
		expect(pieces[1].center[1]).toBeCloseTo(10)
		expect(pieces[1].center[3]).toBeCloseTo(-5)
		expect(pieces[1].size[1]).toBeCloseTo(10)
		expect(pieces[1].size[3]).toBeCloseTo(10)
	end)

	it("a cone is a fan of slices spanning the arc, symmetric about the facing", function()
		local slices = Fx.telegraph.decal.coneSlices
		local pieces = TelegraphShapes.pieces({ kind = "Cone", length = 8, width = 90 }, ORIGIN, FORWARD)
		expect(#pieces).toBe(slices)
		local first, last = pieces[1], pieces[#pieces]
		expect(first.yaw).toBeCloseTo(-last.yaw, 1e-6)
		expect(math.abs(first.yaw)).toBeLessThan(math.rad(45))
		-- Every slice center is `length / 2` from the origin on the ground plane.
		for _, piece in pieces do
			local dx, dz = piece.center[1] - ORIGIN[1], piece.center[3] - ORIGIN[3]
			expect(math.sqrt(dx * dx + dz * dz)).toBeCloseTo(4, 1e-6)
			expect(piece.size[3]).toBe(8)
			expect(piece.circle).toBe(false)
		end
		-- Slices overlap: each is wider than its exact share of the arc at the far end.
		local exact = 2 * 8 * math.sin(math.rad(90) / slices / 2)
		expect(first.size[1]).toBeGreaterThan(exact)
		-- The middle slice points straight along the facing for an odd slice count.
		if slices % 2 == 1 then
			expect(pieces[(slices + 1) / 2].yaw).toBeCloseTo(0, 1e-6)
		end
	end)

	it("no shape draws the default cone", function()
		local pieces = TelegraphShapes.pieces(nil, ORIGIN, FORWARD)
		expect(#pieces).toBe(Fx.telegraph.decal.coneSlices)
		local default = TelegraphShapes.defaultShape()
		expect(default.kind).toBe(Fx.telegraph.decal.defaultShape.kind)
	end)

	it("the decal fades in over the wind-up, holds, and is gone at the strike", function()
		local windUp = 1
		expect(TelegraphShapes.decalAlpha(-0.1, windUp, 1)).toBe(0)
		expect(TelegraphShapes.decalAlpha(0, windUp, 1)).toBe(0)
		local early = TelegraphShapes.decalAlpha(windUp * Fx.telegraph.fadeInFraction * 0.5, windUp, 1)
		expect(early).toBeGreaterThan(0)
		expect(early).toBeLessThan(Fx.telegraph.decal.alpha)
		local held = TelegraphShapes.decalAlpha(windUp * 0.6, windUp, 1)
		expect(held).toBeCloseTo(Fx.telegraph.decal.alpha)
		expect(TelegraphShapes.decalAlpha(windUp, windUp, 1)).toBe(0)
		expect(TelegraphShapes.isOver(windUp, windUp)).toBe(true)
		expect(TelegraphShapes.isOver(windUp * 0.99, windUp)).toBe(false)
	end)

	it("intensity scales the decal but never below the visible minimum", function()
		local windUp = 0.8
		local full = TelegraphShapes.decalAlpha(0.6, windUp, 1)
		local dim = TelegraphShapes.decalAlpha(0.6, windUp, 0)
		expect(dim).toBeCloseTo(full * Fx.telegraph.intensityMin)
		expect(dim).toBeGreaterThan(0)
	end)

	it("the fill transparency ramps toward the data value and pulses near the strike", function()
		local windUp = 1
		expect(TelegraphShapes.fillTransparency(-1, windUp, 1)).toBe(1)
		expect(TelegraphShapes.fillTransparency(windUp, windUp, 1)).toBe(1)
		local mid = TelegraphShapes.fillTransparency(windUp * 0.5, windUp, 1)
		expect(mid).toBeCloseTo(Fx.telegraph.fillTransparency)
		local pulseStart = windUp * Fx.telegraph.pulseFromFraction
		local atPulseStart = TelegraphShapes.fillTransparency(pulseStart, windUp, 1)
		expect(atPulseStart).toBeCloseTo(Fx.telegraph.fillTransparency)
		local half = pulseStart + 0.5 / Fx.telegraph.pulseHz
		local dipped = TelegraphShapes.fillTransparency(half, windUp, 1)
		expect(dipped).toBeGreaterThan(atPulseStart)
		expect(dipped).toBeLessThan(1)
	end)

	it("maps kinds to the three telegraph tokens", function()
		expect(TelegraphShapes.token("Normal")).toBe("TelegraphWhite")
		expect(TelegraphShapes.token("Unblockable")).toBe("TelegraphRed")
		expect(TelegraphShapes.token("GuardBreak")).toBe("TelegraphYellow")
		expect(TelegraphShapes.token("Nonsense")).toBe("TelegraphWhite")
	end)
end)
