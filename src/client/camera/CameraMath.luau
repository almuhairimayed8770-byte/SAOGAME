--!strict
--[[
	CameraMath: the pure math under CameraController (section 10), on plain {x, y, z} tables so
	it runs in Lune. CameraController converts to Vector3 / CFrame at the edge.

	Conventions: yaw 0 puts the camera behind a rig that faces -Z (the camera sits at +Z and looks
	toward -Z); yaw increases counter-clockwise seen from above. Pitch is the camera's elevation
	above the focus in degrees (positive looks down). Every tunable comes in as a parameter from
	camera.luau; nothing here holds a number of its own.
]]

export type Vec = { number }

export type LockParams = {
	focusBias: number,
	baseDistance: number,
	minDistance: number,
	maxDistance: number,
	distancePerSeparation: number,
}

-- The FOV punch's numbers (camera.luau punch rows).
export type PunchParams = {
	degrees: number,
	attack: number,
	settle: number,
	damping: number,
	band: number,
}

export type LockFrame = {
	focus: Vec,
	yaw: number,
	distance: number,
	separation: number,
}

local CameraMath = {}

local HALF_TURN = 180 -- unit: degrees in a half turn
local FULL_TURN = 360 -- unit: degrees in a full turn

local function unpack3(v: Vec): (number, number, number)
	local x, y, z = table.unpack(v)
	return x, y, z
end

--- Spring stiffness (omega squared) whose time constant is `lag` seconds.
function CameraMath.springFromLag(lag: number): number
	local omega = 1 / lag
	return omega * omega
end

--- The velocity impulse that makes a critically damped spring peak `studs` away from rest.
function CameraMath.impulseForDisplacement(studs: number, stiffness: number): number
	-- A critically damped spring kicked with velocity v peaks at v / (omega * e).
	return studs * math.sqrt(stiffness) * math.exp(1)
end

--- Exponential decay of `value` by `rate` per second over `dt`; never linear.
function CameraMath.decay(value: number, rate: number, dt: number): number
	return value * math.exp(-rate * dt)
end

--- Noise-like shake offset at `time`: summed incommensurate sines per axis, scaled by `amplitude`.
function CameraMath.shakeOffset(time: number, amplitude: number, frequency: number, lanes: { { number } }): Vec
	local omega = 2 * math.pi * frequency
	local count = #lanes
	if count == 0 or amplitude <= 0 then
		return { 0, 0, 0 }
	end
	local result = {}
	for axis = 1, 3 do -- unit: three axes
		local total = 0
		for _, lane in lanes do
			local multiplier, phase = lane[1], lane[2]
			-- Each axis shifts the phase by its index so no two axes move in step.
			total += math.sin(omega * multiplier * time + phase * axis)
		end
		result[axis] = total / count * amplitude
	end
	return result
end

--- Camera position relative to the focus for an orbit (yaw and pitch in degrees).
function CameraMath.orbitOffset(
	yawDegrees: number,
	pitchDegrees: number,
	distance: number,
	height: number,
	side: number
): Vec
	local yaw = math.rad(yawDegrees)
	local pitch = math.rad(pitchDegrees)
	local cosPitch = math.cos(pitch)
	local backX, backY, backZ = math.sin(yaw) * cosPitch, math.sin(pitch), math.cos(yaw) * cosPitch
	local rightX, rightZ = math.cos(yaw), -math.sin(yaw)
	return {
		backX * distance + rightX * side,
		backY * distance + height,
		backZ * distance + rightZ * side,
	}
end

--- The yaw (degrees) at which a camera behind `from` looks toward `to`.
function CameraMath.yawTowards(from: Vec, to: Vec): number
	local fromX, _, fromZ = unpack3(from)
	local toX, _, toZ = unpack3(to)
	local dx, dz = toX - fromX, toZ - fromZ
	if dx == 0 and dz == 0 then
		return 0
	end
	return math.deg(math.atan2(-dx, -dz))
end

--- Signed shortest rotation (degrees) from `fromDegrees` to `toDegrees`, in (-180, 180].
function CameraMath.shortestDelta(fromDegrees: number, toDegrees: number): number
	local delta = (toDegrees - fromDegrees + HALF_TURN) % FULL_TURN - HALF_TURN
	if delta == -HALF_TURN then
		return HALF_TURN
	end
	return delta
end

--- Wraps an angle into [-180, 180).
function CameraMath.wrapDegrees(degrees: number): number
	return (degrees + HALF_TURN) % FULL_TURN - HALF_TURN
end

--- Applies a look delta (pixels or stick units) to yaw and pitch, clamping pitch.
function CameraMath.applyLook(
	yaw: number,
	pitch: number,
	dx: number,
	dy: number,
	degreesPerUnit: number,
	invertY: boolean,
	pitchMin: number,
	pitchMax: number
): (number, number)
	local newYaw = CameraMath.wrapDegrees(yaw - dx * degreesPerUnit)
	local sign = if invertY then -1 else 1
	local newPitch = math.clamp(pitch + dy * degreesPerUnit * sign, pitchMin, pitchMax)
	return newYaw, newPitch
end

--- Lock-on framing: a focus between the fighters, the yaw that puts the camera behind the player
--- looking at the target, and a distance that grows with their separation.
function CameraMath.lockFrame(player: Vec, target: Vec, params: LockParams): LockFrame
	local px, py, pz = unpack3(player)
	local tx, ty, tz = unpack3(target)
	local dx, dy, dz = tx - px, ty - py, tz - pz
	local separation = math.sqrt(dx * dx + dz * dz)
	local bias = params.focusBias
	local focus = { px + dx * bias, py + dy * bias, pz + dz * bias }
	local distance = math.clamp(
		params.baseDistance + separation * params.distancePerSeparation,
		params.minDistance,
		params.maxDistance
	)
	return {
		focus = focus,
		yaw = CameraMath.yawTowards(player, target),
		distance = distance,
		separation = separation,
	}
end

--- Distance the camera may sit at after a collision probe (nil hit = unobstructed).
function CameraMath.collisionDistance(
	desired: number,
	hitDistance: number?,
	probeRadius: number,
	minDistance: number
): number
	if hitDistance == nil then
		return desired
	end
	return math.max(math.min(desired, hitDistance - probeRadius), minDistance)
end

--- Which segment of a scripted shot list is playing at `elapsed`, and how far along it is.
function CameraMath.scriptedSample(count: number, duration: number, elapsed: number): (number, number)
	local segments = count - 1
	if segments < 1 or duration <= 0 then
		return 1, 0
	end
	local segmentTime = duration / segments
	local position = math.clamp(elapsed / segmentTime, 0, segments)
	local index = math.min(math.floor(position) + 1, segments)
	local alpha = math.clamp(position - (index - 1), 0, 1)
	return index, alpha
end

--- Lifts a point by `height` studs (the chest-height focus above a root part).
function CameraMath.raise(point: Vec, height: number): Vec
	local x, y, z = unpack3(point)
	return { x, y + height, z }
end

--- A blend weight that eases from 0 to 1 over `duration` with a sine curve (no linear tweens).
function CameraMath.easeBlend(elapsed: number, duration: number): number
	if duration <= 0 then
		return 1
	end
	local t = math.clamp(elapsed / duration, 0, 1)
	return -(math.cos(math.pi * t) - 1) / 2
end

--- A damped spring's unit step back: 1 at `elapsed` 0 with zero velocity, inside `band` of 0 by
--- `settle` seconds. Under-damped (`damping` < 1) it swings a little past 0 before it settles;
--- at or over 1 it is the critically damped curve. Never linear.
function CameraMath.springBack(elapsed: number, settle: number, damping: number, band: number): number
	if elapsed <= 0 then
		return 1
	end
	if damping >= 1 then
		-- (1 + x) e^-x = band has no closed form; three fixed-point steps of x = L + ln(1 + x)
		-- (L = -ln band) land within a tenth of a percent of it.
		local scaled = -math.log(band)
		local x = scaled + math.log(1 + scaled)
		x = scaled + math.log(1 + x)
		x = scaled + math.log(1 + x)
		local omega = x / settle
		return (1 + omega * elapsed) * math.exp(-omega * elapsed)
	end
	local omega = -math.log(band) / (damping * settle)
	local decay = damping * omega
	local damped = omega * math.sqrt(1 - damping * damping)
	local envelope = math.exp(-decay * elapsed)
	return envelope * (math.cos(damped * elapsed) + decay / damped * math.sin(damped * elapsed))
end

--- The FOV offset in degrees (negative narrows) `elapsed` seconds into a punch that starts from
--- `from` (the offset a punch already showing has, else 0): eased out to -degrees over `attack`,
--- arriving with zero slope, then sprung back to rest by `settle`. The second value is true once
--- the punch is over (the offset is then 0).
function CameraMath.punchOffset(elapsed: number, params: PunchParams, from: number?): (number, boolean)
	local start = from or 0
	local peak = -params.degrees
	if elapsed <= 0 then
		return start, false
	end
	if elapsed < params.attack then
		local remaining = 1 - elapsed / params.attack
		local eased = 1 - remaining * remaining -- QuadOut: the push is fastest at the start
		return start + (peak - start) * eased, false
	end
	local since = elapsed - params.attack
	if since >= params.settle then
		return 0, true
	end
	return peak * CameraMath.springBack(since, params.settle, params.damping, params.band), false
end

--- Seconds a punch lasts, push to settled.
function CameraMath.punchSeconds(params: PunchParams): number
	return params.attack + params.settle
end

return CameraMath
