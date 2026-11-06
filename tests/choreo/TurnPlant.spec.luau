--!strict
--[[
	A turn in place plants its feet (section 10 and section 21 gate line 4: no sliding foot; Studio
	item 323(d)). The lock turns a standing body toward a target behind it at combat.aim.lockTurnRate
	(720 degrees a second: 180 in 0.25 s) and Locomotion plays TurnLeft or TurnRight once the body has
	turned choreo.locomotion.turnInPlaceDegrees. On the owner's PC (1cf87aa, shot 10) the feet moved
	1.08 and 2.29 studs through the TurnRight; here a 180-degree turn to the right moves them 1.28 and
	2.09, and a planted foot slides 0.25-0.31 studs a 60 Hz frame and drifts up to 1.02 over one
	plant: the root yaws over feet the clip keeps on the ground, and the TurnRight's own left foot
	"drags round" (its header) on the ground.
	The real Choreo animator and Locomotion run on a Lune rig whose root the lock turns, standing
	drawn and standing sheathed (each stance plays its own turn clips, D-416), 90, 135 and 180 degrees
	each way, on 60 and 240 Hz frames; the mixer's offsets pose the hit
	matrix's player on its field (HitMatrix.standing, as ClipAudit poses every clip). A foot counts as
	planted by its corners within locomotion.stride.contact of the field, and is measured by its
	least-moving grounded corner (D-365): over any 60 Hz frame it moves no more than
	review.audit.footSlideStuds, and over one plant no more than review.audit.footDriftStuds from
	where it touched down. The bounds are ClipAudit's own; none moves.
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
local Audit = Dev.review.audit
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
	last: { Vector3 }?,
	down: { Vector3 }?,
	grounded: { boolean }?,
}
local function run(degrees: number, side: number, hz: number, rate: number, drawn: boolean): { [string]: Track }
	local model = buildRig()
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, { footIK = false })
	local dt = 1 / hz
	local yaw, left = 0, degrees
	local tracks: { [string]: Track } = {}
	for _, name in FOOT do
		tracks[name] = { worstSlide = 0, slideAt = 0, worstDrift = 0, driftAt = 0 }
	end
	local frames = math.floor(1.6 * hz)
	local per60 = hz / 60
	local slideAcc: { [string]: { number } } = { LeftFoot = {}, RightFoot = {} }
	for frame = 1, frames do
		local t = frame * dt
		if t > 0.5 then
			local step = math.min(left, rate * dt)
			left -= step
			yaw += step * side
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
		})
		animator:step(dt)
		local rootFrame = avatar.base * CFrame.Angles(0, math.rad(yaw), 0)
		local solved = Pose.solve(avatar.model, rootFrame, animator.mixer:lastOffsets(), chain)
		if t < 0.5 - 1e-9 then
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
						track.slideAt = t - 0.5
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
						track.driftAt = t - 0.5
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
describe("a turn in place plants its feet (323(d))", function()
	for _, case in { { -1, true }, { 1, true }, { -1, false }, { 1, false } } do
		local side, drawn = case[1] :: number, case[2] :: boolean
		it(
			("the lock turns the standing %s body to the %s: no planted foot slides or drifts"):format(
				if drawn then "drawn" else "sheathed",
				if side < 0 then "right" else "left"
			),
			function()
				local problems = {}
				for _, degrees in { 90, 135, 180 } do
					for _, hz in { 60, 240 } do
						local tracks = run(degrees, side, hz, Combat.aim.lockTurnRate, drawn)
						for _, name in FOOT do
							local track = tracks[name]
							if track.worstSlide > Audit.footSlideStuds + 1e-6 then
								table.insert(
									problems,
									("%d deg %d Hz %s slides %.2f in a 60 Hz frame while planted at +%.3f s (max %.2f)"):format(
										degrees,
										hz,
										name,
										track.worstSlide,
										track.slideAt,
										Audit.footSlideStuds
									)
								)
							end
							if track.worstDrift > Audit.footDriftStuds + 1e-6 then
								table.insert(
									problems,
									("%d deg %d Hz %s drifts %.2f over one plant at +%.3f s (max %.2f)"):format(
										degrees,
										hz,
										name,
										track.worstDrift,
										track.driftAt,
										Audit.footDriftStuds
									)
								)
							end
						end
					end
				end
				expect(table.concat(problems, "\n")).toBe("")
			end
		)
	end
end)
