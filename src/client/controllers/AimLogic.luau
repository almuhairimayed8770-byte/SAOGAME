--!strict
--[[
	AimLogic: the pure aim rules under CharacterController (D-112). Plain numbers only, so every rule
	runs in Lune; combat.luau `aim` holds the tunables.

	While a lock is held and the body is free (Idle, Guard, the held Art stance; not while the stick
	sprints, unless aim.lockFaceWhileSprinting), the body faces the target: it turns toward it at
	aim.lockTurnRate (turnStep) and the stick strafes at walk speed (moveSpeed). A basic swing or an
	Art release faces the rest of the way at once, but by at most aim.snapDegrees (requestTurn); with
	no lock the same snap aims at the best enemy in the assist cone around the body's look
	(assistPick, ranked by TargetRanking). The clip carries the body from there: no turning in Art,
	Basic, PostMotion, Dodge, Stagger, GuardBroken or Dead, past the snap's own whip (below).

	The server sweeps where the request faces and accepts a facing within deg(acos(1 -
	facingTolerance)) of the root it has seen (D-113), and that root is some way behind this client's.
	So the snap also keeps the facing within aim.snapDegrees + aim.replicationMarginDegrees of every
	yaw the body held in the last combat.lagAllowance (the yaw history), and never turns away from the
	target to do it. A request sent while the lock's own turn is still sweeping the body round
	(sendOffset) faces back toward where the body was a lag window ago, by just enough for the server
	to accept it: the swing comes out, swept between the two, rather than being refused.

	The snap's whip (item 102): the request faces the whole snap at once, but the body shows it over
	aim.snapTurnSeconds on aim.snapTurnEasing (newSnap, snapStep, snapLeft), a fast start that
	settles into the facing, so it reads as a turn and not a one-frame pop. A slowed capture
	stretches it with the clips (snapSeconds).

	Angles are degrees, signed positive to the left: the sign of a CFrame.Angles(0, yaw, 0) turn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Easing = require(ReplicatedStorage.Shared.util.Easing)
local ActionLogic = require(script.Parent.ActionLogic)
local TargetRanking = require(script.Parent.TargetRanking)

export type Config = {
	lockTurnRate: number,
	lockFaceWhileSprinting: boolean,
	snapDegrees: number,
	snapTurnSeconds: number,
	snapTurnEasing: string,
	replicationMarginDegrees: number,
	assistRange: number,
	assistConeDegrees: number,
	assistAngleWeightStuds: number,
	minFaceDistance: number,
}

-- An enemy as the assist sees it: flat studs from the body and the signed bearing from its look.
export type Bearing = { id: number, distance: number, bearing: number }

-- A snap the body is still showing: `turn` degrees (+ = left) from where it stood when the request
-- went at `startedAt`, over `seconds`, of which `applied` are already on the root.
export type Snap = { turn: number, applied: number, startedAt: number, seconds: number }

-- The root's yaw over the last lag window, unwrapped (a turn through the back keeps counting).
export type YawHistory = {
	times: { number },
	yaws: { number }, -- unwrapped degrees, the same order as times
	last: number?, -- the last yaw recorded, as given (wrapped)
	total: number, -- the last yaw recorded, unwrapped
}

local AimLogic = {}

-- The states in which the body turns to face a held lock.
local FACES_LOCK: { [ActionLogic.LocalState]: boolean } = {
	Idle = true,
	Guard = true,
	Holding = true,
}

local function wrap(degrees: number): number
	return (degrees + 180) % 360 - 180
end

--- True while the body turns to face a held lock: Idle, Guard and Holding, and not while sprinting
--- unless `config.lockFaceWhileSprinting`.
function AimLogic.facesLock(
	state: ActionLogic.LocalState,
	hasLock: boolean,
	sprinting: boolean,
	config: Config
): boolean
	if not hasLock or FACES_LOCK[state] ~= true then
		return false
	end
	return not sprinting or config.lockFaceWhileSprinting
end

--- Signed degrees (+ = left) from a look (x, z) to a direction (x, z); 0 for no direction.
function AimLogic.bearing(lookX: number, lookZ: number, toX: number, toZ: number): number
	return ActionLogic.turnAngle(lookX, lookZ, toX, toZ)
end

--- The bearing from a body at (fromX, fromZ) looking along (lookX, lookZ) to a point (toX, toZ), or
--- nil when the point is closer than `minDistance` (no direction to face).
function AimLogic.bearingTo(
	lookX: number,
	lookZ: number,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	minDistance: number
): number?
	local dx, dz = toX - fromX, toZ - fromZ
	if math.sqrt(dx * dx + dz * dz) < math.max(minDistance, 1e-6) then
		return nil
	end
	return AimLogic.bearing(lookX, lookZ, dx, dz)
end

--- The yaw of a look (x, z) in degrees: 0 along -Z, positive to the left.
function AimLogic.yawOf(lookX: number, lookZ: number): number
	return math.deg(math.atan2(-lookX, -lookZ))
end

--- One frame of the lock turn: `delta` clamped to the rate times the frame.
function AimLogic.turnStep(delta: number, rate: number, dt: number): number
	local most = rate * dt
	return math.clamp(delta, -most, most)
end

--- The snap: `delta` clamped to `most` either way.
function AimLogic.snap(delta: number, most: number): number
	return math.clamp(delta, -most, most)
end

--- How far a swing or a release turns the body toward a target `delta` degrees away: by at
--- most config.snapDegrees, toward the target only, and no farther than snapDegrees +
--- replicationMarginDegrees from any yaw the body held in the lag window (`lo` and `hi`, the window's
--- lowest and highest yaw from the current one, so lo <= 0 <= hi), which the server may still hold.
--- A body that turned too far in the window to snap without leaving that bound does not snap.
function AimLogic.requestTurn(delta: number, lo: number, hi: number, config: Config): number
	local most = config.snapDegrees
	local budget = most + config.replicationMarginDegrees
	if delta > 0 then
		return math.min(delta, math.max(0, math.min(most, lo + budget)))
	elseif delta < 0 then
		return math.max(delta, math.min(0, math.max(-most, hi - budget)))
	end
	return 0
end

--- The offset (degrees, + = left) from the body's look to the facing a request carries: 0 when the
--- look is within snapDegrees + replicationMarginDegrees of every yaw of the lag window (`lo` and
--- `hi` as in requestTurn), else the nearest offset that is, so a request sent mid-turn (the lock's
--- acquisition turn) faces where the server can accept instead of being refused. A window wider
--- than twice that bound gets its middle.
function AimLogic.sendOffset(lo: number, hi: number, config: Config): number
	local budget = config.snapDegrees + config.replicationMarginDegrees
	local low, high = hi - budget, lo + budget
	if low > high then
		return (lo + hi) / 2
	end
	return math.clamp(0, low, high)
end

--- How much of a `turn` (degrees) the body shows `elapsed` seconds into its whip of `seconds` on
--- the `easing` curve: none at the start, the whole turn from `seconds` on (at once when `seconds`
--- is 0 or less).
function AimLogic.snapShown(turn: number, elapsed: number, seconds: number, easing: string): number
	if seconds <= 0 or elapsed >= seconds then
		return turn
	end
	if elapsed <= 0 then
		return 0
	end
	return turn * Easing.evaluate(easing, elapsed / seconds)
end

--- A whip of `turn` degrees starting at `startedAt`, over `seconds`.
function AimLogic.newSnap(turn: number, startedAt: number, seconds: number): Snap
	return { turn = turn, applied = 0, startedAt = startedAt, seconds = seconds }
end

--- The degrees to turn the root now, at time `t`, to show the snap on its curve; records them as
--- applied. Taken twice at the same moment, the second hands out nothing.
function AimLogic.snapStep(snap: Snap, t: number, easing: string): number
	local shown = AimLogic.snapShown(snap.turn, t - snap.startedAt, snap.seconds, easing)
	local step = shown - snap.applied
	snap.applied = shown
	return step
end

--- The degrees of the snap the body has still to show (0 once it is over).
function AimLogic.snapLeft(snap: Snap): number
	return snap.turn - snap.applied
end

--- How long the whip takes at a capture's time scale (dev.luau timeScale, 1 in play): the clips
--- run `scale` times as fast, and so does the whip. A scale of 0 or less changes nothing.
function AimLogic.snapSeconds(config: Config, scale: number): number
	if scale <= 0 then
		return config.snapTurnSeconds
	end
	return config.snapTurnSeconds / scale
end

--- An empty yaw history.
function AimLogic.newHistory(): YawHistory
	return { times = {}, yaws = {}, last = nil, total = 0 }
end

--- Records the root's yaw (degrees, wrapped) at time `t` and forgets what is older than `window`,
--- keeping the one yaw that was in effect when the window began.
function AimLogic.record(history: YawHistory, t: number, yaw: number, window: number)
	local last = history.last
	history.total = if last == nil then yaw else history.total + wrap(yaw - last)
	history.last = yaw
	table.insert(history.times, t)
	table.insert(history.yaws, history.total)
	local times = history.times
	while #times >= 2 and times[2] <= t - window do
		table.remove(times, 1)
		table.remove(history.yaws, 1)
	end
end

--- The lowest and highest yaw of the history, from the latest one (0, 0 when empty).
function AimLogic.range(history: YawHistory): (number, number)
	local yaws = history.yaws
	local count = #yaws
	if count == 0 then
		return 0, 0
	end
	local latest = yaws[count]
	local lo, hi = 0, 0
	for index = 1, count do
		local offset = yaws[index] - latest
		lo = math.min(lo, offset)
		hi = math.max(hi, offset)
	end
	return lo, hi
end

--- The enemy the soft assist aims at with no lock: the best of `candidates` inside
--- config.assistRange and config.assistConeDegrees around the look, ranked by TargetRanking
--- (distance plus the angle priced at config.assistAngleWeightStuds a radian), or nil. One closer
--- than config.minFaceDistance gives no direction and is skipped.
function AimLogic.assistPick(candidates: { Bearing }, config: Config): Bearing?
	local ranking: { TargetRanking.Candidate } = {}
	for _, candidate in candidates do
		if candidate.distance >= config.minFaceDistance then
			table.insert(ranking, {
				id = candidate.id,
				distance = candidate.distance,
				angle = math.rad(math.abs(candidate.bearing)),
			})
		end
	end
	local best = TargetRanking.rank(ranking, {
		range = config.assistRange,
		coneDegrees = config.assistConeDegrees,
		angleWeightStuds = config.assistAngleWeightStuds,
	})[1]
	if best == nil then
		return nil
	end
	for _, candidate in candidates do
		if candidate.id == best.id then
			return candidate
		end
	end
	return nil
end

--- The Humanoid speed while the body faces its lock: no faster than a walk, so the strafe and the
--- back-walk the 8-direction walk set shows keep their feet (D-054); otherwise `speed` stands.
function AimLogic.moveSpeed(speed: number, facingLock: boolean, walk: number): number
	return if facingLock then math.min(speed, walk) else speed
end

return AimLogic
