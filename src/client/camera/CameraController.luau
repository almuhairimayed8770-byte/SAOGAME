--!strict
--[[
	CameraController (section 10): a Scriptable third-person camera driven on RenderStepped. A
	spring on the position gives the 0.12 s follow lag; the orbit comes from the mouse, the right
	stick or a touch drag; the FOV sits on its own spring at 60 degrees and kicks +8 on Art
	activation and dashes; `punch` narrows it a few degrees on an Art's final hit or a kill, eased
	in and sprung back (CameraMath.punchOffset), added after the FOV spring so the kick's spring
	and the shake are untouched; `nudge` is an impulse on the position spring toward a hit point; `shake`
	is summed-sine noise with a fast exponential decay; lock-on frames both fighters from behind
	the player; Duel and Raid presets change the orbit; a spherecast from the focus pulls the
	camera in front of walls. Every number is in camera.luau; the math is in CameraMath (tested).

	Render stalls (a display asleep, a minimised window, a long hitch: RenderStepped stops while the
	game goes on): every step runs on the real time since the last one, whatever dt the engine
	reports for the frame that comes back. The punch, the kicks and the shake are timed from when
	they were asked for, so one asked for before a stall is over by the frame after it, never
	replayed. The springs integrate the gap in pieces of at most camera.stall.maxStepSeconds (a
	semi-implicit Euler step thrown by a long one would fling the camera), and past
	camera.stall.settleSeconds they snap where they would have settled, a nudge's push included.
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
-- The kick and the shake: their size when last asked for and when (os.clock); each decays from there.
local kickPeak = 0
local kickAt = 0
local shakePeak = 0
local shakeAt = 0
-- The punch showing: its numbers, when it was asked for and the offset it started from (a punch
-- over a punch eases on from where the first one is).
local punchParams: CameraMath.PunchParams? = nil
local punchAt = 0
local punchFrom = 0
local shakeTime = 0
local lastStepAt: number? = nil -- os.clock of the last render step
local scripted: Scripted? = nil
local blendBack: BlendBack? = nil
local raycastParams: RaycastParams? = nil
local started = false

-- The clock every transient is timed on (monotonic seconds).
local function now(): number
	return os.clock()
end

-- The FOV kick at `at`: its size when asked for, decayed since (never linearly).
local function kickValue(at: number): number
	return CameraMath.decay(kickPeak, CameraData.fov.kickDecay, math.max(at - kickAt, 0))
end

-- The shake energy at `at`: its size when asked for, decayed since; zero under the cutoff.
local function shakeValue(at: number): number
	local energy = CameraMath.decay(shakePeak, CameraData.shake.decay, math.max(at - shakeAt, 0))
	return if energy < CameraData.shake.cutoff then 0 else energy
end

-- The punch's FOV offset at `at` (0 with none showing); a punch that has settled is let go.
local function punchValue(at: number): number
	local params = punchParams
	if params == nil then
		return 0
	end
	local offset, done = CameraMath.punchOffset(at - punchAt, params, punchFrom)
	if done then
		punchParams = nil
		return 0
	end
	return offset
end

-- Steps a spring over `span` seconds in pieces of at most camera.stall.maxStepSeconds, or snaps it
-- to its target when `settle` (a stall past camera.stall.settleSeconds). Returns its position.
local function advanceSpring<T>(spring: Spring.Spring<T>, span: number, settle: boolean): T
	if settle then
		spring:Snap(spring.target)
		return spring.position
	end
	local pieces = math.max(1, math.ceil(span / CameraData.stall.maxStepSeconds))
	local piece = span / pieces
	for _ = 1, pieces do
		spring:Step(piece)
	end
	return spring.position
end

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
	-- The real time since the last frame: the engine's dt, or the clock's gap when the engine
	-- reports less (the first frame after a stall may say one frame).
	local at = now()
	local gap = if lastStepAt ~= nil then at - (lastStepAt :: number) else dt
	lastStepAt = at
	local span = math.max(dt, gap, 0)
	local settle = span > CameraData.stall.settleSeconds
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	UserInputService.MouseBehavior = if mouseCaptured then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default

	-- FOV: rest plus a decaying kick, on its own spring.
	fovSpring.target = CameraData.fov.rest + kickValue(at) + (if mobile then CameraData.mobile.fovAdd else 0)
	-- The punch rides on top of the spring: the spring would smooth a 3-frame push away.
	camera.FieldOfView = advanceSpring(fovSpring, span, settle) + punchValue(at)

	if scripted ~= nil then
		stepScripted(span, camera)
		return
	end

	local root = subjectRoot()
	if root == nil then
		return
	end

	-- Right stick: integrate the held deflection over the frame (never over a stall).
	if gamepadLook.Magnitude > 0 and not settle then
		local perSecond = CameraData.input.gamepadDegreesPerSecond
		applyLook(gamepadLook.X * span, -gamepadLook.Y * span, perSecond)
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
		yaw = CameraMath.wrapDegrees(advanceSpring(yawSpring, span, settle))
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
			advanceSpring(distanceSpring, span, settle)
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
	local position = advanceSpring(follow, span, settle)

	-- Shake: noise scaled by a decaying energy, in the camera's own axes.
	local shakeEnergy = shakeValue(at)
	shakeTime += span
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
		back.elapsed += span
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

--- Starts (or raises) a shake at the tier's amplitude; it decays on its own from now.
function CameraController.shake(tier: string)
	local amplitude = CameraData.shake.amplitude[tier] or CameraData.shake.amplitude.Normal
	local at = now()
	shakePeak = math.max(shakeValue(at), amplitude)
	shakeAt = at
end

--- Kicks the FOV by the Art or dash amount; the kick decays back to rest from now.
function CameraController.fovKick(kind: KickKind?)
	local amount = if kind == "Dash" then CameraData.fov.dashKick else CameraData.fov.artKick
	local at = now()
	kickPeak = math.max(kickValue(at), amount)
	kickAt = at
end

--- Pushes the FOV in by camera.luau punch[kind] ("Final" | "Kill"), eased in and sprung back; a
--- punch over a punch starts from the offset showing now, so the FOV never jumps.
function CameraController.punch(kind: string)
	local params = CameraData.punch[kind]
	if params == nil then
		return
	end
	local at = now()
	punchFrom = punchValue(at)
	punchParams = params
	punchAt = at
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
