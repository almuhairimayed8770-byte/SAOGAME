--!strict
--[[
	Engine: the few engine handles the fx / ui / audio modules share (the viewer position, the
	Heartbeat signal, the local player, pooled-part folders), each behind a pcall so the same
	modules load under Lune where the services are bare stubs. Tests replace the viewer through
	`Engine.setViewer` and never touch the camera.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Engine = {}

local viewerOverride: (() -> Vector3?)? = nil
local clockOverride: (() -> number)? = nil
local folders: { [string]: Instance } = {}

--- The Heartbeat signal, or nil when the engine is not running (Lune).
function Engine.heartbeat(): RBXScriptSignal?
	local ok, signal = pcall(function()
		return (RunService :: any).Heartbeat
	end)
	if ok and typeof(signal) == "RBXScriptSignal" then
		return signal
	end
	return nil
end

--- Connects `fn(dt)` to Heartbeat when it exists; returns a disconnect function (a no-op under Lune).
function Engine.onHeartbeat(fn: (dt: number) -> ()): () -> ()
	local signal = Engine.heartbeat()
	if signal == nil then
		return function() end
	end
	local connection = signal:Connect(fn)
	return function()
		connection:Disconnect()
	end
end

--- Monotonic seconds (every fade, flash and crossfade in the package reads time through here).
function Engine.now(): number
	if clockOverride ~= nil then
		return clockOverride()
	end
	return os.clock()
end

--- Replaces the clock (tests step fades by hand); nil restores the real one.
function Engine.setClock(fn: (() -> number)?)
	clockOverride = fn
end

--- The current camera, or nil.
function Engine.camera(): Camera?
	local ok, camera = pcall(function()
		return (workspace :: any).CurrentCamera
	end)
	if ok and typeof(camera) == "Instance" then
		return camera :: Camera
	end
	return nil
end

--- Replaces where the viewer position comes from (tests, spectator cameras).
function Engine.setViewer(fn: (() -> Vector3?)?)
	viewerOverride = fn
end

--- Where the viewer is: the camera position, or nil when there is no camera.
function Engine.viewerPosition(): Vector3?
	if viewerOverride ~= nil then
		return viewerOverride()
	end
	local camera = Engine.camera()
	if camera == nil then
		return nil
	end
	local ok, position = pcall(function()
		return (camera :: any).CFrame.Position
	end)
	if ok and typeof(position) == "Vector3" then
		return position
	end
	return nil
end

--- Studs from the viewer to a position (a large number when there is no viewer).
function Engine.distanceTo(position: Vector3): number
	local viewer = Engine.viewerPosition()
	if viewer == nil then
		return 1e6
	end
	return (position - viewer).Magnitude
end

--- The local player, or nil (server, Lune).
function Engine.localPlayer(): Player?
	local ok, player = pcall(function()
		return (Players :: any).LocalPlayer
	end)
	if ok and typeof(player) == "Instance" then
		return player :: Player
	end
	return nil
end

--- The local PlayerGui, or nil.
function Engine.playerGui(): Instance?
	local player = Engine.localPlayer()
	if player == nil then
		return nil
	end
	local ok, gui = pcall(function()
		return player:FindFirstChildOfClass("PlayerGui")
	end)
	if ok and typeof(gui) == "Instance" then
		return gui
	end
	return nil
end

--- True on a touch device.
function Engine.isTouch(): boolean
	local ok, touch = pcall(function()
		return (game:GetService("UserInputService") :: any).TouchEnabled
	end)
	return ok and touch == true
end

--- A named Folder under `parent` for pooled parts, created once; detached under Lune.
function Engine.folder(parent: Instance, name: string): Instance
	local key = tostring(parent) .. "/" .. name
	local existing: Instance? = folders[key]
	if existing ~= nil then
		return existing
	end
	local found: Instance? = nil
	pcall(function()
		found = parent:FindFirstChild(name)
	end)
	if found ~= nil then
		folders[key] = found :: Instance
		return found :: Instance
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	pcall(function()
		folder.Parent = parent
	end)
	folders[key] = folder
	return folder
end

--- Calls `fn` once when `instance` leaves the DataModel (destroyed by the server, or unparented),
--- so pools and per-rig tables let go of rigs that are gone. Returns a disconnect function (a
--- no-op under Lune, where instances have no AncestryChanged signal).
function Engine.onRemoved(instance: Instance, fn: () -> ()): () -> ()
	local connection: RBXScriptConnection? = nil
	local ok = pcall(function()
		connection = (instance :: any).AncestryChanged:Connect(function(_child: Instance, parent: Instance?)
			if parent ~= nil and instance:IsDescendantOf(game) then
				return
			end
			if connection ~= nil then
				connection:Disconnect()
				connection = nil
			end
			fn()
		end)
	end)
	if not ok then
		return function() end
	end
	return function()
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
	end
end

--- The world position of a model (its PrimaryPart, else its first BasePart), or nil.
function Engine.modelPosition(model: Instance?): Vector3?
	if model == nil then
		return nil
	end
	local primary: Instance? = nil
	pcall(function()
		primary = (model :: any).PrimaryPart
	end)
	if primary == nil then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				primary = descendant
				break
			end
		end
	end
	if primary == nil then
		return nil
	end
	local ok, position = pcall(function()
		return (primary :: any).CFrame.Position
	end)
	if ok and typeof(position) == "Vector3" then
		return position
	end
	return nil
end

--- Every BasePart under a model.
function Engine.parts(model: Instance): { BasePart }
	local list = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

--- A plain {x, y, z} from a Vector3 (for the pure math modules).
function Engine.toTable(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

--- A Vector3 from a plain {x, y, z}.
function Engine.toVector(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

return Engine
