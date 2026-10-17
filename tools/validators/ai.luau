--!strict
--[[
	Validates src/shared/data/ai.luau: the shape of every tuning table, the section 16 rates
	matching enemies.rules, every Charger row's line covered by chargeSpeed * strike, material
	costs that PathfindingService accepts (positive numbers keyed by material name), and attack
	weights that name attacks which exist in enemies.luau.
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

	if typeof(AI.interrupt) == "table" then
		positiveNumber(AI.interrupt.resumeDelay, "interrupt.resumeDelay")
		for _, state in { "Stagger", "Break", "GuardBroken" } do
			positiveNumber(AI.interrupt.durations[state], "interrupt.durations." .. state)
		end
	end

	return problems
end

return validate
