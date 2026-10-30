--!strict
--[[
	DevAimLogic: the pure half of the Studio aim hook (DevAim.client.luau, D-114). The signed yaw
	from the body's flat look to a point, the Heartbeat turn step, which enemy a command aims at, a
	"swing" command's plan, when the body is free and when an Art's run is over, and the rounding
	and tallies of the report. Dev tooling only: no engine access, no gameplay decision.

	Yaw is in degrees and positive to the left, the way CFrame.Angles(0, rad(yaw), 0) turns a body
	and the way CombatService's trace signs its bearing.
]]

export type SwingKind = "basic" | "art"
export type SwingPlan = { kind: SwingKind, slot: number, count: number }
export type SwingLimits = { maxSwings: number, defaultSlot: number, slots: number }
export type Candidate = { id: number, distance: number }

local EPSILON = 1e-6

local FREE: { [string]: boolean } = { Idle = true, Moving = true }

local DevAimLogic = {}

--- The command names the hook answers, for its "help" reply.
DevAimLogic.COMMANDS = { "help", "status", "lock", "face", "swing", "guard", "dodge", "draw" }

--- Signed degrees (+ = left) from the flat look (lookX, lookZ) to the flat offset (dx, dz); nil
--- when either has no length.
function DevAimLogic.yawOff(lookX: number, lookZ: number, dx: number, dz: number): number?
	if lookX * lookX + lookZ * lookZ < EPSILON or dx * dx + dz * dz < EPSILON then
		return nil
	end
	local cross = lookZ * dx - lookX * dz
	local dot = lookX * dx + lookZ * dz
	return math.deg(math.atan2(cross, dot))
end

--- This frame's share of a turn of `delta` degrees at `ratePerSecond` over `dt` seconds.
function DevAimLogic.turnStep(delta: number, ratePerSecond: number, dt: number): number
	local most = ratePerSecond * dt
	return math.clamp(delta, -most, most)
end

--- True when a yaw off the target is known and within `tolerance` degrees.
function DevAimLogic.faced(yaw: number?, tolerance: number): boolean
	return yaw ~= nil and math.abs(yaw) <= tolerance
end

--- The enemy a command aims at: the id asked for, else the lock, else the nearest candidate (the
--- lower id on a tie).
function DevAimLogic.pickTarget(requestedId: number?, lockId: number?, candidates: { Candidate }): number?
	if requestedId ~= nil then
		return requestedId
	end
	if lockId ~= nil then
		return lockId
	end
	local best: Candidate? = nil
	for _, candidate in candidates do
		if
			best == nil
			or candidate.distance < best.distance
			or (candidate.distance == best.distance and candidate.id < best.id)
		then
			best = candidate
		end
	end
	return if best ~= nil then best.id else nil
end

--- The args table of an invoke (anything else reads as no args).
function DevAimLogic.args(value: any): { [string]: any }
	return if typeof(value) == "table" then value else {}
end

local function isWhole(value: any): boolean
	return typeof(value) == "number" and value == value and value % 1 == 0
end

--- A "swing" command's plan from its args: kind "basic" (default) or "art", the Art slot
--- (default `limits.defaultSlot`) and the count (default 1, at most `limits.maxSwings`). Returns
--- nil and the reason for args it cannot run.
function DevAimLogic.swingPlan(value: any, limits: SwingLimits): (SwingPlan?, string?)
	local args = DevAimLogic.args(value)
	local kind = if args.kind == nil then "basic" else args.kind
	if kind ~= "basic" and kind ~= "art" then
		return nil, ('kind must be "basic" or "art", got %s'):format(tostring(args.kind))
	end
	local slot = if args.slot == nil then limits.defaultSlot else args.slot
	if not isWhole(slot) or slot < 1 or slot > limits.slots then
		return nil, ("slot must be a whole number from 1 to %d"):format(limits.slots)
	end
	local count = if args.count == nil then 1 else args.count
	if not isWhole(count) or count < 1 or count > limits.maxSwings then
		return nil, ("count must be a whole number from 1 to %d"):format(limits.maxSwings)
	end
	return { kind = kind :: SwingKind, slot = slot, count = count }, nil
end

--- True when the server state lets a new action start (Idle, Moving, or not known yet).
function DevAimLogic.isFree(state: string?): boolean
	return state == nil or FREE[state] == true
end

--- True once an Art's run is over: the server put the body in Art and has freed it since.
function DevAimLogic.artRunOver(states: { string }): boolean
	if table.find(states, "Art") == nil or #states == 0 then
		return false
	end
	return FREE[states[#states]] == true
end

--- `value` rounded to `decimals` places (nil stays nil; never a negative zero).
function DevAimLogic.round(value: number?, decimals: number): number?
	if value == nil then
		return nil
	end
	local rounded = tonumber(("%." .. tostring(decimals) .. "f"):format(value)) :: number
	return rounded + 0
end

--- How many hits and how much damage a swing's HitConfirmed payloads carry.
function DevAimLogic.tally(hits: { { damage: number } }): (number, number)
	local damage = 0
	for _, hit in hits do
		damage += hit.damage
	end
	return #hits, damage
end

return DevAimLogic
