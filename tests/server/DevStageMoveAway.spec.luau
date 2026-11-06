--!strict
--[[
	The staging's move-out of near field enemies keeps them off the ledge and its ramp (critic item
	6, shot 5 take 3 on the owner's PC; round E note: moveAway can push a held field enemy into the
	built ramp). DevStage moves every held field enemy nearer the stand spot than
	capture.stage.awayStuds straight out along the line from the spot (DevStageLogic.awaySpot), and
	pivots it there at the height it stood. Along +Z from the stage area's spot that line ends on
	the open shot's ramp (0, 60): the ramp's top stands 2 studs over the field there, so the
	enemy's body is put inside the wedge. The move-out takes the stage's ledge and turns off the
	straight line until the spot clears the ledge's and the ramp's footprint by routeMarginStuds.
]]

local Logic = Harness.load("src/server/dev/DevStageLogic")
local Dev = Harness.load("src/shared/data/dev")

local STAGE = Dev.capture.stage
local LEDGE = STAGE.ledge
local SPOT = STAGE.area.position

-- Whether the flat point stands within `grow` of the ledge's or the ramp's footprint.
local function nearLedge(x: number, z: number, grow: number): boolean
	local half = math.max(LEDGE.size[1], LEDGE.ramp.size[1]) / 2
	local front = LEDGE.position[3] - LEDGE.size[3] / 2
	local back = LEDGE.position[3] + LEDGE.size[3] / 2 + LEDGE.ramp.size[3]
	return math.abs(x - LEDGE.position[1]) <= half + grow and z >= front - grow and z <= back + grow
end

describe("DevStageLogic.awaySpot keeps a moved field enemy off the ledge and its ramp", function()
	it("moves an enemy out to awayStuds from every bearing, never onto the ramp or the ledge", function()
		local bad = {}
		for bearing = 0, 355, 5 do
			for _, distance in { 5, 30, 60 } do
				local lx, lz = Logic.look(bearing)
				local fromX, fromZ = SPOT[1] + lx * distance, SPOT[3] + lz * distance
				local x, z = (Logic.awaySpot :: any)(SPOT[1], SPOT[3], fromX, fromZ, STAGE.awayStuds, STAGE)
				expect(x ~= nil and z ~= nil).toBe(true)
				local out = math.sqrt((x - SPOT[1]) ^ 2 + (z - SPOT[3]) ^ 2)
				expect(out).toBeGreaterThan(STAGE.awayStuds - 1e-6)
				if nearLedge(x, z, STAGE.routeMarginStuds) then
					table.insert(bad, ("%g@%d -> (%.1f, %.1f)"):format(distance, bearing, x, z))
				end
			end
		end
		print(
			("[moveAway] %d of %d move-outs land within %g studs of the ledge or ramp: %s"):format(
				#bad,
				72 * 3,
				STAGE.routeMarginStuds,
				table.concat(bad, ", ")
			)
		)
		expect(#bad).toBe(0)
	end)

	it("still moves an enemy straight out where that line is clear", function()
		-- Along -Z (bearing 0) and along +X (bearing 270): no ledge on the way.
		for _, bearing in { 0, 270 } do
			local lx, lz = Logic.look(bearing)
			local x, z = (Logic.awaySpot :: any)(
				SPOT[1],
				SPOT[3],
				SPOT[1] + lx * 10,
				SPOT[3] + lz * 10,
				STAGE.awayStuds,
				STAGE
			)
			expect(x).toBeCloseTo(SPOT[1] + lx * STAGE.awayStuds, 1e-6)
			expect(z).toBeCloseTo(SPOT[3] + lz * STAGE.awayStuds, 1e-6)
		end
	end)
end)
