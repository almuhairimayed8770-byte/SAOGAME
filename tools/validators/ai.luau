--!strict
--[[
	Validates src/shared/data/ai.luau: the shape of every tuning table, the section 16 rates
	matching enemies.rules, every Charger row's line covered by chargeSpeed * strike, material
	costs that PathfindingService accepts (positive numbers keyed by material name), and attack
	weights that name attacks which exist in enemies.luau. The hit-stop pause cap holds at least
	one Final hit-stop (D-168), and the fighter collision groups are four distinct names other than
	Default whose `apart` pairs name only them or Default and let a rush pass the players (D-167); a
	stopped rush turns solid after longer than the clients' draw lag and before its recovery ends
	(D-190); a rush's line keeps up with its body by less than the lag that reads as a jam (D-195).
	An enemy's blocker (D-198) collides with players, with other enemies and their blockers (D-281)
	and with nothing else (not the world, not a rush), a standing enemy's root no longer collides with players,
	and blockerHeight reaches above the top of every enemy rig's root. How a rush meets the world
	(rushWorld, D-205 to D-209): positive numbers, a glance below 90 degrees, a look ahead at least a
	sidestep's run, a sidestep that fits its run, at least three legs, the server's leg turn equal to
	the drawn one (choreo enemy.rush.turnRate), a daze no shorter than a parry's stagger, and a
	climbable riser below every Charger rig's hip. A rush's dead stop leads by at most one AI tick,
	and a walking body's snout slack in a wall stays below a rush's corner margin (D-278, D-279); a
	rush's landing paces over at least one frame, ends within less than that margin of its stop and
	lasts long enough to land the fastest Charger rush from its lead (D-525), and its MoveTo aims
	past its stop by more than the Humanoid's MoveTo tolerance plus that lead (D-548); a
	blocked step tells running from blocked and is told before the jam lag (D-280). Every enemy
	Humanoid keeps out of FallingDown and only ever out of fall states (upright.offStates, D-494);
	each client's copy stands up to Running or GettingUp, retries a whole number of steps and logs
	under three distinct names the server never publishes (upright.client, D-523), turns off at
	least the server's fall states, says whether it is asked at its Humanoid's arrival, and stands
	a fallen copy up by one of its two named rescues (D-543, D-544).
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local ARCHETYPE_FIELDS = {
	"turnRate",
	"windUpTurnRate",
	"strikeTurnRate",
	"recoverTurnRate",
	"attackCooldown",
	"chaseSpeedMultiplier",
	"engageFraction",
	"engageAngle",
}

local CHARGER_FIELDS = {
	"minChargeDistance",
	"maxChargeDistance",
	"circleDistance",
	"circleOutwardBias",
	"lineUpToleranceDegrees",
	"lineUpLooseToleranceDegrees",
	"lineUpTimeout",
	"chargeSpeed",
	"overshoot",
	"wheelAngle",
	"wheelSpeedMultiplier",
	"jamLagStuds",
	"keepUpStuds",
	"runningFraction",
	"blockedFraction",
	"blockedSeconds",
}

local function validate(ctx: Context): { string }
	local problems: { string } = {}
	local AI = ctx.load("src/shared/data/ai")
	local Enemies = ctx.load("src/shared/data/enemies")

	local function problem(message: string)
		table.insert(problems, "ai: " .. message)
	end

	local function positiveNumber(value: any, name: string, allowZero: boolean?)
		if typeof(value) ~= "number" or value ~= value then
			problem(("%s must be a number, got %s"):format(name, typeof(value)))
		elseif value < 0 or (value == 0 and not allowZero) then
			problem(
				("%s must be %s, got %s"):format(
					name,
					if allowZero then "zero or positive" else "positive",
					tostring(value)
				)
			)
		end
	end

	if AI.tickHz ~= Enemies.rules.aiTickHz then
		problem("tickHz must equal enemies.rules.aiTickHz")
	end
	if AI.bossTickHz ~= Enemies.rules.bossTickHz then
		problem("bossTickHz must equal enemies.rules.bossTickHz")
	end
	if AI.sleepRadius ~= Enemies.rules.simulateRadius then
		problem("sleepRadius must equal enemies.rules.simulateRadius")
	end
	if AI.pathfindPastStuds ~= Enemies.rules.pathfindBeyondStuds then
		problem("pathfindPastStuds must equal enemies.rules.pathfindBeyondStuds")
	end
	positiveNumber(AI.maxTicksPerFrame, "maxTicksPerFrame")
	positiveNumber(AI.sleepCheckInterval, "sleepCheckInterval")

	for _, group in { "perception", "leash", "movement", "interrupt", "attack", "telegraph" } do
		if typeof(AI[group]) ~= "table" then
			problem(("%s must be a table"):format(group))
		end
	end

	-- A blow shown before the server's word (D-258): never on a state that defends, so a guard, a
	-- parry or a dodge is never drawn as a hit first.
	local strike = AI.strikePrediction
	if typeof(strike) ~= "table" then
		problem("strikePrediction must be a table")
	else
		if typeof(strike.enabled) ~= "boolean" then
			problem("strikePrediction.enabled must be a boolean")
		end
		if typeof(strike.exposedStates) ~= "table" then
			problem("strikePrediction.exposedStates must be a table")
		else
			for _, defended in { "Guard", "Dodge", "Stagger", "GuardBroken", "Dead" } do
				if strike.exposedStates[defended] ~= nil then
					problem(("strikePrediction.exposedStates must not hold %s"):format(defended))
				end
			end
		end
		for _, field in
			{
				"defenceGraceSeconds",
				"marginStuds",
				"marginDegrees",
				"lateSeconds",
				"confirmSeconds",
				"takeBackBlendOut",
			}
		do
			positiveNumber(strike[field], "strikePrediction." .. field)
		end
		if typeof(strike.marginDegrees) == "number" and strike.marginDegrees >= 90 then
			problem("strikePrediction.marginDegrees must be below 90")
		end
	end

	-- D-259: room between enemies.
	local spacing = AI.spacing
	if typeof(spacing) ~= "table" then
		problem("spacing must be a table")
	else
		for _, field in { "gapStuds", "slideStuds", "slideMinStuds", "stepStuds", "stepSpeedMultiplier" } do
			positiveNumber(spacing[field], "spacing." .. field)
		end
		local passes = spacing.standOffPasses
		if typeof(passes) ~= "number" or passes < 1 or passes % 1 ~= 0 then
			problem("spacing.standOffPasses must be a whole number of at least 1")
		end
		if typeof(spacing.stepSpeedMultiplier) == "number" and spacing.stepSpeedMultiplier > 1 then
			problem("spacing.stepSpeedMultiplier must be at most 1 (a step aside is never faster than a walk)")
		end
		local movement = AI.movement
		if
			typeof(spacing.slideMinStuds) == "number"
			and typeof(movement) == "table"
			and typeof(movement.moveAheadStuds) == "number"
			and spacing.slideMinStuds > movement.moveAheadStuds
		then
			problem("spacing.slideMinStuds must be at most movement.moveAheadStuds (the slide's longest walk)")
		end
		if typeof(spacing.freePhases) ~= "table" then
			problem("spacing.freePhases must be a table")
		else
			-- A body mid-attack, staggered or dead stays where it is: its strike resolves from there.
			for _, busy in { "WindUp", "Strike", "Recover", "Interrupted", "Dead" } do
				if spacing.freePhases[busy] ~= nil then
					problem(("spacing.freePhases must not hold %s"):format(busy))
				end
			end
		end
	end

	if typeof(AI.archetypes) ~= "table" then
		problem("archetypes must be a table")
		return problems
	end
	for _, name in { "Charger", "Brute", "Default" } do
		if AI.archetypes[name] == nil then
			problem(("archetypes.%s is missing"):format(name))
		end
	end
	for name, tuning in AI.archetypes do
		for _, field in ARCHETYPE_FIELDS do
			local allowZero = field == "windUpTurnRate" or field == "strikeTurnRate" or field == "attackCooldown"
			positiveNumber(tuning[field], ("archetypes.%s.%s"):format(name, field), allowZero)
		end
		if typeof(tuning.engageFraction) == "number" and tuning.engageFraction > 1 then
			problem(("archetypes.%s.engageFraction must be at most 1"):format(name))
		end
		if typeof(tuning.engageAngle) == "number" and tuning.engageAngle > 180 then
			problem(("archetypes.%s.engageAngle must be at most 180"):format(name))
		end
	end

	local charger = AI.archetypes.Charger
	if charger ~= nil then
		for _, field in CHARGER_FIELDS do
			positiveNumber(charger[field], "archetypes.Charger." .. field, field == "circleOutwardBias")
		end
		if charger.minChargeDistance >= charger.maxChargeDistance then
			problem("archetypes.Charger.minChargeDistance must be below maxChargeDistance")
		end
		if charger.circleDistance <= charger.minChargeDistance then
			problem("archetypes.Charger.circleDistance must be above minChargeDistance (hysteresis)")
		end
		if charger.lineUpToleranceDegrees > charger.lineUpLooseToleranceDegrees then
			problem("archetypes.Charger.lineUpToleranceDegrees must not exceed the loose tolerance")
		end
		if
			typeof(charger.keepUpStuds) == "number"
			and typeof(charger.jamLagStuds) == "number"
			and charger.keepUpStuds >= charger.jamLagStuds
		then
			problem(
				"archetypes.Charger.keepUpStuds must be below jamLagStuds (a jam is further behind than keeping up)"
			)
		end
		-- A blocked step (D-280): a pass that shows the body running is never one that shows it
		-- blocked, and the blocked time is told before the body could fall jamLagStuds behind.
		local running, blockedShare = charger.runningFraction, charger.blockedFraction
		if typeof(running) == "number" and running > 1 then
			problem("archetypes.Charger.runningFraction must be at most 1")
		end
		if typeof(running) == "number" and typeof(blockedShare) == "number" and blockedShare >= running then
			problem("archetypes.Charger.blockedFraction must be below runningFraction")
		end
		local blockedSeconds = charger.blockedSeconds
		if
			typeof(blockedSeconds) == "number"
			and typeof(charger.jamLagStuds) == "number"
			and typeof(charger.chargeSpeed) == "number"
			and charger.chargeSpeed > 0
			and blockedSeconds >= charger.jamLagStuds / charger.chargeSpeed
		then
			problem(
				("archetypes.Charger.blockedSeconds %s must be shorter than jamLagStuds / chargeSpeed (%.3f s)"):format(
					tostring(blockedSeconds),
					charger.jamLagStuds / charger.chargeSpeed
				)
			)
		end
		for _, def in Enemies.list() do
			if def.archetype == "Charger" then
				for _, attack in def.attacks do
					if attack.groundShape == "Line" and AI.rushSpeed(attack) * attack.strike < attack.reach - 1e-9 then
						problem(
							("%s.%s: rushSpeed %s * strike %s does not cover reach %s"):format(
								def.id,
								attack.id,
								tostring(AI.rushSpeed(attack)),
								tostring(attack.strike),
								tostring(attack.reach)
							)
						)
					end
				end
				if charger.maxChargeDistance >= def.aggroRange then
					problem(
						("%s: aggroRange %s must exceed maxChargeDistance"):format(def.id, tostring(def.aggroRange))
					)
				end
				local lineUp = AI.chargerLineUpDistance(def.moveSpeed)
				if lineUp < charger.minChargeDistance then
					problem(
						("%s: wheeling at moveSpeed %s from circleDistance lines up at %.1f studs, inside minChargeDistance %s"):format(
							def.id,
							tostring(def.moveSpeed),
							lineUp,
							tostring(charger.minChargeDistance)
						)
					)
				end
			end
		end
	end

	local brute = AI.archetypes.Brute
	if brute ~= nil then
		positiveNumber(brute.stopDistance, "archetypes.Brute.stopDistance")
	end

	if typeof(AI.movement) == "table" and typeof(AI.movement.materialCosts) == "table" then
		for material, cost in AI.movement.materialCosts do
			if typeof(material) ~= "string" then
				problem("movement.materialCosts keys must be material names")
			end
			positiveNumber(cost, ("movement.materialCosts.%s"):format(tostring(material)))
		end
	else
		problem("movement.materialCosts must be a table")
	end
	if typeof(AI.movement) == "table" then
		-- A rush's dead stop (D-279) takes the next frame to come within a tick at most, so a stop
		-- point is never reached more than a tick's run early.
		local lead = AI.movement.haltLeadSeconds
		positiveNumber(lead, "movement.haltLeadSeconds")
		if typeof(lead) == "number" and lead > AI.tickSeconds() + 1e-9 then
			problem(
				("movement.haltLeadSeconds %s must be at most one AI tick (%s s)"):format(
					tostring(lead),
					tostring(AI.tickSeconds())
				)
			)
		end
		-- A walk's snout stands in a wall by a hair at most (D-278): less than the margin a rush keeps
		-- off a corner it clips past.
		local slack = AI.movement.snoutSlackStuds
		positiveNumber(slack, "movement.snoutSlackStuds", true)
		local margin = if typeof(AI.rushWorld) == "table" then AI.rushWorld.clipMarginStuds else nil
		if typeof(slack) == "number" and typeof(margin) == "number" and slack >= margin then
			problem(
				("movement.snoutSlackStuds %s must be below rushWorld.clipMarginStuds (%s)"):format(
					tostring(slack),
					tostring(margin)
				)
			)
		end
		-- A rush's landing (D-525): each frame's pace covers what is left over at least one frame,
		-- so the next frame never comes after the body has passed its stop; it ends a hair short of
		-- its stop, as a walk's snout stands a hair in a wall; and it lasts long enough to land the
		-- fastest rush from its lead (its speed times haltLeadSeconds) to within landSlackStuds on
		-- frames as slow as haltLeadSeconds, each covering 1 / landFrames of what is left.
		local frames = AI.movement.landFrames
		local landSlack = AI.movement.landSlackStuds
		local landMost = AI.movement.landMaxSeconds
		positiveNumber(frames, "movement.landFrames")
		positiveNumber(landSlack, "movement.landSlackStuds")
		positiveNumber(landMost, "movement.landMaxSeconds")
		if typeof(frames) == "number" and frames > 0 and frames < 1 then
			problem(("movement.landFrames %s must be at least 1"):format(tostring(frames)))
		end
		if typeof(landSlack) == "number" and typeof(margin) == "number" and landSlack > 0 and landSlack >= margin then
			problem(
				("movement.landSlackStuds %s must be below rushWorld.clipMarginStuds (%s)"):format(
					tostring(landSlack),
					tostring(margin)
				)
			)
		end
		local fastest = 0
		for _, def in Enemies.list() do
			if def.archetype == "Charger" then
				for _, attack in def.attacks do
					if attack.arc == 0 or attack.groundShape == "Line" then
						fastest = math.max(fastest, AI.rushSpeed(attack))
					end
				end
			end
		end
		if
			typeof(frames) == "number"
			and frames >= 1
			and typeof(landSlack) == "number"
			and landSlack > 0
			and typeof(landMost) == "number"
			and typeof(lead) == "number"
			and lead > 0
			and fastest * lead > landSlack
		then
			local count = 1
			if frames > 1 then
				count = math.ceil(math.log(landSlack / (fastest * lead)) / math.log(1 - 1 / frames) - 1e-9)
			end
			local need = count * lead
			if landMost < need - 1e-9 then
				problem(
					("movement.landMaxSeconds %s must land the fastest rush (%s studs/s) from its lead within it (%.3f s)"):format(
						tostring(landMost),
						tostring(fastest),
						need
					)
				)
			end
		end
		-- The landing's MoveTo (D-548) aims past its stop by more than the Humanoid's MoveTo
		-- tolerance plus the fastest rush's lead, so no frame of the landing finds its goal inside
		-- the tolerance however far from the stop it began.
		local tolerance = AI.movement.moveToToleranceStuds
		local aim = AI.movement.landAimStuds
		positiveNumber(tolerance, "movement.moveToToleranceStuds")
		positiveNumber(aim, "movement.landAimStuds")
		if
			typeof(tolerance) == "number"
			and tolerance > 0
			and typeof(aim) == "number"
			and aim > 0
			and typeof(lead) == "number"
			and lead > 0
		then
			local need = tolerance + fastest * lead
			if aim <= need then
				problem(
					("movement.landAimStuds %s must be past moveToToleranceStuds plus the fastest rush's lead (%.3f)"):format(
						tostring(aim),
						need
					)
				)
			end
		end
	end

	if typeof(AI.attack) == "table" and typeof(AI.attack.weights) == "table" then
		local known: { [string]: boolean } = {}
		for _, def in Enemies.list() do
			for _, attack in def.attacks do
				known[attack.id] = true
			end
		end
		for _, attack in Enemies.eliteAttacks do
			known[attack.id] = true
		end
		for attackId, weight in AI.attack.weights do
			positiveNumber(weight, ("attack.weights.%s"):format(tostring(attackId)))
			if not known[attackId] then
				problem(("attack.weights.%s names an attack no enemy has"):format(tostring(attackId)))
			end
		end
		positiveNumber(AI.attack.defaultWeight, "attack.defaultWeight")
	end

	-- D-168: one Final hit-stop (the combo finisher's freeze) always fits inside the per-attack cap.
	local Combat = ctx.load("src/shared/data/combat")
	if typeof(AI.hitStop) ~= "table" then
		problem("hitStop must be a table")
	else
		local cap = AI.hitStop.maxPausePerAttack
		positiveNumber(cap, "hitStop.maxPausePerAttack")
		local final = Combat.hitStopFrames.Final * Combat.hitStopFrameSeconds
		if typeof(cap) == "number" and cap > 0 and cap < final - 1e-9 then
			problem(
				("hitStop.maxPausePerAttack %s is shorter than one Final hit-stop (%s s)"):format(
					tostring(cap),
					tostring(final)
				)
			)
		end
	end

	-- D-167: the fighter collision groups.
	local collision = AI.collision
	if typeof(collision) ~= "table" then
		problem("collision must be a table")
	else
		local names: { [string]: boolean } = {}
		local count = 0
		for _, field in { "players", "enemies", "rushing", "blockers" } do
			local name = collision[field]
			if typeof(name) ~= "string" or name == "" then
				problem(("collision.%s must be a group name"):format(field))
			elseif name == "Default" then
				problem(("collision.%s must not be the engine's Default group"):format(field))
			elseif not names[name] then
				names[name] = true
				count += 1
			end
		end
		if count ~= 4 then
			problem("collision groups must be four distinct names")
		end
		local passesPlayers = false
		local apartSet: { [string]: boolean } = {}
		if typeof(collision.apart) ~= "table" then
			problem("collision.apart must be a list of group pairs")
		else
			for _, pair in collision.apart do
				for _, name in { pair[1], pair[2] } do
					if not names[name] and name ~= "Default" then
						problem(
							("collision.apart names %s, which is neither a fighter group nor Default"):format(
								tostring(name)
							)
						)
					end
				end
				local a, b = tostring(pair[1]), tostring(pair[2])
				apartSet[a .. "|" .. b] = true
				apartSet[b .. "|" .. a] = true
				if
					(a == collision.rushing and b == collision.players)
					or (a == collision.players and b == collision.rushing)
				then
					passesPlayers = true
				end
			end
		end
		if not passesPlayers then
			problem("collision.apart must let the rushing group pass the players group")
		end
		-- D-198: the blocker is what a player bumps into; D-281: a solid enemy's whole footprint meets
		-- another's (its blocker, its root), so enemies never stand inside each other. It never meets
		-- the world (the body moves on the floor as before) nor a rush (D-167).
		local blockers = collision.blockers
		if typeof(blockers) == "string" then
			for _, key in { "players", "enemies", "blockers" } do
				if apartSet[blockers .. "|" .. tostring(collision[key])] then
					problem(("collision.apart must not keep the blockers group from the %s group"):format(key))
				end
			end
			for _, other in { "Default", collision.rushing } do
				if not apartSet[blockers .. "|" .. tostring(other)] then
					problem(("collision.apart must keep the blockers group from %s"):format(tostring(other)))
				end
			end
			if not apartSet[tostring(collision.enemies) .. "|" .. tostring(collision.players)] then
				problem("collision.apart must keep the enemies group from the players group (the blocker stands in)")
			end
		end
		local blockerHeight = collision.blockerHeight
		positiveNumber(blockerHeight, "collision.blockerHeight")
		if typeof(blockerHeight) == "number" then
			local Rigs = ctx.load("src/shared/data/rigs")
			for _, rigId in Enemies.rigIds() do
				local rig = Rigs[rigId]
				local parts = if rig ~= nil then rig.parts else nil
				local root = if parts ~= nil then parts[rig.rootPart] else nil
				if root ~= nil and blockerHeight <= rig.hipHeight + root.size[2] then
					problem(
						("collision.blockerHeight %s must reach above rig %s's root top (%s)"):format(
							tostring(blockerHeight),
							rigId,
							tostring(rig.hipHeight + root.size[2])
						)
					)
				end
			end
		end
		-- D-204: every slope a rushing root climbs is ground to the world casts, and a wall never is.
		local groundSlope = collision.groundSlopeDegrees
		positiveNumber(groundSlope, "collision.groundSlopeDegrees")
		if typeof(groundSlope) == "number" then
			if groundSlope >= 90 then
				problem(("collision.groundSlopeDegrees must be below 90, got %s"):format(tostring(groundSlope)))
			end
			local Rigs = ctx.load("src/shared/data/rigs")
			local checked: { [string]: boolean } = {}
			for _, def in Enemies.list() do
				local rig = if def.archetype == "Charger" then Rigs[def.skin] else nil
				local parts = if rig ~= nil then rig.parts else nil
				local root = if parts ~= nil then parts[rig.rootPart] else nil
				if root ~= nil and not checked[def.skin] then
					checked[def.skin] = true
					-- The slope the root's box first touches with its front edge.
					local climb = math.deg(math.atan(rig.hipHeight / (root.size[3] / 2)))
					if groundSlope < climb then
						problem(
							("collision.groundSlopeDegrees %s must be at least rig %s's climb (%.1f)"):format(
								tostring(groundSlope),
								def.skin,
								climb
							)
						)
					end
				end
			end
		end
		-- D-190: a stopped rush turns solid only once no client still draws it where it was, and
		-- before its recovery ends (it moves off then).
		local lag = collision.clientDrawLagSeconds
		local rejoinClear = collision.rejoinClearSeconds
		positiveNumber(lag, "collision.clientDrawLagSeconds")
		positiveNumber(rejoinClear, "collision.rejoinClearSeconds")
		if typeof(lag) == "number" and typeof(rejoinClear) == "number" then
			if rejoinClear <= lag then
				problem(
					("collision.rejoinClearSeconds %s must exceed clientDrawLagSeconds %s"):format(
						tostring(rejoinClear),
						tostring(lag)
					)
				)
			end
			for _, def in Enemies.list() do
				for _, attack in def.attacks do
					local rush = def.archetype == "Charger" and (attack.arc == 0 or attack.groundShape == "Line")
					if rush and attack.recovery <= rejoinClear then
						problem(
							("%s.%s: recovery %s must exceed collision.rejoinClearSeconds %s"):format(
								def.id,
								attack.id,
								tostring(attack.recovery),
								tostring(rejoinClear)
							)
						)
					end
				end
			end
		end
	end

	-- D-205 to D-209: how a rushing body meets the world, one set of numbers for the server and the
	-- clients.
	local world = AI.rushWorld
	if typeof(world) ~= "table" then
		problem("rushWorld must be a table")
	else
		for _, field in
			{
				"riserStuds",
				"probeStuds",
				"glanceDegrees",
				"clipStuds",
				"clipMarginStuds",
				"clipRunStuds",
				"clipPassStuds",
				"clipBisections",
				"lookAheadStuds",
				"maxLegs",
				"turnRate",
				"slamDazeSeconds",
				"fallGravity",
				"restStuds",
				"restSeconds",
				"restSpeed",
			}
		do
			positiveNumber(world[field], "rushWorld." .. field)
		end
		local function numbers(...: any): boolean
			for index = 1, select("#", ...) do
				local value = select(index, ...)
				if typeof(value) ~= "number" or value ~= value then
					return false
				end
			end
			return true
		end
		if numbers(world.glanceDegrees) and world.glanceDegrees >= 90 then
			problem(("rushWorld.glanceDegrees must be below 90, got %s"):format(tostring(world.glanceDegrees)))
		end
		-- A sidestep seen at once still has its whole run before the snout reaches the corner.
		if numbers(world.lookAheadStuds, world.clipRunStuds) and world.lookAheadStuds < world.clipRunStuds then
			problem(
				("rushWorld.lookAheadStuds %s must be at least clipRunStuds %s"):format(
					tostring(world.lookAheadStuds),
					tostring(world.clipRunStuds)
				)
			)
		end
		-- A sidestep of the most overlap fits its run (one steeper than it is wide is a slam).
		if
			numbers(world.clipRunStuds, world.clipStuds, world.clipMarginStuds)
			and world.clipRunStuds < world.clipStuds + world.clipMarginStuds
		then
			problem("rushWorld.clipRunStuds must be at least clipStuds + clipMarginStuds")
		end
		-- A line, a bend and a sidestep's two legs.
		if numbers(world.maxLegs) and (world.maxLegs < 3 or world.maxLegs % 1 ~= 0) then
			problem(("rushWorld.maxLegs must be a whole number of at least 3, got %s"):format(tostring(world.maxLegs)))
		end
		if numbers(world.clipBisections) and world.clipBisections % 1 ~= 0 then
			problem("rushWorld.clipBisections must be a whole number")
		end
		-- The server's body and every drawn one turn onto a new leg at the same rate.
		local Choreo = ctx.load("src/shared/data/choreo")
		local drawnTurn = Choreo.enemy and Choreo.enemy.rush and Choreo.enemy.rush.turnRate
		if drawnTurn ~= world.turnRate then
			problem(
				("rushWorld.turnRate %s must equal choreo enemy.rush.turnRate %s"):format(
					tostring(world.turnRate),
					tostring(drawnTurn)
				)
			)
		end
		-- A slam's daze is the best opening a boar gives: no shorter than a parry's stagger.
		local parry = ctx.load("src/shared/data/combat").parryStagger
		if numbers(world.slamDazeSeconds, parry) and world.slamDazeSeconds < parry then
			problem(
				("rushWorld.slamDazeSeconds %s must be at least combat.parryStagger %s"):format(
					tostring(world.slamDazeSeconds),
					tostring(parry)
				)
			)
		end
		-- A step the body climbs is lower than every rushing rig's hip (its root's box clears the
		-- step's top when it gets there), and the ground probe reaches below the hip.
		local Rigs = ctx.load("src/shared/data/rigs")
		for _, def in Enemies.list() do
			local rig = if def.archetype == "Charger" then Rigs[def.skin] else nil
			if rig ~= nil and numbers(world.riserStuds, world.probeStuds, rig.hipHeight) then
				if world.riserStuds >= rig.hipHeight then
					problem(
						("rushWorld.riserStuds %s must be below rig %s's hipHeight %s"):format(
							tostring(world.riserStuds),
							def.skin,
							tostring(rig.hipHeight)
						)
					)
				end
				if world.probeStuds <= rig.hipHeight then
					problem(("rushWorld.probeStuds must reach below rig %s's hip"):format(def.skin))
				end
			end
		end
	end

	-- D-494: the fall states every enemy Humanoid keeps out of are engine state names, and never a
	-- state the body needs (standing, walking, the air, getting up, death).
	local upright = AI.upright
	local fallStates = { FallingDown = true, Ragdoll = true, Physics = true, PlatformStanding = true, Seated = true }
	if typeof(upright) ~= "table" or typeof(upright.offStates) ~= "table" or #upright.offStates == 0 then
		problem("upright.offStates must be a non-empty list of Humanoid state names")
	else
		local seen: { [string]: boolean } = {}
		for _, name in upright.offStates do
			if typeof(name) ~= "string" or not fallStates[name] then
				problem(
					("upright.offStates: %s is not a fall state an enemy may keep out of (%s)"):format(
						tostring(name),
						"FallingDown, Ragdoll, Physics, PlatformStanding, Seated"
					)
				)
			elseif seen[name] then
				problem(("upright.offStates names %s twice"):format(name))
			end
			if typeof(name) == "string" then
				seen[name] = true
			end
		end
		if not seen.FallingDown then
			problem("upright.offStates must hold FallingDown (the staged charge's jam, D-494)")
		end
	end

	-- D-523: each client's copy. It stands up into a state a standing body walks in (never a fall
	-- state, so never one of offStates), retries a bounded number of PreSimulation steps, and logs
	-- through three distinct attribute names that are none of the names the server publishes on a
	-- fighter (a server write would overwrite the client's), with distinct non-empty values.
	local client = if typeof(upright) == "table" then upright.client else nil
	if typeof(client) ~= "table" then
		problem("upright.client must be a table (the client copy's stand-up and log aid, D-523)")
	else
		local standUpStates = { Running = true, GettingUp = true }
		local stand = client.standUpState
		if typeof(stand) ~= "string" or not standUpStates[stand] then
			problem(("upright.client.standUpState %s must be Running or GettingUp"):format(tostring(stand)))
		elseif typeof(upright.offStates) == "table" and table.find(upright.offStates, stand) ~= nil then
			problem(("upright.client.standUpState %s is one of upright.offStates"):format(stand))
		end
		local tries = client.maxTries
		if typeof(tries) ~= "number" or tries < 1 or tries % 1 ~= 0 then
			problem("upright.client.maxTries must be a whole number of at least 1")
		end
		-- D-543: the copy's own list holds every state the server turns off, and only fall states.
		local clientStates = client.offStates
		if typeof(clientStates) ~= "table" or #clientStates == 0 then
			problem("upright.client.offStates must be a non-empty list of Humanoid state names")
		else
			local seen: { [string]: boolean } = {}
			for _, name in clientStates do
				if typeof(name) ~= "string" or not fallStates[name] then
					problem(
						("upright.client.offStates: %s is not a fall state an enemy may keep out of"):format(
							tostring(name)
						)
					)
				elseif seen[name] then
					problem(("upright.client.offStates names %s twice"):format(name))
				else
					seen[name] = true
				end
			end
			for _, name in if typeof(upright.offStates) == "table" then upright.offStates else {} do
				if typeof(name) == "string" and not seen[name] then
					problem(("upright.client.offStates must hold %s (upright.offStates, the server's)"):format(name))
				end
			end
			if typeof(stand) == "string" and seen[stand] then
				problem(("upright.client.standUpState %s is one of upright.client.offStates"):format(stand))
			end
		end
		if typeof(client.catchOnArrival) ~= "boolean" then
			problem("upright.client.catchOnArrival must be true or false")
		end
		-- D-544: the code knows the two rescues by these names.
		local rescues = client.rescues
		if
			typeof(rescues) ~= "table"
			or rescues.stateMachine ~= "StateMachine"
			or rescues.changeState ~= "ChangeState"
		then
			problem('upright.client.rescues must name stateMachine "StateMachine" and changeState "ChangeState"')
		elseif client.rescue ~= rescues.stateMachine and client.rescue ~= rescues.changeState then
			problem(("upright.client.rescue %s must be one of upright.client.rescues"):format(tostring(client.rescue)))
		end
		local published = {
			EntityId = true,
			EntityKind = true,
			DefId = true,
			Rig = true,
			DisplayName = true,
			HP = true,
			MaxHP = true,
			Gauge = true,
			MaxGauge = true,
			State = true,
			Cursor = true,
			Level = true,
			WeaponId = true,
			Elite = true,
			Drawn = true,
		}
		local names: { [string]: string } = {}
		local attributes = client.attributes
		for _, field in { "state", "why", "tries" } do
			local name = if typeof(attributes) == "table" then attributes[field] else nil
			if typeof(name) ~= "string" or name == "" then
				problem(("upright.client.attributes.%s must be a non-empty attribute name"):format(field))
			elseif published[name] then
				problem(("upright.client.attributes.%s '%s' is an attribute the server publishes"):format(field, name))
			elseif names[name] ~= nil then
				problem(("upright.client.attributes.%s '%s' is also attributes.%s"):format(field, name, names[name]))
			else
				names[name] = field
			end
		end
		local values: { [string]: string } = {}
		for _, group in
			{ { "states", { "off", "stoodUp", "waiting" } }, { "whys", { "noHumanoid", "notEnemy", "notTaken" } } }
		do
			local list = client[group[1]]
			for _, field in group[2] :: { string } do
				local label = ("upright.client.%s.%s"):format(group[1] :: string, field)
				local value = if typeof(list) == "table" then list[field] else nil
				if typeof(value) ~= "string" or value == "" then
					problem(label .. " must be a non-empty string")
				elseif values[value] ~= nil then
					problem(("%s '%s' is also %s"):format(label, value, values[value]))
				else
					values[value] = label
				end
			end
		end
	end

	if typeof(AI.interrupt) == "table" then
		positiveNumber(AI.interrupt.resumeDelay, "interrupt.resumeDelay")
		for _, state in { "Stagger", "Break", "GuardBroken" } do
			positiveNumber(AI.interrupt.durations[state], "interrupt.durations." .. state)
		end
	end

	return problems
end

return validate
