--!strict
--[[
	MoveInput: the stick, as the player's control module reads it, in world space.

		local stick = MoveInput.world(humanoid) -- unit length, or zero while the stick is let go

	The control module (PlayerModule:GetControls()) has one active controller for the device in
	use: the keyboard, a gamepad, or a touch thumbstick or dynamic thumbstick. Its GetMoveVector is
	the stick that controller reads, relative to the camera for every one of them. The control
	module turns it onto the camera's yaw before it Moves the Humanoid (its calculateRawMoveVector:
	the camera's back vector flattened, or its right and up vectors while it looks straight up or
	down); this does the same, and answers it as Humanoid.MoveDirection describes a move: unit
	length, or zero.

	Humanoid.MoveDirection is not the stick: it is the last Humanoid:Move, and the character
	controller Moves the Humanoid itself (the two-step stop's carry, the lock's frame, the body
	shell). While a controller is active the control module Moves first every frame and overwrites
	that; with none active (the controls disabled, a menu) nothing does, and the stop's carry read
	its own Move back as a held stick and walked the body on at its walk speed for as long as the
	controls stayed off (D-474).

	A place with no control module (no default PlayerModule) answers the Humanoid's MoveDirection,
	as before. `bind` replaces the control module and the camera (specs); nil restores them.
]]

local Players = game:GetService("Players")

-- The control module's surface this reads (PlayerModule ControlModule).
type Controls = {
	GetMoveVector: (self: any) -> Vector3,
	GetActiveController: ((self: any) -> any)?,
}

export type Deps = {
	-- The control module, nil while there is none to read (the Humanoid's MoveDirection answers).
	controls: () -> any,
	-- The current camera's CFrame, nil with no camera (the move vector is taken as world space).
	camera: () -> CFrame?,
}

local MoveInput = {}

-- The default control module: found in the local player's PlayerScripts on first use, and looked
-- for again only while the PlayerModule is not there yet; a PlayerModule that fails to load (or has
-- no GetControls) is given up on, never retried each frame.
local controlsFound: any = nil
local controlsFailed = false

local function defaultControls(): any
	if controlsFound ~= nil or controlsFailed then
		return controlsFound
	end
	-- No local player outside a client (a Lune spec's DataModel has none to index).
	local hasPlayer, player = pcall(function(): Player?
		return Players.LocalPlayer
	end)
	local scripts = if hasPlayer and player ~= nil then player:FindFirstChildOfClass("PlayerScripts") else nil
	local module = if scripts ~= nil then scripts:FindFirstChild("PlayerModule") else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, loaded = pcall(function(): any
		return (require :: any)(module)
	end)
	if not ok or typeof(loaded) ~= "table" or typeof(loaded.GetControls) ~= "function" then
		controlsFailed = true
		return nil
	end
	local gotControls, controls = pcall(function(): any
		return loaded:GetControls()
	end)
	if not gotControls or typeof(controls) ~= "table" or typeof(controls.GetMoveVector) ~= "function" then
		controlsFailed = true
		return nil
	end
	controlsFound = controls
	return controls
end

local function defaultCamera(): CFrame?
	local camera = workspace.CurrentCamera
	return if camera ~= nil then camera.CFrame else nil
end

local deps: Deps = { controls = defaultControls, camera = defaultCamera }

--- Replaces the control module or the camera (specs); nil restores the engine's.
function MoveInput.bind(overrides: { controls: (() -> any)?, camera: (() -> CFrame?)? }?)
	deps = {
		controls = if overrides ~= nil and overrides.controls ~= nil then overrides.controls else defaultControls,
		camera = if overrides ~= nil and overrides.camera ~= nil then overrides.camera else defaultCamera,
	}
end

--- A camera-relative move vector in world space, as the control module turns it before it Moves
--- the Humanoid (calculateRawMoveVector): on the camera's yaw, from its back vector, or from its
--- right and up vectors while it looks straight up or down.
function MoveInput.toWorld(relative: Vector3, camera: CFrame): Vector3
	local _, _, _, r00, r01, r02, _, _, r12, _, _, r22 = camera:GetComponents()
	local c, s
	if r12 < 1 and r12 > -1 then
		c, s = r22, r02
	else
		c, s = r00, -r01 * math.sign(r12)
	end
	local norm = math.sqrt(c * c + s * s)
	if norm < 1e-6 then
		return Vector3.new(relative.X, 0, relative.Z)
	end
	return Vector3.new((c * relative.X + s * relative.Z) / norm, 0, (c * relative.Z - s * relative.X) / norm)
end

-- Unit length, or zero (as Humanoid.MoveDirection describes a move).
local function direction(move: Vector3): Vector3
	local flat = Vector3.new(move.X, 0, move.Z)
	local length = flat.Magnitude
	if length < 1e-6 then
		return Vector3.zero
	end
	return flat / length
end

--- The stick this frame in world space: unit length, or zero while it is let go (or no controller
--- is active). With no control module, the Humanoid's MoveDirection.
function MoveInput.world(humanoid: Humanoid): Vector3
	local controls = deps.controls() :: Controls?
	if controls == nil then
		return humanoid.MoveDirection
	end
	local move = controls:GetMoveVector()
	if move.Magnitude < 1e-6 then
		return Vector3.zero
	end
	-- Every stick controller's vector is camera-relative; one that says otherwise (a scripted
	-- MoveTo's path) is already in world space.
	local relative = true
	local active: any = nil
	local getActive = controls.GetActiveController
	if typeof(getActive) == "function" then
		active = getActive(controls)
	end
	if typeof(active) == "table" and typeof(active.IsMoveVectorCameraRelative) == "function" then
		relative = active:IsMoveVectorCameraRelative() ~= false
	end
	local camera = if relative then deps.camera() else nil
	return direction(if camera ~= nil then MoveInput.toWorld(move, camera) else move)
end

return MoveInput
