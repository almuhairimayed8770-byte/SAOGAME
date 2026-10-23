--!strict
--[[
	Validates the server hit detection block of src/shared/data/combat.luau (section 6, D-010):
	the sample rate, hit radius and target cap are positive, the lag allowance is not negative, and
	the arc sweep (HitSweep.followArc) is tied to the hit radius and has a positive whole cap.

	sweepMaxTipStep is how far either end of the blade may move between two samples of the sweep
	while sweepMaxSubdivisions lasts (a step the cap leaves longer is covered by its ends' chords
	instead, HitSweep.castBladePath). Every point the blade passes between two samples lies within
	half a step of one of them, and the overlap test reaches one hit radius from each sampled blade,
	so a step of at most two radii is what guarantees that a blade passing through a target touches
	it at a sample; past that, a thin target can sit in the gap between two sampled blades.

	sweepMaxRootSpeed decides when the body jumped (HitSweep.jumped): a root step longer than it
	times the time since the last sample, plus what is left of the window's lag credit (it times
	lagAllowance when full; a longer step spends it, a shorter one refills it). So over any stretch
	of a window the root may travel the speed times (the stretch + lagAllowance). An honest body
	must never jump, so the speed is at least sweepRootSpeedMargin times the fastest honest travel
	over any span of at least lagAllowance, from every source of travel:
	- walking: the sprint cap (maxSpeedStudsPerSecond) or choreo.luau's sprintSpeed, the faster;
	- root motion: walking plus the longest path any player clip's root motion carries the body in
	  the span (read at dev.luau groundClearance.sampleHz, every frame of the 0.25x review);
	- the dodge: walking plus dodgeDistance over dodgeDuration;
	- the anti-cheat: what it lets a body travel in one of its samples (anticheatSampleInterval) at
	  the sprint cap times speedMargin, with its full lag credit, plus a dodge or the largest
	  in-scope Art's rootMotion with rootMotionSlack, over that sample and the lag.
	speedMargin is the speed check's tolerance on the sprint cap (D-052): at least 1, so an honest
	sprint at the cap is never judged past it, and at most MAX_SPEED_MARGIN, so the check still
	catches a body much faster than the cap.
	A move the anti-cheat calls a teleport must never be swept across, so the farthest the sweep
	follows the root over one anti-cheat sample (the speed over the sample, or one frame if that is
	longer, plus the full credit) stays under teleportFlagDistance.

	The aim table (D-112): every number is sound, and aim.snapDegrees plus
	aim.replicationMarginDegrees stays within deg(acos(1 - facingTolerance)), the farthest a request's
	facing may be from the root the server has seen. A swing turns the body by up to the snap the
	instant it is sent, and the server may still be catching up on a turn before it, so a bigger sum
	would get honest swings rejected (and their clips cancelled).
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

-- The widest step that still guarantees a pass-through touches a sample, in hit radii.
local MAX_STEP_IN_RADII = 2
-- The largest tolerance the speed check may put on the sprint cap (D-052).
local MAX_SPEED_MARGIN = 1.25
-- The widest a cone around the body can be.
local FULL_TURN_DEGREES = 360

local PLAYER_CLIPS = "src/shared/clips/player"

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- The fastest a clip's root motion carries the body over any span of at least `minimum` seconds,
-- in studs per second, with the root read `hz` times a second. It is the path the root travels in
-- the span, not the straight line across it: the sweep's lag credit is spent by the sum of its
-- frame steps, and a root that goes back and forth spends it on every step. Spans start at
-- `minimum` (rounded up to a reading) and grow a reading at a time until they cover the whole clip.
local function fastestRootMotion(ClipSampler: any, clip: any, minimum: number, hz: number): number
	local duration = clip.duration
	if not isNumber(duration) or duration <= 0 then
		return 0
	end
	local count = math.ceil(duration * hz)
	-- along[index]: the root's path length from the clip's start to reading `index`.
	local along: { [number]: number } = { [0] = 0 }
	local previous = ClipSampler.rootMotionAt(clip, 0)
	for index = 1, count do
		local root = ClipSampler.rootMotionAt(clip, math.min(index / hz, duration))
		local dx, dy, dz = root[1] - previous[1], root[2] - previous[2], root[3] - previous[3]
		along[index] = along[index - 1] + math.sqrt(dx * dx + dy * dy + dz * dz)
		previous = root
	end
	-- The whole path: no span can carry the root farther, so once that over the span is no faster
	-- than the fastest span found, longer spans cannot be faster either.
	local length = along[count]
	if length <= 0 then
		return 0
	end
	local fastest = 0
	local span = math.max(math.ceil(minimum * hz - 1e-9), 1)
	while length / (span / hz) > fastest do
		local farthest = 0
		for from = 0, math.max(count - span, 0) do
			local to = math.min(from + span, count)
			farthest = math.max(farthest, along[to] - along[from])
		end
		fastest = math.max(fastest, farthest / (span / hz))
		if span >= count then
			break
		end
		span += 1
	end
	return fastest
end

return function(ctx: Context): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, "combat: " .. message)
	end

	local combat = ctx.load("src/shared/data/combat")

	local function positive(name: string): boolean
		local value = combat[name]
		if not isNumber(value) or value <= 0 then
			problem(("%s must be a positive number (got %s)"):format(name, tostring(value)))
			return false
		end
		return true
	end

	local function positiveWhole(name: string): boolean
		local value = combat[name]
		if not isNumber(value) or value < 1 or value % 1 ~= 0 then
			problem(("%s must be a positive whole number (got %s)"):format(name, tostring(value)))
			return false
		end
		return true
	end

	-- Aim (D-112): checked first, since the hit sweep checks below stop at their first gap.
	local aim = combat.aim
	if typeof(aim) ~= "table" then
		problem(("aim must be a table (got %s)"):format(typeof(aim)))
	else
		local function aimPositive(name: string): boolean
			local value = aim[name]
			if not isNumber(value) or value <= 0 then
				problem(("aim.%s must be a positive number (got %s)"):format(name, tostring(value)))
				return false
			end
			return true
		end
		local function aimNonNegative(name: string): boolean
			local value = aim[name]
			if not isNumber(value) or value < 0 then
				problem(("aim.%s must be a number, 0 or more (got %s)"):format(name, tostring(value)))
				return false
			end
			return true
		end
		aimPositive("lockTurnRate")
		aimPositive("assistRange")
		aimNonNegative("assistAngleWeightStuds")
		aimNonNegative("minFaceDistance")
		if aimPositive("assistConeDegrees") and aim.assistConeDegrees > FULL_TURN_DEGREES then
			problem(
				("aim.assistConeDegrees %s is wider than a full turn (%d)"):format(
					tostring(aim.assistConeDegrees),
					FULL_TURN_DEGREES
				)
			)
		end
		if typeof(aim.lockFaceWhileSprinting) ~= "boolean" then
			problem(
				("aim.lockFaceWhileSprinting must be true or false (got %s)"):format(
					tostring(aim.lockFaceWhileSprinting)
				)
			)
		end
		local snapOk = aimPositive("snapDegrees")
		local marginOk = aimNonNegative("replicationMarginDegrees")
		local toleranceOk = isNumber(combat.facingTolerance)
			and combat.facingTolerance > 0
			and combat.facingTolerance <= 2
		if not toleranceOk then
			problem(
				("facingTolerance must be a number above 0 and at most 2 (got %s)"):format(
					tostring(combat.facingTolerance)
				)
			)
		end
		if snapOk and marginOk and toleranceOk then
			local acceptance = math.deg(math.acos(1 - combat.facingTolerance))
			if aim.snapDegrees + aim.replicationMarginDegrees > acceptance then
				problem(
					("aim.snapDegrees %s + aim.replicationMarginDegrees %s is over the server's facing acceptance, deg(acos(1 - facingTolerance)) = %.2f: a swing turned that far would be rejected"):format(
						tostring(aim.snapDegrees),
						tostring(aim.replicationMarginDegrees),
						acceptance
					)
				)
			end
		end
	end

	local rateOk = positive("hitSampleHz")
	positiveWhole("maxTargetsPerWindow")
	local lagOk = isNumber(combat.lagAllowance) and combat.lagAllowance >= 0
	if not lagOk then
		problem(("lagAllowance must be a number of seconds, 0 or more (got %s)"):format(tostring(combat.lagAllowance)))
	end

	local radiusOk = positive("hitSphereRadius")
	local stepOk = positive("sweepMaxTipStep")
	positiveWhole("sweepMaxSubdivisions")
	if radiusOk and stepOk and combat.sweepMaxTipStep > combat.hitSphereRadius * MAX_STEP_IN_RADII then
		problem(
			("sweepMaxTipStep %s is over %d x hitSphereRadius (%s): a blade could pass through a target between two sub-samples"):format(
				tostring(combat.sweepMaxTipStep),
				MAX_STEP_IN_RADII,
				tostring(combat.hitSphereRadius)
			)
		)
	end

	-- When the body jumped: the root speed bound and its margin over honest travel.
	local speedOk = positive("sweepMaxRootSpeed")
	local margin = combat.sweepRootSpeedMargin
	local marginOk = isNumber(margin) and margin >= 1
	if not marginOk then
		problem(("sweepRootSpeedMargin must be a number, 1 or more (got %s)"):format(tostring(margin)))
	end
	local speedMargin = combat.speedMargin
	local speedMarginOk = isNumber(speedMargin) and speedMargin >= 1 and speedMargin <= MAX_SPEED_MARGIN
	if not speedMarginOk then
		problem(
			("speedMargin must be a number from 1 to %s: the speed check's tolerance on the sprint cap (got %s)"):format(
				tostring(MAX_SPEED_MARGIN),
				tostring(speedMargin)
			)
		)
	end
	local sourcesOk = speedMarginOk
		and positive("maxSpeedStudsPerSecond")
		and positive("dodgeDistance")
		and positive("dodgeDuration")
		and positive("anticheatSampleInterval")
		and positive("teleportFlagDistance")
		and isNumber(combat.rootMotionSlack)
	if not (speedOk and marginOk and sourcesOk and rateOk and lagOk) then
		return problems
	end

	local choreo = ctx.load("src/shared/data/choreo")
	local dev = ctx.load("src/shared/data/dev")
	local ClipSampler = ctx.load("src/shared/choreo/ClipSampler")
	local lag = combat.lagAllowance
	local walking = math.max(combat.maxSpeedStudsPerSecond, choreo.locomotion.sprintSpeed)
	local sources: { { name: string, speed: number } } = {
		{ name = "walking", speed = walking },
		{
			name = "the dodge",
			speed = walking + combat.dodgeDistance / math.max(combat.dodgeDuration, lag),
		},
	}

	-- Root motion: every player clip, over spans of at least the lag (at least one reading).
	local hz = dev.groundClearance.sampleHz
	local fastestClip, fastestSpeed = "", 0
	for _, file in ctx.listFiles(PLAYER_CLIPS, "%.luau$") do
		local id = file:match("^src/shared/clips/(.-)%.luau$")
		if id == nil then
			continue
		end
		local ok, clip = pcall(ctx.load, "src/shared/clips/" .. id)
		if not ok or typeof(clip) ~= "table" then
			continue -- the clips validator reports a clip that does not load
		end
		local speed = fastestRootMotion(ClipSampler, clip, lag, hz)
		if speed > fastestSpeed then
			fastestClip, fastestSpeed = id, speed
		end
	end
	table.insert(sources, { name = "root motion (" .. fastestClip .. ")", speed = walking + fastestSpeed })

	-- The anti-cheat: one sample interval with the full lag credit and the largest burst it grants.
	local arts = ctx.load("src/shared/data/arts")
	local scope = ctx.load("src/shared/data/scope")
	local largestArt = 0
	for _, artId in scope.arts do
		local art = arts.byId(artId)
		if art ~= nil then
			largestArt = math.max(largestArt, art.rootMotion)
		end
	end
	local interval = combat.anticheatSampleInterval
	local burst = math.max(combat.dodgeDistance, largestArt + combat.rootMotionSlack)
	local allowed = combat.maxSpeedStudsPerSecond * combat.speedMargin * (interval + lag) + burst
	table.insert(sources, { name = "the anti-cheat allowance", speed = allowed / (interval + lag) })

	local honest, honestName = 0, ""
	for _, source in sources do
		if source.speed > honest then
			honest, honestName = source.speed, source.name
		end
	end
	if combat.sweepMaxRootSpeed < honest * margin then
		problem(
			("sweepMaxRootSpeed %s is under %s x the fastest honest travel (%.2f studs a second, %s): an honest body would break the sweep's chain"):format(
				tostring(combat.sweepMaxRootSpeed),
				tostring(margin),
				honest,
				honestName
			)
		)
	end
	-- The farthest the sweep follows the root over one anti-cheat sample (or one frame, if longer):
	-- the speed over it plus the full lag credit.
	local span = math.max(1 / combat.hitSampleHz, interval)
	local followed = combat.sweepMaxRootSpeed * (span + lag)
	if followed >= combat.teleportFlagDistance then
		problem(
			("sweepMaxRootSpeed %s lets the sweep follow the root %.1f studs in %.2f s (one anti-cheat sample and the lag credit), not under teleportFlagDistance (%s): it would sweep across a move the anti-cheat calls a teleport"):format(
				tostring(combat.sweepMaxRootSpeed),
				followed,
				span,
				tostring(combat.teleportFlagDistance)
			)
		)
	end

	return problems
end
