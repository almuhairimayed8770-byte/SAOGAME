--!strict
--[[
	Validates the Studio dev hooks in src/shared/data/dev.luau (D-114): `aim`, the client helper
	that drives the real request path from a Studio MCP execute_luau call
	(src/client/dev/DevAim.client.luau), and `trace`, the server helper that reads
	CombatService.traceSink (src/server/dev/DevCombat.server.luau).

	Every wait the helpers make is tied to the game numbers it waits on, so a retuned combat table
	cannot quietly turn a helper's report into a wrong one:
	- aim.faceToleranceDegrees stays under combat.luau aim.snapDegrees (the swing's own snap finishes
	  the turn) and under deg(acos(1 - facingTolerance)), the farthest facing the server accepts;
	- aim.faceTimeoutSeconds lets the lock turn (aim.lockTurnRate) and the dev turn
	  (aim.faceDegreesPerSecond) come round from straight behind;
	- aim.replicationSettleSeconds covers combat.lagAllowance, so the server sees a dev turn and the
	  client's yaw history no longer holds the old facing;
	- aim.artHoldSeconds is past the start pose and activation hold and short of the cancel time;
	- aim.swingGapSeconds is no faster than BasicAttackRequest's refill, outlasts the server's basic
	  swing (basicHitDuration) and the latest basic hit window plus the lag allowance (so a swing's
	  hit is in before the next goes), and stays inside basicChainWindow (the chain carries on);
	- aim.runTimeoutSeconds and trace.runTimeoutSeconds outlast the longest loadout Art;
	- aim.maxSwings covers one whole basic chain; trace.keepEvents holds every window of the
	  longest swing command.

	The capture's timeScale.steps are each above 0 and at most 1, and timeScale.default is one of
	them: the capture slows the local body with them (CharacterController.setCaptureTimeScale), so
	a step past 1x would move it faster than the anti-cheat's sprint cap.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local HALF_TURN_DEGREES = 180
local MAX_DECIMALS = 6
local CLIPS = "src/shared/clips/"

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isWhole(value: any): boolean
	return isNumber(value) and value % 1 == 0
end

local function isName(value: any): boolean
	return typeof(value) == "string" and value:match("^%a%w*$") ~= nil
end

return function(ctx: Context): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, "dev: " .. message)
	end

	local dev = ctx.load("src/shared/data/dev")
	local combat = ctx.load("src/shared/data/combat")
	local world = ctx.load("src/shared/data/world")
	local arts = ctx.load("src/shared/data/arts")
	local weapons = ctx.load("src/shared/data/weapons")
	local playground = ctx.load("src/shared/data/playground")
	local sampler = ctx.load("src/shared/choreo/ClipSampler")

	-- The capture's slow-motion steps (D-111).
	local timeScale = dev.timeScale
	if typeof(timeScale) ~= "table" or typeof(timeScale.steps) ~= "table" or #timeScale.steps == 0 then
		problem("timeScale.steps must be a list of at least one scale")
	else
		for index, step in timeScale.steps do
			if not isNumber(step) or step <= 0 or step > 1 then
				problem(
					("timeScale.steps[%d] must be a number above 0 and at most 1 (got %s): the capture slows the local body with it, and past 1x it would outrun the anti-cheat's cap"):format(
						index,
						tostring(step)
					)
				)
			end
		end
		if table.find(timeScale.steps, timeScale.default) == nil then
			problem(("timeScale.default (%s) must be one of timeScale.steps"):format(tostring(timeScale.default)))
		end
	end

	local aim = dev.aim
	local trace = dev.trace
	if typeof(aim) ~= "table" then
		problem("aim table is missing")
		return problems
	end
	if typeof(trace) ~= "table" then
		problem("trace table is missing")
		return problems
	end

	local numeric = {
		"faceToleranceDegrees",
		"faceTimeoutSeconds",
		"faceDegreesPerSecond",
		"replicationSettleSeconds",
		"artHoldSeconds",
		"swingGapSeconds",
		"runTimeoutSeconds",
		"actionSettleSeconds",
	}
	for _, key in numeric do
		if not isNumber(aim[key]) or aim[key] <= 0 then
			problem(("aim.%s must be a positive number"):format(key))
		end
	end
	if not isNumber(trace.runTimeoutSeconds) or trace.runTimeoutSeconds <= 0 then
		problem("trace.runTimeoutSeconds must be a positive number")
	end
	if #problems > 0 then
		return problems
	end

	-- Names
	if not isName(aim.bindableName) then
		problem("aim.bindableName must be a plain instance name")
	end
	if not isName(trace.bindableName) then
		problem("trace.bindableName must be a plain instance name")
	end
	if aim.bindableName == trace.bindableName then
		problem("aim.bindableName and trace.bindableName must differ")
	end
	if typeof(trace.printPrefix) ~= "string" or trace.printPrefix == "" then
		problem("trace.printPrefix must be a non-empty string")
	end
	local function checkDecimals(name: string, decimals: any)
		if not isWhole(decimals) or decimals < 0 or decimals > MAX_DECIMALS then
			problem(("%s.decimals must be a whole number from 0 to %d"):format(name, MAX_DECIMALS))
		end
	end
	checkDecimals("aim", aim.decimals)
	checkDecimals("trace", trace.decimals)

	-- Facing
	local acceptance = math.deg(math.acos(1 - combat.facingTolerance))
	if aim.faceToleranceDegrees >= acceptance then
		problem(
			("aim.faceToleranceDegrees (%g) must be under the server's facing acceptance (%.2f degrees)"):format(
				aim.faceToleranceDegrees,
				acceptance
			)
		)
	end
	local combatAim = combat.aim
	if typeof(combatAim) == "table" then
		if isNumber(combatAim.snapDegrees) and aim.faceToleranceDegrees >= combatAim.snapDegrees then
			problem(
				("aim.faceToleranceDegrees (%g) must be under combat.aim.snapDegrees (%g): the swing's snap finishes the turn"):format(
					aim.faceToleranceDegrees,
					combatAim.snapDegrees
				)
			)
		end
		if isNumber(combatAim.lockTurnRate) and combatAim.lockTurnRate > 0 then
			local needed = HALF_TURN_DEGREES / combatAim.lockTurnRate
			if aim.faceTimeoutSeconds < needed then
				problem(
					("aim.faceTimeoutSeconds (%g) is shorter than the lock turn from straight behind (%.3f s)"):format(
						aim.faceTimeoutSeconds,
						needed
					)
				)
			end
		end
	end
	local devTurn = HALF_TURN_DEGREES / aim.faceDegreesPerSecond
	if aim.faceTimeoutSeconds < devTurn then
		problem(
			("aim.faceTimeoutSeconds (%g) is shorter than the dev turn from straight behind (%.3f s)"):format(
				aim.faceTimeoutSeconds,
				devTurn
			)
		)
	end
	if aim.replicationSettleSeconds < combat.lagAllowance then
		problem(
			("aim.replicationSettleSeconds (%g) must cover combat.lagAllowance (%g)"):format(
				aim.replicationSettleSeconds,
				combat.lagAllowance
			)
		)
	end
	if aim.actionSettleSeconds < combat.lagAllowance then
		problem(
			("aim.actionSettleSeconds (%g) must cover combat.lagAllowance (%g)"):format(
				aim.actionSettleSeconds,
				combat.lagAllowance
			)
		)
	end

	-- The Art hold
	local stance = combat.startPoseTime + combat.activationHold
	if aim.artHoldSeconds <= stance then
		problem(
			("aim.artHoldSeconds (%g) must pass the start pose and activation hold (%g)"):format(
				aim.artHoldSeconds,
				stance
			)
		)
	end
	if aim.artHoldSeconds >= combat.activationCancelTime then
		problem(
			("aim.artHoldSeconds (%g) must be short of combat.activationCancelTime (%g)"):format(
				aim.artHoldSeconds,
				combat.activationCancelTime
			)
		)
	end

	-- The loadout's attacks: the basic chain of its weapon and its quick-slot Arts.
	local loadout = playground.loadout
	local category = weapons.category(loadout.weapon)
	local latestBasicClose = 0
	local mostWindows = 0
	if category == nil then
		problem(("playground loadout weapon %s has no category"):format(tostring(loadout.weapon)))
	else
		for index = 1, combat.basicChainLength do
			local path = ("%splayer/%s/Basic%d"):format(CLIPS, category, index)
			local ok, clip = pcall(ctx.load, path)
			if not ok then
				problem(("no basic clip at %s"):format(path))
				continue
			end
			local windows = sampler.hitWindows(clip)
			mostWindows = math.max(mostWindows, #windows)
			for _, window in windows do
				latestBasicClose = math.max(latestBasicClose, window.close)
			end
		end
	end
	local longestArt = 0
	for _, artId in loadout.artSlots do
		local art = arts.byId(artId)
		if art == nil then
			continue -- the playground validator reports it
		end
		longestArt = math.max(longestArt, art.total + art.postMotion)
		mostWindows = math.max(mostWindows, art.hits)
	end

	-- Swing spacing
	local rate = world.anticheat.remoteRates.BasicAttackRequest.perSecond
	if aim.swingGapSeconds < 1 / rate then
		problem(
			("aim.swingGapSeconds (%g) is faster than BasicAttackRequest's refill (%g a second)"):format(
				aim.swingGapSeconds,
				rate
			)
		)
	end
	if aim.swingGapSeconds < combat.basicHitDuration then
		problem(
			("aim.swingGapSeconds (%g) must outlast the server's basic swing (basicHitDuration %g)"):format(
				aim.swingGapSeconds,
				combat.basicHitDuration
			)
		)
	end
	local seen = latestBasicClose + combat.lagAllowance
	if aim.swingGapSeconds < seen then
		problem(
			("aim.swingGapSeconds (%g) must outlast the latest basic hit window plus the lag allowance (%g)"):format(
				aim.swingGapSeconds,
				seen
			)
		)
	end
	if aim.swingGapSeconds > combat.basicChainWindow then
		problem(
			("aim.swingGapSeconds (%g) must stay inside combat.basicChainWindow (%g) so the chain carries on"):format(
				aim.swingGapSeconds,
				combat.basicChainWindow
			)
		)
	end

	-- Run timeouts
	local artRun = longestArt + aim.artHoldSeconds + combat.lagAllowance
	if aim.runTimeoutSeconds < artRun then
		problem(
			("aim.runTimeoutSeconds (%g) must outlast the longest loadout Art from the press (%g)"):format(
				aim.runTimeoutSeconds,
				artRun
			)
		)
	end
	local serverRun = longestArt + combat.lagAllowance
	if trace.runTimeoutSeconds < serverRun then
		problem(
			("trace.runTimeoutSeconds (%g) must outlast the longest loadout Art (%g)"):format(
				trace.runTimeoutSeconds,
				serverRun
			)
		)
	end

	-- Counts
	if not isWhole(aim.maxSwings) or aim.maxSwings < combat.basicChainLength then
		problem(
			("aim.maxSwings must be a whole number of at least combat.basicChainLength (%d)"):format(
				combat.basicChainLength
			)
		)
	elseif not isWhole(trace.keepEvents) or trace.keepEvents < aim.maxSwings * mostWindows then
		problem(
			("trace.keepEvents must be a whole number of at least aim.maxSwings x the most windows a loadout attack has (%d)"):format(
				aim.maxSwings * mostWindows
			)
		)
	end

	return problems
end
