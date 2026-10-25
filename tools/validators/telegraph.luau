--!strict
--[[
	Validates the parry glint in src/shared/data/fx.luau `telegraph` (D-CP1, D-CP2, D-289) against
	the blows it glints on:
	- glintFrames is a whole number of at least 1 and glintAimFrames is 0 or more;
	- glintToken is a palette token; glintKinds holds only kinds the tells have (`sounds`), each
	  true, and never Unblockable: an Unblockable blow cannot be parried (section 6), so it never
	  shows the cue to press;
	- glintDecalAlpha is above the ground's own decal.alpha (the glint reads brighter) and at most 1;
	- glintLeadMax is 0 or more and glintLeadSamples a whole number of at least 1;
	- every enemy, elite and boss blow of a kind that glints, with a strike, has its glint (with no
	  lead) wholly on the parry window and before the tell goes out: inside
	  [lands - combat.luau parryWindow, lands - ai.luau telegraph.snapLeadSeconds] and inside its own
	  wind-up and strike, so a press on any glint frame can parry. The glint is the one
	  TelegraphShapes.timing draws: glintFrames frames centred on the window's middle, glintAimFrames
	  earlier. A Charger's rush (a Line, or no arc) has no glint: its run is the strike.
]]

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value
end

local function isWhole(value: any, least: number): boolean
	return isNumber(value) and value >= least and value % 1 == 0
end

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "telegraph: " .. message)
		end
	end

	local fx = ctx.load("src/shared/data/fx")
	local combat = ctx.load("src/shared/data/combat")
	local ai = ctx.load("src/shared/data/ai")
	local palette = ctx.load("src/shared/data/palette")
	local Enemies = ctx.load("src/shared/data/enemies")
	local Bosses = ctx.load("src/shared/data/bosses")

	local config = fx.telegraph
	if typeof(config) ~= "table" then
		check(false, "fx.telegraph is missing")
		return problems
	end

	check(isWhole(config.glintFrames, 1), "glintFrames must be a whole number of at least 1")
	check(isNumber(config.glintAimFrames) and config.glintAimFrames >= 0, "glintAimFrames must be 0 or more")
	check(
		typeof(config.glintToken) == "string" and palette.tokens[config.glintToken] ~= nil,
		("glintToken '%s' is not a palette token"):format(tostring(config.glintToken))
	)
	local kinds = config.glintKinds
	if typeof(kinds) ~= "table" then
		check(false, "glintKinds must be a set of telegraph kinds")
		kinds = {}
	end
	for kind, value in kinds do
		check(
			typeof(kind) == "string" and typeof(config.sounds) == "table" and config.sounds[kind] ~= nil,
			("glintKinds.%s is not a telegraph kind"):format(tostring(kind))
		)
		check(value == true, ("glintKinds.%s must be true"):format(tostring(kind)))
	end
	check(
		kinds.Unblockable == nil,
		"glintKinds must not hold Unblockable: an Unblockable blow cannot be parried, so it never shows the cue"
	)
	local decal = if typeof(config.decal) == "table" then config.decal.alpha else nil
	check(
		isNumber(config.glintDecalAlpha)
			and isNumber(decal)
			and config.glintDecalAlpha > decal
			and config.glintDecalAlpha <= 1,
		("glintDecalAlpha (%s) must be above decal.alpha (%s) and at most 1"):format(
			tostring(config.glintDecalAlpha),
			tostring(decal)
		)
	)
	check(isNumber(config.glintLeadMax) and config.glintLeadMax >= 0, "glintLeadMax must be 0 or more")
	check(isWhole(config.glintLeadSamples, 1), "glintLeadSamples must be a whole number of at least 1")
	if not (isWhole(config.glintFrames, 1) and isNumber(config.glintAimFrames)) then
		return problems
	end

	-- TelegraphShapes.timing with no lead, in seconds from the wind-up's start.
	local frame = combat.hitStopFrameSeconds
	local window = combat.parryWindow
	local snapLead = ai.telegraph.snapLeadSeconds
	local function blow(label: string, archetype: string?, attack: any)
		if kinds[attack.telegraph] ~= true or not (isNumber(attack.strike) and attack.strike > 0) then
			return
		end
		if archetype == "Charger" and (attack.arc == 0 or attack.groundShape == "Line") then
			return
		end
		local lands = attack.windUp + attack.strike
		local centre = lands - window / 2 - config.glintAimFrames * frame
		local half = config.glintFrames * frame / 2
		local from, to = centre - half, centre + half
		local opens, ends = math.max(lands - window, 0), lands - snapLead
		check(
			from >= opens - 1e-9 and to <= ends + 1e-9,
			("%s: its glint [%.4f, %.4f] s into the wind-up must lie inside [%.4f, %.4f] (the parry window, to the tell's end)"):format(
				label,
				from,
				to,
				opens,
				ends
			)
		)
	end

	for _, def in Enemies.list() do
		for _, attack in def.attacks do
			blow(("%s.%s"):format(def.id, attack.id), def.archetype, attack)
		end
	end
	local archetypes: { string } = {}
	for archetype in Enemies.eliteAttacks do
		table.insert(archetypes, archetype)
	end
	table.sort(archetypes)
	for _, archetype in archetypes do
		local attack = Enemies.eliteAttacks[archetype]
		blow(("elite %s.%s"):format(archetype, attack.id), archetype, attack)
	end
	for _, boss in Bosses.list() do
		for index, phase in boss.phases do
			for _, attack in phase.attacks do
				blow(("%s phase %d.%s"):format(boss.id, index, attack.id), nil, attack)
			end
		end
	end

	return problems
end
