--!strict
--[[
	A dodge out of the run at every point of its stride (Studio item 515(b) and (d); D-609,
	D-610). DodgeTakeOver.spec.luau presses each dodge at one point of each gait and reads the
	rows while the dodge holds the body; this one presses DodgeForward (the unlocked run's dodge)
	at dev.luau groundClearance.dodgeRun.points points of one stride cycle of the run, drawn and
	sheathed, and reads three windows of 60 Hz rows (row +1 is the first row the dodge shows, the
	step of the press):
	- row +1: the stride's last step is still in it (its phase stands from this step, but its
	  clock moved one more frame), so each part turns at most max(popDegrees, the part's own most
	  over the stride before the press + slack);
	- from row +2 until the dodge lets go: every part at most popDegrees (the gait stands, so the
	  turn is the dodge's blend in and its own keys);
	- the blend out (the clip's end until it has gone, and the first row after): each part at most
	  max(popDegrees, its own most over the stride + slack), the gait striding again under it.

	On 81b8fef the stride stood where the press found it and was picked up there after the dodge:
	the 0.15 s blend out crossed a lower leg swinging away from the dodge's one landing pose, 25.2
	degrees a row out of the sheathed run (7 of 24 points over the bar) and 21.9 out of the drawn
	run (4 of 24). Now the stride is picked up at locomotion.dodgeHandOff.resumePhase. And over its
	0.12 s leg blend the dodge crossed the held stride's lower leg into the lean at 20.7 and 21.1
	on row +4 from the drawn run (2 of 24 points); the legs now take 0.13 s.

	Real Choreo and Locomotion (foot IK on a flat field) on the hit matrix's player; the dodge
	played as CharacterController plays it (handOver, nothing live to cut), the root moved at the
	dodge's speed (combat.luau dodgeDistance / dodgeDuration) for dodgeDuration, the stick held
	forward throughout; each part's turn per row read in the root part's frame.
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

local Cases = Dev.groundClearance.dodgeRun
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

-- One row: each part's turn since the row before, and where the dodge stood.
type Row = { turns: { [string]: number }, stopping: boolean, done: boolean }
type Take = { rows: { [number]: Row }, cycle: number }

-- The run held for `settle + lead` seconds, DodgeForward pressed, `after` seconds more. Rows are
-- keyed by the step after the press (0: the press step, shown on row +1).
local function take(drawn: boolean, lead: number, dodge: string): Take
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
	local press = math.floor((Cases.settle + lead) * HZ + 0.5)
	local offset = Vector3.zero
	local last: any = nil
	local handle: any = nil
	local result: Take = { rows = {}, cycle = 0 }
	for frame = 1, press + math.floor(Cases.after * HZ + 0.5) do
		clock += dt
		local k = frame - press
		if handle == nil and k >= 0 then
			result.cycle = 1 / locomotion.gaitPace
			handle = animator:play(PREFIX .. dodge, { handOver = true })
		end
		local dodging = handle ~= nil and k * dt < Combat.dodgeDuration - 1e-9
		local velocity = if dodging then WAYS[dodge] * DODGE_SPEED else Vector3.new(0, 0, -Cases.speed)
		offset += velocity * dt
		local rootFrame = avatar.base * CFrame.new(offset)
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = Vector3.new(0, 0, -1),
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
		if last ~= nil and k > -2 * HZ then
			local turns: { [string]: number } = {}
			for _, part in PARTS do
				turns[part] = angleBetween(last[part], solved[part])
			end
			result.rows[k] = {
				turns = turns,
				stopping = handle ~= nil and handle.stopping and not handle.done,
				done = handle ~= nil and handle.done,
			}
		end
		last = solved
	end
	locomotion:destroy()
	Choreo.release(model)
	return result
end

type Worst = { degrees: number, over: number, at: string }

-- Each window's worst turn, its worst excess over its bar, and the points of the stride it fails.
local function judge(drawn: boolean, dodge: string): ({ [string]: Worst }, { [string]: number }, number)
	local windows = { "row1", "held", "out" }
	local worst: { [string]: Worst } = {}
	local failing: { [string]: number } = {}
	for _, name in windows do
		worst[name] = { degrees = 0, over = -math.huge, at = "" }
		failing[name] = 0
	end
	local cycle = take(drawn, 0, dodge).cycle
	for point = 0, Cases.points - 1 do
		local lead = point * cycle / Cases.points
		local result = take(drawn, lead, dodge)
		-- The stride's own most per part over the cycle before the press.
		local own: { [string]: number } = {}
		for _, part in PARTS do
			local most = 0
			for k = -math.ceil(cycle * HZ), -1 do
				most = math.max(most, result.rows[k].turns[part])
			end
			own[part] = most
		end
		local fails: { [string]: boolean } = {}
		local doneAt: number? = nil
		local k = 0
		while result.rows[k] ~= nil do
			local row = result.rows[k]
			if row.done and doneAt == nil then
				doneAt = k
			end
			local window: string? = nil
			if k == 0 then
				window = "row1"
			elseif not row.stopping and not row.done then
				window = "held"
			elseif row.stopping or (doneAt ~= nil and k <= doneAt) then
				window = "out"
			end
			if window ~= nil then
				for _, part in PARTS do
					local degrees = row.turns[part]
					local bar = if window == "held" then POP else math.max(POP, own[part] + Cases.slack)
					local cell = worst[window]
					if degrees > cell.degrees then
						cell.degrees = degrees
						cell.at = ("point %d (lead %.3f s) row +%d %s (bar %.1f)"):format(point, lead, k + 1, part, bar)
					end
					cell.over = math.max(cell.over, degrees - bar)
					if degrees > bar + 1e-9 then
						fails[window] = true
					end
				end
			end
			k += 1
		end
		for name in fails do
			failing[name] += 1
		end
	end
	return worst, failing, cycle
end

describe("DodgeRun", function()
	it("a dodge out of the run turns no part past its bar at any point of the stride (515(b), (d))", function()
		local problems: { string } = {}
		local report: { string } = {}
		local labels = {
			row1 = "row +1 (the stride's last step in it)",
			held = "rows +2 until the dodge lets go",
			out = "the blend out",
		}
		for _, dodge in ChoreoData.locomotion.dodgeHandOff.clips do
			for _, drawn in { true, false } do
				local stance = (if drawn then "drawn" else "sheathed") .. " " .. dodge
				local worst, failing, cycle = judge(drawn, dodge)
				for _, name in { "row1", "held", "out" } do
					local cell = worst[name]
					table.insert(
						report,
						("%s run %d (cycle %.3f s), %s: worst %.1f at %s; %d of %d points over the bar"):format(
							stance,
							Cases.speed,
							cycle,
							labels[name],
							cell.degrees,
							cell.at,
							failing[name],
							Cases.points
						)
					)
					if failing[name] > 0 then
						table.insert(
							problems,
							("%s run, %s: %d of %d points over the bar, by up to %.1f degrees (worst %.1f at %s)"):format(
								stance,
								labels[name],
								failing[name],
								Cases.points,
								cell.over,
								cell.degrees,
								cell.at
							)
						)
					end
				end
			end
		end
		print("DodgeRun:\n  " .. table.concat(report, "\n  "))
		expect(table.concat(problems, "\n")).toBe("")
	end)
end)
