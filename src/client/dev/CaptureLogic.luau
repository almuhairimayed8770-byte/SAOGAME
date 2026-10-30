--!strict
--[[
	CaptureLogic: the capture panel's pure rules (Capture.client.luau, F12), on plain values so they
	run in Lune: the counter's line, what K does before and at a take's target length, the prompt
	line at a moment of the take, auto-perform's presses (a shot's timed keys and stick, the
	reactions timed off an enemy's attack clip the client is drawing and moved on by its hit-stop,
	their chains and Art cycle, the standing rules, the stick on the camera's frame, the lock
	presses on a staged enemy and the let-go of the keys a stopped take holds, D-290, CF; when a
	standing basic may go, a chain Art's queued let-go taken back and the way up a staging reply
	reads, EF), and the walk into the stand ring a
	staging asks for (D-244): the walk read off the reply, whether the feet stand in the ring or
	near its spot, where the auto-walk steers and where it lets go (the stop's carry ahead of the
	spot along the last leg), the correction's walk back behind the spot and its creep in (CW), how
	far a body at rest is off the spot and its facing, the turn on the spot to that facing, and when
	the next staging may be asked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.types)
local ActionLogic = require(script.Parent.Parent.controllers.ActionLogic)

local CaptureLogic = {}

-- One step of a reaction's chain (dev.luau PerformStep).
export type PerformStep = {
	action: string,
	hold: number,
	delay: number,
	enemy: number?,
	cycle: { string }?,
	stick: { number }?,
	sprint: boolean?,
	within: number?,
	to: number?,
}

-- One entry of a shot's perform list (dev.luau Perform).
export type PerformEntry = {
	action: string,
	hold: number,
	at: number?,
	onClip: string?,
	lead: number?,
	enemy: number?,
	repeats: boolean?,
	lock: boolean?,
	chain: { PerformStep }?,
	every: number?,
	from: number?,
	to: number?,
	within: number?,
	stick: { number }?,
	sprint: boolean?,
}

-- One key auto-perform presses or lets go of `at` seconds into the take; a stick's press (the
-- move action) carries its entry, whose stick and sprint it holds.
export type Press = { at: number, action: string, down: boolean, entry: PerformEntry? }

-- A clip-timed entry's state (CF): the take time its key goes down next (nil: none waits), the
-- clip time of the last event heard (an earlier one starts a new play), whether this play has had
-- its press, and how many presses it has had.
export type Reaction = { entry: PerformEntry, at: number?, heard: number?, pressed: boolean, count: number }

-- A standing rule's state (CF): its entry and the take time it last pressed.
export type Standing = { entry: PerformEntry, last: number? }

-- The walk a staging asks for (DevStage's reply, DevStageLogic.Ring plus its route): the stand
-- ring (the spot's floor point and facing, the flat radius, how far the feet may be off the floor,
-- the box the feet must stand over or nil) and the route's flat points { x, z }, the last the
-- spot; `index` is the point the auto-walk steers for.
export type Walk = {
	x: number,
	y: number,
	z: number,
	facing: number,
	radius: number,
	tolerance: number,
	over: { number }?,
	path: { { number } },
	index: number,
	-- A correction (CaptureLogic.correctStep) has reached its point behind the spot.
	backed: boolean?,
}

export type Counter = {
	shotId: string,
	frames: number,
	rendered: number?, -- RenderStepped frames since the take started (D-336)
	elapsed: number,
	target: number,
	scale: number,
	auto: boolean?, -- auto-perform is pressing this take's keys
	confirming: boolean?, -- K was pressed short of the target: a second one stops unmarked
	markKey: string?,
}

--- The counter's line: the shot, the frame (and the rendered frames, when given: r), the time
--- against the target length and the scale.
function CaptureLogic.counterText(counter: Counter): string
	local frame = ("f %d"):format(counter.frames)
	if counter.rendered ~= nil then
		frame ..= ("  r %d"):format(counter.rendered)
	end
	local text = ("%s  %s  %.1f / %g s  %gx"):format(
		counter.shotId,
		frame,
		counter.elapsed,
		counter.target,
		counter.scale
	)
	if counter.auto == true then
		text ..= "  auto"
	end
	if counter.confirming == true then
		text ..= ("  short of the target: %s again stops it unmarked"):format(counter.markKey or "K")
	end
	return text
end

--- The corner square's color token on the `rendered`th rendered frame of a take (0 on its first):
--- the two tokens in turn, so it swaps every rendered frame (D-336).
function CaptureLogic.tickToken(rendered: number, tokens: { string }): string
	return tokens[rendered % 2 + 1]
end

--- What K does `elapsed` seconds into a take of target length `target`, at clock `now` with a stop
--- waiting to be confirmed until `confirmUntil` (nil: none): "Done" at or past the target (marked),
--- "Stop" inside the confirm window (ended, unmarked), else "Confirm" (asks first).
function CaptureLogic.markDecision(elapsed: number, target: number, now: number, confirmUntil: number?): string
	if elapsed >= target then
		return "Done"
	end
	if confirmUntil ~= nil and now <= confirmUntil then
		return "Stop"
	end
	return "Confirm"
end

--- The prompt line `elapsed` seconds into the take: the last beat whose moment has come, or nil.
function CaptureLogic.promptAt(prompts: { { at: number, text: string } }, elapsed: number): string?
	local line: string? = nil
	for _, beat in prompts do
		if beat.at <= elapsed then
			line = beat.text
		else
			break
		end
	end
	return line
end

--- A shot's timed keys as presses in time order: each `at` a down and `at + hold` an up, a
--- stick's carrying its entry. The clip-timed ones (onClip) and the standing rules (every) are
--- left out: a reaction is timed when its attack is heard.
function CaptureLogic.timedPresses(perform: { PerformEntry }): { Press }
	local presses: { Press } = {}
	for _, entry in perform do
		local at = entry.at
		if at ~= nil then
			local carried = if entry.stick ~= nil then entry else nil
			table.insert(presses, { at = at, action = entry.action, down = true, entry = carried })
			table.insert(presses, { at = at + entry.hold, action = entry.action, down = false, entry = carried })
		end
	end
	table.sort(presses, function(a: Press, b: Press): boolean
		if a.at ~= b.at then
			return a.at < b.at
		end
		-- A let-go before a press at the same moment.
		return not a.down and b.down
	end)
	return presses
end

--- Puts `press` into `queue` (sorted) in time order: after every press at or before its moment,
--- a let-go ahead of a press at the same moment.
function CaptureLogic.enqueue(queue: { Press }, press: Press)
	local index = #queue + 1
	for position, other in queue do
		if press.at < other.at or (press.at == other.at and not press.down and other.down) then
			index = position
			break
		end
	end
	table.insert(queue, index, press)
end

--- Takes the presses due by `elapsed` off the front of `queue` (sorted), in order.
function CaptureLogic.due(queue: { Press }, elapsed: number): { Press }
	local list: { Press } = {}
	while #queue > 0 and queue[1].at <= elapsed do
		table.insert(list, table.remove(queue, 1) :: Press)
	end
	return list
end

--- Seconds from now until the parry's guard goes down: `lead` before the attack clip's first
--- HitWindowOpen, heard at its event `eventTime` seconds into the clip. Nil when the clip has no
--- hit window or that moment has passed.
function CaptureLogic.parryDelay(events: { Types.ClipEvent }, eventTime: number, lead: number): number?
	for _, event in events do
		if event.kind == "HitWindowOpen" then
			local delay = event.time - eventTime - lead
			return if delay >= 0 then delay else nil
		end
	end
	return nil
end

--- A reaction for each clip-timed entry of a shot's perform list, in list order, none waiting.
function CaptureLogic.reactions(perform: { PerformEntry }): { Reaction }
	local list: { Reaction } = {}
	for _, entry in perform do
		if entry.onClip ~= nil then
			table.insert(list, { entry = entry, at = nil, heard = nil, pressed = false, count = 0 })
		end
	end
	return list
end

--- Hears an event `eventTime` seconds into a play of the reaction's clip (its `events`), at take
--- time `elapsed`. An event earlier than the last heard starts a new play. Until the play's press
--- (and on the first play only, unless the entry repeats) the press is set `lead` before the
--- clip's hit window, from this event: each later event moves it on, since the client holds an
--- attack's clip through its attacker's hit-stop. `early` (how long a press takes to reach the
--- server on the server's clock: the way up a staging reply read, CaptureLogic.wayUp, else the
--- glint lead, Telegraphs.glintLead, D-289, EF) sets a Guard that much earlier still, so it
--- reaches the server inside the parry window as a press with no latency would (the server judges
--- that window on its own clock); never before `elapsed`. Any other press stays on the clip as
--- drawn (a dodge and its chain meet the body this client draws, D-319). A press that would come
--- past the entry's `to` is not set (CaptureLogic.inside). True when it set the press.
function CaptureLogic.hear(
	reaction: Reaction,
	events: { Types.ClipEvent },
	eventTime: number,
	elapsed: number,
	early: number?
): boolean
	local last = reaction.heard
	if last ~= nil and eventTime < last then
		reaction.pressed = false
	end
	reaction.heard = eventTime
	if reaction.pressed or (reaction.entry.repeats ~= true and reaction.count > 0) then
		return false
	end
	local delay = CaptureLogic.parryDelay(events, eventTime, reaction.entry.lead or 0)
	if delay == nil then
		return false
	end
	local shift = if reaction.entry.action == "Guard" then math.max(early or 0, 0) else 0
	local at = elapsed + math.max(delay - shift, 0)
	if not CaptureLogic.inside(reaction.entry, at) then
		reaction.at = nil
		return false
	end
	reaction.at = at
	return true
end

--- Whether a reaction's key, or a step of its chain, may go down at take time `at`: at most its
--- entry's `to` (no limit without one), so what it launches lands before the take's cut (D-320).
--- A chain step is held to its own `to` as well (EF): the fight's guard answers every overhead the
--- take shows while the Art after it stops early enough to land before the cut.
function CaptureLogic.inside(entry: PerformEntry | PerformStep, at: number): boolean
	local to = entry.to
	return to == nil or at <= to + 1e-9
end

--- The reaction's attacker was hit mid-attack: the server paused its attack `seconds` (HitConfirmed
--- attackPause) and this client holds its clip as long, so a press waiting comes that much later.
function CaptureLogic.pause(reaction: Reaction, seconds: number)
	local at = reaction.at
	if at ~= nil and seconds > 0 then
		reaction.at = at + seconds
	end
end

--- The reaction's key went down: this play has had its press, and nothing waits.
function CaptureLogic.pressed(reaction: Reaction)
	reaction.at = nil
	reaction.pressed = true
	reaction.count += 1
end

--- Takes the earliest queued let-go of `action` off `queue` (a key let go early: a chain's held Art
--- cancelled when a reaction drops the chain, EF). True when there was one.
function CaptureLogic.unqueue(queue: { Press }, action: string): boolean
	for index, press in queue do
		if press.action == action and not press.down then
			table.remove(queue, index)
			return true
		end
	end
	return false
end

--- Whether a standing rule's key may go down while the local body is in `state`
--- (CharacterController.state; nil when there is no body to ask): a BasicAttack only when the body
--- could start a basic (ActionLogic.canStart). A basic pressed in an Art, a hold, a guard or a
--- dodge does nothing, and spending the rule's beat on it left the body's next free moment waiting
--- out `every` (EF: no basic landed in Studio's fight). The lock rule never waits on the body.
function CaptureLogic.standingFree(action: string, state: unknown): boolean
	if action ~= "BasicAttack" or typeof(state) ~= "string" then
		return true
	end
	return (ActionLogic.canStart(state :: any, "Basic", 0, 0))
end

--- The way up a staging reply reads (EF): how long the ask sent at `sentAt` on this client's server
--- clock (workspace:GetServerTimeNow) took to reach the server on its own clock (the reply's
--- `receivedAt`, DevStage): the way up plus this client's clock lag behind the server's, the lead
--- a press needs to reach the server when one with no latency would. Within 0 and `max`; nil with
--- nothing to read.
function CaptureLogic.wayUp(sentAt: number?, reply: unknown, max: number): number?
	if sentAt == nil or typeof(reply) ~= "table" then
		return nil
	end
	local receivedAt = (reply :: any).receivedAt
	if typeof(receivedAt) ~= "number" then
		return nil
	end
	return math.clamp(receivedAt - sentAt, 0, max)
end

--- The standing rules (`every`) of a shot's perform list, in list order, none pressed yet.
function CaptureLogic.standing(perform: { PerformEntry }): { Standing }
	local list: { Standing } = {}
	for _, entry in perform do
		if entry.every ~= nil then
			table.insert(list, { entry = entry, last = nil })
		end
	end
	return list
end

--- Whether a standing rule may press at take time `elapsed`: inside its span (`from` to `to`, the
--- whole take when unset) and `every` seconds or more since it last pressed.
function CaptureLogic.standingDue(rule: Standing, elapsed: number): boolean
	local entry = rule.entry
	if elapsed < (entry.from or 0) or elapsed > (entry.to or math.huge) then
		return false
	end
	local last = rule.last
	return last == nil or elapsed - last >= (entry.every or 0) - 1e-9
end

--- The action a step presses the `count`-th time it comes round (from 1): its cycle's in turn,
--- or its own action.
function CaptureLogic.cycleAction(step: PerformStep, count: number): string
	local cycle = step.cycle
	if cycle == nil or #cycle == 0 then
		return step.action
	end
	return cycle[(math.max(count, 1) - 1) % #cycle + 1]
end

--- A stick { right, forward } on the camera's view as Humanoid:Move's camera-relative vector
--- (x right, z back), no longer than a full push.
function CaptureLogic.stickMove(stick: { number }): (number, number)
	local x, z = stick[1] or 0, -(stick[2] or 0)
	local length = math.sqrt(x * x + z * z)
	if length > 1 then
		return x / length, z / length
	end
	return x, z
end

--- The id of staged enemy `enemy` (stage.enemies index, 1 when nil) from the staging reply's ids;
--- the staged target alone when the reply listed none (nil past it).
function CaptureLogic.enemyId(ids: { number }?, targetId: number?, enemy: number?): number?
	local index = enemy or 1
	if ids ~= nil then
		return ids[index]
	end
	return if index == 1 then targetId else nil
end

--- What an auto-perform lock press does in a take that staged `stagedId` while the lock is on
--- `lockedId` (D-290): it acts on the staged target alone, never the lock key's cycle (best, next
--- one down, then off), which could step on to a field enemy nearer than the staged one. "Lock" it
--- when the lock is off or on another enemy, "Release" it when the lock is on it, and "Key" (the
--- lock key's own path) when the take staged no target (outside Studio).
function CaptureLogic.lockPress(stagedId: number?, lockedId: number?): "Lock" | "Release" | "Key"
	if stagedId == nil then
		return "Key"
	end
	return if lockedId == stagedId then "Release" else "Lock"
end

-- One key a stopped take lets go of: its action, and its Art slot when it is an Art key.
export type LetGo = { action: string, slot: number? }

--- The keys auto-perform still holds as a take stops (`held`, by action), each to come up without
--- acting (D-290): in name order, an Art key with its slot (`slotOf`, input.luau artSlot), whose
--- hold is cancelled before the key comes up, so the release launches nothing.
function CaptureLogic.letGo(held: { [string]: boolean }, slotOf: (string) -> number?): { LetGo }
	local keys: { LetGo } = {}
	for action, down in held do
		if down then
			table.insert(keys, { action = action, slot = slotOf(action) })
		end
	end
	table.sort(keys, function(a: LetGo, b: LetGo): boolean
		return a.action < b.action
	end)
	return keys
end

--- Whether auto-perform presses this take: on, and at 1x (slowed, the drawn clips run late on the
--- server's clock and a timed key would land off its beat).
function CaptureLogic.performs(on: boolean, scale: number): boolean
	return on and scale == 1
end

local function isNumber(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value :: number) ~= math.huge
end

local function numbers(list: unknown, count: number): { number }?
	if typeof(list) ~= "table" or #(list :: { any }) ~= count then
		return nil
	end
	local out: { number } = {}
	for index = 1, count do
		local value = (list :: { any })[index]
		if not isNumber(value) then
			return nil
		end
		out[index] = value
	end
	return out
end

--- The walk a staging reply asks for: nil when the reply carries none, or a malformed one. A
--- fresh table, steering for the route's first point.
function CaptureLogic.walkFrom(reply: unknown): Walk?
	if typeof(reply) ~= "table" then
		return nil
	end
	local walk = (reply :: any).walk
	if typeof(walk) ~= "table" then
		return nil
	end
	for _, key in { "x", "y", "z", "facing", "radius", "tolerance" } do
		if not isNumber(walk[key]) then
			return nil
		end
	end
	local over: { number }? = nil
	if walk.over ~= nil then
		over = numbers(walk.over, 4)
		if over == nil then
			return nil
		end
	end
	local path: { { number } } = {}
	if typeof(walk.path) == "table" then
		for _, point in walk.path do
			local flat = numbers(point, 2)
			if flat == nil then
				return nil
			end
			table.insert(path, flat :: { number })
		end
	end
	if #path == 0 then
		path = { { walk.x, walk.z } }
	end
	return {
		x = walk.x,
		y = walk.y,
		z = walk.z,
		facing = walk.facing,
		radius = walk.radius,
		tolerance = walk.tolerance,
		over = over,
		path = path,
		index = 1,
	}
end

--- Whether feet at (x, floorY, z) stand in the walk's ring: the rule the server stages by
--- (DevStageLogic.inRing), within the radius (flat) of the spot, within the tolerance of its floor
--- and over its box when it has one.
function CaptureLogic.inRing(walk: Walk, x: number, floorY: number, z: number): boolean
	local dx, dz = x - walk.x, z - walk.z
	if dx * dx + dz * dz > walk.radius * walk.radius or math.abs(floorY - walk.y) > walk.tolerance then
		return false
	end
	local over = walk.over
	return over == nil or (x >= over[1] and x <= over[2] and z >= over[3] and z <= over[4])
end

--- The stop's carry (studs) after the auto-walk lets go at `speed` studs per second (1x terms):
--- none past `skidSpeed` (choreo locomotion.skidSpeedThreshold: the Skid stops the body, and the
--- two-step stop carries nothing, D-059), else speed x carrySeconds (the two-step stop's carry
--- through the middle of the stride).
function CaptureLogic.stopCarry(speed: number, skidSpeed: number, carrySeconds: number): number
	if speed > skidSpeed then
		return 0
	end
	return math.max(speed, 0) * carrySeconds
end

--- The route's last leg as a flat unit direction (the point before the spot to the spot), or nil
--- for a route of the spot alone.
function CaptureLogic.lastLeg(walk: Walk): (number?, number?)
	local path = walk.path
	if #path < 2 then
		return nil, nil
	end
	local from, spot = path[#path - 1], path[#path]
	local dx, dz = spot[1] - from[1], spot[2] - from[2]
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		return nil, nil
	end
	return dx / length, dz / length
end

--- How far (studs) the route's end is still ahead of (x, z) along the last leg (below 0: past
--- it); for a route of the spot alone, the flat distance to it.
function CaptureLogic.ahead(walk: Walk, x: number, z: number): number
	local spot = walk.path[#walk.path]
	local dx, dz = spot[1] - x, spot[2] - z
	local ux, uz = CaptureLogic.lastLeg(walk)
	if ux == nil or uz == nil then
		return math.sqrt(dx * dx + dz * dz)
	end
	return dx * ux + dz * uz
end

--- The flat unit direction the auto-walk steers along from (x, z), or nil once it lets go. It
--- steers for the route's point at `walk.index`, moving the index on past every point within
--- `reach` studs (flat) up to the one before the spot. On the last leg it follows the leg's line,
--- aiming `lookahead` studs along it past the root's foot on it (so the body comes square onto the
--- leg and runs along the spot's facing), and lets go once the spot is no more than `letGo` studs
--- ahead along the leg. A route of the spot alone steers straight for it and lets go within
--- `letGo` of it.
function CaptureLogic.steer(
	walk: Walk,
	x: number,
	z: number,
	reach: number,
	letGo: number,
	lookahead: number
): (number?, number?)
	local path = walk.path
	while walk.index < #path do
		local point = path[walk.index]
		local dx, dz = point[1] - x, point[2] - z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance > reach then
			return dx / distance, dz / distance
		end
		walk.index += 1
	end
	local spot = path[#path]
	local ux, uz = CaptureLogic.lastLeg(walk)
	if ux == nil or uz == nil then
		local dx, dz = spot[1] - x, spot[2] - z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance <= letGo or distance < 1e-6 then
			return nil, nil
		end
		return dx / distance, dz / distance
	end
	local ahead = (spot[1] - x) * ux + (spot[2] - z) * uz
	if ahead <= letGo then
		return nil, nil
	end
	-- The point `lookahead` along the leg past the root's foot on its line.
	local aimX = spot[1] - ux * (ahead - lookahead) - x
	local aimZ = spot[2] - uz * (ahead - lookahead) - z
	local length = math.sqrt(aimX * aimX + aimZ * aimZ)
	if length < 1e-6 then
		return ux, uz
	end
	return aimX / length, aimZ / length
end

--- The flat unit direction a body walks onto the spot along: the route's last leg, or for a route
--- of the spot alone the spot's facing (0 looks along -Z, + turns left).
function CaptureLogic.approachDirection(walk: Walk): (number, number)
	local ux, uz = CaptureLogic.lastLeg(walk)
	if ux ~= nil and uz ~= nil then
		return ux, uz
	end
	local radians = math.rad(walk.facing)
	return -math.sin(radians), -math.cos(radians)
end

--- Whether feet at (x, floorY, z) stand within `studs` (flat) of the walk's spot and within its
--- ring's height tolerance of the spot's floor (a body below the ledge is never near its top).
function CaptureLogic.near(walk: Walk, x: number, floorY: number, z: number, studs: number): boolean
	local dx, dz = x - walk.x, z - walk.z
	return dx * dx + dz * dz <= studs * studs and math.abs(floorY - walk.y) <= walk.tolerance
end

--- The correction (a second walk, or a walk asked for while the root stands beside the spot,
--- CW): never a sprint, and never a turn-round near the spot at speed. Unless the root already
--- stands `back` studs or more behind the spot along the approach (CaptureLogic.approachDirection)
--- and within `reach` of its line, it first walks to the point `back` studs behind the spot at
--- `pace` (studs per second, 1x) until within `reach` of it (walk.backed). Then it walks in along
--- the approach at a pace that falls with the distance left (ahead / creepSeconds, at most
--- `pace`), so the body arrives as good as stopped and the two-step stop has nothing to carry: it
--- aims `lookahead` along the line past the root's foot on it, and straight along it over the
--- last `lookahead` studs, so the body ends square to the spot's facing. Returns the flat unit
--- direction and the pace to walk it at, or nil once the pace asked falls under `endPace` (the
--- spot reached or passed): let go.
function CaptureLogic.correctStep(
	walk: Walk,
	x: number,
	z: number,
	back: number,
	reach: number,
	lookahead: number,
	pace: number,
	creepSeconds: number,
	endPace: number
): (number?, number?, number?)
	local spot = walk.path[#walk.path]
	local ux, uz = CaptureLogic.approachDirection(walk)
	local ahead = (spot[1] - x) * ux + (spot[2] - z) * uz
	local side = (x - spot[1]) * uz - (z - spot[2]) * ux
	if walk.backed ~= true then
		if ahead >= back and math.abs(side) <= reach then
			walk.backed = true
		else
			local dx, dz = spot[1] - ux * back - x, spot[2] - uz * back - z
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance > reach then
				return dx / distance, dz / distance, pace
			end
			walk.backed = true
		end
	end
	local speed = ahead / creepSeconds
	if speed < endPace then
		return nil, nil, nil
	end
	if ahead <= lookahead then
		return ux, uz, math.min(pace, speed)
	end
	local aimX = spot[1] - ux * (ahead - lookahead) - x
	local aimZ = spot[2] - uz * (ahead - lookahead) - z
	local length = math.sqrt(aimX * aimX + aimZ * aimZ)
	if length < 1e-6 then
		return ux, uz, math.min(pace, speed)
	end
	return aimX / length, aimZ / length, math.min(pace, speed)
end

--- How far a body at rest at (x, z), looking along (lookX, lookZ), is off the walk's spot: the
--- flat studs from it and the degrees from the spot's facing (as DevStageLogic.look reads it:
--- 0 looks along -Z, + turns left).
function CaptureLogic.restOff(walk: Walk, x: number, z: number, lookX: number, lookZ: number): (number, number)
	local dx, dz = x - walk.x, z - walk.z
	local studs = math.sqrt(dx * dx + dz * dz)
	local length = math.sqrt(lookX * lookX + lookZ * lookZ)
	if length < 1e-6 then
		return studs, 180
	end
	local radians = math.rad(walk.facing)
	local dot = (lookX * -math.sin(radians) + lookZ * -math.cos(radians)) / length
	return studs, math.deg(math.acos(math.clamp(dot, -1, 1)))
end

--- The turn on the spot for a body at rest looking along (lookX, lookZ) toward the walk's spot's
--- facing: the yaw (degrees about +Y, + turns left as the facing does) to turn it by this frame,
--- the shorter way and at most `most`, and whether that turn reaches the facing. A look with no
--- flat direction turns nothing and never reaches it.
function CaptureLogic.faceTurn(walk: Walk, lookX: number, lookZ: number, most: number): (number, boolean)
	if lookX * lookX + lookZ * lookZ < 1e-12 then
		return 0, false
	end
	local facing = math.deg(math.atan2(-lookX, -lookZ))
	local left = (walk.facing - facing + 180) % 360 - 180
	local step = math.max(most, 0)
	if math.abs(left) <= step then
		return left, true
	end
	return if left > 0 then step else -step, false
end

--- Seconds to wait before the next request may go, the last having gone at `lastAt` (nil: none):
--- the server takes one a player per 1 / perSecond.
function CaptureLogic.askWait(lastAt: number?, now: number, perSecond: number): number
	if lastAt == nil then
		return 0
	end
	return math.max(0, lastAt + 1 / perSecond - now)
end

return CaptureLogic
