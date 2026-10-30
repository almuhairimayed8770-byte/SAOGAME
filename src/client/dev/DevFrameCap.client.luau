--!strict
--[[
	DevFrameCap: the Studio frame-rate cap (Studio item 303: a take at 30 frames a second, which
	Studio's own menu does not offer). Runs only in Studio (RunService:IsStudio()) in a place whose
	Workspace carries the DevCapture attribute; anywhere else it returns before it binds anything,
	and no shipping script requires it.

	While Workspace carries dev.luau frameCap.attribute as a number of frames a second from
	frameCap.least to frameCap.most, its render step (frameCap.priority: after every step that
	draws the frame, camera.luau renderOrder.late included) waits on os.clock until 1/cap seconds
	have passed since the last frame it let go. A frame that took longer goes at once, and the next
	is timed from it, so a slow frame never brings a burst after it. With no cap (no attribute, or
	one out of range) the step returns at once. Set it from the command bar:
	workspace:SetAttribute("DevFrameCap", 30); clear it with nil.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dev = require(Shared.data.dev)

if not RunService:IsStudio() or workspace:GetAttribute(Dev.attributes.capture) ~= true then
	return
end

local Cap = Dev.frameCap
local STEP_NAME = "SkyspireDevFrameCap"

-- The cap asked for, or nil when there is none in range.
local function capNow(): number?
	local value = workspace:GetAttribute(Cap.attribute)
	if typeof(value) ~= "number" or value ~= value or value < Cap.least or value > Cap.most then
		return nil
	end
	return value
end

-- When the last frame was let go (os.clock).
local released = os.clock()

RunService:BindToRenderStep(
	STEP_NAME,
	(Enum.RenderPriority :: any)[Cap.priority.base].Value + Cap.priority.offset,
	function()
		local cap = capNow()
		local now = os.clock()
		if cap ~= nil then
			local due = released + 1 / cap
			-- A busy wait: a task.wait would hand the frame back to the engine, which draws it.
			while now < due do
				now = os.clock()
			end
		end
		released = now
	end
)
