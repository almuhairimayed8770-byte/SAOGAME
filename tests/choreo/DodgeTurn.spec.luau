--!strict
--[[
	A dodge pressed while a turn in place is under way (D-613; Studio item 515(b)): standing,
	drawn and sheathed, the stick turned dev.luau groundClearance.dodgeTurn.degrees to the left and
	to the right, the root turning toward it at combat.luau aim.lockTurnRate (Locomotion plays the
	turn clip and holds the hips, D-416), and each dodge pressed each of `pressAfter` seconds after
	the stick turned. Each part's turn per review.fps row, in the root part's frame (the root's
	own yaw is the body turning, not a pop), from the dodge's first row until it has gone, is at
	most review.audit.popDegrees.

	On 81b8fef the dodge cut the turn clip as an action: it took the arms and legs over the
	cancel's snap (choreo.luau handOver.seconds), turning the left forearm up to 41.8 and the left
	hand up to 48.9 degrees on its first row from the sheathed stance and a lower leg 24.8 from the
	drawn one (the owner's PC on c78acd1: the sheathed standing dodge to the left, its right lower
	leg 33.6 on the second row). Now a turn it cuts is a stance (locomotion.dodgeHandOff.takesFrom):
	the dodge takes the body over its joints' own blends and the turn stands under it until they
	have come in.

	Real Choreo and Locomotion (foot IK on a flat field) on the hit matrix's player; the dodge played
	as CharacterController plays it (handOver), the root moved at the dodge's speed along its way.
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
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")

local Cases = Dev.groundClearance.dodgeTurn
local TURN_RATE = Combat.aim.lockTurnRate
local POP = Dev.review.audit.popDegrees
local HZ = Dev.review.fps
local PREFIX = ChoreoData.locomotion.clipPrefix
local DODGE_SPEED = Combat.dodgeDistance / Combat.dodgeDuration
-- Each dodge and the way it moves the root, in the root's frame (DodgeTakeOver.spec.luau's).
local WAYS: { [string]: Vector3 } = {
	DodgeForward = Vector3.new(0, 0, -1),
	DodgeBack = Vector3.new(0, 0, 1),
	DodgeLeft = Vector3.new(-1, 0, 0),
	DodgeRight = Vector3.new(1, 0, 0),
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

type Worst = { degrees: number, at: string }

-- One take: the turn to `side` (1 left, -1 right), `dodge` pressed `pressAfter` seconds into it.
local function take(drawn: boolean, side: number, dodge: string, pressAfter: number): Worst
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
	local stickAt = math.floor(Cases.settle * HZ + 0.5)
	local press = stickAt + math.max(1, math.floor(pressAfter * HZ + 0.5))
	local yaw = 0
	local offset = Vector3.zero
	local last: any = nil
	local handle: any = nil
	local worst: Worst = { degrees = 0, at = "" }
	for frame = 1, press + math.floor(Cases.after * HZ + 0.5) do
		clock += dt
		if frame == press then
			handle = animator:play(PREFIX .. dodge, { handOver = true })
		end
		local turning = frame >= stickAt
		if turning then
			yaw = math.min(Cases.degrees, yaw + TURN_RATE * dt)
		end
		local dodging = handle ~= nil and (frame - press) * dt < Combat.dodgeDuration - 1e-9
		local facing = CFrame.Angles(0, math.rad(yaw * side), 0)
		local velocity = if dodging then facing:VectorToWorldSpace(WAYS[dodge]) * DODGE_SPEED else Vector3.zero
		offset += velocity * dt
		local rootFrame = avatar.base * CFrame.new(offset) * facing
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = Vector3.zero,
			speed = velocity.Magnitude,
			sprinting = false,
			grounded = true,
			drawn = drawn,
			turning = if turning then (Cases.degrees - yaw) * side else 0,
			verticalVelocity = 0,
			velocity = velocity,
		})
		animator:step(dt)
		-- Posed in the root's frame (Pose.solve against the base: the root's yaw left out).
		local solved = Pose.solve(model, avatar.base, animator.mixer:lastOffsets(), chain)
		local k = frame - press
		-- From the dodge's first row until it has gone.
		if last ~= nil and handle ~= nil and k >= 0 and (not handle.done or k == 0) then
			for _, part in PARTS do
				local degrees = angleBetween(last[part], solved[part])
				if degrees > worst.degrees then
					worst.degrees = degrees
					worst.at = ("row +%d %s"):format(k + 1, part)
				end
			end
		end
		last = solved
	end
	locomotion:destroy()
	Choreo.release(model)
	return worst
end

describe("DodgeTurn", function()
	it("a dodge pressed during a turn in place turns no part past popDegrees a row (515(b))", function()
		local problems: { string } = {}
		local report: { string } = {}
		for _, drawn in { true, false } do
			local stance = if drawn then "drawn" else "sheathed"
			for _, side in { 1, -1 } do
				local way = if side > 0 then "left" else "right"
				for _, dodge in ChoreoData.locomotion.dodgeHandOff.clips do
					local most: Worst = { degrees = 0, at = "" }
					for _, pressAfter in Cases.pressAfter do
						local worst = take(drawn, side, dodge, pressAfter)
						if worst.degrees > most.degrees then
							most = {
								degrees = worst.degrees,
								at = ("%.2f s into the turn, %s"):format(pressAfter, worst.at),
							}
						end
						if worst.degrees > POP + 1e-9 then
							table.insert(
								problems,
								("%s, turning %s, %s pressed %.2f s into the turn: %.1f degrees at %s (limit %g)"):format(
									stance,
									way,
									dodge,
									pressAfter,
									worst.degrees,
									worst.at,
									POP
								)
							)
						end
					end
					table.insert(
						report,
						("%s, turning %s, %s: worst %.1f (%s)"):format(stance, way, dodge, most.degrees, most.at)
					)
				end
			end
		end
		print("DodgeTurn:\n  " .. table.concat(report, "\n  "))
		expect(table.concat(problems, "\n")).toBe("")
	end)
end)
