--!strict
--[[
	Verlet: a point-chain solver for procedural secondary motion (coats, capes, scarves, hair,
	tails; section 10). Pure math on plain {x, y, z} tables so it runs in Lune tests; the client
	FX module maps the points onto part chains each frame.
]]

export type Vec = { number }

export type Chain = {
	points: { Vec },
	previous: { Vec },
	segmentLength: number,
	gravity: Vec,
	drag: number, -- 0..1 velocity kept per step
	wind: Vec,
	collisionCenter: Vec?,
	collisionRadius: number,
	iterations: number,
}

local Verlet = {}

local function add(a: Vec, b: Vec): Vec
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

local function sub(a: Vec, b: Vec): Vec
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function scale(a: Vec, s: number): Vec
	return { a[1] * s, a[2] * s, a[3] * s }
end

local function length(a: Vec): number
	return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
end

--- Creates a chain of `count` points hanging from `anchor` along `direction`.
function Verlet.new(anchor: Vec, direction: Vec, count: number, segmentLength: number): Chain
	local points = {}
	local previous = {}
	for index = 0, count - 1 do
		local point = add(anchor, scale(direction, index * segmentLength))
		table.insert(points, point)
		table.insert(previous, table.clone(point))
	end
	return {
		points = points,
		previous = previous,
		segmentLength = segmentLength,
		gravity = { 0, -40, 0 },
		drag = 0.96,
		wind = { 0, 0, 0 },
		collisionCenter = nil,
		collisionRadius = 0,
		iterations = 3,
	}
end

--- Advances the chain; the first point is pinned to `anchor`.
function Verlet.step(chain: Chain, anchor: Vec, dt: number)
	local points = chain.points
	local previous = chain.previous
	local acceleration = add(chain.gravity, chain.wind)
	local dt2 = dt * dt
	for index = 2, #points do
		local point = points[index]
		local velocity = scale(sub(point, previous[index]), chain.drag)
		previous[index] = table.clone(point)
		points[index] = add(add(point, velocity), scale(acceleration, dt2))
	end
	points[1] = table.clone(anchor)
	previous[1] = table.clone(anchor)
	for _ = 1, chain.iterations do
		for index = 2, #points do
			local a = points[index - 1]
			local b = points[index]
			local delta = sub(b, a)
			local distance = length(delta)
			if distance < 1e-6 then
				continue
			end
			local correction = scale(delta, (distance - chain.segmentLength) / distance)
			if index == 2 then
				points[index] = sub(b, correction)
			else
				points[index - 1] = add(a, scale(correction, 0.5))
				points[index] = sub(b, scale(correction, 0.5))
			end
		end
		local center = chain.collisionCenter
		if center and chain.collisionRadius > 0 then
			for index = 2, #points do
				local offset = sub(points[index], center)
				local distance = length(offset)
				if distance < chain.collisionRadius and distance > 1e-6 then
					points[index] = add(center, scale(offset, chain.collisionRadius / distance))
				end
			end
		end
	end
end

Verlet.length = length

return Verlet
