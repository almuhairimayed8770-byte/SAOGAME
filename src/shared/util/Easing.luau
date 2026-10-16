--!strict
--[[
	Easing curves for Choreo keys and camera moves.

	Section 10: expo-out for snaps, back-out for overshoot, spring for settles. Linear is here
	for the root and the camera only; the clip validator rejects Linear on a limb.
	Every function maps t in [0, 1] to a progress value (Spring and BackOut overshoot past 1).
]]

local Easing = {}

local BACK_OVERSHOOT = 1.70158 -- standard back-out constant; ~10% overshoot
local SPRING_DECAY = 6 -- how fast the spring settle dies out
local SPRING_CYCLES = 1.5 -- oscillations across the key

function Easing.Linear(t: number): number
	return t
end

function Easing.Hold(t: number): number
	return if t >= 1 then 1 else 0
end

function Easing.ExpoOut(t: number): number
	if t >= 1 then
		return 1
	end
	return 1 - 2 ^ (-10 * t)
end

function Easing.ExpoIn(t: number): number
	if t <= 0 then
		return 0
	end
	return 2 ^ (10 * (t - 1))
end

function Easing.BackOut(t: number): number
	local u = t - 1
	return 1 + u * u * ((BACK_OVERSHOOT + 1) * u + BACK_OVERSHOOT)
end

function Easing.QuadIn(t: number): number
	return t * t
end

function Easing.QuadOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

function Easing.SineInOut(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

--- Damped spring: overshoots the key, rings, and settles to 1 at t = 1.
function Easing.Spring(t: number): number
	if t >= 1 then
		return 1
	end
	return 1 - math.exp(-SPRING_DECAY * t) * math.cos(SPRING_CYCLES * 2 * math.pi * t)
end

--- Looks up a curve by its data-table name; errors on an unknown name so bad data fails loudly.
function Easing.get(name: string): (number) -> number
	local curve = (Easing :: any)[name]
	if typeof(curve) ~= "function" then
		error(("unknown easing '%s'"):format(name))
	end
	return curve
end

--- Evaluates a named curve, clamping t to [0, 1] first.
function Easing.evaluate(name: string, t: number): number
	return Easing.get(name)(math.clamp(t, 0, 1))
end

return Easing
