--!strict
--[[
	A dodge pressed after an unlocked key has turned the body on the spot (D-646; Studio item
	531(b)(d)): standing, drawn and sheathed, A or D held for each of dev.luau
	groundClearance.dodgeTap.holdSeconds, the body turning and setting off toward it on a
	Studio-like Humanoid, and the dodge CharacterController picks for the stick at the press (Back
	once the key is up) pressed each of `pressAfter` seconds after the key went down. Each part's
	turn per review.fps row, in the root part's frame, from the dodge's first row until it has gone,
	is at most review.audit.popDegrees.

	On 3d59958 a dodge only stopped Locomotion writing the gait's weights (D-528): the Mixer carried
	them on to the targets of the frame before the press, the tapped key's run, so the legs strode on
	under the dodge's first row (drawn, A held 0.08 s, DodgeBack pressed 0.10 s after: row +1 22.4
	degrees; the owner's PC turnD_A_100, RightLowerLeg 26.45 on its row 2) and crossed back to the
	idle in its fade (sheathed: LeftLowerArm 20.1 to 20.3 on row +30; the PC's turnS_A_100 and
	turnS_D_100 20.16 and 20.68 on row 31). Now the weights stand where the dodge found them.

	The key held through the dodge (D-657): pressed each of `heldPressAfter` seconds after the key
	went down, the dodge lets go into the run. On 25fbe7d the weights stood at the press's mix
	under the dodge and crossed to the run only under its fade: sheathed, pressed 0.075 s after the
	key, LeftLowerLeg 21.0 degrees on row +28 at 60 Hz (24.0 a 60 Hz row's worth at 144). Now, once
	the dodge's pose hides the gait, its weights are aimed at the stick's gait (the run while a key
	is down, the idle when not), and the dodge holds the gait's phase and hands the legs back at
	dodgeHandOff.resumePhase (D-609), from a standing press too. Every take runs at each of
	`stepHz`: at review.fps every row is judged; at another rate (each frame's turn scaled to a
	review.fps row, as item 550 scales the screen's rows) the dodge's first row and its blend out,
	the rows the gait shows in, while the rows between are the dodge's own keys over a gait it
	hides or stands (DodgeForward's landing turns the left forearm 21.7 a 60 Hz row's worth on one
	144 Hz frame, before and after) and are reported.

	Real Choreo and Locomotion (foot IK on a flat field) on the hit matrix's player. The controller's
	frame is emulated: the stick, the two-step stop's carry (ActionLogic.stopCarryStep), the dodge
	played with handOver and the movement locked for combat.luau dodgeDuration, the stick's walk
	speed once the action lets go (State.stickSpeed: the run's, no lock or sprint here), the clip's
	root motion and the held yaw after the step, then the Humanoid's move.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local function fakeSignal()
	local signal = {}
	function signal:Connect()
		return { Disconnect = function() end }
	end
	return signal
end
Harness.stubService("RunService", {
	RenderStepped = fakeSignal(),
	Heartbeat = fakeSignal(),
	PreSimulation = fakeSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local clock = 0
local Choreo = Harness.load("src/client/choreo/Choreo")
Choreo.configure({
	now = function()
		return clock
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Combat = Harness.load("src/shared/data/combat")
local Input = Harness.load("src/shared/data/input")
local Dev = Harness.load("src/shared/data/dev")

local Cases = Dev.groundClearance.dodgeTap
local ENGINE = Cases.engine
local POP = Dev.review.audit.popDegrees
local HZ = Dev.review.fps
local Config = ChoreoData.locomotion
local PREFIX = Config.clipPrefix
local RUN_SPEED = Config.runSpeed
local STOP_CARRY = {
	seconds = Config.stopStepsSeconds,
	minCycles = Config.stopMinCycles,
	endSpeed = Config.stopEndSpeed,
	minSpeed = Config.idleSpeedThreshold,
	maxSpeed = Config.skidSpeedThreshold,
}

local root = Harness.repoRoot()
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end
local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")

local PARTS = {
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
	"Head",
	"UpperTorso",
	"LowerTorso",
}

local function angleBetween(a: CFrame, b: CFrame): number
	local _, radians = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	return math.deg(math.abs(radians))
end

local function yawOf(frame: CFrame): number
	local look = frame.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

-- The worst judged turn and where, the dodge pressed, and the worst row not judged (another rate's
-- rows between the dodge's first and its blend out).
type Worst = { degrees: number, at: string, dodge: string, between: number }

-- One take at `hz` steps a second: the key's world stick `key` held `holdSeconds` (nil: to the
-- end), the dodge pressed `pressAfter` seconds after it went down.
local function take(drawn: boolean, key: Vector3, holdSeconds: number?, pressAfter: number, hz: number): Worst
	local avatar, field = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", drawn)
	local top = ClipAudit.topOf(field.CFrame, field.Size)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: any
	local primary = model.PrimaryPart
	humanoid.HipHeight = avatar.rootHeight - primary.Size.Y / 2
	primary.CFrame = avatar.base
	primary.Position = avatar.base.Position
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, {
		raycast = function(origin: Vector3, direction: Vector3): Vector3?
			if origin.Y >= top and origin.Y + direction.Y <= top then
				return Vector3.new(origin.X, top, origin.Z)
			end
			return nil
		end,
	})
	local dt = 1 / hz
	-- A frame's turn as a review.fps row's (item 550 step 8).
	local perRow = hz / HZ
	local everyRow = hz == HZ
	local chain = Pose.chain(model)
	local keyAt = math.floor(Cases.settle * hz + 0.5)
	local keyUp = if holdSeconds ~= nil then keyAt + math.max(1, math.floor(holdSeconds * hz + 0.5)) else math.huge
	local press = keyAt + math.max(1, math.floor(pressAfter * hz + 0.5))
	local carry: any = ActionLogic.newStopCarry()
	local gait: any = { phase = 0, leftStep = 0, leftAfter = 0, rightStep = 0.5, rightAfter = 0 }
	local rootFrame = avatar.base
	local velocity = Vector3.zero
	local pending: { Vector3 } = {}
	local dodgeUntil = -math.huge
	local heldYaw: number? = nil
	local handle: any = nil
	local gone = false
	local last: any = nil
	local worst: Worst = { degrees = 0, at = "", dodge = "", between = 0 }
	for frame = 1, press + math.floor(Cases.after * hz + 0.5) do
		clock += dt
		local stick = if frame >= keyAt and frame < keyUp then key else Vector3.zero
		if frame == press then
			-- CharacterController.dodge: the stick in the body's frame (none while the carry runs).
			local held = if carry.active then Vector3.zero else stick
			local moveLocal = rootFrame.Rotation:VectorToObjectSpace(held)
			local direction = ActionLogic.dodgeDirection(moveLocal.X, moveLocal.Z, Input.dodge.inputDeadzone)
			worst.dodge = "Dodge" .. direction
			handle = animator:play(PREFIX .. worst.dodge, { handOver = true })
			dodgeUntil = frame + Combat.dodgeDuration * hz
		end
		local locked = frame < dodgeUntil - 1e-9
		local state = if locked then "Dodge" else "Idle"
		local walkSpeed = if locked then 0 else RUN_SPEED
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local moveDir = stick
		local stopGait: any = nil
		if moveDir.Magnitude == 0 then
			locomotion:stopGait(gait)
			stopGait = gait
		end
		local carried = ActionLogic.stopCarryStep(
			carry,
			moveDir.X,
			moveDir.Z,
			speed,
			walkSpeed,
			true,
			state,
			dt,
			STOP_CARRY,
			stopGait
		)
		local targetSpeed = if carried > 0 then carried else walkSpeed
		if carried > 0 then
			moveDir = Vector3.new(carry.x, 0, carry.z)
		end
		local look = rootFrame.LookVector
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = moveDir,
			speed = speed,
			sprinting = false,
			grounded = true,
			drawn = drawn,
			turning = if locked then 0 else ActionLogic.turnAngle(look.X, look.Z, moveDir.X, moveDir.Z),
			verticalVelocity = 0,
			velocity = velocity,
			-- CharacterController's stickSpeed (D-657): the run's, with no lock or sprint key.
			stickSpeed = if stick.Magnitude > 0 then RUN_SPEED else 0,
		})
		animator:step(dt)
		-- The controller's after-step: the dodge's yaw held, its clip's root motion on the root.
		if locked then
			if heldYaw == nil then
				heldYaw = yawOf(rootFrame)
			else
				local back = ((heldYaw :: number) - yawOf(rootFrame) + 180) % 360 - 180
				rootFrame *= CFrame.Angles(0, math.rad(back), 0)
			end
			rootFrame += rootFrame.Rotation:VectorToWorldSpace(animator:currentRootMotionDelta())
		else
			heldYaw = nil
		end
		-- Posed in the root's frame (Pose.solve against the base: the root's yaw left out).
		local solved = Pose.solve(model, avatar.base, animator.mixer:lastOffsets(), chain)
		local k = frame - press
		-- From the dodge's first row until the row it has gone on.
		if last ~= nil and handle ~= nil and k >= 0 and not gone then
			-- At another rate: the first row, and from the dodge's let-go (its blend out).
			local judged = everyRow or k == 0 or handle.stopping
			for _, part in PARTS do
				local degrees = angleBetween(last[part], solved[part]) * perRow
				if not judged then
					worst.between = math.max(worst.between, degrees)
				elseif degrees > worst.degrees then
					worst.degrees = degrees
					worst.at = ("row +%d %s"):format(k + 1, part)
				end
			end
			gone = handle.done
		end
		last = solved
		-- The engine: the move of `lagFrames` frames ago, the body's speed toward it at its rates,
		-- AutoRotate turning the body toward it while the movement is not locked.
		local want = if moveDir.Magnitude > 0 then moveDir.Unit * targetSpeed else Vector3.zero
		table.insert(pending, want)
		local applied = Vector3.zero
		if #pending > ENGINE.lagFrames then
			applied = table.remove(pending, 1) :: Vector3
		end
		local change = applied - velocity
		local rate = if applied.Magnitude < 1e-6 then ENGINE.decel else ENGINE.accel
		if change.Magnitude > 1e-9 then
			velocity += change.Unit * math.min(change.Magnitude, rate * dt)
		end
		local at = rootFrame.Position + velocity * dt
		local turn = 0
		if not locked and applied.Magnitude > 1e-6 then
			local facing = rootFrame.LookVector
			local move = applied.Unit
			local angle = math.atan2(facing.X * move.Z - facing.Z * move.X, facing.X * move.X + facing.Z * move.Z)
			local most = math.rad(ENGINE.turnRate) * dt
			turn = math.clamp(-angle, -most, most)
		end
		rootFrame = CFrame.new(at) * rootFrame.Rotation * CFrame.Angles(0, turn, 0)
	end
	locomotion:destroy()
	Choreo.release(model)
	return worst
end

-- Every take of `holds` (false: the key held to the end) and `presses` at each of Cases.stepHz,
-- drawn and sheathed, A and D: the problems over popDegrees and a line per stance, key and rate.
local function sweep(holds: { number | false }, presses: { number }): ({ string }, { string })
	local problems: { string } = {}
	local report: { string } = {}
	local keys = { { "A", Vector3.new(-1, 0, 0) }, { "D", Vector3.new(1, 0, 0) } }
	for _, hz in Cases.stepHz do
		for _, drawn in { true, false } do
			local stance = if drawn then "drawn" else "sheathed"
			for _, key in keys do
				local most: Worst = { degrees = 0, at = "", dodge = "", between = 0 }
				for _, hold in holds do
					local holdSeconds: number? = if hold == false then nil else hold :: number
					for _, pressAfter in presses do
						local worst = take(drawn, key[2] :: Vector3, holdSeconds, pressAfter, hz)
						local label = ("%d Hz, %s, %s %s, %s pressed %.3f s after it"):format(
							hz,
							stance,
							key[1] :: string,
							if holdSeconds ~= nil then ("held %.2f s"):format(holdSeconds) else "held through",
							worst.dodge,
							pressAfter
						)
						most.between = math.max(most.between, worst.between)
						if worst.degrees > most.degrees then
							most.degrees = worst.degrees
							most.at = ("%s: %s"):format(label, worst.at)
						end
						if worst.degrees > POP + 1e-9 then
							table.insert(
								problems,
								("%s: %.1f degrees at %s (limit %g)"):format(label, worst.degrees, worst.at, POP)
							)
						end
					end
				end
				table.insert(
					report,
					("%d Hz, %s, key %s: worst %.1f (%s)%s"):format(
						hz,
						stance,
						key[1] :: string,
						most.degrees,
						most.at,
						if hz == HZ then "" else (", between (not judged) %.1f"):format(most.between)
					)
				)
			end
		end
	end
	return problems, report
end

describe("DodgeTap", function()
	it("a dodge pressed after an unlocked key turned the body turns no part past popDegrees a row (531)", function()
		local problems, report = sweep(Cases.holdSeconds, Cases.pressAfter)
		print("DodgeTap:\n  " .. table.concat(report, "\n  "))
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it(
		"a dodge with the key held through it lets go into the run with no part past popDegrees a row (D-657)",
		function()
			local problems, report = sweep({ false }, Cases.heldPressAfter)
			print("DodgeTap held:\n  " .. table.concat(report, "\n  "))
			expect(table.concat(problems, "\n")).toBe("")
		end
	)
end)
