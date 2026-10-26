--!strict
--[[
	The gait generator's core; tools/gaitgen.luau is its command line and
	tests/tools/gaitgen.spec.luau runs its check.

	Every loop keeps a planted foot where it lands while the body passes over it. For each key time
	the root and upper body come from the gait (Gaits.luau), and each leg is solved by damped least
	squares (Ik.luau) on the hit matrix's body (Rig.luau) so the foot sits on its planned frame: on
	the field moving back at the gait's ground speed while planted, rolling on and off the sole
	about its strike and lift pivots, and along a Hermite path through the swing points (or set by
	hand, swingJoints) in the air. Each stance is solved twice round so its first key is seeded from
	its own end. Both sets' legs are twins (D-134): a drawn gait shares its sheathed gait's plans,
	key times, Footsteps and pelvis height.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Emit = require("./Emit")
local Gaits = require("./Gaits")
local Ik = require("./Ik")
local Keys = require("./Keys")
local Rig = require("./Rig")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

type Gait = Keys.Gait
type Plan = Keys.Plan

--- One generated clip.
export type Result = {
	name: string,
	path: string, -- the clip file, relative to the repo root
	source: string, -- the clip file's text (already StyLua-formatted)
	worstError: number, -- the worst planted-foot miss over the stance keys (studs)
	misses: { string }, -- one line per stance key whose foot misses by more than MISS
}

--- A committed clip that differs from what the generator makes.
export type Drift = {
	name: string,
	path: string,
	missing: boolean, -- no committed file
	line: number, -- the first line that differs
	lines: number, -- how many lines differ (line by line)
	committed: string?, -- the committed text of `line` (nil past its end)
	generated: string?, -- the generated text of `line`
}

local GaitGen = {}

local CLIP_DIRECTORY = "src/shared/clips/player/OneHandedSword"

--- Every clip the generator owns, in the order it writes them.
GaitGen.NAMES = {
	"WalkForward",
	"WalkForwardDrawn",
	"WalkBack",
	"WalkBackDrawn",
	"WalkLeft",
	"WalkLeftDrawn",
	"WalkRight",
	"WalkRightDrawn",
	"Run",
	"RunDrawn",
	"Sprint",
	"SprintDrawn",
}

--- Committed clips the generator does not reproduce, and why. --check skips them and a plain run
--- leaves them alone; naming one on the command line rewrites it and loses its hand edits. None
--- now: Run's and Sprint's upper bodies, re-keyed by hand for the back mount (D-050, D-055), are
--- pinned in sources/Run.luau and sources/Sprint.luau and sampled like the drawn set's.
GaitGen.DRIFTED = {} :: { [string]: string }

local MISS = 0.01 -- a stance key whose foot is further than this from its plan is reported (studs)
local EASING = "SineInOut"
local SEED_KNEE = -20 -- the first IK seed bends the knee a little (degrees)
local REG = 0.002 -- regularisation toward the seed (hip Y and ankle Z three times this, toward 0)
local ITERATIONS = 300
local POSITION_WEIGHT = 10 -- residual weight per stud of foot position error
local AXIS_WEIGHT = 3 -- residual weight per unit of foot axis error
local EPS = 1e-3 -- the step of the swing path's end tangents (s)
local SAME = 1e-6 -- two key times this close are the same key (s)
local EDGE = 1e-9 -- a time this close to a phase boundary is on it (s)

--- The repo-relative path of a gait's clip file.
function GaitGen.path(name: string): string
	return ("%s/%s.luau"):format(CLIP_DIRECTORY, name)
end

-- -----------------------------------------------------------------------------------------
-- Foot frames
-- -----------------------------------------------------------------------------------------

type Body = {
	rig: Rig.Rig,
	gaits: { [string]: Gait },
	ground: number,
	sole: Vector3,
	pivots: { [string]: Vector3 },
}

local built: { harness: any, body: Body }? = nil

-- The rig and the gaits, built once per harness.
local function bodyFor(Harness: any): Body
	if built and built.harness == Harness then
		return built.body
	end
	local rig = Rig.new(Harness)
	local foot = rig.footSize * 0.5
	local sole = Vector3.new(0, -foot.Y, 0)
	local body: Body = {
		rig = rig,
		gaits = Gaits.build(rig),
		ground = rig.ground,
		sole = sole,
		pivots = {
			heel = Vector3.new(0, -foot.Y, foot.Z),
			toe = Vector3.new(0, -foot.Y, -foot.Z),
			center = sole,
			left = Vector3.new(-foot.X, -foot.Y, 0), -- outer edge of a left foot (side-steps)
			right = Vector3.new(foot.X, -foot.Y, 0),
		},
	}
	built = { harness = Harness, body = body }
	return body
end

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function wrap(t: number, from: number, period: number): number
	return from + ((t - from) % period)
end

-- A foot state: { x, y, z, pitch, roll }: the sole center (root space, y above the field), pitch
-- (degrees, X+ toes up) and roll (degrees, Z+ rolls left).
type FootState = { number }

local function stateCF(body: Body, s: FootState): CFrame
	return CFrame.new(s[1], body.ground + s[2], s[3])
		* CFrame.Angles(math.rad(s[4]), 0, math.rad(s[5]))
		* CFrame.new(-body.sole)
end

local function cfState(body: Body, cf: CFrame): FootState
	local sole = cf * body.sole
	local look = cf.LookVector
	local right = cf.RightVector
	return {
		sole.X,
		sole.Y - body.ground,
		sole.Z,
		math.deg(math.atan2(look.Y, -look.Z)),
		math.deg(math.atan2(right.Y, right.X)),
	}
end

-- The planted foot's frame at time t (plan.ts <= t <= plan.tl).
local function stanceCF(body: Body, gait: Gait, plan: Plan, t: number): CFrame
	local travel = gait.dir * gait.speed * (t - plan.ts)
	local flat = Vector3.new(plan.x, body.ground, plan.z) - travel -- the flat sole center
	local pivotName: string, angle: number
	if t < plan.flatFrom then
		local a = smooth((t - plan.ts) / (plan.flatFrom - plan.ts))
		pivotName, angle = plan.strikePivot, plan.strikeAngle * (1 - a)
	elseif t <= plan.flatTo then
		pivotName, angle = "center", 0
	else
		local a = math.clamp((t - plan.flatTo) / (plan.tl - plan.flatTo), 0, 1)
		local power = plan.liftPower
		a = if power then a ^ power else smooth(a)
		pivotName, angle = plan.liftPivot, plan.liftAngle * a
	end
	local pivot = body.pivots[pivotName]
	local at = flat + (pivot - body.sole)
	local rotation
	if pivotName == "left" or pivotName == "right" then
		rotation = CFrame.Angles(0, 0, math.rad(angle))
	else
		rotation = CFrame.Angles(math.rad(angle), 0, 0)
	end
	return CFrame.new(at) * rotation * CFrame.new(-pivot)
end

-- When the foot is off the field: the lift, or the end of its peel.
local function liftEnd(plan: Plan): number
	local peel = plan.peel
	return plan.tl + (if peel then peel.duration else 0)
end

-- The peeling foot's frame at time t (plan.tl < t <= liftEnd): still going back with the field,
-- the lift pivot rising and the roll going on, both eased in from the lift.
local function peelCF(body: Body, gait: Gait, plan: Plan, peel: Keys.Peel, t: number): CFrame
	local a = math.clamp((t - plan.tl) / peel.duration, 0, 1)
	local eased = a * a
	local travel = gait.dir * gait.speed * (t - plan.ts)
	local flat = Vector3.new(plan.x, body.ground, plan.z) - travel
	local pivot = body.pivots[plan.liftPivot]
	local at = flat + (pivot - body.sole) + Vector3.new(0, peel.rise * eased, 0)
	local angle = plan.liftAngle + peel.angle * eased
	local rotation
	if plan.liftPivot == "left" or plan.liftPivot == "right" then
		rotation = CFrame.Angles(0, 0, math.rad(angle))
	else
		rotation = CFrame.Angles(math.rad(angle), 0, 0)
	end
	return CFrame.new(at) * rotation * CFrame.new(-pivot)
end

-- When the foot comes down onto its line: the strike, or the start of its approach (D-334).
local function approachStart(plan: Plan): number
	local approach = plan.approach
	return plan.ts - (if approach then approach.duration else 0)
end

-- The approaching foot's frame at time t (approachStart <= t <= plan.ts): already going back with
-- the field, the strike pivot coming down and the roll going back to the strike's, both eased out
-- into the strike, so it meets stanceCF there.
local function approachCF(body: Body, gait: Gait, plan: Plan, approach: Keys.Approach, t: number): CFrame
	local a = math.clamp((plan.ts - t) / approach.duration, 0, 1)
	local eased = a * a
	local travel = gait.dir * gait.speed * (t - plan.ts)
	local flat = Vector3.new(plan.x, body.ground, plan.z) - travel
	local pivot = body.pivots[plan.strikePivot]
	local at = flat + (pivot - body.sole) + Vector3.new(0, approach.rise * eased, 0)
	local angle = plan.strikeAngle + approach.angle * eased
	local rotation
	if plan.strikePivot == "left" or plan.strikePivot == "right" then
		rotation = CFrame.Angles(0, 0, math.rad(angle))
	else
		rotation = CFrame.Angles(math.rad(angle), 0, 0)
	end
	return CFrame.new(at) * rotation * CFrame.new(-pivot)
end

-- The foot's frame from the strike to the end of its peel.
local function groundCF(body: Body, gait: Gait, plan: Plan, t: number): CFrame
	local peel = plan.peel
	if peel and t > plan.tl + EDGE then
		return peelCF(body, gait, plan, peel, t)
	end
	return stanceCF(body, gait, plan, t)
end

local function hermite(p0: number, m0: number, p1: number, m1: number, u: number, h: number): number
	local u2, u3 = u * u, u * u * u
	local h00 = 2 * u3 - 3 * u2 + 1
	local h10 = u3 - 2 * u2 + u
	local h01 = -2 * u3 + 3 * u2
	local h11 = u3 - u2
	return h00 * p0 + h10 * h * m0 + h01 * p1 + h11 * h * m1
end

type PathPoint = { t: number, s: FootState }

-- The foot's frame at any time: planted or peeling, coming down through its approach, or on the
-- swing path (a Hermite curve through the lift state, the swing points and the next strike state
-- or the approach's start, its end tangents matching the stance's or the approach's).
local function footCF(body: Body, gait: Gait, plan: Plan, time: number): CFrame
	local T = gait.duration
	local t = wrap(time, plan.ts, T)
	local off = liftEnd(plan)
	if t <= off + EDGE then
		return groundCF(body, gait, plan, t)
	end
	local approach = plan.approach
	local on = approachStart(plan) + T
	if approach and t >= on - EDGE then
		return approachCF(body, gait, plan, approach, t - T)
	end
	local lift = cfState(body, groundCF(body, gait, plan, off))
	local liftBefore = cfState(body, groundCF(body, gait, plan, off - EPS))
	local strike, strikeAfter
	if approach then
		strike = cfState(body, approachCF(body, gait, plan, approach, on - T))
		strikeAfter = cfState(body, approachCF(body, gait, plan, approach, on - T + EPS))
	else
		strike = cfState(body, stanceCF(body, gait, plan, plan.ts))
		strikeAfter = cfState(body, stanceCF(body, gait, plan, plan.ts + EPS))
	end
	local points: { PathPoint } = { { t = off, s = lift } }
	local swing = plan.swing
	if swing then
		for _, p in swing do
			local at = wrap(p.t, plan.ts, T)
			if at >= on - SAME then
				error(("gaitgen: a swing point at %.4f s falls in the approach"):format(p.t))
			end
			table.insert(points, { t = at, s = { p.x, p.y, p.z, p.pitch, p.roll } })
		end
	end
	table.insert(points, { t = on, s = strike })
	table.sort(points, function(a: PathPoint, b: PathPoint): boolean
		return a.t < b.t
	end)
	local tangents: { FootState } = {}
	for i, p in points do
		local m: FootState = {}
		for f = 1, 5 do
			if i == 1 then
				m[f] = (p.s[f] - liftBefore[f]) / EPS
			elseif i == #points then
				m[f] = (strikeAfter[f] - p.s[f]) / EPS
			else
				local a, b = points[i - 1], points[i + 1]
				m[f] = (b.s[f] - a.s[f]) / (b.t - a.t)
			end
		end
		tangents[i] = m
	end
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		if t >= a.t - EDGE and t <= b.t + EDGE then
			local h = b.t - a.t
			local u = (t - a.t) / h
			local s: FootState = {}
			for f = 1, 5 do
				s[f] = hermite(a.s[f], tangents[i][f], b.s[f], tangents[i + 1][f], u, h)
			end
			return stateCF(body, s)
		end
	end
	error("no swing segment at " .. t)
end

-- -----------------------------------------------------------------------------------------
-- Legs
-- -----------------------------------------------------------------------------------------

type Leg = { hip: string, knee: string, ankle: string, foot: string }

local LEGS: { [string]: Leg } = {
	Left = { hip = "LeftHip", knee = "LeftKnee", ankle = "LeftAnkle", foot = "LeftFoot" },
	Right = { hip = "RightHip", knee = "RightKnee", ankle = "RightAnkle", foot = "RightFoot" },
}
local SIDES = { "Left", "Right" }

-- Hip X, Y, Z, knee X, ankle X, Z (degrees): the six angles a leg is solved in.
type LegAngles = { number }

-- Solves one leg so its foot lands on `target` (root space); returns the angles and how far the
-- foot ends from the target (studs).
local function legIK(
	body: Body,
	offsets: Ik.Offsets,
	side: string,
	target: CFrame,
	seed: LegAngles
): (LegAngles, number)
	local leg = LEGS[side]
	local base = body.rig.base
	local params: { Ik.Param } = {
		{ joint = leg.hip, axis = 1, start = seed[1], seed = seed[1], reg = REG, min = -100, max = 130 },
		{ joint = leg.hip, axis = 2, start = seed[2], seed = 0, reg = REG * 3, min = -40, max = 40 },
		{ joint = leg.hip, axis = 3, start = seed[3], seed = seed[3], reg = REG, min = -50, max = 50 },
		{ joint = leg.knee, axis = 1, start = seed[4], seed = seed[4], reg = REG, min = -150, max = 0 },
		{ joint = leg.ankle, axis = 1, start = seed[5], seed = seed[5], reg = REG, min = -80, max = 80 },
		{ joint = leg.ankle, axis = 3, start = seed[6], seed = 0, reg = REG * 3, min = -40, max = 40 },
	}
	local x = Ik.solve(offsets, params, {
		iterations = ITERATIONS,
		solve = body.rig.solve,
		residual = function(solved: Ik.Solved): { number }
			local cf = base:ToObjectSpace(solved[leg.foot])
			local dp = cf.Position - target.Position
			local dr = cf.RightVector - target.RightVector
			local du = cf.UpVector - target.UpVector
			return {
				POSITION_WEIGHT * dp.X,
				POSITION_WEIGHT * dp.Y,
				POSITION_WEIGHT * dp.Z,
				AXIS_WEIGHT * dr.X,
				AXIS_WEIGHT * dr.Y,
				AXIS_WEIGHT * dr.Z,
				AXIS_WEIGHT * du.X,
				AXIS_WEIGHT * du.Y,
				AXIS_WEIGHT * du.Z,
			}
		end,
	})
	-- the position error without the regularisation
	local solved = body.rig.solve(Ik.apply(offsets, params, x))
	local miss = (base:ToObjectSpace(solved[leg.foot]).Position - target.Position).Magnitude
	return x, miss
end

local function mirrorJoint(name: string): string
	if name:sub(1, 4) == "Left" then
		return "Right" .. name:sub(5)
	elseif name:sub(1, 5) == "Right" then
		return "Left" .. name:sub(6)
	end
	return name
end

local function mirrorKey(key: Keys.JointKey): Keys.JointKey
	local pos = key.pos
	return {
		pos = if pos then { -pos[1], pos[2], pos[3] } else nil,
		rot = { key.rot[1], -key.rot[2], -key.rot[3] },
	}
end

-- The clip keys of one gait, with its worst stance miss and the misses past MISS.
local function solveKeys(body: Body, gait: Gait): ({ Emit.ClipKey }, number, { string })
	local T = gait.duration
	local seeds: { [string]: LegAngles } = {
		Left = { 0, 0, 0, SEED_KNEE, 0, 0 },
		Right = { 0, 0, 0, SEED_KNEE, 0, 0 },
	}
	local worst = 0
	local misses: { string } = {}
	local function inStance(plan: Plan, kt: number): boolean
		return wrap(kt, plan.ts, T) <= plan.tl + EDGE
	end
	local function same(a: number, b: number): boolean
		return math.abs(((a - b + T / 2) % T) - T / 2) < SAME
	end
	-- the root and upper body of every key, as offsets for the solve and as keys for the clip
	local keyOffsets: { Ik.Offsets } = {}
	local keyJoints: { Keys.Joints } = {}
	for index, kt in gait.keyTimes do
		local offsets: Ik.Offsets = {}
		local joints: Keys.Joints = {}
		for name, key in gait.upper(kt) do
			offsets[name] = { pos = key.pos or { 0, 0, 0 }, rot = key.rot }
			joints[name] = key
		end
		keyOffsets[index], keyJoints[index] = offsets, joints
	end
	for _, side in SIDES do
		local plan = if side == "Left" then gait.plans.Left else gait.plans.Right
		local leg = LEGS[side]
		local solution: { [number]: LegAngles } = {}
		-- stance keys by IK, twice round so the first seed comes from the stance's own end
		for pass = 1, 2 do
			for index, kt in gait.keyTimes do
				if inStance(plan, kt) then
					local x, miss = legIK(body, keyOffsets[index], side, footCF(body, gait, plan, kt), seeds[side])
					seeds[side] = x
					solution[index] = x
					if pass == 2 then
						worst = math.max(worst, miss)
						if miss > MISS then
							table.insert(misses, ("%s foot misses by %.3f at %.4f s"):format(side, miss, kt))
						end
					end
				end
			end
		end
		local liftAngles: LegAngles?, strikeAngles: LegAngles?
		for index, kt in gait.keyTimes do
			if same(kt, plan.tl) then
				liftAngles = solution[index]
			end
			if same(kt, plan.ts) then
				strikeAngles = solution[index]
			end
		end
		if liftAngles == nil or strikeAngles == nil then
			error("gaitgen: a plan's lift and strike need keys")
		end
		local lifted: LegAngles, struck: LegAngles = liftAngles, strikeAngles
		-- peel keys by IK, in time order from the lift (seeded from the lift's solution)
		local off = liftEnd(plan)
		local function inPeel(kt: number): boolean
			local w = wrap(kt, plan.ts, T)
			return w > plan.tl + EDGE and w <= off + EDGE
		end
		local offAngles: LegAngles = lifted
		if plan.peel then
			local order: { number } = {}
			for index, kt in gait.keyTimes do
				if inPeel(kt) then
					table.insert(order, index)
				end
			end
			table.sort(order, function(a: number, b: number): boolean
				return wrap(gait.keyTimes[a], plan.tl, T) < wrap(gait.keyTimes[b], plan.tl, T)
			end)
			seeds[side] = lifted
			local peeled: LegAngles? = nil
			for _, index in order do
				local kt = gait.keyTimes[index]
				local x, miss = legIK(body, keyOffsets[index], side, footCF(body, gait, plan, kt), seeds[side])
				seeds[side] = x
				solution[index] = x
				worst = math.max(worst, miss)
				if miss > MISS then
					table.insert(misses, ("%s foot misses its peel by %.3f at %.4f s"):format(side, miss, kt))
				end
				if same(kt, off) then
					peeled = x
				end
			end
			if peeled == nil then
				error("gaitgen: a plan's peel needs a key at its end")
			end
			offAngles = peeled :: LegAngles
		end
		-- approach keys by IK, back in time from the strike (seeded from the strike's solution)
		local on = approachStart(plan) + T
		local function inApproach(kt: number): boolean
			return plan.approach ~= nil and wrap(kt, plan.ts, T) >= on - EDGE
		end
		local onAngles: LegAngles = struck
		if plan.approach then
			local order: { number } = {}
			for index, kt in gait.keyTimes do
				if inApproach(kt) then
					table.insert(order, index)
				end
			end
			table.sort(order, function(a: number, b: number): boolean
				return wrap(gait.keyTimes[a], plan.ts, T) > wrap(gait.keyTimes[b], plan.ts, T)
			end)
			seeds[side] = struck
			local started: LegAngles? = nil
			for _, index in order do
				local kt = gait.keyTimes[index]
				local x, miss = legIK(body, keyOffsets[index], side, footCF(body, gait, plan, kt), seeds[side])
				seeds[side] = x
				solution[index] = x
				worst = math.max(worst, miss)
				if miss > MISS then
					table.insert(misses, ("%s foot misses its approach by %.3f at %.4f s"):format(side, miss, kt))
				end
				if same(kt, on) then
					started = x
				end
			end
			if started == nil then
				error("gaitgen: a plan's approach needs a key at its start")
			end
			onAngles = started :: LegAngles
		end
		-- swing keys: set by hand (hip Y/Z and ankle Z blend from the lift, or the peel's end, to
		-- the strike or the approach's start) with the keys between them where the clip would play
		-- the leg without them, or by IK to the path
		local entries: { Keys.SwingJoint } = plan.swingJoints or {}
		type Anchor = { t: number, x: LegAngles }
		local anchors: { Anchor } = { { t = off, x = offAngles } }
		local span = on - off
		for _, e in entries do
			local at = wrap(e.t, off, T)
			if at >= on - SAME then
				error(("gaitgen: a swing joint key at %.4f s falls in the approach"):format(e.t))
			end
			local frac = (at - off) / span
			local function mix(i: number): number
				return offAngles[i] + (onAngles[i] - offAngles[i]) * frac
			end
			table.insert(anchors, { t = at, x = { e.hip, mix(2), mix(3), e.knee, e.ankle, mix(6) } })
		end
		table.insert(anchors, { t = on, x = onAngles })
		table.sort(anchors, function(a: Anchor, b: Anchor): boolean
			return a.t < b.t
		end)
		for index, kt in gait.keyTimes do
			if not inStance(plan, kt) and not inPeel(kt) and not inApproach(kt) then
				if #entries > 0 then
					local at = wrap(kt, off, T)
					local x: LegAngles? = nil
					for i = 1, #anchors - 1 do
						local a, b = anchors[i], anchors[i + 1]
						if at >= a.t - SAME and at <= b.t + SAME then
							local u = math.clamp((at - a.t) / (b.t - a.t), 0, 1)
							local eased = -(math.cos(math.pi * u) - 1) / 2 -- SineInOut, as the clip plays it
							local mixed: LegAngles = {}
							for f = 1, 6 do
								mixed[f] = a.x[f] + (b.x[f] - a.x[f]) * eased
							end
							x = mixed
							break
						end
					end
					if x == nil then
						error(("gaitgen: no swing anchor around %.4f s"):format(kt))
					end
					solution[index] = x :: LegAngles
				else
					local x = legIK(body, keyOffsets[index], side, footCF(body, gait, plan, kt), seeds[side])
					seeds[side] = x
					solution[index] = x
				end
			end
		end
		for index in gait.keyTimes do
			local x = solution[index]
			keyJoints[index][leg.hip] = { rot = { x[1], x[2], x[3] } }
			keyJoints[index][leg.knee] = { rot = { x[4], 0, 0 } }
			keyJoints[index][leg.ankle] = { rot = { x[5], 0, x[6] } }
		end
	end
	local keys: { Emit.ClipKey } = {}
	for index, kt in gait.keyTimes do
		local joints = keyJoints[index]
		if gait.mirrored then
			local mirrored: Keys.Joints = {}
			for name, key in joints do
				mirrored[mirrorJoint(name)] = mirrorKey(key)
			end
			joints = mirrored
		end
		keys[index] = { time = kt, easing = EASING, joints = joints, comment = gait.comments[kt] }
	end
	return keys, worst, misses
end

-- -----------------------------------------------------------------------------------------
-- Generate, write, check
-- -----------------------------------------------------------------------------------------

--- Generates one clip in memory. `Harness` is tests/_harness/Harness.luau.
function GaitGen.generate(Harness: any, name: string): Result
	local body = bodyFor(Harness)
	local gait = body.gaits[name]
	if gait == nil then
		error(("gaitgen: no gait %q (owned: %s)"):format(name, table.concat(GaitGen.NAMES, ", ")))
	end
	local keys, worst, misses = solveKeys(body, gait)
	return {
		name = name,
		path = GaitGen.path(name),
		source = Emit.clip(name, gait, keys),
		worstError = worst,
		misses = misses,
	}
end

--- Writes a generated clip over its file.
function GaitGen.write(Harness: any, result: Result)
	fs.writeFile(Harness.repoRoot() .. "/" .. result.path, result.source)
end

--- The clips the check compares: every owned clip but the DRIFTED ones.
function GaitGen.checked(): { string }
	local names: { string } = {}
	for _, name in GaitGen.NAMES do
		if GaitGen.DRIFTED[name] == nil then
			table.insert(names, name)
		end
	end
	return names
end

--- Compares a generated clip with the committed text (nil: no file). Returns nil when they match
--- byte for byte, else the first line that differs and how many lines do.
function GaitGen.compare(result: Result, committed: string?): Drift?
	if committed == result.source then
		return nil
	end
	if committed == nil then
		return { name = result.name, path = result.path, missing = true, line = 0, lines = 0 }
	end
	local committedLines = committed:split("\n")
	local generatedLines = result.source:split("\n")
	local first: number? = nil
	local count = 0
	for index = 1, math.max(#committedLines, #generatedLines) do
		if committedLines[index] ~= generatedLines[index] then
			first = first or index
			count += 1
		end
	end
	local line = first or 0
	return {
		name = result.name,
		path = result.path,
		missing = false,
		line = line,
		lines = count,
		committed = committedLines[line],
		generated = generatedLines[line],
	}
end

--- Regenerates each named clip (default: GaitGen.checked()) in memory and compares it with the
--- committed file. Returns one Drift per clip that differs.
function GaitGen.check(Harness: any, names: { string }?): { Drift }
	local drifts: { Drift } = {}
	for _, name in names or GaitGen.checked() do
		local result = GaitGen.generate(Harness, name)
		local ok, committed = pcall(Harness.readFile, result.path)
		local drift = GaitGen.compare(result, if ok then committed else nil)
		if drift then
			table.insert(drifts, drift)
		end
	end
	return drifts
end

--- One line describing a drift.
function GaitGen.describe(drift: Drift): string
	if drift.missing then
		return ("%s: %s is missing"):format(drift.name, drift.path)
	end
	return ("%s: %s differs from the generator on %d line(s), first line %d: committed `%s`, generated `%s`"):format(
		drift.name,
		drift.path,
		drift.lines,
		drift.line,
		drift.committed or "(end of file)",
		drift.generated or "(end of file)"
	)
end

return GaitGen
