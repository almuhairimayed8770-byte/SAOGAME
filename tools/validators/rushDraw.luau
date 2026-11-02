--!strict
--[[
	Validates the drawn rush's pass and its skid's dust.

	choreo.luau enemy.rush.detachBody (D-531) is a boolean: whether a drawn rush draws the body's
	Torso itself, off the replicated root's physics move, or through the root joint.

	choreo.luau enemy.rush.teleportStuds (D-553) is positive studs over the Charger's whole rush
	travel (ai.luau chargeSpeed) in a throttled 0.1 s frame: a root's move other than forward down
	the path that a run can show (all of a long frame's travel sideways, the path not yet told
	turned) never reads as a placement.

	choreo.luau enemy.rush.settleRestSpeed (D-602) is positive studs a second under the slowest a
	landing root moves before the server stops it dead (ai.luau movement.landSlackStuds over
	landFrames 60 Hz server frames, 0.6): a late root the server still lands never reads at rest, so
	the hand-back waits for it.

	choreo.luau enemy.rush.settleRestSeconds (D-648) is positive seconds over two of the longest
	rows a rush is drawn on (a 30 fps row of up to 0.035 s, item 527) and under settleSeconds: a row
	or two on which the replicated root did not move never reads as its rest, and the wait it adds
	stays inside the hand-back's.

	choreo.luau enemy.rush.pass (RushDraw's swing past a player's body in its path, D-167):
	- leadStuds, fullStuds and returnStuds are positive studs; marginStuds and centreStuds are
	  studs at least 0.
	- leadStuds is under fullStuds: for a body square on the line the swing is less than half done
	  (smoothstep of lead / (lead + full)) when the snout meets it, so the snout still meets it.
	- centreStuds is at most half combat.luau's strikeLineWidth: the band a body is passed on the
	  rusher's right is inside the line the strike resolves.

	fx.luau rushSkid (the skid's dust, RushDraw.takeDust and WallSlam.skid):
	- everyStuds is positive studs; rearShare is a share in [0, 1] of the body's back.
	- particles is a positive whole number, no more than a slam's (fx.wallSlam.particles).
	- It is dust, never light: lightEmission 0 (no flash budget), and token is a palette token.
	- lifetime, speed, size and transparency are ordered ranges (min <= max, birth > 0), the
	  transparency within [0, 1]; spreadAngle within [0, 180] degrees; drag, gravity, rotation and
	  rotSpeed at least 0; emitterSize positive; folderName a name of its own (not the slam's).
]]

-- The longest frame a run is judged on short of a stall (ai.luau's rushWorld rules name a throttled
-- 0.1 s frame too).
local THROTTLED_FRAME_SECONDS = 0.1
-- The server's frame a landing is paced on (its Heartbeat at 60 Hz, EnemyService's landStep).
local SERVER_FRAME_SECONDS = 1 / 60
-- The longest row a rush is judged on: DevFrameCap 30's rows of 1/30 and 0.0349 s (item 527).
local LONGEST_ROW_SECONDS = 0.035

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function positive(value: any): boolean
	return finite(value) and value > 0
end

local function atLeastZero(value: any): boolean
	return finite(value) and value >= 0
end

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "rushDraw: " .. message)
		end
	end

	local choreo = ctx.load("src/shared/data/choreo")
	local combat = ctx.load("src/shared/data/combat")
	local fx = ctx.load("src/shared/data/fx")
	local palette = ctx.load("src/shared/data/palette")

	local rush = if typeof(choreo.enemy) == "table" then choreo.enemy.rush else nil
	check(
		typeof(rush) == "table" and typeof(rush.detachBody) == "boolean",
		"choreo enemy.rush.detachBody must be a boolean (whether a drawn rush draws the Torso off the root's physics)"
	)
	local ai = ctx.load("src/shared/data/ai")
	local teleport = if typeof(rush) == "table" then rush.teleportStuds else nil
	check(positive(teleport), "choreo enemy.rush.teleportStuds must be a positive number of studs")
	local charger = if typeof(ai.archetypes) == "table" then ai.archetypes.Charger else nil
	local speed = if typeof(charger) == "table" then charger.chargeSpeed else nil
	if positive(teleport) and positive(speed) then
		check(
			teleport > speed * THROTTLED_FRAME_SECONDS,
			("enemy.rush.teleportStuds %.2f must be over a throttled %.1f s frame of the rush (%.2f studs at chargeSpeed %g): a run's own move would read as a placement"):format(
				teleport,
				THROTTLED_FRAME_SECONDS,
				speed * THROTTLED_FRAME_SECONDS,
				speed
			)
		)
	end
	local restSpeed = if typeof(rush) == "table" then rush.settleRestSpeed else nil
	check(positive(restSpeed), "choreo enemy.rush.settleRestSpeed must be a positive number of studs a second")
	local movement = ai.movement
	if
		positive(restSpeed)
		and typeof(movement) == "table"
		and positive(movement.landSlackStuds)
		and positive(movement.landFrames)
	then
		local slowest = movement.landSlackStuds / (movement.landFrames * SERVER_FRAME_SECONDS)
		check(
			restSpeed < slowest,
			("enemy.rush.settleRestSpeed %.2f must be under %.2f studs a second, the slowest a landing root moves (landSlackStuds %.3f over landFrames %g of a 60 Hz server frame): a root still landing would read at rest"):format(
				restSpeed,
				slowest,
				movement.landSlackStuds,
				movement.landFrames
			)
		)
	end
	local restSeconds = if typeof(rush) == "table" then rush.settleRestSeconds else nil
	check(positive(restSeconds), "choreo enemy.rush.settleRestSeconds must be a positive number of seconds")
	if positive(restSeconds) then
		check(
			restSeconds >= 2 * LONGEST_ROW_SECONDS,
			("enemy.rush.settleRestSeconds %.3f must be at least two of the longest rows (2 x %.3f s): a row on which the late root did not move would read as its rest"):format(
				restSeconds,
				LONGEST_ROW_SECONDS
			)
		)
		local settle = if typeof(rush) == "table" then rush.settleSeconds else nil
		if positive(settle) then
			check(
				restSeconds < settle,
				("enemy.rush.settleRestSeconds %.3f must be under settleSeconds %.3f: the wait for a root at rest stays inside the hand-back's"):format(
					restSeconds,
					settle
				)
			)
		end
	end
	local pass = if typeof(rush) == "table" then rush.pass else nil
	if typeof(pass) ~= "table" then
		check(false, "choreo enemy.rush.pass is missing (the drawn rush's swing past a player's body)")
	else
		for _, key in { "leadStuds", "fullStuds", "returnStuds" } do
			check(positive(pass[key]), ("enemy.rush.pass.%s must be a positive number of studs"):format(key))
		end
		for _, key in { "marginStuds", "centreStuds" } do
			check(atLeastZero(pass[key]), ("enemy.rush.pass.%s must be a number of studs at least 0"):format(key))
		end
		if positive(pass.leadStuds) and positive(pass.fullStuds) then
			check(
				pass.leadStuds < pass.fullStuds,
				("enemy.rush.pass.leadStuds %.2f must be under fullStuds %.2f: the swing is less than half done when the snout meets a body on the line"):format(
					pass.leadStuds,
					pass.fullStuds
				)
			)
		end
		local width = combat.strikeLineWidth
		if atLeastZero(pass.centreStuds) and positive(width) then
			check(
				pass.centreStuds <= width / 2,
				("enemy.rush.pass.centreStuds %.2f is wider than half the strike line (%.2f)"):format(
					pass.centreStuds,
					width / 2
				)
			)
		end
	end

	local skid = fx.rushSkid
	if typeof(skid) ~= "table" then
		check(false, "fx rushSkid is missing (the dust a rush's skid kicks up)")
		return problems
	end
	check(positive(skid.everyStuds), "rushSkid.everyStuds must be a positive number of studs")
	check(
		finite(skid.rearShare) and skid.rearShare >= 0 and skid.rearShare <= 1,
		"rushSkid.rearShare must be a share in [0, 1] of the body's back"
	)
	local particles = skid.particles
	check(
		positive(particles) and math.floor(particles) == particles,
		"rushSkid.particles must be a positive whole number"
	)
	local slam = fx.wallSlam
	if positive(particles) and typeof(slam) == "table" and positive(slam.particles) then
		check(
			particles <= slam.particles,
			("rushSkid.particles %g is more than a slam's (%g)"):format(particles, slam.particles)
		)
	end
	check(skid.lightEmission == 0, "rushSkid.lightEmission must be 0: dust, never light (no flash budget)")
	check(
		typeof(skid.token) == "string" and palette.tokens[skid.token] ~= nil,
		("rushSkid.token '%s' is not a palette token"):format(tostring(skid.token))
	)
	local function range(name: string, low: string, high: string, ok: (any) -> boolean)
		local row = skid[name]
		if typeof(row) ~= "table" or not ok(row[low]) or not ok(row[high]) then
			check(false, ("rushSkid.%s needs %s and %s"):format(name, low, high))
			return
		end
		check(row[low] <= row[high], ("rushSkid.%s.%s is over %s"):format(name, low, high))
	end
	range("lifetime", "min", "max", positive)
	range("speed", "min", "max", atLeastZero)
	range("size", "birth", "death", positive)
	local fade = skid.transparency
	check(
		typeof(fade) == "table"
			and atLeastZero(fade.birth)
			and atLeastZero(fade.death)
			and fade.birth <= 1
			and fade.death <= 1,
		"rushSkid.transparency birth and death must be within [0, 1]"
	)
	check(
		atLeastZero(skid.spreadAngle) and skid.spreadAngle <= 180,
		"rushSkid.spreadAngle must be within [0, 180] degrees"
	)
	for _, key in { "drag", "gravity", "rotation", "rotSpeed" } do
		check(atLeastZero(skid[key]), ("rushSkid.%s must be a number at least 0"):format(key))
	end
	check(positive(skid.emitterSize), "rushSkid.emitterSize must be a positive number of studs")
	check(
		typeof(skid.folderName) == "string"
			and skid.folderName ~= ""
			and (typeof(slam) ~= "table" or skid.folderName ~= slam.folderName),
		"rushSkid.folderName must be a folder name of its own"
	)

	return problems
end
