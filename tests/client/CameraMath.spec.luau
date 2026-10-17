--!strict
local CameraMath = Harness.load("src/client/camera/CameraMath")
local Spring = Harness.load("src/shared/util/Spring")
local camera = Harness.load("src/shared/data/camera")

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
