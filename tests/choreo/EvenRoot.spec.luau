--!strict
-- EvenRoot's height (D-682, AW 568(c) on 577a59a): the server's root let go at a walk's start
-- settles into its contact (the PC's kobold 3.4000 held, 3.3984 from the release on) and the body
-- drawn on it stood its feet that much deeper. The drawn root holds the height it stood at while
-- the replicated root sinks within enemy.gait.evenRoot.sinkStuds of it, follows past that, is
-- never under the replicated root and rises with it; tuning with no sinkStuds keeps the root's own.

local EvenRoot = Harness.load("src/client/choreo/EvenRoot")
local ChoreoData = Harness.load("src/shared/data/choreo")

local FRAME = 1 / 60
local SINK = ChoreoData.enemy.gait.evenRoot.sinkStuds
local STAND = 3.4
local EPS = 1e-5 -- a CFrame's float32 at that height

local function at(y: number, z: number?): CFrame
	return CFrame.new(2, y, z or -5) * CFrame.Angles(0, math.rad(30), 0)
end

-- Stands the root at STAND for 30 rows, then steps it through `heights` (one a row, walking
-- on along z by `pace` studs a row); returns the drawn heights.
local function drawn(heights: { number }, pace: number?, own: any?): { number }
	local even = EvenRoot.new()
	for _ = 1, 30 do
		EvenRoot.step(even, at(STAND), FRAME, nil, own)
	end
	local out = {}
	for index, y in heights do
		local frame = EvenRoot.step(even, at(y, -5 - index * (pace or 0)), FRAME, nil, own)
		table.insert(out, frame.Position.Y)
	end
	return out
end

describe("EvenRoot: a drawn root holds its stand's height over a settling root (AW 568(c); D-682)", function()
	it("has a sink to hold over, more than the PC's settle", function()
		expect(typeof(SINK)).toBe("number")
		expect(SINK > 0.0016).toBe(true)
	end)

	it("holds the stand's height while the root settles 0.0016 and sets off", function()
		local heights = {}
		for index = 1, 60 do
			heights[index] = STAND - 0.0016
		end
		for _, y in drawn(heights, 0.1) do
			expect(math.abs(y - STAND)).toBeLessThanOrEqual(EPS)
		end
	end)

	it("follows a root sinking past sinkStuds, at most sinkStuds over it, and rises with it", function()
		local heights = { STAND - SINK / 2, STAND - SINK * 2, STAND - SINK * 3, STAND - SINK * 2.5, STAND + 0.01 }
		local out = drawn(heights, 0.1)
		expect(math.abs(out[1] - STAND)).toBeLessThanOrEqual(EPS)
		expect(math.abs(out[2] - (STAND - SINK))).toBeLessThanOrEqual(EPS)
		expect(math.abs(out[3] - (STAND - SINK * 2))).toBeLessThanOrEqual(EPS)
		-- The root rising within sinkStuds of the drawn height leaves it; past it, the drawn rises.
		expect(math.abs(out[4] - (STAND - SINK * 2))).toBeLessThanOrEqual(EPS)
		expect(math.abs(out[5] - (STAND + 0.01))).toBeLessThanOrEqual(EPS)
		for index, y in out do
			expect(y >= heights[index] - EPS).toBe(true)
			expect(y <= heights[index] + SINK + EPS).toBe(true)
		end
	end)

	it("starts afresh at the root's height on a placement", function()
		local even = EvenRoot.new()
		for _ = 1, 30 do
			EvenRoot.step(even, at(STAND), FRAME)
		end
		EvenRoot.step(even, at(STAND - 0.002), FRAME)
		local far = ChoreoData.enemy.rush.teleportStuds + 1
		local placed = EvenRoot.step(even, at(STAND - 0.002, -5 - far), FRAME)
		expect(math.abs(placed.Position.Y - (STAND - 0.002))).toBeLessThanOrEqual(EPS)
	end)

	it("keeps the root's own height on tuning with no sinkStuds (the local fighter's)", function()
		local own = table.clone(ChoreoData.enemy.gait.evenRoot)
		own.sinkStuds = nil
		for _, y in drawn({ STAND - 0.0016, STAND - 0.0016, STAND - 0.003 }, 0.1, own) do
			expect(y < STAND - 0.0015).toBe(true)
		end
		local out = drawn({ STAND - 0.0016, STAND - 0.003 }, 0.1, ChoreoData.locomotion.stride.evenRoot)
		expect(math.abs(out[1] - (STAND - 0.0016))).toBeLessThanOrEqual(EPS)
		expect(math.abs(out[2] - (STAND - 0.003))).toBeLessThanOrEqual(EPS)
	end)
end)
