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

	The timeline (`distanceAt`, RushWorld's, which the server dazes a slammed body by): nothing
	before the launch; the rush speed until the attack's strike beat (the whole line resolved by
	then, D-166); then a skid that sheds that speed evenly over what is left of the run (reach +
	overshoot), so the body comes to rest where the server's body stands, the beat after it got
	there. A jam (RushEnded "Jammed") caps it at the distance the server's body is stuck at, a slam
	("Wall") at where its snout rests on the face; an interrupt, a death or a stop at the distance it
	stopped at. Every distance is down the rush's path (RushWorld.Leg): its line, then the bends a
	glancing wall and the sidesteps a clipped corner add (RushTurned, or this client's own cast).

	It meets the world as the server's body does (D-205 to D-209, choreo/RushWorld.luau, the same
	rules): its root's box is cast ahead of it along its leg from where it is drawn, as far as the
	server's cast looks, at the height of the ground under it, so it slams with its snout on a wall's
	face (not its root's box), bends along a glancing wall, sidesteps a clipped corner and runs over
	slopes and the steps the server's root climbs. A ground probe under the drawn spot sets its height
	(never the late root's, which stands lower on a rise and higher on a fall).

	The drawn body never jumps (data/choreo.luau enemy.rush):
	  Armed     before the launch: the body stands on its root, turned onto its line (D-255). The
	            server's body holds the line through the crouch while its late root may still show
	            the turn onto it; from the root's own look it turns at the chase's rate (ai.luau
	            Charger turnRate), faster when the time left needs it, never faster than turnRate,
	            so it is on the line by the launch and the launch turns nothing. A crouch that will
	            not launch (`release`) keeps its turn until the late root has come round to it, then
	            is on its root, or slides back onto it after settleSeconds.
	  Run       from the launch: it starts where the root is drawn and closes on the timeline, each
	            frame moving the timeline's own travel give or take catchUpFraction of a frame's
	            travel at the rush speed (none on the launch frame), never backward. An offset off
	            the path closes at that pace too, and the facing turns onto the leg's at turnRate. It
	            never moves where the world would stop its body (`room`, the server's worldAhead cast):
	            it stops there as at a jam, its snout on the face.
	  Settle    the timeline is done: the body still closes on its end (never backward), and waits
	            until the root has come within settleStuds of where the server's body stopped (the
	            last RushEnded's distance, else the run's end or limit), or settleSeconds.
	            Before any RushEnded, a late root come to rest well short of the drawn body (ai.luau
	            rushWorld rest*, D-256) is the server's body stuck there: a jam told early.
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
local RushWorld = require(Shared.choreo.RushWorld)

local TUNING = ChoreoData.enemy.rush
local WORLD = AI.rushWorld
local CHARGER = AI.archetypes.Charger

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
--- when that is less than `distance`, and the normal of the face that does (nil: named no way);
--- nil when nothing stops it within `distance` (RushDraw.room).
export type Room = (from: CFrame, direction: Vector3, distance: number) -> (number?, Vector3?)

--- The height of the ground under `spot`, looking down from `spot`'s height (RushDraw.ground); nil
--- when nothing is there.
export type Ground = (spot: Vector3) -> number?

--- A contact the drawn body reaches (a slam, a bend, a sidestep): its cue plays on the frame the
--- body gets `at` studs down its path (RushDraw.takeCues).
export type Cue = {
	kind: RushWorld.Kind,
	at: number,
	point: Vector3,
	normal: Vector3,
	played: boolean,
}

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
	legs: { RushWorld.Leg }, -- its path: the line, then its bends and sidesteps
	phase: Phase,
	limit: number?, -- the farthest down the path the body goes (a jam, a stop, the world)
	guess: number?, -- the limit this client's own cast set (a slam the server may turn instead)
	endsAt: number?, -- server time the run stopped early
	rest: number?, -- where down the path the server's body stopped (the last RushEnded)
	walled: boolean, -- a slam set the limit (this client's cast or the server's "Wall")
	along: number, -- the drawn body's distance down the path
	lateral: Vector3, -- the drawn body's flat offset off the path
	facing: Vector3, -- the drawn body's flat look direction
	height: number?, -- the drawn root's height (nil: the root's own)
	fall: number, -- studs a second the drawn body drops (onto lower ground)
	body: RushWorld.Body?, -- the body a wall is judged on (RushDraw.setBody)
	hover: number?, -- the root's centre above the ground under it
	cues: { Cue },
	lastTime: number?, -- the server time of the last step
	settleAt: number?, -- when the run was over
	handFrom: CFrame?, -- where the hand-back started
	handAt: number,
	handSeconds: number,
	drawn: CFrame?, -- the CFrame last drawn (Frozen keeps it)
	released: boolean, -- an Armed crouch that will not launch (RushDraw.release)
	restSpot: Vector3?, -- where the late root was last seen moving (flat), and when (D-256)
	restFrom: number?,
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

-- The flat point `along` studs down the path, plus the offset off it.
local function spotOf(state: State): Vector3
	return RushWorld.pointAt(state.legs, state.along) + state.lateral
end

-- Puts the drawn body's place in the world on `legs` (a new line, the server's bends): the nearest
-- point down them and the flat offset off it.
local function rebase(state: State, legs: { RushWorld.Leg })
	local world = spotOf(state)
	state.legs = legs
	state.along = RushWorld.project(legs, world)
	state.lateral = world - RushWorld.pointAt(legs, state.along)
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

--- How far down its path the server's timeline has the body `t` seconds after the launch (the
--- timeline the server dazes a slammed body by, RushWorld.distanceAt).
function RushDraw.distanceAt(line: Line, t: number): number
	return RushWorld.distanceAt(line.speed, line.length, line.strike, t)
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
	local legs = RushWorld.line(line.origin, line.direction)
	return {
		line = line,
		legs = legs,
		phase = "Armed",
		limit = nil,
		guess = nil,
		endsAt = nil,
		rest = nil,
		walled = false,
		along = 0,
		lateral = Vector3.zero,
		facing = unitFlat(line.direction, Vector3.new(0, 0, -1)),
		height = nil,
		fall = 0,
		body = nil,
		hover = nil,
		cues = {},
		lastTime = nil,
		settleAt = nil,
		handFrom = nil,
		handAt = 0,
		handSeconds = 0,
		drawn = nil,
		released = false,
		restSpot = nil,
		restFrom = nil,
	}
end

--- The server's own line and clock (RushStarted) replace the predicted ones. The drawn body keeps
--- its place in the world: what it now stands at on the new line is where it closes from. A limit
--- already set (the world, a halt: RushEnded never comes before its RushStarted) keeps its place
--- in the world too.
function RushDraw.retime(state: State, line: Line)
	local oldLegs = state.legs
	local legs = RushWorld.line(line.origin, line.direction)
	if RushWorld.sameLegs({ oldLegs[1] }, legs) then
		-- The line the telegraph predicted: the path this client already found on it (its bends and
		-- sidesteps) and its limit stand; only the clock is the server's.
		state.line = line
		if state.phase == "Settle" and state.endsAt == nil then
			state.phase = "Run"
			state.settleAt = nil
		end
		return
	end
	local direction = legs[1].heading
	if state.phase == "Run" or state.phase == "Settle" then
		local world = spotOf(state)
		local rel = world - legs[1].from
		state.along = rel:Dot(direction)
		state.lateral = rel - direction * state.along
	end
	local limit = state.limit
	if limit ~= nil then
		local stop = RushWorld.pointAt(oldLegs, limit)
		state.limit = math.max(0, (stop - legs[1].from):Dot(direction))
		state.guess = if state.guess ~= nil then state.limit else nil
	end
	state.legs = legs
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

-- Drops the slam this client's own cast guessed (its limit, its cue not yet played): the server's
-- word says otherwise.
local function unguess(state: State)
	local guess = state.guess
	if guess == nil then
		return
	end
	state.guess = nil
	if state.limit == guess then
		state.limit = nil
		state.walled = false
	end
	for index = #state.cues, 1, -1 do
		local entry = state.cues[index]
		if entry.kind == "Slam" and not entry.played then
			table.remove(state.cues, index)
		end
	end
end

-- The limit the server tells (a jam, a slam, a stop): a nearer one stands (this client's own wall
-- is never run past). Down the path this client draws: the server's own, its RushTurned legs and
-- the bends this client's cast found the same (a lost RushTurned costs nothing).
local function told(state: State, distance: number)
	state.limit = math.min(state.limit or math.huge, math.max(0, distance))
end

--- The server's body is stuck `distance` down its path (RushEnded "Jammed"): the timeline goes no
--- further; the hits still run on the clock, so the clock does not stop.
function RushDraw.jam(state: State, distance: number)
	told(state, distance)
end

--- The run stopped `distance` down its path at server time `at` (an interrupt, a death, a stop).
function RushDraw.stop(state: State, distance: number, at: number)
	told(state, distance)
	state.endsAt = math.min(state.endsAt or math.huge, at)
end

--- Where down its path the server's body stopped (a RushEnded's distance, D-210): the hand-back
--- waits for the root to get there, not to where the body is drawn.
function RushDraw.rest(state: State, distance: number)
	state.rest = math.max(0, distance)
end

-- Adds the cue for a contact `at` studs down the path, or moves the one of its kind already there
-- (the server's word replaces this client's own guess at the same contact).
local function cue(state: State, kind: RushWorld.Kind, at: number, point: Vector3, normal: Vector3)
	for _, existing in state.cues do
		if existing.kind == kind and math.abs(existing.at - at) <= WORLD.clipRunStuds then
			if not existing.played then
				existing.at = at
				existing.point = point
				existing.normal = normal
			end
			return
		end
	end
	table.insert(state.cues, { kind = kind, at = at, point = point, normal = normal, played = false })
end

--- A slam (RushEnded "Wall", or this client's `own` cast): the body goes no further than `distance`
--- down its path, where its snout rests on the face at `point` (normal `normal`), and its cue plays
--- when it gets there (D-208). No cast looks further. The server's cue replaces this client's own.
function RushDraw.wall(state: State, distance: number, point: Vector3?, normal: Vector3?, own: boolean?)
	if own == true then
		local limit = math.max(0, distance)
		if state.limit == nil or limit < (state.limit :: number) then
			state.limit = limit
			state.guess = limit
		end
	else
		told(state, distance)
	end
	state.walled = true
	local stop = state.limit or distance
	local direction = RushWorld.pointAt(state.legs, stop + 1) - RushWorld.pointAt(state.legs, stop)
	cue(state, "Slam", stop, point or RushWorld.pointAt(state.legs, stop), normal or -direction)
end

--- The server's path (RushTurned: a glance's bend, a clip's sidestep, D-206, D-207): the body is
--- drawn on these legs from now on, keeping its place in the world (an offset closes as any other),
--- and the contact's cue plays when it gets `at` studs down them.
function RushDraw.turn(
	state: State,
	legs: { RushWorld.Leg },
	kind: RushWorld.Kind,
	at: number,
	point: Vector3,
	normal: Vector3
)
	if #legs == 0 then
		return
	end
	-- A slam this client guessed where the server turns is no slam.
	unguess(state)
	local limit = state.limit
	local stop = if limit ~= nil then RushWorld.pointAt(state.legs, limit) else nil
	if state.phase == "Run" or state.phase == "Settle" then
		rebase(state, legs)
	else
		state.legs = legs
	end
	if stop ~= nil then
		state.limit = RushWorld.project(legs, stop)
	end
	cue(state, kind, at, point, normal)
end

--- The body the drawn rush is judged on against the world (D-205): its corners at rest and its
--- root's size (RushWorld.profileOf), and how high its root's centre stands above the ground under
--- it (the Humanoid's HipHeight plus half the root's height). Without it the drawn rush stops with
--- its root's box at a wall and stands at its root's height.
function RushDraw.setBody(state: State, body: RushWorld.Body?, hover: number?)
	state.body = body
	state.hover = hover
end

--- The cues the drawn body reached since the last call, oldest first (each once): a slam's on the
--- frame its snout rests on the face, a bend's or a sidestep's as it passes it. Reached is within
--- RushWorld.SAME_STUDS: the server's stop and this client's own agree to about that.
function RushDraw.takeCues(state: State): { Cue }
	local due: { Cue } = {}
	for _, entry in state.cues do
		if not entry.played and state.along >= entry.at - RushWorld.SAME_STUDS then
			entry.played = true
			table.insert(due, entry)
		end
	end
	return due
end

--- The run stopped where the body is drawn now (a Stagger or a Break heard before its RushEnded).
--- Once a RushEnded has told where the server's body stops (a jam, a slam) the server tells this
--- stop too (D-210): a slam's daze is a Stagger on the frame the snout reaches the face, which a
--- client drawing a frame behind would otherwise hold a frame's travel short of it. That RushEnded is
--- unreliable: lost, or heard after the daze, a stop the timeline has brought the snout to a face
--- this client's own cast found by `now` is that slam's daze (D-218), so the body still goes onto the
--- face (its slam's cue plays there); any other stop holds it where it is drawn.
function RushDraw.halt(state: State, now: number)
	if state.rest ~= nil then
		return
	end
	if state.phase == "Run" or state.phase == "Settle" then
		local stop = math.max(0, state.along)
		local guess = state.guess
		if
			guess ~= nil
			and state.limit == guess
			and RushDraw.distanceAt(state.line, now - state.line.startedAt) >= guess - RushWorld.SAME_STUDS
		then
			stop = math.max(stop, guess)
		end
		state.limit = math.min(state.limit or math.huge, stop)
		state.endsAt = math.min(state.endsAt or math.huge, now)
	end
end

--- The body stays where it is drawn for good (a death), a crouch's turn too. False when nothing was
--- drawn yet.
function RushDraw.freeze(state: State): boolean
	if state.drawn == nil or state.phase == "Done" then
		state.phase = "Done"
		return false
	end
	state.phase = "Frozen"
	return true
end

-- Starts the slide from where the body is drawn onto the root, over at least handBackSeconds (more
-- for a longer way, at the catch-up pace).
local function handBack(state: State, drawn: CFrame, now: number, root: CFrame?)
	local gap = if root ~= nil then (flat(root.Position) - flat(drawn.Position)).Magnitude else 0
	state.phase = "HandBack"
	state.handFrom = drawn
	state.handAt = now
	local pace = math.max(TUNING.catchUpFraction * state.line.speed, 1e-6)
	state.handSeconds = math.max(TUNING.handBackSeconds, gap / pace)
end

--- The rush will not run as drawn: its wind-up was dropped or cut before the server launched it (a
--- hold, a sleep, a stagger heard before any RushStarted). A crouch's turn is kept until the late
--- root has come round to it (Armed, D-255); a launch this client predicted and drew slides back
--- onto the root (`root`, as it stands now). False when nothing is drawn: the body is on its root.
function RushDraw.release(state: State, now: number, root: CFrame?): boolean
	local drawn = state.drawn
	local phase = state.phase
	if phase == "Frozen" or phase == "HandBack" then
		return true
	end
	if drawn == nil or phase == "Done" then
		state.phase = "Done"
		return false
	end
	if phase == "Armed" then
		if not state.released then
			state.released = true
			state.settleAt = now
		end
		return true
	end
	handBack(state, drawn, now, root)
	return true
end

--- True while the body is drawn away from its root's place (Run, Settle, HandBack or Frozen; a
--- crouch's turn stands on its root).
function RushDraw.drawing(state: State): boolean
	local phase = state.phase
	return phase == "Run" or phase == "Settle" or phase == "HandBack" or phase == "Frozen"
end

--- True while the server's clock still moves the body (Run, Settle): the server pauses nothing of
--- a launched rush, so neither does the client's clip.
function RushDraw.running(state: State): boolean
	return state.phase == "Run" or state.phase == "Settle"
end

-- The drawn CFrame from the path coordinates, at the drawn height (the root's without one).
local function compose(state: State, root: CFrame): CFrame
	local spot = spotOf(state)
	local position = Vector3.new(spot.X, state.height or root.Position.Y, spot.Z)
	return CFrame.lookAt(position, position + state.facing)
end

--- Whether a face the world cast met is ground the body climbs, not a wall (D-204): its normal is
--- within ai.luau collision.groundSlopeDegrees of straight up. The one rule the server judges by too
--- (RushWorld.isGround, D-209). Nil (a face named no way) is a wall.
function RushDraw.isGround(normal: Vector3?): boolean
	return RushWorld.isGround(normal)
end

-- The engine's world cast bound to the rushing group and the body's own model (RushWorld.Cast).
local function bind(cast: WorldCast, exclude: Instance): RushWorld.Cast
	return function(start: CFrame, size: Vector3, vector: Vector3): (number?, Vector3?)
		return cast(start, size, vector, AI.collision.rushing, exclude)
	end
end

--- How far a root of `size` at `from` may move along `direction` (flattened) before the world stops
--- it, when that is less than `distance`, and the face's normal; nil when nothing does, or with no
--- world to ask (`cast` failed). The server's worldAhead cast (EnemyService, D-197) made from the
--- drawn body: the root's own box in the rushing group (the world only: a rush passes through
--- players and enemies, D-167), cast from where its front face stands at its centre, never against
--- its own `exclude`. Ground the body runs over is no stop (RushWorld.runsOver, D-204, D-209): a
--- slope, or a step's riser the box, cast level, meets two or three treads ahead.
function RushDraw.room(
	from: CFrame,
	size: Vector3,
	direction: Vector3,
	distance: number,
	cast: WorldCast,
	exclude: Instance
): (number?, Vector3?)
	local f = flat(direction)
	if f.Magnitude < 1e-6 or not (distance > 0) then
		return nil, nil
	end
	f = f.Unit
	local half = size / 2
	local reach = math.abs(from.RightVector:Dot(f)) * half.X
		+ math.abs(from.UpVector:Dot(f)) * half.Y
		+ math.abs(from.LookVector:Dot(f)) * half.Z
	local bound = bind(cast, exclude)
	local ok, travelled, normal = pcall(bound, from - f * reach, size, f * (distance + reach))
	if not ok or typeof(travelled) ~= "number" then
		return nil, nil
	end
	local face: Vector3? = if typeof(normal) == "Vector3" then normal else nil
	local free = math.max(0, travelled - reach)
	if RushWorld.runsOver(bound, from, size, f, free, face) then
		return nil, nil
	end
	return free, face
end

--- The height of the ground under `spot` (its X and Z), looking down from `spot`'s height by
--- ai.luau rushWorld.probeStuds in the rushing group, never at `exclude`; nil when nothing is there.
function RushDraw.ground(spot: Vector3, cast: WorldCast, exclude: Instance): number?
	return RushWorld.groundBelow(bind(cast, exclude), spot, WORLD.probeStuds)
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

-- The body judged against the world: the one set (RushDraw.setBody), else the root's box alone.
local function bodyOf(state: State): RushWorld.Body
	local body = state.body
	if body ~= nil then
		return body
	end
	return { profile = {}, size = Vector3.zero }
end

-- Looks at the world ahead of the drawn body along the leg it runs, as the server's cast does
-- (Charger look): as far as its snout gets this frame (`step` more studs down the path) plus
-- lookAheadStuds, never past the leg's end nor the run's. A wall becomes this client's own slam (the
-- body's limit and its cue), bend or sidestep (its path from here on), by RushWorld.contact.
local function look(state: State, root: CFrame, step: number, room: Room)
	if state.walled then
		return
	end
	local legs = state.legs
	local along = state.along
	local index = RushWorld.legIndex(legs, along)
	local leg = legs[index]
	local body = state.body
	local size = if body ~= nil then body.size else nil
	local frame = compose(state, root)
	local reach = 0
	if size ~= nil then
		local half = size / 2
		reach = math.abs(frame.RightVector:Dot(leg.heading)) * half.X
			+ math.abs(frame.UpVector:Dot(leg.heading)) * half.Y
			+ math.abs(frame.LookVector:Dot(leg.heading)) * half.Z
	end
	local front = if body ~= nil then math.max(RushWorld.front(body.profile), reach) else reach
	local farthest = math.min(
		along + step + front + WORLD.lookAheadStuds,
		RushWorld.lookLimit(legs, index, state.line.length, reach, front)
	)
	local distance = farthest - along - reach
	if not (distance > 0) then
		return
	end
	local free, normal = room(frame, leg.heading, distance)
	if free == nil then
		return
	end
	local probe = function(offset: Vector3, direction: Vector3, length: number): number?
		local hit = room(frame + offset, direction, length)
		return hit
	end
	local contact = RushWorld.contact(
		legs,
		along,
		free,
		normal,
		bodyOf(state),
		frame.Position.Y,
		if body ~= nil then probe else nil
	)
	local turned = contact.legs
	if contact.kind == "Slam" or turned == nil then
		RushDraw.wall(state, contact.at, contact.point, contact.normal, true)
		return
	end
	if not RushWorld.sameLegs(turned, legs) then
		state.legs = turned
		cue(state, contact.kind, contact.at, contact.point, contact.normal)
	end
end

-- The drawn root's height: on the ground under the drawn spot (`ground`) at the root's hover above
-- it. Never below it (a step lifts the body at once, as its root's Humanoid steps up when it gets
-- there); onto lower ground it drops under rushWorld.fallGravity, as its root falls. Without a
-- ground probe or a hover, or with nothing under it, it keeps the height it has.
local function stand(state: State, root: CFrame, dt: number, ground: Ground?)
	local hover = state.hover
	local height = state.height or root.Position.Y
	state.height = height
	if ground == nil or hover == nil then
		return
	end
	local spot = spotOf(state)
	local below = ground(Vector3.new(spot.X, height, spot.Z))
	if below == nil then
		return
	end
	local level = below + hover
	if level >= height then
		state.height = level
		state.fall = 0
		return
	end
	local speed = state.fall + WORLD.fallGravity * math.max(0, dt)
	local nextHeight = math.max(level, height - speed * math.max(0, dt))
	-- Landed, it keeps the pace the ground drops at (down a ramp), not a fall's.
	state.fall = if nextHeight <= level and dt > 0 then (height - nextHeight) / dt else speed
	state.height = nextHeight
end

-- The crouch (D-255): the body on its root, turned from the root's own look onto its line by the
-- launch at the chase's rate or the rate the time left needs, never faster than the run's turn. A
-- released crouch keeps turning onto the line (the server's body holds it) until the late root has
-- come round to the body (a frame's turn of the chase apart), then is on it; or after
-- settleSeconds it slides back onto the root.
local function armed(state: State, now: number, dt: number, root: CFrame): CFrame?
	local goal = state.legs[1].facing
	local look = unitFlat(root.LookVector, goal)
	local frame = math.max(0, dt)
	local chase = math.rad(CHARGER.turnRate)
	if state.drawn == nil then
		state.facing = look
	else
		local left = math.acos(math.clamp(state.facing:Dot(goal), -1, 1))
		local remaining = state.line.startedAt - now
		local rate = chase
		if not state.released then
			rate = if remaining > 1e-6
				then math.clamp(left / remaining, chase, math.rad(TUNING.turnRate))
				else math.rad(TUNING.turnRate)
		end
		state.facing = turnToward(state.facing, goal, rate * frame)
	end
	state.lastTime = now
	local position = root.Position
	local drawn = CFrame.lookAt(position, position + state.facing)
	if state.released then
		local apart = math.acos(math.clamp(look:Dot(state.facing), -1, 1))
		if apart <= chase * frame + 1e-6 then
			state.phase = "Done"
			state.drawn = nil
			return nil
		end
		if now - (state.settleAt or now) >= TUNING.settleSeconds then
			handBack(state, drawn, now, root)
		end
	end
	state.drawn = drawn
	return drawn
end

-- D-256: before any RushEnded told where the server's body stopped, its late root come to rest
-- (moved less than rushWorld.restStuds over restSeconds, carrying at most restSpeed) after leaving
-- its crouch (keepUpStuds) and more than jamLagStuds behind the drawn body is that body stuck there:
-- a free run rests only at its end. The jam and the rest are told as a RushEnded "Jammed" would.
local function noticeRest(state: State, now: number, root: CFrame, velocity: Vector3?)
	local spot = flat(root.Position)
	local seen = state.restSpot
	if seen == nil or (spot - seen).Magnitude > WORLD.restStuds then
		state.restSpot = spot
		state.restFrom = now
		return
	end
	if now - (state.restFrom or now) < WORLD.restSeconds then
		return
	end
	if velocity ~= nil and flat(velocity).Magnitude > WORLD.restSpeed then
		return
	end
	local along = RushWorld.project(state.legs, root.Position)
	if along < CHARGER.keepUpStuds or state.along - along <= CHARGER.jamLagStuds then
		return
	end
	RushDraw.jam(state, along)
	RushDraw.rest(state, along)
end

--- One frame: where to draw the root part at server time `now` (`dt` the frame's length) given
--- where its replicated root stands (and the velocity it carries, nil: unknown), or nil when the
--- body is drawn on its root (once Done; a crouch stands on it, turned). `room` asks the world how
--- far the drawn body may move (nil: never stopped); `ground` how high the ground under it stands
--- (nil: the drawn body keeps its height).
function RushDraw.step(
	state: State,
	now: number,
	dt: number,
	root: CFrame,
	room: Room?,
	ground: Ground?,
	rootVelocity: Vector3?
): CFrame?
	local line = state.line
	local phase = state.phase
	local launching = false
	if phase == "Done" then
		return nil
	elseif phase == "Frozen" then
		return state.drawn
	elseif phase == "Armed" then
		if now < line.startedAt or state.released then
			return armed(state, now, dt, root)
		end
		-- The launch: the body starts where the root is drawn, so nothing jumps; turned as the
		-- crouch drew it, else on the root's own look.
		local legs = state.legs
		local first = legs[1]
		local along = if #legs == 1
			then (flat(root.Position) - first.from):Dot(first.heading)
			else RushWorld.project(legs, root.Position)
		state.along = along
		state.lateral = flat(root.Position) - RushWorld.pointAt(legs, along)
		if state.drawn == nil then
			state.facing = unitFlat(root.LookVector, first.heading)
		end
		state.restSpot = nil
		state.restFrom = nil
		state.height = root.Position.Y
		state.fall = 0
		state.lastTime = math.max(line.startedAt, now - dt)
		state.phase = "Run"
		phase = "Run"
		launching = true
	end

	if phase == "Run" or phase == "Settle" then
		if state.rest == nil and not launching then
			noticeRest(state, now, root, rootVelocity)
		end
		local last = state.lastTime or now
		local goal = goalAt(state, now)
		local natural = math.max(0, goal - goalAt(state, last))
		-- No catching up on the launch frame itself: its first move is never more than a frame of
		-- the run's own travel, however late the launch was heard.
		local slack = if launching then 0 else TUNING.catchUpFraction * line.speed * math.max(0, dt)
		local step = math.max(0, math.clamp(goal - state.along, natural - slack, natural + slack))
		if step > 0 and room ~= nil then
			-- The world ahead: a slam stops the body with its snout on the face (as at a jam), a
			-- glance or a clipped corner turns its path.
			look(state, root, step, room)
			local limit = state.limit
			if limit ~= nil then
				goal = math.min(goal, limit)
				step = math.max(0, math.min(step, limit - state.along))
			end
		end
		state.along += step
		local off = state.lateral.Magnitude
		if off > 1e-6 then
			state.lateral = state.lateral * (math.max(0, off - slack) / off)
		end
		local leg = state.legs[RushWorld.legIndex(state.legs, state.along)]
		state.facing = turnToward(state.facing, leg.facing, math.rad(TUNING.turnRate) * math.max(0, dt))
		stand(state, root, dt, ground)
		state.lastTime = now
		if phase == "Run" and runOver(state, now) then
			state.phase = "Settle"
			state.settleAt = now
			phase = "Settle"
		end
		local drawn = compose(state, root)
		if phase == "Settle" then
			-- The root has come to where the server's body stopped (the last RushEnded's distance,
			-- else the run's end or a limit), or it has had settleSeconds to. A stop only this
			-- client's own cast guessed is no place to meet the root before the server's word: a
			-- late root still standing in its crouch near it, or running on past it, has not come to
			-- it, and the slide would chase it.
			local stopped = RushWorld.pointAt(state.legs, state.rest or goal)
			local guessed = state.rest == nil and state.guess ~= nil and state.limit == state.guess
			local arrived = not guessed and (flat(root.Position) - stopped).Magnitude <= TUNING.settleStuds
			local waited = now - (state.settleAt or now) >= TUNING.settleSeconds
			if arrived or waited then
				handBack(state, drawn, now, root)
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
