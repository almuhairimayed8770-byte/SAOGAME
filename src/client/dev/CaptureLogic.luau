--!strict
--[[
	CaptureLogic: the capture panel's pure rules (Capture.client.luau, F12), on plain values so they
	run in Lune: the counter's line, what K does before and at a take's target length, the prompt
	line at a moment of the take, auto-perform's presses (a shot's timed keys, and the parry's
	guard timed off the attack clip the client is drawing), and the walk into the stand ring a
	staging asks for (D-244): the walk read off the reply, whether the feet stand in the ring, where
	the auto-walk steers, and when the next staging may be asked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.types)

local CaptureLogic = {}

-- One key auto-perform presses or lets go of `at` seconds into the take.
export type Press = { at: number, action: string, down: boolean }

-- One entry of a shot's perform list (dev.luau Perform).
export type PerformEntry = { action: string, hold: number, at: number?, onClip: string?, lead: number? }

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
}

export type Counter = {
	shotId: string,
	frames: number,
	elapsed: number,
	target: number,
	scale: number,
	auto: boolean?, -- auto-perform is pressing this take's keys
	confirming: boolean?, -- K was pressed short of the target: a second one stops unmarked
	markKey: string?,
}

--- The counter's line: the shot, the frame, the time against the target length and the scale.
function CaptureLogic.counterText(counter: Counter): string
	local text = ("%s  f %d  %.1f / %g s  %gx"):format(
		counter.shotId,
		counter.frames,
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

--- A shot's timed keys as presses in time order: each `at` a down and `at + hold` an up. The
--- clip-timed ones (onClip) are left out: the parry is timed when its attack is heard.
function CaptureLogic.timedPresses(perform: { PerformEntry }): { Press }
	local presses: { Press } = {}
	for _, entry in perform do
		local at = entry.at
		if at ~= nil then
			table.insert(presses, { at = at, action = entry.action, down = true })
			table.insert(presses, { at = at + entry.hold, action = entry.action, down = false })
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

--- The flat unit direction the auto-walk steers along from (x, z): toward the route's point at
--- `walk.index`, moving the index on past every point within `reach` studs (flat) but the last
--- (the spot), which is reached within `arrive`. Nil once the spot is reached (the walk lets go).
function CaptureLogic.steer(walk: Walk, x: number, z: number, reach: number, arrive: number): (number?, number?)
	local path = walk.path
	while walk.index <= #path do
		local point = path[walk.index]
		local dx, dz = point[1] - x, point[2] - z
		local distance = math.sqrt(dx * dx + dz * dz)
		local last = walk.index == #path
		if distance > (if last then arrive else reach) then
			return dx / distance, dz / distance
		end
		if last then
			return nil, nil
		end
		walk.index += 1
	end
	return nil, nil
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
