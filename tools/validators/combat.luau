--!strict
--[[
	Validates the server hit detection block of src/shared/data/combat.luau (section 6, D-010):
	the sample rate, hit radius and target cap are positive, the lag allowance is not negative, and
	the arc sweep (HitSweep.followArc) is tied to the hit radius and has a positive whole cap.

	sweepMaxTipStep is how far either end of the blade may move between two samples of the sweep
	while sweepMaxSubdivisions lasts (a step the cap leaves longer is covered by its ends' chords
	instead, HitSweep.castBladePath). Every point the blade passes between two samples lies within
	half a step of one of them, and the overlap test reaches one hit radius from each sampled blade,
	so a step of at most two radii is what guarantees that a blade passing through a target touches
	it at a sample; past that, a thin target can sit in the gap between two sampled blades.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

-- The widest step that still guarantees a pass-through touches a sample, in hit radii.
local MAX_STEP_IN_RADII = 2

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

return function(ctx: Context): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, "combat: " .. message)
	end

	local combat = ctx.load("src/shared/data/combat")

	local function positive(name: string): boolean
		local value = combat[name]
		if not isNumber(value) or value <= 0 then
			problem(("%s must be a positive number (got %s)"):format(name, tostring(value)))
			return false
		end
		return true
	end

	local function positiveWhole(name: string): boolean
		local value = combat[name]
		if not isNumber(value) or value < 1 or value % 1 ~= 0 then
			problem(("%s must be a positive whole number (got %s)"):format(name, tostring(value)))
			return false
		end
		return true
	end

	positive("hitSampleHz")
	positiveWhole("maxTargetsPerWindow")
	if not isNumber(combat.lagAllowance) or combat.lagAllowance < 0 then
		problem(("lagAllowance must be a number of seconds, 0 or more (got %s)"):format(tostring(combat.lagAllowance)))
	end

	local radiusOk = positive("hitSphereRadius")
	local stepOk = positive("sweepMaxTipStep")
	positiveWhole("sweepMaxSubdivisions")
	if radiusOk and stepOk and combat.sweepMaxTipStep > combat.hitSphereRadius * MAX_STEP_IN_RADII then
		problem(
			("sweepMaxTipStep %s is over %d x hitSphereRadius (%s): a blade could pass through a target between two sub-samples"):format(
				tostring(combat.sweepMaxTipStep),
				MAX_STEP_IN_RADII,
				tostring(combat.hitSphereRadius)
			)
		)
	end

	return problems
end
