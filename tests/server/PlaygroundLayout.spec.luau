--!strict
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local Playground = Harness.load("src/shared/data/playground")
local World = Harness.load("src/shared/data/world")
local Fx = Harness.load("src/shared/data/fx")

local rim = Playground.rim
local TAU = 2 * math.pi

describe("PlaygroundLayout posts and rails", function()
	local posts = PlaygroundLayout.posts(Playground.fieldRadius, rim.postSpacing, rim.postSize)

	it("fits one post every postSpacing studs around the rim", function()
		local expected = math.floor(TAU * Playground.fieldRadius / rim.postSpacing)
		expect(#posts).toBe(expected)
		expect(#posts).toBe(125)
		expect(PlaygroundLayout.ringCount(Playground.fieldRadius, rim.postSpacing)).toBe(expected)
	end)

	it("every post stands half a post inside the field edge at half its height", function()
		local radius = Playground.fieldRadius - rim.postSize[1] / 2
		for _, post in posts do
			expect(PlaygroundLayout.distance(0, 0, post.x, post.z)).toBeCloseTo(radius, 1e-6)
			expect(post.y).toBeCloseTo(rim.postSize[2] / 2, 1e-9)
		end
	end)

	it("neighbouring posts are about postSpacing apart and the ring closes", function()
		for index, post in posts do
			local next = posts[index % #posts + 1]
			local gap = PlaygroundLayout.distance(post.x, post.z, next.x, next.z)
			expect(gap).toBeGreaterThan(rim.postSpacing * 0.9)
			expect(gap).toBeLessThan(rim.postSpacing * 1.1)
		end
	end)

	it("rail heights put the top rail flush with the posts and the mid rail at half height", function()
		local heights = PlaygroundLayout.railHeights(rim.railingHeight, rim.railThickness, World.railing.railCount)
		expect(#heights).toBe(World.railing.railCount)
		expect(heights[1]).toBeCloseTo(rim.railingHeight - rim.railThickness / 2, 1e-9)
		expect(heights[2]).toBeCloseTo(heights[1] / 2, 1e-9)
		expect(PlaygroundLayout.railHeights(4, 1, 1)).toEqual({ 3.5 })
	end)

	it("one rail per height between each pair of posts, along the chord, overlapping into the posts", function()
		local heights = PlaygroundLayout.railHeights(rim.railingHeight, rim.railThickness, World.railing.railCount)
		local overlap = rim.postSize[1]
		local rails = PlaygroundLayout.rails(posts, heights, overlap)
		expect(#rails).toBe(#posts * #heights)
		local first = rails[1]
		local a = posts[1]
		local b = posts[2]
		expect(first.x).toBeCloseTo((a.x + b.x) / 2, 1e-9)
		expect(first.z).toBeCloseTo((a.z + b.z) / 2, 1e-9)
		expect(first.y).toBeCloseTo(heights[1], 1e-9)
		local chord = PlaygroundLayout.distance(a.x, a.z, b.x, b.z)
		expect(first.length).toBeCloseTo(chord + overlap, 1e-9)
		expect(math.sqrt(first.dirX * first.dirX + first.dirZ * first.dirZ)).toBeCloseTo(1, 1e-9)
		-- The direction points from post 1 to post 2.
		expect(first.dirX * (b.x - a.x) + first.dirZ * (b.z - a.z)).toBeGreaterThan(0)
		-- The last rail closes the loop back to the first post.
		local last = rails[#rails]
		local tail = posts[#posts]
		expect(last.x).toBeCloseTo((tail.x + a.x) / 2, 1e-9)
	end)

	it("a single post makes no rails", function()
		expect(PlaygroundLayout.rails({ { x = 1, y = 0, z = 0, angle = 0 } }, { 1 }, 0)).toEqual({})
	end)
end)

describe("PlaygroundLayout pillars, clouds and the kill volume", function()
	it("places the pillars evenly at pillarDistance, from below the clouds to under the ceiling", function()
		local underside = Playground.ceilingHeight - 3
		local centerY = PlaygroundLayout.pillarCenterY(underside, World.pillars.ceilingGap, rim.pillarHeight)
		local pillars = PlaygroundLayout.pillars(rim.pillarCount, rim.pillarDistance, centerY)
		expect(#pillars).toBe(rim.pillarCount)
		for index, pillar in pillars do
			expect(PlaygroundLayout.distance(0, 0, pillar.x, pillar.z)).toBeCloseTo(rim.pillarDistance, 1e-6)
			expect(pillar.angle).toBeCloseTo((index - 1) * 360 / rim.pillarCount, 1e-9)
			expect(pillar.y).toBe(centerY)
		end
		local top = centerY + rim.pillarHeight / 2
		local bottom = centerY - rim.pillarHeight / 2
		expect(top).toBeCloseTo(underside - World.pillars.ceilingGap, 1e-9)
		expect(bottom).toBeLessThan(-rim.cloudRingDrop)
	end)

	it("the cloud ring sits cloudRingDrop below the field with tangents to drift along", function()
		local clouds = PlaygroundLayout.clouds(rim.cloudCount, rim.cloudRingRadius, rim.cloudRingDrop)
		expect(#clouds).toBe(rim.cloudCount)
		for _, cloud in clouds do
			expect(cloud.y).toBe(-rim.cloudRingDrop)
			expect(PlaygroundLayout.distance(0, 0, cloud.x, cloud.z)).toBeCloseTo(rim.cloudRingRadius, 1e-6)
			-- The tangent is perpendicular to the radius.
			expect(cloud.dirX * cloud.x + cloud.dirZ * cloud.z).toBeCloseTo(0, 1e-6)
			expect(math.sqrt(cloud.dirX * cloud.dirX + cloud.dirZ * cloud.dirZ)).toBeCloseTo(1, 1e-9)
		end
	end)

	it("jitter scatters clouds radially and vertically within bounds, deterministically per seed", function()
		local jitter = { radial = World.clouds.radialJitter, height = World.clouds.heightJitter }
		local first =
			PlaygroundLayout.clouds(rim.cloudCount, rim.cloudRingRadius, rim.cloudRingDrop, jitter, Random.new(7))
		local again =
			PlaygroundLayout.clouds(rim.cloudCount, rim.cloudRingRadius, rim.cloudRingDrop, jitter, Random.new(7))
		local moved = false
		for index, cloud in first do
			local distance = PlaygroundLayout.distance(0, 0, cloud.x, cloud.z)
			expect(distance).toBeGreaterThanOrEqual(rim.cloudRingRadius - jitter.radial - 1e-6)
			expect(distance).toBeLessThanOrEqual(rim.cloudRingRadius + jitter.radial + 1e-6)
			expect(math.abs(cloud.y + rim.cloudRingDrop)).toBeLessThanOrEqual(jitter.height + 1e-9)
			expect(cloud.x).toBe(again[index].x)
			if math.abs(cloud.y + rim.cloudRingDrop) > 1e-6 then
				moved = true
			end
		end
		expect(moved).toBe(true)
	end)

	it("the kill volume is a slab whose top face is the kill plane", function()
		local box = PlaygroundLayout.killVolume(Playground.killVolume)
		expect(box.x).toBe(0)
		expect(box.z).toBe(0)
		expect(box.y + box.size[2] / 2).toBeCloseTo(Playground.killVolume.y, 1e-9)
		expect(box.size[1]).toBe(Playground.killVolume.halfExtent * 2)
		expect(box.size[3]).toBe(Playground.killVolume.halfExtent * 2)
		expect(box.size[1]).toBeGreaterThan(Playground.fieldRadius * 2)
	end)
end)

describe("PlaygroundLayout budget and spawns", function()
	it("the whole rim, pillars and clouds stay under the Playground part budget", function()
		local estimate = PlaygroundLayout.partEstimate(
			Playground.fieldRadius,
			rim.postSpacing,
			World.railing.railCount,
			rim.pillarCount,
			Fx.quality.High.cloudBillboards
		)
		expect(estimate).toBe(
			125 + 125 * World.railing.railCount + rim.pillarCount + Fx.quality.High.cloudBillboards + 1
		)
		expect(estimate).toBeLessThan(World.playground.partBudget)
	end)

	it("scatter stays inside its disc and covers it", function()
		local random = Random.new(3)
		local farthest = 0
		for _ = 1, 200 do
			local x, z = PlaygroundLayout.scatter(60, -40, Playground.spawnScatterRadius, random)
			local distance = PlaygroundLayout.distance(60, -40, x, z)
			expect(distance).toBeLessThanOrEqual(Playground.spawnScatterRadius + 1e-9)
			farthest = math.max(farthest, distance)
		end
		expect(farthest).toBeGreaterThan(Playground.spawnScatterRadius * 0.8)
	end)

	it("facing jitter stays inside its range and root height stands a rig on the ground", function()
		local random = Random.new(11)
		for _ = 1, 50 do
			local facing = PlaygroundLayout.jitterFacing(90, Playground.spawnFacingJitterDegrees, random)
			expect(math.abs(facing - 90)).toBeLessThanOrEqual(Playground.spawnFacingJitterDegrees)
		end
		expect(PlaygroundLayout.rootHeight(1.6, 2.4, 0)).toBeCloseTo(2.8, 1e-9)
		expect(PlaygroundLayout.rootHeight(1.6, 2.4, 0.05)).toBeCloseTo(2.85, 1e-9)
	end)

	it("ring and ringCount reject nonsense", function()
		expect(PlaygroundLayout.ring(0, 10, 0)).toEqual({})
		expect(PlaygroundLayout.ringCount(1, 1000)).toBe(1)
		expect(function()
			PlaygroundLayout.ringCount(10, 0)
		end).toThrow("positive")
	end)
end)
