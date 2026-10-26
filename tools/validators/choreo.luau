--!strict
--[[
	Validates data/choreo.luau's render-stall jump (stall.jumpSeconds, D-132). A step longer than
	jumpSeconds is a jump: the clip clocks take the gap, the root takes none of it, and the events
	it crossed only close what they close.

	- jumpSeconds is a positive, finite number.
	- A rig the quality tier steps on Heartbeat (distantHz, farHz) steps every 1 / rate, and
	  Heartbeat keeps running while the display sleeps: only a Heartbeat hitch as long as a whole
	  step on top of one may count as a jump, so jumpSeconds is at least 2 / rate for every rate of
	  every tier. Low's 4 Hz far rate wants 0.5 s.
	- A gap the camera snaps through (camera.luau stall.settleSeconds) is a stall for the clips too,
	  so jumpSeconds is at most settleSeconds.

	And the sheath's moving cap: sheath.movingTipShare is in (0, 1], the share of drawTipSpeed and
	sheatheTipSpeed a Draw or Sheathe over a moving body is held to (tests/choreo/SheathTip.spec.luau
	sweeps the cycle at it), so the cap moving is never above the cap standing.
]]

local TIERS = { "High", "Medium", "Low" }
local RATES = { "distantHz", "farHz" }

local function positive(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0 and value < math.huge
end

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "choreo: " .. message)
		end
	end

	local choreo = ctx.load("src/shared/data/choreo")
	local camera = ctx.load("src/shared/data/camera")

	local sheath = choreo.sheath
	local share = if typeof(sheath) == "table" then sheath.movingTipShare else nil
	check(
		positive(share) and share <= 1,
		("sheath.movingTipShare (%s) must be in (0, 1]: the share of the tip cap a Draw or Sheathe over a moving body keeps"):format(
			tostring(share)
		)
	)

	local stall = choreo.stall
	if typeof(stall) ~= "table" then
		check(false, "stall is missing (jumpSeconds: the longest step that is not a render-stall jump)")
		return problems
	end
	local jump = stall.jumpSeconds
	if not positive(jump) then
		check(false, "stall.jumpSeconds must be a positive number of seconds")
		return problems
	end

	for _, tier in TIERS do
		local row = choreo.quality[tier]
		if typeof(row) == "table" then
			for _, rate in RATES do
				local hz = row[rate]
				if positive(hz) then
					check(
						jump >= 2 / hz,
						("stall.jumpSeconds %.2f is under 2 / quality.%s.%s (%.2f): a rig stepped on Heartbeat at that rate would jump on a hitch shorter than its own step"):format(
							jump,
							tier,
							rate,
							2 / hz
						)
					)
				end
			end
		end
	end

	local settle = if typeof(camera.stall) == "table" then camera.stall.settleSeconds else nil
	if positive(settle) then
		check(
			jump <= settle,
			("stall.jumpSeconds %.2f is over camera.stall.settleSeconds (%.2f): a gap the camera snaps through would replay the clips"):format(
				jump,
				settle
			)
		)
	end

	return problems
end
