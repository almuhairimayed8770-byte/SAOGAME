--!strict
--[[
	Validates the wall slam's shake in src/shared/data/fx.luau `wallSlam` (D-296), the numbers
	Replication.slamCue reads when a rush meets a wall near the local player:
	- shakeTier is a tier of combat.luau cameraShakeStuds (the shake's amplitude);
	- shakeRadius is a positive number of studs: past it a slam does not shake the camera;
	- shakeFullRadius is in [0, shakeRadius): the shake is whole up to it and fades by
	  CameraMath.falloff to nothing at shakeRadius, so a slam just inside the radius never shakes as
	  hard as one at the player's feet. At shakeRadius or past it there would be no fade at all.
]]

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value < math.huge and value > -math.huge
end

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "wallSlam: " .. message)
		end
	end

	local fx = ctx.load("src/shared/data/fx")
	local combat = ctx.load("src/shared/data/combat")
	local slam = fx.wallSlam
	if typeof(slam) ~= "table" then
		check(false, "fx.wallSlam is missing")
		return problems
	end

	check(
		typeof(slam.shakeTier) == "string"
			and typeof(combat.cameraShakeStuds) == "table"
			and isNumber(combat.cameraShakeStuds[slam.shakeTier]),
		("shakeTier '%s' must be a tier of combat.cameraShakeStuds"):format(tostring(slam.shakeTier))
	)
	local radiusOk = isNumber(slam.shakeRadius) and slam.shakeRadius > 0
	check(radiusOk, ("shakeRadius (%s) must be a positive number of studs"):format(tostring(slam.shakeRadius)))
	check(
		isNumber(slam.shakeFullRadius)
			and slam.shakeFullRadius >= 0
			and radiusOk
			and slam.shakeFullRadius < slam.shakeRadius,
		("shakeFullRadius (%s) must be in [0, shakeRadius %s): the shake fades from it to nothing at shakeRadius"):format(
			tostring(slam.shakeFullRadius),
			tostring(slam.shakeRadius)
		)
	)

	return problems
end
