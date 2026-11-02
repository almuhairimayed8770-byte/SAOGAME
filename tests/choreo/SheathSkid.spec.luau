--!strict
--[[
	A sprint let go into the Skid while a Draw or Sheathe plays (D-579): the game's own path, as
	SheathTip.spec.luau runs it. Locomotion steps SheathState and plays the Skid from
	LocomotionState's stop, the Choreo animator and its mixer blend them, and WeaponMount moves the
	Weapon motor on the clip's own event, on the hit matrix's player (HitMatrix.standing).

	The owner's PC on 209875b, beside item 475: in a sprint take the sword's Sheathe played at the
	Skid stop; its rows reached 241 studs a second with the sword still in the hand, the tip jumping
	from beside the chest to the hip in two frames. On the base the Skid (FullBody, above the
	Sheathe's UpperBody) took the arm over its 0.1 s blend in: the arm crossed from the Sheathe's
	swing to the Skid's flung-back arm (up to 423 studs a second at 240 Hz). And a Sheathe that
	started under the Skid's fade-out took the arm from the Skid's last pose (85 at 240 Hz).

	Now a Skid that starts while a Draw or Sheathe is under way leaves that clip the arm and the
	sword's joint, and the clip's clock stands for the Skid's brake (choreo.luau
	sheath.skidBrakeSeconds); a Skid that started first still covers the arm until it has faded out.

	Each case runs dev.luau groundClearance.sheathSkid.settle seconds at the sprint in the start
	state, flips the Drawn target (the combat tag running out, or a draw), lets the stick go
	`stopAfter` seconds after the flip with the root stopping evenly over each of `stopSeconds`
	(0: at once; the owner's PC on c78acd1 stopped in about 0.03 s, and at 240 fps played the Skid
	on 3 of 10 takes, D-612), and runs `seconds` more. The
	tip is read in the root part's space (the camera follows the root): the chain the screen shows a
	row later with the sword's place (D-555), whose step over its own frame time is the screen speed
	D-545 reads. No step may move the tip faster than sheath.sheatheTipSpeed (the Sheathe) or
	drawTipSpeed (the Draw), or turn the blade faster than sheath.bladeTurnRate; the Skid must play,
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
local Joints = Harness.load("src/shared/choreo/Joints")
local Pose = Harness.load("src/shared/choreo/Pose")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")
local WeaponModels = Harness.load("src/shared/data/weaponModels")

local Sheath = ChoreoData.sheath
local Cases = Dev.groundClearance.sheathSkid
local PREFIX = ChoreoData.locomotion.clipPrefix
local SKID = PREFIX .. ChoreoData.locomotion.clips.Skid

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
	tipAt: number, -- seconds after the flip
	turn: number, -- degrees a second
	turnAt: number,
	skid: boolean, -- a Skid showed
	place: string?, -- the Weapon motor's Part0 at the end
}

local function run(drawing: boolean, stopAfter: number, hz: number, stopSeconds: number): Result
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
	local travelled = Vector3.zero
	local lastTip: any, lastLine: any = nil, nil
	local t = 0
	for _ = 1, math.floor(seconds * hz + 0.5) do
		clock += dt
		t += dt
		local flipped = t > flipAt + 1e-9
		local running = t <= stopAt + 1e-9
		local speed = Cases.speed
		if not running then
			speed = if stopSeconds <= 0 then 0 else math.max(0, Cases.speed * (1 - (t - stopAt) / stopSeconds))
		end
		travelled += Vector3.new(0, 0, -speed * dt)
		local rootFrame = base * CFrame.new(travelled)
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = if running then Vector3.new(0, 0, -1) else Vector3.zero,
			speed = speed,
			sprinting = running,
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
				result.tip, result.tipAt = tipSpeed, t - flipAt
			end
			if turnRate > result.turn then
				result.turn, result.turnAt = turnRate, t - flipAt
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
	local wanted = if drawing then "RightHand" else nil
	local problems: { string } = {}
	local fastest, fastestCase, sharpest = 0, "", 0
	local cases = 0
	for _, hz in Cases.stepHz do
		for _, stopSeconds in Cases.stopSeconds do
			for _, stopAfter in Cases.stopAfter do
				local result = run(drawing, stopAfter, hz, stopSeconds)
				cases += 1
				local case = ("%s, %g Hz, the stick let go %+.2f s after the flip, stopping over %g s"):format(
					name,
					hz,
					stopAfter,
					stopSeconds
				)
				if result.tip > fastest then
					fastest, fastestCase = result.tip, case
				end
				sharpest = math.max(sharpest, result.turn)
				if not result.skid then
					table.insert(problems, ("%s: no Skid played"):format(case))
				end
				if result.tip > tipLimit then
					table.insert(
						problems,
						("%s: the tip moves %.1f studs/s at +%.3f s (limit %g)"):format(
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
						("%s: the blade turns %.0f degrees/s at +%.3f s (limit %g)"):format(
							case,
							result.turn,
							result.turnAt,
							Sheath.bladeTurnRate
						)
					)
				end
				local onBack = result.place ~= "RightHand"
				if (wanted == "RightHand") == onBack then
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
	expect(cases).toBe(#Cases.stepHz * #Cases.stopSeconds * #Cases.stopAfter)
	print(
		("  %s at a Skid: %d cases, the tip at most %.1f studs/s (%s), the blade at most %.0f degrees/s"):format(
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

describe("Draw and Sheathe at a sprint's Skid stop (D-579)", function()
	it("Sheathe: the tip under sheath.sheatheTipSpeed, the blade under bladeTurnRate, the sword on the back", function()
		check(false)
	end)
	it("Draw: the tip under sheath.drawTipSpeed, the blade under bladeTurnRate, the sword in the hand", function()
		check(true)
	end)
end)
