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

	Real Choreo and Locomotion (foot IK on a flat field) on the hit matrix's player. The controller's
	frame is emulated: the stick, the two-step stop's carry (ActionLogic.stopCarryStep), the dodge
	played with handOver and the movement locked for combat.luau dodgeDuration, the clip's root
	motion and the held yaw after the step, then the Humanoid's move.
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

type Worst = { degrees: number, at: string, dodge: string }

-- One take: the key's world stick `key` held `holdSeconds`, the dodge pressed `pressAfter` seconds
-- after it went down.
local function take(drawn: boolean, key: Vector3, holdSeconds: number, pressAfter: number): Worst
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
	local dt = 1 / HZ
	local chain = Pose.chain(model)
	local keyAt = math.floor(Cases.settle * HZ + 0.5)
	local keyUp = keyAt + math.max(1, math.floor(holdSeconds * HZ + 0.5))
	local press = keyAt + math.max(1, math.floor(pressAfter * HZ + 0.5))
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
	local worst: Worst = { degrees = 0, at = "", dodge = "" }
	for frame = 1, press + math.floor(Cases.after * HZ + 0.5) do
		clock += dt
		local stick = if frame >= keyAt and frame < keyUp then key else Vector3.zero
		if frame == press then
			-- CharacterController.dodge: the stick in the body's frame (none while the carry runs).
			local held = if carry.active then Vector3.zero else stick
			local moveLocal = rootFrame.Rotation:VectorToObjectSpace(held)
			local direction = ActionLogic.dodgeDirection(moveLocal.X, moveLocal.Z, Input.dodge.inputDeadzone)
			worst.dodge = "Dodge" .. direction
			handle = animator:play(PREFIX .. worst.dodge, { handOver = true })
			dodgeUntil = frame + Combat.dodgeDuration * HZ
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
			for _, part in PARTS do
				local degrees = angleBetween(last[part], solved[part])
				if degrees > worst.degrees then
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

describe("DodgeTap", function()
	it("a dodge pressed after an unlocked key turned the body turns no part past popDegrees a row (531)", function()
		local problems: { string } = {}
		local report: { string } = {}
		local keys = { { "A", Vector3.new(-1, 0, 0) }, { "D", Vector3.new(1, 0, 0) } }
		for _, drawn in { true, false } do
			local stance = if drawn then "drawn" else "sheathed"
			for _, key in keys do
				local most: Worst = { degrees = 0, at = "", dodge = "" }
				for _, holdSeconds in Cases.holdSeconds do
					for _, pressAfter in Cases.pressAfter do
						local worst = take(drawn, key[2] :: Vector3, holdSeconds, pressAfter)
						local label = ("%s, %s held %.2f s, %s pressed %.2f s after it"):format(
							stance,
							key[1] :: string,
							holdSeconds,
							worst.dodge,
							pressAfter
						)
						if worst.degrees > most.degrees then
							most = { degrees = worst.degrees, at = ("%s: %s"):format(label, worst.at), dodge = "" }
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
					("%s, key %s: worst %.1f (%s)"):format(stance, key[1] :: string, most.degrees, most.at)
				)
			end
		end
		print("DodgeTap:\n  " .. table.concat(report, "\n  "))
		expect(table.concat(problems, "\n")).toBe("")
	end)
end)
