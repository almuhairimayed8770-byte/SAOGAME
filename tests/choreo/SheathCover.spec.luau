--!strict
--[[
	A guard raised with the sword on the back while a clip above the sheath clips hides the right
	arm (a landing, a skid, a standing turn): the game's own path, as SheathTip.spec.luau runs it.
	Locomotion steps SheathState, the Draw plays over the Guard (sheath.drawFirstClips) through the
	Choreo animator, and WeaponMount moves the Weapon motor on the clip's own event, on the hit
	matrix's player (HitMatrix.standing).

	Under the cover the hand is not at the hilt, so the WeaponDraw that fires there is ignored. On
	7d112ef the Draw over the guard ran on to its end regardless; with the guard let go by then, the
	Draw's end put the sword in the hand wherever the arm was (7.41 studs from the back in one
	240 Hz frame). With the guard still held it played again and took the sword at the hilt (0.257).
	Now a Draw that has not taken the sword stops under the cover and plays over the guard from its
	start once the arm is free (D-504), so the sword only changes place at the hilt.

	Each case stands dev.luau groundClearance.sheathCover.settle seconds sheathed, presses the guard
	with the Drawn target (CharacterController's predicted draw), plays the cover clip `coverAt`
	seconds after the press, and either lets the guard go `releaseAt` seconds after it (over
	combat.luau locomotionBlendOut, as the controller's stopClip does) or holds it to the end. No
	step may move the tip faster than choreo.luau sheath.drawTipSpeed, and the sword ends in the hand.
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
local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local WeaponModels = Harness.load("src/shared/data/weaponModels")

local Sheath = ChoreoData.sheath
local Cover = Dev.groundClearance.sheathCover
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

type Result = { step: number, at: number, hand: boolean }

local function run(coverClip: string, coverAt: number, releaseAt: number?, speed: number): Result
	local avatar = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", false)
	local trailEnd = model:FindFirstChild("TrailEnd", true)
	local blade = trailEnd.Parent.Name
	local motor: any = nil
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and item.Name == WeaponModels.motorName then
			motor = item
		end
	end
	assert(motor ~= nil, "the hit matrix's player carries a Weapon motor")
	local primary = model.PrimaryPart
	local base = avatar.base
	primary.CFrame = base
	primary.Position = base.Position
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, { footIK = false })
	local dt = 1 / Cover.stepHz
	local travelled = Vector3.zero
	local guard: any = nil
	local covered, released = false, false
	local lastTip: any = nil
	local worst: Result = { step = 0, at = 0, hand = false }
	for frame = 1, math.floor((Cover.settle + Cover.seconds) * Cover.stepHz + 0.5) do
		clock += dt
		local after = frame * dt - Cover.settle
		if after > 0 and guard == nil then
			guard = animator:play(PREFIX .. "Guard", { handOver = true })
		end
		if after >= coverAt and not covered then
			covered = true
			animator:play(PREFIX .. coverClip, {})
		end
		if releaseAt ~= nil and after >= releaseAt and not released then
			released = true
			animator:stop(guard, Combat.locomotionBlendOut)
		end
		travelled += Vector3.new(0, 0, -speed * dt)
		local rootFrame = base * CFrame.new(travelled)
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = if speed > 0 then Vector3.new(0, 0, -1) else Vector3.zero,
			speed = speed,
			sprinting = false,
			grounded = true,
			-- The guard press predicts the draw (sheath.predictSeconds, longer than every case).
			drawn = after > 0,
			turning = 0,
			verticalVelocity = 0,
			velocity = Vector3.new(0, 0, -speed),
		})
		animator:step(dt)
		local solved = solveLive(model, rootFrame)
		local tip = rootFrame:PointToObjectSpace((solved[blade] * trailEnd.CFrame).Position)
		if lastTip ~= nil then
			local step = (tip - lastTip).Magnitude
			if step > worst.step then
				worst.step = step
				worst.at = after
			end
		end
		lastTip = tip
	end
	worst.hand = motor.Part0 ~= nil and motor.Part0.Name == "RightHand"
	locomotion:destroy()
	Choreo.release(model)
	return worst
end

describe("SheathCover", function()
	it("a guard raised sheathed under a cover takes the sword at the hilt, under sheath.drawTipSpeed", function()
		local limit = Sheath.drawTipSpeed / Cover.stepHz
		local cases, worstStep, worstLabel = 0, 0, ""
		for _, coverClip in Cover.clips do
			for _, coverAt in Cover.coverAt do
				for _, speed in Cover.speeds do
					for mode = 1, 2 do
						-- Let go, then held to the end.
						local releaseAt: number? = if mode == 1 then Cover.releaseAt else nil
						local result = run(coverClip, coverAt, releaseAt, speed)
						cases += 1
						local label = ("%s %.2f s after the press, speed %d, %s"):format(
							coverClip,
							coverAt,
							speed,
							if releaseAt ~= nil then ("released at %.2f s"):format(releaseAt) else "held"
						)
						if result.step > worstStep then
							worstStep = result.step
							worstLabel = ("%s: %.3f at +%.3f s"):format(label, result.step, result.at)
						end
						if result.step > limit then
							error(
								("%s: the tip moves %.3f studs in one %d Hz step at +%.3f s (sheath.drawTipSpeed allows %.3f): the sword changed place away from the hilt"):format(
									label,
									result.step,
									Cover.stepHz,
									result.at,
									limit
								)
							)
						end
						if not result.hand then
							error(("%s: the sword is not in the hand at the end"):format(label))
						end
					end
				end
			end
		end
		print(("SheathCover: %d cases, worst tip step %s (limit %.3f)"):format(cases, worstLabel, limit))
		expect(cases).toBe(#Cover.clips * #Cover.coverAt * #Cover.speeds * 2)
	end)
end)
