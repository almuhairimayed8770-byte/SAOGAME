--!strict
--[[
	RushDraw: where a rushing enemy's body is drawn (D-171). Pure: it reads the CFrames it is
	handed and returns the one to draw; Replication feeds it and hands the offset to the animator
	(Choreo setBodyOffset).

	The server runs a Charger's rush on its own clock (Charger.luau, D-166): from the launch the body
	runs down the telegraphed line at the rush speed and the line resolves its hits by that clock,
	whatever the body does. The body the client sees is the replicated root, which physics
	replication draws 0.2 to 0.3 s late (0.5 s on the first move after a long stand): a snout that
	reaches a player a quarter second after the server's hit. So while the rush runs the body is
	drawn on the server's timeline instead, and the root keeps its physics and replicated place.

	The timeline (`distanceAt`): nothing before the launch; the rush speed until the attack's
	strike beat (the whole line resolved by then, D-166); then a skid that sheds that speed evenly
	over what is left of the run (reach + overshoot), so the body comes to rest where the server's
	body stands, the beat after it got there. A jam (RushEnded "Jammed") caps it at the distance the
	server's body is stuck at; an interrupt, a death or a stop at the distance it stopped at.

	The drawn body never jumps (data/choreo.luau enemy.rush):
	  Armed     before the launch: nothing is drawn (the body is on its root).
	  Run       from the launch: it starts where the root is drawn and closes on the timeline, each
	            frame moving the timeline's own travel give or take catchUpFraction of a frame's
	            travel at the rush speed (none on the launch frame), never backward. An offset off the line closes at that pace
	            too, and the facing turns onto the line at turnRate. It never moves where the world
	            would stop its root (`room`, the server's worldAhead cast): it stops there as at a jam.
	  Settle    the timeline is done: the body still closes on its end (never backward), and waits
	            until the root has come within settleStuds of where the server's body stopped (or
	            settleSeconds).
	  HandBack  it slides from where it stood onto the root over handBackSeconds, longer for a longer
	            way at the catch-up pace, on handBackEasing; then it is Done and drawn on its root.
	  Frozen    a death: the body stays where it was drawn (the death freeze and the shatter play
	            there); it never goes back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)
local AI = require(Shared.data.ai)
local Easing = require(Shared.util.Easing)

local TUNING = ChoreoData.enemy.rush

export type Phase = "Armed" | "Run" | "Settle" | "HandBack" | "Frozen" | "Done"

--- A rush's line and clock: RushStarted's, or the one a telegraph predicts.
export type Line = {
	origin: Vector3, -- the crouch point; only its X and Z are read
	direction: Vector3, -- along the line (flattened here)
	speed: number, -- studs a second
	length: number, -- studs the run covers (reach + overshoot)
	strike: number, -- seconds from the launch the full speed lasts (the attack's strike)
	startedAt: number, -- server time of the launch
}

--- How far the root's centre may move from `from` along `direction` before the world stops it,
--- when that is less than `distance`; nil when nothing stops it within `distance` (RushDraw.room).
export type Room = (from: CFrame, direction: Vector3, distance: number) -> number?

--- The engine's world cast (EnemyService's WorldCast): a box of `size` at `start` moved by
--- `vector`, colliding as `group` does and never with `exclude`; how far it travelled before it met
--- something, or nil, and the normal of the face it met (nil: a face named no way, taken for a wall).
export type WorldCast = (
	start: CFrame,
	size: Vector3,
	vector: Vector3,
	group: string,
	exclude: Instance
) -> (number?, Vector3?)

export type State = {
	line: Line,
	phase: Phase,
	limit: number?, -- the farthest down the line the body goes (a jam, a stop, the world)
	endsAt: number?, -- server time the run stopped early
	along: number, -- the drawn body's distance down the line
	lateral: Vector3, -- the drawn body's flat offset off the line
	facing: Vector3, -- the drawn body's flat look direction
	lastTime: number?, -- the server time of the last step
	settleAt: number?, -- when the run was over
	handFrom: CFrame?, -- where the hand-back started
	handAt: number,
	handSeconds: number,
	drawn: CFrame?, -- the CFrame last drawn (Frozen keeps it)
}

local RushDraw = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitFlat(v: Vector3, fallback: Vector3): Vector3
	local f = flat(v)
	if f.Magnitude < 1e-6 then
		return fallback
	end
	return f.Unit
end

--- True for an attack the client draws as a rush: a Charger's line (Charger.luau isRush).
function RushDraw.isRush(archetype: string?, attack: { arc: number, groundShape: string? }?): boolean
	if archetype ~= "Charger" or attack == nil then
		return false
	end
	return attack.arc == 0 or attack.groundShape == "Line"
end

--- The line a telegraph predicts for a Charger's attack: from its origin along its facing, at the
--- rush speed for reach + overshoot studs, launched `windUp` after the wind-up began.
function RushDraw.predict(
	attack: { reach: number, strike: number, windUp: number },
	windUpStart: number,
	origin: Vector3,
	facing: Vector3
): Line
	local speed = AI.rushSpeed(attack)
	return {
		origin = origin,
		direction = unitFlat(facing, Vector3.new(0, 0, -1)),
		speed = speed,
		length = attack.reach + AI.archetypes.Charger.overshoot,
		strike = attack.strike,
		startedAt = windUpStart + attack.windUp,
	}
end

--- Seconds after the launch the full speed ends and the skid begins.
local function cruiseSeconds(line: Line): number
	if line.speed <= 0 then
		return 0
	end
	return math.clamp(line.strike, 0, line.length / line.speed)
end

--- Seconds after the launch the timeline comes to rest (the skid's end).
function RushDraw.finishSeconds(line: Line): number
	if line.speed <= 0 then
		return 0
	end
	local cruise = cruiseSeconds(line)
	local rest = math.max(0, line.length - line.speed * cruise)
	return cruise + 2 * rest / line.speed
end

--- How far down the line the server's timeline has the body `t` seconds after the launch.
function RushDraw.distanceAt(line: Line, t: number): number
	if t <= 0 or line.speed <= 0 then
		return 0
	end
	local cruise = cruiseSeconds(line)
	if t <= cruise then
		return line.speed * t
	end
	local covered = line.speed * cruise
	local rest = math.max(0, line.length - covered)
	if rest <= 0 then
		return line.length
	end
	local skid = 2 * rest / line.speed
	local u = math.min(t - cruise, skid)
	return covered + line.speed * u - 0.5 * (line.speed / skid) * u * u
end

-- The timeline's distance at server time `now`, under a jam's or a stop's limit and frozen from
-- an early stop on.
local function goalAt(state: State, now: number): number
	local line = state.line
	local at = now
	local endsAt = state.endsAt
	if endsAt ~= nil then
		at = math.min(at, endsAt)
	end
	local d = RushDraw.distanceAt(line, at - line.startedAt)
	local limit = state.limit
	if limit ~= nil then
		d = math.min(d, limit)
	end
	return d
end

-- True once the timeline has nothing more to move at `now`.
local function runOver(state: State, now: number): boolean
	local line = state.line
	local endsAt = state.endsAt
	if endsAt ~= nil and now >= endsAt then
		return true
	end
	if now - line.startedAt >= RushDraw.finishSeconds(line) then
		return true
	end
	local limit = state.limit
	return limit ~= nil and RushDraw.distanceAt(line, now - line.startedAt) >= limit
end

--- A rush waiting for its launch on `line`.
function RushDraw.new(line: Line): State
	return {
		line = line,
		phase = "Armed",
		limit = nil,
		endsAt = nil,
		along = 0,
		lateral = Vector3.zero,
		facing = unitFlat(line.direction, Vector3.new(0, 0, -1)),
		lastTime = nil,
		settleAt = nil,
		handFrom = nil,
		handAt = 0,
		handSeconds = 0,
		drawn = nil,
	}
end

--- The server's own line and clock (RushStarted) replace the predicted ones. The drawn body keeps
--- its place in the world: what it now stands at on the new line is where it closes from. A limit
--- already set (the world, a halt: RushEnded never comes before its RushStarted) keeps its place
--- in the world too.
function RushDraw.retime(state: State, line: Line)
	local old = state.line
	local oldDirection = unitFlat(old.direction, Vector3.zAxis)
	local direction = unitFlat(line.direction, Vector3.zAxis)
	if state.phase == "Run" or state.phase == "Settle" then
		local world = flat(old.origin) + oldDirection * state.along + state.lateral
		local rel = world - flat(line.origin)
		state.along = rel:Dot(direction)
		state.lateral = rel - direction * state.along
	end
	local limit = state.limit
	if limit ~= nil then
		local stop = flat(old.origin) + oldDirection * limit
		state.limit = math.max(0, (stop - flat(line.origin)):Dot(direction))
	end
	state.line = line
	if state.phase == "Settle" and state.endsAt == nil then
		state.phase = "Run"
		state.settleAt = nil
	end
end

--- Moves a predicted launch by `seconds` (the server paused the wind-up). Only before the launch.
function RushDraw.delay(state: State, seconds: number)
	if state.phase ~= "Armed" then
		return
	end
	local line = state.line
	state.line = {
		origin = line.origin,
		direction = line.direction,
		speed = line.speed,
		length = line.length,
		strike = line.strike,
		startedAt = line.startedAt + seconds,
	}
end

--- The server's body is stuck `distance` down the line (RushEnded "Jammed"): the timeline goes no
--- further; the hits still run on the clock, so the clock does not stop.
function RushDraw.jam(state: State, distance: number)
	state.limit = math.min(state.limit or math.huge, math.max(0, distance))
end

--- The run stopped `distance` down the line at server time `at` (an interrupt, a death, a stop).
function RushDraw.stop(state: State, distance: number, at: number)
	RushDraw.jam(state, distance)
	state.endsAt = math.min(state.endsAt or math.huge, at)
end

--- The run stopped where the body is drawn now (a Stagger or a Break heard before its RushEnded).
function RushDraw.halt(state: State, now: number)
	if state.phase == "Run" or state.phase == "Settle" then
		state.limit = math.min(state.limit or math.huge, math.max(0, state.along))
		state.endsAt = math.min(state.endsAt or math.huge, now)
	end
end

--- The body stays where it is drawn for good (a death). False when nothing was drawn yet.
function RushDraw.freeze(state: State): boolean
	if state.drawn == nil or state.phase == "Done" or state.phase == "Armed" then
		state.phase = "Done"
		return false
	end
	state.phase = "Frozen"
	return true
end

--- True while the body is drawn away from its root (Run, Settle, HandBack or Frozen).
function RushDraw.drawing(state: State): boolean
	local phase = state.phase
	return phase == "Run" or phase == "Settle" or phase == "HandBack" or phase == "Frozen"
end

--- True while the server's clock still moves the body (Run, Settle): the server pauses nothing of
--- a launched rush, so neither does the client's clip.
function RushDraw.running(state: State): boolean
	return state.phase == "Run" or state.phase == "Settle"
end

-- The drawn CFrame from the line coordinates, at the root's height.
local function compose(state: State, root: CFrame): CFrame
	local line = state.line
	local direction = unitFlat(line.direction, Vector3.zAxis)
	local spot = flat(line.origin) + direction * state.along + state.lateral
	local position = Vector3.new(spot.X, root.Position.Y, spot.Z)
	return CFrame.lookAt(position, position + state.facing)
end

--- Whether a face the world cast met is ground the body climbs, not a wall (D-204): its normal is
--- within ai.luau collision.groundSlopeDegrees of straight up, as EnemyService.isGround rules on the
--- server. Nil (a face named no way) is a wall.
function RushDraw.isGround(normal: Vector3?): boolean
	if normal == nil or normal.Magnitude < 1e-6 then
		return false
	end
	return normal.Unit.Y >= math.cos(math.rad(AI.collision.groundSlopeDegrees))
end

--- How far a root of `size` at `from` may move along `direction` (flattened) before the world stops
--- it, when that is less than `distance`; nil when nothing does, or with no world to ask (`cast`
--- failed). The server's worldAhead cast (EnemyService, D-197) made from the drawn body: the root's
--- own box in the rushing group (the world only: a rush passes through players and enemies,
--- D-167), cast from where its front face stands at its centre, never against its own `exclude`.
--- Ground the root climbs is no stop (RushDraw.isGround, D-204): the drawn body stands at its
--- late root's height, below a rising ramp's surface ahead, so its box meets the ramp.
function RushDraw.room(
	from: CFrame,
	size: Vector3,
	direction: Vector3,
	distance: number,
	cast: WorldCast,
	exclude: Instance
): number?
	local f = flat(direction)
	if f.Magnitude < 1e-6 or not (distance > 0) then
		return nil
	end
	f = f.Unit
	local half = size / 2
	local reach = math.abs(from.RightVector:Dot(f)) * half.X
		+ math.abs(from.UpVector:Dot(f)) * half.Y
		+ math.abs(from.LookVector:Dot(f)) * half.Z
	local ok, travelled, normal =
		pcall(cast, from - f * reach, size, f * (distance + reach), AI.collision.rushing, exclude)
	if not ok or typeof(travelled) ~= "number" then
		return nil
	end
	if RushDraw.isGround(if typeof(normal) == "Vector3" then normal else nil) then
		return nil
	end
	return math.max(0, travelled - reach)
end

-- Turns `from` toward `to` (flat unit vectors) by at most `radians`.
local function turnToward(from: Vector3, to: Vector3, radians: number): Vector3
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= radians or angle < 1e-6 then
		return to
	end
	local cross = from:Cross(to).Y
	local sign = if cross >= 0 then 1 else -1
	return (CFrame.Angles(0, sign * radians, 0) * from).Unit
end

--- One frame: where to draw the root part at server time `now` (`dt` the frame's length) given
--- where its replicated root stands, or nil when the body is drawn on its root (before the launch,
--- and once Done). `room` asks the world how far the drawn body may move (nil: never stopped).
function RushDraw.step(state: State, now: number, dt: number, root: CFrame, room: Room?): CFrame?
	local line = state.line
	local phase = state.phase
	local launching = false
	if phase == "Done" then
		return nil
	elseif phase == "Frozen" then
		return state.drawn
	elseif phase == "Armed" then
		if now < line.startedAt then
			return nil
		end
		-- The launch: the body starts where the root is drawn, so nothing jumps.
		local direction = unitFlat(line.direction, Vector3.zAxis)
		local rel = flat(root.Position) - flat(line.origin)
		state.along = rel:Dot(direction)
		state.lateral = rel - direction * state.along
		state.facing = unitFlat(root.LookVector, direction)
		state.lastTime = math.max(line.startedAt, now - dt)
		state.phase = "Run"
		phase = "Run"
		launching = true
	end

	if phase == "Run" or phase == "Settle" then
		local last = state.lastTime or now
		local goal = goalAt(state, now)
		local natural = math.max(0, goal - goalAt(state, last))
		-- No catching up on the launch frame itself: its first move is never more than a frame of
		-- the run's own travel, however late the launch was heard.
		local slack = if launching then 0 else TUNING.catchUpFraction * line.speed * math.max(0, dt)
		local step = math.max(0, math.clamp(goal - state.along, natural - slack, natural + slack))
		if step > 0 and room ~= nil then
			-- The world stops the root short of the move: the body stops there, as at a jam.
			local free = room(compose(state, root), unitFlat(line.direction, Vector3.zAxis), step)
			if free ~= nil and free < step then
				step = math.max(0, free)
				RushDraw.jam(state, state.along + step)
				goal = math.min(goal, state.along + step)
			end
		end
		state.along += step
		local off = state.lateral.Magnitude
		if off > 1e-6 then
			state.lateral = state.lateral * (math.max(0, off - slack) / off)
		end
		local direction = unitFlat(line.direction, Vector3.zAxis)
		state.facing = turnToward(state.facing, direction, math.rad(TUNING.turnRate) * math.max(0, dt))
		state.lastTime = now
		if phase == "Run" and runOver(state, now) then
			state.phase = "Settle"
			state.settleAt = now
			phase = "Settle"
		end
		local drawn = compose(state, root)
		if phase == "Settle" then
			-- The root has come to where the server's body stopped (the run's end, or a jam's or a
			-- stop's limit), or it has had settleSeconds to.
			local stopped = flat(line.origin) + unitFlat(line.direction, Vector3.zAxis) * goal
			local arrived = (flat(root.Position) - stopped).Magnitude <= TUNING.settleStuds
			local waited = now - (state.settleAt or now) >= TUNING.settleSeconds
			if arrived or waited then
				local gap = (flat(root.Position) - flat(drawn.Position)).Magnitude
				state.phase = "HandBack"
				state.handFrom = drawn
				state.handAt = now
				local pace = math.max(TUNING.catchUpFraction * line.speed, 1e-6)
				state.handSeconds = math.max(TUNING.handBackSeconds, gap / pace)
			end
		end
		state.drawn = drawn
		return drawn
	end

	-- HandBack: from where it stood onto the root as the root stands now.
	local from = state.handFrom or root
	local u = if state.handSeconds > 0 then math.clamp((now - state.handAt) / state.handSeconds, 0, 1) else 1
	if u >= 1 then
		state.phase = "Done"
		state.drawn = nil
		return nil
	end
	local drawn = from:Lerp(root, Easing.evaluate(TUNING.handBackEasing, u))
	state.drawn = drawn
	return drawn
end

return RushDraw
