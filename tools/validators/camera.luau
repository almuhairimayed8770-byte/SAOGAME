--!strict
--[[
	Validates src/shared/data/camera.luau against section 10: the follow lag, rest FOV, kicks,
	nudge and shake tiers, the three orbit presets (Duel low and tight, Raid high and wide), sane
	pitch and zoom limits, lock-on distances and the shake noise lanes. The framing (D-145, D-146,
	D-149): the follow's leash (positive, and never clipping a hit's nudge), the two-shot's height,
	clearances, widest swing (inside a quarter turn, where the split between the fighters grows
	with the swing), side hysteresis, solve steps and blend lag, and the probe's see-through
	threshold and pass count. The close fight (F3): closeGap under openGap, both positive, the close
	swing inside a quarter turn, a positive close height and turn cap, the aim depth a fraction in
	(0, 1], and footprintPart RigBuilder's blocker name. The catch-up: catchUpDegreesPerSecond at
	least maxTurnDegreesPerSecond (it lifts the cap), catchUpMostDegrees and catchUpEase positive,
	catchUpMargin 0 or more. The death's still shot: riseHoldSeconds 0 or more. The wall at the
	shoulder: wallBlockedFraction in (0, 1], wallGainFraction in [0, 1]. The punch rows (Final, Kill):
	a few degrees, an attack inside the tier's hit-stop, a spring that swings back past rest by at
	most a quarter and is settled when it ends, eased in (never linear), short; the kill pushes in
	at least as far as the final hit. The render-stall numbers (stall): the longest piece a frame
	is cut into keeps every spring's semi-implicit Euler step from ringing or blowing up, and is at
	least a 60 fps frame; the settle snap comes only once every spring has settled, and never cuts
	one frame into more than MAX_PIECES pieces.
]]

-- A 60 fps frame: a piece shorter than this would cut every ordinary frame up.
local FRAME_SECONDS = 1 / 60
-- How far off its target (a fraction of the gap it started with) a spring may still be when a
-- stall past settleSeconds snaps it there: half a percent, under a pixel at the follow distance.
local SETTLE_BAND = 0.005
-- The most spring steps one long frame may take before the settle snap takes over.
local MAX_PIECES = 120

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "camera: " .. message)
		end
	end

	local camera = ctx.load("src/shared/data/camera")
	local combat = ctx.load("src/shared/data/combat")

	check(camera.follow.lag == 0.12, "follow.lag must be the section 10 value 0.12 s")
	check(camera.follow.damping >= 1, "follow.damping below critical would overshoot the follow")
	check(camera.fov.rest == 60, "fov.rest must be 60 degrees")
	check(camera.fov.artKick == 8 and camera.fov.dashKick == 8, "fov kicks must be +8 degrees")
	check(camera.fov.kickDecay > 0 and camera.fov.lag > 0, "fov decay and lag must be positive")
	check(camera.nudge.studs == combat.cameraNudgeStuds, "nudge.studs must point at combat.cameraNudgeStuds")
	check(camera.shake.amplitude == combat.cameraShakeStuds, "shake.amplitude must point at combat.cameraShakeStuds")
	check(camera.shake.decay > 0 and camera.shake.frequency > 0, "shake decay and frequency must be positive")
	check(camera.shake.cutoff > 0, "shake.cutoff must be positive")
	local startPhase = camera.shake.startPhase
	local period = if typeof(camera.shake.frequency) == "number" and camera.shake.frequency > 0
		then 1 / camera.shake.frequency
		else 0
	check(
		typeof(startPhase) == "number" and startPhase >= 0 and startPhase < period,
		("shake.startPhase (%s) must be in [0, 1/frequency %.4f) seconds: where a shake from rest starts its noise (312)"):format(
			tostring(startPhase),
			period
		)
	)
	check(typeof(camera.shake.lanes) == "table" and #camera.shake.lanes >= 2, "shake needs at least two noise lanes")
	for index, lane in camera.shake.lanes do
		check(
			typeof(lane) == "table" and typeof(lane[1]) == "number" and typeof(lane[2]) == "number" and lane[1] > 0,
			("shake.lanes[%d] must be {frequency multiplier > 0, phase}"):format(index)
		)
	end

	for _, name in { "Default", "Duel", "Raid" } do
		local orbit = camera.orbit[name]
		check(typeof(orbit) == "table", ("orbit.%s is missing"):format(name))
		if typeof(orbit) == "table" then
			check(orbit.distance > 0, ("orbit.%s.distance must be positive"):format(name))
			check(
				orbit.pitch >= camera.pitch.min and orbit.pitch <= camera.pitch.max,
				("orbit.%s.pitch must sit inside the pitch limits"):format(name)
			)
			check(
				orbit.distance >= camera.zoom.min and orbit.distance <= camera.zoom.max,
				("orbit.%s.distance must sit inside the zoom limits"):format(name)
			)
		end
	end
	check(camera.orbit.Duel.distance < camera.orbit.Default.distance, "Duel must be tighter than Default")
	check(camera.orbit.Raid.distance > camera.orbit.Default.distance, "Raid must be wider than Default")
	check(camera.orbit.Duel.pitch < camera.orbit.Default.pitch, "Duel must sit lower than Default")
	check(camera.orbit.Raid.pitch > camera.orbit.Default.pitch, "Raid must sit higher than Default")
	check(camera.orbit.Duel.height < camera.orbit.Raid.height, "Duel must sit lower than Raid")

	check(camera.pitch.min < camera.pitch.max, "pitch.min must be below pitch.max")
	check(camera.pitch.max < 90 and camera.pitch.min > -90, "pitch limits must stay off the poles")
	check(camera.zoom.min > 0 and camera.zoom.min < camera.zoom.max, "zoom.min must be positive and below zoom.max")
	check(camera.zoom.step > 0, "zoom.step must be positive")

	local lock = camera.lock
	check(lock.range > 0 and lock.breakDistance >= lock.range, "lock.breakDistance must be at least lock.range")
	check(lock.coneDegrees > 0 and lock.coneDegrees <= 360, "lock.coneDegrees must be in (0, 360]")
	check(
		lock.minDistance <= lock.baseDistance and lock.baseDistance <= lock.maxDistance,
		"lock distances must satisfy min <= base <= max"
	)
	check(lock.focusBias >= 0 and lock.focusBias <= 1, "lock.focusBias must be in 0..1")
	check(lock.yawLag > 0 and lock.angleWeightStuds >= 0, "lock.yawLag must be positive, angleWeightStuds non-negative")

	-- The framing: the two-shot, the leash and the probe.
	local function positive(value: any): boolean
		return typeof(value) == "number" and value == value and value > 0 and value < math.huge
	end
	local function count(value: any): boolean
		return positive(value) and value == math.floor(value)
	end
	check(lock.minDistance > 0, "lock.minDistance must be positive")
	check(
		positive(lock.height),
		"lock.height must be a positive number of studs: the two-shot camera stands over the player's root"
	)
	check(
		typeof(lock.lookHeight) == "number" and lock.lookHeight == lock.lookHeight,
		"lock.lookHeight must be a number of studs above the line between the roots"
	)
	check(
		positive(lock.playerClearance) and positive(lock.targetClearance),
		"lock.playerClearance and lock.targetClearance must be positive half widths in studs"
	)
	local maxOrbit = lock.maxOrbitDegrees
	check(
		positive(maxOrbit) and maxOrbit <= 90,
		"lock.maxOrbitDegrees must be in (0, 90]: past a quarter turn the split between the fighters stops growing with the swing"
	)
	check(
		typeof(lock.sideHysteresis) == "number"
			and lock.sideHysteresis >= 0
			and positive(maxOrbit)
			and lock.sideHysteresis < maxOrbit,
		"lock.sideHysteresis must be in [0, maxOrbitDegrees)"
	)
	check(count(lock.solveSteps), "lock.solveSteps must be a whole number of bisection steps, at least 1")
	check(positive(lock.blendLag), "lock.blendLag must be a positive number of seconds")
	-- Close fights (F3): the shot is fully close at closeGap, not at all from openGap.
	check(
		positive(lock.closeGap) and positive(lock.openGap) and lock.closeGap < lock.openGap,
		"lock.closeGap must be positive and below lock.openGap: the close shot eases out between them"
	)
	check(
		positive(lock.closeSwingDegrees) and lock.closeSwingDegrees <= 90,
		"lock.closeSwingDegrees must be in (0, 90]: a three-quarter view, never past a quarter turn"
	)
	check(positive(lock.closeHeight), "lock.closeHeight must be a positive number of studs above the player's root")
	check(
		positive(lock.maxTurnDegreesPerSecond),
		"lock.maxTurnDegreesPerSecond must be a positive cap on the bearing's turn (degrees per second)"
	)
	check(
		positive(lock.aimDepthFraction) and lock.aimDepthFraction <= 1,
		"lock.aimDepthFraction must be in (0, 1]: the aim never comes nearer the lens than that much of the player's depth"
	)
	-- The catch-up (a rush pass): a lifted cap, never a lower one, eased on and off.
	check(
		positive(lock.catchUpDegreesPerSecond)
			and positive(lock.maxTurnDegreesPerSecond)
			and lock.catchUpDegreesPerSecond >= lock.maxTurnDegreesPerSecond,
		"lock.catchUpDegreesPerSecond must be at least lock.maxTurnDegreesPerSecond: the catch-up lifts the turn cap, never lowers it"
	)
	check(
		positive(lock.catchUpMostDegrees),
		"lock.catchUpMostDegrees must be a positive number of degrees: the most the catch-up turns in one long frame"
	)
	check(
		typeof(lock.catchUpMargin) == "number" and lock.catchUpMargin >= 0 and lock.catchUpMargin < math.huge,
		"lock.catchUpMargin must be 0 or more: the share of the half width past the screen's side before the catch-up starts"
	)
	check(
		positive(lock.catchUpEase),
		"lock.catchUpEase must be a positive number of seconds: the catch-up eases on and off, never pops"
	)
	-- A death's still shot (F4, D-239) and the wall at the shoulder.
	check(
		typeof(lock.riseHoldSeconds) == "number" and lock.riseHoldSeconds >= 0 and lock.riseHoldSeconds < math.huge,
		"lock.riseHoldSeconds must be 0 or more seconds: how long the death's still shot stays after the freeze"
	)
	check(
		positive(lock.wallBlockedFraction) and lock.wallBlockedFraction <= 1,
		"lock.wallBlockedFraction must be in (0, 1]: the share of the camera's reach a wall leaves before the shot swings over"
	)
	check(
		typeof(lock.wallGainFraction) == "number" and lock.wallGainFraction >= 0 and lock.wallGainFraction <= 1,
		"lock.wallGainFraction must be in [0, 1]: how much more of its reach the other shoulder must open"
	)
	local RigBuilder = ctx.load("src/server/world/RigBuilder")
	check(
		lock.footprintPart == RigBuilder.BLOCKER_NAME,
		("lock.footprintPart '%s' must be RigBuilder's blocker name '%s': the close gap is measured to the body's footprint"):format(
			tostring(lock.footprintPart),
			tostring(RigBuilder.BLOCKER_NAME)
		)
	)
	local leash: any = if typeof(camera.follow.leash) == "table" then camera.follow.leash else nil
	check(leash ~= nil, "follow.leash is missing (closer and further)")
	if leash ~= nil then
		check(
			positive(leash.closer) and positive(leash.further),
			"follow.leash.closer and follow.leash.further must be positive studs"
		)
		if positive(leash.closer) then
			check(
				leash.closer >= camera.nudge.studs,
				("follow.leash.closer %.2f must be at least nudge.studs (%.2f): the leash would clip a hit's nudge"):format(
					leash.closer,
					camera.nudge.studs
				)
			)
		end
	end
	local seeThrough = camera.collision.seeThrough
	check(
		positive(seeThrough) and seeThrough <= 1,
		"collision.seeThrough must be in (0, 1]: parts at least this transparent never block the view"
	)
	check(count(camera.collision.maxPasses), "collision.maxPasses must be a whole number of casts, at least 1")

	check(camera.mobile.distanceMultiplier >= 1, "mobile defaults must be at least as wide as desktop")
	check(
		camera.collision.probeRadius > 0 and camera.collision.minDistance > 0,
		"collision probe numbers must be positive"
	)
	check(camera.collision.pullOutLag > 0, "collision.pullOutLag must be positive")
	check(
		camera.input.mouseDegreesPerPixel > 0 and camera.input.gamepadDegreesPerSecond > 0,
		"look sensitivities must be positive"
	)
	check(camera.input.gamepadDeadzone >= 0 and camera.input.gamepadDeadzone < 1, "gamepad deadzone must be in [0, 1)")
	check(camera.scripted.blendOut > 0, "scripted.blendOut must be positive")
	check(camera.epsilon > 0 and camera.epsilon < 0.001, "epsilon must be a small positive number")

	-- The punch (the push in on the big hit): a few degrees, landing inside its tier's hit-stop,
	-- eased in and sprung back, short.
	local punch = camera.punch
	check(typeof(punch) == "table", "punch is missing (Final and Kill rows)")
	if typeof(punch) == "table" then
		local CameraMath = ctx.load("src/client/camera/CameraMath")
		local function isNumber(value: any): boolean
			return typeof(value) == "number" and value == value
		end
		for _, kind in { "Final", "Kill" } do
			check(typeof(punch[kind]) == "table", ("punch.%s is missing"):format(kind))
		end
		for kind, row in punch do
			local label = "punch." .. tostring(kind)
			if typeof(row) ~= "table" then
				check(false, label .. " must be a table")
				continue
			end
			local frames = combat.hitStopFrames[kind]
			check(frames ~= nil, label .. " must be named by a hit-stop tier (combat.hitStopFrames)")
			local fields = { "degrees", "attack", "settle", "damping", "band" }
			local complete = true
			for _, field in fields do
				if not isNumber(row[field]) then
					check(false, ("%s.%s must be a number"):format(label, field))
					complete = false
				end
			end
			if not complete then
				continue
			end
			check(
				row.degrees > 0 and row.degrees <= camera.fov.artKick,
				label .. ".degrees must be a few degrees: positive and at most the Art kick (fov.artKick)"
			)
			if frames ~= nil then
				local hold = frames * combat.hitStopFrameSeconds
				check(
					row.attack > 0 and row.attack <= hold + 1e-9,
					("%s.attack must be positive and land inside the %s hit-stop (%.4f s)"):format(label, kind, hold)
				)
			end
			check(row.settle > 0, label .. ".settle must be positive")
			check(row.attack + row.settle <= 1, label .. " must be short: attack + settle at most 1 s")
			check(
				row.damping > 0 and row.damping < 1,
				label .. ".damping must be in (0, 1): a spring that swings back past rest, never a linear return"
			)
			check(row.band > 0 and row.band <= 0.1, label .. ".band must be in (0, 0.1]")
			if row.degrees <= 0 or row.attack <= 0 or row.settle <= 0 or row.damping <= 0 or row.damping >= 1 then
				continue
			end

			-- The curve itself, sampled at 240 Hz.
			local step = 1 / 240
			local total = CameraMath.punchSeconds(row)
			local first = CameraMath.punchOffset(0, row)
			check(math.abs(first) < 1e-9, label .. " must start at rest")
			local atPeak = CameraMath.punchOffset(row.attack, row)
			check(
				math.abs(atPeak + row.degrees) <= row.degrees * 0.01,
				label .. " must reach -degrees at the end of the attack"
			)
			local half = CameraMath.punchOffset(row.attack * 0.5, row)
			check(
				-half > row.degrees * 0.5 + 1e-6,
				label .. " must ease in (past the linear midpoint half way through the attack), never linear"
			)
			local narrowest, widest, tail = 0, 0, 0
			local t = 0
			while t < total - step do
				local offset, done = CameraMath.punchOffset(t, row)
				check(not done, label .. " ended before attack + settle")
				narrowest = math.min(narrowest, offset)
				widest = math.max(widest, offset)
				tail = offset
				t += step
			end
			check(narrowest >= -row.degrees * 1.001, label .. " must never narrow past its degrees")
			check(widest > 0, label .. " must spring back past rest before it settles")
			check(widest <= row.degrees * 0.25, label .. " must overshoot rest by at most a quarter of its degrees")
			check(
				math.abs(tail) <= row.degrees * row.band * 1.5,
				label .. " must be settled (inside band) when it ends, so dropping it never pops"
			)
			local _, over = CameraMath.punchOffset(total, row)
			check(over, label .. " must report done at attack + settle")
		end
		if typeof(punch.Final) == "table" and typeof(punch.Kill) == "table" then
			local final, kill = punch.Final, punch.Kill
			if isNumber(final.degrees) and isNumber(kill.degrees) then
				check(kill.degrees >= final.degrees, "punch.Kill must push in at least as far as punch.Final")
			end
		end
	end

	-- Render stalls: the springs CameraController steps, with the damping it gives each.
	local stall = camera.stall
	check(typeof(stall) == "table", "stall is missing (maxStepSeconds and settleSeconds)")
	if typeof(stall) == "table" then
		local complete = true
		for _, field in { "maxStepSeconds", "settleSeconds" } do
			local value = stall[field]
			if typeof(value) ~= "number" or value ~= value or value <= 0 then
				check(false, ("stall.%s must be a positive number"):format(field))
				complete = false
			end
		end
		if complete then
			local Spring = ctx.load("src/shared/util/Spring")
			local CameraMath = ctx.load("src/client/camera/CameraMath")
			local springs = {
				{ name = "follow", lag = camera.follow.lag, damping = camera.follow.damping },
				{ name = "fov", lag = camera.fov.lag, damping = camera.fov.damping },
				{ name = "lock yaw", lag = camera.lock.yawLag, damping = camera.follow.damping },
				{ name = "lock blend", lag = camera.lock.blendLag, damping = camera.follow.damping },
				{ name = "collision pull-out", lag = camera.collision.pullOutLag, damping = camera.follow.damping },
			}
			local piece, settle = stall.maxStepSeconds, stall.settleSeconds
			check(
				piece >= FRAME_SECONDS - 1e-9,
				("stall.maxStepSeconds %.4f s must be at least one 60 fps frame (%.4f s): a shorter piece cuts every frame up"):format(
					piece,
					FRAME_SECONDS
				)
			)
			for _, row in springs do
				if typeof(row.lag) ~= "number" or row.lag <= 0 or typeof(row.damping) ~= "number" then
					continue
				end
				-- One step of Spring.Step on (displacement, velocity / omega) with h = omega x piece:
				-- [[1 - h^2, h (1 - 2 zeta h)], [-h, 1 - 2 zeta h]]. It neither rings nor blows up
				-- while both eigenvalues are real and in [0, 1).
				local h = piece / row.lag
				local trace = 2 - h * h - 2 * row.damping * h
				local det = 1 - 2 * row.damping * h
				local disc = trace * trace - 4 * det
				local calm = disc >= 0 and det >= 0 and trace >= 0 and (trace + math.sqrt(math.max(disc, 0))) / 2 < 1
				check(
					calm,
					("stall.maxStepSeconds %.4f s is too long a piece for the %s spring (lag %.3f s, damping %.2f): omega x step %.3f makes its step ring or blow up"):format(
						piece,
						row.name,
						row.lag,
						row.damping,
						h
					)
				)
				-- Where the spring is when the snap takes over: released from a unit gap at rest.
				local spring = Spring.new(1, CameraMath.springFromLag(row.lag), row.damping)
				spring.target = 0
				local dt = math.min(piece, FRAME_SECONDS)
				local t, off = 0, 0
				while t < settle * 2 do
					spring:Step(dt)
					t += dt
					if t >= settle then
						off = math.max(off, math.abs(spring.position))
					end
				end
				check(
					off <= SETTLE_BAND,
					("stall.settleSeconds %.2f s is too soon for the %s spring (lag %.3f s): it is still %.1f%% off its target, past %.1f%%"):format(
						settle,
						row.name,
						row.lag,
						off * 100,
						SETTLE_BAND * 100
					)
				)
			end
			local pieces = math.ceil(settle / piece - 1e-9)
			check(
				pieces <= MAX_PIECES,
				("stall.settleSeconds %.2f s cuts one frame into %d pieces, past %d"):format(settle, pieces, MAX_PIECES)
			)
		end
	end

	return problems
end
