--!strict
--[[
	CameraController (section 10): a Scriptable third-person camera driven on RenderStepped. A
	spring on the position gives the 0.12 s follow lag; the orbit comes from the mouse, the right
	stick or a touch drag; the FOV sits on its own spring at 60 degrees and kicks +8 on Art
	activation and dashes; `punch` narrows it a few degrees on an Art's final hit or a kill, eased
	in and sprung back (CameraMath.punchOffset), added after the FOV spring so the kick's spring
	and the shake are untouched; `nudge` is an impulse on the follow spring toward a hit point; `shake`
	is summed-sine noise with a fast exponential decay; Duel and Raid presets change the orbit.
	Every number is in camera.luau; the math is in CameraMath (tested).

	Framing (D-145, D-146, D-149). Each frame builds a rig on the subject's pivot (root + focusHeight):
	where the camera sits and where it aims. The free rig sits low over the right shoulder
	(CameraMath.orbitOffset and shoulderLook: the aim shifted right and up with the camera, so the
	look-down is the pitch). A lock builds a two-shot (CameraMath.twoShot): the camera a little over
	the fighters' heads behind the player, swung off the line on a spring around the player just
	far enough to stand them side by side, aiming between them; the look input waits while it
	holds. A blend spring eases between the two rigs, so a lock (and the draw it brings) eases on
	and off, and a lock whose target is gone eases out from where the target was. The whole rig
	rides a lagged pivot (the 0.12 s follow) leashed along the view (CameraMath.leash): the camera
	and its aim move together, so a dodge never tilts the view, and a dodge toward the lens never
	brings it onto the player; and leashed across it (D-181), so a sideways dodge never carries the
	player toward the screen's edge.

	Walls (D-149): a spherecast from the true pivot to the camera spot. A hit on a character (any model
	holding a Humanoid: the player's own weapon, the lock target, other players), an accessory or a
	see-through part is looked past (CameraMath.blocksView) and the probe cast again. A wall pulls
	the rig in toward the pivot at once, the camera and its aim together (the view keeps its
	direction), and it eases back out.

	The contact frame (D-180). The camera steps at Camera priority (200), before the character
	controller (301) predicts a contact and asks for its nudge and shake. A late pass at Last
	priority shows a nudge or a shake asked for between the two on that same frame: the follow
	spring is linear, so the impulse's own response over the frame's time is added to the step that
	ran (exactly as if the impulse had come before it), and the frame is drawn again from the same
	rig, wall fraction and shake axes with the nudge's shift and the new shake. A frame with no such
	impulse is left exactly as the main step drew it, and an impulse asked for between frames (the
	network) shows on the next frame, as before.

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
local LATE_STEP_NAME = "SkyspireCameraLate"

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
-- The lagged pivot the rig rides on (leashed along and across the view when read).
local pivotSpring: Spring.Spring<Vector3>? = nil
local fovSpring = Spring.new(CameraData.fov.rest, CameraMath.springFromLag(CameraData.fov.lag), CameraData.fov.damping)
-- The two-shot camera's bearing around the player (degrees); on the free camera's while unlocked.
local shotStiffness = CameraMath.springFromLag(CameraData.lock.yawLag)
local bearingSpring = Spring.new(0, shotStiffness, CameraData.follow.damping)
-- The two-shot's flat distance and its aim relative to the player's root: they ease as the
-- fighters part or close, so a dodge widens the shot without tilting it.
local shotDistanceSpring = Spring.new(0, shotStiffness, CameraData.follow.damping)
local shotAimSpring = Spring.new(Vector3.zero, shotStiffness, CameraData.follow.damping)
local shotLive = false
-- 0 the free rig, 1 the two-shot.
local blendSpring = Spring.new(0, CameraMath.springFromLag(CameraData.lock.blendLag), CameraData.follow.damping)
-- The fraction of the rig's reach a wall leaves the camera: snaps in, eases out.
local reachSpring = Spring.new(1, CameraMath.springFromLag(CameraData.collision.pullOutLag), CameraData.follow.damping)
-- The two-shot's side of the line (1 right of the player, -1 left) and where its target last was.
local lockSign = 1
local lockPoint: Vector3? = nil
local wasLocked = false
-- The last frame's view yaw (the free camera takes it when a lock lets go) and camera spot.
local viewYaw = 0
local cameraSpot: Vector3? = nil
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
-- What the main step drew this frame, for the late pass (D-180): live from the main step's end to
-- the late pass, or to the next main step when no late pass runs.
local drawn = {
	live = false,
	at = 0,
	span = 0,
	settle = false,
	pivot = Vector3.zero,
	trailing = Vector3.zero,
	forward = Vector3.zero, -- the flat unit view the leash held the pivot along (zero: not leashed)
	anchor = Vector3.zero,
	fraction = 1,
	position = Vector3.zero,
	lookAt = Vector3.zero,
	axes = CFrame.identity, -- the camera's CFrame before the step: the shake's axes
	shakeTime = 0,
	blendFrom = nil :: CFrame?,
	blendAlpha = 1,
}
-- The nudge impulses and whether a shake were asked for while `drawn` is live.
local lateImpulse = Vector3.zero
local lateShake = false
-- A follow spring at rest that plays a late impulse alone over the frame's time.
local impulseProbe = Spring.new(Vector3.zero, followStiffness, CameraData.follow.damping)
local raycastParams: RaycastParams? = nil
-- The probe's exclude list: the subject, then whatever this frame's probe looked past.
local probeFilter: { Instance } = {}
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

local function pivotOf(root: BasePart): Vector3
	return root.Position + Vector3.yAxis * CameraData.follow.focusHeight
end

-- Back to the subject alone on the probe's exclude list.
local function resetFilter()
	table.clear(probeFilter)
	if subject ~= nil then
		table.insert(probeFilter, subject)
	end
	if raycastParams ~= nil then
		raycastParams.FilterDescendantsInstances = probeFilter
	end
end

-- The character (a model holding a Humanoid) a part belongs to, or nil. Workspace is a Model to
-- the engine: the walk stops there.
local function characterOf(part: Instance): Model?
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model ~= nil and model ~= workspace do
		if model:FindFirstChildOfClass("Humanoid") ~= nil then
			return model
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

-- How far along `direction` from `origin` the first part that blocks the view is (nil: clear).
-- Characters, accessories and see-through parts are looked past: added to the exclude list for
-- the next cast, at most collision.maxPasses casts a frame.
local function blockerDistance(origin: Vector3, direction: Vector3): number?
	local params = raycastParams
	if params == nil then
		return nil
	end
	local found: number? = nil
	local extended = false
	for _ = 1, CameraData.collision.maxPasses do
		local result = workspace:Spherecast(origin, CameraData.collision.probeRadius, direction, params)
		if result == nil then
			break
		end
		local part = result.Instance
		local character = characterOf(part)
		local accessory = part:FindFirstAncestorWhichIsA("Accessory")
		if
			CameraMath.blocksView(
				part.Transparency,
				CameraData.collision.seeThrough,
				character ~= nil,
				accessory ~= nil
			)
		then
			found = result.Distance
			break
		end
		local past: Instance = character or accessory or part
		table.insert(probeFilter, past)
		params.FilterDescendantsInstances = probeFilter
		extended = true
	end
	if extended then
		resetFilter()
	end
	return found
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

-- The shake's offset at `time` with `energy`, in the axes of `axes` (zero with no energy).
local function shakeIn(axes: CFrame, energy: number, time: number): Vector3
	if energy <= 0 then
		return Vector3.zero
	end
	local sx, sy, sz =
		table.unpack(CameraMath.shakeOffset(time, energy, CameraData.shake.frequency, CameraData.shake.lanes))
	return axes.RightVector * sx + axes.UpVector * sy + axes.LookVector * sz
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
		local root = subjectRoot()
		if pivotSpring ~= nil and root ~= nil then
			pivotSpring:Snap(pivotOf(root))
		end
	end
end

-- The rig for this frame, relative to the true pivot: where the camera sits and where it aims.
-- Blends the free rig and the two-shot and steps the bearing and blend springs.
local function rig(root: BasePart, span: number, settle: boolean): (Vector3, Vector3)
	local orbit = CameraData.orbit[mode]
	local distance = orbitDistance()
	local usePitch = pitch
	if mobile then
		distance *= CameraData.mobile.distanceMultiplier
		usePitch += CameraData.mobile.pitchAdd
	end
	local freeCamera = toVector(CameraMath.orbitOffset(yaw, usePitch, distance, orbit.height, orbit.side))
	local freeLook = toVector(CameraMath.shoulderLook(yaw, orbit.height, orbit.side))

	local targetRoot = lockRoot()
	if targetRoot ~= nil then
		lockPoint = targetRoot.Position
	elseif wasLocked then
		-- The lock let go (or its target went): the free camera picks up the view's heading.
		yaw = viewYaw
		freeCamera = toVector(CameraMath.orbitOffset(yaw, usePitch, distance, orbit.height, orbit.side))
		freeLook = toVector(CameraMath.shoulderLook(yaw, orbit.height, orbit.side))
	end
	wasLocked = targetRoot ~= nil
	blendSpring.target = if targetRoot ~= nil then 1 else 0
	local weight = advanceSpring(blendSpring, span, settle)
	local point = lockPoint
	if point == nil or (targetRoot == nil and weight <= CameraData.epsilon) then
		-- Free: the two-shot would start from where this camera stands around the player.
		lockPoint = nil
		shotLive = false
		blendSpring:Snap(0)
		bearingSpring:Snap(CameraMath.yawTowards(toTable(freeCamera), { 0, 0, 0 }))
		return freeCamera, freeLook
	end

	local lock = CameraData.lock
	local player = toTable(root.Position)
	local target = toTable(point)
	local shot = CameraMath.twoShot(player, target, lock, if mobile then CameraData.mobile.distanceMultiplier else 1)
	local aim = toVector(CameraMath.twoShotLook(player, target, lock.focusBias, lock.lookHeight)) - root.Position
	if not shotLive then
		-- A new shot starts on its shape; the blend eases the camera onto it.
		shotLive = true
		shotDistanceSpring:Snap(shot.distance)
		shotAimSpring:Snap(aim)
	end
	if targetRoot ~= nil then
		local offLine = CameraMath.shortestDelta(shot.lineYaw, bearingSpring.position)
		lockSign = CameraMath.lockSide(lockSign, offLine, lock.sideHysteresis)
		local bearing = shot.lineYaw + lockSign * shot.swing
		bearingSpring.target = bearingSpring.position + CameraMath.shortestDelta(bearingSpring.position, bearing)
		advanceSpring(bearingSpring, span, settle)
	end
	shotDistanceSpring.target = shot.distance
	shotAimSpring.target = aim
	local distanceNow = advanceSpring(shotDistanceSpring, span, settle)
	local aimNow = advanceSpring(shotAimSpring, span, settle)
	local pivot = pivotOf(root)
	local lockCamera = toVector(CameraMath.twoShotCamera(player, bearingSpring.position, distanceNow, lock.height))
		- pivot
	local lockLook = root.Position + aimNow - pivot
	return freeCamera:Lerp(lockCamera, weight), freeLook:Lerp(lockLook, weight)
end

local function step(dt: number)
	-- The real time since the last frame: the engine's dt, or the clock's gap when the engine
	-- reports less (the first frame after a stall may say one frame).
	local at = now()
	local gap = if lastStepAt ~= nil then at - (lastStepAt :: number) else dt
	lastStepAt = at
	-- A new frame: nothing of the last one is left for a late pass.
	drawn.live = false
	lateImpulse = Vector3.zero
	lateShake = false
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

	-- Right stick: integrate the held deflection over the frame (never over a stall). A lock owns
	-- the view: the look input waits.
	if gamepadLook.Magnitude > 0 and not settle and lockTarget == nil then
		local perSecond = CameraData.input.gamepadDegreesPerSecond
		applyLook(gamepadLook.X * span, -gamepadLook.Y * span, perSecond)
	end

	local pivot = pivotOf(root)
	local cameraOffset, lookOffset = rig(root, span, settle)

	-- The lagged pivot, leashed along and across the view.
	local spring = pivotSpring
	if spring == nil then
		spring = Spring.new(pivot, followStiffness, CameraData.follow.damping)
		pivotSpring = spring
	end
	local follow = spring :: Spring.Spring<Vector3>
	if (pivot - follow.position).Magnitude > CameraData.follow.snapDistance then
		follow:Snap(pivot)
	end
	follow.target = pivot
	local trailing = advanceSpring(follow, span, settle)
	local view = lookOffset - cameraOffset
	local forward = Vector3.new(view.X, 0, view.Z)
	local anchor = trailing
	if forward.Magnitude > CameraData.epsilon then
		local leash = CameraData.follow.leash
		anchor = toVector(
			CameraMath.leash(
				toTable(pivot),
				toTable(trailing),
				toTable(forward.Unit),
				leash.closer,
				leash.further,
				leash.side
			)
		)
	end

	-- Walls: probe from the true pivot to the camera spot; pull the rig in toward the pivot.
	local reach = anchor - pivot + cameraOffset
	local aim = anchor - pivot + lookOffset
	local length = reach.Magnitude
	if length > CameraData.epsilon and raycastParams ~= nil then
		local allowed = math.min(
			CameraMath.collisionDistance(
				length,
				blockerDistance(pivot, reach),
				CameraData.collision.probeRadius,
				CameraData.collision.minDistance
			) / length,
			1
		)
		-- Pull in at once in front of a wall; ease back out.
		if allowed < reachSpring.position then
			reachSpring:Snap(allowed)
		else
			reachSpring.target = allowed
			advanceSpring(reachSpring, span, settle)
		end
	end
	local fraction = reachSpring.position
	local position = pivot + reach * fraction
	local lookAt = pivot + aim * fraction
	cameraSpot = position
	if forward.Magnitude > CameraData.epsilon then
		viewYaw = CameraMath.yawTowards(toTable(position), toTable(lookAt))
	end

	-- Shake: noise scaled by a decaying energy, in the camera's own axes.
	local shakeEnergy = shakeValue(at)
	shakeTime += span
	local axes = camera.CFrame
	local shakeVector = shakeIn(axes, shakeEnergy, shakeTime)

	local followCFrame = CFrame.lookAt(position + shakeVector, lookAt + shakeVector)
	local back = blendBack
	local blendFrom: CFrame? = nil
	local blendAlpha = 1
	if back ~= nil then
		local alpha = CameraMath.easeBlend(back.elapsed, CameraData.scripted.blendOut)
		back.elapsed += span
		followCFrame = back.from:Lerp(followCFrame, alpha)
		blendFrom, blendAlpha = back.from, alpha
		if alpha >= 1 then
			blendBack = nil
		end
	end
	camera.CFrame = followCFrame
	camera.Focus = CFrame.new(lookAt)

	-- Kept for the late pass (D-180).
	drawn.live = true
	drawn.at = at
	drawn.span = span
	drawn.settle = settle
	drawn.pivot = pivot
	drawn.trailing = trailing
	drawn.forward = if forward.Magnitude > CameraData.epsilon then forward.Unit else Vector3.zero
	drawn.anchor = anchor
	drawn.fraction = fraction
	drawn.position = position
	drawn.lookAt = lookAt
	drawn.axes = axes
	drawn.shakeTime = shakeTime
	drawn.blendFrom = blendFrom
	drawn.blendAlpha = blendAlpha
end

-- The late pass (D-180), after every render step that can ask for a hit's nudge or shake (the
-- character controller's contact at 301): a nudge or a shake asked for since the main step shows
-- on this frame. Nothing else of the frame changes, and a frame without one is left alone.
local function lateStep(_dt: number)
	if not drawn.live then
		return
	end
	drawn.live = false
	local impulse = lateImpulse
	local shook = lateShake
	lateImpulse = Vector3.zero
	lateShake = false
	local nudged = impulse.Magnitude > CameraData.epsilon
	if not nudged and not shook then
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local position = drawn.position
	local lookAt = drawn.lookAt
	local spring = pivotSpring
	if nudged and spring ~= nil and spring.position == drawn.trailing then
		-- The spring is linear: the impulse's own response over the frame adds to the step that
		-- ran, exactly as if it had come before it (a settled stall drops it, as it would have).
		impulseProbe:Snap(Vector3.zero)
		impulseProbe.velocity = impulse
		local moved = advanceSpring(impulseProbe, drawn.span, drawn.settle)
		local trailing = drawn.trailing + moved
		spring.position = trailing
		spring.velocity += impulseProbe.velocity - impulse
		local anchor = trailing
		if drawn.forward ~= Vector3.zero then
			local leash = CameraData.follow.leash
			anchor = toVector(
				CameraMath.leash(
					toTable(drawn.pivot),
					toTable(trailing),
					toTable(drawn.forward),
					leash.closer,
					leash.further,
					leash.side
				)
			)
		end
		-- The rig rides the anchor, pulled in by the frame's wall fraction.
		local shift = (anchor - drawn.anchor) * drawn.fraction
		position += shift
		lookAt += shift
		cameraSpot = position
	end
	local shakeVector = shakeIn(drawn.axes, shakeValue(drawn.at), drawn.shakeTime)
	local followCFrame = CFrame.lookAt(position + shakeVector, lookAt + shakeVector)
	local blendFrom = drawn.blendFrom
	if blendFrom ~= nil then
		followCFrame = blendFrom:Lerp(followCFrame, drawn.blendAlpha)
	end
	camera.CFrame = followCFrame
	camera.Focus = CFrame.new(lookAt)
end

-- ------------------------------------------------------------------ public API

--- Pushes the camera toward `toward` so it peaks `studs` away from its path (every hit, section 10).
function CameraController.nudge(toward: Vector3, studs: number)
	local spring = pivotSpring
	local spot = cameraSpot
	if spring == nil or spot == nil then
		return
	end
	local direction = toward - spot
	if direction.Magnitude <= CameraData.epsilon then
		return
	end
	local impulse = direction.Unit * CameraMath.impulseForDisplacement(studs, followStiffness)
	spring:Impulse(impulse)
	if drawn.live then
		-- Asked for after this frame's step: the late pass shows it on this frame (D-180).
		lateImpulse += impulse
	end
end

--- Starts (or raises) a shake at the tier's amplitude; it decays on its own from now.
function CameraController.shake(tier: string)
	local amplitude = CameraData.shake.amplitude[tier] or CameraData.shake.amplitude.Normal
	local at = now()
	shakePeak = math.max(shakeValue(at), amplitude)
	shakeAt = at
	if drawn.live then
		lateShake = true
	end
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

--- Locks the framing on a model (nil clears it). The shot eases between the free camera and the
--- two-shot; a new lock takes the right shoulder unless the camera already stands well left.
function CameraController.setLockTarget(model: Model?)
	if model ~= nil and lockTarget == nil then
		lockSign = 1
	end
	lockTarget = model
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
	resetFilter()
	reachSpring:Snap(1)
	local spring = pivotSpring
	local root = subjectRoot()
	if spring ~= nil and root ~= nil then
		spring:Snap(pivotOf(root))
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
		if mouseCaptured and lockTarget == nil then
			applyLook(input.Delta.X, input.Delta.Y, CameraData.input.mouseDegreesPerPixel)
		end
	elseif inputType == Enum.UserInputType.MouseWheel then
		zoomOffset = math.clamp(
			zoomOffset - input.Position.Z * CameraData.zoom.step,
			CameraData.zoom.min - CameraData.orbit[mode].distance,
			CameraData.zoom.max - CameraData.orbit[mode].distance
		)
	elseif inputType == Enum.UserInputType.Touch then
		if not processed and lockTarget == nil then
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
	-- After the character controller's contact (Character + 1) and anything else that can ask
	-- for a hit's nudge or shake inside the frame (D-180).
	RunService:BindToRenderStep(LATE_STEP_NAME, Enum.RenderPriority.Last.Value, lateStep)
end

return CameraController
