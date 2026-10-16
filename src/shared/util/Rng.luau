--!strict
--[[
	Rng: weighted rolls on a `Random` seeded per request (section 7). Every roll that matters
	(origins, loot, crits) goes through here so it is testable and loggable.
]]

local Rng = {}

export type Weighted<T> = { value: T, weight: number }

--- Picks one entry by weight. Weights need not sum to 100; zero-weight entries are never picked.
function Rng.weighted<T>(random: Random, entries: { Weighted<T> }): T
	local total = 0
	for _, entry in entries do
		total += entry.weight
	end
	assert(total > 0, "weighted roll with no weight")
	local roll = random:NextNumber() * total
	local accumulated = 0
	for _, entry in entries do
		accumulated += entry.weight
		if roll < accumulated then
			return entry.value
		end
	end
	return entries[#entries].value
end

--- True with probability `chance` in [0, 1].
function Rng.chance(random: Random, chance: number): boolean
	return random:NextNumber() < chance
end

--- A Random seeded from a request key and a server-side nonce so clients cannot predict it.
function Rng.forRequest(nonce: number, requestKey: number): Random
	return Random.new(nonce * 7919 + requestKey)
end

return Rng
