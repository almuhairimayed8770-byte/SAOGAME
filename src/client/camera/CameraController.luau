--!strict
--[[
	CameraController (section 10): a Scriptable third-person camera driven on RenderStepped. A
	spring on the position gives the 0.12 s follow lag; the orbit comes from the mouse, the right
	stick or a touch drag; the FOV sits on its own spring at 60 degrees and kicks +8 on Art
	activation and dashes; `nudge` is an impulse on the position spring toward a hit point; `shake`
	is summed-sine noise with a fast exponential decay; lock-on frames both fighters from behind
	the player; Duel and Raid presets change the orbit; a spherecast from the focus pulls the
	camera in front of walls. Every number is in camera.luau; the math is in CameraMath (tested).
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CameraData = require(Shared.data.camera)
local Spring = require(Shared.util.Spring)
local CameraMath = require(script.Parent.CameraMath)

export type Mode = "Default" | "Duel" | "Raid"
export type KickKind = "Art" | "Dash"

local RENDER_STEP_NAME = "SkyspireCamera"

type Scripted = { frames: { CFrame }, duration: number, elapsed: number }
type BlendBack = { from: CFrame, elapsed: number }

local CameraController = {}

local mode: Mode = "Default"
local yaw = 0
local pitch = CameraData.orbit.Default.pitch
local zoomOffset = 0
local lockTarget: Model? = nil
local subject: Model? = nil
local mouseCaptured = UserInputService.MouseEnabled and not UserInputService.TouchEnabled
local mobile = UserInputService.TouchEnabled
local gamepadLook = Vector2.zero

local followStiffness = CameraMath.springFromLag(CameraData.follow.lag)
local positionSpring: Spring.Spring<Vector3>? = nil
local fovSpring = Spring.new(CameraData.fov.rest, CameraMath.springFromLag(CameraData.fov.lag), CameraData.fov.damping)
local yawSpring = Spring.new(0, CameraMath.springFromLag(CameraData.lock.yawLag), CameraData.follow.damping)
local distanceSpring = Spring.new(
	CameraData.orbit.Default.distance,
	CameraMath.springFromLag(CameraData.collision.pullOutLag),
	CameraData.follow.damping
)
local fovKickAmount = 0
local shakeEnergy = 0
local shakeTime = 0
local scripted: Scripted? = nil
local blendBack: BlendBack? = nil
local raycastParams: RaycastParams? = nil
local started = false

local function toVector(v: { number }): Vector3
	local x, y, z = table.unpack(v)
	return Vector3.new(x, y, z)
end

local function toTable(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function subjectRoot(): BasePart?
	local model = subject
	if model == nil then
		return nil
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function lockRoot(): BasePart?
	local model = lockTarget
	if model == nil or model.Parent == nil then
		return nil
	end
	local root = model.PrimaryPart
	return if root ~= nil then root else nil
end

local function orbitDistance(): number
	local orbit = CameraData.orbit[mode]
	return math.clamp(orbit.distance + zoomOffset, CameraData.zoom.min, CameraData.zoom.max)
end

local function applyLook(dx: number, dy: number, degreesPerUnit: number)
	yaw, pitch = CameraMath.applyLook(
		yaw,
		pitch,
		dx,
		dy,
		degreesPerUnit,
		CameraData.input.invertY,
		CameraData.pitch.min,
		CameraData.pitch.max
	)
end

local function stepScripted(dt: number, camera: Camera)
	local shot = scripted :: Scripted
	local index, alpha = CameraMath.scriptedSample(#shot.frames, shot.duration, shot.elapsed)
	local from = shot.frames[index]
	local to = shot.frames[index + 1] or from
	camera.CFrame = from:Lerp(to, CameraMath.easeBlend(alpha, 1))
	shot.elapsed += dt
	if shot.elapsed >= shot.duration then
		scripted = nil
		blendBack = { from = camera.CFrame, elapsed = 0 }
		if positionSpring ~= nil then
			positionSpring:Snap(camera.CFrame.Position)
		end
	end
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	UserInputService.MouseBehavior = if mouseCaptured then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default

	-- FOV: rest plus a decaying kick, on its own spring.
	fovKickAmount = CameraMath.decay(fovKickAmount, CameraData.fov.kickDecay, dt)
	fovSpring.target = CameraData.fov.rest + fovKickAmount + (if mobile then CameraData.mobile.fovAdd else 0)
	camera.FieldOfView = fovSpring:Step(dt)

	if scripted ~= nil then
		stepScripted(dt, camera)
		return
	end

	local root = subjectRoot()
	if root == nil then
		return
	end

	-- Right stick: integrate the held deflection.
	if gamepadLook.Magnitude > 0 then
		local perSecond = CameraData.input.gamepadDegreesPerSecond
		applyLook(gamepadLook.X * dt, -gamepadLook.Y * dt, perSecond)
	end

	local orbit = CameraData.orbit[mode]
	local focus = root.Position + Vector3.yAxis * CameraData.follow.focusHeight
	local lookAt = focus
	local distance = orbitDistance()
	local height, side, usePitch = orbit.height, orbit.side, pitch

	local targetRoot = lockRoot()
	if targetRoot ~= nil then
		local lock = CameraData.lock
		local frame = CameraMath.lockFrame(toTable(root.Position), toTable(targetRoot.Position), lock)
		yawSpring.target = yawSpring.position + CameraMath.shortestDelta(yawSpring.position, frame.yaw)
		yaw = CameraMath.wrapDegrees(yawSpring:Step(dt))
		lookAt = toVector(CameraMath.raise(frame.focus, CameraData.follow.focusHeight))
		distance = frame.distance
		height, side = lock.height, lock.side
		usePitch = pitch + (lock.pitch - orbit.pitch)
	else
		yawSpring:Snap(yaw)
	end

	if mobile then
		distance *= CameraData.mobile.distanceMultiplier
		usePitch += CameraData.mobile.pitchAdd
	end

	local offset = toVector(CameraMath.orbitOffset(yaw, usePitch, distance, height, side))
	local direction = offset
	local length = direction.Magnitude
	if length > CameraData.epsilon and raycastParams ~= nil then
		local result = workspace:Spherecast(focus, CameraData.collision.probeRadius, direction, raycastParams)
		local hitDistance = if result ~= nil then result.Distance else nil
		local allowed = CameraMath.collisionDistance(
			length,
			hitDistance,
			CameraData.collision.probeRadius,
			CameraData.collision.minDistance
		)
		-- Pull in instantly in front of a wall; ease back out.
		if allowed < distanceSpring.position then
			distanceSpring:Snap(allowed)
		else
			distanceSpring.target = allowed
			distanceSpring:Step(dt)
		end
		direction = direction.Unit * distanceSpring.position
	end
	local desired = focus + direction

	local spring = positionSpring
	if spring == nil then
		spring = Spring.new(desired, followStiffness, CameraData.follow.damping)
		positionSpring = spring
	end
	local follow = spring :: Spring.Spring<Vector3>
	if (desired - follow.position).Magnitude > CameraData.follow.snapDistance then
		follow:Snap(desired)
	end
	follow.target = desired
	local position = follow:Step(dt)

	-- Shake: noise scaled by a decaying energy, in the camera's own axes.
	shakeEnergy = CameraMath.decay(shakeEnergy, CameraData.shake.decay, dt)
	if shakeEnergy < CameraData.shake.cutoff then
		shakeEnergy = 0
	end
	shakeTime += dt
	local shakeVector = Vector3.zero
	if shakeEnergy > 0 then
		local sx, sy, sz = table.unpack(
			CameraMath.shakeOffset(shakeTime, shakeEnergy, CameraData.shake.frequency, CameraData.shake.lanes)
		)
		local current = camera.CFrame
		shakeVector = current.RightVector * sx + current.UpVector * sy + current.LookVector * sz
	end

	local followCFrame = CFrame.lookAt(position + shakeVector, lookAt + shakeVector)
	local back = blendBack
	if back ~= nil then
		local alpha = CameraMath.easeBlend(back.elapsed, CameraData.scripted.blendOut)
		back.elapsed += dt
		followCFrame = back.from:Lerp(followCFrame, alpha)
		if alpha >= 1 then
			blendBack = nil
		end
	end
	camera.CFrame = followCFrame
	camera.Focus = CFrame.new(lookAt)
end

-- ------------------------------------------------------------------ public API

--- Pushes the camera toward `toward` so it peaks `studs` away from its path (every hit, section 10).
function CameraController.nudge(toward: Vector3, studs: number)
	local spring = positionSpring
	if spring == nil then
		return
	end
	local direction = toward - spring.position
	if direction.Magnitude <= CameraData.epsilon then
		return
	end
	spring:Impulse(direction.Unit * CameraMath.impulseForDisplacement(studs, followStiffness))
end

--- Starts (or raises) a shake at the tier's amplitude; it decays on its own.
function CameraController.shake(tier: string)
	local amplitude = CameraData.shake.amplitude[tier] or CameraData.shake.amplitude.Normal
	shakeEnergy = math.max(shakeEnergy, amplitude)
end

--- Kicks the FOV by the Art or dash amount; the kick decays back to rest.
function CameraController.fovKick(kind: KickKind?)
	local amount = if kind == "Dash" then CameraData.fov.dashKick else CameraData.fov.artKick
	fovKickAmount = math.max(fovKickAmount, amount)
end

--- Locks the framing on a model (nil clears it).
function CameraController.setLockTarget(model: Model?)
	lockTarget = model
	yawSpring:Snap(yaw)
end

--- Switches the orbit preset.
function CameraController.setMode(newMode: Mode)
	if CameraData.orbit[newMode] == nil then
		error(("CameraController: unknown mode '%s'"):format(tostring(newMode)))
	end
	local previous = CameraData.orbit[mode]
	mode = newMode
	pitch = pitch + (CameraData.orbit[newMode].pitch - previous.pitch)
end

--- Plays a list of CFrames over `duration` seconds (boss entrances), then eases back to the follow.
function CameraController.scripted(cframeList: { CFrame }, duration: number)
	if #cframeList == 0 then
		return
	end
	scripted = { frames = cframeList, duration = duration, elapsed = 0 }
end

--- Sets which model the camera follows (the local character by default).
function CameraController.setSubject(model: Model?)
	subject = model
	if raycastParams ~= nil then
		raycastParams.FilterDescendantsInstances = if model ~= nil then { model } else {}
	end
	local spring = positionSpring
	local root = subjectRoot()
	if spring ~= nil and root ~= nil then
		spring:Snap(root.Position + toVector(CameraMath.orbitOffset(yaw, pitch, orbitDistance(), 0, 0)))
	end
end

--- Captures the mouse (LockCenter orbit) or releases it for menus.
function CameraController.setMouseCaptured(captured: boolean)
	mouseCaptured = captured
end

--- The current yaw and pitch in degrees.
function CameraController.orientation(): (number, number)
	return yaw, pitch
end

--- The current mode.
function CameraController.mode(): Mode
	return mode
end

local function onInputChanged(input: InputObject, processed: boolean)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseMovement then
		if mouseCaptured then
			applyLook(input.Delta.X, input.Delta.Y, CameraData.input.mouseDegreesPerPixel)
		end
	elseif inputType == Enum.UserInputType.MouseWheel then
		zoomOffset = math.clamp(
			zoomOffset - input.Position.Z * CameraData.zoom.step,
			CameraData.zoom.min - CameraData.orbit[mode].distance,
			CameraData.zoom.max - CameraData.orbit[mode].distance
		)
	elseif inputType == Enum.UserInputType.Touch then
		if not processed then
			applyLook(input.Delta.X, input.Delta.Y, CameraData.input.touchDegreesPerPixel)
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		local position = Vector2.new(input.Position.X, input.Position.Y)
		gamepadLook = if position.Magnitude >= CameraData.input.gamepadDeadzone then position else Vector2.zero
	end
end

--- Binds the RenderStepped loop, input and the local character.
function CameraController.start()
	if started then
		return
	end
	started = true
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	raycastParams = params
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function(model)
		CameraController.setSubject(model)
	end)
	player.CharacterRemoving:Connect(function()
		CameraController.setSubject(nil)
	end)
	if player.Character ~= nil then
		CameraController.setSubject(player.Character)
	end
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if inputType == Enum.UserInputType.Touch then
			mobile = true
			mouseCaptured = false
		elseif inputType == Enum.UserInputType.Keyboard or inputType == Enum.UserInputType.MouseMovement then
			mouseCaptured = true
		end
	end)
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value, step)
end

return CameraController
