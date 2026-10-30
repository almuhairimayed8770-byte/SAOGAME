--!strict
--[[
	OutlineRanking: which rigs get a Highlight when there are more fighters than the budget
	(section 11: 31 concurrent, ranked by importance then distance; party, lock target and boss
	always on). Pure: OutlineManager feeds it plain candidate records.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)

export type Importance = "Boss" | "Lock" | "Party" | "Normal"

export type Candidate = {
	key: any, -- whatever identifies the rig to the caller (the model)
	importance: Importance,
	distance: number, -- studs from the viewer
}

local OutlineRanking = {}

--- Ranks candidates (lower is better): importance first, then distance.
function OutlineRanking.compare(a: Candidate, b: Candidate): boolean
	local ranks = Fx.outline.importanceRank
	local rankA = ranks[a.importance] or ranks.Normal
	local rankB = ranks[b.importance] or ranks.Normal
	if rankA ~= rankB then
		return rankA < rankB
	end
	return a.distance < b.distance
end

--- Picks the candidates that get a Highlight: always-on importances regardless of distance, then
--- the nearest of the rest inside `maxDistance`, until `budget` is spent. Returns the chosen keys
--- in rank order plus a set for membership tests.
function OutlineRanking.select(
	candidates: { Candidate },
	budget: number,
	maxDistance: number
): ({ any }, { [any]: boolean })
	local eligible: { Candidate } = {}
	local alwaysOn = Fx.outline.alwaysOn
	for _, candidate in candidates do
		if alwaysOn[candidate.importance] == true or candidate.distance <= maxDistance then
			table.insert(eligible, candidate)
		end
	end
	table.sort(eligible, OutlineRanking.compare)
	local chosen: { any } = {}
	local set: { [any]: boolean } = {}
	local limit = math.max(0, math.floor(budget))
	for index = 1, math.min(limit, #eligible) do
		local candidate = eligible[index]
		table.insert(chosen, candidate.key)
		set[candidate.key] = true
	end
	return chosen, set
end

--- Darkens a base color toward the ink color by the outline blend: the near-black outline.
function OutlineRanking.inkColor(base: { number }, ink: { number }, blend: number): { number }
	local t = math.clamp(blend, 0, 1)
	return {
		base[1] + (ink[1] - base[1]) * t,
		base[2] + (ink[2] - base[2]) * t,
		base[3] + (ink[3] - base[3]) * t,
	}
end

return OutlineRanking
