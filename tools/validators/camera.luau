--!strict
--[[
	Validates src/shared/data/camera.luau against section 10: the follow lag, rest FOV, kicks,
	nudge and shake tiers, the three orbit presets (Duel low and tight, Raid high and wide), sane
	pitch and zoom limits, lock-on distances and the shake noise lanes.
]]

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

	return problems
end
