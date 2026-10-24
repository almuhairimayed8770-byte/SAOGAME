--!strict
--[[
	Draw and Sheathe as the client plays them: the blade's tip and line through the game's own path.
	Locomotion steps SheathState (Draw or Sheathe from the Drawn target), plays the clip at
	priority.Sheath over the locomotion set through the Choreo animator and its mixer (the blend in,
	the base set switch, the end of the clip into the next pose), and WeaponMount swaps the Weapon
	motor between the hand and the back on the clip's own event. All of it runs on the hit
	matrix's player (HitMatrix.standing, the body GroundClearance poses), and after every step the
	blade's tip and guard end are solved from the joint instances as Choreo left them: each joint's
	Transform, and the Weapon motor's Part0 and C0 as WeaponMount set them. Breathe plays, as in
	the game.

	The motion is taken in the root part's space: the camera follows the root, so that is what
	moves on screen. Each case stands dev.luau groundClearance.sheathTip.settle seconds in its
	start state, flips the target, and runs until the clip has blended out and `after` seconds
	more, at each of `speeds` and stepped at each of `stepHz` (a 60 fps frame and the 240 Hz
	review). No step may move the tip faster than choreo.luau sheath.drawTipSpeed (the Draw) or
	sheatheTipSpeed (the Sheathe), or turn the blade's line faster than sheath.bladeTurnRate.

	GroundClearance's own tip check poses each clip alone over a still base (no envelope, no
	Breathe, no set switch); this one shows whatever the game shows between those poses too.

	A long frame (sheathTip.hitch: a hitch of `seconds` among `hz` frames) lands once the clip has
	stepped 1 to `steps` times: the envelope takes the whole hitch in one step, and the drawn sprint
	pose must give way in that same step, not over the normal frames after it.
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
	-- Choreo's rig step (bound before every reader of a pose, D-211): the spec steps the rig itself.
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
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Joints = Harness.load("src/shared/choreo/Joints")
local Pose = Harness.load("src/shared/choreo/Pose")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")
local WeaponModels = Harness.load("src/shared/data/weaponModels")

local Sheath = ChoreoData.sheath
local Tip = Dev.groundClearance.sheathTip
local PREFIX = ChoreoData.locomotion.clipPrefix

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

-- Every part's CFrame from the joint instances as they stand: the chain is read again each time,
-- so the Weapon motor hangs from whichever part (and at whichever C0) WeaponMount left it on.
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

-- The fastest a case moved the blade, and where.
type Worst = {
	tip: number, -- studs a second
	tipStep: number, -- studs in that step
	tipAt: number, -- seconds after the flip
	tipClip: number?, -- the clip's own time then, nil once it is gone
	turn: number, -- degrees a second
	turnStep: number, -- degrees in that step
	turnAt: number,
	turnClip: number?,
	swapped: boolean, -- the sword changed place during the case
}

-- One case: the Drawn target flips to `drawing` after the settle, the root moving straight ahead at
-- `speed` the whole time, stepped `hz` times a second. With `hitchAfter`, the step after the clip has
-- stepped that many times is sheathTip.hitch.seconds long instead.
local function run(drawing: boolean, speed: number, hz: number, hitchAfter: number?): Worst
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
	local clipId = PREFIX .. (if drawing then Sheath.clips.draw else Sheath.clips.sheathe)
	local clip = ClipLibrary.get(clipId)
	local wait = if drawing then 0 else Sheath.sheatheDelay
	local seconds = Tip.settle + wait + clip.duration + (clip.blendOut or ChoreoData.blendOut) + Tip.after
	local frameDt = 1 / hz
	local frames = math.floor(seconds * hz + 0.5)
	local startPart = motor.Part0
	local worst: Worst = {
		tip = 0,
		tipStep = 0,
		tipAt = 0,
		tipClip = nil,
		turn = 0,
		turnStep = 0,
		turnAt = 0,
		turnClip = nil,
		swapped = false,
	}
	local lastTip: any, lastLine: any = nil, nil
	local travelled = Vector3.zero
	local clipSteps = 0 -- steps the clip has been live for
	local extra = 0 -- the hitch's time past one frame, once it has landed
	for frame = 1, frames do
		local dt = frameDt
		if hitchAfter ~= nil and clipSteps == hitchAfter and extra == 0 then
			dt = Tip.hitch.seconds
			extra = dt - frameDt
		end
		local t = frame * frameDt + extra
		clock += dt
		local drawn = if t > Tip.settle then drawing else not drawing
		model:SetAttribute("Drawn", drawn)
		travelled += Vector3.new(0, 0, -speed * dt)
		local rootFrame = base * CFrame.new(travelled)
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = if speed > 0 then Vector3.new(0, 0, -1) else Vector3.zero,
			speed = speed,
			sprinting = speed > ChoreoData.locomotion.runSpeed,
			grounded = true,
			drawn = drawn,
			turning = 0,
			verticalVelocity = 0,
			velocity = Vector3.new(0, 0, -speed),
		})
		animator:step(dt)
		local solved = solveLive(model, rootFrame)
		local tip = rootFrame:PointToObjectSpace((solved[blade] * trailEnd.CFrame).Position)
		local guard = rootFrame:PointToObjectSpace((solved[blade] * trailStart.CFrame).Position)
		local line = (tip - guard).Unit
		if motor.Part0 ~= startPart then
			worst.swapped = true
		end
		local handle = animator.mixer:find(clipId)
		if handle ~= nil and not handle.done then
			clipSteps += 1
		end
		if lastTip ~= nil and t > Tip.settle then
			local clipTime = if handle ~= nil then handle.time else nil
			local tipSpeed = (tip - lastTip).Magnitude / dt
			local turnRate = math.deg(math.acos(math.clamp(line:Dot(lastLine), -1, 1))) / dt
			if tipSpeed > worst.tip then
				worst.tip, worst.tipStep, worst.tipAt, worst.tipClip = tipSpeed, tipSpeed * dt, t - Tip.settle, clipTime
			end
			if turnRate > worst.turn then
				worst.turn, worst.turnStep, worst.turnAt, worst.turnClip =
					turnRate, turnRate * dt, t - Tip.settle, clipTime
			end
		end
		lastTip, lastLine = tip, line
	end
	locomotion:destroy()
	Choreo.release(model)
	return worst
end

local function clipAt(clipTime: number?): string
	return if clipTime ~= nil then ("clip %.3f s"):format(clipTime) else "no clip live"
end

-- Every case of one clip: each speed at each step rate, then (`hitches`) each speed at the hitch's
-- frame rate with the long frame after each of the clip's first `steps` steps.
local function check(drawing: boolean, hitches: boolean?): ()
	local name = if drawing then "Draw" else "Sheathe"
	local tipLimit = if drawing then Sheath.drawTipSpeed else Sheath.sheatheTipSpeed
	local problems: { string } = {}
	local fastest, sharpest = 0, 0
	local cases = 0
	local runs: { { speed: number, hz: number, hitchAfter: number? } } = {}
	for _, speed in Tip.speeds do
		if hitches then
			for after = 1, Tip.hitch.steps do
				table.insert(runs, { speed = speed, hz = Tip.hitch.hz, hitchAfter = after })
			end
		else
			for _, hz in Tip.stepHz do
				table.insert(runs, { speed = speed, hz = hz })
			end
		end
	end
	for _, each in runs do
		local speed, hz = each.speed, each.hz
		local worst = run(drawing, speed, hz, each.hitchAfter)
		cases += 1
		-- The sword must actually change place, or the case measured nothing of the swap.
		expect(worst.swapped).toBe(true)
		fastest = math.max(fastest, worst.tip)
		sharpest = math.max(sharpest, worst.turn)
		local case = ("%s at %g studs/s, %g Hz"):format(name, speed, hz)
		if each.hitchAfter ~= nil then
			case ..= (", a %g s frame after clip step %d"):format(Tip.hitch.seconds, each.hitchAfter)
		end
		if worst.tip > tipLimit then
			table.insert(
				problems,
				("%s: the tip moves %.1f studs/s (%.2f studs in that step) at +%.3f s, %s (limit %g)"):format(
					case,
					worst.tip,
					worst.tip / hz,
					worst.tipAt,
					clipAt(worst.tipClip),
					tipLimit
				)
			)
		end
		if worst.turn > Sheath.bladeTurnRate then
			table.insert(
				problems,
				("%s: the blade turns %.0f degrees/s (%.1f degrees in that step) at +%.3f s, %s (limit %g)"):format(
					case,
					worst.turn,
					worst.turn / hz,
					worst.turnAt,
					clipAt(worst.turnClip),
					Sheath.bladeTurnRate
				)
			)
		end
	end
	expect(cases).toBe(#Tip.speeds * (if hitches then Tip.hitch.steps else #Tip.stepHz))
	expect(fastest).toBeGreaterThan(0)
	print(
		("  %s: %d cases, the tip at most %.1f studs/s, the blade turning at most %.0f degrees/s"):format(
			name,
			cases,
			fastest,
			sharpest
		)
	)
	if #problems > 0 then
		error(("%d %s case(s) jump:\n%s"):format(#problems, name, table.concat(problems, "\n")))
	end
end

describe("Draw and Sheathe move the blade as a whip on the client's own path", function()
	it("Draw: the tip under sheath.drawTipSpeed and the blade under sheath.bladeTurnRate", function()
		check(true)
	end)

	it("Sheathe: the tip under sheath.sheatheTipSpeed and the blade under sheath.bladeTurnRate", function()
		check(false)
	end)

	it("Draw: a hitch early in the clip moves the tip no faster on the frames after it", function()
		check(true, true)
	end)

	it("Sheathe: a hitch early in the clip moves the tip no faster on the frames after it", function()
		check(false, true)
	end)
end)
