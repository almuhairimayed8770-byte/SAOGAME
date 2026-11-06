--!strict
--[[
	The guard comes up as a snap (Studio item 436(c), D-527): raised from the drawn stance, the
	arms reach the guard within dev.luau review.audit.cancel.snapFrames 60 Hz rows of the press
	(section 10 beat 2: a snap is 2 to 4 frames), the way a guard that cuts a basic already does
	(D-408), and from the row after them no part turns more than review.audit.reportDegrees.

	On 4b18b5c a guard raised with nothing to cut blended in over the Guard clip's own blendIn
	(0.08 s, SineInOut): the arms turned 11.3 / 28.4 / 32.7 / 24.1 / 6.6 degrees on the five rows
	after the press (the owner's PC: 9.5 / 29.6 / 29.8 / 25.6 / 7.7), three of them past
	review.audit.popDegrees and two past the snap's frames.

	Real Choreo and Locomotion (foot IK on a flat field) on the hit matrix's player, drawn, standing
	and walking at the guard's walk; the guard played as CharacterController.setGuard plays it, and
	each upper-body part's turn per 60 Hz row read in the root part's frame (what the camera follows).
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

local Choreo = Harness.load("src/client/choreo/Choreo")
Choreo.configure({
	now = function()
		return 0
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")

local Audit = Dev.review.audit
local GUARD_ID = ChoreoData.locomotion.clipPrefix .. "Guard"
local HZ = Dev.review.fps

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

-- The parts the guard (an UpperBody clip) moves: the arms, the hands, the torso and the head. The
-- legs walk on under it (their turns are the stride's own).
local UPPER = {
	"Head",
	"UpperTorso",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
}

local function angleBetween(a: CFrame, b: CFrame): number
	local _, radians = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	return math.deg(math.abs(radians))
end

-- Each row's largest part turn (degrees) and the part, from the press row on.
local function raise(speed: number): { { degrees: number, part: string } }
	local avatar, field = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", true)
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
	local settle = 1
	local travelled = 0
	local last: any = nil
	local rows = {}
	for frame = 1, math.floor((settle + 0.4) * HZ + 0.5) do
		local t = frame * dt
		local pressed = t > settle + 1e-9
		if pressed and #rows == 0 and last ~= nil and animator.mixer:find(GUARD_ID) == nil then
			animator:play(GUARD_ID, { handOver = true })
		end
		travelled += speed * dt
		local rootFrame = avatar.base * CFrame.new(0, 0, -travelled)
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = if speed > 0 then Vector3.new(0, 0, -1) else Vector3.zero,
			speed = speed,
			sprinting = false,
			grounded = true,
			drawn = true,
			turning = 0,
			verticalVelocity = 0,
			velocity = Vector3.new(0, 0, -speed),
		})
		animator:step(dt)
		-- Solved on the standing base: each part's turn in the root part's frame. One row later than
		-- the screen draws it (the pose is drawn on the next row, D-342): the per-row turns are the same.
		local solved = Pose.solve(model, avatar.base, animator.mixer:lastOffsets(), chain)
		if pressed and last ~= nil then
			local worst, part = 0, ""
			for _, name in UPPER do
				local degrees = angleBetween(last[name], solved[name])
				if degrees > worst then
					worst, part = degrees, name
				end
			end
			table.insert(rows, { degrees = worst, part = part })
		end
		last = solved
	end
	locomotion:destroy()
	Choreo.release(model)
	return rows
end

describe("GuardRaise", function()
	it("the guard raised from the drawn stance is a snap: done within cancel.snapFrames rows (436(c))", function()
		local problems = {}
		local report = {}
		for _, speed in { 0, ChoreoData.locomotion.walkSpeed } do
			local rows = raise(speed)
			local shown = {}
			for index = 1, 6 do
				table.insert(shown, ("%.1f"):format(rows[index].degrees))
			end
			table.insert(report, ("at %d: %s"):format(speed, table.concat(shown, " / ")))
			for index, row in rows do
				if index > Audit.cancel.snapFrames and row.degrees > Audit.reportDegrees then
					table.insert(
						problems,
						("at %d studs/s the %s still turns %.1f degrees on row %d after the press (the snap is %d rows; reportDegrees %d)"):format(
							speed,
							row.part,
							row.degrees,
							index,
							Audit.cancel.snapFrames,
							Audit.reportDegrees
						)
					)
				end
			end
		end
		print("GuardRaise, the largest part turn on each row after the press: " .. table.concat(report, "; "))
		expect(table.concat(problems, "\n")).toBe("")
	end)
end)
