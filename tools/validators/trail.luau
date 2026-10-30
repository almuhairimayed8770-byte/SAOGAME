--!strict
--[[
	Validates the ribbon's window close, edge-on width and owner attribute in data/fx.luau
	trail.ribbon (D-360, D-361, D-362):

	- closeSeconds is a number from 0 up to under trail.lifetime: when a trail goes out, every
	  sample on the ribbon fades out over it and goes, so a window's arc is gone before the next
	  window lights. It must also fit, with one frame (choreo.frameSeconds) to spare, in every gap a
	  clip leaves between two lit spans of its trail, so the gap shows a clear frame. A clip's trail
	  is lit while a window is on (TrailOn or HitWindowOpen turn it on; HitWindowClose, TrailOff or
	  PostMotionStart turn it off) or a smear is on (SmearOn to SmearOff), the way Replication
	  routes the events to Trails.setActive. An off and an on at the same time leave no gap;
	- edgeOn is a table { edgeAt, fullAt, minShare }: 0 <= edgeAt < fullAt <= 1 (facing is |cos|
	  of the angle between the swept sheet's normal and the line to the camera) and
	  0 < minShare <= 1 (the share of full width a cut seen edge-on keeps);
	- ownerAttribute is a non-empty string: the attribute on a ribbon's host that names the rig it
	  draws now (D-362), so a per-frame log tells the player's ribbon from an enemy's.

	tests/client/TrailWindows.spec.luau plays the clips through the real Trails module and measures
	both on screen.
]]

local CLIPS_DIRECTORY = "src/shared/clips"
local EPSILON = 1e-6

local ON_WINDOW: { [string]: boolean } = { TrailOn = true, HitWindowOpen = true }
local OFF_WINDOW: { [string]: boolean } = { HitWindowClose = true, TrailOff = true, PostMotionStart = true }

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value
end

-- Every gap (seconds) between two lit spans of the clip's trail, with the time it starts.
local function gapsOf(clip: any): { { from: number, seconds: number } }
	local gaps = {}
	if typeof(clip) ~= "table" or typeof(clip.events) ~= "table" then
		return gaps
	end
	local window = false
	local smear = false
	local offAt: number? = nil
	for _, event in clip.events do
		if typeof(event) == "table" and isNumber(event.time) then
			local wasLit = window or smear
			local kind = event.kind
			if ON_WINDOW[kind] then
				window = true
			elseif OFF_WINDOW[kind] then
				window = false
			elseif kind == "SmearOn" then
				smear = true
			elseif kind == "SmearOff" then
				smear = false
			end
			local lit = window or smear
			if wasLit and not lit then
				offAt = event.time
			elseif lit and not wasLit and offAt ~= nil then
				local seconds = event.time - (offAt :: number)
				if seconds > EPSILON then
					table.insert(gaps, { from = offAt :: number, seconds = seconds })
				end
				offAt = nil
			end
		end
	end
	return gaps
end

return function(ctx: any): { string }
	local problems = {}
	local function problem(message: string, ...: any)
		table.insert(problems, "trail: " .. message:format(...))
	end

	local trail = ctx.load("src/shared/data/fx").trail
	local ribbon = if typeof(trail) == "table" then trail.ribbon else nil
	if typeof(ribbon) ~= "table" then
		problem("fx.trail.ribbon must be a table")
		return problems
	end

	local close = ribbon.closeSeconds
	if not isNumber(close) or close < 0 then
		problem("ribbon.closeSeconds must be a number of seconds, 0 or more (the fade after a window goes out)")
	elseif not isNumber(trail.lifetime) or close >= trail.lifetime then
		problem(
			"ribbon.closeSeconds (%.3f) must be under trail.lifetime (%s): the close cuts a sample's life short",
			close,
			tostring(trail.lifetime)
		)
	else
		local frame = ctx.load("src/shared/data/choreo").frameSeconds
		if not isNumber(frame) or frame <= 0 then
			problem("choreo.frameSeconds must be a number above 0")
			frame = 0
		end
		for _, path in ctx.listFiles(CLIPS_DIRECTORY, "%.luau$") do
			local id = path:match("^" .. CLIPS_DIRECTORY .. "/(.-)%.luau$")
			if id ~= nil then
				local ok, clip = pcall(ctx.load, CLIPS_DIRECTORY .. "/" .. id)
				if ok then
					for _, gap in gapsOf(clip) do
						if close + frame > gap.seconds + EPSILON then
							problem(
								"%s: the gap at %.4f between two lit spans is %.3f s; ribbon.closeSeconds (%.3f) plus a frame (%.4f) must fit in it, so the gap shows a clear frame",
								id,
								gap.from,
								gap.seconds,
								close,
								frame
							)
						end
					end
				end
			end
		end
	end

	local edgeOn = ribbon.edgeOn
	if typeof(edgeOn) ~= "table" then
		problem("ribbon.edgeOn must be a table { edgeAt, fullAt, minShare }")
	else
		local edgeAt, fullAt, minShare = edgeOn.edgeAt, edgeOn.fullAt, edgeOn.minShare
		if not (isNumber(edgeAt) and isNumber(fullAt) and edgeAt >= 0 and edgeAt < fullAt and fullAt <= 1) then
			problem(
				"ribbon.edgeOn needs 0 <= edgeAt < fullAt <= 1 (facings, |cos| of the angle to the camera); got %s, %s",
				tostring(edgeAt),
				tostring(fullAt)
			)
		end
		if not (isNumber(minShare) and minShare > 0 and minShare <= 1) then
			problem(
				"ribbon.edgeOn.minShare must be above 0 and at most 1 (the share of full width a cut seen edge-on keeps); got %s",
				tostring(minShare)
			)
		end
	end

	local owner = ribbon.ownerAttribute
	if typeof(owner) ~= "string" or owner == "" then
		problem(
			"ribbon.ownerAttribute must be a non-empty string (the host attribute that names the rig a ribbon draws); got %s",
			tostring(owner)
		)
	end

	return problems
end
