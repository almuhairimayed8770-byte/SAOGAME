--!strict
--[[
	Damped least squares over joint Euler angles (degrees) for the gait generator: a numeric
	Jacobian through the caller's forward kinematics, Levenberg-Marquardt steps solved by Gaussian
	elimination, every parameter clamped to its range. Deterministic: the same inputs give the same
	angles to the last bit, which is what lets tools/gaitgen.luau --check compare bytes.
]]

--- A joint offset as Pose.solve reads it (both arrays always present).
export type Offset = { pos: { number }, rot: { number } }
export type Offsets = { [string]: Offset }

--- Part name -> world frame, as Pose.solve returns it.
export type Solved = { [string]: CFrame }

--- One solved angle: `rot[axis]` of `joint`, starting at `start`, pulled toward `seed` with weight
--- `reg`, kept inside [`min`, `max`].
export type Param = {
	joint: string,
	axis: number,
	start: number,
	seed: number,
	reg: number,
	min: number,
	max: number,
}

export type Options = {
	iterations: number,
	-- Forward kinematics: every part's frame under the offsets.
	solve: (offsets: Offsets) -> Solved,
	-- The weighted errors to drive to zero (the regularisation terms are appended to them).
	residual: (solved: Solved) -> { number },
}

local Ik = {}

local STEP = 1e-3 -- the numeric Jacobian's finite difference (degrees)
local MAX_STEP = 20 -- the largest change of one angle per iteration (degrees)
local LAMBDA_START = 1e-2
local LAMBDA_SHRINK = 0.3 -- after a step that lowers the cost
local LAMBDA_FLOOR = 1e-7
local LAMBDA_GROW = 10 -- after a step that does not
local LAMBDA_CEILING = 1e8 -- give up past this damping
local TOLERANCE = 1e-12 -- stop once the cost is below this

local function copy(base: Offsets): Offsets
	local out: Offsets = {}
	for name, offset in base do
		out[name] = {
			pos = { offset.pos[1], offset.pos[2], offset.pos[3] },
			rot = { offset.rot[1], offset.rot[2], offset.rot[3] },
		}
	end
	return out
end

--- The offsets with each parameter's angle set from `x` (a joint missing from `base` starts at rest).
function Ik.apply(base: Offsets, params: { Param }, x: { number }): Offsets
	local out = copy(base)
	for index, param in params do
		local entry = out[param.joint]
		if entry == nil then
			entry = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }
			out[param.joint] = entry
		end
		entry.rot[param.axis] = x[index]
	end
	return out
end

local function squared(values: { number }): number
	local total = 0
	for _, value in values do
		total += value * value
	end
	return total
end

--- Solves the parameters; returns the angles and the final cost (residual plus regularisation).
function Ik.solve(base: Offsets, params: { Param }, options: Options): ({ number }, number)
	local x: { number } = {}
	for index, param in params do
		x[index] = param.start
	end
	local function evaluate(xs: { number }): { number }
		local residual = options.residual(options.solve(Ik.apply(base, params, xs)))
		for index, param in params do
			table.insert(residual, param.reg * (xs[index] - param.seed))
		end
		return residual
	end

	local lambda = LAMBDA_START
	local r = evaluate(x)
	local cost = squared(r)
	local n = #x
	for _ = 1, options.iterations do
		-- numeric Jacobian
		local jacobian: { { number } } = {}
		for j = 1, n do
			local xp = table.clone(x)
			xp[j] += STEP
			local rp = evaluate(xp)
			for i = 1, #r do
				jacobian[i] = jacobian[i] or {}
				jacobian[i][j] = (rp[i] - r[i]) / STEP
			end
		end
		-- normal equations (J^T J + lambda (I + diag J^T J)) dx = -J^T r
		local a: { { number } } = {}
		local b: { number } = {}
		for row = 1, n do
			a[row] = {}
			for column = 1, n do
				local sum = 0
				for i = 1, #r do
					sum += jacobian[i][row] * jacobian[i][column]
				end
				a[row][column] = sum
			end
			a[row][row] += lambda * (1 + a[row][row])
			local sum = 0
			for i = 1, #r do
				sum += jacobian[i][row] * r[i]
			end
			b[row] = -sum
		end
		-- Gaussian elimination with partial pivoting
		for column = 1, n do
			local pivot = column
			for row = column + 1, n do
				if math.abs(a[row][column]) > math.abs(a[pivot][column]) then
					pivot = row
				end
			end
			a[column], a[pivot] = a[pivot], a[column]
			b[column], b[pivot] = b[pivot], b[column]
			for row = column + 1, n do
				local factor = a[row][column] / a[column][column]
				for c = column, n do
					a[row][c] -= factor * a[column][c]
				end
				b[row] -= factor * b[column]
			end
		end
		local dx: { number } = {}
		for row = n, 1, -1 do
			local sum = b[row]
			for c = row + 1, n do
				sum -= a[row][c] * dx[c]
			end
			dx[row] = sum / a[row][row]
		end
		local xn: { number } = {}
		for j = 1, n do
			local step = math.clamp(dx[j], -MAX_STEP, MAX_STEP)
			xn[j] = x[j] + step
			xn[j] = math.max(params[j].min, xn[j])
			xn[j] = math.min(params[j].max, xn[j])
		end
		local rn = evaluate(xn)
		local cn = squared(rn)
		if cn < cost then
			x, r, cost = xn, rn, cn
			lambda = math.max(lambda * LAMBDA_SHRINK, LAMBDA_FLOOR)
			if cost < TOLERANCE then
				break
			end
		else
			lambda *= LAMBDA_GROW
			if lambda > LAMBDA_CEILING then
				break
			end
		end
	end
	return x, cost
end

return Ik
