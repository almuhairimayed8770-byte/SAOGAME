--!strict
--[[
	DevTrace: the pure half of the Studio combat trace hook (DevCombat.server.luau, D-114). Turns
	CombatService's TraceEvent (one closed damage window of a player's run) into a plain table that
	a Studio MCP execute_luau can JSON-encode and into one compact Output line, keeps the newest
	events in a bounded buffer, and reads a facing argument. Dev tooling only: no engine access.

	Yaw is in degrees: a look's yaw is the angle CFrame.Angles(0, rad(yaw), 0) turns -Z by, so 0
	faces -Z and positive turns left, the way CombatService signs its trace bearing.
]]

-- The fields of CombatService.TraceEvent this module reads (the service exports the full type).
export type Nearest = {
	entityId: number,
	name: string,
	distance: number,
	bearingDegrees: number,
	clearance: number?,
}
export type Event = {
	entityId: number,
	clipId: string,
	artId: string?,
	windowIndex: number,
	windowCount: number,
	hits: number,
	facing: Vector3,
	rootLook: Vector3,
	nearest: Nearest?,
}
export type PlainNearest = { entityId: number, name: string, distance: number, bearing: number, clearance: number? }
export type Plain = {
	entityId: number,
	clipId: string,
	artId: string?,
	window: string,
	windowIndex: number,
	windowCount: number,
	hits: number,
	facingYaw: number?, -- the run's validated facing
	rootOff: number?, -- the server root's look at the close, from the facing (+ = left)
	nearest: PlainNearest?,
}

local EPSILON = 1e-6

local DevTrace = {}

--- `value` rounded to `decimals` places (nil stays nil; never a negative zero).
function DevTrace.round(value: number?, decimals: number): number?
	if value == nil then
		return nil
	end
	local rounded = tonumber(("%." .. tostring(decimals) .. "f"):format(value)) :: number
	return rounded + 0
end
local round = DevTrace.round

local function fixed(value: number?, decimals: number, signed: boolean): string
	if value == nil then
		return "-"
	end
	local pattern = (if signed then "%+." else "%.") .. tostring(decimals) .. "f"
	return pattern:format(round(value, decimals) :: number)
end

--- The yaw of a look (0 faces -Z, + = left), or nil when it has no flat length.
function DevTrace.yawOf(look: Vector3): number?
	if look.X * look.X + look.Z * look.Z < EPSILON then
		return nil
	end
	return math.deg(math.atan2(-look.X, -look.Z))
end

--- The signed turn in degrees (+ = left) from the flat look `from` to the flat look `to`.
function DevTrace.yawBetween(from: Vector3, to: Vector3): number?
	if from.X * from.X + from.Z * from.Z < EPSILON or to.X * to.X + to.Z * to.Z < EPSILON then
		return nil
	end
	local cross = from.Z * to.X - from.X * to.Z
	local dot = from.X * to.X + from.Z * to.Z
	return math.deg(math.atan2(cross, dot))
end

--- The event as plain, rounded fields (no Vector3), for "events" and the run replies.
function DevTrace.plain(event: Event, decimals: number): Plain
	local nearest = event.nearest
	local plainNearest: PlainNearest? = nil
	if nearest then
		plainNearest = {
			entityId = nearest.entityId,
			name = nearest.name,
			distance = round(nearest.distance, decimals) :: number,
			bearing = round(nearest.bearingDegrees, decimals) :: number,
			clearance = round(nearest.clearance, decimals),
		}
	end
	return {
		entityId = event.entityId,
		clipId = event.clipId,
		artId = event.artId,
		window = ("%d/%d"):format(event.windowIndex, event.windowCount),
		windowIndex = event.windowIndex,
		windowCount = event.windowCount,
		hits = event.hits,
		facingYaw = round(DevTrace.yawOf(event.facing), decimals),
		rootOff = round(DevTrace.yawBetween(event.facing, event.rootLook), decimals),
		nearest = plainNearest,
	}
end

--- One compact Output line for a closed window: who, which clip, which window, the hits, the
--- facing's yaw, the root's turn off it, and the nearest enemy's distance, bearing and blade
--- clearance ("-" when no blade was solved).
function DevTrace.line(event: Event, prefix: string, decimals: number): string
	local head = ("%s e%d %s%s w%d/%d hits=%d yaw=%s root=%s"):format(
		prefix,
		event.entityId,
		event.clipId,
		if event.artId ~= nil then (" (%s)"):format(event.artId) else "",
		event.windowIndex,
		event.windowCount,
		event.hits,
		fixed(DevTrace.yawOf(event.facing), decimals, false),
		fixed(DevTrace.yawBetween(event.facing, event.rootLook), decimals, true)
	)
	local nearest = event.nearest
	if not nearest then
		return head .. " | no enemy"
	end
	return ("%s | %s #%d d=%s bearing=%s clear=%s"):format(
		head,
		nearest.name,
		nearest.entityId,
		fixed(nearest.distance, decimals, false),
		fixed(nearest.bearingDegrees, decimals, true),
		fixed(nearest.clearance, decimals, false)
	)
end

--- Appends `item` and drops the oldest past `keep`.
function DevTrace.push<T>(buffer: { T }, item: T, keep: number)
	table.insert(buffer, item)
	while #buffer > keep do
		table.remove(buffer, 1)
	end
end

--- The newest `count` items, oldest first (all of them when count is nil).
function DevTrace.last<T>(buffer: { T }, count: number?): { T }
	local from = if count == nil then 1 else math.max(#buffer - count + 1, 1)
	local out = {}
	for index = from, #buffer do
		table.insert(out, buffer[index])
	end
	return out
end

--- True once a run's last window has closed.
function DevTrace.complete(events: { Event }): boolean
	local last = events[#events]
	return last ~= nil and last.windowIndex >= last.windowCount
end

--- The hits a run's windows landed.
function DevTrace.hitsOf(events: { Event }): number
	local total = 0
	for _, event in events do
		total += event.hits
	end
	return total
end

--- A facing argument: nil, a Vector3 or an {x, y, z} list. Returns nil and a reason for anything else.
function DevTrace.vector(value: any): (Vector3?, string?)
	if value == nil then
		return nil, nil
	end
	if typeof(value) == "Vector3" then
		return value, nil
	end
	if typeof(value) == "table" then
		local x, y, z = value[1], value[2], value[3]
		if typeof(x) == "number" and typeof(y) == "number" and typeof(z) == "number" then
			return Vector3.new(x, y, z), nil
		end
	end
	return nil, "facing must be a Vector3 or an {x, y, z} list of numbers"
end

return DevTrace
