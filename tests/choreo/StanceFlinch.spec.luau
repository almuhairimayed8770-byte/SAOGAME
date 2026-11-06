--!strict
--[[
	A hit out of an Art's stance, on the game's own path (D-294). The Choreo animator and its mixer
	(Base locomotion, the Art on FullBody, the flinch on Additive) and Locomotion run on the hit
	matrix's player, and the spec makes the calls the client makes, in their order:
	CharacterController.beginArt plays the Art; its ActivationHold event freezes the hold
	(freezeHold: the rig's time scale to 0); Replication.showStrike plays the flinch on the
	strike's frame (D-258); a latency later the server's Stagger lets the hold go (clearHold: the
	time scale back to 1, the Art stopped with combat.luau locomotionBlendOut). The word path
	(no strike shown) holds the rig for the Normal hit-stop and plays the flinch with the word.

	The flinch reads on the frame the blow lands and on every frame the stance still holds: the
	pose shows the flinch's hit at full (flinchShown of its peak), however still the rig's clock
	stands. The stance goes cleanly: from the moment it is let go, the Art fades out where it
	stood, its clock never moving on into the anticipation or the cut and no event of it firing,
	whether the blow lands in the hold or while the stance is still being taken. Only the stance
	and wind-up stand: an Art let go past its first cut still crosses the keys that close its
	window and trail, and a remote rig (Locomotion.attach) keeps its clock running, so the
	HitWindowOpen its fade crosses puts the activation light out (D-231).
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

local PREFIX = "player/OneHandedSword/"
local ART = PREFIX .. "SharpNail"
local SIDES = { "Front", "Back", "Left", "Right" }
local RATES = { 60, 144, 240 }
-- The share of the flinch's own peak the strike frame shows at least.
local SHOWN = 0.9

-- The clip time of a clip's first event of `kind`.
local function eventTime(clipId: string, kind: string): number
	for _, event in ClipLibrary.get(clipId).events or {} do
		if event.kind == kind then
			return event.time
		end
	end
	error(("%s has no %s event"):format(clipId, kind))
end

-- The largest joint rotation (degrees) or move (studs, x 100) a key holds.
local function keyPeak(key: any): number
	local peak = 0
	for _, joint in key.joints do
		for axis = 1, 3 do
			if joint.rot ~= nil then
				peak = math.max(peak, math.abs(joint.rot[axis]))
			end
			if joint.pos ~= nil then
				peak = math.max(peak, math.abs(joint.pos[axis]) * 100)
			end
		end
	end
	return peak
end

-- A clip's peak (the most any key holds, as keyPeak) and the time of the last key that holds it:
-- until then the hit is the clip's own pose, after it the recoil.
local function peakOf(clipId: string): (number, number)
	local peak, peakEnd = 0, 0
	for _, key in ClipLibrary.get(clipId).keys do
		local held = keyPeak(key)
		if held > peak + 1e-9 then
			peak, peakEnd = held, key.time
		elseif held > peak - 1e-9 then
			peakEnd = key.time
		end
	end
	return peak, peakEnd
end

-- How far apart two poses are, the same scale as peakOf: the most any joint turned (degrees) or
-- moved (studs, x 100) between them.
local function apart(a: any, b: any): number
	local most = 0
	local function compare(x: any, y: any)
		for axis = 1, 3 do
			most = math.max(most, math.abs(x.rot[axis] - y.rot[axis]), math.abs(x.pos[axis] - y.pos[axis]) * 100)
		end
	end
	local zero = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }
	for name, offset in a do
		compare(offset, b[name] or zero)
	end
	for name, offset in b do
		if a[name] == nil then
			compare(zero, offset)
		end
	end
	return most
end

type Case = {
	hz: number,
	side: string,
	-- "hold": the blow lands holdFor seconds into the frozen hold; "windUp": it lands strikeAt
	-- seconds after the Art started, before its ActivationHold.
	at: string,
	holdFor: number?,
	strikeAt: number?,
	latency: number, -- seconds from the strike frame to the server's word
	path: string, -- "shown" (D-258, the flinch on the strike frame) or "word" (hit-stop, flinch on the word)
	flinch: boolean, -- false: the same run with no flinch played (the reference)
}

type Frame = {
	offsets: { [string]: any },
	phase: string, -- "before" the strike, "stance" (struck, the word not come), "after" the word
	artTime: number?, -- the Art's clock, nil once its handle is gone
	flinchTime: number?, -- the flinch's clock, nil while none plays
}

type Run = {
	frames: { Frame },
	frozenAt: number?, -- the Art's clock when the hold froze it
	wordArtTime: number, -- the Art's clock when the word let the stance go
	lateEvents: { string }, -- the Art's events fired after the word
}

local function run(case: Case): Run
	local avatar = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", true)
	model:SetAttribute("State", "Idle")
	local primary = model.PrimaryPart
	primary.CFrame = avatar.base
	primary.Position = avatar.base.Position
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, { footIK = false })
	local dt = 1 / case.hz
	local holding = false
	local frozenAt: number? = nil
	local art: any = nil
	local afterWord = false
	local lateEvents: { string } = {}
	local connection = animator.events:Connect(function(clipId: string, event: any)
		if clipId ~= ART then
			return
		end
		if afterWord then
			table.insert(lateEvents, ("%s at %.3f"):format(event.kind, event.time))
		elseif event.kind == "ActivationHold" and holding and frozenAt == nil then
			-- CharacterController's clipEvent listener: freezeHold.
			frozenAt = art.time
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
	for _ = 1, case.hz do
		frame()
	end
	-- beginArt
	art = animator:play(ART)
	holding = true
	local flinchId = PREFIX .. "Flinch" .. case.side
	local flinch: any = nil
	local frames: { Frame } = {}
	local struck, worded = false, false
	local since, frozenSince = 0, 0
	local wordArtTime = 0
	local total = math.ceil((0.25 + (case.holdFor or 0) + case.latency + 0.6) * case.hz)
	for _ = 1, total do
		since += dt
		if frozenAt ~= nil then
			frozenSince += dt
		end
		if not struck then
			local due = if case.at == "hold"
				then frozenAt ~= nil and frozenSince >= (case.holdFor :: number) + dt - 1e-9
				else since >= (case.strikeAt :: number) - 1e-9
			if due then
				struck = true
				since = 0
				if case.path == "shown" and case.flinch then
					flinch = animator:play(flinchId) -- Replication.showStrike's playReaction
				end
			end
		elseif not worded and since >= case.latency - 1e-9 then
			worded = true
			if case.path == "word" then
				-- HitConfirmed's holdLocal, then StateChanged's playReaction.
				animator:hitStop(Combat.hitStopFrames.Normal - Combat.hitStopShaveFrames)
				if case.flinch then
					flinch = animator:play(flinchId)
				end
			end
			-- The State attribute's Stagger: clearHold.
			holding = false
			wordArtTime = art.time
			animator:setTimeScale(1)
			animator:stop(art, Combat.locomotionBlendOut)
			afterWord = true
		end
		frame()
		local offsets = {}
		for name, offset in animator.mixer:lastOffsets() do
			offsets[name] = { pos = table.clone(offset.pos), rot = table.clone(offset.rot) }
		end
		table.insert(frames, {
			offsets = offsets,
			phase = if worded then "after" elseif struck then "stance" else "before",
			artTime = if art.done then nil else art.time,
			flinchTime = if flinch ~= nil and not flinch.done then flinch.time else nil,
		})
	end
	connection:Disconnect()
	locomotion:destroy()
	Choreo.release(model)
	return { frames = frames, frozenAt = frozenAt, wordArtTime = wordArtTime, lateEvents = lateEvents }
end

local function caseName(case: Case): string
	local at = if case.at == "hold"
		then ("%.2f s into the hold"):format(case.holdFor :: number)
		else ("%.3f s into the wind-up"):format(case.strikeAt :: number)
	return ("Flinch%s %s at %d Hz, %s path, word %.2f s later"):format(case.side, at, case.hz, case.path, case.latency)
end

-- The struck frames that do not show the flinch's hit: the strike frame and every frame the stance
-- still holds (on the word path, the word's frame and the hit-stop's).
local function unshown(case: Case): { string }
	local with = run(case)
	local reference = table.clone(case)
	reference.flinch = false
	local without = run(reference)
	local peak, peakEnd = peakOf(PREFIX .. "Flinch" .. case.side)
	local firstStruck: number? = nil
	local checked, short, least = 0, 0, math.huge
	for index, frame in with.frames do
		-- Struck: on the shown path from the strike frame, on the word path from the word's frame.
		local struck = if case.path == "shown" then frame.phase ~= "before" else frame.phase == "after"
		if struck and firstStruck == nil then
			firstStruck = index
		end
		-- The frames the flinch's clock has not taken past its hit: all of them while the clock
		-- stands (the frozen hold, the hit-stop), the first ones while it runs.
		local flinchTime = frame.flinchTime
		if struck and flinchTime ~= nil and flinchTime <= peakEnd + 1e-9 then
			local shown = apart(frame.offsets, without.frames[index].offsets)
			checked += 1
			least = math.min(least, shown)
			if shown < peak * SHOWN then
				short += 1
			end
		end
	end
	assert(firstStruck ~= nil and checked > 0, caseName(case) .. ": the blow never landed")
	if short == 0 then
		return {}
	end
	return {
		("%s: %d of the %d struck frames show under %d%% of the flinch (least %.1f of %.1f)"):format(
			caseName(case),
			short,
			checked,
			SHOWN * 100,
			least,
			peak
		),
	}
end

-- What the stance did after the word let it go: its clock moving past where it stood, or its
-- events firing.
local function unclean(case: Case): { string }
	local result = run(case)
	local problems: { string } = {}
	local most = result.wordArtTime
	for _, frame in result.frames do
		if frame.phase == "after" and frame.artTime ~= nil then
			most = math.max(most, frame.artTime :: number)
		end
	end
	if most > result.wordArtTime + 1e-6 then
		table.insert(
			problems,
			("%s: the Art's clock ran on from %.3f to %.3f s as it faded"):format(
				caseName(case),
				result.wordArtTime,
				most
			)
		)
	end
	if #result.lateEvents > 0 then
		table.insert(
			problems,
			("%s: the Art fired %s after the word"):format(caseName(case), table.concat(result.lateEvents, ", "))
		)
	end
	-- It fades all the way out, and the stance's pose leaves with it.
	local last = result.frames[#result.frames]
	if last.artTime ~= nil then
		table.insert(problems, ("%s: the Art still plays at the end"):format(caseName(case)))
	end
	return problems
end

local function report(problems: { string })
	if #problems > 0 then
		error(("%d problem(s):\n%s"):format(#problems, table.concat(problems, "\n")))
	end
end

describe("a hit out of an Art's stance (D-294)", function()
	it("the frozen hold freezes Sharp Nail at its ActivationHold, as the case assumes", function()
		local result =
			run({ hz = 60, side = "Front", at = "hold", holdFor = 0.2, latency = 0.1, path = "shown", flinch = true })
		expect(result.frozenAt).never.toBeNil()
		expect(math.abs((result.frozenAt :: number) - eventTime(ART, "ActivationHold")) < 1 / 60 + 1e-9).toBe(true)
	end)

	it("reads as a flinch on the strike frame and every frame the stance still holds", function()
		local problems: { string } = {}
		for _, hz in RATES do
			for _, side in SIDES do
				for _, path in { "shown", "word" } do
					local case: Case =
						{ hz = hz, side = side, at = "hold", holdFor = 0.2, latency = 0.1, path = path, flinch = true }
					for _, line in unshown(case) do
						table.insert(problems, line)
					end
				end
			end
		end
		report(problems)
	end)

	it("reads as a flinch on the strike frame while the stance is still being taken", function()
		local problems: { string } = {}
		for _, hz in RATES do
			for _, side in SIDES do
				local case: Case = {
					hz = hz,
					side = side,
					at = "windUp",
					strikeAt = 0.05,
					latency = 0.05,
					path = "shown",
					flinch = true,
				}
				for _, line in unshown(case) do
					table.insert(problems, line)
				end
			end
		end
		report(problems)
	end)

	it("lets the stance go where it stood: no clock past it, no event, all of it faded", function()
		local problems: { string } = {}
		for _, hz in RATES do
			for _, latency in { 0.05, 0.1, 0.25 } do
				for _, case in
					{
						{
							hz = hz,
							side = "Front",
							at = "hold",
							holdFor = 0.2,
							latency = latency,
							path = "shown",
							flinch = true,
						},
						{
							hz = hz,
							side = "Left",
							at = "hold",
							holdFor = 0.05,
							latency = latency,
							path = "word",
							flinch = true,
						},
						-- Struck before the ActivationHold: the word comes before the hold freezes.
						{
							hz = hz,
							side = "Back",
							at = "windUp",
							strikeAt = 0.03,
							latency = 0.05,
							path = "shown",
							flinch = true,
						},
					} :: { Case }
				do
					for _, line in unclean(case) do
						table.insert(problems, line)
					end
				end
			end
		end
		report(problems)
	end)

	it("lets an Art let go after its first damage frame play on, closing its window and trail", function()
		-- Only the stance and wind-up stand: past the first cut the fade still crosses the
		-- HitWindowClose and TrailOff that put the trail out (Replication.routeClipEvent).
		local avatar = HitMatrix.standing(Harness)
		local model = avatar.model
		model:SetAttribute("Rig", "PlayerR15")
		model:SetAttribute("Drawn", true)
		model:SetAttribute("State", "Idle")
		local primary = model.PrimaryPart
		primary.CFrame = avatar.base
		primary.Position = avatar.base.Position
		local animator: any = Choreo.get(model)
		local locomotion: any = Locomotion.new(animator, model, { footIK = false })
		local dt = 1 / 60
		local stopped = false
		local fired: { string } = {}
		local connection = animator.events:Connect(function(clipId: string, event: any)
			if clipId == ART and stopped then
				table.insert(fired, event.kind)
			end
		end)
		local art: any = animator:play(ART)
		local cut = eventTime(ART, "HitWindowOpen") + 0.02
		for _ = 1, 120 do
			if not stopped and art.time >= cut then
				stopped = true
				animator:stop(art, Combat.locomotionBlendOut)
			end
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
		connection:Disconnect()
		locomotion:destroy()
		Choreo.release(model)
		expect(stopped).toBe(true)
		expect(table.find(fired, "HitWindowClose")).never.toBeNil()
		expect(table.find(fired, "TrailOff")).never.toBeNil()
	end)

	it("keeps a remote Art's clock running as it fades, so its HitWindowOpen puts the light out", function()
		-- Replication.routeClipEvent closes a remote Art's activation light on the HitWindowOpen its
		-- fade crosses (D-231): a rig Locomotion.attach drives never holds a clip it lets go.
		local avatar = HitMatrix.standing(Harness)
		local model = avatar.model
		model:SetAttribute("Rig", "PlayerR15")
		model:SetAttribute("Drawn", true)
		model:SetAttribute("State", "Idle")
		local primary = model.PrimaryPart
		primary.CFrame = avatar.base
		primary.Position = avatar.base.Position
		local animator: any = Choreo.get(model)
		local driver: any = Locomotion.attach(animator, model, {
			footIK = false,
			tracker = function()
				return {
					moveDir = Vector3.zero,
					speed = 0,
					sprinting = false,
					grounded = true,
					turning = 0,
					verticalVelocity = 0,
					velocity = Vector3.zero,
				}
			end,
		})
		local dt = 1 / 60
		local stopped = false
		local fired: { string } = {}
		local connection = animator.events:Connect(function(clipId: string, event: any)
			if clipId == ART and stopped then
				table.insert(fired, event.kind)
			end
		end)
		local art: any = animator:play(ART)
		local stance = eventTime(ART, "ActivationHold") + 0.05
		for _ = 1, 120 do
			if not stopped and art.time >= stance then
				stopped = true
				animator:stop(art, Combat.locomotionBlendOut)
			end
			clock += dt
			animator:step(dt)
		end
		connection:Disconnect()
		driver:destroy()
		Choreo.release(model)
		expect(stopped).toBe(true)
		expect(table.find(fired, "HitWindowOpen")).never.toBeNil()
	end)
end)
