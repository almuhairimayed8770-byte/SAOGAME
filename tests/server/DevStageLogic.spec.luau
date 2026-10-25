--!strict
--[[
	DevStageLogic (src/server/dev/DevStageLogic.luau): the pure placement and timing rules under the
	capture's staging (F12, DevStage.server.luau). Facings are degrees with 0 looking along -Z and
	+ turning left (CFrame.Angles(0, rad(f), 0)), the playground's convention.
]]

local Logic = Harness.load("src/server/dev/DevStageLogic")
local Dev = Harness.load("src/shared/data/dev")

local STAGE = Dev.capture.stage

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-9)
end

describe("DevStageLogic placement", function()
	it("looks along -Z at facing 0 and turns left with +", function()
		local x, z = Logic.look(0)
		expect(near(x, 0) and near(z, -1)).toBe(true)
		x, z = Logic.look(90)
		expect(near(x, -1) and near(z, 0)).toBe(true)
		-- The same look as CFrame.Angles.
		for _, facing in { -135, -30, 0, 45, 170 } do
			local look = CFrame.Angles(0, math.rad(facing), 0).LookVector
			x, z = Logic.look(facing)
			expect(near(x, look.X, 1e-6) and near(z, look.Z, 1e-6)).toBe(true)
		end
	end)

	it("puts a staged enemy its distance out at its side off the player's facing", function()
		local x, z = Logic.around(10, 20, 0, 0, 3.5)
		expect(near(x, 10) and near(z, 16.5)).toBe(true)
		-- 90 degrees left of a player looking along -Z is -X.
		x, z = Logic.around(0, 0, 0, 90, 4)
		expect(near(x, -4) and near(z, 0, 1e-9)).toBe(true)
		-- The distance is flat and exact whatever the facing and side.
		for _, facing in { -120, 0, 33, 180 } do
			for _, side in { -65, 0, 20, 65 } do
				x, z = Logic.around(5, -7, facing, side, 9)
				expect(near(math.sqrt((x - 5) ^ 2 + (z + 7) ^ 2), 9, 1e-9)).toBe(true)
			end
		end
	end)

	it("faces a staged enemy at the player", function()
		local facing = Logic.facingFrom(0, -10, 0, 0) :: number
		-- Looking from z = -10 toward the origin is along +Z: facing 180.
		expect(near(math.abs(facing), 180, 1e-9)).toBe(true)
		local ex, ez = Logic.around(3, 4, 25, 40, 12)
		local back = Logic.facingFrom(ex, ez, 3, 4) :: number
		local lx, lz = Logic.look(back)
		local dx, dz = (3 - ex) / 12, (4 - ez) / 12
		expect(near(lx, dx, 1e-9) and near(lz, dz, 1e-9)).toBe(true)
		expect(Logic.facingFrom(1, 1, 1, 1)).toBeNil()
	end)

	it("moves a field enemy inside the away distance out to it, along the line from the spot", function()
		local x, z = Logic.awaySpot(0, 0, 3, 4, 70)
		expect(near(x :: number, 42, 1e-9) and near(z :: number, 56, 1e-9)).toBe(true)
		-- Already far enough: left where it is.
		x, z = Logic.awaySpot(0, 0, 70, 1, 70)
		expect(x).toBeNil()
		expect(z).toBeNil()
		-- On top of the spot: pushed out along +X.
		x, z = Logic.awaySpot(5, 5, 5, 5, 70)
		expect(near(x :: number, 75) and near(z :: number, 5)).toBe(true)
	end)

	it("stands the player at the area, or on the ledge top its inset in from the +Z edge", function()
		local area = STAGE.area
		local x, y, z, facing = Logic.standSpot(false, area, STAGE.ledge)
		expect(x).toBe(area.position[1])
		expect(y).toBe(area.position[2])
		expect(z).toBe(area.position[3])
		expect(facing).toBe(area.facing)
		local ledge = STAGE.ledge
		x, y, z, facing = Logic.standSpot(true, area, ledge)
		expect(x).toBe(ledge.position[1])
		expect(y).toBe(ledge.position[2] + ledge.size[2] / 2)
		expect(z).toBe(ledge.position[3] + ledge.size[3] / 2 - ledge.standInset)
		expect(facing).toBe(ledge.facing)
	end)

	it("knows when a point stands on the ledge's top", function()
		local ledge = STAGE.ledge
		local x, _, z = Logic.standSpot(true, STAGE.area, ledge)
		expect(Logic.onLedge(ledge, x, z)).toBe(true)
		expect(Logic.onLedge(ledge, ledge.position[1] + ledge.size[1], z)).toBe(false)
		expect(Logic.onLedge(ledge, x, ledge.position[3] - ledge.size[3])).toBe(false)
	end)
end)

describe("DevStageLogic stand ring (D-244: the staging never moves the player)", function()
	it("rings the stand spot with the stand radius and tolerance; the open shot's over the ledge's top", function()
		local ledge = STAGE.ledge
		for _, open in { false, true } do
			local ring = Logic.ring(open, STAGE)
			local x, y, z, facing = Logic.standSpot(open, STAGE.area, ledge)
			expect(ring.x).toBe(x)
			expect(ring.y).toBe(y)
			expect(ring.z).toBe(z)
			expect(ring.facing).toBe(facing)
			expect(ring.radius).toBe(STAGE.standRadius)
			expect(ring.tolerance).toBe(STAGE.standHeightTolerance)
			if open then
				local over = ring.over :: { number }
				expect(over).toEqual({
					ledge.position[1] - ledge.size[1] / 2,
					ledge.position[1] + ledge.size[1] / 2,
					ledge.position[3] - ledge.size[3] / 2,
					ledge.position[3] + ledge.size[3] / 2,
				})
			else
				expect(ring.over).toBeNil()
			end
		end
	end)

	it("takes feet inside the radius (flat) and the tolerance (height), and over the box when it has one", function()
		local ring = { x = 10, y = 2, z = -5, facing = 0, radius = 3, tolerance = 1, over = nil }
		expect(Logic.inRing(ring, 10, 2, -5)).toBe(true)
		expect(Logic.inRing(ring, 12.9, 2.9, -5)).toBe(true)
		expect(Logic.inRing(ring, 10 + 3 * math.cos(1), 2, -5 + 3 * math.sin(1) - 1e-9)).toBe(true)
		expect(Logic.inRing(ring, 13.1, 2, -5)).toBe(false)
		expect(Logic.inRing(ring, 12.2, 2, -2.8)).toBe(false) -- 3.0+ studs on the diagonal
		expect(Logic.inRing(ring, 10, 3.2, -5)).toBe(false)
		expect(Logic.inRing(ring, 10, 0.8, -5)).toBe(false)
		local boxed = table.clone(ring) :: any
		boxed.over = { 8, 20, -20, -4 }
		expect(Logic.inRing(boxed, 10, 2, -4.5)).toBe(true)
		expect(Logic.inRing(boxed, 10, 2, -3.5)).toBe(false) -- inside the radius, off the box
	end)
end)

describe("DevStageLogic ramp", function()
	it("stands the ramp against the ledge's +Z face, centred across it, on its floor, turned a half turn", function()
		local ledge = STAGE.ledge
		local x, y, z, yaw = Logic.rampFrame(ledge)
		local size = ledge.ramp.size
		expect(x).toBe(ledge.position[1])
		expect(y).toBe(ledge.position[2] - ledge.size[2] / 2 + size[2] / 2)
		expect(z).toBe(ledge.position[3] + ledge.size[3] / 2 + size[3] / 2)
		expect(yaw).toBe(180)
		-- A WedgePart's tall face is its back (+Z): turned, it looks at the ledge.
		local frame = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
		local back = frame:PointToWorldSpace(Vector3.new(0, 0, size[3] / 2))
		expect(back.Z).toBeCloseTo(ledge.position[3] + ledge.size[3] / 2, 1e-6)
	end)

	it("knows when a point stands over the ramp", function()
		local ledge = STAGE.ledge
		local edge = ledge.position[3] + ledge.size[3] / 2
		local size = ledge.ramp.size
		expect(Logic.onRamp(ledge, ledge.position[1], edge + size[3] / 2)).toBe(true)
		expect(Logic.onRamp(ledge, ledge.position[1] + size[1] / 2 - 0.01, edge + 0.01)).toBe(true)
		expect(Logic.onRamp(ledge, ledge.position[1] + size[1] / 2 + 0.01, edge + 1)).toBe(false)
		expect(Logic.onRamp(ledge, ledge.position[1], edge - 1)).toBe(false) -- the ledge's top
		expect(Logic.onRamp(ledge, ledge.position[1], edge + size[3] + 0.01)).toBe(false)
	end)
end)

-- The flat footprint of the ledge and its ramp (their bounding box), as crosses takes it.
local function footprint(grow: number): { number }
	local ledge = STAGE.ledge
	local half = math.max(ledge.size[1], ledge.ramp.size[1]) / 2 + grow
	return {
		ledge.position[1] - half,
		ledge.position[1] + half,
		ledge.position[3] - ledge.size[3] / 2 - grow,
		ledge.position[3] + ledge.size[3] / 2 + ledge.ramp.size[3] + grow,
	}
end

-- Every leg of a route from (x, z), as segments { ax, az, bx, bz }.
local function legs(path: { { number } }, x: number, z: number): { { number } }
	local list = {}
	local ax, az = x, z
	for _, point in path do
		table.insert(list, { ax, az, point[1], point[2] })
		ax, az = point[1], point[2]
	end
	return list
end

describe("DevStageLogic route", function()
	it("crosses a box only through its inside", function()
		local box = { 0, 10, 0, 10 }
		expect(Logic.crosses(box, -5, 5, 15, 5)).toBe(true)
		expect(Logic.crosses(box, 5, 5, 6, 6)).toBe(true) -- wholly inside
		expect(Logic.crosses(box, -5, -5, -1, 20)).toBe(false)
		expect(Logic.crosses(box, -5, 10, 15, 10)).toBe(false) -- along an edge
		expect(Logic.crosses(box, -5, 5, 0, 5)).toBe(false) -- ends on an edge
		expect(Logic.crosses(box, -5, 5, -5, 5)).toBe(false) -- a point outside
		expect(Logic.crosses(box, -1, 9, 1, 11)).toBe(false) -- clips the corner's outside
	end)

	it("ends every route with the approach along the facing, then the spot", function()
		for _, open in { false, true } do
			local x, _, z, facing = Logic.standSpot(open, STAGE.area, STAGE.ledge)
			local lx, lz = Logic.look(facing)
			local path = Logic.route(open, STAGE, true, 60, -60)
			local approach, spot = path[#path - 1], path[#path]
			expect(spot).toEqual({ x, z })
			expect(near(approach[1], x - lx * STAGE.approachStuds, 1e-9)).toBe(true)
			expect(near(approach[2], z - lz * STAGE.approachStuds, 1e-9)).toBe(true)
		end
	end)

	it("walks straight to an area shot while the ledge is not built", function()
		local path = Logic.route(false, STAGE, false, 0, 80)
		expect(#path).toBe(2)
	end)

	it("goes round the built ledge and ramp to an area shot, never through them", function()
		local solid = footprint(0)
		for _, from in { { 0, 90 }, { 10, 60 }, { -30, 50 }, { 9.5, 40 } } do
			local path = Logic.route(false, STAGE, true, from[1], from[2])
			for _, leg in legs(path, from[1], from[2]) do
				expect(Logic.crosses(solid, leg[1], leg[2], leg[3], leg[4])).toBe(false)
			end
		end
		-- In front of the ledge, the area is straight ahead: no detour.
		expect(#Logic.route(false, STAGE, true, 0, 20)).toBe(2)
		-- On the ledge or its ramp: straight off the front edge.
		expect(#Logic.route(false, STAGE, true, 0, 40)).toBe(2)
	end)

	it(
		"takes the open shot from the field round the ledge and up the ramp's centre line, never through them",
		function()
			local ledge = STAGE.ledge
			local solid = footprint(0)
			local keep = footprint(STAGE.routeMarginStuds)
			local area = STAGE.area
			for _, from in
				{ { area.position[1], area.position[3] }, { 0, 0 }, { 40, 40 }, { -9.5, 45 }, { 0, 90 }, { 20, 120 } }
			do
				local path = Logic.route(true, STAGE, true, from[1], from[2])
				local n = #path
				-- The foot (the ramp's centre line, the margin past its low end), the approach, the spot.
				expect(path[n - 2]).toEqual({ ledge.position[1], keep[4] })
				expect(Logic.onRamp(ledge, path[n - 1][1], path[n - 1][2])).toBe(true)
				-- Every leg before the foot keeps off the ledge and the ramp.
				local all = legs(path, from[1], from[2])
				for index = 1, #all - 2 do
					local leg = all[index]
					expect(Logic.crosses(solid, leg[1], leg[2], leg[3], leg[4])).toBe(false)
				end
				-- The climb runs up the centre line along the spot's facing.
				for index = #all - 1, #all do
					expect(all[index][1]).toBe(ledge.position[1])
					expect(all[index][3]).toBe(ledge.position[1])
					expect(all[index][4] < all[index][2]).toBe(true)
				end
			end
		end
	)

	it("takes the open shot from the ledge's top or the ramp across to the centre line, then the climb", function()
		local ledge = STAGE.ledge
		for _, from in { { 6, 36 }, { -3, 60 } } do
			local path = Logic.route(true, STAGE, true, from[1], from[2])
			expect(#path).toBe(3)
			expect(path[1]).toEqual({ ledge.position[1], from[2] })
		end
	end)
end)

describe("DevStageLogic timing", function()
	it("holds an enemy only outside its wind-up and its strike (a held wind-up draws a phantom rush)", function()
		for _, phase in { "Idle", "Alert", "Chase", "Recover", "Return", "Interrupted" } do
			expect(Logic.canHold(phase)).toBe(true)
		end
		expect(Logic.canHold("WindUp")).toBe(false)
		expect(Logic.canHold("Strike")).toBe(false)
		-- No brain (gone, or dead): nothing to wait for.
		expect(Logic.canHold(nil)).toBe(true)
		expect(Logic.canHold("Dead")).toBe(true)
	end)

	it("lets one player's requests through no faster than the rate", function()
		expect(Logic.allowed(nil, 10, 2)).toBe(true)
		expect(Logic.allowed(10, 10.4, 2)).toBe(false)
		expect(Logic.allowed(10, 10.5, 2)).toBe(true)
	end)

	it("finds a shot by id", function()
		local shots = Dev.capture.shots
		expect(Logic.shotIndex(shots, shots[3].id)).toBe(3)
		expect(Logic.shotIndex(shots, "no-such-shot")).toBeNil()
		expect(Logic.shotIndex(shots, 7 :: any)).toBeNil()
	end)
end)
