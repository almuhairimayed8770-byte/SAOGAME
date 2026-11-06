--!strict
--[[
	Origins validator: each creation roll's weights sum to 100 (within 1e-9), every weight is
	positive, every lineage and origin id has an effects entry with a description, the rare
	rolls have announcement lines, and the section 7 chances are exactly the spec's.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local TOTAL = 100
local TOLERANCE = 1e-9

local EXPECTED = {
	lineage = {
		Lowlander = 16,
		Highborn = 16,
		Woodling = 16,
		Ironfolk = 16,
		Driftkin = 16,
		Stormblood = 6,
		Nightveil = 6,
		Ashborn = 5,
		Starmarked = 2,
		Hollowkin = 1,
	},
	origin = { None = 92, Ironhand = 3, Beastbond = 2, Flashdraw = 1.5, DualWielder = 1, Aegis = 0.5 },
	mark = { ArchitectsMark = 0.1, None = 99.9 },
}

local ANNOUNCED = { "DualWielder", "Aegis", "ArchitectsMark" }

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end

	local Origins = ctx.load("src/shared/data/origins")

	for _, rollName in { "lineage", "origin", "mark" } do
		local entries = Origins[rollName]
		if typeof(entries) ~= "table" then
			problem("origins.%s is missing", rollName)
			continue
		end
		local expected = EXPECTED[rollName]
		local seen: { [string]: boolean } = {}
		local total = 0
		for index, entry in ipairs(entries) do
			if typeof(entry.value) ~= "string" or typeof(entry.weight) ~= "number" then
				problem("origins.%s[%d] needs a string value and a numeric weight", rollName, index)
				continue
			end
			if entry.weight <= 0 then
				problem("origins.%s '%s' has a non-positive weight", rollName, entry.value)
			end
			if seen[entry.value] then
				problem("origins.%s lists '%s' twice", rollName, entry.value)
			end
			seen[entry.value] = true
			total += entry.weight
			local want = expected[entry.value]
			if want == nil then
				problem("origins.%s '%s' is not in the section 7 table", rollName, entry.value)
			elseif math.abs(want - entry.weight) > TOLERANCE then
				problem(
					"origins.%s '%s' weight %s should be %s",
					rollName,
					entry.value,
					tostring(entry.weight),
					tostring(want)
				)
			end
		end
		for id in expected do
			if not seen[id] then
				problem("origins.%s is missing '%s'", rollName, id)
			end
		end
		if math.abs(total - TOTAL) > TOLERANCE then
			problem("origins.%s weights sum to %s, not %d", rollName, tostring(total), TOTAL)
		end
		if rollName ~= "mark" then
			for id in seen do
				local effect = Origins.effects[id]
				if typeof(effect) ~= "table" then
					problem("origins.effects has no entry for %s '%s'", rollName, id)
				elseif typeof(effect.description) ~= "string" or effect.description == "" then
					problem("origins.effects.%s needs a description", id)
				end
			end
		end
	end

	for _, id in ANNOUNCED do
		if typeof(Origins.announcements[id]) ~= "string" then
			problem("origins.announcements is missing the line for '%s'", id)
		end
		if typeof(Origins.displayNames[id]) ~= "string" then
			problem("origins.displayNames is missing '%s'", id)
		end
	end
	if Origins.announcements.DualWielder ~= "A Dual Wielder has entered the Spire" then
		problem("origins.announcements.DualWielder must be the section 7 line")
	end
	if typeof(Origins.roll) ~= "function" or typeof(Origins.announcementsFor) ~= "function" then
		problem("origins.luau must export roll() and announcementsFor()")
	end

	return problems
end
