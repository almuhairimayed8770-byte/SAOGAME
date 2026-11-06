--!strict
--[[
	EvenRoot: the root an enemy's body is drawn on while it walks or turns, rebuilt from the
	replicated root at the pace and the yaw rate the replicated root keeps (D-664; Studio items
	557 and 558, G2g's open issue 1).

	The screen draws the pose a rig's step writes on the root part where physics leaves it, and a
	client draws a replicated root unevenly from row to row: on the owner's PC the client rows' yaw
	steps read 0.02 to 2.89 degrees at 60 fps where the server's read 1.67 to 1.90 (532(g) on
	3eee415), and its position steps likewise. The step cannot know that row's step when it writes
	the joints, so every planted foot moved by the row's deviation (Lune with the PC's yaw cycle:
	0.078 to 0.115 a 60 Hz row on the boar's turning rows, against 0.041 to 0.057 drawn evenly).

	So RigDriver draws the body itself, off the root's move at physics (Choreo's setBodyOffset with
	`at`, D-531's detach), on a root the step knows: this one. Each step reads the root as the last
	row left it and advances its own root by the replicated root's pace and yaw rate over the last
	rateSeconds (a window that spans the PC's 8-row yaw cycle at 60 fps), pulled toward a point
	lagSeconds of that pace behind the replicated root with a time constant of followSeconds.
	It never passes the replicated root along the way it goes, never steps back along it, and
	never stays more than maxLagStuds or maxLagDegrees behind it, so it stops where the
	replicated root stops, with no overshoot, and a row the replicated root jumps or stalls moves
	it only by followSeconds' share. Standing, it closes on the root and snaps there within
	settleStuds and settleDegrees. RigDriver draws the body on it standing too: the first row of a
	move or a turn is then drawn where the last stood, not where physics carried the root.
	A step longer than choreo.luau enemy.rush.teleportStuds is a placement: it starts afresh there.
	A fresh start handed the body someone else drew on the last row (a rush handing it back) starts
	at that body's flat place and yaw, no further than maxLagStuds and maxLagDegrees off, and closes
	on the replicated root from there: the hand-back never jumps.

		local even = EvenRoot.new()
		local drawnOn = EvenRoot.step(even, root.CFrame, dt) -- the root this row is drawn on
	EvenRoot.step(even, root.CFrame, dt, handed)        -- a fresh start where a rush drew the body
	EvenRoot.step(even, ahead, dt, nil, tuning)         -- another's numbers: the local fighter's
	                                                    -- (choreo.luau locomotion.stride.evenRoot,
	                                                    -- D-675), handed the root where its
	                                                    -- frame's physics is expected to take it
		EvenRoot.turnTo(even, crouch)                       -- a rush's crouch turned the body
		EvenRoot.reset(even)                                -- forget it (a rush has the body)

	Its height is the one it stood at while the replicated root sinks no more than sinkStuds
	below it (the server's root let go at a walk's start settles into its contact: 0.0016 on the
	PC's rows of 568(c), and the body drawn there stood its feet 0.0016 deeper, D-682), and
	followed past that: it is never under the replicated root nor more than sinkStuds over it, and
	it rises with it. Tuning with no sinkStuds (the local fighter's) keeps the root's own height.

	Pure: no instances, nothing but the CFrame it is handed. Pitch and roll are the replicated
	root's own.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)

local TIME_NOISE = 1e-9 -- unit: seconds, float noise in a sum of frame times
local STILL_SPEED = 1e-3 -- unit: studs a second, a windowed pace this low is standing
local STILL_TURN = 1e-3 -- unit: radians a second, a windowed yaw rate this low is not turning

export type State = {
	started: boolean,
	clock: number,
	times: { number },
	points: { Vector3 }, -- the replicated root's flat place at each time
	yaws: { number }, -- its yaw (radians, unwrapped) at each time
	rawYaw: number, -- its last yaw as read (radians, -pi .. pi)
	rootYaw: number, -- its last yaw, unwrapped
	at: Vector3, -- this root's flat place
	height: number, -- this root's height
	yaw: number, -- this root's yaw, unwrapped as rootYaw is
	pace: Vector3, -- the replicated root's flat pace over the window (studs a second)
	turn: number, -- its yaw rate over the window (radians a second)
}

-- The numbers a root is evened with (enemy.gait.evenRoot, or the local fighter's).
export type Tuning = {
	rateSeconds: number,
	followSeconds: number,
	lagSeconds: number,
	maxLagStuds: number,
	maxLagDegrees: number,
	settleStuds: number,
	settleDegrees: number,
	-- The most the replicated root may sink below the height this root holds (nil: none).
	sinkStuds: number?,
}

local EvenRoot = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function yawOf(frame: CFrame): number
	local look = frame.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

--- A root standing by: the first step starts it on the replicated root.
function EvenRoot.new(): State
	return {
		started = false,
		clock = 0,
		times = {},
		points = {},
		yaws = {},
		rawYaw = 0,
		rootYaw = 0,
		at = Vector3.zero,
		height = 0,
		yaw = 0,
		pace = Vector3.zero,
		turn = 0,
	}
end

--- Forgets everything: the next step starts on the replicated root as it then stands.
function EvenRoot.reset(state: State)
	state.started = false
	table.clear(state.times)
	table.clear(state.points)
	table.clear(state.yaws)
	state.pace = Vector3.zero
	state.turn = 0
end

-- Starts afresh on `root` (the first step, or a placement).
local function start(state: State, root: CFrame, raw: number)
	state.started = true
	table.clear(state.times)
	table.clear(state.points)
	table.clear(state.yaws)
	state.rawYaw = raw
	state.rootYaw = raw
	state.at = flat(root.Position)
	state.height = root.Position.Y
	state.yaw = raw
	state.pace = Vector3.zero
	state.turn = 0
end

-- The CFrame this root stands at: the replicated root's pitch and roll, this root's flat place,
-- height and yaw.
local function compose(state: State, root: CFrame): CFrame
	local turned = CFrame.Angles(0, state.yaw - state.rootYaw, 0) * root.Rotation
	return CFrame.new(state.at.X, state.height, state.at.Z) * turned
end

--- One step: `root` is the replicated root as the last row left it, `dt` this step's seconds, and
--- `handed` where someone else drew the body on the last row (a fresh start starts there).
--- Returns the root this step's row is drawn on. `own`: numbers in place of enemy.gait.evenRoot's
--- (the local fighter's, D-675).
function EvenRoot.step(state: State, root: CFrame, dt: number, handed: CFrame?, own: Tuning?): CFrame
	local tuning: Tuning = own or ChoreoData.enemy.gait.evenRoot
	local raw = yawOf(root)
	local here = flat(root.Position)
	if not state.started or (here - state.at).Magnitude > ChoreoData.enemy.rush.teleportStuds then
		start(state, root, raw)
		if handed ~= nil then
			local off = flat(handed.Position) - here
			if off.Magnitude > tuning.maxLagStuds then
				off = off.Unit * tuning.maxLagStuds
			end
			local most = math.rad(tuning.maxLagDegrees)
			state.at = here + off
			state.yaw = raw + math.clamp(wrap(yawOf(handed) - raw), -most, most)
		end
	else
		state.rootYaw += wrap(raw - state.rawYaw)
		state.rawYaw = raw
	end
	-- The height: held while the replicated root sinks within sinkStuds of it, never under it.
	local rootY = root.Position.Y
	state.height = math.clamp(state.height, rootY, rootY + (tuning.sinkStuds or 0))
	if not (dt > 0) then
		return compose(state, root)
	end
	-- The replicated root's pace and yaw rate over the last rateSeconds (all of it until that much
	-- has gone by): the oldest sample kept is the newest at or before the window's start.
	local times, points, yaws = state.times, state.points, state.yaws
	state.clock += dt
	table.insert(times, state.clock)
	table.insert(points, here)
	table.insert(yaws, state.rootYaw)
	local from = state.clock - tuning.rateSeconds + TIME_NOISE
	while #times > 2 and times[2] <= from do
		table.remove(times, 1)
		table.remove(points, 1)
		table.remove(yaws, 1)
	end
	local span = state.clock - times[1]
	local pace = if span > 0 then (here - points[1]) / span else Vector3.zero
	local turn = if span > 0 then (state.rootYaw - yaws[1]) / span else 0
	state.pace, state.turn = pace, turn
	local follow = 1 - math.exp(-dt / tuning.followSeconds)

	-- The flat place: on at the pace, pulled toward lagSeconds of the pace behind the root, never
	-- past the root along the way it goes nor back along it, never further off than maxLagStuds.
	local was = state.at
	local ahead = was + pace * dt
	local at = ahead + (here - pace * tuning.lagSeconds - ahead) * follow
	if pace.Magnitude > STILL_SPEED then
		local along = pace.Unit
		local past = (at - here):Dot(along)
		if past > 0 then
			at -= along * past
		end
		-- Back along the way only as far as the root (a root it had passed, turned round).
		local floor = math.min(0, (here - was):Dot(along))
		local back = (at - was):Dot(along)
		if back < floor then
			at -= along * (back - floor)
		end
	end
	local off = at - here
	if off.Magnitude > tuning.maxLagStuds then
		at = here + off.Unit * tuning.maxLagStuds
	end
	local placed = (at - here).Magnitude <= tuning.settleStuds
	state.at = if placed then here else at

	-- The yaw, by the same rules.
	local wasYaw = state.yaw
	local aheadYaw = wasYaw + turn * dt
	local yaw = aheadYaw + (state.rootYaw - turn * tuning.lagSeconds - aheadYaw) * follow
	if math.abs(turn) > STILL_TURN then
		local sense = if turn > 0 then 1 else -1
		yaw = sense * math.min(sense * yaw, sense * state.rootYaw)
		yaw = sense * math.max(sense * yaw, math.min(sense * wasYaw, sense * state.rootYaw))
	end
	local most = math.rad(tuning.maxLagDegrees)
	yaw = state.rootYaw + math.clamp(yaw - state.rootYaw, -most, most)
	local turned = math.abs(yaw - state.rootYaw) <= math.rad(tuning.settleDegrees)
	state.yaw = if turned then state.rootYaw else yaw

	return compose(state, root)
end

--- Takes the yaw a drawn body is turned to by someone else (a rush's crouch, on its root): this
--- root turns from there, so the body never pops when it hands back.
function EvenRoot.turnTo(state: State, drawn: CFrame)
	if state.started then
		state.yaw = state.rootYaw + wrap(yawOf(drawn) - state.rawYaw)
	end
end

return EvenRoot
