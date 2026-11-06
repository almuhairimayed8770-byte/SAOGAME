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

	D-626: the sheathed turns from lockTurn.sheathedIdleStarts seconds into the sheathed idle
	(its weight shift onto the left leg, 4.5 to 8.2 s), at each of lockTurn.sheathedStepHz, the row
	read summed over the rows of a 60 Hz row's time. The weight shift carried both feet 0.15 to 0.17
	off where the cycle starts them, which is where the turn clips stand them: a turn's 0.08 s
	blend in brought them back in five rows and its 0.15 s blend out took them away again (0.045 a
	60 Hz row, 15 of 48 idle phases over 0.01). Its legs are now solved at the shift's key, as the
	drawn idle's were (D-417), and the idle's own soles hold within stride.contact of their start.
	As every case above, the body stays sheathed: a lock-on's own draw (the stance changing under
	the turn) is not in this read.

	D-640: a lock-on from the sheathed body, the sword rig the server's WeaponBuilder hung, the
	lock calling the predicted draw as Main.client.luau hooks TargetController.targetChanged
	(CharacterController.predictDraw's stamp, read through ActionLogic.drawnTarget on the lock's
	first frame). The draw changed the stance under the turn: the Base set crossfaded Idle to
	IdleDrawn under the sheathed turn's entry and the turn blended out into the drawn stance, whose
	feet stand 0.2 and 0.6 studs off the sheathed one (0.10 to 0.15 a 60 Hz row's time); a standing
	lock-on and a standing sheathe slid the same way under nothing (0.08 to 0.10). Now the turn
	steps into the drawn stance (TurnLeftDraw, TurnRightDraw), a standing change takes a step
	(DrawStep, SheatheStep), and the Base set holds until that clip shows at full weight. From
	lockTurn.idlePhaseCount phases of the idle, at each of sheathedStepHz, every row's read moves
	at most rowStuds over a 60 Hz row's time, and the Draw still starts on the lock's frame
	standing, after the turn turning (D-050, 323(b)).

	D-641: the turns, drawn and sheathed, from each phase on the owner's PC's row times
	(lockTurn.pcRowSeconds, seeded): the hips' come-round ended on the second plant's touchdown row,
	which read up to 0.026 on 11 and 19 of 288 turns. It now ends turnPlant.leadSeconds of clip time
	before it (one row at 60, three at 144).
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
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
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
	-- D-626: the same read summed over the rows of a 60 Hz row's time (as many rows as cover
	-- 1/60 s; one at 60 Hz, three at 144), a row with no corner in the band counting none.
	worstRow60: number,
	row60At: number,
	recent: { number },
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
		tracks[name] = {
			worstSlide = 0,
			slideAt = 0,
			worstDrift = 0,
			driftAt = 0,
			worstRow = 0,
			rowAt = 0,
			worstRow60 = 0,
			row60At = 0,
			recent = {},
		}
	end
	leads.UpperTorso, leads.Head = 0, 0
	local frames = math.floor((from + 1.1) * hz)
	local per60 = hz / 60
	local rows60 = math.max(1, math.ceil(per60 - 1e-9))
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
				local recent = track.recent
				table.insert(recent, if least < math.huge then least else 0)
				if #recent > rows60 then
					table.remove(recent, 1)
				end
				local sum = 0
				for _, moved in recent do
					sum += moved
				end
				if sum > track.worstRow60 then
					track.worstRow60 = sum
					track.row60At = t - from
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

describe("the lock turn from the sheathed idle's weight shift (D-626)", function()
	it("the sheathed idle keeps both feet where its cycle starts them through its weight shift", function()
		local clip = ClipLibrary.get(ChoreoData.locomotion.clipPrefix .. ChoreoData.locomotion.clips.Idle)
		local function corners(time: number): { [string]: { Vector3 } }
			local solved = Pose.solve(avatar.model, avatar.base, ClipSampler.sample(clip, time), chain)
			local out = {}
			for _, name in FOOT do
				out[name] = bottom(solved[name], (avatar.model:FindFirstChild(name) :: any).Size)
			end
			return out
		end
		local start = corners(0)
		-- Each foot's farthest corner from its start, across and up or down, and when.
		local worst: { [string]: { moved: number, movedAt: number, rose: number, roseAt: number } } = {}
		for _, name in FOOT do
			worst[name] = { moved = 0, movedAt = 0, rose = 0, roseAt = 0 }
		end
		for index = 1, 240 do
			local time = clip.duration * index / 240
			for name, now in corners(time) do
				local most = worst[name]
				for i = 1, 4 do
					local from = start[name][i]
					local moved = (flat(now[i]) - flat(from)).Magnitude
					local rose = math.abs(now[i].Y - from.Y)
					if moved > most.moved then
						most.moved, most.movedAt = moved, time
					end
					if rose > most.rose then
						most.rose, most.roseAt = rose, time
					end
				end
			end
		end
		local problems = {}
		for _, name in FOOT do
			local most = worst[name]
			if most.moved > CONTACT or most.rose > CONTACT then
				table.insert(
					problems,
					("%s: a sole corner moves %.3f across its start (at %.2f s) and %.3f up or down (at %.2f s), max %.2f"):format(
						name,
						most.moved,
						most.movedAt,
						most.rose,
						most.roseAt,
						CONTACT
					)
				)
			end
		end
		print(
			("LockTurnShown sheathed idle: a sole corner moved %.4f / %.4f, rose or sank %.4f / %.4f (left / right)"):format(
				worst.LeftFoot.moved,
				worst.RightFoot.moved,
				worst.LeftFoot.rose,
				worst.RightFoot.rose
			)
		)
		expect(table.concat(problems, "\n")).toBe("")
	end)

	for _, side in { -1, 1 } do
		it(
			("the lock turns the sheathed body to the %s from the idle's weight shift: its feet hold"):format(
				if side < 0 then "right" else "left"
			),
			function()
				local problems = {}
				local worst: { [number]: number } = {}
				for _, start in Bar.sheathedIdleStarts do
					for _, degrees in Bar.degrees do
						for _, hz in Bar.sheathedStepHz do
							local tracks = run(degrees, side, hz, Combat.aim.lockTurnRate, false, start)
							for _, name in FOOT do
								local track = tracks[name]
								-- The moves over a 60 Hz row's time.
								local row = track.worstRow60
								worst[hz] = math.max(worst[hz] or 0, row)
								if row > Bar.rowStuds + 1e-6 then
									table.insert(
										problems,
										("%d deg %d Hz from %.1f s into the sheathed idle: %s moves %.4f in a 60 Hz row's time on the field at +%.3f s (max %.3f)"):format(
											degrees,
											hz,
											start,
											name,
											row,
											track.row60At,
											Bar.rowStuds
										)
									)
								end
								if track.worstDrift > Bar.driftStuds + 1e-6 then
									table.insert(
										problems,
										("%d deg %d Hz from %.1f s into the sheathed idle: %s drifts %.3f over one plant at +%.3f s (max %.2f)"):format(
											degrees,
											hz,
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
				end
				local parts = {}
				for _, hz in Bar.sheathedStepHz do
					table.insert(parts, ("%d Hz %.4f"):format(hz, worst[hz] or 0))
				end
				print(
					("LockTurnShown sheathed idle phases side %d: worst row in a 60 Hz row's time %s"):format(
						side,
						table.concat(parts, ", ")
					)
				)
				expect(table.concat(problems, "\n")).toBe("")
			end
		)
	end
end)

-- D-640 and D-641: the lock-on from the sheathed body, and the turns on the PC's row times.
local Signal = Harness.load("src/shared/util/Signal")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")
local world = Instance.new("Folder")
world.Name = "World"

-- A player rig the server's WeaponBuilder hung its sword on (SheathLockTurn.spec.luau's): the
-- Draw plays on it, and the turn under way holds it back as it does in play.
local function buildSwordRig(): any
	local model = Instance.new("Model")
	model.Name = "Player"
	model:SetAttribute("Rig", "PlayerR15")
	local parts = {}
	local function part(name: string): any
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Size = Vector3.new(1, 1, 1)
		created.CFrame = CFrame.new(0, 3, 0)
		created.Position = Vector3.new(0, 3, 0)
		created.Parent = model
		parts[name] = created
		return created
	end
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name == WeaponModels.motorName then
			continue
		end
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Part0 = part(joint.part0)
		motor.Part1 = part(joint.part1)
		motor.C0 = RigBuilder.frameOf(joint.c0)
		motor.Parent = motor.Part1
	end
	model.PrimaryPart = parts.HumanoidRootPart
	WeaponBuilder.equip(model, Weapons.byId("TrialistSword"))
	model.Parent = world
	return model
end

type LockRun = {
	degrees: number, -- the lock turns the body this far (0: a standing lock-on, the target ahead)
	side: number, -- -1 to the right, 1 to the left
	start: number, -- seconds into the idle the lock comes
	hz: number?, -- each row 1 / hz seconds, or
	seed: number?, -- each row's time drawn from lockTurn.pcRowSeconds by a generator seeded so
	drawn: boolean, -- the body stands drawn
	lockOn: boolean?, -- the lock-on asks for the sword (the sword rig, standing sheathed)
	-- The sword rig stands drawn, sword in hand, and the server's Drawn turns false at `start`
	-- (no lock, the combat tag run out): the Sheathe plays after sheath.sheatheDelay.
	sheathe: boolean?,
	clips: { [string]: boolean }?, -- filled with every full-body clip that played after the lock
}
-- The most a foot's least-moving corner within stride.contact of the field on both rows (AR
-- 513(a)'s read) moved over a 60 Hz row's time after the lock, when (seconds after it), and the
-- Draw's start (seconds after the lock; nil: none played).
type LockRead = { LeftFoot: { worst: number, at: number }, RightFoot: { worst: number, at: number }, drawAt: number? }
local DRAW_ID = ChoreoData.locomotion.clipPrefix .. ChoreoData.sheath.clips.draw
local SHEATHE_ID = ChoreoData.locomotion.clipPrefix .. ChoreoData.sheath.clips.sheathe
-- The read runs this long after the lock: a turn's clip comes about 4 rows in and is gone by
-- +0.72 s (0.5 s and its 0.15 s blend out); a stance step by +0.6 s.
local LOCK_READ_SECONDS = 0.9
local function lockRun(opts: LockRun): LockRead
	local model = if opts.lockOn or opts.sheathe then buildSwordRig() else buildRig()
	if opts.sheathe then
		model:SetAttribute("Drawn", true)
	end
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, { footIK = false })
	-- TargetController.targetChanged as Main.client.luau hooks it up: a lock calls
	-- CharacterController.predictDraw, which stamps the clock; every frame the controller hands
	-- Locomotion ActionLogic.drawnTarget(the server's Drawn, that stamp, now, sheath.predictSeconds).
	local targetChanged = Signal.new()
	local clock = 0
	local lastPredictAt: number? = nil
	targetChanged:Connect(function(record: any)
		if record ~= nil then
			lastPredictAt = clock
		end
	end)
	local seeded = opts.seed ~= nil
	local seed: number = opts.seed or 0
	local function rowTime(): number
		if not seeded then
			return 1 / (opts.hz or 60)
		end
		seed = (seed * 1103515245 + 12345) % 2147483648
		local least, most = Bar.pcRowSeconds[1], Bar.pcRowSeconds[2]
		return least + (most - least) * seed / 2147483648
	end
	-- Rows that cover a 60 Hz row's time (one on the PC's rows).
	local rows60 = if seeded then 1 else math.max(1, math.ceil((opts.hz or 60) / 60 - 1e-9))
	local read: LockRead = {
		LeftFoot = { worst = 0, at = 0 },
		RightFoot = { worst = 0, at = 0 },
		drawAt = nil,
	}
	local recent: { [string]: { number } } = { LeftFoot = {}, RightFoot = {} }
	local last: { [string]: { Vector3 } } = {}
	local yaw, left = 0, opts.degrees
	local locked = false
	-- The body stands until two 60 Hz rows before the lock on rows of a fifth of a second (the
	-- idle's clocks only run on: every number below is the same on 60 Hz rows), then on the run's
	-- own rows.
	local settle = opts.start - 2 / 60
	-- A sheathe changes the stance once the Sheathe has come in over the arm (Locomotion's
	-- showsDrawn): sheatheDelay and the clip's blend in later.
	local reads = LOCK_READ_SECONDS
		+ (if opts.sheathe then ChoreoData.sheath.sheatheDelay + ClipLibrary.get(SHEATHE_ID).blendIn else 0)
	while clock < opts.start + reads do
		local dt = if clock < settle then math.min(0.2, settle - clock) else rowTime()
		local fine = clock >= settle
		clock += dt
		local ahead = 0
		if fine and clock > opts.start then
			if not locked then
				locked = true
				if opts.lockOn then
					targetChanged:Fire({})
				end
			end
			local step = math.min(left, Combat.aim.lockTurnRate * dt)
			left -= step
			ahead = step * opts.side
		end
		model.PrimaryPart.CFrame = CFrame.Angles(0, math.rad(yaw), 0)
		locomotion:update(dt, {
			moveDir = Vector3.zero,
			speed = 0,
			sprinting = false,
			grounded = true,
			drawn = opts.drawn or ActionLogic.drawnTarget(
				opts.sheathe == true and clock <= opts.start,
				lastPredictAt,
				clock,
				ChoreoData.sheath.predictSeconds
			),
			turning = 0,
			verticalVelocity = 0,
			yawAhead = ahead,
		})
		animator:step(dt)
		yaw += ahead
		model.PrimaryPart.CFrame = CFrame.Angles(0, math.rad(yaw), 0)
		if not fine then
			continue
		end
		if locked then
			for _, handle in animator.mixer:handles() do
				if handle.clipId == DRAW_ID and read.drawAt == nil then
					read.drawAt = clock - opts.start
				end
				if opts.clips ~= nil and handle.layer == "FullBody" and handle.weight > 0 then
					(opts.clips :: { [string]: boolean })[handle.clipId:match("[^/]+$") or handle.clipId] = true
				end
			end
		end
		local rootFrame = avatar.base * CFrame.Angles(0, math.rad(yaw), 0)
		local solved = Pose.solve(avatar.model, rootFrame, animator.mixer:lastOffsets(), chain)
		for _, name in FOOT do
			local now = bottom(solved[name], (avatar.model:FindFirstChild(name) :: any).Size)
			local before = last[name]
			last[name] = now
			if before == nil or not locked then
				continue
			end
			local least = math.huge
			for i = 1, 4 do
				if math.abs(now[i].Y - FIELD_TOP) <= CONTACT and math.abs(before[i].Y - FIELD_TOP) <= CONTACT then
					least = math.min(least, (flat(now[i]) - flat(before[i])).Magnitude)
				end
			end
			local moves = recent[name]
			table.insert(moves, if least < math.huge then least else 0)
			if #moves > rows60 then
				table.remove(moves, 1)
			end
			local sum = 0
			for _, moved in moves do
				sum += moved
			end
			local foot = (read :: any)[name]
			if sum > foot.worst then
				foot.worst = sum
				foot.at = clock - opts.start
			end
		end
	end
	locomotion:destroy()
	Choreo.release(model)
	return read
end

-- Every phase of the sweep: lockTurn.idlePhaseCount points spread evenly over one cycle of the
-- idle (12 s: a quarter second apart), from half a second stood (the other cases' start).
local function phases(): { number }
	local cycle = ClipLibrary.get(ChoreoData.locomotion.clipPrefix .. ChoreoData.locomotion.clips.Idle).duration
	local out = {}
	for index = 0, Bar.idlePhaseCount - 1 do
		table.insert(out, 0.5 + index * cycle / Bar.idlePhaseCount)
	end
	return out
end

-- Runs every run of the sweep and returns the problems, the worst read and how many runs were over.
local function sweep(label: string, runs: { LockRun }): ({ string }, number, number, number)
	local problems = {}
	local worst, over, count = 0, 0, 0
	for _, opts in runs do
		local read = lockRun(opts)
		count += 1
		local most = 0
		for _, name in FOOT do
			local foot = (read :: any)[name]
			most = math.max(most, foot.worst)
			if foot.worst > Bar.rowStuds + 1e-6 then
				table.insert(
					problems,
					("%s %d deg side %d %s from %.2f s into the idle: %s moves %.4f in a 60 Hz row's time on the field at +%.3f s (max %.3f)"):format(
						label,
						opts.degrees,
						opts.side,
						if opts.seed ~= nil then "on the PC's rows" else ("at %d Hz"):format(opts.hz or 60),
						opts.start,
						name,
						foot.worst,
						foot.at,
						Bar.rowStuds
					)
				)
			end
		end
		worst = math.max(worst, most)
		if most > Bar.rowStuds + 1e-6 then
			over += 1
		end
	end
	return problems, worst, over, count
end

describe("a lock-on from the sheathed body steps into the drawn stance (D-640)", function()
	for _, side in { -1, 1 } do
		it(
			("the lock turns the sheathed body to the %s as it draws, from every idle phase: no sole slides"):format(
				if side < 0 then "right" else "left"
			),
			function()
				local lines, parts = {}, {}
				for _, hz in Bar.sheathedStepHz do
					local runs: { LockRun } = {}
					for _, start in phases() do
						for _, degrees in Bar.degrees do
							table.insert(
								runs,
								{ degrees = degrees, side = side, start = start, hz = hz, drawn = false, lockOn = true }
							)
						end
					end
					local problems, worst, over, count = sweep("lock turn", runs)
					table.move(problems, 1, #problems, #lines + 1, lines)
					table.insert(parts, ("%d Hz worst %.4f, %d of %d over"):format(hz, worst, over, count))
				end
				print(("LockTurnShown lock-on side %d: %s"):format(side, table.concat(parts, "; ")))
				expect(table.concat(lines, "\n")).toBe("")
			end
		)
	end

	it("a standing lock-on draws from every idle phase: the feet step into the drawn stance", function()
		local lines, parts = {}, {}
		for _, hz in Bar.sheathedStepHz do
			local runs: { LockRun } = {}
			for _, start in phases() do
				table.insert(runs, { degrees = 0, side = 1, start = start, hz = hz, drawn = false, lockOn = true })
			end
			local problems, worst, over, count = sweep("standing lock-on", runs)
			table.move(problems, 1, #problems, #lines + 1, lines)
			table.insert(parts, ("%d Hz worst %.4f, %d of %d over"):format(hz, worst, over, count))
		end
		print(("LockTurnShown standing lock-on: %s"):format(table.concat(parts, "; ")))
		expect(table.concat(lines, "\n")).toBe("")
	end)

	it("a standing sheathe from every idle phase: the feet step back into the idle's stance", function()
		local lines, parts = {}, {}
		for _, hz in Bar.sheathedStepHz do
			local runs: { LockRun } = {}
			for _, start in phases() do
				table.insert(runs, { degrees = 0, side = 1, start = start, hz = hz, drawn = false, sheathe = true })
			end
			local problems, worst, over, count = sweep("standing sheathe", runs)
			table.move(problems, 1, #problems, #lines + 1, lines)
			table.insert(parts, ("%d Hz worst %.4f, %d of %d over"):format(hz, worst, over, count))
		end
		print(("LockTurnShown standing sheathe: %s"):format(table.concat(parts, "; ")))
		expect(table.concat(lines, "\n")).toBe("")
	end)

	it("plays the turn into the drawn stance, and the Draw on the lock's frame or after the turn", function()
		-- The Draw's timing stands (D-050): a standing lock-on draws on its first frame; a lock
		-- turn holds the Draw for the turn (323(b)), as the sheathed turn did.
		local seen: { [string]: boolean } = {}
		local standing = lockRun({ degrees = 0, side = 1, start = 0.5, hz = 60, drawn = false, lockOn = true })
		local turn =
			lockRun({ degrees = 135, side = -1, start = 0.5, hz = 60, drawn = false, lockOn = true, clips = seen })
		print(
			("LockTurnShown lock-on Draw: standing +%.3f s, 135 to the right +%.3f s"):format(
				standing.drawAt or -1,
				turn.drawAt or -1
			)
		)
		expect(standing.drawAt).toBeCloseTo(1 / 60, 1e-6)
		expect(seen[ChoreoData.locomotion.clips.TurnRightDraw]).toBe(true)
		expect(seen[ChoreoData.locomotion.clips.TurnRight]).toBeNil()
		expect((turn.drawAt or 0) > ChoreoData.locomotion.turnClipDuration).toBe(true)
	end)
end)

describe("the hips are round before the second plant lands (D-641)", function()
	for _, drawn in { true, false } do
		it(
			("the lock turns the standing %s body from every idle phase on the PC's row times: no sole slides"):format(
				if drawn then "drawn" else "sheathed"
			),
			function()
				local runs: { LockRun } = {}
				for index, start in phases() do
					for _, side in { -1, 1 } do
						for _, degrees in Bar.degrees do
							table.insert(runs, {
								degrees = degrees,
								side = side,
								start = start,
								seed = Bar.rowSeed + index,
								drawn = drawn,
							})
						end
					end
				end
				local problems, worst, over, count = sweep(if drawn then "drawn" else "sheathed", runs)
				print(
					("LockTurnShown %s on the PC's rows: worst %.4f, %d of %d over"):format(
						if drawn then "drawn" else "sheathed",
						worst,
						over,
						count
					)
				)
				expect(table.concat(problems, "\n")).toBe("")
			end
		)
	end
end)
