--!strict
--[[
	FrameClock: frame-counted callbacks for the two- and three-frame flashes (section 10 beat 4,
	section 11). "N frames" means N rendered frames, so the flash reads the same at any frame
	rate the player actually gets; under Lune (no Heartbeat) it falls back to the 60 fps frame
	length from combat.luau through task.delay so the same code runs in tests.

	One Heartbeat connection serves every pending callback; there is nothing per frame when
	nothing is pending.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage.Shared

local Combat = require(Shared.data.combat)

export type Cancel = () -> ()

type Pending = { remaining: number, fn: () -> (), cancelled: boolean }

local FrameClock = {}

local pending: { Pending } = {}
local connection: RBXScriptConnection? = nil

local function heartbeat(): RBXScriptSignal?
	local ok, signal = pcall(function()
		return (RunService :: any).Heartbeat
	end)
	if ok and typeof(signal) == "RBXScriptSignal" then
		return signal
	end
	return nil
end

local function step()
	for index = #pending, 1, -1 do
		local entry = pending[index]
		if entry.cancelled then
			table.remove(pending, index)
			continue
		end
		entry.remaining -= 1
		if entry.remaining <= 0 then
			table.remove(pending, index)
			local ok, err = pcall(entry.fn)
			if not ok then
				warn("[FrameClock] callback failed: " .. tostring(err))
			end
		end
	end
	if #pending == 0 and connection ~= nil then
		connection:Disconnect()
		connection = nil
	end
end

--- Runs `fn` after `frames` rendered frames (at least one). Returns a cancel function.
function FrameClock.after(frames: number, fn: () -> ()): Cancel
	local count = math.max(1, math.floor(frames + 0.5))
	local signal = heartbeat()
	if signal == nil then
		local thread = task.delay(count * Combat.hitStopFrameSeconds, fn)
		return function()
			pcall(task.cancel, thread)
		end
	end
	local entry: Pending = { remaining = count, fn = fn, cancelled = false }
	table.insert(pending, entry)
	if connection == nil then
		connection = signal:Connect(step)
	end
	return function()
		entry.cancelled = true
	end
end

--- Seconds that `frames` frames take at the reference frame rate (for durations, never for flashes).
function FrameClock.seconds(frames: number): number
	return frames * Combat.hitStopFrameSeconds
end

return FrameClock
