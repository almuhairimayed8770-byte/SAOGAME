--!strict
--[[
	TargetRanking: pure candidate ranking for lock-on (section 6: F / R3 locks the nearest enemy
	in front of the camera; repeated presses cycle). Plain numbers only, so it runs in Lune.
]]

export type Vec = { number }

export type Candidate = {
	id: number,
	distance: number, -- studs from the player
	angle: number, -- radians between the camera's forward and the direction to the candidate
}

export type Params = {
	range: number,
	coneDegrees: number,
	angleWeightStuds: number,
}

local TargetRanking = {}

local function unpack3(v: Vec): (number, number, number)
	local x, y, z = table.unpack(v)
	return x, y, z
end

--- Angle (radians, 0..pi) between `forward` and the direction from `from` to `to`.
function TargetRanking.angleFrom(forward: Vec, from: Vec, to: Vec): number
	local fx, fy, fz = unpack3(forward)
	local ax, ay, az = unpack3(from)
	local bx, by, bz = unpack3(to)
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local forwardLength = math.sqrt(fx * fx + fy * fy + fz * fz)
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	if forwardLength == 0 or length == 0 then
		return 0
	end
	local cosine = (fx * dx + fy * dy + fz * dz) / (forwardLength * length)
	return math.acos(math.clamp(cosine, -1, 1))
end

--- True when the candidate is inside the lock range and the camera's cone.
function TargetRanking.eligible(candidate: Candidate, params: Params): boolean
	return candidate.distance <= params.range and candidate.angle <= math.rad(params.coneDegrees / 2)
end

--- Lower is better: distance plus the off-center angle priced in studs.
function TargetRanking.score(candidate: Candidate, params: Params): number
	return candidate.distance + candidate.angle * params.angleWeightStuds
end

--- Eligible candidates sorted best first (ties broken by id so the order is stable).
function TargetRanking.rank(candidates: { Candidate }, params: Params): { Candidate }
	local ranked = {}
	for _, candidate in candidates do
		if TargetRanking.eligible(candidate, params) then
			table.insert(ranked, candidate)
		end
	end
	table.sort(ranked, function(a, b)
		local scoreA, scoreB = TargetRanking.score(a, params), TargetRanking.score(b, params)
		if scoreA ~= scoreB then
			return scoreA < scoreB
		end
		return a.id < b.id
	end)
	return ranked
end

--- The id a lock press selects: the best candidate when nothing is locked or the current target
--- is no longer ranked, the next one down while cycling, and nil (unlock) past the last.
function TargetRanking.next(rankedIds: { number }, currentId: number?): number?
	if #rankedIds == 0 then
		return nil
	end
	if currentId == nil then
		return rankedIds[1]
	end
	local index = table.find(rankedIds, currentId)
	if index == nil then
		return rankedIds[1]
	end
	return rankedIds[index + 1]
end

--- True when a held lock must drop: the target is gone or dead, or beyond the break distance.
function TargetRanking.shouldClear(state: string?, distance: number?, breakDistance: number): boolean
	if state == nil or state == "Dead" or distance == nil then
		return true
	end
	return distance > breakDistance
end

return TargetRanking
