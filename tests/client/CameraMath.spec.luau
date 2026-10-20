--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local CameraMath = Harness.load("src/client/camera/CameraMath")
local Spring = Harness.load("src/shared/util/Spring")
local camera = Harness.load("src/shared/data/camera")
local combat = Harness.load("src/shared/data/combat")

local function simulate(spring, seconds, dt, onStep)
	local t = 0
	while t < seconds do
		spring:Step(dt)
		t += dt
		if onStep then
			onStep(spring.position, t)
		end
	end
	return spring.position
end

describe("CameraMath", function()
	it("turns the follow lag into a critically damped spring that settles without overshoot", function()
		local stiffness = CameraMath.springFromLag(camera.follow.lag)
		expect(stiffness).toBeCloseTo((1 / camera.follow.lag) ^ 2, 1e-6)
		local spring = Spring.new(0, stiffness, camera.follow.damping)
		spring.target = 1
		local previous = 0
		local final = simulate(spring, camera.follow.lag * 5, 1 / 240, function(position)
			expect(position).toBeGreaterThanOrEqual(previous - 1e-9)
			expect(position).toBeLessThanOrEqual(1 + 1e-6)
			previous = position
		end)
		expect(final).toBeGreaterThan(0.9)
		expect(final).toBeLessThan(1)
	end)

	it("sizes a nudge impulse so the spring peaks at the requested studs", function()
		local stiffness = CameraMath.springFromLag(camera.follow.lag)
		local spring = Spring.new(0, stiffness, 1)
		spring:Impulse(CameraMath.impulseForDisplacement(camera.nudge.studs, stiffness))
		local peak = 0
		simulate(spring, camera.follow.lag * 8, 1 / 480, function(position)
			peak = math.max(peak, position)
		end)
		expect(peak).toBeCloseTo(camera.nudge.studs, camera.nudge.studs * 0.05)
	end)

	it("decays exponentially", function()
		expect(CameraMath.decay(1, math.log(2), 1)).toBeCloseTo(0.5, 1e-9)
		expect(CameraMath.decay(10, camera.shake.decay, 0)).toBe(10)
		expect(CameraMath.decay(10, camera.shake.decay, 1)).toBeLessThan(0.01)
	end)

	it("shake is bounded noise that differs per axis and over time, zero at zero amplitude", function()
		local lanes = camera.shake.lanes
		expect(CameraMath.shakeOffset(0.3, 0, camera.shake.frequency, lanes)).toEqual({ 0, 0, 0 })
		local a = CameraMath.shakeOffset(0.31, 0.3, camera.shake.frequency, lanes)
		local b = CameraMath.shakeOffset(0.37, 0.3, camera.shake.frequency, lanes)
		for axis = 1, 3 do
			expect(math.abs(a[axis])).toBeLessThanOrEqual(0.3 + 1e-9)
		end
		expect(a[1] == b[1] and a[2] == b[2] and a[3] == b[3]).toBe(false)
		expect(a[1] == a[2] and a[2] == a[3]).toBe(false)
	end)

	it("orbits behind a rig at yaw 0 and swings around with yaw and pitch", function()
		local behind = CameraMath.orbitOffset(0, 0, 10, 0, 0)
		expect(behind[1]).toBeCloseTo(0, 1e-6)
		expect(behind[2]).toBeCloseTo(0, 1e-6)
		expect(behind[3]).toBeCloseTo(10, 1e-6)
		local left = CameraMath.orbitOffset(90, 0, 10, 0, 0)
		expect(left[1]).toBeCloseTo(10, 1e-6)
		expect(left[3]).toBeCloseTo(0, 1e-6)
		local above = CameraMath.orbitOffset(0, 90, 10, 2, 0)
		expect(above[2]).toBeCloseTo(12, 1e-6)
		expect(above[3]).toBeCloseTo(0, 1e-6)
		local shoulder = CameraMath.orbitOffset(0, 0, 10, 0, 1.5)
		expect(shoulder[1]).toBeCloseTo(1.5, 1e-6)
	end)

	it("yawTowards puts the camera behind the viewer looking at the target", function()
		expect(CameraMath.yawTowards({ 0, 0, 0 }, { 0, 0, -5 })).toBeCloseTo(0, 1e-6)
		expect(CameraMath.yawTowards({ 0, 0, 0 }, { 5, 0, 0 })).toBeCloseTo(-90, 1e-6)
		expect(math.abs(CameraMath.yawTowards({ 0, 0, 0 }, { 0, 0, 5 }))).toBeCloseTo(180, 1e-6)
		expect(CameraMath.yawTowards({ 1, 0, 1 }, { 1, 0, 1 })).toBe(0)
	end)

	it("takes the shortest way around and wraps angles", function()
		expect(CameraMath.shortestDelta(170, -170)).toBeCloseTo(20, 1e-9)
		expect(CameraMath.shortestDelta(-170, 170)).toBeCloseTo(-20, 1e-9)
		expect(CameraMath.shortestDelta(0, 180)).toBe(180)
		expect(CameraMath.wrapDegrees(190)).toBeCloseTo(-170, 1e-9)
		expect(CameraMath.wrapDegrees(-190)).toBeCloseTo(170, 1e-9)
	end)

	it("applies look input with pitch clamping, yaw wrapping and optional inversion", function()
		local yaw, pitch = CameraMath.applyLook(170, 10, -100, 0, 0.5, false, -20, 75)
		expect(yaw).toBeCloseTo(-140, 1e-9)
		expect(pitch).toBe(10)
		local _, high = CameraMath.applyLook(0, 70, 0, 100, 0.5, false, -20, 75)
		expect(high).toBe(75)
		local _, inverted = CameraMath.applyLook(0, 10, 0, 10, 0.5, true, -20, 75)
		expect(inverted).toBeCloseTo(5, 1e-9)
	end)

	it("frames a lock between the fighters with a distance that grows with separation", function()
		local params = camera.lock
		local frame = CameraMath.lockFrame({ 0, 0, 0 }, { 0, 0, -10 }, params)
		expect(frame.separation).toBeCloseTo(10, 1e-6)
		expect(frame.yaw).toBeCloseTo(0, 1e-6)
		expect(frame.focus[3]).toBeCloseTo(-10 * params.focusBias, 1e-6)
		expect(frame.distance).toBeCloseTo(
			math.clamp(params.baseDistance + 10 * params.distancePerSeparation, params.minDistance, params.maxDistance),
			1e-6
		)
		local far = CameraMath.lockFrame({ 0, 0, 0 }, { 0, 0, -200 }, params)
		expect(far.distance).toBe(params.maxDistance)
		local near = CameraMath.lockFrame({ 0, 0, 0 }, { 0, 0, -1 }, params)
		expect(near.distance).toBeGreaterThanOrEqual(params.minDistance)
	end)

	it("pulls the camera in front of a wall and never closer than the minimum", function()
		expect(CameraMath.collisionDistance(12, nil, 0.6, 1.5)).toBe(12)
		expect(CameraMath.collisionDistance(12, 8, 0.6, 1.5)).toBeCloseTo(7.4, 1e-9)
		expect(CameraMath.collisionDistance(12, 1, 0.6, 1.5)).toBe(1.5)
		expect(CameraMath.collisionDistance(5, 20, 0.6, 1.5)).toBe(5)
	end)

	it("samples a scripted shot list by segment", function()
		local index, alpha = CameraMath.scriptedSample(3, 2, 0)
		expect(index).toBe(1)
		expect(alpha).toBe(0)
		index, alpha = CameraMath.scriptedSample(3, 2, 0.5)
		expect(index).toBe(1)
		expect(alpha).toBeCloseTo(0.5, 1e-9)
		index, alpha = CameraMath.scriptedSample(3, 2, 1.5)
		expect(index).toBe(2)
		expect(alpha).toBeCloseTo(0.5, 1e-9)
		index, alpha = CameraMath.scriptedSample(3, 2, 3)
		expect(index).toBe(2)
		expect(alpha).toBe(1)
		index, alpha = CameraMath.scriptedSample(1, 2, 1)
		expect(index).toBe(1)
		expect(alpha).toBe(0)
	end)

	it("eases blends with a sine curve", function()
		expect(CameraMath.easeBlend(0, 1)).toBeCloseTo(0, 1e-9)
		expect(CameraMath.easeBlend(0.5, 1)).toBeCloseTo(0.5, 1e-9)
		expect(CameraMath.easeBlend(1, 1)).toBeCloseTo(1, 1e-9)
		expect(CameraMath.easeBlend(0.25, 1)).toBeLessThan(0.25)
		expect(CameraMath.easeBlend(5, 0)).toBe(1)
		expect(CameraMath.raise({ 1, 2, 3 }, 2)).toEqual({ 1, 4, 3 })
	end)

	it("the camera data keeps the section 10 numbers", function()
		expect(camera.follow.lag).toBe(0.12)
		expect(camera.fov.rest).toBe(60)
		expect(camera.fov.artKick).toBe(8)
		expect(camera.nudge.studs).toBe(0.4)
		expect(camera.shake.amplitude).toEqual({ Normal = 0.15, Final = 0.3, Kill = 0.6 })
		expect(camera.orbit.Duel.distance).toBeLessThan(camera.orbit.Default.distance)
		expect(camera.orbit.Raid.distance).toBeGreaterThan(camera.orbit.Default.distance)
		expect(camera.orbit.Duel.pitch).toBeLessThan(camera.orbit.Raid.pitch)
		expect(camera.mobile.distanceMultiplier).toBeGreaterThan(1)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The FOV punch (the push in on the big hit)
-- ------------------------------------------------------------------------------------------

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Samples a punch at `hz` from 0 to its end: { {t, offset} }.
local function samples(params: any, hz: number, from: number?): { { number } }
	local list = {}
	local step = 1 / hz
	local t = 0
	local total = CameraMath.punchSeconds(params)
	while t < total do
		local offset = CameraMath.punchOffset(t, params, from)
		table.insert(list, { t, offset })
		t += step
	end
	return list
end

describe("CameraMath punch", function()
	for _, kind in { "Final", "Kill" } do
		local params = camera.punch[kind]

		it(kind .. ": eases in to -degrees over the attack, fastest at the start", function()
			expect(CameraMath.punchOffset(0, params)).toBe(0)
			expect(CameraMath.punchOffset(params.attack, params)).toBeCloseTo(-params.degrees, 1e-9)
			-- QuadOut: three quarters of the way at half the attack, never the linear half.
			local half = CameraMath.punchOffset(params.attack * 0.5, params)
			expect(half).toBeCloseTo(-params.degrees * 0.75, 1e-9)
			local previous = 0
			local previousStep = math.huge
			for index = 1, 20 do
				local offset = CameraMath.punchOffset(params.attack * index / 20, params)
				local stepSize = previous - offset
				expect(stepSize).toBeGreaterThan(0) -- narrowing all the way
				expect(stepSize).toBeLessThan(previousStep + 1e-12) -- and slowing down: eased, not linear
				previous, previousStep = offset, stepSize
			end
		end)

		it(kind .. ": arrives at the peak with no kink and springs back past rest before it settles", function()
			local dt = 1e-4
			local before = CameraMath.punchOffset(params.attack - dt, params)
			local after = CameraMath.punchOffset(params.attack + dt, params)
			local peak = CameraMath.punchOffset(params.attack, params)
			-- Both sides of the seam are flat at the peak (zero slope in, zero velocity out).
			expect(math.abs(before - peak) / dt).toBeLessThan(params.degrees / params.attack * 0.01)
			expect(math.abs(after - peak) / dt).toBeLessThan(params.degrees / params.attack * 0.01)
			local widest, narrowest = 0, 0
			for _, sample in samples(params, 480) do
				widest = math.max(widest, sample[2])
				narrowest = math.min(narrowest, sample[2])
			end
			expect(narrowest).toBeGreaterThanOrEqual(-params.degrees - 1e-9)
			expect(widest).toBeGreaterThan(0)
			expect(widest).toBeLessThanOrEqual(params.degrees * 0.25)
			-- Settled at the end, so dropping it never pops; then it reports done at 0.
			local total = CameraMath.punchSeconds(params)
			local tail = CameraMath.punchOffset(total - 1e-4, params)
			expect(math.abs(tail)).toBeLessThanOrEqual(params.degrees * params.band * 1.5)
			local offset, done = CameraMath.punchOffset(total, params)
			expect(offset).toBe(0)
			expect(done).toBe(true)
			local _, early = CameraMath.punchOffset(total * 0.5, params)
			expect(early).toBe(false)
		end)

		it(kind .. ": is never linear on the way back", function()
			local list = samples(params, 240)
			local curved = 0
			for index = 2, #list - 1 do
				local t = list[index][1]
				if t > params.attack + 1 / 240 then
					local second = list[index + 1][2] - 2 * list[index][2] + list[index - 1][2]
					if math.abs(second) > 1e-7 then
						curved += 1
					end
				end
			end
			local back = 0
			for _, sample in list do
				if sample[1] > params.attack + 1 / 240 then
					back += 1
				end
			end
			-- Every step on the way back bends (a linear return would have no second difference).
			expect(curved).toBeGreaterThanOrEqual(back - 4)
		end)
	end

	it("a punch over a punch eases on from the offset showing, so the FOV never jumps", function()
		local params = camera.punch.Kill
		expect(CameraMath.punchOffset(0, params, -2)).toBe(-2)
		expect(CameraMath.punchOffset(1e-5, params, -2)).toBeCloseTo(-2, 1e-3)
		expect(CameraMath.punchOffset(params.attack, params, -2)).toBeCloseTo(-params.degrees, 1e-9)
		expect(CameraMath.punchOffset(params.attack * 0.5, params, -2)).toBeCloseTo(
			-2 + (-params.degrees + 2) * 0.75,
			1e-9
		)
	end)

	it("springBack starts at 1, under-damped swings past 0, critical settles without crossing", function()
		expect(CameraMath.springBack(0, 0.3, 0.5, 0.02)).toBe(1)
		local crossed = false
		local t = 0
		while t < 0.3 do
			if CameraMath.springBack(t, 0.3, 0.5, 0.02) < 0 then
				crossed = true
			end
			t += 1 / 480
		end
		expect(crossed).toBe(true)
		local previous = 1
		t = 1 / 480
		while t < 0.3 do
			local value = CameraMath.springBack(t, 0.3, 1, 0.02)
			expect(value).toBeGreaterThan(0)
			expect(value).toBeLessThan(previous)
			previous = value
			t += 1 / 480
		end
		expect(CameraMath.springBack(0.3, 0.3, 1, 0.02)).toBeCloseTo(0.02, 1e-3)
	end)

	it("the camera data pushes in a few degrees inside each tier's hit-stop, the kill furthest", function()
		for kind, params in camera.punch do
			expect(params.degrees).toBeGreaterThan(0)
			expect(params.degrees).toBeLessThanOrEqual(camera.fov.artKick)
			expect(params.attack).toBeLessThanOrEqual(combat.hitStopFrames[kind] * combat.hitStopFrameSeconds + 1e-9)
			expect(params.damping).toBeLessThan(1)
		end
		expect(camera.punch.Kill.degrees).toBeGreaterThanOrEqual(camera.punch.Final.degrees)
	end)
end)

describe("camera validator: punch", function()
	local function runValidator(change: ((any) -> ())?): { string }
		local path = "tools/validators/camera.luau"
		local chunk = luau.load(
			fs.readFile(Harness.repoRoot() .. "/" .. path),
			{ debugName = path, environment = Harness.environment() :: any }
		)
		local validate = chunk()
		-- Only the punch is copied: the validator checks the shake and nudge rows by identity.
		local copy = table.clone(camera)
		copy.punch = deepCopy(camera.punch)
		if change ~= nil then
			change(copy)
		end
		return validate({
			load = function(modulePath: string): any
				if modulePath == "src/shared/data/camera" then
					return copy
				end
				return Harness.load(modulePath)
			end,
			listFiles = Harness.listFiles,
			readFile = Harness.readFile,
			repoRoot = Harness.repoRoot(),
		})
	end

	local function mentions(problems: { string }, needle: string): boolean
		for _, problem in problems do
			if problem:find(needle, 1, true) then
				return true
			end
		end
		return false
	end

	it("is clean on the real table", function()
		expect(runValidator()).toEqual({})
	end)

	it("needs both rows, named by hit-stop tiers", function()
		local problems = runValidator(function(copy)
			copy.punch.Kill = nil
			copy.punch.Huge = deepCopy(copy.punch.Final)
		end)
		expect(mentions(problems, "punch.Kill is missing")).toBe(true)
		expect(mentions(problems, "punch.Huge must be named by a hit-stop tier")).toBe(true)
	end)

	it("rejects a push past the Art kick and an attack that outlasts the hit-stop", function()
		local problems = runValidator(function(copy)
			copy.punch.Final.degrees = camera.fov.artKick + 1
			copy.punch.Kill.attack = combat.hitStopFrames.Kill * combat.hitStopFrameSeconds * 2
		end)
		expect(mentions(problems, "punch.Final.degrees must be a few degrees")).toBe(true)
		expect(mentions(problems, "punch.Kill.attack must be positive and land inside the Kill hit-stop")).toBe(true)
	end)

	it("rejects a return with no spring, one that swings too far, and a loose settle band", function()
		local problems = runValidator(function(copy)
			copy.punch.Final.damping = 1
			copy.punch.Kill.damping = 0.15
		end)
		expect(mentions(problems, "punch.Final.damping must be in (0, 1)")).toBe(true)
		expect(mentions(problems, "punch.Kill must overshoot rest by at most a quarter")).toBe(true)
		local loose = runValidator(function(copy)
			copy.punch.Final.band = 0.5
		end)
		expect(mentions(loose, "punch.Final.band must be in (0, 0.1]")).toBe(true)
	end)

	it("rejects a long punch and a kill that pushes in less than a final hit", function()
		local problems = runValidator(function(copy)
			copy.punch.Kill.settle = 2
			copy.punch.Kill.degrees = copy.punch.Final.degrees - 1
		end)
		expect(mentions(problems, "punch.Kill must be short")).toBe(true)
		expect(mentions(problems, "punch.Kill must push in at least as far as punch.Final")).toBe(true)
	end)
end)
