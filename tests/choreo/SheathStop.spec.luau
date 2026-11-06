--!strict
--[[
	A stop with no Skid while a Draw or Sheathe plays (D-611; Studio item 512): the sprint and
	the run eased off (a gamepad stick let back, slower than the Skid's drop, so LocomotionState
	plays no Skid) and the run let go into the two-step stop (ActionLogic's carry, as
	CharacterController runs it with Locomotion.stopGait). The game's own path, as
	SheathSkid.spec.luau runs it: Locomotion steps SheathState, the Choreo animator and its mixer
	blend the base under the clip, and WeaponMount moves the Weapon motor on the clip's event, on
	the hit matrix's player (HitMatrix.standing).

	On 81b8fef the stop's blend from the run or sprint to the idle straightened the torso under the
	Sheathe's raised arm while the clip swung it on: the tip read up to 94.5 studs a second (the
	run eased off over 0.25 s at 240 Hz), 92.9 from the sprint eased off over 0.1 s and 87.5 from
	the run let go at 16, against the 84 cap, and the blade turned up to 1188 degrees a second
	against 1080 (the steady sprint under the same clip at most 76.8). Now while the base's gait
	falls faster than choreo.luau sheath.stopBrakeRate steps a second (sheath.stopBrakeClips), the
	sheath clip's clock stands, as D-579 does under a Skid's brake.

	Each case runs dev.luau groundClearance.sheathStop.settle seconds moving in the start state,
	flips the Drawn target, lets the stick go `stopAfter` seconds after the flip and runs `seconds`
	more. The tip is read in the root part's space (the camera follows the root), as SheathSkid
	reads it. No step may move the tip faster than sheath.sheatheTipSpeed (the Sheathe) or
	drawTipSpeed (the Draw), or turn the blade faster than sheath.bladeTurnRate; no Skid may play,
	and the sword must end where the target wants it.
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
local Joints = Harness.load("src/shared/choreo/Joints")
local Pose = Harness.load("src/shared/choreo/Pose")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")
local WeaponModels = Harness.load("src/shared/data/weaponModels")

local Sheath = ChoreoData.sheath
local Config = ChoreoData.locomotion
local Cases = Dev.groundClearance.sheathStop
local SKID = Config.clipPrefix .. Config.clips.Skid
-- CharacterController's carry configuration.
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

local function solveLive(model: any, rootFrame: any): { [string]: any }
	local chain = Pose.chain(model)
	local joints = Joints.map(model)
	local solved: { [string]: any } = { [chain.rootName] = rootFrame }
	for _, link in chain.links do
		local joint: any = joints[link.name]
		solved[link.part1] = solved[link.part0] * link.c0 * joint.Transform * link.c1Inverse
	end
	return solved
end

type Result = {
	tip: number, -- studs a second
	tipAt: number, -- seconds after the stick let go
	turn: number, -- degrees a second
	turnAt: number,
	skid: boolean, -- a Skid showed
	place: string?, -- the Weapon motor's Part0 at the end
}

-- A stop from `start` studs a second: the root eased off over `ease` seconds, or (ease nil) the
-- run let go into the carry.
local function run(drawing: boolean, start: number, ease: number?, stopAfter: number, hz: number): Result
	local avatar = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", not drawing)
	local trailStart = model:FindFirstChild("TrailStart", true)
	local trailEnd = model:FindFirstChild("TrailEnd", true)
	assert(trailStart ~= nil and trailEnd ~= nil, "the matrix's sword has no TrailStart / TrailEnd")
	local blade = trailEnd.Parent.Name
	local motor: any = nil
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and item.Name == WeaponModels.motorName then
			motor = item
		end
	end
	assert(motor ~= nil, "the matrix's sword has no Weapon motor")
	local primary = model.PrimaryPart
	local base = avatar.base
	primary.CFrame = base
	primary.Position = base.Position
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, { footIK = false })
	local dt = 1 / hz
	local flipAt = Cases.settle
	local stopAt = flipAt + stopAfter
	local seconds = math.max(flipAt, stopAt) + Cases.seconds
	local result: Result = { tip = 0, tipAt = 0, turn = 0, turnAt = 0, skid = false, place = nil }
	local carry: any =
		{ active = false, moving = false, x = 0, z = -1, from = 0, elapsed = 0, phase = 0, total = 0, left = 0 }
	local gait: any = { phase = 0, leftStep = 0, leftAfter = 0, rightStep = 0.5, rightAfter = 0 }
	local travelled = Vector3.zero
	local lastTip: any, lastLine: any = nil, nil
	local speed = start
	local t = 0
	for _ = 1, math.floor(seconds * hz + 0.5) do
		clock += dt
		t += dt
		local flipped = t > flipAt + 1e-9
		local held = t <= stopAt + 1e-9
		if ease ~= nil then
			if not held then
				speed = math.max(0, speed - start * dt / ease)
			end
		else
			-- CharacterController: the stop's gait read once the stick is let go, the carry's
			-- speed while it runs, the run's while the stick is held.
			if not held then
				locomotion:stopGait(gait)
			end
			local carried = ActionLogic.stopCarryStep(
				carry,
				0,
				if held then -1 else 0,
				speed,
				Cases.run,
				true,
				"Idle",
				dt,
				STOP_CARRY,
				if held then nil else gait
			)
			speed = if held then Cases.run else carried
		end
		travelled += Vector3.new(0, 0, -speed * dt)
		local rootFrame = base * CFrame.new(travelled)
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = if held then Vector3.new(0, 0, -1) else Vector3.zero,
			speed = speed,
			sprinting = held and start > Config.skidSpeedThreshold,
			grounded = true,
			drawn = if flipped then drawing else not drawing,
			turning = 0,
			verticalVelocity = 0,
			velocity = Vector3.new(0, 0, -speed),
		})
		animator:step(dt)
		local skid = animator.mixer:find(SKID)
		if skid ~= nil and skid.weight > 0 and skid.fade > 0 then
			result.skid = true
		end
		local solved = solveLive(model, rootFrame)
		local tip = rootFrame:PointToObjectSpace((solved[blade] * trailEnd.CFrame).Position)
		local guard = rootFrame:PointToObjectSpace((solved[blade] * trailStart.CFrame).Position)
		local line = (tip - guard).Unit
		if lastTip ~= nil and flipped then
			local tipSpeed = (tip - lastTip).Magnitude / dt
			local turnRate = math.deg(math.acos(math.clamp(line:Dot(lastLine), -1, 1))) / dt
			if tipSpeed > result.tip then
				result.tip, result.tipAt = tipSpeed, t - stopAt
			end
			if turnRate > result.turn then
				result.turn, result.turnAt = turnRate, t - stopAt
			end
		end
		lastTip, lastLine = tip, line
	end
	result.place = if motor.Part0 ~= nil then motor.Part0.Name else nil
	locomotion:destroy()
	Choreo.release(model)
	return result
end

local function check(drawing: boolean)
	local name = if drawing then "Draw" else "Sheathe"
	local tipLimit = if drawing then Sheath.drawTipSpeed else Sheath.sheatheTipSpeed
	local problems: { string } = {}
	local fastest, fastestCase, sharpest = 0, "", 0
	local cases = 0
	-- Each stop: its start speed and its ease (false: the run let go into the carry).
	local stops: { { start: number, ease: number | false } } = { { start = Cases.run, ease = false } }
	for _, start in { Cases.sprint, Cases.run } do
		for _, ease in Cases.eases do
			table.insert(stops, { start = start, ease = ease })
		end
	end
	for _, hz in Cases.stepHz do
		for _, stop in stops do
			local ease: number? = if stop.ease == false then nil else stop.ease :: number
			for _, stopAfter in Cases.stopAfter do
				local result = run(drawing, stop.start, ease, stopAfter, hz)
				cases += 1
				local how = if ease ~= nil
					then ("the %s at %g eased off over %g s"):format(
						if stop.start > Config.skidSpeedThreshold then "sprint" else "run",
						stop.start,
						ease
					)
					else ("the run at %g let go into the two-step stop"):format(Cases.run)
				local case = ("%s, %g Hz, %s %+.2f s after the flip"):format(name, hz, how, stopAfter)
				if result.tip > fastest then
					fastest, fastestCase = result.tip, ("%s (%+.3f s after the let-go)"):format(case, result.tipAt)
				end
				sharpest = math.max(sharpest, result.turn)
				if result.skid then
					table.insert(problems, ("%s: a Skid played"):format(case))
				end
				if result.tip > tipLimit then
					table.insert(
						problems,
						("%s: the tip moves %.1f studs/s %+.3f s after the let-go (limit %g)"):format(
							case,
							result.tip,
							result.tipAt,
							tipLimit
						)
					)
				end
				if result.turn > Sheath.bladeTurnRate then
					table.insert(
						problems,
						("%s: the blade turns %.0f degrees/s %+.3f s after the let-go (limit %g)"):format(
							case,
							result.turn,
							result.turnAt,
							Sheath.bladeTurnRate
						)
					)
				end
				if (result.place == "RightHand") ~= drawing then
					table.insert(
						problems,
						("%s: the sword ends on %s, not %s"):format(
							case,
							tostring(result.place),
							if drawing then "the hand" else "the back"
						)
					)
				end
			end
		end
	end
	expect(cases).toBe(#Cases.stepHz * (2 * #Cases.eases + 1) * #Cases.stopAfter)
	print(
		("  %s at a stop with no Skid: %d cases, the tip at most %.1f studs/s (%s), the blade at most %.0f degrees/s"):format(
			name,
			cases,
			fastest,
			fastestCase,
			sharpest
		)
	)
	if #problems > 0 then
		error(("%d %s case(s) fail:\n%s"):format(#problems, name, table.concat(problems, "\n")))
	end
end

describe("Draw and Sheathe at a stop with no Skid (D-611)", function()
	it("Sheathe: the tip under sheath.sheatheTipSpeed, the blade under bladeTurnRate, the sword on the back", function()
		check(false)
	end)
	it("Draw: the tip under sheath.drawTipSpeed, the blade under bladeTurnRate, the sword in the hand", function()
		check(true)
	end)
end)
