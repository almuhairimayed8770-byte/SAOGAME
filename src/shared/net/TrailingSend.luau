--!strict
--[[
	TrailingSend: paces a client request that carries a state (the lock-on target, a held guard)
	so the server always ends up with the client's last state.

		local sender = TrailingSend.new({
			gap = TrailingSend.gapOf("TargetRequest"),
			burst = 1, -- optional: sends that may go out back to back (default 1)
			now = os.clock,
			schedule = function(seconds, fn) task.delay(seconds, fn) end,
			send = function(entityId) net.fire("TargetRequest", { entityId = entityId }) end,
		})
		sender:set(entityId) -- nil is a state too (no lock)

	Net drops a request over its remote's rate (world.luau anticheat.remoteRates) without a word,
	so firing on every change can lose the last one: mashing the lock key can end on an unlock the
	server never hears. Here the client keeps its own copy of a token bucket: `burst` sends, one
	more every `gap`. A change sends at once while the bucket has a send; otherwise one send is
	scheduled for when it has one again, and it carries whatever the state is by then. Only one
	send is ever pending. So the client never sends faster than the remote refills, the rest of
	the server's burst is left for network bunching, and the last change always goes out.

	With burst 1 every send waits a whole gap after the one before. A guard tap (raise, then
	release 20 ms later) needs burst 2: the server starts its parry rearm clock when the release
	arrives, so a release held back to the end of the gap would refuse the next parry.

	The bucket is kept as the time its next send is due (`due`): a send at t may go out when
	t >= due - (burst - 1) * gap, and then pushes due to max(due, t) + gap. Pure: the clock, the
	scheduler and the send come in, so Lune drives it on a fake clock.
]]

local World = require(script.Parent.Parent.data.world)

export type Options = {
	gap: number, -- seconds between two sends once the burst is spent (1 / the remote's perSecond)
	burst: number?, -- sends that may go out back to back (default 1; keep it inside the server's burst)
	now: () -> number, -- the client clock, in seconds
	schedule: (seconds: number, fn: () -> ()) -> (), -- runs fn once, `seconds` from now (task.delay)
	send: (state: any) -> (), -- fires the request for a state
}

export type TrailingSend = {
	set: (self: TrailingSend, state: any) -> (),
	isPending: (self: TrailingSend) -> boolean,
}

local TrailingSend = {}
TrailingSend.__index = TrailingSend

--- The shortest time between two sends a remote's rate limit allows: 1 / its perSecond.
function TrailingSend.gapOf(remoteName: string): number
	local rate = World.anticheat.remoteRates[remoteName]
	if rate == nil then
		error(("TrailingSend: no anticheat.remoteRates entry for '%s'"):format(remoteName), 2)
	end
	return 1 / rate.perSecond
end

--- A sender that has sent nothing yet, so its first `burst` changes go out at once.
function TrailingSend.new(options: Options): TrailingSend
	local burst = options.burst or 1
	if burst < 1 then
		error(("TrailingSend: burst must be at least 1 send (got %s)"):format(tostring(burst)), 2)
	end
	local self = setmetatable({
		gap = options.gap,
		burst = burst,
		now = options.now,
		schedule = options.schedule,
		send = options.send,
		state = nil :: any, -- the latest state set
		due = nil :: number?, -- when the bucket is full again (nil: it is full)
		pending = false, -- a trailing send is scheduled
	}, TrailingSend)
	return (self :: any) :: TrailingSend
end

local function sendNow(self: any)
	local t = self.now()
	local due: number? = self.due
	self.due = math.max(due or t, t) + self.gap
	self.send(self.state)
end

--- Records a new state and sends it now, or once the bucket has a send again.
function TrailingSend.set(self: any, state: any)
	self.state = state
	if self.pending then
		-- The scheduled send reads the state when it goes out.
		return
	end
	local due: number? = self.due
	local wait = if due == nil then 0 else due - (self.burst - 1) * self.gap - self.now()
	if wait <= 0 then
		sendNow(self)
		return
	end
	self.pending = true
	self.schedule(wait, function()
		self.pending = false
		sendNow(self)
	end)
end

--- True while a trailing send is scheduled.
function TrailingSend.isPending(self: any): boolean
	return self.pending
end

return TrailingSend
