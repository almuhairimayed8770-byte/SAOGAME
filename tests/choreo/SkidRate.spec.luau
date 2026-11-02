--!strict
--[[
	A sprint's stop plays its Skid alike at every frame rate (D-612; Studio item 512(b)).
	LocomotionState reads the stop from the speed CharacterController gives it each update.

	The owner's PC on c78acd1 at 240 fps: the body went from 24 to 0 in about 0.03 s on letting go
	of W, and the Skid played on only 3 of 10 takes (at 60 fps on all 10). On 81b8fef the drop was
	read between two updates (more than locomotion.stopSpeedDrop lost in one, from above
	skidSpeedThreshold): a 0.03 s stop loses 13 in a 60 Hz update but 3.3 in a 240 Hz one. Now the
	drop is read against a speed that falls at stopSpeedDrop / stopDropSeconds, which is the same
	rule at 60 Hz and a fall rate at any other.

	Each case runs dev.luau groundClearance.skidRate.settle seconds at the sprint, then lets the
	speed fall evenly to 0 over the case's seconds (0: at once), and two seconds more, at each of
	stepHz. A stop over each of skidStops plays one Skid; one over each of easedStops (slower than
	the Skid's drop) plays none.
]]

local LocomotionState = Harness.load("src/client/choreo/LocomotionState")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")

local Cases = Dev.groundClearance.skidRate

local function input(speed: number): any
	return {
		forward = if speed > 0 then 1 else 0,
		right = 0,
		speed = speed,
		sprinting = speed > ChoreoData.locomotion.skidSpeedThreshold,
		grounded = true,
		drawn = false,
		turning = 0,
		yawRate = 0,
		verticalVelocity = 0,
	}
end

-- How many Skids a stop over `seconds` plays at `hz`.
local function skids(hz: number, seconds: number): number
	local state = LocomotionState.new()
	local dt = 1 / hz
	local count = 0
	local t = 0
	for _ = 1, math.floor((Cases.settle + seconds + 2) * hz + 0.5) do
		t += dt
		local into = t - Cases.settle
		local speed = Cases.sprint
		if into > 1e-9 then
			speed = if seconds <= 0 then 0 else math.max(0, Cases.sprint * (1 - into / seconds))
		end
		if state:update(dt, input(speed)).oneShot == "Skid" then
			count += 1
		end
	end
	return count
end

describe("SkidRate", function()
	it("a sprint's stop plays one Skid at every frame rate, an eased one none (512(b))", function()
		local problems: { string } = {}
		local report: { string } = {}
		for _, hz in Cases.stepHz do
			local row: { string } = {}
			for _, seconds in Cases.skidStops do
				local count = skids(hz, seconds)
				table.insert(row, ("%g s: %d"):format(seconds, count))
				if count ~= 1 then
					table.insert(
						problems,
						("%g Hz, the sprint stopped over %g s: %d Skids, not 1"):format(hz, seconds, count)
					)
				end
			end
			for _, seconds in Cases.easedStops do
				local count = skids(hz, seconds)
				table.insert(row, ("%g s eased: %d"):format(seconds, count))
				if count ~= 0 then
					table.insert(
						problems,
						("%g Hz, the sprint eased off over %g s: %d Skids, not 0"):format(hz, seconds, count)
					)
				end
			end
			table.insert(report, ("%g Hz: %s"):format(hz, table.concat(row, ", ")))
		end
		print("SkidRate (Skids a stop):\n  " .. table.concat(report, "\n  "))
		expect(table.concat(problems, "\n")).toBe("")
	end)
end)
