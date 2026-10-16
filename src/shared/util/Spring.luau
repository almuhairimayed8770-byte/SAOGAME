--!strict
--[[
	Spring: a critically-damped-or-better numeric spring used by the camera follow, the FOV,
	the hit nudge and Choreo settles. Works on numbers and on Vector3 (anything with +, -, *).
]]

local Spring = {}
Spring.__index = Spring

export type Spring<T> = {
	position: T,
	velocity: T,
	target: T,
	stiffness: number,
	damping: number,
	Step: (self: Spring<T>, dt: number) -> T,
	Impulse: (self: Spring<T>, impulse: T) -> (),
	Snap: (self: Spring<T>, value: T) -> (),
}

--- Creates a spring at `initial`. `stiffness` is the angular frequency squared; `damping` 1 is critical.
function Spring.new<T>(initial: T, stiffness: number, damping: number): Spring<T>
	local self = setmetatable({
		position = initial,
		velocity = (initial :: any) * 0,
		target = initial,
		stiffness = stiffness,
		damping = damping,
	}, Spring)
	return (self :: any) :: Spring<T>
end

--- Semi-implicit Euler step; stable for the stiffness values used in camera data.
function Spring.Step(self: any, dt: number): any
	local omega = math.sqrt(self.stiffness)
	local displacement = self.position - self.target
	local acceleration = -self.stiffness * displacement - 2 * self.damping * omega * self.velocity
	self.velocity = self.velocity + acceleration * dt
	self.position = self.position + self.velocity * dt
	return self.position
end

--- Adds velocity; used for the hit nudge and shake.
function Spring.Impulse(self: any, impulse: any)
	self.velocity = self.velocity + impulse
end

--- Moves the spring to a value with zero velocity (teleports, respawns).
function Spring.Snap(self: any, value: any)
	self.position = value
	self.target = value
	self.velocity = value * 0
end

return Spring
