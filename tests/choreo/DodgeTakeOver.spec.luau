--!strict
--[[
	A dodge takes the body without a pop (Studio item 436(d), D-528): pressed from the drawn or
	the sheathed stance, standing, walking or running, no part of the body turns more than dev.luau
	review.audit.popDegrees on any 60 Hz row while the dodge holds the body.

	On 4b18b5c a dodge with nothing to cut blended in over its own blendIn (0.05 s) from whatever
	the body showed: the stance it was not authored from (the sheathed one) or a gait that went on
	striding under it and retargeted to the dodge's 32 studs a second. The arms turned up to 58.6
	degrees a row and the legs up to 40.2 on the first two rows after the press (the owner's PC:
	30.9 / 60.3, 60.07, 57.80, 34.8), all before the State attribute read Dodge. A sprint is not
	judged here: its own stride turns the feet over popDegrees a row.

	Real Choreo and Locomotion (foot IK on a flat field) on the hit matrix's player; the dodge played
	as CharacterController plays it (handOver, nothing live to cut), the root moved at the dodge's
	speed (combat.luau dodgeDistance / dodgeDuration) its way, the stick held as before; each part's
	turn per 60 Hz row read in the root part's frame (what the camera follows).
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

local Audit = Dev.review.audit
local PREFIX = ChoreoData.locomotion.clipPrefix
local HZ = Dev.review.fps
local DODGE_SPEED = Combat.dodgeDistance / Combat.dodgeDuration

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
	Arms = { "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" },
	Legs = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" },
	Body = { "Head", "UpperTorso", "LowerTorso" },
}
-- Each dodge and the way it moves the root, in the root's frame.
local DODGES = {
	{ name = "Forward", way = Vector3.new(0, 0, -1) },
	{ name = "Back", way = Vector3.new(0, 0, 1) },
	{ name = "Left", way = Vector3.new(-1, 0, 0) },
	{ name = "Right", way = Vector3.new(1, 0, 0) },
}

local function angleBetween(a: CFrame, b: CFrame): number
	local _, radians = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	return math.deg(math.abs(radians))
end

type Worst = { degrees: number, part: string, row: number }

-- The largest part turn of each group on the rows the dodge holds the body (from the press until
-- it lets go), the stick held forward at `speed` before and after.
local function dodge(name: string, way: Vector3, drawn: boolean, speed: number): { [string]: Worst }
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
	local settle = 1.5
	local offset = Vector3.zero
	local last: any = nil
	local handle: any = nil
	local worst: { [string]: Worst } = {}
	for group in PARTS do
		worst[group] = { degrees = 0, part = "", row = 0 }
	end
	local row = 0
	for frame = 1, math.floor((settle + 0.6) * HZ + 0.5) do
		clock += dt
		local since = frame * dt - settle
		if handle == nil and since > -1e-9 then
			handle = animator:play(PREFIX .. "Dodge" .. name, { handOver = true })
		end
		local dodging = handle ~= nil and since < Combat.dodgeDuration - 1e-9
		local velocity = if dodging then way * DODGE_SPEED else Vector3.new(0, 0, -speed)
		offset += velocity * dt
		local rootFrame = avatar.base * CFrame.new(offset)
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = if speed > 0 then Vector3.new(0, 0, -1) else Vector3.zero,
			speed = velocity.Magnitude,
			sprinting = false,
			grounded = true,
			drawn = drawn,
			turning = 0,
			verticalVelocity = 0,
			velocity = velocity,
		})
		animator:step(dt)
		local solved = Pose.solve(model, avatar.base, animator.mixer:lastOffsets(), chain)
		if handle ~= nil and last ~= nil then
			row += 1
			-- The dodge holds the body until it lets go (its blend out under the gait).
			if not handle.stopping and not handle.done then
				for group, names in PARTS do
					for _, part in names do
						local degrees = angleBetween(last[part], solved[part])
						if degrees > worst[group].degrees then
							worst[group] = { degrees = degrees, part = part, row = row }
						end
					end
				end
			end
		end
		last = solved
	end
	locomotion:destroy()
	Choreo.release(model)
	return worst
end

describe("DodgeTakeOver", function()
	it("a dodge from any stance or gait turns no part over popDegrees a row (436(d))", function()
		local problems = {}
		local report = {}
		for _, drawn in { true, false } do
			for _, speed in { 0, ChoreoData.locomotion.walkSpeed, ChoreoData.locomotion.runSpeed } do
				local line = {}
				for _, entry in DODGES do
					local worst = dodge(entry.name, entry.way, drawn, speed)
					local cells = {}
					for _, group in { "Arms", "Legs", "Body" } do
						local cell = worst[group]
						table.insert(cells, ("%.1f"):format(cell.degrees))
						if cell.degrees > Audit.popDegrees then
							table.insert(
								problems,
								("Dodge%s %s at %d studs/s: the %s turns %.1f degrees on row %d (popDegrees %d)"):format(
									entry.name,
									if drawn then "drawn" else "sheathed",
									speed,
									cell.part,
									cell.degrees,
									cell.row,
									Audit.popDegrees
								)
							)
						end
					end
					table.insert(line, entry.name .. " " .. table.concat(cells, "/"))
				end
				table.insert(
					report,
					("%s %d: %s"):format(if drawn then "drawn" else "sheathed", speed, table.concat(line, ", "))
				)
			end
		end
		print("DodgeTakeOver, arms/legs/body worst turn a row:\n  " .. table.concat(report, "\n  "))
		expect(table.concat(problems, "\n")).toBe("")
	end)
end)
