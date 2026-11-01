--!strict
--[[
	Validates the outline budget and ranks in src/shared/data/fx.luau `outline` (section 11, D-476),
	the numbers OutlineManager and OutlineRanking read to light at most budgets.highlights rig
	Highlights at once:
	- budget is a whole number of at least 1 and at most budgets.highlights (the engine's cap);
	- importanceRank holds a number for Boss, Lock, Party and Normal, and Normal ranks last: every
	  other importance is lit before a resting outline;
	- alwaysOn holds only importances importanceRank ranks, each true, and never Normal;
	- signalRank (a rig showing a hit's flash or a telegraph's tint) is a number after every
	  always-on importance's rank and before Normal's: a flash never takes an always-on rig's slot,
	  and always takes the farthest resting outline's before it would light past the budget.
]]

local IMPORTANCES = { "Boss", "Lock", "Party", "Normal" }

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value < math.huge and value > -math.huge
end

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "outline: " .. message)
		end
	end

	local fx = ctx.load("src/shared/data/fx")
	local outline = fx.outline
	if typeof(outline) ~= "table" then
		check(false, "fx.outline is missing")
		return problems
	end
	local cap = if typeof(fx.budgets) == "table" then fx.budgets.highlights else nil
	check(isNumber(cap) and cap >= 1 and cap % 1 == 0, "budgets.highlights must be a whole number of at least 1")
	check(
		isNumber(outline.budget)
			and outline.budget >= 1
			and outline.budget % 1 == 0
			and isNumber(cap)
			and outline.budget <= cap,
		("budget (%s) must be a whole number from 1 to budgets.highlights (%s): the engine draws no more"):format(
			tostring(outline.budget),
			tostring(cap)
		)
	)

	local ranks = outline.importanceRank
	if typeof(ranks) ~= "table" then
		check(false, "importanceRank must be a table of importance -> rank")
		return problems
	end
	for _, importance in IMPORTANCES do
		check(isNumber(ranks[importance]), ("importanceRank.%s must be a number"):format(importance))
	end
	local normal = ranks.Normal
	if not isNumber(normal) then
		return problems
	end
	for importance, rank in ranks do
		if importance ~= "Normal" then
			check(
				isNumber(rank) and rank < normal,
				("importanceRank.%s (%s) must rank before Normal (%s)"):format(
					tostring(importance),
					tostring(rank),
					tostring(normal)
				)
			)
		end
	end

	local alwaysOn = outline.alwaysOn
	if typeof(alwaysOn) ~= "table" then
		check(false, "alwaysOn must be a set of importances")
		alwaysOn = {}
	end
	local lastAlwaysOn = -math.huge
	for importance, value in alwaysOn do
		check(value == true, ("alwaysOn.%s must be true"):format(tostring(importance)))
		check(importance ~= "Normal", "alwaysOn must not hold Normal: resting outlines are ranked by distance")
		local rank = ranks[importance]
		check(isNumber(rank), ("alwaysOn.%s is not an importance importanceRank ranks"):format(tostring(importance)))
		if isNumber(rank) then
			lastAlwaysOn = math.max(lastAlwaysOn, rank)
		end
	end

	local signal = outline.signalRank
	check(
		isNumber(signal) and signal > lastAlwaysOn and signal < normal,
		("signalRank (%s) must rank after every always-on importance (%s) and before Normal (%s): a flash takes a resting outline's slot, never an always-on rig's"):format(
			tostring(signal),
			tostring(lastAlwaysOn),
			tostring(normal)
		)
	)

	return problems
end
