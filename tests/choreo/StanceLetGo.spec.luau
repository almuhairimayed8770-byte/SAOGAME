--!strict
--[[
	A stance the server takes away before the Art's first cut (D-340): a hit, a guard break or
	death lets the Art go with combat.luau struckStanceBlendOut (CharacterController's clearHold and
	takeArtAway on the server's Stagger, GuardBroken, Break and Dead; tests/client/
	CharacterController.spec.luau pins that wiring). Played on the game's own path: the Choreo
	animator and its mixer with Locomotion on the hit matrix's player (the Art on FullBody over the
	drawn idle), the rig stepped at 60, 144 and 240 Hz, the blade's tip read in the root part's space
	the camera follows.

	Every in-scope Art, let go in each place a hit can find it: frozen in its glowing hold
	(freezeHold at the ActivationHold), frozen short of it in the wind-up (a shown blow waits for its
	word unlit, D-326), and launched, its clock running in the anticipation before its first cut
	(Locomotion stands it where it was let go, D-294). From the let-go on, the tip never moves faster
	than combat.luau struckStanceTipSpeed: the sword comes down, it does not cut. Over
	locomotionBlendOut a raised stance came down past the front of the body at up to 93 (Sharp Nail)
	and 130 (Vertical) studs a second, the shape of a cut with no trail on it.

	No flinch plays here: the hit's own recoil (the flinch, D-258) is the blow's, and this is about
	what the fade adds. The fade is gone inside the stagger, so the fighter's next action never plays
	under it (tools/validators/combat.luau).
]]

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
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
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Joints = Harness.load("src/shared/choreo/Joints")
local Pose = Harness.load("src/shared/choreo/Pose")
local Combat = Harness.load("src/shared/data/combat")
local Arts = Harness.load("src/shared/data/arts")
local Scope = Harness.load("src/shared/data/scope")

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

local RATES = { 60, 144, 240 }
-- How long the case keeps stepping after the let-go: the whole fade, and a little of the idle.
local AFTER = 0.15

-- Every part's CFrame from the joint instances as they stand (as tests/choreo/SheathTip.spec).
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

-- The clip time of a clip's first event of `kind`.
local function eventTime(clip: any, kind: string): number
	for _, event in clip.events or {} do
		if event.kind == kind then
			return event.time
		end
	end
	error(("%s has no %s event"):format(clip.id, kind))
end

-- The clip's first damage frame: its first HitWindowOpen, TrailOn or SmearOn (Locomotion's rule).
local function firstStrike(clip: any): number
	local first = math.huge
	for _, event in clip.events or {} do
		if event.kind == "HitWindowOpen" or event.kind == "TrailOn" or event.kind == "SmearOn" then
			first = math.min(first, event.time)
		end
	end
	return first
end

type Case = {
	clipId: string,
	hz: number,
	-- "hold": frozen at its ActivationHold (freezeHold) for `seconds`; "windUp": frozen where it
	-- stands `seconds` into the clip (D-326); "launched": its clock running, let go `seconds`
	-- before its first damage frame.
	at: string,
	seconds: number,
}

type Worst = {
	speed: number, -- studs a second
	at: number, -- seconds after the let-go
	gone: boolean, -- the Art had faded out by the end
	clockMoved: boolean, -- the Art's clock ran on after the let-go
}

local function run(case: Case): Worst
	local avatar = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", true)
	model:SetAttribute("State", "Idle")
	local trailEnd = model:FindFirstChild("TrailEnd", true)
	assert(trailEnd ~= nil, "the matrix's sword has no TrailEnd")
	local blade = trailEnd.Parent.Name
	local primary = model.PrimaryPart
	local base = avatar.base
	primary.CFrame = base
	primary.Position = base.Position
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, { footIK = false })
	local clip = ClipLibrary.get(case.clipId)
	local dt = 1 / case.hz
	local art: any = nil
	local holding = false
	local frozen = false
	local connection = animator.events:Connect(function(clipId: string, event: any)
		-- CharacterController's clipEvent listener: freezeHold.
		if clipId == case.clipId and event.kind == "ActivationHold" and holding and not frozen then
			frozen = true
			animator:setTimeScale(0)
		end
	end)
	local function frame()
		clock += dt
		locomotion:update(dt, {
			moveDir = Vector3.zero,
			speed = 0,
			sprinting = false,
			grounded = true,
			drawn = true,
			turning = 0,
			verticalVelocity = 0,
			velocity = Vector3.zero,
		})
		animator:step(dt)
	end
	local function tip(): any
		local solved = solveLive(model, base)
		return base:PointToObjectSpace((solved[blade] * trailEnd.CFrame).Position)
	end
	for _ = 1, case.hz do
		frame()
	end
	art = animator:play(case.clipId)
	holding = case.at == "hold"
	-- Step to the let-go.
	local frozenFor = 0
	local guard = 0
	while true do
		guard += 1
		assert(guard < 10 * case.hz, ("%s never reached its let-go"):format(case.clipId))
		if case.at == "hold" then
			if frozen then
				frozenFor += dt
				if frozenFor >= case.seconds - 1e-9 then
					break
				end
			end
		elseif case.at == "windUp" then
			if art.time >= case.seconds - 1e-9 then
				-- waitUnlit: the stance freezes where it stands.
				animator:setTimeScale(0)
				frozenFor += dt
				if frozenFor >= 0.1 - 1e-9 then
					break
				end
			end
		elseif art.time >= firstStrike(clip) - case.seconds - 1e-9 then
			break
		end
		frame()
	end
	-- The server's word: clearHold / takeArtAway.
	holding = false
	animator:setTimeScale(1)
	local letGoAt = art.time
	animator:stop(art, Combat.struckStanceBlendOut)
	local worst: Worst = { speed = 0, at = 0, gone = false, clockMoved = false }
	local last = tip()
	local since = 0
	local steps = math.ceil((Combat.struckStanceBlendOut + AFTER) * case.hz)
	for _ = 1, steps do
		frame()
		since += dt
		local now = tip()
		local speed = (now - last).Magnitude / dt
		if speed > worst.speed then
			worst.speed, worst.at = speed, since
		end
		last = now
		if not art.done and art.time > letGoAt + 1e-6 then
			worst.clockMoved = true
		end
	end
	worst.gone = art.done == true
	connection:Disconnect()
	locomotion:destroy()
	Choreo.release(model)
	return worst
end

local function caseName(case: Case): string
	local at = if case.at == "hold"
		then ("held %.2f s in its hold"):format(case.seconds)
		elseif case.at == "windUp" then ("frozen %.2f s into its wind-up"):format(case.seconds)
		else ("launched, %.3f s before its first cut"):format(case.seconds)
	return ("%s %s at %d Hz"):format(case.clipId, at, case.hz)
end

-- The in-scope Arts' clips.
local function artClips(): { string }
	local clips: { string } = {}
	for _, id in Scope.arts do
		local art = Arts.byId(id)
		assert(art ~= nil, "no art " .. id)
		table.insert(clips, art.clip)
	end
	return clips
end

local function cases(): { Case }
	local list: { Case } = {}
	for _, clipId in artClips() do
		local clip = ClipLibrary.get(clipId)
		local hold = eventTime(clip, "ActivationHold")
		local strike = firstStrike(clip)
		assert(strike < math.huge and strike > hold, clipId .. " has no first cut after its hold")
		for _, hz in RATES do
			table.insert(list, { clipId = clipId, hz = hz, at = "hold", seconds = 0.2 })
			for _, share in { 0.4, 0.8 } do
				table.insert(list, { clipId = clipId, hz = hz, at = "windUp", seconds = hold * share })
			end
			for _, share in { 0.25, 0.75 } do
				table.insert(list, { clipId = clipId, hz = hz, at = "launched", seconds = (strike - hold) * share })
			end
		end
	end
	return list
end

describe("a stance the server takes away comes down, it does not cut (D-340)", function()
	it("every in-scope Art, held, winding up or launched, keeps its tip under struckStanceTipSpeed", function()
		local problems: { string } = {}
		for _, case in cases() do
			local worst = run(case)
			if worst.speed > Combat.struckStanceTipSpeed then
				table.insert(
					problems,
					("%s: the tip moved %.1f studs a second %.3f s after the let-go (cap %d)"):format(
						caseName(case),
						worst.speed,
						worst.at,
						Combat.struckStanceTipSpeed
					)
				)
			end
		end
		if #problems > 0 then
			error(("%d problem(s):\n%s"):format(#problems, table.concat(problems, "\n")))
		end
	end)

	it("lets the stance go where it stood and all the way out", function()
		local problems: { string } = {}
		for _, case in cases() do
			if case.hz == 60 then
				local worst = run(case)
				if worst.clockMoved then
					table.insert(problems, caseName(case) .. ": the Art's clock ran on as it faded")
				end
				if not worst.gone then
					table.insert(problems, caseName(case) .. ": the Art still plays at the end")
				end
			end
		end
		if #problems > 0 then
			error(("%d problem(s):\n%s"):format(#problems, table.concat(problems, "\n")))
		end
	end)
end)
