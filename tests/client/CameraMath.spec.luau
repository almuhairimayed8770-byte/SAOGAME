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

	it("frames a lock as a two-shot whose distance grows with the separation", function()
		local params = camera.lock
		local shot = CameraMath.twoShot({ 0, 0, 0 }, { 0, 0, -10 }, params)
		expect(shot.separation).toBeCloseTo(10, 1e-6)
		expect(shot.lineYaw).toBeCloseTo(0, 1e-6)
		expect(shot.distance).toBeCloseTo(
			math.clamp(params.baseDistance + 10 * params.distancePerSeparation, params.minDistance, params.maxDistance),
			1e-6
		)
		local far = CameraMath.twoShot({ 0, 0, 0 }, { 0, 0, -200 }, params)
		expect(far.distance).toBe(params.maxDistance)
		local near = CameraMath.twoShot({ 0, 0, 0 }, { 0, 0, -1 }, params)
		expect(near.distance).toBeGreaterThanOrEqual(params.minDistance)
		local mobile = CameraMath.twoShot({ 0, 0, 0 }, { 0, 0, -10 }, params, 1.25)
		expect(mobile.distance).toBeCloseTo(shot.distance * 1.25, 1e-6)
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
-- Framing: the free camera over the shoulder, the lock-on two-shot, the leash, the occluders
-- ------------------------------------------------------------------------------------------

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

describe("CameraMath framing", function()
	it("aims the free camera right of and above the pivot so the camera's elevation is its pitch", function()
		for _, yaw in { 0, 37, -120, 180 } do
			local look = v3(CameraMath.shoulderLook(yaw, 0.8, 2.5))
			local cameraAt = v3(CameraMath.orbitOffset(yaw, 8, 10, 0.8, 2.5))
			local view = look - cameraAt
			expect(view.Magnitude).toBeCloseTo(10, 1e-6)
			expect(math.deg(math.asin(-view.Unit.Y))).toBeCloseTo(8, 1e-6)
			-- The pivot (the player) sits left of where the camera looks.
			local right = view:Cross(Vector3.yAxis).Unit
			expect((Vector3.zero - cameraAt):Dot(right)).toBeLessThan(-1)
		end
	end)

	it("measures the split between the fighters, growing with the swing off the line", function()
		expect(CameraMath.splitAngle(10, 6, 0)).toBeCloseTo(0, 1e-9)
		local previous = 0
		for swing = 5, 90, 5 do
			local split = CameraMath.splitAngle(10, 6, swing)
			expect(split).toBeGreaterThan(previous)
			previous = split
		end
		-- Directly beside the player (90 degrees), the split is the angle the separation subtends.
		expect(CameraMath.splitAngle(10, 6, 90)).toBeCloseTo(math.deg(math.atan2(6, 10)), 1e-6)
	end)

	it("swings the two-shot just far enough to stand the fighters apart, less as they part", function()
		local params = camera.lock
		local previous = math.huge
		for _, separation in { 3, 4, 5, 6, 8, 10, 14, 20 } do
			local shot = CameraMath.twoShot({ 0, 3, 0 }, { 0, 3, -separation }, params)
			expect(shot.swing).toBeGreaterThan(0)
			expect(shot.swing).toBeLessThanOrEqual(params.maxOrbitDegrees)
			expect(shot.swing).toBeLessThanOrEqual(previous + 1e-9)
			previous = shot.swing
			if shot.swing < params.maxOrbitDegrees then
				-- The split the swing gives covers both clearances, seen from the camera.
				local toTarget = math.sqrt(
					shot.distance ^ 2 + separation ^ 2 + 2 * shot.distance * separation * math.cos(math.rad(shot.swing))
				)
				local needed = math.deg(
					math.atan(params.playerClearance / shot.distance) + math.atan(params.targetClearance / toTarget)
				)
				expect(CameraMath.splitAngle(shot.distance, separation, shot.swing)).toBeCloseTo(needed, 1e-3)
			end
		end
		-- Fighters on top of each other take the widest swing.
		expect(CameraMath.twoShot({ 0, 0, 0 }, { 0, 0, 0 }, params).swing).toBe(params.maxOrbitDegrees)
	end)

	it("puts the two-shot camera on its bearing around the player and aims between the fighters", function()
		local cameraAt = v3(CameraMath.twoShotCamera({ 1, 3, 2 }, 90, 10, 3.7))
		expect((cameraAt - Vector3.new(11, 6.7, 2)).Magnitude).toBeLessThan(1e-9)
		-- The bearing is the yaw the camera there has when it looks at the player.
		expect(CameraMath.yawTowards({ 11, 6.7, 2 }, { 1, 3, 2 })).toBeCloseTo(90, 1e-9)
		local look = v3(CameraMath.twoShotLook({ 0, 3, 0 }, { 0, 4, -8 }, 0.5, 1.3))
		expect((look - Vector3.new(0, 4.8, -4)).Magnitude).toBeLessThan(1e-9)
	end)

	it("keeps its side of the line until the camera is past the hysteresis on the other", function()
		expect(CameraMath.lockSide(1, 10, 15)).toBe(1)
		expect(CameraMath.lockSide(1, -10, 15)).toBe(1)
		expect(CameraMath.lockSide(1, -20, 15)).toBe(-1)
		expect(CameraMath.lockSide(-1, 10, 15)).toBe(-1)
		expect(CameraMath.lockSide(-1, 20, 15)).toBe(1)
	end)

	it("leashes the lagged pivot along the view only: so far ahead, a little further behind", function()
		local forward = { 0, 0, -1 }
		-- The body hopped back toward the camera: the lagged pivot is 4 studs ahead of it.
		local held = v3(CameraMath.leash({ 0, 3, 4 }, { 1, 3.5, 0 }, forward, 0.75, 2.5))
		expect((held - Vector3.new(1, 3.5, 3.25)).Magnitude).toBeLessThan(1e-9)
		-- A dash forward: the pivot trails 4 behind, held to 2.5.
		local trailed = v3(CameraMath.leash({ 0, 3, -4 }, { 0, 3, 0 }, forward, 0.75, 2.5))
		expect((trailed - Vector3.new(0, 3, -1.5)).Magnitude).toBeLessThan(1e-9)
		-- Inside the leash nothing moves.
		local inside = v3(CameraMath.leash({ 0, 3, 0 }, { 0.5, 3, -0.5 }, forward, 0.75, 2.5))
		expect((inside - Vector3.new(0.5, 3, -0.5)).Magnitude).toBeLessThan(1e-9)
	end)

	it("leashes the lagged pivot across the view too when given a side (D-181)", function()
		local forward = { 0, 0, -1 } -- the view's flat right is +X
		-- A dodge left: the lagged pivot 3 studs right of the body (and 0.5 behind), held to 1.
		local held = v3(CameraMath.leash({ -3, 3, 0 }, { 0, 3.5, 0.5 }, forward, 0.75, 2.5, 1))
		expect((held - Vector3.new(-2, 3.5, 0.5)).Magnitude).toBeLessThan(1e-9)
		local right = v3(CameraMath.leash({ 3, 3, 0 }, { 0, 3, 0 }, forward, 0.75, 2.5, 1))
		expect((right - Vector3.new(2, 3, 0)).Magnitude).toBeLessThan(1e-9)
		-- Both ways at once on a turned view: along and across are clamped on their own axes.
		local yaw = math.rad(30)
		local turned = { -math.sin(yaw), 0, -math.cos(yaw) }
		local along, across = Vector3.new(turned[1], 0, turned[3]), Vector3.new(-turned[3], 0, turned[1])
		local trailing = across * 4 - along * 5
		local both = v3(CameraMath.leash({ 0, 0, 0 }, { trailing.X, 0, trailing.Z }, turned, 0.75, 2.5, 1))
		expect(both:Dot(across)).toBeCloseTo(1, 1e-9)
		expect(both:Dot(along)).toBeCloseTo(-2.5, 1e-9)
		-- Inside the side leash nothing moves; without a side the sideways lag is left alone.
		local inside = v3(CameraMath.leash({ 0, 3, 0 }, { 0.9, 3, -0.5 }, forward, 0.75, 2.5, 1))
		expect((inside - Vector3.new(0.9, 3, -0.5)).Magnitude).toBeLessThan(1e-9)
		local free = v3(CameraMath.leash({ -3, 3, 0 }, { 0, 3, 0 }, forward, 0.75, 2.5))
		expect((free - Vector3.new(0, 3, 0)).Magnitude).toBeLessThan(1e-9)
	end)

	it("never clips a hit's nudge with the side leash (D-181)", function()
		local side = camera.follow.leash.side
		expect(typeof(side)).toBe("number")
		expect(side).toBeGreaterThanOrEqual(camera.nudge.studs)
		expect(camera.follow.leash.closer).toBeGreaterThanOrEqual(camera.nudge.studs)
	end)

	it("lets only opaque world parts block the view, never characters or accessories", function()
		local seeThrough = camera.collision.seeThrough
		expect(CameraMath.blocksView(0, seeThrough, false, false)).toBe(true)
		expect(CameraMath.blocksView(0, seeThrough, true, false)).toBe(false)
		expect(CameraMath.blocksView(0, seeThrough, false, true)).toBe(false)
		expect(CameraMath.blocksView(seeThrough, seeThrough, false, false)).toBe(false)
		expect(CameraMath.blocksView(1, seeThrough, false, false)).toBe(false)
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

describe("camera validator: punch and render stalls", function()
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

	-- The springs CameraController steps, with the damping it gives each.
	local springs = {
		{ name = "follow", lag = camera.follow.lag, damping = camera.follow.damping },
		{ name = "fov", lag = camera.fov.lag, damping = camera.fov.damping },
		{ name = "lock yaw", lag = camera.lock.yawLag, damping = camera.follow.damping },
		{ name = "lock blend", lag = camera.lock.blendLag, damping = camera.follow.damping },
		{ name = "collision pull-out", lag = camera.collision.pullOutLag, damping = camera.follow.damping },
	}

	it("keeps every camera spring from ringing at the longest piece a stalled frame is cut into", function()
		for _, row in springs do
			local spring = Spring.new(1, CameraMath.springFromLag(row.lag), row.damping)
			spring.target = 0
			local previous = 1
			simulate(spring, 3, camera.stall.maxStepSeconds, function(position)
				expect(position).toBeGreaterThanOrEqual(-1e-9) -- never past its target
				expect(position).toBeLessThanOrEqual(previous + 1e-9)
				previous = position
			end)
			expect(math.abs(spring.position)).toBeLessThan(0.01)
		end
		-- One quarter-second piece throws the stiffest spring past its target: why the gap is cut up.
		local fov = Spring.new(1, CameraMath.springFromLag(camera.fov.lag), camera.fov.damping)
		fov.target = 0
		fov:Step(0.25)
		expect(fov.position).toBeLessThan(-1)
	end)

	it("rejects a leash that clips the nudge and broken two-shot and probe numbers", function()
		local problems = runValidator(function(copy)
			copy.follow = deepCopy(camera.follow)
			copy.follow.leash.closer = camera.nudge.studs / 2
			copy.lock = deepCopy(camera.lock)
			copy.lock.maxOrbitDegrees = 120
			copy.lock.playerClearance = 0
			copy.lock.height = -1
			copy.lock.solveSteps = 2.5
			copy.lock.blendLag = 0
			copy.collision = deepCopy(camera.collision)
			copy.collision.seeThrough = 1.5
			copy.collision.maxPasses = 0
		end)
		expect(mentions(problems, "must be at least nudge.studs")).toBe(true)
		expect(mentions(problems, "lock.maxOrbitDegrees must be in (0, 90]")).toBe(true)
		expect(mentions(problems, "lock.playerClearance and lock.targetClearance must be positive")).toBe(true)
		expect(mentions(problems, "lock.height must be a positive number")).toBe(true)
		expect(mentions(problems, "lock.solveSteps must be a whole number")).toBe(true)
		expect(mentions(problems, "lock.blendLag must be a positive number")).toBe(true)
		expect(mentions(problems, "collision.seeThrough must be in (0, 1]")).toBe(true)
		expect(mentions(problems, "collision.maxPasses must be a whole number")).toBe(true)
		local hysteresis = runValidator(function(copy)
			copy.lock = deepCopy(camera.lock)
			copy.lock.sideHysteresis = camera.lock.maxOrbitDegrees
		end)
		expect(mentions(hysteresis, "lock.sideHysteresis must be in [0, maxOrbitDegrees)")).toBe(true)
		local missing = runValidator(function(copy)
			copy.follow = deepCopy(camera.follow)
			copy.follow.leash = nil
		end)
		expect(mentions(missing, "follow.leash is missing")).toBe(true)
	end)

	it("is clean on the real stall numbers and wants both of them", function()
		expect(mentions(runValidator(), "stall")).toBe(false)
		local missing = runValidator(function(copy)
			copy.stall = nil
		end)
		expect(mentions(missing, "stall is missing")).toBe(true)
		local broken = runValidator(function(copy)
			copy.stall = { maxStepSeconds = 0, settleSeconds = "2" }
		end)
		expect(mentions(broken, "stall.maxStepSeconds must be a positive number")).toBe(true)
		expect(mentions(broken, "stall.settleSeconds must be a positive number")).toBe(true)
	end)

	it("rejects a piece too long for the stiffest spring and one shorter than a frame", function()
		local long = runValidator(function(copy)
			copy.stall = { maxStepSeconds = 0.05, settleSeconds = camera.stall.settleSeconds }
		end)
		expect(mentions(long, "stall.maxStepSeconds 0.0500 s is too long a piece for the fov spring")).toBe(true)
		expect(mentions(long, "for the follow spring")).toBe(false)
		local short = runValidator(function(copy)
			copy.stall = { maxStepSeconds = 1 / 120, settleSeconds = camera.stall.settleSeconds }
		end)
		expect(mentions(short, "stall.maxStepSeconds 0.0083 s must be at least one 60 fps frame")).toBe(true)
	end)

	it(
		"rejects a settle that snaps a spring still on its way and one that cuts a frame into too many pieces",
		function()
			local soon = runValidator(function(copy)
				copy.stall = { maxStepSeconds = camera.stall.maxStepSeconds, settleSeconds = 1.6 }
			end)
			-- The 0.25 s pull-out is 1.2% off at 1.6 s; the 0.2 s lock yaw is inside half a percent.
			expect(mentions(soon, "stall.settleSeconds 1.60 s is too soon for the collision pull-out spring")).toBe(
				true
			)
			expect(mentions(soon, "too soon for the lock yaw spring")).toBe(false)
			local late = runValidator(function(copy)
				copy.stall = { maxStepSeconds = camera.stall.maxStepSeconds, settleSeconds = 10 }
			end)
			expect(mentions(late, "stall.settleSeconds 10.00 s cuts one frame into 300 pieces")).toBe(true)
		end
	)
end)

-- ------------------------------------------------------------------------------------------
-- Close fights, the bearing's turn rate, the aim's depth and the lock's stick (F3, issue 12)
-- ------------------------------------------------------------------------------------------

describe("CameraMath close fights", function()
	it("eases the close weight from toe to toe out to apart, with no kink at either end", function()
		expect(CameraMath.closeness(0, 1.5, 4.5)).toBe(1)
		expect(CameraMath.closeness(1.5, 1.5, 4.5)).toBe(1)
		expect(CameraMath.closeness(4.5, 1.5, 4.5)).toBe(0)
		expect(CameraMath.closeness(9, 1.5, 4.5)).toBe(0)
		expect(CameraMath.closeness(3, 1.5, 4.5)).toBeCloseTo(0.5, 1e-9)
		local previous = 1
		for gap = 1.5, 4.5, 0.1 do
			local weight = CameraMath.closeness(gap, 1.5, 4.5)
			expect(weight).toBeLessThanOrEqual(previous + 1e-12)
			previous = weight
		end
		-- Flat at both ends: a step of a hundredth moves it by well under a hundredth.
		expect(1 - CameraMath.closeness(1.51, 1.5, 4.5)).toBeLessThan(1e-3)
		expect(CameraMath.closeness(4.49, 1.5, 4.5)).toBeLessThan(1e-3)
	end)

	it("measures the flat gap from a point to a footprint box", function()
		expect(CameraMath.footprintGap(0, 0, 1.3, 4)).toBe(0)
		expect(CameraMath.footprintGap(3.3, 0, 1.3, 4)).toBeCloseTo(2, 1e-9)
		expect(CameraMath.footprintGap(0, -6, 1.3, 4)).toBeCloseTo(2, 1e-9)
		expect(CameraMath.footprintGap(-4.3, 8, 1.3, 4)).toBeCloseTo(5, 1e-9)
	end)

	it("swings a close fight to at least its three-quarter angle, and only a close one", function()
		local params = camera.lock
		expect(typeof(params.closeSwingDegrees)).toBe("number")
		for _, separation in { 0.5, 1, 1.5, 2, 2.5, 3 } do
			local open = CameraMath.twoShot({ 0, 3, 0 }, { 0, 3, -separation }, params)
			local close = CameraMath.twoShot({ 0, 3, 0 }, { 0, 3, -separation }, params, nil, 1)
			expect(open.closeness).toBe(0)
			expect(close.closeness).toBe(1)
			expect(close.swing).toBeGreaterThanOrEqual(params.closeSwingDegrees :: number)
			expect(close.swing).toBeGreaterThanOrEqual(open.swing)
			expect(close.distance).toBe(open.distance)
			local half = CameraMath.twoShot({ 0, 3, 0 }, { 0, 3, -separation }, params, nil, 0.5)
			expect(half.swing).toBeGreaterThanOrEqual((params.closeSwingDegrees :: number) / 2 - 1e-9)
		end
		-- Apart, a closeness of 0 leaves the solved swing as it was.
		local apart = CameraMath.twoShot({ 0, 3, 0 }, { 0, 3, -10 }, params, nil, 0)
		local plain = CameraMath.twoShot({ 0, 3, 0 }, { 0, 3, -10 }, params)
		expect(apart.swing).toBe(plain.swing)
	end)

	it("caps a whip's turn rate and leaves an ordinary ease alone", function()
		-- A spring that moved 10 degrees in a 60 fps frame at 600 deg/s: held to 150 deg/s.
		local position, velocity = CameraMath.capTurn(20, 30, 600, 150, 1 / 60)
		expect(position).toBeCloseTo(22.5, 1e-9)
		expect(velocity).toBe(150)
		local back, backVelocity = CameraMath.capTurn(20, 10, -600, 150, 1 / 60)
		expect(back).toBeCloseTo(17.5, 1e-9)
		expect(backVelocity).toBe(-150)
		local calm, calmVelocity = CameraMath.capTurn(20, 21, 60, 150, 1 / 60)
		expect(calm).toBe(21)
		expect(calmVelocity).toBe(60)
	end)

	it("holds the aim out at the player's depth when the target runs to the camera's side", function()
		-- The camera 10 studs behind the player (+Z), the target ran past to 3 studs from the lens.
		local cameraAt, player = { 0, 6.7, 10 }, { 0, 3, 0 }
		local aim = v3(CameraMath.holdAimDepth(cameraAt, player, { 2, 4.3, 5 }, 1))
		expect(aim.Z).toBeCloseTo(0, 1e-6)
		expect(aim.X).toBeCloseTo(2, 1e-6)
		expect(aim.Y).toBeCloseTo(4.3, 1e-6)
		-- An aim already past the player stays where it is.
		local ahead = v3(CameraMath.holdAimDepth(cameraAt, player, { 1, 4.3, -3 }, 1))
		expect((ahead - Vector3.new(1, 4.3, -3)).Magnitude).toBeLessThan(1e-6)
		-- The look down onto the held aim is the shallow one the player's depth gives.
		local look = (aim - v3(cameraAt)).Unit
		expect(math.deg(math.asin(-look.Y))).toBeLessThan(20)
	end)

	it("reads the stick in the lock's frame: forward walks at the target wherever the camera looks", function()
		-- The camera looks 50 degrees off the line to a target straight down -Z.
		local yaw = math.rad(50)
		local view = { -math.sin(yaw), -0.2, -math.cos(yaw) }
		local line = { 0, 0, -4 }
		-- W: the engine's forward is the camera's flat look.
		local forward = v3(CameraMath.lockMove({ view[1], 0, view[3] }, view, line))
		expect((forward.Unit - Vector3.new(0, 0, -1)).Magnitude).toBeLessThan(1e-9)
		-- D: the camera's flat right turns to the line's right (+X for a line down -Z).
		local right = v3(CameraMath.lockMove({ math.cos(yaw), 0, -math.sin(yaw) }, view, line))
		expect((right - Vector3.new(1, 0, 0)).Magnitude).toBeLessThan(1e-9)
		-- S walks straight away, and the stick's length is kept.
		local back = v3(CameraMath.lockMove({ math.sin(yaw) * 0.5, 0, math.cos(yaw) * 0.5 }, view, line))
		expect((back - Vector3.new(0, 0, 0.5)).Magnitude).toBeLessThan(1e-9)
		-- No line (the target on the player) or no flat view: unchanged.
		local same = v3(CameraMath.lockMove({ 1, 0, 0 }, view, { 0, 2, 0 }))
		expect((same - Vector3.new(1, 0, 0)).Magnitude).toBeLessThan(1e-9)
		local up = v3(CameraMath.lockMove({ 1, 0, 0 }, { 0, -1, 0 }, line))
		expect((up - Vector3.new(1, 0, 0)).Magnitude).toBeLessThan(1e-9)
	end)
end)
