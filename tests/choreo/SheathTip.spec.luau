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

	A guard raised with the sword on the back (the guard cases) plays the Guard clip as
	CharacterController's guard press does, with the Drawn target: the Draw plays over the guard
	(sheath.drawFirstClips, overPriority) and hands the arm to it from sheath.handOverTime, under the
	same limits. Pressed with the flip, or a little after a lock-on's Draw has started under it.
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
local LocomotionState = Harness.load("src/client/choreo/LocomotionState")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Joints = Harness.load("src/shared/choreo/Joints")
local Pose = Harness.load("src/shared/choreo/Pose")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")
local WeaponModels = Harness.load("src/shared/data/weaponModels")

local Sheath = ChoreoData.sheath
local Tip = Dev.groundClearance.sheathTip
local PREFIX = ChoreoData.locomotion.clipPrefix
local GUARD_ID = PREFIX .. "Guard"

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
-- stepped that many times is sheathTip.hitch.seconds long instead. With `backAt`, the target turns
-- back on the first step that finds the clip's clock at or past it: a lock-on (or any combat
-- request) that wants the sword while the Sheathe still holds it, or a fight that ends while the
-- Draw has not taken it yet.
local function run(
	drawing: boolean,
	speed: number,
	hz: number,
	hitchAfter: number?,
	backAt: number?,
	lead: number?,
	guardAt: number?
): Worst
	-- `lead` more seconds in the start state put the flip at another point of the gait's cycle.
	local settle = Tip.settle + (lead or 0)
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
	local seconds = settle + wait + clip.duration + (clip.blendOut or ChoreoData.blendOut) + Tip.after
	if guardAt ~= nil then
		-- The Draw plays again over the guard when one had started under it.
		seconds += guardAt
	end
	if backAt ~= nil then
		-- Long enough for the clip the target turns back to as well (a Draw cut back with the sword
		-- in the hand sheathes it again).
		local other = ClipLibrary.get(PREFIX .. (if drawing then Sheath.clips.sheathe else Sheath.clips.draw))
		seconds += Sheath.sheatheDelay + Sheath.cutBackBlend + other.duration
	end
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
	local guarded = false
	local travelled = Vector3.zero
	local clipSteps = 0 -- steps the clip has been live for
	local wentBack = false -- the target turned true again mid-Sheathe (backAt)
	local extra = 0 -- the hitch's time past one frame, once it has landed
	for frame = 1, frames do
		local dt = frameDt
		if hitchAfter ~= nil and clipSteps == hitchAfter and extra == 0 then
			dt = Tip.hitch.seconds
			extra = dt - frameDt
		end
		local t = frame * frameDt + extra
		clock += dt
		local drawn = if t > settle then drawing else not drawing
		if backAt ~= nil then
			local live = animator.mixer:find(clipId)
			if wentBack or (live ~= nil and not live.stopping and live.time >= backAt - 1e-9) then
				wentBack = true
				drawn = not drawing
			end
		end
		model:SetAttribute("Drawn", drawn)
		if guardAt ~= nil and not guarded and t > settle and t - settle >= guardAt - 1e-9 then
			-- The guard press, on the flip's own step or later: the Guard clip plays before the
			-- frame's locomotion step, as CharacterController's guard press does.
			guarded = true
			animator:play(GUARD_ID)
		end
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
		if lastTip ~= nil and t > settle then
			local clipTime = if handle ~= nil then handle.time else nil
			local tipSpeed = (tip - lastTip).Magnitude / dt
			local turnRate = math.deg(math.acos(math.clamp(line:Dot(lastLine), -1, 1))) / dt
			if tipSpeed > worst.tip then
				worst.tip, worst.tipStep, worst.tipAt, worst.tipClip = tipSpeed, tipSpeed * dt, t - settle, clipTime
			end
			if turnRate > worst.turn then
				worst.turn, worst.turnStep, worst.turnAt, worst.turnClip = turnRate, turnRate * dt, t - settle, clipTime
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

-- The time a sheath clip moves the sword (Draw's WeaponDraw, Sheathe's WeaponSheathe): until then
-- the sword is where the clip found it.
local function swapTime(drawing: boolean): number
	local clip = ClipLibrary.get(PREFIX .. (if drawing then Sheath.clips.draw else Sheath.clips.sheathe))
	local kind = if drawing then "WeaponDraw" else "WeaponSheathe"
	for _, event in clip.events or {} do
		if event.kind == kind then
			return event.time
		end
	end
	error(("the %s clip has no %s event"):format(clip.id, kind))
end

-- Steps of the first step rate between the cut-back cases: the cut-back's pace is a smooth curve
-- over the clip's clock, so every third frame finds its worst.
local BACK_STRIDE = 3

-- Points of the gait's cycle the "phases" cases flip the target at, spread over the longest gait
-- clip's cycle (at least one whole cycle of every gait at every speed): a moving base's torso
-- adds its own swing to the arm's, most where the two line up.
local PHASES = 48
-- When the guard is pressed in the guard cases, in seconds after the Drawn target flips: with it
-- (the press itself predicts drawn), and while a lock-on's Draw plays under it before and after
-- its WeaponDraw (0.22 s).
local GUARD_AFTER = { 0, 0.1, 0.2, 0.3, 0.5, 0.7 }

local function longestCycle(): number
	local longest = 0
	for _, gait in LocomotionState.gaits() do
		longest = math.max(longest, gait.duration)
	end
	return longest
end

-- Every case of one clip: each speed at each step rate, then (`mode` "hitches") each speed at the
-- hitch's frame rate with the long frame after each of the clip's first `steps` steps, or (`mode`
-- "phases") each moving speed at each step rate with the flip at PHASES points of the gait's cycle,
-- held to the cap times sheath.movingTipShare (the margin Studio's reading needs over this one), or
-- (`mode` "back") each speed at the first step rate with the target turning back at every BACK_STRIDE-th
-- frame of the clip's clock while the sword is in the hand: a Sheathe before its WeaponSheathe (the
-- lock-on mid-Sheathe), a Draw after its WeaponDraw (the fight over mid-Draw). Nothing else moves
-- the arm then, so the drawn pose comes back under the Draw's limits, or the sword goes back to
-- the sheath under the Sheathe's. (A Draw cut back before its WeaponDraw leaves the blade on the
-- back; a Sheathe cut back after its WeaponSheathe plays the Draw at once.)
local function check(drawing: boolean, mode: ("hitches" | "back" | "phases" | "guard")?): ()
	local name = (if drawing then "Draw" else "Sheathe")
		.. (
			if mode == "back"
				then " cut back"
				elseif mode == "phases" then " over the gait's cycle"
				elseif mode == "guard" then " under a guard raised sheathed"
				else ""
		)
	local tipLimit = if drawing ~= (mode == "back") then Sheath.drawTipSpeed else Sheath.sheatheTipSpeed
	if mode == "phases" then
		tipLimit *= Sheath.movingTipShare
	end
	local problems: { string } = {}
	local fastest, sharpest = 0, 0
	local cases = 0
	local runs: { { speed: number, hz: number, hitchAfter: number?, backAt: number?, lead: number?, guardAt: number? } } =
		{}
	local expected = 0
	for _, speed in Tip.speeds do
		if mode == "phases" then
			if speed > 0 then
				local span = longestCycle()
				for _, hz in Tip.stepHz do
					for point = 0, PHASES - 1 do
						table.insert(runs, { speed = speed, hz = hz, lead = point * span / PHASES })
						expected += 1
					end
				end
			end
		elseif mode == "guard" then
			for _, hz in Tip.stepHz do
				for _, guardAt in GUARD_AFTER do
					table.insert(runs, { speed = speed, hz = hz, guardAt = guardAt })
					expected += 1
				end
			end
		elseif mode == "hitches" then
			for after = 1, Tip.hitch.steps do
				table.insert(runs, { speed = speed, hz = Tip.hitch.hz, hitchAfter = after })
			end
		elseif mode == "back" then
			local hz = Tip.stepHz[1]
			local swap = math.floor(swapTime(drawing) * hz)
			local clip = ClipLibrary.get(PREFIX .. (if drawing then Sheath.clips.draw else Sheath.clips.sheathe))
			local first = if drawing then swap + 1 else 1
			local last = if drawing then math.ceil(clip.duration * hz) - 1 else swap
			for frame = first, last, BACK_STRIDE do
				table.insert(runs, { speed = speed, hz = hz, backAt = frame / hz })
				expected += 1
			end
		else
			for _, hz in Tip.stepHz do
				table.insert(runs, { speed = speed, hz = hz })
			end
		end
	end
	for _, each in runs do
		local speed, hz = each.speed, each.hz
		local worst = run(drawing, speed, hz, each.hitchAfter, each.backAt, each.lead, each.guardAt)
		cases += 1
		-- The sword must actually change place, or the case measured nothing of the swap; a Sheathe
		-- cut back keeps it in the hand.
		expect(worst.swapped).toBe(drawing or mode ~= "back")
		fastest = math.max(fastest, worst.tip)
		sharpest = math.max(sharpest, worst.turn)
		local case = ("%s at %g studs/s, %g Hz"):format(name, speed, hz)
		if each.hitchAfter ~= nil then
			case ..= (", a %g s frame after clip step %d"):format(Tip.hitch.seconds, each.hitchAfter)
		end
		if each.backAt ~= nil then
			case ..= (", the target back at clip %.3f s"):format(each.backAt)
		end
		if each.lead ~= nil then
			case ..= (", flipped %.3f s into the cycle"):format(each.lead)
		end
		if each.guardAt ~= nil then
			case ..= (", the guard %.3f s after the flip"):format(each.guardAt)
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
	if mode == "back" or mode == "phases" or mode == "guard" then
		expect(cases).toBe(expected)
		expect(cases).toBeGreaterThan(#Tip.speeds)
	else
		expect(cases).toBe(#Tip.speeds * (if mode == "hitches" then Tip.hitch.steps else #Tip.stepHz))
	end
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

	it("Draw over a walk, a run and a sprint, at every point of their cycle: the tip under the moving cap", function()
		check(true, "phases")
	end)

	it("Draw: a hitch early in the clip moves the tip no faster on the frames after it", function()
		check(true, "hitches")
	end)

	it("Sheathe: a hitch early in the clip moves the tip no faster on the frames after it", function()
		check(false, "hitches")
	end)

	it("Sheathe cut back with the sword still in the hand: back to drawn under the Draw's limits", function()
		check(false, "back")
	end)

	it("Draw cut back with the sword in the hand: sheathed again under the Sheathe's limits", function()
		check(true, "back")
	end)

	it("Guard raised sheathed: the Draw plays over it and hands over under the Draw's limits", function()
		check(true, "guard")
	end)
end)
