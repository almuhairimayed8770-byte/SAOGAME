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
	An enemy's blocker (D-198) collides with players and with nothing else (not the world, not an
	enemy, not a rush, not another blocker), a standing enemy's root no longer collides with players,
	and blockerHeight reaches above the top of every enemy rig's root. How a rush meets the world
	(rushWorld, D-205 to D-209): positive numbers, a glance below 90 degrees, a look ahead at least a
	sidestep's run, a sidestep that fits its run, at least three legs, the server's leg turn equal to
	the drawn one (choreo enemy.rush.turnRate), a daze no shorter than a parry's stagger, and a
	climbable riser below every Charger rig's hip.
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
		-- D-198: the blocker is what a player bumps into, and nothing else touches it.
		local blockers = collision.blockers
		if typeof(blockers) == "string" then
			if apartSet[blockers .. "|" .. tostring(collision.players)] then
				problem("collision.apart must not keep the blockers group from the players group")
			end
			for _, other in { "Default", collision.enemies, collision.rushing, blockers } do
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

	if typeof(AI.interrupt) == "table" then
		positiveNumber(AI.interrupt.resumeDelay, "interrupt.resumeDelay")
		for _, state in { "Stagger", "Break", "GuardBroken" } do
			positiveNumber(AI.interrupt.durations[state], "interrupt.durations." .. state)
		end
	end

	return problems
end

return validate
