--!strict
--[[
	Validates data/choreo.luau locomotion.stride, the numbers Locomotion paces the gait clips with
	(D-054): every gait clip (the walks, Run and Sprint of both sets) has a ground speed and a
	touchdown; the pace range holds a clip's own rate (rateFloor < 1 < rateCeiling); and every walk
	clip, played at rateCeiling, keeps its planted foot under a root moving at locomotion.walkSpeed.
	The lock-on strafe and backpedal move at that speed on one walk clip alone (D-112), so a walk
	whose ground speed times rateCeiling falls short of it slides at every step. The two-step stop's
	locomotion.stopHandOverCycles sits inside half a cycle, so a settle point can fall before the
	other foot's Footstep.
	tests/choreo/Stride.spec.luau re-measures the ground speeds and touchdowns from the clips.
]]

local SETS = { "", "Drawn" }
local WALKS = { "WalkForward", "WalkBack", "WalkLeft", "WalkRight" }
local GAITS = { "WalkForward", "WalkBack", "WalkLeft", "WalkRight", "Run", "Sprint" }

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "stride: " .. message)
		end
	end

	local choreo = ctx.load("src/shared/data/choreo")
	local locomotion = choreo.locomotion
	local stride = locomotion.stride
	local groundSpeed = stride.groundSpeed
	local touchdown = stride.touchdown

	check(stride.rateFloor > 0 and stride.rateFloor < 1, "rateFloor must sit between 0 and a clip's own rate 1")
	check(stride.rateCeiling > 1, "rateCeiling must be above a clip's own rate 1")
	local handOver = locomotion.stopHandOverCycles
	check(
		typeof(handOver) == "number" and handOver > 0 and handOver < 0.5,
		"stopHandOverCycles must be a number of cycles between 0 and half a cycle (a settle point must fit before the other foot's Footstep)"
	)

	for _, set in SETS do
		for _, gait in GAITS do
			local name = gait .. set
			local speed = groundSpeed[name]
			check(
				typeof(speed) == "number" and speed > 0,
				("groundSpeed.%s must be a positive number (studs a second at rate 1)"):format(name)
			)
			local feet = touchdown[name]
			check(
				typeof(feet) == "table" and typeof(feet.left) == "table" and typeof(feet.right) == "table",
				("touchdown.%s must give the left and right foot"):format(name)
			)
		end
		for _, walk in WALKS do
			local name = walk .. set
			local speed = groundSpeed[name]
			if typeof(speed) == "number" then
				local fastest = speed * stride.rateCeiling
				check(
					fastest >= locomotion.walkSpeed,
					("%s at rateCeiling moves its planted foot %.2f studs a second, under walkSpeed %.2f: a lock-on strafe or backpedal would slide"):format(
						name,
						fastest,
						locomotion.walkSpeed
					)
				)
			end
		end
	end

	return problems
end
