--!strict
--[[
	Validates the fixed staged view (CameraController.setStage, CameraMath.StageView.fixed).

	camera.luau stage:
	- fixAfterSeconds is a positive number of seconds under dev.luau capture.countdownSeconds: the
	  view has taken its spot before the take's "go", so it stands still through the whole take.
	- fixStillStuds is a positive number of studs, and a body that drifts fixStillStuds over
	  fixAfterSeconds moves no faster than choreo.luau locomotion.idleSpeedThreshold: what the hold
	  counts as standing, the locomotion counts as standing too, and any walk resets it.

	dev.luau capture.cameras: each view's `fixed` is nil or a boolean.
]]

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function positive(value: any): boolean
	return finite(value) and value > 0
end

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "stageView: " .. message)
		end
	end

	local camera = ctx.load("src/shared/data/camera")
	local dev = ctx.load("src/shared/data/dev")
	local choreo = ctx.load("src/shared/data/choreo")

	local capture = if typeof(dev.capture) == "table" then dev.capture else {}
	local stage = camera.stage
	if typeof(stage) ~= "table" then
		check(false, "camera stage is missing (when a fixed staged view holds its spot)")
	else
		local after, still = stage.fixAfterSeconds, stage.fixStillStuds
		check(positive(after), "stage.fixAfterSeconds must be a positive number of seconds")
		check(positive(still), "stage.fixStillStuds must be a positive number of studs")
		local countdown = capture.countdownSeconds
		if positive(after) and positive(countdown) then
			check(
				after < countdown,
				("stage.fixAfterSeconds %.2f must be under capture.countdownSeconds %.2f: the view holds before the take"):format(
					after,
					countdown
				)
			)
		end
		local locomotion = if typeof(choreo.locomotion) == "table" then choreo.locomotion else {}
		local standing = locomotion.idleSpeedThreshold
		if positive(after) and positive(still) and positive(standing) then
			check(
				still / after <= standing,
				("stage.fixStillStuds %.2f over fixAfterSeconds %.2f is %.2f studs/s, faster than locomotion.idleSpeedThreshold %.2f: a moving body would count as standing"):format(
					still,
					after,
					still / after,
					standing
				)
			)
		end
	end

	local cameras = if typeof(capture.cameras) == "table" then capture.cameras else {}
	for name, view in cameras do
		if typeof(view) == "table" then
			check(
				view.fixed == nil or typeof(view.fixed) == "boolean",
				("capture.cameras.%s.fixed must be true, false or left out"):format(tostring(name))
			)
		end
	end

	return problems
end
