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

	it("a cone is a fan of flat right triangles, symmetric about the facing", function()
		local slices = Fx.telegraph.decal.coneSlices
		local pieces = TelegraphShapes.pieces({ kind = "Cone", length = 8, width = 90 }, ORIGIN, FORWARD)
		-- Each slice is an isosceles triangle from the apex to its chord, cut in two along its axis.
		expect(#pieces).toBe(2 * slices)
		local first, last = pieces[1], pieces[#pieces]
		expect(first.yaw).toBeCloseTo(-last.yaw, 1e-6)
		expect(math.abs(first.yaw)).toBeLessThan(math.rad(45))
		for _, piece in pieces do
			expect(piece.circle).toBe(false)
			expect(piece.wedge == 1 or piece.wedge == -1).toBe(true)
			expect(piece.center[2]).toBeCloseTo(Fx.telegraph.decal.groundOffset)
			-- Every corner lies on the ground at the origin's height, within the cone's length.
			for _, corner in TelegraphShapes.triangle(piece) do
				expect(corner[2]).toBeCloseTo(Fx.telegraph.decal.groundOffset)
				local dx, dz = corner[1] - ORIGIN[1], corner[3] - ORIGIN[3]
				expect(math.sqrt(dx * dx + dz * dz)).toBeLessThan(8 + 1e-6)
			end
		end
	end)

	-- Issue 15: the overlapping blocks of the old fan doubled their alpha where two met (the seams).
	-- The triangles share their edges and never overlap: every point of the fan lies in exactly one.
	it("the cone's triangles tile the fan exactly: no seam doubles it, no gap shows the grass", function()
		local length, arc = 8, 60
		local pieces = TelegraphShapes.pieces({ kind = "Cone", length = length, width = arc }, ORIGIN, { 1, 0, 0 })
		local triangles = {}
		local area = 0
		for _, piece in pieces do
			local t = TelegraphShapes.triangle(piece)
			table.insert(triangles, t)
			local ax, az = t[2][1] - t[1][1], t[2][3] - t[1][3]
			local bx, bz = t[3][1] - t[1][1], t[3][3] - t[1][3]
			area += math.abs(ax * bz - az * bx) / 2
		end
		local slices = Fx.telegraph.decal.coneSlices
		local fan = slices * 0.5 * length * length * math.sin(math.rad(arc) / slices)
		expect(area).toBeCloseTo(fan, 1e-6)
		local function inside(t, x: number, z: number): boolean
			local sign = nil
			for index = 1, 3 do
				local a, b = t[index], t[index % 3 + 1]
				local cross = (b[1] - a[1]) * (z - a[3]) - (b[3] - a[3]) * (x - a[1])
				if math.abs(cross) < 1e-6 then
					return false -- on an edge: shared, counted by neither
				end
				local s = cross > 0
				if sign == nil then
					sign = s
				elseif sign ~= s then
					return false
				end
			end
			return true
		end
		local covered, doubled = 0, 0
		for i = 0, 80 do
			for j = -40, 40 do
				local x, z = ORIGIN[1] + i * 0.1013, ORIGIN[3] + j * 0.1007
				local count = 0
				for _, t in triangles do
					if inside(t, x, z) then
						count += 1
					end
				end
				if count > 1 then
					doubled += 1
				elseif count == 1 then
					covered += 1
				end
			end
		end
		expect(doubled).toBe(0)
		expect(covered).toBeGreaterThan(1000)
	end)

	it("no shape draws the default cone", function()
		local pieces = TelegraphShapes.pieces(nil, ORIGIN, FORWARD)
		expect(#pieces).toBe(2 * Fx.telegraph.decal.coneSlices)
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

	-- F7 (issue 9) and D-CP1: a blow's tell stays lit past the wind-up until its snap begins (the
	-- strike's landing less ai.luau telegraph.snapLeadSeconds). Its glint is fx.luau
	-- telegraph.glintFrames frames centred on the parry window's middle, glintAimFrames early: the
	-- frames a press seen on it reaches the server inside the window from, a frame or two later.
	it("a blow's tell holds through the strike to the snap and glints a few frames on the parry window", function()
		local AI = Harness.load("src/shared/data/ai")
		local combat = Harness.load("src/shared/data/combat")
		local F = combat.hitStopFrameSeconds
		local windUp, strike = 1.0, 0.35
		local lands = windUp + strike
		local ends, glintFrom, glintUntil = TelegraphShapes.timing(windUp, strike)
		expect(ends).toBeCloseTo(lands - AI.telegraph.snapLeadSeconds, 1e-9)
		local centre = lands - combat.parryWindow / 2 - Fx.telegraph.glintAimFrames * F
		expect(glintFrom).toBeCloseTo(centre - Fx.telegraph.glintFrames * F / 2, 1e-9)
		expect(glintUntil).toBeCloseTo(centre + Fx.telegraph.glintFrames * F / 2, 1e-9)
		-- Inside the parry window, and over before the snap.
		expect(glintFrom >= lands - combat.parryWindow).toBe(true)
		expect(glintUntil <= ends).toBe(true)
		local function decal(at: number, level: number?): number
			return TelegraphShapes.decalAlpha(at, windUp, level or 1, ends, glintFrom, glintUntil)
		end
		local function fill(at: number, level: number?): number
			return TelegraphShapes.fillTransparency(at, windUp, level or 1, ends, glintFrom, glintUntil)
		end
		local function glinting(at: number): boolean
			return TelegraphShapes.glinting(at, ends, glintFrom, glintUntil)
		end
		-- Past the wind-up it is still lit, the ground shape at its full alpha.
		expect(decal(windUp + 0.1)).toBeCloseTo(Fx.telegraph.decal.alpha)
		expect(fill(windUp + 0.1)).toBeLessThan(1)
		expect(glinting(windUp + 0.1)).toBe(false)
		expect(TelegraphShapes.isOver(windUp + 0.1, ends)).toBe(false)
		-- The glint: the fill at its brightest and the ground brighter, from glintFrom to glintUntil.
		local glint = AI.telegraph.glintFillTransparency
		local mid = (glintFrom + glintUntil) / 2
		expect(glinting(glintFrom - 1e-3)).toBe(false)
		expect(glinting(glintFrom)).toBe(true)
		expect(glinting(mid)).toBe(true)
		expect(glinting(glintUntil)).toBe(false)
		expect(fill(mid)).toBeCloseTo(glint)
		expect(glint).toBeLessThan(Fx.telegraph.fillTransparency)
		expect(decal(mid)).toBeCloseTo(Fx.telegraph.glintDecalAlpha)
		-- After it, to the snap: the plain lit tell again.
		local after = (glintUntil + ends) / 2
		expect(glinting(after)).toBe(false)
		expect(fill(after)).never.toBeCloseTo(glint)
		expect(fill(after)).toBeLessThan(1)
		expect(decal(after)).toBeCloseTo(Fx.telegraph.decal.alpha)
		-- Gone on the snap.
		expect(TelegraphShapes.isOver(ends, ends)).toBe(true)
		expect(decal(ends)).toBe(0)
		expect(fill(ends)).toBe(1)
		expect(glinting(ends)).toBe(false)
		-- The accessibility floor dims the glint too, never below visible.
		expect(fill(mid, 0)).toBeCloseTo(1 - (1 - glint) * Fx.telegraph.intensityMin)
		expect(decal(mid, 0)).toBeCloseTo(Fx.telegraph.glintDecalAlpha * Fx.telegraph.intensityMin)
		-- A rush's line (no strike given) still ends at its launch, with no glint.
		local rushEnds, rushFrom, rushUntil = TelegraphShapes.timing(0.6, nil)
		expect(rushEnds).toBe(0.6)
		expect(rushFrom).toBe(0.6)
		expect(rushUntil).toBe(0.6)
		expect(TelegraphShapes.glinting(0.3, rushEnds, rushFrom, rushUntil)).toBe(false)
	end)

	-- D-289: the client's press reaches the server its one-way latency late, so the glint comes that
	-- much earlier (`lead`, capped by fx.luau telegraph.glintLeadMax): a press at it reaches the
	-- server inside the parry window. The tell itself still holds to the snap.
	it("a lead moves the whole glint earlier, capped, and the tell still holds to the snap", function()
		local AI = Harness.load("src/shared/data/ai")
		local windUp, strike = 1.0, 0.35
		local plainEnds, plainFrom, plainUntil = TelegraphShapes.timing(windUp, strike)
		local ends, glintFrom, glintUntil = TelegraphShapes.timing(windUp, strike, 0.08)
		expect(ends).toBeCloseTo(plainEnds, 1e-9)
		expect(glintFrom).toBeCloseTo(plainFrom - 0.08, 1e-9)
		expect(glintUntil).toBeCloseTo(plainUntil - 0.08, 1e-9)
		-- No lead (or a negative one): the glint where it is with none.
		for _, lead in { 0, -0.2 } do
			local e, f, u = TelegraphShapes.timing(windUp, strike, lead)
			expect(e).toBeCloseTo(plainEnds, 1e-9)
			expect(f).toBeCloseTo(plainFrom, 1e-9)
			expect(u).toBeCloseTo(plainUntil, 1e-9)
		end
		-- A lead past the cap moves it by the cap alone.
		local cap = Fx.telegraph.glintLeadMax
		local _, cappedFrom, cappedUntil = TelegraphShapes.timing(windUp, strike, 1)
		expect(cappedFrom).toBeCloseTo(plainFrom - cap, 1e-9)
		expect(cappedUntil).toBeCloseTo(plainUntil - cap, 1e-9)
		-- The fill glints from glintFrom to glintUntil, then is the plain lit fill to the snap.
		local glint = AI.telegraph.glintFillTransparency
		local function fill(at: number): number
			return TelegraphShapes.fillTransparency(at, windUp, 1, ends, glintFrom, glintUntil)
		end
		expect(fill(glintFrom - 0.01)).never.toBeCloseTo(glint)
		expect(fill(glintFrom + 0.001)).toBeCloseTo(glint)
		expect(fill(glintUntil - 0.001)).toBeCloseTo(glint)
		local after = fill(glintUntil + 0.01)
		expect(after).never.toBeCloseTo(glint)
		expect(after).toBeLessThan(1)
		expect(fill(ends)).toBe(1)
		-- A rush's line has no glint to move.
		local rushEnds, rushFrom, rushUntil = TelegraphShapes.timing(0.6, nil, 0.1)
		expect(rushEnds).toBe(0.6)
		expect(rushFrom).toBe(0.6)
		expect(rushUntil).toBe(0.6)
	end)

	it("a glint never starts before the wind-up nor runs past the snap", function()
		for _, windUp in { 0, 0.05, 0.4, 1.2 } do
			for _, strike in { 0.01, 0.1, 0.2, 0.5 } do
				for _, lead in { 0, 0.05, 1 } do
					local ends, from, untilAt = TelegraphShapes.timing(windUp, strike, lead)
					expect(from >= 0 and from <= untilAt and untilAt <= ends).toBe(true)
				end
			end
		end
	end)

	it("maps kinds to the three telegraph tokens, and a glint to its own", function()
		expect(TelegraphShapes.token("Normal")).toBe("TelegraphWhite")
		expect(TelegraphShapes.token("Unblockable")).toBe("TelegraphRed")
		expect(TelegraphShapes.token("GuardBreak")).toBe("TelegraphYellow")
		expect(TelegraphShapes.token("Nonsense")).toBe("TelegraphWhite")
		expect(TelegraphShapes.token("GuardBreak", true)).toBe(Fx.telegraph.glintToken)
		expect(TelegraphShapes.token("GuardBreak", false)).toBe("TelegraphYellow")
		-- Only a blow that can be parried glints (D-CP2): an Unblockable one must be dodged.
		expect(TelegraphShapes.glints("Normal")).toBe(true)
		expect(TelegraphShapes.glints("GuardBreak")).toBe(true)
		expect(TelegraphShapes.glints("Unblockable")).toBe(false)
		expect(TelegraphShapes.glints("Nonsense")).toBe(false)
	end)

	it(
		"the glint's numbers: whole frames, a palette token, brighter than the tell, never on an Unblockable blow",
		function()
			local Palette = Harness.load("src/shared/data/palette")
			local combat = Harness.load("src/shared/data/combat")
			local Enemies = Harness.load("src/shared/data/enemies")
			local Bosses = Harness.load("src/shared/data/bosses")
			local t = Fx.telegraph
			expect(typeof(t.glintFrames) == "number" and t.glintFrames >= 1).toBe(true)
			expect(t.glintFrames == math.floor(t.glintFrames)).toBe(true)
			expect(typeof(t.glintAimFrames) == "number" and t.glintAimFrames >= 0).toBe(true)
			expect(Palette.tokens[t.glintToken]).never.toBeNil()
			expect(t.glintDecalAlpha > t.decal.alpha and t.glintDecalAlpha <= 1).toBe(true)
			expect(t.glintKinds.Normal).toBe(true)
			expect(t.glintKinds.GuardBreak).toBe(true)
			expect(t.glintKinds.Unblockable).toBeNil()
			expect(t.glintLeadMax >= 0).toBe(true)
			expect(t.glintLeadSamples >= 1 and t.glintLeadSamples == math.floor(t.glintLeadSamples)).toBe(true)
			-- Every blow that glints, an enemy's or a boss's, glints whole, inside its parry window
			-- (no lead) and before its snap.
			local F = combat.hitStopFrameSeconds
			local blows = 0
			local function check(attack: any)
				if
					typeof(attack.strike) ~= "number"
					or not (attack.strike > 0)
					or not t.glintKinds[attack.telegraph]
				then
					return
				end
				blows += 1
				local ends, from, untilAt = TelegraphShapes.timing(attack.windUp, attack.strike)
				local lands = attack.windUp + attack.strike
				expect(untilAt - from).toBeCloseTo(t.glintFrames * F, 1e-9)
				expect(from >= lands - combat.parryWindow - 1e-9).toBe(true)
				expect(untilAt <= ends + 1e-9).toBe(true)
			end
			for _, def in Enemies.list() do
				for _, attack in def.attacks do
					check(attack)
				end
			end
			for _, boss in Bosses.list() do
				for _, phase in boss.phases or {} do
					for _, attack in phase.attacks or {} do
						check(attack)
					end
				end
			end
			expect(blows > 0).toBe(true)
		end
	)
end)

-- F16 (D-258): a body is shown struck before the server's word only this deep in the blow's shape.
describe("TelegraphShapes.deepInside", function()
	local function inside(reach: number, arc: number, point: { number }, facing: { number }?): boolean
		return TelegraphShapes.deepInside(reach, arc, 4, { 0, 3, 0 }, facing or { 0, 0, -1 }, point, 1, 8)
	end

	it("a cone holds a body inside its reach and its arc by the margins, at any height", function()
		expect(inside(6, 60, { 0, 0, -4.9 })).toBe(true)
		expect(inside(6, 60, { 0, 9, -3 })).toBe(true)
		expect(inside(6, 60, { 0, 0, -5.1 })).toBe(false)
		-- 21 degrees off the facing is inside 30 - 8; 23 is not.
		local function at(degrees: number): { number }
			local r = math.rad(degrees)
			return { 4 * math.sin(r), 0, -4 * math.cos(r) }
		end
		expect(inside(6, 60, at(21))).toBe(true)
		expect(inside(6, 60, at(-21))).toBe(true)
		expect(inside(6, 60, at(23))).toBe(false)
		expect(inside(6, 60, { 0, 0, 3 })).toBe(false)
		-- The facing turns the cone with it; its height is ignored.
		expect(inside(6, 60, { -4, 0, 0 }, { -1, 5, 0 })).toBe(true)
		expect(inside(6, 60, { 0, 0, -4 }, { -1, 0, 0 })).toBe(false)
	end)

	it("a full circle holds anything inside its reach, a line its length and width", function()
		expect(inside(6, 360, { 0, 0, 4.9 })).toBe(true)
		expect(inside(6, 360, { 5.2, 0, 0 })).toBe(false)
		-- A line 6 long and 4 wide: 1 in from each end and side.
		expect(inside(6, 0, { 0, 0, -3 })).toBe(true)
		expect(inside(6, 0, { 0.9, 0, -3 })).toBe(true)
		expect(inside(6, 0, { 1.1, 0, -3 })).toBe(false)
		expect(inside(6, 0, { 0, 0, -0.5 })).toBe(false)
		expect(inside(6, 0, { 0, 0, -5.5 })).toBe(false)
	end)

	it("no facing, no shape", function()
		expect(inside(6, 60, { 0, 0, -3 }, { 0, 1, 0 })).toBe(false)
	end)
end)
