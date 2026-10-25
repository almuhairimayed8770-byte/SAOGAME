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

-- A staged view (the capture's shots, F12; dev.luau capture.cameras): the camera stands
-- `distance` studs (flat) from the anchor and `height` above it, at a bearing `degrees` off the
-- reference (stageReference), and aims `lookHeight` above the point `focusBias` of the way from
-- the player to the target.
export type StageAnchor = "Player" | "Target" | "Middle"
export type StageReference = "Line" | "Facing" | "World"

export type StageView = {
	anchor: StageAnchor,
	reference: StageReference,
	degrees: number,
	distance: number,
	height: number,
	focusBias: number,
	lookHeight: number,
}

-- The lock-on two-shot's numbers (camera.luau lock). closeSwingDegrees is the close fight's
-- three-quarter swing (F3): a shot `closeness` 1 swings at least this far off the line.
export type TwoShotParams = {
	baseDistance: number,
	minDistance: number,
	maxDistance: number,
	distancePerSeparation: number,
	playerClearance: number,
	targetClearance: number,
	maxOrbitDegrees: number,
	solveSteps: number,
	closeSwingDegrees: number?,
}

-- The FOV punch's numbers (camera.luau punch rows).
export type PunchParams = {
	degrees: number,
	attack: number,
	settle: number,
	damping: number,
	band: number,
}

-- A lock-on two-shot: the camera sits `distance` studs (flat) from the player, swung `swing`
-- degrees off the line behind the player (lineYaw), so the two fighters stand apart on screen.
-- `closeness` is the close fight's weight it was solved with (0 apart, 1 toe to toe).
export type TwoShot = {
	lineYaw: number,
	swing: number,
	distance: number,
	separation: number,
	closeness: number,
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

--- Where the free camera aims, relative to the pivot: `side` studs to the right and `height` up,
--- so the player stands left of center and the camera's elevation is exactly its pitch (the
--- camera is orbitOffset with the same numbers: this point plus `distance` back along the orbit).
function CameraMath.shoulderLook(yawDegrees: number, height: number, side: number): Vec
	local yaw = math.rad(yawDegrees)
	return { math.cos(yaw) * side, height, -math.sin(yaw) * side }
end

--- The angle (degrees) between the two fighters seen from a camera `distance` studs behind the
--- first and swung `swingDegrees` off the line to the second, `separation` studs further on.
function CameraMath.splitAngle(distance: number, separation: number, swingDegrees: number): number
	local swing = math.rad(swingDegrees)
	return math.deg(swing - math.atan2(distance * math.sin(swing), separation + distance * math.cos(swing)))
end

-- The split a two-shot needs: half of each fighter's clearance, seen from the camera.
local function neededSplit(distance: number, separation: number, swingDegrees: number, params: TwoShotParams): number
	local swing = math.rad(swingDegrees)
	local toTarget =
		math.sqrt(distance * distance + separation * separation + 2 * distance * separation * math.cos(swing))
	return math.deg(math.atan(params.playerClearance / distance) + math.atan(params.targetClearance / toTarget))
end

--- How close a fight is, from the flat gap (studs) between the player and the target's body:
--- 1 at or under `close`, 0 at or past `open`, eased between (smoothstep), so the close shot comes
--- and goes without a kink.
function CameraMath.closeness(gap: number, close: number, open: number): number
	if gap <= close then
		return 1
	end
	if gap >= open then
		return 0
	end
	local t = (open - gap) / (open - close)
	return t * t * (3 - 2 * t) -- unit: smoothstep, 3t^2 - 2t^3
end

--- The flat distance from a point to a box's footprint, both in the box's own space: the point at
--- (x, z), the box `halfX` by `halfZ` around the origin (0 inside it).
function CameraMath.footprintGap(x: number, z: number, halfX: number, halfZ: number): number
	local dx = math.max(math.abs(x) - halfX, 0)
	local dz = math.max(math.abs(z) - halfZ, 0)
	return math.sqrt(dx * dx + dz * dz)
end

--- Lock-on two-shot: the line from the player to the target, the camera's flat distance from the
--- player (growing with their separation, times `scale` for mobile), and the smallest swing off
--- the line behind the player that puts the fighters side by side with their clearances apart
--- (at most maxOrbitDegrees; found by bisection, the split growing with the swing). A close fight
--- (`closeness` above 0, CameraMath.closeness) swings at least closeness x closeSwingDegrees: toe
--- to toe no swing stands the bodies apart, so the shot turns to a three-quarter view of both (F3).
function CameraMath.twoShot(
	player: Vec,
	target: Vec,
	params: TwoShotParams,
	scale: number?,
	closeness: number?
): TwoShot
	local px, _, pz = unpack3(player)
	local tx, _, tz = unpack3(target)
	local dx, dz = tx - px, tz - pz
	local separation = math.sqrt(dx * dx + dz * dz)
	local distance = math.clamp(
		params.baseDistance + separation * params.distancePerSeparation,
		params.minDistance,
		params.maxDistance
	) * (scale or 1)
	local function gap(swing: number): number
		return CameraMath.splitAngle(distance, separation, swing) - neededSplit(distance, separation, swing, params)
	end
	local low, high = 0, params.maxOrbitDegrees
	local swing = high
	if gap(low) >= 0 then
		swing = low
	elseif gap(high) >= 0 then
		for _ = 1, params.solveSteps do
			local middle = (low + high) / 2
			if gap(middle) >= 0 then
				high = middle
			else
				low = middle
			end
		end
		swing = high
	end
	local close = math.clamp(closeness or 0, 0, 1)
	swing = math.max(swing, close * (params.closeSwingDegrees or 0))
	return {
		lineYaw = CameraMath.yawTowards(player, target),
		swing = swing,
		distance = distance,
		separation = separation,
		closeness = close,
	}
end

--- A turn capped at `maxRate` degrees per second over `span` seconds: from `previous` (where the
--- angle was before the step) to `position` (where its spring put it), with the spring's
--- `velocity`. Returns the capped position and velocity; a turn under the cap is unchanged, so
--- only a whip is slowed, never an ordinary ease (issue 12, issue 22).
function CameraMath.capTurn(
	previous: number,
	position: number,
	velocity: number,
	maxRate: number,
	span: number
): (number, number)
	local most = math.max(maxRate, 0)
	local step = math.clamp(position - previous, -most * span, most * span)
	return previous + step, math.clamp(velocity, -most, most)
end

--- The two-shot's aim held out at depth: the flat view runs from the camera to the player, and an
--- aim whose depth along it is under `fraction` of the player's is pushed out along it to that
--- depth (only along the view, so its height and its side stay). A target that has run past the
--- player to the camera's side would otherwise pull the aim in under the lens: a look straight
--- down onto the player's head (issue 12).
function CameraMath.holdAimDepth(cameraAt: Vec, player: Vec, aim: Vec, fraction: number): Vec
	local cx, _, cz = unpack3(cameraAt)
	local px, _, pz = unpack3(player)
	local ax, ay, az = unpack3(aim)
	local vx, vz = px - cx, pz - cz
	local length = math.sqrt(vx * vx + vz * vz)
	if length <= 0 then
		return { ax, ay, az }
	end
	local ux, uz = vx / length, vz / length
	local depth = (ax - cx) * ux + (az - cz) * uz
	local least = length * fraction
	if depth >= least then
		return { ax, ay, az }
	end
	local push = least - depth
	return { ax + ux * push, ay, az + uz * push }
end

--- A move direction the engine read in the camera's flat frame (`view`, the camera's look), read
--- again in the lock's: turned by the yaw from the flat view to the flat `line` (player to target),
--- so forward walks at the target, back away from it and sideways around it, wherever the
--- two-shot stands. The length and the height are kept; with no flat view or line it is unchanged.
function CameraMath.lockMove(move: Vec, view: Vec, line: Vec): Vec
	local mx, my, mz = unpack3(move)
	local vx, _, vz = unpack3(view)
	local lx, _, lz = unpack3(line)
	if (vx == 0 and vz == 0) or (lx == 0 and lz == 0) then
		return { mx, my, mz }
	end
	-- The turn from the view's heading to the line's (yaw counter-clockwise from above, -Z = 0).
	local turn = math.atan2(-lx, -lz) - math.atan2(-vx, -vz)
	local c, s = math.cos(turn), math.sin(turn)
	-- Rotating (x, z) counter-clockwise from above by `turn` about +Y.
	return { mx * c + mz * s, my, -mx * s + mz * c }
end

--- The two-shot camera: `distance` studs (flat) from the player along the bearing (the yaw a
--- camera there would have looking at the player), `height` studs above the player's root.
function CameraMath.twoShotCamera(player: Vec, bearingDegrees: number, distance: number, height: number): Vec
	local px, py, pz = unpack3(player)
	local bearing = math.rad(bearingDegrees)
	return { px + math.sin(bearing) * distance, py + height, pz + math.cos(bearing) * distance }
end

--- The two-shot aim: `bias` of the way from the player's root to the target's, `height` above.
function CameraMath.twoShotLook(player: Vec, target: Vec, bias: number, height: number): Vec
	local px, py, pz = unpack3(player)
	local tx, ty, tz = unpack3(target)
	return { px + (tx - px) * bias, py + (ty - py) * bias + height, pz + (tz - pz) * bias }
end

--- A staged view's anchor (the capture's shots, F12): the player's root, the target's, or the
--- middle of the two; the player's alone when there is no target.
function CameraMath.stageAnchor(anchor: string, player: Vec, target: Vec?): Vec
	local px, py, pz = unpack3(player)
	if target == nil or anchor == "Player" then
		return { px, py, pz }
	end
	local tx, ty, tz = unpack3(target)
	if anchor == "Target" then
		return { tx, ty, tz }
	end
	return { (px + tx) / 2, (py + ty) / 2, (pz + tz) / 2 }
end

--- A staged view's reference bearing (degrees, as twoShotCamera reads a bearing): "Line", behind
--- the anchor on the line from the other fighter (the player's end of it for "Middle"); "Facing",
--- behind the anchor's flat `look`; "World", 0 (the anchor's +Z). Nil when the reference needs a
--- target or a look that is not there.
function CameraMath.stageReference(reference: string, anchor: string, player: Vec, target: Vec?, look: Vec?): number?
	if reference == "World" then
		return 0
	end
	if reference == "Facing" then
		if look == nil then
			return nil
		end
		local lx, _, lz = unpack3(look)
		if lx == 0 and lz == 0 then
			return nil
		end
		-- Behind a rig looking along (lx, lz) is the other way: a bearing b stands at (sin b, cos b).
		return math.deg(math.atan2(-lx, -lz))
	end
	if target == nil then
		return nil
	end
	if anchor == "Target" then
		return CameraMath.yawTowards(target, player)
	end
	return CameraMath.yawTowards(player, target)
end

--- Which side of the line the two-shot camera keeps (1 right of the player, -1 left), given the
--- side it has and where the camera is (degrees off the line, + = right): it changes sides only
--- once the camera is more than `hysteresis` degrees over on the other one.
function CameraMath.lockSide(current: number, offLine: number, hysteresis: number): number
	if current >= 0 then
		return if offLine < -hysteresis then -1 else 1
	end
	return if offLine > hysteresis then 1 else -1
end

--- The follow's leash: `trailing` (the lagged pivot) held within `closer` studs ahead of `focus`
--- (the camera nearer the subject) and `further` behind it, along the flat unit `forward` (the
--- view), and, when `side` is given, within `side` studs of it either way across the view (the
--- flat right of `forward`, D-181). Vertical lag is left alone.
function CameraMath.leash(focus: Vec, trailing: Vec, forward: Vec, closer: number, further: number, side: number?): Vec
	local fx, _, fz = unpack3(focus)
	local tx, ty, tz = unpack3(trailing)
	local ux, _, uz = unpack3(forward)
	local along = (tx - fx) * ux + (tz - fz) * uz
	local excess = along - math.clamp(along, -further, closer)
	local x, z = tx - ux * excess, tz - uz * excess
	if side ~= nil then
		-- The view's flat right is (-uz, ux): forward -Z gives right +X.
		local rx, rz = -uz, ux
		local across = (tx - fx) * rx + (tz - fz) * rz
		local wide = across - math.clamp(across, -side, side)
		x -= rx * wide
		z -= rz * wide
	end
	return { x, ty, z }
end

--- Whether a part the collision probe hit blocks the view: never part of a character (any model
--- holding a Humanoid: the player's own weapon, the lock target, other players) or an accessory,
--- and never a part at least `seeThrough` transparent.
function CameraMath.blocksView(
	transparency: number,
	seeThrough: number,
	inCharacter: boolean,
	inAccessory: boolean
): boolean
	return not inCharacter and not inAccessory and transparency < seeThrough
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
