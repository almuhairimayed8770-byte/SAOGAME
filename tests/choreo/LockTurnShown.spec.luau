--!strict
--[[
	The lock turn as the screen shows it (D-505, Studio item 363(b)). The root's CFrame shows on the
	frame it is written; a pose shows one frame after the step that wrote it (impact.poseLagFrames).
	On 7d112ef CharacterController turned the root in its render step, before Locomotion's update,
	so each frame showed the root's new yaw under the pose that countered the yaw before it: the
	planted feet swung round with the root for a frame (the turn plant's Root took the yaw back
	one frame late). On the owner's PC the feet slid 0.13 to 0.32 a frame through the lock turns.
	Now the lock's turn lands on PreSimulation, after the step, and Locomotion reads the facing
	ahead (State.yawAhead), so the frame that shows the turned root shows the pose that took it
	back.

	As TurnPlant.spec.luau runs it (the real Choreo and Locomotion on a Lune rig, posed onto the hit
	matrix's player on its field, 90, 135 and 180 degrees each way, drawn and sheathed, at
	combat.aim.lockTurnRate), except that each step hands Locomotion the turn as yawAhead with the
	root still where the last frame left it, writes the turn after the step, and poses the root
	as it then stands with that step's offsets: the frame that shows them together. A foot counts as
	planted by its corners within locomotion.stride.contact of the field; over any 60 Hz frame its
	least-moving grounded corner moves no more than dev.luau groundClearance.lockTurn.slideStuds,
	and over one plant no more than lockTurn.driftStuds from where it touched down (363(b)). The
	chest and the head lead the hips by at most choreo.luau turnPlant.twistDegrees (363(c)), within
	lockTurn.leadSlack: on 7d112ef a drawn turn to the right led by 57.5, the drawn stance's own 12
	degrees on top of the plant's 45 (D-507).

	AR 513 (D-615): the same turns started at each of lockTurn.idleStarts seconds into the drawn
	idle, where its weight shift holds the hips up to 0.1 stud off the root's axis (IdleDrawn's Root
	at 0.08, 0.06 from 3 s). On 81b8fef the plant took the root's yaw back but left that offset on
	the turning root, so both feet swung round with it: 0.029 a 60 Hz row at 3 s, 0.016 at 10 s
	(the owner's PC 0.011 to 0.047 on four of six turns). Each 60 Hz row's least-moving corner
	within the contact band of the field on both rows (513(a)'s read) moves at most
	lockTurn.rowStuds.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
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
local Rigs = Harness.load("src/shared/data/rigs")
local Pose = Harness.load("src/shared/choreo/Pose")
local Combat = Harness.load("src/shared/data/combat")
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
local avatar, field = HitMatrix.standing(Harness)
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local FIELD_TOP = ClipAudit.topOf(field.CFrame, field.Size)
local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")
local CONTACT = ChoreoData.locomotion.stride.contact
local Bar = Dev.groundClearance.lockTurn
local chain = Pose.chain(avatar.model)
local function buildRig(): any
	local model = Instance.new("Model")
	model.Name = "PlayerR15"
	model:SetAttribute("Rig", "PlayerR15")
	local parts = {}
	local function part(name: string): any
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Position = Vector3.zero
		created.Parent = model
		parts[name] = created
		return created
	end
	for _, joint in Rigs.PlayerR15.joints do
		part(joint.part0)
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Parent = part(joint.part1)
	end
	model.PrimaryPart = parts.HumanoidRootPart
	return model
end

local FOOT = { "LeftFoot", "RightFoot" }
local function yawOfFrame(frame: CFrame): number
	local look = frame.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end
-- The most the chest and the head led the hips in the last run (degrees, + = left).
local leads: { [string]: number } = { UpperTorso = 0, Head = 0 }
local function bottom(frame: CFrame, size: Vector3): { Vector3 }
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(out, (frame * CFrame.new(sx * size.X / 2, -size.Y / 2, sz * size.Z / 2)).Position)
		end
	end
	return out
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end
type Track = {
	worstSlide: number,
	slideAt: number,
	worstDrift: number,
	driftAt: number,
	worstRow: number, -- AR 513(a): the most the least-moving corner within the band moved in a row
	rowAt: number,
	last: { Vector3 }?,
	down: { Vector3 }?,
	grounded: { boolean }?,
}
local function run(
	degrees: number,
	side: number,
	hz: number,
	rate: number,
	drawn: boolean,
	start: number?
): { [string]: Track }
	-- The turn starts this many seconds into the idle (AR 513: the drawn idle's weight shift).
	local from = start or 0.5
	local model = buildRig()
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, { footIK = false })
	local dt = 1 / hz
	local yaw, left = 0, degrees
	local tracks: { [string]: Track } = {}
	for _, name in FOOT do
		tracks[name] = { worstSlide = 0, slideAt = 0, worstDrift = 0, driftAt = 0, worstRow = 0, rowAt = 0 }
	end
	leads.UpperTorso, leads.Head = 0, 0
	local frames = math.floor((from + 1.1) * hz)
	local per60 = hz / 60
	local slideAcc: { [string]: { number } } = { LeftFoot = {}, RightFoot = {} }
	for frame = 1, frames do
		local t = frame * dt
		-- The render step: the root still stands where the last frame left it; the lock's turn
		-- this frame is handed to Locomotion ahead.
		local ahead = 0
		if t > from then
			local step = math.min(left, rate * dt)
			left -= step
			ahead = step * side
		end
		model.PrimaryPart.CFrame = CFrame.Angles(0, math.rad(yaw), 0)
		locomotion:update(dt, {
			moveDir = Vector3.zero,
			speed = 0,
			sprinting = false,
			grounded = true,
			drawn = drawn,
			turning = 0,
			verticalVelocity = 0,
			yawAhead = ahead,
		})
		animator:step(dt)
		-- PreSimulation: the turn lands on the root; the frame that shows this step's pose shows
		-- the root standing so.
		yaw += ahead
		model.PrimaryPart.CFrame = CFrame.Angles(0, math.rad(yaw), 0)
		local rootFrame = avatar.base * CFrame.Angles(0, math.rad(yaw), 0)
		local solved = Pose.solve(avatar.model, rootFrame, animator.mixer:lastOffsets(), chain)
		-- How far the chest and the head stand round from the hips (+ = left), on the shown frame.
		for _, part in { "UpperTorso", "Head" } do
			local lead = (yawOfFrame(solved[part]) - yawOfFrame(solved.LowerTorso) + 180) % 360 - 180
			if math.abs(lead) > math.abs(leads[part]) then
				leads[part] = lead
			end
		end
		if t < from - 1e-9 then
			continue
		end
		for _, name in FOOT do
			local track = tracks[name]
			local now = bottom(solved[name], (avatar.model:FindFirstChild(name) :: any).Size)
			local grounded = {}
			for i = 1, 4 do
				grounded[i] = now[i].Y - FIELD_TOP <= CONTACT
			end
			local last, wasDown = track.last, track.grounded
			if last ~= nil then
				-- AR 513(a): the least-moving corner within the band of the field on both rows.
				local least = math.huge
				for i = 1, 4 do
					if
						math.abs(now[i].Y - FIELD_TOP) <= CONTACT
						and math.abs((last :: { Vector3 })[i].Y - FIELD_TOP) <= CONTACT
					then
						least = math.min(least, (flat(now[i]) - flat((last :: { Vector3 })[i])).Magnitude)
					end
				end
				if least < math.huge and least > track.worstRow then
					track.worstRow = least
					track.rowAt = t - from
				end
			end
			if last ~= nil and wasDown ~= nil then
				-- slide: the least-moving corner grounded through the frame
				local least = math.huge
				for i = 1, 4 do
					if grounded[i] and wasDown[i] then
						least = math.min(least, (flat(now[i]) - flat(last[i])).Magnitude)
					end
				end
				if least < math.huge then
					local acc = slideAcc[name]
					table.insert(acc, least)
					local sum = 0
					for k = math.max(1, #acc - math.floor(per60 + 0.5) + 1), #acc do
						sum += acc[k]
					end
					if sum > track.worstSlide then
						track.worstSlide = sum
						track.slideAt = t - from
					end
				else
					slideAcc[name] = {}
				end
			end
			-- drift: from touch-down, the least-moving corner grounded since then
			local any = false
			for i = 1, 4 do
				any = any or grounded[i]
			end
			if any then
				if track.down == nil then
					track.down = table.clone(now)
					track.keep = table.clone(grounded)
				else
					local least = math.huge
					for i = 1, 4 do
						(track :: any).keep[i] = (track :: any).keep[i] and grounded[i]
						if (track :: any).keep[i] then
							least = math.min(least, (flat(now[i]) - flat((track.down :: any)[i])).Magnitude)
						end
					end
					if least == math.huge then
						track.down = table.clone(now);
						(track :: any).keep = table.clone(grounded)
					elseif least > track.worstDrift then
						track.worstDrift = least
						track.driftAt = t - from
					end
				end
			else
				track.down = nil
			end
			track.last = now
			track.grounded = grounded
		end
	end
	locomotion:destroy()
	Choreo.release(model)
	return tracks
end
describe("the lock turn as the frame shows it (363(b), D-505)", function()
	for _, case in { { -1, true }, { 1, true }, { -1, false }, { 1, false } } do
		local side, drawn = case[1] :: number, case[2] :: boolean
		it(
			("the lock turns the standing %s body to the %s: the shown root and pose keep each planted foot"):format(
				if drawn then "drawn" else "sheathed",
				if side < 0 then "right" else "left"
			),
			function()
				local problems = {}
				local worst: { [string]: number } = { slide = 0, drift = 0 }
				for _, degrees in Bar.degrees do
					for _, hz in Bar.stepHz do
						local tracks = run(degrees, side, hz, Combat.aim.lockTurnRate, drawn)
						for part, lead in leads do
							worst[part] = math.max(worst[part] or 0, math.abs(lead))
							if math.abs(lead) > ChoreoData.locomotion.turnPlant.twistDegrees + Bar.leadSlack then
								table.insert(
									problems,
									("%d deg %d Hz: the %s leads the hips by %.1f degrees (choreo.luau turnPlant.twistDegrees %d)"):format(
										degrees,
										hz,
										if part == "Head" then "head" else "chest",
										lead,
										ChoreoData.locomotion.turnPlant.twistDegrees
									)
								)
							end
						end
						for _, name in FOOT do
							local track = tracks[name]
							worst.slide = math.max(worst.slide, track.worstSlide)
							worst.drift = math.max(worst.drift, track.worstDrift)
							if track.worstSlide > Bar.slideStuds + 1e-6 then
								table.insert(
									problems,
									("%d deg %d Hz %s slides %.3f in a 60 Hz frame while planted at +%.3f s (max %.2f)"):format(
										degrees,
										hz,
										name,
										track.worstSlide,
										track.slideAt,
										Bar.slideStuds
									)
								)
							end
							if track.worstDrift > Bar.driftStuds + 1e-6 then
								table.insert(
									problems,
									("%d deg %d Hz %s drifts %.3f over one plant at +%.3f s (max %.2f)"):format(
										degrees,
										hz,
										name,
										track.worstDrift,
										track.driftAt,
										Bar.driftStuds
									)
								)
							end
						end
					end
				end
				print(
					("LockTurnShown %s side %d: worst slide %.3f, drift %.3f, chest lead %.1f, head lead %.1f"):format(
						tostring(drawn),
						side,
						worst.slide,
						worst.drift,
						worst.UpperTorso or 0,
						worst.Head or 0
					)
				)
				expect(table.concat(problems, "\n")).toBe("")
			end
		)
	end
end)

describe("the lock turn from the drawn idle's weight shift (AR 513, D-615)", function()
	for _, side in { -1, 1 } do
		it(
			("the lock turns the drawn body to the %s from every idle phase: the hips' offset turns with them"):format(
				if side < 0 then "right" else "left"
			),
			function()
				local problems = {}
				local worst: { [string]: number } = { row = 0, slide = 0, drift = 0 }
				for _, start in Bar.idleStarts do
					for _, degrees in Bar.degrees do
						local tracks = run(degrees, side, 60, Combat.aim.lockTurnRate, true, start)
						for _, name in FOOT do
							local track = tracks[name]
							worst.row = math.max(worst.row, track.worstRow)
							worst.slide = math.max(worst.slide, track.worstSlide)
							worst.drift = math.max(worst.drift, track.worstDrift)
							if track.worstRow > Bar.rowStuds + 1e-6 then
								table.insert(
									problems,
									("%d deg from %.1f s into the idle: %s moves %.4f in a 60 Hz row on the field at +%.3f s (max %.3f)"):format(
										degrees,
										start,
										name,
										track.worstRow,
										track.rowAt,
										Bar.rowStuds
									)
								)
							end
							if track.worstDrift > Bar.driftStuds + 1e-6 then
								table.insert(
									problems,
									("%d deg from %.1f s into the idle: %s drifts %.3f over one plant at +%.3f s (max %.2f)"):format(
										degrees,
										start,
										name,
										track.worstDrift,
										track.driftAt,
										Bar.driftStuds
									)
								)
							end
						end
					end
				end
				print(
					("LockTurnShown idle phases side %d: worst row %.4f, frame %.4f, drift %.3f"):format(
						side,
						worst.row,
						worst.slide,
						worst.drift
					)
				)
				expect(table.concat(problems, "\n")).toBe("")
			end
		)
	end
end)
