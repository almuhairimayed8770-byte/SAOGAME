--!strict
--[[
	Validates data/choreo.luau locomotion.stride, the numbers Locomotion paces the gait clips with
	(D-054): every gait clip (the walks, Run and Sprint of both sets) has a ground speed and a
	touchdown; the pace range holds a clip's own rate (rateFloor < 1 < rateCeiling); and every walk
	clip, played at rateCeiling, keeps its planted foot under a root moving at locomotion.walkSpeed.
	The lock-on strafe and backpedal move at that speed on one walk clip alone (D-112), so a walk
	whose ground speed times rateCeiling falls short of it slides at every step. The two-step stop's
	locomotion.stopHandOverCycles sits inside half a cycle, so a settle point can fall before the
	other foot's Footstep. The blocked body's numbers (stride.blocked, D-144): an angle that tells a
	velocity off the stick from one along it (0 < degrees < 90), a settle that is no wait at all or
	under a second, a smoothing time above 0, and a speed match tighter than idleSpeedThreshold at
	the slowest capture step (dev.luau timeScale.steps), so a velocity that is not the speed's
	reading is never taken for it. stride.heldRiseSeconds, the time the walks take to carry a held
	move alone (LocomotionState.heldShare, D-292), is a positive number of seconds.
	stride.travelSlipDecaySeconds (D-411) is at least four frames and at most travelSlipSeconds / 2
	/ 0.01: a lasting 1% bias in the root's travel holds the travel slip at half its bound at most.
	stride.takeUp (StepTakeUp, D-651): whole numbers of frames, a planned-phase window of at
	least three frames (144 fps plans 2, 2, 1) and a span that holds it, the gate's window and the
	first guess's frames; the planned phase fitted again within its own window; a grid of at least
	two phases; a drift window that holds two drift steps
	at item 530's 1.5% drift and fits in the span at 60 fps; a gate share from a half to all; a
	whole-step tolerance under half a step; and a p90 bar above 0 and under one physics step's
	travel at walkSpeed (the slide one missed step shows).
	tests/choreo/Stride.spec.luau re-measures the ground speeds and touchdowns from the clips.
]]

local SETS = { "", "Drawn" }
local WALKS = { "WalkForward", "WalkBack", "WalkLeft", "WalkRight" }
local GAITS = { "WalkForward", "WalkBack", "WalkLeft", "WalkRight", "Run", "Sprint" }
-- The travel slip's decay (D-411): the root's travel may run a lasting fraction off its speed (0.6%
-- in the owner's run log); a 1% one must hold the running difference at half its bound at most.
local MAX_TRAVEL_BIAS = 0.01
local MIN_SLIP_DECAY_FRAMES = 4
-- The take-up's fit (D-651): 144 fps plans its steps 2, 2, 1, so the planned phase needs three
-- frames at least; item 530's engine ran 1.5% ahead of every clock the code reads, and a drift
-- fit needs two of its steps; the span holds the drift window at 60 fps.
local MIN_PLAN_ROWS = 3
local MIN_PHASES = 2
local ITEM_530_DRIFT = 0.015
local MIN_DRIFT_STEPS = 2
local SPAN_FPS = 60

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
	local heldRise = stride.heldRiseSeconds
	check(
		typeof(heldRise) == "number" and heldRise > 0 and heldRise < math.huge,
		("heldRiseSeconds (%s) must be a positive number of seconds: the walks take a held move over across it, never in one frame (D-292)"):format(
			tostring(heldRise)
		)
	)
	-- The travel slip's memory (D-411): longer than a few frames (a long physics frame and the short
	-- one after it cancel inside it) and short enough that a lasting 1% bias in the root's travel
	-- holds the running difference at no more than half travelSlipSeconds.
	local decay = stride.travelSlipDecaySeconds
	local slipSeconds = stride.travelSlipSeconds
	check(
		typeof(decay) == "number"
			and typeof(slipSeconds) == "number"
			and decay >= MIN_SLIP_DECAY_FRAMES / 60
			and decay * MAX_TRAVEL_BIAS <= slipSeconds / 2,
		("travelSlipDecaySeconds (%s) must be at least %d frames and at most travelSlipSeconds / 2 / %g (%s): a lasting bias never pins the travel slip at its bound"):format(
			tostring(decay),
			MIN_SLIP_DECAY_FRAMES,
			MAX_TRAVEL_BIAS,
			tostring(if typeof(slipSeconds) == "number" then slipSeconds / 2 / MAX_TRAVEL_BIAS else slipSeconds)
		)
	)
	local takeUp = stride.takeUp
	if typeof(takeUp) ~= "table" then
		check(false, "takeUp must hold the step take-up's numbers (D-651)")
	else
		local function whole(value: any, least: number): boolean
			return typeof(value) == "number" and value == math.floor(value) and value >= least
		end
		local function number(value: any): boolean
			return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
		end
		check(
			whole(takeUp.planRows, MIN_PLAN_ROWS),
			("takeUp.planRows (%s) must be a whole number of frames, at least %d (144 fps plans its steps 2, 2, 1)"):format(
				tostring(takeUp.planRows),
				MIN_PLAN_ROWS
			)
		)
		check(
			whole(takeUp.refitRows, 1) and number(takeUp.planRows) and takeUp.refitRows <= takeUp.planRows,
			("takeUp.refitRows (%s) must be a whole number of frames from 1 to planRows: the carried phase is fitted again within its own window"):format(
				tostring(takeUp.refitRows)
			)
		)
		check(
			whole(takeUp.gateRows, 1) and whole(takeUp.minRows, 1),
			"takeUp.gateRows and takeUp.minRows must be whole numbers of frames, at least 1"
		)
		check(
			whole(takeUp.minRows, 1) and whole(takeUp.planRows, 1) and takeUp.minRows >= takeUp.planRows,
			"takeUp.minRows must be at least planRows: the first guess has its whole window"
		)
		check(
			whole(takeUp.spanRows, 1)
				and number(takeUp.planRows)
				and number(takeUp.gateRows)
				and number(takeUp.minRows)
				and takeUp.spanRows >= math.max(takeUp.planRows, takeUp.gateRows, takeUp.minRows),
			"takeUp.spanRows must be a whole number of frames holding planRows, gateRows and minRows"
		)
		check(
			whole(takeUp.phases, MIN_PHASES),
			("takeUp.phases must be a whole number, at least %d"):format(MIN_PHASES)
		)
		check(number(takeUp.stepHz) and takeUp.stepHz > 0, "takeUp.stepHz must be physics steps a second, above 0")
		check(
			number(takeUp.extraSeconds)
				and number(takeUp.stepHz)
				and takeUp.extraSeconds * takeUp.stepHz * ITEM_530_DRIFT >= MIN_DRIFT_STEPS
				and whole(takeUp.spanRows, 1)
				and takeUp.extraSeconds * SPAN_FPS <= takeUp.spanRows,
			("takeUp.extraSeconds (%s) must hold %d drift steps at item 530's %g drift and fit in spanRows at %d fps"):format(
				tostring(takeUp.extraSeconds),
				MIN_DRIFT_STEPS,
				ITEM_530_DRIFT,
				SPAN_FPS
			)
		)
		check(
			number(takeUp.gateShare) and takeUp.gateShare >= 0.5 and takeUp.gateShare <= 1,
			"takeUp.gateShare must be from 0.5 to 1 (a guess wrong on half its frames is no guess)"
		)
		check(
			number(takeUp.wholeSteps) and takeUp.wholeSteps > 0 and takeUp.wholeSteps < 0.5,
			"takeUp.wholeSteps must be above 0 and under half a step"
		)
		local oneStep = if number(takeUp.stepHz) and takeUp.stepHz > 0 then locomotion.walkSpeed / takeUp.stepHz else 0
		check(
			number(takeUp.p90Bar) and takeUp.p90Bar > 0 and takeUp.p90Bar < oneStep,
			("takeUp.p90Bar (%s) must be above 0 and under one physics step's travel at walkSpeed (%.4f)"):format(
				tostring(takeUp.p90Bar),
				oneStep
			)
		)
	end

	local handOver = locomotion.stopHandOverCycles
	check(
		typeof(handOver) == "number" and handOver > 0 and handOver < 0.5,
		"stopHandOverCycles must be a number of cycles between 0 and half a cycle (a settle point must fit before the other foot's Footstep)"
	)

	local blocked = stride.blocked
	if typeof(blocked) ~= "table" then
		check(false, "blocked must hold degrees, settleSeconds, followSeconds and matchSpeed")
	else
		local function number(value: any): boolean
			return typeof(value) == "number" and value == value
		end
		check(
			number(blocked.degrees) and blocked.degrees > 0 and blocked.degrees < 90,
			"blocked.degrees must sit between 0 and 90 (a velocity more than it off the stick is off it)"
		)
		check(
			number(blocked.settleSeconds) and blocked.settleSeconds >= 0 and blocked.settleSeconds < 1,
			"blocked.settleSeconds must be from 0 to under a second (how long the stick holds still first)"
		)
		check(
			number(blocked.followSeconds) and blocked.followSeconds > 0,
			"blocked.followSeconds must be above 0 (the blocked gait's smoothing time)"
		)
		local slowest = 1
		for _, step in ctx.load("src/shared/data/dev").timeScale.steps do
			slowest = math.min(slowest, step)
		end
		local limit = locomotion.idleSpeedThreshold * slowest
		check(
			number(blocked.matchSpeed) and blocked.matchSpeed >= 0 and blocked.matchSpeed < limit,
			("blocked.matchSpeed must be from 0 to under idleSpeedThreshold at the slowest capture step (%.3f)"):format(
				limit
			)
		)
	end

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
